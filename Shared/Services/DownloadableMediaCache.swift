// ∅ 2026 lil org

import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
typealias DownloadableMediaImage = NSImage
#else
import UIKit
typealias DownloadableMediaImage = UIImage
#endif

extension Notification.Name {
    static let downloadableMediaCacheFileAvailabilityDidChange = Notification.Name("DownloadableMediaCacheFileAvailabilityDidChange")
}

final class DownloadableMediaCache {

    typealias PrefetchDirection = PlayerMediaPrefetchDirection

    static let shared = DownloadableMediaCache()

    private static let webViewHTMLDirectoryName = "_WebViewHTML"

    static func orderedWindowIndices(currentIndex: Int, tokenCount: Int, direction: PrefetchDirection) -> [Int] {
        PlayerDownloadableMediaWindowLayout.orderedWindowIndices(
            currentIndex: currentIndex,
            tokenCount: tokenCount,
            direction: direction
        )
    }

    static func windowDescriptors(
        collectionId: String,
        currentTokenIndex: Int,
        tokenCount: Int,
        direction: PrefetchDirection
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        orderedWindowIndices(
            currentIndex: currentTokenIndex,
            tokenCount: tokenCount,
            direction: direction
        )
        .compactMap {
            CollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: collectionId,
                tokenIndex: $0
            )
        }
    }

    private static func decodedWindowDescriptors(
        collectionId: String,
        currentTokenIndex: Int,
        tokenCount: Int,
        direction: PrefetchDirection
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        PlayerDownloadableMediaWindowLayout.decodedWindowIndices(
            currentIndex: currentTokenIndex,
            tokenCount: tokenCount,
            direction: direction
        )
        .compactMap {
            CollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: collectionId,
                tokenIndex: $0
            )
        }
    }

    static func adjacentDescriptor(
        collectionId: String,
        currentTokenIndex: Int,
        tokenCount: Int,
        direction: PrefetchDirection
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        let targetTokenIndex = currentTokenIndex + direction.adjacentOffset
        guard targetTokenIndex >= 0, targetTokenIndex < tokenCount else { return nil }
        return CollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: collectionId,
            tokenIndex: targetTokenIndex
        )
    }

    static func adjacentDescriptor(
        for context: PlayerTokenContext?,
        direction: PrefetchDirection
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let context else { return nil }
        return adjacentDescriptor(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
    }

    private let queue = DispatchQueue(label: "org.lil.nft-player.downloadable-media-cache", qos: .utility)
    private let imageDecodeQueue = DispatchQueue(label: "org.lil.nft-player.downloadable-media-cache.decode", qos: .utility)
    private let foregroundImageDecodeQueue = DispatchQueue(
        label: "org.lil.nft-player.downloadable-media-cache.decode.foreground",
        qos: .utility
    )
    private let memoryCache = NSCache<NSString, DownloadableMediaImage>()
    private let session: URLSession
    private let cacheRoot: URL
    private let stagingRoot: URL
    private let maximumConcurrentDownloads = 4

    private struct OngoingDownload {
        let task: URLSessionDownloadTask
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let id: UUID
    }

    private struct DownloadedMediaMetadata: Codable {
        let sourceURL: URL
    }

    private enum ImageDecodePriority: Equatable {
        case foreground, prefetch
    }

    private enum ImageDecodeWorkKind: Equatable {
        case primary, foregroundRace
    }

    private struct ImageDecodeJob {
        let decodeId: UUID
        let fileURL: URL
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let key: String
        let redownloadOnFailure: Bool
        let priority: ImageDecodePriority
        let workKind: ImageDecodeWorkKind
    }

    private final class LoadRequest {
        let id = UUID()
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }

        func cancelIfNeeded() -> Bool {
            lock.withLock {
                guard !cancelled else { return false }
                cancelled = true
                return true
            }
        }
    }

    private final class OneShotToken {
        private let lock = NSLock()
        private var wasTaken = false

        func take() -> Bool {
            lock.withLock {
                guard !wasTaken else { return false }
                wasTaken = true
                return true
            }
        }
    }

    private struct RetainedFileNameKey: Hashable {
        let collectionId: String
        let fileName: String
    }

    private typealias ImageLoadCompletion = (DownloadableMediaImage?) -> Void
    private struct ImageLoadCallback {
        let request: LoadRequest
        let completion: ImageLoadCompletion
    }
    private typealias ImageLoadCompletions = [UUID: ImageLoadCallback]

    private typealias FileLoadCompletion = (URL?) -> Void
    private struct FileLoadCallback {
        let request: LoadRequest
        let completion: FileLoadCompletion
    }
    private typealias FileLoadCompletions = [UUID: FileLoadCallback]

    private struct ActiveWindow {
        let collectionId: String
        let ownerId: UUID
        let fileNames: Set<String>
        let decodedKeys: Set<String>
    }

    private var activeWindow: ActiveWindow?
    private var memoryKeysByCollection = [String: Set<String>]()
    private var pendingDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
    private var pendingKeys = Set<String>()
    private var ongoingDownloads = [String: OngoingDownload]()
    private var decodeIdsByKey = [String: UUID]()
    private var foregroundDecodeIdsByKey = [String: UUID]()
    private var freshDownloadDecodeKeys = Set<String>()
    private var redownloadOnDecodeFailureKeys = Set<String>()
    private var foregroundKey: String?
    private var foregroundWorkKeys = Set<String>()
    private var completions = [String: ImageLoadCompletions]()
    private var fileCompletions = [String: FileLoadCompletions]()
    private var retainedFileKeys = [String: Int]()
    private var retainedFileNameKeys = [RetainedFileNameKey: Int]()
    private var retainedDecodeFailureDescriptors = [String: CollectionCatalogDownloadableMediaDescriptor]()
    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = maximumConcurrentDownloads
        session = URLSession(configuration: configuration)
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        cacheRoot = applicationSupportDirectory.appendingPathComponent("DownloadableTokenMedia", isDirectory: true)
        stagingRoot = fileManager.temporaryDirectory.appendingPathComponent("DownloadableTokenMedia", isDirectory: true)
        try? fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        var excludedFromBackupURL = cacheRoot
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludedFromBackupURL.setResourceValues(resourceValues)
        try? FileManager.default.removeItem(
            at: cacheRoot.appendingPathComponent(Self.webViewHTMLDirectoryName, isDirectory: true)
        )
        memoryCache.countLimit = PlayerDownloadableMediaWindowLayout.decodedWindowCapacity
        memoryCache.totalCostLimit = 128 * 1024 * 1024

