// ∅ 2026 lil org

import QuartzCore
import UIKit

@MainActor
final class GridMaterializer {
    enum CarryoverRetention {
        case none
        case pendingBase
        case all
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

    struct DrainResult: Equatable {
        let processedCount: Int
        let elapsed: CFTimeInterval
        let stoppedForTimeLimit: Bool
    }

    typealias GridModeTransitionImageLoad = GridRenderTransitionImageLoad

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

    struct PromotionRepresentationKey: Hashable {
        let representationID: ObjectIdentifier
        let tokenIndex: Int
    }

    struct PendingDetailRepresentationKey: Hashable {
        let representationID: ObjectIdentifier
        let sourceItem: Int
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

    typealias Session = GridRenderSession
    typealias GridModeCellFrameCorrection =
        GridPlaneRenderer.GridModeCellFrameCorrection
    typealias GridModeCellFrameCorrectionGeometry =
        GridPlaneRenderer.GridModeCellFrameCorrectionGeometry
    typealias AppliedPlaneScale = GridPlaneRenderer.AppliedPlaneScale
    typealias SeamCompensation = GridPlaneRenderer.SeamCompensation
    private final class DisplayLinkTarget: NSObject {
        weak var materializer: GridMaterializer?

        @MainActor @objc func tick(_ displayLink: CADisplayLink) {
            materializer?.handleTick(displayLink)
        }
    }

    private static let jobLimit = 8
    private static let timeLimit: CFTimeInterval = 0.002
    private static let transitionJobLimit = 32
    private static let transitionMaximumTimeLimit: CFTimeInterval = 0.004
    private static let transitionFrameFraction: CFTimeInterval = 0.24
    private static let defaultFrameDuration: CFTimeInterval = 1.0 / 60
    private static let minimumSourceBatchCapacity = 4
    private(set) weak var collectionView:
        MobilePlayerCollectionBrowserCollectionView?
    private(set) weak var viewportView: UIView?
    private let planeRenderer: GridPlaneRenderer
    private let contentAccess: ContentAccess
    private let imageAccess: ImageAccess
    private let clock: () -> CFTimeInterval
    private var queue = MaterializationQueue()
    private var displayLink: CADisplayLink?
    private let displayLinkTarget = DisplayLinkTarget()
    private var activeSession: Session?
    private(set) var isDraining = false
    private(set) var transitionWorkQueueFilterPassCount: UInt = 0
    private(set) var hasTransitionPlaceholderTones = false
    private(set) var destinationPlanBuildCount = 0
    private(set) var sourceCoverageBuildCount = 0
    private(set) var foregroundEligibilityReconciliationCount = 0

    var phantomShapeStructureBuildCount: Int {
        planeRenderer.phantomShapeStructureBuildCount
    }

    var phantomShapeMaskBuildCount: Int {
        planeRenderer.phantomShapeMaskBuildCount
    }

    init(
        collectionView: MobilePlayerCollectionBrowserCollectionView,
        viewportView: UIView,
        contentAccess: ContentAccess,
        imageAccess: ImageAccess,
        clock: @escaping () -> CFTimeInterval
    ) {
        self.collectionView = collectionView
        self.viewportView = viewportView
        self.planeRenderer = GridPlaneRenderer(
            collectionView: collectionView,
            viewportView: viewportView
        )
        self.contentAccess = contentAccess
        self.imageAccess = imageAccess
        self.clock = clock
        displayLinkTarget.materializer = self
    }

    isolated deinit {
        displayLink?.invalidate()
        activeSession?.transitionImageLoads.values.forEach {
            $0.cancellation()
        }
        activeSession?.sourceOverscanCells.values.forEach {
            $0.cancelImageLoad()
        }
        activeSession?.phantomCells.values.forEach {
            $0.cancelImageLoad()
        }
    }

    func activate(session: Session) {
        activeSession = session
    }

    func deactivate(session: Session) {
        guard activeSession?.id == session.id else { return }
        activeSession = nil
    }

    func makePlaneContext(
        request: GridModePlaneRequest,
        session: Session
    ) -> GridModePlaneContext? {
        planeRenderer.makePlaneContext(
            request: request,
            session: session
        )
    }

