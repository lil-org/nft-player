// ∅ 2026 lil org

import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
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

    private typealias FileAvailabilityScope =
        DownloadableMediaAvailabilityPublisher.Scope

    nonisolated enum WindowOwnership: Hashable, Sendable {
        nonisolated enum CooperativeGroup: Hashable, Sendable {
            case macPlayerPager
            case macCollectionBrowser
        }

        case exclusive
        case cooperative(CooperativeGroup)
    }

    static let shared = DownloadableMediaCache()

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

    private let memoryCache: DownloadableMediaMemoryCache
    private let imageDecodeLane: any DownloadableMediaImageDecoding
    private let downloader: any DownloadableMediaDownloading
    nonisolated private let layout: DownloadableMediaCacheLayout
    private let diskStore: DownloadableMediaDiskStore
    private let diskPruner: DownloadableMediaDiskPruner
    private let availabilityPublisher: DownloadableMediaAvailabilityPublisher
    nonisolated private let cacheRoot: URL
    nonisolated private let stagingRoot: URL
    private let maximumConcurrentDownloads = 4
#if DEBUG && os(iOS)
    private struct FileLeaseCountWaiter {
        let id: UUID
        let expectedCount: Int
        let request: DownloadableMediaAsyncRequest<Void>
    }

    private struct ImageDemandCountWaiter {
        let id: UUID
        let expectedCount: Int
        let request: DownloadableMediaAsyncRequest<Void>
    }

    private var beforeCorruptFileRemovalForTesting:
        (@Sendable () async -> Void)?
    private var afterCorruptFileRecoveryForTesting:
        (@Sendable () async -> Void)?
    private var afterRetainedDecodeFailureForTesting:
        (@Sendable () async -> Void)?
    private var beforeDownloadFinalizationCommitForTesting:
        (@Sendable () async -> Void)?
    private var fileLeaseCountWaitersForTesting =
        [String: [FileLeaseCountWaiter]]()
    private var imageDemandCountWaitersForTesting =
        [String: [ImageDemandCountWaiter]]()
#endif

    private struct OngoingDownload {
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let id: UUID
        let operation: Task<Void, Never>
        var priorityRevision: UInt64 = 0
        var isFinalizing = false
        var isCancelling = false
    }

    private typealias WindowFileAvailability =
        DownloadableMediaFileAvailability

    private nonisolated struct WindowWorkPlan: Sendable {
        let foregroundDescriptor: CollectionCatalogDownloadableMediaDescriptor
        let requiresDecodedForegroundImage: Bool
        let decodedDescriptors: [CollectionCatalogDownloadableMediaDescriptor]
        let downloadDescriptors: [CollectionCatalogDownloadableMediaDescriptor]
    }


    private nonisolated enum ImageLoadScheduling: Sendable {
        case foreground
        case preservingPrefetch
    }

    private nonisolated enum ImageDecodeOrigin: Equatable, Sendable {
        case cachedFile
        case freshDownload
    }

    private typealias ImageDecodeGeneration =
        DownloadableMediaImageDecodeGeneration

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

    typealias CancellableFileRemovalToken =
        DownloadableMediaFileRemovalToken

    private nonisolated struct RetainedFileNameKey: Hashable, Sendable {
        let collectionId: String
        let fileName: String
    }

    private struct ImageLoadRequest {
        let request: LoadRequest
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let result: DownloadableMediaAsyncRequest<DownloadableMediaImage?>
    }
    private typealias ImageLoadRequests = [UUID: ImageLoadRequest]

    private struct FileLoadRequest {
        let request: LoadRequest
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let result: DownloadableMediaAsyncRequest<URL?>
    }
    private typealias FileLoadRequests = [UUID: FileLoadRequest]

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
    private nonisolated enum DiskPruneReason: Sendable {
        case routine, afterWrite
    }
#endif
    private var activeWindow: ActiveWindow?
    private var exclusiveWindowRegistration: ExclusiveWindowRegistration?
    private var managedWindowsByOwnerId = [UUID: ManagedWindow]()
    private var windowPreparationSequence: UInt64 = 0
    private var pendingDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
    private var pendingKeys = Set<String>()
    private var ongoingDownloads = [String: OngoingDownload]()
    private var windowWorkTask: Task<Void, Never>?
    private var windowWorkGeneration: UInt64 = 0
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
    private var completions = [String: ImageLoadRequests]()
    private var fileCompletions = [String: FileLoadRequests]()
    private var retainedFileKeys = [String: Int]()
    private var retainedFileNameKeys = [RetainedFileNameKey: Int]()
    private var retainedDecodeFailureDescriptors = [String: CollectionCatalogDownloadableMediaDescriptor]()
    private var pendingCorruptFileRemovals = [String: CancellableFileRemovalToken]()
    private var memoryWarningObserver: NSObjectProtocol?
    private var knownAvailableFileURLs = [String: URL]()
    private var diskProtectionRevision: UInt64 = 0

    private convenience init() {
        self.init(
            layout: .live,
            downloader: DownloadableMediaDownloader(
                maximumConcurrentDownloads: 4
            ),
            imageDecoder: DownloadableMediaImageDecoder()
        )
    }

    init(
        layout: DownloadableMediaCacheLayout,
        downloader: any DownloadableMediaDownloading,
        imageDecoder: any DownloadableMediaImageDecoding,
        notificationCenter: NotificationCenter = .default,
        observesMemoryWarnings: Bool = true
    ) {
        let diskStore = DownloadableMediaDiskStore(layout: layout)
        memoryCache = DownloadableMediaMemoryCache()
        imageDecodeLane = imageDecoder
        self.downloader = downloader
        self.layout = layout
        self.diskStore = diskStore
        self.diskPruner = DownloadableMediaDiskPruner(
            layout: layout,
            store: diskStore
        )
        availabilityPublisher = DownloadableMediaAvailabilityPublisher(
            layout: layout,
            notificationCenter: notificationCenter
        )
        cacheRoot = layout.cacheRoot
        stagingRoot = layout.stagingRoot
        configureDecodedImageMemoryCacheLimit(
            decodedDescriptorCount: PlayerDownloadableMediaWindowLayout.decodedWindowCapacity
        )
        Task {
            _ = await diskStore.prepare()
        }

#if os(iOS)
        if observesMemoryWarnings {
            memoryWarningObserver = notificationCenter.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMemoryWarning()
                }
            }
        }
