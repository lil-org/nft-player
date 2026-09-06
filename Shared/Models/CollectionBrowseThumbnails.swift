// ∅ 2026 lil org

import Foundation

nonisolated struct CollectionBrowseImageSources: Hashable, Sendable {
    let smallestThumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    let smallThumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor
    let thumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor
    let largeDescriptor: CollectionCatalogDownloadableMediaDescriptor

    init(
        smallestThumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor? = nil,
        smallThumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor? = nil,
        thumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor,
        largeDescriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        self.smallThumbnailDescriptor = smallThumbnailDescriptor
            ?? thumbnailDescriptor
        self.smallestThumbnailDescriptor = smallestThumbnailDescriptor
        self.thumbnailDescriptor = thumbnailDescriptor
        self.largeDescriptor = largeDescriptor
    }

    func descriptor(
        for quality: CollectionBrowseImageQuality
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        switch quality {
        case .smallestThumbnail:
            return smallestThumbnailDescriptor
        case .smallThumbnail:
            return smallThumbnailDescriptor
        case .thumbnail:
            return thumbnailDescriptor
        case .large:
            return largeDescriptor
        }
    }

    func quality(
        of descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> CollectionBrowseImageQuality? {
        if descriptor == largeDescriptor {
            return .large
        }
        if descriptor == thumbnailDescriptor {
            return .thumbnail
        }
        if descriptor == smallThumbnailDescriptor {
            return .smallThumbnail
        }
        if let smallestThumbnailDescriptor,
           descriptor == smallestThumbnailDescriptor {
            return .smallestThumbnail
        }
        return nil
    }

    var descriptorsByDescendingQuality: [CollectionCatalogDownloadableMediaDescriptor] {
        [
            largeDescriptor,
            thumbnailDescriptor,
            smallThumbnailDescriptor,
            smallestThumbnailDescriptor,
        ]
            .compactMap { $0 }
            .reduce(into: []) { descriptors, descriptor in
                if !descriptors.contains(descriptor) {
                    descriptors.append(descriptor)
                }
            }
    }
}

nonisolated extension CollectionCatalog {

    private static let generativeThumbnailBaseURL = URL(string: "https://cdn.lil.org/player")!
    static func standardThumbsPathsAvailable(specificCollectionId: String) -> Bool {
        SuggestedItemsService.item(id: specificCollectionId)?.standardThumbsPathsAvailable == true
    }

    static func desktopCollectionBrowseColumnCount(
        specificCollectionId: String
    ) -> Int {
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

    static func collectionBrowseImageSources(
        specificCollectionId: String,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        guard let thumbnailDescriptor = collectionBrowseThumbnailDescriptor(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }
        let smallThumbnailDescriptor = sizedThumbnailDescriptor(
            for: thumbnailDescriptor,
            width: .width260
        ) ?? thumbnailDescriptor
        let smallestThumbnailDescriptor = sizedThumbnailDescriptor(
            for: thumbnailDescriptor,
            width: .width140
        )

        let largeDescriptor: CollectionCatalogDownloadableMediaDescriptor
#if os(iOS) || os(macOS)
        if let renderKind = NativeMetalCardRenderKind(
            collectionId: specificCollectionId
        ) {
            switch renderKind {
            case .cardNft2, .ponchoDrifella:
                largeDescriptor = nativeMetalCardStaticMediaDescriptor(
                    renderKind: renderKind,
                    tokenIndex: tokenIndex
                ) ?? thumbnailDescriptor
            }
        } else {
            largeDescriptor = standardLargeDescriptor(for: thumbnailDescriptor)
        }
#else
        largeDescriptor = standardLargeDescriptor(for: thumbnailDescriptor)
#endif

        return CollectionBrowseImageSources(
            smallestThumbnailDescriptor: smallestThumbnailDescriptor,
            smallThumbnailDescriptor: smallThumbnailDescriptor,
            thumbnailDescriptor: thumbnailDescriptor,
            largeDescriptor: largeDescriptor
        )
    }

    private static func standardLargeDescriptor(
        for thumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        guard collectionBrowseMidImagesAvailable(
            specificCollectionId: thumbnailDescriptor.collectionId
        ) else {
            guard let primaryDescriptor = downloadableMediaDescriptor(
                specificCollectionId: thumbnailDescriptor.collectionId,
                tokenIndex: thumbnailDescriptor.tokenIndex
            ), primaryDescriptor.isStaticImage else {
                return thumbnailDescriptor
            }
            return primaryDescriptor
        }

        return midDescriptor(for: thumbnailDescriptor) ?? thumbnailDescriptor
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

    private static func midDescriptor(
        for thumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard thumbnailDescriptor.isCollectionBrowserThumbnail,
              let midURL = CollectionBrowseImageURLMapping.midURL(
                for: thumbnailDescriptor.url
              ) else {
            return nil
        }

        return CollectionCatalogDownloadableMediaDescriptor(
            collectionId: thumbnailDescriptor.collectionId,
            tokenId: thumbnailDescriptor.tokenId,
            tokenIndex: thumbnailDescriptor.tokenIndex,
            media: .staticImage(url: midURL, fileExtension: "webp"),
            purpose: .collectionBrowserMid,
            thumbnailAspectRatio: thumbnailDescriptor.thumbnailAspectRatio
        )
    }

    static func collectionBrowseSizedThumbnailDescriptor(
        specificCollectionId: String,
        tokenIndex: Int,
        width: CollectionBrowseThumbnailWidth
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let thumbnailDescriptor = collectionBrowseThumbnailDescriptor(
            specificCollectionId: specificCollectionId,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }
        return sizedThumbnailDescriptor(
            for: thumbnailDescriptor,
            width: width
        )
    }

    private static func sizedThumbnailDescriptor(
        for thumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor,
        width: CollectionBrowseThumbnailWidth
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        let offset = SuggestedItemsService.item(
            id: thumbnailDescriptor.collectionId
        )?.sizedThumbsIndexOffset ?? 0
        let (sizedThumbnailIndex, overflow) = thumbnailDescriptor.tokenIndex
            .addingReportingOverflow(offset)

        guard !overflow,
              sizedThumbnailIndex >= 0,
              thumbnailDescriptor.isCollectionBrowserThumbnail,
              let mappingSourceURL = sizedThumbnailMappingSourceURL(
                for: thumbnailDescriptor
              ),
              let sizedThumbnailURL = CollectionBrowseImageURLMapping
                .thumbnailURL(
                    for: mappingSourceURL,
                    tokenIndex: sizedThumbnailIndex,
                    width: width
                ) else {
            return nil
        }

        return CollectionCatalogDownloadableMediaDescriptor(
            collectionId: thumbnailDescriptor.collectionId,
            tokenId: thumbnailDescriptor.tokenId,
            tokenIndex: thumbnailDescriptor.tokenIndex,
            media: .staticImage(url: sizedThumbnailURL, fileExtension: "webp"),
            purpose: .collectionBrowserThumbnail,
            thumbnailAspectRatio: thumbnailDescriptor.thumbnailAspectRatio
        )
    }

    private static func sizedThumbnailMappingSourceURL(
        for thumbnailDescriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> URL? {
        guard thumbnailDescriptor.collectionId
                == NativeMetalCardRenderKind.ponchoDrifella.collectionId else {
            return thumbnailDescriptor.url
        }

        let thumbnailDirectoryURL = thumbnailDescriptor.url
            .deletingLastPathComponent()
        let frontsDirectoryURL = thumbnailDirectoryURL
            .deletingLastPathComponent()
        guard thumbnailDirectoryURL.lastPathComponent == "thumbs",
              frontsDirectoryURL.lastPathComponent == "fronts" else {
            return nil
        }
        return frontsDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent(
                thumbnailDescriptor.url.lastPathComponent,
                isDirectory: false
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
