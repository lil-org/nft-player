// ∅ 2026 lil org

import Foundation

nonisolated enum CollectionBrowseImageQuality: Int, Hashable, Sendable {
    case smallestThumbnail
    case smallThumbnail
    case thumbnail
    case large

    func canReplace(_ displayedQuality: Self?) -> Bool {
        guard let displayedQuality else { return true }
        return rawValue >= displayedQuality.rawValue
    }

    var isDenseGridThumbnail: Bool {
        self == .smallestThumbnail || self == .smallThumbnail
    }
}

nonisolated enum CollectionBrowseImageWindowSelection: Hashable, Sendable {
    case requestedQuality
    case locallyAvailableLarge
    case omitSatisfiedToken

    static func resolve(
        requiredQuality: CollectionBrowseImageQuality,
        isDisplayingSatisfyingThumbnail: Bool,
        isDisplayingLargeImage: Bool,
        largeImageIsLocallyAvailable: Bool
    ) -> Self {
        if requiredQuality.isDenseGridThumbnail,
           isDisplayingSatisfyingThumbnail {
            return .omitSatisfiedToken
        }
        guard requiredQuality != .large,
              isDisplayingLargeImage else {
            return .requestedQuality
        }
        return largeImageIsLocallyAvailable
            ? .locallyAvailableLarge
            : .omitSatisfiedToken
    }
}

nonisolated enum CollectionBrowseImageLoadPolicy: Sendable {
    /// `largeImageIsLocallyAvailable` is evaluated last and only when the
    /// cheap terms already pass — resolving it stats the cache file and
    /// touches its LRU entry, which must not happen on cells that can never
    /// promote.
    static func allowsLocalLargeImagePromotion(
        requiredQuality: CollectionBrowseImageQuality,
        hasDistinctLargeImage: Bool,
        largeImageIsLocallyAvailable: @autoclosure () -> Bool,
        allowsPromotion: Bool
    ) -> Bool {
        requiredQuality != .large
            && hasDistinctLargeImage
            && allowsPromotion
            && largeImageIsLocallyAvailable()
    }

    static func allowsLargeImageLoad(
        requiredQuality: CollectionBrowseImageQuality,
        hasDistinctLargeImage: Bool,
        largeImageIsLocallyAvailable: @autoclosure () -> Bool,
        allowsLocalPromotion: Bool
    ) -> Bool {
        guard hasDistinctLargeImage else { return true }
        return requiredQuality == .large
            || allowsLocalLargeImagePromotion(
                requiredQuality: requiredQuality,
                hasDistinctLargeImage: hasDistinctLargeImage,
                largeImageIsLocallyAvailable: largeImageIsLocallyAvailable(),
                allowsPromotion: allowsLocalPromotion
            )
    }
}

nonisolated enum CollectionBrowseSnapshotUpdatePolicy: Sendable {
    static func isSettledPositionEcho(
        currentCollectionId: String,
        currentItemCount: Int,
        updatedCollectionId: String,
        updatedItemCount: Int,
        updatedInitialTokenIndex: Int,
        lastPublishedTokenIndex: Int?
    ) -> Bool {
        updatedCollectionId == currentCollectionId
            && updatedItemCount == currentItemCount
            && updatedInitialTokenIndex == lastPublishedTokenIndex
    }
}

/// The 9-5-3-1 column ladder of the Photos app. Odd counts keep a center
/// column, so zoom transitions reveal content symmetrically at both sides
/// instead of forcing one-sided column shifts.
nonisolated enum MobileCollectionBrowserGridMode: Int, CaseIterable, Hashable, Sendable {
    case large = 1
    case threeColumns = 3
    case fiveColumns = 5
    case nineColumns = 9

    static let defaultMode = MobileCollectionBrowserGridMode.threeColumns

    var columnCount: Int {
        rawValue
    }

    var requiredImageQuality: CollectionBrowseImageQuality {
        switch self {
        case .large:
            .large
        case .threeColumns:
            .thumbnail
        case .fiveColumns:
            .smallThumbnail
        case .nineColumns:
            .smallestThumbnail
        }
    }

    var allowsLocalLargeImageUpgrade: Bool {
        self == .large || self == .threeColumns
    }
}

nonisolated enum CollectionBrowseThumbnailWidth: Int, CaseIterable, Hashable, Sendable {
    case width140 = 140
    case width260 = 260

    var pathComponent: String {
        String(rawValue)
    }
}

