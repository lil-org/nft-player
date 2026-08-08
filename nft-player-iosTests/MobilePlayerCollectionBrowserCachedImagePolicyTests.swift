// ∅ 2026 lil org

import Foundation
import XCTest
@testable import nft_player_ios

final class MobilePlayerCollectionBrowserCachedImagePolicyTests: XCTestCase {

    private func makeDescriptor(
        name: String,
        purpose: CollectionCatalogDownloadableMediaPurpose
    ) -> DownloadableMediaDescriptor {
        CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "7",
            tokenIndex: 7,
            media: .staticImage(
                url: URL(fileURLWithPath: "/\(name).webp"),
                fileExtension: "webp"
            ),
            purpose: purpose
        )
    }

    private func makeDistinctSources() -> (
        sources: CollectionBrowseImageSources,
        thumbnail: DownloadableMediaDescriptor,
        large: DownloadableMediaDescriptor
    ) {
        let thumbnail = makeDescriptor(
            name: "thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let large = makeDescriptor(
            name: "large",
            purpose: .collectionBrowserMid
        )
        return (
            CollectionBrowseImageSources(
                thumbnailDescriptor: thumbnail,
                largeDescriptor: large
            ),
            thumbnail,
            large
        )
    }

    func testThumbnailBaseWithoutLargeUpgradeUsesOnlyThumbnail() {
        let fixture = makeDistinctSources()

        XCTAssertEqual(
            fixture.sources.cachedImageCandidateDescriptors(
                selectionPolicy: .base(
                    requiredQuality: .thumbnail,
                    allowsLocalLargeUpgrade: false
                )
            ),
            [fixture.thumbnail]
        )
    }

    func testRequiredLargeWithoutUpgradeUsesDescendingQuality() {
        let fixture = makeDistinctSources()

        XCTAssertEqual(
            fixture.sources.cachedImageCandidateDescriptors(
                selectionPolicy: .base(
                    requiredQuality: .large,
                    allowsLocalLargeUpgrade: false
                )
            ),
            [fixture.large, fixture.thumbnail]
        )
    }

    func testThumbnailBaseWithLargeUpgradeUsesDescendingQuality() {
        let fixture = makeDistinctSources()

        XCTAssertEqual(
            fixture.sources.cachedImageCandidateDescriptors(
                selectionPolicy: .base(
                    requiredQuality: .thumbnail,
                    allowsLocalLargeUpgrade: true
                )
            ),
            [fixture.large, fixture.thumbnail]
        )
    }

    func testSharedDescriptorIsReturnedOnceWithoutLargeUpgrade() {
        let descriptor = makeDescriptor(
            name: "shared",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )

        XCTAssertEqual(
            sources.cachedImageCandidateDescriptors(
                selectionPolicy: .base(
                    requiredQuality: .thumbnail,
                    allowsLocalLargeUpgrade: false
                )
            ),
            [descriptor]
        )
    }
}
