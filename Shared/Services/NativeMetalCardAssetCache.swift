// ∅ 2026 lil org

import CoreGraphics
import Foundation
import os

struct NativeMetalCardAssetURLs {
    let renderKind: NativeMetalCardRenderKind
    let tokenID: Int
    let foil: NativeMetalCardAssetURL
    let textureMask: NativeMetalCardAssetURL
    let grain: NativeMetalCardAssetURL
    let glitter: NativeMetalCardAssetURL
}

struct NativeMetalCardAssetURL {
    let asset: NativeMetalCardAssetPath
    let url: URL
}

enum NativeMetalCardAssetRole: Hashable {
    case face
    case foil
    case textureMask
    case grain
    case glitter
}

struct NativeMetalCardAssetPath: Hashable {
    let role: NativeMetalCardAssetRole
    let relativePath: String
}

struct NativeMetalCardAssetPaths {
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

struct NativeMetalCardAssetCacheConfiguration {
    let renderKind: NativeMetalCardRenderKind
    let rootURL: URL
    let logger: Logger
    let logName: String
    let maxCacheBytes: Int64?
    let markCachedFilesAsUsed: Bool
    let paths: (Int) -> NativeMetalCardAssetPaths
    let remoteURL: (NativeMetalCardAssetPath) -> URL?
}

private struct NativeMetalCardFileEnsureResult {
    let didSucceed: Bool
    let downloadedByteCount: Int64
    let cachedFileUse: NativeMetalCardCachedFileUse?
}

private struct NativeMetalCardCachedFileUse {
    let url: URL
    let relativePath: String
}

private struct PendingNativeMetalCardDownload {
    let id: UUID
    let task: URLSessionDownloadTask
    var completions: [(NativeMetalCardFileEnsureResult) -> Void]
    var isPrefetchOnly: Bool
}

private struct NativeMetalCardCachedFile {
    let url: URL
    let relativePath: String
    let byteCount: Int64
    let lastUsed: Date
}

private enum NativeMetalCardStaticImageAsset {
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

final class NativeMetalCardAssetCache {

    private static let cachedFileUseTouchInterval: TimeInterval = 5 * 60

    private let fileManager = FileManager.default
    private let configuration: NativeMetalCardAssetCacheConfiguration
    private let workQueue: DispatchQueue
    private let workQueueSpecificKey = DispatchSpecificKey<Void>()
    private var pendingDownloads = [String: PendingNativeMetalCardDownload]()
    private var downloadedBytesSinceLastTrimScan: Int64 = 0
    private var hasCompletedCacheTrimScan = false
    private var cachedFileUseTouchDates = [String: Date]()

    init(configuration: NativeMetalCardAssetCacheConfiguration, queueLabel: String) {
        self.configuration = configuration
        self.workQueue = DispatchQueue(label: queueLabel, qos: .utility)
        self.workQueue.setSpecific(key: workQueueSpecificKey, value: ())

        try? fileManager.createDirectory(at: configuration.rootURL, withIntermediateDirectories: true)
        var resourceURL = configuration.rootURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(resourceValues)
    }

    func loadEffectAssets(for tokenID: Int, completion: @escaping (NativeMetalCardAssetURLs?) -> Void) {
        let assetURLs = urls(for: tokenID)
        ensureFiles(effectAssets(for: tokenID)) { didSucceed in
            DispatchQueue.main.async {
                completion(didSucceed ? assetURLs : nil)
            }
        }
    }

    func loadFace(for tokenID: Int, completion: @escaping (URL?) -> Void) {
        let faceAsset = assetPaths(for: tokenID).face
        let faceURL = localURL(for: faceAsset.relativePath)
        ensureFiles([faceAsset]) { didSucceed in
            DispatchQueue.main.async {
                completion(didSucceed ? faceURL : nil)
            }
        }
    }

    func cacheFace(
        for tokenID: Int,
        from sourceURL: URL,
        completion: ((Bool) -> Void)? = nil
    ) {
        importCachedFile(
            faceAsset(for: tokenID),
            from: sourceURL,
            completion: completion
        )
    }

    func cache(
        assets: [NativeMetalCardAssetPath],
        taskPriority: Float = URLSessionTask.defaultPriority,
        isPrefetch: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        ensureFiles(
            assets,
            taskPriority: taskPriority,
            isPrefetch: isPrefetch,
            completion: completion
        )
    }

