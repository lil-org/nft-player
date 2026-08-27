// ∅ 2026 lil org

import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobilePlayerCollectionBrowserCoordinatorContractTests:
    XCTestCase {}

@MainActor
private final class SettlementAcceptance {
    var value = false
}

@MainActor
extension MobilePlayerCollectionBrowserCoordinatorContractTests {
    private func makeImageContentAccess(
        requiredImageQuality: @escaping @MainActor ()
            -> CollectionBrowseImageQuality = { .large },
        prepareThumbnailWindow: @escaping @MainActor (
            MobilePlayerCollectionBrowserImagePipeline
                .ThumbnailWindowPreparation
        ) -> Void = { _ in }
    ) -> MobilePlayerCollectionBrowserImagePipeline.ContentAccess {
        .init(
            visibleIndexPaths: { [] },
            cell: { _ in nil },
            visibleCells: { [] },
            viewportRenderCells: { [] },
            requiredImageQuality: requiredImageQuality,
            baseColumnCount: { 5 },
            isRendererActive: { false },
            isApplyingPosition: { false },
            isPreparedTransitionActive: { false },
            isForegroundActive: { true },
            projectedTokenRange: { _, _, _ in nil },
            prepareThumbnailWindow: prepareThumbnailWindow
        )
    }

    private func makeScrollContentAccess(
        publishFocusedPagePosition: @escaping @MainActor (
            PlayerPagePosition
        ) -> Void = { _ in },
        publishSettledPosition: @escaping @MainActor (
            PlayerCollectionScrollPublication
        ) -> Bool = { _ in true },
        performScheduledScrollObservation: @escaping @MainActor () -> Void = {},
        scrollMotionAnimationDidExpire: @escaping @MainActor () -> Void = {}
    ) -> MobilePlayerCollectionBrowserScrollCoordinator.ContentAccess {
        .init(
            pagePosition: { PlayerPagePosition(position: $0) },
            publishFocusedPagePosition: publishFocusedPagePosition,
            publishSettledPosition: publishSettledPosition,
            performScheduledScrollObservation:
                performScheduledScrollObservation,
            scrollMotionAnimationDidExpire: scrollMotionAnimationDidExpire
        )
    }

    func testImagePipelineSnapshotRestoreRoundTripsAllSnapshotState() throws {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var preparations = [
            MobilePlayerCollectionBrowserImagePipeline
                .ThumbnailWindowPreparation
        ]()
        pipeline.configure(contentAccess: makeImageContentAccess(
            prepareThumbnailWindow: { preparations.append($0) }
        ))
        pipeline.setActive(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .backward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .large
        )
        let snapshot = pipeline.snapshot()

        pipeline.resetThumbnailWindow()
        pipeline.restore(snapshot)

        XCTAssertEqual(pipeline.snapshot(), snapshot)
        let request = try XCTUnwrap(snapshot.lastThumbnailWindowRequest)
        XCTAssertEqual(request.tokenIndex, 18)
        XCTAssertEqual(request.direction, .backward)
        XCTAssertEqual(request.prefetchStride, 9)
        XCTAssertEqual(request.columnCount, 5)
        XCTAssertEqual(request.quality, .large)
        XCTAssertEqual(preparations.count, 1)
    }

    func testImagePipelineInvalidateIsIdempotentAndRejectsStateChanges() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var requiredQualityAccessCount = 0
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: {
                requiredQualityAccessCount += 1
                return .smallThumbnail
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.setScrollMotionActive(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .backward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .large
        )
        let snapshot = pipeline.snapshot()

        pipeline.invalidate()
        pipeline.invalidate()
        pipeline.setActive(false)
        pipeline.setVisible(false)
        pipeline.setScrollMotionActive(false)
        pipeline.resetThumbnailWindow()
        pipeline.restore(.init(
            lastThumbnailWindowRequest: nil
        ))
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: {
                requiredQualityAccessCount += 100
                return .large
            }
        ))

        XCTAssertTrue(pipeline.isActive)
        XCTAssertTrue(pipeline.isVisible)
        XCTAssertTrue(pipeline.isScrollMotionActive)
        XCTAssertEqual(pipeline.snapshot(), snapshot)
        XCTAssertFalse(pipeline.defersDenseGridImageLoading)
        XCTAssertEqual(requiredQualityAccessCount, 0)
    }

#if DEBUG
    func testImagePipelineInvalidationClearsAndRejectsPendingDenseGridWork() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: { .smallThumbnail }
        ))
        pipeline.setScrollMotionActive(true)
        pipeline.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: [3, 5, 3, 8]
        )

        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 3)
        XCTAssertTrue(pipeline.isDenseGridImageDisplayLinkActive)

        pipeline.invalidate()
        pipeline.invalidate()
        pipeline.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: [13, 21]
        )

        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
        XCTAssertFalse(pipeline.isDenseGridImageDisplayLinkActive)
        XCTAssertEqual(
            pipeline.drainDenseGridImageDisplayLinkFrameForTesting(),
            0
        )
    }