#endif
    }

#if DEBUG && os(iOS)
    convenience init(
        layout: DownloadableMediaCacheLayout,
        downloader: any DownloadableMediaDownloading,
        imageDecoder: any DownloadableMediaImageDecoding,
        notificationCenter: NotificationCenter = .default,
        beforeCorruptFileRemovalForTesting:
            (@Sendable () async -> Void)? = nil,
        afterCorruptFileRecoveryForTesting:
            (@Sendable () async -> Void)? = nil,
        afterRetainedDecodeFailureForTesting:
            (@Sendable () async -> Void)? = nil,
        beforeDownloadFinalizationCommitForTesting:
            (@Sendable () async -> Void)? = nil
    ) {
        self.init(
            layout: layout,
            downloader: downloader,
            imageDecoder: imageDecoder,
            notificationCenter: notificationCenter,
            observesMemoryWarnings: false
        )
        self.beforeCorruptFileRemovalForTesting =
            beforeCorruptFileRemovalForTesting
        self.afterCorruptFileRecoveryForTesting =
            afterCorruptFileRecoveryForTesting
        self.afterRetainedDecodeFailureForTesting =
            afterRetainedDecodeFailureForTesting
        self.beforeDownloadFinalizationCommitForTesting =
            beforeDownloadFinalizationCommitForTesting
    }
