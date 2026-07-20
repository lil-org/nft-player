// ∅ 2026 lil org

import QuartzCore
import UIKit

final class MobilePlayerCollectionBrowserCollectionView: UICollectionView {}

enum MobilePlayerCollectionBrowserDisplayPreparationResult: Equatable {
    case prepared
    case superseded
    case unavailable
}

final class VerticalCollectionBrowserViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {

    private struct PreparedTransition {
        let preparation: PlayerCollectionBrowsePreparation
        let contentOffset: CGPoint
        let layoutSize: CGSize
        let layoutWindowSafeAreaInsets: UIEdgeInsets
        let verticalContentOffsetRange: ClosedRange<CGFloat>
        let browseSnapshot: PlayerCollectionBrowseSnapshot?
        let publicationState: PlayerCollectionScrollPublicationState?
        let hasFinishedInitialPositioning: Bool
        let focusedTokenIndex: Int?
        let forcedFocusedTokenIndex: Int?
        let retainedFocusFocalBias: PlayerCollectionScrollFocalBias?
        let lastEmittedFocusedTokenIndex: Int?
        let lastThumbnailWindowRequest: ThumbnailWindowRequest?
        let lastPrefetchDirection: DownloadableMediaCache.PrefetchDirection
        let lastScrollOffsetY: CGFloat?
        let layoutAspectProfile: MobilePlayerBrowserAspectProfile
        let sampledCollectionFallbackSpec: PlayerMediaPlaceholderSpec
    }

    private struct PrefetchLoad {
        let id: UUID
        let cancel: () -> Void
    }

    private struct ThumbnailWindowRequest: Equatable {
        let tokenIndex: Int
        let direction: DownloadableMediaCache.PrefetchDirection
        let prefetchStride: Int
    }

    private struct WindowSafeAreaState {
        let insets: UIEdgeInsets
        let isStatusBarHidden: Bool
    }

    private struct WindowSafeAreaLayoutUpdate {
        let insetsToCapture: UIEdgeInsets?
        let clearsPendingRefresh: Bool
        let requiresLayoutRefresh: Bool
    }

    private enum FocusPublicationCadence {
        case immediate
        case continuous
    }

    private static let cellReuseIdentifier = "MobilePlayerCollectionBrowserCell"
    private static let boundaryEpsilon: CGFloat = 0.75
    private static let focusedModeDragThreshold: CGFloat = 8
    private static let verticalContentMargin: CGFloat = 0
    private static let maximumPrefetchLoadCount = 96
    private static let continuousFocusPublicationInterval: CFTimeInterval = 1 / 12
    private static let scrollToTopAnimationTimeout: TimeInterval = 2

    let uuid: UUID

    var onFocusedPagePosition: ((PlayerPagePosition) -> Void)?
    var onSettledPagePosition: ((PlayerPagePosition, Bool) -> Bool)?
    var onSelection: ((MobilePlayerBrowserTransitionSelection) -> Bool)?
    var onFocusedModeChange: ((Bool) -> Bool)?

