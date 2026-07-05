// ∅ 2026 lil org

import SwiftUI
import UIKit
import LinkPresentation

struct MobilePlayerConfig: Hashable, Codable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
    var initialTokenId: String?
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

struct MobilePlayerPageLayoutRequest {
    let id = UUID()
    let pageLayout: MobilePlayerPageLayout
    let targetPagePosition: PlayerPagePosition?
    let completion: (() -> Void)?
}

struct MobilePlayerPageLayoutRejection {
    let pageLayoutChangeID: UUID
    let requestedPageLayout: MobilePlayerPageLayout
    let targetPagePosition: PlayerPagePosition?
    let currentPageLayout: MobilePlayerPageLayout
}

struct MobilePlayerPageLayoutApplication {
    let pageLayoutChangeID: UUID
    let requestedPageLayout: MobilePlayerPageLayout
    let targetPagePosition: PlayerPagePosition?
}

enum MobilePlayerStaticImageGridExpandSelectionResult {
    case started
    case busy
    case fallbackToImmediateOpen
    case rejected
}

private struct MobilePlayerPendingPageLayoutApplication {
    let pageLayoutChangeID: UUID
    let targetPagePosition: PlayerPagePosition?
    let completion: () -> Void
}

struct MobilePlayerStaticImageGridSelection {
    let pageLayout: MobilePlayerPageLayout
    let pagePosition: PlayerPagePosition
    let selectedSlotIndex: Int
    let descriptors: [DownloadableMediaDescriptor]
    let images: [UIImage?]

    init?(
        pageLayout: MobilePlayerPageLayout,
        pagePosition: PlayerPagePosition,
        selectedSlotIndex: Int,
        descriptors: [DownloadableMediaDescriptor],
        images: [UIImage?]
    ) {
        guard pageLayout.isStaticImageGrid,
              descriptors.indices.contains(selectedSlotIndex),
              images.count == descriptors.count else {
            return nil
        }

        let selectedDescriptor = descriptors[selectedSlotIndex]
        guard pageLayout.supports(descriptor: selectedDescriptor) else {
            return nil
        }

        self.pageLayout = pageLayout
        self.pagePosition = pagePosition
        self.selectedSlotIndex = selectedSlotIndex
        self.descriptors = descriptors
        self.images = images
    }

    var selectedDescriptor: DownloadableMediaDescriptor {
        descriptors[selectedSlotIndex]
    }

    var selectedImage: UIImage? {
        images[selectedSlotIndex]
    }

    var selectedImageSize: CGSize {
        selectedImage?.size ?? MobilePlayerPageLayout.staticImageGridFallbackImageSize(for: selectedDescriptor)
    }

    var imageSizes: [CGSize] {
        MobilePlayerPageLayout.staticImageGridImageSizes(for: descriptors, images: images)
    }

}

protocol MobilePlayerStaticImageGridSelectionProviding: AnyObject {
    func canSelectStaticImageGrid(at location: CGPoint, in coordinateView: UIView) -> Bool
    func staticImageGridSelection(at location: CGPoint, in coordinateView: UIView) -> MobilePlayerStaticImageGridSelection?
}

enum MobilePlayerStaticImageGridSwitchMode: Equatable {
    case animated(descriptors: [DownloadableMediaDescriptor])
    case direct(descriptors: [DownloadableMediaDescriptor])
}

struct MobilePlayerLayoutInteractionState: Equatable {
    let pageLayout: MobilePlayerPageLayout
    let tokenIndex: Int?
    let staticImageGridPageLayout: MobilePlayerPageLayout?
    let currentDescriptor: DownloadableMediaDescriptor?
    let staticImageGridSwitchMode: MobilePlayerStaticImageGridSwitchMode

    static let empty = MobilePlayerLayoutInteractionState(
        pageLayout: .onePerPage,
        tokenIndex: nil,
        staticImageGridPageLayout: nil,
        currentDescriptor: nil,
        staticImageGridSwitchMode: .animated(descriptors: [])
    )

