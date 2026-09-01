import Foundation
import os
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class DownloadableMediaCacheTests: XCTestCase {}

nonisolated private final class DecodedImageAvailabilityRecorder:
    @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues = [
        DownloadableMediaCacheDecodedImageAvailability
    ]()

    var values: [DownloadableMediaCacheDecodedImageAvailability] {
        lock.withLock { recordedValues }
    }

    func record(_ value: DownloadableMediaCacheDecodedImageAvailability) {
        lock.withLock { recordedValues.append(value) }
    }
}

@MainActor
extension DownloadableMediaCacheTests {

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
                    "demand-b",
                ],
                imageDemandKeys: ["demand-a", "demand-b"],
                foregroundKey: "foreground",
                preferredKeys: ["near", "foreground"]
            ),
            ["demand-b", "demand-a", "foreground", "near", "tail"]
        )
    }

    func testAddingAndRemovingImageDemandReordersPendingDecode() {
        let pendingKeys = ["demanded", "foreground", "near", "tail"]
        let withDemand = DownloadableMediaCache
            .orderedPendingImageDecodeKeysForTesting(
                pendingKeys: pendingKeys,
                imageDemandKeys: ["demanded"],
                foregroundKey: "foreground",
                preferredKeys: ["near", "demanded"]
            )
        let withoutDemand = DownloadableMediaCache
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
            withoutDemand,
            ["foreground", "near", "demanded", "tail"]
        )
    }

    func testAsyncImageReturnsSynchronousMemoryHit() async {
        let descriptor = makeDescriptor(name: "async-memory-hit")
        let image = makeImage(.cyan)
        let cache = DownloadableMediaCache.shared
        cache.installDecodedImageForTesting(image, for: descriptor)
        defer {
            cache.removeDecodedImageForTesting(for: descriptor)
        }

        let loadedImage = await cache.image(for: descriptor)

        XCTAssertTrue(loadedImage === image)
    }

    func testDecodedImageAvailabilityOnlyPublishesAcceptedInsertions()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let recorder = DecodedImageAvailabilityRecorder()
        let observer = fixture.notificationCenter.addObserver(
            forName: .downloadableMediaCacheDecodedImageDidBecomeAvailable,
            object: nil,
            queue: nil
        ) { notification in
            guard let availability = notification.object
                as? DownloadableMediaCacheDecodedImageAvailability else {
                return
            }
            recorder.record(availability)
        }
        defer {
            fixture.notificationCenter.removeObserver(observer)
            fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
        }
        let rejectedDescriptor = makeDescriptor(
            name: "rejected-decoded-notification"
        )
        let acceptedDescriptor = makeDescriptor(
            name: "accepted-decoded-notification"
        )
        let expected = DownloadableMediaCacheDecodedImageAvailability(
            collectionId: acceptedDescriptor.collectionId,
            tokenIndex: acceptedDescriptor.tokenIndex
        )

        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(false)
        fixture.cache.installMemoryCachedImageForTesting(
            makeImage(.red),
            for: rejectedDescriptor
        )
        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
        fixture.cache.installMemoryCachedImageForTesting(
            makeImage(.green),
            for: acceptedDescriptor
        )
        try await waitForControlledEvent("decoded image availability") {
            while !recorder.values.contains(expected) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertEqual(recorder.values, [expected])
    }

    func testImageDecoderDownsamplesPortraitByDisplayedPixelWidth()
        async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("portrait.png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sourceImage = UIGraphicsImageRenderer(
            size: CGSize(width: 1_000, height: 3_000),
            format: format
        ).image { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 3_000))
        }
        try XCTUnwrap(sourceImage.pngData()).write(to: fileURL)

        let transfer = await DownloadableMediaImageDecoder().decode(
            at: fileURL,
            variant: .downsampled(maxPixelWidth: 320),
            generation: DownloadableMediaImageDecodeGeneration()
        )
        let image = try XCTUnwrap(transfer?.image)

        XCTAssertEqual(image.cgImage?.width, 320)
        XCTAssertEqual(image.cgImage?.height ?? 0, 960, accuracy: 1)
        XCTAssertEqual(
            transfer?.variant,
            .downsampled(maxPixelWidth: 320)
        )
    }

    func testImageDecoderNeverUpsamplesSmallSources() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("small.png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sourceImage = UIGraphicsImageRenderer(
            size: CGSize(width: 100, height: 300),
            format: format
        ).image { context in
            UIColor.cyan.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 300))
        }
        try XCTUnwrap(sourceImage.pngData()).write(to: fileURL)

        let transfer = await DownloadableMediaImageDecoder().decode(
            at: fileURL,
            variant: .downsampled(maxPixelWidth: 320),
            generation: DownloadableMediaImageDecodeGeneration()
        )
        let image = try XCTUnwrap(transfer?.image)

        XCTAssertEqual(image.cgImage?.width, 100)
        XCTAssertEqual(image.cgImage?.height, 300)
        XCTAssertEqual(transfer?.variant, .full)
    }

    func testImageDecoderFallsBackToFullDecodeWhenThumbnailFails() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("fallback.png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sourceImage = UIGraphicsImageRenderer(
            size: CGSize(width: 640, height: 960),
            format: format
        ).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 960))
        }
        try XCTUnwrap(sourceImage.pngData()).write(to: fileURL)

        let entry = DownloadableMediaImageDecoder
            .decodeDownsampledImageWithFailedThumbnailForTesting(
                at: fileURL,
                maxPixelWidth: 160
            )

        XCTAssertEqual(entry?.image.cgImage?.width, 640)
        XCTAssertEqual(entry?.image.cgImage?.height, 960)
        XCTAssertEqual(entry?.variant, .full)
    }

    func testDecodedImageVariantsKeepFullResolutionIndependent() {
        let descriptor = makeDescriptor(name: "decode-variants")
        let denseImage = makeImage(.purple)
        let fullImage = makeImage(.yellow)
        let cache = DownloadableMediaCache.shared
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(
            denseImage,
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 320)
        )

        XCTAssertNil(cache.cachedDecodedImage(for: descriptor, variant: .full))
        XCTAssertTrue(cache.cachedDecodedImage(
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 320)
        ) === denseImage)
        let denseEntry = cache.cachedDecodedImageEntry(
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 140)
        )
        XCTAssertTrue(denseEntry?.image === denseImage)
        XCTAssertEqual(
            denseEntry?.variant,
            .downsampled(maxPixelWidth: 320)
        )

        cache.installDecodedImageForTesting(fullImage, for: descriptor)

        XCTAssertTrue(cache.cachedDecodedImage(
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 320)
        ) === denseImage)
        XCTAssertTrue(cache.cachedDecodedImage(
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 640)
        ) === fullImage)
        let fullFallbackEntry = cache.cachedDecodedImageEntry(
            for: descriptor,
            variant: .downsampled(maxPixelWidth: 640)
        )
        XCTAssertTrue(fullFallbackEntry?.image === fullImage)
        XCTAssertEqual(fullFallbackEntry?.variant, .full)
    }

    func testAnyCachedDecodedImageUsesSmallestVariantAndSkipsStaleMetadata() {
        let descriptor = makeDescriptor(name: "any-decode-variant")
        let smallVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 140
        )
        let largeVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 260
        )
        let smallImage = makeImage(.purple)
        let largeImage = makeImage(.cyan)
        let fullImage = makeImage(.yellow)
        let cache = DownloadableMediaCache.shared
        defer { cache.resetDecodedImagesForTesting() }

        cache.installDecodedImageForTesting(
            fullImage,
            for: descriptor,
            variant: .full
        )
        cache.installDecodedImageForTesting(
            largeImage,
            for: descriptor,
            variant: largeVariant
        )
        cache.installDecodedImageForTesting(
            smallImage,
            for: descriptor,
            variant: smallVariant
        )

        let smallestEntry = cache.anyCachedDecodedImageEntry(for: descriptor)
        XCTAssertTrue(smallestEntry?.image === smallImage)
        XCTAssertEqual(smallestEntry?.variant, smallVariant)

        cache.removeDecodedImageForTesting(
            for: descriptor,
            variant: smallVariant
        )
        let nextEntry = cache.anyCachedDecodedImageEntry(for: descriptor)
        XCTAssertTrue(nextEntry?.image === largeImage)
        XCTAssertEqual(nextEntry?.variant, largeVariant)

        cache.removeDecodedImageForTesting(
            for: descriptor,
            variant: largeVariant
        )
        let fullEntry = cache.anyCachedDecodedImageEntry(for: descriptor)
        XCTAssertTrue(fullEntry?.image === fullImage)
        XCTAssertEqual(fullEntry?.variant, .full)
    }

    func testDistinctImageDemandChangesAdjustProtectionLinearly() {
        let cache = DownloadableMediaCache.shared
        let countsBefore = cache.instrumentationCountsForTesting()
        let descriptors = (0..<1_000).map { index in
            makeDescriptor(
                name: "protection-delta-\(index)"
            )
        }

        cache.exerciseImageDemandProtectionForTesting(descriptors)

        let countsAfter = cache.instrumentationCountsForTesting()
        XCTAssertEqual(
            countsAfter.protectionFullRebuilds,
            countsBefore.protectionFullRebuilds
        )
        XCTAssertEqual(
            countsAfter.protectionPathAdjustments
                - countsBefore.protectionPathAdjustments,
            4_000
        )
    }

    func testMemoryCacheReplacementRetiresOnlyPreviousContentsOffMainThread() async {
        let cache = DownloadableMediaMemoryCache(decodedDescriptorCount: 2)
        let retiredImage = makeImage(.orange)
        let activeImage = makeImage(.green)
        cache.insert(
            retiredImage,
            forKey: "retired",
            collectionId: "collection"
        )

        cache.clear()
        cache.insert(
            activeImage,
            forKey: "active",
            collectionId: "collection"
        )
        let retirementRanOnMainThread = await cache.waitForRetirementForTesting()

        XCTAssertEqual(retirementRanOnMainThread, false)
        XCTAssertNil(cache.image(forKey: "retired"))
        XCTAssertTrue(cache.image(forKey: "active") === activeImage)
    }

    func testMemoryWarningDoesNotClearNewerCachedImage() async {
        let descriptor = makeDescriptor(name: "post-memory-warning")
        let image = makeImage(.magenta)
        let cache = DownloadableMediaCache.shared
        defer {
            cache.resetDecodedImagesForTesting()
            cache.cancelAllDownloads()
        }

        cache.handleMemoryWarningForTesting()
        cache.installMemoryCachedImageForTesting(image, for: descriptor)
        _ = await cache.waitForDecodedImageRetirementForTesting()

        XCTAssertTrue(cache.cachedDecodedImage(for: descriptor) === image)
    }

    func testMemoryWarningPreservesActiveAnimatedMediaDownload() {
        let descriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "memory-warning-foreground-\(UUID())",
            tokenId: "0",
            tokenIndex: 0,
            media: .animatedImage(
                url: URL(fileURLWithPath: "/memory-warning-\(UUID()).gif"),
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

    func testClearingWindowDropsPendingVariantDuringRunningDecode()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "cleared-window-decode")
        let ownerID = UUID()
        let variant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: variant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("cleared window decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        XCTAssertTrue(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: variant
        ))

        fixture.cache.clearActiveWindow(ownerId: ownerID)

        XCTAssertFalse(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: variant
        ))
    }

    func testMemoryWarningDropsPendingVariantDuringRunningDecode()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "memory-warning-decode")
        let ownerID = UUID()
        let variant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: variant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("memory warning decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        XCTAssertTrue(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: variant
        ))

        fixture.cache.handleMemoryWarningForTesting()

        XCTAssertFalse(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: variant
        ))
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.cyan))
        )
        XCTAssertTrue(didComplete)
        try await waitForControlledEvent("memory warning decode completion") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
        XCTAssertNil(fixture.cache.cachedDecodedImage(
            for: descriptor,
            variant: variant
        ))
    }

    func testCachedFileOnlyWindowDoesNotLeaveForegroundDecodeWork() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "file-only-window")
        let ownerID = UUID()
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.cyan).pngData()).write(to: fileURL)
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [],
                adjacentDescriptor: nil,
                includesCurrentInDecodedDescriptors: false
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("file-only window work") {
            try await fixture.cache.waitForWindowWorkForTesting()
        }

        XCTAssertFalse(fixture.cache.hasForegroundFileWorkForTesting(
            for: descriptor
        ))
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 0)
    }

    func testRunningDecodeCachesAfterDemandMovesToFileOnlyWindow()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "running-decode-file-window")
        let ownerID = UUID()
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        let recorder = DecodedImageAvailabilityRecorder()
        let observer = fixture.notificationCenter.addObserver(
            forName: .downloadableMediaCacheDecodedImageDidBecomeAvailable,
            object: nil,
            queue: nil
        ) { notification in
            guard let availability = notification.object
                as? DownloadableMediaCacheDecodedImageAvailability else {
                return
            }
            recorder.record(availability)
        }
        defer {
            fixture.notificationCenter.removeObserver(observer)
            fixture.cache.clearActiveWindow(ownerId: ownerID)
        }

        let imageTask = Task { @MainActor in
            await fixture.cache.image(for: descriptor)
        }
        try await waitForControlledEvent("running file-window decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [],
                adjacentDescriptor: nil,
                includesCurrentInDecodedDescriptors: false
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("file-only window switch") {
            try await fixture.cache.waitForWindowWorkForTesting()
        }

        imageTask.cancel()
        let cancelledImage = try await waitForControlledTaskValue(
            imageTask,
            event: "cancelled running decode demand"
        )
        try await waitForControlledEvent("running decode demand removal") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 0
            )
        }
        XCTAssertNil(cancelledImage)
        XCTAssertTrue(fixture.cache.hasActiveImageDecodeForTesting(
            for: descriptor
        ))

        let decodedImage = makeImage(.cyan)
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: decodedImage)
        )
        XCTAssertTrue(didComplete)
        let expectedAvailability = DownloadableMediaCacheDecodedImageAvailability(
            collectionId: descriptor.collectionId,
            tokenIndex: descriptor.tokenIndex
        )
        try await waitForControlledEvent("file-window decoded availability") {
            while !recorder.values.contains(expectedAvailability) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertTrue(
            fixture.cache.cachedDecodedImage(for: descriptor) === decodedImage
        )
        XCTAssertEqual(recorder.values, [expectedAvailability])
    }

    func testDenseWindowPredecodeUsesDenseVariantAndReusesIt() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "dense-window")
        let ownerID = UUID()
        let variant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        let window = PlayerDownloadableMediaWindow(
            currentDescriptor: descriptor,
            descriptors: [descriptor],
            decodedDescriptors: [descriptor],
            adjacentDescriptor: nil,
            decodeVariant: variant
        )
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        fixture.cache.prepareWindow(window, ownerId: ownerID)
        try await waitForControlledEvent("dense decode start") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let variants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(variants, [variant])
        let didCompleteDecode = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.orange))
        )
        XCTAssertTrue(didCompleteDecode)
        try await waitForControlledEvent("dense image cache") {
            while await MainActor.run(body: {
                fixture.cache.cachedDecodedImage(
                    for: descriptor,
                    variant: variant
                ) == nil
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertNotNil(fixture.cache.cachedDecodedImage(
            for: descriptor,
            variant: variant
        ))
        XCTAssertNil(fixture.cache.cachedDecodedImage(for: descriptor))

        fixture.cache.prepareWindow(window, ownerId: ownerID)
        try await waitForControlledEvent("reused dense window work") {
            try await fixture.cache.waitForWindowWorkForTesting()
        }
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 1)
        XCTAssertFalse(fixture.cache.hasForegroundFileWorkForTesting(
            for: descriptor
        ))
    }

    func testDenseWindowRedownloadUsesCachedVariantWithoutAnotherDecode()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "dense-window-redownload")
        let ownerID = UUID()
        let variant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        let imageTask = Task { @MainActor in
            await fixture.cache.imageEntry(
                for: descriptor,
                variant: variant
            )
        }
        try await waitForControlledEvent("dense redownload start") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: variant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("dense redownload window") {
            try await fixture.cache.waitForWindowWorkForTesting()
        }

        let cachedImage = makeImage(.purple)
        fixture.cache.installDecodedImageForTesting(
            cachedImage,
            for: descriptor,
            variant: variant
        )
        let didCompleteDownload = await fixture.downloader.succeed(
            requestID: requestID,
            data: Data("dense".utf8)
        )
        let entry = try await waitForControlledTaskValue(
            imageTask,
            event: "cached dense redownload completion"
        )
        let decodeCount = await fixture.decoder.startedDecodeCount()

        XCTAssertTrue(didCompleteDownload)
        XCTAssertTrue(entry?.image === cachedImage)
        XCTAssertEqual(entry?.variant, variant)
        XCTAssertEqual(decodeCount, 0)
    }

    func testCooperativeWindowsDecodeDenseThenFullForSameFile() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(
            name: "cooperative-variants",
            collectionId: "cooperative-variant-window",
            tokenIndex: 0
        )
        let denseOwnerID = UUID()
        let fullOwnerID = UUID()
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 260
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer {
            fixture.cache.clearActiveWindow(ownerId: denseOwnerID)
            fixture.cache.clearActiveWindow(ownerId: fullOwnerID)
        }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: denseVariant
            ),
            ownerId: denseOwnerID,
            ownership: .cooperative(.macCollectionBrowser)
        )
        try await waitForControlledEvent("dense cooperative decode start") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: .full
            ),
            ownerId: fullOwnerID,
            ownership: .cooperative(.macPlayerPager)
        )
        try await waitForControlledEvent("full cooperative window work") {
            try await fixture.cache.waitForWindowWorkForTesting()
        }
        XCTAssertTrue(fixture.cache.hasForegroundWorkForTesting(
            for: descriptor
        ))
        let didCompleteDense = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.orange))
        )
        XCTAssertTrue(didCompleteDense)
        try await waitForControlledEvent("full cooperative decode start") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }
        XCTAssertTrue(fixture.cache.hasForegroundWorkForTesting(
            for: descriptor
        ))

        let variants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(variants, [denseVariant, .full])
        let didCompleteFull = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.blue))
        )
        XCTAssertTrue(didCompleteFull)
        try await waitForControlledEvent("full image cache") {
            while await MainActor.run(body: {
                fixture.cache.cachedDecodedImage(for: descriptor) == nil
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertNotNil(fixture.cache.cachedDecodedImage(
            for: descriptor,
            variant: denseVariant
        ))
        XCTAssertNotNil(fixture.cache.cachedDecodedImage(for: descriptor))
        XCTAssertFalse(fixture.cache.hasForegroundWorkForTesting(
            for: descriptor
        ))
        XCTAssertFalse(fixture.cache.hasForegroundFileWorkForTesting(
            for: descriptor
        ))
    }

    func testFollowUpDemandDecodeRunsBeforeQueuedPrefetch() async throws {
        let fixture = try makeControlledCacheFixture()
        let collectionID = "follow-up-priority"
        let target = makeDescriptor(
            name: "follow-up-target",
            collectionId: collectionID,
            tokenIndex: 0
        )
        let prefetchDescriptors = (1...2).map { index in
            makeDescriptor(
                name: "follow-up-prefetch-\(index)",
                collectionId: collectionID,
                tokenIndex: index
            )
        }
        let descriptors = [target] + prefetchDescriptors
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 140
        )
        for descriptor in descriptors {
            let fileURL = fixture.cache.cachedFileURLForTesting(
                for: descriptor
            )
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        }
        let ownerID = UUID()
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: target,
                descriptors: descriptors,
                decodedDescriptors: descriptors,
                adjacentDescriptor: nil,
                decodeVariant: denseVariant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("initial target decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        try await fixture.cache.waitForWindowWorkForTesting()
        XCTAssertTrue(prefetchDescriptors.allSatisfy {
            fixture.cache.hasActiveImageDecodeForTesting(for: $0)
        })

        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: target, variant: .full)
        }
        defer { fullTask.cancel() }
        try await waitForControlledEvent("follow-up full demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: target,
                expectedCount: 1
            )
        }
        let didCompleteDense = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(
                image: makeImage(.purple)
            )
        )
        XCTAssertTrue(didCompleteDense)
        try await waitForControlledEvent("prioritized follow-up decode") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }

        let startedURLs = await fixture.decoder.startedDecodeFileURLs()
        XCTAssertEqual(
            Array(startedURLs.prefix(2)),
            [
                fixture.cache.cachedFileURLForTesting(for: target),
                fixture.cache.cachedFileURLForTesting(for: target),
            ]
        )
        let startedVariants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(Array(startedVariants.prefix(2)), [denseVariant, .full])

        let fullImage = makeImage(.cyan)
        let didCompleteFull = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: fullImage)
        )
        XCTAssertTrue(didCompleteFull)
        let entry = try await waitForControlledTaskValue(
            fullTask,
            event: "prioritized follow-up completion"
        )
        XCTAssertTrue(entry?.image === fullImage)
    }

    func testActualFullDecodeSatisfiesPendingFullWindow() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "actual-full-variant")
        let denseOwnerID = UUID()
        let fullOwnerID = UUID()
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer {
            fixture.cache.clearActiveWindow(ownerId: denseOwnerID)
            fixture.cache.clearActiveWindow(ownerId: fullOwnerID)
        }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: denseVariant
            ),
            ownerId: denseOwnerID,
            ownership: .cooperative(.macCollectionBrowser)
        )
        try await waitForControlledEvent("small source decode start") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: .full
            ),
            ownerId: fullOwnerID,
            ownership: .cooperative(.macPlayerPager)
        )
        try await waitForControlledEvent("actual full window work") {
            try await fixture.cache.waitForWindowWorkForTesting()
        }
        XCTAssertTrue(fixture.cache.hasForegroundWorkForTesting(
            for: descriptor
        ))
        let expectedImage = makeImage(.purple)
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(
                image: expectedImage,
                variant: .full
            )
        )
        XCTAssertTrue(didComplete)
        try await waitForControlledEvent("small source decode completion") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 1)
        XCTAssertTrue(fixture.cache.cachedDecodedImage(
            for: descriptor,
            variant: .full
        ) === expectedImage)
        let denseEntry = fixture.cache.cachedDecodedImageEntry(
            for: descriptor,
            variant: denseVariant
        )
        XCTAssertTrue(denseEntry?.image === expectedImage)
        XCTAssertEqual(denseEntry?.variant, .full)
        XCTAssertFalse(fixture.cache.hasForegroundWorkForTesting(
            for: descriptor
        ))
    }

    func testForegroundRequirementUsesLiveDemandOrderAndCancellation()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "live-foreground-requirement")
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer { fixture.cache.cancelAllDownloads() }

        let denseTask = Task { @MainActor in
            await fixture.cache.image(
                for: descriptor,
                variant: denseVariant
            )
        }
        try await waitForControlledEvent("dense foreground decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let fullTask = Task { @MainActor in
            await fixture.cache.image(for: descriptor, variant: .full)
        }
        try await waitForControlledEvent("full foreground demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 2
            )
        }

        fixture.cache.prioritizeForegroundImageForTesting(
            descriptor,
            requiredDecodeVariant: .full
        )
        fixture.cache.prioritizeForegroundImageForTesting(
            descriptor,
            requiredDecodeVariant: denseVariant
        )
        let denseImage = makeImage(.purple)
        let didCompleteDense = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: denseImage)
        )
        XCTAssertTrue(didCompleteDense)
        let deliveredDenseImage = try await waitForControlledTaskValue(
            denseTask,
            event: "dense foreground completion"
        )
        XCTAssertTrue(deliveredDenseImage === denseImage)
        try await waitForControlledEvent("full foreground decode") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }
        XCTAssertTrue(fixture.cache.hasForegroundWorkForTesting(
            for: descriptor
        ))

        fullTask.cancel()
        _ = try await waitForControlledTaskValue(
            fullTask,
            event: "full demand cancellation"
        )
        try await waitForControlledEvent("foreground demand removal") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 0
            )
        }
        XCTAssertFalse(fixture.cache.hasForegroundWorkForTesting(
            for: descriptor
        ))
        await fixture.decoder.cancelAll()
    }

    func testLargerDenseDecodeCompletesSmallerDenseDemand() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "compatible-dense-demands")
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        let expectedImage = makeImage(.purple)

        let largeTask = Task { @MainActor in
            await fixture.cache.imageEntry(
                for: descriptor,
                variant: .downsampled(maxPixelWidth: 260)
            )
        }
        try await waitForControlledEvent("large dense demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 1
            )
        }
        let smallTask = Task { @MainActor in
            await fixture.cache.imageEntry(
                for: descriptor,
                variant: .downsampled(maxPixelWidth: 140)
            )
        }
        try await waitForControlledEvent("small dense demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 2
            )
        }
        try await waitForControlledEvent("compatible dense decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: expectedImage)
        )
        XCTAssertTrue(didComplete)

        let largeEntry = try await waitForControlledTaskValue(
            largeTask,
            event: "large dense completion"
        )
        let smallEntry = try await waitForControlledTaskValue(
            smallTask,
            event: "small dense completion"
        )
        XCTAssertTrue(largeEntry?.image === expectedImage)
        XCTAssertTrue(smallEntry?.image === expectedImage)
        XCTAssertEqual(
            largeEntry?.variant,
            .downsampled(maxPixelWidth: 260)
        )
        XCTAssertEqual(
            smallEntry?.variant,
            .downsampled(maxPixelWidth: 260)
        )
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 1)
    }

    func testOverlappingCachedFileRequestsStartStrongestLiveDecode()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "overlapping-variant-demands")
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 140
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)

        let denseTask = Task { @MainActor in
            await fixture.cache.imageEntry(
                for: descriptor,
                variant: denseVariant
            )
        }
        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: descriptor, variant: .full)
        }
        defer {
            denseTask.cancel()
            fullTask.cancel()
        }
        try await waitForControlledEvent("overlapping image demands") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 2
            )
        }
        try await waitForControlledEvent("strongest live decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }

        let startedVariants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(startedVariants, [.full])
        let image = makeImage(.purple)
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: image)
        )
        XCTAssertTrue(didComplete)
        let denseEntry = try await waitForControlledTaskValue(
            denseTask,
            event: "overlapping dense completion"
        )
        let fullEntry = try await waitForControlledTaskValue(
            fullTask,
            event: "overlapping full completion"
        )

        XCTAssertTrue(denseEntry?.image === image)
        XCTAssertTrue(fullEntry?.image === image)
        XCTAssertEqual(denseEntry?.variant, .full)
        XCTAssertEqual(fullEntry?.variant, .full)
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 1)
    }

    func testQueuedDecodeUpgradesToStrongestDemandBeforeStarting()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let blocker = makeDescriptor(name: "decode-upgrade-blocker")
        let target = makeDescriptor(name: "decode-upgrade-target")
        for descriptor in [blocker, target] {
            let fileURL = fixture.cache.cachedFileURLForTesting(
                for: descriptor
            )
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        }

        let blockerTask = Task { @MainActor in
            await fixture.cache.image(for: blocker)
        }
        try await waitForControlledEvent("blocking decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }

        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 140
        )
        let denseTask = Task { @MainActor in
            await fixture.cache.imageEntry(
                for: target,
                variant: denseVariant
            )
        }
        try await waitForControlledEvent("queued dense decode") {
            while await MainActor.run(body: {
                !fixture.cache.hasActiveImageDecodeForTesting(for: target)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: target, variant: .full)
        }
        try await waitForControlledEvent("full decode demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: target,
                expectedCount: 2
            )
        }
        let decodeCountBeforeUpgrade = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCountBeforeUpgrade, 1)

        let didCompleteBlocker = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(
                image: makeImage(.cyan)
            )
        )
        XCTAssertTrue(didCompleteBlocker)
        _ = try await waitForControlledTaskValue(
            blockerTask,
            event: "blocking decode completion"
        )
        try await waitForControlledEvent("upgraded decode") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }
        let startedVariants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(startedVariants, [.full, .full])

        let targetImage = makeImage(.purple)
        let didCompleteTarget = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: targetImage)
        )
        XCTAssertTrue(didCompleteTarget)
        let denseEntry = try await waitForControlledTaskValue(
            denseTask,
            event: "dense upgraded completion"
        )
        let fullEntry = try await waitForControlledTaskValue(
            fullTask,
            event: "full upgraded completion"
        )

        XCTAssertTrue(denseEntry?.image === targetImage)
        XCTAssertTrue(fullEntry?.image === targetImage)
        XCTAssertEqual(denseEntry?.variant, .full)
        XCTAssertEqual(fullEntry?.variant, .full)
        let finalDecodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(finalDecodeCount, 2)
    }

    func testQueuedDecodeDowngradesToWindowVariantAfterDemandCancellation()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let blocker = makeDescriptor(name: "decode-downgrade-blocker")
        let target = makeDescriptor(name: "decode-downgrade-target")
        let ownerID = UUID()
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 140
        )
        for descriptor in [blocker, target] {
            let fileURL = fixture.cache.cachedFileURLForTesting(
                for: descriptor
            )
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        }
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        let blockerTask = Task { @MainActor in
            await fixture.cache.image(for: blocker)
        }
        try await waitForControlledEvent("blocking downgrade decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: target,
                descriptors: [target],
                decodedDescriptors: [target],
                adjacentDescriptor: nil,
                decodeVariant: denseVariant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("queued window decode") {
            while await MainActor.run(body: {
                !fixture.cache.hasActiveImageDecodeForTesting(for: target)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: target, variant: .full)
        }
        try await waitForControlledEvent("queued full demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: target,
                expectedCount: 1
            )
        }
        fullTask.cancel()
        let cancelledEntry = try await waitForControlledTaskValue(
            fullTask,
            event: "cancelled queued full demand"
        )
        XCTAssertNil(cancelledEntry)
        try await waitForControlledEvent("removed queued full demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: target,
                expectedCount: 0
            )
        }

        let didCompleteBlocker = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(
                image: makeImage(.cyan)
            )
        )
        XCTAssertTrue(didCompleteBlocker)
        _ = try await waitForControlledTaskValue(
            blockerTask,
            event: "blocking downgrade completion"
        )
        try await waitForControlledEvent("downgraded window decode") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }
        let startedVariants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(startedVariants, [.full, denseVariant])

        let didCompleteTarget = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(
                image: makeImage(.purple)
            )
        )
        XCTAssertTrue(didCompleteTarget)
    }

    func testDispatchedDecodeUpgradesBeforeGenerationStarts() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "dispatched-decode-upgrade")
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 140
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        await fixture.decoder.suspendDecodeStarts()

        let denseTask = Task { @MainActor in
            await fixture.cache.imageEntry(
                for: descriptor,
                variant: denseVariant
            )
        }
        try await waitForControlledEvent("dispatched dense decode") {
            await fixture.decoder.waitForDecodeAttemptCount(1)
        }
        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: descriptor, variant: .full)
        }
        try await waitForControlledEvent("dispatched full demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 2
            )
        }

        await fixture.decoder.resumeDecodeStarts()
        try await waitForControlledEvent("replaced full decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let startedVariants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(startedVariants, [.full])

        let image = makeImage(.purple)
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: image)
        )
        XCTAssertTrue(didComplete)
        let denseEntry = try await waitForControlledTaskValue(
            denseTask,
            event: "dispatched dense completion"
        )
        let fullEntry = try await waitForControlledTaskValue(
            fullTask,
            event: "dispatched full completion"
        )
        XCTAssertTrue(denseEntry?.image === image)
        XCTAssertTrue(fullEntry?.image === image)
        XCTAssertEqual(denseEntry?.variant, .full)
        XCTAssertEqual(fullEntry?.variant, .full)
    }

    func testCancelledDispatchedFullDecodeRetiresWhenWindowVariantIsCached()
        async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "dispatched-decode-retirement")
        let ownerID = UUID()
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 140
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        fixture.cache.installDecodedImageForTesting(
            makeImage(.cyan),
            for: descriptor,
            variant: denseVariant
        )
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: denseVariant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("cached dense window") {
            try await fixture.cache.waitForWindowWorkForTesting()
        }
        await fixture.decoder.suspendDecodeStarts()

        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: descriptor, variant: .full)
        }
        try await waitForControlledEvent("dispatched full decode") {
            await fixture.decoder.waitForDecodeAttemptCount(1)
        }
        fullTask.cancel()
        let cancelledEntry = try await waitForControlledTaskValue(
            fullTask,
            event: "dispatched full cancellation"
        )
        XCTAssertNil(cancelledEntry)
        try await waitForControlledEvent("removed dispatched full demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 0
            )
        }

        await fixture.decoder.resumeDecodeStarts()
        try await waitForControlledEvent("retired dispatched full decode") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
        let startedDecodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(startedDecodeCount, 0)
        XCTAssertNotNil(fixture.cache.cachedDecodedImage(
            for: descriptor,
            variant: denseVariant
        ))
    }

    func testUncachedDecodedImageDoesNotRetryAttemptedWindowVariant() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "rejected-decoded-image")
        let ownerID = UUID()
        let variant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer {
            fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
            fixture.cache.clearActiveWindow(ownerId: ownerID)
        }
        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(false)

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: variant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("rejected image decode start") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(
                image: makeImage(.purple),
                variant: .full
            )
        )
        XCTAssertTrue(didComplete)
        try await waitForControlledEvent("rejected image decode completion") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 1)
        XCTAssertNil(fixture.cache.cachedDecodedImage(
            for: descriptor,
            variant: variant
        ))
    }

    func testUncachedFullOnlyWindowDoesNotRetryDecode() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "rejected-full-only-window")
        let ownerID = UUID()
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer {
            fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
            fixture.cache.clearActiveWindow(ownerId: ownerID)
        }
        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(false)

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: .full
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("rejected full-only decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.purple))
        )
        XCTAssertTrue(didComplete)
        try await waitForControlledEvent("terminal full-only decode") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertNil(fixture.cache.cachedDecodedImage(for: descriptor))
        XCTAssertFalse(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: .full
        ))
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 1)
    }

    func testUncachedDenseDecodeStillCompletesPendingFullRequest() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "rejected-dense-pending-full")
        let ownerID = UUID()
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 260
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer {
            fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
            fixture.cache.clearActiveWindow(ownerId: ownerID)
        }
        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(false)

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: denseVariant
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("rejected dense decode start") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }

        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: descriptor, variant: .full)
        }
        defer { fullTask.cancel() }
        try await waitForControlledEvent("pending full image demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 1
            )
        }

        let didCompleteDense = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.purple))
        )
        XCTAssertTrue(didCompleteDense)
        try await waitForControlledEvent("full decode after dense rejection") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }

        let fullImage = makeImage(.cyan)
        let didCompleteFull = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: fullImage)
        )
        XCTAssertTrue(didCompleteFull)
        let fullEntry = try await waitForControlledTaskValue(
            fullTask,
            event: "full image after dense rejection"
        )
        XCTAssertTrue(fullEntry?.image === fullImage)
        XCTAssertEqual(fullEntry?.variant, .full)
        try await waitForControlledEvent("rejected decode queue drain") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        let startedVariants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(startedVariants, [denseVariant, .full])
    }

    func testUncachedFullDecodeFallsBackToDensePendingVariant() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "rejected-full-with-dense")
        let fullOwnerID = UUID()
        let denseOwnerID = UUID()
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 260
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer {
            fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
            fixture.cache.clearActiveWindow(ownerId: fullOwnerID)
            fixture.cache.clearActiveWindow(ownerId: denseOwnerID)
        }
        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(false)

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: .full
            ),
            ownerId: fullOwnerID,
            ownership: .cooperative(.macPlayerPager)
        )
        try await waitForControlledEvent("rejected full decode start") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: denseVariant
            ),
            ownerId: denseOwnerID,
            ownership: .cooperative(.macCollectionBrowser)
        )
        try await fixture.cache.waitForWindowWorkForTesting()

        let didCompleteFull = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.purple))
        )
        XCTAssertTrue(didCompleteFull)
        try await waitForControlledEvent("dense fallback decode start") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }
        let startedVariants = await fixture.decoder.startedDecodeVariants()
        XCTAssertEqual(startedVariants, [.full, denseVariant])
        XCTAssertNil(fixture.cache.cachedDecodedImage(for: descriptor))

        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
        let denseImage = makeImage(.cyan)
        let didCompleteDense = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: denseImage)
        )
        XCTAssertTrue(didCompleteDense)
        try await waitForControlledEvent("dense fallback image cache") {
            while await MainActor.run(body: {
                fixture.cache.cachedDecodedImage(
                    for: descriptor,
                    variant: denseVariant
                ) == nil
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
        try await waitForControlledEvent("dense fallback completion") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertTrue(fixture.cache.cachedDecodedImage(
            for: descriptor,
            variant: denseVariant
        ) === denseImage)
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 2)
    }

    func testWindowRefreshDuringFullCallbackDecodeSettlesDenseWork() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "refreshed-dense-window")
        let ownerID = UUID()
        let denseVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 260
        )
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        let window = PlayerDownloadableMediaWindow(
            currentDescriptor: descriptor,
            descriptors: [descriptor],
            decodedDescriptors: [descriptor],
            adjacentDescriptor: nil,
            decodeVariant: denseVariant
        )
        defer {
            fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
            fixture.cache.clearActiveWindow(ownerId: ownerID)
        }
        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(false)

        fixture.cache.prepareWindow(window, ownerId: ownerID)
        try await waitForControlledEvent("initial dense decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let fullTask = Task { @MainActor in
            await fixture.cache.imageEntry(for: descriptor, variant: .full)
        }
        defer { fullTask.cancel() }
        try await waitForControlledEvent("full callback demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 1
            )
        }

        let didCompleteDense = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: makeImage(.purple))
        )
        XCTAssertTrue(didCompleteDense)
        try await waitForControlledEvent("full callback decode") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }

        fixture.cache.prepareWindow(window, ownerId: ownerID)
        try await fixture.cache.waitForWindowWorkForTesting()
        XCTAssertTrue(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: denseVariant
        ))
        fixture.cache.setDecodedImageCacheAcceptsInsertionsForTesting(true)
        let fullImage = makeImage(.cyan)
        let didCompleteFull = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(
                image: fullImage,
                variant: .full
            )
        )
        XCTAssertTrue(didCompleteFull)
        let fullEntry = try await waitForControlledTaskValue(
            fullTask,
            event: "refreshed full callback"
        )
        XCTAssertTrue(fullEntry?.image === fullImage)
        try await waitForControlledEvent("refreshed decode drain") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertFalse(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: denseVariant
        ))
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 2)
    }

    func testDecodeFailureDoesNotSettlePendingWindowVariant() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "failed-window-decode")
        let ownerID = UUID()
        let fileURL = fixture.cache.cachedFileURLForTesting(for: descriptor)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try XCTUnwrap(makeImage(.orange).pngData()).write(to: fileURL)
        defer { fixture.cache.clearActiveWindow(ownerId: ownerID) }

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [descriptor],
                adjacentDescriptor: nil,
                decodeVariant: .full
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("failed window decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let didComplete = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: nil)
        )
        XCTAssertTrue(didComplete)
        try await waitForControlledEvent("failed decode cleanup") {
            while await MainActor.run(body: {
                fixture.cache.hasActiveImageDecodeForTesting(for: descriptor)
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        }

        XCTAssertTrue(fixture.cache.hasPendingWindowDecodeVariantForTesting(
            for: descriptor,
            variant: .full
        ))
    }

    func testDecodedVariantMetadataRetainsResidentImagesPastSoftCapacity() {
        let cache = DownloadableMediaCache.shared
        cache.resetDecodedImagesForTesting()
        defer { cache.resetDecodedImagesForTesting() }
        let capacity = cache.decodedVariantMetadataCountsForTesting().capacity
        let retainedDescriptor = makeDescriptor(name: "metadata-retained")
        let retainedImage = makeImage(.cyan)
        let variant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 320
        )

        cache.installDecodedImageForTesting(
            retainedImage,
            for: retainedDescriptor,
            variant: variant
        )

        for index in 0..<(capacity + 20) {
            cache.installDecodedImageForTesting(
                makeImage(.purple),
                for: makeDescriptor(name: "metadata-\(index)"),
                variant: variant
            )
        }

        let counts = cache.decodedVariantMetadataCountsForTesting()
        XCTAssertEqual(counts.count, counts.capacity + 21)
        let retainedEntry = cache.anyCachedDecodedImageEntry(
            for: retainedDescriptor
        )
        XCTAssertTrue(retainedEntry?.image === retainedImage)
        XCTAssertEqual(retainedEntry?.variant, variant)
    }

    func testFileLeasesProtectFilesUntilTheLastLeaseReleases() async throws {
        let descriptor = makeDescriptor(name: "leased-file")
        guard let fixture = try? makeControlledCacheFixture() else {
            XCTFail("Could not create controlled cache fixture")
            return
        }
        let firstLease = fixture.cache.fileLease(for: descriptor)
        let secondLease = fixture.cache.fileLease(for: descriptor)
        let fileName = fixture.cache.cachedFileURLForTesting(
            for: descriptor
        ).lastPathComponent
        let expectedFileNames = Set([
            fileName,
            fileName + DownloadableMediaCacheLayout.downloadedMediaMetadataFileSuffix,
        ])
        let expectedDiskPaths = Set(
            fixture.layout.diskPaths(for: descriptor)
        )

        XCTAssertTrue(expectedFileNames.isSubset(of:
            fixture.cache.fileNamesProtectedFromEvictionForTesting(
                collectionId: descriptor.collectionId,
                allowedFileNames: []
            )
        ))
        XCTAssertTrue(expectedDiskPaths.isSubset(of:
            fixture.cache.protectedDiskPathsForTesting()
        ))

        fixture.cache.cancelAllDownloads()

        firstLease.release()
        try await waitForControlledEvent("first file lease release") {
            await fixture.cache.waitForFileLeaseCountForTesting(
                for: descriptor,
                expectedCount: 1
            )
        }

        XCTAssertTrue(expectedFileNames.isSubset(of:
            fixture.cache.fileNamesProtectedFromEvictionForTesting(
                collectionId: descriptor.collectionId,
                allowedFileNames: []
            )
        ))
        XCTAssertTrue(expectedDiskPaths.isSubset(of:
            fixture.cache.protectedDiskPathsForTesting()
        ))

        secondLease.release()
        try await waitForControlledEvent("final file lease release") {
            await fixture.cache.waitForFileLeaseCountForTesting(
                for: descriptor,
                expectedCount: 0
            )
        }

        XCTAssertTrue(fixture.cache.fileNamesProtectedFromEvictionForTesting(
            collectionId: descriptor.collectionId,
            allowedFileNames: []
        ).isEmpty)
        XCTAssertTrue(
            expectedDiskPaths.isDisjoint(
                with: fixture.cache.protectedDiskPathsForTesting()
            )
        )
    }

    func testCancellingImageDemandPreservesSharedFileDownload() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "shared-image-file-demand")
        let fileTask = Task { @MainActor in
            await fixture.cache.file(for: descriptor)
        }
        try await waitForControlledEvent("shared download start") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id
        let imageTask = Task { @MainActor in
            await fixture.cache.image(for: descriptor)
        }
        try await waitForControlledEvent("shared download priority update") {
            await fixture.downloader.waitForPriorityUpdateCount(1)
        }

        XCTAssertEqual(
            fixture.cache.fileDemandCountForTesting(for: descriptor),
            1
        )
        XCTAssertEqual(
            fixture.cache.imageDemandCountForTesting(for: descriptor),
            1
        )

        imageTask.cancel()
        let cancelledImage = try await waitForControlledTaskValue(
            imageTask,
            event: "cancelled shared image request"
        )
        try await waitForControlledEvent("image demand cancellation") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 0
            )
        }

        XCTAssertNil(cancelledImage)
        let didCompleteDownload = await fixture.downloader.succeed(
            requestID: requestID,
            data: Data("shared".utf8)
        )
        let fileURL = try await waitForControlledTaskValue(
            fileTask,
            event: "shared file request completion"
        )
        let downloaderSnapshot = await fixture.downloader.snapshot()
        let decodeCount = await fixture.decoder.startedDecodeCount()

        XCTAssertTrue(didCompleteDownload)
        XCTAssertEqual(
            fileURL?.standardizedFileURL,
            fixture.layout.location(for: descriptor).mediaURL.standardizedFileURL
        )
        XCTAssertEqual(downloaderSnapshot.startedRequestIDs, [requestID])
        XCTAssertFalse(downloaderSnapshot.cancelledRequestIDs.contains(requestID))
        XCTAssertEqual(decodeCount, 0)
        XCTAssertEqual(
            fixture.cache.imageDemandCountForTesting(for: descriptor),
            0
        )
        XCTAssertEqual(
            fixture.cache.fileDemandCountForTesting(for: descriptor),
            0
        )
    }

    func testCancellingLastDemandCancelsDownloader() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "last-demand")
        let fileTask = Task { @MainActor in
            await fixture.cache.file(for: descriptor)
        }
        try await waitForControlledEvent("last-demand download start") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id

        fileTask.cancel()

        let fileURL = try await waitForControlledTaskValue(
            fileTask,
            event: "cancelled last-demand file request"
        )
        try await waitForControlledEvent("last-demand cancellation") {
            await fixture.downloader.waitForCancellation(of: requestID)
        }
        let snapshot = await fixture.downloader.snapshot()
        XCTAssertNil(fileURL)
        XCTAssertEqual(
            fixture.cache.fileDemandCountForTesting(for: descriptor),
            0
        )
        XCTAssertEqual(snapshot.activeRequestCount, 0)
        XCTAssertEqual(snapshot.cancelledRequestIDs, [requestID])
    }

    func testCancelAllPreservesLeasedFileRequest() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "leased-cancel-all")
        let lease = fixture.cache.fileLease(for: descriptor)
        defer { lease.release() }
        let fileTask = Task { @MainActor in
            await fixture.cache.file(for: descriptor)
        }
        try await waitForControlledEvent("leased download start") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id

        fixture.cache.cancelAllDownloads()

        XCTAssertEqual(
            fixture.cache.fileDemandCountForTesting(for: descriptor),
            1
        )
        let didCompleteDownload = await fixture.downloader.succeed(
            requestID: requestID,
            data: Data("leased".utf8)
        )
        let fileURL = try await waitForControlledTaskValue(
            fileTask,
            event: "leased file request completion"
        )
        let snapshot = await fixture.downloader.snapshot()

        XCTAssertTrue(didCompleteDownload)
        XCTAssertEqual(
            fileURL?.standardizedFileURL,
            fixture.layout.location(for: descriptor).mediaURL.standardizedFileURL
        )
        XCTAssertFalse(snapshot.cancelledRequestIDs.contains(requestID))
        XCTAssertEqual(snapshot.activeRequestCount, 0)
    }

    func testExactEvictionInvalidatesOnlyRemovedAvailability() async throws {
        let fixture = try makeControlledCacheFixture()
        let seedStore = DownloadableMediaDiskStore(layout: fixture.layout)
        let protectedDescriptor = makeDescriptor(
            name: "exact-eviction-protected",
            collectionId: "exact-eviction",
            tokenIndex: 0
        )
        let removedDescriptor = makeDescriptor(
            name: "exact-eviction-removed",
            collectionId: "exact-eviction",
            tokenIndex: 1
        )
        let protectedLocation = fixture.layout.location(for: protectedDescriptor)
        let removedLocation = fixture.layout.location(for: removedDescriptor)

        for location in [protectedLocation, removedLocation] {
            let stagedURL = try makeStagedFile(
                Data(location.descriptor.tokenId.utf8),
                name: UUID().uuidString,
                layout: fixture.layout
            )
            let finalization = await seedStore.finalizeDownload(
                at: stagedURL,
                location: location,
                sourceURL: location.descriptor.url
            )
            XCTAssertTrue(finalization.succeeded)
        }

        let protectedExistingURL = await fixture.cache.existingFileURL(
            for: protectedDescriptor
        )
        let removedExistingURL = await fixture.cache.existingFileURL(
            for: removedDescriptor
        )
        XCTAssertEqual(protectedExistingURL, protectedLocation.mediaURL)
        XCTAssertEqual(removedExistingURL, removedLocation.mediaURL)

        let evictionStore = DownloadableMediaDiskStore(layout: fixture.layout)
        let eviction = await evictionStore.evictFilesOutsideWindow(
            collectionId: protectedDescriptor.collectionId,
            protectedFileNames: Set(
                fixture.layout.fileNames(for: protectedDescriptor)
            )
        )
        await fixture.cache.applyRemovedMediaURLsForTesting(
            eviction.removedMediaURLs
        )

        XCTAssertEqual(
            eviction.removedMediaURLs,
            [removedLocation.mediaURL.standardizedFileURL]
        )
        XCTAssertNil(fixture.cache.knownLocalFileURL(for: removedDescriptor))
        XCTAssertEqual(
            fixture.cache.knownLocalFileURL(for: protectedDescriptor),
            protectedLocation.mediaURL
        )
    }

    func testKnownAvailabilityRejectsRemovalBeforeMutationResultIsApplied() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptor = makeDescriptor(name: "removal-frontier")
        let location = fixture.layout.location(for: descriptor)
        let fileTask = Task { @MainActor in
            await fixture.cache.file(for: descriptor)
        }
        try await waitForControlledEvent("removal-frontier download") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id
        let didCompleteDownload = await fixture.downloader.succeed(
            requestID: requestID,
            data: Data("cached".utf8)
        )
        XCTAssertTrue(didCompleteDownload)
        let fileURL = try await waitForControlledTaskValue(
            fileTask,
            event: "removal-frontier file request completion"
        )

        XCTAssertEqual(fileURL, location.mediaURL)
        XCTAssertEqual(
            fixture.cache.knownLocalFileURL(for: descriptor),
            location.mediaURL
        )

        await fixture.cache.removeCachedFileForTesting(for: descriptor)

        XCTAssertNil(fixture.cache.knownLocalFileURL(for: descriptor))
        await fixture.cache.applyRemovedMediaURLsForTesting([
            location.mediaURL
        ])
        XCTAssertNil(fixture.cache.knownLocalFileURL(for: descriptor))
    }

    func testLeaseAcquiredDuringCorruptCleanupCompletesAfterRedownload() async throws {
        let gate = ControlledDownloadableMediaAsyncGate()
        let retainedFailureAcknowledgment =
            DownloadableMediaAsyncRequest<Void>()
        let fixture = try makeControlledCacheFixture(
            beforeCorruptFileRemoval: {
                await gate.pause()
            },
            afterRetainedDecodeFailure: {
                retainedFailureAcknowledgment.finish(())
            }
        )
        addTeardownBlock {
            await gate.resume()
        }
        let descriptor = makeDescriptor(name: "corrupt-with-lease")
        let location = fixture.layout.location(for: descriptor)
        let store = DownloadableMediaDiskStore(layout: fixture.layout)
        let stagedURL = try makeStagedFile(
            Data("corrupt".utf8),
            name: "corrupt",
            layout: fixture.layout
        )
        let finalization = await store.finalizeDownload(
            at: stagedURL,
            location: location,
            sourceURL: descriptor.url
        )
        XCTAssertTrue(finalization.succeeded)
        let existingURL = await fixture.cache.existingFileURL(for: descriptor)
        XCTAssertEqual(existingURL, location.mediaURL)

        let imageTask = Task { @MainActor in
            await fixture.cache.image(for: descriptor)
        }
        try await waitForControlledEvent("corrupt decode start") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let didCompleteCorruptDecode = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: nil)
        )
        XCTAssertTrue(didCompleteCorruptDecode)
        try await waitForControlledEvent("corrupt cleanup pause") {
            await gate.waitUntilPaused()
        }

        let lease = fixture.cache.fileLease(for: descriptor)
        await gate.resume()
        try await waitForControlledEvent("retained failure acknowledgment") {
            await withTaskCancellationHandler {
                await retainedFailureAcknowledgment.wait()
            } onCancel: {
                retainedFailureAcknowledgment.cancel(returning: ())
            }
        }

        XCTAssertEqual(
            fixture.cache.imageDemandCountForTesting(for: descriptor),
            1
        )

        lease.release()
        try await waitForControlledEvent("replacement download start") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id
        let didCompleteRedownload = await fixture.downloader.succeed(
            requestID: requestID,
            data: Data("replacement".utf8)
        )
        XCTAssertTrue(didCompleteRedownload)
        try await waitForControlledEvent("replacement decode start") {
            await fixture.decoder.waitForStartedDecodeCount(2)
        }
        let expectedImage = makeImage(.blue)
        let didCompleteDecodedImage = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: expectedImage)
        )
        XCTAssertTrue(didCompleteDecodedImage)

        let image = try await waitForControlledTaskValue(
            imageTask,
            event: "replacement image request completion"
        )
        XCTAssertTrue(image === expectedImage)
        XCTAssertEqual(
            fixture.cache.imageDemandCountForTesting(for: descriptor),
            0
        )
    }

    func testCancelAllWhileCorruptRemovalIsPausedDoesNotRestartDownload() async throws {
        let gate = ControlledDownloadableMediaAsyncGate()
        let recoveryFinished = DownloadableMediaAsyncRequest<Void>()
        let fixture = try makeControlledCacheFixture(
            beforeCorruptFileRemoval: {
                await gate.pause()
            },
            afterCorruptFileRecovery: {
                recoveryFinished.finish(())
            }
        )
        let descriptor = makeDescriptor(name: "cancel-paused-corrupt-removal")
        let location = fixture.layout.location(for: descriptor)
        let store = DownloadableMediaDiskStore(layout: fixture.layout)
        let stagedURL = try makeStagedFile(
            Data("corrupt".utf8),
            name: "cancel-paused-corrupt-removal",
            layout: fixture.layout
        )
        let finalization = await store.finalizeDownload(
            at: stagedURL,
            location: location,
            sourceURL: descriptor.url
        )
        XCTAssertTrue(finalization.succeeded)
        let existingURL = await fixture.cache.existingFileURL(
            for: descriptor
        )
        XCTAssertEqual(
            existingURL,
            location.mediaURL
        )

        let imageCompletion = DownloadableMediaAsyncRequest<Bool>()
        let imageTask = Task { @MainActor in
            let image = await fixture.cache.image(for: descriptor)
            imageCompletion.finish(image == nil)
        }
        addTeardownBlock {
            imageTask.cancel()
            await gate.resume()
        }
        try await waitForControlledEvent("cancel-paused corrupt decode") {
            await fixture.decoder.waitForStartedDecodeCount(1)
        }
        let didCompleteDecode = await fixture.decoder.completeNext(
            with: DownloadableMediaDecodedImageTransfer(image: nil)
        )
        XCTAssertTrue(didCompleteDecode)
        try await waitForControlledEvent("paused corrupt removal") {
            await gate.waitUntilPaused()
        }

        fixture.cache.cancelAllDownloads()
        let didFinishNil = try await waitForControlledEvent(
            "cancelled paused-corrupt image request"
        ) {
            await withTaskCancellationHandler {
                await imageCompletion.wait()
            } onCancel: {
                imageCompletion.cancel(returning: false)
            }
        }
        XCTAssertTrue(didFinishNil)

        await gate.resume()
        try await waitForControlledEvent("corrupt recovery completion") {
            await withTaskCancellationHandler {
                await recoveryFinished.wait()
            } onCancel: {
                recoveryFinished.cancel(returning: ())
            }
        }

        XCTAssertEqual(
            fixture.cache.imageDemandCountForTesting(for: descriptor),
            0
        )
        XCTAssertFalse(
            fixture.cache.hasForegroundFileWorkForTesting(for: descriptor)
        )
        XCTAssertFalse(
            fixture.cache.hasScheduledFileWorkForTesting(for: descriptor)
        )
        let downloaderSnapshot = await fixture.downloader.snapshot()
        XCTAssertTrue(downloaderSnapshot.startedRequestIDs.isEmpty)
    }

    func testCancellationDuringDownloadFinalizationDoesNotRestoreDemand() async throws {
        let gate = ControlledDownloadableMediaAsyncGate()
        let finalizationFinished = DownloadableMediaAsyncRequest<Void>()
        let fixture = try makeControlledCacheFixture(
            beforeDownloadFinalizationCommit: {
                await gate.pause()
            }
        )
        _ = fixture.notificationCenter.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: nil
        ) { notification in
            guard let change = notification.object
                as? DownloadableMediaCacheFileAvailabilityChange,
                  change == .becameAvailable else {
                return
            }
            finalizationFinished.finish(())
        }
        addTeardownBlock {
            await gate.resume()
        }
        let descriptor = makeDescriptor(name: "cancel-during-finalization")
        let firstTask = Task { @MainActor in
            await fixture.cache.image(for: descriptor)
        }
        try await waitForControlledEvent("finalization download") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let secondTask = Task { @MainActor in
            await fixture.cache.image(for: descriptor)
        }
        try await waitForControlledEvent("shared finalization demand") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 2
            )
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id
        let didCompleteDownload = await fixture.downloader.succeed(
            requestID: requestID,
            data: Data("finalized".utf8)
        )
        XCTAssertTrue(didCompleteDownload)
        try await waitForControlledEvent("paused finalization") {
            await gate.waitUntilPaused()
        }

        firstTask.cancel()
        let firstImage = try await waitForControlledTaskValue(
            firstTask,
            event: "individually cancelled finalization request"
        )
        XCTAssertNil(firstImage)
        try await waitForControlledEvent("individual finalization cancellation") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 1
            )
        }

        fixture.cache.cancelAllDownloads()
        let secondImage = try await waitForControlledTaskValue(
            secondTask,
            event: "global finalization request completion"
        )
        XCTAssertNil(secondImage)
        try await waitForControlledEvent("global finalization cancellation") {
            try await fixture.cache.waitForImageDemandCountForTesting(
                for: descriptor,
                expectedCount: 0
            )
        }
        await gate.resume()
        try await waitForControlledEvent("finalization completion") {
            await withTaskCancellationHandler {
                await finalizationFinished.wait()
            } onCancel: {
                finalizationFinished.cancel(returning: ())
            }
        }
        XCTAssertEqual(
            fixture.cache.imageDemandCountForTesting(for: descriptor),
            0
        )
        XCTAssertFalse(
            fixture.cache.hasScheduledFileWorkForTesting(for: descriptor)
        )
        let decodeCount = await fixture.decoder.startedDecodeCount()
        XCTAssertEqual(decodeCount, 0)
        let snapshot = await fixture.downloader.snapshot()
        XCTAssertEqual(snapshot.startedRequestIDs, [requestID])
    }

    func testDownloadConcurrencyIsLimitedToFour() async throws {
        let fixture = try makeControlledCacheFixture()
        let descriptors = (0..<5).map {
            makeDescriptor(
                name: "download-cap-\($0)",
                collectionId: "download-cap",
                tokenIndex: $0
            )
        }
        let tasks = descriptors.map { descriptor in
            Task { @MainActor in
                await fixture.cache.file(for: descriptor)
            }
        }
        defer { tasks.forEach { $0.cancel() } }

        try await waitForControlledEvent("four concurrent downloads") {
            await fixture.downloader.waitForStartedRequestCount(4)
        }
        var snapshot = await fixture.downloader.snapshot()
        XCTAssertEqual(snapshot.startedRequestIDs.count, 4)
        XCTAssertEqual(snapshot.activeRequestCount, 4)

        let didCompleteFirstDownload = await fixture.downloader.succeed(
            requestID: snapshot.startedRequestIDs[0],
            data: Data("first".utf8)
        )
        XCTAssertTrue(didCompleteFirstDownload)
        try await waitForControlledEvent("fifth queued download") {
            await fixture.downloader.waitForStartedRequestCount(5)
        }
        snapshot = await fixture.downloader.snapshot()
        XCTAssertEqual(snapshot.startedRequestIDs.count, 5)
        XCTAssertEqual(snapshot.activeRequestCount, 4)

        for requestID in snapshot.activeRequestIDs {
            let didCompleteDownload = await fixture.downloader.succeed(
                requestID: requestID,
                data: Data(requestID.uuidString.utf8)
            )
            XCTAssertTrue(didCompleteDownload)
        }
        for task in tasks {
            let fileURL = try await waitForControlledTaskValue(
                task,
                event: "concurrent file request completion"
            )
            XCTAssertNotNil(fileURL)
        }

        let finalSnapshot = await fixture.downloader.snapshot()
        XCTAssertEqual(finalSnapshot.activeRequestCount, 0)
    }

    func testForegroundDemandPromotesAndRestoresWindowPrefetchPriority() async throws {
        let fixture = try makeControlledCacheFixture()
        let ownerID = UUID()
        let collectionID = "priority-window"
        let foregroundDescriptor = makeAnimatedDescriptor(
            name: "priority-foreground",
            collectionId: collectionID,
            tokenIndex: 0
        )
        let prefetchDescriptor = makeAnimatedDescriptor(
            name: "priority-prefetch",
            collectionId: collectionID,
            tokenIndex: 1
        )
        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: foregroundDescriptor,
                descriptors: [foregroundDescriptor, prefetchDescriptor],
                decodedDescriptors: [],
                adjacentDescriptor: prefetchDescriptor
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("foreground window download") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let foregroundStartedRequest = await fixture.downloader.startedRequest(
            for: foregroundDescriptor.url
        )
        let foregroundRequest = try XCTUnwrap(foregroundStartedRequest)

        XCTAssertEqual(foregroundRequest.priority, 1)
        let didCompleteForeground = await fixture.downloader.succeed(
            requestID: foregroundRequest.id,
            data: Data("foreground".utf8)
        )
        XCTAssertTrue(didCompleteForeground)
        try await waitForControlledEvent("window prefetch download") {
            await fixture.downloader.waitForStartedRequestCount(2)
        }
        let prefetchStartedRequest = await fixture.downloader.startedRequest(
            for: prefetchDescriptor.url
        )
        let prefetchRequest = try XCTUnwrap(prefetchStartedRequest)
        XCTAssertEqual(prefetchRequest.priority, 0.5)

        let demandTask = Task { @MainActor in
            await fixture.cache.file(for: prefetchDescriptor)
        }
        let optionalPromotionEvent = try await waitForControlledEvent(
            "foreground demand promotion"
        ) {
            await fixture.downloader.waitForEffectivePriority(
                1,
                requestID: prefetchRequest.id,
                afterRevision: 0
            )
        }
        let promotionEvent = try XCTUnwrap(optionalPromotionEvent)

        demandTask.cancel()
        let cancelledDemandURL = try await waitForControlledTaskValue(
            demandTask,
            event: "cancelled priority demand"
        )
        XCTAssertNil(cancelledDemandURL)
        let optionalRestorationEvent = try await waitForControlledEvent(
            "prefetch priority restoration"
        ) {
            await fixture.downloader.waitForEffectivePriority(
                0.5,
                requestID: prefetchRequest.id,
                afterRevision: promotionEvent.effectiveRevision
            )
        }
        let restorationEvent = try XCTUnwrap(optionalRestorationEvent)

        XCTAssertEqual(promotionEvent.priority, 1)
        XCTAssertEqual(promotionEvent.effectivePriority, 1)
        XCTAssertGreaterThan(promotionEvent.effectiveRevision, 0)
        XCTAssertEqual(restorationEvent.priority, 0.5)
        XCTAssertEqual(restorationEvent.effectivePriority, 0.5)
        XCTAssertGreaterThan(
            restorationEvent.effectiveRevision,
            promotionEvent.effectiveRevision
        )
    }

    func testControlledDownloaderRejectsStalePriorityRevision() async throws {
        let fixture = try makeControlledCacheFixture()
        let requestID = UUID()
        let request = DownloadableMediaDownloadRequest(
            id: requestID,
            sourceURL: URL(string: "https://example.com/stale-priority.gif")!,
            priority: 0.5,
            stagingRoot: fixture.layout.stagingRoot
        )
        let downloadTask = Task {
            await fixture.downloader.download(request)
        }
        try await waitForControlledEvent("stale-priority download") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }

        await fixture.downloader.setPriority(
            0.25,
            for: requestID,
            revision: 2
        )
        await fixture.downloader.setPriority(
            1,
            for: requestID,
            revision: 1
        )
        let events = await fixture.downloader.snapshot().priorityEvents

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].effectivePriority, 0.25)
        XCTAssertEqual(events[0].effectiveRevision, 2)
        XCTAssertEqual(events[1].priority, 1)
        XCTAssertEqual(events[1].effectivePriority, 0.25)
        XCTAssertEqual(events[1].effectiveRevision, 2)

        await fixture.downloader.cancel(requestID: requestID)
        let result = try await waitForControlledTaskValue(
            downloadTask,
            event: "cancelled stale-priority download"
        )
        guard case .cancelled? = result.failure else {
            XCTFail("Expected the controlled download to be cancelled")
            return
        }
    }

    func testWrongOwnerCannotClearExclusiveWindow() async throws {
        let fixture = try makeControlledCacheFixture()
        let ownerID = UUID()
        let descriptor = makeAnimatedDescriptor(
            name: "wrong-owner",
            collectionId: "exclusive-window",
            tokenIndex: 0
        )
        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [],
                adjacentDescriptor: nil
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("exclusive window download") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id

        fixture.cache.clearActiveWindow(ownerId: UUID())

        XCTAssertTrue(
            fixture.cache.hasForegroundFileWorkForTesting(for: descriptor)
        )
        let snapshot = await fixture.downloader.snapshot()
        XCTAssertTrue(snapshot.activeRequestIDs.contains(requestID))
    }

    func testSuspendingExclusiveWindowCancelsForegroundDownload() async throws {
        let fixture = try makeControlledCacheFixture()
        let ownerID = UUID()
        let descriptor = makeAnimatedDescriptor(
            name: "suspended-window",
            collectionId: "exclusive-window",
            tokenIndex: 0
        )
        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: descriptor,
                descriptors: [descriptor],
                decodedDescriptors: [],
                adjacentDescriptor: nil
            ),
            ownerId: ownerID
        )
        try await waitForControlledEvent("suspended window download") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let requestID = await fixture.downloader.startedRequest(at: 0).id

        fixture.cache.suspendActiveWindow(ownerId: ownerID)
        try await waitForControlledEvent("suspended window cancellation") {
            await fixture.downloader.waitForCancellation(of: requestID)
        }

        XCTAssertFalse(
            fixture.cache.hasForegroundFileWorkForTesting(for: descriptor)
        )
        let snapshot = await fixture.downloader.snapshot()
        XCTAssertFalse(snapshot.activeRequestIDs.contains(requestID))
    }

    func testNewestCooperativeWindowOwnsForegroundSelection() async throws {
        let fixture = try makeControlledCacheFixture()
        let firstOwnerID = UUID()
        let secondOwnerID = UUID()
        let collectionID = "cooperative-window"
        let firstDescriptor = makeAnimatedDescriptor(
            name: "cooperative-first",
            collectionId: collectionID,
            tokenIndex: 0
        )
        let secondDescriptor = makeAnimatedDescriptor(
            name: "cooperative-second",
            collectionId: collectionID,
            tokenIndex: 1
        )
        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: firstDescriptor,
                descriptors: [firstDescriptor],
                decodedDescriptors: [],
                adjacentDescriptor: nil
            ),
            ownerId: firstOwnerID,
            ownership: .cooperative(.macPlayerPager)
        )
        try await waitForControlledEvent("first cooperative window") {
            await fixture.downloader.waitForStartedRequestCount(1)
        }
        let optionalFirstRequest = await fixture.downloader.latestStartedRequest(
            for: firstDescriptor.url
        )
        let firstRequest = try XCTUnwrap(optionalFirstRequest)

        fixture.cache.prepareWindow(
            PlayerDownloadableMediaWindow(
                currentDescriptor: secondDescriptor,
                descriptors: [secondDescriptor],
                decodedDescriptors: [],
                adjacentDescriptor: nil
            ),
            ownerId: secondOwnerID,
            ownership: .cooperative(.macCollectionBrowser)
        )
        try await waitForControlledEvent("newest cooperative window") {
            await fixture.downloader.waitForStartedRequestCount(2)
        }
        try await waitForControlledEvent("old cooperative prefetch cancellation") {
            await fixture.downloader.waitForCancellation(of: firstRequest.id)
        }
        let optionalSecondRequest = await fixture.downloader.latestStartedRequest(
            for: secondDescriptor.url
        )
        let secondRequest = try XCTUnwrap(optionalSecondRequest)

        XCTAssertFalse(
            fixture.cache.hasForegroundFileWorkForTesting(
                for: firstDescriptor
            )
        )
        XCTAssertTrue(
            fixture.cache.hasForegroundFileWorkForTesting(
                for: secondDescriptor
            )
        )
        let cancellationSnapshot = await fixture.downloader.snapshot()
        XCTAssertTrue(
            cancellationSnapshot.cancelledRequestIDs.contains(firstRequest.id)
        )

        let didCompleteSecond = await fixture.downloader.succeed(
            requestID: secondRequest.id,
            data: Data("second".utf8)
        )
        XCTAssertTrue(didCompleteSecond)
        try await waitForControlledEvent("old cooperative prefetch requeue") {
            await fixture.downloader.waitForStartedRequestCount(3)
        }
        let optionalRequeuedRequest = await fixture.downloader.latestStartedRequest(
            for: firstDescriptor.url
        )
        let requeuedRequest = try XCTUnwrap(optionalRequeuedRequest)
        XCTAssertNotEqual(requeuedRequest.id, firstRequest.id)
        XCTAssertEqual(requeuedRequest.priority, 0.5)
    }

    private func makeControlledCacheFixture(
        beforeCorruptFileRemoval:
            (@Sendable () async -> Void)? = nil,
        afterCorruptFileRecovery:
            (@Sendable () async -> Void)? = nil,
        afterRetainedDecodeFailure:
            (@Sendable () async -> Void)? = nil,
        beforeDownloadFinalizationCommit:
            (@Sendable () async -> Void)? = nil
    ) throws -> (
        rootURL: URL,
        layout: DownloadableMediaCacheLayout,
        cache: DownloadableMediaCache,
        downloader: ControlledDownloadableMediaDownloader,
        decoder: ControlledDownloadableMediaImageDecoder,
        notificationCenter: NotificationCenter
    ) {
        let rootURL = try makeTemporaryDirectory()
        let layout = DownloadableMediaCacheLayout(
            cacheRoot: rootURL.appendingPathComponent(
                "cache",
                isDirectory: true
            ),
            stagingRoot: rootURL.appendingPathComponent(
                "staging",
                isDirectory: true
            )
        )
        let downloader = ControlledDownloadableMediaDownloader()
        let decoder = ControlledDownloadableMediaImageDecoder()
        let notificationCenter = NotificationCenter()
        let cache: DownloadableMediaCache
        if beforeCorruptFileRemoval != nil
            || afterCorruptFileRecovery != nil
            || afterRetainedDecodeFailure != nil
            || beforeDownloadFinalizationCommit != nil {
            cache = DownloadableMediaCache(
                layout: layout,
                downloader: downloader,
                imageDecoder: decoder,
                notificationCenter: notificationCenter,
                beforeCorruptFileRemovalForTesting:
                    beforeCorruptFileRemoval,
                afterCorruptFileRecoveryForTesting:
                    afterCorruptFileRecovery,
                afterRetainedDecodeFailureForTesting:
                    afterRetainedDecodeFailure,
                beforeDownloadFinalizationCommitForTesting:
                    beforeDownloadFinalizationCommit
            )
        } else {
            cache = DownloadableMediaCache(
                layout: layout,
                downloader: downloader,
                imageDecoder: decoder,
                notificationCenter: notificationCenter,
                observesMemoryWarnings: false
            )
        }
        addTeardownBlock { [cache, decoder, downloader, rootURL] in
            await MainActor.run {
                cache.cancelAllDownloads()
            }
            await downloader.cancelAll()
            await decoder.cancelAll()
            await MainActor.run {
                cache.cancelAllDownloads()
            }
            await downloader.cancelAll()
            await decoder.cancelAll()
            try? FileManager.default.removeItem(at: rootURL)
        }
        return (
            rootURL,
            layout,
            cache,
            downloader,
            decoder,
            notificationCenter
        )
    }

    private func makeDescriptor(
        name: String,
        collectionId: String,
        tokenIndex: Int
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        CollectionCatalogDownloadableMediaDescriptor(
            collectionId: collectionId,
            tokenId: name,
            tokenIndex: tokenIndex,
            media: .staticImage(
                url: URL(string: "https://example.com/\(name).webp")!,
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
    }

    private func makeAnimatedDescriptor(
        name: String,
        collectionId: String,
        tokenIndex: Int
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        CollectionCatalogDownloadableMediaDescriptor(
            collectionId: collectionId,
            tokenId: name,
            tokenIndex: tokenIndex,
            media: .animatedImage(
                url: URL(string: "https://example.com/\(name).gif")!,
                fileExtension: "gif"
            )
        )
    }
#endif

    func testDecodeGenerationStartsOnceAndInvalidationSkipsWork() {
        let currentGeneration = DownloadableMediaImageDecodeGeneration()
        XCTAssertTrue(currentGeneration.beginIfCurrent())
        XCTAssertFalse(currentGeneration.beginIfCurrent())
        XCTAssertFalse(currentGeneration.invalidateIfPending())

        let invalidatedGeneration = DownloadableMediaImageDecodeGeneration()
        XCTAssertTrue(invalidatedGeneration.invalidateIfPending())
        XCTAssertFalse(invalidatedGeneration.invalidateIfPending())
        XCTAssertFalse(invalidatedGeneration.beginIfCurrent())
    }

    func testImageDecoderHonorsGenerationInvalidation() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("image.png")
        let image = makeImage(.purple)
        try XCTUnwrap(image.pngData()).write(to: fileURL)
        let decoder = DownloadableMediaImageDecoder()

        let decoded = await decoder.decode(
            at: fileURL,
            generation: DownloadableMediaImageDecodeGeneration()
        )
        let invalidatedGeneration = DownloadableMediaImageDecodeGeneration()
        invalidatedGeneration.invalidate()
        let invalidated = await decoder.decode(
            at: fileURL,
            generation: invalidatedGeneration
        )

        XCTAssertNotNil(decoded?.image)
        XCTAssertNil(invalidated)
    }

    func testMultipleLeasesReleaseExactlyOnceEach() {
        let releaseCount = OSAllocatedUnfairLock(initialState: 0)
        let first = DownloadableMediaFileLease {
            releaseCount.withLock { $0 += 1 }
        }
        let second = DownloadableMediaFileLease {
            releaseCount.withLock { $0 += 1 }
        }

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            first.release()
        }
        second.release()
        second.release()

        XCTAssertEqual(releaseCount.withLock { $0 }, 2)
    }

    func testLeaseReleasesOnDeinit() {
        let releaseCount = OSAllocatedUnfairLock(initialState: 0)
        var lease: DownloadableMediaFileLease? = DownloadableMediaFileLease {
            releaseCount.withLock { $0 += 1 }
        }

        XCTAssertNotNil(lease)
        lease = nil

        XCTAssertEqual(releaseCount.withLock { $0 }, 1)
    }

    func testAsyncRequestCancellationFinishesOnce() async throws {
        let cancellationCount = OSAllocatedUnfairLock(initialState: 0)
        let cancellationFinished = DownloadableMediaAsyncRequest<Void>()
        let request = DownloadableMediaAsyncRequest<String?>()
        request.installCancellation {
            cancellationCount.withLock { $0 += 1 }
            cancellationFinished.finish(())
        }
        let waiter = Task {
            await withTaskCancellationHandler {
                await request.wait()
            } onCancel: {
                request.finish(nil)
            }
        }

        request.cancel(returning: nil)
        request.finish("late")
        let result = try await waitForControlledTaskValue(
            waiter,
            event: "cancelled async request"
        )
        try await waitForControlledEvent("async request cancellation action") {
            await withTaskCancellationHandler {
                await cancellationFinished.wait()
            } onCancel: {
                cancellationFinished.cancel(returning: ())
            }
        }

        XCTAssertNil(result)
        XCTAssertEqual(cancellationCount.withLock { $0 }, 1)
    }

    private func makeDescriptor(
        name: String
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "\(name)-\(UUID())",
            tokenId: "0",
            tokenIndex: 0,
            media: .staticImage(
                url: URL(fileURLWithPath: "/\(name).webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
    }

    private func makeImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image {
            color.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}

extension DownloadableMediaCacheTests {

    func testDiskProtectionDeltasRetainOverlappingOwners() {
        let layout = DownloadableMediaCacheLayout(
            cacheRoot: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            ),
            stagingRoot: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        )
        let store = DownloadableMediaDiskStore(layout: layout)
        let path = layout.cacheRoot.appendingPathComponent("media").path

        store.applyProtectedPathDelta(
            adding: [path],
            removing: [],
            revision: 1
        )
        store.applyProtectedPathDelta(
            adding: [path],
            removing: [],
            revision: 2
        )
        store.applyProtectedPathDelta(
            adding: [],
            removing: [path],
            revision: 3
        )
        XCTAssertEqual(store.protectedPathsForTesting(), [path])

        for revision in 4...1_003 {
            store.applyProtectedPathDelta(
                adding: [path],
                removing: [path],
                revision: UInt64(revision)
            )
        }

        XCTAssertEqual(store.protectedPathsForTesting(), [path])

        store.applyProtectedPathDelta(
            adding: [],
            removing: [path],
            revision: 1_004
        )
        XCTAssertEqual(store.protectedPathsForTesting(), [])
    }

    func testDiskStoreFinalizesMetadataAndAvailability() async throws {
        let fixture = try makeDiskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let descriptor = makeDiskDescriptor(name: "finalized")
        let location = fixture.layout.location(for: descriptor)
        let contents = Data("cached-media".utf8)
        let stagedURL = try makeStagedFile(
            contents,
            name: "finalized",
            layout: fixture.layout
        )
        let sourceURL = URL(string: "https://cdn.example.com/finalized.webp")!

        let finalization = await fixture.store.finalizeDownload(
            at: stagedURL,
            location: location,
            sourceURL: sourceURL
        )
        let existingURL = await fixture.store.existingFileURL(
            at: location,
            recordsAccess: false
        )
        let downloadedSourceURL = await fixture.store.sourceURL(at: location)
        let availability = await fixture.store.availability(for: [location])

        XCTAssertTrue(finalization.succeeded)
        XCTAssertEqual(finalization.mediaURL, location.mediaURL)
        XCTAssertGreaterThanOrEqual(finalization.cacheBytes, Int64(contents.count))
        XCTAssertEqual(try Data(contentsOf: location.mediaURL), contents)
        XCTAssertEqual(existingURL, location.mediaURL)
        XCTAssertEqual(downloadedSourceURL, sourceURL)
        XCTAssertEqual(availability.hasFile(forKey: location.key), true)
    }

    func testDiskEvictionPreservesProtectedMediaAndMetadataPair() async throws {
        let fixture = try makeDiskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let protectedDescriptor = makeDiskDescriptor(
            name: "protected",
            collectionId: "eviction"
        )
        let evictedDescriptor = makeDiskDescriptor(
            name: "evicted",
            collectionId: "eviction",
            tokenIndex: 1
        )
        let protectedLocation = fixture.layout.location(for: protectedDescriptor)
        let evictedLocation = fixture.layout.location(for: evictedDescriptor)

        for (name, location) in [
            ("protected", protectedLocation),
            ("evicted", evictedLocation),
        ] {
            let stagedURL = try makeStagedFile(
                Data(name.utf8),
                name: name,
                layout: fixture.layout
            )
            let finalization = await fixture.store.finalizeDownload(
                at: stagedURL,
                location: location,
                sourceURL: location.descriptor.url
            )
            XCTAssertTrue(finalization.succeeded)
        }

        let eviction = await fixture.store.evictFilesOutsideWindow(
            collectionId: protectedDescriptor.collectionId,
            protectedFileNames: Set(
                fixture.layout.fileNames(for: protectedDescriptor)
            )
        )

        XCTAssertTrue(eviction.didRemoveItem)
        XCTAssertFalse(eviction.wasCancelled)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: protectedLocation.mediaURL.path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: protectedLocation.metadataURL.path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: evictedLocation.mediaURL.path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: evictedLocation.metadataURL.path
        ))
    }

    private func makeDiskFixture() throws -> (
        rootURL: URL,
        layout: DownloadableMediaCacheLayout,
        store: DownloadableMediaDiskStore
    ) {
        let rootURL = try makeTemporaryDirectory()
        let layout = DownloadableMediaCacheLayout(
            cacheRoot: rootURL.appendingPathComponent("cache", isDirectory: true),
            stagingRoot: rootURL.appendingPathComponent("staging", isDirectory: true)
        )
        return (
            rootURL,
            layout,
            DownloadableMediaDiskStore(layout: layout)
        )
    }

    private func makeDiskDescriptor(
        name: String,
        collectionId: String = "disk-store",
        tokenIndex: Int = 0
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        CollectionCatalogDownloadableMediaDescriptor(
            collectionId: collectionId,
            tokenId: name,
            tokenIndex: tokenIndex,
            media: .staticImage(
                url: URL(string: "https://example.com/\(name).webp")!,
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
    }

    private func makeStagedFile(
        _ data: Data,
        name: String,
        layout: DownloadableMediaCacheLayout
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: layout.stagingRoot,
            withIntermediateDirectories: true
        )
        let url = layout.stagingRoot.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

nonisolated private struct ControlledDownloadableMediaDownloaderSnapshot:
    Sendable {
    let startedRequestIDs: [UUID]
    let activeRequestIDs: Set<UUID>
    let cancelledRequestIDs: Set<UUID>
    let priorityEvents: [ControlledDownloadableMediaPriorityEvent]

    var activeRequestCount: Int {
        activeRequestIDs.count
    }
}

nonisolated private struct ControlledDownloadableMediaPriorityEvent:
    Equatable, Sendable {
    let priority: Float
    let requestID: UUID
    let revision: UInt64
    let effectivePriority: Float
    let effectiveRevision: UInt64
}

private actor ControlledDownloadableMediaDownloader:
    DownloadableMediaDownloading {

    private struct ActiveRequest {
        let request: DownloadableMediaDownloadRequest
        let continuation:
            CheckedContinuation<DownloadableMediaDownloadResult, Never>
    }

    private struct CountWaiter {
        let id: UUID
        let count: Int
        let request: DownloadableMediaAsyncRequest<Void>
    }

    private struct CancellationWaiter {
        let id: UUID
        let request: DownloadableMediaAsyncRequest<Void>
    }

    private struct PriorityEventWaiter {
        let id: UUID
        let requestID: UUID
        let priority: Float
        let afterRevision: UInt64
        let request:
            DownloadableMediaAsyncRequest<ControlledDownloadableMediaPriorityEvent?>
    }

    private var activeRequests = [UUID: ActiveRequest]()
    private var startedRequests = [DownloadableMediaDownloadRequest]()
    private var cancelledRequestIDs = Set<UUID>()
    private var priorityEvents = [ControlledDownloadableMediaPriorityEvent]()
    private var effectivePriorities = [UUID: (priority: Float, revision: UInt64)]()
    private var startedRequestWaiters = [CountWaiter]()
    private var priorityUpdateWaiters = [CountWaiter]()
    private var cancellationWaiters = [UUID: [CancellationWaiter]]()
    private var priorityEventWaiters = [PriorityEventWaiter]()

    func download(
        _ request: DownloadableMediaDownloadRequest
    ) async -> DownloadableMediaDownloadResult {
        guard !Task.isCancelled,
              !cancelledRequestIDs.contains(request.id) else {
            return cancelledResult(requestID: request.id)
        }
        return await withCheckedContinuation { continuation in
            activeRequests[request.id] = ActiveRequest(
                request: request,
                continuation: continuation
            )
            startedRequests.append(request)
            if effectivePriorities[request.id] == nil {
                effectivePriorities[request.id] = (request.priority, 0)
            }
            resumeCountWaiters(
                &startedRequestWaiters,
                currentCount: startedRequests.count
            )
        }
    }

    func setPriority(
        _ priority: Float,
        for requestID: UUID,
        revision: UInt64
    ) {
        if let current = effectivePriorities[requestID] {
            if revision >= current.revision {
                effectivePriorities[requestID] = (priority, revision)
            }
        } else {
            effectivePriorities[requestID] = (priority, revision)
        }
        let effective = effectivePriorities[requestID]!
        let event = ControlledDownloadableMediaPriorityEvent(
            priority: priority,
            requestID: requestID,
            revision: revision,
            effectivePriority: effective.priority,
            effectiveRevision: effective.revision
        )
        priorityEvents.append(event)
        resumeCountWaiters(
            &priorityUpdateWaiters,
            currentCount: priorityEvents.count
        )
        resumePriorityEventWaiters(with: event)
    }

    func cancel(requestID: UUID) {
        guard cancelledRequestIDs.insert(requestID).inserted else { return }
        if let activeRequest = activeRequests.removeValue(forKey: requestID) {
            activeRequest.continuation.resume(
                returning: DownloadableMediaDownloadResult(
                    requestID: requestID,
                    stagedURL: nil,
                    sourceURL: nil,
                    failure: .cancelled
                )
            )
        }
        cancellationWaiters.removeValue(forKey: requestID)?.forEach {
            $0.request.finish(())
        }
    }

    func cancelAll() {
        for requestID in Array(activeRequests.keys) {
            cancel(requestID: requestID)
        }
    }

    private func cancelledResult(
        requestID: UUID
    ) -> DownloadableMediaDownloadResult {
        DownloadableMediaDownloadResult(
            requestID: requestID,
            stagedURL: nil,
            sourceURL: nil,
            failure: .cancelled
        )
    }

    func waitForStartedRequestCount(_ count: Int) async {
        guard startedRequests.count < count else { return }
        let waiter = CountWaiter(
            id: UUID(),
            count: count,
            request: DownloadableMediaAsyncRequest<Void>()
        )
        startedRequestWaiters.append(waiter)
        defer {
            startedRequestWaiters.removeAll { $0.id == waiter.id }
        }
        await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: ())
        }
    }

    func waitForPriorityUpdateCount(_ count: Int) async {
        guard priorityEvents.count < count else { return }
        let waiter = CountWaiter(
            id: UUID(),
            count: count,
            request: DownloadableMediaAsyncRequest<Void>()
        )
        priorityUpdateWaiters.append(waiter)
        defer {
            priorityUpdateWaiters.removeAll { $0.id == waiter.id }
        }
        await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: ())
        }
    }

    func waitForCancellation(of requestID: UUID) async {
        guard !cancelledRequestIDs.contains(requestID) else { return }
        let waiter = CancellationWaiter(
            id: UUID(),
            request: DownloadableMediaAsyncRequest<Void>()
        )
        cancellationWaiters[requestID, default: []].append(waiter)
        defer {
            cancellationWaiters[requestID]?.removeAll { $0.id == waiter.id }
            if cancellationWaiters[requestID]?.isEmpty == true {
                cancellationWaiters.removeValue(forKey: requestID)
            }
        }
        await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: ())
        }
    }

    func waitForEffectivePriority(
        _ priority: Float,
        requestID: UUID,
        afterRevision: UInt64 = 0
    ) async -> ControlledDownloadableMediaPriorityEvent? {
        if let event = matchingPriorityEvent(
            priority,
            requestID: requestID,
            afterRevision: afterRevision
        ) {
            return event
        }
        let waiter = PriorityEventWaiter(
            id: UUID(),
            requestID: requestID,
            priority: priority,
            afterRevision: afterRevision,
            request: DownloadableMediaAsyncRequest<
                ControlledDownloadableMediaPriorityEvent?
            >()
        )
        priorityEventWaiters.append(waiter)
        defer {
            priorityEventWaiters.removeAll { $0.id == waiter.id }
        }
        return await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: nil)
        }
    }

    func startedRequest(
        at index: Int
    ) -> DownloadableMediaDownloadRequest {
        startedRequests[index]
    }

    func startedRequest(
        for sourceURL: URL
    ) -> DownloadableMediaDownloadRequest? {
        startedRequests.first { $0.sourceURL == sourceURL }
    }

    func latestStartedRequest(
        for sourceURL: URL
    ) -> DownloadableMediaDownloadRequest? {
        startedRequests.last { $0.sourceURL == sourceURL }
    }

    func succeed(requestID: UUID, data: Data) -> Bool {
        guard let activeRequest = activeRequests.removeValue(
            forKey: requestID
        ) else {
            return false
        }
        let stagedURL = activeRequest.request.stagingRoot.appendingPathComponent(
            UUID().uuidString
        )
        do {
            try FileManager.default.createDirectory(
                at: activeRequest.request.stagingRoot,
                withIntermediateDirectories: true
            )
            try data.write(to: stagedURL)
            activeRequest.continuation.resume(
                returning: DownloadableMediaDownloadResult(
                    requestID: requestID,
                    stagedURL: stagedURL,
                    sourceURL: activeRequest.request.sourceURL,
                    failure: nil
                )
            )
            return true
        } catch {
            activeRequest.continuation.resume(
                returning: DownloadableMediaDownloadResult(
                    requestID: requestID,
                    stagedURL: nil,
                    sourceURL: nil,
                    failure: .staging
                )
            )
            return false
        }
    }

    func snapshot() -> ControlledDownloadableMediaDownloaderSnapshot {
        ControlledDownloadableMediaDownloaderSnapshot(
            startedRequestIDs: startedRequests.map(\.id),
            activeRequestIDs: Set(activeRequests.keys),
            cancelledRequestIDs: cancelledRequestIDs,
            priorityEvents: priorityEvents
        )
    }

    private func resumeCountWaiters(
        _ waiters: inout [CountWaiter],
        currentCount: Int
    ) {
        var pendingWaiters = [CountWaiter]()
        for waiter in waiters {
            if currentCount >= waiter.count {
                waiter.request.finish(())
            } else {
                pendingWaiters.append(waiter)
            }
        }
        waiters = pendingWaiters
    }

    private func matchingPriorityEvent(
        _ priority: Float,
        requestID: UUID,
        afterRevision: UInt64
    ) -> ControlledDownloadableMediaPriorityEvent? {
        priorityEvents.first {
            $0.requestID == requestID
                && $0.effectivePriority == priority
                && $0.effectiveRevision == $0.revision
                && $0.effectiveRevision > afterRevision
        }
    }

    private func resumePriorityEventWaiters(
        with event: ControlledDownloadableMediaPriorityEvent
    ) {
        var pendingWaiters = [PriorityEventWaiter]()
        for waiter in priorityEventWaiters {
            if event.requestID == waiter.requestID,
               event.effectivePriority == waiter.priority,
               event.effectiveRevision == event.revision,
               event.effectiveRevision > waiter.afterRevision {
                waiter.request.finish(event)
            } else {
                pendingWaiters.append(waiter)
            }
        }
        priorityEventWaiters = pendingWaiters
    }
}

