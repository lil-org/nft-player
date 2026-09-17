import Foundation
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksLocalGenerationTests: XCTestCase {}

@MainActor
extension ArtBlocksLocalGenerationTests {
    private struct Project {
        let name: String
        let slug: String
        let projectId: Int
        let count: Int
        let kind: Script.Kind
        let ratio: ThumbnailAspectRatio
        var address = "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270"
        var legacySuffix: String?

        var id: String { address + (legacySuffix ?? String(projectId)) }
        var sampleIndices: [Int] { [0, count / 2, count - 1] }

        func tokenId(at index: Int) -> String {
            String(projectId * 1_000_000 + index)
        }

        func imageURL(at index: Int) -> String {
            "https://cdn.lil.org/player/\(slug)/\(index).png"
        }
    }

    private var projects: [Project] {
        [
            Project(name: "Archetype", slug: "archetype", projectId: 23, count: 600,
                    kind: .p5js100, ratio: .init(width: 1, height: 1)),
            Project(name: "Fidenza", slug: "fidenza", projectId: 78, count: 999,
                    kind: .p5js100, ratio: .init(width: 5, height: 6)),
            Project(name: "Ringers", slug: "ringers", projectId: 13, count: 1_000,
                    kind: .p5js100, ratio: .init(width: 1, height: 1)),
            Project(name: "Instructions for Defacement", slug: "instructions_for_defacement",
                    projectId: 0, count: 712, kind: .js, ratio: .init(width: 325, height: 139),
                    address: "0x18de6097ce5b5b2724c9cae6ac519917f3f178c0"),
            Project(name: "Meridian", slug: "meridian", projectId: 163, count: 1_000,
                    kind: .js, ratio: .init(width: 140, height: 249)),
            Project(name: "The Eternal Pump", slug: "the_eternal_pump", projectId: 22, count: 50,
                    kind: .three, ratio: .init(width: 1, height: 1)),
            Project(name: "Parnassus", slug: "parnassus", projectId: 2, count: 100,
                    kind: .p5js100, ratio: .init(width: 140, height: 249),
                    address: "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce3676",
                    legacySuffix: "71f6ddfea755d56de211919de8fc87ec"),
        ]
    }

    func testSevenCollectionsKeepTheirCatalogIdentitiesAndUseBundledGeneration() throws {
        let ids = Set(projects.map(\.id))
        let catalogItems = SuggestedItemsService.allItems.filter { ids.contains($0.id) }
        XCTAssertEqual(catalogItems.map(\.id), projects.map(\.id))
        XCTAssertEqual(catalogItems.map(\.name), projects.map(\.name))

        for project in projects {
            let item = try XCTUnwrap(SuggestedItemsService.item(id: project.id), project.name)
            let script = try bundledScript(for: project)
            XCTAssertEqual(item.internalSlug, project.slug)
            XCTAssertEqual(item.address, project.address)
            XCTAssertEqual(item.chainId, 1)
            XCTAssertEqual(item.chain, .ethereum)
            XCTAssertNil(item.tokenCount, project.name)
            XCTAssertFalse(item.isDownloadableCollection, project.name)
            XCTAssertFalse(CollectionCatalog.isDownloadableCollection(specificCollectionId: project.id))
            XCTAssertTrue(TokenGenerator.isBundledWebGenerativeCollection(id: project.id), project.name)
            XCTAssertTrue(CollectionCatalog.canOpenCollection(specificCollectionId: project.id))
            XCTAssertEqual(CollectionCatalog.allItems.contains { $0.id == project.id }, true, project.name)
            XCTAssertEqual(script.id, project.id)
            XCTAssertEqual(script.address, project.address)
            XCTAssertEqual(script.abId, String(project.projectId))
            XCTAssertEqual(script.kind, project.kind)
            XCTAssertEqual(script.collectionIdOverride, project.legacySuffix == nil ? nil : project.id)
            XCTAssertFalse(script.value.isEmpty, project.name)
        }
    }

