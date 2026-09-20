import Foundation
import XCTest
@testable import NftPlayerSyncCore

final class ArtworkAssetPolicyTests: XCTestCase {
    func testCDNHostAndSchemeAreExact() throws {
        for value in ["https://cdn.lil.org/player/1.webp", "https://CDN.LIL.ORG:443/art.png?v=2"] {
            XCTAssertTrue(ArtworkAssetPolicy.allowsRemoteURL(try XCTUnwrap(URL(string: value))))
        }
        for value in [
            "http://cdn.lil.org/art.png", "https://cdn.lil.org.example.com/art.png",
            "https://example.com/cdn.lil.org/art.png", "https://user@cdn.lil.org/art.png",
            "https://cdn.lil.org:8443/art.png", "file:///art.png", "https://media-proxy.artblocks.io/art.png",
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertFalse(ArtworkAssetPolicy.allowsRemoteURL(url), value)
            XCTAssertThrowsError(try ArtworkAssetPolicy.validateRemoteURL(url), value)
        }
    }

    func testTerraformsExceptionRequiresItsHTMLTokenEndpoint() throws {
        let url = try XCTUnwrap(URL(string: "https://tokens.mathcastles.xyz/terraforms/token-html/123?ext=html"))
        XCTAssertFalse(ArtworkAssetPolicy.allowsRemoteURL(url))
        XCTAssertTrue(ArtworkAssetPolicy.allowsRemoteURL(url, allowsTerraforms: true))
        for value in [
            "https://tokens.mathcastles.xyz/other/123?ext=html",
            "https://tokens.mathcastles.xyz/terraforms/token-html/123/image.png?ext=html",
            "https://tokens.mathcastles.xyz/terraforms/token-html/%31?ext=html",
            "https://tokens.mathcastles.xyz/terraforms/token-html/123",
            "https://tokens.mathcastles.xyz/terraforms/token-html/123?ext=png",
            "https://tokens.mathcastles.xyz/terraforms/token-html/123?ext=html&other=1",
        ] {
            XCTAssertFalse(ArtworkAssetPolicy.allowsRemoteURL(
                try XCTUnwrap(URL(string: value)), allowsTerraforms: true
            ), value)
        }
    }

    func testSessionsRejectExternalRedirectsBeforeFollowingThem() async throws {
        let origin = try XCTUnwrap(URL(string: "https://cdn.lil.org/asset"))
        let response = try XCTUnwrap(HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: nil))
        for allowsTerraforms in [false, true] {
            let session = ArtworkAssetPolicy.makeSession(configuration: .ephemeral, allowsTerraforms: allowsTerraforms)
            defer { session.invalidateAndCancel() }
            let delegate = try XCTUnwrap(session.delegate as? URLSessionTaskDelegate)
            let task = session.dataTask(with: origin)
            for value in [
                "https://cdn.lil.org/other.webp",
                "https://tokens.mathcastles.xyz/terraforms/token-html/1?ext=html",
                "https://media-proxy.artblocks.io/1.png",
            ] {
                let url = try XCTUnwrap(URL(string: value))
                let redirected: URLRequest? = await withCheckedContinuation { continuation in
                    delegate.urlSession?(
                        session, task: task, willPerformHTTPRedirection: response,
                        newRequest: URLRequest(url: url)
                    ) { continuation.resume(returning: $0) }
                }
                XCTAssertEqual(redirected?.url, ArtworkAssetPolicy.allowsRemoteURL(url, allowsTerraforms: allowsTerraforms) ? url : nil)
            }
        }
    }

    func testPolicyIsInsertedBeforeContentAndOnlyOnce() throws {
        let documents = [
            "<!doctype html><html><head><script>run()</script></head><body></body></html>",
            "<!-- before --><HTML data-value='>'>\n<HEAD><script>run()</script></HEAD></HTML>",
            "<html><body><script>run()</script></body></html>",
            "<script>run()</script><head></head>",
        ]
        for document in documents {
            let protected = ArtworkAssetPolicy.protectHTML(document)
            let policy = try XCTUnwrap(protected.range(of: ArtworkAssetPolicy.contentSecurityPolicyMetaTag))
            let script = try XCTUnwrap(protected.range(of: "<script>"))
            XCTAssertLessThan(policy.lowerBound, script.lowerBound)
            XCTAssertEqual(ArtworkAssetPolicy.protectHTML(protected), protected)
        }
        XCTAssertEqual(ArtworkAssetPolicy.protectHTML(""), "")
    }

    func testDependencyCacheRejectsExternalDescriptors() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = PersistentArtworkDependencyCache(rootURL: root, transport: { _ in
            throw URLError(.badServerResponse)
        })
        let dependency = PersistentArtworkDependency(
            id: "external", remoteURL: try XCTUnwrap(URL(string: "https://example.com/script.js")),
            expectedByteCount: 1, sha256: String(repeating: "0", count: 64)
        )
        do {
            _ = try await cache.data(for: dependency)
            XCTFail("External descriptor was accepted")
        } catch {
            XCTAssertEqual(error as? PersistentArtworkDependencyCache.Failure, .invalidDescriptor)
        }
    }
}
