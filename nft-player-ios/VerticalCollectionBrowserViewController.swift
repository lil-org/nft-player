// ∅ 2026 lil org

import QuartzCore
import UIKit

enum MobilePlayerCollectionBrowserDisplayPreparationResult: Equatable {
    case prepared
    case superseded
    case unavailable
}

final class VerticalCollectionBrowserViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching,
    UIGestureRecognizerDelegate {

    private struct PreparedTransition {
        let preparation: PlayerCollectionBrowsePreparation
        let contentOffset: CGPoint
        let layoutSize: CGSize
        let layoutDisplayScale: CGFloat
        let layoutWindowSafeAreaInsets: UIEdgeInsets
        let verticalContentOffsetRange: ClosedRange<CGFloat>
        let browseSnapshot: PlayerCollectionBrowseSnapshot?
        let scrollCoordinatorSnapshot:
            MobilePlayerCollectionBrowserScrollCoordinator.Snapshot
        let imagePipelineSnapshot:
            MobilePlayerCollectionBrowserImagePipeline.Snapshot
        let layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    }

    private struct WindowSafeAreaState {
        let insets: UIEdgeInsets
    }

    private struct LayoutAspectSample {
        let index: Int
        let size: CGSize
        let usesNativeMetalCardCornerMask: Bool
    }

    private struct WindowSafeAreaLayoutUpdate {
        let insetsToCapture: UIEdgeInsets?
        let clearsPendingRefresh: Bool
        let requiresLayoutRefresh: Bool
    }

    private static let cellReuseIdentifier = "MobilePlayerCollectionBrowserCell"
    private static let boundaryEpsilon: CGFloat = 0.75
    private static let verticalContentMargin: CGFloat = 0

    let uuid: UUID

    var onFocusedPagePosition: ((PlayerPagePosition) -> Void)?
    var onSettledPagePosition: ((PlayerPagePosition, Bool) -> Bool)?
    var onSelection: ((MobilePlayerBrowserTransitionSelection) -> Bool)?
    var onImmediateSelection: ((PlayerPagePosition, @escaping () -> Void) -> Bool)?
#if DEBUG
    typealias ThumbnailWindowMetrics =
        MobilePlayerCollectionBrowserImagePipeline.ThumbnailWindowMetrics

    var thumbnailWindowMetrics: ThumbnailWindowMetrics {
        imagePipeline.thumbnailWindowMetrics
    }
#endif

    private let browserCollectionLayout = MobilePlayerCollectionBrowserLayout()
    private let imagePipeline = MobilePlayerCollectionBrowserImagePipeline()
    private let scrollCoordinator =
        MobilePlayerCollectionBrowserScrollCoordinator()
    private let gridModeCoordinator:
        MobilePlayerCollectionBrowserGridModeCoordinator
    private lazy var collectionView: MobilePlayerCollectionBrowserCollectionView = {
        let collectionView = MobilePlayerCollectionBrowserCollectionView(
            frame: .zero,
            collectionViewLayout: browserCollectionLayout
        )
        collectionView.backgroundColor = .clear
        collectionView.isOpaque = false
        collectionView.alwaysBounceVertical = true
        collectionView.alwaysBounceHorizontal = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.keyboardDismissMode = .none
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.scrollsToTop = false
        collectionView.accessibilityIdentifier = "MobilePlayerCollectionBrowser"
        collectionView.register(
            MobilePlayerCollectionBrowserCell.self,
            forCellWithReuseIdentifier: Self.cellReuseIdentifier
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.onWillAccessibilityScroll = { [weak self] in
            guard let self else {
                return .init(
                    interruptedGridModeSettle: false,
                    wasScrollMotionActive: false
                )
            }
            let wasScrollMotionActive = self.isScrollMotionActive
            let interrupted = self.finalizeInterruptibleGridModeSettle()
            self.beginScrollMotion()
            return .init(
                interruptedGridModeSettle: interrupted,
                wasScrollMotionActive: wasScrollMotionActive
            )
        }
        collectionView.onAccessibilityScrollResult = {
            [weak self] succeeded, attempt in
            guard let self else { return }
            if succeeded {
                self.removeGridModeCommitSnapshot()
                self.scheduleScrollMotionAnimationTimeout()
                return
            }
            if !attempt.wasScrollMotionActive {
                self.endScrollMotion()
                self.resumeVisibleBrowserImageLoadsIfNeeded()
                self.scheduleGridModeGeometryPrewarmIfPossible()
            }
            if attempt.interruptedGridModeSettle {
                self.settleAfterImmediateGridModeOffsetIfPossible()
            }
        }
        collectionView.contentOffsetTarget = { [weak self] requestedContentOffset, animated in
            self?.gridModeContentOffsetTarget(
                for: requestedContentOffset,
                animated: animated
            ) ?? (requestedContentOffset, false)
        }
        collectionView.onDidApplyImmediateContentOffset = { [weak self] in
            self?.settleAfterImmediateGridModeOffsetIfPossible()
        }
        return collectionView
    }()

    private var browseSnapshot: PlayerCollectionBrowseSnapshot?
    private var publicationState: PlayerCollectionScrollPublicationState? {
        get { scrollCoordinator.publicationState }
        set { scrollCoordinator.publicationState = newValue }
    }
    private var hasFinishedInitialPositioning: Bool {
        get { scrollCoordinator.hasFinishedInitialPositioning }
        set { scrollCoordinator.hasFinishedInitialPositioning = newValue }
    }
    private var isActive: Bool {
        get { scrollCoordinator.isActive }
        set {
            scrollCoordinator.setActive(newValue)
            imagePipeline.setActive(newValue)
        }
    }
    private var isViewVisible: Bool {
        get { imagePipeline.isVisible }
        set { imagePipeline.setVisible(newValue) }
    }
    private var isApplyingPosition: Bool {
        get { scrollCoordinator.isApplyingPosition }
        set { scrollCoordinator.setApplyingPosition(newValue) }
    }
    private var lastLayoutSize = CGSize.zero
    private var lastLayoutDisplayScale: CGFloat = 0
    private var focusedTokenIndex: Int? {
        get { scrollCoordinator.focusedTokenIndex }
        set { scrollCoordinator.focusedTokenIndex = newValue }
    }
    private var forcedFocusedTokenIndex: Int? {
        get { scrollCoordinator.forcedFocusedTokenIndex }
        set { scrollCoordinator.forcedFocusedTokenIndex = newValue }
    }
    private var retainedFocusFocalBias: PlayerCollectionScrollFocalBias? {
        get { scrollCoordinator.retainedFocusFocalBias }
        set { scrollCoordinator.retainedFocusFocalBias = newValue }
    }
    private var lastEmittedFocusedTokenIndex: Int? {
        get { scrollCoordinator.lastEmittedFocusedTokenIndex }
        set { scrollCoordinator.lastEmittedFocusedTokenIndex = newValue }
    }
    private var lastScrollOffsetY: CGFloat? {
        get { scrollCoordinator.lastScrollOffsetY }
        set { scrollCoordinator.lastScrollOffsetY = newValue }
    }
    private var dragStartContentOffsetY: CGFloat? {
        get { scrollCoordinator.dragStartContentOffsetY }
        set { scrollCoordinator.dragStartContentOffsetY = newValue }
    }
    private var needsWindowSafeAreaRefresh = false
    private var isScrollMotionActive: Bool {
        scrollCoordinator.isScrollMotionActive
    }
    private(set) var lastPrefetchDirection:
        DownloadableMediaCache.PrefetchDirection {
        get { scrollCoordinator.lastPrefetchDirection }
        set { scrollCoordinator.setPrefetchDirection(newValue) }
    }
    private var preparedTransition: PreparedTransition?
    private var layoutAspectState = MobilePlayerCollectionBrowserLayoutAspectState(
        aspectProfile: MobilePlayerBrowserAspectProfile(
            itemCount: 0,
            uniformImageSize: CGSize(width: 1, height: 1)
        ),
        fallbackSpec: PlayerMediaPlaceholderSpec(
            aspectSize: CGSize(width: 1, height: 1)
        )
    )
    private var layoutWindowSafeAreaInsets = UIEdgeInsets.zero
    private var hasCapturedLayoutWindowSafeAreaInsets = false
    private var gridModeInteractionCoordinator:
        PlayerBrowserGridInteractionCoordinator {
        get { gridModeCoordinator.interactionCoordinator }
        set { gridModeCoordinator.interactionCoordinator = newValue }
    }
    private var gridModeEffectDrainDepth: Int {
        get { gridModeCoordinator.effectDrainDepth }
        set { gridModeCoordinator.effectDrainDepth = newValue }
    }
    private var gridModeContentOffsetRestorationDepth: Int {
        get { gridModeCoordinator.contentOffsetRestorationDepth }
        set { gridModeCoordinator.contentOffsetRestorationDepth = newValue }
    }
    private var gridModeCommitSnapshotView: UIView? {
        gridModeCoordinator.commitSnapshotView
    }
    private var gridModeCommitSnapshotContentOffset: CGPoint? {
        get { gridModeCoordinator.commitSnapshotContentOffset }
        set { gridModeCoordinator.commitSnapshotContentOffset = newValue }
    }
    private var gridModeSettleContentOffsetY: CGFloat? {
        gridModeCoordinator.settleContentOffsetY
    }
    private var gridModeGeometryCache: GridModeGeometryCache? {
        get { gridModeCoordinator.geometryCache }
        set { gridModeCoordinator.geometryCache = newValue }
    }
    private var gridModeGeometryPrewarmPlan: GridModeGeometryPrewarmPlan? {
        get { gridModeCoordinator.geometryPrewarmPlan }
        set { gridModeCoordinator.geometryPrewarmPlan = newValue }
    }
    private var gridModeDestinationCache: [
        MobileCollectionBrowserGridMode: CachedGridModeDestination
    ] {
        get { gridModeCoordinator.destinationCache }
        set { gridModeCoordinator.destinationCache = newValue }
    }
    private var gridModePinchRecognizer: UIPinchGestureRecognizer {
        gridModeCoordinator.pinchRecognizer
    }
    private var lastGridModePinchViewLocation: CGPoint? {
        get { gridModeCoordinator.lastPinchViewLocation }
        set { gridModeCoordinator.lastPinchViewLocation = newValue }
    }
    private var gridModePinchFrameCoalescer: GridModePinchFrameCoalescer {
        gridModeCoordinator.pinchFrameCoalescer
    }
    private var gridModeGeometryPrewarmUpdate: PendingMainQueueUpdate {
        gridModeCoordinator.geometryPrewarmUpdate
    }
    private var gridModeRenderer: MobilePlayerCollectionBrowserGridRenderer {
        gridModeCoordinator.renderer
    }

    private var configuredColumnCount: Int {
        browserCollectionLayout.browserLayout?.columnCount ?? 0
    }

    private var configuredPrefetchStride: Int {
        browserCollectionLayout.browserLayout?.prefetchStride
            ?? MobilePlayerBrowserLayout.defaultColumnCount
    }

    private var requiredImageQuality: CollectionBrowseImageQuality {
        gridMode.requiredImageQuality
    }

    init(
        uuid: UUID,
        gridModeCommitSnapshotFactory: @escaping (UIView) -> UIView? = { view in
            view.resizableSnapshotView(
                from: view.bounds,
                afterScreenUpdates: false,
                withCapInsets: .zero
            )
        }
    ) {
        self.uuid = uuid
        self.gridModeCoordinator =
            MobilePlayerCollectionBrowserGridModeCoordinator(
                commitSnapshotFactory: gridModeCommitSnapshotFactory
            )
        super.init(nibName: nil, bundle: nil)
        imagePipeline.configure(contentAccess: .init(
            visibleIndexPaths: { [weak self] in
                self?.collectionView.indexPathsForVisibleItems ?? []
            },
            cell: { [weak self] indexPath in
                self?.collectionView.cellForItem(at: indexPath)
                    as? MobilePlayerCollectionBrowserCell
            },
            visibleCells: { [weak self] in
                self?.visibleBrowserCells ?? []
            },
            viewportRenderCells: { [weak self] in
                self?.gridModeRenderer.viewportRenderCells ?? []
            },
            requiredImageQuality: { [weak self] in
                self?.requiredImageQuality ?? .large
            },
            baseColumnCount: { [weak self] in
                self?.gridMode.columnCount ?? 0
            },
            isRendererActive: { [weak self] in
                self?.gridModeRenderer.isActive == true
            },
            isApplyingPosition: { [weak self] in
                self?.isApplyingPosition == true
            },
            isPreparedTransitionActive: { [weak self] in
                self?.preparedTransition != nil
            },
            isForegroundActive: { [weak self] in
                self?.collectionView.window?.windowScene?.activationState
                    == .foregroundActive
            },
            projectedTokenRange: { [weak self] tokenIndex, direction, distance in
                self?.projectedBrowserTokenRange(
                    around: tokenIndex,
                    direction: direction,
                    refreshDistance: distance
                )
            },
            prepareThumbnailWindow: { [weak self] preparation in
                guard let self else { return }
                MobilePlaybackController.shared
                    .prepareCollectionBrowseThumbnailWindow(
                        uuid: self.uuid,
                        centeredAt: preparation.tokenIndex,
                        direction: preparation.direction,
                        prefetchStride: preparation.prefetchStride,
                        columnCount: preparation.columnCount,
                        quality: preparation.quality,
                        requiredTokenRange: preparation.requiredTokenRange,
                        displayedHigherQualityThumbnailTokenIndices:
                            preparation
                                .displayedHigherQualityThumbnailTokenIndices,
                        displayedLargeTokenIndices:
                            preparation.displayedLargeTokenIndices,
                        locallyAvailableLargeTokenIndices:
                            preparation.locallyAvailableLargeTokenIndices
                    )
            }
        ))
        scrollCoordinator.configure(contentAccess: .init(
            pagePosition: { [weak self] tokenIndex in
                self?.browseSnapshot?.pagePosition(forTokenIndex: tokenIndex)
            },
            publishFocusedPagePosition: { [weak self] pagePosition in
                self?.onFocusedPagePosition?(pagePosition)
            },
            publishSettledPosition: { [weak self] publication in
                self?.publishSettledPagePosition(publication) == true
            },
            performScheduledScrollObservation: { [weak self] in
                self?.observeCurrentAnchor(
                    focusCadence: .continuous,
                    preparesThumbnailWindow: true,
                    forcesThumbnailWindow: false
                )
            },
            scrollMotionAnimationDidExpire: { [weak self] in
                self?.handleScrollMotionAnimationTimeout()
            }
        ))
    }

    private func configureGridModeCoordinator() {
        gridModeCoordinator.configure(
            collectionView: collectionView,
            viewportView: view,
            gestureTarget: self,
            gestureAction: #selector(handleGridModePinch(_:)),
            gestureDelegate: self,
            rendererContentAccess: .init(
                configureCell: { [weak self] cell, indexPath, configuration in
                    self?.configureBrowserCell(
                        cell,
                        at: indexPath,
                        requiredImageQuality:
                            configuration.requiredImageQuality,
                        imageLoadPolicy: configuration.imageLoadPolicy,
                        allowsLocalLargeImageUpgrade:
                            configuration.allowsLocalLargeImageUpgrade
                    )
                },
                contentIdentity: { [weak self] in
                    self?.browserContentIdentity(forTokenIndex: $0)
                },
                imageSources: { [weak self] in
                    self?.browseImageSources(forTokenIndex: $0)
                }
            ),
            contentAccess: .init(
                applyPinchFrame: { [weak self] frame in
                    self?.applyGridModePinchFrame(frame)
                },
                prewarmNextGeometry: { [weak self] in
                    self?.prewarmNextGridModeGeometry()
                },
                settleTick: { [weak self] in
                    self?.advanceGridModeInteractionTick(.settleTick(
                        timestamp: CACurrentMediaTime()
                    ))
                },
                interactionFadeTick: { [weak self] in
                    self?.advanceGridModeInteractionTick(.interactionFadeTick(
                        timestamp: CACurrentMediaTime()
                    ))
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        gridModeCoordinator.invalidate()
        scrollCoordinator.invalidate()
        imagePipeline.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true

        registerForTraitChanges([UITraitDisplayScale.self]) {
            (controller: VerticalCollectionBrowserViewController, _) in
            controller.view.setNeedsLayout()
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        configureGridModeCoordinator()
        view.addGestureRecognizer(gridModePinchRecognizer)

        reloadBrowseSnapshot(resetPublicationState: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidEnterBackground(_:)),
            name: UIScene.didEnterBackgroundNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidActivate(_:)),
            name: UIScene.didActivateNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadableMediaCacheFileAvailabilityDidChange(_:)),
            name: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
        )
    }

    @objc private func sceneDidEnterBackground(_ notification: Notification) {
        guard let windowScene = notification.object as? UIWindowScene,
              let currentWindowScene = collectionView.window?.windowScene,
              windowScene === currentWindowScene else {
            return
        }
        finalizeGridModeInteractionIfNeeded()
        endScrollMotionAndResetDragState()
        flushSettledPosition()
        cancelGridModeGeometryPrewarming()
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        guard let windowScene = notification.object as? UIWindowScene,
              let currentWindowScene = collectionView.window?.windowScene,
              windowScene === currentWindowScene else {
            return
        }
        resumeVisibleBrowserImageLoadsIfNeeded()
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    @objc private func downloadableMediaCacheFileAvailabilityDidChange(
        _ notification: Notification
    ) {
        refreshVisibleCachedImagesIfNeeded(notification: notification)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = view.bounds.size
        let sizeChanged = lastLayoutSize != .zero && lastLayoutSize != viewportSize
        let displayScale = currentLayoutDisplayScale
        let displayScaleChanged = lastLayoutDisplayScale > 0
            && lastLayoutDisplayScale != displayScale
        let windowSafeAreaLayoutUpdate = resolveWindowSafeAreaLayoutUpdate(
            state: currentWindowSafeAreaState,
            sizeChanged: sizeChanged
        )
        var interruptedGridModeAnchorTokenIndex: Int?
        if hasGridModeInteractionState,
           sizeChanged || displayScaleChanged
               || windowSafeAreaLayoutUpdate.requiresLayoutRefresh {
            interruptedGridModeAnchorTokenIndex =
                gridModeRenderer.anchorTokenIndex
            finalizeGridModeInteractionIfNeeded()
            guard !hasGridModeInteractionState else {
                view.setNeedsLayout()
                return
            }
        }
        if sizeChanged || displayScaleChanged
            || windowSafeAreaLayoutUpdate.requiresLayoutRefresh {
            removeGridModeCommitSnapshot()
        }
        let previousLayoutWindowSafeAreaInsets = layoutWindowSafeAreaInsets
        let previousContentOffset = collectionView.contentOffset
        let previousVerticalContentOffsetRange = verticalContentOffsetRange

        if let insets = windowSafeAreaLayoutUpdate.insetsToCapture {
            captureLayoutWindowSafeAreaInsets(insets)
        }
        if windowSafeAreaLayoutUpdate.clearsPendingRefresh {
            needsWindowSafeAreaRefresh = false
        }
        let transition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: lastLayoutSize,
            viewportSize: viewportSize,
            needsGeometryRefresh:
                displayScaleChanged
                    || windowSafeAreaLayoutUpdate.requiresLayoutRefresh,
            displayScale: displayScale,
            topContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.top,
            bottomContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.bottom,
            aspectProfile: layoutAspectState.aspectProfile,
            forcedTokenIndex: forcedFocusedTokenIndex,
            interactionAnchorTokenIndex:
                interruptedGridModeAnchorTokenIndex,
            focusedTokenIndex: focusedTokenIndex
        )
        let wasApplyingPosition = isApplyingPosition
        if transition.needsLayout {
            isApplyingPosition = true
            if let browserLayout = transition.layout {
                installCollectionLayout(browserLayout)
            }
            collectionView.layoutIfNeeded()
        }

        if transition.geometryChanged,
           !transition.needsInitialLayout {
            if sizeChanged || displayScaleChanged,
               let retainedFocus = transition.retainedFocusTokenIndex {
                centerContent(on: retainedFocus)
                retainFocusedTokenIndex(retainedFocus)
                focusedTokenIndex = retainedFocus
            } else if windowSafeAreaLayoutUpdate.requiresLayoutRefresh {
                restoreContentPositionAfterSafeAreaChange(
                    previousContentOffset: previousContentOffset,
                    previousTopContentInset:
                        previousLayoutWindowSafeAreaInsets.top,
                    previousVerticalContentOffsetRange:
                        previousVerticalContentOffsetRange,
                    retainedFocusTokenIndex:
                        transition.retainedFocusTokenIndex
                )
            }
        }
        if transition.needsLayout {
            lastScrollOffsetY = collectionView.contentOffset.y
        }
        isApplyingPosition = wasApplyingPosition
        lastLayoutSize = viewportSize
        lastLayoutDisplayScale = displayScale

        guard isActive else { return }
        let hadFinishedInitialPositioning = hasFinishedInitialPositioning
        performInitialPositioningIfNeeded()
        if hadFinishedInitialPositioning,
           transition.geometryChanged,
           !isApplyingPosition {
            settleCurrentPosition()
        } else if windowSafeAreaLayoutUpdate.clearsPendingRefresh {
            scheduleGridModeGeometryPrewarmIfPossible()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        cancelGridModeGeometryPrewarming()
        needsWindowSafeAreaRefresh = true
        view.setNeedsLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewVisible = true
        resumeVisibleBrowserImageLoadsIfNeeded()
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
        finalizeGridModeInteractionIfNeeded()
        endScrollMotionAndResetDragState()
        flushSettledPosition()
        cancelGridModeGeometryPrewarming()
    }

    var currentPagePosition: PlayerPagePosition? {
        guard let browseSnapshot,
              let tokenIndex = forcedFocusedTokenIndex ?? focusedTokenIndex else {
            return nil
        }
        return browseSnapshot.pagePosition(forTokenIndex: tokenIndex)
    }

    var gridMode: MobileCollectionBrowserGridMode {
        MobileCollectionBrowserGridMode(
            rawValue: layoutAspectState.aspectProfile.columnCount
        ) ?? .defaultMode
    }

    func makeGridModeMenu() -> UIMenu {
        gridModeCoordinator.makeMenu(currentMode: gridMode) {
            [weak self] gridMode in
                guard self?.setGridMode(gridMode) == true else { return }
                Haptic.selectionChanged()
        }
    }

    @discardableResult
    func setGridMode(_ gridMode: MobileCollectionBrowserGridMode) -> Bool {
        let initialGridMode = self.gridMode
        guard gridMode != initialGridMode,
              isActive,
              !isApplyingPosition,
              !hasGridModeInteractionState,
              preparedTransition == nil,
              let browseSnapshot else {
            return false
        }

        let retainedTokenIndex = gridModeAnchorTokenIndex()
            ?? browseSnapshot.initialTokenIndex
        let canAnimateTransition = hasFinishedInitialPositioning
        let ratios = canAnimateTransition
            ? makeGridModeRatios(fromMode: initialGridMode)
            : []
        let effects = gridModeInteractionCoordinator.handle(
            .menuSelected(
                fromMode: initialGridMode,
                toMode: gridMode,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            ),
            ratioProvider: { fromMode in
                fromMode == initialGridMode ? ratios : []
            }
        )
        return applyGridModeInteractionEffects(
            effects,
            transitionAnchor: { [weak self] in
                guard let self else { return nil }
                return makeGridModeGestureAnchor(
                    tokenIndex: retainedTokenIndex,
                    preferredContentPoint: gridModeVisualFocalPoint()
                )
            }
        )
    }

    private var hasGridModeInteractionState: Bool {
        gridModeCoordinator.hasInteractionState
    }

    /// `awaitingRenderer` also reports `.settling` but cannot be finalized;
    /// `canBeginPinch` excludes it.
    private var hasInterruptibleGridModeSettle: Bool {
        gridModeInteractionCoordinator.phase == .settling
            && gridModeInteractionCoordinator.canBeginPinch
            && gridModeEffectDrainDepth == 0
    }

    @discardableResult
    private func finalizeInterruptibleGridModeSettle() -> Bool {
        guard hasInterruptibleGridModeSettle,
              gridModeContentOffsetRestorationDepth == 0 else {
            return false
        }
        finalizeGridModeInteractionIfNeeded()
        return gridModeInteractionCoordinator.phase == .idle
    }

    private func interruptGridModeSettleForDragIfNeeded() {
        guard !finalizeInterruptibleGridModeSettle(),
              gridModeInteractionCoordinator.phase == .settling,
              !gridModeInteractionCoordinator.canBeginPinch else {
            return
        }
        _ = gridModeInteractionCoordinator.handle(.interrupt)
    }

    private func gridModeVisualGeometry(
        for layout: MobilePlayerBrowserLayout
    ) -> MobilePlayerBrowserVisualLayoutGeometry {
        collectionView.visualGeometry(for: layout)
    }

    private func makeGridModeGestureAnchor(
        tokenIndex: Int,
        preferredContentPoint: CGPoint
    ) -> GridModeGestureAnchor? {
        guard let layout = browserCollectionLayout.browserLayout,
              let itemFrame = gridModeVisualGeometry(for: layout)
                .itemFrame(at: tokenIndex) else {
            return nil
        }
        let relativeItemPoint = CGPoint(
            x: MobilePlayerBrowserGridTransition.anchorRelativeX(
                contentX: preferredContentPoint.x,
                itemFrame: itemFrame
            ),
            y: MobilePlayerBrowserGridTransition.anchorRelativeY(
                contentY: preferredContentPoint.y,
                itemFrame: itemFrame
            )
        )
        let anchorContentPoint = CGPoint(
            x: MobilePlayerBrowserGridTransition.anchorX(
                itemFrame: itemFrame,
                relativeX: relativeItemPoint.x
            ),
            y: MobilePlayerBrowserGridTransition.anchorY(
                itemFrame: itemFrame,
                relativeY: relativeItemPoint.y
            )
        )
        return GridModeGestureAnchor(
            tokenIndex: tokenIndex,
            viewportPoint: CGPoint(
                x: anchorContentPoint.x - collectionView.contentOffset.x,
                y: anchorContentPoint.y - collectionView.contentOffset.y
            ),
            relativeItemPoint: relativeItemPoint,
            baseContentOffsetY: collectionView.contentOffset.y
        )
    }

    private func makeGridModePlaneRequest(
        plane: PlayerBrowserGridInteractionCoordinator.Plane
    ) -> GridModePlaneRequest? {
        guard let renderSnapshot = gridModeRenderer.renderSnapshot,
              plane.fromMode == gridMode,
              browseSnapshot?.itemCount ?? 0 > 0,
              let anchor = renderSnapshot.gestureAnchor,
              let fromLayout = browserCollectionLayout.browserLayout,
              let destination = makeGridModeDestination(
                  mode: plane.toMode,
                  anchorTokenIndex: anchor.tokenIndex
              ) else {
            return nil
        }

        guard let transitionLayout = MobilePlayerBrowserGridTransition(
            fromLayout: fromLayout,
            toLayout: destination.layout
        ),
              transitionLayout.itemWidthRatio == plane.itemWidthRatio,
              gridModeVisualGeometry(for: fromLayout)
                .itemFrame(at: anchor.tokenIndex) != nil,
              let toFrame = gridModeVisualGeometry(for: destination.layout)
                .itemFrame(at: anchor.tokenIndex) else {
            return nil
        }

        let viewportSize = view.bounds.size
        let toContentOffsetY = MobilePlayerBrowserGridTransition.clampedContentOffsetY(
            MobilePlayerBrowserGridTransition.targetContentOffsetY(
                anchorFrame: toFrame,
                anchorRelativeY: anchor.relativeItemPoint.y,
                anchorViewportY: anchor.viewportPoint.y
            ),
            contentHeight: destination.layout.contentSize.height,
            viewportHeight: viewportSize.height
        )
        guard anchor.baseContentOffsetY.isFinite, toContentOffsetY.isFinite else {
            return nil
        }

        let horizontalPivotX = MobilePlayerBrowserGridTransition
            .boundaryPreservingPivotX(
                anchorX: anchor.viewportPoint.x,
                columnPitchRatio: transitionLayout.columnPitchRatio,
                destinationColumnPitch: destination.layout.itemWidth
                    + destination.layout.interItemSpacing,
                viewportWidth: viewportSize.width
            )
        let fromAnchorContentPoint = CGPoint(
            x: horizontalPivotX + collectionView.contentOffset.x,
            y: anchor.viewportPoint.y + anchor.baseContentOffsetY
        )
        let toAnchorContentPoint = CGPoint(
            x: fromAnchorContentPoint.x,
            y: MobilePlayerBrowserGridTransition.anchorY(
                itemFrame: toFrame,
                relativeY: anchor.relativeItemPoint.y
            )
        )
        let incomingAnchor = CGPoint(
            x: toAnchorContentPoint.x - collectionView.contentOffset.x,
            y: toAnchorContentPoint.y - toContentOffsetY
        )
        guard let canonicalCrossfade = PlayerBrowserGridCrossfade(
            itemWidthRatio: transitionLayout.itemWidthRatio,
            terminalScaleX: transitionLayout.columnPitchRatio,
            terminalScaleY: transitionLayout.rowPitchRatio,
            outgoingAnchor: CGPoint(
                x: horizontalPivotX,
                y: anchor.viewportPoint.y
            ),
            incomingAnchor: incomingAnchor,
            outgoingContentOffsetY: anchor.baseContentOffsetY,
            incomingContentOffsetY: toContentOffsetY,
            outgoingContentHeight: fromLayout.contentSize.height,
            incomingContentHeight: destination.layout.contentSize.height,
            viewportSize: viewportSize
        ) else {
            return nil
        }
        let crossfade: PlayerBrowserGridCrossfade
        if let visualAnchor = renderSnapshot.visualAnchor {
            guard let reanchoredCrossfade = canonicalCrossfade.reanchored(
                outgoingAnchor: visualAnchor
            ) else {
                return nil
            }
            crossfade = reanchoredCrossfade
        } else {
            crossfade = canonicalCrossfade
        }
        return GridModePlaneRequest(
            id: plane.id,
            toMode: plane.toMode,
            layoutAspectState: destination.layoutAspectState,
            anchorTokenIndex: anchor.tokenIndex,
            transitionLayout: transitionLayout,
            crossfade: crossfade,
            latticeMap: transitionLayout.latticeMap(
                fromAnchorContentPoint: fromAnchorContentPoint,
                toAnchorContentPoint: toAnchorContentPoint
            )
        )
    }

    private func makeGridModeDestination(
        mode: MobileCollectionBrowserGridMode,
        anchorTokenIndex: Int
    ) -> CachedGridModeDestination? {
        guard gridModeRenderer.isActive, let browseSnapshot else {
            return nil
        }
        if let cachedDestination = gridModeDestinationCache[mode],
           cachedDestination.anchorTokenIndex == anchorTokenIndex {
            return cachedDestination
        }

        let aspectState: MobilePlayerCollectionBrowserLayoutAspectState
        let layout: MobilePlayerBrowserLayout
        let aspectRatioProfile = MobilePlaybackController.shared
            .collectionBrowseThumbnailAspectRatioProfile(
                snapshot: browseSnapshot
            )
        if let aspectRatioProfile {
            guard let geometry = makeGridModeGeometry(
                snapshot: browseSnapshot,
                mode: mode,
                aspectRatioProfile: aspectRatioProfile
            ) else {
                return nil
            }
            aspectState = MobilePlayerCollectionBrowserLayoutAspectState(
                aspectProfile: geometry.aspectProfile,
                fallbackSpec: makeLayoutFallbackSpec(
                    snapshot: browseSnapshot,
                    focusedTokenIndex: anchorTokenIndex
                )
            )
            layout = geometry.layout
        } else {
            aspectState = makeLayoutAspectState(
                snapshot: browseSnapshot,
                columnCount: mode.columnCount,
                focusedTokenIndex: anchorTokenIndex,
                aspectRatioProfile: nil
            )
            guard let sampledLayout = makeBrowserLayout(
                aspectProfile: aspectState.aspectProfile
            ) else {
                return nil
            }
            layout = sampledLayout
        }

        let destination = CachedGridModeDestination(
            anchorTokenIndex: anchorTokenIndex,
            layoutAspectState: aspectState,
            layout: layout
        )
        gridModeDestinationCache[mode] = destination
        return destination
    }

    private func makeGridModeGeometry(
        snapshot: PlayerCollectionBrowseSnapshot,
        mode: MobileCollectionBrowserGridMode,
        aspectRatioProfile: ThumbnailAspectRatioProfile
    ) -> CachedGridModeGeometry? {
        ensureGridModeGeometryCache(snapshot: snapshot)
        if let geometry = gridModeGeometryCache?.geometries[mode] {
            return geometry
        }

        let aspectProfile = makeLayoutAspectProfile(
            snapshot: snapshot,
            columnCount: mode.columnCount,
            aspectRatioProfile: aspectRatioProfile
        )
        guard let layout = makeBrowserLayout(aspectProfile: aspectProfile) else {
            return nil
        }
        let geometry = CachedGridModeGeometry(
            aspectProfile: aspectProfile,
            layout: layout
        )
        gridModeGeometryCache?.geometries[mode] = geometry
        return geometry
    }

    @discardableResult
    private func ensureGridModeGeometryCache(
        snapshot: PlayerCollectionBrowseSnapshot
    ) -> GridModeGeometryCacheIdentity {
        let identity = gridModeGeometryCacheIdentity(snapshot: snapshot)
        if gridModeGeometryCache?.identity != identity {
            gridModeGeometryCache = GridModeGeometryCache(
                identity: identity,
                geometries: [:]
            )
        }
        return identity
    }

    private func gridModeGeometryCacheIdentity(
        snapshot: PlayerCollectionBrowseSnapshot
    ) -> GridModeGeometryCacheIdentity {
        GridModeGeometryCacheIdentity(
            collectionId: snapshot.collectionId,
            itemCount: snapshot.itemCount,
            viewportSize: view.bounds.size,
            displayScale: currentLayoutDisplayScale,
            topContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.top,
            bottomContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.bottom
        )
    }

    private func scheduleGridModeGeometryPrewarmIfPossible() {
        guard let context = gridModeGeometryPrewarmContext(),
              let browserLayout = browserCollectionLayout.browserLayout,
              let currentMode = MobileCollectionBrowserGridMode(
                  rawValue: layoutAspectState.aspectProfile.columnCount
              ) else {
            cancelGridModeGeometryPrewarming()
            return
        }

        let identity = ensureGridModeGeometryCache(snapshot: context.snapshot)
        gridModeGeometryCache?.geometries[currentMode] = CachedGridModeGeometry(
            aspectProfile: layoutAspectState.aspectProfile,
            layout: browserLayout
        )

        let missingModes = MobileCollectionBrowserGridMode.allCases
            .filter { gridModeGeometryCache?.geometries[$0] == nil }
            .sorted { lhs, rhs in
                let lhsDistance = abs(
                    lhs.columnCount - currentMode.columnCount
                )
                let rhsDistance = abs(
                    rhs.columnCount - currentMode.columnCount
                )
                if lhsDistance == rhsDistance {
                    return lhs.columnCount < rhs.columnCount
                }
                return lhsDistance < rhsDistance
            }
        guard !missingModes.isEmpty else {
            cancelGridModeGeometryPrewarming()
            return
        }

        gridModeGeometryPrewarmUpdate.invalidate()
        gridModeGeometryPrewarmPlan = GridModeGeometryPrewarmPlan(
            identity: identity,
            modes: missingModes
        )
        gridModeGeometryPrewarmUpdate.schedule()
    }

    private func prewarmNextGridModeGeometry() {
        guard var plan = gridModeGeometryPrewarmPlan,
              !plan.modes.isEmpty,
              let context = gridModeGeometryPrewarmContext() else {
            cancelGridModeGeometryPrewarming()
            return
        }

        let identity = gridModeGeometryCacheIdentity(snapshot: context.snapshot)
        guard plan.identity == identity,
              gridModeGeometryCache?.identity == identity else {
            cancelGridModeGeometryPrewarming()
            scheduleGridModeGeometryPrewarmIfPossible()
            return
        }

        let mode = plan.modes.removeFirst()
        gridModeGeometryPrewarmPlan = plan.modes.isEmpty ? nil : plan
        if gridModeGeometryCache?.geometries[mode] == nil {
            _ = makeGridModeGeometry(
                snapshot: context.snapshot,
                mode: mode,
                aspectRatioProfile: context.aspectRatioProfile
            )
        }
        if gridModeGeometryPrewarmPlan != nil {
            gridModeGeometryPrewarmUpdate.schedule()
        }
    }

    private func cancelGridModeGeometryPrewarming() {
        gridModeGeometryPrewarmUpdate.invalidate()
        gridModeGeometryPrewarmPlan = nil
    }

    private func gridModeGeometryPrewarmContext() -> (
        snapshot: PlayerCollectionBrowseSnapshot,
        aspectRatioProfile: ThumbnailAspectRatioProfile
    )? {
        guard isActive,
              isViewVisible,
              let windowScene = collectionView.window?.windowScene,
              windowScene.activationState == .foregroundActive,
              !hasGridModeInteractionState,
              !isApplyingPosition,
              !needsWindowSafeAreaRefresh,
              preparedTransition == nil,
              hasFinishedInitialPositioning,
              !collectionView.isTracking,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              !isScrollMotionActive,
              let browseSnapshot,
              let aspectRatioProfile = MobilePlaybackController.shared
                .collectionBrowseThumbnailAspectRatioProfile(
                    snapshot: browseSnapshot
                ),
              case .variable = aspectRatioProfile else {
            return nil
        }
        return (browseSnapshot, aspectRatioProfile)
    }

    /// Scrolling stays frozen for as long as the pinch owns the grid: the
    /// renderer anchors every plane transform to the content offset captured
    /// when the interaction began. The settle releases it so a drag can land
    /// without waiting out the spring.
    private func setGridModeScrollingSuspended(_ suspended: Bool) {
        collectionView.isScrollEnabled = suspended ? false : isActive
    }

    private func applyGridModeInteractionBegan(
        transitionAnchor: (() -> GridModeGestureAnchor?)?
    ) {
        guard !gridModeRenderer.isActive else {
            setGridModeScrollingSuspended(true)
            return
        }
        guard let sourceLayout = browserCollectionLayout.browserLayout else {
            return
        }
        let wasCollectionViewPrefetchingEnabled =
            collectionView.isPrefetchingEnabled
        cancelGridModeGeometryPrewarming()
        isApplyingPosition = true
        collectionView.isPrefetchingEnabled = false
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(
            clampedContentOffset(collectionView.contentOffset),
            animated: false
        )
        endScrollMotionAndResetDragState()
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        setGridModeScrollingSuspended(true)
        collectionView.clipsToBounds = false
        gridModeDestinationCache.removeAll(keepingCapacity: true)
        _ = gridModeRenderer.begin(
            gestureAnchor: transitionAnchor?(),
            sourceLayout: sourceLayout,
            wasCollectionViewPrefetchingEnabled:
                wasCollectionViewPrefetchingEnabled
        )
    }

    private func applyGridModeInteractionFinished(
        settlesPosition: Bool
    ) {
        gridModePinchFrameCoalescer.invalidate()
        stopGridModeSettleDisplayLink()
        stopGridModeInteractionFadeDisplayLink()
        guard let finishState = gridModeRenderer.finish(
            preservingCarryover: true
        ) else {
            removeGridModeCommitSnapshot()
            collectionView.clipsToBounds = true
            gridModeDestinationCache.removeAll(keepingCapacity: false)
            isApplyingPosition = false
            collectionView.isPrefetchingEnabled = true
            setGridModeScrollingSuspended(false)
            demoteVisibleBrowserImageLoadsIfNeeded()
            resumeVisibleBrowserImageLoadsIfNeeded()
            scheduleGridModeGeometryPrewarmIfPossible()
            return
        }
        let pannedContentOffsetY = finishState.pannedContentOffsetY.map {
            MobilePlayerBrowserGridTransition.clampedContentOffsetY(
                $0,
                contentHeight: browserCollectionLayout.browserLayout?
                    .contentSize.height ?? 0,
                viewportHeight: view.bounds.height
            )
        }
        collectionView.clipsToBounds = true
        gridModeDestinationCache.removeAll(keepingCapacity: false)
        if let pannedContentOffsetY {
            collectionView.contentOffset.y = pannedContentOffsetY
        }
        collectionView.layoutIfNeeded()
        if finishState.clearsTransitionPlaceholderTones {
            visibleBrowserCells.forEach {
                // A commit in this same drain tones still-loading regions;
                // their load's completion clears them. The sweep only covers
                // cells nothing else will run for.
                guard !$0.keepsTransitionPlaceholderToneForPendingLoad else {
                    return
                }
                $0.setTransitionPlaceholderTone(false)
            }
        }
        lastScrollOffsetY = collectionView.contentOffset.y
        isApplyingPosition = false
        collectionView.isPrefetchingEnabled =
            finishState.wasCollectionViewPrefetchingEnabled
        setGridModeScrollingSuspended(false)
        if settlesPosition {
            settleCurrentPosition()
        }
        demoteVisibleBrowserImageLoadsIfNeeded()
        resumeVisibleBrowserImageLoadsIfNeeded()
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    private func renderGridModeZoom(
        planeId: UUID?,
        scale: CGFloat,
        panDeltaY: CGFloat
    ) -> Bool {
        guard let sourceLayout = browserCollectionLayout.browserLayout else {
            return false
        }
        return gridModeRenderer.renderZoom(
            planeID: planeId,
            scale: scale,
            panDeltaY: panDeltaY,
            sourceLayout: sourceLayout
        )
    }

    private func renderGridModeSettle(
        id: UUID,
        scale: CGFloat,
        settleProgress: CGFloat,
        presentationProgress: CGFloat,
        panDeltaY: CGFloat
    ) -> Bool {
        gridModeRenderer.renderSettle(
            id: id,
            scale: scale,
            settleProgress: settleProgress,
            presentationProgress: presentationProgress,
            panDeltaY: panDeltaY
        )
    }

    private func commitGridModePlaneGeometry(
        id: UUID,
        mode: MobileCollectionBrowserGridMode
    ) -> Bool {
        let commitSnapshot = installGridModeSnapshotCover()
        guard let preparation = gridModeRenderer.prepareCommit(
            id: id,
            mode: mode,
            capturesFallbackSources: true
        ) else {
            removeGridModeCommitSnapshot()
            return false
        }
        startGridModeCommitSnapshotDissolve(commitSnapshot)
        var completed = false
        defer {
            if !completed {
                gridModeRenderer.abortCommit(preparation)
                removeGridModeCommitSnapshot()
            }
        }
        let plane = preparation.planeRequest
        layoutAspectState = plane.layoutAspectState
        gridModeCoordinator.beginCommitFadeWindow()
        let toLayout = plane.transitionLayout.toLayout
        installCollectionLayout(toLayout)
        applyGridModeTransitionEndpoint(
            layout: toLayout,
            contentOffsetY: preparation.terminalContentOffsetY
        )
        guard gridModeRenderer.completeCommit(preparation) else { return false }
        completed = true
        gridModeCommitSnapshotContentOffset = collectionView.contentOffset
        retainFocusedTokenIndex(plane.anchorTokenIndex)
        focusedTokenIndex = plane.anchorTokenIndex
        return true
    }

    /// Captures the rendered viewport before a plane's pixels are replaced,
    /// then dissolves it over the new presentation.
    @discardableResult
    private func installGridModeSnapshotCover() -> UIView {
        gridModeCoordinator.installSnapshotCover(
            viewportView: view,
            collectionView: collectionView
        )
    }

    private func startGridModeCommitSnapshotDissolve(_ snapshot: UIView) {
        gridModeCoordinator.startCommitSnapshotDissolve(snapshot)
    }

    /// A stale transition snapshot over a live grid is worse than a sharpen
    /// blink: every path that resumes rendering or scrolling must drop it.
    private func removeGridModeCommitSnapshot() {
        gridModeCoordinator.removeCommitSnapshot()
    }

    private func captureVisibleCarryoverSources(
        anchorTokenIndex: Int?
    ) -> [MobilePlayerBrowserGridCarryoverSource] {
        let eligibleSourceCells = collectionView.indexPathsForVisibleItems
            .sorted { $0.item < $1.item }
            .compactMap { indexPath -> (
                indexPath: IndexPath,
                cell: MobilePlayerCollectionBrowserCell
            )? in
                guard let cell = collectionView.cellForItem(
                    at: indexPath
                ) as? MobilePlayerCollectionBrowserCell else {
                    return nil
                }
                return (indexPath, cell)
            }
        let selectedItems = PlayerBrowserGridCarryoverSelection
            .selectedItemIndices(
                candidateItemIndices: eligibleSourceCells.map {
                    $0.indexPath.item
                },
                anchorItemIndex: anchorTokenIndex
            )
        let sourceCells = eligibleSourceCells.compactMap {
            selectedItems.contains($0.indexPath.item) ? $0.cell : nil
        }
        return MobilePlayerCollectionBrowserTransitionSupport.captureSources(
            from: sourceCells,
            in: view
        )
    }

    /// Preserves the highest-priority visible regions across the layout swap.
    private func installGridModeCarryoverContent(
        sources: [MobilePlayerBrowserGridCarryoverSource],
        anchorTokenIndex: Int? = nil
    ) {
        _ = MobilePlayerCollectionBrowserTransitionSupport.installCarryover(
            sources: sources,
            in: collectionView,
            viewportView: view,
            anchorItemIndex: anchorTokenIndex ?? focusedTokenIndex,
            hasImageSources: { tokenIndex in
                browseImageSources(forTokenIndex: tokenIndex) != nil
            }
        )
    }

    private func discardGridModePlane(id: UUID) -> Bool {
        guard let sourceLayout = browserCollectionLayout.browserLayout else {
            return false
        }
        return gridModeRenderer.discardPlane(
            id: id,
            sourceLayout: sourceLayout
        )
    }

    private func applyGridModeTransitionEndpoint(
        layout: MobilePlayerBrowserLayout,
        contentOffsetY: CGFloat
    ) {
        let contentOffsetY = MobilePlayerBrowserGridTransition.clampedContentOffsetY(
            contentOffsetY,
            contentHeight: layout.contentSize.height,
            viewportHeight: collectionView.bounds.height
        )
        collectionView.setContentOffset(
            CGPoint(
                x: canonicalContentOffsetX,
                y: contentOffsetY
            ),
            animated: false
        )
        collectionView.layoutIfNeeded()
        lastScrollOffsetY = collectionView.contentOffset.y
    }

    private func makeGridModeRatios(
        fromMode: MobileCollectionBrowserGridMode
    ) -> [PlayerBrowserGridInteractionCoordinator.ModeRatio] {
        guard fromMode == gridMode,
              let fromWidth = browserCollectionLayout.browserLayout?.itemWidth,
              fromWidth > 0 else {
            return []
        }
        return MobileCollectionBrowserGridMode.allCases.compactMap { mode in
            guard mode != fromMode else {
                return .init(mode: mode, itemWidthRatio: 1)
            }
            guard let width = MobilePlayerBrowserLayout.itemWidth(
                viewportSize: view.bounds.size,
                columnCount: mode.columnCount,
                displayScale: currentLayoutDisplayScale
            ) else {
                return nil
            }
            return .init(mode: mode, itemWidthRatio: width / fromWidth)
        }
    }

    private func gridModePinchFrame(
        _ recognizer: UIPinchGestureRecognizer
    ) -> GridModePinchFrame {
        GridModePinchFrame(
            scale: recognizer.scale,
            viewLocation: recognizer.location(in: view)
        )
    }

    private func finalizeGridModeInteractionIfNeeded() {
        let snapshotAtEntry = gridModeCommitSnapshotView
        defer {
            if gridModeCommitSnapshotView === snapshotAtEntry {
                removeGridModeCommitSnapshot()
            }
        }
        guard hasGridModeInteractionState else { return }
        gridModePinchFrameCoalescer.invalidate()
        lastGridModePinchViewLocation = nil
        let effects = gridModeInteractionCoordinator.handle(.interrupt)
        applyGridModeInteractionEffects(effects, transitionAnchor: nil)
        if gridModeInteractionCoordinator.phase == .idle {
            scheduleGridModeGeometryPrewarmIfPossible()
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === gridModePinchRecognizer else { return true }
        guard isActive,
              hasFinishedInitialPositioning,
              browseSnapshot?.itemCount ?? 0 > 0,
              collectionView.bounds.width > 0,
              collectionView.bounds.height > 0,
              preparedTransition == nil,
              gridModeInteractionCoordinator.canBeginPinch else {
            return false
        }
        return gridModeInteractionCoordinator.phase == .settling
            || !isApplyingPosition
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === gridModePinchRecognizer
            && otherGestureRecognizer === collectionView.panGestureRecognizer
    }

    @objc private func handleGridModePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            gridModePinchFrameCoalescer.invalidate()
            cancelGridModeGeometryPrewarming()
            let wasSettling = gridModeInteractionCoordinator.phase == .settling
            let frame = gridModePinchFrame(recognizer)
            lastGridModePinchViewLocation = frame.viewLocation
            gridModePinchFrameCoalescer.seed(frame)
            let initialGridMode = gridMode
            let ratios = makeGridModeRatios(fromMode: initialGridMode)
            let effects = gridModeInteractionCoordinator.handle(
                .pinchBegan(
                    sample: frame.sample,
                    currentMode: gridMode
                ),
                ratioProvider: { fromMode in
                    fromMode == initialGridMode ? ratios : []
                }
            )
            if wasSettling, effects.contains(.stopDisplayLink) {
                reanchorSettlingGridModeRendering(
                    at: frame.viewLocation
                )
            }
            applyGridModeInteractionEffects(
                effects,
                transitionAnchor: gridModePinchAnchorProvider(
                    viewLocation: frame.viewLocation
                )
            )
            if gridModeInteractionCoordinator.phase == .idle {
                scheduleGridModeGeometryPrewarmIfPossible()
            }

        case .changed:
            let frame = gridModePinchFrame(recognizer)
            lastGridModePinchViewLocation = frame.viewLocation
            gridModePinchFrameCoalescer.stage(frame)

        case .ended:
            let terminalEvent = PlayerBrowserGridInteractionCoordinator.Event.pinchEnded(
                scale: recognizer.scale,
                reduceMotion: UIAccessibility.isReduceMotionEnabled,
                timestamp: CACurrentMediaTime()
            )
            gridModePinchFrameCoalescer.flush()
            finishGridModePinch(terminalEvent)

        case .cancelled, .failed:
            gridModePinchFrameCoalescer.flush()
            finishGridModePinch(.pinchCancelled(
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            ))

        default:
            break
        }
    }

    private func reanchorSettlingGridModeRendering(at screenPoint: CGPoint) {
        gridModeRenderer.reanchorSettlingRendering(at: screenPoint)
    }

    private func applyGridModePinchFrame(_ frame: GridModePinchFrame) {
        let effects = gridModeInteractionCoordinator.handle(
            .pinchChanged(sample: frame.sample)
        )
        let rendersGestureGeometry = effects.contains { effect in
            switch effect {
            case .renderZoom, .renderSettle:
                true
            default:
                false
            }
        }
        applyGridModeInteractionEffects(
            effects,
            transitionAnchor: gridModePinchAnchorProvider(
                viewLocation: frame.viewLocation
            ),
            requestsGestureMaterializationBurst: rendersGestureGeometry
        )
    }

    private func finishGridModePinch(
        _ event: PlayerBrowserGridInteractionCoordinator.Event
    ) {
        let transitionAnchor = lastGridModePinchViewLocation.map {
            gridModePinchAnchorProvider(viewLocation: $0)
        }
        defer { lastGridModePinchViewLocation = nil }
        let effects = gridModeInteractionCoordinator.handle(event)
        applyGridModeInteractionEffects(
            effects,
            transitionAnchor: transitionAnchor
        )
        if gridModeInteractionCoordinator.phase == .idle {
            scheduleGridModeGeometryPrewarmIfPossible()
        }
    }

    private func advanceGridModeInteractionTick(
        _ event: PlayerBrowserGridInteractionCoordinator.Event
    ) {
        let effects = gridModeInteractionCoordinator.handle(
            event
        )
        applyGridModeInteractionEffects(effects, transitionAnchor: nil)
    }

    private func startGridModeSettleDisplayLink() {
        gridModeCoordinator.startSettleDisplayLink(
            collectionView: collectionView
        )
    }

    private func stopGridModeSettleDisplayLink() {
        gridModeCoordinator.stopSettleDisplayLink(
            collectionView: collectionView
        )
    }

    private func startGridModeInteractionFadeDisplayLink() {
        gridModeCoordinator.startInteractionFadeDisplayLink()
    }

    private func stopGridModeInteractionFadeDisplayLink() {
        gridModeCoordinator.stopInteractionFadeDisplayLink()
    }

    @discardableResult
    private func applyGridModeInteractionEffects(
        _ initialEffects: [PlayerBrowserGridInteractionCoordinator.Effect],
        transitionAnchor: (() -> GridModeGestureAnchor?)?,
        requestsGestureMaterializationBurst: Bool = false
    ) -> Bool {
        let result = drainGridModeInteractionEffects(
            initialEffects,
            transitionAnchor: transitionAnchor
        )
        if gridModeInteractionCoordinator.phase != .interacting {
            gridModeRenderer.cancelGestureMaterializationBurst()
        } else if requestsGestureMaterializationBurst {
            gridModeRenderer.requestGestureMaterializationBurst()
        }
        if result.needsVisibleCellQualityReconciliation {
            reloadVisibleCells()
        }
        return result.succeeded
    }

    private func drainGridModeInteractionEffects(
        _ initialEffects: [PlayerBrowserGridInteractionCoordinator.Effect],
        transitionAnchor: (() -> GridModeGestureAnchor?)?
    ) -> (
        succeeded: Bool,
        needsVisibleCellQualityReconciliation: Bool
    ) {
        gridModeEffectDrainDepth += 1
        defer { gridModeEffectDrainDepth -= 1 }
        var pendingEffects = initialEffects
        var needsVisibleCellQualityReconciliation = false
        var rendererRecoverySucceeded = true

        func reconcileVisibleCellsIfNeeded() {
            guard needsVisibleCellQualityReconciliation else { return }
            needsVisibleCellQualityReconciliation = false
            reloadVisibleCells()
        }

        func enqueueRendererFailureRecovery() {
            let effects = gridModeInteractionCoordinator.handle(
                .rendererFailed
            )
            rendererRecoverySucceeded = rendererRecoverySucceeded
                && effects.contains { effect in
                    if case .applyMode = effect {
                        return true
                    }
                    return false
                }
            pendingEffects = effects.isEmpty
                ? [.resetRenderer, .finishInteraction(settlesPosition: false)]
                : effects
        }

        effectLoop: while !pendingEffects.isEmpty {
            let effect = pendingEffects.removeFirst()
            switch effect {
            case .beginInteraction:
                removeGridModeCommitSnapshot()
                applyGridModeInteractionBegan(
                    transitionAnchor: transitionAnchor
                )

            case .coverPlaneChange:
                if gridModeRenderer.planeChangeNeedsVisualCover {
                    startGridModeCommitSnapshotDissolve(
                        installGridModeSnapshotCover()
                    )
                }

            case let .installPlane(plane):
                guard let context = makeGridModePlaneRequest(plane: plane),
                      gridModeRenderer.installPlane(context) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }

            case let .renderZoom(planeId, scale, panDeltaY):
                guard renderGridModeZoom(
                    planeId: planeId,
                    scale: scale,
                    panDeltaY: panDeltaY
                ) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }

            case let .renderSettle(
                id,
                scale,
                settleProgress,
                presentationProgress,
                panDeltaY
            ):
                guard renderGridModeSettle(
                    id: id,
                    scale: scale,
                    settleProgress: settleProgress,
                    presentationProgress: presentationProgress,
                    panDeltaY: panDeltaY
                ) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }

            case let .renderInteractionFade(id, presentationProgress):
                guard gridModeRenderer.renderInteractionFade(
                    id: id,
                    presentationProgress: presentationProgress
                ) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }

            case let .commitPlane(id, mode):
                guard commitGridModePlaneGeometry(id: id, mode: mode) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                needsVisibleCellQualityReconciliation = true
                prependGridModeRendererSuccessEffects(to: &pendingEffects)

            case let .discardPlane(id):
                guard discardGridModePlane(id: id) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                prependGridModeRendererSuccessEffects(to: &pendingEffects)

            case let .applyMode(mode):
                guard applyGridModeWithoutAnimation(
                    mode,
                    retainedTokenIndex: gridModeRenderer.renderSnapshot?
                        .gestureAnchor?.tokenIndex
                ) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                needsVisibleCellQualityReconciliation = true
                prependGridModeRendererSuccessEffects(to: &pendingEffects)

            case .resetRenderer:
                resetGridModeRenderer()
                needsVisibleCellQualityReconciliation = true

            case .selectionHaptic:
                Haptic.selectionChanged()

            case .startDisplayLink:
                stopGridModeInteractionFadeDisplayLink()
                startGridModeSettleDisplayLink()
                setGridModeScrollingSuspended(false)
                let continuedEffects = gridModeInteractionCoordinator.handle(
                    .settleStarted(timestamp: CACurrentMediaTime())
                )
                pendingEffects.insert(contentsOf: continuedEffects, at: 0)

            case .stopDisplayLink:
                stopGridModeSettleDisplayLink()

            case .startInteractionFadeTicks:
                startGridModeInteractionFadeDisplayLink()

            case .stopInteractionFadeTicks:
                stopGridModeInteractionFadeDisplayLink()

            case let .reconcileMedia(cancelsPrefetchLoads):
                if cancelsPrefetchLoads {
                    imagePipeline.cancelAllPrefetchLoads()
                }
                imagePipeline.resetThumbnailWindow()
                needsVisibleCellQualityReconciliation = true
                reconcileVisibleCellsIfNeeded()

            case let .finishInteraction(settlesPosition):
                reconcileVisibleCellsIfNeeded()
                applyGridModeInteractionFinished(
                    settlesPosition: settlesPosition
                )
            }
        }
        return (
            rendererRecoverySucceeded,
            needsVisibleCellQualityReconciliation
        )
    }

    private func prependGridModeRendererSuccessEffects(
        to pendingEffects: inout [PlayerBrowserGridInteractionCoordinator.Effect]
    ) {
        let continuedEffects = gridModeInteractionCoordinator.handle(
            .rendererSucceeded
        )
        pendingEffects.insert(contentsOf: continuedEffects, at: 0)
    }

    private func resetGridModeRenderer() {
        removeGridModeCommitSnapshot()
        let anchoredContentOffsetY = gridModeRenderer.reset()
        guard let layout = browserCollectionLayout.browserLayout else {
            return
        }
        applyGridModeTransitionEndpoint(
            layout: layout,
            contentOffsetY: anchoredContentOffsetY
                ?? collectionView.contentOffset.y
        )
    }

    private func applyGridModeWithoutAnimation(
        _ gridMode: MobileCollectionBrowserGridMode,
        retainedTokenIndex: Int?
    ) -> Bool {
        guard gridModeRenderer.isActive, let browseSnapshot else {
            return false
        }
        let tokenIndex = retainedTokenIndex
            ?? gridModeAnchorTokenIndex()
            ?? browseSnapshot.initialTokenIndex
        guard let destination = makeGridModeDestination(
            mode: gridMode,
            anchorTokenIndex: tokenIndex
        ), destination.layout.itemFrame(at: tokenIndex) != nil else {
            return false
        }
        guard let preparation = gridModeRenderer.prepareDirectCommit() else {
            return false
        }
        var completed = false
        defer {
            if !completed {
                gridModeRenderer.abortDirectCommit(preparation)
            }
        }
        layoutAspectState = destination.layoutAspectState
        installCollectionLayout(destination.layout)
        centerContent(on: tokenIndex)
        guard gridModeRenderer.completeDirectCommit(preparation) else {
            return false
        }
        completed = true
        gridModeRenderer.updateGestureAnchor(nil)
        retainFocusedTokenIndex(tokenIndex)
        focusedTokenIndex = tokenIndex
        lastScrollOffsetY = collectionView.contentOffset.y
        collectionView.layoutIfNeeded()
        visibleBrowserCells.forEach {
            $0.setTransitionPlaceholderTone(false)
        }
        return true
    }

    private func gridModePinchAnchorProvider(
        viewLocation: CGPoint
    ) -> () -> GridModeGestureAnchor? {
        { [weak self] in
            self?.pinchGridModeGestureAnchor(viewLocation: viewLocation)
        }
    }

    private func pinchGridModeGestureAnchor(
        viewLocation: CGPoint
    ) -> GridModeGestureAnchor? {
        let contentPoint = collectionView.convert(viewLocation, from: view)
        if let indexPath = collectionView.indexPathForItem(
            at: contentPoint
        ) {
            return makeGridModeGestureAnchor(
                tokenIndex: indexPath.item,
                preferredContentPoint: contentPoint
            )
        }
        return makeGridModeGestureAnchor(
            tokenIndex: gridModeAnchorTokenIndex() ?? 0,
            preferredContentPoint: gridModeVisualFocalPoint()
        )
    }

    /// `makeGridModeGestureAnchor` resolves mirrored view geometry, while
    /// `currentFocalPoint` resolves the unmirrored layout model.
    private func gridModeVisualFocalPoint() -> CGPoint {
        let focalPoint = currentFocalPoint()
        guard let layout = browserCollectionLayout.browserLayout else {
            return focalPoint
        }
        return gridModeVisualGeometry(for: layout).mirroredPoint(focalPoint)
    }

    /// Resolves the anchor the way every grid-mode entry point does. Not a
    /// property: `currentAnchorTokenIndex()` resolves visible geometry and can
    /// clear `forcedFocusedTokenIndex`, so this must be called once.
    private func gridModeAnchorTokenIndex() -> Int? {
        currentAnchorTokenIndex()
            ?? forcedFocusedTokenIndex
            ?? focusedTokenIndex
            ?? browseSnapshot?.initialTokenIndex
    }

    func setActive(_ active: Bool) {
        if active {
            loadViewIfNeeded()
        }
        guard isActive != active else {
            if active {
                performInitialPositioningIfNeeded()
            }
            return
        }
        finalizeGridModeInteractionIfNeeded()

        if active,
           let preparation = preparedTransition?.preparation,
           !finalizePreparedDisplay(preparation) {
            return
        }

        if !active {
            cancelGridModeGeometryPrewarming()
            flushSettledPosition()
            endScrollMotionAndResetDragState()
            cancelScheduledScrollUpdate()
            cancelPendingFocusPublication(resetLastPublicationTime: true)
            imagePipeline.cancelAllPrefetchLoads()
            imagePipeline.resetThumbnailWindow()
            imagePipeline.cancelVisibleCellImageLoads()
        }

        isActive = active
        collectionView.isScrollEnabled = active
        collectionView.isUserInteractionEnabled = active
        collectionView.scrollsToTop = active
        if active {
            reloadBrowseSnapshot(
                resetPublicationState: browseSnapshot == nil
            )
            reloadVisibleCells()
            performInitialPositioningIfNeeded()
            if hasFinishedInitialPositioning {
                observeCurrentAnchor(
                    focusCadence: .immediate,
                    preparesThumbnailWindow: true,
                    forcesThumbnailWindow: true
                )
                publishSettledTokenIfNeeded()
            }
            scheduleGridModeGeometryPrewarmIfPossible()
        }
    }

    func prepareForDisplay(
        using preparation: PlayerCollectionBrowsePreparation,
        forcePosition: Bool = false,
        publishWhenStable: Bool,
        completion: @escaping @MainActor (
            MobilePlayerCollectionBrowserDisplayPreparationResult
        ) -> Void
    ) {
        loadViewIfNeeded()
        finalizeGridModeInteractionIfNeeded()
        let generation = scrollCoordinator.beginPositioning()
        guard isValid(preparation) else {
            isApplyingPosition = false
            cancelPreparedTransition()
            completion(.unavailable)
            return
        }
        endScrollMotionAndResetDragState()

        if let preparedTransition,
           preparedTransition.preparation != preparation {
            restorePreparedTransition(preparedTransition)
        }
        if preparedTransition == nil {
            preparedTransition = makePreparedTransition(for: preparation)
        }

        isApplyingPosition = true
        let snapshotChanged = applyBrowseSnapshotIfNeeded(
            preparation.snapshot,
            sampledAround: preparation.focusedTokenIndex
        )

        scrollCoordinator.beginPublicationPositioning(
            at: preparation.focusedTokenIndex,
            snapshotChanged: snapshotChanged
        )

        if forcePosition
            || snapshotChanged
            || !isTokenFullyVisible(preparation.focusedTokenIndex) {
            centerContent(on: preparation.focusedTokenIndex)
        }
        retainFocusedTokenIndex(preparation.focusedTokenIndex)
        focusedTokenIndex = preparation.focusedTokenIndex
        collectionView.layoutIfNeeded()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                completion(.superseded)
                return
            }
            guard self.scrollCoordinator
                .isCurrentPositioningGeneration(generation) else {
                completion(.superseded)
                return
            }

            self.collectionView.layoutIfNeeded()
            self.scrollCoordinator.finishPositioning()
            self.resumeVisibleBrowserImageLoadsIfNeeded()
            self.scrollCoordinator.observe(
                tokenIndex: preparation.focusedTokenIndex,
                focusCadence: .immediate
            )
            if publishWhenStable, self.isActive {
                self.publishSettledTokenIfNeeded()
            }
            self.prepareThumbnailWindow(
                around: preparation.focusedTokenIndex,
                direction: self.lastPrefetchDirection,
                force: true
            )
            if self.isActive {
                self.preparedTransition = nil
            }
            self.scheduleGridModeGeometryPrewarmIfPossible()
            completion(.prepared)
        }
    }

    func canCommitPreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) -> Bool {
        !isActive
            && !isApplyingPosition
            && browseSnapshot == preparation.snapshot
            && preparedTransition?.preparation == preparation
    }

    func commitPreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) {
        assert(canCommitPreparedDisplay(preparation))
        preparedTransition = nil
    }

    @discardableResult
    func finalizePreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) -> Bool {
        guard browseSnapshot == preparation.snapshot else { return false }
        guard let preparedTransition else { return true }
        guard preparedTransition.preparation == preparation,
              MobilePlaybackController.shared.collectionBrowseSnapshot(uuid: uuid) == preparation.snapshot else {
            return false
        }
        self.preparedTransition = nil
        return true
    }

    func cancelPendingDisplayPreparation() {
        scrollCoordinator.cancelPositioning()
        cancelPreparedTransition()
    }

    func canSelectItem(at location: CGPoint, in coordinateView: UIView) -> Bool {
        guard isActive, !hasGridModeInteractionState else { return false }
        let point = collectionView.convert(location, from: coordinateView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else {
            return false
        }
        return canSelectBrowserCell(at: indexPath.item)
    }

    private func canSelectBrowserCell(at tokenIndex: Int) -> Bool {
        guard gridModeCommitSnapshotView == nil,
              let identity = browserContentIdentity(
            forTokenIndex: tokenIndex
        ),
              let cell = collectionView.cellForItem(
                  at: IndexPath(item: tokenIndex, section: 0)
              ) as? MobilePlayerCollectionBrowserCell else {
            return false
        }
        return cell.canSelect(representing: identity)
    }

    func preparedTransitionSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection? {
        guard let preparation = MobilePlaybackController.shared.prepareCollectionBrowse(
            uuid: uuid,
            containing: pagePosition
        ) else {
            return nil
        }
        return preparedTransitionSelection(using: preparation)
    }

    func preparedTransitionSelection(
        using preparation: PlayerCollectionBrowsePreparation
    ) -> MobilePlayerBrowserTransitionSelection? {
        loadViewIfNeeded()
        finalizeGridModeInteractionIfNeeded()
        guard isValid(preparation) else { return nil }
        endScrollMotionAndResetDragState()

        if let preparedTransition,
           preparedTransition.preparation != preparation {
            restorePreparedTransition(preparedTransition)
        }

        if preparedTransition == nil {
            preparedTransition = makePreparedTransition(for: preparation)
        }

        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        isApplyingPosition = true
        let snapshotChanged = applyBrowseSnapshotIfNeeded(
            preparation.snapshot,
            sampledAround: preparation.focusedTokenIndex
        )
        publicationState = PlayerCollectionScrollPublicationState(
            initialIndex: preparation.focusedTokenIndex
        )
        hasFinishedInitialPositioning = false
        lastEmittedFocusedTokenIndex = nil
        imagePipeline.resetThumbnailWindow()
        if snapshotChanged
            || !isTokenFullyVisible(preparation.focusedTokenIndex) {
            centerContent(on: preparation.focusedTokenIndex)
        }
        retainFocusedTokenIndex(preparation.focusedTokenIndex)
        focusedTokenIndex = preparation.focusedTokenIndex
        collectionView.layoutIfNeeded()
        isApplyingPosition = false
        guard let selection = transitionSelection(
            tokenIndex: preparation.focusedTokenIndex
        ) else {
            cancelPreparedTransition()
            return nil
        }
        return selection
    }

    func cancelPreparedTransition() {
        guard let preparedTransition else { return }
        restorePreparedTransition(preparedTransition)
    }

    private func isValid(_ preparation: PlayerCollectionBrowsePreparation) -> Bool {
        preparation.snapshot.pagePosition(
            forTokenIndex: preparation.focusedTokenIndex
        ) != nil
    }

    private func makePreparedTransition(
        for preparation: PlayerCollectionBrowsePreparation
    ) -> PreparedTransition {
        PreparedTransition(
            preparation: preparation,
            contentOffset: collectionView.contentOffset,
            layoutSize: collectionView.bounds.size,
            layoutDisplayScale: lastLayoutDisplayScale > 0
                ? lastLayoutDisplayScale
                : currentLayoutDisplayScale,
            layoutWindowSafeAreaInsets: layoutWindowSafeAreaInsets,
            verticalContentOffsetRange: verticalContentOffsetRange,
            browseSnapshot: browseSnapshot,
            scrollCoordinatorSnapshot: scrollCoordinator.snapshot(),
            imagePipelineSnapshot: imagePipeline.snapshot(),
            layoutAspectState: layoutAspectState
        )
    }

    private func restorePreparedTransition(_ preparedTransition: PreparedTransition) {
        self.preparedTransition = nil
        cancelGridModeGeometryPrewarming()
        gridModeGeometryCache = nil
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        isApplyingPosition = true

        browseSnapshot = preparedTransition.browseSnapshot
        layoutAspectState = preparedTransition.layoutAspectState
        imagePipeline.cancelAllPrefetchLoads()
        imagePipeline.cancelVisibleCellImageLoads()
        collectionView.reloadData()
        configureCollectionLayout()
        collectionView.layoutIfNeeded()

        let layoutSizeAndScaleUnchanged =
            preparedTransition.layoutSize == collectionView.bounds.size
            && preparedTransition.layoutDisplayScale
                == currentLayoutDisplayScale
        let canRestoreExactGeometry =
            layoutSizeAndScaleUnchanged
            && preparedTransition.layoutWindowSafeAreaInsets
                == layoutWindowSafeAreaInsets
            && preparedTransition.verticalContentOffsetRange
                == verticalContentOffsetRange
        if layoutSizeAndScaleUnchanged {
            let restoredContentOffset = canRestoreExactGeometry
                ? preparedTransition.contentOffset
                : contentOffsetAfterSafeAreaChange(
                    previousContentOffset: preparedTransition.contentOffset,
                    previousTopContentInset:
                        preparedTransition.layoutWindowSafeAreaInsets.top,
                    previousVerticalContentOffsetRange:
                        preparedTransition.verticalContentOffsetRange
                )
            collectionView.setContentOffset(
                restoredContentOffset,
                animated: false
            )
        } else if let focusedTokenIndex = preparedTransition
            .scrollCoordinatorSnapshot.forcedFocusedTokenIndex
            ?? preparedTransition.scrollCoordinatorSnapshot.focusedTokenIndex {
            centerContent(on: focusedTokenIndex)
        } else {
            collectionView.setContentOffset(clampedContentOffset(preparedTransition.contentOffset), animated: false)
        }
        collectionView.layoutIfNeeded()

        let scrollSnapshot = preparedTransition.scrollCoordinatorSnapshot
        let restoredRetainedFocusFocalBias: PlayerCollectionScrollFocalBias?
        if let forcedFocusedTokenIndex = scrollSnapshot.forcedFocusedTokenIndex {
            if canRestoreExactGeometry {
                restoredRetainedFocusFocalBias =
                    scrollSnapshot.retainedFocusFocalBias
                    ?? makeFocalBias(for: forcedFocusedTokenIndex)
            } else {
                restoredRetainedFocusFocalBias =
                    makeFocalBias(for: forcedFocusedTokenIndex)
            }
        } else {
            restoredRetainedFocusFocalBias = canRestoreExactGeometry
                ? scrollSnapshot.retainedFocusFocalBias
                : nil
        }
        scrollCoordinator.restore(
            scrollSnapshot,
            retainedFocusFocalBias: restoredRetainedFocusFocalBias,
            lastScrollOffsetY: canRestoreExactGeometry
                ? scrollSnapshot.lastScrollOffsetY
                : collectionView.contentOffset.y
        )
        imagePipeline.restore(preparedTransition.imagePipelineSnapshot)
        isApplyingPosition = false
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    func scrollToFirstItemAndPublish() {
        guard let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: 0),
              let preparation = MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: uuid,
                containing: pagePosition
              ) else {
            return
        }

        endScrollMotionAndResetDragState()
        prepareForDisplay(
            using: preparation,
            forcePosition: true,
            publishWhenStable: true
        ) { _ in }
    }

    func flushSettledPosition() {
        guard isActive else { return }
        finalizeGridModeInteractionIfNeeded()
        cancelScheduledScrollUpdate()
        observeCurrentAnchor(
            focusCadence: .immediate,
            preparesThumbnailWindow: false,
            forcesThumbnailWindow: false
        )
        scrollCoordinator.finalFlush(hasViewedToEnd: hasViewedToEnd)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        browseSnapshot?.itemCount ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.cellReuseIdentifier,
            for: indexPath
        )
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else { return cell }
        configureBrowserCell(browserCell, at: indexPath)
        gridModeRenderer.didConfigureCell(browserCell, at: indexPath)
        return browserCell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        gridModeRenderer.willDisplayCell(cell, at: indexPath)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        imagePipeline.willDisplay(
            cell: browserCell,
            tokenIndex: indexPath.item,
            intersectsViewport: {
                MobilePlayerCollectionBrowserTransitionSupport
                    .itemIntersectsViewport(
                    at: indexPath,
                    cell: browserCell,
                    collectionView: collectionView,
                    viewportView: view
                )
            }
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        imagePipeline.willEndDisplaying(tokenIndex: indexPath.item)
        gridModeRenderer.didEndDisplayingCell(cell, at: indexPath)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        imagePipeline.didEndDisplaying(
            cell: browserCell,
            tokenIndex: indexPath.item
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        isActive
            && !hasGridModeInteractionState
            && canSelectBrowserCell(at: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        performSelection(at: indexPath.item)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard isActive,
              !hasGridModeInteractionState,
              canSelectBrowserCell(at: indexPath.item),
              let snapshot = browseSnapshot,
              let descriptor = MobilePlaybackController.shared.collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: indexPath.item
              ),
              !descriptor.collectionId.isEmpty,
              !descriptor.tokenId.isEmpty else {
            return nil
        }

        let configuration = UIContextMenuConfiguration(
            identifier: indexPath as NSIndexPath,
            previewProvider: nil
        ) { [weak self] _ in
            guard self?.canSelectBrowserCell(at: indexPath.item) == true else {
                return nil
            }
            let token = MobileCollectionCatalog.generateToken(
                specificCollectionId: descriptor.collectionId,
                tokenIndex: descriptor.tokenIndex
            )

            var children: [UIMenuElement] = [
                UIDeferredMenuElement.uncached { completion in
                    Task {
                        let storedState = PlayerBookmarksStore.storedBookmarkState(
                            collectionId: descriptor.collectionId,
                            tokenId: descriptor.tokenId
                        )
                        let resolvedIsBookmarked = storedState.isReady
                            ? storedState.isBookmarked
                            : await PlayerBookmarksStore.shared.isBookmarked(
                                collectionId: descriptor.collectionId,
                                tokenId: descriptor.tokenId
                            )
                        let latestState = PlayerBookmarksStore.storedBookmarkState(
                            collectionId: descriptor.collectionId,
                            tokenId: descriptor.tokenId
                        )
                        let isBookmarked = latestState.isReady
                            ? latestState.isBookmarked
                            : resolvedIsBookmarked
                        let action = UIAction(
                            title: isBookmarked ? Strings.removeBookmark : Strings.bookmark,
                            image: UIImage(
                                systemName: isBookmarked ? "bookmark.fill" : "bookmark"
                            ),
                            attributes: latestState.isTogglePending ? .disabled : []
                        ) { _ in
                            let didBeginToggle = PlayerBookmarksStore.enqueueBookmarkUpdate(
                                collectionId: descriptor.collectionId,
                                tokenId: descriptor.tokenId,
                                isBookmarked: !isBookmarked
                            )
                            if didBeginToggle {
                                Haptic.selectionChanged()
                            }
                        }
                        completion([action])
                    }
                }
            ]
            if let url = token?.url {
                children.append(
                    UIAction(title: Strings.viewOnBlockExplorer, image: UIImage(systemName: "globe")) { _ in
                        UIApplication.shared.open(url)
                    }
                )
            }

            return UIMenu(title: token?.displayName ?? "", children: children)
        }
        configuration.preferredMenuElementOrder = .fixed
        return configuration
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let indexPath = configuration.identifier as? IndexPath else { return }
        let tokenIndex = indexPath.item
        guard canSelectBrowserCell(at: tokenIndex) else {
            animator.preferredCommitStyle = .dismiss
            return
        }
        guard let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) else {
            animator.preferredCommitStyle = .dismiss
            animator.addCompletion { [weak self] in
                self?.performSelection(at: tokenIndex)
            }
            return
        }

        var didFinishCommitAnimation = false
        var didFailSwitch = false
        var didRunFallback = false
        let runFallbackIfReady = { [weak self] in
            guard didFinishCommitAnimation,
                  didFailSwitch,
                  !didRunFallback else {
                return
            }
            didRunFallback = true
            self?.performSelection(at: tokenIndex)
        }
        guard onImmediateSelection?(pagePosition, {
            didFailSwitch = true
            runFallbackIfReady()
        }) == true else {
            animator.preferredCommitStyle = .dismiss
            animator.addCompletion { [weak self] in
                self?.performSelection(at: tokenIndex)
            }
            return
        }

        animator.preferredCommitStyle = .pop
        animator.addCompletion {
            didFinishCommitAnimation = true
            runFallbackIfReady()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let quality = requiredImageQuality
        imagePipeline.prefetch(
            indexPaths: indexPaths,
            centerTokenIndex: { [weak self] in
                self?.focusedTokenIndex
                    ?? self?.currentAnchorTokenIndex()
                    ?? 0
            },
            requiredImageQuality: quality,
            descriptor: { [weak self] tokenIndex in
                guard let snapshot = self?.browseSnapshot else { return nil }
                return MobilePlaybackController.shared
                    .collectionBrowsePrefetchDescriptor(
                        snapshot: snapshot,
                        tokenIndex: tokenIndex,
                        quality: quality
                    )
            }
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        imagePipeline.cancelPrefetching(indexPaths: indexPaths)
    }

    private func gridModeContentOffsetTarget(
        for requestedContentOffset: CGPoint,
        animated: Bool
    ) -> (target: CGPoint, settlesAfterApplying: Bool) {
        let requestedDeltaY = requestedContentOffset.y
            - collectionView.contentOffset.y
        guard requestedDeltaY.isFinite else {
            return (collectionView.contentOffset, false)
        }
        guard requestedDeltaY != 0 else {
            guard gridModeInteractionCoordinator.phase == .settling else {
                return (requestedContentOffset, false)
            }
            return (
                CGPoint(
                    x: canonicalContentOffsetX,
                    y: requestedContentOffset.y
                ),
                false
            )
        }
        guard finalizeInterruptibleGridModeSettle() else {
            if gridModeInteractionCoordinator.phase == .idle,
               gridModeEffectDrainDepth == 0 {
                removeGridModeCommitSnapshot()
            }
            return (requestedContentOffset, false)
        }
        let target = clampedContentOffset(CGPoint(
            x: collectionView.contentOffset.x,
            y: collectionView.contentOffset.y + requestedDeltaY
        ))
        return (
            target,
            !animated || target == collectionView.contentOffset
        )
    }

    private func settleAfterImmediateGridModeOffsetIfPossible() {
        guard gridModeInteractionCoordinator.phase == .idle,
              !isApplyingPosition,
              !collectionView.isTracking,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              !isScrollMotionActive else {
            return
        }
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    private func resolveScrollObservedDuringGridModeSettle(
        _ scrollView: UIScrollView
    ) -> Bool {
        guard hasInterruptibleGridModeSettle else { return false }
        let observedContentOffsetY = scrollView.contentOffset.y
        let settleContentOffsetY = gridModeSettleContentOffsetY
            ?? lastScrollOffsetY
            ?? observedContentOffsetY
        let observedDeltaY = observedContentOffsetY - settleContentOffsetY
        guard observedDeltaY.isFinite else { return false }
        guard observedDeltaY != 0 else {
            let canonicalContentOffset = CGPoint(
                x: canonicalContentOffsetX,
                y: observedContentOffsetY
            )
            if canonicalContentOffset != scrollView.contentOffset {
                scrollView.setContentOffset(
                    canonicalContentOffset,
                    animated: false
                )
            }
            return false
        }
        return resumeObservedGridModeSettleOffset(
            settleContentOffsetY: settleContentOffsetY,
            observedDeltaY: observedDeltaY
        )
    }

    private func resumeObservedGridModeSettleOffset(
        settleContentOffsetY: CGFloat,
        observedDeltaY: CGFloat
    ) -> Bool {
        gridModeContentOffsetRestorationDepth += 1
        defer { gridModeContentOffsetRestorationDepth -= 1 }
        collectionView.setContentOffsetWithoutResolution(CGPoint(
            x: canonicalContentOffsetX,
            y: settleContentOffsetY
        ))
        collectionView.layoutIfNeeded()
        finalizeGridModeInteractionIfNeeded()
        guard gridModeInteractionCoordinator.phase == .idle else {
            lastScrollOffsetY = collectionView.contentOffset.y
            return false
        }
        removeGridModeCommitSnapshot()
        let committedContentOffsetY = collectionView.contentOffset.y
        lastScrollOffsetY = committedContentOffsetY
        let resumedContentOffset = CGPoint(
            x: canonicalContentOffsetX,
            y: clampedVerticalContentOffsetY(
                committedContentOffsetY + observedDeltaY
            )
        )
        let resumedDeltaY = resumedContentOffset.y - committedContentOffsetY
        if abs(resumedDeltaY) > Self.boundaryEpsilon {
            lastPrefetchDirection = resumedDeltaY > 0 ? .forward : .backward
        }
        if resumedContentOffset != collectionView.contentOffset {
            collectionView.setContentOffsetWithoutResolution(
                resumedContentOffset
            )
        }
        return true
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        interruptGridModeSettleForDragIfNeeded()
        removeGridModeCommitSnapshot()
        cancelScrollMotionAnimationTimeout()
        if scrollCoordinator.beginDrag(
            contentOffsetY: scrollView.contentOffset.y,
            clampedContentOffsetY:
                clampedVerticalContentOffsetY(scrollView.contentOffset.y)
        ) {
            imagePipeline.setScrollMotionActive(true)
            cancelGridModeGeometryPrewarming()
            demoteVisibleBrowserImageLoadsIfNeeded()
        }
        let verticalRange = verticalContentOffsetRange
        if verticalRange.upperBound - verticalRange.lowerBound <= Self.boundaryEpsilon,
           scrollCoordinator.markCurrentDragAcknowledged() {
            MobilePlaybackController.shared.acknowledgeIntentionalViewingPosition(uuid: uuid)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if gridModeContentOffsetRestorationDepth > 0 {
            _ = scrollCoordinator.observeContentOffset(scrollView.contentOffset.y)
            return
        }
        if let snapshotContentOffset = gridModeCommitSnapshotContentOffset,
           gridModeEffectDrainDepth == 0,
           scrollView.contentOffset != snapshotContentOffset {
            removeGridModeCommitSnapshot()
        }
        let settlesAfterImmediateGridModeOffset =
            resolveScrollObservedDuringGridModeSettle(scrollView)
        let previousOffsetY = scrollCoordinator.observeContentOffset(
            scrollView.contentOffset.y
        )
        guard isActive,
              hasFinishedInitialPositioning,
              !isApplyingPosition else {
            return
        }
        releaseRetainedFocusForOutwardPullIfNeeded(scrollView)
        acknowledgeIntentionalScrollIfNeeded(scrollView)
        if let previousOffsetY {
            let offsetDelta = PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
                previousOffsetY: previousOffsetY,
                currentOffsetY: scrollView.contentOffset.y,
                validRange: verticalContentOffsetRange
            )
            _ = scrollCoordinator.updatePrefetchDirection(
                offsetDelta: offsetDelta,
                epsilon: Self.boundaryEpsilon
            )
        }
        scheduleScrollUpdate()
        if settlesAfterImmediateGridModeOffset {
            settleAfterImmediateGridModeOffsetIfPossible()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        endScrollMotionAndResetDragState()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        endScrollMotionAndResetDragState()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settleScrollMotionIfIdle(scrollView)
    }

    private func settleScrollMotionIfIdle(_ scrollView: UIScrollView) {
        guard !scrollView.isTracking,
              !scrollView.isDragging,
              !scrollView.isDecelerating,
              dragStartContentOffsetY == nil else {
            return
        }
        endScrollMotion()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        guard isActive else { return false }
        let interruptedGridModeSettle = finalizeInterruptibleGridModeSettle()
        guard !hasGridModeInteractionState else { return false }
        endScrollMotionAndResetDragState()
        let hasScrollMotion =
            scrollView.contentOffset.y
                > verticalContentOffsetRange.lowerBound + Self.boundaryEpsilon
        if hasScrollMotion {
            beginScrollMotion()
            removeGridModeCommitSnapshot()
            scheduleScrollMotionAnimationTimeout()
        }
        retainFocusedTokenIndex(nil)
        cancelScheduledScrollUpdate()
        lastScrollOffsetY = scrollView.contentOffset.y
        if interruptedGridModeSettle, !hasScrollMotion {
            settleAfterImmediateGridModeOffsetIfPossible()
        }
        return true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        settleScrollMotionIfIdle(scrollView)
    }

    private func applyBrowseSnapshotIfNeeded(
        _ snapshot: PlayerCollectionBrowseSnapshot?,
        sampledAround focusedTokenIndex: Int?
    ) -> Bool {
        let snapshotChanged = browseSnapshot != snapshot
        if snapshotChanged {
            applyBrowseSnapshot(
                snapshot,
                sampledAround: focusedTokenIndex,
                gridMode: gridMode
            )
        }
        return snapshotChanged
    }

    private func applyBrowseSnapshot(
        _ snapshot: PlayerCollectionBrowseSnapshot?,
        sampledAround focusedTokenIndex: Int?,
        gridMode: MobileCollectionBrowserGridMode
    ) {
        cancelGridModeGeometryPrewarming()
        let cachedGeometry: CachedGridModeGeometry?
        if let snapshot {
            ensureGridModeGeometryCache(snapshot: snapshot)
            cachedGeometry = gridModeGeometryCache?.geometries[gridMode]
        } else {
            gridModeGeometryCache = nil
            cachedGeometry = nil
        }
        browseSnapshot = snapshot
        if let snapshot, let cachedGeometry {
            layoutAspectState = MobilePlayerCollectionBrowserLayoutAspectState(
                aspectProfile: cachedGeometry.aspectProfile,
                fallbackSpec: makeLayoutFallbackSpec(
                    snapshot: snapshot,
                    focusedTokenIndex: focusedTokenIndex
                )
            )
        } else {
            updateLayoutAspectProfile(
                snapshot: snapshot,
                focusedTokenIndex: focusedTokenIndex,
                columnCount: gridMode.columnCount
            )
        }
        imagePipeline.cancelAllPrefetchLoads()
        imagePipeline.cancelVisibleCellImageLoads()
        // An in-place reload recreates every cell; anchor-nearest regions keep
        // their current pixels and crossfade to the reloaded content.
        let isOnScreen = isActive && viewIfLoaded?.window != nil
        let carryoverSources = isOnScreen
            ? captureVisibleCarryoverSources(
                anchorTokenIndex: focusedTokenIndex
            )
            : []
        if isOnScreen {
            gridModeCoordinator.beginCommitFadeWindow()
        }
        collectionView.reloadData()
        if let cachedGeometry {
            installCollectionLayout(cachedGeometry.layout)
        } else {
            configureCollectionLayout()
        }
        collectionView.layoutIfNeeded()
        if !carryoverSources.isEmpty {
            installGridModeCarryoverContent(
                sources: carryoverSources,
                anchorTokenIndex: focusedTokenIndex
            )
        }
    }

    private func updateLayoutAspectProfile(
        snapshot: PlayerCollectionBrowseSnapshot?,
        focusedTokenIndex: Int?,
        columnCount: Int
    ) {
        let defaultSize = CGSize(width: 1, height: 1)
        guard let snapshot,
              snapshot.itemCount > 0 else {
            layoutAspectState = MobilePlayerCollectionBrowserLayoutAspectState(
                aspectProfile: MobilePlayerBrowserAspectProfile(
                    itemCount: 0,
                    uniformImageSize: defaultSize,
                    columnCount: columnCount
                ),
                fallbackSpec: PlayerMediaPlaceholderSpec(
                    aspectSize: defaultSize
                )
            )
            return
        }

        let aspectRatioProfile = MobilePlaybackController.shared
            .collectionBrowseThumbnailAspectRatioProfile(snapshot: snapshot)
        let aspectState = makeLayoutAspectState(
            snapshot: snapshot,
            columnCount: columnCount,
            focusedTokenIndex: focusedTokenIndex,
            aspectRatioProfile: aspectRatioProfile
        )
        layoutAspectState = aspectState
    }

    private func makeLayoutAspectState(
        snapshot: PlayerCollectionBrowseSnapshot,
        columnCount: Int,
        focusedTokenIndex: Int?,
        aspectRatioProfile: ThumbnailAspectRatioProfile?
    ) -> MobilePlayerCollectionBrowserLayoutAspectState {
        let defaultSize = CGSize(width: 1, height: 1)
        let sampleState = makeLayoutAspectSamples(
            snapshot: snapshot,
            focusedTokenIndex: focusedTokenIndex
        )

        let aspectProfile: MobilePlayerBrowserAspectProfile
        if let aspectRatioProfile {
            aspectProfile = makeLayoutAspectProfile(
                snapshot: snapshot,
                columnCount: columnCount,
                aspectRatioProfile: aspectRatioProfile
            )
        } else {
            let layoutFallbackSize = sampleState.samples
                .map(\.size)
                .max {
                    $0.height / $0.width < $1.height / $1.width
                }
                ?? defaultSize
            aspectProfile = MobilePlayerBrowserAspectProfile(
                itemCount: snapshot.itemCount,
                uniformImageSize: layoutFallbackSize,
                columnCount: columnCount
            )
        }

        return MobilePlayerCollectionBrowserLayoutAspectState(
            aspectProfile: aspectProfile,
            fallbackSpec: makeLayoutFallbackSpec(
                focus: sampleState.focus,
                samples: sampleState.samples
            )
        )
    }

    private func makeLayoutAspectSamples(
        snapshot: PlayerCollectionBrowseSnapshot,
        focusedTokenIndex: Int?
    ) -> (focus: Int, samples: [LayoutAspectSample]) {
        guard snapshot.itemCount > 0 else { return (0, []) }
        let sampleCount = min(
            snapshot.itemCount,
            MobilePlayerBrowserLayout.maximumAspectSampleCount
        )
        let focus = min(max(focusedTokenIndex ?? snapshot.initialTokenIndex, 0), snapshot.itemCount - 1)
        let firstIndex = min(
            max(focus - sampleCount / 2, 0),
            snapshot.itemCount - sampleCount
        )
        let sampleRange = firstIndex..<(firstIndex + sampleCount)
        let samples = sampleRange.compactMap { tokenIndex -> LayoutAspectSample? in
            guard let descriptor = MobilePlaybackController.shared.collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            ) else {
                return nil
            }
            let size = PlayerCollectionBrowserSupport.fallbackImageSize(for: descriptor)
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }
            return LayoutAspectSample(
                index: tokenIndex,
                size: size,
                usesNativeMetalCardCornerMask:
                    descriptor.usesNativeMetalCardPresentation
            )
        }
        return (focus, samples)
    }

    private func makeLayoutFallbackSpec(
        snapshot: PlayerCollectionBrowseSnapshot,
        focusedTokenIndex: Int?
    ) -> PlayerMediaPlaceholderSpec {
        let sampleState = makeLayoutAspectSamples(
            snapshot: snapshot,
            focusedTokenIndex: focusedTokenIndex
        )
        return makeLayoutFallbackSpec(
            focus: sampleState.focus,
            samples: sampleState.samples
        )
    }

    private func makeLayoutFallbackSpec(
        focus: Int,
        samples: [LayoutAspectSample]
    ) -> PlayerMediaPlaceholderSpec {
        let nearestSample = samples.min { lhs, rhs in
            let lhsDistance = abs(lhs.index - focus)
            let rhsDistance = abs(rhs.index - focus)
            return lhsDistance == rhsDistance
                ? lhs.index < rhs.index
                : lhsDistance < rhsDistance
        }
        return PlayerMediaPlaceholderSpec(
            aspectSize: nearestSample?.size ?? CGSize(width: 1, height: 1),
            usesNativeMetalCardCornerMask:
                nearestSample?.usesNativeMetalCardCornerMask ?? false
        )
    }

    private func makeLayoutAspectProfile(
        snapshot: PlayerCollectionBrowseSnapshot,
        columnCount: Int,
        aspectRatioProfile: ThumbnailAspectRatioProfile
    ) -> MobilePlayerBrowserAspectProfile {
        switch aspectRatioProfile {
        case let .uniform(aspectRatio):
            return MobilePlayerBrowserAspectProfile(
                itemCount: snapshot.itemCount,
                uniformImageSize: aspectRatio.size,
                columnCount: columnCount
            )
        case let .variable(aspectRatios):
            return MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: aspectRatios.map {
                    CGFloat($0.height) / CGFloat($0.width)
                },
                columnCount: columnCount
            )
        }
    }

    private func reloadBrowseSnapshot(resetPublicationState: Bool) {
        let newSnapshot = MobilePlaybackController.shared.collectionBrowseSnapshot(uuid: uuid)
        let snapshotChanged = newSnapshot != browseSnapshot
        guard snapshotChanged || resetPublicationState else { return }

        if !resetPublicationState,
           snapshotChanged,
           let newSnapshot,
           let currentSnapshot = browseSnapshot,
           CollectionBrowseSnapshotUpdatePolicy.isSettledPositionEcho(
               currentCollectionId: currentSnapshot.collectionId,
               currentItemCount: currentSnapshot.itemCount,
               updatedCollectionId: newSnapshot.collectionId,
               updatedItemCount: newSnapshot.itemCount,
               updatedInitialTokenIndex: newSnapshot.initialTokenIndex,
               lastPublishedTokenIndex:
                   publicationState?.lastPublishedTokenIndex
           ) {
            browseSnapshot = newSnapshot
            return
        }

        let restorationIndex = PlayerCollectionScrollPolicy.restorationIndex(
            savedIndex: newSnapshot?.initialTokenIndex,
            itemCount: newSnapshot?.itemCount ?? 0
        )
        applyBrowseSnapshot(
            newSnapshot,
            sampledAround: restorationIndex,
            gridMode: gridMode
        )

        publicationState = restorationIndex.map {
            PlayerCollectionScrollPublicationState(initialIndex: $0)
        }
        hasFinishedInitialPositioning = false
        focusedTokenIndex = restorationIndex
        retainFocusedTokenIndex(restorationIndex)
        lastEmittedFocusedTokenIndex = nil
        imagePipeline.resetThumbnailWindow()
        cancelPendingFocusPublication(resetLastPublicationTime: true)
    }

    private func performInitialPositioningIfNeeded() {
        guard !hasFinishedInitialPositioning,
              lastLayoutSize != .zero,
              let browseSnapshot,
              let targetTokenIndex = PlayerCollectionScrollPolicy.restorationIndex(
                savedIndex: browseSnapshot.initialTokenIndex,
                itemCount: browseSnapshot.itemCount
              ),
              collectionView.bounds.width > 0,
              collectionView.bounds.height > 0 else {
            return
        }

        isApplyingPosition = true
        centerContent(on: targetTokenIndex)
        retainFocusedTokenIndex(targetTokenIndex)
        focusedTokenIndex = targetTokenIndex
        collectionView.layoutIfNeeded()
        isApplyingPosition = false
        hasFinishedInitialPositioning = true
        publicationState?.finishInitialPositioning()
        publicationState?.observeCandidate(targetTokenIndex)
        publishFocus(tokenIndex: targetTokenIndex, cadence: .immediate)
        publishSettledTokenIfNeeded()
        prepareThumbnailWindow(around: targetTokenIndex, direction: .forward, force: true)
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    private func configureCollectionLayout() {
        guard let browserLayout = makeBrowserLayout(
            aspectProfile: layoutAspectState.aspectProfile
        ) else {
            return
        }

        installCollectionLayout(browserLayout)
    }

    private func makeBrowserLayout(
        aspectProfile: MobilePlayerBrowserAspectProfile
    ) -> MobilePlayerBrowserLayout? {
        let viewportSize = view.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        return MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            displayScale: currentLayoutDisplayScale,
            topContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.top,
            bottomContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.bottom,
            aspectProfile: aspectProfile
        )
    }

    private func installCollectionLayout(
        _ browserLayout: MobilePlayerBrowserLayout
    ) {
        let thumbnailWindowCadenceChanged =
            configuredPrefetchStride != browserLayout.prefetchStride
                || configuredColumnCount != browserLayout.columnCount
        browserCollectionLayout.browserLayout = browserLayout
        if thumbnailWindowCadenceChanged {
            imagePipeline.resetThumbnailWindow()
        }
        collectionView.scrollIndicatorInsets = UIEdgeInsets(
            top: layoutWindowSafeAreaInsets.top,
            left: 0,
            bottom: layoutWindowSafeAreaInsets.bottom,
            right: 0
        )
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    private func captureLayoutWindowSafeAreaInsets(_ safeAreaInsets: UIEdgeInsets) {
        layoutWindowSafeAreaInsets = UIEdgeInsets(
            top: safeAreaInsets.top.isFinite ? max(safeAreaInsets.top, 0) : 0,
            left: 0,
            bottom: safeAreaInsets.bottom.isFinite ? max(safeAreaInsets.bottom, 0) : 0,
            right: 0
        )
        hasCapturedLayoutWindowSafeAreaInsets = true
    }

    private func resolveWindowSafeAreaLayoutUpdate(
        state: WindowSafeAreaState?,
        sizeChanged: Bool
    ) -> WindowSafeAreaLayoutUpdate {
        guard let state else {
            return WindowSafeAreaLayoutUpdate(
                insetsToCapture: nil,
                clearsPendingRefresh: false,
                requiresLayoutRefresh: false
            )
        }

        let needsInitialCapture = !hasCapturedLayoutWindowSafeAreaInsets
        let isScrollInteractionActive = isScrollMotionActive
        let canEvaluatePendingRefresh =
            needsWindowSafeAreaRefresh
            && !isScrollInteractionActive
        let shouldCaptureInsets =
            sizeChanged || needsInitialCapture || canEvaluatePendingRefresh
        let resolvedInsets = shouldCaptureInsets
            ? UIEdgeInsets(
                top: sizeChanged || needsInitialCapture
                    ? state.insets.top
                    : layoutWindowSafeAreaInsets.top,
                left: 0,
                bottom: state.insets.bottom,
                right: 0
            )
            : nil
        let insetsChanged =
            resolvedInsets.map { $0 != layoutWindowSafeAreaInsets } == true

        return WindowSafeAreaLayoutUpdate(
            insetsToCapture: resolvedInsets,
            clearsPendingRefresh: shouldCaptureInsets,
            requiresLayoutRefresh:
                needsInitialCapture
                    || (!sizeChanged && insetsChanged)
        )
    }

    private var currentWindowSafeAreaState: WindowSafeAreaState? {
        guard let window = collectionView.window else { return nil }

        let safeAreaInsets = collectionView.safeAreaInsets

        let displayScale = window.screen.scale
        func pixelAligned(_ value: CGFloat) -> CGFloat {
            let sanitizedValue = value.isFinite ? max(value, 0) : 0
            guard displayScale.isFinite, displayScale > 0 else {
                return sanitizedValue
            }
            return (sanitizedValue * displayScale).rounded() / displayScale
        }

        return WindowSafeAreaState(
            insets: UIEdgeInsets(
                top: pixelAligned(safeAreaInsets.top),
                left: 0,
                bottom: pixelAligned(safeAreaInsets.bottom),
                right: 0
            )
        )
    }

    private var currentLayoutDisplayScale: CGFloat {
        let traitScale = traitCollection.displayScale
        if traitScale.isFinite, traitScale > 0 {
            return traitScale
        }
        let windowScale = view.window?.screen.scale ?? 0
        return windowScale.isFinite && windowScale > 0 ? windowScale : 3
    }

    private func restoreContentPositionAfterSafeAreaChange(
        previousContentOffset: CGPoint,
        previousTopContentInset: CGFloat,
        previousVerticalContentOffsetRange: ClosedRange<CGFloat>,
        retainedFocusTokenIndex: Int?
    ) {
        let restoredContentOffset = contentOffsetAfterSafeAreaChange(
            previousContentOffset: previousContentOffset,
            previousTopContentInset: previousTopContentInset,
            previousVerticalContentOffsetRange:
                previousVerticalContentOffsetRange
        )
        let appliedOffsetDeltaY =
            restoredContentOffset.y - previousContentOffset.y
        collectionView.setContentOffset(restoredContentOffset, animated: false)
        scrollCoordinator.adjustDragStartContentOffset(
            by: appliedOffsetDeltaY
        )

        retainFocusedTokenIndex(retainedFocusTokenIndex)
        if let retainedFocusTokenIndex {
            focusedTokenIndex = retainedFocusTokenIndex
        }
    }

    private func contentOffsetAfterSafeAreaChange(
        previousContentOffset: CGPoint,
        previousTopContentInset: CGFloat,
        previousVerticalContentOffsetRange: ClosedRange<CGFloat>
    ) -> CGPoint {
        let restoredContentOffsetY =
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: previousContentOffset.y,
                previousRange: previousVerticalContentOffsetRange,
                updatedRange: verticalContentOffsetRange,
                topContentInsetDelta:
                    layoutWindowSafeAreaInsets.top
                        - previousTopContentInset,
                boundaryEpsilon: Self.boundaryEpsilon
            )
        return clampedContentOffset(
            CGPoint(
                x: previousContentOffset.x,
                y: restoredContentOffsetY
            )
        )
    }

    private func centerContent(on tokenIndex: Int) {
        guard let browseSnapshot,
              (0..<browseSnapshot.itemCount).contains(tokenIndex) else {
            return
        }

        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
            collectionView.scrollToItem(
                at: indexPath,
                at: .centeredVertically,
                animated: false
            )
            return
        }

        let proposedOffsetY: CGFloat
        if let focalGeometry {
            proposedOffsetY = focalGeometry.contentOffsetY(
                anchoringFocalY: attributes.frame.midY
            )
        } else {
            proposedOffsetY = attributes.frame.midY - collectionView.bounds.height / 2
        }
        collectionView.setContentOffset(
            clampedContentOffset(CGPoint(x: 0, y: proposedOffsetY)),
            animated: false
        )
    }

    private var canonicalContentOffsetX: CGFloat {
        -collectionView.adjustedContentInset.left
    }

    private func clampedContentOffset(_ contentOffset: CGPoint) -> CGPoint {
        return CGPoint(
            x: canonicalContentOffsetX,
            y: clampedVerticalContentOffsetY(contentOffset.y)
        )
    }

    private func clampedVerticalContentOffsetY(_ contentOffsetY: CGFloat) -> CGFloat {
        let verticalRange = verticalContentOffsetRange
        return min(max(contentOffsetY, verticalRange.lowerBound), verticalRange.upperBound)
    }

    private var verticalContentOffsetRange: ClosedRange<CGFloat> {
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        return minimumOffsetY...maximumOffsetY
    }

    private var hasViewedToEnd: Bool {
        guard let browseSnapshot,
              browseSnapshot.itemCount > 0,
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: browseSnapshot.itemCount - 1, section: 0)
              ) else {
            return false
        }
        return PlayerCollectionScrollPolicy.hasViewedToEnd(
            finalItemFrame: attributes.frame,
            viewport: collectionView.bounds,
            maximumContentOffsetY: verticalContentOffsetRange.upperBound,
            epsilon: Self.boundaryEpsilon
        )
    }

    private func isTokenFullyVisible(_ tokenIndex: Int) -> Bool {
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
            return false
        }
        return PlayerCollectionScrollPolicy.isItemFullyVisible(
            frame: attributes.frame,
            viewport: collectionView.bounds,
            epsilon: Self.boundaryEpsilon
        )
    }

    private func releaseRetainedFocusForOutwardPullIfNeeded(_ scrollView: UIScrollView) {
        guard forcedFocusedTokenIndex != nil else { return }
        let verticalRange = verticalContentOffsetRange
        guard verticalRange.upperBound - verticalRange.lowerBound > Self.boundaryEpsilon else {
            return
        }
        let contentOffsetY = scrollView.contentOffset.y
        let isOutwardPull = contentOffsetY < verticalRange.lowerBound - Self.boundaryEpsilon
            || contentOffsetY > verticalRange.upperBound + Self.boundaryEpsilon
        guard isOutwardPull else { return }
        retainFocusedTokenIndex(nil)
    }

    private func acknowledgeIntentionalScrollIfNeeded(_ scrollView: UIScrollView) {
        let currentContentOffsetY = clampedVerticalContentOffsetY(scrollView.contentOffset.y)
        guard scrollCoordinator.acknowledgeIntentionalScrollIfNeeded(
            clampedContentOffsetY: currentContentOffsetY,
            epsilon: Self.boundaryEpsilon
        ) else { return }
        MobilePlaybackController.shared.acknowledgeIntentionalViewingPosition(uuid: uuid)
    }

    private func endScrollMotionAndResetDragState() {
        endScrollMotion()
        scrollCoordinator.resetDragState()
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
    }

    private func beginScrollMotion() {
        guard scrollCoordinator.beginScrollMotion() else { return }
        imagePipeline.setScrollMotionActive(true)
        cancelGridModeGeometryPrewarming()
        demoteVisibleBrowserImageLoadsIfNeeded()
    }

    private func endScrollMotion() {
        scrollCoordinator.endScrollMotion()
        imagePipeline.setScrollMotionActive(false)
        imagePipeline.cancelDenseGridImageRefreshes()
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
    }

    private func cancelScrollMotionAnimationTimeout() {
        scrollCoordinator.cancelScrollMotionAnimationTimeout()
    }

    private func scheduleScrollMotionAnimationTimeout() {
        scrollCoordinator.scheduleScrollMotionAnimationTimeout()
    }

    private func handleScrollMotionAnimationTimeout() {
        endScrollMotion()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    private func settleAfterApplyingPendingWindowSafeAreaRefresh() {
        guard !isApplyingPosition else { return }
        if needsWindowSafeAreaRefresh,
           let currentAnchorTokenIndex = currentAnchorTokenIndex() {
            focusedTokenIndex = currentAnchorTokenIndex
        }
        let previousSettlementGeneration = scrollCoordinator.settlementGeneration
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
        view.layoutIfNeeded()
        if scrollCoordinator.settlementGeneration == previousSettlementGeneration {
            settleCurrentPosition()
        }
    }

    private func currentAnchorTokenIndex() -> Int? {
        guard let browseSnapshot,
              let browserLayout = browserCollectionLayout.browserLayout else {
            return nil
        }

        let visibleItems = collectionView.indexPathsForVisibleItems.compactMap {
            indexPath -> PlayerCollectionVisibleItem? in
            guard let frame = browserLayout.itemFrame(at: indexPath.item) else {
                return nil
            }
            return PlayerCollectionVisibleItem(
                index: indexPath.item,
                frame: frame
            )
        }
        let candidateIndex = PlayerCollectionScrollPolicy.anchorIndex(
            visibleItems: visibleItems,
            focalPoint: currentFocalPoint(),
            itemCount: browseSnapshot.itemCount
        )
        let resolvedIndex = PlayerCollectionScrollPolicy.resolvedAnchorIndex(
            retainedIndex: forcedFocusedTokenIndex,
            candidateIndex: candidateIndex,
            itemCount: browseSnapshot.itemCount,
            configuredColumnCount: configuredColumnCount
        )
        if forcedFocusedTokenIndex != nil,
           resolvedIndex != forcedFocusedTokenIndex {
            forcedFocusedTokenIndex = nil
        }
        return resolvedIndex
    }

    private func retainFocusedTokenIndex(_ tokenIndex: Int?) {
        forcedFocusedTokenIndex = tokenIndex
        retainedFocusFocalBias = tokenIndex.flatMap { makeFocalBias(for: $0) }
    }

    private func currentFocalPoint() -> CGPoint {
        let viewport = collectionView.bounds
        guard let focalGeometry else {
            return CGPoint(x: viewport.midX, y: viewport.midY)
        }

        let standardFocalPoint = focalGeometry.focalPoint(at: collectionView.contentOffset.y)
        guard let retainedFocusFocalBias else {
            return standardFocalPoint
        }

        let adjustedFocalPoint = retainedFocusFocalBias.adjustedFocalPoint(
            from: standardFocalPoint,
            minimumFocalY: focalGeometry.firstItemCenter.y,
            maximumFocalY: focalGeometry.lastItemCenter.y
        )
        if retainedFocusFocalBias.isExpired(
            at: standardFocalPoint.y,
            minimumFocalY: focalGeometry.firstItemCenter.y,
            maximumFocalY: focalGeometry.lastItemCenter.y
        ) {
            self.retainedFocusFocalBias = nil
        }
        return adjustedFocalPoint
    }

    private var focalGeometry: PlayerCollectionScrollFocalGeometry? {
        guard let browseSnapshot,
              browseSnapshot.itemCount > 0,
              configuredColumnCount > 0,
              collectionView.bounds.width > 0,
              collectionView.bounds.height > 0,
              let browserLayout = browserCollectionLayout.browserLayout,
              let firstItemFrame = browserLayout.itemFrame(at: 0),
              let lastItemFrame = browserLayout.itemFrame(
                at: browseSnapshot.itemCount - 1
              ) else {
            return nil
        }

        let lastRowFirstIndex = ((browseSnapshot.itemCount - 1) / configuredColumnCount)
            * configuredColumnCount
        let lastRowFocalEntryY: CGFloat
        if lastRowFirstIndex > 0,
           let previousRowFrame = browserLayout.itemFrame(
                at: lastRowFirstIndex - configuredColumnCount
           ) {
            lastRowFocalEntryY = (
                previousRowFrame.midY + lastItemFrame.midY
            ) / 2
        } else {
            lastRowFocalEntryY = firstItemFrame.midY
        }

        let verticalRange = verticalContentOffsetRange
        return PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: verticalRange.lowerBound,
            maximumOffsetY: verticalRange.upperBound,
            viewportHeight: collectionView.bounds.height,
            viewportCenterX: collectionView.bounds.midX,
            firstItemCenter: CGPoint(
                x: firstItemFrame.midX,
                y: firstItemFrame.midY
            ),
            lastItemCenter: CGPoint(
                x: lastItemFrame.midX,
                y: lastItemFrame.midY
            ),
            lastRowFocalEntryY: lastRowFocalEntryY
        )
    }

    private func makeFocalBias(for tokenIndex: Int) -> PlayerCollectionScrollFocalBias? {
        guard let focalGeometry,
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: tokenIndex, section: 0)
              ) else {
            return nil
        }

        let contentOffsetY = clampedVerticalContentOffsetY(collectionView.contentOffset.y)
        let standardFocalPoint = focalGeometry.focalPoint(at: contentOffsetY)
        let targetCenterY = attributes.frame.midY
        let rowTravel = max(
            browserCollectionLayout.browserLayout?
                .minimumAdjacentRowCenterDistance(
                    containingItemAt: tokenIndex
                ) ?? attributes.frame.height + (
                    browserCollectionLayout.browserLayout?.interItemSpacing
                        ?? MobilePlayerBrowserLayout.itemSpacing
                ),
            1
        )
        return PlayerCollectionScrollFocalBias(
            referenceFocalY: standardFocalPoint.y,
            deltaY: targetCenterY - standardFocalPoint.y,
            decayDistance: max(
                abs(targetCenterY - standardFocalPoint.y),
                rowTravel
            )
        )
    }

    private func observeCurrentAnchor(
        focusCadence:
            MobilePlayerCollectionBrowserScrollCoordinator
                .FocusPublicationCadence,
        preparesThumbnailWindow: Bool,
        forcesThumbnailWindow: Bool
    ) {
        guard let tokenIndex = currentAnchorTokenIndex() else { return }
        scrollCoordinator.observe(
            tokenIndex: tokenIndex,
            focusCadence: focusCadence
        )
        if preparesThumbnailWindow {
            prepareThumbnailWindow(
                around: tokenIndex,
                direction: lastPrefetchDirection,
                force: forcesThumbnailWindow
            )
        }
    }

    private func settleCurrentPosition() {
        guard isActive else { return }
        scrollCoordinator.beginSettlement()
        resumeVisibleBrowserImageLoadsIfNeeded()
        observeCurrentAnchor(
            focusCadence: .immediate,
            preparesThumbnailWindow: true,
            forcesThumbnailWindow: true
        )
        publishSettledTokenIfNeeded()
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    private func performSelection(at tokenIndex: Int) {
        guard !hasGridModeInteractionState,
              canSelectBrowserCell(at: tokenIndex) else {
            return
        }
        endScrollMotionAndResetDragState()
        guard let selection = transitionSelection(tokenIndex: tokenIndex) else {
            settleCurrentPosition()
            return
        }
        guard onSelection?(selection) == true else {
            settleCurrentPosition()
            return
        }
        settleSelection(at: tokenIndex)
    }

    private func settleSelection(at tokenIndex: Int) {
        guard isActive,
              browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return
        }

        scrollCoordinator.cancelScheduledScrollUpdate()
        retainFocusedTokenIndex(tokenIndex)
        MobilePlaybackController.shared.acknowledgeIntentionalViewingPosition(uuid: uuid)
        scrollCoordinator.observe(
            tokenIndex: tokenIndex,
            focusCadence: .immediate
        )
        publishSettledTokenIfNeeded()
    }

    private func scheduleScrollUpdate() {
        scrollCoordinator.scheduleScrollUpdate()
    }

    private func cancelScheduledScrollUpdate() {
        scrollCoordinator.cancelScheduledScrollUpdate()
    }

    private func publishFocus(
        tokenIndex: Int,
        cadence:
            MobilePlayerCollectionBrowserScrollCoordinator
                .FocusPublicationCadence
    ) {
        scrollCoordinator.publishFocus(tokenIndex: tokenIndex, cadence: cadence)
    }

    private func cancelPendingFocusPublication(resetLastPublicationTime: Bool) {
        scrollCoordinator.cancelPendingFocusPublication(
            resetLastPublicationTime: resetLastPublicationTime
        )
    }

    private func publishSettledTokenIfNeeded() {
        scrollCoordinator.settle(hasViewedToEnd: hasViewedToEnd)
    }

    private func publishSettledPagePosition(
        _ publication: PlayerCollectionScrollPublication
    ) -> Bool {
        guard let pagePosition = browseSnapshot?.pagePosition(
            forTokenIndex: publication.tokenIndex
        ) else {
            return false
        }
        return onSettledPagePosition?(
            pagePosition,
            publication.hasViewedToEnd
        ) == true
    }

    private func prepareThumbnailWindow(
        around tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        force: Bool
    ) {
        imagePipeline.prepareThumbnailWindow(
            around: tokenIndex,
            direction: direction,
            force: force,
            configuredPrefetchStride: configuredPrefetchStride,
            configuredColumnCount: configuredColumnCount,
            requiredImageQuality: requiredImageQuality
        )
    }

    private func projectedBrowserTokenRange(
        around tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        refreshDistance: Int
    ) -> ClosedRange<Int>? {
        guard let browseSnapshot,
              browseSnapshot.itemCount > 0,
              let browserLayout = browserCollectionLayout.browserLayout else {
            return nil
        }
        let lastTokenIndex = browseSnapshot.itemCount - 1
        let targetTokenIndex: Int
        switch direction {
        case .forward:
            let target = tokenIndex.addingReportingOverflow(refreshDistance)
            targetTokenIndex = target.overflow
                ? lastTokenIndex
                : min(target.partialValue, lastTokenIndex)
        case .backward:
            let target = tokenIndex.subtractingReportingOverflow(refreshDistance)
            targetTokenIndex = target.overflow
                ? 0
                : max(target.partialValue, 0)
        }
        guard let targetFrame = browserLayout.itemFrame(at: targetTokenIndex) else {
            return nil
        }
        let projectedContentOffsetY = clampedVerticalContentOffsetY(
            focalGeometry?.contentOffsetY(anchoringFocalY: targetFrame.midY)
                ?? targetFrame.midY - collectionView.bounds.height / 2
        )
        let projectedViewport = CGRect(
            x: collectionView.bounds.minX,
            y: projectedContentOffsetY,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        let candidates = browserLayout.candidateItemIndices(
            intersecting: projectedViewport
        )
        guard let first = candidates.first,
              let last = candidates.last else {
            return nil
        }
        return first...last
    }

    private func transitionSelection(tokenIndex: Int) -> MobilePlayerBrowserTransitionSelection? {
        guard let selectedSnapshot = itemSnapshot(tokenIndex: tokenIndex) else { return nil }
        let neighbors = collectionView.indexPathsForVisibleItems
            .map(\.item)
            .filter { $0 != tokenIndex }
            .sorted()
            .compactMap(itemSnapshot(tokenIndex:))
        return MobilePlayerBrowserTransitionSelection(
            selectedSnapshot: selectedSnapshot,
            visibleNeighborSnapshots: neighbors
        )
    }

    private func itemSnapshot(tokenIndex: Int) -> MobilePlayerBrowserItemSnapshot? {
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        guard let cell = collectionView.cellForItem(at: indexPath) as? MobilePlayerCollectionBrowserCell,
              let identity = browserContentIdentity(
                  forTokenIndex: tokenIndex
              ),
              cell.canSelect(representing: identity),
              let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) else {
            return nil
        }
        let hasLoadedImage = cell.prepareForTransitionSnapshot(tokenIndex: tokenIndex)
        guard let snapshot = cell.transitionSnapshot(
            afterScreenUpdates: hasLoadedImage
        ) else {
            return nil
        }

        return MobilePlayerBrowserItemSnapshot(
            tokenIndex: tokenIndex,
            pagePosition: pagePosition,
            descriptor: cell.descriptor,
            fallbackImageSize: cell.displayedImageSize,
            hasLoadedImage: hasLoadedImage,
            frameInWindow: snapshot.frameInWindow,
            snapshotView: snapshot.view
        )
    }

    private func browseImageSources(
        forTokenIndex tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        browseSnapshot.flatMap {
            MobilePlaybackController.shared.collectionBrowseImageSources(
                snapshot: $0,
                tokenIndex: tokenIndex
            )
        }
    }

    private func browserContentIdentity(
        forTokenIndex tokenIndex: Int
    ) -> MobilePlayerBrowserContentIdentity? {
        guard let browseSnapshot,
              browseSnapshot.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return nil
        }
        return MobilePlayerBrowserContentIdentity(
            collectionId: browseSnapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    private func configureBrowserCell(
        _ cell: MobilePlayerCollectionBrowserCell,
        at indexPath: IndexPath,
        requiredImageQuality: CollectionBrowseImageQuality? = nil,
        imageLoadPolicy: MobilePlayerCollectionBrowserCell.ImageLoadPolicy? = nil,
        allowsLocalLargeImageUpgrade: Bool? = nil
    ) {
        guard let contentIdentity = browserContentIdentity(
            forTokenIndex: indexPath.item
        ) else {
            cell.prepareForGridModePhantomReuse()
            return
        }
        let imageSources = browseImageSources(forTokenIndex: indexPath.item)
        imagePipeline.configure(
            cell: cell,
            tokenIndex: indexPath.item,
            requiredImageQuality: requiredImageQuality,
            imageLoadPolicy: imageLoadPolicy,
            apply: { resolvedRequiredImageQuality, resolvedImageLoadPolicy in
                cell.configure(
                    contentIdentity: contentIdentity,
                    itemCount: browseSnapshot?.itemCount ?? 0,
                    imageSources: imageSources,
                    requiredImageQuality: resolvedRequiredImageQuality,
                    missingDescriptorFallbackSpec: layoutAspectState.fallbackSpec,
                    imageLoadPolicy: resolvedImageLoadPolicy,
                    fadesFirstImage: gridModeCoordinator.fadesFirstImage,
                    allowsLocalLargeImageUpgrade: allowsLocalLargeImageUpgrade
                        ?? gridMode.allowsLocalLargeImageUpgrade
                )
            }
        )
    }

    private func reloadVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? MobilePlayerCollectionBrowserCell else {
                continue
            }
            configureBrowserCell(cell, at: indexPath)
        }
    }

    private func refreshVisibleCachedImagesIfNeeded(notification: Notification) {
        imagePipeline.handleCacheNotification(notification)
    }

    private var visibleBrowserCells: [MobilePlayerCollectionBrowserCell] {
        collectionView.visibleCells.compactMap { $0 as? MobilePlayerCollectionBrowserCell }
    }

    private func demoteVisibleBrowserImageLoadsIfNeeded() {
        imagePipeline.demoteVisibleImageLoadsIfNeeded()
    }

    private func resumeVisibleBrowserImageLoadsIfNeeded() {
        imagePipeline.resumeVisibleImageLoadsIfNeeded()
    }

