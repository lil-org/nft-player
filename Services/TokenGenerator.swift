// ∅ 2026 lil org

import Foundation

struct TokenGenerator {
    
    private static let dirURL = SuggestedItemsService.bundle.url(forResource: "Scripts", withExtension: nil)!
    private static var collectionDataCache = [String: CollectionTokenData]()
    private static let collectionDataCacheLock = NSLock()
    private static var scriptCache = [String: ScriptCacheEntry]()
    private static let scriptCacheLock = NSLock()
    private static let ponchoDrifellaNativeCollectionId = "JCTP3kK3xGtWs5mDHxJBuRro38HftaiCDdKsfkXuK2gH"
    private static let cardNft2NativeCollection = RangedNativeCollection(
        collectionId: "EAzEpagtyeRAx9npnpVMpygoA8ouX7DRpLTghhPvYTiu",
        tokenCount: { cardNft2RangedTokenCount },
        tokenAtIndex: { cardNft2Token(at: $0) },
        tokenWithID: { cardNft2Token(id: $0) }
    )
    private static let rangedNativeCollectionsById: [String: RangedNativeCollection] = [
        cardNft2NativeCollection.collectionId: cardNft2NativeCollection
    ]
    private static let nativeRendererCollectionIds: Set<String> = {
        var ids = Set([ponchoDrifellaNativeCollectionId])
        ids.formUnion(rangedNativeCollectionsById.keys)
        return ids
    }()

    private enum ScriptCacheEntry {
        case found(Script)
        case missing

        var script: Script? {
            switch self {
            case let .found(script):
                return script
            case .missing:
                return nil
            }
        }
    }

    private struct RangedNativeCollection {
        let collectionId: String
        let tokenCount: () -> Int
        let tokenAtIndex: (Int) -> BundledTokens.Item?
        let tokenWithID: (Int) -> BundledTokens.Item

        var count: Int {
            tokenCount()
        }

        func token(at tokenIndex: Int) -> BundledTokens.Item? {
            guard tokenIndex >= 0,
                  tokenIndex < count else { return nil }
            return tokenAtIndex(tokenIndex)
        }

        func tokenIndex(for tokenId: String) -> Int? {
            guard let tokenID = Int(tokenId),
                  tokenID >= 1,
                  tokenID <= count else { return nil }
            return tokenID - 1
        }

        func randomToken(notTokenId: String?) -> BundledTokens.Item? {
            let availableCount = count
            guard availableCount > 0 else { return nil }

            var tokenID = Int.random(in: 1...availableCount)
            if availableCount > 1, String(tokenID) == notTokenId {
                let offset = Int.random(in: 1..<availableCount)
                tokenID = ((tokenID - 1 + offset) % availableCount) + 1
            }
            return tokenWithID(tokenID)
        }
    }

    private static let platformDisabledCollectionIds: Set<String> = {
#if os(visionOS)
        return Set([
            "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367650",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270250",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270356",
            "0x99a9b7c1116f9ceeb1652de04d5969cce509b069472",
            "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367667",
        ])
#elseif os(tvOS)
        return Set([
            "0x99a9b7c1116f9ceeb1652de04d5969cce509b069472",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270356",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270250",
        ])
#else
        return Set<String>()
#endif
    }()

    private static var disablesNativeRenderersOnCurrentPlatform: Bool {
#if os(watchOS) || os(visionOS) || os(tvOS)
        return true
#else
        return false
#endif
    }

