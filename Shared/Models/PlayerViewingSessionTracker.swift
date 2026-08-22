// ∅ 2026 lil org

import Foundation

@MainActor
enum PlayerPersistenceUpdates {
    private struct PendingUpdate {
        let id: UUID
        let task: Task<Void, Never>
    }

    private static var pendingUpdate: PendingUpdate?

    static var hasPendingUpdates: Bool {
        pendingUpdate != nil
    }

    static func enqueue(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        let previousTask = pendingUpdate?.task
        let updateID = UUID()
        let task = Task { @MainActor in
            await previousTask?.value
            await operation()
            guard pendingUpdate?.id == updateID else { return }
            pendingUpdate = nil
        }
        pendingUpdate = PendingUpdate(id: updateID, task: task)
    }

    static func flush() async {
        while let update = pendingUpdate {
            await update.task.value
            if pendingUpdate?.id == update.id {
                pendingUpdate = nil
            }
        }
    }
}

@MainActor
final class PlayerPresentationRequestGate {

    typealias PresentationOperation = @MainActor () -> Void
    private typealias PersistenceOperation = @MainActor @Sendable () async -> Void

    private struct Suspension: Equatable {
        let id: UUID
        let request: Request
    }

    private struct DeferredCommit {
        let request: Request
        let present: PresentationOperation
        let persist: PersistenceOperation
    }

    struct Request: Equatable, Sendable {
        fileprivate let id: UUID
    }

    private var pendingRequest: Request?
    private var suspension: Suspension?
    private var deferredCommit: DeferredCommit?
    private var commitDepth = 0
    private var committedPersistenceOperations = [PersistenceOperation]()

    func begin() -> Request {
        let request = Request(id: UUID())
        pendingRequest = request
        deferredCommit = nil
        return request
    }

    func isPending(_ request: Request) -> Bool {
        pendingRequest == request
    }

    func cancel() {
        pendingRequest = nil
        suspension = nil
        deferredCommit = nil
    }

    func resolutionForPendingRequest() -> (@MainActor (Bool) -> Void)? {
        guard let request = pendingRequest else { return nil }
        let suspension = Suspension(id: UUID(), request: request)
        self.suspension = suspension
        return { [weak self] didComplete in
            self?.resolve(suspension, didComplete: didComplete)
        }
    }

    @discardableResult
    func commit(
        _ request: Request,
        present: @escaping PresentationOperation,
        persist: @escaping @MainActor @Sendable () async -> Void
    ) -> Bool {
        guard isPending(request) else { return false }
        if suspension?.request == request {
            guard deferredCommit?.request != request else { return false }
            deferredCommit = DeferredCommit(
                request: request,
                present: present,
                persist: persist
            )
            return true
        }
        return performCommit(request, present: present, persist: persist)
    }

    private func resolve(_ suspension: Suspension, didComplete: Bool) {
        guard self.suspension == suspension else { return }
        self.suspension = nil
        guard pendingRequest == suspension.request else {
            if deferredCommit?.request == suspension.request {
                deferredCommit = nil
            }
            return
        }
        if didComplete {
            pendingRequest = nil
            deferredCommit = nil
            return
        }
        guard let deferredCommit,
              deferredCommit.request == suspension.request else {
            return
        }
        self.deferredCommit = nil
        _ = performCommit(
            deferredCommit.request,
            present: deferredCommit.present,
            persist: deferredCommit.persist
        )
    }

    private func performCommit(
        _ request: Request,
        present: PresentationOperation,
        persist: @escaping PersistenceOperation
    ) -> Bool {
        guard isPending(request) else { return false }
        pendingRequest = nil
        commitDepth += 1
        committedPersistenceOperations.append(persist)
        present()
        commitDepth -= 1
        if commitDepth == 0 {
            let persistenceOperations = committedPersistenceOperations
            committedPersistenceOperations.removeAll(keepingCapacity: true)
            persistenceOperations.forEach(PlayerPersistenceUpdates.enqueue)
        }
        return true
    }
}