    var canSwitchDirectlyToStaticImageGrid: Bool {
        guard case .direct(let descriptors) = staticImageGridSwitchMode,
              !descriptors.isEmpty else {
            return false
        }

        return canUseCurrentStaticImageGridLayout
    }

    var canMinimizeToStaticImageGrid: Bool {
        guard case .animated = staticImageGridSwitchMode else { return false }

        return canUseCurrentStaticImageGridLayout
            && staticImageGridSelectedSlot != nil
    }

    var staticImageGridDescriptors: [DownloadableMediaDescriptor] {
        switch staticImageGridSwitchMode {
        case .animated(let descriptors):
            return descriptors
        case .direct(let descriptors):
            return descriptors
        }
    }

    var staticImageGridSelectedSlot: Int? {
        if let currentDescriptor,
           let descriptorIndex = staticImageGridDescriptors.firstIndex(of: currentDescriptor) {
            return descriptorIndex
        }

        guard let tokenIndex,
              let staticImageGridPageLayout else { return nil }
        let fallbackSlot = max(tokenIndex, 0) % staticImageGridPageLayout.pageSize
        guard staticImageGridDescriptors.indices.contains(fallbackSlot) else { return nil }
        return fallbackSlot
    }

    private var canUseCurrentStaticImageGridLayout: Bool {
        guard let staticImageGridPageLayout else { return false }

        return pageLayout == .onePerPage
            && staticImageGridPageLayout.supports(descriptor: currentDescriptor)
    }
}

final class MobilePlayerChromeController: ObservableObject {
    @Published private(set) var showControls = false
    @Published private(set) var isStatusBarRevealedByDismiss = false
    @Published private(set) var isPlayerContentHiddenForCardTransition = false
    @Published private(set) var pageLayoutRequest: MobilePlayerPageLayoutRequest?
    private(set) var playerBackgroundColor: UIColor
    private(set) var isPlayerContentZoomed = false
    private(set) var layoutInteractionState = MobilePlayerLayoutInteractionState.empty
    var onPlayerBackgroundColorChange: ((UIColor) -> Void)?
    var onStaticImageGridMinimizeRequest: (() -> Bool)?
    var onStaticImageGridExpandRequest: ((MobilePlayerStaticImageGridSelection) -> MobilePlayerStaticImageGridExpandSelectionResult)?
    private weak var staticImageGridSelectionProvider: (any MobilePlayerStaticImageGridSelectionProviding)?
    private var liveLayoutInteractionStateProviderID: UUID?
    private var liveLayoutInteractionStateProvider: (() -> MobilePlayerLayoutInteractionState)?

    init(playerBackgroundColor: UIColor = MobilePlayerBackgroundColor.defaultColor) {
        self.playerBackgroundColor = playerBackgroundColor
    }

