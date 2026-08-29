// ∅ 2026 lil org

import QuartzCore
import UIKit

struct MobilePlayerCollectionBrowserLayoutAspectState {
    let aspectProfile: MobilePlayerBrowserAspectProfile
    let fallbackSpec: PlayerMediaPlaceholderSpec
}

struct GridModeGestureAnchor {
    let tokenIndex: Int
    let viewportPoint: CGPoint
    let relativeItemPoint: CGPoint
    let baseContentOffsetY: CGFloat
}

enum GridModeRebaseClock {
    case drift
    case destinationEndpoint
    case sourceEndpoint(installationScale: CGFloat)
}

struct GridModeRebase {
    let transform: PlayerBrowserGridCrossfadePlaneRebase
    let clock: GridModeRebaseClock
    var progress: CGFloat

    mutating func applying(
        to baseTransform: CGAffineTransform,
        scale: CGFloat,
        driftProgress: CGFloat,
        settleProgress: CGFloat
    ) -> CGAffineTransform {
        let appliedProgress: CGFloat
        switch clock {
        case .drift:
            appliedProgress = driftProgress
        case .destinationEndpoint:
            appliedProgress = PlayerBrowserGridCrossfadePlaneRebase
                .endpointClockProgress(
                    previousProgress: progress,
                    driftProgress: driftProgress,
                    settleProgress: settleProgress
                )
            progress = appliedProgress
        case let .sourceEndpoint(installationScale):
            appliedProgress = PlayerBrowserGridCrossfadePlaneRebase
                .sourceEndpointClockProgress(
                    previousProgress: progress,
                    scale: scale,
                    installationScale: installationScale
                )
            progress = appliedProgress
        }
        return transform.applying(to: baseTransform, progress: appliedProgress)
    }
}

struct GridModePlaneRequest {
    let id: UUID
    let toMode: MobileCollectionBrowserGridMode
    let layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    let anchorTokenIndex: Int
    let transitionLayout: MobilePlayerBrowserGridTransition
    let crossfade: PlayerBrowserGridCrossfade
    let latticeMap: MobilePlayerBrowserGridLatticeMap
}

struct GridModePlaneContext {
    let request: GridModePlaneRequest
    var rebase: GridModeRebase?

    var id: UUID { request.id }
    var toMode: MobileCollectionBrowserGridMode { request.toMode }
    var layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState {
        request.layoutAspectState
    }
    var anchorTokenIndex: Int { request.anchorTokenIndex }
    var transitionLayout: MobilePlayerBrowserGridTransition {
        request.transitionLayout
    }
    var crossfade: PlayerBrowserGridCrossfade { request.crossfade }
    var latticeMap: MobilePlayerBrowserGridLatticeMap { request.latticeMap }

    func terminalOutgoingPlane(
        panDeltaY: CGFloat
    ) -> PlayerBrowserGridCrossfadePlane {
        crossfade.outgoingPlane(
            scale: transitionLayout.itemWidthRatio,
            panDeltaY: panDeltaY
        )
    }
}

@MainActor
final class MobilePlayerCollectionBrowserGridRenderer: NSObject {
    private typealias CarryoverRetention = GridMaterializer.CarryoverRetention
    typealias CellConfiguration = GridMaterializer.CellConfiguration
    typealias ContentAccess = GridMaterializer.ContentAccess
    typealias ImageAccess = GridMaterializer.ImageAccess

    struct RenderSnapshot {
        let gestureAnchor: GridModeGestureAnchor?
        let visualAnchor: CGPoint?
    }

    struct CommitPreparation {
        let id: UUID
        let planeRequest: GridModePlaneRequest
        let terminalContentOffsetY: CGFloat
        let carryoverSourceCount: Int
    }

    struct DirectCommitPreparation {
        let id: UUID
    }

    struct FinishState {
        let wasCollectionViewPrefetchingEnabled: Bool
        let pannedContentOffsetY: CGFloat?
        let clearsTransitionPlaceholderTones: Bool
    }

    enum Lifecycle {
        case idle
        case active(Session)
        case committing(CommitState)
    }

    enum LifecycleName: Equatable {
        case idle
        case active
        case committing
    }

    typealias MaterializationDrainResult = GridMaterializer.DrainResult
    typealias MaterializationKind = GridMaterializer.MaterializationKind
    typealias MaterializationPriority = GridMaterializer.MaterializationPriority
    typealias MaterializationJob = GridMaterializer.MaterializationJob
    typealias MaterializationQueue = GridMaterializer.MaterializationQueue
    typealias Session = GridRenderSession

