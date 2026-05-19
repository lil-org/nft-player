// ∅ 2026 lil org

import SwiftUI
import AppKit

struct LocalHtmlView: View {
    
    private var windowNumber = 0
    private weak var playerMenuDelegate: PlayerMenuDelegate?
    private let onViewAgain: () -> Void
    private let onFinish: () -> Void
    
    @ObservedObject var playerModel: PlayerModel
    
    init(
        playerModel: PlayerModel,
        windowNumber: Int,
        playerMenuDelegate: PlayerMenuDelegate,
        onViewAgain: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.playerModel = playerModel
        self.windowNumber = windowNumber
        self.playerMenuDelegate = playerMenuDelegate
        self.onViewAgain = onViewAgain
        self.onFinish = onFinish
    }
    
    var body: some View {
        let isCollectionComplete = playerModel.currentProgress?.isComplete == true

        ZStack(alignment: .bottom) {
            MacPlayerMediaView(token: playerModel.currentToken, playerMenuDelegate: playerMenuDelegate)
                .onAppear {
                    hideCursorIfFullscreen()
                }
                .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .background(.black)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
                    if (notification.object as? NSWindow)?.windowNumber == windowNumber {
                        NSCursor.setHiddenUntilMouseMoves(true)
                    }
                }

            if isCollectionComplete {
                MacPlayerCompletionControls(
                    onViewAgain: onViewAgain,
                    onFinish: onFinish
                )
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isCollectionComplete)
    }
    
    private func hideCursorIfFullscreen() {
        if let window = NSApplication.shared.windows.first(where: { $0.windowNumber == windowNumber }) {
            if window.styleMask.contains(.fullScreen) {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }
    
}

private struct MacPlayerCompletionControls: View {
    let onViewAgain: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(image: Images.viewAgain, title: Strings.viewAgain, action: onViewAgain)
            actionButton(image: Images.finish, title: Strings.finish, action: onFinish)
        }
    }

    private func actionButton(image: Image, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                image
                    .font(.caption.weight(.semibold))
                    .imageScale(.small)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel(title)
    }
}