#endif

    func testImagePipelineCommitsWindowAfterSynchronousPreparationEffect() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var callbackSnapshot:
            MobilePlayerCollectionBrowserImagePipeline.Snapshot?
        pipeline.configure(contentAccess: makeImageContentAccess(
            prepareThumbnailWindow: { _ in
                callbackSnapshot = pipeline.snapshot()
            }
        ))
        pipeline.setActive(true)

        pipeline.prepareThumbnailWindow(
            around: 7,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 6,
            configuredColumnCount: 3,
            requiredImageQuality: .large
        )

        XCTAssertNil(callbackSnapshot?.lastThumbnailWindowRequest)
        XCTAssertEqual(
            pipeline.snapshot().lastThumbnailWindowRequest?.tokenIndex,
            7
        )
    }

    func testScrollCoordinatorSnapshotRestoreRoundTripsAllSnapshotState()
        throws {
        var sourcePublications = [PlayerCollectionScrollPublication]()
        let source = MobilePlayerCollectionBrowserScrollCoordinator()
        source.configure(contentAccess: makeScrollContentAccess(
            publishSettledPosition: {
                sourcePublications.append($0)
                return true
            }
        ))
        source.beginPublicationPositioning(at: 2, snapshotChanged: true)
        source.finishInitialPositioning()
        source.publicationState?.observeCandidate(9)
        source.focusedTokenIndex = 9
        source.forcedFocusedTokenIndex = 8
        source.retainedFocusFocalBias = try XCTUnwrap(
            PlayerCollectionScrollFocalBias(
                referenceFocalY: 240,
                deltaY: -32,
                decayDistance: 120
            )
        )
        source.lastEmittedFocusedTokenIndex = 7
        source.lastScrollOffsetY = 315
        source.setPrefetchDirection(.backward)
        let snapshot = source.snapshot()

        var restoredPublications = [PlayerCollectionScrollPublication]()
        let restored = MobilePlayerCollectionBrowserScrollCoordinator()
        restored.configure(contentAccess: makeScrollContentAccess(
            publishSettledPosition: {
                restoredPublications.append($0)
                return true
            }
        ))
        restored.restore(
            snapshot,
            retainedFocusFocalBias: snapshot.retainedFocusFocalBias,
            lastScrollOffsetY: snapshot.lastScrollOffsetY
        )
        let roundTrip = restored.snapshot()

        XCTAssertEqual(
            roundTrip.publicationState?.lastPublishedTokenIndex,
            snapshot.publicationState?.lastPublishedTokenIndex
        )
        XCTAssertEqual(
            roundTrip.hasFinishedInitialPositioning,
            snapshot.hasFinishedInitialPositioning
        )
        XCTAssertEqual(roundTrip.focusedTokenIndex, snapshot.focusedTokenIndex)
        XCTAssertEqual(
            roundTrip.forcedFocusedTokenIndex,
            snapshot.forcedFocusedTokenIndex
        )
        XCTAssertEqual(
            roundTrip.retainedFocusFocalBias,
            snapshot.retainedFocusFocalBias
        )
        XCTAssertEqual(
            roundTrip.lastEmittedFocusedTokenIndex,
            snapshot.lastEmittedFocusedTokenIndex
        )
        XCTAssertEqual(roundTrip.lastScrollOffsetY, snapshot.lastScrollOffsetY)
        XCTAssertEqual(
            roundTrip.lastPrefetchDirection,
            snapshot.lastPrefetchDirection
        )

        source.settle(hasViewedToEnd: true)
        restored.settle(hasViewedToEnd: true)
        XCTAssertEqual(sourcePublications, restoredPublications)
        XCTAssertEqual(
            source.snapshot().publicationState?.lastPublishedTokenIndex,
            restored.snapshot().publicationState?.lastPublishedTokenIndex
        )
    }

    func testScrollCoordinatorInvalidateIsIdempotentAndRejectsStateChanges() {
        let coordinator = MobilePlayerCollectionBrowserScrollCoordinator()
        coordinator.configure(contentAccess: makeScrollContentAccess())
        coordinator.setActive(true)
        coordinator.setApplyingPosition(true)
        XCTAssertTrue(coordinator.beginScrollMotion())
        coordinator.beginPublicationPositioning(at: 4, snapshotChanged: true)
        coordinator.focusedTokenIndex = 4
        coordinator.forcedFocusedTokenIndex = 5
        coordinator.lastEmittedFocusedTokenIndex = 3
        coordinator.lastScrollOffsetY = 180
        coordinator.setPrefetchDirection(.backward)
        let snapshot = coordinator.snapshot()

        coordinator.invalidate()
        coordinator.invalidate()
        coordinator.setActive(false)
        coordinator.setApplyingPosition(false)
        coordinator.endScrollMotion()
        coordinator.resetInitialPositioning(
            at: 99,
            resetsLastEmittedFocus: true
        )
        coordinator.setPrefetchDirection(.forward)
        coordinator.restore(
            snapshot,
            retainedFocusFocalBias: nil,
            lastScrollOffsetY: 999
        )

        XCTAssertTrue(coordinator.isActive)
        XCTAssertTrue(coordinator.isApplyingPosition)
        XCTAssertTrue(coordinator.isScrollMotionActive)
        XCTAssertEqual(coordinator.focusedTokenIndex, 4)
        XCTAssertEqual(coordinator.forcedFocusedTokenIndex, 5)
        XCTAssertEqual(coordinator.lastEmittedFocusedTokenIndex, 3)
        XCTAssertEqual(coordinator.lastScrollOffsetY, 180)
        XCTAssertEqual(coordinator.lastPrefetchDirection, .backward)
        XCTAssertFalse(coordinator.beginScrollMotion())
        XCTAssertFalse(coordinator.beginDrag(
            contentOffsetY: 20,
            clampedContentOffsetY: 20
        ))
        XCTAssertNil(coordinator.observeContentOffset(20))
        XCTAssertNil(coordinator.updatePrefetchDirection(
            offsetDelta: 10,
            epsilon: 0.5
        ))
        let generation = coordinator.beginPositioning()
        XCTAssertFalse(coordinator.isCurrentPositioningGeneration(generation))
    }

