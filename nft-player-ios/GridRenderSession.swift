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

struct GridRenderTransitionImageSourcesWaiter: Equatable {
    let sourceItem: Int
    let destinationItem: Int
}

struct GridRenderCellFrameCorrection: Equatable {
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
final class GridSourceRepresentationStore {
    enum Geometry: Equatable {
        case none
        case corrected(GridRenderCellFrameCorrection)
        case marginHeld

        var correction: GridRenderCellFrameCorrection? {
            guard case let .corrected(correction) = self else { return nil }
            return correction
        }
    }

    enum ForegroundEligibility: Equatable {
        case none
        case terminal
        case current
    }

    enum ImageWork {
        case idle
        case waitingForSources(GridRenderTransitionImageSourcesWaiter)
        case loading(GridRenderTransitionImageLoad)

        var waiter: GridRenderTransitionImageSourcesWaiter? {
            guard case let .waitingForSources(waiter) = self else {
                return nil
            }
            return waiter
        }

        var load: GridRenderTransitionImageLoad? {
            guard case let .loading(load) = self else { return nil }
            return load
        }
    }

    struct Record {
        let cell: MobilePlayerCollectionBrowserCell
        let itemIndex: Int
        var detailedSourceItem: Int?
        var isPrepared = false
        var isFallbackLocked = false
        var tracksUnpreparedMargin = false
        var needsClassificationPaint = false
        var geometry = Geometry.none
        var foregroundEligibility = ForegroundEligibility.none
        var imageWork = ImageWork.idle
    }

    private(set) var records = [ObjectIdentifier: Record]()
    private(set) var preparedRepresentationIDs = Set<ObjectIdentifier>()
    private(set) var lockedFallbackRepresentationIDs = Set<ObjectIdentifier>()
    private(set) var detailedSourceCellItems = [ObjectIdentifier: Int]()
    private(set) var transitionImageSourcesWaiters = [
        ObjectIdentifier: GridRenderTransitionImageSourcesWaiter
    ]()
    private(set) var transitionImageLoads = [
        ObjectIdentifier: GridRenderTransitionImageLoad
    ]()
    private(set) var foregroundEligibleRepresentationIDs = Set<ObjectIdentifier>()
    private(set) var currentViewportRepresentationIDs = Set<ObjectIdentifier>()
    private(set) var cellFrameCorrections = [
        ObjectIdentifier: (
            cell: UICollectionViewCell,
            correction: GridRenderCellFrameCorrection
        )
    ]()
    private(set) var unpreparedMarginTrackingRepresentationIDs =
        Set<ObjectIdentifier>()
    private(set) var deferredClassificationPaintRepresentationIDs =
        Set<ObjectIdentifier>()
    private(set) var marginCoverageRepresentationIDs = Set<ObjectIdentifier>()

    var frameClassifiedRepresentationIDs: Set<ObjectIdentifier> {
        Set(cellFrameCorrections.keys).union(marginCoverageRepresentationIDs)
    }

    var frameTrackedRepresentationIDs: Set<ObjectIdentifier> {
        frameClassifiedRepresentationIDs.union(
            unpreparedMarginTrackingRepresentationIDs
        )
    }

    func register(_ cell: MobilePlayerCollectionBrowserCell, itemIndex: Int) {
        let id = ObjectIdentifier(cell)
        if let record = records[id] {
            precondition(record.itemIndex == itemIndex)
            return
        }
        records[id] = Record(cell: cell, itemIndex: itemIndex)
    }

    @discardableResult
    func remove(_ id: ObjectIdentifier) -> Record? {
        guard let record = records.removeValue(forKey: id) else { return nil }
        updateIndexes(for: id, previous: record, current: nil)
        return record
    }

    @discardableResult
    func markPrepared(_ id: ObjectIdentifier) -> Bool {
        mutate(id) {
            let changed = !$0.isPrepared || $0.tracksUnpreparedMargin
            $0.isPrepared = true
            $0.tracksUnpreparedMargin = false
            return changed
        }
    }

    @discardableResult
    func markUnprepared(_ id: ObjectIdentifier) -> Bool {
        mutate(id) {
            let changed = $0.isPrepared
            $0.isPrepared = false
            return changed
        }
    }

    func retainPreparedRepresentations(
        where predicate: (ObjectIdentifier) -> Bool
    ) {
        for id in preparedRepresentationIDs where !predicate(id) {
            markUnprepared(id)
        }
    }

