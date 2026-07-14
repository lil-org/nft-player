// ∅ 2026 lil org

import Foundation

typealias MobileCollectionItem = CollectionCatalogItem
typealias DownloadableMediaDescriptor = CollectionCatalogDownloadableMediaDescriptor
typealias MobileCollectionCatalog = CollectionCatalog

extension MobileCollectionCatalog {

    private static let generativeThumbnailBaseURL = URL(string: "https://cdn.lil.org/player")!

    static func standardThumbsPathsAvailable(specificCollectionId: String) -> Bool {
        SuggestedItemsService.item(id: specificCollectionId)?.standardThumbsPathsAvailable == true
    }

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

        guard let primaryDescriptor = downloadableMediaDescriptor(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }

        return standardThumbnailDescriptor(for: primaryDescriptor) ?? primaryDescriptor
    }

    static func staticImageGridMediaDescriptor(
        for primaryDescriptor: DownloadableMediaDescriptor
    ) -> DownloadableMediaDescriptor {
        return standardThumbnailDescriptor(for: primaryDescriptor) ?? primaryDescriptor
    }

    private static func standardThumbnailDescriptor(
        for primaryDescriptor: DownloadableMediaDescriptor
    ) -> DownloadableMediaDescriptor? {
        guard primaryDescriptor.purpose == .primary,
              standardThumbsPathsAvailable(specificCollectionId: primaryDescriptor.collectionId),
              var originalURLComponents = URLComponents(
                url: primaryDescriptor.url,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }

        originalURLComponents.query = nil
        originalURLComponents.fragment = nil
        guard let originalURL = originalURLComponents.url else { return nil }

        let originalStem = originalURL.deletingPathExtension().lastPathComponent
        guard !originalURL.pathExtension.isEmpty,
              !originalStem.isEmpty,
              originalStem != ".",
              originalStem != ".." else {
            return nil
        }

        let thumbnailURL = originalURL
            .deletingLastPathComponent()
            .appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent("\(originalStem).webp", isDirectory: false)
        return DownloadableMediaDescriptor(
            collectionId: primaryDescriptor.collectionId,
            tokenId: primaryDescriptor.tokenId,
            tokenIndex: primaryDescriptor.tokenIndex,
            media: .staticImage(url: thumbnailURL, fileExtension: "webp"),
            purpose: .staticImageGridThumbnail
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
