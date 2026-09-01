// ∅ 2026 lil org

import Foundation
import MetalKit
import os
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobilePlayerCollectionBrowserCachedImagePolicyTests: XCTestCase {}

@MainActor
extension MobilePlayerCollectionBrowserCachedImagePolicyTests {

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
        smallestThumbnail: DownloadableMediaDescriptor,
        smallThumbnail: DownloadableMediaDescriptor,
        thumbnail: DownloadableMediaDescriptor,
        large: DownloadableMediaDescriptor
    ) {
        let smallestThumbnail = makeDescriptor(
            name: "smallest-thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let smallThumbnail = makeDescriptor(
            name: "small-thumbnail",
            purpose: .collectionBrowserThumbnail
        )
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
                smallestThumbnailDescriptor: smallestThumbnail,
                smallThumbnailDescriptor: smallThumbnail,
                thumbnailDescriptor: thumbnail,
                largeDescriptor: large
            ),
            smallestThumbnail,
            smallThumbnail,
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

    func testDecodeVariantCompatibilityRequiresEnoughPixels() {
        XCTAssertTrue(
            DownloadableMediaImageDecodeVariant.full.satisfies(
                .downsampled(maxPixelWidth: 260)
            )
        )
        XCTAssertTrue(
            DownloadableMediaImageDecodeVariant.downsampled(
                maxPixelWidth: 260
            ).satisfies(.downsampled(maxPixelWidth: 140))
        )
        XCTAssertFalse(
            DownloadableMediaImageDecodeVariant.downsampled(
                maxPixelWidth: 140
            ).satisfies(.downsampled(maxPixelWidth: 260))
        )
        XCTAssertFalse(
            DownloadableMediaImageDecodeVariant.downsampled(
                maxPixelWidth: 260
            ).satisfies(.full)
        )
    }

#if DEBUG
    func testCachedImageCarriesActualDecodeVariant() throws {
        let descriptor = makeDescriptor(
            name: "cached-variant-provenance",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let cache = DownloadableMediaCache.shared
        let loader = MobilePlayerCollectionBrowserCellImageLoader()
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(
            makeImage(.red),
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 260)
        )
        cache.installDecodedImageForTesting(
            makeImage(.blue),
            for: descriptor,
            variant: .full
        )
        loader.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: descriptor.collectionId,
                tokenIndex: descriptor.tokenIndex
            ),
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            imageDecodeVariant: .downsampled(maxPixelWidth: 140),
            imageLoadPolicy: .cachedOnly,
            allowsLocalLargeImageUpgrade: false,
            retainedDescriptor: nil,
            retainedImageHasLocalFile: false,
            fallbackImageSize: CGSize(width: 1, height: 1)
        )

        XCTAssertEqual(
            try XCTUnwrap(loader.cachedImageIfAvailable(
                displayedImageIsPresent: false
            )).imageDecodeVariant,
            .downsampled(maxPixelWidth: 260)
        )
    }

    func testBestAvailableCachedImagePrefersDestinationDecodeTierBeforeQuality()
        throws {
        let fixture = makeDistinctSources()
        let cache = DownloadableMediaCache.shared
        let largeImage = makeImage(.red)
        let thumbnailImage = makeImage(.blue)
        defer { cache.resetDecodedImagesForTesting() }
        cache.resetDecodedImagesForTesting()
        cache.installDecodedImageForTesting(
            largeImage,
            for: fixture.large,
            variant: .downsampled(maxPixelWidth: 160)
        )
        cache.installDecodedImageForTesting(
            thumbnailImage,
            for: fixture.thumbnail,
            variant: .full
        )

        let entry = try XCTUnwrap(fixture.sources.cachedImageEntry(
            in: cache,
            selectionPolicy: .highestAvailable,
            decodeSelection: .bestAvailable(
                preferredVariants: [
                    .full,
                    .downsampled(maxPixelWidth: 288),
                ]
            )
        ))

        XCTAssertEqual(entry.descriptor, fixture.thumbnail)
        XCTAssertEqual(entry.quality, .thumbnail)
        XCTAssertTrue(entry.image === thumbnailImage)
        XCTAssertEqual(entry.variant, .full)
    }

    func testBestAvailableCachedImagePrefersSourceDecodeTierBeforeAny()
        throws {
        let fixture = makeDistinctSources()
        let cache = DownloadableMediaCache.shared
        let largeImage = makeImage(.red)
        let thumbnailImage = makeImage(.blue)
        let sourceVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 288
        )
        defer { cache.resetDecodedImagesForTesting() }
        cache.resetDecodedImagesForTesting()
        cache.installDecodedImageForTesting(
            largeImage,
            for: fixture.large,
            variant: .downsampled(maxPixelWidth: 160)
        )
        cache.installDecodedImageForTesting(
            thumbnailImage,
            for: fixture.thumbnail,
            variant: sourceVariant
        )

        let entry = try XCTUnwrap(fixture.sources.cachedImageEntry(
            in: cache,
            selectionPolicy: .highestAvailable,
            decodeSelection: .bestAvailable(
                preferredVariants: [.full, sourceVariant, sourceVariant]
            )
        ))

        XCTAssertEqual(entry.descriptor, fixture.thumbnail)
        XCTAssertEqual(entry.quality, .thumbnail)
        XCTAssertTrue(entry.image === thumbnailImage)
        XCTAssertEqual(entry.variant, sourceVariant)
    }

    func testBestAvailableCachedImagePreservesAnyVariantAndQualityRanking()
        throws {
        let fixture = makeDistinctSources()
        let cache = DownloadableMediaCache.shared
        let largeImage = makeImage(.red)
        let thumbnailImage = makeImage(.blue)
        let largeVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 160
        )
        defer { cache.resetDecodedImagesForTesting() }
        cache.resetDecodedImagesForTesting()
        cache.installDecodedImageForTesting(
            largeImage,
            for: fixture.large,
            variant: largeVariant
        )
        cache.installDecodedImageForTesting(
            thumbnailImage,
            for: fixture.thumbnail,
            variant: .downsampled(maxPixelWidth: 140)
        )

        let entry = try XCTUnwrap(fixture.sources.cachedImageEntry(
            in: cache,
            selectionPolicy: .highestAvailable,
            decodeSelection: .bestAvailable(
                preferredVariants: [
                    .full,
                    .downsampled(maxPixelWidth: 288),
                ]
            )
        ))

        XCTAssertEqual(entry.descriptor, fixture.large)
        XCTAssertEqual(entry.quality, .large)
        XCTAssertTrue(entry.image === largeImage)
        XCTAssertEqual(entry.variant, largeVariant)
    }
