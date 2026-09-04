// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobilePlayerCollectionBrowserGridRendererTests {
    func testImmediateFinishCancelsWorkBeforeFirstTick() throws {
        let fixture = try makeFixture()
        begin(fixture)

        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
        XCTAssertFalse(fixture.collectionView.subviews.contains {
            $0 is MobilePlayerCollectionBrowserCell
        })
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )

        XCTAssertNotNil(fixture.renderer.finish(preservingCarryover: false))
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 0)
        XCTAssertEqual(fixture.configureCount.value, 0)
    }

    func testTransitionImageCompletionWaitsForPump() async throws {
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    completion.value = callback
                    return {}
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let originalSubviewIDs = sourceCell.contentView.subviews.map(
            ObjectIdentifier.init
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let loaded = try XCTUnwrap(completion.value)

        loaded(makeImage())
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                sourceCell.contentView.subviews.map(ObjectIdentifier.init),
                originalSubviewIDs
            )
            XCTAssertEqual(
                fixture.renderer.pendingMaterializationWorkCount,
                1
            )
            _ = fixture.renderer.drainMaterializationWork()
        }

        XCTAssertGreaterThan(
            sourceCell.contentView.subviews.count,
            originalSubviewIDs.count
        )
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.sourceRepresentations.preparedRepresentationIDs.contains(
            ObjectIdentifier(sourceCell)
        ))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testTransitionImageCompletionProcessesDuringTrackingRunLoopMode() throws {
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    completion.value = callback
                    return {}
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let originalSubviewIDs = sourceCell.contentView.subviews.map(
            ObjectIdentifier.init
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        try XCTUnwrap(completion.value)(makeImage())

        XCTAssertTrue(runMainTrackingRunLoop {
            fixture.renderer.pendingMaterializationWorkCount > 0
                || sourceCell.contentView.subviews.count
                    > originalSubviewIDs.count
        })
        if fixture.renderer.pendingMaterializationWorkCount > 0 {
            XCTAssertEqual(
                sourceCell.contentView.subviews.map(ObjectIdentifier.init),
                originalSubviewIDs
            )
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertGreaterThan(
            sourceCell.contentView.subviews.count,
            originalSubviewIDs.count
        )
    }

    func testInvalidTransitionCompletionIsRetiredByPump() async throws {
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    completion.value = callback
                    return {}
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        try XCTUnwrap(completion.value)(makeImage())
        sourceCell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 1
            ),
            itemCount: 2,
            imageSources: nil,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                fixture.renderer.pendingMaterializationWorkCount,
                1
            )
            _ = fixture.renderer.drainMaterializationWork()
        }
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.sourceRepresentations.transitionImageLoads.isEmpty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testRendererDeallocatesWithPendingDisplayLinkWork() throws {
        weak var renderer: MobilePlayerCollectionBrowserGridRenderer?

        do {
            let fixture = try makeFixture()
            begin(fixture)
            XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
            XCTAssertGreaterThan(
                fixture.renderer.pendingMaterializationWorkCount,
                0
            )
            renderer = fixture.renderer
        }

        XCTAssertNil(renderer)
    }

    func testDrainProcessesAtMostEightJobs() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let pendingCount = fixture.renderer.pendingMaterializationWorkCount
        XCTAssertGreaterThan(pendingCount, 8)

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 8)
        XCTAssertGreaterThan(fixture.renderer.pendingMaterializationWorkCount, 0)
        XCTAssertLessThanOrEqual(
            fixture.renderer.pendingMaterializationWorkCount,
            pendingCount
        )
        XCTAssertGreaterThan(fixture.configureCount.value, 0)
        XCTAssertLessThanOrEqual(fixture.configureCount.value, 7)
        XCTAssertFalse(result.stoppedForTimeLimit)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDrainRunsAtBurstBudgetAfterGestureRender() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        fixture.renderer.requestGestureMaterializationBurst()
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            32
        )

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 32)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        XCTAssertLessThanOrEqual(
            fixture.renderer.drainMaterializationWork().processedCount,
            8
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testGestureDrainScalesItsTimeBudgetWithFrameDuration() throws {
        func processedCount(frameDuration: CFTimeInterval) throws -> Int {
            let time = Box<CFTimeInterval>(0)
            let fixture = try makeFixture(clock: {
                defer { time.value += 0.000_25 }
                return time.value
            })
            begin(fixture)
            XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: 0.8,
                settleProgress: 0.5,
                panDeltaY: 0
            ))
            fixture.renderer.requestGestureMaterializationBurst()
            time.value = 0

            let result = fixture.renderer.drainMaterializationWork(
                frameDuration: frameDuration
            )
            _ = fixture.renderer.finish(preservingCarryover: false)
            XCTAssertTrue(result.stoppedForTimeLimit)
            return result.processedCount
        }

        let thirtyHertzCount = try processedCount(frameDuration: 1.0 / 30)
        let sixtyHertzCount = try processedCount(frameDuration: 1.0 / 60)
        let oneTwentyHertzCount = try processedCount(frameDuration: 1.0 / 120)

        XCTAssertEqual(thirtyHertzCount, sixtyHertzCount)
        XCTAssertGreaterThan(sixtyHertzCount, oneTwentyHertzCount)
    }

    func testCoordinatorFrameTailUsesSixtyAndOneTwentyHertzBudgets()
        throws {
        func processedCount(frameDuration: CFTimeInterval) throws -> Int {
            let fixture = try makeFixture(clock: { 0 })
            begin(fixture)
            XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
            XCTAssertGreaterThan(
                fixture.renderer.pendingMaterializationWorkCount,
                8
            )
            let frame = GridTransitionFrame(
                timestamp: 1,
                targetTimestamp: 1 + frameDuration
            )
            fixture.renderer.beginTransitionFrame(frame)
            let result = try XCTUnwrap(
                fixture.renderer.finishTransitionFrame(frame)
            )
            _ = fixture.renderer.finish(preservingCarryover: false)
            return result.processedCount
        }

        XCTAssertEqual(try processedCount(frameDuration: 1.0 / 120), 4)
        XCTAssertEqual(try processedCount(frameDuration: 1.0 / 60), 8)
    }

    func testCoordinatorFrameTailSkipsWorkAfterDeadline() throws {
        let fixture = try makeFixture(clock: { 2 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let pendingCount = fixture.renderer.pendingMaterializationWorkCount
        XCTAssertGreaterThan(pendingCount, 0)
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )

        XCTAssertTrue(fixture.renderer.beginTransitionFrame(frame))
        let result = try XCTUnwrap(
            fixture.renderer.finishTransitionFrame(frame)
        )

        XCTAssertEqual(result.processedCount, 0)
        XCTAssertTrue(result.stoppedForTimeLimit)
        XCTAssertEqual(
            fixture.renderer.pendingMaterializationWorkCount,
            pendingCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

#if DEBUG
    func testExpiredTransitionFrameDoesNotCommitDirtyPhantomMask() throws {
        let fixture = try makeFixture(clock: { 2 })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )

        fixture.renderer.beginTransitionFrame(frame)
        _ = fixture.renderer.finishTransitionFrame(frame)

        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testNearExpiredTransitionFrameDefersDirtyPhantomMask() throws {
        let frameDuration = 1.0 / 120
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + frameDuration
        )
        let fixture = try makeFixture(clock: {
            frame.targetTimestamp - frameDuration / 4
        })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount

        fixture.renderer.beginTransitionFrame(frame)
        _ = fixture.renderer.finishTransitionFrame(frame)

        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testNextLiveTransitionFrameCommitsDeferredPhantomMask() throws {
        let time = Box<CFTimeInterval>(2)
        let fixture = try makeFixture(clock: { time.value })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount
        let expiredFrame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
        fixture.renderer.beginTransitionFrame(expiredFrame)
        _ = fixture.renderer.finishTransitionFrame(expiredFrame)
        time.value = 2
        let liveFrame = GridTransitionFrame(
            timestamp: 2,
            targetTimestamp: 2 + 1.0 / 120
        )

        fixture.renderer.beginTransitionFrame(liveFrame)
        _ = fixture.renderer.finishTransitionFrame(liveFrame)

        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before + 1
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testExpiredSnapshotBarrierForcesDirtyPhantomMaskCommit() throws {
        let fixture = try makeFixture(clock: { 2 })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
        fixture.renderer.beginTransitionFrame(frame)

        let barrierResult = fixture.renderer.prepareForSnapshot(using: frame)

        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before + 1
        )
        XCTAssertEqual(
            fixture.renderer.finishTransitionFrame(frame),
            barrierResult
        )
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before + 1
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testExpiredFrameDefersMaskCommitWhenFrameDrivingEnds() throws {
        let time = Box<CFTimeInterval>(0)
        let fixture = try makeFixture(clock: { time.value })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount
        let displayLinkStartCount = fixture.renderer
            .independentMaterializerDisplayLinkStartCount
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
        time.value = 2
        fixture.renderer.beginTransitionFrame(frame)
        fixture.renderer.setTransitionFrameDriving(false)

        _ = fixture.renderer.finishTransitionFrame(frame)

        XCTAssertFalse(fixture.renderer.isTransitionFrameDriving)
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before
        )
        XCTAssertEqual(
            fixture.renderer.independentMaterializerDisplayLinkStartCount,
            displayLinkStartCount + 1
        )

        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before + 1
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }
#endif

    func testTransitionFrameDefersMaterializerHandoffUntilTailCompletes()
        throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        XCTAssertTrue(fixture.renderer.isTransitionFrameDriving)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
#if DEBUG
        let startCount = fixture.renderer
            .independentMaterializerDisplayLinkStartCount
#endif

        fixture.renderer.beginTransitionFrame(frame)
        fixture.renderer.setTransitionFrameDriving(false)
        XCTAssertTrue(fixture.renderer.isTransitionFrameDriving)
#if DEBUG
        XCTAssertEqual(
            fixture.renderer.independentMaterializerDisplayLinkStartCount,
            startCount
        )
#endif

        _ = fixture.renderer.finishTransitionFrame(frame)
        XCTAssertFalse(fixture.renderer.isTransitionFrameDriving)
#if DEBUG
        XCTAssertGreaterThan(
            fixture.renderer.independentMaterializerDisplayLinkStartCount,
            startCount
        )
#endif
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testSynchronousSnapshotBarrierUsesSixtyHertzBudget() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 60
        )
        XCTAssertTrue(fixture.renderer.beginTransitionFrame(frame))
        let result = try XCTUnwrap(fixture.renderer.prepareForSnapshot(
            using: frame
        ))

        XCTAssertEqual(result.processedCount, 8)
        XCTAssertEqual(
            fixture.renderer.finishTransitionFrame(frame),
            result
        )
        XCTAssertTrue(fixture.renderer.isTransitionFrameDriving)
        fixture.renderer.setTransitionFrameDriving(false)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

#if DEBUG
    func testSnapshotBarrierDrainsOnceAndDefersHandoffUntilFrameTail()
        throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
        let drainCount = fixture.renderer.externalMaterializerFrameDrainCount

        fixture.renderer.beginTransitionFrame(frame)
        fixture.renderer.setTransitionFrameDriving(false)
        let barrierResult = try XCTUnwrap(
            fixture.renderer.prepareForSnapshot(using: frame)
        )

        XCTAssertEqual(barrierResult.processedCount, 4)
        XCTAssertEqual(
            fixture.renderer.externalMaterializerFrameDrainCount,
            drainCount + 1
        )
        XCTAssertTrue(fixture.renderer.isTransitionFrameDriving)

        let tailResult = try XCTUnwrap(
            fixture.renderer.finishTransitionFrame(frame)
        )

        XCTAssertEqual(tailResult, barrierResult)
        XCTAssertEqual(
            fixture.renderer.externalMaterializerFrameDrainCount,
            drainCount + 1
        )
        XCTAssertFalse(fixture.renderer.isTransitionFrameDriving)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testSnapshotBarrierCommitsPhantomMaskBeforeFrameTail() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        let firstFrame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
        fixture.renderer.beginTransitionFrame(firstFrame)
        _ = fixture.renderer.finishTransitionFrame(firstFrame)
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount

        let secondFrame = GridTransitionFrame(
            timestamp: 1 + 1.0 / 120,
            targetTimestamp: 1 + 2.0 / 120
        )
        fixture.renderer.beginTransitionFrame(secondFrame)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before
        )
        let barrierResult = try XCTUnwrap(
            fixture.renderer.prepareForSnapshot(using: secondFrame)
        )

        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before + 1
        )
        XCTAssertEqual(
            fixture.renderer.finishTransitionFrame(secondFrame),
            barrierResult
        )
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before + 1
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testEndingExternalDrivingFlushesDirtyPhantomMask() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        let frame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
        fixture.renderer.beginTransitionFrame(frame)
        _ = fixture.renderer.finishTransitionFrame(frame)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount

        fixture.renderer.setTransitionFrameDriving(false)

        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            before + 1
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testTransitionFramesSkipCleanPhantomMaskCommits() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        fixture.renderer.setTransitionFrameDriving(true)
        let before = fixture.renderer.phantomShapeMaskCommitAttemptCount

        let firstFrame = GridTransitionFrame(
            timestamp: 1,
            targetTimestamp: 1 + 1.0 / 120
        )
        fixture.renderer.beginTransitionFrame(firstFrame)
        _ = fixture.renderer.finishTransitionFrame(firstFrame)
        let afterFirstFrame = fixture.renderer.phantomShapeMaskCommitAttemptCount

        let secondFrame = GridTransitionFrame(
            timestamp: 1 + 1.0 / 120,
            targetTimestamp: 1 + 2.0 / 120
        )
        fixture.renderer.beginTransitionFrame(secondFrame)
        _ = fixture.renderer.finishTransitionFrame(secondFrame)

        XCTAssertEqual(afterFirstFrame, before + 1)
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            afterFirstFrame
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }
#endif

    func testInteractionFadePreservesOnlyTheNextMaterializationBurst() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        fixture.renderer.requestGestureMaterializationBurst()
        XCTAssertTrue(fixture.renderer.renderInteractionFade(
            id: fixture.planeRequest.id,
            presentationProgress: 0.6
        ))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(result.processedCount, 8)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        XCTAssertLessThanOrEqual(
            fixture.renderer.drainMaterializationWork().processedCount,
            8
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testMaterializationBurstRequestWithoutWorkIsIgnored() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        fixture.renderer.requestGestureMaterializationBurst()
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )

        XCTAssertLessThanOrEqual(
            fixture.renderer.drainMaterializationWork().processedCount,
            8
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testCancellingBurstWhileCommitIsPendingClearsSessionRequest() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        fixture.renderer.requestGestureMaterializationBurst()
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.pendingGestureMaterializationBurst)
        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: fixture.planeRequest.toMode
        ))

        fixture.renderer.cancelGestureMaterializationBurst()

        XCTAssertFalse(session.pendingGestureMaterializationBurst)
        fixture.renderer.abortCommit(preparation)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPhantomShapeHierarchyIsRetainedAcrossDrainBatches() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layerIDs = try XCTUnwrap(shapeView.layer.sublayers).map(
            ObjectIdentifier.init
        )
        XCTAssertFalse(layerIDs.isEmpty)

        _ = fixture.renderer.drainMaterializationWork()
        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertTrue(session.phantomShapeView === shapeView)
        XCTAssertEqual(
            shapeView.layer.sublayers?.map(ObjectIdentifier.init),
            layerIDs
        )
        XCTAssertFalse(session.phantomCells.isEmpty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testRetainedCandidateShapeHidesWithoutImplicitAnimations() throws {
        let fixture = try makeFixture(itemCount: 1, clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        XCTAssertFalse(shapeView.isHidden)
        XCTAssertFalse(layers.candidates.isHidden)
        XCTAssertNotNil(layers.candidates.path)
        XCTAssertTrue(layers.repeatedRows.isHidden)
        XCTAssertTrue(layers.finalRow.isHidden)
        XCTAssertTrue(layers.solidCoverage.isHidden)
        assertNoAnimations(in: shapeView.layer)

        drainQueuedWork(fixture)

        XCTAssertTrue(session.phantomShapeView === shapeView)
        XCTAssertTrue(shapeView.isHidden)
        XCTAssertEqual(
            shapeView.layer.sublayers?.map(ObjectIdentifier.init),
            [
                layers.repeatedRows,
                layers.finalRow,
                layers.solidCoverage,
                layers.candidates,
            ].map(ObjectIdentifier.init)
        )
        assertNoAnimations(in: shapeView.layer)
        _ = fixture.renderer.finish(preservingCarryover: false)
        XCTAssertNil(shapeView.superview)
    }

    func testRetainedRepeatedShapeUpdatesMaskWithoutImplicitAnimations()
        throws {
        let fixture = try makeFixture(
            itemCount: 603,
            uniformImageSize: CGSize(width: 10, height: 1),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        XCTAssertFalse(layers.repeatedRows.isHidden)
        XCTAssertGreaterThan(layers.repeatedRows.instanceCount, 0)
        XCTAssertNotNil(layers.repeatedRow.path)
        XCTAssertFalse(layers.finalRow.isHidden)
        XCTAssertNotNil(layers.finalRow.path)
        XCTAssertTrue(layers.solidCoverage.isHidden)
        XCTAssertNil(shapeView.layer.mask)
        assertNoAnimations(in: shapeView.layer)

        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertTrue(session.phantomShapeView === shapeView)
        let mask = try XCTUnwrap(shapeView.layer.mask as? CAShapeLayer)
        XCTAssertEqual(mask.fillRule, .evenOdd)
        XCTAssertNotNil(mask.path)
        XCTAssertFalse(layers.repeatedRows.isHidden)
        XCTAssertFalse(layers.finalRow.isHidden)
        XCTAssertTrue(layers.solidCoverage.isHidden)
        assertNoAnimations(in: shapeView.layer)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testRetainedSolidShapeUpdatesMaskWithoutImplicitAnimations() throws {
        let fixture = try makeFixture(
            itemCount: 10_000,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        XCTAssertTrue(layers.repeatedRows.isHidden)
        XCTAssertTrue(layers.finalRow.isHidden)
        XCTAssertFalse(layers.solidCoverage.isHidden)
        XCTAssertNotNil(layers.solidCoverage.path)
        XCTAssertNil(shapeView.layer.mask)
        assertNoAnimations(in: shapeView.layer)

        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertTrue(session.phantomShapeView === shapeView)
        let mask = try XCTUnwrap(shapeView.layer.mask as? CAShapeLayer)
        XCTAssertEqual(mask.fillRule, .evenOdd)
        XCTAssertNotNil(mask.path)
        XCTAssertTrue(layers.repeatedRows.isHidden)
        XCTAssertFalse(layers.solidCoverage.isHidden)
        assertNoAnimations(in: shapeView.layer)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testNewViewportDetailPreemptsRemainingSourceWorkWithinDrain()
        throws {
        let imageLoadCount = Counter()
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(true)
        let fixture = try makeFixture(
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    imageLoadCount.value += 1
                    return {}
                }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                guard limitsDrainToOneJob.value else { return 0 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let destinationCellCount = try XCTUnwrap(
            session.currentPhantomPlan?.cellCandidates.count
        )
        for _ in 0 ..< destinationCellCount * 3 {
            guard session.phantomCells.count < destinationCellCount else {
                break
            }
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertEqual(session.phantomCells.count, destinationCellCount)

        limitsDrainToOneJob.value = false
        clockCalls.value = 0
        let sourceResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

        XCTAssertLessThanOrEqual(sourceResult.processedCount, 8)
        XCTAssertFalse(session.sourceOverscanCells.isEmpty)
        XCTAssertGreaterThan(imageLoadCount.value, 0)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDrainFlushesDeferredClassificationPaint() throws {
        let fixture = try makeFixture(
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            presentationProgress: 0.5,
            panDeltaY: 0
        ))
        let session = try activeSession(fixture)
        drainQueuedWork(fixture)
        let sourceRepresentationIDs = Set(
            session.sourceOverscanCells.values.map(ObjectIdentifier.init)
        )
        XCTAssertFalse(sourceRepresentationIDs.isEmpty)
        let unpreparedSourceRepresentationIDs = sourceRepresentationIDs
            .intersection(
                session.sourceRepresentations.unpreparedMarginTrackingRepresentationIDs
            )
        let visibleRepresentationID = try XCTUnwrap(
            unpreparedSourceRepresentationIDs.first { representationID in
                guard let itemIndex = session.sourceRepresentations.records[
                    representationID
                ]?.itemIndex else {
                    return false
                }
                return session.viewportSelectedSourceItems.contains(itemIndex)
            }
        )
        let bufferedRepresentationID = try XCTUnwrap(
            unpreparedSourceRepresentationIDs.first { representationID in
                guard let itemIndex = session.sourceRepresentations.records[
                    representationID
                ]?.itemIndex else {
                    return false
                }
                return !session.viewportSelectedSourceItems.contains(itemIndex)
            }
        )
        session.deferClassificationPaint(for: bufferedRepresentationID)
        session.deferClassificationPaint(for: visibleRepresentationID)

        let paintResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 1, time: 1)
        )
        XCTAssertEqual(paintResult.processedCount, 1)
        XCTAssertFalse(
            session.sourceRepresentations.deferredClassificationPaintRepresentationIDs.contains(
                visibleRepresentationID
            )
        )
        XCTAssertTrue(
            session.sourceRepresentations.deferredClassificationPaintRepresentationIDs.contains(
                bufferedRepresentationID
            )
        )
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.sourceRepresentations.deferredClassificationPaintRepresentationIDs.isEmpty
        )
    }

    func testDirtySourceRefreshRespectsTimeAndCannotBeStarvedAcrossDrains()
        throws {
        let imageLoadCount = Counter()
        let clockCalls = Counter()
        let clockMode = Box(0)
        let fixture = try makeFixture(
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    imageLoadCount.value += 1
                    return {}
                }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                switch clockMode.value {
                case 0:
                    return clockCalls.value < 2 ? 0 : 0.005
                case 1:
                    return clockCalls.value == 0 ? 0 : 0.005
                default:
                    return 0
                }
            }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        for _ in 0 ..< 500 {
            guard session.sourceOverscanCells.isEmpty else { break }
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertFalse(session.sourceOverscanCells.isEmpty)
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertEqual(imageLoadCount.value, 0)

        clockMode.value = 1
        clockCalls.value = 0
        let expiredResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(expiredResult.processedCount, 0)
        XCTAssertTrue(expiredResult.stoppedForTimeLimit)
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)

        clockMode.value = 0
        clockCalls.value = 0
        let refreshResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(refreshResult.processedCount, 1)
        XCTAssertEqual(imageLoadCount.value, 0)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)

        clockCalls.value = 0
        let detailResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(detailResult.processedCount, 1)
        XCTAssertGreaterThan(imageLoadCount.value, 0)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testSourceJobWaitsWhenItsDependentWorkCannotFitInDrain() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        for itemIndex in 0 ..< 6 {
            let cell = MobilePlayerCollectionBrowserCell(frame: .zero)
            cell.configure(
                contentIdentity: MobilePlayerBrowserContentIdentity(
                    collectionId: "queued",
                    tokenIndex: itemIndex
                ),
                itemCount: 6,
                imageSources: nil,
                requiredImageQuality: .thumbnail,
                missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                    thumbnailAspectRatio: nil
                ),
                imageLoadPolicy: .disabled
            )
            fixture.renderer.willDisplayCell(
                cell,
                at: IndexPath(item: itemIndex, section: 0)
            )
        }
        XCTAssertTrue(session.destinationPlanRefreshIsDirty)

        let result = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

        XCTAssertEqual(result.processedCount, 8)
        XCTAssertTrue(session.sourceOverscanCells.isEmpty)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDrainStopsAtTwoMillisecondBudget() throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(clock: {
            defer { clockCalls.value += 1 }
            return clockCalls.value < 2 ? 0 : 0.002_001
        })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertTrue(result.stoppedForTimeLimit)
        XCTAssertGreaterThanOrEqual(result.elapsed, 0.002)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDeferredRefreshWaitsWhenBudgetIsExhausted() throws {
        let clockCalls = Counter()
        let returnsExpiredTime = Box(true)
        let fixture = try makeFixture(clock: {
            defer { clockCalls.value += 1 }
            guard returnsExpiredTime.value else { return 0 }
            return clockCalls.value == 0 ? 0 : 0.005
        })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        fixture.renderer.didConfigureCell(
            MobilePlayerCollectionBrowserCell(frame: .zero),
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)

        let expiredResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

        XCTAssertEqual(expiredResult.processedCount, 0)
        XCTAssertTrue(expiredResult.stoppedForTimeLimit)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)

        returnsExpiredTime.value = false
        let refreshResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

        XCTAssertEqual(refreshResult.processedCount, 8)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 2)
        XCTAssertGreaterThan(fixture.configureCount.value, 0)
        XCTAssertLessThanOrEqual(fixture.configureCount.value, 7)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }
}

