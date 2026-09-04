// ∅ 2026 lil org

import os
import UIKit

@MainActor
protocol MobilePlaybackSessionDisplay: AnyObject {

    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentPagePosition() -> PlayerPagePosition
    func flushPendingViewingProgress()

}

nonisolated protocol MobilePlaybackViewingSessionTracking: Sendable {
    func prepareRestartUpdate(
        collectionId: String?
    ) async -> PlayerContinueViewingUpdate?
    func beginRestart(update: PlayerContinueViewingUpdate?) async
    func markViewed(_ progress: MobileViewingProgress) async
}

nonisolated extension PlayerViewingSessionTracker:
    MobilePlaybackViewingSessionTracking {}

struct MobilePlayerFileShareItem {
    let fileURL: URL
    let previewTitle: String
    let previewImage: () -> UIImage?
    private let fileLease: DownloadableMediaFileLease

    init(
        fileURL: URL,
        previewTitle: String,
        fileLease: DownloadableMediaFileLease,
        previewImage: @escaping () -> UIImage?
    ) {
        self.fileURL = fileURL
        self.previewTitle = previewTitle
        self.previewImage = previewImage
        self.fileLease = fileLease
    }
}

typealias MobilePlayerDisplayMode = PlayerDisplayMode

extension PlayerDisplayMode {
    static func initialMode(
        for config: MobilePlayerConfig,
        collectionBrowserAvailable: Bool
    ) -> PlayerDisplayMode {
        initialMode(
            hasWidgetTokenInsertion: config.widgetTokenInsertion != nil,
            collectionBrowserAvailable: collectionBrowserAvailable
        )
    }
}

extension PlayerCollectionBrowserSupport {
    static func isAvailable(for config: MobilePlayerConfig) -> Bool {
        guard let collectionId = config.specificToken?.fullCollectionId ?? config.initialItemId else {
            return false
        }
        return isAvailable(forCollectionId: collectionId)
    }
}

extension MobilePlayerFileShareItem {
    static func previewTitle(for token: GeneratedToken, progressText: String) -> String {
        let trimmedCollectionName = token.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = token.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle: String
        if !trimmedCollectionName.isEmpty {
            baseTitle = trimmedCollectionName
        } else if !trimmedDisplayName.isEmpty {
            baseTitle = trimmedDisplayName
        } else {
            baseTitle = Strings.nftPlayer
        }
        let trimmedProgressText = progressText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedProgressText.isEmpty ? baseTitle : "\(baseTitle) \(trimmedProgressText)"
    }
}

@MainActor
enum MobileCollectionBrowseMediaResolver {

