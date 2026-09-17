import CryptoKit
import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksRenderingStartupTests: XCTestCase {}

@MainActor
private final class StartupOperation<Value: Sendable> {
    private var completion: ((Result<Value, Error>) -> Void)?
    var timeoutTask: Task<Void, Never>?

    init(_ completion: @escaping (Result<Value, Error>) -> Void) {
        self.completion = completion
    }

    func finish(_ result: Result<Value, Error>) {
        guard let completion else { return }
        self.completion = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        completion(result)
    }
}

@MainActor
private final class StartupDocumentProbe: NSObject, WKScriptMessageHandler {
    var documents: [[String: Any]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let document = message.body as? [String: Any],
              let generation = document["generation"] as? String,
              !documents.contains(where: { $0["generation"] as? String == generation }) else { return }
        documents.append(document)
    }
}

@MainActor
private final class StartupReadinessProbe: NSObject, WKScriptMessageHandler {
    var firstDrawByGeneration: [String: Date] = [:]

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              let generation = body["generation"] as? String,
              firstDrawByGeneration[generation] == nil else { return }
        firstDrawByGeneration[generation] = Date()
    }
}

@MainActor
private final class StartupFixture {
    let webView = AutoReloadingWebView.newArtBlocksRenderer()
    let probe = StartupDocumentProbe()
    let window: UIWindow
    var errors: [String] = []
    private(set) var loadedHTML = ""