    @discardableResult
    func lockFallback(_ id: ObjectIdentifier) -> Bool {
        mutate(id) {
            let changed = !$0.isFallbackLocked
            $0.isFallbackLocked = true
            $0.foregroundEligibility = .none
            return changed
        }
    }

    func lockFallbacks(_ ids: Set<ObjectIdentifier>) {
        for id in ids { lockFallback(id) }
    }

    func unlockFallback(_ id: ObjectIdentifier) {
        mutate(id) {
            $0.isFallbackLocked = false
            return true
        }
    }

    func rearm(_ ids: Set<ObjectIdentifier>) {
        for id in ids {
            mutate(id) {
                $0.isFallbackLocked = false
                $0.isPrepared = false
                $0.detailedSourceItem = nil
                $0.foregroundEligibility = .none
                return true
            }
        }
    }

    func clearDetailPreparation(
        for ids: Set<ObjectIdentifier>,
        sourceItems: Set<Int>,
        lockingFallback: Bool
    ) {
        for id in ids {
            mutate(id) {
                $0.isPrepared = false
                $0.foregroundEligibility = .none
                if lockingFallback {
                    $0.isFallbackLocked = true
                }
                return true
            }
        }
        for (id, item) in detailedSourceCellItems
        where sourceItems.contains(item) {
            setDetailedSourceItem(nil, for: id)
        }
    }

    func setDetailedSourceItem(_ item: Int?, for id: ObjectIdentifier) {
        mutate(id) {
            $0.detailedSourceItem = item
            return true
        }
    }

    @discardableResult
    func trackUnpreparedMargin(_ id: ObjectIdentifier) -> Bool {
        mutate(id) {
            let changed = !$0.tracksUnpreparedMargin
            $0.tracksUnpreparedMargin = true
            return changed
        }
    }

    @discardableResult
    func stopTrackingUnpreparedMargin(_ id: ObjectIdentifier) -> Bool {
        mutate(id) {
            let changed = $0.tracksUnpreparedMargin
            $0.tracksUnpreparedMargin = false
            return changed
        }
    }

    func deferClassificationPaint(for id: ObjectIdentifier) {
        mutate(id) {
            $0.needsClassificationPaint = true
            return true
        }
    }

    func finishClassificationPaint(for id: ObjectIdentifier) {
        mutate(id) {
            $0.needsClassificationPaint = false
            return true
        }
    }

    func clearDeferredClassificationPaint() {
        for id in deferredClassificationPaintRepresentationIDs {
            finishClassificationPaint(for: id)
        }
    }

    func setGeometry(_ geometry: Geometry, for id: ObjectIdentifier) {
        mutate(id) {
            $0.geometry = geometry
            return true
        }
    }

    func dropGeometry(for ids: Set<ObjectIdentifier>) {
        for id in ids {
            mutate(id) {
                $0.geometry = .none
                $0.tracksUnpreparedMargin = false
                $0.needsClassificationPaint = false
                return true
            }
        }
    }

    func removeForegroundEligibility(for ids: Set<ObjectIdentifier>) {
        for id in ids { removeForegroundEligibility(for: id) }
    }

    func removeForegroundEligibility(for id: ObjectIdentifier) {
        mutate(id) {
            $0.foregroundEligibility = .none
            return true
        }
    }

    func replaceForegroundEligibility(
        eligible: Set<ObjectIdentifier>,
        currentViewport: Set<ObjectIdentifier>
    ) {
        precondition(currentViewport.isSubset(of: eligible))
        let changedIDs = foregroundEligibleRepresentationIDs
            .symmetricDifference(eligible)
            .union(currentViewportRepresentationIDs
                .symmetricDifference(currentViewport))
        for id in changedIDs {
            mutate(id) {
                $0.foregroundEligibility = currentViewport.contains(id)
                    ? .current
                    : eligible.contains(id) ? .terminal : .none
                return true
            }
        }
    }

    func clearForegroundEligibility() {
        for id in foregroundEligibleRepresentationIDs {
            removeForegroundEligibility(for: id)
        }
    }

    func waitForImageSources(
        _ waiter: GridRenderTransitionImageSourcesWaiter,
        for id: ObjectIdentifier
    ) {
        mutate(id) {
            precondition($0.imageWork.load == nil)
            $0.imageWork = .waitingForSources(waiter)
            return true
        }
    }

