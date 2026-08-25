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
    nonisolated static let downloadableMediaCacheFileAvailabilityDidChange = Notification.Name("DownloadableMediaCacheFileAvailabilityDidChange")
}

nonisolated enum DownloadableMediaCacheFileAvailabilityChange: Equatable, Sendable {
    case becameAvailable
    case becameUnavailable
}

@MainActor
final class DownloadableMediaCache {

    typealias PrefetchDirection = PlayerMediaPrefetchDirection

    private nonisolated enum FileAvailabilityScope: Sendable {
        case file(URL)
        case collection(URL)
        case all
    }

    nonisolated enum WindowOwnership: Hashable, Sendable {
        nonisolated enum CooperativeGroup: Hashable, Sendable {
            case macPlayerPager
            case macCollectionBrowser
        }

        case exclusive
        case cooperative(CooperativeGroup)
    }

    static let shared = DownloadableMediaCache()

    nonisolated private static let fileAvailabilityScopeUserInfoKey = "DownloadableMediaCacheFileAvailabilityScope"
    nonisolated private static let webViewHTMLDirectoryName = "_WebViewHTML"
    nonisolated private static let downloadedMediaMetadataFileSuffix = ".metadata.json"
    nonisolated private static let fileRemovalTombstonePrefix = ".nft-player-removing-"
    nonisolated private static let fileRemovalTrashDirectoryName = ".FileRemovalTrash"
#if os(macOS)
    nonisolated private static let legacyRemovalTrashDirectoryName = ".DiskPruneTrash"
#elseif os(tvOS) || os(visionOS)
    nonisolated private static let legacyRemovalTrashDirectoryName = ".FileEvictionTrash"
#endif

    nonisolated static func orderedWindowIndices(currentIndex: Int, tokenCount: Int, direction: PrefetchDirection) -> [Int] {
        PlayerDownloadableMediaWindowLayout.orderedWindowIndices(
            currentIndex: currentIndex,
            tokenCount: tokenCount,
            direction: direction
        )
    }

