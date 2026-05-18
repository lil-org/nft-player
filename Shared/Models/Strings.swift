// ∅ 2026 lil org

import Foundation

struct Strings {

    static let viewOnBlockscout = loc("View on Blockscout")
    static let viewOnOpensea = loc("View on OpenSea")
    static let viewOnSolanaExplorer = loc("View on Solana Explorer")
    static let viewOnTzkt = loc("View on TzKT")
    static let cancel = loc("Cancel")
    static let ok = loc("OK")
    static let retry = loc("Retry")
    static let nftFolder = loc("Nft Folder")
    static let somethingWentWrong = loc("Something went wrong")
    static let experimetalOfflineGeneration = loc("Offline generation is a new experimental feature")
    static let letUsKnowOfIssues = loc("Let us know of any issues.")
    static let back = loc("Back")
    static let forward = loc("Forward")
    static let info = loc("Info")
    static let more = loc("More")
    static let editPlaylist = loc("Edit Playlist")
    static let nextCollection = loc("Next Collection")
    static let finish = loc("Finish")
    static let share = loc("Share")
    static let bookmark = loc("Bookmark")
    static let removeBookmark = loc("Remove Bookmark")
    static let continueViewing = loc("Continue Viewing")
    static let viewAgain = loc("View Again")
    static let play = loc("Play")
    static let go = loc("Go")
    static let tokenId = loc("Token Id")
    static let sendFeedback = loc("Send Feedback")
    static let mail = loc("Mail")
    static let rateOnTheAppStore = loc("Rate on the App Store")
    static let changeAppIcon = loc("Change App Icon")
    static let selectSomethingInTheApp = loc("Select something in the app.")
    
    static let navigate = loc("Navigate")
    static let toggleInfo = loc("Toggle Info")

    static let airplay = "AirPlay"
    static let x = "𝕏"
    static let github = "GitHub"
    static let blockExplorer = "Blockscout"
    static let opensea = "OpenSea"
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
