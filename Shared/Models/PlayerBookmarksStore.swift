// ∅ 2026 lil org

import Foundation
import os

nonisolated extension Notification.Name {
    static let playerBookmarksDidChange = Notification.Name("PlayerBookmarksDidChange")
}

nonisolated struct PlayerBookmark: Codable, Hashable, Sendable {
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

nonisolated struct PlayerStoredBookmarkState: Equatable, Sendable {
    let isBookmarked: Bool
    let isTogglePending: Bool
    let isReady: Bool
}

nonisolated struct PlayerBookmarkPresentationState: Equatable, Sendable {

    struct Target: Equatable, Hashable, Sendable {
        let collectionId: String
        let tokenId: String
    }

    struct LoadRequest: Equatable, Sendable {
        let target: Target
        fileprivate let revision: UInt
    }

    struct ToggleRequest: Equatable, Sendable {
        let target: Target
        let isBookmarked: Bool
    }

    private(set) var target: Target?
    private(set) var isBookmarked = false
    private(set) var isReady = false
    private(set) var isTogglePending = false
    private var revision: UInt = 0

    var canToggle: Bool {
        target != nil && isReady && !isTogglePending
    }

    @discardableResult
    mutating func beginLoading(
        target: Target?,
        storedState: PlayerStoredBookmarkState
    ) -> LoadRequest? {
        revision &+= 1
        self.target = target
        isBookmarked = target == nil ? false : storedState.isBookmarked
        isReady = target == nil || storedState.isReady
        isTogglePending = target != nil && storedState.isTogglePending
        return target.map { LoadRequest(target: $0, revision: revision) }
    }

    mutating func beginToggle() -> ToggleRequest? {
        guard canToggle, let target else { return nil }
        revision &+= 1
        isTogglePending = true
        return ToggleRequest(target: target, isBookmarked: !isBookmarked)
    }

    @discardableResult
    mutating func applyLoadedState(
        isBookmarked: Bool,
        for request: LoadRequest
    ) -> Bool {
        guard target == request.target, revision == request.revision else {
            return false
        }
        self.isBookmarked = isBookmarked
        isReady = true
        return true
    }

    @discardableResult
    mutating func applyToggleCompletion(
        isBookmarked: Bool,
        for target: Target,
        isTogglePending: Bool
    ) -> Bool {
        guard self.target == target else { return false }
        revision &+= 1
        self.isBookmarked = isBookmarked
        isReady = true
        self.isTogglePending = isTogglePending
        return true
    }
}

actor PlayerBookmarksStore {
    private typealias BookmarkRecordsByCollectionId = [String: [String: PlayerBookmark]]

    private nonisolated struct BookmarkKey: Hashable, Sendable {
        let collectionId: String
        let tokenId: String
    }

    private nonisolated struct SnapshotState: Sendable {
        var records = BookmarkRecordsByCollectionId()
        var isLoaded = false
        var pendingToggleKeys = Set<BookmarkKey>()
    }

    static let shared = PlayerBookmarksStore()

    private static let bookmarksSyncDomain = PlayerSyncDomain.bookmarks
    private static let quarantinedBookmarksKey =
        "\(bookmarksSyncDomain.key).quarantinedRemote"
    nonisolated private static let snapshot = OSAllocatedUnfairLock(
        initialState: SnapshotState()
    )
    private let userDefaults: UserDefaults
    private let updatesSharedSnapshot: Bool
    private var cachedBookmarkRecordsByCollectionId: BookmarkRecordsByCollectionId?
    private var cachedBookmarksData: Data?
    private var quarantinedRemoteBookmarkRecords = BookmarkRecordsByCollectionId()

    init(userDefaults: sending UserDefaults = .standard) {
        updatesSharedSnapshot = userDefaults === UserDefaults.standard
        let quarantinedRecords = userDefaults.data(forKey: Self.quarantinedBookmarksKey)
            .flatMap {
                try? JSONDecoder().decode(BookmarkRecordsByCollectionId.self, from: $0)
            }
            ?? [:]
        self.userDefaults = userDefaults
        quarantinedRemoteBookmarkRecords = quarantinedRecords
    }

    nonisolated static func storedBookmarkState(
        collectionId: String,
        tokenId: String
    ) -> PlayerStoredBookmarkState {
        guard !collectionId.isEmpty, !tokenId.isEmpty else {
            return PlayerStoredBookmarkState(
                isBookmarked: false,
                isTogglePending: false,
                isReady: true
            )
        }
        let key = BookmarkKey(collectionId: collectionId, tokenId: tokenId)
        return snapshot.withLock { state in
            PlayerStoredBookmarkState(
                isBookmarked: state.records[collectionId]?[tokenId]?.isDeleted == false,
                isTogglePending: state.pendingToggleKeys.contains(key),
                isReady: state.isLoaded
            )
        }
    }

    @MainActor
    @discardableResult
    static func enqueueBookmarkUpdate(
        collectionId: String,
        tokenId: String,
        isBookmarked: Bool,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else {
            completion?(false)
            return false
        }
        let key = BookmarkKey(collectionId: collectionId, tokenId: tokenId)
        let admission = snapshot.withLock {
            state -> (admitted: Bool, existingBookmark: PlayerBookmark?) in
            guard state.pendingToggleKeys.insert(key).inserted else {
                return (false, nil)
            }
            return (true, state.records[collectionId]?[tokenId])
        }
        guard admission.admitted else { return false }
        let existingBookmark = admission.existingBookmark
        let updatedAt = PlayerSyncLogicalClock.next(
            for: .bookmarks,
            after: existingBookmark?.updatedAt
        )
        let bookmarkUpdate = PlayerBookmark(
            bookmarkedAt: isBookmarked && existingBookmark?.isDeleted != false
                ? updatedAt
                : existingBookmark?.bookmarkedAt ?? updatedAt,
            updatedAt: updatedAt,
            isDeleted: !isBookmarked
        )
        NotificationCenter.default.post(
            name: .playerBookmarksDidChange,
            object: nil
        )
        PlayerPersistenceUpdates.enqueue {
            let isBookmarked = await shared.applyBookmark(
                bookmarkUpdate,
                collectionId: collectionId,
                tokenId: tokenId
            )
            snapshot.withLock { state in
                _ = state.pendingToggleKeys.remove(key)
            }
            NotificationCenter.default.post(
                name: .playerBookmarksDidChange,
                object: nil
            )
            completion?(isBookmarked)
        }
        return true
    }

    func isBookmarked(collectionId: String, tokenId: String) -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }
        return bookmarkRecordsByCollectionId()[collectionId]?[tokenId]?.isDeleted == false
    }

    func prepareSharedSnapshot() {
        guard updatesSharedSnapshot else { return }
        _ = bookmarkRecordsByCollectionId()
    }

    var syncedBookmarksData: Data? {
        var bookmarkRecords = bookmarkRecordsByCollectionId()
        for (collectionId, recordsByTokenId) in quarantinedRemoteBookmarkRecords {
            for (tokenId, bookmark) in recordsByTokenId {
                bookmarkRecords[collectionId, default: [:]][tokenId] = bookmark
            }
        }
        let compactedBookmarkRecords = compactBookmarkRecords(bookmarkRecords)
        guard !compactedBookmarkRecords.isEmpty else { return nil }
        return encodeBookmarkRecords(compactedBookmarkRecords)
    }

    @discardableResult
    func toggleBookmark(collectionId: String, tokenId: String) async -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }

        let existingBookmark = bookmarkRecordsByCollectionId()[collectionId]?[tokenId]
        let now = PlayerSyncLogicalClock.next(
            for: .bookmarks,
            after: existingBookmark?.updatedAt
        )
        let willBeBookmarked = existingBookmark?.isDeleted != false
        return await applyBookmark(
            PlayerBookmark(
                bookmarkedAt: willBeBookmarked
                    ? now
                    : existingBookmark?.bookmarkedAt ?? now,
                updatedAt: now,
                isDeleted: !willBeBookmarked
            ),
            collectionId: collectionId,
            tokenId: tokenId
        )
    }

    func mergeSyncedBookmarksData(_ data: Data?) async -> PlayerSyncMergeResult {
        guard let data else {
            replaceQuarantinedRemoteBookmarks(with: [:])
            return .ignored
        }
        guard let decodedRemoteBookmarkRecords = decodeBookmarkRecords(from: data) else {
            replaceQuarantinedRemoteBookmarks(with: [:])
            return .ignored
        }
        let localBookmarkRecords = bookmarkRecordsByCollectionId()
        let compactedLocalBookmarkRecords = compactBookmarkRecords(localBookmarkRecords)
        let remotePayload = filteredRemoteBookmarkRecords(
            decodedRemoteBookmarkRecords,
            relativeTo: PlayerSyncTimestampPolicy.currentDate,
            preserving: compactedLocalBookmarkRecords
        )
        replaceQuarantinedRemoteBookmarks(with: remotePayload.rejectedRecords)
        observeTimestamps(in: remotePayload.records)

        let compactedRemoteBookmarkRecords = compactBookmarkRecords(remotePayload.records)
        let mergedBookmarkRecords = mergeBookmarkRecords(
            compactedLocalBookmarkRecords,
            with: compactedRemoteBookmarkRecords
        )
        let hasQuarantinedLocalBookmark = remotePayload.rejectedRecords.contains {
            collectionId, recordsByTokenId in
            guard let localRecords = compactedLocalBookmarkRecords[collectionId] else {
                return false
            }
            return !Set(localRecords.keys).isDisjoint(with: recordsByTokenId.keys)
        }
        if mergedBookmarkRecords != localBookmarkRecords {
            await save(mergedBookmarkRecords, mirrorToICloud: false)
            return hasQuarantinedLocalBookmark
                ? .remoteWasPartiallyUntrusted
                : .localChanged
        }
        if hasQuarantinedLocalBookmark {
            return .remoteWasPartiallyUntrusted
        }
        return compactedRemoteBookmarkRecords == compactedLocalBookmarkRecords
            ? .ignored
            : .remoteWasStale
    }

    private func bookmarkRecordsByCollectionId() -> BookmarkRecordsByCollectionId {
        let storedData = userDefaults.data(forKey: Self.bookmarksSyncDomain.key)
        if let cachedBookmarkRecordsByCollectionId, cachedBookmarksData == storedData {
            let normalizedRecords = normalizedLocalBookmarkRecords(
                cachedBookmarkRecordsByCollectionId,
                relativeTo: PlayerSyncTimestampPolicy.currentDate
            )
            guard normalizedRecords != cachedBookmarkRecordsByCollectionId else {
                return cachedBookmarkRecordsByCollectionId
            }
            saveWithoutMirroring(normalizedRecords)
            scheduleBookmarksSync()
            return normalizedRecords
        }

        if let decodedRecords = decodeBookmarkRecords(from: storedData) {
            let normalizedRecords = normalizedLocalBookmarkRecords(
                decodedRecords,
                relativeTo: PlayerSyncTimestampPolicy.currentDate
            )
            let compactedRecords = compactBookmarkRecords(normalizedRecords)
            if compactedRecords != decodedRecords {
                saveWithoutMirroring(compactedRecords)
                scheduleBookmarksSync()
                updateSharedSnapshotIfNeeded(compactedRecords)
                return compactedRecords
            }

            cachedBookmarkRecordsByCollectionId = compactedRecords
            cachedBookmarksData = storedData
            observeTimestamps(in: compactedRecords)
            updateSharedSnapshotIfNeeded(compactedRecords)
            return compactedRecords
        }

        cachedBookmarkRecordsByCollectionId = [:]
        cachedBookmarksData = storedData
        updateSharedSnapshotIfNeeded([:])
        return [:]
    }

    private func decodeBookmarkRecords(from data: Data?) -> BookmarkRecordsByCollectionId? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(
            BookmarkRecordsByCollectionId.self,
            from: data
        )
    }

    private func normalizedLocalBookmarkRecords(
        _ bookmarkRecords: BookmarkRecordsByCollectionId,
        relativeTo now: Date
    ) -> BookmarkRecordsByCollectionId {
        bookmarkRecords.mapValues { recordsByTokenId in
            recordsByTokenId.mapValues { bookmark in
                PlayerBookmark(
                    bookmarkedAt: PlayerSyncTimestampPolicy.normalizedLocalTimestamp(
                        bookmark.bookmarkedAt,
                        relativeTo: now
                    ),
                    updatedAt: PlayerSyncTimestampPolicy.normalizedLocalTimestamp(
                        bookmark.updatedAt,
                        relativeTo: now
                    ),
                    isDeleted: bookmark.isDeleted
                )
            }
        }
    }

    private func filteredRemoteBookmarkRecords(
        _ bookmarkRecords: BookmarkRecordsByCollectionId,
        relativeTo now: Date,
        preserving localBookmarkRecords: BookmarkRecordsByCollectionId
    ) -> (records: BookmarkRecordsByCollectionId, rejectedRecords: BookmarkRecordsByCollectionId) {
        var rejectedRecords = BookmarkRecordsByCollectionId()
        let records = bookmarkRecords.reduce(into: BookmarkRecordsByCollectionId()) { result, collection in
            for (tokenId, bookmark) in collection.value {
                let remainsQuarantined = quarantinedRemoteBookmarkRecords[
                    collection.key
                ]?[tokenId] == bookmark
                    && localBookmarkRecords[collection.key]?[tokenId] != nil
                guard !remainsQuarantined, PlayerSyncTimestampPolicy.isPlausible(
                    bookmark.updatedAt,
                    relativeTo: now
                ) else {
                    rejectedRecords[collection.key, default: [:]][tokenId] = bookmark
                    continue
                }
                result[collection.key, default: [:]][tokenId] = PlayerBookmark(
                    bookmarkedAt: PlayerSyncTimestampPolicy.normalizedLocalTimestamp(
                        bookmark.bookmarkedAt,
                        relativeTo: now
                    ),
                    updatedAt: bookmark.updatedAt,
                    isDeleted: bookmark.isDeleted
                )
            }
        }
        return (records, rejectedRecords)
    }

    private func replaceQuarantinedRemoteBookmarks(
        with records: BookmarkRecordsByCollectionId
    ) {
        quarantinedRemoteBookmarkRecords = compactBookmarkRecords(records)
        guard !quarantinedRemoteBookmarkRecords.isEmpty,
              let data = encodeBookmarkRecords(quarantinedRemoteBookmarkRecords) else {
            userDefaults.removeObject(forKey: Self.quarantinedBookmarksKey)
            return
        }
        userDefaults.set(data, forKey: Self.quarantinedBookmarksKey)
    }

    private func encodeBookmarkRecords(_ bookmarkRecords: BookmarkRecordsByCollectionId) -> Data? {
        try? JSONEncoder().encode(bookmarkRecords)
    }

