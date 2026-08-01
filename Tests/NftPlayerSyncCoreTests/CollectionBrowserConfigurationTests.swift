// ∅ 2026 lil org

import Foundation
import XCTest
@testable import NftPlayerSyncCore

final class CollectionBrowserConfigurationTests: XCTestCase {

    func testGridModeCycleAndDestinationImages() {
        XCTAssertEqual(MobileCollectionBrowserGridMode.twoColumns.next, .large)
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.twoColumns.nextSystemImageName,
            "rectangle.grid.1x2"
        )
        XCTAssertEqual(MobileCollectionBrowserGridMode.large.next, .threeColumns)
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.large.nextSystemImageName,
            "square.grid.3x2"
        )
        XCTAssertEqual(MobileCollectionBrowserGridMode.threeColumns.next, .twoColumns)
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.threeColumns.nextSystemImageName,
            "square.grid.2x2"
        )
        XCTAssertFalse(MobileCollectionBrowserGridMode.twoColumns.requiresLargeImage)
        XCTAssertTrue(MobileCollectionBrowserGridMode.large.requiresLargeImage)
        XCTAssertFalse(MobileCollectionBrowserGridMode.threeColumns.requiresLargeImage)
    }

    func testGridModeImageQualityUsesLargeImagesWhenThreeColumnCollectionsUseTwoColumns() {
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.twoColumns.requiredImageQuality(
                defaultGridMode: .threeColumns
            ),
            .large
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.twoColumns.requiredImageQuality(
                defaultGridMode: .twoColumns
            ),
            .thumbnail
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.threeColumns.requiredImageQuality(
                defaultGridMode: .threeColumns
            ),
            .thumbnail
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.large.requiredImageQuality(
                defaultGridMode: .twoColumns
            ),
            .large
        )
    }

    func testGridModePreferencesPreserveLegacyOverridesPerInternalSlug() throws {
        let suiteName = "CollectionBrowserConfigurationTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let terraformsKey = try XCTUnwrap(
            MobileCollectionBrowserGridModePreferences.userDefaultsKey(
                internalSlug: "terraforms"
            )
        )
        userDefaults.set(2, forKey: terraformsKey)

        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: "terraforms",
                defaultGridMode: .threeColumns
            ),
            .twoColumns
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: "another-collection",
                defaultGridMode: .threeColumns
            ),
            .threeColumns
        )
        let invalidOverrideKey = try XCTUnwrap(
            MobileCollectionBrowserGridModePreferences.userDefaultsKey(
                internalSlug: "invalid-override"
            )
        )
        userDefaults.set(99, forKey: invalidOverrideKey)
        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: "invalid-override",
                defaultGridMode: .twoColumns
            ),
            .twoColumns
        )

        MobileCollectionBrowserGridModePreferences.save(
            gridMode: .large,
            userDefaults: userDefaults,
            internalSlug: "terraforms"
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: "terraforms",
                defaultGridMode: .threeColumns
            ),
            .large
        )
        XCTAssertNil(
            MobileCollectionBrowserGridModePreferences.userDefaultsKey(
                internalSlug: ""
            )
        )
    }

    func testMidImageURLMappingUsesFinalThumbsDirectory() throws {
        let terraformsThumbnail = try XCTUnwrap(
            URL(string: "https://cdn.lil.org/player/terraforms/thumbs/1.webp")
        )
        let bundledThumbnail = try XCTUnwrap(
            URL(string: "https://cdn.lil.org/player/example-generative/thumbs/42.webp")
        )
        let standardThumbnail = try XCTUnwrap(
            URL(string: "https://cdn.example.com/nft/collection/thumbs/0001.webp")
        )

        XCTAssertEqual(
            CollectionBrowseImageURLMapping.midURL(for: terraformsThumbnail),
            URL(string: "https://cdn.lil.org/player/terraforms/mid/1.webp")
        )
        XCTAssertEqual(
            CollectionBrowseImageURLMapping.midURL(for: bundledThumbnail),
            URL(string: "https://cdn.lil.org/player/example-generative/mid/42.webp")
        )
        XCTAssertEqual(
            CollectionBrowseImageURLMapping.midURL(for: standardThumbnail),
            URL(string: "https://cdn.example.com/nft/collection/mid/0001.webp")
        )
    }

    func testMidImageURLMappingRejectsUnsafeOrUnsupportedURLs() throws {
        let unsupportedURLs = [
            "file:///collection/thumbs/1.webp",
            "https://cdn.lil.org/nft/card_nft_2/fronts_1400/0001.webp",
            "https://cdn.lil.org/nft/poncho_drifella/fronts/1.webp",
            "https://cdn.example.com/collection/thumbs/1.png",
            "https://cdn.example.com/collection/thumbs/1.webp?version=2",
            "https://cdn.example.com/collection/thumbs/1.webp#preview",
            "https://cdn.example.com/collection/thumbs/nested%2F1.webp",
        ]

        for value in unsupportedURLs {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(CollectionBrowseImageURLMapping.midURL(for: url), value)
        }
    }

    func testImageQualityNeverAllowsLateThumbnailToReplaceLargeImage() {
        XCTAssertTrue(CollectionBrowseImageQuality.thumbnail.canReplace(nil))
        XCTAssertTrue(CollectionBrowseImageQuality.large.canReplace(.thumbnail))
        XCTAssertTrue(CollectionBrowseImageQuality.large.canReplace(.large))
        XCTAssertFalse(CollectionBrowseImageQuality.thumbnail.canReplace(.large))
    }

    func testCacheWindowKeepsDisplayedLargeImagesWithoutRedundantDownloads() {
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .thumbnail,
                isDisplayingLargeImage: true,
                largeImageIsLocallyAvailable: true
            ),
            .locallyAvailableLarge
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .thumbnail,
                isDisplayingLargeImage: true,
                largeImageIsLocallyAvailable: false
            ),
            .omitSatisfiedToken
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .thumbnail,
                isDisplayingLargeImage: false,
                largeImageIsLocallyAvailable: true
            ),
            .requestedQuality
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .large,
                isDisplayingLargeImage: true,
                largeImageIsLocallyAvailable: false
            ),
            .requestedQuality
        )
    }
}
