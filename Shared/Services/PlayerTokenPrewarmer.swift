// ∅ 2026 lil org

import Foundation

@MainActor
enum PlayerTokenPrewarmer {

    private struct TokenKey: Hashable, Sendable {
        let collectionId: String
        let tokenId: String?
    }

    private static let maximumLaunchTokenPrewarmCount = 2

    private static var didScheduleLaunchPrewarm = false
    private static var requestedKeys = Set<TokenKey>()
    private static var prewarmedTokens = [TokenKey: GeneratedToken]()

    static func scheduleAfterLaunch(continueViewingProgress: PlayerViewingProgress?, initialCollectionIds: [String]) {
        guard !didScheduleLaunchPrewarm else { return }
        didScheduleLaunchPrewarm = true

        var candidates = [TokenKey]()
        let continueCollectionId: String?
        if let continueViewingProgress, !continueViewingProgress.isComplete {
            let tokenKey = TokenKey(collectionId: continueViewingProgress.collectionId, tokenId: continueViewingProgress.tokenId)
            if shouldPrewarm(tokenKey) {
                candidates.append(tokenKey)
            }
            continueCollectionId = continueViewingProgress.collectionId
        } else {
            continueCollectionId = nil
        }
        initialCollectionIds.forEach { collectionId in
            guard collectionId != continueCollectionId else { return }
            let tokenKey = TokenKey(collectionId: collectionId, tokenId: nil)
            guard shouldPrewarm(tokenKey) else { return }
            candidates.append(tokenKey)
        }

        let dedupedCandidates = candidates.reduce(into: [TokenKey]()) { result, candidate in
            guard !result.contains(candidate) else { return }
            result.append(candidate)
        }
        let launchCandidates = Array(
            dedupedCandidates.prefix(maximumLaunchTokenPrewarmCount)
        )
        Task(priority: .utility) {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            for candidate in launchCandidates {
                guard !Task.isCancelled else { return }
                await requestTokenPrewarm(candidate)
            }
        }
    }

    static func preparedToken(initialCollectionId: String?, initialTokenId: String?) -> GeneratedToken? {
        guard let key = tokenKey(collectionId: initialCollectionId, tokenId: initialTokenId) else {
            return nil
        }
        return prewarmedTokens[key]
    }

    private static func tokenKey(collectionId: String?, tokenId: String?) -> TokenKey? {
        guard let collectionId else { return nil }
        return TokenKey(collectionId: collectionId, tokenId: tokenId)
    }

    private static func requestTokenPrewarm(_ key: TokenKey) async {
        guard shouldPrewarm(key) else { return }

        guard prewarmedTokens[key] == nil,
              requestedKeys.insert(key).inserted else {
            return
        }

        guard let token = await generateToken(for: key) else { return }
        prewarmedTokens[key] = token
    }

    @concurrent
    private static func generateToken(for key: TokenKey) async -> GeneratedToken? {
        let tokenIndex: Int
        if let tokenId = key.tokenId {
            guard let requestedTokenIndex = CollectionCatalog.tokenIndex(specificCollectionId: key.collectionId, tokenId: tokenId) else {
                return nil
            }
            tokenIndex = requestedTokenIndex
        } else {
            tokenIndex = 0
        }
        return CollectionCatalog.generateToken(specificCollectionId: key.collectionId, tokenIndex: tokenIndex)
    }

    private static func shouldPrewarm(_ key: TokenKey) -> Bool {
        !CollectionCatalog.isDownloadableCollection(specificCollectionId: key.collectionId)
    }
}