    private let browserCollectionLayout = MobilePlayerCollectionBrowserLayout()
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
        return collectionView
    }()

    private var browseSnapshot: PlayerCollectionBrowseSnapshot?
    private var publicationState: PlayerCollectionScrollPublicationState?
    private var hasFinishedInitialPositioning = false
    private var isActive = false
    private var isApplyingPosition = false
    private var positioningGeneration: UInt = 0
    private var lastLayoutSize = CGSize.zero
    private var focusedTokenIndex: Int?
    private var forcedFocusedTokenIndex: Int?
    private var retainedFocusFocalBias: PlayerCollectionScrollFocalBias?
    private var lastEmittedFocusedTokenIndex: Int?
    private var pendingFocusedTokenIndex: Int?
    private var focusPublicationGeneration: UInt = 0
    private var isFocusPublicationScheduled = false
    private var lastFocusPublicationTime: CFTimeInterval?
    private var lastScrollOffsetY: CGFloat?
    private var dragStartContentOffsetY: CGFloat?
    private var hasAcknowledgedCurrentDrag = false
    private var isFocusedModeActive = false
    private var focusedModeDragDisplacement: CGFloat = 0
    private var needsWindowSafeAreaRefresh = false
    private var isScrollToTopAnimationActive = false
    private var scrollToTopAnimationTimeoutGeneration: UInt = 0
    private var lastThumbnailWindowRequest: ThumbnailWindowRequest?
    private var lastPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    private var scrollUpdateGeneration: UInt = 0
    private var isScrollUpdateScheduled = false
    private var positionSettlementGeneration: UInt = 0
    private var preparedTransition: PreparedTransition?
    private var layoutAspectProfile = MobilePlayerBrowserAspectProfile(
        itemCount: 0,
        uniformImageSize: CGSize(width: 1, height: 1)
    )
    private var sampledCollectionFallbackSpec = PlayerMediaPlaceholderSpec(
        aspectSize: CGSize(width: 1, height: 1)
    )
    private var layoutWindowSafeAreaInsets = UIEdgeInsets.zero
    private var hasCapturedLayoutWindowSafeAreaInsets = false
    private var prefetchLoads = [Int: PrefetchLoad]()
    private var backgroundObserver: NSObjectProtocol?
    private var cacheFileAvailabilityObserver: NSObjectProtocol?

    private var configuredColumnCount: Int {
        browserCollectionLayout.browserLayout?.columnCount ?? 0
    }

    private var configuredPrefetchStride: Int {
        browserCollectionLayout.browserLayout?.prefetchStride
            ?? MobilePlayerBrowserLayout.defaultColumnCount
    }

    init(uuid: UUID) {
        self.uuid = uuid
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let cacheFileAvailabilityObserver {
            NotificationCenter.default.removeObserver(cacheFileAvailabilityObserver)
        }
        cancelAllPrefetchLoads()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        reloadBrowseSnapshot(resetPublicationState: true)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cancelScrollToTopAnimationState()
            self?.finishCurrentDrag()
            self?.flushSettledPosition()
        }
        cacheFileAvailabilityObserver = NotificationCenter.default.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVisibleCachedImagesIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = collectionView.bounds.size
        let sizeChanged = lastLayoutSize != .zero && lastLayoutSize != viewportSize
        let windowSafeAreaLayoutUpdate = resolveWindowSafeAreaLayoutUpdate(
            state: currentWindowSafeAreaState,
            sizeChanged: sizeChanged
        )
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
            needsSafeAreaRefresh:
                windowSafeAreaLayoutUpdate.requiresLayoutRefresh,
            topContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.top,
            bottomContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.bottom,
            aspectProfile: layoutAspectProfile,
            forcedTokenIndex: forcedFocusedTokenIndex,
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
            if sizeChanged,
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
        lastLayoutSize = collectionView.bounds.size

        guard isActive else { return }
        let hadFinishedInitialPositioning = hasFinishedInitialPositioning
        performInitialPositioningIfNeeded()
        if hadFinishedInitialPositioning,
           transition.geometryChanged,
           !isApplyingPosition {
            settleCurrentPosition()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        needsWindowSafeAreaRefresh = true
        view.setNeedsLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelScrollToTopAnimationState()
        finishCurrentDrag()
        flushSettledPosition()
    }

    var currentPagePosition: PlayerPagePosition? {
        guard let browseSnapshot,
              let tokenIndex = forcedFocusedTokenIndex ?? focusedTokenIndex else {
            return nil
        }
        return browseSnapshot.pagePosition(forTokenIndex: tokenIndex)
    }

    func setActive(_ active: Bool) {
        guard isActive != active else {
            if active {
                performInitialPositioningIfNeeded()
            }
            return
        }

        if active,
           let preparation = preparedTransition?.preparation,
           !finalizePreparedDisplay(preparation) {
            return
        }

        if !active {
            setFocusedModeActive(false)
            cancelScrollToTopAnimationState()
            flushSettledPosition()
            finishCurrentDrag()
            cancelScheduledScrollUpdate()
            cancelPendingFocusPublication(resetLastPublicationTime: true)
            cancelAllPrefetchLoads()
            lastThumbnailWindowRequest = nil
            visibleBrowserCells.forEach { $0.cancelImageLoad() }
        }

        isActive = active
        collectionView.isScrollEnabled = active
        collectionView.isUserInteractionEnabled = active
        collectionView.scrollsToTop = active
        if active {
            reloadBrowseSnapshot(resetPublicationState: browseSnapshot == nil)
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
        }
    }

    func setFocusedModeActiveForDisplayTransition(_ isActive: Bool) {
        setFocusedModeActive(isActive)
    }

    func prepareForDisplay(
        using preparation: PlayerCollectionBrowsePreparation,
        forcePosition: Bool = false,
        publishWhenStable: Bool,
        completion: @escaping (MobilePlayerCollectionBrowserDisplayPreparationResult) -> Void
    ) {
        loadViewIfNeeded()
        positioningGeneration &+= 1
        let generation = positioningGeneration
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        guard isValid(preparation) else {
            isApplyingPosition = false
            cancelPreparedTransition()
            completion(.unavailable)
            return
        }

        if let preparedTransition,
           preparedTransition.preparation != preparation {
            restorePreparedTransition(preparedTransition)
        }
        if preparedTransition == nil {
            preparedTransition = makePreparedTransition(for: preparation)
        }

        let snapshotChanged = browseSnapshot != preparation.snapshot
        isApplyingPosition = true
        if snapshotChanged {
            applyBrowseSnapshot(
                preparation.snapshot,
                sampledAround: preparation.focusedTokenIndex
            )
        }

        if hasFinishedInitialPositioning, !snapshotChanged {
            if publicationState == nil {
                publicationState = PlayerCollectionScrollPublicationState(
                    initialIndex: preparation.focusedTokenIndex
                )
                publicationState?.finishInitialPositioning()
            }
            publicationState?.beginProgrammaticPositioning(at: preparation.focusedTokenIndex)
        } else {
            publicationState = PlayerCollectionScrollPublicationState(
                initialIndex: preparation.focusedTokenIndex
            )
            hasFinishedInitialPositioning = false
        }

        if forcePosition
            || snapshotChanged
            || !isTokenFullyVisible(preparation.focusedTokenIndex) {
            centerContent(on: preparation.focusedTokenIndex)
        }
        retainFocusedTokenIndex(preparation.focusedTokenIndex)
        focusedTokenIndex = preparation.focusedTokenIndex
        collectionView.layoutIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(.superseded)
                return
            }
            guard self.positioningGeneration == generation else {
                completion(.superseded)
                return
            }

            self.collectionView.layoutIfNeeded()
            if !self.hasFinishedInitialPositioning {
                self.hasFinishedInitialPositioning = true
                self.publicationState?.finishInitialPositioning()
            } else {
                self.publicationState?.finishProgrammaticPositioning()
            }
            self.isApplyingPosition = false
            self.publicationState?.observeCandidate(preparation.focusedTokenIndex)
            self.publishFocus(
                tokenIndex: preparation.focusedTokenIndex,
                cadence: .immediate
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
            completion(.prepared)
        }
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
        positioningGeneration &+= 1
        isApplyingPosition = false
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        cancelPreparedTransition()
    }

    func canSelectItem(at location: CGPoint, in coordinateView: UIView) -> Bool {
        guard isActive else { return false }
        let point = collectionView.convert(location, from: coordinateView)
        return collectionView.indexPathForItem(at: point) != nil
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
        guard isValid(preparation) else { return nil }

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
        let snapshotChanged = browseSnapshot != preparation.snapshot
        if snapshotChanged {
            applyBrowseSnapshot(
                preparation.snapshot,
                sampledAround: preparation.focusedTokenIndex
            )
        }
        publicationState = PlayerCollectionScrollPublicationState(
            initialIndex: preparation.focusedTokenIndex
        )
        hasFinishedInitialPositioning = false
        lastEmittedFocusedTokenIndex = nil
        lastThumbnailWindowRequest = nil
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
            layoutWindowSafeAreaInsets: layoutWindowSafeAreaInsets,
            verticalContentOffsetRange: verticalContentOffsetRange,
            browseSnapshot: browseSnapshot,
            publicationState: publicationState,
            hasFinishedInitialPositioning: hasFinishedInitialPositioning,
            focusedTokenIndex: focusedTokenIndex,
            forcedFocusedTokenIndex: forcedFocusedTokenIndex,
            retainedFocusFocalBias: retainedFocusFocalBias,
            lastEmittedFocusedTokenIndex: lastEmittedFocusedTokenIndex,
            lastThumbnailWindowRequest: lastThumbnailWindowRequest,
            lastPrefetchDirection: lastPrefetchDirection,
            lastScrollOffsetY: lastScrollOffsetY,
            layoutAspectProfile: layoutAspectProfile,
            sampledCollectionFallbackSpec: sampledCollectionFallbackSpec
        )
    }

    private func restorePreparedTransition(_ preparedTransition: PreparedTransition) {
        self.preparedTransition = nil
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        isApplyingPosition = true

        browseSnapshot = preparedTransition.browseSnapshot
        publicationState = preparedTransition.publicationState
        hasFinishedInitialPositioning = preparedTransition.hasFinishedInitialPositioning
        layoutAspectProfile = preparedTransition.layoutAspectProfile
        sampledCollectionFallbackSpec = preparedTransition.sampledCollectionFallbackSpec
        cancelAllPrefetchLoads()
        visibleBrowserCells.forEach { $0.cancelImageLoad() }
        collectionView.reloadData()
        configureCollectionLayout()
        collectionView.layoutIfNeeded()

        let layoutSizeUnchanged =
            preparedTransition.layoutSize == collectionView.bounds.size
        let canRestoreExactGeometry =
            layoutSizeUnchanged
            && preparedTransition.layoutWindowSafeAreaInsets
                == layoutWindowSafeAreaInsets
            && preparedTransition.verticalContentOffsetRange
                == verticalContentOffsetRange
        if layoutSizeUnchanged {
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
        } else if let focusedTokenIndex = preparedTransition.forcedFocusedTokenIndex
            ?? preparedTransition.focusedTokenIndex {
            centerContent(on: focusedTokenIndex)
        } else {
            collectionView.setContentOffset(clampedContentOffset(preparedTransition.contentOffset), animated: false)
        }
        collectionView.layoutIfNeeded()

        focusedTokenIndex = preparedTransition.focusedTokenIndex
        if let forcedFocusedTokenIndex = preparedTransition.forcedFocusedTokenIndex {
            self.forcedFocusedTokenIndex = forcedFocusedTokenIndex
            if canRestoreExactGeometry {
                retainedFocusFocalBias = preparedTransition.retainedFocusFocalBias
                    ?? makeFocalBias(for: forcedFocusedTokenIndex)
            } else {
                retainedFocusFocalBias = makeFocalBias(for: forcedFocusedTokenIndex)
            }
        } else {
            forcedFocusedTokenIndex = nil
            retainedFocusFocalBias = canRestoreExactGeometry
                ? preparedTransition.retainedFocusFocalBias
                : nil
        }
        lastEmittedFocusedTokenIndex = preparedTransition.lastEmittedFocusedTokenIndex
        lastThumbnailWindowRequest = preparedTransition.lastThumbnailWindowRequest
        lastPrefetchDirection = preparedTransition.lastPrefetchDirection
        lastScrollOffsetY = canRestoreExactGeometry
            ? preparedTransition.lastScrollOffsetY
            : collectionView.contentOffset.y
        isApplyingPosition = false
    }

    func scrollToFirstItemAndPublish() {
        guard let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: 0),
              let preparation = MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: uuid,
                containing: pagePosition
              ) else {
            return
        }

        cancelScrollToTopAnimationState()
        finishCurrentDrag()
        setFocusedModeActive(false)
        prepareForDisplay(
            using: preparation,
            forcePosition: true,
            publishWhenStable: true
        ) { _ in }
    }

    func flushSettledPosition() {
        guard isActive else { return }
        cancelScheduledScrollUpdate()
        observeCurrentAnchor(
            focusCadence: .immediate,
            preparesThumbnailWindow: false,
            forcesThumbnailWindow: false
        )
        guard let publication = publicationState?.finalFlush(
            hasViewedToEnd: hasViewedToEnd
        ) else {
            return
        }
        guard publishSettledPagePosition(publication) else {
            publicationState?.retryPublication(of: publication)
            return
        }
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
        return browserCell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard isActive || preparedTransition != nil else { return }
        (cell as? MobilePlayerCollectionBrowserCell)?.resumeImageLoadIfNeeded(
            tokenIndex: indexPath.item
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? MobilePlayerCollectionBrowserCell)?.cancelImageLoad(
            ifRepresenting: indexPath.item
        )
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let selection = transitionSelection(tokenIndex: indexPath.item),
              onSelection?(selection) == true else {
            return
        }
        settleSelection(at: indexPath.item)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        guard isActive,
              prefetchLoads.count < Self.maximumPrefetchLoadCount else {
            return
        }

        let center = focusedTokenIndex ?? currentAnchorTokenIndex() ?? 0
        let orderedIndices = Set(indexPaths.map(\.item)).sorted {
            let lhsDistance = abs($0 - center)
            let rhsDistance = abs($1 - center)
            return lhsDistance == rhsDistance ? $0 < $1 : lhsDistance < rhsDistance
        }

        for tokenIndex in orderedIndices {
            guard prefetchLoads.count < Self.maximumPrefetchLoadCount,
                  prefetchLoads[tokenIndex] == nil,
                  let browseSnapshot,
                  let descriptor = MobilePlaybackController.shared.collectionBrowseThumbnailDescriptor(
                    snapshot: browseSnapshot,
                    tokenIndex: tokenIndex
                  ),
                  DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) == nil else {
                continue
            }

            let loadID = UUID()
            if let cancellation = DownloadableMediaCache.shared.loadProvisionalImage(
                for: descriptor,
                completion: { [weak self] _ in
                    DispatchQueue.main.async {
                        guard self?.prefetchLoads[tokenIndex]?.id == loadID else { return }
                        self?.prefetchLoads.removeValue(forKey: tokenIndex)
                    }
                }
            ) {
                prefetchLoads[tokenIndex] = PrefetchLoad(id: loadID, cancel: cancellation)
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for tokenIndex in Set(indexPaths.map(\.item)) {
            prefetchLoads.removeValue(forKey: tokenIndex)?.cancel()
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelScrollToTopAnimationState()
        lastScrollOffsetY = scrollView.contentOffset.y
        dragStartContentOffsetY = clampedVerticalContentOffsetY(scrollView.contentOffset.y)
        hasAcknowledgedCurrentDrag = false
        resetFocusedModeDragIntent()
        let verticalRange = verticalContentOffsetRange
        if verticalRange.upperBound - verticalRange.lowerBound <= Self.boundaryEpsilon {
            hasAcknowledgedCurrentDrag = true
            MobilePlaybackController.shared.acknowledgeIntentionalViewingPosition(uuid: uuid)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let previousOffsetY = lastScrollOffsetY
        lastScrollOffsetY = scrollView.contentOffset.y
        guard isActive,
              hasFinishedInitialPositioning,
              !isApplyingPosition else {
            return
        }
        releaseRetainedFocusForOutwardPullIfNeeded(scrollView)
        acknowledgeIntentionalScrollIfNeeded(scrollView)
        if let previousOffsetY {
            // Rubber-band recovery moves contentOffset in the same direction
            // that hides chrome. Only count movement through scrollable content.
            let offsetDelta = PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
                previousOffsetY: previousOffsetY,
                currentOffsetY: scrollView.contentOffset.y,
                validRange: verticalContentOffsetRange
            )
            if scrollView.isDragging {
                updateFocusedMode(for: offsetDelta)
            }
            if abs(offsetDelta) > Self.boundaryEpsilon {
                lastPrefetchDirection = offsetDelta > 0 ? .forward : .backward
            }
        }
        scheduleScrollUpdate()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        finishCurrentDrag()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishCurrentDrag()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        cancelScrollToTopAnimationState()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        guard isActive else { return false }
        finishCurrentDrag()
        cancelScrollToTopAnimationState()
        isScrollToTopAnimationActive =
            scrollView.contentOffset.y
                > verticalContentOffsetRange.lowerBound + Self.boundaryEpsilon
        if isScrollToTopAnimationActive {
            scheduleScrollToTopAnimationTimeout()
        }
        retainFocusedTokenIndex(nil)
        cancelScheduledScrollUpdate()
        lastScrollOffsetY = scrollView.contentOffset.y
        setFocusedModeActive(false)
        return true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        cancelScrollToTopAnimationState()
        setFocusedModeActive(false)
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    private func applyBrowseSnapshot(
        _ snapshot: PlayerCollectionBrowseSnapshot?,
        sampledAround focusedTokenIndex: Int?
    ) {
        browseSnapshot = snapshot
        updateLayoutAspectProfile(
            snapshot: snapshot,
            focusedTokenIndex: focusedTokenIndex
        )
        cancelAllPrefetchLoads()
        visibleBrowserCells.forEach { $0.cancelImageLoad() }
        collectionView.reloadData()
        configureCollectionLayout()
        collectionView.layoutIfNeeded()
    }

    private func updateLayoutAspectProfile(
        snapshot: PlayerCollectionBrowseSnapshot?,
        focusedTokenIndex: Int?
    ) {
        let defaultSize = CGSize(width: 1, height: 1)
        guard let snapshot,
              snapshot.itemCount > 0 else {
            layoutAspectProfile = MobilePlayerBrowserAspectProfile(
                itemCount: 0,
                uniformImageSize: defaultSize
            )
            sampledCollectionFallbackSpec = PlayerMediaPlaceholderSpec(
                aspectSize: defaultSize
            )
            return
        }

        let columnCount =
            MobilePlaybackController.shared.collectionBrowseColumnCount(
                snapshot: snapshot
            )
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
        let makeSample = {
            tokenIndex -> (index: Int, size: CGSize, usesNativeMetalCardCornerMask: Bool)? in
            guard let descriptor = MobilePlaybackController.shared.collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            ) else {
                return nil
            }
            let size = MobilePlayerCollectionBrowserSupport.fallbackImageSize(for: descriptor)
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }
            return (tokenIndex, size, descriptor.usesNativeMetalCardPresentation)
        }

        let nearestSample:
            (index: Int, size: CGSize, usesNativeMetalCardCornerMask: Bool)?
        if let aspectRatioProfile =
            MobilePlaybackController.shared.collectionBrowseThumbnailAspectRatioProfile(
                snapshot: snapshot
            ) {
            switch aspectRatioProfile {
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
            nearestSample = sampleRange
                .sorted {
                    let lhsDistance = abs($0 - focus)
                    let rhsDistance = abs($1 - focus)
                    return lhsDistance == rhsDistance
                        ? $0 < $1
                        : lhsDistance < rhsDistance
                }
                .lazy
                .compactMap(makeSample)
                .first
        } else {
            let samples = sampleRange.compactMap(makeSample)
            let layoutFallbackSize = samples
                .map { $0.size }
                .max {
                    $0.height / $0.width < $1.height / $1.width
                }
                ?? defaultSize
            layoutAspectProfile = MobilePlayerBrowserAspectProfile(
                itemCount: snapshot.itemCount,
                uniformImageSize: layoutFallbackSize,
                columnCount: columnCount
            )
            nearestSample = samples.min { lhs, rhs in
                let lhsDistance = abs(lhs.index - focus)
                let rhsDistance = abs(rhs.index - focus)
                return lhsDistance == rhsDistance
                    ? lhs.index < rhs.index
                    : lhsDistance < rhsDistance
            }
        }

        sampledCollectionFallbackSpec = PlayerMediaPlaceholderSpec(
            aspectSize: nearestSample?.size ?? defaultSize,
            usesNativeMetalCardCornerMask:
                nearestSample?.usesNativeMetalCardCornerMask ?? false
        )
    }

    private func reloadBrowseSnapshot(resetPublicationState: Bool) {
        let newSnapshot = MobilePlaybackController.shared.collectionBrowseSnapshot(uuid: uuid)
        let changed = newSnapshot != browseSnapshot
        guard changed || resetPublicationState else { return }

        let restorationIndex = PlayerCollectionScrollPolicy.restorationIndex(
            savedIndex: newSnapshot?.initialTokenIndex,
            itemCount: newSnapshot?.itemCount ?? 0
        )
        applyBrowseSnapshot(newSnapshot, sampledAround: restorationIndex)

        publicationState = restorationIndex.map {
            PlayerCollectionScrollPublicationState(initialIndex: $0)
        }
        hasFinishedInitialPositioning = false
        focusedTokenIndex = restorationIndex
        retainFocusedTokenIndex(restorationIndex)
        lastEmittedFocusedTokenIndex = nil
        lastThumbnailWindowRequest = nil
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
    }

    private func configureCollectionLayout() {
        let viewportSize = collectionView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let topInset = Self.verticalContentMargin + layoutWindowSafeAreaInsets.top
        let bottomInset = Self.verticalContentMargin + layoutWindowSafeAreaInsets.bottom
        guard let browserLayout = MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            topContentInset: topInset,
            bottomContentInset: bottomInset,
            aspectProfile: layoutAspectProfile
        ) else {
            return
        }

        installCollectionLayout(browserLayout)
    }

    private func installCollectionLayout(
        _ browserLayout: MobilePlayerBrowserLayout
    ) {
        let prefetchStrideChanged =
            configuredPrefetchStride != browserLayout.prefetchStride
        browserCollectionLayout.browserLayout = browserLayout
        if prefetchStrideChanged {
            lastThumbnailWindowRequest = nil
        }
        collectionView.scrollIndicatorInsets = UIEdgeInsets(
            top: layoutWindowSafeAreaInsets.top,
            left: 0,
            bottom: layoutWindowSafeAreaInsets.bottom,
            right: 0
        )
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
        let isScrollInteractionActive =
            dragStartContentOffsetY != nil || isScrollToTopAnimationActive
        let canEvaluatePendingRefresh =
            needsWindowSafeAreaRefresh
            && !isScrollInteractionActive
        let hasStableVisibleStatusBar =
            !isFocusedModeActive && !state.isStatusBarHidden

        let refreshInsets: UIEdgeInsets?
        if !canEvaluatePendingRefresh {
            refreshInsets = nil
        } else if hasStableVisibleStatusBar {
            refreshInsets = state.insets
        } else {
            // Status-bar visibility is the only top-edge change intentionally
            // frozen for smooth focused scrolling. Keep other edges current.
            refreshInsets = UIEdgeInsets(
                top: layoutWindowSafeAreaInsets.top,
                left: 0,
                bottom: state.insets.bottom,
                right: 0
            )
        }
        let changedRefreshInsets = refreshInsets.flatMap {
            $0 == layoutWindowSafeAreaInsets ? nil : $0
        }

        return WindowSafeAreaLayoutUpdate(
            insetsToCapture:
                sizeChanged || needsInitialCapture
                    ? state.insets
                    : changedRefreshInsets,
            clearsPendingRefresh:
                hasStableVisibleStatusBar
                    && (sizeChanged
                        || needsInitialCapture
                        || canEvaluatePendingRefresh),
            requiresLayoutRefresh:
                needsInitialCapture
                    || (!sizeChanged && changedRefreshInsets != nil)
        )
    }

    private var currentWindowSafeAreaState: WindowSafeAreaState? {
        guard let window = collectionView.window else { return nil }

        let statusBarManager = window.windowScene?.statusBarManager
        let isStatusBarHidden = statusBarManager?.isStatusBarHidden == true
        // The window only accounts for physical screen obstructions. The
        // collection view's safe area also includes bars imposed by its
        // containing view-controller hierarchy, such as the translucent
        // navigation bar.
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
            ),
            isStatusBarHidden: isStatusBarHidden
        )
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
        if let dragStartContentOffsetY {
            self.dragStartContentOffsetY =
                dragStartContentOffsetY + appliedOffsetDeltaY
        }

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

    private func clampedContentOffset(_ contentOffset: CGPoint) -> CGPoint {
        return CGPoint(
            x: -collectionView.adjustedContentInset.left,
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
        // Keep a transition target stable until the user deliberately pulls past the edge.
        retainFocusedTokenIndex(nil)
    }

    private func acknowledgeIntentionalScrollIfNeeded(_ scrollView: UIScrollView) {
        guard !hasAcknowledgedCurrentDrag,
              let dragStartContentOffsetY else {
            return
        }
        let currentContentOffsetY = clampedVerticalContentOffsetY(scrollView.contentOffset.y)
        guard abs(currentContentOffsetY - dragStartContentOffsetY) > Self.boundaryEpsilon else {
            return
        }

        hasAcknowledgedCurrentDrag = true
        MobilePlaybackController.shared.acknowledgeIntentionalViewingPosition(uuid: uuid)
    }

    private func finishCurrentDrag() {
        dragStartContentOffsetY = nil
        hasAcknowledgedCurrentDrag = false
        resetFocusedModeDragIntent()
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
    }

    private func cancelScrollToTopAnimationState() {
        scrollToTopAnimationTimeoutGeneration &+= 1
        guard isScrollToTopAnimationActive else { return }
        isScrollToTopAnimationActive = false
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
    }

    private func scheduleScrollToTopAnimationTimeout() {
        scrollToTopAnimationTimeoutGeneration &+= 1
        let generation = scrollToTopAnimationTimeoutGeneration
        // UIKit has no cancellation callback for an interrupted status-bar scroll.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.scrollToTopAnimationTimeout
        ) { [weak self] in
            guard let self,
                  self.isScrollToTopAnimationActive,
                  self.scrollToTopAnimationTimeoutGeneration == generation else {
                return
            }
            self.cancelScrollToTopAnimationState()
            self.settleAfterApplyingPendingWindowSafeAreaRefresh()
        }
    }

    private func settleAfterApplyingPendingWindowSafeAreaRefresh() {
        if needsWindowSafeAreaRefresh,
           let currentAnchorTokenIndex = currentAnchorTokenIndex() {
            focusedTokenIndex = currentAnchorTokenIndex
        }
        let previousSettlementGeneration = positionSettlementGeneration
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
        view.layoutIfNeeded()
        if positionSettlementGeneration == previousSettlementGeneration {
            settleCurrentPosition()
        }
    }

    private func updateFocusedMode(for offsetDelta: CGFloat) {
        focusedModeDragDisplacement += offsetDelta
        guard abs(focusedModeDragDisplacement) >= Self.focusedModeDragThreshold else {
            return
        }

        setFocusedModeActive(focusedModeDragDisplacement > 0)
    }

    private func setFocusedModeActive(_ isActive: Bool) {
        resetFocusedModeDragIntent()
        guard isFocusedModeActive != isActive else { return }
        guard onFocusedModeChange?(isActive) ?? true else { return }

        isFocusedModeActive = isActive
        if !isActive {
            needsWindowSafeAreaRefresh = true
            view.setNeedsLayout()
        }
    }

    private func resetFocusedModeDragIntent() {
        focusedModeDragDisplacement = 0
    }

    private func currentAnchorTokenIndex() -> Int? {
        guard let browseSnapshot else { return nil }

        let visibleItems = collectionView.indexPathsForVisibleItems.compactMap { indexPath -> PlayerCollectionVisibleItem? in
            guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
                return nil
            }
            return PlayerCollectionVisibleItem(index: indexPath.item, frame: attributes.frame)
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
              let firstAttributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
              ),
              let lastAttributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: browseSnapshot.itemCount - 1, section: 0)
              ) else {
            return nil
        }

        let lastRowFirstIndex = ((browseSnapshot.itemCount - 1) / configuredColumnCount)
            * configuredColumnCount
        let lastRowFocalEntryY: CGFloat
        if lastRowFirstIndex > 0,
           let previousRowAttributes =
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(
                    item: lastRowFirstIndex - configuredColumnCount,
                    section: 0
                )
            ) {
            lastRowFocalEntryY = (
                previousRowAttributes.frame.midY + lastAttributes.frame.midY
            ) / 2
        } else {
            lastRowFocalEntryY = firstAttributes.frame.midY
        }

        let verticalRange = verticalContentOffsetRange
        return PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: verticalRange.lowerBound,
            maximumOffsetY: verticalRange.upperBound,
            viewportHeight: collectionView.bounds.height,
            viewportCenterX: collectionView.bounds.midX,
            firstItemCenter: CGPoint(
                x: firstAttributes.frame.midX,
                y: firstAttributes.frame.midY
            ),
            lastItemCenter: CGPoint(
                x: lastAttributes.frame.midX,
                y: lastAttributes.frame.midY
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
                ) ?? attributes.frame.height + MobilePlayerBrowserLayout.itemSpacing,
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
        focusCadence: FocusPublicationCadence,
        preparesThumbnailWindow: Bool,
        forcesThumbnailWindow: Bool
    ) {
        guard let tokenIndex = currentAnchorTokenIndex() else { return }
        publicationState?.observeCandidate(tokenIndex)
        publishFocus(tokenIndex: tokenIndex, cadence: focusCadence)
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
        positionSettlementGeneration &+= 1
        cancelScheduledScrollUpdate()
        observeCurrentAnchor(
            focusCadence: .immediate,
            preparesThumbnailWindow: true,
            forcesThumbnailWindow: true
        )
        publishSettledTokenIfNeeded()
    }

    private func settleSelection(at tokenIndex: Int) {
        guard isActive,
              browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return
        }

        cancelScheduledScrollUpdate()
        retainFocusedTokenIndex(tokenIndex)
        focusedTokenIndex = tokenIndex
        publicationState?.observeCandidate(tokenIndex)
        MobilePlaybackController.shared.acknowledgeIntentionalViewingPosition(uuid: uuid)
        publishFocus(tokenIndex: tokenIndex, cadence: .immediate)
        publishSettledTokenIfNeeded()
    }

    private func scheduleScrollUpdate() {
        guard !isScrollUpdateScheduled else { return }
        isScrollUpdateScheduled = true
        scrollUpdateGeneration &+= 1
        let generation = scrollUpdateGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.scrollUpdateGeneration == generation else {
                return
            }
            self.isScrollUpdateScheduled = false
            guard self.isActive,
                  self.hasFinishedInitialPositioning,
                  !self.isApplyingPosition else {
                return
            }
            self.observeCurrentAnchor(
                focusCadence: .continuous,
                preparesThumbnailWindow: true,
                forcesThumbnailWindow: false
            )
        }
    }

    private func cancelScheduledScrollUpdate() {
        scrollUpdateGeneration &+= 1
        isScrollUpdateScheduled = false
    }

    private func publishFocus(
        tokenIndex: Int,
        cadence: FocusPublicationCadence
    ) {
        focusedTokenIndex = tokenIndex
        switch cadence {
        case .immediate:
            cancelPendingFocusPublication(resetLastPublicationTime: false)
            emitFocus(tokenIndex: tokenIndex)

        case .continuous:
            guard isActive else {
                return
            }
            if lastEmittedFocusedTokenIndex == tokenIndex {
                cancelPendingFocusPublication(resetLastPublicationTime: false)
                return
            }
            pendingFocusedTokenIndex = tokenIndex
            let now = CACurrentMediaTime()
            let elapsed = lastFocusPublicationTime.map { now - $0 }
                ?? Self.continuousFocusPublicationInterval
            guard elapsed < Self.continuousFocusPublicationInterval else {
                cancelPendingFocusPublication(resetLastPublicationTime: false)
                emitFocus(tokenIndex: tokenIndex)
                return
            }
            guard !isFocusPublicationScheduled else { return }

            isFocusPublicationScheduled = true
            focusPublicationGeneration &+= 1
            let generation = focusPublicationGeneration
            let delay = Self.continuousFocusPublicationInterval - elapsed
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.focusPublicationGeneration == generation else {
                    return
                }
                self.isFocusPublicationScheduled = false
                guard let tokenIndex = self.pendingFocusedTokenIndex else { return }
                self.pendingFocusedTokenIndex = nil
                self.emitFocus(tokenIndex: tokenIndex)
            }
        }
    }

    private func emitFocus(tokenIndex: Int) {
        guard isActive,
              lastEmittedFocusedTokenIndex != tokenIndex,
              let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) else {
            return
        }
        lastEmittedFocusedTokenIndex = tokenIndex
        lastFocusPublicationTime = CACurrentMediaTime()
        onFocusedPagePosition?(pagePosition)
    }

    private func cancelPendingFocusPublication(resetLastPublicationTime: Bool) {
        focusPublicationGeneration &+= 1
        isFocusPublicationScheduled = false
        pendingFocusedTokenIndex = nil
        if resetLastPublicationTime {
            lastFocusPublicationTime = nil
        }
    }

    private func publishSettledTokenIfNeeded() {
        guard let publication = publicationState?.settle(
            hasViewedToEnd: hasViewedToEnd
        ) else {
            return
        }
        guard publishSettledPagePosition(publication) else {
            publicationState?.retryPublication(of: publication)
            return
        }
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
        guard isActive else { return }
        let request = ThumbnailWindowRequest(
            tokenIndex: tokenIndex,
            direction: direction,
            prefetchStride: configuredPrefetchStride
        )
        if !force, lastThumbnailWindowRequest == request {
            return
        }
        if !force,
           let lastThumbnailWindowRequest,
           lastThumbnailWindowRequest.direction == direction,
           lastThumbnailWindowRequest.prefetchStride == configuredPrefetchStride,
           abs(lastThumbnailWindowRequest.tokenIndex - tokenIndex) < configuredPrefetchStride {
            return
        }
        _ = MobilePlaybackController.shared.prepareCollectionBrowseThumbnailWindow(
            uuid: uuid,
            centeredAt: tokenIndex,
            direction: direction,
            prefetchStride: configuredPrefetchStride
        )
        // Remember empty attempts too. Missing descriptors are a valid browser state,
        // and forced settle/activation requests still retry late availability.
        lastThumbnailWindowRequest = request
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

    private func cancelAllPrefetchLoads() {
        let cancellations = prefetchLoads.values.map(\.cancel)
        prefetchLoads.removeAll()
        cancellations.forEach { $0() }
    }

    private func configureBrowserCell(
        _ cell: MobilePlayerCollectionBrowserCell,
        at indexPath: IndexPath
    ) {
        let descriptor = browseSnapshot.flatMap {
            MobilePlaybackController.shared.collectionBrowseThumbnailDescriptor(
                snapshot: $0,
                tokenIndex: indexPath.item
            )
        }
        cell.configure(
            tokenIndex: indexPath.item,
            itemCount: browseSnapshot?.itemCount ?? 0,
            descriptor: descriptor,
            missingDescriptorFallbackSpec: sampledCollectionFallbackSpec,
            allowsImageLoading: isActive || preparedTransition != nil
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

    private func refreshVisibleCachedImagesIfNeeded() {
        guard isActive || preparedTransition != nil else { return }
        visibleBrowserCells.forEach { $0.refreshAvailableImageIfNeeded() }
    }

    private var visibleBrowserCells: [MobilePlayerCollectionBrowserCell] {
        collectionView.visibleCells.compactMap { $0 as? MobilePlayerCollectionBrowserCell }
    }
}

private final class MobilePlayerCollectionBrowserLayout: UICollectionViewLayout {
    override var developmentLayoutDirection: UIUserInterfaceLayoutDirection {
        .leftToRight
    }

    override var flipsHorizontallyInOppositeLayoutDirection: Bool {
        true
    }

    var browserLayout: MobilePlayerBrowserLayout? {
        didSet {
            invalidateLayout()
        }
    }

    override var collectionViewContentSize: CGSize {
        browserLayout?.contentSize ?? .zero
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        guard let browserLayout else { return [] }
        return browserLayout
            .candidateItemIndices(intersecting: rect)
            .compactMap { itemIndex in
                let indexPath = IndexPath(item: itemIndex, section: 0)
                guard let attributes = layoutAttributesForItem(at: indexPath),
                      attributes.frame.intersects(rect) else {
                    return nil
                }
                return attributes
            }
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0,
              let frame = browserLayout?.itemFrame(at: indexPath.item) else {
            return nil
        }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        collectionView?.bounds.size != newBounds.size
    }
}

private final class MobilePlayerCollectionBrowserCell: UICollectionViewCell {

    struct TransitionSnapshot {
        let frameInWindow: CGRect
        let view: UIView
    }

    private let placeholderView = PlayerMediaPlaceholderView()
    private let imageView = NativeMetalCardCornerMaskedImageView()
    private(set) var descriptor: DownloadableMediaDescriptor?
    private(set) var displayedImageSize = CGSize(width: 1, height: 1)
    private var representedTokenIndex: Int?
    private var imageLoadID: UUID?
    private var imageLoadCancellation: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        contentView.backgroundColor = .clear
        contentView.isOpaque = false
        contentView.clipsToBounds = false

        placeholderView.frame = contentView.bounds
        placeholderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(placeholderView)

        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.backgroundColor = .clear
        imageView.isOpaque = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        imageView.isUserInteractionEnabled = false
        contentView.addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelImageLoad()
        representedTokenIndex = nil
        descriptor = nil
        displayedImageSize = CGSize(width: 1, height: 1)
        imageView.image = nil
        imageView.usesNativeMetalCardCornerMask = false
        placeholderView.configure(with: PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil))
        placeholderView.setHidden(false, animated: false)
    }

    func configure(
        tokenIndex: Int,
        itemCount: Int,
        descriptor: DownloadableMediaDescriptor?,
        missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec,
        allowsImageLoading: Bool
    ) {
        cancelImageLoad()
        representedTokenIndex = tokenIndex
        self.descriptor = descriptor
        imageView.image = nil
        let usesNativeMetalCardCornerMask = descriptor?.usesNativeMetalCardPresentation
            ?? missingDescriptorFallbackSpec.usesNativeMetalCardCornerMask
        imageView.usesNativeMetalCardCornerMask = usesNativeMetalCardCornerMask

        if let descriptor {
            displayedImageSize = MobilePlayerCollectionBrowserSupport.fallbackImageSize(
                for: descriptor
            )
        } else {
            displayedImageSize = missingDescriptorFallbackSpec.aspectSize
        }
        placeholderView.configure(
            with: PlayerMediaPlaceholderSpec(
                aspectSize: displayedImageSize,
                usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask
            )
        )
        placeholderView.setHidden(false, animated: false)
        accessibilityLabel = Strings.pagePosition(
            current: tokenIndex + 1,
            total: max(itemCount, tokenIndex + 1)
        )

        if allowsImageLoading {
            startImageLoadIfNeeded(animatedWhenLoaded: true)
        }
    }

    func resumeImageLoadIfNeeded(tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex else { return }
        startImageLoadIfNeeded(animatedWhenLoaded: true)
    }

    func prepareForTransitionSnapshot(tokenIndex: Int) -> Bool {
        guard representedTokenIndex == tokenIndex else { return false }
        startImageLoadIfNeeded(animatedWhenLoaded: false)
        guard imageView.image != nil else { return false }
        placeholderView.setHidden(true, animated: false)
        return true
    }

    func cancelImageLoad(ifRepresenting tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex else { return }
        cancelImageLoad()
    }

    func cancelImageLoad() {
        imageLoadID = nil
        let cancellation = imageLoadCancellation
        imageLoadCancellation = nil
        cancellation?()
    }

    private func startImageLoadIfNeeded(animatedWhenLoaded: Bool) {
        guard imageView.image == nil,
              let tokenIndex = representedTokenIndex,
              let descriptor else {
            return
        }
        if let cachedImage = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            cancelImageLoad()
            setImage(
                cachedImage,
                descriptor: descriptor,
                tokenIndex: tokenIndex,
                animated: false
            )
            return
        }
        guard imageLoadID == nil else { return }

        let loadID = UUID()
        imageLoadID = loadID
        let cancellation = DownloadableMediaCache.shared.loadImage(for: descriptor) { [weak self] image in
            DispatchQueue.main.async {
                guard let self,
                      self.imageLoadID == loadID else {
                    return
                }
                self.imageLoadID = nil
                self.imageLoadCancellation = nil
                guard
                      self.representedTokenIndex == tokenIndex,
                      self.descriptor == descriptor,
                      let image else {
                    return
                }
                self.setImage(
                    image,
                    descriptor: descriptor,
                    tokenIndex: tokenIndex,
                    animated: animatedWhenLoaded
                )
            }
        }
        if imageLoadID == loadID {
            imageLoadCancellation = cancellation
        }
    }

    func transitionSnapshot(afterScreenUpdates: Bool) -> TransitionSnapshot? {
        layoutIfNeeded()
        let mediaFrame = MobilePlayerAspectFitLayout.centeredRect(
            for: displayedImageSize,
            in: contentView.bounds
        )
        let clippedMediaFrame = mediaFrame.intersection(contentView.bounds)
        guard !clippedMediaFrame.isNull,
              !clippedMediaFrame.isEmpty else {
            return nil
        }

        let snapshotFrame = CGRect(origin: .zero, size: clippedMediaFrame.size)
        let snapshotView: UIView
        if let croppedSnapshot = contentView.resizableSnapshotView(
            from: clippedMediaFrame,
            afterScreenUpdates: afterScreenUpdates,
            withCapInsets: .zero
        ) {
            croppedSnapshot.frame = snapshotFrame
            snapshotView = croppedSnapshot
        } else {
            snapshotView = makeTransitionMediaFallback(frame: snapshotFrame)
        }
        snapshotView.clipsToBounds = true
        return TransitionSnapshot(
            frameInWindow: contentView.convert(clippedMediaFrame, to: nil),
            view: snapshotView
        )
    }

    private func makeTransitionMediaFallback(frame: CGRect) -> UIView {
        if let image = imageView.image {
            let fallbackImageView = NativeMetalCardCornerMaskedImageView(frame: frame)
            fallbackImageView.backgroundColor = .clear
            fallbackImageView.isOpaque = false
            fallbackImageView.contentMode = .scaleAspectFit
            fallbackImageView.image = image
            fallbackImageView.usesNativeMetalCardCornerMask = imageView.usesNativeMetalCardCornerMask
            fallbackImageView.layoutIfNeeded()
            return fallbackImageView
        }

        let fallbackPlaceholder = PlayerMediaPlaceholderView(frame: frame)
        fallbackPlaceholder.configure(
            with: PlayerMediaPlaceholderSpec(
                aspectSize: displayedImageSize,
                usesNativeMetalCardCornerMask: imageView.usesNativeMetalCardCornerMask
            )
        )
        fallbackPlaceholder.layoutIfNeeded()
        return fallbackPlaceholder
    }

    func refreshAvailableImageIfNeeded() {
        guard imageView.image == nil,
              let tokenIndex = representedTokenIndex,
              let descriptor,
              descriptor.isStaticImage else {
            return
        }

        let cache = DownloadableMediaCache.shared
        if let image = cache.cachedDecodedImage(for: descriptor) {
            cancelImageLoad()
            setImage(
                image,
                descriptor: descriptor,
                tokenIndex: tokenIndex,
                animated: true
            )
            return
        }

        guard imageLoadID == nil,
              cache.localFileURL(for: descriptor) != nil else {
            return
        }
        startImageLoadIfNeeded(animatedWhenLoaded: true)
    }

    private func setImage(
        _ image: UIImage,
        descriptor: DownloadableMediaDescriptor,
        tokenIndex: Int,
        animated: Bool
    ) {
        guard representedTokenIndex == tokenIndex,
              self.descriptor == descriptor else {
            return
        }
        displayedImageSize = image.size
        imageView.image = image
        placeholderView.setHidden(true, animated: animated)
        prewarmNativeMetalCardFaceIfNeeded(for: descriptor)
    }

    private func prewarmNativeMetalCardFaceIfNeeded(for descriptor: DownloadableMediaDescriptor) {
        guard let renderKind = descriptor.nativeMetalCardRenderKind,
              let tokenID = Int(descriptor.tokenId) else {
            return
        }
        guard let cachedStaticImageURL = DownloadableMediaCache.shared.localFileURL(for: descriptor) else {
            renderKind.loadFace(for: tokenID) { _ in }
            return
        }

        renderKind.cacheFace(for: tokenID, from: cachedStaticImageURL) { didCacheFace in
            guard !didCacheFace else { return }
            renderKind.loadFace(for: tokenID) { _ in }
        }
    }
}