    nonisolated static func collectionBrowseThumbnailDescriptor(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> DownloadableMediaDescriptor? {
        guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else { return nil }

        return MobileCollectionCatalog.collectionBrowseThumbnailDescriptor(
            specificCollectionId: snapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    nonisolated static func collectionBrowseImageSources(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else { return nil }

        return MobileCollectionCatalog.collectionBrowseImageSources(
            specificCollectionId: snapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    nonisolated static func collectionBrowseImageDescriptor(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int,
        quality: CollectionBrowseImageQuality
    ) -> DownloadableMediaDescriptor? {
        switch quality {
        case .smallestThumbnail:
            guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else {
                return nil
            }
            return MobileCollectionCatalog.collectionBrowseSizedThumbnailDescriptor(
                specificCollectionId: snapshot.collectionId,
                tokenIndex: tokenIndex,
                width: .width140
            )
        case .smallThumbnail:
            guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else {
                return nil
            }
            return MobileCollectionCatalog.collectionBrowseSizedThumbnailDescriptor(
                specificCollectionId: snapshot.collectionId,
                tokenIndex: tokenIndex,
                width: .width260
            ) ?? collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            )
        case .thumbnail:
            return collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            )
        case .large:
            return collectionBrowseImageSources(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            )?.largeDescriptor
        }
    }

    static func collectionBrowsePrefetchDescriptor(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int,
        quality: CollectionBrowseImageQuality
    ) -> DownloadableMediaDescriptor? {
        guard let sources = collectionBrowseImageSources(
            snapshot: snapshot,
            tokenIndex: tokenIndex
        ) else {
            return nil
        }
        guard let requestedDescriptor = sources.descriptor(for: quality) else {
            return nil
        }
        let cache = DownloadableMediaCache.shared
        if quality == .thumbnail,
           sources.largeDescriptor != requestedDescriptor,
           cache.cachedDecodedImage(for: sources.largeDescriptor) != nil {
            return nil
        }
        if cache.cachedDecodedImage(for: requestedDescriptor) != nil {
            return nil
        }
        guard quality.isDenseGridThumbnail else {
            return requestedDescriptor
        }
        let satisfyingDescriptors: [DownloadableMediaDescriptor]
        switch quality {
        case .smallestThumbnail:
            satisfyingDescriptors = [
                sources.smallThumbnailDescriptor,
                sources.thumbnailDescriptor,
            ]
        case .smallThumbnail:
            satisfyingDescriptors = [sources.thumbnailDescriptor]
        case .thumbnail, .large:
            satisfyingDescriptors = []
        }
        if satisfyingDescriptors.contains(where: {
            $0 != requestedDescriptor
                && cache.cachedDecodedImage(for: $0) != nil
        }) {
            return nil
        }
        return requestedDescriptor
    }

    static func collectionBrowseThumbnailAspectRatioProfile(
        snapshot: PlayerCollectionBrowseSnapshot
    ) -> ThumbnailAspectRatioProfile? {
        guard snapshot.itemCount > 0,
              let profile = MobileCollectionCatalog.collectionBrowseThumbnailAspectRatioProfile(
                specificCollectionId: snapshot.collectionId
              ),
              profile.isCompatible(withItemCount: snapshot.itemCount) else {
            return nil
        }
        return profile
    }

    nonisolated static func collectionBrowseCompactCoverage(
        imageSources: CollectionBrowseImageSources?,
        centeredAt tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        itemCount: Int,
        columnCount: Int,
        prefetchStride: Int,
        quality: CollectionBrowseImageQuality,
        requiredTokenRange: ClosedRange<Int>?
    ) -> PlayerCollectionBrowseMediaWindowPolicy.CompactCoverage? {
        guard quality.isDenseGridThumbnail,
              let requiredTokenRange,
              let imageSources,
              let requestedDescriptor = imageSources.descriptor(for: quality),
              requestedDescriptor != imageSources.thumbnailDescriptor else {
            return nil
        }
        return PlayerCollectionBrowseMediaWindowPolicy.compactCoverage(
            centeredAt: tokenIndex,
            requiredTokenRange: requiredTokenRange,
            itemCount: itemCount,
            columnCount: columnCount,
            prefetchStride: prefetchStride,
            prefersIncreasingIndices: direction == .forward
        )
    }
}

nonisolated struct MobileCollectionBrowseThumbnailWindowPlanRequest: Sendable {
    let snapshot: PlayerCollectionBrowseSnapshot
    let tokenIndex: Int
    let direction: PlayerMediaPrefetchDirection
    let prefetchStride: Int
    let columnCount: Int
    let quality: CollectionBrowseImageQuality
    let requiredTokenRange: ClosedRange<Int>?
    let visibleTokenRange: ClosedRange<Int>?
    let isFileOnly: Bool
    let decodeVariant: DownloadableMediaImageDecodeVariant
    let displayedHigherQualityThumbnailTokenIndices: Set<Int>
    let displayedLargeTokenIndices: Set<Int>
    let locallyAvailableLargeTokenIndices: Set<Int>
}

nonisolated protocol MobileCollectionBrowseThumbnailWindowPlanning: Sendable {
    func makeWindow(
        for request: MobileCollectionBrowseThumbnailWindowPlanRequest
    ) async -> PlayerDownloadableMediaWindow?
}

nonisolated enum MobileCollectionBrowseThumbnailWindowPreparationResult:
    Equatable,
    Sendable {
    case planned
    case committed
    case unavailable
    case superseded
}

nonisolated final class MobileCollectionBrowseImageSourcesCache: Sendable {
    private struct CacheIdentity: Hashable, Sendable {
        let collectionId: String
        let itemCount: Int
    }

    private struct CacheKey: Hashable, Sendable {
        let identity: CacheIdentity
        let tokenIndex: Int
    }

    private enum CachedImageSources: Sendable {
        case available(CollectionBrowseImageSources)
        case unavailable

        var value: CollectionBrowseImageSources? {
            switch self {
            case let .available(imageSources):
                imageSources
            case .unavailable:
                nil
            }
        }
    }

    private struct CachedImageSourcesEntry: Sendable {
        let imageSources: CachedImageSources
        var lessRecentKey: CacheKey?
        var moreRecentKey: CacheKey?
    }

    private enum Lookup {
        case cached(CachedImageSources)
        case missing(revision: UInt)
    }

    private struct Storage: Sendable {
        var revision: UInt = 0
        var cachedImageSourcesByKey = [
            CacheKey: CachedImageSourcesEntry
        ]()
        var retainedKeys = Set<CacheKey>()
        var retainedImageSources = [CacheKey: CachedImageSources]()
        var leastRecentKey: CacheKey?
        var mostRecentKey: CacheKey?

        mutating func removeAll() {
            revision &+= 1
            cachedImageSourcesByKey.removeAll(keepingCapacity: true)
            retainedKeys.removeAll()
            retainedImageSources.removeAll()
            leastRecentKey = nil
            mostRecentKey = nil
        }

        mutating func lookup(key: CacheKey) -> Lookup {
            guard let cached = retainedImageSources[key]
                ?? cachedImageSourcesByKey[key]?.imageSources else {
                return .missing(revision: revision)
            }
            markImageSourcesAsMostRecent(key: key)
            return .cached(cached)
        }

        mutating func retainImageSources(for keys: Set<CacheKey>) {
            retainedKeys = keys
            retainedImageSources = retainedImageSources.filter {
                keys.contains($0.key)
            }
            for key in keys {
                if let cached = cachedImageSourcesByKey[key] {
                    retainedImageSources[key] = cached.imageSources
                }
            }
        }

        mutating func insertImageSources(
            _ imageSources: CachedImageSources,
            key: CacheKey,
            maximumCachedImageSourceCount: Int
        ) {
            if retainedKeys.contains(key) {
                retainedImageSources[key] = imageSources
            }
            if cachedImageSourcesByKey.count
                >= maximumCachedImageSourceCount {
                evictLeastRecentImageSources()
            }
            cachedImageSourcesByKey[key] = CachedImageSourcesEntry(
                imageSources: imageSources,
                lessRecentKey: mostRecentKey,
                moreRecentKey: nil
            )
            if let mostRecentKey {
                cachedImageSourcesByKey[mostRecentKey]?.moreRecentKey = key
            } else {
                leastRecentKey = key
            }
            mostRecentKey = key
        }

        mutating func markImageSourcesAsMostRecent(key: CacheKey) {
            guard key != mostRecentKey,
                  var entry = cachedImageSourcesByKey[key] else {
                return
            }
            if let lessRecentKey = entry.lessRecentKey {
                cachedImageSourcesByKey[lessRecentKey]?.moreRecentKey =
                    entry.moreRecentKey
            } else {
                leastRecentKey = entry.moreRecentKey
            }
            if let moreRecentKey = entry.moreRecentKey {
                cachedImageSourcesByKey[moreRecentKey]?.lessRecentKey =
                    entry.lessRecentKey
            }
            entry.lessRecentKey = mostRecentKey
            entry.moreRecentKey = nil
            if let mostRecentKey {
                cachedImageSourcesByKey[mostRecentKey]?.moreRecentKey = key
            }
            cachedImageSourcesByKey[key] = entry
            mostRecentKey = key
        }

        mutating func evictLeastRecentImageSources() {
            guard let key = leastRecentKey,
                  let entry = cachedImageSourcesByKey.removeValue(forKey: key)
            else {
                return
            }
            leastRecentKey = entry.moreRecentKey
            if let leastRecentKey {
                cachedImageSourcesByKey[leastRecentKey]?.lessRecentKey = nil
            } else {
                mostRecentKey = nil
            }
        }
    }

    private let maximumCachedImageSourceCount: Int
    private let imageSourcesResolver: @Sendable (
        PlayerCollectionBrowseSnapshot,
        Int
    ) -> CollectionBrowseImageSources?
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    init(
        maximumCachedImageSourceCount: Int = 512,
        imageSourcesResolver: @escaping @Sendable (
            PlayerCollectionBrowseSnapshot,
            Int
        ) -> CollectionBrowseImageSources? = {
            MobileCollectionBrowseMediaResolver.collectionBrowseImageSources(
                snapshot: $0,
                tokenIndex: $1
            )
        }
    ) {
        self.maximumCachedImageSourceCount = max(
            maximumCachedImageSourceCount,
            1
        )
        self.imageSourcesResolver = imageSourcesResolver
    }

    func clear() {
        storage.withLock { state in
            state.removeAll()
        }
    }

    fileprivate func retainVisibleImageSources(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenRange: ClosedRange<Int>?
    ) {
        let identity = CacheIdentity(
            collectionId: snapshot.collectionId,
            itemCount: snapshot.itemCount
        )
        var keys = Set<CacheKey>()
        if let tokenRange {
            let first = max(tokenRange.lowerBound, 0)
            let last = min(tokenRange.upperBound, snapshot.itemCount - 1)
            if first <= last {
                keys = Set((first...last).map {
                    CacheKey(identity: identity, tokenIndex: $0)
                })
            }
        }
        storage.withLock { [keys] state in
            state.retainImageSources(for: keys)
        }
    }

    fileprivate func resolveImageSources(
        snapshot: PlayerCollectionBrowseSnapshot?,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        guard let snapshot,
              snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return nil
        }
        let key = CacheKey(
            identity: CacheIdentity(
                collectionId: snapshot.collectionId,
                itemCount: snapshot.itemCount
            ),
            tokenIndex: tokenIndex
        )
        let lookup = storage.withLock { state in
            state.lookup(key: key)
        }
        let revision: UInt
        switch lookup {
        case let .cached(imageSources):
            return imageSources.value
        case let .missing(cacheRevision):
            revision = cacheRevision
        }
        let resolved = imageSourcesResolver(snapshot, tokenIndex)
        let cachedImageSources: CachedImageSources = resolved.map {
            .available($0)
        } ?? .unavailable
        return storage.withLock { state in
            guard state.revision == revision else {
                return nil
            }
            switch state.lookup(key: key) {
            case let .cached(imageSources):
                return imageSources.value
            case .missing:
                state.insertImageSources(
                    cachedImageSources,
                    key: key,
                    maximumCachedImageSourceCount:
                        maximumCachedImageSourceCount
                )
                return resolved
            }
        }
    }

    func cachedImageSources(
        snapshot: PlayerCollectionBrowseSnapshot?,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        guard let snapshot,
              snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return nil
        }
        let key = CacheKey(
            identity: CacheIdentity(
                collectionId: snapshot.collectionId,
                itemCount: snapshot.itemCount
            ),
            tokenIndex: tokenIndex
        )
        return storage.withLock { state in
            switch state.lookup(key: key) {
            case let .cached(imageSources):
                return imageSources.value
            case .missing:
                return nil
            }
        }
    }

    var cachedImageSourceCount: Int {
        storage.withLock { state in
            Set(state.cachedImageSourcesByKey.keys)
                .union(state.retainedImageSources.keys).count
        }
    }
}

actor MobileCollectionBrowseThumbnailWindowPlanner:
    MobileCollectionBrowseThumbnailWindowPlanning {
    private let imageSourcesCache: MobileCollectionBrowseImageSourcesCache

    init(imageSourcesCache: MobileCollectionBrowseImageSourcesCache) {
        self.imageSourcesCache = imageSourcesCache
    }

    func makeWindow(
        for request: MobileCollectionBrowseThumbnailWindowPlanRequest
    ) async -> PlayerDownloadableMediaWindow? {
        guard !Task.isCancelled,
              request.snapshot.pagePosition(
                forTokenIndex: request.tokenIndex
              ) != nil else {
            return nil
        }
        imageSourcesCache.retainVisibleImageSources(
            snapshot: request.snapshot,
            tokenRange: request.visibleTokenRange ?? request.requiredTokenRange
        )
        let centerImageSources = imageSources(
            snapshot: request.snapshot,
            tokenIndex: request.tokenIndex
        )
        guard !Task.isCancelled else { return nil }
        let compactCoverage = MobileCollectionBrowseMediaResolver
            .collectionBrowseCompactCoverage(
                imageSources: centerImageSources,
                centeredAt: request.tokenIndex,
                direction: request.direction,
                itemCount: request.snapshot.itemCount,
                columnCount: request.columnCount,
                prefetchStride: request.prefetchStride,
                quality: request.quality,
                requiredTokenRange: request.requiredTokenRange
            )
        let window = PlayerCollectionBrowseMediaWindowLayout.makeWindow(
            centeredAt: request.tokenIndex,
            itemCount: request.snapshot.itemCount,
            direction: request.direction,
            prefetchStride: request.prefetchStride,
            columnCount: request.columnCount,
            compactCoverage: compactCoverage,
            visibleTokenRange: request.visibleTokenRange,
            includesDecodedDescriptors: !request.isFileOnly,
            decodeVariant: request.decodeVariant,
            descriptorForTokenIndex: { candidateTokenIndex in
                guard !Task.isCancelled else { return nil }
                let selection = CollectionBrowseImageWindowSelection.resolve(
                    requiredQuality: request.quality,
                    isDisplayingSatisfyingThumbnail:
                        request.displayedHigherQualityThumbnailTokenIndices
                            .contains(candidateTokenIndex),
                    isDisplayingLargeImage:
                        request.displayedLargeTokenIndices.contains(
                            candidateTokenIndex
                        ),
                    largeImageIsLocallyAvailable:
                        request.locallyAvailableLargeTokenIndices.contains(
                            candidateTokenIndex
                        )
                )
                switch selection {
                case .requestedQuality:
                    return self.imageSources(
                        snapshot: request.snapshot,
                        tokenIndex: candidateTokenIndex
                    )?.descriptor(for: request.quality)
                case .locallyAvailableLarge:
                    return self.imageSources(
                        snapshot: request.snapshot,
                        tokenIndex: candidateTokenIndex
                    )?.largeDescriptor
                case .omitSatisfiedToken:
                    return nil
                }
            }
        )
        return Task.isCancelled ? nil : window
    }

    private func imageSources(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        guard !Task.isCancelled else { return nil }
        return imageSourcesCache.resolveImageSources(
            snapshot: snapshot,
            tokenIndex: tokenIndex
        )
    }
}

@MainActor
final class MobileCollectionBrowseThumbnailWindowPreparationOrder {
    struct Claim: Equatable {
        let sequence: UInt64
    }

