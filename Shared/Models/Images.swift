// ∅ 2026 lil org

import Cocoa

struct Images {
    
    static var backTitleBar: NSImage { systemName("chevron.backward") }
    static var forwardTitleBar: NSImage { systemName("chevron.forward") }
    static var bookmarkTitleBar: NSImage { systemName("bookmark") }
    static var bookmarkFillTitleBar: NSImage { systemName("bookmark.fill") }
    static var moreTitleBar: NSImage { systemName("ellipsis.circle") }
    
    private static func systemName(_ systemName: String) -> NSImage {
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!
    }
    
}
