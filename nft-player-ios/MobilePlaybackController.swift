// ∅ 2026 lil org

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

nonisolated struct MobileCollectionBrowseImageSourcesCache: Sendable {
    private struct CacheIdentity: Equatable, Sendable {
        let collectionId: String
        let itemCount: Int
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
        var lessRecentTokenIndex: Int?
        var moreRecentTokenIndex: Int?
    }

    private let maximumCachedImageSourceCount: Int
    private let imageSourcesResolver: @Sendable (
        PlayerCollectionBrowseSnapshot,
        Int
    ) -> CollectionBrowseImageSources?
    private var cacheIdentity: CacheIdentity?
    private var cachedImageSourcesByTokenIndex = [
        Int: CachedImageSourcesEntry
    ]()
    private var leastRecentTokenIndex: Int?
    private var mostRecentTokenIndex: Int?

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

    mutating func updateSnapshot(
        _ snapshot: PlayerCollectionBrowseSnapshot?
    ) {
        let identity = snapshot.map {
            CacheIdentity(
                collectionId: $0.collectionId,
                itemCount: $0.itemCount
            )
        }
        guard cacheIdentity != identity else { return }
        cacheIdentity = identity
        cachedImageSourcesByTokenIndex.removeAll(keepingCapacity: true)
        leastRecentTokenIndex = nil
        mostRecentTokenIndex = nil
    }

    mutating func imageSources(
        snapshot: PlayerCollectionBrowseSnapshot?,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        updateSnapshot(snapshot)
        guard let snapshot,
              snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return nil
        }
        if let cached = cachedImageSourcesByTokenIndex[tokenIndex] {
            markImageSourcesAsMostRecent(tokenIndex: tokenIndex)
            return cached.imageSources.value
        }
        let resolved = imageSourcesResolver(snapshot, tokenIndex)
        let cachedImageSources: CachedImageSources = resolved.map {
            .available($0)
        } ?? .unavailable
        insertImageSources(
            cachedImageSources,
            tokenIndex: tokenIndex
        )
        return resolved
    }

    var cachedImageSourceCount: Int {
        cachedImageSourcesByTokenIndex.count
    }

    private mutating func insertImageSources(
        _ imageSources: CachedImageSources,
        tokenIndex: Int
    ) {
        if cachedImageSourcesByTokenIndex.count
            >= maximumCachedImageSourceCount {
            evictLeastRecentImageSources()
        }
        cachedImageSourcesByTokenIndex[tokenIndex] = CachedImageSourcesEntry(
            imageSources: imageSources,
            lessRecentTokenIndex: mostRecentTokenIndex,
            moreRecentTokenIndex: nil
        )
        if let mostRecentTokenIndex {
            cachedImageSourcesByTokenIndex[mostRecentTokenIndex]?
                .moreRecentTokenIndex = tokenIndex
        } else {
            leastRecentTokenIndex = tokenIndex
        }
        mostRecentTokenIndex = tokenIndex
    }

    private mutating func markImageSourcesAsMostRecent(tokenIndex: Int) {
        guard tokenIndex != mostRecentTokenIndex,
              var entry = cachedImageSourcesByTokenIndex[tokenIndex] else {
            return
        }
        if let lessRecentTokenIndex = entry.lessRecentTokenIndex {
            cachedImageSourcesByTokenIndex[lessRecentTokenIndex]?
                .moreRecentTokenIndex = entry.moreRecentTokenIndex
        } else {
            leastRecentTokenIndex = entry.moreRecentTokenIndex
        }
        if let moreRecentTokenIndex = entry.moreRecentTokenIndex {
            cachedImageSourcesByTokenIndex[moreRecentTokenIndex]?
                .lessRecentTokenIndex = entry.lessRecentTokenIndex
        }
        entry.lessRecentTokenIndex = mostRecentTokenIndex
        entry.moreRecentTokenIndex = nil
        if let mostRecentTokenIndex {
            cachedImageSourcesByTokenIndex[mostRecentTokenIndex]?
                .moreRecentTokenIndex = tokenIndex
        }
        cachedImageSourcesByTokenIndex[tokenIndex] = entry
        mostRecentTokenIndex = tokenIndex
    }

    private mutating func evictLeastRecentImageSources() {
        guard let tokenIndex = leastRecentTokenIndex,
              let entry = cachedImageSourcesByTokenIndex.removeValue(
                forKey: tokenIndex
              ) else {
            return
        }
        leastRecentTokenIndex = entry.moreRecentTokenIndex
        if let leastRecentTokenIndex {
            cachedImageSourcesByTokenIndex[leastRecentTokenIndex]?
                .lessRecentTokenIndex = nil
        } else {
            mostRecentTokenIndex = nil
        }
    }
}

