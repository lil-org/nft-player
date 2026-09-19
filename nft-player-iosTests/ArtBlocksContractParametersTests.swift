import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksContractParametersTests: XCTestCase {}

@MainActor
private final class ContractParametersFixture: NSObject, WKScriptMessageHandler {
    private final class SnapshotResult {
        var continuation: CheckedContinuation<String?, Error>?

        init(_ continuation: CheckedContinuation<String?, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<String?, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    let webView: AutoReloadingWebView
    let window: UIWindow
    private weak var previousKeyWindow: UIWindow?
    var errors: [String] = []
    var requests: [String] = []
    var diagnostics: [String] = []

    init(ratio: CGFloat, rules: WKContentRuleList) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        webView = AutoReloadingWebView.newArtBlocksRenderer()
        webView.artworkDependencyCache = JavaScriptLibraryFixtures.cache
        webView.frame = CGRect(x: 0, y: 0, width: min(390, 844 * ratio), height: min(844, 390 / ratio))
        window = UIWindow(windowScene: scene)
        super.init()
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        webView.configuration.userContentController.add(rules)
        webView.configuration.userContentController.add(self, name: "contractQARequest")
        webView.configuration.userContentController.add(self, name: "contractQAError")
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: Self.instrumentation, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let host = UIViewController()
        host.view.addSubview(webView)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    func load(script: Script, token: BundledTokens.Item) throws {
        webView.configureArtBlocksRendering(collectionId: script.id, tokenId: token.id) { [weak self] in self?.errors.append($0) }
        var html = RawHtmlGenerator.createHtml(script: script, token: token)
        let start = try XCTUnwrap(html.range(of: "<script>let tokenData = ")).upperBound
        let end = try XCTUnwrap(html.range(of: ";</script>", range: start..<html.endIndex)).upperBound
        html.insert(contentsOf: "<script>window.__contractQASuppliedToken = {tokenId: tokenData.tokenId, hash: tokenData.hash};</script>", at: end)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func close() {
        webView.stopLoading()
        webView.clearArtBlocksRendering()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "contractQARequest")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "contractQAError")
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let source = message.body as? String else { return }
        if message.name == "contractQARequest" { requests.append(source) }
        else { diagnostics.append(source) }
    }

    func snapshot(includeGraphicsErrors: Bool = false) async throws -> [String: Any]? {
        let result: String? = try await withCheckedThrowingContinuation { continuation in
            let pending = SnapshotResult(continuation)
            webView.evaluateJavaScript("window.__contractQASnapshot ? JSON.stringify(window.__contractQASnapshot(\(includeGraphicsErrors ? "true" : "false"))) : null") { value, error in
                pending.finish(error.map { .failure($0) } ?? .success(value as? String))
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                pending.finish(.failure(NSError(domain: "ContractParametersProbeTimeout", code: 1)))
            }
        }
        guard let result else { return nil }
        return try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
    }

