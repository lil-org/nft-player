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

#if DEBUG
    func testPendingDecodePriorityBucketsPreserveOrderAndDeduplicate() {
        XCTAssertEqual(
            DownloadableMediaCache.orderedPendingImageDecodeKeysForTesting(
                pendingKeys: [
                    "tail",
                    "foreground",
                    "demand-b",
                    "near",
                    "demand-a",
                    "demand-b"
                ],
                imageDemandKeys: ["demand-a", "demand-b"],
                foregroundKey: "foreground",
                preferredKeys: ["near", "foreground"]
            ),
            ["demand-b", "demand-a", "foreground", "near", "tail"]
        )
    }

    func testAddingImageDemandPromotesExistingPendingDecode() {
        let pendingKeys = ["foreground", "near", "demanded", "tail"]
        let withoutDemand = DownloadableMediaCache
            .orderedPendingImageDecodeKeysForTesting(
                pendingKeys: pendingKeys,
                imageDemandKeys: [],
                foregroundKey: "foreground",
                preferredKeys: ["near", "demanded"]
            )
        let withDemand = DownloadableMediaCache
            .orderedPendingImageDecodeKeysForTesting(
                pendingKeys: pendingKeys,
                imageDemandKeys: ["demanded"],
                foregroundKey: "foreground",
                preferredKeys: ["near", "demanded"]
            )

        XCTAssertEqual(
            withoutDemand,
            ["foreground", "near", "demanded", "tail"]
        )
        XCTAssertEqual(
            withDemand,
            ["demanded", "foreground", "near", "tail"]
        )
    }

    func testCancellingLastImageDemandDemotesRetainedPendingDecode() {
        let pendingKeys = ["demanded", "foreground", "near", "tail"]
        let withDemand = DownloadableMediaCache
            .orderedPendingImageDecodeKeysForTesting(
                pendingKeys: pendingKeys,
                imageDemandKeys: ["demanded"],
                foregroundKey: "foreground",
                preferredKeys: ["near", "demanded"]
            )
        let afterCancellation = DownloadableMediaCache
            .orderedPendingImageDecodeKeysForTesting(
                pendingKeys: pendingKeys,
                imageDemandKeys: [],
                foregroundKey: "foreground",
                preferredKeys: ["near", "demanded"]
            )

        XCTAssertEqual(
            withDemand,
            ["demanded", "foreground", "near", "tail"]
        )
        XCTAssertEqual(
            afterCancellation,
            ["foreground", "near", "demanded", "tail"]
        )
    }

    func testQueuedDecodeRetirementRequiresNoWindowDemandOrStartedWork() {
        XCTAssertTrue(DownloadableMediaCache.shouldRetireQueuedImageDecodeForTesting(
            isInDecodedWindow: false,
            hasImageDemand: false,
            hasStarted: false
        ))
        XCTAssertFalse(DownloadableMediaCache.shouldRetireQueuedImageDecodeForTesting(
            isInDecodedWindow: true,
            hasImageDemand: false,
            hasStarted: false
        ))
        XCTAssertFalse(DownloadableMediaCache.shouldRetireQueuedImageDecodeForTesting(
            isInDecodedWindow: false,
            hasImageDemand: true,
            hasStarted: false
        ))
        XCTAssertFalse(DownloadableMediaCache.shouldRetireQueuedImageDecodeForTesting(
            isInDecodedWindow: false,
            hasImageDemand: false,
            hasStarted: true
        ))
    }

    func testDecodeGenerationStartsOnceAndInvalidationSkipsIt() {
        XCTAssertEqual(
            DownloadableMediaCache.imageDecodeGenerationStartResultsForTesting(
                invalidateBeforeStart: false
            ),
            [true, false]
        )
        XCTAssertEqual(
            DownloadableMediaCache.imageDecodeGenerationStartResultsForTesting(
                invalidateBeforeStart: true
            ),
            [false, false]
        )
    }
