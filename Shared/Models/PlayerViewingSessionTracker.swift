// ∅ 2026 lil org

import Foundation

struct PlayerViewingSessionTracker {

    private let continueViewingCollectionId: String?
    private var restartSuppressedCollectionId: String?

    init(continueViewingCollectionId: String?) {
        self.continueViewingCollectionId = continueViewingCollectionId
    }

    mutating func markViewed(_ progress: PlayerViewingProgress) {
        PlayerViewingProgressStore.save(progress)
        updateContinueViewingCollection(for: progress)
    }

    mutating func beginRestart(collectionId: String?) {
        guard let collectionId, !collectionId.isEmpty else {
            restartSuppressedCollectionId = nil
            return
        }

        restartSuppressedCollectionId = collectionId
        PlayerViewingProgressStore.removeContinueViewingCollectionId(collectionId)
    }

    private mutating func updateContinueViewingCollection(for progress: PlayerViewingProgress) {
        if let suppressedCollectionId = restartSuppressedCollectionId {
            guard progress.collectionId == suppressedCollectionId else {
                restartSuppressedCollectionId = nil
                PlayerViewingProgressStore.removeContinueViewingCollectionId(suppressedCollectionId)
                return
            }

            guard progress.tokenIndex > 0 else {
                PlayerViewingProgressStore.removeContinueViewingCollectionId(suppressedCollectionId)
                return
            }

            restartSuppressedCollectionId = nil
        }

        PlayerViewingProgressStore.updateContinueViewingCollection(
            for: progress,
            expectedCollectionId: continueViewingCollectionId
        )
    }

}