#endif

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

    func testSmallThumbnailBaseWithoutLargeUpgradePrefersOptimizedThumbnail() {
        let fixture = makeDistinctSources()

        XCTAssertEqual(
            fixture.sources.cachedImageCandidateDescriptors(
                selectionPolicy: .base(
                    requiredQuality: .smallThumbnail,
                    allowsLocalLargeUpgrade: false
                )
            ),
            [fixture.smallThumbnail, fixture.thumbnail]
        )
    }

    func testSmallestThumbnailBaseReusesHigherQualityThumbnails() {
        let fixture = makeDistinctSources()

        XCTAssertEqual(
            fixture.sources.cachedImageCandidateDescriptors(
                selectionPolicy: .base(
                    requiredQuality: .smallestThumbnail,
                    allowsLocalLargeUpgrade: false
                )
            ),
            [
                fixture.smallestThumbnail,
                fixture.smallThumbnail,
                fixture.thumbnail,
            ]
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
            [
                fixture.large,
                fixture.thumbnail,
                fixture.smallThumbnail,
                fixture.smallestThumbnail,
            ]
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
            [
                fixture.large,
                fixture.thumbnail,
                fixture.smallThumbnail,
                fixture.smallestThumbnail,
            ]
        )
    }

    func testFourDistinctImageSourcesResolveByQuality() {
        let fixture = makeDistinctSources()

        XCTAssertEqual(
            fixture.sources.descriptor(for: .smallestThumbnail),
            fixture.smallestThumbnail
        )
        XCTAssertEqual(
            fixture.sources.descriptor(for: .smallThumbnail),
            fixture.smallThumbnail
        )
        XCTAssertEqual(
            fixture.sources.descriptor(for: .thumbnail),
            fixture.thumbnail
        )
        XCTAssertEqual(
            fixture.sources.descriptor(for: .large),
            fixture.large
        )
        XCTAssertEqual(
            fixture.sources.quality(of: fixture.smallestThumbnail),
            .smallestThumbnail
        )
        XCTAssertEqual(
            fixture.sources.quality(of: fixture.smallThumbnail),
            .smallThumbnail
        )
        XCTAssertEqual(
            fixture.sources.quality(of: fixture.thumbnail),
            .thumbnail
        )
        XCTAssertEqual(fixture.sources.quality(of: fixture.large), .large)
        XCTAssertNil(
            fixture.sources.fallbackQuality(after: .smallestThumbnail)
        )
        XCTAssertNil(fixture.sources.fallbackQuality(after: .smallThumbnail))
        XCTAssertEqual(
            fixture.sources.fallbackQuality(after: .large),
            .thumbnail
        )
        XCTAssertNil(fixture.sources.fallbackQuality(after: .thumbnail))
    }

    func testMissingSmallestThumbnailDoesNotResolveToAnotherTier() {
        let smallThumbnail = makeDescriptor(
            name: "small-thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let thumbnail = makeDescriptor(
            name: "thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let smallFallback = CollectionBrowseImageSources(
            smallThumbnailDescriptor: smallThumbnail,
            thumbnailDescriptor: thumbnail,
            largeDescriptor: thumbnail
        )
        let standardFallback = CollectionBrowseImageSources(
            thumbnailDescriptor: thumbnail,
            largeDescriptor: thumbnail
        )

        XCTAssertNil(smallFallback.descriptor(for: .smallestThumbnail))
        XCTAssertEqual(
            smallFallback.quality(of: smallThumbnail),
            .smallThumbnail
        )
        XCTAssertNil(
            smallFallback.fallbackQuality(after: .smallestThumbnail)
        )
        XCTAssertNil(standardFallback.descriptor(for: .smallestThumbnail))
        XCTAssertEqual(
            standardFallback.quality(of: thumbnail),
            .large
        )
        XCTAssertNil(
            standardFallback.fallbackQuality(after: .smallestThumbnail)
        )
    }