#endif

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

        XCTAssertEqual(
            cell.refreshCachedImageIfAvailable(
                tokenIndex: descriptor.tokenIndex
            ),
            .unavailable
        )

        let cache = DownloadableMediaCache.shared
        cache.installDecodedImageForTesting(makeImage(.blue), for: descriptor)
        defer { cache.removeDecodedImageForTesting(for: descriptor) }

        XCTAssertEqual(
            cell.refreshCachedImageIfAvailable(
                tokenIndex: descriptor.tokenIndex
            ),
            .satisfied
        )
    }

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

        XCTAssertEqual(
            cell.refreshCachedImageIfAvailable(tokenIndex: 0),
            .satisfied
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

    func testDecodedImageResetRetiresOnlyReplacedCacheOffMainThread() async {
        let collectionId = "retired-memory-cache-\(UUID())"
        let retiredDescriptor = makeDescriptor(
            name: "retired",
            purpose: .collectionBrowserThumbnail,
            collectionId: collectionId,
            tokenIndex: 0
        )
        let activeDescriptor = makeDescriptor(
            name: "active",
            purpose: .collectionBrowserThumbnail,
            collectionId: collectionId,
            tokenIndex: 1
        )
        let retiredImage = makeImage(.orange)
        let activeImage = makeImage(.green)
        let cache = DownloadableMediaCache.shared
        defer {
            cache.resetDecodedImagesForTesting()
        }

        cache.installMemoryCachedImageForTesting(
            retiredImage,
            for: retiredDescriptor
        )
        cache.resetDecodedImagesForTesting()
        cache.installMemoryCachedImageForTesting(
            activeImage,
            for: activeDescriptor
        )

        let retirementRanOnMainThread = await cache.waitForDecodedImageRetirementForTesting()

        XCTAssertEqual(retirementRanOnMainThread, false)
        XCTAssertNil(cache.cachedDecodedImage(for: retiredDescriptor))
        XCTAssertTrue(cache.cachedDecodedImage(for: activeDescriptor) === activeImage)
    }

    func testCancelAllDownloadsInvalidatesDeferredImageLoad() async {
        let descriptor = makeDescriptor(
            name: "cancelled-deferred-image",
            purpose: .collectionBrowserThumbnail,
            collectionId: "cancelled-deferred-image-\(UUID())",
            tokenIndex: 0
        )
        let image = makeImage(.cyan)
        let cache = DownloadableMediaCache.shared
        let completion = expectation(description: "Deferred image load completes")
        var loadedImage: UIImage?
        defer {
            cache.removeDecodedImageForTesting(for: descriptor)
            cache.cancelAllDownloads()
        }

        _ = cache.loadImage(for: descriptor) { image in
            loadedImage = image
            completion.fulfill()
        }
        cache.cancelAllDownloads()
        cache.installDecodedImageForTesting(image, for: descriptor)

        await fulfillment(of: [completion], timeout: 1)

        XCTAssertNil(loadedImage)
    }

    func testCancelAllDownloadsInvalidatesDeferredFileLoad() async throws {
        let descriptor = makeDescriptor(
            name: "cancelled-deferred-file",
            purpose: .collectionBrowserThumbnail,
            collectionId: "cancelled-deferred-file-\(UUID())",
            tokenIndex: 0
        )
        let cache = DownloadableMediaCache.shared
        let fileURL = cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("cached".utf8).write(to: fileURL)
        let completion = expectation(description: "Deferred file load completes")
        var loadedURL: URL?
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            cache.cancelAllDownloads()
        }

        _ = cache.loadFile(for: descriptor) { url in
            loadedURL = url
            completion.fulfill()
        }
        cache.cancelAllDownloads()

        await fulfillment(of: [completion], timeout: 1)

        XCTAssertNil(loadedURL)
    }

    func testCancelAllDownloadsPreservesRetainedDeferredFileLoad() async throws {
        let descriptor = makeDescriptor(
            name: "retained-deferred-file",
            purpose: .collectionBrowserThumbnail,
            collectionId: "retained-deferred-file-\(UUID())",
            tokenIndex: 0
        )
        let cache = DownloadableMediaCache.shared
        let fileURL = cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("cached".utf8).write(to: fileURL)
        let completion = expectation(description: "Retained deferred file load completes")
        var loadedURL: URL?

        _ = cache.loadFile(for: descriptor) { url in
            loadedURL = url
            completion.fulfill()
        }
        let releaseFile = cache.retainFile(for: descriptor)
        defer {
            releaseFile()
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            cache.cancelAllDownloads()
        }
        cache.cancelAllDownloads()

        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(loadedURL, fileURL)
        releaseFile()
        await Task.yield()
    }

    func testRetainingAfterCancelDoesNotReviveDeferredFileLoad() async throws {
        let descriptor = makeDescriptor(
            name: "post-cancel-retained-file",
            purpose: .collectionBrowserThumbnail,
            collectionId: "post-cancel-retained-file-\(UUID())",
            tokenIndex: 0
        )
        let cache = DownloadableMediaCache.shared
        let fileURL = cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("cached".utf8).write(to: fileURL)
        let completion = expectation(description: "Cancelled deferred file load completes")
        var loadedURL: URL?

        _ = cache.loadFile(for: descriptor) { url in
            loadedURL = url
            completion.fulfill()
        }
        cache.cancelAllDownloads()
        let releaseFile = cache.retainFile(for: descriptor)
        defer {
            releaseFile()
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            cache.cancelAllDownloads()
        }

        await fulfillment(of: [completion], timeout: 1)

        XCTAssertNil(loadedURL)
        releaseFile()
        await Task.yield()
    }

    func testFileEvictionProtectsDemandedFileNames() {
        let collectionId = "eviction-demand-\(UUID())"
        let descriptor = makeDescriptor(
            name: "demanded-file",
            purpose: .collectionBrowserThumbnail,
            collectionId: collectionId,
            tokenIndex: 0
        )
        let cache = DownloadableMediaCache.shared
        let cancel = cache.loadFile(for: descriptor) { _ in }
        defer {
            cancel?()
            cache.cancelAllDownloads()
        }

        let protectedFileNames = cache.fileNamesProtectedFromEvictionForTesting(
            collectionId: collectionId,
            allowedFileNames: ["window-file"]
        )
        let fileName = cache.cachedFileURLForTesting(for: descriptor).lastPathComponent

        XCTAssertTrue(protectedFileNames.contains("window-file"))
        XCTAssertTrue(protectedFileNames.contains(fileName))
        XCTAssertTrue(protectedFileNames.contains("\(fileName).metadata.json"))
    }

    func testMemoryWarningDoesNotClearNewerCachedImage() async {
        let descriptor = makeDescriptor(
            name: "post-memory-warning-image",
            purpose: .collectionBrowserThumbnail,
            collectionId: "post-memory-warning-image-\(UUID())",
            tokenIndex: 0
        )
        let image = makeImage(.magenta)
        let cache = DownloadableMediaCache.shared
        defer {
            cache.resetDecodedImagesForTesting()
            let window = PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [],
                adjacentDescriptor: nil
            )
            cache.prepareWindow(window, ownerId: UUID())
            cache.cancelAllDownloads()
        }

        cache.handleMemoryWarningForTesting()
        cache.installMemoryCachedImageForTesting(image, for: descriptor)
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertTrue(cache.cachedDecodedImage(for: descriptor) === image)
    }

    func testMemoryWarningPreservesActiveAnimatedMediaDownloadWithoutFileCallback() {
        let collectionId = "memory-warning-foreground-media-\(UUID())"
        let descriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: collectionId,
            tokenId: "0",
            tokenIndex: 0,
            media: .animatedImage(
                url: URL(fileURLWithPath: "/memory-warning-foreground-media-\(UUID()).gif"),
                fileExtension: "gif"
            )
        )
        let cache = DownloadableMediaCache.shared
        let ownerId = UUID()
        let window = PlayerDownloadableMediaWindow(
            currentDescriptor: descriptor,
            descriptors: [descriptor],
            decodedDescriptors: [],
            adjacentDescriptor: nil
        )
        defer {
            cache.clearActiveWindow(ownerId: ownerId)
            cache.cancelAllDownloads()
        }

        cache.prepareWindow(window, ownerId: ownerId)
        cache.handleMemoryWarningForTesting()

        XCTAssertTrue(cache.hasForegroundFileWorkForTesting(for: descriptor))
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

