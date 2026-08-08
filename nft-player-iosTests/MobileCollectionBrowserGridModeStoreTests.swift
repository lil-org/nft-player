// ∅ 2026 lil org

import Foundation
import XCTest
@testable import nft_player_ios

final class MobileCollectionBrowserGridModeStoreTests: XCTestCase {

    func testKnownLegacyTwoColumnCatalogUsesThreeColumnFirstRunDefault() throws {
        let suiteName = "MobileCollectionBrowserGridModeStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let item = try XCTUnwrap(
            SuggestedItemsService.visibleItems.first {
                $0.iosCollectionBrowserColumnCount == 2
                    && $0.internalSlug?.isEmpty == false
            }
        )

        XCTAssertEqual(
            MobileCollectionBrowserGridModeStore.gridMode(
                specificCollectionId: item.id,
                userDefaults: userDefaults
            ),
            .threeColumns
        )
        XCTAssertEqual(
            CollectionCatalog.desktopCollectionBrowseColumnCount(
                specificCollectionId: item.id
            ),
            2
        )
    }

    func testUnknownCollectionUsesThreeColumnFirstRunDefault() throws {
        let suiteName = "MobileCollectionBrowserGridModeStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            MobileCollectionBrowserGridModeStore.gridMode(
                specificCollectionId: "missing-grid-mode-test-collection",
                userDefaults: userDefaults
            ),
            .threeColumns
        )
    }

    func testUnknownCollectionUsesThreeColumnDesktopDefault() {
        XCTAssertEqual(
            CollectionCatalog.desktopCollectionBrowseColumnCount(
                specificCollectionId: "missing-grid-mode-test-collection"
            ),
            MobilePlayerBrowserLayout.defaultColumnCount
        )
        XCTAssertEqual(MobileCollectionBrowserGridMode.defaultMode, .threeColumns)
    }
}
