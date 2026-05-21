// ∅ 2026 lil org

import Foundation

enum PlayerSyncMergeResult {
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

    init?(key: String) {
        guard let domain = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = domain
    }

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

    var maximumPayloadBytes: Int? {
        switch self {
        case .bookmarks:
            return 700_000
        case .viewingProgress, .continueViewingState:
            return nil
        }
    }

    var canBeDroppedForTotalQuota: Bool {
        self == .bookmarks
    }

    var removesCloudValueWhenPayloadIsNil: Bool {
        false
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
