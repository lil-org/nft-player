// ∅ 2026 lil org

import SwiftUI

class PlayerModel: ObservableObject {
    
    let specificCollectionId: String?
    let continueViewingCollectionId: String?
    private(set) var widgetTokenInsertion: PlayerWidgetTokenInsertion?
    
    @Published var currentToken: GeneratedToken
    @Published var history: [GeneratedToken]
    @Published var currentIndex: Int = 0
    @Published var showingInfoPopover = false
    @Published private(set) var isCurrentTokenInsertedWidgetToken = false
    private static let historyTrimThreshold = 23
    private static let retainedHistoryCount = 10
    private var restartSuppressedCollectionId: String?

    init(specificCollectionId: String?, notTokenId: String?) {
        let token = Self.generateRandomToken(
            specificCollectionId: specificCollectionId,
            notTokenId: notTokenId
        ) ?? GeneratedToken.empty
        self.currentToken = token
        self.history = [token]
        self.specificCollectionId = specificCollectionId
        self.continueViewingCollectionId = specificCollectionId
        self.widgetTokenInsertion = nil
    }

    init(collectionId: String, initialTokenId: String? = nil, continueViewingCollectionId: String? = nil) {
        let token = Self.initialToken(collectionId: collectionId, initialTokenId: initialTokenId) ?? GeneratedToken.empty
        self.currentToken = token
        self.history = [token]
        self.specificCollectionId = collectionId
        self.continueViewingCollectionId = continueViewingCollectionId ?? collectionId
        self.widgetTokenInsertion = nil
    }
    
    init(token: GeneratedToken) {
        self.currentToken = token
        self.history = [token]
        self.specificCollectionId = token.fullCollectionId
        self.continueViewingCollectionId = token.fullCollectionId
        self.widgetTokenInsertion = nil
    }

    init(widgetTokenInsertion: PlayerWidgetTokenInsertion) {
        self.currentToken = widgetTokenInsertion.insertedToken
        self.history = [widgetTokenInsertion.insertedToken]
        self.specificCollectionId = widgetTokenInsertion.collectionId
        self.continueViewingCollectionId = widgetTokenInsertion.collectionId
        self.widgetTokenInsertion = widgetTokenInsertion
        self.isCurrentTokenInsertedWidgetToken = true
    }

    var playerWindowTitle: String {
        playerWindowTitle(for: currentToken)
    }

    func playerWindowTitle(for token: GeneratedToken) -> String {
        let collectionName = token.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = token.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle: String
        if !collectionName.isEmpty {
            baseTitle = collectionName
        } else if !displayName.isEmpty {
            baseTitle = displayName
        } else {
            baseTitle = Strings.nftFolder
        }

#if os(macOS)
        guard let tokenContext = CollectionCatalog.tokenContext(for: token) else {
            return baseTitle
        }

        let pagePosition = shouldMaskPagePosition(for: token)
            ? Strings.maskedPagePosition(total: tokenContext.tokenCount)
            : Strings.pagePosition(current: tokenContext.tokenIndex + 1, total: tokenContext.tokenCount)
        return "\(baseTitle) \(pagePosition)"
#else
        return baseTitle
#endif
    }
    
    func showInitialCollection() {
#if os(macOS)
        let newToken = specificCollectionId
            .flatMap { Self.generateToken(specificCollectionId: $0, tokenIndex: 0) }
            ?? Self.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: nil)
            ?? currentToken
#else
        let newToken = Self.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: nil) ?? currentToken
#endif
        clearWidgetTokenInsertion()
        showNewToken(newToken)
    }
    
    func goBack() {
#if os(macOS)
        if currentIndex > 0 {
            currentIndex -= 1
            currentToken = history[currentIndex]
        } else if let previousToken = adjacentToken(offset: -1) {
            history.insert(previousToken, at: 0)
            currentToken = previousToken
            trimHistoryAfterCurrentIfNeeded()
        }
#else
        if currentIndex > 0 {
            currentIndex -= 1
            currentToken = history[currentIndex]
        }
#endif
        showingInfoPopover = false
    }

    func goForward() {
#if os(macOS)
        if currentIndex < history.count - 1 {
            currentIndex += 1
            currentToken = history[currentIndex]
        } else if let nextToken = adjacentToken(offset: 1) {
            history.append(nextToken)
            currentIndex = history.count - 1
            currentToken = nextToken
            trimHistoryBeforeCurrentIfNeeded()
        }
#else
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
            trimHistoryBeforeCurrentIfNeeded()
        }