    private static let instrumentation = """
    (function () {
      window.addEventListener('error', function (event) {
        window.webkit.messageHandlers.contractQAError.postMessage(JSON.stringify({message: event.message,
          stack: event.error && event.error.stack, source: event.filename, line: event.lineno,
          asset: event.target && (event.target.src || event.target.href)}));
      }, true);
      const consoleError = console.error;
      console.error = function () {
        window.webkit.messageHandlers.contractQAError.postMessage(Array.from(arguments).map(String).join(' ').slice(0, 2000));
        return consoleError.apply(this, arguments);
      };
      const records = new WeakMap();
      const canvasWidth = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'width').get;
      const canvasHeight = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'height').get;
      const getContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (kind) {
        const context = getContext.apply(this, arguments);
        if (context && !records.has(this)) records.set(this, {kind: kind, draws: 0, context: context});
        return context;
      };
      function track(prototype, names) {
        if (!prototype) return;
        for (const name of names) {
          const original = prototype[name];
          if (typeof original !== 'function') continue;
          prototype[name] = function () {
            const record = records.get(this.canvas);
            if (record) record.draws++;
            return original.apply(this, arguments);
          };
        }
      }
      track(CanvasRenderingContext2D.prototype, ['fill', 'stroke', 'fillRect', 'strokeRect', 'drawImage']);
      track(window.WebGLRenderingContext?.prototype, ['drawArrays', 'drawElements']);
      track(window.WebGL2RenderingContext?.prototype, ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced']);
      let noLoopCalls = 0;
      document.addEventListener('DOMContentLoaded', function () {
        if (!window.p5) return;
        const noLoop = p5.prototype.noLoop;
        p5.prototype.noLoop = function () {
          const canvas = this.canvas || this._renderer?.canvas;
          if (canvas?.isConnected && records.get(canvas)?.draws > 0) noLoopCalls++;
          return noLoop.apply(this, arguments);
        };
      }, {once: true});
      function disallows(source) {
        try {
          const url = new URL(String(source), document.baseURI);
          if (!/^https?:$/.test(url.protocol)) return false;
          window.webkit.messageHandlers.contractQARequest.postMessage(url.href);
          return true;
        } catch (_) { return false; }
      }
      const fetch = window.fetch;
      window.fetch = function (input, options) {
        if (disallows(input && input.url || input)) return Promise.reject(new Error('Offline fixture blocked a network request'));
        return fetch.call(this, input, options);
      };
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, source) {
        if (disallows(source)) throw new Error('Offline fixture blocked a network request');
        return open.apply(this, arguments);
      };
      window.__contractQASnapshot = function (includeGraphicsErrors) {
        const canvases = [];
        const pendingCanvases = [];
        document.querySelectorAll('canvas').forEach(function (canvas) {
          const record = records.get(canvas), rect = canvas.getBoundingClientRect();
          const context = record?.context;
          const graphics = context && typeof context.getParameter === 'function' ? {
            maxTextureSize: context.getParameter(context.MAX_TEXTURE_SIZE),
            maxRenderbufferSize: context.getParameter(context.MAX_RENDERBUFFER_SIZE),
            isContextLost: context.isContextLost(),
            error: includeGraphicsErrors ? context.getError() : null
          } : null;
          pendingCanvases.push({kind: record?.kind, draws: record?.draws || 0, width: canvasWidth.call(canvas), height: canvasHeight.call(canvas),
            x: rect.x, y: rect.y, cssWidth: rect.width, cssHeight: rect.height, graphics: graphics});
          if (!record || record.draws < 1 || rect.width <= 0 || rect.height <= 0) return;
          let ancestor = canvas;
          while (ancestor) {
            const style = getComputedStyle(ancestor);
            if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) return;
            ancestor = ancestor.parentElement;
          }
          if (rect.right <= 0 || rect.bottom <= 0 || rect.left >= innerWidth || rect.top >= innerHeight) return;
          canvases.push({kind: record.kind, draws: record.draws, width: canvasWidth.call(canvas), height: canvasHeight.call(canvas),
            x: rect.x, y: rect.y, cssWidth: rect.width, cssHeight: rect.height});
        });
        return {generation: window.__artBlocksPreviewGeneration || '', ready: document.readyState === 'complete',
          inputTokenId: window.__contractQASuppliedToken?.tokenId, inputHash: window.__contractQASuppliedToken?.hash,
          tokenId: typeof tokenData === 'object' ? tokenData.tokenId : null,
          hash: typeof tokenData === 'object' ? tokenData.hash : null,
          parameters: typeof tokenData === 'object' ? tokenData.externalAssetDependencies?.[0]?.data : null,
          canvases: canvases, pendingCanvases: pendingCanvases, noLoopCalls: noLoopCalls,
          visibilityState: document.visibilityState, hasFocus: document.hasFocus(),
          giftReady: typeof Ye !== 'undefined' && Ye === 1 && typeof pd === 'number'
            && pd === Number(tokenData.externalAssetDependencies?.[0]?.data?.blockTimestamp) && yd === 'blockTime'
            && (!document.getElementById('loading-overlay') || getComputedStyle(document.getElementById('loading-overlay')).display === 'none'),
          quality: window.__artBlocksPreviewResolution || null};
      };
    }());
    """
}

@MainActor
extension ArtBlocksContractParametersTests {
    private var collectionNames: Set<String> {
        ["degenerative", "Gift of Time", "pool party"]
    }

    func testFrozenParametersRoundTripWithoutLosingTokenOrAspectRatioMetadata() throws {
        let parameters = ["message": "Frozen \"雪\"\nline", "empty": "", "number": "0"]
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 2, "count": 1, "firstId": "7", "hash": ["0xabc"],
            "contractParameters": [parameters], "aspectRatio": [[3, 4]]
        ])
        let tokens = try JSONDecoder().decode(BundledTokens.self, from: data)
        let first = try XCTUnwrap(tokens.items.first)
        XCTAssertEqual(first.id, "7")
        XCTAssertEqual(first.hash, "0xabc")
        XCTAssertEqual(first.contractParameters, parameters)
        XCTAssertEqual(first.aspectRatio, AspectRatio(width: 3, height: 4))
        let restored = try JSONDecoder().decode(BundledTokens.self, from: JSONEncoder().encode(tokens))
        XCTAssertEqual(restored.items.first?.contractParameters, parameters)
        XCTAssertEqual(restored.items.first?.aspectRatio, first.aspectRatio)
        let invalid = Data(#"{"id":"7","contractParameters":{"number":42}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(BundledTokens.Item.self, from: invalid))
    }

