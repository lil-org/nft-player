import Darwin
import Foundation
import XCTest
import os
@testable import NftPlayerSyncCore

private final class TokenCacheActivityProbe: Sendable {
    private let handler = OSAllocatedUnfairLock(initialState: Optional<@Sendable (Bool) -> Void>.none)
    let didFinish: @Sendable () -> Void

    init(didFinish: @escaping @Sendable () -> Void) {
        self.didFinish = didFinish
    }

    func begin(_ handler: @escaping @Sendable (Bool) -> Void) {
        self.handler.withLock { $0 = handler }
        DispatchQueue.global().async {
            handler(false)
            self.didFinish()
        }
    }

    func expire() async {
        let handler = handler.withLock { $0 }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                handler?(true)
                continuation.resume()
            }
        }
    }
}

private actor TokenManifestTransportProbe {
    enum Failure: Error { case offline }
    private(set) var calls = 0
    private(set) var urls: [URL] = []
    private var bytes: Data
    private var statusCode: Int
    private var offline: Bool
    private var held: Bool
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var started: [CheckedContinuation<Void, Never>] = []

    init(bytes: Data, statusCode: Int = 200, offline: Bool = false, held: Bool = false) {
        self.bytes = bytes
        self.statusCode = statusCode
        self.offline = offline
        self.held = held
    }

    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        calls += 1
        urls.append(url)
        started.forEach { $0.resume() }
        started.removeAll()
        if held { await withCheckedContinuation { pending.append($0) } }
        if offline { throw Failure.offline }
        return (bytes, statusCode)
    }

    func waitUntilCalled() async {
        if calls == 0 { await withCheckedContinuation { started.append($0) } }
    }

    func release() {
        held = false
        pending.forEach { $0.resume() }
        pending.removeAll()
    }

    func replace(bytes: Data, statusCode: Int = 200, offline: Bool = false) {
        self.bytes = bytes
        self.statusCode = statusCode
        self.offline = offline
    }
}

@MainActor
final class PersistentCollectionTokenCacheTests: XCTestCase {
    private let manifest = Data(#"{"version":2,"count":2,"firstId":"100","name":["First",null],"hash":["0xabc",null],"aspectRatio":[[3,4],null],"contractParameters":[{"seed":"42"},null],"urlTemplate":{"value":"id","suffix":".png"},"excludedMediaIndices":[1]}"#.utf8)

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CollectionTokensTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testPersistsOriginalBytesAndRecreatedCacheReadsForeverOffline() async throws {
        let root = try directory()
        let probe = TokenManifestTransportProbe(bytes: manifest)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        let loaded = try await cache.data(for: "chromie_squiggle")
        XCTAssertEqual(loaded, manifest)
        let file = root.appendingPathComponent("chromie_squiggle.json")
        XCTAssertEqual(try Data(contentsOf: file), manifest)
        for url in [root, file] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
        let urls = await probe.urls
        XCTAssertEqual(urls, [URL(string: "https://cdn.lil.org/player/collections/chromie_squiggle.json")!])
        let oldDate = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        let offline = TokenManifestTransportProbe(bytes: Data(), offline: true)
        let recreated = PersistentCollectionTokenCache(rootURL: root, transport: { try await offline.fetch($0) })
        let reloaded = try await recreated.data(for: "chromie_squiggle")
        let cached = try await recreated.cachedData(for: "chromie_squiggle")
        XCTAssertEqual(reloaded, manifest)
        XCTAssertEqual(cached, manifest)
        let calls = await offline.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, oldDate)
    }

