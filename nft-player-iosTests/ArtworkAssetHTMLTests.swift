import Foundation
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtworkAssetHTMLTests: CollectionTokenFixtureTestCase {}

@MainActor
extension ArtworkAssetHTMLTests {
    private func token() -> BundledTokens.Item {
        BundledTokens.Item(id: "0", name: nil, hash: "0x" + String(repeating: "a", count: 64))
    }

    private func webView(setup: String = "") -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if !setup.isEmpty {
            configuration.userContentController.addUserScript(WKUserScript(
                source: setup, injectionTime: .atDocumentStart, forMainFrameOnly: true
            ))
        }
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
    }

    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? await condition()) == true { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Artwork HTML did not reach the expected state")
        throw URLError(.timedOut)
    }

    func testEveryHTMLTemplateStartsItsPolicyBeforeExecutableContent() throws {
        for profile: Script.RenderingProfile? in [nil, .artBlocks] {
            for kind in [Script.Kind.js, .svg, .html, .p5js100, .twemoji, .three167] {
                let script = Script(
                    id: "policy-fixture", address: "0xpolicy", name: "Policy fixture", abId: "0",
                    value: kind == .html ? "<html><head><script>window.artist = true;</script></head></html>" : "window.artist = true;",
                    metadata: .init(kind: kind, renderingProfile: profile)
                )
                let html = RawHtmlGenerator.createHtml(script: script, token: token(), forceLibScript: "window.library = true;")
                let policy = try XCTUnwrap(html.range(of: "http-equiv=\"Content-Security-Policy\""), kind.rawValue)
                let firstScript = try XCTUnwrap(html.range(of: "<script"), kind.rawValue)
                XCTAssertLessThan(policy.lowerBound, firstScript.lowerBound, kind.rawValue)
                XCTAssertFalse(html.contains("https://gateway.pinata.cloud/"))
                XCTAssertFalse(html.contains("https://arweave.net/"))
            }
        }
    }

    func testExternalRequestsAreBlockedInDocumentAndNestedHTMLWhileInlineContentRuns() async throws {
        let exercise = """
        const state = top.__policyProbe;
        const label = window === top ? 'main' : 'child';
        document.addEventListener('securitypolicyviolation', event => {
          state.violations.push(label + ':' + event.effectiveDirective);
        });
        eval("state.inline.push(label)");
        const image = new Image();
        image.src = 'https://external-assets.invalid/image.png';
        document.body.appendChild(image);
        const script = document.createElement('script');
        script.src = 'https://external-assets.invalid/script.js';
        document.body.appendChild(script);
        fetch('https://external-assets.invalid/data.json').catch(() => state.rejections.push(label));
        const localImage = new Image();
        localImage.onload = () => state.images.push(label);
        localImage.src = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><rect width="1" height="1" fill="red"/></svg>');
        document.body.appendChild(localImage);
        """
        let child = "<html><body><script>" + exercise + "</script></body></html>"
        let childJSON = String(decoding: try JSONSerialization.data(withJSONObject: child, options: [.fragmentsAllowed]), as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
        let html = ArtworkAssetPolicy.protectHTML("""
        <html><body><script>
        window.__policyProbe = {violations: [], inline: [], rejections: [], images: []};
        \(exercise)
        const frame = document.createElement('iframe');
        frame.srcdoc = \(childJSON);
        document.body.appendChild(frame);
        </script></body></html>
        """)
        let view = webView()
        defer { view.stopLoading() }
        view.loadHTMLString(html, baseURL: nil)
        try await waitUntil {
            (try await view.evaluateJavaScript("window.__policyProbe?.violations.length === 6 && window.__policyProbe?.images.length === 2 && window.__policyProbe?.rejections.length === 2")) as? Bool == true
        }
        let snapshot = try await view.evaluateJavaScript("window.__policyProbe")
        let state = try XCTUnwrap(snapshot as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(state["inline"] as? [String])), ["main", "child"])
        let violations = Set(try XCTUnwrap(state["violations"] as? [String]))
        for context in ["main", "child"] {
            XCTAssertTrue(violations.contains(context + ":img-src"))
            XCTAssertTrue(violations.contains(context + ":script-src-elem") || violations.contains(context + ":script-src"))
            XCTAssertTrue(violations.contains(context + ":connect-src"))
        }
    }

    func testDopamineUsesNativeEmojiWithSavedPreferenceAndHeadlessBrowser() async throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "dopamine_machines"))
        let script = try JavaScriptLibraryFixtures.script(collectionId: item.id)
        let token = try XCTUnwrap(SuggestedItemsService.cachedTokens(collectionId: item.id)?.items.first)
        XCTAssertEqual(script.kind, .twemoji)
        XCTAssertTrue(RawHtmlGenerator.requiredDependencies(for: script).isEmpty)
        let html = RawHtmlGenerator.createHtml(script: script, token: token, forceLibScript: "throw new Error('Twemoji must not load');")
        XCTAssertTrue(PersistentJavaScriptLibrary.requiredDependencies(in: html).isEmpty)
        for (saved, headless) in [(false, false), (true, false), (true, true)] {
            let view = webView(setup: """
            window.twemoji = {parse: () => { throw new Error('Twemoji must not run'); }};
            Object.defineProperty(window, 'localStorage', { value: {
              getItem: key => key === '__DOPAMINE_EMOJI_TOGGLE__' ? '\(saved)' : null,
              setItem: () => {}
            }});
            """)
            if headless { view.customUserAgent = "Headless artwork test" }
            defer { view.stopLoading() }
            view.loadHTMLString(html, baseURL: nil)
            try await waitUntil {
                (try await view.evaluateJavaScript("document.querySelector('#main')?.childElementCount > 0")) as? Bool == true
            }
            let snapshot = try await view.evaluateJavaScript("""
            ({twemoji: !!window.twemoji, polyfill: USE_EMOJI_POLYFILL,
              headless: IS_HEADLESS, images: document.querySelectorAll('img.emojiPolyfill').length})
            """)
            let state = try XCTUnwrap(snapshot as? [String: Any])
            XCTAssertEqual(state["twemoji"] as? Bool, false)
            XCTAssertEqual(state["polyfill"] as? Bool, false)
            XCTAssertEqual(state["headless"] as? Bool, headless)
            XCTAssertEqual(state["images"] as? Int, 0)
            _ = try await view.evaluateJavaScript("document.dispatchEvent(new KeyboardEvent('keydown', {key: 'e'}));")
            let images = try await view.evaluateJavaScript("document.querySelectorAll('img.emojiPolyfill').length")
            XCTAssertEqual(images as? Int, 0)
        }
    }

    func testHypertypeLoadsPinnedCachedDependencyWithEmptyGatewayDefaults() async throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "hypertype"))
        let script = try JavaScriptLibraryFixtures.script(collectionId: item.id)
        let token = try XCTUnwrap(SuggestedItemsService.cachedTokens(collectionId: item.id)?.items.first)
        let html = try await RawHtmlGenerator.resolveDependencies(
            in: RawHtmlGenerator.createHtml(script: script, token: token),
            collectionId: item.id, cache: JavaScriptLibraryFixtures.cache
        )
        XCTAssertTrue(html.contains("data:text/javascript;base64,"))
        let view = webView()
        defer { view.stopLoading() }
        view.loadHTMLString(html, baseURL: nil)
        try await waitUntil {
            (try await view.evaluateJavaScript("document.querySelector('svg')?.childElementCount > 1")) as? Bool == true
        }
        let gateways = try await view.evaluateJavaScript("[tokenData.preferredIPFSGateway, tokenData.preferredArweaveGateway]")
        XCTAssertEqual(gateways as? [String], ["", ""])
    }
}
