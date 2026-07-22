// ∅ 2026 lil org

import Foundation

var alternativeResourcesPath: String?

struct SuggestedItemsService {

    private struct SuggestedArtistMetadata: Decodable {

        let name: String
        private let website: String?
        private let x: String?
        private let bluesky: String?

        func artist(slug: String) -> SuggestedArtist {
            SuggestedArtist(
                id: slug,
                name: name,
                website: Self.webURL(website),
                x: Self.webURL(x),
                bluesky: Self.webURL(bluesky)
            )
        }

        private static func webURL(_ value: String?) -> URL? {
            guard let value,
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host?.isEmpty == false else {
                return nil
            }
            return url
        }

        private enum CodingKeys: CodingKey {
            case name
            case website
            case x
            case bluesky
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            website = try? container.decode(String.self, forKey: .website)
            x = try? container.decode(String.self, forKey: .x)
            bluesky = try? container.decode(String.self, forKey: .bluesky)
        }

    }
    
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
    private static let artistsBySlug: [String: SuggestedArtist] = {
        guard let url = bundle.url(forResource: "artists", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let metadataBySlug = try? JSONDecoder().decode(
                [String: SuggestedArtistMetadata].self,
                from: data
              ) else {
            return [:]
        }
        return metadataBySlug.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.artist(slug: entry.key)
        }
    }()
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

    static func artists(forCollectionId collectionId: String) -> [SuggestedArtist] {
        guard let artistSlugs = item(id: collectionId)?.artists else { return [] }
        return artistSlugs.compactMap { artistsBySlug[$0] }
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
