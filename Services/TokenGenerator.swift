// ∅ 2026 lil org

import Foundation
import os

nonisolated enum TokenGenerator {
    
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
        Set(SuggestedItemsService.allItems.compactMap { item in
            guard let metadata = item.script,
                  !isCollectionDisabledOnCurrentPlatform(id: item.id),
                  metadata.kind.isNativeRenderer || item.scriptDependency != nil else {
                return nil
            }
            return item.id
        })
    }()

    static func canGenerate(id: String) -> Bool {
        return generativeCollectionIds.contains(id)
    }

    static func isBundledWebGenerativeCollection(id: String) -> Bool {
        guard canGenerate(id: id),
              let metadata = SuggestedItemsService.item(id: id)?.script else {
            return false
        }
        return !metadata.kind.isNativeRenderer
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
        return collectionData.tokens[tokenIndex].resolvingAspectRatio(
            default: collectionData.item.aspectRatio
        )
    }

    static func aspectRatioProfile(
        specificCollectionId: String
    ) -> AspectRatioProfile? {
        guard !isRangedNativeCollection(specificCollectionId),
              let item = generativeItem(specificCollectionId: specificCollectionId) else { return nil }
        return BundledTokenMetadata.aspectRatioProfile(
            count: item.bundledTokenCount,
            isUniform: item.hasUniformAspectRatio,
            defaultAspectRatio: item.aspectRatio
        ) {
            collectionData(specificCollectionId: specificCollectionId)?.aspectRatioProfile
        }
    }

    static func needsArtworkPreparation(collectionId: String) -> Bool {
        isBundledWebGenerativeCollection(id: collectionId)
    }

    static func usesArtBlocksRenderer(collectionId: String) -> Bool {
        guard canGenerate(id: collectionId) else { return false }
        return SuggestedItemsService.item(id: collectionId)?.script?.renderingProfile == .artBlocks
    }

    static func legacyArtBlocksCollectionId(collectionId: String) -> String? {
        guard usesArtBlocksRenderer(collectionId: collectionId),
              let item = SuggestedItemsService.item(id: collectionId) else { return nil }
        return item.address + "-dev-good-" + String(item.chainId) + "-" + item.scriptProjectId
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
        guard let item = generativeItem(specificCollectionId: specificCollectionId) else { return 0 }
        return BundledTokenMetadata.count(item.bundledTokenCount) {
            collectionData(specificCollectionId: specificCollectionId)?.tokens.count ?? 0
        }
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
        return (source.item.name, source.token.id)
    }
#endif

    static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        guard let source = tokenSource(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }
        return generateToken(source.token, item: source.item)
    }
    
    static func generateRandomToken(specificCollectionId: String, notTokenId: String?) -> GeneratedToken? {
        if isRangedNativeCollection(specificCollectionId) {
            guard let collection = activeRangedNativeCollection(specificCollectionId: specificCollectionId) else { return nil }
            guard let item = generativeItem(specificCollectionId: specificCollectionId),
                  let token = collection.randomToken(notTokenId: notTokenId) else { return nil }
            return generateToken(token, item: item)
        }

        guard let collectionData = collectionData(specificCollectionId: specificCollectionId),
              var randomToken = collectionData.tokens.randomElement() else { return nil }
        
        if randomToken.id == notTokenId, let another = collectionData.tokens.randomElement() {
            randomToken = another
        }
        
        return generateToken(randomToken, item: collectionData.item)
    }

    static func collectionWebURL(specificCollectionId: String) -> URL? {
        guard let item = generativeItem(specificCollectionId: specificCollectionId) else { return nil }
        if item.chain == .solana {
            return URL(string: "https://explorer.solana.com/address/\(item.address)")
        }
        return NftGallery.blockExplorer.url(network: item.network, chain: .ethereum, collectionAddress: item.address, tokenId: nil)
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
    ) -> (token: BundledTokens.Item, item: SuggestedItem)? {
        if isRangedNativeCollection(specificCollectionId) {
            guard let collection = activeRangedNativeCollection(
                specificCollectionId: specificCollectionId
            ),
                  let item = generativeItem(specificCollectionId: specificCollectionId),
                  let token = collection.token(at: tokenIndex) else {
                return nil
            }
            return (token, item)
        }

        guard let collectionData = collectionData(
            specificCollectionId: specificCollectionId
        ),
              collectionData.tokens.indices.contains(tokenIndex) else {
            return nil
        }
        return (collectionData.tokens[tokenIndex], collectionData.item)
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
        BundledTokens.Item(id: String(tokenID), name: nil, hash: nil)
    }

    static func prepareCollection(collectionId: String, tokens: BundledTokens) {
        guard let item = generativeItem(specificCollectionId: collectionId),
              !isRangedNativeCollection(collectionId),
              cache.withLock({ $0.collectionDataByCollectionId[collectionId] }) == nil else { return }
        let collectionData = CollectionTokenData(item: item, tokens: tokens.items)
        cache.withLock { state in
            state.collectionDataByCollectionId[collectionId] = collectionData
        }
    }

    private static func collectionData(specificCollectionId: String) -> CollectionTokenData? {
        cache.withLock { $0.collectionDataByCollectionId[specificCollectionId] }
    }