#if DEBUG
    func testDecodeVariantUpgradeKeepsDisplayedFallback() throws {
        let descriptor = makeDescriptor(
            name: "dense-upgrade-fallback",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: descriptor.collectionId,
            tokenIndex: descriptor.tokenIndex
        )
        let denseImage = makeImage(.red)
        let cache = DownloadableMediaCache.shared
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let imageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(
            denseImage,
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 140)
        )
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec:
                PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil),
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false,
            imageDecodeVariant: .downsampled(maxPixelWidth: 140)
        )
        XCTAssertTrue(imageView.image === denseImage)

        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec:
                PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil),
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false,
            imageDecodeVariant: .full
        )

        XCTAssertTrue(imageView.image === denseImage)
    }

    func testFullConfigurationReplacesDenseImageForSameDescriptor() throws {
        let descriptor = makeDescriptor(
            name: "dense-to-full",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: descriptor.collectionId,
            tokenIndex: descriptor.tokenIndex
        )
        let denseImage = makeImage(.red)
        let fullImage = makeImage(.blue)
        let cache = DownloadableMediaCache.shared
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let placeholder = PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil)
        let imageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(
            denseImage,
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 140)
        )
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false,
            imageDecodeVariant: .downsampled(maxPixelWidth: 140)
        )
        XCTAssertTrue(imageView.image === denseImage)

        cache.installDecodedImageForTesting(fullImage, for: descriptor)
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false,
            imageDecodeVariant: .full
        )

        XCTAssertTrue(imageView.image === fullImage)
    }

    func testLargerDenseConfigurationReplacesSmallerDenseImage() throws {
        let descriptor = makeDescriptor(
            name: "dense-size-upgrade",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: descriptor.collectionId,
            tokenIndex: descriptor.tokenIndex
        )
        let smallImage = makeImage(.red)
        let largeImage = makeImage(.blue)
        let cache = DownloadableMediaCache.shared
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let placeholder = PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil)
        let imageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(
            smallImage,
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 140)
        )
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false,
            imageDecodeVariant: .downsampled(maxPixelWidth: 140)
        )
        XCTAssertTrue(imageView.image === smallImage)

        cache.installDecodedImageForTesting(
            largeImage,
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 260)
        )
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false,
            imageDecodeVariant: .downsampled(maxPixelWidth: 260)
        )

        XCTAssertTrue(imageView.image === largeImage)
    }

    func testUnchangedUnsatisfiedCachedOnlyConfigurationRefreshesCache() throws {
        let descriptor = makeDescriptor(
            name: "same-signature-cache-refresh",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: descriptor.collectionId,
            tokenIndex: descriptor.tokenIndex
        )
        let image = makeImage(.blue)
        let cache = DownloadableMediaCache.shared
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let placeholder = PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil)
        let imageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(image, for: descriptor)
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .cachedOnly,
            allowsLocalLargeImageUpgrade: false
        )
        XCTAssertNil(imageView.image)

        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .cachedOnly,
            allowsLocalLargeImageUpgrade: false
        )

        XCTAssertTrue(imageView.image === image)
    }

    func testUnchangedForegroundConfigurationInstallsCachedUpgrade() throws {
        let thumbnailDescriptor = makeDescriptor(
            name: "unchanged-thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let largeDescriptor = makeDescriptor(
            name: "unchanged-large",
            purpose: .primary
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: thumbnailDescriptor,
            largeDescriptor: largeDescriptor
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: thumbnailDescriptor.collectionId,
            tokenIndex: thumbnailDescriptor.tokenIndex
        )
        let thumbnailImage = makeImage(.red)
        let largeImage = makeImage(.blue)
        let cache = DownloadableMediaCache.shared
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let placeholder = PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil)
        let imageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(
            thumbnailImage,
            for: thumbnailDescriptor
        )
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground
        )
        XCTAssertTrue(imageView.image === thumbnailImage)

        cache.installDecodedImageForTesting(largeImage, for: largeDescriptor)
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground
        )

        XCTAssertTrue(imageView.image === largeImage)
    }

    func testForegroundReconfigurationRestoresDemotedImageLoadPolicy() throws {
        let descriptor = makeDescriptor(
            name: "foreground-reconfiguration",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: descriptor.collectionId,
            tokenIndex: descriptor.tokenIndex
        )
        let cache = DownloadableMediaCache.shared
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        defer { cache.resetDecodedImagesForTesting() }
        cache.installDecodedImageForTesting(
            makeImage(.blue),
            for: descriptor
        )

        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec:
                PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil),
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false
        )
        cell.demoteImageLoadToCachedOnlyIfNeeded(
            tokenIndex: descriptor.tokenIndex
        )
        XCTAssertFalse(cell.usesForegroundImageLoading)

        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec:
                PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil),
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false
        )

        XCTAssertTrue(cell.usesForegroundImageLoading)
    }

    func testMissingSmallestThumbnailStopsCachedRefreshRetry() {
        let descriptor = makeDescriptor(
            name: "missing-smallest-refresh",
            purpose: .collectionBrowserThumbnail
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        cell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: descriptor.collectionId,
                tokenIndex: descriptor.tokenIndex
            ),
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .smallestThumbnail,
            missingDescriptorFallbackSpec:
                PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil),
            imageLoadPolicy: .cachedOnly,
            allowsLocalLargeImageUpgrade: false
        )

        XCTAssertFalse(
            cell.refreshCachedImageIfAvailable(
                tokenIndex: descriptor.tokenIndex
            )
        )

        let cache = DownloadableMediaCache.shared
        cache.installDecodedImageForTesting(makeImage(.blue), for: descriptor)
        defer { cache.removeDecodedImageForTesting(for: descriptor) }

        XCTAssertTrue(
            cell.refreshCachedImageIfAvailable(
                tokenIndex: descriptor.tokenIndex
            )
        )
    }