    private static let jsonsNames: Set<String> = {
        let fileManager = FileManager.default
        let fileURLs = (try? fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)) ?? []
        return Set(fileURLs.compactMap { fileURL in
            let fileName = fileURL.lastPathComponent
            let collectionId = String(fileName.dropLast(5))
            guard !platformDisabledCollectionIds.contains(collectionId) else { return nil }
            if disablesNativeRenderersOnCurrentPlatform,
               nativeRendererCollectionIds.contains(collectionId) {
                return nil
            }
            return fileName
        })
    }()

    static func canGenerate(id: String) -> Bool {
        return jsonsNames.contains(id + ".json")
    }
    
    static func isCollectionDisabledOnCurrentPlatform(id: String) -> Bool {
        if platformDisabledCollectionIds.contains(id) {
            return true
        }
        guard disablesNativeRenderersOnCurrentPlatform else {
            return false
        }
        return nativeRendererCollectionIds.contains(id)
    }

    static var allGenerativeSuggestedItems: [SuggestedItem] {
        return SuggestedItemsService.visibleItems.filter { jsonsNames.contains($0.id + ".json") }
    }
    
    static func tokenCount(specificCollectionId: String) -> Int {
        if isRangedNativeCollection(specificCollectionId) {
            return activeRangedNativeCollection(specificCollectionId: specificCollectionId)?.count ?? 0
        }
        return collectionData(specificCollectionId: specificCollectionId)?.tokens.count ?? 0
    }

    static func tokenIndex(specificCollectionId: String, tokenId: String) -> Int? {
        if isRangedNativeCollection(specificCollectionId) {
            guard let collection = activeRangedNativeCollection(specificCollectionId: specificCollectionId) else { return nil }
            return collection.tokenIndex(for: tokenId)
        }
        return collectionData(specificCollectionId: specificCollectionId)?.tokenIndicesById[tokenId]
    }

    static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        if isRangedNativeCollection(specificCollectionId) {
            guard let collection = activeRangedNativeCollection(specificCollectionId: specificCollectionId) else { return nil }
            guard let script = script(specificCollectionId: specificCollectionId),
                  let token = collection.token(at: tokenIndex) else { return nil }
            return generateToken(token, script: script)
        }

        guard let collectionData = collectionData(specificCollectionId: specificCollectionId),
              collectionData.tokens.indices.contains(tokenIndex) else { return nil }
        return generateToken(collectionData.tokens[tokenIndex], script: collectionData.script)
    }
    
    static func generateRandomToken(specificCollectionId: String, notTokenId: String?) -> GeneratedToken? {
        if isRangedNativeCollection(specificCollectionId) {
            guard let collection = activeRangedNativeCollection(specificCollectionId: specificCollectionId) else { return nil }
            guard let script = script(specificCollectionId: specificCollectionId),
                  let token = collection.randomToken(notTokenId: notTokenId) else { return nil }
            return generateToken(token, script: script)
        }

        guard let collectionData = collectionData(specificCollectionId: specificCollectionId),
              var randomToken = collectionData.tokens.randomElement() else { return nil }
        
        if randomToken.id == notTokenId, let another = collectionData.tokens.randomElement() {
            randomToken = another
        }
        
        return generateToken(randomToken, script: collectionData.script)
    }

    private static func collectionData(specificCollectionId: String) -> CollectionTokenData? {
        collectionData(jsonName: specificCollectionId + ".json")
    }

    private static func isRangedNativeCollection(_ specificCollectionId: String) -> Bool {
        rangedNativeCollectionsById[specificCollectionId] != nil
    }

    private static func activeRangedNativeCollection(specificCollectionId: String) -> RangedNativeCollection? {
        guard let collection = rangedNativeCollectionsById[specificCollectionId],
              collection.count > 0,
              jsonsNames.contains(specificCollectionId + ".json") else { return nil }
        return collection
    }

    private static var cardNft2RangedTokenCount: Int {
#if os(watchOS) || os(visionOS) || os(tvOS)
        return 0
#else
        return CardNft2CardMetadata.tokenCount
#endif
    }

    private static func cardNft2Token(at tokenIndex: Int) -> BundledTokens.Item? {
        guard tokenIndex >= 0,
              tokenIndex < cardNft2RangedTokenCount else { return nil }
        return cardNft2Token(id: tokenIndex + 1)
    }

    private static func cardNft2Token(id tokenID: Int) -> BundledTokens.Item {
        BundledTokens.Item(id: String(tokenID), name: nil, url: nil, sh: nil, hash: nil)
    }

    private static func script(specificCollectionId: String) -> Script? {
        script(jsonName: specificCollectionId + ".json")
    }

    private static func collectionData(jsonName: String) -> CollectionTokenData? {
        if let collectionData = collectionDataCacheLock.withLock({ collectionDataCache[jsonName] }) {
            return collectionData
        }

        guard let script = script(jsonName: jsonName),
              let tokens = bundledTokens(script: script) else { return nil }

        let collectionData = CollectionTokenData(script: script, tokens: tokens)
        return collectionDataCacheLock.withLock {
            if let cachedCollectionData = collectionDataCache[jsonName] {
                return cachedCollectionData
            }
            collectionDataCache[jsonName] = collectionData
            return collectionData
        }
    }

    private static func script(jsonName: String) -> Script? {
        if let cachedEntry = scriptCacheLock.withLock({ scriptCache[jsonName] }) {
            return cachedEntry.script
        }

        let url = dirURL.appendingPathComponent(jsonName)
        let decodedScript = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(Script.self, from: $0)
        }
        let entry: ScriptCacheEntry = decodedScript.map(ScriptCacheEntry.found) ?? .missing
        return scriptCacheLock.withLock {
            if let cachedEntry = scriptCache[jsonName] {
                return cachedEntry.script
            }
            scriptCache[jsonName] = entry
            return decodedScript
        }
    }

    private static func bundledTokens(script: Script) -> [BundledTokens.Item]? {
        SuggestedItemsService.bundledTokens(collectionId: script.id)?.items
    }
    
    private static func generateToken(_ token: BundledTokens.Item, script: Script) -> GeneratedToken? {
        let renderKind = script.kind.generatedTokenRenderKind
        let html = RawHtmlGenerator.createHtml(script: script, token: token)
        let cleanId = (token.id.hasPrefix(script.abId) && token.id != script.abId) ? String(token.id.dropFirst(script.abId.count).drop(while: { $0 == "0" })) : token.id
        let displayTokenId = "#" + (cleanId.isEmpty ? "0" : cleanId)
        let name = script.name + " " + displayTokenId
        
        let webURL = webURL(script: script, token: token)
        let generatedToken = GeneratedToken(fullCollectionId: script.id,
                                            collectionName: script.name,
                                            address: script.address,
                                            id: token.id,
                                            html: html,
                                            displayName: name,
                                            displayTokenId: displayTokenId,
                                            url: webURL,
                                            instructions: script.instructions,
                                            screensaver: script.screensaverUrl,
                                            renderKind: renderKind)
        return generatedToken
    }

    private static func webURL(script: Script, token: BundledTokens.Item) -> URL? {
        if script.chain == .solana {
            return URL(string: "https://explorer.solana.com/address/\(script.address)")
        }

        return NftGallery.blockExplorer.url(network: .mainnet, chain: .ethereum, collectionAddress: script.address, tokenId: token.id)
    }
    
}

private struct CollectionTokenData {
    let script: Script
    let tokens: [BundledTokens.Item]
    let tokenIndicesById: [String: Int]

    init(script: Script, tokens: [BundledTokens.Item]) {
        self.script = script
        self.tokens = tokens

        var tokenIndicesById = [String: Int]()
        for (index, token) in tokens.enumerated() where tokenIndicesById[token.id] == nil {
            tokenIndicesById[token.id] = index
        }
        self.tokenIndicesById = tokenIndicesById
    }
}