    nonisolated static func windowDescriptors(
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

    nonisolated private static func decodedWindowDescriptors(
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

    nonisolated static func adjacentDescriptor(
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

    nonisolated static func adjacentDescriptor(
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

    private var memoryCache = NSCache<NSString, DownloadableMediaImage>()
    private let imageDecodeLane = ImageDecodeLane()
    private let diskMutationLane = DiskMutationLane()
    private let decodedImageRetirementLane = DecodedImageRetirementLane()
    private var decodedImageRetirementTask: Task<Bool, Never>?
#if DEBUG && os(iOS)
    private let testingDecodedImagesLock = NSLock()
    private var testingDecodedImages = [String: DownloadableMediaImage]()
#endif
    private let session: URLSession
    nonisolated private let cacheRoot: URL
    nonisolated private let stagingRoot: URL
    nonisolated private let fileRemovalTombstoneDirectory: URL?
    nonisolated private static let defaultDecodedImageMemoryCostLimit = 512 * 1024 * 1024
    nonisolated private static let decodedImageMemoryCostLimitPerDescriptor = 64 * 1024 * 1024
#if os(iOS)
    nonisolated private static let mediaFirstDecodedImageCountLimit = 240
    nonisolated private static let minimumMediaFirstDecodedImageMemoryCostLimit: UInt64 = 768 * 1024 * 1024
    nonisolated private static let maximumMediaFirstDecodedImageMemoryCostLimit: UInt64 = 2 * 1024 * 1024 * 1024
#endif
#if os(iOS) || os(macOS)
    nonisolated private static let maximumDiskCacheBytes: Int64 = 10 * 1024 * 1024 * 1024
    nonisolated private static let targetDiskCacheBytes: Int64 = 8 * 1024 * 1024 * 1024
    nonisolated private static let minimumAvailableDiskBytes: Int64 = 1 * 1024 * 1024 * 1024
    nonisolated private static let diskPruneCheckDebounceInterval: TimeInterval = 2
    nonisolated private static let diskPruneCheckInterval: TimeInterval = 60
    nonisolated private static let cachedFileTouchDebounceInterval: TimeInterval = 2
    nonisolated private static let cachedFileTouchMinimumInterval: TimeInterval = 30
    nonisolated private static let cachedFileTouchHistoryLimit = 4096
#if os(macOS)
    nonisolated private static let diskPruneCandidateBatchSize = 16
    nonisolated private static let diskPruneFileBatchSize = 32
    nonisolated private static let diskPruneMaximumMutationDeferralInterval: TimeInterval = 10
#endif
#endif
    private let maximumConcurrentDownloads = 4

    private struct OngoingDownload {
        let task: URLSessionDownloadTask
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let id: UUID
        var isFinalizing = false
    }

    private nonisolated struct WindowFileCandidate: Sendable {
        let key: String
        let url: URL
    }

    private nonisolated struct WindowFileAvailability: Sendable {
        let checkedKeys: Set<String>
        let availableKeys: Set<String>

        func hasFile(forKey key: String) -> Bool? {
            checkedKeys.contains(key) ? availableKeys.contains(key) : nil
        }
    }

    private nonisolated struct WindowWorkPlan: Sendable {
        let foregroundDescriptor: CollectionCatalogDownloadableMediaDescriptor
        let requiresDecodedForegroundImage: Bool
        let decodedDescriptors: [CollectionCatalogDownloadableMediaDescriptor]
        let downloadDescriptors: [CollectionCatalogDownloadableMediaDescriptor]
    }

    private nonisolated struct DownloadedMediaMetadata: Codable, Sendable {
        let sourceURL: URL
    }

    private nonisolated struct DownloadFileFinalization: Sendable {
        let succeeded: Bool
        let didRemoveExistingItem: Bool
        let cacheBytes: Int64
    }

    private nonisolated enum ImageLoadScheduling: Sendable {
        case foreground
        case preservingPrefetch
    }

    private nonisolated enum ImageDecodeOrigin: Equatable, Sendable {
        case cachedFile
        case freshDownload
    }

    private nonisolated final class ImageDecodeGeneration: @unchecked Sendable {
        private enum State: Equatable {
            case pending
            case decoding
            case invalidated
        }

        private let lock = NSLock()
        private var state = State.pending

        var hasStarted: Bool {
            lock.withLock { state == .decoding }
        }

        func beginIfCurrent() -> Bool {
            lock.withLock {
                guard state == .pending else { return false }
                state = .decoding
                return true
            }
        }

        func invalidate() {
            lock.withLock {
                state = .invalidated
            }
        }
    }

    private nonisolated struct DecodedImageTransfer: @unchecked Sendable {
        let image: DownloadableMediaImage?
    }

    private nonisolated final class DecodedImageMemoryRetirement: @unchecked Sendable {
        private var cache: NSCache<NSString, DownloadableMediaImage>?
        private var retainedImages: [DownloadableMediaImage]

        init(
            cache: NSCache<NSString, DownloadableMediaImage>,
            retainedImages: [DownloadableMediaImage]
        ) {
            self.cache = cache
            self.retainedImages = retainedImages
        }

        func releaseContents() {
            cache?.removeAllObjects()
            cache = nil
            retainedImages.removeAll(keepingCapacity: false)
        }
    }

    private actor ImageDecodeLane {
        func decode(
            at fileURL: URL,
            generation: ImageDecodeGeneration
        ) async -> DecodedImageTransfer? {
            guard generation.beginIfCurrent() else { return nil }
            return DownloadableMediaCache.loadDecodedImage(at: fileURL)
        }
    }

    private actor DecodedImageRetirementLane {
        func retire(_ retirement: DecodedImageMemoryRetirement) -> Bool {
            let ranOnMainThread = Thread.isMainThread
            retirement.releaseContents()
            return ranOnMainThread
        }
    }

    private actor DiskMutationLane {
        func finalizeDownload(
            at stagedURL: URL,
            fileURL: URL,
            metadataURL: URL,
            sourceURL: URL,
            availabilityRevision: FileAvailabilityRevision
        ) -> DownloadFileFinalization {
            availabilityRevision.beginMutation()
            defer { availabilityRevision.endMutation() }
            let fileManager = FileManager.default
            var didRemoveExistingItem = false
            var didClearMediaPath = false
            do {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                do {
                    try fileManager.removeItem(at: fileURL)
                    didRemoveExistingItem = true
                } catch let error as NSError where error.domain == NSCocoaErrorDomain
                    && error.code == NSFileNoSuchFileError {}
                didClearMediaPath = true

                let metadataBytes: Int64
                do {
                    let metadata = DownloadedMediaMetadata(sourceURL: sourceURL)
                    let metadataData = try JSONEncoder().encode(metadata)
                    try metadataData.write(to: metadataURL, options: .atomic)
                    metadataBytes = Int64(
                        (try? metadataURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                            ?? 0
                    )
                } catch {
                    try? fileManager.removeItem(at: metadataURL)
                    metadataBytes = 0
                }
                try fileManager.moveItem(at: stagedURL, to: fileURL)
                let mediaBytes = Int64(
                    (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                        ?? 0
                )
                return DownloadFileFinalization(
                    succeeded: true,
                    didRemoveExistingItem: didRemoveExistingItem,
                    cacheBytes: mediaBytes + metadataBytes
                )
            } catch {
                if didClearMediaPath {
                    try? fileManager.removeItem(at: metadataURL)
                }
                try? fileManager.removeItem(at: stagedURL)
                return DownloadFileFinalization(
                    succeeded: false,
                    didRemoveExistingItem: didRemoveExistingItem,
                    cacheBytes: 0
                )
            }
        }

        func removeFileRemovalTombstones(at directoryURL: URL) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else {
                return
            }
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }

        func removeFallbackFileRemovalTombstones(at rootURL: URL) {
            DownloadableMediaCache.removeFallbackFileRemovalTombstones(
                at: rootURL
            )
        }

        func removeOrphanMetadata(
            at metadataURL: URL,
            ifMediaMissingAt mediaURL: URL,
            token: CancellableFileRemovalToken
        ) -> CancellableFileRemovalToken.RemovalResult {
            let fileManager = FileManager.default
            guard !fileManager.fileExists(atPath: mediaURL.path) else { return .notRemoved }
            return token.removeIfActive(at: metadataURL)
        }

        func removeCachePair(
            mediaURL: URL,
            metadataURL: URL?,
            token: CancellableFileRemovalToken
        ) -> CancellableFileRemovalToken.PairRemovalResult {
            token.removePairIfActive(primaryURL: mediaURL, sidecarURL: metadataURL)
        }

        func evictFilesOutsideWindow(
            directory: URL,
            protectedFileNames: Set<String>,
            token: CancellableFileRemovalToken
        ) -> Bool {
            let fileManager = FileManager.default
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                return false
            }

            let urlsByName = Dictionary(uniqueKeysWithValues: contents.map {
                ($0.lastPathComponent, $0)
            })
            let mediaURLs = contents
                .filter { !$0.lastPathComponent.hasSuffix(DownloadableMediaCache.downloadedMediaMetadataFileSuffix) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            var didRemoveItem = false
            for mediaURL in mediaURLs {
                let mediaFileName = mediaURL.lastPathComponent
                let metadataFileName = DownloadableMediaCache.metadataFileName(
                    forFileName: mediaFileName
                )
                guard !protectedFileNames.contains(mediaFileName),
                      !protectedFileNames.contains(metadataFileName) else {
                    continue
                }
                let removal = token.removePairIfActive(
                    primaryURL: mediaURL,
                    sidecarURL: urlsByName[metadataFileName]
                )
                switch removal.primary {
                case .removed, .stagedForCleanup:
                    didRemoveItem = true
                case .notRemoved:
                    continue
                case .cancelled:
                    return didRemoveItem
                }
            }

            let mediaFileNames = Set(mediaURLs.map(\.lastPathComponent))
            let orphanMetadataURLs = contents
                .filter { $0.lastPathComponent.hasSuffix(DownloadableMediaCache.downloadedMediaMetadataFileSuffix) }
                .filter {
                    let mediaFileName = String(
                        $0.lastPathComponent.dropLast(
                            DownloadableMediaCache.downloadedMediaMetadataFileSuffix.count
                        )
                    )
                    return !mediaFileNames.contains(mediaFileName)
                        && !protectedFileNames.contains(mediaFileName)
                        && !protectedFileNames.contains($0.lastPathComponent)
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for metadataURL in orphanMetadataURLs {
                switch token.removeIfActive(at: metadataURL) {
                case .removed, .stagedForCleanup:
                    didRemoveItem = true
                case .notRemoved:
                    continue
                case .cancelled:
                    return didRemoveItem
                }
            }
            return didRemoveItem
        }

#if os(macOS)
        func removeDiskCacheCandidates(
            _ candidates: [DiskPruneCandidate],
            removalByteTarget: Int64?,
            protectedPaths: Set<String>,
            token: CancellableFileRemovalToken
        ) -> DiskPruneRemovalResult {
            var processedCandidateCount = 0
            var removedFileCount = 0
            var removedCacheBytes: Int64 = 0
            var freedDiskBytes: Int64 = 0

            for candidate in candidates {
                if let removalByteTarget, removedCacheBytes >= removalByteTarget {
                    break
                }
                processedCandidateCount += 1
                guard candidate.filePaths.isDisjoint(with: protectedPaths) else {
                    continue
                }

                guard removedFileCount < DownloadableMediaCache.diskPruneFileBatchSize else {
                    break
                }
                let canRemoveSidecar = removedFileCount + 1
                    < DownloadableMediaCache.diskPruneFileBatchSize
                let removal = token.removePairIfActive(
                    primaryURL: candidate.primaryFile.url,
                    sidecarURL: canRemoveSidecar ? candidate.sidecarFile?.url : nil
                )
                switch removal.primary {
                case .cancelled:
                    return DiskPruneRemovalResult(
                        wasCurrent: false,
                        processedCandidateCount: processedCandidateCount,
                        didRemoveItem: removedFileCount > 0,
                        removedCacheBytes: removedCacheBytes,
                        freedDiskBytes: freedDiskBytes
                    )
                case .notRemoved:
                    continue
                case .removed:
                    removedFileCount += 1
                    removedCacheBytes += candidate.primaryFile.size
                    freedDiskBytes += candidate.primaryFile.size
                case .stagedForCleanup:
                    removedFileCount += 1
                    removedCacheBytes += candidate.primaryFile.size
                }
                if let sidecarRemoval = removal.sidecar,
                   sidecarRemoval.removedFromCache,
                   let sidecarFile = candidate.sidecarFile {
                    removedFileCount += 1
                    removedCacheBytes += sidecarFile.size
                    if sidecarRemoval.freedStorage {
                        freedDiskBytes += sidecarFile.size
                    }
                }
            }

            return DiskPruneRemovalResult(
                wasCurrent: token.isActive,
                processedCandidateCount: processedCandidateCount,
                didRemoveItem: removedFileCount > 0,
                removedCacheBytes: removedCacheBytes,
                freedDiskBytes: freedDiskBytes
            )
        }
#endif
    }

    private struct ActiveDecode {
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let fileURL: URL
        let generation: ImageDecodeGeneration
        let origin: ImageDecodeOrigin
    }

    private struct RunningDecode {
        let key: String
        let generation: ImageDecodeGeneration
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

    nonisolated private final class OneShotToken: @unchecked Sendable {
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

    nonisolated private final class FileAvailabilityRevision: @unchecked Sendable {
        private struct State {
            var value: UInt64 = 0
            var activeMutations = 0
        }

        private let lock = NSLock()
        private var state = State()

        func snapshot() -> UInt64 {
            lock.withLock { state.value }
        }

        func isCurrent(_ snapshot: UInt64) -> Bool {
            lock.withLock {
                state.activeMutations == 0 && state.value == snapshot
            }
        }

        func beginMutation() {
            lock.withLock {
                state.activeMutations += 1
                state.value &+= 1
            }
        }

        func endMutation() {
            lock.withLock {
                state.activeMutations -= 1
                state.value &+= 1
            }
        }

        func invalidate() {
            lock.withLock { state.value &+= 1 }
        }
    }

    nonisolated final class CancellableFileRemovalToken: @unchecked Sendable {
        private nonisolated enum RemovalClaim {
            case claimed(URL)
            case notRemoved
            case cancelled
        }

        nonisolated enum RemovalResult: Equatable, Sendable {
            case removed
            case stagedForCleanup
            case notRemoved
            case cancelled

            var removedFromCache: Bool {
                self == .removed || self == .stagedForCleanup
            }

            var freedStorage: Bool {
                self == .removed
            }
        }

        nonisolated struct PairRemovalResult: Equatable, Sendable {
            let primary: RemovalResult
            let sidecar: RemovalResult?
        }

        private let lock = NSLock()
        private let tombstoneDirectoryURL: URL?
        private let willClaimRemoval: @Sendable () -> Void
        private let didClaimRemoval: @Sendable () -> Void
        private let removeItem: @Sendable (URL) throws -> Void
        private var isCancelled = false

        init(
            tombstoneDirectoryURL: URL? = nil,
            willClaimRemoval: @escaping @Sendable () -> Void = {},
            didClaimRemoval: @escaping @Sendable () -> Void = {},
            removeItem: @escaping @Sendable (URL) throws -> Void = CancellableFileRemovalToken.removeItem
        ) {
            self.tombstoneDirectoryURL = tombstoneDirectoryURL
            self.willClaimRemoval = willClaimRemoval
            self.didClaimRemoval = didClaimRemoval
            self.removeItem = removeItem
        }

        var isActive: Bool {
            lock.withLock { !isCancelled }
        }

        func cancel() {
            lock.withLock { isCancelled = true }
        }

        func removeIfActive(at url: URL) -> RemovalResult {
            switch claimRemoval(at: url) {
            case let .claimed(tombstoneURL):
                return removeClaimedItem(at: tombstoneURL)
            case .notRemoved:
                return .notRemoved
            case .cancelled:
                return .cancelled
            }
        }

        func removePairIfActive(primaryURL: URL, sidecarURL: URL?) -> PairRemovalResult {
            let primaryResult = removeIfActive(at: primaryURL)
            guard primaryResult.removedFromCache, let sidecarURL else {
                return PairRemovalResult(primary: primaryResult, sidecar: nil)
            }
            return PairRemovalResult(
                primary: primaryResult,
                sidecar: removeIfActive(at: sidecarURL)
            )
        }

        private func claimRemoval(at url: URL) -> RemovalClaim {
            lock.withLock {
                guard !isCancelled else { return .cancelled }
                willClaimRemoval()
                defer { didClaimRemoval() }
                let fallbackDirectoryURL = url.deletingLastPathComponent()
                let directoryURL = tombstoneDirectoryURL ?? fallbackDirectoryURL
                let tombstoneFileName = DownloadableMediaCache.fileRemovalTombstonePrefix
                    + UUID().uuidString
                let tombstoneURL = directoryURL.appendingPathComponent(tombstoneFileName)
                do {
                    try FileManager.default.moveItem(at: url, to: tombstoneURL)
                    return .claimed(tombstoneURL)
                } catch {
                    return .notRemoved
                }
            }
        }

        private func removeClaimedItem(at tombstoneURL: URL) -> RemovalResult {
            do {
                try removeItem(tombstoneURL)
                return .removed
            } catch {
                return .stagedForCleanup
            }
        }

        nonisolated private static func removeItem(at url: URL) throws {
            try FileManager.default.removeItem(at: url)
        }
    }

    private nonisolated struct RetainedFileNameKey: Hashable, Sendable {
        let collectionId: String
        let fileName: String
    }

    private typealias ImageLoadCompletion = (DownloadableMediaImage?) -> Void
    private struct ImageLoadCallback {
        let request: LoadRequest
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let completion: ImageLoadCompletion
    }
    private typealias ImageLoadCompletions = [UUID: ImageLoadCallback]

    private typealias FileLoadCompletion = (URL?) -> Void
    private struct FileLoadCallback {
        let request: LoadRequest
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let completion: FileLoadCompletion
    }
    private typealias FileLoadCompletions = [UUID: FileLoadCallback]

    private struct ExclusiveWindowRegistration {
        let ownerId: UUID
        let mediaWindow: PlayerDownloadableMediaWindow
        var isSuspended: Bool
    }

    private struct ManagedWindow {
        let mediaWindow: PlayerDownloadableMediaWindow
        let cooperativeGroup: WindowOwnership.CooperativeGroup
        let fileNames: Set<String>
        let allowedKeys: Set<String>
        let decodedKeys: Set<String>
        let preparationSequence: UInt64
        var isSuspended: Bool

        var collectionId: String {
            mediaWindow.currentDescriptor.collectionId
        }
    }

    private struct ActiveWindow {
        let collectionId: String
        let fileNames: Set<String>
        let allowedKeys: Set<String>
        let decodedKeys: Set<String>
    }

#if os(tvOS) || os(visionOS)
    private struct PendingFinalizedFileRemoval {
        let collectionId: String
        let fileNames: Set<String>
        let token: CancellableFileRemovalToken
    }
#endif

#if os(iOS) || os(macOS)
    private nonisolated struct DiskCacheFileSnapshot: Sendable {
        let url: URL
        let isDirectory: Bool
        let size: Int64
        let contentAccessDate: Date?
        let contentModificationDate: Date?

        init(url: URL) {
            let values = try? url.resourceValues(forKeys: [
                .contentAccessDateKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey
            ])
            self.url = url
            self.isDirectory = values?.isDirectory == true
            self.size = Int64(values?.fileSize ?? 0)
            self.contentAccessDate = values?.contentAccessDate
            self.contentModificationDate = values?.contentModificationDate
        }
    }

    private nonisolated struct DiskCacheEntry: Sendable {
        let mediaURL: URL
        let metadataURL: URL?
        let filePaths: Set<String>
        let mediaSize: Int64
        let metadataSize: Int64
        let lastAccessDate: Date

        var size: Int64 {
            mediaSize + metadataSize
        }
    }

    private nonisolated struct DiskCacheOrphanMetadataEntry: Sendable {
        let url: URL
        let mediaURL: URL
        let path: String
        let size: Int64
    }

    private nonisolated enum DiskPruneReason: Sendable {
        case routine, afterWrite
    }

    private nonisolated struct DiskPruneRequest: Sendable {
        var bypassRoutineThrottle: Bool
        var protectedPaths: Set<String>

        mutating func merge(_ other: DiskPruneRequest) {
            bypassRoutineThrottle = bypassRoutineThrottle || other.bypassRoutineThrottle
            protectedPaths.formUnion(other.protectedPaths)
        }
    }

    private nonisolated struct DiskPruneResult: Sendable {
        let didRemoveItem: Bool
        let cacheBytesAfterPrune: Int64
        let availableDiskBytesAfterPrune: Int64?
    }

#if os(macOS)
    private nonisolated struct DiskPruneCandidate: Sendable {
        let filePaths: Set<String>
        let primaryFile: (url: URL, size: Int64)
        let sidecarFile: (url: URL, size: Int64)?
    }

    private nonisolated struct DiskPruneRemovalContext: Sendable {
        let protectedPaths: Set<String>
        let token: CancellableFileRemovalToken
    }

    private nonisolated struct DiskPruneRemovalResult: Sendable {
        let wasCurrent: Bool
        let processedCandidateCount: Int
        let didRemoveItem: Bool
        let removedCacheBytes: Int64
        let freedDiskBytes: Int64
    }
#endif
#endif

    private var activeWindow: ActiveWindow?
    private var exclusiveWindowRegistration: ExclusiveWindowRegistration?
    private var managedWindowsByOwnerId = [UUID: ManagedWindow]()
    private var windowPreparationSequence: UInt64 = 0
#if !os(iOS)
    private var memoryKeysByCollection = [String: Set<String>]()
#endif
    private var pendingDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
    private var pendingKeys = Set<String>()
    private var ongoingDownloads = [String: OngoingDownload]()
    private var windowWorkTask: Task<Void, Never>?
    private var windowWorkGeneration: UInt64 = 0
    nonisolated private let fileAvailabilityRevision = FileAvailabilityRevision()
#if os(iOS)
    private var suppressesPrefetchDecodeUntilNextWindowWork = false
#endif
#if os(tvOS) || os(visionOS)
    private var fileEvictionTask: Task<Void, Never>?
    private var fileEvictionToken: CancellableFileRemovalToken?
    private var fileEvictionGeneration: UInt64 = 0
    private var pendingFinalizedFileRemovals = [UUID: PendingFinalizedFileRemoval]()
#endif
    private var activeDecodesByKey = [String: ActiveDecode]()
    private var pendingDecodeKeys = [String]()
    private var runningDecode: RunningDecode?
    private var foregroundKey: String?
    private var foregroundWorkKeys = Set<String>()
    private var completions = [String: ImageLoadCompletions]()
    private var fileCompletions = [String: FileLoadCompletions]()
    private var retainedFileKeys = [String: Int]()
    private var retainedFileNameKeys = [RetainedFileNameKey: Int]()
    private var retainedDecodeFailureDescriptors = [String: CollectionCatalogDownloadableMediaDescriptor]()
    private var memoryWarningObserver: NSObjectProtocol?
#if os(iOS) || os(macOS)
    private var lastRoutineDiskPruneCheckDate: Date?
    private var pendingDiskPruneRequest: DiskPruneRequest?
    private var isDiskPruneCheckScheduled = false
    private var isDiskPruneRunning = false
    private var estimatedDiskCacheBytes: Int64?
    private var estimatedAvailableDiskBytes: Int64?
    private var diskCacheBytesAddedSinceLastEstimate: Int64 = 0
    private var diskPruneRemovalToken: CancellableFileRemovalToken?
#if os(macOS)
    private var diskCacheMutationGeneration: UInt64 = 0
    private var diskPruneMutationDeferralDeadline: DispatchTime?
    private var diskPruneMutationDeferralGeneration: UInt64?
#endif
    private var pendingCachedFileTouchURLs = [String: URL]()
    private var cachedFileTouchDates = [String: Date]()
    private var isCachedFileTouchScheduled = false
#endif

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
        let fileRemovalTrashDirectory = cacheRoot.appendingPathComponent(
            Self.fileRemovalTrashDirectoryName,
            isDirectory: true
        )
        let fileRemovalTombstoneDirectory = fileRemovalTrashDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try? fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        do {
            try fileManager.createDirectory(
                at: fileRemovalTombstoneDirectory,
                withIntermediateDirectories: true
            )
            self.fileRemovalTombstoneDirectory = fileRemovalTombstoneDirectory
        } catch {
            self.fileRemovalTombstoneDirectory = nil
        }
        var excludedFromBackupURL = cacheRoot
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludedFromBackupURL.setResourceValues(resourceValues)
        try? FileManager.default.removeItem(
            at: cacheRoot.appendingPathComponent(Self.webViewHTMLDirectoryName, isDirectory: true)
        )
        configureDecodedImageMemoryCacheLimit(
            decodedDescriptorCount: PlayerDownloadableMediaWindowLayout.decodedWindowCapacity
        )

        let activeFileRemovalTombstoneDirectory = self.fileRemovalTombstoneDirectory
        Task(priority: .utility) { [activeFileRemovalTombstoneDirectory] in
            await Self.removeStaleFileRemovalTrash(
                at: fileRemovalTrashDirectory,
                keeping: activeFileRemovalTombstoneDirectory
            )
        }

#if os(macOS) || os(tvOS) || os(visionOS)
        let legacyRemovalTrashDirectory = cacheRoot.appendingPathComponent(
            Self.legacyRemovalTrashDirectoryName,
            isDirectory: true
        )
        Task(priority: .utility) {
            await Self.removeLegacyRemovalTrashDirectory(at: legacyRemovalTrashDirectory)
        }
#endif

#if os(iOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning()
            }
        }
#endif
    }

    @discardableResult
    func prepareWindow(
        for context: PlayerTokenContext?,
        ownerId: UUID,
        direction: PrefetchDirection,
        ownership: WindowOwnership = .exclusive
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
        prepareWindow(window, ownerId: ownerId, ownership: ownership)
        return currentDescriptor
    }

    @discardableResult
    func prepareWindow(
        _ window: PlayerDownloadableMediaWindow,
        ownerId: UUID,
        ownership: WindowOwnership = .exclusive
    ) -> CollectionCatalogDownloadableMediaDescriptor {
        let previousWindow = activeWindow
        switch ownership {
        case .exclusive:
            managedWindowsByOwnerId.removeAll()
            windowPreparationSequence = 0
            exclusiveWindowRegistration = ExclusiveWindowRegistration(
                ownerId: ownerId,
                mediaWindow: window,
                isSuspended: false
            )
            reconcileExclusiveWindow(previousWindow: previousWindow)
        case let .cooperative(group):
            exclusiveWindowRegistration = nil
            prepareManagedWindowRegistration(
                window,
                ownerId: ownerId,
                cooperativeGroup: group
            )
            reconcileManagedWindows(previousWindow: previousWindow)
        }
        return window.currentDescriptor
    }

    func clearActiveWindow(ownerId: UUID) {
        if exclusiveWindowRegistration?.ownerId == ownerId {
            let previousWindow = activeWindow
            exclusiveWindowRegistration = nil
            reconcileExclusiveWindow(previousWindow: previousWindow)
            return
        }
        guard managedWindowsByOwnerId.removeValue(forKey: ownerId) != nil else { return }
        let previousWindow = activeWindow
        reconcileManagedWindows(previousWindow: previousWindow)
    }

    func suspendActiveWindow(ownerId: UUID) {
        if var registration = exclusiveWindowRegistration,
           registration.ownerId == ownerId,
           !registration.isSuspended {
            let previousWindow = activeWindow
            registration.isSuspended = true
            exclusiveWindowRegistration = registration
            reconcileExclusiveWindow(previousWindow: previousWindow)
            return
        }
        guard var window = managedWindowsByOwnerId[ownerId],
              !window.isSuspended else { return }
        let previousWindow = activeWindow
        window.isSuspended = true
        managedWindowsByOwnerId[ownerId] = window
        reconcileManagedWindows(previousWindow: previousWindow)
    }

    private func prepareManagedWindowRegistration(
        _ window: PlayerDownloadableMediaWindow,
        ownerId: UUID,
        cooperativeGroup: WindowOwnership.CooperativeGroup
    ) {
        let collectionId = window.currentDescriptor.collectionId
        let canJoinExistingWindows = managedWindowsByOwnerId.values.allSatisfy {
            $0.collectionId == collectionId
        }
        if !canJoinExistingWindows {
            managedWindowsByOwnerId.removeAll()
        } else {
            let replacedOwnerIds = managedWindowsByOwnerId.compactMap { existingOwnerId, window -> UUID? in
                guard window.cooperativeGroup == cooperativeGroup else {
                    return nil
                }
                return existingOwnerId
            }
            replacedOwnerIds.forEach {
                managedWindowsByOwnerId.removeValue(forKey: $0)
            }
        }

        windowPreparationSequence &+= 1
        managedWindowsByOwnerId[ownerId] = ManagedWindow(
            mediaWindow: window,
            cooperativeGroup: cooperativeGroup,
            fileNames: Set(window.descriptors.flatMap(self.fileNames(for:))),
            allowedKeys: Set(window.descriptors.map(self.cacheKey(for:))),
            decodedKeys: Set(window.decodedDescriptors.map(self.cacheKey(for:))),
            preparationSequence: windowPreparationSequence,
            isSuspended: false
        )
    }

    private func reconcileExclusiveWindow(previousWindow: ActiveWindow?) {
        guard let registration = exclusiveWindowRegistration else {
            clearActiveWindowState()
            return
        }

        let mediaWindow = registration.mediaWindow
        let decodedKeys: Set<String>
        let allowedKeys: Set<String>
        if registration.isSuspended {
            allowedKeys = []
            if mediaWindow.currentDescriptor.isStaticImage {
                decodedKeys = [cacheKey(for: mediaWindow.currentDescriptor)]
            } else {
                decodedKeys = []
            }
        } else {
            allowedKeys = Set(mediaWindow.descriptors.map(self.cacheKey(for:)))
            decodedKeys = Set(mediaWindow.decodedDescriptors.map(self.cacheKey(for:)))
        }
        let nextWindow = ActiveWindow(
            collectionId: mediaWindow.currentDescriptor.collectionId,
            fileNames: Set(mediaWindow.descriptors.flatMap(self.fileNames(for:))),
            allowedKeys: allowedKeys,
            decodedKeys: decodedKeys
        )
        reconcileActiveWindow(nextWindow, previousWindow: previousWindow)

        if registration.isSuspended {
            reconcileInactiveWindowWork()
        } else {
            scheduleExclusiveWindowWork(mediaWindow)
        }
    }

    private func reconcileManagedWindows(previousWindow: ActiveWindow?) {
        guard let nextWindow = makeActiveWindow() else {
            clearActiveWindowState()
            return
        }

        reconcileActiveWindow(nextWindow, previousWindow: previousWindow)
        scheduleManagedWindowWork()
    }

    private func reconcileActiveWindow(_ nextWindow: ActiveWindow, previousWindow: ActiveWindow?) {
        let didChangeCollection = previousWindow?.collectionId != nextWindow.collectionId
        if didChangeCollection {
            cancelDownloadsOutsideActiveCollection(collectionId: nextWindow.collectionId)
#if !os(iOS)
            evictMemoryOutsideActiveCollection(collectionId: nextWindow.collectionId)
#endif
        }

        configureDecodedImageMemoryCacheLimit(decodedDescriptorCount: nextWindow.decodedKeys.count)
        let didChangeFileWindow = didChangeCollection || previousWindow?.fileNames != nextWindow.fileNames
        let didChangeAllowedWindow = didChangeCollection || previousWindow?.allowedKeys != nextWindow.allowedKeys
        let didChangeDecodedWindow = didChangeCollection || previousWindow?.decodedKeys != nextWindow.decodedKeys
#if os(iOS) || os(macOS)
        if didChangeFileWindow {
            cancelDiskPruneRemovalIfNeeded()
        }
#elseif os(tvOS) || os(visionOS)
        if didChangeFileWindow {
            cancelScheduledFileEviction()
        }
        cancelFinalizedFileRemovals(retainedBy: nextWindow)
#endif
        activeWindow = nextWindow

        if didChangeFileWindow {
#if os(iOS) || os(macOS)
            scheduleDiskPruneCheck()
#elseif os(tvOS) || os(visionOS)
            scheduleFileEvictionOutsideWindow(
                collectionId: nextWindow.collectionId,
                allowedFileNames: nextWindow.fileNames
            )
#endif
        }
        if didChangeAllowedWindow {
            cancelDownloadsOutsideWindow(
                collectionId: nextWindow.collectionId,
                allowedKeys: nextWindow.allowedKeys
            )
        }
        pruneForegroundTracking(allowedKeys: nextWindow.allowedKeys)
        if didChangeDecodedWindow {
            invalidateUndemandedDecodeWork(
                outside: nextWindow.decodedKeys,
                startsDrain: false
            )
        }
#if !os(iOS)
        if didChangeDecodedWindow {
            evictMemoryOutsideWindow(
                collectionId: nextWindow.collectionId,
                allowedKeys: nextWindow.decodedKeys
            )
        }
#endif
    }

    private func makeActiveWindow() -> ActiveWindow? {
        guard let firstWindow = managedWindowsByOwnerId.values.first else { return nil }

        var fileNames = Set<String>()
        var allowedKeys = Set<String>()
        var decodedKeys = Set<String>()
        for window in managedWindowsByOwnerId.values {
            guard window.collectionId == firstWindow.collectionId else { continue }
            fileNames.formUnion(window.fileNames)
            if window.isSuspended {
                if window.mediaWindow.currentDescriptor.isStaticImage {
                    decodedKeys.insert(cacheKey(for: window.mediaWindow.currentDescriptor))
                }
            } else {
                allowedKeys.formUnion(window.allowedKeys)
                decodedKeys.formUnion(window.decodedKeys)
            }
        }
        return ActiveWindow(
            collectionId: firstWindow.collectionId,
            fileNames: fileNames,
            allowedKeys: allowedKeys,
            decodedKeys: decodedKeys
        )
    }

    private func scheduleManagedWindowWork() {
        let activeWindows = managedWindowsByOwnerId.values
            .filter { !$0.isSuspended }
            .sorted { $0.preparationSequence > $1.preparationSequence }

        guard let foregroundWindow = activeWindows.first else {
            reconcileInactiveWindowWork()
            return
        }
        var decodedDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
        var usedDecodedKeys = Set<String>()
        for window in activeWindows {
            for descriptor in window.mediaWindow.decodedDescriptors {
                let key = cacheKey(for: descriptor)
                guard usedDecodedKeys.insert(key).inserted else { continue }
                decodedDescriptors.append(descriptor)
            }
        }
        let downloadDescriptors = prioritizedDownloadDescriptors(for: activeWindows)
        scheduleWindowWork(WindowWorkPlan(
            foregroundDescriptor: foregroundWindow.mediaWindow.currentDescriptor,
            requiresDecodedForegroundImage: foregroundWindow.mediaWindow.currentDescriptor.isStaticImage,
            decodedDescriptors: decodedDescriptors,
            downloadDescriptors: downloadDescriptors
        ))
    }

    private func scheduleExclusiveWindowWork(_ mediaWindow: PlayerDownloadableMediaWindow) {
        let downloadDescriptors = prioritizedDownloadDescriptors(for: mediaWindow)
        scheduleWindowWork(WindowWorkPlan(
            foregroundDescriptor: mediaWindow.currentDescriptor,
            requiresDecodedForegroundImage: mediaWindow.currentDescriptor.isStaticImage,
            decodedDescriptors: mediaWindow.decodedDescriptors,
            downloadDescriptors: downloadDescriptors
        ))
    }

    private func reconcileInactiveWindowWork() {
        cancelScheduledWindowWork()
        foregroundKey = nil
        foregroundWorkKeys.removeAll()
        updateOngoingDownloadPriorities()
        startDownloadsIfNeeded()
    }

    private func scheduleWindowWork(_ plan: WindowWorkPlan) {
#if os(iOS)
        suppressesPrefetchDecodeUntilNextWindowWork = false
#endif
        windowWorkTask?.cancel()
        windowWorkGeneration &+= 1
        let generation = windowWorkGeneration
        let availabilityRevision = fileAvailabilityRevision.snapshot()
        var candidatesByKey = [String: WindowFileCandidate]()
        for descriptor in [plan.foregroundDescriptor] + plan.decodedDescriptors + plan.downloadDescriptors {
            let key = cacheKey(for: descriptor)
            candidatesByKey[key] = WindowFileCandidate(key: key, url: fileURL(for: descriptor))
        }

        windowWorkTask = Task { @MainActor [weak self] in
            let availability = await Self.fileAvailability(for: Array(candidatesByKey.values))
            guard !Task.isCancelled,
                  let self,
                  self.windowWorkGeneration == generation else {
                return
            }
            guard self.fileAvailabilityRevision.isCurrent(availabilityRevision) else {
                self.scheduleWindowWork(plan)
                return
            }
            self.windowWorkTask = nil
            self.applyWindowWork(plan, availability: availability)
        }
    }

    private func cancelScheduledWindowWork() {
        windowWorkTask?.cancel()
        windowWorkTask = nil
        windowWorkGeneration &+= 1
    }

    private func applyWindowWork(_ plan: WindowWorkPlan, availability: WindowFileAvailability) {
        prioritizeForegroundImageIfNeeded(
            plan.foregroundDescriptor,
            requireDecodedStaticImage: plan.requiresDecodedForegroundImage,
            hasFile: availability.hasFile(forKey: cacheKey(for: plan.foregroundDescriptor))
        )
        decodeCachedImagesIfNeeded(plan.decodedDescriptors, availability: availability)
        for descriptor in plan.downloadDescriptors {
            enqueueDownloadIfNeeded(
                descriptor,
                isForegroundRequest: false,
                hasFile: availability.hasFile(forKey: cacheKey(for: descriptor))
            )
        }
        reorderPendingDownloads(preferredDescriptors: plan.downloadDescriptors)
        startDownloadsIfNeeded(fileAvailability: availability)
    }

    @concurrent
    nonisolated private static func fileAvailability(
        for candidates: [WindowFileCandidate]
    ) async -> WindowFileAvailability {
        var checkedKeys = Set<String>()
        var availableKeys = Set<String>()
        for candidate in candidates {
            guard !Task.isCancelled else { break }
            checkedKeys.insert(candidate.key)
            if FileManager.default.fileExists(atPath: candidate.url.path) {
                availableKeys.insert(candidate.key)
            }
        }
        return WindowFileAvailability(
            checkedKeys: checkedKeys,
            availableKeys: availableKeys
        )
    }

    func cancelAllDownloads() {
        cancelScheduledWindowWork()
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
#if os(tvOS) || os(visionOS)
        cancelScheduledFileEviction()
#endif
        cancelUnretainedDownloadsAndPendingWork()

        invalidateAllImageDecodes()
        foregroundKey = nil
        foregroundWorkKeys.removeAll()
        clearDecodedImageMemory()
#if !os(iOS)
        memoryKeysByCollection.removeAll()
#endif
        activeWindow = nil
        exclusiveWindowRegistration = nil
        managedWindowsByOwnerId.removeAll()
        windowPreparationSequence = 0
        updateOngoingDownloadPriorities()
        startDownloadsIfNeeded()
    }

    @discardableResult
    func loadImage(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        completion: @escaping (DownloadableMediaImage?) -> Void
    ) -> (() -> Void)? {
        loadImage(
            for: descriptor,
            scheduling: .foreground,
            completion: completion
        )
    }

    @discardableResult
    func loadProvisionalImage(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        completion: @escaping (DownloadableMediaImage?) -> Void
    ) -> (() -> Void)? {
        loadImage(
            for: descriptor,
            scheduling: .preservingPrefetch,
            completion: completion
        )
    }

    private func loadImage(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        scheduling: ImageLoadScheduling,
        completion: @escaping (DownloadableMediaImage?) -> Void
    ) -> (() -> Void)? {
#if os(tvOS) || os(visionOS)
        cancelFinalizedFileRemovals(
            collectionId: descriptor.collectionId,
            fileNames: Set(fileNames(for: descriptor))
        )
#endif
        guard descriptor.isStaticImage else {
            Task { @MainActor in
                completion(nil)
            }
            return nil
        }

        let request = LoadRequest()
        let key = cacheKey(for: descriptor)
        let callback = ImageLoadCallback(
            request: request,
            descriptor: descriptor,
            completion: completion
        )
        completions[key, default: [:]][request.id] = callback
        reorderPendingImageDecodes()
#if os(tvOS) || os(visionOS)
        rescheduleFileEvictionIfNeeded(for: [descriptor])
#endif
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !request.isCancelled,
                  self.completions[key]?[request.id] != nil else {
                return
            }

            let cachedImageLookup = self.cachedDecodedImageLookup(forKey: key)
            if let cachedImage = cachedImageLookup.image {
                guard self.removeCompletion(forKey: key, requestId: request.id) else {
                    return
                }
                self.updateQueuedImageDecodeAfterDemandChange(forKey: key)
                if cachedImageLookup.recordsDiskAccess {
                    self.markCachedFileUsed(for: descriptor)
                }
                self.complete([callback], with: cachedImage)
                return
            }

            let fileURL = self.fileURL(for: descriptor)
            let availability = await self.currentFileAvailability(
                for: WindowFileCandidate(key: key, url: fileURL)
            )
            guard !request.isCancelled,
                  self.completions[key]?[request.id] != nil else {
                return
            }
            let hasFile = availability.hasFile(forKey: key) == true
            switch scheduling {
            case .foreground:
                self.prioritizeForegroundImageIfNeeded(
                    descriptor,
                    requireDecodedStaticImage: true,
                    hasFile: hasFile
                )
            case .preservingPrefetch:
                self.enqueueDownloadIfNeeded(
                    descriptor,
                    isForegroundRequest: true,
                    hasFile: hasFile
                )
            }
            if hasFile {
                self.markCachedFileUsed(for: descriptor)
                if self.activeDecodesByKey[key] == nil {
                    self.startImageDecode(
                        at: fileURL,
                        descriptor: descriptor,
                        key: key,
                        origin: .cachedFile
                    )
                } else {
                    self.reorderPendingImageDecodes()
                }
                return
            }

            self.startDownloadsIfNeeded(fileAvailability: availability)
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
            Task { @MainActor in
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
#if os(tvOS) || os(visionOS)
        cancelFinalizedFileRemovals(
            collectionId: descriptor.collectionId,
            fileNames: Set(fileNames(for: descriptor))
        )
#endif
        let request = LoadRequest()
        let key = cacheKey(for: descriptor)
        let callback = FileLoadCallback(
            request: request,
            descriptor: descriptor,
            completion: completion
        )
        fileCompletions[key, default: [:]][request.id] = callback
#if os(tvOS) || os(visionOS)
        rescheduleFileEvictionIfNeeded(for: [descriptor])
#endif
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !request.isCancelled,
                  self.fileCompletions[key]?[request.id] != nil else {
                return
            }
            let fileURL = self.fileURL(for: descriptor)
            let availability = await self.currentFileAvailability(
                for: WindowFileCandidate(key: key, url: fileURL)
            )
            guard !request.isCancelled,
                  self.fileCompletions[key]?[request.id] != nil else {
                return
            }
            let hasFile = self.ongoingDownloads[key]?.isFinalizing != true
                && availability.hasFile(forKey: key) == true
            guard !hasFile else {
                _ = self.removeFileCompletion(forKey: key, requestId: request.id)
                self.markCachedFileUsed(for: descriptor)
                self.completeFile([callback], with: fileURL)
                return
            }

            self.prioritizeForegroundImageIfNeeded(
                descriptor,
                requireDecodedStaticImage: false,
                hasFile: false
            )
            self.startDownloadsIfNeeded(fileAvailability: availability)
        }

        return { [weak self, request] in
            guard request.cancelIfNeeded() else { return }
            self?.cancelFileLoad(for: descriptor, requestId: request.id)
        }
    }

    private func cancelImageLoad(for descriptor: CollectionCatalogDownloadableMediaDescriptor, requestId: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cancelLoad(
                for: descriptor,
                requestId: requestId,
                updatesImageDecodePriority: true
            ) { key, requestId in
                self.removeCompletion(forKey: key, requestId: requestId)
            }
        }
    }

    private func currentFileAvailability(
        for candidate: WindowFileCandidate
    ) async -> WindowFileAvailability {
        while true {
            let revision = fileAvailabilityRevision.snapshot()
            let availability = await Self.fileAvailability(for: [candidate])
            if fileAvailabilityRevision.isCurrent(revision) {
                return availability
            }
        }
    }

    private func cancelFileLoad(for descriptor: CollectionCatalogDownloadableMediaDescriptor, requestId: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cancelLoad(
                for: descriptor,
                requestId: requestId,
                updatesImageDecodePriority: false
            ) { key, requestId in
                self.removeFileCompletion(forKey: key, requestId: requestId)
            }
        }
    }

    private func cancelLoad(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        requestId: UUID,
        updatesImageDecodePriority: Bool,
        removeCallback: (String, UUID) -> Bool
    ) {
        let key = cacheKey(for: descriptor)
        guard removeCallback(key, requestId) else { return }
        let didEndFileDemand = cancelFileWorkIfNoLongerNeeded(for: descriptor, key: key)
        if updatesImageDecodePriority {
            updateQueuedImageDecodeAfterDemandChange(forKey: key)
        }
#if os(tvOS) || os(visionOS)
        if didEndFileDemand {
            rescheduleFileEvictionIfNeeded(for: [descriptor])
        }
#endif
        guard didEndFileDemand else { return }
        startDownloadsIfNeeded()
    }

    private func removeCompletion(forKey key: String, requestId: UUID) -> Bool {
        removeCallback(
            forKey: key,
            requestId: requestId,
            from: &completions
        )
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
#if os(tvOS) || os(visionOS)
        cancelFinalizedFileRemovals(
            collectionId: descriptor.collectionId,
            fileNames: Set(fileNames(for: descriptor))
        )
#endif
        let key = cacheKey(for: descriptor)
        guard ongoingDownloads[key]?.isFinalizing != true else { return nil }
        let url = fileURL(for: descriptor)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
#if os(iOS) || os(macOS)
        markCachedFileUsed(for: descriptor)
#endif
        return url
    }

    func retainFile(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> @Sendable () -> Void {
        let key = cacheKey(for: descriptor)
        let collectionId = descriptor.collectionId
        let fileNameKeys = fileNames(for: descriptor).map {
            RetainedFileNameKey(collectionId: collectionId, fileName: $0)
        }
        let releaseToken = OneShotToken()

#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
#if os(tvOS) || os(visionOS)
        cancelScheduledFileEviction()
        cancelFinalizedFileRemovals(
            collectionId: collectionId,
            fileNames: Set(fileNameKeys.map(\.fileName))
        )
#endif
        retainedFileKeys[key, default: 0] += 1
        for fileNameKey in fileNameKeys {
            retainedFileNameKeys[fileNameKey, default: 0] += 1
        }
#if os(tvOS) || os(visionOS)
        if let activeWindow {
            scheduleFileEvictionOutsideWindow(
                collectionId: activeWindow.collectionId,
                allowedFileNames: activeWindow.fileNames
            )
        }
#endif
        updateOngoingDownloadPriorities()
        startDownloadsIfNeeded()

        return { [weak self, releaseToken] in
            guard releaseToken.take() else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.releaseRetainedFile(forKey: key, fileNameKeys: fileNameKeys)
                if !self.hasRetainedFile(forKey: key) {
                    self.handleRetainedDecodeFailureIfNeeded(forKey: key)
                    self.cancelFileWorkIfNoLongerNeeded(for: descriptor, key: key)
                }
                if let activeWindow,
                   activeWindow.collectionId == collectionId,
                   !Set(self.fileNames(for: descriptor)).isSubset(of: activeWindow.fileNames) {
#if os(iOS) || os(macOS)
                    self.scheduleDiskPruneCheck()
#elseif os(tvOS) || os(visionOS)
                    self.cancelScheduledFileEviction()
                    self.scheduleFileEvictionOutsideWindow(
                        collectionId: collectionId,
                        allowedFileNames: activeWindow.fileNames
                    )
#endif
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
        let key = cacheKey(for: descriptor)
        let lookup = cachedDecodedImageLookup(forKey: key)
        guard let image = lookup.image else { return nil }

#if os(iOS) || os(macOS)
        if lookup.recordsDiskAccess {
            markCachedFileUsed(for: descriptor)
        }
#endif
        return image
    }

#if DEBUG && os(iOS)
    nonisolated static func orderedPendingImageDecodeKeysForTesting(
        pendingKeys: [String],
        imageDemandKeys: Set<String>,
        foregroundKey: String?,
        preferredKeys: [String]
    ) -> [String] {
        orderedPendingImageDecodeKeys(
            pendingKeys: pendingKeys,
            imageDemandKeys: imageDemandKeys,
            foregroundKey: foregroundKey,
            preferredKeys: preferredKeys
        )
    }

    nonisolated static func shouldRetireQueuedImageDecodeForTesting(
        isInDecodedWindow: Bool,
        hasImageDemand: Bool,
        hasStarted: Bool
    ) -> Bool {
        shouldRetireQueuedImageDecode(
            isInDecodedWindow: isInDecodedWindow,
            hasImageDemand: hasImageDemand,
            hasStarted: hasStarted
        )
    }

    nonisolated static func imageDecodeGenerationStartResultsForTesting(
        invalidateBeforeStart: Bool
    ) -> [Bool] {
        let generation = ImageDecodeGeneration()
        if invalidateBeforeStart {
            generation.invalidate()
        }
        return [generation.beginIfCurrent(), generation.beginIfCurrent()]
    }

    func installDecodedImageForTesting(
        _ image: DownloadableMediaImage,
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        let key = cacheKey(for: descriptor)
        testingDecodedImagesLock.withLock {
            testingDecodedImages[key] = image
        }
    }

    func installMemoryCachedImageForTesting(
        _ image: DownloadableMediaImage,
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        cache(image, for: descriptor)
    }

    func removeDecodedImageForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        let key = cacheKey(for: descriptor)
        testingDecodedImagesLock.withLock {
            _ = testingDecodedImages.removeValue(forKey: key)
        }
    }

    func resetDecodedImagesForTesting() {
        clearDecodedImageMemory()
    }

    func waitForDecodedImageRetirementForTesting() async -> Bool? {
        await decodedImageRetirementTask?.value
    }

    func cachedFileURLForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> URL {
        fileURL(for: descriptor)
    }

    func fileNamesProtectedFromEvictionForTesting(
        collectionId: String,
        allowedFileNames: Set<String>
    ) -> Set<String> {
        fileNamesProtectedFromEviction(
            collectionId: collectionId,
            allowedFileNames: allowedFileNames
        )
    }

    func handleMemoryWarningForTesting() {
        handleMemoryWarning()
    }

    func hasForegroundFileWorkForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> Bool {
        let key = cacheKey(for: descriptor)
        return foregroundKey == key
            && foregroundWorkKeys.contains(key)
            && (pendingKeys.contains(key) || ongoingDownloads[key] != nil)
    }
#endif

    private func clearDecodedImageMemory() {
        let retiredCache = memoryCache
        let replacementCache = NSCache<NSString, DownloadableMediaImage>()
        replacementCache.countLimit = retiredCache.countLimit
        replacementCache.totalCostLimit = retiredCache.totalCostLimit
        memoryCache = replacementCache

#if DEBUG && os(iOS)
        let retainedImages = testingDecodedImagesLock.withLock {
            let images = Array(testingDecodedImages.values)
            testingDecodedImages.removeAll(keepingCapacity: false)
            return images
        }
#else
        let retainedImages = [DownloadableMediaImage]()
#endif
        let retirement = DecodedImageMemoryRetirement(
            cache: retiredCache,
            retainedImages: retainedImages
        )
        let previousTask = decodedImageRetirementTask
        let retirementLane = decodedImageRetirementLane
        decodedImageRetirementTask = Task(priority: .utility) {
            _ = await previousTask?.value
            return await retirementLane.retire(retirement)
        }
    }

    var webViewHTMLDirectoryURL: URL {
        cacheRoot.appendingPathComponent(Self.webViewHTMLDirectoryName, isDirectory: true)
    }

    var webViewReadAccessURL: URL {
        cacheRoot
    }

    private func notifyFileAvailabilityChanged(
        _ change: DownloadableMediaCacheFileAvailabilityChange,
        scope: FileAvailabilityScope = .all
    ) {
        invalidateFileAvailability()
        Task { @MainActor in
#if os(iOS) || os(macOS)
            NotificationCenter.default.post(
                name: .downloadableMediaCacheFileAvailabilityDidChange,
                object: change,
                userInfo: [Self.fileAvailabilityScopeUserInfoKey: scope]
            )
#else
            NotificationCenter.default.post(
                name: .downloadableMediaCacheFileAvailabilityDidChange,
                object: change
            )
#endif
        }
    }

    private func invalidateFileAvailability() {
        fileAvailabilityRevision.invalidate()
    }

    private func makeFileRemovalToken() -> CancellableFileRemovalToken {
        let revision = fileAvailabilityRevision
        return CancellableFileRemovalToken(
            tombstoneDirectoryURL: fileRemovalTombstoneDirectory,
            willClaimRemoval: revision.beginMutation,
            didClaimRemoval: revision.endMutation
        )
    }

    func fileAvailabilityChange(
        _ notification: Notification,
        affects descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> Bool {
        guard let scope = notification.userInfo?[Self.fileAvailabilityScopeUserInfoKey]
            as? FileAvailabilityScope else {
            return true
        }

        switch scope {
        case .file(let fileURL):
            return fileURL.standardizedFileURL == self.fileURL(for: descriptor).standardizedFileURL
        case .collection(let directoryURL):
            return directoryURL.standardizedFileURL
                == collectionDirectory(collectionId: descriptor.collectionId).standardizedFileURL
        case .all:
            return true
        }
    }

    func fileAvailabilityChange(
        _ notification: Notification,
        affectsCollection collectionId: String
    ) -> Bool {
        guard let scope = notification.userInfo?[Self.fileAvailabilityScopeUserInfoKey]
            as? FileAvailabilityScope else {
            return true
        }

        let directoryURL = collectionDirectory(collectionId: collectionId).standardizedFileURL
        switch scope {
        case .file(let fileURL):
            return fileURL.deletingLastPathComponent().standardizedFileURL == directoryURL
        case .collection(let changedDirectoryURL):
            return changedDirectoryURL.standardizedFileURL == directoryURL
        case .all:
            return true
        }
    }

    @discardableResult
    nonisolated private func removeItemIfPresent(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return false
        } catch {
            return false
        }
    }

    private func configureDecodedImageMemoryCacheLimit(decodedDescriptorCount: Int) {
#if os(iOS)
        if memoryCache.countLimit != Self.mediaFirstDecodedImageCountLimit {
            memoryCache.countLimit = Self.mediaFirstDecodedImageCountLimit
        }
        let totalCostLimit = Self.mediaFirstDecodedImageMemoryCostLimit
        if memoryCache.totalCostLimit != totalCostLimit {
            memoryCache.totalCostLimit = totalCostLimit
        }
#else
        let decodedCacheCountLimit = max(
            PlayerDownloadableMediaWindowLayout.decodedWindowCapacity,
            decodedDescriptorCount
        )
        if memoryCache.countLimit != decodedCacheCountLimit {
            memoryCache.countLimit = decodedCacheCountLimit
        }
        let descriptorDerivedCostLimit = Self.decodedImageMemoryCostLimit(
            for: decodedCacheCountLimit
        )
#if os(macOS)
        let decodedCacheTotalCostLimit = min(
            descriptorDerivedCostLimit,
            Self.macDecodedImageMemoryCostLimit
        )
#else
        let decodedCacheTotalCostLimit = descriptorDerivedCostLimit
#endif
        if memoryCache.totalCostLimit != decodedCacheTotalCostLimit {
            memoryCache.totalCostLimit = decodedCacheTotalCostLimit
        }
#endif
    }

#if os(macOS)
    private static var macDecodedImageMemoryCostLimit: Int {
        let physicalMemoryLimit = min(
            ProcessInfo.processInfo.physicalMemory / 8,
            UInt64(1024 * 1024 * 1024)
        )
        return max(defaultDecodedImageMemoryCostLimit, Int(physicalMemoryLimit))
    }
#endif

#if os(iOS)
    private static var mediaFirstDecodedImageMemoryCostLimit: Int {
        let boundedLimit = min(
            max(
                ProcessInfo.processInfo.physicalMemory / 4,
                minimumMediaFirstDecodedImageMemoryCostLimit
            ),
            maximumMediaFirstDecodedImageMemoryCostLimit
        )
        return Int(boundedLimit)
    }

    private func handleMemoryWarning() {
        let foregroundDescriptor = activeForegroundDescriptor
        let preservedForegroundKey = foregroundDescriptor.map(cacheKey(for:))
        cancelScheduledWindowWork()
        suppressesPrefetchDecodeUntilNextWindowWork = true
        clearDecodedImageMemory()
        invalidateUndemandedDecodeWork()
        cancelPrefetchDownloadsAndPendingWork(
            preservingForegroundKey: preservedForegroundKey
        )
        guard let foregroundDescriptor else {
            foregroundKey = nil
            foregroundWorkKeys.removeAll()
            return
        }
        prioritizeForegroundImageIfNeeded(
            foregroundDescriptor,
            requireDecodedStaticImage: false
        )
        startDownloadsIfNeeded()
    }

    private var activeForegroundDescriptor: CollectionCatalogDownloadableMediaDescriptor? {
        if let registration = exclusiveWindowRegistration,
           !registration.isSuspended {
            return registration.mediaWindow.currentDescriptor
        }
        return managedWindowsByOwnerId.values
            .filter { !$0.isSuspended }
            .max { $0.preparationSequence < $1.preparationSequence }?
            .mediaWindow.currentDescriptor
    }

    private func invalidateUndemandedDecodeWork() {
        let keysToInvalidate = Set(activeDecodesByKey.keys.filter { key in
            Self.shouldRetireQueuedImageDecode(
                isInDecodedWindow: false,
                hasImageDemand: hasImageDemandCallbacks(forKey: key),
                hasStarted: isImageDecodeRunning(forKey: key)
            )
        })
        invalidateImageDecodes(for: keysToInvalidate)
    }

#endif

    private func invalidateUndemandedDecodeWork(
        outside decodedWindowKeys: Set<String>,
        startsDrain: Bool
    ) {
        let keysToInvalidate = Set(activeDecodesByKey.keys.filter { key in
            Self.shouldRetireQueuedImageDecode(
                isInDecodedWindow: decodedWindowKeys.contains(key),
                hasImageDemand: hasImageDemandCallbacks(forKey: key),
                hasStarted: isImageDecodeRunning(forKey: key)
            )
        })
        invalidateImageDecodes(
            for: keysToInvalidate,
            startsDrain: startsDrain
        )
    }

    private func invalidateImageDecodes(
        for keys: Set<String>,
        startsDrain: Bool = true
    ) {
        for key in keys {
            activeDecodesByKey.removeValue(forKey: key)?.generation.invalidate()
        }
        pendingDecodeKeys.removeAll { keys.contains($0) }
        if startsDrain {
            startNextImageDecodeIfNeeded()
        }
    }

    private func updateQueuedImageDecodeAfterDemandChange(forKey key: String) {
        if Self.shouldRetireQueuedImageDecode(
            isInDecodedWindow: activeWindow?.decodedKeys.contains(key) == true,
            hasImageDemand: hasImageDemandCallbacks(forKey: key),
            hasStarted: isImageDecodeRunning(forKey: key)
        ) {
            invalidateImageDecodes(for: [key])
            return
        }
        reorderPendingImageDecodes()
    }

    nonisolated private static func shouldRetireQueuedImageDecode(
        isInDecodedWindow: Bool,
        hasImageDemand: Bool,
        hasStarted: Bool
    ) -> Bool {
        !isInDecodedWindow && !hasImageDemand && !hasStarted
    }

    private func invalidateAllImageDecodes() {
        activeDecodesByKey.values.forEach { $0.generation.invalidate() }
        activeDecodesByKey.removeAll()
        pendingDecodeKeys.removeAll()
    }

#if os(iOS) || os(macOS)
    private func scheduleDiskPruneCheck(
        protecting extraProtectedDescriptors: [CollectionCatalogDownloadableMediaDescriptor] = [],
        reason: DiskPruneReason = .routine
    ) {
        queueDiskPruneRequest(DiskPruneRequest(
            bypassRoutineThrottle: reason == .afterWrite,
            protectedPaths: Set(extraProtectedDescriptors.flatMap(diskCachePaths(for:)))
        ))
    }

    private func schedulePostWriteDiskPruneCheck(
        protecting descriptor: CollectionCatalogDownloadableMediaDescriptor,
        addedBytes: Int64
    ) {
        diskCacheBytesAddedSinceLastEstimate += max(addedBytes, 0)
        guard shouldSchedulePostWriteDiskPruneCheck() else { return }

        scheduleDiskPruneCheck(protecting: [descriptor], reason: .afterWrite)
    }

    private func shouldSchedulePostWriteDiskPruneCheck() -> Bool {
        guard let estimatedDiskCacheBytes else { return true }

        let projectedCacheBytes = estimatedDiskCacheBytes + diskCacheBytesAddedSinceLastEstimate
        if projectedCacheBytes > Self.maximumDiskCacheBytes {
            return true
        }

        guard let estimatedAvailableDiskBytes else { return false }
        return estimatedAvailableDiskBytes - diskCacheBytesAddedSinceLastEstimate < Self.minimumAvailableDiskBytes
    }

    private func invalidateEstimatedDiskCacheState() {
        estimatedDiskCacheBytes = nil
        estimatedAvailableDiskBytes = nil
        diskCacheBytesAddedSinceLastEstimate = 0
#if os(macOS)
        recordDiskCacheMutation()
#endif
    }

    private func cancelDiskPruneRemovalIfNeeded() {
        guard let diskPruneRemovalToken else { return }
        diskPruneRemovalToken.cancel()
        self.diskPruneRemovalToken = nil
#if os(macOS)
        diskCacheMutationGeneration &+= 1
#endif
    }

#if os(macOS)
    private func recordDiskCacheMutation() {
        if diskPruneRemovalToken != nil {
            cancelDiskPruneRemovalIfNeeded()
        } else {
            diskCacheMutationGeneration &+= 1
        }
    }
#endif

    private func queueDiskPruneRequest(_ request: DiskPruneRequest) {
        if var pendingDiskPruneRequest {
            pendingDiskPruneRequest.merge(request)
            self.pendingDiskPruneRequest = pendingDiskPruneRequest
        } else {
            pendingDiskPruneRequest = request
        }

#if os(macOS)
        if diskPruneMutationDeferralDeadline != nil,
           hasReliableEstimatedDiskPressure() {
            resetDiskPruneMutationDeferral()
        }
#endif
        schedulePendingDiskPruneCheckIfNeeded()
    }

    private func schedulePendingDiskPruneCheckIfNeeded() {
        guard pendingDiskPruneRequest != nil,
              !isDiskPruneCheckScheduled,
              !isDiskPruneRunning else {
            return
        }

        isDiskPruneCheckScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.diskPruneCheckDebounceInterval))
            guard let self else { return }

            self.isDiskPruneCheckScheduled = false
#if os(macOS)
            self.handleScheduledDiskPruneCheck()
#else
            self.startPendingDiskPruneCheckIfNeeded()
#endif
        }
    }

#if os(macOS)
    private func handleScheduledDiskPruneCheck() {
        guard let deferralDeadline = diskPruneMutationDeferralDeadline,
              let deferralGeneration = diskPruneMutationDeferralGeneration else {
            startPendingDiskPruneCheckIfNeeded()
            return
        }

        let didReachMaximumDeferral = DispatchTime.now() >= deferralDeadline
        guard diskCacheMutationGeneration == deferralGeneration
                || didReachMaximumDeferral else {
            diskPruneMutationDeferralGeneration = diskCacheMutationGeneration
            schedulePendingDiskPruneCheckIfNeeded()
            return
        }

        resetDiskPruneMutationDeferral()
        startPendingDiskPruneCheckIfNeeded()
    }

    private func deferDiskPruneRetryUntilMutationsSettle(_ request: DiskPruneRequest) {
        if var pendingDiskPruneRequest {
            pendingDiskPruneRequest.merge(request)
            self.pendingDiskPruneRequest = pendingDiskPruneRequest
        } else {
            pendingDiskPruneRequest = request
        }
        if diskPruneMutationDeferralDeadline == nil {
            diskPruneMutationDeferralDeadline =
                .now() + Self.diskPruneMaximumMutationDeferralInterval
        }
        diskPruneMutationDeferralGeneration = diskCacheMutationGeneration
        schedulePendingDiskPruneCheckIfNeeded()
    }

    private func resetDiskPruneMutationDeferral() {
        diskPruneMutationDeferralDeadline = nil
        diskPruneMutationDeferralGeneration = nil
    }

    private func hasReliableEstimatedDiskPressure() -> Bool {
        guard let estimatedDiskCacheBytes else { return false }

        let (projectedCacheBytes, didCacheBytesOverflow) = estimatedDiskCacheBytes
            .addingReportingOverflow(diskCacheBytesAddedSinceLastEstimate)
        if didCacheBytesOverflow || projectedCacheBytes > Self.maximumDiskCacheBytes {
            return true
        }

        guard let estimatedAvailableDiskBytes else { return false }
        let (projectedAvailableDiskBytes, didAvailableBytesOverflow) = estimatedAvailableDiskBytes
            .subtractingReportingOverflow(diskCacheBytesAddedSinceLastEstimate)
        return didAvailableBytesOverflow
            || projectedAvailableDiskBytes < Self.minimumAvailableDiskBytes
    }
#endif

    private func startPendingDiskPruneCheckIfNeeded() {
        guard let request = pendingDiskPruneRequest else { return }
        pendingDiskPruneRequest = nil

        guard consumeDiskPruneThrottle(for: request) else { return }

#if os(macOS)
        if let estimatedDiskCacheBytes {
            let (updatedCacheBytes, didOverflow) = estimatedDiskCacheBytes
                .addingReportingOverflow(diskCacheBytesAddedSinceLastEstimate)
            self.estimatedDiskCacheBytes = didOverflow ? Int64.max : updatedCacheBytes
        }
        if let estimatedAvailableDiskBytes {
            let (updatedAvailableBytes, didOverflow) = estimatedAvailableDiskBytes
                .subtractingReportingOverflow(diskCacheBytesAddedSinceLastEstimate)
            self.estimatedAvailableDiskBytes = didOverflow ? Int64.min : updatedAvailableBytes
        }
#endif
        diskCacheBytesAddedSinceLastEstimate = 0
        isDiskPruneRunning = true

#if os(iOS) || os(macOS)
        let diskPruneRemovalToken = makeFileRemovalToken()
        self.diskPruneRemovalToken = diskPruneRemovalToken
#endif
#if os(macOS)
        let diskCacheMutationGeneration = self.diskCacheMutationGeneration
#endif
        Task { @MainActor [weak self, request] in
            guard let self else { return }

#if os(macOS)
            let result = await self.pruneDiskCacheIfNeeded(
                protectedPaths: request.protectedPaths,
                mutationGeneration: diskCacheMutationGeneration,
                removalToken: diskPruneRemovalToken
            )
#else
            let result = await self.pruneDiskCacheIfNeeded(
                protectedPaths: request.protectedPaths,
                removalToken: diskPruneRemovalToken
            )
#endif

#if os(iOS) || os(macOS)
            if self.diskPruneRemovalToken === diskPruneRemovalToken {
                self.diskPruneRemovalToken = nil
            }
#endif
#if os(macOS)
            if self.diskCacheMutationGeneration != diskCacheMutationGeneration {
                self.isDiskPruneRunning = false
                if result.didRemoveItem {
                    self.notifyFileAvailabilityChanged(.becameUnavailable)
                }
                let scanStillNeedsPrune = result.cacheBytesAfterPrune > Self.maximumDiskCacheBytes
                    || result.availableDiskBytesAfterPrune.map {
                        $0 < Self.minimumAvailableDiskBytes
                    } == true
                if result.didRemoveItem || self.estimatedDiskCacheBytes == nil {
                    self.estimatedDiskCacheBytes = nil
                    self.estimatedAvailableDiskBytes = nil
                    self.diskCacheBytesAddedSinceLastEstimate = 0
                }
                var retryRequest = request
                retryRequest.bypassRoutineThrottle = true
                retryRequest.protectedPaths.removeAll()
                if scanStillNeedsPrune || self.hasReliableEstimatedDiskPressure() {
                    self.resetDiskPruneMutationDeferral()
                    self.queueDiskPruneRequest(retryRequest)
                } else {
                    self.deferDiskPruneRetryUntilMutationsSettle(retryRequest)
                }
                return
            }
            self.resetDiskPruneMutationDeferral()
#endif
            self.isDiskPruneRunning = false
            self.estimatedDiskCacheBytes = result.cacheBytesAfterPrune
            self.estimatedAvailableDiskBytes = result.availableDiskBytesAfterPrune
            if result.didRemoveItem {
                self.notifyFileAvailabilityChanged(.becameUnavailable)
            }
#if os(iOS)
            if !diskPruneRemovalToken.isActive {
                var retryRequest = request
                retryRequest.bypassRoutineThrottle = true
                retryRequest.protectedPaths.removeAll()
                self.queueDiskPruneRequest(retryRequest)
                return
            }
#endif
            self.schedulePendingDiskPruneCheckIfNeeded()
        }
    }

    private func consumeDiskPruneThrottle(for request: DiskPruneRequest) -> Bool {
        guard !request.bypassRoutineThrottle else { return true }

        let now = Date()
        if let lastRoutineDiskPruneCheckDate,
           now.timeIntervalSince(lastRoutineDiskPruneCheckDate) < Self.diskPruneCheckInterval {
            return false
        }

        lastRoutineDiskPruneCheckDate = now
        return true
    }

#if os(macOS)
    @concurrent
    private func pruneDiskCacheIfNeeded(
        protectedPaths requestedProtectedPaths: Set<String>,
        mutationGeneration: UInt64,
        removalToken: CancellableFileRemovalToken
    ) async -> DiskPruneResult {
        if let fileRemovalTombstoneDirectory {
            await diskMutationLane.removeFileRemovalTombstones(
                at: fileRemovalTombstoneDirectory
            )
        } else {
            await diskMutationLane.removeFallbackFileRemovalTombstones(
                at: cacheRoot
            )
        }
        let snapshot = diskCacheSnapshot()
        let mediaCacheBytes = snapshot.entries.reduce(Int64(0)) { $0 + $1.size }
        let orphanMetadataBytes = snapshot.orphanMetadataEntries.reduce(Int64(0)) { $0 + $1.size }
        let totalCacheBytes = mediaCacheBytes + orphanMetadataBytes
        let availableDiskBytes = availableDiskBytes()
        let isOverCacheLimit = totalCacheBytes > Self.maximumDiskCacheBytes
        let isUnderFreeSpaceLimit = availableDiskBytes.map { $0 < Self.minimumAvailableDiskBytes } ?? false
        guard isOverCacheLimit || isUnderFreeSpaceLimit else {
            return DiskPruneResult(
                didRemoveItem: false,
                cacheBytesAfterPrune: totalCacheBytes,
                availableDiskBytesAfterPrune: availableDiskBytes
            )
        }
        var freedCacheBytes: Int64 = 0
        var freedDiskBytes: Int64 = 0
        var didRemoveItem = false

        func didReachPruneTargets() -> Bool {
            let projectedCacheBytes = totalCacheBytes - freedCacheBytes
            let projectedAvailableBytes = availableDiskBytes.map { $0 + freedDiskBytes }
            let didReachCacheTarget = projectedCacheBytes <= Self.targetDiskCacheBytes
            let didReachFreeSpaceTarget = projectedAvailableBytes.map {
                $0 >= Self.minimumAvailableDiskBytes
            } ?? true
            return didReachCacheTarget && didReachFreeSpaceTarget
        }

        func currentResult() -> DiskPruneResult {
            DiskPruneResult(
                didRemoveItem: didRemoveItem,
                cacheBytesAfterPrune: totalCacheBytes - freedCacheBytes,
                availableDiskBytesAfterPrune: availableDiskBytes.map { $0 + freedDiskBytes }
            )
        }

        func apply(_ removal: DiskPruneRemovalResult) {
            freedCacheBytes += removal.removedCacheBytes
            freedDiskBytes += removal.freedDiskBytes
            didRemoveItem = didRemoveItem || removal.didRemoveItem
        }

        var orphanIndex = 0
        while orphanIndex < snapshot.orphanMetadataEntries.count {
            let batchEnd = min(
                orphanIndex + Self.diskPruneCandidateBatchSize,
                snapshot.orphanMetadataEntries.count
            )
            let candidates = snapshot.orphanMetadataEntries[orphanIndex..<batchEnd].map {
                DiskPruneCandidate(
                    filePaths: [$0.path],
                    primaryFile: (url: $0.url, size: $0.size),
                    sidecarFile: nil
                )
            }
            let removal = await removeDiskCacheCandidatesIfUnprotected(
                candidates,
                removalByteTarget: nil,
                extraProtectedPaths: requestedProtectedPaths,
                mutationGeneration: mutationGeneration,
                removalToken: removalToken
            )
            apply(removal)
            guard removal.wasCurrent else {
                return currentResult()
            }
            guard removal.processedCandidateCount > 0 else {
                return currentResult()
            }
            orphanIndex += removal.processedCandidateCount
        }

        guard !didReachPruneTargets() else {
            return currentResult()
        }

        let sortedEntries = snapshot.entries.sorted { $0.lastAccessDate < $1.lastAccessDate }
        var mediaIndex = 0
        while mediaIndex < sortedEntries.count, !didReachPruneTargets() {
            let remainingCacheDeficit = max(
                totalCacheBytes - freedCacheBytes - Self.targetDiskCacheBytes,
                0
            )
            let remainingFreeSpaceDeficit = availableDiskBytes.map {
                max(Self.minimumAvailableDiskBytes - ($0 + freedDiskBytes), 0)
            } ?? 0
            let removalByteTarget = max(remainingCacheDeficit, remainingFreeSpaceDeficit)
            guard removalByteTarget > 0 else { break }

            let batchEnd = min(
                mediaIndex + Self.diskPruneCandidateBatchSize,
                sortedEntries.count
            )
            let candidates = sortedEntries[mediaIndex..<batchEnd].map { entry in
                return DiskPruneCandidate(
                    filePaths: entry.filePaths,
                    primaryFile: (url: entry.mediaURL, size: entry.mediaSize),
                    sidecarFile: entry.metadataURL.map {
                        (url: $0, size: entry.metadataSize)
                    }
                )
            }
            let removal = await removeDiskCacheCandidatesIfUnprotected(
                candidates,
                removalByteTarget: removalByteTarget,
                extraProtectedPaths: requestedProtectedPaths,
                mutationGeneration: mutationGeneration,
                removalToken: removalToken
            )
            apply(removal)
            guard removal.wasCurrent else {
                return currentResult()
            }
            guard removal.processedCandidateCount > 0 else {
                return currentResult()
            }
            mediaIndex += removal.processedCandidateCount
        }

        return currentResult()
    }

    @concurrent
    private func removeDiskCacheCandidatesIfUnprotected(
        _ candidates: [DiskPruneCandidate],
        removalByteTarget: Int64?,
        extraProtectedPaths: Set<String>,
        mutationGeneration: UInt64,
        removalToken: CancellableFileRemovalToken
    ) async -> DiskPruneRemovalResult {
        guard let context = await diskPruneRemovalContext(
            extraProtectedPaths: extraProtectedPaths,
            mutationGeneration: mutationGeneration,
            removalToken: removalToken
        ) else {
            return DiskPruneRemovalResult(
                wasCurrent: false,
                processedCandidateCount: 0,
                didRemoveItem: false,
                removedCacheBytes: 0,
                freedDiskBytes: 0
            )
        }
        return await diskMutationLane.removeDiskCacheCandidates(
            candidates,
            removalByteTarget: removalByteTarget,
            protectedPaths: context.protectedPaths,
            token: context.token
        )
    }

    private func diskPruneRemovalContext(
        extraProtectedPaths: Set<String>,
        mutationGeneration: UInt64,
        removalToken: CancellableFileRemovalToken
    ) -> DiskPruneRemovalContext? {
        guard diskCacheMutationGeneration == mutationGeneration,
              diskPruneRemovalToken === removalToken,
              removalToken.isActive else {
            return nil
        }
        return DiskPruneRemovalContext(
            protectedPaths: protectedDiskCachePaths(
                extraProtectedPaths: extraProtectedPaths
            ),
            token: removalToken
        )
    }
#else
    @concurrent
    private func pruneDiskCacheIfNeeded(
        protectedPaths requestedProtectedPaths: Set<String>,
        removalToken: CancellableFileRemovalToken
    ) async -> DiskPruneResult {
        if let fileRemovalTombstoneDirectory {
            await diskMutationLane.removeFileRemovalTombstones(
                at: fileRemovalTombstoneDirectory
            )
        } else {
            await diskMutationLane.removeFallbackFileRemovalTombstones(
                at: cacheRoot
            )
        }
        let snapshot = diskCacheSnapshot()
        let mediaCacheBytes = snapshot.entries.reduce(Int64(0)) { $0 + $1.size }
        let orphanMetadataBytes = snapshot.orphanMetadataEntries.reduce(Int64(0)) { $0 + $1.size }
        let totalCacheBytes = mediaCacheBytes + orphanMetadataBytes
        let availableDiskBytes = availableDiskBytes()
        let isOverCacheLimit = totalCacheBytes > Self.maximumDiskCacheBytes
        let isUnderFreeSpaceLimit = availableDiskBytes.map { $0 < Self.minimumAvailableDiskBytes } ?? false
        guard isOverCacheLimit || isUnderFreeSpaceLimit else {
            return DiskPruneResult(
                didRemoveItem: false,
                cacheBytesAfterPrune: totalCacheBytes,
                availableDiskBytesAfterPrune: availableDiskBytes
            )
        }
        let protectedPaths = await protectedDiskCachePaths(
            extraProtectedPaths: requestedProtectedPaths
        )

        var freedCacheBytes: Int64 = 0
        var freedDiskBytes: Int64 = 0
        var didRemoveItem = false

        func currentResult() -> DiskPruneResult {
            DiskPruneResult(
                didRemoveItem: didRemoveItem,
                cacheBytesAfterPrune: totalCacheBytes - freedCacheBytes,
                availableDiskBytesAfterPrune: availableDiskBytes.map { $0 + freedDiskBytes }
            )
        }

        func didReachPruneTargets() -> Bool {
            let projectedCacheBytes = totalCacheBytes - freedCacheBytes
            let projectedAvailableBytes = availableDiskBytes.map { $0 + freedDiskBytes }
            let didReachCacheTarget = projectedCacheBytes <= Self.targetDiskCacheBytes
            let didReachFreeSpaceTarget = projectedAvailableBytes.map {
                $0 >= Self.minimumAvailableDiskBytes
            } ?? true
            return didReachCacheTarget && didReachFreeSpaceTarget
        }

        for entry in snapshot.orphanMetadataEntries {
            guard !protectedPaths.contains(entry.path) else {
                continue
            }
            let removal = await diskMutationLane.removeOrphanMetadata(
                at: entry.url,
                ifMediaMissingAt: entry.mediaURL,
                token: removalToken
            )
            switch removal {
            case .removed:
                freedCacheBytes += entry.size
                freedDiskBytes += entry.size
                didRemoveItem = true
            case .stagedForCleanup:
                freedCacheBytes += entry.size
                didRemoveItem = true
            case .notRemoved:
                continue
            case .cancelled:
                return currentResult()
            }
        }

        guard !didReachPruneTargets() else {
            return currentResult()
        }

        for entry in snapshot.entries.sorted(by: { $0.lastAccessDate < $1.lastAccessDate }) {
            guard entry.filePaths.isDisjoint(with: protectedPaths) else { continue }

            let removal = await diskMutationLane.removeCachePair(
                mediaURL: entry.mediaURL,
                metadataURL: entry.metadataURL,
                token: removalToken
            )
            if removal.primary == .cancelled {
                return currentResult()
            }
            let removedMedia = removal.primary.removedFromCache
            let removedMetadata = removal.sidecar?.removedFromCache == true
            let entryRemovedCacheBytes = (removedMedia ? entry.mediaSize : 0)
                + (removedMetadata ? entry.metadataSize : 0)
            let entryFreedDiskBytes = (removal.primary.freedStorage ? entry.mediaSize : 0)
                + (removal.sidecar?.freedStorage == true ? entry.metadataSize : 0)
            guard removedMedia || removedMetadata else { continue }

            freedCacheBytes += entryRemovedCacheBytes
            freedDiskBytes += entryFreedDiskBytes
            didRemoveItem = true

            if didReachPruneTargets() {
                break
            }
        }

        return currentResult()
    }
#endif

    nonisolated private func diskCacheSnapshot() -> (entries: [DiskCacheEntry], orphanMetadataEntries: [DiskCacheOrphanMetadataEntry]) {
        guard let collectionDirectories = try? FileManager.default.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }

        var entries = [DiskCacheEntry]()
        var orphanMetadataEntries = [DiskCacheOrphanMetadataEntry]()
        for directoryURL in collectionDirectories where directoryURL.lastPathComponent != Self.webViewHTMLDirectoryName {
            let directoryValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard directoryValues?.isDirectory == true,
                  let fileURLs = try? FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [
                        .contentAccessDateKey,
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isDirectoryKey
                    ],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            let fileSnapshotsByName = Dictionary(uniqueKeysWithValues: fileURLs.map {
                ($0.lastPathComponent, DiskCacheFileSnapshot(url: $0))
            })
            let fileNames = Set(fileSnapshotsByName.keys)
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                guard let fileSnapshot = fileSnapshotsByName[fileName],
                      !fileSnapshot.isDirectory else {
                    continue
                }

                guard !fileName.hasSuffix(Self.downloadedMediaMetadataFileSuffix) else {
                    let mediaFileName = String(fileName.dropLast(Self.downloadedMediaMetadataFileSuffix.count))
                    if !fileNames.contains(mediaFileName) {
                        orphanMetadataEntries.append(DiskCacheOrphanMetadataEntry(
                            url: fileSnapshot.url,
                            mediaURL: directoryURL.appendingPathComponent(mediaFileName),
                            path: diskCachePath(for: fileSnapshot.url),
                            size: fileSnapshot.size
                        ))
                    }
                    continue
                }

                let metadataFileName = "\(fileName)\(Self.downloadedMediaMetadataFileSuffix)"
                let metadataSnapshot = fileSnapshotsByName[metadataFileName]
                let metadataURL = metadataSnapshot?.url
                var filePaths = Set([diskCachePath(for: fileURL)])
                if let metadataURL {
                    filePaths.insert(diskCachePath(for: metadataURL))
                }
                entries.append(DiskCacheEntry(
                    mediaURL: fileURL,
                    metadataURL: metadataURL,
                    filePaths: filePaths,
                    mediaSize: fileSnapshot.size,
                    metadataSize: metadataSnapshot?.size ?? 0,
                    lastAccessDate: fileSnapshot.contentAccessDate
                        ?? fileSnapshot.contentModificationDate
                        ?? .distantPast
                ))
            }
        }
        return (entries, orphanMetadataEntries)
    }