#if DEBUG
    var pendingDenseGridImageRefreshCount: Int {
        imagePipeline.pendingDenseGridImageRefreshCount
    }

    var isDenseGridImageDisplayLinkActive: Bool {
        imagePipeline.isDenseGridImageDisplayLinkActive
    }

    var isScrollMotionAnimationTimeoutScheduled: Bool {
        scrollCoordinator.isScrollMotionAnimationTimeoutScheduled
    }

    var isScrollMotionActiveForTesting: Bool {
        isScrollMotionActive
    }

    var hasPendingGridModeGeometryPrewarmForTesting: Bool {
        gridModeGeometryPrewarmPlan != nil
    }

    func drainDenseGridImageDisplayLinkFrameForTesting() -> Int {
        imagePipeline.drainDenseGridImageDisplayLinkFrameForTesting()
    }

    func replacePendingDenseGridImageRefreshesForTesting(
        tokenIndices: [Int]
    ) {
        imagePipeline.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: tokenIndices
        )
    }

    func expireScrollMotionAnimationForTesting() {
        guard isScrollMotionActive else { return }
        endScrollMotion()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func resetGridModeGeometryPrewarmingForTesting() {
        cancelGridModeGeometryPrewarming()
        gridModeGeometryCache = nil
    }
#endif

}