nonisolated final class CancellableFileRemovalTokenTests: XCTestCase {

    func testSuccessfulRemovalDeletesFile() throws {
        let fileURL = temporaryFileURL()
        try Data("cached".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let token = DownloadableMediaCache.CancellableFileRemovalToken()

        XCTAssertEqual(token.removeIfActive(at: fileURL), .removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCancelledRemovalLeavesFileInPlace() throws {
        let fileURL = temporaryFileURL()
        try Data("cached".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let token = DownloadableMediaCache.CancellableFileRemovalToken()

        token.cancel()

        XCTAssertEqual(token.removeIfActive(at: fileURL), .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCancelledPairRemovalLeavesBothFilesInPlace() throws {
        let primaryURL = temporaryFileURL()
        let sidecarURL = temporaryFileURL()
        try Data("cached".utf8).write(to: primaryURL)
        try Data("metadata".utf8).write(to: sidecarURL)
        defer {
            try? FileManager.default.removeItem(at: primaryURL)
            try? FileManager.default.removeItem(at: sidecarURL)
        }
        let token = DownloadableMediaCache.CancellableFileRemovalToken()

        token.cancel()
        let removal = token.removePairIfActive(
            primaryURL: primaryURL,
            sidecarURL: sidecarURL
        )

        XCTAssertEqual(removal.primary, .cancelled)
        XCTAssertNil(removal.sidecar)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testFailedCleanupIsStagedForLaterRemoval() {
        let fileURL = temporaryFileURL()
        try? Data("cached".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let attemptedURL = OSAllocatedUnfairLock<URL?>(initialState: nil)
        let token = DownloadableMediaCache.CancellableFileRemovalToken(removeItem: { url in
            attemptedURL.withLock { $0 = url }
            throw CancellableFileRemovalTestError.expected
        })
        defer {
            if let url = attemptedURL.withLock({ $0 }) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let result = token.removeIfActive(at: fileURL)
        XCTAssertEqual(result, .stagedForCleanup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(token.isActive)
    }

    func testFailedPrimaryRemovalLeavesSidecarInPlace() throws {
        let primaryURL = temporaryFileURL()
        let sidecarURL = temporaryFileURL()
        try Data("metadata".utf8).write(to: sidecarURL)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        let token = DownloadableMediaCache.CancellableFileRemovalToken()

        let removal = token.removePairIfActive(
            primaryURL: primaryURL,
            sidecarURL: sidecarURL
        )

        XCTAssertEqual(removal.primary, .notRemoved)
        XCTAssertNil(removal.sidecar)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testSuccessfulPairRemovalDeletesBothFiles() throws {
        let primaryURL = temporaryFileURL()
        let sidecarURL = temporaryFileURL()
        try Data("cached".utf8).write(to: primaryURL)
        try Data("metadata".utf8).write(to: sidecarURL)
        defer {
            try? FileManager.default.removeItem(at: primaryURL)
            try? FileManager.default.removeItem(at: sidecarURL)
        }
        let token = DownloadableMediaCache.CancellableFileRemovalToken()

        let removal = token.removePairIfActive(
            primaryURL: primaryURL,
            sidecarURL: sidecarURL
        )

        XCTAssertEqual(removal.primary, .removed)
        XCTAssertEqual(removal.sidecar, .removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testCancellationDoesNotWaitForInFlightRemoval() {
        let removalStarted = DispatchSemaphore(value: 0)
        let allowRemoval = DispatchSemaphore(value: 0)
        let removalFinished = DispatchSemaphore(value: 0)
        let cancellationFinished = DispatchSemaphore(value: 0)
        let token = DownloadableMediaCache.CancellableFileRemovalToken(removeItem: { url in
            removalStarted.signal()
            allowRemoval.wait()
            try? FileManager.default.removeItem(at: url)
        })
        let fileURL = temporaryFileURL()
        try? Data("cached".utf8).write(to: fileURL)

        DispatchQueue.global().async {
            _ = token.removeIfActive(at: fileURL)
            removalFinished.signal()
        }
        XCTAssertEqual(removalStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            token.cancel()
            cancellationFinished.signal()
        }
        XCTAssertEqual(cancellationFinished.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(token.isActive)
        let cancelledResult = token.removeIfActive(at: fileURL)
        XCTAssertEqual(cancelledResult, .cancelled)
        let replacementData = Data("replacement".utf8)
        try? replacementData.write(to: fileURL)

        allowRemoval.signal()

        XCTAssertEqual(removalFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(try? Data(contentsOf: fileURL), replacementData)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testCancellationDuringPrimaryRemovalSkipsSidecar() {
        let primaryURL = temporaryFileURL()
        let sidecarURL = temporaryFileURL()
        let primaryStarted = DispatchSemaphore(value: 0)
        let allowPrimaryRemoval = DispatchSemaphore(value: 0)
        let pairFinished = DispatchSemaphore(value: 0)
        let cancellationFinished = DispatchSemaphore(value: 0)
        let sidecarRemoved = DispatchSemaphore(value: 0)
        let removalIndex = OSAllocatedUnfairLock(initialState: 0)
        let token = DownloadableMediaCache.CancellableFileRemovalToken(removeItem: { url in
            let index = removalIndex.withLock { index in
                defer { index += 1 }
                return index
            }
            if index == 0 {
                primaryStarted.signal()
                allowPrimaryRemoval.wait()
            } else {
                sidecarRemoved.signal()
            }
            try? FileManager.default.removeItem(at: url)
        })
        try? Data("cached".utf8).write(to: primaryURL)
        try? Data("metadata".utf8).write(to: sidecarURL)
        defer {
            try? FileManager.default.removeItem(at: primaryURL)
            try? FileManager.default.removeItem(at: sidecarURL)
        }

        DispatchQueue.global().async {
            _ = token.removePairIfActive(
                primaryURL: primaryURL,
                sidecarURL: sidecarURL
            )
            pairFinished.signal()
        }
        XCTAssertEqual(primaryStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            token.cancel()
            cancellationFinished.signal()
        }
        XCTAssertEqual(cancellationFinished.wait(timeout: .now() + 1), .success)
        allowPrimaryRemoval.signal()

        XCTAssertEqual(pairFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(sidecarRemoved.wait(timeout: .now()), .timedOut)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private enum CancellableFileRemovalTestError: Error {
    case expected
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
