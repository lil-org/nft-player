// ∅ 2026 lil org

import SwiftUI
import UIKit
import LinkPresentation
import Observation

struct MobilePlayerConfig: Hashable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
    var initialTokenId: String?
    var initialTokenIndex: Int?
    var continueViewingCollectionId: String?
    var widgetTokenInsertion: PlayerWidgetTokenInsertion?
}

private let playerChromeToggleAnimation = Animation.easeInOut(duration: 0.12)
private let playerManualGlassHideAnimation = Animation.smooth(duration: 0.23)
private let playerNavigationBarControlSize: CGFloat = 44
private let playerNavigationTitleMinimumWidth: CGFloat = 112
private let playerProgressControlSize: CGFloat = 34
private let playerNavigationArrowSpacing: CGFloat = 4

enum MobileBundledGenerativePresentationMode: Equatable {
    case thumbnailAspectFit
    case fullscreen
}

enum MobilePlayerBrowserExpandSelectionResult {
    case started
    case busy
    case fallbackToImmediateOpen
    case rejected
}

struct MobilePlayerBrowserItemSnapshot {
    let tokenIndex: Int
    let pagePosition: PlayerPagePosition
    let descriptor: DownloadableMediaDescriptor?
    let fallbackImageSize: CGSize
    let hasLoadedImage: Bool
    let frameInWindow: CGRect
    let snapshotView: UIView
}

struct MobilePlayerBrowserTransitionSelection {
    let selectedSnapshot: MobilePlayerBrowserItemSnapshot
    let visibleNeighborSnapshots: [MobilePlayerBrowserItemSnapshot]
}

protocol MobilePlayerBrowserTransitionProviding: AnyObject {
    var isCollectionBrowserActive: Bool { get }

    func makeOnePerPageTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView?
    func prepareCollectionBrowserSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection?
    func cancelPreparedCollectionBrowserSelection()
}

private final class MobilePlayerFocusedPagePositionUpdateCoordinator {
    private var generation: UInt = 0

    func beginUpdate() -> UInt {
        generation &+= 1
        return generation
    }

    func isCurrent(_ generation: UInt) -> Bool {
        self.generation == generation
    }

    func cancelPendingUpdate() {
        generation &+= 1
    }
}

enum MobilePlayerBrowserSwitchMode: Equatable {
    case animated
    case offscreenInsertion
}

struct MobilePlayerLayoutInteractionState: Equatable {
    let displayMode: MobilePlayerDisplayMode
    let pagePosition: PlayerPagePosition?
    let collectionBrowserAvailable: Bool
    let currentDescriptor: DownloadableMediaDescriptor?
    let browserSwitchMode: MobilePlayerBrowserSwitchMode

    static let empty = MobilePlayerLayoutInteractionState(
        displayMode: .onePerPage,
        pagePosition: nil,
        collectionBrowserAvailable: false,
        currentDescriptor: nil,
        browserSwitchMode: .animated
    )

    var canSwitchDirectlyToCollectionBrowser: Bool {
        browserSwitchMode == .offscreenInsertion && canSwitchToCollectionBrowser
    }

    var canMinimizeToCollectionBrowser: Bool {
        browserSwitchMode == .animated && canSwitchToCollectionBrowser
    }

    var canSwitchToCollectionBrowser: Bool {
        displayMode == .onePerPage
            && pagePosition != nil
            && collectionBrowserAvailable
    }
}

struct MobilePlayerNavigationTitleState: Equatable {
    var collectionTitle = ""
    var pageLabel = ""
}

@MainActor
@Observable
final class MobilePlayerNavigationTitleController {
    private(set) var title = MobilePlayerNavigationTitleState()

    func setTitle(
        collectionTitle: String,
        pageLabel: String
    ) {
        let title = MobilePlayerNavigationTitleState(
            collectionTitle: collectionTitle,
            pageLabel: pageLabel
        )
        guard !collectionTitle.isEmpty,
              self.title != title else {
            return
        }
        self.title = title
    }

