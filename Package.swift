// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NftFolderSyncCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "NftFolderSyncCore",
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
                "Services/DownloadableMediaCache.swift",
                "Services/PlayerTokenPrewarmer.swift",
                "Services/PlayerWebContentLoadCoordinator.swift",
                "Services/PonchoDrifellaAssetCache.swift"
            ],
            sources: [
                "Models/PlayerSyncTypes.swift",
                "Models/PlayerViewingProgressStore.swift",
                "Models/PlayerBookmarksStore.swift",
                "Models/Strings.swift",
                "Services/PlayerICloudSync.swift"
            ]
        ),
        .testTarget(
            name: "NftFolderSyncCoreTests",
            dependencies: ["NftFolderSyncCore"],
            path: "Tests/NftFolderSyncCoreTests"
        )
    ]
)
