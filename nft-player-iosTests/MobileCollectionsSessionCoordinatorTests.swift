// ∅ 2026 lil org

import Foundation
import XCTest
@testable import nft_player_ios

nonisolated final class MobileCollectionsSessionCoordinatorTests: XCTestCase {
    override func tearDown() async throws {
        await PlayerPersistenceUpdates.flush()
        try await super.tearDown()
    }
}

@MainActor
extension MobileCollectionsSessionCoordinatorTests {

    func testInitialRefreshLoadsProgressResetsScrollAndPrewarms() async throws {
        let item = try firstCollectionItem()
        let progress = makeProgress(collectionId: item.id, tokenIndex: 3)
        let snapshot = makeSnapshot([progress])
        let store = CoordinatorProgressStore(snapshot: snapshot)
        let fixture = try makeFixture(
            store: store,
            prewarmCollectionIds: ["prewarm-a", "prewarm-b"]
        )

        XCTAssertFalse(fixture.coordinator.isReadyToRevealNavigation)

        await fixture.coordinator.refreshViewingProgress(
            id: fixture.coordinator.viewingProgressRefreshID
        )

        XCTAssertTrue(fixture.coordinator.hasLoadedViewingProgress)
        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)
        XCTAssertEqual(fixture.coordinator.continueViewingScrollResetID, 1)
        XCTAssertEqual(fixture.coordinator.recentContinueViewingProgresses, [progress])
        XCTAssertEqual(
            fixture.recorder.prewarmRequests,
            [
                CoordinatorPrewarmRequest(
                    progress: progress,
                    collectionIds: ["prewarm-a", "prewarm-b"]
                ),
            ]
        )
    }

    func testStaleRefreshIsRejectedWhileRefreshFlagsCoalesce() async throws {
        let item = try firstCollectionItem()
        let staleProgress = makeProgress(collectionId: item.id, tokenIndex: 1)
        let freshProgress = makeProgress(collectionId: item.id, tokenIndex: 6)
        let snapshots = CoordinatorValueQueue<PlayerViewingProgressSnapshot>()
        let store = CoordinatorProgressStore(
            snapshot: .empty,
            snapshotQueue: snapshots
        )
        let fixture = try makeFixture(store: store)

        await snapshots.send(.empty)
        await fixture.coordinator.refreshViewingProgress(id: 0)
        XCTAssertEqual(fixture.coordinator.continueViewingScrollResetID, 1)
        XCTAssertEqual(fixture.recorder.prewarmRequests.count, 1)

        fixture.coordinator.viewingProgressDidChange()
        let staleRefreshID = fixture.coordinator.viewingProgressRefreshID
        fixture.coordinator.applicationDidBecomeActive()
        let currentRefreshID = fixture.coordinator.viewingProgressRefreshID

        let staleTask = Task {
            await fixture.coordinator.refreshViewingProgress(id: staleRefreshID)
        }
        await assertWaiterCount(1, in: snapshots)
        await snapshots.send(makeSnapshot([staleProgress]))
        await staleTask.value

        XCTAssertEqual(fixture.coordinator.viewingProgressSnapshot, .empty)
        XCTAssertEqual(fixture.coordinator.continueViewingScrollResetID, 1)
        XCTAssertEqual(fixture.recorder.prewarmRequests.count, 1)

        let currentTask = Task {
            await fixture.coordinator.refreshViewingProgress(id: currentRefreshID)
        }
        await assertWaiterCount(1, in: snapshots)
        await snapshots.send(makeSnapshot([freshProgress]))
        await currentTask.value

        XCTAssertEqual(
            fixture.coordinator.viewingProgressSnapshot,
            makeSnapshot([freshProgress])
        )
        XCTAssertEqual(fixture.coordinator.continueViewingScrollResetID, 2)
        XCTAssertEqual(fixture.recorder.prewarmRequests.count, 2)
        XCTAssertEqual(fixture.recorder.prewarmRequests.last?.progress, freshProgress)
    }

    func testUpdateRefreshesWithNewInputsAndObservesWidgetState() async throws {
        let items = try firstCollectionItems(count: 2)
        let removedProgress = makeProgress(collectionId: items[0].id, tokenIndex: 1)
        let visibleProgress = makeProgress(collectionId: items[1].id, tokenIndex: 2)
        let fixture = try makeFixture(store: CoordinatorProgressStore())

        await fixture.coordinator.refreshViewingProgress(id: 0)
        fixture.recorder.prewarmRequests.removeAll()

        fixture.coordinator.update(
            collectionItems: [items[1]],
            widgetLaunchPresentationState: fixture.widgetState,
            dependencies: fixture.dependencies,
            initialCollectionIdsForPrewarm: { ["collection-update"] }
        )
        XCTAssertEqual(fixture.coordinator.viewingProgressRefreshID, 1)

        let updatedFixture = try makeFixture(
            store: CoordinatorProgressStore(
                snapshot: makeSnapshot([removedProgress, visibleProgress])
            )
        )
        let widgetURL = try widgetURL(collectionId: items[1].id)
        prepareWidgetLaunch(widgetURL, fixture: updatedFixture)
        fixture.coordinator.update(
            collectionItems: [items[1]],
            widgetLaunchPresentationState: updatedFixture.widgetState,
            dependencies: updatedFixture.dependencies,
            initialCollectionIdsForPrewarm: { ["updated-prewarm"] }
        )

        XCTAssertEqual(fixture.coordinator.viewingProgressRefreshID, 2)
        XCTAssertTrue(fixture.coordinator.isPreparingWidgetPlayerPresentation)
        await fixture.coordinator.refreshViewingProgress(id: 2)
        XCTAssertEqual(
            fixture.coordinator.recentContinueViewingProgresses,
            [visibleProgress]
        )
        XCTAssertEqual(
            updatedFixture.recorder.prewarmRequests,
            [
                CoordinatorPrewarmRequest(
                    progress: visibleProgress,
                    collectionIds: ["updated-prewarm"]
                ),
            ]
        )
    }

    func testNormalOpenRestoresAnimatedPresentation() async throws {
        let item = try firstCollectionItem()
        let fixture = try makeFixture(
            store: CoordinatorProgressStore()
        )

        let didOpenInstantly = await fixture.coordinator
            .requestCollectionOpen(
                collectionId: item.id,
                transition: .instant
            ).value
        XCTAssertTrue(didOpenInstantly)
        XCTAssertFalse(
            fixture.coordinator.playerPresentationTransition
                .animatesNavigationTransition
        )

        let didOpenNormally = await fixture.coordinator
            .requestCollectionOpen(collectionId: item.id).value
        XCTAssertTrue(didOpenNormally)
        XCTAssertTrue(
            fixture.coordinator.playerPresentationTransition
                .animatesNavigationTransition
        )
    }

    func testCollectionOpenUsesSavedProgressWhenAvailable() async throws {
        await PlayerPersistenceUpdates.flush()
        let item = try firstCollectionItem()
        let progress = makeProgress(collectionId: item.id, tokenIndex: 4)
        let store = CoordinatorProgressStore(
            progressByCollectionId: [item.id: progress]
        )
        let fixture = try makeFixture(store: store)

        let didOpen = await fixture.coordinator
            .requestResumeViewing(progress).value
        await PlayerPersistenceUpdates.flush()

        XCTAssertTrue(didOpen)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, item.id)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialTokenId, progress.tokenId)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialTokenIndex, 4)
        XCTAssertTrue(
            fixture.coordinator.playerPresentationTransition
                .animatesNavigationTransition
        )
        XCTAssertEqual(
            fixture.coordinator.playerConfig?.continueViewingCollectionId,
            item.id
        )
        XCTAssertEqual(fixture.recorder.hapticCount, 1)
        let metrics = await store.metrics()
        XCTAssertEqual(metrics.appliedUpdates.map(\.collectionId), [item.id])
        XCTAssertEqual(metrics.orderingEvents, ["present", "apply"])
    }

    func testCollectionOpenWithoutProgressStartsAtCollection() async throws {
        await PlayerPersistenceUpdates.flush()
        let item = try firstCollectionItem()
        let store = CoordinatorProgressStore()
        let fixture = try makeFixture(store: store)

        let didOpen = await fixture.coordinator
            .requestCollectionOpen(collectionId: item.id).value
        await PlayerPersistenceUpdates.flush()

        XCTAssertTrue(didOpen)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, item.id)
        XCTAssertNil(fixture.coordinator.playerConfig?.initialTokenId)
        XCTAssertNil(fixture.coordinator.playerConfig?.initialTokenIndex)
        XCTAssertEqual(
            fixture.recorder.preparedRequests,
            [
                CoordinatorPreparedRequest(
                    initialItemId: item.id,
                    initialTokenId: nil,
                    initialTokenIndex: nil,
                    continueViewingCollectionId: item.id,
                    widgetTokenInsertion: nil
                ),
            ]
        )
    }

    func testSupersededAsynchronousOpenOnlyPresentsLatestRequest() async throws {
        await PlayerPersistenceUpdates.flush()
        let items = try firstCollectionItems(count: 2)
        let progressResults = CoordinatorValueQueue<MobileViewingProgress?>()
        let store = CoordinatorProgressStore(progressQueue: progressResults)
        let fixture = try makeFixture(store: store)

        let firstTask = fixture.coordinator.requestCollectionOpen(
            collectionId: items[0].id
        )
        await assertWaiterCount(1, in: progressResults)
        let secondTask = fixture.coordinator.requestCollectionOpen(
            collectionId: items[1].id
        )
        await assertWaiterCount(2, in: progressResults)

        await progressResults.send(
            makeProgress(collectionId: items[0].id, tokenIndex: 2)
        )
        await progressResults.send(nil)

        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        await PlayerPersistenceUpdates.flush()

        XCTAssertFalse(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, items[1].id)
        XCTAssertEqual(fixture.recorder.preparedRequests.count, 1)
        XCTAssertEqual(fixture.recorder.hapticCount, 1)
    }

    func testProgressChangeWaitsUntilMatchingPlayerDismissal() async throws {
        await PlayerPersistenceUpdates.flush()
        let item = try firstCollectionItem()
        let fixture = try makeFixture(store: CoordinatorProgressStore())

        let didOpen = await fixture.coordinator.requestCollectionOpen(
            collectionId: item.id,
            transition: .instant
        ).value
        XCTAssertTrue(
            didOpen
        )
        let config = try XCTUnwrap(fixture.coordinator.playerConfig)
        XCTAssertFalse(
            fixture.coordinator.playerPresentationTransition
                .animatesNavigationTransition
        )

        fixture.coordinator.viewingProgressDidChange()
        XCTAssertEqual(fixture.coordinator.viewingProgressRefreshID, 0)

        fixture.coordinator.dismissPlayer(MobilePlayerConfig())
        XCTAssertEqual(fixture.coordinator.playerConfig?.id, config.id)
        XCTAssertEqual(fixture.coordinator.viewingProgressRefreshID, 0)

        fixture.coordinator.dismissPlayer(config)
        XCTAssertNil(fixture.coordinator.playerConfig)
        XCTAssertTrue(
            fixture.coordinator.playerPresentationTransition
                .animatesNavigationTransition
        )
        XCTAssertEqual(fixture.coordinator.viewingProgressRefreshID, 1)

        fixture.coordinator.viewingProgressDidChange()
        XCTAssertEqual(fixture.coordinator.viewingProgressRefreshID, 2)
    }

    func testInvalidAndInvisibleWidgetLinksAreRejectedAndUnstaged() async throws {
        let fixture = try makeFixture(store: CoordinatorProgressStore())
        let invalidURL = try XCTUnwrap(
            URL(string: "https://example.com/collection?id=invalid")
        )

        XCTAssertNil(fixture.coordinator.handleOpenURL(invalidURL))
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)

        let invisibleURL = try XCTUnwrap(
            WidgetDeepLink.collection(id: "invisible", tokenId: nil).url
        )
        fixture.widgetState.prepareForIncomingURLs(
            [invisibleURL],
            isApplicationLaunch: true,
            isSupportedCollection: { _ in true }
        )
        XCTAssertTrue(fixture.widgetState.isPreparingWidgetPlayerPresentation)

        XCTAssertNil(fixture.coordinator.handleOpenURL(invisibleURL))
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)
        XCTAssertNil(fixture.coordinator.playerConfig)
    }

    func testCollectionWidgetHandoffFinishesOnlyAfterMatchingPresentation() async throws {
        await PlayerPersistenceUpdates.flush()
        let item = try firstCollectionItem()
        let fixture = try makeFixture(store: CoordinatorProgressStore())
        let url = try widgetURL(collectionId: item.id)
        prepareWidgetLaunch(url, fixture: fixture)

        let task = try XCTUnwrap(fixture.coordinator.handleOpenURL(url))
        await task.value
        let config = try XCTUnwrap(fixture.coordinator.playerConfig)

        XCTAssertTrue(fixture.widgetState.isPreparingWidgetPlayerPresentation)
        XCTAssertFalse(
            fixture.coordinator.playerPresentationTransition
                .animatesNavigationTransition
        )

        fixture.coordinator.didPresentPlayer(MobilePlayerConfig())
        XCTAssertTrue(fixture.widgetState.isPreparingWidgetPlayerPresentation)

        fixture.coordinator.didPresentPlayer(config)
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)
    }

    func testWidgetTokenInsertionAndFallbackPrepareExpectedConfigurations() async throws {
        await PlayerPersistenceUpdates.flush()
        let item = try firstCollectionItem()
        let insertion = makeWidgetInsertion(collectionId: item.id)
        let insertionStore = CoordinatorProgressStore()
        let insertionFixture = try makeFixture(
            store: insertionStore,
            widgetTokenInsertion: insertion
        )
        let tokenURL = try widgetURL(
            collectionId: item.id,
            tokenId: insertion.insertedToken.id
        )

        let insertionTask = try XCTUnwrap(
            insertionFixture.coordinator.handleOpenURL(tokenURL)
        )
        await insertionTask.value
        await PlayerPersistenceUpdates.flush()

        XCTAssertEqual(
            insertionFixture.coordinator.playerConfig?.widgetTokenInsertion,
            insertion
        )
        XCTAssertEqual(
            insertionFixture.recorder.widgetRequests.first?.tokenId,
            insertion.insertedToken.id
        )
        let insertionMetrics = await insertionStore.metrics()
        XCTAssertEqual(insertionMetrics.savedProgresses.map(\.collectionId), [item.id])
        XCTAssertEqual(
            insertionMetrics.orderingEvents,
            ["present", "save", "apply"]
        )

        let fallbackStore = CoordinatorProgressStore()
        let fallbackFixture = try makeFixture(store: fallbackStore)
        let fallbackTask = try XCTUnwrap(
            fallbackFixture.coordinator.handleOpenURL(tokenURL)
        )
        await fallbackTask.value
        await PlayerPersistenceUpdates.flush()

        XCTAssertNil(fallbackFixture.coordinator.playerConfig?.widgetTokenInsertion)
        XCTAssertEqual(fallbackFixture.coordinator.playerConfig?.initialItemId, item.id)
        XCTAssertEqual(fallbackFixture.recorder.flushCount, 2)
        let fallbackMetrics = await fallbackStore.metrics()
        XCTAssertEqual(
            fallbackMetrics.requestedProgressCollectionIds,
            [item.id, item.id]
        )
    }

    func testRejectedAndCancelledWidgetHandoffsClearPresentationStaging() async throws {
        await PlayerPersistenceUpdates.flush()
        let item = try firstCollectionItem()
        let rejectedFixture = try makeFixture(
            store: CoordinatorProgressStore(allowsContinueViewingUpdate: false)
        )
        let rejectedURL = try widgetURL(collectionId: item.id)
        prepareWidgetLaunch(rejectedURL, fixture: rejectedFixture)

        let rejectedTask = try XCTUnwrap(
            rejectedFixture.coordinator.handleOpenURL(rejectedURL)
        )
        await rejectedTask.value

        XCTAssertNil(rejectedFixture.coordinator.playerConfig)
        XCTAssertFalse(
            rejectedFixture.widgetState.isPreparingWidgetPlayerPresentation
        )

        let flushQueue = CoordinatorValueQueue<Void>()
        let cancelledFixture = try makeFixture(
            store: CoordinatorProgressStore(),
            flushQueue: flushQueue
        )
        let cancelledURL = try widgetURL(collectionId: item.id)
        prepareWidgetLaunch(cancelledURL, fixture: cancelledFixture)
        let cancelledTask = try XCTUnwrap(
            cancelledFixture.coordinator.handleOpenURL(cancelledURL)
        )
        await assertWaiterCount(1, in: flushQueue)

        cancelledFixture.coordinator.cancel()
        await flushQueue.send(())
        await cancelledTask.value

        XCTAssertNil(cancelledFixture.coordinator.playerConfig)
        XCTAssertFalse(
            cancelledFixture.widgetState.isPreparingWidgetPlayerPresentation
        )
    }

    func testConfigurationUpdateClearsBlockedWidgetHandoff() async throws {
        let items = try firstCollectionItems(count: 2)
        let flushQueue = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(
            store: CoordinatorProgressStore(),
            flushQueue: flushQueue
        )
        let url = try widgetURL(collectionId: items[0].id)
        prepareWidgetLaunch(url, fixture: fixture)
        let task = try XCTUnwrap(
            fixture.coordinator.handleOpenURL(url)
        )
        await assertWaiterCount(1, in: flushQueue)

        fixture.coordinator.update(
            collectionItems: [items[0]],
            widgetLaunchPresentationState: fixture.widgetState,
            dependencies: fixture.dependencies,
            initialCollectionIdsForPrewarm: { [] }
        )

        XCTAssertFalse(
            fixture.widgetState.isPreparingWidgetPlayerPresentation
        )
        await flushQueue.send(())
        await task.value
        XCTAssertNil(fixture.coordinator.playerConfig)
    }

    func testPresentationGateDefersThenPresentsOrDiscardsHandoff() async throws {
        await PlayerPersistenceUpdates.flush()
        let item = try firstCollectionItem()
        let fixture = try makeFixture(store: CoordinatorProgressStore())

        let openTask = fixture.coordinator.requestCollectionOpen(
            collectionId: item.id
        )
        let continueResolution = try XCTUnwrap(
            fixture.coordinator.resolutionForPendingPresentationRequest()
        )
        let didOpen = await openTask.value
        XCTAssertTrue(didOpen)
        XCTAssertNil(fixture.coordinator.playerConfig)

        continueResolution(false)
        XCTAssertNotNil(fixture.coordinator.playerConfig)
        await PlayerPersistenceUpdates.flush()

        let handoffFixture = try makeFixture(store: CoordinatorProgressStore())
        let url = try widgetURL(collectionId: item.id)
        prepareWidgetLaunch(url, fixture: handoffFixture)
        let handoffTask = try XCTUnwrap(
            handoffFixture.coordinator.handleOpenURL(url)
        )
        let discardResolution = try XCTUnwrap(
            handoffFixture.coordinator.resolutionForPendingPresentationRequest()
        )

        await handoffTask.value
        XCTAssertNil(handoffFixture.coordinator.playerConfig)
        XCTAssertTrue(handoffFixture.widgetState.isPreparingWidgetPlayerPresentation)

        discardResolution(true)
        XCTAssertNil(handoffFixture.coordinator.playerConfig)
        XCTAssertFalse(
            handoffFixture.widgetState.isPreparingWidgetPlayerPresentation
        )
    }

    private func makeFixture(
        store: CoordinatorProgressStore,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil,
        prewarmCollectionIds: [String] = ["prewarm"],
        flushQueue: CoordinatorValueQueue<Void>? = nil
    ) throws -> CoordinatorFixture {
        let items = try firstCollectionItems(count: 2)
        let widgetState = WidgetLaunchPresentationState()
        let recorder = CoordinatorRecorder()
        let visibleCollectionIds = Set(items.map(\.id))
        let dependencies = MobileCollectionsSessionCoordinator.Dependencies(
            progressStore: store,
            flushPersistenceUpdates: {
                recorder.flushCount += 1
                if let flushQueue {
                    await flushQueue.next()
                }
            },
            canOpenCollection: { visibleCollectionIds.contains($0) },
            makeWidgetTokenInsertion: { collectionId, tokenId, progress in
                recorder.widgetRequests.append(
                    CoordinatorWidgetRequest(
                        collectionId: collectionId,
                        tokenId: tokenId,
                        progress: progress
                    )
                )
                return widgetTokenInsertion
            },
            preparePlayerConfig: { request in
                recorder.preparedRequests.append(
                    CoordinatorPreparedRequest(request: request)
                )
                return MobilePlayerConfig(
                    initialItemId: request.initialItemId,
                    initialTokenId: request.initialTokenId,
                    initialTokenIndex: request.initialTokenIndex,
                    continueViewingCollectionId:
                        request.continueViewingCollectionId,
                    widgetTokenInsertion: request.widgetTokenInsertion
                )
            },
            schedulePlayerPrewarm: { progress, collectionIds in
                recorder.prewarmRequests.append(
                    CoordinatorPrewarmRequest(
                        progress: progress,
                        collectionIds: collectionIds
                    )
                )
            },
            emitSelectionHaptic: {
                recorder.hapticCount += 1
                store.recordPresentation()
            }
        )
        let coordinator = MobileCollectionsSessionCoordinator(
            collectionItems: items,
            widgetLaunchPresentationState: widgetState,
            dependencies: dependencies,
            initialCollectionIdsForPrewarm: { prewarmCollectionIds }
        )
        return CoordinatorFixture(
            coordinator: coordinator,
            widgetState: widgetState,
            recorder: recorder,
            dependencies: dependencies
        )
    }

    private func firstCollectionItem() throws -> MobileCollectionItem {
        try XCTUnwrap(MobileCollectionCatalog.allItems.first)
    }

    private func firstCollectionItems(count: Int) throws -> [MobileCollectionItem] {
        let items = Array(MobileCollectionCatalog.allItems.prefix(count))
        guard items.count == count else {
            throw XCTSkip("The mobile catalog does not contain enough collections")
        }
        return items
    }

    private func makeProgress(
        collectionId: String,
        tokenIndex: Int
    ) -> MobileViewingProgress {
        MobileViewingProgress(
            collectionId: collectionId,
            collectionName: "Collection \(collectionId)",
            tokenId: "token-\(tokenIndex)",
            tokenIndex: tokenIndex,
            tokenCount: 10,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(tokenIndex + 1))
        )
    }

    private func makeSnapshot(
        _ progresses: [MobileViewingProgress]
    ) -> PlayerViewingProgressSnapshot {
        PlayerViewingProgressSnapshot(
            progressByCollectionId: Dictionary(
                uniqueKeysWithValues: progresses.map { ($0.collectionId, $0) }
            ),
            percentagesByCollectionId: Dictionary(
                uniqueKeysWithValues: progresses.map {
                    ($0.collectionId, $0.percent)
                }
            ),
            viewedToEndCollectionIds: Set(
                progresses.filter(\.hasBeenViewedToEnd).map(\.collectionId)
            ),
            recentContinueViewingProgresses: progresses
        )
    }

    private func makeWidgetInsertion(
        collectionId: String
    ) -> PlayerWidgetTokenInsertion {
        let anchor = makeProgress(collectionId: collectionId, tokenIndex: 2)
        return PlayerWidgetTokenInsertion(
            insertedToken: GeneratedToken(
                fullCollectionId: collectionId,
                collectionName: anchor.collectionName,
                address: collectionId,
                id: "widget-token",
                html: "",
                displayName: "Widget token",
                displayTokenId: "widget-token",
                url: nil
            ),
            insertedTokenIndex: 3,
            anchorProgress: anchor,
            isAnchorProgressResolved: true
        )
    }

    private func widgetURL(
        collectionId: String,
        tokenId: String? = nil
    ) throws -> URL {
        try XCTUnwrap(
            WidgetDeepLink.collection(id: collectionId, tokenId: tokenId).url
        )
    }

    private func prepareWidgetLaunch(
        _ url: URL,
        fixture: CoordinatorFixture
    ) {
        fixture.widgetState.prepareForIncomingURLs(
            [url],
            isApplicationLaunch: true,
            isSupportedCollection: { _ in true }
        )
    }

    private func assertWaiterCount<Value: Sendable>(
        _ expectedCount: Int,
        in queue: CoordinatorValueQueue<Value>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if await queue.waiterCount == expectedCount {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        let actualCount = await queue.waiterCount
        XCTFail(
            "Expected \(expectedCount) waiters, found \(actualCount)",
            file: file,
            line: line
        )
    }
}

