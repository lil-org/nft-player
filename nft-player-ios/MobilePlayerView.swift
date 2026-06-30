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
    let completion: (() -> Void)?
}

private struct MobilePlayerPendingPageLayoutCompletion {
    let pageLayout: MobilePlayerPageLayout
    let completion: () -> Void
}

struct MobilePlayerLayoutInteractionState: Equatable {
    let pageLayout: MobilePlayerPageLayout
    let collectionId: String
    let tokenIndex: Int?
    let supportsFourPerPage: Bool
    let currentDescriptor: DownloadableMediaDescriptor?
    let fourPerPageDescriptors: [DownloadableMediaDescriptor]

    static let empty = MobilePlayerLayoutInteractionState(
        pageLayout: .onePerPage,
        collectionId: "",
        tokenIndex: nil,
        supportsFourPerPage: false,
        currentDescriptor: nil,
        fourPerPageDescriptors: []
    )

    var canMinimizeCardNftToFourPerPage: Bool {
        MobilePlayerPageLayout.isCardNftCollection(collectionId)
            && pageLayout == .onePerPage
            && supportsFourPerPage
            && currentDescriptor != nil
            && fourPerPageSelectedSlot != nil
    }

    var fourPerPageSelectedSlot: Int? {
        if let currentDescriptor,
           let descriptorIndex = fourPerPageDescriptors.firstIndex(of: currentDescriptor) {
            return descriptorIndex
        }

        guard let tokenIndex else { return nil }
        let fallbackSlot = max(tokenIndex, 0) % MobilePlayerPageLayout.fourPerPage.pageSize
        guard fourPerPageDescriptors.indices.contains(fallbackSlot) else { return nil }
        return fallbackSlot
    }
}

final class MobilePlayerChromeController: ObservableObject {
    @Published private(set) var showControls = false
    @Published private(set) var isStatusBarRevealedByDismiss = false
    @Published private(set) var isPlayerContentHiddenByCardMinimize = false
    @Published private(set) var pageLayoutRequest: MobilePlayerPageLayoutRequest?
    private(set) var playerBackgroundColor: UIColor
    private(set) var isPlayerContentZoomed = false
    private(set) var layoutInteractionState = MobilePlayerLayoutInteractionState.empty
    var onPlayerBackgroundColorChange: ((UIColor) -> Void)?

    init(playerBackgroundColor: UIColor = MobilePlayerBackgroundColor.defaultColor) {
        self.playerBackgroundColor = playerBackgroundColor
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

    func setPlayerContentHiddenByCardMinimize(_ isHidden: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setPlayerContentHiddenByCardMinimize(isHidden) }
            return
        }

