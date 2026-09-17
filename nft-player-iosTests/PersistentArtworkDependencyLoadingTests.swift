import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class PersistentArtworkDependencyLoadingTests: XCTestCase {}

private actor DependencyLoadingTransport {
    private(set) var requests = 0
    private var pending: CheckedContinuation<(data: Data, statusCode: Int), Error>?

    func download(_ url: URL) async throws -> (data: Data, statusCode: Int) {
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
private final class DependencyLoadingProbe: NSObject, WKScriptMessageHandler {
    var documentCount = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        documentCount += 1
    }
}

@MainActor
private final class DependencyRendererFixture {
    let window: UIWindow
    let container: UIView
    let renderer: FullscreenTokenMediaRenderer
    let webView: AutoReloadingWebView
    let probe = DependencyLoadingProbe()
    private weak var previousKeyWindow: UIWindow?

    init(cache: PersistentArtworkDependencyCache) throws {
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
        renderer = FullscreenTokenMediaRenderer(containerView: container)
        renderer.configureArtBlocksRendering(collectionId: PersistentArtworkDependency.hypertype.collectionId, tokenId: "0")
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
        let id = PersistentArtworkDependency.hypertype.collectionId
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
        let bytes = try asset()
        let online = PersistentArtworkDependencyCache(rootURL: directory) { _ in (bytes, 200) }
        _ = try await online.data(for: .hypertype)
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
        let bytes = try asset()
        let cache = PersistentArtworkDependencyCache(rootURL: directory) { _ in (bytes, 200) }
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
