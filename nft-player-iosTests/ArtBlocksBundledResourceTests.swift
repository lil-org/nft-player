import CryptoKit
import Foundation
import UIKit
import XCTest
import WebKit
@testable import nft_player_ios

nonisolated final class ArtBlocksBundledResourceTests: XCTestCase {}

@MainActor
private final class HypertypeFixtureAssetHandler: NSObject, WKURLSchemeHandler {
    let data: Data
    var requests: [String] = []

    init(data: Data) { self.data = data }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.absoluteString == "hypertype-fixture://bundled/QmXWXHGkxYFjJF5AuPiVB91VXK31LnoPN9EXKgiWFUvfT6" else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        requests.append(url.absoluteString)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/javascript", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
private final class HypertypeOfflineFixture: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let assetHandler: HypertypeFixtureAssetHandler
    let window: UIWindow
    private weak var previousKeyWindow: UIWindow?
    var documentLoads = 0

    init(asset: Data, rules: WKContentRuleList) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(rules)
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.instrumentation, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        assetHandler = HypertypeFixtureAssetHandler(data: asset)
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: "hypertype-fixture")
        webView = WKWebView(frame: scene.coordinateSpace.bounds, configuration: configuration)
        window = UIWindow(windowScene: scene)
        super.init()
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let host = UIViewController()
        host.view.addSubview(webView)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        webView.frame = host.view.bounds
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { documentLoads += 1 }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    func snapshot() async throws -> [String: Any] {
        let value = try await webView.evaluateJavaScript("""
        (function () {
          const state = window.__hypertypeQA, svg = document.querySelector('svg');
          const descriptor = Object.getOwnPropertyDescriptor(HTMLScriptElement.prototype, 'src');
          const expected = window.__hypertypeOriginalSrc;
          return {
            ready: document.readyState === 'complete' && !!state.firstVisibleMS && svg && svg.childElementCount > 1,
            svg: svg ? svg.outerHTML : '', tokenId: tokenData.tokenId, hash: tokenData.hash,
            errors: state.errors, requests: state.requests, assetLoads: state.assetLoads,
            descriptorRestored: !!expected && descriptor.get === expected.get && descriptor.set === expected.set
              && descriptor.enumerable === expected.enumerable && descriptor.configurable === expected.configurable,
            firstVisibleMS: state.firstVisibleMS,
            networkResources: performance.getEntriesByType('resource').map(entry => entry.name).filter(name => /^https?:/.test(name)),
            startupGate: !!document.querySelector('meta[name="artblocks-review-startup"]')
          };
        }());
        """)
        return try XCTUnwrap(value as? [String: Any])
    }

    func paintedScreenshot() async throws -> UIImage {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let bounds = try await webView.evaluateJavaScript("""
            (function () {
              const rect = document.querySelector('svg').getBoundingClientRect();
              return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
            }());
            """)
            let rect = try XCTUnwrap(bounds as? [String: Double])
            let crop = CGRect(x: try XCTUnwrap(rect["x"]), y: try XCTUnwrap(rect["y"]),
                              width: try XCTUnwrap(rect["width"]), height: try XCTUnwrap(rect["height"]))
                .intersection(webView.bounds)
            guard !crop.isEmpty, !crop.isNull else { throw NSError(domain: "HypertypeInvisibleSVG", code: 1) }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = crop
            configuration.snapshotWidth = 256
            configuration.afterScreenUpdates = true
            let image = try await webView.takeSnapshot(configuration: configuration)
            if try containsArtworkPixels(image) { return image }
            await Task.yield()
        }
        XCTFail("Hypertype SVG exists but WebKit did not capture painted artwork within eight seconds")
        throw NSError(domain: "HypertypeUnpaintedSVG", code: 1)
    }

    private func containsArtworkPixels(_ image: UIImage) throws -> Bool {
        let source = try XCTUnwrap(image.cgImage)
        let width = 64, height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        var dark = 0, light = 0
        for row in 2..<(height - 2) {
            for column in 2..<(width - 2) {
                let offset = (row * width + column) * 4
                let luminance = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
                if pixels[offset + 3] > 240 && luminance < 180 { dark += 1 }
                if pixels[offset + 3] > 240 && luminance > 210 { light += 1 }
            }
        }
        return dark >= 16 && light >= 16
    }

    private static let instrumentation = """
    (function () {
      const state = window.__hypertypeQA = { errors: [], requests: [], assetLoads: 0, firstVisibleMS: null };
      function record(source) {
        if (/^https?:/.test(String(source))) state.requests.push(String(source));
      }
      window.addEventListener('error', event => state.errors.push(String(event.message || event.target.src || 'asset error')), true);
      window.addEventListener('unhandledrejection', event => state.errors.push(String(event.reason)));
      const consoleError = console.error;
      console.error = function () {
        state.errors.push(Array.from(arguments).map(String).join(' '));
        return consoleError.apply(this, arguments);
      };
      const fetch = window.fetch;
      window.fetch = function (input) { record(input && input.url || input); return fetch.apply(this, arguments); };
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, source) { record(source); return open.apply(this, arguments); };
      const append = Node.prototype.appendChild;
      Node.prototype.appendChild = function (node) {
        if (node.nodeType === 1) { record(node.src); record(node.href && (node.href.baseVal || node.href)); }
        return append.apply(this, arguments);
      };
      document.addEventListener('load', event => {
        if (event.target.tagName === 'SCRIPT' && event.target.src) state.assetLoads++;
      }, true);
      function inspect() {
        const svg = document.querySelector('svg');
        if (svg && svg.childElementCount > 1) {
          const rect = svg.getBoundingClientRect();
          let visible = rect.width > 0 && rect.height > 0;
          for (let node = svg; node; node = node.parentElement) {
            const style = getComputedStyle(node);
            visible = visible && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) > 0;
          }
          if (visible) { state.firstVisibleMS = performance.now(); return; }
        }
        requestAnimationFrame(inspect);
      }
      requestAnimationFrame(inspect);
    }());
    """
}

