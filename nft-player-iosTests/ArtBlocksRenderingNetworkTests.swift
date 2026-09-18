import Foundation
import XCTest
import WebKit
@testable import nft_player_ios

nonisolated final class ArtBlocksRenderingNetworkTests: XCTestCase {}

@MainActor
extension ArtBlocksRenderingNetworkTests {
    func testPendingFetchReportsAssetTimeout() async throws {
        try await verify(
            source: "fetch('https://fetch-pending.invalid/');",
            expectedTimeoutHost: "fetch-pending.invalid"
        )
    }

    func testCompletedFetchCancelsAssetTimeout() async throws {
        try await verify(
            source: "fetch('https://fetch-complete.invalid/').then(response => window.__result = String(response.status));",
            expectedResult: "200"
        )
    }

    func testPendingXHRReportsAssetTimeout() async throws {
        try await verify(
            source: "const request = new XMLHttpRequest(); request.open('GET', 'https://xhr-pending.invalid/'); request.send();",
            expectedTimeoutHost: "xhr-pending.invalid"
        )
    }

    func testCompletedXHRCancelsAssetTimeout() async throws {
        try await verify(source: """
        const request = new XMLHttpRequest();
        request.open('GET', 'https://xhr-complete.invalid/');
        request.addEventListener('loadend', () => window.__result = 'complete');
        request.send();
        """, expectedResult: "complete")
    }

    func testStalledResponseBodyReportsAssetTimeoutAfterHeadersArrive() async throws {
        try await verify(
            source: "fetch('https://body-pending.invalid/').then(response => response.text());",
            expectedTimeoutHost: "body-pending.invalid"
        )
    }

    func testCompletedResponseBodyCancelsAssetTimeoutAndRemainsReadable() async throws {
        try await verify(
            source: "fetch('https://body-complete.invalid/').then(response => response.text()).then(text => window.__result = text);",
            expectedResult: "artwork"
        )
    }

    func testStalledClonedResponseBodyReportsAssetTimeout() async throws {
        try await verify(
            source: "fetch('https://body-pending.invalid/').then(response => response.clone().text());",
            expectedTimeoutHost: "body-pending.invalid"
        )
    }

    func testCallerAbortPreservesFetchOptionsAndCancelsAssetTimeout() async throws {
        try await verify(source: """
        const controller = new AbortController();
        const options = { signal: controller.signal, cache: 'no-store' };
        fetch('https://abort.invalid/', options).catch(error => {
            window.__result = error.name + ':' + String(window.__lastFetchOptions === options);
        });
        controller.abort();
        """, expectedResult: "AbortError:true")
    }

    func testPagehideCancelsPendingTimeoutsAndPreventsLateRequestTimeouts() async throws {
        try await verify(source: """
        fetch('https://before-pagehide.invalid/');
        window.dispatchEvent(new Event('pagehide'));
        fetch('https://after-pagehide.invalid/');
        window.__result = 'hidden';
        """, expectedResult: "hidden")
    }

    func testRejectedFetchReportsFailureEvenWhenArtworkHandlesTheRejection() async throws {
        try await verify(
            source: "fetch('https://fetch-rejected.invalid/').catch(error => window.__result = error.message);",
            expectedFailureHost: "fetch-rejected.invalid",
            expectedResult: "Network unavailable"
        )
    }

    func testRejectedResponseBodyReportsFailureAndPreservesTheRejection() async throws {
        try await verify(
            source: "fetch('https://body-rejected.invalid/').then(response => response.text()).catch(error => window.__result = error.message);",
            expectedFailureHost: "body-rejected.invalid",
            expectedResult: "Body unavailable"
        )
    }

    func testHTTPErrorReportsFailureWhilePreservingTheResponse() async throws {
        try await verify(
            source: "fetch('https://http-error.invalid/').then(response => window.__result = String(response.status));",
            expectedFailureHost: "http-error.invalid",
            expectedResult: "404"
        )
    }

