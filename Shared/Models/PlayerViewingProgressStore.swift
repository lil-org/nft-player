// ∅ 2026 lil org

import Foundation

extension Notification.Name {
    static let playerViewingProgressDidChange = Notification.Name("PlayerViewingProgressDidChange")
}

struct PlayerContinueViewingEntry: Codable, Hashable {
    let collectionId: String
    let updatedAt: Date
    let isRemoved: Bool

    init(collectionId: String, updatedAt: Date, isRemoved: Bool = false) {
        self.collectionId = collectionId
        self.updatedAt = updatedAt
        self.isRemoved = isRemoved
    }

    enum CodingKeys: String, CodingKey {
        case collectionId
        case updatedAt
        case isRemoved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collectionId = try container.decode(String.self, forKey: .collectionId)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isRemoved = try container.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
    }
}

struct PlayerContinueViewingState: Codable, Hashable {
    let entries: [PlayerContinueViewingEntry]
    let updatedAt: Date

    init(entries: [PlayerContinueViewingEntry], updatedAt: Date? = nil) {
        self.entries = entries
        self.updatedAt = updatedAt ?? Self.fallbackUpdatedAt(for: entries)
    }

    enum CodingKeys: String, CodingKey {
        case entries
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([PlayerContinueViewingEntry].self, forKey: .entries)
        let decodedUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedAt = decodedUpdatedAt ?? Self.fallbackUpdatedAt(for: entries)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func fallbackUpdatedAt(for entries: [PlayerContinueViewingEntry]) -> Date {
        entries.first { !$0.isRemoved }?.updatedAt
            ?? entries.first?.updatedAt
            ?? .distantPast
    }
}

struct PlayerViewingProgress: Codable, Hashable {
    let collectionId: String
    let collectionName: String
    let tokenId: String
    let tokenIndex: Int
    let tokenCount: Int
    let updatedAt: Date
    var hasViewedToEnd: Bool

    init(
        collectionId: String,
        collectionName: String,
        tokenId: String,
        tokenIndex: Int,
        tokenCount: Int,
        updatedAt: Date,
        hasViewedToEnd: Bool = false
    ) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.tokenId = tokenId
        self.tokenIndex = tokenIndex
        self.tokenCount = tokenCount
        self.updatedAt = updatedAt
        self.hasViewedToEnd = hasViewedToEnd
    }

    enum CodingKeys: String, CodingKey {
        case collectionId
        case collectionName
        case tokenId
        case tokenIndex
        case tokenCount
        case updatedAt
        case hasViewedToEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collectionId = try container.decode(String.self, forKey: .collectionId)
        collectionName = try container.decode(String.self, forKey: .collectionName)
        tokenId = try container.decode(String.self, forKey: .tokenId)
        tokenIndex = try container.decode(Int.self, forKey: .tokenIndex)
        tokenCount = try container.decode(Int.self, forKey: .tokenCount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        hasViewedToEnd = try container.decodeIfPresent(Bool.self, forKey: .hasViewedToEnd) ?? false
    }

    var fraction: Double {
        guard tokenCount > 0 else { return 0 }
        return min(max(Double(tokenIndex + 1) / Double(tokenCount), 0), 1)
    }

    var percent: Int {
        guard fraction > 0 else { return 0 }
        guard !isComplete else { return 100 }
        return min(max(Int((fraction * 100).rounded(.up)), 1), 99)
    }

    var isComplete: Bool {
        tokenCount > 0 && tokenIndex >= tokenCount - 1
    }

    var hasBeenViewedToEnd: Bool {
        hasViewedToEnd || isComplete
    }

    var pageLabel: String {
        guard tokenCount > 0 else { return "" }
        return Strings.pagePosition(current: tokenIndex + 1, total: tokenCount)
    }

}

struct PlayerViewingProgressSnapshot: Hashable {
    let percentagesByCollectionId: [String: Int]
    let viewedToEndCollectionIds: Set<String>
    let recentContinueViewingProgresses: [PlayerViewingProgress]

    func firstVisibleContinueViewingProgress(
        isVisibleCollection: (String) -> Bool
    ) -> PlayerViewingProgress? {
        recentContinueViewingProgresses.first { progress in
            isVisibleCollection(progress.collectionId)
        }
    }
}

enum PlayerViewingProgressStore {
    private typealias ProgressByCollectionId = [String: PlayerViewingProgress]

