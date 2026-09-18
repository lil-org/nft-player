import Foundation
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksCatalogTests: XCTestCase {}

@MainActor
extension ArtBlocksCatalogTests {
    private var compactTokenFixture: Data {
        Data("""
        {
          "defaultFileExtension": " .PNG ",
          "urlPrefixes": ["https://example.com/"],
          "thumbnailAspectRatios": [[3, 4], [16, 9]],
          "thumbnailAspectRatioOverrides": [[2, 1]],
          "artworkAspectRatios": [[1, 1]],
          "items": [
            ["legacy", 0, "legacy.png"],
            ["extension", 0, "extension", ".JPG"],
            ["named-hash", 0, "named.png", null, {"name": "Named artwork", "hash": "0xabc"}],
            ["named-extension", 0, "named", "webp", {"name": "Extension artwork"}],
            ["absolute", -1, "https://other.example/art.png", null, {"hash": "0xdef"}]
          ]
        }
        """.utf8)
    }

    func testCompactBundledTokensPreserveNamesHashesAndAspectRatiosAfterRoundTrip() throws {
        let tokens = try JSONDecoder().decode(BundledTokens.self, from: compactTokenFixture)
        XCTAssertEqual(tokens.items.map(\.id), ["legacy", "extension", "named-hash", "named-extension", "absolute"])
        XCTAssertEqual(tokens.items.map(\.url), [
            "https://example.com/legacy.png",
            "https://example.com/extension",
            "https://example.com/named.png",
            "https://example.com/named",
            "https://other.example/art.png"
        ])
        XCTAssertEqual(tokens.items.map(\.name), [nil, nil, "Named artwork", "Extension artwork", nil])
        XCTAssertEqual(tokens.items.map(\.hash), [nil, nil, "0xabc", nil, "0xdef"])
        XCTAssertEqual(tokens.items[2].thumbnailAspectRatio, ThumbnailAspectRatio(width: 16, height: 9))
        XCTAssertEqual(tokens.items[0].thumbnailAspectRatio, ThumbnailAspectRatio(width: 3, height: 4))
        XCTAssertTrue(tokens.items.allSatisfy { $0.artworkAspectRatio == ThumbnailAspectRatio(width: 1, height: 1) })

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(tokens)
        let restored = try JSONDecoder().decode(BundledTokens.self, from: encoded)
        XCTAssertEqual(restored.items.map(\.name), tokens.items.map(\.name))
        XCTAssertEqual(restored.items.map(\.hash), tokens.items.map(\.hash))
        XCTAssertEqual(restored.items.map(\.thumbnailAspectRatio), tokens.items.map(\.thumbnailAspectRatio))
        XCTAssertEqual(try encoder.encode(restored), encoded)
    }

