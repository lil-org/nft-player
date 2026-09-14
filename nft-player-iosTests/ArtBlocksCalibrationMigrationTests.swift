import CryptoKit
import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksCalibrationMigrationTests: XCTestCase {}

private struct MigratedStartupCalibration: Codable, Equatable {
    let zoom: Double
    let ignoresReports: Bool
}

@MainActor
private final class CalibrationMigrationDocumentProbe: NSObject, WKScriptMessageHandler {
    var documents: [[String: String]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let document = message.body as? [String: String] else { return }
        documents.append(document)
    }
}

@MainActor
extension ArtBlocksCalibrationMigrationTests {
    func testLegacyCalibrationMigratesBeforeFirstArtworkLoadWithoutChangingHistoricalReviewState() async throws {
        let collectionId = "0x47a91457a3a1f700097199fd63c039c4784384ab80"
        let identity = "42161:0x47a91457a3a1f700097199fd63c039c4784384ab:80"
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundle.url(forResource: "Scripts/" + collectionId, withExtension: "json"))
        let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: scriptURL))
        let token = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: collectionId)?.items.first)
        let profile = try XCTUnwrap(ArtBlocksRenderingStartupProfiles.startupProfile(script))
        let legacyId = try XCTUnwrap(script.legacyArtBlocksCollectionId)
        XCTAssertEqual(script.name, "Autopoiesis ")
        XCTAssertEqual(profile.authoredPixelDensity, 1)
        XCTAssertEqual(legacyId, "0x47a91457a3a1f700097199fd63c039c4784384ab-dev-good-42161-80")

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let host = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        let size = CGSize(width: 300, height: 300)
        let scale = max(window.screen.scale, 1)
        let idiom = host.view.traitCollection.userInterfaceIdiom.rawValue
        func calibrationKey(_ id: String) -> String {
            let values = [id, token.id, profile.revision, String(Double(size.width)), String(Double(size.height)),
                          String(Double(scale)), String(idiom), ProcessInfo.processInfo.operatingSystemVersionString]
            return SHA256.hash(data: Data(values.joined(separator: "|").utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
        let oldKey = calibrationKey(legacyId)
        let newKey = calibrationKey(collectionId)
        XCTAssertNotEqual(oldKey, newKey)
        let calibration = MigratedStartupCalibration(zoom: Double(1 / scale), ignoresReports: false)
        let storageKey = "artBlocksReview.startupCalibrations.v1"
        let reviewSentinels = [
            "artBlocksReview.decisionsByIdentity.v1": [identity: "yes"],
            "artBlocksReview.notesByIdentity.v1": [identity: "Preserve the original review note."],
            "artBlocksReview.pass-5.decisionsByIdentity.v1": [identity: "double-check"],
            "artBlocksReview.pass-5.notesByIdentity.v1": [identity: "Preserve the final review note. 雪"]
        ]
        let defaults = UserDefaults.standard
        let previousValues = ([storageKey] + reviewSentinels.keys.sorted()).map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previousValues {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(try JSONEncoder().encode([oldKey: calibration]), forKey: storageKey)
        for (key, value) in reviewSentinels { defaults.set(value, forKey: key) }

        let webView = AutoReloadingWebView.newArtBlocksRenderer()
        webView.frame = CGRect(origin: .zero, size: size)
        let probe = CalibrationMigrationDocumentProbe()
        webView.configuration.userContentController.add(probe, name: "calibrationMigrationDocumentProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        document.addEventListener('DOMContentLoaded', function () {
          window.webkit.messageHandlers.calibrationMigrationDocumentProbe.postMessage({
            generation: window.__artBlocksPreviewGeneration,
            tokenId: String(tokenData.tokenId), hash: tokenData.hash
          });
        }, { once: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        host.view.addSubview(webView)
        window.layoutIfNeeded()
        defer {
            webView.stopLoading()
            webView.clearArtBlocksRendering()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "calibrationMigrationDocumentProbe")
            webView.removeFromSuperview()
        }
        XCTAssertEqual(webView.traitCollection.userInterfaceIdiom.rawValue, idiom)
        var errors: [String] = []
        webView.configureArtBlocksRendering(collectionId: collectionId, tokenId: token.id) { errors.append($0) }
        webView.loadHTMLString(RawHtmlGenerator.createHtml(script: script, token: token), baseURL: nil)

        func storedCalibrations() throws -> [String: MigratedStartupCalibration] {
            try JSONDecoder().decode([String: MigratedStartupCalibration].self,
                from: XCTUnwrap(defaults.data(forKey: storageKey)))
        }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, errors.isEmpty {
            if try storedCalibrations()[newKey] != nil, webView.artworkIsPresented, !probe.documents.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let migrated = try storedCalibrations()
        XCTAssertNil(migrated[oldKey])
        XCTAssertEqual(migrated, [newKey: calibration])
        XCTAssertTrue(webView.artworkIsPresented)
        XCTAssertEqual(Double(webView.pageZoom), calibration.zoom, accuracy: 0.000001)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "; "))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(probe.documents.count, 1)
        XCTAssertEqual(probe.documents.first?["tokenId"], token.id)
        XCTAssertEqual(probe.documents.first?["hash"], token.hash)
        XCTAssertEqual(try storedCalibrations(), [newKey: calibration])
        for (key, value) in reviewSentinels {
            XCTAssertEqual(defaults.dictionary(forKey: key) as? [String: String], value)
        }
    }
}
