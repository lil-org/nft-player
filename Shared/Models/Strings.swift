// ∅ 2026 lil org

import Foundation

struct Strings {

    static let viewOnBlockscout = loc("View on Blockscout")
    static let viewOnSolanaExplorer = loc("View on Solana Explorer")
    static let viewOnTzkt = loc("View on TzKT")
    static let ok = loc("OK")
    static let nftFolder = loc("Nft Folder")
    static let back = loc("Back")
    static let forward = loc("Forward")
    static let more = loc("More")
    static let finish = loc("Finish")
    static let share = loc("Share")
    static let bookmark = loc("Bookmark")
    static let removeBookmark = loc("Remove Bookmark")
    static let continueViewing = loc("Continue Viewing")
    static let viewAgain = loc("View Again")
    static let play = loc("Play")
    static let sendFeedback = loc("Send Feedback")
    static let mail = loc("Mail")
    static let rateOnTheAppStore = loc("Rate on the App Store")
    static let changeAppIcon = loc("Change App Icon")
    static let selectSomethingInTheApp = loc("Select something in the app.")
    
    static let navigate = loc("Navigate")
    static let toggleInfo = loc("Toggle Info")

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

    static func viewOnWebTitle(for url: URL?) -> String {
        if url?.isHosted(on: "explorer.solana.com") == true {
            return viewOnSolanaExplorer
        }
        if url?.isHosted(on: "tzkt.io") == true {
            return viewOnTzkt
        }
        return viewOnBlockscout
    }
    
}

private extension URL {
    func isHosted(on expectedHost: String) -> Bool {
        guard var host = host?.lowercased() else { return false }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host == expectedHost
    }
}
