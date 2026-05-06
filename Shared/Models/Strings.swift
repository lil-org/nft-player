// ∅ 2026 lil org

import Foundation

struct Strings {
        
    static let newFolder = loc("New Folder")
    static let removeFolder = loc("Remove Folder")
    static let hardReset = loc("Hard Reset")
    static let viewOnArtBlocks = loc("View on Art Blocks")
    static let viewOnBlockscout = loc("View on Blockscout")
    static let viewOnOpensea = loc("View on OpenSea")
    static let viewinFinder = loc("Show in Finder")
    static let viewOnZora = loc("View on Zora")
    static let addressOrEns = loc("Address or ENS")
    static let cancel = loc("Cancel")
    static let ok = loc("OK")
    static let sync = loc("Sync")
    static let pause = loc("Pause")
    static let stopAllDownloads = loc("Stop Downloads")
    static let newFolderMenuItem = newFolder
    static let retry = loc("Retry")
    static let nftFolder = loc("Nft Folder")
    static let somethingWentWrong = loc("Something went wrong")
    static let thisWorksForFilesInsideNftFolder = loc("This works for files inside the nft folder")
    static let maxFileSize50mb = loc("Max file size 50 MB")
    static let hideFromHere = loc("Hide")
    static let downloadVideo = loc("Download video")
    static let downloadAudio = loc("Download audio")
    static let restoreHiddenItems = loc("Restore Hidden Items")
    static let eraseAllContent = loc("Erase All Content")
    static let experimetalOfflineGeneration = loc("Offline generation is a new experimental feature")
    static let letUsKnowOfIssues = loc("Let us know of any issues.")
    static let back = loc("Back")
    static let forward = loc("Forward")
    static let info = loc("Info")
    static let editPlaylist = loc("Edit Playlist")
    static let nextCollection = loc("Next Collection")
    static let anotherCollection = loc("Another Collection")
    static let continueViewing = loc("Continue Viewing")
    static let watchAgain = loc("Watch Again")
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
    static let ens = "ENS"
    static let lilOrgLinkWithEmojis = "🌐 lil.org 👈"
    
    private static func loc(_ string: String.LocalizationValue) -> String {
        return String(localized: string)
    }

    static func percent(_ value: Int) -> String {
        String.localizedStringWithFormat(loc("%lld%%"), Int64(value))
    }
    
}
