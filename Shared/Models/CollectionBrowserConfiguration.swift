// ∅ 2026 lil org

import Foundation

nonisolated enum CollectionBrowseImageQuality: Int, Hashable, Sendable {
    case smallThumbnail
    case thumbnail
    case large

    func canReplace(_ displayedQuality: Self?) -> Bool {
        guard let displayedQuality else { return true }
        return rawValue >= displayedQuality.rawValue
    }
}

nonisolated enum CollectionBrowseImageWindowSelection: Hashable, Sendable {
    case requestedQuality
    case locallyAvailableLarge
    case omitSatisfiedToken

    static func resolve(
        requiredQuality: CollectionBrowseImageQuality,
        isDisplayingRegularThumbnail: Bool,
        isDisplayingLargeImage: Bool,
        largeImageIsLocallyAvailable: Bool
    ) -> Self {
        if requiredQuality == .smallThumbnail,
           isDisplayingRegularThumbnail {
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

/// The 5-3-1 column ladder of the Photos app. Odd counts keep a center
/// column, so zoom transitions reveal content symmetrically at both sides
/// instead of forcing one-sided column shifts.
nonisolated enum MobileCollectionBrowserGridMode: Int, CaseIterable, Hashable, Sendable {
    case large = 1
    case threeColumns = 3
    case fiveColumns = 5

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
        }
    }

    var allowsLocalLargeImageUpgrade: Bool {
        self != .fiveColumns
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
