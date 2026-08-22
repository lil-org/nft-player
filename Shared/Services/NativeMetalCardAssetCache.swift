// ∅ 2026 lil org

import CoreGraphics
import Foundation
import os

nonisolated struct NativeMetalCardAssetURLs: Sendable {
    let renderKind: NativeMetalCardRenderKind
    let tokenID: Int
    let foil: NativeMetalCardAssetURL
    let textureMask: NativeMetalCardAssetURL
    let grain: NativeMetalCardAssetURL
    let glitter: NativeMetalCardAssetURL
}

nonisolated struct NativeMetalCardAssetURL: Sendable {
    let asset: NativeMetalCardAssetPath
    let url: URL
    let generationID: UUID
}

nonisolated enum NativeMetalCardAssetRole: Hashable, Sendable {
    case face
    case foil
    case textureMask
    case grain
    case glitter
}

nonisolated struct NativeMetalCardAssetPath: Hashable, Sendable {
    let role: NativeMetalCardAssetRole
    let relativePath: String
}

nonisolated struct NativeMetalCardAssetPaths: Sendable {
    let face: NativeMetalCardAssetPath
    let foil: NativeMetalCardAssetPath
    let textureMask: NativeMetalCardAssetPath
    let grain: NativeMetalCardAssetPath
    let glitter: NativeMetalCardAssetPath

    init(face: String, foil: String, textureMask: String, grain: String, glitter: String) {
        self.face = NativeMetalCardAssetPath(role: .face, relativePath: face)
        self.foil = NativeMetalCardAssetPath(role: .foil, relativePath: foil)
        self.textureMask = NativeMetalCardAssetPath(role: .textureMask, relativePath: textureMask)
        self.grain = NativeMetalCardAssetPath(role: .grain, relativePath: grain)
        self.glitter = NativeMetalCardAssetPath(role: .glitter, relativePath: glitter)
    }

    var tokenSpecificAssets: [NativeMetalCardAssetPath] {
        [face] + tokenSpecificEffectAssets
    }

    var tokenSpecificEffectAssets: [NativeMetalCardAssetPath] {
        [foil, textureMask]
    }

    var sharedEffectAssets: [NativeMetalCardAssetPath] {
        [grain, glitter]
    }

    var effectAssets: [NativeMetalCardAssetPath] {
        tokenSpecificEffectAssets + sharedEffectAssets
    }
}

nonisolated struct NativeMetalCardAssetCacheConfiguration: Sendable {
    let renderKind: NativeMetalCardRenderKind
    let rootURL: URL
    let logger: Logger
    let logName: String
    let maxCacheBytes: Int64?
    let markCachedFilesAsUsed: Bool
    let paths: @Sendable (Int) -> NativeMetalCardAssetPaths
    let remoteURL: @Sendable (NativeMetalCardAssetPath) -> URL?
}

private nonisolated struct NativeMetalCardFileEnsureResult: Sendable {
    let didSucceed: Bool
    let downloadedByteCount: Int64
    let cachedFileUse: NativeMetalCardCachedFileUse?
}

private nonisolated struct NativeMetalCardCachedFileUse: Sendable {
    let url: URL
    let relativePath: String
}

private nonisolated struct NativeMetalCardDownloadTransfer: Sendable {
    let temporaryURL: URL?
    let statusCode: Int?
    let errorDescription: String?
}

