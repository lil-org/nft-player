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
            sampledImageSizes: [CGSize(width: 210, height: 373)]
        ))

        XCTAssertEqual(
            layout.itemSize.width * 3 + MobilePlayerBrowserLayout.itemSpacing * 2,
            viewportWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            layout.itemSize.height,
            layout.itemSize.width * 373 / 210,
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
            sampledImageSizes: [CGSize(width: 512, height: 512)]
        ))

        XCTAssertEqual(
            layout.itemSize.width * 3 + MobilePlayerBrowserLayout.itemSpacing * 2,
            viewportWidth,
            accuracy: 0.000_001
        )
        XCTAssertEqual(layout.itemSize.height, layout.itemSize.width, accuracy: 0.000_001)
        XCTAssertEqual(layout.visibleRowCount, 6)
        XCTAssertEqual(layout.prefetchStride, 15)
    }

    func testMixedAspectSamplesUseTallestWidthScaledRow() throws {
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 390, height: 844),
            topContentInset: 47,
            bottomContentInset: 34,
            sampledImageSizes: [
                CGSize(width: 2, height: 1),
                CGSize(width: 1, height: 1),
                CGSize(width: 1, height: 2),
            ]
        ))

        XCTAssertEqual(layout.itemSize.height, layout.itemSize.width * 2, accuracy: 0.000_001)
        XCTAssertEqual(layout.visibleRowCount, 3)
        XCTAssertEqual(layout.prefetchStride, 9)
    }

    func testRotationRecalculatesGeometryAndPrefetchStride() throws {
        let samples = [CGSize(width: 210, height: 373)]
        let landscapeViewportSize = CGSize(width: 932, height: 430)
        let portrait = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 430, height: 932),
            topContentInset: 59,
            bottomContentInset: 34,
            sampledImageSizes: samples
        ))
        let landscape = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: landscapeViewportSize,
            bottomContentInset: 21,
            sampledImageSizes: samples
        ))

        XCTAssertNotEqual(portrait.itemSize, landscape.itemSize)
        XCTAssertEqual(portrait.prefetchStride, 12)
        XCTAssertEqual(landscape.prefetchStride, 3)
        XCTAssertEqual(
            MobilePlayerBrowserLayout.retainedFocusTokenIndex(
                geometryChanged: portrait.itemSize != landscape.itemSize,
                forcedTokenIndex: nil,
                focusedTokenIndex: 37
            ),
            37
        )
        XCTAssertGreaterThan(landscape.itemSize.height, landscapeViewportSize.height)

        let maximumContentOffsetY = landscape.itemSize.height
            + 21
            - landscapeViewportSize.height
        XCTAssertTrue(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: CGRect(
                    x: (landscape.itemSize.width + MobilePlayerBrowserLayout.itemSpacing) * 2,
                    y: 0,
                    width: landscape.itemSize.width,
                    height: landscape.itemSize.height
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
            sampledImageSizes: []
        ))

        XCTAssertEqual(layout.itemSize.height, layout.itemSize.width, accuracy: 0.000_001)
    }
}
