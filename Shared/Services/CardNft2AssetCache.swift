// ∅ 2026 lil org

import Foundation
import os

nonisolated final class CardNft2AssetCache: Sendable {

    static let shared = CardNft2AssetCache()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
        category: "CardNft2Metal"
    )
    private static let maxPrefetchFilesPerRequest = 6
    private static let maxCacheBytes: Int64 = 512 * 1024 * 1024
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
                logger: Self.logger,
                logName: "Card NFT 2",
                maxCacheBytes: Self.maxCacheBytes,
                markCachedFilesAsUsed: true,
                paths: Self.assetPaths(for:),
                remoteURL: { asset in
                    Self.remoteURL(
                        for: asset,
                        foilAssetsBaseURL: Self.foilAssetsBaseURL,
                        textureMaskAssetsBaseURL: Self.textureMaskAssetsBaseURL,
                        sharedEffectAssetsBaseURL: Self.sharedEffectAssetsBaseURL
                    )
                }
            )
        )
    }

    func loadEffectAssets(for tokenID: Int) async -> NativeMetalCardAssetURLs? {
        await core.loadEffectAssets(for: tokenID)
    }

    func loadFace(for tokenID: Int) async -> NativeMetalCardAssetURL? {
        await core.loadFace(for: tokenID)
    }

    func cacheFace(for tokenID: Int, from sourceURL: URL) async -> Bool {
        await core.cacheFace(for: tokenID, from: sourceURL)
    }

    func prefetch(around tokenID: Int, radius: Int) async {
        guard radius > 0, !Task.isCancelled else { return }

        let boundedRadius = min(radius, CardNft2CardMetadata.tokenCount)
        let clampedTokenID = min(max(tokenID, 1), CardNft2CardMetadata.tokenCount)
        let tokenIDs = (1...boundedRadius).flatMap { distance in
            [clampedTokenID - distance, clampedTokenID + distance]
        }.filter { tokenID in
            tokenID >= 1 && tokenID <= CardNft2CardMetadata.tokenCount
        }

        var prefetchAssets = [NativeMetalCardAssetPath]()
        for tokenID in tokenIDs {
            guard !Task.isCancelled else { return }
            prefetchAssets.append(contentsOf: await displayAssets(for: tokenID))
        }

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
        guard !Task.isCancelled else { return }
        let cappedPrefetchPaths = cappedPrefetchAssets.map(\.relativePath)
        let currentTokenPaths = await displayAssets(for: clampedTokenID).map(\.relativePath)
        guard !Task.isCancelled else { return }
        await core.cancelStalePrefetchDownloads(keeping: Set(cappedPrefetchPaths + currentTokenPaths))
        guard !Task.isCancelled else { return }
        await core.cache(
            assets: cappedPrefetchAssets,
            taskPriority: URLSessionTask.lowPriority,
            isPrefetch: true
        )
    }

    func invalidate(_ assetURL: NativeMetalCardAssetURL) async {
        await core.invalidate(assetURL)
    }

    func cancelPrefetchDownloads() async {
        await core.cancelPrefetchDownloads()
    }

    private func displayAssets(for tokenID: Int) async -> [NativeMetalCardAssetPath] {
        let metadata = CardNft2CardMetadata.metadata(for: tokenID)
        return metadata.requiresEffectAssets
            ? await core.tokenSpecificAssets(for: tokenID)
            : [await core.faceAsset(for: tokenID)]
    }

    private static func assetPaths(for tokenID: Int) -> NativeMetalCardAssetPaths {
        let formattedTokenID = String(format: "%04d", tokenID)
        return NativeMetalCardAssetPaths(
            face: NativeMetalCardRenderKind.cardNft2.faceImageRelativePath(tokenID: tokenID),
            foil: "foils/\(formattedTokenID).webp",
            textureMask: "textures/\(formattedTokenID).webp",
            grain: "img/grain.webp",
            glitter: "img/glitter.png"
        )
    }

    private static func remoteURL(
        for asset: NativeMetalCardAssetPath,
        foilAssetsBaseURL: URL,
        textureMaskAssetsBaseURL: URL,
        sharedEffectAssetsBaseURL: URL
    ) -> URL? {
        let fileName = URL(fileURLWithPath: asset.relativePath).lastPathComponent
        switch asset.role {
        case .face:
            return NativeMetalCardRenderKind.cardNft2.staticImageURL(fileName: fileName)
        case .foil:
            return foilAssetsBaseURL.appendingPathComponent(fileName)
        case .textureMask:
            return textureMaskAssetsBaseURL.appendingPathComponent(fileName)
        case .grain, .glitter:
            return sharedEffectAssetsBaseURL.appendingPathComponent(fileName)
        }
    }
}
