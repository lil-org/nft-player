// ∅ 2026 lil org

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var didFinishLaunching = false
    private let currentInstanceId = UUID().uuidString
    
    private let allDownloadsManager = AllDownloadsManager.shared
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        cleanupDefaultsIfNeeded()
        createDirectoryIfNeeded()
        didFinishLaunching = true
        
        NSApplication.shared.servicesProvider = RightClickServiceProvider()
        NSUpdateDynamicServices()
        
        Navigator.shared.showControlCenter(addWallet: false)
        
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.post(name: .mustTerminate, object: currentInstanceId)
        notificationCenter.addObserver(self, selector: #selector(terminateInstance(_:)), name: .mustTerminate, object: nil, suspensionBehavior: .deliverImmediately)
        allDownloadsManager.start()
        AvatarService.setup()
    }
    
    private func cleanupDefaultsIfNeeded() {
        let currentVersion = Defaults.cleanupVersion
        if currentVersion == 0 {
            Defaults.performCleanup(version: currentVersion)
            SharedDefaults.performCleanup(version: currentVersion)
            Defaults.cleanupVersion = 1
        }
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
    
    private func createDirectoryIfNeeded() {
        _ = URL.nftDirectory
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Navigator.shared.showControlCenter(addWallet: false)
        return true
    }
    
    @IBAction func didClickNewWindowItem(_ sender: Any) {
        Navigator.shared.showControlCenter(addWallet: false)
    }
    
}
