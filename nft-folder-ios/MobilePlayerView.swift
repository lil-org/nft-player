// ∅ 2026 lil org

import SwiftUI
import UIKit

struct MobilePlayerConfig: Hashable, Codable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
    var initialTokenId: String?
}

private let doNotShowInstructionsTmp = true

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
    
    init(config: MobilePlayerConfig, onDismiss: @escaping () -> Void, chrome: MobilePlayerChromeController) {
        self.initialConfig = config
        self.onDismiss = onDismiss
        self.chrome = chrome
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                FourDirectionalPlayerContainerView(initialConfig: initialConfig, onCoordinateUpdate: { newCoordinate in
                    DispatchQueue.main.async {
                        let token = MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: newCoordinate)
                        self.currentToken = token
                        self.currentProgress = MobilePlaybackController.shared.markViewed(uuid: initialConfig.id, coordinate: newCoordinate)
                        updateExternalDisplayToken(token)
                    }
                })
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
                            onBack: goBack,
                            onForward: goForward,
                            onWatchAgain: watchAgain,
                            onNextCollection: nextCollection
                        )
                        .padding(.horizontal, 18)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .allowsHitTesting(true)
                }
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
            updateExternalDisplayToken(GeneratedToken.empty)
            MobilePlaybackController.shared.stopAndDisconnect(uuid: initialConfig.id)
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

    private func watchAgain() {
        MobilePlaybackController.shared.restartCollection(uuid: initialConfig.id)
        Haptic.selectionChanged()
    }

    private func nextCollection() {
        MobilePlaybackController.shared.changeCollection(uuid: initialConfig.id)
        Haptic.selectionChanged()
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
            .foregroundStyle(.white)
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
    let onBack: () -> Void
    let onForward: () -> Void
    let onWatchAgain: () -> Void
    let onNextCollection: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Button(action: onBack) {
                    Images.back
                        .font(.title3.weight(.semibold))
                        .frame(width: 56, height: 46)
                }
                .accessibilityLabel(Strings.back)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)

                Text(progress?.tokenLabel ?? "")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 46)

                Button(action: onForward) {
                    Images.forward
                        .font(.title3.weight(.semibold))
                        .frame(width: 56, height: 46)
                }
                .accessibilityLabel(Strings.forward)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background {
                ProgressCapsuleBackground(progress: progress?.fraction ?? 0)
            }
            .clipShape(Capsule())

            if progress?.isComplete == true {
                HStack(spacing: 8) {
                    Button(Strings.watchAgain, action: onWatchAgain)
                    Button(Strings.anotherCollection, action: onNextCollection)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
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
        } else {
            Capsule()
                .fill(.white.opacity(0.08))
                .glassEffect(.regular.tint(.black.opacity(0.42)), in: Capsule())
        }
    }
}
