// ∅ 2026 lil org

import Foundation

extension CollectionCatalog {

    private static let generativeThumbnailBaseURL = URL(string: "https://cdn.lil.org/player")!

    static func standardThumbsPathsAvailable(specificCollectionId: String) -> Bool {
        SuggestedItemsService.item(id: specificCollectionId)?.standardThumbsPathsAvailable == true
    }

    static func collectionBrowseColumnCount(specificCollectionId: String) -> Int {
        SuggestedItemsService.item(id: specificCollectionId)?
            .iosCollectionBrowserColumnCount == 2
            ? 2
            : MobilePlayerBrowserLayout.defaultColumnCount
    }

    static func collectionBrowseThumbnailDescriptor(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        if let descriptor = bundledGenerativeThumbnailDescriptor(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) {
            return descriptor
        }

        if let descriptor = nativeMetalCardThumbnailDescriptor(
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

    static func collectionBrowseThumbnailDescriptor(
        for primaryDescriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        return standardThumbnailDescriptor(for: primaryDescriptor) ?? primaryDescriptor
    }

    private static func standardThumbnailDescriptor(
        for primaryDescriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard primaryDescriptor.purpose == .primary,
              let suggestedItem = SuggestedItemsService.item(id: primaryDescriptor.collectionId),
              suggestedItem.standardThumbsPathsAvailable == true,
              var originalURLComponents = URLComponents(
                url: primaryDescriptor.url,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }

        originalURLComponents.query = nil
        originalURLComponents.fragment = nil
        guard let originalURL = originalURLComponents.url else { return nil }

        let thumbnailURL: URL
        if let standardThumbsBaseURL = suggestedItem.standardThumbsBaseURL {
            guard let thumbnailBaseURLComponents = URLComponents(string: standardThumbsBaseURL),
                  let scheme = thumbnailBaseURLComponents.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  thumbnailBaseURLComponents.host?.isEmpty == false,
                  let thumbnailBaseURL = thumbnailBaseURLComponents.url else {
                return nil
            }

            let originalStem = originalURL.deletingPathExtension().lastPathComponent
            guard !originalStem.isEmpty,
                  originalStem != "/",
                  originalStem != ".",
                  originalStem != ".." else {
                return nil
            }

            thumbnailURL = thumbnailBaseURL
                .appendingPathComponent("\(originalStem).webp", isDirectory: false)
        } else {
            let originalStem = originalURL.deletingPathExtension().lastPathComponent
            guard !originalURL.pathExtension.isEmpty,
                  !originalStem.isEmpty,
                  originalStem != ".",
                  originalStem != ".." else {
                return nil
            }

            thumbnailURL = originalURL
                .deletingLastPathComponent()
                .appendingPathComponent("thumbs", isDirectory: true)
                .appendingPathComponent("\(originalStem).webp", isDirectory: false)
        }

        return CollectionCatalogDownloadableMediaDescriptor(
            collectionId: primaryDescriptor.collectionId,
            tokenId: primaryDescriptor.tokenId,
            tokenIndex: primaryDescriptor.tokenIndex,
            media: .staticImage(url: thumbnailURL, fileExtension: "webp"),
            purpose: .collectionBrowserThumbnail,
            thumbnailAspectRatio: primaryDescriptor.thumbnailAspectRatio
        )
    }

    /// Native metal card collections have no downloadable primary descriptor on macOS —
    /// the pager renders them with Metal — so derive the browse thumbnail straight from
    /// the render kind's static face image. iOS reaches the same thumbnail URLs through
    /// `downloadableMediaDescriptor`, which is iOS-only for these collections.
    private static func nativeMetalCardThumbnailDescriptor(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
#if os(macOS)
        guard let renderKind = NativeMetalCardRenderKind(collectionId: specificCollectionId),
              let primaryDescriptor = nativeMetalCardStaticMediaDescriptor(
                renderKind: renderKind,
                tokenIndex: tokenIndex
              ) else {
            return nil
        }

        return standardThumbnailDescriptor(for: primaryDescriptor) ?? primaryDescriptor
#else
        return nil
#endif
    }

    private static func bundledGenerativeThumbnailDescriptor(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let token = TokenGenerator.bundledWebGenerativeToken(
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
        return CollectionCatalogDownloadableMediaDescriptor(
            collectionId: specificCollectionId,
            tokenId: token.id,
            tokenIndex: tokenIndex,
            media: .staticImage(url: thumbnailURL, fileExtension: "webp"),
            purpose: .collectionBrowserThumbnail,
            thumbnailAspectRatio: token.thumbnailAspectRatio
        )
    }
}
