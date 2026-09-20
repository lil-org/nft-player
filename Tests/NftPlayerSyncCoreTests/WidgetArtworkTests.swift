import Foundation
import ImageIO
import XCTest
@testable import NftPlayerSyncCore

final class WidgetArtworkTests: XCTestCase {
    func testCollectionDefaultsRequireMidAndDeclaredThumbnailPaths() throws {
        for fields: [String: Any] in [[:], [
            "hasMid": NSNull(),
            "standardThumbsPathsAvailable": NSNull(),
            "standardThumbsBaseURL": NSNull(),
        ]] {
            let collection = try collection(fields)
            XCTAssertTrue(collection.hasMid)
            XCTAssertFalse(collection.standardThumbsPathsAvailable)
            XCTAssertNil(collection.standardThumbsBaseURL)
            XCTAssertNil(WidgetTokenItem(id: "token", urlSuffix: "1.png")
                .staticImageReference(collection: collection))
        }
    }

    func testCollectionIdentityAndResourceNameRemainStable() throws {
        let collection = try collection([
            "address": "contract",
            "abId": "123",
            "collectionId": "other",
            "name": "  Artwork  ",
            "internal_slug": "artwork",
        ])
        XCTAssertEqual(collection.id, "contract123")
        XCTAssertEqual(collection.name, "Artwork")
        XCTAssertEqual(collection.bundledResourceName, "artwork")

        let fallback = try self.collection([
            "address": "contract",
            "collectionId": "42",
            "name": "  ",
            "internal_slug": "",
        ])
        XCTAssertEqual(fallback.id, "contract42")
        XCTAssertEqual(fallback.name, "contract42")
        XCTAssertEqual(fallback.bundledResourceName, "contract42")
    }

    func testMidUsesPreservedFilenameForStaticAndAnimatedMedia() throws {
        let collection = try collection(["standardThumbsPathsAvailable": true])
        for fileExtension in ["png", "jpg", "jpeg", "webp", "gif", "svg", "mp4", "html"] {
            let token = WidgetTokenItem(id: "different-token-id", urlSuffix: "0007.\(fileExtension)")
            let reference = try XCTUnwrap(token.staticImageReference(collection: collection))
            XCTAssertEqual(reference.tokenId, "different-token-id")
            XCTAssertEqual(reference.url.absoluteString, "https://cdn.example.com/artwork/mid/0007.webp")
        }
    }

    func testMidStripsOriginalQueryAndFragment() throws {
        let collection = try collection([
            "hasMid": true,
            "standardThumbsPathsAvailable": true,
        ])
        let token = WidgetTokenItem(id: "token", urlSuffix: "nested/0007.png?version=3#artwork")
        XCTAssertEqual(
            token.staticImageReference(collection: collection)?.url.absoluteString,
            "https://cdn.example.com/artwork/nested/mid/0007.webp"
        )
    }

    func testMidUsesCustomThumbnailBaseForExtensionlessSource() throws {
        let collection = try collection([
            "urlPrefix": "https://tokens.example.com/token-html/",
            "standardThumbsPathsAvailable": true,
            "standardThumbsBaseURL": "https://cdn.example.com/terraforms/thumbs/",
        ])
        let token = WidgetTokenItem(id: "token-42", urlSuffix: "0007")
        let reference = try XCTUnwrap(token.staticImageReference(collection: collection))
        XCTAssertEqual(reference.tokenId, "token-42")
        XCTAssertEqual(reference.url.absoluteString, "https://cdn.example.com/terraforms/mid/0007.webp")
    }

    func testMidFailureNeverFallsBackToOriginalOrThumbnail() throws {
        let cases: [[String: Any]] = [
            ["standardThumbsPathsAvailable": false],
            ["standardThumbsPathsAvailable": true, "standardThumbsBaseURL": "file:///artwork/thumbs/"],
            ["standardThumbsPathsAvailable": true, "standardThumbsBaseURL": "https://cdn.example.com/previews/"],
            ["standardThumbsPathsAvailable": true, "standardThumbsBaseURL": "https://cdn.example.com/thumbs/?v=1"],
        ]
        for fields in cases {
            let collection = try collection(fields)
            XCTAssertNil(WidgetTokenItem(id: "token", urlSuffix: "0007.png")
                .staticImageReference(collection: collection))
        }
        let collection = try collection(["standardThumbsPathsAvailable": true])
        XCTAssertNil(WidgetTokenItem(id: "token", urlSuffix: "extensionless")
            .staticImageReference(collection: collection))
    }

    func testMidRejectsMalformedOrUnsupportedSourceURLs() throws {
        let collection = try collection([
            "urlPrefix": "",
            "standardThumbsPathsAvailable": true,
        ])
        for source in [
            "file:///artwork/0007.png",
            "ipfs://image/0007.png",
            "/artwork/0007.png",
            "https:///0007.png",
            "https://cdn.example.com/artwork/",
            "https://cdn.example.com/artwork/nested%2F0007.png",
            "https://cdn.example.com/artwork/nested%5C0007.png",
        ] {
            XCTAssertNil(WidgetTokenItem(id: "token", urlSuffix: source)
                .staticImageReference(collection: collection), source)
        }
    }

