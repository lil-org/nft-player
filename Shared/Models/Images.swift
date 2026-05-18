// ∅ 2026 lil org

import Cocoa

struct Images {
    
    static var infoTitleBar: NSImage { systemName("info.circle") }
    static var backTitleBar: NSImage { systemName("chevron.backward") }
    static var forwardTitleBar: NSImage { systemName("chevron.forward") }
    static var nextCollectionTitleBar: NSImage { systemName("forward.circle") }
    static var playlistConfiguration: NSImage { systemName("line.3.horizontal.circle") }
    
    private static func systemName(_ systemName: String) -> NSImage {
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!
    }
    
}
