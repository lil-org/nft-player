// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NftPlayerSyncCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "NftPlayerSyncCore",
            path: "Shared",
            exclude: [
                "Assets",
                "Extensions/CollectionsGridScrollViewHelpers.swift",
                "Extensions/Links.swift",
                "Extensions/Notification.swift",
                "Models/Chain.swift",
                "Models/CardNft2CardMetadata.swift",
                "Models/CollectionBrowseThumbnails.swift",
                "Models/CollectionCatalog.swift",
                "Models/CollectionsGridScrollMemory.swift",
                "Models/Consts.swift",
                "Models/Images.swift",
                "Models/NftGallery.swift",
                "Models/NativeMetalCardMetadata.swift",
                "Models/PonchoDrifellaCardMetadata.swift",
                "Models/PlayerCollectionBrowserSupport.swift",
                "Models/PlayerWidgetTokenInsertion.swift",
                "Services/DownloadableMediaCache.swift",
                "Services/DownloadableMediaCacheSupport.swift",
                "Services/DownloadableMediaDownloader.swift",
                "Services/DownloadableMediaImageDecoder.swift",
                "Services/DownloadableMediaMemoryCache.swift",
                "Services/DownloadableMediaDiskStore.swift",
                "Services/CardNft2AssetCache.swift",
                "Services/NativeMetalCardAssetCache.swift",
                "Services/NativeMetalCardRendererCore.swift",
                "Services/PlayerTokenPrewarmer.swift",
                "Services/PlayerWebContentLoadCoordinator.swift",
                "Services/PonchoDrifellaAssetCache.swift"
            ],
            sources: [
                "Models/CollectionBrowserConfiguration.swift",
                "Models/MobilePlayerBrowserLayout.swift",
                "Models/PlayerBrowserGridCrossfade.swift",
                "Models/PlayerBrowserGridSourceCoverage.swift",
                "Models/PlayerBrowserGridInteractionCoordinator.swift",
                "Models/PlayerBrowserGridPinchPolicy.swift",
                "Models/PlayerCardMinimizePinchPolicy.swift",
                "Models/PlayerCollectionScrollPolicy.swift",
                "Models/PlayerSyncTypes.swift",
                "Models/PlayerViewingProgressStore.swift",
                "Models/PlayerViewingSessionTracker.swift",
                "Models/PlayerBookmarksStore.swift",
                "Models/Strings.swift",
                "Models/WidgetDeepLink.swift",
                "Services/PlayerICloudSync.swift"
            ],
            swiftSettings: [
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "NftPlayerSyncCoreTests",
            dependencies: ["NftPlayerSyncCore"],
            path: "Tests/NftPlayerSyncCoreTests",
            swiftSettings: [
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