#endif
        showingInfoPopover = false
    }
    
    func changeCollection() {
#if os(macOS)
        let newToken = CollectionCatalog
            .nextShuffledCollectionId()
            .flatMap { Self.generateToken(specificCollectionId: $0, tokenIndex: 0) }
            ?? currentToken
#else
        let newToken = Self.generateRandomToken(specificCollectionId: nil, notTokenId: nil) ?? currentToken
#endif
        clearWidgetTokenInsertion()
        showNewToken(newToken)
    }
    
    func showNewToken(_ newToken: GeneratedToken) {
        setCurrentTokenInsertedWidgetToken(false)
        history.append(newToken)
        currentIndex = history.count - 1
        currentToken = newToken
        trimHistoryBeforeCurrentIfNeeded()
        showingInfoPopover = false
    }

    func showPagedToken(_ token: GeneratedToken, isInsertedWidgetToken: Bool = false) {
        guard currentToken != token || isCurrentTokenInsertedWidgetToken != isInsertedWidgetToken else { return }

        if currentToken == token {
            setCurrentTokenInsertedWidgetToken(isInsertedWidgetToken)
            showingInfoPopover = false
            return
        }

        if currentIndex > 0, history[currentIndex - 1] == token {
            currentIndex -= 1
        } else if currentIndex < history.count - 1, history[currentIndex + 1] == token {
            currentIndex += 1
        } else {
            if currentIndex < history.count - 1 {
                history.removeLast(history.count - currentIndex - 1)
            }
            history.append(token)
            currentIndex = history.count - 1
            trimHistoryBeforeCurrentIfNeeded()
        }

        setCurrentTokenInsertedWidgetToken(isInsertedWidgetToken)
        currentToken = token
        showingInfoPopover = false
    }

    var currentProgress: PlayerViewingProgress? {
        if isCurrentTokenInsertedWidgetToken,
           let widgetTokenInsertion {
            return widgetTokenInsertion.updatedAnchorProgress()
        }
        return progress(for: currentToken)
    }

    func progress(for token: GeneratedToken) -> PlayerViewingProgress? {
        guard !token.fullCollectionId.isEmpty,
              let tokenIndex = Self.tokenIndex(
                specificCollectionId: token.fullCollectionId,
                tokenId: token.id
              ) else {
            return nil
        }

        let tokenCount = Self.tokenCount(specificCollectionId: token.fullCollectionId)
        guard tokenCount > 0 else { return nil }
        return PlayerViewingProgress(
            collectionId: token.fullCollectionId,
            collectionName: token.collectionName,
            tokenId: token.id,
            tokenIndex: tokenIndex,
            tokenCount: tokenCount,
            updatedAt: Date()
        )
    }

    @discardableResult
    func markCurrentTokenViewed() -> PlayerViewingProgress? {
        markTokenViewed(currentToken)
    }

    @discardableResult
    func markTokenViewed(_ token: GeneratedToken) -> PlayerViewingProgress? {
        let progress = shouldMaskPagePosition(for: token)
            ? widgetTokenInsertion?.updatedAnchorProgress()
            : progress(for: token)
        guard let progress else { return nil }
        PlayerViewingProgressStore.save(progress)
        updateContinueViewingCollection(for: progress)
        return progress
    }

    func restartCollection() {
        guard !currentToken.fullCollectionId.isEmpty,
              let firstToken = Self.generateToken(specificCollectionId: currentToken.fullCollectionId, tokenIndex: 0) else {
            return
        }

        restartSuppressedCollectionId = currentToken.fullCollectionId
        PlayerViewingProgressStore.recordContinueViewingClearedForSync()
        clearWidgetTokenInsertion()
        history = [firstToken]
        currentIndex = 0
        currentToken = firstToken
        showingInfoPopover = false
    }
    
    private func trimHistoryBeforeCurrentIfNeeded() {
        guard history.count > Self.historyTrimThreshold else { return }

        let removedCount = history.count - Self.retainedHistoryCount
        history.removeFirst(removedCount)
        currentIndex = max(currentIndex - removedCount, 0)
    }

    private func trimHistoryAfterCurrentIfNeeded() {
        guard history.count > Self.historyTrimThreshold else { return }

        history.removeLast(history.count - Self.retainedHistoryCount)
        currentIndex = min(currentIndex, history.count - 1)
    }

    private func clearWidgetTokenInsertion() {
        widgetTokenInsertion = nil
        setCurrentTokenInsertedWidgetToken(false)
    }

    private func setCurrentTokenInsertedWidgetToken(_ isInsertedWidgetToken: Bool) {
        guard isCurrentTokenInsertedWidgetToken != isInsertedWidgetToken else { return }
        isCurrentTokenInsertedWidgetToken = isInsertedWidgetToken
    }

    private func adjacentToken(offset: Int) -> GeneratedToken? {
        if isCurrentTokenInsertedWidgetToken,
           let widgetTokenInsertion {
            let targetIndex = widgetTokenInsertion.tokenIndex(adjacentToInsertedTokenBy: offset)
            guard targetIndex >= 0,
                  targetIndex < widgetTokenInsertion.anchorProgress.tokenCount else {
                return nil
            }
            return Self.generateToken(specificCollectionId: widgetTokenInsertion.collectionId, tokenIndex: targetIndex)
        }

        guard let currentProgress else { return nil }
        let targetIndex = currentProgress.tokenIndex + offset
        guard targetIndex >= 0, targetIndex < currentProgress.tokenCount else { return nil }
        return Self.generateToken(specificCollectionId: currentProgress.collectionId, tokenIndex: targetIndex)
    }

    private func shouldMaskPagePosition(for token: GeneratedToken) -> Bool {
        isCurrentTokenInsertedWidgetToken && currentToken == token
    }

    private func updateContinueViewingCollection(for progress: PlayerViewingProgress) {
        if let suppressedCollectionId = restartSuppressedCollectionId {
            guard progress.collectionId == suppressedCollectionId else {
                restartSuppressedCollectionId = nil
                PlayerViewingProgressStore.clearContinueViewingCollectionId()
                return
            }

            guard progress.tokenIndex > 0 else {
                PlayerViewingProgressStore.clearContinueViewingCollectionId()
                return
            }

            restartSuppressedCollectionId = nil
        }

        PlayerViewingProgressStore.updateContinueViewingCollection(
            for: progress,
            expectedCollectionId: continueViewingCollectionId
        )
    }

    private static func generateRandomToken(specificCollectionId: String?, notTokenId: String?) -> GeneratedToken? {
#if os(macOS)
        CollectionCatalog.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: notTokenId)