    func testCompactDownloadableTokensPreserveNamesExtensionsAndAspectRatios() throws {
        let tokens = try JSONDecoder().decode(DownloadableCollectionTokensPayload.self, from: compactTokenFixture)
        XCTAssertEqual(tokens.defaultFileExtension, "png")
        XCTAssertEqual(tokens.items.map(\.id), ["legacy", "extension", "named-hash", "named-extension", "absolute"])
        XCTAssertEqual(tokens.items.map(\.name), [nil, nil, "Named artwork", "Extension artwork", nil])
        XCTAssertEqual(tokens.items.map(\.fileExtension), [nil, "jpg", nil, "webp", nil])
        XCTAssertEqual(tokens.items[2].url, "https://example.com/named.png")
        XCTAssertEqual(tokens.items[4].url, "https://other.example/art.png")
        XCTAssertEqual(tokens.items[2].thumbnailAspectRatio, ThumbnailAspectRatio(width: 16, height: 9))
        XCTAssertEqual(tokens.items[0].thumbnailAspectRatio, ThumbnailAspectRatio(width: 3, height: 4))
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
            for (index, token) in tokens.items.enumerated() {
                XCTAssertEqual(token.id, String(projectID * 1_000_000 + index), item.name)
                XCTAssertNotNil(token.hash?.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression), item.name + " " + token.id)
                XCTAssertNotNil(token.artworkAspectRatio, item.name + " " + token.id)
                XCTAssertNotNil(token.thumbnailAspectRatio, item.name + " " + token.id)
                XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
            }
            for index in Set([0, tokens.items.count / 2, tokens.items.count - 1]) {
                let token = tokens.items[index]
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
                    XCTAssertEqual(descriptor.thumbnailAspectRatio, token.thumbnailAspectRatio)
                }
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.tokenId, token.id)
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.thumbnailAspectRatio, token.thumbnailAspectRatio)
            }
            XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: -1))
            XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: tokens.items.count))
            count += tokens.items.count
        }
        XCTAssertEqual(count, 143_847)
    }

    func testNeighborhoodThumbnailFramingIsIndependentOfGenerativeArtworkFraming() throws {
        let item = try XCTUnwrap(additions.first { $0.internalSlug == "neighborhood" })
        let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
        for (index, width, height) in [(0, 16, 9), (3, 1, 1), (7, 9, 16)] {
            let ratio = ThumbnailAspectRatio(width: width, height: height)
            XCTAssertEqual(tokens[index].id, String(146_000_000 + index))
            XCTAssertEqual(tokens[index].thumbnailAspectRatio, ratio)
            XCTAssertEqual(tokens[index].artworkAspectRatio, ThumbnailAspectRatio(width: 1, height: 1))
            let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
            XCTAssertEqual(sources.thumbnailDescriptor.thumbnailAspectRatio, ratio)
            XCTAssertEqual(sources.smallThumbnailDescriptor.thumbnailAspectRatio, ratio)
            XCTAssertEqual(sources.smallestThumbnailDescriptor?.thumbnailAspectRatio, ratio)
            XCTAssertEqual(sources.largeDescriptor.thumbnailAspectRatio, ratio)
            let generated = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: index))
            XCTAssertEqual(generated.id, tokens[index].id)
            XCTAssertNil(generated.media)
            XCTAssertFalse(generated.html.isEmpty)
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
        for key in ["bundledDate", "generativeOnly", "hasCover", "hasThumbnails", "iosOnly"] { fields.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(SuggestedItem.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertNil(legacy.bundledDate)
        XCTAssertNil(legacy.generativeOnly)
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
            XCTAssertEqual(tokens.count, count)
            for (index, expected) in tokens.enumerated() {
                XCTAssertFalse(try XCTUnwrap(expected.name).isEmpty)
                let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: item.id, tokenIndex: index))
                XCTAssertEqual(token.id, expected.id)
                XCTAssertEqual(token.fullCollectionId, item.id)
                XCTAssertEqual(token.address, item.address)
                XCTAssertEqual(token.displayName, expected.name)
                XCTAssertEqual(token.media?.url.absoluteString, expected.url)
                XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
                XCTAssertEqual(token.url?.absoluteString, "https://eth.blockscout.com/token/\(item.address)/instance/\(expected.id)?tab=metadata")

                let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
                let originalURL = try XCTUnwrap(expected.url.flatMap(URL.init(string:)))
                let stem = originalURL.deletingPathExtension().lastPathComponent
                let base = "https://cdn.lil.org/player/\(slug)"
                XCTAssertEqual(sources.thumbnailDescriptor.url.absoluteString, "\(base)/thumbs/\(stem).webp")
                XCTAssertEqual(sources.smallThumbnailDescriptor.url.absoluteString, "\(base)/thumbs/260/\(index).webp")
                XCTAssertEqual(sources.smallestThumbnailDescriptor?.url.absoluteString, "\(base)/thumbs/140/\(index).webp")
                XCTAssertEqual(sources.largeDescriptor.url.absoluteString, "\(base)/mid/\(stem).webp")
                XCTAssertEqual(sources.thumbnailDescriptor.thumbnailAspectRatio, expected.thumbnailAspectRatio)
                XCTAssertNotNil(expected.thumbnailAspectRatio)
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
            XCTAssertTrue(tokens.isComplete)
            XCTAssertEqual(tokens.items.count, count)
            XCTAssertEqual(Set(tokens.items.map(\.id)).count, count)
            let base = "https://cdn.lil.org/player/\(slug)"
            for (index, expected) in tokens.items.enumerated() {
                XCTAssertEqual(expected.id, String(projectID * 1_000_000 + index))
                XCTAssertEqual(expected.url, "\(base)/\(index).png")
                XCTAssertNotNil(expected.thumbnailAspectRatio)
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
                XCTAssertEqual(sources.thumbnailDescriptor.thumbnailAspectRatio, expected.thumbnailAspectRatio)
                XCTAssertEqual(sources.largeDescriptor.thumbnailAspectRatio, expected.thumbnailAspectRatio)
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
        let expectations = [(0, 6, 5), (1, 9, 16), (2, 16, 9), (4, 5, 6), (15, 1, 1)]
        for (index, width, height) in expectations {
            let expected = ThumbnailAspectRatio(width: width, height: height)
            XCTAssertEqual(tokens[index].thumbnailAspectRatio, expected)
            let sources = try XCTUnwrap(CollectionCatalog.collectionBrowseImageSources(specificCollectionId: item.id, tokenIndex: index))
            XCTAssertEqual(sources.thumbnailDescriptor.thumbnailAspectRatio, expected)
            XCTAssertEqual(sources.smallThumbnailDescriptor.thumbnailAspectRatio, expected)
            XCTAssertEqual(sources.smallestThumbnailDescriptor?.thumbnailAspectRatio, expected)
            XCTAssertEqual(sources.largeDescriptor.thumbnailAspectRatio, expected)
        }
        XCTAssertEqual(Set(tokens.compactMap(\.thumbnailAspectRatio)).count, 5)
    }
}