    func testAll4461TokenIDsHashesImagesAndAspectRatiosArePreserved() throws {
        var total = 0
        for project in projects {
            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: project.id))
            XCTAssertEqual(tokens.items.count, project.count, project.name)
            XCTAssertEqual(tokens.items.map(\.id), (0..<project.count).map(project.tokenId))
            XCTAssertEqual(TokenGenerator.tokenCount(specificCollectionId: project.id), project.count)
            XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: project.id), project.count)
            XCTAssertEqual(
                CollectionCatalog.collectionBrowseThumbnailAspectRatioProfile(specificCollectionId: project.id),
                .uniform(project.ratio)
            )
            for (index, token) in tokens.items.enumerated() {
                let hash = try XCTUnwrap(token.hash, "\(project.name) #\(index)")
                XCTAssertNotNil(hash.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression))
                XCTAssertEqual(token.url, project.imageURL(at: index))
                XCTAssertEqual(token.thumbnailAspectRatio, project.ratio)
                XCTAssertEqual(
                    CollectionCatalog.tokenIndex(specificCollectionId: project.id, tokenId: token.id),
                    index
                )
            }
            total += tokens.items.count
        }
        XCTAssertEqual(total, 4_461)
    }

    func testLowMiddleAndHighTokensProduceHTMLWithStableIdentityAndThumbnails() throws {
        for project in projects {
            let script = try bundledScript(for: project)
            for index in project.sampleIndices {
                let token = try XCTUnwrap(CollectionCatalog.generateToken(
                    specificCollectionId: project.id,
                    tokenIndex: index
                ), "\(project.name) #\(index)")
                XCTAssertEqual(token.fullCollectionId, project.id)
                XCTAssertEqual(token.id, project.tokenId(at: index))
                XCTAssertEqual(token.displayTokenId, "#\(index)")
                XCTAssertEqual(token.displayName, "\(project.name) #\(index)")
                XCTAssertEqual(token.renderKind ?? .html, .html)
                XCTAssertNil(token.media)
                XCTAssertTrue(token.html.hasPrefix("<html>"))
                XCTAssertTrue(token.html.contains(script.value), project.name)
                let context = try XCTUnwrap(CollectionCatalog.tokenContext(for: token))
                XCTAssertEqual(context.collectionId, project.id)
                XCTAssertEqual(context.tokenIndex, index)
                XCTAssertEqual(context.tokenCount, project.count)
                let thumbnail = try XCTUnwrap(CollectionCatalog.collectionBrowseThumbnailDescriptor(
                    specificCollectionId: project.id,
                    tokenIndex: index
                ))
                XCTAssertEqual(thumbnail.collectionId, project.id)
                XCTAssertEqual(thumbnail.tokenId, token.id)
                XCTAssertEqual(thumbnail.media.url.absoluteString,
                               "https://cdn.lil.org/player/\(project.slug)/thumbs/\(index).webp")
                XCTAssertEqual(thumbnail.thumbnailAspectRatio, project.ratio)
            }
            XCTAssertNil(TokenGenerator.generateToken(specificCollectionId: project.id, tokenIndex: -1))
            XCTAssertNil(TokenGenerator.generateToken(specificCollectionId: project.id, tokenIndex: project.count))
            if project.kind == .p5js100 || project.kind == .three {
                XCTAssertNotNil(PersistentJavaScriptLibrary.library(named: project.kind.rawValue))
            }
        }
    }

    func testStaticCollectionsKeepTheirOriginalImagesAndRemainVisibleInTheFullGrid() throws {
        let staticProjects: [(
            name: String, slug: String, address: String, projectId: Int,
            count: Int, ratio: ThumbnailAspectRatio
        )] = [
            ("Fragments of an Infinite Field", "fragments_of_an_infinite_field",
             "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270", 159, 1_024, .init(width: 1, height: 1)),
            ("Flore Perdue", "flore_perdue",
             "0x7c3ea2b7b3befa1115ab51c09f0c9f245c500b18", 29, 100, .init(width: 105, height: 142)),
            ("Letters to My Future Self", "letters_to_my_future_self",
             "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270", 174, 1_000, .init(width: 1, height: 1)),
        ]
        for project in staticProjects {
            let id = project.address + String(project.projectId)
            let item = try XCTUnwrap(SuggestedItemsService.item(id: id), project.name)
            let tokens = try XCTUnwrap(SuggestedItemsService.bundledTokens(collectionId: id))
            XCTAssertEqual(item.name, project.name)
            XCTAssertEqual(item.internalSlug, project.slug)
            XCTAssertEqual(item.tokenCount, project.count)
            XCTAssertTrue(item.isDownloadableCollection)
            XCTAssertTrue(CollectionCatalog.isDownloadableCollection(specificCollectionId: id))
            XCTAssertFalse(TokenGenerator.canGenerate(id: id))
            XCTAssertEqual(CollectionCatalog.allItems.contains { $0.id == id }, true, project.name)
            XCTAssertTrue(SuggestedItemsService.visibleItems.contains { $0.id == id }, project.name)
            XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: id), project.count)
            XCTAssertEqual(tokens.items.count, project.count)
            XCTAssertEqual(tokens.items.map(\.id), (0..<project.count).map {
                String(project.projectId * 1_000_000 + $0)
            })
            for (index, token) in tokens.items.enumerated() {
                XCTAssertNil(token.hash, "\(project.name) #\(index)")
                XCTAssertEqual(token.url, "https://cdn.lil.org/player/\(project.slug)/\(index).png")
                XCTAssertEqual(token.thumbnailAspectRatio, project.ratio)
                XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: id, tokenId: token.id), index)
            }
            for index in [0, project.count / 2, project.count - 1] {
                let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: id, tokenIndex: index))
                XCTAssertEqual(token.fullCollectionId, id)
                XCTAssertEqual(token.id, String(project.projectId * 1_000_000 + index))
                XCTAssertFalse(token.html.isEmpty)
                XCTAssertEqual(token.media, .staticImage(
                    url: try XCTUnwrap(URL(string: "https://cdn.lil.org/player/\(project.slug)/\(index).png")),
                    fileExtension: "png"
                ))
                let thumbnail = try XCTUnwrap(CollectionCatalog.collectionBrowseThumbnailDescriptor(
                    specificCollectionId: id,
                    tokenIndex: index
                ))
                XCTAssertEqual(thumbnail.tokenId, token.id)
                XCTAssertEqual(thumbnail.media.url.absoluteString,
                               "https://cdn.lil.org/player/\(project.slug)/thumbs/\(index).webp")
                XCTAssertEqual(thumbnail.thumbnailAspectRatio, project.ratio)
            }
            XCTAssertEqual(
                CollectionCatalog.collectionBrowseThumbnailAspectRatioProfile(specificCollectionId: id),
                .uniform(project.ratio)
            )
        }
    }

    func testParnassusRestoresBookmarksAndViewingProgressUnderItsLegacyIdentity() async throws {
        let project = try XCTUnwrap(projects.first { $0.slug == "parnassus" })
        let suiteName = "ArtBlocksLocalGenerationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let savedProgress = PlayerViewingProgress(
            collectionId: project.id,
            collectionName: project.name,
            tokenId: "2000050",
            tokenIndex: 50,
            tokenCount: 100,
            updatedAt: Date()
        )
        defaults.set(try JSONEncoder().encode([project.id: savedProgress]),
                     forKey: PlayerSyncDomain.viewingProgress.key)
        defaults.set(try JSONEncoder().encode([
            project.id: ["2000050": PlayerBookmark(bookmarkedAt: Date())]
        ]), forKey: PlayerSyncDomain.bookmarks.key)
        let progressStore = PlayerViewingProgressStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        let bookmarksStore = PlayerBookmarksStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        let restoredProgress = await progressStore.progress(collectionId: project.id)
        XCTAssertEqual(restoredProgress, savedProgress)
        let token = try XCTUnwrap(CollectionCatalog.generateToken(
            specificCollectionId: try XCTUnwrap(restoredProgress).collectionId,
            tokenIndex: try XCTUnwrap(restoredProgress).tokenIndex
        ))
        let isBookmarked = await bookmarksStore.isBookmarked(
            collectionId: token.fullCollectionId,
            tokenId: token.id
        )
        XCTAssertTrue(isBookmarked)
        XCTAssertEqual(token.displayName, "Parnassus #50")
        XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: project.id, tokenId: "2000050"), 50)
        XCTAssertNil(SuggestedItemsService.item(id: project.address + "2"))
        XCTAssertFalse(TokenGenerator.canGenerate(id: project.address + "2"))
    }

    func testDefacementUsesCDNAssetAdapterAndDisplayTuning() throws {
        let project = try XCTUnwrap(projects.first { $0.slug == "instructions_for_defacement" })
        let script = try bundledScript(for: project)
        let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: project.id, tokenIndex: 0))
        XCTAssertEqual(script.kind, .js)
        XCTAssertTrue(script.value.contains("tokenData.preferredIPFSGateway"))
        XCTAssertTrue(script.value.contains("https://cdn.lil.org/player/instructions_for_defacement/"))
        XCTAssertTrue(script.value.contains("tokenData.externalAssetDependencies"))
        XCTAssertTrue(script.value.contains("background.jpg"))
        let tuning = try XCTUnwrap(script.nftPlayerDisplayTuning)
        XCTAssertTrue(tuning.contains("document.documentElement.style.height"))
        XCTAssertTrue(tuning.contains("document.body.style.minHeight"))
        XCTAssertTrue(tuning.contains("100%"))
        XCTAssertTrue(token.html.contains(tuning))
        XCTAssertEqual(SuggestedItemsService.item(id: project.id)?.iosCollectionBrowserColumnCount, 2)
        for other in projects where other.id != project.id {
            let otherScript = try bundledScript(for: other)
            XCTAssertFalse(otherScript.value.contains("tokenData.externalAssetDependencies"), other.name)
        }
    }

    func testScriptIdentityOverrideIsOptionalAndRoundTrips() throws {
        let fixture: [String: Any] = [
            "address": "0xcollection", "abId": "2", "name": "Legacy script",
            "kind": "js", "value": "void 0;",
        ]
        let oldScript = try JSONDecoder().decode(Script.self, from: JSONSerialization.data(withJSONObject: fixture))
        XCTAssertNil(oldScript.collectionIdOverride)
        XCTAssertEqual(oldScript.id, "0xcollection2")
        var overriddenFixture = fixture
        overriddenFixture["collectionIdOverride"] = "preserved-collection-id"
        let newScript = try JSONDecoder().decode(Script.self, from: JSONSerialization.data(withJSONObject: overriddenFixture))
        XCTAssertEqual(newScript.abId, "2")
        XCTAssertEqual(newScript.id, "preserved-collection-id")
        let roundTripped = try JSONDecoder().decode(Script.self, from: JSONEncoder().encode(newScript))
        XCTAssertEqual(roundTripped.id, newScript.id)
        XCTAssertEqual(roundTripped.collectionIdOverride, newScript.collectionIdOverride)
    }

    private func bundledScript(for project: Project) throws -> Script {
        let url = try XCTUnwrap(SuggestedItemsService.bundledScriptURL(collectionId: project.id), project.name)
        return try JSONDecoder().decode(Script.self, from: Data(contentsOf: url))
    }
}
