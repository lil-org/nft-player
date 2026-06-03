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
                "Extensions/Links.swift",
                "Extensions/Notification.swift",
                "Models/Chain.swift",
                "Models/CollectionCatalog.swift",
                "Models/Consts.swift",
                "Models/Images.swift",
                "Models/NftGallery.swift",
                "Models/PonchoDrifellaCardMetadata.swift",
                "Models/PlayerWidgetTokenInsertion.swift",
                "Services/DownloadableMediaCache.swift",
                "Services/PlayerTokenPrewarmer.swift",
                "Services/PlayerWebContentLoadCoordinator.swift",
                "Services/PonchoDrifellaAssetCache.swift"
            ],
            sources: [
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