#endif

    func testMissingSmallestThumbnailReleasesRetargetCarryover() async {
        let collectionId = "missing-smallest-retarget-\(UUID())"
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
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let placeholder = PlayerMediaPlaceholderSpec(
            thumbnailAspectRatio: nil
        )
        cell.configure(
            contentIdentity: identityA,
            itemCount: 2,
            imageSources: sourcesA,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            makeImage(.red),
            descriptor: descriptorA,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        cell.configure(
            contentIdentity: identityB,
            itemCount: 2,
            imageSources: sourcesB,
            requiredImageQuality: .smallestThumbnail,
            missingDescriptorFallbackSpec: placeholder,
            imageLoadPolicy: .foreground,
            allowsLocalLargeImageUpgrade: false
        )
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        XCTAssertNil(cell.carryoverSourceContent)
        XCTAssertTrue(cell.canSelect(representing: identityB))
        XCTAssertNil(cell.descriptor)
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

    func testDescendingCandidatesDeduplicateSharedQualityDescriptors() {
        let shared = makeDescriptor(
            name: "shared",
            purpose: .collectionBrowserThumbnail
        )
        let smallThumbnail = makeDescriptor(
            name: "small-thumbnail",
            purpose: .collectionBrowserThumbnail
        )
        let partiallySharedSources = CollectionBrowseImageSources(
            smallThumbnailDescriptor: smallThumbnail,
            thumbnailDescriptor: shared,
            largeDescriptor: shared
        )
        let fullySharedSources = CollectionBrowseImageSources(
            thumbnailDescriptor: shared,
            largeDescriptor: shared
        )

        XCTAssertEqual(
            partiallySharedSources.descriptorsByDescendingQuality,
            [shared, smallThumbnail]
        )
        XCTAssertEqual(
            fullySharedSources.descriptorsByDescendingQuality,
            [shared]
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
    func testCachedOnlyCellInstallsImageDecodedAfterConfiguration() throws {
        let collectionId = "scrolling-cache-\(UUID())"
        let descriptor = makeDescriptor(
            name: "scrolling-cache",
            purpose: .collectionBrowserThumbnail,
            collectionId: collectionId,
            tokenIndex: 0
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: collectionId,
            tokenIndex: 0
        )
        let image = makeImage(.magenta)
        let cache = DownloadableMediaCache.shared
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .smallThumbnail,
            missingDescriptorFallbackSpec:
                PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil),
            imageLoadPolicy: .cachedOnly,
            allowsLocalLargeImageUpgrade: false
        )
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertNil(baseImageView.image)
        XCTAssertFalse(cell.usesForegroundImageLoading)

        cache.installDecodedImageForTesting(image, for: descriptor)
        defer {
            cache.removeDecodedImageForTesting(for: descriptor)
        }

        XCTAssertTrue(
            cell.refreshCachedImageIfAvailable(tokenIndex: 0)
        )
        XCTAssertTrue(baseImageView.image === image)
        XCTAssertFalse(cell.usesForegroundImageLoading)
    }

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

#endif
}

private actor NativeMetalCardAssetLoadGate<Value: Sendable> {
    private struct PendingValue: Sendable {
        let value: Value
    }

    private var continuation: CheckedContinuation<Value, Never>?
    private var pendingValue: PendingValue?
    private var started = false

    func wait() async -> Value {
        started = true
        if let pendingValue {
            self.pendingValue = nil
            return pendingValue.value
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func hasStarted() -> Bool {
        started
    }

    func resume(returning value: Value) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        } else {
            pendingValue = PendingValue(value: value)
        }
    }
}

nonisolated final class NativeMetalCardAssetLeaseTests: XCTestCase {

    func testAssetGenerationChangesOnlyWhenCachedFileChanges() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let facePath = "faces/1.webp"
        let faceURL = rootURL.appendingPathComponent(facePath)
        try FileManager.default.createDirectory(
            at: faceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let contents = Data([1, 2, 3])
        try contents.write(to: faceURL)

        let cache = NativeMetalCardAssetCache(configuration: NativeMetalCardAssetCacheConfiguration(
            renderKind: .cardNft2,
            rootURL: rootURL,
            logger: Logger(subsystem: "org.lil.nft-player.tests", category: "NativeMetalCardAssetCache"),
            logName: "test",
            maxCacheBytes: nil,
            markCachedFilesAsUsed: false,
            paths: { _ in
                NativeMetalCardAssetPaths(
                    face: facePath,
                    foil: "foils/1.webp",
                    textureMask: "textures/1.webp",
                    grain: "img/grain.webp",
                    glitter: "img/glitter.png"
                )
            },
            remoteURL: { _ in nil }
        ))

        let firstResult = await cache.loadFace(for: 1)
        let secondResult = await cache.loadFace(for: 1)
        let firstAssetURL = try XCTUnwrap(firstResult)
        let secondAssetURL = try XCTUnwrap(secondResult)
        XCTAssertEqual(firstAssetURL.generationID, secondAssetURL.generationID)

        await cache.invalidate(firstAssetURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: faceURL.path))

        let replacementSourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let replacementContents = Data([4, 5, 6])
        try replacementContents.write(to: replacementSourceURL)
        defer {
            try? FileManager.default.removeItem(at: replacementSourceURL)
        }
        let didCacheReplacement = await cache.cacheFace(
            for: 1,
            from: replacementSourceURL
        )
        XCTAssertTrue(didCacheReplacement)
        let replacementResult = await cache.loadFace(for: 1)
        let replacementAssetURL = try XCTUnwrap(replacementResult)
        XCTAssertNotEqual(firstAssetURL.generationID, replacementAssetURL.generationID)

        await cache.invalidate(firstAssetURL)
        XCTAssertEqual(try Data(contentsOf: faceURL), replacementContents)

        await cache.invalidate(replacementAssetURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: faceURL.path))
    }
}

