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

    func testCollectionAvailabilityMatchesHostPlatform() throws {
        let restricted = try collection(["iosOnly": true, "generativeOnly": true])
        XCTAssertTrue(restricted.isAvailable(on: .iOS))
        XCTAssertFalse(restricted.isAvailable(on: .macOS))
        XCTAssertFalse(restricted.isAvailable(on: .visionOS))
        XCTAssertTrue(try collection(["iosOnly": true]).isAvailable(on: .macOS))

        let disabledRenderer = try collection([
            "address": "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270",
            "abId": "250",
        ])
        XCTAssertTrue(disabledRenderer.isAvailable(on: .iOS))
        XCTAssertTrue(disabledRenderer.isAvailable(on: .macOS))
        XCTAssertFalse(disabledRenderer.isAvailable(on: .visionOS))
    }

    func testMidUsesPreservedFilenameForStaticAndAnimatedMedia() throws {
        let collection = try collection(["standardThumbsPathsAvailable": true])
        for fileExtension in ["png", "jpg", "jpeg", "webp", "gif", "svg", "mp4", "html"] {
            let token = WidgetTokenItem(id: "different-token-id", urlSuffix: "0007.\(fileExtension)")
            let reference = try XCTUnwrap(token.staticImageReference(collection: collection))
            XCTAssertEqual(reference.tokenId, "different-token-id")
            XCTAssertEqual(reference.url.absoluteString, "https://cdn.lil.org/artwork/mid/0007.webp")
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
            "https://cdn.lil.org/artwork/nested/mid/0007.webp"
        )
    }

    func testMidUsesCustomThumbnailBaseForExtensionlessSource() throws {
        let collection = try collection([
            "urlPrefix": "https://tokens.mathcastles.xyz/terraforms/token-html/",
            "standardThumbsPathsAvailable": true,
            "standardThumbsBaseURL": "https://cdn.lil.org/terraforms/thumbs/",
        ])
        let token = WidgetTokenItem(id: "token-42", urlSuffix: "0007")
        let reference = try XCTUnwrap(token.staticImageReference(collection: collection))
        XCTAssertEqual(reference.tokenId, "token-42")
        XCTAssertEqual(reference.url.absoluteString, "https://cdn.lil.org/terraforms/mid/0007.webp")
    }

    func testMidFailureNeverFallsBackToOriginalOrThumbnail() throws {
        let cases: [[String: Any]] = [
            ["standardThumbsPathsAvailable": false],
            ["standardThumbsPathsAvailable": true, "standardThumbsBaseURL": "file:///artwork/thumbs/"],
            ["standardThumbsPathsAvailable": true, "standardThumbsBaseURL": "https://cdn.lil.org/previews/"],
            ["standardThumbsPathsAvailable": true, "standardThumbsBaseURL": "https://cdn.lil.org/thumbs/?v=1"],
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
            "https://cdn.lil.org/artwork/",
            "https://cdn.lil.org/artwork/nested%2F0007.png",
            "https://cdn.lil.org/artwork/nested%5C0007.png",
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
            XCTAssertEqual(reference.url.absoluteString, "https://cdn.lil.org/artwork/" + suffix)
        }
        XCTAssertEqual(
            WidgetTokenItem(id: "token", urlSuffix: "0007?ext=png")
                .staticImageReference(collection: collection)?.url.absoluteString,
            "https://cdn.lil.org/artwork/0007?ext=png"
        )
    }

    func testNoMidRejectsNonStaticMediaAndNonHTTPURLs() throws {
        let collection = try collection([
            "urlPrefix": "",
            "hasMid": false,
            "standardThumbsPathsAvailable": true,
        ])
        for source in [
            "https://cdn.lil.org/0007.gif",
            "https://cdn.lil.org/0007.svg",
            "https://cdn.lil.org/0007.mp4",
            "https://cdn.lil.org/0007.html",
            "https://cdn.lil.org/0007",
            "file:///artwork/0007.png",
            "0007.png",
        ] {
            XCTAssertNil(WidgetTokenItem(id: "token", urlSuffix: source)
                .staticImageReference(collection: collection), source)
        }
    }

    func testMissingSourcesNeverFallBackToExternalProxy() throws {
        for chain in ["ethereum", "solana", "tezos"] {
            for hasMid in [true, false] {
                let collection = try collection([
                    "chain": chain,
                    "hasMid": hasMid,
                    "standardThumbsPathsAvailable": true,
                ])
                XCTAssertNil(WidgetTokenItem(id: "123000007", urlSuffix: nil)
                    .staticImageReference(collection: collection))
            }
        }
    }

    func testExternalAssetsAreRejected() throws {
        for hasMid in [true, false] {
            let collection = try collection([
                "urlPrefix": "",
                "hasMid": hasMid,
                "standardThumbsPathsAvailable": true,
            ])
            for source in [
                "https://media.example.com/0007.png",
                "http://cdn.lil.org/0007.png",
                "https://cdn.lil.org.example.com/0007.png",
            ] {
                XCTAssertNil(WidgetTokenItem(id: "token", urlSuffix: source)
                    .staticImageReference(collection: collection))
            }
        }
    }

    func testCompactPayloadRetainsIDsWhenTemplateUsesIndex() throws {
        let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: Data("""
            {"version":2,"count":2,"ids":["token-a","token-b"],"urlTemplate":{"value":"index1","suffix":".gif"}}
            """.utf8))
        let collection = try collection(["standardThumbsPathsAvailable": true])
        let items = (0..<payload.count).map { payload.item(at: $0) }
        XCTAssertEqual(items.map(\.id), ["token-a", "token-b"])
        XCTAssertEqual(items.map(\.urlSuffix), ["1.gif", "2.gif"])
        let references = items.compactMap { $0.staticImageReference(collection: collection) }
        XCTAssertEqual(references.map(\.tokenId), ["token-a", "token-b"])
        XCTAssertEqual(references.map(\.url.absoluteString), [
            "https://cdn.lil.org/artwork/mid/1.webp",
            "https://cdn.lil.org/artwork/mid/2.webp",
        ])
    }

    func testCompactPayloadPreservesPaddedExplicitFilename() throws {
        let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: Data("""
            {"version":2,"count":1,"firstId":"1000000","urlSuffix":["0007.png"]}
            """.utf8))
        let collection = try collection(["standardThumbsPathsAvailable": true])
        XCTAssertEqual(payload.count, 1)
        let reference = try XCTUnwrap(payload.item(at: 0).staticImageReference(collection: collection))
        XCTAssertEqual(reference.tokenId, "1000000")
        XCTAssertEqual(reference.url.absoluteString, "https://cdn.lil.org/artwork/mid/0007.webp")
    }

    func testGenerativeMidUsesManifestPositionsAndPreservesTokenIDs() throws {
        let collection = try collection([
            "internal_slug": "generative_art",
            "script": ["kind": "p5js100"],
        ])
        let cases: [(String, [String])] = [
            (#"{"version":2,"count":2,"firstId":"123000007"}"#, ["123000007", "123000008"]),
            (#"{"version":2,"count":2,"ids":["mint-b","mint-a"],"urlSuffix":[null,null]}"#, ["mint-b", "mint-a"]),
        ]
        for (json, ids) in cases {
            let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: Data(json.utf8))
            let items = (0..<payload.count).map { payload.item(at: $0) }
            let references = items.compactMap { $0.staticImageReference(collection: collection) }
            XCTAssertEqual(items.map(\.sourceIndex), [0, 1])
            XCTAssertEqual(references.map(\.tokenId), ids)
            XCTAssertEqual(references.map(\.url.absoluteString), [
                "https://cdn.lil.org/player/generative_art/mid/0.webp",
                "https://cdn.lil.org/player/generative_art/mid/1.webp",
            ])
        }
    }

    func testGenerativeMidPreservesExplicitSourcesAndDoesNotReplaceFailures() throws {
        let collection = try collection([
            "urlPrefix": "",
            "internal_slug": "generative_art",
            "script": ["kind": "js"],
            "standardThumbsPathsAvailable": true,
        ])
        let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: Data("""
            {"version":2,"count":3,"ids":["explicit","invalid","generated"],
            "urlSuffix":["https://cdn.lil.org/artwork/0007.png","file:///0008.png",null]}
            """.utf8))
        XCTAssertNil(payload.item(at: 1).staticImageReference(collection: collection))
        let references = (0..<payload.count).compactMap {
            payload.item(at: $0).staticImageReference(collection: collection)
        }
        XCTAssertEqual(references.map(\.tokenId), ["explicit", "generated"])
        XCTAssertEqual(references.map(\.url.absoluteString), [
            "https://cdn.lil.org/artwork/mid/0007.webp",
            "https://cdn.lil.org/player/generative_art/mid/2.webp",
        ])
    }

    func testGenerativeMidRequiresValidSlugAndSourceIndexWithoutProxyFallback() throws {
        let fields: [String: Any] = [
            "chain": "ethereum",
            "internal_slug": "generative_art",
            "script": ["kind": "js"],
            "standardThumbsPathsAvailable": true,
        ]
        let collection = try collection(fields)
        for index: Int? in [nil, -1] {
            XCTAssertNil(WidgetTokenItem(id: "123000007", urlSuffix: nil, sourceIndex: index)
                .staticImageReference(collection: collection))
        }
        let invalidSlugs: [Any] = [
            NSNull(), "", "../artwork", "UPPERCASE", "art-work", "_artwork", "art__work",
            String(repeating: "a", count: 121),
        ]
        for slug in invalidSlugs {
            var invalidFields = fields
            invalidFields["internal_slug"] = slug
            XCTAssertNil(WidgetTokenItem(id: "123000007", urlSuffix: nil, sourceIndex: 0)
                .staticImageReference(collection: try self.collection(invalidFields)))
        }
    }

    func testMissingEmptyAndNativeScriptsDoNotSynthesizeSources() throws {
        let scripts: [Any] = [NSNull(), ["kind": ""], ["kind": "native.card-nft-2"]]
        let token = WidgetTokenItem(id: "123000007", urlSuffix: nil, sourceIndex: 0)
        for script in scripts {
            var fields: [String: Any] = [
                "address": "0xcontract",
                "chain": "ethereum",
                "internal_slug": "generative_art",
                "script": script,
            ]
            XCTAssertNil(token.staticImageReference(collection: try collection(fields)))
            fields["standardThumbsPathsAvailable"] = true
            XCTAssertNil(token.staticImageReference(collection: try collection(fields)))
        }
    }

    func testGenerativeCollectionWithoutMidKeepsOriginalStaticSources() throws {
        let collection = try collection([
            "address": "0xcontract",
            "chain": "ethereum",
            "internal_slug": "generative_art",
            "script": ["kind": "js"],
            "hasMid": false,
        ])
        XCTAssertNil(WidgetTokenItem(id: "123000007", urlSuffix: nil, sourceIndex: 0)
            .staticImageReference(collection: collection))
        XCTAssertEqual(
            WidgetTokenItem(id: "123000007", urlSuffix: "0007.png", sourceIndex: 0)
                .staticImageReference(collection: collection)?.url.absoluteString,
            "https://cdn.lil.org/artwork/0007.png"
        )
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
            "urlPrefix": "https://cdn.lil.org/artwork/",
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
