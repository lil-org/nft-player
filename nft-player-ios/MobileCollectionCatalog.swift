// ∅ 2026 lil org

import Foundation

typealias MobileCollectionItem = CollectionCatalogItem
typealias DownloadableMediaDescriptor = CollectionCatalogDownloadableMediaDescriptor
typealias MobileCollectionCatalog = CollectionCatalog

enum MobileCollectionBrowserGridModeStore {
    private static let supportedColumnCounts = Set([2, 3])
    private static let userDefaultsKeyPrefix = "iosCollectionBrowserColumnCountOverride."

    static func columnCount(
        specificCollectionId: String,
        defaultColumnCount: Int
    ) -> Int {
        guard let key = userDefaultsKey(specificCollectionId: specificCollectionId),
              let storedColumnCount = UserDefaults.standard.object(forKey: key) as? Int,
              supportedColumnCounts.contains(storedColumnCount) else {
            return defaultColumnCount
        }
        return storedColumnCount
    }

    static func save(
        columnCount: Int,
        specificCollectionId: String
    ) {
        guard supportedColumnCounts.contains(columnCount),
              let key = userDefaultsKey(specificCollectionId: specificCollectionId) else {
            return
        }
        UserDefaults.standard.set(columnCount, forKey: key)
    }

    private static func userDefaultsKey(specificCollectionId: String) -> String? {
        guard let internalSlug = SuggestedItemsService.item(
            id: specificCollectionId
        )?.internalSlug,
              !internalSlug.isEmpty else {
            return nil
        }
        return userDefaultsKeyPrefix + internalSlug
    }
}
