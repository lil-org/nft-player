import CryptoKit
import Foundation
import XCTest
@testable import NftPlayerSyncCore

private actor DependencyTransportProbe {
    enum Failure: Error { case offline }
    private(set) var calls = 0
    private(set) var urls: [URL] = []
    var bytes: Data
    var statusCode: Int
    var offline: Bool
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
final class PersistentArtworkDependencyCacheTests: XCTestCase {
    private let javascript = Data("globalThis.hypertypeFixture = 'verified dependency';\n".utf8)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArtworkDependenciesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func descriptor(_ data: Data) -> PersistentArtworkDependency {
        PersistentArtworkDependency(
            collectionId: PersistentArtworkDependency.hypertype.collectionId,
            remoteURL: URL(string: "https://example.test/hypertype/dependency.js")!,
            expectedByteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func file(in root: URL, for dependency: PersistentArtworkDependency) -> URL {
        root.appendingPathComponent("hypertype").appendingPathComponent(dependency.sha256 + ".js")
    }

    func testHypertypeDescriptorIsPinnedAndOtherCollectionsNeedNoDependency() {
        let dependency = PersistentArtworkDependency.hypertype
        XCTAssertEqual(dependency.collectionId, "0xbb5471c292065d3b01b2e81e299267221ae9a2500")
        XCTAssertEqual(dependency.remoteURL.absoluteString, "https://cdn.lil.org/player/hypertype/dependency.js")
        XCTAssertEqual(dependency.expectedByteCount, 712_587)
        XCTAssertEqual(dependency.sha256, "48d2613055cacdf43217ed43710990150ef2afaa15540c69d2b840d80fd4b6c8")
        XCTAssertEqual(PersistentArtworkDependency.forCollection(dependency.collectionId.uppercased()), dependency)
        XCTAssertNil(PersistentArtworkDependency.forCollection("other-collection"))
    }

    func testColdLoadPersistsValidatedBytesWithBackupExclusion() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let probe = DependencyTransportProbe(bytes: javascript)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        let data = try await cache.data(for: dependency)
        XCTAssertEqual(data, javascript)
        XCTAssertEqual(try Data(contentsOf: file(in: root, for: dependency)), javascript)
        let calls = await probe.calls
        let urls = await probe.urls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(urls, [dependency.remoteURL])
        for url in [root, root.appendingPathComponent("hypertype"), file(in: root, for: dependency)] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
    }

    func testRecreatedCacheWorksOfflineWithoutNetworkOrRevalidationRequest() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let first = PersistentArtworkDependencyCache(rootURL: root, transport: { [javascript] _ in (javascript, 200) })
        _ = try await first.data(for: dependency)
        let file = file(in: root, for: dependency)
        let oldDate = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        let offline = DependencyTransportProbe(bytes: Data(), offline: true)
        let recreated = PersistentArtworkDependencyCache(rootURL: root, transport: { try await offline.fetch($0) })
        let firstRead = try await recreated.data(for: dependency)
        let secondRead = try await recreated.data(for: dependency)
        XCTAssertEqual(firstRead, javascript)
        XCTAssertEqual(secondRead, javascript)
        let calls = await offline.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, oldDate)
    }

    func testConcurrentConsumersShareOneRequestAndPublishedFile() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let probe = DependencyTransportProbe(bytes: javascript, held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        let readers = (0..<30).map { _ in Task { try await cache.data(for: dependency) } }
        await probe.waitUntilCalled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(in: root, for: dependency).path))
        await probe.release()
        for reader in readers {
            let result = try await reader.value
            XCTAssertEqual(result, javascript)
        }
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("hypertype").path), [dependency.sha256 + ".js"])
    }

    func testCancellationDoesNotCancelSharedDownloadOrOtherConsumer() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let probe = DependencyTransportProbe(bytes: javascript, held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        let stopped = expectation(description: "Consumer stops before download finishes")
        let canceled = Task {
            do { _ = try await cache.data(for: dependency); XCTFail("Canceled consumer should stop waiting") }
            catch is CancellationError { stopped.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await probe.waitUntilCalled()
        canceled.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        let remaining = Task { try await cache.data(for: dependency) }
        let previewStopped = expectation(description: "Preview stops before download finishes")
        let preview = Task {
            do { _ = try await cache.cachedData(for: dependency); XCTFail("Canceled preview should stop waiting") }
            catch is CancellationError { previewStopped.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        for _ in 0..<10 { await Task.yield() }
        preview.cancel()
        await fulfillment(of: [previewStopped], timeout: 2)
        await probe.release()
        await canceled.value
        await preview.value
        let result = try await remaining.value
        XCTAssertEqual(result, javascript)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try Data(contentsOf: file(in: root, for: dependency)), javascript)
    }

    func testDiskCorruptionIsCheckedOnEveryUseAndRepaired() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let probe = DependencyTransportProbe(bytes: javascript)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        _ = try await cache.data(for: dependency)
        let destination = file(in: root, for: dependency)
        try Data(repeating: 65, count: javascript.count).write(to: destination)
        let repaired = try await cache.data(for: dependency)
        XCTAssertEqual(repaired, javascript)
        XCTAssertEqual(try Data(contentsOf: destination), javascript)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }

    func testCorruptDiskIsDiscardedAndOfflineFailureCanRetry() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let destination = file(in: root, for: dependency)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("incomplete".utf8).write(to: destination)
        let probe = DependencyTransportProbe(bytes: javascript, offline: true)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        do { _ = try await cache.data(for: dependency); XCTFail("Offline miss should fail") }
        catch DependencyTransportProbe.Failure.offline {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        await probe.replace(bytes: javascript)
        let data = try await cache.data(for: dependency)
        XCTAssertEqual(data, javascript)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }

    func testHTTPSizeAndHashFailuresNeverPublishAndRemainRetryable() async throws {
        let invalidResponses: [(Data, Int, PersistentArtworkDependencyCache.Failure)] = [
            (javascript, 503, .httpStatus(503)),
            (Data(), 200, .byteCount(expected: javascript.count, actual: 0)),
            (Data(repeating: 65, count: javascript.count), 200, .checksum)
        ]
        for (bytes, status, expected) in invalidResponses {
            let root = try directory()
            let dependency = descriptor(javascript)
            let probe = DependencyTransportProbe(bytes: bytes, statusCode: status)
            let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
            do { _ = try await cache.data(for: dependency); XCTFail("Invalid response should fail") }
            catch let error as PersistentArtworkDependencyCache.Failure { XCTAssertEqual(error, expected) }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("hypertype").path), [])
            await probe.replace(bytes: javascript)
            let result = try await cache.data(for: dependency)
            XCTAssertEqual(result, javascript)
            let calls = await probe.calls
            XCTAssertEqual(calls, 2)
        }
    }

    func testInvalidUTF8FailsEvenWhenSizeAndHashMatch() async throws {
        let root = try directory()
        let bytes = Data([0xC3, 0x28])
        let dependency = descriptor(bytes)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { _ in (bytes, 200) })
        do { _ = try await cache.data(for: dependency); XCTFail("Invalid UTF8 should fail") }
        catch let error as PersistentArtworkDependencyCache.Failure { XCTAssertEqual(error, .invalidUTF8) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(in: root, for: dependency).path))
    }

    func testStaleOwnedStagingIsRemovedWhileUnrelatedFilesRemain() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let directory = root.appendingPathComponent("hypertype")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stale = directory.appendingPathComponent(".\(dependency.sha256)-interrupted.partial")
        let unrelated = directory.appendingPathComponent("unrelated.partial")
        try Data("partial bytes".utf8).write(to: stale)
        try Data("keep".utf8).write(to: unrelated)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { [javascript] _ in (javascript, 200) })
        _ = try await cache.data(for: dependency)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), Set([dependency.sha256 + ".js", "unrelated.partial"]))
    }

    func testWriteFailureDoesNotPublishAndNextCallCanRetry() async throws {
        let root = try directory()
        let dependency = descriptor(javascript)
        let probe = DependencyTransportProbe(bytes: javascript, held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        let load = Task { try await cache.data(for: dependency) }
        await probe.waitUntilCalled()
        let directory = root.appendingPathComponent("hypertype")
        try FileManager.default.removeItem(at: directory)
        try Data("blocking file".utf8).write(to: directory)
        await probe.release()
        do { _ = try await load.value; XCTFail("Publication should fail") }
        catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(in: root, for: dependency).path))
        try FileManager.default.removeItem(at: directory)
        let retried = try await cache.data(for: dependency)
        XCTAssertEqual(retried, javascript)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }
}
