// ∅ 2026 lil org

import Foundation

struct MobileCollectionItem: Hashable, Identifiable {
    let id: String
    let name: String
    let coverAssetName: String

    init(item: SuggestedItem) {
        id = item.id
        name = item.name
        coverAssetName = item.id
    }
}

struct SolanaImageDescriptor: Hashable {
    let collectionId: String
    let tokenId: String
    let tokenIndex: Int
    let url: URL
    let fileExtension: String
    let media: GeneratedTokenMedia

    var isStaticImage: Bool {
        media.isStaticImage
    }
}

enum MobileCollectionCatalog {
    private static let shuffleLock = NSLock()
    private static var currentPassCollectionIds = Set<String>()

    static let allItems: [MobileCollectionItem] = {
        (
            TokenGenerator.allGenerativeSuggestedItems
                + SuggestedItemsService.allSolanaCollectionItems
        )
        .map(MobileCollectionItem.init(item:))
    }()

    static func nextShuffledCollectionId() -> String? {
        shuffleLock.withLock {
            if currentPassCollectionIds.isEmpty {
                currentPassCollectionIds = Set(allItems.map(\.id))
            }
            let nextCollectionId = currentPassCollectionIds.randomElement()
            if let nextCollectionId {
                currentPassCollectionIds.remove(nextCollectionId)
            }
            return nextCollectionId
        }
    }

    static func tokenCount(specificCollectionId: String) -> Int {
        if SolanaCollectionService.hasCollection(id: specificCollectionId) {
            return SolanaCollectionService.tokenCount(collectionId: specificCollectionId)
        }
        return TokenGenerator.tokenCount(specificCollectionId: specificCollectionId)
    }

    static func isSolanaCollection(specificCollectionId: String) -> Bool {
        SolanaCollectionService.hasCollection(id: specificCollectionId)
    }

    static func tokenIndex(specificCollectionId: String, tokenId: String) -> Int? {
        if SolanaCollectionService.hasCollection(id: specificCollectionId) {
            return SolanaCollectionService.tokenIndex(collectionId: specificCollectionId, tokenId: tokenId)
        }
        return TokenGenerator.tokenIndex(specificCollectionId: specificCollectionId, tokenId: tokenId)
    }

    static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        if SolanaCollectionService.hasCollection(id: specificCollectionId) {
            return SolanaCollectionService.generateToken(collectionId: specificCollectionId, tokenIndex: tokenIndex)
        }
        return TokenGenerator.generateToken(specificCollectionId: specificCollectionId, tokenIndex: tokenIndex)
    }

    static func solanaImageDescriptor(specificCollectionId: String, tokenIndex: Int) -> SolanaImageDescriptor? {
        guard SolanaCollectionService.hasCollection(id: specificCollectionId) else { return nil }
        return SolanaCollectionService.imageDescriptor(collectionId: specificCollectionId, tokenIndex: tokenIndex)
    }
}

struct SolanaCollectionIndexItem: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let tokenCount: Int

    init?(item: SuggestedItem) {
        guard item.isSolanaCollection,
              let tokenCount = item.tokenCount else {
            return nil
        }
        id = item.id
        name = item.name
        self.tokenCount = tokenCount
    }
}

private enum SolanaCollectionService {
    private static let lock = NSLock()
    private static var cachedIndex: SolanaCollectionsIndex?
    private static var cachedTokenDataByCollectionId = [String: SolanaCollectionTokenData]()

    static var collections: [SolanaCollectionIndexItem] {
        index.collections
    }

    static func hasCollection(id: String) -> Bool {
        index.collectionById[id] != nil
    }

    static func tokenCount(collectionId: String) -> Int {
        index.collectionById[collectionId]?.tokenCount ?? 0
    }

    static func tokenIndex(collectionId: String, tokenId: String) -> Int? {
        tokenData(collectionId: collectionId)?.tokenIndicesById[tokenId]
    }

