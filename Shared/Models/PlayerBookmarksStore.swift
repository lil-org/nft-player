// ∅ 2026 lil org

import Foundation

extension Notification.Name {
    static let playerBookmarksDidChange = Notification.Name("PlayerBookmarksDidChange")
}

struct PlayerBookmark: Codable, Hashable {
    let bookmarkedAt: Date
    let updatedAt: Date
    let isDeleted: Bool

    init(bookmarkedAt: Date, updatedAt: Date? = nil, isDeleted: Bool = false) {
        self.bookmarkedAt = bookmarkedAt
        self.updatedAt = updatedAt ?? bookmarkedAt
        self.isDeleted = isDeleted
    }

    enum CodingKeys: String, CodingKey {
        case bookmarkedAt
        case updatedAt
        case isDeleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookmarkedAt = try container.decode(Date.self, forKey: .bookmarkedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? bookmarkedAt
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookmarkedAt, forKey: .bookmarkedAt)
        if updatedAt != bookmarkedAt {
            try container.encode(updatedAt, forKey: .updatedAt)
        }
        if isDeleted {
            try container.encode(isDeleted, forKey: .isDeleted)
        }
    }
}

enum PlayerBookmarksStore {
    private typealias BookmarkRecordsByCollectionId = [String: [String: PlayerBookmark]]

    private static let bookmarksSyncDomain = PlayerSyncDomain.bookmarks
    private static let legacyMobileBookmarksKey = "mobileBookmarksByCollectionId"
    private static let userDefaults = UserDefaults.standard
    private static var cachedBookmarkRecordsByCollectionId: BookmarkRecordsByCollectionId?
    private static var cachedBookmarksData: Data?

    private struct LegacyPlayerBookmark: Codable {
        let tokenId: String
        let bookmarkedAt: Date
    }

