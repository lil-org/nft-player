// ∅ 2026 lil org

import Foundation
import os

nonisolated enum PlayerSyncTimestampPolicy {
    static let maximumFutureSkew: TimeInterval = 24 * 60 * 60
    static let invalidLocalTimestamp = Date.distantPast

#if SWIFT_PACKAGE
    nonisolated private static let currentDateOverride = OSAllocatedUnfairLock<Date?>(
        initialState: nil
    )
#endif

    static var currentDate: Date {
#if SWIFT_PACKAGE
        if let currentDate = currentDateOverride.withLock({ $0 }) {
            return currentDate
        }
#endif
        return Date()
    }

    static func isPlausible(
        _ timestamp: Date,
        relativeTo now: Date
    ) -> Bool {
        timestamp <= now.addingTimeInterval(maximumFutureSkew)
    }

    static func normalizedLocalTimestamp(
        _ timestamp: Date,
        relativeTo now: Date
    ) -> Date {
        isPlausible(timestamp, relativeTo: now)
            ? timestamp
            : invalidLocalTimestamp
    }

    static func logicalClockFloor(
        _ timestamp: Date,
        relativeTo now: Date
    ) -> Date {
        isPlausible(timestamp, relativeTo: now) ? timestamp : now
    }

#if SWIFT_PACKAGE
    static func setCurrentDateForTesting(_ currentDate: Date?) {
        currentDateOverride.withLock { $0 = currentDate }
    }
#endif
}

nonisolated enum PlayerSyncLogicalClock {
    private enum Family {
        case viewingActivity
        case bookmarks
    }

    private struct State {
        var viewingActivity = Date.distantPast
        var bookmarks = Date.distantPast

        subscript(family: Family) -> Date {
            get {
                switch family {
                case .viewingActivity: viewingActivity
                case .bookmarks: bookmarks
                }
            }
            set {
                switch family {
                case .viewingActivity: viewingActivity = newValue
                case .bookmarks: bookmarks = newValue
                }
            }
        }
    }

    nonisolated private static let highWaterMarks = OSAllocatedUnfairLock(
        initialState: State()
    )

    static func observe(_ timestamp: Date, for domain: PlayerSyncDomain) {
        let now = PlayerSyncTimestampPolicy.currentDate
        let observedTimestamp = PlayerSyncTimestampPolicy.logicalClockFloor(
            timestamp,
            relativeTo: now
        )
        let family = family(for: domain)
        highWaterMarks.withLock { highWaterMarks in
            highWaterMarks[family] = max(
                PlayerSyncTimestampPolicy.logicalClockFloor(
                    highWaterMarks[family],
                    relativeTo: now
                ),
                observedTimestamp
            )
        }
    }

    static func next(for domain: PlayerSyncDomain, after timestamp: Date? = nil) -> Date {
        let now = PlayerSyncTimestampPolicy.currentDate
        let family = family(for: domain)
        return highWaterMarks.withLock { highWaterMarks in
            let floor = max(
                PlayerSyncTimestampPolicy.logicalClockFloor(
                    highWaterMarks[family],
                    relativeTo: now
                ),
                timestamp.map {
                    PlayerSyncTimestampPolicy.logicalClockFloor(
                        $0,
                        relativeTo: now
                    )
                } ?? .distantPast
            )
            let nextTimestamp = now > floor
                ? now
                : Date(
                    timeIntervalSinceReferenceDate: floor
                        .timeIntervalSinceReferenceDate
                        .nextUp
                )
            highWaterMarks[family] = nextTimestamp
            return nextTimestamp
        }
    }

#if SWIFT_PACKAGE
    static func resetForTesting() {
        highWaterMarks.withLock { $0 = State() }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil)
    }
#endif

    private static func family(for domain: PlayerSyncDomain) -> Family {
        switch domain {
        case .viewingProgress, .continueViewingState:
            return .viewingActivity
        case .bookmarks:
            return .bookmarks
        }
    }
}

nonisolated enum PlayerSyncMergeResult: Equatable, Sendable {
    case ignored
    case localChanged
    case remoteWasStale
    case remoteWasUntrusted
    case remoteWasPartiallyUntrusted

    var shouldMirrorLocalValue: Bool {
        switch self {
        case .localChanged, .remoteWasStale, .remoteWasPartiallyUntrusted:
            true
        case .ignored, .remoteWasUntrusted:
            false
        }
    }

    var blocksConflictingUpload: Bool {
        self == .remoteWasUntrusted
    }
}

nonisolated enum PlayerSyncDomain: CaseIterable, Hashable, Sendable {
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
