// ∅ 2026 lil org

import Cocoa
import SwiftUI

@MainActor
final class Navigator: NSObject, NSWindowDelegate {

    private override init() { super.init() }
    static let shared = Navigator()

    private var mainWindow: NSWindow?
    private let playerPresentationGate = PlayerPresentationRequestGate()

    func showCollections() {
        MacNavigationModel.shared.resetToCollections()
        showMainWindow()
    }

    func requestPlayer(
        collectionId: String,
        ensureFrontAfterOpening: Bool = false,
        transition: MacRouteTransition = .slide
    ) {
        let request = playerPresentationGate.begin()
        Task {
            await showPlayerUsingProgress(
                collectionId: collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                transition: transition,
                request: request
            )
        }
    }

    func requestPlayer(
        collectionId: String,
        initialTokenId: String?,
        continueViewingCollectionId: String,
        ensureFrontAfterOpening: Bool = false,
        transition: MacRouteTransition = .slide
    ) {
        let request = playerPresentationGate.begin()
        Task {
            guard let snapshot = await playerPresentationSnapshot(for: request),
                  playerPresentationGate.isPending(request) else {
                return
            }
            let progress = snapshot.progress(collectionId: collectionId)
            await showPlayer(
                collectionId: collectionId,
                initialTokenId: progress?.tokenId ?? initialTokenId,
                continueViewingCollectionId: continueViewingCollectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                transition: transition,
                request: request
            )
        }
    }

    func requestShuffledPlayer() {
        let request = playerPresentationGate.begin()
        Task {
            guard let snapshot = await playerPresentationSnapshot(for: request),
                  playerPresentationGate.isPending(request) else {
                return
            }

            let items = CollectionCatalog.allItems
            let unfinishedItems = items.filter {
                !snapshot.viewedToEndCollectionIds.contains($0.id)
            }
            guard let item = (unfinishedItems.isEmpty ? items : unfinishedItems).randomElement() else {
                return
            }

            let progress = snapshot.progress(collectionId: item.id)
            await showPlayer(
                collectionId: item.id,
                initialTokenId: progress?.isComplete == false ? progress?.tokenId : nil,
                continueViewingCollectionId: item.id,
                ensureFrontAfterOpening: false,
                transition: .slide,
                request: request
            )
        }
    }

    func cancelPendingPlayerPresentation() {
        playerPresentationGate.cancel()
    }

    private func playerPresentationSnapshot(
        for request: PlayerPresentationRequestGate.Request
    ) async -> PlayerViewingProgressSnapshot? {
        await PlayerPersistenceUpdates.flush()
        guard playerPresentationGate.isPending(request) else { return nil }
        let snapshot = await PlayerViewingProgressStore.shared.progressSnapshot()
        guard playerPresentationGate.isPending(request) else { return nil }
        return snapshot
    }

    private func showPlayerUsingProgress(
        collectionId: String,
        ensureFrontAfterOpening: Bool,
        transition: MacRouteTransition,
        request: PlayerPresentationRequestGate.Request,
        preparedSnapshot: PlayerViewingProgressSnapshot? = nil
    ) async {
        guard playerPresentationGate.isPending(request) else { return }
        guard CollectionCatalog.allItems.contains(where: { $0.id == collectionId }) else { return }

        let snapshot: PlayerViewingProgressSnapshot
        if let preparedSnapshot {
            snapshot = preparedSnapshot
        } else {
            guard let loadedSnapshot = await playerPresentationSnapshot(for: request),
                  playerPresentationGate.isPending(request) else {
                return
            }
            snapshot = loadedSnapshot
        }

        if let progress = snapshot.progress(collectionId: collectionId) {
            await showPlayer(
                collectionId: progress.collectionId,
                initialTokenId: progress.tokenId,
                continueViewingCollectionId: progress.collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                transition: transition,
                request: request
            )
            return
        }

        guard playerPresentationGate.isPending(request) else { return }
        await showPlayer(
            collectionId: collectionId,
            initialTokenId: nil,
            continueViewingCollectionId: collectionId,
            ensureFrontAfterOpening: ensureFrontAfterOpening,
            transition: transition,
            request: request
        )
    }

