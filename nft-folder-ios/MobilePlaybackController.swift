// ∅ 2026 lil org

import UIKit

protocol MobilePlaybackControllerDisplay: AnyObject {
    
    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentCoordinate() -> (Int, Int)
    
}

enum PlaybackNavigationDirection {
    case up, down, back, forward, nextCollection, restartCollection
}

extension Notification.Name {
    static let solanaImageCacheFileAvailabilityDidChange = Notification.Name("SolanaImageCacheFileAvailabilityDidChange")
}

struct MobileViewingProgress: Codable, Hashable {
    let collectionId: String
    let collectionName: String
    let tokenId: String
    let tokenIndex: Int
    let tokenCount: Int
    let updatedAt: Date
    var hasViewedToEnd: Bool

    init(
        collectionId: String,
        collectionName: String,
        tokenId: String,
        tokenIndex: Int,
        tokenCount: Int,
        updatedAt: Date,
        hasViewedToEnd: Bool = false
    ) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.tokenId = tokenId
        self.tokenIndex = tokenIndex
        self.tokenCount = tokenCount
        self.updatedAt = updatedAt
        self.hasViewedToEnd = hasViewedToEnd
    }

    enum CodingKeys: String, CodingKey {
        case collectionId
        case collectionName
        case tokenId
        case tokenIndex
        case tokenCount
        case updatedAt
        case hasViewedToEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collectionId = try container.decode(String.self, forKey: .collectionId)
        collectionName = try container.decode(String.self, forKey: .collectionName)
        tokenId = try container.decode(String.self, forKey: .tokenId)
        tokenIndex = try container.decode(Int.self, forKey: .tokenIndex)
        tokenCount = try container.decode(Int.self, forKey: .tokenCount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        hasViewedToEnd = try container.decodeIfPresent(Bool.self, forKey: .hasViewedToEnd) ?? false
    }

    var fraction: Double {
        guard tokenCount > 0 else { return 0 }
        return min(max(Double(tokenIndex + 1) / Double(tokenCount), 0), 1)
    }

    var percent: Int {
        guard fraction > 0 else { return 0 }
        guard !isComplete else { return 100 }
        return min(max(Int((fraction * 100).rounded(.up)), 1), 99)
    }

    var isComplete: Bool {
        tokenCount > 0 && tokenIndex >= tokenCount - 1
    }

    var hasBeenViewedToEnd: Bool {
        hasViewedToEnd || isComplete
    }

    var pageLabel: String {
        guard tokenCount > 0 else { return "" }
        return Strings.pagePosition(current: tokenIndex + 1, total: tokenCount)
    }
}

struct MobilePlayerImageShareItem {
    let fileURL: URL
    let previewTitle: String
    let previewImage: () -> UIImage?
}

extension MobilePlayerImageShareItem {
    static func previewTitle(for token: GeneratedToken, progressText: String) -> String {
        let trimmedCollectionName = token.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = token.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle: String
        if !trimmedCollectionName.isEmpty {
            baseTitle = trimmedCollectionName
        } else if !trimmedDisplayName.isEmpty {
            baseTitle = trimmedDisplayName
        } else {
            baseTitle = Strings.nftFolder
        }
        let trimmedProgressText = progressText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedProgressText.isEmpty ? baseTitle : "\(baseTitle) \(trimmedProgressText)"
    }
}

enum MobileViewingProgressStore {
    private static let progressKey = "mobileViewingProgressByCollectionId"
    private static let continueViewingCollectionIdKey = "mobileContinueViewingCollectionId"
    private static let userDefaults = UserDefaults.standard
    private static var cachedProgressByCollectionId: [String: MobileViewingProgress]?
    private static var cachedProgressData: Data?

    static func save(_ progress: MobileViewingProgress) {
        var allProgress = allProgressByCollectionId()
        var updatedProgress = progress
        updatedProgress.hasViewedToEnd = progress.hasBeenViewedToEnd || allProgress[progress.collectionId]?.hasBeenViewedToEnd == true
        allProgress[progress.collectionId] = updatedProgress
        save(allProgress)
    }

    static func progressSnapshot() -> (
        percentagesByCollectionId: [String: Int],
        viewedToEndCollectionIds: Set<String>,
        continueViewingProgress: MobileViewingProgress?
    ) {
        let progressByCollectionId = allProgressByCollectionId()
        let viewedToEndCollectionIds = Set(progressByCollectionId.compactMap { collectionId, progress in
            progress.hasBeenViewedToEnd ? collectionId : nil
        })
        return (
            progressByCollectionId.mapValues(\.percent),
            viewedToEndCollectionIds,
            continueViewingProgress(in: progressByCollectionId)
        )
    }

    static func progress(collectionId: String) -> MobileViewingProgress? {
        allProgressByCollectionId()[collectionId]
    }

    static func setContinueViewingCollectionId(_ collectionId: String) {
        userDefaults.set(collectionId, forKey: continueViewingCollectionIdKey)
    }

    static func clearContinueViewingCollectionId() {
        userDefaults.removeObject(forKey: continueViewingCollectionIdKey)
    }

    private static func continueViewingProgress(in progressByCollectionId: [String: MobileViewingProgress]) -> MobileViewingProgress? {
        guard let collectionId = userDefaults.string(forKey: continueViewingCollectionIdKey),
              let progress = progressByCollectionId[collectionId],
              !progress.isComplete else {
            return nil
        }
        return progress
    }

    private static func allProgressByCollectionId() -> [String: MobileViewingProgress] {
        let storedData = userDefaults.data(forKey: progressKey)
        if let cachedProgressByCollectionId, cachedProgressData == storedData {
            return cachedProgressByCollectionId
        }

        guard let storedData,
              let progress = try? JSONDecoder().decode([String: MobileViewingProgress].self, from: storedData) else {
            cachedProgressByCollectionId = [:]
            cachedProgressData = storedData
            return [:]
        }
        cachedProgressByCollectionId = progress
        cachedProgressData = storedData
        return progress
    }