private struct CoordinatorFixture {
    let coordinator: MobileCollectionsSessionCoordinator
    let widgetState: WidgetLaunchPresentationState
    let recorder: CoordinatorRecorder
    let dependencies: MobileCollectionsSessionCoordinator.Dependencies
}

@MainActor
private final class CoordinatorRecorder {
    var flushCount = 0
    var hapticCount = 0
    var preparedRequests = [CoordinatorPreparedRequest]()
    var prewarmRequests = [CoordinatorPrewarmRequest]()
    var widgetRequests = [CoordinatorWidgetRequest]()
}

private struct CoordinatorPreparedRequest: Equatable {
    let initialItemId: String?
    let initialTokenId: String?
    let initialTokenIndex: Int?
    let continueViewingCollectionId: String?
    let widgetTokenInsertion: PlayerWidgetTokenInsertion?

    init(
        initialItemId: String?,
        initialTokenId: String?,
        initialTokenIndex: Int?,
        continueViewingCollectionId: String?,
        widgetTokenInsertion: PlayerWidgetTokenInsertion?
    ) {
        self.initialItemId = initialItemId
        self.initialTokenId = initialTokenId
        self.initialTokenIndex = initialTokenIndex
        self.continueViewingCollectionId = continueViewingCollectionId
        self.widgetTokenInsertion = widgetTokenInsertion
    }

