// ∅ 2026 lil org

import Foundation

enum PlayerSyncMergeResult: Equatable {
    case ignored
    case localChanged
    case remoteWasStale

    var shouldMirrorLocalValue: Bool {
        self != .ignored
    }
}

enum PlayerSyncDomain: CaseIterable, Hashable {
    case viewingProgress
    case continueViewingState
    case bookmarks

    var key: String {
        switch self {
        case .viewingProgress:
            return "playerViewingProgressByCollectionId"
        case .continueViewingState:
            return "playerContinueViewingState"
        case .bookmarks:
            return "playerBookmarksByCollectionId"
        }
    }

    var cloudKitRecordName: String {
        switch self {
        case .viewingProgress:
            return "player-viewing-progress"
        case .continueViewingState:
            return "player-continue-viewing-state"
        case .bookmarks:
            return "player-bookmarks"
        }
    }

    var logLabel: String {
        switch self {
        case .viewingProgress:
            return "viewing progress"
        case .continueViewingState:
            return "continue viewing state"
        case .bookmarks:
            return "bookmark"
        }
    }
}
