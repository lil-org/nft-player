// ∅ 2026 lil org

import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
final class MobileCollectionBrowserGridModePresentationTests: XCTestCase {

    private final class PlaybackDisplay: MobilePlaybackControllerDisplay {
        func navigate(_ direction: PlaybackNavigationDirection) {}

        func getCurrentPagePosition() -> PlayerPagePosition {
            .initial
        }

        func flushPendingViewingProgress() {}
    }

    private struct Fixture {
        let uuid: UUID
        let controller: VerticalCollectionBrowserViewController
        let window: UIWindow
    }

    private func collectionMetadata() throws -> (
        id: String,
        internalSlug: String
    ) {
        let item = try XCTUnwrap(
            SuggestedItemsService.visibleItems.first { item in
                guard let internalSlug = item.internalSlug,
                      !internalSlug.isEmpty,
                      PlayerCollectionBrowserSupport.isAvailable(
                          forCollectionId: item.id
                      ) else {
                    return false
                }
                let tokenCount = CollectionCatalog.tokenCount(
                    specificCollectionId: item.id
                )
                return tokenCount >= 4 && tokenCount <= 512
                    && CollectionCatalog.canGenerateToken(
                        specificCollectionId: item.id,
                        tokenIndex: 0
                    )
            }
        )
        return (item.id, try XCTUnwrap(item.internalSlug))
    }

    private func makeFixture(collectionId: String) throws -> Fixture {
        let uuid = UUID()
        let display = PlaybackDisplay()
        MobilePlaybackController.shared.subscribe(
            config: MobilePlayerConfig(
                id: uuid,
                initialItemId: collectionId,
                initialTokenIndex: 0
            ),
            display: display
        )

        let controller = VerticalCollectionBrowserViewController(uuid: uuid)
        let window = UIWindow(frame: CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        ))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.setActive(true)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.gridMode, .threeColumns)
        XCTAssertNotNil(controller.currentPagePosition)
        return Fixture(uuid: uuid, controller: controller, window: window)
    }

    private func tearDownFixture(_ fixture: Fixture) {
        fixture.controller.cancelPendingDisplayPreparation()
        fixture.controller.setActive(false)
        fixture.window.isHidden = true
        fixture.window.rootViewController = nil
        MobilePlaybackController.shared.stopAndDisconnect(uuid: fixture.uuid)
    }

    private func selectGridMode(
        _ mode: MobileCollectionBrowserGridMode,
        controller: VerticalCollectionBrowserViewController
    ) async throws {
        XCTAssertTrue(controller.setGridMode(mode))
        for _ in 0..<200 {
            if controller.gridMode == mode {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Grid mode did not settle to \(mode)")
    }

    private func prepare(
        _ controller: VerticalCollectionBrowserViewController,
        using preparation: PlayerCollectionBrowsePreparation
    ) async -> MobilePlayerCollectionBrowserDisplayPreparationResult {
        await withCheckedContinuation { continuation in
            controller.prepareForDisplay(
                using: preparation,
                publishWhenStable: false
            ) {
                continuation.resume(returning: $0)
            }
        }
    }

    private func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    func testRestartCollectionPreservesTemporaryGridMode() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(
            .fiveColumns,
            controller: fixture.controller
        )

        fixture.controller.scrollToFirstItemAndPublish()
        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
    }

    func testLegacyGridModeValueIsIgnored() throws {
        let metadata = try collectionMetadata()
        let key = "iosCollectionBrowserColumnCountOverride.\(metadata.internalSlug)"
        let userDefaults = UserDefaults.standard
        let previousValue = userDefaults.object(forKey: key)
        userDefaults.set(MobileCollectionBrowserGridMode.large.rawValue, forKey: key)
        defer {
            if let previousValue {
                userDefaults.set(previousValue, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }

        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        XCTAssertEqual(fixture.controller.gridMode, .threeColumns)
    }

    func testOnePerPageRoundTripPreservesTemporaryGridModeAndFocus() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let targetPagePosition = PlayerPagePosition(position: 3)
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: targetPagePosition
            )
        )

        let result = await prepare(
            fixture.controller,
            using: preparation
        )
        XCTAssertEqual(result, .prepared)
        XCTAssertEqual(
            fixture.controller.currentPagePosition,
            targetPagePosition
        )
        try await selectGridMode(.large, controller: fixture.controller)

        fixture.controller.setActive(false)
        XCTAssertEqual(fixture.controller.gridMode, .large)
        let returnPreparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: targetPagePosition
            )
        )
        let returnResult = await prepare(
            fixture.controller,
            using: returnPreparation
        )
        XCTAssertEqual(returnResult, .prepared)
        fixture.controller.setActive(true)

        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(
            fixture.controller.currentPagePosition,
            targetPagePosition
        )
    }

    func testCancelledPreparationPreservesTemporaryModeAndPosition() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(.large, controller: fixture.controller)
        fixture.controller.setActive(false)
        let originalPosition = fixture.controller.currentPagePosition
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: .initial
            )
        )
        let completion = expectation(description: "Preparation superseded")
        var result: MobilePlayerCollectionBrowserDisplayPreparationResult?

        fixture.controller.prepareForDisplay(
            using: preparation,
            publishWhenStable: false
        ) {
            result = $0
            completion.fulfill()
        }
        XCTAssertEqual(fixture.controller.gridMode, .large)

        fixture.controller.cancelPendingDisplayPreparation()
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(fixture.controller.currentPagePosition, originalPosition)
    }

    func testPreparationPreservesTemporaryModeAndRetainsTargetFocus() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(.fiveColumns, controller: fixture.controller)
        fixture.controller.setActive(false)
        let targetPagePosition = PlayerPagePosition(position: 3)
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: targetPagePosition
            )
        )

        let result = await prepare(
            fixture.controller,
            using: preparation
        )

        XCTAssertEqual(result, .prepared)
        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertEqual(
            fixture.controller.currentPagePosition,
            targetPagePosition
        )
    }
}
