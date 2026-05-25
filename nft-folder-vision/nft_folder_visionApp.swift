// ∅ 2026 lil org

import SwiftUI
import UIKit

private let visionCollectionsDefaultWindowWidth: CGFloat = 960
private let visionCollectionsDefaultWindowHeight: CGFloat = 720

@main
struct nft_folder_visionApp: App {
    @UIApplicationDelegateAdaptor(VisionAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: WindowId.collections) {
            VisionCollectionsView()
        }
        .defaultSize(
            width: visionCollectionsDefaultWindowWidth,
            height: visionCollectionsDefaultWindowHeight
        )
        .windowResizability(.contentMinSize)
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
