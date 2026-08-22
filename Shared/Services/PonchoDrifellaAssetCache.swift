// ∅ 2026 lil org

import Foundation
import os

nonisolated final class PonchoDrifellaAssetCache: Sendable {

    static let shared = PonchoDrifellaAssetCache()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
        category: "PonchoDrifellaMetal"
    )
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
                logger: Self.logger,
                logName: "Poncho",
                maxCacheBytes: nil,
                markCachedFilesAsUsed: false,
                paths: Self.assetPaths(for:),
                remoteURL: { asset in
                    Self.remoteURL(for: asset, baseURL: Self.baseURL)
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

        let boundedRadius = min(radius, PonchoDrifellaCardMetadata.tokenCount)
        let clampedTokenID = min(max(tokenID, 1), PonchoDrifellaCardMetadata.tokenCount)
        let lowerBound = max(1, clampedTokenID - boundedRadius)
        let upperBound = min(PonchoDrifellaCardMetadata.tokenCount, clampedTokenID + boundedRadius)
        guard lowerBound <= upperBound else { return }
        var prefetchAssets = [NativeMetalCardAssetPath]()
        for nearbyTokenID in lowerBound...upperBound where nearbyTokenID != clampedTokenID {
            guard !Task.isCancelled else { return }
            prefetchAssets.append(contentsOf: await core.tokenSpecificAssets(for: nearbyTokenID))
        }
        guard !Task.isCancelled else { return }
        let currentTokenPaths = await core.tokenSpecificPaths(for: clampedTokenID)
        guard !Task.isCancelled else { return }
        let pathsToKeep = Set(prefetchAssets.map(\.relativePath) + currentTokenPaths)
        await core.cancelStalePrefetchDownloads(keeping: pathsToKeep)
        guard !Task.isCancelled else { return }
        await core.cache(
            assets: prefetchAssets,
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