        guard isPlayerContentHiddenByCardMinimize != isHidden else { return }
        isPlayerContentHiddenByCardMinimize = isHidden
    }

    func setLayoutInteractionState(_ state: MobilePlayerLayoutInteractionState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setLayoutInteractionState(state) }
            return
        }

        guard layoutInteractionState != state else { return }
        layoutInteractionState = state
    }

    func requestPageLayout(_ pageLayout: MobilePlayerPageLayout, completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.requestPageLayout(pageLayout, completion: completion) }
            return
        }

        pageLayoutRequest = MobilePlayerPageLayoutRequest(pageLayout: pageLayout, completion: completion)
    }

    func clearPageLayoutRequest(_ request: MobilePlayerPageLayoutRequest) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.clearPageLayoutRequest(request) }
            return
        }

        guard pageLayoutRequest?.id == request.id else { return }
        pageLayoutRequest = nil
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
    @State private var supportsCurrentFourPerPageLayout = false
    @State private var pendingPageLayoutCompletion: MobilePlayerPendingPageLayoutCompletion?
    
    init(config: MobilePlayerConfig, onDismiss: @escaping () -> Void, chrome: MobilePlayerChromeController) {
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
                    pageLayout: pageLayout,
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
                            let supportsFourPerPageLayout = self.supportsFourPerPageLayout(for: newPagePosition)
                            self.supportsCurrentFourPerPageLayout = supportsFourPerPageLayout
                            if !supportsFourPerPageLayout && self.pageLayout == .fourPerPage {
                                self.pageLayout = .onePerPage
                            }
                            self.updateLayoutInteractionState()
                            self.updateNavigationAvailability(for: newPagePosition)
                            self.updateShareItem(for: newPagePosition)
                            self.updateBookmarkState(for: token)
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
                    onPageLayoutContentReady: { readyPageLayout in
                        self.completePendingPageLayoutRequest(for: readyPageLayout)
                    },
                    onZoomStateChange: { isZoomed in
                        chrome.setPlayerContentZoomed(isZoomed)
                    }
                )
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .opacity(chrome.isPlayerContentHiddenByCardMinimize ? 0 : 1)
                .allowsHitTesting(!chrome.isPlayerContentHiddenByCardMinimize)

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
            chrome.setPlayerContentHiddenByCardMinimize(false)
            pendingPageLayoutCompletion = nil
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
        guard canSwitchCurrentCardNftToFourPerPage else {
            onDismiss()
            return
        }

        applyPageLayout(.fourPerPage)
    }

    private func supportsFourPerPageLayout(for pagePosition: PlayerPagePosition) -> Bool {
        return MobilePlaybackController.shared.supportsPageLayout(
            .fourPerPage,
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
            didAcceptRequest = applyPageLayout(.onePerPage)
        case .fourPerPage:
            guard canSwitchCurrentCardNftToFourPerPage else {
                request.completion?()
                return
            }
            didAcceptRequest = applyPageLayout(.fourPerPage)
        }

        guard didAcceptRequest else {
            request.completion?()
            return
        }

        if let completion = request.completion {
            pendingPageLayoutCompletion = MobilePlayerPendingPageLayoutCompletion(
                pageLayout: request.pageLayout,
                completion: completion
            )
        }
    }

    private func completePendingPageLayoutRequest(for readyPageLayout: MobilePlayerPageLayout) {
        guard let pendingPageLayoutCompletion,
              pendingPageLayoutCompletion.pageLayout == readyPageLayout else {
            return
        }

        let completion = pendingPageLayoutCompletion.completion
        self.pendingPageLayoutCompletion = nil
        DispatchQueue.main.async {
            completion()
        }
    }

    private var canSwitchCurrentCardNftToFourPerPage: Bool {
        MobilePlayerPageLayout.isCardNftCollection(currentToken.fullCollectionId)
            && pageLayout == .onePerPage
            && supportsCurrentFourPerPageLayout
    }

    @discardableResult
    private func applyPageLayout(_ requestedPageLayout: MobilePlayerPageLayout) -> Bool {
        guard pageLayout != requestedPageLayout else {
            updateLayoutInteractionState()
            return false
        }

        pageLayout = requestedPageLayout
        updateNavigationAvailability(for: currentPagePosition)
        updateLayoutInteractionState()
        return true
    }

    private func updateLayoutInteractionState() {
        guard canSwitchCurrentCardNftToFourPerPage else {
            chrome.setLayoutInteractionState(.empty)
            return
        }

        let currentDescriptor = currentDownloadableMediaDescriptor()
        guard let currentDescriptor else {
            chrome.setLayoutInteractionState(.empty)
            return
        }

        chrome.setLayoutInteractionState(
            MobilePlayerLayoutInteractionState(
                pageLayout: pageLayout,
                collectionId: currentToken.fullCollectionId,
                tokenIndex: currentDescriptor.tokenIndex,
                supportsFourPerPage: supportsCurrentFourPerPageLayout,
                currentDescriptor: currentDescriptor,
                fourPerPageDescriptors: fourPerPageDescriptors(containing: currentPagePosition)
            )
        )
    }

    private func currentDownloadableMediaDescriptor() -> DownloadableMediaDescriptor? {
        guard let currentPagePosition else { return nil }
        return MobilePlaybackController.shared.downloadableMediaDescriptor(
            uuid: initialConfig.id,
            pagePosition: currentPagePosition
        )
    }

    private func fourPerPageDescriptors(containing pagePosition: PlayerPagePosition?) -> [DownloadableMediaDescriptor] {
        guard let pagePosition else { return [] }

        let stablePagePosition = MobilePlaybackController.shared.stablePagePosition(
            uuid: initialConfig.id,
            containing: pagePosition,
            pageLayout: .fourPerPage
        )

        var descriptors = [DownloadableMediaDescriptor]()
        descriptors.reserveCapacity(MobilePlayerPageLayout.fourPerPage.pageSize)
        for offset in 0..<MobilePlayerPageLayout.fourPerPage.pageSize {
            let descriptorPagePosition = stablePagePosition.advanced(by: offset)
            guard let descriptor = MobilePlaybackController.shared.downloadableMediaDescriptor(
                uuid: initialConfig.id,
                pagePosition: descriptorPagePosition
            ) else {
                break
            }

            guard MobilePlayerPageLayout.fourPerPage.supports(descriptor: descriptor) else {
                break
            }

            descriptors.append(descriptor)
        }
        return descriptors
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

struct ProgressCapsuleBackground: View {
    let progress: Double
    var isInteractive = false

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                if #available(iOS 26.0, *) {
                    liquidGlassBase
                } else {
                    fallbackBase
                }

                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(width: geometry.size.width * clampedProgress)
            }
            .clipShape(Capsule())
        }
    }

    private var fallbackBase: some View {
        Capsule()
            .fill(.black.opacity(0.66))
            .background(.ultraThinMaterial, in: Capsule())
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var liquidGlassBase: some View {
        if isInteractive {
            Capsule()
                .fill(.white.opacity(0.08))
                .glassEffect(.regular.tint(.black.opacity(0.42)).interactive(), in: Capsule())
                .glassEffectTransition(.materialize)
        } else {
            Capsule()
                .fill(.white.opacity(0.08))
                .glassEffect(.regular.tint(.black.opacity(0.42)), in: Capsule())
                .glassEffectTransition(.materialize)
        }
    }
}
