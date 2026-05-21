import SwiftUI
import UIKit

private let feedbackShortcutItemType = "org.lil.nft-folder.feedback"

@main
struct nft_folder_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MobileCollectionsView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PlayerICloudSync.shared.start()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        PlayerICloudSync.shared.flushPendingChanges(synchronize: true)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        PlayerICloudSync.shared.flushPendingChanges(synchronize: true)
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
    
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcutItem = connectionOptions.shortcutItem, shortcutItem.type == feedbackShortcutItemType {
            UIApplication.shared.open(.quickFeedbackMail)
        }
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
