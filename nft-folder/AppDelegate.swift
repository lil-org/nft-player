// ∅ 2026 lil org

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let currentInstanceId = UUID().uuidString
    private var terminateFlushTimeoutWorkItem: DispatchWorkItem?
    private var isReplyingToTerminate = false
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        PlayerICloudSync.shared.start()
        Navigator.shared.showControlCenter()
        
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.post(name: .mustTerminate, object: currentInstanceId)
        notificationCenter.addObserver(self, selector: #selector(terminateInstance(_:)), name: .mustTerminate, object: nil, suspensionBehavior: .deliverImmediately)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        terminateFlushTimeoutWorkItem?.cancel()
        terminateFlushTimeoutWorkItem = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isReplyingToTerminate else { return .terminateNow }

        let timeoutWorkItem = DispatchWorkItem { [weak self, weak sender] in
            guard let self, let sender else { return }
            finishTerminationFlush(sender)
        }
        terminateFlushTimeoutWorkItem = timeoutWorkItem

        PlayerICloudSync.shared.flushPendingChanges { [weak self, weak sender] in
            DispatchQueue.main.async {
                guard let self, let sender else { return }
                finishTerminationFlush(sender)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeoutWorkItem)
        return .terminateLater
    }

    private func finishTerminationFlush(_ sender: NSApplication) {
        guard !isReplyingToTerminate else { return }

        isReplyingToTerminate = true
        terminateFlushTimeoutWorkItem?.cancel()
        terminateFlushTimeoutWorkItem = nil
        sender.reply(toApplicationShouldTerminate: true)
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
