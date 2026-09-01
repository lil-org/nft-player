import UIKit
import os

private let gridModeCoordinatorSignposter = OSSignposter(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "GridModeCoordinator"
)

private struct CachedGridModeDestination {
    let anchorTokenIndex: Int
    let layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    let layout: MobilePlayerBrowserLayout
}

/// Excludes the initial token because settled-position echoes do not change geometry.
private struct GridModeGeometryCacheIdentity: Equatable {
    let collectionId: String
    let itemCount: Int
    let viewportSize: CGSize
    let displayScale: CGFloat
    let topContentInset: CGFloat
    let bottomContentInset: CGFloat
}

private struct CachedGridModeGeometry {
    let aspectProfile: MobilePlayerBrowserAspectProfile
    let layout: MobilePlayerBrowserLayout
}

private struct GridModeGeometryCache {
    let identity: GridModeGeometryCacheIdentity
    var geometries: [MobileCollectionBrowserGridMode: CachedGridModeGeometry]
}

private struct GridModeGeometryPrewarmPlan {
    let identity: GridModeGeometryCacheIdentity
    var modes: [MobileCollectionBrowserGridMode]
}

@MainActor
final class MobilePlayerCollectionBrowserGridModeCoordinator: NSObject,
    UIGestureRecognizerDelegate {
    struct CurrentState {
        let browseSnapshot: PlayerCollectionBrowseSnapshot?
        let layoutAspectState:
            MobilePlayerCollectionBrowserLayoutAspectState
        let isActive: Bool
        let isViewVisible: Bool
        let isApplyingPosition: Bool
        let hasFinishedInitialPositioning: Bool
        let focusedTokenIndex: Int?
        let forcedFocusedTokenIndex: Int?
        let isScrollMotionActive: Bool
        let needsWindowSafeAreaRefresh: Bool
        let hasPreparedTransition: Bool
        let currentLayoutDisplayScale: CGFloat
        let layoutWindowSafeAreaInsets: UIEdgeInsets
    }

    struct LayoutOperations {
        let makeLayoutAspectState: @MainActor (
            PlayerCollectionBrowseSnapshot,
            Int,
            Int?,
            ThumbnailAspectRatioProfile?
        ) -> MobilePlayerCollectionBrowserLayoutAspectState
        let makeLayoutFallbackSpec: @MainActor (
            PlayerCollectionBrowseSnapshot,
            Int?
        ) -> PlayerMediaPlaceholderSpec
        let makeLayoutAspectProfile: @MainActor (
            PlayerCollectionBrowseSnapshot,
            Int,
            ThumbnailAspectRatioProfile
        ) -> MobilePlayerBrowserAspectProfile
        let makeBrowserLayout: @MainActor (
            MobilePlayerBrowserAspectProfile
        ) -> MobilePlayerBrowserLayout?
        let installCollectionLayout: @MainActor (
            MobilePlayerBrowserLayout
        ) -> Void
        let centerContent: @MainActor (Int) -> Void
        let currentAnchorTokenIndex: @MainActor () -> Int?
        let currentFocalPoint: @MainActor () -> CGPoint
        let retainFocusedTokenIndex: @MainActor (Int?) -> Void
    }

    struct BrowserEffects {
        let setBrowseSnapshot: @MainActor (
            PlayerCollectionBrowseSnapshot?
        ) -> Void
        let setLayoutAspectState: @MainActor (
            MobilePlayerCollectionBrowserLayoutAspectState
        ) -> Void
        let updateLayoutAspectProfile: @MainActor (
            PlayerCollectionBrowseSnapshot?,
            Int?,
            Int
        ) -> Void
        let configureCollectionLayout: @MainActor () -> Void
        let endScrollMotionAndResetDragState: @MainActor () -> Void
        let settleCurrentPosition: @MainActor () -> Void
        let prepareCurrentImageWindowIfPossible: @MainActor () -> Void
        let settleAfterApplyingPendingWindowSafeAreaRefresh:
            @MainActor () -> Void
        let reloadVisibleCells: @MainActor () -> Void
        let browseImageSources: @MainActor (
            Int
        ) -> CollectionBrowseImageSources?
    }

    private static let boundaryEpsilon: CGFloat = 0.75
    private static let verticalContentMargin: CGFloat = 0

    private let frameDriver: any GridTransitionFrameDriving
    private let coverRenderer: MobilePlayerGridTransitionCoverRenderer
    private weak var collectionView:
        MobilePlayerCollectionBrowserCollectionView?
    private weak var viewportView: UIView?
    private var browserCollectionLayout:
        MobilePlayerCollectionBrowserLayout?
    private var scrollCoordinator:
        MobilePlayerCollectionBrowserScrollCoordinator?
    private var imagePipeline:
        MobilePlayerCollectionBrowserImagePipeline?
    private var currentState: (@MainActor () -> CurrentState)?
    private var layoutOperations: LayoutOperations?
    private var browserEffects: BrowserEffects?
    private var isInvalidated = false

    private var renderer: MobilePlayerCollectionBrowserGridRenderer?
    private var pinchRecognizer: UIPinchGestureRecognizer?
    private var geometryPrewarmUpdate: PendingMainQueueUpdate?
    private var transitionRuntime: PlayerBrowserGridTransitionRuntime
    private var effectDrainDepth = 0
    private var contentOffsetRestorationDepth = 0
    private var settleContentOffsetY: CGFloat?
    private var settlePanMaximumNumberOfTouches: Int?
    private var geometryCache: GridModeGeometryCache?
    private var geometryPrewarmPlan: GridModeGeometryPrewarmPlan?
    private var destinationCache = [
        MobileCollectionBrowserGridMode: CachedGridModeDestination
    ]()
    private var lastPinchViewLocation: CGPoint?
    private var settlingReanchorCount = 0

    init(
        commitSnapshotFactory: @escaping (UIView) -> UIView?,
        frameDriver: (any GridTransitionFrameDriving)? = nil
    ) {
        self.frameDriver = frameDriver
            ?? GridTransitionDisplayLinkFrameDriver()
        self.coverRenderer = MobilePlayerGridTransitionCoverRenderer(
            snapshotFactory: commitSnapshotFactory
        )
        self.transitionRuntime = PlayerBrowserGridTransitionRuntime(
            configuration: .init(
                coverFadeDuration:
                    MobilePlayerCollectionBrowserTransitionPresentation
                        .contentFadeDuration,
                coverRemovalGrace: 0.05,
                rendererFadeDuration:
                    GridPlaneRenderer.contentFadeOutDuration,
                firstImageFadeWindow: 1.5
            )
        )
        super.init()
    }

    func configure(
        collectionView: MobilePlayerCollectionBrowserCollectionView,
        viewportView: UIView,
        collectionLayout: MobilePlayerCollectionBrowserLayout,
        scrollCoordinator: MobilePlayerCollectionBrowserScrollCoordinator,
        imagePipeline: MobilePlayerCollectionBrowserImagePipeline,
        rendererContentAccess:
            MobilePlayerCollectionBrowserGridRenderer.ContentAccess,
        currentState: @escaping @MainActor () -> CurrentState,
        layoutOperations: LayoutOperations,
        browserEffects: BrowserEffects
    ) {
        guard !isInvalidated, renderer == nil else { return }
        self.collectionView = collectionView
        self.viewportView = viewportView
        browserCollectionLayout = collectionLayout
        self.scrollCoordinator = scrollCoordinator
        self.imagePipeline = imagePipeline
        self.currentState = currentState
        self.layoutOperations = layoutOperations
        self.browserEffects = browserEffects
        renderer = MobilePlayerCollectionBrowserGridRenderer(
            collectionView: collectionView,
            viewportView: viewportView,
            contentAccess: rendererContentAccess
        )
        let recognizer = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinch(_:))
        )
        recognizer.delegate = self
        pinchRecognizer = recognizer
        viewportView.addGestureRecognizer(recognizer)
        geometryPrewarmUpdate = PendingMainQueueUpdate(
            action: { [weak self] in
                self?.prewarmNextGeometry()
            }
        )
    }

    var hasInteractionState: Bool {
        transitionRuntime.phase != .idle
    }

    var gridMode: MobileCollectionBrowserGridMode {
        guard let layoutAspectState = currentState?().layoutAspectState else {
            return .defaultMode
        }
        return MobileCollectionBrowserGridMode(
            rawValue: layoutAspectState.aspectProfile.columnCount
        ) ?? .defaultMode
    }

    var viewportRenderCells: [MobilePlayerCollectionBrowserCell] {
        renderer?.viewportRenderCells ?? []
    }

    var isRendererActive: Bool {
        renderer?.isActive == true
    }

    var blocksSelection: Bool {
        transitionRuntime.blocksSelection
    }

    var fadesFirstImage: Bool {
        transitionRuntime.fadesFirstImage(at: frameDriver.now)
    }

    func makeMenu() -> UIMenu {
        let currentMode = gridMode
        let actions = MobileCollectionBrowserGridMode.allCases.reversed().map {
            mode in
            UIAction(
                title: menuTitle(for: mode),
                image: UIImage(systemName: menuSystemImageName(for: mode)),
                state: mode == currentMode ? .on : .off
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard self?.setGridMode(mode) == true else { return }
                    Haptic.selectionChanged()
                }
            }
        }
        return UIMenu(
            options: [.displayInline, .singleSelection, .displayAsPalette],
            children: actions
        )
    }

    @discardableResult
    func setGridMode(_ mode: MobileCollectionBrowserGridMode) -> Bool {
        guard !isInvalidated,
              let state = currentState?(),
              let browseSnapshot = state.browseSnapshot else {
            return false
        }
        let initialMode = gridMode
        guard mode != initialMode,
              state.isActive,
              !state.isApplyingPosition,
              !hasInteractionState,
              !state.hasPreparedTransition else {
            return false
        }

        let retainedTokenIndex = gridModeAnchorTokenIndex()
            ?? browseSnapshot.initialTokenIndex
        let ratios = state.hasFinishedInitialPositioning
            ? makeGridModeRatios(fromMode: initialMode)
            : []
        let output = transitionRuntime.handle(
            .menuSelected(
                fromMode: initialMode,
                toMode: mode,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            ),
            at: frameDriver.now,
            ratioProvider: { fromMode in
                fromMode == initialMode ? ratios : []
            }
        )
        return applyRuntimeOutput(
            output,
            transitionAnchor: { [weak self] in
                guard let self else { return nil }
                return self.makeGestureAnchor(
                    tokenIndex: retainedTokenIndex,
                    preferredContentPoint: self.gridModeVisualFocalPoint()
                )
            }
        )
    }

    func didConfigureCell(
        _ cell: MobilePlayerCollectionBrowserCell,
        at indexPath: IndexPath
    ) {
        renderer?.didConfigureCell(cell, at: indexPath)
    }

    func willDisplayCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        renderer?.willDisplayCell(cell, at: indexPath)
    }

    func didEndDisplayingCell(
        _ cell: UICollectionViewCell,
        at indexPath: IndexPath
    ) {
        renderer?.didEndDisplayingCell(cell, at: indexPath)
    }

    enum GeometryChangePreparation {
        case ready(anchorTokenIndex: Int?)
        case retryAfterInteractionFinishes
    }

    func prepareForGeometryChange(
        _ geometryChanged: Bool
    ) -> GeometryChangePreparation {
        guard !isInvalidated, geometryChanged else {
            return .ready(anchorTokenIndex: nil)
        }
        var anchorTokenIndex: Int?
        if hasInteractionState {
            anchorTokenIndex = renderer?.anchorTokenIndex
            interruptInteractionIfNeeded()
            guard !hasInteractionState else {
                return .retryAfterInteractionFinishes
            }
        }
        removeTransitionCover()
        return .ready(anchorTokenIndex: anchorTokenIndex)
    }

    func interruptInteractionIfNeeded() {
        guard !isInvalidated else { return }
        let coverAtEntry = transitionRuntime.activeCover?.id
        defer {
            if transitionRuntime.activeCover?.id == coverAtEntry {
                removeTransitionCover()
            }
        }
        guard hasInteractionState else { return }
        lastPinchViewLocation = nil
        let output = transitionRuntime.handle(
            .interrupt,
            at: frameDriver.now
        )
        applyRuntimeOutput(output, transitionAnchor: nil)
        if transitionRuntime.phase == .idle {
            scheduleGeometryPrewarmIfPossible()
        }
    }

    @discardableResult
    func finalizeInterruptibleSettle() -> Bool {
        guard hasInterruptibleSettle,
              contentOffsetRestorationDepth == 0 else {
            return false
        }
        interruptInteractionIfNeeded()
        return transitionRuntime.phase == .idle
    }

    func prepareForDragging() {
        guard !isInvalidated else { return }
        interruptSettleForDragIfNeeded()
        removeTransitionCover()
    }

    func dragDidBeginScrollMotion() {
        cancelGeometryPrewarming()
    }

    struct ScrollObservation {
        let shouldContinue: Bool
        let settlesAfterImmediateOffset: Bool
    }

    func observeScrollDuringGridMode(
        _ scrollView: UIScrollView
    ) -> ScrollObservation {
        guard !isInvalidated else {
            return ScrollObservation(
                shouldContinue: true,
                settlesAfterImmediateOffset: false
            )
        }
        if contentOffsetRestorationDepth > 0 {
            _ = scrollCoordinator?.observeContentOffset(
                scrollView.contentOffset.y
            )
            return ScrollObservation(
                shouldContinue: false,
                settlesAfterImmediateOffset: false
            )
        }
        if let snapshotContentOffset = transitionRuntime.activeCover?
            .contentOffset,
           effectDrainDepth == 0,
           scrollView.contentOffset != snapshotContentOffset {
            removeTransitionCover()
        }
        return ScrollObservation(
            shouldContinue: true,
            settlesAfterImmediateOffset:
                resolveScrollObservedDuringSettle(scrollView)
        )
    }

    func contentOffsetTarget(
        for requestedContentOffset: CGPoint,
        animated: Bool
    ) -> (target: CGPoint, settlesAfterApplying: Bool) {
        guard !isInvalidated, let collectionView else {
            return (requestedContentOffset, false)
        }
        let requestedDeltaY = requestedContentOffset.y
            - collectionView.contentOffset.y
        guard requestedDeltaY.isFinite else {
            return (collectionView.contentOffset, false)
        }
        guard requestedDeltaY != 0 else {
            guard transitionRuntime.phase == .settling else {
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
        guard finalizeInterruptibleSettle() else {
            if transitionRuntime.phase == .idle,
               effectDrainDepth == 0 {
                removeTransitionCover()
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

    func settleAfterImmediateOffsetIfPossible() {
        guard !isInvalidated,
              let state = currentState?(),
              let collectionView,
              transitionRuntime.phase == .idle,
              !state.isApplyingPosition,
              !collectionView.isTracking,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              !state.isScrollMotionActive else {
            return
        }
        browserEffects?
            .settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func discardTransitionCover() {
        guard !isInvalidated else { return }
        removeTransitionCover()
    }

    func scheduleGeometryPrewarmIfPossible() {
        guard !isInvalidated,
              let context = geometryPrewarmContext(),
              let browserLayout = browserCollectionLayout?.browserLayout,
              let state = currentState?(),
              let currentMode = MobileCollectionBrowserGridMode(
                  rawValue: state.layoutAspectState.aspectProfile.columnCount
              ) else {
            cancelGeometryPrewarming()
            return
        }

        let identity = ensureGeometryCache(snapshot: context.snapshot)
        geometryCache?.geometries[currentMode] = CachedGridModeGeometry(
            aspectProfile: state.layoutAspectState.aspectProfile,
            layout: browserLayout
        )

        let missingModes = MobileCollectionBrowserGridMode.allCases
            .filter { geometryCache?.geometries[$0] == nil }
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
            cancelGeometryPrewarming()
            return
        }

        geometryPrewarmUpdate?.invalidate()
        geometryPrewarmPlan = GridModeGeometryPrewarmPlan(
            identity: identity,
            modes: missingModes
        )
        geometryPrewarmUpdate?.schedule()
    }

    func cancelGeometryPrewarming() {
        geometryPrewarmUpdate?.invalidate()
        geometryPrewarmPlan = nil
    }

    func resetGeometryState() {
        cancelGeometryPrewarming()
        geometryCache = nil
    }

    func applyBrowseSnapshot(
        _ snapshot: PlayerCollectionBrowseSnapshot?,
        sampledAround focusedTokenIndex: Int?,
        gridMode: MobileCollectionBrowserGridMode
    ) {
        guard !isInvalidated,
              let state = currentState?(),
              let effects = browserEffects,
              let layoutOperations,
              let collectionView,
              let viewportView,
              let imagePipeline else {
            return
        }
        cancelGeometryPrewarming()
        let cachedGeometry: CachedGridModeGeometry?
        if let snapshot {
            ensureGeometryCache(snapshot: snapshot)
            cachedGeometry = geometryCache?.geometries[gridMode]
        } else {
            geometryCache = nil
            cachedGeometry = nil
        }
        effects.setBrowseSnapshot(snapshot)
        if let snapshot, let cachedGeometry {
            effects.setLayoutAspectState(
                MobilePlayerCollectionBrowserLayoutAspectState(
                    aspectProfile: cachedGeometry.aspectProfile,
                    fallbackSpec: layoutOperations.makeLayoutFallbackSpec(
                        snapshot,
                        focusedTokenIndex
                    )
                )
            )
        } else {
            effects.updateLayoutAspectProfile(
                snapshot,
                focusedTokenIndex,
                gridMode.columnCount
            )
        }
        imagePipeline.cancelVisibleCellImageLoads()
        let isOnScreen = state.isActive && viewportView.window != nil
        let carryoverSources = isOnScreen
            ? captureVisibleCarryoverSources(
                anchorTokenIndex: focusedTokenIndex
            )
            : []
        if isOnScreen {
            transitionRuntime.beginFirstImageFade(at: frameDriver.now)
            reconcileFrameDriving()
        }
        collectionView.reloadData()
        if let cachedGeometry {
            layoutOperations.installCollectionLayout(cachedGeometry.layout)
        } else {
            effects.configureCollectionLayout()
        }
        collectionView.layoutIfNeeded()
        if !carryoverSources.isEmpty {
            installCarryoverContent(
                sources: carryoverSources,
                anchorTokenIndex: focusedTokenIndex
            )
        }
    }

#if DEBUG
    struct LifecycleStateForTesting: Equatable {
        let isInvalidated: Bool
        let hasPendingPinchFrame: Bool
        let hasPendingGeometryPrewarm: Bool
        let isSettleDisplayLinkActive: Bool
        let isInteractionFadeDisplayLinkActive: Bool
        let isFrameDriverActive: Bool
        let hasCommitSnapshot: Bool
        let isRendererActive: Bool
        let isPinchRecognizerAttached: Bool
        let isDrainingEffects: Bool
        let isRestoringContentOffset: Bool
        let settlingReanchorCount: Int
    }

    var lifecycleStateForTesting: LifecycleStateForTesting {
        LifecycleStateForTesting(
            isInvalidated: isInvalidated,
            hasPendingPinchFrame: transitionRuntime.hasPendingPinchFrame,
            hasPendingGeometryPrewarm: geometryPrewarmPlan != nil,
            isSettleDisplayLinkActive:
                transitionRuntime.needsSettleFrames,
            isInteractionFadeDisplayLinkActive:
                transitionRuntime.needsInteractionFadeFrames,
            isFrameDriverActive: frameDriver.isRunning,
            hasCommitSnapshot:
                transitionRuntime.hasCover && coverRenderer.hasCover,
            isRendererActive: renderer?.isActive == true,
            isPinchRecognizerAttached: pinchRecognizer?.view != nil,
            isDrainingEffects: effectDrainDepth > 0,
            isRestoringContentOffset: contentOffsetRestorationDepth > 0,
            settlingReanchorCount: settlingReanchorCount
        )
    }

    func flushPendingPinchFrameForTesting() {
        let output = transitionRuntime.flushPendingPinch(
            at: frameDriver.now
        )
        applyRuntimeOutput(output, transitionAnchor: nil)
    }

#endif

    func handleGridModePinchForTesting(
        _ recognizer: UIPinchGestureRecognizer
    ) {
        handlePinch(recognizer)
    }

    private func prewarmNextGeometry() {
        guard !isInvalidated,
              var plan = geometryPrewarmPlan,
              !plan.modes.isEmpty,
              let context = geometryPrewarmContext() else {
            cancelGeometryPrewarming()
            return
        }

        let identity = geometryCacheIdentity(snapshot: context.snapshot)
        guard plan.identity == identity,
              geometryCache?.identity == identity else {
            cancelGeometryPrewarming()
            scheduleGeometryPrewarmIfPossible()
            return
        }

        let mode = plan.modes.removeFirst()
        geometryPrewarmPlan = plan.modes.isEmpty ? nil : plan
        if geometryCache?.geometries[mode] == nil {
            _ = makeGeometry(
                snapshot: context.snapshot,
                mode: mode,
                aspectRatioProfile: context.aspectRatioProfile
            )
        }
        if geometryPrewarmPlan != nil {
            geometryPrewarmUpdate?.schedule()
        }
    }

    private func geometryPrewarmContext() -> (
        snapshot: PlayerCollectionBrowseSnapshot,
        aspectRatioProfile: ThumbnailAspectRatioProfile
    )? {
        guard let state = currentState?(),
              let collectionView,
              state.isActive,
              state.isViewVisible,
              let windowScene = collectionView.window?.windowScene,
              windowScene.activationState == .foregroundActive,
              !hasInteractionState,
              !state.isApplyingPosition,
              !state.needsWindowSafeAreaRefresh,
              !state.hasPreparedTransition,
              state.hasFinishedInitialPositioning,
              !collectionView.isTracking,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              !state.isScrollMotionActive,
              let browseSnapshot = state.browseSnapshot,
              let aspectRatioProfile = MobileCollectionBrowseMediaResolver
                .collectionBrowseThumbnailAspectRatioProfile(
                    snapshot: browseSnapshot
                ),
              case .variable = aspectRatioProfile else {
            return nil
        }
        return (browseSnapshot, aspectRatioProfile)
    }

    @discardableResult
    private func ensureGeometryCache(
        snapshot: PlayerCollectionBrowseSnapshot
    ) -> GridModeGeometryCacheIdentity {
        let identity = geometryCacheIdentity(snapshot: snapshot)
        if geometryCache?.identity != identity {
            geometryCache = GridModeGeometryCache(
                identity: identity,
                geometries: [:]
            )
        }
        return identity
    }

    private func geometryCacheIdentity(
        snapshot: PlayerCollectionBrowseSnapshot
    ) -> GridModeGeometryCacheIdentity {
        let state = currentState?()
        return GridModeGeometryCacheIdentity(
            collectionId: snapshot.collectionId,
            itemCount: snapshot.itemCount,
            viewportSize: viewportView?.bounds.size ?? .zero,
            displayScale: state?.currentLayoutDisplayScale ?? 0,
            topContentInset:
                Self.verticalContentMargin
                    + (state?.layoutWindowSafeAreaInsets.top ?? 0),
            bottomContentInset:
                Self.verticalContentMargin
                    + (state?.layoutWindowSafeAreaInsets.bottom ?? 0)
        )
    }

    private func makeGeometry(
        snapshot: PlayerCollectionBrowseSnapshot,
        mode: MobileCollectionBrowserGridMode,
        aspectRatioProfile: ThumbnailAspectRatioProfile
    ) -> CachedGridModeGeometry? {
        guard let layoutOperations else { return nil }
        ensureGeometryCache(snapshot: snapshot)
        if let geometry = geometryCache?.geometries[mode] {
            return geometry
        }

        let aspectProfile = layoutOperations.makeLayoutAspectProfile(
            snapshot,
            mode.columnCount,
            aspectRatioProfile
        )
        guard let layout = layoutOperations.makeBrowserLayout(aspectProfile) else {
            return nil
        }
        let geometry = CachedGridModeGeometry(
            aspectProfile: aspectProfile,
            layout: layout
        )
        geometryCache?.geometries[mode] = geometry
        return geometry
    }

    private func makeDestination(
        mode: MobileCollectionBrowserGridMode,
        anchorTokenIndex: Int
    ) -> CachedGridModeDestination? {
        guard renderer?.isActive == true,
              let browseSnapshot = currentState?().browseSnapshot,
              let layoutOperations else {
            return nil
        }
        if let cachedDestination = destinationCache[mode],
           cachedDestination.anchorTokenIndex == anchorTokenIndex {
            return cachedDestination
        }

        let aspectState: MobilePlayerCollectionBrowserLayoutAspectState
        let layout: MobilePlayerBrowserLayout
        let aspectRatioProfile = MobileCollectionBrowseMediaResolver
            .collectionBrowseThumbnailAspectRatioProfile(
                snapshot: browseSnapshot
            )
        if let aspectRatioProfile {
            guard let geometry = makeGeometry(
                snapshot: browseSnapshot,
                mode: mode,
                aspectRatioProfile: aspectRatioProfile
            ) else {
                return nil
            }
            aspectState = MobilePlayerCollectionBrowserLayoutAspectState(
                aspectProfile: geometry.aspectProfile,
                fallbackSpec: layoutOperations.makeLayoutFallbackSpec(
                    browseSnapshot,
                    anchorTokenIndex
                )
            )
            layout = geometry.layout
        } else {
            aspectState = layoutOperations.makeLayoutAspectState(
                browseSnapshot,
                mode.columnCount,
                anchorTokenIndex,
                nil
            )
            guard let sampledLayout = layoutOperations.makeBrowserLayout(
                aspectState.aspectProfile
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
        destinationCache[mode] = destination
        return destination
    }

    private func visualGeometry(
        for layout: MobilePlayerBrowserLayout
    ) -> MobilePlayerBrowserVisualLayoutGeometry? {
        collectionView?.visualGeometry(for: layout)
    }

    private func makeGestureAnchor(
        tokenIndex: Int,
        preferredContentPoint: CGPoint
    ) -> GridModeGestureAnchor? {
        guard let collectionView,
              let layout = browserCollectionLayout?.browserLayout,
              let itemFrame = visualGeometry(for: layout)?
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

    private func makePlaneRequest(
        plane: PlayerBrowserGridInteractionCoordinator.Plane
    ) -> GridModePlaneRequest? {
        guard let renderer,
              let renderSnapshot = renderer.renderSnapshot,
              let state = currentState?(),
              let collectionView,
              let viewportView,
              plane.fromMode == gridMode,
              state.browseSnapshot?.itemCount ?? 0 > 0,
              let anchor = renderSnapshot.gestureAnchor,
              let fromLayout = browserCollectionLayout?.browserLayout,
              let destination = makeDestination(
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
              visualGeometry(for: fromLayout)?
                .itemFrame(at: anchor.tokenIndex) != nil,
              let toFrame = visualGeometry(for: destination.layout)?
                .itemFrame(at: anchor.tokenIndex) else {
            return nil
        }

        let viewportSize = viewportView.bounds.size
        let toContentOffsetY = MobilePlayerBrowserGridTransition
            .clampedContentOffsetY(
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
            ),
            imageDecodeVariant:
                MobilePlayerCollectionBrowserGridImageDecodeVariant.resolve(
                    for: destination.layout,
                    displayScale: state.currentLayoutDisplayScale
                )
        )
    }

    private func makeGridModeRatios(
        fromMode: MobileCollectionBrowserGridMode
    ) -> [PlayerBrowserGridInteractionCoordinator.ModeRatio] {
        guard fromMode == gridMode,
              let fromWidth = browserCollectionLayout?.browserLayout?.itemWidth,
              fromWidth > 0,
              let state = currentState?(),
              let viewportView else {
            return []
        }
        return MobileCollectionBrowserGridMode.allCases.compactMap { mode in
            guard mode != fromMode else {
                return .init(mode: mode, itemWidthRatio: 1)
            }
            guard let width = MobilePlayerBrowserLayout.itemWidth(
                viewportSize: viewportView.bounds.size,
                columnCount: mode.columnCount,
                displayScale: state.currentLayoutDisplayScale
            ) else {
                return nil
            }
            return .init(mode: mode, itemWidthRatio: width / fromWidth)
        }
    }

    private func pinchFrame(
        _ recognizer: UIPinchGestureRecognizer
    ) -> PlayerBrowserGridTransitionRuntime.PinchFrame {
        let viewLocation = recognizer.location(in: viewportView)
        return PlayerBrowserGridTransitionRuntime.PinchFrame(
            sample: .init(
                scale: recognizer.scale,
                centroidY: viewLocation.y,
                timestamp: frameDriver.now
            ),
            viewLocation: viewLocation
        )
    }

    private func pinchAnchorProvider(
        viewLocation: CGPoint
    ) -> () -> GridModeGestureAnchor? {
        { [weak self] in
            self?.pinchGestureAnchor(viewLocation: viewLocation)
        }
    }

    private func pinchGestureAnchor(
        viewLocation: CGPoint
    ) -> GridModeGestureAnchor? {
        guard let collectionView, let viewportView else { return nil }
        let contentPoint = collectionView.convert(
            viewLocation,
            from: viewportView
        )
        if let indexPath = collectionView.indexPathForItem(at: contentPoint) {
            return makeGestureAnchor(
                tokenIndex: indexPath.item,
                preferredContentPoint: contentPoint
            )
        }
        return makeGestureAnchor(
            tokenIndex: gridModeAnchorTokenIndex() ?? 0,
            preferredContentPoint: gridModeVisualFocalPoint()
        )
    }

    private func gridModeVisualFocalPoint() -> CGPoint {
        let focalPoint = layoutOperations?.currentFocalPoint() ?? .zero
        guard let layout = browserCollectionLayout?.browserLayout else {
            return focalPoint
        }
        return visualGeometry(for: layout)?.mirroredPoint(focalPoint)
            ?? focalPoint
    }

    private func gridModeAnchorTokenIndex() -> Int? {
        if let resolvedIndex = layoutOperations?.currentAnchorTokenIndex() {
            return resolvedIndex
        }
        guard let state = currentState?() else { return nil }
        return state.forcedFocusedTokenIndex
            ?? state.focusedTokenIndex
            ?? state.browseSnapshot?.initialTokenIndex
    }

    private var canonicalContentOffsetX: CGFloat {
        -(collectionView?.adjustedContentInset.left ?? 0)
    }

    private func clampedContentOffset(_ contentOffset: CGPoint) -> CGPoint {
        CGPoint(
            x: canonicalContentOffsetX,
            y: clampedVerticalContentOffsetY(contentOffset.y)
        )
    }

    private func clampedVerticalContentOffsetY(
        _ contentOffsetY: CGFloat
    ) -> CGFloat {
        guard let collectionView else { return contentOffsetY }
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        return min(max(contentOffsetY, minimumOffsetY), maximumOffsetY)
    }

    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === pinchRecognizer else { return true }
        guard !isInvalidated,
              let state = currentState?(),
              let collectionView,
              state.isActive,
              state.hasFinishedInitialPositioning,
              state.browseSnapshot?.itemCount ?? 0 > 0,
              collectionView.bounds.width > 0,
              collectionView.bounds.height > 0,
              !state.hasPreparedTransition,
              transitionRuntime.canBeginPinch else {
            return false
        }
        return transitionRuntime.phase == .settling
            || !state.isApplyingPosition
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
            UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === pinchRecognizer
            && otherGestureRecognizer === collectionView?.panGestureRecognizer
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard !isInvalidated else { return }
        switch recognizer.state {
        case .began:
            cancelGeometryPrewarming()
            let wasSettling = transitionRuntime.phase == .settling
            let frame = pinchFrame(recognizer)
            lastPinchViewLocation = frame.viewLocation
            let initialMode = gridMode
            let ratios = makeGridModeRatios(fromMode: initialMode)
            let output = transitionRuntime.beginPinch(
                frame,
                currentMode: initialMode,
                at: frameDriver.now,
                ratioProvider: { fromMode in
                    fromMode == initialMode ? ratios : []
                }
            )
            let stopsSettle = output.effects.contains {
                $0 == .stopDisplayLink
            }
            if wasSettling, stopsSettle {
                settlingReanchorCount += 1
                renderer?.reanchorSettlingRendering(
                    at: frame.viewLocation
                )
            }
            applyRuntimeOutput(
                output,
                transitionAnchor: pinchAnchorProvider(
                    viewLocation: frame.viewLocation
                )
            )
            if transitionRuntime.phase == .idle {
                scheduleGeometryPrewarmIfPossible()
            }

        case .changed:
            let frame = pinchFrame(recognizer)
            lastPinchViewLocation = frame.viewLocation
            transitionRuntime.stagePinch(frame)
            reconcileFrameDriving()

        case .ended:
            let timestamp = frameDriver.now
            finishPinch(transitionRuntime.endPinch(
                scale: recognizer.scale,
                reduceMotion: UIAccessibility.isReduceMotionEnabled,
                timestamp: timestamp
            ))

        case .cancelled, .failed:
            finishPinch(transitionRuntime.cancelPinch(
                reduceMotion: UIAccessibility.isReduceMotionEnabled,
                at: frameDriver.now
            ))

        default:
            break
        }
    }

    private func finishPinch(
        _ output: PlayerBrowserGridTransitionRuntime.Output
    ) {
        let transitionAnchor = lastPinchViewLocation.map {
            pinchAnchorProvider(viewLocation: $0)
        }
        defer { lastPinchViewLocation = nil }
        applyRuntimeOutput(
            output,
            transitionAnchor: transitionAnchor
        )
        if transitionRuntime.phase == .idle {
            scheduleGeometryPrewarmIfPossible()
        }
    }

    private func advanceFrame(to frame: GridTransitionFrame) {
        guard !isInvalidated else { return }
        renderer?.beginTransitionFrame(frame)
        let signpostState = gridModeCoordinatorSignposter.beginInterval(
            "TransitionFrameWork"
        )
        let output = transitionRuntime.advanceFrame(to: frame.timestamp)
        applyRuntimeOutput(
            output,
            transitionAnchor: nil,
            transitionFrame: frame
        )
        let drainResult = renderer?.finishTransitionFrame(frame)
        gridModeCoordinatorSignposter.endInterval(
            "TransitionFrameWork",
            signpostState
        )
        if drainResult != nil, frameDriver.now > frame.targetTimestamp {
            gridModeCoordinatorSignposter.emitEvent("TransitionDeadlineMiss")
        }
    }

    private var hasInterruptibleSettle: Bool {
        transitionRuntime.phase == .settling
            && transitionRuntime.canBeginPinch
            && effectDrainDepth == 0
    }

    private func interruptSettleForDragIfNeeded() {
        guard !finalizeInterruptibleSettle(),
              transitionRuntime.phase == .settling,
              !transitionRuntime.canBeginPinch else {
            return
        }
        let output = transitionRuntime.handle(
            .interrupt,
            at: frameDriver.now
        )
        applyRuntimeOutput(output, transitionAnchor: nil)
    }

    private func resolveScrollObservedDuringSettle(
        _ scrollView: UIScrollView
    ) -> Bool {
        guard hasInterruptibleSettle else { return false }
        let observedContentOffsetY = scrollView.contentOffset.y
        let settleContentOffsetY = settleContentOffsetY
            ?? scrollCoordinator?.lastScrollOffsetY
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
        return resumeObservedSettleOffset(
            settleContentOffsetY: settleContentOffsetY,
            observedDeltaY: observedDeltaY
        )
    }

    private func resumeObservedSettleOffset(
        settleContentOffsetY: CGFloat,
        observedDeltaY: CGFloat
    ) -> Bool {
        guard let collectionView, let scrollCoordinator else { return false }
        contentOffsetRestorationDepth += 1
        defer { contentOffsetRestorationDepth -= 1 }
        collectionView.setContentOffsetWithoutResolution(CGPoint(
            x: canonicalContentOffsetX,
            y: settleContentOffsetY
        ))
        collectionView.layoutIfNeeded()
        interruptInteractionIfNeeded()
        guard transitionRuntime.phase == .idle else {
            scrollCoordinator.lastScrollOffsetY = collectionView.contentOffset.y
            return false
        }
        removeTransitionCover()
        let committedContentOffsetY = collectionView.contentOffset.y
        scrollCoordinator.lastScrollOffsetY = committedContentOffsetY
        let resumedContentOffset = CGPoint(
            x: canonicalContentOffsetX,
            y: clampedVerticalContentOffsetY(
                committedContentOffsetY + observedDeltaY
            )
        )
        let resumedDeltaY = resumedContentOffset.y - committedContentOffsetY
        if abs(resumedDeltaY) > Self.boundaryEpsilon {
            scrollCoordinator.setPrefetchDirection(
                resumedDeltaY > 0 ? .forward : .backward
            )
        }
        if resumedContentOffset != collectionView.contentOffset {
            collectionView.setContentOffsetWithoutResolution(
                resumedContentOffset
            )
        }
        return true
    }

    @discardableResult
    private func applyRuntimeOutput(
        _ output: PlayerBrowserGridTransitionRuntime.Output,
        transitionAnchor: (() -> GridModeGestureAnchor?)?,
        transitionFrame: GridTransitionFrame? = nil
    ) -> Bool {
        if transitionRuntime.needsFrames || coverRenderer.hasCover
            || output.effects.contains(where: { effect in
                switch effect {
                case .installPlane, .renderZoom, .renderSettle,
                     .renderInteractionFade, .coverPlaneChange, .commitPlane:
                    true
                default:
                    false
                }
        }) {
            renderer?.setTransitionFrameDriving(true)
        }
        let synchronousTransitionFrame: GridTransitionFrame?
        if transitionFrame == nil,
           output.effects.contains(where: { effect in
               if case .commitPlane = effect { return true }
               return false
           }) {
            let timestamp = frameDriver.now
            synchronousTransitionFrame = GridTransitionFrame(
                timestamp: timestamp,
                targetTimestamp: timestamp
                    + GridTransitionFrame.maximumDuration
            )
        } else {
            synchronousTransitionFrame = nil
        }
        let beganSynchronousTransitionFrame = synchronousTransitionFrame.map {
            renderer?.beginTransitionFrame($0) == true
        } ?? false
        defer {
            if beganSynchronousTransitionFrame,
               let synchronousTransitionFrame {
                _ = renderer?.finishTransitionFrame(
                    synchronousTransitionFrame
                )
            }
        }
        let effectTransitionFrame = transitionFrame
            ?? synchronousTransitionFrame
        if let expiredCoverID = output.expiredCoverID {
            coverRenderer.remove(generation: expiredCoverID)
        }
        let resolvedTransitionAnchor = output.appliedPinchFrame.map { frame in
            pinchAnchorProvider(viewLocation: frame.viewLocation)
        } ?? transitionAnchor
        let result = drainInteractionEffects(
            output.effects,
            transitionAnchor: resolvedTransitionAnchor,
            transitionFrame: effectTransitionFrame
        )
        let requestsGestureMaterializationBurst = output.effects.contains {
            effect in
            switch effect {
            case .renderZoom, .renderSettle:
                true
            default:
                false
            }
        }
        if transitionRuntime.phase != .interacting {
            renderer?.cancelGestureMaterializationBurst()
        } else if requestsGestureMaterializationBurst {
            renderer?.requestGestureMaterializationBurst()
        }
        if result.needsVisibleCellQualityReconciliation {
            browserEffects?.reloadVisibleCells()
        }
        reconcileFrameDriving()
        return result.succeeded
    }

    private func drainInteractionEffects(
        _ initialEffects: [PlayerBrowserGridInteractionCoordinator.Effect],
        transitionAnchor: (() -> GridModeGestureAnchor?)?,
        transitionFrame: GridTransitionFrame?
    ) -> (
        succeeded: Bool,
        needsVisibleCellQualityReconciliation: Bool
    ) {
        effectDrainDepth += 1
        defer { effectDrainDepth -= 1 }
        var pendingEffects = initialEffects
        var needsVisibleCellQualityReconciliation = false
        var rendererRecoverySucceeded = true

        func reconcileVisibleCellsIfNeeded() {
            guard needsVisibleCellQualityReconciliation else { return }
            needsVisibleCellQualityReconciliation = false
            browserEffects?.reloadVisibleCells()
        }

        func enqueueRendererFailureRecovery() {
            let output = transitionRuntime.handle(
                .rendererFailed,
                at: frameDriver.now
            )
            if let expiredCoverID = output.expiredCoverID {
                coverRenderer.remove(generation: expiredCoverID)
            }
            let effects = output.effects
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
                removeTransitionCover()
                applyInteractionBegan(transitionAnchor: transitionAnchor)

            case .coverPlaneChange:
                let timestamp = frameDriver.now
                if transitionRuntime.planeChangeNeedsVisualCover(
                    at: timestamp
                ), let cover = installTransitionCover(at: timestamp) {
                    startTransitionCoverFade(cover, at: frameDriver.now)
                }

            case let .installPlane(plane):
                guard let context = makePlaneRequest(plane: plane),
                      renderer?.installPlane(context) == true else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )

            case let .renderZoom(planeId, scale, panDeltaY):
                guard renderZoom(
                    planeId: planeId,
                    scale: scale,
                    panDeltaY: panDeltaY
                ) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )

            case let .renderSettle(
                id,
                scale,
                settleProgress,
                presentationProgress,
                panDeltaY
            ):
                guard renderer?.renderSettle(
                    id: id,
                    scale: scale,
                    settleProgress: settleProgress,
                    presentationProgress: presentationProgress,
                    panDeltaY: panDeltaY
                ) == true else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )

            case let .renderInteractionFade(id, presentationProgress):
                guard renderer?.renderInteractionFade(
                    id: id,
                    presentationProgress: presentationProgress
                ) == true else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )

            case let .commitPlane(id, mode):
                guard commitPlaneGeometry(
                    id: id,
                    mode: mode,
                    transitionFrame: transitionFrame
                ) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )
                needsVisibleCellQualityReconciliation = true
                prependRendererSuccessEffects(to: &pendingEffects)

            case let .discardPlane(id):
                guard discardPlane(id: id) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )
                prependRendererSuccessEffects(to: &pendingEffects)

            case let .applyMode(mode):
                guard applyModeWithoutAnimation(
                    mode,
                    retainedTokenIndex: renderer?.renderSnapshot?
                        .gestureAnchor?.tokenIndex
                ) else {
                    enqueueRendererFailureRecovery()
                    continue effectLoop
                }
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )
                needsVisibleCellQualityReconciliation = true
                prependRendererSuccessEffects(to: &pendingEffects)

            case .resetRenderer:
                resetRenderer()
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )
                needsVisibleCellQualityReconciliation = true

            case .selectionHaptic:
                Haptic.selectionChanged()

            case .startDisplayLink, .stopDisplayLink,
                 .startInteractionFadeTicks, .stopInteractionFadeTicks:
                let output = transitionRuntime.acknowledgeTimingEffect(
                    effect,
                    at: frameDriver.now
                )
                if let expiredCoverID = output.expiredCoverID {
                    coverRenderer.remove(generation: expiredCoverID)
                }
                reconcileFrameDriving()
                pendingEffects.insert(contentsOf: output.effects, at: 0)

            case .reconcileMedia:
                imagePipeline?.resetThumbnailWindow()
                needsVisibleCellQualityReconciliation = true
                reconcileVisibleCellsIfNeeded()

            case let .finishInteraction(settlesPosition):
                reconcileVisibleCellsIfNeeded()
                applyInteractionFinished(settlesPosition: settlesPosition)
                transitionRuntime.recordRendererEffect(
                    effect,
                    at: frameDriver.now
                )
            }
        }
        reconcileSettleFrameDemand()
        return (
            rendererRecoverySucceeded,
            needsVisibleCellQualityReconciliation
        )
    }

    private func prependRendererSuccessEffects(
        to pendingEffects: inout [PlayerBrowserGridInteractionCoordinator.Effect]
    ) {
        let output = transitionRuntime.handle(
            .rendererSucceeded,
            at: frameDriver.now
        )
        if let expiredCoverID = output.expiredCoverID {
            coverRenderer.remove(generation: expiredCoverID)
        }
        pendingEffects.insert(contentsOf: output.effects, at: 0)
    }

    private func setScrollingSuspended(_ suspended: Bool) {
        guard let collectionView else { return }
        collectionView.isScrollEnabled = suspended
            ? false
            : scrollCoordinator?.isActive == true
    }

    private func applyInteractionBegan(
        transitionAnchor: (() -> GridModeGestureAnchor?)?
    ) {
        guard let renderer,
              let sourceLayout = browserCollectionLayout?.browserLayout,
              let collectionView,
              let scrollCoordinator,
              let browserEffects else {
            return
        }
        guard !renderer.isActive else {
            setScrollingSuspended(true)
            return
        }
        let wasCollectionViewPrefetchingEnabled =
            collectionView.isPrefetchingEnabled
        cancelGeometryPrewarming()
        scrollCoordinator.setApplyingPosition(true)
        collectionView.isPrefetchingEnabled = false
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(
            clampedContentOffset(collectionView.contentOffset),
            animated: false
        )
        browserEffects.endScrollMotionAndResetDragState()
        scrollCoordinator.cancelScheduledScrollUpdate()
        scrollCoordinator.cancelPendingFocusPublication(
            resetLastPublicationTime: false
        )
        setScrollingSuspended(true)
        collectionView.clipsToBounds = false
        destinationCache.removeAll(keepingCapacity: true)
        _ = renderer.begin(
            gestureAnchor: transitionAnchor?(),
            sourceLayout: sourceLayout,
            sourceImageDecodeVariant:
                MobilePlayerCollectionBrowserGridImageDecodeVariant.resolve(
                    for: sourceLayout,
                    displayScale: currentState?()
                        .currentLayoutDisplayScale ?? 3
            ),
            wasCollectionViewPrefetchingEnabled:
                wasCollectionViewPrefetchingEnabled
        )
    }

    private func applyInteractionFinished(settlesPosition: Bool) {
        transitionRuntime.discardPendingPinch()
        guard let collectionView,
              let scrollCoordinator,
              let imagePipeline else {
            return
        }
        guard let finishState = renderer?.finish(
            preservingCarryover: true
        ) else {
            removeTransitionCover()
            collectionView.clipsToBounds = true
            destinationCache.removeAll(keepingCapacity: false)
            scrollCoordinator.setApplyingPosition(false)
            collectionView.isPrefetchingEnabled = true
            setScrollingSuspended(false)
            imagePipeline.demoteVisibleImageLoadsIfNeeded()
            imagePipeline.resumeVisibleImageLoadsIfNeeded()
            if !settlesPosition {
                browserEffects?.prepareCurrentImageWindowIfPossible()
            }
            scheduleGeometryPrewarmIfPossible()
            return
        }
        let pannedContentOffsetY = finishState.pannedContentOffsetY.map {
            MobilePlayerBrowserGridTransition.clampedContentOffsetY(
                $0,
                contentHeight: browserCollectionLayout?.browserLayout?
                    .contentSize.height ?? 0,
                viewportHeight: viewportView?.bounds.height ?? 0
            )
        }
        collectionView.clipsToBounds = true
        destinationCache.removeAll(keepingCapacity: false)
        if let pannedContentOffsetY {
            collectionView.contentOffset.y = pannedContentOffsetY
        }
        collectionView.layoutIfNeeded()
        if finishState.clearsTransitionPlaceholderTones {
            visibleBrowserCells.forEach {
                guard !$0.keepsTransitionPlaceholderToneForPendingLoad else {
                    return
                }
                $0.setTransitionPlaceholderTone(false)
            }
        }
        scrollCoordinator.lastScrollOffsetY = collectionView.contentOffset.y
        scrollCoordinator.setApplyingPosition(false)
        collectionView.isPrefetchingEnabled =
            finishState.wasCollectionViewPrefetchingEnabled
        setScrollingSuspended(false)
        if settlesPosition {
            browserEffects?.settleCurrentPosition()
        } else {
            browserEffects?.prepareCurrentImageWindowIfPossible()
        }
        imagePipeline.demoteVisibleImageLoadsIfNeeded()
        imagePipeline.resumeVisibleImageLoadsIfNeeded()
        scheduleGeometryPrewarmIfPossible()
    }

    private func renderZoom(
        planeId: UUID?,
        scale: CGFloat,
        panDeltaY: CGFloat
    ) -> Bool {
        guard let sourceLayout = browserCollectionLayout?.browserLayout else {
            return false
        }
        return renderer?.renderZoom(
            planeID: planeId,
            scale: scale,
            panDeltaY: panDeltaY,
            sourceLayout: sourceLayout
        ) == true
    }

    private func commitPlaneGeometry(
        id: UUID,
        mode: MobileCollectionBrowserGridMode,
        transitionFrame: GridTransitionFrame?
    ) -> Bool {
        guard let renderer,
              let collectionView,
              let layoutOperations,
              let browserEffects,
              let scrollCoordinator else {
            return false
        }
        let barrierFrame = transitionFrame ?? GridTransitionFrame(
            timestamp: frameDriver.now,
            targetTimestamp: frameDriver.now
                + GridTransitionFrame.maximumDuration
        )
        guard renderer.prepareForSnapshot(using: barrierFrame) != nil,
              let cover = installTransitionCover(at: frameDriver.now) else {
            return false
        }
        guard let preparation = renderer.prepareCommit(
            id: id,
            mode: mode,
            capturesFallbackSources: true
        ) else {
            removeTransitionCover(generation: cover.generation)
            return false
        }
        startTransitionCoverFade(cover, at: frameDriver.now)
        var completed = false
        defer {
            if !completed {
                renderer.abortCommit(preparation)
                removeTransitionCover(generation: cover.generation)
            }
        }
        let plane = preparation.planeRequest
        browserEffects.setLayoutAspectState(plane.layoutAspectState)
        transitionRuntime.beginFirstImageFade(at: frameDriver.now)
        let toLayout = plane.transitionLayout.toLayout
        layoutOperations.installCollectionLayout(toLayout)
        applyTransitionEndpoint(
            layout: toLayout,
            contentOffsetY: preparation.terminalContentOffsetY
        )
        guard renderer.completeCommit(preparation) else { return false }
        completed = true
        transitionRuntime.updateCoverContentOffset(
            generation: cover.generation,
            contentOffset: collectionView.contentOffset
        )
        coverRenderer.updateCapturedContentOffset(
            collectionView.contentOffset,
            generation: cover.generation
        )
        layoutOperations.retainFocusedTokenIndex(plane.anchorTokenIndex)
        scrollCoordinator.focusedTokenIndex = plane.anchorTokenIndex
        return true
    }

    private func discardPlane(id: UUID) -> Bool {
        guard let sourceLayout = browserCollectionLayout?.browserLayout else {
            return false
        }
        return renderer?.discardPlane(
            id: id,
            sourceLayout: sourceLayout
        ) == true
    }

    private func resetRenderer() {
        removeTransitionCover()
        let anchoredContentOffsetY = renderer?.reset()
        guard let layout = browserCollectionLayout?.browserLayout,
              let collectionView else {
            return
        }
        applyTransitionEndpoint(
            layout: layout,
            contentOffsetY: anchoredContentOffsetY
                ?? collectionView.contentOffset.y
        )
    }

    private func applyModeWithoutAnimation(
        _ mode: MobileCollectionBrowserGridMode,
        retainedTokenIndex: Int?
    ) -> Bool {
        guard let renderer,
              renderer.isActive,
              let state = currentState?(),
              let browseSnapshot = state.browseSnapshot,
              let collectionView,
              let layoutOperations,
              let browserEffects,
              let scrollCoordinator else {
            return false
        }
        let tokenIndex = retainedTokenIndex
            ?? gridModeAnchorTokenIndex()
            ?? browseSnapshot.initialTokenIndex
        guard let destination = makeDestination(
            mode: mode,
            anchorTokenIndex: tokenIndex
        ), destination.layout.itemFrame(at: tokenIndex) != nil else {
            return false
        }
        guard let preparation = renderer.prepareDirectCommit() else {
            return false
        }
        var completed = false
        defer {
            if !completed {
                renderer.abortDirectCommit(preparation)
            }
        }
        browserEffects.setLayoutAspectState(destination.layoutAspectState)
        layoutOperations.installCollectionLayout(destination.layout)
        layoutOperations.centerContent(tokenIndex)
        guard renderer.completeDirectCommit(preparation) else {
            return false
        }
        completed = true
        renderer.updateGestureAnchor(nil)
        layoutOperations.retainFocusedTokenIndex(tokenIndex)
        scrollCoordinator.focusedTokenIndex = tokenIndex
        scrollCoordinator.lastScrollOffsetY = collectionView.contentOffset.y
        collectionView.layoutIfNeeded()
        visibleBrowserCells.forEach {
            $0.setTransitionPlaceholderTone(false)
        }
        return true
    }

    private func applyTransitionEndpoint(
        layout: MobilePlayerBrowserLayout,
        contentOffsetY: CGFloat
    ) {
        guard let collectionView, let scrollCoordinator else { return }
        let contentOffsetY = MobilePlayerBrowserGridTransition
            .clampedContentOffsetY(
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
        scrollCoordinator.lastScrollOffsetY = collectionView.contentOffset.y
    }

    private var visibleBrowserCells: [MobilePlayerCollectionBrowserCell] {
        collectionView?.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        } ?? []
    }

    private func captureVisibleCarryoverSources(
        anchorTokenIndex: Int?
    ) -> [MobilePlayerBrowserGridCarryoverSource] {
        guard let collectionView, let viewportView else { return [] }
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
            in: viewportView
        )
    }

    private func installCarryoverContent(
        sources: [MobilePlayerBrowserGridCarryoverSource],
        anchorTokenIndex: Int? = nil
    ) {
        guard let collectionView,
              let viewportView,
              let effects = browserEffects else {
            return
        }
        _ = MobilePlayerCollectionBrowserTransitionSupport.installCarryover(
            sources: sources,
            in: collectionView,
            viewportView: viewportView,
            anchorItemIndex: anchorTokenIndex
                ?? currentState?().focusedTokenIndex,
            hasImageSources: { tokenIndex in
                effects.browseImageSources(tokenIndex) != nil
            }
        )
    }

    private func installTransitionCover(
        at timestamp: TimeInterval
    ) -> PlayerBrowserGridTransitionRuntime.Cover? {
        guard !isInvalidated,
              let viewportView,
              let collectionView else {
            return nil
        }
        let cover = transitionRuntime.installCover(
            contentOffset: collectionView.contentOffset,
            at: timestamp
        )
        guard coverRenderer.install(
            generation: cover.generation,
            viewportView: viewportView,
            collectionView: collectionView
        ) else {
            transitionRuntime.removeCover(generation: cover.generation)
            coverRenderer.removeAll()
            reconcileFrameDriving()
            return nil
        }
        reconcileFrameDriving()
        return cover
    }

    private func startTransitionCoverFade(
        _ cover: PlayerBrowserGridTransitionRuntime.Cover,
        at timestamp: TimeInterval
    ) {
        guard !isInvalidated,
              coverRenderer.startFade(generation: cover.generation) else {
            removeTransitionCover(generation: cover.generation)
            return
        }
        transitionRuntime.beginCoverFade(
            generation: cover.generation,
            at: timestamp
        )
        reconcileFrameDriving()
    }

    private func removeTransitionCover(
        generation: PlayerBrowserGridTransitionRuntime.Cover.Generation? = nil
    ) {
        let removedGeneration = transitionRuntime.removeCover(
            generation: generation
        )
        if let removedGeneration {
            coverRenderer.remove(generation: removedGeneration)
        } else if generation == nil {
            coverRenderer.removeAll()
        }
        reconcileFrameDriving()
    }

    private func startSettleFrameDemand() {
        guard !isInvalidated, let collectionView else { return }
        if settleContentOffsetY == nil {
            settleContentOffsetY = collectionView.contentOffset.y
        }
        if settlePanMaximumNumberOfTouches == nil {
            let panGestureRecognizer = collectionView.panGestureRecognizer
            settlePanMaximumNumberOfTouches = panGestureRecognizer
                .maximumNumberOfTouches
            panGestureRecognizer.maximumNumberOfTouches = 1
        }
        setScrollingSuspended(false)
    }

    private func stopSettleFrameDemand() {
        settleContentOffsetY = nil
        if let collectionView,
           let maximumNumberOfTouches = settlePanMaximumNumberOfTouches {
            collectionView.panGestureRecognizer.maximumNumberOfTouches =
                maximumNumberOfTouches
        }
        settlePanMaximumNumberOfTouches = nil
    }

    private func reconcileFrameDriving() {
        guard !isInvalidated else {
            frameDriver.stop()
            stopSettleFrameDemand()
            return
        }
        reconcileSettleFrameDemand()
        let shouldExternallyDriveRenderer = transitionRuntime.needsFrames
            || coverRenderer.hasCover
        renderer?.setTransitionFrameDriving(shouldExternallyDriveRenderer)
        if shouldExternallyDriveRenderer {
            guard !frameDriver.isRunning else { return }
            frameDriver.start { [weak self] frame in
                self?.advanceFrame(to: frame)
            }
        } else {
            frameDriver.stop()
        }
    }

    private func reconcileSettleFrameDemand() {
        if transitionRuntime.needsSettleFrames {
            startSettleFrameDemand()
        } else {
            stopSettleFrameDemand()
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        geometryPrewarmUpdate?.invalidate()
        geometryPrewarmPlan = nil
        frameDriver.invalidate()
        stopSettleFrameDemand()
        transitionRuntime.invalidate()
        coverRenderer.removeAll()
        let finishState = renderer?.finish(preservingCarryover: false)
        if let collectionView {
            collectionView.clipsToBounds = true
            if let pannedContentOffsetY = finishState?.pannedContentOffsetY {
                collectionView.contentOffset.y =
                    clampedVerticalContentOffsetY(pannedContentOffsetY)
            }
            collectionView.layoutIfNeeded()
            if finishState?.clearsTransitionPlaceholderTones == true {
                visibleBrowserCells.forEach {
                    guard !$0.keepsTransitionPlaceholderToneForPendingLoad else {
                        return
                    }
                    $0.setTransitionPlaceholderTone(false)
                }
            }
            if let wasPrefetchingEnabled =
                finishState?.wasCollectionViewPrefetchingEnabled {
                collectionView.isPrefetchingEnabled = wasPrefetchingEnabled
            }
        }
        scrollCoordinator?.lastScrollOffsetY = collectionView?.contentOffset.y
        scrollCoordinator?.setApplyingPosition(false)
        setScrollingSuspended(false)
        imagePipeline?.demoteVisibleImageLoadsIfNeeded()
        imagePipeline?.resumeVisibleImageLoadsIfNeeded()
        effectDrainDepth = 0
        contentOffsetRestorationDepth = 0
        destinationCache.removeAll(keepingCapacity: false)
        lastPinchViewLocation = nil
        pinchRecognizer?.delegate = nil
        if let pinchRecognizer {
            pinchRecognizer.view?.removeGestureRecognizer(pinchRecognizer)
        }
        pinchRecognizer = nil
        currentState = nil
        layoutOperations = nil
        browserEffects = nil
    }

    private func menuTitle(
        for mode: MobileCollectionBrowserGridMode
    ) -> String {
        switch mode {
        case .large:
            Strings.largeGrid
        case .threeColumns:
            Strings.threeColumns
        case .fiveColumns:
            Strings.fiveColumns
        case .nineColumns:
            Strings.nineColumns
        }
    }

    private func menuSystemImageName(
        for mode: MobileCollectionBrowserGridMode
    ) -> String {
        switch mode {
        case .large:
            "rectangle.grid.1x2"
        case .threeColumns:
            "square.grid.3x2"
        case .fiveColumns:
            "square.grid.4x3.fill"
        case .nineColumns:
            "square.grid.3x3.fill"
        }
    }
}