    func testNoMidUsesOriginalStaticImageWithoutRewriting() throws {
        let collection = try collection([
            "hasMid": false,
            "standardThumbsPathsAvailable": false,
        ])
        for fileExtension in ["png", "jpg", "jpeg", "webp", "heic", "heif", "tiff"] {
            let suffix = "0007.\(fileExtension)?version=3#artwork"
            let reference = try XCTUnwrap(WidgetTokenItem(id: "token", urlSuffix: suffix)
                .staticImageReference(collection: collection))
            XCTAssertEqual(reference.tokenId, "token")
            XCTAssertEqual(reference.url.absoluteString, "https://cdn.example.com/artwork/" + suffix)
        }
        XCTAssertEqual(
            WidgetTokenItem(id: "token", urlSuffix: "0007?ext=png")
                .staticImageReference(collection: collection)?.url.absoluteString,
            "https://cdn.example.com/artwork/0007?ext=png"
        )
    }

    func testNoMidRejectsNonStaticMediaAndNonHTTPURLs() throws {
        let collection = try collection([
            "urlPrefix": "",
            "hasMid": false,
            "standardThumbsPathsAvailable": true,
        ])
        for source in [
            "https://cdn.example.com/0007.gif",
            "https://cdn.example.com/0007.svg",
            "https://cdn.example.com/0007.mp4",
            "https://cdn.example.com/0007.html",
            "https://cdn.example.com/0007",
            "file:///artwork/0007.png",
            "0007.png",
        ] {
            XCTAssertNil(WidgetTokenItem(id: "token", urlSuffix: source)
                .staticImageReference(collection: collection), source)
        }
    }

    func testEthereumSourceFallbackStillUsesTokenID() throws {
        let collection = try collection([
            "address": "0xcontract",
            "chain": "ethereum",
            "standardThumbsPathsAvailable": true,
        ])
        let token = WidgetTokenItem(id: "123000007", urlSuffix: nil)
        let reference = try XCTUnwrap(token.staticImageReference(collection: collection))
        XCTAssertEqual(reference.tokenId, "123000007")
        XCTAssertEqual(
            reference.url.absoluteString,
            "https://media-proxy.artblocks.io/0xcontract/mid/123000007.webp"
        )
        XCTAssertNil(token.staticImageReference(collection: try self.collection([
            "chain": "solana",
            "standardThumbsPathsAvailable": true,
        ])))
    }

    func testCompactPayloadRetainsIDsWhenTemplateUsesIndex() throws {
        let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: Data("""
            {"version":2,"count":2,"ids":["token-a","token-b"],"urlTemplate":{"value":"index1","suffix":".gif"}}
            """.utf8))
        let collection = try collection(["standardThumbsPathsAvailable": true])
        XCTAssertEqual(payload.items.map(\.id), ["token-a", "token-b"])
        XCTAssertEqual(payload.items.map(\.urlSuffix), ["1.gif", "2.gif"])
        let references = payload.items.compactMap { $0.staticImageReference(collection: collection) }
        XCTAssertEqual(references.map(\.tokenId), ["token-a", "token-b"])
        XCTAssertEqual(references.map(\.url.absoluteString), [
            "https://cdn.example.com/artwork/mid/1.webp",
            "https://cdn.example.com/artwork/mid/2.webp",
        ])
    }

    func testCompactPayloadPreservesPaddedExplicitFilename() throws {
        let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: Data("""
            {"version":2,"count":1,"firstId":"1000000","urlSuffix":["0007.png"]}
            """.utf8))
        let collection = try collection(["standardThumbsPathsAvailable": true])
        let reference = try XCTUnwrap(payload.items.first?.staticImageReference(collection: collection))
        XCTAssertEqual(reference.tokenId, "1000000")
        XCTAssertEqual(reference.url.absoluteString, "https://cdn.example.com/artwork/mid/0007.webp")
    }

    func testCacheCodecRoundTripsCurrentVersionAndNormalizesEmptyTokenID() throws {
        let png = try pngData()
        for tokenID: String? in ["token-42", "", nil] {
            let encoded = try XCTUnwrap(WidgetImageCacheCodec.encode(WidgetCachedImage(data: png, tokenId: tokenID)))
            let decoded = try XCTUnwrap(WidgetImageCacheCodec.decode(encoded))
            XCTAssertEqual(decoded.data, png)
            XCTAssertEqual(decoded.tokenId, tokenID?.isEmpty == false ? tokenID : nil)
            let record = try XCTUnwrap(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
            XCTAssertEqual(record["version"] as? Int, 2)
        }
    }

    func testCacheCodecRejectsLegacyRawImageAndRecords() throws {
        let png = try pngData()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
        XCTAssertNil(WidgetImageCacheCodec.decode(png))
        for version in [0, 1, 3, 999] {
            let encoded = try PropertyListSerialization.data(fromPropertyList: [
                "version": version,
                "data": png,
                "tokenId": "old-token",
            ], format: .binary, options: 0)
            XCTAssertNil(WidgetImageCacheCodec.decode(encoded))
        }
    }

    func testCacheCodecRejectsCorruptAndIncompleteRecords() throws {
        XCTAssertNil(WidgetImageCacheCodec.decode(Data()))
        XCTAssertNil(WidgetImageCacheCodec.decode(Data("corrupt".utf8)))
        for record: [String: Any] in [
            ["version": 2, "tokenId": "token"],
            ["version": 2, "data": 123],
            ["data": try pngData(), "tokenId": "token"],
        ] {
            let encoded = try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
            XCTAssertNil(WidgetImageCacheCodec.decode(encoded))
        }
    }

    private func collection(_ fields: [String: Any] = [:]) throws -> WidgetCollection {
        var values: [String: Any] = [
            "address": "collection",
            "chain": "solana",
            "urlPrefix": "https://cdn.example.com/artwork/",
        ]
        values.merge(fields) { _, replacement in replacement }
        return try JSONDecoder().decode(
            WidgetCollection.self,
            from: JSONSerialization.data(withJSONObject: values)
        )
    }

    private func pngData() throws -> Data {
        try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
    }
}
