// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobilePlayerCollectionBrowserGridRendererTests {
    func testReplacementPlaneRejectsQueuedSourceMaterialization() throws {
        let fixture = try makeFixture(clock: { 0 })
        let replacementFixture = try makeFixture(itemCount: 1, clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )

        XCTAssertTrue(fixture.renderer.installPlane(
            replacementFixture.planeRequest
        ))
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
        drainQueuedWork(fixture)

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertEqual(Set(session.sourceOverscanCells.keys), [0])
        let sourceCell = try XCTUnwrap(session.sourceOverscanCells[0])
        XCTAssertEqual(
            sourceCell.frame,
            replacementFixture.sourceLayout.itemFrame(at: 0)
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPlaneTaggedSourceOverscanMaterializesAfterInstallation() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)

        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(sessionBeforeDrain) = fixture.renderer.lifecycle
        else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(sessionBeforeDrain.sourceOverscanCells.isEmpty)

        drainQueuedWork(fixture)

        guard case let .active(sessionAfterDrain) = fixture.renderer.lifecycle
        else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertFalse(sessionAfterDrain.sourceOverscanCells.isEmpty)
        XCTAssertTrue(sessionAfterDrain.sourceOverscanCells.values.allSatisfy {
            $0.alpha == 1
        })
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testSourceOverscanIsLayeredAboveDestinationPhantoms() throws {
        let fixture = try makeFixture(
            itemCount: 6,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        let session = try activeSession(fixture)
        let source = try XCTUnwrap(session.sourceOverscanCells[3])
        let phantom = try XCTUnwrap(session.phantomCells[5])
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let visibleSource = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
        )
        let overlap = source.frame.intersection(phantom.frame)
        XCTAssertFalse(overlap.isNull)
        XCTAssertGreaterThan(overlap.width, 0)
        XCTAssertGreaterThan(overlap.height, 0)

        let shapeIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: shapeView)
        )
        let phantomIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: phantom)
        )
        let sourceIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: source)
        )
        let visibleSourceIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: visibleSource)
        )
        XCTAssertLessThan(shapeIndex, phantomIndex)
        XCTAssertLessThan(phantomIndex, sourceIndex)
        XCTAssertLessThan(sourceIndex, visibleSourceIndex)
    }

    func testVisibleNoPlaneSourceCellsPromoteWithoutAnotherRender() throws {
        let fixture = try makeFixture(
            itemCount: 30,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: 0,
                viewportPoint: CGPoint(
                    x: fixture.viewportView.bounds.midX,
                    y: fixture.viewportView.bounds.midY
                ),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.renderZoom(
            planeID: nil,
            scale: 0.8,
            panDeltaY: 0,
            sourceLayout: fixture.sourceLayout
        ))

        drainQueuedWork(fixture)

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let sourceCellIDs = Set(session.sourceOverscanCells.values.map(
            ObjectIdentifier.init
        ))
        let visibleSourceCells = fixture.renderer.viewportRenderCells.filter {
            sourceCellIDs.contains(ObjectIdentifier($0))
        }
        XCTAssertFalse(visibleSourceCells.isEmpty)
        XCTAssertTrue(visibleSourceCells.allSatisfy(\.usesForegroundImageLoading))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testVisibleActivePlaneSourceCellsPromoteWithoutAnotherRender() throws {
        let fixture = try makeFixture(
            itemCount: 30,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        drainQueuedWork(fixture)

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let sourceCellIDs = Set(session.sourceOverscanCells.values.map(
            ObjectIdentifier.init
        ))
        let visibleSourceCells = fixture.renderer.viewportRenderCells.filter {
            sourceCellIDs.contains(ObjectIdentifier($0))
        }
        XCTAssertFalse(visibleSourceCells.isEmpty)
        XCTAssertTrue(visibleSourceCells.allSatisfy(\.usesForegroundImageLoading))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testVisiblePhantomCellsPromoteWithoutAnotherRender() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let eligibilityReconciliationCount = fixture.renderer
            .foregroundEligibilityReconciliationCount

        drainQueuedWork(fixture)

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let phantomCellIDs = Set(session.phantomCells.values.map(
            ObjectIdentifier.init
        ))
        let visiblePhantomCells = fixture.renderer.viewportRenderCells.filter {
            phantomCellIDs.contains(ObjectIdentifier($0))
        }
        XCTAssertTrue(session.sourceOverscanCells.isEmpty)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(visiblePhantomCells.isEmpty)
        XCTAssertTrue(visiblePhantomCells.allSatisfy(
            \.usesForegroundImageLoading
        ))
        XCTAssertEqual(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            eligibilityReconciliationCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testCellEndDisplayRemovesDetailWithoutFilteringWholeQueue()
        throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(
            fixture.renderer.pendingDetailMaterializationWorkCount,
            1
        )
        let filterPassCount = fixture.renderer
            .transitionWorkQueueFilterPassCount

        fixture.renderer.didEndDisplayingCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )

        XCTAssertEqual(
            fixture.renderer.pendingDetailMaterializationWorkCount,
            0
        )
        XCTAssertEqual(
            fixture.renderer.transitionWorkQueueFilterPassCount,
            filterPassCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testQueuedDetailDemotesWhenCellLeavesCurrentViewport() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(
            fixture.renderer
                .pendingVisibleDetailMaterializationRepresentationIDs
                .contains(representationID)
        )

        sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY
        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )

        XCTAssertTrue(
            session.foregroundEligibleRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.currentViewportRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            fixture.renderer
                .pendingDetailMaterializationRepresentationIDs
                .contains(representationID)
        )
        XCTAssertFalse(
            fixture.renderer
                .pendingVisibleDetailMaterializationRepresentationIDs
                .contains(representationID)
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testForegroundEligibilityReconciliationUsesBufferedCoverage()
        throws {
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 5,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let terminalScale = fixture.planeRequest.transitionLayout
            .itemWidthRatio
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)
        let currentViewportRect = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        )
        let expectedCurrentCoverage = currentViewportRect.insetBy(
            dx: -currentViewportRect.width / 4,
            dy: -currentViewportRect.height / 4
        )
        let currentCoverage = try XCTUnwrap(
            session.foregroundCurrentViewportCoverage.installedRect
        )
        XCTAssertEqual(
            currentCoverage.width,
            expectedCurrentCoverage.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            currentCoverage.height,
            expectedCurrentCoverage.height,
            accuracy: 0.000_001
        )
        let reconciliationCount = fixture.renderer
            .foregroundEligibilityReconciliationCount

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale * 0.999,
            settleProgress: 0,
            panDeltaY: -1
        ))

        XCTAssertEqual(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            reconciliationCount
        )
        let actuallyEligibleIDs = foregroundEligibleRepresentationIDs(
            fixture: fixture,
            session: session,
            panDeltaY: -1,
            usesBufferedCoverage: false
        )
        XCTAssertTrue(actuallyEligibleIDs.isSubset(
            of: session.foregroundEligibleRepresentationIDs
        ))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: -fixture.viewportView.bounds.height
        ))
        XCTAssertGreaterThan(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            reconciliationCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testInstalledPhantomsStayEligibleWithinBufferedCoverage()
        throws {
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 1,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 0
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let terminalScale = fixture.planeRequest.transitionLayout
            .itemWidthRatio

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)
        let firstEligibleItems = foregroundEligiblePhantomItems(
            fixture: fixture,
            session: session,
            panDeltaY: 0
        )
        XCTAssertFalse(firstEligibleItems.isEmpty)
        XCTAssertEqual(firstEligibleItems, Set(session.phantomCells.keys))
        XCTAssertTrue(firstEligibleItems.allSatisfy {
            session.phantomCells[$0]?.usesForegroundImageLoading == true
        })

        let panDeltaY = -fixture.viewportView.bounds.height / 2
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: panDeltaY
        ))
        drainQueuedWork(fixture)
        let secondEligibleItems = foregroundEligiblePhantomItems(
            fixture: fixture,
            session: session,
            panDeltaY: panDeltaY
        )
        XCTAssertFalse(
            firstEligibleItems.subtracting(secondEligibleItems).isEmpty
        )
        XCTAssertFalse(
            secondEligibleItems.subtracting(firstEligibleItems).isEmpty
        )
        XCTAssertEqual(secondEligibleItems, Set(session.phantomCells.keys))
        XCTAssertTrue(secondEligibleItems.allSatisfy {
            session.phantomCells[$0]?.usesForegroundImageLoading == true
        })
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    /// Source cells and phantoms sit side by side on screen but are laid out
    /// on lattices whose spacings differ by the pitch ratio. Both are held to
    /// their own layout's spacing, so at any scale the whole screen shows one
    /// seam width — Photos never shows two.

    func testFadeFlushesPreparedSourceCoverageBeforeLockingFallbacks()
        throws {
        let image = makeImage()
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        _ = fixture.renderer.drainMaterializationWork()

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(session.preparedRepresentationIDs.contains(
            representationID
        ))
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertNotNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )
        XCTAssertFalse(session.lockedFallbackRepresentationIDs.contains(
            representationID
        ))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDestinationPlanRefreshBatchesAndDiscardsSupersededJobs() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let planGeneration = session.destinationPlaneCellPlanGeneration

        fixture.renderer.didConfigureCell(
            MobilePlayerCollectionBrowserCell(frame: .zero),
            at: IndexPath(item: 0, section: 0)
        )
        fixture.renderer.didConfigureCell(
            MobilePlayerCollectionBrowserCell(frame: .zero),
            at: IndexPath(item: 1, section: 0)
        )

        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        // Reconfiguring a cell must not advance the generation: that would
        // discard every queued phantom, and the replan that re-enqueues them
        // is the lowest-priority job in the drain.
        XCTAssertEqual(
            session.destinationPlaneCellPlanGeneration,
            planGeneration
        )

        let refreshResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )
        XCTAssertEqual(refreshResult.processedCount, 8)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 2)
        XCTAssertGreaterThan(
            session.destinationPlaneCellPlanGeneration,
            planGeneration,
            "the replan itself advances the generation"
        )
        XCTAssertGreaterThan(fixture.configureCount.value, 0)
        XCTAssertLessThanOrEqual(fixture.configureCount.value, 7)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPendingDetailLoadKeepsDestinationPlan() throws {
        let imageLoadCount = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    imageLoadCount.value += 1
                    return {}
                }
            ),
            clock: { 0 }
        )
        XCTAssertEqual(fixture.collectionView.visibleCells.count, 1)
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let planGeneration = session.destinationPlaneCellPlanGeneration

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(result.processedCount, 0)
        XCTAssertEqual(imageLoadCount.value, 1)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertEqual(
            session.destinationPlaneCellPlanGeneration,
            planGeneration
        )
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPreparedDetailRefreshesDestinationCoverage() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(result.processedCount, 0)
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 2)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertEqual(
            session.sourceCoverage.coveredDestinationItems,
            Set([0])
        )
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 2)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPreparedDetailsBatchSourceCoverageRefresh() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 60,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)

        let result = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

        XCTAssertEqual(result.processedCount, 8)
        XCTAssertGreaterThan(session.preparedRepresentationIDs.count, 1)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 2)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testTransitionImageCompletionsBatchSourceCoverageRefresh()
        async throws {
        let callbacks = Box<[((UIImage?) -> Void)]>([])
        let fixture = try makeFixture(
            itemCount: 60,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, completion in
                    callbacks.value.append(completion)
                    return {}
                }
            ),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertGreaterThan(callbacks.value.count, 1)
        let sourceCoverageBuildCount = fixture.renderer
            .sourceCoverageBuildCount
        XCTAssertGreaterThan(session.transitionImageLoads.count, 1)

        for callback in callbacks.value {
            callback(makeImage())
        }
        await runOnNextMainQueueTurn()
        XCTAssertGreaterThan(
            fixture.renderer.pendingTransitionImageCompletionWorkCount,
            1
        )

        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(session.preparedRepresentationIDs.count, 1)
        XCTAssertEqual(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount + 1
        )
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testLateSourceOverscanOutsideRepresentationRectStaysUnclassified()
        throws {
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(true)
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            providesContentAccess: true,
            anchorItemIndex: 3,
            clock: {
                defer { clockCalls.value += 1 }
                guard limitsDrainToOneJob.value else { return 0 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let session = try activeSession(fixture)
        let sourceRect = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        ).insetBy(dx: 0, dy: -fixture.viewportView.bounds.height / 2)
        var lateSource: MobilePlayerCollectionBrowserCell?
        for _ in 0 ..< 100 where lateSource == nil {
            let existingIDs = Set(
                session.sourceOverscanCells.values.map(ObjectIdentifier.init)
            )
            clockCalls.value = 0
            let result = fixture.renderer.drainMaterializationWork()
            lateSource = session.sourceOverscanCells.values.first { cell in
                !existingIDs.contains(ObjectIdentifier(cell))
                    && !cell.convert(cell.bounds, to: fixture.collectionView)
                        .intersects(sourceRect)
            }
            if lateSource != nil {
                XCTAssertTrue(result.stoppedForTimeLimit)
            }
        }
        let source = try XCTUnwrap(lateSource)
        let representationID = ObjectIdentifier(source)

        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(source.alpha, 1, accuracy: 0.000_001)

        limitsDrainToOneJob.value = false
        drainQueuedWork(fixture)

        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertFalse(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertEqual(source.alpha, 1, accuracy: 0.000_001)
    }

    func testQueuedDetailIsPromotedWhenCellEntersViewport() throws {
        let imageLoadCount = Counter()
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(false)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
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
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY + 1
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.selectedSourceItems.isEmpty)
        drainQueuedWork(fixture)
        XCTAssertEqual(imageLoadCount.value, 0)

        sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY + 1
        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 1)

        sourceCell.frame.origin.y = fixture.viewportView.bounds.minY
        fixture.renderer.willDisplayCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 2)

        limitsDrainToOneJob.value = true
        clockCalls.value = 0
        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertEqual(imageLoadCount.value, 1)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }
}