private actor ControlledDownloadableMediaImageDecoder:
    DownloadableMediaVariantImageDecoding {

    private struct PendingDecode {
        let id: UUID
        let request: DownloadableMediaAsyncRequest<
            DownloadableMediaDecodedImageTransfer?
        >
    }

    private struct CountWaiter {
        let id: UUID
        let count: Int
        let request: DownloadableMediaAsyncRequest<Void>
    }

    private var pendingDecodes = [PendingDecode]()
    private var decodeStartGate: DownloadableMediaAsyncRequest<Void>?
    private var decodeAttemptCountValue = 0
    private var startedDecodeCountValue = 0
    private var startedVariants = [DownloadableMediaImageDecodeVariant]()
    private var startedFileURLs = [URL]()
    private var decodeAttemptWaiters = [CountWaiter]()
    private var startedDecodeWaiters = [CountWaiter]()

    func decode(
        at fileURL: URL,
        variant: DownloadableMediaImageDecodeVariant,
        generation: DownloadableMediaImageDecodeGeneration
    ) async -> DownloadableMediaDecodedImageTransfer? {
        decodeAttemptCountValue += 1
        resumeCountWaiters(
            &decodeAttemptWaiters,
            currentCount: decodeAttemptCountValue
        )
        if let decodeStartGate {
            await decodeStartGate.wait()
        }
        guard generation.beginIfCurrent() else { return nil }
        let pendingDecode = PendingDecode(
            id: UUID(),
            request: DownloadableMediaAsyncRequest<
                DownloadableMediaDecodedImageTransfer?
            >()
        )
        pendingDecodes.append(pendingDecode)
        startedDecodeCountValue += 1
        startedVariants.append(variant.normalized)
        startedFileURLs.append(fileURL)
        resumeStartedDecodeWaiters()
        defer {
            pendingDecodes.removeAll { $0.id == pendingDecode.id }
        }
        return await withTaskCancellationHandler {
            await pendingDecode.request.wait()
        } onCancel: {
            pendingDecode.request.cancel(returning: nil)
        }
    }

    func waitForStartedDecodeCount(_ count: Int) async {
        guard startedDecodeCountValue < count else { return }
        let waiter = CountWaiter(
            id: UUID(),
            count: count,
            request: DownloadableMediaAsyncRequest<Void>()
        )
        startedDecodeWaiters.append(waiter)
        defer {
            startedDecodeWaiters.removeAll { $0.id == waiter.id }
        }
        await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: ())
        }
    }

    func suspendDecodeStarts() {
        guard decodeStartGate == nil else { return }
        decodeStartGate = DownloadableMediaAsyncRequest<Void>()
    }

    func resumeDecodeStarts() {
        decodeStartGate?.finish(())
        decodeStartGate = nil
    }

    func waitForDecodeAttemptCount(_ count: Int) async {
        guard decodeAttemptCountValue < count else { return }
        let waiter = CountWaiter(
            id: UUID(),
            count: count,
            request: DownloadableMediaAsyncRequest<Void>()
        )
        decodeAttemptWaiters.append(waiter)
        defer {
            decodeAttemptWaiters.removeAll { $0.id == waiter.id }
        }
        await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: ())
        }
    }

    func startedDecodeCount() -> Int {
        startedDecodeCountValue
    }

    func startedDecodeVariants() -> [DownloadableMediaImageDecodeVariant] {
        startedVariants
    }

    func startedDecodeFileURLs() -> [URL] {
        startedFileURLs
    }

    func completeNext(
        with transfer: DownloadableMediaDecodedImageTransfer?
    ) -> Bool {
        guard !pendingDecodes.isEmpty else { return false }
        pendingDecodes.removeFirst().request.finish(transfer)
        return true
    }

    func cancelAll() {
        resumeDecodeStarts()
        let decodes = pendingDecodes
        pendingDecodes.removeAll()
        decodes.forEach { $0.request.cancel(returning: nil) }
    }

    private func resumeStartedDecodeWaiters() {
        resumeCountWaiters(
            &startedDecodeWaiters,
            currentCount: startedDecodeCountValue
        )
    }

    private func resumeCountWaiters(
        _ waiters: inout [CountWaiter],
        currentCount: Int
    ) {
        var pendingWaiters = [CountWaiter]()
        for waiter in waiters {
            if currentCount >= waiter.count {
                waiter.request.finish(())
            } else {
                pendingWaiters.append(waiter)
            }
        }
        waiters = pendingWaiters
    }
}