#if SWIFT_PACKAGE
    func resetForTesting() {
        cachedBookmarkRecordsByCollectionId = [:]
        cachedBookmarksData = nil
        quarantinedRemoteBookmarkRecords = [:]
        userDefaults.removeObject(forKey: Self.bookmarksSyncDomain.key)
        userDefaults.removeObject(forKey: Self.quarantinedBookmarksKey)
        if updatesSharedSnapshot {
            Self.snapshot.withLock {
                $0.records = [:]
                $0.isLoaded = true
                $0.pendingToggleKeys.removeAll()
            }
        }
        NotificationCenter.default.post(name: .playerBookmarksDidChange, object: nil)
    }
#endif

    private func compactBookmarkRecords(
        _ bookmarkRecords: BookmarkRecordsByCollectionId
    ) -> BookmarkRecordsByCollectionId {
        return bookmarkRecords.reduce(into: BookmarkRecordsByCollectionId()) { result, collectionEntry in
            guard !collectionEntry.value.isEmpty else { return }
            result[collectionEntry.key] = collectionEntry.value
        }
    }

    private func save(
        _ bookmarkRecords: BookmarkRecordsByCollectionId,
        mirrorToICloud: Bool = true
    ) async {
        saveWithoutMirroring(bookmarkRecords)
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        if mirrorToICloud {
            await PlayerICloudSync.shared.playerBookmarksDidChange()
        }
#endif
    }

    private func saveWithoutMirroring(_ bookmarkRecords: BookmarkRecordsByCollectionId) {
        let compactedBookmarkRecords = compactBookmarkRecords(bookmarkRecords)
        observeTimestamps(in: compactedBookmarkRecords)
        guard let data = encodeBookmarkRecords(compactedBookmarkRecords) else { return }
        cachedBookmarkRecordsByCollectionId = compactedBookmarkRecords
        cachedBookmarksData = data
        updateSharedSnapshotIfNeeded(compactedBookmarkRecords)
        userDefaults.set(data, forKey: Self.bookmarksSyncDomain.key)
        NotificationCenter.default.post(name: .playerBookmarksDidChange, object: nil)
    }

    private func scheduleBookmarksSync() {
#if os(macOS) || os(iOS) || os(visionOS) || os(tvOS)
        Task { @MainActor in
            PlayerICloudSync.shared.playerBookmarksDidChange()
        }
#endif
    }

    private func updateSharedSnapshotIfNeeded(
        _ records: BookmarkRecordsByCollectionId
    ) {
        guard updatesSharedSnapshot else { return }
        Self.snapshot.withLock {
            $0.records = records
            $0.isLoaded = true
        }
    }

    private func applyBookmark(
        _ incomingBookmark: PlayerBookmark,
        collectionId: String,
        tokenId: String
    ) async -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }
        var bookmarkRecords = bookmarkRecordsByCollectionId()
        var collectionBookmarkRecords = bookmarkRecords[collectionId] ?? [:]
        let existingBookmark = collectionBookmarkRecords[tokenId]
        let now = PlayerSyncTimestampPolicy.currentDate
        let updatedAt: Date
        if PlayerSyncTimestampPolicy.isPlausible(
            incomingBookmark.updatedAt,
            relativeTo: now
        ) {
            updatedAt = incomingBookmark.updatedAt
        } else {
            updatedAt = PlayerSyncLogicalClock.next(
                for: .bookmarks,
                after: existingBookmark?.updatedAt
            )
        }
        let bookmarkedAt: Date
        if PlayerSyncTimestampPolicy.isPlausible(
            incomingBookmark.bookmarkedAt,
            relativeTo: now
        ) {
            bookmarkedAt = incomingBookmark.bookmarkedAt
        } else if incomingBookmark.isDeleted {
            bookmarkedAt = existingBookmark?.bookmarkedAt ?? updatedAt
        } else {
            bookmarkedAt = updatedAt
        }
        let bookmark = PlayerBookmark(
            bookmarkedAt: bookmarkedAt,
            updatedAt: updatedAt,
            isDeleted: incomingBookmark.isDeleted
        )

        let updatedBookmark = existingBookmark
            .map { mergeBookmark($0, with: bookmark) }
            ?? bookmark
        guard collectionBookmarkRecords[tokenId] != updatedBookmark else {
            return !updatedBookmark.isDeleted
        }

        collectionBookmarkRecords[tokenId] = updatedBookmark
        bookmarkRecords[collectionId] = collectionBookmarkRecords
        await save(bookmarkRecords)
        return bookmarkRecordsByCollectionId()[collectionId]?[tokenId]?.isDeleted == false
    }

    private func observeTimestamps(in bookmarkRecords: BookmarkRecordsByCollectionId) {
        var latestTimestamp: Date?
        for bookmarkRecordsByTokenId in bookmarkRecords.values {
            for bookmark in bookmarkRecordsByTokenId.values {
                latestTimestamp = latestTimestamp.map { max($0, bookmark.updatedAt) }
                    ?? bookmark.updatedAt
            }
        }
        if let latestTimestamp {
            PlayerSyncLogicalClock.observe(latestTimestamp, for: .bookmarks)
        }
    }

    private func mergeBookmarkRecords(
        _ localBookmarkRecords: BookmarkRecordsByCollectionId,
        with remoteBookmarkRecords: BookmarkRecordsByCollectionId
    ) -> BookmarkRecordsByCollectionId {
        remoteBookmarkRecords.reduce(into: localBookmarkRecords) { result, collectionEntry in
            for tokenEntry in collectionEntry.value {
                if let localBookmark = result[collectionEntry.key]?[tokenEntry.key] {
                    result[collectionEntry.key, default: [:]][tokenEntry.key] = mergeBookmark(
                        localBookmark,
                        with: tokenEntry.value
                    )
                    continue
                }

                result[collectionEntry.key, default: [:]][tokenEntry.key] = tokenEntry.value
            }
        }
    }

    private func mergeBookmark(
        _ localBookmark: PlayerBookmark,
        with remoteBookmark: PlayerBookmark
    ) -> PlayerBookmark {
        guard localBookmark.isDeleted == remoteBookmark.isDeleted else {
            if localBookmark.updatedAt == remoteBookmark.updatedAt {
                return localBookmark.isDeleted ? remoteBookmark : localBookmark
            }
            return localBookmark.updatedAt > remoteBookmark.updatedAt ? localBookmark : remoteBookmark
        }

        let bookmarkedAt = min(localBookmark.bookmarkedAt, remoteBookmark.bookmarkedAt)
        let updatedAt = max(localBookmark.updatedAt, remoteBookmark.updatedAt)
        return PlayerBookmark(
            bookmarkedAt: bookmarkedAt,
            updatedAt: updatedAt,
            isDeleted: localBookmark.isDeleted
        )
    }
}
