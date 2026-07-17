// ∅ 2026 lil org

import SwiftUI
import UIKit
import LinkPresentation

struct MobilePlayerConfig: Hashable, Codable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
    var initialTokenId: String?
    var initialTokenIndex: Int?
    var continueViewingCollectionId: String?
    var trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    var widgetTokenInsertion: PlayerWidgetTokenInsertion?
}

private let doNotShowInstructionsTmp = true
private let playerChromeToggleAnimation = Animation.easeInOut(duration: 0.12)
private let playerManualGlassHideAnimation = Animation.smooth(duration: 0.23)
private let playerNavigationBarControlSize: CGFloat = 44
private let playerProgressControlSize: CGFloat = 34
private let playerNavigationArrowSpacing: CGFloat = 4

struct MobilePlayerDisplayModeRequest {
    let id = UUID()
    let displayMode: MobilePlayerDisplayMode
    let targetPagePosition: PlayerPagePosition?
    let completion: ((Bool) -> Void)?
}

struct MobilePlayerDisplayModeRejection {
    let displayModeChangeID: UUID
    let requestedDisplayMode: MobilePlayerDisplayMode
    let targetPagePosition: PlayerPagePosition?
    let currentDisplayMode: MobilePlayerDisplayMode
}

struct MobilePlayerDisplayModeApplication {
    let displayModeChangeID: UUID
    let requestedDisplayMode: MobilePlayerDisplayMode
    let targetPagePosition: PlayerPagePosition?
}

struct MobilePlayerDisplayModeSupersession {
    let displayModeChangeID: UUID
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

    func prepareCollectionBrowserSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection?
    func cancelPreparedCollectionBrowserSelection()
}

private struct MobilePlayerPendingDisplayModeApplication {
    let displayModeChangeID: UUID
    let requestedDisplayMode: MobilePlayerDisplayMode
    let targetPagePosition: PlayerPagePosition?
    let completion: (Bool) -> Void

    func matches(
        displayMode: MobilePlayerDisplayMode,
        targetPagePosition: PlayerPagePosition?
    ) -> Bool {
        requestedDisplayMode == displayMode
            && self.targetPagePosition == targetPagePosition
    }
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
    let browserDensity: MobilePlayerBrowserDensity?
    let currentDescriptor: DownloadableMediaDescriptor?
    let browserSwitchMode: MobilePlayerBrowserSwitchMode

    static let empty = MobilePlayerLayoutInteractionState(
        displayMode: .onePerPage,
        pagePosition: nil,
        browserDensity: nil,
        currentDescriptor: nil,
        browserSwitchMode: .animated
    )

    var canSwitchDirectlyToCollectionBrowser: Bool {
        browserSwitchMode == .offscreenInsertion && canUseCurrentCollectionBrowser
    }

    var canMinimizeToCollectionBrowser: Bool {
        browserSwitchMode == .animated && canUseCurrentCollectionBrowser
    }

    private var canUseCurrentCollectionBrowser: Bool {
        displayMode == .onePerPage
            && pagePosition != nil
            && browserDensity != nil
    }
}

final class MobilePlayerChromeController: ObservableObject {
    @Published private(set) var showControls = false
    @Published private(set) var isPlayerContentHiddenForCardTransition = false
    @Published private(set) var allowsNavigationBackSwipe: Bool
    @Published private(set) var displayModeRequest: MobilePlayerDisplayModeRequest?
    @Published private(set) var playerBackgroundColor: UIColor
    private(set) var isPlayerContentZoomed = false
    private(set) var layoutInteractionState = MobilePlayerLayoutInteractionState.empty
    var onCollectionBrowserMinimizeRequest: (() -> Bool)?
    var onCollectionBrowserExpandRequest: ((MobilePlayerBrowserTransitionSelection) -> MobilePlayerBrowserExpandSelectionResult)?
    private weak var collectionBrowserTransitionProvider: (any MobilePlayerBrowserTransitionProviding)?
    private var liveLayoutInteractionStateProviderID: UUID?
    private var liveLayoutInteractionStateProvider: (() -> MobilePlayerLayoutInteractionState)?