nonisolated final class GridTransitionDisplayLinkFrameDriverTests:
    XCTestCase {}

@MainActor
extension GridTransitionDisplayLinkFrameDriverTests {
    func testFrameClampsAdaptiveBudgetToSixtyThroughOneTwentyHertz() {
        let fastFrame = GridTransitionFrame(
            timestamp: 10,
            targetTimestamp: 10 + 1.0 / 240
        )
        let normalFrame = GridTransitionFrame(
            timestamp: 10,
            targetTimestamp: 10 + 1.0 / 120
        )
        let slowFrame = GridTransitionFrame(
            timestamp: 10,
            targetTimestamp: 10 + 1.0 / 30
        )

        XCTAssertEqual(fastFrame.duration, 1.0 / 240, accuracy: 0.000_001)
        XCTAssertEqual(
            fastFrame.adaptiveDuration,
            1.0 / 120,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            normalFrame.adaptiveDuration,
            1.0 / 120,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            slowFrame.adaptiveDuration,
            1.0 / 60,
            accuracy: 0.000_001
        )
    }

    func testFramesRunInTrackingModeAndLifecycleIsTerminalAfterInvalidation() {
        let driver = GridTransitionDisplayLinkFrameDriver()
        var frameCount = 0
        var frameModes = [RunLoop.Mode?]()
        var framesArrivedOnMainThread = true

        driver.start { _ in
            frameCount += 1
            frameModes.append(RunLoop.current.currentMode)
            framesArrivedOnMainThread = framesArrivedOnMainThread
                && Thread.isMainThread
        }

        XCTAssertTrue(driver.isRunning)
        XCTAssertTrue(runMainTrackingRunLoop {
            frameCount > 0
        })
        XCTAssertTrue(framesArrivedOnMainThread)
        XCTAssertEqual(frameModes.first, .tracking)

        driver.stop()
        let stoppedFrameCount = frameCount
        XCTAssertFalse(driver.isRunning)
        XCTAssertFalse(runMainTrackingRunLoop(
            until: { frameCount > stoppedFrameCount },
            timeout: 0.05
        ))

        driver.start { _ in
            frameCount += 1
        }

        XCTAssertTrue(driver.isRunning)
        XCTAssertTrue(runMainTrackingRunLoop {
            frameCount > stoppedFrameCount
        })

        driver.invalidate()
        let invalidatedFrameCount = frameCount
        XCTAssertFalse(driver.isRunning)

        driver.start { _ in
            frameCount += 1
        }

        XCTAssertFalse(driver.isRunning)
        XCTAssertFalse(runMainTrackingRunLoop(
            until: { frameCount > invalidatedFrameCount },
            timeout: 0.05
        ))
    }
}