#else
        TokenGenerator.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: notTokenId)
#endif
    }

    private static func initialToken(collectionId: String, initialTokenId: String?) -> GeneratedToken? {
        if let initialTokenId,
           let tokenIndex = tokenIndex(specificCollectionId: collectionId, tokenId: initialTokenId) {
            return generateToken(specificCollectionId: collectionId, tokenIndex: tokenIndex)
        }

        return generateToken(specificCollectionId: collectionId, tokenIndex: 0)
    }

    private static func tokenIndex(specificCollectionId: String, tokenId: String) -> Int? {
#if os(macOS)
        CollectionCatalog.tokenIndex(specificCollectionId: specificCollectionId, tokenId: tokenId)
#else
        TokenGenerator.tokenIndex(specificCollectionId: specificCollectionId, tokenId: tokenId)
#endif
    }

    private static func tokenCount(specificCollectionId: String) -> Int {
#if os(macOS)
        CollectionCatalog.tokenCount(specificCollectionId: specificCollectionId)
#else
        TokenGenerator.tokenCount(specificCollectionId: specificCollectionId)
#endif
    }

    private static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
#if os(macOS)
        CollectionCatalog.generateToken(specificCollectionId: specificCollectionId, tokenIndex: tokenIndex)
#else
        TokenGenerator.generateToken(specificCollectionId: specificCollectionId, tokenIndex: tokenIndex)
#endif
    }

}
