// ∅ 2026 lil org

import Foundation

extension GridMaterializer {
    enum MaterializationKind {
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

    enum MaterializationPriority: Int, CaseIterable, Comparable {
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

    struct MaterializationJob {
        let sessionID: UUID
        let priority: MaterializationPriority
        let sequence: UInt
        let kind: MaterializationKind
    }

    struct MaterializationQueue {
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

        func pendingDetailRepresentationKeys()
            -> Set<PendingDetailRepresentationKey> {
            Set(jobsByKey.values.compactMap { job in
                guard case let .detail(
                    _,
                    _,
                    representationID,
                    sourceItem
                ) = job.kind else {
                    return nil
                }
                return PendingDetailRepresentationKey(
                    representationID: representationID,
                    sourceItem: sourceItem
                )
            })
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
}
