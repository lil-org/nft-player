// ∅ 2026 lil org

import Cocoa
import SwiftUI

class Navigator: NSObject {
    
    private override init() { super.init() }
    static let shared = Navigator()
    
    func showNewFolderInput() {
        showControlCenter(addWallet: true)
    }
    
    func showPlayer(model: PlayerModel) {
        Window.closeOtherPlayers()
        let window = LocalHtmlWindow(
            playerModel: model,
            contentRect: CGRect(origin: .zero, size: CGSize(width: 420, height: 420)),
            styleMask: [.closable, .fullSizeContentView, .titled, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.isOpaque = false
        window.hasShadow = true
        window.isRestorable = true
        window.setFrameAutosaveName(Consts.playerFrameAutosaveName)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        
        if window.frame.origin == .zero || !window.isOnActiveSpace || !window.isVisible {
            window.center()
        }
    }
    
    func showControlCenter(addWallet: Bool) {
        AllDownloadsManager.shared.checkFolders()
        Window.closeAllControlCenters()
        let contentView = WalletsListView(showAddWalletPopup: addWallet)
        let window = RightClickActivatingWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 777, height: 593)),
            styleMask: [.closable, .fullSizeContentView, .titled, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = false
        window.hasShadow = true
        window.isRestorable = true
        window.setFrameAutosaveName(Consts.controlCenterFrameAutosaveName)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView.frame(minWidth: 251, minHeight: 130))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        
        if window.frame.origin == .zero || !window.isOnActiveSpace || !window.isVisible {
            window.center()
        }
    }
    
}