    private var nextSequence: UInt64 = 0
    private var latestCommittedSequence: UInt64 = 0

    func claim() -> Claim {
        nextSequence &+= 1
        return Claim(sequence: nextSequence)
    }

    func commitIfNewer(_ claim: Claim) -> Bool {
        guard claim.sequence > latestCommittedSequence else { return false }
        latestCommittedSequence = claim.sequence
        return true
    }

    func supersedePendingClaims() {
        nextSequence &+= 1
        latestCommittedSequence = nextSequence
    }
}

@MainActor
final class MobilePlaybackSession {

    private enum LifecycleState: Equatable {
        case active
        case disconnecting
        case disconnected
    }

    private static let collectionBrowseThumbnailWindowPreparationOrder =
        MobileCollectionBrowseThumbnailWindowPreparationOrder()

    let config: MobilePlayerConfig

    var id: UUID {
        config.id
    }

    var isActive: Bool {
        lifecycleState == .active
    }

    private weak var display: MobilePlaybackSessionDisplay?
    private let viewingSessionTracker: any MobilePlaybackViewingSessionTracking
    fileprivate let mediaWindowOwnerID = UUID()
    private let disconnect: @MainActor (MobilePlaybackSession) -> Void
    private var lifecycleState = LifecycleState.active
    private var navigationRequestGeneration: UInt = 0
    let collectionBrowseImageSourcesCache:
        MobileCollectionBrowseImageSourcesCache
    private let collectionBrowseThumbnailWindowPlanner:
        any MobileCollectionBrowseThumbnailWindowPlanning
    private let installDownloadableMediaWindow: @MainActor (
        PlayerDownloadableMediaWindow,
        UUID
    ) -> Void
    private var collectionBrowseThumbnailWindowPreparationTask:
        Task<Void, Never>?
    private var collectionBrowseThumbnailWindowPreparationGeneration: UInt = 0
    private var collectionBrowseThumbnailWindowPreparationCompletion:
        (@MainActor (
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ) -> Void)?
    private lazy var dataSource = PlayerTokenPagingDataSource(
        initialCollectionId: config.initialItemId,
        specificInitialToken: config.specificToken,
        initialTokenId: config.initialTokenId,
        initialTokenIndex: config.initialTokenIndex,
        widgetTokenInsertion: config.widgetTokenInsertion
    )