    func testArtworkCanInitializeHelpersWithoutReplacingItsSuppliedTokenData() async throws {
        try await verify(source: """
        if (!window.tokenData) {
            window.artworkHelper = () => tokenData.tokenId;
            window.tokenData = { tokenId: 'artist-fallback' };
        }
        window.__result = artworkHelper() + ':' + tokenData.tokenId;
        """, expectedResult: "0:0")
    }

    private func verify(
        source: String,
        expectedTimeoutHost: String? = nil,
        expectedFailureHost: String? = nil,
        expectedResult: String? = nil
    ) async throws {
        let script = Script(
            id: "preview-request-lifecycle", address: "0xpreview", name: "Request lifecycle test", abId: "0",
            value: source + "\nwindow.__scenarioStarted = true;",
            metadata: .init(kind: .js, renderingProfile: .artBlocks, requiresInitialCanvas: false)
        )
        let tokenFixture: [String: Any] = ["items": [["id": "0", "hash": "0x" + String(repeating: "a", count: 64)]]]
        let tokens = try JSONDecoder().decode(BundledTokens.self, from: JSONSerialization.data(withJSONObject: tokenFixture))
        let webView = AutoReloadingWebView.newArtBlocksRenderer()
        webView.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: Self.syntheticRequests, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        var errors: [String] = []
        webView.configureArtBlocksRendering(collectionId: script.id, tokenId: "0") { errors.append($0) }
        defer {
            webView.stopLoading()
            webView.clearArtBlocksRendering()
        }
        webView.loadHTMLString(
            RawHtmlGenerator.createHtml(script: script, token: tokens.items[0], forceLibScript: ""),
            baseURL: nil
        )
        try await waitUntil {
            (try? await webView.evaluateJavaScript("window.__scenarioStarted")) as? Bool == true
        }
        if let expectedResult {
            try await waitUntil {
                (try? await webView.evaluateJavaScript("window.__result")) as? String == expectedResult
            }
        }
        if let expectedTimeoutHost {
            try await waitUntil { !errors.isEmpty }
            XCTAssertEqual(errors.count, 1)
            XCTAssertTrue(try XCTUnwrap(errors.first).contains("Timed out loading artwork asset"))
            XCTAssertTrue(try XCTUnwrap(errors.first).contains(expectedTimeoutHost))
        } else if let expectedFailureHost {
            try await waitUntil { !errors.isEmpty }
            XCTAssertEqual(errors.count, 1)
            XCTAssertTrue(try XCTUnwrap(errors.first).contains("Could not load artwork asset"))
            XCTAssertTrue(try XCTUnwrap(errors.first).contains(expectedFailureHost))
        } else {
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertTrue(errors.isEmpty, errors.joined(separator: "; "))
        }
    }

    private func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for preview request state")
        throw CancellationError()
    }

    private static let syntheticRequests = """
    const scheduleTimeout = window.setTimeout;
    window.setTimeout = function (callback, delay, ...args) {
        return scheduleTimeout.call(this, callback, delay === 60000 ? 150 : delay, ...args);
    };
    function stalledBodyResponse() {
        const response = new Response('artwork');
        response.text = function () { return new Promise(() => {}); };
        response.clone = stalledBodyResponse;
        return response;
    }
    window.fetch = function (input, options) {
        window.__lastFetchOptions = options;
        const source = String(input);
        if (source.includes('body-pending')) return Promise.resolve(stalledBodyResponse());
        if (source.includes('body-rejected')) {
            const response = new Response('artwork');
            response.text = () => Promise.reject(new TypeError('Body unavailable'));
            return Promise.resolve(response);
        }
        if (source.includes('fetch-rejected')) return Promise.reject(new TypeError('Network unavailable'));
        if (source.includes('http-error')) return Promise.resolve(new Response('Not found', { status: 404 }));
        if (source.includes('abort')) {
            return new Promise((resolve, reject) => {
                options.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
            });
        }
        return source.includes('complete') ? Promise.resolve(new Response('artwork')) : new Promise(() => {});
    };
    XMLHttpRequest.prototype.open = function (method, source) { this.__source = source; };
    XMLHttpRequest.prototype.send = function () {
        if (String(this.__source).includes('complete')) this.dispatchEvent(new Event('loadend'));
    };
    """
}
