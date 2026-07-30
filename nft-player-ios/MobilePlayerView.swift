// ∅ 2026 lil org

import SwiftUI
import UIKit
import LinkPresentation

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

final class MobilePlayerNavigationTitleController: ObservableObject {
    @Published private(set) var title = MobilePlayerNavigationTitleState()
    @Published private(set) var isModeTransitionActive = false

    func setTitle(
        collectionTitle: String,
        pageLabel: String
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setTitle(
                    collectionTitle: collectionTitle,
                    pageLabel: pageLabel
                )
            }
            return
        }

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

    func setModeTransitionActive(_ isActive: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setModeTransitionActive(isActive) }
            return
        }

        guard isModeTransitionActive != isActive else { return }
        isModeTransitionActive = isActive
    }
}

final class MobilePlayerChromeController: ObservableObject {
    @Published private(set) var showControls = true
    @Published private(set) var isPlayerContentHiddenForCardTransition = false
    @Published private(set) var allowsNavigationBackSwipe: Bool
    @Published private(set) var playerBackgroundColor: UIColor
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setCollectionBrowserTransitionProvider(provider)
            }
            return
        }

        collectionBrowserTransitionProvider = provider
    }

    func clearCollectionBrowserTransitionProvider(_ provider: any MobilePlayerBrowserTransitionProviding) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.clearCollectionBrowserTransitionProvider(provider)
            }
            return
        }

        guard collectionBrowserTransitionProvider === provider else { return }
        collectionBrowserTransitionProvider = nil
    }

    var isCollectionBrowserActive: Bool {
        Thread.isMainThread && collectionBrowserTransitionProvider?.isCollectionBrowserActive == true
    }

    var pagerProvider: (any MobilePlayerPagerProviding)? {
        Thread.isMainThread ? registeredPagerProvider : nil
    }

    func setPagerProvider(_ provider: any MobilePlayerPagerProviding) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setPagerProvider(provider)
            }
            return
        }

        registeredPagerProvider = provider
    }

    func clearPagerProvider(_ provider: any MobilePlayerPagerProviding) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.clearPagerProvider(provider)
            }
            return
        }

        guard registeredPagerProvider === provider else { return }
        registeredPagerProvider = nil
    }

    func prepareCollectionBrowserSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection? {
        guard Thread.isMainThread else { return nil }
        return collectionBrowserTransitionProvider?.prepareCollectionBrowserSelection(for: pagePosition)
    }

    func makeOnePerPageTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView? {
        guard Thread.isMainThread else { return nil }
        return collectionBrowserTransitionProvider?
            .makeOnePerPageTransitionSnapshot(
                from: sourceFrame,
                in: coordinateView
            )
    }

    func cancelPreparedCollectionBrowserSelection() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.cancelPreparedCollectionBrowserSelection() }
            return
        }

        collectionBrowserTransitionProvider?.cancelPreparedCollectionBrowserSelection()
    }

    func setLiveLayoutInteractionStateProvider(
        id: UUID,
        _ provider: @escaping () -> MobilePlayerLayoutInteractionState
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setLiveLayoutInteractionStateProvider(id: id, provider)
            }
            return
        }

        liveLayoutInteractionStateProviderID = id
        liveLayoutInteractionStateProvider = provider
    }

    func clearLiveLayoutInteractionStateProvider(id: UUID) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.clearLiveLayoutInteractionStateProvider(id: id)
            }
            return
        }

        guard liveLayoutInteractionStateProviderID == id else { return }

        liveLayoutInteractionStateProviderID = nil
        liveLayoutInteractionStateProvider = nil
    }

    func currentLayoutInteractionState() -> MobilePlayerLayoutInteractionState {
        guard Thread.isMainThread else { return layoutInteractionState }

        return liveLayoutInteractionStateProvider?() ?? layoutInteractionState
    }

    func toggleControls() {
        setControlsVisible(!showControls)
    }

    func setControlsVisible(_ isVisible: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setControlsVisible(isVisible) }
            return
        }

        guard showControls != isVisible else { return }
        showControls = isVisible
    }

    func setPlayerBackgroundColor(_ color: UIColor) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setPlayerBackgroundColor(color) }
            return
        }

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

    func setPlayerContentZoomed(_ isZoomed: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setPlayerContentZoomed(isZoomed) }
            return
        }

        guard isPlayerContentZoomed != isZoomed else { return }
        isPlayerContentZoomed = isZoomed
    }

    func setPlayerContentHiddenForCardTransition(_ isHidden: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setPlayerContentHiddenForCardTransition(isHidden) }
            return
        }

        guard isPlayerContentHiddenForCardTransition != isHidden else { return }
        isPlayerContentHiddenForCardTransition = isHidden
    }

    func setPlayerModeTitleTransitionActive(_ isActive: Bool) {
        playerNavigationTitleController.setModeTransitionActive(isActive)
    }

    func setNavigationBackSwipeAllowed(_ isAllowed: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setNavigationBackSwipeAllowed(isAllowed) }
            return
        }

        guard allowsNavigationBackSwipe != isAllowed else { return }
        allowsNavigationBackSwipe = isAllowed
    }

    func setLayoutInteractionState(_ state: MobilePlayerLayoutInteractionState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setLayoutInteractionState(state) }
            return
        }

        guard layoutInteractionState != state else { return }
        layoutInteractionState = state
    }

    @discardableResult
    func requestCollectionBrowserExpand(
        _ selection: MobilePlayerBrowserTransitionSelection
    ) -> MobilePlayerBrowserExpandSelectionResult {
        guard Thread.isMainThread else { return .rejected }
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

    private let initialConfig: MobilePlayerConfig
    private let onDismiss: () -> Void
    private let collectionBrowserAvailable: Bool
    @ObservedObject private var chrome: MobilePlayerChromeController

    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentProgress: MobileViewingProgress?
    @State private var currentPagePosition: PlayerPagePosition?
    @State private var isCurrentPagePositionInsertedWidgetToken = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isCurrentTokenBookmarked = false
    @State private var bundledGenerativePresentationMode:
        MobileBundledGenerativePresentationMode = .thumbnailAspectFit
    @State private var focusedPagePositionUpdateCoordinator =
        MobilePlayerFocusedPagePositionUpdateCoordinator()

    init(
        config: MobilePlayerConfig,
        onDismiss: @escaping () -> Void,
        chrome: MobilePlayerChromeController
    ) {
        self.initialConfig = config
        self.onDismiss = onDismiss
        self.chrome = chrome
        self.collectionBrowserAvailable = PlayerCollectionBrowserSupport.isAvailable(
            for: config
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
                    initialConfig: initialConfig,
                    chrome: chrome,
                    bundledGenerativePresentationMode: bundledGenerativePresentationMode,
                    onFocusedPagePositionUpdate: handleFocusedPagePositionUpdate,
                    onSettledPagePositionUpdate: handleSettledPagePositionUpdate,
                    onPaginationAttempt: {},
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
                            playerID: initialConfig.id,
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
                .allowsHitTesting(chrome.showControls && canBookmarkCurrentToken)
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
            bundledGenerativePresentationMode = .thumbnailAspectFit
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerBookmarksDidChange)) { _ in
            updateBookmarkState(for: currentToken)
        }
        .onAppear {
            guard !isAllowedToHideStatusBar else { return }

            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            let window = scene?.windows.first
            let topSafeArea = window?.safeAreaInsets.top ?? 0
            if topSafeArea < 44 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                    isAllowedToHideStatusBar = true
                }
            } else {
                isAllowedToHideStatusBar = true
            }
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

        guard let descriptor = MobilePlaybackController.shared.collectionBrowseThumbnailDescriptor(
            uuid: initialConfig.id,
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

    private func updateLayoutInteractionState() {
        chrome.setLayoutInteractionState(
            MobilePlaybackController.shared.layoutInteractionState(
                uuid: initialConfig.id,
                displayMode: .onePerPage,
                pagePosition: currentPagePosition,
                collectionBrowserAvailable: collectionBrowserAvailable
            )
        )
    }

    private func handleFocusedPagePositionUpdate(_ pagePosition: PlayerPagePosition) {
        let generation = focusedPagePositionUpdateCoordinator.beginUpdate()

        DispatchQueue.main.async {
            guard self.focusedPagePositionUpdateCoordinator.isCurrent(generation) else { return }

            let token = MobilePlaybackController.shared.getToken(
                uuid: initialConfig.id,
                pagePosition: pagePosition
            )
            let pageLabel = MobilePlaybackController.shared.pageLabel(
                uuid: initialConfig.id,
                pagePosition: pagePosition
            ) ?? ""
            let isInsertedWidgetToken = MobilePlaybackController.shared.isInsertedWidgetToken(
                uuid: initialConfig.id,
                pagePosition: pagePosition
            )
            let progress = MobilePlaybackController.shared.progress(
                uuid: initialConfig.id,
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
        DispatchQueue.main.async {
            guard self.currentPagePosition == pagePosition else { return }
            self.currentProgress = progress
        }
        return progress != nil
    }

    private func markViewed(
        _ pagePosition: PlayerPagePosition,
        hasViewedToEnd: Bool
    ) -> MobileViewingProgress? {
        MobilePlaybackController.shared.markViewed(
            uuid: initialConfig.id,
            pagePosition: pagePosition,
            hasViewedToEnd: hasViewedToEnd
        )
    }

    private func goBack() {
        navigateIfPossible(canGoBack) {
            MobilePlaybackController.shared.goBack(uuid: initialConfig.id)
        }
    }

    private func goForward() {
        navigateIfPossible(canGoForward) {
            MobilePlaybackController.shared.goForward(uuid: initialConfig.id)
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
        MobilePlaybackController.shared.hasNavigationDestination(
            uuid: initialConfig.id,
            from: pagePosition,
            direction: direction
        )
    }

    private func viewAgain() {
        MobilePlaybackController.shared.restartCollection(uuid: initialConfig.id)
    }

    private func toggleCurrentTokenBookmark() {
        guard canBookmarkCurrentToken else { return }

        isCurrentTokenBookmarked = PlayerBookmarksStore.toggleBookmark(
            collectionId: currentToken.fullCollectionId,
            tokenId: currentToken.id
        )
        Haptic.selectionChanged()
    }

    private func updateBookmarkState(for token: GeneratedToken) {
        guard !token.fullCollectionId.isEmpty, !token.id.isEmpty else {
            isCurrentTokenBookmarked = false
            return
        }

        isCurrentTokenBookmarked = PlayerBookmarksStore.isBookmarked(
            collectionId: token.fullCollectionId,
            tokenId: token.id
        )
    }

}

let playerCollectionTitleProgressAnimationDuration: TimeInterval = 0.12

struct PlayerNavigationTitleView: View {
    @ObservedObject var chrome: MobilePlayerChromeController
    @ObservedObject private var titleController: MobilePlayerNavigationTitleController

    init(chrome: MobilePlayerChromeController) {
        self.chrome = chrome
        self.titleController = chrome.playerNavigationTitleController
    }

    var body: some View {
        let hidesPageLabel = chrome.isPlayerContentHiddenForCardTransition
            || titleController.isModeTransitionActive
        let title = titleController.title

        PlayerCollectionTitlePill(
            title: title.collectionTitle,
            progressText: hidesPageLabel ? "" : title.pageLabel
        )
        .opacity(chrome.showControls || hidesPageLabel ? 1 : 0)
        .accessibilityHidden(!chrome.showControls)
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
        let counterVisibilityAnimation = Animation.easeInOut(
            duration: playerCollectionTitleProgressAnimationDuration
        )
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
                    .transition(.opacity)
            }
        }
            .padding(.horizontal, 14)
            .frame(minWidth: playerNavigationTitleMinimumWidth, maxWidth: 220)
            .frame(height: playerNavigationBarControlSize)

        if #available(iOS 26.0, *) {
            label
                .glassEffect(.regular, in: Capsule())
                .animation(counterVisibilityAnimation, value: progressText.isEmpty)
        } else {
            label
                .background(.ultraThinMaterial, in: Capsule())
                .animation(counterVisibilityAnimation, value: progressText.isEmpty)
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
    let playerID: UUID
    let pagePosition: PlayerPagePosition?
    let isVisible: Bool

    @State private var shareItem: MobilePlayerFileShareItem?

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
            updateShareItem(for: pagePosition)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .downloadableMediaCacheFileAvailabilityDidChange
            )
        ) { notification in
            let availabilityChange = notification.object
                as? DownloadableMediaCacheFileAvailabilityChange
            if shareItem != nil,
               availabilityChange == .becameAvailable {
                return
            }
            updateShareItem(for: pagePosition)
        }
    }

    private func updateShareItem(for pagePosition: PlayerPagePosition?) {
        let updatedShareItem = pagePosition.flatMap {
            MobilePlaybackController.shared.downloadedFileShareItem(
                uuid: playerID,
                pagePosition: $0
            )
        }
        guard shareItem?.fileURL != updatedShareItem?.fileURL
            || shareItem?.previewTitle != updatedShareItem?.previewTitle else {
            return
        }
        shareItem = updatedShareItem
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