    final class CommitState {
        let id = UUID()
        let session: Session
        fileprivate let plane: GridModePlaneContext?
        let sources: [MobilePlayerBrowserGridCarryoverSource]
        let fallbackSourceItemByDestinationItem: [Int: Int]
        fileprivate(set) var isComplete = false

        fileprivate init(
            session: Session,
            plane: GridModePlaneContext?,
            sources: [MobilePlayerBrowserGridCarryoverSource],
            fallbackSourceItemByDestinationItem: [Int: Int]
        ) {
            self.session = session
            self.plane = plane
            self.sources = sources
            self.fallbackSourceItemByDestinationItem =
                fallbackSourceItemByDestinationItem
        }
    }

    typealias GridModeTransitionImageLoad =
        GridMaterializer.GridModeTransitionImageLoad
    typealias GridModeTransitionImageCompletion =
        GridMaterializer.GridModeTransitionImageCompletion

    typealias PromotionRepresentationKey =
        GridMaterializer.PromotionRepresentationKey
    typealias PendingDetailRepresentationKey =
        GridMaterializer.PendingDetailRepresentationKey

    typealias GridModeCellFrameCorrection =
        GridPlaneRenderer.GridModeCellFrameCorrection
    typealias GridModeCellFrameCorrectionGeometry =
        GridPlaneRenderer.GridModeCellFrameCorrectionGeometry
    typealias PhantomShapeOccupantKey =
        GridPlaneRenderer.PhantomShapeOccupantKey
    typealias PhantomShapeFrameCompensation =
        GridPlaneRenderer.PhantomShapeFrameCompensation
    typealias PhantomShapeView = GridPlaneRenderer.PhantomShapeView
    typealias PhantomShapePathRenderer =
        GridPlaneRenderer.PhantomShapePathRenderer

    private let materializer: GridMaterializer
    private(set) var lifecycle: Lifecycle = .idle

    private var collectionView: MobilePlayerCollectionBrowserCollectionView? {
        materializer.collectionView
    }

    private var viewportView: UIView? {
        materializer.viewportView
    }

    var destinationPlanBuildCount: Int {
        materializer.destinationPlanBuildCount
    }

    var sourceCoverageBuildCount: Int {
        materializer.sourceCoverageBuildCount
    }

    var phantomShapeStructureBuildCount: Int {
        materializer.phantomShapeStructureBuildCount
    }

    var phantomShapeMaskBuildCount: Int {
        materializer.phantomShapeMaskBuildCount
    }

    var foregroundEligibilityReconciliationCount: Int {
        materializer.foregroundEligibilityReconciliationCount
    }

    init(
        collectionView: MobilePlayerCollectionBrowserCollectionView,
        viewportView: UIView,
        contentAccess: ContentAccess,
        imageAccess: ImageAccess = .live,
        clock: @escaping () -> CFTimeInterval = CACurrentMediaTime
    ) {
        self.materializer = GridMaterializer(
            collectionView: collectionView,
            viewportView: viewportView,
            contentAccess: contentAccess,
            imageAccess: imageAccess,
            clock: clock
        )
        super.init()
    }

    var isActive: Bool {
        if case .idle = lifecycle { return false }
        return true
    }

    var lifecycleName: LifecycleName {
        switch lifecycle {
        case .idle:
            return .idle
        case .active:
            return .active
        case .committing:
            return .committing
        }
    }

    var planeChangeNeedsVisualCover: Bool {
        guard case let .active(session) = lifecycle else { return false }
        return session.lastContentFadeAlpha > 0
            || session.contentFadeAnimationMayBeActive
    }

    var pendingMaterializationWorkCount: Int {
        materializer.pendingWorkCount
    }

    var pendingDetailMaterializationWorkCount: Int {
        materializer.pendingDetailWorkCount
    }

    var pendingDetailMaterializationRepresentationIDs:
        Set<ObjectIdentifier> {
        materializer.pendingDetailRepresentationIDs
    }

    var pendingDetailMaterializationRepresentationKeys:
        Set<PendingDetailRepresentationKey> {
        materializer.pendingDetailRepresentationKeys
    }

    var pendingVisibleDetailMaterializationRepresentationIDs:
        Set<ObjectIdentifier> {
        materializer.pendingVisibleDetailRepresentationIDs
    }

