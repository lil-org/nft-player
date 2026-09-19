import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class PersistentJavaScriptLibraryTests: XCTestCase {}

private actor LibraryDownloadProbe {
    private(set) var urls: [URL] = []
    private var failNext: Bool
    private var held: Bool
    private var pending: CheckedContinuation<Void, Never>?

    init(failNext: Bool = false, held: Bool = false) {
        self.failNext = failNext
        self.held = held
    }

    func download(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        urls.append(url)
        if held { await withCheckedContinuation { pending = $0 } }
        if failNext {
            failNext = false
            return (Data(), 503)
        }
        guard let dependency = (PersistentJavaScriptLibrary.all + [.hypertype]).first(where: { $0.remoteURL == url }) else {
            throw URLError(.unsupportedURL)
        }
        return (try JavaScriptLibraryFixtures.data(for: dependency), 200)
    }

    func release() {
        held = false
        pending?.resume()
        pending = nil
    }
}

@MainActor
extension PersistentJavaScriptLibraryTests {
    private func scripts() throws -> [Script] {
        try SuggestedItemsService.allItems.filter { $0.script != nil }
            .sorted { $0.bundledResourceName < $1.bundledResourceName }
            .map { try XCTUnwrap(JavaScriptLibraryFixtures.script(collectionId: $0.id), $0.name) }
    }