    static func generateToken(collectionId: String, tokenIndex: Int) -> GeneratedToken? {
        guard let collection = index.collectionById[collectionId],
              let tokenData = tokenData(collectionId: collectionId),
              tokenData.tokens.indices.contains(tokenIndex) else {
            return nil
        }

        let token = tokenData.tokens[tokenIndex]
        let nextImageURL = tokenData.tokens.indices.contains(tokenIndex + 1)
            ? tokenData.tokens[tokenIndex + 1].url
            : nil
        let displayTokenId = "#\(tokenIndex + 1)"
        let solanaExplorerURL = URL(string: "https://explorer.solana.com/address/\(token.id)")
        let media = resolvedMedia(for: token, defaultFileExtension: tokenData.defaultFileExtension)

        return GeneratedToken(
            fullCollectionId: collection.id,
            collectionName: collection.name,
            address: collection.id,
            id: token.id,
            html: SolanaTokenHTML.createImageHTML(imageURL: token.url, nextImageURL: nextImageURL),
            displayName: "\(collection.name) \(displayTokenId)",
            displayTokenId: displayTokenId,
            url: solanaExplorerURL,
            instructions: nil,
            screensaver: nil,
            media: media
        )
    }

    static func imageDescriptor(collectionId: String, tokenIndex: Int) -> SolanaImageDescriptor? {
        guard let tokenData = tokenData(collectionId: collectionId),
              tokenData.tokens.indices.contains(tokenIndex) else {
            return nil
        }

        let token = tokenData.tokens[tokenIndex]
        guard let resolvedMedia = resolvedMedia(for: token, defaultFileExtension: tokenData.defaultFileExtension) else {
            return nil
        }

        return SolanaImageDescriptor(
            collectionId: collectionId,
            tokenId: token.id,
            tokenIndex: tokenIndex,
            url: resolvedMedia.url,
            fileExtension: resolvedMedia.fileExtension,
            media: resolvedMedia
        )
    }

    private static func resolvedMedia(
        for token: SolanaTokenItem,
        defaultFileExtension: String?
    ) -> GeneratedTokenMedia? {
        guard let url = URL(string: token.url),
              let fileExtension = token.resolvedFileExtension(defaultFileExtension: defaultFileExtension) else {
            return nil
        }

        if SolanaMediaFileExtension.isAnimatedImage(fileExtension) {
            return .animatedImage(url: url, fileExtension: fileExtension)
        }
        if SolanaMediaFileExtension.isStaticImage(fileExtension) {
            return .staticImage(url: url, fileExtension: fileExtension)
        }
        return nil
    }

    private static var index: SolanaCollectionsIndex {
        if let cachedIndex = lock.withLock({ cachedIndex }) {
            return cachedIndex
        }

        let loadedIndex = loadIndex()
        return lock.withLock {
            if let cachedIndex = Self.cachedIndex {
                return cachedIndex
            }
            Self.cachedIndex = loadedIndex
            return loadedIndex
        }
    }

    private static func tokenData(collectionId: String) -> SolanaCollectionTokenData? {
        if let cachedTokenData = lock.withLock({ cachedTokenDataByCollectionId[collectionId] }) {
            return cachedTokenData
        }

        guard let loadedTokenData = loadTokenData(collectionId: collectionId) else {
            return nil
        }

        return lock.withLock {
            if let cachedTokenData = cachedTokenDataByCollectionId[collectionId] {
                return cachedTokenData
            }
            cachedTokenDataByCollectionId[collectionId] = loadedTokenData
            return loadedTokenData
        }
    }

    private static func loadIndex() -> SolanaCollectionsIndex {
        SolanaCollectionsIndex(
            collections: SuggestedItemsService.allSolanaCollectionItems.compactMap(SolanaCollectionIndexItem.init(item:))
        )
    }

    private static func loadTokenData(collectionId: String) -> SolanaCollectionTokenData? {
        guard let url = SuggestedItemsService.bundle.url(forResource: collectionId, withExtension: "json", subdirectory: "Tokens"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SolanaCollectionTokensPayload.self, from: data) else {
            return nil
        }
        return SolanaCollectionTokenData(
            defaultFileExtension: payload.defaultFileExtension,
            tokens: payload.items
        )
    }
}

private struct SolanaCollectionsIndex {
    let collections: [SolanaCollectionIndexItem]
    let collectionById: [String: SolanaCollectionIndexItem]

    init(collections: [SolanaCollectionIndexItem]) {
        self.collections = collections
        collectionById = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })
    }
}

