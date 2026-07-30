// swift-tools-version: 5.9

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
                "Services/CardNft2AssetCache.swift",
                "Services/NativeMetalCardAssetCache.swift",
                "Services/NativeMetalCardRendererCore.swift",
                "Services/PlayerTokenPrewarmer.swift",
                "Services/PlayerWebContentLoadCoordinator.swift",
                "Services/PonchoDrifellaAssetCache.swift"
            ],
            sources: [
                "Models/MobilePlayerBrowserLayout.swift",
                "Models/PlayerCardMinimizePinchPolicy.swift",
                "Models/PlayerCollectionScrollPolicy.swift",
                "Models/PlayerSyncTypes.swift",
                "Models/PlayerViewingProgressStore.swift",
                "Models/PlayerViewingSessionTracker.swift",
                "Models/PlayerBookmarksStore.swift",
                "Models/Strings.swift",
                "Models/WidgetDeepLink.swift",
                "Services/PlayerICloudSync.swift"
            ]
        ),
        .testTarget(
            name: "NftPlayerSyncCoreTests",
            dependencies: ["NftPlayerSyncCore"],
            path: "Tests/NftPlayerSyncCoreTests"
        )
    ]
)