    func clearImageSourcesWaiter(for id: ObjectIdentifier) {
        mutate(id) {
            guard $0.imageWork.waiter != nil else { return false }
            $0.imageWork = .idle
            return true
        }
    }

    func installImageLoad(
        _ load: GridRenderTransitionImageLoad,
        for id: ObjectIdentifier
    ) {
        mutate(id) {
            precondition($0.imageWork.load == nil)
            precondition($0.itemIndex == load.sourceItem)
            $0.imageWork = .loading(load)
            return true
        }
    }

    @discardableResult
    func takeImageLoad(for id: ObjectIdentifier) -> GridRenderTransitionImageLoad? {
        guard let load = records[id]?.imageWork.load else { return nil }
        mutate(id) {
            $0.imageWork = .idle
            return true
        }
        return load
    }

    func reset() {
        precondition(transitionImageLoads.isEmpty)
        records.removeAll(keepingCapacity: true)
        preparedRepresentationIDs.removeAll(keepingCapacity: true)
        lockedFallbackRepresentationIDs.removeAll(keepingCapacity: true)
        detailedSourceCellItems.removeAll(keepingCapacity: true)
        transitionImageSourcesWaiters.removeAll(keepingCapacity: true)
        foregroundEligibleRepresentationIDs.removeAll(keepingCapacity: true)
        currentViewportRepresentationIDs.removeAll(keepingCapacity: true)
        cellFrameCorrections.removeAll(keepingCapacity: true)
        unpreparedMarginTrackingRepresentationIDs.removeAll(keepingCapacity: true)
        deferredClassificationPaintRepresentationIDs.removeAll(keepingCapacity: true)
        marginCoverageRepresentationIDs.removeAll(keepingCapacity: true)
    }

    @discardableResult
    private func mutate(
        _ id: ObjectIdentifier,
        _ mutation: (inout Record) -> Bool
    ) -> Bool {
        guard var record = records[id] else { return false }
        let previous = record
        let changed = mutation(&record)
        records[id] = record
        updateIndexes(for: id, previous: previous, current: record)
        return changed
    }

    private func updateIndexes(
        for id: ObjectIdentifier,
        previous: Record,
        current: Record?
    ) {
        func updateMembership(
            _ ids: inout Set<ObjectIdentifier>,
            wasIncluded: Bool,
            isIncluded: Bool
        ) {
            guard wasIncluded != isIncluded else { return }
            if isIncluded {
                ids.insert(id)
            } else {
                ids.remove(id)
            }
        }

        updateMembership(
            &preparedRepresentationIDs,
            wasIncluded: previous.isPrepared,
            isIncluded: current?.isPrepared == true
        )
        updateMembership(
            &lockedFallbackRepresentationIDs,
            wasIncluded: previous.isFallbackLocked,
            isIncluded: current?.isFallbackLocked == true
        )
        updateMembership(
            &unpreparedMarginTrackingRepresentationIDs,
            wasIncluded: previous.tracksUnpreparedMargin,
            isIncluded: current?.tracksUnpreparedMargin == true
        )
        updateMembership(
            &deferredClassificationPaintRepresentationIDs,
            wasIncluded: previous.needsClassificationPaint,
            isIncluded: current?.needsClassificationPaint == true
        )
        updateMembership(
            &marginCoverageRepresentationIDs,
            wasIncluded: previous.geometry == .marginHeld,
            isIncluded: current?.geometry == .marginHeld
        )
        updateMembership(
            &foregroundEligibleRepresentationIDs,
            wasIncluded: previous.foregroundEligibility != .none,
            isIncluded: current.map { $0.foregroundEligibility != .none } == true
        )
        updateMembership(
            &currentViewportRepresentationIDs,
            wasIncluded: previous.foregroundEligibility == .current,
            isIncluded: current?.foregroundEligibility == .current
        )
        if previous.detailedSourceItem != current?.detailedSourceItem {
            detailedSourceCellItems[id] = current?.detailedSourceItem
        }
        if previous.geometry != current?.geometry {
            cellFrameCorrections[id] = current.flatMap { record in
                record.geometry.correction.map { (record.cell, $0) }
            }
        }
        if previous.imageWork.waiter != current?.imageWork.waiter {
            transitionImageSourcesWaiters[id] = current?.imageWork.waiter
        }
        if previous.imageWork.load?.id != current?.imageWork.load?.id {
            transitionImageLoads[id] = current?.imageWork.load
        }
    }
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
    let sourceRepresentations = GridSourceRepresentationStore()
    var sourceCoverage =
        PlayerBrowserGridSourceCoveragePlan<ObjectIdentifier>.empty
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
    var lastReconciledCurrentViewportRepresentationIDs = Set<ObjectIdentifier>()

