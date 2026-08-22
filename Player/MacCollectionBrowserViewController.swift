// ∅ 2026 lil org

import Cocoa

final class MacCollectionBrowserViewController: NSViewController,
    MacNavigationScreen,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate {

    private static let boundaryEpsilon: CGFloat = 0.75
    private static let focusPublicationInterval: CFTimeInterval = 1 / 12
    private static let settleDelay: TimeInterval = 0.12

    private struct ThumbnailWindowRequest: Equatable {
        let tokenIndex: Int
        let direction: DownloadableMediaCache.PrefetchDirection
        let prefetchStride: Int
    }

    let session: MacPlayerSession

    var onSelection: ((MacPlayerBrowserItemSnapshot) -> Void)?
    var onFocusedTokenIndex: ((Int?) -> Void)?

    private let model: MacNavigationModel
    private let ownerId = UUID()
    private let snapshot: PlayerCollectionBrowseSnapshot
    private let browserLayout = MacCollectionBrowserLayout()
    private let scrollView = MacCollectionBrowserScrollView()
    private let collectionView = MacCollectionBrowserCollectionView()

    private var layoutAspectProfile: MobilePlayerBrowserAspectProfile
    private var descriptorCache = [Int: CollectionCatalogDownloadableMediaDescriptor]()
    private var publicationState: PlayerCollectionScrollPublicationState?
    private var focusedTokenIndex: Int? {
        didSet {
            guard focusedTokenIndex != oldValue, isViewLoaded else { return }
            updateFocusRing(at: oldValue)
            updateFocusRing(at: focusedTokenIndex)
        }
    }
    private var lastPublishedFocusTime: CFTimeInterval?
    private var lastEmittedFocusedTokenIndex: Int?
    private var pendingFocusedTokenIndex: Int?
    private var isFocusPublicationScheduled = false
    private var focusPublicationTask: Task<Void, Never>?
    private var lastViewportSize = CGSize.zero
    private var lastDisplayScale: CGFloat = 0
    private var isApplyingPosition = false
    private var lastScrollOffsetY: CGFloat?
    private var lastPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    private var lastThumbnailWindowRequest: ThumbnailWindowRequest?
    private var pendingInitialTokenIndex: Int?
    private var settleTask: Task<Void, Never>?
    private var settleRequestId: UUID?
    private var isActive = false
    private var isPreparedForIncomingTransition = false

    private var allowsThumbnailDemand: Bool {
        isActive || isPreparedForIncomingTransition
    }

    var focusedTokenContext: PlayerTokenContext? {
        guard let focusedTokenIndex,
              (0..<snapshot.itemCount).contains(focusedTokenIndex),
              CollectionCatalog.canGenerateToken(
                specificCollectionId: snapshot.collectionId,
                tokenIndex: focusedTokenIndex
              ) else {
            return nil
        }
        return PlayerTokenContext(
            collectionId: snapshot.collectionId,
            tokenIndex: focusedTokenIndex,
            tokenCount: snapshot.itemCount
        )
    }

    fileprivate var allowsUserInteraction: Bool {
        isActive
            && model.session?.id == session.id
            && model.commands?.isNavigationTransitionInFlight != true
    }

    init(session: MacPlayerSession, model: MacNavigationModel) {
        self.session = session
        self.model = model
        let itemCount = max(session.tokenCount, 0)
        self.snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: session.collectionId,
            itemCount: itemCount,
            initialTokenIndex: min(max(session.initialTokenIndex, 0), max(itemCount - 1, 0))
        )
        self.layoutAspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 0,
            uniformImageSize: CGSize(width: 1, height: 1)
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        focusPublicationTask?.cancel()
        settleTask?.cancel()
        DownloadableMediaCache.shared.clearActiveWindow(ownerId: ownerId)
    }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MacPlayerBackgroundColor
            .color(forCollectionId: session.collectionId).cgColor
        view.setAccessibilityHidden(true)
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.collectionViewLayout = browserLayout
        collectionView.owner = self
        scrollView.owner = self
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            MacCollectionBrowserItem.self,
            forItemWithIdentifier: MacCollectionBrowserItem.identifier
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = collectionView
        updateScrollerInteractionAvailability()
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBackingPropertiesDidChange(_:)),
            name: NSWindow.didChangeBackingPropertiesNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadableMediaCacheFileAvailabilityDidChange(_:)),
            name: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
        )

        let restorationIndex = PlayerCollectionScrollPolicy.restorationIndex(
            savedIndex: snapshot.initialTokenIndex,
            itemCount: snapshot.itemCount
        )
        publicationState = restorationIndex.map {
            PlayerCollectionScrollPublicationState(initialIndex: $0)
        }
        focusedTokenIndex = restorationIndex
        pendingInitialTokenIndex = restorationIndex
        updateLayoutAspectProfile(sampledAround: restorationIndex)
        collectionView.reloadData()
    }

    @objc private func scrollViewBoundsDidChange() {
        handleScroll()
    }

    @objc private func windowBackingPropertiesDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === view.window else {
            return
        }
        configureLayoutIfNeeded()
    }

    @objc private func downloadableMediaCacheFileAvailabilityDidChange(_ notification: Notification) {
        guard allowsThumbnailDemand else { return }
        guard DownloadableMediaCache.shared.fileAvailabilityChange(
            notification,
            affectsCollection: snapshot.collectionId
        ) else {
            return
        }
        refreshVisibleThumbnails(affectedBy: notification)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        configureLayoutIfNeeded()
        updateScrollerInteractionAvailability()
    }

    // MARK: - MacNavigationScreen

    func navigationScreenDidBecomeActive() {
        guard model.session?.id == session.id else { return }
        isPreparedForIncomingTransition = false
        isActive = true
        updateScrollerInteractionAvailability()
        view.setAccessibilityHidden(false)
        configureLayoutIfNeeded()
        applyPendingInitialPositionIfNeeded()
        lastScrollOffsetY = scrollView.contentView.bounds.minY
        publishFocus(force: true)
        prepareThumbnailWindow(force: false)
        refreshVisibleThumbnails()
        scheduleSettle()
        view.window?.makeFirstResponder(collectionView)
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.isActive == true else { return }
            self?.updateScrollerInteractionAvailability()
        }
    }

    func navigationScreenDidResignActive() {
        guard isActive else { return }
        isActive = false
        updateScrollerInteractionAvailability()
        view.setAccessibilityHidden(true)
        settleRequestId = nil
        settleTask?.cancel()
        settleTask = nil
        pendingFocusedTokenIndex = nil
        flushSettledPosition()
    }

    func navigationScreenDidMoveOffstage() {
        isPreparedForIncomingTransition = false
        updateScrollerInteractionAvailability()
        cancelVisibleThumbnailLoads()
        DownloadableMediaCache.shared.suspendActiveWindow(ownerId: ownerId)
    }

    func prepareForIncomingTransition() {
        guard !isActive else { return }
        isPreparedForIncomingTransition = true
        updateScrollerInteractionAvailability()
        prepareThumbnailWindow(force: true)
        refreshVisibleThumbnails()
    }

    // MARK: - Positioning

    func scroll(toTokenIndex tokenIndex: Int, animated: Bool) {
        guard isViewLoaded else {
            pendingInitialTokenIndex = tokenIndex
            return
        }
        configureLayoutIfNeeded()
        guard let layout = browserLayout.browserLayout,
              let itemFrame = layout.itemFrame(at: tokenIndex) else {
            pendingInitialTokenIndex = tokenIndex
            return
        }

        let isFullyVisible = PlayerCollectionScrollPolicy.isItemFullyVisible(
            frame: itemFrame,
            viewport: scrollView.contentView.bounds,
            epsilon: Self.boundaryEpsilon
        )
        if !isFullyVisible {
            let origin = CGPoint(
                x: 0,
                y: contentOffsetY(centeringItemFrame: itemFrame, in: layout)
            )
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    scrollView.contentView.animator().setBoundsOrigin(origin)
                }
            } else {
                scrollView.contentView.setBoundsOrigin(origin)
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        focusedTokenIndex = tokenIndex
        publishFocus(force: true)
        prepareThumbnailWindow(force: false)
    }

    /// Where a token's artwork sits on screen, in window coordinates. This is the
    /// media rect rather than the whole cell, so the hero card lands on the picture
    /// and not on the letterbox margins around it.
    func itemFrameInWindow(tokenIndex: Int) -> CGRect? {
        guard let layout = browserLayout.browserLayout,
              let itemFrame = layout.itemFrame(at: tokenIndex) else {
            return nil
        }
        guard let descriptor = descriptor(for: tokenIndex) else {
            return collectionView.convert(itemFrame, to: nil)
        }
        // Use the descriptor's declared size, not the decoded image, so the rect is
        // available before the thumbnail has loaded.
        let mediaRect = MacPlayerCardGeometry.expandedFrame(
            for: PlayerCollectionBrowserSupport.fallbackImageSize(for: descriptor),
            in: itemFrame
        )
        return collectionView.convert(mediaRect, to: nil)
    }

    func thumbnailImage(tokenIndex: Int) -> NSImage? {
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        if let image = (collectionView.item(at: indexPath) as? MacCollectionBrowserItem)?
            .displayedImage {
            return image
        }
        guard let descriptor = descriptor(for: tokenIndex) else { return nil }
        return DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor)
    }

    func usesNativeMetalCardCornerMask(tokenIndex: Int) -> Bool {
        descriptor(for: tokenIndex)?.usesNativeMetalCardPresentation == true
    }

    func setItemHidden(_ isHidden: Bool, tokenIndex: Int) {
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        (collectionView.item(at: indexPath) as? MacCollectionBrowserItem)?.view.isHidden = isHidden
    }

    // MARK: - Layout

    private func configureLayoutIfNeeded() {
        let viewportSize = scrollView.contentView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let displayScale = currentLayoutDisplayScale
        let displayScaleChanged = lastDisplayScale > 0
            && lastDisplayScale != displayScale

        let transition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: lastViewportSize,
            viewportSize: viewportSize,
            needsGeometryRefresh: displayScaleChanged,
            displayScale: displayScale,
            aspectProfile: layoutAspectProfile,
            forcedTokenIndex: pendingInitialTokenIndex,
            focusedTokenIndex: focusedTokenIndex
        )
        guard transition.needsLayout, let layout = transition.layout else { return }

        let isFirstLayout = transition.needsInitialLayout
        let wasApplyingPosition = isApplyingPosition
        isApplyingPosition = true
        lastViewportSize = viewportSize
        lastDisplayScale = displayScale
        browserLayout.browserLayout = layout
        collectionView.frame = CGRect(origin: .zero, size: layout.contentSize)
        if isFirstLayout {
            collectionView.reloadData()
        }

        if let retainedFocusTokenIndex = transition.retainedFocusTokenIndex {
            pendingInitialTokenIndex = retainedFocusTokenIndex
        }
        applyPendingInitialPositionIfNeeded()
        lastScrollOffsetY = scrollView.contentView.bounds.minY
        isApplyingPosition = wasApplyingPosition

        if allowsThumbnailDemand {
            prepareThumbnailWindow(force: false)
        }
        if isActive {
            publishFocus(force: false)
            scheduleSettle()
        }
    }

    private var currentLayoutDisplayScale: CGFloat {
        let scale = view.window?.backingScaleFactor
            ?? parent?.view.window?.backingScaleFactor
            ?? 2
        return scale.isFinite && scale > 0 ? scale : 2
    }

    private func applyPendingInitialPositionIfNeeded() {
        guard let tokenIndex = pendingInitialTokenIndex,
              let layout = browserLayout.browserLayout,
              let itemFrame = layout.itemFrame(at: tokenIndex) else {
            return
        }
        pendingInitialTokenIndex = nil

        guard scrollView.contentView.bounds.height > 0 else {
            pendingInitialTokenIndex = tokenIndex
            return
        }
        let wasApplyingPosition = isApplyingPosition
        isApplyingPosition = true
        let targetY = contentOffsetY(centeringItemFrame: itemFrame, in: layout)
        scrollView.contentView.setBoundsOrigin(CGPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        lastScrollOffsetY = scrollView.contentView.bounds.minY
        isApplyingPosition = wasApplyingPosition
        focusedTokenIndex = tokenIndex
        publicationState?.finishInitialPositioning()
    }

    // MARK: - Focal geometry

    /// The scroll offset that puts `itemFrame` under the focal point. Uses the shared
    /// focal model so it inverts `focalPoint(at:)` exactly — centring naively would
    /// make a first- or last-row token immediately re-resolve to a different index.
    private func contentOffsetY(
        centeringItemFrame itemFrame: CGRect,
        in layout: MobilePlayerBrowserLayout
    ) -> CGFloat {
        if let focalGeometry {
            return focalGeometry.contentOffsetY(anchoringFocalY: itemFrame.midY)
        }
        let viewportHeight = scrollView.contentView.bounds.height
        let maximumY = max(layout.contentSize.height - viewportHeight, 0)
        return min(max(itemFrame.midY - viewportHeight / 2, 0), maximumY)
    }

    /// Mirrors the iOS browser's focal model: near the scroll extremes the focal point
    /// travels to the first/last item's centre, because the viewport centre can never
    /// sit on the first or last row.
    private var focalGeometry: PlayerCollectionScrollFocalGeometry? {
        guard let layout = browserLayout.browserLayout,
              layout.itemCount > 0,
              layout.columnCount > 0,
              let firstItemFrame = layout.itemFrame(at: 0),
              let lastItemFrame = layout.itemFrame(at: layout.itemCount - 1) else {
            return nil
        }

        let viewport = scrollView.contentView.bounds
        guard viewport.width > 0, viewport.height > 0 else { return nil }

        let lastRowFirstIndex = ((layout.itemCount - 1) / layout.columnCount) * layout.columnCount
        let lastRowFocalEntryY: CGFloat
        if lastRowFirstIndex > 0,
           let previousRowFrame = layout.itemFrame(at: lastRowFirstIndex - layout.columnCount) {
            lastRowFocalEntryY = (previousRowFrame.midY + lastItemFrame.midY) / 2
        } else {
            lastRowFocalEntryY = firstItemFrame.midY
        }

        return PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: 0,
            maximumOffsetY: max(layout.contentSize.height - viewport.height, 0),
            viewportHeight: viewport.height,
            viewportCenterX: viewport.midX,
            firstItemCenter: CGPoint(x: firstItemFrame.midX, y: firstItemFrame.midY),
            lastItemCenter: CGPoint(x: lastItemFrame.midX, y: lastItemFrame.midY),
            lastRowFocalEntryY: lastRowFocalEntryY
        )
    }

    private func updateLayoutAspectProfile(sampledAround focusedTokenIndex: Int?) {
        let defaultSize = CGSize(width: 1, height: 1)
        guard snapshot.itemCount > 0 else {
            layoutAspectProfile = MobilePlayerBrowserAspectProfile(
                itemCount: 0,
                uniformImageSize: defaultSize
            )
            return
        }

        let columnCount = CollectionCatalog.desktopCollectionBrowseColumnCount(
            specificCollectionId: snapshot.collectionId
        )
        if let profile = CollectionCatalog.collectionBrowseThumbnailAspectRatioProfile(
            specificCollectionId: snapshot.collectionId
        ), profile.isCompatible(withItemCount: snapshot.itemCount) {
            switch profile {
            case let .uniform(aspectRatio):
                layoutAspectProfile = MobilePlayerBrowserAspectProfile(
                    itemCount: snapshot.itemCount,
                    uniformImageSize: aspectRatio.size,
                    columnCount: columnCount
                )
            case let .variable(aspectRatios):
                layoutAspectProfile = MobilePlayerBrowserAspectProfile(
                    heightToWidthRatios: aspectRatios.map {
                        CGFloat($0.height) / CGFloat($0.width)
                    },
                    columnCount: columnCount
                )
            }
            return
        }

        let sampleCount = min(snapshot.itemCount, MobilePlayerBrowserLayout.maximumAspectSampleCount)
        let focus = min(max(focusedTokenIndex ?? snapshot.initialTokenIndex, 0), snapshot.itemCount - 1)
        let firstIndex = min(max(focus - sampleCount / 2, 0), snapshot.itemCount - sampleCount)
        let sampleSizes = (firstIndex..<(firstIndex + sampleCount)).compactMap { tokenIndex -> CGSize? in
            guard let descriptor = descriptor(for: tokenIndex) else { return nil }
            let size = PlayerCollectionBrowserSupport.fallbackImageSize(for: descriptor)
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                return nil
            }
            return size
        }
        let layoutFallbackSize = sampleSizes.max { $0.height / $0.width < $1.height / $1.width }
            ?? defaultSize
        layoutAspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: snapshot.itemCount,
            uniformImageSize: layoutFallbackSize,
            columnCount: columnCount
        )
    }

    // MARK: - Scrolling

    private func handleScroll() {
        guard isViewLoaded else { return }
        let offsetY = scrollView.contentView.bounds.minY
        let previousOffsetY = lastScrollOffsetY
        lastScrollOffsetY = offsetY
        guard allowsUserInteraction, !isApplyingPosition else { return }

        if let previousOffsetY,
           let layout = browserLayout.browserLayout {
            let maximumOffsetY = max(
                layout.contentSize.height - scrollView.contentView.bounds.height,
                0
            )
            let offsetDelta = PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
                previousOffsetY: previousOffsetY,
                currentOffsetY: offsetY,
                validRange: 0...maximumOffsetY
            )
            if abs(offsetDelta) > Self.boundaryEpsilon {
                lastPrefetchDirection = offsetDelta > 0 ? .forward : .backward
            }
        }

        updateFocusedTokenIndex()
        publishFocus(force: false)
        prepareThumbnailWindow(force: false)
        scheduleSettle()
    }

    private func updateFocusedTokenIndex() {
        guard let layout = browserLayout.browserLayout, layout.itemCount > 0 else { return }
        let viewport = scrollView.contentView.bounds
        let visibleItems = layout.candidateItemIndices(intersecting: viewport).compactMap { index in
            layout.itemFrame(at: index).map { PlayerCollectionVisibleItem(index: index, frame: $0) }
        }
        let focalPoint = focalGeometry?.focalPoint(at: viewport.minY)
            ?? CGPoint(x: viewport.midX, y: viewport.midY)
        let candidateIndex = PlayerCollectionScrollPolicy.anchorIndex(
            visibleItems: visibleItems,
            focalPoint: focalPoint,
            itemCount: layout.itemCount
        )
        focusedTokenIndex = PlayerCollectionScrollPolicy.resolvedAnchorIndex(
            retainedIndex: nil,
            candidateIndex: candidateIndex,
            itemCount: layout.itemCount,
            configuredColumnCount: layout.columnCount
        )
        if let focusedTokenIndex {
            publicationState?.observeCandidate(focusedTokenIndex)
        }
    }

    /// Rate-limits focus changes to `focusPublicationInterval`, with a trailing
    /// emission so the index a scroll settles on is never dropped. Each published
    /// index rebuilds the toolbar, so per-frame emission during a fling is costly.
    private func publishFocus(force: Bool) {
        guard let focusedTokenIndex else { return }
        guard force || lastEmittedFocusedTokenIndex != focusedTokenIndex else { return }

        let now = CACurrentMediaTime()
        if !force, let lastPublishedFocusTime {
            let elapsed = now - lastPublishedFocusTime
            if elapsed < Self.focusPublicationInterval {
                schedulePendingFocusPublication(
                    tokenIndex: focusedTokenIndex,
                    after: Self.focusPublicationInterval - elapsed
                )
                return
            }
        }
        emitFocus(tokenIndex: focusedTokenIndex, at: now)
    }

    private func schedulePendingFocusPublication(tokenIndex: Int, after delay: CFTimeInterval) {
        pendingFocusedTokenIndex = tokenIndex
        guard !isFocusPublicationScheduled else { return }
        isFocusPublicationScheduled = true
        focusPublicationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(delay, 0)))
            } catch {
                return
            }
            guard let self else { return }
            self.isFocusPublicationScheduled = false
            self.focusPublicationTask = nil
            guard let pendingFocusedTokenIndex = self.pendingFocusedTokenIndex else { return }
            self.pendingFocusedTokenIndex = nil
            guard pendingFocusedTokenIndex != self.lastEmittedFocusedTokenIndex else { return }
            self.emitFocus(tokenIndex: pendingFocusedTokenIndex, at: CACurrentMediaTime())
        }
    }

    private func emitFocus(tokenIndex: Int, at time: CFTimeInterval) {
        pendingFocusedTokenIndex = nil
        lastPublishedFocusTime = time
        lastEmittedFocusedTokenIndex = tokenIndex
        onFocusedTokenIndex?(tokenIndex)
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        let requestId = UUID()
        settleRequestId = requestId
        settleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.settleDelay))
            } catch {
                return
            }
            guard let self,
                  self.isActive,
                  self.settleRequestId == requestId else {
                return
            }
            self.settleRequestId = nil
            self.settleTask = nil
            self.flushSettledPosition()
        }
    }

    private func flushSettledPosition() {
        guard let focusedTokenIndex,
              var publicationState,
              let layout = browserLayout.browserLayout else {
            return
        }

        let viewport = scrollView.contentView.bounds
        let maximumContentOffsetY = max(layout.contentSize.height - viewport.height, 0)
        let hasViewedToEnd = layout.itemFrame(at: layout.itemCount - 1).map {
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: $0,
                viewport: viewport,
                maximumContentOffsetY: maximumContentOffsetY,
                epsilon: Self.boundaryEpsilon
            )
        } ?? false

        publicationState.observeCandidate(focusedTokenIndex)
        let publication = publicationState.settle(hasViewedToEnd: hasViewedToEnd)
        self.publicationState = publicationState
        guard let publication else { return }
        let playerModel = session.playerModel
        let collectionId = snapshot.collectionId
        guard let progress = playerModel.viewingProgress(
            collectionId: collectionId,
            tokenIndex: publication.tokenIndex,
            hasViewedToEnd: publication.hasViewedToEnd
        ) else {
            return
        }
        PlayerPersistenceUpdates.enqueue {
            await playerModel.markViewed(progress)
        }
    }

    // MARK: - Thumbnails

    private func descriptor(for tokenIndex: Int) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard (0..<snapshot.itemCount).contains(tokenIndex) else { return nil }
        if let cached = descriptorCache[tokenIndex] {
            return cached
        }
        guard let descriptor = CollectionCatalog.collectionBrowseThumbnailDescriptor(
            specificCollectionId: snapshot.collectionId,
            tokenIndex: tokenIndex
        ), PlayerCollectionBrowserSupport.isAvailable(for: descriptor) else {
            return nil
        }
        descriptorCache[tokenIndex] = descriptor
        return descriptor
    }

    private func prepareThumbnailWindow(force: Bool) {
        guard allowsThumbnailDemand, let focusedTokenIndex else { return }
        let prefetchStride = browserLayout.browserLayout?.prefetchStride
            ?? MobilePlayerBrowserLayout.defaultColumnCount
        let request = ThumbnailWindowRequest(
            tokenIndex: focusedTokenIndex,
            direction: lastPrefetchDirection,
            prefetchStride: prefetchStride
        )
        if !force, lastThumbnailWindowRequest == request {
            return
        }
        if !force,
           let lastThumbnailWindowRequest,
           lastThumbnailWindowRequest.direction == request.direction,
           lastThumbnailWindowRequest.prefetchStride == request.prefetchStride,
           abs(lastThumbnailWindowRequest.tokenIndex - request.tokenIndex) < prefetchStride {
            return
        }
        lastThumbnailWindowRequest = request

        guard let window = PlayerCollectionBrowseMediaWindowLayout.makeWindow(
            centeredAt: focusedTokenIndex,
            itemCount: snapshot.itemCount,
            direction: lastPrefetchDirection,
            prefetchStride: prefetchStride,
            descriptorForTokenIndex: { descriptor(for: $0) }
        ) else {
            DownloadableMediaCache.shared.clearActiveWindow(ownerId: ownerId)
            return
        }
        DownloadableMediaCache.shared.prepareWindow(
            window,
            ownerId: ownerId,
            ownership: .cooperative(.macCollectionBrowser)
        )
    }

    private func refreshVisibleThumbnails(affectedBy notification: Notification? = nil) {
        guard allowsThumbnailDemand else { return }
        for indexPath in collectionView.indexPathsForVisibleItems() {
            if let notification {
                guard let descriptor = descriptor(for: indexPath.item),
                      DownloadableMediaCache.shared.fileAvailabilityChange(
                        notification,
                        affects: descriptor
                      ) else {
                    continue
                }
            }
            guard let item = collectionView.item(at: indexPath) as? MacCollectionBrowserItem else { continue }
            item.refreshImageIfNeeded()
        }
    }

    private func cancelVisibleThumbnailLoads() {
        collectionView.visibleItems()
            .compactMap { $0 as? MacCollectionBrowserItem }
            .forEach { $0.cancelImageLoad() }
    }

    private func accessibilityLabel(tokenIndex: Int) -> String {
        let position = Strings.pagePosition(
            current: tokenIndex + 1,
            total: max(snapshot.itemCount, tokenIndex + 1)
        )
        let collectionName = session.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return collectionName.isEmpty ? position : "\(collectionName), \(position)"
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        snapshot.itemCount
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: MacCollectionBrowserItem.identifier,
            for: indexPath
        )
        guard let browserItem = item as? MacCollectionBrowserItem else { return item }
        let tokenIndex = indexPath.item
        browserItem.configure(
            tokenIndex: tokenIndex,
            descriptor: descriptor(for: tokenIndex),
            accessibilityLabel: accessibilityLabel(tokenIndex: tokenIndex),
            allowsImageLoading: allowsThumbnailDemand
        ) { [weak self] in
            self?.select(tokenIndex: tokenIndex)
        }
        browserItem.isFocused = indexPath.item == focusedTokenIndex
        return browserItem
    }

    // MARK: - NSCollectionViewDelegate

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        collectionView.deselectItems(at: indexPaths)
        guard let tokenIndex = indexPaths.first?.item else { return }
        select(tokenIndex: tokenIndex)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard allowsThumbnailDemand else { return }
        (item as? MacCollectionBrowserItem)?.resumeImageLoadIfNeeded(
            tokenIndex: indexPath.item
        )
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        (item as? MacCollectionBrowserItem)?.cancelImageLoad(
            ifRepresenting: indexPath.item
        )
    }

    func select(tokenIndex: Int) {
        guard allowsUserInteraction,
              (0..<snapshot.itemCount).contains(tokenIndex) else {
            return
        }
        focusedTokenIndex = tokenIndex
        publishFocus(force: true)
        guard let snapshot = makeItemSnapshot(tokenIndex: tokenIndex) else { return }
        onSelection?(snapshot)
        updateScrollerInteractionAvailability()
    }

    private func makeItemSnapshot(tokenIndex: Int) -> MacPlayerBrowserItemSnapshot? {
        guard let frameInWindow = itemFrameInWindow(tokenIndex: tokenIndex) else { return nil }
        return MacPlayerBrowserItemSnapshot(
            tokenIndex: tokenIndex,
            frameInWindow: frameInWindow,
            image: thumbnailImage(tokenIndex: tokenIndex),
            usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask(tokenIndex: tokenIndex)
        )
    }

    // MARK: - Keyboard

    /// Moves the focused item without touching NSCollectionView's selection — a
    /// selection change here would open an item, which is not what an arrow key means.
    fileprivate func moveFocus(by offset: Int) {
        guard allowsUserInteraction, snapshot.itemCount > 0 else { return }
        let current = focusedTokenIndex ?? 0
        let target = min(max(current + offset, 0), snapshot.itemCount - 1)
        guard target != current else { return }
        focusFor(tokenIndex: target)
    }

    fileprivate func moveFocusVertically(byRows rowOffset: Int) {
        guard allowsUserInteraction else { return }
        let current = focusedTokenIndex ?? 0
        guard let target = PlayerCollectionScrollPolicy.verticalNavigationIndex(
            currentIndex: current,
            itemCount: snapshot.itemCount,
            columnCount: focusedColumnCount,
            rowOffset: rowOffset
        ), target != current else {
            return
        }
        focusFor(tokenIndex: target)
    }

    fileprivate func moveFocusToRow(_ row: FocusRow) {
        guard allowsUserInteraction, snapshot.itemCount > 0 else { return }
        focusFor(tokenIndex: row == .first ? 0 : snapshot.itemCount - 1)
    }

    fileprivate var focusedColumnCount: Int {
        browserLayout.browserLayout?.columnCount ?? MobilePlayerBrowserLayout.defaultColumnCount
    }

    fileprivate var visibleRowCount: Int {
        max(browserLayout.browserLayout?.visibleRowCount ?? 1, 1)
    }

    fileprivate func openFocusedItem() {
        guard allowsUserInteraction, let focusedTokenIndex else { return }
        select(tokenIndex: focusedTokenIndex)
    }

    fileprivate enum FocusRow {
        case first, last
    }

    private func focusFor(tokenIndex: Int) {
        scroll(toTokenIndex: tokenIndex, animated: false)
    }

    private func updateFocusRing(at tokenIndex: Int?) {
        guard let tokenIndex else { return }
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        (collectionView.item(at: indexPath) as? MacCollectionBrowserItem)?
            .isFocused = tokenIndex == focusedTokenIndex
    }

    fileprivate func navigateBack() {
        guard allowsUserInteraction else { return }
        model.goBack()
        updateScrollerInteractionAvailability()
    }

    override func cancelOperation(_ sender: Any?) {
        navigateBack()
    }

    private func updateScrollerInteractionAvailability() {
        let isEnabled = allowsUserInteraction
        guard let verticalScroller = scrollView.verticalScroller,
              verticalScroller.isEnabled != isEnabled else {
            return
        }
        verticalScroller.isEnabled = isEnabled
    }

    // MARK: - Context menu

    fileprivate func contextMenu(forTokenIndex tokenIndex: Int) -> NSMenu? {
        guard allowsUserInteraction,
              descriptor(for: tokenIndex) != nil,
              !snapshot.collectionId.isEmpty,
              let token = CollectionCatalog.generateToken(
                specificCollectionId: snapshot.collectionId,
                tokenIndex: tokenIndex
              ),
              !token.id.isEmpty else {
            return nil
        }

        // Keep the window title and the menu's target on the same item.
        focusedTokenIndex = tokenIndex
        publishFocus(force: true)

        let menu = NSMenu(title: token.displayName)
        menu.autoenablesItems = false

        let bookmarkState = PlayerBookmarksStore.storedBookmarkState(
            collectionId: token.fullCollectionId,
            tokenId: token.id
        )
        let bookmarkItem = NSMenuItem(
            title: bookmarkState.isBookmarked ? Strings.removeBookmark : Strings.bookmark,
            action: #selector(toggleBookmarkForMenuItem(_:)),
            keyEquivalent: ""
        )
        bookmarkItem.target = self
        bookmarkItem.representedObject = MacCollectionBrowserBookmarkAction(
            tokenIndex: tokenIndex,
            isBookmarked: !bookmarkState.isBookmarked
        )
        bookmarkItem.isEnabled = bookmarkState.isReady && !bookmarkState.isTogglePending
        menu.addItem(bookmarkItem)

        if token.url != nil {
            menu.addItem(.separator())
            let viewOnWebItem = NSMenuItem(
                title: Strings.viewOnBlockExplorer,
                action: #selector(viewOnBlockExplorerForMenuItem(_:)),
                keyEquivalent: ""
            )
            viewOnWebItem.target = self
            viewOnWebItem.representedObject = tokenIndex
            menu.addItem(viewOnWebItem)
        }
        return menu
    }

    @objc private func toggleBookmarkForMenuItem(_ sender: NSMenuItem) {
        guard allowsUserInteraction,
              let action = sender.representedObject as? MacCollectionBrowserBookmarkAction,
              let token = CollectionCatalog.generateToken(
                specificCollectionId: snapshot.collectionId,
                tokenIndex: action.tokenIndex
              ),
              !token.fullCollectionId.isEmpty,
              !token.id.isEmpty else {
            return
        }
        PlayerBookmarksStore.enqueueBookmarkUpdate(
            collectionId: token.fullCollectionId,
            tokenId: token.id,
            isBookmarked: action.isBookmarked
        )
    }

    @objc private func viewOnBlockExplorerForMenuItem(_ sender: NSMenuItem) {
        guard allowsUserInteraction,
              let tokenIndex = sender.representedObject as? Int,
              let url = CollectionCatalog.generateToken(
                specificCollectionId: snapshot.collectionId,
                tokenIndex: tokenIndex
              )?.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

}

