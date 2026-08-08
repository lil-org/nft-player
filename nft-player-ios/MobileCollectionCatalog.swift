// ∅ 2026 lil org

import Foundation

typealias MobileCollectionItem = CollectionCatalogItem
typealias DownloadableMediaDescriptor = CollectionCatalogDownloadableMediaDescriptor
typealias MobileCollectionCatalog = CollectionCatalog

enum MobileCollectionBrowserGridModeStore {
    static func gridMode(
        specificCollectionId: String,
        userDefaults: UserDefaults = .standard
    ) -> MobileCollectionBrowserGridMode {
        guard let internalSlug = internalSlug(
            specificCollectionId: specificCollectionId
        ) else {
            return .defaultMode
        }
        return MobileCollectionBrowserGridModePreferences.gridMode(
            userDefaults: userDefaults,
            internalSlug: internalSlug
        )
    }

    static func save(
        gridMode: MobileCollectionBrowserGridMode,
        specificCollectionId: String,
        userDefaults: UserDefaults = .standard
    ) {
        guard let internalSlug = internalSlug(
            specificCollectionId: specificCollectionId
        ) else {
            return
        }
        MobileCollectionBrowserGridModePreferences.save(
            gridMode: gridMode,
            userDefaults: userDefaults,
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
