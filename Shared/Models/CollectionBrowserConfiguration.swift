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

enum MobileCollectionBrowserGridMode: Int, CaseIterable, Hashable {
    case large = 1
    case twoColumns = 2
    case threeColumns = 3
    case fourColumns = 4

    var columnCount: Int {
        rawValue
    }

    var requiresLargeImage: Bool {
        self == .large
    }

    func requiredImageQuality(
        defaultGridMode: MobileCollectionBrowserGridMode
    ) -> CollectionBrowseImageQuality {
        if requiresLargeImage
            || self == .twoColumns && defaultGridMode == .threeColumns {
            return .large
        }
        return .thumbnail
    }
}

enum MobileCollectionBrowserGridModePreferences {
    private static let userDefaultsKeyPrefix = "iosCollectionBrowserColumnCountOverride."

    static func gridMode(
        userDefaults: UserDefaults,
        internalSlug: String,
        defaultGridMode: MobileCollectionBrowserGridMode
    ) -> MobileCollectionBrowserGridMode {
        guard let key = userDefaultsKey(internalSlug: internalSlug),
              let storedColumnCount = userDefaults.object(forKey: key) as? Int,
              let storedGridMode = MobileCollectionBrowserGridMode(
                rawValue: storedColumnCount
              ) else {
            return defaultGridMode
        }
        return storedGridMode
    }

    static func save(
        gridMode: MobileCollectionBrowserGridMode,
        userDefaults: UserDefaults,
        internalSlug: String
    ) {
        guard let key = userDefaultsKey(internalSlug: internalSlug) else { return }
        userDefaults.set(gridMode.rawValue, forKey: key)
    }

    static func userDefaultsKey(internalSlug: String) -> String? {
        guard !internalSlug.isEmpty else { return nil }
        return userDefaultsKeyPrefix + internalSlug
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
