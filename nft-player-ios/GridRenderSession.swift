// ∅ 2026 lil org

import UIKit

struct GridRenderTransitionImageLoad {
    let id: UUID
    let sourceItem: Int
    let destinationItem: Int
    let planeID: UUID
    let contentGeneration: UInt
    let contentIdentity: MobilePlayerBrowserContentIdentity
    let requiredImageQuality: CollectionBrowseImageQuality
    let requiredImageDecodeVariant: DownloadableMediaImageDecodeVariant
    let descriptor: DownloadableMediaDescriptor
    let cancellation: () -> Void
}

struct GridRenderCellFrameCorrection {
    let centerDelta: CGPoint
    let sizeDelta: CGSize
    let destinationVisibilityProgress: CGFloat
}

struct GridRenderFrameRevision: Equatable {
    let planeID: UUID
    let scale: Int
    let settleProgress: Int
    let presentationProgress: Int
    let panDeltaY: Int
    let sourceGeometrySignature: Int
}

@MainActor
final class GridRenderSession {
    enum LatticeItemShiftResolution {
        case unresolved
        case unavailable
        case shift(columns: Int, rows: Int)
    }

    let id = UUID()
    let wasCollectionViewPrefetchingEnabled: Bool
    var sourceLayout: MobilePlayerBrowserLayout
    let sourceImageDecodeVariant: DownloadableMediaImageDecodeVariant
    var gestureAnchor: GridModeGestureAnchor?
    var visualAnchor: CGPoint?
    var plane: GridModePlaneContext?
    var zoomRebase: GridModeRebase?
    var lastPanDeltaY: CGFloat = 0
    var lastRenderedScale: CGFloat = 1
    var lastSettleProgress: CGFloat = 0
    var lastPlaneFrameRevision: GridRenderFrameRevision?
    var pendingGestureMaterializationBurst = false
    var lastContentFadeAlpha: CGFloat = 0
    /// The alpha the in-flight render frame will commit. Cell
    /// classification reads it mid-frame, before `applyContentFade`
    /// records the committed value into `lastContentFadeAlpha`.
    var currentContentFadeTargetAlpha: CGFloat = 0
    var contentFadeAnimationMayBeActive = false
    var contentFadeAnimationGeneration: UInt = 0
    var reassignments = [Int: Int]()
    /// Destination items already claimed by the degraded (non-uniform
    /// lattice) per-cell matching path; a second cell resolving to a
    /// claimed item stays a source fallback instead of duplicating art.
    var assignedDestinationItems = Set<Int>()
    var latticeItemShiftResolution = LatticeItemShiftResolution.unresolved
    var selectedSourceItems = Set<Int>()
    var viewportSelectedSourceItems = Set<Int>()
    var preparedRepresentationIDs = Set<ObjectIdentifier>()
    var lockedFallbackRepresentationIDs = Set<ObjectIdentifier>()
    var sourceCoverage =
        PlayerBrowserGridSourceCoveragePlan<ObjectIdentifier>.empty
    var detailedSourceCellItems = [ObjectIdentifier: Int]()
    var cachedSourceRepresentations = [ObjectIdentifier: (
        itemIndex: Int,
        cell: MobilePlayerCollectionBrowserCell
    )]()
    var sourceOverscanCells = [Int: MobilePlayerCollectionBrowserCell]()
    var phantomCells = [Int: MobilePlayerCollectionBrowserCell]()
    var reusablePhantomCells = [MobilePlayerCollectionBrowserCell]()
    var viewportPromotionCoverage = PlayerBrowserGridPhantomCoverage()
    var viewportDetailCoverage = PlayerBrowserGridPhantomCoverage()
    var foregroundCurrentViewportCoverage = PlayerBrowserGridPhantomCoverage()
    var foregroundTerminalViewportCoverage = PlayerBrowserGridPhantomCoverage()
    var phantomShapeView: UIView?
    var defersPhantomShapeMaskCommits = false
    var phantomShapeMaskIsDirty = false
    var phantomCoverage = PlayerBrowserGridPhantomCoverage()
    var sourceOverscanCoverage = PlayerBrowserGridPhantomCoverage()
    var sourcePlanePriorityCoverage = PlayerBrowserGridPhantomCoverage()
    var destinationPlanePriorityCoverage = PlayerBrowserGridPhantomCoverage()
    var sourcePlaneCellPlanGeneration: UInt = 0
    var destinationPlaneCellPlanGeneration: UInt = 0
    var transitionContentGeneration: UInt = 0
    var transitionImageLoads = [
        ObjectIdentifier: GridRenderTransitionImageLoad
    ]()
    var foregroundEligibleRepresentationIDs = Set<ObjectIdentifier>()
    var currentViewportRepresentationIDs = Set<ObjectIdentifier>()
    var lastReconciledCurrentViewportRepresentationIDs = Set<ObjectIdentifier>()
    var cellFrameCorrections = [
        ObjectIdentifier: (
            cell: UICollectionViewCell,
            correction: GridRenderCellFrameCorrection
        )
    ]()
    var unpreparedMarginTrackingRepresentationIDs = Set<ObjectIdentifier>()
    var deferredClassificationPaintRepresentationIDs = Set<ObjectIdentifier>()
    /// Source cells whose destination lands off screen; they hold their
    /// source position and content to keep the viewport margins covered.
    var marginCoverageRepresentationIDs = Set<ObjectIdentifier>()