@MainActor
extension ArtBlocksBundledResourceTests {
    func testHypertypePersistentDependencyRequiresExactArtistIdentitySourceAndDependency() throws {
        let (script, tokens) = try hypertypeResources()
        let token = try XCTUnwrap(tokens.items.first)
        let html = RawHtmlGenerator.createHtml(script: script, token: token)
        XCTAssertTrue(html.contains("function nftPlayerHypertypePersistentDependency()"))
        XCTAssertEqual(RawHtmlGenerator.requiredDependency(in: html, collectionId: script.id), .hypertype)
        XCTAssertFalse(html.contains("data:text/javascript;base64,"))
        XCTAssertTrue(html.contains("<script>" + script.value + "</script>"))
        XCTAssertEqual(ArtBlocksRenderingStartupProfiles.startupPolicy(script), .direct)
        let dependency = try XCTUnwrap(script.externalAssetDependencies?.first)
        var variations = [
            script.replacing(address: "0x0000000000000000000000000000000000000001"),
            script.replacing(id: script.id + "-other"),
            script.replacing(name: "Different collection"),
            script.replacing(abId: "1"),
            script.replacing(chain: .base),
            script.replacing(value: script.value + "\n"),
            script.modifyingMetadata { $0.kind = .js },
            script.modifyingMetadata { $0.renderingProfile = nil },
            script.modifyingMetadata { $0.externalAssetDependencies = [dependency, dependency] }
        ]
        for changedDependency in [
            Script.ExternalAssetDependency(index: dependency.index, cid: "QmChangedDependency",
                dependency_type: dependency.dependency_type, data: dependency.data, bytecode_address: dependency.bytecode_address),
            Script.ExternalAssetDependency(index: dependency.index, cid: dependency.cid,
                dependency_type: "ONCHAIN", data: dependency.data, bytecode_address: dependency.bytecode_address),
            Script.ExternalAssetDependency(index: 1, cid: dependency.cid,
                dependency_type: dependency.dependency_type, data: dependency.data, bytecode_address: dependency.bytecode_address),
            Script.ExternalAssetDependency(index: dependency.index, cid: dependency.cid,
                dependency_type: dependency.dependency_type, data: "changed data", bytecode_address: dependency.bytecode_address),
            Script.ExternalAssetDependency(index: dependency.index, cid: dependency.cid,
                dependency_type: dependency.dependency_type, data: dependency.data,
                bytecode_address: "0x0000000000000000000000000000000000000001")
        ] {
            variations.append(script.modifyingMetadata { $0.externalAssetDependencies = [changedDependency] })
        }
        for modified in variations {
            XCTAssertFalse(RawHtmlGenerator.createHtml(script: modified, token: token).contains("function nftPlayerHypertypePersistentDependency()"))
        }
    }