    var pendingPromotionRepresentationKeys:
        Set<PromotionRepresentationKey> {
        materializer.pendingPromotionRepresentationKeys
    }

    var pendingTransitionImageCompletionWorkCount: Int {
        materializer.pendingTransitionImageCompletionWorkCount
    }

    var pendingVisibleTransitionImageCompletionWorkCount: Int {
        materializer.pendingVisibleTransitionImageCompletionWorkCount
    }

    var transitionWorkQueueFilterPassCount: UInt {
        materializer.transitionWorkQueueFilterPassCount
    }

    var anchorTokenIndex: Int? {
        currentSession?.gestureAnchor?.tokenIndex
            ?? currentSession?.plane?.anchorTokenIndex
    }

    var renderSnapshot: RenderSnapshot? {
        guard let session = currentSession else { return nil }
        return RenderSnapshot(
            gestureAnchor: session.gestureAnchor,
            visualAnchor: session.visualAnchor
        )
    }

    var managedCells: [MobilePlayerCollectionBrowserCell] {
        materializer.managedCells(session: currentSession)
    }

    var phantomShapeMaskedFrames: [CGRect] {
        materializer.phantomShapeMaskedFrames(session: currentSession)
    }

    var viewportRenderCells: [MobilePlayerCollectionBrowserCell] {
        materializer.viewportRenderCells(session: currentSession)
    }

    private var currentSession: Session? {
        switch lifecycle {
        case .idle:
            return nil
        case let .active(session):
            return session
        case let .committing(commit):
            return commit.session
        }
    }