    private func protectedDiskCachePaths(extraProtectedPaths: Set<String> = []) -> Set<String> {
        var protectedPaths = extraProtectedPaths
        if let activeWindow {
            let directory = collectionDirectory(collectionId: activeWindow.collectionId)
            for fileName in activeWindow.fileNames {
                protectedPaths.insert(diskCachePath(for: directory.appendingPathComponent(fileName)))
            }
        }
        for fileNameKey in retainedFileNameKeys.keys {
            let directory = collectionDirectory(collectionId: fileNameKey.collectionId)
            protectedPaths.insert(diskCachePath(for: directory.appendingPathComponent(fileNameKey.fileName)))
        }
        for descriptor in pendingDescriptors {
            protectedPaths.formUnion(diskCachePaths(for: descriptor))
        }
        for download in ongoingDownloads.values {
            protectedPaths.formUnion(diskCachePaths(for: download.descriptor))
        }
        for activeDecode in activeDecodesByKey.values {
            protectedPaths.formUnion(diskCachePaths(for: activeDecode.descriptor))
        }
        for descriptor in retainedDecodeFailureDescriptors.values {
            protectedPaths.formUnion(diskCachePaths(for: descriptor))
        }
        return protectedPaths
    }

    nonisolated private func availableDiskBytes() -> Int64? {
        guard let values = try? cacheRoot.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else {
            return nil
        }

        if let importantCapacity = values.volumeAvailableCapacityForImportantUsage {
            return importantCapacity
        }
        return values.volumeAvailableCapacity.map(Int64.init)
    }

