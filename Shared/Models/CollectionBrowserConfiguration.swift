// ∅ 2026 lil org

import Foundation

enum CollectionBrowseImageQuality: Int, Hashable {
    case thumbnail
    case large

    func canReplace(_ displayedQuality: Self?) -> Bool {
        guard let displayedQuality else { return true }
        return rawValue >= displayedQuality.rawValue
    }
}

enum CollectionBrowseImageWindowSelection: Hashable {
    case requestedQuality
    case locallyAvailableLarge
    case omitSatisfiedToken

    static func resolve(
        requiredQuality: CollectionBrowseImageQuality,
        isDisplayingLargeImage: Bool,
        largeImageIsLocallyAvailable: Bool
    ) -> Self {
        guard requiredQuality == .thumbnail,
              isDisplayingLargeImage else {
            return .requestedQuality
        }
        return largeImageIsLocallyAvailable
            ? .locallyAvailableLarge
            : .omitSatisfiedToken
    }
}

enum CollectionBrowseImageLoadPolicy {
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
        requiredQuality == .thumbnail
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

enum CollectionBrowseSnapshotUpdatePolicy {
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
enum MobileCollectionBrowserGridMode: Int, CaseIterable, Hashable {
    case large = 1
    case threeColumns = 3
    case fiveColumns = 5

    static let defaultMode = MobileCollectionBrowserGridMode.threeColumns

    var columnCount: Int {
        rawValue
    }

    var requiredImageQuality: CollectionBrowseImageQuality {
        self == .large ? .large : .thumbnail
    }
}

enum CollectionBrowseImageURLMapping {
    static func midURL(for thumbnailURL: URL) -> URL? {
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

        return thumbnailDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("mid", isDirectory: true)
            .appendingPathComponent(
                thumbnailURL.lastPathComponent,
                isDirectory: false
            )
    }
}
