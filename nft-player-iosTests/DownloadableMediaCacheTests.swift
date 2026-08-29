import Foundation
import os
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class DownloadableMediaCacheTests: XCTestCase {}

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

        XCTAssertTrue(expectedFileNames.isSubset(of:
            fixture.cache.fileNamesProtectedFromEvictionForTesting(
                collectionId: descriptor.collectionId,
                allowedFileNames: []
            )
        ))

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
            await fixture.cache.waitForImageDemandCountForTesting(
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
            await fixture.cache.waitForImageDemandCountForTesting(
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
            await fixture.cache.waitForImageDemandCountForTesting(
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
            await fixture.cache.waitForImageDemandCountForTesting(
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
        XCTAssertTrue(currentGeneration.hasStarted)

        let invalidatedGeneration = DownloadableMediaImageDecodeGeneration()
        invalidatedGeneration.invalidate()
        XCTAssertFalse(invalidatedGeneration.beginIfCurrent())
        XCTAssertFalse(invalidatedGeneration.hasStarted)
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
    DownloadableMediaImageDecoding {

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
    private var startedDecodeCountValue = 0
    private var startedDecodeWaiters = [CountWaiter]()

    func decode(
        at fileURL: URL,
        generation: DownloadableMediaImageDecodeGeneration
    ) async -> DownloadableMediaDecodedImageTransfer? {
        _ = fileURL
        guard generation.beginIfCurrent() else { return nil }
        let pendingDecode = PendingDecode(
            id: UUID(),
            request: DownloadableMediaAsyncRequest<
                DownloadableMediaDecodedImageTransfer?
            >()
        )
        pendingDecodes.append(pendingDecode)
        startedDecodeCountValue += 1
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

    func startedDecodeCount() -> Int {
        startedDecodeCountValue
    }

    func completeNext(
        with transfer: DownloadableMediaDecodedImageTransfer?
    ) -> Bool {
        guard !pendingDecodes.isEmpty else { return false }
        pendingDecodes.removeFirst().request.finish(transfer)
        return true
    }

    func cancelAll() {
        let decodes = pendingDecodes
        pendingDecodes.removeAll()
        decodes.forEach { $0.request.cancel(returning: nil) }
    }

    private func resumeStartedDecodeWaiters() {
        var pendingWaiters = [CountWaiter]()
        for waiter in startedDecodeWaiters {
            if startedDecodeCountValue >= waiter.count {
                waiter.request.finish(())
            } else {
                pendingWaiters.append(waiter)
            }
        }
        startedDecodeWaiters = pendingWaiters
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
    operation: @escaping @Sendable () async -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            await operation()
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
