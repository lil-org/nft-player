// ∅ 2026 lil org

import Foundation
import os

nonisolated private let alternativeResourcesPathStorage = OSAllocatedUnfairLock(
    initialState: Optional<String>.none
)

nonisolated var alternativeResourcesPath: String? {
    get { alternativeResourcesPathStorage.withLock { $0 } }
    set { alternativeResourcesPathStorage.withLock { $0 = newValue } }
}

nonisolated enum SuggestedItemsService {

    private struct Snapshot: Sendable {
        let allItems: [SuggestedItem]
        let itemsById: [String: SuggestedItem]
        let itemsByResourceName: [String: SuggestedItem]
        let artistsBySlug: [String: SuggestedArtist]
    }

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
    
    private static let alternativeResourceDirectoryURL = alternativeResourcesPath.map {
        URL(fileURLWithPath: $0 + "/Contents/Resources", isDirectory: true)
    }

    static let bundle: Bundle = {
        if let alternativeResourceDirectoryURL,
           let altBundle = Bundle(
            url: alternativeResourceDirectoryURL.appendingPathComponent(
                "Suggested.bundle",
                isDirectory: true
            )
           ) {
            return altBundle
        } else if let bundleURL = Bundle.main.url(forResource: "Suggested", withExtension: "bundle"),
           let suggestedBundle = Bundle(url: bundleURL) {
            return suggestedBundle
        } else {
            return Bundle.main
        }
    }()

    private static let snapshot: Snapshot = {
        let allItems = loadItems(resource: "items")

        let itemsById = allItems.reduce(into: [String: SuggestedItem]()) { result, item in
            result[item.id] = result[item.id] ?? item
        }
        let itemsByResourceName = allItems.reduce(into: [String: SuggestedItem]()) { result, item in
            result[item.bundledResourceName] = result[item.bundledResourceName] ?? item
        }

        let artistsBySlug: [String: SuggestedArtist]
        if let url = bundle.url(forResource: "artists", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let metadataBySlug = try? JSONDecoder().decode(
            [String: SuggestedArtistMetadata].self,
            from: data
           ) {
            artistsBySlug = metadataBySlug.reduce(into: [:]) { result, entry in
                result[entry.key] = entry.value.artist(slug: entry.key)
            }
        } else {
            artistsBySlug = [:]
        }

        return Snapshot(
            allItems: allItems,
            itemsById: itemsById,
            itemsByResourceName: itemsByResourceName,
            artistsBySlug: artistsBySlug
        )
    }()

    private static func loadItems(resource: String) -> [SuggestedItem] {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SuggestedItem].self, from: data) else {
            return []
        }
        return items
    }

    static let allItems = snapshot.allItems
    static let visibleItems = snapshot.allItems.filter {
        isCollectionAvailableOnCurrentPlatform(id: $0.id)
    }
    static let allDownloadableCollectionItems = visibleItems.filter(\.isDownloadableCollection)

    static func item(id: String) -> SuggestedItem? {
        snapshot.itemsById[id]
    }

    static func item(resourceName: String) -> SuggestedItem? {
        snapshot.itemsByResourceName[resourceName]
    }

    static func isCollectionAvailableOnCurrentPlatform(id: String) -> Bool {
#if os(iOS)
        return true
#else
        guard let item = item(id: id) else { return true }
        return item.iosOnly != true || item.generativeOnly != true
#endif
    }

    static func artists(forCollectionId collectionId: String) -> [SuggestedArtist] {
        guard let artistSlugs = item(id: collectionId)?.artists else { return [] }
        return artistSlugs.compactMap { snapshot.artistsBySlug[$0] }
    }
    
    static func bundledTokens(collectionId: String) -> BundledTokens? {
        if let collection = scriptItem(collectionId: collectionId),
           let url = bundledTokensURL(collectionId: collectionId),
           let data = try? Data(contentsOf: url),
           let bundledTokens = try? BundledTokens(data: data, collection: collection) {
            return bundledTokens
        } else {
            return nil
        }
    }

    static func bundledTokensURL(collectionId: String) -> URL? {
        bundledResourceURL(collectionId: collectionId, subdirectory: "Tokens")
    }

    static func scriptItem(collectionId: String) -> SuggestedItem? {
        let lowercaseId = collectionId.lowercased()
        return item(id: collectionId) ?? item(id: lowercaseId)
            ?? item(resourceName: collectionId) ?? item(resourceName: lowercaseId)
    }

    private static func bundledResourceURL(collectionId: String, subdirectory: String) -> URL? {
        let collection = item(id: collectionId) ?? item(id: collectionId.lowercased())
        let resourceName = collection?.bundledResourceName ?? collectionId
        return bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory)
            ?? bundle.url(forResource: resourceName.lowercased(), withExtension: "json", subdirectory: subdirectory)
    }

}
