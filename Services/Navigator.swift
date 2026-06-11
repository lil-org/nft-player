// ∅ 2026 lil org

import Cocoa
import SwiftUI

class Navigator: NSObject {
    
    private override init() { super.init() }
    static let shared = Navigator()

    func showPlayer(
        collectionId: String,
        ensureFrontAfterOpening: Bool = false,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        guard CollectionCatalog.allItems.contains(where: { $0.id == collectionId }) else { return }

        if let progress = PlayerViewingProgressStore.progress(collectionId: collectionId) {
            showPlayer(
                collectionId: progress.collectionId,
                initialTokenId: progress.tokenId,
                continueViewingCollectionId: progress.collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                trackingMode: trackingMode
            )
            return
        }

        showPlayer(
            collectionId: collectionId,
            continueViewingCollectionId: collectionId,
            ensureFrontAfterOpening: ensureFrontAfterOpening,
            trackingMode: trackingMode
        )
    }

    func showWidgetPlayer(collectionId: String, tokenId: String?, ensureFrontAfterOpening: Bool = false) {
        let trackingMode = widgetOpenTrackingMode()
        if let tokenId {
            showPlayer(
                collectionId: collectionId,
                widgetTokenId: tokenId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                trackingMode: trackingMode
            )
        } else {
            showPlayer(
                collectionId: collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                trackingMode: trackingMode
            )
        }
    }

    private func showPlayer(
        collectionId: String,
        widgetTokenId: String,
        ensureFrontAfterOpening: Bool,
        trackingMode: PlayerViewingSessionTrackingMode
    ) {
        guard let widgetTokenInsertion = CollectionCatalog.widgetTokenInsertion(
            collectionId: collectionId,
            widgetTokenId: widgetTokenId,
            progress: PlayerViewingProgressStore.progress(collectionId: collectionId)
        ) else {
            showPlayer(
                collectionId: collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                trackingMode: trackingMode
            )
            return
        }

        PlayerViewingProgressStore.save(widgetTokenInsertion.updatedAnchorProgress())
        if trackingMode.updatesContinueViewing {
            PlayerViewingProgressStore.setContinueViewingCollectionId(collectionId)
        }
        showPlayer(
            model: PlayerModel(widgetTokenInsertion: widgetTokenInsertion, trackingMode: trackingMode),
            ensureFrontAfterOpening: ensureFrontAfterOpening
        )
    }

    func showPlayer(
        collectionId: String,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String,
        ensureFrontAfterOpening: Bool = false,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        if trackingMode.updatesContinueViewing {
            PlayerViewingProgressStore.setContinueViewingCollectionId(continueViewingCollectionId)
        }
        let preparedToken = PlayerTokenPrewarmer.preparedToken(
            initialCollectionId: collectionId,
            initialTokenId: initialTokenId
        )
        let model = preparedToken.map {
            PlayerModel(token: $0, trackingMode: trackingMode)
        } ?? PlayerModel(
            collectionId: collectionId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId,
            trackingMode: trackingMode
        )
        showPlayer(model: model, ensureFrontAfterOpening: ensureFrontAfterOpening)
    }

    func showPlayer(model: PlayerModel, ensureFrontAfterOpening: Bool = false) {
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
        
        orderPlayerWindowToFront(window, regardless: ensureFrontAfterOpening)
        if window.frame.origin == .zero || !window.isOnActiveSpace || !window.isVisible {
            window.center()
            orderPlayerWindowToFront(window, regardless: ensureFrontAfterOpening)
        }

        guard ensureFrontAfterOpening else { return }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window.isVisible else { return }
            self.orderPlayerWindowToFront(window, regardless: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self, weak window] in
            guard let self, let window, window.isVisible else { return }
            self.orderPlayerWindowToFront(window, regardless: true)
        }
    }
    
    func showControlCenter() {
        Window.closeAllControlCenters()
        let contentView = WalletsListView()
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

    private func orderPlayerWindowToFront(_ window: NSWindow, regardless: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        if regardless {
            window.orderFrontRegardless()
        }
    }

    private func widgetOpenTrackingMode() -> PlayerViewingSessionTrackingMode {
        PlayerViewingProgressStore.progressSnapshot().continueViewingProgress == nil
            ? .updateContinueViewing
            : .progressOnly
    }
    
}
