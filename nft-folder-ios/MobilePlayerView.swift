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
private let startupProgressVisibleDuration: DispatchTimeInterval = .milliseconds(1300)
private let startupProgressHideAnimation = Animation.smooth(duration: 0.5)
private let playerProgressControlSize: CGFloat = 34

final class MobilePlayerChromeController: ObservableObject {
    @Published private(set) var showControls = false

    func toggleControls() {
        setControlsVisible(!showControls)
    }

    func setControlsVisible(_ isVisible: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.setControlsVisible(isVisible) }
            return
        }

        guard showControls != isVisible else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            showControls = isVisible
        }
    }
}

struct MobilePlayerView: View {
    
    private let initialConfig: MobilePlayerConfig
    private let onDismiss: () -> Void
    @ObservedObject private var chrome: MobilePlayerChromeController
    
    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentProgress: MobileViewingProgress?
    @State private var isStartupProgressVisible = true
    @State private var didScheduleStartupProgressAutoHide = false
    @State private var startupProgressAutoHideWorkItem: DispatchWorkItem?
    @Namespace private var startupProgressGlassNamespace
    
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
                            self.currentToken = token
                            self.currentProgress = progress
                            self.scheduleStartupProgressAutoHideIfNeeded(progress: progress)
                            updateExternalDisplayToken(token)
                        }
                    },
                    onPaginationAttempt: {
                        DispatchQueue.main.async {
                            self.hideStartupProgressForPaginationAttempt()
                        }
                    },
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

                if chrome.showControls {
                    VStack {
                        Spacer()
                        PlayerBottomControls(
                            progress: currentProgress,
                            canGoBack: canGoBack,
                            canGoForward: canGoForward,
                            hidesProgressLabel: shouldShowStartupProgress,
                            onBack: goBack,
                            onForward: goForward,
                            onViewAgain: viewAgain,
                            onFinish: onDismiss
                        )
                        .padding(.horizontal, 18)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .allowsHitTesting(true)
                }

                startupProgressOverlay(safeAreaBottom: geometry.safeAreaInsets.bottom)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chrome.showControls ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .statusBar(hidden: isAllowedToHideStatusBar && !chrome.showControls)
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
                    PlayerCollectionTitlePill(title: currentToken.collectionName)
                }
            }
        }
        .onDisappear {
            startupProgressAutoHideWorkItem?.cancel()
            updateExternalDisplayToken(GeneratedToken.empty)
            MobilePlaybackController.shared.stopAndDisconnect(uuid: initialConfig.id)
        }
        .onChange(of: chrome.showControls) { _, showControls in
            if showControls {
                cancelStartupProgressAutoHide()
            } else {
                invalidateStartupProgressAutoHide()
            }
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

    private var shouldShowStartupProgress: Bool {
        isStartupProgressVisible && currentProgress?.pageLabel.isEmpty == false
    }

    private func startupProgressOverlay(safeAreaBottom: CGFloat) -> some View {
        VStack {
            Spacer()
            startupProgressControl
                .padding(.horizontal, 18)
                .padding(.bottom, max(safeAreaBottom, 16))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var startupProgressControl: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                if shouldShowStartupProgress {
                    startupProgressNavigationRow
                }
            }
        } else if shouldShowStartupProgress {
            startupProgressNavigationRow
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private var startupProgressNavigationRow: some View {
        HStack(spacing: 8) {
            PlayerProgressArrowButton(
                image: Images.back,
                accessibilityLabel: Strings.back,
                isEnabled: false,
                action: {}
            )
            .hidden()

            StartupProgressTextPill(
                text: currentProgress?.pageLabel ?? "",
                namespace: startupProgressGlassNamespace
            )

            PlayerProgressArrowButton(
                image: Images.forward,
                accessibilityLabel: Strings.forward,
                isEnabled: false,
                action: {}
            )
            .hidden()
        }
    }
    
    private var infoMenu: some View {
        Menu {
            if !doNotShowInstructionsTmp, let instructions = currentToken.instructions {
                Text(instructions)
            }
            Button(Strings.viewOnBlockscout, action: viewOnWeb)
            Text(currentToken.displayName)
        } label: {
            Images.info
        }
        .accessibilityLabel(Strings.info)
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

    private func scheduleStartupProgressAutoHideIfNeeded(progress: MobileViewingProgress?) {
        guard progress != nil, isStartupProgressVisible, !didScheduleStartupProgressAutoHide else { return }

        didScheduleStartupProgressAutoHide = true
        let workItem = DispatchWorkItem {
            guard !chrome.showControls else { return }

            withAnimation(startupProgressHideAnimation) {
                isStartupProgressVisible = false
            }
        }
        startupProgressAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + startupProgressVisibleDuration, execute: workItem)
    }

    private func hideStartupProgressForPaginationAttempt() {
        guard shouldShowStartupProgress, !chrome.showControls else { return }

        cancelStartupProgressAutoHide()
        withAnimation(startupProgressHideAnimation) {
            isStartupProgressVisible = false
        }
    }

    private func invalidateStartupProgressAutoHide() {
        cancelStartupProgressAutoHide()
        isStartupProgressVisible = false
    }

    private func cancelStartupProgressAutoHide() {
        startupProgressAutoHideWorkItem?.cancel()
        startupProgressAutoHideWorkItem = nil
    }

}

private struct PlayerCollectionTitlePill: View {
    let title: String

    var body: some View {
        titleLabel
    }

    @ViewBuilder
    private var titleLabel: some View {
        let label = Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: 220)

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
    let progress: MobileViewingProgress?
    let canGoBack: Bool
    let canGoForward: Bool
    let hidesProgressLabel: Bool
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

    private var completionActions: some View {
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
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var progressNavigationControls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                progressNavigationRow
            }
        } else {
            progressNavigationRow
        }
    }

    private var progressNavigationRow: some View {
        HStack(spacing: 8) {
            PlayerProgressArrowButton(
                image: Images.back,
                accessibilityLabel: Strings.back,
                isEnabled: canGoBack,
                action: onBack
            )

            PlayerProgressTextPill(text: progress?.pageLabel ?? "")
                .hidden(hidesProgressLabel)

            PlayerProgressArrowButton(
                image: Images.forward,
                accessibilityLabel: Strings.forward,
                isEnabled: canGoForward,
                action: onForward
            )
        }
    }
}

private extension View {
    @ViewBuilder
    func hidden(_ isHidden: Bool) -> some View {
        if isHidden {
            hidden()
        } else {
            self
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
        } else {
            button
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct PlayerProgressTextPill: View {
    let text: String

    var body: some View {
        label
    }

    @ViewBuilder
    private var label: some View {
        let label = PlayerProgressTextLabel(text: text)

        if #available(iOS 26.0, *) {
            label
                .glassEffect(.regular, in: Capsule())
        } else {
            label
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct StartupProgressTextPill: View {
    let text: String
    let namespace: Namespace.ID

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            PlayerProgressTextLabel(text: text)
                .glassEffect(.regular, in: Capsule())
                .glassEffectID("startup-progress", in: namespace)
                .glassEffectTransition(.materialize)
        } else {
            PlayerProgressTextPill(text: text)
        }
    }
}

private struct PlayerProgressTextLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 58)
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
