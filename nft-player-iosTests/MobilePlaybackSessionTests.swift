// ∅ 2026 lil org

import XCTest
@testable import nft_player_ios

nonisolated final class MobilePlaybackSessionTests: XCTestCase {}

private actor MobilePlaybackSessionTestViewingTracker:
    MobilePlaybackViewingSessionTracking {

    private let preparationStarted: AsyncStream<Void>
    private let preparationStartedContinuation: AsyncStream<Void>.Continuation
    private var restartContinuation:
        CheckedContinuation<PlayerContinueViewingUpdate?, Never>?
    private var isPreparationCancelled = false

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.preparationStarted = stream
        self.preparationStartedContinuation = continuation
    }

    func prepareRestartUpdate(
        collectionId: String?
    ) async -> PlayerContinueViewingUpdate? {
        guard !isPreparationCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            restartContinuation = continuation
            preparationStartedContinuation.yield(())
            preparationStartedContinuation.finish()
        }
    }

    func beginRestart(update: PlayerContinueViewingUpdate?) async {}

    func markViewed(_ progress: MobileViewingProgress) async {}

    func waitUntilPrepareStarted() async -> Bool {
        var iterator = preparationStarted.makeAsyncIterator()
        return await iterator.next() != nil
    }

    func cancelPreparedRestart() {
        isPreparationCancelled = true
        preparationStartedContinuation.finish()
        resumePreparedRestart()
    }

    func resumePreparedRestart() {
        guard let continuation = restartContinuation else { return }
        restartContinuation = nil
        continuation.resume(returning: nil)
    }
}