    func setStaticImageGridSelectionProvider(_ provider: any MobilePlayerStaticImageGridSelectionProviding) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setStaticImageGridSelectionProvider(provider)
            }
            return
        }

        staticImageGridSelectionProvider = provider
    }

    func clearStaticImageGridSelectionProvider(_ provider: any MobilePlayerStaticImageGridSelectionProviding) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.clearStaticImageGridSelectionProvider(provider)
            }
            return
        }

        guard staticImageGridSelectionProvider === provider else { return }

        staticImageGridSelectionProvider = nil
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

    func canSelectStaticImageGrid(at location: CGPoint, in coordinateView: UIView) -> Bool {
        guard Thread.isMainThread else { return false }

        return staticImageGridSelectionProvider?.canSelectStaticImageGrid(
            at: location,
            in: coordinateView
        ) == true
    }

    func staticImageGridSelection(at location: CGPoint, in coordinateView: UIView) -> MobilePlayerStaticImageGridSelection? {
        guard Thread.isMainThread else { return nil }

        return staticImageGridSelectionProvider?.staticImageGridSelection(at: location, in: coordinateView)
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

    func setStatusBarRevealedByDismiss(_ isRevealed: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setStatusBarRevealedByDismiss(isRevealed) }
            return
        }

        guard isStatusBarRevealedByDismiss != isRevealed else { return }
        isStatusBarRevealedByDismiss = isRevealed
    }

    func setPlayerBackgroundColor(_ color: UIColor) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setPlayerBackgroundColor(color) }
            return
        }

        guard !playerBackgroundColor.isVisuallyEqual(to: color) else { return }
        playerBackgroundColor = color
        onPlayerBackgroundColorChange?(color)
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

    func setLayoutInteractionState(_ state: MobilePlayerLayoutInteractionState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setLayoutInteractionState(state) }
            return
        }

        guard layoutInteractionState != state else { return }
        layoutInteractionState = state
    }

    @discardableResult
    func requestPageLayout(
        _ pageLayout: MobilePlayerPageLayout,
        targetPagePosition: PlayerPagePosition? = nil,
        completion: (() -> Void)? = nil
    ) -> UUID {
        let request = MobilePlayerPageLayoutRequest(
            pageLayout: pageLayout,
            targetPagePosition: targetPagePosition,
            completion: completion
        )

        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.pageLayoutRequest = request
            }
            return request.id
        }

        pageLayoutRequest = request
        return request.id
    }

    func clearPageLayoutRequest(_ request: MobilePlayerPageLayoutRequest) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.clearPageLayoutRequest(request) }
            return
        }

        guard pageLayoutRequest?.id == request.id else { return }
        pageLayoutRequest = nil
    }

    @discardableResult
    func requestStaticImageGridMinimize() -> Bool {
        guard Thread.isMainThread else { return false }

        return onStaticImageGridMinimizeRequest?() == true
    }

    @discardableResult
    func requestStaticImageGridExpand(
        _ selection: MobilePlayerStaticImageGridSelection
    ) -> MobilePlayerStaticImageGridExpandSelectionResult {
        guard Thread.isMainThread else { return .rejected }

        return onStaticImageGridExpandRequest?(selection) ?? .fallbackToImmediateOpen
    }
}

struct MobilePlayerView: View {
    
    private let initialConfig: MobilePlayerConfig
    private let onDismiss: () -> Void
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
    @State private var pageLayout: MobilePlayerPageLayout
    @State private var pageLayoutChangeID = UUID()
    @State private var pageLayoutTargetPagePosition: PlayerPagePosition?
    @State private var pendingPageLayoutApplication: MobilePlayerPendingPageLayoutApplication?
    
    init(
        config: MobilePlayerConfig,
        onDismiss: @escaping () -> Void,
        chrome: MobilePlayerChromeController
    ) {
        self.initialConfig = config
        self.onDismiss = onDismiss
        self.chrome = chrome
        _pageLayout = State(initialValue: MobilePlayerPageLayout.initialLayout(for: config))
    }

