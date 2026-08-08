// ∅ 2026 lil org

import QuartzCore
import UIKit

final class MobilePlayerCollectionBrowserCollectionView: UICollectionView {
    func visualGeometry(
        for layout: MobilePlayerBrowserLayout
    ) -> MobilePlayerBrowserVisualLayoutGeometry {
        MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally:
                effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
    }
}

enum MobilePlayerCollectionBrowserDisplayPreparationResult: Equatable {
    case prepared
    case superseded
    case unavailable
}

struct GridModePinchFrame: Equatable {
    let sample: PlayerBrowserGridInteractionCoordinator.PinchSample
    let viewLocation: CGPoint

    init(
        scale: CGFloat,
        viewLocation: CGPoint,
        timestamp: TimeInterval
    ) {
        self.sample = PlayerBrowserGridInteractionCoordinator.PinchSample(
            scale: scale,
            centroidY: viewLocation.y,
            timestamp: timestamp
        )
        self.viewLocation = viewLocation
    }
}

final class GridModePinchFrameCoalescer {
    private var pendingFrame: GridModePinchFrame?
    private let apply: (GridModePinchFrame) -> Void
    private lazy var update = PendingMainQueueUpdate { [weak self] in
        self?.applyPendingFrame()
    }

    init(apply: @escaping (GridModePinchFrame) -> Void) {
        self.apply = apply
    }

    func seed(_ frame: GridModePinchFrame) {
        pendingFrame = frame
    }

    func stage(_ frame: GridModePinchFrame) {
        pendingFrame = frame
        update.schedule()
    }

    func flush() {
        update.invalidate()
        applyPendingFrame()
    }

    func invalidate() {
        update.invalidate()
        pendingFrame = nil
    }

