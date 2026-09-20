import Foundation

nonisolated enum ArtworkContentResolver {
    enum Failure: Error, Equatable {
        case invalidReference
        case unavailableCollection
        case unavailableToken
        case emptyArtwork
    }

    private struct Request: Codable {
        let collectionId: String
        let tokenId: String
        let sha256: String
    }

    private static let referencePrefix = "nft-player-artwork:"
    private static let versionedReferencePrefix = referencePrefix + "v1:"

    @MainActor
    static func makeLoadGate() -> PersistentWebContentLoadGate {
        PersistentWebContentLoadGate(
            requiresPreparation: requiresPreparation,
            resolve: { try await resolve($0, cache: $1, allowsDownloads: $2) }
        )
    }

    static func reference(collectionId: String, tokenId: String, sha256: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let request = Request(collectionId: collectionId, tokenId: tokenId, sha256: sha256)
        return versionedReferencePrefix + (try! encoder.encode(request)).base64EncodedString()
    }

    static func requiresPreparation(_ html: String) -> Bool {
        html.hasPrefix(referencePrefix)
            || !PersistentJavaScriptLibrary.requiredDependencies(in: html).isEmpty
    }

    @concurrent
    static func resolve(
        _ html: String,
        cache: PersistentArtworkDependencyCache = .shared,
        allowsDownloads: Bool = true
    ) async throws -> String {
        try Task.checkCancellation()
        let document: String
        if html.hasPrefix(referencePrefix) {
            guard html.hasPrefix(versionedReferencePrefix),
                  let data = Data(base64Encoded: String(html.dropFirst(versionedReferencePrefix.count))),
                  let request = try? JSONDecoder().decode(Request.self, from: data) else {
                throw Failure.invalidReference
            }
            guard let item = SuggestedItemsService.scriptItem(collectionId: request.collectionId),
                  let dependency = item.scriptDependency,
                  dependency.sha256 == request.sha256 else {
                throw Failure.invalidReference
            }
            try await CollectionCatalog.prepareCollection(
                collectionId: item.id, allowsDownloads: allowsDownloads
            )
            guard let tokenIndex = TokenGenerator.tokenIndex(specificCollectionId: item.id, tokenId: request.tokenId),
                  let token = TokenGenerator.bundledWebGenerativeToken(specificCollectionId: item.id, tokenIndex: tokenIndex) else {
                throw Failure.unavailableToken
            }
            let script = try await script(collectionId: item.id, cache: cache, allowsDownloads: allowsDownloads)
            try Task.checkCancellation()
            document = RawHtmlGenerator.createHtml(script: script, token: token)
            guard !document.isEmpty else { throw Failure.emptyArtwork }
        } else {
            document = html
        }
        let resolved = try await PersistentJavaScriptLibrary.resolve(document, cache: cache, allowsDownloads: allowsDownloads)
        return ArtworkAssetPolicy.protectHTML(resolved)
    }

    @concurrent
    static func script(
        collectionId: String,
        cache: PersistentArtworkDependencyCache = .shared,
        allowsDownloads: Bool = true
    ) async throws -> Script {
        try Task.checkCancellation()
        guard let item = SuggestedItemsService.scriptItem(collectionId: collectionId),
              let metadata = item.script else { throw Failure.unavailableCollection }
        let source: String
        if metadata.kind.isNativeRenderer {
            source = ""
        } else {
            guard let dependency = item.scriptDependency else {
                throw PersistentArtworkDependencyCache.Failure.invalidDescriptor
            }
            let data: Data
            if allowsDownloads {
                data = try await cache.data(for: dependency)
            } else {
                guard let cachedData = try await cache.cachedData(for: dependency) else {
                    throw PersistentArtworkDependencyCache.Failure.notCached
                }
                data = cachedData
            }
            try Task.checkCancellation()
            guard let value = String(data: data, encoding: .utf8) else {
                throw PersistentArtworkDependencyCache.Failure.invalidUTF8
            }
            source = value
        }
        guard let script = Script(item: item, value: source) else { throw Failure.unavailableCollection }
        return script
    }

    @concurrent
    static func prepareCollection(
        collectionId: String,
        cache: PersistentArtworkDependencyCache = .shared
    ) async throws {
        let script = try await script(collectionId: collectionId, cache: cache)
        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for dependency in RawHtmlGenerator.requiredDependencies(for: script) {
                group.addTask { _ = try await cache.data(for: dependency) }
            }
            try await group.waitForAll()
        }
    }
}