private nonisolated final class NativeMetalCardDownloadOperation: @unchecked Sendable {
    private let task: URLSessionDownloadTask
    private let resultTask: Task<NativeMetalCardDownloadTransfer, Never>

    init(
        remoteURL: URL,
        downloadID: UUID,
        relativePath: String,
        priority: Float,
        logger: Logger
    ) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: NativeMetalCardDownloadTransfer.self
        )
        resultTask = Task {
            for await transfer in stream {
                return transfer
            }
            return NativeMetalCardDownloadTransfer(
                temporaryURL: nil,
                statusCode: nil,
                errorDescription: "Download ended without a result"
            )
        }

        let handoffDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeMetalCardDownloads", isDirectory: true)
        let handoffURL = handoffDirectory
            .appendingPathComponent(downloadID.uuidString)
            .appendingPathExtension(
                URL(fileURLWithPath: relativePath).pathExtension
            )
        task = URLSession.shared.downloadTask(with: remoteURL) {
            temporaryURL,
            response,
            error in
            let persistedURL = temporaryURL.flatMap { temporaryURL -> URL? in
                do {
                    try FileManager.default.createDirectory(
                        at: handoffDirectory,
                        withIntermediateDirectories: true
                    )
                    try? FileManager.default.removeItem(at: handoffURL)
                    try FileManager.default.moveItem(
                        at: temporaryURL,
                        to: handoffURL
                    )
                    return handoffURL
                } catch {
                    logger.error(
                        "Native card download handoff failed for \(relativePath, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                    return nil
                }
            }
            continuation.yield(NativeMetalCardDownloadTransfer(
                temporaryURL: persistedURL,
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                errorDescription: error.map(String.init(describing:))
                    ?? (temporaryURL != nil && persistedURL == nil
                        ? "Unable to persist temporary download"
                        : nil)
            ))
            continuation.finish()
        }
        task.priority = priority
        task.resume()
    }

    func value() async -> NativeMetalCardDownloadTransfer {
        await resultTask.value
    }

    func promote(to priority: Float) {
        task.priority = max(task.priority, priority)
    }

    func cancel() {
        task.cancel()
    }
}

private nonisolated struct PendingNativeMetalCardDownload: Sendable {
    let id: UUID
    let operation: NativeMetalCardDownloadOperation
    var isPrefetchOnly: Bool
}

private nonisolated struct NativeMetalCardCachedFile: Sendable {
    let url: URL
    let relativePath: String
    let byteCount: Int64
    let lastUsed: Date
}

private nonisolated enum NativeMetalCardStaticImageAsset {
    static let size = CGSize(width: 1000, height: 1400)
    static let fileExtension = "webp"

    private static let cardNft2BaseURL = URL(string: "https://cdn.lil.org/nft/card_nft_2/fronts_1400")!
    private static let ponchoDrifellaBaseURL = URL(string: "https://cdn.lil.org/nft/poncho_drifella/fronts")!

    static func baseURL(for renderKind: NativeMetalCardRenderKind) -> URL {
        switch renderKind {
        case .cardNft2:
            return cardNft2BaseURL
        case .ponchoDrifella:
            return ponchoDrifellaBaseURL
        }
    }
}