    fileprivate init(
        config: MobilePlayerConfig,
        viewingSessionTracker: any MobilePlaybackViewingSessionTracking,
        collectionBrowseImageSourcesCache:
            MobileCollectionBrowseImageSourcesCache,
        collectionBrowseThumbnailWindowPlanner:
            any MobileCollectionBrowseThumbnailWindowPlanning,
        installDownloadableMediaWindow: @escaping @MainActor (
            PlayerDownloadableMediaWindow,
            UUID
        ) -> Void = {
            DownloadableMediaCache.shared.prepareWindow($0, ownerId: $1)
        },
        disconnect: @escaping @MainActor (MobilePlaybackSession) -> Void
    ) {
        self.config = config
        self.viewingSessionTracker = viewingSessionTracker
        self.collectionBrowseImageSourcesCache =
            collectionBrowseImageSourcesCache
        self.collectionBrowseThumbnailWindowPlanner =
            collectionBrowseThumbnailWindowPlanner
        self.installDownloadableMediaWindow = installDownloadableMediaWindow
        self.disconnect = disconnect
    }

    func attach(display: MobilePlaybackSessionDisplay) {
        guard lifecycleState == .active else { return }
        self.display = display
    }

    func stopAndDisconnect() {
        guard lifecycleState == .active else { return }
        lifecycleState = .disconnecting
        let thumbnailWindowCompletion =
            detachPendingCollectionBrowseThumbnailWindowPreparation()
        advanceNavigationRequestGeneration()
        display?.flushPendingViewingProgress()
        display = nil
        collectionBrowseImageSourcesCache.clear()
        lifecycleState = .disconnected
        disconnect(self)
        thumbnailWindowCompletion?(.superseded)
    }

