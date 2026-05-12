// ∅ 2026 lil org

import Foundation

var alternativeResourcesPath: String?

struct SuggestedItemsService {
    
    static let bundle: Bundle = {
        if let altPath = alternativeResourcesPath,
           let altBundle = Bundle(url: URL(fileURLWithPath: altPath + "/Contents/Resources/Suggested.bundle")) {
            return altBundle
        } else if let bundleURL = Bundle.main.url(forResource: "Suggested", withExtension: "bundle"),
           let suggestedBundle = Bundle(url: bundleURL) {
            return suggestedBundle
        } else {
            return Bundle.main
        }
    }()
    
    static var allItems = [SuggestedItem]()
    static var visibleItems = readSuggestedItems()
    static var toHide = Set(Defaults.suggestedItemsToHide)

    static var allDownloadableCollectionItems: [SuggestedItem] {
        ensureItemsLoaded()
        return allItems.filter(\.isDownloadableCollection)
    }
    
    static func doNotSuggestAnymore(item: SuggestedItem) {
        visibleItems.removeAll(where: { item.id == $0.id })
        toHide.insert(item.id)
        Defaults.suggestedItemsToHide = Array(toHide)
    }
    
    static func suggestedItems(address: String) -> [SuggestedItem] {
        let lowercased = address.lowercased()
        guard !address.hasSuffix(".eth") else { return [] }
        ensureItemsLoaded()
        return allItems.filter {
            $0.address.lowercased() == lowercased && shouldIncludeInVisibleItems($0)
        }
    }
    
    static func bundledTokens(collectionId: String) -> BundledTokens? {
        if let url = bundle.url(forResource: "Tokens/" + collectionId, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundledTokens = try? JSONDecoder().decode(BundledTokens.self, from: data) {
            return bundledTokens
        } else {
            return nil
        }
    }
    
    static func restoredSuggestedItems(usersWallets: [WatchOnlyWallet]) -> [SuggestedItem] {
        let walletsIds = Set(usersWallets.map { $0.id })
        let hiddenAndAddedByUser = Defaults.suggestedItemsToHide.filter { walletsIds.contains($0) }
        Defaults.suggestedItemsToHide = hiddenAndAddedByUser
        toHide = Set(hiddenAndAddedByUser)
        visibleItems = readSuggestedItems()
        return visibleItems
    }
    
    private static func readSuggestedItems() -> [SuggestedItem] {
        ensureItemsLoaded()
        
        let filtered = allItems.filter { item in
            !toHide.contains(item.id) && shouldIncludeInVisibleItems(item)
        }
        return filtered
    }

    private static func shouldIncludeInVisibleItems(_ item: SuggestedItem) -> Bool {
#if os(iOS)
        return true
#else
        return !item.isSolanaCollection
#endif
    }

    private static func ensureItemsLoaded() {
        guard allItems.isEmpty else { return }
        guard let url = bundle.url(forResource: "items", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SuggestedItem].self, from: data) else {
            return
        }
        allItems = items
    }
    
}
