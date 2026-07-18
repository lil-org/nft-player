// ∅ 2026 lil org

import Foundation
import os

private let ponchoDrifellaAssetCacheLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "PonchoDrifellaMetal"
)

final class PonchoDrifellaAssetCache {

    static let shared = PonchoDrifellaAssetCache()
    private static let baseURL = URL(string: "https://cdn.lil.org/nft/poncho_drifella")!

    private let core: NativeMetalCardAssetCache

    private init() {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let rootURL = applicationSupportURL.appendingPathComponent("PonchoDrifellaAssets", isDirectory: true)
        core = NativeMetalCardAssetCache(
            configuration: NativeMetalCardAssetCacheConfiguration(
                renderKind: .ponchoDrifella,
                rootURL: rootURL,
                logger: ponchoDrifellaAssetCacheLogger,
                logName: "Poncho",
                maxCacheBytes: nil,
                markCachedFilesAsUsed: false,
                paths: Self.assetPaths(for:),
                remoteURL: { asset in
                    Self.remoteURL(for: asset, baseURL: Self.baseURL)
                }
            ),
            queueLabel: "org.lil.nft-player.poncho-cache"
        )
    }

    func loadEffectAssets(for tokenID: Int, completion: @escaping (NativeMetalCardAssetURLs?) -> Void) {
        core.loadEffectAssets(for: tokenID, completion: completion)
    }

    func loadFace(for tokenID: Int, completion: @escaping (URL?) -> Void) {
        core.loadFace(for: tokenID, completion: completion)
    }

    func cacheFace(
        for tokenID: Int,
        from sourceURL: URL,
        completion: ((Bool) -> Void)? = nil
    ) {
        core.cacheFace(for: tokenID, from: sourceURL, completion: completion)
    }

    func prefetch(around tokenID: Int, radius: Int) {
        guard radius > 0 else { return }

        let boundedRadius = min(radius, PonchoDrifellaCardMetadata.tokenCount)
        let clampedTokenID = min(max(tokenID, 1), PonchoDrifellaCardMetadata.tokenCount)
        let lowerBound = max(1, clampedTokenID - boundedRadius)
        let upperBound = min(PonchoDrifellaCardMetadata.tokenCount, clampedTokenID + boundedRadius)
        guard lowerBound <= upperBound else { return }
        let prefetchAssets = (lowerBound...upperBound)
            .filter { $0 != clampedTokenID }
            .flatMap { core.tokenSpecificAssets(for: $0) }
        let pathsToKeep = Set(prefetchAssets.map(\.relativePath) + core.tokenSpecificPaths(for: clampedTokenID))
        core.cancelStalePrefetchDownloads(keeping: pathsToKeep)
        core.cache(
            assets: prefetchAssets,
            taskPriority: URLSessionTask.lowPriority,
            isPrefetch: true
        )
    }

    func invalidateFaceAsset(for tokenID: Int) {
        core.invalidateFaceAsset(for: tokenID)
    }

    func invalidateEffectAssets(for tokenID: Int) {
        core.invalidateEffectAssets(for: tokenID)
    }

    func invalidate(_ asset: NativeMetalCardAssetPath) {
        core.invalidate(asset)
    }

    func cancelPrefetchDownloads() {
        core.cancelPrefetchDownloads()
    }

    private static func assetPaths(for tokenID: Int) -> NativeMetalCardAssetPaths {
        NativeMetalCardAssetPaths(
            face: NativeMetalCardRenderKind.ponchoDrifella.faceImageRelativePath(tokenID: tokenID),
            foil: "foils/\(tokenID).webp",
            textureMask: "textures/\(tokenID).webp",
            grain: "img/grain.webp",
            glitter: "img/glitter.png"
        )
    }

    private static func remoteURL(for asset: NativeMetalCardAssetPath, baseURL: URL) -> URL? {
        let fileName = URL(fileURLWithPath: asset.relativePath).lastPathComponent
        guard !fileName.isEmpty else { return nil }

        let directory: String
        switch asset.role {
        case .face:
            return NativeMetalCardRenderKind.ponchoDrifella.staticImageURL(fileName: fileName)
        case .foil:
            directory = "foils"
        case .textureMask:
            directory = "textures"
        case .grain, .glitter:
            directory = "misc"
        }

        return baseURL.appendingPathComponent(directory).appendingPathComponent(fileName)
    }
}
