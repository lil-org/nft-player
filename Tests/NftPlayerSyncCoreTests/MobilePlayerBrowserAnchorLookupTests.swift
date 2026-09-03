import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class MobilePlayerBrowserAnchorLookupTests: XCTestCase {
    func testAnchorMatchesVisibleItemScanAcrossGridModesAndScrollOffsets() throws {
        let sizes = [
            CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390),
        ]

        for columns in [1, 3, 5, 9] {
            for size in sizes {
                let effectiveColumns = columns * (size.width > size.height ? 2 : 1)
                let itemCount = effectiveColumns * 24 + max(effectiveColumns / 2, 1)
                for variableHeights in [false, true] {
                    let profile = variableHeights
                        ? MobilePlayerBrowserAspectProfile(
                            heightToWidthRatios: (0..<itemCount).map {
                                [CGFloat(0.3), 1, 2.1, 0.6][($0 / effectiveColumns) % 4]
                            },
                            columnCount: columns
                        )
                        : MobilePlayerBrowserAspectProfile(
                            itemCount: itemCount,
                            uniformImageSize: CGSize(width: 1, height: 1),
                            columnCount: columns
                        )
                    let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
                        viewportSize: size,
                        topContentInset: 47,
                        bottomContentInset: 34,
                        aspectProfile: profile
                    ))
                    XCTAssertEqual(layout.usesUniformRowHeights, !variableHeights)

                    let maximumOffset = max(layout.contentSize.height - size.height, 0)
                    let offsets: [CGFloat] = [
                        -size.height * 2, -40, 0, 50,
                        maximumOffset / 2, maximumOffset,
                        maximumOffset + 40, layout.contentSize.height + 50,
                    ]
                    for offset in offsets {
                        for horizontalInset in [CGFloat(0), size.width * 0.2] {
                            let viewport = CGRect(
                                x: horizontalInset,
                                y: offset,
                                width: size.width - horizontalInset * 2,
                                height: size.height
                            )
                            let points = [
                                CGPoint(x: viewport.midX, y: viewport.midY),
                                CGPoint(x: -20, y: viewport.minY),
                                CGPoint(x: size.width + 20, y: viewport.maxY),
                            ]
                            for point in points {
                                XCTAssertEqual(
                                    layout.anchorItemIndex(near: point, in: viewport),
                                    scannedAnchor(in: layout, near: point, viewport: viewport),
                                    "columns=\(columns), size=\(size), variable=\(variableHeights), viewport=\(viewport), point=\(point)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testRowCenterTiesRespectHorizontalDistanceAndLowerIndex() throws {
        for variableHeights in [false, true] {
            let profile = variableHeights
                ? MobilePlayerBrowserAspectProfile(
                    heightToWidthRatios: Array(repeating: CGFloat(1), count: 5)
                        + Array(repeating: CGFloat(2), count: 5)
                        + [0.5],
                    columnCount: 5
                )
                : MobilePlayerBrowserAspectProfile(
                    itemCount: 11,
                    uniformImageSize: CGSize(width: 1, height: 1),
                    columnCount: 5
                )
            let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
                viewportSize: CGSize(width: 508, height: 1_000),
                displayScale: 1,
                aspectProfile: profile
            ))
            let fullRowFirst = try XCTUnwrap(layout.itemFrame(at: 5))
            let fullRowLast = try XCTUnwrap(layout.itemFrame(at: 9))
            let finalItem = try XCTUnwrap(layout.itemFrame(at: 10))
            let tiedY = (fullRowFirst.midY + finalItem.midY) / 2
            let viewport = CGRect(origin: .zero, size: layout.contentSize)

            XCTAssertEqual(
                layout.anchorItemIndex(
                    near: CGPoint(x: fullRowLast.midX, y: tiedY),
                    in: viewport
                ),
                9
            )
            XCTAssertEqual(
                layout.anchorItemIndex(
                    near: CGPoint(x: finalItem.midX, y: tiedY),
                    in: viewport
                ),
                5
            )
            XCTAssertEqual(
                layout.anchorItemIndex(
                    near: CGPoint(x: fullRowLast.midX, y: tiedY + 0.001),
                    in: viewport
                ),
                10
            )
        }
    }

    func testColumnCenterTiePrefersLowerVisibleIndex() throws {
        let layout = try makeLayout(itemCount: 10)
        let first = try XCTUnwrap(layout.itemFrame(at: 0))
        let second = try XCTUnwrap(layout.itemFrame(at: 1))
        let point = CGPoint(x: (first.midX + second.midX) / 2, y: first.midY)

        XCTAssertEqual(
            layout.anchorItemIndex(
                near: point,
                in: CGRect(origin: .zero, size: layout.contentSize)
            ),
            0
        )
        XCTAssertEqual(
            layout.anchorItemIndex(near: point, in: second.insetBy(dx: 1, dy: 1)),
            1
        )
    }

    func testAnchorRequiresAnItemIntersectingTheViewport() throws {
        let layout = try makeLayout(itemCount: 6)
        let first = try XCTUnwrap(layout.itemFrame(at: 0))
        let final = try XCTUnwrap(layout.itemFrame(at: 5))
        let point = CGPoint(x: first.midX, y: first.midY)
        let emptyViewports = [
            CGRect.zero,
            CGRect(x: 0, y: 0, width: 0, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 0),
            CGRect(x: 0, y: -200, width: 508, height: 100),
            CGRect(x: 0, y: final.maxY + 1, width: 508, height: 100),
            CGRect(x: 600, y: 0, width: 100, height: 100),
            CGRect(x: first.maxX + 0.5, y: 0, width: 1, height: first.height),
            CGRect(x: 0, y: first.maxY + 0.5, width: 508, height: 1),
            CGRect(x: final.maxX + 1, y: final.minY + 1, width: 100, height: 50),
        ]

        for viewport in emptyViewports {
            XCTAssertNil(layout.anchorItemIndex(near: point, in: viewport), "\(viewport)")
        }
        XCTAssertEqual(
            layout.anchorItemIndex(
                near: CGPoint(x: first.midX, y: -100),
                in: CGRect(x: 0, y: -100, width: 508, height: 101)
            ),
            0
        )
        XCTAssertEqual(
            layout.anchorItemIndex(
                near: CGPoint(x: 508, y: final.maxY + 100),
                in: CGRect(x: 0, y: final.maxY - 1, width: 508, height: 101)
            ),
            5
        )
        XCTAssertNil(try makeLayout(itemCount: 0).anchorItemIndex(
            near: point,
            in: CGRect(x: 0, y: 0, width: 508, height: 1_000)
        ))
    }

    func testAnchorRejectsNonfiniteGeometry() throws {
        let layout = try makeLayout(itemCount: 10)
        let viewport = CGRect(origin: .zero, size: layout.contentSize)
        for point in [
            CGPoint(x: CGFloat.nan, y: 50),
            CGPoint(x: 50, y: CGFloat.infinity),
            CGPoint(x: -CGFloat.infinity, y: 50),
        ] {
            XCTAssertNil(layout.anchorItemIndex(near: point, in: viewport))
        }
        for invalidViewport in [
            CGRect.null,
            CGRect.infinite,
            CGRect(x: CGFloat.nan, y: 0, width: 508, height: 100),
            CGRect(x: 0, y: CGFloat.infinity, width: 508, height: 100),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
            CGRect(x: 0, y: 0, width: 508, height: CGFloat.nan),
        ] {
            XCTAssertNil(layout.anchorItemIndex(
                near: CGPoint(x: 50, y: 50),
                in: invalidViewport
            ))
        }
    }

    private func makeLayout(itemCount: Int) throws -> MobilePlayerBrowserLayout {
        try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: CGSize(width: 508, height: 1_000),
            displayScale: 1,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: itemCount,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: 5
            )
        ))
    }

    private func scannedAnchor(
        in layout: MobilePlayerBrowserLayout,
        near point: CGPoint,
        viewport: CGRect
    ) -> Int? {
        let items = (0..<layout.itemCount).compactMap { index -> PlayerCollectionVisibleItem? in
            guard let frame = layout.itemFrame(at: index), frame.intersects(viewport) else {
                return nil
            }
            return PlayerCollectionVisibleItem(index: index, frame: frame)
        }
        return PlayerCollectionScrollPolicy.anchorIndex(
            visibleItems: items,
            focalPoint: point,
            itemCount: layout.itemCount
        )
    }
}