    func setPageLabel(_ pageLabel: String) {
        guard title.pageLabel != pageLabel else { return }
        title = MobilePlayerNavigationTitleState(
            collectionTitle: title.collectionTitle,
            pageLabel: pageLabel
        )
    }
}

@MainActor
@Observable
final class MobilePlayerChromeController {
    private(set) var showControls = true
    private(set) var isPlayerContentHiddenForCardTransition = false
    private(set) var allowsNavigationBackSwipe: Bool
    private(set) var playerBackgroundColor: UIColor
    let playerNavigationTitleController = MobilePlayerNavigationTitleController()
    private(set) var isPlayerContentZoomed = false
    private(set) var layoutInteractionState = MobilePlayerLayoutInteractionState.empty
    var onCollectionBrowserExpandRequest: ((MobilePlayerBrowserTransitionSelection) -> MobilePlayerBrowserExpandSelectionResult)?
    private weak var collectionBrowserTransitionProvider: (any MobilePlayerBrowserTransitionProviding)?
    private weak var registeredPagerProvider: (any MobilePlayerPagerProviding)?
    private var liveLayoutInteractionStateProviderID: UUID?
    private var liveLayoutInteractionStateProvider: (() -> MobilePlayerLayoutInteractionState)?

    init(
        playerBackgroundColor: UIColor = MobilePlayerBackgroundColor.defaultColor,
        allowsNavigationBackSwipe: Bool
    ) {
        self.playerBackgroundColor = playerBackgroundColor
        self.allowsNavigationBackSwipe = allowsNavigationBackSwipe
    }

    static func shouldShowPlayerChrome(
        showControls: Bool,
        allowsNavigationBackSwipe: Bool
    ) -> Bool {
        allowsNavigationBackSwipe || showControls
    }

    var isPlayerChromeVisible: Bool {
        Self.shouldShowPlayerChrome(
            showControls: showControls,
            allowsNavigationBackSwipe: allowsNavigationBackSwipe
        )
    }

    func setCollectionBrowserTransitionProvider(_ provider: any MobilePlayerBrowserTransitionProviding) {
        collectionBrowserTransitionProvider = provider
    }

    func clearCollectionBrowserTransitionProvider(_ provider: any MobilePlayerBrowserTransitionProviding) {
        guard collectionBrowserTransitionProvider === provider else { return }
        collectionBrowserTransitionProvider = nil
    }

    var isCollectionBrowserActive: Bool {
        collectionBrowserTransitionProvider?.isCollectionBrowserActive == true
    }

    var pagerProvider: (any MobilePlayerPagerProviding)? {
        registeredPagerProvider
    }

    func setPagerProvider(_ provider: any MobilePlayerPagerProviding) {
        registeredPagerProvider = provider
    }

    func clearPagerProvider(_ provider: any MobilePlayerPagerProviding) {
        guard registeredPagerProvider === provider else { return }
        registeredPagerProvider = nil
    }

    func prepareCollectionBrowserSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection? {
        return collectionBrowserTransitionProvider?.prepareCollectionBrowserSelection(for: pagePosition)
    }

    func makeOnePerPageTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView? {
        return collectionBrowserTransitionProvider?
            .makeOnePerPageTransitionSnapshot(
                from: sourceFrame,
                in: coordinateView
            )
    }

    func cancelPreparedCollectionBrowserSelection() {
        collectionBrowserTransitionProvider?.cancelPreparedCollectionBrowserSelection()
    }

    func setLiveLayoutInteractionStateProvider(
        id: UUID,
        _ provider: @escaping () -> MobilePlayerLayoutInteractionState
    ) {
        liveLayoutInteractionStateProviderID = id
        liveLayoutInteractionStateProvider = provider
    }

    func clearLiveLayoutInteractionStateProvider(id: UUID) {
        guard liveLayoutInteractionStateProviderID == id else { return }

        liveLayoutInteractionStateProviderID = nil
        liveLayoutInteractionStateProvider = nil
    }

    func currentLayoutInteractionState() -> MobilePlayerLayoutInteractionState {
        return liveLayoutInteractionStateProvider?() ?? layoutInteractionState
    }

    func toggleControls() {
        setControlsVisible(!showControls)
    }