    var hasCellFrameCorrectionTransforms = false
    var hasSourceSeamCompensationTransforms = false
    var hasPhantomSeamCompensationTransforms = false
    var currentPhantomPlan: PlayerBrowserGridPhantomPlan?
    var sourceCoverageRefreshIsDirty = false
    var phantomShapeRefreshIsDirty = false
    var destinationPlanRefreshIsDirty = false
    var managedCellPlanRefreshIsPending = false

    func deferClassificationPaint(for representationID: ObjectIdentifier) {
        sourceRepresentations.deferClassificationPaint(for: representationID)
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
        sourceRepresentations.preparedRepresentationIDs.contains(representationID)
            && !sourceRepresentations.lockedFallbackRepresentationIDs.contains(
                representationID
            )
            && (sourceCoverage.readyDestinationByRepresentation[
                representationID
            ] != nil || sourceRepresentations.cellFrameCorrections[
                representationID
            ] != nil)
    }

    func removeForegroundEligibility(
        for representationIDs: Set<ObjectIdentifier>
    ) {
        sourceRepresentations.removeForegroundEligibility(for: representationIDs)
    }

    func removeForegroundEligibility(
        for representationID: ObjectIdentifier
    ) {
        sourceRepresentations.removeForegroundEligibility(for: representationID)
    }

    func unregisterSourceRepresentation(
        _ representationID: ObjectIdentifier
    ) {
        precondition(sourceRepresentations.transitionImageLoads[
            representationID
        ] == nil)
        sourceRepresentations.remove(representationID)
        if sourceRepresentations.cellFrameCorrections.isEmpty {
            hasCellFrameCorrectionTransforms = false
        }
    }

    func registerSourceRepresentation(
        _ cell: MobilePlayerCollectionBrowserCell,
        itemIndex: Int
    ) {
        sourceRepresentations.register(cell, itemIndex: itemIndex)
    }

    func addCellFrameCorrection(
        _ correction: GridRenderCellFrameCorrection,
        for cell: UICollectionViewCell
    ) {
        let representationID = ObjectIdentifier(cell)
        sourceRepresentations.setGeometry(.corrected(correction), for: representationID)
    }

    func holdSourceRepresentationForMargin(
        _ representationID: ObjectIdentifier
    ) {
        sourceRepresentations.setGeometry(.marginHeld, for: representationID)
        if sourceRepresentations.cellFrameCorrections.isEmpty {
            hasCellFrameCorrectionTransforms = false
        }
    }

    func dropCellFrameCorrections(
        for representationIDs: Set<ObjectIdentifier>
    ) {
        sourceRepresentations.dropGeometry(for: representationIDs)
        if sourceRepresentations.cellFrameCorrections.isEmpty {
            hasCellFrameCorrectionTransforms = false
        }
    }

    func releaseUnpreparedMarginCoverage(
        for representationID: ObjectIdentifier
    ) {
        sourceRepresentations.setGeometry(.none, for: representationID)
        if sourceRepresentations.cellFrameCorrections.isEmpty {
            hasCellFrameCorrectionTransforms = false
        }
    }

    func clearForegroundEligibility() {
        sourceRepresentations.clearForegroundEligibility()
    }

    func resetForegroundEligibilityCoverage() {
        foregroundCurrentViewportCoverage.reset()
        foregroundTerminalViewportCoverage.reset()
    }

    func resetTransitionState() {
        reassignments.removeAll(keepingCapacity: true)
        assignedDestinationItems.removeAll(keepingCapacity: true)
        latticeItemShiftResolution = .unresolved
        selectedSourceItems.removeAll(keepingCapacity: true)
        viewportSelectedSourceItems.removeAll(keepingCapacity: true)
        sourceCoverage = .empty
        sourceRepresentations.reset()
        lastReconciledCurrentViewportRepresentationIDs.removeAll(
            keepingCapacity: true
        )
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