private struct MacCollectionBrowserBookmarkAction {
    let tokenIndex: Int
    let isBookmarked: Bool
}

private final class MacCollectionBrowserScrollView: NSScrollView {

    weak var owner: MacCollectionBrowserViewController?

    override func scrollWheel(with event: NSEvent) {
        guard let owner else {
            super.scrollWheel(with: event)
            return
        }
        guard owner.allowsUserInteraction else { return }
        super.scrollWheel(with: event)
    }

}

// MARK: - Collection view

/// Owns the two things NSCollectionView's own machinery would otherwise swallow:
/// right-click menus, and arrow keys (which must move focus, not selection — a
/// selection change on this screen means "open this item").
private final class MacCollectionBrowserCollectionView: NSCollectionView {

    private static let swipeDominanceRatio: CGFloat = 1.5

    weak var owner: MacCollectionBrowserViewController?

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: location) else { return nil }
        return owner?.contextMenu(forTokenIndex: indexPath.item)
    }

    override func moveLeft(_ sender: Any?) {
        owner?.moveFocus(by: -1)
    }

    override func moveRight(_ sender: Any?) {
        owner?.moveFocus(by: 1)
    }

    override func moveUp(_ sender: Any?) {
        owner?.moveFocusVertically(byRows: -1)
    }

    override func moveDown(_ sender: Any?) {
        owner?.moveFocusVertically(byRows: 1)
    }

    override func scrollPageUp(_ sender: Any?) {
        guard let owner else { return }
        owner.moveFocusVertically(byRows: -owner.visibleRowCount)
    }

    override func scrollPageDown(_ sender: Any?) {
        guard let owner else { return }
        owner.moveFocusVertically(byRows: owner.visibleRowCount)
    }

    override func moveToBeginningOfDocument(_ sender: Any?) {
        owner?.moveFocusToRow(.first)
    }

    override func moveToEndOfDocument(_ sender: Any?) {
        owner?.moveFocusToRow(.last)
    }

    override func insertNewline(_ sender: Any?) {
        owner?.openFocusedItem()
    }

    override func insertLineBreak(_ sender: Any?) {
        owner?.openFocusedItem()
    }

    /// Two-finger swipe right goes back to the collections grid — the Mac form of the
    /// interactive back iOS leaves enabled on this screen, and the same gesture Safari
    /// and Finder use. Discrete rather than interactive: it runs the same slide the
    /// toolbar chevron does.
    override func scrollWheel(with event: NSEvent) {
        guard let owner else {
            super.scrollWheel(with: event)
            return
        }
        guard owner.allowsUserInteraction else { return }

        // Only claim a gesture that begins clearly horizontal. If the .began event
        // carries no deltas the gesture simply scrolls as usual — the right failure
        // mode for an accelerator that Cmd+[ and Esc already cover.
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              event.hasPreciseScrollingDeltas,
              event.phase == .began,
              event.scrollingDeltaX != 0,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * Self.swipeDominanceRatio else {
            super.scrollWheel(with: event)
            return
        }

        var didHandle = false
        event.trackSwipeEvent(
            options: .lockDirection,
            dampenAmountThresholdMin: -1,
            max: 1
        ) { [weak self] gestureAmount, phase, isComplete, stop in
            guard let owner = self?.owner else {
                stop.pointee = true
                return
            }
            guard phase == .ended || isComplete else { return }
            guard !didHandle, gestureAmount >= 1 else { return }
            didHandle = true
            owner.navigateBack()
        }
    }

}

