// ∅ 2026 lil org

import XCTest
@testable import NftPlayerSyncCore

final class PlayerSyncMergeTests: XCTestCase {

    private let userDefaultsSuiteName = "PlayerSyncMergeTests-\(UUID().uuidString)"
    private var userDefaults: UserDefaults { UserDefaults(suiteName: userDefaultsSuiteName)! }
    private lazy var progressStore = PlayerViewingProgressStore(
        userDefaults: UserDefaults(suiteName: userDefaultsSuiteName)!
    )
    private lazy var bookmarksStore = PlayerBookmarksStore(
        userDefaults: UserDefaults(suiteName: userDefaultsSuiteName)!
    )

    override func setUp() async throws {
        try await super.setUp()
        PlayerSyncLogicalClock.resetForTesting()
        await resetStores()
    }

    override func tearDown() async throws {
        await resetStores()
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        try await super.tearDown()
    }

    func testLogicalClockKeepsBookmarksSeparateFromViewingActivity() {
        let observedTimestamp = Date().addingTimeInterval(3_600)
        PlayerSyncLogicalClock.observe(observedTimestamp, for: .bookmarks)

        let viewingTimestamp = PlayerSyncLogicalClock.next(for: .viewingProgress)
        let bookmarkTimestamp = PlayerSyncLogicalClock.next(for: .bookmarks)

        XCTAssertLessThan(viewingTimestamp, observedTimestamp)
        XCTAssertGreaterThan(bookmarkTimestamp, observedTimestamp)
    }

    func testLogicalClockSharesProgressAndContinueViewingOrdering() {
        let observedTimestamp = Date().addingTimeInterval(3_600)
        PlayerSyncLogicalClock.observe(observedTimestamp, for: .viewingProgress)

        let continueViewingTimestamp = PlayerSyncLogicalClock.next(for: .continueViewingState)
        let explicitTimestamp = continueViewingTimestamp.addingTimeInterval(3_600)
        let progressTimestamp = PlayerSyncLogicalClock.next(
            for: .viewingProgress,
            after: explicitTimestamp
        )

        XCTAssertGreaterThan(continueViewingTimestamp, observedTimestamp)
        XCTAssertGreaterThan(progressTimestamp, explicitTimestamp)
    }

    func testLogicalClockBoundsImplausibleFutureTimestamps() {
        let implausibleTimestamp = Date().addingTimeInterval(365 * 24 * 60 * 60)
        PlayerSyncLogicalClock.observe(implausibleTimestamp, for: .viewingProgress)

        let observedTimestamp = PlayerSyncLogicalClock.next(for: .continueViewingState)
        let explicitTimestamp = PlayerSyncLogicalClock.next(
            for: .bookmarks,
            after: implausibleTimestamp
        )
        XCTAssertLessThan(observedTimestamp, implausibleTimestamp)
        XCTAssertLessThan(explicitTimestamp, implausibleTimestamp)
        XCTAssertLessThan(abs(observedTimestamp.timeIntervalSinceNow), 5)
        XCTAssertLessThan(abs(explicitTimestamp.timeIntervalSinceNow), 5)
    }

    func testProgressSnapshotReturnsProgressAndObservesContinueViewingTimestamp() async {
        let collectionId = "collection"
        let savedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let futureTimestamp = PlayerSyncLogicalClock.next(
            for: .continueViewingState
        ).addingTimeInterval(3_600)
        writeProgress([collectionId: savedProgress])
        writeContinueViewing(
            PlayerContinueViewingState(entries: [], updatedAt: futureTimestamp)
        )

        let snapshot = await progressStore.progressSnapshot()
        let nextTimestamp = PlayerSyncLogicalClock.next(for: .viewingProgress)

        XCTAssertEqual(snapshot.progress(collectionId: collectionId), savedProgress)
        XCTAssertGreaterThan(nextTimestamp, futureTimestamp)
    }

