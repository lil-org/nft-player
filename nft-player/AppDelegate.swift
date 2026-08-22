// ∅ 2026 lil org

import Cocoa

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let currentInstanceId = UUID().uuidString
    private var hasFinishedLaunching = false
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        PlayerICloudSync.shared.start()
        Navigator.shared.showMainWindow()
        
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.post(name: .mustTerminate, object: currentInstanceId)
        notificationCenter.addObserver(self, selector: #selector(terminateInstance(_:)), name: .mustTerminate, object: nil, suspensionBehavior: .deliverImmediately)
        hasFinishedLaunching = true
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc private func terminateInstance(_ notification: Notification) {
        guard let senderId = notification.object as? String else { return }
        if senderId != currentInstanceId {
            NSApplication.shared.terminate(nil)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Navigator.shared.showMainWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        WidgetLaunchPresentationState.shared.prepareForIncomingURLs(
            urls,
            isApplicationLaunch: !hasFinishedLaunching,
            isSupportedCollection: { collectionId in
                CollectionCatalog.allItems.contains { $0.id == collectionId }
            }
        )

        let widgetURLs = urls.filter { WidgetDeepLink(url: $0) != nil }
        guard !widgetURLs.isEmpty else { return }

        widgetURLs.forEach(openWidgetURL)
    }
    
    @IBAction func didClickNewWindowItem(_ sender: Any) {
        Navigator.shared.showCollections()
    }

    private func openWidgetURL(_ url: URL) {
        guard let deepLink = WidgetDeepLink(url: url),
              let target = deepLink.collectionTarget(ifSupported: { collectionId in
                CollectionCatalog.allItems.contains { $0.id == collectionId }
              }) else {
            WidgetLaunchPresentationState.shared.finishWidgetPlayerHandoff(for: url)
            return
        }
        let handoffRequest = WidgetLaunchPresentationState.shared
            .beginWidgetPlayerHandoff(for: url)

        Navigator.shared.requestWidgetPlayer(
            collectionId: target.collectionId,
            tokenId: target.tokenId,
            ensureFrontAfterOpening: true
        ) {
            WidgetLaunchPresentationState.shared.finishWidgetPlayerHandoff(handoffRequest)
        }
    }
    
}