actor NativeMetalCardAssetCache {

    private static let cachedFileUseTouchInterval: TimeInterval = 5 * 60

    private let fileManager = FileManager.default
    private let configuration: NativeMetalCardAssetCacheConfiguration
    private var pendingDownloads = [String: PendingNativeMetalCardDownload]()
    private var downloadedBytesSinceLastTrimScan: Int64 = 0
    private var hasCompletedCacheTrimScan = false
    private var cachedFileUseTouchDates = [String: Date]()
    private var fileGenerationIDs = [String: UUID]()

    init(configuration: NativeMetalCardAssetCacheConfiguration) {
        self.configuration = configuration

        try? fileManager.createDirectory(at: configuration.rootURL, withIntermediateDirectories: true)
        var resourceURL = configuration.rootURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(resourceValues)
    }

    func loadEffectAssets(for tokenID: Int) async -> NativeMetalCardAssetURLs? {
        let assets = effectAssets(for: tokenID)
        guard await ensureFiles(assets),
              !Task.isCancelled,
              assets.allSatisfy({ hasCachedFile(at: localURL(for: $0.relativePath)) }) else {
            return nil
        }
        return urls(for: tokenID)
    }

    func loadFace(for tokenID: Int) async -> NativeMetalCardAssetURL? {
        let faceAsset = assetPaths(for: tokenID).face
        guard await ensureFiles([faceAsset]),
              !Task.isCancelled,
              hasCachedFile(at: localURL(for: faceAsset.relativePath)) else {
            return nil
        }
        return assetURL(for: faceAsset)
    }

    func cacheFace(for tokenID: Int, from sourceURL: URL) -> Bool {
        importCachedFile(faceAsset(for: tokenID), from: sourceURL)
    }

    @discardableResult
    func cache(
        assets: [NativeMetalCardAssetPath],
        taskPriority: Float = URLSessionTask.defaultPriority,
        isPrefetch: Bool = false
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        return await ensureFiles(
            assets,
            taskPriority: taskPriority,
            isPrefetch: isPrefetch
        )
    }

    func cancelStalePrefetchDownloads(keeping relativePathsToKeep: Set<String>) {
        let stalePrefetchDownloads = pendingDownloads.filter { relativePath, pendingDownload in
            pendingDownload.isPrefetchOnly && !relativePathsToKeep.contains(relativePath)
        }

        for (relativePath, pendingDownload) in stalePrefetchDownloads {
            pendingDownloads.removeValue(forKey: relativePath)
            pendingDownload.operation.cancel()
        }
    }

    func cancelPrefetchDownloads() {
        cancelStalePrefetchDownloads(keeping: [])
    }

    func invalidate(_ assetURL: NativeMetalCardAssetURL) {
        let relativePath = assetURL.asset.relativePath
        guard fileGenerationIDs[relativePath] == assetURL.generationID else { return }
        fileGenerationIDs[relativePath] = nil
        cachedFileUseTouchDates[relativePath] = nil
        try? fileManager.removeItem(at: localURL(for: relativePath))
    }

    func tokenSpecificAssets(for tokenID: Int) -> [NativeMetalCardAssetPath] {
        assetPaths(for: tokenID).tokenSpecificAssets
    }

    func tokenSpecificPaths(for tokenID: Int) -> [String] {
        tokenSpecificAssets(for: tokenID).map(\.relativePath)
    }

    func faceAsset(for tokenID: Int) -> NativeMetalCardAssetPath {
        assetPaths(for: tokenID).face
    }

    private func ensureFiles(
        _ assets: [NativeMetalCardAssetPath],
        taskPriority: Float = URLSessionTask.defaultPriority,
        isPrefetch: Bool = false
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let results = await withTaskGroup(
            of: NativeMetalCardFileEnsureResult.self,
            returning: [NativeMetalCardFileEnsureResult].self
        ) { group in
            for asset in assets {
                group.addTask {
                    await self.ensureFile(asset, taskPriority: taskPriority, isPrefetch: isPrefetch)
                }
            }

            var results = [NativeMetalCardFileEnsureResult]()
            results.reserveCapacity(assets.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        let cachedFileUses = results.compactMap(\.cachedFileUse)
        markCachedFilesAsUsed(cachedFileUses)

        let downloadedByteCount = results.reduce(Int64(0)) { $0 + $1.downloadedByteCount }
        if downloadedByteCount > 0 {
            let protectedRelativePaths = Set(assets.map(\.relativePath))
            Task {
                trimCacheIfNeeded(
                    protecting: protectedRelativePaths,
                    downloadedByteCount: downloadedByteCount
                )
            }
        }
        return results.allSatisfy(\.didSucceed)
    }

    private func ensureFile(
        _ asset: NativeMetalCardAssetPath,
        taskPriority: Float,
        isPrefetch: Bool
    ) async -> NativeMetalCardFileEnsureResult {
        guard !Task.isCancelled else { return failedEnsureResult }
        let relativePath = asset.relativePath
        let localURL = localURL(for: relativePath)
        if hasCachedFile(at: localURL) {
            return cachedResult(localURL: localURL, relativePath: relativePath, isPrefetch: isPrefetch)
        }

        let pendingDownload: PendingNativeMetalCardDownload
        if var existingDownload = pendingDownloads[relativePath] {
            existingDownload.isPrefetchOnly = existingDownload.isPrefetchOnly && isPrefetch
            existingDownload.operation.promote(to: taskPriority)
            pendingDownloads[relativePath] = existingDownload
            pendingDownload = existingDownload
        } else {
            guard let remoteURL = configuration.remoteURL(asset) else {
                configuration.logger.error(
                    "Unknown \(self.configuration.logName, privacy: .public) asset path: \(relativePath, privacy: .public)"
                )
                return failedEnsureResult
            }

            let downloadID = UUID()
            let downloadOperation = makeDownloadOperation(
                remoteURL: remoteURL,
                downloadID: downloadID,
                relativePath: relativePath,
                priority: taskPriority
            )
            let newDownload = PendingNativeMetalCardDownload(
                id: downloadID,
                operation: downloadOperation,
                isPrefetchOnly: isPrefetch
            )
            pendingDownloads[relativePath] = newDownload
            pendingDownload = newDownload
        }

        let transfer = await pendingDownload.operation.value()
        guard pendingDownloads[relativePath]?.id == pendingDownload.id else {
            if let temporaryURL = transfer.temporaryURL {
                try? fileManager.removeItem(at: temporaryURL)
            }
            if hasCachedFile(at: localURL) {
                return cachedResult(localURL: localURL, relativePath: relativePath, isPrefetch: isPrefetch)
            }
            return failedEnsureResult
        }

        pendingDownloads.removeValue(forKey: relativePath)
        guard let downloadedByteCount = storeDownloadedFile(
            transfer,
            remoteURL: configuration.remoteURL(asset),
            localURL: localURL,
            relativePath: relativePath
        ) else {
            return failedEnsureResult
        }

        return NativeMetalCardFileEnsureResult(
            didSucceed: true,
            downloadedByteCount: downloadedByteCount,
            cachedFileUse: configuration.markCachedFilesAsUsed && !isPrefetch
                ? NativeMetalCardCachedFileUse(url: localURL, relativePath: relativePath)
                : nil
        )
    }

    private var failedEnsureResult: NativeMetalCardFileEnsureResult {
        NativeMetalCardFileEnsureResult(
            didSucceed: false,
            downloadedByteCount: 0,
            cachedFileUse: nil
        )
    }

    private func cachedResult(
        localURL: URL,
        relativePath: String,
        isPrefetch: Bool
    ) -> NativeMetalCardFileEnsureResult {
        NativeMetalCardFileEnsureResult(
            didSucceed: true,
            downloadedByteCount: 0,
            cachedFileUse: configuration.markCachedFilesAsUsed && !isPrefetch
                ? NativeMetalCardCachedFileUse(url: localURL, relativePath: relativePath)
                : nil
        )
    }

    private func makeDownloadOperation(
        remoteURL: URL,
        downloadID: UUID,
        relativePath: String,
        priority: Float
    ) -> NativeMetalCardDownloadOperation {
        NativeMetalCardDownloadOperation(
            remoteURL: remoteURL,
            downloadID: downloadID,
            relativePath: relativePath,
            priority: priority,
            logger: configuration.logger
        )
    }

    private func importCachedFile(_ asset: NativeMetalCardAssetPath, from sourceURL: URL) -> Bool {
        let relativePath = asset.relativePath
        let localURL = localURL(for: relativePath)
        if hasCachedFile(at: localURL) {
            if configuration.markCachedFilesAsUsed {
                markCachedFileAsUsed(at: localURL, relativePath: relativePath)
            }
            return true
        }

        guard let copiedByteCount = copyCachedFile(from: sourceURL, to: localURL) else {
            return false
        }
        fileGenerationIDs[relativePath] = nil
        if configuration.markCachedFilesAsUsed {
            markCachedFileAsUsed(at: localURL, relativePath: relativePath)
        }

        if let pendingDownload = pendingDownloads.removeValue(forKey: relativePath) {
            pendingDownload.operation.cancel()
        }
        trimCacheIfNeeded(
            protecting: Set([relativePath]),
            downloadedByteCount: copiedByteCount
        )
        return true
    }

    private func storeDownloadedFile(
        _ transfer: NativeMetalCardDownloadTransfer,
        remoteURL: URL?,
        localURL: URL,
        relativePath: String
    ) -> Int64? {
        guard let temporaryURL = transfer.temporaryURL,
              transfer.statusCode.map({ 200..<300 ~= $0 }) != false,
              transfer.errorDescription == nil else {
            configuration.logger.error(
                "\(self.configuration.logName, privacy: .public) asset download failed: \(remoteURL?.absoluteString ?? "unknown", privacy: .public), status: \(transfer.statusCode ?? -1, privacy: .public), error: \(transfer.errorDescription ?? "unknown", privacy: .public)"
            )
            if let temporaryURL = transfer.temporaryURL {
                try? fileManager.removeItem(at: temporaryURL)
            }
            return nil
        }

        do {
            fileGenerationIDs[relativePath] = nil
            try fileManager.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: localURL)
            try fileManager.moveItem(at: temporaryURL, to: localURL)
            return cachedFileByteCount(at: localURL)
        } catch {
            configuration.logger.error(
                "\(self.configuration.logName, privacy: .public) asset cache write failed: \(localURL.path, privacy: .public), error: \(String(describing: error), privacy: .public)"
            )
            try? fileManager.removeItem(at: temporaryURL)
            return nil
        }
    }

    private func copyCachedFile(from sourceURL: URL, to localURL: URL) -> Int64? {
        guard hasCachedFile(at: sourceURL) else { return nil }

        do {
            try fileManager.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: localURL)
            try fileManager.copyItem(at: sourceURL, to: localURL)
            return cachedFileByteCount(at: localURL)
        } catch {
            configuration.logger.error(
                "\(self.configuration.logName, privacy: .public) asset cache import failed: \(localURL.path, privacy: .public), error: \(String(describing: error), privacy: .public)"
            )
            try? fileManager.removeItem(at: localURL)
            return nil
        }
    }

    private func urls(for tokenID: Int) -> NativeMetalCardAssetURLs {
        let paths = assetPaths(for: tokenID)
        return NativeMetalCardAssetURLs(
            renderKind: configuration.renderKind,
            tokenID: tokenID,
            foil: assetURL(for: paths.foil),
            textureMask: assetURL(for: paths.textureMask),
            grain: assetURL(for: paths.grain),
            glitter: assetURL(for: paths.glitter)
        )
    }

    private func assetURL(for asset: NativeMetalCardAssetPath) -> NativeMetalCardAssetURL {
        let generationID = fileGenerationIDs[asset.relativePath] ?? UUID()
        fileGenerationIDs[asset.relativePath] = generationID
        return NativeMetalCardAssetURL(
            asset: asset,
            url: localURL(for: asset.relativePath),
            generationID: generationID
        )
    }

    private func effectAssets(for tokenID: Int) -> [NativeMetalCardAssetPath] {
        assetPaths(for: tokenID).effectAssets
    }

    private func assetPaths(for tokenID: Int) -> NativeMetalCardAssetPaths {
        let clampedTokenID = min(max(tokenID, 1), configuration.renderKind.tokenCount)
        return configuration.paths(clampedTokenID)
    }

    private func localURL(for relativePath: String) -> URL {
        configuration.rootURL.appendingPathComponent(relativePath)
    }

    private var cacheTrimScanByteThreshold: Int64 {
        guard let maxCacheBytes = configuration.maxCacheBytes else { return .max }
        return max(1, min(maxCacheBytes / 16, 32 * 1024 * 1024))
    }

    private func trimCacheIfNeeded(protecting protectedRelativePaths: Set<String>, downloadedByteCount: Int64) {
        guard let maxCacheBytes = configuration.maxCacheBytes else { return }
        downloadedBytesSinceLastTrimScan += downloadedByteCount
        guard !hasCompletedCacheTrimScan || downloadedBytesSinceLastTrimScan >= cacheTrimScanByteThreshold else {
            return
        }

        let protectedPaths = protectedRelativePaths.union(pendingDownloads.keys)
        let files = cachedFiles()
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        hasCompletedCacheTrimScan = true
        downloadedBytesSinceLastTrimScan = 0
        guard totalBytes > maxCacheBytes else { return }

        for file in files.sorted(by: { $0.lastUsed < $1.lastUsed }) {
            guard !protectedPaths.contains(file.relativePath) else { continue }
            do {
                try fileManager.removeItem(at: file.url)
                fileGenerationIDs[file.relativePath] = nil
                cachedFileUseTouchDates[file.relativePath] = nil
                totalBytes -= file.byteCount
                if totalBytes <= maxCacheBytes {
                    break
                }
            } catch {
                configuration.logger.error(
                    "\(self.configuration.logName, privacy: .public) cache trim failed for \(file.url.path, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func cachedFiles() -> [NativeMetalCardCachedFile] {
        guard let enumerator = fileManager.enumerator(
            at: configuration.rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
                  ),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  let relativePath = relativePath(for: fileURL) else {
                return nil
            }

            return NativeMetalCardCachedFile(
                url: fileURL,
                relativePath: relativePath,
                byteCount: Int64(fileSize),
                lastUsed: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private func relativePath(for fileURL: URL) -> String? {
        let rootPath = configuration.rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func markCachedFileAsUsed(at url: URL, relativePath: String) {
        let now = Date()
        if let lastTouchDate = cachedFileUseTouchDates[relativePath],
           now.timeIntervalSince(lastTouchDate) < Self.cachedFileUseTouchInterval {
            return
        }

        cachedFileUseTouchDates[relativePath] = now
        try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }

    private func markCachedFilesAsUsed(_ cachedFileUses: [NativeMetalCardCachedFileUse]) {
        guard !cachedFileUses.isEmpty else { return }

        var markedPaths = Set<String>()
        for cachedFileUse in cachedFileUses where markedPaths.insert(cachedFileUse.relativePath).inserted {
            markCachedFileAsUsed(at: cachedFileUse.url, relativePath: cachedFileUse.relativePath)
        }
    }

    private func hasCachedFile(at url: URL) -> Bool {
        cachedFileByteCount(at: url) != nil
    }

    private func cachedFileByteCount(at url: URL) -> Int64? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > 0 else {
            return nil
        }
        return Int64(fileSize)
    }
}

nonisolated private protocol NativeMetalCardAssetCaching: Sendable {
    func loadFace(for tokenID: Int) async -> NativeMetalCardAssetURL?
    func cacheFace(for tokenID: Int, from sourceURL: URL) async -> Bool
    func loadEffectAssets(for tokenID: Int) async -> NativeMetalCardAssetURLs?
    func prefetch(around tokenID: Int, radius: Int) async
    func invalidate(_ assetURL: NativeMetalCardAssetURL) async
    func cancelPrefetchDownloads() async
}

nonisolated extension CardNft2AssetCache: NativeMetalCardAssetCaching {}
nonisolated extension PonchoDrifellaAssetCache: NativeMetalCardAssetCaching {}

nonisolated extension NativeMetalCardRenderKind {
    var staticImageSize: CGSize {
        NativeMetalCardStaticImageAsset.size
    }

    var staticImageFileExtension: String {
        NativeMetalCardStaticImageAsset.fileExtension
    }

    func staticImageURL(tokenID: Int) -> URL? {
        guard tokenID >= 1,
              tokenID <= tokenCount else {
            return nil
        }
        return staticImageURL(fileName: faceImageFileName(tokenID: tokenID))
    }

    func staticImageURL(fileName: String) -> URL {
        NativeMetalCardStaticImageAsset.baseURL(for: self).appendingPathComponent(fileName)
    }

    func faceImageFileName(tokenID: Int) -> String {
        switch self {
        case .cardNft2:
            return String(format: "%04d.%@", tokenID, staticImageFileExtension)
        case .ponchoDrifella:
            return "\(tokenID).\(staticImageFileExtension)"
        }
    }

    func faceImageRelativePath(tokenID: Int) -> String {
        switch self {
        case .cardNft2:
            return "img/\(faceImageFileName(tokenID: tokenID))"
        case .ponchoDrifella:
            return "drifs/\(faceImageFileName(tokenID: tokenID))"
        }
    }

    private var assetCache: any NativeMetalCardAssetCaching {
        switch self {
        case .cardNft2:
            CardNft2AssetCache.shared
        case .ponchoDrifella:
            PonchoDrifellaAssetCache.shared
        }
    }

    func loadFace(for tokenID: Int) async -> NativeMetalCardAssetURL? {
        await assetCache.loadFace(for: tokenID)
    }

    func cacheFace(for tokenID: Int, from sourceURL: URL) async -> Bool {
        await assetCache.cacheFace(for: tokenID, from: sourceURL)
    }

    func loadEffectAssets(for tokenID: Int) async -> NativeMetalCardAssetURLs? {
        await assetCache.loadEffectAssets(for: tokenID)
    }

    func prefetch(around tokenID: Int, radius: Int) async {
        await assetCache.prefetch(around: tokenID, radius: radius)
    }

    func invalidate(_ assetURL: NativeMetalCardAssetURL) async {
        await assetCache.invalidate(assetURL)
    }

    func cancelPrefetchDownloads() async {
        await assetCache.cancelPrefetchDownloads()
    }
}