    private static let progressSyncDomain = PlayerSyncDomain.viewingProgress
    private static let continueViewingSyncDomain = PlayerSyncDomain.continueViewingState
    private static let maximumActiveContinueViewingEntryCount = 20
    private static let maximumRemovedContinueViewingEntryCount = 20
    private static let userDefaults = UserDefaults.standard
    private static var cachedProgressByCollectionId: ProgressByCollectionId?
    private static var cachedProgressData: Data?

    static func save(_ progress: PlayerViewingProgress) {
        var allProgress = allProgressByCollectionId()
        var updatedProgress = progress
        updatedProgress.hasViewedToEnd = progress.hasBeenViewedToEnd || allProgress[progress.collectionId]?.hasBeenViewedToEnd == true
        allProgress[progress.collectionId] = updatedProgress
        save(allProgress)
    }

    static var syncedProgressData: Data? {
        let progress = allProgressByCollectionId()
        guard !progress.isEmpty else { return nil }
        return cachedProgressData ?? encodeProgress(progress)
    }

    static var syncedContinueViewingStateData: Data? {
        guard let state = continueViewingState() else {
            return nil
        }
        return encodeContinueViewingState(normalizedContinueViewingState(state))
    }

    static func progressSnapshot() -> PlayerViewingProgressSnapshot {
        let progressByCollectionId = allProgressByCollectionId()
        let viewedToEndCollectionIds = Set(progressByCollectionId.compactMap { collectionId, progress in
            progress.hasBeenViewedToEnd ? collectionId : nil
        })
        let recentContinueViewingProgresses = recentContinueViewingProgresses(in: progressByCollectionId)
        return PlayerViewingProgressSnapshot(
            percentagesByCollectionId: progressByCollectionId.mapValues(\.percent),
            viewedToEndCollectionIds: viewedToEndCollectionIds,
            recentContinueViewingProgresses: recentContinueViewingProgresses
        )
    }

    static func progress(collectionId: String) -> PlayerViewingProgress? {
        allProgressByCollectionId()[collectionId]
    }

    static func setContinueViewingCollectionId(_ collectionId: String) {
        let state = continueViewingState() ?? PlayerContinueViewingState(entries: [])
        saveContinueViewingState(
            stateByRecordingContinueViewingCollectionId(collectionId, in: state)
        )
    }

    static func removeContinueViewingCollectionId(_ collectionId: String?) {
        guard let collectionId,
              !collectionId.isEmpty else {
            return
        }

        let state = normalizedContinueViewingState(
            continueViewingState() ?? PlayerContinueViewingState(entries: [])
        )
        if state.entries.first(where: { $0.collectionId == collectionId })?.isRemoved == true {
            return
        }

        saveContinueViewingState(
            stateByRecordingContinueViewingCollectionId(collectionId, in: state, isRemoved: true)
        )
    }

    static func updateContinueViewingCollection(
        for progress: PlayerViewingProgress,
        expectedCollectionId: String?
    ) {
        guard let expectedCollectionId,
              progress.collectionId == expectedCollectionId else {
            removeContinueViewingCollectionId(expectedCollectionId ?? progress.collectionId)
            return
        }

        let savedProgress = allProgressByCollectionId()[progress.collectionId] ?? progress
        guard !savedProgress.hasBeenViewedToEnd else {
            removeContinueViewingCollectionId(progress.collectionId)
            return
        }

        setContinueViewingCollectionId(progress.collectionId)
    }

    static func mergeSyncedProgressData(_ data: Data?) -> PlayerSyncMergeResult {
        guard let remoteProgress = decodeProgress(from: data) else { return .ignored }

        let localProgress = allProgressByCollectionId()
        let mergedProgress = mergeProgress(localProgress, with: remoteProgress)
        guard mergedProgress != localProgress else {
            return remoteProgress == localProgress ? .ignored : .remoteWasStale
        }

        save(mergedProgress, mirrorToICloud: false)
        return .localChanged
    }

    static func mergeSyncedContinueViewingStateData(_ data: Data?) -> PlayerSyncMergeResult {
        let remoteState = decodeContinueViewingState(from: data)
        let localState = continueViewingState()

        guard let mergedState = mergedContinueViewingState(
            localState: localState,
            remoteState: remoteState
        ) else { return .ignored }

        guard mergedState != localState else {
            return remoteState == localState ? .ignored : .remoteWasStale
        }

        saveContinueViewingState(mergedState, mirrorToICloud: false)
        return .localChanged
    }

#if SWIFT_PACKAGE
    static func resetForTesting() {
        cachedProgressByCollectionId = [:]
        cachedProgressData = nil
        userDefaults.removeObject(forKey: progressSyncDomain.key)
        userDefaults.removeObject(forKey: continueViewingSyncDomain.key)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }
#endif