#endif

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
        refreshDiskProtection()

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
        var locationsByKey = [String: DownloadableMediaDiskLocation]()
        for descriptor in [plan.foregroundDescriptor] + plan.decodedDescriptors + plan.downloadDescriptors {
            let key = cacheKey(for: descriptor)
            locationsByKey[key] = layout.location(for: descriptor)
        }

        windowWorkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.diskStore.availabilitySnapshot(
                for: Array(locationsByKey.values)
            )
            let unavailableKeys = snapshot.availability.checkedKeys
                .subtracting(snapshot.availability.availableKeys)
            let unavailableMediaURLs = Set(unavailableKeys.compactMap {
                locationsByKey[$0]?.mediaURL
            })
            guard !Task.isCancelled,
                  self.windowWorkGeneration == generation else {
                await self.discardWindowAvailabilitySnapshot(
                    snapshot,
                    unavailableMediaURLs: unavailableMediaURLs
                )
                return
            }
            let didApply = self.diskStore.fileStateRevision.withCurrent(
                snapshot.mutationGeneration
            ) {
                self.windowWorkTask = nil
                self.applyWindowWork(
                    plan,
                    availability: snapshot.availability
                )
                self.diskStore.acknowledgeUnavailablePaths(
                    snapshot.unavailablePathClaims
                )
            }
            guard didApply else {
                await self.discardWindowAvailabilitySnapshot(
                    snapshot,
                    unavailableMediaURLs: unavailableMediaURLs
                )
                guard !Task.isCancelled,
                      self.windowWorkGeneration == generation else {
                    return
                }
                self.scheduleWindowWork(plan)
                return
            }
        }
    }

    private func discardWindowAvailabilitySnapshot(
        _ snapshot: DownloadableMediaDiskAvailabilitySnapshot,
        unavailableMediaURLs: Set<URL>
    ) async {
        let knownMediaURLs = Set(
            knownAvailableFileURLs.values.map(\.standardizedFileURL)
        )
        let knownUnavailableMediaURLs = unavailableMediaURLs.intersection(
            knownMediaURLs
        )
        let didApply = diskStore.fileStateRevision.withCurrent(
            snapshot.mutationGeneration
        ) {
            invalidateKnownAvailability(
                for: knownUnavailableMediaURLs
            )
            diskStore.acknowledgeUnavailablePaths(
                snapshot.unavailablePathClaims
            )
        }
        guard !didApply else { return }

        let knownUnavailablePaths = Set(
            knownUnavailableMediaURLs.map { layout.diskPath(for: $0) }
        )
        diskStore.acknowledgeUnavailablePaths(
            Set(snapshot.unavailablePathClaims.filter {
                !knownUnavailablePaths.contains($0.path)
            })
        )
        await applyRemovedMediaURLs(knownUnavailableMediaURLs)
    }

    private func cancelScheduledWindowWork() {
        windowWorkTask?.cancel()
        windowWorkTask = nil
        windowWorkGeneration &+= 1
    }

    private func applyWindowWork(_ plan: WindowWorkPlan, availability: WindowFileAvailability) {
        var discoveredAvailableFile = false
        for descriptor in [plan.foregroundDescriptor]
            + plan.decodedDescriptors
            + plan.downloadDescriptors {
            let key = cacheKey(for: descriptor)
            if availability.hasFile(forKey: key) == true {
                discoveredAvailableFile = discoveredAvailableFile
                    || knownAvailableFileURLs[key] == nil
                knownAvailableFileURLs[key] = fileURL(for: descriptor)
            } else if availability.hasFile(forKey: key) == false {
                knownAvailableFileURLs.removeValue(forKey: key)
            }
        }
        if discoveredAvailableFile {
            notifyFileAvailabilityChanged(.becameAvailable)
        }
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

    func cancelAllDownloads() {
        cancelScheduledWindowWork()
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
#if os(tvOS) || os(visionOS)
        cancelScheduledFileEviction()
#endif
        cancelUnretainedDownloadsAndPendingWork()
        pendingCorruptFileRemovals.values.forEach { $0.cancel() }

        invalidateAllImageDecodes()
        foregroundKey = nil
        foregroundWorkKeys.removeAll()
        clearDecodedImageMemory()
        activeWindow = nil
        refreshDiskProtection()
        exclusiveWindowRegistration = nil
        managedWindowsByOwnerId.removeAll()
        windowPreparationSequence = 0
        updateOngoingDownloadPriorities()
        startDownloadsIfNeeded()
    }

    func knownLocalFileURL(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> URL? {
        let key = cacheKey(for: descriptor)
        guard ongoingDownloads[key]?.isFinalizing != true,
              pendingCorruptFileRemovals[key] == nil else {
            return nil
        }
        guard let url = knownAvailableFileURLs[key] else { return nil }
        guard !diskStore.isMediaURLUnavailable(url) else { return nil }
        markCachedFileUsed(for: descriptor)
        return url
    }

    func existingFileURL(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) async -> URL? {
        let key = cacheKey(for: descriptor)
        guard ongoingDownloads[key]?.isFinalizing != true,
              pendingCorruptFileRemovals[key] == nil else {
            return nil
        }
        let location = layout.location(for: descriptor)
        let availability = await currentFileAvailability(for: location)
        guard ongoingDownloads[key]?.isFinalizing != true,
              pendingCorruptFileRemovals[key] == nil,
              availability.hasFile(forKey: key) == true,
              !diskStore.isMediaURLUnavailable(location.mediaURL) else {
            return nil
        }
        markCachedFileUsed(for: descriptor)
        return location.mediaURL
    }

    func image(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        priority: DownloadableMediaRequestPriority = .foreground
    ) async -> DownloadableMediaImage? {
        if let image = cachedDecodedImage(for: descriptor) {
            return image
        }

        let request = DownloadableMediaAsyncRequest<DownloadableMediaImage?>()
        return await withTaskCancellationHandler {
            let scheduling: ImageLoadScheduling = priority == .foreground
                ? .foreground
                : .preservingPrefetch
            let cancellation = beginImageRequest(
                for: descriptor,
                scheduling: scheduling,
                result: request
            )
            request.installCancellation(cancellation ?? {})
            return await request.wait()
        } onCancel: {
            request.cancel(returning: nil)
        }
    }

    func image(
        for token: GeneratedToken,
        priority: DownloadableMediaRequestPriority = .foreground
    ) async -> DownloadableMediaImage? {
        guard let tokenIndex = CollectionCatalog.tokenIndex(
            specificCollectionId: token.fullCollectionId,
            tokenId: token.id
        ),
        let descriptor = CollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: token.fullCollectionId,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }
        return await image(for: descriptor, priority: priority)
    }

    func file(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) async -> URL? {
        let request = DownloadableMediaAsyncRequest<URL?>()
        return await withTaskCancellationHandler {
            let cancellation = beginFileRequest(
                for: descriptor,
                result: request
            )
            request.installCancellation(cancellation ?? {})
            return await request.wait()
        } onCancel: {
            request.cancel(returning: nil)
        }
    }

    func downloadedSourceURL(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) async -> URL {
        await diskStore.sourceURL(
            at: layout.location(for: descriptor)
        ) ?? descriptor.url
    }

    func fileLease(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> DownloadableMediaFileLease {
        let release = makeFileRelease(for: descriptor)
        return DownloadableMediaFileLease(release: release)
    }

    private func beginImageRequest(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        scheduling: ImageLoadScheduling,
        result: DownloadableMediaAsyncRequest<DownloadableMediaImage?>
    ) -> (@MainActor @Sendable () -> Void)? {
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
#if os(tvOS) || os(visionOS)
        cancelFinalizedFileRemovals(
            collectionId: descriptor.collectionId,
            fileNames: Set(fileNames(for: descriptor))
        )
#endif
        guard descriptor.isStaticImage else {
            result.finish(nil)
            return nil
        }

        let request = LoadRequest()
        let key = cacheKey(for: descriptor)
        let callback = ImageLoadRequest(
            request: request,
            descriptor: descriptor,
            result: result
        )
        completions[key, default: [:]][request.id] = callback
        refreshDiskProtection()
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
                for: self.layout.location(for: descriptor)
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

    private func beginFileRequest(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        result: DownloadableMediaAsyncRequest<URL?>
    ) -> (@MainActor @Sendable () -> Void)? {
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
#if os(tvOS) || os(visionOS)
        cancelFinalizedFileRemovals(
            collectionId: descriptor.collectionId,
            fileNames: Set(fileNames(for: descriptor))
        )
#endif
        let request = LoadRequest()
        let key = cacheKey(for: descriptor)
        let callback = FileLoadRequest(
            request: request,
            descriptor: descriptor,
            result: result
        )
        fileCompletions[key, default: [:]][request.id] = callback
        refreshDiskProtection()
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
                for: self.layout.location(for: descriptor)
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
        for location: DownloadableMediaDiskLocation
    ) async -> WindowFileAvailability {
        while true {
            let snapshot = await diskStore.availabilitySnapshot(
                for: [location]
            )
            let didApply = diskStore.fileStateRevision.withCurrent(
                snapshot.mutationGeneration
            ) {
                if snapshot.availability.hasFile(forKey: location.key)
                    == true {
                    knownAvailableFileURLs[location.key] = location.mediaURL
                } else if snapshot.availability.hasFile(forKey: location.key)
                    == false {
                    knownAvailableFileURLs.removeValue(forKey: location.key)
                }
                diskStore.acknowledgeUnavailablePaths(
                    snapshot.unavailablePathClaims
                )
            }
            if didApply {
                return snapshot.availability
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
        let removed = removeCallback(
            forKey: key,
            requestId: requestId,
            from: &completions
        )
        if removed {
            refreshDiskProtection()
        }
        return removed
    }

    private func detachImageCallbacks(forKey key: String) -> ImageLoadRequests {
        guard let callbacks = completions.removeValue(forKey: key) else {
            return [:]
        }
        refreshDiskProtection()
        return callbacks
    }

    private func activeImageCallbacks(forKey key: String) -> ImageLoadRequests {
        (completions[key] ?? [:]).filter {
            !$0.value.request.isCancelled
        }
    }

    private func detachFileCallbacks(forKey key: String) -> FileLoadRequests {
        guard let callbacks = fileCompletions.removeValue(forKey: key) else {
            return [:]
        }
        refreshDiskProtection()
        return callbacks
    }

    private func removeFileCompletion(forKey key: String, requestId: UUID) -> Bool {
        let removed = removeCallback(
            forKey: key,
            requestId: requestId,
            from: &fileCompletions
        )
        if removed {
            refreshDiskProtection()
        }
        return removed
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

    private func makeFileRelease(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> @Sendable () -> Void {
        let key = cacheKey(for: descriptor)
        pendingCorruptFileRemovals[key]?.cancel()
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
        refreshDiskProtection()
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
                    await self.handleRetainedDecodeFailureIfNeeded(forKey: key)
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
        memoryCache.installInjectedImage(image, forKey: key)
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
        memoryCache.removeInjectedImage(forKey: key)
    }

    func resetDecodedImagesForTesting() {
        clearDecodedImageMemory()
    }

    func waitForDecodedImageRetirementForTesting() async -> Bool? {
        await memoryCache.waitForRetirementForTesting()
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

    func hasScheduledFileWorkForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> Bool {
        let key = cacheKey(for: descriptor)
        return pendingKeys.contains(key) || ongoingDownloads[key] != nil
    }

    func imageDemandCountForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> Int {
        let key = cacheKey(for: descriptor)
        return completions[key]?.count ?? 0
    }

    func waitForImageDemandCountForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        expectedCount: Int
    ) async {
        let key = cacheKey(for: descriptor)
        guard imageDemandCountForTesting(for: descriptor) != expectedCount else {
            return
        }
        let waiterID = UUID()
        let request = DownloadableMediaAsyncRequest<Void>()
        await withTaskCancellationHandler {
            if imageDemandCountForTesting(for: descriptor) == expectedCount {
                return
            }
            imageDemandCountWaitersForTesting[key, default: []].append(
                ImageDemandCountWaiter(
                    id: waiterID,
                    expectedCount: expectedCount,
                    request: request
                )
            )
            defer {
                removeImageDemandCountWaiterForTesting(
                    id: waiterID,
                    forKey: key
                )
            }
            await request.wait()
        } onCancel: {
            request.cancel(returning: ())
        }
    }

    func fileDemandCountForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> Int {
        let key = cacheKey(for: descriptor)
        return fileCompletions[key]?.values.filter {
            !$0.request.isCancelled
        }.count ?? 0
    }

    func applyRemovedMediaURLsForTesting(
        _ removedMediaURLs: Set<URL>
    ) async {
        await applyRemovedMediaURLs(removedMediaURLs)
    }

    func removeCachedFileForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) async {
        _ = await diskStore.removePair(
            at: layout.location(for: descriptor)
        )
    }

    func waitForFileLeaseCountForTesting(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        expectedCount: Int
    ) async {
        let key = cacheKey(for: descriptor)
        guard (retainedFileKeys[key] ?? 0) > expectedCount else { return }
        let waiterID = UUID()
        let request = DownloadableMediaAsyncRequest<Void>()
        await withTaskCancellationHandler {
            guard (retainedFileKeys[key] ?? 0) > expectedCount else { return }
            fileLeaseCountWaitersForTesting[key, default: []].append(
                FileLeaseCountWaiter(
                    id: waiterID,
                    expectedCount: expectedCount,
                    request: request
                )
            )
            defer {
                removeFileLeaseCountWaiterForTesting(
                    id: waiterID,
                    forKey: key
                )
            }
            await request.wait()
        } onCancel: {
            request.cancel(returning: ())
        }
    }

    private func resumeImageDemandCountWaitersForTesting() {
        for key in Array(imageDemandCountWaitersForTesting.keys) {
            let count = completions[key]?.count ?? 0
            let waiters = imageDemandCountWaitersForTesting.removeValue(
                forKey: key
            ) ?? []
            var pendingWaiters = [ImageDemandCountWaiter]()
            for waiter in waiters {
                if count == waiter.expectedCount {
                    waiter.request.finish(())
                } else {
                    pendingWaiters.append(waiter)
                }
            }
            if !pendingWaiters.isEmpty {
                imageDemandCountWaitersForTesting[key] = pendingWaiters
            }
        }
    }

    private func removeImageDemandCountWaiterForTesting(
        id: UUID,
        forKey key: String
    ) {
        guard var waiters = imageDemandCountWaitersForTesting[key] else {
            return
        }
        waiters.removeAll { $0.id == id }
        if waiters.isEmpty {
            _ = imageDemandCountWaitersForTesting.removeValue(forKey: key)
        } else {
            imageDemandCountWaitersForTesting[key] = waiters
        }
    }

    private func removeFileLeaseCountWaiterForTesting(
        id: UUID,
        forKey key: String
    ) {
        guard var waiters = fileLeaseCountWaitersForTesting[key] else {
            return
        }
        waiters.removeAll { $0.id == id }
        if waiters.isEmpty {
            _ = fileLeaseCountWaitersForTesting.removeValue(forKey: key)
        } else {
            fileLeaseCountWaitersForTesting[key] = waiters
        }
    }
#endif

    private func clearDecodedImageMemory() {
        memoryCache.clear()
    }

    var webViewHTMLDirectoryURL: URL {
        layout.webViewHTMLDirectoryURL
    }

    var webViewReadAccessURL: URL {
        layout.webViewReadAccessURL
    }

    private func notifyFileAvailabilityChanged(
        _ change: DownloadableMediaCacheFileAvailabilityChange,
        scope: FileAvailabilityScope = .all
    ) {
        if change == .becameUnavailable {
            switch scope {
            case let .file(fileURL):
                knownAvailableFileURLs = knownAvailableFileURLs.filter {
                    $0.value.standardizedFileURL
                        != fileURL.standardizedFileURL
                }
            case let .collection(directoryURL):
                knownAvailableFileURLs = knownAvailableFileURLs.filter {
                    $0.value.deletingLastPathComponent().standardizedFileURL
                        != directoryURL.standardizedFileURL
                }
            case .all:
                knownAvailableFileURLs.removeAll(keepingCapacity: true)
            }
        }
        availabilityPublisher.post(change, scope: scope)
    }

    private func makeFileRemovalToken() -> CancellableFileRemovalToken {
        CancellableFileRemovalToken()
    }

    func fileAvailabilityChange(
        _ notification: Notification,
        affects descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> Bool {
        availabilityPublisher.change(
            notification,
            affects: descriptor
        )
    }

    func fileAvailabilityChange(
        _ notification: Notification,
        affectsCollection collectionId: String
    ) -> Bool {
        availabilityPublisher.change(
            notification,
            affectsCollection: collectionId
        )
    }

    private func configureDecodedImageMemoryCacheLimit(decodedDescriptorCount: Int) {
        memoryCache.configureLimits(
            decodedDescriptorCount: decodedDescriptorCount
        )
    }

#if os(iOS)
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
        if !keys.isEmpty {
            refreshDiskProtection()
        }
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
        refreshDiskProtection()
    }

#if os(iOS) || os(macOS)
    private func scheduleDiskPruneCheck(
        protecting extraProtectedDescriptors: [CollectionCatalogDownloadableMediaDescriptor] = [],
        reason: DiskPruneReason = .routine
    ) {
        let extraProtectedPaths = Set(
            extraProtectedDescriptors.flatMap(layout.diskPaths(for:))
        )
        let pruneReason: DownloadableMediaDiskPruneReason =
            reason == .afterWrite ? .afterWrite : .routine
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.diskPruner.prune(
                protecting: extraProtectedPaths,
                reason: pruneReason
            )
            await self.applyDiskPruneResult(result)
        }
    }

    private func schedulePostWriteDiskPruneCheck(
        protecting descriptor: CollectionCatalogDownloadableMediaDescriptor,
        addedBytes: Int64
    ) {
        let additionalProtectedPaths = Set(layout.diskPaths(for: descriptor))
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.diskPruner.recordWrite(
                cacheBytes: addedBytes,
                protecting: additionalProtectedPaths
            )
            await self.applyDiskPruneResult(result)
        }
    }

    private func cancelDiskPruneRemovalIfNeeded() {
        diskStore.cancelPrune()
    }

    private func applyDiskPruneResult(
        _ result: DownloadableMediaDiskPruneResult
    ) async {
        await applyRemovedMediaURLs(result.removedMediaURLs)
    }

    private func refreshDiskProtection() {
        diskProtectionRevision &+= 1
        let revision = diskProtectionRevision
        let protectedPaths = protectedDiskCachePaths()
        diskStore.setProtectedPaths(
            protectedPaths,
            revision: revision
        )
#if DEBUG && os(iOS)
        resumeImageDemandCountWaitersForTesting()
#endif
    }


    private func protectedDiskCachePaths(
        extraProtectedPaths: Set<String> = []
    ) -> Set<String> {
        var protectedPaths = extraProtectedPaths
        if let activeWindow {
            let directory = collectionDirectory(
                collectionId: activeWindow.collectionId
            )
            for fileName in activeWindow.fileNames {
                protectedPaths.insert(
                    layout.diskPath(
                        for: directory.appendingPathComponent(fileName)
                    )
                )
            }
        }
        for fileNameKey in retainedFileNameKeys.keys {
            let directory = collectionDirectory(
                collectionId: fileNameKey.collectionId
            )
            protectedPaths.insert(
                layout.diskPath(
                    for: directory.appendingPathComponent(fileNameKey.fileName)
                )
            )
        }
        for descriptor in pendingDescriptors {
            protectedPaths.formUnion(layout.diskPaths(for: descriptor))
        }
        for download in ongoingDownloads.values {
            protectedPaths.formUnion(
                layout.diskPaths(for: download.descriptor)
            )
        }
        for activeDecode in activeDecodesByKey.values {
            protectedPaths.formUnion(
                layout.diskPaths(for: activeDecode.descriptor)
            )
        }
        for descriptor in retainedDecodeFailureDescriptors.values {
            protectedPaths.formUnion(layout.diskPaths(for: descriptor))
        }
        for callbacks in completions.values {
            for callback in callbacks.values {
                protectedPaths.formUnion(
                    layout.diskPaths(for: callback.descriptor)
                )
            }
        }
        for callbacks in fileCompletions.values {
            for callback in callbacks.values {
                protectedPaths.formUnion(
                    layout.diskPaths(for: callback.descriptor)
                )
            }
        }
        return protectedPaths
    }

    private func markCachedFileUsed(for descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        let location = layout.location(for: descriptor)
        Task {
            await diskStore.touch(location)
        }
    }

    nonisolated private func diskCachePaths(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> [String] {
        layout.diskPaths(for: descriptor)
    }

    nonisolated private func diskCachePath(for url: URL) -> String {
        layout.diskPath(for: url)
    }
#else
    private func markCachedFileUsed(for _: CollectionCatalogDownloadableMediaDescriptor) {}
    private func refreshDiskProtection() {}
#endif

    private func applyRemovedMediaURLs(
        _ removedMediaURLs: Set<URL>
    ) async {
        let mediaURLs = Set(removedMediaURLs.map(\.standardizedFileURL))
        guard !mediaURLs.isEmpty else { return }
        while true {
            let snapshot = await diskStore.availabilitySnapshot(
                forMediaURLs: mediaURLs
            )
            let unavailableMediaURLs = snapshot.checkedURLs.subtracting(
                snapshot.availableURLs
            )
            let didApply = diskStore.fileStateRevision.withCurrent(
                snapshot.mutationGeneration
            ) {
                invalidateKnownAvailability(for: unavailableMediaURLs)
                diskStore.acknowledgeUnavailablePaths(
                    snapshot.unavailablePathClaims
                )
            }
            if didApply {
                return
            }
        }
    }

    private func invalidateKnownAvailability(for mediaURLs: Set<URL>) {
        for mediaURL in mediaURLs {
            notifyFileAvailabilityChanged(
                .becameUnavailable,
                scope: .file(mediaURL)
            )
        }
    }

    private func enqueueDownloadIfNeeded(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        isForegroundRequest: Bool,
        hasFile knownFileAvailability: Bool? = nil
    ) {
        let key = cacheKey(for: descriptor)
        if ongoingDownloads[key] != nil {
            if isForegroundRequest {
                updateOngoingDownloadPriority(forKey: key)
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
            ?? (knownAvailableFileURLs[key] != nil)
        guard !hasFile else { return }

        pendingKeys.insert(key)
        if isForegroundRequest {
            pendingDescriptors.insert(descriptor, at: 0)
        } else {
            pendingDescriptors.append(descriptor)
        }
        refreshDiskProtection()
    }

    private func startDownloadsIfNeeded(fileAvailability: WindowFileAvailability? = nil) {
        while ongoingDownloads.count < maximumConcurrentDownloads {
            guard let descriptor = popNextStartablePendingDescriptor(
                fileAvailability: fileAvailability
            ) else { return }
            let key = cacheKey(for: descriptor)

            let downloadId = UUID()
            let request = DownloadableMediaDownloadRequest(
                id: downloadId,
                sourceURL: descriptor.url,
                priority: downloadTaskPriority(forKey: key),
                stagingRoot: stagingRoot
            )
            let operation = Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.downloader.download(request)
                await self.finishDownload(
                    descriptor: descriptor,
                    downloadId: downloadId,
                    result: result
                )
            }
            ongoingDownloads[key] = OngoingDownload(
                descriptor: descriptor,
                id: downloadId,
                operation: operation
            )
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
                refreshDiskProtection()
                continue
            }

            if !foregroundWorkKeys.isEmpty && !isForegroundKey(key) && !hasActiveFileInterest {
                index += 1
                continue
            }

            let hasFile = fileAvailability?.hasFile(forKey: key)
                ?? (knownAvailableFileURLs[key] != nil)
            if hasFile {
                pendingDescriptors.remove(at: index)
                pendingKeys.remove(key)
                refreshDiskProtection()
                continue
            }

            pendingDescriptors.remove(at: index)
            pendingKeys.remove(key)
            refreshDiskProtection()
            return descriptor
        }
        return nil
    }

    private func finishDownload(
        descriptor: CollectionCatalogDownloadableMediaDescriptor,
        downloadId: UUID,
        result: DownloadableMediaDownloadResult
    ) async {
#if os(iOS) || os(macOS)
        var downloadedCacheBytes: Int64?
        var requiresPostWriteDiskScan = false
        defer {
            if requiresPostWriteDiskScan {
                scheduleDiskPruneCheck(
                    protecting: [descriptor],
                    reason: .afterWrite
                )
            } else if let downloadedCacheBytes {
                schedulePostWriteDiskPruneCheck(
                    protecting: descriptor,
                    addedBytes: downloadedCacheBytes
                )
            }
        }
#endif
        let key = cacheKey(for: descriptor)
        guard ongoingDownloads[key]?.id == downloadId else {
            if let stagedURL = result.stagedURL {
                await diskStore.discardStagedFile(at: stagedURL)
            }
            return
        }
        if ongoingDownloads[key]?.isCancelling == true {
            if let stagedURL = result.stagedURL {
                await diskStore.discardStagedFile(at: stagedURL)
            }
            return
        }

        guard result.failure == nil else {
            guard let state = removeDownloadState(forKey: key, downloadId: downloadId) else { return }
            let (callbacks, fileCallbacks) = state
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }
        guard let tmpURL = result.stagedURL else {
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
            await diskStore.discardStagedFile(at: tmpURL)
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }
#endif

        let fileURL = fileURL(for: descriptor)
        let location = layout.location(for: descriptor)
        ongoingDownloads[key]?.isFinalizing = true
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
        let finalization = await diskStore.finalizeDownload(
            at: tmpURL,
            location: location,
            sourceURL: result.sourceURL ?? descriptor.url
        )
        let finalizationIsCurrent = diskStore
            .isMutationGenerationCurrent(finalization.mutationGeneration)
        let finalizedFileIsAvailable: Bool
        if finalizationIsCurrent {
            finalizedFileIsAvailable = finalization.succeeded
        } else {
            finalizedFileIsAvailable = await currentFileAvailability(
                for: location
            ).hasFile(forKey: key) == true
        }
#if os(iOS) || os(macOS)
        cancelDiskPruneRemovalIfNeeded()
#endif
        let didRemoveExistingItem = finalization.didRemoveExistingItem
        guard finalizedFileIsAvailable else {
            if didRemoveExistingItem {
                await applyRemovedMediaURLs([fileURL])
            } else {
                _ = await currentFileAvailability(for: location)
            }
#if os(iOS) || os(macOS)
            scheduleDiskPruneCheck(protecting: [descriptor], reason: .afterWrite)
#endif
            guard let state = removeDownloadState(
                forKey: key,
                downloadId: downloadId
            ) else { return }
            let (callbacks, fileCallbacks) = state
            completeFile(fileCallbacks, with: nil)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

#if DEBUG && os(iOS)
        await runBeforeDownloadFinalizationCommitForTestingIfNeeded()
#endif

#if os(iOS) || os(macOS)
        if didRemoveExistingItem || !finalizationIsCurrent {
            requiresPostWriteDiskScan = true
        } else {
            downloadedCacheBytes = finalization.cacheBytes
        }
#endif
        let didApplyFinalization = diskStore.fileStateRevision.withCurrent(
            finalization.mutationGeneration
        ) {
            knownAvailableFileURLs[key] = fileURL
        }
        if !didApplyFinalization {
            let availability = await currentFileAvailability(for: location)
            guard availability.hasFile(forKey: key) == true else {
                guard let state = removeDownloadState(
                    forKey: key,
                    downloadId: downloadId
                ) else { return }
                let (callbacks, fileCallbacks) = state
                completeFile(fileCallbacks, with: nil)
                finishForegroundWork(forKey: key, callbacks: callbacks)
                return
            }
        }

#if os(tvOS) || os(visionOS)
        let isInActiveFileWindow = activeWindow?.collectionId == descriptor.collectionId
            && Set(fileNames(for: descriptor)).isSubset(of: activeWindow?.fileNames ?? [])
        let shouldKeepFinalizedFile = isInActiveFileWindow
            || completions[key]?.isEmpty == false
            || fileCompletions[key]?.isEmpty == false
            || hasRetainedFile(forKey: key)
        guard shouldKeepFinalizedFile else {
            knownAvailableFileURLs.removeValue(forKey: key)
            guard removeDownloadState(
                forKey: key,
                downloadId: downloadId
            ) != nil else { return }
            scheduleFinalizedFileRemoval(
                for: descriptor
            )
            finishForegroundWork(forKey: key)
            return
        }
#endif

        guard removeOngoingDownloadState(
            forKey: key,
            downloadId: downloadId
        ) else { return }
        let fileCallbacks = detachFileCallbacks(forKey: key)
        notifyFileAvailabilityChanged(
            .becameAvailable,
            scope: .file(fileURL)
        )
        completeFile(fileCallbacks, with: fileURL)

        guard descriptor.isStaticImage else {
            let callbacks = detachImageCallbacks(forKey: key)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }

        let shouldDecodeForPrefetch = shouldKeepDecodedImage(descriptor, key: key)
        guard completions[key]?.isEmpty == false || shouldDecodeForPrefetch else {
            finishForegroundWork(forKey: key)
            return
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
    ) -> (ImageLoadRequests, FileLoadRequests)? {
        guard removeOngoingDownloadState(
            forKey: key,
            downloadId: downloadId
        ) else { return nil }
        return (
            detachImageCallbacks(forKey: key),
            detachFileCallbacks(forKey: key)
        )
    }

    private func removeOngoingDownloadState(
        forKey key: String,
        downloadId: UUID
    ) -> Bool {
        guard ongoingDownloads[key]?.id == downloadId else { return false }
        ongoingDownloads.removeValue(forKey: key)
        refreshDiskProtection()
        return true
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
        refreshDiskProtection()
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
                    await self.finishImageDecode(
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
    ) async {
        guard let activeDecode = activeDecodesByKey[key],
              activeDecode.generation === generation else { return }
        activeDecodesByKey.removeValue(forKey: key)
        refreshDiskProtection()
        if let image {
            let callbacks = detachImageCallbacks(forKey: key)
            let hasDemandCallbacks = callbacks.values.contains {
                !$0.request.isCancelled
            }
            if shouldCacheDecodedImage(
                activeDecode.descriptor,
                key: key,
                hasDemandCallbacks: hasDemandCallbacks
            ) {
                cache(image, for: activeDecode.descriptor)
            }
            finishForegroundWork(forKey: key, callbacks: callbacks, image: image)
            return
        }

        let shouldRedownloadOnFailure = activeDecode.origin == .cachedFile
        if hasRetainedFile(forKey: key) {
            deferDecodeFailureForRetainedFile(
                activeDecode.descriptor,
                key: key,
                redownloadsWhenReleased: shouldRedownloadOnFailure
            )
#if DEBUG && os(iOS)
            await runAfterRetainedDecodeFailureForTestingIfNeeded()
#endif
            return
        }

        await removeCachedFileAfterDecodeFailure(
            for: activeDecode.descriptor,
            fileURL: activeDecode.fileURL
        )
        if hasRetainedFile(forKey: key) {
            deferDecodeFailureForRetainedFile(
                activeDecode.descriptor,
                key: key,
                redownloadsWhenReleased: shouldRedownloadOnFailure
            )
#if DEBUG && os(iOS)
            await runAfterCorruptFileRecoveryForTestingIfNeeded()
            await runAfterRetainedDecodeFailureForTestingIfNeeded()
#endif
            return
        }

        let currentCallbacks = activeImageCallbacks(forKey: key)
        guard shouldRedownloadOnFailure, !currentCallbacks.isEmpty else {
            let callbacks = detachImageCallbacks(forKey: key)
            finishForegroundWork(forKey: key, callbacks: callbacks)
#if DEBUG && os(iOS)
            await runAfterCorruptFileRecoveryForTestingIfNeeded()
#endif
            return
        }

        startForegroundDownload(for: activeDecode.descriptor, key: key)
        startDownloadsIfNeeded()
#if DEBUG && os(iOS)
        await runAfterCorruptFileRecoveryForTestingIfNeeded()
#endif
    }

    private func deferDecodeFailureForRetainedFile(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        key: String,
        redownloadsWhenReleased: Bool
    ) {
        retainedDecodeFailureDescriptors[key] = descriptor
        refreshDiskProtection()
        guard redownloadsWhenReleased,
              !activeImageCallbacks(forKey: key).isEmpty else {
            let callbacks = detachImageCallbacks(forKey: key)
            finishForegroundWork(forKey: key, callbacks: callbacks)
            return
        }
    }

#if DEBUG && os(iOS)
    private func runBeforeDownloadFinalizationCommitForTestingIfNeeded() async {
        guard let beforeDownloadFinalizationCommitForTesting else { return }
        self.beforeDownloadFinalizationCommitForTesting = nil
        await beforeDownloadFinalizationCommitForTesting()
    }

    private func runAfterCorruptFileRecoveryForTestingIfNeeded() async {
        guard let afterCorruptFileRecoveryForTesting else { return }
        self.afterCorruptFileRecoveryForTesting = nil
        await afterCorruptFileRecoveryForTesting()
    }

    private func runAfterRetainedDecodeFailureForTestingIfNeeded() async {
        guard let afterRetainedDecodeFailureForTesting else { return }
        self.afterRetainedDecodeFailureForTesting = nil
        await afterRetainedDecodeFailureForTesting()
    }
#endif

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

        let hasFile = knownFileAvailability
            ?? (knownAvailableFileURLs[key] != nil)
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
#if DEBUG && os(iOS)
        resumeFileLeaseCountWaitersForTesting(forKey: key)
#endif
        refreshDiskProtection()
    }

#if DEBUG && os(iOS)
    private func resumeFileLeaseCountWaitersForTesting(forKey key: String) {
        let count = retainedFileKeys[key] ?? 0
        var pendingWaiters = [FileLeaseCountWaiter]()
        for waiter in fileLeaseCountWaitersForTesting.removeValue(forKey: key)
            ?? [] {
            if count <= waiter.expectedCount {
                waiter.request.finish(())
            } else {
                pendingWaiters.append(waiter)
            }
        }
        if !pendingWaiters.isEmpty {
            fileLeaseCountWaitersForTesting[key] = pendingWaiters
        }
    }
#endif

    private func handleRetainedDecodeFailureIfNeeded(
        forKey key: String
    ) async {
        guard let descriptor = retainedDecodeFailureDescriptors.removeValue(forKey: key) else { return }
        refreshDiskProtection()
        await removeCachedFileAfterDecodeFailure(
            for: descriptor,
            fileURL: fileURL(for: descriptor)
        )
        if hasRetainedFile(forKey: key) {
            retainedDecodeFailureDescriptors[key] = descriptor
            refreshDiskProtection()
            return
        }

        if completions[key]?.isEmpty == false {
            startForegroundDownload(for: descriptor, key: key)
        } else {
            finishForegroundWork(forKey: key)
        }
    }

    private func removeCachedFileAfterDecodeFailure(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL
    ) async {
        let location = layout.location(for: descriptor)
        let token = makeFileRemovalToken()
        pendingCorruptFileRemovals[location.key]?.cancel()
        pendingCorruptFileRemovals[location.key] = token
#if DEBUG && os(iOS)
        if let beforeCorruptFileRemovalForTesting {
            self.beforeCorruptFileRemovalForTesting = nil
            await beforeCorruptFileRemovalForTesting()
        }
#endif
        let removal = await diskStore.removeCorruptFile(
            at: location,
            token: token
        )
        if pendingCorruptFileRemovals[location.key] === token {
            pendingCorruptFileRemovals.removeValue(forKey: location.key)
        }
        guard removal.mediaURLIsUnavailable else { return }
        await applyRemovedMediaURLs([fileURL])
#if os(iOS) || os(macOS)
        if removal.didRemoveItem {
            await diskPruner.invalidateEstimatedState()
        }
#endif
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
            return 1
        }

        return foregroundWorkKeys.isEmpty ? 0.5 : 0
    }

    private func updateOngoingDownloadPriorities() {
        for key in Array(ongoingDownloads.keys) {
            updateOngoingDownloadPriority(forKey: key)
        }
    }

    private func updateOngoingDownloadPriority(forKey key: String) {
        guard var download = ongoingDownloads[key] else { return }
        download.priorityRevision &+= 1
        ongoingDownloads[key] = download
        let priority = downloadTaskPriority(forKey: key)
        let revision = download.priorityRevision
        Task {
            await downloader.setPriority(
                priority,
                for: download.id,
                revision: revision
            )
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
        callbacks: ImageLoadRequests = [:],
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
                ?? (knownAvailableFileURLs[key] != nil)
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

    private func complete(_ callbacks: ImageLoadRequests, with image: DownloadableMediaImage?) {
        complete(Array(callbacks.values), with: image)
    }

    private func complete(_ callbacks: [ImageLoadRequest], with image: DownloadableMediaImage?) {
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
                callback.result.finish(image)
            }
#if os(tvOS) || os(visionOS)
            self?.rescheduleFileEvictionIfNeeded(for: callbacks.map(\.descriptor))
#endif
        }
    }

    private func completeFile(_ callbacks: FileLoadRequests, with fileURL: URL?) {
        completeFile(Array(callbacks.values), with: fileURL)
    }

    private func completeFile(_ callbacks: [FileLoadRequest], with fileURL: URL?) {
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
                callback.result.finish(fileURL)
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
        refreshDiskProtection()
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
        refreshDiskProtection()
    }

    private func cancelDownload(forKey key: String) {
        guard var download = ongoingDownloads[key],
              !download.isCancelling else {
            return
        }
        if download.isFinalizing {
            complete(completions.removeValue(forKey: key) ?? [:], with: nil)
            completeFile(fileCompletions.removeValue(forKey: key) ?? [:], with: nil)
            refreshDiskProtection()
            return
        }
        download.isCancelling = true
        ongoingDownloads[key] = download
        download.operation.cancel()
        complete(completions.removeValue(forKey: key) ?? [:], with: nil)
        completeFile(fileCompletions.removeValue(forKey: key) ?? [:], with: nil)
        refreshDiskProtection()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.downloader.cancel(requestID: download.id)
            guard self.ongoingDownloads[key]?.id == download.id else {
                return
            }
            self.ongoingDownloads.removeValue(forKey: key)
            let hasDemand = self.hasDemandCallbacksOrRetainedFile(
                forKey: key
            )
            if hasDemand
                || self.isDescriptorInActiveWindow(download.descriptor) {
                self.enqueueDownloadIfNeeded(
                    download.descriptor,
                    isForegroundRequest: hasDemand,
                    hasFile: false
                )
            }
            self.refreshDiskProtection()
            self.startDownloadsIfNeeded()
        }
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
            refreshDiskProtection()
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
        refreshDiskProtection()
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
        refreshDiskProtection()
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
        refreshDiskProtection()
#if !os(iOS)
        clearDecodedImageMemory()
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
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        let removalId = UUID()
        let token = makeFileRemovalToken()
        pendingFinalizedFileRemovals[removalId] = PendingFinalizedFileRemoval(
            collectionId: descriptor.collectionId,
            fileNames: Set(fileNames(for: descriptor)),
            token: token
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            let location = self.layout.location(for: descriptor)
            let removal = await self.diskStore.removePair(
                at: location,
                token: token
            )
            if removal.mediaURLIsUnavailable {
                await self.applyRemovedMediaURLs([location.mediaURL])
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
        let protectedFileNames = fileNamesProtectedFromEviction(
            collectionId: collectionId,
            allowedFileNames: allowedFileNames
        )
        let token = makeFileRemovalToken()
        fileEvictionToken = token
        fileEvictionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.diskStore.evictFilesOutsideWindow(
                collectionId: collectionId,
                protectedFileNames: protectedFileNames,
                token: token
            )
            await self.applyRemovedMediaURLs(result.removedMediaURLs)
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


#if !os(iOS)
    private func evictMemoryOutsideWindow(collectionId: String, allowedKeys: Set<String>) {
        memoryCache.evictOutsideWindow(
            collectionId: collectionId,
            allowedKeys: allowedKeys
        )
    }

    private func evictMemoryOutsideActiveCollection(collectionId: String) {
        memoryCache.evictOutsideActiveCollection(collectionId)
    }
#endif

    private func cache(_ image: DownloadableMediaImage, for descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        let key = cacheKey(for: descriptor)
        memoryCache.insert(
            image,
            forKey: key,
            collectionId: descriptor.collectionId
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
        layout.cacheKey(for: descriptor)
    }

    private func cachedDecodedImage(forKey key: String) -> DownloadableMediaImage? {
        cachedDecodedImageLookup(forKey: key).image
    }

    private func cachedDecodedImageLookup(
        forKey key: String
    ) -> (image: DownloadableMediaImage?, recordsDiskAccess: Bool) {
        let lookup = memoryCache.lookup(forKey: key)
        return (lookup.image, lookup.recordsDiskAccess)
    }

    nonisolated private func fileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL {
        layout.location(for: descriptor).mediaURL
    }

    nonisolated private func metadataFileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL {
        layout.location(for: descriptor).metadataURL
    }

    nonisolated private func fileNames(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> [String] {
        layout.fileNames(for: descriptor)
    }

    nonisolated private func collectionDirectory(collectionId: String) -> URL {
        layout.collectionDirectory(collectionId: collectionId)
    }

}