    func cancelStalePrefetchDownloads(keeping relativePathsToKeep: Set<String>) {
        workQueue.async {
            let stalePrefetchDownloads = self.pendingDownloads.filter { relativePath, pendingDownload in
                pendingDownload.isPrefetchOnly && !relativePathsToKeep.contains(relativePath)
            }

            for (relativePath, pendingDownload) in stalePrefetchDownloads {
                self.pendingDownloads.removeValue(forKey: relativePath)
                pendingDownload.task.cancel()
                pendingDownload.completions.forEach {
                    $0(NativeMetalCardFileEnsureResult(
                        didSucceed: false,
                        downloadedByteCount: 0,
                        cachedFileUse: nil
                    ))
                }
            }
        }
    }

    func cancelPrefetchDownloads() {
        cancelStalePrefetchDownloads(keeping: [])
    }

    func invalidateFaceAsset(for tokenID: Int) {
        invalidateAssets([faceAsset(for: tokenID)])
    }

    func invalidateEffectAssets(for tokenID: Int) {
        invalidateAssets(tokenSpecificEffectAssets(for: tokenID))
    }

    func invalidate(_ asset: NativeMetalCardAssetPath) {
        invalidateAssets([asset])
    }

    func invalidateAssets(_ assets: [NativeMetalCardAssetPath]) {
        workQueue.async {
            for asset in assets {
                self.cachedFileUseTouchDates[asset.relativePath] = nil
                try? self.fileManager.removeItem(at: self.localURL(for: asset.relativePath))
            }
        }
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
        isPrefetch: Bool = false,
        completion: ((Bool) -> Void)?
    ) {
        let group = DispatchGroup()
        var didSucceed = true
        var downloadedByteCount: Int64 = 0
        var cachedFileUses = [NativeMetalCardCachedFileUse]()

        for asset in assets {
            group.enter()
            ensureFile(asset, taskPriority: taskPriority, isPrefetch: isPrefetch) { result in
                didSucceed = didSucceed && result.didSucceed
                downloadedByteCount += result.downloadedByteCount
                if let cachedFileUse = result.cachedFileUse {
                    cachedFileUses.append(cachedFileUse)
                }
                group.leave()
            }
        }

        group.notify(queue: workQueue) {
            completion?(didSucceed)
            self.markCachedFilesAsUsed(cachedFileUses)
            if downloadedByteCount > 0 {
                self.trimCacheIfNeeded(
                    protecting: Set(assets.map(\.relativePath)),
                    downloadedByteCount: downloadedByteCount
                )
            }
        }
    }

    private func ensureFile(
        _ asset: NativeMetalCardAssetPath,
        taskPriority: Float,
        isPrefetch: Bool,
        completion: @escaping (NativeMetalCardFileEnsureResult) -> Void
    ) {
        workQueue.async {
            self.ensureFileOnWorkQueue(
                asset,
                taskPriority: taskPriority,
                isPrefetch: isPrefetch,
                completion: completion
            )
        }
    }

    private func importCachedFile(
        _ asset: NativeMetalCardAssetPath,
        from sourceURL: URL,
        completion: ((Bool) -> Void)?
    ) {
        workQueue.async {
            let relativePath = asset.relativePath
            let localURL = self.localURL(for: relativePath)
            if self.hasCachedFile(at: localURL) {
                if self.configuration.markCachedFilesAsUsed {
                    self.markCachedFileAsUsed(at: localURL, relativePath: relativePath)
                }
                completion?(true)
                return
            }

            guard let copiedByteCount = self.copyCachedFile(from: sourceURL, to: localURL) else {
                completion?(false)
                return
            }
            if self.configuration.markCachedFilesAsUsed {
                self.markCachedFileAsUsed(at: localURL, relativePath: relativePath)
            }

            if let pendingDownload = self.pendingDownloads.removeValue(forKey: relativePath) {
                pendingDownload.task.cancel()
                let cachedFileUse = self.configuration.markCachedFilesAsUsed && !pendingDownload.isPrefetchOnly
                    ? NativeMetalCardCachedFileUse(url: localURL, relativePath: relativePath)
                    : nil
                let result = NativeMetalCardFileEnsureResult(
                    didSucceed: true,
                    downloadedByteCount: 0,
                    cachedFileUse: cachedFileUse
                )
                pendingDownload.completions.forEach { $0(result) }
            }

            completion?(true)
            self.trimCacheIfNeeded(
                protecting: Set([relativePath]),
                downloadedByteCount: copiedByteCount
            )
        }
    }

