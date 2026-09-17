// ∅ 2026 lil org

import Foundation
import os

nonisolated enum TokenGenerator {
    
    private static let scriptURLsByCollectionId: [String: URL] = {
        SuggestedItemsService.allItems.reduce(into: [:]) { result, item in
            if let url = SuggestedItemsService.bundledScriptURL(collectionId: item.id) {
                result[item.id] = url
            }
        }
    }()
    private static let cache = OSAllocatedUnfairLock(initialState: CacheState())
    private static let cardNft2NativeCollection = RangedNativeCollection(
        collectionId: NativeMetalCardRenderKind.cardNft2.collectionId,
        tokenCount: { cardNft2RangedTokenCount },
        tokenAtIndex: { cardNft2Token(at: $0) },
        tokenWithID: { cardNft2Token(id: $0) }
    )
    private static let rangedNativeCollectionsById: [String: RangedNativeCollection] = [
        cardNft2NativeCollection.collectionId: cardNft2NativeCollection
    ]
    private static let nativeRendererCollectionIds = Set(NativeMetalCardRenderKind.allCases.map(\.collectionId))

    private struct CacheState: Sendable {
        var collectionDataByCollectionId = [String: CollectionTokenData]()
        var scriptByCollectionId = [String: ScriptCacheEntry]()
    }

    private enum ScriptCacheEntry: Sendable {
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

    private struct RangedNativeCollection: Sendable {
        let collectionId: String
        let tokenCount: @Sendable () -> Int
        let tokenAtIndex: @Sendable (Int) -> BundledTokens.Item?
        let tokenWithID: @Sendable (Int) -> BundledTokens.Item

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

    private static let disablesNativeRenderersOnCurrentPlatform: Bool = {
#if os(watchOS) || os(visionOS) || os(tvOS)
        return true
#else
        return false
#endif
    }()

    private static let generativeCollectionIds: Set<String> = {
        Set(scriptURLsByCollectionId.keys.filter { collectionId in
            !isCollectionDisabledOnCurrentPlatform(id: collectionId)
        })
    }()

    static func canGenerate(id: String) -> Bool {
        return generativeCollectionIds.contains(id)
    }

    static func isBundledWebGenerativeCollection(id: String) -> Bool {
        guard canGenerate(id: id),
              let script = script(specificCollectionId: id) else {
            return false
        }
        return !script.kind.isNativeRenderer
    }

    static func bundledWebGenerativeToken(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> BundledTokens.Item? {
        guard isBundledWebGenerativeCollection(id: specificCollectionId),
              let collectionData = collectionData(specificCollectionId: specificCollectionId),
              collectionData.tokens.indices.contains(tokenIndex) else {
            return nil
        }
        return collectionData.tokens[tokenIndex]
    }

    static func thumbnailAspectRatioProfile(
        specificCollectionId: String
    ) -> ThumbnailAspectRatioProfile? {
        guard !isRangedNativeCollection(specificCollectionId) else { return nil }
        return collectionData(
            specificCollectionId: specificCollectionId
        )?.thumbnailAspectRatioProfile
    }

    static func artworkAspectRatioProfile(specificCollectionId: String) -> ThumbnailAspectRatioProfile? {
        guard !isRangedNativeCollection(specificCollectionId) else { return nil }
        return collectionData(specificCollectionId: specificCollectionId)?.artworkAspectRatioProfile
    }

    static func requiredPersistentDependencies(collectionId: String) -> [PersistentArtworkDependency] {
        guard canGenerate(id: collectionId), let script = script(specificCollectionId: collectionId) else { return [] }
        return RawHtmlGenerator.requiredDependencies(for: script)
    }

    static func usesArtBlocksRenderer(collectionId: String) -> Bool {
        guard canGenerate(id: collectionId) else { return false }
        return script(specificCollectionId: collectionId)?.usesArtBlocksRenderer == true
    }

    static func legacyArtBlocksCollectionId(collectionId: String) -> String? {
        guard canGenerate(id: collectionId) else { return nil }
        return script(specificCollectionId: collectionId)?.legacyArtBlocksCollectionId
    }

    static func isCollectionDisabledOnCurrentPlatform(id: String) -> Bool {
        if !SuggestedItemsService.isCollectionAvailableOnCurrentPlatform(id: id)
            || platformDisabledCollectionIds.contains(id) {
            return true
        }
        guard disablesNativeRenderersOnCurrentPlatform else {
            return false
        }
        return nativeRendererCollectionIds.contains(id)
    }

    static let allGenerativeSuggestedItems = SuggestedItemsService.visibleItems.filter {
        canGenerate(id: $0.id)
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

#if os(macOS)
    static func tokenIdentity(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> (collectionName: String, tokenId: String)? {
        guard let source = tokenSource(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }
        return (source.script.name, source.token.id)
    }
#endif

    static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        guard let source = tokenSource(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }
        return generateToken(source.token, script: source.script)
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

    static func collectionWebURL(specificCollectionId: String) -> URL? {
        guard let script = script(specificCollectionId: specificCollectionId) else { return nil }
        if script.chain == .solana {
            return URL(string: "https://explorer.solana.com/address/\(script.address)")
        }
        let network = SuggestedItemsService.item(id: script.id)?.network ?? .mainnet
        return NftGallery.blockExplorer.url(network: network, chain: .ethereum, collectionAddress: script.address, tokenId: nil)
    }

    private static func isRangedNativeCollection(_ specificCollectionId: String) -> Bool {
        rangedNativeCollectionsById[specificCollectionId] != nil
    }

    private static func activeRangedNativeCollection(specificCollectionId: String) -> RangedNativeCollection? {
        guard let collection = rangedNativeCollectionsById[specificCollectionId],
              collection.count > 0,
              canGenerate(id: specificCollectionId) else { return nil }
        return collection
    }

    private static func tokenSource(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> (token: BundledTokens.Item, script: Script)? {
        if isRangedNativeCollection(specificCollectionId) {
            guard let collection = activeRangedNativeCollection(
                specificCollectionId: specificCollectionId
            ),
                  let script = script(specificCollectionId: specificCollectionId),
                  let token = collection.token(at: tokenIndex) else {
                return nil
            }
            return (token, script)
        }

        guard let collectionData = collectionData(
            specificCollectionId: specificCollectionId
        ),
              collectionData.tokens.indices.contains(tokenIndex) else {
            return nil
        }
        return (collectionData.tokens[tokenIndex], collectionData.script)
    }

    private static let cardNft2RangedTokenCount: Int = {
#if os(watchOS) || os(visionOS) || os(tvOS)
        return 0
#else
        return CardNft2CardMetadata.tokenCount
#endif
    }()

    private static func cardNft2Token(at tokenIndex: Int) -> BundledTokens.Item? {
        guard tokenIndex >= 0,
              tokenIndex < cardNft2RangedTokenCount else { return nil }
        return cardNft2Token(id: tokenIndex + 1)
    }

    private static func cardNft2Token(id tokenID: Int) -> BundledTokens.Item {
        BundledTokens.Item(id: String(tokenID), name: nil, url: nil, sh: nil, hash: nil)
    }

    private static func collectionData(specificCollectionId: String) -> CollectionTokenData? {
        if let collectionData = cache.withLock({ $0.collectionDataByCollectionId[specificCollectionId] }) {
            return collectionData
        }

        guard let script = script(specificCollectionId: specificCollectionId),
              let tokens = bundledTokens(script: script) else { return nil }

        let collectionData = CollectionTokenData(script: script, tokens: tokens)
        return cache.withLock { state in
            if let cachedCollectionData = state.collectionDataByCollectionId[specificCollectionId] {
                return cachedCollectionData
            }
            state.collectionDataByCollectionId[specificCollectionId] = collectionData
            return collectionData
        }
    }

    private static func script(specificCollectionId: String) -> Script? {
        guard canGenerate(id: specificCollectionId) else { return nil }
        if let cachedEntry = cache.withLock({ $0.scriptByCollectionId[specificCollectionId] }) {
            return cachedEntry.script
        }

        let decodedScript = scriptURLsByCollectionId[specificCollectionId].flatMap { try? Data(contentsOf: $0) }.flatMap {
            try? JSONDecoder().decode(Script.self, from: $0)
        }
        let entry: ScriptCacheEntry = decodedScript.map(ScriptCacheEntry.found) ?? .missing
        return cache.withLock { state in
            if let cachedEntry = state.scriptByCollectionId[specificCollectionId] {
                return cachedEntry.script
            }
            state.scriptByCollectionId[specificCollectionId] = entry
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
                                            renderKind: renderKind)
        return generatedToken
    }

    private static func webURL(script: Script, token: BundledTokens.Item) -> URL? {
        if script.chain == .solana {
            return URL(string: "https://explorer.solana.com/address/\(script.address)")
        }

        let network = SuggestedItemsService.item(id: script.id)?.network ?? .mainnet
        return NftGallery.blockExplorer.url(network: network, chain: .ethereum, collectionAddress: script.address, tokenId: token.id)
    }
    
}

nonisolated private struct CollectionTokenData: Sendable {
    let script: Script
    let tokens: [BundledTokens.Item]
    let tokenIndicesById: [String: Int]
    let thumbnailAspectRatioProfile: ThumbnailAspectRatioProfile?
    let artworkAspectRatioProfile: ThumbnailAspectRatioProfile?

    init(script: Script, tokens: [BundledTokens.Item]) {
        self.script = script
        self.tokens = tokens

        var tokenIndicesById = [String: Int]()
        var aspectRatioProfileBuilder = ThumbnailAspectRatioProfileBuilder()
        var artworkAspectRatioProfileBuilder = ThumbnailAspectRatioProfileBuilder()
        for (index, token) in tokens.enumerated() {
            aspectRatioProfileBuilder.append(token.thumbnailAspectRatio)
            artworkAspectRatioProfileBuilder.append(token.artworkAspectRatio ?? token.thumbnailAspectRatio)
            if tokenIndicesById[token.id] == nil {
                tokenIndicesById[token.id] = index
            }
        }
        self.tokenIndicesById = tokenIndicesById
        self.thumbnailAspectRatioProfile = aspectRatioProfileBuilder.profile
        self.artworkAspectRatioProfile = artworkAspectRatioProfileBuilder.profile
    }
}
