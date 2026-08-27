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

fileprivate struct GridModePlaneContext {
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
    private enum CarryoverRetention {
        case none
        case pendingBase
        case all
    }

    private enum SourcePresentationRole {
        case awaitingClassification
        case marginCoverage
        case destinationTransition
        case sourceFallback
    }

    private final class MaterializationDisplayLinkTarget: NSObject {
        weak var renderer: MobilePlayerCollectionBrowserGridRenderer?

        @MainActor @objc func tick(_ displayLink: CADisplayLink) {
            renderer?.handleMaterializationTick(displayLink)
        }
    }

    enum CellConfiguration: Equatable {
        case sourceOverscan
        case destinationPhantom(
            requiredImageQuality: CollectionBrowseImageQuality
        )

        var requiredImageQuality: CollectionBrowseImageQuality? {
            switch self {
            case .sourceOverscan:
                nil
            case let .destinationPhantom(requiredImageQuality):
                requiredImageQuality
            }
        }

        var imageLoadPolicy: MobilePlayerCollectionBrowserCell.ImageLoadPolicy {
            .cachedOnly
        }

        var allowsLocalLargeImageUpgrade: Bool {
            false
        }
    }

    struct ContentAccess {
        let configureCell: (
            MobilePlayerCollectionBrowserCell,
            IndexPath,
            CellConfiguration
        ) -> Void
        let contentIdentity: (Int) -> MobilePlayerBrowserContentIdentity?
        let imageSources: (Int) -> CollectionBrowseImageSources?
    }

    struct ImageAccess {
        typealias CachedImage = (
            descriptor: DownloadableMediaDescriptor,
            quality: CollectionBrowseImageQuality,
            image: UIImage
        )

        let cachedImage: (
            CollectionBrowseImageSources,
            CachedImageSelectionPolicy
        ) -> CachedImage?
        let loadImage: (
            DownloadableMediaDescriptor,
            @escaping (UIImage?) -> Void
        ) -> (() -> Void)?

        static let live = Self(
            cachedImage: { imageSources, selectionPolicy in
                imageSources.highestQualityCachedImage(
                    in: DownloadableMediaCache.shared,
                    selectionPolicy: selectionPolicy
                )
            },
            loadImage: { descriptor, completion in
                DownloadableMediaCache.shared.loadImage(
                    for: descriptor,
                    completion: completion
                )
            }
        )
    }

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

    struct MaterializationDrainResult: Equatable {
        let processedCount: Int
        let elapsed: CFTimeInterval
        let stoppedForTimeLimit: Bool
    }

    fileprivate enum LatticeItemShiftResolution {
        case unresolved
        case unavailable
        case shift(columns: Int, rows: Int)
    }

    final class Session {
        let id = UUID()
        let wasCollectionViewPrefetchingEnabled: Bool
        fileprivate(set) var sourceLayout: MobilePlayerBrowserLayout
        fileprivate(set) var gestureAnchor: GridModeGestureAnchor?
        fileprivate(set) var visualAnchor: CGPoint?
        fileprivate var plane: GridModePlaneContext?
        fileprivate(set) var zoomRebase: GridModeRebase?
        fileprivate(set) var lastPanDeltaY: CGFloat = 0
        fileprivate(set) var lastRenderedScale: CGFloat = 1
        fileprivate(set) var lastSettleProgress: CGFloat = 0
        fileprivate(set) var pendingGestureMaterializationBurst = false
        fileprivate(set) var lastContentFadeAlpha: CGFloat = 0
        /// The alpha the in-flight render frame will commit. Cell
        /// classification reads it mid-frame, before `applyContentFade`
        /// records the committed value into `lastContentFadeAlpha`.
        fileprivate(set) var currentContentFadeTargetAlpha: CGFloat = 0
        fileprivate(set) var contentFadeAnimationMayBeActive = false
        fileprivate(set) var contentFadeAnimationGeneration: UInt = 0
        fileprivate(set) var reassignments = [Int: Int]()
        /// Destination items already claimed by the degraded (non-uniform
        /// lattice) per-cell matching path; a second cell resolving to a
        /// claimed item stays a source fallback instead of duplicating art.
        fileprivate(set) var assignedDestinationItems = Set<Int>()
        fileprivate var latticeItemShiftResolution =
            LatticeItemShiftResolution.unresolved
        fileprivate(set) var selectedSourceItems = Set<Int>()
        fileprivate(set) var viewportSelectedSourceItems = Set<Int>()
        fileprivate(set) var preparedRepresentationIDs = Set<ObjectIdentifier>()
        fileprivate(set) var lockedFallbackRepresentationIDs = Set<ObjectIdentifier>()
        fileprivate(set) var sourceCoverage =
            PlayerBrowserGridSourceCoveragePlan<ObjectIdentifier>.empty
        fileprivate(set) var detailedSourceCellItems = [ObjectIdentifier: Int]()
        fileprivate(set) var cachedSourceRepresentations = [ObjectIdentifier: (
            itemIndex: Int,
            cell: MobilePlayerCollectionBrowserCell
        )]()
        fileprivate(set) var sourceOverscanCells = [Int: MobilePlayerCollectionBrowserCell]()
        fileprivate(set) var phantomCells = [Int: MobilePlayerCollectionBrowserCell]()
        fileprivate(set) var reusablePhantomCells = [MobilePlayerCollectionBrowserCell]()
        fileprivate(set) var viewportPromotionCoverage = PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var viewportDetailCoverage = PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var foregroundCurrentViewportCoverage =
            PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var foregroundTerminalViewportCoverage =
            PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var phantomShapeView: UIView?
        fileprivate(set) var phantomCoverage = PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var sourceOverscanCoverage = PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var sourcePlanePriorityCoverage = PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var destinationPlanePriorityCoverage = PlayerBrowserGridPhantomCoverage()
        fileprivate(set) var sourcePlaneCellPlanGeneration: UInt = 0
        fileprivate(set) var destinationPlaneCellPlanGeneration: UInt = 0
        fileprivate(set) var transitionContentGeneration: UInt = 0
        fileprivate(set) var transitionImageLoads = [
            ObjectIdentifier: GridModeTransitionImageLoad
        ]()
        fileprivate(set) var foregroundEligibleRepresentationIDs =
            Set<ObjectIdentifier>()
        fileprivate(set) var currentViewportRepresentationIDs =
            Set<ObjectIdentifier>()
        fileprivate(set) var lastReconciledCurrentViewportRepresentationIDs =
            Set<ObjectIdentifier>()
        fileprivate(set) var cellFrameCorrections = [
            ObjectIdentifier: (
                cell: UICollectionViewCell,
                correction: GridModeCellFrameCorrection
            )
        ]()
        fileprivate(set) var unpreparedMarginTrackingRepresentationIDs =
            Set<ObjectIdentifier>()
        fileprivate(set) var deferredClassificationPaintRepresentationIDs =
            Set<ObjectIdentifier>()
        /// Source cells whose destination lands off screen; they hold their
        /// source position and content to keep the viewport margins covered.
        fileprivate(set) var marginCoverageRepresentationIDs =
            Set<ObjectIdentifier>()

        fileprivate var frameClassifiedRepresentationIDs: Set<ObjectIdentifier> {
            Set(cellFrameCorrections.keys).union(
                marginCoverageRepresentationIDs
            )
        }

        fileprivate var frameTrackedRepresentationIDs: Set<ObjectIdentifier> {
            frameClassifiedRepresentationIDs.union(
                unpreparedMarginTrackingRepresentationIDs
            )
        }

        fileprivate(set) var hasCellFrameCorrectionTransforms = false
        fileprivate(set) var hasSourceSeamCompensationTransforms = false
        fileprivate(set) var hasPhantomSeamCompensationTransforms = false
        fileprivate(set) var currentPhantomPlan: PlayerBrowserGridPhantomPlan?
        fileprivate(set) var sourceCoverageRefreshIsDirty = false
        fileprivate(set) var phantomShapeRefreshIsDirty = false
        fileprivate(set) var destinationPlanRefreshIsDirty = false
        fileprivate(set) var managedCellPlanRefreshIsPending = false

        func deferClassificationPaint(for representationID: ObjectIdentifier) {
            deferredClassificationPaintRepresentationIDs.insert(
                representationID
            )
        }

        fileprivate func sourceItemPrecedes(_ lhs: Int, _ rhs: Int) -> Bool {
            let lhsIsVisible = viewportSelectedSourceItems.contains(lhs)
            let rhsIsVisible = viewportSelectedSourceItems.contains(rhs)
            if lhsIsVisible != rhsIsVisible {
                return lhsIsVisible
            }
            return lhs < rhs
        }

        fileprivate func removeForegroundEligibility(
            for representationIDs: Set<ObjectIdentifier>
        ) {
            foregroundEligibleRepresentationIDs.subtract(representationIDs)
            currentViewportRepresentationIDs.subtract(representationIDs)
        }

        fileprivate func removeForegroundEligibility(
            for representationID: ObjectIdentifier
        ) {
            foregroundEligibleRepresentationIDs.remove(representationID)
            currentViewportRepresentationIDs.remove(representationID)
        }

        fileprivate func unregisterSourceRepresentation(
            _ representationID: ObjectIdentifier
        ) {
            cachedSourceRepresentations.removeValue(forKey: representationID)
            preparedRepresentationIDs.remove(representationID)
            lockedFallbackRepresentationIDs.remove(representationID)
            unpreparedMarginTrackingRepresentationIDs.remove(
                representationID
            )
            deferredClassificationPaintRepresentationIDs.remove(
                representationID
            )
            marginCoverageRepresentationIDs.remove(representationID)
            removeForegroundEligibility(for: representationID)
            detailedSourceCellItems.removeValue(forKey: representationID)
        }

        fileprivate func registerSourceRepresentation(
            _ cell: MobilePlayerCollectionBrowserCell,
            itemIndex: Int
        ) {
            let representationID = ObjectIdentifier(cell)
            if let registeredItem = cachedSourceRepresentations[
                representationID
            ]?.itemIndex, registeredItem != itemIndex {
                unregisterSourceRepresentation(representationID)
            }
            cachedSourceRepresentations[representationID] = (
                itemIndex: itemIndex,
                cell: cell
            )
        }

        fileprivate func addCellFrameCorrection(
            _ correction: GridModeCellFrameCorrection,
            for cell: UICollectionViewCell
        ) {
            let representationID = ObjectIdentifier(cell)
            marginCoverageRepresentationIDs.remove(representationID)
            cellFrameCorrections[representationID] = (cell, correction)
        }

        fileprivate func holdSourceRepresentationForMargin(
            _ representationID: ObjectIdentifier
        ) {
            cellFrameCorrections.removeValue(forKey: representationID)
            marginCoverageRepresentationIDs.insert(representationID)
            if cellFrameCorrections.isEmpty {
                hasCellFrameCorrectionTransforms = false
            }
        }

        fileprivate func dropCellFrameCorrections(
            for representationIDs: Set<ObjectIdentifier>
        ) {
            for representationID in representationIDs {
                cellFrameCorrections.removeValue(forKey: representationID)
            }
            unpreparedMarginTrackingRepresentationIDs.subtract(
                representationIDs
            )
            deferredClassificationPaintRepresentationIDs.subtract(
                representationIDs
            )
            marginCoverageRepresentationIDs.subtract(representationIDs)
            if cellFrameCorrections.isEmpty {
                hasCellFrameCorrectionTransforms = false
            }
        }

        fileprivate func releaseUnpreparedMarginCoverage(
            for representationID: ObjectIdentifier
        ) {
            cellFrameCorrections.removeValue(forKey: representationID)
            marginCoverageRepresentationIDs.remove(representationID)
            if cellFrameCorrections.isEmpty {
                hasCellFrameCorrectionTransforms = false
            }
        }

        /// Margin coverage is keyed by cell identity, so entries outlive the
        /// cells they name unless they are dropped with the representations.
        fileprivate func pruneMarginCoverageToSourceRepresentations() {
            guard !marginCoverageRepresentationIDs.isEmpty
                || !unpreparedMarginTrackingRepresentationIDs.isEmpty else {
                return
            }
            marginCoverageRepresentationIDs.formIntersection(
                cachedSourceRepresentations.keys
            )
            unpreparedMarginTrackingRepresentationIDs.formIntersection(
                cachedSourceRepresentations.keys
            )
        }

        fileprivate func clearForegroundEligibility() {
            foregroundEligibleRepresentationIDs.removeAll(
                keepingCapacity: true
            )
            currentViewportRepresentationIDs.removeAll(
                keepingCapacity: true
            )
        }

        fileprivate func resetForegroundEligibilityCoverage() {
            foregroundCurrentViewportCoverage.reset()
            foregroundTerminalViewportCoverage.reset()
        }

        fileprivate func resetTransitionState() {
            transitionImageLoads.values.forEach { $0.cancellation() }
            reassignments.removeAll(keepingCapacity: true)
            assignedDestinationItems.removeAll(keepingCapacity: true)
            latticeItemShiftResolution = .unresolved
            selectedSourceItems.removeAll(keepingCapacity: true)
            viewportSelectedSourceItems.removeAll(keepingCapacity: true)
            preparedRepresentationIDs.removeAll(keepingCapacity: true)
            lockedFallbackRepresentationIDs.removeAll(keepingCapacity: true)
            sourceCoverage = .empty
            detailedSourceCellItems.removeAll(keepingCapacity: true)
            cachedSourceRepresentations.removeAll(keepingCapacity: true)
            clearForegroundEligibility()
            lastReconciledCurrentViewportRepresentationIDs.removeAll(
                keepingCapacity: true
            )
            transitionImageLoads.removeAll(keepingCapacity: true)
            cellFrameCorrections.removeAll(keepingCapacity: true)
            unpreparedMarginTrackingRepresentationIDs.removeAll(
                keepingCapacity: true
            )
            deferredClassificationPaintRepresentationIDs.removeAll(
                keepingCapacity: true
            )
            marginCoverageRepresentationIDs.removeAll(keepingCapacity: true)
            lastContentFadeAlpha = 0
            currentContentFadeTargetAlpha = 0
            contentFadeAnimationMayBeActive = false
            lastSettleProgress = 0
            hasCellFrameCorrectionTransforms = false
            hasSourceSeamCompensationTransforms = false
            hasPhantomSeamCompensationTransforms = false
            phantomShapeView = nil
            currentPhantomPlan = nil
            sourceCoverageRefreshIsDirty = false
            phantomShapeRefreshIsDirty = false
            destinationPlanRefreshIsDirty = false
            managedCellPlanRefreshIsPending = false
            phantomCoverage.reset()
            sourceOverscanCoverage.reset()
            sourcePlanePriorityCoverage.reset()
            destinationPlanePriorityCoverage.reset()
            viewportPromotionCoverage.reset()
            viewportDetailCoverage.reset()
            resetForegroundEligibilityCoverage()
            sourcePlaneCellPlanGeneration &+= 1
            destinationPlaneCellPlanGeneration &+= 1
        }

        fileprivate init(
            gestureAnchor: GridModeGestureAnchor?,
            sourceLayout: MobilePlayerBrowserLayout,
            wasCollectionViewPrefetchingEnabled: Bool
        ) {
            self.gestureAnchor = gestureAnchor
            self.sourceLayout = sourceLayout
            self.wasCollectionViewPrefetchingEnabled =
                wasCollectionViewPrefetchingEnabled
        }
    }

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

    struct GridModeTransitionImageLoad {
        let id: UUID
        let sourceItem: Int
        let destinationItem: Int
        let planeID: UUID
        let contentGeneration: UInt
        let contentIdentity: MobilePlayerBrowserContentIdentity
        let requiredImageQuality: CollectionBrowseImageQuality
        let descriptor: DownloadableMediaDescriptor
        let cancellation: () -> Void
    }

    struct GridModeTransitionImageCompletion {
        let planeID: UUID
        let contentGeneration: UInt
        let loadID: UUID
        let representationID: ObjectIdentifier
        let sourceItem: Int
        let destinationItem: Int
        let contentIdentity: MobilePlayerBrowserContentIdentity
        let requiredImageQuality: CollectionBrowseImageQuality
        let descriptor: DownloadableMediaDescriptor
        let image: UIImage?
    }

    private struct TransitionRepresentationKey: Hashable {
        let representationID: ObjectIdentifier
        let sourceItem: Int
    }

    private enum TransitionWorkScope {
        case all
        case anySourceForRepresentationIDs(Set<ObjectIdentifier>)
        case sourceItems(Set<Int>)
        case representationKeys(Set<TransitionRepresentationKey>)

        var isEmpty: Bool {
            switch self {
            case .all:
                false
            case let .anySourceForRepresentationIDs(representationIDs):
                representationIDs.isEmpty
            case let .sourceItems(sourceItems):
                sourceItems.isEmpty
            case let .representationKeys(representationKeys):
                representationKeys.isEmpty
            }
        }

        func contains(
            representationID: ObjectIdentifier,
            sourceItem: Int
        ) -> Bool {
            switch self {
            case .all:
                true
            case let .anySourceForRepresentationIDs(representationIDs):
                representationIDs.contains(representationID)
            case let .sourceItems(sourceItems):
                sourceItems.contains(sourceItem)
            case let .representationKeys(representationKeys):
                representationKeys.contains(TransitionRepresentationKey(
                    representationID: representationID,
                    sourceItem: sourceItem
                ))
            }
        }
    }

    private struct ForegroundDestinationEligibilityContext {
        let currentViewportRect: CGRect
        let currentPriorityRect: CGRect
        let terminalViewportRect: CGRect
        let destinationGeometry: MobilePlayerBrowserVisualLayoutGeometry
    }

    private enum ForegroundDestinationEligibility: Equatable {
        case current
        case terminal
    }

    struct PromotionRepresentationKey: Hashable {
        let representationID: ObjectIdentifier
        let tokenIndex: Int
    }

    struct PendingDetailRepresentationKey: Hashable {
        let representationID: ObjectIdentifier
        let sourceItem: Int
    }

    struct GridModeCellFrameCorrection {
        let centerDelta: CGPoint
        let sizeDelta: CGSize
        let destinationVisibilityProgress: CGFloat
    }

    struct GridModeCellFrameCorrectionGeometry {
        let currentToTerminal: CGAffineTransform
        let terminalScreenOffsetY: CGFloat
        let destinationGeometry: MobilePlayerBrowserVisualLayoutGeometry
    }

    private struct SourceCellEntry {
        let indexPath: IndexPath
        let cell: MobilePlayerCollectionBrowserCell
    }

    private struct ResolvedTransitionContent {
        let destinationItem: Int
        let contentIdentity: MobilePlayerBrowserContentIdentity
        let imageSources: CollectionBrowseImageSources
        let cachedImage: ImageAccess.CachedImage?
    }

    private enum TransitionContentPreparation {
        case ready
        case pending
        case unavailable
    }

    private enum DetailedSourceMaterializationCandidates {
        case unpreparedSourceCells([SourceCellEntry])
        case eligibleRepresentationIDs(Set<ObjectIdentifier>)
    }

    private enum ManualCellLayerRole {
        case sourceOverscan
        case destinationPhantom
    }

    private static let materializationJobLimit = 8
    private static let materializationTimeLimit: CFTimeInterval = 0.002
    /// Gesture renders may expose many cells at once, so they admit more cheap
    /// jobs while keeping materialization within a fixed fraction of the frame.
    private static let transitionMaterializationJobLimit = 32
    private static let transitionMaterializationMaximumTimeLimit:
        CFTimeInterval = 0.004
    private static let transitionMaterializationFrameFraction: CFTimeInterval =
        0.24
    private static let defaultMaterializationFrameDuration: CFTimeInterval =
        1.0 / 60
    private static let minimumSourceBatchCapacity = 4
    private static let contentFadeOutDuration: TimeInterval = 0.12
    private static let edgeHandoffDistance: CGFloat = 128

    private weak var collectionView: MobilePlayerCollectionBrowserCollectionView?
    private weak var viewportView: UIView?
    private let contentAccess: ContentAccess
    private let imageAccess: ImageAccess
    private let clock: () -> CFTimeInterval
    private(set) var lifecycle: Lifecycle = .idle
    private var materializationQueue = MaterializationQueue()
    private(set) var transitionWorkQueueFilterPassCount: UInt = 0
    private var materializationDisplayLink: CADisplayLink?
    private let materializationDisplayLinkTarget =
        MaterializationDisplayLinkTarget()
    private var isDrainingMaterialization = false
    private var hasTransitionPlaceholderTones = false
    private(set) var destinationPlanBuildCount = 0
    private(set) var sourceCoverageBuildCount = 0
    private(set) var phantomShapeStructureBuildCount = 0
    private(set) var phantomShapeMaskBuildCount = 0
    private(set) var foregroundEligibilityReconciliationCount = 0

    init(
        collectionView: MobilePlayerCollectionBrowserCollectionView,
        viewportView: UIView,
        contentAccess: ContentAccess,
        imageAccess: ImageAccess = .live,
        clock: @escaping () -> CFTimeInterval = CACurrentMediaTime
    ) {
        self.collectionView = collectionView
        self.viewportView = viewportView
        self.contentAccess = contentAccess
        self.imageAccess = imageAccess
        self.clock = clock
        super.init()
        materializationDisplayLinkTarget.renderer = self
    }

    isolated deinit {
        materializationDisplayLink?.invalidate()
        let session: Session?
        switch lifecycle {
        case .idle:
            session = nil
        case let .active(activeSession):
            session = activeSession
        case let .committing(commit):
            session = commit.session
        }
        session?.transitionImageLoads.values.forEach { $0.cancellation() }
        session?.sourceOverscanCells.values.forEach { $0.cancelImageLoad() }
        session?.phantomCells.values.forEach { $0.cancelImageLoad() }
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
        materializationQueue.count
    }

    var pendingDetailMaterializationWorkCount: Int {
        materializationQueue.count {
            if case .detail = $0.kind { return true }
            return false
        }
    }

    var pendingDetailMaterializationRepresentationIDs:
        Set<ObjectIdentifier> {
        materializationQueue.representationIDs { job in
            guard case let .detail(_, _, representationID, _) = job.kind
            else {
                return nil
            }
            return representationID
        }
    }

    var pendingDetailMaterializationRepresentationKeys:
        Set<PendingDetailRepresentationKey> {
        materializationQueue.pendingDetailRepresentationKeys()
    }

    var pendingVisibleDetailMaterializationRepresentationIDs:
        Set<ObjectIdentifier> {
        materializationQueue.representationIDs { job in
            guard job.priority == .visibleRepresentation,
                  case let .detail(_, _, representationID, _) = job.kind
            else {
                return nil
            }
            return representationID
        }
    }

    var pendingPromotionRepresentationKeys:
        Set<PromotionRepresentationKey> {
        materializationQueue.promotionRepresentationKeys()
    }

    var pendingTransitionImageCompletionWorkCount: Int {
        materializationQueue.count {
            if case .transitionImageCompletion = $0.kind { return true }
            return false
        }
    }

    var pendingVisibleTransitionImageCompletionWorkCount: Int {
        materializationQueue.count {
            guard $0.priority == .visibleRepresentation,
                  case .transitionImageCompletion = $0.kind else {
                return false
            }
            return true
        }
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
        guard let session = currentSession else { return [] }
        return Array(session.sourceOverscanCells.values)
            + Array(session.phantomCells.values)
    }

    var phantomShapeMaskedFrames: [CGRect] {
        guard let placeholderView = currentSession?.phantomShapeView
            as? PhantomShapeView else {
            return []
        }
        return placeholderView.renderedShapeExclusionFrames
            + Array(placeholderView.renderedOccupantFrames.values)
    }

    var viewportRenderCells: [MobilePlayerCollectionBrowserCell] {
        guard let session = currentSession else {
            return visibleBrowserCells
        }
        guard let collectionView, let viewportView else { return [] }
        var cells = viewportSourceCells(session: session).map(\.cell)
        cells.append(contentsOf: session.phantomCells.compactMap {
            itemIndex, cell in
            MobilePlayerCollectionBrowserTransitionSupport
                .itemIntersectsViewport(
                    at: IndexPath(item: itemIndex, section: 0),
                    cell: cell,
                    collectionView: collectionView,
                    viewportView: viewportView
                ) ? cell : nil
        })
        return cells
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
        if let collectionView {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath)
                    as? MobilePlayerCollectionBrowserCell else {
                    continue
                }
                registerSourceRepresentation(
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
        guard !materializationQueue.isEmpty || hasDeferredRenderRefresh else {
            return
        }
        currentSession?.pendingGestureMaterializationBurst = true
    }

    func cancelGestureMaterializationBurst() {
        currentSession?.pendingGestureMaterializationBurst = false
    }

    @discardableResult
    func installPlane(_ request: GridModePlaneRequest) -> Bool {
        guard case let .active(session) = lifecycle,
              let collectionView,
              let viewportView else {
            return false
        }
        let installationScale = session.lastRenderedScale
        let installationPlane = request.crossfade.outgoingPlane(
            scale: installationScale,
            panDeltaY: session.lastPanDeltaY
        )
        let installationDrift = request.crossfade.driftProgress(
            forScale: installationScale
        )
        let rebase = Self.makeRebase(
            currentTransform: collectionView.transform,
            baseTransform: request.crossfade.transform(
                for: installationPlane,
                viewCenter: CGPoint(
                    x: viewportView.bounds.midX,
                    y: viewportView.bounds.midY
                )
            ),
            installationScale: installationScale,
            driftProgress: installationDrift
        )
        let plane = GridModePlaneContext(request: request, rebase: rebase)
        cancelMaterializationPump()
        clearTransitionContent(
            session: session,
            carryoverRetention: .pendingBase
        )
        session.plane = plane
        session.zoomRebase = nil
        extendSourceCoverageIfNeeded(
            session: session,
            layout: request.transitionLayout.fromLayout,
            targetPlaneID: request.id,
            installsStructuralCoverage: false
        )
        classifyDetailedSourceRepresentations(session: session, plane: plane)
        refreshSourceCoverageAndMaterialization(
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
              let collectionView,
              let viewportView,
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
        guard let anchor = session.gestureAnchor else { return false }
        session.sourceLayout = sourceLayout
        session.lastRenderedScale = scale
        let transform = zoomTransform(
            scale: scale,
            panDeltaY: panDeltaY,
            anchor: session.visualAnchor ?? anchor.viewportPoint,
            layout: sourceLayout,
            baseContentOffsetY: anchor.baseContentOffsetY,
            viewportSize: viewportView.bounds.size
        )
        if var rebase = session.zoomRebase {
            collectionView.transform = rebase.applying(
                to: transform,
                scale: scale,
                driftProgress: 0,
                settleProgress: 0
            )
            session.zoomRebase = rebase.progress >= 1 ? nil : rebase
        } else {
            collectionView.transform = transform
        }
        extendSourceCoverageIfNeeded(session: session, layout: sourceLayout)
        if let appliedScale = appliedPlaneScale() {
            applySourceSeamCompensations(
                session: session,
                naturalSpacing: sourceLayout.interItemSpacing,
                targetSpacing: sourceLayout.interItemSpacing,
                appliedScale: appliedScale
            )
            refreshPhantomShapeStructure(session: session)
        }
        enqueueViewportPromotions(session: session)
        applyContentFade(session: session, alpha: 0, animated: true)
        refreshPhantomShapeExclusionMask(session: session)
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
        applyContentFade(
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
        guard case let .active(session) = lifecycle,
              let viewportView,
              scale.isFinite,
              scale > 0,
              scale != 1,
              let gestureAnchor = session.gestureAnchor else {
            currentSession?.zoomRebase = nil
            return
        }
        let baseTransform = zoomTransform(
            scale: scale,
            panDeltaY: panDeltaY,
            anchor: anchor,
            layout: sourceLayout,
            baseContentOffsetY: gestureAnchor.baseContentOffsetY,
            viewportSize: viewportView.bounds.size
        )
        session.zoomRebase = Self.makeRebase(
            currentTransform: currentTransform,
            baseTransform: baseTransform,
            installationScale: scale,
            driftProgress: 0
        )
    }

    func reanchorSettlingRendering(at screenPoint: CGPoint) {
        guard case let .active(session) = lifecycle,
              let collectionView,
              let viewportView,
              screenPoint.x.isFinite,
              screenPoint.y.isFinite else {
            return
        }
        let currentTransform = collectionView.transform
        let determinant = currentTransform.a * currentTransform.d
            - currentTransform.b * currentTransform.c
        guard determinant.isFinite, abs(determinant) > .ulpOfOne else {
            return
        }
        let pivot = CGPoint(
            x: viewportView.bounds.midX,
            y: viewportView.bounds.midY
        )
        let centeredPoint = CGPoint(
            x: screenPoint.x - pivot.x,
            y: screenPoint.y - pivot.y
        ).applying(currentTransform.inverted())
        let outgoingAnchor = CGPoint(
            x: centeredPoint.x + pivot.x,
            y: centeredPoint.y + pivot.y
        )
        guard let plane = session.plane else {
            session.visualAnchor = outgoingAnchor
            installZoomRebase(
                currentTransform: currentTransform,
                scale: session.lastRenderedScale,
                panDeltaY: session.lastPanDeltaY,
                anchor: outgoingAnchor,
                sourceLayout: session.sourceLayout
            )
            return
        }
        guard let crossfade = plane.crossfade.reanchored(
            outgoingAnchor: outgoingAnchor
        ) else {
            return
        }
        let outgoingPlane = crossfade.outgoingPlane(
            scale: session.lastRenderedScale,
            panDeltaY: session.lastPanDeltaY
        )
        let installationDrift = crossfade.driftProgress(
            forScale: session.lastRenderedScale
        )
        guard installationDrift < 1 || session.lastSettleProgress < 1 else {
            return
        }
        let rebase = Self.makeRebase(
            currentTransform: currentTransform,
            baseTransform: crossfade.transform(
                for: outgoingPlane,
                viewCenter: pivot
            ),
            installationScale: session.lastRenderedScale,
            driftProgress: installationDrift,
            settleProgress: session.lastSettleProgress
        )
        session.visualAnchor = outgoingAnchor
        session.zoomRebase = nil
        session.plane = GridModePlaneContext(
            request: GridModePlaneRequest(
                id: plane.id,
                toMode: plane.toMode,
                layoutAspectState: plane.layoutAspectState,
                anchorTokenIndex: plane.anchorTokenIndex,
                transitionLayout: plane.transitionLayout,
                crossfade: crossfade,
                latticeMap: plane.latticeMap
            ),
            rebase: rebase
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
            refreshDetailedSourceRepresentations(
                session: session,
                plane: plane
            )
        }
        var ineligibleFallbackSourceItems = Set<Int>()
        var fallbackSourceItemByDestinationItem = [Int: Int]()
        for sourceItem in prioritizedSourceItems(
            session.selectedSourceItems,
            session: session
        ) {
            if let destinationItem = destinationItem(
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
        let sources = captureVisibleCarryoverSources(
            session: session,
            anchorTokenIndex: plane.anchorTokenIndex,
            capturesFallbackSources: capturesFallbackSources,
            ineligibleFallbackSourceItems: ineligibleFallbackSourceItems
        )
        let terminalContentOffsetY = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        ).incomingContentOffsetY
        cancelMaterializationPump()
        let commit = CommitState(
            session: session,
            plane: plane,
            sources: sources,
            fallbackSourceItemByDestinationItem:
                fallbackSourceItemByDestinationItem
        )
        lifecycle = .committing(commit)
        session.plane = nil
        session.gestureAnchor = nil
        tearDownPlaneRendering(session: session)
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
        installCarryoverContent(
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
        cancelMaterializationPump()
        let commit = CommitState(
            session: session,
            plane: nil,
            sources: [],
            fallbackSourceItemByDestinationItem: [:]
        )
        lifecycle = .committing(commit)
        tearDownPlaneRendering(session: session)
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
    }

    func abortCommit(_ preparation: CommitPreparation? = nil) {
        guard case let .committing(commit) = lifecycle,
              !commit.isComplete,
              preparation == nil || preparation?.id == commit.id else {
            return
        }
        cancelMaterializationPump()
        tearDownPlaneRendering(session: commit.session)
        lifecycle = .active(commit.session)
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
        cancelMaterializationPump()
        session.sourceLayout = sourceLayout
        session.plane = nil
        clearTransitionContent(
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
        cancelMaterializationPump()
        tearDownPlaneRendering(
            session: session,
            carryoverRetention: .pendingBase
        )
        return anchoredContentOffsetY
    }

    func finish(preservingCarryover: Bool) -> FinishState? {
        guard let session = currentSession else { return nil }
        let clearsTransitionPlaceholderTones = session.gestureAnchor != nil
            || hasTransitionPlaceholderTones
        let pannedContentOffsetY = session.gestureAnchor.map {
            $0.baseContentOffsetY - session.lastPanDeltaY
        }
        session.gestureAnchor = nil
        session.lastPanDeltaY = 0
        cancelMaterializationPump()
        tearDownPlaneRendering(
            session: session,
            carryoverRetention: preservingCarryover ? .all : .none
        )
        session.reusablePhantomCells.removeAll(keepingCapacity: false)
        hasTransitionPlaceholderTones = false
        lifecycle = .idle
        return FinishState(
            wasCollectionViewPrefetchingEnabled:
                session.wasCollectionViewPrefetchingEnabled,
            pannedContentOffsetY: pannedContentOffsetY,
            clearsTransitionPlaceholderTones:
                clearsTransitionPlaceholderTones
        )
    }

    private static func makeRebase(
        currentTransform: CGAffineTransform,
        baseTransform: CGAffineTransform,
        installationScale: CGFloat,
        driftProgress: CGFloat,
        settleProgress: CGFloat = 0
    ) -> GridModeRebase? {
        let clock: GridModeRebaseClock
        let installationProgress: CGFloat
        if driftProgress >= 1 {
            clock = .destinationEndpoint
            installationProgress = PlayerBrowserGridCrossfade
                .sanitizedProgress(settleProgress)
        } else if driftProgress <= 0, installationScale != 1 {
            clock = .sourceEndpoint(installationScale: installationScale)
            installationProgress = 0
        } else {
            clock = .drift
            installationProgress = driftProgress
        }
        guard let transform = PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: currentTransform,
            baseTransform: baseTransform,
            installationProgress: installationProgress
        ) else {
            return nil
        }
        return GridModeRebase(
            transform: transform,
            clock: clock,
            progress: installationProgress
        )
    }

    private func zoomTransform(
        scale: CGFloat,
        panDeltaY: CGFloat,
        anchor: CGPoint,
        layout: MobilePlayerBrowserLayout,
        baseContentOffsetY: CGFloat,
        viewportSize: CGSize
    ) -> CGAffineTransform {
        let panScreenShiftY = PlayerBrowserGridCrossfade.safePanDeltaY(
            restContentOffsetY: baseContentOffsetY,
            maximumContentOffsetY: max(
                layout.contentSize.height - viewportSize.height,
                0
            ),
            scale: scale,
            panDeltaY: panDeltaY
        )
        return PlayerBrowserGridCrossfade.anchoredScaleTransform(
            scaleX: scale,
            scaleY: scale,
            anchor: anchor,
            translation: CGPoint(x: 0, y: panScreenShiftY),
            viewCenter: CGPoint(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            )
        )
    }

    private func applyPlaneFrames(
        session: Session,
        plane: inout GridModePlaneContext,
        scale: CGFloat,
        settleProgress: CGFloat,
        presentationProgress: CGFloat
    ) {
        guard let collectionView, let viewportView else { return }
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
        extendDestinationCoverageIfNeeded(session: session, plane: plane)
        let outgoingPlane = plane.crossfade.outgoingPlane(
            scale: scale,
            panDeltaY: session.lastPanDeltaY
        )
        let driftProgress = plane.crossfade.driftProgress(forScale: scale)
        let baseTransform = plane.crossfade.transform(
            for: outgoingPlane,
            viewCenter: CGPoint(
                x: viewportView.bounds.midX,
                y: viewportView.bounds.midY
            )
        )
        if var rebase = plane.rebase {
            collectionView.transform = rebase.applying(
                to: baseTransform,
                scale: scale,
                driftProgress: driftProgress,
                settleProgress: settleProgress
            )
            plane.rebase = rebase
        } else {
            collectionView.transform = baseTransform
        }
        extendSourceCoverageIfNeeded(
            session: session,
            layout: plane.transitionLayout.fromLayout,
            targetPlaneID: plane.id,
            installsStructuralCoverage: false
        )
        let appliedScale = appliedPlaneScale()
        reconcileCellFrameCorrectionClassifications(
            session: session,
            plane: plane,
            defersStableTransform: appliedScale != nil,
            defersPresentationUpdate: contentFadeWillSweepWithoutAnimation
        )
        if let appliedScale {
            applyCellFrameCorrections(
                session: session,
                plane: plane,
                appliedScale: appliedScale
            )
            applySeamCompensations(
                session: session,
                plane: plane,
                appliedScale: appliedScale
            )
        }
        session.deferredClassificationPaintRepresentationIDs.removeAll(
            keepingCapacity: true
        )
        enqueueViewportPromotions(session: session)
        reconcileForegroundDestinationEligibility(
            session: session,
            plane: plane
        )
        if presentationProgress > 0 {
            applyContentFade(
                session: session,
                alpha: contentFadeAlpha,
                animated: false
            )
        } else {
            applyContentFade(session: session, alpha: 0, animated: true)
        }
        if presentationProgress
            <= PlayerBrowserGridCrossfade.contentFadeRearmSettleProgress {
            rearmLockedFallbackRepresentationsWhileContentIsHidden(
                session: session,
                dropsUnpreparedGeometry: settleProgress == 0
            )
        }
        refreshPhantomShapeExclusionMask(session: session)
    }

    private struct AppliedPlaneScale {
        let x: CGFloat
        let y: CGFloat
    }

    private struct CellFrameCorrectionTransformContext {
        let settleProgress: CGFloat
        let appliedScale: AppliedPlaneScale
        let terminalScale: AppliedPlaneScale
        let sourceSpacing: CGFloat
        let destinationSpacing: CGFloat
        let targetSpacing: CGFloat
    }

    private func appliedPlaneScale() -> AppliedPlaneScale? {
        guard let transform = collectionView?.transform,
              transform.a.isFinite,
              transform.d.isFinite,
              transform.a > 0,
              transform.d > 0 else {
            return nil
        }
        return AppliedPlaneScale(x: transform.a, y: transform.d)
    }

    private func cellFrameCorrectionTransformContext(
        session: Session,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) -> CellFrameCorrectionTransformContext? {
        let terminalPlane = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        )
        guard terminalPlane.scaleX.isFinite,
              terminalPlane.scaleY.isFinite,
              terminalPlane.scaleX > 0,
              terminalPlane.scaleY > 0 else {
            return nil
        }
        return CellFrameCorrectionTransformContext(
            settleProgress: session.lastSettleProgress,
            appliedScale: appliedScale,
            terminalScale: AppliedPlaneScale(
                x: terminalPlane.scaleX,
                y: terminalPlane.scaleY
            ),
            sourceSpacing:
                plane.transitionLayout.fromLayout.interItemSpacing,
            destinationSpacing:
                plane.transitionLayout.toLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            )
        )
    }

    private func applyCellFrameCorrections(
        session: Session,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) {
        guard !session.cellFrameCorrections.isEmpty,
              let context = cellFrameCorrectionTransformContext(
                  session: session,
                  plane: plane,
                  appliedScale: appliedScale
              ) else {
            for (cell, _) in session.cellFrameCorrections.values {
                setTransform(.identity, on: cell)
            }
            session.hasCellFrameCorrectionTransforms = false
            return
        }
        var hasTransforms = false
        for (cell, correction) in session.cellFrameCorrections.values {
            let applied = applyCellFrameCorrection(
                correction,
                to: cell,
                context: context
            )
            if !applied {
                setTransform(.identity, on: cell)
            }
            hasTransforms = applied || hasTransforms
        }
        session.hasCellFrameCorrectionTransforms = hasTransforms
    }

    private struct SeamCompensation {
        /// Cells and the phantom shape must never shrink past half their
        /// natural size, or a spacing that rivals the cell width flips them.
        static let minimumScaleFactor: CGFloat = 0.5

        let excessX: CGFloat
        let excessY: CGFloat
        let appliedScale: AppliedPlaneScale

        init?(
            naturalSpacing: CGFloat,
            targetSpacing: CGFloat,
            relativeScaleX: CGFloat,
            relativeScaleY: CGFloat,
            appliedScale: AppliedPlaneScale
        ) {
            let excessX = naturalSpacing * relativeScaleX - targetSpacing
            let excessY = naturalSpacing * relativeScaleY - targetSpacing
            guard excessX.isFinite,
                  excessY.isFinite,
                  excessX != 0 || excessY != 0 else {
                return nil
            }
            self.excessX = excessX
            self.excessY = excessY
            self.appliedScale = appliedScale
        }
    }

    /// Scaling the whole grid scales its seams with it, so a zoom would fatten
    /// every gap by the zoom factor and a zoom-out would starve it. Resizing
    /// every cell symmetrically by the excess leaves the seam at exactly
    /// `spacing` at any scale — `spacing * s - spacing * (s - 1) == spacing` —
    /// the way Photos does. Above unity the cells grow and the outermost edges
    /// push outward, so the plane also covers more margin, not less.
    private func sourceSeamCompensation(
        session: Session,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        sourceSeamCompensation(
            naturalSpacing:
                plane.transitionLayout.fromLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            ),
            appliedScale: appliedScale
        )
    }

    private func sourceSeamCompensation(
        naturalSpacing: CGFloat,
        targetSpacing: CGFloat,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        SeamCompensation(
            naturalSpacing: naturalSpacing,
            targetSpacing: targetSpacing,
            relativeScaleX: appliedScale.x,
            relativeScaleY: appliedScale.y,
            appliedScale: appliedScale
        )
    }

    /// With no plane the seam target is the source spacing itself, so only
    /// the applied zoom's excess is compensated away.
    private func noPlaneSourceSeamCompensation(
        session: Session,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        sourceSeamCompensation(
            naturalSpacing: session.sourceLayout.interItemSpacing,
            targetSpacing: session.sourceLayout.interItemSpacing,
            appliedScale: appliedScale
        )
    }

    /// A live plane owns the seam math: when its excess is zero the source
    /// cells must stay untransformed, never borrow the no-plane formula.
    private func currentSourceSeamCompensation(
        session: Session,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        guard let plane = session.plane else {
            return noPlaneSourceSeamCompensation(
                session: session,
                appliedScale: appliedScale
            )
        }
        return sourceSeamCompensation(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        )
    }

    private func transitionSeamSpacing(
        session: Session,
        plane: GridModePlaneContext
    ) -> CGFloat {
        let sourceSpacing = plane.transitionLayout.fromLayout.interItemSpacing
        let destinationSpacing = plane.transitionLayout.toLayout.interItemSpacing
        let progress = plane.crossfade.driftProgress(
            forScale: session.lastRenderedScale
        )
        return sourceSpacing
            + (destinationSpacing - sourceSpacing)
                * progress
    }

    private func setTransform(
        _ transform: CGAffineTransform,
        on cell: UICollectionViewCell
    ) {
        guard cell.transform != transform else { return }
        cell.transform = transform
    }

    @discardableResult
    private func applySeamCompensation(
        to cell: UICollectionViewCell,
        compensation: SeamCompensation
    ) -> Bool {
        let screenWidth = cell.bounds.width * compensation.appliedScale.x
        let screenHeight = cell.bounds.height * compensation.appliedScale.y
        guard screenWidth > 0, screenHeight > 0 else { return false }
        setTransform(
            CGAffineTransform(
                scaleX: max(
                    1 + compensation.excessX / screenWidth,
                    SeamCompensation.minimumScaleFactor
                ),
                y: max(
                    1 + compensation.excessY / screenHeight,
                    SeamCompensation.minimumScaleFactor
                )
            ),
            on: cell
        )
        return true
    }

    /// Phantoms are laid out on the destination lattice divided by the pitch
    /// ratio, so their seam is `toSpacing * scale / terminalScale` — a
    /// different width from the source cells they sit beside. Holding them at
    /// the destination's own spacing puts one seam width on the whole screen.
    private func phantomSeamCompensation(
        session: Session,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        let terminal = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        )
        guard terminal.scaleX != 0, terminal.scaleY != 0 else { return nil }
        return SeamCompensation(
            naturalSpacing:
                plane.transitionLayout.toLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            ),
            relativeScaleX: appliedScale.x / terminal.scaleX,
            relativeScaleY: appliedScale.y / terminal.scaleY,
            appliedScale: appliedScale
        )
    }

    private func applySeamCompensations(
        session: Session,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) {
        if let phantomCompensation = phantomSeamCompensation(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        ) {
            for phantom in session.phantomCells.values
            where phantom.superview != nil {
                if applySeamCompensation(
                    to: phantom,
                    compensation: phantomCompensation
                ) {
                    session.hasPhantomSeamCompensationTransforms = true
                }
            }
        } else {
            clearPhantomSeamCompensation(session: session)
        }
        applySourceSeamCompensations(
            session: session,
            naturalSpacing:
                plane.transitionLayout.fromLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            ),
            appliedScale: appliedScale
        )
        refreshPhantomShapeStructure(session: session)
    }

    private func applySourceSeamCompensations(
        session: Session,
        naturalSpacing: CGFloat,
        targetSpacing: CGFloat,
        appliedScale: AppliedPlaneScale
    ) {
        guard let compensation = sourceSeamCompensation(
            naturalSpacing: naturalSpacing,
            targetSpacing: targetSpacing,
            appliedScale: appliedScale
        ) else {
            clearSourceSeamCompensation(session: session)
            return
        }
        var hasTransforms = false
        for (representationID, representation) in
            session.cachedSourceRepresentations
        where session.cellFrameCorrections[representationID] == nil
            && representation.cell.superview != nil
            && representation.cell.represents(
                tokenIndex: representation.itemIndex
            ) {
            hasTransforms = applySeamCompensation(
                to: representation.cell,
                compensation: compensation
            ) || hasTransforms
        }
        session.hasSourceSeamCompensationTransforms = hasTransforms
    }

    private func applyNoPlaneSourceSeamCompensation(
        session: Session,
        to cell: MobilePlayerCollectionBrowserCell
    ) {
        guard session.plane == nil,
              let appliedScale = appliedPlaneScale(),
              let compensation = noPlaneSourceSeamCompensation(
                  session: session,
                  appliedScale: appliedScale
              ) else {
            setTransform(.identity, on: cell)
            return
        }
        if applySeamCompensation(to: cell, compensation: compensation) {
            session.hasSourceSeamCompensationTransforms = true
        }
    }

    private func currentPhantomShapeFrameCompensation(
        session: Session
    ) -> PhantomShapeFrameCompensation? {
        guard let appliedScale = appliedPlaneScale() else {
            return nil
        }
        let compensation: SeamCompensation?
        if let plane = session.plane {
            compensation = phantomSeamCompensation(
                session: session,
                plane: plane,
                appliedScale: appliedScale
            )
        } else {
            compensation = noPlaneSourceSeamCompensation(
                session: session,
                appliedScale: appliedScale
            )
        }
        guard let compensation else { return nil }
        return PhantomShapeFrameCompensation(
            excessX: compensation.excessX,
            excessY: compensation.excessY,
            appliedScaleX: compensation.appliedScale.x,
            appliedScaleY: compensation.appliedScale.y,
            minimumScaleFactor: SeamCompensation.minimumScaleFactor
        )
    }

    private func refreshPhantomShapeStructure(session: Session) {
        guard let placeholderView = session.phantomShapeView
            as? PhantomShapeView else {
            return
        }
        renderPhantomShapeStructure(
            session: session,
            in: placeholderView,
            rebuildsTopology: false
        )
    }

    private func clearPhantomSeamCompensation(session: Session) {
        guard session.hasPhantomSeamCompensationTransforms else { return }
        session.hasPhantomSeamCompensationTransforms = false
        for phantom in session.phantomCells.values {
            setTransform(.identity, on: phantom)
        }
    }

    /// Only the source lattice: the two lattices reach zero excess at
    /// different scales, so clearing one must never touch the other.
    private func clearSourceSeamCompensation(session: Session) {
        guard session.hasSourceSeamCompensationTransforms else { return }
        session.hasSourceSeamCompensationTransforms = false
        for (representationID, representation) in
            session.cachedSourceRepresentations
        where session.cellFrameCorrections[representationID] == nil
            && representation.cell.superview != nil
            && representation.cell.represents(
                tokenIndex: representation.itemIndex
            ) {
            setTransform(.identity, on: representation.cell)
        }
    }

    private func applyCellFrameCorrection(
        _ correction: GridModeCellFrameCorrection,
        to cell: UICollectionViewCell,
        context: CellFrameCorrectionTransformContext
    ) -> Bool {
        // The visibility factor stays in the TRANSFORM (unlike the overlay
        // alpha, where it painted a half-faded margin ring): correction
        // classification can flap between drain and settle frames, and the
        // damping keeps the corrected and uncorrected transforms close
        // enough that a flap never reads as a whole-grid flip.
        let progress = context.settleProgress
            * correction.destinationVisibilityProgress
        let screenWidth = cell.bounds.width * context.appliedScale.x
        let screenHeight = cell.bounds.height * context.appliedScale.y
        let seamExcessX = context.sourceSpacing * context.appliedScale.x
            + progress * (
                context.destinationSpacing
                    - context.sourceSpacing * context.terminalScale.x
            ) - context.targetSpacing
        let seamExcessY = context.sourceSpacing * context.appliedScale.y
            + progress * (
                context.destinationSpacing
                    - context.sourceSpacing * context.terminalScale.y
            ) - context.targetSpacing
        let scaleX = screenWidth > 0
            ? 1 + (
                progress * correction.sizeDelta.width + seamExcessX
            ) / screenWidth
            : 1
        let scaleY = screenHeight > 0
            ? 1 + (
                progress * correction.sizeDelta.height + seamExcessY
            ) / screenHeight
            : 1
        let transform = CGAffineTransform(
            translationX: progress * correction.centerDelta.x
                / context.appliedScale.x,
            y: progress * correction.centerDelta.y
                / context.appliedScale.y
        ).scaledBy(x: scaleX, y: scaleY)
        guard transform.a.isFinite,
              transform.b.isFinite,
              transform.c.isFinite,
              transform.d.isFinite,
              transform.tx.isFinite,
              transform.ty.isFinite else {
            return false
        }
        setTransform(transform, on: cell)
        return transform != .identity
    }

    private func registerCellFrameCorrection(
        session: Session,
        cell: UICollectionViewCell,
        destinationItem: Int,
        plane: GridModePlaneContext,
        geometry: GridModeCellFrameCorrectionGeometry? = nil,
        defersStableTransform: Bool = false,
        defersPresentationUpdate: Bool = false
    ) {
        let cellID = ObjectIdentifier(cell)
        let installsOnScreenCorrection = !session
            .unpreparedMarginTrackingRepresentationIDs.contains(cellID)
        let hadCorrection = session.cellFrameCorrections[cellID] != nil
        let wasMarginHeld = session.marginCoverageRepresentationIDs.contains(
            cellID
        )
        guard let geometry = geometry ?? cellFrameCorrectionGeometry(
                  session: session,
                  plane: plane
              ),
              let correction = cellFrameCorrection(
                  for: cell,
                  destinationItem: destinationItem,
                  geometry: geometry,
                  settleProgress: session.lastSettleProgress
              ) else {
            return
        }
        guard correction.destinationVisibilityProgress > 0 else {
            session.holdSourceRepresentationForMargin(cellID)
            if !defersStableTransform || hadCorrection || !wasMarginHeld {
                applyUncorrectedSourcePresentation(
                    session: session,
                    cell: cell,
                    cellID: cellID,
                    plane: plane,
                    interruptingAnimation: hadCorrection || !wasMarginHeld,
                    defersPresentationUpdate: defersPresentationUpdate
                )
            }
            return
        }
        guard installsOnScreenCorrection else {
            session.releaseUnpreparedMarginCoverage(for: cellID)
            if !defersStableTransform || hadCorrection || wasMarginHeld {
                applyUncorrectedSourcePresentation(
                    session: session,
                    cell: cell,
                    cellID: cellID,
                    plane: plane,
                    interruptingAnimation: hadCorrection || wasMarginHeld,
                    defersPresentationUpdate: defersPresentationUpdate
                )
            }
            return
        }
        session.addCellFrameCorrection(correction, for: cell)
        if !defersStableTransform {
            if let appliedScale = appliedPlaneScale(),
               let context = cellFrameCorrectionTransformContext(
                   session: session,
                   plane: plane,
                   appliedScale: appliedScale
               ),
               applyCellFrameCorrection(
                   correction,
                   to: cell,
                   context: context
               ) {
                session.hasCellFrameCorrectionTransforms = true
            } else {
                setTransform(.identity, on: cell)
            }
        }
        if !defersPresentationUpdate,
           let browserCell = cell as? MobilePlayerCollectionBrowserCell {
            applySourceContentFade(
                session: session,
                representationID: cellID,
                cell: browserCell,
                alpha: session.currentContentFadeTargetAlpha,
                interruptingAnimation: wasMarginHeld || !hadCorrection
            )
        }
    }

    /// Restores the plain source presentation for a cell that keeps no
    /// on-screen correction: content fade for its current classification and
    /// the seam compensation every uncorrected source cell wears.
    private func applyUncorrectedSourcePresentation(
        session: Session,
        cell: UICollectionViewCell,
        cellID: ObjectIdentifier,
        plane: GridModePlaneContext,
        interruptingAnimation: Bool,
        defersPresentationUpdate: Bool
    ) {
        if !defersPresentationUpdate,
           let browserCell = cell as? MobilePlayerCollectionBrowserCell {
            applySourceContentFade(
                session: session,
                representationID: cellID,
                cell: browserCell,
                alpha: session.currentContentFadeTargetAlpha,
                interruptingAnimation: interruptingAnimation
            )
        }
        if let appliedScale = appliedPlaneScale(),
           let compensation = sourceSeamCompensation(
               session: session,
               plane: plane,
               appliedScale: appliedScale
           ) {
            applySeamCompensation(to: cell, compensation: compensation)
            session.hasSourceSeamCompensationTransforms = true
        } else {
            setTransform(.identity, on: cell)
        }
    }

    private func reconcileCellFrameCorrectionClassifications(
        session: Session,
        plane: GridModePlaneContext,
        defersStableTransform: Bool,
        defersPresentationUpdate: Bool
    ) {
        let representationIDs = session.frameTrackedRepresentationIDs
        guard !representationIDs.isEmpty,
              let geometry = cellFrameCorrectionGeometry(
                  session: session,
                  plane: plane
              ) else {
            return
        }
        for representationID in representationIDs {
            guard let representation = session.cachedSourceRepresentations[
                representationID
            ],
            representation.cell.superview != nil,
            representation.cell.represents(
                tokenIndex: representation.itemIndex
            ),
            let destinationItem = destinationItem(
                session: session,
                sourceItem: representation.itemIndex,
                plane: plane
            ) else {
                continue
            }
            registerCellFrameCorrection(
                session: session,
                cell: representation.cell,
                destinationItem: destinationItem,
                plane: plane,
                geometry: geometry,
                defersStableTransform: defersStableTransform,
                defersPresentationUpdate: defersPresentationUpdate
            )
        }
    }

    private func removeCellFrameCorrection(
        session: Session,
        for cell: UICollectionViewCell
    ) {
        removeCellFrameCorrections(session: session, for: [cell])
    }

    private func removeCellFrameCorrections<Cells: Sequence>(
        session: Session,
        for cells: Cells
    ) where Cells.Element: UICollectionViewCell {
        let cells = Array(cells)
        let cellIDs = Set(cells.map(ObjectIdentifier.init))
        guard !cellIDs.isEmpty else { return }
        session.dropCellFrameCorrections(for: cellIDs)
        for cell in cells {
            setTransform(.identity, on: cell)
        }
        guard let plane = session.plane,
              let appliedScale = appliedPlaneScale(),
              let compensation = sourceSeamCompensation(
                  session: session,
                  plane: plane,
                  appliedScale: appliedScale
              ) else {
            return
        }
        for cell in cells {
            let representationID = ObjectIdentifier(cell)
            guard session.cachedSourceRepresentations[representationID]?
                .cell === cell,
                  cell.superview != nil else {
                continue
            }
            if applySeamCompensation(
                to: cell,
                compensation: compensation
            ) {
                session.hasSourceSeamCompensationTransforms = true
            }
        }
    }

    private func cellFrameCorrectionGeometry(
        session: Session,
        plane: GridModePlaneContext
    ) -> GridModeCellFrameCorrectionGeometry? {
        guard let collectionView, let viewportView else { return nil }
        let currentTransform = collectionView.transform
        guard currentTransform.a != 0, currentTransform.d != 0 else {
            return nil
        }
        let terminalPlane = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        )
        let pivot = CGPoint(
            x: viewportView.bounds.midX,
            y: viewportView.bounds.midY
        )
        let terminalTransform = plane.crossfade.transform(
            for: terminalPlane,
            viewCenter: pivot
        )
        let currentToTerminal = CGAffineTransform(
            translationX: -pivot.x,
            y: -pivot.y
        )
        .concatenating(currentTransform.inverted())
        .concatenating(terminalTransform)
        .concatenating(CGAffineTransform(
            translationX: pivot.x,
            y: pivot.y
        ))
        return GridModeCellFrameCorrectionGeometry(
            currentToTerminal: currentToTerminal,
            terminalScreenOffsetY: terminalPlane.incomingContentOffsetY,
            destinationGeometry: visualGeometry(
                for: plane.transitionLayout.toLayout
            )
        )
    }

    /// How deeply a frame's visible sliver has crossed into the viewport,
    /// normalized over a handoff distance that shrinks as the settle lands.
    private func edgeVisibilityProgress(
        of frame: CGRect,
        in viewportBounds: CGRect,
        settleProgress: CGFloat
    ) -> CGFloat {
        guard let visibleRect = PlayerBrowserGridGeometry.visibleRect(
            frame,
            clippedTo: viewportBounds
        ) else {
            return 0
        }
        let handoffDistance = min(
            Self.edgeHandoffDistance * (1 - settleProgress),
            min(frame.width, frame.height)
        )
        guard handoffDistance > 0 else { return 1 }
        return PlayerBrowserGridCrossfade.sanitizedProgress(
            min(visibleRect.width, visibleRect.height) / handoffDistance
        )
    }

    private func cellFrameCorrection(
        for cell: UICollectionViewCell,
        destinationItem: Int,
        geometry: GridModeCellFrameCorrectionGeometry,
        settleProgress: CGFloat
    ) -> GridModeCellFrameCorrection? {
        guard let viewportView,
              let superview = cell.superview,
              let destinationScreenFrame = destinationScreenFrame(
                  destinationItem: destinationItem,
                  geometry: geometry
              ) else {
            return nil
        }
        // center/bounds ignore the live transform, so this reads the cell's
        // untransformed screen frame without resetting that transform.
        let currentScreenFrame = superview.convert(
            CGRect(
                x: cell.center.x - cell.bounds.width / 2,
                y: cell.center.y - cell.bounds.height / 2,
                width: cell.bounds.width,
                height: cell.bounds.height
            ),
            to: viewportView
        )
        let terminalScreenFrame = currentScreenFrame.applying(
            geometry.currentToTerminal
        )
        let centerDelta = CGPoint(
            x: destinationScreenFrame.midX - terminalScreenFrame.midX,
            y: destinationScreenFrame.midY - terminalScreenFrame.midY
        )
        let sizeDelta = CGSize(
            width: destinationScreenFrame.width - terminalScreenFrame.width,
            height: destinationScreenFrame.height - terminalScreenFrame.height
        )
        let destinationEdgeVisibilityProgress = edgeVisibilityProgress(
            of: destinationScreenFrame,
            in: viewportView.bounds,
            settleProgress: settleProgress
        )
        let retirementStart = PlayerBrowserGridCrossfade
            .contentFadeEndSettleProgress
        let retirementProgress = PlayerBrowserGridCrossfade
            .sanitizedProgress(
                (settleProgress - retirementStart)
                    / (1 - retirementStart)
            )
        let terminalRetirementVisibilityProgress = retirementProgress
            * edgeVisibilityProgress(
                of: terminalScreenFrame,
                in: viewportView.bounds,
                settleProgress: settleProgress
            )
        let destinationVisibilityProgress = max(
            destinationEdgeVisibilityProgress,
            terminalRetirementVisibilityProgress
        )
        guard centerDelta.x.isFinite,
              centerDelta.y.isFinite,
              sizeDelta.width.isFinite,
              sizeDelta.height.isFinite else {
            return nil
        }
        return GridModeCellFrameCorrection(
            centerDelta: centerDelta,
            sizeDelta: sizeDelta,
            destinationVisibilityProgress: destinationVisibilityProgress
        )
    }

    private func destinationScreenFrame(
        destinationItem: Int,
        geometry: GridModeCellFrameCorrectionGeometry
    ) -> CGRect? {
        guard let collectionView,
              let destinationFrame = geometry.destinationGeometry.itemFrame(
                  at: destinationItem
              ) else {
            return nil
        }
        return destinationFrame.offsetBy(
            dx: -collectionView.contentOffset.x,
            dy: -geometry.terminalScreenOffsetY
        )
    }

    private func visualGeometry(
        for layout: MobilePlayerBrowserLayout
    ) -> MobilePlayerBrowserVisualLayoutGeometry {
        collectionView?.visualGeometry(for: layout)
            ?? MobilePlayerBrowserVisualLayoutGeometry(
                layout: layout,
                mirrorsHorizontally: false
            )
    }

    private var revealMarginY: CGFloat {
        (viewportView?.bounds.height ?? 0) / 2
    }

    private func priorityCoverageBuffer(for rect: CGRect) -> CGSize {
        CGSize(width: rect.width / 4, height: rect.height / 4)
    }

    private func detailItemSet<Items: Sequence>(
        _ candidateItemIndices: Items,
        anchorItemIndex: Int?,
        maximumCount: Int
    ) -> Set<Int> where Items.Element == Int {
        guard maximumCount > 0 else { return [] }
        let candidates = Set(candidateItemIndices.filter { $0 >= 0 })
        guard candidates.count > maximumCount else { return candidates }
        return Set(PlayerBrowserGridDetailPlan(
            candidateItemIndices: Array(candidates),
            anchorItemIndex: anchorItemIndex,
            maximumCount: maximumCount
        ).itemIndices)
    }

    private func classifyDetailedSourceRepresentations(
        session: Session,
        plane: GridModePlaneContext
    ) {
        let sourceCells = viewportSourceCells(session: session)
        let selectedItems = Set(PlayerBrowserGridDetailPlan(
            candidateItemIndices: sourceCells.map { $0.indexPath.item },
            anchorItemIndex: plane.anchorTokenIndex,
            maximumCount:
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
        ).itemIndices)
        session.selectedSourceItems = selectedItems
        session.viewportSelectedSourceItems = selectedItems
        session.preparedRepresentationIDs = session
            .preparedRepresentationIDs.filter { representationID in
                sourceCells.contains {
                    ObjectIdentifier($0.cell) == representationID
                        && session.selectedSourceItems.contains(
                            $0.indexPath.item
                        )
                }
            }
    }

    @discardableResult
    private func reconcileDetailedSourceRepresentationsIfNeeded(
        session: Session,
        plane: GridModePlaneContext
    ) -> Bool {
        guard let collectionView, let viewportView else { return false }
        let viewportRect = collectionView.convert(
            viewportView.bounds,
            from: viewportView
        )
        let replacementRect = session.viewportDetailCoverage.replacementRect(
            requiredRect: viewportRect,
            buffer: priorityCoverageBuffer(for: viewportRect)
        )
        let detailCells: [SourceCellEntry]?
        let viewportCells: [SourceCellEntry]
        if let replacementRect {
            let replacementCells = sourceCells(
                session: session,
                intersecting: replacementRect
            )
            detailCells = replacementCells
            viewportCells = registeredSourceCells(
                session: session,
                intersecting: viewportRect
            )
        } else {
            detailCells = nil
            viewportCells = registeredSourceCells(
                session: session,
                intersecting: viewportRect
            )
        }
        let hasUniformLattice = latticeItemShift(
            session: session,
            plane: plane
        ) != nil
        let correctedSourceItems: [Int]
        if hasUniformLattice {
            correctedSourceItems = session.cellFrameCorrections.keys.compactMap {
                representationID in
                session.detailedSourceCellItems[representationID]
                    ?? session.cachedSourceRepresentations[representationID]?
                        .itemIndex
            }
        } else {
            correctedSourceItems = []
        }
        let retainedCorrectionItems = detailItemSet(
            correctedSourceItems,
            anchorItemIndex: plane.anchorTokenIndex,
            maximumCount:
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        let viewportItems = detailItemSet(
            viewportCells.compactMap {
                retainedCorrectionItems.contains($0.indexPath.item)
                    ? nil
                    : $0.indexPath.item
            },
            anchorItemIndex: plane.anchorTokenIndex,
            maximumCount: max(
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
                    - retainedCorrectionItems.count,
                0
            )
        )
        let viewportItemSet = retainedCorrectionItems.union(viewportItems)
        let viewportSelectionChanged = viewportItemSet
            != session.viewportSelectedSourceItems
        if detailCells == nil,
           hasUniformLattice,
           viewportItemSet.isSubset(of: session.selectedSourceItems) {
            guard viewportSelectionChanged else { return false }
            session.viewportSelectedSourceItems = viewportItemSet
            return true
        }
        let marginCandidateItems = detailCells?.compactMap {
            viewportItemSet.contains($0.indexPath.item)
                ? nil
                : $0.indexPath.item
        } ?? session.selectedSourceItems.filter {
            !viewportItemSet.contains($0)
        }
        let marginItems = detailItemSet(
            marginCandidateItems,
            anchorItemIndex: plane.anchorTokenIndex,
            maximumCount: max(
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
                    - viewportItemSet.count,
                0
            )
        )
        let selectedItems = viewportItemSet.union(marginItems)
        let selectionChanged = selectedItems != session.selectedSourceItems
        guard selectionChanged || viewportSelectionChanged else { return false }
        let removedItems = session.selectedSourceItems.subtracting(
            selectedItems
        )
        session.selectedSourceItems = selectedItems
        session.viewportSelectedSourceItems = viewportItemSet
        let remappedItems = rebuildDegradedDestinationClaims(
            session: session,
            plane: plane
        )
        clearDetailedSourceItems(
            session: session,
            itemIndices: removedItems.union(remappedItems)
        )
        return true
    }

    private func rebuildDegradedDestinationClaims(
        session: Session,
        plane: GridModePlaneContext
    ) -> Set<Int> {
        guard case .unavailable = session.latticeItemShiftResolution else {
            return []
        }
        let previousReassignments = session.reassignments
        session.reassignments.removeAll(keepingCapacity: true)
        session.assignedDestinationItems.removeAll(keepingCapacity: true)
        for sourceItem in prioritizedSourceItems(
            session.selectedSourceItems,
            session: session
        ) {
            guard let destinationItem = degradedDestinationItem(
                sourceItem: sourceItem,
                plane: plane
            ), session.assignedDestinationItems.insert(destinationItem)
                .inserted else {
                continue
            }
            session.reassignments[sourceItem] = destinationItem
        }
        return Set(previousReassignments.keys)
            .union(session.reassignments.keys)
            .filter {
                previousReassignments[$0] != session.reassignments[$0]
            }
    }

    private func refreshDetailedSourceRepresentations(
        session: Session,
        plane: GridModePlaneContext
    ) {
        session.sourceCoverageRefreshIsDirty = false
        _ = reconcileDetailedSourceRepresentationsIfNeeded(
            session: session,
            plane: plane
        )
        refreshSourceCoverageAndMaterialization(
            session: session,
            plane: plane
        )
    }

    private func refreshSourceCoverageAndMaterialization(
        session: Session,
        plane: GridModePlaneContext
    ) {
        let sourceCellEntries = refreshSourceCoverage(
            session: session,
            plane: plane
        )
        enqueueDetailedSourceMaterialization(
            session: session,
            plane: plane,
            candidates: .unpreparedSourceCells(sourceCellEntries)
        )
        reconcileForegroundDestinationEligibility(
            session: session,
            plane: plane
        )
    }

    private func destinationItem(
        session: Session,
        sourceItem: Int,
        plane: GridModePlaneContext
    ) -> Int? {
        if let destinationItem = session.reassignments[sourceItem] {
            return destinationItem
        }
        let fromLayout = plane.transitionLayout.fromLayout
        let toLayout = plane.transitionLayout.toLayout
        // Photos assigns transition content by an integer lattice shift — a
        // bijection. Proximity matching aliases neighboring cells onto the
        // same destination item at the lattice edges, drawing the same art
        // twice side by side mid-flight.
        if let shift = latticeItemShift(session: session, plane: plane) {
            let fromColumns = fromLayout.columnCount
            let toColumns = toLayout.columnCount
            guard fromColumns > 0, toColumns > 0 else { return nil }
            let destinationColumn = sourceItem % fromColumns + shift.columns
            let destinationRow = sourceItem / fromColumns + shift.rows
            guard destinationColumn >= 0,
                  destinationColumn < toColumns,
                  destinationRow >= 0 else {
                return nil
            }
            let destinationItem = destinationRow * toColumns
                + destinationColumn
            guard destinationItem < toLayout.itemCount else { return nil }
            session.reassignments[sourceItem] = destinationItem
            return destinationItem
        }
        guard let destinationItem = degradedDestinationItem(
            sourceItem: sourceItem,
            plane: plane
        ),
              !session.assignedDestinationItems.contains(destinationItem)
        else {
            return nil
        }
        session.reassignments[sourceItem] = destinationItem
        session.assignedDestinationItems.insert(destinationItem)
        return destinationItem
    }

    private func degradedDestinationItem(
        sourceItem: Int,
        plane: GridModePlaneContext
    ) -> Int? {
        let fromGeometry = visualGeometry(
            for: plane.transitionLayout.fromLayout
        )
        let toGeometry = visualGeometry(for: plane.transitionLayout.toLayout)
        guard let fromFrame = fromGeometry.itemFrame(at: sourceItem) else {
            return nil
        }
        return toGeometry.nearestItemIndex(
            to: plane.latticeMap.destinationPoint(
                fromSource: CGPoint(x: fromFrame.midX, y: fromFrame.midY)
            )
        )
    }

    private func prioritizedSourceItems<S: Sequence>(
        _ sourceItems: S,
        session: Session
    ) -> [Int] where S.Element == Int {
        sourceItems.sorted { session.sourceItemPrecedes($0, $1) }
    }

    private func latticeItemShift(
        session: Session,
        plane: GridModePlaneContext
    ) -> (columns: Int, rows: Int)? {
        switch session.latticeItemShiftResolution {
        case let .shift(columns, rows):
            return (columns, rows)
        case .unavailable:
            return nil
        case .unresolved:
            break
        }
        let fromGeometry = visualGeometry(
            for: plane.transitionLayout.fromLayout
        )
        let toGeometry = visualGeometry(for: plane.transitionLayout.toLayout)
        guard let referenceFrame = fromGeometry.itemFrame(at: 0),
              let shift = MobilePlayerBrowserGridTransition.latticeItemShift(
                  fromLayout: plane.transitionLayout.fromLayout,
                  toLayout: plane.transitionLayout.toLayout,
                  mappedLogicalCenterOfItemZero: toGeometry.mirroredPoint(
                      plane.latticeMap.destinationPoint(
                          fromSource: CGPoint(
                              x: referenceFrame.midX,
                              y: referenceFrame.midY
                          )
                      )
                  )
              ) else {
            session.latticeItemShiftResolution = .unavailable
            return nil
        }
        session.latticeItemShiftResolution = .shift(
            columns: shift.columns,
            rows: shift.rows
        )
        return shift
    }

    @discardableResult
    private func refreshSourceCoverage(
        session: Session,
        plane: GridModePlaneContext
    ) -> [SourceCellEntry] {
        sourceCoverageBuildCount += 1
        session.resetForegroundEligibilityCoverage()
        let sourceRect = sourceRepresentationRect()
        var sourceCellEntries = sourceCells(
            session: session,
            intersecting: sourceRect
        )
        sourceCellEntries.sort {
            session.sourceItemPrecedes(
                $0.indexPath.item,
                $1.indexPath.item
            )
        }
        session.pruneMarginCoverageToSourceRepresentations()
        for entry in sourceCellEntries where
            session.selectedSourceItems.contains(entry.indexPath.item)
                && !session.preparedRepresentationIDs.contains(
                    ObjectIdentifier(entry.cell)
                ) {
            _ = classifyUnpreparedSourceRepresentation(
                session: session,
                cell: entry.cell,
                sourceItem: entry.indexPath.item,
                plane: plane
            )
        }
        let existingRepresentationIDs = Set(
            sourceCellEntries.map { ObjectIdentifier($0.cell) }
        )
        sourceCellEntries.append(contentsOf: session
            .frameTrackedRepresentationIDs
            .subtracting(existingRepresentationIDs)
            .compactMap { representationID in
                guard let representation = session.cachedSourceRepresentations[
                    representationID
                ], representation.cell.superview != nil,
                representation.cell.represents(
                    tokenIndex: representation.itemIndex
                ) else {
                    return nil
                }
                return SourceCellEntry(
                    indexPath: IndexPath(
                        item: representation.itemIndex,
                        section: 0
                    ),
                    cell: representation.cell
                )
            })
        let representations = sourceCellEntries.map {
            PlayerBrowserGridSourceRepresentation(
                id: ObjectIdentifier($0.cell),
                sourceItem: $0.indexPath.item
            )
        }
        let makePlan = {
            PlayerBrowserGridSourceCoveragePlan(
                representations: representations,
                selectedSourceItems: session.selectedSourceItems,
                preparedRepresentationIDs: session.preparedRepresentationIDs
                    .subtracting(session.lockedFallbackRepresentationIDs),
                destinationBySourceItem: {
                    [weak self, weak session] sourceItem in
                    guard let self, let session else { return nil }
                    return self.destinationItem(
                        session: session,
                        sourceItem: sourceItem,
                        plane: plane
                    )
                }
            )
        }
        var plan = makePlan()
        if session.lastContentFadeAlpha > 0 {
            let newlyLockedRepresentationIDs = plan
                .fallbackRepresentationIDs.subtracting(
                    session.lockedFallbackRepresentationIDs
                )
            session.lockedFallbackRepresentationIDs.formUnion(
                newlyLockedRepresentationIDs
            )
            session.removeForegroundEligibility(
                for: newlyLockedRepresentationIDs
            )
            invalidateTransitionWork(
                session: session,
                scope: .anySourceForRepresentationIDs(
                    newlyLockedRepresentationIDs
                ),
                removePendingDetails: true
            )
            installDeferredBaseImages(
                session: session,
                for: newlyLockedRepresentationIDs
            )
            if !newlyLockedRepresentationIDs.isEmpty {
                plan = makePlan()
            }
        }
        let lostCoveredDestinationItems = session.sourceCoverage
            .coveredDestinationItems.subtracting(plan.coveredDestinationItems)
        session.sourceCoverage = plan
        let phantomCollisionItems = plan.coveredDestinationItems.filter {
            session.phantomCells[$0] != nil
        }
        if !phantomCollisionItems.isEmpty {
            // A live overlay now owns these items; leaving their phantoms up
            // draws the same art twice side by side until the next replan.
            recyclePhantomCells(
                session: session,
                retaining: Set(session.phantomCells.keys)
                    .subtracting(phantomCollisionItems)
            )
        }
        let installedImmediateDestinationCoverage =
            session.lastContentFadeAlpha > 0
            && !lostCoveredDestinationItems.isEmpty
        if installedImmediateDestinationCoverage {
            refreshDestinationPlan(session: session, plane: plane)
        }
        let representedCells = Dictionary(
            uniqueKeysWithValues: sourceCellEntries.map {
                (ObjectIdentifier($0.cell), $0.cell)
            }
        )
        for (representationID, cell) in representedCells {
            applySourceContentFade(
                session: session,
                representationID: representationID,
                cell: cell,
                alpha: session.lastContentFadeAlpha
            )
        }
        refreshPhantomShapeExclusionMask(session: session)
        if installedImmediateDestinationCoverage {
            return sourceCellEntries
        }
        if isDrainingMaterialization || session.currentPhantomPlan != nil {
            // Must not advance the plan generation: that discards every queued
            // phantom, and the replan that would re-enqueue them is the
            // lowest-priority job in the drain. installPhantomCell re-checks
            // coverage at install time, so stale queued jobs are harmless.
            session.destinationPlanRefreshIsDirty = true
            startMaterializationDisplayLinkIfNeeded()
        } else {
            refreshDestinationPlan(session: session, plane: plane)
        }
        return sourceCellEntries
    }

    private func sourceRepresentationRect() -> CGRect {
        guard let collectionView, let viewportView else { return .null }
        return collectionView.convert(viewportView.bounds, from: viewportView)
            .insetBy(dx: 0, dy: -revealMarginY)
    }

    private func detailMaterializationPriority(
        for cell: UICollectionViewCell
    ) -> MaterializationPriority {
        guard let collectionView, let viewportView else { return .deferred }
        let viewportRect = collectionView.convert(
            viewportView.bounds,
            from: viewportView
        )
        return self.cell(cell, intersects: viewportRect)
            ? .visibleRepresentation
            : .deferred
    }

    private func enqueueDetailedSourceMaterialization(
        session: Session,
        plane: GridModePlaneContext,
        candidates: DetailedSourceMaterializationCandidates
    ) {
        guard collectionView != nil, viewportView != nil else { return }
        let anchor = plane.anchorTokenIndex
        let candidateRepresentations: [SourceCellEntry]
        let includesPreparedRepresentations: Bool
        let usesEligibilityPriority: Bool
        switch candidates {
        case let .unpreparedSourceCells(sourceCellEntries):
            candidateRepresentations = sourceCellEntries
            includesPreparedRepresentations = false
            usesEligibilityPriority = false
        case let .eligibleRepresentationIDs(representationIDs):
            candidateRepresentations = representationIDs.compactMap {
                representationID in
                guard let representation = session
                    .cachedSourceRepresentations[representationID] else {
                    return nil
                }
                return SourceCellEntry(
                    indexPath: IndexPath(
                        item: representation.itemIndex,
                        section: 0
                    ),
                    cell: representation.cell
                )
            }
            includesPreparedRepresentations = true
            usesEligibilityPriority = true
        }
        let representations = candidateRepresentations.filter {
            let representationID = ObjectIdentifier($0.cell)
            return session.selectedSourceItems.contains($0.indexPath.item)
                && (includesPreparedRepresentations
                    || !session.preparedRepresentationIDs.contains(
                        representationID
                    ))
                && (includesPreparedRepresentations
                    || session.detailedSourceCellItems[representationID]
                        != $0.indexPath.item)
                && !session.lockedFallbackRepresentationIDs.contains(
                    representationID
                )
        }.sorted { lhs, rhs in
            let lhsDistance = abs(lhs.indexPath.item - anchor)
            let rhsDistance = abs(rhs.indexPath.item - anchor)
            if lhsDistance == rhsDistance {
                return lhs.indexPath.item < rhs.indexPath.item
            }
            return lhsDistance < rhsDistance
        }
        for representation in representations {
            let representationID = ObjectIdentifier(representation.cell)
            let priority: MaterializationPriority
            if usesEligibilityPriority {
                priority = session.currentViewportRepresentationIDs.contains(
                    representationID
                )
                    ? .visibleRepresentation
                    : .deferred
            } else {
                priority = detailMaterializationPriority(
                    for: representation.cell
                )
            }
            enqueueMaterialization(
                session: session,
                priority: priority,
                kind: .detail(
                    planeID: plane.id,
                    contentGeneration: session.transitionContentGeneration,
                    representationID: representationID,
                    sourceItem: representation.indexPath.item
                )
            )
        }
    }

    private func clearDetailedSourceItems(
        session: Session,
        itemIndices: Set<Int>
    ) {
        guard !itemIndices.isEmpty else { return }
        let cells = itemIndices.flatMap {
            sourceCells(session: session, at: $0)
        }
        let cellIDs = Set(cells.map(ObjectIdentifier.init))
        session.preparedRepresentationIDs.subtract(cellIDs)
        if session.lastContentFadeAlpha > 0 {
            session.lockedFallbackRepresentationIDs.formUnion(cellIDs)
        }
        session.detailedSourceCellItems = session
            .detailedSourceCellItems.filter {
                !itemIndices.contains($0.value)
            }
        session.removeForegroundEligibility(for: cellIDs)
        invalidateTransitionWork(
            session: session,
            scope: .sourceItems(itemIndices),
            removePendingDetails: true
        )
        removeCellFrameCorrections(session: session, for: cells)
        for cell in cells {
            cell.finishTransitionContent(
                preservingCarryover: cell.hasCarryoverContent
            )
            applySourceContentFade(
                session: session,
                representationID: ObjectIdentifier(cell),
                cell: cell,
                alpha: session.lastContentFadeAlpha
            )
        }
    }

    private func phantomCellBudget(
        destinationGeometry: MobilePlayerBrowserVisualLayoutGeometry,
        priorityRect: CGRect,
        coveredDestinationItems: Set<Int>,
        maximumCount: Int
    ) -> Int {
        guard maximumCount > 0 else { return 0 }
        var count = 0
        for itemIndex in destinationGeometry.layout.candidateItemIndices(
            intersecting: priorityRect
        ) where !coveredDestinationItems.contains(itemIndex) {
            guard destinationGeometry.itemFrame(at: itemIndex)?
                .intersects(priorityRect) == true else {
                continue
            }
            count += 1
            if count == maximumCount { return count }
        }
        return count
    }

    private func destinationRects(
        session: Session,
        plane: GridModePlaneContext
    ) -> (requiredCoverage: CGRect, priority: CGRect)? {
        guard let viewportView else { return nil }
        let terminalPlane = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        )
        let marginY = revealMarginY
        return (
            CGRect(
                x: -viewportView.bounds.width / 4,
                y: terminalPlane.incomingContentOffsetY - marginY,
                width: viewportView.bounds.width * 1.5,
                height: viewportView.bounds.height + marginY * 2
            ),
            CGRect(
                x: 0,
                y: terminalPlane.incomingContentOffsetY,
                width: viewportView.bounds.width,
                height: viewportView.bounds.height
            )
        )
    }

    private func foregroundDestinationEligibilityContext(
        session: Session,
        plane: GridModePlaneContext
    ) -> ForegroundDestinationEligibilityContext? {
        guard let collectionView,
              let viewportView,
              let terminalViewportRect = destinationRects(
                  session: session,
                  plane: plane
              )?.priority else {
            return nil
        }
        let currentViewportRect = collectionView.convert(
            viewportView.bounds,
            from: viewportView
        )
        return ForegroundDestinationEligibilityContext(
            currentViewportRect: currentViewportRect,
            currentPriorityRect: currentViewportRect,
            terminalViewportRect: terminalViewportRect,
            destinationGeometry: visualGeometry(
                for: plane.transitionLayout.toLayout
            )
        )
    }

    private func replacementForegroundDestinationEligibilityContext(
        session: Session,
        plane: GridModePlaneContext
    ) -> ForegroundDestinationEligibilityContext? {
        guard let context = foregroundDestinationEligibilityContext(
            session: session,
            plane: plane
        ) else {
            return nil
        }
        let currentChanged = replaceForegroundCoverageIfNeeded(
            &session.foregroundCurrentViewportCoverage,
            requiredRect: context.currentViewportRect
        )
        let terminalChanged = replaceForegroundCoverageIfNeeded(
            &session.foregroundTerminalViewportCoverage,
            requiredRect: context.terminalViewportRect
        )
        guard currentChanged || terminalChanged,
              let currentViewportRect = session
                .foregroundCurrentViewportCoverage.installedRect,
              let terminalViewportRect = session
                .foregroundTerminalViewportCoverage.installedRect else {
            return nil
        }
        return ForegroundDestinationEligibilityContext(
            currentViewportRect: currentViewportRect,
            currentPriorityRect: context.currentPriorityRect,
            terminalViewportRect: terminalViewportRect,
            destinationGeometry: context.destinationGeometry
        )
    }

    private func replaceForegroundCoverageIfNeeded(
        _ coverage: inout PlayerBrowserGridPhantomCoverage,
        requiredRect: CGRect
    ) -> Bool {
        let buffer = priorityCoverageBuffer(for: requiredRect)
        let targetCoverageRect = requiredRect.insetBy(
            dx: -buffer.width,
            dy: -buffer.height
        )
        if let installedRect = coverage.installedRect {
            let exceedsWidth = installedRect.width
                > targetCoverageRect.width + buffer.width
            let exceedsHeight = installedRect.height
                > targetCoverageRect.height + buffer.height
            if exceedsWidth || exceedsHeight {
                coverage.reset()
            }
        }
        return coverage.replacementRect(
            requiredRect: requiredRect,
            buffer: buffer
        ) != nil
    }

    private func cachedForegroundDestinationEligibilityContext(
        session: Session,
        plane: GridModePlaneContext
    ) -> ForegroundDestinationEligibilityContext? {
        guard let context = foregroundDestinationEligibilityContext(
            session: session,
            plane: plane
        ) else {
            return nil
        }
        return ForegroundDestinationEligibilityContext(
            currentViewportRect: session.foregroundCurrentViewportCoverage
                .installedRect ?? context.currentViewportRect,
            currentPriorityRect: context.currentPriorityRect,
            terminalViewportRect: session.foregroundTerminalViewportCoverage
                .installedRect ?? context.terminalViewportRect,
            destinationGeometry: context.destinationGeometry
        )
    }

    private func foregroundDestinationEligibility(
        destinationItem: Int,
        cell: MobilePlayerCollectionBrowserCell,
        context: ForegroundDestinationEligibilityContext?
    ) -> ForegroundDestinationEligibility? {
        guard let context else { return nil }
        if self.cell(cell, intersects: context.currentPriorityRect) {
            return .current
        }
        if self.cell(cell, intersects: context.currentViewportRect) {
            return .terminal
        }
        guard let destinationFrame = context.destinationGeometry.itemFrame(
            at: destinationItem
        ),
        PlayerBrowserGridGeometry.visibleRect(
            destinationFrame,
            clippedTo: context.terminalViewportRect
        ) != nil else {
            return nil
        }
        return .terminal
    }

    private func reconcileForegroundDestinationEligibility(
        session: Session,
        plane: GridModePlaneContext
    ) {
        guard let context = replacementForegroundDestinationEligibilityContext(
            session: session,
            plane: plane
        ) else {
            return
        }
        foregroundEligibilityReconciliationCount += 1
        reconcileTransitionImageLoadEligibility(
            session: session,
            plane: plane,
            context: context
        )
        reconcilePhantomImageLoadEligibility(
            session: session,
            context: context
        )
    }

    private func reconcileTransitionImageLoadEligibility(
        session: Session,
        plane: GridModePlaneContext,
        context: ForegroundDestinationEligibilityContext?
    ) {
        var eligibleRepresentationIDs = Set<ObjectIdentifier>()
        var currentRepresentationIDs = Set<ObjectIdentifier>()
        for (representationID, representation) in
            session.cachedSourceRepresentations {
            guard session.selectedSourceItems.contains(
                representation.itemIndex
            ),
            !session.lockedFallbackRepresentationIDs.contains(
                representationID
            ),
            representation.cell.represents(
                tokenIndex: representation.itemIndex
            ),
            let destinationItem = destinationItem(
                session: session,
                sourceItem: representation.itemIndex,
                plane: plane
            ) else {
                continue
            }
            guard let eligibility = foregroundDestinationEligibility(
                destinationItem: destinationItem,
                cell: representation.cell,
                context: context
            ) else {
                continue
            }
            eligibleRepresentationIDs.insert(representationID)
            if eligibility == .current {
                currentRepresentationIDs.insert(representationID)
            }
        }
        let previousEligibleRepresentationIDs = session
            .foregroundEligibleRepresentationIDs
        let removedRepresentationIDs = previousEligibleRepresentationIDs
            .subtracting(
                eligibleRepresentationIDs
            )
        let addedRepresentationIDs = eligibleRepresentationIDs.subtracting(
            previousEligibleRepresentationIDs
        )
        let priorityChangedRepresentationIDs = session
            .lastReconciledCurrentViewportRepresentationIDs
            .symmetricDifference(currentRepresentationIDs)
        session.foregroundEligibleRepresentationIDs =
            eligibleRepresentationIDs
        session.currentViewportRepresentationIDs =
            currentRepresentationIDs
        session.lastReconciledCurrentViewportRepresentationIDs =
            currentRepresentationIDs
        for representationID in priorityChangedRepresentationIDs {
            let priority: MaterializationPriority =
                currentRepresentationIDs.contains(representationID)
                ? .visibleRepresentation
                : .deferred
            materializationQueue.reprioritizeDetails(
                sessionID: session.id,
                planeID: plane.id,
                contentGeneration: session.transitionContentGeneration,
                representationID: representationID,
                priority: priority
            )
            if eligibleRepresentationIDs.contains(representationID),
               let load = session.transitionImageLoads[representationID] {
                materializationQueue
                    .reprioritizeTransitionImageCompletion(
                        sessionID: session.id,
                        loadID: load.id,
                        representationID: representationID,
                        priority: priority
                    )
            }
        }
        invalidateTransitionWork(
            session: session,
            scope: .anySourceForRepresentationIDs(
                removedRepresentationIDs
            ),
            removePendingDetails: false
        )
        enqueueDetailedSourceMaterialization(
            session: session,
            plane: plane,
            candidates: .eligibleRepresentationIDs(addedRepresentationIDs)
        )
    }

    private func reconcilePhantomImageLoadEligibility(
        session: Session,
        context: ForegroundDestinationEligibilityContext?,
        cells: [Int: MobilePlayerCollectionBrowserCell]? = nil
    ) {
        for (destinationItem, cell) in cells ?? session.phantomCells {
            let representationID = ObjectIdentifier(cell)
            guard let eligibility = foregroundDestinationEligibility(
                destinationItem: destinationItem,
                cell: cell,
                context: context
            ) else {
                materializationQueue.removePromotion(
                    sessionID: session.id,
                    contentGeneration: session.transitionContentGeneration,
                    representationID: representationID,
                    tokenIndex: destinationItem
                )
                cell.demoteImageLoadToCachedOnlyIfNeeded(
                    tokenIndex: destinationItem
                )
                continue
            }
            if cell.usesForegroundImageLoading {
                materializationQueue.removePromotion(
                    sessionID: session.id,
                    contentGeneration: session.transitionContentGeneration,
                    representationID: representationID,
                    tokenIndex: destinationItem
                )
                continue
            }
            let priority: MaterializationPriority = eligibility == .current
                ? .visibleRepresentation
                : .deferred
            materializationQueue.reprioritizePromotion(
                sessionID: session.id,
                contentGeneration: session.transitionContentGeneration,
                representationID: representationID,
                tokenIndex: destinationItem,
                priority: priority
            )
            enqueueMaterialization(
                session: session,
                priority: priority,
                kind: .promotion(
                    contentGeneration: session.transitionContentGeneration,
                    representationID: representationID,
                    tokenIndex: destinationItem
                )
            )
        }
    }

    private func extendDestinationCoverageIfNeeded(
        session: Session,
        plane: GridModePlaneContext
    ) {
        guard let rects = destinationRects(session: session, plane: plane)
        else {
            return
        }
        let replacementRect = session.phantomCoverage.replacementRect(
            requiredRect: rects.requiredCoverage,
            buffer: CGSize(width: 0, height: revealMarginY)
        )
        let priorityCoverageRect = session
            .destinationPlanePriorityCoverage.replacementRect(
                requiredRect: rects.priority,
                buffer: priorityCoverageBuffer(for: rects.priority)
            )
        guard replacementRect != nil || priorityCoverageRect != nil else {
            return
        }
        refreshDestinationPlan(
            session: session,
            plane: plane,
            coverageRect: replacementRect
                ?? session.phantomCoverage.installedRect
                ?? rects.requiredCoverage,
            priorityRect: rects.priority,
            visualCellRect: priorityCoverageRect
                ?? session.destinationPlanePriorityCoverage.installedRect
                ?? rects.priority
        )
    }

    private func refreshDestinationPlan(
        session: Session,
        plane: GridModePlaneContext
    ) {
        guard let rects = destinationRects(session: session, plane: plane)
        else {
            return
        }
        refreshDestinationPlan(
            session: session,
            plane: plane,
            coverageRect: session.phantomCoverage.installedRect
                ?? rects.requiredCoverage,
            priorityRect: rects.priority,
            visualCellRect: session.destinationPlanePriorityCoverage
                .installedRect ?? rects.priority
        )
    }

    private func refreshDestinationPlan(
        session: Session,
        plane: GridModePlaneContext,
        coverageRect: CGRect,
        priorityRect: CGRect,
        visualCellRect: CGRect
    ) {
        let geometry = visualGeometry(for: plane.transitionLayout.toLayout)
        let coveredItems = session.sourceCoverage.coveredDestinationItems
        let maximumCellCount = phantomCellBudget(
            destinationGeometry: geometry,
            priorityRect: visualCellRect,
            coveredDestinationItems: coveredItems,
            maximumCount:
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: plane.latticeMap,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: coveredItems,
            maximumCellCount: maximumCellCount
        )
        advanceDestinationPlanGeneration(session: session)
        session.managedCellPlanRefreshIsPending = false
        session.destinationPlanRefreshIsDirty = false
        session.currentPhantomPlan = plan
        session.phantomShapeRefreshIsDirty = false
        destinationPlanBuildCount += 1
        let generation = session.destinationPlaneCellPlanGeneration
        let retainedItems = Set(plan.cellCandidates.map(
            \.destinationItemIndex
        )).subtracting(coveredItems)
        recyclePhantomCells(session: session, retaining: retainedItems)
        replacePhantomShapeCoverage(
            session: session,
            plan: plan,
            installedItemIndices: Set(session.phantomCells.keys)
        )
        for candidate in plan.cellCandidates where
            !coveredItems.contains(candidate.destinationItemIndex)
                && session.phantomCells[candidate.destinationItemIndex] == nil {
            let priority: MaterializationPriority = candidate.destinationFrame
                .intersects(priorityRect)
                ? .destinationViewport
                : .deferred
            enqueueMaterialization(
                session: session,
                priority: priority,
                kind: .destination(
                    planeID: plane.id,
                    contentGeneration: session.transitionContentGeneration,
                    planGeneration: generation,
                    candidate: candidate,
                    requiredImageQuality: plane.toMode.requiredImageQuality
                )
            )
        }
    }

    private func extendSourceCoverageIfNeeded(
        session: Session,
        layout: MobilePlayerBrowserLayout,
        targetPlaneID: UUID? = nil,
        installsStructuralCoverage: Bool = true
    ) {
        guard session.plane?.id == targetPlaneID,
              let collectionView,
              let viewportView else {
            return
        }
        let requiredRect = collectionView.convert(
            viewportView.bounds,
            from: viewportView
        )
        let replacementRect = session.sourceOverscanCoverage.replacementRect(
            requiredRect: requiredRect,
            buffer: CGSize(
                width: requiredRect.width / 2,
                height: requiredRect.height / 2
            )
        )
        let priorityCoverageRect = session
            .sourcePlanePriorityCoverage.replacementRect(
                requiredRect: requiredRect,
                buffer: priorityCoverageBuffer(for: requiredRect)
            )
        guard replacementRect != nil || priorityCoverageRect != nil else {
            return
        }
        let coverageRect = replacementRect
            ?? session.sourceOverscanCoverage.installedRect
            ?? requiredRect
        let visualCellRect = priorityCoverageRect
            ?? session.sourcePlanePriorityCoverage.installedRect
            ?? requiredRect
        let geometry = visualGeometry(for: layout)
        let managedItems = existingManagedSourceItemIndices(
            intersecting: visualCellRect,
            layout: layout
        )
        let retainedItems = Set(session.sourceOverscanCells.keys.filter {
            !managedItems.contains($0)
                && geometry.itemFrame(at: $0)?.intersects(visualCellRect)
                    == true
        })
        let didRecycle = recycleSourceOverscanCells(
            session: session,
            retaining: retainedItems
        )
        if didRecycle,
           session.currentPhantomPlan != nil,
           let plane = session.plane {
            refreshDetailedSourceRepresentations(
                session: session,
                plane: plane
            )
        }
        let coveredItems = existingManagedSourceItemIndices(
            intersecting: coverageRect,
            layout: layout
        ).union(session.sourceOverscanCells.keys)
        let maximumCellCount = phantomCellBudget(
            destinationGeometry: geometry,
            priorityRect: visualCellRect,
            coveredDestinationItems: coveredItems,
            maximumCount: max(
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
                    - session.sourceOverscanCells.count,
                0
            )
        )
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: coverageRect,
            priorityRect: requiredRect,
            coveredDestinationItems: coveredItems,
            maximumCellCount: maximumCellCount
        )
        advanceSourcePlanGeneration(session: session)
        if session.plane == nil {
            session.managedCellPlanRefreshIsPending = false
        }
        if installsStructuralCoverage {
            session.currentPhantomPlan = plan
            session.phantomShapeRefreshIsDirty = false
        }
        let generation = session.sourcePlaneCellPlanGeneration
        if installsStructuralCoverage {
            replacePhantomShapeCoverage(
                session: session,
                plan: plan,
                installedItemIndices: Set(session.sourceOverscanCells.keys)
            )
        }
        for candidate in plan.cellCandidates where
            session.sourceOverscanCells[candidate.destinationItemIndex] == nil {
            let priority: MaterializationPriority = candidate.sourceFrame
                .intersects(requiredRect)
                ? .sourceViewport
                : .deferred
            enqueueMaterialization(
                session: session,
                priority: priority,
                kind: .source(
                    planeID: targetPlaneID,
                    contentGeneration: session.transitionContentGeneration,
                    planGeneration: generation,
                    candidate: candidate
                )
            )
        }
    }

    private func installSourceOverscanCell(
        session: Session,
        candidate: PlayerBrowserGridPhantomCandidate,
        targetPlaneID: UUID?
    ) {
        guard let collectionView,
              session.plane?.id == targetPlaneID,
              session.sourceOverscanCells[candidate.destinationItemIndex]
                == nil,
              collectionView.cellForItem(at: IndexPath(
                  item: candidate.destinationItemIndex,
                  section: 0
              )) == nil else {
            return
        }
        let itemIndex = candidate.destinationItemIndex
        let cell = MobilePlayerCollectionBrowserCell(
            frame: candidate.sourceFrame
        )
        cell.setTransitionPlaceholderTone(true)
        contentAccess.configureCell(
            cell,
            IndexPath(item: itemIndex, section: 0),
            .sourceOverscan
        )
        let cellID = ObjectIdentifier(cell)
        if session.lastContentFadeAlpha > 0 {
            session.lockedFallbackRepresentationIDs.insert(cellID)
        }
        applySourcePresentation(
            cell: cell,
            role: .awaitingClassification,
            visibleAlpha: session.lastContentFadeAlpha
        )
        insertCellAbovePhantomShape(
            session: session,
            cell: cell,
            role: .sourceOverscan
        )
        if let appliedScale = appliedPlaneScale(),
           let compensation = currentSourceSeamCompensation(
               session: session,
               appliedScale: appliedScale
           ),
           applySeamCompensation(to: cell, compensation: compensation) {
            session.hasSourceSeamCompensationTransforms = true
        }
        session.sourceOverscanCells[itemIndex] = cell
        registerSourceRepresentation(
            session: session,
            cell: cell,
            itemIndex: itemIndex
        )
        invalidateViewportPromotion(session: session)
        if session.plane == nil {
            session.phantomShapeRefreshIsDirty = true
            enqueueVisiblePromotion(
                session: session,
                cell: cell,
                tokenIndex: itemIndex
            )
        }
        if session.plane != nil {
            markSourceCoverageRefreshDirty(session: session)
        }
    }

    @discardableResult
    private func recycleSourceOverscanCell(
        session: Session,
        at itemIndex: Int,
        performsIndividualCleanup: Bool = true
    ) -> Bool {
        guard let cell = session.sourceOverscanCells.removeValue(
            forKey: itemIndex
        ) else {
            return false
        }
        let cellID = ObjectIdentifier(cell)
        materializationQueue.removePromotion(
            sessionID: session.id,
            contentGeneration: session.transitionContentGeneration,
            representationID: cellID,
            tokenIndex: itemIndex
        )
        if performsIndividualCleanup {
            invalidateTransitionWork(
                session: session,
                scope: .representationKeys([TransitionRepresentationKey(
                    representationID: cellID,
                    sourceItem: itemIndex
                )]),
                removePendingDetails: true
            )
        }
        session.unregisterSourceRepresentation(cellID)
        if performsIndividualCleanup {
            removeCellFrameCorrection(session: session, for: cell)
        }
        cell.prepareForGridModePhantomReuse()
        cell.removeFromSuperview()
        return true
    }

    @discardableResult
    private func recycleSourceOverscanCells(
        session: Session,
        retaining itemIndices: Set<Int>
    ) -> Bool {
        let recycledItems = session.sourceOverscanCells.keys.filter {
            !itemIndices.contains($0)
        }
        let representations = Set(recycledItems.compactMap { itemIndex in
            session.sourceOverscanCells[itemIndex].map {
                TransitionRepresentationKey(
                    representationID: ObjectIdentifier($0),
                    sourceItem: itemIndex
                )
            }
        })
        let recycledCells = recycledItems.compactMap {
            session.sourceOverscanCells[$0]
        }
        invalidateTransitionWork(
            session: session,
            scope: .representationKeys(representations),
            removePendingDetails: true
        )
        for itemIndex in recycledItems {
            recycleSourceOverscanCell(
                session: session,
                at: itemIndex,
                performsIndividualCleanup: false
            )
        }
        removeCellFrameCorrections(session: session, for: recycledCells)
        if !recycledItems.isEmpty {
            invalidateViewportPromotion(session: session)
        }
        return !recycledItems.isEmpty
    }

    private func installPhantomCell(
        session: Session,
        candidate: PlayerBrowserGridPhantomCandidate,
        requiredImageQuality: CollectionBrowseImageQuality
    ) {
        guard session.phantomCells[candidate.destinationItemIndex] == nil,
              !session.sourceCoverage.coveredDestinationItems.contains(
                  candidate.destinationItemIndex
              ) else {
            return
        }
        let phantom = session.reusablePhantomCells.popLast()
            ?? MobilePlayerCollectionBrowserCell(frame: candidate.sourceFrame)
        phantom.frame = candidate.sourceFrame
        phantom.setTransitionPlaceholderTone(true)
        contentAccess.configureCell(
            phantom,
            IndexPath(
                item: candidate.destinationItemIndex,
                section: 0
            ),
            .destinationPhantom(
                requiredImageQuality: requiredImageQuality
            )
        )
        insertCellAbovePhantomShape(
            session: session,
            cell: phantom,
            role: .destinationPhantom
        )
        if let plane = session.plane,
           let appliedScale = appliedPlaneScale(),
           let compensation = phantomSeamCompensation(
               session: session,
               plane: plane,
               appliedScale: appliedScale
           ),
           applySeamCompensation(to: phantom, compensation: compensation) {
            session.hasPhantomSeamCompensationTransforms = true
        }
        session.phantomCells[candidate.destinationItemIndex] = phantom
        session.phantomShapeRefreshIsDirty = true
        // Must not re-arm the viewport promotion sweep: it only promotes source
        // representations, so a phantom install cannot change its outcome, but
        // re-arming preempts the phantoms still queued behind it.
        if let plane = session.plane {
            reconcileForegroundDestinationEligibility(
                session: session,
                plane: plane
            )
            reconcilePhantomImageLoadEligibility(
                session: session,
                context: cachedForegroundDestinationEligibilityContext(
                    session: session,
                    plane: plane
                ),
                cells: [candidate.destinationItemIndex: phantom]
            )
        }
    }

    private func recyclePhantomCells(
        session: Session,
        retaining itemIndices: Set<Int>
    ) {
        let recycledItems = session.phantomCells.keys.filter {
            !itemIndices.contains($0)
        }
        for itemIndex in recycledItems {
            guard let phantom = session.phantomCells.removeValue(
                forKey: itemIndex
            ) else {
                continue
            }
            materializationQueue.removePromotion(
                sessionID: session.id,
                contentGeneration: session.transitionContentGeneration,
                representationID: ObjectIdentifier(phantom),
                tokenIndex: itemIndex
            )
            phantom.prepareForGridModePhantomReuse()
            phantom.removeFromSuperview()
            session.reusablePhantomCells.append(phantom)
        }
        if !recycledItems.isEmpty {
            invalidateViewportBasePromotion(session: session)
        }
    }

    private func insertCellAbovePhantomShape(
        session: Session,
        cell: MobilePlayerCollectionBrowserCell,
        role: ManualCellLayerRole
    ) {
        guard let collectionView else { return }
        if role == .sourceOverscan {
            let manualCellIDs = Set(
                session.sourceOverscanCells.values.map(ObjectIdentifier.init)
                    + session.phantomCells.values.map(ObjectIdentifier.init)
            )
            if let topmostManualCell = collectionView.subviews.last(where: {
                manualCellIDs.contains(ObjectIdentifier($0))
            }) {
                collectionView.insertSubview(
                    cell,
                    aboveSubview: topmostManualCell
                )
                return
            }
        }
        if let phantomShapeView = session.phantomShapeView,
           phantomShapeView.superview === collectionView {
            collectionView.insertSubview(cell, aboveSubview: phantomShapeView)
        } else {
            collectionView.insertSubview(cell, at: 0)
        }
    }

    private func replacePhantomShapeCoverage(
        session: Session,
        plan: PlayerBrowserGridPhantomPlan,
        installedItemIndices: Set<Int>
    ) {
        let pendingCandidates = plan.cellCandidates.filter {
            !installedItemIndices.contains($0.destinationItemIndex)
        }
        guard let shapeCoverage = plan.shapeCoverage else {
            replacePhantomShapeCoverage(
                session: session,
                candidates: pendingCandidates + plan.shapeCandidates,
                shapeCoverage: nil
            )
            return
        }
        let pendingFrames = pendingCandidates.map(\.sourceFrame)
        let excludedFrames = shapeCoverage.excludedFrames.filter {
            !pendingFrames.contains($0)
        }
        replacePhantomShapeCoverage(
            session: session,
            candidates: plan.shapeCandidates,
            shapeCoverage: shapeCoverage.replacingExcludedFrames(
                excludedFrames
            )
        )
    }

    private func phantomShapeOccupantFrames(
        session: Session
    ) -> [PhantomShapeOccupantKey: CGRect] {
        guard let collectionView else { return [:] }
        var frames = [PhantomShapeOccupantKey: CGRect]()
        if session.plane == nil {
            for (itemIndex, cell) in session.sourceOverscanCells
            where cell.superview != nil
                && cell.represents(tokenIndex: itemIndex) {
                frames[.source(ObjectIdentifier(cell))] = cell.convert(
                    cell.bounds,
                    to: collectionView
                )
            }
            for cell in visibleBrowserCells {
                guard let indexPath = collectionView.indexPath(for: cell),
                      cell.represents(tokenIndex: indexPath.item) else {
                    continue
                }
                frames[.source(ObjectIdentifier(cell))] = cell.convert(
                    cell.bounds,
                    to: collectionView
                )
            }
            return frames
        }
        for (itemIndex, cell) in session.phantomCells
        where cell.superview != nil && cell.represents(tokenIndex: itemIndex) {
            frames[.phantom(itemIndex)] = cell.convert(
                cell.bounds,
                to: collectionView
            )
        }
        let transitionVisualRepresentationIDs = Set(
            session.sourceCoverage.readyDestinationByRepresentation.keys
        ).union(
            session.cellFrameCorrections.keys
        ).filter {
            sourceRepresentationOwnsTransitionVisual(
                session: session,
                representationID: $0
            )
        }
        let sourceOccupantRepresentationIDs = transitionVisualRepresentationIDs
            .union(session.marginCoverageRepresentationIDs)
        for representationID in sourceOccupantRepresentationIDs {
            guard let representation = session.cachedSourceRepresentations[
                representationID
            ], representation.cell.superview != nil,
            representation.cell.represents(
                tokenIndex: representation.itemIndex
            ) else {
                continue
            }
            frames[.source(representationID)] = representation.cell.convert(
                representation.cell.bounds,
                to: collectionView
            )
        }
        return frames
    }

    private func replacePhantomShapeCoverage(
        session: Session,
        candidates: [PlayerBrowserGridPhantomCandidate],
        shapeCoverage: PlayerBrowserGridPhantomShapeCoverage?
    ) {
        guard let collectionView else { return }
        guard !candidates.isEmpty || shapeCoverage?.coverageBounds != nil else {
            if let placeholderView = session.phantomShapeView
                as? PhantomShapeView {
                placeholderView.rawCandidateFrames.removeAll(
                    keepingCapacity: true
                )
                placeholderView.rawShapeCoverage = nil
                placeholderView.renderedCoverageBounds = nil
                placeholderView.renderedShapeExclusionFrames.removeAll(
                    keepingCapacity: true
                )
                placeholderView.renderedShapeExclusionPath = nil
                placeholderView.maskedCoverageBounds = nil
                placeholderView.renderedOccupantFrames.removeAll(
                    keepingCapacity: true
                )
                placeholderView.layer.mask = nil
                placeholderView.isHidden = true
            }
            return
        }
        let placeholderView: PhantomShapeView
        if let existingView = session.phantomShapeView as? PhantomShapeView {
            placeholderView = existingView
        } else {
            session.phantomShapeView?.removeFromSuperview()
            placeholderView = PhantomShapeView(frame: .zero)
            session.phantomShapeView = placeholderView
        }
        placeholderView.rawCandidateFrames = candidates.map(\.sourceFrame)
        placeholderView.rawShapeCoverage = shapeCoverage
        if placeholderView.superview !== collectionView
            || collectionView.subviews.first !== placeholderView {
            collectionView.insertSubview(placeholderView, at: 0)
        }
        renderPhantomShapeStructure(
            session: session,
            in: placeholderView,
            rebuildsTopology: true
        )
        refreshPhantomShapeExclusionMask(session: session)
    }

    private func renderPhantomShapeStructure(
        session: Session,
        in placeholderView: PhantomShapeView,
        rebuildsTopology: Bool
    ) {
        let frameCompensation = currentPhantomShapeFrameCompensation(
            session: session
        )
        guard rebuildsTopology || placeholderView.renderedFrameCompensation
            != frameCompensation else {
            return
        }
        phantomShapeStructureBuildCount += 1
        let candidateFrames = placeholderView.rawCandidateFrames.map {
            frameCompensation?.applying(to: $0) ?? $0
        }
        let candidateBounds = candidateFrames.first.map { first in
            candidateFrames.dropFirst().reduce(first) { $0.union($1) }
        }
        let shapeBounds = placeholderView.rawShapeCoverage?.coverageBounds.map {
            frameCompensation?.applying(to: $0) ?? $0
        }
        let shapeExclusionFrames = placeholderView.rawShapeCoverage?
            .excludedFrames.map {
                frameCompensation?.applying(to: $0) ?? $0
            } ?? []
        let coverageBounds: CGRect
        if let candidateBounds, let shapeBounds {
            coverageBounds = candidateBounds.union(shapeBounds)
        } else if let candidateBounds {
            coverageBounds = candidateBounds
        } else if let shapeBounds {
            coverageBounds = shapeBounds
        } else {
            placeholderView.isHidden = true
            placeholderView.renderedFrameCompensation = frameCompensation
            placeholderView.renderedCoverageBounds = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        placeholderView.isHidden = false
        placeholderView.frame = coverageBounds
        if placeholderView.renderedShapeExclusionFrames
            != shapeExclusionFrames {
            placeholderView.maskedCoverageBounds = nil
        }
        placeholderView.renderedShapeExclusionFrames = shapeExclusionFrames
        if shapeExclusionFrames.isEmpty {
            placeholderView.renderedShapeExclusionPath = nil
        } else {
            let exclusionPath = PhantomShapePathRenderer.path(
                frames: shapeExclusionFrames,
                relativeTo: coverageBounds
            )
            placeholderView.renderedShapeExclusionPath =
                PhantomShapePathRenderer.exclusionMaskPath(
                    exclusionPath: exclusionPath,
                    maskBounds: placeholderView.bounds
                )
        }
        if rebuildsTopology {
            placeholderView.reset(
                fillColor: mobilePlayerBrowserPlaceholderToneColor.cgColor
            )
            placeholderView.renderedOccupantFrames.removeAll(
                keepingCapacity: true
            )
            placeholderView.maskedCoverageBounds = nil
        }
        if let shapeCoverage = placeholderView.rawShapeCoverage {
            installPhantomShapeCoverage(
                shapeCoverage,
                coverageBounds: coverageBounds,
                in: placeholderView,
                frameCompensation: frameCompensation,
                configuresTopology: rebuildsTopology
            )
        }
        if !candidateFrames.isEmpty {
            if rebuildsTopology {
                placeholderView.candidateLayer.isHidden = false
            }
            placeholderView.candidateLayer.frame = placeholderView.bounds
            placeholderView.candidateLayer.path = PhantomShapePathRenderer.path(
                frames: candidateFrames,
                relativeTo: coverageBounds
            )
        }
        placeholderView.renderedFrameCompensation = frameCompensation
        placeholderView.renderedCoverageBounds = coverageBounds
    }

    private func installPhantomShapeCoverage(
        _ coverage: PlayerBrowserGridPhantomShapeCoverage,
        coverageBounds: CGRect,
        in placeholderView: PhantomShapeView,
        frameCompensation: PhantomShapeFrameCompensation?,
        configuresTopology: Bool
    ) {
        let adjustedFrame: (CGRect) -> CGRect = { frame in
            frameCompensation?.applying(to: frame) ?? frame
        }
        switch coverage {
        case let .repeatedRows(rows):
            let firstRowFrames = rows.firstRowFrames.map(adjustedFrame)
            if rows.rowCount > 0, let firstFrame = firstRowFrames.first {
                let rowBounds = firstRowFrames.dropFirst().reduce(
                    firstFrame
                ) { $0.union($1) }
                if configuresTopology {
                    placeholderView.repeatedRowsLayer.isHidden = false
                    placeholderView.repeatedRowsLayer.masksToBounds = true
                    placeholderView.repeatedRowsLayer.instanceCount =
                        rows.rowCount
                    placeholderView.repeatedRowsLayer.instanceTransform =
                        CATransform3DMakeTranslation(0, rows.rowPitch, 0)
                }
                placeholderView.repeatedRowsLayer.frame =
                    placeholderView.bounds
                placeholderView.repeatedRowLayer.frame = rowBounds.offsetBy(
                    dx: -coverageBounds.minX,
                    dy: -coverageBounds.minY
                )
                placeholderView.repeatedRowLayer.path =
                    PhantomShapePathRenderer.path(
                        frames: firstRowFrames,
                        relativeTo: rowBounds
                    )
            }
            let finalRowFrames = rows.finalRowFrames.map(adjustedFrame)
            if !finalRowFrames.isEmpty {
                if configuresTopology {
                    placeholderView.finalRowLayer.isHidden = false
                }
                placeholderView.finalRowLayer.frame = placeholderView.bounds
                placeholderView.finalRowLayer.path =
                    PhantomShapePathRenderer.path(
                        frames: finalRowFrames,
                        relativeTo: coverageBounds
                    )
            }
        case let .solid(solidCoverage):
            if configuresTopology {
                placeholderView.solidCoverageLayer.isHidden = false
            }
            placeholderView.solidCoverageLayer.frame = placeholderView.bounds
            placeholderView.solidCoverageLayer.path =
                PhantomShapePathRenderer.path(
                    frames: [adjustedFrame(solidCoverage.frame)],
                    relativeTo: coverageBounds
                )
        }
    }

    private func refreshPhantomShapeExclusionMask(session: Session) {
        guard let placeholderView = session.phantomShapeView
            as? PhantomShapeView,
              let coverageBounds = placeholderView.renderedCoverageBounds
        else {
            return
        }
        let occupantFrames = phantomShapeOccupantFrames(session: session)
        guard placeholderView.renderedOccupantFrames != occupantFrames
            || placeholderView.maskedCoverageBounds != coverageBounds else {
            return
        }
        phantomShapeMaskBuildCount += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        placeholderView.renderedOccupantFrames = occupantFrames
        placeholderView.maskedCoverageBounds = coverageBounds
        let hasShapeExclusions = placeholderView
            .renderedShapeExclusionPath != nil
        guard hasShapeExclusions || !occupantFrames.isEmpty else {
            placeholderView.layer.mask = nil
            return
        }
        placeholderView.exclusionMaskLayer.frame = placeholderView.bounds
        placeholderView.exclusionMaskLayer.path = placeholderView
            .renderedShapeExclusionPath
                ?? PhantomShapePathRenderer.exclusionMaskPath(
                    exclusionPath: nil,
                    maskBounds: placeholderView.bounds
                )
        placeholderView.exclusionMaskLayer.fillRule = .evenOdd
        placeholderView.exclusionMaskLayer.fillColor = UIColor.white.cgColor
        if occupantFrames.isEmpty {
            placeholderView.exclusionMaskLayer.mask = nil
        } else {
            let occupantFrameValues = occupantFrames.values.sorted {
                lhs, rhs in
                lhs.minY == rhs.minY
                    ? lhs.minX < rhs.minX
                    : lhs.minY < rhs.minY
            }
            let occupantPath = PhantomShapePathRenderer.path(
                frames: occupantFrameValues,
                relativeTo: coverageBounds
            )
            // Disjoint rects already punch correctly under even-odd; the
            // boolean op is only needed when an overlap would flip the
            // intersection back to filled.
            let normalizedOccupantPath = PhantomShapePathRenderer
                .hasOverlappingVerticallySortedFrames(occupantFrameValues)
                ? occupantPath.normalized(using: .winding)
                : occupantPath
            placeholderView.occupantExclusionMaskLayer.frame =
                placeholderView.exclusionMaskLayer.bounds
            placeholderView.occupantExclusionMaskLayer.path =
                PhantomShapePathRenderer.exclusionMaskPath(
                    exclusionPath: normalizedOccupantPath,
                    maskBounds: placeholderView.bounds
                )
            placeholderView.occupantExclusionMaskLayer.fillRule = .evenOdd
            placeholderView.occupantExclusionMaskLayer.fillColor =
                UIColor.white.cgColor
            placeholderView.exclusionMaskLayer.mask =
                placeholderView.occupantExclusionMaskLayer
        }
        placeholderView.layer.mask = placeholderView.exclusionMaskLayer
    }

    private func existingManagedSourceItemIndices(
        intersecting rect: CGRect,
        layout: MobilePlayerBrowserLayout
    ) -> Set<Int> {
        guard let collectionView else { return [] }
        return Set(layout.candidateItemIndices(intersecting: rect).filter {
            collectionView.cellForItem(at: IndexPath(
                item: $0,
                section: 0
            )) != nil
        })
    }

    private func sourceCells(
        session: Session,
        at itemIndex: Int
    ) -> [MobilePlayerCollectionBrowserCell] {
        guard let collectionView else { return [] }
        var cells = [MobilePlayerCollectionBrowserCell]()
        if let cell = collectionView.cellForItem(at: IndexPath(
            item: itemIndex,
            section: 0
        )) as? MobilePlayerCollectionBrowserCell {
            cells.append(cell)
        }
        if let cell = session.sourceOverscanCells[itemIndex],
           !cells.contains(where: { $0 === cell }) {
            cells.append(cell)
        }
        return cells
    }

    private func cell(
        _ cell: UICollectionViewCell,
        intersects rect: CGRect
    ) -> Bool {
        guard let collectionView, cell.superview != nil else { return false }
        let intersection = cell.convert(cell.bounds, to: collectionView)
            .intersection(rect)
        return !intersection.isNull
            && intersection.width > 0
            && intersection.height > 0
    }

    private func registerSourceRepresentation(
        session: Session,
        cell: MobilePlayerCollectionBrowserCell,
        itemIndex: Int
    ) {
        let representationID = ObjectIdentifier(cell)
        if let registeredItem = session.cachedSourceRepresentations[
            representationID
        ]?.itemIndex, registeredItem != itemIndex {
            materializationQueue.removePromotion(
                sessionID: session.id,
                contentGeneration: session.transitionContentGeneration,
                representationID: representationID,
                tokenIndex: registeredItem
            )
            invalidateTransitionWork(
                session: session,
                scope: .representationKeys([TransitionRepresentationKey(
                    representationID: representationID,
                    sourceItem: registeredItem
                )]),
                removePendingDetails: true
            )
            removeCellFrameCorrection(session: session, for: cell)
        }
        session.registerSourceRepresentation(cell, itemIndex: itemIndex)
    }

    private func sourceCells(
        session: Session,
        intersecting rect: CGRect
    ) -> [SourceCellEntry] {
        let itemIndices = sourceItemIndices(
            session: session,
            intersecting: rect
        )
        for itemIndex in itemIndices {
            for cell in sourceCells(session: session, at: itemIndex)
            where cell.superview != nil
                && cell.represents(tokenIndex: itemIndex) {
                registerSourceRepresentation(
                    session: session,
                    cell: cell,
                    itemIndex: itemIndex
                )
            }
        }
        return registeredSourceCells(
            session: session,
            itemIndices: itemIndices,
            intersecting: rect
        )
    }

    private func sourceItemIndices(
        session: Session,
        intersecting rect: CGRect
    ) -> Set<Int> {
        let layout = session.plane?.transitionLayout.fromLayout
            ?? session.sourceLayout
        let geometry = visualGeometry(for: layout)
        let layoutRect = geometry.mirrorsHorizontally
            ? CGRect(
                x: layout.contentSize.width - rect.maxX,
                y: rect.minY,
                width: rect.width,
                height: rect.height
            )
            : rect
        return Set(layout.candidateItemIndices(intersecting: layoutRect).filter {
            layout.itemFrame(at: $0)?.intersects(layoutRect) == true
        })
    }

    private func registeredSourceCells(
        session: Session,
        intersecting rect: CGRect
    ) -> [SourceCellEntry] {
        registeredSourceCells(
            session: session,
            itemIndices: sourceItemIndices(
                session: session,
                intersecting: rect
            ),
            intersecting: rect
        )
    }

    private func registeredSourceCells(
        session: Session,
        itemIndices: Set<Int>,
        intersecting rect: CGRect
    ) -> [SourceCellEntry] {
        var entries = [SourceCellEntry]()
        let layout = session.plane?.transitionLayout.fromLayout
            ?? session.sourceLayout
        let geometry = visualGeometry(for: layout)
        for (representationID, representation) in
            session.cachedSourceRepresentations {
            guard representation.cell.superview != nil,
                  representation.cell.represents(
                      tokenIndex: representation.itemIndex
                  ) else {
                continue
            }
            let needsLiveIntersection = session.frameTrackedRepresentationIDs
                .contains(representationID)
                || !sourceRepresentationMatchesLayout(
                    representation,
                    geometry: geometry
                )
            let isVisible = needsLiveIntersection
                ? cell(representation.cell, intersects: rect)
                : itemIndices.contains(representation.itemIndex)
            guard isVisible else { continue }
            entries.append(SourceCellEntry(
                indexPath: IndexPath(
                    item: representation.itemIndex,
                    section: 0
                ),
                cell: representation.cell
            ))
        }
        return entries.sorted {
            $0.indexPath.item < $1.indexPath.item
        }
    }

    private func sourceRepresentationMatchesLayout(
        _ representation: (
            itemIndex: Int,
            cell: MobilePlayerCollectionBrowserCell
        ),
        geometry: MobilePlayerBrowserVisualLayoutGeometry
    ) -> Bool {
        guard let collectionView,
              let superview = representation.cell.superview else {
            return false
        }
        guard let expectedFrame = geometry.itemFrame(
            at: representation.itemIndex
        ) else {
            return false
        }
        let cell = representation.cell
        let untransformedFrame = CGRect(
            x: cell.center.x - cell.bounds.width / 2,
            y: cell.center.y - cell.bounds.height / 2,
            width: cell.bounds.width,
            height: cell.bounds.height
        )
        let actualFrame = superview === collectionView
            ? untransformedFrame
            : superview.convert(untransformedFrame, to: collectionView)
        let epsilon: CGFloat = 0.001
        return abs(actualFrame.minX - expectedFrame.minX) <= epsilon
            && abs(actualFrame.minY - expectedFrame.minY) <= epsilon
            && abs(actualFrame.width - expectedFrame.width) <= epsilon
            && abs(actualFrame.height - expectedFrame.height) <= epsilon
    }

    private func sourceRepresentation(
        session: Session,
        id: ObjectIdentifier,
        itemIndex: Int
    ) -> MobilePlayerCollectionBrowserCell? {
        if let representation = session.cachedSourceRepresentations[id],
           representation.itemIndex == itemIndex,
           representation.cell.superview != nil,
           representation.cell.represents(tokenIndex: itemIndex) {
            return representation.cell
        }
        return sourceCells(session: session, at: itemIndex).first {
            ObjectIdentifier($0) == id && $0.represents(tokenIndex: itemIndex)
        }
    }

    private func viewportSourceCells(
        session: Session
    ) -> [SourceCellEntry] {
        guard let collectionView, let viewportView else { return [] }
        return sourceCells(
            session: session,
            intersecting: collectionView.convert(
                viewportView.bounds,
                from: viewportView
            )
        )
    }

    private var visibleBrowserCells: [MobilePlayerCollectionBrowserCell] {
        collectionView?.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        } ?? []
    }

    private func invalidateViewportPromotion(session: Session) {
        invalidateViewportBasePromotion(session: session)
        session.viewportDetailCoverage.reset()
    }

    private func invalidateViewportBasePromotion(session: Session) {
        session.viewportPromotionCoverage.reset()
    }

    private func enqueueViewportPromotions(
        session: Session,
        reconcilesDetails: Bool = true
    ) {
        guard let collectionView, let viewportView else { return }
        let viewportRect = collectionView.convert(
            viewportView.bounds,
            from: viewportView
        )
        let promotionRect = session.viewportPromotionCoverage.replacementRect(
            requiredRect: viewportRect,
            buffer: priorityCoverageBuffer(for: viewportRect)
        )
        if reconcilesDetails,
           let plane = session.plane,
           reconcileDetailedSourceRepresentationsIfNeeded(
                session: session,
                plane: plane
            ) {
            markSourceCoverageRefreshDirty(session: session)
        }
        guard let promotionRect else { return }
        let sourceRepresentations = sourceCells(
            session: session,
            intersecting: promotionRect
        )
        let viewportRepresentationIDs = Set(registeredSourceCells(
            session: session,
            intersecting: viewportRect
        ).map { ObjectIdentifier($0.cell) })
        for representation in sourceRepresentations {
            enqueueMaterialization(
                session: session,
                priority: viewportRepresentationIDs.contains(
                    ObjectIdentifier(representation.cell)
                ) ? .visibleRepresentation : .deferred,
                kind: .promotion(
                    contentGeneration: session.transitionContentGeneration,
                    representationID: ObjectIdentifier(representation.cell),
                    tokenIndex: representation.indexPath.item
                )
            )
        }
    }

    private func enqueueVisiblePromotion(
        session: Session,
        cell: MobilePlayerCollectionBrowserCell,
        tokenIndex: Int
    ) {
        guard let collectionView, let viewportView else { return }
        let viewportRect = collectionView.convert(
            viewportView.bounds,
            from: viewportView
        )
        guard self.cell(cell, intersects: viewportRect) else { return }
        enqueueMaterialization(
            session: session,
            priority: .visibleRepresentation,
            kind: .promotion(
                contentGeneration: session.transitionContentGeneration,
                representationID: ObjectIdentifier(cell),
                tokenIndex: tokenIndex
            )
        )
    }

    func didConfigureCell(
        _ cell: MobilePlayerCollectionBrowserCell,
        at indexPath: IndexPath
    ) {
        guard case let .active(session) = lifecycle else { return }
        recycleSourceOverscanCell(session: session, at: indexPath.item)
        registerSourceRepresentation(
            session: session,
            cell: cell,
            itemIndex: indexPath.item
        )
        invalidateManagedCellPlans(session: session)
        guard let plane = session.plane else {
            applyNoPlaneSourceSeamCompensation(session: session, to: cell)
            refreshPhantomShapeExclusionMask(session: session)
            return
        }
        let cellID = ObjectIdentifier(cell)
        session.detailedSourceCellItems.removeValue(forKey: cellID)
        if session.lastContentFadeAlpha > 0 {
            session.lockedFallbackRepresentationIDs.insert(cellID)
        }
        refreshDetailedSourceRepresentations(session: session, plane: plane)
        applySourceContentFade(
            session: session,
            representationID: cellID,
            cell: cell,
            alpha: session.lastContentFadeAlpha
        )
    }

    func willDisplayCell(
        _ cell: UICollectionViewCell,
        at indexPath: IndexPath
    ) {
        guard case let .active(session) = lifecycle else { return }
        invalidateManagedCellPlans(session: session)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            removeCellFrameCorrection(session: session, for: cell)
            return
        }
        registerSourceRepresentation(
            session: session,
            cell: browserCell,
            itemIndex: indexPath.item
        )
        if let plane = session.plane {
            let cellID = ObjectIdentifier(browserCell)
            if session.lastContentFadeAlpha > 0 {
                session.lockedFallbackRepresentationIDs.insert(cellID)
            }
            refreshDetailedSourceRepresentations(session: session, plane: plane)
        } else {
            removeCellFrameCorrection(session: session, for: cell)
            applyNoPlaneSourceSeamCompensation(
                session: session,
                to: browserCell
            )
            refreshPhantomShapeExclusionMask(session: session)
        }
        enqueueMaterialization(
            session: session,
            priority: .visibleRepresentation,
            kind: .promotion(
                contentGeneration: session.transitionContentGeneration,
                representationID: ObjectIdentifier(browserCell),
                tokenIndex: indexPath.item
            )
        )
    }

    func didEndDisplayingCell(
        _ cell: UICollectionViewCell,
        at indexPath: IndexPath
    ) {
        guard case let .active(session) = lifecycle else { return }
        invalidateManagedCellPlans(session: session)
        removeCellFrameCorrection(session: session, for: cell)
        let cellID = ObjectIdentifier(cell)
        session.unregisterSourceRepresentation(cellID)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        materializationQueue.removePromotion(
            sessionID: session.id,
            contentGeneration: session.transitionContentGeneration,
            representationID: cellID,
            tokenIndex: indexPath.item
        )
        invalidateTransitionWork(
            session: session,
            scope: .representationKeys([TransitionRepresentationKey(
                representationID: cellID,
                sourceItem: indexPath.item
            )]),
            removePendingDetails: true
        )
        browserCell.finishTransitionContent()
        browserCell.alpha = 1
        browserCell.transform = .identity
        markSourceCoverageRefreshDirty(session: session)
    }

    private func markSourceCoverageRefreshDirty(session: Session) {
        guard session.plane != nil else { return }
        session.sourceCoverageRefreshIsDirty = true
        startMaterializationDisplayLinkIfNeeded()
    }

    private func invalidateManagedCellPlans(session: Session) {
        guard !session.managedCellPlanRefreshIsPending else { return }
        session.managedCellPlanRefreshIsPending = true
        if session.plane == nil {
            session.sourcePlanePriorityCoverage.reset()
            advanceSourcePlanGeneration(session: session)
            if session.currentPhantomPlan != nil {
                startMaterializationDisplayLinkIfNeeded()
            }
        } else {
            session.sourcePlanePriorityCoverage.reset()
            session.destinationPlanePriorityCoverage.reset()
            session.destinationPlanRefreshIsDirty = true
            startMaterializationDisplayLinkIfNeeded()
        }
        invalidateViewportPromotion(session: session)
    }

    private func configureDetailedSourceRepresentation(
        session: Session,
        cell: MobilePlayerCollectionBrowserCell,
        sourceItem: Int,
        plane: GridModePlaneContext,
        resolvedContent: ResolvedTransitionContent? = nil
    ) {
        guard session.selectedSourceItems.contains(sourceItem),
              cell.represents(tokenIndex: sourceItem) else {
            return
        }
        let cellID = ObjectIdentifier(cell)
        var changesSourceCoverage = false
        if cell.hasCarryoverContent {
            changesSourceCoverage = session.lockedFallbackRepresentationIDs
                .insert(cellID).inserted
        }
        guard !session.lockedFallbackRepresentationIDs.contains(cellID)
        else {
            changesSourceCoverage = classifyUnpreparedSourceRepresentation(
                session: session,
                cell: cell,
                sourceItem: sourceItem,
                plane: plane
            ) || changesSourceCoverage
            applySourceContentFade(
                session: session,
                representationID: cellID,
                cell: cell,
                alpha: session.lastContentFadeAlpha
            )
            if changesSourceCoverage {
                markSourceCoverageRefreshDirty(session: session)
            }
            return
        }
        if let previousItem = session.detailedSourceCellItems[cellID],
           previousItem != sourceItem {
            invalidateTransitionWork(
                session: session,
                scope: .representationKeys([TransitionRepresentationKey(
                    representationID: cellID,
                    sourceItem: previousItem
                )]),
                removePendingDetails: true
            )
            removeCellFrameCorrection(session: session, for: cell)
            changesSourceCoverage = session.preparedRepresentationIDs
                .remove(cellID) != nil || changesSourceCoverage
            cell.finishTransitionContent()
        }
        session.detailedSourceCellItems[cellID] = sourceItem
        guard let destinationItem = destinationItem(
            session: session,
            sourceItem: sourceItem,
            plane: plane
        ) else {
            cell.installDeferredBaseImageIfNoIncomingOverlay()
            changesSourceCoverage = session.preparedRepresentationIDs
                .remove(cellID) != nil || changesSourceCoverage
            if session.unpreparedMarginTrackingRepresentationIDs.remove(
                cellID
            ) != nil {
                removeCellFrameCorrection(session: session, for: cell)
                changesSourceCoverage = true
            }
            applySourceContentFade(
                session: session,
                representationID: cellID,
                cell: cell,
                alpha: session.lastContentFadeAlpha
            )
            if changesSourceCoverage {
                markSourceCoverageRefreshDirty(session: session)
            }
            return
        }
        let preparation = loadTransitionContent(
            session: session,
            fromItem: sourceItem,
            toItem: destinationItem,
            requiredQuality: plane.toMode.requiredImageQuality,
            into: cell,
            plane: plane,
            resolvedContent: resolvedContent
        )
        switch preparation {
        case .ready:
            changesSourceCoverage = session
                .unpreparedMarginTrackingRepresentationIDs.remove(cellID)
                != nil || changesSourceCoverage
            changesSourceCoverage = session.preparedRepresentationIDs
                .insert(cellID).inserted || changesSourceCoverage
            registerCellFrameCorrection(
                session: session,
                cell: cell,
                destinationItem: destinationItem,
                plane: plane
            )
        case .pending, .unavailable:
            if case .unavailable = preparation {
                cell.installDeferredBaseImageIfNoIncomingOverlay()
            }
            changesSourceCoverage = session.preparedRepresentationIDs
                .remove(cellID) != nil || changesSourceCoverage
            changesSourceCoverage = classifyUnpreparedSourceRepresentation(
                session: session,
                cell: cell,
                sourceItem: sourceItem,
                plane: plane
            ) || changesSourceCoverage
            applySourceContentFade(
                session: session,
                representationID: cellID,
                cell: cell,
                alpha: session.lastContentFadeAlpha
            )
        }
        if changesSourceCoverage {
            markSourceCoverageRefreshDirty(session: session)
        }
    }

    private func classifyUnpreparedSourceRepresentation(
        session: Session,
        cell: MobilePlayerCollectionBrowserCell,
        sourceItem: Int,
        plane: GridModePlaneContext
    ) -> Bool {
        let representationID = ObjectIdentifier(cell)
        let wasTracked = session.unpreparedMarginTrackingRepresentationIDs
            .contains(representationID)
        guard wasTracked
            || session.cellFrameCorrections[representationID] == nil
                && !session.marginCoverageRepresentationIDs.contains(
                    representationID
                ) else {
            return false
        }
        guard let destinationItem = destinationItem(
            session: session,
            sourceItem: sourceItem,
            plane: plane
        ) else {
            guard wasTracked else { return false }
            session.dropCellFrameCorrections(for: [representationID])
            return true
        }
        let inserted = session.unpreparedMarginTrackingRepresentationIDs
            .insert(representationID).inserted
        // A drain tick landing between settle frames must not paint a
        // classification the next settle frame may reverse: two near-identical
        // rasterizations alternating per frame read as a whole-grid shimmer.
        // The settle frame's correction sweep is the authoritative painter;
        // register the correction and let that sweep show it.
        let defersToSettleFrame = isDrainingMaterialization
            && session.lastSettleProgress > 0
        if defersToSettleFrame {
            session.deferClassificationPaint(for: representationID)
            return inserted
        }
        registerCellFrameCorrection(
            session: session,
            cell: cell,
            destinationItem: destinationItem,
            plane: plane
        )
        return inserted
    }

    @discardableResult
    private func loadTransitionContent(
        session: Session,
        fromItem: Int,
        toItem: Int,
        requiredQuality: CollectionBrowseImageQuality,
        into cell: MobilePlayerCollectionBrowserCell,
        plane: GridModePlaneContext,
        resolvedContent: ResolvedTransitionContent? = nil
    ) -> TransitionContentPreparation {
        guard cell.represents(tokenIndex: fromItem) else {
            return .unavailable
        }
        let cellID = ObjectIdentifier(cell)
        guard !session.lockedFallbackRepresentationIDs.contains(cellID),
              let resolvedContent = resolvedContent?.destinationItem == toItem
                ? resolvedContent
                : resolveTransitionContent(destinationItem: toItem) else {
            cancelTransitionImageLoad(session: session, for: cell)
            return .unavailable
        }
        let contentIdentity = resolvedContent.contentIdentity
        let imageSources = resolvedContent.imageSources
        let retainedTransitionContentQuality = session
            .preparedRepresentationIDs.contains(cellID)
            && session.detailedSourceCellItems[cellID] == fromItem
            ? cell.incomingTransitionContentQuality(
                representing: contentIdentity,
                from: imageSources
            )
            : nil
        var installedCachedContent = false
        if let cachedImage = resolvedContent.cachedImage {
            let satisfiesRequiredQuality = cachedImage.quality.canReplace(
                requiredQuality
            )
            if cachedImage.quality.canReplace(
                retainedTransitionContentQuality
            ) {
                cell.installTransitionContent(
                    image: cachedImage.image,
                    descriptor: cachedImage.descriptor,
                    usesNativeMetalCardCornerMask:
                        cachedImage.descriptor
                            .usesNativeMetalCardPresentation,
                    targetAlpha: session.lastContentFadeAlpha,
                    animated: false,
                    identity: contentIdentity
                )
                installedCachedContent = true
            }
            if satisfiesRequiredQuality {
                cancelTransitionImageLoad(session: session, for: cell)
                return .ready
            }
        }
        if let retainedTransitionContentQuality,
           retainedTransitionContentQuality.canReplace(requiredQuality) {
            cancelTransitionImageLoad(session: session, for: cell)
            return .ready
        }
        let generation = session.transitionContentGeneration
        let sessionID = session.id
        let planeID = plane.id
        guard let descriptor = imageSources.descriptor(
            for: requiredQuality
        ) else {
            cancelTransitionImageLoad(session: session, for: cell)
            return installedCachedContent
                || retainedTransitionContentQuality != nil
                ? .ready
                : .unavailable
        }
        let loadEligibility = foregroundDestinationEligibility(
            destinationItem: toItem,
            cell: cell,
            context: cachedForegroundDestinationEligibilityContext(
                session: session,
                plane: plane
            )
        )
        if let load = session.transitionImageLoads[cellID] {
            if load.sourceItem == fromItem,
               load.destinationItem == toItem,
               load.planeID == planeID,
               load.contentGeneration == generation,
               load.contentIdentity == contentIdentity,
               load.requiredImageQuality == requiredQuality,
               load.descriptor == descriptor,
               loadEligibility != nil {
                return installedCachedContent
                    || retainedTransitionContentQuality != nil
                    ? .ready
                    : .pending
            }
            cancelTransitionImageLoad(session: session, for: cell)
        }
        guard loadEligibility != nil,
              session.lastContentFadeAlpha <= 0 else {
            return installedCachedContent
                || retainedTransitionContentQuality != nil
                ? .ready
                : .unavailable
        }
        let loadID = UUID()
        let cancellation = imageAccess.loadImage(descriptor) {
            [weak self] image in
            Task { @MainActor [weak self] in
                guard let self,
                      case let .active(activeSession) = self.lifecycle,
                      activeSession.id == sessionID,
                      let load = activeSession.transitionImageLoads[cellID],
                      load.id == loadID else {
                    return
                }
                let completionPriority: MaterializationPriority
                if let activePlane = activeSession.plane,
                   activePlane.id == planeID,
                   let activeCell = self.sourceRepresentation(
                       session: activeSession,
                       id: cellID,
                       itemIndex: fromItem
                   ),
                   self.foregroundDestinationEligibility(
                       destinationItem: toItem,
                       cell: activeCell,
                       context: self
                           .cachedForegroundDestinationEligibilityContext(
                               session: activeSession,
                               plane: activePlane
                           )
                   ) == .current {
                    completionPriority = .visibleRepresentation
                } else {
                    completionPriority = .deferred
                }
                self.enqueueMaterialization(
                    session: activeSession,
                    priority: completionPriority,
                    kind: .transitionImageCompletion(
                        GridModeTransitionImageCompletion(
                            planeID: planeID,
                            contentGeneration: generation,
                            loadID: loadID,
                            representationID: cellID,
                            sourceItem: fromItem,
                            destinationItem: toItem,
                            contentIdentity: contentIdentity,
                            requiredImageQuality: requiredQuality,
                            descriptor: descriptor,
                            image: image
                        )
                    )
                )
            }
        }
        if let cancellation {
            guard case let .active(activeSession) = lifecycle,
                  activeSession.id == sessionID,
                  let activePlane = activeSession.plane,
                  activePlane.id == planeID,
                  activeSession.transitionContentGeneration == generation,
                  cell.represents(tokenIndex: fromItem),
                  contentAccess.contentIdentity(toItem) == contentIdentity,
                  contentAccess.imageSources(toItem)?.descriptor(
                      for: requiredQuality
                  ) == descriptor,
                  foregroundDestinationEligibility(
                      destinationItem: toItem,
                      cell: cell,
                      context: cachedForegroundDestinationEligibilityContext(
                          session: activeSession,
                          plane: activePlane
                      )
                  ) != nil else {
                cancellation()
                return installedCachedContent
                    || retainedTransitionContentQuality != nil
                    ? .ready
                    : .unavailable
            }
            session.transitionImageLoads[cellID] = GridModeTransitionImageLoad(
                id: loadID,
                sourceItem: fromItem,
                destinationItem: toItem,
                planeID: planeID,
                contentGeneration: generation,
                contentIdentity: contentIdentity,
                requiredImageQuality: requiredQuality,
                descriptor: descriptor,
                cancellation: cancellation
            )
            return installedCachedContent
                || retainedTransitionContentQuality != nil
                ? .ready
                : .pending
        }
        return installedCachedContent
            || retainedTransitionContentQuality != nil
            ? .ready
            : .unavailable
    }

    private func resolveTransitionContent(
        destinationItem: Int
    ) -> ResolvedTransitionContent? {
        guard let contentIdentity = contentAccess.contentIdentity(destinationItem),
              let imageSources = contentAccess.imageSources(destinationItem) else {
            return nil
        }
        return ResolvedTransitionContent(
            destinationItem: destinationItem,
            contentIdentity: contentIdentity,
            imageSources: imageSources,
            cachedImage: imageAccess.cachedImage(
                imageSources,
                .highestAvailable
            )
        )
    }

    private func applySourceContentFade(
        session: Session,
        representationID: ObjectIdentifier,
        cell: MobilePlayerCollectionBrowserCell,
        alpha: CGFloat,
        interruptingAnimation: Bool = false
    ) {
        let visibleAlpha = sourceTransitionContentTargetAlpha(
            session: session,
            representationID: representationID,
            alpha: alpha
        )
        let role: SourcePresentationRole
        if session.marginCoverageRepresentationIDs.contains(representationID) {
            role = .marginCoverage
        } else if sourceRepresentationOwnsTransitionVisual(
            session: session,
            representationID: representationID
        ) {
            role = .destinationTransition
        } else {
            role = .sourceFallback
        }
        applySourcePresentation(
            cell: cell,
            role: role,
            visibleAlpha: visibleAlpha,
            interruptingAnimation: interruptingAnimation
        )
    }

    private func applySourcePresentation(
        cell: MobilePlayerCollectionBrowserCell,
        role: SourcePresentationRole,
        visibleAlpha: CGFloat,
        interruptingAnimation: Bool = false
    ) {
        switch role {
        case .awaitingClassification:
            setSourceCellAlpha(1, on: cell)
            if cell.holdsCarryoverForPendingBaseImage {
                cell.setTransitionContentAlpha(
                    1,
                    interruptingAnimation: interruptingAnimation
                )
            }
        case .marginCoverage:
            setSourceCellAlpha(1, on: cell)
            cell.setTransitionContentAlpha(
                cell.holdsCarryoverForPendingBaseImage ? 1 : 0,
                interruptingAnimation: interruptingAnimation
            )
        case .destinationTransition:
            setSourceCellAlpha(1, on: cell)
            cell.setTransitionContentAlpha(
                visibleAlpha,
                interruptingAnimation: interruptingAnimation
            )
        case .sourceFallback:
            // Photos never fades the outgoing plane: a cell whose destination
            // content has not arrived keeps its old pixels at full opacity
            // until the arrival crossfades in or the commit carries them over.
            // Fading it out uncovers the background wherever nothing else
            // paints that region — the flanks of a zoom-in most visibly.
            setSourceCellAlpha(1, on: cell)
            if cell.holdsCarryoverForPendingBaseImage {
                cell.setTransitionContentAlpha(
                    1,
                    interruptingAnimation: interruptingAnimation
                )
            } else if !cell.hasCarryoverContent {
                cell.setTransitionContentAlpha(
                    0,
                    interruptingAnimation: interruptingAnimation
                )
            }
        }
    }

    private func sourceTransitionContentTargetAlpha(
        session: Session,
        representationID: ObjectIdentifier,
        alpha: CGFloat
    ) -> CGFloat {
        // Photos fades the whole outgoing plane uniformly. Scaling the
        // incoming overlay down by edge visibility left a ring of half-faded
        // cells at the viewport margins — old art ghosting through new — for
        // the entire flight.
        guard !session.marginCoverageRepresentationIDs.contains(
            representationID
        ) else {
            return 0
        }
        return alpha
    }

    private func sourceRepresentationOwnsTransitionVisual(
        session: Session,
        representationID: ObjectIdentifier
    ) -> Bool {
        session.preparedRepresentationIDs.contains(representationID)
            && !session.lockedFallbackRepresentationIDs.contains(
                representationID
            )
            && (session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ] != nil || session.cellFrameCorrections[representationID] != nil)
    }

    private func installDeferredBaseImages(
        session: Session,
        for representationIDs: Set<ObjectIdentifier>
    ) {
        for representationID in representationIDs {
            guard let representation = session
                .cachedSourceRepresentations[representationID],
                  representation.cell.superview != nil,
                  representation.cell.represents(
                      tokenIndex: representation.itemIndex
                  ) else {
                continue
            }
            representation.cell.installDeferredBaseImageIfNoIncomingOverlay()
        }
    }

    private func setSourceCellAlpha(
        _ alpha: CGFloat,
        on cell: MobilePlayerCollectionBrowserCell
    ) {
        guard cell.alpha != alpha else { return }
        cell.alpha = alpha
    }

    private func rearmLockedFallbackRepresentationsWhileContentIsHidden(
        session: Session,
        dropsUnpreparedGeometry: Bool
    ) {
        guard !session.lockedFallbackRepresentationIDs.isEmpty
            || dropsUnpreparedGeometry else {
            return
        }
        let classifiedRepresentationIDs = session
            .frameClassifiedRepresentationIDs
        let droppableRepresentationIDs = dropsUnpreparedGeometry
            ? classifiedRepresentationIDs.subtracting(
                session.preparedRepresentationIDs
            )
            : []
        guard !session.lockedFallbackRepresentationIDs.isEmpty
            || !droppableRepresentationIDs.isEmpty else {
            return
        }
        // This runs per frame while content is hidden, so the cell map holds
        // only IDs the rearm or the geometry drop can read back: locked or
        // droppable ones. The drop recomputes against the narrowed prepared
        // set below, but every ID it gains that way is rearmed, and rearmed
        // IDs are locked, so they are all here.
        let neededRepresentationIDs = session.lockedFallbackRepresentationIDs
            .union(droppableRepresentationIDs)
        var currentCells = [
            ObjectIdentifier: MobilePlayerCollectionBrowserCell
        ]()
        for (representationID, representation) in
            session.cachedSourceRepresentations
        where neededRepresentationIDs.contains(representationID)
            && representation.cell.superview != nil
            && representation.cell.represents(
                tokenIndex: representation.itemIndex
            ) {
            currentCells[representationID] = representation.cell
        }
        for (itemIndex, cell) in session.sourceOverscanCells
        where cell.superview != nil && cell.represents(tokenIndex: itemIndex) {
            let representationID = ObjectIdentifier(cell)
            guard neededRepresentationIDs.contains(representationID) else {
                continue
            }
            currentCells[representationID] = cell
        }
        if let collectionView {
            for cell in visibleBrowserCells {
                let representationID = ObjectIdentifier(cell)
                guard neededRepresentationIDs.contains(representationID),
                      let indexPath = collectionView.indexPath(for: cell),
                      cell.represents(tokenIndex: indexPath.item) else {
                    continue
                }
                currentCells[representationID] = cell
            }
        }
        let retainedRepresentationIDs = Set(
            currentCells.compactMap { representationID, cell in
                cell.hasCarryoverContent
                    ? representationID
                    : nil
            }
        )
        let rearmedRepresentationIDs = session
            .lockedFallbackRepresentationIDs.subtracting(
                retainedRepresentationIDs
            )
        let rearmedCells = rearmedRepresentationIDs.compactMap {
            currentCells[$0]
        }
        if !rearmedRepresentationIDs.isEmpty {
            session.lockedFallbackRepresentationIDs.subtract(
                rearmedRepresentationIDs
            )
            session.preparedRepresentationIDs.subtract(
                rearmedRepresentationIDs
            )
            session.detailedSourceCellItems = session.detailedSourceCellItems
                .filter { !rearmedRepresentationIDs.contains($0.key) }
            session.removeForegroundEligibility(for: rearmedRepresentationIDs)
            invalidateTransitionWork(
                session: session,
                scope: .anySourceForRepresentationIDs(
                    rearmedRepresentationIDs
                ),
                removePendingDetails: true
            )
            for cell in rearmedCells {
                cell.finishTransitionContent()
            }
        }
        let droppedGeometryRepresentationIDs = dropsUnpreparedGeometry
            ? classifiedRepresentationIDs.subtracting(
                session.preparedRepresentationIDs
            ).subtracting(
                session.unpreparedMarginTrackingRepresentationIDs
            )
            : []
        if !droppedGeometryRepresentationIDs.isEmpty {
            let droppedGeometryCells = droppedGeometryRepresentationIDs
                .compactMap { currentCells[$0] }
            removeCellFrameCorrections(
                session: session,
                for: droppedGeometryCells
            )
            session.dropCellFrameCorrections(
                for: droppedGeometryRepresentationIDs.subtracting(
                    Set(droppedGeometryCells.map(ObjectIdentifier.init))
                )
            )
        }
        if !rearmedRepresentationIDs.isEmpty
            || !droppedGeometryRepresentationIDs.isEmpty {
            markSourceCoverageRefreshDirty(session: session)
        }
    }

    private func prepareCacheReadyResolvedCarryoverFallbacks(
        session: Session,
        plane: GridModePlaneContext
    ) {
        guard !session.lockedFallbackRepresentationIDs.isEmpty else { return }
        let candidates = session.cachedSourceRepresentations.compactMap {
            representationID, representation -> (
                ObjectIdentifier,
                Int,
                MobilePlayerCollectionBrowserCell,
                ResolvedTransitionContent
            )? in
            guard session.lockedFallbackRepresentationIDs.contains(
                representationID
            ), session.selectedSourceItems.contains(representation.itemIndex),
            representation.cell.superview != nil,
            representation.cell.represents(
                tokenIndex: representation.itemIndex
            ), !representation.cell.hasCarryoverContent,
            let destinationItem = destinationItem(
                session: session,
                sourceItem: representation.itemIndex,
                plane: plane
            ), let resolvedContent = resolveTransitionContent(
                destinationItem: destinationItem
            ), resolvedContent.cachedImage != nil else {
                return nil
            }
            return (
                representationID,
                representation.itemIndex,
                representation.cell,
                resolvedContent
            )
        }
        for (representationID, sourceItem, cell, resolvedContent) in candidates {
            session.lockedFallbackRepresentationIDs.remove(representationID)
            configureDetailedSourceRepresentation(
                session: session,
                cell: cell,
                sourceItem: sourceItem,
                plane: plane,
                resolvedContent: resolvedContent
            )
        }
    }

    private func applyContentFade(
        session: Session,
        alpha: CGFloat,
        animated: Bool
    ) {
        let alpha = PlayerBrowserGridCrossfade.sanitizedProgress(alpha)
        session.currentContentFadeTargetAlpha = alpha
        let previousAlpha = session.lastContentFadeAlpha
        let changesAlpha = previousAlpha != alpha
        let interruptsAnimation = !animated
            && session.contentFadeAnimationMayBeActive
        guard changesAlpha || interruptsAnimation else { return }
        if changesAlpha, previousAlpha <= 0, alpha > 0 {
            if let plane = session.plane {
                prepareCacheReadyResolvedCarryoverFallbacks(
                    session: session,
                    plane: plane
                )
            }
            if session.sourceCoverageRefreshIsDirty,
               let plane = session.plane {
                refreshDetailedSourceRepresentations(
                    session: session,
                    plane: plane
                )
            }
            if session.destinationPlanRefreshIsDirty,
               let plane = session.plane {
                refreshDestinationPlan(session: session, plane: plane)
            }
            let fallbackRepresentationIDs = session.sourceCoverage
                .fallbackRepresentationIDs
            session.lockedFallbackRepresentationIDs.formUnion(
                fallbackRepresentationIDs
            )
            session.removeForegroundEligibility(
                for: session.lockedFallbackRepresentationIDs
            )
            invalidateTransitionWork(
                session: session,
                scope: .anySourceForRepresentationIDs(
                    session.lockedFallbackRepresentationIDs
                ),
                removePendingDetails: true
            )
            installDeferredBaseImages(
                session: session,
                for: fallbackRepresentationIDs
            )
        }
        if changesAlpha {
            session.lastContentFadeAlpha = alpha
        }
        let sessionID = session.id
        let apply = { [weak self, weak session] in
            guard let self,
                  let session,
                  self.currentSession?.id == sessionID else {
                return
            }
            for representation in session.cachedSourceRepresentations.values
            where representation.cell.superview != nil
                && representation.cell.represents(
                    tokenIndex: representation.itemIndex
                ) {
                if !animated,
                   representation.cell.layer.animation(forKey: "opacity") != nil {
                    representation.cell.layer.removeAnimation(
                        forKey: "opacity"
                    )
                }
                applySourceContentFade(
                    session: session,
                    representationID: ObjectIdentifier(representation.cell),
                    cell: representation.cell,
                    alpha: alpha,
                    interruptingAnimation: !animated
                )
            }
        }
        if animated {
            session.contentFadeAnimationMayBeActive = true
            session.contentFadeAnimationGeneration &+= 1
            let generation = session.contentFadeAnimationGeneration
            UIView.animate(
                withDuration: Self.contentFadeOutDuration,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: apply
            ) { [weak session] _ in
                // A superseded animation's completion must not clear the flag
                // out from under the animation that replaced it.
                guard let session,
                      session.contentFadeAnimationGeneration == generation
                else {
                    return
                }
                session.contentFadeAnimationMayBeActive = false
            }
        } else {
            session.contentFadeAnimationMayBeActive = false
            apply()
        }
    }

    private func cancelTransitionImageLoad(
        session: Session,
        for cell: MobilePlayerCollectionBrowserCell,
        ifRepresenting sourceItem: Int? = nil
    ) {
        let cellID = ObjectIdentifier(cell)
        guard let load = session.transitionImageLoads[cellID],
              sourceItem == nil || load.sourceItem == sourceItem else {
            return
        }
        invalidateTransitionWork(
            session: session,
            scope: .representationKeys([TransitionRepresentationKey(
                representationID: cellID,
                sourceItem: load.sourceItem
            )]),
            removePendingDetails: false
        )
    }

    private func cancelTransitionImageLoads(session: Session) {
        invalidateTransitionWork(
            session: session,
            scope: .all,
            removePendingDetails: false
        )
    }

    private func invalidateTransitionWork(
        session: Session,
        scope: TransitionWorkScope,
        removePendingDetails: Bool
    ) {
        guard !scope.isEmpty else { return }
        var loads = [(
            representationID: ObjectIdentifier,
            load: GridModeTransitionImageLoad
        )]()
        switch scope {
        case .all:
            loads.reserveCapacity(session.transitionImageLoads.count)
            for (representationID, load) in session.transitionImageLoads {
                loads.append((representationID, load))
            }
        case let .anySourceForRepresentationIDs(representationIDs):
            loads.reserveCapacity(representationIDs.count)
            for representationID in representationIDs {
                if let load = session.transitionImageLoads[representationID] {
                    loads.append((representationID, load))
                }
            }
        case let .sourceItems(sourceItems):
            for (representationID, load) in session.transitionImageLoads
            where sourceItems.contains(load.sourceItem) {
                loads.append((representationID, load))
            }
        case let .representationKeys(representationKeys):
            loads.reserveCapacity(representationKeys.count)
            for representationKey in representationKeys {
                guard let load = session.transitionImageLoads[
                    representationKey.representationID
                ],
                load.sourceItem == representationKey.sourceItem else {
                    continue
                }
                loads.append((representationKey.representationID, load))
            }
        }
        for entry in loads {
            session.transitionImageLoads.removeValue(
                forKey: entry.representationID
            )
        }
        let loadIDs = Set(loads.map(\.load.id))
        var handledQueueInvalidationDirectly = false
        if !materializationQueue.isEmpty,
           case let .representationKeys(representationKeys) = scope,
           let plane = session.plane {
            handledQueueInvalidationDirectly = true
            for entry in loads {
                materializationQueue.removeTransitionImageCompletion(
                    sessionID: session.id,
                    loadID: entry.load.id,
                    representationID: entry.representationID
                )
            }
            if removePendingDetails {
                for representationKey in representationKeys {
                    materializationQueue.removeDetail(
                        sessionID: session.id,
                        planeID: plane.id,
                        contentGeneration:
                            session.transitionContentGeneration,
                        representationID:
                            representationKey.representationID,
                        sourceItem: representationKey.sourceItem
                    )
                }
            }
        } else if !materializationQueue.isEmpty, !removePendingDetails {
            handledQueueInvalidationDirectly = true
            for entry in loads {
                materializationQueue.removeTransitionImageCompletion(
                    sessionID: session.id,
                    loadID: entry.load.id,
                    representationID: entry.representationID
                )
            }
        }
        if !handledQueueInvalidationDirectly,
           !materializationQueue.isEmpty,
           removePendingDetails || !loadIDs.isEmpty {
            transitionWorkQueueFilterPassCount &+= 1
            materializationQueue.removeAll { job in
                guard job.sessionID == session.id else { return false }
                switch job.kind {
                case let .transitionImageCompletion(completion):
                    return loadIDs.contains(completion.loadID)
                case let .detail(
                    _,
                    _,
                    representationID,
                    sourceItem
                ):
                    return removePendingDetails && scope.contains(
                        representationID: representationID,
                        sourceItem: sourceItem
                    )
                default:
                    return false
                }
            }
        }
        for entry in loads {
            entry.load.cancellation()
        }
    }

    private func clearTransitionContent(
        session: Session,
        carryoverRetention: CarryoverRetention = .none,
        installsDeferredBaseImages: Bool = false
    ) {
        session.transitionContentGeneration &+= 1
        cancelTransitionImageLoads(session: session)
        session.phantomShapeView?.removeFromSuperview()
        session.resetTransitionState()
        let sourceCells = visibleBrowserCells
            + Array(session.sourceOverscanCells.values)
        for cell in sourceCells {
            let preservesCarryover: Bool
            switch carryoverRetention {
            case .none:
                preservesCarryover = false
            case .pendingBase:
                preservesCarryover = cell.holdsCarryoverForPendingBaseImage
            case .all:
                preservesCarryover = true
            }
            if installsDeferredBaseImages {
                cell.finishTransitionContent(
                    preservingCarryover: preservesCarryover
                )
            } else {
                cell.clearTransitionContent(
                    preservingCarryover: preservesCarryover
                )
            }
            cell.layer.removeAnimation(forKey: "opacity")
            cell.alpha = 1
            if cell.transform != .identity {
                cell.transform = .identity
            }
        }
        recyclePhantomCells(session: session, retaining: [])
    }

    private func tearDownPlaneRendering(
        session: Session,
        carryoverRetention: CarryoverRetention = .none
    ) {
        session.plane = nil
        session.visualAnchor = nil
        session.zoomRebase = nil
        clearTransitionContent(
            session: session,
            carryoverRetention: carryoverRetention,
            installsDeferredBaseImages: true
        )
        collectionView?.transform = .identity
        session.lastRenderedScale = 1
        recycleSourceOverscanCells(session: session, retaining: [])
        session.sourceOverscanCells.removeAll(keepingCapacity: false)
    }

    private func captureVisibleCarryoverSources(
        session: Session,
        anchorTokenIndex: Int?,
        capturesFallbackSources: Bool,
        ineligibleFallbackSourceItems: Set<Int>
    ) -> [MobilePlayerBrowserGridCarryoverSource] {
        guard let collectionView, let viewportView else { return [] }
        let eligibleSourceCells = viewportSourceCells(session: session)
            .sorted { lhs, rhs in
                if lhs.indexPath.item == rhs.indexPath.item {
                    return ObjectIdentifier(lhs.cell).hashValue
                        < ObjectIdentifier(rhs.cell).hashValue
                }
                return lhs.indexPath.item < rhs.indexPath.item
            }.filter {
                let representationID = ObjectIdentifier($0.cell)
                let hasReadyDestination = session.sourceCoverage
                    .readyDestinationByRepresentation[representationID] != nil
                let capturesFallback = capturesFallbackSources
                    && session.selectedSourceItems.contains(
                        $0.indexPath.item
                    )
                    && !ineligibleFallbackSourceItems.contains(
                        $0.indexPath.item
                    )
                    && session.sourceCoverage.fallbackRepresentationIDs
                        .contains(representationID)
                    && $0.cell.carryoverSourceContent != nil
                return hasReadyDestination || capturesFallback
            }
        let selectedItems = PlayerBrowserGridCarryoverSelection
            .selectedItemIndices(
                candidateItemIndices: eligibleSourceCells.map {
                    $0.indexPath.item
                },
                anchorItemIndex: anchorTokenIndex
            )
        let selectedSourceCells = eligibleSourceCells.filter {
            selectedItems.contains($0.indexPath.item)
        }
        var destinationItemByRepresentationID = [ObjectIdentifier: Int]()
        for source in selectedSourceCells {
            let representationID = ObjectIdentifier(source.cell)
            if let destinationItem = session.sourceCoverage
                .readyDestinationByRepresentation[representationID]
                ?? session.reassignments[source.indexPath.item] {
                destinationItemByRepresentationID[representationID] =
                    destinationItem
            }
        }
        let phantomCells = session.phantomCells.sorted {
            $0.key < $1.key
        }.compactMap { itemIndex, cell -> MobilePlayerCollectionBrowserCell? in
            guard MobilePlayerCollectionBrowserTransitionSupport
                .itemIntersectsViewport(
                    at: IndexPath(item: itemIndex, section: 0),
                    cell: cell,
                    collectionView: collectionView,
                    viewportView: viewportView
            ) else {
                return nil
            }
            destinationItemByRepresentationID[ObjectIdentifier(cell)] =
                itemIndex
            return cell
        }
        let carryoverCells = (selectedSourceCells.map(\.cell) + phantomCells.prefix(
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )).prefix(
            PlayerBrowserGridRenderBudget.maximumCarryoverSourceCount
        )
        return MobilePlayerCollectionBrowserTransitionSupport.captureSources(
            from: Array(carryoverCells),
            in: viewportView,
            destinationItem: {
                destinationItemByRepresentationID[ObjectIdentifier($0)]
            }
        )
    }

    private func installCarryoverContent(
        session: Session,
        plane: GridModePlaneContext,
        sources: [MobilePlayerBrowserGridCarryoverSource],
        fallbackSourceItemByDestinationItem: [Int: Int]
    ) {
        guard let collectionView, let viewportView else { return }
        let holdsPlaceholderTone =
            MobilePlayerCollectionBrowserTransitionSupport.installCarryover(
                sources: sources,
                in: collectionView,
                viewportView: viewportView,
                anchorItemIndex: plane.anchorTokenIndex,
                hasImageSources: { itemIndex in
                    contentAccess.imageSources(itemIndex) != nil
                },
                fallbackContent: { itemIndex, cell in
                    fallbackCarryoverSource(
                        destinationItem: itemIndex,
                        isNeeded: cell.needsCarryoverContent,
                        sourceItemByDestinationItem:
                            fallbackSourceItemByDestinationItem
                    )
                }
            )
        hasTransitionPlaceholderTones = hasTransitionPlaceholderTones
            || holdsPlaceholderTone
        session.sourceCoverage = .empty
    }

    private func fallbackCarryoverSource(
        destinationItem: Int,
        isNeeded: Bool,
        sourceItemByDestinationItem: [Int: Int]
    ) -> MobilePlayerBrowserCarryoverContent? {
        guard isNeeded,
              let sourceItem = sourceItemByDestinationItem[destinationItem],
              let contentIdentity = contentAccess.contentIdentity(sourceItem),
              let imageSources = contentAccess.imageSources(sourceItem),
              let cachedImage = imageAccess.cachedImage(
                  imageSources,
                  .highestAvailable
              ) else {
            return nil
        }
        return MobilePlayerBrowserCarryoverContent(
            identity: contentIdentity,
            image: cachedImage.image,
            usesNativeMetalCardCornerMask:
                cachedImage.descriptor.usesNativeMetalCardPresentation
        )
    }

    private func enqueueMaterialization(
        session: Session,
        priority: MaterializationPriority,
        kind: MaterializationKind
    ) {
        guard case let .active(activeSession) = lifecycle,
              activeSession.id == session.id else {
            return
        }
        if materializationQueue.enqueue(
            sessionID: session.id,
            priority: priority,
            kind: kind
        ) {
            startMaterializationDisplayLinkIfNeeded()
        }
    }

    private func advanceDestinationPlanGeneration(session: Session) {
        session.destinationPlaneCellPlanGeneration &+= 1
        materializationQueue.removeAll { job in
            guard job.sessionID == session.id else { return false }
            if case .destination = job.kind {
                return true
            }
            return false
        }
    }

    private func advanceSourcePlanGeneration(session: Session) {
        session.sourcePlaneCellPlanGeneration &+= 1
        materializationQueue.removeAll { job in
            guard job.sessionID == session.id else { return false }
            if case .source = job.kind {
                return true
            }
            return false
        }
    }

    private func startMaterializationDisplayLinkIfNeeded() {
        guard materializationDisplayLink == nil,
              !materializationQueue.isEmpty || hasDeferredRenderRefresh else {
            return
        }
        let displayLink = CADisplayLink(
            target: materializationDisplayLinkTarget,
            selector: #selector(MaterializationDisplayLinkTarget.tick(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        materializationDisplayLink = displayLink
    }

    private var hasDeferredRenderRefresh: Bool {
        guard case let .active(session) = lifecycle else { return false }
        return !session.deferredClassificationPaintRepresentationIDs.isEmpty
            || hasNonClassificationDeferredRenderRefresh(session: session)
    }

    private func hasNonClassificationDeferredRenderRefresh(
        session: Session
    ) -> Bool {
        let needsNoPlaneManagedCellPlanRefresh = session.plane == nil
            && session.managedCellPlanRefreshIsPending
            && session.currentPhantomPlan != nil
        return session.sourceCoverageRefreshIsDirty
            || session.destinationPlanRefreshIsDirty
            || session.phantomShapeRefreshIsDirty
            || needsNoPlaneManagedCellPlanRefresh
    }

    private func handleMaterializationTick(_ displayLink: CADisplayLink) {
        _ = drainMaterializationWork(
            frameDuration: displayLink.targetTimestamp - displayLink.timestamp
        )
    }

    private func nextDeferredClassificationRepresentationID(
        session: Session
    ) -> ObjectIdentifier? {
        session.deferredClassificationPaintRepresentationIDs.min { lhs, rhs in
            let lhsItem = session.cachedSourceRepresentations[lhs]?.itemIndex
                ?? Int.max
            let rhsItem = session.cachedSourceRepresentations[rhs]?.itemIndex
                ?? Int.max
            return session.sourceItemPrecedes(lhsItem, rhsItem)
        }
    }

    private func deferredClassificationIsVisible(
        _ representationID: ObjectIdentifier,
        session: Session
    ) -> Bool {
        guard let itemIndex = session.cachedSourceRepresentations[
            representationID
        ]?.itemIndex else {
            return false
        }
        return session.viewportSelectedSourceItems.contains(itemIndex)
    }

    private func paintDeferredClassification(
        _ representationID: ObjectIdentifier,
        session: Session
    ) -> Bool {
        guard let plane = session.plane,
              let geometry = cellFrameCorrectionGeometry(
                  session: session,
                  plane: plane
              ) else {
            return false
        }
        session.deferredClassificationPaintRepresentationIDs.remove(
            representationID
        )
        guard let representation = session.cachedSourceRepresentations[
            representationID
        ],
              session.unpreparedMarginTrackingRepresentationIDs.contains(
                  representationID
              ),
              representation.cell.superview != nil,
              representation.cell.represents(
                  tokenIndex: representation.itemIndex
              ),
              let destinationItem = destinationItem(
                  session: session,
                  sourceItem: representation.itemIndex,
                  plane: plane
              ) else {
            return true
        }
        registerCellFrameCorrection(
            session: session,
            cell: representation.cell,
            destinationItem: destinationItem,
            plane: plane,
            geometry: geometry
        )
        return true
    }

    @discardableResult
    func drainMaterializationWork(
        budgetOverride: (jobs: Int, time: CFTimeInterval)? = nil,
        frameDuration: CFTimeInterval? = nil
    ) -> MaterializationDrainResult {
        let start = clock()
        var processedCount = 0
        var canBatchDirtySource = false
        isDrainingMaterialization = true
        defer { isDrainingMaterialization = false }
        let usesGestureBudget: Bool
        if case let .active(session) = lifecycle {
            let requestedBurst = session.pendingGestureMaterializationBurst
            session.pendingGestureMaterializationBurst = false
            usesGestureBudget = requestedBurst && session.plane != nil
        } else {
            usesGestureBudget = false
        }
        let jobLimit = budgetOverride?.jobs ?? (usesGestureBudget
            ? Self.transitionMaterializationJobLimit
            : Self.materializationJobLimit)
        let effectiveFrameDuration = frameDuration.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? Self.defaultMaterializationFrameDuration
        let transitionTimeLimit = min(
            Self.transitionMaterializationMaximumTimeLimit,
            effectiveFrameDuration
                * Self.transitionMaterializationFrameFraction
        )
        let timeLimit = budgetOverride?.time ?? (usesGestureBudget
            ? transitionTimeLimit
            : Self.materializationTimeLimit)
        while processedCount < jobLimit,
              clock() - start < timeLimit {
            guard case let .active(session) = lifecycle else { break }
            let remainingCount = jobLimit - processedCount
            if session.sourceCoverageRefreshIsDirty {
                if canBatchDirtySource,
                   let nextJob = materializationQueue.first,
                   canBatchSourceCoverageRefresh(
                       with: nextJob,
                       remainingCount: remainingCount
                   ) {
                    materializationQueue.removeFirst()
                    processMaterialization(nextJob)
                    processedCount += 1
                    continue
                }
                flushDeferredSourceCoverage(session: session)
                processedCount += 1
                canBatchDirtySource = false
                continue
            }
            if let deferredRepresentationID =
                nextDeferredClassificationRepresentationID(session: session),
               deferredClassificationIsVisible(
                   deferredRepresentationID,
                   session: session
               ), materializationQueue.first?.priority
                    != .visibleRepresentation {
                guard paintDeferredClassification(
                    deferredRepresentationID,
                    session: session
                ) else {
                    break
                }
                processedCount += 1
                canBatchDirtySource = false
                continue
            }
            let hasNonClassificationRefresh =
                hasNonClassificationDeferredRenderRefresh(session: session)
            if hasNonClassificationRefresh,
               materializationQueue.isEmpty || remainingCount == 1 {
                guard flushDeferredRenderRefresh() else { break }
                processedCount += 1
                continue
            }
            guard let nextJob = materializationQueue.first else {
                guard let representationID =
                    nextDeferredClassificationRepresentationID(
                        session: session
                    ), paintDeferredClassification(
                        representationID,
                        session: session
                    ) else {
                    break
                }
                processedCount += 1
                canBatchDirtySource = false
                continue
            }
            if case .source = nextJob.kind,
               remainingCount < Self.minimumSourceBatchCapacity {
                if let representationID =
                    nextDeferredClassificationRepresentationID(
                        session: session
                    ) {
                    guard paintDeferredClassification(
                        representationID,
                        session: session
                    ) else {
                        break
                    }
                    processedCount += 1
                    canBatchDirtySource = false
                    continue
                }
                if hasNonClassificationRefresh {
                    guard flushDeferredRenderRefresh() else { break }
                    processedCount += 1
                    continue
                }
                break
            }
            materializationQueue.removeFirst()
            processMaterialization(nextJob)
            processedCount += 1
            switch nextJob.kind {
            case .detail, .source, .transitionImageCompletion:
                canBatchDirtySource = true
            case .destination, .promotion:
                canBatchDirtySource = false
            }
        }
        if processedCount > 0,
           case let .active(session) = lifecycle {
            refreshPhantomShapeExclusionMask(session: session)
        }
        let elapsed = max(clock() - start, 0)
        let stoppedForTimeLimit = (
            !materializationQueue.isEmpty || hasDeferredRenderRefresh
        )
            && elapsed >= timeLimit
        if materializationQueue.isEmpty && !hasDeferredRenderRefresh {
            materializationDisplayLink?.invalidate()
            materializationDisplayLink = nil
        }
        return MaterializationDrainResult(
            processedCount: processedCount,
            elapsed: elapsed,
            stoppedForTimeLimit: stoppedForTimeLimit
        )
    }

    private func canBatchSourceCoverageRefresh(
        with job: MaterializationJob,
        remainingCount: Int
    ) -> Bool {
        switch job.kind {
        case .detail, .transitionImageCompletion:
            return remainingCount >= 2
        case .source:
            return remainingCount >= Self.minimumSourceBatchCapacity
        case .destination, .promotion:
            return false
        }
    }

    private func processMaterialization(_ job: MaterializationJob) {
        guard case let .active(session) = lifecycle,
              session.id == job.sessionID else {
            return
        }
        switch job.kind {
        case let .detail(
            planeID,
            contentGeneration,
            representationID,
            sourceItem
        ):
            guard session.transitionContentGeneration == contentGeneration,
                  let plane = session.plane,
                  plane.id == planeID,
                  session.selectedSourceItems.contains(sourceItem),
                  let cell = sourceRepresentation(
                      session: session,
                      id: representationID,
                      itemIndex: sourceItem
                  ) else {
                return
            }
            configureDetailedSourceRepresentation(
                session: session,
                cell: cell,
                sourceItem: sourceItem,
                plane: plane
            )
        case let .destination(
            planeID,
            contentGeneration,
            planGeneration,
            candidate,
            requiredImageQuality
        ):
            guard session.transitionContentGeneration == contentGeneration,
                  session.plane?.id == planeID,
                  session.destinationPlaneCellPlanGeneration
                    == planGeneration else {
                return
            }
            installPhantomCell(
                session: session,
                candidate: candidate,
                requiredImageQuality: requiredImageQuality
            )
        case let .source(
            planeID,
            contentGeneration,
            planGeneration,
            candidate
        ):
            guard session.transitionContentGeneration == contentGeneration,
                  session.plane?.id == planeID,
                  session.sourcePlaneCellPlanGeneration == planGeneration else {
                return
            }
            installSourceOverscanCell(
                session: session,
                candidate: candidate,
                targetPlaneID: planeID
            )
        case let .promotion(
            contentGeneration,
            representationID,
            tokenIndex
        ):
            guard session.transitionContentGeneration == contentGeneration,
                  let cell = managedCell(
                      session: session,
                      representationID: representationID,
                      tokenIndex: tokenIndex
                  ) else {
                return
            }
            if session.phantomCells[tokenIndex] === cell {
                guard let plane = session.plane,
                      foregroundDestinationEligibility(
                          destinationItem: tokenIndex,
                          cell: cell,
                          context: cachedForegroundDestinationEligibilityContext(
                              session: session,
                              plane: plane
                          )
                      ) != nil else {
                    cell.demoteImageLoadToCachedOnlyIfNeeded(
                        tokenIndex: tokenIndex
                    )
                    return
                }
            }
            cell.resumeImageLoadIfNeeded(tokenIndex: tokenIndex)
            cell.promoteImageLoadToForegroundIfNeeded(tokenIndex: tokenIndex)
        case let .transitionImageCompletion(completion):
            processTransitionImageCompletion(
                completion,
                session: session
            )
        }
    }

    private func processTransitionImageCompletion(
        _ completion: GridModeTransitionImageCompletion,
        session: Session
    ) {
        guard session.transitionContentGeneration
                == completion.contentGeneration,
              let plane = session.plane,
              plane.id == completion.planeID,
              let load = session.transitionImageLoads[
                  completion.representationID
              ],
              load.id == completion.loadID,
              load.sourceItem == completion.sourceItem,
              load.destinationItem == completion.destinationItem,
              load.planeID == completion.planeID,
              load.contentGeneration == completion.contentGeneration,
              load.contentIdentity == completion.contentIdentity,
              load.requiredImageQuality == completion.requiredImageQuality,
              load.descriptor == completion.descriptor else {
            return
        }
        session.transitionImageLoads.removeValue(
            forKey: completion.representationID
        )
        guard session.selectedSourceItems.contains(completion.sourceItem),
              let cell = sourceRepresentation(
                  session: session,
                  id: completion.representationID,
                  itemIndex: completion.sourceItem
              ),
              contentAccess.contentIdentity(completion.destinationItem)
                == completion.contentIdentity,
              contentAccess.imageSources(
                  completion.destinationItem
              )?.descriptor(for: completion.requiredImageQuality)
                == completion.descriptor else {
            return
        }
        guard let image = completion.image else {
            cell.installDeferredBaseImageIfNoIncomingOverlay()
            return
        }
        guard !cell.hasCarryoverContent else {
            lockSourceFallbackRepresentation(
                session: session,
                representationID: completion.representationID
            )
            return
        }
        if session.lastContentFadeAlpha > 0 {
            let isReady = session.preparedRepresentationIDs.contains(
                completion.representationID
            ) && session.sourceCoverage.readyDestinationByRepresentation[
                completion.representationID
            ] == completion.destinationItem
                && !session.lockedFallbackRepresentationIDs.contains(
                    completion.representationID
                )
            guard isReady else {
                cell.installDeferredBaseImageIfNoIncomingOverlay()
                lockSourceFallbackRepresentation(
                    session: session,
                    representationID: completion.representationID
                )
                return
            }
            cell.installTransitionContent(
                image: image,
                descriptor: completion.descriptor,
                usesNativeMetalCardCornerMask:
                    completion.descriptor.usesNativeMetalCardPresentation,
                targetAlpha: sourceTransitionContentTargetAlpha(
                    session: session,
                    representationID: completion.representationID,
                    alpha: session.lastContentFadeAlpha
                ),
                animated: true,
                identity: completion.contentIdentity
            )
            return
        }
        guard !session.lockedFallbackRepresentationIDs.contains(
            completion.representationID
        ) else {
            return
        }
        cell.installTransitionContent(
            image: image,
            descriptor: completion.descriptor,
            usesNativeMetalCardCornerMask:
                completion.descriptor.usesNativeMetalCardPresentation,
            targetAlpha: session.lastContentFadeAlpha,
            animated: false,
            identity: completion.contentIdentity
        )
        let stoppedTrackingMargin = session
            .unpreparedMarginTrackingRepresentationIDs.remove(
                completion.representationID
            ) != nil
        let preparedRepresentation = session.preparedRepresentationIDs.insert(
            completion.representationID
        ).inserted
        let changesSourceCoverage = stoppedTrackingMargin
            || preparedRepresentation
        registerCellFrameCorrection(
            session: session,
            cell: cell,
            destinationItem: completion.destinationItem,
            plane: plane
        )
        if changesSourceCoverage {
            markSourceCoverageRefreshDirty(session: session)
        }
    }

    private func lockSourceFallbackRepresentation(
        session: Session,
        representationID: ObjectIdentifier
    ) {
        guard session.lockedFallbackRepresentationIDs.insert(
            representationID
        ).inserted else {
            return
        }
        session.removeForegroundEligibility(for: representationID)
        markSourceCoverageRefreshDirty(session: session)
    }

    private func flushDeferredRenderRefresh() -> Bool {
        guard case let .active(session) = lifecycle else { return false }
        if session.managedCellPlanRefreshIsPending,
           session.currentPhantomPlan != nil,
           session.plane == nil {
            guard collectionView != nil, viewportView != nil else {
                session.managedCellPlanRefreshIsPending = false
                return true
            }
            extendSourceCoverageIfNeeded(
                session: session,
                layout: session.sourceLayout
            )
            return !session.managedCellPlanRefreshIsPending
        }
        if session.sourceCoverageRefreshIsDirty {
            flushDeferredSourceCoverage(session: session)
        }
        if session.destinationPlanRefreshIsDirty,
           let plane = session.plane {
            session.destinationPlanRefreshIsDirty = false
            refreshDestinationPlan(
                session: session,
                plane: plane
            )
            return true
        }
        flushDeferredPhantomShapeRefresh(session: session)
        return true
    }

    private func flushDeferredPhantomShapeRefresh(session: Session) {
        guard session.phantomShapeRefreshIsDirty,
              let plan = session.currentPhantomPlan else {
            session.phantomShapeRefreshIsDirty = false
            return
        }
        session.phantomShapeRefreshIsDirty = false
        let installedItemIndices = session.plane == nil
            ? Set(session.sourceOverscanCells.keys)
            : Set(session.phantomCells.keys)
        replacePhantomShapeCoverage(
            session: session,
            plan: plan,
            installedItemIndices: installedItemIndices
        )
    }

    private func flushDeferredSourceCoverage(session: Session) {
        guard let plane = session.plane else { return }
        refreshDetailedSourceRepresentations(
            session: session,
            plane: plane
        )
        enqueueViewportPromotions(
            session: session,
            reconcilesDetails: false
        )
    }

    private func managedCell(
        session: Session,
        representationID: ObjectIdentifier,
        tokenIndex: Int
    ) -> MobilePlayerCollectionBrowserCell? {
        if let cell = sourceRepresentation(
            session: session,
            id: representationID,
            itemIndex: tokenIndex
        ) {
            return cell
        }
        guard let phantom = session.phantomCells[tokenIndex],
              ObjectIdentifier(phantom) == representationID,
              phantom.represents(tokenIndex: tokenIndex) else {
            return nil
        }
        return phantom
    }

    private func cancelMaterializationPump() {
        materializationDisplayLink?.invalidate()
        materializationDisplayLink = nil
        materializationQueue.removeAll(keepingCapacity: false)
    }
}