    func setControlsVisible(_ isVisible: Bool) {
        guard showControls != isVisible else { return }
        showControls = isVisible
    }

    func setPlayerBackgroundColor(_ color: UIColor) {
        guard !playerBackgroundColor.isVisuallyEqual(to: color) else { return }
        playerBackgroundColor = color
    }

    func setPlayerNavigationTitle(
        collectionTitle: String,
        pageLabel: String
    ) {
        playerNavigationTitleController.setTitle(
            collectionTitle: collectionTitle,
            pageLabel: pageLabel
        )
    }

    func setPlayerNavigationPageLabel(_ pageLabel: String) {
        playerNavigationTitleController.setPageLabel(pageLabel)
    }

    func setPlayerContentZoomed(_ isZoomed: Bool) {
        guard isPlayerContentZoomed != isZoomed else { return }
        isPlayerContentZoomed = isZoomed
    }

    func setPlayerContentHiddenForCardTransition(_ isHidden: Bool) {
        guard isPlayerContentHiddenForCardTransition != isHidden else { return }
        isPlayerContentHiddenForCardTransition = isHidden
    }

    func setNavigationBackSwipeAllowed(_ isAllowed: Bool) {
        guard allowsNavigationBackSwipe != isAllowed else { return }
        allowsNavigationBackSwipe = isAllowed
    }

    func setLayoutInteractionState(_ state: MobilePlayerLayoutInteractionState) {
        guard layoutInteractionState != state else { return }
        layoutInteractionState = state
    }

    @discardableResult
    func requestCollectionBrowserExpand(
        _ selection: MobilePlayerBrowserTransitionSelection
    ) -> MobilePlayerBrowserExpandSelectionResult {
        return onCollectionBrowserExpandRequest?(selection) ?? .fallbackToImmediateOpen
    }
}

final class MobilePlayerCardTransitionCanvas {

    let view: UIView = {
        let view = UIView()
        view.backgroundColor = MobilePlayerBackgroundColor.defaultColor
        view.isOpaque = true
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()
}

struct MobilePlayerView: View {

    private let playbackSession: MobilePlaybackSession
    private let onDismiss: () -> Void
    private let collectionBrowserAvailable: Bool
    private let chrome: MobilePlayerChromeController

    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentProgress: MobileViewingProgress?
    @State private var currentPagePosition: PlayerPagePosition?
    @State private var isCurrentPagePositionInsertedWidgetToken = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var bookmarkPresentationState = PlayerBookmarkPresentationState()
    @State private var bookmarkStateTask: Task<Void, Never>?
    @State private var bundledGenerativePresentationMode:
        MobileBundledGenerativePresentationMode = .thumbnailAspectFit
    @State private var focusedPagePositionUpdateCoordinator =
        MobilePlayerFocusedPagePositionUpdateCoordinator()