    nonisolated private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func markCachedFileUsed(for descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        scheduleCachedFileTouch(at: fileURL(for: descriptor))
    }

    private func scheduleCachedFileTouch(at url: URL) {
        let path = diskCachePath(for: url)
        let now = Date()
        if let lastTouchDate = cachedFileTouchDates[path],
           now.timeIntervalSince(lastTouchDate) < Self.cachedFileTouchMinimumInterval {
            return
        }

        pendingCachedFileTouchURLs[path] = url
        guard !isCachedFileTouchScheduled else { return }

        isCachedFileTouchScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.cachedFileTouchDebounceInterval))
            self?.flushCachedFileTouches()
        }
    }

    private func flushCachedFileTouches() {
        isCachedFileTouchScheduled = false
        let urls = Array(pendingCachedFileTouchURLs.values)
        let paths = Array(pendingCachedFileTouchURLs.keys)
        pendingCachedFileTouchURLs.removeAll(keepingCapacity: true)
        guard !urls.isEmpty else { return }

        let now = Date()
        for path in paths {
            cachedFileTouchDates[path] = now
        }
        pruneCachedFileTouchHistoryIfNeeded()

        Task(priority: .utility) {
            await Self.touchCachedFiles(at: urls)
        }
    }

    @concurrent
    nonisolated private static func touchCachedFiles(at urls: [URL]) async {
        urls.forEach(touchCachedFile)
    }

    private func pruneCachedFileTouchHistoryIfNeeded() {
        guard cachedFileTouchDates.count > Self.cachedFileTouchHistoryLimit else { return }

        cachedFileTouchDates = Dictionary(uniqueKeysWithValues: cachedFileTouchDates
            .sorted { $0.value > $1.value }
            .prefix(Self.cachedFileTouchHistoryLimit)
            .map { ($0.key, $0.value) })
    }

    nonisolated private static func touchCachedFile(at url: URL) {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.contentAccessDate = Date()
        try? mutableURL.setResourceValues(resourceValues)
    }

    nonisolated private func diskCachePaths(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> [String] {
        [fileURL(for: descriptor), metadataFileURL(for: descriptor)].map(diskCachePath(for:))
    }

    nonisolated private func diskCachePath(for url: URL) -> String {
        url.standardizedFileURL.path
    }
#else
    private func markCachedFileUsed(for _: CollectionCatalogDownloadableMediaDescriptor) {}
#endif

    private func enqueueDownloadIfNeeded(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        isForegroundRequest: Bool,
        hasFile knownFileAvailability: Bool? = nil
    ) {
        let key = cacheKey(for: descriptor)
        if let ongoingDownload = ongoingDownloads[key] {
            if isForegroundRequest {
                ongoingDownload.task.priority = downloadTaskPriority(forKey: key)
            }
            return
        }

        if pendingKeys.contains(key) {
            guard isForegroundRequest else { return }
            pendingDescriptors.removeAll { cacheKey(for: $0) == key }
            pendingDescriptors.insert(descriptor, at: 0)
            return
        }

        let hasFile = knownFileAvailability
            ?? FileManager.default.fileExists(atPath: fileURL(for: descriptor).path)
        guard !hasFile else { return }

        pendingKeys.insert(key)
        if isForegroundRequest {
            pendingDescriptors.insert(descriptor, at: 0)
        } else {
            pendingDescriptors.append(descriptor)
        }
    }

    private func startDownloadsIfNeeded(fileAvailability: WindowFileAvailability? = nil) {
        while ongoingDownloads.count < maximumConcurrentDownloads {
            guard let descriptor = popNextStartablePendingDescriptor(
                fileAvailability: fileAvailability
            ) else { return }
            let key = cacheKey(for: descriptor)

            let downloadId = UUID()
            let stagingRoot = self.stagingRoot
            let task = session.downloadTask(with: descriptor.url) { [weak self] tmpURL, response, error in
                let stagedURL = Self.stageDownloadFile(
                    tmpURL,
                    response: response,
                    error: error,
                    stagingRoot: stagingRoot
                )
                Task { @MainActor [weak self] in
                    await self?.finishDownload(
                        descriptor: descriptor,
                        downloadId: downloadId,
                        tmpURL: stagedURL,
                        response: response,
                        error: error
                    )
                }
            }
            task.priority = downloadTaskPriority(forKey: key)
            ongoingDownloads[key] = OngoingDownload(
                task: task,
                descriptor: descriptor,
                id: downloadId
            )
            task.resume()
        }
    }

    private func popNextStartablePendingDescriptor(
        fileAvailability: WindowFileAvailability?
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
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

            let hasFile = fileAvailability?.hasFile(forKey: key)
                ?? FileManager.default.fileExists(atPath: fileURL(for: descriptor).path)
            if hasFile {
                pendingDescriptors.remove(at: index)
                pendingKeys.remove(key)
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
    ) async {
#if os(iOS) || os(macOS)
        var downloadedCacheBytes: Int64?
        defer {
            if let downloadedCacheBytes {
                schedulePostWriteDiskPruneCheck(protecting: descriptor, addedBytes: downloadedCacheBytes)
            }
        }
#endif
        let key = cacheKey(for: descriptor)
        guard ongoingDownloads[key]?.id == downloadId else {
            if let tmpURL {
                try? FileManager.default.removeItem(at: tmpURL)
            }
            return
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil,
              (200...299).contains(statusCode) else {
            guard let state = removeDownloadState(forKey: key, downloadId: downloadId) else { return }
            let (callbacks, fileCallbacks) = state
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }
        guard let tmpURL else {
            guard let state = removeDownloadState(forKey: key, downloadId: downloadId) else { return }
            let (callbacks, fileCallbacks) = state
#if os(iOS) || os(macOS)
            scheduleDiskPruneCheck(protecting: [descriptor], reason: .afterWrite)
#endif
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

#if !os(iOS)
        let shouldStoreDownloadedFile = isDescriptorInActiveWindow(descriptor)
            || completions[key]?.isEmpty == false
            || fileCompletions[key]?.isEmpty == false
            || hasRetainedFile(forKey: key)
        guard shouldStoreDownloadedFile else {
            guard let state = removeDownloadState(forKey: key, downloadId: downloadId) else { return }
            let (callbacks, fileCallbacks) = state
            try? FileManager.default.removeItem(at: tmpURL)
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }
#endif

        let fileURL = fileURL(for: descriptor)
        let metadataURL = metadataFileURL(for: descriptor)
        ongoingDownloads[key]?.isFinalizing = true
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
        let finalization = await diskMutationLane.finalizeDownload(
            at: tmpURL,
            fileURL: fileURL,
            metadataURL: metadataURL,
            sourceURL: response?.url ?? descriptor.url,
            availabilityRevision: fileAvailabilityRevision
        )
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
        guard let state = removeDownloadState(forKey: key, downloadId: downloadId) else { return }
        let (callbacks, fileCallbacks) = state
        let didRemoveExistingItem = finalization.didRemoveExistingItem
        guard finalization.succeeded else {
            if didRemoveExistingItem {
#if os(iOS) || os(macOS)
                invalidateEstimatedDiskCacheState()
#endif
                notifyFileAvailabilityChanged(
                    .becameUnavailable,
                    scope: .file(fileURL)
                )
            }
#if os(iOS) || os(macOS)
            scheduleDiskPruneCheck(protecting: [descriptor], reason: .afterWrite)
#endif
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

#if os(tvOS) || os(visionOS)
        let isInActiveFileWindow = activeWindow?.collectionId == descriptor.collectionId
            && Set(fileNames(for: descriptor)).isSubset(of: activeWindow?.fileNames ?? [])
        let shouldKeepFinalizedFile = isInActiveFileWindow
            || !callbacks.isEmpty
            || !fileCallbacks.isEmpty
            || hasRetainedFile(forKey: key)
        guard shouldKeepFinalizedFile else {
            scheduleFinalizedFileRemoval(
                collectionId: descriptor.collectionId,
                fileNames: Set(fileNames(for: descriptor)),
                fileURL: fileURL,
                metadataURL: metadataURL
            )
            finishForegroundWork(forKey: key)
            return
        }
#endif

#if os(macOS)
        if !didRemoveExistingItem {
            recordDiskCacheMutation()
        }
#endif
#if os(iOS) || os(macOS)
        if didRemoveExistingItem {
            invalidateEstimatedDiskCacheState()
        }
        downloadedCacheBytes = finalization.cacheBytes
#endif
        notifyFileAvailabilityChanged(
            .becameAvailable,
            scope: .file(fileURL)
        )

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
        startImageDecode(
            at: fileURL,
            descriptor: descriptor,
            key: key,
            origin: .freshDownload,
            replacingExisting: true
        )
        startDownloadsIfNeeded()
    }

    private func removeDownloadState(
        forKey key: String,
        downloadId: UUID
    ) -> (ImageLoadCompletions, FileLoadCompletions)? {
        guard ongoingDownloads[key]?.id == downloadId else { return nil }
        ongoingDownloads.removeValue(forKey: key)
        return (
            completions.removeValue(forKey: key) ?? [:],
            fileCompletions.removeValue(forKey: key) ?? [:]
        )
    }

    private func startImageDecode(
        at fileURL: URL,
        descriptor: CollectionCatalogDownloadableMediaDescriptor,
        key: String,
        origin: ImageDecodeOrigin,
        replacingExisting: Bool = false,
        startsDrain: Bool = true
    ) {
        if let activeDecode = activeDecodesByKey[key] {
            guard replacingExisting,
                  activeDecode.origin != .freshDownload else {
                reorderPendingImageDecodes()
                return
            }
            activeDecode.generation.invalidate()
            activeDecodesByKey.removeValue(forKey: key)
            pendingDecodeKeys.removeAll { $0 == key }
        }
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
        let generation = ImageDecodeGeneration()
        activeDecodesByKey[key] = ActiveDecode(
            descriptor: descriptor,
            fileURL: fileURL,
            generation: generation,
            origin: origin
        )
        pendingDecodeKeys.append(key)
        if startsDrain {
            reorderPendingImageDecodes()
            startNextImageDecodeIfNeeded()
        }
    }

    private func reorderPendingImageDecodes(preferredKeys: [String] = []) {
        guard !pendingDecodeKeys.isEmpty else { return }
        let foregroundDecodeKey = foregroundKey.flatMap { key in
            activeWindow?.decodedKeys.contains(key) == true ? key : nil
        }
        pendingDecodeKeys = Self.orderedPendingImageDecodeKeys(
            pendingKeys: pendingDecodeKeys,
            imageDemandKeys: Set(completions.keys),
            foregroundKey: foregroundDecodeKey,
            preferredKeys: preferredKeys
        )
    }

    nonisolated private static func orderedPendingImageDecodeKeys(
        pendingKeys: [String],
        imageDemandKeys: Set<String>,
        foregroundKey: String?,
        preferredKeys: [String]
    ) -> [String] {
        let pendingKeySet = Set(pendingKeys)
        var reorderedKeys = [String]()
        var usedKeys = Set<String>()

        func append(_ key: String) {
            guard pendingKeySet.contains(key),
                  usedKeys.insert(key).inserted else {
                return
            }
            reorderedKeys.append(key)
        }

        for key in pendingKeys where imageDemandKeys.contains(key) {
            append(key)
        }
        if let foregroundKey {
            append(foregroundKey)
        }
        preferredKeys.forEach(append)
        pendingKeys.forEach(append)
        return reorderedKeys
    }

    private func isImageDecodeRunning(forKey key: String) -> Bool {
        guard let runningDecode,
              runningDecode.key == key,
              let activeDecode = activeDecodesByKey[key],
              activeDecode.generation === runningDecode.generation else {
            return false
        }
        return runningDecode.generation.hasStarted
    }

    private func startNextImageDecodeIfNeeded() {
        guard runningDecode == nil else { return }
        while !pendingDecodeKeys.isEmpty {
            let key = pendingDecodeKeys.removeFirst()
            guard let activeDecode = activeDecodesByKey[key] else { continue }
            let generation = activeDecode.generation
            runningDecode = RunningDecode(key: key, generation: generation)
            Task(priority: .utility) { @MainActor [weak self] in
                guard let self else { return }
                let transfer = await self.imageDecodeLane.decode(
                    at: activeDecode.fileURL,
                    generation: generation
                )
                guard let runningDecode = self.runningDecode,
                      runningDecode.key == key,
                      runningDecode.generation === generation else {
                    return
                }
                self.runningDecode = nil
                if let transfer {
                    self.finishImageDecode(
                        transfer.image,
                        key: key,
                        generation: generation
                    )
                }
                self.startNextImageDecodeIfNeeded()
            }
            return
        }
    }

    private func finishImageDecode(
        _ image: DownloadableMediaImage?,
        key: String,
        generation: ImageDecodeGeneration
    ) {
        guard let activeDecode = activeDecodesByKey[key],
              activeDecode.generation === generation else { return }
        activeDecodesByKey.removeValue(forKey: key)

        let callbacks = completions.removeValue(forKey: key) ?? [:]
        if let image {
            if shouldCacheDecodedImage(
                activeDecode.descriptor,
                key: key,
                hasDemandCallbacks: !callbacks.isEmpty
            ) {
                cache(image, for: activeDecode.descriptor)
            }
            finishForegroundWork(forKey: key, callbacks: callbacks, image: image)
            return
        }

        let shouldRedownloadOnFailure = activeDecode.origin == .cachedFile
            && !callbacks.isEmpty
        if hasRetainedFile(forKey: key) {
            retainedDecodeFailureDescriptors[key] = activeDecode.descriptor
            if shouldRedownloadOnFailure, !callbacks.isEmpty {
                completions[key, default: [:]].merge(callbacks) { current, _ in current }
            } else {
                finishForegroundWork(forKey: key, callbacks: callbacks)
            }
            return
        }

        removeCachedFileAfterDecodeFailure(
            for: activeDecode.descriptor,
            fileURL: activeDecode.fileURL
        )
        guard shouldRedownloadOnFailure, !callbacks.isEmpty else {
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

        completions[key, default: [:]].merge(callbacks) { current, _ in current }
        startForegroundDownload(for: activeDecode.descriptor, key: key)
        startDownloadsIfNeeded()
    }

    nonisolated private static func loadDecodedImage(at fileURL: URL) -> DecodedImageTransfer {
        autoreleasepool {
            guard let image = DownloadableMediaImage(contentsOfFile: fileURL.path) else {
                return DecodedImageTransfer(image: nil)
            }
            return DecodedImageTransfer(image: image.decodedForDisplay())
        }
    }

    nonisolated private static func stageDownloadFile(
        _ tmpURL: URL?,
        response: URLResponse?,
        error: Error?,
        stagingRoot: URL
    ) -> URL? {
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
        requireDecodedStaticImage: Bool,
        hasFile knownFileAvailability: Bool? = nil
    ) {
        let key = cacheKey(for: descriptor)
        foregroundKey = key
        foregroundWorkKeys.formIntersection([key])
        reorderPendingImageDecodes()
        updateOngoingDownloadPriorities()

        let fileURL = fileURL(for: descriptor)
        let hasFile = knownFileAvailability
            ?? FileManager.default.fileExists(atPath: fileURL.path)
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

    private func hasImageDemandCallbacks(forKey key: String) -> Bool {
        completions[key]?.isEmpty == false
    }

    private func hasRetainedFile(forKey key: String) -> Bool {
        (retainedFileKeys[key] ?? 0) > 0
    }

    private func hasDemandCallbacksOrRetainedFile(forKey key: String) -> Bool {
        hasDemandCallbacks(forKey: key) || hasRetainedFile(forKey: key)
    }

    private func fileNamesProtectedFromEviction(
        collectionId: String,
        allowedFileNames: Set<String>
    ) -> Set<String> {
        var protectedFileNames = allowedFileNames
        protectedFileNames.formUnion(retainedFileNameKeys.keys.compactMap { key in
            key.collectionId == collectionId ? key.fileName : nil
        })

        func protect(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
            guard descriptor.collectionId == collectionId else { return }
            protectedFileNames.formUnion(fileNames(for: descriptor))
        }

        ongoingDownloads.values.forEach { protect($0.descriptor) }
        completions.values.forEach { callbacks in
            callbacks.values.forEach { protect($0.descriptor) }
        }
        fileCompletions.values.forEach { callbacks in
            callbacks.values.forEach { protect($0.descriptor) }
        }
        return protectedFileNames
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
#if os(iOS) || os(macOS)
            invalidateEstimatedDiskCacheState()
#endif
            notifyFileAvailabilityChanged(
                .becameUnavailable,
                scope: .file(fileURL)
            )
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
        enqueueDownloadIfNeeded(descriptor, isForegroundRequest: true, hasFile: false)
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

    private func decodeCachedImagesIfNeeded(
        _ descriptors: [CollectionCatalogDownloadableMediaDescriptor],
        availability: WindowFileAvailability? = nil
    ) {
        for descriptor in descriptors {
            let key = cacheKey(for: descriptor)
            guard activeWindow?.decodedKeys.contains(key) == true,
                  cachedDecodedImage(forKey: key) == nil else {
                continue
            }

            let fileURL = fileURL(for: descriptor)
            let hasFile = availability?.hasFile(forKey: key)
                ?? FileManager.default.fileExists(atPath: fileURL.path)
            guard hasFile else {
                continue
            }

            if activeDecodesByKey[key] == nil {
                startImageDecode(
                    at: fileURL,
                    descriptor: descriptor,
                    key: key,
                    origin: .cachedFile,
                    startsDrain: false
                )
            }
        }
        reorderPendingImageDecodes(
            preferredKeys: descriptors.map(cacheKey(for:))
        )
        startNextImageDecodeIfNeeded()
    }

    private func prioritizedDownloadDescriptors(
        for mediaWindow: PlayerDownloadableMediaWindow
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        var orderedDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
        var usedKeys = Set<String>()

        func appendDescriptor(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
            guard usedKeys.insert(cacheKey(for: descriptor)).inserted else { return }
            orderedDescriptors.append(descriptor)
        }

        appendPrioritizedDownloadDescriptors(from: mediaWindow, using: appendDescriptor)
        return orderedDescriptors
    }

    private func prioritizedDownloadDescriptors(
        for windows: [ManagedWindow]
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        var orderedDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
        var usedKeys = Set<String>()

        func appendDescriptor(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
            guard usedKeys.insert(cacheKey(for: descriptor)).inserted else { return }
            orderedDescriptors.append(descriptor)
        }

        for window in windows {
            appendPrioritizedDownloadDescriptors(from: window.mediaWindow, using: appendDescriptor)
        }
        return orderedDescriptors
    }

    private func appendPrioritizedDownloadDescriptors(
        from mediaWindow: PlayerDownloadableMediaWindow,
        using appendDescriptor: (CollectionCatalogDownloadableMediaDescriptor) -> Void
    ) {
        appendDescriptor(mediaWindow.currentDescriptor)
        mediaWindow.preferredDownloadDescriptors.forEach(appendDescriptor)
        mediaWindow.decodedDescriptors.forEach(appendDescriptor)
        mediaWindow.descriptors.forEach(appendDescriptor)
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
        guard !activeCallbacks.isEmpty else {
#if os(tvOS) || os(visionOS)
            rescheduleFileEvictionIfNeeded(for: callbacks.map(\.descriptor))
#endif
            return
        }
        Task { @MainActor [weak self] in
            activeCallbacks.forEach { callback in
                guard !callback.request.isCancelled else { return }
                callback.completion(image)
            }
#if os(tvOS) || os(visionOS)
            self?.rescheduleFileEvictionIfNeeded(for: callbacks.map(\.descriptor))
#endif
        }
    }

    private func completeFile(_ callbacks: FileLoadCompletions, with fileURL: URL?) {
        completeFile(Array(callbacks.values), with: fileURL)
    }

    private func completeFile(_ callbacks: [FileLoadCallback], with fileURL: URL?) {
        let activeCallbacks = callbacks.filter { !$0.request.isCancelled }
        guard !activeCallbacks.isEmpty else {
#if os(tvOS) || os(visionOS)
            rescheduleFileEvictionIfNeeded(for: callbacks.map(\.descriptor))
#endif
            return
        }
        Task { @MainActor [weak self] in
            var didDeliverFile = false
            activeCallbacks.forEach { callback in
                guard !callback.request.isCancelled else { return }
                didDeliverFile = true
                callback.completion(fileURL)
            }
            guard didDeliverFile else {
#if os(tvOS) || os(visionOS)
                self?.rescheduleFileEvictionIfNeeded(for: callbacks.map(\.descriptor))
#endif
                return
            }
#if os(tvOS) || os(visionOS)
            if fileURL == nil {
                self?.rescheduleFileEvictionIfNeeded(for: callbacks.map(\.descriptor))
            }
#endif
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
        guard let download = ongoingDownloads[key] else { return }
        download.task.cancel()
        if download.isFinalizing {
            complete(completions.removeValue(forKey: key) ?? [:], with: nil)
            completeFile(fileCompletions.removeValue(forKey: key) ?? [:], with: nil)
            return
        }
        ongoingDownloads.removeValue(forKey: key)
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

    private func cancelPrefetchDownloadsAndPendingWork(
        preservingForegroundKey: String? = nil
    ) {
        cancelPendingAndOngoingDownloads { key in
            key != preservingForegroundKey
                && !hasDemandCallbacksOrRetainedFile(forKey: key)
        }
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
        cancelScheduledWindowWork()
#if os(tvOS) || os(visionOS)
        cancelScheduledFileEviction()
#endif
        activeWindow = nil
        invalidateUndemandedDecodeWork(
            outside: [],
            startsDrain: true
        )
        exclusiveWindowRegistration = nil
        managedWindowsByOwnerId.removeAll()
        windowPreparationSequence = 0
        foregroundKey = nil
        foregroundWorkKeys.removeAll()
#if !os(iOS)
        clearDecodedImageMemory()
        memoryKeysByCollection.removeAll()
#endif
        cancelPrefetchDownloadsAndPendingWork()
        updateOngoingDownloadPriorities()
        startDownloadsIfNeeded()
    }

#if os(tvOS) || os(visionOS)
    private func rescheduleFileEvictionIfNeeded(
        for descriptors: [CollectionCatalogDownloadableMediaDescriptor]
    ) {
        guard let activeWindow,
              descriptors.contains(where: { descriptor in
                  descriptor.collectionId == activeWindow.collectionId
                      && !Set(fileNames(for: descriptor)).isSubset(of: activeWindow.fileNames)
              }) else {
            return
        }
        cancelScheduledFileEviction()
        scheduleFileEvictionOutsideWindow(
            collectionId: activeWindow.collectionId,
            allowedFileNames: activeWindow.fileNames
        )
    }

    private func scheduleFinalizedFileRemoval(
        collectionId: String,
        fileNames: Set<String>,
        fileURL: URL,
        metadataURL: URL
    ) {
        let removalId = UUID()
        let token = makeFileRemovalToken()
        pendingFinalizedFileRemovals[removalId] = PendingFinalizedFileRemoval(
            collectionId: collectionId,
            fileNames: fileNames,
            token: token
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            let removal = await self.diskMutationLane.removeCachePair(
                mediaURL: fileURL,
                metadataURL: metadataURL,
                token: token
            )
            if removal.primary.removedFromCache {
                self.notifyFileAvailabilityChanged(
                    .becameUnavailable,
                    scope: .file(fileURL)
                )
            }
            self.pendingFinalizedFileRemovals.removeValue(forKey: removalId)
        }
    }

    private func cancelFinalizedFileRemovals(retainedBy window: ActiveWindow) {
        cancelFinalizedFileRemovals(
            collectionId: window.collectionId,
            fileNames: window.fileNames
        )
    }

    private func cancelFinalizedFileRemovals(
        collectionId: String,
        fileNames: Set<String>
    ) {
        for removal in pendingFinalizedFileRemovals.values
        where removal.collectionId == collectionId
            && removal.fileNames.isSubset(of: fileNames) {
            removal.token.cancel()
        }
    }

    private func scheduleFileEvictionOutsideWindow(
        collectionId: String,
        allowedFileNames: Set<String>
    ) {
        let generation = fileEvictionGeneration
        let directory = collectionDirectory(collectionId: collectionId)
        let protectedFileNames = fileNamesProtectedFromEviction(
            collectionId: collectionId,
            allowedFileNames: allowedFileNames
        )
        let token = makeFileRemovalToken()
        fileEvictionToken = token
        fileEvictionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let fileRemovalTombstoneDirectory = self.fileRemovalTombstoneDirectory {
                await self.diskMutationLane.removeFileRemovalTombstones(
                    at: fileRemovalTombstoneDirectory
                )
            } else {
                await self.diskMutationLane.removeFallbackFileRemovalTombstones(
                    at: self.cacheRoot
                )
            }
            let didRemoveItem = await self.diskMutationLane.evictFilesOutsideWindow(
                directory: directory,
                protectedFileNames: protectedFileNames,
                token: token
            )
            if didRemoveItem {
                self.notifyFileAvailabilityChanged(
                    .becameUnavailable,
                    scope: .collection(directory)
                )
            }
            guard self.fileEvictionGeneration == generation else { return }
            self.fileEvictionTask = nil
            self.fileEvictionToken = nil
        }
    }

    private func cancelScheduledFileEviction() {
        fileEvictionToken?.cancel()
        fileEvictionToken = nil
        fileEvictionTask?.cancel()
        fileEvictionTask = nil
        fileEvictionGeneration &+= 1
    }

#endif

    @concurrent
    nonisolated private static func removeLegacyRemovalTrashDirectory(at url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    @concurrent
    nonisolated private static func removeStaleFileRemovalTrash(
        at directoryURL: URL,
        keeping currentDirectoryURL: URL?
    ) async {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let currentDirectoryURL = currentDirectoryURL?.standardizedFileURL
        for url in contents where url.standardizedFileURL != currentDirectoryURL {
            try? FileManager.default.removeItem(at: url)
        }
        if currentDirectoryURL != nil {
            removeFallbackFileRemovalTombstones(
                at: directoryURL.deletingLastPathComponent()
            )
        }
    }

    nonisolated private static func removeFallbackFileRemovalTombstones(
        at rootURL: URL
    ) {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return
        }
        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let contents = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                  ) else {
                continue
            }
            for url in contents where url.lastPathComponent.hasPrefix(
                fileRemovalTombstonePrefix
            ) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

#if !os(iOS)
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
#endif

    private func cache(_ image: DownloadableMediaImage, for descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        let key = cacheKey(for: descriptor)
        memoryCache.setObject(image, forKey: key as NSString, cost: estimatedCost(of: image))
#if !os(iOS)
        memoryKeysByCollection[descriptor.collectionId, default: []].insert(key)
#endif
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

    private static func decodedImageMemoryCostLimit(for decodedDescriptorCapacity: Int) -> Int {
        max(
            defaultDecodedImageMemoryCostLimit,
            max(decodedDescriptorCapacity, 1) * decodedImageMemoryCostLimitPerDescriptor
        )
    }

    private func isDescriptorInActiveWindow(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) -> Bool {
        guard let activeWindow,
              activeWindow.collectionId == descriptor.collectionId else {
            return false
        }
        return activeWindow.allowedKeys.contains(cacheKey(for: descriptor))
    }

    private func shouldKeepDecodedImage(_ descriptor: CollectionCatalogDownloadableMediaDescriptor, key: String) -> Bool {
#if os(iOS)
        guard !suppressesPrefetchDecodeUntilNextWindowWork else { return false }
#endif
        return activeWindow?.collectionId == descriptor.collectionId
            && activeWindow?.decodedKeys.contains(key) == true
    }

    private func shouldCacheDecodedImage(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        key: String,
        hasDemandCallbacks: Bool
    ) -> Bool {
#if os(iOS)
        hasDemandCallbacks || shouldKeepDecodedImage(descriptor, key: key)
#else
        shouldKeepDecodedImage(descriptor, key: key)
#endif
    }

    private func cacheKey(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
        "\(descriptor.collectionId)|\(descriptor.tokenIndex)|\(descriptor.tokenId)|\(sourceURLHash(for: descriptor))|\(descriptor.fileExtension)"
    }

    private func cachedDecodedImage(forKey key: String) -> DownloadableMediaImage? {
        cachedDecodedImageLookup(forKey: key).image
    }

    private func cachedDecodedImageLookup(
        forKey key: String
    ) -> (image: DownloadableMediaImage?, recordsDiskAccess: Bool) {
#if DEBUG && os(iOS)
        if let testingImage = testingDecodedImagesLock.withLock({
            testingDecodedImages[key]
        }) {
            return (testingImage, false)
        }
#endif
        return (memoryCache.object(forKey: key as NSString), true)
    }

    nonisolated private func fileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL {
        collectionDirectory(collectionId: descriptor.collectionId).appendingPathComponent(fileName(for: descriptor))
    }

    nonisolated private func metadataFileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL {
        collectionDirectory(collectionId: descriptor.collectionId).appendingPathComponent(metadataFileName(for: descriptor))
    }

    nonisolated private func fileNames(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> [String] {
        let fileName = fileName(for: descriptor)
        return [fileName, Self.metadataFileName(forFileName: fileName)]
    }

    nonisolated private func fileName(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
        let paddedIndex = String(format: "%06d", descriptor.tokenIndex)
        return "\(paddedIndex)-\(safePathComponent(descriptor.tokenId))-\(sourceURLHash(for: descriptor)).\(descriptor.fileExtension)"
    }

    nonisolated private func metadataFileName(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
        Self.metadataFileName(forFileName: fileName(for: descriptor))
    }

    nonisolated private static func metadataFileName(forFileName fileName: String) -> String {
        "\(fileName)\(Self.downloadedMediaMetadataFileSuffix)"
    }

    nonisolated private func collectionDirectory(collectionId: String) -> URL {
        cacheRoot.appendingPathComponent(safePathComponent(collectionId), isDirectory: true)
    }

    nonisolated private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars)
    }

    nonisolated private func sourceURLHash(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> String {
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
    nonisolated func decodedForDisplay() -> NSImage {
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
    nonisolated func decodedForDisplay() -> UIImage {
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
