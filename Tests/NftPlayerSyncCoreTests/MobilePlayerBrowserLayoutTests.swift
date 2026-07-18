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
                    layout.itemSize(at: rowIndex * MobilePlayerBrowserLayout.columnCount)
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
        let finalRowQuery = CGRect(
            x: 0,
            y: finalItemFrame.minY + 1,
            width: layout.contentSize.width,
            height: finalItemFrame.height - 2
        )
        let finalVisibleItemIndices = layout
            .candidateItemIndices(intersecting: finalRowQuery)
            .filter {
                layout.itemFrame(at: $0)?.intersects(finalRowQuery) == true
            }
        XCTAssertEqual(finalVisibleItemIndices, [9_999])
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

        let secondRowQuery = CGRect(
            x: 0,
            y: secondRowFrame.minY + 1,
            width: layout.contentSize.width,
            height: secondRowFrame.height - 2
        )
        let visibleItemIndices = layout
            .candidateItemIndices(intersecting: secondRowQuery)
            .filter {
                layout.itemFrame(at: $0)?.intersects(secondRowQuery) == true
            }
        XCTAssertEqual(visibleItemIndices, [3, 4, 5])
    }

    func testRotationRecalculatesGeometryAndPrefetchStride() throws {
        let aspectProfile = MobilePlayerBrowserAspectProfile(
            itemCount: 12,
            uniformImageSize: CGSize(width: 210, height: 373)
        )
        let landscapeViewportSize = CGSize(width: 932, height: 430)
        let portrait = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 430, height: 932),
            topContentInset: 59,
            bottomContentInset: 34,
            aspectProfile: aspectProfile
        ))
        let landscape = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: landscapeViewportSize,
            bottomContentInset: 21,
            aspectProfile: aspectProfile
        ))
        let portraitItemSize = try XCTUnwrap(portrait.uniformItemSize)
        let landscapeItemSize = try XCTUnwrap(landscape.uniformItemSize)

        XCTAssertNotEqual(portraitItemSize, landscapeItemSize)
        XCTAssertEqual(portrait.prefetchStride, 12)
        XCTAssertEqual(landscape.prefetchStride, 3)
        XCTAssertEqual(
            MobilePlayerBrowserLayout.retainedFocusTokenIndex(
                geometryChanged: portraitItemSize != landscapeItemSize,
                forcedTokenIndex: nil,
                focusedTokenIndex: 37
            ),
            37
        )
        XCTAssertGreaterThan(landscapeItemSize.height, landscapeViewportSize.height)

        let maximumContentOffsetY = landscapeItemSize.height
            + 21
            - landscapeViewportSize.height
        XCTAssertTrue(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: CGRect(
                    x: (landscapeItemSize.width + MobilePlayerBrowserLayout.itemSpacing) * 2,
                    y: 0,
                    width: landscapeItemSize.width,
                    height: landscapeItemSize.height
                ),
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

    func testLayoutFocusRetentionPrefersForcedFocusAndRequiresGeometryChange() {
        XCTAssertEqual(
            MobilePlayerBrowserLayout.retainedFocusTokenIndex(
                geometryChanged: true,
                forcedTokenIndex: 12,
                focusedTokenIndex: 37
            ),
            12
        )
        XCTAssertNil(
            MobilePlayerBrowserLayout.retainedFocusTokenIndex(
                geometryChanged: false,
                forcedTokenIndex: 12,
                focusedTokenIndex: 37
            )
        )
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
}
