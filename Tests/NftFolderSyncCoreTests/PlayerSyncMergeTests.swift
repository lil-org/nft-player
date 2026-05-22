// ∅ 2026 lil org

import XCTest
@testable import NftFolderSyncCore

final class PlayerSyncMergeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        resetStores()
    }

    override func tearDown() {
        resetStores()
        super.tearDown()
    }

    func testProgressMergeKeepsFurthestProgressOverNewestProgress() throws {
        let collectionId = "collection"
        let newerLocalProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let olderRemoteProgress = progress(
            collectionId: collectionId,
            tokenId: "token-6",
            tokenIndex: 6,
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )

        writeProgress([collectionId: newerLocalProgress])

        let result = PlayerViewingProgressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: olderRemoteProgress])
        )

        XCTAssertEqual(result, .localChanged)
        XCTAssertEqual(PlayerViewingProgressStore.progress(collectionId: collectionId)?.tokenIndex, 6)
    }

    func testProgressMergeKeepsViewedToEndStateWithoutMovingProgressBackward() throws {
        let collectionId = "collection"
        let viewedToEndProgress = progress(
            collectionId: collectionId,
            tokenId: "token-1",
            tokenIndex: 1,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            hasViewedToEnd: true
        )
        let remoteProgress = progress(
            collectionId: collectionId,
            tokenId: "token-6",
            tokenIndex: 6,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )

        writeProgress([collectionId: viewedToEndProgress])

        _ = PlayerViewingProgressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: remoteProgress])
        )

        let mergedProgress = try XCTUnwrap(PlayerViewingProgressStore.progress(collectionId: collectionId))
        XCTAssertEqual(mergedProgress.tokenIndex, 6)
        XCTAssertEqual(
            PlayerViewingProgressStore.progressSnapshot().viewedToEndCollectionIds,
            [collectionId]
        )
    }

    func testBookmarkMergeKeepsNewerLocalDeleteOverStaleRemoteActiveBookmark() throws {
        let collectionId = "collection"
        let tokenId = "token"
        let localDeletedBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200),
            isDeleted: true
        )
        let remoteActiveBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 150)
        )

        writeBookmarks([collectionId: [tokenId: localDeletedBookmark]])

        let result = PlayerBookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([collectionId: [tokenId: remoteActiveBookmark]])
        )

        XCTAssertEqual(result, .remoteWasStale)
        XCTAssertFalse(PlayerBookmarksStore.isBookmarked(collectionId: collectionId, tokenId: tokenId))
    }

    func testBookmarkMergeRestoresNewerRemoteActiveBookmarkAfterLocalDelete() throws {
        let collectionId = "collection"
        let tokenId = "token"
        let localDeletedBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200),
            isDeleted: true
        )
        let remoteActiveBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )

        writeBookmarks([collectionId: [tokenId: localDeletedBookmark]])

        let result = PlayerBookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([collectionId: [tokenId: remoteActiveBookmark]])
        )

        XCTAssertEqual(result, .localChanged)
        XCTAssertTrue(PlayerBookmarksStore.isBookmarked(collectionId: collectionId, tokenId: tokenId))
    }

    func testDeletedBookmarkIsEncodedForSync() throws {
        let collectionId = "collection"
        let tokenId = "token"
        let deletedBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200),
            isDeleted: true
        )
        writeBookmarks([collectionId: [tokenId: deletedBookmark]])

        let data = try XCTUnwrap(PlayerBookmarksStore.syncedBookmarksData)
        let bookmarks = try JSONDecoder().decode([String: [String: PlayerBookmark]].self, from: data)
        XCTAssertEqual(bookmarks[collectionId]?[tokenId], deletedBookmark)
    }

    func testContinueViewingIgnoresRemoteClearWhenLocalProgressIsUseful() throws {
        let collectionId = "collection"
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        ])
        writeContinueViewing(
            PlayerContinueViewingState(
                collectionId: collectionId,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        let remoteClear = PlayerContinueViewingState(
            collectionId: nil,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteClear)
        )

        XCTAssertEqual(result, .remoteWasStale)
        XCTAssertEqual(
            PlayerViewingProgressStore.progressSnapshot().continueViewingProgress?.collectionId,
            collectionId
        )
    }

    func testClearedContinueViewingStateIsEncodedForSync() throws {
        let clearedState = PlayerContinueViewingState(
            collectionId: nil,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        writeContinueViewing(clearedState)

        let data = try XCTUnwrap(PlayerViewingProgressStore.syncedContinueViewingStateData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertEqual(state, clearedState)
    }

    func testContinueViewingUpdateKeepsViewedToEndCollectionCleared() throws {
        let collectionId = "collection"
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "token-6",
                tokenIndex: 6,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100),
                hasViewedToEnd: true
            )
        ])

        PlayerViewingProgressStore.updateContinueViewingCollection(
            for: progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            ),
            expectedCollectionId: collectionId
        )

        XCTAssertNil(PlayerViewingProgressStore.progressSnapshot().continueViewingProgress)
        let data = try XCTUnwrap(PlayerViewingProgressStore.syncedContinueViewingStateData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertNil(state.collectionId)
    }

    private func progress(
        collectionId: String,
        tokenId: String,
        tokenIndex: Int,
        updatedAt: Date,
        hasViewedToEnd: Bool = false
    ) -> PlayerViewingProgress {
        PlayerViewingProgress(
            collectionId: collectionId,
            collectionName: "Collection",
            tokenId: tokenId,
            tokenIndex: tokenIndex,
            tokenCount: 10,
            updatedAt: updatedAt,
            hasViewedToEnd: hasViewedToEnd
        )
    }

    private func resetStores() {
        PlayerViewingProgressStore.clearLocalSyncedData()
        PlayerBookmarksStore.clearLocalSyncedData()
    }

    private func writeProgress(_ progress: [String: PlayerViewingProgress]) {
        UserDefaults.standard.set(try! encodedProgress(progress), forKey: PlayerSyncDomain.viewingProgress.key)
    }

    private func writeBookmarks(_ bookmarks: [String: [String: PlayerBookmark]]) {
        UserDefaults.standard.set(try! encodedBookmarks(bookmarks), forKey: PlayerSyncDomain.bookmarks.key)
    }

    private func writeContinueViewing(_ state: PlayerContinueViewingState) {
        UserDefaults.standard.set(
            try! JSONEncoder().encode(state),
            forKey: PlayerSyncDomain.continueViewingState.key
        )
    }

    private func encodedProgress(_ progress: [String: PlayerViewingProgress]) throws -> Data {
        try JSONEncoder().encode(progress)
    }

    private func encodedBookmarks(_ bookmarks: [String: [String: PlayerBookmark]]) throws -> Data {
        try JSONEncoder().encode(bookmarks)
    }

}
