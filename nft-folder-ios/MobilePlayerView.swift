// ∅ 2026 lil org

import SwiftUI
import UIKit

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
}

struct MobilePlayerView: View {
    
    private let initialConfig: MobilePlayerConfig
    private let onDismiss: () -> Void
    @ObservedObject private var chrome: MobilePlayerChromeController
    
    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentProgress: MobileViewingProgress?
    @State private var currentCoordinate: PlayerCoordinate?
    @State private var shareImageURL: URL?
    @State private var isCurrentTokenBookmarked = false
    
    init(config: MobilePlayerConfig, onDismiss: @escaping () -> Void, chrome: MobilePlayerChromeController) {
        self.initialConfig = config
        self.onDismiss = onDismiss
        self.chrome = chrome
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                FourDirectionalPlayerContainerView(
                    initialConfig: initialConfig,
                    onCoordinateUpdate: { newCoordinate in
                        DispatchQueue.main.async {
                            let token = MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: newCoordinate)
                            let progress = MobilePlaybackController.shared.markViewed(uuid: initialConfig.id, coordinate: newCoordinate)
                            self.currentCoordinate = newCoordinate
                            self.currentToken = token
                            self.currentProgress = progress
                            self.updateShareImageURL(for: newCoordinate)
                            self.updateBookmarkState(for: token)
                            updateExternalDisplayToken(token)
                        }
                    },
                    onPaginationAttempt: {},
                    onUnavailableNavigation: {
                        chrome.setControlsVisible(true)
                    }
                )
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            chrome.toggleControls()
                        }
                )
                .onLongPressGesture {
                    chrome.toggleControls()
                }

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
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
                    .animation(chrome.showControls ? playerChromeToggleAnimation : playerManualGlassHideAnimation, value: chrome.showControls)
                }
                .allowsHitTesting(chrome.showControls)

                VStack {
                    Spacer()
                    HStack {
                        if chrome.showControls, let shareImageURL {
                            PlayerShareButton(imageURL: shareImageURL)
                                .transition(.opacity)
                        }
                        Spacer()
                    }
                    .padding(.leading, 18)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
                    .animation(chrome.showControls ? playerChromeToggleAnimation : playerManualGlassHideAnimation, value: chrome.showControls)
                    .animation(playerChromeToggleAnimation, value: shareImageURL)
                }
                .allowsHitTesting(chrome.showControls && shareImageURL != nil)

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
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
                    .animation(chrome.showControls ? playerChromeToggleAnimation : playerManualGlassHideAnimation, value: chrome.showControls)
                    .animation(playerChromeToggleAnimation, value: isCurrentTokenBookmarked)
                }
                .allowsHitTesting(chrome.showControls && canBookmarkCurrentToken)
            }
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
            MobilePlaybackController.shared.stopAndDisconnect(uuid: initialConfig.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .solanaImageCacheFileAvailabilityDidChange)) { _ in
            updateShareImageURL(for: currentCoordinate)
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
            Button(viewOnWebTitle, action: viewOnWeb)
            Text(currentToken.displayName)
        } label: {
            Images.info
        }
        .accessibilityLabel(Strings.info)
    }

    private var viewOnWebTitle: String {
        currentToken.url?.isSolscanURL == true ? Strings.viewOnSolscan : Strings.viewOnBlockscout
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

        isCurrentTokenBookmarked = MobileBookmarksStore.toggleBookmark(
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

        isCurrentTokenBookmarked = MobileBookmarksStore.isBookmarked(
            collectionId: token.fullCollectionId,
            tokenId: token.id
        )
    }

    private func updateShareImageURL(for coordinate: PlayerCoordinate?) {
        guard let coordinate else {
            shareImageURL = nil
            return
        }

        shareImageURL = MobilePlaybackController.shared.downloadedStaticImageFileURL(
            uuid: initialConfig.id,
            coordinate: coordinate
        )
    }

}

private extension URL {
    var isSolscanURL: Bool {
        guard var host = host?.lowercased() else { return false }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host == "solscan.io" || host.hasSuffix(".solscan.io")
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
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: playerNavigationArrowSpacing) {
                if isVisible {
                    progressNavigationRow
                }
            }
        } else if isVisible {
            progressNavigationRow
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .font(.subheadline.weight(.semibold))
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
    let imageURL: URL

    @ViewBuilder
    var body: some View {
        let link = ShareLink(item: imageURL) {
            Images.share
                .font(.subheadline.weight(.semibold))
                .frame(width: playerProgressControlSize, height: playerProgressControlSize)
                .contentShape(Circle())
        }
        .accessibilityLabel(Strings.share)

        if #available(iOS 26.0, *) {
            link
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .glassEffectTransition(.materialize)
        } else {
            link
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct PlayerBookmarkButton: View {
    let isBookmarked: Bool
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let button = Button(action: action) {
            (isBookmarked ? Images.bookmarkFill : Images.bookmark)
                .font(.subheadline.weight(.semibold))
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