nonisolated final class NativeMetalCardResourceLifecycleTests: XCTestCase {

    @MainActor
    func testRendererCoreDoesNotStayAliveWhileAssetLoadsAreSuspended() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }
        let faceGate = NativeMetalCardAssetLoadGate<NativeMetalCardAssetURL?>()
        let effectGate = NativeMetalCardAssetLoadGate<NativeMetalCardAssetURLs?>()
        let assetLoader = NativeMetalCardRendererAssetLoader(
            loadFace: { _, _ in
                await faceGate.wait()
            },
            loadEffectAssets: { _, _ in
                await effectGate.wait()
            },
            prefetch: { _, _, _ in },
            cancelPrefetchDownloads: { _ in },
            invalidateAsset: { _, _ in }
        )
        var rendererCore = NativeMetalCardRendererCore(
            device: device,
            logger: Logger(subsystem: "org.lil.nft-player.tests", category: "NativeMetalCard"),
            assetLoader: assetLoader
        )
        guard rendererCore != nil else {
            throw XCTSkip("Native Metal renderer is unavailable")
        }
        weak let weakRendererCore = rendererCore

        rendererCore?.display(tokenID: 1, renderKind: .cardNft2)
        for _ in 0..<100 {
            let faceLoadStarted = await faceGate.hasStarted()
            let effectLoadStarted = await effectGate.hasStarted()
            if faceLoadStarted, effectLoadStarted {
                break
            }
            await Task.yield()
        }
        let faceLoadStarted = await faceGate.hasStarted()
        let effectLoadStarted = await effectGate.hasStarted()
        XCTAssertTrue(faceLoadStarted)
        XCTAssertTrue(effectLoadStarted)

        rendererCore = nil
        for _ in 0..<10 where weakRendererCore != nil {
            await Task.yield()
        }
        XCTAssertNil(weakRendererCore)

        await faceGate.resume(returning: nil)
        await effectGate.resume(returning: nil)
    }

    @MainActor
    func testEffectAssetFailureStillPresentsFaceFallback() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }
        let faceGate = NativeMetalCardAssetLoadGate<NativeMetalCardAssetURL?>()
        let effectGate = NativeMetalCardAssetLoadGate<NativeMetalCardAssetURLs?>()
        await effectGate.resume(returning: nil)
        let assetLoader = NativeMetalCardRendererAssetLoader(
            loadFace: { _, _ in
                await faceGate.wait()
            },
            loadEffectAssets: { _, _ in
                await effectGate.wait()
            },
            prefetch: { _, _, _ in },
            cancelPrefetchDownloads: { _ in },
            invalidateAsset: { _, _ in }
        )
        guard let rendererCore = NativeMetalCardRendererCore(
            device: device,
            logger: Logger(subsystem: "org.lil.nft-player.tests", category: "NativeMetalCard"),
            assetLoader: assetLoader
        ) else {
            throw XCTSkip("Native Metal renderer is unavailable")
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let imageData = try XCTUnwrap(image.pngData())
        let faceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try imageData.write(to: faceURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: faceURL)
        }
        let contentReady = expectation(description: "Face fallback is ready")

        rendererCore.display(
            tokenID: 1,
            renderKind: .cardNft2,
            onContentReady: {
                contentReady.fulfill()
            }
        )
        for _ in 0..<100 {
            if await effectGate.hasStarted() {
                break
            }
            await Task.yield()
        }
        let effectLoadStarted = await effectGate.hasStarted()
        XCTAssertTrue(effectLoadStarted)
        for _ in 0..<10 {
            await Task.yield()
        }

        await faceGate.resume(returning: NativeMetalCardAssetURL(
            asset: NativeMetalCardAssetPath(role: .face, relativePath: faceURL.lastPathComponent),
            url: faceURL,
            generationID: UUID()
        ))
        await fulfillment(of: [contentReady], timeout: 2)

        let textures = try XCTUnwrap(rendererCore.textures)
        XCTAssertFalse(textures.rendersEffect)
    }
}
