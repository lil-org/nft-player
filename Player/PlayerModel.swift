// ∅ 2026 lil org

import Foundation
import Observation

@MainActor @Observable
final class PlayerModel {
    
    private(set) var widgetTokenInsertion: PlayerWidgetTokenInsertion?
    
    var currentToken: GeneratedToken {
        didSet {
            bookmarkController.updateTarget(currentBookmarkTarget)
        }
    }
    var history: [GeneratedToken]
    var currentIndex: Int = 0
    private(set) var isCurrentTokenInsertedWidgetToken = false
    private let bookmarkController = PlayerBookmarkController()
    private static let historyTrimThreshold = 23
    private static let retainedHistoryCount = 10
    private let viewingSessionTracker: PlayerViewingSessionTracker
    @ObservationIgnored private var restartRequestGeneration: UInt = 0

    init(specificCollectionId: String?, notTokenId: String?) {
        let token = Self.generateRandomToken(
            specificCollectionId: specificCollectionId,
            notTokenId: notTokenId
        ) ?? GeneratedToken.empty
        self.currentToken = token
        self.history = [token]
        self.widgetTokenInsertion = nil
        self.viewingSessionTracker = PlayerViewingSessionTracker(continueViewingCollectionId: specificCollectionId)
        configureBookmarkState()
    }

    init(
        collectionId: String,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String? = nil
    ) {
        let token = Self.initialToken(collectionId: collectionId, initialTokenId: initialTokenId) ?? GeneratedToken.empty
        self.currentToken = token
        self.history = [token]
        self.widgetTokenInsertion = nil
        self.viewingSessionTracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: continueViewingCollectionId ?? collectionId
        )
        configureBookmarkState()
    }
    
    init(token: GeneratedToken) {
        self.currentToken = token
        self.history = [token]
        self.widgetTokenInsertion = nil
        self.viewingSessionTracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: token.fullCollectionId
        )
        configureBookmarkState()
    }

    init(widgetTokenInsertion: PlayerWidgetTokenInsertion) {
        self.currentToken = widgetTokenInsertion.insertedToken
        self.history = [widgetTokenInsertion.insertedToken]
        self.widgetTokenInsertion = widgetTokenInsertion
        self.isCurrentTokenInsertedWidgetToken = true
        self.viewingSessionTracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: widgetTokenInsertion.collectionId
        )
        configureBookmarkState()
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
            baseTitle = Strings.nftPlayer
        }

#if os(macOS) || os(tvOS)
        guard let tokenContext = CollectionCatalog.tokenContext(for: token) else {
            return baseTitle
        }

        let pagePosition = Strings.pagePosition(
            current: tokenContext.tokenIndex + 1,
            total: tokenContext.tokenCount
        )
        return "\(baseTitle) \(pagePosition)"
#else
        return baseTitle
#endif
    }
    
    func goBack() {
        cancelPendingCollectionRestart()
#if os(macOS) || os(tvOS)
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
    }

    func goForward() {
        cancelPendingCollectionRestart()
#if os(macOS) || os(tvOS)
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
    }
    
    func showPagedToken(_ token: GeneratedToken, isInsertedWidgetToken: Bool = false) {
        guard currentToken != token || isCurrentTokenInsertedWidgetToken != isInsertedWidgetToken else { return }
        cancelPendingCollectionRestart()

        if currentToken == token {
            setCurrentTokenInsertedWidgetToken(isInsertedWidgetToken)
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
    }

    var currentProgress: PlayerViewingProgress? {
        if isCurrentTokenInsertedWidgetToken,
           let widgetTokenInsertion {
            return widgetTokenInsertion.automaticAnchorProgress()
        }
        return progress(for: currentToken)
    }

    var canBookmarkCurrentToken: Bool {
        Self.canBookmark(token: currentToken)
    }

    var canToggleCurrentTokenBookmark: Bool {
        canBookmarkCurrentToken && bookmarkController.canToggle
    }

    var isCurrentTokenBookmarked: Bool {
        bookmarkController.isBookmarked
    }

    func toggleCurrentTokenBookmark(
        completion: (@MainActor @Sendable (BookmarkTarget, Bool) -> Void)? = nil
    ) {
        bookmarkController.toggle(completion: completion)
    }

    func refreshCurrentTokenBookmarkState() async {
        await bookmarkController.refresh()
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
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress)
        )
    }

    func viewingProgress(for token: GeneratedToken) -> PlayerViewingProgress? {
        shouldRecordAnchorProgress(for: token)
            ? widgetTokenInsertion?.automaticAnchorProgress()
            : progress(for: token)
    }

    func markViewed(_ progress: PlayerViewingProgress) async {
        await viewingSessionTracker.markViewed(progress)
    }

