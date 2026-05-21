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
}

private let doNotShowInstructionsTmp = true
private let playerChromeToggleAnimation = Animation.easeInOut(duration: 0.12)
private let playerManualGlassHideAnimation = Animation.smooth(duration: 0.23)
private let playerNavigationBarControlSize: CGFloat = 44
private let playerProgressControlSize: CGFloat = 34
private let playerNavigationArrowSpacing: CGFloat = 4

final class MobilePlayerChromeController: ObservableObject {
    @Published private(set) var showControls = true
    @Published private(set) var isStatusBarRevealedByDismiss = false
    private(set) var playerBackgroundColor: UIColor
    private(set) var isPlayerContentZoomed = false
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
}

struct MobilePlayerView: View {
    
    private let initialConfig: MobilePlayerConfig
    private let onDismiss: () -> Void
    @ObservedObject private var chrome: MobilePlayerChromeController
    
    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentProgress: MobileViewingProgress?
    @State private var currentCoordinate: PlayerCoordinate?
    @State private var shareItem: MobilePlayerFileShareItem?
    @State private var isCurrentTokenBookmarked = false
    
    init(config: MobilePlayerConfig, onDismiss: @escaping () -> Void, chrome: MobilePlayerChromeController) {
        self.initialConfig = config
        self.onDismiss = onDismiss
        self.chrome = chrome
    }

    var body: some View {
        GeometryReader { geometry in
            let bottomChromePadding = MobileBottomChromeSpacing.padding(forSafeAreaBottom: geometry.safeAreaInsets.bottom)

            ZStack {
                FourDirectionalPlayerContainerView(
                    initialConfig: initialConfig,
                    onCoordinateUpdate: { newCoordinate in
                        DispatchQueue.main.async {
                            let token = MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: newCoordinate)
                            chrome.setPlayerBackgroundColor(MobilePlayerBackgroundColor.color(for: token))

                            let progress = MobilePlaybackController.shared.markViewed(uuid: initialConfig.id, coordinate: newCoordinate)
                            self.currentCoordinate = newCoordinate
                            self.currentToken = token
                            self.currentProgress = progress
                            self.updateShareItem(for: newCoordinate)
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
                    onZoomStateChange: { isZoomed in
                        chrome.setPlayerContentZoomed(isZoomed)
                    }
                )
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())

                VStack {
                    Spacer()
                    PlayerBottomControls(
                        isVisible: chrome.showControls,
                        progress: currentProgress,
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
                Button(action: onDismiss) {
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
                        progressText: currentProgress?.pageLabel ?? ""
                    )
                }
            }
        }
        .onDisappear {
            updateExternalDisplayToken(GeneratedToken.empty)
            PonchoDrifellaMetalCardView.resetMotionCalibration()
            MobilePlaybackController.shared.stopAndDisconnect(uuid: initialConfig.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadableMediaCacheFileAvailabilityDidChange)) { _ in
            updateShareItem(for: currentCoordinate)
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

    private var canGoBack: Bool {
        guard let currentProgress else { return false }
        return currentProgress.tokenIndex > 0
    }

    private var canGoForward: Bool {
        guard let currentProgress else { return false }
        return currentProgress.tokenIndex < currentProgress.tokenCount - 1
    }

    private var canBookmarkCurrentToken: Bool {
        !currentToken.fullCollectionId.isEmpty && !currentToken.id.isEmpty
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

    private func updateShareItem(for coordinate: PlayerCoordinate?) {
        guard let coordinate else {
            shareItem = nil
            return
        }

        shareItem = MobilePlaybackController.shared.downloadedFileShareItem(
            uuid: initialConfig.id,
            coordinate: coordinate
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
