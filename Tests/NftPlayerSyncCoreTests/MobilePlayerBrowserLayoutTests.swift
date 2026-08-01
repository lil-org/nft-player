// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class MobilePlayerBrowserLayoutTests: XCTestCase {

    func testBustaBouncaUsesFullWidthAndWidthDerivedRowHeight() throws {
        let viewportWidth: CGFloat = 430
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: viewportWidth, height: 932),
            topContentInset: 59,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 12,
                uniformImageSize: CGSize(width: 210, height: 373)
            )
        ))
        let itemSize = try XCTUnwrap(layout.uniformItemSize)

        XCTAssertEqual(layout.columnCount, MobilePlayerBrowserLayout.defaultColumnCount)
        XCTAssertEqual(
            itemSize.width * 3 + MobilePlayerBrowserLayout.itemSpacing * 2,
            viewportWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            itemSize.height,
            itemSize.width * 373 / 210,
            accuracy: 0.000_001
        )
        XCTAssertEqual(layout.visibleRowCount, 4)
        XCTAssertEqual(layout.prefetchStride, 12)
    }

    func testSquareArtRemainsThreeWideAndPrefetchIsCapped() throws {
        let viewportWidth: CGFloat = 390
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: viewportWidth, height: 844),
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 30,
                uniformImageSize: CGSize(width: 512, height: 512)
            )
        ))
        let itemSize = try XCTUnwrap(layout.uniformItemSize)

        XCTAssertEqual(
            itemSize.width * 3 + MobilePlayerBrowserLayout.itemSpacing * 2,
            viewportWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(itemSize.height, itemSize.width, accuracy: 0.000_001)
        XCTAssertEqual(layout.visibleRowCount, 6)
        XCTAssertEqual(layout.prefetchStride, 15)
    }

    func testMixedAspectItemsUseTallestAspectOnlyWithinTheirRow() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(itemImageSizes: [
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 1, height: 2),
                CGSize(width: 2, height: 1),
                CGSize(width: 2, height: 1),
                CGSize(width: 2, height: 1),
            ])
        ))

        XCTAssertFalse(layout.usesUniformRowHeights)
        XCTAssertEqual(layout.cachedVariableRowCount, 2)
        for itemIndex in 0...2 {
            XCTAssertEqual(
                try XCTUnwrap(layout.itemSize(at: itemIndex)).height,
                layout.itemWidth * 2,
                accuracy: 0.000_001
            )
        }
        for itemIndex in 3...5 {
            XCTAssertEqual(
                try XCTUnwrap(layout.itemSize(at: itemIndex)).height,
                layout.itemWidth * 0.5,
                accuracy: 0.000_001
            )
        }
    }

    func testInYourDreamsUsesVariableCachedRowHeights() throws {
        let aspectRatios = [
            CGSize(width: 1, height: 1),
            CGSize(width: 325, height: 183),
            CGSize(width: 140, height: 249),
            CGSize(width: 325, height: 244),
        ]
        let aspectRatioOverrides = [
            (2, 3), (4, 2), (5, 2), (6, 2), (7, 3), (8, 1),
            (12, 1), (13, 3), (14, 1), (15, 1), (16, 3), (17, 3),
            (19, 1), (20, 2), (22, 1), (23, 1), (24, 1), (25, 1),
            (26, 1), (27, 1), (34, 1), (35, 2), (36, 1), (40, 1),
            (42, 1), (43, 1), (45, 3), (46, 2), (49, 2), (51, 1),
            (52, 1), (63, 2), (64, 1), (65, 2), (66, 2), (67, 2),
            (68, 2), (69, 2), (70, 1), (71, 2), (72, 2), (73, 2),
            (74, 1), (75, 2),
        ]
        var itemImageSizes = Array(repeating: aspectRatios[0], count: 76)
        for (itemIndex, aspectRatioIndex) in aspectRatioOverrides {
            itemImageSizes[itemIndex] = aspectRatios[aspectRatioIndex]
        }
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 430, height: 932),
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemImageSizes: itemImageSizes
            )
        ))
        let expectedRowRatios: [CGFloat] = [
            1,
            249 / 140,
            249 / 140,
            1,
            244 / 325,
            244 / 325,
            249 / 140,
            1,
            183 / 325,
            1,
            1,
            249 / 140,
            1,
            1,
            1,
            249 / 140,
            249 / 140,
            1,
            1,
            1,
            1,
            249 / 140,
            249 / 140,
            249 / 140,
            249 / 140,
            249 / 140,
        ]

        XCTAssertEqual(layout.cachedVariableRowCount, expectedRowRatios.count)
        for (rowIndex, expectedRatio) in expectedRowRatios.enumerated() {
            XCTAssertEqual(
                try XCTUnwrap(
                    layout.itemSize(at: rowIndex * layout.columnCount)
                ).height,
                layout.itemWidth * expectedRatio,
                accuracy: 0.000_001
            )
        }
        XCTAssertEqual(
            layout.contentSize.height,
            expectedRowRatios.reduce(0, +) * layout.itemWidth
                + CGFloat(expectedRowRatios.count - 1)
                    * MobilePlayerBrowserLayout.itemSpacing,
            accuracy: 0.000_001
        )
    }

    func testUniformAspectItemsUseFixedSizeFastPath() throws {
        XCTAssertTrue(MobilePlayerBrowserAspectProfile(itemImageSizes: [
            CGSize(width: 512, height: 512),
            CGSize(width: 1, height: 1),
            CGSize(width: 2048, height: 2048),
        ]).usesUniformAspectRatio)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 10_000,
            uniformImageSize: CGSize(width: 512, height: 512)
        )
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: aspectProfile
        ))

        XCTAssertTrue(aspectProfile.usesUniformAspectRatio)
        XCTAssertTrue(layout.usesUniformRowHeights)
        XCTAssertEqual(layout.cachedVariableRowCount, 0)
        XCTAssertNotNil(layout.uniformItemSize)
        XCTAssertEqual(layout.itemSize(at: 0), layout.itemSize(at: 9_999))
        XCTAssertEqual(layout.rowCount, 3_334)
        let finalItemFrame = try XCTUnwrap(layout.itemFrame(at: 9_999))
        XCTAssertEqual(
            finalItemFrame.maxY + 34,
            layout.contentSize.height,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            visibleItemIndices(inInteriorOf: finalItemFrame, layout: layout),
            [9_999]
        )
    }

    func testUniformVisibleLookupSafelyHandlesExtremeFiniteRectangles() throws {
        let itemCount = 12
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: itemCount,
                uniformImageSize: CGSize(width: 1, height: 1)
            )
        ))
        let extremeCoordinate = CGFloat.greatestFiniteMagnitude / 4

        XCTAssertEqual(
            layout.candidateItemIndices(intersecting: CGRect(
                x: 0,
                y: -extremeCoordinate,
                width: layout.contentSize.width,
                height: 1
            )),
            0..<0
        )
        XCTAssertEqual(
            layout.candidateItemIndices(intersecting: CGRect(
                x: 0,
                y: extremeCoordinate,
                width: layout.contentSize.width,
                height: 1
            )),
            0..<0
        )
        XCTAssertEqual(
            layout.candidateItemIndices(intersecting: CGRect(
                x: 0,
                y: -extremeCoordinate,
                width: layout.contentSize.width,
                height: extremeCoordinate * 2
            )),
            0..<itemCount
        )
    }

    func testUniformVisibleLookupKeepsExtremeItemCountArithmeticBounded() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: Int.max,
                uniformImageSize: CGSize(width: 1, height: 1)
            )
        ))
        let extremeCoordinate = CGFloat.greatestFiniteMagnitude / 4
        let candidates = layout.candidateItemIndices(intersecting: CGRect(
            x: 0,
            y: -extremeCoordinate,
            width: layout.contentSize.width,
            height: extremeCoordinate * 2
        ))

        XCTAssertEqual(candidates.lowerBound, 0)
        XCTAssertEqual(candidates.upperBound, Int.max)
    }

    func testPartialFinalRowUsesOnlyItsExistingItems() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            aspectProfile: MobilePlayerBrowserAspectProfile(itemImageSizes: [
                CGSize(width: 1, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 2, height: 1),
            ])
        ))

        XCTAssertEqual(
            try XCTUnwrap(layout.itemSize(at: 0)).height,
            layout.itemWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.itemSize(at: 3)).height,
            layout.itemWidth * 0.5,
            accuracy: 0.000_001
        )
    }

    func testInvalidAspectMetadataPreservesItemPositionsAndFallsBackToSquare() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            aspectProfile: MobilePlayerBrowserAspectProfile(itemImageSizes: [
                CGSize(width: 2, height: 1),
                .zero,
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 2),
            ])
        ))

        XCTAssertEqual(
            try XCTUnwrap(layout.itemSize(at: 0)).height,
            layout.itemWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.itemSize(at: 3)).height,
            layout.itemWidth * 2,
            accuracy: 0.000_001
        )
    }

    func testVariableFramesPackRowsAndVisibleLookupDoesNotSkipItems() throws {
        let topInset: CGFloat = 10
        let bottomInset: CGFloat = 20
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            topContentInset: topInset,
            bottomContentInset: bottomInset,
            aspectProfile: MobilePlayerBrowserAspectProfile(itemImageSizes: [
                CGSize(width: 1, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 2, height: 1),
                CGSize(width: 2, height: 1),
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 2),
            ])
        ))
        let firstRowFrame = try XCTUnwrap(layout.itemFrame(at: 0))
        let secondRowFrame = try XCTUnwrap(layout.itemFrame(at: 3))
        let finalRowFrame = try XCTUnwrap(layout.itemFrame(at: 6))

        XCTAssertEqual(firstRowFrame.minY, topInset, accuracy: 0.000_001)
        XCTAssertEqual(
            secondRowFrame.minY,
            firstRowFrame.maxY + MobilePlayerBrowserLayout.itemSpacing,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            finalRowFrame.minY,
            secondRowFrame.maxY + MobilePlayerBrowserLayout.itemSpacing,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.itemFrame(at: 2)).maxX,
            layout.contentSize.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            layout.contentSize.height,
            finalRowFrame.maxY + bottomInset,
            accuracy: 0.000_001
        )

        XCTAssertEqual(
            visibleItemIndices(inInteriorOf: secondRowFrame, layout: layout),
            [3, 4, 5]
        )
    }

    func testRotationRecalculatesGeometryAndPrefetchStride() throws {
        let portraitViewportSize = CGSize(width: 430, height: 932)
        let landscapeViewportSize = CGSize(width: 932, height: 430)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 12,
            uniformImageSize: CGSize(width: 210, height: 373)
        )
        let portraitTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: .zero,
            viewportSize: portraitViewportSize,
            needsSafeAreaRefresh: true,
            topContentInset: 59,
            bottomContentInset: 34,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 7
        )
        let rotationTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: portraitViewportSize,
            viewportSize: landscapeViewportSize,
            needsSafeAreaRefresh: false,
            bottomContentInset: 21,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 7
        )
        let portrait = try XCTUnwrap(portraitTransition.layout)
        let landscape = try XCTUnwrap(rotationTransition.layout)
        let portraitItemSize = try XCTUnwrap(portrait.uniformItemSize)
        let landscapeItemSize = try XCTUnwrap(landscape.uniformItemSize)

        XCTAssertEqual(aspectProfile.columnCount, 3)
        XCTAssertEqual(portrait.columnCount, 3)
        XCTAssertEqual(landscape.columnCount, 6)
        XCTAssertEqual(portrait.rowCount, 4)
        XCTAssertEqual(landscape.rowCount, 2)
        XCTAssertNotEqual(portraitItemSize, landscapeItemSize)
        XCTAssertEqual(portrait.prefetchStride, 12)
        XCTAssertEqual(landscape.prefetchStride, 12)
        XCTAssertEqual(rotationTransition.retainedFocusTokenIndex, 7)
        XCTAssertLessThan(landscapeItemSize.height, landscapeViewportSize.height)
        XCTAssertEqual(
            try XCTUnwrap(landscape.itemFrame(at: 5)).maxX,
            landscapeViewportSize.width,
            accuracy: 0.000_001
        )

        let finalItemFrame = try XCTUnwrap(landscape.itemFrame(at: 11))
        let maximumContentOffsetY = max(
            landscape.contentSize.height - landscapeViewportSize.height,
            0
        )
        XCTAssertTrue(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: finalItemFrame,
                viewport: CGRect(
                    x: 0,
                    y: maximumContentOffsetY,
                    width: landscapeViewportSize.width,
                    height: landscapeViewportSize.height
                ),
                maximumContentOffsetY: maximumContentOffsetY,
                epsilon: 0.75
            )
        )
    }

    func testSafeAreaOnlyRelayoutPreservesInteriorRowsAndScrollBoundaries() throws {
        let viewportSize = CGSize(width: 430, height: 932)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 24,
            uniformImageSize: CGSize(width: 210, height: 373)
        )
        let hiddenStatusBarLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            topContentInset: 0,
            bottomContentInset: 34,
            aspectProfile: aspectProfile
        ))
        let visibleStatusBarLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            topContentInset: 59,
            bottomContentInset: 34,
            aspectProfile: aspectProfile
        ))
        let previousContentOffsetY: CGFloat = 320
        let topInsetDelta: CGFloat = 59
        let hiddenStatusBarRange: ClosedRange<CGFloat> = 0...max(
            hiddenStatusBarLayout.contentSize.height - viewportSize.height,
            0
        )
        let visibleStatusBarRange: ClosedRange<CGFloat> = 0...max(
            visibleStatusBarLayout.contentSize.height - viewportSize.height,
            0
        )
        let compensatedContentOffsetY =
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: previousContentOffsetY,
                previousRange: hiddenStatusBarRange,
                updatedRange: visibleStatusBarRange,
                topContentInsetDelta: topInsetDelta,
                boundaryEpsilon: 0.75
            )

        XCTAssertEqual(
            visibleStatusBarLayout.contentSize.height
                - hiddenStatusBarLayout.contentSize.height,
            topInsetDelta,
            accuracy: 0.000_001
        )
        for itemIndex in [0, 7, 23] {
            let hiddenFrame = try XCTUnwrap(
                hiddenStatusBarLayout.itemFrame(at: itemIndex)
            )
            let visibleFrame = try XCTUnwrap(
                visibleStatusBarLayout.itemFrame(at: itemIndex)
            )
            XCTAssertEqual(
                visibleFrame.minY - hiddenFrame.minY,
                topInsetDelta,
                accuracy: 0.000_001
            )
            XCTAssertEqual(visibleFrame.size, hiddenFrame.size)
            XCTAssertEqual(
                visibleFrame.midY - compensatedContentOffsetY,
                hiddenFrame.midY - previousContentOffsetY,
                accuracy: 0.000_001
            )
        }
        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: hiddenStatusBarRange.lowerBound,
                previousRange: hiddenStatusBarRange,
                updatedRange: visibleStatusBarRange,
                topContentInsetDelta: topInsetDelta,
                boundaryEpsilon: 0.75
            ),
            visibleStatusBarRange.lowerBound
        )
        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: hiddenStatusBarRange.upperBound,
                previousRange: hiddenStatusBarRange,
                updatedRange: visibleStatusBarRange,
                topContentInsetDelta: topInsetDelta,
                boundaryEpsilon: 0.75
            ),
            visibleStatusBarRange.upperBound
        )
        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: 0.5,
                previousRange: 0...0.5,
                updatedRange: 0...10,
                topContentInsetDelta: topInsetDelta,
                boundaryEpsilon: 0.75
            ),
            10
        )
        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: compensatedContentOffsetY,
                previousRange: visibleStatusBarRange,
                updatedRange: hiddenStatusBarRange,
                topContentInsetDelta: -topInsetDelta,
                boundaryEpsilon: 0.75
            ),
            previousContentOffsetY,
            accuracy: 0.000_001
        )
    }

    func testSafeAreaOffsetClampsFiniteAdditionOverflowTowardUpdatedBoundary() {
        let extreme = CGFloat.greatestFiniteMagnitude
        let interiorMagnitude = extreme * 0.75

        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: interiorMagnitude,
                previousRange: 0...extreme,
                updatedRange: 0...extreme,
                topContentInsetDelta: interiorMagnitude,
                boundaryEpsilon: 0
            ),
            extreme
        )
        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: -interiorMagnitude,
                previousRange: (-extreme)...0,
                updatedRange: (-extreme)...0,
                topContentInsetDelta: -interiorMagnitude,
                boundaryEpsilon: 0
            ),
            -extreme
        )
    }

    func testSafeAreaOffsetKeepsInteriorAndBottomStickyForBottomOnlyChange() {
        let previousRange: ClosedRange<CGFloat> = 0...100
        let updatedRange: ClosedRange<CGFloat> = 0...140

        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: 40,
                previousRange: previousRange,
                updatedRange: updatedRange,
                topContentInsetDelta: 0,
                boundaryEpsilon: 0.75
            ),
            40
        )
        XCTAssertEqual(
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: previousRange.upperBound,
                previousRange: previousRange,
                updatedRange: updatedRange,
                topContentInsetDelta: 0,
                boundaryEpsilon: 0.75
            ),
            updatedRange.upperBound
        )
    }

    func testInitialLandscapeLayoutDoublesBaseColumnCount() throws {
        let viewportSize = CGSize(width: 844, height: 390)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 7,
            uniformImageSize: CGSize(width: 1, height: 1)
        )
        let transition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: .zero,
            viewportSize: viewportSize,
            needsSafeAreaRefresh: false,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 4
        )
        let layout = try XCTUnwrap(transition.layout)

        XCTAssertTrue(transition.needsInitialLayout)
        XCTAssertEqual(aspectProfile.columnCount, 3)
        XCTAssertEqual(layout.columnCount, 6)
        XCTAssertEqual(layout.rowCount, 2)
        XCTAssertEqual(layout.prefetchStride, 15)
        XCTAssertEqual(
            try XCTUnwrap(layout.itemFrame(at: 5)).maxX,
            viewportSize.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.itemFrame(at: 6)).minX,
            0,
            accuracy: 0.000_001
        )
    }

    func testFourColumnModeUsesFourPortraitAndEightLandscapeColumns() throws {
        let portraitSize = CGSize(width: 390, height: 844)
        let landscapeSize = CGSize(width: 844, height: 390)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 17,
            uniformImageSize: CGSize(width: 1, height: 1),
            columnCount: 4
        )
        let portrait = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: portraitSize,
            aspectProfile: aspectProfile
        ))
        let landscape = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: landscapeSize,
            aspectProfile: aspectProfile
        ))

        XCTAssertEqual(portrait.columnCount, 4)
        XCTAssertEqual(portrait.rowCount, 5)
        XCTAssertEqual(landscape.columnCount, 8)
        XCTAssertEqual(landscape.rowCount, 3)
        XCTAssertEqual(
            try XCTUnwrap(portrait.itemFrame(at: 3)).maxX,
            portraitSize.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(landscape.itemFrame(at: 7)).maxX,
            landscapeSize.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(landscape.itemFrame(at: 8)).minX,
            0,
            accuracy: 0.000_001
        )
    }

    func testSquareViewportKeepsPortraitColumnCount() throws {
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 8,
            uniformImageSize: CGSize(width: 1, height: 1),
            columnCount: 2
        )
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 430, height: 430),
            aspectProfile: aspectProfile
        ))

        XCTAssertEqual(aspectProfile.columnCount, 2)
        XCTAssertEqual(layout.columnCount, 2)
    }

    func testTwoColumnUniformGeometryUsesFullWidthAndFindsPartialFinalRow() throws {
        let viewportWidth: CGFloat = 390
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 5,
            uniformImageSize: CGSize(width: 1, height: 1),
            columnCount: 2
        )
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: viewportWidth, height: 844),
            topContentInset: 47,
            bottomContentInset: 34,
            aspectProfile: aspectProfile
        ))
        let itemSize = try XCTUnwrap(layout.uniformItemSize)
        let finalItemFrame = try XCTUnwrap(layout.itemFrame(at: 4))

        XCTAssertEqual(aspectProfile.columnCount, 2)
        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(layout.rowCount, 3)
        XCTAssertEqual(
            itemSize.width * 2 + MobilePlayerBrowserLayout.itemSpacing,
            viewportWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.itemFrame(at: 1)).maxX,
            viewportWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(finalItemFrame.minX, 0, accuracy: 0.000_001)
        XCTAssertEqual(layout.visibleRowCount, 4)
        XCTAssertEqual(layout.prefetchStride, 8)

        XCTAssertEqual(
            visibleItemIndices(inInteriorOf: finalItemFrame, layout: layout),
            [4]
        )
    }

    func testTwoColumnVariableRowsGroupPairsAndPackFrames() throws {
        let topInset: CGFloat = 10
        let bottomInset: CGFloat = 20
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            topContentInset: topInset,
            bottomContentInset: bottomInset,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemImageSizes: [
                    CGSize(width: 2, height: 1),
                    CGSize(width: 1, height: 1),
                    CGSize(width: 1, height: 2),
                    CGSize(width: 2, height: 1),
                    CGSize(width: 4, height: 1),
                ],
                columnCount: 2
            )
        ))
        let firstRowFrame = try XCTUnwrap(layout.itemFrame(at: 0))
        let secondRowFrame = try XCTUnwrap(layout.itemFrame(at: 2))
        let finalRowFrame = try XCTUnwrap(layout.itemFrame(at: 4))

        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(layout.rowCount, 3)
        XCTAssertFalse(layout.usesUniformRowHeights)
        XCTAssertEqual(layout.cachedVariableRowCount, 3)
        XCTAssertEqual(firstRowFrame.height, layout.itemWidth, accuracy: 0.000_001)
        XCTAssertEqual(
            secondRowFrame.height,
            layout.itemWidth * 2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            finalRowFrame.height,
            layout.itemWidth * 0.25,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            secondRowFrame.minY,
            firstRowFrame.maxY + MobilePlayerBrowserLayout.itemSpacing,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            finalRowFrame.minY,
            secondRowFrame.maxY + MobilePlayerBrowserLayout.itemSpacing,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.itemFrame(at: 3)).maxX,
            layout.contentSize.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            layout.contentSize.height,
            finalRowFrame.maxY + bottomInset,
            accuracy: 0.000_001
        )

        XCTAssertEqual(
            visibleItemIndices(inInteriorOf: secondRowFrame, layout: layout),
            [2, 3]
        )
    }

    func testTwoColumnLandscapeVariableRowsMergeCachedPortraitRowPairs() throws {
        try assertLandscapeVariableRows(
            itemImageSizes: [
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 1, height: 2),
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 3),
            ],
            baseColumnCount: 2,
            expectedRowRatios: [2, 3]
        )
    }

    func testLandscapeVariableRowsMergePortraitRowsAndFindPartialFinalRow() throws {
        try assertLandscapeVariableRows(
            itemImageSizes: [
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 4, height: 3),
                CGSize(width: 1, height: 2),
                CGSize(width: 2, height: 1),
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 3),
            ],
            baseColumnCount: MobilePlayerBrowserLayout.defaultColumnCount,
            expectedRowRatios: [2, 3]
        )
    }

    func testTwoColumnRotationDoublesColumnsAndRetainsFocus() throws {
        let portraitSize = CGSize(width: 430, height: 932)
        let landscapeSize = CGSize(width: 932, height: 430)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 12,
            uniformImageSize: CGSize(width: 210, height: 373),
            columnCount: 2
        )
        let portraitTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: .zero,
            viewportSize: portraitSize,
            needsSafeAreaRefresh: true,
            topContentInset: 59,
            bottomContentInset: 34,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 7
        )
        let rotationTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: portraitSize,
            viewportSize: landscapeSize,
            needsSafeAreaRefresh: false,
            bottomContentInset: 21,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 7
        )
        let returnTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: landscapeSize,
            viewportSize: portraitSize,
            needsSafeAreaRefresh: false,
            topContentInset: 59,
            bottomContentInset: 34,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 7
        )
        let portrait = try XCTUnwrap(portraitTransition.layout)
        let landscape = try XCTUnwrap(rotationTransition.layout)
        let returnedPortrait = try XCTUnwrap(returnTransition.layout)

        XCTAssertTrue(portraitTransition.needsInitialLayout)
        XCTAssertTrue(rotationTransition.geometryChanged)
        XCTAssertFalse(rotationTransition.needsInitialLayout)
        XCTAssertEqual(rotationTransition.retainedFocusTokenIndex, 7)
        XCTAssertTrue(returnTransition.geometryChanged)
        XCTAssertEqual(returnTransition.retainedFocusTokenIndex, 7)
        XCTAssertEqual(aspectProfile.columnCount, 2)
        XCTAssertEqual(portrait.columnCount, 2)
        XCTAssertEqual(landscape.columnCount, 4)
        XCTAssertEqual(returnedPortrait.columnCount, 2)
        XCTAssertEqual(portrait.rowCount, 6)
        XCTAssertEqual(landscape.rowCount, 3)
        XCTAssertEqual(returnedPortrait.rowCount, 6)
        XCTAssertNotEqual(portrait.uniformItemSize, landscape.uniformItemSize)
        XCTAssertEqual(portrait.prefetchStride, 6)
        XCTAssertEqual(landscape.prefetchStride, 4)
        XCTAssertEqual(returnedPortrait.prefetchStride, 6)
        XCTAssertEqual(
            try XCTUnwrap(landscape.itemFrame(at: 3)).maxX,
            landscapeSize.width,
            accuracy: 0.000_001
        )
    }

    func testLargeModeRotationUsesOneAndTwoColumnsAndRetainsFocus() throws {
        let portraitSize = CGSize(width: 430, height: 932)
        let landscapeSize = CGSize(width: 932, height: 430)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 7,
            uniformImageSize: CGSize(width: 210, height: 373),
            columnCount: 1
        )
        let portraitTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: .zero,
            viewportSize: portraitSize,
            needsSafeAreaRefresh: true,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 4
        )
        let rotationTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: portraitSize,
            viewportSize: landscapeSize,
            needsSafeAreaRefresh: false,
            aspectProfile: aspectProfile,
            forcedTokenIndex: nil,
            focusedTokenIndex: 4
        )
        let portrait = try XCTUnwrap(portraitTransition.layout)
        let landscape = try XCTUnwrap(rotationTransition.layout)

        XCTAssertEqual(aspectProfile.columnCount, 1)
        XCTAssertEqual(portrait.columnCount, 1)
        XCTAssertEqual(landscape.columnCount, 2)
        XCTAssertEqual(
            portrait.interItemSpacing,
            MobilePlayerBrowserLayout.itemSpacing * 2
        )
        XCTAssertEqual(landscape.interItemSpacing, portrait.interItemSpacing)
        XCTAssertEqual(portrait.rowCount, 7)
        XCTAssertEqual(landscape.rowCount, 4)
        XCTAssertEqual(rotationTransition.retainedFocusTokenIndex, 4)
        XCTAssertEqual(
            try XCTUnwrap(portrait.itemFrame(at: 1)).minY,
            try XCTUnwrap(portrait.itemFrame(at: 0)).maxY
                + portrait.interItemSpacing,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(landscape.itemFrame(at: 1)).minX,
            try XCTUnwrap(landscape.itemFrame(at: 0)).maxX
                + landscape.interItemSpacing,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(landscape.itemFrame(at: 1)).maxX,
            landscapeSize.width,
            accuracy: 0.000_001
        )
    }

    func testNonPositiveColumnCountFallsBackToThreeColumns() throws {
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 4,
            uniformImageSize: CGSize(width: 1, height: 1),
            columnCount: 0
        )
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            aspectProfile: aspectProfile
        ))

        XCTAssertEqual(
            aspectProfile.columnCount,
            MobilePlayerBrowserLayout.defaultColumnCount
        )
        XCTAssertEqual(
            layout.columnCount,
            MobilePlayerBrowserLayout.defaultColumnCount
        )
        XCTAssertEqual(layout.rowCount, 2)
    }

    func testOverflowingLandscapeColumnCountReturnsNil() {
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 1,
            uniformImageSize: CGSize(width: 1, height: 1),
            columnCount: Int.max
        )

        XCTAssertNil(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 2, height: 1),
            aspectProfile: aspectProfile
        ))
    }

    func testLargeLandscapeColumnCountKeepsPrefetchArithmeticBounded() throws {
        let portraitColumnCount = Int.max / 2
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: 1
            ),
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 1,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: portraitColumnCount
            )
        ))

        XCTAssertEqual(layout.columnCount, portraitColumnCount * 2)
        XCTAssertEqual(
            layout.prefetchStride,
            MobilePlayerBrowserLayout.maximumPrefetchStride
        )
    }

    func testViewportTransitionPrefersForcedFocusAndRequiresGeometryChange() {
        let viewportSize = CGSize(width: 430, height: 932)
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 40,
            uniformImageSize: CGSize(width: 1, height: 1)
        )
        let safeAreaTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: viewportSize,
            viewportSize: viewportSize,
            needsSafeAreaRefresh: true,
            aspectProfile: aspectProfile,
            forcedTokenIndex: 12,
            focusedTokenIndex: 37
        )
        let unchangedTransition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: viewportSize,
            viewportSize: viewportSize,
            needsSafeAreaRefresh: false,
            aspectProfile: aspectProfile,
            forcedTokenIndex: 12,
            focusedTokenIndex: 37
        )

        XCTAssertEqual(
            safeAreaTransition.retainedFocusTokenIndex,
            12
        )
        XCTAssertTrue(safeAreaTransition.geometryChanged)
        XCTAssertNotNil(safeAreaTransition.layout)
        XCTAssertNil(unchangedTransition.retainedFocusTokenIndex)
        XCTAssertFalse(unchangedTransition.geometryChanged)
        XCTAssertNil(unchangedTransition.layout)
    }

    func testMissingAspectMetadataFallsBackToSquare() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: 3,
                uniformImageSize: .zero
            )
        ))

        XCTAssertEqual(
            try XCTUnwrap(layout.uniformItemSize).height,
            layout.itemWidth,
            accuracy: 0.000_001
        )
    }

    private func assertLandscapeVariableRows(
        itemImageSizes: [CGSize],
        baseColumnCount: Int,
        expectedRowRatios: [CGFloat]
    ) throws {
        let viewportSize = CGSize(width: 844, height: 390)
        let bottomInset: CGFloat = 20
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            topContentInset: 10,
            bottomContentInset: bottomInset,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemImageSizes: itemImageSizes,
                columnCount: baseColumnCount
            )
        ))
        let rowFrames = try expectedRowRatios.indices.map { rowIndex in
            try XCTUnwrap(
                layout.itemFrame(at: rowIndex * layout.columnCount)
            )
        }
        let finalItemIndex = itemImageSizes.count - 1
        let finalRowFrame = try XCTUnwrap(layout.itemFrame(at: finalItemIndex))

        XCTAssertEqual(layout.columnCount, baseColumnCount * 2)
        XCTAssertEqual(layout.rowCount, expectedRowRatios.count)
        XCTAssertFalse(layout.usesUniformRowHeights)
        XCTAssertEqual(
            layout.cachedVariableRowCount,
            expectedRowRatios.count
        )
        for (rowFrame, expectedRatio) in zip(rowFrames, expectedRowRatios) {
            XCTAssertEqual(
                rowFrame.height,
                layout.itemWidth * expectedRatio,
                accuracy: 0.000_001
            )
        }
        for rowIndex in rowFrames.indices.dropFirst() {
            XCTAssertEqual(
                rowFrames[rowIndex].minY,
                rowFrames[rowIndex - 1].maxY
                    + MobilePlayerBrowserLayout.itemSpacing,
                accuracy: 0.000_001
            )
        }
        XCTAssertEqual(
            try XCTUnwrap(
                layout.itemFrame(at: layout.columnCount - 1)
            ).maxX,
            viewportSize.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(finalRowFrame.minX, 0, accuracy: 0.000_001)
        XCTAssertEqual(
            layout.contentSize.height,
            finalRowFrame.maxY + bottomInset,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            visibleItemIndices(
                inInteriorOf: finalRowFrame,
                layout: layout
            ),
            [finalItemIndex]
        )
    }

    private func visibleItemIndices(
        inInteriorOf rowFrame: CGRect,
        layout: MobilePlayerBrowserLayout
    ) -> [Int] {
        let rowInterior = CGRect(
            x: 0,
            y: rowFrame.minY + 1,
            width: layout.contentSize.width,
            height: rowFrame.height - 2
        )
        return layout
            .candidateItemIndices(intersecting: rowInterior)
            .filter {
                layout.itemFrame(at: $0)?.intersects(rowInterior) == true
            }
    }
}