    init(size: CGSize) throws {
        webView.artworkDependencyCache = JavaScriptLibraryFixtures.cache
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        webView.frame = CGRect(origin: .zero, size: size)
        webView.configuration.userContentController.add(probe, name: "startupDocumentProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        const startupCanvasWidth = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'width').get;
        const startupCanvasHeight = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'height').get;
        window.__startupBitmapWidth = canvas => startupCanvasWidth.call(canvas);
        window.__startupBitmapHeight = canvas => startupCanvasHeight.call(canvas);
        document.addEventListener('DOMContentLoaded', function () {
          const identity = window.__startupOriginalToken || (typeof tokenData === 'object' && tokenData ? tokenData : {});
          window.webkit.messageHandlers.startupDocumentProbe.postMessage({
            generation: window.__artBlocksPreviewGeneration,
            tokenId: identity.tokenId || null, hash: identity.hash || identity.hashes?.[0] || null,
            width: innerWidth, height: innerHeight, timestamp: performance.now()
          });
        }, { once: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let host = UIViewController()
        host.view.addSubview(webView)
        window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
    }

    func load(_ script: Script, token: BundledTokens.Item, size: CGSize) {
        webView.configureArtBlocksRendering(collectionId: script.id, tokenId: token.id) { [weak self] in
            self?.errors.append($0)
        }
        webView.frame.size = size
        var html = RawHtmlGenerator.createHtml(script: script, token: token)
        if let start = html.range(of: "<script>let tokenData = "),
           let end = html[start.upperBound...].range(of: "</script>") {
            html.insert(contentsOf: "window.__startupOriginalToken = {tokenId:tokenData.tokenId,hash:tokenData.hash || tokenData.hashes?.[0]};", at: end.lowerBound)
        }
        loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func close() {
        webView.stopLoading()
        webView.clearArtBlocksRendering()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "startupDocumentProbe")
        window.isHidden = true
        window.rootViewController = nil
    }

    func evaluate(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let operation = StartupOperation<String> { continuation.resume(with: $0) }
            webView.evaluateJavaScript(source) { value, error in
                if let error { operation.finish(.failure(error)) }
                else if let value = value as? String { operation.finish(.success(value)) }
                else { operation.finish(.failure(NSError(domain: "StartupMissingEvaluation", code: 1))) }
            }
            operation.timeoutTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                operation.finish(.failure(NSError(domain: "StartupEvaluationTimeout", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Artwork JavaScript did not respond within five seconds"])))
            }
        }
    }

    func screenshot() async throws -> UIImage {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let operation = StartupOperation<Data> { continuation.resume(with: $0) }
            webView.takeSnapshot(with: nil) { image, error in
                if let error { operation.finish(.failure(error)) }
                else if let data = image?.pngData() { operation.finish(.success(data)) }
                else { operation.finish(.failure(NSError(domain: "StartupMissingSnapshot", code: 1))) }
            }
            operation.timeoutTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                operation.finish(.failure(NSError(domain: "StartupSnapshotTimeout", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Artwork snapshot did not respond within five seconds"])))
            }
        }
        return try XCTUnwrap(UIImage(data: data))
    }

    func snapshot() async throws -> [String: Any] {
        let json = try await evaluate("""
        JSON.stringify((() => {
          const identity = window.__startupOriginalToken || (typeof tokenData === 'object' && tokenData ? tokenData : null);
          const loading = document.getElementById('loading-overlay');
          const rect = element => {
            if (!element) return null;
            const r = element.getBoundingClientRect();
            return { x: r.x, y: r.y, width: r.width, height: r.height,
              clientWidth: element.clientWidth, clientHeight: element.clientHeight,
              scrollWidth: element.scrollWidth, scrollHeight: element.scrollHeight };
          };
          const viewport = window.visualViewport;
          return {
            generation: window.__artBlocksPreviewGeneration || null,
            tokenId: identity?.tokenId || null, hash: identity?.hash || identity?.hashes?.[0] || null,
            artistTokenData: typeof tokenData === 'object' ? { tokenId:tokenData.tokenId,hash:tokenData.hash || tokenData.hashes?.[0] }
              : { value: typeof tokenData === 'undefined' ? null : String(tokenData) },
            readyState: document.readyState, timestamp: performance.now(),
            width: innerWidth, height: innerHeight, dpr: devicePixelRatio,
            viewportScale: viewport?.scale || 1,
            visualViewport: viewport ? { width: viewport.width, height: viewport.height, scale: viewport.scale,
              offsetLeft: viewport.offsetLeft, offsetTop: viewport.offsetTop } : null,
            body: rect(document.body), document: rect(document.documentElement),
            coarsePointer: matchMedia('(pointer:coarse)').matches,
            quality: window.__artBlocksPreviewResolution || null,
            loaderVisible: !!loading && getComputedStyle(loading).display !== 'none'
              && getComputedStyle(loading).visibility !== 'hidden',
            canvases: [...document.querySelectorAll('canvas')].map((canvas, index) => {
              const r = canvas.getBoundingClientRect();
              let visible = r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0
                && r.left < innerWidth && r.top < innerHeight;
              let preservesSampling = false;
              for (let node = canvas; node; node = node.parentElement) {
                const s = getComputedStyle(node);
                visible = visible && s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) !== 0;
                const blur = s.filter.match(/blur\\(\\s*([\\d.]+)px\\s*\\)/);
                if (s.imageRendering === 'pixelated' || s.imageRendering === 'crisp-edges'
                    || blur && Number(blur[1]) > 0) preservesSampling = true;
              }
              return { id: canvas.id, index: index, visible: visible, preservesSampling: preservesSampling,
                width: window.__startupBitmapWidth(canvas), height: window.__startupBitmapHeight(canvas),
                x: r.x, y: r.y, rectWidth: r.width, rectHeight: r.height };
            }),
            canYouSeeIt: typeof hasDrawn === 'undefined' ? null : { hasDrawn: hasDrawn,
              canvasWidth: typeof width === 'number' ? width : null, canvasHeight: typeof height === 'number' ? height : null },
            spiroFlakes: typeof T === 'number' && typeof L === 'number' ? { step: T, interval: L } : null,
            vahria: typeof composer === 'undefined' || typeof renderer === 'undefined'
              || typeof displacementShader === 'undefined' || typeof displacementPass === 'undefined' ? null : {
              buffer: [renderer.getDrawingBufferSize(new THREE.Vector2()).x, renderer.getDrawingBufferSize(new THREE.Vector2()).y],
              target: [composer.renderTarget1.width, composer.renderTarget1.height],
              ja: displacementShader.uniforms.ja.value, passJa: displacementPass.uniforms.ja.value
            }
          };
        })())
        """)
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(value as? [String: Any])
    }
}

@MainActor
extension ArtBlocksRenderingStartupTests {
    func testPoolPartyAutomaticPlaybackForEverySavedToken() async throws {
        let id = "0xaa00b2b2db36b8f8004a9aa96f0012005d92b3000"
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: id))
        let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: id))
        let source = try Data(contentsOf: scriptURL), tokenData = try Data(contentsOf: tokensURL)
        let script = try JSONDecoder().decode(Script.self, from: source)
        let tokens = try JSONDecoder().decode(BundledTokens.self, from: tokenData).items
        let profile = try XCTUnwrap(ArtBlocksRenderingStartupProfiles.startupProfile(script))
        let expectsCycle = ArtBlocksRenderingStartupProfiles.afterArtist(script).contains("timeline_mode = true;")
        XCTAssertTrue(expectsCycle)
        XCTAssertEqual(tokens.count, 20)
        let fixture = try StartupFixture(size: CGSize(width: 300, height: 300))
        defer { fixture.close() }
        var evidence: [[String: Any]] = []
        for (index, token) in tokens.enumerated() {
            AutoReloadingWebView.resetStartupCalibrationsForTesting()
            let previousCount = fixture.probe.documents.count
            let started = Date()
            fixture.load(script, token: token, size: CGSize(width: 300, height: 300))
            let deadline = Date().addingTimeInterval(20)
            while !fixture.webView.artworkIsPresented, fixture.errors.isEmpty, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let latency = Date().timeIntervalSince(started)
            XCTAssertTrue(fixture.webView.artworkIsPresented)
            XCTAssertTrue(fixture.errors.isEmpty)
            let first = try await fixture.snapshot()
            assertSnapshot(first, token: token, profile: profile, fixture: fixture, label: "pool party \(index)")
            let probe = """
            JSON.stringify({timeline_mode,show_info,show_pnl,hint:_vuiHintAlpha,active:_vuiActive,
              state:getAnimationState(),count:pairPriceChanges.length,seconds:SECS_PER_MONTH,frames:frameCount,
              parameters:productionData,finite:Object.values(getAnimationState()).every(Number.isFinite)})
            """
            let initialJSON = try await fixture.evaluate(probe)
            let initial = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(initialJSON.utf8)) as? [String: Any])
            XCTAssertEqual(initial["timeline_mode"] as? Bool, expectsCycle)
            XCTAssertEqual(initial["show_info"] as? Bool, false)
            XCTAssertEqual(initial["show_pnl"] as? Bool, false)
            XCTAssertEqual(initial["active"] as? Bool, false)
            XCTAssertEqual(initial["seconds"] as? Int, 10)
            XCTAssertEqual(initial["finite"] as? Bool, true)
            if expectsCycle { XCTAssertEqual(initial["hint"] as? Int, 0) }
            let expected = try JSONEncoder().encode(token.contractParameters)
            XCTAssertEqual(initial["parameters"] as? NSDictionary,
                           try JSONSerialization.jsonObject(with: expected) as? NSDictionary)
            try await Task.sleep(for: .milliseconds(250))
            let laterJSON = try await fixture.evaluate(probe)
            let later = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(laterJSON.utf8)) as? [String: Any])
            XCTAssertGreaterThan(number(later, "frames"), number(initial, "frames"))
            if expectsCycle {
                let state = try XCTUnwrap(initial["state"] as? [String: Any])
                let next = try XCTUnwrap(later["state"] as? [String: Any])
                XCTAssertGreaterThan(number(next, "loopedTime"), number(state, "loopedTime"))
            }
            XCTAssertEqual(fixture.probe.documents.count - previousCount, 1)
            let last = try await fixture.snapshot()
            XCTAssertEqual(first["generation"] as? String, last["generation"] as? String)
            let row: [String: Any] = ["tokenIndex": index, "tokenId": token.id, "seconds": latency,
                "cycle": expectsCycle, "documents": fixture.probe.documents.count - previousCount,
                "initial": initial, "later": later]
            evidence.append(row)
            print("POOL_PARTY_RESULT \(String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))")
            if index == 0 || index == tokens.count - 1 {
                try await attach(fixture, script: script, token: token, profile: profile, phase: "pool-party-\(index)",
                    observations: [first,last], previousDocuments: previousCount, elapsed: latency)
            }
        }
        XCTAssertEqual(try Data(contentsOf: scriptURL), source)
        XCTAssertEqual(try Data(contentsOf: tokensURL), tokenData)
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted,.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "pool party all saved playback"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStartupPresentsTheFirstStableDrawingWithoutATimedGracePeriod() async throws {
        let (fixture, script, tokens, probe) = try syntheticStartupFixture()
        defer { fixture.close() }
        let token = try XCTUnwrap(tokens.first)
        try loadSyntheticStartup(fixture, script: script, token: token, source: syntheticCanvasSource + "draw();")
        let presentedAt = try await waitForSyntheticPresentation(fixture)
        let snapshot = try await fixture.snapshot()
        try assertPromptSyntheticPresentation(fixture, snapshot: snapshot, probe: probe, presentedAt: presentedAt)
        XCTAssertEqual(fixture.probe.documents.count, 1)
        XCTAssertEqual(snapshot["tokenId"] as? String, token.id)
    }

    func testStartupWaitsForDelayedDrawingThenPresentsWithoutAnExtraTimer() async throws {
        let (fixture, script, tokens, probe) = try syntheticStartupFixture()
        defer { fixture.close() }
        let token = try XCTUnwrap(tokens.first)
        try loadSyntheticStartup(fixture, script: script, token: token,
            source: syntheticCanvasSource + "setTimeout(draw, 350);")
        let deadline = Date().addingTimeInterval(5)
        while fixture.probe.documents.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(fixture.probe.documents.count, 1)
        XCTAssertTrue(probe.firstDrawByGeneration.isEmpty)
        XCTAssertFalse(fixture.webView.artworkIsPresented)
        let presentedAt = try await waitForSyntheticPresentation(fixture)
        let snapshot = try await fixture.snapshot()
        try assertPromptSyntheticPresentation(fixture, snapshot: snapshot, probe: probe, presentedAt: presentedAt)
        XCTAssertEqual(fixture.probe.documents.count, 1)
    }

    func testStartupCorrectsAnUndersampledFirstDrawingBeforeItBecomesVisible() async throws {
        let (fixture, script, tokens, _) = try syntheticStartupFixture()
        defer { fixture.close() }
        guard fixture.window.screen.scale > 1 else { throw XCTSkip("Requires a Retina display") }
        let token = try XCTUnwrap(tokens.first)
        let source = syntheticCanvasSource.replacingOccurrences(of: "innerWidth * devicePixelRatio", with: "innerWidth")
            .replacingOccurrences(of: "innerHeight * devicePixelRatio", with: "innerHeight") + "draw();"
        try loadSyntheticStartup(fixture, script: script, token: token, source: source, needsCalibration: true)
        _ = try await waitForSyntheticPresentation(fixture)
        let snapshot = try await fixture.snapshot()
        XCTAssertEqual(fixture.probe.documents.count, 2, "The uncalibrated document became visible before correction")
        XCTAssertEqual(snapshot["tokenId"] as? String, token.id)
        let quality = try XCTUnwrap(snapshot["quality"] as? [String: Any])
        XCTAssertLessThanOrEqual(number(quality, "factor"), 1.02)
        XCTAssertEqual(Double(fixture.webView.pageZoom), 1 / Double(fixture.window.screen.scale), accuracy: 0.001)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fixture.probe.documents.count, 2)
        XCTAssertTrue(fixture.webView.artworkIsPresented)
    }

    func testStartupChecksGeometryAgainAfterTheFirstDrawingFrame() async throws {
        let (fixture, script, tokens, _) = try syntheticStartupFixture()
        defer { fixture.close() }
        let token = try XCTUnwrap(tokens.first)
        try loadSyntheticStartup(fixture, script: script, token: token, source: syntheticCanvasSource + """
        canvas.style.width = '20px'; canvas.style.height = '20px';
        draw();
        requestAnimationFrame(function () {
          canvas.style.width = '100vw'; canvas.style.height = '100vh';
          window.__syntheticLayoutSettled = true;
          draw();
        });
        """)
        _ = try await waitForSyntheticPresentation(fixture)
        let snapshot = try await fixture.snapshot()
        let settled = try await fixture.evaluate("JSON.stringify(window.__syntheticLayoutSettled === true)")
        XCTAssertEqual(settled, "true")
        let canvas = try XCTUnwrap((snapshot["canvases"] as? [[String: Any]])?.first { $0["id"] as? String == "synthetic-art" })
        XCTAssertEqual(number(canvas, "rectWidth"), number(snapshot, "width"), accuracy: 1)
        XCTAssertEqual(number(canvas, "rectHeight"), number(snapshot, "height"), accuracy: 1)
        XCTAssertEqual(fixture.probe.documents.count, 1)
    }

    func testStartupCanPresentIntentionallyPixelatedDrawingWithoutAQualityReport() async throws {
        let (fixture, script, tokens, probe) = try syntheticStartupFixture()
        defer { fixture.close() }
        let token = try XCTUnwrap(tokens.first)
        try loadSyntheticStartup(fixture, script: script, token: token, source: syntheticCanvasSource + """
        canvas.width = canvas.height = 32;
        canvas.style.imageRendering = 'pixelated';
        draw();
        """)
        let presentedAt = try await waitForSyntheticPresentation(fixture)
        let snapshot = try await fixture.snapshot()
        try assertPromptSyntheticPresentation(fixture, snapshot: snapshot, probe: probe, presentedAt: presentedAt)
        XCTAssertEqual(fixture.probe.documents.count, 1)
        XCTAssertTrue(snapshot["quality"] is NSNull)
        let canvas = try XCTUnwrap((snapshot["canvases"] as? [[String: Any]])?.first { $0["id"] as? String == "synthetic-art" })
        XCTAssertEqual(number(canvas, "width"), 32)
        XCTAssertEqual(number(canvas, "height"), 32)
    }

    func testStartupReplacingAPendingTokenOnlyLoadsTheLatestToken() async throws {
        let (fixture, script, tokens, _) = try syntheticStartupFixture()
        defer { fixture.close() }
        XCTAssertGreaterThanOrEqual(tokens.count, 2)
        let first = tokens[0], next = tokens[1]
        try loadSyntheticStartup(fixture, script: script, token: first, source: syntheticCanvasSource + "draw();")
        try loadSyntheticStartup(fixture, script: script, token: next, source: syntheticCanvasSource + "draw();")
        _ = try await waitForSyntheticPresentation(fixture)
        let snapshot = try await fixture.snapshot()
        XCTAssertEqual(fixture.probe.documents.count, 1)
        XCTAssertEqual(fixture.probe.documents.first?["tokenId"] as? String, next.id)
        XCTAssertEqual(snapshot["tokenId"] as? String, next.id)
        XCTAssertEqual(snapshot["hash"] as? String, next.hash)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fixture.probe.documents.count, 1)
        XCTAssertTrue(fixture.webView.artworkIsPresented)
    }

    func testStartupDoesNotRevealHiddenAncestorOrOffscreenDrawing() async throws {
        for mode in ["hidden-ancestor", "offscreen", "fading-ancestor"] {
            let (fixture, script, tokens, probe) = try syntheticStartupFixture()
            defer { fixture.close() }
            let token = try XCTUnwrap(tokens.first)
            let prepare = mode != "offscreen" ? """
            const ancestor = document.body.appendChild(document.createElement('div'));
            ancestor.style.opacity = '0';
            \(mode == "fading-ancestor" ? "ancestor.style.transition = 'opacity 2s linear';" : "")
            ancestor.appendChild(canvas);
            """ : "canvas.style.left = 'calc(100vw + 100px)';"
            let reveal = mode != "offscreen" ? "ancestor.style.opacity = '1';" : "canvas.style.left = '0';"
            try loadSyntheticStartup(fixture, script: script, token: token, source: syntheticCanvasSource + prepare + """
            draw();
            setTimeout(function () {
              \(reveal)
              window.__syntheticNowVisible = true;
              window.__syntheticVisibilityChangedAt = Date.now();
            }, 350);
            """)
            let deadline = Date().addingTimeInterval(5)
            while fixture.probe.documents.isEmpty, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertEqual(fixture.probe.documents.count, 1, mode)
            XCTAssertFalse(probe.firstDrawByGeneration.isEmpty, mode)
            XCTAssertFalse(fixture.webView.artworkIsPresented, "Revealed \(mode) drawing")
            _ = try await waitForSyntheticPresentation(fixture)
            let nowVisible = try await fixture.evaluate("JSON.stringify(window.__syntheticNowVisible === true)")
            XCTAssertEqual(nowVisible, "true", mode)
            XCTAssertEqual(fixture.probe.documents.count, 1, mode)
            XCTAssertTrue(fixture.webView.artworkIsPresented, mode)
            if mode == "fading-ancestor" {
                let delay = try await fixture.evaluate("JSON.stringify(Date.now() - window.__syntheticVisibilityChangedAt)")
                XCTAssertLessThan(try XCTUnwrap(Double(delay)), 250, "Waited for the entire authored fade before revealing")
            }
        }
    }

    private var syntheticCanvasSource: String {
        """
        document.querySelectorAll('canvas').forEach(function (element) { element.remove(); });
        const canvas = document.body.appendChild(document.createElement('canvas'));
        canvas.id = 'synthetic-art';
        canvas.width = Math.round(innerWidth * devicePixelRatio);
        canvas.height = Math.round(innerHeight * devicePixelRatio);
        canvas.style.cssText = 'position:absolute;inset:0;width:100vw;height:100vh';
        const context = canvas.getContext('2d');
        function draw() {
          context.fillStyle = '#357fbd';
          context.fillRect(0, 0, canvas.width, canvas.height);
          window.webkit.messageHandlers.startupReadinessProbe.postMessage({ generation: window.__artBlocksPreviewGeneration });
        }
        """
    }

    private func syntheticStartupFixture() throws -> (StartupFixture, Script, [BundledTokens.Item], StartupReadinessProbe) {
        let id = "0x47a91457a3a1f700097199fd63c039c4784384ab3"
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: id))
        let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: id))
        let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: scriptURL))
        let tokens = try JSONDecoder().decode(BundledTokens.self, from: Data(contentsOf: tokensURL)).items
        AutoReloadingWebView.resetStartupCalibrationsForTesting()
        let fixture = try StartupFixture(size: CGSize(width: 300, height: 300))
        let probe = StartupReadinessProbe()
        fixture.webView.configuration.userContentController.add(probe, name: "startupReadinessProbe")
        return (fixture, script, tokens, probe)
    }

    private func loadSyntheticStartup(
        _ fixture: StartupFixture, script: Script, token: BundledTokens.Item, source: String, needsCalibration: Bool = false
    ) throws {
        let artistTag = "<script>\(script.value)</script>"
        var html = RawHtmlGenerator.createHtml(script: script, token: token)
        XCTAssertTrue(html.contains(artistTag))
        html = html.replacingOccurrences(of: artistTag, with: "<script>\(source)</script>")
        if needsCalibration {
            let prefix = "<meta name=\"artblocks-review-startup\" content=\""
            let start = try XCTUnwrap(html.range(of: prefix))
            let end = try XCTUnwrap(html[start.upperBound...].firstIndex(of: "\""))
            let range = start.upperBound..<end
            let data = try XCTUnwrap(Data(base64Encoded: String(html[range])))
            var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            for key in ["authoredPixelDensity", "coarsePointerPixelDensity", "phonePixelDensity", "iPadPixelDensity"] {
                fields.removeValue(forKey: key)
            }
            fields["revision"] = "synthetic-startup-calibration"
            html.replaceSubrange(range, with: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]).base64EncodedString())
        }
        fixture.webView.configureArtBlocksRendering(collectionId: script.id, tokenId: token.id) { [weak fixture] in
            fixture?.errors.append($0)
        }
        fixture.webView.loadHTMLString(html, baseURL: nil)
    }

    private func waitForSyntheticPresentation(_ fixture: StartupFixture) async throws -> Date {
        let deadline = Date().addingTimeInterval(5)
        while !fixture.webView.artworkIsPresented, fixture.errors.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let presentedAt = Date()
        XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
        XCTAssertTrue(fixture.webView.artworkIsPresented)
        return presentedAt
    }

    private func assertPromptSyntheticPresentation(
        _ fixture: StartupFixture, snapshot: [String: Any], probe: StartupReadinessProbe, presentedAt: Date
    ) throws {
        let generation = try XCTUnwrap(snapshot["generation"] as? String)
        let firstDrawAt = try XCTUnwrap(probe.firstDrawByGeneration[generation])
        XCTAssertLessThan(presentedAt.timeIntervalSince(firstDrawAt), 0.250, "Stable drawing waited for an unnecessary grace period")
        XCTAssertTrue(fixture.errors.isEmpty)
        XCTAssertTrue(fixture.webView.artworkIsPresented)
    }

    func testStartupColdCoverageForEveryCalibratedCollection() async throws {
        let items = try SuggestedItemsService.allItems.filter { item in
            guard TokenGenerator.usesArtBlocksRenderer(collectionId: item.id) else { return false }
            let url = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: item.id))
            let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: url))
            if case .calibrated = ArtBlocksRenderingStartupProfiles.startupPolicy(script) { return true }
            return false
        }
        XCTAssertEqual(items.count, 79)
        var results: [[String: Any]] = []
        for item in items {
            let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: item.id))
            let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: item.id))
            let source = try Data(contentsOf: scriptURL), tokenData = try Data(contentsOf: tokensURL)
            let script = try JSONDecoder().decode(Script.self, from: source)
            let token = try XCTUnwrap(JSONDecoder().decode(BundledTokens.self, from: tokenData).items.first)
            let ratio = try XCTUnwrap(token.artworkAspectRatio)
            let profile = try XCTUnwrap(ArtBlocksRenderingStartupProfiles.startupProfile(script))
            let size = CGSize(width: 300, height: 300 / ratio.value)
            AutoReloadingWebView.resetStartupCalibrationsForTesting()
            let fixture = try StartupFixture(size: size)
            defer { fixture.close() }
            let started = Date()
            fixture.load(script, token: token, size: size)
            let deadline = started.addingTimeInterval(["Cushions", "Gift of Time"].contains(script.name) ? 60 : 20)
            while !fixture.webView.artworkIsPresented,
                  fixture.errors.isEmpty, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertTrue(fixture.errors.isEmpty, "\(script.name): \(fixture.errors.joined(separator: "; "))")
            XCTAssertTrue(fixture.webView.artworkIsPresented, "\(script.name) timed out")
            let first = try await fixture.snapshot()
            assertSnapshot(first, token: token, profile: profile, fixture: fixture, label: "\(script.name) cold coverage")
            let generation = try XCTUnwrap(first["generation"] as? String)
            XCTAssertEqual(fixture.probe.documents.count, 1, "\(script.name) reloaded before presentation")
            try await Task.sleep(for: .milliseconds(100))
            let stable = try await fixture.snapshot()
            XCTAssertEqual(stable["generation"] as? String, generation, "\(script.name) restarted after presentation")
            XCTAssertEqual(fixture.probe.documents.count, 1, "\(script.name) added a document after presentation")
            XCTAssertTrue(fixture.webView.artworkIsPresented, "\(script.name) covered its first stable frame")
            assertSnapshot(stable, token: token, profile: profile, fixture: fixture, label: "\(script.name) settled cold coverage")
            XCTAssertEqual(try Data(contentsOf: scriptURL), source)
            XCTAssertEqual(try Data(contentsOf: tokensURL), tokenData)
            let result: [String: Any] = [
                "name": script.name, "collectionId": script.id, "tokenId": token.id,
                "milliseconds": elapsed * 1000, "documentCount": fixture.probe.documents.count,
                "quality": first["quality"] ?? NSNull(), "pageZoom": Double(fixture.webView.pageZoom),
                "screenScale": Double(fixture.window.screen.scale), "device": UIDevice.current.model,
                "errors": fixture.errors
            ]
            results.append(result)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print("LATENCY_COVERAGE \(try XCTUnwrap(String(data: data, encoding: .utf8)))")
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "Every calibrated collection cold startup latency"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStartupLatencyRepresentativeCollections() async throws {
        let collections = [
            ("Afterimage", "0x47a91457a3a1f700097199fd63c039c4784384ab3"),
            ("Aragnation", "0x99a9b7c1116f9ceeb1652de04d5969cce509b069401"),
            ("100 Sunsets", "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367629"),
            ("Classical Revival", "0x000000098a14b4e08132fd55faec521ab597a0010"),
            ("Can you see it", "0x47a91457a3a1f700097199fd63c039c4784384ab315"),
            ("Cushions", "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270231"),
            ("Gift of Time", "0x000000dc68934ed27fd11e32491cdf6717acaf211"),
            ("Time travel in a subconscious mind", "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270271"),
            ("SpiroFlakes", "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270136"),
            ("Descent", "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367674"),
            ("Bubble Blobby", "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27062"),
            ("Vahria", "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270340")
        ]
        for (name, id) in collections {
            let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: id))
            let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: id))
            let source = try Data(contentsOf: scriptURL), tokenData = try Data(contentsOf: tokensURL)
            let script = try JSONDecoder().decode(Script.self, from: source)
            let token = try XCTUnwrap(JSONDecoder().decode(BundledTokens.self, from: tokenData).items.first)
            let ratio = try XCTUnwrap(token.artworkAspectRatio)
            let profile = try XCTUnwrap(ArtBlocksRenderingStartupProfiles.startupProfile(script))
            let size = CGSize(width: 300, height: 300 / ratio.value)
            for pass in 1...2 {
                AutoReloadingWebView.resetStartupCalibrationsForTesting()
                let fixture = try StartupFixture(size: size)
                defer { fixture.close() }
                for mode in ["cold", "warm"] {
                    let previousDocuments = fixture.probe.documents.count
                    let started = Date()
                    fixture.load(script, token: token, size: size)
                    let deadline = started.addingTimeInterval(["Cushions", "Gift of Time"].contains(name) ? 60 : 20)
                    while !fixture.webView.artworkIsPresented,
                          fixture.errors.isEmpty, Date() < deadline {
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    let elapsed = Date().timeIntervalSince(started)
                    XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
                    XCTAssertTrue(fixture.webView.artworkIsPresented, "\(name) \(mode) timed out")
                    let snapshot = try await fixture.snapshot()
                    assertSnapshot(snapshot, token: token, profile: profile, fixture: fixture,
                        label: "\(name) latency \(pass) \(mode)")
                    let documents = Array(fixture.probe.documents.dropFirst(previousDocuments))
                    XCTAssertEqual(documents.count, 1, "\(name) \(mode) reloaded before presentation")
                    let result: [String: Any] = [
                        "name": name, "collectionId": id, "tokenId": token.id, "pass": pass, "mode": mode,
                        "elapsed": elapsed, "documentCount": documents.count,
                        "domTimestamp": documents.last?["timestamp"] ?? NSNull(),
                        "quality": snapshot["quality"] ?? NSNull(), "pageZoom": Double(fixture.webView.pageZoom),
                        "nativeSize": [Double(size.width), Double(size.height)],
                        "screenScale": Double(fixture.window.screen.scale),
                        "device": UIDevice.current.model, "errors": fixture.errors
                    ]
                    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                    print("LATENCY_RESULT \(try XCTUnwrap(String(data: data, encoding: .utf8)))")
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    attachment.name = "\(name) latency \(pass) \(mode)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            XCTAssertEqual(try Data(contentsOf: scriptURL), source)
            XCTAssertEqual(try Data(contentsOf: tokensURL), tokenData)
        }
    }

    func testStartupWithoutVisibleDrawingReportsAStallAfterDOMCompletes() async throws {
        let id = "0x47a91457a3a1f700097199fd63c039c4784384ab3"
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: id))
        let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: id))
        let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: scriptURL))
        let token = try XCTUnwrap(JSONDecoder().decode(BundledTokens.self, from: Data(contentsOf: tokensURL)).items.first)
        let fixture = try StartupFixture(size: CGSize(width: 300, height: 300))
        defer { fixture.close() }
        fixture.webView.startupTimeoutForTesting = .seconds(1)
        fixture.webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        document.addEventListener('DOMContentLoaded',function(){document.documentElement.style.visibility='hidden';},{once:true});
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        fixture.load(script, token: token, size: CGSize(width: 300, height: 300))
        let deadline = Date().addingTimeInterval(5)
        while fixture.errors.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(fixture.probe.documents.count, 1)
        XCTAssertEqual(fixture.errors.count, 1)
        XCTAssertTrue(fixture.errors.first?.contains("could not finish loading") == true)
        XCTAssertFalse(fixture.webView.artworkIsPresented)
    }

    func testPresentedStartupCancelsItsStallTimeout() async throws {
        let id = "0x47a91457a3a1f700097199fd63c039c4784384ab3"
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: id))
        let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: id))
        let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: scriptURL))
        let token = try XCTUnwrap(JSONDecoder().decode(BundledTokens.self, from: Data(contentsOf: tokensURL)).items.first)
        let fixture = try StartupFixture(size: CGSize(width: 300, height: 300))
        defer { fixture.close() }
        fixture.webView.startupTimeoutForTesting = .seconds(2)
        fixture.load(script, token: token, size: CGSize(width: 300, height: 300))
        _ = try await waitForPresentation(fixture, token: token, after: 0, timeout: 5)
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(fixture.errors.isEmpty)
        XCTAssertTrue(fixture.webView.artworkIsPresented)
    }

    func testStartup100Sunsets() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367629", name: "100 Sunsets") }
    func testStartup720Minutes() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27027", name: "720 Minutes") }
    func testStartupAfterimage() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab3", name: "Afterimage") }
    func testStartupAncientCoursesOfFictionalRivers() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270284", name: "Ancient Courses of Fictional Rivers") }
    func testStartupAndYetWeLove() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab290", name: "And Yet We Love") }
    func testStartupAragnation() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069401", name: "Aragnation") }
    func testStartupAutology() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270209", name: "Autology") }
    func testStartupBalance() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069489", name: "Balance") }
    func testStartupBalletic() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270343", name: "Balletic") }
    func testStartupBeautyInTheHurting() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270178", name: "Beauty in the Hurting") }
    func testStartupBoxLightStudies() async throws { try await verifyCollection("0xab0000000000aa06f89b268d604a9c1c41524ac6499", name: "Box Light Studies") }
    func testStartupBrava() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367680", name: "Brava") }
    func testStartupBubbleBlobby() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27062", name: "Bubble Blobby") }
    func testStartupCanYouSeeIt() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab315", name: "Can you see it") }
    func testStartupChromaGenesis() async throws { try await verifyCollection("0xb3526a6400260078517643cfd8490078803e00000", name: "Chroma Genesis") }
    func testStartupClassicalRevival() async throws { try await verifyCollection("0x000000098a14b4e08132fd55faec521ab597a0010", name: "Classical Revival") }
    func testStartupCushions() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270231", name: "Cushions") }
    func testStartupDejaVu() async throws { try await verifyCollection("0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e87", name: "Deja Vu") }
    func testStartupDelights() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab82", name: "Delights") }
    func testStartupDescent() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367674", name: "Descent") }
    func testStartupDeCoreS() async throws { try await verifyCollection("0x32d4be5ee74376e08038d652d4dc26e62c67f4366", name: "Décorés") }
    func testStartupEccentrics() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270104", name: "Eccentrics") }
    func testStartupEccentrics2Orbits() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270139", name: "Eccentrics 2: Orbits") }
    func testStartupEchoesOfFridaSutura() async throws { try await verifyCollection("0x0000000fae63d15270aafe9e08a71cd28079572d1", name: "Echoes Of Frida: Sutura") }
    func testStartupEncore() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367682", name: "Encore") }
    func testStartupErratic() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270362", name: "Erratic") }
    func testStartupFold() async throws { try await verifyCollection("0xaf40b66072fe00cacf5a25cd1b7f1688cde20f2f1", name: "Fold") }
    func testStartupFormation() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367611", name: "Formation") }
    func testStartupFriendshipBracelets() async throws { try await verifyCollection("0x942bc2d3e7a589fe5bd4a5c6ef9727dfd82f5c8a0", name: "Friendship Bracelets") }
    func testStartupGazers() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270215", name: "Gazers") }
    func testStartupGeophylla() async throws { try await verifyCollection("0x02f518c529a0002e505000795d00c500eb00534a1", name: "Geophylla") }
    func testStartupGiftOfTime() async throws { try await verifyCollection("0x000000dc68934ed27fd11e32491cdf6717acaf211", name: "Gift of Time") }
    func testStartupHeartbeat() async throws { try await verifyCollection("0x8db6f700a7c90000f92ac90084ad93a500f1eae00", name: "Heartbeat") }
    func testStartupHiminn() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270171", name: "Himinn") }
    func testStartupHyperDriveASide() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069392", name: "Hyper Drive: A-Side") }
    func testStartupIfYouCouldDoItAllAgain() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367658", name: "If You Could Do It All Again") }
    func testStartupIntoTheLight() async throws { try await verifyCollection("0x0000f6bc84ab98fbd8fce1f6d047965c723f00000", name: "Into the Light") }
    func testStartupJazz() async throws { try await verifyCollection("0x000000412217f67742376769695498074f007b970", name: "jazz") }
    func testStartupLatentSpirits() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270329", name: "Latent Spirits") }
    func testStartupLibra() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069398", name: "Libra") }
    func testStartupLiquidRuminations() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270278", name: "Liquid Ruminations") }
    func testStartupMeaningless() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069444", name: "Meaningless") }
    func testStartupMelancholicMagicalMaiden() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069493", name: "Melancholic Magical Maiden") }
    func testStartupMeltIntoYou() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab5", name: "Melt Into You") }
    func testStartupMemoriasDelEspacioOlvidado() async throws { try await verifyCollection("0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e82", name: "Memorias del espacio olvidado") }
    func testStartupMiragem() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069389", name: "Miragem") }
    func testStartupMisbah() async throws { try await verifyCollection("0x0000000c687f0226eaf0bdb39104fad56738cdf20", name: "Misbah") }
    func testStartupNebula() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270210", name: "Nebula") }
    func testStartupNetNetNet() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069441", name: "Net Net Net") }
    func testStartupNthCulture() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367618", name: "nth culture") }
    func testStartupOnChainChain() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270283", name: "OnChainChain") }
    func testStartupParade() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270197", name: "Parade") }
    func testStartupPassages() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367638", name: "Passages") }
    func testStartupPax() async throws { try await verifyCollection("0xd40030fd1d00f1a9944462ff0025e9c8d00035000", name: "Pax") }
    func testStartupPigSTail() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab12", name: "Pig's Tail") }
    func testStartupPixelGlass() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27024", name: "Pixel Glass") }
    func testStartupPoolParty() async throws { try await verifyCollection("0xaa00b2b2db36b8f8004a9aa96f0012005d92b3000", name: "pool party") }
    func testStartupAutopoiesis() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab80", name: "Autopoiesis ") }
    func testStartupProscenium() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069486", name: "Proscenium") }
    func testStartupQuarantine() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270183", name: "Quarantine") }
    func testStartupRainBlooms() async throws { try await verifyCollection("0x70270e65bc37832ef845fa330c2b71501970dab90", name: "Rain Blooms") }
    func testStartupReceiveTransmission() async throws { try await verifyCollection("0x294fed5f1d3d30cfa6fe86a937dc3141eec8bc6d4", name: "Receive Transmission") }
    func testStartupSandaliya() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270366", name: "Sandaliya") }
    func testStartupSeasky() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069459", name: "Seasky") }
    func testStartupSigils() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27093", name: "Sigils") }
    func testStartupSpiroFlakes() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270136", name: "SpiroFlakes") }
    func testStartupStellaraum() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce36761", name: "Stellaraum") }
    func testStartupSudfah() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270328", name: "Sudfah") }
    func testStartupTheCollectorSRoom() async throws { try await verifyCollection("0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e814", name: "The Collector's Room") }
    func testStartupTheHarvest() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069407", name: "The Harvest") }
    func testStartupTheNursery() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce36767", name: "The Nursery") }
    func testStartupTheSpringBeginsWithTheFirstRainstorm() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270317", name: "the spring begins with the first rainstorm") }
    func testStartupTimeTravelInASubconsciousMind() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270271", name: "Time travel in a subconscious mind") }
    func testStartupTrademark() async throws { try await verifyCollection("0x8cdbd7010bd197848e95c1fd7f6e870aac9b0d3c4", name: "Trademark") }
    func testStartupTransformationsDuChamp() async throws { try await verifyCollection("0x000000b394cac6057d87df835bea27844b3e28280", name: "Transformations du Champ") }
    func testStartupUMK() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069436", name: "UMK") }
    func testStartupVahria() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270340", name: "Vahria") }
    func testStartupVoid() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27042", name: "Void") }
    func testStartupVoyager() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069434", name: "Voyager") }

    func testStartupCushionsAllReviewedTokensAndAdditionalVariants() async throws {
        let collectionId = "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270231"
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: collectionId))
        let tokenURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: collectionId))
        let originalSource = try Data(contentsOf: scriptURL)
        let originalTokens = try Data(contentsOf: tokenURL)
        let script = try JSONDecoder().decode(Script.self, from: originalSource)
        let allTokens = try JSONDecoder().decode(BundledTokens.self, from: originalTokens).items
        XCTAssertGreaterThan(allTokens.count, 23)
        guard allTokens.count > 23 else { return }
        let reviewedTokenIDs = (0..<23).map { String(231_000_000 + $0) }
        let reviewedTokens = try reviewedTokenIDs.map { id in
            try XCTUnwrap(allTokens.first { $0.id == id }, "Missing reviewed Cushions token \(id)")
        }
        let additionalTokens = [allTokens[allTokens.count / 2], try XCTUnwrap(allTokens.last)]
            .filter { !reviewedTokenIDs.contains($0.id) }
        let tokens = reviewedTokens + additionalTokens
        let profile = try XCTUnwrap(ArtBlocksRenderingStartupProfiles.startupProfile(script))
        XCTAssertEqual(script.name, "Cushions")
        XCTAssertEqual(reviewedTokens.count, 23)
        XCTAssertFalse(additionalTokens.isEmpty)
        AutoReloadingWebView.resetStartupCalibrationsForTesting()
        let fixture = try StartupFixture(size: CGSize(width: 300, height: 300))
        defer { fixture.close() }
        for (index, token) in tokens.enumerated() {
            let previousDocuments = fixture.probe.documents.count
            fixture.load(script, token: token, size: CGSize(width: 300, height: 300))
            try await verifyPresentation(fixture, script: script, token: token, profile: profile,
                phase: "all-saved-\(index)", previousDocuments: previousDocuments)
            XCTAssertEqual(fixture.probe.documents.count - previousDocuments, 1,
                "Cushions token \(index) required more than one document")
            if index == 8 || index == 20 {
                for (phase, size) in [("landscape", CGSize(width: 844, height: 390)), ("square-fit", CGSize(width: 390, height: 390))] {
                    let previousDocuments = fixture.probe.documents.count
                    fixture.webView.frame.size = size
                    fixture.webView.reloadStableArtworkAfterResize()
                    try await verifyPresentation(fixture, script: script, token: token, profile: profile,
                        phase: "all-saved-\(index)-\(phase)", previousDocuments: previousDocuments)
                    XCTAssertEqual(fixture.probe.documents.count - previousDocuments, 1,
                        "Cushions token \(index) \(phase) required more than one document")
                }
            }
        }
        XCTAssertEqual(try Data(contentsOf: scriptURL), originalSource, "Cushions artist resource changed")
        XCTAssertEqual(try Data(contentsOf: tokenURL), originalTokens, "Cushions saved token records changed")
        XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
    }

    func testStartupTinyResizeKeepsPresentedDocument() async throws {
        try await verifyRedundantRequest(.tinyResize)
    }

    func testStartupResizeAwayAndBackKeepsPresentedDocument() async throws {
        try await verifyRedundantRequest(.resizeReturn)
    }

    func testStartupDuplicateHTMLKeepsPresentedDocument() async throws {
        try await verifyRedundantRequest(.duplicateHTML)
    }

    private enum RedundantRequest: String {
        case tinyResize, resizeReturn, duplicateHTML
    }

    private func verifyRedundantRequest(_ request: RedundantRequest) async throws {
        let collectionId = "0x47a91457a3a1f700097199fd63c039c4784384ab3"
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: collectionId))
        let tokenURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: collectionId))
        let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: scriptURL))
        let token = try XCTUnwrap(JSONDecoder().decode(BundledTokens.self, from: Data(contentsOf: tokenURL)).items.first)
        let profile = try XCTUnwrap(ArtBlocksRenderingStartupProfiles.startupProfile(script))
        let size = CGSize(width: 300, height: 300)
        AutoReloadingWebView.resetStartupCalibrationsForTesting()
        let fixture = try StartupFixture(size: size)
        defer { fixture.close() }
        fixture.load(script, token: token, size: size)
        let initial = try await waitForPresentation(fixture, token: token, after: 0, timeout: 20)
        let generation = try XCTUnwrap(initial["generation"] as? String)
        let documentCount = fixture.probe.documents.count
        XCTAssertEqual(documentCount, 1)
        print("STARTUP_PHASE name=Afterimage phase=\(request.rawValue) token=\(token.id)")
        switch request {
        case .tinyResize:
            let delta = 0.25 / fixture.window.screen.scale
            fixture.webView.frame.size = CGSize(width: size.width + delta, height: size.height + delta)
            fixture.webView.reloadStableArtworkAfterResize()
        case .resizeReturn:
            fixture.webView.frame.size = CGSize(width: 340, height: 400)
            XCTAssertFalse(fixture.webView.artworkIsPresented)
            fixture.webView.reloadStableArtworkAfterResize()
            fixture.webView.frame.size = size
            fixture.webView.reloadStableArtworkAfterResize()
        case .duplicateHTML:
            fixture.webView.loadHTMLString(fixture.loadedHTML, baseURL: nil)
        }
        var observations = [initial]
        _ = try await waitForPresentation(fixture, token: token, after: documentCount - 1, timeout: 3)
        for _ in 0..<2 {
            try await Task.sleep(for: .milliseconds(600))
            let snapshot = try await fixture.snapshot()
            observations.append(snapshot)
            XCTAssertEqual(snapshot["generation"] as? String, generation, "\(request.rawValue) restarted the document")
            XCTAssertEqual(fixture.probe.documents.count, documentCount, "\(request.rawValue) navigated again")
            XCTAssertTrue(fixture.webView.artworkIsPresented, "\(request.rawValue) left a cover over the artwork")
            assertSnapshot(snapshot, token: token, profile: profile, fixture: fixture, label: request.rawValue)
        }
        try await attach(fixture, script: script, token: token, profile: profile, phase: request.rawValue,
            observations: observations, previousDocuments: 0, elapsed: 0)
    }

    private func verifyCollection(_ collectionId: String, name: String) async throws {
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: collectionId))
        let tokenURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: collectionId))
        let originalSource = try Data(contentsOf: scriptURL)
        let originalTokens = try Data(contentsOf: tokenURL)
        let script = try JSONDecoder().decode(Script.self, from: originalSource)
        let tokens = try JSONDecoder().decode(BundledTokens.self, from: originalTokens).items
        XCTAssertEqual(script.id, collectionId)
        XCTAssertEqual(script.name, name)
        let profile = try XCTUnwrap(ArtBlocksRenderingStartupProfiles.startupProfile(script))
        XCTAssertGreaterThanOrEqual(tokens.count, 2)
        guard tokens.count >= 2 else { return }
        let first = tokens[0], next = tokens[1]
        let firstRatio = try XCTUnwrap(first.artworkAspectRatio)
        let nextRatio = try XCTUnwrap(next.artworkAspectRatio)
        let firstSize = CGSize(width: 300, height: 300 / firstRatio.value)
        let nextSize = CGSize(width: 300, height: 300 / nextRatio.value)
        AutoReloadingWebView.resetStartupCalibrationsForTesting()
        let fixture = try StartupFixture(size: firstSize)
        defer { fixture.close() }

        for (phase, token, size) in [("first", first, firstSize), ("next", next, nextSize), ("revisit", first, firstSize)] {
            let previousDocuments = fixture.probe.documents.count
            fixture.load(script, token: token, size: size)
            try await verifyPresentation(fixture, script: script, token: token, profile: profile,
                phase: phase, previousDocuments: previousDocuments)
        }
        for (phase, size) in [("landscape", CGSize(width: 844, height: 390)), ("square-fit", CGSize(width: 390, height: 390))] {
            let previousDocuments = fixture.probe.documents.count
            fixture.webView.frame.size = size
            fixture.webView.reloadStableArtworkAfterResize()
            try await verifyPresentation(fixture, script: script, token: first, profile: profile,
                phase: phase, previousDocuments: previousDocuments)
            let generation = try await fixture.snapshot()["generation"] as? String
            fixture.webView.reloadStableArtworkAfterResize()
            try await Task.sleep(for: .milliseconds(300))
            let repeatedSnapshot = try await fixture.snapshot()
            XCTAssertEqual(repeatedSnapshot["generation"] as? String, generation, "Same-size \(phase) request restarted \(name)")
        }
        XCTAssertEqual(try Data(contentsOf: scriptURL), originalSource, "Artist resource changed: \(name)")
        XCTAssertEqual(try Data(contentsOf: tokenURL), originalTokens, "Token records changed: \(name)")
        XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
    }

    private func verifyPresentation(
        _ fixture: StartupFixture,
        script: Script,
        token: BundledTokens.Item,
        profile: ArtBlocksRenderingStartupProfiles.Profile,
        phase: String,
        previousDocuments: Int
    ) async throws {
        var observations: [[String: Any]] = []
        let timeout: TimeInterval = ["Cushions", "Gift of Time"].contains(script.name) || phase == "landscape" ? 60 : 20
        let started = Date()
        print("STARTUP_PHASE name=\(script.name) phase=\(phase) token=\(token.id) size=\(fixture.webView.bounds.size)")
        do {
            let first = try await waitForPresentation(fixture, token: token, after: previousDocuments, timeout: timeout)
            observations.append(first)
            let generation = try XCTUnwrap(first["generation"] as? String)
            XCTAssertTrue(fixture.webView.usesStableArtworkPresentation)
            XCTAssertTrue(fixture.webView.artworkIsPresented)
            XCTAssertEqual(fixture.webView.artworkRenderedSize, fixture.webView.bounds.size)
            for iteration in 0..<2 {
                let milliseconds = script.name == "SpiroFlakes" && phase == "first" ? 1150 : 600
                try await Task.sleep(for: .milliseconds(milliseconds))
                let snapshot = try await fixture.snapshot()
                observations.append(snapshot)
                XCTAssertEqual(snapshot["generation"] as? String, generation,
                    "\(script.name) \(phase) restarted after presentation (sample \(iteration + 1))")
                XCTAssertTrue(fixture.webView.artworkIsPresented,
                    "\(script.name) \(phase) covered the artwork again after presentation")
                assertSnapshot(snapshot, token: token, profile: profile, fixture: fixture, label: "\(script.name) \(phase)")
            }
            let documents = Array(fixture.probe.documents.dropFirst(previousDocuments))
            XCTAssertFalse(documents.isEmpty)
            if expectsSingleDocument(profile, fixture: fixture, snapshot: first) {
                XCTAssertEqual(documents.count, 1, "\(script.name) \(phase) did not start directly at its validated resolution")
            } else {
                XCTAssertLessThanOrEqual(documents.count, 4, "\(script.name) \(phase) repeatedly recalibrated")
            }
            for document in documents {
                XCTAssertEqual(document["tokenId"] as? String, token.id)
                XCTAssertEqual(document["hash"] as? String, token.hash)
            }
            XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
            try await attach(fixture, script: script, token: token, profile: profile, phase: phase,
                observations: observations, previousDocuments: previousDocuments, elapsed: Date().timeIntervalSince(started))
        } catch {
            if let snapshot = try? await fixture.snapshot() { observations.append(snapshot) }
            let diagnostic: [String: Any] = ["name": script.name, "phase": phase, "error": String(describing: error),
                "documents": Array(fixture.probe.documents.dropFirst(previousDocuments)),
                "observations": observations, "presented": fixture.webView.artworkIsPresented,
                "pageZoom": Double(fixture.webView.pageZoom), "errors": fixture.errors]
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) { print("STARTUP_FAILURE \(json)") }
            try? await attach(fixture, script: script, token: token, profile: profile, phase: phase + "-failure",
                observations: observations, previousDocuments: previousDocuments, elapsed: Date().timeIntervalSince(started))
            throw error
        }
    }

    private func assertSnapshot(
        _ snapshot: [String: Any], token: BundledTokens.Item,
        profile: ArtBlocksRenderingStartupProfiles.Profile, fixture: StartupFixture, label: String
    ) {
        let previousFailures = testRun?.failureCount ?? 0
        XCTAssertEqual(snapshot["tokenId"] as? String, token.id, label)
        XCTAssertEqual(snapshot["hash"] as? String, token.hash, label)
        XCTAssertEqual(snapshot["readyState"] as? String, "complete", label)
        let presentationScale = Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale")
        XCTAssertEqual(number(snapshot, "width") * presentationScale, Double(fixture.webView.bounds.width), accuracy: 2, label)
        XCTAssertEqual(number(snapshot, "height") * presentationScale, Double(fixture.webView.bounds.height), accuracy: 2, label)
        let visible = (snapshot["canvases"] as? [[String: Any]] ?? []).filter { $0["visible"] as? Bool == true }
        XCTAssertFalse(visible.isEmpty, "No visible canvas: \(label)")
        if let quality = snapshot["quality"] as? [String: Any], !profile.fixedResolution {
            let factor = number(quality, "factor")
            XCTAssertGreaterThan(factor, 0, label)
            XCTAssertLessThanOrEqual(factor, 1.02, "Insufficient canvas backing: \(label)")
        } else if !profile.fixedResolution {
            XCTAssertTrue(visible.contains { $0["preservesSampling"] as? Bool == true }, "Missing quality measurement: \(label)")
        }
        XCTAssertFalse(snapshot["loaderVisible"] as? Bool ?? true, "Artist loader still visible: \(label)")
        if let vahria = snapshot["vahria"] as? [String: Any] {
            let buffer = vahria["buffer"] as? [Double]
            XCTAssertEqual(vahria["target"] as? [Double], buffer, label)
            XCTAssertEqual(vahria["ja"] as? [Double], buffer, label)
            XCTAssertEqual(vahria["passJa"] as? [Double], buffer, label)
        }
        if (testRun?.failureCount ?? 0) > previousFailures {
            let diagnostic: [String: Any] = ["label": label, "snapshot": snapshot,
                "nativeSize": [Double(fixture.webView.bounds.width), Double(fixture.webView.bounds.height)],
                "pageZoom": Double(fixture.webView.pageZoom), "presented": fixture.webView.artworkIsPresented,
                "documents": fixture.probe.documents, "errors": fixture.errors]
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) { print("STARTUP_ASSERTION_FAILURE \(json)") }
        }
    }

    private func expectsSingleDocument(
        _ profile: ArtBlocksRenderingStartupProfiles.Profile, fixture: StartupFixture, snapshot: [String: Any]
    ) -> Bool {
        if profile.fixedResolution { return true }
        let idiom = fixture.webView.traitCollection.userInterfaceIdiom
        let idiomDensity = idiom == .pad ? profile.iPadPixelDensity : profile.phonePixelDensity
        let coarseDensity = snapshot["coarsePointer"] as? Bool == true ? profile.coarsePointerPixelDensity : nil
        guard let density = idiomDensity ?? coarseDensity ?? profile.authoredPixelDensity else { return false }
        let scale = fixture.window.screen.scale
        let zoom = min(1, max(1 / scale, CGFloat(density) / scale))
        if let maximum = profile.maximumLogicalDimension,
           max(fixture.webView.bounds.width, fixture.webView.bounds.height) / zoom > maximum { return false }
        return true
    }

    private func waitForPresentation(
        _ fixture: StartupFixture, token: BundledTokens.Item, after documentCount: Int, timeout: TimeInterval
    ) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !fixture.errors.isEmpty {
                XCTFail(fixture.errors.joined(separator: "; "))
                throw NSError(domain: "ArtBlocksRenderingStartupTests", code: 2)
            }
            if fixture.webView.artworkIsPresented,
               fixture.probe.documents.count > documentCount,
               let snapshot = try? await fixture.snapshot(),
               snapshot["tokenId"] as? String == token.id,
               snapshot["hash"] as? String == token.hash,
               snapshot["generation"] as? String == fixture.probe.documents.last?["generation"] as? String {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Timed out waiting for stable artwork presentation for token \(token.id)")
        throw NSError(domain: "ArtBlocksRenderingStartupTests", code: 1)
    }

    private func attach(
        _ fixture: StartupFixture, script: Script, token: BundledTokens.Item,
        profile: ArtBlocksRenderingStartupProfiles.Profile, phase: String,
        observations: [[String: Any]], previousDocuments: Int, elapsed: TimeInterval
    ) async throws {
        let profileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
        let information: [String: Any] = [
            "collectionId": script.id, "name": script.name, "tokenId": token.id, "tokenHash": token.hash ?? "",
            "phase": phase, "elapsed": elapsed, "profile": profileObject,
            "artistSourceSHA256": SHA256.hash(data: Data(script.value.utf8)).map { String(format: "%02x", $0) }.joined(),
            "nativeSize": [Double(fixture.webView.bounds.width), Double(fixture.webView.bounds.height)],
            "screenScale": Double(fixture.window.screen.scale), "pageZoom": Double(fixture.webView.pageZoom),
            "presented": fixture.webView.artworkIsPresented, "errors": fixture.errors,
            "documents": Array(fixture.probe.documents.dropFirst(previousDocuments)), "observations": observations
        ]
        let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: information, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        metadata.name = "\(script.name) \(phase) startup"
        metadata.lifetime = .keepAlways
        add(metadata)
        let image = try await fixture.screenshot()
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "\(script.name) \(phase) artwork"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func number(_ object: [String: Any], _ key: String) -> Double {
        (object[key] as? NSNumber)?.doubleValue ?? 0
    }
}
