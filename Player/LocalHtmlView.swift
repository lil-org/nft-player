// ∅ 2026 lil org

import SwiftUI
import AppKit

struct LocalHtmlView: View {
    
    private var windowNumber = 0
    private weak var playerMenuDelegate: PlayerMenuDelegate?
    
    @ObservedObject var playerModel: PlayerModel
    
    init(playerModel: PlayerModel, windowNumber: Int, playerMenuDelegate: PlayerMenuDelegate) {
        self.playerModel = playerModel
        self.windowNumber = windowNumber
        self.playerMenuDelegate = playerMenuDelegate
    }
    
    var body: some View {
        DesktopWebView(htmlContent: playerModel.currentToken.html, playerMenuDelegate: playerMenuDelegate)
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
    }
    
    private func hideCursorIfFullscreen() {
        if let window = NSApplication.shared.windows.first(where: { $0.windowNumber == windowNumber }) {
            if window.styleMask.contains(.fullScreen) {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }
    
}