#if os(iOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clearMemoryCache()
        }
#endif
    }

    @discardableResult
    func prepareWindow(
        for context: PlayerTokenContext?,
        ownerId: UUID,
        direction: PrefetchDirection
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let context else { return nil }

        let descriptors = Self.windowDescriptors(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
        let decodedDescriptors = Self.decodedWindowDescriptors(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
        guard let currentDescriptor = descriptors.first(where: { $0.tokenIndex == context.tokenIndex }) else {
            return nil
        }

        let window = PlayerDownloadableMediaWindow(
            currentDescriptor: currentDescriptor,
            descriptors: descriptors,
            decodedDescriptors: decodedDescriptors,
            adjacentDescriptor: nil
        )
        prepareWindow(window, ownerId: ownerId)
        return currentDescriptor
    }

    @discardableResult
    func prepareWindow(
        _ window: PlayerDownloadableMediaWindow,
        ownerId: UUID
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        prepareWindow(
            collectionId: window.currentDescriptor.collectionId,
            ownerId: ownerId,
            currentDescriptor: window.currentDescriptor,
            descriptors: window.descriptors,
            decodedDescriptors: window.decodedDescriptors
        )
        return window.currentDescriptor
    }

    private func prepareWindow(
        collectionId: String,
        ownerId: UUID,
        currentDescriptor: CollectionCatalogDownloadableMediaDescriptor,
        descriptors: [CollectionCatalogDownloadableMediaDescriptor],
        decodedDescriptors: [CollectionCatalogDownloadableMediaDescriptor]
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let previousWindow = self.activeWindow
            let didChangeCollection = previousWindow?.collectionId != collectionId
            if didChangeCollection {
                self.cancelDownloadsOutsideActiveCollection(collectionId: collectionId)
                self.evictMemoryOutsideActiveCollection(collectionId: collectionId)
            }

            let allowedFileNames = Set(descriptors.flatMap(self.fileNames(for:)))
            let allowedKeys = Set(descriptors.map(self.cacheKey(for:)))
            let decodedKeys = Set(decodedDescriptors.map(self.cacheKey(for:)))
            let didChangeFileWindow = didChangeCollection || previousWindow?.fileNames != allowedFileNames
            let didChangeDecodedWindow = didChangeCollection || previousWindow?.decodedKeys != decodedKeys
            self.activeWindow = ActiveWindow(
                collectionId: collectionId,
                ownerId: ownerId,
                fileNames: allowedFileNames,
                decodedKeys: decodedKeys
            )

            if didChangeFileWindow {
                self.evictFilesOutsideWindow(collectionId: collectionId, allowedFileNames: allowedFileNames)
                self.cancelDownloadsOutsideWindow(collectionId: collectionId, allowedKeys: allowedKeys)
            }
            self.pruneForegroundTracking(allowedKeys: allowedKeys)
            self.prioritizeForegroundImageIfNeeded(
                currentDescriptor,
                requireDecodedStaticImage: currentDescriptor.isStaticImage
            )
            if didChangeDecodedWindow {
                self.evictMemoryOutsideWindow(collectionId: collectionId, allowedKeys: decodedKeys)
            }
            self.decodeCachedImagesIfNeeded(decodedDescriptors)

            let downloadDescriptors = self.prioritizedDownloadDescriptors(
                currentDescriptor: currentDescriptor,
                descriptors: descriptors,
                decodedDescriptors: decodedDescriptors
            )
            for descriptor in downloadDescriptors {
                self.enqueueDownloadIfNeeded(descriptor, isForegroundRequest: false)
            }
            self.reorderPendingDownloads(preferredDescriptors: downloadDescriptors)
            self.startDownloadsIfNeeded()
        }
    }

    func clearActiveWindow(ownerId: UUID) {
        queue.async { [weak self] in
            guard let self, self.activeWindow?.ownerId == ownerId else { return }
            self.clearActiveWindowState()
        }
    }

    func cancelAllDownloads() {
        queue.async { [weak self] in
            guard let self else { return }

            self.cancelUnretainedDownloadsAndPendingWork()

            self.decodeIdsByKey.removeAll()
            self.foregroundDecodeIdsByKey.removeAll()
            self.freshDownloadDecodeKeys.removeAll()
            self.redownloadOnDecodeFailureKeys.removeAll()
            self.foregroundKey = nil
            self.foregroundWorkKeys.removeAll()
            self.memoryCache.removeAllObjects()
            self.memoryKeysByCollection.removeAll()
            self.activeWindow = nil
            self.updateOngoingDownloadPriorities()
            self.startDownloadsIfNeeded()
        }
    }

    @discardableResult
    func loadImage(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        completion: @escaping (DownloadableMediaImage?) -> Void
    ) -> (() -> Void)? {
        guard descriptor.isStaticImage else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return nil
        }

        let request = LoadRequest()
        queue.async { [weak self] in
            guard let self else { return }
            guard !request.isCancelled else { return }

            let key = self.cacheKey(for: descriptor)
            let callback = ImageLoadCallback(request: request, completion: completion)
            if let cachedImage = self.cachedDecodedImage(forKey: key) {
                self.complete([callback], with: cachedImage)
                return
            }

            let fileURL = self.fileURL(for: descriptor)
            self.completions[key, default: [:]][request.id] = callback
            self.prioritizeForegroundImageIfNeeded(descriptor, requireDecodedStaticImage: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if self.decodeIdsByKey[key] == nil {
                    self.startImageDecode(
                        at: fileURL,
                        descriptor: descriptor,
                        key: key,
                        redownloadOnFailure: true,
                        priority: .foreground
                    )
                } else {
                    let shouldRedownloadOnFailure = !self.freshDownloadDecodeKeys.contains(key)
                    if shouldRedownloadOnFailure {
                        self.redownloadOnDecodeFailureKeys.insert(key)
                    }
                    self.startForegroundDecodeIfNeeded(
                        at: fileURL,
                        descriptor: descriptor,
                        key: key,
                        redownloadOnFailure: shouldRedownloadOnFailure
                    )
                }
                return
            }

            self.startDownloadsIfNeeded()
        }

        return { [weak self, request] in
            guard request.cancelIfNeeded() else { return }
            self?.cancelImageLoad(for: descriptor, requestId: request.id)
        }
    }

    @discardableResult
    func loadImage(for token: GeneratedToken, completion: @escaping (DownloadableMediaImage?) -> Void) -> (() -> Void)? {
        guard let tokenIndex = CollectionCatalog.tokenIndex(
            specificCollectionId: token.fullCollectionId,
            tokenId: token.id
        ),
              let descriptor = CollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: token.fullCollectionId,
                tokenIndex: tokenIndex
              ) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return nil
        }

        return loadImage(for: descriptor, completion: completion)
    }

    @discardableResult
    func loadFile(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        completion: @escaping (URL?) -> Void
    ) -> (() -> Void)? {
        let request = LoadRequest()
        queue.async { [weak self] in
            guard let self else { return }
            guard !request.isCancelled else { return }

            let key = self.cacheKey(for: descriptor)
            let callback = FileLoadCallback(request: request, completion: completion)
            let fileURL = self.fileURL(for: descriptor)
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                self.completeFile([callback], with: fileURL)
                return
            }

            self.fileCompletions[key, default: [:]][request.id] = callback
            self.prioritizeForegroundImageIfNeeded(descriptor, requireDecodedStaticImage: false)
            self.startDownloadsIfNeeded()
        }

        return { [weak self, request] in
            guard request.cancelIfNeeded() else { return }
            self?.cancelFileLoad(for: descriptor, requestId: request.id)
        }
    }

    private func cancelImageLoad(for descriptor: CollectionCatalogDownloadableMediaDescriptor, requestId: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelLoad(for: descriptor, requestId: requestId) { key, requestId in
                self.removeCompletion(forKey: key, requestId: requestId)
            }
        }
    }

    private func cancelFileLoad(for descriptor: CollectionCatalogDownloadableMediaDescriptor, requestId: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelLoad(for: descriptor, requestId: requestId) { key, requestId in
                self.removeFileCompletion(forKey: key, requestId: requestId)
            }
        }
    }

    private func cancelLoad(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        requestId: UUID,
        removeCallback: (String, UUID) -> Bool
    ) {
        let key = cacheKey(for: descriptor)
        guard removeCallback(key, requestId) else { return }
        guard cancelFileWorkIfNoLongerNeeded(for: descriptor, key: key) else { return }
        startDownloadsIfNeeded()
    }

    private func removeCompletion(forKey key: String, requestId: UUID) -> Bool {
        removeCallback(forKey: key, requestId: requestId, from: &completions)
    }

    private func removeFileCompletion(forKey key: String, requestId: UUID) -> Bool {
        removeCallback(forKey: key, requestId: requestId, from: &fileCompletions)
    }

    private func removeCallback<Callback>(
        forKey key: String,
        requestId: UUID,
        from callbacksByKey: inout [String: [UUID: Callback]]
    ) -> Bool {
        guard var callbacks = callbacksByKey[key],
              callbacks.removeValue(forKey: requestId) != nil else {
            return false
        }

        if callbacks.isEmpty {
            callbacksByKey.removeValue(forKey: key)
        } else {
            callbacksByKey[key] = callbacks
        }
        return true
    }

    func localFileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL? {
        let url = fileURL(for: descriptor)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func retainFile(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> () -> Void {
        let key = cacheKey(for: descriptor)
        let collectionId = descriptor.collectionId
        let fileNameKeys = fileNames(for: descriptor).map {
            RetainedFileNameKey(collectionId: collectionId, fileName: $0)
        }
        let releaseToken = OneShotToken()

        queue.async { [weak self] in
            guard let self else { return }
            self.retainedFileKeys[key, default: 0] += 1
            for fileNameKey in fileNameKeys {
                self.retainedFileNameKeys[fileNameKey, default: 0] += 1
            }
            self.updateOngoingDownloadPriorities()
            self.startDownloadsIfNeeded()
        }

        return { [weak self, releaseToken] in
            guard releaseToken.take() else { return }
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.releaseRetainedFile(forKey: key, fileNameKeys: fileNameKeys)
                if !self.hasRetainedFile(forKey: key) {
                    self.handleRetainedDecodeFailureIfNeeded(forKey: key)
                    self.cancelFileWorkIfNoLongerNeeded(for: descriptor, key: key)
                }
                if let activeWindow,
                   activeWindow.collectionId == collectionId,
                   !Set(self.fileNames(for: descriptor)).isSubset(of: activeWindow.fileNames) {
                    self.evictFilesOutsideWindow(
                        collectionId: collectionId,
                        allowedFileNames: activeWindow.fileNames
                    )
                }
                self.updateOngoingDownloadPriorities()
                self.startDownloadsIfNeeded()
            }
        }
    }

    func downloadedSourceURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL {
        guard let data = try? Data(contentsOf: metadataFileURL(for: descriptor)),
              let metadata = try? JSONDecoder().decode(DownloadedMediaMetadata.self, from: data) else {
            return descriptor.url
        }
        return metadata.sourceURL
    }

    func cachedDecodedImage(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> DownloadableMediaImage? {
        cachedDecodedImage(forKey: cacheKey(for: descriptor))
    }

    var webViewHTMLDirectoryURL: URL {
        cacheRoot.appendingPathComponent(Self.webViewHTMLDirectoryName, isDirectory: true)
    }

    var webViewReadAccessURL: URL {
        cacheRoot
    }

    private func notifyFileAvailabilityChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadableMediaCacheFileAvailabilityDidChange, object: nil)
        }
    }

    @discardableResult
    private func removeItemIfPresent(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return false
        } catch {
            return false
        }
    }

    private func clearMemoryCache() {
        queue.async { [weak self] in
            self?.memoryCache.removeAllObjects()
            self?.memoryKeysByCollection.removeAll()
        }
    }

    private func enqueueDownloadIfNeeded(_ descriptor: CollectionCatalogDownloadableMediaDescriptor, isForegroundRequest: Bool) {
        let key = cacheKey(for: descriptor)
        if let ongoingDownload = ongoingDownloads[key] {
            if isForegroundRequest {
                ongoingDownload.task.priority = downloadTaskPriority(forKey: key)
            }
            return
        }
        guard !FileManager.default.fileExists(atPath: fileURL(for: descriptor).path) else { return }

        if pendingKeys.contains(key) {
            guard isForegroundRequest else { return }
            pendingDescriptors.removeAll { cacheKey(for: $0) == key }
            pendingDescriptors.insert(descriptor, at: 0)
            return
        }

        pendingKeys.insert(key)
        if isForegroundRequest {
            pendingDescriptors.insert(descriptor, at: 0)
        } else {
            pendingDescriptors.append(descriptor)
        }
    }

    private func startDownloadsIfNeeded() {
        while ongoingDownloads.count < maximumConcurrentDownloads {
            guard let descriptor = popNextStartablePendingDescriptor() else { return }
            let key = cacheKey(for: descriptor)

            let downloadId = UUID()
            let task = session.downloadTask(with: descriptor.url) { [weak self] tmpURL, response, error in
                guard let self else { return }

                let stagedURL = self.stageDownloadFile(tmpURL, response: response, error: error)
                self.queue.async { [weak self] in
                    self?.finishDownload(
                        descriptor: descriptor,
                        downloadId: downloadId,
                        tmpURL: stagedURL,
                        response: response,
                        error: error
                    )
                }
            }
            task.priority = downloadTaskPriority(forKey: key)
            ongoingDownloads[key] = OngoingDownload(task: task, descriptor: descriptor, id: downloadId)
            task.resume()
        }
    }

    private func popNextStartablePendingDescriptor() -> CollectionCatalogDownloadableMediaDescriptor? {
        var index = 0
        while index < pendingDescriptors.count {
            let descriptor = pendingDescriptors[index]
            let key = cacheKey(for: descriptor)
            let hasActiveFileInterest = hasDemandCallbacksOrRetainedFile(forKey: key)
            let isAllowed = isDescriptorInActiveWindow(descriptor) || hasActiveFileInterest
            if !isAllowed {
                pendingDescriptors.remove(at: index)
                pendingKeys.remove(key)
                continue
            }

            if !foregroundWorkKeys.isEmpty && !isForegroundKey(key) && !hasActiveFileInterest {
                index += 1
                continue
            }

            pendingDescriptors.remove(at: index)
            pendingKeys.remove(key)
            return descriptor
        }
        return nil
    }

    private func finishDownload(
        descriptor: CollectionCatalogDownloadableMediaDescriptor,
        downloadId: UUID,
        tmpURL: URL?,
        response: URLResponse?,
        error: Error?
    ) {
        let key = cacheKey(for: descriptor)
        guard ongoingDownloads[key]?.id == downloadId else {
            if let tmpURL {
                try? FileManager.default.removeItem(at: tmpURL)
            }
            return
        }

        ongoingDownloads.removeValue(forKey: key)

        let callbacks = completions.removeValue(forKey: key) ?? [:]
        let fileCallbacks = fileCompletions.removeValue(forKey: key) ?? [:]
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil,
              (200...299).contains(statusCode),
              let tmpURL else {
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

        guard isDescriptorInActiveWindow(descriptor)
                || !callbacks.isEmpty
                || !fileCallbacks.isEmpty
                || hasRetainedFile(forKey: key) else {
            try? FileManager.default.removeItem(at: tmpURL)
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

        let fileURL = fileURL(for: descriptor)
        var didRemoveExistingItem = false
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            didRemoveExistingItem = removeItemIfPresent(at: fileURL)
            try FileManager.default.moveItem(at: tmpURL, to: fileURL)
            writeDownloadedMediaMetadata(response: response, for: descriptor)
            notifyFileAvailabilityChanged()
        } catch {
            if didRemoveExistingItem {
                try? FileManager.default.removeItem(at: metadataFileURL(for: descriptor))
                notifyFileAvailabilityChanged()
            }
            try? FileManager.default.removeItem(at: tmpURL)
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

        completeFile(fileCallbacks, with: fileURL)

        guard descriptor.isStaticImage else {
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

        let shouldDecodeForPrefetch = shouldKeepDecodedImage(descriptor, key: key)
        guard !callbacks.isEmpty || shouldDecodeForPrefetch else {
            finishForegroundWork(forKey: key)
            return
        }

        if !callbacks.isEmpty {
            completions[key, default: [:]].merge(callbacks) { current, _ in current }
        }
        let decodePriority = imageDecodePriority(forKey: key, hasKnownDemandCallbacks: !callbacks.isEmpty)
        if decodeIdsByKey[key] == nil {
            freshDownloadDecodeKeys.insert(key)
            startImageDecode(
                at: fileURL,
                descriptor: descriptor,
                key: key,
                redownloadOnFailure: false,
                priority: decodePriority
            )
        } else if !callbacks.isEmpty && !freshDownloadDecodeKeys.contains(key) {
            redownloadOnDecodeFailureKeys.insert(key)
            startForegroundDecodeIfNeeded(
                at: fileURL,
                descriptor: descriptor,
                key: key,
                redownloadOnFailure: true
            )
        } else if decodePriority == .foreground {
            startForegroundDecodeIfNeeded(
                at: fileURL,
                descriptor: descriptor,
                key: key,
                redownloadOnFailure: false
            )
        }
        startDownloadsIfNeeded()
    }

    private func startImageDecode(
        at fileURL: URL,
        descriptor: CollectionCatalogDownloadableMediaDescriptor,
        key: String,
        redownloadOnFailure: Bool,
        priority: ImageDecodePriority
    ) {
        let decodeId = UUID()
        decodeIdsByKey[key] = decodeId

        if redownloadOnFailure {
            redownloadOnDecodeFailureKeys.insert(key)
        } else {
            redownloadOnDecodeFailureKeys.remove(key)
        }

        if priority == .foreground {
            foregroundDecodeIdsByKey[key] = decodeId
        }
        enqueueImageDecodeWork(ImageDecodeJob(
            decodeId: decodeId,
            fileURL: fileURL,
            descriptor: descriptor,
            key: key,
            redownloadOnFailure: redownloadOnFailure,
            priority: priority,
            workKind: .primary
        ))
    }

    private func startForegroundDecodeIfNeeded(
        at fileURL: URL,
        descriptor: CollectionCatalogDownloadableMediaDescriptor,
        key: String,
        redownloadOnFailure: Bool
    ) {
        guard let decodeId = decodeIdsByKey[key],
              foregroundDecodeIdsByKey[key] != decodeId else { return }

        foregroundDecodeIdsByKey[key] = decodeId

        // Race the existing prefetch decode on the foreground queue.
        enqueueImageDecodeWork(ImageDecodeJob(
            decodeId: decodeId,
            fileURL: fileURL,
            descriptor: descriptor,
            key: key,
            redownloadOnFailure: redownloadOnFailure,
            priority: .foreground,
            workKind: .foregroundRace
        ))
    }

    private func enqueueImageDecodeWork(_ job: ImageDecodeJob) {
        let decodeQueue = job.priority == .foreground ? foregroundImageDecodeQueue : imageDecodeQueue
        decodeQueue.async { [weak self] in
            let image = Self.loadDecodedImage(at: job.fileURL)
            self?.queue.async { [weak self] in
                self?.finishImageDecode(
                    image,
                    job: job
                )
            }
        }
    }

    private func finishImageDecode(
        _ image: DownloadableMediaImage?,
        job: ImageDecodeJob
    ) {
        if job.priority == .foreground,
           foregroundDecodeIdsByKey[job.key] == job.decodeId {
            foregroundDecodeIdsByKey.removeValue(forKey: job.key)
        }
        guard decodeIdsByKey[job.key] == job.decodeId else { return }

        if job.workKind == .foregroundRace, image == nil {
            guard redownloadOnDecodeFailureKeys.contains(job.key) else {
                return
            }
        }
        decodeIdsByKey.removeValue(forKey: job.key)
        freshDownloadDecodeKeys.remove(job.key)
        let wasRequestedForRedownloadOnFailure = redownloadOnDecodeFailureKeys.remove(job.key) != nil
        let shouldRedownloadOnFailure = job.redownloadOnFailure || wasRequestedForRedownloadOnFailure

        let callbacks = completions.removeValue(forKey: job.key) ?? [:]
        if let image {
            if shouldKeepDecodedImage(job.descriptor, key: job.key) {
                cache(image, for: job.descriptor)
            }
            finishForegroundWork(forKey: job.key, callbacks: callbacks, image: image)
            return
        }

        if hasRetainedFile(forKey: job.key) {
            retainedDecodeFailureDescriptors[job.key] = job.descriptor
            if shouldRedownloadOnFailure, !callbacks.isEmpty {
                completions[job.key, default: [:]].merge(callbacks) { current, _ in current }
            } else {
                finishForegroundWork(forKey: job.key, callbacks: callbacks)
            }
            return
        }

        removeCachedFileAfterDecodeFailure(for: job.descriptor, fileURL: job.fileURL)
        guard shouldRedownloadOnFailure, !callbacks.isEmpty else {
            finishForegroundWork(forKey: job.key, callbacks: callbacks)
            return
        }

        completions[job.key, default: [:]].merge(callbacks) { current, _ in current }
        startForegroundDownload(for: job.descriptor, key: job.key)
        startDownloadsIfNeeded()
    }

    private static func loadDecodedImage(at fileURL: URL) -> DownloadableMediaImage? {
        autoreleasepool {
            guard let image = DownloadableMediaImage(contentsOfFile: fileURL.path) else { return nil }
            return image.decodedForDisplay()
        }
    }

    private func stageDownloadFile(_ tmpURL: URL?, response: URLResponse?, error: Error?) -> URL? {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, (200...299).contains(statusCode), let tmpURL else {
            return nil
        }

        let fileManager = FileManager.default
        let stagedURL = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: false)

        do {
            try fileManager.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try fileManager.moveItem(at: tmpURL, to: stagedURL)
            return stagedURL
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            do {
                try fileManager.copyItem(at: tmpURL, to: stagedURL)
                return stagedURL
            } catch {
                try? fileManager.removeItem(at: stagedURL)
                return nil
            }
        }
    }

    private func pruneForegroundTracking(allowedKeys: Set<String>) {
        var retainedKeys = allowedKeys
        retainedKeys.formUnion(completions.keys)
        retainedKeys.formUnion(fileCompletions.keys)
        if let foregroundKey, !retainedKeys.contains(foregroundKey) {
            self.foregroundKey = nil
        }
        foregroundWorkKeys.formIntersection(retainedKeys)
        updateOngoingDownloadPriorities()
    }

    private func prioritizeForegroundImageIfNeeded(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        requireDecodedStaticImage: Bool
    ) {
        let key = cacheKey(for: descriptor)
        foregroundKey = key
        foregroundWorkKeys.formIntersection([key])
        updateOngoingDownloadPriorities()

        let fileURL = fileURL(for: descriptor)
        let hasFile = FileManager.default.fileExists(atPath: fileURL.path)
        let isReady: Bool
        if descriptor.isStaticImage {
            isReady = cachedDecodedImage(forKey: key) != nil || (!requireDecodedStaticImage && hasFile)
        } else {
            isReady = hasFile
        }
        guard !isReady else {
            markForegroundWorkFinished(forKey: key)
            return
        }

        if hasFile {
            markForegroundWorkStarted(forKey: key)
        } else {
            startForegroundDownload(for: descriptor, key: key)
        }
    }

    private func isForegroundKey(_ key: String) -> Bool {
        foregroundKey == key
    }

    private func hasDemandCallbacks(forKey key: String) -> Bool {
        completions[key]?.isEmpty == false || fileCompletions[key]?.isEmpty == false
    }

    private func hasRetainedFile(forKey key: String) -> Bool {
        (retainedFileKeys[key] ?? 0) > 0
    }

    private func hasDemandCallbacksOrRetainedFile(forKey key: String) -> Bool {
        hasDemandCallbacks(forKey: key) || hasRetainedFile(forKey: key)
    }

    private func isRetainedFileName(_ fileName: String, collectionId: String) -> Bool {
        (retainedFileNameKeys[RetainedFileNameKey(collectionId: collectionId, fileName: fileName)] ?? 0) > 0
    }

    private func releaseRetainedFile(forKey key: String, fileNameKeys: [RetainedFileNameKey]) {
        decrementRetainedCount(for: key, in: &retainedFileKeys)
        for fileNameKey in fileNameKeys {
            decrementRetainedCount(for: fileNameKey, in: &retainedFileNameKeys)
        }
    }

    private func handleRetainedDecodeFailureIfNeeded(forKey key: String) {
        guard let descriptor = retainedDecodeFailureDescriptors.removeValue(forKey: key) else { return }
        removeCachedFileAfterDecodeFailure(for: descriptor, fileURL: fileURL(for: descriptor))

        if completions[key]?.isEmpty == false {
            startForegroundDownload(for: descriptor, key: key)
        } else {
            finishForegroundWork(forKey: key)
        }
    }

    private func removeCachedFileAfterDecodeFailure(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL
    ) {
        if removeItemIfPresent(at: fileURL) {
            try? FileManager.default.removeItem(at: metadataFileURL(for: descriptor))
            notifyFileAvailabilityChanged()
        }
    }

    private func decrementRetainedCount<Key: Hashable>(for value: Key, in counts: inout [Key: Int]) {
        guard let count = counts[value] else { return }
        if count <= 1 {
            counts.removeValue(forKey: value)
        } else {
            counts[value] = count - 1
        }
    }

    private func downloadTaskPriority(forKey key: String) -> Float {
        if isForegroundKey(key) || hasDemandCallbacksOrRetainedFile(forKey: key) {
            return URLSessionTask.highPriority
        }

        return foregroundWorkKeys.isEmpty ? URLSessionTask.defaultPriority : URLSessionTask.lowPriority
    }

    private func imageDecodePriority(
        forKey key: String,
        hasKnownDemandCallbacks: Bool = false
    ) -> ImageDecodePriority {
        let hasDemandCallbacks = hasKnownDemandCallbacks || self.hasDemandCallbacks(forKey: key)
        if isForegroundKey(key) || hasDemandCallbacks {
            return .foreground
        }

        return .prefetch
    }

    private func updateOngoingDownloadPriorities() {
        ongoingDownloads.forEach { key, download in
            download.task.priority = downloadTaskPriority(forKey: key)
        }
    }

    private func markForegroundWorkFinished(forKey key: String) {
        guard foregroundWorkKeys.remove(key) != nil else { return }
        updateOngoingDownloadPriorities()
    }

    private func markForegroundWorkStarted(forKey key: String) {
        foregroundWorkKeys.insert(key)
        updateOngoingDownloadPriorities()
    }

    private func startForegroundDownload(for descriptor: CollectionCatalogDownloadableMediaDescriptor, key: String) {
        markForegroundWorkStarted(forKey: key)
        cancelOngoingPrefetchDownloadsForForeground()
        enqueueDownloadIfNeeded(descriptor, isForegroundRequest: true)
    }

    private func finishForegroundWork(
        forKey key: String,
        callbacks: ImageLoadCompletions = [:],
        image: DownloadableMediaImage? = nil
    ) {
        markForegroundWorkFinished(forKey: key)
        complete(callbacks, with: image)
        startDownloadsIfNeeded()
    }

    private func cancelOngoingPrefetchDownloadsForForeground() {
        let keysToCancel = ongoingDownloads.keys.filter { key in
            !isForegroundKey(key) && !hasDemandCallbacksOrRetainedFile(forKey: key)
        }

        for key in keysToCancel {
            cancelOngoingPrefetchDownloadForForeground(forKey: key)
        }
    }

    private func cancelOngoingPrefetchDownloadForForeground(forKey key: String) {
        guard !isForegroundKey(key),
              !hasDemandCallbacksOrRetainedFile(forKey: key),
              let descriptor = ongoingDownloads[key]?.descriptor else {
            return
        }

        cancelDownload(forKey: key)
        guard isDescriptorInActiveWindow(descriptor) else { return }
        enqueueDownloadIfNeeded(descriptor, isForegroundRequest: false)
    }

    private func decodeCachedImagesIfNeeded(_ descriptors: [CollectionCatalogDownloadableMediaDescriptor]) {
        for descriptor in descriptors {
            let key = cacheKey(for: descriptor)
            guard activeWindow?.decodedKeys.contains(key) == true,
                  cachedDecodedImage(forKey: key) == nil else {
                continue
            }

            let fileURL = fileURL(for: descriptor)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }

            let decodePriority = imageDecodePriority(forKey: key)
            if decodeIdsByKey[key] == nil {
                startImageDecode(
                    at: fileURL,
                    descriptor: descriptor,
                    key: key,
                    redownloadOnFailure: false,
                    priority: decodePriority
                )
            } else if decodePriority == .foreground {
                startForegroundDecodeIfNeeded(
                    at: fileURL,
                    descriptor: descriptor,
                    key: key,
                    redownloadOnFailure: false
                )
            }
        }
    }

    private func prioritizedDownloadDescriptors(
        currentDescriptor: CollectionCatalogDownloadableMediaDescriptor,
        descriptors: [CollectionCatalogDownloadableMediaDescriptor],
        decodedDescriptors: [CollectionCatalogDownloadableMediaDescriptor]
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        var orderedDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
        var usedKeys = Set<String>()

        func appendDescriptor(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
            guard usedKeys.insert(cacheKey(for: descriptor)).inserted else { return }
            orderedDescriptors.append(descriptor)
        }

        appendDescriptor(currentDescriptor)
        decodedDescriptors.forEach(appendDescriptor)
        descriptors.forEach(appendDescriptor)
        return orderedDescriptors
    }

    private func reorderPendingDownloads(preferredDescriptors: [CollectionCatalogDownloadableMediaDescriptor]) {
        guard !pendingDescriptors.isEmpty else { return }

        var pendingDescriptorsByKey = [String: CollectionCatalogDownloadableMediaDescriptor]()
        for descriptor in pendingDescriptors {
            pendingDescriptorsByKey[cacheKey(for: descriptor)] = descriptor
        }

        var reorderedDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
        var usedKeys = Set<String>()

        func appendPendingDescriptor(forKey key: String) {
            guard usedKeys.insert(key).inserted,
                  let descriptor = pendingDescriptorsByKey[key] else {
                return
            }
            reorderedDescriptors.append(descriptor)
        }

        for descriptor in pendingDescriptors {
            let key = cacheKey(for: descriptor)
            if hasDemandCallbacksOrRetainedFile(forKey: key) {
                appendPendingDescriptor(forKey: key)
            }
        }

        for descriptor in preferredDescriptors {
            appendPendingDescriptor(forKey: cacheKey(for: descriptor))
        }

        for descriptor in pendingDescriptors {
            appendPendingDescriptor(forKey: cacheKey(for: descriptor))
        }

        pendingDescriptors = reorderedDescriptors
        pendingKeys = Set(reorderedDescriptors.map { cacheKey(for: $0) })
    }

    private func complete(_ callbacks: ImageLoadCompletions, with image: DownloadableMediaImage?) {
        complete(Array(callbacks.values), with: image)
    }

    private func complete(_ callbacks: [ImageLoadCallback], with image: DownloadableMediaImage?) {
        let activeCallbacks = callbacks.filter { !$0.request.isCancelled }
        guard !activeCallbacks.isEmpty else { return }
        DispatchQueue.main.async {
            activeCallbacks.forEach { callback in
                guard !callback.request.isCancelled else { return }
                callback.completion(image)
            }
        }
    }

    private func completeFile(_ callbacks: FileLoadCompletions, with fileURL: URL?) {
        completeFile(Array(callbacks.values), with: fileURL)
    }

    private func completeFile(_ callbacks: [FileLoadCallback], with fileURL: URL?) {
        let activeCallbacks = callbacks.filter { !$0.request.isCancelled }
        guard !activeCallbacks.isEmpty else { return }
        DispatchQueue.main.async {
            activeCallbacks.forEach { callback in
                guard !callback.request.isCancelled else { return }
                callback.completion(fileURL)
            }
        }
    }

    private func cancelDownloadsOutsideWindow(collectionId: String, allowedKeys: Set<String>) {
        pendingDescriptors.removeAll { descriptor in
            let key = cacheKey(for: descriptor)
            let shouldRemove = descriptor.collectionId == collectionId
                && !allowedKeys.contains(key)
                && !hasDemandCallbacksOrRetainedFile(forKey: key)
            if shouldRemove {
                pendingKeys.remove(key)
                complete(completions.removeValue(forKey: key) ?? [:], with: nil)
                completeFile(fileCompletions.removeValue(forKey: key) ?? [:], with: nil)
            }
            return shouldRemove
        }

        let keysToCancel = ongoingDownloads.compactMap { key, download in
            download.descriptor.collectionId == collectionId
                && !allowedKeys.contains(key)
                && !hasDemandCallbacksOrRetainedFile(forKey: key)
                ? key
                : nil
        }

        for key in keysToCancel {
            cancelDownload(forKey: key)
        }
    }

    private func cancelDownloadsOutsideActiveCollection(collectionId: String) {
        pendingDescriptors.removeAll { descriptor in
            let key = cacheKey(for: descriptor)
            let shouldRemove = descriptor.collectionId != collectionId
                && !hasDemandCallbacksOrRetainedFile(forKey: key)
            if shouldRemove {
                pendingKeys.remove(key)
                complete(completions.removeValue(forKey: key) ?? [:], with: nil)
                completeFile(fileCompletions.removeValue(forKey: key) ?? [:], with: nil)
            }
            return shouldRemove
        }

        let keysToCancel = ongoingDownloads.compactMap { key, download in
            download.descriptor.collectionId != collectionId
                && !hasDemandCallbacksOrRetainedFile(forKey: key)
                ? key
                : nil
        }
        keysToCancel.forEach(cancelDownload)
    }

    private func cancelDownload(forKey key: String) {
        guard let download = ongoingDownloads.removeValue(forKey: key) else { return }
        download.task.cancel()
        complete(completions.removeValue(forKey: key) ?? [:], with: nil)
        completeFile(fileCompletions.removeValue(forKey: key) ?? [:], with: nil)
    }

    @discardableResult
    private func cancelFileWorkIfNoLongerNeeded(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        key: String
    ) -> Bool {
        guard !hasDemandCallbacksOrRetainedFile(forKey: key) else { return false }

        if foregroundKey == key {
            foregroundKey = nil
        }
        markForegroundWorkFinished(forKey: key)

        if !isDescriptorInActiveWindow(descriptor) {
            pendingDescriptors.removeAll { cacheKey(for: $0) == key }
            pendingKeys.remove(key)
            cancelDownload(forKey: key)
        } else if !foregroundWorkKeys.isEmpty {
            cancelOngoingPrefetchDownloadForForeground(forKey: key)
        } else {
            updateOngoingDownloadPriorities()
        }
        return true
    }

    private func cancelUnretainedDownloadsAndPendingWork() {
        let retainedKeys = Set(retainedFileKeys.keys)

        cancelPendingAndOngoingDownloads { !retainedKeys.contains($0) }

        let imageCallbacks = removeAllCallbacks(from: &completions)
        let fileCallbacks = unretainedCallbacks(from: &fileCompletions, retainedKeys: retainedKeys)
        complete(imageCallbacks, with: nil)
        completeFile(fileCallbacks, with: nil)
    }

    private func removeAllCallbacks<Callback>(
        from callbacksByKey: inout [String: [UUID: Callback]]
    ) -> [Callback] {
        let callbacks = callbacksByKey.values.flatMap { $0.values }
        callbacksByKey.removeAll()
        return callbacks
    }

    private func unretainedCallbacks<Callback>(
        from callbacksByKey: inout [String: [UUID: Callback]],
        retainedKeys: Set<String>
    ) -> [Callback] {
        var callbacks = [Callback]()
        for key in Array(callbacksByKey.keys) where !retainedKeys.contains(key) {
            if let removedCallbacks = callbacksByKey.removeValue(forKey: key) {
                callbacks.append(contentsOf: removedCallbacks.values)
            }
        }
        return callbacks
    }

    private func cancelPrefetchDownloadsAndPendingWork() {
        cancelPendingAndOngoingDownloads { !hasDemandCallbacksOrRetainedFile(forKey: $0) }
    }

    private func cancelPendingAndOngoingDownloads(where shouldCancelKey: (String) -> Bool) {
        pendingDescriptors.removeAll { descriptor in
            let key = cacheKey(for: descriptor)
            let shouldCancel = shouldCancelKey(key)
            if shouldCancel {
                pendingKeys.remove(key)
            }
            return shouldCancel
        }

        let keysToCancel = ongoingDownloads.keys.filter(shouldCancelKey)
        keysToCancel.forEach(cancelDownload)
    }

    private func clearActiveWindowState() {
        activeWindow = nil
        foregroundKey = nil
        foregroundWorkKeys.removeAll()
        memoryCache.removeAllObjects()
        memoryKeysByCollection.removeAll()
        cancelPrefetchDownloadsAndPendingWork()
        updateOngoingDownloadPriorities()
        startDownloadsIfNeeded()
    }

    private func evictFilesOutsideWindow(collectionId: String, allowedFileNames: Set<String>) {
        let directory = collectionDirectory(collectionId: collectionId)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        var didRemoveItem = false
        for url in contents where !allowedFileNames.contains(url.lastPathComponent)
            && !isRetainedFileName(url.lastPathComponent, collectionId: collectionId) {
            didRemoveItem = removeItemIfPresent(at: url) || didRemoveItem
        }
        if didRemoveItem {
            notifyFileAvailabilityChanged()
        }
    }

    private func evictMemoryOutsideWindow(collectionId: String, allowedKeys: Set<String>) {
        let existingKeys = memoryKeysByCollection[collectionId] ?? []
        for key in existingKeys where !allowedKeys.contains(key) {
            memoryCache.removeObject(forKey: key as NSString)
        }
        memoryKeysByCollection[collectionId] = existingKeys.intersection(allowedKeys)
    }

    private func evictMemoryOutsideActiveCollection(collectionId: String) {
        for (storedCollectionId, keys) in memoryKeysByCollection where storedCollectionId != collectionId {
            keys.forEach { memoryCache.removeObject(forKey: $0 as NSString) }
        }
        memoryKeysByCollection = memoryKeysByCollection.filter { $0.key == collectionId }
    }

    private func cache(_ image: DownloadableMediaImage, for descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        let key = cacheKey(for: descriptor)
        memoryCache.setObject(image, forKey: key as NSString, cost: estimatedCost(of: image))
        memoryKeysByCollection[descriptor.collectionId, default: []].insert(key)
    }

    private func writeDownloadedMediaMetadata(response: URLResponse?, for descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        let metadataURL = metadataFileURL(for: descriptor)
        let metadata = DownloadedMediaMetadata(sourceURL: response?.url ?? descriptor.url)
        guard let data = try? JSONEncoder().encode(metadata) else {
            try? FileManager.default.removeItem(at: metadataURL)
            return
        }

        do {
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: metadataURL)
        }
    }

    private func estimatedCost(of image: DownloadableMediaImage) -> Int {
#if os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            return max(width * height * 4, 1)
        }
        return max(cgImage.width * cgImage.height * 4, 1)
