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

    func testApprovedCollectionsAreNormalCatalogEntriesWithoutImageModes() throws {
        XCTAssertEqual(SuggestedItemsService.allItems.count, 519)
        XCTAssertEqual(additions.count, 292)
        var policies = [String: Int]()
        for item in additions {
            XCTAssertFalse(item.id.contains("dev-good"), item.name)
            XCTAssertEqual(item.id, item.address + (item.abId ?? ""), item.name)
            XCTAssertEqual(item.iosOnly, true)
            XCTAssertEqual(item.hasCover, false)
            XCTAssertEqual(item.hasThumbnails, false)
            XCTAssertFalse(item.isDownloadableCollection)
            XCTAssertNil(item.tokenCount)
            XCTAssertFalse(item.artists.isEmpty, item.name)
            XCTAssertTrue(SuggestedItemsService.visibleItems.contains { $0.id == item.id })
            XCTAssertTrue(CollectionCatalog.allItems.contains { $0.id == item.id && !$0.hasCover })
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
}