    private func ensureFileOnWorkQueue(
        _ asset: NativeMetalCardAssetPath,
        taskPriority: Float,
        isPrefetch: Bool,
        completion: @escaping (NativeMetalCardFileEnsureResult) -> Void
    ) {
        let relativePath = asset.relativePath
        let localURL = self.localURL(for: relativePath)
        if self.hasCachedFile(at: localURL) {
            let cachedFileUse = configuration.markCachedFilesAsUsed && !isPrefetch
                ? NativeMetalCardCachedFileUse(url: localURL, relativePath: relativePath)
                : nil
            completion(NativeMetalCardFileEnsureResult(
                didSucceed: true,
                downloadedByteCount: 0,
                cachedFileUse: cachedFileUse
            ))
            return
        }

        if var pendingDownload = self.pendingDownloads[relativePath] {
            pendingDownload.completions.append(completion)
            pendingDownload.isPrefetchOnly = pendingDownload.isPrefetchOnly && isPrefetch
            pendingDownload.task.priority = max(pendingDownload.task.priority, taskPriority)
            self.pendingDownloads[relativePath] = pendingDownload
            return
        }

        guard let remoteURL = configuration.remoteURL(asset) else {
            configuration.logger.error("Unknown \(self.configuration.logName, privacy: .public) asset path: \(relativePath, privacy: .public)")
            completion(NativeMetalCardFileEnsureResult(
                didSucceed: false,
                downloadedByteCount: 0,
                cachedFileUse: nil
            ))
            return
        }

        let downloadID = UUID()
        let task = URLSession.shared.downloadTask(with: remoteURL) { temporaryURL, response, error in
            self.completeDownload(
                relativePath: relativePath,
                downloadID: downloadID,
                from: temporaryURL,
                response: response,
                error: error,
                remoteURL: remoteURL,
                localURL: localURL
            )
        }
        task.priority = taskPriority
        self.pendingDownloads[relativePath] = PendingNativeMetalCardDownload(
            id: downloadID,
            task: task,
            completions: [completion],
            isPrefetchOnly: isPrefetch
        )
        task.resume()
    }

    private func storeDownloadedFile(
        from temporaryURL: URL?,
        response: URLResponse?,
        error: Error?,
        remoteURL: URL,
        localURL: URL
    ) -> Int64? {
        guard error == nil,
              let temporaryURL,
              (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) != false else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            configuration.logger.error(
                "\(self.configuration.logName, privacy: .public) asset download failed: \(remoteURL.absoluteString, privacy: .public), status: \(statusCode, privacy: .public), error: \(String(describing: error), privacy: .public)"
            )
            if let temporaryURL {
                try? fileManager.removeItem(at: temporaryURL)
            }
            return nil
        }

