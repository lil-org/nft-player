import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import NftPlayerSyncCore

private actor CoverTransportProbe {
    enum Failure: Error { case offline, timedOut }

    private(set) var names: [String] = []
    private(set) var cancellations: [Int] = []
    private(set) var peakActive = 0
    private var active = 0
    private var bytes: Data
    private var statusCode: Int
    private var offline = false
    private var held: Bool
    private var released: Set<String> = []
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]

    init(bytes: Data, statusCode: Int = 200, held: Bool = false) {
        self.bytes = bytes
        self.statusCode = statusCode
        self.held = held
    }

    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        let name = url.deletingPathExtension().lastPathComponent
        let id = names.count
        names.append(name)
        active += 1
        peakActive = max(peakActive, active)
        defer { active -= 1 }
        if held && !released.contains(name) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { pending[id] = $0 }
            } onCancel: {
                Task { await self.recordCancellation(id) }
            }
        }
        if offline { throw Failure.offline }
        return (bytes, statusCode)
    }

    func waitForCalls(_ count: Int) async throws {
        for _ in 0..<200 {
            if names.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timedOut
    }

    func release(_ name: String) {
        released.insert(name)
        for id in pending.keys.filter({ names[$0] == name }) { complete(id) }
    }

    func complete(_ id: Int, error: Error? = nil) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    private func recordCancellation(_ id: Int) {
        cancellations.append(id)
    }

    func waitForCancellations(_ count: Int) async throws {
        for _ in 0..<200 {
            if cancellations.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timedOut
    }

    func releaseAll() {
        held = false
        for continuation in pending.values { continuation.resume() }
        pending.removeAll()
    }

    func replace(bytes: Data, statusCode: Int = 200, offline: Bool = false) {
        self.bytes = bytes
        self.statusCode = statusCode
        self.offline = offline
    }
}

@MainActor
final class PersistentCollectionCoverCacheTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CollectionCoverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func jpeg() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func file(in root: URL, name: String = "0xmons") -> URL {
        root.appendingPathComponent("v1").appendingPathComponent(name + ".jpg")
    }

    func testPersistsOriginalBytesAndRecreatedCacheReadsForeverWithoutNetwork() async throws {
        let root = try directory()
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image)
        let first = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
        let published = expectation(description: "Newly persisted cover is announced on the main thread")
        published.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(forName: .collectionCoverDidBecomeAvailable, object: nil, queue: nil) { notification in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(notification.object as? String, "0xmons")
            published.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let downloaded = try await first.data(for: "0xmons")
        XCTAssertEqual(downloaded, image)
        XCTAssertEqual(try Data(contentsOf: file(in: root)), image)
        for url in [root, root.appendingPathComponent("v1"), file(in: root)] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
        let oldDate = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file(in: root).path)
        let offline = CoverTransportProbe(bytes: Data())
        await offline.replace(bytes: Data(), offline: true)
        let recreated = PersistentCollectionCoverCache(rootURL: root, transport: { try await offline.fetch($0) })
        let fromDisk = try await recreated.data(for: "0xmons")
        XCTAssertEqual(fromDisk, image)
        let calls = await offline.names
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(try file(in: root).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, oldDate)
        XCTAssertEqual(PersistentCollectionCoverCache.baseURL.appendingPathComponent("0xmons.jpg").absoluteString,
                       "https://cdn.lil.org/player/covers/v1/0xmons.jpg")
        await fulfillment(of: [published], timeout: 2)
    }

    func testConcurrentConsumersCoalesceAndCancellationLeavesSharedDownloadRunning() async throws {
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let canceled = Task { try await cache.data(for: "0xmons") }
        try await probe.waitForCalls(1)
        let readers = (0..<12).map { _ in Task { try await cache.data(for: "0xmons") } }
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Canceled consumer should stop waiting") }
        catch is CancellationError {}
        await probe.releaseAll()
        for reader in readers {
            let value = try await reader.value
            XCTAssertEqual(value, image)
        }
        let names = await probe.names
        XCTAssertEqual(names, ["0xmons"])
    }

    func testDiskHitBypassesFourBlockedDownloads() async throws {
        let root = try directory()
        let image = try jpeg()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("v1"), withIntermediateDirectories: true)
        try image.write(to: file(in: root))
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
        let downloads = (0..<4).map { index in Task { try await cache.data(for: "blocked-\(index)") } }
        try await probe.waitForCalls(4)
        let hit = expectation(description: "Cached cover loads while every download slot is occupied")
        let reader = Task {
            let value = try await cache.data(for: "0xmons")
            XCTAssertEqual(value, image)
            hit.fulfill()
        }
        await fulfillment(of: [hit], timeout: 2)
        await probe.releaseAll()
        try await reader.value
        for download in downloads { _ = try await download.value }
        let names = await probe.names
        XCTAssertEqual(names.count, 4)
        XCTAssertFalse(names.contains("0xmons"))
    }

    func testCanceledQueuedPrefetchesWaitForTheBackgroundSlot() async throws {
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        await cache.preload(assetNames: ["bulk-first"])
        try await probe.waitForCalls(1)
        let visible = (0..<3).map { index in Task { try await cache.data(for: "visible-\(index)") } }
        try await probe.waitForCalls(4)
        let abandoned = (0..<4).map { index in
            Task { try await cache.data(for: "abandoned-\(index)", priority: .prefetch) }
        }
        try await Task.sleep(for: .milliseconds(30))
        for reader in abandoned { reader.cancel() }
        for reader in abandoned {
            do { _ = try await reader.value; XCTFail("Canceled consumer should stop waiting") }
            catch is CancellationError {}
        }
        let nearby = Task { try await cache.data(for: "nearby", priority: .prefetch) }
        await probe.release("visible-0")
        try await probe.waitForCalls(5)
        let names = await probe.names
        XCTAssertEqual(names.last, "nearby")
        await probe.releaseAll()
        for reader in visible { _ = try await reader.value }
        _ = try await nearby.value
        for index in 0..<4 { _ = try await cache.data(for: "abandoned-\(index)", priority: .background) }
    }

    func testCancelingVisibleWaiterPreservesRemainingPrefetchDemand() async throws {
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        await cache.preload(assetNames: ["bulk-first"])
        try await probe.waitForCalls(1)
        let visible = (0..<3).map { index in Task { try await cache.data(for: "visible-\(index)") } }
        try await probe.waitForCalls(4)
        let first = Task { try await cache.data(for: "first", priority: .prefetch) }
        try await Task.sleep(for: .milliseconds(30))
        let remaining = Task { try await cache.data(for: "shared", priority: .prefetch) }
        let canceled = Task { try await cache.data(for: "shared", priority: .visible) }
        try await Task.sleep(for: .milliseconds(30))
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Canceled consumer should stop waiting") }
        catch is CancellationError {}
        await probe.release("visible-0")
        try await probe.waitForCalls(5)
        let afterCancellation = await probe.names
        XCTAssertEqual(afterCancellation.last, "first")
        await probe.release("first")
        try await probe.waitForCalls(6)
        let afterFirst = await probe.names
        XCTAssertEqual(afterFirst.last, "shared")
        await probe.releaseAll()
        for reader in visible { _ = try await reader.value }
        _ = try await first.value
        _ = try await remaining.value
    }

    func testSchedulingLimitsBulkWorkAndPromotesVisibleCoverAheadOfPrefetch() async throws {
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        await cache.preload(assetNames: ["bulk-first", "bulk-last", "promoted"])
        try await probe.waitForCalls(1)
        try await Task.sleep(for: .milliseconds(20))
        let initialNames = await probe.names
        XCTAssertEqual(initialNames, ["bulk-first"])
        let visible = (0..<3).map { index in Task { try await cache.data(for: "visible-\(index)") } }
        try await probe.waitForCalls(4)
        let nearby = Task { try await cache.data(for: "nearby", priority: .prefetch) }
        let promoted = Task { try await cache.data(for: "promoted", priority: .visible) }
        for _ in 0..<20 { await Task.yield() }
        await probe.release("visible-0")
        try await probe.waitForCalls(5)
        let afterPromotion = await probe.names
        XCTAssertEqual(afterPromotion.count, 5)
        XCTAssertEqual(afterPromotion.last, "promoted")
        await probe.release("promoted")
        try await probe.waitForCalls(6)
        let afterPrefetch = await probe.names
        XCTAssertEqual(afterPrefetch.last, "nearby")
        let peak = await probe.peakActive
        XCTAssertEqual(peak, 4)
        await probe.releaseAll()
        for reader in visible { _ = try await reader.value }
        _ = try await nearby.value
        _ = try await promoted.value
        _ = try await cache.data(for: "bulk-last")
    }

    func testSpeculativeDownloadsReserveVisibleCapacityAfterCancellationAndRecoverTheirSlots() async throws {
        for firstPriority in [PersistentCollectionCoverCache.Priority.prefetch, .background] {
            let image = try jpeg()
            let probe = CoverTransportProbe(bytes: image, held: true)
            let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
            addTeardownBlock { await probe.releaseAll() }
            let first = Task { try await cache.data(for: "first", priority: firstPriority) }
            try await probe.waitForCalls(1)
            let second = Task { try await cache.data(for: "second", priority: .prefetch) }
            try await probe.waitForCalls(2)
            for reader in [first, second] { reader.cancel() }
            for reader in [first, second] {
                do { _ = try await reader.value; XCTFail("Canceled consumer should stop waiting") }
                catch is CancellationError {}
            }
            let queued = Task { try await cache.data(for: "queued", priority: .prefetch) }
            try await Task.sleep(for: .milliseconds(30))
            let beforeVisible = await probe.names
            XCTAssertEqual(beforeVisible, ["first", "second"])
            let visible = (0..<2).map { index in Task { try await cache.data(for: "visible-\(index)") } }
            try await probe.waitForCalls(4)
            let withVisible = await probe.names
            XCTAssertEqual(Set(withVisible), ["first", "second", "visible-0", "visible-1"])
            await probe.release("first")
            try await probe.waitForCalls(5)
            let afterRelease = await probe.names
            XCTAssertEqual(afterRelease.last, "queued")
            await probe.releaseAll()
            for reader in visible { _ = try await reader.value }
            _ = try await queued.value
            for name in ["first", "second"] {
                let persisted = try await cache.data(for: name)
                XCTAssertEqual(persisted, image)
            }
            let names = await probe.names
            let peak = await probe.peakActive
            XCTAssertEqual(names.count, 5)
            XCTAssertEqual(peak, 4)
        }
    }

    func testCorruptFileIsReplacedAndDiskOnlyMissDoesNotDownload() async throws {
        let root = try directory()
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image)
        let cache = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
        let miss = try await cache.cachedData(for: "0xmons")
        XCTAssertNil(miss)
        let before = await probe.names
        XCTAssertTrue(before.isEmpty)
        _ = try await cache.data(for: "0xmons")
        try Data("broken JPEG".utf8).write(to: file(in: root))
        let repaired = try await cache.data(for: "0xmons")
        XCTAssertEqual(repaired, image)
        XCTAssertEqual(try Data(contentsOf: file(in: root)), image)
        let names = await probe.names
        XCTAssertEqual(names.count, 2)
    }

    func testVisibleDemandPreemptsAbandonedDownloadsWithoutExceedingFourTransfers() async throws {
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        addTeardownBlock { await probe.releaseAll() }
        let abandoned = (0..<4).map { index in Task { try await cache.data(for: "old-\(index)") } }
        try await probe.waitForCalls(4)
        for reader in abandoned { reader.cancel() }
        for reader in abandoned {
            do { _ = try await reader.value; XCTFail("Canceled consumer should stop waiting") }
            catch is CancellationError {}
        }
        let visible = Task { try await cache.data(for: "fresh") }
        try await probe.waitForCancellations(1)
        let cancellations = await probe.cancellations
        let canceled = try XCTUnwrap(cancellations.first)
        let heldNames = await probe.names
        XCTAssertEqual(heldNames.count, 4)
        await probe.complete(canceled, error: URLError(.cancelled))
        try await probe.waitForCalls(5)
        let afterCancellation = await probe.names
        XCTAssertEqual(afterCancellation.last, "fresh")
        await probe.releaseAll()
        _ = try await visible.value
        for name in heldNames { _ = try await cache.data(for: name, priority: .background) }
        let names = await probe.names
        let peak = await probe.peakActive
        XCTAssertEqual(names.filter { $0 == heldNames[canceled] }.count, 2)
        XCTAssertEqual(names.count, 6)
        XCTAssertEqual(peak, 4)
    }

    func testConsumerJoiningPreemptedRunSurvivesFailureOrSuccessfulCompletion() async throws {
        for succeeds in [false, true] {
            let image = try jpeg()
            let probe = CoverTransportProbe(bytes: image, held: true)
            let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
            addTeardownBlock { await probe.releaseAll() }
            let abandoned = Task {
                try await cache.data(for: "abandoned", priority: succeeds ? .background : .prefetch)
            }
            try await probe.waitForCalls(1)
            let observed = (0..<3).map { index in Task { try await cache.data(for: "observed-\(index)") } }
            try await probe.waitForCalls(4)
            abandoned.cancel()
            do { _ = try await abandoned.value; XCTFail("Canceled consumer should stop waiting") }
            catch is CancellationError {}
            let visible = Task { try await cache.data(for: "fresh") }
            try await probe.waitForCancellations(1)
            let cancellations = await probe.cancellations
            XCTAssertEqual(cancellations, [0])
            let joined = Task { try await cache.data(for: "abandoned") }
            try await Task.sleep(for: .milliseconds(30))
            if succeeds {
                await probe.complete(0)
                try await probe.waitForCalls(5)
            } else {
                await probe.release("observed-0")
                try await probe.waitForCalls(5)
                await probe.complete(0, error: URLError(.cancelled))
                try await probe.waitForCalls(6)
                let retried = await probe.names
                XCTAssertEqual(retried.last, "abandoned")
            }
            await probe.releaseAll()
            let joinedImage = try await joined.value
            XCTAssertEqual(joinedImage, image)
            _ = try await visible.value
            for reader in observed { _ = try await reader.value }
            let names = await probe.names
            let finalCancellations = await probe.cancellations
            let peak = await probe.peakActive
            XCTAssertEqual(names.count, succeeds ? 5 : 6)
            XCTAssertEqual(finalCancellations, [0])
            XCTAssertEqual(peak, 4)
        }
    }

    func testVisibleDemandPreemptsDownloadRetainedByPrefetch() async throws {
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        addTeardownBlock { await probe.releaseAll() }
        let prefetch = Task { try await cache.data(for: "shared", priority: .prefetch) }
        try await probe.waitForCalls(1)
        let canceled = Task { try await cache.data(for: "shared") }
        let observed = (0..<3).map { index in Task { try await cache.data(for: "observed-\(index)") } }
        try await probe.waitForCalls(4)
        try await Task.sleep(for: .milliseconds(30))
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Canceled visible consumer should stop waiting") }
        catch is CancellationError {}
        let visible = Task { try await cache.data(for: "fresh") }
        try await probe.waitForCancellations(1)
        let cancellations = await probe.cancellations
        let heldNames = await probe.names
        XCTAssertEqual(cancellations, [0])
        XCTAssertEqual(heldNames.count, 4)
        await probe.complete(0, error: URLError(.cancelled))
        try await probe.waitForCalls(5)
        let afterPreemption = await probe.names
        XCTAssertEqual(afterPreemption.last, "fresh")
        await probe.release("observed-0")
        try await probe.waitForCalls(6)
        let afterRelease = await probe.names
        XCTAssertEqual(afterRelease.last, "shared")
        await probe.releaseAll()
        let prefetchedImage = try await prefetch.value
        XCTAssertEqual(prefetchedImage, image)
        _ = try await visible.value
        for reader in observed { _ = try await reader.value }
        let finalCancellations = await probe.cancellations
        let peak = await probe.peakActive
        XCTAssertEqual(finalCancellations, [0])
        XCTAssertEqual(peak, 4)
    }

    func testConnectionRecoveryRetriesOlderConsumerAndPreloadFailures() async throws {
        for hasConsumer in [true, false] {
            let image = try jpeg()
            let probe = CoverTransportProbe(bytes: image, held: true)
            let cache = PersistentCollectionCoverCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
            addTeardownBlock { await probe.releaseAll() }
            let reader = hasConsumer ? Task { try await cache.data(for: "0xmons") } : nil
            if !hasConsumer { await cache.preload(assetNames: ["0xmons"]) }
            try await probe.waitForCalls(1)
            await cache.connectionRecovered()
            await probe.complete(0, error: CoverTransportProbe.Failure.offline)
            try await probe.waitForCalls(2)
            await probe.complete(1)
            let value: Data
            if let reader { value = try await reader.value }
            else { value = try await cache.data(for: "0xmons") }
            let names = await probe.names
            XCTAssertEqual(value, image)
            XCTAssertEqual(names, ["0xmons", "0xmons"])
        }
    }

    func testUnusableStorageReturnsNetworkImageAndPreloadRetriesPersistence() async throws {
        let root = try directory()
        let blockedDirectory = root.appendingPathComponent("v1")
        try Data("not a directory".utf8).write(to: blockedDirectory)
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
        addTeardownBlock { await probe.releaseAll() }
        let published = expectation(description: "Only the durable retry announces a saved cover")
        let observer = NotificationCenter.default.addObserver(forName: .collectionCoverDidBecomeAvailable, object: nil, queue: nil) { _ in
            published.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        await cache.preload(assetNames: ["0xmons"])
        try await probe.waitForCalls(1)
        let reader = Task { try await cache.data(for: "0xmons") }
        try await Task.sleep(for: .milliseconds(30))
        await probe.releaseAll()
        let value = try await reader.value
        let diskMiss = try await cache.cachedData(for: "0xmons")
        XCTAssertEqual(value, image)
        XCTAssertNil(diskMiss)
        try FileManager.default.removeItem(at: blockedDirectory)
        await cache.preload(assetNames: ["0xmons"], retryFailures: true)
        try await probe.waitForCalls(2)
        _ = try await cache.data(for: "0xmons")
        XCTAssertEqual(try Data(contentsOf: file(in: root)), image)
        await fulfillment(of: [published], timeout: 2)
    }

    func testReadAndWritePermissionFailuresReturnValidNetworkImages() async throws {
        let root = try directory()
        let directory = root.appendingPathComponent("v1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unreadable = file(in: root)
        let original = Data("unreadable original".utf8)
        try original.write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path)
        }
        XCTAssertThrowsError(try Data(contentsOf: unreadable))
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image)
        let cache = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
        let fromNetwork = try await cache.data(for: "0xmons")
        XCTAssertEqual(fromNetwork, image)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path)
        XCTAssertEqual(try Data(contentsOf: unreadable), original)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let unwritable = try await cache.data(for: "no-write")
        XCTAssertEqual(unwritable, image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(in: root, name: "no-write").path))
        await probe.replace(bytes: Data("invalid image".utf8))
        do { _ = try await cache.data(for: "invalid"); XCTFail("Invalid network data must still fail") }
        catch let failure as PersistentCollectionCoverCache.Failure { XCTAssertEqual(failure, .invalidImage) }
    }

    func testUnsafeCacheEntryIsNotOverwrittenByNetworkFallback() async throws {
        let root = try directory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("v1"), withIntermediateDirectories: true)
        let target = root.appendingPathComponent("keep")
        let original = Data("keep".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: file(in: root), withDestinationURL: target)
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image)
        let cache = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
        let value = try await cache.data(for: "0xmons")
        XCTAssertEqual(value, image)
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try file(in: root).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
    }

    func testHTTPAndInvalidImageFailuresAreNotPersistedAndRemainRetryable() async throws {
        let image = try jpeg()
        let failures: [(Data, Int, PersistentCollectionCoverCache.Failure)] = [
            (image, 503, .httpStatus(503)),
            (Data("not an image".utf8), 200, .invalidImage)
        ]
        for (bytes, status, expected) in failures {
            let root = try directory()
            let probe = CoverTransportProbe(bytes: bytes, statusCode: status)
            let cache = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
            do { _ = try await cache.data(for: "0xmons"); XCTFail("Invalid response should fail") }
            catch let failure as PersistentCollectionCoverCache.Failure { XCTAssertEqual(failure, expected) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: file(in: root).path))
            await probe.replace(bytes: image)
            let retried = try await cache.data(for: "0xmons")
            XCTAssertEqual(retried, image)
            let names = await probe.names
            XCTAssertEqual(names.count, 2)
        }
    }

    func testPreloadingIsIdempotentAndExplicitlyRetriesFailures() async throws {
        let root = try directory()
        let image = try jpeg()
        let probe = CoverTransportProbe(bytes: image, statusCode: 503, held: true)
        let cache = PersistentCollectionCoverCache(rootURL: root, transport: { try await probe.fetch($0) })
        await cache.preload(assetNames: ["0xmons", "0xmons"])
        try await probe.waitForCalls(1)
        let reader = Task { try await cache.data(for: "0xmons") }
        for _ in 0..<20 { await Task.yield() }
        await probe.releaseAll()
        do { _ = try await reader.value; XCTFail("Failed preload should also fail its consumer") }
        catch let failure as PersistentCollectionCoverCache.Failure { XCTAssertEqual(failure, .httpStatus(503)) }
        await cache.preload(assetNames: ["0xmons"])
        let afterRepeatedPreload = await probe.names
        XCTAssertEqual(afterRepeatedPreload.count, 1)
        await probe.replace(bytes: image)
        await cache.preload(assetNames: ["0xmons"], retryFailures: true)
        let retried = try await cache.data(for: "0xmons")
        XCTAssertEqual(retried, image)
        await cache.preload(assetNames: ["0xmons"], retryFailures: true)
        let names = await probe.names
        XCTAssertEqual(names.count, 2)
    }
}
