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
    private static var itemsById = [String: SuggestedItem]()
    static var visibleItems: [SuggestedItem] {
        ensureItemsLoaded()
        return allItems
    }

    static var allDownloadableCollectionItems: [SuggestedItem] {
        ensureItemsLoaded()
        return allItems.filter(\.isDownloadableCollection)
    }

    static func item(id: String) -> SuggestedItem? {
        ensureItemsLoaded()
        return itemsById[id]
    }
    
    static func bundledTokens(collectionId: String) -> BundledTokens? {
        if let url = bundle.url(forResource: "Tokens/" + collectionId, withExtension: "json") ?? bundle.url(forResource: "Tokens/" + collectionId.lowercased(), withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundledTokens = try? JSONDecoder().decode(BundledTokens.self, from: data) {
            return bundledTokens
        } else {
            return nil
        }
    }

    private static func ensureItemsLoaded() {
        guard allItems.isEmpty else { return }
        guard let url = bundle.url(forResource: "items", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SuggestedItem].self, from: data) else {
            return
        }
        allItems = items
        itemsById = items.reduce(into: [:]) { result, item in
            result[item.id] = result[item.id] ?? item
        }
    }
    
}
