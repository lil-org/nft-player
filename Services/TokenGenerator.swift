// ∅ 2026 lil org

import Foundation

struct TokenGenerator {
    
    private static let ponchoDrifellaCollectionId = "JCTP3kK3xGtWs5mDHxJBuRro38HftaiCDdKsfkXuK2gH"
    private static let dirURL = SuggestedItemsService.bundle.url(forResource: "Scripts", withExtension: nil)!
    private static var collectionDataCache = [String: CollectionTokenData]()
    private static let collectionDataCacheLock = NSLock()
    
    private static let disabledCollectionIds: Set<String> = {
#if os(watchOS)
        return Set([ponchoDrifellaCollectionId])
#elseif os(visionOS)
        return Set([
            "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367650",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270250",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270356",
            "0x99a9b7c1116f9ceeb1652de04d5969cce509b069472",
            "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367667",
            ponchoDrifellaCollectionId,
        ])
#elseif os(tvOS)
        return Set([
            "0x99a9b7c1116f9ceeb1652de04d5969cce509b069472",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270356",
            "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270250",
            ponchoDrifellaCollectionId,
        ])
#else
        return Set<String>()
#endif
    }()

    private static let jsonsNames: Set<String> = {
        let fileManager = FileManager.default
        let fileURLs = (try? fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)) ?? []
        return Set(fileURLs.compactMap { fileURL in
            let fileName = fileURL.lastPathComponent
            let collectionId = String(fileName.dropLast(5))
            return disabledCollectionIds.contains(collectionId) ? nil : fileName
        })
    }()

    static func canGenerate(id: String) -> Bool {
        return jsonsNames.contains(id + ".json")
    }
    
    static func isCollectionDisabledOnCurrentPlatform(id: String) -> Bool {
        return disabledCollectionIds.contains(id)
    }

    static var allGenerativeSuggestedItems: [SuggestedItem] {
        return SuggestedItemsService.visibleItems.filter { jsonsNames.contains($0.id + ".json") }
    }
    
    static func tokenCount(specificCollectionId: String) -> Int {
        collectionData(specificCollectionId: specificCollectionId)?.tokens.count ?? 0
    }

    static func tokenIndex(specificCollectionId: String, tokenId: String) -> Int? {
        collectionData(specificCollectionId: specificCollectionId)?.tokenIndicesById[tokenId]
    }

    static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        guard let collectionData = collectionData(specificCollectionId: specificCollectionId),
              collectionData.tokens.indices.contains(tokenIndex) else { return nil }
        return generateToken(collectionData.tokens[tokenIndex], script: collectionData.script)
    }
    
    static func generateRandomToken(specificCollectionId: String, notTokenId: String?) -> GeneratedToken? {
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
        let url = dirURL.appendingPathComponent(jsonName)
        guard let data = try? Data(contentsOf: url),
              let script = try? JSONDecoder().decode(Script.self, from: data) else { return nil }
        return script
    }

    private static func bundledTokens(script: Script) -> [BundledTokens.Item]? {
        SuggestedItemsService.bundledTokens(collectionId: script.id)?.items
    }
    
    private static func generateToken(_ token: BundledTokens.Item, script: Script) -> GeneratedToken? {
        let usesNativePonchoRenderer = script.kind == .ponchoDrifellaNative
        let html = usesNativePonchoRenderer ? "" : RawHtmlGenerator.createHtml(script: script, token: token)
        let cleanId = (token.id.hasPrefix(script.abId) && token.id != script.abId) ? String(token.id.dropFirst(script.abId.count).drop(while: { $0 == "0" })) : token.id
        let displayTokenId = "#" + (cleanId.isEmpty ? "0" : cleanId)
        let name = script.name + " " + displayTokenId
        let renderKind: GeneratedTokenRenderKind? = usesNativePonchoRenderer ? .ponchoDrifellaMetal : nil
        
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
