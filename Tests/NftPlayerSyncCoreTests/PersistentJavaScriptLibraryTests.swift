import CryptoKit
import Foundation
import XCTest
@testable import NftPlayerSyncCore

private actor LibraryTransportProbe {
    enum Failure: Error { case offline }
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var maximumActive = 0
    private var held: Bool
    private var offline = false
    private var data: [URL: Data]
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    init(data: [URL: Data], held: Bool = false) {
        self.data = data
        self.held = held
    }

    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        calls += 1
        active += 1
        maximumActive = max(maximumActive, active)
        let ready = observers.filter { calls >= $0.0 }
        observers.removeAll { calls >= $0.0 }
        ready.forEach { $0.1.resume() }
        defer { active -= 1 }
        if held { await withCheckedContinuation { pending.append($0) } }
        if offline { throw Failure.offline }
        return (data[url] ?? Data(), 200)
    }

    func waitForCalls(_ count: Int) async {
        if calls < count { await withCheckedContinuation { observers.append((count, $0)) } }
    }

    func release() {
        held = false
        pending.forEach { $0.resume() }
        pending.removeAll()
    }

    func setOffline(_ value: Bool) { offline = value }
}

@MainActor
final class PersistentJavaScriptLibraryTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixture(_ dependency: PersistentArtworkDependency) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("nft-player-iosTests/Fixtures/JavaScriptLibraries/" + dependency.remoteURL.lastPathComponent))
    }

    private func cacheFiles(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("libraries"), includingPropertiesForKeys: nil)
    }

    func testAllElevenCDNDescriptorsMatchUnmodifiedFixtures() throws {
        XCTAssertEqual(PersistentJavaScriptLibrary.all.count, 11)
        XCTAssertEqual(Set(PersistentJavaScriptLibrary.all.map(\.id)).count, 11)
        var bytes = 0
        for dependency in PersistentJavaScriptLibrary.all {
            XCTAssertEqual(dependency.remoteURL.deletingLastPathComponent().absoluteString, "https://cdn.lil.org/player/lib/")
            XCTAssertEqual(PersistentJavaScriptLibrary.library(named: dependency.remoteURL.lastPathComponent), dependency)
            let data = try fixture(dependency)
            bytes += data.count
            XCTAssertEqual(data.count, dependency.expectedByteCount)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), dependency.sha256)
        }
        XCTAssertEqual(bytes, 5_307_166)
        XCTAssertNil(PersistentJavaScriptLibrary.library(named: "js"))
        XCTAssertNil(PersistentJavaScriptLibrary.library(named: "native.poncho-drifella"))
    }

    func testResolverPreservesInlineBytesModuleURLsAndScriptOrdering() async throws {
        let three = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "three167"))
        let tone = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "tone1504"))
        let threeBytes = try fixture(three)
        let toneBytes = try fixture(tone)
        let cache = PersistentArtworkDependencyCache(rootURL: try directory()) { url in
            (url == three.remoteURL ? threeBytes : toneBytes, 200)
        }
        let inline = PersistentJavaScriptLibrary.reference(for: tone)
        let module = try XCTUnwrap(PersistentJavaScriptLibrary.dataURLReference(forInlineReference: PersistentJavaScriptLibrary.reference(for: three)))
        let escaped = PersistentJavaScriptLibrary.reference(for: tone, format: .escapedInline)
        let html = "<script>\(inline)</script><script type=\"importmap\">{\"imports\":{\"three\":\"\(module)\"}}</script><script>artist()</script><script>\(escaped)</script>"
        XCTAssertEqual(PersistentJavaScriptLibrary.requiredDependencies(in: html), [tone, three])
        let result = try await PersistentJavaScriptLibrary.resolve(html, cache: cache)
        let expected = html.replacingOccurrences(of: inline, with: String(decoding: toneBytes, as: UTF8.self))
            .replacingOccurrences(of: module, with: "data:text/javascript;base64," + threeBytes.base64EncodedString())
            .replacingOccurrences(of: escaped, with: String(decoding: toneBytes, as: UTF8.self).replacingOccurrences(of: "</script", with: "<\\/script"))
        XCTAssertEqual(result, expected)
        XCTAssertTrue(PersistentJavaScriptLibrary.requiredDependencies(in: result).isEmpty)
    }

    func testLiteralResolutionHandlesUnicodeAndRepeatedReferencesWithoutChangingOtherText() async throws {
        let library = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let bytes = try fixture(library)
        let hypertype = PersistentArtworkDependency.hypertype
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let hypertypeBytes = try Data(contentsOf: root.appendingPathComponent("nft-player-iosTests/Fixtures/Hypertype/dependency.js"))
        let cache = PersistentArtworkDependencyCache(rootURL: try directory()) { url in
            (url == library.remoteURL ? bytes : hypertypeBytes, 200)
        }
        let inline = PersistentJavaScriptLibrary.reference(for: library)
        let module = PersistentJavaScriptLibrary.reference(for: library, format: .dataURL)
        let dynamic = PersistentJavaScriptLibrary.hypertypeReference
        let prefix = "🎨é e\u{301} 日本語 𝄞"
        let html = prefix + "<script>" + inline + "</script>" + prefix + dynamic + module + inline + dynamic + prefix
        XCTAssertEqual(PersistentJavaScriptLibrary.requiredDependencies(in: html), [library, hypertype])
        let resolved = try await PersistentJavaScriptLibrary.resolve(html, cache: cache)
        let expected = html.replacingOccurrences(of: inline, with: String(decoding: bytes, as: UTF8.self))
            .replacingOccurrences(of: module, with: "data:text/javascript;base64," + bytes.base64EncodedString())
            .replacingOccurrences(of: dynamic, with: "data:text/javascript;base64," + hypertypeBytes.base64EncodedString())
        XCTAssertEqual(Data(resolved.utf8), Data(expected.utf8))
        XCTAssertTrue(PersistentJavaScriptLibrary.requiredDependencies(in: resolved).isEmpty)
    }

    func testSharedLibraryRequestsUseAtMostFourConcurrentDownloads() async throws {
        let root = try directory()
        let fixtures = try Dictionary(uniqueKeysWithValues: PersistentJavaScriptLibrary.all.map { ($0.remoteURL, try fixture($0)) })
        let probe = LibraryTransportProbe(data: fixtures, held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        let readers = PersistentJavaScriptLibrary.all.flatMap { dependency in
            (0..<3).map { _ in Task { try await cache.data(for: dependency) } }
        }
        await probe.waitForCalls(4)
        let active = await probe.active
        XCTAssertEqual(active, 4)
        await probe.release()
        for reader in readers { _ = try await reader.value }
        let calls = await probe.calls
        let maximum = await probe.maximumActive
        XCTAssertEqual(calls, 11)
        XCTAssertLessThanOrEqual(maximum, 4)
        XCTAssertEqual(try cacheFiles(root).count, 11)
    }

    func testLibraryCacheSurvivesMediaEvictionAndRecoversAfterSystemPurge() async throws {
        let root = try directory()
        let library = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [library.remoteURL: try fixture(library)])
        let dependencyRoot = root.appendingPathComponent("ArtworkDependencies")
        let mediaRoot = root.appendingPathComponent("DownloadableMedia")
        let cache = PersistentArtworkDependencyCache(rootURL: dependencyRoot, transport: { try await probe.fetch($0) })
        let original = try await cache.data(for: library)
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        try Data("evictable".utf8).write(to: mediaRoot.appendingPathComponent("image.webp"))
        try FileManager.default.removeItem(at: mediaRoot)
        await probe.setOffline(true)
        let reopened = PersistentArtworkDependencyCache(rootURL: dependencyRoot, transport: { try await probe.fetch($0) })
        let offline = try await reopened.data(for: library)
        XCTAssertEqual(offline, original)
        try FileManager.default.removeItem(at: dependencyRoot)
        await probe.setOffline(false)
        let repaired = try await reopened.data(for: library)
        XCTAssertEqual(repaired, original)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }

    func testPendingGateIsImmediateCoalescesAndDeliversOnlyLatestCallbacks() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: try fixture(dependency)], held: true)
        let gate = PersistentWebContentLoadGate()
        gate.cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let html = "<script>\(PersistentJavaScriptLibrary.reference(for: dependency))</script>"
        var starts = 0
        let ready = expectation(description: "latest callback")
        XCTAssertTrue(gate.load(html, context: "collection:0", onStart: { starts += 1 }, onReady: { _ in XCTFail("Replaced callback") }, onFailure: { _ in XCTFail() }))
        XCTAssertEqual(starts, 1)
        await probe.waitForCalls(1)
        XCTAssertTrue(gate.load(html, context: "collection:0", onStart: { starts += 1 }, onReady: { result in
            XCTAssertFalse(result.contains("nft-player-library:"))
            ready.fulfill()
        }, onFailure: { _ in XCTFail() }))
        await probe.release()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(starts, 1)
        var warm = false
        gate.cancel()
        XCTAssertTrue(gate.load(html, context: "collection:0", onStart: { XCTFail("Warm load should not clear visible artwork") }, onReady: { _ in warm = true }, onFailure: { _ in XCTFail() }))
        XCTAssertTrue(warm)
    }

    func testGateCancellationAndResetRejectStaleCompletionWithoutCancelingSharedDownload() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: try fixture(dependency)], held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let gate = PersistentWebContentLoadGate()
        gate.cache = cache
        let html = PersistentJavaScriptLibrary.reference(for: dependency)
        gate.load(html, context: "old-token", onStart: {}, onReady: { _ in XCTFail("Canceled token rendered") }, onFailure: { _ in XCTFail() })
        await probe.waitForCalls(1)
        gate.reset()
        let ready = expectation(description: "new token rendered")
        gate.load(html, context: "new-token", onStart: {}, onReady: { _ in ready.fulfill() }, onFailure: { _ in XCTFail() })
        await probe.release()
        await fulfillment(of: [ready], timeout: 5)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        gate.reset()
        var started = false
        let second = expectation(description: "cached disk read")
        gate.load(html, context: "new-token", onStart: { started = true }, onReady: { _ in second.fulfill() }, onFailure: { _ in XCTFail() })
        XCTAssertTrue(started)
        await fulfillment(of: [second], timeout: 5)
    }

    func testGateLibraryFreeNavigationRejectsPendingArtwork() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: try fixture(dependency)], held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let gate = PersistentWebContentLoadGate()
        gate.cache = cache
        gate.load(PersistentJavaScriptLibrary.reference(for: dependency), context: "old", onStart: {}, onReady: { _ in XCTFail() }, onFailure: { _ in XCTFail() })
        await probe.waitForCalls(1)
        XCTAssertFalse(gate.load("<html>no library</html>", context: "new", onStart: { XCTFail() }, onReady: { _ in XCTFail() }, onFailure: { _ in XCTFail() }))
        await probe.release()
        _ = try await cache.data(for: dependency)
        for _ in 0..<10 { await Task.yield() }
    }

    func testCacheOnlyMissDoesNotCreateStorageOrStartDownload() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: try fixture(dependency)])
        let root = try directory().appendingPathComponent("absent")
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        let bytes = try await cache.cachedData(for: dependency)
        XCTAssertNil(bytes)
        do {
            _ = try await PersistentJavaScriptLibrary.resolve(PersistentJavaScriptLibrary.reference(for: dependency), cache: cache, allowsDownloads: false)
            XCTFail("Missing cache-only dependency should fail")
        } catch let error as PersistentArtworkDependencyCache.Failure {
            XCTAssertEqual(error, .notCached)
        }
        let calls = await probe.calls
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testCacheOnlyReadUsesVerifiedOfflineBytesAndNeverRepairsCorruptionThroughNetwork() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let root = try directory()
        let fixture = try fixture(dependency)
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: fixture])
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        _ = try await cache.data(for: dependency)
        await probe.setOffline(true)
        let reopened = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        let bytes = try await reopened.cachedData(for: dependency)
        XCTAssertEqual(bytes, fixture)
        let html = try await PersistentJavaScriptLibrary.resolve(PersistentJavaScriptLibrary.reference(for: dependency), cache: reopened, allowsDownloads: false)
        XCTAssertEqual(html, String(decoding: fixture, as: UTF8.self))
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("libraries/" + dependency.sha256 + ".js"))
        let corrupt = try await reopened.cachedData(for: dependency)
        XCTAssertNil(corrupt)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testCacheOnlyReadJoinsSelectedCollectionsExistingDownload() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let fixture = try fixture(dependency)
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: fixture], held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let selected = Task { try await cache.data(for: dependency) }
        await probe.waitForCalls(1)
        let preview = Task { try await cache.cachedData(for: dependency) }
        for _ in 0..<10 { await Task.yield() }
        await probe.release()
        let selectedBytes = try await selected.value
        let previewBytes = try await preview.value
        XCTAssertEqual(selectedBytes, fixture)
        XCTAssertEqual(previewBytes, fixture)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testPreviewInspectionCannotRaceForegroundCorruptionRepair() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "p5js11111"))
        let bytes = try fixture(dependency)
        let corrupt = Data(repeating: 32, count: bytes.count)
        let root = try directory()
        let file = root.appendingPathComponent("libraries/" + dependency.sha256 + ".js")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: bytes])
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.fetch($0) })
        for _ in 0..<100 {
            try corrupt.write(to: file)
            let preview = Task { try await cache.cachedData(for: dependency) }
            await Task.yield()
            let repaired = try await cache.data(for: dependency)
            let cached = try await preview.value
            XCTAssertEqual(repaired, bytes)
            XCTAssertTrue(cached == nil || cached == bytes)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
        let calls = await probe.calls
        XCTAssertEqual(calls, 100)
    }

    func testGatePolicyChangeReplacesPendingPreviewAndKeepsSharedDownload() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: try fixture(dependency)], held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let preload = Task { try await cache.data(for: dependency) }
        await probe.waitForCalls(1)
        let gate = PersistentWebContentLoadGate()
        gate.cache = cache
        let html = PersistentJavaScriptLibrary.reference(for: dependency)
        var starts = 0
        gate.load(html, context: "same-artwork", allowsDownloads: false, onStart: { starts += 1 }, onReady: { _ in XCTFail("Preview was replaced") }, onFailure: { _ in XCTFail() })
        for _ in 0..<10 { await Task.yield() }
        let ready = expectation(description: "selected callback")
        gate.load(html, context: "same-artwork", allowsDownloads: true, onStart: { starts += 1 }, onReady: { _ in ready.fulfill() }, onFailure: { _ in XCTFail() })
        XCTAssertEqual(starts, 2)
        await probe.release()
        _ = try await preload.value
        await fulfillment(of: [ready], timeout: 5)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testGateAllowsSelectedCollectionToDownloadAfterCacheOnlyPreviewMiss() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: try fixture(dependency)])
        let gate = PersistentWebContentLoadGate()
        gate.cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let html = PersistentJavaScriptLibrary.reference(for: dependency)
        let failed = expectation(description: "cache-only miss")
        gate.load(html, context: "same-artwork", allowsDownloads: false, onStart: {}, onReady: { _ in XCTFail() }, onFailure: { error in
            XCTAssertEqual(error as? PersistentArtworkDependencyCache.Failure, .notCached)
            failed.fulfill()
        })
        await fulfillment(of: [failed], timeout: 5)
        let initialCalls = await probe.calls
        XCTAssertEqual(initialCalls, 0)
        let ready = expectation(description: "selected artwork downloaded")
        gate.load(html, context: "same-artwork", allowsDownloads: true, onStart: {}, onReady: { _ in ready.fulfill() }, onFailure: { _ in XCTFail() })
        await fulfillment(of: [ready], timeout: 5)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testMultiLibraryFailureSurfacesBeforeSiblingDownloadFinishesAndCanRetry() async throws {
        let tone = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "tone1504"))
        let three = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "three167"))
        let failing = LibraryTransportProbe(data: [tone.remoteURL: try fixture(tone)], held: true)
        let held = LibraryTransportProbe(data: [three.remoteURL: try fixture(three)], held: true)
        await failing.setOffline(true)
        let gate = PersistentWebContentLoadGate()
        gate.cache = PersistentArtworkDependencyCache(rootURL: try directory()) { url in
            try await (url == tone.remoteURL ? failing : held).fetch(url)
        }
        let html = PersistentJavaScriptLibrary.reference(for: tone) + PersistentJavaScriptLibrary.reference(for: three)
        let failed = expectation(description: "Failure surfaces while sibling is still downloading")
        gate.load(html, context: "token", onStart: {}, onReady: { _ in XCTFail() }, onFailure: { error in
            XCTAssertTrue(error is LibraryTransportProbe.Failure)
            failed.fulfill()
        })
        await failing.waitForCalls(1)
        await held.waitForCalls(1)
        await failing.release()
        await fulfillment(of: [failed], timeout: 2)
        await failing.setOffline(false)
        let ready = expectation(description: "Retry reuses sibling download")
        gate.load(html, context: "token", onStart: {}, onReady: { _ in ready.fulfill() }, onFailure: { _ in XCTFail() })
        await held.release()
        await fulfillment(of: [ready], timeout: 5)
        let failedCalls = await failing.calls
        let siblingCalls = await held.calls
        XCTAssertEqual(failedCalls, 2)
        XCTAssertEqual(siblingCalls, 1)
    }

    func testGateFailureRemainsRetryable() async throws {
        let dependency = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "twemoji"))
        let probe = LibraryTransportProbe(data: [dependency.remoteURL: try fixture(dependency)])
        await probe.setOffline(true)
        let gate = PersistentWebContentLoadGate()
        gate.cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        let html = PersistentJavaScriptLibrary.reference(for: dependency)
        let failed = expectation(description: "failure surfaced")
        gate.load(html, context: "token", onStart: {}, onReady: { _ in XCTFail() }, onFailure: { _ in failed.fulfill() })
        await fulfillment(of: [failed], timeout: 5)
        await probe.setOffline(false)
        let ready = expectation(description: "retry succeeded")
        gate.load(html, context: "token", onStart: {}, onReady: { _ in ready.fulfill() }, onFailure: { _ in XCTFail() })
        await fulfillment(of: [ready], timeout: 5)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }
}
