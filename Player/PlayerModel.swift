// ∅ 2026 lil org

import SwiftUI

class PlayerModel: ObservableObject {
    
    let specificCollectionId: String?
    
    @Published var currentToken: GeneratedToken
    @Published var history: [GeneratedToken]
    @Published var currentIndex: Int = 0
    @Published var showingInfoPopover = false

    init(specificCollectionId: String?, notTokenId: String?) {
        let token = Self.generateRandomToken(
            specificCollectionId: specificCollectionId,
            notTokenId: notTokenId
        ) ?? GeneratedToken.empty
        self.currentToken = token
        self.history = [token]
        self.specificCollectionId = specificCollectionId
    }
    
    init(token: GeneratedToken) {
        self.currentToken = token
        self.history = [token]
        self.specificCollectionId = token.fullCollectionId
    }

    var playerWindowTitle: String {
        let collectionName = currentToken.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = currentToken.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle: String
        if !collectionName.isEmpty {
            baseTitle = collectionName
        } else if !displayName.isEmpty {
            baseTitle = displayName
        } else {
            baseTitle = Strings.nftFolder
        }

#if os(macOS)
        guard !currentToken.fullCollectionId.isEmpty,
              !currentToken.id.isEmpty,
              let tokenIndex = CollectionCatalog.tokenIndex(
                specificCollectionId: currentToken.fullCollectionId,
                tokenId: currentToken.id
              ) else {
            return baseTitle
        }

        let tokenCount = CollectionCatalog.tokenCount(specificCollectionId: currentToken.fullCollectionId)
        guard tokenCount > 0 else { return baseTitle }

        return "\(baseTitle) \(Strings.pagePosition(current: tokenIndex + 1, total: tokenCount))"
#else
        return baseTitle
#endif
    }
    
    func showInitialCollection() {
        let newToken = Self.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: nil) ?? currentToken
        showNewToken(newToken)
    }
    
    func goBack() {
        if currentIndex > 0 {
            currentIndex -= 1
            currentToken = history[currentIndex]
        }
        showingInfoPopover = false
    }

    func goForward() {
        if currentIndex < history.count - 1 {
            currentIndex += 1
            currentToken = history[currentIndex]
        } else {
            let newToken = Self.generateRandomToken(
                specificCollectionId: currentToken.fullCollectionId,
                notTokenId: currentToken.id
            ) ?? currentToken
            history.append(newToken)
            currentIndex = history.count - 1
            currentToken = newToken
            freeUpHistoryIfNeeded()
        }
        showingInfoPopover = false
    }
    
    func changeCollection() {
        let newToken = Self.generateRandomToken(specificCollectionId: nil, notTokenId: nil) ?? currentToken
        showNewToken(newToken)
    }
    
    func showNewToken(_ newToken: GeneratedToken) {
        history.append(newToken)
        currentIndex = history.count - 1
        currentToken = newToken
        freeUpHistoryIfNeeded()
        showingInfoPopover = false
    }
    
    private func freeUpHistoryIfNeeded() {
        if history.count > 23 {
            let cutTarget = 10
            history.removeFirst(history.count - cutTarget)
            currentIndex = cutTarget - 1
        }
    }

    private static func generateRandomToken(specificCollectionId: String?, notTokenId: String?) -> GeneratedToken? {
#if os(macOS)
        CollectionCatalog.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: notTokenId)
#else
        TokenGenerator.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: notTokenId)
#endif
    }

}
