// ∅ 2026 lil org

import XCTest
@testable import NftPlayerSyncCore

final class PlayerSyncMergeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        resetStores()
    }

    override func tearDown() {
        resetStores()
        super.tearDown()
    }

    func testProgressMergeKeepsNewerLocalProgressOverStaleRemoteForwardProgress() throws {
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

        XCTAssertEqual(result, .remoteWasStale)
        XCTAssertEqual(PlayerViewingProgressStore.progress(collectionId: collectionId)?.tokenIndex, 2)
    }

    func testProgressMergeAppliesNewerRemoteProgressEvenWhenItMovesBackward() throws {
        let collectionId = "collection"
        let olderLocalProgress = progress(
            collectionId: collectionId,
            tokenId: "token-6",
            tokenIndex: 6,
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let newerRemoteProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )

        writeProgress([collectionId: olderLocalProgress])

        let result = PlayerViewingProgressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: newerRemoteProgress])
        )

        XCTAssertEqual(result, .localChanged)
        XCTAssertEqual(PlayerViewingProgressStore.progress(collectionId: collectionId)?.tokenIndex, 2)
    }

    func testProgressMergeUsesFurthestProgressWhenTimestampsMatch() throws {
        let collectionId = "collection"
        let updatedAt = Date(timeIntervalSinceReferenceDate: 300)
        let localProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: updatedAt
        )
        let remoteProgress = progress(
            collectionId: collectionId,
            tokenId: "token-6",
            tokenIndex: 6,
            updatedAt: updatedAt
        )

        writeProgress([collectionId: localProgress])

        let result = PlayerViewingProgressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: remoteProgress])
        )

        XCTAssertEqual(result, .localChanged)
        XCTAssertEqual(PlayerViewingProgressStore.progress(collectionId: collectionId)?.tokenIndex, 6)
    }

    func testProgressMergeKeepsViewedToEndStateWhileUsingLatestStopPosition() throws {
        let collectionId = "collection"
        let viewedToEndProgress = progress(
            collectionId: collectionId,
            tokenId: "token-6",
            tokenIndex: 6,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            hasViewedToEnd: true
        )
        let remoteProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )

        writeProgress([collectionId: viewedToEndProgress])

        _ = PlayerViewingProgressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: remoteProgress])
        )

        let mergedProgress = try XCTUnwrap(PlayerViewingProgressStore.progress(collectionId: collectionId))
        XCTAssertEqual(mergedProgress.tokenIndex, 2)
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
        try assertSyncedContinueViewingCleared()
    }

    func testSessionTrackerSavesProgressAndSetsContinueViewingForExpectedCollection() {
        let collectionId = "collection"
        var tracker = PlayerViewingSessionTracker(continueViewingCollectionId: collectionId)
        let viewedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )

        tracker.markViewed(viewedProgress)
        XCTAssertEqual(PlayerViewingProgressStore.progress(collectionId: collectionId), viewedProgress)
        XCTAssertEqual(
            PlayerViewingProgressStore.progressSnapshot().continueViewingProgress?.collectionId,
            collectionId
        )
    }

    func testSessionTrackerClearsContinueViewingWhenExpectedCollectionDoesNotMatch() throws {
        var tracker = PlayerViewingSessionTracker(continueViewingCollectionId: "expected")

        tracker.markViewed(
            progress(
                collectionId: "other",
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        XCTAssertNil(PlayerViewingProgressStore.progressSnapshot().continueViewingProgress)
        try assertSyncedContinueViewingCleared()
    }

    func testSessionTrackerClearsContinueViewingWhenCollectionIsViewedToEnd() throws {
        let collectionId = "collection"
        var tracker = PlayerViewingSessionTracker(continueViewingCollectionId: collectionId)

        tracker.markViewed(
            progress(
                collectionId: collectionId,
                tokenId: "token-9",
                tokenIndex: 9,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        XCTAssertNil(PlayerViewingProgressStore.progressSnapshot().continueViewingProgress)
        try assertSyncedContinueViewingCleared()
    }

    func testSessionTrackerKeepsContinueViewingClearedAtRestartedTokenZero() throws {
        let collectionId = "collection"
        var tracker = PlayerViewingSessionTracker(continueViewingCollectionId: collectionId)
        let viewedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-3",
            tokenIndex: 3,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        tracker.markViewed(viewedProgress)

        tracker.beginRestart(collectionId: viewedProgress.collectionId)
        tracker.markViewed(
            progress(
                collectionId: collectionId,
                tokenId: "token-0",
                tokenIndex: 0,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        XCTAssertNil(PlayerViewingProgressStore.progressSnapshot().continueViewingProgress)
        try assertSyncedContinueViewingCleared()
    }

    func testProgressOnlySessionTrackerSavesProgressWithoutReplacingContinueViewing() {
        let continueViewingCollectionId = "continue"
        let widgetCollectionId = "widget"
        let continueViewingProgress = progress(
            collectionId: continueViewingCollectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let widgetProgress = progress(
            collectionId: widgetCollectionId,
            tokenId: "token-4",
            tokenIndex: 4,
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        writeProgress([continueViewingCollectionId: continueViewingProgress])
        writeContinueViewing(
            PlayerContinueViewingState(
                collectionId: continueViewingCollectionId,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        var tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: widgetCollectionId,
            trackingMode: .progressOnly
        )
        tracker.markViewed(widgetProgress)

        XCTAssertEqual(PlayerViewingProgressStore.progress(collectionId: widgetCollectionId), widgetProgress)
        XCTAssertEqual(
            PlayerViewingProgressStore.progressSnapshot().continueViewingProgress?.collectionId,
            continueViewingCollectionId
        )
    }

    func testProgressOnlySessionTrackerDoesNotClearContinueViewingForMismatchedProgress() {
        let continueViewingCollectionId = "continue"
        let continueViewingProgress = progress(
            collectionId: continueViewingCollectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        writeProgress([continueViewingCollectionId: continueViewingProgress])
        writeContinueViewing(
            PlayerContinueViewingState(
                collectionId: continueViewingCollectionId,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        var tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: "expected-widget",
            trackingMode: .progressOnly
        )
        tracker.markViewed(
            progress(
                collectionId: "other-widget",
                tokenId: "token-4",
                tokenIndex: 4,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        XCTAssertEqual(
            PlayerViewingProgressStore.progressSnapshot().continueViewingProgress?.collectionId,
            continueViewingCollectionId
        )
    }

    func testProgressOnlySessionTrackerDoesNotClearContinueViewingDuringRestart() {
        let continueViewingCollectionId = "continue"
        let widgetCollectionId = "widget"
        let continueViewingProgress = progress(
            collectionId: continueViewingCollectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        writeProgress([continueViewingCollectionId: continueViewingProgress])
        writeContinueViewing(
            PlayerContinueViewingState(
                collectionId: continueViewingCollectionId,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        var tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: widgetCollectionId,
            trackingMode: .progressOnly
        )
        tracker.beginRestart(collectionId: widgetCollectionId)
        tracker.markViewed(
            progress(
                collectionId: widgetCollectionId,
                tokenId: "token-0",
                tokenIndex: 0,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        XCTAssertEqual(
            PlayerViewingProgressStore.progressSnapshot().continueViewingProgress?.collectionId,
            continueViewingCollectionId
        )
    }

    private func assertSyncedContinueViewingCleared() throws {
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