#else
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(width * height * 4, 1)
#endif
    }

    private func isDescriptorInActiveWindow(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) -> Bool {
        guard let activeWindow,
              activeWindow.collectionId == descriptor.collectionId else {
            return false
        }
        return activeWindow.fileNames.contains(fileName(for: descriptor))
    }

    private func shouldKeepDecodedImage(_ descriptor: CollectionCatalogDownloadableMediaDescriptor, key: String) -> Bool {
        activeWindow?.collectionId == descriptor.collectionId && activeWindow?.decodedKeys.contains(key) == true
    }

    private func cacheKey(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
        "\(descriptor.collectionId)|\(descriptor.tokenIndex)|\(descriptor.tokenId)|\(sourceURLHash(for: descriptor))|\(descriptor.fileExtension)"
    }

    private func cachedDecodedImage(forKey key: String) -> DownloadableMediaImage? {
        memoryCache.object(forKey: key as NSString)
    }

    private func fileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL {
        collectionDirectory(collectionId: descriptor.collectionId).appendingPathComponent(fileName(for: descriptor))
    }

    private func metadataFileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL {
        collectionDirectory(collectionId: descriptor.collectionId).appendingPathComponent(metadataFileName(for: descriptor))
    }

    private func fileNames(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> [String] {
        [fileName(for: descriptor), metadataFileName(for: descriptor)]
    }

    private func fileName(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
        let paddedIndex = String(format: "%06d", descriptor.tokenIndex)
        return "\(paddedIndex)-\(safePathComponent(descriptor.tokenId))-\(sourceURLHash(for: descriptor)).\(descriptor.fileExtension)"
    }

    private func metadataFileName(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
        "\(fileName(for: descriptor)).metadata.json"
    }

    private func collectionDirectory(collectionId: String) -> URL {
        cacheRoot.appendingPathComponent(safePathComponent(collectionId), isDirectory: true)
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars)
    }

    private func sourceURLHash(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in descriptor.url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

#if os(macOS)
fileprivate extension NSImage {
    func decodedForDisplay() -> NSImage {
        guard isValid, size.width > 0, size.height > 0 else { return self }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: max(cgImage.width, 1),
                height: max(cgImage.height, 1),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return self
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let decodedImage = context.makeImage() else { return self }

        let image = NSImage(size: size)
        let representation = NSBitmapImageRep(cgImage: decodedImage)
        representation.size = size
        image.addRepresentation(representation)
        return image
    }
}
#else
fileprivate extension UIImage {
    func decodedForDisplay() -> UIImage {
        guard images == nil, size.width > 0, size.height > 0 else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