#if DEBUG
    func testScrollCoordinatorInvalidationRejectsPendingFocusScrollAndTimeoutWork()
        async throws {
        var focusedPositions = [PlayerPagePosition]()
        var scheduledScrollObservationCount = 0
        var timeoutCount = 0
        let coordinator = MobilePlayerCollectionBrowserScrollCoordinator()
        coordinator.configure(contentAccess: makeScrollContentAccess(
            publishFocusedPagePosition: { focusedPositions.append($0) },
            performScheduledScrollObservation: {
                scheduledScrollObservationCount += 1
            },
            scrollMotionAnimationDidExpire: { timeoutCount += 1 }
        ))
        coordinator.setActive(true)
        coordinator.hasFinishedInitialPositioning = true
        coordinator.publishFocus(tokenIndex: 1, cadence: .continuous)
        coordinator.publishFocus(tokenIndex: 2, cadence: .continuous)
        coordinator.scheduleScrollUpdate()
        XCTAssertTrue(coordinator.beginScrollMotion())
        coordinator.scheduleScrollMotionAnimationTimeout()
        XCTAssertTrue(coordinator.isScrollMotionAnimationTimeoutScheduled)

        coordinator.invalidate()
        coordinator.invalidate()
        coordinator.scheduleScrollUpdate()
        coordinator.scheduleScrollMotionAnimationTimeout()
        XCTAssertFalse(coordinator.isScrollMotionAnimationTimeoutScheduled)
        await Task.yield()
        await Task.yield()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(focusedPositions, [PlayerPagePosition(position: 1)])
        XCTAssertEqual(scheduledScrollObservationCount, 0)
        XCTAssertEqual(timeoutCount, 0)
    }
#endif

    func testScrollCoordinatorCommitsStateBeforeSynchronousEffectsAndRetry() {
        let coordinator = MobilePlayerCollectionBrowserScrollCoordinator()
        var callbackEvents = [String]()
        var emittedFocusAtCallback: Int?
        var settledIndexAtCallback: Int?
        let acceptsSettlement = SettlementAcceptance()
        coordinator.configure(contentAccess: makeScrollContentAccess(
            publishFocusedPagePosition: { _ in
                emittedFocusAtCallback =
                    coordinator.lastEmittedFocusedTokenIndex
                callbackEvents.append("focus")
            },
            publishSettledPosition: { _ in
                settledIndexAtCallback = coordinator.snapshot()
                    .publicationState?.lastPublishedTokenIndex
                callbackEvents.append(
                    acceptsSettlement.value ? "settled" : "retry"
                )
                return acceptsSettlement.value
            }
        ))
        coordinator.setActive(true)

        coordinator.publishFocus(tokenIndex: 6, cadence: .immediate)
        coordinator.beginPublicationPositioning(at: 2, snapshotChanged: true)
        coordinator.finishInitialPositioning()
        coordinator.publicationState?.observeCandidate(11)
        coordinator.settle(hasViewedToEnd: false)

        XCTAssertEqual(emittedFocusAtCallback, 6)
        XCTAssertEqual(settledIndexAtCallback, 11)
        XCTAssertNil(
            coordinator.snapshot().publicationState?.lastPublishedTokenIndex
        )

        acceptsSettlement.value = true
        coordinator.settle(hasViewedToEnd: false)

        XCTAssertEqual(callbackEvents, ["focus", "retry", "settled"])
        XCTAssertEqual(
            coordinator.snapshot().publicationState?.lastPublishedTokenIndex,
            11
        )
    }
}
