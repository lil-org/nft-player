// ∅ 2026 lil org

import Cocoa
import SwiftUI

class Navigator: NSObject, NSWindowDelegate {

    private override init() { super.init() }
    static let shared = Navigator()

    private var mainWindow: NSWindow?

    func showCollections() {
        MacNavigationModel.shared.resetToCollections()
        showMainWindow()
    }

    func showPlayer(
        collectionId: String,
        ensureFrontAfterOpening: Bool = false,
        transition: MacRouteTransition = .slide
    ) {
        guard CollectionCatalog.allItems.contains(where: { $0.id == collectionId }) else { return }

        if let progress = PlayerViewingProgressStore.progress(collectionId: collectionId) {
            showPlayer(
                collectionId: progress.collectionId,
                initialTokenId: progress.tokenId,
                continueViewingCollectionId: progress.collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                transition: transition
            )
            return
        }

        showPlayer(
            collectionId: collectionId,
            continueViewingCollectionId: collectionId,
            ensureFrontAfterOpening: ensureFrontAfterOpening,
            transition: transition
        )
    }

    /// Widget launches present instantly, as on iOS — the point of the widget is
    /// "click the art, get the art", not a staged grid animating itself away.
    func showWidgetPlayer(collectionId: String, tokenId: String?, ensureFrontAfterOpening: Bool = false) {
        if let tokenId {
            showPlayer(
                collectionId: collectionId,
                widgetTokenId: tokenId,
                ensureFrontAfterOpening: ensureFrontAfterOpening
            )
        } else {
            showPlayer(
                collectionId: collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                transition: .none
            )
        }
    }

    private func showPlayer(
        collectionId: String,
        widgetTokenId: String,
        ensureFrontAfterOpening: Bool
    ) {
        guard let widgetTokenInsertion = CollectionCatalog.widgetTokenInsertion(
            collectionId: collectionId,
            widgetTokenId: widgetTokenId,
            progress: PlayerViewingProgressStore.progress(collectionId: collectionId)
        ) else {
            showPlayer(
                collectionId: collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                transition: .none
            )
            return
        }

        if let anchorProgress = widgetTokenInsertion.automaticAnchorProgress() {
            PlayerViewingProgressStore.save(anchorProgress)
        }
        PlayerViewingProgressStore.setContinueViewingCollectionId(collectionId)
        showPlayer(
            model: PlayerModel(widgetTokenInsertion: widgetTokenInsertion),
            ensureFrontAfterOpening: ensureFrontAfterOpening,
            transition: .none
        )
    }

    func showPlayer(
        collectionId: String,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String,
        ensureFrontAfterOpening: Bool = false,
        transition: MacRouteTransition = .slide
    ) {
        PlayerViewingProgressStore.setContinueViewingCollectionId(continueViewingCollectionId)
        let preparedToken = PlayerTokenPrewarmer.preparedToken(
            initialCollectionId: collectionId,
            initialTokenId: initialTokenId
        )
        let model = preparedToken.map {
            PlayerModel(token: $0)
        } ?? PlayerModel(
            collectionId: collectionId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId
        )
        showPlayer(model: model, ensureFrontAfterOpening: ensureFrontAfterOpening, transition: transition)
    }

    func showPlayer(
        model: PlayerModel,
        ensureFrontAfterOpening: Bool = false,
        transition: MacRouteTransition = .slide
    ) {
        MacNavigationModel.shared.present(playerModel: model, transition: transition)
        let presentedSessionId = MacNavigationModel.shared.session?.id
        let presentedWindow = showMainWindow(activating: true)

        guard ensureFrontAfterOpening else { return }

        let bringPresentedWindowToFront = { [weak self, weak presentedWindow] in
            guard let self,
                  let presentedWindow,
                  presentedWindow === self.mainWindow,
                  presentedWindow.isVisible,
                  MacNavigationModel.shared.session?.id == presentedSessionId else {
                return
            }
            self.orderMainWindowToFront(regardless: true)
        }
        DispatchQueue.main.async(execute: bringPresentedWindowToFront)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(150),
            execute: bringPresentedWindowToFront
        )
    }

    @discardableResult
    func showMainWindow(activating: Bool = true) -> NSWindow {
        if let mainWindow {
            if activating {
                orderMainWindowToFront()
            }
            return mainWindow
        }

        let window = RightClickActivatingWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 777, height: 593)),
            styleMask: [.closable, .fullSizeContentView, .titled, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = false
        window.hasShadow = true
        window.isRestorable = true
        window.setFrameAutosaveName(Consts.mainWindowFrameAutosaveName)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: MacRootView(model: MacNavigationModel.shared)
        )
        window.contentMinSize = CGSize(width: 320, height: 240)
        window.toolbarStyle = .unified
        mainWindow = window

        if activating {
            orderMainWindowToFront()
        }

        if window.frame.origin == .zero || !window.isOnActiveSpace || !window.isVisible {
            window.center()
        }
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === mainWindow else {
            return
        }
        MacNavigationModel.shared.handleMainWindowWillClose()
    }

    private func orderMainWindowToFront(regardless: Bool = false) {
        guard let mainWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.makeMain()
        if regardless {
            mainWindow.orderFrontRegardless()
        }
    }

}
