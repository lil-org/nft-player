// ∅ 2026 lil org

import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobileCollectionsSessionCoordinatorTests: CollectionTokenFixtureTestCase {
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

    func testCompletedBackCancelsManifestPreparationAndWidgetHandoffImmediately() async throws {
        let item = try firstCollectionItem()
        let preparations = CoordinatorValueQueue<Void>()
        let cancelled = expectation(description: "Manifest preparation cancelled")
        let store = CoordinatorProgressStore()
        let fixture = try makeFixture(store: store, prepareCollection: { _ in
            await withTaskCancellationHandler {
                await preparations.next()
            } onCancel: {
                cancelled.fulfill()
            }
            try Task.checkCancellation()
        })
        let url = try widgetURL(collectionId: item.id, tokenId: "widget-token")
        let task = try XCTUnwrap(fixture.coordinator.handleOpenURL(url))
        await assertWaiterCount(1, in: preparations)
        let resolution = try XCTUnwrap(
            fixture.coordinator.resolutionForPendingPresentationRequest()
        )

        resolution(true)

        XCTAssertNil(fixture.coordinator.openingDestination)
        XCTAssertFalse(fixture.coordinator.collectionPreparation.isLoading)
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)
        XCTAssertNil(fixture.coordinator.collectionPreparation.errorMessage)
        await fulfillment(of: [cancelled], timeout: 2)
        await preparations.send(())
        await task.value
        XCTAssertNil(fixture.coordinator.playerConfig)
        let metrics = await store.metrics()
        XCTAssertTrue(metrics.preparedUpdates.isEmpty)
        XCTAssertTrue(metrics.appliedUpdates.isEmpty)
    }

    func testCancelledBackKeepsManifestPreparationAndWidgetHandoff() async throws {
        let item = try firstCollectionItem()
        let insertion = makeWidgetInsertion(collectionId: item.id)
        let preparations = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(
            store: CoordinatorProgressStore(),
            widgetTokenInsertion: insertion,
            prepareCollection: { _ in
                await preparations.next()
                try Task.checkCancellation()
            }
        )
        let url = try widgetURL(collectionId: item.id, tokenId: insertion.insertedToken.id)
        let task = try XCTUnwrap(fixture.coordinator.handleOpenURL(url))
        await assertWaiterCount(1, in: preparations)
        let resolution = try XCTUnwrap(
            fixture.coordinator.resolutionForPendingPresentationRequest()
        )

        let destination = fixture.coordinator.openingDestination
        resolution(false)

        XCTAssertEqual(fixture.coordinator.openingDestination, destination)
        XCTAssertTrue(fixture.coordinator.collectionPreparation.isLoading)
        XCTAssertTrue(fixture.widgetState.isPreparingWidgetPlayerPresentation)
        await preparations.send(())
        await task.value
        let config = try XCTUnwrap(fixture.coordinator.playerConfig)
        XCTAssertEqual(config.widgetTokenInsertion, insertion)
        fixture.coordinator.didPresentPlayer(config)
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)
    }

    func testSupersededBackCompletionKeepsNewManifestPreparationAndWidgetHandoff() async throws {
        let items = try firstCollectionItems(count: 2)
        let insertion = makeWidgetInsertion(collectionId: items[1].id)
        let preparations = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(
            store: CoordinatorProgressStore(),
            widgetTokenInsertion: insertion,
            prepareCollection: { _ in
                await preparations.next()
                try Task.checkCancellation()
            }
        )
        let firstURL = try widgetURL(collectionId: items[0].id, tokenId: "first-token")
        let firstTask = try XCTUnwrap(fixture.coordinator.handleOpenURL(firstURL))
        await assertWaiterCount(1, in: preparations)
        let resolution = try XCTUnwrap(
            fixture.coordinator.resolutionForPendingPresentationRequest()
        )
        let secondURL = try widgetURL(collectionId: items[1].id, tokenId: insertion.insertedToken.id)
        let secondTask = try XCTUnwrap(fixture.coordinator.handleOpenURL(secondURL))
        await assertWaiterCount(2, in: preparations)

        resolution(true)

        XCTAssertTrue(fixture.coordinator.collectionPreparation.isLoading)
        XCTAssertTrue(fixture.widgetState.isPreparingWidgetPlayerPresentation)
        await preparations.send(())
        await preparations.send(())
        await firstTask.value
        await secondTask.value
        let config = try XCTUnwrap(fixture.coordinator.playerConfig)
        XCTAssertEqual(config.initialItemId, items[1].id)
        XCTAssertEqual(config.widgetTokenInsertion, insertion)
        XCTAssertEqual(fixture.recorder.preparedRequests.count, 1)
        fixture.coordinator.didPresentPlayer(config)
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)
    }

    func testManifestPreparationOpensDestinationBeforeTokensAreReady() async throws {
        let item = try firstCollectionItem()
        let preparations = CoordinatorValueQueue<Void>()
        let store = CoordinatorProgressStore()
        let fixture = try makeFixture(store: store, prepareCollection: { _ in
            await preparations.next()
        })
        await fixture.coordinator.refreshViewingProgress(id: 0)

        let task = fixture.coordinator.requestCollectionOpen(collectionId: item.id)
        let destination = try XCTUnwrap(fixture.coordinator.openingDestination)
        XCTAssertEqual(destination.collectionId, item.id)
        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)
        await assertWaiterCount(1, in: preparations)

        XCTAssertEqual(fixture.coordinator.openingDestination?.id, destination.id)
        XCTAssertTrue(fixture.coordinator.collectionPreparation.isLoading)
        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)
        XCTAssertNil(fixture.coordinator.playerConfig)
        XCTAssertTrue(fixture.recorder.preparedRequests.isEmpty)
        let pendingMetrics = await store.metrics()
        XCTAssertTrue(pendingMetrics.preparedUpdates.isEmpty)
        XCTAssertTrue(pendingMetrics.appliedUpdates.isEmpty)

        await preparations.send(())
        let didOpen = await task.value
        XCTAssertTrue(didOpen)
        XCTAssertFalse(fixture.coordinator.collectionPreparation.isLoading)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, item.id)
        fixture.coordinator.didPresentPlayer(try XCTUnwrap(fixture.coordinator.playerConfig))
        XCTAssertNil(fixture.coordinator.openingDestination)
    }

    func testManifestFailureDoesNotSaveProgressAndRetryPreservesSavedPosition() async throws {
        let item = try firstCollectionItem()
        let progress = makeProgress(collectionId: item.id, tokenIndex: 4)
        let store = CoordinatorProgressStore(progressByCollectionId: [item.id: progress])
        let retryPreparation = CoordinatorValueQueue<Void>()
        var attempts = 0
        let fixture = try makeFixture(store: store, prepareCollection: { _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            await retryPreparation.next()
        })

        let openTask = fixture.coordinator.requestResumeViewing(progress)
        let destination = try XCTUnwrap(fixture.coordinator.openingDestination)
        XCTAssertEqual(destination.initialTokenIndex, progress.tokenIndex)
        let didOpen = await openTask.value
        XCTAssertFalse(didOpen)
        XCTAssertEqual(fixture.coordinator.openingDestination?.id, destination.id)
        XCTAssertNotNil(fixture.coordinator.collectionPreparation.errorMessage)
        XCTAssertNil(fixture.coordinator.playerConfig)
        let failedMetrics = await store.metrics()
        XCTAssertTrue(failedMetrics.preparedUpdates.isEmpty)
        XCTAssertTrue(failedMetrics.appliedUpdates.isEmpty)

        fixture.coordinator.collectionPreparation.retry()
        await assertWaiterCount(1, in: retryPreparation)
        XCTAssertEqual(fixture.coordinator.openingDestination?.id, destination.id)
        XCTAssertNil(fixture.coordinator.collectionPreparation.errorMessage)
        await retryPreparation.send(())
        await assertPlayerPresented(fixture.coordinator)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, item.id)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialTokenId, progress.tokenId)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialTokenIndex, progress.tokenIndex)
    }

    func testCancelledManifestPreparationNeverPresentsOrSaves() async throws {
        let item = try firstCollectionItem()
        let preparations = CoordinatorValueQueue<Void>()
        let store = CoordinatorProgressStore()
        let fixture = try makeFixture(store: store, prepareCollection: { _ in
            await preparations.next()
        })
        let task = fixture.coordinator.requestCollectionOpen(collectionId: item.id)
        await assertWaiterCount(1, in: preparations)

        fixture.coordinator.cancel()
        await preparations.send(())
        let didOpen = await task.value
        await PlayerPersistenceUpdates.flush()

        XCTAssertFalse(didOpen)
        XCTAssertFalse(fixture.coordinator.collectionPreparation.isLoading)
        XCTAssertNil(fixture.coordinator.collectionPreparation.errorMessage)
        XCTAssertNil(fixture.coordinator.playerConfig)
        let metrics = await store.metrics()
        XCTAssertTrue(metrics.preparedUpdates.isEmpty)
        XCTAssertTrue(metrics.appliedUpdates.isEmpty)
    }

    func testSupersededManifestCompletionCannotReplaceNewSelection() async throws {
        let items = try firstCollectionItems(count: 2)
        let preparations = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(store: CoordinatorProgressStore(), prepareCollection: { id in
            if id == items[0].id { await preparations.next() }
        })
        let firstTask = fixture.coordinator.requestCollectionOpen(collectionId: items[0].id)
        await assertWaiterCount(1, in: preparations)
        let secondResult = await fixture.coordinator.requestCollectionOpen(collectionId: items[1].id).value
        await preparations.send(())
        let firstResult = await firstTask.value

        XCTAssertFalse(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, items[1].id)
        XCTAssertEqual(fixture.recorder.preparedRequests.count, 1)
        XCTAssertNil(fixture.coordinator.collectionPreparation.errorMessage)
    }

    func testWidgetRetryKeepsTokenAndDefersInsertionUntilManifestIsReady() async throws {
        let item = try firstCollectionItem()
        let insertion = makeWidgetInsertion(collectionId: item.id)
        let preparations = CoordinatorValueQueue<Void>()
        var attempts = 0
        let fixture = try makeFixture(
            store: CoordinatorProgressStore(),
            widgetTokenInsertion: insertion,
            prepareCollection: { _ in
                attempts += 1
                if attempts == 1 { throw URLError(.notConnectedToInternet) }
                await preparations.next()
            }
        )
        await fixture.coordinator.refreshViewingProgress(id: 0)
        let url = try widgetURL(collectionId: item.id, tokenId: insertion.insertedToken.id)
        prepareWidgetLaunch(url, fixture: fixture)
        let task = try XCTUnwrap(fixture.coordinator.handleOpenURL(url))
        await task.value

        XCTAssertTrue(fixture.recorder.widgetRequests.isEmpty)
        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)
        fixture.coordinator.collectionPreparation.retry()
        await assertWaiterCount(1, in: preparations)
        XCTAssertTrue(fixture.recorder.widgetRequests.isEmpty)
        await preparations.send(())
        await assertPlayerPresented(fixture.coordinator)
        XCTAssertEqual(fixture.recorder.widgetRequests.first?.tokenId, insertion.insertedToken.id)
        XCTAssertEqual(fixture.coordinator.playerConfig?.widgetTokenInsertion, insertion)
    }

    func testSelectingCollectionUnstagesSupersededWidgetDownloadImmediately() async throws {
        let items = try firstCollectionItems(count: 2)
        let preparations = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(store: CoordinatorProgressStore(), prepareCollection: { id in
            if id == items[0].id { await preparations.next() }
        })
        await fixture.coordinator.refreshViewingProgress(id: 0)
        let url = try widgetURL(collectionId: items[0].id, tokenId: "widget-token")
        prepareWidgetLaunch(url, fixture: fixture)
        let firstTask = try XCTUnwrap(fixture.coordinator.handleOpenURL(url))
        await assertWaiterCount(1, in: preparations)
        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)

        let didOpen = await fixture.coordinator.requestCollectionOpen(collectionId: items[1].id).value
        XCTAssertTrue(didOpen)
        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)
        XCTAssertFalse(fixture.widgetState.isPreparingWidgetPlayerPresentation)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, items[1].id)

        await preparations.send(())
        await firstTask.value
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, items[1].id)
        XCTAssertTrue(fixture.recorder.widgetRequests.isEmpty)
    }

    func testNavigationPushesLoadingDestinationAndBackCancelsPreparation() async throws {
        let item = try firstCollectionItem()
        let preparations = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(store: CoordinatorProgressStore(), prepareCollection: { _ in
            await preparations.next()
        })
        let task = fixture.coordinator.requestCollectionOpen(collectionId: item.id, transition: .instant)
        let destination = try XCTUnwrap(fixture.coordinator.openingDestination)
        let root = UIHostingController(rootView: Color.black)
        let navigation = PlayerNavigationController(rootViewController: root)
        let navigationCoordinator = MobileCollectionsNavigationView<Color>.Coordinator()
        navigationCoordinator.attach(navigationController: navigation, rootViewController: root)
        let didShowOpening = expectation(description: "Loading destination finished appearing")
        let navigationObserver = CoordinatorNavigationObserver(
            forwardingTo: navigationCoordinator,
            didShowOpening: didShowOpening
        )
        navigation.delegate = navigationObserver
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = navigation
        window.isHidden = false
        window.layoutIfNeeded()
        defer {
            withExtendedLifetime(navigationObserver) {
                navigationCoordinator.invalidate()
                window.isHidden = true
            }
        }
        navigationCoordinator.update(
            playerConfig: fixture.coordinator.playerConfig,
            openingDestination: destination,
            collectionPreparation: fixture.coordinator.collectionPreparation,
            onDismissOpeningDestination: fixture.coordinator.dismissOpeningDestination,
            presentationTransition: .instant,
            onWillDismissPlayer: fixture.coordinator.resolutionForPendingPresentationRequest,
            onDidPresentPlayer: fixture.coordinator.didPresentPlayer,
            onDismissPlayer: fixture.coordinator.dismissPlayer
        )

        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertEqual(navigation.topViewController?.title, destination.title)
        XCTAssertTrue(navigation.topViewController is UIHostingController<CollectionOpeningView>)
        XCTAssertNil(fixture.coordinator.playerConfig)
        await fulfillment(of: [didShowOpening], timeout: 2)
        await assertWaiterCount(1, in: preparations)

        navigation.popToRootViewController(animated: false)
        let dismissalDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while fixture.coordinator.openingDestination != nil, ContinuousClock.now < dismissalDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNil(fixture.coordinator.openingDestination)
        await preparations.send(())
        let didOpen = await task.value
        XCTAssertFalse(didOpen)
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertNil(fixture.coordinator.playerConfig)
    }

    func testNavigationCompletedBackDoesNotDiscardNewReadyDestination() async throws {
        let items = try firstCollectionItems(count: 2)
        let preparations = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(store: CoordinatorProgressStore(), prepareCollection: { id in
            if id == items[0].id { await preparations.next() }
        })
        let firstTask = fixture.coordinator.requestCollectionOpen(collectionId: items[0].id, transition: .instant)
        let root = UIHostingController(rootView: Color.black)
        let navigation = PlayerNavigationController(rootViewController: root)
        let navigationCoordinator = MobileCollectionsNavigationView<Color>.Coordinator()
        navigationCoordinator.attach(navigationController: navigation, rootViewController: root)
        navigation.delegate = navigationCoordinator
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = navigation
        window.isHidden = false
        window.layoutIfNeeded()
        defer {
            navigationCoordinator.invalidate()
            window.isHidden = true
        }
        func synchronize(_ transition: PlayerPresentationTransition) {
            navigationCoordinator.update(
                playerConfig: fixture.coordinator.playerConfig,
                openingDestination: fixture.coordinator.openingDestination,
                collectionPreparation: fixture.coordinator.collectionPreparation,
                onDismissOpeningDestination: fixture.coordinator.dismissOpeningDestination,
                presentationTransition: transition,
                onWillDismissPlayer: fixture.coordinator.resolutionForPendingPresentationRequest,
                onDidPresentPlayer: fixture.coordinator.didPresentPlayer,
                onDismissPlayer: fixture.coordinator.dismissPlayer
            )
        }
        synchronize(.instant)
        XCTAssertTrue(navigation.topViewController is UIHostingController<CollectionOpeningView>)
        await assertWaiterCount(1, in: preparations)
        let backResolution = try XCTUnwrap(fixture.coordinator.resolutionForPendingPresentationRequest())
        let secondDidOpen = await fixture.coordinator.requestCollectionOpen(collectionId: items[1].id).value
        XCTAssertTrue(secondDidOpen)
        let config = try XCTUnwrap(fixture.coordinator.playerConfig)
        synchronize(.animated)
        navigation.delegate = nil
        navigation.setViewControllers([root], animated: false)
        navigation.delegate = navigationCoordinator
        backResolution(true)
        navigationCoordinator.navigationController(navigation, didShow: root, animated: false)
        await preparations.send(())
        _ = await firstTask.value

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while navigation.viewControllers.count == 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(fixture.coordinator.playerConfig?.id, config.id)
        XCTAssertGreaterThan(navigation.viewControllers.count, 1)
        XCTAssertFalse(navigation.topViewController is UIHostingController<CollectionOpeningView>)
    }

    func testDestinationOpensBeforePersistenceFlushAndSavedPositionLookup() async throws {
        let item = try firstCollectionItem()
        let flushes = CoordinatorValueQueue<Void>()
        let progressResults = CoordinatorValueQueue<MobileViewingProgress?>()
        let store = CoordinatorProgressStore(progressQueue: progressResults)
        let fixture = try makeFixture(store: store, flushQueue: flushes)
        let task = fixture.coordinator.requestCollectionOpen(collectionId: item.id)
        let destination = try XCTUnwrap(fixture.coordinator.openingDestination)

        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)
        XCTAssertNil(fixture.coordinator.playerConfig)
        await assertWaiterCount(1, in: flushes)
        XCTAssertEqual(fixture.coordinator.openingDestination?.id, destination.id)
        XCTAssertTrue(fixture.recorder.preparedRequests.isEmpty)
        await flushes.send(())
        await assertWaiterCount(1, in: progressResults)
        XCTAssertEqual(fixture.coordinator.openingDestination?.id, destination.id)
        XCTAssertTrue(fixture.recorder.preparedRequests.isEmpty)

        fixture.coordinator.dismissOpeningDestination(destination)
        await progressResults.send(nil)
        let didOpen = await task.value
        XCTAssertFalse(didOpen)
        XCTAssertNil(fixture.coordinator.openingDestination)
        XCTAssertNil(fixture.coordinator.playerConfig)
        let metrics = await store.metrics()
        XCTAssertTrue(metrics.preparedUpdates.isEmpty)
        XCTAssertTrue(metrics.appliedUpdates.isEmpty)
    }

    func testDismissedSupersededDestinationCannotCancelNewSelection() async throws {
        let items = try firstCollectionItems(count: 2)
        let preparations = CoordinatorValueQueue<Void>()
        let fixture = try makeFixture(store: CoordinatorProgressStore(), prepareCollection: { _ in
            await preparations.next()
        })
        let first = fixture.coordinator.requestCollectionOpen(collectionId: items[0].id)
        let oldDestination = try XCTUnwrap(fixture.coordinator.openingDestination)
        await assertWaiterCount(1, in: preparations)
        let second = fixture.coordinator.requestCollectionOpen(collectionId: items[1].id)
        let newDestination = try XCTUnwrap(fixture.coordinator.openingDestination)
        let invalidSelection = await fixture.coordinator.requestCollectionOpen(collectionId: "missing").value
        XCTAssertFalse(invalidSelection)
        XCTAssertEqual(fixture.coordinator.openingDestination?.id, newDestination.id)
        fixture.coordinator.dismissOpeningDestination(oldDestination)
        XCTAssertEqual(fixture.coordinator.openingDestination?.id, newDestination.id)
        await assertWaiterCount(2, in: preparations)
        await preparations.send(())
        await preparations.send(())
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertFalse(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(fixture.coordinator.playerConfig?.initialItemId, items[1].id)
    }

    func testBackAfterPreparationBeforeShellReplacementDiscardsReadyPlayer() async throws {
        let item = try firstCollectionItem()
        let fixture = try makeFixture(store: CoordinatorProgressStore())
        let task = fixture.coordinator.requestCollectionOpen(collectionId: item.id)
        let destination = try XCTUnwrap(fixture.coordinator.openingDestination)
        let didOpen = await task.value
        XCTAssertTrue(didOpen)
        XCTAssertNotNil(fixture.coordinator.playerConfig)

        fixture.coordinator.dismissOpeningDestination(destination)

        XCTAssertNil(fixture.coordinator.openingDestination)
        XCTAssertNil(fixture.coordinator.playerConfig)
    }

    func testDelayedReadyUpdateCannotReopenDismissedLoadingDestination() async throws {
        for completesDismissalBeforeUpdate in [false, true] {
            let item = try firstCollectionItem()
            let preparations = CoordinatorValueQueue<Void>()
            let fixture = try makeFixture(store: CoordinatorProgressStore(), prepareCollection: { _ in
                await preparations.next()
            })
            let task = fixture.coordinator.requestCollectionOpen(collectionId: item.id, transition: .instant)
            let root = UIHostingController(rootView: Color.black)
            let navigation = PlayerNavigationController(rootViewController: root)
            let navigationCoordinator = MobileCollectionsNavigationView<Color>.Coordinator()
            navigationCoordinator.attach(navigationController: navigation, rootViewController: root)
            navigation.delegate = navigationCoordinator
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let window = UIWindow(windowScene: scene)
            window.rootViewController = navigation
            window.isHidden = false
            window.layoutIfNeeded()
            defer {
                navigationCoordinator.invalidate()
                window.isHidden = true
            }
            func synchronize() {
                navigationCoordinator.update(
                    playerConfig: fixture.coordinator.playerConfig,
                    openingDestination: fixture.coordinator.openingDestination,
                    collectionPreparation: fixture.coordinator.collectionPreparation,
                    onDismissOpeningDestination: fixture.coordinator.dismissOpeningDestination,
                    presentationTransition: .instant,
                    onWillDismissPlayer: fixture.coordinator.resolutionForPendingPresentationRequest,
                    onDidPresentPlayer: fixture.coordinator.didPresentPlayer,
                    onDismissPlayer: fixture.coordinator.dismissPlayer
                )
            }
            synchronize()
            XCTAssertTrue(navigation.topViewController is UIHostingController<CollectionOpeningView>)
            await assertWaiterCount(1, in: preparations)
            await preparations.send(())
            let didOpen = await task.value
            XCTAssertTrue(didOpen)
            XCTAssertNotNil(fixture.coordinator.playerConfig)
            XCTAssertTrue(navigation.topViewController is UIHostingController<CollectionOpeningView>)

            navigation.popToRootViewController(animated: false)
            XCTAssertTrue(navigation.topViewController === root)
            if completesDismissalBeforeUpdate {
                navigationCoordinator.navigationController(navigation, didShow: root, animated: false)
            }
            synchronize()
            XCTAssertTrue(navigation.topViewController === root)
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while fixture.coordinator.playerConfig != nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertTrue(navigation.topViewController === root)
            XCTAssertNil(fixture.coordinator.playerConfig)
            XCTAssertNil(fixture.coordinator.openingDestination)
        }
    }

#if DEBUG
    func testColdManifestDestinationDoesNotConstructPlayerUntilCanonicalTokensAreInstalled() async throws {
        let item = try XCTUnwrap(MobileCollectionCatalog.allItems.first {
            SuggestedItemsService.tokenResourceName(collectionId: $0.id) == "fidenza"
        })
        let data = try Data(contentsOf: XCTUnwrap(CollectionTokenFixtures.url(collectionId: item.id)))
        let tokens = try BundledTokens(data: data)
        let tokenIndex = 4
        let token = tokens.items[tokenIndex]
        let progress = MobileViewingProgress(
            collectionId: item.id,
            collectionName: item.name,
            tokenId: token.id,
            tokenIndex: tokenIndex,
            tokenCount: tokens.items.count,
            updatedAt: Date()
        )
        CollectionCatalog.resetPreparedCollectionForTesting(collectionId: item.id)
        defer {
            XCTAssertNoThrow(try CollectionCatalog.installPreparedTokens(data, collectionId: item.id))
        }
        let downloads = CoordinatorValueQueue<Void>()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PersistentCollectionTokenCache(rootURL: directory, transport: { _ in
            await downloads.next()
            return (data, 200)
        })
        let fixture = try makeFixture(
            store: CoordinatorProgressStore(progressByCollectionId: [item.id: progress]),
            collectionItems: [item],
            prepareCollection: { id in
                try await CollectionCatalog.prepareCollection(collectionId: id, cache: cache)
            }
        )
        let task = fixture.coordinator.requestResumeViewing(progress)
        XCTAssertEqual(fixture.coordinator.openingDestination?.collectionId, item.id)
        XCTAssertTrue(fixture.coordinator.isReadyToRevealNavigation)
        await assertWaiterCount(1, in: downloads)
        XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: tokenIndex))
        XCTAssertNil(fixture.coordinator.playerConfig)
        XCTAssertTrue(fixture.recorder.preparedRequests.isEmpty)

        await downloads.send(())
        let didOpen = await task.value
        XCTAssertTrue(didOpen)
        let config = try XCTUnwrap(fixture.coordinator.playerConfig)
        XCTAssertEqual(config.initialTokenId, token.id)
        XCTAssertEqual(config.initialTokenIndex, tokenIndex)
        XCTAssertEqual(
            CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: tokenIndex)?.id,
            token.id
        )
    }