actor MobileCollectionBrowseThumbnailWindowPlanner:
    MobileCollectionBrowseThumbnailWindowPlanning {
    private var imageSourcesCache: MobileCollectionBrowseImageSourcesCache

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
        imageSourcesCache = MobileCollectionBrowseImageSourcesCache(
            maximumCachedImageSourceCount: maximumCachedImageSourceCount,
            imageSourcesResolver: imageSourcesResolver
        )
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
        return imageSourcesCache.imageSources(
            snapshot: snapshot,
            tokenIndex: tokenIndex
        )
    }

#if DEBUG
    func imageSourcesForTesting(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        return imageSources(snapshot: snapshot, tokenIndex: tokenIndex)
    }

    var cachedImageSourceCountForTesting: Int {
        imageSourcesCache.cachedImageSourceCount
    }
#endif
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
        (@MainActor (Bool) -> Void)?
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
        collectionBrowseThumbnailWindowPlanner:
            any MobileCollectionBrowseThumbnailWindowPlanning =
                MobileCollectionBrowseThumbnailWindowPlanner(),
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
        lifecycleState = .disconnected
        disconnect(self)
        thumbnailWindowCompletion?(false)
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
        completion?(false)
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
            completion?(false)
            return nil
        }
        Self.collectionBrowseThumbnailWindowPreparationOrder
            .supersedePendingClaims()

        installDownloadableMediaWindow(window, mediaWindowOwnerID)
        completion?(false)
        return window
    }

    @discardableResult
    func prepareCollectionBrowseThumbnailWindow(
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
        completion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> Task<Void, Never>? {
        guard lifecycleState == .active else {
            completion(false)
            return nil
        }
        let supersededCompletion =
            detachPendingCollectionBrowseThumbnailWindowPreparation()
        guard let snapshot = collectionBrowseSnapshot() else {
            DownloadableMediaCache.shared.clearActiveWindow(
                ownerId: mediaWindowOwnerID
            )
            supersededCompletion?(false)
            completion(false)
            return nil
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
        let preparationTask = Task {
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
                  self.lifecycleState == .active,
                  self.collectionBrowseSnapshot() == snapshot,
                  shouldApply() else {
                completion?(false)
                return
            }
            guard let preparedWindow else {
                DownloadableMediaCache.shared.clearActiveWindow(
                    ownerId: self.mediaWindowOwnerID
                )
                completion?(false)
                return
            }
            guard Self.collectionBrowseThumbnailWindowPreparationOrder
                .commitIfNewer(claim) else {
                completion?(false)
                return
            }
            self.installDownloadableMediaWindow(
                preparedWindow,
                self.mediaWindowOwnerID
            )
            completion?(true)
        }
        collectionBrowseThumbnailWindowPreparationTask = preparationTask
        supersededCompletion?(false)
        return preparationTask
    }

    func cancelPendingCollectionBrowseThumbnailWindowPreparation() {
        let completion =
            detachPendingCollectionBrowseThumbnailWindowPreparation()
        completion?(false)
    }

    private func detachPendingCollectionBrowseThumbnailWindowPreparation()
        -> (@MainActor (Bool) -> Void)? {
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
        let makeCollectionBrowseThumbnailWindowPlanner:
            @MainActor () ->
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
            makeCollectionBrowseThumbnailWindowPlanner:
                @escaping @MainActor () ->
                    any MobileCollectionBrowseThumbnailWindowPlanning = {
                        MobileCollectionBrowseThumbnailWindowPlanner()
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
        let session = MobilePlaybackSession(
            config: config,
            viewingSessionTracker: dependencies.makeViewingSessionTracker(
                config.continueViewingCollectionId
            ),
            collectionBrowseThumbnailWindowPlanner:
                dependencies.makeCollectionBrowseThumbnailWindowPlanner(),
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
