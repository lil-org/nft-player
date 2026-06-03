// ∅ 2026 lil org

import Cocoa

extension Notification.Name {
    static let playerWindowsDidChange = Notification.Name("PlayerWindowsDidChange")
}

struct Window {

    private static var openPlayerWindows = Set<ObjectIdentifier>()
    
    static func closeOtherPlayers() {
        NSApplication.shared.windows.forEach {
            if $0 is LocalHtmlWindow {
                $0.close()
            }
        }
    }
    
    static func closeAllControlCenters() {
        NSApplication.shared.windows.forEach {
            if $0 is RightClickActivatingWindow {
                $0.close()
            }
        }
    }
    
    static var hasOpenPlayerWindows: Bool {
        return !openPlayerWindows.isEmpty
    }

    static func registerPlayerWindow(_ window: LocalHtmlWindow) {
        guard openPlayerWindows.insert(ObjectIdentifier(window)).inserted else { return }
        notifyPlayerWindowsDidChange()
    }

    static func unregisterPlayerWindow(_ window: LocalHtmlWindow) {
        guard openPlayerWindows.remove(ObjectIdentifier(window)) != nil else { return }
        notifyPlayerWindowsDidChange()
    }

    private static func notifyPlayerWindowsDidChange() {
        NotificationCenter.default.post(name: .playerWindowsDidChange, object: nil)
    }

}