    init(
        request: MobileCollectionsSessionCoordinator.PlayerConfigurationRequest
    ) {
        self.init(
            initialItemId: request.initialItemId,
            initialTokenId: request.initialTokenId,
            initialTokenIndex: request.initialTokenIndex,
            continueViewingCollectionId: request.continueViewingCollectionId,
            widgetTokenInsertion: request.widgetTokenInsertion
        )
    }
}

private struct CoordinatorPrewarmRequest: Equatable {
    let progress: MobileViewingProgress?
    let collectionIds: [String]
}

private struct CoordinatorWidgetRequest: Equatable {
    let collectionId: String
    let tokenId: String
    let progress: MobileViewingProgress?
}

private actor CoordinatorProgressStore: MobileCollectionsProgressStoring {
    struct Metrics: Sendable {
        let requestedProgressCollectionIds: [String]
        let preparedUpdates: [PlayerContinueViewingUpdate]
        let savedProgresses: [MobileViewingProgress]
        let appliedUpdates: [PlayerContinueViewingUpdate]
        let orderingEvents: [String]
    }

    private var progressByCollectionId: [String: MobileViewingProgress]
    private var snapshot: PlayerViewingProgressSnapshot
    private let snapshotQueue:
        CoordinatorValueQueue<PlayerViewingProgressSnapshot>?
    private let progressQueue: CoordinatorValueQueue<MobileViewingProgress?>?
    private let allowsContinueViewingUpdate: Bool
    private var requestedProgressCollectionIds = [String]()
    private var preparedUpdates = [PlayerContinueViewingUpdate]()
    private var savedProgresses = [MobileViewingProgress]()
    private var appliedUpdates = [PlayerContinueViewingUpdate]()
    private nonisolated let orderingRecorder = CoordinatorOrderingRecorder()

    init(
        progressByCollectionId: [String: MobileViewingProgress] = [:],
        snapshot: PlayerViewingProgressSnapshot = .empty,
        snapshotQueue: CoordinatorValueQueue<PlayerViewingProgressSnapshot>? = nil,
        progressQueue: CoordinatorValueQueue<MobileViewingProgress?>? = nil,
        allowsContinueViewingUpdate: Bool = true
    ) {
        self.progressByCollectionId = progressByCollectionId
        self.snapshot = snapshot
        self.snapshotQueue = snapshotQueue
        self.progressQueue = progressQueue
        self.allowsContinueViewingUpdate = allowsContinueViewingUpdate
    }

    func progress(collectionId: String) async -> MobileViewingProgress? {
        requestedProgressCollectionIds.append(collectionId)
        if let progressQueue {
            return await progressQueue.next()
        }
        return progressByCollectionId[collectionId]
    }

    func progressSnapshot() async -> PlayerViewingProgressSnapshot {
        if let snapshotQueue {
            return await snapshotQueue.next()
        }
        return snapshot
    }

    func prepareContinueViewingUpdate(
        collectionId: String,
        isRemoved: Bool
    ) async -> PlayerContinueViewingUpdate? {
        guard allowsContinueViewingUpdate else { return nil }
        let update = PlayerContinueViewingUpdate(
            collectionId: collectionId,
            updatedAt: Date(timeIntervalSince1970: 1),
            isRemoved: isRemoved
        )
        preparedUpdates.append(update)
        return update
    }

    func save(_ progress: MobileViewingProgress) async -> Bool {
        orderingRecorder.record("save")
        savedProgresses.append(progress)
        return true
    }

    func applyContinueViewingUpdate(
        _ update: PlayerContinueViewingUpdate
    ) async {
        orderingRecorder.record("apply")
        appliedUpdates.append(update)
    }

    nonisolated func recordPresentation() {
        orderingRecorder.record("present")
    }

    func metrics() -> Metrics {
        Metrics(
            requestedProgressCollectionIds: requestedProgressCollectionIds,
            preparedUpdates: preparedUpdates,
            savedProgresses: savedProgresses,
            appliedUpdates: appliedUpdates,
            orderingEvents: orderingRecorder.snapshot()
        )
    }
}

nonisolated private final class CoordinatorOrderingRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events = [String]()

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private actor CoordinatorValueQueue<Value: Sendable> {
    private var values = [Value]()
    private var waiters = [CheckedContinuation<Value, Never>]()

    var waiterCount: Int {
        waiters.count
    }

    func next() async -> Value {
        if !values.isEmpty {
            return values.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func send(_ value: sending Value) {
        guard !waiters.isEmpty else {
            values.append(value)
            return
        }
        waiters.removeFirst().resume(returning: value)
    }
}