    @discardableResult
    func begin(
        gestureAnchor: GridModeGestureAnchor?,
        sourceLayout: MobilePlayerBrowserLayout,
        wasCollectionViewPrefetchingEnabled: Bool
    ) -> Bool {
        guard case .idle = lifecycle else { return false }
        let session = Session(
            gestureAnchor: gestureAnchor,
            sourceLayout: sourceLayout,
            wasCollectionViewPrefetchingEnabled:
                wasCollectionViewPrefetchingEnabled
        )
        lifecycle = .active(session)
        materializer.activate(session: session)
        if let collectionView {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath)
                    as? MobilePlayerCollectionBrowserCell else {
                    continue
                }
                materializer.registerSourceRepresentation(
                    session: session,
                    cell: cell,
                    itemIndex: indexPath.item
                )
            }
        }
        return true
    }

    func updateGestureAnchor(_ gestureAnchor: GridModeGestureAnchor?) {
        currentSession?.gestureAnchor = gestureAnchor
    }

    func requestGestureMaterializationBurst() {
        materializer.requestGestureMaterializationBurst()
    }

    func cancelGestureMaterializationBurst() {
        materializer.cancelGestureMaterializationBurst(
            session: currentSession
        )
    }

    @discardableResult
    func installPlane(_ request: GridModePlaneRequest) -> Bool {
        guard case let .active(session) = lifecycle,
              let plane = materializer.makePlaneContext(
                  request: request,
                  session: session
              ) else {
            return false
        }
        materializer.cancel()
        materializer.clearTransitionContent(
            session: session,
            carryoverRetention: .pendingBase
        )
        session.plane = plane
        session.zoomRebase = nil
        materializer.extendSourceCoverageIfNeeded(
            session: session,
            layout: request.transitionLayout.fromLayout,
            targetPlaneID: request.id,
            installsStructuralCoverage: false
        )
        materializer.classifyDetailedSourceRepresentations(
            session: session,
            plane: plane
        )
        materializer.refreshSourceCoverageAndMaterialization(
            session: session,
            plane: plane
        )
        return true
    }

    @discardableResult
    func renderZoom(
        planeID: UUID?,
        scale: CGFloat,
        panDeltaY: CGFloat,
        sourceLayout: MobilePlayerBrowserLayout
    ) -> Bool {
        guard case let .active(session) = lifecycle,
              collectionView != nil,
              viewportView != nil,
              scale.isFinite,
              scale > 0 else {
            return false
        }
        session.lastPanDeltaY = panDeltaY
        if let planeID {
            return renderSettle(
                id: planeID,
                scale: scale,
                settleProgress: 0,
                presentationProgress: 0,
                panDeltaY: panDeltaY
            )
        }
        guard materializer.applyZoomTransform(
            session: session,
            scale: scale,
            panDeltaY: panDeltaY,
            sourceLayout: sourceLayout
        ) else { return false }
        materializer.extendSourceCoverageIfNeeded(
            session: session,
            layout: sourceLayout
        )
        if let appliedScale = materializer.appliedPlaneScale() {
            materializer.applySourceSeamCompensations(
                session: session,
                naturalSpacing: sourceLayout.interItemSpacing,
                targetSpacing: sourceLayout.interItemSpacing,
                appliedScale: appliedScale
            )
            materializer.refreshPhantomShapeStructure(session: session)
        }
        materializer.enqueueViewportPromotions(session: session)
        materializer.applyContentFade(
            session: session,
            alpha: 0,
            animated: true
        )
        materializer.refreshPhantomShapeExclusionMask(session: session)
        return true
    }

    @discardableResult
    func renderSettle(
        id: UUID,
        scale: CGFloat,
        settleProgress: CGFloat,
        presentationProgress: CGFloat? = nil,
        panDeltaY: CGFloat
    ) -> Bool {
        guard case let .active(session) = lifecycle,
              scale.isFinite,
              scale > 0,
              var plane = session.plane,
              plane.id == id else {
            return false
        }
        session.lastPanDeltaY = panDeltaY
        session.lastRenderedScale = scale
        applyPlaneFrames(
            session: session,
            plane: &plane,
            scale: scale,
            settleProgress: settleProgress,
            presentationProgress: presentationProgress ?? settleProgress
        )
        session.plane = plane
        return true
    }

    @discardableResult
    func renderInteractionFade(
        id: UUID,
        presentationProgress: CGFloat
    ) -> Bool {
        guard case let .active(session) = lifecycle,
              session.plane?.id == id,
              presentationProgress.isFinite else {
            return false
        }
        let contentFadeAlpha = PlayerBrowserGridCrossfade.incomingContentAlpha(
            settleProgress: presentationProgress
        )
        materializer.applyContentFade(
            session: session,
            alpha: contentFadeAlpha,
            animated: false
        )
        return true
    }

    func installZoomRebase(
        currentTransform: CGAffineTransform,
        scale: CGFloat,
        panDeltaY: CGFloat,
        anchor: CGPoint,
        sourceLayout: MobilePlayerBrowserLayout
    ) {
        guard case let .active(session) = lifecycle else {
            currentSession?.zoomRebase = nil
            return
        }
        materializer.installZoomRebase(
            session: session,
            currentTransform: currentTransform,
            scale: scale,
            panDeltaY: panDeltaY,
            anchor: anchor,
            sourceLayout: sourceLayout
        )
    }

    func reanchorSettlingRendering(at screenPoint: CGPoint) {
        guard case let .active(session) = lifecycle else { return }
        materializer.reanchorSettlingRendering(
            session: session,
            at: screenPoint
        )
    }

    func prepareCommit(
        id: UUID,
        mode: MobileCollectionBrowserGridMode,
        capturesFallbackSources: Bool = false
    ) -> CommitPreparation? {
        guard case let .active(session) = lifecycle,
              let plane = session.plane,
              plane.id == id,
              plane.toMode == mode else {
            return nil
        }
        if session.sourceCoverageRefreshIsDirty {
            materializer.refreshDetailedSourceRepresentations(
                session: session,
                plane: plane
            )
        }
        var ineligibleFallbackSourceItems = Set<Int>()
        var fallbackSourceItemByDestinationItem = [Int: Int]()
        for sourceItem in materializer.prioritizedSourceItems(
            session.selectedSourceItems,
            session: session
        ) {
            if let destinationItem = materializer.destinationItem(
                    session: session,
                    sourceItem: sourceItem,
                    plane: plane
            ) {
                if fallbackSourceItemByDestinationItem[destinationItem] == nil {
                    fallbackSourceItemByDestinationItem[destinationItem] =
                        sourceItem
                }
            } else {
                ineligibleFallbackSourceItems.insert(sourceItem)
            }
        }
        let sources = materializer.captureVisibleCarryoverSources(
            session: session,
            anchorTokenIndex: plane.anchorTokenIndex,
            capturesFallbackSources: capturesFallbackSources,
            ineligibleFallbackSourceItems: ineligibleFallbackSourceItems
        )
        let terminalContentOffsetY = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        ).incomingContentOffsetY
        materializer.cancel()
        let commit = CommitState(
            session: session,
            plane: plane,
            sources: sources,
            fallbackSourceItemByDestinationItem:
                fallbackSourceItemByDestinationItem
        )
        lifecycle = .committing(commit)
        materializer.deactivate(session: session)
        session.plane = nil
        session.gestureAnchor = nil
        materializer.tearDownPlaneRendering(session: session)
        return CommitPreparation(
            id: commit.id,
            planeRequest: plane.request,
            terminalContentOffsetY: terminalContentOffsetY,
            carryoverSourceCount: sources.count
        )
    }

    @discardableResult
    func completeCommit(_ preparation: CommitPreparation) -> Bool {
        guard case let .committing(commit) = lifecycle,
              commit.id == preparation.id,
              !commit.isComplete,
              commit.plane?.id == preparation.planeRequest.id else {
            return false
        }
        guard let plane = commit.plane else { return false }
        materializer.installCarryoverContent(
            session: commit.session,
            plane: plane,
            sources: commit.sources,
            fallbackSourceItemByDestinationItem:
                commit.fallbackSourceItemByDestinationItem
        )
        commit.isComplete = true
        return true
    }

    func prepareDirectCommit() -> DirectCommitPreparation? {
        guard case let .active(session) = lifecycle else { return nil }
        materializer.cancel()
        let commit = CommitState(
            session: session,
            plane: nil,
            sources: [],
            fallbackSourceItemByDestinationItem: [:]
        )
        lifecycle = .committing(commit)
        materializer.deactivate(session: session)
        materializer.tearDownPlaneRendering(session: session)
        return DirectCommitPreparation(id: commit.id)
    }

    @discardableResult
    func completeDirectCommit(
        _ preparation: DirectCommitPreparation
    ) -> Bool {
        guard case let .committing(commit) = lifecycle,
              commit.id == preparation.id,
              !commit.isComplete,
              commit.plane == nil else {
            return false
        }
        commit.isComplete = true
        return true
    }

    func abortDirectCommit(_ preparation: DirectCommitPreparation? = nil) {
        guard case let .committing(commit) = lifecycle,
              commit.plane == nil,
              !commit.isComplete,
              preparation == nil || preparation?.id == commit.id else {
            return
        }
        lifecycle = .active(commit.session)
        materializer.activate(session: commit.session)
    }

    func abortCommit(_ preparation: CommitPreparation? = nil) {
        guard case let .committing(commit) = lifecycle,
              !commit.isComplete,
              preparation == nil || preparation?.id == commit.id else {
            return
        }
        materializer.cancel()
        materializer.tearDownPlaneRendering(session: commit.session)
        lifecycle = .active(commit.session)
        materializer.activate(session: commit.session)
    }

    @discardableResult
    func discardPlane(id: UUID, sourceLayout: MobilePlayerBrowserLayout) -> Bool {
        guard case let .active(session) = lifecycle else { return false }
        guard let plane = session.plane else { return true }
        guard plane.id == id, let collectionView else { return false }
        if let anchor = session.visualAnchor
            ?? session.gestureAnchor?.viewportPoint {
            installZoomRebase(
                currentTransform: collectionView.transform,
                scale: session.lastRenderedScale,
                panDeltaY: session.lastPanDeltaY,
                anchor: anchor,
                sourceLayout: sourceLayout
            )
        }
        materializer.cancel()
        session.sourceLayout = sourceLayout
        session.plane = nil
        materializer.clearTransitionContent(
            session: session,
            carryoverRetention: .pendingBase,
            installsDeferredBaseImages: true
        )
        return true
    }

    func reset() -> CGFloat? {
        guard let session = currentSession else { return nil }
        let anchoredContentOffsetY = session.gestureAnchor.map {
            $0.baseContentOffsetY - session.lastPanDeltaY
        }
        materializer.cancel()
        materializer.tearDownPlaneRendering(
            session: session,
            carryoverRetention: .pendingBase
        )
        return anchoredContentOffsetY
    }

    func finish(preservingCarryover: Bool) -> FinishState? {
        guard let session = currentSession else { return nil }
        let clearsTransitionPlaceholderTones = session.gestureAnchor != nil
            || materializer.hasTransitionPlaceholderTones
        let pannedContentOffsetY = session.gestureAnchor.map {
            $0.baseContentOffsetY - session.lastPanDeltaY
        }
        session.gestureAnchor = nil
        session.lastPanDeltaY = 0
        materializer.cancel()
        materializer.tearDownPlaneRendering(
            session: session,
            carryoverRetention: preservingCarryover ? .all : .none
        )
        materializer.releaseReusablePhantomCells(session: session)
        materializer.clearTransitionPlaceholderTones()
        lifecycle = .idle
        materializer.deactivate(session: session)
        return FinishState(
            wasCollectionViewPrefetchingEnabled:
                session.wasCollectionViewPrefetchingEnabled,
            pannedContentOffsetY: pannedContentOffsetY,
            clearsTransitionPlaceholderTones:
                clearsTransitionPlaceholderTones
        )
    }

    private func applyPlaneFrames(
        session: Session,
        plane: inout GridModePlaneContext,
        scale: CGFloat,
        settleProgress: CGFloat,
        presentationProgress: CGFloat
    ) {
        guard collectionView != nil, viewportView != nil else { return }
        let settleProgress = PlayerBrowserGridCrossfade.sanitizedProgress(
            settleProgress
        )
        let presentationProgress = PlayerBrowserGridCrossfade
            .sanitizedProgress(presentationProgress)
        let contentFadeAlpha = PlayerBrowserGridCrossfade.incomingContentAlpha(
            settleProgress: presentationProgress
        )
        let contentFadeWillSweepWithoutAnimation = presentationProgress > 0
            && (session.lastContentFadeAlpha != contentFadeAlpha
                || session.contentFadeAnimationMayBeActive)
        session.lastSettleProgress = settleProgress
        session.currentContentFadeTargetAlpha = contentFadeAlpha
        materializer.extendDestinationCoverageIfNeeded(
            session: session,
            plane: plane
        )
        guard materializer.applyPlaneTransform(
            session: session,
            plane: &plane,
            scale: scale,
            settleProgress: settleProgress
        ) else { return }
        materializer.extendSourceCoverageIfNeeded(
            session: session,
            layout: plane.transitionLayout.fromLayout,
            targetPlaneID: plane.id,
            installsStructuralCoverage: false
        )
        let appliedScale = materializer.appliedPlaneScale()
        materializer.reconcileCellFrameCorrectionClassifications(
            session: session,
            plane: plane,
            defersStableTransform: appliedScale != nil,
            defersPresentationUpdate: contentFadeWillSweepWithoutAnimation
        )
        if let appliedScale {
            materializer.applyCellFrameCorrections(
                session: session,
                plane: plane,
                appliedScale: appliedScale
            )
            materializer.applySeamCompensations(
                session: session,
                plane: plane,
                appliedScale: appliedScale
            )
        }
        session.deferredClassificationPaintRepresentationIDs.removeAll(
            keepingCapacity: true
        )
        materializer.enqueueViewportPromotions(session: session)
        materializer.reconcileForegroundDestinationEligibility(
            session: session,
            plane: plane
        )
        if presentationProgress > 0 {
            materializer.applyContentFade(
                session: session,
                alpha: contentFadeAlpha,
                animated: false
            )
        } else {
            materializer.applyContentFade(
                session: session,
                alpha: 0,
                animated: true
            )
        }
        if presentationProgress
            <= PlayerBrowserGridCrossfade.contentFadeRearmSettleProgress {
            materializer.rearmLockedFallbackRepresentationsWhileContentIsHidden(
                session: session,
                dropsUnpreparedGeometry: settleProgress == 0
            )
        }
        materializer.refreshPhantomShapeExclusionMask(session: session)
    }

    func didConfigureCell(
        _ cell: MobilePlayerCollectionBrowserCell,
        at indexPath: IndexPath
    ) {
        materializer.didConfigureCell(cell, at: indexPath)
    }

    func willDisplayCell(
        _ cell: UICollectionViewCell,
        at indexPath: IndexPath
    ) {
        materializer.willDisplayCell(cell, at: indexPath)
    }

    func didEndDisplayingCell(
        _ cell: UICollectionViewCell,
        at indexPath: IndexPath
    ) {
        materializer.didEndDisplayingCell(cell, at: indexPath)
    }

    @discardableResult
    func drainMaterializationWork(
        budgetOverride: (jobs: Int, time: CFTimeInterval)? = nil,
        frameDuration: CFTimeInterval? = nil
    ) -> MaterializationDrainResult {
        materializer.drain(
            budgetOverride: budgetOverride,
            frameDuration: frameDuration
        )
    }

}