    func testProgressMergeKeepsNewerLocalProgressOverStaleRemoteForwardProgress() async throws {
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

        let result = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: olderRemoteProgress])
        )

        XCTAssertEqual(result, .remoteWasStale)
        let savedTokenIndex = await progressStore.progress(collectionId: collectionId)?.tokenIndex
        XCTAssertEqual(savedTokenIndex, 2)
    }

    func testProgressMergeAppliesNewerRemoteProgressEvenWhenItMovesBackward() async throws {
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

        let result = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: newerRemoteProgress])
        )

        XCTAssertEqual(result, .localChanged)
        let savedTokenIndex = await progressStore.progress(collectionId: collectionId)?.tokenIndex
        XCTAssertEqual(savedTokenIndex, 2)
    }

    func testProgressMergeUsesFurthestProgressWhenTimestampsMatch() async throws {
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

        let result = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: remoteProgress])
        )

        XCTAssertEqual(result, .localChanged)
        let savedTokenIndex = await progressStore.progress(collectionId: collectionId)?.tokenIndex
        XCTAssertEqual(savedTokenIndex, 6)
    }

    func testProgressMergeKeepsViewedToEndStateWhileUsingLatestStopPosition() async throws {
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

        _ = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: remoteProgress])
        )

        let savedProgress = await progressStore.progress(collectionId: collectionId)
        let mergedProgress = try XCTUnwrap(savedProgress)
        XCTAssertEqual(mergedProgress.tokenIndex, 2)
        let snapshot = await progressStore.progressSnapshot()
        XCTAssertEqual(
            snapshot.viewedToEndCollectionIds,
            [collectionId]
        )
    }

    func testProgressSaveKeepsNewerStoredProgressOverStaleSave() async throws {
        let collectionId = "collection"
        let newerProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let staleProgress = progress(
            collectionId: collectionId,
            tokenId: "token-6",
            tokenIndex: 6,
            updatedAt: Date(timeIntervalSinceReferenceDate: 200),
            hasViewedToEnd: true
        )

        _ = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: newerProgress])
        )
        await progressStore.save(staleProgress)

        let storedProgress = await progressStore.progress(collectionId: collectionId)
        let savedProgress = try XCTUnwrap(storedProgress)
        XCTAssertEqual(savedProgress.tokenId, "token-2")
        XCTAssertEqual(savedProgress.updatedAt, newerProgress.updatedAt)
        XCTAssertTrue(savedProgress.hasViewedToEnd)
    }

    func testProgressSaveRejectsUnchangedStaleSave() async throws {
        let collectionId = "collection"
        let newerProgress = progress(
            collectionId: collectionId,
            tokenId: "token-4",
            tokenIndex: 4,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        _ = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: newerProgress])
        )

        let didSave = await progressStore.save(
            progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        XCTAssertFalse(didSave)
        let storedProgress = await progressStore.progress(collectionId: collectionId)
        XCTAssertEqual(storedProgress, newerProgress)
    }

    func testFreshProgressAdvancesPastFutureSyncedTimestamp() async throws {
        let collectionId = "collection"
        let futureTimestamp = PlayerSyncLogicalClock.next(
            for: .viewingProgress
        ).addingTimeInterval(3_600)
        let remoteProgress = progress(
            collectionId: collectionId,
            tokenId: "token-8",
            tokenIndex: 8,
            updatedAt: futureTimestamp,
            hasViewedToEnd: true
        )
        _ = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: remoteProgress])
        )

        let localProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        await progressStore.save(localProgress)

        let storedProgress = await progressStore.progress(collectionId: collectionId)
        let savedProgress = try XCTUnwrap(storedProgress)
        XCTAssertEqual(savedProgress.tokenId, localProgress.tokenId)
        XCTAssertGreaterThan(savedProgress.updatedAt, futureTimestamp)
        XCTAssertTrue(savedProgress.hasViewedToEnd)
    }

    func testFreshProgressRebasesImplausiblyFutureStoredTimestamp() async throws {
        let collectionId = "collection"
        let futureTimestamp = Date().addingTimeInterval(365 * 24 * 60 * 60)
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "token-8",
                tokenIndex: 8,
                updatedAt: futureTimestamp
            )
        ])
        _ = await progressStore.progress(collectionId: collectionId)

        let localProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        let didSave = await progressStore.save(localProgress)

        let savedProgress = await progressStore.progress(collectionId: collectionId)
        let storedProgress = try XCTUnwrap(savedProgress)
        XCTAssertTrue(didSave)
        XCTAssertEqual(storedProgress.tokenId, localProgress.tokenId)
        XCTAssertLessThan(storedProgress.updatedAt, futureTimestamp)
        XCTAssertLessThan(abs(storedProgress.updatedAt.timeIntervalSinceNow), 5)
    }

    func testProgressMergeFiltersInvalidRemoteEntryAndKeepsValidRemoteEntry() async throws {
        let now = Date()
        let localCollectionId = "local"
        let remoteCollectionId = "remote"
        let localProgress = progress(
            collectionId: localCollectionId,
            tokenId: "local-token",
            tokenIndex: 2,
            updatedAt: now.addingTimeInterval(-100)
        )
        let invalidRemoteProgress = progress(
            collectionId: localCollectionId,
            tokenId: "invalid-remote-token",
            tokenIndex: 8,
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60)
        )
        let validRemoteProgress = progress(
            collectionId: remoteCollectionId,
            tokenId: "valid-remote-token",
            tokenIndex: 4,
            updatedAt: now.addingTimeInterval(-50)
        )
        writeProgress([localCollectionId: localProgress])

        let result = await progressStore.mergeSyncedProgressData(
            try encodedProgress([
                localCollectionId: invalidRemoteProgress,
                remoteCollectionId: validRemoteProgress,
            ])
        )

        XCTAssertEqual(result, .remoteWasPartiallyUntrusted)
        XCTAssertTrue(result.shouldMirrorLocalValue)
        XCTAssertFalse(result.blocksConflictingUpload)
        let storedLocalProgress = await progressStore.progress(
            collectionId: localCollectionId
        )
        let storedRemoteProgress = await progressStore.progress(
            collectionId: remoteCollectionId
        )
        XCTAssertEqual(storedLocalProgress, localProgress)
        XCTAssertEqual(storedRemoteProgress, validRemoteProgress)
        let encodedSyncedProgress = await progressStore.syncedProgressData
        let syncedData = try XCTUnwrap(encodedSyncedProgress)
        let syncedProgress = try JSONDecoder().decode(
            [String: PlayerViewingProgress].self,
            from: syncedData
        )
        XCTAssertEqual(syncedProgress[localCollectionId], invalidRemoteProgress)
        XCTAssertEqual(syncedProgress[remoteCollectionId], validRemoteProgress)
    }

    func testInvalidOnlyRemoteProgressIsQuarantined() async throws {
        let invalidRemoteProgress = progress(
            collectionId: "collection",
            tokenId: "token",
            tokenIndex: 8,
            updatedAt: Date().addingTimeInterval(365 * 24 * 60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }

        let result = await progressStore.mergeSyncedProgressData(
            try encodedProgress(["collection": invalidRemoteProgress])
        )
        let syncedData = await progressStore.syncedProgressData
        let data = try XCTUnwrap(syncedData)
        let syncedProgress = try JSONDecoder().decode(
            [String: PlayerViewingProgress].self,
            from: data
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertFalse(result.shouldMirrorLocalValue)
        XCTAssertEqual(syncedProgress["collection"], invalidRemoteProgress)

        _ = await progressStore.mergeSyncedProgressData(try encodedProgress([:]))
        let releasedProgressData = await progressStore.syncedProgressData
        XCTAssertNil(releasedProgressData)

        _ = await progressStore.mergeSyncedProgressData(
            try encodedProgress(["collection": invalidRemoteProgress])
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(
            invalidRemoteProgress.updatedAt
        )
        let agedResult = await progressStore.mergeSyncedProgressData(
            try encodedProgress(["collection": invalidRemoteProgress])
        )
        let agedProgress = await progressStore.progress(collectionId: "collection")
        XCTAssertEqual(agedResult, .localChanged)
        XCTAssertEqual(agedProgress, invalidRemoteProgress)
    }

    func testQuarantinedProgressPreservesValidSiblingSync() async throws {
        let sourceSuiteName = "PlayerSyncMergeSource-\(UUID().uuidString)"
        let sourceStore = PlayerViewingProgressStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: sourceSuiteName))
        )
        let actualNow = Date()
        let fastNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let rejectedProgress = progress(
            collectionId: "rejected",
            tokenId: "rejected-token",
            tokenIndex: 8,
            updatedAt: fastNow
        )
        let validProgress = progress(
            collectionId: "valid",
            tokenId: "valid-token",
            tokenIndex: 4,
            updatedAt: actualNow
        )
        defer {
            PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil)
            UserDefaults(suiteName: sourceSuiteName)?
                .removePersistentDomain(forName: sourceSuiteName)
        }

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(fastNow)
        _ = await sourceStore.save(rejectedProgress)
        let encodedInitialSource = await sourceStore.syncedProgressData
        let initialSourceData = try XCTUnwrap(encodedInitialSource)

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        _ = await progressStore.save(validProgress)
        let destinationResult = await progressStore.mergeSyncedProgressData(
            initialSourceData
        )
        let encodedDestination = await progressStore.syncedProgressData
        let destinationData = try XCTUnwrap(encodedDestination)

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(fastNow)
        let sourceResult = await sourceStore.mergeSyncedProgressData(destinationData)
        let encodedSource = await sourceStore.syncedProgressData
        let sourceData = try XCTUnwrap(encodedSource)

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        let repeatedDestinationResult = await progressStore.mergeSyncedProgressData(
            sourceData
        )
        let encodedRepeatedDestination = await progressStore.syncedProgressData
        let repeatedDestinationData = try XCTUnwrap(encodedRepeatedDestination)

        XCTAssertEqual(destinationResult, .remoteWasStale)
        XCTAssertTrue(destinationResult.shouldMirrorLocalValue)
        XCTAssertEqual(sourceResult, .localChanged)
        XCTAssertEqual(repeatedDestinationResult, .ignored)
        XCTAssertEqual(
            try JSONDecoder().decode([String: PlayerViewingProgress].self, from: sourceData),
            try JSONDecoder().decode(
                [String: PlayerViewingProgress].self,
                from: repeatedDestinationData
            )
        )
    }

    func testQuarantinedProgressKeepsSameKeyUpdatePending() async throws {
        let now = Date()
        let localProgress = progress(
            collectionId: "collection",
            tokenId: "local-token",
            tokenIndex: 2,
            updatedAt: now
        )
        let rejectedProgress = progress(
            collectionId: "collection",
            tokenId: "remote-token",
            tokenIndex: 8,
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        _ = await progressStore.save(localProgress)

        let result = await progressStore.mergeSyncedProgressData(
            try encodedProgress(["collection": rejectedProgress])
        )
        let restartedStore = PlayerViewingProgressStore(
            userDefaults: UserDefaults(suiteName: userDefaultsSuiteName)!
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(rejectedProgress.updatedAt)
        let repeatedResult = await restartedStore.mergeSyncedProgressData(
            try encodedProgress(["collection": rejectedProgress])
        )
        let storedProgress = await restartedStore.progress(collectionId: "collection")
        let encodedProgress = await restartedStore.syncedProgressData
        let data = try XCTUnwrap(encodedProgress)
        let outboundProgress = try JSONDecoder().decode(
            [String: PlayerViewingProgress].self,
            from: data
        )

        XCTAssertEqual(result, .remoteWasPartiallyUntrusted)
        XCTAssertTrue(result.shouldMirrorLocalValue)
        XCTAssertFalse(result.blocksConflictingUpload)
        XCTAssertEqual(repeatedResult, .remoteWasPartiallyUntrusted)
        XCTAssertEqual(storedProgress, localProgress)
        XCTAssertEqual(outboundProgress["collection"], rejectedProgress)
    }

    func testValidRemoteProgressBeatsImplausiblyFutureLocalProgress() async throws {
        let now = Date()
        let collectionId = "collection"
        let invalidLocalProgress = progress(
            collectionId: collectionId,
            tokenId: "local-token",
            tokenIndex: 2,
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60)
        )
        let validRemoteProgress = progress(
            collectionId: collectionId,
            tokenId: "remote-token",
            tokenIndex: 6,
            updatedAt: now.addingTimeInterval(60 * 60)
        )
        writeProgress([collectionId: invalidLocalProgress])

        let result = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: validRemoteProgress])
        )

        XCTAssertEqual(result, .localChanged)
        let storedProgress = await progressStore.progress(collectionId: collectionId)
        XCTAssertEqual(storedProgress, validRemoteProgress)
    }

    func testCachedProgressCanUpdateAfterClockCorrection() async throws {
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let collectionId = "collection"
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "cached-token",
                tokenIndex: 8,
                updatedAt: incorrectNow
            )
        ])
        _ = await progressStore.progress(collectionId: collectionId)

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        let updatedProgress = progress(
            collectionId: collectionId,
            tokenId: "updated-token",
            tokenIndex: 2,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        let didSave = await progressStore.save(updatedProgress)

        XCTAssertTrue(didSave)
        let storedProgress = await progressStore.progress(collectionId: collectionId)
        XCTAssertEqual(storedProgress?.tokenId, updatedProgress.tokenId)
    }

    func testDelayedProgressEventNormalizesAfterClockCorrection() async throws {
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let collectionId = "collection"
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)
        let delayedProgress = progress(
            collectionId: collectionId,
            tokenId: "token",
            tokenIndex: 2,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        let didSave = await progressStore.save(delayedProgress)

        let storedProgress = await progressStore.progress(collectionId: collectionId)
        XCTAssertTrue(didSave)
        let updatedAt = try XCTUnwrap(storedProgress?.updatedAt)
        XCTAssertGreaterThanOrEqual(updatedAt, actualNow)
        XCTAssertLessThan(updatedAt, actualNow.addingTimeInterval(1))
    }

    func testDelayedProgressEventAdvancesPastPlausibleFutureState() async throws {
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let collectionId = "collection"
        let existingProgress = progress(
            collectionId: collectionId,
            tokenId: "existing-token",
            tokenIndex: 2,
            updatedAt: actualNow.addingTimeInterval(60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)
        let delayedProgress = progress(
            collectionId: collectionId,
            tokenId: "delayed-token",
            tokenIndex: 4,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        writeProgress([collectionId: existingProgress])

        let didSave = await progressStore.save(delayedProgress)

        let savedProgress = await progressStore.progress(collectionId: collectionId)
        let storedProgress = try XCTUnwrap(savedProgress)
        XCTAssertTrue(didSave)
        XCTAssertEqual(storedProgress.tokenId, delayedProgress.tokenId)
        XCTAssertGreaterThan(storedProgress.updatedAt, existingProgress.updatedAt)
    }

    func testBookmarkMergeKeepsNewerLocalDeleteOverStaleRemoteActiveBookmark() async throws {
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

        let result = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([collectionId: [tokenId: remoteActiveBookmark]])
        )

        XCTAssertEqual(result, .remoteWasStale)
        let isBookmarked = await bookmarksStore.isBookmarked(collectionId: collectionId, tokenId: tokenId)
        XCTAssertFalse(isBookmarked)
    }

    func testBookmarkMergeUsesActiveRecordWhenTimestampsMatch() async throws {
        let collectionId = "collection"
        let tokenId = "token"
        let updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        let localDeletedBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: updatedAt,
            isDeleted: true
        )
        let remoteActiveBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: updatedAt
        )
        writeBookmarks([collectionId: [tokenId: localDeletedBookmark]])

        _ = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([collectionId: [tokenId: remoteActiveBookmark]])
        )

        let isBookmarked = await bookmarksStore.isBookmarked(
            collectionId: collectionId,
            tokenId: tokenId
        )
        XCTAssertTrue(isBookmarked)
    }

    func testBookmarkMergeRestoresNewerRemoteActiveBookmarkAfterLocalDelete() async throws {
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

        let result = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([collectionId: [tokenId: remoteActiveBookmark]])
        )

        XCTAssertEqual(result, .localChanged)
        let isBookmarked = await bookmarksStore.isBookmarked(collectionId: collectionId, tokenId: tokenId)
        XCTAssertTrue(isBookmarked)
    }

    func testBookmarkPresentationClearsPreviousTokenWhileNextTokenLoads() throws {
        let firstTarget = PlayerBookmarkPresentationState.Target(
            collectionId: "collection",
            tokenId: "first"
        )
        let secondTarget = PlayerBookmarkPresentationState.Target(
            collectionId: "collection",
            tokenId: "second"
        )
        var state = PlayerBookmarkPresentationState()
        let firstRequest = try XCTUnwrap(
            state.beginLoading(
                target: firstTarget,
                storedState: PlayerStoredBookmarkState(
                    isBookmarked: true,
                    isTogglePending: false,
                    isReady: true
                )
            )
        )

        _ = state.beginLoading(
            target: secondTarget,
            storedState: PlayerStoredBookmarkState(
                isBookmarked: false,
                isTogglePending: false,
                isReady: false
            )
        )

        XCTAssertFalse(state.isBookmarked)
        XCTAssertFalse(state.isReady)
        XCTAssertFalse(state.canToggle)
        XCTAssertFalse(
            state.applyLoadedState(
                isBookmarked: true,
                for: firstRequest
            )
        )
        XCTAssertEqual(state.target, secondTarget)
        XCTAssertFalse(state.isBookmarked)
    }

    func testBookmarkPresentationRejectsDuplicateToggleUntilCompletion() throws {
        let target = PlayerBookmarkPresentationState.Target(
            collectionId: "collection",
            tokenId: "token"
        )
        var state = PlayerBookmarkPresentationState()
        _ = state.beginLoading(
            target: target,
            storedState: PlayerStoredBookmarkState(
                isBookmarked: false,
                isTogglePending: false,
                isReady: true
            )
        )

        let request = try XCTUnwrap(state.beginToggle())
        XCTAssertEqual(request.target, target)
        XCTAssertTrue(request.isBookmarked)
        XCTAssertTrue(state.isTogglePending)
        XCTAssertFalse(state.canToggle)
        XCTAssertNil(state.beginToggle())
        XCTAssertTrue(
            state.applyToggleCompletion(
                isBookmarked: true,
                for: target,
                isTogglePending: false
            )
        )
        XCTAssertTrue(state.isBookmarked)
        XCTAssertFalse(state.isTogglePending)
        XCTAssertTrue(state.canToggle)
    }

    func testBookmarkToggleAdmissionRejectsConcurrentDuplicate() async {
        await PlayerBookmarksStore.shared.resetForTesting()
        let target = PlayerBookmarkPresentationState.Target(
            collectionId: "collection",
            tokenId: "token"
        )

        let admission = await MainActor.run {
            let first = PlayerBookmarksStore.enqueueBookmarkUpdate(
                collectionId: target.collectionId,
                tokenId: target.tokenId,
                isBookmarked: true
            )
            let pendingState = PlayerBookmarksStore.storedBookmarkState(
                collectionId: target.collectionId,
                tokenId: target.tokenId
            )
            let second = PlayerBookmarksStore.enqueueBookmarkUpdate(
                collectionId: target.collectionId,
                tokenId: target.tokenId,
                isBookmarked: true
            )
            return (first, second, pendingState)
        }

        XCTAssertTrue(admission.0)
        XCTAssertFalse(admission.1)
        XCTAssertTrue(admission.2.isTogglePending)
        var secondPresentation = PlayerBookmarkPresentationState()
        _ = secondPresentation.beginLoading(
            target: target,
            storedState: admission.2
        )
        XCTAssertFalse(secondPresentation.canToggle)

        await PlayerPersistenceUpdates.flush()
        let finalState = PlayerBookmarksStore.storedBookmarkState(
            collectionId: target.collectionId,
            tokenId: target.tokenId
        )
        XCTAssertTrue(finalState.isBookmarked)
        XCTAssertFalse(finalState.isTogglePending)
        await PlayerBookmarksStore.shared.resetForTesting()
    }

    func testQueuedBookmarkTogglePreservesIntentAcrossInterveningMerge() async throws {
        await PlayerPersistenceUpdates.flush()
        await PlayerBookmarksStore.shared.resetForTesting()
        let gate = PlayerSyncTestGate()
        let completion = await MainActor.run { BookmarkToggleCompletionRecorder() }
        let collectionId = "collection"
        let tokenId = "token"

        let admitted = await MainActor.run {
            PlayerPersistenceUpdates.enqueue {
                await gate.wait()
            }
            return PlayerBookmarksStore.enqueueBookmarkUpdate(
                collectionId: collectionId,
                tokenId: tokenId,
                isBookmarked: true
            ) { isBookmarked in
                completion.value = isBookmarked
            }
        }
        XCTAssertTrue(admitted)

        let remoteBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        _ = await PlayerBookmarksStore.shared.mergeSyncedBookmarksData(
            try encodedBookmarks([collectionId: [tokenId: remoteBookmark]])
        )

        await gate.open()
        await PlayerPersistenceUpdates.flush()

        let isBookmarked = await PlayerBookmarksStore.shared.isBookmarked(
            collectionId: collectionId,
            tokenId: tokenId
        )
        let completedState = await MainActor.run { completion.value }
        XCTAssertTrue(isBookmarked)
        XCTAssertEqual(completedState, true)
        await PlayerBookmarksStore.shared.resetForTesting()
    }

    func testBookmarkUpdateUsesPresentedIntentAfterInterveningMerge() async throws {
        await PlayerPersistenceUpdates.flush()
        await PlayerBookmarksStore.shared.resetForTesting()
        let collectionId = "collection"
        let tokenId = "token"
        let target = PlayerBookmarkPresentationState.Target(
            collectionId: collectionId,
            tokenId: tokenId
        )
        var presentationState = PlayerBookmarkPresentationState()
        _ = presentationState.beginLoading(
            target: target,
            storedState: PlayerStoredBookmarkState(
                isBookmarked: false,
                isTogglePending: false,
                isReady: true
            )
        )
        _ = await PlayerBookmarksStore.shared.mergeSyncedBookmarksData(
            try encodedBookmarks([
                collectionId: [
                    tokenId: PlayerBookmark(
                        bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100)
                    ),
                ],
            ])
        )

        let request = try XCTUnwrap(presentationState.beginToggle())
        let admitted = await MainActor.run {
            PlayerBookmarksStore.enqueueBookmarkUpdate(
                collectionId: request.target.collectionId,
                tokenId: request.target.tokenId,
                isBookmarked: request.isBookmarked
            )
        }
        await PlayerPersistenceUpdates.flush()
        let isBookmarked = await PlayerBookmarksStore.shared.isBookmarked(
            collectionId: collectionId,
            tokenId: tokenId
        )

        XCTAssertTrue(admitted)
        XCTAssertTrue(request.isBookmarked)
        XCTAssertTrue(isBookmarked)
        await PlayerBookmarksStore.shared.resetForTesting()
    }

    func testBookmarkToggleAdvancesPastFutureStoredTimestamp() async throws {
        await PlayerPersistenceUpdates.flush()
        await PlayerBookmarksStore.shared.resetForTesting()
        let collectionId = "collection"
        let tokenId = "token"
        let futureDate = PlayerSyncLogicalClock.next(for: .bookmarks).addingTimeInterval(3_600)
        let futureBookmark = PlayerBookmark(
            bookmarkedAt: futureDate,
            updatedAt: futureDate
        )
        _ = await PlayerBookmarksStore.shared.mergeSyncedBookmarksData(
            try encodedBookmarks([collectionId: [tokenId: futureBookmark]])
        )

        let admitted = await MainActor.run {
            PlayerBookmarksStore.enqueueBookmarkUpdate(
                collectionId: collectionId,
                tokenId: tokenId,
                isBookmarked: false
            )
        }
        XCTAssertTrue(admitted)
        await PlayerPersistenceUpdates.flush()

        let isBookmarked = await PlayerBookmarksStore.shared.isBookmarked(
            collectionId: collectionId,
            tokenId: tokenId
        )
        let syncedData = await PlayerBookmarksStore.shared.syncedBookmarksData
        let data = try XCTUnwrap(syncedData)
        let bookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: data
        )
        XCTAssertFalse(isBookmarked)
        XCTAssertGreaterThan(
            try XCTUnwrap(bookmarks[collectionId]?[tokenId]?.updatedAt),
            futureDate
        )
        await PlayerBookmarksStore.shared.resetForTesting()
    }

    func testBookmarkToggleRebasesImplausiblyFutureStoredTimestamp() async throws {
        let collectionId = "collection"
        let tokenId = "token"
        let futureTimestamp = Date().addingTimeInterval(365 * 24 * 60 * 60)
        writeBookmarks([
            collectionId: [
                tokenId: PlayerBookmark(
                    bookmarkedAt: futureTimestamp,
                    updatedAt: futureTimestamp
                )
            ]
        ])
        let initialIsBookmarked = await bookmarksStore.isBookmarked(
            collectionId: collectionId,
            tokenId: tokenId
        )
        XCTAssertTrue(initialIsBookmarked)

        let isBookmarked = await bookmarksStore.toggleBookmark(
            collectionId: collectionId,
            tokenId: tokenId
        )
        let encodedBookmarks = await bookmarksStore.syncedBookmarksData
        let syncedData = try XCTUnwrap(encodedBookmarks)
        let bookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: syncedData
        )
        let updatedBookmark = try XCTUnwrap(bookmarks[collectionId]?[tokenId])
        XCTAssertFalse(isBookmarked)
        XCTAssertTrue(updatedBookmark.isDeleted)
        XCTAssertLessThan(updatedBookmark.updatedAt, futureTimestamp)
        XCTAssertLessThan(abs(updatedBookmark.updatedAt.timeIntervalSinceNow), 5)
    }

    func testBookmarkMergeFiltersInvalidRemoteRecordAndKeepsValidRemoteRecord() async throws {
        let now = Date()
        let localCollectionId = "local"
        let remoteCollectionId = "remote"
        let localTokenId = "local-token"
        let remoteTokenId = "remote-token"
        let localBookmark = PlayerBookmark(
            bookmarkedAt: now.addingTimeInterval(-100)
        )
        let invalidRemoteBookmark = PlayerBookmark(
            bookmarkedAt: now.addingTimeInterval(365 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60),
            isDeleted: true
        )
        let validRemoteBookmark = PlayerBookmark(
            bookmarkedAt: now.addingTimeInterval(-50)
        )
        writeBookmarks([
            localCollectionId: [localTokenId: localBookmark],
        ])

        let result = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([
                localCollectionId: [localTokenId: invalidRemoteBookmark],
                remoteCollectionId: [remoteTokenId: validRemoteBookmark],
            ])
        )

        XCTAssertEqual(result, .remoteWasPartiallyUntrusted)
        XCTAssertTrue(result.shouldMirrorLocalValue)
        XCTAssertFalse(result.blocksConflictingUpload)
        let isLocalBookmarked = await bookmarksStore.isBookmarked(
            collectionId: localCollectionId,
            tokenId: localTokenId
        )
        let isRemoteBookmarked = await bookmarksStore.isBookmarked(
            collectionId: remoteCollectionId,
            tokenId: remoteTokenId
        )
        XCTAssertTrue(isLocalBookmarked)
        XCTAssertTrue(isRemoteBookmarked)
        let encodedSyncedBookmarks = await bookmarksStore.syncedBookmarksData
        let syncedData = try XCTUnwrap(encodedSyncedBookmarks)
        let syncedBookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: syncedData
        )
        XCTAssertEqual(
            syncedBookmarks[localCollectionId]?[localTokenId],
            invalidRemoteBookmark
        )
        XCTAssertEqual(
            syncedBookmarks[remoteCollectionId]?[remoteTokenId],
            validRemoteBookmark
        )
    }

    func testInvalidOnlyRemoteBookmarksAreQuarantined() async throws {
        let futureTimestamp = Date().addingTimeInterval(365 * 24 * 60 * 60)
        let invalidRemoteBookmark = PlayerBookmark(
            bookmarkedAt: futureTimestamp,
            updatedAt: futureTimestamp
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }

        let result = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks(["collection": ["token": invalidRemoteBookmark]])
        )
        let syncedData = await bookmarksStore.syncedBookmarksData
        let data = try XCTUnwrap(syncedData)
        let syncedBookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: data
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertFalse(result.shouldMirrorLocalValue)
        XCTAssertEqual(
            syncedBookmarks["collection"]?["token"],
            invalidRemoteBookmark
        )

        _ = await bookmarksStore.mergeSyncedBookmarksData(try encodedBookmarks([:]))
        let releasedBookmarkData = await bookmarksStore.syncedBookmarksData
        XCTAssertNil(releasedBookmarkData)

        _ = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks(["collection": ["token": invalidRemoteBookmark]])
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(futureTimestamp)
        let agedResult = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks(["collection": ["token": invalidRemoteBookmark]])
        )
        let agedIsBookmarked = await bookmarksStore.isBookmarked(
            collectionId: "collection",
            tokenId: "token"
        )
        XCTAssertEqual(agedResult, .localChanged)
        XCTAssertTrue(agedIsBookmarked)
    }

    func testQuarantinedBookmarkKeepsSameKeyTogglePending() async throws {
        let futureTimestamp = Date().addingTimeInterval(365 * 24 * 60 * 60)
        let rejectedBookmark = PlayerBookmark(
            bookmarkedAt: futureTimestamp,
            updatedAt: futureTimestamp
        )
        let remoteData = try encodedBookmarks([
            "collection": ["token": rejectedBookmark],
        ])
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        _ = await bookmarksStore.mergeSyncedBookmarksData(remoteData)
        let isBookmarked = await bookmarksStore.toggleBookmark(
            collectionId: "collection",
            tokenId: "token"
        )

        let result = await bookmarksStore.mergeSyncedBookmarksData(remoteData)
        let restartedStore = PlayerBookmarksStore(
            userDefaults: UserDefaults(suiteName: userDefaultsSuiteName)!
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(futureTimestamp)
        let repeatedResult = await restartedStore.mergeSyncedBookmarksData(remoteData)
        let encodedBookmarks = await restartedStore.syncedBookmarksData
        let data = try XCTUnwrap(encodedBookmarks)
        let outboundBookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: data
        )

        XCTAssertTrue(isBookmarked)
        XCTAssertEqual(result, .remoteWasPartiallyUntrusted)
        XCTAssertTrue(result.shouldMirrorLocalValue)
        XCTAssertFalse(result.blocksConflictingUpload)
        XCTAssertEqual(repeatedResult, .remoteWasPartiallyUntrusted)
        XCTAssertEqual(outboundBookmarks["collection"]?["token"], rejectedBookmark)
    }

    func testBookmarkMergeAcceptsDeletionWithInvalidBookmarkedAt() async throws {
        let now = Date()
        let collectionId = "collection"
        let tokenId = "token"
        let remoteUpdatedAt = now.addingTimeInterval(-10)
        writeBookmarks([
            collectionId: [
                tokenId: PlayerBookmark(
                    bookmarkedAt: now.addingTimeInterval(-100),
                    updatedAt: now.addingTimeInterval(-50)
                ),
            ],
        ])

        let result = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([
                collectionId: [
                    tokenId: PlayerBookmark(
                        bookmarkedAt: now.addingTimeInterval(365 * 24 * 60 * 60),
                        updatedAt: remoteUpdatedAt,
                        isDeleted: true
                    ),
                ],
            ])
        )

        let syncedData = await bookmarksStore.syncedBookmarksData
        let data = try XCTUnwrap(syncedData)
        let bookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: data
        )
        let bookmark = try XCTUnwrap(bookmarks[collectionId]?[tokenId])
        XCTAssertEqual(result, .localChanged)
        XCTAssertTrue(result.shouldMirrorLocalValue)
        XCTAssertTrue(bookmark.isDeleted)
        XCTAssertEqual(bookmark.updatedAt, remoteUpdatedAt)
        XCTAssertEqual(
            bookmark.bookmarkedAt,
            PlayerSyncTimestampPolicy.invalidLocalTimestamp
        )
    }

    func testBookmarkMergeAcceptsActiveRecordWithInvalidBookmarkedAt() async throws {
        let now = Date()
        let remoteUpdatedAt = now.addingTimeInterval(-10)
        let result = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([
                "collection": [
                    "token": PlayerBookmark(
                        bookmarkedAt: now.addingTimeInterval(365 * 24 * 60 * 60),
                        updatedAt: remoteUpdatedAt
                    ),
                ],
            ])
        )

        let encodedBookmarks = await bookmarksStore.syncedBookmarksData
        let data = try XCTUnwrap(encodedBookmarks)
        let bookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: data
        )
        let bookmark = try XCTUnwrap(bookmarks["collection"]?["token"])
        XCTAssertEqual(result, .localChanged)
        XCTAssertFalse(bookmark.isDeleted)
        XCTAssertEqual(bookmark.updatedAt, remoteUpdatedAt)
        XCTAssertEqual(
            bookmark.bookmarkedAt,
            PlayerSyncTimestampPolicy.invalidLocalTimestamp
        )
    }

    func testBookmarkLogicalClockIgnoresHistoricalBookmarkDate() async throws {
        let now = Date()
        let futureBookmarkedAt = now.addingTimeInterval(60 * 60)
        _ = await bookmarksStore.mergeSyncedBookmarksData(
            try encodedBookmarks([
                "collection": [
                    "token": PlayerBookmark(
                        bookmarkedAt: futureBookmarkedAt,
                        updatedAt: now.addingTimeInterval(-60)
                    ),
                ],
            ])
        )

        let nextTimestamp = PlayerSyncLogicalClock.next(for: .bookmarks)

        XCTAssertLessThan(nextTimestamp, futureBookmarkedAt)
    }

    func testCachedBookmarkCanToggleAfterClockCorrection() async throws {
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let collectionId = "collection"
        let tokenId = "token"
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)
        writeBookmarks([
            collectionId: [
                tokenId: PlayerBookmark(
                    bookmarkedAt: incorrectNow,
                    updatedAt: incorrectNow
                ),
            ],
        ])
        let initialIsBookmarked = await bookmarksStore.isBookmarked(
            collectionId: collectionId,
            tokenId: tokenId
        )
        XCTAssertTrue(initialIsBookmarked)

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        let isBookmarked = await bookmarksStore.toggleBookmark(
            collectionId: collectionId,
            tokenId: tokenId
        )

        XCTAssertFalse(isBookmarked)
    }

    func testQueuedBookmarkEventNormalizesAfterClockCorrection() async throws {
        await PlayerPersistenceUpdates.flush()
        await PlayerBookmarksStore.shared.resetForTesting()
        let gate = PlayerSyncTestGate()
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)

        let admitted = await MainActor.run {
            PlayerPersistenceUpdates.enqueue {
                await gate.wait()
            }
            return PlayerBookmarksStore.enqueueBookmarkUpdate(
                collectionId: "collection",
                tokenId: "token",
                isBookmarked: true
            )
        }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        await gate.open()
        await PlayerPersistenceUpdates.flush()

        let syncedData = await PlayerBookmarksStore.shared.syncedBookmarksData
        let data = try XCTUnwrap(syncedData)
        let bookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: data
        )
        let bookmark = try XCTUnwrap(bookmarks["collection"]?["token"])
        XCTAssertTrue(admitted)
        XCTAssertEqual(bookmark.bookmarkedAt, bookmark.updatedAt)
        XCTAssertGreaterThanOrEqual(bookmark.updatedAt, actualNow)
        XCTAssertLessThan(bookmark.updatedAt, actualNow.addingTimeInterval(1))
        await PlayerBookmarksStore.shared.resetForTesting()
    }

    func testQueuedBookmarkEventAdvancesPastPlausibleFutureState() async throws {
        await PlayerPersistenceUpdates.flush()
        await PlayerBookmarksStore.shared.resetForTesting()
        let gate = PlayerSyncTestGate()
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let existingBookmark = PlayerBookmark(
            bookmarkedAt: actualNow.addingTimeInterval(-100),
            updatedAt: actualNow.addingTimeInterval(60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        _ = await PlayerBookmarksStore.shared.mergeSyncedBookmarksData(
            try encodedBookmarks(["collection": ["token": existingBookmark]])
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)

        let admitted = await MainActor.run {
            PlayerPersistenceUpdates.enqueue {
                await gate.wait()
            }
            return PlayerBookmarksStore.enqueueBookmarkUpdate(
                collectionId: "collection",
                tokenId: "token",
                isBookmarked: false
            )
        }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        await gate.open()
        await PlayerPersistenceUpdates.flush()

        let syncedData = await PlayerBookmarksStore.shared.syncedBookmarksData
        let data = try XCTUnwrap(syncedData)
        let bookmarks = try JSONDecoder().decode(
            [String: [String: PlayerBookmark]].self,
            from: data
        )
        let bookmark = try XCTUnwrap(bookmarks["collection"]?["token"])
        XCTAssertTrue(admitted)
        XCTAssertTrue(bookmark.isDeleted)
        XCTAssertEqual(bookmark.bookmarkedAt, existingBookmark.bookmarkedAt)
        XCTAssertGreaterThan(bookmark.updatedAt, existingBookmark.updatedAt)
        await PlayerBookmarksStore.shared.resetForTesting()
    }

    func testDeletedBookmarkIsEncodedForSync() async throws {
        let collectionId = "collection"
        let tokenId = "token"
        let deletedBookmark = PlayerBookmark(
            bookmarkedAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200),
            isDeleted: true
        )
        writeBookmarks([collectionId: [tokenId: deletedBookmark]])

        let syncedData = await bookmarksStore.syncedBookmarksData
        let data = try XCTUnwrap(syncedData)
        let bookmarks = try JSONDecoder().decode([String: [String: PlayerBookmark]].self, from: data)
        XCTAssertEqual(bookmarks[collectionId]?[tokenId], deletedBookmark)
    }

    func testCurrentCompactRecordsDecodeMissingOptionalFields() async throws {
        let bookmarkData = Data(#"{"bookmarkedAt":100}"#.utf8)
        let bookmark = try JSONDecoder().decode(PlayerBookmark.self, from: bookmarkData)
        XCTAssertEqual(bookmark.updatedAt, bookmark.bookmarkedAt)
        XCTAssertFalse(bookmark.isDeleted)

        let stateData = Data(
            #"{"entries":[{"collectionId":"collection","updatedAt":200}]}"#.utf8
        )
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: stateData)
        XCTAssertEqual(state.entries.map(\.collectionId), ["collection"])
        XCTAssertFalse(try XCTUnwrap(state.entries.first).isRemoved)
        XCTAssertEqual(state.updatedAt, Date(timeIntervalSinceReferenceDate: 200))
        let encodedState = try JSONEncoder().encode(state)
        let stateObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedState) as? [String: Any]
        )
        XCTAssertNil(stateObject["collectionId"])

        let progressData = Data(
            #"{"collectionId":"collection","collectionName":"Collection","tokenId":"token","tokenIndex":2,"tokenCount":10,"updatedAt":300}"#.utf8
        )
        let decodedProgress = try JSONDecoder().decode(PlayerViewingProgress.self, from: progressData)
        XCTAssertFalse(decodedProgress.hasViewedToEnd)
    }

    func testLegacyBookmarkRootPayloadIsIgnored() async throws {
        let legacyData = Data(
            #"{"collection":{"tokenId":"token","bookmarkedAt":100}}"#.utf8
        )

        let result = await bookmarksStore.mergeSyncedBookmarksData(legacyData)
        let isBookmarked = await bookmarksStore.isBookmarked(collectionId: "collection", tokenId: "token")
        XCTAssertEqual(result, .ignored)
        XCTAssertFalse(isBookmarked)
    }

    func testContinueViewingIgnoresRemoteClearWhenLocalProgressIsUseful() async throws {
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
                        updatedAt: Date(timeIntervalSinceReferenceDate: 100)
                    )
                ]
            )
        )

        let remoteClear = PlayerContinueViewingState(
            entries: [],
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteClear)
        )

        XCTAssertEqual(result, .remoteWasStale)
        let snapshot = await progressStore.progressSnapshot()
        XCTAssertEqual(snapshot.recentContinueViewingProgresses.first?.collectionId, collectionId)
    }

    func testClearedContinueViewingStateIsEncodedForSync() async throws {
        let clearedState = PlayerContinueViewingState(
            entries: [],
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        writeContinueViewing(clearedState)

        let syncedData = await progressStore.syncedContinueViewingStateData
        let data = try XCTUnwrap(syncedData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertEqual(state, clearedState)
    }

    func testLegacySingleContinueViewingPayloadIsIgnored() async throws {
        let legacyData = Data(
            #"{"collectionId":"legacy","updatedAt":200}"#.utf8
        )

        let result = await progressStore.mergeSyncedContinueViewingStateData(legacyData)
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(result, .ignored)
        XCTAssertTrue(collectionIds.isEmpty)
    }

    func testLegacyUserDefaultsKeysAreIgnored() async throws {
        let legacyKeys = [
            "mobileViewingProgressByCollectionId",
            "playerContinueViewingCollectionId",
            "mobileContinueViewingCollectionId",
            "mobileBookmarksByCollectionId"
        ]
        defer {
            legacyKeys.forEach(userDefaults.removeObject(forKey:))
        }

        let legacyProgress = progress(
            collectionId: "legacy",
            tokenId: "token",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        userDefaults.set(Data(), forKey: PlayerSyncDomain.viewingProgress.key)
        userDefaults.set(
            try encodedProgress(["legacy": legacyProgress]),
            forKey: legacyKeys[0]
        )
        userDefaults.set(Data(), forKey: PlayerSyncDomain.continueViewingState.key)
        userDefaults.set("legacy", forKey: legacyKeys[1])
        userDefaults.set("legacy", forKey: legacyKeys[2])
        userDefaults.set(Data(#"{"legacy":{"tokenId":"token","bookmarkedAt":100}}"#.utf8), forKey: legacyKeys[3])
        userDefaults.set(Data(), forKey: PlayerSyncDomain.bookmarks.key)

        let savedLegacyProgress = await progressStore.progress(collectionId: "legacy")
        let collectionIds = await continueViewingCollectionIds()
        let isBookmarked = await bookmarksStore.isBookmarked(collectionId: "legacy", tokenId: "token")
        XCTAssertNil(savedLegacyProgress)
        XCTAssertTrue(collectionIds.isEmpty)
        XCTAssertFalse(isBookmarked)
    }

    func testContinueViewingMergeSeedsRecentListFromProgressWhenStateIsMissing() async throws {
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

        let result = await progressStore.mergeSyncedContinueViewingStateData(nil)

        let expectedCollectionIds = Array((4...23).reversed()).map { "collection-\($0)" }
        XCTAssertEqual(result, .localChanged)
        let recentCollectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(recentCollectionIds, expectedCollectionIds)

        let syncedData = await progressStore.syncedContinueViewingStateData
        let data = try XCTUnwrap(syncedData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertEqual(state.entries.filter { !$0.isRemoved }.map(\.collectionId), expectedCollectionIds)
        XCTAssertEqual(state.entries.first(where: { !$0.isRemoved })?.collectionId, "collection-23")
    }

    func testContinueViewingMergeDoesNotSeedFromProgressAfterExplicitLocalClear() async throws {
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
                entries: [],
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        let result = await progressStore.mergeSyncedContinueViewingStateData(nil)

        XCTAssertEqual(result, .ignored)
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, [])
    }

    func testContinueViewingMergeStoresRemoteClearWhenLocalStateIsMissing() async throws {
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

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(entries: [], updatedAt: remoteClearUpdatedAt)
            )
        )

        XCTAssertEqual(result, .localChanged)
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, [])

        let state = try await syncedContinueViewingState()
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, remoteClearUpdatedAt)
    }

    func testContinueViewingMergeAcceptsNewerRemoteClearOverOlderLocalClear() async throws {
        let localClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let remoteClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 300)
        writeContinueViewing(
            PlayerContinueViewingState(entries: [], updatedAt: localClearUpdatedAt)
        )

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(entries: [], updatedAt: remoteClearUpdatedAt)
            )
        )

        XCTAssertEqual(result, .localChanged)

        let state = try await syncedContinueViewingState()
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, remoteClearUpdatedAt)
    }

    func testContinueViewingMergeKeepsNewerLocalClearOverStaleRemoteClear() async throws {
        let localClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 300)
        let remoteClearUpdatedAt = Date(timeIntervalSinceReferenceDate: 100)
        writeContinueViewing(
            PlayerContinueViewingState(entries: [], updatedAt: localClearUpdatedAt)
        )

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(entries: [], updatedAt: remoteClearUpdatedAt)
            )
        )

        XCTAssertEqual(result, .remoteWasStale)

        let state = try await syncedContinueViewingState()
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, localClearUpdatedAt)
    }

    func testContinueViewingSnapshotReturnsRecentEntriesNewestFirst() async throws {
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

        let collectionIds = await continueViewingCollectionIds()
        let snapshot = await progressStore.progressSnapshot()
        XCTAssertEqual(collectionIds, [newer, middle, older])
        XCTAssertEqual(snapshot.recentContinueViewingProgresses.first?.collectionId, newer)
    }

    func testContinueViewingSnapshotPreservesEntryOrderWhenTimestampsMatch() async throws {
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

        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, expectedCollectionIds)

        let state = try await syncedContinueViewingState()
        XCTAssertEqual(state.entries.filter { !$0.isRemoved }.map(\.collectionId), expectedCollectionIds)
    }

    func testSetContinueViewingMovesDuplicateCollectionToFront() async throws {
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

        await progressStore.setContinueViewingCollectionId(first)
        await progressStore.setContinueViewingCollectionId(second)
        await progressStore.setContinueViewingCollectionId(first)

        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, [first, second])
    }

    func testSetContinueViewingCapsActiveRecentListAtTwentyCollections() async throws {
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

        for collectionId in collectionIds {
            await progressStore.setContinueViewingCollectionId(collectionId)
        }

        let recentCollectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(recentCollectionIds.count, 20)
        XCTAssertEqual(recentCollectionIds.first, "collection-24")
        XCTAssertEqual(recentCollectionIds.last, "collection-5")
        XCTAssertFalse(recentCollectionIds.contains("collection-4"))
    }

    func testFreshContinueViewingSetAdvancesPastFutureClear() async throws {
        let collectionId = "collection"
        let futureTimestamp = PlayerSyncLogicalClock.next(
            for: .continueViewingState
        ).addingTimeInterval(3_600)
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: futureTimestamp
            )
        ])
        writeContinueViewing(
            PlayerContinueViewingState(entries: [], updatedAt: futureTimestamp)
        )

        await progressStore.setContinueViewingCollectionId(collectionId)

        let state = try await syncedContinueViewingState()
        let entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == collectionId })
        )
        XCTAssertFalse(entry.isRemoved)
        XCTAssertGreaterThan(entry.updatedAt, futureTimestamp)
    }

    func testImplausiblyFutureLocalContinueViewingStateAllowsSetAndRemove() async throws {
        let now = Date()
        let futureTimestamp = now.addingTimeInterval(365 * 24 * 60 * 60)
        let setCollectionId = "set-collection"
        writeContinueViewing(
            PlayerContinueViewingState(entries: [], updatedAt: futureTimestamp)
        )

        await progressStore.setContinueViewingCollectionId(setCollectionId)

        var state = try await syncedContinueViewingState()
        var entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == setCollectionId })
        )
        XCTAssertFalse(entry.isRemoved)
        XCTAssertLessThan(entry.updatedAt, futureTimestamp)

        let removeCollectionId = "remove-collection"
        writeContinueViewing(
            PlayerContinueViewingState(
                entries: [
                    PlayerContinueViewingEntry(
                        collectionId: removeCollectionId,
                        updatedAt: futureTimestamp
                    ),
                ]
            )
        )

        await progressStore.removeContinueViewingCollectionId(removeCollectionId)

        state = try await syncedContinueViewingState()
        entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == removeCollectionId })
        )
        XCTAssertTrue(entry.isRemoved)
        XCTAssertLessThan(entry.updatedAt, futureTimestamp)
    }

    func testDelayedContinueViewingUpdateNormalizesAfterClockCorrection() async throws {
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let collectionId = "collection"
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)
        let delayedUpdate = await progressStore.prepareContinueViewingUpdate(
            collectionId: collectionId
        )

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        await progressStore.applyContinueViewingUpdate(
            try XCTUnwrap(delayedUpdate)
        )

        let state = try await syncedContinueViewingState()
        let entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == collectionId })
        )
        XCTAssertGreaterThanOrEqual(entry.updatedAt, actualNow)
        XCTAssertLessThan(entry.updatedAt, actualNow.addingTimeInterval(1))
    }

    func testDelayedContinueViewingUpdateAdvancesPastPlausibleFutureState() async throws {
        let actualNow = Date()
        let incorrectNow = actualNow.addingTimeInterval(365 * 24 * 60 * 60)
        let collectionId = "collection"
        let existingEntry = PlayerContinueViewingEntry(
            collectionId: collectionId,
            updatedAt: actualNow.addingTimeInterval(60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        writeContinueViewing(PlayerContinueViewingState(entries: [existingEntry]))
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(incorrectNow)
        let delayedUpdate = await progressStore.prepareContinueViewingUpdate(
            collectionId: collectionId,
            isRemoved: true
        )

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(actualNow)
        await progressStore.applyContinueViewingUpdate(
            try XCTUnwrap(delayedUpdate)
        )

        let state = try await syncedContinueViewingState()
        let entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == collectionId })
        )
        XCTAssertTrue(entry.isRemoved)
        XCTAssertGreaterThan(entry.updatedAt, existingEntry.updatedAt)
    }

    func testInvalidRemoteContinueViewingClearCannotOverwriteLocalEntry() async throws {
        let now = Date()
        let collectionId = "collection"
        let localEntry = PlayerContinueViewingEntry(
            collectionId: collectionId,
            updatedAt: now.addingTimeInterval(-100)
        )
        writeContinueViewing(PlayerContinueViewingState(entries: [localEntry]))
        let invalidRemoteClear = PlayerContinueViewingState(
            entries: [],
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(invalidRemoteClear)
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(invalidRemoteClear.updatedAt)
        let repeatedResult = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(invalidRemoteClear)
        )

        let state = try await syncedContinueViewingState()
        XCTAssertEqual(result, .remoteWasUntrusted)
        XCTAssertEqual(repeatedResult, .remoteWasUntrusted)
        XCTAssertFalse(result.shouldMirrorLocalValue)
        XCTAssertTrue(result.blocksConflictingUpload)
        XCTAssertEqual(state.entries, [localEntry])
    }

    func testInvalidOnlyRemoteContinueViewingIsQuarantined() async throws {
        let invalidRemoteClear = PlayerContinueViewingState(
            entries: [],
            updatedAt: Date().addingTimeInterval(365 * 24 * 60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(invalidRemoteClear)
        )
        let syncedData = await progressStore.syncedContinueViewingStateData

        XCTAssertEqual(result, .ignored)
        XCTAssertFalse(result.shouldMirrorLocalValue)
        XCTAssertNil(syncedData)

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(invalidRemoteClear.updatedAt)
        let agedResult = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(invalidRemoteClear)
        )
        let agedState = try await syncedContinueViewingState()
        XCTAssertEqual(agedResult, .localChanged)
        XCTAssertEqual(agedState, invalidRemoteClear)
    }

    func testInvalidContinueViewingEntryIsQuarantinedWhileValidSiblingMerges() async throws {
        let now = Date()
        let validEntry = PlayerContinueViewingEntry(
            collectionId: "valid",
            updatedAt: now.addingTimeInterval(-10)
        )
        let invalidEntry = PlayerContinueViewingEntry(
            collectionId: "invalid",
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60)
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(entries: [validEntry, invalidEntry])
            )
        )
        let storedData = try XCTUnwrap(
            userDefaults.data(forKey: PlayerSyncDomain.continueViewingState.key)
        )
        let storedState = try JSONDecoder().decode(
            PlayerContinueViewingState.self,
            from: storedData
        )

        XCTAssertEqual(result, .localChanged)
        XCTAssertTrue(result.shouldMirrorLocalValue)
        XCTAssertEqual(storedState.entries, [validEntry])
        let encodedSyncedState = await progressStore.syncedContinueViewingStateData
        let syncedData = try XCTUnwrap(encodedSyncedState)
        let syncedState = try JSONDecoder().decode(
            PlayerContinueViewingState.self,
            from: syncedData
        )
        XCTAssertEqual(Set(syncedState.entries), Set([validEntry, invalidEntry]))

        PlayerSyncTimestampPolicy.setCurrentDateForTesting(invalidEntry.updatedAt)
        let agedResult = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(entries: [validEntry, invalidEntry])
            )
        )
        let agedStoredData = try XCTUnwrap(
            userDefaults.data(forKey: PlayerSyncDomain.continueViewingState.key)
        )
        let agedStoredState = try JSONDecoder().decode(
            PlayerContinueViewingState.self,
            from: agedStoredData
        )
        XCTAssertEqual(agedResult, .localChanged)
        XCTAssertTrue(agedStoredState.entries.contains(invalidEntry))
    }

    func testQuarantinedContinueViewingEntryKeepsSameKeyUpdatePending() async throws {
        let now = Date()
        let rejectedEntry = PlayerContinueViewingEntry(
            collectionId: "collection",
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60)
        )
        let remoteData = try JSONEncoder().encode(
            PlayerContinueViewingState(entries: [rejectedEntry])
        )
        defer { PlayerSyncTimestampPolicy.setCurrentDateForTesting(nil) }
        _ = await progressStore.mergeSyncedContinueViewingStateData(remoteData)
        await progressStore.setContinueViewingCollectionId("collection")

        let result = await progressStore.mergeSyncedContinueViewingStateData(remoteData)
        let restartedStore = PlayerViewingProgressStore(
            userDefaults: UserDefaults(suiteName: userDefaultsSuiteName)!
        )
        PlayerSyncTimestampPolicy.setCurrentDateForTesting(rejectedEntry.updatedAt)
        let repeatedResult = await restartedStore.mergeSyncedContinueViewingStateData(
            remoteData
        )
        let encodedState = await restartedStore.syncedContinueViewingStateData
        let data = try XCTUnwrap(encodedState)
        let outboundState = try JSONDecoder().decode(
            PlayerContinueViewingState.self,
            from: data
        )

        XCTAssertEqual(result, .remoteWasPartiallyUntrusted)
        XCTAssertTrue(result.shouldMirrorLocalValue)
        XCTAssertFalse(result.blocksConflictingUpload)
        XCTAssertEqual(repeatedResult, .remoteWasPartiallyUntrusted)
        XCTAssertEqual(outboundState.entries, [rejectedEntry])
    }

    func testInvalidContinueViewingEntryBlocksLocalClear() async throws {
        let localClear = PlayerContinueViewingState(
            entries: [],
            updatedAt: Date().addingTimeInterval(-10)
        )
        writeContinueViewing(localClear)
        let invalidEntry = PlayerContinueViewingEntry(
            collectionId: "invalid",
            updatedAt: Date().addingTimeInterval(365 * 24 * 60 * 60)
        )

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(entries: [invalidEntry])
            )
        )
        let storedData = try XCTUnwrap(
            userDefaults.data(forKey: PlayerSyncDomain.continueViewingState.key)
        )
        let storedState = try JSONDecoder().decode(
            PlayerContinueViewingState.self,
            from: storedData
        )

        XCTAssertEqual(result, .remoteWasUntrusted)
        XCTAssertFalse(result.shouldMirrorLocalValue)
        XCTAssertEqual(storedState, localClear)
    }

    func testInvalidRemoteContinueViewingRootKeepsValidRemoteEntries() async throws {
        let now = Date()
        let localEntry = PlayerContinueViewingEntry(
            collectionId: "local",
            updatedAt: now.addingTimeInterval(-100)
        )
        let remoteEntry = PlayerContinueViewingEntry(
            collectionId: "remote",
            updatedAt: now.addingTimeInterval(-50)
        )
        writeContinueViewing(PlayerContinueViewingState(entries: [localEntry]))
        let remoteState = PlayerContinueViewingState(
            entries: [remoteEntry],
            updatedAt: now.addingTimeInterval(365 * 24 * 60 * 60)
        )

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteState)
        )

        let state = try await syncedContinueViewingState()
        XCTAssertEqual(result, .localChanged)
        XCTAssertEqual(Set(state.entries), Set([localEntry, remoteEntry]))
    }

    func testDeferredOpeningUpdateDoesNotOverrideLaterCompletedProgress() async throws {
        let collectionId = "collection"
        let preparedOpeningUpdate = await progressStore.prepareContinueViewingUpdate(
            collectionId: collectionId
        )
        let openingUpdate = try XCTUnwrap(preparedOpeningUpdate)
        let completedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-9",
            tokenIndex: 9,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )

        await tracker.markViewed(completedProgress)
        await progressStore.applyContinueViewingUpdate(openingUpdate)

        let state = try await syncedContinueViewingState()
        let entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == collectionId })
        )
        XCTAssertTrue(entry.isRemoved)
        XCTAssertEqual(entry.updatedAt, completedProgress.updatedAt)
        XCTAssertGreaterThan(completedProgress.updatedAt, openingUpdate.updatedAt)
    }

    func testRestartRemovalAdvancesPastFutureContinueViewingEntry() async throws {
        let collectionId = "collection"
        let futureTimestamp = PlayerSyncLogicalClock.next(
            for: .continueViewingState
        ).addingTimeInterval(3_600)
        writeContinueViewing(
            PlayerContinueViewingState(
                entries: [
                    PlayerContinueViewingEntry(
                        collectionId: collectionId,
                        updatedAt: futureTimestamp
                    )
                ]
            )
        )
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )

        await tracker.beginRestart(collectionId: collectionId)

        let state = try await syncedContinueViewingState()
        let entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == collectionId })
        )
        XCTAssertTrue(entry.isRemoved)
        XCTAssertGreaterThan(entry.updatedAt, futureTimestamp)
    }

    func testPreparedRestartUpdateLetsQueuedMovementResumeContinueViewing() async throws {
        let collectionId = "collection"
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )
        let queuedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-3",
            tokenIndex: 3,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        let preparedRestartUpdate = await tracker.prepareRestartUpdate(collectionId: collectionId)
        let restartUpdate = try XCTUnwrap(preparedRestartUpdate)
        let restartedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-0",
            tokenIndex: 0,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        let movementProgress = progress(
            collectionId: collectionId,
            tokenId: "token-1",
            tokenIndex: 1,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )

        await tracker.markViewed(queuedProgress)
        await tracker.beginRestart(update: restartUpdate)
        await tracker.markViewed(restartedProgress)
        await tracker.markViewed(movementProgress)

        let state = try await syncedContinueViewingState()
        let entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == collectionId })
        )
        XCTAssertFalse(entry.isRemoved)
        XCTAssertGreaterThanOrEqual(entry.updatedAt, movementProgress.updatedAt)
        XCTAssertGreaterThan(movementProgress.updatedAt, restartUpdate.updatedAt)
    }

    func testPreparedRestartUpdateRebasesPastLaterQueuedProgress() async throws {
        let collectionId = "collection"
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )
        let preparedRestartUpdate = await tracker.prepareRestartUpdate(
            collectionId: collectionId
        )
        let restartUpdate = try XCTUnwrap(preparedRestartUpdate)
        let queuedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-3",
            tokenIndex: 3,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
        let restartedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-0",
            tokenIndex: 0,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )

        await tracker.markViewed(queuedProgress)
        await tracker.beginRestart(update: restartUpdate)
        await tracker.markViewed(restartedProgress)

        let state = try await syncedContinueViewingState()
        let entry = try XCTUnwrap(
            state.entries.first(where: { $0.collectionId == collectionId })
        )
        XCTAssertTrue(entry.isRemoved)
        XCTAssertGreaterThan(entry.updatedAt, queuedProgress.updatedAt)
    }

    func testRestartRebaseUsesNewerEmptyStateClearAsMovementFloor() async throws {
        let collectionId = "collection"
        let optionalPreparedUpdate = await progressStore.prepareContinueViewingUpdate(
            collectionId: collectionId,
            isRemoved: true
        )
        let preparedUpdate = try XCTUnwrap(optionalPreparedUpdate)
        let clearTimestamp = PlayerSyncLogicalClock.next(for: .continueViewingState)
        writeContinueViewing(
            PlayerContinueViewingState(entries: [], updatedAt: clearTimestamp)
        )

        let rebasedUpdate = await progressStore.rebasedRestartContinueViewingUpdate(
            preparedUpdate
        )

        XCTAssertEqual(rebasedUpdate.updatedAt, clearTimestamp)
        XCTAssertTrue(rebasedUpdate.isRemoved)
    }

    func testRemovingMostRecentContinueViewingCollectionRevealsOlderCollection() async throws {
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

        await progressStore.updateContinueViewingCollection(
            for: progress(
                collectionId: recent,
                tokenId: "token-9",
                tokenIndex: 9,
                updatedAt: Date(timeIntervalSinceReferenceDate: 300)
            ),
            expectedCollectionId: recent
        )

        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, [older])
    }

    func testContinueViewingMergeKeepsNewerLocalRemovalOverStaleRemoteActiveEntry() async throws {
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

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteState)
        )

        XCTAssertEqual(result, .remoteWasStale)
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, [])
    }

    func testRemovingAlreadyRemovedContinueViewingCollectionRefreshesTombstone() async throws {
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

        await progressStore.removeContinueViewingCollectionId(collectionId)

        let syncedData = await progressStore.syncedContinueViewingStateData
        let data = try XCTUnwrap(syncedData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        let refreshedEntry = try XCTUnwrap(state.entries.first)
        XCTAssertTrue(refreshedEntry.isRemoved)
        XCTAssertGreaterThan(refreshedEntry.updatedAt, removedAt)
        XCTAssertEqual(state.updatedAt, refreshedEntry.updatedAt)
    }

    func testNewerLocalRemovalPreventsIntermediateRemoteEntryFromResurrecting() async throws {
        let collectionId = "collection"
        let initialRemovalAt = Date(timeIntervalSinceReferenceDate: 100)
        let remoteEntryAt = Date(timeIntervalSinceReferenceDate: 200)
        let localRemovalAt = Date(timeIntervalSinceReferenceDate: 300)
        writeProgress([
            collectionId: progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: remoteEntryAt
            )
        ])
        writeContinueViewing(
            PlayerContinueViewingState(
                entries: [
                    PlayerContinueViewingEntry(
                        collectionId: collectionId,
                        updatedAt: initialRemovalAt,
                        isRemoved: true
                    )
                ]
            )
        )

        await progressStore.applyContinueViewingUpdate(
            PlayerContinueViewingUpdate(
                collectionId: collectionId,
                updatedAt: localRemovalAt,
                isRemoved: true
            )
        )
        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(
                PlayerContinueViewingState(
                    entries: [
                        PlayerContinueViewingEntry(
                            collectionId: collectionId,
                            updatedAt: remoteEntryAt
                        )
                    ]
                )
            )
        )

        let state = try await syncedContinueViewingState()
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(result, .remoteWasStale)
        XCTAssertEqual(
            state.entries,
            [
                PlayerContinueViewingEntry(
                    collectionId: collectionId,
                    updatedAt: localRemovalAt,
                    isRemoved: true
                )
            ]
        )
        XCTAssertTrue(collectionIds.isEmpty)
    }

    func testContinueViewingMergeKeepsNewerLocalClearOverStaleRemoteActiveEntry() async throws {
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
                entries: [],
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

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteState)
        )

        XCTAssertEqual(result, .remoteWasStale)
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, [])

        let syncedData = await progressStore.syncedContinueViewingStateData
        let data = try XCTUnwrap(syncedData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.updatedAt, localClearUpdatedAt)
    }

    func testContinueViewingMergeAcceptsRemoteEntryNewerThanLocalClear() async throws {
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
                entries: [],
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

        let result = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(remoteState)
        )

        XCTAssertEqual(result, .localChanged)
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(collectionIds, [collectionId])
    }

    func testContinueViewingStateCapsRemovedEntriesAtTwentyCollections() async throws {
        let entries = (0..<25).map { index in
            PlayerContinueViewingEntry(
                collectionId: "collection-\(index)",
                updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
                isRemoved: true
            )
        }
        writeContinueViewing(PlayerContinueViewingState(entries: entries))

        let syncedData = await progressStore.syncedContinueViewingStateData
        let data = try XCTUnwrap(syncedData)
        let state = try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)

        XCTAssertFalse(state.entries.contains { !$0.isRemoved })
        XCTAssertEqual(state.entries.count, 20)
        XCTAssertEqual(
            state.entries.map(\.collectionId),
            Array((5...24).reversed()).map { "collection-\($0)" }
        )
        XCTAssertTrue(state.entries.allSatisfy(\.isRemoved))
    }

    func testContinueViewingUpdateKeepsViewedToEndCollectionCleared() async throws {
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

        await progressStore.updateContinueViewingCollection(
            for: progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            ),
            expectedCollectionId: collectionId
        )

        let snapshot = await progressStore.progressSnapshot()
        XCTAssertNil(snapshot.recentContinueViewingProgresses.first)
        try await assertSyncedContinueViewingCleared()
    }

    func testStaleProgressUpdateKeepsNewerContinueViewingRemoval() async throws {
        let collectionId = "collection"
        let newerProgress = progress(
            collectionId: collectionId,
            tokenId: "token-4",
            tokenIndex: 4,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let removal = PlayerContinueViewingEntry(
            collectionId: collectionId,
            updatedAt: Date(timeIntervalSinceReferenceDate: 300),
            isRemoved: true
        )
        _ = await progressStore.mergeSyncedProgressData(
            try encodedProgress([collectionId: newerProgress])
        )
        _ = await progressStore.mergeSyncedContinueViewingStateData(
            try JSONEncoder().encode(PlayerContinueViewingState(entries: [removal]))
        )
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )

        await tracker.markViewed(
            progress(
                collectionId: collectionId,
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        let savedProgress = await progressStore.progress(collectionId: collectionId)
        let state = try await syncedContinueViewingState()
        let collectionIds = await continueViewingCollectionIds()
        XCTAssertEqual(savedProgress?.tokenId, newerProgress.tokenId)
        XCTAssertEqual(state.entries, [removal])
        XCTAssertTrue(collectionIds.isEmpty)
    }

    func testSessionTrackerSavesProgressAndSetsContinueViewingForExpectedCollection() async throws {
        let collectionId = "collection"
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )
        let viewedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-2",
            tokenIndex: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )

        await tracker.markViewed(viewedProgress)
        let savedProgress = await progressStore.progress(collectionId: collectionId)
        let snapshot = await progressStore.progressSnapshot()
        XCTAssertEqual(savedProgress, viewedProgress)
        XCTAssertEqual(snapshot.recentContinueViewingProgresses.first?.collectionId, collectionId)
    }

    func testSessionTrackerClearsContinueViewingWhenExpectedCollectionDoesNotMatch() async throws {
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: "expected",
            progressStore: progressStore
        )

        await tracker.markViewed(
            progress(
                collectionId: "other",
                tokenId: "token-2",
                tokenIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        let snapshot = await progressStore.progressSnapshot()
        XCTAssertNil(snapshot.recentContinueViewingProgresses.first)
        try await assertSyncedContinueViewingCleared()
    }

    func testSessionTrackerClearsContinueViewingWhenCollectionIsViewedToEnd() async throws {
        let collectionId = "collection"
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )

        await tracker.markViewed(
            progress(
                collectionId: collectionId,
                tokenId: "token-9",
                tokenIndex: 9,
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )

        let snapshot = await progressStore.progressSnapshot()
        XCTAssertNil(snapshot.recentContinueViewingProgresses.first)
        try await assertSyncedContinueViewingCleared()
    }

    func testSessionTrackerKeepsContinueViewingClearedAtRestartedTokenZero() async throws {
        let collectionId = "collection"
        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: collectionId,
            progressStore: progressStore
        )
        let viewedProgress = progress(
            collectionId: collectionId,
            tokenId: "token-3",
            tokenIndex: 3,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        await tracker.markViewed(viewedProgress)

        await tracker.beginRestart(collectionId: viewedProgress.collectionId)
        await tracker.markViewed(
            progress(
                collectionId: collectionId,
                tokenId: "token-0",
                tokenIndex: 0,
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        let snapshot = await progressStore.progressSnapshot()
        XCTAssertNil(snapshot.recentContinueViewingProgresses.first)
        try await assertSyncedContinueViewingCleared()
    }

    private func assertSyncedContinueViewingCleared() async throws {
        let state = try await syncedContinueViewingState()
        XCTAssertFalse(state.entries.contains { !$0.isRemoved })
    }

    private func syncedContinueViewingState(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PlayerContinueViewingState {
        let syncedData = await progressStore.syncedContinueViewingStateData
        let data = try XCTUnwrap(
            syncedData,
            file: file,
            line: line
        )
        return try JSONDecoder().decode(PlayerContinueViewingState.self, from: data)
    }

    private func continueViewingCollectionIds() async -> [String] {
        await progressStore.progressSnapshot()
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

    private func resetStores() async {
        await progressStore.resetForTesting()
        await bookmarksStore.resetForTesting()
    }

    private func writeProgress(_ progress: [String: PlayerViewingProgress]) {
        userDefaults.set(try! encodedProgress(progress), forKey: PlayerSyncDomain.viewingProgress.key)
    }

    private func writeBookmarks(_ bookmarks: [String: [String: PlayerBookmark]]) {
        userDefaults.set(try! encodedBookmarks(bookmarks), forKey: PlayerSyncDomain.bookmarks.key)
    }

    private func writeContinueViewing(_ state: PlayerContinueViewingState) {
        userDefaults.set(
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

private actor PlayerSyncTestGate {
    private var isOpen = false
    private var continuations = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waitingContinuations = continuations
        continuations.removeAll()
        waitingContinuations.forEach { $0.resume() }
    }
}

@MainActor
private final class BookmarkToggleCompletionRecorder {
    var value: Bool?
}