    private static func save(_ progress: [String: MobileViewingProgress]) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        cachedProgressByCollectionId = progress
        cachedProgressData = data
        userDefaults.set(data, forKey: progressKey)
    }
}

private struct MobileBookmark: Codable, Hashable {
    let bookmarkedAt: Date
}

enum MobileBookmarksStore {
    private static let bookmarksKey = "mobileBookmarksByCollectionId"
    private static let userDefaults = UserDefaults.standard
    private static var cachedBookmarksByCollectionId: [String: [String: MobileBookmark]]?
    private static var cachedBookmarksData: Data?

    private struct LegacyMobileBookmark: Codable {
        let tokenId: String
        let bookmarkedAt: Date
    }

    static func isBookmarked(collectionId: String, tokenId: String) -> Bool {
        bookmarksByCollectionId()[collectionId]?[tokenId] != nil
    }

    @discardableResult
    static func toggleBookmark(collectionId: String, tokenId: String) -> Bool {
        guard !collectionId.isEmpty, !tokenId.isEmpty else { return false }

        var bookmarks = bookmarksByCollectionId()
        var collectionBookmarks = bookmarks[collectionId] ?? [:]
        if collectionBookmarks[tokenId] != nil {
            collectionBookmarks.removeValue(forKey: tokenId)
            if collectionBookmarks.isEmpty {
                bookmarks.removeValue(forKey: collectionId)
            } else {
                bookmarks[collectionId] = collectionBookmarks
            }
            save(bookmarks)
            return false
        }

        collectionBookmarks[tokenId] = MobileBookmark(bookmarkedAt: Date())
        bookmarks[collectionId] = collectionBookmarks
        save(bookmarks)
        return true
    }

    private static func bookmarksByCollectionId() -> [String: [String: MobileBookmark]] {
        let storedData = userDefaults.data(forKey: bookmarksKey)
        if let cachedBookmarksByCollectionId, cachedBookmarksData == storedData {
            return cachedBookmarksByCollectionId
        }

        guard let storedData else {
            cachedBookmarksByCollectionId = [:]
            cachedBookmarksData = storedData
            return [:]
        }

        if let bookmarks = try? JSONDecoder().decode([String: [String: MobileBookmark]].self, from: storedData) {
            cachedBookmarksByCollectionId = bookmarks
            cachedBookmarksData = storedData
            return bookmarks
        }

        if let legacyBookmarks = try? JSONDecoder().decode([String: LegacyMobileBookmark].self, from: storedData) {
            let bookmarks = legacyBookmarks.reduce(into: [String: [String: MobileBookmark]]()) { result, entry in
                guard !entry.value.tokenId.isEmpty else { return }
                result[entry.key, default: [:]][entry.value.tokenId] = MobileBookmark(bookmarkedAt: entry.value.bookmarkedAt)
            }
            save(bookmarks)
            return bookmarks
        }

        cachedBookmarksByCollectionId = [:]
        cachedBookmarksData = storedData
        return [:]
    }

    private static func save(_ bookmarks: [String: [String: MobileBookmark]]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        cachedBookmarksByCollectionId = bookmarks
        cachedBookmarksData = data
        userDefaults.set(data, forKey: bookmarksKey)
    }
}

class MobilePlaybackController {
    
    private init() {}
    
    static let shared = MobilePlaybackController()
    
    private var displays = [UUID: MobilePlaybackControllerDisplay]()
    private var initialConfigs = [UUID: MobilePlayerConfig]()
    private var tokensDataSources = [UUID: GeneratedTokensDataSource]()
    private var restartSuppressedCollectionIds = [UUID: String]()
    
    func showNewToken(displayId: UUID, token: GeneratedToken, sameCollection: Bool, coordinate: PlayerCoordinate) {
        guard let dataSource = tokensDataSources[displayId] else { return }
        dataSource.pushToken(token, coordinate: coordinate, sameCollection: sameCollection)
        if sameCollection {
            goForward(uuid: displayId)
        } else {
            goDown(uuid: displayId)
        }
    }
    
    func goForward(uuid: UUID) {
        navigate(.forward, uuid: uuid)
    }
    
    func goBack(uuid: UUID) {
        navigate(.back, uuid: uuid)
    }
    
    func goUp(uuid: UUID) {
        navigate(.up, uuid: uuid)
    }
    
    func goDown(uuid: UUID) {
        navigate(.down, uuid: uuid)
    }

    func changeCollection(uuid: UUID) {
        navigate(.nextCollection, uuid: uuid)
    }

    func restartCollection(uuid: UUID) {
        suppressContinueViewingUntilMovementAfterRestart(uuid: uuid)
        navigate(.restartCollection, uuid: uuid)
    }

    private func navigate(_ direction: PlaybackNavigationDirection, uuid: UUID) {
        displays[uuid]?.navigate(direction)
    }
    
    func subscribe(config: MobilePlayerConfig, display: MobilePlaybackControllerDisplay) {
        displays[config.id] = display
        initialConfigs[config.id] = config
    }
    
    func stopAndDisconnect(uuid: UUID) {
        displays.removeValue(forKey: uuid)
        initialConfigs.removeValue(forKey: uuid)
        tokensDataSources.removeValue(forKey: uuid)
        restartSuppressedCollectionIds.removeValue(forKey: uuid)
        if displays.isEmpty {
            SolanaImageCache.shared.cancelAllDownloads()
        }
    }
    
    func getToken(uuid: UUID, coordinate: PlayerCoordinate) -> GeneratedToken {
        dataSource(uuid: uuid)?.getToken(coordinate: coordinate) ?? .empty
    }

    func canRender(uuid: UUID, coordinate: PlayerCoordinate) -> Bool {
        dataSource(uuid: uuid)?.canRender(coordinate: coordinate) ?? false
    }