// MARK: - Layout

private final class MacCollectionBrowserLayout: NSCollectionViewLayout {

    var browserLayout: MobilePlayerBrowserLayout? {
        didSet {
            guard browserLayout != oldValue else { return }
            invalidateLayout()
        }
    }

    override var collectionViewContentSize: NSSize {
        browserLayout?.contentSize ?? .zero
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard let browserLayout else { return [] }
        return browserLayout.candidateItemIndices(intersecting: rect).compactMap {
            layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let browserLayout,
              let itemFrame = browserLayout.itemFrame(at: indexPath.item) else {
            return nil
        }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = itemFrame
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        false
    }

}

// MARK: - Cell

private final class MacCollectionBrowserItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("MacCollectionBrowserItem")

    private let thumbnailView = MacCollectionBrowserThumbnailView()
    private var representedTokenIndex: Int?
    private var descriptor: CollectionCatalogDownloadableMediaDescriptor?
    private var imageLoadId: UUID?
    private var imageLoadCancellation: (() -> Void)?

    override func loadView() {
        view = thumbnailView
        thumbnailView.setAccessibilityElement(true)
        thumbnailView.setAccessibilityRole(.button)
    }

    var isFocused = false {
        didSet {
            guard oldValue != isFocused else { return }
            thumbnailView.isFocused = isFocused
            thumbnailView.setAccessibilitySelected(isFocused)
        }
    }

