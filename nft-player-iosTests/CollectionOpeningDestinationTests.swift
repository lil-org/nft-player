import XCTest
@testable import nft_player_ios

nonisolated final class CollectionOpeningDestinationTests: XCTestCase {}

@MainActor
extension CollectionOpeningDestinationTests {
    func testUniformCatalogMetadataProvidesBrowserPlaceholders() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "fidenza"))
        let destination = CollectionOpeningDestination(collectionId: item.id)

        XCTAssertEqual(destination.title, item.name)
        XCTAssertEqual(destination.itemCount, item.bundledTokenCount)
        XCTAssertEqual(destination.uniformAspectRatio, item.aspectRatio)
        XCTAssertEqual(destination.layout, .browser(columnCount: 3))

        let frames = destination.placeholderFrames(
            viewportSize: CGSize(width: 390, height: 844),
            displayScale: 3
        )
        XCTAssertFalse(frames.isEmpty)
        XCTAssertLessThan(frames.count, 30)
        let ratio = try XCTUnwrap(item.aspectRatio).value
        for frame in frames {
            XCTAssertEqual(frame.width / frame.height, ratio, accuracy: 0.0001)
        }
    }

    func testVariableCatalogRatioDoesNotProduceMisleadingPlaceholders() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "maps_for_grief"))
        XCTAssertNotNil(item.aspectRatio)
        XCTAssertEqual(item.hasUniformAspectRatio, false)
        let destination = CollectionOpeningDestination(collectionId: item.id)

        XCTAssertNil(destination.uniformAspectRatio)
        XCTAssertTrue(destination.placeholderFrames(
            viewportSize: CGSize(width: 390, height: 844),
            displayScale: 3
        ).isEmpty)
    }

    func testUnknownCollectionRemainsBlank() {
        let destination = CollectionOpeningDestination(collectionId: "missing-collection")

        XCTAssertEqual(destination.itemCount, 0)
        XCTAssertNil(destination.uniformAspectRatio)
        XCTAssertTrue(destination.placeholderFrames(
            viewportSize: CGSize(width: 390, height: 844),
            displayScale: 3
        ).isEmpty)
    }

    func testWidgetDestinationUsesOneCenteredFittedPlaceholder() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "fidenza"))
        let destination = CollectionOpeningDestination(collectionId: item.id, opensToken: true)
        let viewportSize = CGSize(width: 800, height: 400)
        let frames = destination.placeholderFrames(viewportSize: viewportSize, displayScale: 2)

        XCTAssertEqual(destination.layout, .artwork)
        XCTAssertEqual(frames.count, 1)
        let frame = try XCTUnwrap(frames.first)
        XCTAssertEqual(frame.midX, viewportSize.width / 2, accuracy: 0.0001)
        XCTAssertEqual(frame.midY, viewportSize.height / 2, accuracy: 0.0001)
        XCTAssertEqual(frame.height, viewportSize.height, accuracy: 0.0001)
        XCTAssertEqual(frame.width / frame.height, 5.0 / 6.0, accuracy: 0.0001)
    }

    func testLargeCollectionOnlyDrawsVisiblePlaceholdersAroundSavedPosition() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "chromie_squiggle"))
        let destination = CollectionOpeningDestination(collectionId: item.id, initialTokenIndex: 5_000)
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let frames = destination.placeholderFrames(viewportSize: viewport.size, displayScale: 3)

        XCTAssertEqual(destination.initialTokenIndex, 5_000)
        XCTAssertGreaterThan(destination.itemCount, 5_000)
        XCTAssertFalse(frames.isEmpty)
        XCTAssertLessThan(frames.count, 50)
        XCTAssertTrue(frames.allSatisfy { $0.intersects(viewport) })
    }

    func testRestorationIndexIsClampedAndEmptyViewportDrawsNothing() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "fidenza"))
        let beforeStart = CollectionOpeningDestination(collectionId: item.id, initialTokenIndex: -1)
        let afterEnd = CollectionOpeningDestination(collectionId: item.id, initialTokenIndex: Int.max)

        XCTAssertEqual(beforeStart.initialTokenIndex, 0)
        XCTAssertEqual(afterEnd.initialTokenIndex, afterEnd.itemCount - 1)
        XCTAssertTrue(afterEnd.placeholderFrames(viewportSize: .zero, displayScale: 3).isEmpty)
        XCTAssertNotEqual(beforeStart.id, afterEnd.id)
        let restored = beforeStart.withInitialTokenIndex(40)
        XCTAssertEqual(restored.id, beforeStart.id)
        XCTAssertEqual(restored.initialTokenIndex, 40)
    }

    func testSavedPositionNearGridEdgesUsesBrowserFocalRestoration() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "fidenza"))
        let size = CGSize(width: 390, height: 844)
        let topInset: CGFloat = 62
        let bottomInset: CGFloat = 34
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: size,
            displayScale: 3,
            topContentInset: topInset,
            bottomContentInset: bottomInset,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: try XCTUnwrap(item.bundledTokenCount),
                uniformImageSize: try XCTUnwrap(item.aspectRatio).size
            )
        ))
        let firstFrame = try XCTUnwrap(layout.itemFrame(at: 0))
        let lastFrame = try XCTUnwrap(layout.itemFrame(at: layout.itemCount - 1))
        let previousRow = try XCTUnwrap(layout.itemFrame(at: layout.itemCount - 4))
        let focalGeometry = try XCTUnwrap(PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: 0,
            maximumOffsetY: layout.contentSize.height - size.height,
            viewportHeight: size.height,
            viewportCenterX: size.width / 2,
            firstItemCenter: CGPoint(x: firstFrame.midX, y: firstFrame.midY),
            lastItemCenter: CGPoint(x: lastFrame.midX, y: lastFrame.midY),
            lastRowFocalEntryY: (previousRow.midY + lastFrame.midY) / 2
        ))
        for index in [3, layout.itemCount - 4] {
            let destination = CollectionOpeningDestination(collectionId: item.id, initialTokenIndex: index)
            let frame = try XCTUnwrap(layout.itemFrame(at: index))
            let offset = focalGeometry.contentOffsetY(anchoringFocalY: frame.midY)
            let frames = destination.placeholderFrames(
                viewportSize: size,
                displayScale: 3,
                topContentInset: topInset,
                bottomContentInset: bottomInset
            )
            XCTAssertTrue(frames.contains(frame.offsetBy(dx: 0, dy: -offset)))
        }
        let start = CollectionOpeningDestination(collectionId: item.id)
        XCTAssertEqual(start.placeholderFrames(
            viewportSize: size,
            displayScale: 3,
            topContentInset: topInset,
            bottomContentInset: bottomInset
        ).first?.minY, topInset)
    }
}
