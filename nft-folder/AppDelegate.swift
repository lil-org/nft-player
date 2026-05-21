// ∅ 2026 lil org

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let currentInstanceId = UUID().uuidString
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        PlayerICloudSync.shared.start()
        Navigator.shared.showControlCenter()
        
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.post(name: .mustTerminate, object: currentInstanceId)
        notificationCenter.addObserver(self, selector: #selector(terminateInstance(_:)), name: .mustTerminate, object: nil, suspensionBehavior: .deliverImmediately)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        PlayerICloudSync.shared.flushPendingChanges(synchronize: true)
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
        Navigator.shared.showControlCenter()
        return true
    }
    
    @IBAction func didClickNewWindowItem(_ sender: Any) {
        Navigator.shared.showControlCenter()
    }
    
}
