import Foundation
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksCatalogTests: XCTestCase {}

@MainActor
extension ArtBlocksCatalogTests {
    private var additions: [SuggestedItem] {
        SuggestedItemsService.allItems.filter { $0.bundledDate == "2026-09-14" && $0.generativeOnly == true }
    }

    func testApprovedCollectionsHaveCoversAndGenerativeOnlyPlayback() throws {
        XCTAssertEqual(SuggestedItemsService.allItems.count, 529)
        XCTAssertEqual(additions.count, 292)
        var policies = [String: Int]()
        for item in additions {
            XCTAssertFalse(item.id.contains("dev-good"), item.name)
            XCTAssertEqual(item.id, item.address + (item.abId ?? ""), item.name)
            XCTAssertEqual(item.iosOnly, true)
            XCTAssertEqual(item.hasCover, true)
            XCTAssertEqual(item.hasThumbnails, false)
            XCTAssertFalse(item.isDownloadableCollection)
            XCTAssertNil(item.tokenCount)
            XCTAssertFalse(item.artists.isEmpty, item.name)
            XCTAssertTrue(SuggestedItemsService.visibleItems.contains { $0.id == item.id })
            XCTAssertTrue(CollectionCatalog.allItems.contains { $0.id == item.id && $0.hasCover })
            let cover = try XCTUnwrap(UIImage(named: item.id)?.cgImage, item.name)
            XCTAssertEqual(cover.width, 300, item.name)
            XCTAssertEqual(cover.height, 300, item.name)
            XCTAssertTrue(TokenGenerator.usesArtBlocksRenderer(collectionId: item.id))
            XCTAssertTrue(CollectionCatalog.canOpenCollection(specificCollectionId: item.id))
            XCTAssertFalse(CollectionCatalog.isDownloadableCollection(specificCollectionId: item.id))
            XCTAssertFalse(PlayerCollectionBrowserSupport.isAvailable(forCollectionId: item.id))
            XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: 0))
            let url = try XCTUnwrap(SuggestedItemsService.bundle.url(forResource: "Scripts/" + item.id, withExtension: "json"))
            let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: url))
            let policy = ArtBlocksRenderingStartupProfiles.startupProfile(script) == nil ? "direct" : "calibrated"
            policies[policy, default: 0] += 1
        }
        XCTAssertEqual(policies, ["direct": 213, "calibrated": 79])
    }

    func testAllMintedRecordsDecodeWithHashesAndStableNavigationIdentity() throws {
        var count = 0
        for item in additions {
            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id))
            XCTAssertFalse(tokens.items.isEmpty, item.name)
            XCTAssertEqual(Set(tokens.items.map(\.id)).count, tokens.items.count, item.name)
            XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: item.id), tokens.items.count)
            for token in tokens.items {
                XCTAssertNotNil(token.hash?.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression), item.name + " " + token.id)
                XCTAssertNotNil(token.artworkAspectRatio ?? token.thumbnailAspectRatio, item.name + " " + token.id)
            }
            for index in Set([0, tokens.items.count / 2, tokens.items.count - 1]) {
                let token = tokens.items[index]
                XCTAssertEqual(TokenGenerator.tokenIndex(specificCollectionId: item.id, tokenId: token.id), index)
                XCTAssertNil(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: item.id, tokenIndex: index))
            }
            count += tokens.items.count
        }
        XCTAssertGreaterThan(count, 6_524)
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
            let cover = try XCTUnwrap(UIImage(named: item.id))
            XCTAssertEqual(cover.cgImage?.width, 300)
            XCTAssertEqual(cover.cgImage?.height, 300)

            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: item.id)).items
            XCTAssertEqual(tokens.count, count)
            for (index, expected) in tokens.enumerated() {
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
            let cover = try XCTUnwrap(UIImage(named: item.id))
            XCTAssertEqual(cover.cgImage?.width, 300)
            XCTAssertEqual(cover.cgImage?.height, 300)

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