#endif

    private func assertPlayerPresented(
        _ coordinator: MobileCollectionsSessionCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if coordinator.playerConfig != nil { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Expected player presentation", file: file, line: line)
    }

    private func makeFixture(
        store: CoordinatorProgressStore,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil,
        prewarmCollectionIds: [String] = ["prewarm"],
        flushQueue: CoordinatorValueQueue<Void>? = nil,
        collectionItems: [MobileCollectionItem]? = nil,
        prepareCollection: @escaping @MainActor (String) async throws -> Void = { _ in }
    ) throws -> CoordinatorFixture {
        let items = try collectionItems ?? firstCollectionItems(count: 2)
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
            prepareCollection: prepareCollection,
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

@MainActor
private final class CoordinatorNavigationObserver: NSObject, UINavigationControllerDelegate {
    private let delegate: any UINavigationControllerDelegate
    private var didShowOpening: XCTestExpectation?

    init(forwardingTo delegate: any UINavigationControllerDelegate, didShowOpening: XCTestExpectation) {
        self.delegate = delegate
        self.didShowOpening = didShowOpening
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        delegate.navigationController?(navigationController, willShow: viewController, animated: animated)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        delegate.navigationController?(navigationController, didShow: viewController, animated: animated)
        if viewController is UIHostingController<CollectionOpeningView> {
            didShowOpening?.fulfill()
            didShowOpening = nil
        }
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