private actor ControlledDownloadableMediaAsyncGate {
    private struct Waiter {
        let id: UUID
        let request: DownloadableMediaAsyncRequest<Void>
    }

    private var isPaused = false
    private var isOpen = false
    private var pauseWaiter: Waiter?
    private var pausedWaiters = [Waiter]()

    func pause() async {
        isPaused = true
        pausedWaiters.forEach { $0.request.finish(()) }
        pausedWaiters.removeAll()
        guard !isOpen else { return }
        let waiter = Waiter(
            id: UUID(),
            request: DownloadableMediaAsyncRequest<Void>()
        )
        pauseWaiter = waiter
        defer {
            if pauseWaiter?.id == waiter.id {
                pauseWaiter = nil
            }
        }
        await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: ())
        }
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        let waiter = Waiter(
            id: UUID(),
            request: DownloadableMediaAsyncRequest<Void>()
        )
        pausedWaiters.append(waiter)
        defer {
            pausedWaiters.removeAll { $0.id == waiter.id }
        }
        await withTaskCancellationHandler {
            await waiter.request.wait()
        } onCancel: {
            waiter.request.cancel(returning: ())
        }
    }

    func resume() {
        isOpen = true
        pauseWaiter?.request.finish(())
        pauseWaiter = nil
    }
}

