// ∅ 2026 lil org

import XCTest
@testable import NftPlayerSyncCore

final class PlayerSyncMergeTests: XCTestCase {

    private struct LegacyContinueViewingState: Codable {
        let collectionId: String?
        let updatedAt: Date
    }

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

    func testLegacySingleContinueViewingStateDecodesIntoRecentList() throws {
        let collectionId = "legacy"
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        ])
        writeLegacyContinueViewing(
            collectionId: collectionId,
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )

        XCTAssertEqual(continueViewingCollectionIds(), [collectionId])

        let data = try XCTUnwrap(PlayerViewingProgressStore.syncedContinueViewingStateData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertEqual(state.collectionId, collectionId)
        XCTAssertEqual(state.entries.map(\.collectionId), [collectionId])
    }

    func testContinueViewingMergeSeedsRecentListFromProgressWhenStateIsMissing() throws {
        let collectionIds = (0..<25).map { "collection-\($0)" }
        let progressByCollectionId = Dictionary(
            uniqueKeysWithValues: collectionIds.enumerated().map { index, collectionId in
                (
                    collectionId,
                    progress(
                        collectionId: collectionId,
                        tokenId: "token-\(index)",
                        tokenIndex: min(index, 8),
                        updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
                        hasViewedToEnd: index == 24
                    )
                )
            }
        )
        writeProgress(progressByCollectionId)

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(nil)

        let expectedCollectionIds = Array((4...23).reversed()).map { "collection-\($0)" }
        XCTAssertEqual(result, .localChanged)
        XCTAssertEqual(continueViewingCollectionIds(), expectedCollectionIds)

        let data = try XCTUnwrap(PlayerViewingProgressStore.syncedContinueViewingStateData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertEqual(state.entries.filter { !$0.isRemoved }.map(\.collectionId), expectedCollectionIds)
        XCTAssertEqual(state.collectionId, "collection-23")
    }

    func testContinueViewingMergeDoesNotSeedFromProgressAfterExplicitLocalClear() {
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
                collectionId: nil,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(nil)

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(continueViewingCollectionIds(), [])
    }

    func testContinueViewingMergeStoresRemoteClearWhenLocalStateIsMissing() throws {
        let collectionId = "collection"
        let remoteClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 300)
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        ])

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(collectionId: nil, updatedAt: remoteClearUpdatedAt)
            )
        )

        XCTAssertEqual(result, .localChanged)
        XCTAssertEqual(continueViewingCollectionIds(), [])

        let state = try syncedContinueViewingState()
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, remoteClearUpdatedAt)
    }

    func testContinueViewingMergeAcceptsNewerRemoteClearOverOlderLocalClear() throws {
        let localClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let remoteClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 300)
        writeContinueViewing(
            PlayerContinueViewingState(collectionId: nil, updatedAt: localClearUpdatedAt)
        )

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(collectionId: nil, updatedAt: remoteClearUpdatedAt)
            )
        )

        XCTAssertEqual(result, .localChanged)

        let state = try syncedContinueViewingState()
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, remoteClearUpdatedAt)
    }

    func testContinueViewingMergeKeepsNewerLocalClearOverStaleRemoteClear() throws {
        let localClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 300)
        let remoteClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 100)
        writeContinueViewing(
            PlayerContinueViewingState(collectionId: nil, updatedAt: localClearUpdatedAt)
        )

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(collectionId: nil, updatedAt: remoteClearUpdatedAt)
            )
        )

        XCTAssertEqual(result, .remoteWasStale)

        let state = try syncedContinueViewingState()
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, localClearUpdatedAt)
    }

    func testContinueViewingSnapshotReturnsRecentEntriesNewestFirst() {
        let older = "older"
        let middle = "middle"
        let newer = "newer"
        writeProgress([
            older: progress(
                collectionId: older,
                tokenId: "token-1",
                tokenIndex: 1,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            ),
            middle: progress(
                collectionId: middle,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            ),
            newer: progress(
                collectionId: newer,
                tokenId: "token-3",
                tokenIndex: 3,
                updatedAt: Date(timeIntervalSinceReferenceDate: 300)
            )
        ])
        writeContinueViewing(
            PlayerContinueViewingState(
                entries: [
                    PlayerContinueViewingEntry(
                        collectionId: newer,
                        updatedAt: Date(timeIntervalSinceReferenceDate: 300)
                    ),
                    PlayerContinueViewingEntry(
                        collectionId: middle,
                        updatedAt: Date(timeIntervalSinceReferenceDate: 200)
                    ),
                    PlayerContinueViewingEntry(
                        collectionId: older,
                        updatedAt: Date(timeIntervalSinceReferenceDate: 100)
                    )
                ]
            )
        )

        XCTAssertEqual(continueViewingCollectionIds(), [newer, middle, older])
        XCTAssertEqual(
            PlayerViewingProgressStore.progressSnapshot().continueViewingProgress?.collectionId,
            newer
        )
    }

    func testContinueViewingSnapshotPreservesEntryOrderWhenTimestampsMatch() throws {
        let expectedCollectionIds = ["z-newest", "m-middle", "a-oldest"]
        let updatedAt = Date(timeIntervalSinceReferenceDate: 300)
        writeProgress(
            Dictionary(
                uniqueKeysWithValues: expectedCollectionIds.enumerated().map { index, collectionId in
                    (
                        collectionId,
                        progress(
                            collectionId: collectionId,
                            tokenId: "token-\(index)",
                            tokenIndex: index + 1,
                            updatedAt: updatedAt
                        )
                    )
                }
            )
        )
        writeContinueViewing(
            PlayerContinueViewingState(
                entries: expectedCollectionIds.map { collectionId in
                    PlayerContinueViewingEntry(collectionId: collectionId, updatedAt: updatedAt)
                }
            )
        )

        XCTAssertEqual(continueViewingCollectionIds(), expectedCollectionIds)

        let state = try syncedContinueViewingState()
        XCTAssertEqual(state.entries.filter { !$0.isRemoved }.map(\.collectionId), expectedCollectionIds)
    }

    func testSetContinueViewingMovesDuplicateCollectionToFront() {
        let first = "first"
        let second = "second"
        writeProgress([
            first: progress(
                collectionId: first,
                tokenId: "token-1",
                tokenIndex: 1,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            ),
            second: progress(
                collectionId: second,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        ])

        PlayerViewingProgressStore.setContinueViewingCollectionId(first)
        PlayerViewingProgressStore.setContinueViewingCollectionId(second)
        PlayerViewingProgressStore.setContinueViewingCollectionId(first)

        XCTAssertEqual(continueViewingCollectionIds(), [first, second])
    }

    func testSetContinueViewingCapsActiveRecentListAtTwentyCollections() {
        let collectionIds = (0..<25).map { "collection-\($0)" }
        let progressByCollectionId = Dictionary(
            uniqueKeysWithValues: collectionIds.enumerated().map { index, collectionId in
                (
                    collectionId,
                    progress(
                        collectionId: collectionId,
                        tokenId: "token-\(index)",
                        tokenIndex: min(index, 8),
                        updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index))
                    )
                )
            }
        )
        writeProgress(progressByCollectionId)

        collectionIds.forEach(PlayerViewingProgressStore.setContinueViewingCollectionId)

        let recentCollectionIds = continueViewingCollectionIds()
        XCTAssertEqual(recentCollectionIds.count, 20)
        XCTAssertEqual(recentCollectionIds.first, "collection-24")
        XCTAssertEqual(recentCollectionIds.last, "collection-5")
        XCTAssertFalse(recentCollectionIds.contains("collection-4"))
    }

    func testRemovingMostRecentContinueViewingCollectionRevealsOlderCollection() {
        let recent = "recent"
        let older = "older"
        writeProgress([
            recent: progress(
                collectionId: recent,
                tokenId: "token-9",
                tokenIndex: 9,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200),
                hasViewedToEnd: true
            ),
            older: progress(
                collectionId: older,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        ])
        writeContinueViewing(
            PlayerContinueViewingState(
                entries: [
                    PlayerContinueViewingEntry(
                        collectionId: recent,
                        updatedAt: Date(timeIntervalSinceReferenceDate: 200)
                    ),
                    PlayerContinueViewingEntry(
                        collectionId: older,
                        updatedAt: Date(timeIntervalSinceReferenceDate: 100)
                    )
                ]
            )
        )

        PlayerViewingProgressStore.updateContinueViewingCollection(
            for: progress(
                collectionId: recent,
                tokenId: "token-9",
                tokenIndex: 9,
                updatedAt: Date(timeIntervalSinceReferenceDate: 300)
            ),
            expectedCollectionId: recent
        )

        XCTAssertEqual(continueViewingCollectionIds(), [older])
    }

    func testContinueViewingMergeKeepsNewerLocalRemovalOverStaleRemoteActiveEntry() throws {
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
                entries: [
                    PlayerContinueViewingEntry(
                        collectionId: collectionId,
                        updatedAt: Date(timeIntervalSinceReferenceDate: 300),
                        isRemoved: true
                    )
                ]
            )
        )
        let remoteState = PlayerContinueViewingState(
            entries: [
                PlayerContinueViewingEntry(
                    collectionId: collectionId,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 100)
                )
            ]
        )

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteState)
        )

        XCTAssertEqual(result, .remoteWasStale)
        XCTAssertEqual(continueViewingCollectionIds(), [])
    }

    func testRemovingAlreadyRemovedContinueViewingCollectionDoesNotRefreshTombstone() throws {
        let collectionId = "collection"
        let removedAt = Date(timeIntervalSinceReferenceDate: 300)
        let removedEntry = PlayerContinueViewingEntry(
            collectionId: collectionId,
            updatedAt: removedAt,
            isRemoved: true
        )
        writeContinueViewing(
            PlayerContinueViewingState(entries: [removedEntry])
        )

        PlayerViewingProgressStore.removeContinueViewingCollectionId(collectionId)

        let data = try XCTUnwrap(PlayerViewingProgressStore.syncedContinueViewingStateData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertEqual(state.entries, [removedEntry])
        XCTAssertEqual(state.updatedAt, removedAt)
    }

    func testContinueViewingMergeKeepsNewerLocalClearOverStaleRemoteActiveEntry() throws {
        let collectionId = "collection"
        let localClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 300)
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
                collectionId: nil,
                updatedAt: localClearUpdatedAt
            )
        )
        let remoteState = PlayerContinueViewingState(
            entries: [
                PlayerContinueViewingEntry(
                    collectionId: collectionId,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 100)
                )
            ]
        )

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteState)
        )

        XCTAssertEqual(result, .remoteWasStale)
        XCTAssertEqual(continueViewingCollectionIds(), [])

        let data = try XCTUnwrap(PlayerViewingProgressStore.syncedContinueViewingStateData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, localClearUpdatedAt)
    }

    func testContinueViewingMergeAcceptsRemoteEntryNewerThanLocalClear() throws {
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
                collectionId: nil,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )
        let remoteState = PlayerContinueViewingState(
            entries: [
                PlayerContinueViewingEntry(
                    collectionId: collectionId,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 300)
                )
            ]
        )

        let result = PlayerViewingProgressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteState)
        )

        XCTAssertEqual(result, .localChanged)
        XCTAssertEqual(continueViewingCollectionIds(), [collectionId])
    }

    func testContinueViewingStateCapsRemovedEntriesAtTwentyCollections() throws {
        let entries = (0..<25).map { index in
            PlayerContinueViewingEntry(
                collectionId: "collection-\(index)",
                updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
                isRemoved: true
            )
        }
        writeContinueViewing(PlayerContinueViewingState(entries: entries))

        let data = try XCTUnwrap(PlayerViewingProgressStore.syncedContinueViewingStateData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)

        XCTAssertNil(state.collectionId)
        XCTAssertEqual(state.entries.count, 20)
        XCTAssertEqual(
            state.entries.map(\.collectionId),
            Array((5...24).reversed()).map { "collection-\($0)" }
        )
        XCTAssertTrue(state.entries.allSatisfy(\.isRemoved))
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
        let state = try syncedContinueViewingState()
        XCTAssertNil(state.collectionId)
    }

    private func syncedContinueViewingState(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> PlayerContinueViewingState {
        let data = try XCTUnwrap(
            PlayerViewingProgressStore.syncedContinueViewingStateData,
            file: file,
            line: line
        )
        return try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
    }

    private func continueViewingCollectionIds() -> [String] {
        PlayerViewingProgressStore.progressSnapshot()
            .recentContinueViewingProgresses
            .map(\.collectionId)
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

    private func writeLegacyContinueViewing(collectionId: String?, updatedAt: Date) {
        UserDefaults.standard.set(
            try! JSONEncoder().encode(
                LegacyContinueViewingState(collectionId: collectionId, updatedAt: updatedAt)
            ),
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
