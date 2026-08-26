// ∅ 2026 lil org

import Foundation
import XCTest
@testable import NftPlayerSyncCore

final class CollectionBrowserConfigurationTests: XCTestCase {

    func testGridModesExposeSupportedColumnCounts() {
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.allCases,
            [.large, .threeColumns, .fiveColumns, .nineColumns]
        )
        XCTAssertEqual(MobileCollectionBrowserGridMode.large.columnCount, 1)
        XCTAssertEqual(MobileCollectionBrowserGridMode.threeColumns.columnCount, 3)
        XCTAssertEqual(MobileCollectionBrowserGridMode.fiveColumns.columnCount, 5)
        XCTAssertEqual(MobileCollectionBrowserGridMode.nineColumns.columnCount, 9)
        XCTAssertEqual(MobileCollectionBrowserGridMode.defaultMode, .threeColumns)
    }

    func testGridModesSelectTheirDesignatedImageQuality() {
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
            .smallThumbnail
        )
        XCTAssertEqual(
            MobileCollectionBrowserGridMode.nineColumns.requiredImageQuality,
            .smallestThumbnail
        )
        XCTAssertTrue(
            MobileCollectionBrowserGridMode.large.allowsLocalLargeImageUpgrade
        )
        XCTAssertTrue(
            MobileCollectionBrowserGridMode.threeColumns
                .allowsLocalLargeImageUpgrade
        )
        XCTAssertFalse(
            MobileCollectionBrowserGridMode.fiveColumns
                .allowsLocalLargeImageUpgrade
        )
        XCTAssertFalse(
            MobileCollectionBrowserGridMode.nineColumns
                .allowsLocalLargeImageUpgrade
        )
    }

    func testSizedThumbnailURLMappingAddsWidthAfterThumbsDirectory() throws {
        XCTAssertEqual(CollectionBrowseThumbnailWidth.width140.rawValue, 140)
        XCTAssertEqual(CollectionBrowseThumbnailWidth.width260.rawValue, 260)
        let mappings = [
            (
                source: "https://cdn.lil.org/player/terraforms/thumbs/1.webp",
                tokenIndex: 0,
                width140: "https://cdn.lil.org/player/terraforms/thumbs/140/0.webp",
                width260: "https://cdn.lil.org/player/terraforms/thumbs/260/0.webp"
            ),
            (
                source: "https://cdn.lil.org/player/example-generative/thumbs/42.webp",
                tokenIndex: 42,
                width140: "https://cdn.lil.org/player/example-generative/thumbs/140/42.webp",
                width260: "https://cdn.lil.org/player/example-generative/thumbs/260/42.webp"
            ),
            (
                source: "https://cdn.example.com/nft/collection/thumbs/0001.webp",
                tokenIndex: 0,
                width140: "https://cdn.example.com/nft/collection/thumbs/140/0.webp",
                width260: "https://cdn.example.com/nft/collection/thumbs/260/0.webp"
            ),
        ]

        for mapping in mappings {
            let url = try XCTUnwrap(URL(string: mapping.source))
            XCTAssertEqual(
                CollectionBrowseImageURLMapping.thumbnailURL(
                    for: url,
                    tokenIndex: mapping.tokenIndex,
                    width: .width140
                ),
                URL(string: mapping.width140)
            )
            XCTAssertEqual(
                CollectionBrowseImageURLMapping.thumbnailURL(
                    for: url,
                    tokenIndex: mapping.tokenIndex,
                    width: .width260
                ),
                URL(string: mapping.width260)
            )
            XCTAssertEqual(
                CollectionBrowseImageURLMapping.smallThumbnailURL(
                    for: url,
                    tokenIndex: mapping.tokenIndex
                ),
                URL(string: mapping.width260)
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

    func testImageURLMappingsRejectUnsafeOrUnsupportedURLs() throws {
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
            XCTAssertNil(
                CollectionBrowseImageURLMapping.smallThumbnailURL(
                    for: url,
                    tokenIndex: 0
                ),
                value
            )
            for width in CollectionBrowseThumbnailWidth.allCases {
                XCTAssertNil(
                    CollectionBrowseImageURLMapping.thumbnailURL(
                        for: url,
                        tokenIndex: 0,
                        width: width
                    ),
                    value
                )
            }
        }
    }

    func testSizedThumbnailURLMappingRejectsNegativeTokenIndices() throws {
        let thumbnailURL = try XCTUnwrap(URL(
            string: "https://cdn.example.com/collection/thumbs/1.webp"
        ))

        XCTAssertNil(CollectionBrowseImageURLMapping.smallThumbnailURL(
            for: thumbnailURL,
            tokenIndex: -1
        ))
        for width in CollectionBrowseThumbnailWidth.allCases {
            XCTAssertNil(CollectionBrowseImageURLMapping.thumbnailURL(
                for: thumbnailURL,
                tokenIndex: -1,
                width: width
            ))
        }
    }

    func testImageQualityReplacementFollowsResolutionOrder() {
        XCTAssertTrue(CollectionBrowseImageQuality.smallestThumbnail.canReplace(nil))
        XCTAssertTrue(CollectionBrowseImageQuality.smallThumbnail.canReplace(nil))
        XCTAssertTrue(CollectionBrowseImageQuality.thumbnail.canReplace(nil))
        XCTAssertTrue(
            CollectionBrowseImageQuality.smallThumbnail.canReplace(
                .smallestThumbnail
            )
        )
        XCTAssertTrue(
            CollectionBrowseImageQuality.thumbnail.canReplace(.smallThumbnail)
        )
        XCTAssertTrue(CollectionBrowseImageQuality.large.canReplace(.thumbnail))
        XCTAssertTrue(CollectionBrowseImageQuality.large.canReplace(.large))
        XCTAssertFalse(
            CollectionBrowseImageQuality.smallestThumbnail.canReplace(
                .smallThumbnail
            )
        )
        XCTAssertFalse(
            CollectionBrowseImageQuality.smallThumbnail.canReplace(.thumbnail)
        )
        XCTAssertFalse(CollectionBrowseImageQuality.thumbnail.canReplace(.large))
        XCTAssertTrue(CollectionBrowseImageQuality.smallestThumbnail.isDenseGridThumbnail)
        XCTAssertTrue(CollectionBrowseImageQuality.smallThumbnail.isDenseGridThumbnail)
        XCTAssertFalse(CollectionBrowseImageQuality.thumbnail.isDenseGridThumbnail)
    }

    func testCacheWindowKeepsDisplayedLargeImagesWithoutRedundantDownloads() {
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .smallThumbnail,
                isDisplayingSatisfyingThumbnail: true,
                isDisplayingLargeImage: false,
                largeImageIsLocallyAvailable: false
            ),
            .omitSatisfiedToken
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .smallestThumbnail,
                isDisplayingSatisfyingThumbnail: true,
                isDisplayingLargeImage: false,
                largeImageIsLocallyAvailable: false
            ),
            .omitSatisfiedToken
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .smallThumbnail,
                isDisplayingSatisfyingThumbnail: false,
                isDisplayingLargeImage: true,
                largeImageIsLocallyAvailable: true
            ),
            .locallyAvailableLarge
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .thumbnail,
                isDisplayingSatisfyingThumbnail: false,
                isDisplayingLargeImage: true,
                largeImageIsLocallyAvailable: true
            ),
            .locallyAvailableLarge
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .thumbnail,
                isDisplayingSatisfyingThumbnail: false,
                isDisplayingLargeImage: true,
                largeImageIsLocallyAvailable: false
            ),
            .omitSatisfiedToken
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .thumbnail,
                isDisplayingSatisfyingThumbnail: true,
                isDisplayingLargeImage: false,
                largeImageIsLocallyAvailable: true
            ),
            .requestedQuality
        )
        XCTAssertEqual(
            CollectionBrowseImageWindowSelection.resolve(
                requiredQuality: .large,
                isDisplayingSatisfyingThumbnail: false,
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
                requiredQuality: .smallThumbnail,
                hasDistinctLargeImage: true,
                largeImageIsLocallyAvailable: true,
                allowsPromotion: true
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