    var displayedImage: NSImage? {
        thumbnailView.image
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelImageLoad()
        representedTokenIndex = nil
        descriptor = nil
        thumbnailView.image = nil
        thumbnailView.isHidden = false
        thumbnailView.onAccessibilityPress = nil
        thumbnailView.setAccessibilityLabel(nil)
        thumbnailView.setAccessibilitySelected(false)
        isFocused = false
    }

    isolated deinit {
        cancelImageLoad()
    }

    func configure(
        tokenIndex: Int,
        descriptor: CollectionCatalogDownloadableMediaDescriptor?,
        accessibilityLabel: String,
        allowsImageLoading: Bool,
        onAccessibilityPress: @escaping () -> Void
    ) {
        let retainedImage = representedTokenIndex == tokenIndex && self.descriptor == descriptor
            ? thumbnailView.image
            : nil
        cancelImageLoad()
        representedTokenIndex = tokenIndex
        self.descriptor = descriptor
        thumbnailView.usesNativeMetalCardCornerMask = descriptor?.usesNativeMetalCardPresentation == true
        thumbnailView.image = retainedImage
        thumbnailView.setAccessibilityLabel(accessibilityLabel)
        thumbnailView.onAccessibilityPress = onAccessibilityPress
        if thumbnailView.image == nil,
           let descriptor,
           let cached = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            thumbnailView.image = cached
        }
        if allowsImageLoading {
            refreshImageIfNeeded()
        }
    }

    func resumeImageLoadIfNeeded(tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex else { return }
        refreshImageIfNeeded()
    }

    func cancelImageLoad(ifRepresenting tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex else { return }
        cancelImageLoad()
    }

    func cancelImageLoad() {
        imageLoadId = nil
        let cancellation = imageLoadCancellation
        imageLoadCancellation = nil
        cancellation?()
    }

    func refreshImageIfNeeded() {
        guard thumbnailView.image == nil,
              let tokenIndex = representedTokenIndex,
              let descriptor else {
            return
        }
        if let cached = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            cancelImageLoad()
            thumbnailView.image = cached
            return
        }
        guard imageLoadId == nil else { return }

        let loadId = UUID()
        imageLoadId = loadId
        let cancellation = DownloadableMediaCache.shared.loadProvisionalImage(
            for: descriptor
        ) { [weak self] image in
            guard let self, self.imageLoadId == loadId else { return }
            self.imageLoadId = nil
            self.imageLoadCancellation = nil
            guard self.representedTokenIndex == tokenIndex,
                  self.descriptor == descriptor else {
                return
            }
            self.thumbnailView.image = image
        }
        if imageLoadId == loadId {
            imageLoadCancellation = cancellation
        }
    }

}

