// ∅ 2026 lil org

import Foundation

nonisolated struct Strings: Sendable {

    static let viewOnBlockExplorer = loc("View on block explorer")
    static let viewFullscreen = loc("View fullscreen")
    static let ok = loc("OK")
    static let nftPlayer = loc("NFT Player")
    static let back = loc("Back")
    static let forward = loc("Forward")
    static let more = loc("More")
    static let gridLayout = loc("Grid layout")
    static let largeGrid = loc("Large grid: 1 column in portrait, 2 in landscape")
    static let threeColumns = loc("3 columns")
    static let fiveColumns = loc("5 columns")
    static let nineColumns = loc("9 columns")
    static let finish = loc("Finish")
    static let share = loc("Share")
    static let copyMedia = loc("Copy Media")
    static let saveAs = loc("Save As…")
    static let copyMediaFailed = loc("Could not copy media.")
    static let saveMediaFailed = loc("Could not save media.")
    static let bookmark = loc("Bookmark")
    static let removeBookmark = loc("Remove Bookmark")
    static let bookmarked = loc("Bookmarked")
    static let bookmarkRemoved = loc("Bookmark Removed")
    static let continueViewing = loc("Continue Viewing")
    static let viewAgain = loc("View Again")
    static let enterImmersiveMode = loc("Enter Immersive Mode")
    static let exitImmersiveMode = loc("Exit Immersive Mode")
    static let play = loc("Play")
    static let settings = loc("Settings")
    static let shuffle = loc("Shuffle")
    static let sendFeedback = loc("Send Feedback")
    static let search = loc("Search")
    static let cancel = loc("Cancel")
    static let nothingFound = loc("Nothing found.")
    static let mail = loc("Mail")
    static let rateOnTheAppStore = loc("Rate on the App Store")
    static let changeAppIcon = loc("Change App Icon")
    static let selectSomethingInTheApp = loc("Select something in the app.")
    static let x = "𝕏"
    static let github = "GitHub"
    static let lilOrgLinkWithEmojis = "🌐 lil.org 👈"
    
    private static func loc(_ string: String.LocalizationValue) -> String {
        return String(localized: string)
    }

    static func percent(_ value: Int) -> String {
        String.localizedStringWithFormat(loc("%lld%%"), Int64(value))
    }

    static func pagePosition(current: Int, total: Int) -> String {
        String(format: loc("%1$lld of %2$lld"), Int64(current), Int64(total))
    }
    
}
