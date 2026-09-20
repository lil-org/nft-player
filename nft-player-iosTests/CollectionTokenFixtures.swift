import Foundation
import XCTest
@testable import nft_player_ios

nonisolated enum CollectionTokenFixtures {
    enum Failure: LocalizedError {
        case missingManifest(String)

        var errorDescription: String? {
            switch self {
            case .missingManifest(let name):
                "Missing collection fixture \(name). Run node scripts/hydrate-collection-test-manifests.mjs, then rebuild the test bundle."
            }
        }
    }

    static func url(collectionId: String) -> URL? {
        guard let name = SuggestedItemsService.tokenResourceName(collectionId: collectionId) else { return nil }
        return Bundle(for: CollectionTokenFixtureTestCase.self).url(
            forResource: name, withExtension: "json", subdirectory: "CollectionManifests"
        )
    }

    private static let preparation = Result<Void, Error> {
        for item in SuggestedItemsService.allItems {
            guard let name = SuggestedItemsService.tokenResourceName(collectionId: item.id) else { continue }
            guard let url = url(collectionId: item.id) else { throw Failure.missingManifest(name) }
            try CollectionCatalog.installPreparedTokens(Data(contentsOf: url), collectionId: item.id)
        }
    }

    static func prepareAll() throws {
        try preparation.get()
    }
}

nonisolated class CollectionTokenFixtureTestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try CollectionTokenFixtures.prepareAll()
    }
}

#if DEBUG
private actor CollectionPreparationTransportProbe {
    private(set) var urls: [URL] = []
    private let data: Data
    private var statusCode: Int
    private let offline: Bool

    init(data: Data, statusCode: Int = 200, offline: Bool = false) {
        self.data = data
        self.statusCode = statusCode
        self.offline = offline
    }

    func fetch(_ url: URL) throws -> (data: Data, statusCode: Int) {
        urls.append(url)
        if offline { throw URLError(.notConnectedToInternet) }
        return (data, statusCode)
    }

    func setStatusCode(_ statusCode: Int) {
        self.statusCode = statusCode
    }
}

nonisolated final class CollectionTokenColdPreparationTests: XCTestCase {}

@MainActor
extension CollectionTokenColdPreparationTests {
    private struct Fixture {
        let item: SuggestedItem
        let data: Data
        let tokens: BundledTokens
    }

    private func fixture(_ slug: String = "fidenza") throws -> Fixture {
        let item = try XCTUnwrap(SuggestedItemsService.item(resourceName: slug))
        let url = try XCTUnwrap(CollectionTokenFixtures.url(collectionId: item.id))
        let data = try Data(contentsOf: url)
        return Fixture(item: item, data: data, tokens: try BundledTokens(data: data))
    }

