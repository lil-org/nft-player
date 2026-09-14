import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksRenderingResizeTests: XCTestCase {}

private actor PreviewResizeViewingTracker: MobilePlaybackViewingSessionTracking {
    func prepareRestartUpdate(collectionId: String?) async -> PlayerContinueViewingUpdate? { nil }
    func beginRestart(update: PlayerContinueViewingUpdate?) async {}
    func markViewed(_ progress: MobileViewingProgress) async {}
}

@MainActor
private final class PreviewResizeDocumentProbe: NSObject, WKScriptMessageHandler {
    var documents: [[String: Any]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let document = message.body as? [String: Any] {
            documents.append(document)
        }
    }
}

@MainActor
extension ArtBlocksRenderingResizeTests {
    func testVisiblePreviewReloadsOnceAfterSettledResizeAndCanPageForward() async throws {
        let item = try XCTUnwrap(SuggestedItemsService.allItems.filter { $0.generativeOnly == true }.first { $0.name == "Afterimage" })
        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
        let registry = MobilePlaybackSessionRegistry(dependencies: .init(
            makeViewingSessionTracker: { _ in PreviewResizeViewingTracker() },
            clearActiveMediaWindow: { _ in },
            cancelAllMediaDownloads: {},
            installDownloadableMediaWindow: { _, _ in XCTFail("Preview requested downloadable media") }
        ))
        let session = registry.startSession(config: MobilePlayerConfig(initialItemId: item.id, initialTokenIndex: 0))
        let player = makePlayer(session: session, presentationMode: .fullscreen)
        let host = UIViewController()
        host.addChild(player)
        host.view.addSubview(player.view)
        player.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        player.didMove(toParent: host)
        let navigation = PlayerNavigationController(rootViewController: host)
        navigation.setNavigationBarHidden(true, animated: false)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = navigation
        window.isHidden = false
        window.layoutIfNeeded()
        player.view.layoutIfNeeded()
        defer {
            player.deactivatePagerForCollectionBrowser()
            session.stopAndDisconnect()
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitForPreview {
            guard let webView = self.webViews(in: player.view).first else { return false }
            return (try? await webView.evaluateJavaScript("document.readyState === 'complete' && window.__artBlocksPreviewResolution?.factor <= 1.02 && tokenData.tokenId")) as? String == tokens.items[0].id
        }
        let webView = try XCTUnwrap(webViews(in: player.view).first)
        let generationValue = try await webView.evaluateJavaScript("window.__artBlocksPreviewGeneration")
        let initialGeneration = try XCTUnwrap(generationValue as? String)
        XCTAssertEqual(webView.bounds.size, CGSize(width: 390, height: 844))
        let probe = PreviewResizeDocumentProbe()
        webView.configuration.userContentController.add(probe, name: "previewResizeProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        document.addEventListener('DOMContentLoaded', function () {
          window.webkit.messageHandlers.previewResizeProbe.postMessage({
            generation: window.__artBlocksPreviewGeneration,
            width: innerWidth, height: innerHeight, tokenId: tokenData.tokenId
          });
        }, { once: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        defer { webView.configuration.userContentController.removeScriptMessageHandler(forName: "previewResizeProbe") }

        player.view.frame.size = CGSize(width: 700, height: 420)
        player.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        player.view.frame.size = CGSize(width: 844, height: 390)
        player.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(probe.documents.isEmpty)
        let unsettledGeneration = try await webView.evaluateJavaScript("window.__artBlocksPreviewGeneration") as? String
        XCTAssertEqual(unsettledGeneration, initialGeneration)
        try await waitForPreview { !probe.documents.isEmpty }
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(probe.documents.count, 1)
        let resized = try XCTUnwrap(probe.documents.first)
        XCTAssertNotEqual(resized["generation"] as? String, initialGeneration)
        XCTAssertEqual(try XCTUnwrap(resized["width"] as? Double) * Double(webView.pageZoom), 844, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(resized["height"] as? Double) * Double(webView.pageZoom), 390, accuracy: 1)
        XCTAssertEqual(resized["tokenId"] as? String, tokens.items[0].id)
        XCTAssertEqual(webView.bounds.size, CGSize(width: 844, height: 390))

        let initialPosition = player.pagerCurrentPagePosition()
        player.navigatePager(.forward)
        try await waitForPreview {
            guard player.pagerCurrentPagePosition().position == initialPosition.position + 1 else { return false }
            for candidate in self.webViews(in: player.view) {
                if (try? await candidate.evaluateJavaScript("document.readyState === 'complete' && window.__artBlocksPreviewResolution?.factor <= 1.02 && tokenData.tokenId")) as? String == tokens.items[1].id {
                    return true
                }
            }
            return false
        }
        XCTAssertEqual(player.pagerCurrentPagePosition().position, initialPosition.position + 1)

        player.deactivatePagerForCollectionBrowser()
        player.willMove(toParent: nil)
        player.view.removeFromSuperview()
        player.removeFromParent()
        let fittedPlayer = makePlayer(session: session, presentationMode: .thumbnailAspectFit)
        host.addChild(fittedPlayer)
        host.view.addSubview(fittedPlayer.view)
        fittedPlayer.view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        fittedPlayer.didMove(toParent: host)
        fittedPlayer.view.layoutIfNeeded()
        defer { fittedPlayer.deactivatePagerForCollectionBrowser() }
        XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: 0))
        let ratio = try XCTUnwrap(tokens.items[0].artworkAspectRatio ?? tokens.items[0].thumbnailAspectRatio)
        XCTAssertEqual(ratio.width, ratio.height)
        try await waitForPreview {
            guard let fittedWebView = self.webViews(in: fittedPlayer.view).first else { return false }
            return (try? await fittedWebView.evaluateJavaScript("document.readyState === 'complete' && window.__artBlocksPreviewResolution?.factor <= 1.02 && tokenData.tokenId")) as? String == tokens.items[0].id
        }
        let fittedWebView = try XCTUnwrap(webViews(in: fittedPlayer.view).first)
        XCTAssertEqual(fittedWebView.bounds.size, CGSize(width: 390, height: 390))
        let fittedDimensionsValue = try await fittedWebView.evaluateJavaScript("[innerWidth, innerHeight]")
        let fittedDimensions = try XCTUnwrap(fittedDimensionsValue as? [Double])
        XCTAssertEqual(fittedDimensions[0] * Double(fittedWebView.pageZoom), 390, accuracy: 1)
        XCTAssertEqual(fittedDimensions[1] * Double(fittedWebView.pageZoom), 390, accuracy: 1)
    }

    private func makePlayer(session: MobilePlaybackSession, presentationMode: MobileBundledGenerativePresentationMode) -> HorizontalPlayerContainer {
        HorizontalPlayerContainer(
            playbackSession: session,
            chrome: MobilePlayerChromeController(allowsNavigationBackSwipe: false),
            bundledGenerativePresentationMode: presentationMode,
            onFocusedPagePositionUpdate: { _ in },
            onSettledPagePositionUpdate: { _, _ in true },
            onPaginationAttempt: {},
            onUnavailableNavigation: {},
            onToggleChrome: {},
            onZoomStateChange: { _ in }
        )
    }

    private func webViews(in view: UIView) -> [AutoReloadingWebView] {
        (view as? AutoReloadingWebView).map { [$0] } ?? view.subviews.flatMap { webViews(in: $0) }
    }

    private func waitForPreview(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for the actual preview player")
        throw NSError(domain: "ArtBlocksRenderingResizeTests", code: 1)
    }
}
