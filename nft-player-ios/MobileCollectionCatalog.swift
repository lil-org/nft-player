// ∅ 2026 lil org

import Foundation

typealias MobileCollectionItem = CollectionCatalogItem
typealias DownloadableMediaDescriptor = CollectionCatalogDownloadableMediaDescriptor
typealias MobileCollectionCatalog = CollectionCatalog

enum MobileCollectionBrowserGridModeStore {
    static func gridMode(
        specificCollectionId: String,
        defaultColumnCount: Int
    ) -> MobileCollectionBrowserGridMode {
        let defaultGridMode = MobileCollectionBrowserGridMode(
            rawValue: defaultColumnCount
        ) ?? .threeColumns
        guard let internalSlug = internalSlug(
            specificCollectionId: specificCollectionId
        ) else {
            return defaultGridMode
        }
        return MobileCollectionBrowserGridModePreferences.gridMode(
            userDefaults: .standard,
            internalSlug: internalSlug,
            defaultGridMode: defaultGridMode
        )
    }

    static func save(
        gridMode: MobileCollectionBrowserGridMode,
        specificCollectionId: String
    ) {
        guard let internalSlug = internalSlug(
            specificCollectionId: specificCollectionId
        ) else {
            return
        }
        MobileCollectionBrowserGridModePreferences.save(
            gridMode: gridMode,
            userDefaults: .standard,
            internalSlug: internalSlug
        )
    }

    private static func internalSlug(specificCollectionId: String) -> String? {
        guard let internalSlug = SuggestedItemsService.item(
            id: specificCollectionId
        )?.internalSlug,
              !internalSlug.isEmpty else {
            return nil
        }
        return internalSlug
    }
}
