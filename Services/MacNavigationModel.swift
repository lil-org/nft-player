// ∅ 2026 lil org

import Combine
import Foundation

typealias MacPlayerDisplayMode = PlayerDisplayMode

enum MacRoute: Hashable {
    case collections
    case player(sessionId: UUID, mode: MacPlayerDisplayMode)

    var displayMode: MacPlayerDisplayMode? {
        switch self {
        case .collections:
            return nil
        case let .player(_, mode):
            return mode
        }
    }

    var sessionId: UUID? {
        switch self {
        case .collections:
            return nil
        case let .player(sessionId, _):
            return sessionId
        }
    }
}

enum MacRouteTransition {
    /// Slide, the way a navigation push/pop looks.
    case slide
    /// The container already animated the change itself (hero card zoom), or none is wanted.
    case none
}

final class MacPlayerSession {

    let id = UUID()
    let playerModel: PlayerModel
    let collectionId: String
    let collectionName: String
    let tokenCount: Int
    let supportsCollectionBrowser: Bool

    init(playerModel: PlayerModel) {
        self.playerModel = playerModel
        let token = playerModel.currentToken
        let collectionId = playerModel.widgetTokenInsertion?.collectionId ?? token.fullCollectionId
        self.collectionId = collectionId
        self.collectionName = token.collectionName
        let tokenCount = CollectionCatalog.tokenCount(specificCollectionId: collectionId)
        self.tokenCount = tokenCount
        self.supportsCollectionBrowser = !collectionId.isEmpty
            && tokenCount > 0
            && PlayerCollectionBrowserSupport.isAvailable(forCollectionId: collectionId)
    }

    var initialTokenIndex: Int {
        playerModel.widgetTokenInsertion?.anchorTokenIndex
            ?? CollectionCatalog.tokenContext(for: playerModel.currentToken)?.tokenIndex
            ?? 0
    }

    var collectionBrowserTokenIndex: Int? {
        if playerModel.isCurrentTokenInsertedWidgetToken,
           let widgetTokenInsertion = playerModel.widgetTokenInsertion,
           widgetTokenInsertion.collectionId == collectionId,
           (0..<tokenCount).contains(widgetTokenInsertion.anchorTokenIndex) {
            return widgetTokenInsertion.anchorTokenIndex
        }

        guard let context = CollectionCatalog.tokenContext(for: playerModel.currentToken),
              context.collectionId == collectionId,
              (0..<tokenCount).contains(context.tokenIndex) else {
            return nil
        }
        return context.tokenIndex
    }

}

/// Single source of truth for what the one macOS window is showing.
/// The AppKit container reconciles its view controller stack against `route`.
final class MacNavigationModel: ObservableObject {

    static let shared = MacNavigationModel()

    @Published private(set) var route: MacRoute = .collections
    @Published private(set) var title = Strings.nftPlayer
    @Published private(set) var canBookmarkCurrentToken = false
    @Published private(set) var isCurrentTokenBookmarked = false
    @Published private(set) var canGoToPreviousPage = false
    @Published private(set) var canGoToNextPage = false

    private(set) var session: MacPlayerSession?
    private(set) var routeTransition: MacRouteTransition = .none
    weak var commands: MacNavigationCommands?

    private var tokenObserver: AnyCancellable?
    private var bookmarkObserver: AnyCancellable?
    private var widgetInsertionObserver: AnyCancellable?
    private var browserFocusTokenIndex: Int?
    private var isChromeRefreshScheduled = false

    private init() {}

    func present(playerModel: PlayerModel, transition: MacRouteTransition = .slide) {
        let session = MacPlayerSession(playerModel: playerModel)
        let mode = MacPlayerDisplayMode.initialMode(
            hasWidgetTokenInsertion: playerModel.widgetTokenInsertion != nil,
            collectionBrowserAvailable: session.supportsCollectionBrowser
        )
        adopt(session: session)
        // Record the opening position straight away, the way opening the player window
        // used to. Without this a session that lands on the browser and is quit before
        // the wall is scrolled leaves no progress and no continue-viewing entry.
        playerModel.markCurrentTokenViewed()
        browserFocusTokenIndex = session.initialTokenIndex
        setRoute(.player(sessionId: session.id, mode: mode), transition: transition)
    }

    func showCollections(transition: MacRouteTransition = .slide) {
        guard commands?.isNavigationTransitionInFlight != true,
              route != .collections else {
            return
        }
        setRoute(.collections, transition: transition)
    }

    func resetToCollections() {
        guard route != .collections else { return }
        setRoute(.collections, transition: .none)
    }