/// Aspect-fit thumbnail with the rounded-corner mask the native metal card
/// collections use. The image lives on the view's own backing layer rather than a
/// sublayer, so Core Animation scales it against the animating presentation bounds —
/// a sublayer's frame is only laid out once, at the final size, which made the hero
/// card wipe open instead of zooming.
final class MacCollectionBrowserThumbnailView: NSView {

    private var appliedMaskBounds: CGRect?
    private var focusRingLayer: CALayer?

    var onAccessibilityPress: (() -> Void)?

    var usesNativeMetalCardCornerMask = false {
        didSet {
            guard oldValue != usesNativeMetalCardCornerMask else { return }
            appliedMaskBounds = nil
            updateCornerMask(for: bounds)
        }
    }

    /// Marks the keyboard target. Driven by the browser's focused token index rather
    /// than by collection view selection, which on this screen means "open".
    var isFocused = false {
        didSet {
            guard oldValue != isFocused else { return }
            updateFocusRing()
        }
    }

    var image: NSImage? {
        didSet {
            withoutLayerAnimations {
                layer?.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                // The placeholder tint fills the cell; once artwork is in, the margins
                // around a letterboxed image should read as empty, not as grey slabs.
                layer?.backgroundColor = (image == nil ? Self.placeholderColor : .clear)
            }
        }
    }

