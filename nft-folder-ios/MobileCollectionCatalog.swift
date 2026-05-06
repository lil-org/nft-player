// ∅ 2026 lil org

import Foundation

struct MobileCollectionItem: Hashable, Identifiable {
    let id: String
    let name: String
    let coverAssetName: String
    let isSolana: Bool

    init(generative item: SuggestedItem) {
        id = item.id
        name = item.name
        coverAssetName = item.id
        isSolana = false
    }

    init(solana item: SolanaCollectionIndexItem) {
        id = item.id
        name = item.name
        coverAssetName = item.coverAssetName
        isSolana = true
    }
}

enum MobileCollectionCatalog {
    private static let shuffleLock = NSLock()
    private static var currentPassCollectionIds = Set<String>()

    static let allItems: [MobileCollectionItem] = {
        TokenGenerator.allGenerativeSuggestedItems.map(MobileCollectionItem.init(generative:))
            + SolanaCollectionService.collections.map(MobileCollectionItem.init(solana:))
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
}

struct SolanaCollectionIndexItem: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let coverAssetName: String
    let tokenCount: Int
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
        let solscanURL = URL(string: "https://solscan.io/token/\(token.id)?cluster=mainnet")

        return GeneratedToken(
            fullCollectionId: collection.id,
            collectionName: collection.name,
            address: collection.id,
            id: token.id,
            html: SolanaTokenHTML.createImageHTML(imageURL: token.url, nextImageURL: nextImageURL),
            displayName: "\(collection.name) \(displayTokenId)",
            displayTokenId: displayTokenId,
            url: solscanURL,
            instructions: nil,
            screensaver: nil
        )
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
        guard let url = bundle.url(forResource: "index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SolanaCollectionsIndexPayload.self, from: data) else {
            return SolanaCollectionsIndex(collections: [])
        }
        return SolanaCollectionsIndex(collections: payload.collections)
    }

    private static func loadTokenData(collectionId: String) -> SolanaCollectionTokenData? {
        guard let url = bundle.url(forResource: collectionId, withExtension: "json", subdirectory: "Tokens"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SolanaCollectionTokensPayload.self, from: data) else {
            return nil
        }
        return SolanaCollectionTokenData(tokens: payload.items)
    }

    private static var bundle: Bundle {
        guard let bundleURL = Bundle.main.url(forResource: "SolanaCollections", withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL) else {
            return .main
        }
        return bundle
    }
}

private struct SolanaCollectionsIndexPayload: Codable {
    let collections: [SolanaCollectionIndexItem]
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
    let items: [SolanaTokenItem]

    enum CodingKeys: String, CodingKey {
        case items
        case urlPrefixes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlPrefixes = try container.decodeIfPresent([String].self, forKey: .urlPrefixes) ?? []

        if let compactRows = try? container.decode([SolanaCompactTokenRow].self, forKey: .items) {
            items = compactRows.map { row in
                SolanaTokenItem(id: row.id, url: row.url(prefixes: urlPrefixes))
            }
        } else {
            items = try container.decode([SolanaTokenItem].self, forKey: .items)
        }
    }
}

private struct SolanaTokenItem: Codable, Hashable {
    let id: String
    let url: String
}

private struct SolanaCompactTokenRow: Decodable {
    let id: String
    let prefixIndex: Int
    let urlSuffix: String

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        prefixIndex = try container.decode(Int.self)
        urlSuffix = try container.decode(String.self)
    }

    func url(prefixes: [String]) -> String {
        guard prefixes.indices.contains(prefixIndex) else { return urlSuffix }
        return prefixes[prefixIndex] + urlSuffix
    }
}

private struct SolanaCollectionTokenData {
    let tokens: [SolanaTokenItem]
    let tokenIndicesById: [String: Int]

    init(tokens: [SolanaTokenItem]) {
        self.tokens = tokens

        var tokenIndicesById = [String: Int]()
        for (index, token) in tokens.enumerated() where tokenIndicesById[token.id] == nil {
            tokenIndicesById[token.id] = index
        }
        self.tokenIndicesById = tokenIndicesById
    }
}

private enum SolanaTokenHTML {
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
            background: #000;
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