actor PlayerViewingSessionTracker {

    private struct RestartSuppression {
        let generation: UInt
        let collectionId: String
        var update: PlayerContinueViewingUpdate? = nil
        var shouldClearWhenPrepared = false
        var didMoveWhilePreparing = false
    }

    private let progressStore: PlayerViewingProgressStore
    private let continueViewingCollectionId: String?
    private var restartSuppression: RestartSuppression?
    private var restartGeneration: UInt = 0
    private var updateGeneration: UInt = 0

    init(
        continueViewingCollectionId: String?,
        progressStore: PlayerViewingProgressStore = .shared
    ) {
        self.continueViewingCollectionId = continueViewingCollectionId
        self.progressStore = progressStore
    }

    func markViewed(_ progress: PlayerViewingProgress) async {
        updateGeneration &+= 1
        let generation = updateGeneration
        await progressStore.save(progress)
        guard generation == updateGeneration else { return }
        await updateContinueViewingCollection(for: progress)
    }

    func beginRestart(collectionId: String?) async {
        updateGeneration &+= 1
        guard let collectionId, !collectionId.isEmpty else {
            restartSuppression = nil
            return
        }

        restartGeneration &+= 1
        let generation = restartGeneration
        restartSuppression = RestartSuppression(
            generation: generation,
            collectionId: collectionId
        )
        guard let update = await progressStore.prepareContinueViewingUpdate(
            collectionId: collectionId,
            isRemoved: true
        ) else { return }
        guard restartSuppression?.generation == generation else {
            return
        }
        let committedUpdate = await progressStore.rebasedRestartContinueViewingUpdate(update)
        guard var restartSuppression,
              restartSuppression.generation == generation else {
            return
        }
        guard !restartSuppression.didMoveWhilePreparing else {
            self.restartSuppression = nil
            return
        }
        restartSuppression.update = committedUpdate
        self.restartSuppression = restartSuppression.shouldClearWhenPrepared
            ? nil
            : restartSuppression
        await progressStore.applyContinueViewingUpdate(committedUpdate)
    }

    func prepareRestartUpdate(collectionId: String?) async -> PlayerContinueViewingUpdate? {
        guard let collectionId, !collectionId.isEmpty else { return nil }
        return await progressStore.prepareContinueViewingUpdate(
            collectionId: collectionId,
            isRemoved: true
        )
    }

    func beginRestart(update: PlayerContinueViewingUpdate?) async {
        updateGeneration &+= 1
        guard let update else {
            restartSuppression = nil
            return
        }

        restartGeneration &+= 1
        let generation = restartGeneration
        restartSuppression = RestartSuppression(
            generation: generation,
            collectionId: update.collectionId,
            update: update
        )
        let committedUpdate = await progressStore.rebasedRestartContinueViewingUpdate(update)
        guard var restartSuppression,
              restartSuppression.generation == generation else {
            return
        }
        restartSuppression.update = committedUpdate
        self.restartSuppression = restartSuppression
        await progressStore.applyContinueViewingUpdate(committedUpdate)
    }

    private func updateContinueViewingCollection(for progress: PlayerViewingProgress) async {
        var restartUpdatedAt: Date?
        if let restartSuppression {
            guard progress.collectionId == restartSuppression.collectionId else {
                if let update = restartSuppression.update {
                    self.restartSuppression = nil
                    let committedUpdate = await progressStore
                        .rebasedRestartContinueViewingUpdate(update)
                    await progressStore.applyContinueViewingUpdate(committedUpdate)
                } else {
                    self.restartSuppression?.shouldClearWhenPrepared = true
                }
                return
            }

            guard progress.tokenIndex > 0 else {
                if let update = restartSuppression.update {
                    let committedUpdate = await progressStore
                        .rebasedRestartContinueViewingUpdate(update)
                    guard self.restartSuppression?.generation == restartSuppression.generation else {
                        return
                    }
                    self.restartSuppression?.update = committedUpdate
                    await progressStore.applyContinueViewingUpdate(committedUpdate)
                }
                return
            }

            if let update = restartSuppression.update {
                let committedUpdate = await progressStore
                    .rebasedRestartContinueViewingUpdate(update)
                guard self.restartSuppression?.generation == restartSuppression.generation else {
                    return
                }
                restartUpdatedAt = committedUpdate.updatedAt
                self.restartSuppression = nil
            } else {
                self.restartSuppression?.shouldClearWhenPrepared = true
                self.restartSuppression?.didMoveWhilePreparing = true
            }
        }

        await progressStore.updateContinueViewingCollection(
            for: progress,
            expectedCollectionId: continueViewingCollectionId,
            after: restartUpdatedAt
        )
    }

}