    func prepareSolanaImageWindow(
        uuid: UUID,
        coordinate: PlayerCoordinate,
        direction: SolanaImageCache.PrefetchDirection
    ) -> SolanaImageDescriptor? {
        guard let context = dataSource(uuid: uuid)?.collectionTokenContext(coordinate: coordinate) else {
            return nil
        }

        guard MobileCollectionCatalog.isSolanaCollection(specificCollectionId: context.collectionId) else {
            return nil
        }

        let orderedIndices = SolanaImageCache.orderedWindowIndices(
            currentIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
        var currentDescriptor: SolanaImageDescriptor?
        let descriptors = orderedIndices.compactMap { tokenIndex in
            let descriptor = MobileCollectionCatalog.solanaImageDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: tokenIndex
            )
            if tokenIndex == context.tokenIndex {
                currentDescriptor = descriptor
            }
            return descriptor
        }
        SolanaImageCache.shared.prepareWindow(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            descriptors: descriptors,
            direction: direction
        )
        return currentDescriptor
    }

    func adjacentSolanaImageDescriptor(
        uuid: UUID,
        coordinate: PlayerCoordinate,
        direction: SolanaImageCache.PrefetchDirection
    ) -> SolanaImageDescriptor? {
        guard let context = dataSource(uuid: uuid)?.collectionTokenContext(coordinate: coordinate),
              MobileCollectionCatalog.isSolanaCollection(specificCollectionId: context.collectionId) else {
            return nil
        }

        let targetTokenIndex: Int
        switch direction {
        case .forward:
            targetTokenIndex = context.tokenIndex + 1
        case .backward:
            targetTokenIndex = context.tokenIndex - 1
        }

        guard targetTokenIndex >= 0, targetTokenIndex < context.tokenCount else { return nil }
        return MobileCollectionCatalog.solanaImageDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: targetTokenIndex
        )
    }

    func markViewed(uuid: UUID, coordinate: PlayerCoordinate) -> MobileViewingProgress? {
        guard let progress = dataSource(uuid: uuid)?.progress(coordinate: coordinate) else { return nil }
        MobileViewingProgressStore.save(progress)
        updateContinueViewingCollection(for: progress, uuid: uuid)
        return progress
    }

    func downloadedStaticImageShareItem(uuid: UUID, coordinate: PlayerCoordinate) -> MobilePlayerImageShareItem? {
        guard let dataSource = dataSource(uuid: uuid),
              let context = dataSource.collectionTokenContext(coordinate: coordinate),
              let descriptor = MobileCollectionCatalog.solanaImageDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: context.tokenIndex
              ),
              descriptor.isStaticImage else {
            return nil
        }

        guard let fileURL = SolanaImageCache.shared.localFileURL(for: descriptor) else { return nil }
        let token = dataSource.getToken(coordinate: coordinate)
        return MobilePlayerImageShareItem(
            fileURL: fileURL,
            previewTitle: MobilePlayerImageShareItem.previewTitle(
                for: token,
                progressText: Strings.pagePosition(current: context.tokenIndex + 1, total: context.tokenCount)
            )
        ) {
            SolanaImageCache.shared.cachedDecodedImage(for: descriptor)
        }
    }

    private func updateContinueViewingCollection(for progress: MobileViewingProgress, uuid: UUID) {
        if let suppressedCollectionId = restartSuppressedCollectionIds[uuid] {
            guard progress.collectionId == suppressedCollectionId else {
                restartSuppressedCollectionIds.removeValue(forKey: uuid)
                MobileViewingProgressStore.clearContinueViewingCollectionId()
                return
            }

            guard progress.tokenIndex > 0 else {
                MobileViewingProgressStore.clearContinueViewingCollectionId()
                return
            }

            restartSuppressedCollectionIds.removeValue(forKey: uuid)
        }

        guard let continueViewingCollectionId = initialConfigs[uuid]?.continueViewingCollectionId,
              progress.collectionId == continueViewingCollectionId,
              !progress.isComplete else {
            MobileViewingProgressStore.clearContinueViewingCollectionId()
            return
        }

        MobileViewingProgressStore.setContinueViewingCollectionId(progress.collectionId)
    }

    private func suppressContinueViewingUntilMovementAfterRestart(uuid: UUID) {
        guard let coordinate = displays[uuid]?.getCurrentCoordinate(),
              let progress = dataSource(uuid: uuid)?.progress(coordinate: PlayerCoordinate(x: coordinate.0, y: coordinate.1)) else {
            restartSuppressedCollectionIds.removeValue(forKey: uuid)
            return
        }

        restartSuppressedCollectionIds[uuid] = progress.collectionId
        MobileViewingProgressStore.clearContinueViewingCollectionId()
    }

    func startHorizontalCoordinate(uuid: UUID, verticalIndex: Int) -> Int {
        dataSource(uuid: uuid)?.horizontalCoordinateForTokenIndex(0, verticalIndex: verticalIndex) ?? 0
    }

    private func dataSource(uuid: UUID) -> GeneratedTokensDataSource? {
        guard let initialConfig = initialConfigs[uuid] else { return nil }
        if let dataSource = tokensDataSources[uuid] {
            return dataSource
        }

        let newDataSource = GeneratedTokensDataSource(
            initialCollectionId: initialConfig.initialItemId,
            specificInitialToken: initialConfig.specificToken,
            initialTokenId: initialConfig.initialTokenId
        )
        tokensDataSources[uuid] = newDataSource
        return newDataSource
    }

}

final class SolanaImageCache {

    enum PrefetchDirection {
        case forward, backward
    }

    static let shared = SolanaImageCache()

    private static let windowRadius = 10
    private static let decodedPreferredRadius = 3
    private static let decodedOppositeRadius = 1
    private static let decodedWindowCapacity = decodedPreferredRadius + decodedOppositeRadius + 1
    private static let webViewHTMLDirectoryName = "_WebViewHTML"

