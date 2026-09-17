import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksExternalDisplayTests: XCTestCase {}

@MainActor
private final class ExternalDisplayDocumentProbe: NSObject, WKScriptMessageHandler {
    var documents: [[String: Any]] = []
    var errors: [String] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        if let error = body["error"] as? String {
            errors.append(error)
        } else if let generation = body["generation"] as? String,
                  !documents.contains(where: { $0["generation"] as? String == generation }) {
            documents.append(body)
        }
    }
}

@MainActor
private final class ExternalDisplayEvaluation {
    private var completion: ((Result<String, Error>) -> Void)?
    var timeout: Task<Void, Never>?

    init(_ completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
    }

    func finish(_ result: Result<String, Error>) {
        guard let completion else { return }
        self.completion = nil
        timeout?.cancel()
        timeout = nil
        completion(result)
    }
}

@MainActor
private final class ExternalDisplayIntegrationFixture {
    let controller = ExternalDisplayViewController()
    let probe = ExternalDisplayDocumentProbe()
    let window: UIWindow
    let webView: AutoReloadingWebView
    private let previousKeyWindow: UIWindow?

    init(token: GeneratedToken, size: CGSize) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view.backgroundColor = .black
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.view.frame = .zero
        updateExternalDisplayToken(token)
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        webView = try XCTUnwrap(Self.webViews(in: controller.view).first)
        XCTAssertEqual(webView.bounds.size, .zero)
        webView.configuration.userContentController.add(probe, name: "externalDisplayProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        window.__externalDisplayHasDrawn = false;
        const externalGetContext = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function () {
          const context = externalGetContext.apply(this, arguments);
          if (context && !context.__externalDisplayInstrumented) {
            context.__externalDisplayInstrumented = true;
            ['fill', 'stroke', 'fillRect', 'drawImage', 'putImageData', 'fillText'].forEach(name => {
              const original = context[name];
              if (typeof original !== 'function') return;
              context[name] = function () {
                const result = original.apply(this, arguments);
                window.__externalDisplayHasDrawn = true;
                this[name] = original;
                return result;
              };
            });
          }
          return context;
        };
        document.addEventListener('DOMContentLoaded', () => {
          if (typeof tokenData === 'undefined') return;
          window.webkit.messageHandlers.externalDisplayProbe.postMessage({
            generation: window.__artBlocksPreviewGeneration,
            tokenId: tokenData.tokenId, hash: tokenData.hash || tokenData.hashes?.[0]
          });
        }, { once: true });
        window.addEventListener('error', event => {
          window.webkit.messageHandlers.externalDisplayProbe.postMessage({
            error: String(event.message || event.target?.src || 'Artwork resource error')
          });
        }, true);
        window.addEventListener('unhandledrejection', event => {
          window.webkit.messageHandlers.externalDisplayProbe.postMessage({error: String(event.reason)});
        });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.didMove(toParent: host)
        window.rootViewController = host
        controller.view.frame = CGRect(origin: .zero, size: size)
        window.isHidden = false
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    func close() {
        updateExternalDisplayToken(.empty)
        webView.stopLoading()
        webView.clearArtBlocksRendering()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "externalDisplayProbe")
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    func resize(to size: CGSize) {
        controller.view.frame.size = size
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    func snapshot() async throws -> [String: Any] {
        let json = try await evaluate("""
        JSON.stringify((() => {
          const svg = document.querySelector('svg');
          const rect = svg?.getBoundingClientRect();
          const metadata = document.querySelector('meta[name="artblocks-review-startup"]');
          return {
            startupProfile: metadata ? JSON.parse(atob(metadata.content)) : null,
            tokenId: typeof tokenData === 'object' ? tokenData.tokenId : null,
            hash: typeof tokenData === 'object' ? tokenData.hash || tokenData.hashes?.[0] : null,
            generation: window.__artBlocksPreviewGeneration,
            ready: document.readyState === 'complete',
            drawn: window.__externalDisplayHasDrawn === true,
            width: innerWidth, height: innerHeight,
            quality: window.__artBlocksPreviewResolution || null,
            canvases: [...document.querySelectorAll('canvas')].filter(c => {
              const r = c.getBoundingClientRect();
              return r.width > 0 && r.height > 0 && c.width > 0 && c.height > 0;
            }).length,
            svgPaint: !!svg && svg.querySelectorAll('path, rect, text, polygon, g').length > 1,
            svg: rect ? { x: rect.x, y: rect.y, right: rect.right, bottom: rect.bottom } : null
          };
        })())
        """)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func evaluate(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let operation = ExternalDisplayEvaluation { continuation.resume(with: $0) }
            webView.evaluateJavaScript(source) { value, error in
                if let error { operation.finish(.failure(error)) }
                else if let value = value as? String { operation.finish(.success(value)) }
                else { operation.finish(.failure(NSError(domain: "ExternalDisplayEvaluation", code: 1))) }
            }
            operation.timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                operation.finish(.failure(NSError(domain: "ExternalDisplayEvaluationTimeout", code: 1)))
            }
        }
    }

    static func webViews(in view: UIView) -> [AutoReloadingWebView] {
        (view as? AutoReloadingWebView).map { [$0] } ?? view.subviews.flatMap { webViews(in: $0) }
    }

    func assertNoFallback(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(webView.isHidden, file: file, line: line)
        XCTAssertTrue(probe.errors.isEmpty, probe.errors.joined(separator: "\n"), file: file, line: line)
        for view in viewsOutsideWebContent(controller.view) where isVisible(view) {
            XCTAssertFalse(view is UIImageView, "Unexpected external-display image fallback", file: file, line: line)
            XCTAssertNotEqual(view.accessibilityIdentifier, "artwork.retry", file: file, line: line)
        }
    }

    private func viewsOutsideWebContent(_ view: UIView) -> [UIView] {
        guard !(view is WKWebView) else { return [] }
        return [view] + view.subviews.flatMap { viewsOutsideWebContent($0) }
    }

    private func isVisible(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden || candidate.alpha == 0 { return false }
            current = candidate.superview
        }
        return view.window != nil
    }
}