    func testParameterObjectReplacesOnlyTheMatchingArtBlocksOnchainDependency() throws {
        let parameters = ["parameter": "frozen"]
        let token = BundledTokens.Item(id: "1", name: nil, hash: "0xabc", contractParameters: parameters)
        let matched = try syntheticScript(dependency: dependency())
        let matchedData = try tokenData(in: RawHtmlGenerator.createHtml(script: matched, token: token, forceLibScript: ""))
        let assets = try XCTUnwrap(matchedData["externalAssetDependencies"] as? [[String: Any]])
        XCTAssertEqual(assets.first?["data"] as? [String: String], parameters)
        XCTAssertEqual(assets.first?["dependency_type"] as? String, "ONCHAIN")
        XCTAssertEqual(assets.first?["index"] as? Int, 0)

        for asset in [dependency(index: 1), dependency(type: "IPFS"), dependency(address: "0xother")] {
            let script = try syntheticScript(dependency: asset)
            let data = try tokenData(in: RawHtmlGenerator.createHtml(script: script, token: token, forceLibScript: ""))
            let assets = try XCTUnwrap(data["externalAssetDependencies"] as? [[String: Any]])
            XCTAssertEqual(assets.first?["data"] as? String, "original dependency data")
        }
    }

    func testEscapedParameterStringsRemainObjectsAndDoNotAffectOtherRenderers() throws {
        let parameter = "</script><script>window.bad = true</script>\n雪 \\ \"quoted\""
        let parameters = ["text": parameter]
        let token = BundledTokens.Item(id: "1", name: nil, hash: "0xabc", contractParameters: parameters)
        let script = try syntheticScript(dependency: dependency())
        let html = RawHtmlGenerator.createHtml(script: script, token: token, forceLibScript: "")
        XCTAssertFalse(html.contains("<script>window.bad = true</script>"))
        let data = try tokenData(in: html)
        let assets = try XCTUnwrap(data["externalAssetDependencies"] as? [[String: Any]])
        XCTAssertEqual(assets.first?["data"] as? [String: String], parameters)
        let production = try syntheticScript(dependency: dependency(), artBlocksRendering: false)
        let originalToken = BundledTokens.Item(id: token.id, name: nil, hash: token.hash)
        XCTAssertEqual(
            RawHtmlGenerator.createHtml(script: production, token: token, forceLibScript: ""),
            RawHtmlGenerator.createHtml(script: production, token: originalToken, forceLibScript: "")
        )
    }

    func testAllMintedContractTokensContainFrozenParametersAndPreserveIdentity() throws {
        let selected = SuggestedItemsService.allItems
        let affected = selected.filter { collectionNames.contains($0.name) }
        XCTAssertEqual(affected.count, 3)
        XCTAssertEqual(selected.count, 529)
        for item in affected {
            XCTAssertTrue(TokenGenerator.usesArtBlocksRenderer(collectionId: item.id))
            let script = try bundledScript(item)
            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
            if item.name == "pool party" {
                XCTAssertEqual(tokens.items.count, 20)
            } else {
                XCTAssertGreaterThan(tokens.items.count, 23)
            }
            for token in tokens.items {
                let parameters = try XCTUnwrap(token.contractParameters, "\(item.name) \(token.id)")
                let data = try tokenData(in: RawHtmlGenerator.createHtml(script: script, token: token, forceLibScript: ""))
                let assets = try XCTUnwrap(data["externalAssetDependencies"] as? [[String: Any]])
                XCTAssertEqual(assets.first?["data"] as? [String: String], parameters)
                XCTAssertEqual(data["tokenId"] as? String, token.id)
                XCTAssertEqual(data["hash"] as? String, token.hash)
                if item.name == "degenerative" {
                    for key in ["p0", "p1", "p2", "week", "chaos"] { XCTAssertNotNil(parameters[key], key) }
                    XCTAssertFalse(try XCTUnwrap(parameters["p0"]).isEmpty)
                } else if item.name == "Gift of Time" {
                    XCTAssertGreaterThan(Int(try XCTUnwrap(parameters["blockTimestamp"])) ?? 0, 0)
                }
            }
        }
    }

