// ∅ 2026 lil org

import Foundation

extension Notification.Name {
    static let playerViewingProgressDidChange = Notification.Name("PlayerViewingProgressDidChange")
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
    private static let progressKey = "playerViewingProgressByCollectionId"
    private static let legacyMobileProgressKey = "mobileViewingProgressByCollectionId"
    private static let continueViewingCollectionIdKey = "playerContinueViewingCollectionId"
    private static let legacyMobileContinueViewingCollectionIdKey = "mobileContinueViewingCollectionId"
    private static let userDefaults = UserDefaults.standard
    private static var cachedProgressByCollectionId: [String: PlayerViewingProgress]?
    private static var cachedProgressData: Data?

    static func save(_ progress: PlayerViewingProgress) {
        var allProgress = allProgressByCollectionId()
        var updatedProgress = progress
        updatedProgress.hasViewedToEnd = progress.hasBeenViewedToEnd || allProgress[progress.collectionId]?.hasBeenViewedToEnd == true
        allProgress[progress.collectionId] = updatedProgress
        save(allProgress)
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
        userDefaults.set(collectionId, forKey: continueViewingCollectionIdKey)
        userDefaults.removeObject(forKey: legacyMobileContinueViewingCollectionIdKey)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }

    static func clearContinueViewingCollectionId() {
        userDefaults.removeObject(forKey: continueViewingCollectionIdKey)
        userDefaults.removeObject(forKey: legacyMobileContinueViewingCollectionIdKey)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }

    private static func continueViewingProgress(in progressByCollectionId: [String: PlayerViewingProgress]) -> PlayerViewingProgress? {
        let collectionId = userDefaults.string(forKey: continueViewingCollectionIdKey)
            ?? userDefaults.string(forKey: legacyMobileContinueViewingCollectionIdKey)
        guard let collectionId,
              let progress = progressByCollectionId[collectionId],
              !progress.isComplete else {
            return nil
        }
        return progress
    }

    private static func allProgressByCollectionId() -> [String: PlayerViewingProgress] {
        let storedData = userDefaults.data(forKey: progressKey)
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

    private static func decodeProgress(from data: Data?) -> [String: PlayerViewingProgress]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: PlayerViewingProgress].self, from: data)
    }

    private static func save(_ progress: [String: PlayerViewingProgress]) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        cachedProgressByCollectionId = progress
        cachedProgressData = data
        userDefaults.set(data, forKey: progressKey)
        NotificationCenter.default.post(name: .playerViewingProgressDidChange, object: nil)
    }
}

typealias MobileViewingProgress = PlayerViewingProgress
typealias MobileViewingProgressStore = PlayerViewingProgressStore
