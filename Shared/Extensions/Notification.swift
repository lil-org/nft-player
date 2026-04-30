// ∅ 2026 lil org

import Foundation

extension Notification.Name {
    
    static let mustTerminate = Notification.Name("TerminatePreviousInstance")
    static let walletsUpdate = Notification.Name("WalletsUpdate")
    static let downloadsStatusUpdate = Notification.Name("DownloadsStatusUpdate")
    static let didUpdateWalletAvatar = Notification.Name("didUpdateWalletAvatar")
    static let updateAnotherVisibleWalletsList = Notification.Name("updateAnotherVisibleWalletsList")
    static let updateAnotherVisibleSuggestions = Notification.Name("updateAnotherVisibleSuggestions")
    
}