#if DEBUG
    static func removePreparedCollection(collectionId: String) {
        _ = cache.withLock { $0.collectionDataByCollectionId.removeValue(forKey: collectionId) }
    }
#endif

    private static func generativeItem(specificCollectionId: String) -> SuggestedItem? {
        guard canGenerate(id: specificCollectionId) else { return nil }
        return SuggestedItemsService.item(id: specificCollectionId)
    }
    
    private static func generateToken(_ token: BundledTokens.Item, item: SuggestedItem) -> GeneratedToken? {
        guard let metadata = item.script else { return nil }
        let renderKind = metadata.kind.generatedTokenRenderKind
        let html: String
        if metadata.kind.isNativeRenderer {
            html = ""
        } else {
            guard let dependency = item.scriptDependency else { return nil }
            html = ArtworkContentResolver.reference(collectionId: item.id, tokenId: token.id, sha256: dependency.sha256)
        }
        let projectId = item.scriptProjectId
        let cleanId = (token.id.hasPrefix(projectId) && token.id != projectId) ? String(token.id.dropFirst(projectId.count).drop(while: { $0 == "0" })) : token.id
        let displayTokenId = "#" + (cleanId.isEmpty ? "0" : cleanId)
        let name = item.name + " " + displayTokenId
        
        let webURL = webURL(item: item, token: token)
        let generatedToken = GeneratedToken(fullCollectionId: item.id,
                                            collectionName: item.name,
                                            address: item.address,
                                            id: token.id,
                                            html: html,
                                            displayName: name,
                                            displayTokenId: displayTokenId,
                                            url: webURL,
                                            renderKind: renderKind)
        return generatedToken
    }

    private static func webURL(item: SuggestedItem, token: BundledTokens.Item) -> URL? {
        if item.chain == .solana {
            return URL(string: "https://explorer.solana.com/address/\(item.address)")
        }

        return NftGallery.blockExplorer.url(network: item.network, chain: .ethereum, collectionAddress: item.address, tokenId: token.id)
    }
    
}

nonisolated private struct CollectionTokenData: Sendable {
    let item: SuggestedItem
    let tokens: [BundledTokens.Item]
    let tokenIndicesById: [String: Int]
    let aspectRatioProfile: AspectRatioProfile?

    init(item: SuggestedItem, tokens: [BundledTokens.Item]) {
        self.item = item
        self.tokens = tokens

        var tokenIndicesById = [String: Int]()
        var aspectRatioProfileBuilder = AspectRatioProfileBuilder()
        for (index, token) in tokens.enumerated() {
            aspectRatioProfileBuilder.append(token.aspectRatio ?? item.aspectRatio)
            if tokenIndicesById[token.id] == nil {
                tokenIndicesById[token.id] = index
            }
        }
        self.tokenIndicesById = tokenIndicesById
        self.aspectRatioProfile = aspectRatioProfileBuilder.profile
    }
}