    func goForward() {
        guard lifecycleState == .active else { return }
        advanceNavigationRequestGeneration()
        display?.navigate(.forward)
    }

    func goBack() {
        guard lifecycleState == .active else { return }
        advanceNavigationRequestGeneration()
        display?.navigate(.back)
    }

    @discardableResult
    func restartCollection() -> Task<Void, Never>? {
        guard lifecycleState == .active,
              let display else {
            return nil
        }
        let requestGeneration = advanceNavigationRequestGeneration()
        let startingPagePosition = display.getCurrentPagePosition()
        let displayIdentity = ObjectIdentifier(display)
        dataSource.acknowledgeIntentionalViewingPosition()
        let collectionId = dataSource
            .collectionTokenContext(pagePosition: startingPagePosition)?.collectionId
        let tracker = viewingSessionTracker
        return Task { @MainActor [weak self] in
            let update = await tracker.prepareRestartUpdate(collectionId: collectionId)
            guard let self,
                  self.lifecycleState == .active,
                  self.navigationRequestGeneration == requestGeneration,
                  let currentDisplay = self.display,
                  ObjectIdentifier(currentDisplay) == displayIdentity,
                  currentDisplay.getCurrentPagePosition() == startingPagePosition else {
                return
            }
            PlayerPersistenceUpdates.enqueue {
                await tracker.beginRestart(update: update)
            }
            currentDisplay.navigate(.restartCollection)
        }
    }

    func cancelPendingCollectionRestart() {
        guard lifecycleState != .disconnected else { return }
        advanceNavigationRequestGeneration()
    }

    func clearDownloadableMediaWindow() {
        guard lifecycleState != .disconnected else { return }
        let completion =
            detachPendingCollectionBrowseThumbnailWindowPreparation()
        DownloadableMediaCache.shared.clearActiveWindow(ownerId: mediaWindowOwnerID)
        completion?(.superseded)
    }

    func getToken(pagePosition: PlayerPagePosition) -> GeneratedToken {
        activeDataSource?.getToken(pagePosition: pagePosition) ?? .empty
    }

    func canRender(pagePosition: PlayerPagePosition) -> Bool {
        activeDataSource?.canRender(pagePosition: pagePosition) ?? false
    }

    func pageLabel(pagePosition: PlayerPagePosition) -> String? {
        activeDataSource?.pageLabel(pagePosition: pagePosition)
    }

    func isInsertedWidgetToken(pagePosition: PlayerPagePosition) -> Bool {
        activeDataSource?.isInsertedWidgetToken(pagePosition: pagePosition) ?? false
    }

    func collectionBrowseSnapshot() -> PlayerCollectionBrowseSnapshot? {
        activeDataSource?.collectionBrowseSnapshot()
    }

    func prepareCollectionBrowse(
        containing pagePosition: PlayerPagePosition
    ) -> PlayerCollectionBrowsePreparation? {
        activeDataSource?.prepareCollectionBrowse(containing: pagePosition)
    }

    func commitCollectionBrowse(
        preparation: PlayerCollectionBrowsePreparation
    ) -> PlayerCollectionBrowsePositionResolution {
        activeDataSource?.commitCollectionBrowse(preparation) ?? .unavailable
    }

