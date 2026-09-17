import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksPlaybackErrorTests: XCTestCase {}

@MainActor
private final class PlaybackErrorDocumentProbe: NSObject, WKScriptMessageHandler {
    var documents: [[String: String]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let document = message.body as? [String: String] else { return }
        documents.append(document)
    }
}

@MainActor
extension ArtBlocksPlaybackErrorTests {
    func testArtworkErrorUsesGenericNativeRetryAndRejectsStaleErrorsAfterRecovery() async throws {
        let collectionId = "0x47a91457a3a1f700097199fd63c039c4784384ab80"
        let token = try XCTUnwrap(TokenGenerator.generateToken(specificCollectionId: collectionId, tokenIndex: 0))
        XCTAssertFalse(token.html.isEmpty)
        XCTAssertNil(token.media)
        XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: collectionId, tokenIndex: 0))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let host = UIViewController()
        let container = UIView(frame: CGRect(x: 20, y: 60, width: 300, height: 300))
        host.view.addSubview(container)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        let renderer = FullscreenTokenMediaRenderer(containerView: container)
        renderer.configureArtBlocksRendering(collectionId: collectionId, tokenId: token.id)
        let webView = try XCTUnwrap(descendants(of: container).compactMap { $0 as? AutoReloadingWebView }.first)
        webView.artworkDependencyCache = JavaScriptLibraryFixtures.cache
        let probe = PlaybackErrorDocumentProbe()
        webView.configuration.userContentController.add(probe, name: "playbackErrorDocumentProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        document.addEventListener('DOMContentLoaded', function () {
          window.webkit.messageHandlers.playbackErrorDocumentProbe.postMessage({
            generation: window.__artBlocksPreviewGeneration,
            tokenId: String(tokenData.tokenId), hash: tokenData.hash
          });
        }, { once: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        defer {
            renderer.clearContent()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "playbackErrorDocumentProbe")
        }
        renderer.renderWebContent(token.html)
        window.layoutIfNeeded()
        try await waitUntil { webView.artworkIsPresented && probe.documents.count == 1 }
        let originalGeneration = try XCTUnwrap(probe.documents.first?["generation"])
        XCTAssertEqual(probe.documents.first?["tokenId"], token.id)

        _ = try await webView.evaluateJavaScript("window.showPreviewError('private QA diagnostic'); true")
        try await waitUntil { self.retryButton(in: container).map(self.isVisible) == true }
        let retry = try XCTUnwrap(retryButton(in: container))
        XCTAssertEqual(retry.title(for: .normal), String(localized: "Retry artwork"))
        let labels = descendants(of: container).compactMap { $0 as? UILabel }.filter(isVisible)
        XCTAssertTrue(labels.contains { $0.text == String(localized: "This artwork couldn’t be rendered.") })
        XCTAssertFalse(labels.contains { $0.text?.contains("private QA diagnostic") == true })
        XCTAssertTrue(isVisible(webView))
        XCTAssertEqual(probe.documents.count, 1)
        assertNoImageFallback(in: container, webView: webView)
        let errorImage = UIGraphicsImageRenderer(bounds: container.bounds).image { _ in
            container.drawHierarchy(in: container.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: errorImage)
        attachment.name = "Generic artwork error and retry"
        attachment.lifetime = .keepAlways
        add(attachment)

        retry.sendActions(for: .touchUpInside)
        try await waitUntil {
            webView.artworkIsPresented && probe.documents.count == 2
                && probe.documents.last?["generation"] != originalGeneration
        }
        XCTAssertFalse(isVisible(retry))
        XCTAssertEqual(probe.documents.last?["tokenId"], token.id)
        XCTAssertEqual(probe.documents.last?["hash"], probe.documents.first?["hash"])
        let restoredGeneration = try XCTUnwrap(probe.documents.last?["generation"])
        let staleError: [String: String] = ["generation": originalGeneration, "collectionId": collectionId,
                                           "tokenId": token.id, "message": "stale private QA diagnostic"]
        let staleJSON = String(decoding: try JSONSerialization.data(withJSONObject: staleError), as: UTF8.self)
        _ = try await webView.evaluateJavaScript("window.webkit.messageHandlers.artBlocksPreviewError.postMessage(\(staleJSON)); true")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(isVisible(retry))
        XCTAssertTrue(webView.artworkIsPresented)
        XCTAssertEqual(probe.documents.count, 2)
        XCTAssertEqual(probe.documents.last?["generation"], restoredGeneration)
        assertNoImageFallback(in: container, webView: webView)
        let remoteResources = try await webView.evaluateJavaScript("performance.getEntriesByType('resource').map(entry => entry.name).filter(url => /^https?:/.test(url))")
        XCTAssertEqual(remoteResources as? [String], [])
    }

    private func retryButton(in container: UIView) -> UIButton? {
        descendants(of: container).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "artwork.retry" }
    }

    private func assertNoImageFallback(in container: UIView, webView: AutoReloadingWebView) {
        let nativeImages = descendants(of: container).compactMap { $0 as? UIImageView }
            .filter { !$0.isDescendant(of: webView) && isVisible($0) && $0.image != nil }
        XCTAssertTrue(nativeImages.isEmpty)
        XCTAssertEqual(descendants(of: container).compactMap { $0 as? AutoReloadingWebView }.count, 1)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func isVisible(_ view: UIView) -> Bool {
        guard view.window != nil else { return false }
        var current: UIView? = view
        while let ancestor = current {
            if ancestor.isHidden || ancestor.alpha <= 0 { return false }
            current = ancestor.superview
        }
        return true
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the artwork error or retry transition")
        throw NSError(domain: "ArtBlocksPlaybackErrorTests", code: 1)
    }
}
