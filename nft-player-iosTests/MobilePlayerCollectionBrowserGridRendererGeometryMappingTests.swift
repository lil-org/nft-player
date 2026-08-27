// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobilePlayerCollectionBrowserGridRendererTests {
    func testVisualGeometryUsesEffectiveLayoutDirection() throws {
        let fixture = try makeFixture(itemCount: 6)
        fixture.collectionView.semanticContentAttribute = .forceRightToLeft

        let rightToLeftGeometry = fixture.collectionView.visualGeometry(
            for: fixture.sourceLayout
        )

        XCTAssertTrue(rightToLeftGeometry.mirrorsHorizontally)
        fixture.collectionView.semanticContentAttribute = .forceLeftToRight
        let leftToRightGeometry = fixture.collectionView.visualGeometry(
            for: fixture.sourceLayout
        )
        XCTAssertFalse(leftToRightGeometry.mirrorsHorizontally)
    }

    func testCellWhoseDestinationLeavesTheViewportIsHeldForMarginCoverage() throws {
        let image = makeImage()
        func counts(
            anchorItemIndex: Int
        ) throws -> (corrections: Int, held: Int) {
            let fixture = try makeFixture(
                itemCount: 300,
                sourceColumnCount: 3,
                destinationColumnCount: 1,
                destinationMode: .large,
                showsSourceCell: true,
                providesContentAccess: true,
                anchorItemIndex: anchorItemIndex,
                imageAccess: .init(
                    cachedImage: { imageSources, _ in
                        (imageSources.thumbnailDescriptor, .thumbnail, image)
                    },
                    loadImage: { _, _ in {} }
                )
            )
            defer { _ = fixture.renderer.finish(preservingCarryover: false) }
            begin(fixture)
            XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
            drainQueuedWork(fixture)
            let session = try activeSession(fixture)
            XCTAssertTrue(
                fixture.collectionView.visibleCells.allSatisfy {
                    $0.alpha == 1
                },
                "no source cell fades out and leaves a hole in the margins"
            )
            return (
                session.cellFrameCorrections.count,
                session.marginCoverageRepresentationIDs.count
            )
        }

        let onScreen = try counts(anchorItemIndex: 0)
        XCTAssertGreaterThan(
            onScreen.corrections,
            0,
            "an on-screen destination still gets its frame correction"
        )

        let offScreen = try counts(anchorItemIndex: 200)
        XCTAssertEqual(
            offScreen.corrections,
            0,
            "an off-screen destination gets no frame correction"
        )
        XCTAssertGreaterThan(
            offScreen.held,
            0,
            "an off-screen destination is held on the source lattice"
        )
    }

    func testCacheMissOffscreenDestinationStaysHeldThroughRetry()
        async throws {
        let callbacks = Box<[(UIImage?) -> Void]>([])
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 3,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    callbacks.value.append(callback)
                    return {}
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(sourceCell)
        let destinationItem = try XCTUnwrap(
            session.reassignments[0]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )

        XCTAssertEqual(callbacks.value.count, 0)
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )

        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertEqual(callbacks.value.count, 0)
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        drainQueuedWork(fixture)
        let firstLoadCount = callbacks.value.count
        XCTAssertGreaterThan(firstLoadCount, 0)

        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            presentationProgress: 0,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertEqual(callbacks.value.count, firstLoadCount)
        XCTAssertNotNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            presentationProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertNotNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        for callback in callbacks.value.prefix(firstLoadCount) {
            callback(nil)
        }
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)
        XCTAssertNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        drainQueuedWork(fixture)
        let retryCallbacks = callbacks.value.dropFirst(firstLoadCount)
        XCTAssertFalse(retryCallbacks.isEmpty)

        let image = makeImage()
        for callback in retryCallbacks {
            callback(image)
        }
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(primaryTransitionImage(in: sourceCell) === image)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: -targetOffsetY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertGreaterThan(contentContainer.alpha, 0)
    }

    func testPendingBaseCarryoverReclassifiesWithoutAnOnScreenCorrection()
        throws {
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 3,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        sourceCell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 0
            ),
            image: makeImage(),
            usesNativeMetalCardCornerMask: false
        ))
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(sourceCell)
        let destinationItem = try XCTUnwrap(session.reassignments[0])
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )

        XCTAssertNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(sourceCell.holdsCarryoverForPendingBaseImage)
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 1, accuracy: 0.000_001)

        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 1, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )
    }

    func testTerminalSettleContinuouslyRetiresVisibleMarginSourceToOffscreenDestination()
        throws {
        let ratios: [CGFloat] = [
            1, 1, 4, 1, 1, 0.25,
            1, 1, 4, 1, 1, 0.25,
        ]
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 3,
            heightToWidthRatios: ratios,
            sourceContentOffsetY: 158,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceAnchorFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 3)
        )
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: 3,
                viewportPoint: CGPoint(
                    x: sourceAnchorFrame.midX,
                    y: sourceAnchorFrame.midY
                        - fixture.collectionView.contentOffset.y
                ),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: fixture.collectionView.contentOffset.y
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let sourceRepresentation = try XCTUnwrap(
            session.cachedSourceRepresentations.values.first {
                $0.itemIndex == 6
            }
        )
        let representationID = ObjectIdentifier(sourceRepresentation.cell)
        let destinationItem = try XCTUnwrap(
            session.reassignments[sourceRepresentation.itemIndex]
        )
        XCTAssertEqual(destinationItem, 6)
        XCTAssertNotNil(session.phantomCells[4])

        let initialSourceFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertNotNil(PlayerBrowserGridGeometry.visibleRect(
            initialSourceFrame,
            clippedTo: fixture.viewportView.bounds
        ))

        let terminalScale = fixture.planeRequest.transitionLayout.itemWidthRatio
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let marginFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(PlayerBrowserGridGeometry.visibleRect(
            marginFrame,
            clippedTo: fixture.viewportView.bounds
        ))
        let marginOccupantFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                marginOccupantFrame
            )
        )

        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: terminalScale,
            panDeltaY: 0
        )
        let destinationLayoutFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let destinationFrame = destinationLayoutFrame.offsetBy(
            dx: 0,
            dy: -terminalPlane.incomingContentOffsetY
        )
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            destinationFrame,
            clippedTo: fixture.viewportView.bounds
        ))

        let tailStart = PlayerBrowserGridCrossfade
            .contentFadeEndSettleProgress
        let progressAtNinety = (0.9 - tailStart) / (1 - tailStart)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.9,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress),
            progressAtNinety,
            accuracy: 0.000_001
        )
        // The overlay fades uniformly with the content fade — the retirement
        // visibility ramp shapes only the flight transform, never the alpha.
        XCTAssertEqual(
            try XCTUnwrap(transitionContentContainer(
                in: sourceRepresentation.cell
            )).alpha,
            1,
            accuracy: 0.000_001
        )
        let ninetyPercentFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertNotNil(PlayerBrowserGridGeometry.visibleRect(
            ninetyPercentFrame,
            clippedTo: fixture.viewportView.bounds
        ))
        let ninetyPercentOccupantFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                ninetyPercentOccupantFrame
            )
        )
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                marginOccupantFrame
            )
        )

        let offscreenBoundaryPan = -(
            destinationFrame.minY - fixture.viewportView.bounds.maxY - 1
        )
        let offscreenBoundaryPlane = fixture.planeRequest.crossfade
            .outgoingPlane(
                scale: terminalScale,
                panDeltaY: offscreenBoundaryPan
            )
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            destinationLayoutFrame.offsetBy(
                dx: 0,
                dy: -offscreenBoundaryPlane.incomingContentOffsetY
            ),
            clippedTo: fixture.viewportView.bounds
        ))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.9,
            panDeltaY: offscreenBoundaryPan
        ))
        let offscreenBoundaryProgress = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )

        let shallowBoundaryPan = -(
            destinationFrame.minY - fixture.viewportView.bounds.maxY + 1
        )
        let shallowBoundaryPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: terminalScale,
            panDeltaY: shallowBoundaryPan
        )
        let shallowVisibleRect = try XCTUnwrap(
            PlayerBrowserGridGeometry.visibleRect(
                destinationLayoutFrame.offsetBy(
                    dx: 0,
                    dy: -shallowBoundaryPlane.incomingContentOffsetY
                ),
                clippedTo: fixture.viewportView.bounds
            )
        )
        XCTAssertEqual(shallowVisibleRect.height, 1, accuracy: 0.000_001)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.9,
            panDeltaY: shallowBoundaryPan
        ))
        let shallowBoundaryProgress = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertEqual(
            offscreenBoundaryProgress,
            progressAtNinety,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            shallowBoundaryProgress,
            offscreenBoundaryProgress,
            accuracy: 0.000_001
        )

        let progressAtNinetyNine = (0.99 - tailStart) / (1 - tailStart)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.99,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            try XCTUnwrap(session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress),
            progressAtNinetyNine,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(transitionContentContainer(
                in: sourceRepresentation.cell
            )).alpha,
            1,
            accuracy: 0.000_001
        )
        let ninetyNinePercentFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertGreaterThan(
            ninetyNinePercentFrame.minY,
            ninetyPercentFrame.minY
        )
        XCTAssertLessThan(
            ninetyNinePercentFrame.maxY,
            ninetyPercentFrame.maxY
        )
        XCTAssertGreaterThan(destinationFrame.minY, ninetyNinePercentFrame.minY)
        XCTAssertLessThan(destinationFrame.maxY, ninetyNinePercentFrame.maxY)
        XCTAssertLessThan(
            destinationFrame.minY - ninetyNinePercentFrame.minY,
            ninetyNinePercentFrame.minY - ninetyPercentFrame.minY
        )
        XCTAssertLessThan(
            ninetyNinePercentFrame.maxY - destinationFrame.maxY,
            ninetyPercentFrame.maxY - ninetyNinePercentFrame.maxY
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 1,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress,
            1
        )
        XCTAssertEqual(
            try XCTUnwrap(transitionContentContainer(
                in: sourceRepresentation.cell
            )).alpha,
            1,
            accuracy: 0.000_001
        )
        let terminalSourceFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertEqual(
            terminalSourceFrame.minY,
            destinationFrame.minY,
            accuracy: 0.01
        )
        XCTAssertEqual(
            terminalSourceFrame.height,
            destinationFrame.height,
            accuracy: 0.01
        )
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            terminalSourceFrame,
            clippedTo: fixture.viewportView.bounds
        ))
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                marginOccupantFrame
            )
        )

        _ = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .large
        ))
        guard case let .committing(commit) = fixture.renderer.lifecycle else {
            return XCTFail("Expected a committing renderer session")
        }
        XCTAssertFalse(commit.sources.contains {
            $0.content?.identity.tokenIndex == sourceRepresentation.itemIndex
        })
    }

    func testMarginCoverageReclassifiesAndRestoresPreparedContentDuringPan()
        throws {
        let returnsCachedImage = Box(true)
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    returnsCachedImage.value
                        ? (
                            imageSources.thumbnailDescriptor,
                            .thumbnail,
                            image
                        )
                        : nil
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.filter {
                representationID in
                guard let representation = session
                    .cachedSourceRepresentations[representationID],
                      let destinationItem = session.reassignments[
                          representation.itemIndex
                      ],
                      let destinationFrame = fixture.destinationLayout
                          .itemFrame(at: destinationItem) else {
                    return false
                }
                return destinationFrame.minY
                    >= fixture.viewportView.bounds.maxY
            }.min { lhs, rhs in
                let lhsItem = session.cachedSourceRepresentations[lhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let rhsItem = session.cachedSourceRepresentations[rhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let lhsY = lhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                let rhsY = rhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                return lhsY < rhsY
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let settleProgress: CGFloat = 0.5

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(session.lastContentFadeAlpha, 0)
        XCTAssertEqual(representation.cell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)
        XCTAssertNil(session.cellFrameCorrections[representationID])
        let marginTransform = representation.cell.transform
        XCTAssertEqual(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ],
            destinationItem
        )

        returnsCachedImage.value = false
        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: scale,
            panDeltaY: onScreenPanDeltaY
        )
        XCTAssertTrue(destinationFrame.offsetBy(
            dx: -fixture.collectionView.contentOffset.x,
            dy: -terminalPlane.incomingContentOffsetY
        ).intersects(fixture.viewportView.bounds))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        let visibilityProgress = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertGreaterThan(visibilityProgress, 0)
        XCTAssertLessThan(visibilityProgress, 0.1)
        XCTAssertEqual(
            representation.cell.transform.a,
            marginTransform.a,
            accuracy: 0.01
        )
        XCTAssertEqual(
            representation.cell.transform.d,
            marginTransform.d,
            accuracy: 0.01
        )
        XCTAssertEqual(
            representation.cell.transform.tx,
            marginTransform.tx,
            accuracy: 2
        )
        XCTAssertEqual(
            representation.cell.transform.ty,
            marginTransform.ty,
            accuracy: 2
        )
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )
        drainQueuedWork(fixture)
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(representation.cell.transform, marginTransform)
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)
        XCTAssertNil(contentContainer.layer.animation(forKey: "opacity"))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ],
            destinationItem
        )
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 1,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertEqual(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress,
            1
        )
        let expectedTerminalFrame = destinationFrame.offsetBy(
            dx: -fixture.collectionView.contentOffset.x,
            dy: -terminalPlane.incomingContentOffsetY
        )
        let actualTerminalFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertEqual(
            actualTerminalFrame.minX,
            expectedTerminalFrame.minX,
            accuracy: 0.01
        )
        XCTAssertEqual(
            actualTerminalFrame.minY,
            expectedTerminalFrame.minY,
            accuracy: 0.01
        )
        XCTAssertEqual(
            actualTerminalFrame.width,
            expectedTerminalFrame.width,
            accuracy: 0.01
        )
        XCTAssertEqual(
            actualTerminalFrame.height,
            expectedTerminalFrame.height,
            accuracy: 0.01
        )
    }

    func testLockedMarginCoverageFadesWhenPanReclassifiesItOnScreen()
        throws {
        let returnsCachedImage = Box(true)
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    returnsCachedImage.value
                        ? (
                            imageSources.thumbnailDescriptor,
                            .thumbnail,
                            image
                        )
                        : nil
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.filter {
                representationID in
                guard let representation = session
                    .cachedSourceRepresentations[representationID],
                      fixture.collectionView.indexPath(
                          for: representation.cell
                      ) != nil,
                      let destinationItem = session.reassignments[
                          representation.itemIndex
                      ],
                      let destinationFrame = fixture.destinationLayout
                          .itemFrame(at: destinationItem) else {
                    return false
                }
                return destinationFrame.minY
                    >= fixture.viewportView.bounds.maxY
            }.min { lhs, rhs in
                let lhsItem = session.cachedSourceRepresentations[lhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let rhsItem = session.cachedSourceRepresentations[rhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let lhsY = lhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                let rhsY = rhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                return lhsY < rhsY
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let indexPath = try XCTUnwrap(
            fixture.collectionView.indexPath(for: representation.cell)
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let settleProgress: CGFloat = 0.5
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        fixture.renderer.didConfigureCell(
            representation.cell,
            at: indexPath
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(representation.cell.alpha, 1, accuracy: 0.000_001)

        returnsCachedImage.value = false
        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        contentContainer.layer.add(opacity, forKey: "opacity")
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            presentationProgress: 0,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertNil(contentContainer.layer.animation(forKey: "opacity"))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            presentationProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertEqual(session.lastContentFadeAlpha, 0, accuracy: 0.000_001)
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))

        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        _ = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertEqual(
            representation.cell.alpha,
            1,
            accuracy: 0.000_001
        )
        let inactiveContentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        XCTAssertEqual(
            inactiveContentContainer.alpha,
            0,
            accuracy: 0.000_001
        )
    }

    func testShapeMaskKeepsLockedMarginSourceCutOut() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            sourceColumnCount: 3,
            destinationColumnCount: 2,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 1_200,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        for _ in 0 ..< 200 {
            _ = fixture.renderer.drainMaterializationWork()
            if session.currentPhantomPlan?.shapeCoverage != nil,
               !session.marginCoverageRepresentationIDs.isEmpty,
               !session.sourceCoverageRefreshIsDirty,
               !session.destinationPlanRefreshIsDirty,
               !session.phantomShapeRefreshIsDirty {
                break
            }
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        let representationID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.first {
                representationID in
                guard let representation = session
                    .cachedSourceRepresentations[representationID],
                      fixture.collectionView.indexPath(
                          for: representation.cell
                      ) != nil,
                      let destinationItem = session.reassignments[
                          representation.itemIndex
                      ],
                      let destinationFrame = fixture.destinationLayout
                          .itemFrame(at: destinationItem) else {
                    return false
                }
                let sourceFrame = representation.cell.convert(
                    representation.cell.bounds,
                    to: fixture.collectionView
                )
                return destinationFrame.minY
                    >= fixture.viewportView.bounds.maxY
                    && shapeView.frame.contains(CGPoint(
                        x: sourceFrame.midX,
                        y: sourceFrame.midY
                    ))
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let indexPath = try XCTUnwrap(
            fixture.collectionView.indexPath(for: representation.cell)
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let terminalScale = fixture.planeRequest.transitionLayout
            .itemWidthRatio
        let settleProgress: CGFloat = 0.5
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        fixture.renderer.didConfigureCell(
            representation.cell,
            at: indexPath
        )

        let sourceFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.collectionView
        )
        let sourcePoint = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let shapeCoverage = try XCTUnwrap(
            session.currentPhantomPlan?.shapeCoverage
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )
        XCTAssertEqual(representation.cell.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(shapeView.frame.contains(sourcePoint))
        XCTAssertFalse(shapeCoverage.excludedFrames.contains(sourceFrame))
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(sourceFrame)
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            sourcePoint,
            in: shapeView
        ))

        let onScreenPanDeltaY = -(
            destinationFrame.minY - fixture.viewportView.bounds.maxY + 1
        )
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))
        let reclassifiedFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        _ = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertEqual(
            representation.cell.alpha,
            1,
            accuracy: 0.000_001
        )
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                reclassifiedFrame
            )
        )
    }

    /// The seam has to stay `spacing` wide at any plane scale, so cells grow
    /// above unity and shrink below it. A pinch that reverses through unity
    /// must pick up the opposite correction, never keep the stale one, and must
    /// be back to identity at exactly unity.

    func testSeamCompensationTracksThePlaneThroughUnity() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 200,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(
                    x: fixture.viewportView.bounds.midX,
                    y: fixture.viewportView.bounds.midY
                ),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        XCTAssertGreaterThan(fixture.sourceLayout.interItemSpacing, 0)

        func factors(scale: CGFloat, settleProgress: CGFloat) -> [CGFloat] {
            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: scale,
                settleProgress: settleProgress,
                panDeltaY: 0
            ))
            return session.cachedSourceRepresentations
                .filter { session.cellFrameCorrections[$0.key] == nil }
                .map { $0.value.cell.transform.a }
        }

        let grown = factors(scale: 2, settleProgress: 0.5)
        XCTAssertFalse(grown.isEmpty)
        for factor in grown {
            XCTAssertGreaterThan(
                factor,
                1,
                "magnifying the plane grows the cells to hold the seams"
            )
        }

        let shrunk = factors(scale: 0.9, settleProgress: 0)
        XCTAssertFalse(shrunk.isEmpty)
        for factor in shrunk {
            XCTAssertLessThan(
                factor,
                1,
                "below unity the cells shrink to hold the seams open"
            )
        }

        for factor in factors(scale: 1, settleProgress: 0) {
            XCTAssertEqual(
                factor,
                1,
                accuracy: 0.000_001,
                "at unity there is no excess to hide"
            )
        }
    }

    func testCorrectedCellSeamsSurviveDecoupledScaleAndProgress() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(x: 160, y: 320),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let pair = try XCTUnwrap(
            horizontallyAdjacentCorrectedCells(
                fixture: fixture,
                session: session
            ),
            "Expected adjacent corrected source cells"
        )
        let settleProgress: CGFloat = 0.2
        let driftProgress: CGFloat = 0.7
        let scale = pow(
            fixture.planeRequest.transitionLayout.itemWidthRatio,
            driftProgress
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        let expectedSpacing = fixture.sourceLayout.interItemSpacing
            + settleProgress * (
                fixture.destinationLayout.interItemSpacing
                    - fixture.sourceLayout.interItemSpacing
            )
        XCTAssertEqual(
            horizontalScreenGap(
                left: pair.left,
                right: pair.right,
                in: fixture.viewportView
            ),
            expectedSpacing,
            accuracy: onePixelAccuracy(in: fixture.viewportView)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))
        assertTransform(pair.left.transform, equals: .identity)
        assertTransform(pair.right.transform, equals: .identity)
        XCTAssertFalse(session.hasCellFrameCorrectionTransforms)
    }

    func testPresentationProgressDrivesFadeIndependentlyFromGeometryProgress()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representation = try XCTUnwrap(
            session.cellFrameCorrections.first.flatMap {
                session.cachedSourceRepresentations[$0.key]
            }
        )
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let firstGeometryProgress: CGFloat = 0.2
        let secondGeometryProgress: CGFloat = 0.7
        let firstPresentationProgress: CGFloat = 0.6
        let secondPresentationProgress: CGFloat = 0.8

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: firstGeometryProgress,
            presentationProgress: firstPresentationProgress,
            panDeltaY: 0
        ))
        let firstGeometryTransform = representation.cell.transform
        let firstCollectionTransform = fixture.collectionView.transform
        let destinationPlanBuildCount = fixture.renderer
            .destinationPlanBuildCount
        let sourceCoverageBuildCount = fixture.renderer
            .sourceCoverageBuildCount
        let foregroundEligibilityReconciliationCount = fixture.renderer
            .foregroundEligibilityReconciliationCount
        XCTAssertEqual(
            session.lastSettleProgress,
            firstGeometryProgress,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            session.lastContentFadeAlpha,
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: firstPresentationProgress
            ),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderInteractionFade(
            id: fixture.planeRequest.id,
            presentationProgress: secondPresentationProgress
        ))
        assertTransform(
            representation.cell.transform,
            equals: firstGeometryTransform
        )
        assertTransform(
            fixture.collectionView.transform,
            equals: firstCollectionTransform
        )
        XCTAssertEqual(
            session.lastSettleProgress,
            firstGeometryProgress,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            fixture.renderer.destinationPlanBuildCount,
            destinationPlanBuildCount
        )
        XCTAssertEqual(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount
        )
        XCTAssertEqual(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            foregroundEligibilityReconciliationCount
        )
        XCTAssertEqual(
            contentContainer.alpha,
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: secondPresentationProgress
            ),
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: secondGeometryProgress,
            presentationProgress: secondPresentationProgress,
            panDeltaY: 0
        ))
        XCTAssertNotEqual(
            representation.cell.transform,
            firstGeometryTransform
        )
        XCTAssertEqual(
            session.lastSettleProgress,
            secondGeometryProgress,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            contentContainer.alpha,
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: secondPresentationProgress
            ),
            accuracy: 0.000_001
        )
    }

    func testLateCorrectedCellsReceiveSeamCompensationOnRebasedPlane()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(x: 160, y: 320),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        let installationScale: CGFloat = 0.8
        XCTAssertTrue(fixture.renderer.renderZoom(
            planeID: nil,
            scale: installationScale,
            panDeltaY: 0,
            sourceLayout: fixture.sourceLayout
        ))
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let pair = try XCTUnwrap(
            horizontallyAdjacentCorrectedCells(
                fixture: fixture,
                session: session
            ),
            "Expected adjacent corrected source cells"
        )

        XCTAssertEqual(session.lastSettleProgress, 0)
        XCTAssertEqual(
            horizontalScreenGap(
                left: pair.left,
                right: pair.right,
                in: fixture.viewportView
            ),
            fixture.sourceLayout.interItemSpacing,
            // The fractional Photos-matched spacing rounds cell frames to the
            // pixel grid, so a measured pair gap legitimately varies by up to
            // one device pixel.
            accuracy: onePixelAccuracy(in: fixture.viewportView)
        )
        XCTAssertTrue(session.hasCellFrameCorrectionTransforms)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.7,
            settleProgress: 0.25,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            horizontalScreenGap(
                left: pair.left,
                right: pair.right,
                in: fixture.viewportView
            ),
            fixture.sourceLayout.interItemSpacing,
            accuracy: onePixelAccuracy(in: fixture.viewportView)
        )
    }

    func testLateMaterializedCellsReceiveCurrentSeamCompensation() throws {
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 12,
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let sourceCell = try XCTUnwrap(
            session.sourceOverscanCells.values.first
        )
        let phantomCell = try XCTUnwrap(session.phantomCells.values.first)
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let sourceSpacing = fixture.sourceLayout.interItemSpacing
        let expectedSourceScaleX = 1
            + sourceSpacing * (appliedScaleX - 1)
                / (sourceCell.bounds.width * appliedScaleX)
        let expectedSourceScaleY = 1
            + sourceSpacing * (appliedScaleY - 1)
                / (sourceCell.bounds.height * appliedScaleY)
        XCTAssertEqual(
            sourceCell.transform.a,
            expectedSourceScaleX,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            sourceCell.transform.d,
            expectedSourceScaleY,
            accuracy: 0.000_001
        )
        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            panDeltaY: 0
        )
        let destinationSpacing = fixture.destinationLayout.interItemSpacing
        let expectedPhantomScaleX = 1
            + destinationSpacing
                * (appliedScaleX / terminalPlane.scaleX - 1)
                / (phantomCell.bounds.width * appliedScaleX)
        let expectedPhantomScaleY = 1
            + destinationSpacing
                * (appliedScaleY / terminalPlane.scaleY - 1)
                / (phantomCell.bounds.height * appliedScaleY)
        XCTAssertEqual(
            phantomCell.transform.a,
            expectedPhantomScaleX,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            phantomCell.transform.d,
            expectedPhantomScaleY,
            accuracy: 0.000_001
        )
    }

    func testRemovedCorrectionImmediatelyReturnsToSourceSeam()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let scale: CGFloat = 0.8
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        let correctedRepresentationIDs = Set(
            session.cellFrameCorrections.keys
        )
        XCTAssertFalse(correctedRepresentationIDs.isEmpty)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: -fixture.viewportView.bounds.height
        ))
        let removedRepresentationID = try XCTUnwrap(
            correctedRepresentationIDs.first {
                representationID in
                session.cellFrameCorrections[representationID] == nil
                    && !session.preparedRepresentationIDs.contains(
                        representationID
                    )
                    && session.detailedSourceCellItems[representationID] == nil
                    && session.cachedSourceRepresentations[representationID]?
                        .cell.superview != nil
            }
        )
        let cell = try XCTUnwrap(
            session.cachedSourceRepresentations[removedRepresentationID]?.cell
        )
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let spacing = fixture.sourceLayout.interItemSpacing
        let expectedScaleX = 1 + spacing * (appliedScaleX - 1)
            / (cell.bounds.width * appliedScaleX)
        let expectedScaleY = 1 + spacing * (appliedScaleY - 1)
            / (cell.bounds.height * appliedScaleY)
        XCTAssertEqual(cell.transform.a, expectedScaleX, accuracy: 0.000_001)
        XCTAssertEqual(cell.transform.d, expectedScaleY, accuracy: 0.000_001)
    }

    func testCorrectedCellLandsExactlyOnLargeDestinationAtTerminal()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.cellFrameCorrections.keys.first {
                session.cachedSourceRepresentations[$0] != nil
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let terminalScale = fixture.planeRequest.transitionLayout
            .itemWidthRatio

        XCTAssertEqual(
            fixture.sourceLayout.interItemSpacing,
            fixture.destinationLayout.interItemSpacing,
            "the seam is constant across grid modes, matching Photos"
        )
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 1,
            panDeltaY: 0
        ))
        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: terminalScale,
            panDeltaY: 0
        )
        let expectedFrame = destinationFrame.offsetBy(
            dx: -fixture.collectionView.contentOffset.x,
            dy: -terminalPlane.incomingContentOffsetY
        )
        let actualFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertEqual(actualFrame.minX, expectedFrame.minX, accuracy: 0.01)
        XCTAssertEqual(actualFrame.minY, expectedFrame.minY, accuracy: 0.01)
        XCTAssertEqual(actualFrame.width, expectedFrame.width, accuracy: 0.01)
        XCTAssertEqual(
            actualFrame.height,
            expectedFrame.height,
            accuracy: 0.01
        )
    }

    func testActivePlaneExtendsSourceOverscanAfterTransform() throws {
        let fixture = try makeFixture(
            sourceColumnCount: 1,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let initialCoverage = try XCTUnwrap(
            session.sourceOverscanCoverage.installedRect
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0,
            panDeltaY: 0
        ))

        let transformedCoverage = try XCTUnwrap(
            session.sourceOverscanCoverage.installedRect
        )
        let transformedViewport = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        )
        XCTAssertGreaterThan(
            transformedCoverage.width,
            initialCoverage.width
        )
        XCTAssertGreaterThan(
            transformedCoverage.height,
            initialCoverage.height
        )
        XCTAssertTrue(transformedCoverage.contains(transformedViewport))
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDetailSelectionUsesPostTransformViewport() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        cell.frame.origin.y = fixture.viewportView.bounds.maxY
            + fixture.viewportView.bounds.height / 4 + 20
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertFalse(session.selectedSourceItems.contains(0))
        let sourceCoverageBuildCount = fixture.renderer
            .sourceCoverageBuildCount

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0,
            panDeltaY: 0
        ))

        let postTransformViewport = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        )
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertEqual(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount
        )
        XCTAssertTrue(
            session.viewportDetailCoverage.installedRect?.contains(
                postTransformViewport
            ) == true
        )
        drainQueuedWork(fixture)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertGreaterThan(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testUniformMappingRefreshesSelectionInsideRetainedDetailCoverage()
        throws {
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 100, height: 1)
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let departingCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let enteringItem = PlayerBrowserGridRenderBudget.maximumVisualCellCount
        let enteringCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: enteringItem, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let departingFrame = departingCell.frame
        enteringCell.frame = CGRect(
            x: departingFrame.minX,
            y: fixture.viewportView.bounds.maxY + 8,
            width: departingFrame.width,
            height: departingFrame.height
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))
        let session = try activeSession(fixture)
        let initialSelectedItems = session.selectedSourceItems
        let detailCoverageRect = try XCTUnwrap(
            session.viewportDetailCoverage.installedRect
        )
        XCTAssertTrue(initialSelectedItems.contains(0))
        XCTAssertFalse(initialSelectedItems.contains(enteringItem))
        departingCell.frame = enteringCell.frame
        enteringCell.frame = departingFrame

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))

        XCTAssertEqual(
            session.viewportDetailCoverage.installedRect,
            detailCoverageRect
        )
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(
            enteringItem
        ))
        XCTAssertTrue(session.selectedSourceItems.contains(enteringItem))
        XCTAssertTrue(session.viewportSelectedSourceItems.isSubset(
            of: session.selectedSourceItems
        ))
        XCTAssertEqual(
            session.selectedSourceItems.count,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        XCTAssertFalse(
            initialSelectedItems.subtracting(session.selectedSourceItems).isEmpty
        )
        XCTAssertTrue(session.assignedDestinationItems.isEmpty)
    }

    func testRetainedDetailCoverageSelectsRegisteredHorizontalBufferCell()
        throws {
        let fixture = try makeFixture(
            itemCount: 30,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            anchorItemIndex: 0
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let edgeItem = 4
        let edgeCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: edgeItem, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        edgeCell.frame.origin.x = fixture.viewportView.bounds.maxX + 8
        let edgeRepresentationID = ObjectIdentifier(edgeCell)
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        XCTAssertEqual(
            session.cachedSourceRepresentations[edgeRepresentationID]?.itemIndex,
            edgeItem
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))

        let detailCoverageRect = try XCTUnwrap(
            session.viewportDetailCoverage.installedRect
        )
        XCTAssertTrue(
            session.cachedSourceRepresentations[edgeRepresentationID]?.cell
                === edgeCell
        )
        XCTAssertFalse(session.viewportSelectedSourceItems.contains(edgeItem))
        XCTAssertNil(session.cellFrameCorrections[edgeRepresentationID])
        edgeCell.frame.origin.x = 0

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))

        XCTAssertEqual(
            session.viewportDetailCoverage.installedRect,
            detailCoverageRect
        )
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(edgeItem))
    }

    func testDegradedMappingReleasesClaimWhenSelectedSourceLeaves() throws {
        var ratios = Array(repeating: CGFloat(1), count: 12)
        ratios[3] = 2
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            anchorItemIndex: 0,
            heightToWidthRatios: ratios
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let firstCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let laterCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 1, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let visibleFrame = firstCell.frame
        laterCell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        let firstSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 0)
        )
        let laterSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 1)
        )
        let firstDestinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: 0)
        )
        let request = GridModePlaneRequest(
            id: UUID(),
            toMode: fixture.planeRequest.toMode,
            layoutAspectState: fixture.planeRequest.layoutAspectState,
            anchorTokenIndex: 0,
            transitionLayout: fixture.planeRequest.transitionLayout,
            crossfade: fixture.planeRequest.crossfade,
            latticeMap: MobilePlayerBrowserGridLatticeMap(
                columnPitchRatio: 1,
                rowPitchRatio: 1,
                fromAnchorContentPoint: CGPoint(
                    x: firstSourceFrame.midX,
                    y: firstSourceFrame.midY
                ),
                toAnchorContentPoint: CGPoint(
                    x: firstDestinationFrame.midX,
                    y: firstDestinationFrame.midY
                )
            )
        )
        let destinationItem = try XCTUnwrap(
            fixture.destinationLayout.nearestItemIndex(
                to: request.latticeMap.destinationPoint(
                    fromSource: CGPoint(
                        x: laterSourceFrame.midX,
                        y: laterSourceFrame.midY
                    )
                ),
                tolerance: fixture.destinationLayout.interItemSpacing + 1
            )
        )

        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertFalse(session.selectedSourceItems.contains(1))
        XCTAssertEqual(session.reassignments[0], destinationItem)

        firstCell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        laterCell.frame = visibleFrame
        fixture.renderer.didConfigureCell(
            laterCell,
            at: IndexPath(item: 1, section: 0)
        )
        drainQueuedWork(fixture)

        XCTAssertFalse(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.selectedSourceItems.contains(1))
        XCTAssertNil(session.reassignments[0])
        XCTAssertEqual(session.reassignments[1], destinationItem)
        XCTAssertTrue(session.assignedDestinationItems.contains(
            destinationItem
        ))
    }

    func testDegradedMappingPrioritizesVisibleSourceOverBufferedSource()
        throws {
        var ratios = Array(repeating: CGFloat(1), count: 12)
        ratios[3] = 2
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            anchorItemIndex: 0,
            heightToWidthRatios: ratios
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let firstCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let laterCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 1, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let visibleFrame = firstCell.frame
        let bufferedFrame = CGRect(
            x: visibleFrame.minX,
            y: fixture.viewportView.bounds.maxY + 8,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        laterCell.frame = bufferedFrame
        let firstSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 0)
        )
        let laterSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 1)
        )
        let firstDestinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: 0)
        )
        let request = GridModePlaneRequest(
            id: UUID(),
            toMode: fixture.planeRequest.toMode,
            layoutAspectState: fixture.planeRequest.layoutAspectState,
            anchorTokenIndex: 0,
            transitionLayout: fixture.planeRequest.transitionLayout,
            crossfade: fixture.planeRequest.crossfade,
            latticeMap: MobilePlayerBrowserGridLatticeMap(
                columnPitchRatio: 1,
                rowPitchRatio: 1,
                fromAnchorContentPoint: CGPoint(
                    x: firstSourceFrame.midX,
                    y: firstSourceFrame.midY
                ),
                toAnchorContentPoint: CGPoint(
                    x: firstDestinationFrame.midX,
                    y: firstDestinationFrame.midY
                )
            )
        )
        let destinationItem = try XCTUnwrap(
            fixture.destinationLayout.nearestItemIndex(
                to: request.latticeMap.destinationPoint(
                    fromSource: CGPoint(
                        x: laterSourceFrame.midX,
                        y: laterSourceFrame.midY
                    )
                ),
                tolerance: fixture.destinationLayout.interItemSpacing + 1
            )
        )

        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        fixture.renderer.didConfigureCell(
            firstCell,
            at: IndexPath(item: 0, section: 0)
        )
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.selectedSourceItems.contains(1))
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(0))
        XCTAssertFalse(session.viewportSelectedSourceItems.contains(1))
        XCTAssertEqual(session.reassignments[0], destinationItem)
        XCTAssertNil(session.reassignments[1])
        let detailCoverageRect = try XCTUnwrap(
            session.viewportDetailCoverage.installedRect
        )

        firstCell.frame = bufferedFrame
        laterCell.frame = visibleFrame
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: request.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)

        XCTAssertEqual(
            session.viewportDetailCoverage.installedRect,
            detailCoverageRect
        )
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.selectedSourceItems.contains(1))
        XCTAssertFalse(session.viewportSelectedSourceItems.contains(0))
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(1))
        XCTAssertNil(session.reassignments[0])
        XCTAssertEqual(session.reassignments[1], destinationItem)
        XCTAssertTrue(session.assignedDestinationItems.contains(
            destinationItem
        ))
    }

    func testDegradedMappingRequeuesBufferedCollisionLoserWhenClaimFrees()
        throws {
        let image = makeImage()
        var ratios = Array(repeating: CGFloat(1), count: 12)
        ratios[3] = 2
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            heightToWidthRatios: ratios,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let firstSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 0)
        )
        let firstDestinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: 0)
        )
        let request = GridModePlaneRequest(
            id: UUID(),
            toMode: fixture.planeRequest.toMode,
            layoutAspectState: fixture.planeRequest.layoutAspectState,
            anchorTokenIndex: 0,
            transitionLayout: fixture.planeRequest.transitionLayout,
            crossfade: fixture.planeRequest.crossfade,
            latticeMap: MobilePlayerBrowserGridLatticeMap(
                columnPitchRatio: 1,
                rowPitchRatio: 1,
                fromAnchorContentPoint: CGPoint(
                    x: firstSourceFrame.midX,
                    y: firstSourceFrame.midY
                ),
                toAnchorContentPoint: CGPoint(
                    x: firstDestinationFrame.midX,
                    y: firstDestinationFrame.midY
                )
            )
        )
        var sourceItemsByDestination = [Int: [Int]]()
        for sourceItem in 0 ..< ratios.count {
            guard let sourceFrame = fixture.sourceLayout.itemFrame(
                at: sourceItem
            ), let destinationItem = fixture.destinationLayout
                .nearestItemIndex(
                    to: request.latticeMap.destinationPoint(
                        fromSource: CGPoint(
                            x: sourceFrame.midX,
                            y: sourceFrame.midY
                        )
                    ),
                    tolerance: fixture.destinationLayout.interItemSpacing + 1
                ) else {
                continue
            }
            sourceItemsByDestination[destinationItem, default: []].append(
                sourceItem
            )
        }
        let collision = try XCTUnwrap(
            sourceItemsByDestination.sorted { $0.key < $1.key }.first {
                entry in
                entry.value.count >= 2
                    && sourceItemsByDestination.keys.contains {
                        $0 != entry.key
                    }
            }
        )
        let collisionItems = collision.value.sorted()
        let winnerItem = collisionItems[0]
        let loserItem = collisionItems[1]
        let visibleItem = try XCTUnwrap(
            sourceItemsByDestination.sorted { $0.key < $1.key }.first {
                $0.key != collision.key
            }?.value.first
        )
        var cells = [Int: MobilePlayerCollectionBrowserCell]()
        for item in 0 ..< ratios.count {
            cells[item] = try XCTUnwrap(
                fixture.collectionView.cellForItem(
                    at: IndexPath(item: item, section: 0)
                ) as? MobilePlayerCollectionBrowserCell
            )
        }
        let winnerCell = try XCTUnwrap(cells[winnerItem])
        let loserCell = try XCTUnwrap(cells[loserItem])
        let visibleCell = try XCTUnwrap(cells[visibleItem])
        for cell in cells.values {
            cell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        }
        let bufferedY = fixture.viewportView.bounds.maxY + 8
        winnerCell.frame = CGRect(
            x: 0,
            y: bufferedY,
            width: winnerCell.bounds.width,
            height: winnerCell.bounds.height
        )
        loserCell.frame = CGRect(
            x: winnerCell.frame.maxX
                + fixture.sourceLayout.interItemSpacing,
            y: bufferedY,
            width: loserCell.bounds.width,
            height: loserCell.bounds.height
        )
        visibleCell.frame = CGRect(
            x: 0,
            y: 0,
            width: visibleCell.bounds.width,
            height: visibleCell.bounds.height
        )

        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let loserRepresentationID = ObjectIdentifier(loserCell)
        let initialViewportItems = session.viewportSelectedSourceItems
        XCTAssertTrue(initialViewportItems.contains(visibleItem))
        XCTAssertFalse(initialViewportItems.contains(winnerItem))
        XCTAssertFalse(initialViewportItems.contains(loserItem))
        XCTAssertEqual(session.reassignments[winnerItem], collision.key)
        XCTAssertNil(session.reassignments[loserItem])
        XCTAssertEqual(
            session.detailedSourceCellItems[loserRepresentationID],
            loserItem
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(loserRepresentationID)
        )

        winnerCell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        fixture.renderer.didConfigureCell(
            winnerCell,
            at: IndexPath(item: winnerItem, section: 0)
        )

        XCTAssertEqual(
            session.viewportSelectedSourceItems,
            initialViewportItems
        )
        XCTAssertFalse(session.selectedSourceItems.contains(winnerItem))
        XCTAssertTrue(session.selectedSourceItems.contains(loserItem))
        XCTAssertNil(session.reassignments[winnerItem])
        XCTAssertEqual(session.reassignments[loserItem], collision.key)
        XCTAssertNil(session.detailedSourceCellItems[loserRepresentationID])
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.preparedRepresentationIDs.contains(loserRepresentationID)
        )
        XCTAssertEqual(
            session.detailedSourceCellItems[loserRepresentationID],
            loserItem
        )
        XCTAssertTrue(primaryTransitionImage(in: loserCell) === image)
    }

    func testFrameCorrectionUsesViewportCoordinates() throws {
        let originCorrection = try frameCorrection(viewportOrigin: .zero)
        let translatedCorrection = try frameCorrection(
            viewportOrigin: CGPoint(x: 37, y: 83)
        )

        XCTAssertEqual(
            translatedCorrection.centerDelta.x,
            originCorrection.centerDelta.x,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            translatedCorrection.centerDelta.y,
            originCorrection.centerDelta.y,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            translatedCorrection.sizeDelta.width,
            originCorrection.sizeDelta.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            translatedCorrection.sizeDelta.height,
            originCorrection.sizeDelta.height,
            accuracy: 0.000_001
        )
    }

    func testPhantomAndSourceSeamsMatchAtEveryScale() throws {
        let fixture = try makeFixture(
            itemCount: 1_000,
            sourceColumnCount: 1,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceCell: true,
            anchorItemIndex: 12
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(
                    x: fixture.viewportView.bounds.midX,
                    y: fixture.viewportView.bounds.midY
                ),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let layout = fixture.planeRequest.transitionLayout
        let terminalScale = layout.itemWidthRatio
        XCTAssertLessThan(terminalScale, 1, "1->3 shrinks the tiles")
        XCTAssertEqual(
            fixture.sourceLayout.interItemSpacing,
            fixture.destinationLayout.interItemSpacing,
            "the seam is constant across grid modes, matching Photos"
        )

        var compared = 0
        for step in 0...8 {
            let progress = CGFloat(step) / 8
            let scale = 1 + (terminalScale - 1) * progress
            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: scale,
                settleProgress: progress,
                panDeltaY: 0
            ))
            drainQueuedWork(fixture)
            guard let phantom = session.phantomCells.values.first(where: {
                $0.bounds.width > 0
            }) else {
                continue
            }
            guard let source = session.sourceOverscanCells.values
                .first(where: { $0.bounds.width > 0 }) else {
                continue
            }
            // Both lattices share the source pitch, and the plane scales both
            // by the same factor, so it cancels: equal rendered widths in
            // content space is exactly one seam width on screen.
            let sourceWidth = source.bounds.width * source.transform.a
            let phantomWidth = phantom.bounds.width * phantom.transform.a
            XCTAssertEqual(
                phantomWidth,
                sourceWidth,
                accuracy: 0.05,
                "seams differ at scale \(scale): phantom renders "
                    + "\(phantomWidth)pt wide, source \(sourceWidth)pt"
            )
            compared += 1
        }
        XCTAssertGreaterThan(compared, 4, "not enough scales compared")
        XCTAssertEqual(
            fixture.planeRequest.crossfade.driftProgress(
                forScale: terminalScale
            ),
            1,
            accuracy: 0.000_001
        )
    }

    func testNineColumnViewportKeepsPlaceholderCoverageBeyondCellBudget()
        throws {
        let fixture = try makeFixture(
            itemCount: 500,
            sourceColumnCount: 5,
            destinationColumnCount: 9,
            destinationMode: .nineColumns,
            anchorItemIndex: 0
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let plan = try XCTUnwrap(session.currentPhantomPlan)
        let visibleItems = Set(
            fixture.destinationLayout.candidateItemIndices(
                intersecting: fixture.viewportView.bounds
            ).filter {
                fixture.destinationLayout.itemFrame(at: $0)?
                    .intersects(fixture.viewportView.bounds) == true
            }
        )
        let coveredItems = Set(plan.cellCandidates.map(
            \.destinationItemIndex
        )).union(plan.shapeCandidates.map(\.destinationItemIndex))

        XCTAssertGreaterThan(
            visibleItems.count,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        XCTAssertEqual(
            plan.cellCandidates.count,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        XCTAssertTrue(visibleItems.isSubset(of: coveredItems))
        XCTAssertTrue(
            !plan.shapeCandidates.isEmpty || plan.shapeCoverage != nil
        )
        XCTAssertNotNil(session.phantomShapeView)
    }

    func testPhantomShapeUsesCurrentSeamCompensation() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
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
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)

        func assertShapeSize() throws {
            let candidate = try XCTUnwrap(
                session.currentPhantomPlan?.cellCandidates.first
            )
            let shapeView = try XCTUnwrap(session.phantomShapeView)
            let layers = try phantomShapeLayers(in: shapeView)
            let pathBounds = try XCTUnwrap(layers.candidates.path)
                .boundingBoxOfPath
            let appliedScaleX = fixture.collectionView.transform.a
            let appliedScaleY = fixture.collectionView.transform.d
            let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
                scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
                panDeltaY: 0
            )
            let spacing = fixture.destinationLayout.interItemSpacing
            let expectedWidth = max(
                candidate.sourceFrame.width
                    + spacing * (appliedScaleX / terminalPlane.scaleX - 1)
                        / appliedScaleX,
                candidate.sourceFrame.width * 0.5
            )
            let expectedHeight = max(
                candidate.sourceFrame.height
                    + spacing * (appliedScaleY / terminalPlane.scaleY - 1)
                        / appliedScaleY,
                candidate.sourceFrame.height * 0.5
            )
            XCTAssertEqual(pathBounds.width, expectedWidth, accuracy: 0.001)
            XCTAssertEqual(pathBounds.height, expectedHeight, accuracy: 0.001)
        }

        try assertShapeSize()
        let initialBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.7,
            settleProgress: 0,
            panDeltaY: 0
        ))
        try assertShapeSize()
        let scaledBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        XCTAssertGreaterThan(
            scaledBuildCount,
            initialBuildCount
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.7,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            fixture.renderer.phantomShapeStructureBuildCount,
            scaledBuildCount
        )
    }

    func testPhantomShapeMaskTracksCorrectedSourceWithoutRebuildingStructure()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 1_000,
            sourceColumnCount: 1,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 100, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        for _ in 0 ..< 100 where session.cellFrameCorrections.isEmpty {
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertFalse(session.cellFrameCorrections.isEmpty)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        let shapeCoverage = try XCTUnwrap(
            session.currentPhantomPlan?.shapeCoverage
        )

        let scale: CGFloat = 0.8
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.8,
            panDeltaY: 0
        ))
        let firstCorrectedFrames = session.cellFrameCorrections.values
            .compactMap { entry -> (
                cell: MobilePlayerCollectionBrowserCell,
                frame: CGRect
            )? in
                guard let cell = entry.cell
                    as? MobilePlayerCollectionBrowserCell else {
                    return nil
                }
                return (
                    cell,
                    cell.convert(cell.bounds, to: fixture.collectionView)
                )
            }
        XCTAssertFalse(firstCorrectedFrames.isEmpty)
        let structuralLayer: CAShapeLayer
        switch shapeCoverage {
        case .repeatedRows:
            structuralLayer = layers.repeatedRow
        case .solid:
            structuralLayer = layers.solidCoverage
        }
        XCTAssertNotNil(structuralLayer.path)
        let structureBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let changedSource = try XCTUnwrap(
            firstCorrectedFrames.compactMap { entry -> CGRect? in
                guard session.cellFrameCorrections[
                    ObjectIdentifier(entry.cell)
                ] != nil else {
                    return nil
                }
                let secondFrame = entry.cell.convert(
                    entry.cell.bounds,
                    to: fixture.collectionView
                )
                guard entry.frame != secondFrame,
                      fixture.renderer.phantomShapeMaskedFrames.contains(
                          secondFrame
                      ) else {
                    return nil
                }
                return secondFrame
            }.min { lhs, rhs in
                if lhs.minY == rhs.minY {
                    return lhs.minX < rhs.minX
                }
                return lhs.minY < rhs.minY
            }
        )
        XCTAssertEqual(
            fixture.renderer.phantomShapeStructureBuildCount,
            structureBuildCount
        )
        XCTAssertGreaterThan(
            fixture.renderer.phantomShapeMaskBuildCount,
            maskBuildCount
        )
        XCTAssertNotNil((shapeView.layer.mask as? CAShapeLayer)?.path)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                changedSource
            )
        )
    }

    func testPhantomShapeMaskUnionsCoveredSlotAndCorrectedSource() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        for _ in 0 ..< 100 {
            _ = fixture.renderer.drainMaterializationWork()
            if !session.cellFrameCorrections.isEmpty,
               !session.sourceCoverageRefreshIsDirty,
               !session.destinationPlanRefreshIsDirty,
               !session.phantomShapeRefreshIsDirty {
                break
            }
        }
        XCTAssertFalse(session.cellFrameCorrections.isEmpty)
        let terminalScale = fixture.planeRequest.transitionLayout.itemWidthRatio
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let shapeCoverage = try XCTUnwrap(
            session.currentPhantomPlan?.shapeCoverage
        )
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let representationID = ObjectIdentifier(sourceCell)
        let destinationItem = try XCTUnwrap(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let mappedFrame = fixture.planeRequest.latticeMap.sourceRect(
            fromDestination: destinationFrame
        )
        let currentFrame = sourceCell.convert(
            sourceCell.bounds,
            to: fixture.collectionView
        )
        let mappedPoint = CGPoint(x: mappedFrame.midX, y: mappedFrame.midY)
        let currentPoint = CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        XCTAssertTrue(shapeCoverage.excludedFrames.contains(mappedFrame))
        XCTAssertNotEqual(mappedFrame, currentFrame)
        XCTAssertTrue(shapeView.frame.contains(mappedPoint))
        XCTAssertTrue(shapeView.frame.contains(currentPoint))
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                mappedFrame
            )
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                currentFrame
            )
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            mappedPoint,
            in: shapeView
        ))
        XCTAssertFalse(try phantomShapeMaskContains(
            currentPoint,
            in: shapeView
        ))
    }

    func testSolidShapePaintsPendingCandidateUntilInstallation() throws {
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(true)
        let fixture = try makeFixture(
            itemCount: 10_000,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            clock: {
                defer { clockCalls.value += 1 }
                guard limitsDrainToOneJob.value else { return 0 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let plan = try XCTUnwrap(session.currentPhantomPlan)
        let shapeCoverage = try XCTUnwrap(plan.shapeCoverage)
        guard case .solid = shapeCoverage else {
            return XCTFail("Expected solid phantom shape coverage")
        }
        let candidate = try XCTUnwrap(plan.cellCandidates.first)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        let point = CGPoint(
            x: candidate.sourceFrame.midX,
            y: candidate.sourceFrame.midY
        )
        let localPoint = CGPoint(
            x: point.x - shapeView.frame.minX,
            y: point.y - shapeView.frame.minY
        )

        XCTAssertNil(shapeView.layer.mask)
        XCTAssertTrue(try XCTUnwrap(layers.solidCoverage.path).contains(
            localPoint
        ))

        for _ in 0 ..< 100 {
            let installedItems = Set(session.phantomCells.keys)
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
            let newItems = Set(session.phantomCells.keys).subtracting(
                installedItems
            )
            if let newItem = newItems.first,
               let newPhantom = session.phantomCells[newItem] {
                let newFrame = newPhantom.convert(
                    newPhantom.bounds,
                    to: fixture.collectionView
                )
                XCTAssertTrue(
                    fixture.renderer.phantomShapeMaskedFrames.contains(newFrame)
                )
                XCTAssertFalse(try phantomShapeMaskContains(
                    CGPoint(x: newFrame.midX, y: newFrame.midY),
                    in: shapeView
                ))
                XCTAssertEqual(
                    fixture.renderer.phantomShapeStructureBuildCount,
                    structureBuildCount
                )
                XCTAssertEqual(
                    fixture.renderer.phantomShapeMaskBuildCount,
                    maskBuildCount + 1
                )
            }
            if session.phantomCells[candidate.destinationItemIndex] != nil {
                break
            }
        }

        let phantom = try XCTUnwrap(
            session.phantomCells[candidate.destinationItemIndex]
        )
        limitsDrainToOneJob.value = false
        clockCalls.value = 0
        _ = fixture.renderer.drainMaterializationWork()
        let installedFrame = phantom.convert(
            phantom.bounds,
            to: fixture.collectionView
        )
        XCTAssertGreaterThanOrEqual(
            fixture.renderer.phantomShapeMaskedFrames.filter {
                $0.contains(CGPoint(
                    x: installedFrame.midX,
                    y: installedFrame.midY
                ))
            }.count,
            2
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(x: installedFrame.midX, y: installedFrame.midY),
            in: shapeView
        ))
    }

    func testLateCandidateOnlyPhantomIsMaskedWhenDrainBudgetExpires()
        throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let plan = try XCTUnwrap(session.currentPhantomPlan)
        XCTAssertNil(plan.shapeCoverage)
        let candidate = try XCTUnwrap(plan.cellCandidates.first)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        XCTAssertNil(shapeView.layer.mask)
        let structureBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount

        clockCalls.value = 0
        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertTrue(result.stoppedForTimeLimit)
        XCTAssertTrue(session.phantomShapeRefreshIsDirty)
        let phantom = try XCTUnwrap(
            session.phantomCells[candidate.destinationItemIndex]
        )
        let frame = phantom.convert(
            phantom.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(fixture.renderer.phantomShapeMaskedFrames.contains(frame))
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(x: frame.midX, y: frame.midY),
            in: shapeView
        ))
        XCTAssertEqual(
            fixture.renderer.phantomShapeStructureBuildCount,
            structureBuildCount
        )
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskBuildCount,
            maskBuildCount + 1
        )
    }

    func testBudgetedDetailMarginIsMaskedBeforeDrainReturns() throws {
        let clockCalls = Counter()
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            sourceColumnCount: 3,
            destinationColumnCount: 2,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 1_200,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let preinstalledMarginID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.first
        )
        let preinstalledRepresentation = try XCTUnwrap(
            session.cachedSourceRepresentations[preinstalledMarginID]
        )
        let preinstalledFrame = preinstalledRepresentation.cell.convert(
            preinstalledRepresentation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                preinstalledMarginID
            )
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                preinstalledFrame
            )
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(x: preinstalledFrame.midX, y: preinstalledFrame.midY),
            in: shapeView
        ))

        var preparedMarginID: ObjectIdentifier?
        for _ in 0 ..< 100 where preparedMarginID == nil {
            let trackedMarginIDs = session.marginCoverageRepresentationIDs
                .intersection(
                    session.unpreparedMarginTrackingRepresentationIDs
                )
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            let result = fixture.renderer.drainMaterializationWork()
            let newlyPreparedMarginIDs = trackedMarginIDs.intersection(
                session.preparedRepresentationIDs
            ).intersection(
                session.marginCoverageRepresentationIDs
            ).subtracting(
                session.unpreparedMarginTrackingRepresentationIDs
            )
            guard let representationID = newlyPreparedMarginIDs.first else {
                continue
            }
            preparedMarginID = representationID
            XCTAssertEqual(result.processedCount, 1)
            XCTAssertTrue(result.stoppedForTimeLimit)
            XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
            let representation = try XCTUnwrap(
                session.cachedSourceRepresentations[representationID]
            )
            let frame = representation.cell.convert(
                representation.cell.bounds,
                to: fixture.collectionView
            )
            XCTAssertTrue(
                fixture.renderer.phantomShapeMaskedFrames.contains(frame)
            )
            XCTAssertFalse(try phantomShapeMaskContains(
                CGPoint(x: frame.midX, y: frame.midY),
                in: shapeView
            ))
            XCTAssertEqual(
                fixture.renderer.phantomShapeStructureBuildCount,
                structureBuildCount
            )
            XCTAssertEqual(
                fixture.renderer.phantomShapeMaskBuildCount,
                maskBuildCount
            )
        }
        XCTAssertNotNil(preparedMarginID)
    }

    func testBudgetedReadyCorrectionIsMaskedBeforeSourceCoverageRefresh()
        throws {
        let clockCalls = Counter()
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        XCTAssertTrue(session.cellFrameCorrections.isEmpty)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            presentationProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertEqual(session.lastContentFadeAlpha, 0, accuracy: 0.000_001)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        var selectedCorrectionRepresentationID: ObjectIdentifier?

        for _ in 0 ..< 100 where selectedCorrectionRepresentationID == nil {
            let preparedRepresentationIDs = session.preparedRepresentationIDs
            let maskedFrames = fixture.renderer.phantomShapeMaskedFrames
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            let result = fixture.renderer.drainMaterializationWork()
            let newlyPreparedRepresentationIDs = session
                .preparedRepresentationIDs
                .subtracting(preparedRepresentationIDs)
            guard let representationID = newlyPreparedRepresentationIDs
                .first(where: { representationID in
                    guard !session.lockedFallbackRepresentationIDs.contains(
                        representationID
                    ),
                    session.sourceCoverage
                        .readyDestinationByRepresentation[representationID]
                        == nil,
                    let entry = session.cellFrameCorrections[
                        representationID
                    ],
                    entry.cell.superview != nil else {
                        return false
                    }
                    let frame = entry.cell.convert(
                        entry.cell.bounds,
                        to: fixture.collectionView
                    )
                    return shapeView.frame.contains(CGPoint(
                        x: frame.midX,
                        y: frame.midY
                    )) && !maskedFrames.contains(frame)
                }) else {
                continue
            }
            selectedCorrectionRepresentationID = representationID
            XCTAssertEqual(result.processedCount, 1)
            XCTAssertTrue(result.stoppedForTimeLimit)
            XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
            XCTAssertEqual(
                fixture.renderer.phantomShapeStructureBuildCount,
                structureBuildCount
            )
            XCTAssertEqual(
                fixture.renderer.phantomShapeMaskBuildCount,
                maskBuildCount + 1
            )
        }
        let correctedRepresentationID = try XCTUnwrap(
            selectedCorrectionRepresentationID
        )
        let corrected = try XCTUnwrap(
            session.cellFrameCorrections[correctedRepresentationID]
        )
        let frame = corrected.cell.convert(
            corrected.cell.bounds,
            to: fixture.collectionView
        )
        let correctedCell = try XCTUnwrap(
            corrected.cell as? MobilePlayerCollectionBrowserCell
        )
        let point = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(shapeView.frame.contains(point))
        XCTAssertTrue(fixture.renderer.phantomShapeMaskedFrames.contains(frame))
        XCTAssertFalse(try phantomShapeMaskContains(point, in: shapeView))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            presentationProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertNotNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                correctedRepresentationID
            ]
        )
        XCTAssertEqual(correctedCell.alpha, 1, accuracy: 0.000_001)
        let positiveFadeFrame = correctedCell.convert(
            correctedCell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                positiveFadeFrame
            )
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(
                x: positiveFadeFrame.midX,
                y: positiveFadeFrame.midY
            ),
            in: shapeView
        ))
    }

    func testNoPlanePhantomShapeMasksVisibleSourceCells() throws {
        let limitsDeferredDrain = Box(false)
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 2_000,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            showsSourceCell: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 100, height: 1),
            clock: {
                guard limitsDeferredDrain.value else { return 0 }
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
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
        let session = try activeSession(fixture)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        let visibleSourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells
                .compactMap { $0 as? MobilePlayerCollectionBrowserCell }
                .first
        )
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        XCTAssertNotNil((shapeView.layer.mask as? CAShapeLayer)?.path)
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let spacing = fixture.sourceLayout.interItemSpacing
        XCTAssertEqual(
            visibleSourceCell.transform.a,
            1 + spacing * (appliedScaleX - 1)
                / (visibleSourceCell.bounds.width * appliedScaleX),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            visibleSourceCell.transform.d,
            1 + spacing * (appliedScaleY - 1)
                / (visibleSourceCell.bounds.height * appliedScaleY),
            accuracy: 0.000_001
        )
        let sourceFrame = visibleSourceCell.convert(
            visibleSourceCell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(shapeView.bounds.contains(CGPoint(
            x: sourceFrame.midX - shapeView.frame.minX,
            y: sourceFrame.midY - shapeView.frame.minY
        )))
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(sourceFrame)
        )

        let indexPath = try XCTUnwrap(
            fixture.collectionView.indexPath(for: visibleSourceCell)
        )
        visibleSourceCell.transform = .identity
        fixture.renderer.willDisplayCell(
            visibleSourceCell,
            at: indexPath
        )
        XCTAssertEqual(
            visibleSourceCell.transform.a,
            1 + spacing * (appliedScaleX - 1)
                / (visibleSourceCell.bounds.width * appliedScaleX),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            visibleSourceCell.transform.d,
            1 + spacing * (appliedScaleY - 1)
                / (visibleSourceCell.bounds.height * appliedScaleY),
            accuracy: 0.000_001
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                visibleSourceCell.convert(
                    visibleSourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        let departedSlotFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: indexPath.item)
        )
        let departedSlotPoint = CGPoint(
            x: departedSlotFrame.midX,
            y: departedSlotFrame.midY
        )
        XCTAssertTrue(
            try XCTUnwrap(session.currentPhantomPlan?.shapeCoverage)
                .excludedFrames.contains(departedSlotFrame)
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            departedSlotPoint,
            in: shapeView
        ))

        for _ in 0 ..< 100
        where fixture.renderer.pendingMaterializationWorkCount > 0 {
            _ = fixture.renderer.drainMaterializationWork()
        }
        let departedFrame = visibleSourceCell.convert(
            visibleSourceCell.bounds,
            to: fixture.collectionView
        )
        fixture.collectionView.dataSource = nil
        fixture.collectionView.reloadData()
        fixture.collectionView.layoutIfNeeded()
        XCTAssertFalse(fixture.collectionView.visibleCells.contains {
            $0 === visibleSourceCell
        })

        limitsDeferredDrain.value = true
        clockCalls.value = 0
        fixture.renderer.didEndDisplayingCell(
            visibleSourceCell,
            at: indexPath
        )
        XCTAssertTrue(session.managedCellPlanRefreshIsPending)
        let viewportBounds = fixture.viewportView.bounds
        fixture.viewportView.bounds = .zero
        let stalledRefresh = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(stalledRefresh.processedCount, 0)
        XCTAssertTrue(session.managedCellPlanRefreshIsPending)

        fixture.viewportView.bounds = viewportBounds
        clockCalls.value = 0
        let refresh = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(refresh.processedCount, 1)
        XCTAssertFalse(session.managedCellPlanRefreshIsPending)
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(departedFrame)
        )
        let departedSlotLocalPoint = CGPoint(
            x: departedSlotPoint.x - shapeView.frame.minX,
            y: departedSlotPoint.y - shapeView.frame.minY
        )
        XCTAssertTrue(shapeView.bounds.contains(departedSlotLocalPoint))
        XCTAssertTrue(try phantomShapeMaskContains(
            departedSlotPoint,
            in: shapeView
        ))
    }

    func testLateNoPlaneSourceOverscanReceivesCurrentSeamCompensation()
        throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            showsSourceGrid: true,
            anchorItemIndex: 12,
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
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
        let session = try activeSession(fixture)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        for _ in 0 ..< 100 where session.sourceOverscanCells.isEmpty {
            let installedItems = Set(session.sourceOverscanCells.keys)
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
            let newItems = Set(session.sourceOverscanCells.keys).subtracting(
                installedItems
            )
            if let newItem = newItems.first,
               let newSource = session.sourceOverscanCells[newItem] {
                let newFrame = newSource.convert(
                    newSource.bounds,
                    to: fixture.collectionView
                )
                XCTAssertTrue(
                    fixture.renderer.phantomShapeMaskedFrames.contains(newFrame)
                )
                XCTAssertFalse(try phantomShapeMaskContains(
                    CGPoint(x: newFrame.midX, y: newFrame.midY),
                    in: shapeView
                ))
                XCTAssertEqual(
                    fixture.renderer.phantomShapeStructureBuildCount,
                    structureBuildCount
                )
                XCTAssertEqual(
                    fixture.renderer.phantomShapeMaskBuildCount,
                    maskBuildCount + 1
                )
            }
        }
        let sourceCell = try XCTUnwrap(
            session.sourceOverscanCells.values.first
        )
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let spacing = fixture.sourceLayout.interItemSpacing
        XCTAssertEqual(
            sourceCell.transform.a,
            1 + spacing * (appliedScaleX - 1)
                / (sourceCell.bounds.width * appliedScaleX),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            sourceCell.transform.d,
            1 + spacing * (appliedScaleY - 1)
                / (sourceCell.bounds.height * appliedScaleY),
            accuracy: 0.000_001
        )
    }

    func testPhantomPlaneShiftRetiresOldCellsAndPromotesNewCells() throws {
        let fixture = try makeFixture(
            itemCount: 1_000,
            sourceColumnCount: 1,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 500
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
        let firstPhantomKeys = phantomPromotionKeys(session: session)

        let panDeltaY = -fixture.viewportView.bounds.height / 2
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: panDeltaY
        ))
        drainQueuedWork(fixture)
        let secondPhantomKeys = phantomPromotionKeys(session: session)
        XCTAssertFalse(firstPhantomKeys.subtracting(secondPhantomKeys).isEmpty)
        XCTAssertFalse(secondPhantomKeys.subtracting(firstPhantomKeys).isEmpty)
        XCTAssertTrue(session.phantomCells.values.allSatisfy(
            \.usesForegroundImageLoading
        ))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: -fixture.viewportView.bounds.height * 10
        ))
        drainQueuedWork(fixture)
        let finalPhantomKeys = phantomPromotionKeys(session: session)
        XCTAssertFalse(
            secondPhantomKeys.subtracting(finalPhantomKeys).isEmpty
        )
        XCTAssertTrue(session.phantomCells.values.allSatisfy(
            \.usesForegroundImageLoading
        ))
        XCTAssertTrue(
            fixture.renderer.pendingPromotionRepresentationKeys.isEmpty
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testReconfiguredRepresentationClearsCorrectionAndReindexesRegistry()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.cellFrameCorrections.keys.first {
                session.cachedSourceRepresentations[$0] != nil
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let cell = representation.cell
        let previousItem = representation.itemIndex
        let replacementItem = previousItem == 0 ? 1 : 0

        cell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        cell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: replacementItem
            ),
            itemCount: 300,
            imageSources: nil,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        fixture.renderer.didConfigureCell(
            cell,
            at: IndexPath(item: replacementItem, section: 0)
        )

        XCTAssertEqual(
            session.cachedSourceRepresentations[representationID]?.itemIndex,
            replacementItem
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertFalse(session.cachedSourceRepresentations.values.contains {
            $0.itemIndex == previousItem && $0.cell === cell
        })
        fixture.renderer.didEndDisplayingCell(
            cell,
            at: IndexPath(item: replacementItem, section: 0)
        )
        XCTAssertNil(session.cachedSourceRepresentations[representationID])
    }

    func testNarrowRTLViewportUsesMirroredSourceGeometry() throws {
        let fixture = try makeFixture(
            itemCount: 30,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        fixture.collectionView.semanticContentAttribute = .forceRightToLeft
        fixture.collectionView.layoutIfNeeded()
        let viewportWidth = fixture.sourceLayout.itemWidth
        fixture.viewportView.frame.size.width = viewportWidth
        fixture.viewportView.bounds.size.width = viewportWidth
        let geometry = fixture.collectionView.visualGeometry(
            for: fixture.sourceLayout
        )
        for itemIndex in 0..<30 {
            guard let cell = fixture.collectionView.cellForItem(
                at: IndexPath(item: itemIndex, section: 0)
            ), let frame = geometry.itemFrame(at: itemIndex) else {
                continue
            }
            cell.frame = frame
        }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)

        XCTAssertEqual(
            session.viewportSelectedSourceItems,
            Set([4, 9, 14, 19, 24, 29])
        )
    }
}