private actor MobilePlaybackSessionTestThumbnailWindowPlanner:
    MobileCollectionBrowseThumbnailWindowPlanning {

    private let startedExpectation: XCTestExpectation
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init(startedExpectation: XCTestExpectation) {
        self.startedExpectation = startedExpectation
    }

    func makeWindow(
        for request: MobileCollectionBrowseThumbnailWindowPlanRequest
    ) async -> PlayerDownloadableMediaWindow? {
        startedExpectation.fulfill()
        if !isReleased {
            await withCheckedContinuation { continuation in
                if isReleased {
                    continuation.resume()
                } else {
                    releaseContinuation = continuation
                }
            }
        }
        let descriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: request.snapshot.collectionId,
            tokenId: String(request.tokenIndex),
            tokenIndex: request.tokenIndex,
            media: .staticImage(
                url: URL(
                    fileURLWithPath:
                        "/session-order/\(request.snapshot.collectionId)/"
                            + "\(request.tokenIndex).webp"
                ),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
        return PlayerDownloadableMediaWindow(
            currentDescriptor: descriptor,
            descriptors: [descriptor],
            decodedDescriptors: [descriptor],
            adjacentDescriptor: nil,
            decodeVariant: request.decodeVariant
        )
    }

    func resume() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class MobilePlaybackSessionTestDisplay:
    MobilePlaybackSessionDisplay {

    var pagePosition = PlayerPagePosition.initial
    private(set) var navigations = [PlaybackNavigationDirection]()
    private(set) var flushCount = 0

    func navigate(_ direction: PlaybackNavigationDirection) {
        navigations.append(direction)
    }

    func getCurrentPagePosition() -> PlayerPagePosition {
        pagePosition
    }

    func flushPendingViewingProgress() {
        flushCount += 1
    }
}

@MainActor
private final class MobilePlaybackSessionTestWeakDisplayReference {
    weak var value: MobilePlaybackSessionTestDisplay?

    init(_ value: MobilePlaybackSessionTestDisplay?) {
        self.value = value
    }
}

@MainActor
extension MobilePlaybackSessionTests {

    private func testCollectionIDs() throws -> (String, String) {
        let collectionIDs = SuggestedItemsService.visibleItems
            .map(\.id)
            .filter {
                PlayerCollectionBrowserSupport.isAvailable(
                    forCollectionId: $0
                ) && CollectionCatalog.tokenCount(
                    specificCollectionId: $0
                ) > 0
            }
        guard collectionIDs.count >= 2 else {
            throw XCTSkip("Two playable collections are required")
        }
        return (collectionIDs[0], collectionIDs[1])
    }

    private func dependencyRegistry(
        preload: @escaping @MainActor (String) -> Void
    ) -> MobilePlaybackSessionRegistry {
        MobilePlaybackSessionRegistry(dependencies: .init(
            makeViewingSessionTracker: { _ in MobilePlaybackSessionTestViewingTracker() },
            clearActiveMediaWindow: { _ in },
            cancelAllMediaDownloads: {},
            preloadArtworkDependency: preload
        ))
    }

    private func dependencyCollection() throws -> SuggestedItem {
        try XCTUnwrap(SuggestedItemsService.visibleItems.first { $0.internalSlug == "hypertype" })
    }

    private func dependencyAnchorInsertion(
        item: SuggestedItem,
        insertedToken: GeneratedToken
    ) throws -> PlayerWidgetTokenInsertion {
        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
        return PlayerWidgetTokenInsertion(
            insertedToken: insertedToken,
            insertedTokenIndex: 0,
            anchorProgress: PlayerViewingProgress(
                collectionId: item.id,
                collectionName: item.name,
                tokenId: tokens[2].id,
                tokenIndex: 2,
                tokenCount: tokens.count,
                updatedAt: .distantPast
            ),
            isAnchorProgressResolved: true
        )
    }

    func testArtworkDependencyPreloadStartsForActualCollectionEntries() throws {
        let item = try dependencyCollection()
        let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: 7))
        let (otherID, _) = try testCollectionIDs()
        var requests = [String]()
        let registry = dependencyRegistry { requests.append($0) }
        let configurations = [
            MobilePlayerConfig(initialItemId: item.id),
            MobilePlayerConfig(initialItemId: item.id, initialTokenId: token.id,
                               initialTokenIndex: 7, continueViewingCollectionId: item.id),
            MobilePlayerConfig(initialItemId: otherID, specificToken: token),
            MobilePlayerConfig(initialItemId: otherID,
                               widgetTokenInsertion: try dependencyAnchorInsertion(item: item, insertedToken: token))
        ]
        for (index, config) in configurations.enumerated() {
            let session = registry.startSession(config: config)
            XCTAssertTrue(session.isActive)
            XCTAssertEqual(requests, Array(repeating: item.id, count: index + 1))
            session.stopAndDisconnect()
        }
    }

    func testOtherCollectionsAndTokenPreparationDoNotRequestDependencies() throws {
        let item = try dependencyCollection()
        let (otherID, _) = try testCollectionIDs()
        XCTAssertNotEqual(otherID, item.id)
        var requests = [String]()
        let registry = dependencyRegistry { requests.append($0) }
        let session = registry.startSession(config: MobilePlayerConfig(initialItemId: otherID))
        defer { session.stopAndDisconnect() }
        XCTAssertNotNil(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: 0))
        XCTAssertNotNil(session.collectionBrowseSnapshot())
        XCTAssertNotNil(session.prepareCollectionBrowse(containing: .initial))
        _ = session.getToken(pagePosition: .initial)
        _ = session.markViewed(pagePosition: .initial)
        XCTAssertTrue(requests.isEmpty)
    }

    func testWidgetAnchorDependencyWaitsForCommittedCollectionBrowse() throws {
        let item = try dependencyCollection()
        let (otherID, _) = try testCollectionIDs()
        let insertedToken = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: otherID, tokenIndex: 0))
        var requests = [String]()
        let registry = dependencyRegistry { requests.append($0) }
        let session = registry.startSession(config: MobilePlayerConfig(
            initialItemId: item.id,
            widgetTokenInsertion: try dependencyAnchorInsertion(item: item, insertedToken: insertedToken)
        ))
        defer { session.stopAndDisconnect() }
        XCTAssertEqual(session.getToken(pagePosition: .initial).fullCollectionId, otherID)
        _ = session.markViewed(pagePosition: .initial)
        let preparation = try XCTUnwrap(session.prepareCollectionBrowse(containing: .initial))
        XCTAssertEqual(preparation.snapshot.collectionId, item.id)
        XCTAssertTrue(requests.isEmpty)
        let invalid = PlayerCollectionBrowsePreparation(
            sourcePagePosition: preparation.sourcePagePosition,
            snapshot: preparation.snapshot,
            focusedTokenIndex: preparation.focusedTokenIndex + 1,
            requiresWidgetInsertionExit: preparation.requiresWidgetInsertionExit
        )
        XCTAssertEqual(session.commitCollectionBrowse(preparation: invalid), .unavailable)
        XCTAssertTrue(requests.isEmpty)
        guard case .resolved(let position) = session.commitCollectionBrowse(preparation: preparation) else {
            return XCTFail("Expected the prepared collection to commit")
        }
        XCTAssertEqual(requests, [item.id])
        XCTAssertEqual(session.getToken(pagePosition: position).fullCollectionId, item.id)
        _ = session.markViewed(pagePosition: position)
        let repeated = try XCTUnwrap(session.prepareCollectionBrowse(containing: position))
        XCTAssertEqual(session.commitCollectionBrowse(preparation: repeated), .resolved(position))
        XCTAssertEqual(requests, [item.id])
    }

    func testSettledCollectionChangePreloadsOnceAndStopsAfterDisconnect() throws {
        let item = try dependencyCollection()
        let (otherID, _) = try testCollectionIDs()
        let insertedToken = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: otherID, tokenIndex: 0))
        var requests = [String]()
        let registry = dependencyRegistry { requests.append($0) }
        let session = registry.startSession(config: MobilePlayerConfig(
            initialItemId: item.id,
            widgetTokenInsertion: try dependencyAnchorInsertion(item: item, insertedToken: insertedToken)
        ))
        let anchorPosition = PlayerPagePosition(position: 1)
        XCTAssertEqual(session.getToken(pagePosition: anchorPosition).fullCollectionId, item.id)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNotNil(session.markViewed(pagePosition: anchorPosition))
        XCTAssertEqual(requests, [item.id])
        XCTAssertNotNil(session.markViewed(pagePosition: anchorPosition))
        XCTAssertEqual(requests, [item.id])
        let preparation = try XCTUnwrap(session.prepareCollectionBrowse(containing: anchorPosition))
        session.stopAndDisconnect()
        XCTAssertNil(session.markViewed(pagePosition: anchorPosition))
        XCTAssertEqual(session.commitCollectionBrowse(preparation: preparation), .unavailable)
        XCTAssertEqual(requests, [item.id])
    }

    func testSessionsWithSharedConfigIDKeepIndependentStateAndDisplays() throws {
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in
                    MobilePlaybackSessionTestViewingTracker()
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {}
            )
        )
        let (firstCollectionID, secondCollectionID) = try testCollectionIDs()
        let sharedConfigID = UUID()
        let firstSession = registry.startSession(
            config: MobilePlayerConfig(
                id: sharedConfigID,
                initialItemId: firstCollectionID
            )
        )
        let secondSession = registry.startSession(
            config: MobilePlayerConfig(
                id: sharedConfigID,
                initialItemId: secondCollectionID
            )
        )
        let firstDisplay = MobilePlaybackSessionTestDisplay()
        let secondDisplay = MobilePlaybackSessionTestDisplay()
        firstSession.attach(display: firstDisplay)
        secondSession.attach(display: secondDisplay)

        XCTAssertEqual(
            firstSession.collectionBrowseSnapshot()?.collectionId,
            firstCollectionID
        )
        XCTAssertEqual(
            secondSession.collectionBrowseSnapshot()?.collectionId,
            secondCollectionID
        )

        firstSession.goForward()

        XCTAssertEqual(firstDisplay.navigations.count, 1)
        switch try XCTUnwrap(firstDisplay.navigations.first) {
        case .forward:
            break
        case .back, .restartCollection:
            XCTFail("First session routed an unexpected navigation")
        }
        XCTAssertTrue(secondDisplay.navigations.isEmpty)

        firstSession.stopAndDisconnect()
        secondSession.stopAndDisconnect()
    }

    func testDisconnectedSessionReturnsFallbacksAndRejectsActions() async throws {
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in
                    MobilePlaybackSessionTestViewingTracker()
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {}
            )
        )
        let (collectionID, _) = try testCollectionIDs()
        let session = registry.startSession(
            config: MobilePlayerConfig(initialItemId: collectionID)
        )
        let display = MobilePlaybackSessionTestDisplay()
        session.attach(display: display)
        let preparation = try XCTUnwrap(
            session.prepareCollectionBrowse(containing: .initial)
        )

        session.stopAndDisconnect()
        session.goForward()
        session.goBack()
        session.restartCollection()

        XCTAssertEqual(display.flushCount, 1)
        XCTAssertTrue(display.navigations.isEmpty)
        XCTAssertEqual(session.getToken(pagePosition: .initial), .empty)
        XCTAssertFalse(session.canRender(pagePosition: .initial))
        XCTAssertNil(session.pageLabel(pagePosition: .initial))
        XCTAssertFalse(
            session.isInsertedWidgetToken(pagePosition: .initial)
        )
        XCTAssertNil(session.collectionBrowseSnapshot())
        XCTAssertNil(session.prepareCollectionBrowse(containing: .initial))
        XCTAssertEqual(
            session.commitCollectionBrowse(preparation: preparation),
            .unavailable
        )
        XCTAssertNil(
            session.collectionBrowseThumbnailDescriptor(
                pagePosition: .initial
            )
        )
        let layoutState = session.layoutInteractionState(
            displayMode: .onePerPage,
            pagePosition: .initial,
            collectionBrowserAvailable: true
        )
        XCTAssertFalse(layoutState.collectionBrowserAvailable)
        XCTAssertNil(layoutState.currentDescriptor)
        XCTAssertNil(
            session.prepareDownloadableMediaWindow(
                pagePosition: .initial,
                direction: .forward
            )
        )
        session.prepareCollectionBrowseThumbnailWindow(
            centeredAt: 0,
            direction: .forward,
            prefetchStride: 1,
            columnCount: 1,
            quality: .thumbnail,
            requiredTokenRange: nil,
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: []
        )
        XCTAssertNil(
            session.downloadableMediaDescriptor(pagePosition: .initial)
        )
        XCTAssertFalse(
            session.hasNavigationDestination(
                from: .initial,
                direction: .forward
            )
        )
        XCTAssertNil(session.markViewed(pagePosition: .initial))
        XCTAssertNil(
            session.progress(
                pagePosition: .initial,
                resolvedToken: .empty
            )
        )
        let shareItem = await session.downloadedFileShareItem(
            pagePosition: .initial
        )
        XCTAssertNil(shareItem)
        XCTAssertEqual(session.startPagePosition(), .initial)
    }

    func testStopsSessionsByIdentityAndPreservesCacheCleanupPolicy() {
        let tracker = MobilePlaybackSessionTestViewingTracker()
        var clearedOwnerIDs = [UUID]()
        var cancelAllCount = 0
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in tracker },
                clearActiveMediaWindow: { clearedOwnerIDs.append($0) },
                cancelAllMediaDownloads: { cancelAllCount += 1 }
            )
        )
        let firstSession = registry.startSession(config: MobilePlayerConfig())
        let secondSession = registry.startSession(config: MobilePlayerConfig())
        let thirdSession = registry.startSession(config: MobilePlayerConfig())
        let firstDisplay = MobilePlaybackSessionTestDisplay()
        let secondDisplay = MobilePlaybackSessionTestDisplay()
        let thirdDisplay = MobilePlaybackSessionTestDisplay()
        firstSession.attach(display: firstDisplay)
        secondSession.attach(display: secondDisplay)
        thirdSession.attach(display: thirdDisplay)

        firstSession.stopAndDisconnect()

        XCTAssertEqual(firstDisplay.flushCount, 1)
        XCTAssertEqual(registry.activeSessionCount, 2)
        XCTAssertEqual(clearedOwnerIDs.count, 1)
        XCTAssertEqual(cancelAllCount, 0)

        secondSession.stopAndDisconnect()

        XCTAssertEqual(secondDisplay.flushCount, 1)
        XCTAssertEqual(registry.activeSessionCount, 1)
        XCTAssertEqual(clearedOwnerIDs.count, 2)
        XCTAssertEqual(Set(clearedOwnerIDs).count, 2)
        XCTAssertEqual(cancelAllCount, 0)

        thirdSession.stopAndDisconnect()
        thirdSession.stopAndDisconnect()

        XCTAssertEqual(thirdDisplay.flushCount, 1)
        XCTAssertEqual(registry.activeSessionCount, 0)
        XCTAssertEqual(clearedOwnerIDs.count, 2)
        XCTAssertEqual(cancelAllCount, 1)
    }

    func testPendingRestartDoesNotRetainOrNavigateReplacedDisplay() async throws {
        let tracker = MobilePlaybackSessionTestViewingTracker()
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in tracker },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {}
            )
        )
        let session = registry.startSession(config: MobilePlayerConfig())
        var originalDisplay: MobilePlaybackSessionTestDisplay? =
            MobilePlaybackSessionTestDisplay()
        let originalDisplayReference =
            MobilePlaybackSessionTestWeakDisplayReference(originalDisplay)
        session.attach(display: originalDisplay!)
        let restartTask = try XCTUnwrap(session.restartCollection())
        guard await waitUntilPrepareStarted(tracker) else {
            session.stopAndDisconnect()
            await tracker.cancelPreparedRestart()
            restartTask.cancel()
            XCTFail("Restart preparation did not start")
            return
        }
        let replacementDisplay = MobilePlaybackSessionTestDisplay()
        session.attach(display: replacementDisplay)

        originalDisplay = nil
        XCTAssertNil(originalDisplayReference.value)
        await tracker.resumePreparedRestart()
        await restartTask.value

        XCTAssertTrue(replacementDisplay.navigations.isEmpty)
        session.stopAndDisconnect()
    }

    func testPendingRestartCannotNavigateAfterDisconnect() async throws {
        let tracker = MobilePlaybackSessionTestViewingTracker()
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in tracker },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {}
            )
        )
        let session = registry.startSession(config: MobilePlayerConfig())
        let display = MobilePlaybackSessionTestDisplay()
        session.attach(display: display)
        let restartTask = try XCTUnwrap(session.restartCollection())
        guard await waitUntilPrepareStarted(tracker) else {
            session.stopAndDisconnect()
            await tracker.cancelPreparedRestart()
            restartTask.cancel()
            XCTFail("Restart preparation did not start")
            return
        }

        session.stopAndDisconnect()
        await tracker.resumePreparedRestart()
        await restartTask.value

        XCTAssertEqual(display.flushCount, 1)
        XCTAssertTrue(display.navigations.isEmpty)
        XCTAssertEqual(registry.activeSessionCount, 0)
    }

    func testThumbnailWindowPreparationCancellationRejectsPendingTask()
        async throws {
        let collectionID = try testCollectionIDs().0
        let preparationStarted = expectation(
            description: "Thumbnail preparation started"
        )
        let planner = MobilePlaybackSessionTestThumbnailWindowPlanner(
            startedExpectation: preparationStarted
        )
        var applicationChecks = 0
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in
                    MobilePlaybackSessionTestViewingTracker()
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {},
                makeCollectionBrowseThumbnailWindowPlanner: { _ in planner },
                installDownloadableMediaWindow: { _, _ in
                    applicationChecks += 1
                }
            )
        )
        let session = registry.startSession(
            config: MobilePlayerConfig(initialItemId: collectionID)
        )
        var completions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        session.prepareCollectionBrowseThumbnailWindow(
            centeredAt: 0,
            direction: .forward,
            prefetchStride: 9,
            columnCount: 5,
            quality: .smallThumbnail,
            requiredTokenRange: nil,
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: [],
            completion: { completions.append($0) }
        )
        await fulfillment(of: [preparationStarted], timeout: 1)

        session.cancelPendingCollectionBrowseThumbnailWindowPreparation()
        XCTAssertEqual(completions, [.superseded])
        await planner.resume()

        XCTAssertEqual(completions, [.superseded])
        XCTAssertEqual(applicationChecks, 0)
        session.stopAndDisconnect()
    }

    func testThumbnailWindowPreparationReportsPlannedAndUnavailable()
        async throws {
        let collectionID = try testCollectionIDs().0
        let imageSourcesCache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/session-result/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                smallThumbnailDescriptor: descriptor,
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let registry = MobilePlaybackSessionRegistry(dependencies: .init(
            makeViewingSessionTracker: { _ in
                MobilePlaybackSessionTestViewingTracker()
            },
            clearActiveMediaWindow: { _ in },
            cancelAllMediaDownloads: {},
            makeCollectionBrowseImageSourcesCache: {
                imageSourcesCache
            },
            installDownloadableMediaWindow: { _, _ in
                XCTFail("A planned window must not be installed")
            }
        ))
        let session = registry.startSession(
            config: MobilePlayerConfig(initialItemId: collectionID)
        )
        var plannedCompletions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        let plannedCompletion = expectation(description: "Window planned")

        prepareTestThumbnailWindow(
            on: session,
            completion: {
                plannedCompletions.append($0)
                plannedCompletion.fulfill()
            },
            shouldApply: { false }
        )

        await fulfillment(of: [plannedCompletion], timeout: 1)
        XCTAssertEqual(plannedCompletions, [.planned])
        session.stopAndDisconnect()

        let unavailableCache = MobileCollectionBrowseImageSourcesCache {
            _, _ in nil
        }
        let unavailableRegistry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in
                    MobilePlaybackSessionTestViewingTracker()
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {},
                makeCollectionBrowseImageSourcesCache: {
                    unavailableCache
                },
                installDownloadableMediaWindow: { _, _ in
                    XCTFail("An unavailable window must not be installed")
                }
            )
        )
        let unavailableSession = unavailableRegistry.startSession(
            config: MobilePlayerConfig(initialItemId: collectionID)
        )
        var unavailableCompletions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        let unavailableCompletion = expectation(
            description: "Window unavailable"
        )

        prepareTestThumbnailWindow(
            on: unavailableSession,
            completion: {
                unavailableCompletions.append($0)
                unavailableCompletion.fulfill()
            }
        )

        await fulfillment(of: [unavailableCompletion], timeout: 1)
        XCTAssertEqual(unavailableCompletions, [.unavailable])
        unavailableSession.stopAndDisconnect()
    }

    func testThumbnailWindowPreparationOrderingAcrossSessions()
        async throws {
        let newerCommitted = try await thumbnailWindowOrderingResult(
            cancelsNewerPreparation: false
        )
        XCTAssertEqual(newerCommitted.newerCompletions, [.committed])
        XCTAssertEqual(newerCommitted.olderCompletions, [.planned])
        XCTAssertEqual(
            newerCommitted.installedCollectionIDs,
            [newerCommitted.newerCollectionID]
        )

        let newerCancelled = try await thumbnailWindowOrderingResult(
            cancelsNewerPreparation: true
        )
        XCTAssertEqual(newerCancelled.newerCompletions, [.superseded])
        XCTAssertEqual(newerCancelled.olderCompletions, [.committed])
        XCTAssertEqual(
            newerCancelled.installedCollectionIDs,
            [newerCancelled.olderCollectionID]
        )
    }

    func testThumbnailWindowReplacementIsReentrantSafe() async throws {
        let collectionID = try testCollectionIDs().0
        let imageSourcesCache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/session-reentrant/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                smallThumbnailDescriptor: descriptor,
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let planner = MobileCollectionBrowseThumbnailWindowPlanner(
            imageSourcesCache: imageSourcesCache
        )
        var installedTokenIndices = [Int]()
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in
                    MobilePlaybackSessionTestViewingTracker()
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {},
                makeCollectionBrowseImageSourcesCache: {
                    imageSourcesCache
                },
                makeCollectionBrowseThumbnailWindowPlanner: { _ in planner },
                installDownloadableMediaWindow: { window, _ in
                    installedTokenIndices.append(
                        window.currentDescriptor.tokenIndex
                    )
                }
            )
        )
        let session = registry.startSession(
            config: MobilePlayerConfig(initialItemId: collectionID)
        )
        var firstCompletions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        var secondCompletions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        var thirdCompletions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        let firstCompletion = expectation(description: "First window superseded")
        let secondCompletion = expectation(description: "Second window superseded")
        let thirdCompletion = expectation(description: "Third window committed")
        var thirdPreparationStarted = false
        prepareTestThumbnailWindow(
            on: session,
            tokenIndex: 0,
            completion: { result in
                firstCompletions.append(result)
                firstCompletion.fulfill()
                guard result == .superseded,
                      !thirdPreparationStarted else { return }
                thirdPreparationStarted = true
                self.prepareTestThumbnailWindow(
                    on: session,
                    tokenIndex: 0,
                    completion: {
                        thirdCompletions.append($0)
                        thirdCompletion.fulfill()
                    }
                )
            }
        )
        prepareTestThumbnailWindow(
            on: session,
            tokenIndex: 0,
            completion: {
                secondCompletions.append($0)
                secondCompletion.fulfill()
            }
        )

        await fulfillment(
            of: [firstCompletion, secondCompletion, thirdCompletion],
            timeout: 1
        )

        XCTAssertEqual(firstCompletions, [.superseded])
        XCTAssertEqual(secondCompletions, [.superseded])
        XCTAssertEqual(thirdCompletions, [.committed])
        XCTAssertEqual(installedTokenIndices, [0])
        session.stopAndDisconnect()
    }

    private func thumbnailWindowOrderingResult(
        cancelsNewerPreparation: Bool
    ) async throws -> (
        olderCollectionID: String,
        newerCollectionID: String,
        olderCompletions: [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ],
        newerCompletions: [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ],
        installedCollectionIDs: [String]
    ) {
        let (olderCollectionID, newerCollectionID) = try testCollectionIDs()
        let olderStarted = expectation(description: "Older preparation started")
        let newerStarted = expectation(description: "Newer preparation started")
        let olderPlanner = MobilePlaybackSessionTestThumbnailWindowPlanner(
            startedExpectation: olderStarted
        )
        let newerPlanner = MobilePlaybackSessionTestThumbnailWindowPlanner(
            startedExpectation: newerStarted
        )
        var planners = [
            olderPlanner as any MobileCollectionBrowseThumbnailWindowPlanning,
            newerPlanner as any MobileCollectionBrowseThumbnailWindowPlanning
        ]
        var installedCollectionIDs = [String]()
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in
                    MobilePlaybackSessionTestViewingTracker()
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {},
                makeCollectionBrowseThumbnailWindowPlanner: {
                    _ in
                    planners.removeFirst()
                },
                installDownloadableMediaWindow: { window, _ in
                    installedCollectionIDs.append(
                        window.currentDescriptor.collectionId
                    )
                }
            )
        )
        let olderSession = registry.startSession(
            config: MobilePlayerConfig(initialItemId: olderCollectionID)
        )
        let newerSession = registry.startSession(
            config: MobilePlayerConfig(initialItemId: newerCollectionID)
        )
        var olderCompletions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        var newerCompletions = [
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ]()
        let olderCompletion = expectation(description: "Older window completed")
        let newerCompletion = expectation(description: "Newer window completed")
        prepareTestThumbnailWindow(
            on: olderSession,
            completion: {
                olderCompletions.append($0)
                olderCompletion.fulfill()
            }
        )
        await fulfillment(of: [olderStarted], timeout: 1)
        prepareTestThumbnailWindow(
            on: newerSession,
            completion: {
                newerCompletions.append($0)
                newerCompletion.fulfill()
            }
        )
        await fulfillment(of: [newerStarted], timeout: 1)

        if cancelsNewerPreparation {
            newerSession
                .cancelPendingCollectionBrowseThumbnailWindowPreparation()
        }
        await newerPlanner.resume()
        await fulfillment(of: [newerCompletion], timeout: 1)
        await olderPlanner.resume()
        await fulfillment(of: [olderCompletion], timeout: 1)
        olderSession.stopAndDisconnect()
        newerSession.stopAndDisconnect()

        return (
            olderCollectionID,
            newerCollectionID,
            olderCompletions,
            newerCompletions,
            installedCollectionIDs
        )
    }

    private func prepareTestThumbnailWindow(
        on session: MobilePlaybackSession,
        tokenIndex: Int = 0,
        completion: @escaping @MainActor (
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ) -> Void,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) {
        session.prepareCollectionBrowseThumbnailWindow(
            centeredAt: tokenIndex,
            direction: .forward,
            prefetchStride: 9,
            columnCount: 5,
            quality: .smallThumbnail,
            requiredTokenRange: nil,
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: [],
            shouldApply: shouldApply,
            completion: completion
        )
    }

    private func waitUntilPrepareStarted(
        _ tracker: MobilePlaybackSessionTestViewingTracker
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await tracker.waitUntilPrepareStarted()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return false
            }
            let didStart = await group.next() ?? false
            group.cancelAll()
            return didStart
        }
    }
}