    func handleMainWindowWillClose() {
        let commands = commands
        setRoute(.collections, transition: .none)
        commands?.prepareForWindowClose()
        DownloadableMediaCache.shared.cancelAllDownloads()
    }

    func showShuffledCollection() {
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        let collectionItems = CollectionCatalog.allItems
        let unfinishedItems = collectionItems.filter {
            !progressSnapshot.viewedToEndCollectionIds.contains($0.id)
        }
        guard let item = (unfinishedItems.isEmpty ? collectionItems : unfinishedItems).randomElement() else {
            return
        }
        let progress = PlayerViewingProgressStore.progress(collectionId: item.id)
        let initialTokenId = progress?.isComplete == false ? progress?.tokenId : nil
        Navigator.shared.showPlayer(
            collectionId: item.id,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: item.id
        )
    }

    func showCollectionBrowser(transition: MacRouteTransition = .slide) {
        guard let session, session.supportsCollectionBrowser else {
            showCollections()
            return
        }
        setRoute(.player(sessionId: session.id, mode: .collectionBrowser), transition: transition)
    }

    func showOnePerPage(transition: MacRouteTransition = .slide) {
        guard let session else { return }
        setRoute(.player(sessionId: session.id, mode: .onePerPage), transition: transition)
    }

    func goBack() {
        if commands?.navigateBackWithHeroTransition() == true { return }

        switch route {
        case .collections:
            break
        case let .player(_, mode):
            if mode == .onePerPage, session?.supportsCollectionBrowser == true {
                showCollectionBrowser()
            } else {
                showCollections()
            }
        }
    }

    func updateBrowserFocus(tokenIndex: Int?) {
        guard browserFocusTokenIndex != tokenIndex else { return }
        browserFocusTokenIndex = tokenIndex
        guard route.displayMode == .collectionBrowser else { return }
        scheduleChromeRefresh()
    }

    func toggleCurrentTokenBookmark() {
        session?.playerModel.toggleCurrentTokenBookmark()
        refreshChrome()
    }

    /// Re-reads the state that lives on the container (paging availability, media
    /// actions). Called once a screen is on stage, since `commands` is not observable.
    func refreshCommandState() {
        scheduleChromeRefresh()
    }

    private func setRoute(_ route: MacRoute, transition: MacRouteTransition) {
        routeTransition = transition
        if route == .collections {
            releaseSession()
        }
        self.route = route
        refreshChrome()
    }

    private func adopt(session: MacPlayerSession) {
        self.session = session
        let playerModel = session.playerModel
        tokenObserver = playerModel.$currentToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshChrome()
            }
        bookmarkObserver = playerModel.$isCurrentTokenBookmarked
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshChrome()
            }
        widgetInsertionObserver = playerModel.$isCurrentTokenInsertedWidgetToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshChrome()
            }
    }

    private func releaseSession() {
        tokenObserver = nil
        bookmarkObserver = nil
        widgetInsertionObserver = nil
        browserFocusTokenIndex = nil
        session = nil
    }

    /// Coalesced, next-turn refresh. The container drives these from inside SwiftUI's
    /// own update pass (`updateNSViewController`), and publishing from there is
    /// undefined behaviour, so the mutation is pushed to the following turn.
    private func scheduleChromeRefresh() {
        guard !isChromeRefreshScheduled else { return }
        isChromeRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isChromeRefreshScheduled = false
            self.refreshChrome()
        }
    }

    private func refreshChrome() {
        title = makeTitle()
        let playerModel = session?.playerModel
        let isOnePerPage = route.displayMode == .onePerPage
        canBookmarkCurrentToken = isOnePerPage && playerModel?.canBookmarkCurrentToken == true
        isCurrentTokenBookmarked = canBookmarkCurrentToken
            && playerModel?.isCurrentTokenBookmarked == true
        canGoToPreviousPage = isOnePerPage && commands?.canGoToPreviousPage == true
        canGoToNextPage = isOnePerPage && commands?.canGoToNextPage == true
    }

    private func makeTitle() -> String {
        guard let session else { return Strings.nftPlayer }

        switch route {
        case .collections:
            return Strings.nftPlayer
        case let .player(_, mode):
            switch mode {
            case .onePerPage:
                return session.playerModel.playerWindowTitle
            case .collectionBrowser:
                let baseTitle = session.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = baseTitle.isEmpty ? Strings.nftPlayer : baseTitle
                guard let browserFocusTokenIndex, session.tokenCount > 0 else { return name }
                let pagePosition = Strings.pagePosition(
                    current: browserFocusTokenIndex + 1,
                    total: session.tokenCount
                )
                return "\(name) \(pagePosition)"
            }
        }
    }

}
