// ∅ 2026 lil org

import Foundation
import XCTest
@testable import NftPlayerSyncCore

final class CollectionBrowserConfigurationTests: XCTestCase {

    func testGridModesExposeSupportedColumnCounts() {
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.allCases,
            [.large, .threeColumns, .fiveColumns]
        )
        XCTAssertEqual(MobileCollectionBrowserGridMode.large.columnCount, 1)
        XCTAssertEqual(MobileCollectionBrowserGridMode.threeColumns.columnCount, 3)
        XCTAssertEqual(MobileCollectionBrowserGridMode.fiveColumns.columnCount, 5)
        XCTAssertEqual(MobileCollectionBrowserGridMode.defaultMode, .threeColumns)
    }

    func testGridModeImageQualityRequiresLargeImagesOnlyForTheLargeGrid() {
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.large.requiredImageQuality,
            .large
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.threeColumns.requiredImageQuality,
            .thumbnail
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.fiveColumns.requiredImageQuality,
            .thumbnail
        )
    }

    func testGridModePreferencesUseThreeColumnsForMissingAndInvalidValues() throws {
        let suiteName = "CollectionBrowserConfigurationTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: "missing"
            ),
            .threeColumns
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: ""
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
                internalSlug: "invalid-override"
            ),
            .threeColumns
        )
        userDefaults.set(true, forKey: invalidOverrideKey)
        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: "invalid-override"
            ),
            .threeColumns
        )
        userDefaults.set(3.5, forKey: invalidOverrideKey)
        XCTAssertEqual(
            MobileCollectionBrowserGridModePreferences.gridMode(
                userDefaults: userDefaults,
                internalSlug: "invalid-override"
            ),
            .threeColumns
        )
        XCTAssertNil(
            MobileCollectionBrowserGridModePreferences.userDefaultsKey(
                internalSlug: ""
            )
        )
    }

    func testGridModePreferencesPreserveSupportedAndLegacyOverrides() throws {
        let suiteName = "CollectionBrowserConfigurationTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let terraformsKey = try XCTUnwrap(
            MobileCollectionBrowserGridModePreferences.userDefaultsKey(
                internalSlug: "terraforms"
            )
        )
        XCTAssertEqual(
            terraformsKey,
            "iosCollectionBrowserColumnCountOverride.terraforms"
        )

        let storedCases: [(Int, MobileCollectionBrowserGridMode)] = [
            (1, .large),
            (2, .threeColumns),
            (3, .threeColumns),
            (4, .fiveColumns),
            (5, .fiveColumns)
        ]
        for (storedColumnCount, expectedMode) in storedCases {
            userDefaults.set(storedColumnCount, forKey: terraformsKey)
            XCTAssertEqual(
                MobileCollectionBrowserGridModePreferences.gridMode(
                    userDefaults: userDefaults,
                    internalSlug: "terraforms"
                ),
                expectedMode
            )
        }

        for mode in MobileCollectionBrowserGridMode.allCases {
            MobileCollectionBrowserGridModePreferences.save(
                gridMode: mode,
                userDefaults: userDefaults,
                internalSlug: "terraforms"
            )
            XCTAssertEqual(
                MobileCollectionBrowserGridModePreferences.gridMode(
                    userDefaults: userDefaults,
                    internalSlug: "terraforms"
                ),
                mode
            )
        }
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

    func testLargeImageLoadPolicyOnlyPromotesLocalLargeImagesWhenAllowed() {
        XCTAssertFalse(
            CollectionBrowseImageLoadPolicy.allowsLocalLargeImagePromotion(
                requiredQuality: .thumbnail,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: true,
                allowsPromotion: false
            )
        )
        XCTAssertTrue(
            CollectionBrowseImageLoadPolicy.allowsLocalLargeImagePromotion(
                requiredQuality: .thumbnail,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: true,
                allowsPromotion: true
            )
        )
        XCTAssertFalse(
            CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                requiredQuality: .thumbnail,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: true,
                allowsLocalPromotion: false
            )
        )
        XCTAssertTrue(
            CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                requiredQuality: .thumbnail,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: true,
                allowsLocalPromotion: true
            )
        )
        XCTAssertFalse(
            CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                requiredQuality: .thumbnail,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: false,
                allowsLocalPromotion: true
            )
        )
        XCTAssertTrue(
            CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                requiredQuality: .large,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: false,
                allowsLocalPromotion: false
            )
        )
        XCTAssertTrue(
            CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                requiredQuality: .thumbnail,
                hasDistinctLargeImage: false,
                largeImageIsLocallyAvailable: false,
                allowsLocalPromotion: false
            )
        )

        var checkedLocalAvailability = false
        func localAvailability() -> Bool {
            checkedLocalAvailability = true
            return true
        }
        XCTAssertFalse(
            CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                requiredQuality: .thumbnail,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: localAvailability(),
                allowsLocalPromotion: false
            )
        )
        XCTAssertFalse(checkedLocalAvailability)
    }

    func testSnapshotUpdateRecognizesOnlyThePublishedSettledTokenAsAnEcho() {
        XCTAssertTrue(
            CollectionBrowseSnapshotUpdatePolicy.isSettledPositionEcho(
                currentCollectionId: "collection",
                currentItemCount: 100,
                updatedCollectionId: "collection",
                updatedItemCount: 100,
                updatedInitialTokenIndex: 42,
                lastPublishedTokenIndex: 42
            )
        )
        XCTAssertFalse(
            CollectionBrowseSnapshotUpdatePolicy.isSettledPositionEcho(
                currentCollectionId: "collection",
                currentItemCount: 100,
                updatedCollectionId: "collection",
                updatedItemCount: 100,
                updatedInitialTokenIndex: 43,
                lastPublishedTokenIndex: 42
            )
        )
        XCTAssertFalse(
            CollectionBrowseSnapshotUpdatePolicy.isSettledPositionEcho(
                currentCollectionId: "collection",
                currentItemCount: 100,
                updatedCollectionId: "other-collection",
                updatedItemCount: 100,
                updatedInitialTokenIndex: 42,
                lastPublishedTokenIndex: 42
            )
        )
    }
}