#if os(macOS)
    func viewingProgress(
        collectionId: String,
        tokenIndex: Int,
        hasViewedToEnd: Bool
    ) -> PlayerViewingProgress? {
        guard !collectionId.isEmpty else { return nil }
        let tokenCount = Self.tokenCount(specificCollectionId: collectionId)
        guard tokenCount > 0,
              (0..<tokenCount).contains(tokenIndex),
              let identity = CollectionCatalog.tokenIdentity(
                  specificCollectionId: collectionId,
                  tokenIndex: tokenIndex
              ) else {
            return nil
        }

        return PlayerViewingProgress(
            collectionId: collectionId,
            collectionName: identity.collectionName,
            tokenId: identity.tokenId,
            tokenIndex: tokenIndex,
            tokenCount: tokenCount,
            updatedAt: PlayerSyncLogicalClock.next(for: .viewingProgress),
            hasViewedToEnd: hasViewedToEnd
        )
    }
#endif

    func restartCollection(
        ifCurrent shouldCommit: @escaping @MainActor @Sendable () -> Bool,
        onCommit: @escaping @MainActor @Sendable () -> Void
    ) {
        guard !currentToken.fullCollectionId.isEmpty,
              let firstToken = Self.generateToken(specificCollectionId: currentToken.fullCollectionId, tokenIndex: 0) else {
            return
        }

        let collectionId = currentToken.fullCollectionId
        let startingToken = currentToken
        let requestGeneration = advanceRestartRequestGeneration()
        let viewingSessionTracker = self.viewingSessionTracker
        Task { [weak self] in
            let update = await viewingSessionTracker.prepareRestartUpdate(collectionId: collectionId)
            guard let self,
                  restartRequestGeneration == requestGeneration,
                  currentToken == startingToken,
                  shouldCommit() else {
                return
            }

            restartRequestGeneration &+= 1
            PlayerPersistenceUpdates.enqueue {
                await viewingSessionTracker.beginRestart(update: update)
            }
            clearWidgetTokenInsertion()
            history = [firstToken]
            currentIndex = 0
            currentToken = firstToken
            onCommit()
        }
    }

    func cancelPendingCollectionRestart() {
        restartRequestGeneration &+= 1
    }

    @discardableResult
    func exitWidgetTokenInsertion(selectingTokenAt tokenIndex: Int) -> Bool {
        guard let widgetTokenInsertion else { return false }
        let tokenCount = Self.tokenCount(specificCollectionId: widgetTokenInsertion.collectionId)
        guard (0..<tokenCount).contains(tokenIndex),
              let token = Self.generateToken(
                specificCollectionId: widgetTokenInsertion.collectionId,
                tokenIndex: tokenIndex
              ) else {
            return false
        }

        clearWidgetTokenInsertion()
        showPagedToken(token)
        return true
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

    @discardableResult
    private func advanceRestartRequestGeneration() -> UInt {
        restartRequestGeneration &+= 1
        return restartRequestGeneration
    }

    private func adjacentToken(offset: Int) -> GeneratedToken? {
        if isCurrentTokenInsertedWidgetToken,
           let widgetTokenInsertion {
            guard let targetIndex = widgetTokenInsertion.tokenIndex(
                adjacentToInsertedTokenBy: offset
            ),
                  targetIndex >= 0,
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

    private func shouldRecordAnchorProgress(for token: GeneratedToken) -> Bool {
        isCurrentTokenInsertedWidgetToken && currentToken == token
    }

    private static func generateRandomToken(specificCollectionId: String?, notTokenId: String?) -> GeneratedToken? {
        CollectionCatalog.generateRandomToken(specificCollectionId: specificCollectionId, notTokenId: notTokenId)
    }

    private static func initialToken(collectionId: String, initialTokenId: String?) -> GeneratedToken? {
        if let initialTokenId,
           let tokenIndex = tokenIndex(specificCollectionId: collectionId, tokenId: initialTokenId) {
            return generateToken(specificCollectionId: collectionId, tokenIndex: tokenIndex)
        }

        return generateToken(specificCollectionId: collectionId, tokenIndex: 0)
    }

    private static func tokenIndex(specificCollectionId: String, tokenId: String) -> Int? {
        CollectionCatalog.tokenIndex(specificCollectionId: specificCollectionId, tokenId: tokenId)
    }

    private static func tokenCount(specificCollectionId: String) -> Int {
        CollectionCatalog.tokenCount(specificCollectionId: specificCollectionId)
    }

    private static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        CollectionCatalog.generateToken(specificCollectionId: specificCollectionId, tokenIndex: tokenIndex)
    }

    private func configureBookmarkState() {
        bookmarkController.updateTarget(currentBookmarkTarget)
        bookmarkController.start()
    }

    private static func canBookmark(token: GeneratedToken) -> Bool {
        !token.fullCollectionId.isEmpty && !token.id.isEmpty
    }

    private var currentBookmarkTarget: BookmarkTarget? {
        guard canBookmarkCurrentToken else { return nil }
        return BookmarkTarget(
            collectionId: currentToken.fullCollectionId,
            tokenId: currentToken.id
        )
    }

    typealias BookmarkTarget = PlayerBookmarkPresentationState.Target

}
