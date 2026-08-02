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

    private func makeTransition(
        fromColumnCount: Int,
        toColumnCount: Int,
        itemCount: Int = 500,
        progress: CGFloat
    ) throws -> MobilePlayerBrowserGridTransition {
        var transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: makeUniformLayout(
                itemCount: itemCount,
                columnCount: fromColumnCount
            ),
            toLayout: makeUniformLayout(
                itemCount: itemCount,
                columnCount: toColumnCount
            )
        ))
        transition.setProgress(progress)
        return transition
    }

    private func assertFrame(
        _ frame: CGRect,
        matches expectedFrame: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frame.minX, expectedFrame.minX, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.minY, expectedFrame.minY, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.width, expectedFrame.width, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.height, expectedFrame.height, accuracy: 0.000_001, file: file, line: line)
    }

    private func assertCandidateItemIndices(
        _ transition: MobilePlayerBrowserGridTransition,
        intersecting rect: CGRect,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedIndices = (0..<transition.itemCount).filter {
            guard let frame = transition.itemFrame(at: $0) else { return false }
            return frame.maxY >= rect.minY && frame.minY <= rect.maxY
        }
        XCTAssertEqual(
            Array(transition.candidateItemIndices(intersecting: rect)),
            expectedIndices,
            message,
            file: file,
            line: line
        )
    }

    func testEndpointFramesAndContentSizeMatchSourceLayouts() throws {
        let fromLayout = try makeUniformLayout(itemCount: 60, columnCount: 3)
        let toLayout = try makeUniformLayout(itemCount: 60, columnCount: 2)
        var transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fromLayout,
            toLayout: toLayout
        ))

        for itemIndex in [0, 1, 29, 59] {
            XCTAssertEqual(
                try XCTUnwrap(transition.itemFrame(at: itemIndex)),
                try XCTUnwrap(fromLayout.itemFrame(at: itemIndex))
            )
        }
        XCTAssertEqual(transition.contentSize, fromLayout.contentSize)

        transition.setProgress(1)
        for itemIndex in [0, 1, 29, 59] {
            assertFrame(
                try XCTUnwrap(transition.itemFrame(at: itemIndex)),
                matches: try XCTUnwrap(toLayout.itemFrame(at: itemIndex))
            )
        }
        XCTAssertEqual(
            transition.contentSize.width,
            toLayout.contentSize.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transition.contentSize.height,
            toLayout.contentSize.height,
            accuracy: 0.000_001
        )
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

    func testMidpointFramesAverageSourceFrames() throws {
        let fromLayout = try makeUniformLayout(itemCount: 40, columnCount: 4)
        let toLayout = try makeUniformLayout(itemCount: 40, columnCount: 3)
        var transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fromLayout,
            toLayout: toLayout
        ))
        transition.setProgress(0.5)

        for itemIndex in [0, 7, 39] {
            let fromFrame = try XCTUnwrap(fromLayout.itemFrame(at: itemIndex))
            let toFrame = try XCTUnwrap(toLayout.itemFrame(at: itemIndex))
            let interpolatedFrame = try XCTUnwrap(transition.itemFrame(at: itemIndex))
            XCTAssertEqual(
                interpolatedFrame.minX,
                (fromFrame.minX + toFrame.minX) / 2,
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                interpolatedFrame.minY,
                (fromFrame.minY + toFrame.minY) / 2,
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                interpolatedFrame.width,
                (fromFrame.width + toFrame.width) / 2,
                accuracy: 0.000_001
            )
        }
        XCTAssertEqual(
            transition.contentSize.height,
            (fromLayout.contentSize.height + toLayout.contentSize.height) / 2,
            accuracy: 0.000_001
        )
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

    func testCandidateItemIndicesMatchBruteForceForUniformLayouts() throws {
        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
            let transition = try makeTransition(
                fromColumnCount: 3,
                toColumnCount: 1,
                itemCount: 300,
                progress: progress
            )
            let queryRects = [
                CGRect(x: 0, y: -200, width: 390, height: 400),
                CGRect(x: 0, y: 500, width: 390, height: 844),
                CGRect(x: 0, y: 5_000, width: 390, height: 844),
                CGRect(x: 0, y: 100_000, width: 390, height: 844),
                CGRect(x: 0, y: -5_000, width: 390, height: 800)
            ]
            for rect in queryRects {
                assertCandidateItemIndices(
                    transition,
                    intersecting: rect,
                    message: "progress \(progress) rect \(rect)"
                )
            }
        }
    }

    func testCandidateItemIndicesMatchBruteForceForVariableRowLayouts() throws {
        let heightToWidthRatios = (0..<91).map { itemIndex -> CGFloat in
            1 + CGFloat(itemIndex % 5) / 3
        }
        let fromLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: heightToWidthRatios,
                columnCount: 3
            )
        ))
        let toLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: Self.viewportSize,
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: heightToWidthRatios,
                columnCount: 2
            )
        ))
        var transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fromLayout,
            toLayout: toLayout
        ))

        for progress in [CGFloat(0), 0.3, 0.7, 1] {
            transition.setProgress(progress)
            for originY in stride(from: CGFloat(-400), through: 8_000, by: 700) {
                let rect = CGRect(x: 0, y: originY, width: 390, height: 844)
                assertCandidateItemIndices(
                    transition,
                    intersecting: rect,
                    message: "progress \(progress) originY \(originY)"
                )
            }
        }
    }

    func testContentOffsetInterpolationFollowsPanAndClamps() throws {
        var transition = try makeTransition(
            fromColumnCount: 3,
            toColumnCount: 2,
            itemCount: 120,
            progress: 0.5
        )

        let midOffsetY = transition.contentOffsetY(
            fromContentOffsetY: 400,
            toContentOffsetY: 800,
            panDeltaY: 0,
            viewportHeight: 844
        )
        XCTAssertEqual(midOffsetY, 600, accuracy: 0.000_001)

        let pannedOffsetY = transition.contentOffsetY(
            fromContentOffsetY: 400,
            toContentOffsetY: 800,
            panDeltaY: 50,
            viewportHeight: 844
        )
        XCTAssertEqual(pannedOffsetY, 550, accuracy: 0.000_001)

        XCTAssertEqual(
            transition.contentOffsetY(
                fromContentOffsetY: -900,
                toContentOffsetY: -900,
                panDeltaY: 0,
                viewportHeight: 844
            ),
            0
        )

        transition.setProgress(1)
        let maximumOffsetY = max(
            transition.contentSize.height - 844,
            0
        )
        XCTAssertEqual(
            transition.contentOffsetY(
                fromContentOffsetY: 1_000_000,
                toContentOffsetY: 1_000_000,
                panDeltaY: 0,
                viewportHeight: 844
            ),
            maximumOffsetY,
            accuracy: 0.000_001
        )
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

    func testRelativeItemAnchorStaysAtTheSameViewportPositionDuringTransition() throws {
        let fromLayout = try makeUniformLayout(
            itemCount: 80,
            columnCount: 3,
            imageSize: CGSize(width: 2, height: 5)
        )
        let toLayout = try makeUniformLayout(
            itemCount: 80,
            columnCount: 1,
            imageSize: CGSize(width: 2, height: 5)
        )
        let itemIndex = 30
        let relativeItemY: CGFloat = 0.8
        let viewportY: CGFloat = 237
        let fromFrame = try XCTUnwrap(fromLayout.itemFrame(at: itemIndex))
        let toFrame = try XCTUnwrap(toLayout.itemFrame(at: itemIndex))
        let fromContentOffsetY = MobilePlayerBrowserGridTransition.anchorY(
            itemFrame: fromFrame,
            relativeY: relativeItemY
        ) - viewportY
        let toContentOffsetY = MobilePlayerBrowserGridTransition
            .targetContentOffsetY(
                anchorFrame: toFrame,
                anchorRelativeY: relativeItemY,
                anchorViewportY: viewportY
            )
        var transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fromLayout,
            toLayout: toLayout
        ))

        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
            transition.setProgress(progress)
            let frame = try XCTUnwrap(transition.itemFrame(at: itemIndex))
            let contentOffsetY = transition.contentOffsetY(
                fromContentOffsetY: fromContentOffsetY,
                toContentOffsetY: toContentOffsetY,
                panDeltaY: 0,
                viewportHeight: Self.viewportSize.height
            )
            XCTAssertEqual(
                MobilePlayerBrowserGridTransition.anchorY(
                    itemFrame: frame,
                    relativeY: relativeItemY
                ) - contentOffsetY,
                viewportY,
                accuracy: 0.000_001
            )
        }
    }

    func testRawEndpointDefersBoundaryClampUntilItIsNeeded() throws {
        let fromLayout = try makeUniformLayout(
            itemCount: 80,
            columnCount: 1,
            imageSize: CGSize(width: 2, height: 5)
        )
        let toLayout = try makeUniformLayout(
            itemCount: 80,
            columnCount: 4,
            imageSize: CGSize(width: 2, height: 5)
        )
        let itemIndex = 0
        let relativeItemY: CGFloat = 0.8
        let viewportY: CGFloat = 300
        let fromFrame = try XCTUnwrap(fromLayout.itemFrame(at: itemIndex))
        let toFrame = try XCTUnwrap(toLayout.itemFrame(at: itemIndex))
        let fromContentOffsetY = MobilePlayerBrowserGridTransition.anchorY(
            itemFrame: fromFrame,
            relativeY: relativeItemY
        ) - viewportY
        let toContentOffsetY = MobilePlayerBrowserGridTransition
            .targetContentOffsetY(
                anchorFrame: toFrame,
                anchorRelativeY: relativeItemY,
                anchorViewportY: viewportY
            )
        XCTAssertLessThan(toContentOffsetY, 0)

        var transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: fromLayout,
            toLayout: toLayout
        ))
        transition.setProgress(0.5)
        let frame = try XCTUnwrap(transition.itemFrame(at: itemIndex))
        let contentOffsetY = transition.contentOffsetY(
            fromContentOffsetY: fromContentOffsetY,
            toContentOffsetY: toContentOffsetY,
            panDeltaY: 0,
            viewportHeight: Self.viewportSize.height
        )
        XCTAssertGreaterThan(contentOffsetY, 0)
        XCTAssertEqual(
            MobilePlayerBrowserGridTransition.anchorY(
                itemFrame: frame,
                relativeY: relativeItemY
            ) - contentOffsetY,
            viewportY,
            accuracy: 0.000_001
        )
    }

    func testPinchPolicyMapsEffectiveScaleToProgressForBothDirections() {
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.progress(
                effectiveScale: 1.25,
                itemWidthRatio: 1.5
            ),
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.progress(
                effectiveScale: 1.5,
                itemWidthRatio: 1.5
            ),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.progress(
                effectiveScale: 0.875,
                itemWidthRatio: 0.75
            ),
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertLessThan(
            PlayerBrowserGridPinchPolicy.progress(
                effectiveScale: 0.9,
                itemWidthRatio: 1.5
            ),
            0
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.progress(
                effectiveScale: 1.2,
                itemWidthRatio: 1
            ),
            0
        )
    }

    func testPinchPolicyCompletionRespectsProgressAndVelocity() {
        XCTAssertTrue(PlayerBrowserGridPinchPolicy.shouldComplete(
            progress: 0.6,
            velocityTowardTarget: 0
        ))
        XCTAssertFalse(PlayerBrowserGridPinchPolicy.shouldComplete(
            progress: 0.4,
            velocityTowardTarget: 0
        ))
        XCTAssertTrue(PlayerBrowserGridPinchPolicy.shouldComplete(
            progress: 0.2,
            velocityTowardTarget: PlayerBrowserGridPinchPolicy.commitVelocity
        ))
        XCTAssertFalse(PlayerBrowserGridPinchPolicy.shouldComplete(
            progress: 0.05,
            velocityTowardTarget: PlayerBrowserGridPinchPolicy.commitVelocity
        ))
        XCTAssertFalse(PlayerBrowserGridPinchPolicy.shouldComplete(
            progress: 0.8,
            velocityTowardTarget: -PlayerBrowserGridPinchPolicy.commitVelocity
        ))
        XCTAssertFalse(PlayerBrowserGridPinchPolicy.shouldComplete(
            progress: 0,
            velocityTowardTarget: 10
        ))
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
        for viewportSize in viewportSizes {
            for fromMode in MobileCollectionBrowserGridMode.allCases {
                guard let toMode = fromMode.modeWithSmallerItems else { continue }
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

    func testPinchPolicySettleDurationScalesWithRemainingProgress() {
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleDuration(remainingProgress: 0),
            PlayerBrowserGridPinchPolicy.minimumSettleDuration
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleDuration(remainingProgress: 1),
            PlayerBrowserGridPinchPolicy.maximumSettleDuration
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.settleDuration(remainingProgress: -1),
            PlayerBrowserGridPinchPolicy.maximumSettleDuration
        )
        let halfwayDuration = PlayerBrowserGridPinchPolicy.settleDuration(
            remainingProgress: 0.5
        )
        XCTAssertGreaterThan(
            halfwayDuration,
            PlayerBrowserGridPinchPolicy.minimumSettleDuration
        )
        XCTAssertLessThan(
            halfwayDuration,
            PlayerBrowserGridPinchPolicy.maximumSettleDuration
        )
    }

    func testGridModeNeighborSteppingCoversAllModes() {
        XCTAssertNil(MobileCollectionBrowserGridMode.large.modeWithLargerItems)
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.large.modeWithSmallerItems,
            .twoColumns
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.twoColumns.modeWithLargerItems,
            .large
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.twoColumns.modeWithSmallerItems,
            .threeColumns
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.threeColumns.modeWithLargerItems,
            .twoColumns
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.threeColumns.modeWithSmallerItems,
            .fourColumns
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.fourColumns.modeWithLargerItems,
            .threeColumns
        )
        XCTAssertNil(MobileCollectionBrowserGridMode.fourColumns.modeWithSmallerItems)
    }
}
