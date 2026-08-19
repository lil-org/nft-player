// ∅ 2026 lil org

import Foundation
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
final class MobilePlayerCollectionBrowserCachedImagePolicyTests: XCTestCase {

    private func makeDescriptor(
        name: String,
        purpose: CollectionCatalogDownloadableMediaPurpose,
        collectionId: String = "collection",
        tokenIndex: Int = 7
    ) -> DownloadableMediaDescriptor {
        CollectionCatalogDownloadableMediaDescriptor(
            collectionId: collectionId,
            tokenId: String(tokenIndex),
            tokenIndex: tokenIndex,
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

    private func makeImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image {
            color.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
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

    func testSameIdentityReconfigurationKeepsValidDeferredImage() throws {
        let firstThumbnail = makeDescriptor(
            name: "first-thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let replacementThumbnail = makeDescriptor(
            name: "replacement-thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let large = makeDescriptor(
            name: "large",
            purpose: .collectionBrowserMid
        )
        let firstSources = CollectionBrowseImageSources(
            thumbnailDescriptor: firstThumbnail,
            largeDescriptor: large
        )
        let replacementSources = CollectionBrowseImageSources(
            thumbnailDescriptor: replacementThumbnail,
            largeDescriptor: large
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 7
        )
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let thumbnailImage = makeImage(.red)
        let largeImage = makeImage(.blue)
        let placeholder = PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil)

        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: firstSources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnailImage,
            descriptor: firstThumbnail,
            quality: .thumbnail,
            tokenIndex: 7,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        cell.installTransitionContent(
            image: makeImage(.green),
            descriptor: large,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )
        cell.setImage(
            largeImage,
            descriptor: large,
            quality: .large,
            tokenIndex: 7,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertTrue(baseImageView.image === thumbnailImage)

        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: replacementSources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .disabled
        )

        XCTAssertTrue(baseImageView.image === largeImage)
        XCTAssertEqual(cell.descriptor, large)
        XCTAssertFalse(cell.needsCarryoverContent)
    }

    func testDeferredImageInstallsBehindOpaqueTransitionContent() throws {
        let fixture = makeDistinctSources()
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 7
        )
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let thumbnailImage = makeImage(.red)
        let largeImage = makeImage(.blue)

        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: fixture.sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnailImage,
            descriptor: fixture.thumbnail,
            quality: .thumbnail,
            tokenIndex: 7,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let transitionImage = makeImage(.green)
        cell.installTransitionContent(
            image: transitionImage,
            descriptor: fixture.large,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.5,
            animated: false,
            identity: identity
        )
        cell.setImage(
            largeImage,
            descriptor: fixture.large,
            quality: .large,
            tokenIndex: 7,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertTrue(baseImageView.image === thumbnailImage)

        cell.clearTransitionContent()
        cell.setTransitionContentAlpha(0, interruptingAnimation: true)
        XCTAssertTrue(baseImageView.image === thumbnailImage)

        cell.installTransitionContent(
            image: transitionImage,
            descriptor: fixture.large,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 1,
            animated: false,
            identity: identity
        )
        cell.setTransitionContentAlpha(0.5, interruptingAnimation: true)

        XCTAssertTrue(baseImageView.image === largeImage)
        XCTAssertEqual(cell.descriptor, fixture.large)
    }

#if DEBUG
    func testForegroundCachedIdentityRetargetPreservesCarryoverUntilFade() throws {
        let collectionId = "cached-retarget-\(UUID())"
        let descriptorA = makeDescriptor(
            name: "a",
            purpose: .collectionBrowserThumbnail,
            collectionId: collectionId,
            tokenIndex: 0
        )
        let descriptorB = makeDescriptor(
            name: "b",
            purpose: .collectionBrowserThumbnail,
            collectionId: collectionId,
            tokenIndex: 1
        )
        let sourcesA = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptorA,
            largeDescriptor: descriptorA
        )
        let sourcesB = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptorB,
            largeDescriptor: descriptorB
        )
        let identityA = MobilePlayerBrowserContentIdentity(
            collectionId: collectionId,
            tokenIndex: 0
        )
        let identityB = MobilePlayerBrowserContentIdentity(
            collectionId: collectionId,
            tokenIndex: 1
        )
        let imageA = makeImage(.red)
        let imageB = makeImage(.blue)
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let placeholder = PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil)

        cell.configure(
            contentIdentity: identityA,
            itemCount: 2,
            imageSources: sourcesA,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            imageA,
            descriptor: descriptorA,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        DownloadableMediaCache.shared.installDecodedImageForTesting(
            imageB,
            for: descriptorB
        )
        defer {
            DownloadableMediaCache.shared.removeDecodedImageForTesting(
                for: descriptorB
            )
        }

        cell.configure(
            contentIdentity: identityB,
            itemCount: 2,
            imageSources: sourcesB,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false
        )

        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertTrue(baseImageView.image === imageB)
        XCTAssertEqual(cell.descriptor, descriptorB)
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertEqual(cell.carryoverSourceContent?.identity, identityA)
        XCTAssertTrue(cell.carryoverSourceContent?.primary.image === imageA)
        XCTAssertFalse(cell.canSelect(representing: identityB))
    }

    func testDecodedImageResetClearsInjectedImage() {
        let descriptor = makeDescriptor(
            name: "reset-injected-image",
            purpose: .collectionBrowserThumbnail,
            collectionId: "reset-injected-image-\(UUID())",
            tokenIndex: 0
        )
        let image = makeImage(.purple)
        let cache = DownloadableMediaCache.shared
        cache.installDecodedImageForTesting(image, for: descriptor)
        defer {
            cache.removeDecodedImageForTesting(for: descriptor)
        }

        XCTAssertTrue(cache.cachedDecodedImage(for: descriptor) === image)

        cache.resetDecodedImagesForTesting()

        XCTAssertNil(cache.cachedDecodedImage(for: descriptor))
    }
#endif
}
