// ∅ 2026 lil org

import Foundation

extension Notification.Name {
    static let playerViewingProgressDidChange = Notification.Name("PlayerViewingProgressDidChange")
}

private struct PlayerContinueViewingState: Codable, Hashable {
    let collectionId: String?
    let updatedAt: Date
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

enum PlayerViewingProgressStore {
    private typealias ProgressByCollectionId = [String: PlayerViewingProgress]

    private static let progressSyncDomain = PlayerSyncDomain.viewingProgress
    private static let continueViewingSyncDomain = PlayerSyncDomain.continueViewingState
    private static let legacyMobileProgressKey = "mobileViewingProgressByCollectionId"
    private static let continueViewingCollectionIdKey = "playerContinueViewingCollectionId"
    private static let legacyMobileContinueViewingCollectionIdKey = "mobileContinueViewingCollectionId"
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
        guard let state = continueViewingState() else { return nil }
        return encodeContinueViewingState(state)
    }

    static func progressSnapshot() -> (
        percentagesByCollectionId: [String: Int],
        viewedToEndCollectionIds: Set<String>,
        continueViewingProgress: PlayerViewingProgress?
    ) {
        let progressByCollectionId = allProgressByCollectionId()
        let viewedToEndCollectionIds = Set(progressByCollectionId.compactMap { collectionId, progress in
            progress.hasBeenViewedToEnd ? collectionId : nil
        })
        return (
            progressByCollectionId.mapValues(\.percent),
            viewedToEndCollectionIds,
            continueViewingProgress(in: progressByCollectionId)
        )
    }

    static func progress(collectionId: String) -> PlayerViewingProgress? {
        allProgressByCollectionId()[collectionId]
    }

    static func setContinueViewingCollectionId(_ collectionId: String) {
        saveContinueViewingState(
            PlayerContinueViewingState(collectionId: collectionId, updatedAt: Date())
        )
    }

    static func clearContinueViewingCollectionId() {
        guard continueViewingState()?.collectionId != nil else { return }
        saveClearedContinueViewingState()
    }

    static func recordContinueViewingClearedForSync() {
        saveClearedContinueViewingState()
    }

    static func ensureContinueViewingClearedForSync() {
        if let state = continueViewingState(), state.collectionId == nil {
            return
        }
        saveClearedContinueViewingState()
    }

    static func updateContinueViewingCollection(
        for progress: PlayerViewingProgress,
        expectedCollectionId: String?
    ) {
        guard let expectedCollectionId,
              progress.collectionId == expectedCollectionId else {
            ensureContinueViewingClearedForSync()
            return
        }

        guard !progress.isComplete else {
            ensureContinueViewingClearedForSync()
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
        guard let remoteState = decodeContinueViewingState(from: data) else { return .ignored }

        guard let localState = continueViewingState() else {
            saveContinueViewingState(remoteState, mirrorToICloud: false)
            return .localChanged
        }

        guard remoteState.updatedAt > localState.updatedAt else {
            return remoteState == localState ? .ignored : .remoteWasStale
        }
        saveContinueViewingState(remoteState, mirrorToICloud: false)
        return .localChanged
    }

    static func clearLocalSyncedData() {
        cachedProgressByCollectionId = [:]
        cachedProgressData = nil
        userDefaults.removeObject(forKey: progressSyncDomain.key)
        userDefaults.removeObject(forKey: legacyMobileProgressKey)
        userDefaults.removeObject(forKey: continueViewingSyncDomain.key)
        userDefaults.removeObject(forKey: continueViewingCollectionIdKey)
        userDefaults.removeObject(forKey: legacyMobileContinueViewingCollectionIdKey)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }

    private static func continueViewingProgress(in progressByCollectionId: ProgressByCollectionId) -> PlayerViewingProgress? {
        let collectionId = continueViewingState()?.collectionId
        guard let collectionId,
              let progress = progressByCollectionId[collectionId],
              !progress.isComplete else {
            return nil
        }
        return progress
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

        if let legacyData = userDefaults.data(forKey: legacyMobileProgressKey),
           let progress = decodeProgress(from: legacyData) {
            save(progress)
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
#if os(macOS) || os(iOS)
        if mirrorToICloud {
            PlayerICloudSync.shared.playerProgressDidChange()
        }
#endif
    }

    private static func continueViewingState() -> PlayerContinueViewingState? {
        if let data = userDefaults.data(forKey: continueViewingSyncDomain.key),
           let state = decodeContinueViewingState(from: data) {
            return state
        }

        let legacyCollectionId = userDefaults.string(forKey: continueViewingCollectionIdKey)
            ?? userDefaults.string(forKey: legacyMobileContinueViewingCollectionIdKey)
        guard let legacyCollectionId else { return nil }

        return PlayerContinueViewingState(collectionId: legacyCollectionId, updatedAt: .distantPast)
    }

    private static func saveContinueViewingState(
        _ state: PlayerContinueViewingState,
        mirrorToICloud: Bool = true
    ) {
        guard let data = encodeContinueViewingState(state) else { return }

        userDefaults.set(data, forKey: continueViewingSyncDomain.key)
        if let collectionId = state.collectionId {
            userDefaults.set(collectionId, forKey: continueViewingCollectionIdKey)
        } else {
            userDefaults.removeObject(forKey: continueViewingCollectionIdKey)
        }
        userDefaults.removeObject(forKey: legacyMobileContinueViewingCollectionIdKey)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
#if os(macOS) || os(iOS)
        if mirrorToICloud {
            PlayerICloudSync.shared.playerContinueViewingStateDidChange()
        }
#endif
    }

    private static func saveClearedContinueViewingState() {
        saveContinueViewingState(PlayerContinueViewingState(collectionId: nil, updatedAt: Date()))
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

            var mergedEntry = entry.value.updatedAt > localEntry.updatedAt ? entry.value : localEntry
            let hasViewedToEnd = localEntry.hasBeenViewedToEnd || entry.value.hasBeenViewedToEnd
            mergedEntry.hasViewedToEnd = hasViewedToEnd
            result[entry.key] = mergedEntry
        }
    }
}

typealias MobileViewingProgress = PlayerViewingProgress
typealias MobileViewingProgressStore = PlayerViewingProgressStore