    private func restore(_ fixture: Fixture) {
        CollectionCatalog.resetPreparedCollectionForTesting(collectionId: fixture.item.id)
        XCTAssertNoThrow(try CollectionCatalog.installPreparedTokens(fixture.data, collectionId: fixture.item.id))
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ColdCollectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func assertPreparedFidenza(_ fixture: Fixture) throws {
        XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: fixture.item.id), fixture.tokens.items.count)
        for index in [0, fixture.tokens.items.count - 1] {
            let expected = fixture.tokens.items[index]
            let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: fixture.item.id, tokenIndex: index))
            XCTAssertEqual(token.fullCollectionId, fixture.item.id)
            XCTAssertEqual(token.id, expected.id)
            XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: fixture.item.id, tokenId: expected.id), index)
            let generated = try XCTUnwrap(TokenGenerator.bundledWebGenerativeToken(specificCollectionId: fixture.item.id, tokenIndex: index))
            XCTAssertEqual(generated.hash, expected.hash)
            XCTAssertNotNil(generated.hash)
            let media = try XCTUnwrap(CollectionCatalog.collectionBrowseThumbnailDescriptor(specificCollectionId: fixture.item.id, tokenIndex: index))
            XCTAssertEqual(media.tokenId, expected.id)
            XCTAssertEqual(media.url.absoluteString, "https://cdn.lil.org/player/fidenza/thumbs/\(index).webp")
        }
    }

    func testColdPreparationDownloadsAndInstallsCanonicalTokenModels() async throws {
        let fixture = try fixture()
        defer { restore(fixture) }
        CollectionCatalog.resetPreparedCollectionForTesting(collectionId: "FIDENZA")
        XCTAssertNil(SuggestedItemsService.cachedTokens(collectionId: fixture.item.id))
        XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: fixture.item.id, tokenIndex: 0))
        let probe = CollectionPreparationTransportProbe(data: fixture.data)
        let cache = PersistentCollectionTokenCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        try await CollectionCatalog.prepareCollection(collectionId: fixture.item.id.uppercased(), cache: cache)
        try assertPreparedFidenza(fixture)
        try await CollectionCatalog.prepareCollection(collectionId: "fidenza", cache: cache)
        let urls = await probe.urls
        XCTAssertEqual(urls, [URL(string: "https://cdn.lil.org/player/collections/fidenza.json")!])
    }

    func testColdFailureLeavesModelsUnavailableAndCanRetry() async throws {
        let fixture = try fixture()
        defer { restore(fixture) }
        CollectionCatalog.resetPreparedCollectionForTesting(collectionId: fixture.item.id)
        let probe = CollectionPreparationTransportProbe(data: fixture.data, statusCode: 503)
        let cache = PersistentCollectionTokenCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        do {
            try await CollectionCatalog.prepareCollection(collectionId: fixture.item.id, allowsDownloads: false, cache: cache)
            XCTFail("An uncached collection should not become ready offline")
        } catch CollectionCatalog.PreparationFailure.notCached {}
        let beforeDownload = await probe.urls
        XCTAssertTrue(beforeDownload.isEmpty)
        do {
            try await CollectionCatalog.prepareCollection(collectionId: fixture.item.id, cache: cache)
            XCTFail("Failed download must fail collection preparation")
        } catch let failure as PersistentCollectionTokenCache.Failure {
            XCTAssertEqual(failure, .httpStatus(503))
        }
        XCTAssertNil(SuggestedItemsService.cachedTokens(collectionId: fixture.item.id))
        XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: fixture.item.id, tokenIndex: 0))
        await probe.setStatusCode(200)
        try await CollectionCatalog.prepareCollection(collectionId: fixture.item.id, cache: cache)
        try assertPreparedFidenza(fixture)
        let urls = await probe.urls
        XCTAssertEqual(urls, Array(repeating: URL(string: "https://cdn.lil.org/player/collections/fidenza.json")!, count: 2))
    }

    func testRecreatedCachePreparesOfflineAfterClearingAllInMemoryModels() async throws {
        let fixture = try fixture()
        defer { restore(fixture) }
        CollectionCatalog.resetPreparedCollectionForTesting(collectionId: fixture.item.id)
        let root = try directory()
        let first = CollectionPreparationTransportProbe(data: fixture.data)
        let cache = PersistentCollectionTokenCache(rootURL: root, transport: { try await first.fetch($0) })
        try await CollectionCatalog.prepareCollection(collectionId: fixture.item.id, cache: cache)
        let offline = CollectionPreparationTransportProbe(data: Data(), offline: true)
        let recreated = PersistentCollectionTokenCache(rootURL: root, transport: { try await offline.fetch($0) })
        for allowsDownloads in [false, true] {
            CollectionCatalog.resetPreparedCollectionForTesting(collectionId: fixture.item.id)
            XCTAssertNil(CollectionCatalog.generateToken(specificCollectionId: fixture.item.id, tokenIndex: 0))
            try await CollectionCatalog.prepareCollection(
                collectionId: fixture.item.id,
                allowsDownloads: allowsDownloads,
                cache: recreated
            )
            try assertPreparedFidenza(fixture)
        }
        let firstURLs = await first.urls
        let offlineURLs = await offline.urls
        XCTAssertEqual(firstURLs, [URL(string: "https://cdn.lil.org/player/collections/fidenza.json")!])
        XCTAssertTrue(offlineURLs.isEmpty)
    }

    func testColdDownloadablePreparationPreservesIDsMediaAndExclusions() async throws {
        let fixture = try fixture("terraforms")
        defer { restore(fixture) }
        CollectionCatalog.resetPreparedCollectionForTesting(collectionId: fixture.item.id)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture.data) as? [String: Any])
        payload["excludedMediaIndices"] = [0, 2]
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        let probe = CollectionPreparationTransportProbe(data: bytes)
        let cache = PersistentCollectionTokenCache(rootURL: try directory(), transport: { try await probe.fetch($0) })
        XCTAssertNil(CollectionCatalog.downloadableMediaDescriptor(specificCollectionId: fixture.item.id, tokenIndex: 0))
        try await CollectionCatalog.prepareCollection(collectionId: "terraforms", cache: cache)
        XCTAssertEqual(CollectionCatalog.tokenCount(specificCollectionId: fixture.item.id), fixture.tokens.items.count - 2)
        for (preparedIndex, originalIndex) in [(0, 1), (1, 3)] {
            let expected = fixture.tokens.items[originalIndex]
            XCTAssertEqual(CollectionCatalog.tokenIndex(specificCollectionId: fixture.item.id, tokenId: expected.id), preparedIndex)
            let token = try XCTUnwrap(CollectionCatalog.generateToken(specificCollectionId: fixture.item.id, tokenIndex: preparedIndex))
            XCTAssertEqual(token.id, expected.id)
            let media = try XCTUnwrap(CollectionCatalog.downloadableMediaDescriptor(specificCollectionId: fixture.item.id, tokenIndex: preparedIndex))
            XCTAssertEqual(media.tokenId, expected.id)
            XCTAssertEqual(media.url.absoluteString, "https://tokens.mathcastles.xyz/terraforms/token-html/\(expected.id)?ext=html")
            XCTAssertEqual(media.aspectRatio, expected.aspectRatio ?? fixture.item.aspectRatio)
        }
        for originalIndex in [0, 2] {
            XCTAssertNil(CollectionCatalog.tokenIndex(specificCollectionId: fixture.item.id, tokenId: fixture.tokens.items[originalIndex].id))
        }
        let urls = await probe.urls
        XCTAssertEqual(urls, [URL(string: "https://cdn.lil.org/player/collections/terraforms.json")!])
    }

    func testDefaultCacheUsesHostAppGroupAndRecreatedCacheReadsItOffline() async throws {
        let container = try XCTUnwrap(FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PersistentCollectionTokenCache.appGroupIdentifier
        ))
        let root = container.appendingPathComponent("Library/Application Support/CollectionTokens", isDirectory: true)
        let resourceName = "collection-cache-test-" + UUID().uuidString
        let file = root.appendingPathComponent(resourceName + ".json")
        let lock = root.appendingPathComponent(resourceName + ".lock")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: lock)
        }
        let bytes = Data(#"{"version":2,"count":1,"firstId":"0"}"#.utf8)
        let first = CollectionPreparationTransportProbe(data: bytes)
        let cache = PersistentCollectionTokenCache(transport: { try await first.fetch($0) })
        let downloaded = try await cache.data(for: resourceName)
        XCTAssertEqual(downloaded, bytes)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let firstURLs = await first.urls
        XCTAssertEqual(firstURLs, [PersistentCollectionTokenCache.baseURL.appendingPathComponent(resourceName + ".json")])

        let offline = CollectionPreparationTransportProbe(data: Data(), offline: true)
        let recreated = PersistentCollectionTokenCache(transport: { try await offline.fetch($0) })
        let restored = try await recreated.data(for: resourceName)
        XCTAssertEqual(restored, bytes)
        let offlineURLs = await offline.urls
        XCTAssertTrue(offlineURLs.isEmpty)
    }
}
#endif