    static func orderedWindowIndices(currentIndex: Int, tokenCount: Int, direction: PrefetchDirection) -> [Int] {
        guard tokenCount > 0 else { return [] }

        let forwardStart = currentIndex + 1
        let forwardEnd = min(currentIndex + windowRadius, tokenCount - 1)
        let forwardIndices = forwardStart <= forwardEnd ? Array(forwardStart...forwardEnd) : []

        let backwardStart = currentIndex - 1
        let backwardEnd = max(currentIndex - windowRadius, 0)
        let backwardIndices = backwardStart >= backwardEnd
            ? stride(from: backwardStart, through: backwardEnd, by: -1).map { $0 }
            : []

        switch direction {
        case .forward:
            return [currentIndex] + forwardIndices + backwardIndices
        case .backward:
            return [currentIndex] + backwardIndices + forwardIndices
        }
    }

    private let queue = DispatchQueue(label: "org.lil.nft-folder.solana-image-cache", qos: .utility)
    private let imageDecodeQueue = DispatchQueue(label: "org.lil.nft-folder.solana-image-cache.decode", qos: .utility)
    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let cacheRoot: URL
    private let stagingRoot: URL
    private let maximumConcurrentDownloads = 4

    private struct OngoingDownload {
        let task: URLSessionDownloadTask
        let descriptor: SolanaImageDescriptor
        let id: UUID
    }