    func testAllHypertypeTokensMatchOriginalSVGWithoutNetworkAccess() async throws {
        let (script, tokens) = try hypertypeResources()
        XCTAssertEqual(tokens.items.count, 150)
        let assetURL = try XCTUnwrap(Bundle(for: ArtBlocksBundledResourceTests.self).url(forResource: "dependency", withExtension: "js", subdirectory: "Hypertype"))
        let asset = try Data(contentsOf: assetURL)
        XCTAssertEqual(asset.count, 712_587)
        XCTAssertEqual(digest(asset), "48d2613055cacdf43217ed43710990150ef2afaa15540c69d2b840d80fd4b6c8")
        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cache = PersistentArtworkDependencyCache(rootURL: cacheRoot) { _ in (asset, 200) }
        _ = try await cache.data(for: .hypertype)
        let offlineCache = PersistentArtworkDependencyCache(rootURL: cacheRoot) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "HypertypeOfflineAllResources",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        )
        var measurements: [[String: Any]] = []
        for token in tokens.items {
            let generated = RawHtmlGenerator.createHtml(script: script, token: token)
            let html = try await RawHtmlGenerator.resolveDependencies(in: generated, collectionId: script.id, cache: offlineCache)
            let adapterRange = try hypertypeAdapterRange(in: html)
            let capture = "<script>window.__hypertypeOriginalSrc = Object.getOwnPropertyDescriptor(HTMLScriptElement.prototype, 'src');</script>"
            var localHTML = html
            localHTML.insert(contentsOf: capture, at: adapterRange.lowerBound)
            var originalHTML = html
            originalHTML.replaceSubrange(adapterRange, with: capture + "<script>tokenData.preferredIPFSGateway = 'hypertype-fixture://bundled/';</script>")
            var svgDigests: [String] = []
            for (kind, document) in [("bundled", localHTML), ("original", originalHTML)] {
                let fixture = try HypertypeOfflineFixture(asset: asset, rules: XCTUnwrap(rules))
                defer { fixture.close() }
                XCTAssertFalse(fixture.webView.configuration.websiteDataStore.isPersistent)
                fixture.webView.loadHTMLString(document, baseURL: nil)
                try await waitUntil {
                    guard let value = try? await fixture.snapshot() else { return false }
                    return value["ready"] as? Bool == true || !(value["errors"] as? [String] ?? []).isEmpty
                }
                let value = try await fixture.snapshot()
                let context = "\(kind) token \(token.id)"
                XCTAssertEqual(value["ready"] as? Bool, true, context)
                XCTAssertEqual(value["tokenId"] as? String, token.id, context)
                XCTAssertEqual(value["hash"] as? String, token.hash, context)
                XCTAssertEqual(value["errors"] as? [String], [], context)
                XCTAssertEqual(value["requests"] as? [String], [], context)
                XCTAssertEqual(value["networkResources"] as? [String], [], context)
                XCTAssertEqual(value["assetLoads"] as? Int, 1, context)
                XCTAssertEqual(value["descriptorRestored"] as? Bool, true, context)
                XCTAssertEqual(value["startupGate"] as? Bool, false, context)
                XCTAssertEqual(fixture.documentLoads, 1, context)
                XCTAssertEqual(fixture.assetHandler.requests.count, kind == "original" ? 1 : 0, context)
                let svg = try XCTUnwrap(value["svg"] as? String)
                XCTAssertTrue(svg.contains("<path"), context)
                svgDigests.append(digest(Data(svg.utf8)))
                measurements.append(["tokenId": token.id, "mode": kind, "firstVisibleMS": value["firstVisibleMS"] ?? NSNull(), "svgSHA256": svgDigests.last!])
                let image = try await fixture.paintedScreenshot()
                if token.id == tokens.items.first?.id || token.id == tokens.items.last?.id {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Hypertype \(token.id) \(kind) offline painted artwork"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            XCTAssertEqual(svgDigests.first, svgDigests.last, "Hypertype \(token.id) changed its rendered SVG")
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "Hypertype offline rendering measurements"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func hypertypeResources() throws -> (Script, BundledTokens) {
        let identifier = "0xbb5471c292065d3b01b2e81e299267221ae9a2500"
        let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: identifier))
        return (
            try XCTUnwrap(JavaScriptLibraryFixtures.script(collectionId: identifier)),
            try BundledTokens(data: Data(contentsOf: tokensURL), collection: XCTUnwrap(SuggestedItemsService.scriptItem(collectionId: identifier)))
        )
    }

    private func hypertypeAdapterRange(in html: String) throws -> Range<String.Index> {
        let marker = try XCTUnwrap(html.range(of: "function nftPlayerHypertypePersistentDependency()"))
        let start = try XCTUnwrap(html.range(of: "<script", options: .backwards, range: html.startIndex..<marker.lowerBound)).lowerBound
        let end = try XCTUnwrap(html.range(of: "</script>", range: marker.upperBound..<html.endIndex)).upperBound
        return start..<end
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for bundled WebKit resources")
        throw CancellationError()
    }
}