    func testDegenerativeRendersFirstAndLastFrozenTokensOffline() async throws { try await verifyOfflineCollection("degenerative") }
    func testGiftOfTimeRendersFirstAndLastFrozenTokensOffline() async throws { try await verifyOfflineCollection("Gift of Time") }
    func testPoolPartyRendersFirstAndLastFrozenTokensOffline() async throws { try await verifyOfflineCollection("pool party") }

    private func verifyOfflineCollection(_ name: String) async throws {
        let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.name == name })
        XCTAssertTrue(TokenGenerator.usesArtBlocksRenderer(collectionId: item.id))
        let script = try bundledScript(item)
        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "ArtBlocksContractParametersOffline",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        )
        for index in [0, tokens.items.count - 1] {
            let token = tokens.items[index].resolvingAspectRatio(default: item.aspectRatio)
            let fixture = try ContractParametersFixture(ratio: token.aspectRatio?.value ?? 1, rules: try XCTUnwrap(rules))
            defer { fixture.close() }
            try fixture.load(script: script, token: token)
            let snapshot = try await waitForArtwork(in: fixture, collectionName: name, timeout: name == "Gift of Time" ? 60 : 30)
            XCTAssertEqual(snapshot["inputTokenId"] as? String, token.id)
            XCTAssertEqual(snapshot["inputHash"] as? String, token.hash)
            XCTAssertEqual(snapshot["tokenId"] as? String, token.id)
            XCTAssertEqual(snapshot["hash"] as? String, token.hash)
            XCTAssertEqual(snapshot["parameters"] as? [String: String], try XCTUnwrap(token.contractParameters))
            XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
            XCTAssertTrue(fixture.requests.isEmpty, fixture.requests.joined(separator: "; "))
            let image = try await fixture.webView.takeSnapshot(configuration: nil)
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name) \(token.id) offline artwork"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func waitForArtwork(in fixture: ContractParametersFixture, collectionName: String, timeout: TimeInterval?) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout ?? 30)
        var generation = ""
        var consecutiveFrames = 0
        var lastSnapshot: [String: Any]?
        while Date() < deadline {
            if let error = fixture.errors.first {
                XCTFail(([error] + fixture.diagnostics).joined(separator: "\n"))
                throw NSError(domain: "ArtBlocksContractParametersTests", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            if let snapshot = try? await fixture.snapshot() {
                lastSnapshot = snapshot
                if snapshot["ready"] as? Bool == true,
               let currentGeneration = snapshot["generation"] as? String,
               let canvases = snapshot["canvases"] as? [[String: Any]], !canvases.isEmpty {
                    let completed: Bool
                    if collectionName == "Gift of Time" {
                        completed = snapshot["giftReady"] as? Bool == true
                    } else {
                        completed = true
                    }
                    guard completed else {
                        try await Task.sleep(for: .milliseconds(250))
                        continue
                    }
                    consecutiveFrames = currentGeneration == generation ? consecutiveFrames + 1 : 0
                    generation = currentGeneration
                    if consecutiveFrames >= 4 { return snapshot }
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        if let snapshot = try? await fixture.snapshot(includeGraphicsErrors: true) { lastSnapshot = snapshot }
        lastSnapshot?.removeValue(forKey: "parameters")
        let state = lastSnapshot.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            .map { String(decoding: $0, as: UTF8.self) } ?? "No JavaScript snapshot completed"
        XCTFail((["Timed out waiting for offline artwork", state] + fixture.diagnostics).joined(separator: "\n"))
        throw NSError(domain: "ArtBlocksContractParametersTests", code: 2)
    }

    private func bundledScript(_ item: SuggestedItem) throws -> Script {
        return try XCTUnwrap(JavaScriptLibraryFixtures.script(collectionId: item.id))
    }

    private func dependency(index: Int = 0, type: String = "ONCHAIN", address: String = "0x00000000a78e278b2d2e2935faebe19ee9f1ff14") -> Script.ExternalAssetDependency {
        .init(index: index, cid: "", dependency_type: type, data: "original dependency data", bytecode_address: address)
    }

    private func syntheticScript(dependency: Script.ExternalAssetDependency, artBlocksRendering: Bool = true) throws -> Script {
        Script(
            id: "0xparameters0", address: "0xparameters", name: "Parameters fixture", abId: "0", value: "",
            metadata: .init(kind: .js, renderingProfile: artBlocksRendering ? .artBlocks : nil,
                            externalAssetDependencies: [dependency])
        )
    }

    private func tokenData(in html: String) throws -> [String: Any] {
        let start = try XCTUnwrap(html.range(of: "<script>let tokenData = ")).upperBound
        let end = try XCTUnwrap(html.range(of: ";</script>", range: start..<html.endIndex)).lowerBound
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(html[start..<end].utf8)) as? [String: Any])
    }
}
