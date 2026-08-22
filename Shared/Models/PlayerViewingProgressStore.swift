// ∅ 2026 lil org

import Foundation

nonisolated extension Notification.Name {
    static let playerViewingProgressDidChange = Notification.Name("PlayerViewingProgressDidChange")
}

nonisolated struct PlayerContinueViewingEntry: Codable, Hashable, Sendable {
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

nonisolated struct PlayerContinueViewingUpdate: Hashable, Sendable {
    let collectionId: String
    let updatedAt: Date
    let isRemoved: Bool
}

nonisolated struct PlayerContinueViewingState: Codable, Hashable, Sendable {
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

nonisolated struct PlayerViewingProgress: Codable, Hashable, Sendable {
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

nonisolated struct PlayerViewingProgressSnapshot: Hashable, Sendable {
    private let progressByCollectionId: [String: PlayerViewingProgress]
    let percentagesByCollectionId: [String: Int]
    let viewedToEndCollectionIds: Set<String>
    let recentContinueViewingProgresses: [PlayerViewingProgress]

    static let empty = PlayerViewingProgressSnapshot(
        progressByCollectionId: [:],
        percentagesByCollectionId: [:],
        viewedToEndCollectionIds: [],
        recentContinueViewingProgresses: []
    )

    init(
        progressByCollectionId: [String: PlayerViewingProgress],
        percentagesByCollectionId: [String: Int],
        viewedToEndCollectionIds: Set<String>,
        recentContinueViewingProgresses: [PlayerViewingProgress]
    ) {
        self.progressByCollectionId = progressByCollectionId
        self.percentagesByCollectionId = percentagesByCollectionId
        self.viewedToEndCollectionIds = viewedToEndCollectionIds
        self.recentContinueViewingProgresses = recentContinueViewingProgresses
    }

    func progress(collectionId: String) -> PlayerViewingProgress? {
        progressByCollectionId[collectionId]
    }

    func firstVisibleContinueViewingProgress(
        isVisibleCollection: (String) -> Bool
    ) -> PlayerViewingProgress? {
        recentContinueViewingProgresses.first { progress in
            isVisibleCollection(progress.collectionId)
        }
    }
}

actor PlayerViewingProgressStore {
    private typealias ProgressByCollectionId = [String: PlayerViewingProgress]

    static let shared = PlayerViewingProgressStore()

    private static let progressSyncDomain = PlayerSyncDomain.viewingProgress
    private static let continueViewingSyncDomain = PlayerSyncDomain.continueViewingState
    private static let quarantinedProgressKey = "\(progressSyncDomain.key).quarantinedRemote"
    private static let quarantinedContinueViewingEntriesKey =
        "\(continueViewingSyncDomain.key).quarantinedRemoteEntries"
    private static let quarantinedContinueViewingClearKey =
        "\(continueViewingSyncDomain.key).quarantinedRemoteClear"
    private static let maximumActiveContinueViewingEntryCount = 20
    private static let maximumRemovedContinueViewingEntryCount = 20
    private let userDefaults: UserDefaults
    private var cachedProgressByCollectionId: ProgressByCollectionId?
    private var cachedProgressData: Data?
    private var quarantinedRemoteProgress = ProgressByCollectionId()
    private var quarantinedRemoteContinueViewingEntries = [PlayerContinueViewingEntry]()
    private var quarantinedRemoteContinueViewingClear: PlayerContinueViewingState?

    init(userDefaults: sending UserDefaults = .standard) {
        let decoder = JSONDecoder()
        let quarantinedProgress = userDefaults.data(forKey: Self.quarantinedProgressKey)
            .flatMap { try? decoder.decode(ProgressByCollectionId.self, from: $0) }
            ?? [:]
        let quarantinedEntries = userDefaults.data(
            forKey: Self.quarantinedContinueViewingEntriesKey
        )
        .flatMap { try? decoder.decode([PlayerContinueViewingEntry].self, from: $0) }
        ?? []
        let quarantinedClear = userDefaults.data(
            forKey: Self.quarantinedContinueViewingClearKey
        )
        .flatMap { try? decoder.decode(PlayerContinueViewingState.self, from: $0) }
        self.userDefaults = userDefaults
        quarantinedRemoteProgress = quarantinedProgress
        quarantinedRemoteContinueViewingEntries = quarantinedEntries
        quarantinedRemoteContinueViewingClear = quarantinedClear
    }

    @discardableResult
    func save(_ incomingProgress: PlayerViewingProgress) async -> Bool {
        var allProgress = allProgressByCollectionId()
        let existingProgress = allProgress[incomingProgress.collectionId]
        let progress: PlayerViewingProgress
        if PlayerSyncTimestampPolicy.isPlausible(
            incomingProgress.updatedAt,
            relativeTo: PlayerSyncTimestampPolicy.currentDate
        ) {
            progress = incomingProgress
        } else {
            progress = self.progress(
                incomingProgress,
                replacingUpdatedAtWith: PlayerSyncLogicalClock.next(
                    for: .viewingProgress,
                    after: existingProgress?.updatedAt
                )
            )
        }
        var updatedProgress = existingProgress
            .map { latestProgressEntry($0, progress) }
            ?? progress
        updatedProgress.hasViewedToEnd = progress.hasBeenViewedToEnd
            || existingProgress?.hasBeenViewedToEnd == true
        guard updatedProgress != existingProgress else { return false }
        allProgress[incomingProgress.collectionId] = updatedProgress
        await save(allProgress)
        return true
    }

    var syncedProgressData: Data? {
        let progress = allProgressByCollectionId().merging(
            quarantinedRemoteProgress,
            uniquingKeysWith: { _, quarantined in quarantined }
        )
        guard !progress.isEmpty else { return nil }
        return encodeProgress(progress)
    }

    var syncedContinueViewingStateData: Data? {
        let localState = continueViewingState()
        guard localState != nil || !quarantinedRemoteContinueViewingEntries.isEmpty else {
            return nil
        }
        let quarantinedCollectionIds = Set(
            quarantinedRemoteContinueViewingEntries.map(\.collectionId)
        )
        let localEntries = localState?.entries.filter {
            !quarantinedCollectionIds.contains($0.collectionId)
        } ?? []
        return encodeContinueViewingState(
            PlayerContinueViewingState(
                entries: quarantinedRemoteContinueViewingEntries + localEntries,
                updatedAt: localState?.updatedAt
            )
        )
    }

    func progressSnapshot() -> PlayerViewingProgressSnapshot {
        let progressByCollectionId = allProgressByCollectionId()
        let viewedToEndCollectionIds = Set(progressByCollectionId.compactMap { collectionId, progress in
            progress.hasBeenViewedToEnd ? collectionId : nil
        })
        let recentContinueViewingProgresses = recentContinueViewingProgresses(in: progressByCollectionId)
        return PlayerViewingProgressSnapshot(
            progressByCollectionId: progressByCollectionId,
            percentagesByCollectionId: progressByCollectionId.mapValues(\.percent),
            viewedToEndCollectionIds: viewedToEndCollectionIds,
            recentContinueViewingProgresses: recentContinueViewingProgresses
        )
    }

    func progress(collectionId: String) -> PlayerViewingProgress? {
        allProgressByCollectionId()[collectionId]
    }

    func setContinueViewingCollectionId(_ collectionId: String) async {
        guard let update = prepareContinueViewingUpdate(collectionId: collectionId) else { return }
        await applyContinueViewingUpdate(update)
    }

    func removeContinueViewingCollectionId(_ collectionId: String?) async {
        guard let collectionId,
              !collectionId.isEmpty else {
            return
        }

        guard let update = prepareContinueViewingUpdate(
            collectionId: collectionId,
            isRemoved: true
        ) else { return }
        await applyContinueViewingUpdate(update)
    }

    func prepareContinueViewingUpdate(
        collectionId: String,
        isRemoved: Bool = false
    ) -> PlayerContinueViewingUpdate? {
        guard !collectionId.isEmpty else { return nil }
        let state = normalizedContinueViewingState(
            continueViewingState() ?? PlayerContinueViewingState(entries: [])
        )
        return PlayerContinueViewingUpdate(
            collectionId: collectionId,
            updatedAt: PlayerSyncLogicalClock.next(
                for: .continueViewingState,
                after: state.updatedAt
            ),
            isRemoved: isRemoved
        )
    }

    func applyContinueViewingUpdate(_ update: PlayerContinueViewingUpdate) async {
        await recordContinueViewingCollectionId(
            update.collectionId,
            updatedAt: update.updatedAt,
            isRemoved: update.isRemoved
        )
    }

    func rebasedRestartContinueViewingUpdate(
        _ update: PlayerContinueViewingUpdate
    ) -> PlayerContinueViewingUpdate {
        let state = normalizedContinueViewingState(
            continueViewingState() ?? PlayerContinueViewingState(entries: [])
        )
        let existingEntry = state.entries.first {
            $0.collectionId == update.collectionId
        }
        let updatedAt: Date
        if let existingEntry, existingEntry.isRemoved {
            updatedAt = max(existingEntry.updatedAt, update.updatedAt)
        } else if let existingEntry,
                  existingEntry.updatedAt >= update.updatedAt {
            updatedAt = PlayerSyncLogicalClock.next(
                for: .continueViewingState,
                after: existingEntry.updatedAt
            )
        } else if state.entries.isEmpty {
            updatedAt = max(state.updatedAt, update.updatedAt)
        } else {
            updatedAt = update.updatedAt
        }
        return PlayerContinueViewingUpdate(
            collectionId: update.collectionId,
            updatedAt: updatedAt,
            isRemoved: true
        )
    }

    func updateContinueViewingCollection(
        for progress: PlayerViewingProgress,
        expectedCollectionId: String?,
        after continueViewingTimestamp: Date? = nil
    ) async {
        let updatedAt: Date
        if let continueViewingTimestamp,
           continueViewingTimestamp >= progress.updatedAt {
            updatedAt = PlayerSyncLogicalClock.next(
                for: .continueViewingState,
                after: continueViewingTimestamp
            )
        } else {
            updatedAt = progress.updatedAt
        }
        guard let expectedCollectionId,
              progress.collectionId == expectedCollectionId else {
            await recordContinueViewingCollectionId(
                expectedCollectionId ?? progress.collectionId,
                updatedAt: updatedAt,
                isRemoved: true
            )
            return
        }

        let savedProgress = allProgressByCollectionId()[progress.collectionId] ?? progress
        guard !savedProgress.hasBeenViewedToEnd else {
            await recordContinueViewingCollectionId(
                progress.collectionId,
                updatedAt: updatedAt,
                isRemoved: true
            )
            return
        }

        await recordContinueViewingCollectionId(
            progress.collectionId,
            updatedAt: updatedAt
        )
    }

    func mergeSyncedProgressData(_ data: Data?) async -> PlayerSyncMergeResult {
        guard let data else {
            replaceQuarantinedRemoteProgress(with: [:])
            return .ignored
        }
        guard let decodedRemoteProgress = decodeProgress(from: data) else {
            replaceQuarantinedRemoteProgress(with: [:])
            return .ignored
        }
        let localProgress = allProgressByCollectionId()
        let remotePayload = filteredRemoteProgress(
            decodedRemoteProgress,
            relativeTo: PlayerSyncTimestampPolicy.currentDate,
            preserving: Set(localProgress.keys)
        )
        replaceQuarantinedRemoteProgress(with: remotePayload.rejectedProgress)
        observeTimestamps(in: remotePayload.progress)

        let mergedProgress = mergeProgress(localProgress, with: remotePayload.progress)
        let hasQuarantinedLocalProgress = !Set(localProgress.keys).isDisjoint(
            with: remotePayload.rejectedProgress.keys
        )
        if mergedProgress != localProgress {
            await save(mergedProgress, mirrorToICloud: false)
            return hasQuarantinedLocalProgress
                ? .remoteWasPartiallyUntrusted
                : .localChanged
        }
        if hasQuarantinedLocalProgress {
            return .remoteWasPartiallyUntrusted
        }
        return remotePayload.progress == localProgress ? .ignored : .remoteWasStale
    }

    func mergeSyncedContinueViewingStateData(_ data: Data?) async -> PlayerSyncMergeResult {
        let remotePayload: (
            state: PlayerContinueViewingState?,
            rejectedEntries: [PlayerContinueViewingEntry],
            rejectedClear: PlayerContinueViewingState?
        )
        let localState = continueViewingState()
        let fallbackLocalState = localState == nil
            ? continueViewingStateFromProgress(allProgressByCollectionId())
            : nil
        let localReferenceState = localState ?? fallbackLocalState
        let localCollectionIds = Set(
            localReferenceState?.entries.map(\.collectionId) ?? []
        )
        if let data {
            guard let decodedRemoteState = decodeContinueViewingState(from: data) else {
                replaceQuarantinedRemoteContinueViewing(
                    entries: [],
                    clear: nil
                )
                return .ignored
            }
            remotePayload = filteredRemoteContinueViewingState(
                decodedRemoteState,
                relativeTo: PlayerSyncTimestampPolicy.currentDate,
                preserving: localCollectionIds,
                preserveAllEntries: localState?.entries.isEmpty == true,
                preserveClear: localReferenceState != nil
            )
            replaceQuarantinedRemoteContinueViewing(
                entries: remotePayload.rejectedEntries,
                clear: remotePayload.rejectedClear
            )
            if let remoteState = remotePayload.state {
                observeTimestamps(in: remoteState)
            }
        } else {
            replaceQuarantinedRemoteContinueViewing(entries: [], clear: nil)
            remotePayload = (nil, [], nil)
        }
        let rejectedCollectionIds = Set(
            remotePayload.rejectedEntries.map(\.collectionId)
        )

        guard let mergedState = mergedContinueViewingState(
            localState: localState,
            remoteState: remotePayload.state
        ) else {
            let cannotPreserveLocalClear = localState?.entries.isEmpty == true
                && !remotePayload.rejectedEntries.isEmpty
            return (remotePayload.rejectedClear != nil && localState != nil)
                || cannotPreserveLocalClear
                ? .remoteWasUntrusted
                : .ignored
        }
        let mergedCollectionIds = Set(mergedState.entries.map(\.collectionId))
        let hasQuarantinedMergedEntry = !mergedCollectionIds.isDisjoint(
            with: rejectedCollectionIds
        )

        guard mergedState != localState else {
            if remotePayload.rejectedClear != nil
                || (mergedState.entries.isEmpty && !remotePayload.rejectedEntries.isEmpty) {
                return .remoteWasUntrusted
            }
            if hasQuarantinedMergedEntry {
                return .remoteWasPartiallyUntrusted
            }
            return remotePayload.state == localState ? .ignored : .remoteWasStale
        }

        await saveContinueViewingState(mergedState, mirrorToICloud: false)
        if remotePayload.rejectedClear != nil
            || (mergedState.entries.isEmpty && !remotePayload.rejectedEntries.isEmpty) {
            return .remoteWasUntrusted
        }
        return hasQuarantinedMergedEntry
            ? .remoteWasPartiallyUntrusted
            : .localChanged
    }

#if SWIFT_PACKAGE
    func resetForTesting() {
        cachedProgressByCollectionId = [:]
        cachedProgressData = nil
        quarantinedRemoteProgress = [:]
        quarantinedRemoteContinueViewingEntries = []
        quarantinedRemoteContinueViewingClear = nil
        userDefaults.removeObject(forKey: Self.progressSyncDomain.key)
        userDefaults.removeObject(forKey: Self.continueViewingSyncDomain.key)
        userDefaults.removeObject(forKey: Self.quarantinedProgressKey)
        userDefaults.removeObject(forKey: Self.quarantinedContinueViewingEntriesKey)
        userDefaults.removeObject(forKey: Self.quarantinedContinueViewingClearKey)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }
#endif

    private func recentContinueViewingProgresses(in progressByCollectionId: ProgressByCollectionId) -> [PlayerViewingProgress] {
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

    private func allProgressByCollectionId() -> ProgressByCollectionId {
        let storedData = userDefaults.data(forKey: Self.progressSyncDomain.key)
        if let cachedProgressByCollectionId, cachedProgressData == storedData {
            let normalizedProgress = normalizedLocalProgress(
                cachedProgressByCollectionId,
                relativeTo: PlayerSyncTimestampPolicy.currentDate
            )
            guard normalizedProgress != cachedProgressByCollectionId else {
                return cachedProgressByCollectionId
            }
            saveProgressWithoutMirroring(normalizedProgress)
            scheduleProgressSync()
            return normalizedProgress
        }

        if let decodedProgress = decodeProgress(from: storedData) {
            let progress = normalizedLocalProgress(
                decodedProgress,
                relativeTo: PlayerSyncTimestampPolicy.currentDate
            )
            if progress != decodedProgress {
                saveProgressWithoutMirroring(progress)
                scheduleProgressSync()
                return progress
            }
            observeTimestamps(in: progress)
            cachedProgressByCollectionId = progress
            cachedProgressData = storedData
            return progress
        }

        cachedProgressByCollectionId = [:]
        cachedProgressData = storedData
        return [:]
    }

    private func decodeProgress(from data: Data?) -> ProgressByCollectionId? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(
            ProgressByCollectionId.self,
            from: data
        )
    }

    private func normalizedLocalProgress(
        _ progress: ProgressByCollectionId,
        relativeTo now: Date
    ) -> ProgressByCollectionId {
        progress.mapValues { progress in
            let updatedAt = PlayerSyncTimestampPolicy.normalizedLocalTimestamp(
                progress.updatedAt,
                relativeTo: now
            )
            guard updatedAt != progress.updatedAt else { return progress }
            return self.progress(progress, replacingUpdatedAtWith: updatedAt)
        }
    }

    private func progress(
        _ progress: PlayerViewingProgress,
        replacingUpdatedAtWith updatedAt: Date
    ) -> PlayerViewingProgress {
        PlayerViewingProgress(
            collectionId: progress.collectionId,
            collectionName: progress.collectionName,
            tokenId: progress.tokenId,
            tokenIndex: progress.tokenIndex,
            tokenCount: progress.tokenCount,
            updatedAt: updatedAt,
            hasViewedToEnd: progress.hasViewedToEnd
        )
    }

    private func filteredRemoteProgress(
        _ progress: ProgressByCollectionId,
        relativeTo now: Date,
        preserving localCollectionIds: Set<String>
    ) -> (progress: ProgressByCollectionId, rejectedProgress: ProgressByCollectionId) {
        var rejectedProgress = ProgressByCollectionId()
        let filteredProgress = progress.reduce(into: ProgressByCollectionId()) { result, entry in
            let remainsQuarantined = localCollectionIds.contains(entry.key)
                && quarantinedRemoteProgress[entry.key] == entry.value
            guard !remainsQuarantined, PlayerSyncTimestampPolicy.isPlausible(
                entry.value.updatedAt,
                relativeTo: now
            ) else {
                rejectedProgress[entry.key] = entry.value
                return
            }
            result[entry.key] = entry.value
        }
        return (filteredProgress, rejectedProgress)
    }

    private func replaceQuarantinedRemoteProgress(
        with progress: ProgressByCollectionId
    ) {
        quarantinedRemoteProgress = progress
        guard !progress.isEmpty,
              let data = encodeProgress(progress) else {
            userDefaults.removeObject(forKey: Self.quarantinedProgressKey)
            return
        }
        userDefaults.set(data, forKey: Self.quarantinedProgressKey)
    }

    private func encodeProgress(_ progress: ProgressByCollectionId) -> Data? {
        try? JSONEncoder().encode(progress)
    }

    private func save(_ progress: ProgressByCollectionId, mirrorToICloud: Bool = true) async {
        saveProgressWithoutMirroring(progress)
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        if mirrorToICloud {
            await PlayerICloudSync.shared.playerProgressDidChange()
        }
#endif
    }

    private func saveProgressWithoutMirroring(_ progress: ProgressByCollectionId) {
        observeTimestamps(in: progress)
        guard let data = encodeProgress(progress) else { return }
        cachedProgressByCollectionId = progress
        cachedProgressData = data
        userDefaults.set(data, forKey: Self.progressSyncDomain.key)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }

    private func continueViewingState() -> PlayerContinueViewingState? {
        guard let decodedState = decodeContinueViewingState(
            from: userDefaults.data(forKey: Self.continueViewingSyncDomain.key)
        ) else {
            return nil
        }
        let timestampNormalizedState = normalizedLocalContinueViewingState(
            decodedState,
            relativeTo: PlayerSyncTimestampPolicy.currentDate
        )
        let state = normalizedContinueViewingState(timestampNormalizedState)
        if state != decodedState {
            saveContinueViewingStateWithoutMirroring(state)
            scheduleContinueViewingSync()
        } else {
            observeTimestamps(in: state)
        }
        return state
    }

    private func saveContinueViewingState(
        _ state: PlayerContinueViewingState,
        mirrorToICloud: Bool = true
    ) async {
        saveContinueViewingStateWithoutMirroring(state)
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        if mirrorToICloud {
            await PlayerICloudSync.shared.playerContinueViewingStateDidChange()
        }
#endif
    }

    private func saveContinueViewingStateWithoutMirroring(
        _ state: PlayerContinueViewingState
    ) {
        let normalizedState = normalizedContinueViewingState(state)
        observeTimestamps(in: normalizedState)
        guard let data = encodeContinueViewingState(normalizedState) else { return }

        userDefaults.set(data, forKey: Self.continueViewingSyncDomain.key)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }

    private func stateByRecordingContinueViewingCollectionId(
        _ collectionId: String,
        in state: PlayerContinueViewingState,
        updatedAt: Date,
        isRemoved: Bool = false
    ) -> PlayerContinueViewingState {
        guard !collectionId.isEmpty else { return state }

        let normalizedState = normalizedContinueViewingState(state)
        if normalizedState.entries.isEmpty,
           normalizedState.updatedAt >= updatedAt {
            return normalizedState
        }

        let entry = PlayerContinueViewingEntry(
            collectionId: collectionId,
            updatedAt: updatedAt,
            isRemoved: isRemoved
        )
        return normalizedContinueViewingState(
            PlayerContinueViewingState(entries: [entry] + normalizedState.entries)
        )
    }

    private func recordContinueViewingCollectionId(
        _ collectionId: String,
        updatedAt: Date? = nil,
        isRemoved: Bool = false
    ) async {
        guard !collectionId.isEmpty else { return }

        let state = normalizedContinueViewingState(
            continueViewingState() ?? PlayerContinueViewingState(entries: [])
        )

        let eventUpdatedAt: Date
        if let updatedAt,
           PlayerSyncTimestampPolicy.isPlausible(
               updatedAt,
               relativeTo: PlayerSyncTimestampPolicy.currentDate
           ) {
            eventUpdatedAt = updatedAt
        } else {
            eventUpdatedAt = PlayerSyncLogicalClock.next(
                for: .continueViewingState,
                after: state.updatedAt
            )
        }
        let updatedState = stateByRecordingContinueViewingCollectionId(
            collectionId,
            in: state,
            updatedAt: eventUpdatedAt,
            isRemoved: isRemoved
        )
        guard updatedState != state else { return }
        await saveContinueViewingState(updatedState)
    }

    private func normalizedContinueViewingState(_ state: PlayerContinueViewingState) -> PlayerContinueViewingState {
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
                guard removedEntryCount < Self.maximumRemovedContinueViewingEntryCount else {
                    continue
                }
                removedEntryCount += 1
            } else {
                guard activeEntryCount < Self.maximumActiveContinueViewingEntryCount else {
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

    private func encodeContinueViewingState(_ state: PlayerContinueViewingState) -> Data? {
        try? JSONEncoder().encode(state)
    }

    private func decodeContinueViewingState(from data: Data?) -> PlayerContinueViewingState? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
    }

    private func normalizedLocalContinueViewingState(
        _ state: PlayerContinueViewingState,
        relativeTo now: Date
    ) -> PlayerContinueViewingState {
        PlayerContinueViewingState(
            entries: state.entries.map { entry in
                PlayerContinueViewingEntry(
                    collectionId: entry.collectionId,
                    updatedAt: PlayerSyncTimestampPolicy.normalizedLocalTimestamp(
                        entry.updatedAt,
                        relativeTo: now
                    ),
                    isRemoved: entry.isRemoved
                )
            },
            updatedAt: PlayerSyncTimestampPolicy.normalizedLocalTimestamp(
                state.updatedAt,
                relativeTo: now
            )
        )
    }

    private func filteredRemoteContinueViewingState(
        _ state: PlayerContinueViewingState,
        relativeTo now: Date,
        preserving localCollectionIds: Set<String>,
        preserveAllEntries: Bool,
        preserveClear: Bool
    ) -> (
        state: PlayerContinueViewingState?,
        rejectedEntries: [PlayerContinueViewingEntry],
        rejectedClear: PlayerContinueViewingState?
    ) {
        let isRootTimestampPlausible = PlayerSyncTimestampPolicy.isPlausible(
            state.updatedAt,
            relativeTo: now
        )
        guard !state.entries.isEmpty else {
            if preserveClear,
               quarantinedRemoteContinueViewingClear == state {
                return (nil, [], state)
            }
            return isRootTimestampPlausible
                ? (state, [], nil)
                : (nil, [], state)
        }

        let previouslyRejectedEntries = Set(quarantinedRemoteContinueViewingEntries)
        let entries = state.entries.reduce(
            into: (valid: [PlayerContinueViewingEntry](), rejected: [PlayerContinueViewingEntry]())
        ) { result, entry in
            let remainsQuarantined = previouslyRejectedEntries.contains(entry)
                && (preserveAllEntries || localCollectionIds.contains(entry.collectionId))
            if !remainsQuarantined,
               PlayerSyncTimestampPolicy.isPlausible(entry.updatedAt, relativeTo: now) {
                result.valid.append(entry)
            } else {
                result.rejected.append(entry)
            }
        }
        guard !entries.valid.isEmpty else {
            return (nil, entries.rejected, nil)
        }
        return (
            normalizedContinueViewingState(
                PlayerContinueViewingState(entries: entries.valid)
            ),
            entries.rejected,
            nil
        )
    }

    private func replaceQuarantinedRemoteContinueViewing(
        entries: [PlayerContinueViewingEntry],
        clear: PlayerContinueViewingState?
    ) {
        quarantinedRemoteContinueViewingEntries = entries
        quarantinedRemoteContinueViewingClear = clear

        if entries.isEmpty {
            userDefaults.removeObject(
                forKey: Self.quarantinedContinueViewingEntriesKey
            )
        } else if let data = try? JSONEncoder().encode(entries) {
            userDefaults.set(
                data,
                forKey: Self.quarantinedContinueViewingEntriesKey
            )
        }

        if let clear,
           let data = encodeContinueViewingState(clear) {
            userDefaults.set(
                data,
                forKey: Self.quarantinedContinueViewingClearKey
            )
        } else {
            userDefaults.removeObject(
                forKey: Self.quarantinedContinueViewingClearKey
            )
        }
    }

    private func scheduleProgressSync() {
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        Task { @MainActor in
            PlayerICloudSync.shared.playerProgressDidChange()
        }
#endif
    }

    private func scheduleContinueViewingSync() {
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        Task { @MainActor in
            PlayerICloudSync.shared.playerContinueViewingStateDidChange()
        }
#endif
    }

    private func observeTimestamps(in progress: ProgressByCollectionId) {
        if let latestTimestamp = progress.values.lazy.map(\.updatedAt).max() {
            PlayerSyncLogicalClock.observe(latestTimestamp, for: .viewingProgress)
        }
    }

    private func observeTimestamps(in state: PlayerContinueViewingState) {
        let latestTimestamp = state.entries.reduce(state.updatedAt) {
            max($0, $1.updatedAt)
        }
        PlayerSyncLogicalClock.observe(latestTimestamp, for: .continueViewingState)
    }

    private func mergeProgress(
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

    private func latestProgressEntry(
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

    private func mergedContinueViewingState(
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

    private func clearUpdatedAt(for state: PlayerContinueViewingState?) -> Date? {
        guard let state,
              state.entries.isEmpty else {
            return nil
        }
        return state.updatedAt
    }

    private func continueViewingStateFromProgress(
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