    private var activeCollectionId: String?
    private var activeFileNames = Set<String>()
    private var activeDecodedKeys = Set<String>()
    private var memoryKeysByCollection = [String: Set<String>]()
    private var pendingDescriptors = [SolanaImageDescriptor]()
    private var pendingKeys = Set<String>()
    private var ongoingDownloads = [String: OngoingDownload]()
    private var decodingKeys = Set<String>()
    private var freshDownloadDecodeKeys = Set<String>()
    private var redownloadOnDecodeFailureKeys = Set<String>()
    private var completions = [String: [(UIImage?) -> Void]]()
    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = maximumConcurrentDownloads
        session = URLSession(configuration: configuration)
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheRoot = cachesDirectory.appendingPathComponent("SolanaTokenImages", isDirectory: true)
        stagingRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SolanaTokenImages", isDirectory: true)
        try? FileManager.default.removeItem(
            at: cacheRoot.appendingPathComponent(Self.webViewHTMLDirectoryName, isDirectory: true)
        )
        memoryCache.countLimit = Self.decodedWindowCapacity
        memoryCache.totalCostLimit = 128 * 1024 * 1024

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clearMemoryCache()
        }
    }

    func prepareWindow(
        collectionId: String,
        currentTokenIndex: Int,
        descriptors: [SolanaImageDescriptor],
        direction: PrefetchDirection
    ) {
        let staticDescriptors = descriptors.filter(\.isStaticImage)
        queue.async { [weak self] in
            guard let self else { return }

            let didChangeCollection = self.activeCollectionId != collectionId
            if didChangeCollection {
                self.activeCollectionId = collectionId
                self.cancelDownloadsOutsideActiveCollection(collectionId: collectionId)
                self.evictFilesOutsideActiveCollection(collectionId: collectionId)
                self.evictMemoryOutsideActiveCollection(collectionId: collectionId)
            }

            let allowedFileNames = Set(descriptors.map(self.fileName(for:)))
            let allowedKeys = Set(descriptors.map(self.cacheKey(for:)))
            let decodedDescriptors = self.decodedWindowDescriptors(
                from: staticDescriptors,
                currentTokenIndex: currentTokenIndex,
                direction: direction
            )
            let decodedKeys = Set(decodedDescriptors.map(self.cacheKey(for:)))
            if didChangeCollection || self.activeFileNames != allowedFileNames {
                self.activeFileNames = allowedFileNames
                self.evictFilesOutsideWindow(collectionId: collectionId, allowedFileNames: allowedFileNames)
                self.cancelDownloadsOutsideWindow(collectionId: collectionId, allowedKeys: allowedKeys)
            }
            if didChangeCollection || self.activeDecodedKeys != decodedKeys {
                self.activeDecodedKeys = decodedKeys
                self.evictMemoryOutsideWindow(collectionId: collectionId, allowedKeys: decodedKeys)
                self.decodeCachedImagesIfNeeded(decodedDescriptors)
            }

            let downloadDescriptors = self.prioritizedDownloadDescriptors(
                currentTokenIndex: currentTokenIndex,
                descriptors: descriptors,
                decodedDescriptors: decodedDescriptors
            )
            for descriptor in downloadDescriptors {
                self.enqueueDownloadIfNeeded(descriptor, priority: false)
            }
            self.reorderPendingDownloads(preferredDescriptors: downloadDescriptors)
            self.startDownloadsIfNeeded()
        }
    }

    func cancelAllDownloads() {
        queue.async { [weak self] in
            guard let self else { return }

            self.pendingDescriptors.removeAll()
            self.pendingKeys.removeAll()

            self.ongoingDownloads.values.forEach { $0.task.cancel() }
            self.ongoingDownloads.removeAll()
            self.decodingKeys.removeAll()
            self.freshDownloadDecodeKeys.removeAll()
            self.redownloadOnDecodeFailureKeys.removeAll()
            self.memoryCache.removeAllObjects()
            self.memoryKeysByCollection.removeAll()

            let callbacks = self.completions.values.flatMap { $0 }
            self.completions.removeAll()
            self.complete(callbacks, with: nil)
            self.activeCollectionId = nil
            self.activeFileNames.removeAll()
            self.activeDecodedKeys.removeAll()
        }
    }

    func loadImage(for descriptor: SolanaImageDescriptor, completion: @escaping (UIImage?) -> Void) {
        guard descriptor.isStaticImage else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        queue.async { [weak self] in
            guard let self else { return }

            let key = self.cacheKey(for: descriptor)
            if let cachedImage = self.cachedDecodedImage(forKey: key) {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }

            let fileURL = self.fileURL(for: descriptor)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                self.completions[key, default: []].append(completion)
                if self.decodingKeys.insert(key).inserted {
                    self.decodeImage(
                        at: fileURL,
                        descriptor: descriptor,
                        key: key,
                        redownloadOnFailure: true
                    )
                } else if !self.freshDownloadDecodeKeys.contains(key) {
                    self.redownloadOnDecodeFailureKeys.insert(key)
                }
                return
            }

            self.completions[key, default: []].append(completion)
            self.enqueueDownloadIfNeeded(descriptor, priority: true)
            self.startDownloadsIfNeeded()
        }
    }

    func loadImage(for token: GeneratedToken, completion: @escaping (UIImage?) -> Void) {
        guard let tokenIndex = MobileCollectionCatalog.tokenIndex(
            specificCollectionId: token.fullCollectionId,
            tokenId: token.id
        ),
              let descriptor = MobileCollectionCatalog.solanaImageDescriptor(
                specificCollectionId: token.fullCollectionId,
                tokenIndex: tokenIndex
              ) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        loadImage(for: descriptor, completion: completion)
    }

    func localFileURL(for descriptor: SolanaImageDescriptor) -> URL? {
        let url = fileURL(for: descriptor)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func cachedDecodedImage(for descriptor: SolanaImageDescriptor) -> UIImage? {
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
            NotificationCenter.default.post(name: .solanaImageCacheFileAvailabilityDidChange, object: nil)
        }
    }

    @discardableResult
    private func removeItemIfPresent(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        do {
            try FileManager.default.removeItem(at: url)
            return true
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

    private func enqueueDownloadIfNeeded(_ descriptor: SolanaImageDescriptor, priority: Bool) {
        let key = cacheKey(for: descriptor)
        guard ongoingDownloads[key] == nil else { return }
        guard !FileManager.default.fileExists(atPath: fileURL(for: descriptor).path) else { return }

        if pendingKeys.contains(key) {
            guard priority else { return }
            pendingDescriptors.removeAll { cacheKey(for: $0) == key }
            pendingDescriptors.insert(descriptor, at: 0)
            return
        }

        pendingKeys.insert(key)
        if priority {
            pendingDescriptors.insert(descriptor, at: 0)
        } else {
            pendingDescriptors.append(descriptor)
        }
    }

    private func startDownloadsIfNeeded() {
        while ongoingDownloads.count < maximumConcurrentDownloads, !pendingDescriptors.isEmpty {
            let descriptor = pendingDescriptors.removeFirst()
            let key = cacheKey(for: descriptor)
            pendingKeys.remove(key)

            guard isDescriptorInActiveWindow(descriptor) || completions[key]?.isEmpty == false else {
                continue
            }

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
            ongoingDownloads[key] = OngoingDownload(task: task, descriptor: descriptor, id: downloadId)
            task.resume()
        }
    }

    private func finishDownload(
        descriptor: SolanaImageDescriptor,
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

        let callbacks = completions.removeValue(forKey: key) ?? []
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil,
              (200...299).contains(statusCode),
              let tmpURL else {
            complete(callbacks, with: nil)
            startDownloadsIfNeeded()
            return
        }

        guard isDescriptorInActiveWindow(descriptor) || !callbacks.isEmpty else {
            try? FileManager.default.removeItem(at: tmpURL)
            complete(callbacks, with: nil)
            startDownloadsIfNeeded()
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
            notifyFileAvailabilityChanged()
        } catch {
            if didRemoveExistingItem {
                notifyFileAvailabilityChanged()
            }
            try? FileManager.default.removeItem(at: tmpURL)
            complete(callbacks, with: nil)
            startDownloadsIfNeeded()
            return
        }

        guard descriptor.isStaticImage else {
            complete(callbacks, with: nil)
            startDownloadsIfNeeded()
            return
        }

        let shouldDecodeForPrefetch = shouldKeepDecodedImage(descriptor, key: key)
        guard !callbacks.isEmpty || shouldDecodeForPrefetch else {
            startDownloadsIfNeeded()
            return
        }

        if !callbacks.isEmpty {
            completions[key, default: []].append(contentsOf: callbacks)
        }
        if decodingKeys.insert(key).inserted {
            freshDownloadDecodeKeys.insert(key)
            decodeImage(
                at: fileURL,
                descriptor: descriptor,
                key: key,
                redownloadOnFailure: false
            )
        } else if !callbacks.isEmpty && !freshDownloadDecodeKeys.contains(key) {
            redownloadOnDecodeFailureKeys.insert(key)
        }
        startDownloadsIfNeeded()
    }

    private func decodeImage(
        at fileURL: URL,
        descriptor: SolanaImageDescriptor,
        key: String,
        redownloadOnFailure: Bool
    ) {
        if redownloadOnFailure {
            redownloadOnDecodeFailureKeys.insert(key)
        } else {
            redownloadOnDecodeFailureKeys.remove(key)
        }

        imageDecodeQueue.async { [weak self] in
            let image = Self.loadDecodedImage(at: fileURL)
            self?.queue.async { [weak self] in
                self?.finishImageDecode(
                    image,
                    fileURL: fileURL,
                    descriptor: descriptor,
                    key: key,
                    redownloadOnFailure: redownloadOnFailure
                )
            }
        }
    }

    private func finishImageDecode(
        _ image: UIImage?,
        fileURL: URL,
        descriptor: SolanaImageDescriptor,
        key: String,
        redownloadOnFailure: Bool
    ) {
        guard decodingKeys.remove(key) != nil else { return }
        freshDownloadDecodeKeys.remove(key)
        let wasRequestedForRedownloadOnFailure = redownloadOnDecodeFailureKeys.remove(key) != nil
        let shouldRedownloadOnFailure = redownloadOnFailure || wasRequestedForRedownloadOnFailure

        let callbacks = completions.removeValue(forKey: key) ?? []
        if let image {
            if shouldKeepDecodedImage(descriptor, key: key) {
                cache(image, for: descriptor)
            }
            complete(callbacks, with: image)
            return
        }

        if removeItemIfPresent(at: fileURL) {
            notifyFileAvailabilityChanged()
        }
        guard shouldRedownloadOnFailure, !callbacks.isEmpty else {
            complete(callbacks, with: nil)
            return
        }

        completions[key, default: []].append(contentsOf: callbacks)
        enqueueDownloadIfNeeded(descriptor, priority: true)
        startDownloadsIfNeeded()
    }

    private static func loadDecodedImage(at fileURL: URL) -> UIImage? {
        autoreleasepool {
            guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }
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

    private func decodedWindowDescriptors(
        from descriptors: [SolanaImageDescriptor],
        currentTokenIndex: Int,
        direction: PrefetchDirection
    ) -> [SolanaImageDescriptor] {
        let preferredDescriptors: [SolanaImageDescriptor]
        let oppositeDescriptors: [SolanaImageDescriptor]

        switch direction {
        case .forward:
            preferredDescriptors = descriptors.filter {
                $0.tokenIndex > currentTokenIndex && $0.tokenIndex - currentTokenIndex <= Self.decodedPreferredRadius
            }
            oppositeDescriptors = descriptors.filter {
                currentTokenIndex > $0.tokenIndex && currentTokenIndex - $0.tokenIndex <= Self.decodedOppositeRadius
            }
        case .backward:
            preferredDescriptors = descriptors.filter {
                currentTokenIndex > $0.tokenIndex && currentTokenIndex - $0.tokenIndex <= Self.decodedPreferredRadius
            }
            oppositeDescriptors = descriptors.filter {
                $0.tokenIndex > currentTokenIndex && $0.tokenIndex - currentTokenIndex <= Self.decodedOppositeRadius
            }
        }

        let currentDescriptor = descriptors.first { $0.tokenIndex == currentTokenIndex }.map { [$0] } ?? []
        return currentDescriptor + preferredDescriptors + oppositeDescriptors
    }

    private func decodeCachedImagesIfNeeded(_ descriptors: [SolanaImageDescriptor]) {
        for descriptor in descriptors {
            let key = cacheKey(for: descriptor)
            guard activeDecodedKeys.contains(key),
                  cachedDecodedImage(forKey: key) == nil else {
                continue
            }

            let fileURL = fileURL(for: descriptor)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  decodingKeys.insert(key).inserted else {
                continue
            }

            decodeImage(
                at: fileURL,
                descriptor: descriptor,
                key: key,
                redownloadOnFailure: false
            )
        }
    }

    private func prioritizedDownloadDescriptors(
        currentTokenIndex: Int,
        descriptors: [SolanaImageDescriptor],
        decodedDescriptors: [SolanaImageDescriptor]
    ) -> [SolanaImageDescriptor] {
        var orderedDescriptors = [SolanaImageDescriptor]()
        var usedKeys = Set<String>()

        func appendDescriptor(_ descriptor: SolanaImageDescriptor) {
            guard usedKeys.insert(cacheKey(for: descriptor)).inserted else { return }
            orderedDescriptors.append(descriptor)
        }

        if let currentDescriptor = descriptors.first(where: { $0.tokenIndex == currentTokenIndex }) {
            appendDescriptor(currentDescriptor)
        }
        decodedDescriptors.forEach(appendDescriptor)
        descriptors.forEach(appendDescriptor)
        return orderedDescriptors
    }

    private func reorderPendingDownloads(preferredDescriptors: [SolanaImageDescriptor]) {
        guard !pendingDescriptors.isEmpty else { return }

        var pendingDescriptorsByKey = [String: SolanaImageDescriptor]()
        for descriptor in pendingDescriptors {
            pendingDescriptorsByKey[cacheKey(for: descriptor)] = descriptor
        }

        var reorderedDescriptors = [SolanaImageDescriptor]()
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
            if completions[key]?.isEmpty == false {
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

    private func complete(_ callbacks: [(UIImage?) -> Void], with image: UIImage?) {
        guard !callbacks.isEmpty else { return }
        DispatchQueue.main.async {
            callbacks.forEach { $0(image) }
        }
    }

    private func cancelDownloadsOutsideWindow(collectionId: String, allowedKeys: Set<String>) {
        pendingDescriptors.removeAll { descriptor in
            let key = cacheKey(for: descriptor)
            let shouldRemove = descriptor.collectionId == collectionId && !allowedKeys.contains(key)
            if shouldRemove {
                pendingKeys.remove(key)
                complete(completions.removeValue(forKey: key) ?? [], with: nil)
            }
            return shouldRemove
        }

        let keysToCancel = ongoingDownloads.compactMap { key, download in
            download.descriptor.collectionId == collectionId && !allowedKeys.contains(key) ? key : nil
        }

        for key in keysToCancel {
            cancelDownload(forKey: key)
        }
    }

    private func cancelDownloadsOutsideActiveCollection(collectionId: String) {
        pendingDescriptors.removeAll { descriptor in
            let key = cacheKey(for: descriptor)
            let shouldRemove = descriptor.collectionId != collectionId
            if shouldRemove {
                pendingKeys.remove(key)
                complete(completions.removeValue(forKey: key) ?? [], with: nil)
            }
            return shouldRemove
        }

        let keysToCancel = ongoingDownloads.compactMap { key, download in
            download.descriptor.collectionId == collectionId ? nil : key
        }
        keysToCancel.forEach(cancelDownload)
    }

    private func cancelDownload(forKey key: String) {
        guard let download = ongoingDownloads.removeValue(forKey: key) else { return }
        download.task.cancel()
        complete(completions.removeValue(forKey: key) ?? [], with: nil)
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
        for url in contents where !allowedFileNames.contains(url.lastPathComponent) {
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

    private func evictFilesOutsideActiveCollection(collectionId: String) {
        let activeDirectoryName = safePathComponent(collectionId)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        var didRemoveItem = false
        for url in contents {
            guard url.lastPathComponent != activeDirectoryName,
                  url.lastPathComponent != Self.webViewHTMLDirectoryName else {
                continue
            }

            didRemoveItem = removeItemIfPresent(at: url) || didRemoveItem
        }
        if didRemoveItem {
            notifyFileAvailabilityChanged()
        }
    }

    private func evictMemoryOutsideActiveCollection(collectionId: String) {
        for (storedCollectionId, keys) in memoryKeysByCollection where storedCollectionId != collectionId {
            keys.forEach { memoryCache.removeObject(forKey: $0 as NSString) }
        }
        memoryKeysByCollection = memoryKeysByCollection.filter { $0.key == collectionId }
    }

    private func cache(_ image: UIImage, for descriptor: SolanaImageDescriptor) {
        let key = cacheKey(for: descriptor)
        memoryCache.setObject(image, forKey: key as NSString, cost: estimatedCost(of: image))
        memoryKeysByCollection[descriptor.collectionId, default: []].insert(key)
    }

    private func estimatedCost(of image: UIImage) -> Int {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(width * height * 4, 1)
    }

    private func isDescriptorInActiveWindow(_ descriptor: SolanaImageDescriptor) -> Bool {
        guard activeCollectionId == descriptor.collectionId else { return false }
        return activeFileNames.contains(fileName(for: descriptor))
    }

    private func shouldKeepDecodedImage(_ descriptor: SolanaImageDescriptor, key: String) -> Bool {
        activeCollectionId == descriptor.collectionId && activeDecodedKeys.contains(key)
    }

    private func cacheKey(for descriptor: SolanaImageDescriptor) -> String {
        "\(descriptor.collectionId)|\(descriptor.tokenIndex)|\(descriptor.tokenId)|\(sourceURLHash(for: descriptor))|\(descriptor.fileExtension)"
    }

    private func cachedDecodedImage(forKey key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
    }

    private func fileURL(for descriptor: SolanaImageDescriptor) -> URL {
        collectionDirectory(collectionId: descriptor.collectionId).appendingPathComponent(fileName(for: descriptor))
    }

    private func fileName(for descriptor: SolanaImageDescriptor) -> String {
        let paddedIndex = String(format: "%06d", descriptor.tokenIndex)
        return "\(paddedIndex)-\(safePathComponent(descriptor.tokenId))-\(sourceURLHash(for: descriptor)).\(descriptor.fileExtension)"
    }

    private func collectionDirectory(collectionId: String) -> URL {
        cacheRoot.appendingPathComponent(safePathComponent(collectionId), isDirectory: true)
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars)
    }

    private func sourceURLHash(for descriptor: SolanaImageDescriptor) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in descriptor.url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

extension UIImage {
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

enum MobilePlayerPrewarmer {

    private struct TokenKey: Hashable {
        let collectionId: String
        let tokenId: String?
    }

    private static let queue = DispatchQueue(label: "org.lil.nft-folder.mobile-player-prewarm", qos: .utility)
    private static let lock = NSLock()
    private static let maximumLaunchTokenPrewarmCount = 2

    private static var didScheduleLaunchPrewarm = false
    private static var requestedKeys = Set<TokenKey>()
    private static var prewarmedTokens = [TokenKey: GeneratedToken]()

    static func scheduleAfterLaunch(continueViewingProgress: MobileViewingProgress?, initialCollectionIds: [String]) {
        AutoReloadingWebView.scheduleFirstUsePrewarm()

        let shouldScheduleTokenPrewarm = lock.withLock {
            guard !didScheduleLaunchPrewarm else { return false }
            didScheduleLaunchPrewarm = true
            return true
        }
        guard shouldScheduleTokenPrewarm else { return }

        var candidates = [TokenKey]()
        let continueCollectionId: String?
        if let continueViewingProgress, !continueViewingProgress.isComplete {
            let tokenKey = TokenKey(collectionId: continueViewingProgress.collectionId, tokenId: continueViewingProgress.tokenId)
            if shouldPrewarm(tokenKey) {
                candidates.append(tokenKey)
            }
            continueCollectionId = continueViewingProgress.collectionId
        } else {
            continueCollectionId = nil
        }
        initialCollectionIds.forEach { collectionId in
            guard collectionId != continueCollectionId else { return }
            let tokenKey = TokenKey(collectionId: collectionId, tokenId: nil)
            guard shouldPrewarm(tokenKey) else { return }
            candidates.append(tokenKey)
        }

        let dedupedCandidates = candidates.reduce(into: [TokenKey]()) { result, candidate in
            guard !result.contains(candidate) else { return }
            result.append(candidate)
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(1000)) {
            dedupedCandidates.prefix(maximumLaunchTokenPrewarmCount).forEach(requestTokenPrewarm)
        }
    }

    static func preparedConfig(
        initialItemId: String?,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String?
    ) -> MobilePlayerConfig {
        var config = MobilePlayerConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId
        )

        if let key = tokenKey(collectionId: initialItemId, tokenId: initialTokenId) {
            config.specificToken = cachedToken(for: key)
        }
        return config
    }

    private static func tokenKey(collectionId: String?, tokenId: String?) -> TokenKey? {
        guard let collectionId else { return nil }
        return TokenKey(collectionId: collectionId, tokenId: tokenId)
    }

    private static func cachedToken(for key: TokenKey) -> GeneratedToken? {
        lock.withLock {
            prewarmedTokens[key]
        }
    }

    private static func requestTokenPrewarm(_ key: TokenKey) {
        guard shouldPrewarm(key) else { return }

        let shouldRequestToken = lock.withLock {
            guard prewarmedTokens[key] == nil, !requestedKeys.contains(key) else { return false }
            requestedKeys.insert(key)
            return true
        }
        guard shouldRequestToken else { return }

        queue.async {
            guard let token = generateToken(for: key) else { return }
            lock.withLock {
                prewarmedTokens[key] = token
            }
        }
    }

    private static func generateToken(for key: TokenKey) -> GeneratedToken? {
        let tokenIndex: Int
        if let tokenId = key.tokenId {
            guard let requestedTokenIndex = MobileCollectionCatalog.tokenIndex(specificCollectionId: key.collectionId, tokenId: tokenId) else {
                return nil
            }
            tokenIndex = requestedTokenIndex
        } else {
            tokenIndex = 0
        }
        return MobileCollectionCatalog.generateToken(specificCollectionId: key.collectionId, tokenIndex: tokenIndex)
    }

    private static func shouldPrewarm(_ key: TokenKey) -> Bool {
        !MobileCollectionCatalog.isSolanaCollection(specificCollectionId: key.collectionId)
    }

}

private class GeneratedTokensDataSource {
    
    private let initialCollectionId: String?
    private let specificInitialToken: GeneratedToken?
    private let initialTokenId: String?
    
    init(initialCollectionId: String?, specificInitialToken: GeneratedToken?, initialTokenId: String?) {
        self.initialCollectionId = initialCollectionId
        self.specificInitialToken = specificInitialToken
        self.initialTokenId = initialTokenId

        if let specificInitialToken {
            let initialCoordinate = PlayerCoordinate(x: 0, y: 0)
            collectionIds[initialCoordinate.y] = specificInitialToken.fullCollectionId
            collectionBaseTokenIndices[initialCoordinate.y] = MobileCollectionCatalog.tokenIndex(
                specificCollectionId: specificInitialToken.fullCollectionId,
                tokenId: specificInitialToken.id
            ) ?? 0
            latestToken = specificInitialToken
            latestCoordinate = initialCoordinate
        }
    }
    
    private var collectionIds = [Int: String]()
    private var collectionBaseTokenIndices = [Int: Int]()
    
    private var latestToken: GeneratedToken?
    private var latestCoordinate: PlayerCoordinate?
    
    func pushToken(_ token: GeneratedToken, coordinate: PlayerCoordinate, sameCollection: Bool) {
        let newCoordinate = sameCollection
            ? PlayerCoordinate(x: coordinate.x + 1, y: coordinate.y)
            : PlayerCoordinate(x: 0, y: coordinate.y + 1)
        let tokenIndex = MobileCollectionCatalog.tokenIndex(specificCollectionId: token.fullCollectionId, tokenId: token.id) ?? 0
        collectionIds[newCoordinate.y] = token.fullCollectionId
        collectionBaseTokenIndices[newCoordinate.y] = tokenIndex - newCoordinate.x
        latestToken = nil
        latestCoordinate = nil
    }

    func canRender(coordinate: PlayerCoordinate) -> Bool {
        collectionTokenContext(coordinate: coordinate) != nil
    }

    func collectionTokenContext(coordinate: PlayerCoordinate) -> (collectionId: String, tokenIndex: Int, tokenCount: Int)? {
        guard let collectionId = collectionId(verticalIndex: coordinate.y),
              let tokenIndex = tokenIndex(coordinate: coordinate) else {
            return nil
        }

        let tokenCount = MobileCollectionCatalog.tokenCount(specificCollectionId: collectionId)
        guard tokenIndex >= 0, tokenIndex < tokenCount else { return nil }
        return (collectionId, tokenIndex, tokenCount)
    }

    func horizontalCoordinateForTokenIndex(_ tokenIndex: Int, verticalIndex: Int) -> Int {
        ensureCollectionLoaded(verticalIndex: verticalIndex)
        return tokenIndex - (collectionBaseTokenIndices[verticalIndex] ?? 0)
    }

    func progress(coordinate: PlayerCoordinate) -> MobileViewingProgress? {
        let token = getToken(coordinate: coordinate)
        guard !token.fullCollectionId.isEmpty,
              let tokenIndex = tokenIndex(coordinate: coordinate) else { return nil }

        let tokenCount = MobileCollectionCatalog.tokenCount(specificCollectionId: token.fullCollectionId)
        guard tokenCount > 0 else { return nil }
        return MobileViewingProgress(
            collectionId: token.fullCollectionId,
            collectionName: token.collectionName,
            tokenId: token.id,
            tokenIndex: tokenIndex,
            tokenCount: tokenCount,
            updatedAt: Date()
        )
    }

    func getToken(coordinate: PlayerCoordinate) -> GeneratedToken {
        if latestCoordinate == coordinate, let token = latestToken {
            return token
        }

        guard let collectionId = collectionId(verticalIndex: coordinate.y),
              let tokenIndex = tokenIndex(coordinate: coordinate),
              let token = MobileCollectionCatalog.generateToken(specificCollectionId: collectionId, tokenIndex: tokenIndex) else {
            return .empty
        }

        latestToken = token
        latestCoordinate = coordinate
        return token
    }

    private func tokenIndex(coordinate: PlayerCoordinate) -> Int? {
        guard let baseTokenIndex = collectionBaseTokenIndices[coordinate.y] else { return nil }
        return baseTokenIndex + coordinate.x
    }

    private func ensureCollectionLoaded(verticalIndex: Int) {
        _ = collectionId(verticalIndex: verticalIndex)
    }

    private func collectionId(verticalIndex: Int) -> String? {
        if let collectionId = collectionIds[verticalIndex] {
            return collectionId
        }

        let collection: (id: String?, requestedTokenId: String?)
        if verticalIndex == 0 {
            collection = (
                specificInitialToken?.fullCollectionId ?? initialCollectionId ?? MobileCollectionCatalog.nextShuffledCollectionId(),
                specificInitialToken?.id ?? initialTokenId
            )
        } else {
            collection = (MobileCollectionCatalog.nextShuffledCollectionId(), nil)
        }

        guard let collectionId = collection.id else { return nil }
        collectionIds[verticalIndex] = collectionId

        let baseTokenIndex: Int
        if let requestedTokenId = collection.requestedTokenId,
           let requestedIndex = MobileCollectionCatalog.tokenIndex(specificCollectionId: collectionId, tokenId: requestedTokenId) {
            baseTokenIndex = requestedIndex
        } else {
            baseTokenIndex = 0
        }
        collectionBaseTokenIndices[verticalIndex] = baseTokenIndex
        return collectionId
    }

}
