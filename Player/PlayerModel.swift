// ∅ 2026 lil org

import Combine
import SwiftUI

class PlayerModel: ObservableObject {
    
    private(set) var widgetTokenInsertion: PlayerWidgetTokenInsertion?
    
    @Published var currentToken: GeneratedToken {
        didSet {
            refreshCurrentTokenBookmarkState()
        }
    }
    @Published var history: [GeneratedToken]
    @Published var currentIndex: Int = 0
    @Published var showingInfoPopover = false
    @Published private(set) var isCurrentTokenInsertedWidgetToken = false
    @Published private(set) var isCurrentTokenBookmarked = false
    private static let historyTrimThreshold = 23
    private static let retainedHistoryCount = 10
    private var viewingSessionTracker: PlayerViewingSessionTracker
    private var bookmarkChangesObserver: AnyCancellable?

    init(specificCollectionId: String?, notTokenId: String?) {
        let token = Self.generateRandomToken(
            specificCollectionId: specificCollectionId,
            notTokenId: notTokenId
        ) ?? GeneratedToken.empty
        self.currentToken = token
        self.history = [token]
        self.widgetTokenInsertion = nil
        self.viewingSessionTracker = PlayerViewingSessionTracker(continueViewingCollectionId: specificCollectionId)
        configureBookmarkState(for: token)
    }

    init(
        collectionId: String,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String? = nil,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        let token = Self.initialToken(collectionId: collectionId, initialTokenId: initialTokenId) ?? GeneratedToken.empty
        self.currentToken = token
        self.history = [token]
        self.widgetTokenInsertion = nil
        self.viewingSessionTracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: continueViewingCollectionId ?? collectionId,
            trackingMode: trackingMode
        )
        configureBookmarkState(for: token)
    }
    
    init(
        token: GeneratedToken,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        self.currentToken = token
        self.history = [token]
        self.widgetTokenInsertion = nil
        self.viewingSessionTracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: token.fullCollectionId,
            trackingMode: trackingMode
        )
        configureBookmarkState(for: token)
    }

    init(
        widgetTokenInsertion: PlayerWidgetTokenInsertion,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        self.currentToken = widgetTokenInsertion.insertedToken
        self.history = [widgetTokenInsertion.insertedToken]
        self.widgetTokenInsertion = widgetTokenInsertion
        self.isCurrentTokenInsertedWidgetToken = true
        self.viewingSessionTracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: widgetTokenInsertion.collectionId,
            trackingMode: trackingMode
        )
        configureBookmarkState(for: widgetTokenInsertion.insertedToken)
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
        showingInfoPopover = false
    }

    func goForward() {
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
            return widgetTokenInsertion.automaticAnchorProgress()
        }
        return progress(for: currentToken)
    }

    var canBookmarkCurrentToken: Bool {
        Self.canBookmark(token: currentToken)
    }

    @discardableResult
    func toggleCurrentTokenBookmark() -> Bool {
        guard canBookmarkCurrentToken else {
            setCurrentTokenBookmarked(false)
            return false
        }

        let isBookmarked = PlayerBookmarksStore.toggleBookmark(
            collectionId: currentToken.fullCollectionId,
            tokenId: currentToken.id
        )
        setCurrentTokenBookmarked(isBookmarked)
        return isBookmarked
    }

    func refreshCurrentTokenBookmarkState() {
        setCurrentTokenBookmarked(Self.isBookmarked(token: currentToken))
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
        let progress = shouldRecordAnchorProgress(for: token)
            ? widgetTokenInsertion?.automaticAnchorProgress()
            : progress(for: token)
        guard let progress else { return nil }
        viewingSessionTracker.markViewed(progress)
        return progress
    }

    func restartCollection() {
        guard !currentToken.fullCollectionId.isEmpty,
              let firstToken = Self.generateToken(specificCollectionId: currentToken.fullCollectionId, tokenIndex: 0) else {
            return
        }

        viewingSessionTracker.beginRestart(collectionId: currentToken.fullCollectionId)
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

    private func configureBookmarkState(for token: GeneratedToken) {
        setCurrentTokenBookmarked(Self.isBookmarked(token: token))
        installBookmarkChangesObserver()
    }

    private func setCurrentTokenBookmarked(_ isBookmarked: Bool) {
        guard isCurrentTokenBookmarked != isBookmarked else { return }
        isCurrentTokenBookmarked = isBookmarked
    }

    private static func canBookmark(token: GeneratedToken) -> Bool {
        !token.fullCollectionId.isEmpty && !token.id.isEmpty
    }

    private static func isBookmarked(token: GeneratedToken) -> Bool {
        guard canBookmark(token: token) else { return false }
        return PlayerBookmarksStore.isBookmarked(
            collectionId: token.fullCollectionId,
            tokenId: token.id
        )
    }

    private func installBookmarkChangesObserver() {
        bookmarkChangesObserver = NotificationCenter.default.publisher(for: .playerBookmarksDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshCurrentTokenBookmarkState()
            }
    }

}