    func collectionBrowseThumbnailDescriptor(
        pagePosition: PlayerPagePosition
    ) -> DownloadableMediaDescriptor? {
        guard let context = collectionTokenContext(pagePosition: pagePosition) else {
            return nil
        }

        return MobileCollectionCatalog.collectionBrowseThumbnailDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func layoutInteractionState(
        displayMode: MobilePlayerDisplayMode,
        pagePosition: PlayerPagePosition?,
        collectionBrowserAvailable expectedCollectionBrowserAvailability: Bool? = nil
    ) -> MobilePlayerLayoutInteractionState {
        let currentDescriptor = pagePosition.flatMap {
            collectionBrowseThumbnailDescriptor(pagePosition: $0)
                ?? downloadableMediaDescriptor(pagePosition: $0)
        }
        let collectionBrowserAvailable = expectedCollectionBrowserAvailability
            ?? PlayerCollectionBrowserSupport.isAvailable(for: currentDescriptor)
        guard let pagePosition,
              collectionTokenContext(pagePosition: pagePosition) != nil,
              collectionBrowserAvailable else {
            return MobilePlayerLayoutInteractionState(
                displayMode: displayMode,
                pagePosition: pagePosition,
                collectionBrowserAvailable: false,
                currentDescriptor: nil,
                browserSwitchMode: .animated
            )
        }

        return MobilePlayerLayoutInteractionState(
            displayMode: displayMode,
            pagePosition: pagePosition,
            collectionBrowserAvailable: true,
            currentDescriptor: currentDescriptor,
            browserSwitchMode: isInsertedWidgetToken(pagePosition: pagePosition)
                ? .offscreenInsertion
                : .animated
        )
    }

    func prepareDownloadableMediaWindow(
        pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        guard lifecycleState == .active else { return nil }
        let completion =
            detachPendingCollectionBrowseThumbnailWindowPreparation()
        guard let window = dataSource.downloadableMediaWindow(
            pagePosition: pagePosition,
            direction: direction
        ) else {
            DownloadableMediaCache.shared.clearActiveWindow(
                ownerId: mediaWindowOwnerID
            )
            completion?(.superseded)
            return nil
        }
        Self.collectionBrowseThumbnailWindowPreparationOrder
            .supersedePendingClaims()

        installDownloadableMediaWindow(window, mediaWindowOwnerID)
        completion?(.superseded)
        return window
    }

    func prepareCollectionBrowseThumbnailWindow(
        snapshot explicitSnapshot: PlayerCollectionBrowseSnapshot? = nil,
        centeredAt tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        prefetchStride: Int,
        columnCount: Int,
        quality: CollectionBrowseImageQuality,
        requiredTokenRange: ClosedRange<Int>?,
        visibleTokenRange: ClosedRange<Int>? = nil,
        isFileOnly: Bool = false,
        decodeVariant: DownloadableMediaImageDecodeVariant = .full,
        displayedHigherQualityThumbnailTokenIndices: Set<Int>,
        displayedLargeTokenIndices: Set<Int>,
        locallyAvailableLargeTokenIndices: Set<Int>,
        shouldApply: @escaping @MainActor () -> Bool = { true },
        completion: @escaping @MainActor (
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ) -> Void = { _ in }
    ) {
        guard lifecycleState == .active else {
            completion(.superseded)
            return
        }
        let supersededCompletion =
            detachPendingCollectionBrowseThumbnailWindowPreparation()
        guard let snapshot = explicitSnapshot ?? collectionBrowseSnapshot() else {
            collectionBrowseImageSourcesCache.clear()
            DownloadableMediaCache.shared.clearActiveWindow(
                ownerId: mediaWindowOwnerID
            )
            supersededCompletion?(.superseded)
            completion(.unavailable)
            return
        }
        let generation = collectionBrowseThumbnailWindowPreparationGeneration
        let claim = Self.collectionBrowseThumbnailWindowPreparationOrder.claim()
        let request = MobileCollectionBrowseThumbnailWindowPlanRequest(
            snapshot: snapshot,
            tokenIndex: tokenIndex,
            direction: direction,
            prefetchStride: prefetchStride,
            columnCount: columnCount,
            quality: quality,
            requiredTokenRange: requiredTokenRange,
            visibleTokenRange: visibleTokenRange,
            isFileOnly: isFileOnly,
            decodeVariant: decodeVariant,
            displayedHigherQualityThumbnailTokenIndices:
                displayedHigherQualityThumbnailTokenIndices,
            displayedLargeTokenIndices: displayedLargeTokenIndices,
            locallyAvailableLargeTokenIndices:
                locallyAvailableLargeTokenIndices
        )
        let planner = collectionBrowseThumbnailWindowPlanner
        collectionBrowseThumbnailWindowPreparationCompletion = completion
        collectionBrowseThumbnailWindowPreparationTask = Task {
            [weak self] in
            let preparedWindow = await planner.makeWindow(for: request)
            guard let self,
                  self.collectionBrowseThumbnailWindowPreparationGeneration
                    == generation else {
                return
            }
            self.collectionBrowseThumbnailWindowPreparationTask = nil
            let completion =
                self.collectionBrowseThumbnailWindowPreparationCompletion
            self.collectionBrowseThumbnailWindowPreparationCompletion = nil
            guard !Task.isCancelled,
                  self.lifecycleState == .active else {
                completion?(.superseded)
                return
            }
            let hasPreparedImageSources = preparedWindow != nil
                || self.collectionBrowseImageSourcesCache.cachedImageSources(
                    snapshot: snapshot,
                    tokenIndex: tokenIndex
                ) != nil
            guard hasPreparedImageSources else {
                if self.collectionBrowseSnapshot() == snapshot,
                   shouldApply() {
                    DownloadableMediaCache.shared.clearActiveWindow(
                        ownerId: self.mediaWindowOwnerID
                    )
                }
                completion?(.unavailable)
                return
            }
            guard let preparedWindow,
                  self.collectionBrowseSnapshot() == snapshot,
                  shouldApply(),
                  Self.collectionBrowseThumbnailWindowPreparationOrder
                    .commitIfNewer(claim) else {
                completion?(.planned)
                return
            }
            self.installDownloadableMediaWindow(
                preparedWindow,
                self.mediaWindowOwnerID
            )
            completion?(.committed)
        }
        supersededCompletion?(.superseded)
    }

    func cancelPendingCollectionBrowseThumbnailWindowPreparation() {
        let completion =
            detachPendingCollectionBrowseThumbnailWindowPreparation()
        completion?(.superseded)
    }

    private func detachPendingCollectionBrowseThumbnailWindowPreparation()
        -> (@MainActor (
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ) -> Void)? {
        collectionBrowseThumbnailWindowPreparationGeneration &+= 1
        collectionBrowseThumbnailWindowPreparationTask?.cancel()
        collectionBrowseThumbnailWindowPreparationTask = nil
        let completion = collectionBrowseThumbnailWindowPreparationCompletion
        collectionBrowseThumbnailWindowPreparationCompletion = nil
        return completion
    }

    func downloadableMediaDescriptor(
        pagePosition: PlayerPagePosition
    ) -> DownloadableMediaDescriptor? {
        guard let context = downloadableMediaTokenContext(pagePosition: pagePosition) else {
            return nil
        }

        return MobileCollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func hasNavigationDestination(
        from pagePosition: PlayerPagePosition,
        direction: PlaybackNavigationDirection
    ) -> Bool {
        guard let targetOffset = direction.pageOffset else { return false }

        return canRender(pagePosition: pagePosition.advanced(by: targetOffset))
    }

    func markViewed(
        pagePosition: PlayerPagePosition,
        hasViewedToEnd: Bool = false
    ) -> MobileViewingProgress? {
        guard let dataSource = activeDataSource,
              let progress = dataSource.progress(
                  pagePosition: pagePosition,
                  hasViewedToEnd: hasViewedToEnd
              ) else {
            return nil
        }
        let tracker = viewingSessionTracker
        PlayerPersistenceUpdates.enqueue {
            await tracker.markViewed(progress)
        }
        return progress
    }

    func acknowledgeIntentionalViewingPosition() {
        guard let dataSource = activeDataSource else { return }
        advanceNavigationRequestGeneration()
        dataSource.acknowledgeIntentionalViewingPosition()
    }

    func progress(
        pagePosition: PlayerPagePosition,
        resolvedToken: GeneratedToken
    ) -> MobileViewingProgress? {
        activeDataSource?.progress(
            pagePosition: pagePosition,
            resolvedToken: resolvedToken
        )
    }

    func downloadedFileShareItem(
        pagePosition: PlayerPagePosition
    ) async -> MobilePlayerFileShareItem? {
        guard let dataSource = activeDataSource,
              let context = downloadableMediaTokenContext(
                dataSource: dataSource,
                pagePosition: pagePosition
              ),
              let descriptor = MobileCollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: context.tokenIndex
              ) else {
            return nil
        }

        let cache = DownloadableMediaCache.shared
        let fileLease = cache.fileLease(for: descriptor)
        let fileURL: URL?
        if let knownFileURL = cache.knownLocalFileURL(for: descriptor) {
            fileURL = knownFileURL
        } else {
            fileURL = await cache.existingFileURL(for: descriptor)
        }
        guard !Task.isCancelled,
              downloadableMediaDescriptor(pagePosition: pagePosition) == descriptor,
              let fileURL else {
            fileLease.release()
            return nil
        }
        let token = dataSource.getToken(pagePosition: pagePosition)
        return MobilePlayerFileShareItem(
            fileURL: fileURL,
            previewTitle: MobilePlayerFileShareItem.previewTitle(
                for: token,
                progressText: dataSource.pageLabel(pagePosition: pagePosition)
                    ?? Strings.pagePosition(
                        current: context.tokenIndex + 1,
                        total: context.tokenCount
                    )
            ),
            fileLease: fileLease
        ) {
            cache.cachedDecodedImage(for: descriptor)
        }
    }

    func startPagePosition() -> PlayerPagePosition {
        activeDataSource?.pagePosition(forTokenIndex: 0) ?? .initial
    }

    private var activeDataSource: PlayerTokenPagingDataSource? {
        lifecycleState == .disconnected ? nil : dataSource
    }

    @discardableResult
    private func advanceNavigationRequestGeneration() -> UInt {
        navigationRequestGeneration &+= 1
        return navigationRequestGeneration
    }

    private func downloadableMediaTokenContext(
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let dataSource = activeDataSource else { return nil }
        return downloadableMediaTokenContext(
            dataSource: dataSource,
            pagePosition: pagePosition
        )
    }

    private func collectionTokenContext(
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        activeDataSource?.collectionTokenContext(pagePosition: pagePosition)
    }

    private func downloadableMediaTokenContext(
        dataSource: PlayerTokenPagingDataSource,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let context = dataSource.collectionTokenContext(pagePosition: pagePosition),
              MobileCollectionCatalog.hasDownloadableMediaDescriptor(
                specificCollectionId: context.collectionId
              ) else {
            return nil
        }
        return context
    }
}

@MainActor
final class MobilePlaybackSessionRegistry {

