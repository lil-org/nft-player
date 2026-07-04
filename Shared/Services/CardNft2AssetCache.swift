// ∅ 2026 lil org

import Foundation
import os

private let cardNft2AssetCacheLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "CardNft2Metal"
)

final class CardNft2AssetCache {

    static let shared = CardNft2AssetCache()
    private static let maxPrefetchFilesPerRequest = 6
    private static let maxCacheBytes: Int64 = 512 * 1024 * 1024
    private static let faceAssetsBaseURL = URL(string: "https://cdn.lil.org/nft/card_nft_2/fronts_1400")!
    private static let foilAssetsBaseURL = URL(string: "https://cdn.lil.org/nft/card_nft_2/foils")!
    private static let textureMaskAssetsBaseURL = URL(string: "https://cdn.lil.org/nft/card_nft_2/masks")!
    private static let sharedEffectAssetsBaseURL = URL(string: "https://cdn.lil.org/nft/poncho_drifella/misc")!

    private let core: NativeMetalCardAssetCache

    private init() {
        let fileManager = FileManager.default
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let rootURL = cachesURL.appendingPathComponent("CardNft2Assets", isDirectory: true)
        core = NativeMetalCardAssetCache(
            configuration: NativeMetalCardAssetCacheConfiguration(
                renderKind: .cardNft2,
                rootURL: rootURL,
                logger: cardNft2AssetCacheLogger,
                logName: "Card NFT 2",
                maxCacheBytes: Self.maxCacheBytes,
                markCachedFilesAsUsed: true,
                paths: Self.assetPaths(for:),
                remoteURL: { asset in
                    Self.remoteURL(
                        for: asset,
                        faceAssetsBaseURL: Self.faceAssetsBaseURL,
                        foilAssetsBaseURL: Self.foilAssetsBaseURL,
                        textureMaskAssetsBaseURL: Self.textureMaskAssetsBaseURL,
                        sharedEffectAssetsBaseURL: Self.sharedEffectAssetsBaseURL
                    )
                }
            ),
            queueLabel: "org.lil.nft-player.card-nft-2-cache"
        )
    }

    func loadEffectAssets(for tokenID: Int, completion: @escaping (NativeMetalCardAssetURLs?) -> Void) {
        core.loadEffectAssets(for: tokenID, completion: completion)
    }

    func loadFace(for tokenID: Int, completion: @escaping (URL?) -> Void) {
        core.loadFace(for: tokenID, completion: completion)
    }

    func prefetch(around tokenID: Int, radius: Int) {
        guard radius > 0 else { return }

        let boundedRadius = min(radius, CardNft2CardMetadata.tokenCount)
        let clampedTokenID = min(max(tokenID, 1), CardNft2CardMetadata.tokenCount)
        let tokenIDs = (1...boundedRadius).flatMap { distance in
            [clampedTokenID - distance, clampedTokenID + distance]
        }.filter { tokenID in
            tokenID >= 1 && tokenID <= CardNft2CardMetadata.tokenCount
        }

        let prefetchAssets = tokenIDs.flatMap(displayAssets(for:))

        var seenPrefetchPaths = Set<String>()
        var cappedPrefetchAssets = [NativeMetalCardAssetPath]()
        cappedPrefetchAssets.reserveCapacity(Self.maxPrefetchFilesPerRequest)
        for asset in prefetchAssets {
            guard seenPrefetchPaths.insert(asset.relativePath).inserted else { continue }
            cappedPrefetchAssets.append(asset)
            if cappedPrefetchAssets.count >= Self.maxPrefetchFilesPerRequest {
                break
            }
        }
        let cappedPrefetchPaths = cappedPrefetchAssets.map(\.relativePath)
        let currentTokenPaths = displayAssets(for: clampedTokenID).map(\.relativePath)
        core.cancelStalePrefetchDownloads(keeping: Set(cappedPrefetchPaths + currentTokenPaths))
        core.cache(
            assets: cappedPrefetchAssets,
            taskPriority: URLSessionTask.lowPriority,
            isPrefetch: true
        )
    }

    func invalidate(tokenID: Int) {
        core.invalidateTokenSpecificAssets(for: tokenID)
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

    private func displayAssets(for tokenID: Int) -> [NativeMetalCardAssetPath] {
        let metadata = CardNft2CardMetadata.metadata(for: tokenID)
        return metadata.requiresEffectAssets
            ? core.tokenSpecificAssets(for: tokenID)
            : [core.faceAsset(for: tokenID)]
    }

    private static func assetPaths(for tokenID: Int) -> NativeMetalCardAssetPaths {
        let formattedTokenID = String(format: "%04d", tokenID)
        return NativeMetalCardAssetPaths(
            face: "img/\(formattedTokenID).webp",
            foil: "foils/\(formattedTokenID).webp",
            textureMask: "textures/\(formattedTokenID).webp",
            grain: "img/grain.webp",
            glitter: "img/glitter.png"
        )
    }

    private static func remoteURL(
        for asset: NativeMetalCardAssetPath,
        faceAssetsBaseURL: URL,
        foilAssetsBaseURL: URL,
        textureMaskAssetsBaseURL: URL,
        sharedEffectAssetsBaseURL: URL
    ) -> URL? {
        let fileName = URL(fileURLWithPath: asset.relativePath).lastPathComponent
        switch asset.role {
        case .face:
            return faceAssetsBaseURL.appendingPathComponent(fileName)
        case .foil:
            return foilAssetsBaseURL.appendingPathComponent(fileName)
        case .textureMask:
            return textureMaskAssetsBaseURL.appendingPathComponent(fileName)
        case .grain, .glitter:
            return sharedEffectAssetsBaseURL.appendingPathComponent(fileName)
        }
    }
}