    var body: some View {
        GeometryReader { geometry in
            let bottomChromePadding = MobileBottomChromeSpacing.padding(forSafeAreaBottom: geometry.safeAreaInsets.bottom)

            ZStack {
                HorizontalPlayerContainerView(
                    initialConfig: initialConfig,
                    chrome: chrome,
                    pageLayout: pageLayout,
                    pageLayoutChangeID: pageLayoutChangeID,
                    pageLayoutTargetPagePosition: pageLayoutTargetPagePosition,
                    onPagePositionUpdate: { newPagePosition in
                        DispatchQueue.main.async {
                            let token = MobilePlaybackController.shared.getToken(uuid: initialConfig.id, pagePosition: newPagePosition)
                            chrome.setPlayerBackgroundColor(MobilePlayerBackgroundColor.color(for: token))

                            let progress = MobilePlaybackController.shared.markViewed(uuid: initialConfig.id, pagePosition: newPagePosition)
                            self.currentPagePosition = newPagePosition
                            self.currentToken = token
                            self.currentProgress = progress
                            self.currentPageLabel = MobilePlaybackController.shared.pageLabel(
                                uuid: initialConfig.id,
                                pagePosition: newPagePosition
                            ) ?? ""
                            self.isCurrentPagePositionInsertedWidgetToken = MobilePlaybackController.shared.isInsertedWidgetToken(
                                uuid: initialConfig.id,
                                pagePosition: newPagePosition
                            )
                            let staticImageGridPageLayout = self.staticImageGridPageLayout(for: newPagePosition)
                            if self.pageLayout.isStaticImageGrid && staticImageGridPageLayout != self.pageLayout {
                                self.pageLayoutChangeID = UUID()
                                self.pageLayout = .onePerPage
                            }
                            self.updateLayoutInteractionState()
                            self.updateNavigationAvailability(for: newPagePosition)
                            self.updateShareItem(for: newPagePosition)
                            self.updateBookmarkState(for: token)
                            if self.pageLayoutTargetPagePosition == newPagePosition {
                                self.pageLayoutTargetPagePosition = nil
                            }
                            updateExternalDisplayToken(token)
                        }
                    },
                    onPaginationAttempt: {},
                    onUnavailableNavigation: {
                        chrome.setControlsVisible(true)
                    },
                    onToggleChrome: {
                        chrome.toggleControls()
                    },
                    onPageLayoutChangeRequest: { requestedPageLayout in
                        self.applyPageLayout(requestedPageLayout)
                    },
                    onPageLayoutApplied: { application in
                        self.handlePageLayoutApplied(application)
                    },
                    onPageLayoutChangeRejected: { rejection in
                        self.handlePageLayoutChangeRejected(rejection)
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
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chrome.showControls ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .statusBar(hidden: shouldHideStatusBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: handleNavigationBarBack) {
                    Images.back
                }
                .accessibilityLabel(Strings.back)
            }
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
        .onDisappear {
            chrome.setLayoutInteractionState(.empty)
            chrome.setPlayerContentHiddenForCardTransition(false)
            pendingPageLayoutApplication = nil
            pageLayoutTargetPagePosition = nil
            updateExternalDisplayToken(GeneratedToken.empty)
            NativeMetalCardView.resetMotionCalibration()
            MobilePlaybackController.shared.stopAndDisconnect(uuid: initialConfig.id)
        }
        .onReceive(chrome.$pageLayoutRequest) { request in
            guard let request else { return }
            handlePageLayoutRequest(request)
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
        isAllowedToHideStatusBar && !chrome.showControls && !chrome.isStatusBarRevealedByDismiss
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
        guard let staticImageGridPageLayout = currentStaticImageGridPageLayout,
              canSwitchCurrentToStaticImageGrid else {
            onDismiss()
            return
        }

        guard !chrome.requestStaticImageGridMinimize() else {
            return
        }

        applyPageLayout(staticImageGridPageLayout)
    }

    private func staticImageGridPageLayout(for pagePosition: PlayerPagePosition) -> MobilePlayerPageLayout? {
        return MobilePlaybackController.shared.staticImageGridLayout(
            uuid: initialConfig.id,
            pagePosition: pagePosition
        )
    }

    private func handlePageLayoutRequest(_ request: MobilePlayerPageLayoutRequest) {
        defer {
            chrome.clearPageLayoutRequest(request)
        }

        let didAcceptRequest: Bool
        switch request.pageLayout {
        case .onePerPage:
            if let targetPagePosition = request.targetPagePosition,
               !MobilePlaybackController.shared.canRender(uuid: initialConfig.id, pagePosition: targetPagePosition) {
                request.completion?()
                return
            }
            didAcceptRequest = applyPageLayout(
                .onePerPage,
                targetPagePosition: request.targetPagePosition,
                changeID: request.id
            )
        case .fourPerPage, .sixPerPage:
            guard canSwitchCurrentToStaticImageGrid,
                  currentStaticImageGridPageLayout == request.pageLayout else {
                request.completion?()
                return
            }
            didAcceptRequest = applyPageLayout(request.pageLayout, changeID: request.id)
        }

        guard didAcceptRequest else {
            request.completion?()
            return
        }

        if let completion = request.completion {
            pendingPageLayoutApplication = MobilePlayerPendingPageLayoutApplication(
                pageLayoutChangeID: request.id,
                targetPagePosition: request.targetPagePosition,
                completion: completion
            )
        }
    }

    private func handlePageLayoutApplied(_ application: MobilePlayerPageLayoutApplication) {
        guard pageLayoutChangeID == application.pageLayoutChangeID,
              pageLayout == application.requestedPageLayout else {
            return
        }

        if pageLayoutTargetPagePosition == application.targetPagePosition {
            pageLayoutTargetPagePosition = nil
        }

        completePendingPageLayoutApplication(application.pageLayoutChangeID)
    }

    private func completePendingPageLayoutApplication(_ pageLayoutChangeID: UUID) {
        guard let pendingPageLayoutApplication,
              pendingPageLayoutApplication.pageLayoutChangeID == pageLayoutChangeID else {
            return
        }

        let completion = pendingPageLayoutApplication.completion
        self.pendingPageLayoutApplication = nil
        DispatchQueue.main.async {
            completion()
        }
    }

    private func handlePageLayoutChangeRejected(
        _ rejection: MobilePlayerPageLayoutRejection
    ) {
        guard pageLayoutChangeID == rejection.pageLayoutChangeID,
              pageLayout == rejection.requestedPageLayout,
              pageLayoutTargetPagePosition == rejection.targetPagePosition else { return }

        pageLayout = rejection.currentPageLayout
        pageLayoutChangeID = UUID()
        pageLayoutTargetPagePosition = nil

        completePendingPageLayoutApplication(rejection.pageLayoutChangeID)

        updateNavigationAvailability(for: currentPagePosition)
        updateLayoutInteractionState()
    }

    private var canSwitchCurrentToStaticImageGrid: Bool {
        pageLayout == .onePerPage
            && currentStaticImageGridPageLayout != nil
    }

    private var currentStaticImageGridPageLayout: MobilePlayerPageLayout? {
        guard let currentPagePosition else { return nil }
        return staticImageGridPageLayout(for: currentPagePosition)
    }

    @discardableResult
    private func applyPageLayout(
        _ requestedPageLayout: MobilePlayerPageLayout,
        targetPagePosition: PlayerPagePosition? = nil,
        changeID: UUID = UUID()
    ) -> Bool {
        guard !isPageLayoutRequestAlreadyApplied(
            requestedPageLayout,
            targetPagePosition: targetPagePosition
        ) else {
            if targetPagePosition != nil {
                pageLayoutTargetPagePosition = nil
            }
            updateLayoutInteractionState()
            return false
        }

        if let targetPagePosition {
            pageLayoutTargetPagePosition = targetPagePosition
            pageLayoutChangeID = changeID
        } else if pageLayout != requestedPageLayout {
            pageLayoutTargetPagePosition = nil
            pageLayoutChangeID = changeID
        }

        guard pageLayout != requestedPageLayout else {
            updateLayoutInteractionState()
            return targetPagePosition != nil
        }

        pageLayout = requestedPageLayout
        updateNavigationAvailability(for: currentPagePosition)
        updateLayoutInteractionState()
        return true
    }

    private func isPageLayoutRequestAlreadyApplied(
        _ requestedPageLayout: MobilePlayerPageLayout,
        targetPagePosition: PlayerPagePosition?
    ) -> Bool {
        guard pageLayout == requestedPageLayout else { return false }
        guard let targetPagePosition else { return true }
        return currentPagePosition == targetPagePosition
    }

    private func updateLayoutInteractionState() {
        chrome.setLayoutInteractionState(
            MobilePlaybackController.shared.layoutInteractionState(
                uuid: initialConfig.id,
                pageLayout: pageLayout,
                pagePosition: currentPagePosition
            )
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

        let stablePagePosition = MobilePlaybackController.shared.stablePagePosition(
            uuid: initialConfig.id,
            containing: pagePosition,
            pageLayout: pageLayout
        )
        canGoBack = hasNavigationDestination(from: stablePagePosition, direction: .back)
        canGoForward = hasNavigationDestination(from: stablePagePosition, direction: .forward)
    }

    private func hasNavigationDestination(
        from pagePosition: PlayerPagePosition,
        direction: PlaybackNavigationDirection
    ) -> Bool {
        MobilePlaybackController.shared.hasNavigationDestination(
            uuid: initialConfig.id,
            from: pagePosition,
            pageLayout: pageLayout,
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
            if progress?.isComplete == true {
                completionActions
            }
            progressNavigationControls
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