    func testConcurrentReadersCoalesceAndCanceledReaderDoesNotStopDownload() async throws {
        let root = try directory()
        let probe = TokenManifestTransportProbe(bytes: manifest, held: true)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        let stopped = expectation(description: "Canceled reader stops before download finishes")
        let canceled = Task {
            do { _ = try await cache.data(for: "fidenza"); XCTFail("Canceled reader should stop") }
            catch is CancellationError { stopped.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await probe.waitUntilCalled()
        let readers = (0..<20).map { _ in Task { try await cache.data(for: "fidenza") } }
        let whileDownloading = try await cache.cachedData(for: "fidenza")
        XCTAssertNil(whileDownloading)
        canceled.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        await probe.release()
        await canceled.value
        for reader in readers {
            let data = try await reader.value
            XCTAssertEqual(data, manifest)
        }
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["fidenza.json", "fidenza.lock"])
    }

    func testIndependentCachesShareFileLockAndOnlyDownloadOnce() async throws {
        let root = try directory()
        let probe = TokenManifestTransportProbe(bytes: manifest, held: true)
        let first = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        let second = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        let firstReader = Task { try await first.data(for: "fidenza") }
        await probe.waitUntilCalled()
        let secondReader = Task { try await second.data(for: "fidenza") }
        try await Task.sleep(for: .milliseconds(100))
        let beforeRelease = await probe.calls
        XCTAssertEqual(beforeRelease, 1)
        await probe.release()
        let firstData = try await firstReader.value
        let secondData = try await secondReader.value
        XCTAssertEqual(firstData, manifest)
        XCTAssertEqual(secondData, manifest)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testExpiredActivityReleasesSharedLockBeforeReturning() async throws {
        let root = try directory()
        let started = expectation(description: "Download started while protected")
        let finished = expectation(description: "Background activity finished")
        let activity = TokenCacheActivityProbe { finished.fulfill() }
        let cache = PersistentCollectionTokenCache(rootURL: root, activity: .init(perform: activity.begin)) { _ in
            started.fulfill()
            try await Task.sleep(for: .seconds(60))
            return (Data(), 200)
        }
        let reader = Task { try await cache.data(for: "fidenza") }
        await fulfillment(of: [started], timeout: 2)
        await activity.expire()
        await fulfillment(of: [finished], timeout: 2)
        do { _ = try await reader.value; XCTFail("Expired work should be cancelled") }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fidenza.json").path))

        let descriptor = open(root.appendingPathComponent("fidenza.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        let bytes = manifest
        let independent = PersistentCollectionTokenCache(rootURL: root) { _ in (bytes, 200) }
        let retried = try await independent.data(for: "fidenza")
        XCTAssertEqual(retried, bytes)
    }

    func testDeniedActivityDoesNotAcquireLockOrDownload() async throws {
        let root = try directory()
        let denied = PersistentCollectionTokenCache.BackgroundActivity { handler in
            DispatchQueue.global().async { handler(true) }
        }
        let cache = PersistentCollectionTokenCache(rootURL: root, activity: denied) { _ in
            XCTFail("Denied background activity must not start a download")
            return (Data(), 200)
        }
        do { _ = try await cache.data(for: "fidenza"); XCTFail("Denied activity should fail") }
        catch is CancellationError {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testLastReaderCancellationEndsBackgroundActivity() async throws {
        let started = expectation(description: "Protected download started")
        let finished = expectation(description: "Cancelled background activity finished")
        let activity = TokenCacheActivityProbe { finished.fulfill() }
        let root = try directory()
        let cache = PersistentCollectionTokenCache(rootURL: root, activity: .init(perform: activity.begin)) { _ in
            started.fulfill()
            try await Task.sleep(for: .seconds(60))
            return (Data(), 200)
        }
        let reader = Task { try await cache.data(for: "fidenza") }
        await fulfillment(of: [started], timeout: 2)
        reader.cancel()
        do { _ = try await reader.value; XCTFail("Cancelled reader should fail") }
        catch is CancellationError {}
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fidenza.json").path))
    }

    func testSuccessfulActivityEndsAfterPublishingAndCacheHitsNeedNoActivity() async throws {
        let root = try directory()
        let finished = expectation(description: "Background activity finished")
        let activity = TokenCacheActivityProbe { finished.fulfill() }
        let bytes = manifest
        let cache = PersistentCollectionTokenCache(rootURL: root, activity: .init(perform: activity.begin)) { _ in (bytes, 200) }
        let data = try await cache.data(for: "fidenza")
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(data, manifest)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("fidenza.json")), manifest)
        let cached = try await cache.data(for: "fidenza")
        XCTAssertEqual(cached, manifest)
    }

    func testCancelingFinalReaderReleasesLockWithoutPublishing() async throws {
        let root = try directory()
        let probe = TokenManifestTransportProbe(bytes: manifest, held: true)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        let reader = Task { try await cache.data(for: "fidenza") }
        await probe.waitUntilCalled()
        reader.cancel()
        do { _ = try await reader.value; XCTFail("Canceled reader should stop") }
        catch is CancellationError {}
        await probe.release()
        let offline = TokenManifestTransportProbe(bytes: manifest, offline: true)
        let independent = PersistentCollectionTokenCache(
            rootURL: root,
            transport: { try await offline.fetch($0) },
            lockTimeout: .seconds(2)
        )
        do { _ = try await independent.data(for: "fidenza"); XCTFail("Canceled download should not publish") }
        catch TokenManifestTransportProbe.Failure.offline {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fidenza.json").path))
        let calls = await offline.calls
        XCTAssertEqual(calls, 1)
        await offline.replace(bytes: manifest)
        let retried = try await independent.data(for: "fidenza")
        XCTAssertEqual(retried, manifest)
    }

    func testContendedLockTimesOutWithoutDownloadingAndCanRetry() async throws {
        let root = try directory()
        let lockURL = root.appendingPathComponent("fidenza.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let originalInode = try FileManager.default.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as? NSNumber
        let probe = TokenManifestTransportProbe(bytes: manifest)
        let cache = PersistentCollectionTokenCache(
            rootURL: root,
            transport: { try await probe.fetch($0) },
            lockTimeout: .milliseconds(25)
        )
        do { _ = try await cache.data(for: "fidenza"); XCTFail("Held lock should time out") }
        catch let failure as PersistentCollectionTokenCache.Failure { XCTAssertEqual(failure, .lockTimeout) }
        let blockedCalls = await probe.calls
        XCTAssertEqual(blockedCalls, 0)
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        let data = try await cache.data(for: "fidenza")
        XCTAssertEqual(data, manifest)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        let finalInode = try FileManager.default.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as? NSNumber
        XCTAssertEqual(originalInode, finalInode)
    }

    func testDiskOnlyMissDoesNotDownloadAndCorruptFileCanBeRepaired() async throws {
        let root = try directory()
        let probe = TokenManifestTransportProbe(bytes: manifest, offline: true)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        let missing = try await cache.cachedData(for: "fidenza")
        XCTAssertNil(missing)
        let initialCalls = await probe.calls
        XCTAssertEqual(initialCalls, 0)
        let file = root.appendingPathComponent("fidenza.json")
        try Data("broken".utf8).write(to: file)
        let corrupt = try await cache.cachedData(for: "fidenza")
        XCTAssertNil(corrupt)
        do { _ = try await cache.data(for: "fidenza"); XCTFail("Offline miss should fail") }
        catch TokenManifestTransportProbe.Failure.offline {}
        await probe.replace(bytes: manifest)
        let repaired = try await cache.data(for: "fidenza")
        XCTAssertEqual(repaired, manifest)
        XCTAssertEqual(try Data(contentsOf: file), manifest)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }

    func testHTTPAndSchemaFailuresAreNeverPublishedAndRemainRetryable() async throws {
        let invalid: [String] = [
            "not JSON",
            #"{"version":1,"count":1,"firstId":"0"}"#,
            #"{"version":2,"count":2,"ids":["0"]}"#,
            #"{"version":2,"count":1,"firstId":"0","name":[4]}"#,
            #"{"version":2,"count":1,"firstId":"0","hash":[false]}"#,
            #"{"version":2,"count":1,"firstId":"0","urlSuffix":[4]}"#,
            #"{"version":2,"count":1,"firstId":"0","aspectRatio":[[3,0]]}"#,
            #"{"version":2,"count":1,"firstId":"0","aspectRatio":[[3,4,5]]}"#,
            #"{"version":2,"count":1,"firstId":"0","contractParameters":[{"seed":42}]}"#,
            #"{"version":2,"count":1,"firstId":"0","excludedMediaIndices":[1]}"#
        ]
        let failures = invalid.map { (Data($0.utf8), 200, PersistentCollectionTokenCache.Failure.invalidManifest) }
            + [(manifest, 503, .httpStatus(503))]
        for (bytes, status, expected) in failures {
            let root = try directory()
            let probe = TokenManifestTransportProbe(bytes: bytes, statusCode: status)
            let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
            do { _ = try await cache.data(for: "fidenza"); XCTFail("Invalid payload should fail") }
            catch let failure as PersistentCollectionTokenCache.Failure { XCTAssertEqual(failure, expected) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fidenza.json").path))
            await probe.replace(bytes: manifest)
            let repaired = try await cache.data(for: "fidenza")
            XCTAssertEqual(repaired, manifest)
            let calls = await probe.calls
            XCTAssertEqual(calls, 2)
        }
    }

    func testUnsafeResourceNamesNeverAccessTransport() async throws {
        let probe = TokenManifestTransportProbe(bytes: manifest)
        let cache = PersistentCollectionTokenCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        for name in ["", ".", "..", "../fidenza", "a/b", "a\\b", "fidenza.json", "fidenza?x=1"] {
            do { _ = try await cache.data(for: name); XCTFail("Unsafe resource name should fail") }
            catch let failure as PersistentCollectionTokenCache.Failure { XCTAssertEqual(failure, .invalidResourceName) }
            do { _ = try await cache.cachedData(for: name); XCTFail("Unsafe cached resource name should fail") }
            catch let failure as PersistentCollectionTokenCache.Failure { XCTAssertEqual(failure, .invalidResourceName) }
        }
        let calls = await probe.calls
        XCTAssertEqual(calls, 0)
    }

    func testUnsafeCacheEntryIsNotReadOrOverwritten() async throws {
        let root = try directory()
        let target = root.appendingPathComponent("original")
        try manifest.write(to: target)
        let file = root.appendingPathComponent("fidenza.json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let probe = TokenManifestTransportProbe(bytes: manifest)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        do { _ = try await cache.data(for: "fidenza"); XCTFail("Symlink should fail") }
        catch let failure as PersistentCollectionTokenCache.Failure { XCTAssertEqual(failure, .unsafeCacheFile) }
        XCTAssertEqual(try Data(contentsOf: target), manifest)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        let calls = await probe.calls
        XCTAssertEqual(calls, 0)
    }

    func testUnusableStorageFailsAndCanRetryAfterRepair() async throws {
        let root = try directory().appendingPathComponent("storage")
        try Data("not a directory".utf8).write(to: root)
        let probe = TokenManifestTransportProbe(bytes: manifest)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await probe.fetch($0) })
        do { _ = try await cache.data(for: "fidenza"); XCTFail("Unusable storage should fail") }
        catch {}
        let blockedCalls = await probe.calls
        XCTAssertEqual(blockedCalls, 0)
        try FileManager.default.removeItem(at: root)
        let repaired = try await cache.data(for: "fidenza")
        XCTAssertEqual(repaired, manifest)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testOnlyOwnedStagingFilesAreRemovedBeforeRetry() async throws {
        let root = try directory()
        let stale = root.appendingPathComponent(".fidenza.abandoned.partial")
        let unrelated = root.appendingPathComponent(".other.abandoned.partial")
        let overlappingName = root.appendingPathComponent(".fidenza-other.active.partial")
        try Data("partial".utf8).write(to: stale)
        try Data("keep".utf8).write(to: unrelated)
        try Data("active".utf8).write(to: overlappingName)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { [manifest] _ in (manifest, 200) })
        _ = try await cache.data(for: "fidenza")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: overlappingName), Data("active".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), [".fidenza-other.active.partial", ".other.abandoned.partial", "fidenza.json", "fidenza.lock"])
    }

    func testPersistenceFailureDoesNotReturnUncachedNetworkBytes() async throws {
        let root = try directory()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { [manifest] _ in
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            return (manifest, 200)
        })
        do { _ = try await cache.data(for: "fidenza"); XCTFail("Persistence failure should fail the request") }
        catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fidenza.json").path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let repaired = PersistentCollectionTokenCache(rootURL: root, transport: { [manifest] _ in (manifest, 200) })
        let data = try await repaired.data(for: "fidenza")
        XCTAssertEqual(data, manifest)
    }
}