private struct SolanaCollectionTokensPayload: Decodable {
    let defaultFileExtension: String?
    let items: [SolanaTokenItem]

    enum CodingKeys: String, CodingKey {
        case defaultFileExtension
        case items
        case urlPrefixes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultFileExtension = Self.normalizedFileExtension(
            try container.decodeIfPresent(String.self, forKey: .defaultFileExtension)
        )
        let urlPrefixes = try container.decodeIfPresent([String].self, forKey: .urlPrefixes) ?? []

        if let compactRows = try? container.decode([SolanaCompactTokenRow].self, forKey: .items) {
            items = compactRows.map { row in
                SolanaTokenItem(
                    id: row.id,
                    url: row.url(prefixes: urlPrefixes),
                    fileExtension: row.fileExtension
                )
            }
        } else {
            items = try container.decode([SolanaTokenItem].self, forKey: .items).map { item in
                SolanaTokenItem(
                    id: item.id,
                    url: item.url,
                    fileExtension: Self.normalizedFileExtension(item.fileExtension)
                )
            }
        }
    }

    private static func normalizedFileExtension(_ value: String?) -> String? {
        SolanaMediaFileExtension.normalized(value)
    }
}

private struct SolanaTokenItem: Codable, Hashable {
    let id: String
    let url: String
    let fileExtension: String?

    func resolvedFileExtension(defaultFileExtension: String?) -> String? {
        SolanaMediaFileExtension.explicitPathExtension(in: url)
            ?? SolanaMediaFileExtension.normalized(fileExtension)
            ?? defaultFileExtension
    }
}

private struct SolanaCompactTokenRow: Decodable {
    let id: String
    let prefixIndex: Int
    let urlSuffix: String
    let fileExtension: String?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        prefixIndex = try container.decode(Int.self)
        urlSuffix = try container.decode(String.self)
        fileExtension = SolanaMediaFileExtension.normalized(try? container.decode(String.self))
    }

    func url(prefixes: [String]) -> String {
        guard prefixes.indices.contains(prefixIndex) else { return urlSuffix }
        return prefixes[prefixIndex] + urlSuffix
    }
}

private struct SolanaCollectionTokenData {
    let defaultFileExtension: String?
    let tokens: [SolanaTokenItem]
    let tokenIndicesById: [String: Int]

    init(defaultFileExtension: String?, tokens: [SolanaTokenItem]) {
        self.defaultFileExtension = defaultFileExtension
        self.tokens = tokens

        var tokenIndicesById = [String: Int]()
        for (index, token) in tokens.enumerated() where tokenIndicesById[token.id] == nil {
            tokenIndicesById[token.id] = index
        }
        self.tokenIndicesById = tokenIndicesById
    }
}

private enum SolanaMediaFileExtension {
    private static let staticImageExtensions = Set(["png", "jpg", "jpeg", "webp", "heic", "heif"])
    private static let animatedImageExtensions = Set(["gif"])

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t\r")).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func explicitPathExtension(in urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        return normalized(url.pathExtension)
    }

    static func isStaticImage(_ fileExtension: String) -> Bool {
        staticImageExtensions.contains(fileExtension)
    }

    static func isAnimatedImage(_ fileExtension: String) -> Bool {
        animatedImageExtensions.contains(fileExtension)
    }
}

enum SolanaTokenHTML {
    static func createImageHTML(imageURL: String, nextImageURL: String?) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #tokenImage {
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
        }
        </style>
        </head>
        <body>
        <img id="tokenImage" alt="">
        <script>
        const imageURL = \(javaScriptStringLiteral(imageURL));
        const nextImageURL = \(javaScriptStringLiteral(nextImageURL));
        const tokenImage = document.getElementById("tokenImage");
        tokenImage.decoding = "async";
        tokenImage.src = imageURL;

        if (nextImageURL) {
            const preloadImage = new Image();
            preloadImage.decoding = "async";
            preloadImage.src = nextImageURL;
        }
        </script>
        </body>
        </html>
        """
    }

    private static func javaScriptStringLiteral(_ value: String?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              var literal = String(data: data, encoding: .utf8) else {
            return "null"
        }
        literal = literal.replacingOccurrences(of: "</", with: "<\\/")
        return literal
    }
}