    var frameClassifiedRepresentationIDs: Set<ObjectIdentifier> {
        Set(cellFrameCorrections.keys).union(
            marginCoverageRepresentationIDs
        )
    }

    var frameTrackedRepresentationIDs: Set<ObjectIdentifier> {
        frameClassifiedRepresentationIDs.union(
            unpreparedMarginTrackingRepresentationIDs
        )
    }

    var hasCellFrameCorrectionTransforms = false
    var hasSourceSeamCompensationTransforms = false
    var hasPhantomSeamCompensationTransforms = false
    var currentPhantomPlan: PlayerBrowserGridPhantomPlan?
    var sourceCoverageRefreshIsDirty = false
    var phantomShapeRefreshIsDirty = false
    var destinationPlanRefreshIsDirty = false
    var managedCellPlanRefreshIsPending = false

    func deferClassificationPaint(for representationID: ObjectIdentifier) {
        deferredClassificationPaintRepresentationIDs.insert(
            representationID
        )
    }

    func sourceItemPrecedes(_ lhs: Int, _ rhs: Int) -> Bool {
        let lhsIsVisible = viewportSelectedSourceItems.contains(lhs)
        let rhsIsVisible = viewportSelectedSourceItems.contains(rhs)
        if lhsIsVisible != rhsIsVisible {
            return lhsIsVisible
        }
        return lhs < rhs
    }

    func sourceRepresentationOwnsTransitionVisual(
        _ representationID: ObjectIdentifier
    ) -> Bool {
        preparedRepresentationIDs.contains(representationID)
            && !lockedFallbackRepresentationIDs.contains(representationID)
            && (sourceCoverage.readyDestinationByRepresentation[
                representationID
            ] != nil || cellFrameCorrections[representationID] != nil)
    }

    func removeForegroundEligibility(
        for representationIDs: Set<ObjectIdentifier>
    ) {
        foregroundEligibleRepresentationIDs.subtract(representationIDs)
        currentViewportRepresentationIDs.subtract(representationIDs)
    }

    func removeForegroundEligibility(
        for representationID: ObjectIdentifier
    ) {
        foregroundEligibleRepresentationIDs.remove(representationID)
        currentViewportRepresentationIDs.remove(representationID)
    }

    func unregisterSourceRepresentation(
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

    func registerSourceRepresentation(
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

    func addCellFrameCorrection(
        _ correction: GridRenderCellFrameCorrection,
        for cell: UICollectionViewCell
    ) {
        let representationID = ObjectIdentifier(cell)
        marginCoverageRepresentationIDs.remove(representationID)
        cellFrameCorrections[representationID] = (cell, correction)
    }

    func holdSourceRepresentationForMargin(
        _ representationID: ObjectIdentifier
    ) {
        cellFrameCorrections.removeValue(forKey: representationID)
        marginCoverageRepresentationIDs.insert(representationID)
        if cellFrameCorrections.isEmpty {
            hasCellFrameCorrectionTransforms = false
        }
    }

    func dropCellFrameCorrections(
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

    func releaseUnpreparedMarginCoverage(
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
    func pruneMarginCoverageToSourceRepresentations() {
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

    func clearForegroundEligibility() {
        foregroundEligibleRepresentationIDs.removeAll(
            keepingCapacity: true
        )
        currentViewportRepresentationIDs.removeAll(
            keepingCapacity: true
        )
    }

    func resetForegroundEligibilityCoverage() {
        foregroundCurrentViewportCoverage.reset()
        foregroundTerminalViewportCoverage.reset()
    }

    func resetTransitionState() {
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

    init(
        gestureAnchor: GridModeGestureAnchor?,
        sourceLayout: MobilePlayerBrowserLayout,
        sourceImageDecodeVariant: DownloadableMediaImageDecodeVariant,
        wasCollectionViewPrefetchingEnabled: Bool
    ) {
        self.gestureAnchor = gestureAnchor
        self.sourceLayout = sourceLayout
        self.sourceImageDecodeVariant = sourceImageDecodeVariant.normalized
        self.wasCollectionViewPrefetchingEnabled =
            wasCollectionViewPrefetchingEnabled
    }
}
