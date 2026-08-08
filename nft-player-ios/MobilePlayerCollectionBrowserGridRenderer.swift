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
        fileprivate(set) var lastContentFadeAlpha: CGFloat = 0
        fileprivate(set) var reassignments = [Int: Int]()
        fileprivate(set) var selectedSourceItems = Set<Int>()
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
        fileprivate(set) var cellFrameCorrections = [(
            cell: UICollectionViewCell,
            correction: GridModeCellFrameCorrection
        )]()
        fileprivate(set) var hasCellFrameCorrectionTransforms = false
        fileprivate(set) var currentPhantomPlan: PlayerBrowserGridPhantomPlan?
        fileprivate(set) var sourceCoverageRefreshIsDirty = false
        fileprivate(set) var phantomShapeRefreshIsDirty = false
        fileprivate(set) var destinationPlanRefreshIsDirty = false
        fileprivate(set) var managedCellPlanRefreshIsPending = false

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
            removeForegroundEligibility(for: representationID)
            detailedSourceCellItems.removeValue(forKey: representationID)
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
            reassignments.removeAll(keepingCapacity: true)
            selectedSourceItems.removeAll(keepingCapacity: true)
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
            lastContentFadeAlpha = 0
            lastSettleProgress = 0
            hasCellFrameCorrectionTransforms = false
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
        let ineligibleFallbackSourceItems: Set<Int>
        fileprivate(set) var isComplete = false

        fileprivate init(
            session: Session,
            plane: GridModePlaneContext?,
            sources: [MobilePlayerBrowserGridCarryoverSource],
            ineligibleFallbackSourceItems: Set<Int>
        ) {
            self.session = session
            self.plane = plane
            self.sources = sources
            self.ineligibleFallbackSourceItems =
                ineligibleFallbackSourceItems
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

    struct GridModeCellFrameCorrection {
        let centerDelta: CGPoint
        let sizeDelta: CGSize
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

    private enum DetailedSourceMaterializationCandidates {
        case unpreparedSourceCells([SourceCellEntry])
        case eligibleRepresentationIDs(Set<ObjectIdentifier>)
    }

    private final class PhantomShapeView: UIView {
        let repeatedRowLayer = CAShapeLayer()
        let repeatedRowsLayer = CAReplicatorLayer()
        let finalRowLayer = CAShapeLayer()
        let solidCoverageLayer = CAShapeLayer()
        let candidateLayer = CAShapeLayer()
        let exclusionMaskLayer = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            makeBackgroundTransparent()
            isUserInteractionEnabled = false
            repeatedRowsLayer.addSublayer(repeatedRowLayer)
            layer.addSublayer(repeatedRowsLayer)
            layer.addSublayer(finalRowLayer)
            layer.addSublayer(solidCoverageLayer)
            layer.addSublayer(candidateLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError()
        }

        func reset(fillColor: CGColor) {
            repeatedRowsLayer.isHidden = true
            repeatedRowsLayer.instanceCount = 0
            repeatedRowLayer.path = nil
            finalRowLayer.isHidden = true
            finalRowLayer.path = nil
            solidCoverageLayer.isHidden = true
            solidCoverageLayer.path = nil
            candidateLayer.isHidden = true
            candidateLayer.path = nil
            layer.mask = nil
            for shapeLayer in [
                repeatedRowLayer,
                finalRowLayer,
                solidCoverageLayer,
                candidateLayer
            ] {
                shapeLayer.fillColor = fillColor
            }
        }
    }

    private enum MaterializationKind {
        case detail(
            planeID: UUID,
            contentGeneration: UInt,
            representationID: ObjectIdentifier,
            sourceItem: Int
        )
        case destination(
            planeID: UUID,
            contentGeneration: UInt,
            planGeneration: UInt,
            candidate: PlayerBrowserGridPhantomCandidate,
            requiredImageQuality: CollectionBrowseImageQuality
        )
        case source(
            planeID: UUID?,
            contentGeneration: UInt,
            planGeneration: UInt,
            candidate: PlayerBrowserGridPhantomCandidate
        )
        case promotion(
            contentGeneration: UInt,
            representationID: ObjectIdentifier,
            tokenIndex: Int
        )
        case transitionImageCompletion(
            GridModeTransitionImageCompletion
        )
    }

    private enum MaterializationPriority: Int, CaseIterable, Comparable {
        case visibleRepresentation = 0
        case destinationViewport = 1
        case sourceViewport = 2
        case deferred = 3

        static func < (
            lhs: MaterializationPriority,
            rhs: MaterializationPriority
        ) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct MaterializationJob {
        let sessionID: UUID
        let priority: MaterializationPriority
        let sequence: UInt
        let kind: MaterializationKind
    }

    private struct MaterializationQueue {
        private enum KindIdentity: Hashable {
            case detail(UUID, UInt, ObjectIdentifier, Int)
            case destination(UUID, UInt, UInt, Int)
            case source(UUID?, UInt, UInt, Int)
            case promotion(UInt, ObjectIdentifier, Int)
            case transitionImageCompletion(UUID, ObjectIdentifier)
        }

        private struct JobKey: Hashable {
            let sessionID: UUID
            let kind: KindIdentity
        }

        private struct DetailRepresentationKey: Hashable {
            let sessionID: UUID
            let planeID: UUID
            let contentGeneration: UInt
            let representationID: ObjectIdentifier
        }

        private struct HeapEntry {
            let key: JobKey
            let sequence: UInt
        }

        private var jobsByKey = [JobKey: MaterializationJob]()
        private var detailJobKeysByRepresentation = [
            DetailRepresentationKey: Set<JobKey>
        ]()
        private var heaps = Array(
            repeating: [HeapEntry](),
            count: MaterializationPriority.allCases.count
        )
        private var sequence: UInt = 0

        var count: Int {
            jobsByKey.count
        }

        var isEmpty: Bool {
            jobsByKey.isEmpty
        }

        func count(where predicate: (MaterializationJob) -> Bool) -> Int {
            jobsByKey.values.lazy.filter(predicate).count
        }

        func representationIDs(
            where transform: (MaterializationJob) -> ObjectIdentifier?
        ) -> Set<ObjectIdentifier> {
            Set(jobsByKey.values.compactMap(transform))
        }

        func promotionRepresentationKeys() -> Set<PromotionRepresentationKey> {
            Set(jobsByKey.values.compactMap { job in
                guard case let .promotion(
                    _,
                    representationID,
                    tokenIndex
                ) = job.kind else {
                    return nil
                }
                return PromotionRepresentationKey(
                    representationID: representationID,
                    tokenIndex: tokenIndex
                )
            })
        }

        var first: MaterializationJob? {
            mutating get {
                for priorityIndex in heaps.indices {
                    discardStaleHeadEntries(at: priorityIndex)
                    guard let entry = heaps[priorityIndex].first else {
                        continue
                    }
                    return jobsByKey[entry.key]
                }
                return nil
            }
        }

        @discardableResult
        mutating func enqueue(
            sessionID: UUID,
            priority: MaterializationPriority,
            kind: MaterializationKind
        ) -> Bool {
            let key = JobKey(
                sessionID: sessionID,
                kind: Self.identity(for: kind)
            )
            if let existingJob = jobsByKey[key] {
                guard priority < existingJob.priority else { return false }
                let upgradedJob = MaterializationJob(
                    sessionID: existingJob.sessionID,
                    priority: priority,
                    sequence: existingJob.sequence,
                    kind: kind
                )
                jobsByKey[key] = upgradedJob
                insert(
                    HeapEntry(key: key, sequence: upgradedJob.sequence),
                    at: priority.rawValue
                )
                return true
            }
            sequence &+= 1
            let job = MaterializationJob(
                sessionID: sessionID,
                priority: priority,
                sequence: sequence,
                kind: kind
            )
            jobsByKey[key] = job
            indexDetailJob(key)
            insert(
                HeapEntry(key: key, sequence: job.sequence),
                at: priority.rawValue
            )
            return true
        }

        @discardableResult
        mutating func removeDetail(
            sessionID: UUID,
            planeID: UUID,
            contentGeneration: UInt,
            representationID: ObjectIdentifier,
            sourceItem: Int
        ) -> Bool {
            remove(JobKey(
                sessionID: sessionID,
                kind: .detail(
                    planeID,
                    contentGeneration,
                    representationID,
                    sourceItem
                )
            )) != nil
        }

        @discardableResult
        mutating func removeTransitionImageCompletion(
            sessionID: UUID,
            loadID: UUID,
            representationID: ObjectIdentifier
        ) -> Bool {
            remove(JobKey(
                sessionID: sessionID,
                kind: .transitionImageCompletion(loadID, representationID)
            )) != nil
        }

        @discardableResult
        mutating func removePromotion(
            sessionID: UUID,
            contentGeneration: UInt,
            representationID: ObjectIdentifier,
            tokenIndex: Int
        ) -> Bool {
            remove(JobKey(
                sessionID: sessionID,
                kind: .promotion(
                    contentGeneration,
                    representationID,
                    tokenIndex
                )
            )) != nil
        }

        mutating func reprioritizeDetails(
            sessionID: UUID,
            planeID: UUID,
            contentGeneration: UInt,
            representationID: ObjectIdentifier,
            priority: MaterializationPriority
        ) {
            let representationKey = DetailRepresentationKey(
                sessionID: sessionID,
                planeID: planeID,
                contentGeneration: contentGeneration,
                representationID: representationID
            )
            for key in detailJobKeysByRepresentation[representationKey]
                ?? [] {
                reprioritize(key, to: priority)
            }
        }

        mutating func reprioritizeTransitionImageCompletion(
            sessionID: UUID,
            loadID: UUID,
            representationID: ObjectIdentifier,
            priority: MaterializationPriority
        ) {
            reprioritize(
                JobKey(
                    sessionID: sessionID,
                    kind: .transitionImageCompletion(
                        loadID,
                        representationID
                    )
                ),
                to: priority
            )
        }

        mutating func reprioritizePromotion(
            sessionID: UUID,
            contentGeneration: UInt,
            representationID: ObjectIdentifier,
            tokenIndex: Int,
            priority: MaterializationPriority
        ) {
            reprioritize(
                JobKey(
                    sessionID: sessionID,
                    kind: .promotion(
                        contentGeneration,
                        representationID,
                        tokenIndex
                    )
                ),
                to: priority
            )
        }

        @discardableResult
        mutating func removeFirst() -> MaterializationJob {
            for priorityIndex in heaps.indices {
                discardStaleHeadEntries(at: priorityIndex)
                guard let entry = popFirst(at: priorityIndex),
                      let job = jobsByKey.removeValue(forKey: entry.key) else {
                    continue
                }
                removeDetailJobIndex(entry.key)
                if jobsByKey.isEmpty {
                    for index in heaps.indices {
                        heaps[index].removeAll(keepingCapacity: true)
                    }
                }
                return job
            }
            preconditionFailure("Cannot remove a job from an empty queue")
        }

        mutating func removeAll(
            where shouldRemove: (MaterializationJob) -> Bool
        ) {
            let keys = jobsByKey.compactMap { key, job in
                shouldRemove(job) ? key : nil
            }
            guard !keys.isEmpty else { return }
            for key in keys {
                jobsByKey.removeValue(forKey: key)
                removeDetailJobIndex(key)
            }
            rebuildHeaps()
        }

        mutating func removeAll(keepingCapacity: Bool) {
            jobsByKey.removeAll(keepingCapacity: keepingCapacity)
            detailJobKeysByRepresentation.removeAll(
                keepingCapacity: keepingCapacity
            )
            for index in heaps.indices {
                heaps[index].removeAll(keepingCapacity: keepingCapacity)
            }
        }

        private mutating func remove(
            _ key: JobKey
        ) -> MaterializationJob? {
            guard let job = jobsByKey.removeValue(forKey: key) else {
                return nil
            }
            removeDetailJobIndex(key)
            if jobsByKey.isEmpty {
                for index in heaps.indices {
                    heaps[index].removeAll(keepingCapacity: true)
                }
            }
            return job
        }

        private mutating func indexDetailJob(_ key: JobKey) {
            guard let representationKey = Self.detailRepresentationKey(
                for: key
            ) else {
                return
            }
            detailJobKeysByRepresentation[representationKey, default: []]
                .insert(key)
        }

        private mutating func removeDetailJobIndex(_ key: JobKey) {
            guard let representationKey = Self.detailRepresentationKey(
                for: key
            ),
            var keys = detailJobKeysByRepresentation[representationKey] else {
                return
            }
            keys.remove(key)
            if keys.isEmpty {
                detailJobKeysByRepresentation.removeValue(
                    forKey: representationKey
                )
            } else {
                detailJobKeysByRepresentation[representationKey] = keys
            }
        }

        private mutating func reprioritize(
            _ key: JobKey,
            to priority: MaterializationPriority
        ) {
            guard let job = jobsByKey[key],
                  job.priority != priority else {
                return
            }
            let updatedJob = MaterializationJob(
                sessionID: job.sessionID,
                priority: priority,
                sequence: job.sequence,
                kind: job.kind
            )
            jobsByKey[key] = updatedJob
            insert(
                HeapEntry(key: key, sequence: updatedJob.sequence),
                at: priority.rawValue
            )
        }

        private mutating func discardStaleHeadEntries(at priorityIndex: Int) {
            while let entry = heaps[priorityIndex].first {
                guard let job = jobsByKey[entry.key],
                      job.priority.rawValue == priorityIndex,
                      job.sequence == entry.sequence else {
                    _ = popFirst(at: priorityIndex)
                    continue
                }
                return
            }
        }

        private mutating func rebuildHeaps() {
            for index in heaps.indices {
                heaps[index].removeAll(keepingCapacity: true)
            }
            for (key, job) in jobsByKey {
                heaps[job.priority.rawValue].append(HeapEntry(
                    key: key,
                    sequence: job.sequence
                ))
            }
            for priorityIndex in heaps.indices {
                guard heaps[priorityIndex].count > 1 else { continue }
                for parentIndex in stride(
                    from: heaps[priorityIndex].count / 2 - 1,
                    through: 0,
                    by: -1
                ) {
                    siftDown(
                        from: parentIndex,
                        at: priorityIndex
                    )
                }
            }
        }

        private mutating func insert(_ entry: HeapEntry, at priorityIndex: Int) {
            heaps[priorityIndex].append(entry)
            var childIndex = heaps[priorityIndex].count - 1
            while childIndex > 0 {
                let parentIndex = (childIndex - 1) / 2
                guard heaps[priorityIndex][childIndex].sequence
                        < heaps[priorityIndex][parentIndex].sequence else {
                    return
                }
                heaps[priorityIndex].swapAt(childIndex, parentIndex)
                childIndex = parentIndex
            }
        }

        private mutating func popFirst(at priorityIndex: Int) -> HeapEntry? {
            guard !heaps[priorityIndex].isEmpty else { return nil }
            if heaps[priorityIndex].count == 1 {
                return heaps[priorityIndex].removeLast()
            }
            let first = heaps[priorityIndex][0]
            heaps[priorityIndex][0] = heaps[priorityIndex].removeLast()
            siftDown(from: 0, at: priorityIndex)
            return first
        }

        private mutating func siftDown(
            from startIndex: Int,
            at priorityIndex: Int
        ) {
            var parentIndex = startIndex
            while true {
                let leftIndex = parentIndex * 2 + 1
                guard leftIndex < heaps[priorityIndex].count else { break }
                let rightIndex = leftIndex + 1
                let childIndex: Int
                if rightIndex < heaps[priorityIndex].count,
                   heaps[priorityIndex][rightIndex].sequence
                    < heaps[priorityIndex][leftIndex].sequence {
                    childIndex = rightIndex
                } else {
                    childIndex = leftIndex
                }
                guard heaps[priorityIndex][childIndex].sequence
                        < heaps[priorityIndex][parentIndex].sequence else {
                    break
                }
                heaps[priorityIndex].swapAt(parentIndex, childIndex)
                parentIndex = childIndex
            }
        }

        private static func identity(
            for kind: MaterializationKind
        ) -> KindIdentity {
            switch kind {
            case let .detail(plane, generation, id, item):
                return .detail(plane, generation, id, item)
            case let .destination(
                plane,
                contentGeneration,
                planGeneration,
                candidate,
                _
            ):
                return .destination(
                    plane,
                    contentGeneration,
                    planGeneration,
                    candidate.destinationItemIndex
                )
            case let .source(
                plane,
                contentGeneration,
                planGeneration,
                candidate
            ):
                return .source(
                    plane,
                    contentGeneration,
                    planGeneration,
                    candidate.destinationItemIndex
                )
            case let .promotion(contentGeneration, id, item):
                return .promotion(contentGeneration, id, item)
            case let .transitionImageCompletion(completion):
                return .transitionImageCompletion(
                    completion.loadID,
                    completion.representationID
                )
            }
        }

        private static func detailRepresentationKey(
            for key: JobKey
        ) -> DetailRepresentationKey? {
            guard case let .detail(
                planeID,
                contentGeneration,
                representationID,
                _
            ) = key.kind else {
                return nil
            }
            return DetailRepresentationKey(
                sessionID: key.sessionID,
                planeID: planeID,
                contentGeneration: contentGeneration,
                representationID: representationID
            )
        }
    }

    private static let materializationJobLimit = 8
    private static let materializationTimeLimit: CFTimeInterval = 0.002
    private static let minimumSourceBatchCapacity = 4
    private static let contentFadeOutDuration: TimeInterval = 0.12

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
        lifecycle = .active(Session(
            gestureAnchor: gestureAnchor,
            sourceLayout: sourceLayout,
            wasCollectionViewPrefetchingEnabled:
                wasCollectionViewPrefetchingEnabled
        ))
        return true
    }

    func updateGestureAnchor(_ gestureAnchor: GridModeGestureAnchor?) {
        currentSession?.gestureAnchor = gestureAnchor
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
                panDeltaY: panDeltaY
            )
        }
        guard let anchor = session.gestureAnchor else { return false }
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
        enqueueViewportPromotions(session: session)
        applyContentFade(session: session, alpha: 0, animated: true)
        return true
    }

    @discardableResult
    func renderSettle(
        id: UUID,
        scale: CGFloat,
        settleProgress: CGFloat,
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
            settleProgress: settleProgress
        )
        session.plane = plane
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
        mode: MobileCollectionBrowserGridMode
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
        let sources = captureVisibleCarryoverSources(
            session: session,
            anchorTokenIndex: plane.anchorTokenIndex
        )
        let ineligibleFallbackSourceItems = Set(
            session.selectedSourceItems.filter {
                destinationItem(
                    session: session,
                    sourceItem: $0,
                    plane: plane
                ) == nil
            }
        )
        let terminalContentOffsetY = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        ).incomingContentOffsetY
        cancelMaterializationPump()
        let commit = CommitState(
            session: session,
            plane: plane,
            sources: sources,
            ineligibleFallbackSourceItems:
                ineligibleFallbackSourceItems
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
            ineligibleFallbackSourceItems:
                commit.ineligibleFallbackSourceItems
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
            ineligibleFallbackSourceItems: []
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
        session.plane = nil
        clearTransitionContent(
            session: session,
            carryoverRetention: .pendingBase
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
        settleProgress: CGFloat
    ) {
        guard let collectionView, let viewportView else { return }
        let settleProgress = PlayerBrowserGridCrossfade.sanitizedProgress(
            settleProgress
        )
        session.lastSettleProgress = settleProgress
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
        applyCellFrameCorrections(
            session: session,
            settleProgress: settleProgress,
            outgoingPlane: outgoingPlane
        )
        enqueueViewportPromotions(session: session)
        reconcileForegroundDestinationEligibility(
            session: session,
            plane: plane
        )
        if settleProgress > 0 {
            applyContentFade(
                session: session,
                alpha: PlayerBrowserGridCrossfade.incomingContentAlpha(
                    settleProgress: settleProgress
                ),
                animated: false
            )
        } else {
            applyContentFade(session: session, alpha: 0, animated: true)
        }
    }

    private func applyCellFrameCorrections(
        session: Session,
        settleProgress: CGFloat,
        outgoingPlane: PlayerBrowserGridCrossfadePlane
    ) {
        guard !session.cellFrameCorrections.isEmpty,
              outgoingPlane.scaleX > 0,
              outgoingPlane.scaleY > 0,
              settleProgress > 0
                || session.hasCellFrameCorrectionTransforms else {
            return
        }
        session.hasCellFrameCorrectionTransforms = settleProgress > 0
        for (cell, correction) in session.cellFrameCorrections {
            applyCellFrameCorrection(
                correction,
                to: cell,
                settleProgress: settleProgress,
                outgoingPlane: outgoingPlane
            )
        }
    }

    private func applyCellFrameCorrection(
        _ correction: GridModeCellFrameCorrection,
        to cell: UICollectionViewCell,
        settleProgress: CGFloat,
        outgoingPlane: PlayerBrowserGridCrossfadePlane
    ) {
        guard settleProgress > 0 else {
            if cell.transform != .identity {
                cell.transform = .identity
            }
            return
        }
        let screenWidth = cell.bounds.width * outgoingPlane.scaleX
        let screenHeight = cell.bounds.height * outgoingPlane.scaleY
        cell.transform = CGAffineTransform(
            translationX: settleProgress * correction.centerDelta.x
                / outgoingPlane.scaleX,
            y: settleProgress * correction.centerDelta.y
                / outgoingPlane.scaleY
        ).scaledBy(
            x: screenWidth > 0
                ? 1 + settleProgress * correction.sizeDelta.width
                    / screenWidth
                : 1,
            y: screenHeight > 0
                ? 1 + settleProgress * correction.sizeDelta.height
                    / screenHeight
                : 1
        )
    }

    private func registerCellFrameCorrection(
        session: Session,
        cell: UICollectionViewCell,
        destinationItem: Int,
        plane: GridModePlaneContext
    ) {
        removeCellFrameCorrection(session: session, for: cell)
        guard let geometry = cellFrameCorrectionGeometry(
            session: session,
            plane: plane
        ),
              let correction = cellFrameCorrection(
                  for: cell,
                  destinationItem: destinationItem,
                  geometry: geometry
              ) else {
            return
        }
        session.cellFrameCorrections.append((cell, correction))
        guard session.lastSettleProgress > 0 else { return }
        let outgoingPlane = plane.crossfade.outgoingPlane(
            scale: session.lastRenderedScale,
            panDeltaY: session.lastPanDeltaY
        )
        applyCellFrameCorrection(
            correction,
            to: cell,
            settleProgress: session.lastSettleProgress,
            outgoingPlane: outgoingPlane
        )
        session.hasCellFrameCorrectionTransforms = true
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
        session.cellFrameCorrections.removeAll {
            cellIDs.contains(ObjectIdentifier($0.cell))
        }
        for cell in cells where cell.transform != .identity {
            cell.transform = .identity
        }
        if session.cellFrameCorrections.isEmpty {
            session.hasCellFrameCorrectionTransforms = false
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

    private func cellFrameCorrection(
        for cell: UICollectionViewCell,
        destinationItem: Int,
        geometry: GridModeCellFrameCorrectionGeometry
    ) -> GridModeCellFrameCorrection? {
        guard let collectionView,
              let viewportView,
              let destinationFrame = geometry.destinationGeometry.itemFrame(
                  at: destinationItem
              ) else {
            return nil
        }
        let currentScreenFrame = cell.convert(cell.bounds, to: viewportView)
        let terminalScreenFrame = currentScreenFrame.applying(
            geometry.currentToTerminal
        )
        let destinationScreenFrame = destinationFrame.offsetBy(
            dx: -collectionView.contentOffset.x,
            dy: -geometry.terminalScreenOffsetY
        )
        let centerDelta = CGPoint(
            x: destinationScreenFrame.midX - terminalScreenFrame.midX,
            y: destinationScreenFrame.midY - terminalScreenFrame.midY
        )
        let sizeDelta = CGSize(
            width: destinationScreenFrame.width - terminalScreenFrame.width,
            height: destinationScreenFrame.height - terminalScreenFrame.height
        )
        guard centerDelta.x.isFinite,
              centerDelta.y.isFinite,
              sizeDelta.width.isFinite,
              sizeDelta.height.isFinite else {
            return nil
        }
        return GridModeCellFrameCorrection(
            centerDelta: centerDelta,
            sizeDelta: sizeDelta
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

    private func classifyDetailedSourceRepresentations(
        session: Session,
        plane: GridModePlaneContext
    ) {
        let sourceCells = viewportSourceCells(session: session)
        session.selectedSourceItems = Set(PlayerBrowserGridDetailPlan(
            candidateItemIndices: sourceCells.map { $0.indexPath.item },
            anchorItemIndex: plane.anchorTokenIndex,
            maximumCount:
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
        ).itemIndices)
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
        guard let detailRect = session.viewportDetailCoverage.replacementRect(
            requiredRect: viewportRect,
            buffer: priorityCoverageBuffer(for: viewportRect)
        ) else {
            return false
        }
        let detailCells = sourceCells(
            session: session,
            intersecting: detailRect
        )
        let viewportCells = detailCells.filter {
            cell($0.cell, intersects: viewportRect)
        }
        let viewportItems = PlayerBrowserGridDetailPlan(
            candidateItemIndices: viewportCells.map { $0.indexPath.item },
            anchorItemIndex: plane.anchorTokenIndex,
            maximumCount:
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
        ).itemIndices
        let viewportItemSet = Set(viewportItems)
        let marginItems = PlayerBrowserGridDetailPlan(
            candidateItemIndices: detailCells.compactMap {
                viewportItemSet.contains($0.indexPath.item)
                    ? nil
                    : $0.indexPath.item
            },
            anchorItemIndex: plane.anchorTokenIndex,
            maximumCount: max(
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
                    - viewportItems.count,
                0
            )
        ).itemIndices
        let selectedItems = viewportItemSet.union(marginItems)
        guard selectedItems != session.selectedSourceItems else { return false }
        let removedItems = session.selectedSourceItems.subtracting(
            selectedItems
        )
        session.selectedSourceItems = selectedItems
        clearDetailedSourceItems(session: session, itemIndices: removedItems)
        return true
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
        let fromGeometry = visualGeometry(
            for: plane.transitionLayout.fromLayout
        )
        let toGeometry = visualGeometry(for: plane.transitionLayout.toLayout)
        guard let fromFrame = fromGeometry.itemFrame(at: sourceItem),
              let destinationItem = toGeometry.nearestItemIndex(
                  to: plane.latticeMap.destinationPoint(
                      fromSource: CGPoint(
                          x: fromFrame.midX,
                          y: fromFrame.midY
                      )
                  )
              ) else {
            return nil
        }
        session.reassignments[sourceItem] = destinationItem
        return destinationItem
    }

    @discardableResult
    private func refreshSourceCoverage(
        session: Session,
        plane: GridModePlaneContext
    ) -> [SourceCellEntry] {
        sourceCoverageBuildCount += 1
        session.resetForegroundEligibilityCoverage()
        let sourceRect = sourceRepresentationRect()
        let sourceCellEntries = sourceCells(
            session: session,
            intersecting: sourceRect
        )
        session.cachedSourceRepresentations = session
            .cachedSourceRepresentations.filter { _, representation in
                representation.cell.superview != nil
                    && representation.cell.represents(
                        tokenIndex: representation.itemIndex
                    )
        }
        for entry in sourceCellEntries {
            session.cachedSourceRepresentations[
                ObjectIdentifier(entry.cell)
            ] = (itemIndex: entry.indexPath.item, cell: entry.cell)
        }
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
            if !newlyLockedRepresentationIDs.isEmpty {
                plan = makePlan()
            }
        }
        session.sourceCoverage = plan
        let representedCells = Dictionary(
            uniqueKeysWithValues: sourceCellEntries.map {
                (ObjectIdentifier($0.cell), $0.cell)
            }
        )
        for (representationID, cell) in representedCells {
            if plan.readyDestinationByRepresentation[representationID] != nil {
                cell.alpha = 1
                cell.setTransitionContentAlpha(session.lastContentFadeAlpha)
            } else {
                cell.alpha = 1 - session.lastContentFadeAlpha
            }
        }
        if isDrainingMaterialization || session.currentPhantomPlan != nil {
            if !session.destinationPlanRefreshIsDirty {
                advanceDestinationPlanGeneration(session: session)
            }
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
            cell.clearTransitionContent(
                preservingCarryover: cell.holdsCarryoverForPendingBaseImage
            )
            cell.alpha = 1 - session.lastContentFadeAlpha
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
        cell.alpha = 1 - session.lastContentFadeAlpha
        insertCellAbovePhantomShape(session: session, cell: cell)
        session.sourceOverscanCells[itemIndex] = cell
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
        insertCellAbovePhantomShape(session: session, cell: phantom)
        session.phantomCells[candidate.destinationItemIndex] = phantom
        session.phantomShapeRefreshIsDirty = true
        invalidateViewportBasePromotion(session: session)
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
        cell: MobilePlayerCollectionBrowserCell
    ) {
        guard let collectionView else { return }
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

    private func replacePhantomShapeCoverage(
        session: Session,
        candidates: [PlayerBrowserGridPhantomCandidate],
        shapeCoverage: PlayerBrowserGridPhantomShapeCoverage?
    ) {
        guard let collectionView else { return }
        let candidateBounds = candidates.first.map { first in
            candidates.dropFirst().reduce(first.sourceFrame) {
                $0.union($1.sourceFrame)
            }
        }
        let coverageBounds: CGRect
        if let candidateBounds, let shapeBounds = shapeCoverage?.coverageBounds {
            coverageBounds = candidateBounds.union(shapeBounds)
        } else if let candidateBounds {
            coverageBounds = candidateBounds
        } else if let shapeBounds = shapeCoverage?.coverageBounds {
            coverageBounds = shapeBounds
        } else {
            session.phantomShapeView?.isHidden = true
            return
        }
        let placeholderView: PhantomShapeView
        if let existingView = session.phantomShapeView as? PhantomShapeView {
            placeholderView = existingView
        } else {
            session.phantomShapeView?.removeFromSuperview()
            placeholderView = PhantomShapeView(frame: coverageBounds)
            session.phantomShapeView = placeholderView
        }
        collectionView.insertSubview(placeholderView, at: 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        placeholderView.isHidden = false
        placeholderView.frame = coverageBounds
        placeholderView.reset(
            fillColor: mobilePlayerBrowserPlaceholderToneColor.cgColor
        )
        if let shapeCoverage {
            installPhantomShapeCoverage(
                shapeCoverage,
                coverageBounds: coverageBounds,
                in: placeholderView
            )
        }
        if !candidates.isEmpty {
            placeholderView.candidateLayer.isHidden = false
            placeholderView.candidateLayer.frame = placeholderView.bounds
            placeholderView.candidateLayer.path = makePhantomPath(
                frames: candidates.lazy.map(\.sourceFrame),
                relativeTo: coverageBounds
            )
        }
    }

    private func installPhantomShapeCoverage(
        _ coverage: PlayerBrowserGridPhantomShapeCoverage,
        coverageBounds: CGRect,
        in placeholderView: PhantomShapeView
    ) {
        let excludedFrames = coverage.excludedFrames
        switch coverage {
        case let .repeatedRows(rows):
            if rows.rowCount > 0, let firstFrame = rows.firstRowFrames.first {
                let rowBounds = rows.firstRowFrames.dropFirst().reduce(
                    firstFrame
                ) { $0.union($1) }
                placeholderView.repeatedRowsLayer.isHidden = false
                placeholderView.repeatedRowsLayer.frame =
                    placeholderView.bounds
                placeholderView.repeatedRowsLayer.masksToBounds = true
                placeholderView.repeatedRowsLayer.instanceCount = rows.rowCount
                placeholderView.repeatedRowsLayer.instanceTransform =
                    CATransform3DMakeTranslation(0, rows.rowPitch, 0)
                placeholderView.repeatedRowLayer.frame = rowBounds.offsetBy(
                    dx: -coverageBounds.minX,
                    dy: -coverageBounds.minY
                )
                placeholderView.repeatedRowLayer.path = makePhantomPath(
                    frames: rows.firstRowFrames,
                    relativeTo: rowBounds
                )
            }
            if !rows.finalRowFrames.isEmpty {
                placeholderView.finalRowLayer.isHidden = false
                placeholderView.finalRowLayer.frame = placeholderView.bounds
                placeholderView.finalRowLayer.path = makePhantomPath(
                    frames: rows.finalRowFrames,
                    relativeTo: coverageBounds
                )
            }
        case let .solid(solidCoverage):
            placeholderView.solidCoverageLayer.isHidden = false
            placeholderView.solidCoverageLayer.frame = placeholderView.bounds
            placeholderView.solidCoverageLayer.path = makePhantomPath(
                frames: [solidCoverage.frame],
                relativeTo: coverageBounds
            )
        }
        guard !excludedFrames.isEmpty else { return }
        placeholderView.exclusionMaskLayer.frame = placeholderView.bounds
        placeholderView.exclusionMaskLayer.path = makePhantomPath(
            frames: excludedFrames,
            relativeTo: coverageBounds,
            including: placeholderView.bounds
        )
        placeholderView.exclusionMaskLayer.fillRule = .evenOdd
        placeholderView.exclusionMaskLayer.fillColor = UIColor.white.cgColor
        placeholderView.layer.mask = placeholderView.exclusionMaskLayer
    }

    private func makePhantomPath<Frames: Sequence>(
        frames: Frames,
        relativeTo bounds: CGRect,
        including backgroundRect: CGRect? = nil
    ) -> CGPath where Frames.Element == CGRect {
        let path = CGMutablePath()
        if let backgroundRect { path.addRect(backgroundRect) }
        for frame in frames {
            path.addRect(frame.offsetBy(
                dx: -bounds.minX,
                dy: -bounds.minY
            ))
        }
        return path
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

    private func sourceCells(
        session: Session,
        intersecting rect: CGRect
    ) -> [SourceCellEntry] {
        let sourceLayout = session.plane?.transitionLayout.fromLayout
            ?? session.sourceLayout
        var itemIndices = existingManagedSourceItemIndices(
            intersecting: rect,
            layout: sourceLayout
        )
        itemIndices.formUnion(session.sourceOverscanCells.keys)
        return itemIndices.sorted().flatMap { itemIndex in
            let indexPath = IndexPath(item: itemIndex, section: 0)
            return sourceCells(session: session, at: itemIndex).compactMap {
                sourceCell -> SourceCellEntry? in
                guard cell(sourceCell, intersects: rect) else { return nil }
                return SourceCellEntry(indexPath: indexPath, cell: sourceCell)
            }
        }
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

    private func enqueueViewportPromotions(session: Session) {
        guard let collectionView, let viewportView else { return }
        let viewportRect = collectionView.convert(
            viewportView.bounds,
            from: viewportView
        )
        let promotionRect = session.viewportPromotionCoverage.replacementRect(
            requiredRect: viewportRect,
            buffer: priorityCoverageBuffer(for: viewportRect)
        )
        if let plane = session.plane,
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
        for representation in sourceRepresentations {
            enqueueMaterialization(
                session: session,
                priority: cell(representation.cell, intersects: viewportRect)
                    ? .visibleRepresentation
                    : .deferred,
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
        invalidateManagedCellPlans(session: session)
        guard let plane = session.plane else {
            return
        }
        let cellID = ObjectIdentifier(cell)
        session.detailedSourceCellItems.removeValue(forKey: cellID)
        if session.lastContentFadeAlpha > 0 {
            session.lockedFallbackRepresentationIDs.insert(cellID)
        }
        refreshDetailedSourceRepresentations(session: session, plane: plane)
        cell.alpha = session.sourceCoverage
            .readyDestinationByRepresentation[cellID] == nil
            ? 1 - session.lastContentFadeAlpha
            : 1
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
        if let plane = session.plane {
            let cellID = ObjectIdentifier(browserCell)
            if session.lastContentFadeAlpha > 0 {
                session.lockedFallbackRepresentationIDs.insert(cellID)
            }
            refreshDetailedSourceRepresentations(session: session, plane: plane)
        } else {
            removeCellFrameCorrection(session: session, for: cell)
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
        browserCell.clearTransitionContent()
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
        } else {
            session.sourcePlanePriorityCoverage.reset()
            session.destinationPlanePriorityCoverage.reset()
            if !session.destinationPlanRefreshIsDirty {
                advanceDestinationPlanGeneration(session: session)
            }
            session.destinationPlanRefreshIsDirty = true
            startMaterializationDisplayLinkIfNeeded()
        }
        invalidateViewportPromotion(session: session)
    }

    private func configureDetailedSourceRepresentation(
        session: Session,
        cell: MobilePlayerCollectionBrowserCell,
        sourceItem: Int,
        plane: GridModePlaneContext
    ) {
        guard session.selectedSourceItems.contains(sourceItem),
              cell.represents(tokenIndex: sourceItem) else {
            return
        }
        let cellID = ObjectIdentifier(cell)
        var changesSourceCoverage = false
        if cell.holdsCarryoverForPendingBaseImage {
            changesSourceCoverage = session.lockedFallbackRepresentationIDs
                .insert(cellID).inserted
        }
        guard !session.lockedFallbackRepresentationIDs.contains(cellID)
        else {
            cell.alpha = 1 - session.lastContentFadeAlpha
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
            cell.clearTransitionContent()
        }
        session.detailedSourceCellItems[cellID] = sourceItem
        guard let destinationItem = destinationItem(
            session: session,
            sourceItem: sourceItem,
            plane: plane
        ) else {
            changesSourceCoverage = session.preparedRepresentationIDs
                .remove(cellID) != nil || changesSourceCoverage
            cell.alpha = 1 - session.lastContentFadeAlpha
            if changesSourceCoverage {
                markSourceCoverageRefreshDirty(session: session)
            }
            return
        }
        let isReady = loadTransitionContent(
            session: session,
            fromItem: sourceItem,
            toItem: destinationItem,
            requiredQuality: plane.toMode.requiredImageQuality,
            into: cell,
            plane: plane
        )
        if isReady {
            changesSourceCoverage = session.preparedRepresentationIDs
                .insert(cellID).inserted || changesSourceCoverage
            registerCellFrameCorrection(
                session: session,
                cell: cell,
                destinationItem: destinationItem,
                plane: plane
            )
        } else {
            changesSourceCoverage = session.preparedRepresentationIDs
                .remove(cellID) != nil || changesSourceCoverage
            cell.alpha = 1 - session.lastContentFadeAlpha
        }
        if changesSourceCoverage {
            markSourceCoverageRefreshDirty(session: session)
        }
    }

    @discardableResult
    private func loadTransitionContent(
        session: Session,
        fromItem: Int,
        toItem: Int,
        requiredQuality: CollectionBrowseImageQuality,
        into cell: MobilePlayerCollectionBrowserCell,
        plane: GridModePlaneContext
    ) -> Bool {
        guard cell.represents(tokenIndex: fromItem) else { return false }
        let cellID = ObjectIdentifier(cell)
        guard !session.lockedFallbackRepresentationIDs.contains(cellID),
              let contentIdentity = contentAccess.contentIdentity(toItem),
              let imageSources = contentAccess.imageSources(toItem) else {
            cancelTransitionImageLoad(session: session, for: cell)
            return false
        }
        let retainedTransitionContentQuality = session
            .preparedRepresentationIDs.contains(cellID)
            && session.detailedSourceCellItems[cellID] == fromItem
            ? cell.incomingTransitionContentQuality(
                representing: contentIdentity,
                from: imageSources
            )
            : nil
        var installedCachedContent = false
        if let cachedImage = imageAccess.cachedImage(
            imageSources,
            .highestAvailable
        ) {
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
                return true
            }
        }
        if let retainedTransitionContentQuality,
           retainedTransitionContentQuality.canReplace(requiredQuality) {
            cancelTransitionImageLoad(session: session, for: cell)
            return true
        }
        let generation = session.transitionContentGeneration
        let sessionID = session.id
        let planeID = plane.id
        let descriptor = imageSources.descriptor(for: requiredQuality)
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
            }
            cancelTransitionImageLoad(session: session, for: cell)
        }
        guard loadEligibility != nil,
              session.lastContentFadeAlpha <= 0 else {
            return installedCachedContent
                || retainedTransitionContentQuality != nil
        }
        let loadID = UUID()
        let cancellation = imageAccess.loadImage(descriptor) {
            [weak self] image in
            DispatchQueue.main.async {
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
        }
        return installedCachedContent
            || retainedTransitionContentQuality != nil
    }

    private func applyContentFade(
        session: Session,
        alpha: CGFloat,
        animated: Bool
    ) {
        guard session.lastContentFadeAlpha != alpha else { return }
        if session.lastContentFadeAlpha <= 0, alpha > 0 {
            if session.sourceCoverageRefreshIsDirty,
               let plane = session.plane {
                refreshDetailedSourceRepresentations(
                    session: session,
                    plane: plane
                )
            }
            session.lockedFallbackRepresentationIDs.formUnion(
                session.sourceCoverage.fallbackRepresentationIDs
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
        }
        session.lastContentFadeAlpha = alpha
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
                if !animated {
                    representation.cell.layer.removeAnimation(
                        forKey: "opacity"
                    )
                }
                let cellID = ObjectIdentifier(representation.cell)
                if session.sourceCoverage.readyDestinationByRepresentation[
                    cellID
                ] != nil {
                    representation.cell.alpha = 1
                    representation.cell.setTransitionContentAlpha(
                        alpha,
                        interruptingAnimation: !animated
                    )
                } else {
                    representation.cell.alpha = 1 - alpha
                }
            }
        }
        if animated {
            UIView.animate(
                withDuration: Self.contentFadeOutDuration,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: apply
            )
        } else {
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
        carryoverRetention: CarryoverRetention = .none
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
            cell.clearTransitionContent(
                preservingCarryover: preservesCarryover
            )
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
            carryoverRetention: carryoverRetention
        )
        collectionView?.transform = .identity
        session.lastRenderedScale = 1
        recycleSourceOverscanCells(session: session, retaining: [])
        session.sourceOverscanCells.removeAll(keepingCapacity: false)
    }

    private func captureVisibleCarryoverSources(
        session: Session,
        anchorTokenIndex: Int?
    ) -> [MobilePlayerBrowserGridCarryoverSource] {
        guard let collectionView, let viewportView else { return [] }
        let readySourceCells = viewportSourceCells(session: session)
            .sorted { lhs, rhs in
                if lhs.indexPath.item == rhs.indexPath.item {
                    return ObjectIdentifier(lhs.cell).hashValue
                        < ObjectIdentifier(rhs.cell).hashValue
                }
                return lhs.indexPath.item < rhs.indexPath.item
            }.filter {
                session.sourceCoverage.readyDestinationByRepresentation[
                    ObjectIdentifier($0.cell)
                ] != nil
            }
        let selectedItems = PlayerBrowserGridCarryoverSelection
            .selectedItemIndices(
                candidateItemIndices: readySourceCells.map {
                    $0.indexPath.item
                },
                anchorItemIndex: anchorTokenIndex
            )
        let sourceCells = readySourceCells.compactMap {
            selectedItems.contains($0.indexPath.item) ? $0.cell : nil
        }
        let phantomCells = session.phantomCells.sorted {
            $0.key < $1.key
        }.compactMap { itemIndex, cell in
            MobilePlayerCollectionBrowserTransitionSupport
                .itemIntersectsViewport(
                    at: IndexPath(item: itemIndex, section: 0),
                    cell: cell,
                    collectionView: collectionView,
                    viewportView: viewportView
                ) ? cell : nil
        }
        let carryoverCells = (sourceCells + phantomCells.prefix(
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )).prefix(
            PlayerBrowserGridRenderBudget.maximumCarryoverSourceCount
        )
        return MobilePlayerCollectionBrowserTransitionSupport.captureSources(
            from: Array(carryoverCells),
            in: viewportView
        )
    }

    private func installCarryoverContent(
        session: Session,
        plane: GridModePlaneContext,
        sources: [MobilePlayerBrowserGridCarryoverSource],
        ineligibleFallbackSourceItems: Set<Int>
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
                resolveContent: { source, itemIndex, cell in
                    source?.content ?? fallbackCarryoverSource(
                        plane: plane,
                        destinationItem: itemIndex,
                        isNeeded: cell.needsCarryoverContent,
                        ineligibleSourceItems: ineligibleFallbackSourceItems
                    )
                }
            )
        hasTransitionPlaceholderTones = hasTransitionPlaceholderTones
            || holdsPlaceholderTone
        session.sourceCoverage = .empty
    }

    private func fallbackCarryoverSource(
        plane: GridModePlaneContext,
        destinationItem: Int,
        isNeeded: Bool,
        ineligibleSourceItems: Set<Int>
    ) -> MobilePlayerBrowserCarryoverContent? {
        guard isNeeded,
              let destinationFrame = visualGeometry(
                  for: plane.transitionLayout.toLayout
              ).itemFrame(at: destinationItem) else {
            return nil
        }
        let sourceGeometry = visualGeometry(
            for: plane.transitionLayout.fromLayout
        )
        guard let sourceItem = sourceGeometry.nearestItemIndex(
            to: plane.latticeMap.sourcePoint(
                fromDestination: CGPoint(
                    x: destinationFrame.midX,
                    y: destinationFrame.midY
                )
            )
        ),
              !ineligibleSourceItems.contains(sourceItem),
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
        return session.sourceCoverageRefreshIsDirty
            || session.destinationPlanRefreshIsDirty
            || session.phantomShapeRefreshIsDirty
    }

    private func handleMaterializationTick(_: CADisplayLink) {
        _ = drainMaterializationWork()
    }

    @discardableResult
    func drainMaterializationWork() -> MaterializationDrainResult {
        let start = clock()
        var processedCount = 0
        var canBatchDirtySource = false
        isDrainingMaterialization = true
        defer { isDrainingMaterialization = false }
        while processedCount < Self.materializationJobLimit,
              clock() - start < Self.materializationTimeLimit {
            guard case let .active(session) = lifecycle else { break }
            let remainingCount = Self.materializationJobLimit - processedCount
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
            if hasDeferredRenderRefresh,
               materializationQueue.isEmpty || remainingCount == 1 {
                flushDeferredRenderRefresh()
                processedCount += 1
                continue
            }
            guard let nextJob = materializationQueue.first else { break }
            if case .source = nextJob.kind,
               remainingCount < Self.minimumSourceBatchCapacity {
                if hasDeferredRenderRefresh {
                    flushDeferredRenderRefresh()
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
        let elapsed = max(clock() - start, 0)
        let stoppedForTimeLimit = (
            !materializationQueue.isEmpty || hasDeferredRenderRefresh
        )
            && elapsed >= Self.materializationTimeLimit
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
                == completion.descriptor,
              let image = completion.image else {
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
                if session.lockedFallbackRepresentationIDs.insert(
                    completion.representationID
                ).inserted {
                    session.removeForegroundEligibility(
                        for: completion.representationID
                    )
                    markSourceCoverageRefreshDirty(session: session)
                }
                return
            }
            cell.installTransitionContent(
                image: image,
                descriptor: completion.descriptor,
                usesNativeMetalCardCornerMask:
                    completion.descriptor.usesNativeMetalCardPresentation,
                targetAlpha: session.lastContentFadeAlpha,
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
        let changesSourceCoverage = session.preparedRepresentationIDs.insert(
            completion.representationID
        ).inserted
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

    private func flushDeferredRenderRefresh() {
        guard case let .active(session) = lifecycle else { return }
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
            return
        }
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
        enqueueViewportPromotions(session: session)
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
