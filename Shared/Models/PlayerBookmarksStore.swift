// ∅ 2026 lil org

import Foundation

struct PlayerBookmark: Codable, Hashable {
    let bookmarkedAt: Date
}

enum PlayerBookmarksStore {
    private static let bookmarksKey = "playerBookmarksByCollectionId"
    private static let legacyMobileBookmarksKey = "mobileBookmarksByCollectionId"
    private static let userDefaults = UserDefaults.standard
    private static var cachedBookmarksByCollectionId: [String: [String: PlayerBookmark]]?
    private static var cachedBookmarksData: Data?

    private struct LegacyPlayerBookmark: Codable {
        let tokenId: String
        let bookmarkedAt: Date
    }

    static func isBookmarked(collectionId: String, tokenId: String) -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }
        return bookmarksByCollectionId()[collectionId]?[tokenId] != nil
    }

    @discardableResult
    static func toggleBookmark(collectionId: String, tokenId: String) -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }

        var bookmarks = bookmarksByCollectionId()
        var collectionBookmarks = bookmarks[collectionId] ?? [:]
        if collectionBookmarks[tokenId] != nil {
            collectionBookmarks.removeValue(forKey: tokenId)
            if collectionBookmarks.isEmpty {
                bookmarks.removeValue(forKey: collectionId)
            } else {
                bookmarks[collectionId] = collectionBookmarks
            }
            save(bookmarks)
            return false
        }

        collectionBookmarks[tokenId] = PlayerBookmark(bookmarkedAt: Date())
        bookmarks[collectionId] = collectionBookmarks
        save(bookmarks)
        return true
    }

    private static func bookmarksByCollectionId() -> [String: [String: PlayerBookmark]] {
        let storedData = userDefaults.data(forKey: bookmarksKey)
        if let cachedBookmarksByCollectionId, cachedBookmarksData == storedData {
            return cachedBookmarksByCollectionId
        }

        if let bookmarks = decodeBookmarks(from: storedData) {
            cachedBookmarksByCollectionId = bookmarks
            cachedBookmarksData = storedData
            return bookmarks
        }

        if let bookmarks = decodeLegacyBookmarks(from: storedData) {
            save(bookmarks)
            return bookmarks
        }

        if let legacyData = userDefaults.data(forKey: legacyMobileBookmarksKey),
           let bookmarks = decodeBookmarks(from: legacyData) ?? decodeLegacyBookmarks(from: legacyData) {
            save(bookmarks)
            return bookmarks
        }

        cachedBookmarksByCollectionId = [:]
        cachedBookmarksData = storedData
        return [:]
    }

    private static func decodeBookmarks(from data: Data?) -> [String: [String: PlayerBookmark]]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: [String: PlayerBookmark]].self, from: data)
    }

    private static func decodeLegacyBookmarks(from data: Data?) -> [String: [String: PlayerBookmark]]? {
        guard let data,
              let legacyBookmarks = try? JSONDecoder().decode([String: LegacyPlayerBookmark].self, from: data) else {
            return nil
        }

        return legacyBookmarks.reduce(into: [String: [String: PlayerBookmark]]()) { result, entry in
            guard !entry.value.tokenId.isEmpty else { return }
            result[entry.key, default: [:]][entry.value.tokenId] = PlayerBookmark(bookmarkedAt: entry.value.bookmarkedAt)
        }
    }

    private static func save(_ bookmarks: [String: [String: PlayerBookmark]]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        cachedBookmarksByCollectionId = bookmarks
        cachedBookmarksData = data
        userDefaults.set(data, forKey: bookmarksKey)
    }
}