        do {
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

    private func completeDownload(
        relativePath: String,
        downloadID: UUID,
        from temporaryURL: URL?,
        response: URLResponse?,
        error: Error?,
        remoteURL: URL,
        localURL: URL
    ) {
        if DispatchQueue.getSpecific(key: workQueueSpecificKey) != nil {
            completeDownloadOnWorkQueue(
                relativePath: relativePath,
                downloadID: downloadID,
                from: temporaryURL,
                response: response,
                error: error,
                remoteURL: remoteURL,
                localURL: localURL
            )
        } else {
            let persistedTemporaryURL = persistTemporaryDownloadFile(
                temporaryURL,
                downloadID: downloadID,
                relativePath: relativePath
            )
            workQueue.async {
                self.completeDownloadOnWorkQueue(
                    relativePath: relativePath,
                    downloadID: downloadID,
                    from: persistedTemporaryURL,
                    response: response,
                    error: error,
                    remoteURL: remoteURL,
                    localURL: localURL
                )
            }
        }
    }

    private func persistTemporaryDownloadFile(
        _ temporaryURL: URL?,
        downloadID: UUID,
        relativePath: String
    ) -> URL? {
        guard let temporaryURL else { return nil }

        let handoffDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "NativeMetalCardDownloads",
            isDirectory: true
        )
        let handoffURL = handoffDirectory
            .appendingPathComponent(downloadID.uuidString)
            .appendingPathExtension(URL(fileURLWithPath: relativePath).pathExtension)

        do {
            try fileManager.createDirectory(at: handoffDirectory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: handoffURL)
            try fileManager.moveItem(at: temporaryURL, to: handoffURL)
            return handoffURL
        } catch {
            configuration.logger.error(
                "\(self.configuration.logName, privacy: .public) download handoff failed for \(relativePath, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func completeDownloadOnWorkQueue(
        relativePath: String,
        downloadID: UUID,
        from temporaryURL: URL?,
        response: URLResponse?,
        error: Error?,
        remoteURL: URL,
        localURL: URL
    ) {
        guard pendingDownloads[relativePath]?.id == downloadID else {
            if let temporaryURL {
                try? fileManager.removeItem(at: temporaryURL)
            }
            return
        }
        let downloadedByteCount = storeDownloadedFile(
            from: temporaryURL,
            response: response,
            error: error,
            remoteURL: remoteURL,
            localURL: localURL
        )
        let completions = pendingDownloads.removeValue(forKey: relativePath)?.completions ?? []
        let result = NativeMetalCardFileEnsureResult(
            didSucceed: downloadedByteCount != nil,
            downloadedByteCount: downloadedByteCount ?? 0,
            cachedFileUse: nil
        )
        completions.forEach { $0(result) }
    }

    private func urls(for tokenID: Int) -> NativeMetalCardAssetURLs {
        let paths = assetPaths(for: tokenID)
        return NativeMetalCardAssetURLs(
            renderKind: configuration.renderKind,
            tokenID: tokenID,
            foil: NativeMetalCardAssetURL(asset: paths.foil, url: localURL(for: paths.foil.relativePath)),
            textureMask: NativeMetalCardAssetURL(
                asset: paths.textureMask,
                url: localURL(for: paths.textureMask.relativePath)
            ),
            grain: NativeMetalCardAssetURL(asset: paths.grain, url: localURL(for: paths.grain.relativePath)),
            glitter: NativeMetalCardAssetURL(asset: paths.glitter, url: localURL(for: paths.glitter.relativePath))
        )
    }

    private func effectAssets(for tokenID: Int) -> [NativeMetalCardAssetPath] {
        assetPaths(for: tokenID).effectAssets
    }

    private func tokenSpecificEffectAssets(for tokenID: Int) -> [NativeMetalCardAssetPath] {
        assetPaths(for: tokenID).tokenSpecificEffectAssets
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

private protocol NativeMetalCardAssetCaching: AnyObject {
    func loadFace(for tokenID: Int, completion: @escaping (URL?) -> Void)
    func cacheFace(for tokenID: Int, from sourceURL: URL, completion: ((Bool) -> Void)?)
    func loadEffectAssets(for tokenID: Int, completion: @escaping (NativeMetalCardAssetURLs?) -> Void)
    func prefetch(around tokenID: Int, radius: Int)
    func invalidateFaceAsset(for tokenID: Int)
    func invalidateEffectAssets(for tokenID: Int)
    func invalidate(_ asset: NativeMetalCardAssetPath)
    func cancelPrefetchDownloads()
}

extension CardNft2AssetCache: NativeMetalCardAssetCaching {}
extension PonchoDrifellaAssetCache: NativeMetalCardAssetCaching {}

extension NativeMetalCardRenderKind {
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

    private var assetCache: NativeMetalCardAssetCaching {
        switch self {
        case .cardNft2:
            return CardNft2AssetCache.shared
        case .ponchoDrifella:
            return PonchoDrifellaAssetCache.shared
        }
    }

    func loadFace(for tokenID: Int, completion: @escaping (URL?) -> Void) {
        assetCache.loadFace(for: tokenID, completion: completion)
    }

    func cacheFace(
        for tokenID: Int,
        from sourceURL: URL,
        completion: ((Bool) -> Void)? = nil
    ) {
        assetCache.cacheFace(for: tokenID, from: sourceURL, completion: completion)
    }

    func loadEffectAssets(for tokenID: Int, completion: @escaping (NativeMetalCardAssetURLs?) -> Void) {
        assetCache.loadEffectAssets(for: tokenID, completion: completion)
    }

    func prefetch(around tokenID: Int, radius: Int) {
        assetCache.prefetch(around: tokenID, radius: radius)
    }

    func invalidateFaceAsset(for tokenID: Int) {
        assetCache.invalidateFaceAsset(for: tokenID)
    }

    func invalidateEffectAssets(for tokenID: Int) {
        assetCache.invalidateEffectAssets(for: tokenID)
    }

    func invalidate(_ asset: NativeMetalCardAssetPath) {
        assetCache.invalidate(asset)
    }

    func cancelPrefetchDownloads() {
        assetCache.cancelPrefetchDownloads()
    }
}