    @discardableResult
    func applyZoomTransform(
        session: Session,
        scale: CGFloat,
        panDeltaY: CGFloat,
        sourceLayout: MobilePlayerBrowserLayout
    ) -> Bool {
        planeRenderer.applyZoomTransform(
            session: session,
            scale: scale,
            panDeltaY: panDeltaY,
            sourceLayout: sourceLayout
        )
    }

    func installZoomRebase(
        session: Session,
        currentTransform: CGAffineTransform,
        scale: CGFloat,
        panDeltaY: CGFloat,
        anchor: CGPoint,
        sourceLayout: MobilePlayerBrowserLayout
    ) {
        planeRenderer.installZoomRebase(
            session: session,
            currentTransform: currentTransform,
            scale: scale,
            panDeltaY: panDeltaY,
            anchor: anchor,
            sourceLayout: sourceLayout
        )
    }

    func reanchorSettlingRendering(
        session: Session,
        at screenPoint: CGPoint
    ) {
        planeRenderer.reanchorSettlingRendering(
            session: session,
            at: screenPoint
        )
    }

    func applyPlaneTransform(
        session: Session,
        plane: inout GridModePlaneContext,
        scale: CGFloat,
        settleProgress: CGFloat
    ) -> Bool {
        planeRenderer.applyPlaneTransform(
            session: session,
            plane: &plane,
            scale: scale,
            settleProgress: settleProgress
        )
    }

    func clearTransitionPlaceholderTones() {
        hasTransitionPlaceholderTones = false
    }

    func releaseReusablePhantomCells(session: Session) {
        session.reusablePhantomCells.removeAll(keepingCapacity: false)
    }

    func managedCells(session: Session?)
        -> [MobilePlayerCollectionBrowserCell] {
        guard let session else { return [] }
        return Array(session.sourceOverscanCells.values)
            + Array(session.phantomCells.values)
    }

    func phantomShapeMaskedFrames(session: Session?) -> [CGRect] {
        planeRenderer.phantomShapeMaskedFrames(session: session)
    }

