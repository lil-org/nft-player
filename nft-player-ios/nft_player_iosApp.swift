import SwiftUI
import UIKit

private let feedbackShortcutItemType = "org.lil.nft-folder.feedback"

@main
struct nft_player_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MobileCollectionsSceneRoot()
        }
    }
}

private struct MobileCollectionsSceneRoot: View {
    @EnvironmentObject private var sceneDelegate: SceneDelegate

    var body: some View {
        MobileCollectionsView(
            widgetLaunchPresentationState: sceneDelegate.widgetLaunchPresentationState
        )
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

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
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
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
        PlayerICloudSync.shared.flushPendingChanges { [weak self, weak application] in
            guard let application else { return }
            self?.endPlayerSyncBackgroundTask(id: backgroundTaskId, application: application)
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
final class SceneDelegate: UIResponder, UIWindowSceneDelegate, ObservableObject {

    private static var hasActivatedApplicationScene = false

    let widgetLaunchPresentationState = WidgetLaunchPresentationState()
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if session.role == .windowApplication {
            widgetLaunchPresentationState.prepareForIncomingURLs(
                connectionOptions.urlContexts.map(\.url),
                isApplicationLaunch: !Self.hasActivatedApplicationScene,
                isSupportedCollection: { collectionId in
                    MobileCollectionCatalog.allItems.contains { $0.id == collectionId }
                }
            )
        }

        if let shortcutItem = connectionOptions.shortcutItem, shortcutItem.type == feedbackShortcutItemType {
            UIApplication.shared.open(.quickFeedbackMail)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard scene.session.role == .windowApplication else { return }
        Self.hasActivatedApplicationScene = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        widgetLaunchPresentationState.cancelAllWidgetPlayerHandoffs()
    }
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == feedbackShortcutItemType {
            UIApplication.shared.open(.quickFeedbackMail)
        }
        completionHandler(true)
    }
    
}

class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let win = UIWindow(windowScene: ws)
        win.rootViewController = ExternalDisplayViewController()
        win.isHidden = false
        window = win
    }
    
}