    init(
        playbackSession: MobilePlaybackSession,
        onDismiss: @escaping () -> Void,
        chrome: MobilePlayerChromeController
    ) {
        self.playbackSession = playbackSession
        self.onDismiss = onDismiss
        self.chrome = chrome
        self.collectionBrowserAvailable = PlayerCollectionBrowserSupport.isAvailable(
            for: playbackSession.config
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let bottomChromePadding = MobileBottomChromeSpacing.padding(forSafeAreaBottom: geometry.safeAreaInsets.bottom)

            ZStack {
                Color(uiColor: chrome.playerBackgroundColor)
                    .ignoresSafeArea()
                    .opacity(chrome.isPlayerContentHiddenForCardTransition ? 0 : 1)
                    .allowsHitTesting(false)

                HorizontalPlayerContainerView(
                    playbackSession: playbackSession,
                    chrome: chrome,
                    bundledGenerativePresentationMode: bundledGenerativePresentationMode,
                    onFocusedPagePositionUpdate: handleFocusedPagePositionUpdate,
                    onSettledPagePositionUpdate: handleSettledPagePositionUpdate,
                    onPaginationAttempt: {
                        playbackSession.acknowledgeIntentionalViewingPosition()
                    },
                    onUnavailableNavigation: {
                        chrome.setControlsVisible(true)
                    },
                    onToggleChrome: {
                        chrome.toggleControls()
                    },
                    onZoomStateChange: { isZoomed in
                        chrome.setPlayerContentZoomed(isZoomed)
                    }
                )
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .opacity(chrome.isPlayerContentHiddenForCardTransition ? 0 : 1)
                .allowsHitTesting(!chrome.isPlayerContentHiddenForCardTransition)

                VStack {
                    Spacer()
                    PlayerBottomControls(
                        isVisible: chrome.showControls,
                        progress: isCurrentPagePositionInsertedWidgetToken ? nil : currentProgress,
                        showsNavigationArrows: true,
                        canGoBack: canGoBack,
                        canGoForward: canGoForward,
                        onBack: goBack,
                        onForward: goForward,
                        onViewAgain: viewAgain,
                        onFinish: onDismiss
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, bottomChromePadding)
                    .animation(chrome.showControls ? playerChromeToggleAnimation : playerManualGlassHideAnimation, value: chrome.showControls)
                }
                .allowsHitTesting(chrome.showControls)

                VStack {
                    Spacer()
                    HStack {
                        PlayerShareControl(
                            playbackSession: playbackSession,
                            pagePosition: currentPagePosition,
                            isVisible: chrome.showControls
                        )
                        Spacer()
                    }
                    .padding(.leading, 18)
                    .padding(.bottom, bottomChromePadding)
                }
                .allowsHitTesting(chrome.showControls)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if chrome.showControls, canBookmarkCurrentToken {
                            PlayerBookmarkButton(
                                isBookmarked: isCurrentTokenBookmarked,
                                isEnabled: canToggleCurrentTokenBookmark,
                                action: toggleCurrentTokenBookmark
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, bottomChromePadding)
                    .animation(chrome.showControls ? playerChromeToggleAnimation : playerManualGlassHideAnimation, value: chrome.showControls)
                    .animation(playerChromeToggleAnimation, value: isCurrentTokenBookmarked)
                }
                .allowsHitTesting(chrome.showControls && canToggleCurrentTokenBookmark)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .statusBar(hidden: shouldHideStatusBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                infoMenu
                    .allowsHitTesting(!chrome.isPlayerContentHiddenForCardTransition)
                    .accessibilityHidden(chrome.isPlayerContentHiddenForCardTransition)
            }
        }
        .onDisappear {
            focusedPagePositionUpdateCoordinator.cancelPendingUpdate()
            bookmarkStateTask?.cancel()
            bookmarkStateTask = nil
            bundledGenerativePresentationMode = .thumbnailAspectFit
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .playerBookmarksDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            updateBookmarkState(for: currentToken)
        }
        .task {
            guard !isAllowedToHideStatusBar else { return }

            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            let window = scene?.windows.first
            let topSafeArea = window?.safeAreaInsets.top ?? 0
            if topSafeArea < 44 {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            isAllowedToHideStatusBar = true
        }
    }

    private var shouldHideStatusBar: Bool {
        isAllowedToHideStatusBar && !chrome.isPlayerChromeVisible
    }

    private var infoMenu: some View {
        let artists = SuggestedItemsService.artists(
            forCollectionId: currentToken.fullCollectionId
        )
        let hasArtistLinks = artists.contains { !$0.links.isEmpty }

        return Menu {
            ForEach(artists) { artist in
                ForEach(artist.links) { link in
                    Button {
                        openMoreMenuURL(link.destination)
                    } label: {
                        Label {
                            Text(verbatim: link.title)
                        } icon: {
                            artistLinkIcon(for: link.kind)
                        }
                    }
                    .disabled(chrome.isPlayerContentHiddenForCardTransition)
                }
            }

            if hasArtistLinks {
                Divider()
            }

            if canToggleBundledGenerativeFullscreen {
                Toggle(
                    Strings.viewFullscreen,
                    isOn: bundledGenerativeFullscreenBinding
                )
                .disabled(chrome.isPlayerContentHiddenForCardTransition)
            }
            Button(Strings.viewOnBlockExplorer, action: viewOnWeb)
                .disabled(chrome.isPlayerContentHiddenForCardTransition)
        } label: {
            Images.ellipsis
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Strings.more)
    }

    private var canToggleBundledGenerativeFullscreen: Bool {
        guard let currentPagePosition,
              currentToken.media == nil,
              currentToken.nativeMetalCardRenderKind == nil,
              TokenGenerator.isBundledWebGenerativeCollection(
                id: currentToken.fullCollectionId
              ) else {
            return false
        }

        guard let descriptor = playbackSession.collectionBrowseThumbnailDescriptor(
            pagePosition: currentPagePosition
        ) else {
            return false
        }

        return descriptor.collectionId == currentToken.fullCollectionId
            && descriptor.tokenId == currentToken.id
            && descriptor.thumbnailAspectRatio != nil
    }

    private var bundledGenerativeFullscreenBinding: Binding<Bool> {
        Binding(
            get: {
                bundledGenerativePresentationMode == .fullscreen
            },
            set: { isFullscreen in
                guard !chrome.isPlayerContentHiddenForCardTransition else { return }
                bundledGenerativePresentationMode = isFullscreen
                    ? .fullscreen
                    : .thumbnailAspectFit
            }
        )
    }
    
    private func viewOnWeb() {
        guard let url = currentToken.url else { return }
        openMoreMenuURL(url)
    }

    private func openMoreMenuURL(_ url: URL) {
        guard !chrome.isPlayerContentHiddenForCardTransition else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private func artistLinkIcon(for kind: SuggestedArtistLink.Kind) -> some View {
        switch kind {
        case .website:
            Images.website
        case .x:
            Images.xLogo
        case .bluesky:
            Images.blueskyLogo
        }
    }

    private var canBookmarkCurrentToken: Bool {
        !currentToken.fullCollectionId.isEmpty && !currentToken.id.isEmpty
    }

    private var canToggleCurrentTokenBookmark: Bool {
        canBookmarkCurrentToken && bookmarkPresentationState.canToggle
    }

    private var isCurrentTokenBookmarked: Bool {
        bookmarkPresentationState.isBookmarked
    }

    private func updateLayoutInteractionState() {
        chrome.setLayoutInteractionState(
            playbackSession.layoutInteractionState(
                displayMode: .onePerPage,
                pagePosition: currentPagePosition,
                collectionBrowserAvailable: collectionBrowserAvailable
            )
        )
    }

    private func handleFocusedPagePositionUpdate(_ pagePosition: PlayerPagePosition) {
        let generation = focusedPagePositionUpdateCoordinator.beginUpdate()

        Task { @MainActor in
            await Task.yield()
            guard self.focusedPagePositionUpdateCoordinator.isCurrent(generation) else { return }

            let token = playbackSession.getToken(
                pagePosition: pagePosition
            )
            let pageLabel = playbackSession.pageLabel(
                pagePosition: pagePosition
            ) ?? ""
            let isInsertedWidgetToken = playbackSession.isInsertedWidgetToken(
                pagePosition: pagePosition
            )
            let progress = playbackSession.progress(
                pagePosition: pagePosition,
                resolvedToken: token
            )
            chrome.setPlayerNavigationTitle(
                collectionTitle: token.collectionName,
                pageLabel: pageLabel
            )
            chrome.setPlayerBackgroundColor(MobilePlayerBackgroundColor.color(for: token))

            self.currentPagePosition = pagePosition
            self.currentToken = token
            self.currentProgress = progress
            self.isCurrentPagePositionInsertedWidgetToken = isInsertedWidgetToken
            self.updateLayoutInteractionState()
            self.updateNavigationAvailability(for: pagePosition)
            self.updateBookmarkState(for: token)
            updateExternalDisplayToken(token)
        }
    }

    private func handleSettledPagePositionUpdate(
        _ pagePosition: PlayerPagePosition,
        hasViewedToEnd: Bool
    ) -> Bool {
        let progress = markViewed(
            pagePosition,
            hasViewedToEnd: hasViewedToEnd
        )
        Task { @MainActor in
            await Task.yield()
            guard self.currentPagePosition == pagePosition else { return }
            self.currentProgress = progress
        }
        return progress != nil
    }

    private func markViewed(
        _ pagePosition: PlayerPagePosition,
        hasViewedToEnd: Bool
    ) -> MobileViewingProgress? {
        playbackSession.markViewed(
            pagePosition: pagePosition,
            hasViewedToEnd: hasViewedToEnd
        )
    }

    private func goBack() {
        navigateIfPossible(canGoBack) {
            playbackSession.goBack()
        }
    }

    private func goForward() {
        navigateIfPossible(canGoForward) {
            playbackSession.goForward()
        }
    }

    private func navigateIfPossible(_ canNavigate: Bool, action: () -> Void) {
        guard canNavigate else {
            chrome.setControlsVisible(true)
            return
        }
        action()
        Haptic.selectionChanged()
    }

    private func updateNavigationAvailability(for pagePosition: PlayerPagePosition?) {
        guard let pagePosition else {
            canGoBack = false
            canGoForward = false
            return
        }

        canGoBack = hasNavigationDestination(from: pagePosition, direction: .back)
        canGoForward = hasNavigationDestination(from: pagePosition, direction: .forward)
    }

    private func hasNavigationDestination(
        from pagePosition: PlayerPagePosition,
        direction: PlaybackNavigationDirection
    ) -> Bool {
        playbackSession.hasNavigationDestination(
            from: pagePosition,
            direction: direction
        )
    }

    private func viewAgain() {
        playbackSession.restartCollection()
    }

    private func toggleCurrentTokenBookmark() {
        guard let request = bookmarkPresentationState.beginToggle() else { return }

        bookmarkStateTask?.cancel()
        bookmarkStateTask = nil
        let didBeginToggle = PlayerBookmarksStore.enqueueBookmarkUpdate(
            collectionId: request.target.collectionId,
            tokenId: request.target.tokenId,
            isBookmarked: request.isBookmarked
        ) { isBookmarked in
            let storedState = PlayerBookmarksStore.storedBookmarkState(
                collectionId: request.target.collectionId,
                tokenId: request.target.tokenId
            )
            bookmarkPresentationState.applyToggleCompletion(
                isBookmarked: isBookmarked,
                for: request.target,
                isTogglePending: storedState.isTogglePending
            )
        }
        if didBeginToggle {
            Haptic.selectionChanged()
        }
    }

    private func updateBookmarkState(for token: GeneratedToken) {
        bookmarkStateTask?.cancel()
        bookmarkStateTask = nil
        let target: PlayerBookmarkPresentationState.Target? = if token.fullCollectionId.isEmpty
            || token.id.isEmpty {
            nil
        } else {
            PlayerBookmarkPresentationState.Target(
                collectionId: token.fullCollectionId,
                tokenId: token.id
            )
        }
        let storedState = target.map {
            PlayerBookmarksStore.storedBookmarkState(
                collectionId: $0.collectionId,
                tokenId: $0.tokenId
            )
        } ?? PlayerStoredBookmarkState(
            isBookmarked: false,
            isTogglePending: false,
            isReady: true
        )
        guard let request = bookmarkPresentationState.beginLoading(
            target: target,
            storedState: storedState
        ) else { return }

        bookmarkStateTask = Task {
            let isBookmarked = await PlayerBookmarksStore.shared.isBookmarked(
                collectionId: request.target.collectionId,
                tokenId: request.target.tokenId
            )
            guard !Task.isCancelled else { return }
            bookmarkPresentationState.applyLoadedState(
                isBookmarked: isBookmarked,
                for: request
            )
        }
    }

}

struct PlayerNavigationTitleView: View {
    let chrome: MobilePlayerChromeController
    private let titleController: MobilePlayerNavigationTitleController

    init(chrome: MobilePlayerChromeController) {
        self.chrome = chrome
        self.titleController = chrome.playerNavigationTitleController
    }

    var body: some View {
        let title = titleController.title

        PlayerCollectionTitlePill(
            title: title.collectionTitle,
            progressText: title.pageLabel
        )
        .opacity(
            chrome.showControls && !chrome.isPlayerContentHiddenForCardTransition ? 1 : 0
        )
        .accessibilityHidden(
            !chrome.showControls || chrome.isPlayerContentHiddenForCardTransition
        )
    }
}

struct PlayerCollectionTitlePill: View {
    let title: String
    let progressText: String

    var body: some View {
        titleLabel
    }

    @ViewBuilder
    private var titleLabel: some View {
        let label = VStack(spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if !progressText.isEmpty {
                Text(progressText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
            .padding(.horizontal, 14)
            .frame(minWidth: playerNavigationTitleMinimumWidth, maxWidth: 220)
            .frame(height: playerNavigationBarControlSize)

        if #available(iOS 26.0, *) {
            label
                .glassEffect(.regular, in: Capsule())
        } else {
            label
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct PlayerBottomControls: View {
    let isVisible: Bool
    let progress: MobileViewingProgress?
    let showsNavigationArrows: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onViewAgain: () -> Void
    let onFinish: () -> Void

    var body: some View {
        controlsStack
    }

    private var controlsStack: some View {
        VStack(spacing: 12) {
            if progress?.hasBeenViewedToEnd == true {
                completionActions
            }
            if showsNavigationArrows {
                progressNavigationControls
            }
        }
    }

    @ViewBuilder
    private var completionActions: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                if isVisible {
                    completionActionsRow
                }
            }
        } else if isVisible {
            completionActionsRow
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var completionActionsRow: some View {
        HStack(spacing: 18) {
            PlayerProgressActionButton(image: Images.viewAgain, title: Strings.viewAgain) {
                Haptic.selectionChanged()
                onViewAgain()
            }
            PlayerProgressActionButton(image: Images.finish, title: Strings.finish) {
                Haptic.success()
                onFinish()
            }
        }
    }

    @ViewBuilder
    private var progressNavigationControls: some View {
        if isVisible {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: playerNavigationArrowSpacing) {
                    progressNavigationRow
                }
                .transition(.opacity)
            } else {
                progressNavigationRow
                    .transition(.opacity)
            }
        }
    }

    private var progressNavigationRow: some View {
        HStack(spacing: playerNavigationArrowSpacing) {
            PlayerProgressArrowButton(
                image: Images.back,
                accessibilityLabel: Strings.back,
                isEnabled: canGoBack,
                action: onBack
            )

            PlayerProgressArrowButton(
                image: Images.forward,
                accessibilityLabel: Strings.forward,
                isEnabled: canGoForward,
                action: onForward
            )
        }
    }
}

private struct PlayerProgressActionButton: View {
    let image: Image
    let title: String
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 6) {
                image
                    .font(.caption.weight(.semibold))
                    .imageScale(.small)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .frame(height: playerProgressControlSize)
            .contentShape(Capsule())
        }
        .accessibilityLabel(title)

        if #available(iOS 26.0, *) {
            button
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .glassEffectTransition(.materialize)
        } else {
            button
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct PlayerProgressArrowButton: View {
    let image: Image
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let button = Button(action: action) {
            image
                .font(.body.weight(.semibold))
                .imageScale(.large)
                .frame(width: playerProgressControlSize, height: playerProgressControlSize)
                .contentShape(Circle())
        }
        .accessibilityLabel(accessibilityLabel)
        .disabled(!isEnabled)

        if #available(iOS 26.0, *) {
            button
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .glassEffectTransition(.materialize)
        } else {
            button
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct PlayerShareControl: View {
    let playbackSession: MobilePlaybackSession
    let pagePosition: PlayerPagePosition?
    let isVisible: Bool

    @State private var shareItem: MobilePlayerFileShareItem?
    @State private var shareItemTask: Task<Void, Never>?
    @State private var shareItemRequestID = UUID()

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            if isVisible, let shareItem {
                PlayerShareButton(shareItem: shareItem)
                    .transition(.opacity)
            }
        }
        .animation(
            isVisible
                ? playerChromeToggleAnimation
                : playerManualGlassHideAnimation,
            value: isVisible
        )
        .animation(playerChromeToggleAnimation, value: shareItem?.fileURL)
        .onChange(of: pagePosition, initial: true) { _, pagePosition in
            updateShareItem(for: pagePosition, clearsCurrentItem: true)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .downloadableMediaCacheFileAvailabilityDidChange
            )
        ) { notification in
            guard let pagePosition,
                  let descriptor = playbackSession.downloadableMediaDescriptor(
                    pagePosition: pagePosition
                  ),
                  DownloadableMediaCache.shared.fileAvailabilityChange(
                    notification,
                    affects: descriptor
                  ) else {
                return
            }
            let availabilityChange = notification.object
                as? DownloadableMediaCacheFileAvailabilityChange
            if shareItem != nil,
               availabilityChange == .becameAvailable {
                return
            }
            updateShareItem(for: pagePosition)
        }
        .onDisappear {
            shareItemTask?.cancel()
            shareItemTask = nil
        }
    }

    private func updateShareItem(
        for pagePosition: PlayerPagePosition?,
        clearsCurrentItem: Bool = false
    ) {
        shareItemTask?.cancel()
        let requestID = UUID()
        shareItemRequestID = requestID
        if clearsCurrentItem {
            shareItem = nil
        }
        guard let pagePosition else {
            shareItemTask = nil
            return
        }
        shareItemTask = Task { @MainActor in
            let updatedShareItem = await playbackSession.downloadedFileShareItem(
                pagePosition: pagePosition
            )
            guard !Task.isCancelled,
                  shareItemRequestID == requestID else {
                return
            }
            shareItemTask = nil
            guard shareItem?.fileURL != updatedShareItem?.fileURL
                || shareItem?.previewTitle != updatedShareItem?.previewTitle else {
                return
            }
            shareItem = updatedShareItem
        }
    }
}

private struct PlayerShareButton: View {
    let shareItem: MobilePlayerFileShareItem
    @State private var isShareSheetPresented = false

    @ViewBuilder
    var body: some View {
        let button = Button {
            Haptic.selectionChanged()
            isShareSheetPresented = true
        } label: {
            Images.share
                .font(.body.weight(.semibold))
                .imageScale(.large)
                .frame(width: playerProgressControlSize, height: playerProgressControlSize)
                .contentShape(Circle())
        }
        .accessibilityLabel(Strings.share)
        .sheet(isPresented: $isShareSheetPresented) {
            PlayerFileShareSheet(shareItem: shareItem)
        }

        if #available(iOS 26.0, *) {
            button
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .glassEffectTransition(.materialize)
        } else {
            button
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct PlayerFileShareSheet: UIViewControllerRepresentable {
    let shareItem: MobilePlayerFileShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [PlayerFileActivityItemSource(shareItem: shareItem)],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class PlayerFileActivityItemSource: NSObject, UIActivityItemSource {
    private let shareItem: MobilePlayerFileShareItem

    init(shareItem: MobilePlayerFileShareItem) {
        self.shareItem = shareItem
        super.init()
    }

    private var activityItem: Any {
        shareItem.previewImage() ?? shareItem.fileURL
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        activityItem
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        activityItem
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = shareItem.previewTitle
        metadata.originalURL = shareItem.fileURL
        metadata.url = shareItem.fileURL

        if let fileProvider = NSItemProvider(contentsOf: shareItem.fileURL) {
            metadata.imageProvider = fileProvider
        } else if let previewImage = shareItem.previewImage() {
            metadata.imageProvider = NSItemProvider(object: previewImage)
        }

        return metadata
    }
}

private struct PlayerBookmarkButton: View {
    let isBookmarked: Bool
    let isEnabled: Bool
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let button = Button(action: action) {
            (isBookmarked ? Images.bookmarkFill : Images.bookmark)
                .font(.body.weight(.semibold))
                .imageScale(.large)
                .frame(width: playerProgressControlSize, height: playerProgressControlSize)
                .contentShape(Circle())
        }
        .accessibilityLabel(isBookmarked ? Strings.removeBookmark : Strings.bookmark)
        .disabled(!isEnabled)

        if #available(iOS 26.0, *) {
            button
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .glassEffectTransition(.materialize)
        } else {
            button
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