@MainActor
extension ArtBlocksExternalDisplayTests {
    func testControllerPreservesDirectAndCalibratedRenderingAcrossTokensAndResize() async throws {
        let assetURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dependency", withExtension: "js", subdirectory: "Hypertype"))
        let asset = try Data(contentsOf: assetURL)
        let fixtureCache = PersistentArtworkDependencyCache(transport: { _ in (asset, 200) })
        _ = try await fixtureCache.data(for: .hypertype)
        updateExternalDisplayToken(.empty)
        defer { updateExternalDisplayToken(.empty) }
        let hypertype = "0xbb5471c292065d3b01b2e81e299267221ae9a2500"
        let autopoiesis = "0x47a91457a3a1f700097199fd63c039c4784384ab80"
        let first = try token(collectionId: hypertype, index: 0)
        let fixture = try ExternalDisplayIntegrationFixture(token: first.generated, size: CGSize(width: 360, height: 480))
        defer { fixture.close() }
        XCTAssertFalse(fixture.webView.configuration.suppressesIncrementalRendering)

        _ = try await ready(fixture, token: first.bundled, calibrated: false, expectedDocuments: 1)
        let second = try token(collectionId: hypertype, index: 1)
        updateExternalDisplayToken(second.generated)
        _ = try await ready(fixture, token: second.bundled, calibrated: false, expectedDocuments: 2)
        XCTAssertTrue(try XCTUnwrap(ExternalDisplayIntegrationFixture.webViews(in: fixture.controller.view).first) === fixture.webView)

        let calibrated = try token(collectionId: autopoiesis, index: 0)
        updateExternalDisplayToken(calibrated.generated)
        let initial = try await ready(fixture, token: calibrated.bundled, calibrated: true, expectedDocuments: 3)
        let initialGeneration = try XCTUnwrap(initial["generation"] as? String)
        XCTAssertEqual(fixture.webView.artworkRenderedSize, CGSize(width: 360, height: 480))

        fixture.resize(to: CGSize(width: 520, height: 380))
        fixture.resize(to: CGSize(width: 640, height: 360))
        let resized = try await ready(fixture, token: calibrated.bundled, calibrated: true, expectedDocuments: 4)
        let resizedGeneration = try XCTUnwrap(resized["generation"] as? String)
        XCTAssertNotEqual(resizedGeneration, initialGeneration)
        XCTAssertEqual(fixture.webView.artworkRenderedSize, CGSize(width: 640, height: 360))
        XCTAssertEqual(try XCTUnwrap(resized["width"] as? Double) * Double(fixture.webView.pageZoom), 640, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(resized["height"] as? Double) * Double(fixture.webView.pageZoom), 360, accuracy: 2)

        fixture.resize(to: CGSize(width: 640, height: 360))
        updateExternalDisplayToken(calibrated.generated)
        let unchanged = try await ready(fixture, token: calibrated.bundled, calibrated: true, expectedDocuments: 4)
        XCTAssertEqual(unchanged["generation"] as? String, resizedGeneration)
        fixture.assertNoFallback()
        let attachment = XCTAttachment(string: String(decoding: try JSONSerialization.data(withJSONObject: ["documents": fixture.probe.documents, "final": unchanged], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        attachment.name = "External display controller integration"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func token(collectionId: String, index: Int) throws -> (generated: GeneratedToken, bundled: BundledTokens.Item) {
        let generated = try XCTUnwrap(TokenGenerator.generateToken(specificCollectionId: collectionId, tokenIndex: index))
        let bundled = try XCTUnwrap(TokenGenerator.bundledWebGenerativeToken(specificCollectionId: collectionId, tokenIndex: index))
        XCTAssertEqual(generated.id, bundled.id)
        XCTAssertEqual(generated.fullCollectionId, collectionId)
        XCTAssertNil(generated.media)
        XCTAssertFalse(generated.html.isEmpty)
        return (generated, bundled)
    }

    private func ready(
        _ fixture: ExternalDisplayIntegrationFixture,
        token: BundledTokens.Item,
        calibrated: Bool,
        expectedDocuments: Int
    ) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if !fixture.probe.errors.isEmpty {
                XCTFail(fixture.probe.errors.joined(separator: "\n"))
                throw NSError(domain: "ExternalDisplayArtworkError", code: 1)
            }
            if let snapshot = try? await fixture.snapshot(), snapshot["tokenId"] as? String == token.id,
               snapshot["ready"] as? Bool == true, fixture.probe.documents.count >= expectedDocuments {
                let quality = snapshot["quality"] as? [String: Any]
                let painted = calibrated
                    ? snapshot["drawn"] as? Bool == true && (snapshot["canvases"] as? Int ?? 0) > 0
                        && (quality?["factor"] as? Double ?? .infinity) <= 1.02 && fixture.webView.artworkIsPresented
                    : snapshot["svgPaint"] as? Bool == true
                if painted {
                    XCTAssertEqual(snapshot["hash"] as? String, token.hash)
                    XCTAssertEqual(fixture.webView.usesStableArtworkPresentation, calibrated)
                    if calibrated {
                        let profile = try XCTUnwrap(snapshot["startupProfile"] as? [String: Any])
                        XCTAssertEqual(profile["authoredPixelDensity"] as? Double, 1)
                    } else {
                        XCTAssertNil(snapshot["startupProfile"] as? [String: Any])
                        let rect = try XCTUnwrap(snapshot["svg"] as? [String: Double])
                        XCTAssertGreaterThanOrEqual(try XCTUnwrap(rect["x"]), -1)
                        XCTAssertGreaterThanOrEqual(try XCTUnwrap(rect["y"]), -1)
                        XCTAssertLessThanOrEqual(try XCTUnwrap(rect["right"]), try XCTUnwrap(snapshot["width"] as? Double) + 1)
                        XCTAssertLessThanOrEqual(try XCTUnwrap(rect["bottom"]), try XCTUnwrap(snapshot["height"] as? Double) + 1)
                    }
                    XCTAssertEqual(fixture.probe.documents.count, expectedDocuments)
                    XCTAssertEqual(fixture.probe.documents.last?["tokenId"] as? String, token.id)
                    XCTAssertEqual(fixture.probe.documents.last?["hash"] as? String, token.hash)
                    fixture.assertNoFallback()
                    return snapshot
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("External-display artwork did not settle for token \(token.id); documents=\(fixture.probe.documents.count), errors=\(fixture.probe.errors)")
        throw NSError(domain: "ExternalDisplayReadiness", code: 1)
    }
}