    init(
        playerBackgroundColor: UIColor = MobilePlayerBackgroundColor.defaultColor,
        allowsNavigationBackSwipe: Bool
    ) {
        self.playerBackgroundColor = playerBackgroundColor
        self.allowsNavigationBackSwipe = allowsNavigationBackSwipe
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

    func prepareCollectionBrowserSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection? {
        guard Thread.isMainThread else { return nil }
        return collectionBrowserTransitionProvider?.prepareCollectionBrowserSelection(for: pagePosition)
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
    func requestDisplayMode(
        _ displayMode: MobilePlayerDisplayMode,
        targetPagePosition: PlayerPagePosition? = nil,
        completion: ((Bool) -> Void)? = nil
    ) -> UUID {
        let request = MobilePlayerDisplayModeRequest(
            displayMode: displayMode,
            targetPagePosition: targetPagePosition,
            completion: completion
        )

        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.displayModeRequest = request
            }
            return request.id
        }

        displayModeRequest = request
        return request.id
    }

    func clearDisplayModeRequest(_ request: MobilePlayerDisplayModeRequest) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.clearDisplayModeRequest(request) }
            return
        }

        guard displayModeRequest?.id == request.id else { return }
        displayModeRequest = nil
    }

    @discardableResult
    func requestCollectionBrowserMinimize() -> Bool {
        guard Thread.isMainThread else { return false }
        return onCollectionBrowserMinimizeRequest?() == true
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

private struct MobilePlayerCardTransitionCanvasRepresentable: UIViewRepresentable {

    let canvas: MobilePlayerCardTransitionCanvas

    func makeUIView(context: Context) -> UIView {
        canvas.view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // PlayerInteractionController owns the canvas contents and visibility.
    }
}

struct MobilePlayerView: View {
    
    private let initialConfig: MobilePlayerConfig
    private let onDismiss: () -> Void
    private let browserDensity: MobilePlayerBrowserDensity?
    let cardTransitionCanvas: MobilePlayerCardTransitionCanvas
    @ObservedObject private var chrome: MobilePlayerChromeController
    
    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentProgress: MobileViewingProgress?
    @State private var currentPageLabel = ""
    @State private var currentPagePosition: PlayerPagePosition?
    @State private var isCurrentPagePositionInsertedWidgetToken = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var shareItem: MobilePlayerFileShareItem?
    @State private var isCurrentTokenBookmarked = false
    @State private var displayMode: MobilePlayerDisplayMode
    @State private var displayModeChangeID = UUID()
    @State private var displayModeTargetPagePosition: PlayerPagePosition?
    @State private var pendingDisplayModeApplication: MobilePlayerPendingDisplayModeApplication?
    @State private var focusedPagePositionUpdateCoordinator =
        MobilePlayerFocusedPagePositionUpdateCoordinator()
    
    init(
        config: MobilePlayerConfig,
        onDismiss: @escaping () -> Void,
        chrome: MobilePlayerChromeController,
        cardTransitionCanvas: MobilePlayerCardTransitionCanvas
    ) {
        self.initialConfig = config
        self.onDismiss = onDismiss
        self.chrome = chrome
        self.cardTransitionCanvas = cardTransitionCanvas
        let browserDensity = MobilePlayerBrowserDensity.initialDensity(for: config)
        self.browserDensity = browserDensity
        _displayMode = State(
            initialValue: MobilePlayerDisplayMode.initialMode(
                for: config,
                browserDensity: browserDensity
            )
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
                    displayMode: displayMode,
                    browserDensity: browserDensity,
                    displayModeChangeID: displayModeChangeID,
                    displayModeTargetPagePosition: displayModeTargetPagePosition,
                    onFocusedPagePositionUpdate: handleFocusedPagePositionUpdate,
                    onSettledPagePositionUpdate: handleSettledPagePositionUpdate,
                    onPaginationAttempt: {},
                    onUnavailableNavigation: {
                        chrome.setControlsVisible(true)
                    },
                    onToggleChrome: {
                        chrome.toggleControls()
                    },
                    onDisplayModeApplied: { application in
                        self.handleDisplayModeApplied(application)
                    },
                    onDisplayModeChangeRejected: { rejection in
                        self.handleDisplayModeChangeRejected(rejection)
                    },
                    onDisplayModeChangeSuperseded: { supersession in
                        self.handleDisplayModeChangeSuperseded(supersession)
                    },
                    onZoomStateChange: { isZoomed in
                        chrome.setPlayerContentZoomed(isZoomed)
                    }
                )
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .opacity(chrome.isPlayerContentHiddenForCardTransition ? 0 : 1)
                .allowsHitTesting(!chrome.isPlayerContentHiddenForCardTransition)

                if displayMode == .onePerPage {
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
                            if chrome.showControls, let shareItem {
                                PlayerShareButton(shareItem: shareItem)
                                    .transition(.opacity)
                            }
                            Spacer()
                        }
                        .padding(.leading, 18)
                        .padding(.bottom, bottomChromePadding)
                        .animation(chrome.showControls ? playerChromeToggleAnimation : playerManualGlassHideAnimation, value: chrome.showControls)
                        .animation(playerChromeToggleAnimation, value: shareItem?.fileURL)
                    }
                    .allowsHitTesting(chrome.showControls && shareItem != nil)

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

                MobilePlayerCardTransitionCanvasRepresentable(
                    canvas: cardTransitionCanvas
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(
            !chrome.allowsNavigationBackSwipe
                || chrome.isPlayerContentHiddenForCardTransition
        )
        .statusBar(hidden: shouldHideStatusBar)
        .toolbar {
            if !chrome.allowsNavigationBackSwipe,
               !chrome.isPlayerContentHiddenForCardTransition {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: handleNavigationBarBack) {
                        Images.back
                    }
                    .accessibilityLabel(Strings.back)
                }
            }
            if displayMode == .onePerPage {
                ToolbarItem(placement: .navigationBarTrailing) {
                    infoMenu
                }
                ToolbarItem(placement: .principal) {
                    if chrome.showControls {
                        PlayerCollectionTitlePill(
                            title: currentToken.collectionName,
                            progressText: currentPageLabel
                        )
                    }
                }
            }
        }
        .onDisappear {
            chrome.setLayoutInteractionState(.empty)
            chrome.setPlayerContentHiddenForCardTransition(false)
            focusedPagePositionUpdateCoordinator.cancelPendingUpdate()
            completePendingDisplayModeApplication(didApply: false)
            displayModeTargetPagePosition = nil
        }
        .onReceive(chrome.$displayModeRequest) { request in
            guard let request else { return }
            handleDisplayModeRequest(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadableMediaCacheFileAvailabilityDidChange)) { _ in
            updateShareItem(for: currentPagePosition)
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAllowedToHideStatusBar = true
                    }
                }
            } else {
                isAllowedToHideStatusBar = true
            }
        }
    }

    private var shouldHideStatusBar: Bool {
        displayMode == .onePerPage
            && isAllowedToHideStatusBar
            && !chrome.showControls
    }
    
    private var infoMenu: some View {
        Menu {
            if !doNotShowInstructionsTmp, let instructions = currentToken.instructions {
                Text(instructions)
            }
            Button(Strings.viewOnBlockExplorer, action: viewOnWeb)
        } label: {
            Images.ellipsis
        }
        .accessibilityLabel(Strings.more)
    }
    
    private func viewOnWeb() {
        if let url = currentToken.url {
            UIApplication.shared.open(url)
        }
    }

    private var canBookmarkCurrentToken: Bool {
        !currentToken.fullCollectionId.isEmpty && !currentToken.id.isEmpty
    }

    private func handleNavigationBarBack() {
        guard canSwitchCurrentToCollectionBrowser else {
            onDismiss()
            return
        }

        guard !chrome.requestCollectionBrowserMinimize() else {
            return
        }

        applyDisplayMode(
            .collectionBrowser,
            targetPagePosition: currentPagePosition
        )
    }

    private func handleDisplayModeRequest(_ request: MobilePlayerDisplayModeRequest) {
        defer {
            chrome.clearDisplayModeRequest(request)
        }

        let targetPagePosition: PlayerPagePosition?
        if request.displayMode == .onePerPage {
            if let targetPagePosition = request.targetPagePosition,
               !MobilePlaybackController.shared.canRender(uuid: initialConfig.id, pagePosition: targetPagePosition) {
                request.completion?(false)
                return
            }
            targetPagePosition = request.targetPagePosition
        } else {
            guard request.displayMode == .collectionBrowser,
                  browserDensity != nil,
                  let sourcePagePosition = request.targetPagePosition ?? currentPagePosition,
                  MobilePlaybackController.shared.canRender(
                    uuid: initialConfig.id,
                    pagePosition: sourcePagePosition
                  ) else {
                request.completion?(false)
                return
            }
            targetPagePosition = sourcePagePosition
        }

        if pendingDisplayModeApplication?.matches(
            displayMode: request.displayMode,
            targetPagePosition: targetPagePosition
        ) == true {
            request.completion?(false)
            return
        }

        completePendingDisplayModeApplication(didApply: false)
        if let completion = request.completion {
            pendingDisplayModeApplication = MobilePlayerPendingDisplayModeApplication(
                displayModeChangeID: request.id,
                requestedDisplayMode: request.displayMode,
                targetPagePosition: targetPagePosition,
                completion: completion
            )
        }

        let didAcceptRequest = applyDisplayMode(
            request.displayMode,
            targetPagePosition: targetPagePosition,
            changeID: request.id
        )
        if !didAcceptRequest {
            completePendingDisplayModeApplication(
                request.id,
                didApply: false
            )
        }
    }

    private func handleDisplayModeApplied(_ application: MobilePlayerDisplayModeApplication) {
        guard displayModeChangeID == application.displayModeChangeID,
              displayMode == application.requestedDisplayMode else {
            return
        }

        chrome.setNavigationBackSwipeAllowed(
            application.requestedDisplayMode == .collectionBrowser
        )

        if displayModeTargetPagePosition == application.targetPagePosition {
            displayModeTargetPagePosition = nil
        }

        completePendingDisplayModeApplication(
            application.displayModeChangeID,
            didApply: true
        )
    }

    private func completePendingDisplayModeApplication(
        _ displayModeChangeID: UUID,
        didApply: Bool
    ) {
        guard let pendingDisplayModeApplication,
              pendingDisplayModeApplication.displayModeChangeID == displayModeChangeID else {
            return
        }

        let completion = pendingDisplayModeApplication.completion
        self.pendingDisplayModeApplication = nil
        completion(didApply)
    }

    private func completePendingDisplayModeApplication(didApply: Bool) {
        guard let pendingDisplayModeApplication else { return }
        completePendingDisplayModeApplication(
            pendingDisplayModeApplication.displayModeChangeID,
            didApply: didApply
        )
    }

    private func handleDisplayModeChangeSuperseded(
        _ supersession: MobilePlayerDisplayModeSupersession
    ) {
        completePendingDisplayModeApplication(
            supersession.displayModeChangeID,
            didApply: false
        )
    }

    private func handleDisplayModeChangeRejected(
        _ rejection: MobilePlayerDisplayModeRejection
    ) {
        guard displayModeChangeID == rejection.displayModeChangeID,
              displayMode == rejection.requestedDisplayMode,
              displayModeTargetPagePosition == rejection.targetPagePosition else { return }

        displayMode = rejection.currentDisplayMode
        chrome.setNavigationBackSwipeAllowed(
            rejection.currentDisplayMode == .collectionBrowser
        )
        displayModeChangeID = UUID()
        displayModeTargetPagePosition = nil
        completePendingDisplayModeApplication(
            rejection.displayModeChangeID,
            didApply: false
        )

        updateNavigationAvailability(for: currentPagePosition)
        updateLayoutInteractionState()
    }

    private var canSwitchCurrentToCollectionBrowser: Bool {
        guard displayMode == .onePerPage,
              browserDensity != nil,
              let currentPagePosition else {
            return false
        }

        return MobilePlaybackController.shared.canRender(
            uuid: initialConfig.id,
            pagePosition: currentPagePosition
        )
    }

    @discardableResult
    private func applyDisplayMode(
        _ requestedDisplayMode: MobilePlayerDisplayMode,
        targetPagePosition: PlayerPagePosition? = nil,
        changeID: UUID = UUID()
    ) -> Bool {
        guard requestedDisplayMode != .collectionBrowser || browserDensity != nil else {
            return false
        }

        if requestedDisplayMode == .onePerPage {
            chrome.setNavigationBackSwipeAllowed(false)
        }

        displayModeTargetPagePosition = targetPagePosition
        displayModeChangeID = changeID
        displayMode = requestedDisplayMode
        updateNavigationAvailability(for: currentPagePosition)
        updateLayoutInteractionState()
        return true
    }

    private func updateLayoutInteractionState() {
        chrome.setLayoutInteractionState(
            MobilePlaybackController.shared.layoutInteractionState(
                uuid: initialConfig.id,
                displayMode: displayMode,
                pagePosition: currentPagePosition,
                browserDensity: browserDensity
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
            chrome.setPlayerBackgroundColor(MobilePlayerBackgroundColor.color(for: token))

            self.currentPagePosition = pagePosition
            self.currentToken = token
            self.currentProgress = progress
            self.currentPageLabel = pageLabel
            self.isCurrentPagePositionInsertedWidgetToken = isInsertedWidgetToken
            self.updateLayoutInteractionState()
            self.updateNavigationAvailability(for: pagePosition)
            self.updateShareItem(for: pagePosition)
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
        guard displayMode == .onePerPage,
              let pagePosition else {
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

    private func updateShareItem(for pagePosition: PlayerPagePosition?) {
        guard let pagePosition else {
            shareItem = nil
            return
        }

        shareItem = MobilePlaybackController.shared.downloadedFileShareItem(
            uuid: initialConfig.id,
            pagePosition: pagePosition
        )
    }

}

private struct PlayerCollectionTitlePill: View {
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
            .frame(maxWidth: 220)
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