    private func applyPendingFrame() {
        guard let pendingFrame else { return }
        self.pendingFrame = nil
        apply(pendingFrame)
    }
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
        let layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    }

    private struct CancellableLoad {
        let id: UUID
        let cancellation: () -> Void
    }

    private struct ThumbnailWindowRequest: Equatable {
        let tokenIndex: Int
        let direction: DownloadableMediaCache.PrefetchDirection
        let prefetchStride: Int
        let quality: CollectionBrowseImageQuality
        let displayedLargeTokenIndices: Set<Int>
        let locallyAvailableLargeTokenIndices: Set<Int>
    }

    private struct DisplayedLargeImageWindowState {
        let tokenIndices: Set<Int>
        let locallyAvailableTokenIndices: Set<Int>

        static let empty = Self(
            tokenIndices: [],
            locallyAvailableTokenIndices: []
        )
    }

    private struct WindowSafeAreaState {
        let insets: UIEdgeInsets
    }

    private struct LayoutAspectSample {
        let index: Int
        let size: CGSize
        let usesNativeMetalCardCornerMask: Bool
    }

    private struct CachedGridModeDestination {
        let anchorTokenIndex: Int
        let layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
        let layout: MobilePlayerBrowserLayout
    }

    /// Deliberately excludes `initialTokenIndex`: cached geometries do not
    /// depend on it, and a settled-position echo must not discard them.
    private struct GridModeGeometryCacheIdentity: Equatable {
        let collectionId: String
        let itemCount: Int
        let viewportSize: CGSize
        let topContentInset: CGFloat
        let bottomContentInset: CGFloat
    }

    private struct CachedGridModeGeometry {
        let aspectProfile: MobilePlayerBrowserAspectProfile
        let layout: MobilePlayerBrowserLayout
    }

    private struct GridModeGeometryCache {
        let identity: GridModeGeometryCacheIdentity
        var geometries: [
            MobileCollectionBrowserGridMode: CachedGridModeGeometry
        ]
    }

    private struct GridModeGeometryPrewarmPlan {
        let identity: GridModeGeometryCacheIdentity
        var modes: [MobileCollectionBrowserGridMode]
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
    private static let verticalContentMargin: CGFloat = 0
    private static let maximumPrefetchLoadCount = 96
    private static let continuousFocusPublicationInterval: CFTimeInterval = 1 / 12
    private static let scrollToTopAnimationTimeout: TimeInterval = 2
    private static let gridModeCommitFadeWindow: TimeInterval = 1.5

    let uuid: UUID

    var onFocusedPagePosition: ((PlayerPagePosition) -> Void)?
    var onSettledPagePosition: ((PlayerPagePosition, Bool) -> Bool)?
    var onSelection: ((MobilePlayerBrowserTransitionSelection) -> Bool)?
    var onImmediateSelection: ((PlayerPagePosition, @escaping () -> Void) -> Bool)?

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
    private var isViewVisible = false
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
    private var needsWindowSafeAreaRefresh = false
    private var isScrollToTopAnimationActive = false
    private var scrollToTopAnimationTimeoutGeneration: UInt = 0
    private var lastThumbnailWindowRequest: ThumbnailWindowRequest?
    private var lastPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    private var scrollUpdateGeneration: UInt = 0
    private var isScrollUpdateScheduled = false
    private var positionSettlementGeneration: UInt = 0
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
    private var prefetchLoads = [Int: CancellableLoad]()
    private var sceneDidEnterBackgroundObserver: NSObjectProtocol?
    private var sceneDidActivateObserver: NSObjectProtocol?
    private var cacheFileAvailabilityObserver: NSObjectProtocol?
    private var gridModeInteractionCoordinator =
        PlayerBrowserGridInteractionCoordinator()
    /// Cells that materialize during the post-commit fade window fade their
    /// first image in because an instant install reads as a pop at rest.
    private var gridModeCommitFadeDeadline: TimeInterval = 0
    private var gridModeSettleDisplayLink: CADisplayLink?
    private var gridModeGeometryCache: GridModeGeometryCache?
    private var gridModeGeometryPrewarmPlan: GridModeGeometryPrewarmPlan?
    private var gridModeDestinationCache = [
        MobileCollectionBrowserGridMode: CachedGridModeDestination
    ]()
    private lazy var gridModePinchRecognizer: UIPinchGestureRecognizer = {
        let recognizer = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handleGridModePinch(_:))
        )
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var gridModePinchFrameCoalescer = GridModePinchFrameCoalescer {
        [weak self] frame in
        self?.applyGridModePinchFrame(frame)
    }
    private lazy var gridModeGeometryPrewarmUpdate = PendingMainQueueUpdate {
        [weak self] in
        self?.prewarmNextGridModeGeometry()
    }
    private lazy var gridModeRenderer =
        MobilePlayerCollectionBrowserGridRenderer(
            collectionView: collectionView,
            viewportView: view,
            contentAccess: .init(
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
            )
        )

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

    init(uuid: UUID) {
        self.uuid = uuid
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let sceneDidEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(
                sceneDidEnterBackgroundObserver
            )
        }
        if let sceneDidActivateObserver {
            NotificationCenter.default.removeObserver(sceneDidActivateObserver)
        }
        if let cacheFileAvailabilityObserver {
            NotificationCenter.default.removeObserver(cacheFileAvailabilityObserver)
        }
        gridModeSettleDisplayLink?.invalidate()
        cancelAllPrefetchLoads()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        view.addGestureRecognizer(gridModePinchRecognizer)

        reloadBrowseSnapshot(resetPublicationState: true)
        sceneDidEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let windowScene = notification.object as? UIWindowScene,
                  let currentWindowScene = collectionView.window?.windowScene,
                  windowScene === currentWindowScene else {
                return
            }
            finalizeGridModeInteractionIfNeeded()
            cancelScrollToTopAnimationState()
            finishCurrentDrag()
            flushSettledPosition()
            cancelGridModeGeometryPrewarming()
        }
        sceneDidActivateObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let windowScene = notification.object as? UIWindowScene,
                  let currentWindowScene = collectionView.window?.windowScene,
                  windowScene === currentWindowScene else {
                return
            }
            scheduleGridModeGeometryPrewarmIfPossible()
        }
        cacheFileAvailabilityObserver = NotificationCenter.default.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.refreshVisibleCachedImagesIfNeeded(notification: notification)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = view.bounds.size
        let sizeChanged = lastLayoutSize != .zero && lastLayoutSize != viewportSize
        let windowSafeAreaLayoutUpdate = resolveWindowSafeAreaLayoutUpdate(
            state: currentWindowSafeAreaState,
            sizeChanged: sizeChanged
        )
        var interruptedGridModeAnchorTokenIndex: Int?
        if hasGridModeInteractionState,
           sizeChanged || windowSafeAreaLayoutUpdate.requiresLayoutRefresh {
            interruptedGridModeAnchorTokenIndex =
                gridModeRenderer.anchorTokenIndex
            finalizeGridModeInteractionIfNeeded()
            guard !hasGridModeInteractionState else {
                view.setNeedsLayout()
                return
            }
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
            needsSafeAreaRefresh:
                windowSafeAreaLayoutUpdate.requiresLayoutRefresh,
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
        lastLayoutSize = viewportSize

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
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
        finalizeGridModeInteractionIfNeeded()
        cancelScrollToTopAnimationState()
        finishCurrentDrag()
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
        let currentGridMode = gridMode
        let actions = MobileCollectionBrowserGridMode.allCases.reversed().map { gridMode in
            UIAction(
                title: gridMode.menuTitle,
                image: UIImage(systemName: gridMode.menuSystemImageName),
                state: gridMode == currentGridMode ? .on : .off
            ) { [weak self] _ in
                guard self?.setGridMode(gridMode) == true else { return }
                Haptic.selectionChanged()
            }
        }
        return UIMenu(
            options: [.displayInline, .singleSelection, .displayAsPalette],
            children: actions
        )
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
        let effects = gridModeInteractionCoordinator.handle(
            .menuSelected(
                fromMode: initialGridMode,
                toMode: gridMode,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            ),
            ratioProvider: { [weak self] fromMode in
                guard canAnimateTransition else { return [] }
                return self?.makeGridModeRatios(fromMode: fromMode) ?? []
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
        gridModeInteractionCoordinator.phase != .idle
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

        let fromAnchorContentPoint = CGPoint(
            x: anchor.viewportPoint.x + collectionView.contentOffset.x,
            y: anchor.viewportPoint.y + anchor.baseContentOffsetY
        )
        let toAnchorContentPoint = CGPoint(
            x: MobilePlayerBrowserGridTransition.anchorX(
                itemFrame: toFrame,
                relativeX: anchor.relativeItemPoint.x
            ),
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
            outgoingAnchor: anchor.viewportPoint,
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
              !isScrollToTopAnimationActive,
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

    private func applyGridModeInteractionBegan(
        transitionAnchor: (() -> GridModeGestureAnchor?)?
    ) {
        guard !gridModeRenderer.isActive,
              let sourceLayout = browserCollectionLayout.browserLayout else {
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
        cancelScrollToTopAnimationState()
        finishCurrentDrag()
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        collectionView.isScrollEnabled = false
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
        guard let finishState = gridModeRenderer.finish(
            preservingCarryover: true
        ) else {
            return
        }
        gridModePinchFrameCoalescer.invalidate()
        stopGridModeSettleDisplayLink()
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
        collectionView.isScrollEnabled = isActive
        if settlesPosition {
            settleCurrentPosition()
        }
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
        panDeltaY: CGFloat
    ) -> Bool {
        gridModeRenderer.renderSettle(
            id: id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: panDeltaY
        )
    }

    private func commitGridModePlaneGeometry(
        id: UUID,
        mode: MobileCollectionBrowserGridMode
    ) -> Bool {
        guard let preparation = gridModeRenderer.prepareCommit(
            id: id,
            mode: mode
        ) else {
            return false
        }
        var completed = false
        defer {
            if !completed {
                gridModeRenderer.abortCommit(preparation)
            }
        }
        let plane = preparation.planeRequest
        layoutAspectState = plane.layoutAspectState
        gridModeCommitFadeDeadline = CACurrentMediaTime()
            + Self.gridModeCommitFadeWindow
        let toLayout = plane.transitionLayout.toLayout
        installCollectionLayout(toLayout)
        applyGridModeTransitionEndpoint(
            layout: toLayout,
            contentOffsetY: preparation.terminalContentOffsetY
        )
        guard gridModeRenderer.completeCommit(preparation) else { return false }
        completed = true
        retainFocusedTokenIndex(plane.anchorTokenIndex)
        focusedTokenIndex = plane.anchorTokenIndex
        return true
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
            },
            resolveContent: { source, _, _ in source?.content }
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
                x: -collectionView.adjustedContentInset.left,
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
                columnCount: mode.columnCount
            ) else {
                return nil
            }
            return .init(mode: mode, itemWidthRatio: width / fromWidth)
        }
    }

    private func gridModePinchFrame(
        _ recognizer: UIPinchGestureRecognizer,
        timestamp: TimeInterval
    ) -> GridModePinchFrame {
        let viewLocation = recognizer.location(in: view)
        return GridModePinchFrame(
            scale: recognizer.scale,
            viewLocation: viewLocation,
            timestamp: timestamp
        )
    }

    private func finalizeGridModeInteractionIfNeeded() {
        guard hasGridModeInteractionState else { return }
        gridModePinchFrameCoalescer.invalidate()
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
            let timestamp = CACurrentMediaTime()
            let frame = gridModePinchFrame(
                recognizer,
                timestamp: timestamp
            )
            gridModePinchFrameCoalescer.seed(frame)
            let effects = gridModeInteractionCoordinator.handle(
                .pinchBegan(
                    sample: frame.sample,
                    currentMode: gridMode
                ),
                ratioProvider: { [weak self] fromMode in
                    self?.makeGridModeRatios(fromMode: fromMode) ?? []
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
            gridModePinchFrameCoalescer.stage(gridModePinchFrame(
                recognizer,
                timestamp: CACurrentMediaTime()
            ))

        case .ended:
            gridModePinchFrameCoalescer.flush()
            finishGridModePinch(
                velocity: recognizer.velocity,
                isCancelled: false
            )

        case .cancelled, .failed:
            gridModePinchFrameCoalescer.flush()
            finishGridModePinch(velocity: 0, isCancelled: true)

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
        applyGridModeInteractionEffects(
            effects,
            transitionAnchor: gridModePinchAnchorProvider(
                viewLocation: frame.viewLocation
            )
        )
    }

    private func finishGridModePinch(
        velocity: CGFloat,
        isCancelled: Bool
    ) {
        let event: PlayerBrowserGridInteractionCoordinator.Event = isCancelled
            ? .pinchCancelled(reduceMotion: UIAccessibility.isReduceMotionEnabled)
            : .pinchEnded(
                velocity: velocity,
                timestamp: CACurrentMediaTime(),
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            )
        let effects = gridModeInteractionCoordinator.handle(event)
        applyGridModeInteractionEffects(
            effects,
            transitionAnchor: nil
        )
        if gridModeInteractionCoordinator.phase == .idle {
            scheduleGridModeGeometryPrewarmIfPossible()
        }
    }

    @objc private func handleGridModeSettleTick(_: CADisplayLink) {
        let effects = gridModeInteractionCoordinator.handle(
            .settleTick(timestamp: CACurrentMediaTime())
        )
        applyGridModeInteractionEffects(effects, transitionAnchor: nil)
    }

    private func startGridModeSettleDisplayLink() {
        guard gridModeSettleDisplayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(handleGridModeSettleTick(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        gridModeSettleDisplayLink = displayLink
    }

    private func stopGridModeSettleDisplayLink() {
        gridModeSettleDisplayLink?.invalidate()
        gridModeSettleDisplayLink = nil
    }

    @discardableResult
    private func applyGridModeInteractionEffects(
        _ initialEffects: [PlayerBrowserGridInteractionCoordinator.Effect],
        transitionAnchor: (() -> GridModeGestureAnchor?)?
    ) -> Bool {
        let result = drainGridModeInteractionEffects(
            initialEffects,
            transitionAnchor: transitionAnchor
        )
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
                applyGridModeInteractionBegan(
                    transitionAnchor: transitionAnchor
                )

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

            case let .renderSettle(id, scale, settleProgress, panDeltaY):
                guard renderGridModeSettle(
                    id: id,
                    scale: scale,
                    settleProgress: settleProgress,
                    panDeltaY: panDeltaY
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
                startGridModeSettleDisplayLink()
                let continuedEffects = gridModeInteractionCoordinator.handle(
                    .settleStarted(timestamp: CACurrentMediaTime())
                )
                pendingEffects.insert(contentsOf: continuedEffects, at: 0)

            case .stopDisplayLink:
                stopGridModeSettleDisplayLink()

            case let .persistMode(mode):
                if let browseSnapshot {
                    MobilePlaybackController.shared.saveCollectionBrowseGridMode(
                        mode,
                        snapshot: browseSnapshot
                    )
                }

            case let .reconcileMedia(cancelsPrefetchLoads):
                if cancelsPrefetchLoads {
                    cancelAllPrefetchLoads()
                }
                lastThumbnailWindowRequest = nil
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

    /// `makeGridModeGestureAnchor` resolves item frames in mirrored view space,
    /// but `currentFocalPoint` reads layout attributes, which are unmirrored.
    private func gridModeVisualFocalPoint() -> CGPoint {
        let focalPoint = currentFocalPoint()
        guard let layout = browserCollectionLayout.browserLayout else {
            return focalPoint
        }
        return gridModeVisualGeometry(for: layout).mirroredPoint(focalPoint)
    }

    /// Resolves the anchor the way every grid-mode entry point does. Not a
    /// property: `currentAnchorTokenIndex()` queries layout attributes and
    /// can clear `forcedFocusedTokenIndex`, so this must be called once.
    private func gridModeAnchorTokenIndex() -> Int? {
        currentAnchorTokenIndex()
            ?? forcedFocusedTokenIndex
            ?? focusedTokenIndex
            ?? browseSnapshot?.initialTokenIndex
    }

    func setActive(_ active: Bool) {
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
            scheduleGridModeGeometryPrewarmIfPossible()
        }
    }

    func prepareForDisplay(
        using preparation: PlayerCollectionBrowsePreparation,
        forcePosition: Bool = false,
        publishWhenStable: Bool,
        completion: @escaping (MobilePlayerCollectionBrowserDisplayPreparationResult) -> Void
    ) {
        loadViewIfNeeded()
        finalizeGridModeInteractionIfNeeded()
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
        positioningGeneration &+= 1
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
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
        guard let identity = browserContentIdentity(
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
        publicationState = preparedTransition.publicationState
        hasFinishedInitialPositioning = preparedTransition.hasFinishedInitialPositioning
        layoutAspectState = preparedTransition.layoutAspectState
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

        cancelScrollToTopAnimationState()
        finishCurrentDrag()
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
        gridModeRenderer.didConfigureCell(browserCell, at: indexPath)
        return browserCell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        gridModeRenderer.willDisplayCell(cell, at: indexPath)
        guard isActive || preparedTransition != nil else { return }
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        if !gridModeRenderer.isActive {
            browserCell.resumeImageLoadIfNeeded(tokenIndex: indexPath.item)
            if MobilePlayerCollectionBrowserTransitionSupport
                .itemIntersectsViewport(
                    at: indexPath,
                    cell: browserCell,
                    collectionView: collectionView,
                    viewportView: view
                ) {
                browserCell.promoteImageLoadToForegroundIfNeeded(
                    tokenIndex: indexPath.item
                )
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        gridModeRenderer.didEndDisplayingCell(cell, at: indexPath)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        browserCell.cancelImageLoad(ifRepresenting: indexPath.item)
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

            var children = [UIMenuElement]()
            let isBookmarked = PlayerBookmarksStore.isBookmarked(
                collectionId: descriptor.collectionId,
                tokenId: descriptor.tokenId
            )
            children.append(
                UIAction(
                    title: isBookmarked ? Strings.removeBookmark : Strings.bookmark,
                    image: UIImage(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                ) { _ in
                    PlayerBookmarksStore.toggleBookmark(
                        collectionId: descriptor.collectionId,
                        tokenId: descriptor.tokenId
                    )
                    Haptic.selectionChanged()
                }
            )
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
        guard isActive,
              !isApplyingPosition,
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
                  let descriptor = MobilePlaybackController.shared.collectionBrowseImageDescriptor(
                    snapshot: browseSnapshot,
                    tokenIndex: tokenIndex,
                    quality: requiredImageQuality
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
                prefetchLoads[tokenIndex] = CancellableLoad(
                    id: loadID,
                    cancellation: cancellation
                )
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for tokenIndex in Set(indexPaths.map(\.item)) {
            prefetchLoads.removeValue(forKey: tokenIndex)?.cancellation()
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelScrollToTopAnimationState()
        lastScrollOffsetY = scrollView.contentOffset.y
        dragStartContentOffsetY = clampedVerticalContentOffsetY(scrollView.contentOffset.y)
        hasAcknowledgedCurrentDrag = false
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
            let offsetDelta = PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
                previousOffsetY: previousOffsetY,
                currentOffsetY: scrollView.contentOffset.y,
                validRange: verticalContentOffsetRange
            )
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
        guard isActive, !hasGridModeInteractionState else { return false }
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
        return true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        cancelScrollToTopAnimationState()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    private func applyBrowseSnapshot(
        _ snapshot: PlayerCollectionBrowseSnapshot?,
        sampledAround focusedTokenIndex: Int?
    ) {
        cancelGridModeGeometryPrewarming()
        gridModeGeometryCache = nil
        browseSnapshot = snapshot
        updateLayoutAspectProfile(
            snapshot: snapshot,
            focusedTokenIndex: focusedTokenIndex
        )
        cancelAllPrefetchLoads()
        visibleBrowserCells.forEach { $0.cancelImageLoad() }
        // An in-place reload recreates every cell; anchor-nearest regions keep
        // their current pixels and crossfade to the reloaded content.
        let isOnScreen = isActive && viewIfLoaded?.window != nil
        let carryoverSources = isOnScreen
            ? captureVisibleCarryoverSources(
                anchorTokenIndex: focusedTokenIndex
            )
            : []
        if isOnScreen {
            gridModeCommitFadeDeadline = CACurrentMediaTime()
                + Self.gridModeCommitFadeWindow
        }
        collectionView.reloadData()
        configureCollectionLayout()
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
        focusedTokenIndex: Int?
    ) {
        let defaultSize = CGSize(width: 1, height: 1)
        guard let snapshot,
              snapshot.itemCount > 0 else {
            layoutAspectState = MobilePlayerCollectionBrowserLayoutAspectState(
                aspectProfile: MobilePlayerBrowserAspectProfile(
                    itemCount: 0,
                    uniformImageSize: defaultSize
                ),
                fallbackSpec: PlayerMediaPlaceholderSpec(
                    aspectSize: defaultSize
                )
            )
            return
        }

        let columnCount = MobilePlaybackController.shared
            .collectionBrowseGridMode(snapshot: snapshot)
            .columnCount
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
        let changed = newSnapshot != browseSnapshot
        guard changed || resetPublicationState else { return }

        if !resetPublicationState,
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
        let isScrollInteractionActive =
            dragStartContentOffsetY != nil || isScrollToTopAnimationActive
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
        guard !isApplyingPosition else { return }
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
        scheduleGridModeGeometryPrewarmIfPossible()
    }

    private func performSelection(at tokenIndex: Int) {
        guard !hasGridModeInteractionState,
              canSelectBrowserCell(at: tokenIndex),
              let selection = transitionSelection(tokenIndex: tokenIndex),
              onSelection?(selection) == true else {
            return
        }
        settleSelection(at: tokenIndex)
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
        let displayedLargeImages = requiredImageQuality == .thumbnail
            ? displayedLargeImageWindowState()
            : .empty
        let request = ThumbnailWindowRequest(
            tokenIndex: tokenIndex,
            direction: direction,
            prefetchStride: configuredPrefetchStride,
            quality: requiredImageQuality,
            displayedLargeTokenIndices: displayedLargeImages.tokenIndices,
            locallyAvailableLargeTokenIndices:
                displayedLargeImages.locallyAvailableTokenIndices
        )
        if !force, lastThumbnailWindowRequest == request {
            return
        }
        if !force,
           let lastThumbnailWindowRequest,
           lastThumbnailWindowRequest.direction == direction,
           lastThumbnailWindowRequest.prefetchStride == configuredPrefetchStride,
           lastThumbnailWindowRequest.quality == requiredImageQuality,
           lastThumbnailWindowRequest.displayedLargeTokenIndices
                == displayedLargeImages.tokenIndices,
           lastThumbnailWindowRequest.locallyAvailableLargeTokenIndices
                == displayedLargeImages.locallyAvailableTokenIndices,
           abs(lastThumbnailWindowRequest.tokenIndex - tokenIndex) < configuredPrefetchStride {
            return
        }
        _ = MobilePlaybackController.shared.prepareCollectionBrowseThumbnailWindow(
            uuid: uuid,
            centeredAt: tokenIndex,
            direction: direction,
            prefetchStride: configuredPrefetchStride,
            quality: requiredImageQuality,
            displayedLargeTokenIndices: displayedLargeImages.tokenIndices,
            locallyAvailableLargeTokenIndices:
                displayedLargeImages.locallyAvailableTokenIndices
        )
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

    private func cancelAllPrefetchLoads() {
        let cancellations = prefetchLoads.values.map(\.cancellation)
        prefetchLoads.removeAll()
        cancellations.forEach { $0() }
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
        allowsLocalLargeImageUpgrade: Bool = true
    ) {
        guard let contentIdentity = browserContentIdentity(
            forTokenIndex: indexPath.item
        ) else {
            cell.prepareForGridModePhantomReuse()
            return
        }
        let imageSources = browseImageSources(forTokenIndex: indexPath.item)
        let resolvedImageLoadPolicy = imageLoadPolicy
            ?? (isActive || preparedTransition != nil
                ? .foreground
                : .disabled)
        cell.configure(
            contentIdentity: contentIdentity,
            itemCount: browseSnapshot?.itemCount ?? 0,
            imageSources: imageSources,
            requiredImageQuality: requiredImageQuality
                ?? self.requiredImageQuality,
            missingDescriptorFallbackSpec: layoutAspectState.fallbackSpec,
            imageLoadPolicy: resolvedImageLoadPolicy,
            fadesFirstImage: CACurrentMediaTime() < gridModeCommitFadeDeadline,
            allowsLocalLargeImageUpgrade: allowsLocalLargeImageUpgrade
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
        guard isActive || preparedTransition != nil,
              let change = notification.object
                as? DownloadableMediaCacheFileAvailabilityChange else {
            return
        }
        visibleBrowserCells.forEach {
            $0.updateLocalFileAvailability(
                notification: notification,
                isAvailable: change == .becameAvailable
            )
        }
        if change == .becameUnavailable {
            return
        }
        gridModeRenderer.viewportRenderCells.forEach {
            $0.refreshAvailableImageIfNeeded(notification: notification)
        }
    }

    private var visibleBrowserCells: [MobilePlayerCollectionBrowserCell] {
        collectionView.visibleCells.compactMap { $0 as? MobilePlayerCollectionBrowserCell }
    }

    private func displayedLargeImageWindowState() -> DisplayedLargeImageWindowState {
        var tokenIndices = Set<Int>()
        var locallyAvailableTokenIndices = Set<Int>()
        for cell in visibleBrowserCells {
            guard let entry = cell.displayedLargeImageWindowEntry else { continue }
            tokenIndices.insert(entry.tokenIndex)
            if entry.isLocallyAvailable {
                locallyAvailableTokenIndices.insert(entry.tokenIndex)
            }
        }
        return DisplayedLargeImageWindowState(
            tokenIndices: tokenIndices,
            locallyAvailableTokenIndices: locallyAvailableTokenIndices
        )
    }
}

private extension MobileCollectionBrowserGridMode {

    var menuTitle: String {
        switch self {
        case .large:
            Strings.largeGrid
        case .threeColumns:
            Strings.threeColumns
        case .fiveColumns:
            Strings.fiveColumns
        }
    }

    var menuSystemImageName: String {
        switch self {
        case .large:
            "rectangle.grid.1x2"
        case .threeColumns:
            "square.grid.3x2"
        case .fiveColumns:
            "square.grid.4x3.fill"
        }
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
        let candidateItemIndices = browserLayout?.candidateItemIndices(
            intersecting: rect
        ) ?? 0..<0
        return candidateItemIndices
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
