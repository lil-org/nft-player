// ∅ 2026 lil org

import Foundation

typealias MobileCollectionItem = CollectionCatalogItem
typealias DownloadableMediaDescriptor = CollectionCatalogDownloadableMediaDescriptor
typealias MobileCollectionCatalog = CollectionCatalog

extension MobileCollectionCatalog {

    private static let generativeThumbnailBaseURL = URL(string: "https://cdn.lil.org/player")!

    static func staticImageGridMediaDescriptor(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> DownloadableMediaDescriptor? {
        if let descriptor = bundledGenerativeThumbnailDescriptor(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) {
            return descriptor
        }

        return downloadableMediaDescriptor(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        )
    }

    private static func bundledGenerativeThumbnailDescriptor(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> DownloadableMediaDescriptor? {
        guard let tokenId = TokenGenerator.bundledWebGenerativeTokenId(
                specificCollectionId: specificCollectionId,
                tokenIndex: tokenIndex
              ),
              let internalSlug = SuggestedItemsService.item(id: specificCollectionId)?.internalSlug,
              !internalSlug.isEmpty else {
            return nil
        }

        let thumbnailURL = generativeThumbnailBaseURL
            .appendingPathComponent(internalSlug, isDirectory: true)
            .appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent("\(tokenIndex).webp", isDirectory: false)
        return DownloadableMediaDescriptor(
            collectionId: specificCollectionId,
            tokenId: tokenId,
            tokenIndex: tokenIndex,
            media: .staticImage(url: thumbnailURL, fileExtension: "webp"),
            purpose: .staticImageGridThumbnail
        )
    }
}
