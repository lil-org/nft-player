import Foundation
import XCTest
@testable import nft_player_ios

extension Array where Element == BundledTokens.Item {
    nonisolated func resolvingAspectRatios(default aspectRatio: AspectRatio?) -> Self {
        map { $0.resolvingAspectRatio(default: aspectRatio) }
    }
}

nonisolated final class ArtBlocksCatalogTests: XCTestCase {}

@MainActor
extension ArtBlocksCatalogTests {
    private var tokenFixture: Data {
        Data("""
        {
          "version": 2,
          "count": 5,
          "ids": ["legacy", "extension", "named-hash", "named-extension", "hash-only"],
          "urlSuffix": ["legacy.png", "extension.JPG", "named.png", "named.webp", "art.png"],
          "name": [null, null, "Named artwork", "Extension artwork", null],
          "hash": [null, null, "0xabc", null, "0xdef"],
          "aspectRatio": [null, null, [16, 9], null, null]
        }
        """.utf8)
    }

    private func tokenData(items: [[String: Any]]) throws -> Data {
        var payload: [String: Any] = [
            "version": 2,
            "count": items.count,
            "ids": try items.map { try XCTUnwrap($0["id"] as? String) }
        ]
        for key in Set(items.flatMap(\.keys)).subtracting(["id"]) {
            payload[key] = items.map { $0[key] ?? NSNull() }
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func tokenData(rows: String) throws -> Data {
        let items = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rows.utf8)) as? [[String: Any]])
        return try tokenData(items: items)
    }

    private func collectionFixture(metadata: [String: Any] = [:]) throws -> SuggestedItem {
        var payload: [String: Any] = [
            "name": "Fixture", "address": "0xfixture", "chainId": 1,
            "chain": "ethereum", "tokenCount": 5, "artists": []
        ]
        payload.merge(metadata) { _, value in value }
        return try JSONDecoder().decode(SuggestedItem.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    func testBundledTokensPreserveNamesHashesSuffixesAndAspectRatiosAfterRoundTrip() throws {
        let collection = try collectionFixture(metadata: ["urlPrefix": "https://example.com/", "aspectRatio": [3, 4]])
        let tokens = try BundledTokens(data: tokenFixture)
        XCTAssertEqual(tokens.items.map(\.id), ["legacy", "extension", "named-hash", "named-extension", "hash-only"])
        XCTAssertEqual(tokens.items.map(\.urlSuffix), [
            "legacy.png", "extension.JPG", "named.png", "named.webp", "art.png"
        ])
        XCTAssertEqual(tokens.items.map(\.name), [nil, nil, "Named artwork", "Extension artwork", nil])
        XCTAssertEqual(tokens.items.map(\.hash), [nil, nil, "0xabc", nil, "0xdef"])
        XCTAssertEqual(tokens.items[2].aspectRatio, AspectRatio(width: 16, height: 9))
        XCTAssertNil(tokens.items[0].aspectRatio)
        XCTAssertEqual(tokens.items[0].resolvingAspectRatio(default: collection.aspectRatio).aspectRatio, AspectRatio(width: 3, height: 4))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(tokens)
        let restored = try JSONDecoder().decode(BundledTokens.self, from: encoded)
        XCTAssertEqual(restored.items.map(\.urlSuffix), tokens.items.map(\.urlSuffix))
        XCTAssertEqual(restored.items.map(\.name), tokens.items.map(\.name))
        XCTAssertEqual(restored.items.map(\.hash), tokens.items.map(\.hash))
        XCTAssertEqual(restored.items.map(\.aspectRatio), tokens.items.map(\.aspectRatio))
        XCTAssertEqual(try encoder.encode(restored), encoded)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["version", "count", "ids", "name", "hash", "urlSuffix", "aspectRatio"])
        XCTAssertEqual(payload["version"] as? Int, 2)
        XCTAssertEqual(payload["count"] as? Int, 5)
        XCTAssertEqual((payload["urlSuffix"] as? [String])?.first, "legacy.png")
        let ratios = try XCTUnwrap(payload["aspectRatio"] as? [Any])
        XCTAssertTrue(ratios[0] is NSNull)
        XCTAssertEqual(ratios[2] as? [Int], [16, 9])
    }

    func testIndividualTokenRoundTripPreservesSuffixAndRatio() throws {
        let tokens = try BundledTokens(data: tokenFixture)
        for index in [0, 2] {
            let token = tokens.items[index].resolvingAspectRatio(default: AspectRatio(width: 3, height: 4))
            let restored = try JSONDecoder().decode(BundledTokens.Item.self, from: JSONEncoder().encode(token))
            XCTAssertEqual(restored.id, token.id)
            XCTAssertEqual(restored.name, token.name)
            XCTAssertEqual(restored.urlSuffix, token.urlSuffix)
            XCTAssertEqual(restored.aspectRatio, token.aspectRatio)
            XCTAssertEqual(restored.hash, token.hash)
        }
        XCTAssertNil(tokens.items[0].aspectRatio)
    }

    func testDownloadableTokensPreserveNamesExtensionsAndAspectRatios() throws {
        let collection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collectionFixture(
            metadata: ["urlPrefix": "https://example.com/", "aspectRatio": [3, 4]]
        )))
        let tokens = try DownloadableCollectionTokensPayload(data: tokenFixture)
        XCTAssertEqual(tokens.items.map(\.id), ["legacy", "extension", "named-hash", "named-extension", "hash-only"])
        XCTAssertEqual(tokens.items.map(\.name), [nil, nil, "Named artwork", "Extension artwork", nil])
        XCTAssertEqual(tokens.items.map { $0.resolvedFileExtension(collection: collection) }, ["png", "jpg", "png", "webp", "png"])
        XCTAssertEqual(tokens.items[2].resolvedURLString(collection: collection), "https://example.com/named.png")
        XCTAssertEqual(tokens.items[4].resolvedURLString(collection: collection), "https://example.com/art.png")
        XCTAssertEqual(tokens.items[2].aspectRatio, AspectRatio(width: 16, height: 9))
        XCTAssertNil(tokens.items[0].aspectRatio)
        XCTAssertEqual(tokens.items[0].resolvedAspectRatio(collection: collection), AspectRatio(width: 3, height: 4))
    }

    func testDownloadableMediaExtensionsUseURLPathsThenFirstQueryHint() throws {
        let collection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collectionFixture(
            metadata: ["urlPrefix": "https://example.com/"]
        )))
        let cases: [(suffix: String, expected: String?)] = [
            ("1.SVG?ext=png#frame", "svg"),
            ("2?ext=%20.HTML%20", "html"),
            ("3?ext=PNG#preview", "png"),
            ("4?format=png", nil),
            ("5?ext=", nil),
            ("6.webp", "webp"),
            ("7?ext=jpg&ext=png", "jpg"),
            ("8?ext=&ext=png", nil),
            ("9?ext&ext=png", nil),
            ("10#ext=png", nil),
            ("11?next=image.png", nil),
            ("12.txt?ext=png", "txt"),
            ("13?ext=unknown", "unknown"),
            ("14?ext=%20.%20", nil),
            ("15?EXT=png", nil),
            ("16", nil)
        ]
        let data = try tokenData(items: cases.enumerated().map {
            ["id": String($0.offset), "urlSuffix": $0.element.suffix]
        })
        let payload = try DownloadableCollectionTokensPayload(data: data)
        for (token, entry) in zip(payload.items, cases) {
            XCTAssertEqual(token.resolvedFileExtension(collection: collection), entry.expected, entry.suffix)
        }
    }

    func testRemovedTokenFileExtensionsAreIgnoredAndNotEncoded() throws {
        let collection = try collectionFixture(metadata: ["urlPrefix": "https://example.com/"])
        let downloadableCollection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collection))
        let data = try tokenData(rows: """
        [
            {"id":"1","urlSuffix":"extensionless","fileExtension":"html"},
            {"id":"2","urlSuffix":"art.JPG","fileExtension":"webp"},
            {"id":"3","urlSuffix":"art?ext=html","fileExtension":"png"}
        ]
        """)
        let bundled = try BundledTokens(data: data)
        let downloadable = try DownloadableCollectionTokensPayload(data: data)
        XCTAssertEqual(
            downloadable.items.map { $0.resolvedFileExtension(collection: downloadableCollection) },
            [nil, "jpg", "html"]
        )
        for encoded in [try JSONEncoder().encode(bundled.items), try JSONEncoder().encode(downloadable.items)] {
            let items = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
            for item in items {
                XCTAssertEqual(Set(item.keys), ["id", "urlSuffix"])
            }
        }
    }

    func testRemovedTokenMetadataIsIgnoredAndNotEncoded() throws {
        let data = Data(#"{"version":2,"count":1,"firstId":"1","urlSuffix":["https://example.com/1"],"isComplete":false,"defaultFileExtension":"html","urlPrefix":"https://ignored.example/","hasMid":false}"#.utf8)
        let bundled = try JSONDecoder().decode(BundledTokens.self, from: data)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bundled)) as? [String: Any])
        XCTAssertEqual(Set(encoded.keys), ["version", "count", "ids", "urlSuffix"])
        XCTAssertNil(bundled.items.first?.aspectRatio)

        let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == "terraforms" })
        let collection = try XCTUnwrap(DownloadableCollectionIndexItem(item: item))
        let downloadable = try JSONDecoder().decode(DownloadableCollectionTokensPayload.self, from: data)
        XCTAssertNil(try XCTUnwrap(downloadable.items.first).resolvedFileExtension(collection: collection))
    }

    func testTerraformsURLHintsPreserveHTMLMediaAndThumbnails() throws {
        let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == "terraforms" })
        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
        XCTAssertEqual(tokens.items.count, 9844)
        XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: item.id), 9844)

        for (index, token) in tokens.items.resolvingAspectRatios(default: item.aspectRatio).enumerated() {
            XCTAssertEqual(token.urlSuffix, "\(token.id)?ext=html")
            let descriptor = try XCTUnwrap(CollectionCatalog.downloadableMediaDescriptor(specificCollectionId: item.id, tokenIndex: index))
            guard case let .html(url, fileExtension) = descriptor.media else {
                XCTFail("Expected HTML for Terraforms token \(token.id)")
                continue
            }
            XCTAssertEqual(descriptor.tokenId, token.id)
            XCTAssertEqual(url.absoluteString, "https://tokens.mathcastles.xyz/terraforms/token-html/\(token.id)?ext=html")
            XCTAssertEqual(fileExtension, "html")
            let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
            XCTAssertEqual(sources.thumbnailDescriptor.url.absoluteString, "https://cdn.lil.org/player/terraforms/thumbs/\(token.id).webp")
        }
    }

    func testRawTokenRoundTripPreservesSuffixesAndOnlyItemOverrides() throws {
        let tokens = try JSONDecoder().decode(BundledTokens.self, from: tokenFixture)
        let encoded = try JSONEncoder().encode(tokens)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["version", "count", "ids", "name", "hash", "urlSuffix", "aspectRatio"])
        XCTAssertEqual(payload["version"] as? Int, 2)
        XCTAssertEqual(payload["count"] as? Int, 5)
        XCTAssertEqual((payload["urlSuffix"] as? [String])?.first, "legacy.png")
        let ratios = try XCTUnwrap(payload["aspectRatio"] as? [Any])
        XCTAssertTrue(ratios[0] is NSNull)
        XCTAssertEqual(ratios[2] as? [Int], [16, 9])
    }

    func testTokensPreserveFullURLsWithAnEmptyOrAbsentPrefix() throws {
        let urls = ["https://example.com/art.png?size=2#preview", "https://other.example/art?ext=JPG"]
        for metadata: [String: Any] in [["urlPrefix": ""], [:]] {
            let collection = try collectionFixture(metadata: metadata)
            let downloadableCollection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collection))
            let data = try tokenData(items: [
                ["id": "1", "urlSuffix": urls[0], "hash": "0xabc"],
                ["id": "2", "urlSuffix": urls[1]]
            ])
            let bundled = try BundledTokens(data: data)
            let downloadable = try DownloadableCollectionTokensPayload(data: data)
            XCTAssertEqual(bundled.items.compactMap(\.urlSuffix), urls)
            XCTAssertEqual(downloadable.items.compactMap { $0.resolvedURLString(collection: downloadableCollection) }, urls)
            XCTAssertEqual(bundled.items[0].hash, "0xabc")
            XCTAssertEqual(downloadable.items[1].resolvedFileExtension(collection: downloadableCollection), "jpg")
        }
    }

    func testTokensIgnoreRemovedFieldsAndResolveSuffixesAndImplicitSources() throws {
        let collection = try collectionFixture(metadata: ["urlPrefix": "https://prefix.example/"])
        let downloadableCollection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collection))
        let data = try tokenData(rows: """
        [
            {"id":"a","urlSuffix":"a.png","url":"https://ignored.example/a","sh":"asset",
             "imageAspectRatio":[1,1],"referencePixelSize":[2400,3600],
             "previewImageAspectRatio":[2,3],"previewReferencePixelSize":[1200,1800],
             "previewContractParameters":{"ignored":"value"}},
            {"id":"b","url":"https://ignored.example/b","sh":"asset"},
            {"id":"c"}
        ]
        """)
        let bundled = try BundledTokens(data: data)
        let downloadable = try DownloadableCollectionTokensPayload(data: data)
        XCTAssertEqual(bundled.items.map(\.urlSuffix), ["a.png", nil, nil])
        XCTAssertEqual(downloadable.items.map { $0.resolvedURLString(collection: downloadableCollection) }, [
            "https://prefix.example/a.png",
            "https://media-proxy.artblocks.io/0xfixture/b.png",
            "https://media-proxy.artblocks.io/0xfixture/c.png"
        ])
        XCTAssertNil(bundled.items[0].contractParameters)
        XCTAssertNil(bundled.items[0].aspectRatio)
        for encoded in [try JSONEncoder().encode(bundled.items[0]), try JSONEncoder().encode(downloadable.items[0])] {
            let item = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(Set(item.keys), ["id", "urlSuffix"])
        }
        let restored = try BundledTokens(data: JSONEncoder().encode(bundled))
        XCTAssertEqual(restored.items.map(\.urlSuffix), bundled.items.map(\.urlSuffix))
    }

    func testTokensUseCollectionRatioAndPreserveItemOverrides() throws {
        let collection = try collectionFixture(metadata: ["aspectRatio": [32, 18]])
        let downloadableCollection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collection))
        let data = try tokenData(rows: #"[{"id":"a"},{"id":"b","aspectRatio":[6,8]},{"id":"c","aspectRatio":[64,36]}]"#)
        let expected = [AspectRatio(width: 16, height: 9), AspectRatio(width: 3, height: 4), AspectRatio(width: 16, height: 9)]
        let bundled = try BundledTokens(data: data)
        let downloadable = try DownloadableCollectionTokensPayload(data: data)
        XCTAssertNil(bundled.items[0].aspectRatio)
        XCTAssertNil(downloadable.items[0].aspectRatio)
        XCTAssertEqual(bundled.items.resolvingAspectRatios(default: collection.aspectRatio).compactMap(\.aspectRatio), expected)
        XCTAssertEqual(downloadable.items.compactMap { $0.resolvedAspectRatio(collection: downloadableCollection) }, expected)
        let encoded = try JSONEncoder().encode(bundled)
        let restored = try BundledTokens(data: encoded)
        XCTAssertEqual(restored.items.resolvingAspectRatios(default: collection.aspectRatio).compactMap(\.aspectRatio), expected)
        XCTAssertNil(restored.items[0].aspectRatio)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["version", "count", "ids", "aspectRatio"])
    }

    func testTokenRatiosWorkWithoutACollectionDefault() throws {
        let collection = try collectionFixture()
        let downloadableCollection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collection))
        let data = try tokenData(rows: #"[{"id":"a","aspectRatio":[4,3]},{"id":"b"}]"#)
        let bundled = try BundledTokens(data: data)
        let downloadable = try DownloadableCollectionTokensPayload(data: data)
        let expected: [AspectRatio?] = [AspectRatio(width: 4, height: 3), nil]
        XCTAssertEqual(bundled.items.map(\.aspectRatio), expected)
        XCTAssertEqual(downloadable.items.map(\.aspectRatio), expected)
        XCTAssertEqual(bundled.items.resolvingAspectRatios(default: collection.aspectRatio).map(\.aspectRatio), expected)
        XCTAssertEqual(downloadable.items.map { $0.resolvedAspectRatio(collection: downloadableCollection) }, expected)
        let encoded = try JSONEncoder().encode(bundled)
        let restored = try JSONDecoder().decode(BundledTokens.self, from: encoded)
        XCTAssertEqual(restored.items.map(\.aspectRatio), expected)
    }

    func testCollectionMetadataCanBeAbsentOrNull() throws {
        for metadata: [String: Any] in [[:], ["aspectRatio": NSNull(), "urlPrefix": NSNull(), "hasMid": NSNull()]] {
            let collection = try collectionFixture(metadata: metadata)
            let downloadableCollection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collection))
            let data = try tokenData(rows: #"[{"id":"a","aspectRatio":null,"urlSuffix":"https://example.com/a.png"}]"#)
            let bundled = try BundledTokens(data: data)
            let downloadable = try DownloadableCollectionTokensPayload(data: data)
            XCTAssertNil(try XCTUnwrap(bundled.items.first).aspectRatio)
            XCTAssertNil(try XCTUnwrap(downloadable.items.first).aspectRatio)
            XCTAssertEqual(bundled.items.first?.urlSuffix, "https://example.com/a.png")
            XCTAssertEqual(downloadable.items.first?.resolvedURLString(collection: downloadableCollection), "https://example.com/a.png")
            XCTAssertTrue(downloadableCollection.hasMid)
        }
    }

    func testDecodersRejectMalformedCollectionAndItemAspectRatios() throws {
        let invalidRatios: [Any] = [[], [1], [1, 1, 1], [0, 1], [-1, 1], [1.5, 1], ["1", "1"], "1:1", ["width": 1, "height": 1]]
        for ratio in invalidRatios {
            XCTAssertThrowsError(try collectionFixture(metadata: ["aspectRatio": ratio]))
            let data = try tokenData(items: [["id": "a", "aspectRatio": ratio]])
            XCTAssertThrowsError(try JSONDecoder().decode(BundledTokens.self, from: data))
            XCTAssertThrowsError(try JSONDecoder().decode(DownloadableCollectionTokensPayload.self, from: data))
        }
    }

    func testBothTokenDecodersRequireCompactManifests() throws {
        for json in [
            #"{"items":[["a","a.png"]]}"#,
            #"{"items":[{"id":"a","urlSuffix":"a.png"}]}"#,
            #"{"version":1,"count":1,"ids":["a"]}"#
        ] {
            let data = Data(json.utf8)
            XCTAssertThrowsError(try BundledTokens(data: data), json)
            XCTAssertThrowsError(try DownloadableCollectionTokensPayload(data: data), json)
        }
        let item = Data(#"{"id":"a","urlSuffix":"a.png"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BundledTokens.Item.self, from: item).id, "a")
        XCTAssertEqual(try JSONDecoder().decode(DownloadableTokenItem.self, from: item).urlSuffix, "a.png")
    }

    func testCompactTokenRangesAndExplicitIdentifiersPreserveExactValues() throws {
        let cases: [(json: String, ids: [String])] = [
            (#"{"version":2,"count":3,"firstId":"7"}"#, ["7", "8", "9"]),
            (#"{"version":2,"count":2,"firstId":"9223372036854775806"}"#, ["9223372036854775806", "9223372036854775807"]),
            (#"{"version":2,"count":0,"ids":[]}"#, []),
            (#"{"version":2,"count":5,"ids":["01","-1","9223372036854775808","mint-address","9"]}"#,
             ["01", "-1", "9223372036854775808", "mint-address", "9"])
        ]
        for entry in cases {
            let data = Data(entry.json.utf8)
            XCTAssertEqual(try BundledTokens(data: data).items.map(\.id), entry.ids)
            XCTAssertEqual(try DownloadableCollectionTokensPayload(data: data).items.map(\.id), entry.ids)
        }
    }

    func testCompactOptionalColumnsAndExclusionsSurviveRoundTrip() throws {
        let data = Data("""
        {"version":2,"count":3,"firstId":"0",
         "name":[null,"Second",null],"hash":["0xabc",null,"0xdef"],
         "urlSuffix":[null,"art.html",null],"aspectRatio":[null,[6,8],[16,9]],
         "contractParameters":[{"a":"1","b":"two"},null,{}],"excludedMediaIndices":[1]}
        """.utf8)
        let tokens = try BundledTokens(data: data)
        let restored = try BundledTokens(data: JSONEncoder().encode(tokens))
        for payload in [tokens, restored] {
            XCTAssertEqual(payload.items.map(\.id), ["0", "1", "2"])
            XCTAssertEqual(payload.items.map(\.name), [nil, "Second", nil])
            XCTAssertEqual(payload.items.map(\.hash), ["0xabc", nil, "0xdef"])
            XCTAssertEqual(payload.items.map(\.urlSuffix), [nil, "art.html", nil])
            XCTAssertEqual(payload.items.map(\.aspectRatio), [nil, AspectRatio(width: 3, height: 4), AspectRatio(width: 16, height: 9)])
            XCTAssertEqual(payload.items.map(\.contractParameters), [["a": "1", "b": "two"], nil, [:]])
            XCTAssertEqual(payload.excludedMediaIndices, [1])
        }
    }

    func testCompactTemplatesUseSourcePositionsBeforeDownloadableSelection() throws {
        for (value, suffixes) in [
            ("id", ["mint-a.png", "mint-b.png", "mint-c.png"]),
            ("index0", ["0.png", "1.png", "2.png"]),
            ("index1", ["1.png", "2.png", "3.png"])
        ] {
            let data = try JSONSerialization.data(withJSONObject: [
                "version": 2, "count": 3, "ids": ["mint-a", "mint-b", "mint-c"],
                "urlTemplate": ["value": value, "suffix": ".png"], "excludedMediaIndices": [0, 2]
            ])
            XCTAssertEqual(try BundledTokens(data: data).items.map(\.urlSuffix), suffixes)
            let downloadable = try DownloadableCollectionTokensPayload(data: data)
            XCTAssertEqual(downloadable.items.map(\.urlSuffix), suffixes)
            XCTAssertEqual(downloadable.downloadableItems.map(\.id), ["mint-b"])
            XCTAssertEqual(downloadable.downloadableItems.map(\.urlSuffix), [suffixes[1]])
        }
    }

    func testCompactDecodersRejectMalformedRepresentations() throws {
        let invalid: [String] = [
            #"{"version":3,"count":1,"ids":["0"]}"#,
            #"{"version":2,"count":-1,"ids":[]}"#,
            #"{"version":2,"count":1.5,"firstId":"0"}"#,
            #"{"version":2,"count":1}"#,
            #"{"version":2,"count":1,"firstId":"0","ids":["0"]}"#,
            #"{"version":2,"count":1,"firstId":0}"#,
            #"{"version":2,"count":1,"firstId":"-1"}"#,
            #"{"version":2,"count":1,"firstId":"01"}"#,
            #"{"version":2,"count":1,"firstId":"+1"}"#,
            #"{"version":2,"count":1,"firstId":"9223372036854775808"}"#,
            #"{"version":2,"count":2,"firstId":"9223372036854775807"}"#,
            #"{"version":2,"count":2,"ids":["0"]}"#,
            #"{"version":2,"count":1,"ids":[0]}"#,
            #"{"version":2,"count":1,"ids":[null]}"#,
            #"{"version":2,"count":1,"ids":[""]}"#,
            #"{"version":2,"count":1,"ids":["0"],"items":[{"id":"0"}]}"#,
            #"{"version":2,"count":1,"ids":["0"],"name":[]}"#,
            #"{"version":2,"count":1,"ids":["0"],"hash":[null,null]}"#,
            #"{"version":2,"count":1,"ids":["0"],"contractParameters":[]}"#,
            #"{"version":2,"count":1,"ids":["0"],"urlSuffix":["a","b"]}"#,
            #"{"version":2,"count":1,"ids":["0"],"aspectRatio":[]}"#,
            #"{"version":2,"count":1,"ids":["0"],"urlTemplate":{"value":"id","suffix":".png"},"urlSuffix":["0.png"]}"#,
            #"{"version":2,"count":1,"ids":["0"],"urlTemplate":{"value":"index2","suffix":".png"}}"#,
            #"{"version":2,"count":1,"ids":["0"],"urlTemplate":{"value":"id"}}"#,
            #"{"version":2,"count":1,"ids":["0"],"excludedMediaIndices":[-1]}"#,
            #"{"version":2,"count":1,"ids":["0"],"excludedMediaIndices":[1]}"#,
            #"{"version":2,"count":2,"firstId":"0","excludedMediaIndices":[0,0]}"#,
            #"{"version":2,"count":2,"firstId":"0","excludedMediaIndices":[1,0]}"#
        ]
        for json in invalid {
            let data = Data(json.utf8)
            XCTAssertThrowsError(try BundledTokens(data: data), json)
            XCTAssertThrowsError(try DownloadableCollectionTokensPayload(data: data), json)
        }
    }

    func testDownloadableSelectionMatchesMediaResolutionAndPreservesDuplicates() throws {
        let collection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collectionFixture(
            metadata: ["urlPrefix": "https://example.com/"]
        )))
        let cases: [(suffixes: [String], exclusions: [Int])] = [
            (["a.png", "b?ext=html", "c.svg"], []),
            (["a.txt", "b", "c?ext="], [0, 1, 2]),
            (["a.txt", "b.png", "c?ext=&ext=png", "d?ext=%20.HTML%20", "e.SVG?ext=jpg"], [0, 2])
        ]
        for entry in cases {
            let ids = entry.suffixes.indices.map { $0 < 3 ? "duplicate" : String($0) }
            let data = try JSONSerialization.data(withJSONObject: [
                "version": 2, "count": ids.count, "ids": ids,
                "urlSuffix": entry.suffixes, "excludedMediaIndices": entry.exclusions
            ])
            let payload = try DownloadableCollectionTokensPayload(data: data)
            let accepted = payload.items.filter { $0.resolvedMedia(collection: collection) != nil }
            XCTAssertEqual(payload.downloadableItems, accepted)
            XCTAssertEqual(payload.items.count, ids.count)
            if entry.exclusions == [0, 2] {
                XCTAssertEqual(payload.downloadableItems.map(\.id), ["duplicate", "3", "4"])
                XCTAssertEqual(payload.downloadableItems.first?.urlSuffix, "b.png")
            }
        }
    }

    func testDownloadableSelectionDoesNotResolveMediaUntilRequested() throws {
        let data = Data(#"{"version":2,"count":2,"firstId":"0","urlSuffix":["art.txt","missing"]}"#.utf8)
        let payload = try DownloadableCollectionTokensPayload(data: data)
        XCTAssertEqual(payload.downloadableItems, payload.items)
        let collection = try XCTUnwrap(DownloadableCollectionIndexItem(item: collectionFixture(
            metadata: ["urlPrefix": "https://example.com/"]
        )))
        XCTAssertTrue(payload.downloadableItems.allSatisfy { $0.resolvedMedia(collection: collection) == nil })
    }

    func testBundledTokenCountsUseMetadataWithoutLoadingAndFallBackWhenUnknown() {
        var loadCount = 0
        let load = {
            loadCount += 1
            return 7
        }
        XCTAssertEqual(BundledTokenMetadata.count(12, loading: load), 12)
        XCTAssertEqual(BundledTokenMetadata.count(0, loading: load), 0)
        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(BundledTokenMetadata.count(nil, loading: load), 7)
        XCTAssertEqual(BundledTokenMetadata.count(-1, loading: load), 7)
        XCTAssertEqual(loadCount, 2)
    }

    func testBundledUniformProfilesAvoidLoadingAndOtherProfilesRemainLazy() {
        let ratio = AspectRatio(width: 3, height: 4)
        let variable = AspectRatioProfile.variable([ratio, AspectRatio(width: 1, height: 1)])
        var loadCount = 0
        let load: () -> AspectRatioProfile? = {
            loadCount += 1
            return variable
        }
        XCTAssertEqual(BundledTokenMetadata.aspectRatioProfile(
            count: 2, isUniform: true, defaultAspectRatio: ratio, loading: load
        ), .uniform(ratio))
        for marker: Bool? in [nil, false, true] {
            XCTAssertNil(BundledTokenMetadata.aspectRatioProfile(
                count: 0, isUniform: marker, defaultAspectRatio: ratio, loading: load
            ))
        }
        XCTAssertEqual(loadCount, 0)
        let unknownCases: [(Int?, Bool?, AspectRatio?)] = [
            (nil, true, ratio), (-1, true, ratio),
            (2, nil, ratio), (2, false, ratio), (2, true, nil)
        ]
        for (count, marker, defaultRatio) in unknownCases {
            XCTAssertEqual(BundledTokenMetadata.aspectRatioProfile(
                count: count, isUniform: marker, defaultAspectRatio: defaultRatio, loading: load
            ), variable)
        }
        XCTAssertEqual(loadCount, unknownCases.count)
        XCTAssertNil(BundledTokenMetadata.aspectRatioProfile(
            count: nil, isUniform: nil, defaultAspectRatio: nil, loading: { nil }
        ))
    }

    func testBundledTokenMetadataMatchesEveryResourceAndAcceptedDownloadableRecord() throws {
        for item in SuggestedItemsService.allItems {
            guard let url = SuggestedItemsService.bundledTokensURL(collectionId: item.id) else {
                XCTAssertEqual(item.internalSlug, "card_nft_2")
                XCTAssertNil(item.bundledTokenCount)
                XCTAssertNil(item.hasUniformAspectRatio)
                continue
            }
            let data = try Data(contentsOf: url)
            let payload = try BundledTokens(data: data)
            XCTAssertEqual(item.bundledTokenCount, payload.items.count, item.name)
            var profileBuilder = AspectRatioProfileBuilder()
            for token in payload.items {
                profileBuilder.append(token.resolvingAspectRatio(default: item.aspectRatio).aspectRatio)
            }
            let expectedUniform: Bool
            if case let .uniform(ratio)? = profileBuilder.profile {
                expectedUniform = ratio == item.aspectRatio
            } else {
                expectedUniform = false
            }
            XCTAssertEqual(item.hasUniformAspectRatio, expectedUniform, item.name)
            if let collection = DownloadableCollectionIndexItem(item: item) {
                let downloadable = try DownloadableCollectionTokensPayload(data: data)
                let accepted = downloadable.items.filter { $0.resolvedMedia(collection: collection) != nil }
                XCTAssertEqual(downloadable.downloadableItems, accepted, item.name)
                XCTAssertEqual(item.tokenCount, accepted.count, item.name)
            }
        }
    }

    func testBundledMetadataPreservesGenerativeAndNativeRouting() throws {
        let downloadable = try XCTUnwrap(SuggestedItemsService.item(resourceName: "terraforms"))
        XCTAssertGreaterThan(try XCTUnwrap(downloadable.bundledTokenCount), 0)
        for id in [downloadable.id, "unknown_collection"] {
            XCTAssertFalse(TokenGenerator.canGenerate(id: id))
            XCTAssertEqual(TokenGenerator.tokenCount(specificCollectionId: id), 0)
            XCTAssertNil(TokenGenerator.aspectRatioProfile(specificCollectionId: id))
        }
        for slug in ["fidenza", "ringers", "poncho_drifella", "card_nft_2"] {
            let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == slug })
            XCTAssertNil(item.tokenCount, slug)
            XCTAssertNil(DownloadableCollectionIndexItem(item: item), slug)
            XCTAssertFalse(CollectionCatalog.isDownloadableCollection(specificCollectionId: item.id), slug)
            if slug == "card_nft_2" {
                XCTAssertEqual(TokenGenerator.tokenCount(specificCollectionId: item.id), CardNft2CardMetadata.tokenCount)
            } else {
                XCTAssertNotNil(item.bundledTokenCount, slug)
                XCTAssertEqual(TokenGenerator.tokenCount(specificCollectionId: item.id), item.bundledTokenCount)
            }
        }
    }

    func testMixedProfilesAndResolvedTokensPreserveCollectionDefaultsAndOverrides() throws {
        for slug in ["focus", "degenerative"] {
            let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == slug })
            let raw = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
            let resolved = raw.resolvingAspectRatios(default: item.aspectRatio)
            XCTAssertEqual(item.hasUniformAspectRatio, false, slug)
            XCTAssertEqual(TokenGenerator.aspectRatioProfile(specificCollectionId: item.id), .variable(resolved.compactMap(\.aspectRatio)))
            let inheritedIndex = try XCTUnwrap(raw.firstIndex { $0.aspectRatio == nil })
            let overrideIndex = try XCTUnwrap(raw.firstIndex { $0.aspectRatio != nil })
            for index in [inheritedIndex, overrideIndex] {
                XCTAssertEqual(TokenGenerator.bundledWebGenerativeToken(specificCollectionId: item.id, tokenIndex: index)?.aspectRatio, resolved[index].aspectRatio)
            }
            XCTAssertNil(raw[inheritedIndex].aspectRatio)
        }
    }

    func testBundledResourcesAndCoverNamesUseSlugsWithoutChangingCollectionIdentity() throws {
        var tokenCount = 0
        var scriptCount = 0
        var sourceIDs = Set<String>()
        var sourceCounts: [String: Int] = [:]
        for item in SuggestedItemsService.allItems {
            let slug = try XCTUnwrap(item.internalSlug, item.name)
            XCTAssertEqual(item.bundledResourceName, slug)
            XCTAssertEqual(SuggestedItemsService.item(resourceName: slug), item)
            XCTAssertEqual(SuggestedItemsService.item(id: item.id), item)
            XCTAssertEqual(CollectionCatalogItem(item: item).id, item.id)
            XCTAssertEqual(CollectionCatalogItem(item: item).coverAssetName, slug)
            XCTAssertFalse(slug.isEmpty, item.name)
            XCTAssertFalse(slug.contains("/"), item.name)

            if item.internalSlug == "card_nft_2" {
                XCTAssertNil(SuggestedItemsService.bundledTokensURL(collectionId: item.id))
            } else {
                let url = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: item.id), item.name)
                XCTAssertEqual(url.lastPathComponent, slug + ".json")
                XCTAssertNotNil(SuggestedItemsService.bundledTokens(collectionId: item.id), item.name)
                tokenCount += 1
            }

            if let metadata = item.script {
                let script = try XCTUnwrap(Script(item: item, value: ""), item.name)
                XCTAssertEqual(script.id, item.id, item.name)
                XCTAssertEqual(script.address, item.address, item.name)
                XCTAssertEqual(script.name, item.name, item.name)
                XCTAssertEqual(script.chain, item.chain, item.name)
                XCTAssertEqual(script.chainId, item.chainId, item.name)
                XCTAssertEqual(script.metadata, metadata, item.name)
                XCTAssertTrue(TokenGenerator.canGenerate(id: item.id), item.name)
                if metadata.kind.isNativeRenderer {
                    XCTAssertNil(item.scriptDependency, item.name)
                    XCTAssertTrue(script.value.isEmpty, item.name)
                } else {
                    let dependency = try XCTUnwrap(item.scriptDependency, item.name)
                    let fileExtension = try XCTUnwrap(metadata.kind.sourceFileExtension)
                    XCTAssertEqual(dependency.id, "script:" + slug)
                    if metadata.sourceURL == nil {
                        XCTAssertEqual(dependency.remoteURL.pathExtension, fileExtension)
                    }
                    XCTAssertGreaterThan(dependency.expectedByteCount, 0)
                    XCTAssertNotNil(dependency.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression))
                    sourceIDs.insert(dependency.id)
                    sourceCounts[fileExtension, default: 0] += 1
                }
                scriptCount += 1
            } else {
                XCTAssertNil(Script(item: item, value: ""), item.name)
                XCTAssertNil(item.scriptDependency, item.name)
                XCTAssertFalse(TokenGenerator.canGenerate(id: item.id), item.name)
            }
        }
        XCTAssertEqual(tokenCount, 528)
        XCTAssertEqual(scriptCount, 407)
        XCTAssertEqual(sourceIDs.count, 405)
        XCTAssertEqual(sourceCounts, ["js": 402, "pde": 2, "html": 1])
        let directory = SuggestedItemsService.bundle.bundleURL.appendingPathComponent("Scripts")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNil(Bundle.main.url(forResource: "ArtworkScripts", withExtension: nil))
        XCTAssertNil(SuggestedItemsService.bundledTokensURL(collectionId: "unknown_collection"))
        XCTAssertNil(SuggestedItemsService.scriptItem(collectionId: "unknown_collection"))
    }

    func testBundledResourcesPreserveLowercaseIdentifierFallback() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "archetype"))
        XCTAssertEqual(item.id, item.id.lowercased())
        let uppercaseId = item.id.uppercased()
        XCTAssertNotEqual(uppercaseId, item.id)
        XCTAssertNil(SuggestedItemsService.item(id: uppercaseId))

        let tokensURL = try XCTUnwrap(SuggestedItemsService.bundledTokensURL(collectionId: item.id))
        XCTAssertEqual(SuggestedItemsService.bundledTokensURL(collectionId: uppercaseId), tokensURL)
        for identifier in [item.id, uppercaseId, item.bundledResourceName, item.bundledResourceName.uppercased()] {
            let resolvedItem = try XCTUnwrap(SuggestedItemsService.scriptItem(collectionId: identifier))
            XCTAssertEqual(resolvedItem, item)
            XCTAssertEqual(resolvedItem.scriptDependency, item.scriptDependency)
        }

        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
        let uppercaseTokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: uppercaseId))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(uppercaseTokens), try encoder.encode(tokens))

        let solana = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.chain == .solana })
        let lowercasedSolanaId = solana.id.lowercased()
        XCTAssertNotEqual(lowercasedSolanaId, solana.id)
        XCTAssertNotNil(SuggestedItemsService.bundledTokensURL(collectionId: solana.id))
        XCTAssertNil(SuggestedItemsService.item(id: lowercasedSolanaId))
        XCTAssertNil(SuggestedItemsService.bundledTokensURL(collectionId: lowercasedSolanaId))
    }

    func testNativeGenerationUsesCatalogMetadataWithoutSourceFiles() throws {
        for slug in ["card_nft_2", "poncho_drifella"] {
            let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: slug))
            let script = try XCTUnwrap(Script(item: item, value: ""))
            XCTAssertNil(item.scriptDependency)
            XCTAssertTrue(script.kind.isNativeRenderer)
            XCTAssertTrue(script.value.isEmpty)
            XCTAssertTrue(TokenGenerator.canGenerate(id: item.id))
            let token = try XCTUnwrap(TokenGenerator.generateToken(specificCollectionId: item.id, tokenIndex: 0))
            XCTAssertEqual(token.fullCollectionId, item.id)
            XCTAssertEqual(token.renderKind, script.kind.generatedTokenRenderKind)
        }
    }

    func testSourceFormatsAndRendererMetadataRoundTripThroughTheCatalog() throws {
        for (slug, kind, fileExtension) in [
            ("hypertype", Script.Kind.svg, "js"),
            ("genesis", .processingjs146, "pde"),
            ("construction_token", .processingjs146, "pde"),
            ("spiroflakes", .html, "html")
        ] {
            let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: slug))
            let script = try JavaScriptLibraryFixtures.script(collectionId: item.id)
            XCTAssertEqual(script.kind, kind)
            XCTAssertEqual(script.kind.sourceFileExtension, fileExtension)
            XCTAssertFalse(script.value.isEmpty)
        }
        for item in SuggestedItemsService.allItems where item.script != nil {
            let restored = try JSONDecoder().decode(SuggestedItem.self, from: JSONEncoder().encode(item))
            XCTAssertEqual(restored.script, item.script, item.name)
        }
    }

    func testArtworkSourceDescriptorsRequirePinsAndValidateExplicitURLs() throws {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: "archetype"))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        let metadata = try XCTUnwrap(encoded["script"] as? [String: Any])
        for (key, value) in [
            ("expectedByteCount", NSNull()), ("expectedByteCount", 0),
            ("sha256", NSNull()), ("sha256", "invalid"),
            ("sourceURL", "http://example.test/source.js"),
            ("sourceURL", "https://user@example.test/source.js"),
            ("sourceURL", "https://example.test/source.js#fragment")
        ] as [(String, Any)] {
            var changed = metadata
            changed[key] = value
            var fields = encoded
            fields["script"] = changed
            let decoded = try JSONDecoder().decode(SuggestedItem.self, from: JSONSerialization.data(withJSONObject: fields))
            XCTAssertNil(decoded.scriptDependency, "\(key): \(value)")
        }
        var changed = metadata
        changed["sourceURL"] = "https://example.test/pinned-source.js"
        var fields = encoded
        fields["script"] = changed
        let decoded = try JSONDecoder().decode(SuggestedItem.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertEqual(decoded.scriptDependency?.remoteURL.absoluteString, "https://example.test/pinned-source.js")
        XCTAssertEqual(decoded.scriptDependency?.id, item.scriptDependency?.id)
        XCTAssertEqual(decoded.scriptDependency?.sha256, item.scriptDependency?.sha256)
    }

    func testResourceNameFallbackPreservesLegacyDecodingAndCoverMetadata() throws {
        let item = try XCTUnwrap(SuggestedItemsService.allItems.first)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        fields.removeValue(forKey: "internal_slug")
        fields["hasCover"] = false
        let legacy = try JSONDecoder().decode(SuggestedItem.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertNil(legacy.internalSlug)
        XCTAssertEqual(legacy.bundledResourceName, item.id)
        XCTAssertEqual(CollectionCatalogItem(item: legacy).coverAssetName, item.id)
        XCTAssertFalse(CollectionCatalogItem(item: legacy).hasCover)

        fields["internal_slug"] = ""
        let emptySlug = try JSONDecoder().decode(SuggestedItem.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertEqual(emptySlug.bundledResourceName, item.id)
    }

    private var additions: [SuggestedItem] {
        SuggestedItemsService.allItems.filter { $0.bundledDate == "2026-09-14" && $0.generativeOnly == true }
    }

    func testApprovedCollectionsHaveCoversAndBrowsersWithGenerativeOnlyPlayback() throws {
        XCTAssertEqual(SuggestedItemsService.allItems.count, 529)
        XCTAssertEqual(additions.count, 292)
        var policies = [String: Int]()
        for item in additions {
            XCTAssertFalse(item.id.contains("dev-good"), item.name)
            XCTAssertEqual(item.id, item.address + (item.abId ?? ""), item.name)
            XCTAssertEqual(item.iosOnly, true)
            XCTAssertEqual(item.hasCover, true)
            XCTAssertEqual(item.hasThumbnails, true)
            XCTAssertEqual(item.standardThumbsPathsAvailable, true)
            XCTAssertFalse(item.isDownloadableCollection)
            XCTAssertNil(item.tokenCount)
            XCTAssertFalse(item.artists.isEmpty, item.name)
            XCTAssertTrue(SuggestedItemsService.visibleItems.contains { $0.id == item.id })
            XCTAssertTrue(CollectionCatalog.allItems.contains { $0.id == item.id && $0.hasCover })
            let slug = try XCTUnwrap(item.internalSlug, item.name)
            XCTAssertEqual(CollectionCatalogItem(item: item).coverAssetName, slug, item.name)
            XCTAssertTrue(TokenGenerator.usesArtBlocksRenderer(collectionId: item.id))
            XCTAssertTrue(CollectionCatalog.canOpenCollection(specificCollectionId: item.id))
            XCTAssertFalse(CollectionCatalog.isDownloadableCollection(specificCollectionId: item.id))
            XCTAssertTrue(PlayerCollectionBrowserSupport.isAvailable(forCollectionId: item.id))
            XCTAssertTrue(CollectionCatalog.collectionBrowseMidImagesAvailable(specificCollectionId: item.id))
            let descriptor = try XCTUnwrap(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: 0))
            XCTAssertTrue(PlayerCollectionBrowserSupport.isAvailable(for: descriptor))
            XCTAssertTrue(descriptor.isStaticImage)
            XCTAssertTrue(descriptor.isCollectionBrowserThumbnail)
            let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: 0))
            XCTAssertNil(token.media)
            XCTAssertFalse(token.html.isEmpty)
            let script = try JavaScriptLibraryFixtures.script(collectionId: item.id)
            let policy = ArtBlocksRenderingStartupProfiles.startupProfile(script) == nil ? "direct" : "calibrated"
            policies[policy, default: 0] += 1
        }
        XCTAssertEqual(policies, ["direct": 213, "calibrated": 79])
        XCTAssertEqual(PlayerDisplayMode.initialMode(hasWidgetTokenInsertion: false, collectionBrowserAvailable: true), .collectionBrowser)
        XCTAssertEqual(PlayerDisplayMode.initialMode(hasWidgetTokenInsertion: true, collectionBrowserAvailable: true), .onePerPage)
    }

    func testAllMintedRecordsDecodeWithHashesAndStableNavigationIdentity() throws {
        var count = 0
        for item in additions {
            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
            XCTAssertFalse(tokens.items.isEmpty, item.name)
            XCTAssertEqual(Set(tokens.items.map(\.id)).count, tokens.items.count, item.name)
            XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: item.id), tokens.items.count)
            let projectID = try XCTUnwrap(item.abId.flatMap(Int.init))
            let slug = try XCTUnwrap(item.internalSlug)
            for (index, token) in tokens.items.resolvingAspectRatios(default: item.aspectRatio).enumerated() {
                XCTAssertEqual(token.id, String(projectID * 1_000_000 + index), item.name)
                XCTAssertNotNil(token.hash?.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression), item.name + " " + token.id)
                XCTAssertNotNil(token.aspectRatio, item.name + " " + token.id)
                XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
            }
            for index in Set([0, tokens.items.count / 2, tokens.items.count - 1]) {
                let token = tokens.items[index].resolvingAspectRatio(default: item.aspectRatio)
                XCTAssertEqual(TokenGenerator.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
                let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
                let base = "https://cdn.lil.org/player/\(slug)"
                XCTAssertEqual(sources.thumbnailDescriptor.url.absoluteString, "\(base)/thumbs/\(index).webp")
                XCTAssertEqual(sources.smallThumbnailDescriptor.url.absoluteString, "\(base)/thumbs/260/\(index).webp")
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.url.absoluteString, "\(base)/thumbs/140/\(index).webp")
                XCTAssertEqual(sources.largeDescriptor.url.absoluteString, "\(base)/mid/\(index).webp")
                for descriptor in [sources.thumbnailDescriptor, sources.smallThumbnailDescriptor, sources.largeDescriptor] {
                    XCTAssertEqual(descriptor.collectionId, item.id)
                    XCTAssertEqual(descriptor.tokenId, token.id)
                    XCTAssertEqual(descriptor.tokenIndex, index)
                    XCTAssertEqual(descriptor.aspectRatio, token.aspectRatio)
                }
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.tokenId, token.id)
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.aspectRatio, token.aspectRatio)
            }
            XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: -1))
            XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: tokens.items.count))
            count += tokens.items.count
        }
        XCTAssertEqual(count, 143_847)
    }

    func testNeighborhoodUsesPerTokenAspectRatiosForBrowsingAndPlayback() throws {
        let item = try XCTUnwrap(additions.first { $0.internalSlug == "neighborhood" })
        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
            .resolvingAspectRatios(default: item.aspectRatio)
        for (index, width, height) in [(0, 16, 9), (3, 1, 1), (7, 9, 16)] {
            let ratio = AspectRatio(width: width, height: height)
            XCTAssertEqual(tokens[index].id, String(146_000_000 + index))
            XCTAssertEqual(tokens[index].aspectRatio, ratio)
            let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
            XCTAssertEqual(sources.thumbnailDescriptor.aspectRatio, ratio)
            XCTAssertEqual(sources.smallThumbnailDescriptor.aspectRatio, ratio)
            XCTAssertEqual(sources.smallestThumbnailDescriptor?.aspectRatio, ratio)
            XCTAssertEqual(sources.largeDescriptor.aspectRatio, ratio)
            let generated = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: index))
            XCTAssertEqual(generated.id, tokens[index].id)
            XCTAssertNil(generated.media)
            XCTAssertFalse(generated.html.isEmpty)
        }
        XCTAssertEqual(TokenGenerator.aspectRatioProfile(specificCollectionId: item.id), .variable(tokens.compactMap(\.aspectRatio)))
    }

    func testDegenerativeAndAssemblyUseImageRatiosForPlayback() throws {
        for (slug, expected) in [
            ("degenerative", [AspectRatio(width: 400, height: 289), AspectRatio(width: 600, height: 437)]),
            ("assembly", [AspectRatio(width: 5, height: 6)])
        ] {
            let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == slug })
            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
            .resolvingAspectRatios(default: item.aspectRatio)
            for ratio in expected {
                let index = try XCTUnwrap(tokens.firstIndex { $0.aspectRatio == ratio })
                XCTAssertEqual(TokenGenerator.bundledWebGenerativeToken(specificCollectionId: item.id, tokenIndex: index)?.aspectRatio, ratio)
                let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
                XCTAssertEqual(sources.thumbnailDescriptor.aspectRatio, ratio)
                XCTAssertEqual(sources.largeDescriptor.aspectRatio, ratio)
            }
            if slug == "degenerative" {
                XCTAssertEqual(Set(tokens.compactMap(\.aspectRatio)).count, 32)
                XCTAssertEqual(TokenGenerator.aspectRatioProfile(specificCollectionId: item.id), .variable(tokens.compactMap(\.aspectRatio)))
            } else {
                XCTAssertEqual(TokenGenerator.aspectRatioProfile(specificCollectionId: item.id), .uniform(expected[0]))
            }
        }
    }

    func testLargeCollectionsGenerateOnlyRequestedTokensWithoutImages() throws {
        for name in ["Friendship Bracelets", "Trademark", "Flowers"] {
            let item = try XCTUnwrap(additions.first { $0.name == name })
            let count = CollectionCatalog.tokenCount(specificCollectionId: item.id)
            XCTAssertGreaterThan(count, 1_000)
            for index in [0, count / 2, count - 1] {
                let token = try XCTUnwrap(TokenGenerator.generateToken(specificCollectionId: item.id, tokenIndex: index))
                XCTAssertEqual(token.fullCollectionId, item.id)
                XCTAssertNil(token.media)
                XCTAssertFalse(token.html.isEmpty)
                XCTAssertEqual(TokenGenerator.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
            }
            XCTAssertNil(TokenGenerator.generateToken(specificCollectionId: item.id, tokenIndex: count))
            XCTAssertNil(TokenGenerator.generateToken(specificCollectionId: item.id, tokenIndex: -1))
        }
    }

    func testCatalogMetadataRoundTripsAndLegacyDefaultsRemainAvailable() throws {
        let item = try XCTUnwrap(additions.first)
        let encoder = JSONEncoder()
        let decoded = try JSONDecoder().decode(SuggestedItem.self, from: encoder.encode(item))
        XCTAssertEqual(decoded, item)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(item)) as? [String: Any])
        for key in ["bundledDate", "generativeOnly", "hasCover", "hasThumbnails", "iosOnly", "bundledTokenCount", "hasUniformAspectRatio"] { fields.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(SuggestedItem.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertNil(legacy.bundledDate)
        XCTAssertNil(legacy.generativeOnly)
        XCTAssertNil(legacy.bundledTokenCount)
        XCTAssertNil(legacy.hasUniformAspectRatio)
        XCTAssertTrue(CollectionCatalogItem(item: legacy).hasCover)
    }

    func testMiNoteCollectionsOpenWithCoversNamesAndIndividualArtworkLinks() throws {
        for (slug, count) in [("mi_note", 166), ("mi_note_3", 105)] {
            let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == slug })
            XCTAssertTrue(SuggestedItemsService.visibleItems.contains(item))
            XCTAssertTrue(CollectionCatalog.allItems.contains { $0.id == item.id && $0.hasCover })
            XCTAssertTrue(CollectionCatalog.canOpenCollection(specificCollectionId: item.id))
            XCTAssertTrue(PlayerCollectionBrowserSupport.isAvailable(forCollectionId: item.id))
            XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: item.id), count)
            XCTAssertEqual(SuggestedItemsService.artists(forCollectionId: item.id).map(\.id), ["yomme"])
            XCTAssertEqual(CollectionCatalog.collectionWebURL(specificCollectionId: item.id)?.absoluteString, item.collectionWebURL)
            XCTAssertEqual(CollectionCatalogItem(item: item).coverAssetName, slug)

            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
            .resolvingAspectRatios(default: item.aspectRatio)
            XCTAssertEqual(tokens.count, count)
            for (index, expected) in tokens.enumerated() {
                XCTAssertFalse(try XCTUnwrap(expected.name).isEmpty)
                let expectedURL = (item.urlPrefix ?? "") + (try XCTUnwrap(expected.urlSuffix))
                let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: index))
                XCTAssertEqual(token.id, expected.id)
                XCTAssertEqual(token.fullCollectionId, item.id)
                XCTAssertEqual(token.address, item.address)
                XCTAssertEqual(token.displayName, expected.name)
                XCTAssertEqual(token.media?.url.absoluteString, expectedURL)
                XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
                XCTAssertEqual(token.url?.absoluteString, "https://eth.blockscout.com/token/\(item.address)/instance/\(expected.id)?tab=metadata")

                let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
                let originalURL = try XCTUnwrap(URL(string: expectedURL))
                let stem = originalURL.deletingPathExtension().lastPathComponent
                let base = "https://cdn.lil.org/player/\(slug)"
                XCTAssertEqual(sources.thumbnailDescriptor.url.absoluteString, "\(base)/thumbs/\(stem).webp")
                XCTAssertEqual(sources.smallThumbnailDescriptor.url.absoluteString, "\(base)/thumbs/260/\(index).webp")
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.url.absoluteString, "\(base)/thumbs/140/\(index).webp")
                XCTAssertEqual(sources.largeDescriptor.url.absoluteString, "\(base)/mid/\(stem).webp")
                XCTAssertEqual(sources.thumbnailDescriptor.aspectRatio, expected.aspectRatio)
                XCTAssertNotNil(expected.aspectRatio)
            }
            XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: -1))
            XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: count))
        }
    }

    func testPreparedStaticCollectionsOpenWithCoversAndPreservedCDNMediaIdentity() throws {
        let collections = [
            ("bokeh", 300, "mpkoz"),
            ("glass", 300, "eric_de_giuli"),
            ("memory_loss", 256, "andrew_mitchell"),
            ("primavera", 70, "baret_lavida"),
            ("subtraction_reconfiguration", 100, "juan_pedro_vallejo"),
            ("talim", 99, "jonny_baho"),
            ("the_colors_that_heal", 142, "ryan_green"),
            ("twos", 64, "emily_edelman"),
            ("whispering_sands", 100, "obvious"),
            ("windwoven", 110, "radix")
        ]
        var total = 0
        for (slug, count, artist) in collections {
            let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == slug })
            XCTAssertEqual(item.chain, .ethereum)
            XCTAssertEqual(item.chainId, slug == "talim" ? 42161 : 1)
            XCTAssertEqual(item.hasCover, true)
            XCTAssertNil(item.generativeOnly)
            XCTAssertTrue(item.isDownloadableCollection)
            XCTAssertEqual(item.tokenCount, count)
            XCTAssertEqual(item.standardThumbsPathsAvailable, true)
            XCTAssertNil(item.sizedThumbsIndexOffset)
            XCTAssertNotNil(item.bundledDate?.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression))
            XCTAssertEqual(SuggestedItemsService.artists(forCollectionId: item.id).map(\.id), [artist])
            XCTAssertTrue(SuggestedItemsService.visibleItems.contains(item))
            XCTAssertTrue(CollectionCatalog.allItems.contains { $0.id == item.id && $0.hasCover })
            XCTAssertTrue(CollectionCatalog.canOpenCollection(specificCollectionId: item.id))
            XCTAssertTrue(CollectionCatalog.isDownloadableCollection(specificCollectionId: item.id))
            XCTAssertTrue(PlayerCollectionBrowserSupport.isAvailable(forCollectionId: item.id))
            XCTAssertFalse(TokenGenerator.usesArtBlocksRenderer(collectionId: item.id))
            XCTAssertTrue(CollectionCatalog.collectionBrowseMidImagesAvailable(specificCollectionId: item.id))
            XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: item.id), count)
            XCTAssertEqual(CollectionCatalogItem(item: item).coverAssetName, slug)

            let projectID = try XCTUnwrap(item.abId.flatMap(Int.init))
            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
            XCTAssertEqual(tokens.items.count, count)
            XCTAssertEqual(Set(tokens.items.map(\.id)).count, count)
            let base = "https://cdn.lil.org/player/\(slug)"
            for (index, expected) in tokens.items.resolvingAspectRatios(default: item.aspectRatio).enumerated() {
                XCTAssertEqual(expected.id, String(projectID * 1_000_000 + index))
                XCTAssertEqual((item.urlPrefix ?? "") + (try XCTUnwrap(expected.urlSuffix)), "\(base)/\(index).png")
                XCTAssertNotNil(expected.aspectRatio)
                let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: index))
                XCTAssertEqual(token.id, expected.id)
                XCTAssertEqual(token.fullCollectionId, item.id)
                XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
                let media = try XCTUnwrap(token.media)
                guard case let .staticImage(url, fileExtension) = media else {
                    XCTFail("Expected PNG artwork for \(slug)/\(index)")
                    continue
                }
                XCTAssertEqual(url.absoluteString, "\(base)/\(index).png")
                XCTAssertEqual(fileExtension, "png")
                let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
                XCTAssertEqual(sources.thumbnailDescriptor.url.absoluteString, "\(base)/thumbs/\(index).webp")
                XCTAssertEqual(sources.smallThumbnailDescriptor.url.absoluteString, "\(base)/thumbs/260/\(index).webp")
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.url.absoluteString, "\(base)/thumbs/140/\(index).webp")
                XCTAssertEqual(sources.largeDescriptor.url.absoluteString, "\(base)/mid/\(index).webp")
                XCTAssertEqual(sources.thumbnailDescriptor.aspectRatio, expected.aspectRatio)
                XCTAssertEqual(sources.largeDescriptor.aspectRatio, expected.aspectRatio)
            }
            XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: -1))
            XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: count))
            total += count
        }
        XCTAssertEqual(total, 1_541)
        for slug in ["coral_colors", "elefante"] {
            XCTAssertFalse(SuggestedItemsService.allItems.contains { $0.internalSlug == slug })
        }
    }

    func testPrimaveraPreservesMixedArtworkAspectRatios() throws {
        let item = try XCTUnwrap(SuggestedItemsService.allItems.first { $0.internalSlug == "primavera" })
        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
            .resolvingAspectRatios(default: item.aspectRatio)
        let expectations = [(0, 6, 5), (1, 9, 16), (2, 16, 9), (4, 5, 6), (15, 1, 1)]
        for (index, width, height) in expectations {
            let expected = AspectRatio(width: width, height: height)
            XCTAssertEqual(tokens[index].aspectRatio, expected)
            let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
            XCTAssertEqual(sources.thumbnailDescriptor.aspectRatio, expected)
            XCTAssertEqual(sources.smallThumbnailDescriptor.aspectRatio, expected)
            XCTAssertEqual(sources.smallestThumbnailDescriptor?.aspectRatio, expected)
            XCTAssertEqual(sources.largeDescriptor.aspectRatio, expected)
        }
        XCTAssertEqual(Set(tokens.compactMap(\.aspectRatio)).count, 5)
    }
}
