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
        XCTAssertTrue(session.preparedRepresentationIDs.contains(
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
        XCTAssertTrue(session.transitionImageLoads.isEmpty)
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
                session.unpreparedMarginTrackingRepresentationIDs
            )
        let visibleRepresentationID = try XCTUnwrap(
            unpreparedSourceRepresentationIDs.first { representationID in
                guard let itemIndex = session.cachedSourceRepresentations[
                    representationID
                ]?.itemIndex else {
                    return false
                }
                return session.viewportSelectedSourceItems.contains(itemIndex)
            }
        )
        let bufferedRepresentationID = try XCTUnwrap(
            unpreparedSourceRepresentationIDs.first { representationID in
                guard let itemIndex = session.cachedSourceRepresentations[
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
            session.deferredClassificationPaintRepresentationIDs.contains(
                visibleRepresentationID
            )
        )
        XCTAssertTrue(
            session.deferredClassificationPaintRepresentationIDs.contains(
                bufferedRepresentationID
            )
        )
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.deferredClassificationPaintRepresentationIDs.isEmpty
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

nonisolated final class MobilePlayerCollectionBrowserPinchFrameCoalescerTests: XCTestCase {}

@MainActor
extension MobilePlayerCollectionBrowserPinchFrameCoalescerTests {
    private func makeFrame(
        scale: CGFloat,
        location: CGPoint
    ) -> GridModePinchFrame {
        GridModePinchFrame(scale: scale, viewLocation: location)
    }

    func testTerminationFlushAppliesLatestChangedFrameOnce() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        coalescer.seed(makeFrame(
            scale: 1.2,
            location: CGPoint(x: 160, y: 320)
        ))
        let latestFrame = makeFrame(
            scale: 1.01,
            location: CGPoint(x: 160, y: 320)
        )
        coalescer.stage(latestFrame)

        coalescer.flush()
        coalescer.flush()

        XCTAssertEqual(appliedFrames, [latestFrame])
        XCTAssertEqual(latestFrame.sample.centroidY, latestFrame.viewLocation.y)
    }

    func testTerminationFlushAppliesBeganFrameWithoutChangedFrame() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        let beganFrame = makeFrame(
            scale: 1.2,
            location: CGPoint(x: 160, y: 320)
        )
        coalescer.seed(beganFrame)

        coalescer.flush()
        coalescer.flush()

        XCTAssertEqual(appliedFrames, [beganFrame])
    }

    func testInvalidationDropsPendingFrame() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        coalescer.stage(makeFrame(
            scale: 1.2,
            location: CGPoint(x: 160, y: 320)
        ))

        coalescer.invalidate()
        coalescer.flush()

        XCTAssertTrue(appliedFrames.isEmpty)
    }

    func testStagedFrameAppliesDuringTrackingRunLoopMode() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        defer { coalescer.invalidate() }
        let firstFrame = makeFrame(
            scale: 1.1,
            location: CGPoint(x: 140, y: 280)
        )
        let latestFrame = makeFrame(
            scale: 1.2,
            location: CGPoint(x: 150, y: 300)
        )
        coalescer.stage(firstFrame)
        coalescer.stage(latestFrame)

        XCTAssertTrue(runMainTrackingRunLoop {
            !appliedFrames.isEmpty
        })
        XCTAssertEqual(appliedFrames, [latestFrame])
    }
}