nonisolated final class DownloadableMediaFileRemovalTokenTests: XCTestCase {

    func testSuccessfulRemovalDeletesFile() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("media")
        try Data("cached".utf8).write(to: fileURL)
        let token = DownloadableMediaFileRemovalToken()

        XCTAssertEqual(token.removeIfActive(at: fileURL), .removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCancelledRemovalLeavesFileInPlace() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("media")
        try Data("cached".utf8).write(to: fileURL)
        let token = DownloadableMediaFileRemovalToken()

        token.cancel()

        XCTAssertEqual(token.removeIfActive(at: fileURL), .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCancelledPairRemovalLeavesBothFilesInPlace() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let primaryURL = rootURL.appendingPathComponent("media")
        let sidecarURL = rootURL.appendingPathComponent("metadata")
        try Data("cached".utf8).write(to: primaryURL)
        try Data("metadata".utf8).write(to: sidecarURL)
        let token = DownloadableMediaFileRemovalToken()

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

    func testFailedCleanupIsStagedForLaterRemoval() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("media")
        try Data("cached".utf8).write(to: fileURL)
        let attemptedURL = OSAllocatedUnfairLock<URL?>(initialState: nil)
        let token = DownloadableMediaFileRemovalToken(removeItem: { url in
            attemptedURL.withLock { $0 = url }
            throw DownloadableMediaFileRemovalTestError.expected
        })

        let result = token.removeIfActive(at: fileURL)

        XCTAssertEqual(result, .stagedForCleanup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNotNil(attemptedURL.withLock { $0 })
        XCTAssertTrue(token.isActive)
    }

    func testFailedPrimaryRemovalLeavesSidecarInPlace() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let primaryURL = rootURL.appendingPathComponent("media")
        let sidecarURL = rootURL.appendingPathComponent("metadata")
        try Data("metadata".utf8).write(to: sidecarURL)
        let token = DownloadableMediaFileRemovalToken()

        let removal = token.removePairIfActive(
            primaryURL: primaryURL,
            sidecarURL: sidecarURL
        )

        XCTAssertEqual(removal.primary, .notRemoved)
        XCTAssertNil(removal.sidecar)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testSuccessfulPairRemovalDeletesBothFiles() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let primaryURL = rootURL.appendingPathComponent("media")
        let sidecarURL = rootURL.appendingPathComponent("metadata")
        try Data("cached".utf8).write(to: primaryURL)
        try Data("metadata".utf8).write(to: sidecarURL)
        let token = DownloadableMediaFileRemovalToken()

        let removal = token.removePairIfActive(
            primaryURL: primaryURL,
            sidecarURL: sidecarURL
        )

        XCTAssertEqual(removal.primary, .removed)
        XCTAssertEqual(removal.sidecar, .removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testCancellationDoesNotWaitForInFlightRemoval() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let removalStarted = DispatchSemaphore(value: 0)
        let allowRemoval = DispatchSemaphore(value: 0)
        let removalFinished = DispatchSemaphore(value: 0)
        let cancellationFinished = DispatchSemaphore(value: 0)
        let token = DownloadableMediaFileRemovalToken(removeItem: { url in
            removalStarted.signal()
            allowRemoval.wait()
            try? FileManager.default.removeItem(at: url)
        })
        let fileURL = rootURL.appendingPathComponent("media")
        try Data("cached".utf8).write(to: fileURL)

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
        XCTAssertEqual(token.removeIfActive(at: fileURL), .cancelled)
        let replacementData = Data("replacement".utf8)
        try replacementData.write(to: fileURL)

        allowRemoval.signal()

        XCTAssertEqual(removalFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(try Data(contentsOf: fileURL), replacementData)
    }

    func testCancellationDuringPrimaryRemovalSkipsSidecar() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let primaryURL = rootURL.appendingPathComponent("media")
        let sidecarURL = rootURL.appendingPathComponent("metadata")
        let primaryStarted = DispatchSemaphore(value: 0)
        let allowPrimaryRemoval = DispatchSemaphore(value: 0)
        let pairFinished = DispatchSemaphore(value: 0)
        let cancellationFinished = DispatchSemaphore(value: 0)
        let sidecarRemoved = DispatchSemaphore(value: 0)
        let removalIndex = OSAllocatedUnfairLock(initialState: 0)
        let token = DownloadableMediaFileRemovalToken(removeItem: { url in
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
        try Data("cached".utf8).write(to: primaryURL)
        try Data("metadata".utf8).write(to: sidecarURL)

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
}

private enum DownloadableMediaFileRemovalTestError: Error {
    case expected
}

nonisolated private func waitForControlledTaskValue<Value: Sendable>(
    _ task: Task<Value, Never>,
    event: String,
    timeout: Duration = .seconds(2)
) async throws -> Value {
    try await waitForControlledEvent(event, timeout: timeout) {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated private struct ControlledEventTimeoutError:
    Error, CustomStringConvertible, Sendable {
    let event: String

    var description: String {
        "Timed out waiting for \(event)"
    }
}

nonisolated private func waitForControlledEvent<Value: Sendable>(
    _ event: String,
    timeout: Duration = .seconds(2),
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw ControlledEventTimeoutError(event: event)
        }
        guard let value = try await group.next() else {
            throw ControlledEventTimeoutError(event: event)
        }
        group.cancelAll()
        return value
    }
}

nonisolated private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
