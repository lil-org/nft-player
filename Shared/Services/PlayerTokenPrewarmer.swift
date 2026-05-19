// ∅ 2026 lil org

import Foundation

enum PlayerTokenPrewarmer {

    private struct TokenKey: Hashable {
        let collectionId: String
        let tokenId: String?
    }

    private static let queue = DispatchQueue(label: "org.lil.nft-folder.player-token-prewarm", qos: .utility)
    private static let lock = NSLock()
    private static let maximumLaunchTokenPrewarmCount = 2

    private static var didScheduleLaunchPrewarm = false
    private static var requestedKeys = Set<TokenKey>()
    private static var prewarmedTokens = [TokenKey: GeneratedToken]()

    static func scheduleAfterLaunch(continueViewingProgress: PlayerViewingProgress?, initialCollectionIds: [String]) {
        let shouldScheduleTokenPrewarm = lock.withLock {
            guard !didScheduleLaunchPrewarm else { return false }
            didScheduleLaunchPrewarm = true
            return true
        }
        guard shouldScheduleTokenPrewarm else { return }

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
        queue.asyncAfter(deadline: .now() + .milliseconds(1000)) {
            dedupedCandidates.prefix(maximumLaunchTokenPrewarmCount).forEach(requestTokenPrewarm)
        }
    }

    static func preparedToken(initialCollectionId: String?, initialTokenId: String?) -> GeneratedToken? {
        guard let key = tokenKey(collectionId: initialCollectionId, tokenId: initialTokenId) else {
            return nil
        }
        return cachedToken(for: key)
    }

    private static func tokenKey(collectionId: String?, tokenId: String?) -> TokenKey? {
        guard let collectionId else { return nil }
        return TokenKey(collectionId: collectionId, tokenId: tokenId)
    }

    private static func cachedToken(for key: TokenKey) -> GeneratedToken? {
        lock.withLock {
            prewarmedTokens[key]
        }
    }

    private static func requestTokenPrewarm(_ key: TokenKey) {
        guard shouldPrewarm(key) else { return }

        let shouldRequestToken = lock.withLock {
            guard prewarmedTokens[key] == nil, !requestedKeys.contains(key) else { return false }
            requestedKeys.insert(key)
            return true
        }
        guard shouldRequestToken else { return }

        queue.async {
            guard let token = generateToken(for: key) else { return }
            lock.withLock {
                prewarmedTokens[key] = token
            }
        }
    }

    private static func generateToken(for key: TokenKey) -> GeneratedToken? {
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
