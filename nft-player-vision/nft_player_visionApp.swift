// ∅ 2026 lil org

import SwiftUI
import UIKit

@main
struct nft_player_visionApp: App {
    @UIApplicationDelegateAdaptor(VisionAppDelegate.self) var appDelegate
    @State private var immersiveMode = VisionImmersiveModeModel()

    var body: some Scene {
        WindowGroup(id: WindowId.collections) {
            VisionCollectionsSceneRoot()
                .environment(immersiveMode)
        }
        .windowResizability(.contentMinSize)

        ImmersiveSpace(id: WindowId.blackImmersiveBackdrop) {
            VisionBlackImmersiveBackdropView()
                .environment(immersiveMode)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

private struct VisionCollectionsSceneRoot: View {
    @EnvironmentObject private var sceneDelegate: VisionSceneDelegate

    var body: some View {
        VisionCollectionsView(
            widgetLaunchPresentationState: sceneDelegate.widgetLaunchPresentationState
        )
    }
}

final class VisionAppDelegate: NSObject, UIApplicationDelegate {

    private var playerSyncBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var playerSyncBackgroundTaskId: UUID?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PlayerICloudSync.shared.start()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        flushPendingPlayerSync(application)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        flushPendingPlayerSync(application)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            config.delegateClass = VisionSceneDelegate.self
        }
        return config
    }

    private func flushPendingPlayerSync(_ application: UIApplication) {
        endPlayerSyncBackgroundTask(application)
        let backgroundTaskId = UUID()
        playerSyncBackgroundTaskId = backgroundTaskId
        playerSyncBackgroundTask = application.beginBackgroundTask(withName: "PlayerICloudSyncFlush") { [weak self, weak application] in
            guard let application else { return }
            self?.endPlayerSyncBackgroundTask(id: backgroundTaskId, application: application)
        }
        Task { @MainActor [weak self, weak application] in
            await PlayerICloudSync.shared.flushPendingPersistenceAndChanges { [weak self, weak application] in
                guard let application else { return }
                self?.endPlayerSyncBackgroundTask(id: backgroundTaskId, application: application)
            }
        }
    }

    private func endPlayerSyncBackgroundTask(_ application: UIApplication) {
        guard let playerSyncBackgroundTaskId else { return }
        endPlayerSyncBackgroundTask(id: playerSyncBackgroundTaskId, application: application)
    }

    private func endPlayerSyncBackgroundTask(id: UUID, application: UIApplication) {
        guard playerSyncBackgroundTaskId == id,
              playerSyncBackgroundTask != .invalid else {
            return
        }
        let task = playerSyncBackgroundTask
        playerSyncBackgroundTask = .invalid
        playerSyncBackgroundTaskId = nil
        application.endBackgroundTask(task)
    }

}

@MainActor
final class VisionSceneDelegate: UIResponder, UIWindowSceneDelegate, ObservableObject {

    let widgetLaunchPresentationState = WidgetLaunchPresentationState()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard session.role == .windowApplication else { return }
        widgetLaunchPresentationState.prepareForIncomingURLs(
            connectionOptions.urlContexts.map(\.url),
            isApplicationLaunch: true,
            isSupportedCollection: { collectionId in
                CollectionCatalog.allItems.contains { $0.id == collectionId }
            }
        )
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        widgetLaunchPresentationState.cancelAllWidgetPlayerHandoffs()
    }

}
