import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class PersistentArtworkDependencyLoadingTests: CollectionTokenFixtureTestCase {}

nonisolated final class ArtworkContentResolverTests: CollectionTokenFixtureTestCase {}

private actor ArtworkSourceTransport {
    private(set) var urls: [URL] = []
    private var held: Bool
    private var failuresRemaining: Int
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(held: Bool = false, failures: Int = 0) {
        self.held = held
        failuresRemaining = failures
    }

    func download(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        guard let dependency = JavaScriptLibraryFixtures.dependencies.first(where: { $0.remoteURL == url }) else {
            throw URLError(.unsupportedURL)
        }
        urls.append(url)
        if held { await withCheckedContinuation { continuations.append($0) } }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            return (Data(), 503)
        }
        return (try JavaScriptLibraryFixtures.data(for: dependency), 200)
    }

    func release() {
        held = false
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

@MainActor
extension ArtworkContentResolverTests {
    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func item(_ slug: String = "meridian") throws -> SuggestedItem {
        try XCTUnwrap(SuggestedItemsService.scriptItem(collectionId: slug))
    }

    private func token(_ item: SuggestedItem, index: Int = 0) throws -> GeneratedToken {
        try XCTUnwrap(TokenGenerator.generateToken(specificCollectionId: item.id, tokenIndex: index))
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Artwork source operation did not reach the expected state")
        throw URLError(.timedOut)
    }

    func testCatalogAndGenerationProduceStableReferencesWithoutSourcePreparation() throws {
        for item in SuggestedItemsService.allItems where item.scriptDependency != nil {
            let first = try token(item)
            let repeated = try token(item)
            XCTAssertEqual(first.html, repeated.html, item.name)
            XCTAssertTrue(ArtworkContentResolver.requiresPreparation(first.html), item.name)
            XCTAssertFalse(first.html.hasPrefix("<html>"), item.name)
            XCTAssertLessThan(first.html.utf8.count, 1_024, item.name)
            XCTAssertTrue(TokenGenerator.needsArtworkPreparation(collectionId: item.id), item.name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: SuggestedItemsService.bundle.bundleURL.appendingPathComponent("Scripts").path))
    }

    func testAllArtworkFixturesMatchCatalogPinsAndStayOutOfApplicationBundle() throws {
        let items = SuggestedItemsService.allItems.filter { $0.scriptDependency != nil }
        XCTAssertEqual(items.count, 405)
        for item in items {
            let dependency = try XCTUnwrap(item.scriptDependency)
            let data = try JavaScriptLibraryFixtures.data(for: dependency)
            let script = try JavaScriptLibraryFixtures.script(collectionId: item.id)
            XCTAssertEqual(Data(script.value.utf8), data, item.name)
            XCTAssertNil(Bundle.main.url(forResource: dependency.sha256, withExtension: item.script?.kind.sourceFileExtension,
                                        subdirectory: "ArtworkScripts"), item.name)
        }
    }

    func testArtworkFixturesUseRendererExtensionAndExplainMissingHydration() throws {
        let dependency = try XCTUnwrap(item("genesis").scriptDependency)
        let expected = try JavaScriptLibraryFixtures.data(for: dependency)
        for sourceURL in ["https://example.test/download", "https://example.test/source.txt"] {
            let overridden = PersistentArtworkDependency(
                id: dependency.id, remoteURL: try XCTUnwrap(URL(string: sourceURL)),
                expectedByteCount: dependency.expectedByteCount, sha256: dependency.sha256
            )
            XCTAssertEqual(try JavaScriptLibraryFixtures.data(for: overridden), expected)
        }
        let missing = PersistentArtworkDependency(
            id: dependency.id, remoteURL: dependency.remoteURL,
            expectedByteCount: dependency.expectedByteCount, sha256: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try JavaScriptLibraryFixtures.data(for: missing)) { error in
            XCTAssertTrue(error.localizedDescription.contains("node scripts/hydrate-artwork-test-sources.mjs"))
            XCTAssertTrue(error.localizedDescription.contains(missing.sha256 + ".pde"))
        }
    }

    func testJavaScriptWithoutLibrariesFetchesSourceOnceAndReopensOffline() async throws {
        let item = try item()
        let dependency = try XCTUnwrap(item.scriptDependency)
        let expected = try JavaScriptLibraryFixtures.script(collectionId: item.id)
        XCTAssertTrue(RawHtmlGenerator.requiredDependencies(for: expected).isEmpty)
        let probe = ArtworkSourceTransport()
        let directory = root()
        let cache = PersistentArtworkDependencyCache(rootURL: directory, transport: { try await probe.download($0) })
        let generated = try token(item)
        let html = try await ArtworkContentResolver.resolve(generated.html, cache: cache)
        XCTAssertTrue(html.contains(expected.value))
        XCTAssertFalse(ArtworkContentResolver.requiresPreparation(html))
        let warm = try await ArtworkContentResolver.resolve(generated.html, cache: cache)
        XCTAssertEqual(warm, html)
        let urls = await probe.urls
        XCTAssertEqual(urls, [dependency.remoteURL])
        let offline = PersistentArtworkDependencyCache(rootURL: directory) { _ in
            XCTFail("Offline source should already be cached")
            throw URLError(.notConnectedToInternet)
        }
        let reopened = try await ArtworkContentResolver.resolve(generated.html, cache: offline)
        XCTAssertEqual(reopened, html)
    }

    func testConcurrentTokenResolutionsShareSourceDownloadAndKeepEachToken() async throws {
        let item = try item()
        let probe = ArtworkSourceTransport(held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: root(), transport: { try await probe.download($0) })
        let tokens = try (0..<8).map { try token(item, index: $0) }
        let tasks = tokens.map { token in Task { try await ArtworkContentResolver.resolve(token.html, cache: cache) } }
        try await waitUntil { await probe.urls.count == 1 }
        await probe.release()
        for (token, task) in zip(tokens, tasks) {
            let html = try await task.value
            XCTAssertTrue(html.contains(token.id))
            XCTAssertFalse(ArtworkContentResolver.requiresPreparation(html))
        }
        let urls = await probe.urls
        XCTAssertEqual(urls, [try XCTUnwrap(item.scriptDependency).remoteURL])
    }

    func testCacheOnlyPreviewDoesNotDownloadSourceOrMissingLibraries() async throws {
        let item = try item("archetype")
        let probe = ArtworkSourceTransport()
        let directory = root()
        let cache = PersistentArtworkDependencyCache(rootURL: directory, transport: { try await probe.download($0) })
        let generated = try token(item)
        do {
            _ = try await ArtworkContentResolver.resolve(generated.html, cache: cache, allowsDownloads: false)
            XCTFail("Cold preview should fail without a source")
        } catch let failure as PersistentArtworkDependencyCache.Failure { XCTAssertEqual(failure, .notCached) }
        var urls = await probe.urls
        XCTAssertEqual(urls, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        _ = try await ArtworkContentResolver.script(collectionId: item.id, cache: cache)
        do {
            _ = try await ArtworkContentResolver.resolve(generated.html, cache: cache, allowsDownloads: false)
            XCTFail("Preview should fail without its library")
        } catch let failure as PersistentArtworkDependencyCache.Failure { XCTAssertEqual(failure, .notCached) }
        urls = await probe.urls
        XCTAssertEqual(urls, [try XCTUnwrap(item.scriptDependency).remoteURL])
        try await ArtworkContentResolver.prepareCollection(collectionId: item.id, cache: cache)
        let preparedURLs = await probe.urls
        let html = try await ArtworkContentResolver.resolve(generated.html, cache: cache, allowsDownloads: false)
        XCTAssertFalse(ArtworkContentResolver.requiresPreparation(html))
        urls = await probe.urls
        XCTAssertEqual(urls, preparedURLs)
        XCTAssertEqual(urls.count, 2)
    }

    func testInvalidReferenceOrSourceVersionCannotStartDownload() async throws {
        let item = try item()
        let generated = try token(item)
        let probe = ArtworkSourceTransport()
        let cache = PersistentArtworkDependencyCache(rootURL: root(), transport: { try await probe.download($0) })
        for reference in [
            "nft-player-artwork:v2:invalid",
            "nft-player-artwork:v1:invalid",
            ArtworkContentResolver.reference(collectionId: item.id, tokenId: generated.id, sha256: String(repeating: "0", count: 64))
        ] {
            XCTAssertTrue(ArtworkContentResolver.requiresPreparation(reference))
            do {
                _ = try await ArtworkContentResolver.resolve(reference, cache: cache)
                XCTFail("Invalid reference should fail")
            } catch let failure as ArtworkContentResolver.Failure { XCTAssertEqual(failure, .invalidReference) }
        }
        let urls = await probe.urls
        XCTAssertEqual(urls, [])
    }

    func testFailedSourceFetchRemainsRetryable() async throws {
        let item = try item()
        let probe = ArtworkSourceTransport(failures: 1)
        let cache = PersistentArtworkDependencyCache(rootURL: root(), transport: { try await probe.download($0) })
        let reference = try token(item).html
        do {
            _ = try await ArtworkContentResolver.resolve(reference, cache: cache)
            XCTFail("First source request should fail")
        } catch let failure as PersistentArtworkDependencyCache.Failure { XCTAssertEqual(failure, .httpStatus(503)) }
        let html = try await ArtworkContentResolver.resolve(reference, cache: cache)
        XCTAssertFalse(ArtworkContentResolver.requiresPreparation(html))
        let urls = await probe.urls
        XCTAssertEqual(urls.count, 2)
    }

    func testFailedSourceFetchShowsRetryBeforeLoadingAnyDocumentAndRecovers() async throws {
        let item = try item("hypertype")
        let dependency = try XCTUnwrap(item.scriptDependency)
        let probe = ArtworkSourceTransport(failures: 1)
        let cache = PersistentArtworkDependencyCache(rootURL: root(), transport: { try await probe.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache, collectionId: item.id)
        defer { fixture.close() }
        try fixture.load()
        try await waitUntil { fixture.showsRetry }
        XCTAssertEqual(fixture.probe.documentCount, 0)
        let failedURLs = await probe.urls
        XCTAssertEqual(failedURLs, [dependency.remoteURL])
        try XCTUnwrap(fixture.retryButton).sendActions(for: .touchUpInside)
        try await waitUntil { await fixture.renderedTokenID() == "0" }
        XCTAssertFalse(fixture.showsRetry)
        XCTAssertEqual(fixture.probe.documentCount, 1)
        let urls = await probe.urls
        XCTAssertEqual(urls.filter { $0 == dependency.remoteURL }.count, 2)
        XCTAssertEqual(urls.count, 3)
    }

    func testWebViewWaitsForSourceAndOnlyLoadsLatestToken() async throws {
        let item = try item("hypertype")
        let probe = ArtworkSourceTransport(held: true)
        let cache = PersistentArtworkDependencyCache(rootURL: root(), transport: { try await probe.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache, collectionId: item.id)
        defer { fixture.close() }
        try fixture.load()
        try await waitUntil { await probe.urls.count == 1 }
        XCTAssertEqual(fixture.probe.documentCount, 0)
        XCTAssertTrue(fixture.webView.hasPersistentDependencyContent)
        try fixture.load(index: 2)
        await probe.release()
        try await waitUntil { await fixture.renderedTokenID() == "2" }
        XCTAssertEqual(fixture.probe.documentCount, 1)
        let urls = await probe.urls
        XCTAssertEqual(urls.filter { $0 == item.scriptDependency?.remoteURL }.count, 1)
        XCTAssertEqual(urls.count, 2)
    }
}

private actor DependencyLoadingTransport {
    private(set) var requests = 0
    private var pending: CheckedContinuation<(data: Data, statusCode: Int), Error>?

    func download(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        if url != PersistentArtworkDependency.hypertype.remoteURL {
            guard let dependency = JavaScriptLibraryFixtures.dependencies.first(where: { $0.remoteURL == url }) else {
                throw URLError(.unsupportedURL)
            }
            return (try JavaScriptLibraryFixtures.data(for: dependency), 200)
        }
        requests += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish(data: Data, statusCode: Int = 200) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: (data, statusCode))
    }
}

@MainActor
final class DependencyLoadingProbe: NSObject, WKScriptMessageHandler {
    var documentCount = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        documentCount += 1
    }
}

@MainActor
final class DependencyRendererFixture {
    let window: UIWindow
    let container: UIView
    let renderer: FullscreenTokenMediaRenderer
    let webView: AutoReloadingWebView
    let probe = DependencyLoadingProbe()
    private weak var previousKeyWindow: UIWindow?
    private let collectionId: String

    init(cache: PersistentArtworkDependencyCache, collectionId: String = PersistentArtworkDependency.hypertype.collectionId) throws {
        self.collectionId = collectionId
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        let host = UIViewController()
        container = UIView(frame: CGRect(x: 0, y: 60, width: 390, height: 600))
        host.view.addSubview(container)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        renderer = FullscreenTokenMediaRenderer(containerView: container, artworkDependencyCache: cache)
        renderer.configureArtBlocksRendering(collectionId: collectionId, tokenId: "0")
        if !TokenGenerator.usesArtBlocksRenderer(collectionId: collectionId) {
            renderer.renderWebContent("", hidesEmptyWebContent: true)
        }
        webView = try XCTUnwrap(Self.descendants(container).compactMap { $0 as? AutoReloadingWebView }.first)
        webView.artworkDependencyCache = cache
        webView.configuration.userContentController.add(probe, name: "dependencyDocumentProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: "document.addEventListener('DOMContentLoaded', function () { if (typeof tokenData !== 'undefined') window.webkit.messageHandlers.dependencyDocumentProbe.postMessage('started'); }, { once: true });",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
    }

    func load(index: Int = 0) throws {
        let id = collectionId
        let token = try XCTUnwrap(TokenGenerator.generateToken(specificCollectionId: id, tokenIndex: index))
        renderer.configureArtBlocksRendering(collectionId: id, tokenId: token.id)
        renderer.renderWebContent(token.html)
        window.layoutIfNeeded()
    }

    var retryButton: UIButton? {
        Self.descendants(container).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "artwork.retry" }
    }

    var showsRetry: Bool {
        guard let button = retryButton else { return false }
        var view: UIView? = button
        while let current = view {
            if current.isHidden || current.alpha == 0 { return false }
            view = current.superview
        }
        return true
    }

    func renderedTokenID() async -> String? {
        try? await webView.evaluateJavaScript("document.querySelector('svg path') ? String(tokenData.tokenId) : null") as? String
    }

    func close() {
        renderer.clearContent()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "dependencyDocumentProbe")
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    private static func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

@MainActor
extension PersistentArtworkDependencyLoadingTests {
    private func asset() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dependency", withExtension: "js", subdirectory: "Hypertype"))
        return try Data(contentsOf: url)
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Dependency renderer did not reach the expected state")
        throw URLError(.timedOut)
    }

    func testArtworkWaitsForSharedPreloadAndStoppedRendererDoesNotCancelIt() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DependencyLoadingTransport()
        let cache = PersistentArtworkDependencyCache(rootURL: directory, transport: { try await transport.download($0) })
        let preload = Task { try await cache.data(for: .hypertype) }
        try await waitUntil { await transport.requests == 1 }
        let stopped = try DependencyRendererFixture(cache: cache)
        let active = try DependencyRendererFixture(cache: cache)
        defer { stopped.close(); active.close() }
        try stopped.load()
        try active.load(index: 1)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stopped.probe.documentCount, 0)
        XCTAssertEqual(active.probe.documentCount, 0)
        stopped.webView.stopLoading()
        let bytes = try asset()
        await transport.finish(data: bytes)
        let downloaded = try await preload.value
        XCTAssertEqual(downloaded, bytes)
        try await waitUntil { await active.renderedTokenID() == "1" }
        XCTAssertEqual(stopped.probe.documentCount, 0)
        let requests = await transport.requests
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(active.showsRetry)
    }

    func testChangingTokenWhileDownloadingOnlyLoadsTheLatestArtwork() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DependencyLoadingTransport()
        let cache = PersistentArtworkDependencyCache(rootURL: directory, transport: { try await transport.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache)
        defer { fixture.close() }
        try fixture.load()
        try await waitUntil { await transport.requests == 1 }
        try fixture.load(index: 2)
        await transport.finish(data: try asset())
        try await waitUntil { await fixture.renderedTokenID() == "2" }
        XCTAssertEqual(fixture.probe.documentCount, 1)
        XCTAssertFalse(fixture.showsRetry)
    }

    func testFailedDownloadOffersNativeRetryAndRecoversWithoutRegeneratingHTML() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DependencyLoadingTransport()
        let cache = PersistentArtworkDependencyCache(rootURL: directory, transport: { try await transport.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache)
        defer { fixture.close() }
        try fixture.load()
        try await waitUntil { await transport.requests == 1 }
        await transport.finish(data: Data("unavailable".utf8), statusCode: 503)
        try await waitUntil { fixture.showsRetry }
        XCTAssertEqual(fixture.probe.documentCount, 0)
        let retry = try XCTUnwrap(fixture.retryButton)
        retry.sendActions(for: .touchUpInside)
        try await waitUntil { await transport.requests == 2 }
        await transport.finish(data: try asset())
        try await waitUntil { await fixture.renderedTokenID() == "0" }
        XCTAssertFalse(fixture.showsRetry)
        XCTAssertEqual(fixture.probe.documentCount, 1)
    }

    func testClearingRendererRejectsLateDownloadFailure() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DependencyLoadingTransport()
        let cache = PersistentArtworkDependencyCache(rootURL: directory, transport: { try await transport.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache)
        defer { fixture.close() }
        try fixture.load()
        try await waitUntil { await transport.requests == 1 }
        fixture.renderer.clearContent()
        await transport.finish(data: Data(), statusCode: 500)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(fixture.showsRetry)
        XCTAssertEqual(fixture.probe.documentCount, 0)
    }

    func testRecreatedCacheLoadsAnotherArtworkOffline() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let online = JavaScriptLibraryFixtures.makeCache(rootURL: directory)
        try await ArtworkContentResolver.prepareCollection(collectionId: PersistentArtworkDependency.hypertype.collectionId, cache: online)
        let offline = PersistentArtworkDependencyCache(rootURL: directory) { _ in throw URLError(.notConnectedToInternet) }
        let fixture = try DependencyRendererFixture(cache: offline)
        defer { fixture.close() }
        try fixture.load(index: 149)
        try await waitUntil { await fixture.renderedTokenID() == "149" }
        XCTAssertFalse(fixture.showsRetry)
        let resources = try await fixture.webView.evaluateJavaScript("performance.getEntriesByType('resource').map(x => x.name).filter(x => /^https?:/.test(x))")
        XCTAssertEqual(resources as? [String], [])
    }

    func testRepeatedHTMLPreservesTheDocumentAndExplicitRetryReloadsIt() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JavaScriptLibraryFixtures.makeCache(rootURL: directory)
        let fixture = try DependencyRendererFixture(cache: cache)
        defer { fixture.close() }
        try fixture.load()
        try await waitUntil { await fixture.renderedTokenID() == "0" }
        let token = try XCTUnwrap(TokenGenerator.generateToken(
            specificCollectionId: PersistentArtworkDependency.hypertype.collectionId,
            tokenIndex: 0
        ))
        _ = try await fixture.webView.evaluateJavaScript("window.persistentDependencySentinel = 42")
        fixture.webView.loadHTMLString(token.html, baseURL: nil)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fixture.probe.documentCount, 1)
        let sentinel = try await fixture.webView.evaluateJavaScript("window.persistentDependencySentinel")
        XCTAssertEqual(sentinel as? Int, 42)
        fixture.webView.retryArtwork()
        try await waitUntil {
            let tokenID = await fixture.renderedTokenID()
            return fixture.probe.documentCount == 2 && tokenID == "0"
        }
    }

    func testReusedRendererClearsAndCoversPreviousArtworkDuringDownload() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DependencyLoadingTransport()
        let cache = PersistentArtworkDependencyCache(rootURL: directory, transport: { try await transport.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache)
        defer { fixture.close() }
        fixture.webView.loadHTMLString("<html><body><script>window.previousArtwork = true</script></body></html>", baseURL: nil)
        try await waitUntil { (try? await fixture.webView.evaluateJavaScript("window.previousArtwork === true")) as? Bool == true }
        try fixture.load()
        try await waitUntil { await transport.requests == 1 }
        XCTAssertTrue(fixture.webView.accessibilityElementsHidden)
        try await waitUntil { (try? await fixture.webView.evaluateJavaScript("typeof window.previousArtwork === 'undefined'")) as? Bool == true }
        await transport.finish(data: try asset())
        try await waitUntil { await fixture.renderedTokenID() == "0" && !fixture.webView.accessibilityElementsHidden }
        XCTAssertFalse(fixture.showsRetry)
    }

    func testMediaWindowEvictionLeavesPersistentDependencyAvailableOffline() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dependencyRoot = directory.appendingPathComponent("ArtworkDependencies")
        let bytes = try asset()
        let cache = PersistentArtworkDependencyCache(rootURL: dependencyRoot) { _ in (bytes, 200) }
        _ = try await cache.data(for: .hypertype)
        let layout = DownloadableMediaCacheLayout(
            cacheRoot: directory.appendingPathComponent("DownloadableTokenMedia"),
            stagingRoot: directory.appendingPathComponent("staging")
        )
        let mediaDirectory = layout.collectionDirectory(collectionId: PersistentArtworkDependency.hypertype.collectionId)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let mediaFile = mediaDirectory.appendingPathComponent("thumbnail.webp")
        try Data("disposable thumbnail".utf8).write(to: mediaFile)
        let store = DownloadableMediaDiskStore(layout: layout)
        let eviction = await store.evictFilesOutsideWindow(
            collectionId: PersistentArtworkDependency.hypertype.collectionId,
            protectedFileNames: []
        )
        XCTAssertTrue(eviction.didRemoveItem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaFile.path))
        let offline = PersistentArtworkDependencyCache(rootURL: dependencyRoot) { _ in throw URLError(.notConnectedToInternet) }
        let reused = try await offline.data(for: .hypertype)
        XCTAssertEqual(reused, bytes)
    }
}