    func requestWidgetPlayer(
        collectionId: String,
        tokenId: String?,
        ensureFrontAfterOpening: Bool = false,
        completion: @escaping @MainActor () -> Void
    ) {
        let request = playerPresentationGate.begin()
        Task {
            defer { completion() }
            await Task.yield()
            guard playerPresentationGate.isPending(request) else { return }
            if let tokenId {
                await showPlayer(
                    collectionId: collectionId,
                    widgetTokenId: tokenId,
                    ensureFrontAfterOpening: ensureFrontAfterOpening,
                    request: request
                )
            } else {
                await showPlayerUsingProgress(
                    collectionId: collectionId,
                    ensureFrontAfterOpening: ensureFrontAfterOpening,
                    transition: .none,
                    request: request
                )
            }
        }
    }

    private func showPlayer(
        collectionId: String,
        widgetTokenId: String,
        ensureFrontAfterOpening: Bool,
        request: PlayerPresentationRequestGate.Request
    ) async {
        guard let snapshot = await playerPresentationSnapshot(for: request),
              playerPresentationGate.isPending(request) else {
            return
        }
        let progress = snapshot.progress(collectionId: collectionId)
        guard let widgetTokenInsertion = CollectionCatalog.widgetTokenInsertion(
            collectionId: collectionId,
            widgetTokenId: widgetTokenId,
            progress: progress
        ) else {
            await showPlayerUsingProgress(
                collectionId: collectionId,
                ensureFrontAfterOpening: ensureFrontAfterOpening,
                transition: .none,
                request: request,
                preparedSnapshot: snapshot
            )
            return
        }

        guard playerPresentationGate.isPending(request) else { return }
        await commitPlayerPresentation(
            model: PlayerModel(widgetTokenInsertion: widgetTokenInsertion),
            continueViewingCollectionId: collectionId,
            ensureFrontAfterOpening: ensureFrontAfterOpening,
            transition: .none,
            request: request
        )
    }

    private func showPlayer(
        collectionId: String,
        initialTokenId: String?,
        continueViewingCollectionId: String,
        ensureFrontAfterOpening: Bool,
        transition: MacRouteTransition,
        request: PlayerPresentationRequestGate.Request
    ) async {
        guard playerPresentationGate.isPending(request) else { return }
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
        await commitPlayerPresentation(
            model: model,
            continueViewingCollectionId: continueViewingCollectionId,
            ensureFrontAfterOpening: ensureFrontAfterOpening,
            transition: transition,
            request: request
        )
    }

    private func commitPlayerPresentation(
        model: PlayerModel,
        continueViewingCollectionId: String,
        ensureFrontAfterOpening: Bool,
        transition: MacRouteTransition,
        request: PlayerPresentationRequestGate.Request
    ) async {
        guard playerPresentationGate.isPending(request) else { return }
        let openingProgress = model.currentProgress
        let continueViewingUpdate: PlayerContinueViewingUpdate?
        if openingProgress == nil {
            continueViewingUpdate = await PlayerViewingProgressStore.shared
                .prepareContinueViewingUpdate(collectionId: continueViewingCollectionId)
            guard continueViewingUpdate != nil,
                  playerPresentationGate.isPending(request) else {
                return
            }
        } else {
            continueViewingUpdate = nil
        }
        let openingTracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: continueViewingCollectionId
        )
        playerPresentationGate.commit(
            request,
            present: {
                self.showPlayer(
                    model: model,
                    ensureFrontAfterOpening: ensureFrontAfterOpening,
                    transition: transition
                )
            },
            persist: {
                if let openingProgress {
                    await openingTracker.markViewed(openingProgress)
                } else if let continueViewingUpdate {
                    await PlayerViewingProgressStore.shared.applyContinueViewingUpdate(
                        continueViewingUpdate
                    )
                }
            }
        )
    }

    private func showPlayer(
        model: PlayerModel,
        ensureFrontAfterOpening: Bool = false,
        transition: MacRouteTransition = .slide
    ) {
        MacNavigationModel.shared.present(playerModel: model, transition: transition)
        let presentedSessionId = MacNavigationModel.shared.session?.id
        let presentedWindow = showMainWindow(activating: true)

        guard ensureFrontAfterOpening else { return }

        let bringPresentedWindowToFront = { @MainActor [weak self, weak presentedWindow] in
            guard let self,
                  let presentedWindow,
                  presentedWindow === self.mainWindow,
                  presentedWindow.isVisible,
                  MacNavigationModel.shared.session?.id == presentedSessionId else {
                return
            }
            self.orderMainWindowToFront(regardless: true)
        }
        Task { @MainActor in
            await Task.yield()
            bringPresentedWindowToFront()
            try? await Task.sleep(for: .milliseconds(150))
            bringPresentedWindowToFront()
        }
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