    func viewportRenderCells(session: Session?)
        -> [MobilePlayerCollectionBrowserCell] {
        guard let session else { return visibleBrowserCells }
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

    var pendingWorkCount: Int {
        queue.count
    }

    var pendingDetailWorkCount: Int {
        queue.count {
            if case .detail = $0.kind { return true }
            return false
        }
    }

    var pendingDetailRepresentationIDs: Set<ObjectIdentifier> {
        queue.representationIDs { job in
            guard case let .detail(_, _, representationID, _) = job.kind
            else {
                return nil
            }
            return representationID
        }
    }

    var pendingDetailRepresentationKeys:
        Set<PendingDetailRepresentationKey> {
        queue.pendingDetailRepresentationKeys()
    }

    var pendingVisibleDetailRepresentationIDs: Set<ObjectIdentifier> {
        queue.representationIDs { job in
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
        queue.promotionRepresentationKeys()
    }

    var pendingTransitionImageCompletionWorkCount: Int {
        queue.count {
            if case .transitionImageCompletion = $0.kind { return true }
            return false
        }
    }

    var pendingVisibleTransitionImageCompletionWorkCount: Int {
        queue.count {
            guard $0.priority == .visibleRepresentation,
                  case .transitionImageCompletion = $0.kind else {
                return false
            }
            return true
        }
    }

    var isEmpty: Bool {
        queue.isEmpty
    }

    func requestGestureMaterializationBurst() {
        guard !queue.isEmpty || hasDeferredRenderRefresh else {
            return
        }
        activeSession?.pendingGestureMaterializationBurst = true
    }

    func cancelGestureMaterializationBurst(session: Session?) {
        session?.pendingGestureMaterializationBurst = false
    }

    @discardableResult
    func enqueue(
        sessionID: UUID,
        priority: MaterializationPriority,
        kind: MaterializationKind
    ) -> Bool {
        let didEnqueue = queue.enqueue(
            sessionID: sessionID,
            priority: priority,
            kind: kind
        )
        if didEnqueue {
            startIfNeeded()
        }
        return didEnqueue
    }

    @discardableResult
    func removeDetail(
        sessionID: UUID,
        planeID: UUID,
        contentGeneration: UInt,
        representationID: ObjectIdentifier,
        sourceItem: Int
    ) -> Bool {
        queue.removeDetail(
            sessionID: sessionID,
            planeID: planeID,
            contentGeneration: contentGeneration,
            representationID: representationID,
            sourceItem: sourceItem
        )
    }

    @discardableResult
    func removeTransitionImageCompletion(
        sessionID: UUID,
        loadID: UUID,
        representationID: ObjectIdentifier
    ) -> Bool {
        queue.removeTransitionImageCompletion(
            sessionID: sessionID,
            loadID: loadID,
            representationID: representationID
        )
    }

    @discardableResult
    func removePromotion(
        sessionID: UUID,
        contentGeneration: UInt,
        representationID: ObjectIdentifier,
        tokenIndex: Int
    ) -> Bool {
        queue.removePromotion(
            sessionID: sessionID,
            contentGeneration: contentGeneration,
            representationID: representationID,
            tokenIndex: tokenIndex
        )
    }

    func reprioritizeDetails(
        sessionID: UUID,
        planeID: UUID,
        contentGeneration: UInt,
        representationID: ObjectIdentifier,
        priority: MaterializationPriority
    ) {
        queue.reprioritizeDetails(
            sessionID: sessionID,
            planeID: planeID,
            contentGeneration: contentGeneration,
            representationID: representationID,
            priority: priority
        )
    }

    func reprioritizeTransitionImageCompletion(
        sessionID: UUID,
        loadID: UUID,
        representationID: ObjectIdentifier,
        priority: MaterializationPriority
    ) {
        queue.reprioritizeTransitionImageCompletion(
            sessionID: sessionID,
            loadID: loadID,
            representationID: representationID,
            priority: priority
        )
    }

    func reprioritizePromotion(
        sessionID: UUID,
        contentGeneration: UInt,
        representationID: ObjectIdentifier,
        tokenIndex: Int,
        priority: MaterializationPriority
    ) {
        queue.reprioritizePromotion(
            sessionID: sessionID,
            contentGeneration: contentGeneration,
            representationID: representationID,
            tokenIndex: tokenIndex,
            priority: priority
        )
    }

    func removeAll(where shouldRemove: (MaterializationJob) -> Bool) {
        queue.removeAll(where: shouldRemove)
    }

    func filterTransitionWork(
        where shouldRemove: (MaterializationJob) -> Bool
    ) {
        transitionWorkQueueFilterPassCount &+= 1
        queue.removeAll(where: shouldRemove)
    }

    func startIfNeeded() {
        guard displayLink == nil,
              !queue.isEmpty || hasDeferredRenderRefresh else {
            return
        }
        let displayLink = CADisplayLink(
            target: displayLinkTarget,
            selector: #selector(DisplayLinkTarget.tick(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @discardableResult
    func drain(
        budgetOverride: (jobs: Int, time: CFTimeInterval)? = nil,
        frameDuration: CFTimeInterval? = nil
    ) -> DrainResult {
        let start = clock()
        var processedCount = 0
        var canBatchDirtySource = false
        isDraining = true
        defer { isDraining = false }
        let usesGestureBudget: Bool
        if let session = activeSession {
            let requestedBurst = session.pendingGestureMaterializationBurst
            session.pendingGestureMaterializationBurst = false
            usesGestureBudget = requestedBurst && session.plane != nil
        } else {
            usesGestureBudget = false
        }
        let jobLimit = budgetOverride?.jobs ?? (usesGestureBudget
            ? Self.transitionJobLimit
            : Self.jobLimit)
        let effectiveFrameDuration = frameDuration.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? Self.defaultFrameDuration
        let transitionTimeLimit = min(
            Self.transitionMaximumTimeLimit,
            effectiveFrameDuration * Self.transitionFrameFraction
        )
        let timeLimit = budgetOverride?.time ?? (usesGestureBudget
            ? transitionTimeLimit
            : Self.timeLimit)
        while processedCount < jobLimit,
              clock() - start < timeLimit {
            guard let session = activeSession else { break }
            let remainingCount = jobLimit - processedCount
            if session.sourceCoverageRefreshIsDirty {
                if canBatchDirtySource,
                   let nextJob = queue.first,
                   canBatchSourceCoverageRefresh(
                       with: nextJob,
                       remainingCount: remainingCount
                   ) {
                    queue.removeFirst()
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
               ), queue.first?.priority != .visibleRepresentation {
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
               queue.isEmpty || remainingCount == 1 {
                guard flushDeferredRenderRefresh() else { break }
                processedCount += 1
                continue
            }
            guard let nextJob = queue.first else {
                guard let representationID =
                    nextDeferredClassificationRepresentationID(
                        session: session
                    ), paintDeferredClassification(
                        representationID,
                        session: session
                    )
                else {
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
            queue.removeFirst()
            processMaterialization(nextJob)
            processedCount += 1
            switch nextJob.kind {
            case .detail, .source, .transitionImageCompletion:
                canBatchDirtySource = true
            case .destination, .promotion:
                canBatchDirtySource = false
            }
        }
        if processedCount > 0, let session = activeSession {
            planeRenderer.refreshPhantomShapeExclusionMask(session: session)
        }
        let elapsed = max(clock() - start, 0)
        let stoppedForTimeLimit = (
            !queue.isEmpty || hasDeferredRenderRefresh
        ) && elapsed >= timeLimit
        if queue.isEmpty && !hasDeferredRenderRefresh {
            displayLink?.invalidate()
            displayLink = nil
        }
        return DrainResult(
            processedCount: processedCount,
            elapsed: elapsed,
            stoppedForTimeLimit: stoppedForTimeLimit
        )
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        queue.removeAll(keepingCapacity: false)
    }

    private func handleTick(_ displayLink: CADisplayLink) {
        _ = drain(
            frameDuration: displayLink.targetTimestamp - displayLink.timestamp
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
    func appliedPlaneScale() -> AppliedPlaneScale? {
        planeRenderer.appliedPlaneScale()
    }

    func applyCellFrameCorrections(
        session: Session,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) {
        planeRenderer.applyCellFrameCorrections(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        )
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
        planeRenderer.sourceSeamCompensation(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        )
    }

    /// A live plane owns the seam math: when its excess is zero the source
    /// cells must stay untransformed, never borrow the no-plane formula.
    private func currentSourceSeamCompensation(
        session: Session,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        planeRenderer.currentSourceSeamCompensation(
            session: session,
            appliedScale: appliedScale
        )
    }

    private func setTransform(
        _ transform: CGAffineTransform,
        on cell: UICollectionViewCell
    ) {
        planeRenderer.setTransform(transform, on: cell)
    }

    @discardableResult
    private func applySeamCompensation(
        to cell: UICollectionViewCell,
        compensation: SeamCompensation
    ) -> Bool {
        planeRenderer.applySeamCompensation(
            to: cell,
            compensation: compensation
        )
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
        planeRenderer.phantomSeamCompensation(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        )
    }

    func applySeamCompensations(
        session: Session,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) {
        planeRenderer.applySeamCompensations(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        )
    }

    func applySourceSeamCompensations(
        session: Session,
        naturalSpacing: CGFloat,
        targetSpacing: CGFloat,
        appliedScale: AppliedPlaneScale
    ) {
        planeRenderer.applySourceSeamCompensations(
            session: session,
            naturalSpacing: naturalSpacing,
            targetSpacing: targetSpacing,
            appliedScale: appliedScale
        )
    }

    private func applyNoPlaneSourceSeamCompensation(
        session: Session,
        to cell: MobilePlayerCollectionBrowserCell
    ) {
        planeRenderer.applyNoPlaneSourceSeamCompensation(
            session: session,
            to: cell
        )
    }

    func refreshPhantomShapeStructure(session: Session) {
        planeRenderer.refreshPhantomShapeStructure(session: session)
    }

    func refreshPhantomShapeExclusionMask(session: Session) {
        planeRenderer.refreshPhantomShapeExclusionMask(session: session)
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
            if planeRenderer.applyCellFrameCorrection(
                correction,
                to: cell,
                session: session,
                plane: plane
            ) {
                session.hasCellFrameCorrectionTransforms = true
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

    func reconcileCellFrameCorrectionClassifications(
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
        planeRenderer.removeCellFrameCorrection(
            session: session,
            for: cell
        )
    }

    private func removeCellFrameCorrections<Cells: Sequence>(
        session: Session,
        for cells: Cells
    ) where Cells.Element: UICollectionViewCell {
        planeRenderer.removeCellFrameCorrections(
            session: session,
            for: cells
        )
    }

    private func cellFrameCorrectionGeometry(
        session: Session,
        plane: GridModePlaneContext
    ) -> GridModeCellFrameCorrectionGeometry? {
        planeRenderer.cellFrameCorrectionGeometry(
            session: session,
            plane: plane
        )
    }

    private func cellFrameCorrection(
        for cell: UICollectionViewCell,
        destinationItem: Int,
        geometry: GridModeCellFrameCorrectionGeometry,
        settleProgress: CGFloat
    ) -> GridModeCellFrameCorrection? {
        planeRenderer.cellFrameCorrection(
            for: cell,
            destinationItem: destinationItem,
            geometry: geometry,
            settleProgress: settleProgress
        )
    }

    private func visualGeometry(
        for layout: MobilePlayerBrowserLayout
    ) -> MobilePlayerBrowserVisualLayoutGeometry {
        planeRenderer.visualGeometry(for: layout)
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

    func classifyDetailedSourceRepresentations(
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

    func refreshDetailedSourceRepresentations(
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

    func refreshSourceCoverageAndMaterialization(
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

    func destinationItem(
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

    func prioritizedSourceItems<S: Sequence>(
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
        planeRenderer.refreshPhantomShapeExclusionMask(session: session)
        if installedImmediateDestinationCoverage {
            return sourceCellEntries
        }
        if isDraining || session.currentPhantomPlan != nil {
            // Must not advance the plan generation: that discards every queued
            // phantom, and the replan that would re-enqueue them is the
            // lowest-priority job in the drain. installPhantomCell re-checks
            // coverage at install time, so stale queued jobs are harmless.
            session.destinationPlanRefreshIsDirty = true
            startIfNeeded()
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

    func reconcileForegroundDestinationEligibility(
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
            reprioritizeDetails(
                sessionID: session.id,
                planeID: plane.id,
                contentGeneration: session.transitionContentGeneration,
                representationID: representationID,
                priority: priority
            )
            if eligibleRepresentationIDs.contains(representationID),
               let load = session.transitionImageLoads[representationID] {
                reprioritizeTransitionImageCompletion(
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
                removePromotion(
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
                removePromotion(
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
            reprioritizePromotion(
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

    func extendDestinationCoverageIfNeeded(
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
        planeRenderer.replacePhantomShapeCoverage(
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

    func extendSourceCoverageIfNeeded(
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
            planeRenderer.replacePhantomShapeCoverage(
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
        planeRenderer.applySourcePresentation(
            to: cell,
            role: .awaitingClassification,
            visibleAlpha: session.lastContentFadeAlpha
        )
        planeRenderer.insertManualCell(
            cell,
            role: .sourceOverscan,
            session: session
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
        removePromotion(
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
        planeRenderer.insertManualCell(
            phantom,
            role: .destinationPhantom,
            session: session
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
            removePromotion(
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

    func registerSourceRepresentation(
        session: Session,
        cell: MobilePlayerCollectionBrowserCell,
        itemIndex: Int
    ) {
        let representationID = ObjectIdentifier(cell)
        if let registeredItem = session.cachedSourceRepresentations[
            representationID
        ]?.itemIndex, registeredItem != itemIndex {
            removePromotion(
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

    func enqueueViewportPromotions(
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
        guard let session = activeSession else { return }
        recycleSourceOverscanCell(session: session, at: indexPath.item)
        registerSourceRepresentation(
            session: session,
            cell: cell,
            itemIndex: indexPath.item
        )
        invalidateManagedCellPlans(session: session)
        guard let plane = session.plane else {
            applyNoPlaneSourceSeamCompensation(session: session, to: cell)
            planeRenderer.refreshPhantomShapeExclusionMask(session: session)
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
        guard let session = activeSession else { return }
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
            planeRenderer.refreshPhantomShapeExclusionMask(session: session)
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
        guard let session = activeSession else { return }
        invalidateManagedCellPlans(session: session)
        removeCellFrameCorrection(session: session, for: cell)
        let cellID = ObjectIdentifier(cell)
        session.unregisterSourceRepresentation(cellID)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        removePromotion(
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
        planeRenderer.resetSourcePresentation(
            on: browserCell,
            removingOpacityAnimation: false
        )
        markSourceCoverageRefreshDirty(session: session)
    }

    private func markSourceCoverageRefreshDirty(session: Session) {
        guard session.plane != nil else { return }
        session.sourceCoverageRefreshIsDirty = true
            startIfNeeded()
    }

    private func invalidateManagedCellPlans(session: Session) {
        guard !session.managedCellPlanRefreshIsPending else { return }
        session.managedCellPlanRefreshIsPending = true
        if session.plane == nil {
            session.sourcePlanePriorityCoverage.reset()
            advanceSourcePlanGeneration(session: session)
            if session.currentPhantomPlan != nil {
                startIfNeeded()
            }
        } else {
            session.sourcePlanePriorityCoverage.reset()
            session.destinationPlanePriorityCoverage.reset()
            session.destinationPlanRefreshIsDirty = true
            startIfNeeded()
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
        let defersToSettleFrame = isDraining
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
                      let activeSession = self.activeSession,
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
            guard let activeSession,
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
        let role: GridPlaneRenderer.SourcePresentationRole
        if session.marginCoverageRepresentationIDs.contains(representationID) {
            role = .marginCoverage
        } else if session.sourceRepresentationOwnsTransitionVisual(
            representationID
        ) {
            role = .destinationTransition
        } else {
            role = .sourceFallback
        }
        planeRenderer.applySourcePresentation(
            to: cell,
            role: role,
            visibleAlpha: visibleAlpha,
            interruptingAnimation: interruptingAnimation
        )
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

    func rearmLockedFallbackRepresentationsWhileContentIsHidden(
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

    func applyContentFade(
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
                  self.activeSession?.id == sessionID else {
                return
            }
            for representation in session.cachedSourceRepresentations.values
            where representation.cell.superview != nil
                && representation.cell.represents(
                    tokenIndex: representation.itemIndex
                ) {
                if !animated {
                    planeRenderer.interruptSourceOpacityAnimation(
                        on: representation.cell
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
            planeRenderer.animateContentFade(apply) { [weak session] in
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
        if !isEmpty,
           case let .representationKeys(representationKeys) = scope,
           let plane = session.plane {
            handledQueueInvalidationDirectly = true
            for entry in loads {
                removeTransitionImageCompletion(
                    sessionID: session.id,
                    loadID: entry.load.id,
                    representationID: entry.representationID
                )
            }
            if removePendingDetails {
                for representationKey in representationKeys {
                    removeDetail(
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
        } else if !isEmpty, !removePendingDetails {
            handledQueueInvalidationDirectly = true
            for entry in loads {
                removeTransitionImageCompletion(
                    sessionID: session.id,
                    loadID: entry.load.id,
                    representationID: entry.representationID
                )
            }
        }
        if !handledQueueInvalidationDirectly,
           !isEmpty,
           removePendingDetails || !loadIDs.isEmpty {
            filterTransitionWork { job in
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

    func clearTransitionContent(
        session: Session,
        carryoverRetention: CarryoverRetention = .none,
        installsDeferredBaseImages: Bool = false
    ) {
        session.transitionContentGeneration &+= 1
        cancelTransitionImageLoads(session: session)
        planeRenderer.removePhantomShape(session: session)
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
            planeRenderer.resetSourcePresentation(
                on: cell,
                removingOpacityAnimation: true
            )
        }
        recyclePhantomCells(session: session, retaining: [])
    }

    func tearDownPlaneRendering(
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
        planeRenderer.resetCollectionTransform()
        session.lastRenderedScale = 1
        recycleSourceOverscanCells(session: session, retaining: [])
        session.sourceOverscanCells.removeAll(keepingCapacity: false)
    }

    func captureVisibleCarryoverSources(
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

    func installCarryoverContent(
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
        guard let activeSession,
              activeSession.id == session.id else {
            return
        }
        enqueue(
            sessionID: session.id,
            priority: priority,
            kind: kind
        )
    }

    private func advanceDestinationPlanGeneration(session: Session) {
        session.destinationPlaneCellPlanGeneration &+= 1
        removeAll { job in
            guard job.sessionID == session.id else { return false }
            if case .destination = job.kind {
                return true
            }
            return false
        }
    }

    private func advanceSourcePlanGeneration(session: Session) {
        session.sourcePlaneCellPlanGeneration &+= 1
        removeAll { job in
            guard job.sessionID == session.id else { return false }
            if case .source = job.kind {
                return true
            }
            return false
        }
    }

    private var hasDeferredRenderRefresh: Bool {
        guard let session = activeSession else { return false }
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

    private func processMaterialization(_ job: MaterializationJob) {
        guard let session = activeSession,
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
        guard let session = activeSession else { return false }
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
        planeRenderer.replacePhantomShapeCoverage(
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
}