    private func token(for script: Script) -> BundledTokens.Item {
        SuggestedItemsService.bundledTokens(collectionId: script.id)?.items.first(where: { $0.hash != nil })
            ?? BundledTokens.Item(id: script.abId + "000000", name: nil, hash: "0x" + String(repeating: "1", count: 64))
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if (try? await condition()) == true { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("The library-backed renderer did not reach the expected state")
        throw URLError(.timedOut)
    }

    func testAllLibraryFixturesMatchPinnedPayloadsAndStayOutOfApplicationBundle() throws {
        XCTAssertEqual(PersistentJavaScriptLibrary.all.count, 11)
        var bytes = 0
        for library in PersistentJavaScriptLibrary.all {
            let data = try JavaScriptLibraryFixtures.data(for: library)
            XCTAssertEqual(data.count, library.expectedByteCount)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), library.sha256)
            XCTAssertEqual(library.remoteURL.deletingLastPathComponent().absoluteString, "https://cdn.lil.org/player/lib/")
            XCTAssertNil(Bundle.main.url(forResource: library.remoteURL.deletingPathExtension().lastPathComponent, withExtension: "js"))
            bytes += data.count
        }
        XCTAssertEqual(bytes, 5_307_166)
        for absent in ["p5js140", "p5js160", "three160", "three155", "babylon500", "ort1140", "seedrandom305", "p5svg"] {
            XCTAssertNil(PersistentJavaScriptLibrary.library(named: absent))
        }
    }

    func testEveryActiveScriptResolvesToTheSameHTMLAsInlineLibraryFixtures() async throws {
        let scripts = try scripts()
        XCTAssertEqual(scripts.count, 407)
        let sources = try JavaScriptLibraryFixtures.sources()
        let cache = JavaScriptLibraryFixtures.makeCache(rootURL: try directory())
        var usingLibraries = 0
        var references = 0
        for script in scripts {
            let dependencies = RawHtmlGenerator.requiredDependencies(for: script)
            let libraries = dependencies.filter { $0.id.hasPrefix("library:") }
            if !libraries.isEmpty { usingLibraries += 1 }
            references += libraries.count
            XCTAssertEqual(TokenGenerator.needsArtworkPreparation(collectionId: script.id), !script.kind.isNativeRenderer, script.name)
            let token = token(for: script)
            let deferred = RawHtmlGenerator.createHtml(script: script, token: token)
            XCTAssertEqual(PersistentJavaScriptLibrary.requiredDependencies(in: deferred), dependencies, script.name)
            let actual = try await PersistentJavaScriptLibrary.resolve(deferred, cache: cache)
            let inline = RawHtmlGenerator.createHtml(script: script, token: token, libraryScriptProvider: { sources[$0] })
            let expected = try await PersistentJavaScriptLibrary.resolve(inline, cache: cache)
            XCTAssertEqual(actual, expected, script.name)
            XCTAssertTrue(PersistentJavaScriptLibrary.requiredDependencies(in: actual).isEmpty, script.name)
        }
        XCTAssertEqual(usingLibraries, 274)
        XCTAssertEqual(references, 275)
    }

    func testCollectionsShareOneCachedCopyAndReopenOffline() async throws {
        let scripts = Array(try scripts().filter { $0.kind == .p5js100 }.prefix(2))
        XCTAssertEqual(scripts.count, 2)
        let root = try directory()
        let probe = LibraryDownloadProbe()
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.download($0) })
        for script in scripts {
            let html = RawHtmlGenerator.createHtml(script: script, token: token(for: script))
            _ = try await PersistentJavaScriptLibrary.resolve(html, cache: cache)
        }
        let urls = await probe.urls
        XCTAssertEqual(urls, [try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "p5js100")).remoteURL])
        let offline = PersistentArtworkDependencyCache(rootURL: root) { _ in throw URLError(.notConnectedToInternet) }
        let html = RawHtmlGenerator.createHtml(script: scripts[1], token: token(for: scripts[1]))
        let resolved = try await PersistentJavaScriptLibrary.resolve(html, cache: offline)
        XCTAssertTrue(PersistentJavaScriptLibrary.requiredDependencies(in: resolved).isEmpty)
    }

    func testModuleAndToneOrderingAndUnusedPaperTemplate() async throws {
        let scripts = try scripts()
        let module = try XCTUnwrap(scripts.first { $0.kind == .three167 })
        let html = RawHtmlGenerator.createHtml(script: module, token: token(for: module))
        let tone = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "tone1504"))
        let three = try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "three167"))
        XCTAssertEqual(PersistentJavaScriptLibrary.requiredDependencies(in: html), [tone, three])
        let resolved = try await PersistentJavaScriptLibrary.resolve(html, cache: JavaScriptLibraryFixtures.cache)
        let toneSource = String(decoding: try JavaScriptLibraryFixtures.data(for: tone), as: UTF8.self)
        let toneRange = try XCTUnwrap(resolved.range(of: toneSource))
        let importRange = try XCTUnwrap(resolved.range(of: "<script type=\"importmap\">"))
        XCTAssertLessThan(toneRange.lowerBound, importRange.lowerBound)
        XCTAssertTrue(resolved.contains("data:text/javascript;base64," + (try JavaScriptLibraryFixtures.data(for: three)).base64EncodedString()))
        let paperSource = try XCTUnwrap(scripts.first { $0.kind == .p5js100 })
        let paper = paperSource.replacing(value: "document.body.dataset.paper = String(typeof paper);")
            .modifyingMetadata {
                $0.kind = .paper
                $0.renderingProfile = nil
            }
        let template = RawHtmlGenerator.createHtml(script: paper, token: token(for: paper))
        XCTAssertEqual(PersistentJavaScriptLibrary.requiredDependencies(in: template), [try XCTUnwrap(PersistentJavaScriptLibrary.library(named: "paper"))])
    }

    func testLegacyRendererIgnoresTerminationUntilDependencyContentStarts() async throws {
        let script = try XCTUnwrap(scripts().first { $0.kind == .p5js100 && !$0.usesArtBlocksRenderer })
        let root = try directory()
        let probe = LibraryDownloadProbe(held: true)
        addTeardownBlock { await probe.release() }
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { try await probe.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache, collectionId: script.id)
        defer { fixture.close() }
        fixture.renderer.renderWebContent("<html><body><script>window.previousArtwork = true</script></body></html>")
        fixture.window.layoutIfNeeded()
        try await waitUntil { (try await fixture.webView.evaluateJavaScript("window.previousArtwork")) as? Bool == true }

        let simple = script.replacing(value: "window.libraryFixture = typeof p5;")
        let html = RawHtmlGenerator.createHtml(script: simple, token: token(for: script))
        fixture.renderer.renderWebContent(html)
        try await waitUntil { await probe.urls.count == 1 }
        XCTAssertTrue(fixture.webView.hasPersistentDependencyContent)
        fixture.webView.webViewWebContentProcessDidTerminate(fixture.webView)
        XCTAssertFalse(fixture.showsRetry)

        await probe.release()
        try await waitUntil {
            (try await fixture.webView.evaluateJavaScript("window.libraryFixture")) as? String == "function"
                && !fixture.webView.accessibilityElementsHidden
        }
        XCTAssertFalse(fixture.showsRetry)
        XCTAssertEqual(fixture.probe.documentCount, 1)

        fixture.webView.artworkDependencyCache = PersistentArtworkDependencyCache(rootURL: root) { _ in
            throw URLError(.notConnectedToInternet)
        }
        fixture.webView.webViewWebContentProcessDidTerminate(fixture.webView)
        XCTAssertTrue(fixture.showsRetry)
        try XCTUnwrap(fixture.retryButton).sendActions(for: .touchUpInside)
        try await waitUntil { fixture.probe.documentCount == 2 && !fixture.webView.accessibilityElementsHidden }
        let result = try await fixture.webView.evaluateJavaScript("window.libraryFixture")
        XCTAssertEqual(result as? String, "function")
        XCTAssertFalse(fixture.showsRetry)
        let urls = await probe.urls
        XCTAssertEqual(urls.count, 1)
    }

    func testHiddenLegacyRendererIgnoresTerminationAfterNativeArtworkAndCanResume() async throws {
        let script = try XCTUnwrap(scripts().first { $0.kind == .p5js100 && !$0.usesArtBlocksRenderer })
        let probe = LibraryDownloadProbe()
        let cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache, collectionId: script.id)
        defer { fixture.close() }
        let simple = script.replacing(value: "window.libraryFixture = typeof p5;")
        let html = RawHtmlGenerator.createHtml(script: simple, token: token(for: script))
        fixture.renderer.renderWebContent(html)
        fixture.window.layoutIfNeeded()
        try await waitUntil { (try await fixture.webView.evaluateJavaScript("window.libraryFixture")) as? String == "function" }
        XCTAssertTrue(fixture.webView.hasPersistentDependencyContent)

        fixture.renderer.renderNativeMetalCard(tokenId: "0", renderKind: .cardNft2)
        XCTAssertTrue(fixture.webView.isHidden)
        XCTAssertFalse(fixture.webView.hasPersistentDependencyContent)
        fixture.webView.webViewWebContentProcessDidTerminate(fixture.webView)
        XCTAssertFalse(fixture.showsRetry)

        fixture.renderer.renderWebContent(html)
        try await waitUntil { fixture.probe.documentCount == 2 }
        XCTAssertTrue(fixture.webView.hasPersistentDependencyContent)
        fixture.webView.webViewWebContentProcessDidTerminate(fixture.webView)
        XCTAssertTrue(fixture.showsRetry)
        try XCTUnwrap(fixture.retryButton).sendActions(for: .touchUpInside)
        try await waitUntil { fixture.probe.documentCount == 3 }
        XCTAssertFalse(fixture.showsRetry)
        let urls = await probe.urls
        XCTAssertEqual(urls.count, 1)
    }

    func testNonwebArtworkDismissesPreviousLibraryFailure() async throws {
        let script = try XCTUnwrap(scripts().first { $0.kind == .p5js100 && !$0.usesArtBlocksRenderer })
        let cache = PersistentArtworkDependencyCache(rootURL: try directory()) { _ in (Data(), 503) }
        let fixture = try DependencyRendererFixture(cache: cache, collectionId: script.id)
        defer { fixture.close() }
        let html = RawHtmlGenerator.createHtml(script: script, token: token(for: script))

        fixture.renderer.renderNativeMetalCard(tokenId: "0", renderKind: .cardNft2)
        fixture.renderer.renderWebContent(html)
        try await waitUntil { fixture.showsRetry }
        fixture.renderer.renderNativeMetalCard(tokenId: "1", renderKind: .cardNft2)
        XCTAssertFalse(fixture.showsRetry)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        fixture.renderer.displayLoadedImage(image, key: "existing-image")
        fixture.renderer.renderWebContent(html)
        try await waitUntil { fixture.showsRetry }
        fixture.renderer.renderImage(
            key: "loading-image",
            hideImageUntilLoaded: false,
            load: { _ in nil },
            fallbackToWebContent: { XCTFail("Image loading should remain pending") }
        )
        XCTAssertFalse(fixture.showsRetry)

        fixture.renderer.renderWebContent(html)
        try await waitUntil { fixture.showsRetry }
        fixture.renderer.displayLoadedImage(image, key: "cached-image")
        XCTAssertFalse(fixture.showsRetry)
    }

    func testLegacyLibraryFailureUsesNativeRetryAndKeepsRendererChoice() async throws {
        let script = try XCTUnwrap(scripts().first { $0.kind == .p5js100 && !$0.usesArtBlocksRenderer })
        let probe = LibraryDownloadProbe(failNext: true)
        let cache = PersistentArtworkDependencyCache(rootURL: try directory(), transport: { try await probe.download($0) })
        let fixture = try DependencyRendererFixture(cache: cache, collectionId: script.id)
        defer { fixture.close() }
        XCTAssertTrue(fixture.webView.configuration.suppressesIncrementalRendering)
        let simple = script.replacing(value: "window.libraryFixture = typeof p5;")
        let html = RawHtmlGenerator.createHtml(script: simple, token: token(for: script))
        fixture.renderer.renderWebContent(html)
        fixture.window.layoutIfNeeded()
        try await waitUntil { fixture.showsRetry }
        XCTAssertEqual(fixture.probe.documentCount, 0)
        try XCTUnwrap(fixture.retryButton).sendActions(for: .touchUpInside)
        try await waitUntil { (try await fixture.webView.evaluateJavaScript("window.libraryFixture")) as? String == "function" }
        XCTAssertFalse(fixture.showsRetry)
        XCTAssertEqual(fixture.probe.documentCount, 1)
        let urls = await probe.urls
        XCTAssertEqual(urls.count, 2)
        fixture.renderer.renderWebContent(html)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.probe.documentCount, 1)
    }
}