    struct Dependencies {
        let makeViewingSessionTracker:
            @MainActor (String?) -> any MobilePlaybackViewingSessionTracking
        let clearActiveMediaWindow: @MainActor (UUID) -> Void
        let cancelAllMediaDownloads: @MainActor () -> Void
        let makeCollectionBrowseImageSourcesCache:
            @MainActor () -> MobileCollectionBrowseImageSourcesCache
        let makeCollectionBrowseThumbnailWindowPlanner:
            @MainActor (MobileCollectionBrowseImageSourcesCache) ->
                any MobileCollectionBrowseThumbnailWindowPlanning
        let installDownloadableMediaWindow: @MainActor (
            PlayerDownloadableMediaWindow,
            UUID
        ) -> Void

        init(
            makeViewingSessionTracker: @escaping @MainActor (
                String?
            ) -> any MobilePlaybackViewingSessionTracking,
            clearActiveMediaWindow: @escaping @MainActor (UUID) -> Void,
            cancelAllMediaDownloads: @escaping @MainActor () -> Void,
            makeCollectionBrowseImageSourcesCache:
                @escaping @MainActor () ->
                    MobileCollectionBrowseImageSourcesCache = {
                        MobileCollectionBrowseImageSourcesCache()
                    },
            makeCollectionBrowseThumbnailWindowPlanner:
                @escaping @MainActor (
                    MobileCollectionBrowseImageSourcesCache
                ) -> any MobileCollectionBrowseThumbnailWindowPlanning = {
                    MobileCollectionBrowseThumbnailWindowPlanner(
                        imageSourcesCache: $0
                    )
                },
            installDownloadableMediaWindow: @escaping @MainActor (
                PlayerDownloadableMediaWindow,
                UUID
            ) -> Void = {
                DownloadableMediaCache.shared.prepareWindow($0, ownerId: $1)
            }
        ) {
            self.makeViewingSessionTracker = makeViewingSessionTracker
            self.clearActiveMediaWindow = clearActiveMediaWindow
            self.cancelAllMediaDownloads = cancelAllMediaDownloads
            self.makeCollectionBrowseImageSourcesCache =
                makeCollectionBrowseImageSourcesCache
            self.makeCollectionBrowseThumbnailWindowPlanner =
                makeCollectionBrowseThumbnailWindowPlanner
            self.installDownloadableMediaWindow =
                installDownloadableMediaWindow
        }

