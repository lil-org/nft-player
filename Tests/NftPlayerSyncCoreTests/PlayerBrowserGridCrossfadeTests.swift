// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridCrossfadeTests: XCTestCase {

    private static let viewportSize = CGSize(width: 390, height: 844)

    private func makeCrossfade(
        itemWidthRatio: CGFloat = 1.5,
        terminalScaleX: CGFloat? = nil,
        terminalScaleY: CGFloat? = nil,
        outgoingAnchor: CGPoint = CGPoint(x: 325, y: 400),
        incomingAnchor: CGPoint = CGPoint(x: 97.5, y: 430),
        outgoingContentOffsetY: CGFloat = 1_000,
        incomingContentOffsetY: CGFloat = 1_600,
        outgoingContentHeight: CGFloat = 9_000,
        incomingContentHeight: CGFloat = 9_000,
        viewportSize: CGSize = PlayerBrowserGridCrossfadeTests.viewportSize
    ) -> PlayerBrowserGridCrossfade? {
        PlayerBrowserGridCrossfade(
            itemWidthRatio: itemWidthRatio,
            terminalScaleX: terminalScaleX ?? itemWidthRatio,
            terminalScaleY: terminalScaleY ?? itemWidthRatio,
            outgoingAnchor: outgoingAnchor,
            incomingAnchor: incomingAnchor,
            outgoingContentOffsetY: outgoingContentOffsetY,
            incomingContentOffsetY: incomingContentOffsetY,
            outgoingContentHeight: outgoingContentHeight,
            incomingContentHeight: incomingContentHeight,
            viewportSize: viewportSize
        )
    }

    private func transform(
        crossfade: PlayerBrowserGridCrossfade,
        plane: PlayerBrowserGridCrossfadePlane
    ) -> CGAffineTransform {
        crossfade.transform(
            for: plane,
            viewCenter: CGPoint(
                x: Self.viewportSize.width / 2,
                y: Self.viewportSize.height / 2
            )
        )
    }

    private func assertEqual(
        _ lhs: CGAffineTransform,
        _ rhs: CGAffineTransform,
        accuracy: CGFloat = 0.000_001
    ) {
        XCTAssertEqual(lhs.a, rhs.a, accuracy: accuracy)
        XCTAssertEqual(lhs.b, rhs.b, accuracy: accuracy)
        XCTAssertEqual(lhs.c, rhs.c, accuracy: accuracy)
        XCTAssertEqual(lhs.d, rhs.d, accuracy: accuracy)
        XCTAssertEqual(lhs.tx, rhs.tx, accuracy: accuracy)
        XCTAssertEqual(lhs.ty, rhs.ty, accuracy: accuracy)
    }

    func testRequiresScalableFiniteGeometry() {
        XCTAssertNil(makeCrossfade(itemWidthRatio: 1))
        XCTAssertNil(
            makeCrossfade(
                itemWidthRatio: .nan,
                terminalScaleX: 1.5,
                terminalScaleY: 1.5
            )
        )
        XCTAssertNil(makeCrossfade(terminalScaleX: 0))
        XCTAssertNil(makeCrossfade(terminalScaleY: .infinity))
        XCTAssertNil(
            makeCrossfade(outgoingAnchor: CGPoint(x: CGFloat.infinity, y: 0))
        )
        XCTAssertNil(makeCrossfade(outgoingContentOffsetY: .nan))
        XCTAssertNil(makeCrossfade(incomingContentHeight: .nan))
        XCTAssertNil(
            makeCrossfade(viewportSize: CGSize(width: 390, height: 0))
        )
    }

    func testOutgoingRestContentOffsetIsClampedToTheValidRange() throws {
        let crossfade = try XCTUnwrap(makeCrossfade(
            outgoingContentOffsetY: -300,
            outgoingContentHeight: 9_000
        ))
        XCTAssertEqual(crossfade.outgoingRestContentOffsetY, 0)

        let bottomCrossfade = try XCTUnwrap(makeCrossfade(
            outgoingContentOffsetY: 100_000,
            outgoingContentHeight: 9_000
        ))
        XCTAssertEqual(
            bottomCrossfade.outgoingRestContentOffsetY,
            9_000 - Self.viewportSize.height
        )

        let incomingBottomCrossfade = try XCTUnwrap(makeCrossfade(
            incomingContentOffsetY: 100_000,
            incomingContentHeight: 9_000
        ))
        XCTAssertEqual(
            incomingBottomCrossfade.incomingRestContentOffsetY,
            9_000 - Self.viewportSize.height
        )
    }

    func testDriftFollowsTheZoomScaleAndLandsOnTheDestinationAnchor() throws {
        let crossfade = try XCTUnwrap(makeCrossfade())

        let restingPlane = crossfade.outgoingPlane(scale: 1, panDeltaY: 0)
        XCTAssertEqual(restingPlane.scaleX, 1)
        XCTAssertEqual(restingPlane.scaleY, 1)
        XCTAssertEqual(restingPlane.translation, .zero)
        XCTAssertEqual(
            restingPlane.outgoingContentOffsetY,
            crossfade.outgoingRestContentOffsetY
        )

        var previousProgress: CGFloat = -1
        for scale in [CGFloat(1), 1.1, 1.25, 1.4, 1.5] {
            let progress = crossfade.driftProgress(forScale: scale)
            XCTAssertGreaterThanOrEqual(progress, previousProgress)
            previousProgress = progress
            let plane = crossfade.outgoingPlane(scale: scale, panDeltaY: 0)
            XCTAssertEqual(
                plane.translation.x,
                (crossfade.incomingAnchor.x - crossfade.outgoingAnchor.x)
                    * progress,
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                plane.translation.y,
                (crossfade.incomingAnchor.y - crossfade.outgoingAnchor.y)
                    * progress,
                accuracy: 0.000_001
            )
        }
        XCTAssertEqual(crossfade.driftProgress(forScale: 1), 0)
        XCTAssertEqual(crossfade.driftProgress(forScale: 1.5), 1)
        XCTAssertEqual(
            crossfade.driftProgress(forScale: 2.4),
            1,
            "overshoot beyond the destination clamps the drift"
        )

        let terminalPlane = crossfade.outgoingPlane(scale: 1.5, panDeltaY: 0)
        XCTAssertEqual(
            terminalPlane.translation.x,
            crossfade.incomingAnchor.x - crossfade.outgoingAnchor.x,
            accuracy: 0.000_001
        )
    }

    /// The anchor-driven horizontal slide must never walk a content edge in off
    /// a screen edge, and must still deliver the plane to its landing. The slide
    /// term is zero only for a pinch at the exact horizontal centre, so
    /// off-centre anchors are the case that matters.
    func testPlaneCoversTheViewportAndLandsForOffCentreAnchors() throws {
        let width = Self.viewportSize.width
        let ratios: [CGFloat] = [3.0, 1.6667, 1.5, 0.6, 0.3333, 0.2]
        for ratio in ratios {
            for anchorX in [CGFloat(0), 12, 60, 195, 330, 378, 390] {
                for incomingAnchorX in [CGFloat(0), 40, 195, 350, 390] {
                    let crossfade = try XCTUnwrap(
                        makeCrossfade(
                            itemWidthRatio: ratio,
                            outgoingAnchor: CGPoint(x: anchorX, y: 400),
                            incomingAnchor: CGPoint(x: incomingAnchorX, y: 430)
                        ),
                        "r\(ratio) a\(anchorX) i\(incomingAnchorX)"
                    )
                    for step in 0...10 {
                        let progress = CGFloat(step) / 10
                        let scale = pow(ratio, progress)
                        let plane = crossfade.outgoingPlane(
                            scale: scale,
                            panDeltaY: 0
                        )
                        let k = plane.scaleX / crossfade.terminalScaleX
                        let left = min(
                            anchorX * (1 - plane.scaleX),
                            anchorX - k * incomingAnchorX
                        ) + plane.translation.x
                        let right = max(
                            anchorX + plane.scaleX * (width - anchorX),
                            anchorX + k * (width - incomingAnchorX)
                        ) + plane.translation.x
                        XCTAssertLessThanOrEqual(
                            left,
                            0.001,
                            "left uncovered r\(ratio) a\(anchorX) i\(incomingAnchorX) p\(progress)"
                        )
                        XCTAssertGreaterThanOrEqual(
                            right,
                            width - 0.001,
                            "right uncovered r\(ratio) a\(anchorX) i\(incomingAnchorX) p\(progress)"
                        )
                    }
                    // The landing must be exact: at the terminal the bound has
                    // to admit the full anchor drift, or the grid commits offset.
                    let terminal = crossfade.outgoingPlane(
                        scale: ratio,
                        panDeltaY: 0
                    )
                    XCTAssertEqual(
                        terminal.translation.x,
                        incomingAnchorX - anchorX,
                        accuracy: 0.001,
                        "landing deficit r\(ratio) a\(anchorX) i\(incomingAnchorX)"
                    )
                }
            }
        }
    }

    func testReanchoringPreservesBothEndpointTransforms() throws {
        // Production pins both lattices at the fingers: the anchors always
        // share x (the Photos law), and the reanchoring invariance holds on
        // that shape.
        let crossfade = try XCTUnwrap(makeCrossfade(
            itemWidthRatio: 1.5,
            terminalScaleX: 1.42,
            terminalScaleY: 1.47,
            incomingAnchor: CGPoint(x: 325, y: 430)
        ))
        let reanchored = try XCTUnwrap(crossfade.reanchored(
            outgoingAnchor: CGPoint(x: 80, y: 650)
        ))

        for scale in [CGFloat(1), 1.5] {
            assertEqual(
                transform(
                    crossfade: crossfade,
                    plane: crossfade.outgoingPlane(
                        scale: scale,
                        panDeltaY: 0
                    )
                ),
                transform(
                    crossfade: reanchored,
                    plane: reanchored.outgoingPlane(
                        scale: scale,
                        panDeltaY: 0
                    )
                )
            )
        }
        XCTAssertNil(crossfade.reanchored(
            outgoingAnchor: CGPoint(x: CGFloat.infinity, y: 0)
        ))
    }

    func testReanchorRebasePreservesTheAdoptionFrame() throws {
        let crossfade = try XCTUnwrap(makeCrossfade())
        let reanchored = try XCTUnwrap(crossfade.reanchored(
            outgoingAnchor: CGPoint(x: 120, y: 710)
        ))
        let scale: CGFloat = 1.28
        let progress = reanchored.driftProgress(forScale: scale)
        let currentTransform = transform(
            crossfade: crossfade,
            plane: crossfade.outgoingPlane(scale: scale, panDeltaY: 90)
        )
        let reanchoredTransform = transform(
            crossfade: reanchored,
            plane: reanchored.outgoingPlane(scale: scale, panDeltaY: 90)
        )
        let rebase = try XCTUnwrap(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: currentTransform,
            baseTransform: reanchoredTransform,
            installationProgress: progress
        ))

        assertEqual(
            rebase.applying(to: reanchoredTransform, progress: progress),
            currentTransform
        )
    }

    func testSettleEasesEachAxisOntoItsPitchRatio() throws {
        let crossfade = try XCTUnwrap(makeCrossfade(
            itemWidthRatio: 4.0301,
            terminalScaleX: 3.99,
            terminalScaleY: 4.013
        ))

        let terminalPlane = crossfade.outgoingPlane(
            scale: 4.0301,
            panDeltaY: 0
        )
        XCTAssertEqual(terminalPlane.scaleX, 3.99, accuracy: 0.000_001)
        XCTAssertEqual(terminalPlane.scaleY, 4.013, accuracy: 0.000_001)

        var previousDistanceX: CGFloat = .infinity
        var previousDistanceY: CGFloat = .infinity
        for scale in [CGFloat(1), 1.5, 2.2, 3, 3.6, 4.0301] {
            let plane = crossfade.outgoingPlane(scale: scale, panDeltaY: 0)
            let distanceX = abs(plane.scaleX - 3.99)
            let distanceY = abs(plane.scaleY - 4.013)
            XCTAssertLessThanOrEqual(
                distanceX,
                previousDistanceX + 0.000_001,
                "the x scale eases monotonically toward its pitch ratio"
            )
            XCTAssertLessThanOrEqual(
                distanceY,
                previousDistanceY + 0.000_001,
                "the y scale eases monotonically toward its pitch ratio"
            )
            previousDistanceX = distanceX
            previousDistanceY = distanceY
        }
    }

    func testPanIsClampedInContentSpaceAndScaledToTheScreen() throws {
        let crossfade = try XCTUnwrap(makeCrossfade())
        for scale in [CGFloat(0.8), 1, 1.5] {
            for panDeltaY in [CGFloat(-120), -30, 45, 200] {
                let plane = crossfade.outgoingPlane(
                    scale: scale,
                    panDeltaY: panDeltaY
                )
                let screenShift = plane.scaleY * (
                    crossfade.outgoingRestContentOffsetY
                        - plane.outgoingContentOffsetY
                )
                XCTAssertEqual(
                    screenShift,
                    panDeltaY,
                    accuracy: 0.000_001,
                    "scale \(scale) pan \(panDeltaY)"
                )
            }
        }

        let topCrossfade = try XCTUnwrap(makeCrossfade(outgoingContentOffsetY: 0))
        let clamped = topCrossfade.outgoingPlane(
            scale: 1.2,
            panDeltaY: 500
        )
        XCTAssertEqual(clamped.outgoingContentOffsetY, 0)

        let sanitized = crossfade.outgoingPlane(
            scale: 1.2,
            panDeltaY: .nan
        )
        XCTAssertEqual(
            sanitized.outgoingContentOffsetY,
            crossfade.outgoingRestContentOffsetY
        )
    }

    func testDestinationBoundaryConvergesWithoutChangingCancellationGeometry() throws {
        let crossfade = try XCTUnwrap(makeCrossfade(
            incomingContentOffsetY: 0
        ))
        let requestedPanDeltaY: CGFloat = 240
        let cancellationPlane = crossfade.outgoingPlane(
            scale: 1,
            panDeltaY: requestedPanDeltaY
        )
        XCTAssertEqual(
            (crossfade.outgoingRestContentOffsetY
                - cancellationPlane.outgoingContentOffsetY)
                * cancellationPlane.scaleY,
            requestedPanDeltaY,
            accuracy: 0.000_001
        )
        XCTAssertEqual(cancellationPlane.translation, .zero)

        let midpointPlane = crossfade.outgoingPlane(
            scale: 1.25,
            panDeltaY: requestedPanDeltaY
        )
        let midpointRenderedPanDeltaY = (
            crossfade.outgoingRestContentOffsetY
                - midpointPlane.outgoingContentOffsetY
        ) * midpointPlane.scaleY
        XCTAssertGreaterThan(midpointRenderedPanDeltaY, 0)
        XCTAssertLessThan(
            midpointRenderedPanDeltaY,
            requestedPanDeltaY
        )
        XCTAssertEqual(
            midpointPlane.translation.y,
            (crossfade.incomingAnchor.y - crossfade.outgoingAnchor.y)
                * crossfade.driftProgress(forScale: 1.25),
            accuracy: 0.000_001
        )

        let terminalPlane = crossfade.outgoingPlane(
            scale: 1.5,
            panDeltaY: requestedPanDeltaY
        )
        XCTAssertEqual(terminalPlane.incomingContentOffsetY, 0)
        XCTAssertEqual(
            (crossfade.outgoingRestContentOffsetY
                - terminalPlane.outgoingContentOffsetY)
                * terminalPlane.scaleY,
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            terminalPlane.translation.y,
            crossfade.incomingAnchor.y - crossfade.outgoingAnchor.y,
            accuracy: 0.000_001
        )
    }

    func testSourceBoundaryReleasesPanAsDestinationGainsRoom() throws {
        let crossfade = try XCTUnwrap(makeCrossfade(
            outgoingContentOffsetY: 0,
            incomingContentOffsetY: 1_600
        ))
        let requestedPanDeltaY: CGFloat = 240
        let cancellationPlane = crossfade.outgoingPlane(
            scale: 1,
            panDeltaY: requestedPanDeltaY
        )
        XCTAssertEqual(cancellationPlane.outgoingContentOffsetY, 0)
        XCTAssertEqual(cancellationPlane.translation, .zero)

        let midpointScale: CGFloat = 1.25
        let midpointPlane = crossfade.outgoingPlane(
            scale: midpointScale,
            panDeltaY: requestedPanDeltaY
        )
        XCTAssertEqual(midpointPlane.outgoingContentOffsetY, 0)
        let midpointAnchorDriftY = (
            crossfade.incomingAnchor.y - crossfade.outgoingAnchor.y
        ) * crossfade.driftProgress(forScale: midpointScale)
        let midpointRenderedMotionY = midpointPlane.translation.y
            + (crossfade.outgoingRestContentOffsetY
                - midpointPlane.outgoingContentOffsetY) * midpointPlane.scaleY
        XCTAssertGreaterThan(
            midpointRenderedMotionY,
            midpointAnchorDriftY
        )
        XCTAssertLessThan(
            midpointRenderedMotionY,
            midpointAnchorDriftY + requestedPanDeltaY
        )

        let terminalPlane = crossfade.outgoingPlane(
            scale: 1.5,
            panDeltaY: requestedPanDeltaY
        )
        XCTAssertEqual(
            terminalPlane.incomingContentOffsetY,
            crossfade.incomingRestContentOffsetY - requestedPanDeltaY,
            accuracy: 0.000_001
        )
        let terminalRenderedMotionY = terminalPlane.translation.y
            + (crossfade.outgoingRestContentOffsetY
                - terminalPlane.outgoingContentOffsetY) * terminalPlane.scaleY
        XCTAssertEqual(
            terminalRenderedMotionY,
            crossfade.incomingAnchor.y - crossfade.outgoingAnchor.y
                + requestedPanDeltaY,
            accuracy: 0.000_001
        )
    }

    func testTerminalPlaneClampsTheIncomingCommitOffset() throws {
        let crossfade = try XCTUnwrap(makeCrossfade(
            incomingContentOffsetY: 8_000,
            incomingContentHeight: 9_000
        ))
        let terminalPlane = crossfade.outgoingPlane(
            scale: 1.5,
            panDeltaY: -500
        )
        XCTAssertEqual(
            terminalPlane.incomingContentOffsetY,
            9_000 - Self.viewportSize.height,
            accuracy: 0.000_001
        )
    }

    func testShortDestinationClampsEveryTerminalPanToZero() throws {
        let crossfade = try XCTUnwrap(makeCrossfade(
            incomingContentOffsetY: 500,
            incomingContentHeight: 300
        ))
        XCTAssertEqual(crossfade.incomingRestContentOffsetY, 0)
        for panDeltaY in [CGFloat(-2_000), 0, 2_000, .nan] {
            let terminalPlane = crossfade.outgoingPlane(
                scale: 1.5,
                panDeltaY: panDeltaY
            )
            XCTAssertEqual(terminalPlane.incomingContentOffsetY, 0)
        }
    }

    func testIncomingContentFadeIsFrontLoadedAndMonotone() {
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(settleProgress: 0),
            0
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress:
                    PlayerBrowserGridCrossfade.contentFadeStartSettleProgress
            ),
            0
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress:
                    PlayerBrowserGridCrossfade.contentFadeEndSettleProgress
            ),
            1
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(settleProgress: 1),
            1
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: .nan
            ),
            0
        )

        var previousAlpha: CGFloat = -1
        for step in 0...20 {
            let alpha = PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: CGFloat(step) / 20
            )
            XCTAssertGreaterThanOrEqual(alpha, previousAlpha)
            XCTAssertGreaterThanOrEqual(alpha, 0)
            XCTAssertLessThanOrEqual(alpha, 1)
            previousAlpha = alpha
        }
    }

    func testPhantomPlanBoundsCellsWithoutLeavingCoverageHoles() throws {
        let itemCount = 1_000
        let imageSize = CGSize(width: 2, height: 1)
        let sourceLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: itemCount,
                uniformImageSize: imageSize,
                columnCount: 1
            )
        ))
        let destinationLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: itemCount,
                uniformImageSize: imageSize,
                columnCount: 5
            )
        ))
        let transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: sourceLayout,
            toLayout: destinationLayout
        ))
        let anchorIndex = 500
        let sourceAnchorFrame = try XCTUnwrap(
            sourceLayout.itemFrame(at: anchorIndex)
        )
        let destinationAnchorFrame = try XCTUnwrap(
            destinationLayout.itemFrame(at: anchorIndex)
        )
        let latticeMap = transition.latticeMap(
            fromAnchorContentPoint: CGPoint(
                x: sourceAnchorFrame.midX,
                y: sourceAnchorFrame.midY
            ),
            toAnchorContentPoint: CGPoint(
                x: destinationAnchorFrame.midX,
                y: destinationAnchorFrame.midY
            )
        )
        let priorityRect = CGRect(
            x: 0,
            y: destinationAnchorFrame.midY - Self.viewportSize.height / 2,
            width: Self.viewportSize.width,
            height: Self.viewportSize.height
        )
        let coverageRect = CGRect(
            x: -Self.viewportSize.width / 4,
            y: priorityRect.minY - Self.viewportSize.height / 2,
            width: Self.viewportSize.width * 1.5,
            height: Self.viewportSize.height * 2
        )
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: destinationLayout,
            mirrorsHorizontally: false
        )
        let expectedItems = destinationLayout.candidateItemIndices(
            intersecting: coverageRect
        ).filter { itemIndex in
            geometry.itemFrame(at: itemIndex).map {
                coverageRect.intersects($0)
            } == true
        }
        let coveredItems = Set(expectedItems.prefix(3))
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: coveredItems,
            maximumCellCount: 120
        )
        let expectedUncoveredItems = Set(expectedItems).subtracting(
            coveredItems
        )
        let cellItems = Set(
            plan.cellCandidates.map(\.destinationItemIndex)
        )
        let shapeItems = Set(
            plan.shapeCandidates.map(\.destinationItemIndex)
        )
        let visibleItems = Set(expectedUncoveredItems.filter { itemIndex in
            geometry.itemFrame(at: itemIndex).map {
                priorityRect.intersects($0)
            } == true
        })

        XCTAssertGreaterThan(expectedUncoveredItems.count, 120)
        XCTAssertEqual(plan.cellCandidates.count, 120)
        XCTAssertFalse(plan.shapeCandidates.isEmpty)
        XCTAssertTrue(cellItems.isDisjoint(with: shapeItems))
        XCTAssertEqual(
            cellItems.union(shapeItems),
            expectedUncoveredItems
        )
        XCTAssertLessThanOrEqual(visibleItems.count, 120)
        XCTAssertTrue(visibleItems.isSubset(of: cellItems))

        let expectedMarginItems = expectedUncoveredItems.compactMap {
            itemIndex -> (itemIndex: Int, frame: CGRect)? in
            guard let frame = geometry.itemFrame(at: itemIndex),
                  !priorityRect.intersects(frame) else {
                return nil
            }
            return (itemIndex, frame)
        }.sorted { lhs, rhs in
            let lhsDistance = abs(
                lhs.frame.midY - priorityRect.midY
            )
            let rhsDistance = abs(
                rhs.frame.midY - priorityRect.midY
            )
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs.itemIndex < rhs.itemIndex
        }.map(\.itemIndex)
        let selectedMarginItems = plan.cellCandidates.filter {
            !priorityRect.intersects($0.destinationFrame)
        }.map(\.destinationItemIndex)
        XCTAssertEqual(
            selectedMarginItems,
            Array(expectedMarginItems.prefix(selectedMarginItems.count))
        )
    }

    func testPhantomPlanUsesMirroredDestinationFrames() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 300, height: 600),
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 3,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: 3
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: true
        )
        let coverageRect = CGRect(x: 10, y: 10, width: 50, height: 50)
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: coverageRect,
            priorityRect: coverageRect,
            coveredDestinationItems: [],
            maximumCellCount: 10
        )

        XCTAssertEqual(
            plan.cellCandidates.map(\.destinationItemIndex),
            [2]
        )
        XCTAssertEqual(
            plan.cellCandidates.first?.sourceFrame,
            geometry.itemFrame(at: 2)
        )
        XCTAssertTrue(plan.shapeCandidates.isEmpty)
    }

    func testDetailPlanCapsItemsAroundTheAnchor() {
        let plan = PlayerBrowserGridDetailPlan(
            candidateItemIndices: Array(0..<4_000),
            anchorItemIndex: 500,
            maximumCount: 120
        )

        XCTAssertEqual(plan.itemIndices, Array(440..<560))
    }

    func testDetailPlanSanitizesCandidatesAndHandlesBoundaryIndices() {
        XCTAssertEqual(
            PlayerBrowserGridDetailPlan(
                candidateItemIndices: [5, 1, 5, -1, 3],
                anchorItemIndex: 3,
                maximumCount: 10
            ).itemIndices,
            [1, 3, 5]
        )
        XCTAssertEqual(
            PlayerBrowserGridCarryoverSelection.prioritizedItemIndices(
                candidateItemIndices: [5, 1, 5, -1, 3],
                anchorItemIndex: 3
            ),
            [3, 1, 5]
        )
        XCTAssertTrue(PlayerBrowserGridDetailPlan(
            candidateItemIndices: [1, 2, 3],
            anchorItemIndex: 2,
            maximumCount: 0
        ).itemIndices.isEmpty)
        XCTAssertEqual(
            PlayerBrowserGridDetailPlan(
                candidateItemIndices: [0, Int.max - 1, Int.max],
                anchorItemIndex: Int.max,
                maximumCount: 2
            ).itemIndices,
            [Int.max - 1, Int.max]
        )
    }

    func testCarryoverPolicyUsesTheSharedVisualBudget() {
        XCTAssertEqual(
            PlayerBrowserGridRenderBudget.maximumCarryoverSourceCount,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount * 2
        )
        XCTAssertEqual(
            PlayerBrowserGridCarryoverSelection.selectedItemIndices(
                candidateItemIndices: Array(0..<4_000),
                anchorItemIndex: 500
            ),
            Set(440..<560)
        )
        let prioritizedItems = PlayerBrowserGridCarryoverSelection
            .prioritizedItemIndices(
                candidateItemIndices: Array(0..<4_000),
                anchorItemIndex: 500
            )
        XCTAssertEqual(Set(prioritizedItems), Set(440..<560))
        XCTAssertEqual(
            Array(prioritizedItems.prefix(5)),
            [500, 499, 501, 498, 502]
        )
    }

    func testCarryoverSourcePolicyPreservesBoundsAndNilContent() throws {
        let destination = CGRect(x: 0, y: 0, width: 100, height: 100)
        let insufficient = PlayerBrowserGridCarryoverSource<Int>(
            viewportRect: CGRect(x: 0, y: 0, width: 40, height: 100),
            content: 1
        )
        let eligibleWithoutContent = PlayerBrowserGridCarryoverSource<Int>(
            viewportRect: CGRect(x: 0, y: 0, width: 90, height: 100),
            content: nil
        )

        let selected = try XCTUnwrap(
            PlayerBrowserGridCarryoverSelection.bestSource(
                for: destination,
                among: [insufficient, eligibleWithoutContent]
            )
        )

        XCTAssertEqual(selected.viewportRect, eligibleWithoutContent.viewportRect)
        XCTAssertNil(selected.content)
    }

    func testCarryoverSourcePolicyCapsSourceSearch() {
        let destination = CGRect(x: 0, y: 0, width: 100, height: 100)
        let insufficient = PlayerBrowserGridCarryoverSource<Int>(
            viewportRect: CGRect(x: 0, y: 0, width: 40, height: 100),
            content: nil
        )
        let eligible = PlayerBrowserGridCarryoverSource<Int>(
            viewportRect: destination,
            content: 1
        )
        let limit = PlayerBrowserGridRenderBudget.maximumCarryoverSourceCount

        XCTAssertNotNil(PlayerBrowserGridCarryoverSelection.bestSource(
            for: destination,
            among: Array(repeating: insufficient, count: limit - 1)
                + [eligible]
        ))
        XCTAssertNil(PlayerBrowserGridCarryoverSelection.bestSource(
            for: destination,
            among: Array(repeating: insufficient, count: limit)
                + [eligible]
        ))
    }

    func testCarryoverDestinationUsesVisibleClippedArea() throws {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)
        let destination = CGRect(x: -80, y: 0, width: 100, height: 100)
        let visibleDestination = try XCTUnwrap(
            PlayerBrowserGridGeometry.visibleRect(
                destination,
                clippedTo: viewport
            )
        )
        let source = PlayerBrowserGridCarryoverSource<Int>(
            viewportRect: CGRect(x: 0, y: 0, width: 11, height: 100),
            content: 1
        )

        XCTAssertEqual(
            visibleDestination,
            CGRect(x: 0, y: 0, width: 20, height: 100)
        )
        XCTAssertNotNil(PlayerBrowserGridCarryoverSelection.bestSource(
            for: visibleDestination,
            among: [source]
        ))
        XCTAssertNil(
            PlayerBrowserGridGeometry.visibleRect(
                destination,
                clippedTo: CGRect(x: 200, y: 0, width: 100, height: 100)
            )
        )
    }

    func testVisibleGridRectRejectsInvalidGeometry() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
            clippedTo: viewport
        ))
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            CGRect(x: 0, y: 0, width: 10, height: 10),
            clippedTo: CGRect(
                x: 0,
                y: 0,
                width: CGFloat.infinity,
                height: 100
            )
        ))
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            .zero,
            clippedTo: viewport
        ))
    }

    func testCarryoverSelectionUsesGreatestOverlapAndPreservesTies() {
        let destination = CGRect(x: 0, y: 0, width: 100, height: 100)
        let first = CGRect(x: 0, y: 0, width: 80, height: 100)
        let tied = CGRect(x: 20, y: 0, width: 80, height: 100)
        let greatest = CGRect(x: 5, y: 0, width: 90, height: 100)

        XCTAssertEqual(
            PlayerBrowserGridCarryoverSelection.bestSource(
                for: destination,
                among: [first, tied],
                maximumCount: 2,
                sourceRect: { $0 }
            ),
            first
        )
        XCTAssertEqual(
            PlayerBrowserGridCarryoverSelection.bestSource(
                for: destination,
                among: [first, tied, greatest],
                maximumCount: 3,
                sourceRect: { $0 }
            ),
            greatest
        )
    }

    func testCarryoverSelectionRequiresMoreThanHalfCoverage() {
        let destination = CGRect(x: 0, y: 0, width: 100, height: 100)
        let half = CGRect(x: 0, y: 0, width: 50, height: 100)
        let majority = CGRect(x: 0, y: 0, width: 51, height: 100)

        XCTAssertNil(PlayerBrowserGridCarryoverSelection.bestSource(
            for: destination,
            among: [half],
            maximumCount: 1,
            sourceRect: { $0 }
        ))
        XCTAssertEqual(
            PlayerBrowserGridCarryoverSelection.bestSource(
                for: destination,
                among: [majority],
                maximumCount: 1,
                sourceRect: { $0 }
            ),
            majority
        )
    }

    func testCarryoverSelectionRespectsBounds() {
        let destination = CGRect(x: 0, y: 0, width: 100, height: 100)
        let insufficient = CGRect(x: 0, y: 0, width: 40, height: 100)
        let eligible = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertNil(PlayerBrowserGridCarryoverSelection.bestSource(
            for: destination,
            among: [insufficient, eligible],
            maximumCount: 1,
            sourceRect: { $0 }
        ))
        XCTAssertNil(PlayerBrowserGridCarryoverSelection.bestSource(
            for: .zero,
            among: [eligible],
            maximumCount: 1,
            sourceRect: { $0 }
        ))
    }

    func testPhantomPlanUsesSolidCoverageWhenTheBufferExceedsTheRenderingBudget() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 20_000,
                uniformImageSize: CGSize(width: 1_000, height: 1),
                columnCount: 5
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: false
        )
        let coverageRect = CGRect(
            x: 0,
            y: Self.viewportSize.height * 2,
            width: Self.viewportSize.width,
            height: Self.viewportSize.height * 3
        )
        let priorityRect = CGRect(
            x: 0,
            y: coverageRect.midY - Self.viewportSize.height / 2,
            width: Self.viewportSize.width,
            height: Self.viewportSize.height
        )
        let latticeMap = MobilePlayerBrowserGridLatticeMap.identity
        let expectedItems = Set(layout.candidateItemIndices(
            intersecting: coverageRect
        ).filter { itemIndex in
            geometry.itemFrame(at: itemIndex).map {
                coverageRect.intersects($0)
            } == true
        })
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: [],
            maximumCellCount: 120
        )
        let cellItems = Set(
            plan.cellCandidates.map(\.destinationItemIndex)
        )
        let expectedCenterItems = Set(expectedItems.sorted { lhs, rhs in
            let lhsDistance = abs(
                geometry.itemFrame(at: lhs)!.midY - priorityRect.midY
            )
            let rhsDistance = abs(
                geometry.itemFrame(at: rhs)!.midY - priorityRect.midY
            )
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs < rhs
        }.prefix(120))
        let expectedRowCount = Set(
            expectedItems.map { $0 / layout.columnCount }
        ).count
        let solidCoverage = try XCTUnwrap(plan.shapeCoverage?.solidCoverage)

        XCTAssertGreaterThan(expectedItems.count, 120)
        XCTAssertGreaterThan(
            expectedRowCount,
            PlayerBrowserGridPhantomPlan.repeatedRowInstanceLimit
        )
        XCTAssertEqual(cellItems.count, 120)
        XCTAssertEqual(cellItems, expectedCenterItems)
        XCTAssertTrue(plan.shapeCandidates.isEmpty)
        XCTAssertEqual(
            solidCoverage.frame,
            coverageRect
        )
        XCTAssertEqual(
            solidCoverage.excludedFrames,
            plan.cellCandidates.map(\.sourceFrame)
        )

        let shapeOnlyPlan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: [],
            maximumCellCount: 0
        )
        XCTAssertTrue(shapeOnlyPlan.cellCandidates.isEmpty)
        XCTAssertTrue(shapeOnlyPlan.shapeCandidates.isEmpty)
        XCTAssertNotNil(shapeOnlyPlan.shapeCoverage?.solidCoverage)

        let repeatedCoveredItems = Set(expectedItems.sorted().prefix(3))
        let partiallyCoveredPlan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: repeatedCoveredItems,
            maximumCellCount: 0
        )
        XCTAssertEqual(
            partiallyCoveredPlan.shapeCoverage?.excludedFrames,
            repeatedCoveredItems.sorted().compactMap {
                geometry.itemFrame(at: $0)
            }
        )

        let manyCoveredItems = Set(expectedItems.sorted().prefix(600))
        let boundedExclusionPlan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: manyCoveredItems,
            maximumCellCount: 0
        )
        XCTAssertEqual(
            boundedExclusionPlan.shapeCoverage?.excludedFrames,
            manyCoveredItems.sorted().prefix(
                PlayerBrowserGridPhantomPlan.renderingComplexityLimit
            ).compactMap {
                geometry.itemFrame(at: $0)
            }
        )

        let coveredPlan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: expectedItems,
            maximumCellCount: 120
        )
        XCTAssertTrue(coveredPlan.cellCandidates.isEmpty)
        XCTAssertTrue(coveredPlan.shapeCandidates.isEmpty)
        XCTAssertNil(coveredPlan.shapeCoverage)
    }

    func testVariableHeightPhantomPlanUsesBoundedSolidFallback() throws {
        let itemCount = 20_000
        let columnCount = 5
        let ratios = (0..<itemCount).map { itemIndex in
            (itemIndex / columnCount).isMultiple(of: 2)
                ? CGFloat(0.001)
                : CGFloat(0.002)
        }
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: ratios,
                columnCount: columnCount
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: false
        )
        let priorityRect = CGRect(
            x: 0,
            y: layout.contentSize.height / 2 - Self.viewportSize.height / 2,
            width: Self.viewportSize.width,
            height: Self.viewportSize.height
        )
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: CGRect(origin: .zero, size: layout.contentSize),
            priorityRect: priorityRect,
            coveredDestinationItems: [],
            maximumCellCount: 120
        )

        XCTAssertFalse(layout.usesUniformRowHeights)
        let solidCoverage = try XCTUnwrap(plan.shapeCoverage?.solidCoverage)

        XCTAssertEqual(plan.cellCandidates.count, 120)
        XCTAssertTrue(plan.shapeCandidates.isEmpty)
        XCTAssertEqual(
            solidCoverage.frame,
            CGRect(origin: .zero, size: layout.contentSize)
        )
        XCTAssertEqual(
            solidCoverage.excludedFrames,
            plan.cellCandidates.map(\.sourceFrame)
        )

        let priorityIndices = layout.candidateItemIndices(
            intersecting: priorityRect
        )
        let anchorIndex = priorityIndices.lowerBound
            + priorityIndices.count / 2
        let coveredItems = Set(
            max(anchorIndex - 1_000, 0)..<min(anchorIndex + 1_000, itemCount)
        )
        let coveredPlan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: CGRect(origin: .zero, size: layout.contentSize),
            priorityRect: priorityRect,
            coveredDestinationItems: coveredItems,
            maximumCellCount: 120
        )

        XCTAssertTrue(coveredPlan.cellCandidates.isEmpty)
        XCTAssertTrue(coveredPlan.shapeCandidates.isEmpty)
        let coveredSolidCoverage = try XCTUnwrap(
            coveredPlan.shapeCoverage?.solidCoverage
        )
        XCTAssertEqual(
            coveredSolidCoverage.excludedFrames.count,
            PlayerBrowserGridPhantomPlan.renderingComplexityLimit
        )
    }

    func testVariableHeightPhantomPlanKeepsBoundedTileShapes() throws {
        let itemCount = 400
        let columnCount = 5
        let ratios = (0..<itemCount).map { itemIndex in
            (itemIndex / columnCount).isMultiple(of: 2)
                ? CGFloat(0.9)
                : CGFloat(1.1)
        }
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: ratios,
                columnCount: columnCount
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: false
        )
        let coverageRect = CGRect(origin: .zero, size: layout.contentSize)
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: coverageRect,
            priorityRect: coverageRect,
            coveredDestinationItems: [],
            maximumCellCount: 0
        )

        XCTAssertFalse(layout.usesUniformRowHeights)
        XCTAssertGreaterThan(itemCount, 300)
        XCTAssertLessThanOrEqual(
            itemCount,
            PlayerBrowserGridPhantomPlan.renderingComplexityLimit
        )
        XCTAssertTrue(plan.cellCandidates.isEmpty)
        XCTAssertEqual(plan.shapeCandidates.count, itemCount)
        XCTAssertNil(plan.shapeCoverage)
    }

    func testRepeatedPhantomRowsBoundCellCandidatesToPriorityNeighborhood() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 1_500,
                uniformImageSize: CGSize(width: 1_000, height: 1),
                columnCount: 5
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: false
        )
        let priorityFrame = try XCTUnwrap(geometry.itemFrame(at: 750))
        let priorityRect = CGRect(
            x: 0,
            y: priorityFrame.minY + priorityFrame.height / 4,
            width: layout.contentSize.width,
            height: priorityFrame.height / 2
        )
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: CGRect(origin: .zero, size: layout.contentSize),
            priorityRect: priorityRect,
            coveredDestinationItems: Set(300..<1_200),
            maximumCellCount: 120
        )

        XCTAssertNotNil(plan.shapeCoverage?.repeatedRows)
        XCTAssertTrue(plan.shapeCandidates.isEmpty)
        XCTAssertTrue(plan.cellCandidates.isEmpty)
    }

    func testRepeatedPhantomRowsUsePriorityAndMarginOrdering() throws {
        let viewportSize = CGSize(width: 504, height: 844)
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 1_000,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: 5
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: false
        )
        let priorityFrame = try XCTUnwrap(geometry.itemFrame(at: 500))
        let priorityRect = CGRect(
            x: 0,
            y: priorityFrame.minY + priorityFrame.height / 4,
            width: layout.contentSize.width,
            height: priorityFrame.height / 2
        )
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: CGRect(origin: .zero, size: layout.contentSize),
            priorityRect: priorityRect,
            coveredDestinationItems: [],
            maximumCellCount: 10
        )

        XCTAssertNotNil(plan.shapeCoverage?.repeatedRows)
        XCTAssertEqual(
            plan.cellCandidates.map(\.destinationItemIndex),
            [500, 501, 502, 503, 504, 495, 496, 497, 498, 499]
        )
    }

    func testIPadBufferedCoverageRetainsRepeatedRowsAboveThreeHundred() throws {
        let viewportSize = CGSize(width: 1_024, height: 1_366)
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 10_000,
                uniformImageSize: CGSize(width: 100, height: 4),
                columnCount: 5
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: false
        )
        let priorityRect = CGRect(
            x: 0,
            y: layout.contentSize.height / 2 - viewportSize.height / 2,
            width: viewportSize.width,
            height: viewportSize.height
        )
        let coverageRect = priorityRect.insetBy(
            dx: 0,
            dy: -viewportSize.height
        )
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: coverageRect,
            priorityRect: priorityRect,
            coveredDestinationItems: [],
            maximumCellCount: 0
        )
        let repeatedRows = try XCTUnwrap(plan.shapeCoverage?.repeatedRows)

        XCTAssertGreaterThan(repeatedRows.rowCount, 300)
        XCTAssertLessThanOrEqual(
            repeatedRows.rowCount,
            PlayerBrowserGridPhantomPlan.repeatedRowInstanceLimit
        )
        XCTAssertEqual(repeatedRows.firstRowFrames.count, 5)
        XCTAssertEqual(
            repeatedRows.rowPitch - repeatedRows.firstRowFrames[0].height,
            MobilePlayerBrowserLayout.itemSpacing,
            accuracy: 0.000_001
        )
        XCTAssertNil(plan.shapeCoverage?.solidCoverage)
    }

    func testRepeatedPhantomRowsPreserveThePartialFinalRow() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 20_003,
                uniformImageSize: CGSize(width: 100, height: 3),
                columnCount: 5
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: true
        )
        let coverageRect = CGRect(
            x: 0,
            y: max(layout.contentSize.height - Self.viewportSize.height, 0),
            width: Self.viewportSize.width,
            height: Self.viewportSize.height
        )
        let latticeMap = MobilePlayerBrowserGridLatticeMap.identity
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            priorityRect: coverageRect,
            coveredDestinationItems: [],
            maximumCellCount: 0
        )
        let repeatedRows = try XCTUnwrap(plan.shapeCoverage?.repeatedRows)
        let expectedFinalFrames = (20_000..<20_003).compactMap {
            geometry.itemFrame(at: $0)
        }

        XCTAssertLessThanOrEqual(
            repeatedRows.rowCount,
            PlayerBrowserGridPhantomPlan.repeatedRowInstanceLimit
        )
        XCTAssertEqual(repeatedRows.finalRowFrames, expectedFinalFrames)
        XCTAssertTrue(plan.shapeCandidates.isEmpty)
    }

    func testRepeatedPhantomRowsUseInclusiveRenderingComplexityBoundary() throws {
        let maximumRowCount =
            PlayerBrowserGridPhantomPlan.repeatedRowInstanceLimit
        let columnCount = 3
        let repeatedLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: maximumRowCount * columnCount + 1,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: columnCount
            )
        ))
        let repeatedGeometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: repeatedLayout,
            mirrorsHorizontally: false
        )
        let repeatedPlan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: repeatedGeometry,
            latticeMap: .identity,
            coverageRect: CGRect(origin: .zero, size: repeatedLayout.contentSize),
            priorityRect: .zero,
            coveredDestinationItems: [],
            maximumCellCount: 0
        )
        let repeatedRows = try XCTUnwrap(
            repeatedPlan.shapeCoverage?.repeatedRows
        )

        XCTAssertEqual(repeatedRows.rowCount, maximumRowCount)
        XCTAssertEqual(repeatedRows.finalRowFrames.count, 1)

        let solidLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: (maximumRowCount + 1) * columnCount,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: columnCount
            )
        ))
        let solidGeometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: solidLayout,
            mirrorsHorizontally: false
        )
        let solidPlan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: solidGeometry,
            latticeMap: .identity,
            coverageRect: CGRect(origin: .zero, size: solidLayout.contentSize),
            priorityRect: .zero,
            coveredDestinationItems: [],
            maximumCellCount: 0
        )

        XCTAssertNotNil(solidPlan.shapeCoverage?.solidCoverage)
        XCTAssertNil(solidPlan.shapeCoverage?.repeatedRows)
    }

    func testPhantomPlanUsesSolidCoverageAtMaximumItemCount() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: Int.max,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: 3
            )
        ))
        let geometry = MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally: false
        )
        let coverageRect = CGRect(
            x: 0,
            y: 0,
            width: layout.contentSize.width,
            height: layout.contentSize.height.nextUp
        )
        let plan = PlayerBrowserGridPhantomPlan(
            destinationGeometry: geometry,
            latticeMap: .identity,
            coverageRect: coverageRect,
            priorityRect: .zero,
            coveredDestinationItems: [],
            maximumCellCount: 0
        )
        let solidCoverage = try XCTUnwrap(plan.shapeCoverage?.solidCoverage)

        XCTAssertEqual(
            solidCoverage.frame,
            CGRect(origin: .zero, size: layout.contentSize)
        )
        XCTAssertTrue(solidCoverage.excludedFrames.isEmpty)
    }

    func testPhantomCoverageRecentersOnlyAfterLeavingItsBuffer() {
        var coverage = PlayerBrowserGridPhantomCoverage()
        let initialRequired = CGRect(x: 0, y: 100, width: 300, height: 600)
        let initialCoverage = coverage.replacementRect(
            requiredRect: initialRequired,
            buffer: CGSize(width: 50, height: 300)
        )

        XCTAssertEqual(
            initialCoverage,
            CGRect(x: -50, y: -200, width: 400, height: 1_200)
        )
        XCTAssertNil(coverage.replacementRect(
            requiredRect: initialRequired.offsetBy(dx: 0, dy: 250),
            buffer: CGSize(width: 50, height: 300)
        ))

        let shiftedRequired = initialRequired.offsetBy(dx: 0, dy: 350)
        let shiftedCoverage = coverage.replacementRect(
            requiredRect: shiftedRequired,
            buffer: CGSize(width: 50, height: 300)
        )
        XCTAssertEqual(
            shiftedCoverage,
            CGRect(x: -50, y: 150, width: 400, height: 1_200)
        )

        let reversedRequired = initialRequired.offsetBy(dx: 0, dy: -200)
        XCTAssertEqual(
            coverage.replacementRect(
                requiredRect: reversedRequired,
                buffer: CGSize(width: 50, height: 300)
            ),
            CGRect(x: -50, y: -400, width: 400, height: 1_200)
        )
        coverage.reset()
        XCTAssertNil(coverage.installedRect)
    }

    func testPlaneRebaseRequiresAnInstallationBeforeTheEndWithADifference() {
        let base = CGAffineTransform(scaleX: 2, y: 2)
        let current = CGAffineTransform(scaleX: 2.4, y: 2.4)
        XCTAssertNil(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: current,
            baseTransform: base,
            installationProgress: 1
        ))
        XCTAssertNil(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: current,
            baseTransform: base,
            installationProgress: 1.4
        ))
        XCTAssertNil(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: base,
            baseTransform: base,
            installationProgress: 0.4
        ))
        XCTAssertNotNil(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: current,
            baseTransform: base,
            installationProgress: 0
        ))
    }

    /// A plane installed at its own terminal ratio has no drift left to ramp
    /// on, so the host drives the rebase off the settle instead. Installing at
    /// progress 0 has to hold the whole leftover and decay it to nothing.
    func testPlaneRebaseAtTheInstallationOriginDecaysWithoutRampingIn() throws {
        let base = CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: -30)
        let current = CGAffineTransform(a: 2.4, b: 0, c: 0, d: 2.2, tx: 4, ty: -18)
        let rebase = try XCTUnwrap(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: current,
            baseTransform: base,
            installationProgress: 0
        ))

        XCTAssertEqual(rebase.applying(to: base, progress: 0), current)
        XCTAssertEqual(rebase.applying(to: base, progress: 1), base)
        XCTAssertEqual(rebase.applying(to: base, progress: .nan), base)

        var previousDistance = CGFloat.infinity
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            let rebased = rebase.applying(to: base, progress: progress)
            XCTAssertEqual(
                rebased.tx,
                base.tx + (current.tx - base.tx) * (1 - progress),
                accuracy: 0.000_1
            )
            let distance = abs(rebased.tx - base.tx)
            XCTAssertLessThanOrEqual(
                distance,
                previousDistance + 0.000_1,
                "the leftover only ever decays"
            )
            previousDistance = distance
        }
    }

    func testPlaneRebaseRampsTheLeftoverDifferenceInAndBackOut() throws {
        let base = CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: -30)
        let current = CGAffineTransform(a: 2.4, b: 0, c: 0, d: 2.2, tx: 4, ty: -18)
        let installationProgress: CGFloat = 0.4
        let rebase = try XCTUnwrap(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: current,
            baseTransform: base,
            installationProgress: installationProgress
        ))

        // Both endpoints land on the untouched plane transform, so neither the
        // install frame nor the terminal frame jumps.
        XCTAssertEqual(rebase.applying(to: base, progress: 0), base)
        XCTAssertEqual(rebase.applying(to: base, progress: 1), base)
        XCTAssertEqual(rebase.applying(to: base, progress: .nan), base)
        // At the installation point the whole leftover difference is present.
        XCTAssertEqual(
            rebase.applying(to: base, progress: installationProgress),
            current
        )

        for step in 0...20 {
            let progress = CGFloat(step) / 20
            let rebased = rebase.applying(to: base, progress: progress)
            let expectedWeight = progress <= installationProgress
                ? progress / installationProgress
                : (1 - progress) / (1 - installationProgress)
            XCTAssertEqual(
                rebased.tx,
                base.tx + (current.tx - base.tx) * expectedWeight,
                accuracy: 0.000_1
            )
            XCTAssertEqual(
                rebased.a,
                base.a + (current.a - base.a) * expectedWeight,
                accuracy: 0.000_1
            )
        }
    }

    func testPlaneRebaseClampsOutOfRangeProgressToTheEndpoints() throws {
        let base = CGAffineTransform(scaleX: 2, y: 2)
        let rebase = try XCTUnwrap(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: CGAffineTransform(scaleX: 2.4, y: 2.4),
            baseTransform: base,
            installationProgress: 0.5
        ))
        XCTAssertEqual(rebase.applying(to: base, progress: -3), base)
        XCTAssertEqual(rebase.applying(to: base, progress: 4), base)
    }

    func testEndpointRebaseClockDecaysDuringCancellationWithoutRewinding() throws {
        let crossfade = try XCTUnwrap(makeCrossfade(itemWidthRatio: 1.0 / 3))
        let base = CGAffineTransform(scaleX: 1.8, y: 1.8)
        let current = CGAffineTransform(
            a: 1.8,
            b: 0,
            c: 0,
            d: 1.8,
            tx: 90,
            ty: -45
        )
        let rebase = try XCTUnwrap(PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: current,
            baseTransform: base,
            installationProgress: 0
        ))

        var progress: CGFloat = 0
        var previousDistance = CGFloat.infinity
        var sawPartialDecay = false
        for scale in [CGFloat(0.29), 0.5, 0.7, 0.6, 0.8, 1] {
            progress = PlayerBrowserGridCrossfadePlaneRebase
                .endpointClockProgress(
                    previousProgress: progress,
                    driftProgress: crossfade.driftProgress(forScale: scale),
                    settleProgress: 0
                )
            if progress > 0, progress < 1 {
                sawPartialDecay = true
            }
            let transform = rebase.applying(to: base, progress: progress)
            let distance = abs(transform.tx - base.tx)
            XCTAssertLessThanOrEqual(distance, previousDistance + 0.000_1)
            previousDistance = distance
        }

        XCTAssertTrue(sawPartialDecay)
        XCTAssertEqual(progress, 1)
        XCTAssertEqual(rebase.applying(to: base, progress: progress), base)
    }

    func testEndpointRebaseClockPreservesCommitProgressAndMonotonicity() {
        var progress: CGFloat = 0
        for (settleProgress, expectedProgress) in [
            (CGFloat(0), CGFloat(0)),
            (0.35, 0.35),
            (0.2, 0.35),
            (0.8, 0.8),
            (1, 1),
        ] {
            progress = PlayerBrowserGridCrossfadePlaneRebase
                .endpointClockProgress(
                    previousProgress: progress,
                    driftProgress: 1,
                    settleProgress: settleProgress
                )
            XCTAssertEqual(progress, expectedProgress)
        }
    }

    func testSourceEndpointRebaseClockLandsAtIdentityWithoutRewinding() {
        var progress: CGFloat = 0
        for scale in [CGFloat(0.94), 0.97, 0.96, 0.99, 1] {
            let nextProgress = PlayerBrowserGridCrossfadePlaneRebase
                .sourceEndpointClockProgress(
                    previousProgress: progress,
                    scale: scale,
                    installationScale: 0.94
                )
            XCTAssertGreaterThanOrEqual(nextProgress, progress)
            progress = nextProgress
        }
        XCTAssertEqual(progress, 1)
        XCTAssertEqual(
            PlayerBrowserGridCrossfadePlaneRebase
                .sourceEndpointClockProgress(
                    previousProgress: 0,
                    scale: 1.03,
                    installationScale: 0.94
                ),
            1
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfadePlaneRebase
                .sourceEndpointClockProgress(
                    previousProgress: 0,
                    scale: 0.98,
                    installationScale: 1.06
                ),
            1
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfadePlaneRebase
                .sourceEndpointClockProgress(
                    previousProgress: 0.4,
                    scale: .nan,
                    installationScale: 0.94
                ),
            0.4
        )
    }

}

private extension PlayerBrowserGridPhantomShapeCoverage {
    var repeatedRows: PlayerBrowserGridRepeatedPhantomRows? {
        guard case let .repeatedRows(rows) = self else { return nil }
        return rows
    }

    var solidCoverage: PlayerBrowserGridSolidPhantomCoverage? {
        guard case let .solid(coverage) = self else { return nil }
        return coverage
    }
}