    private static func recentContinueViewingProgresses(in progressByCollectionId: ProgressByCollectionId) -> [PlayerViewingProgress] {
        guard let state = continueViewingState() else { return [] }
        let normalizedState = normalizedContinueViewingState(state)
        return normalizedState.entries.compactMap { entry -> PlayerViewingProgress? in
            guard !entry.isRemoved,
                  let progress = progressByCollectionId[entry.collectionId],
                  !progress.hasBeenViewedToEnd else {
                return nil
            }
            return progress
        }
    }

    private static func allProgressByCollectionId() -> ProgressByCollectionId {
        let storedData = userDefaults.data(forKey: progressSyncDomain.key)
        if let cachedProgressByCollectionId, cachedProgressData == storedData {
            return cachedProgressByCollectionId
        }

        if let progress = decodeProgress(from: storedData) {
            cachedProgressByCollectionId = progress
            cachedProgressData = storedData
            return progress
        }

        cachedProgressByCollectionId = [:]
        cachedProgressData = storedData
        return [:]
    }

    private static func decodeProgress(from data: Data?) -> ProgressByCollectionId? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ProgressByCollectionId.self, from: data)
    }

    private static func encodeProgress(_ progress: ProgressByCollectionId) -> Data? {
        try? JSONEncoder().encode(progress)
    }

    private static func save(_ progress: ProgressByCollectionId, mirrorToICloud: Bool = true) {
        guard let data = encodeProgress(progress) else { return }
        cachedProgressByCollectionId = progress
        cachedProgressData = data
        userDefaults.set(data, forKey: progressSyncDomain.key)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        if mirrorToICloud {
            PlayerICloudSync.shared.playerProgressDidChange()
        }
#endif
    }

    private static func continueViewingState() -> PlayerContinueViewingState? {
        decodeContinueViewingState(
            from: userDefaults.data(forKey: continueViewingSyncDomain.key)
        )
    }

    private static func saveContinueViewingState(
        _ state: PlayerContinueViewingState,
        mirrorToICloud: Bool = true
    ) {
        let normalizedState = normalizedContinueViewingState(state)
        guard let data = encodeContinueViewingState(normalizedState) else { return }

        userDefaults.set(data, forKey: continueViewingSyncDomain.key)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        if mirrorToICloud {
            PlayerICloudSync.shared.playerContinueViewingStateDidChange()
        }
#endif
    }

    private static func stateByRecordingContinueViewingCollectionId(
        _ collectionId: String,
        in state: PlayerContinueViewingState,
        updatedAt: Date = Date(),
        isRemoved: Bool = false
    ) -> PlayerContinueViewingState {
        guard !collectionId.isEmpty else { return state }

        let entry = PlayerContinueViewingEntry(
            collectionId: collectionId,
            updatedAt: updatedAt,
            isRemoved: isRemoved
        )
        return PlayerContinueViewingState(
            entries: [entry] + state.entries.filter { $0.collectionId != collectionId }
        )
    }

    private static func normalizedContinueViewingState(_ state: PlayerContinueViewingState) -> PlayerContinueViewingState {
        var latestEntryByCollectionId = [String: (entry: PlayerContinueViewingEntry, order: Int)]()
        for (order, entry) in state.entries.enumerated() {
            guard !entry.collectionId.isEmpty else { continue }
            guard let existing = latestEntryByCollectionId[entry.collectionId] else {
                latestEntryByCollectionId[entry.collectionId] = (entry, order)
                continue
            }

            if entry.updatedAt > existing.entry.updatedAt
                || (entry.updatedAt == existing.entry.updatedAt && entry.isRemoved && !existing.entry.isRemoved) {
                latestEntryByCollectionId[entry.collectionId] = (entry, order)
            }
        }

        let sortedEntries = latestEntryByCollectionId.values.sorted {
            if $0.entry.updatedAt != $1.entry.updatedAt {
                return $0.entry.updatedAt > $1.entry.updatedAt
            }
            if $0.entry.isRemoved != $1.entry.isRemoved {
                return $0.entry.isRemoved && !$1.entry.isRemoved
            }
            return $0.order < $1.order
        }
        .map { $0.entry }

        if sortedEntries.isEmpty {
            return PlayerContinueViewingState(entries: [], updatedAt: state.updatedAt)
        }

        var activeEntryCount = 0
        var removedEntryCount = 0
        var cappedEntries = [PlayerContinueViewingEntry]()
        for entry in sortedEntries {
            if entry.isRemoved {
                guard removedEntryCount < maximumRemovedContinueViewingEntryCount else {
                    continue
                }
                removedEntryCount += 1
            } else {
                guard activeEntryCount < maximumActiveContinueViewingEntryCount else {
                    continue
                }
                activeEntryCount += 1
            }
            cappedEntries.append(entry)
        }

        return PlayerContinueViewingState(
            entries: cappedEntries
        )
    }

    private static func encodeContinueViewingState(_ state: PlayerContinueViewingState) -> Data? {
        try? JSONEncoder().encode(state)
    }

    private static func decodeContinueViewingState(from data: Data?) -> PlayerContinueViewingState? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
    }

    private static func mergeProgress(
        _ localProgress: ProgressByCollectionId,
        with remoteProgress: ProgressByCollectionId
    ) -> ProgressByCollectionId {
        remoteProgress.reduce(into: localProgress) { result, entry in
            guard let localEntry = result[entry.key] else {
                result[entry.key] = entry.value
                return
            }

            var mergedEntry = latestProgressEntry(localEntry, entry.value)
            let hasViewedToEnd = localEntry.hasBeenViewedToEnd || entry.value.hasBeenViewedToEnd
            mergedEntry.hasViewedToEnd = hasViewedToEnd
            result[entry.key] = mergedEntry
        }
    }

    private static func latestProgressEntry(
        _ localEntry: PlayerViewingProgress,
        _ remoteEntry: PlayerViewingProgress
    ) -> PlayerViewingProgress {
        if localEntry.updatedAt != remoteEntry.updatedAt {
            return localEntry.updatedAt > remoteEntry.updatedAt ? localEntry : remoteEntry
        }

        if localEntry.fraction != remoteEntry.fraction {
            return localEntry.fraction > remoteEntry.fraction ? localEntry : remoteEntry
        }

        if localEntry.tokenIndex != remoteEntry.tokenIndex {
            return localEntry.tokenIndex > remoteEntry.tokenIndex ? localEntry : remoteEntry
        }

        return localEntry
    }

    private static func mergedContinueViewingState(
        localState: PlayerContinueViewingState?,
        remoteState: PlayerContinueViewingState?
    ) -> PlayerContinueViewingState? {
        let localEntries = localState?.entries ?? []
        let remoteEntries = remoteState?.entries ?? []
        let localClearUpdatedAt = clearUpdatedAt(for: localState)
        let remoteClearUpdatedAt = clearUpdatedAt(for: remoteState)
        let filteredRemoteEntries: [PlayerContinueViewingEntry]
        if let localClearUpdatedAt {
            filteredRemoteEntries = remoteEntries.filter { $0.updatedAt > localClearUpdatedAt }
        } else {
            filteredRemoteEntries = remoteEntries
        }

        let entries = localEntries + filteredRemoteEntries
        guard !entries.isEmpty else {
            if localState == nil, remoteState == nil {
                return continueViewingStateFromProgress(allProgressByCollectionId())
            }

            if let remoteClearUpdatedAt {
                guard let localClearUpdatedAt else {
                    return remoteState
                }
                return remoteClearUpdatedAt > localClearUpdatedAt ? remoteState : localState
            }

            if let localState,
               localClearUpdatedAt != nil,
               !remoteEntries.isEmpty {
                return normalizedContinueViewingState(localState)
            }

            return nil
        }

        return normalizedContinueViewingState(PlayerContinueViewingState(entries: entries))
    }

    private static func clearUpdatedAt(for state: PlayerContinueViewingState?) -> Date? {
        guard let state,
              state.entries.isEmpty else {
            return nil
        }
        return state.updatedAt
    }

    private static func continueViewingStateFromProgress(
        _ progressByCollectionId: ProgressByCollectionId
    ) -> PlayerContinueViewingState? {
        let entries = progressByCollectionId.values
            .filter { !$0.hasBeenViewedToEnd }
            .map { progress in
                PlayerContinueViewingEntry(
                    collectionId: progress.collectionId,
                    updatedAt: progress.updatedAt
                )
            }

        let state = normalizedContinueViewingState(PlayerContinueViewingState(entries: entries))
        guard state.entries.contains(where: { !$0.isRemoved }) else {
            return nil
        }
        return state
    }
}

typealias MobileViewingProgress = PlayerViewingProgress
typealias MobileViewingProgressStore = PlayerViewingProgressStore