    private static let placeholderColor = NSColor(white: 0.09, alpha: 1).cgColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpLayer()
    }

    private func setUpLayer() {
        wantsLayer = true
        // AppKit derives the backing layer's contentsGravity from this, so set it here
        // rather than only in makeBackingLayer, or aspect fill gets overwritten.
        // Fit, not fill: iOS letterboxes thumbnails whole, and cropping the edges off
        // mixed-aspect artwork is a content-fidelity loss in an app for looking at art.
        layerContentsPlacement = .scaleProportionallyToFit
        layerContentsRedrawPolicy = .never
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = Self.placeholderColor
        layer.masksToBounds = true
        layer.contentsGravity = .resizeAspect
        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .linear
        return layer
    }

    override func layout() {
        super.layout()
        withoutLayerAnimations {
            layer?.contentsScale = window?.backingScaleFactor ?? 2
            focusRingLayer?.frame = bounds
        }
        updateCornerMask(for: bounds)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onAccessibilityPress else { return false }
        onAccessibilityPress()
        return true
    }

    private func updateFocusRing() {
        guard isFocused else {
            focusRingLayer?.removeFromSuperlayer()
            focusRingLayer = nil
            return
        }
        guard focusRingLayer == nil, let layer else { return }
        let ring = CALayer()
        ring.frame = bounds
        ring.borderWidth = 2
        ring.borderColor = NSColor.controlAccentColor.cgColor
        ring.actions = ["borderColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer.addSublayer(ring)
        focusRingLayer = ring
    }

    /// Animates the corner mask alongside an implicit frame animation. The mask is a
    /// `CAShapeLayer`, whose path Core Animation will not interpolate on its own, so
    /// the card would otherwise fly with one grossly oversized rounded corner.
    func animateCornerMask(
        fromBounds: CGRect,
        toBounds: CGRect,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        guard usesNativeMetalCardCornerMask,
              fromBounds.width > 0,
              fromBounds.height > 0,
              toBounds.width > 0,
              toBounds.height > 0 else {
            return
        }

        appliedMaskBounds = nil
        updateCornerMask(for: fromBounds)
        guard let maskLayer = layer?.mask as? CAShapeLayer else { return }

        let fromPath = maskPath(for: fromBounds)
        let toPath = maskPath(for: toBounds)
        let fromPosition = CGPoint(x: fromBounds.midX, y: fromBounds.midY)
        let toPosition = CGPoint(x: toBounds.midX, y: toBounds.midY)

        withoutLayerAnimations {
            maskLayer.bounds = CGRect(origin: .zero, size: toBounds.size)
            maskLayer.position = toPosition
            maskLayer.path = toPath
        }
        appliedMaskBounds = toBounds

        for (keyPath, from, to) in [
            ("path", fromPath as Any, toPath as Any),
            ("bounds.size", NSValue(size: fromBounds.size) as Any, NSValue(size: toBounds.size) as Any),
            ("position", NSValue(point: fromPosition) as Any, NSValue(point: toPosition) as Any)
        ] {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = timingFunction
            maskLayer.add(animation, forKey: "cardTransition.\(keyPath)")
        }
    }

    private func updateCornerMask(for maskBounds: CGRect) {
        guard usesNativeMetalCardCornerMask,
              maskBounds.width > 0,
              maskBounds.height > 0 else {
            layer?.mask = nil
            appliedMaskBounds = nil
            return
        }
        guard appliedMaskBounds != maskBounds || !(layer?.mask is CAShapeLayer) else { return }

        let maskLayer = (layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        withoutLayerAnimations {
            maskLayer.bounds = CGRect(origin: .zero, size: maskBounds.size)
            maskLayer.position = CGPoint(x: maskBounds.midX, y: maskBounds.midY)
            maskLayer.path = maskPath(for: maskBounds)
        }
        layer?.mask = maskLayer
        appliedMaskBounds = maskBounds
    }

    private func maskPath(for maskBounds: CGRect) -> CGPath {
        let radii = NativeMetalCardLayout.cardCornerRadii(in: maskBounds.size)
        return CGPath(
            roundedRect: CGRect(origin: .zero, size: maskBounds.size),
            cornerWidth: radii.width,
            cornerHeight: radii.height,
            transform: nil
        )
    }

    private func withoutLayerAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

}
