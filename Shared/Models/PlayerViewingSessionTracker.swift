// ∅ 2026 lil org

import Foundation

enum PlayerViewingSessionTrackingMode: Hashable, Codable {
    case updateContinueViewing
    case progressOnly

    var updatesContinueViewing: Bool {
        self == .updateContinueViewing
    }
}

struct PlayerViewingSessionTracker {

    private let continueViewingCollectionId: String?
    private let trackingMode: PlayerViewingSessionTrackingMode
    private var restartSuppressedCollectionId: String?

    init(
        continueViewingCollectionId: String?,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        self.continueViewingCollectionId = continueViewingCollectionId
        self.trackingMode = trackingMode
    }

    mutating func markViewed(_ progress: PlayerViewingProgress) {
        PlayerViewingProgressStore.save(progress)
        guard trackingMode.updatesContinueViewing else { return }

        updateContinueViewingCollection(for: progress)
    }

    mutating func beginRestart(collectionId: String?) {
        guard trackingMode.updatesContinueViewing else { return }

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