    static func isBookmarked(collectionId: String, tokenId: String) -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }
        return bookmarkRecordsByCollectionId()[collectionId]?[tokenId]?.isDeleted == false
    }

    static var syncedBookmarksData: Data? {
        let bookmarkRecords = bookmarkRecordsByCollectionId()
        let compactedBookmarkRecords = compactBookmarkRecords(bookmarkRecords)
        guard !compactedBookmarkRecords.isEmpty else { return nil }
        if compactedBookmarkRecords == bookmarkRecords {
            return cachedBookmarksData ?? encodeBookmarkRecords(compactedBookmarkRecords)
        }
        return encodeBookmarkRecords(compactedBookmarkRecords)
    }

    @discardableResult
    static func toggleBookmark(collectionId: String, tokenId: String) -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }

        var bookmarkRecords = bookmarkRecordsByCollectionId()
        var collectionBookmarkRecords = bookmarkRecords[collectionId] ?? [:]
        let now = Date()
        let isBookmarked: Bool

        if let existingBookmark = collectionBookmarkRecords[tokenId],
           !existingBookmark.isDeleted {
            collectionBookmarkRecords[tokenId] = PlayerBookmark(
                bookmarkedAt: existingBookmark.bookmarkedAt,
                updatedAt: now,
                isDeleted: true
            )
            isBookmarked = false
        } else {
            collectionBookmarkRecords[tokenId] = PlayerBookmark(bookmarkedAt: now, updatedAt: now)
            isBookmarked = true
        }

        bookmarkRecords[collectionId] = collectionBookmarkRecords
        save(bookmarkRecords)
        return isBookmarked
    }

    static func mergeSyncedBookmarksData(_ data: Data?) -> PlayerSyncMergeResult {
        guard let remoteBookmarkRecords = decodeBookmarkRecordsPayload(from: data)?.records else {
            return .ignored
        }

        let localBookmarkRecords = bookmarkRecordsByCollectionId()
        let compactedRemoteBookmarkRecords = compactBookmarkRecords(remoteBookmarkRecords)
        let didPruneRemoteBookmarkRecords = compactedRemoteBookmarkRecords != remoteBookmarkRecords
        let mergedBookmarkRecords = mergeBookmarkRecords(
            compactBookmarkRecords(localBookmarkRecords),
            with: compactedRemoteBookmarkRecords
        )
        guard mergedBookmarkRecords != localBookmarkRecords else {
            return compactedRemoteBookmarkRecords == localBookmarkRecords && !didPruneRemoteBookmarkRecords
                ? .ignored
                : .remoteWasStale
        }

        save(mergedBookmarkRecords, mirrorToICloud: false)
        return .localChanged
    }

    private static func bookmarkRecordsByCollectionId() -> BookmarkRecordsByCollectionId {
        let storedData = userDefaults.data(forKey: bookmarksSyncDomain.key)
        if let cachedBookmarkRecordsByCollectionId, cachedBookmarksData == storedData {
            return cachedBookmarkRecordsByCollectionId
        }

        if let decodedPayload = decodeBookmarkRecordsPayload(from: storedData) {
            let compactedRecords = compactBookmarkRecords(decodedPayload.records)
            if decodedPayload.needsMigration || compactedRecords != decodedPayload.records {
                save(compactedRecords)
                return compactedRecords
            }

            cachedBookmarkRecordsByCollectionId = compactedRecords
            cachedBookmarksData = storedData
            return compactedRecords
        }

        if let legacyData = userDefaults.data(forKey: legacyMobileBookmarksKey),
           let decodedPayload = decodeBookmarkRecordsPayload(from: legacyData) {
            let compactedRecords = compactBookmarkRecords(decodedPayload.records)
            save(compactedRecords)
            return compactedRecords
        }

        cachedBookmarkRecordsByCollectionId = [:]
        cachedBookmarksData = storedData
        return [:]
    }

    private static func decodeBookmarkRecordsPayload(
        from data: Data?
    ) -> (records: BookmarkRecordsByCollectionId, needsMigration: Bool)? {
        if let records = decodeBookmarkRecords(from: data) {
            return (records, false)
        }

        if let records = decodeLegacyBookmarkRecords(from: data) {
            return (records, true)
        }

        return nil
    }

    private static func decodeBookmarkRecords(from data: Data?) -> BookmarkRecordsByCollectionId? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(BookmarkRecordsByCollectionId.self, from: data)
    }

    private static func encodeBookmarkRecords(_ bookmarkRecords: BookmarkRecordsByCollectionId) -> Data? {
        try? JSONEncoder().encode(bookmarkRecords)
    }

    private static func decodeLegacyBookmarkRecords(from data: Data?) -> BookmarkRecordsByCollectionId? {
        guard let data,
              let legacyBookmarks = try? JSONDecoder().decode([String: LegacyPlayerBookmark].self, from: data) else {
            return nil
        }

        return legacyBookmarks.reduce(into: BookmarkRecordsByCollectionId()) { result, entry in
            guard !entry.value.tokenId.isEmpty else { return }
            result[entry.key, default: [:]][entry.value.tokenId] = PlayerBookmark(bookmarkedAt: entry.value.bookmarkedAt)
        }
    }

    static func clearLocalSyncedData() {
        cachedBookmarkRecordsByCollectionId = [:]
        cachedBookmarksData = nil
        userDefaults.removeObject(forKey: bookmarksSyncDomain.key)
        userDefaults.removeObject(forKey: legacyMobileBookmarksKey)
        NotificationCenter.default.post(name: .playerBookmarksDidChange, object: nil)
    }

    private static func compactBookmarkRecords(
        _ bookmarkRecords: BookmarkRecordsByCollectionId
    ) -> BookmarkRecordsByCollectionId {
        return bookmarkRecords.reduce(into: BookmarkRecordsByCollectionId()) { result, collectionEntry in
            guard !collectionEntry.value.isEmpty else { return }
            result[collectionEntry.key] = collectionEntry.value
        }
    }

    private static func save(
        _ bookmarkRecords: BookmarkRecordsByCollectionId,
        mirrorToICloud: Bool = true
    ) {
        let compactedBookmarkRecords = compactBookmarkRecords(bookmarkRecords)
        guard let data = encodeBookmarkRecords(compactedBookmarkRecords) else { return }
        cachedBookmarkRecordsByCollectionId = compactedBookmarkRecords
        cachedBookmarksData = data
        userDefaults.set(data, forKey: bookmarksSyncDomain.key)
        NotificationCenter.default.post(name: .playerBookmarksDidChange, object: nil)
#if os(macOS) || os(iOS)
        if mirrorToICloud {
            PlayerICloudSync.shared.playerBookmarksDidChange()
        }
#endif
    }

    private static func mergeBookmarkRecords(
        _ localBookmarkRecords: BookmarkRecordsByCollectionId,
        with remoteBookmarkRecords: BookmarkRecordsByCollectionId
    ) -> BookmarkRecordsByCollectionId {
        remoteBookmarkRecords.reduce(into: localBookmarkRecords) { result, collectionEntry in
            for tokenEntry in collectionEntry.value {
                if let localBookmark = result[collectionEntry.key]?[tokenEntry.key],
                   localBookmark.updatedAt >= tokenEntry.value.updatedAt {
                    continue
                }

                result[collectionEntry.key, default: [:]][tokenEntry.key] = tokenEntry.value
            }
        }
    }
}