nonisolated enum CollectionBrowseImageURLMapping: Sendable {
    static func generativeMidURL(slug: String?, sourceIndex: Int?) -> URL? {
        guard let slug,
              slug.count <= 120,
              slug.range(of: "\\A[a-z0-9]+(?:_[a-z0-9]+)*\\z", options: .regularExpression) != nil,
              let sourceIndex, sourceIndex >= 0 else {
            return nil
        }
        return URL(string: "https://cdn.lil.org/player/\(slug)/mid/\(sourceIndex).webp")
    }

    static func downloadableMidURL(
        for originalURL: URL,
        standardThumbsPathsAvailable: Bool,
        standardThumbsBaseURL: String? = nil
    ) -> URL? {
        guard standardThumbsPathsAvailable,
              let thumbnailURL = standardThumbnailURL(
                for: originalURL,
                standardThumbsBaseURL: standardThumbsBaseURL
              ),
              let url = midURL(for: thumbnailURL),
              ArtworkAssetPolicy.allowsRemoteURL(url) else {
            return nil
        }
        return url
    }

    static func standardThumbnailURL(
        for originalURL: URL,
        standardThumbsBaseURL: String? = nil
    ) -> URL? {
        guard var originalURLComponents = URLComponents(
            url: originalURL,
            resolvingAgainstBaseURL: false
        ),
              let scheme = originalURLComponents.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              originalURLComponents.host?.isEmpty == false,
              let percentEncodedFileName = originalURLComponents.percentEncodedPath
                .split(separator: "/", omittingEmptySubsequences: false)
                .last,
              !percentEncodedFileName.isEmpty,
              !percentEncodedFileName.lowercased().contains("%2f"),
              !percentEncodedFileName.lowercased().contains("%5c") else {
            return nil
        }

        originalURLComponents.query = nil
        originalURLComponents.fragment = nil
        guard let originalURL = originalURLComponents.url else { return nil }

        let originalStem = originalURL.deletingPathExtension().lastPathComponent
        guard !originalStem.isEmpty,
              originalStem != ".",
              originalStem != "..",
              !originalStem.contains("/"),
              !originalStem.contains("\\") else {
            return nil
        }

        let thumbnailDirectoryURL: URL
        if let standardThumbsBaseURL {
            guard let components = URLComponents(string: standardThumbsBaseURL),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host?.isEmpty == false,
                  let baseURL = components.url else {
                return nil
            }
            thumbnailDirectoryURL = baseURL
        } else {
            guard !originalURL.pathExtension.isEmpty else { return nil }
            thumbnailDirectoryURL = originalURL
                .deletingLastPathComponent()
                .appendingPathComponent("thumbs", isDirectory: true)
        }

        return thumbnailDirectoryURL
            .appendingPathComponent("\(originalStem).webp", isDirectory: false)
    }

    static func smallThumbnailURL(
        for thumbnailURL: URL,
        tokenIndex: Int
    ) -> URL? {
        Self.thumbnailURL(
            for: thumbnailURL,
            tokenIndex: tokenIndex,
            width: .width260
        )
    }

    static func thumbnailURL(
        for thumbnailURL: URL,
        tokenIndex: Int,
        width: CollectionBrowseThumbnailWidth
    ) -> URL? {
        guard tokenIndex >= 0,
              let mapping = validatedThumbnailURL(thumbnailURL) else {
            return nil
        }
        return mapping.directoryURL
            .appendingPathComponent(width.pathComponent, isDirectory: true)
            .appendingPathComponent("\(tokenIndex).webp", isDirectory: false)
    }

    static func midURL(for thumbnailURL: URL) -> URL? {
        guard let mapping = validatedThumbnailURL(thumbnailURL) else {
            return nil
        }
        return mapping.directoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("mid", isDirectory: true)
            .appendingPathComponent(mapping.fileName, isDirectory: false)
    }

    private static func validatedThumbnailURL(
        _ thumbnailURL: URL
    ) -> (directoryURL: URL, fileName: String)? {
        guard let thumbnailURLComponents = URLComponents(
            url: thumbnailURL,
            resolvingAgainstBaseURL: false
        ),
              let scheme = thumbnailURLComponents.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              thumbnailURLComponents.host?.isEmpty == false,
              thumbnailURLComponents.query == nil,
              thumbnailURLComponents.fragment == nil else {
            return nil
        }

        let thumbnailDirectoryURL = thumbnailURL.deletingLastPathComponent()
        let percentEncodedFileName = thumbnailURLComponents.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .last
            .map { $0.lowercased() }
        guard thumbnailDirectoryURL.lastPathComponent == "thumbs",
              thumbnailURL.pathExtension.lowercased() == "webp",
              let percentEncodedFileName,
              !percentEncodedFileName.contains("%2f"),
              !percentEncodedFileName.contains("%5c"),
              !thumbnailURL.lastPathComponent.isEmpty,
              thumbnailURL.lastPathComponent != ".",
              thumbnailURL.lastPathComponent != "..",
              !thumbnailURL.lastPathComponent.contains("/"),
              !thumbnailURL.lastPathComponent.contains("\\") else {
            return nil
        }
        return (thumbnailDirectoryURL, thumbnailURL.lastPathComponent)
    }
}
