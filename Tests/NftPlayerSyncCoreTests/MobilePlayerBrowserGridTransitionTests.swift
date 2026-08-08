// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class MobilePlayerBrowserGridTransitionTests: XCTestCase {

    private static let viewportSize = CGSize(width: 390, height: 844)

    private func makeUniformLayout(
        itemCount: Int,
        columnCount: Int,
        imageSize: CGSize = CGSize(width: 512, height: 512),
        viewportSize: CGSize? = nil
    ) throws -> MobilePlayerBrowserLayout {
        try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize ?? Self.viewportSize,
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: itemCount,
                uniformImageSize: imageSize,
                columnCount: columnCount
            )
        ))
    }

    private func makeVariableLayout(
        ratios: [CGFloat],
        columnCount: Int
    ) throws -> MobilePlayerBrowserLayout {
        try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: ratios,
                columnCount: columnCount
            )
        ))
    }

    func testItemWidthRatioComesFromTheConcreteLayouts() throws {
        let viewportSizes = [
            Self.viewportSize,
            CGSize(width: 844, height: 390),
        ]

        for viewportSize in viewportSizes {
            for fromMode in MobileCollectionBrowserGridMode.allCases {
                for toMode in MobileCollectionBrowserGridMode.allCases
                    where fromMode != toMode {
                    let fromLayout = try makeUniformLayout(
                        itemCount: 60,
                        columnCount: fromMode.columnCount,
                        viewportSize: viewportSize
                    )
                    let toLayout = try makeUniformLayout(
                        itemCount: 60,
                        columnCount: toMode.columnCount,
                        viewportSize: viewportSize
                    )
                    let transition = try XCTUnwrap(
                        MobilePlayerBrowserGridTransition(
                            fromLayout: fromLayout,
                            toLayout: toLayout
                        )
                    )

                    XCTAssertEqual(
                        transition.itemWidthRatio,
                        toLayout.itemWidth / fromLayout.itemWidth
                    )
                }
            }
        }
    }

    func testTransitionRequiresDistinctItemWidths() throws {
        let layout = try makeUniformLayout(itemCount: 12, columnCount: 3)
        XCTAssertNil(MobilePlayerBrowserGridTransition(
            fromLayout: layout,
            toLayout: layout
        ))
    }

    func testTransitionRequiresEqualItemCounts() throws {
        XCTAssertNil(MobilePlayerBrowserGridTransition(
            fromLayout: try makeUniformLayout(itemCount: 12, columnCount: 3),
            toLayout: try makeUniformLayout(itemCount: 11, columnCount: 2)
        ))
    }

    func testTargetContentOffsetPreservesAnchorViewportPosition() {
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.targetContentOffsetY(
                anchorFrame: CGRect(x: 0, y: 850, width: 100, height: 100),
                anchorRelativeY: 0.5,
                anchorViewportY: 400
            ),
            500
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.targetContentOffsetY(
                anchorFrame: CGRect(x: 0, y: 50, width: 100, height: 100),
                anchorRelativeY: 0.5,
                anchorViewportY: 700
            ),
            -600
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.targetContentOffsetY(
                anchorFrame: CGRect(x: 0, y: 3_900, width: 100, height: 100),
                anchorRelativeY: 0.5,
                anchorViewportY: 50
            ),
            3_900
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.targetContentOffsetY(
                anchorFrame: CGRect(x: 0, y: 150, width: 100, height: 100),
                anchorRelativeY: 0.5,
                anchorViewportY: 100
            ),
            100
        )
    }

    func testContentOffsetClampHandlesBothBoundariesAndShortContent() {
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.clampedContentOffsetY(
                -600,
                contentHeight: 4_000,
                viewportHeight: 844
            ),
            0
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.clampedContentOffsetY(
                3_900,
                contentHeight: 4_000,
                viewportHeight: 844
            ),
            4_000 - 844
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.clampedContentOffsetY(
                100,
                contentHeight: 400,
                viewportHeight: 844
            ),
            0
        )
    }

    func testAnchorGeometryPreservesThePointInsideTallItems() {
        let frame = CGRect(x: 10, y: 1_000, width: 200, height: 400)

        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorRelativeY(
                contentY: 1_100,
                itemFrame: frame
            ),
            0.25,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.targetContentOffsetY(
                anchorFrame: frame,
                anchorRelativeY: 0.25,
                anchorViewportY: 150
            ),
            950,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorRelativeY(
                contentY: 900,
                itemFrame: frame
            ),
            0
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorRelativeY(
                contentY: 1_500,
                itemFrame: frame
            ),
            1
        )
    }

    func testHorizontalAnchorGeometryMirrorsVerticalBehavior() {
        let frame = CGRect(x: 130, y: 1_000, width: 200, height: 400)

        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorRelativeX(
                contentX: 180,
                itemFrame: frame
            ),
            0.25,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorRelativeX(
                contentX: 0,
                itemFrame: frame
            ),
            0
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorRelativeX(
                contentX: 500,
                itemFrame: frame
            ),
            1
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorRelativeX(
                contentX: .nan,
                itemFrame: frame
            ),
            0.5
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorX(
                itemFrame: frame,
                relativeX: 0.25
            ),
            180,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorX(
                itemFrame: frame,
                relativeX: .nan
            ),
            230,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorX(
                itemFrame: CGRect(x: 40, y: 0, width: 0, height: 10),
                relativeX: 0.7
            ),
            40
        )
    }

    func testPinchPolicySettleTargetPicksTheNearestModeInLogSpace() {
        let ratios: [CGFloat] = [0.6, 1, 3]

        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 1.05,
                velocity: 0,
                itemWidthRatios: ratios
            ),
            1
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 2.0,
                velocity: 0,
                itemWidthRatios: ratios
            ),
            2
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 2.6,
                velocity: 0,
                itemWidthRatios: ratios
            ),
            2
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 0.7,
                velocity: 0,
                itemWidthRatios: ratios
            ),
            0
        )
        XCTAssertNil(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: .nan,
                velocity: 0,
                itemWidthRatios: ratios
            )
        )
        XCTAssertNil(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 1.2,
                velocity: 0,
                itemWidthRatios: []
            )
        )
    }

    func testPinchPolicySettleTargetProjectsTheReleaseVelocity() {
        let ratios: [CGFloat] = [0.6, 1, 3]

        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 1.66,
                velocity: 0,
                itemWidthRatios: ratios
            ),
            1,
            "a still release short of the midpoint settles back by position"
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 1.66,
                velocity: 0.8,
                itemWidthRatios: ratios
            ),
            2,
            "a release still moving outward commits from short of the midpoint"
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 1.9,
                velocity: -1.5,
                itemWidthRatios: ratios
            ),
            1,
            "a release moving back toward the current grid settles back"
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 0.95,
                velocity: -8,
                itemWidthRatios: [0.2, 0.333, 1]
            ),
            0,
            "a violent flick projects across more than one grid"
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 0.95,
                velocity: -1_000_000,
                itemWidthRatios: [0.2, 0.333, 1]
            ),
            0,
            "the projection cap keeps a glitched velocity on the ladder"
        )
    }

    func testPinchPolicyRubberBandsOnlyBeyondTheOutermostRatios() {
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.rubberBandedScale(
                1.4,
                minimumRatio: 0.75,
                maximumRatio: 3
            ),
            1.4
        )
        let beyondMaximum = PlayerBrowserGridPinchPolicy.rubberBandedScale(
            6,
            minimumRatio: 0.75,
            maximumRatio: 3
        )
        XCTAssertGreaterThan(beyondMaximum, 3)
        XCTAssertLessThan(
            beyondMaximum,
            3 * (1 + PlayerBrowserGridPinchPolicy.overshootMaximumDeviation)
        )
        let beyondMinimum = PlayerBrowserGridPinchPolicy.rubberBandedScale(
            0.4,
            minimumRatio: 0.75,
            maximumRatio: 3
        )
        XCTAssertLessThan(beyondMinimum, 0.75)
        XCTAssertGreaterThan(
            beyondMinimum,
            0.75 * (1 - PlayerBrowserGridPinchPolicy.overshootMaximumDeviation)
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.rubberBandedScale(
                .nan,
                minimumRatio: 0.75,
                maximumRatio: 3
            ),
            1
        )
    }

    func testPinchPolicyActivationDeviationStaysBelowAdjacentModeRatioDeviations() throws {
        XCTAssertGreaterThan(
            PlayerBrowserGridPinchPolicy.activationScaleDeviation,
            0
        )

        let viewportSizes = [
            Self.viewportSize,
            CGSize(
                width: Self.viewportSize.height,
                height: Self.viewportSize.width
            )
        ]
        let allModes = MobileCollectionBrowserGridMode.allCases
        for viewportSize in viewportSizes {
            for (fromMode, toMode) in zip(allModes, allModes.dropFirst()) {
                let fromLayout = try makeUniformLayout(
                    itemCount: 1,
                    columnCount: fromMode.columnCount,
                    viewportSize: viewportSize
                )
                let toLayout = try makeUniformLayout(
                    itemCount: 1,
                    columnCount: toMode.columnCount,
                    viewportSize: viewportSize
                )
                let ratios = [
                    toLayout.itemWidth / fromLayout.itemWidth,
                    fromLayout.itemWidth / toLayout.itemWidth
                ]
                for ratio in ratios {
                    XCTAssertLessThan(
                        PlayerBrowserGridPinchPolicy.activationScaleDeviation,
                        abs(ratio - 1),
                        "\(fromMode) and \(toMode) at \(viewportSize)"
                    )
                }
            }
        }
    }

    func testPinchPolicyConsumesOnlyTheActivationDeadZone() {
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.effectiveScaleAfterActivation(1.03),
            1
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.effectiveScaleAfterActivation(1.3),
            1.3 / 1.04,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.effectiveScaleAfterActivation(0.72),
            0.72 / 0.96,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.effectiveScaleAfterActivation(.nan),
            1
        )
    }

    func testPinchPolicyOvershootScaleIsDampedAndSymmetric() {
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.overshootScale(forEffectiveScale: 1),
            1
        )

        let zoomInScale = PlayerBrowserGridPinchPolicy.overshootScale(
            forEffectiveScale: 2
        )
        let zoomOutScale = PlayerBrowserGridPinchPolicy.overshootScale(
            forEffectiveScale: 0.5
        )
        XCTAssertGreaterThan(zoomInScale, 1)
        XCTAssertLessThan(
            zoomInScale,
            1 + PlayerBrowserGridPinchPolicy.overshootMaximumDeviation
        )
        XCTAssertLessThan(zoomOutScale, 1)
        XCTAssertEqual(
            zoomInScale - 1,
            1 - zoomOutScale,
            accuracy: 0.000_001
        )
        XCTAssertGreaterThan(
            PlayerBrowserGridPinchPolicy.overshootScale(forEffectiveScale: 3),
            zoomInScale
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.overshootScale(forEffectiveScale: -1),
            1
        )
    }

    func testPinchPolicySettleSpringConvergesWithASoftTail() {
        var logOffset = log(CGFloat(1.5))
        var logVelocity: CGFloat = 0
        var elapsed: CGFloat = 0
        var timeToRest: CGFloat?
        while elapsed < 3 {
            let stepped = PlayerBrowserGridPinchPolicy.settleSpringStep(
                logOffset: logOffset,
                logVelocity: logVelocity,
                deltaTime: 1.0 / 60
            )
            XCTAssertLessThanOrEqual(
                abs(stepped.logOffset),
                abs(logOffset) + 0.000_001,
                "a critically damped spring never overshoots from rest"
            )
            logOffset = stepped.logOffset
            logVelocity = stepped.logVelocity
            elapsed += 1.0 / 60
            if timeToRest == nil,
               PlayerBrowserGridPinchPolicy.isSettleSpringAtRest(
                   logOffset: logOffset,
                   logVelocity: logVelocity
               ) {
                timeToRest = elapsed
            }
        }
        let restTime = timeToRest ?? 3
        XCTAssertGreaterThan(restTime, 0.4, "the settle keeps a soft tail")
        XCTAssertLessThan(restTime, 1.6, "the settle still finishes promptly")
    }

    func testPinchPolicySettleSeedVelocityBlendsGestureSpeedWithoutOvershoot() {
        let omega = PlayerBrowserGridPinchPolicy.settleAngularFrequency

        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: log(1.5),
                effectiveVelocity: -8,
                scale: 1
            ),
            -omega * log(1.5),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: -0.05,
                effectiveVelocity: -8,
                scale: 0.5
            ),
            omega * 0.05,
            accuracy: 0.000_001
        )

        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: log(1.5),
                effectiveVelocity: 0,
                scale: 1
            ),
            0
        )

        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: 0.5,
                effectiveVelocity: 1,
                scale: 1
            ),
            -1,
            accuracy: 0.000_001
        )

        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: .nan,
                effectiveVelocity: 1,
                scale: 1
            ),
            0
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: 0.3,
                effectiveVelocity: .nan,
                scale: 1
            ),
            -omega * 0.3,
            accuracy: 0.000_001
        )

        for (initialOffset, velocity) in [
            (log(CGFloat(1.5)), CGFloat(-8)),
            (log(CGFloat(0.5)), CGFloat(8)),
            (CGFloat(0.06), CGFloat(0)),
            (CGFloat(-0.3), CGFloat(-1)),
        ] {
            var logOffset = initialOffset
            var logVelocity = PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: initialOffset,
                effectiveVelocity: velocity,
                scale: 1
            )
            var elapsed: CGFloat = 0
            while elapsed < 3 {
                let stepped = PlayerBrowserGridPinchPolicy.settleSpringStep(
                    logOffset: logOffset,
                    logVelocity: logVelocity,
                    deltaTime: 1.0 / 60
                )
                XCTAssertLessThanOrEqual(
                    abs(stepped.logOffset),
                    abs(logOffset) + 0.000_001,
                    "the settle never overshoots the target"
                )
                XCTAssertEqual(
                    stepped.logOffset < 0,
                    initialOffset < 0,
                    "the settle never crosses to the far side of the target"
                )
                logOffset = stepped.logOffset
                logVelocity = stepped.logVelocity
                elapsed += 1.0 / 60
            }
            XCTAssertTrue(PlayerBrowserGridPinchPolicy.isSettleSpringAtRest(
                logOffset: logOffset,
                logVelocity: logVelocity
            ))
        }
    }

    func testPitchRatiosLandSeamsExactly() throws {
        let fiveColumns = try makeUniformLayout(
            itemCount: 120,
            columnCount: 5,
            imageSize: CGSize(width: 500, height: 600)
        )
        let oneColumn = try makeUniformLayout(
            itemCount: 120,
            columnCount: 1,
            imageSize: CGSize(width: 500, height: 600)
        )
        let transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fiveColumns,
            toLayout: oneColumn
        ))

        let fromRowPitch = try XCTUnwrap(fiveColumns.itemFrame(at: 5)).minY
            - (try XCTUnwrap(fiveColumns.itemFrame(at: 0))).minY
        let toRowPitch = try XCTUnwrap(oneColumn.itemFrame(at: 1)).minY
            - (try XCTUnwrap(oneColumn.itemFrame(at: 0))).minY
        XCTAssertEqual(
            fromRowPitch * transition.rowPitchRatio,
            toRowPitch,
            accuracy: 0.000_1
        )

        let fromColumnPitch = try XCTUnwrap(fiveColumns.itemFrame(at: 1)).minX
            - (try XCTUnwrap(fiveColumns.itemFrame(at: 0))).minX
        XCTAssertEqual(
            fromColumnPitch,
            fiveColumns.itemWidth + fiveColumns.interItemSpacing,
            accuracy: 0.000_1
        )
        // The one-column lattice has no second column to sample, so the pitch
        // it must land on is the item width plus its own inter-item spacing.
        let toColumnPitch = oneColumn.itemWidth + oneColumn.interItemSpacing
        XCTAssertEqual(
            fromColumnPitch * transition.columnPitchRatio,
            toColumnPitch,
            accuracy: 0.000_1
        )
        // The whole point of the pitch ratio: spacing does not scale with the
        // item width, so landing on the item-width ratio misses the seam.
        XCTAssertNotEqual(
            transition.columnPitchRatio,
            transition.itemWidthRatio,
            accuracy: 0.001
        )
    }

    func testColumnPitchRatioLandsSeamsBetweenAdjacentLadderModes() throws {
        let fiveColumns = try makeUniformLayout(itemCount: 120, columnCount: 5)
        let threeColumns = try makeUniformLayout(itemCount: 120, columnCount: 3)
        let transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fiveColumns,
            toLayout: threeColumns
        ))

        let fromColumnPitch = try XCTUnwrap(fiveColumns.itemFrame(at: 1)).minX
            - (try XCTUnwrap(fiveColumns.itemFrame(at: 0))).minX
        let toColumnPitch = try XCTUnwrap(threeColumns.itemFrame(at: 1)).minX
            - (try XCTUnwrap(threeColumns.itemFrame(at: 0))).minX
        XCTAssertEqual(
            fromColumnPitch * transition.columnPitchRatio,
            toColumnPitch,
            accuracy: 0.000_1
        )
        XCTAssertNotEqual(
            transition.columnPitchRatio,
            transition.itemWidthRatio,
            accuracy: 0.001
        )
    }

    func testLatticeMapPinsTheAnchorAndScalesEachAxisOnItsOwnPitch() throws {
        let fiveColumns = try makeUniformLayout(
            itemCount: 120,
            columnCount: 5,
            imageSize: CGSize(width: 500, height: 600)
        )
        let threeColumns = try makeUniformLayout(
            itemCount: 120,
            columnCount: 3,
            imageSize: CGSize(width: 500, height: 600)
        )
        let transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fiveColumns,
            toLayout: threeColumns
        ))
        // Unequal on purpose: a map that used one ratio for both axes, or
        // swapped them, has to fail here.
        XCTAssertNotEqual(
            transition.columnPitchRatio,
            transition.rowPitchRatio,
            accuracy: 0.001
        )

        let fromAnchor = CGPoint(x: 120, y: 1_400)
        let toAnchor = CGPoint(x: 210, y: 2_050)
        let map = transition.latticeMap(
            fromAnchorContentPoint: fromAnchor,
            toAnchorContentPoint: toAnchor
        )

        XCTAssertEqual(map.destinationPoint(fromSource: fromAnchor).x, toAnchor.x, accuracy: 0.000_1)
        XCTAssertEqual(map.destinationPoint(fromSource: fromAnchor).y, toAnchor.y, accuracy: 0.000_1)
        XCTAssertEqual(map.sourcePoint(fromDestination: toAnchor).x, fromAnchor.x, accuracy: 0.000_1)
        XCTAssertEqual(map.sourcePoint(fromDestination: toAnchor).y, fromAnchor.y, accuracy: 0.000_1)

        let offAnchor = CGPoint(x: 300, y: 900)
        XCTAssertEqual(
            map.destinationPoint(fromSource: offAnchor).x,
            toAnchor.x + (offAnchor.x - fromAnchor.x) * transition.columnPitchRatio,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            map.destinationPoint(fromSource: offAnchor).y,
            toAnchor.y + (offAnchor.y - fromAnchor.y) * transition.rowPitchRatio,
            accuracy: 0.000_1
        )
        let roundTripped = map.sourcePoint(
            fromDestination: map.destinationPoint(fromSource: offAnchor)
        )
        XCTAssertEqual(roundTripped.x, offAnchor.x, accuracy: 0.000_1)
        XCTAssertEqual(roundTripped.y, offAnchor.y, accuracy: 0.000_1)

        let destinationRect = CGRect(x: 240, y: 1_800, width: 90, height: 108)
        let sourceRect = map.sourceRect(fromDestination: destinationRect)
        XCTAssertEqual(
            sourceRect.origin.x,
            map.sourcePoint(fromDestination: destinationRect.origin).x,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            sourceRect.width,
            destinationRect.width / transition.columnPitchRatio,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            sourceRect.height,
            destinationRect.height / transition.rowPitchRatio,
            accuracy: 0.000_1
        )
    }

    func testRowPitchRatioStaysIsotropicOnVariableRowHeights() throws {
        // One tall item lands in row 0 at five columns but row 1 at three, so
        // a row-0 pitch sample describes neither lattice.
        var ratios = [CGFloat](repeating: 1, count: 120)
        ratios[3] = 3
        let threeColumns = try makeVariableLayout(ratios: ratios, columnCount: 3)
        let fiveColumns = try makeVariableLayout(ratios: ratios, columnCount: 5)
        XCTAssertFalse(threeColumns.usesUniformRowHeights)
        XCTAssertFalse(fiveColumns.usesUniformRowHeights)

        let transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: threeColumns,
            toLayout: fiveColumns
        ))
        XCTAssertEqual(transition.rowPitchRatio, transition.itemWidthRatio)

        let sampledFromPitch = try XCTUnwrap(threeColumns.itemFrame(at: 3)).minY
            - (try XCTUnwrap(threeColumns.itemFrame(at: 0))).minY
        let sampledToPitch = try XCTUnwrap(fiveColumns.itemFrame(at: 5)).minY
            - (try XCTUnwrap(fiveColumns.itemFrame(at: 0))).minY
        XCTAssertGreaterThan(
            abs(sampledToPitch / sampledFromPitch - transition.itemWidthRatio),
            0.5,
            "the sampled pitch is wildly unrepresentative, so the fallback matters"
        )
    }
}