        fileprivate static let live = Dependencies(
            makeViewingSessionTracker: {
                PlayerViewingSessionTracker(continueViewingCollectionId: $0)
            },
            clearActiveMediaWindow: {
                DownloadableMediaCache.shared.clearActiveWindow(ownerId: $0)
            },
            cancelAllMediaDownloads: {
                DownloadableMediaCache.shared.cancelAllDownloads()
            }
        )
    }

    private let dependencies: Dependencies
    private var activeSessions = [ObjectIdentifier: MobilePlaybackSession]()

    var activeSessionCount: Int {
        activeSessions.count
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func startSession(config: MobilePlayerConfig) -> MobilePlaybackSession {
        let imageSourcesCache =
            dependencies.makeCollectionBrowseImageSourcesCache()
        let thumbnailWindowPlanner:
            any MobileCollectionBrowseThumbnailWindowPlanning =
                dependencies.makeCollectionBrowseThumbnailWindowPlanner(
                    imageSourcesCache
                )
        let session = MobilePlaybackSession(
            config: config,
            viewingSessionTracker: dependencies.makeViewingSessionTracker(
                config.continueViewingCollectionId
            ),
            collectionBrowseImageSourcesCache: imageSourcesCache,
            collectionBrowseThumbnailWindowPlanner:
                thumbnailWindowPlanner,
            installDownloadableMediaWindow:
                dependencies.installDownloadableMediaWindow
        ) { [weak self] session in
            self?.disconnect(session)
        }
        activeSessions[ObjectIdentifier(session)] = session
        return session
    }

    private func disconnect(_ session: MobilePlaybackSession) {
        let identity = ObjectIdentifier(session)
        guard activeSessions[identity] === session else { return }
        activeSessions.removeValue(forKey: identity)
        if activeSessions.isEmpty {
            dependencies.cancelAllMediaDownloads()
        } else {
            dependencies.clearActiveMediaWindow(session.mediaWindowOwnerID)
        }
    }
}

@MainActor
final class MobilePlaybackController {

    static let shared = MobilePlaybackController()

    private let registry = MobilePlaybackSessionRegistry(dependencies: .live)

    private init() {}

    func startSession(config: MobilePlayerConfig) -> MobilePlaybackSession {
        registry.startSession(config: config)
    }
}

enum MobilePlayerPrewarmer {

    static func scheduleAfterLaunch(continueViewingProgress: MobileViewingProgress?, initialCollectionIds: [String]) {
        AutoReloadingWebView.scheduleFirstUsePrewarm()
        PlayerTokenPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: initialCollectionIds
        )
    }

    static func preparedConfig(
        initialItemId: String?,
        initialTokenId: String? = nil,
        initialTokenIndex: Int? = nil,
        continueViewingCollectionId: String?,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil
    ) -> MobilePlayerConfig {
        var config = MobilePlayerConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            initialTokenIndex: initialTokenIndex,
            continueViewingCollectionId: continueViewingCollectionId,
            widgetTokenInsertion: widgetTokenInsertion
        )
        if widgetTokenInsertion == nil {
            config.specificToken = PlayerTokenPrewarmer.preparedToken(
                initialCollectionId: initialItemId,
                initialTokenId: initialTokenId
            )
        }
        return config
    }
}
