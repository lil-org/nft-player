// ∅ 2026 lil org

import UIKit

protocol MobilePlaybackControllerDisplay: AnyObject {

    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentPagePosition() -> PlayerPagePosition
    func flushPendingViewingProgress()

}

struct MobilePlayerFileShareItem {
    let fileURL: URL
    let previewTitle: String
    let previewImage: () -> UIImage?
    private let retainedFile: MobilePlayerFileShareRetainedFile

    init(
        fileURL: URL,
        previewTitle: String,
        releaseFile: @escaping @Sendable () -> Void,
        previewImage: @escaping () -> UIImage?
    ) {
        self.fileURL = fileURL
        self.previewTitle = previewTitle
        self.previewImage = previewImage
        self.retainedFile = MobilePlayerFileShareRetainedFile(releaseFile: releaseFile)
    }
}

private final class MobilePlayerFileShareRetainedFile {
    private let releaseFile: @Sendable () -> Void

    init(releaseFile: @escaping @Sendable () -> Void) {
        self.releaseFile = releaseFile
    }

    deinit {
        releaseFile()
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

class MobilePlaybackController {
    
    private init() {}
    
    static let shared = MobilePlaybackController()
    
    private var displays = [UUID: MobilePlaybackControllerDisplay]()
    private var initialConfigs = [UUID: MobilePlayerConfig]()
    private var tokensDataSources = [UUID: PlayerTokenPagingDataSource]()
    private var viewingSessionTrackers = [UUID: PlayerViewingSessionTracker]()
    private var navigationRequestGenerations = [UUID: UInt]()
    
    func goForward(uuid: UUID) {
        advanceNavigationRequestGeneration(uuid: uuid)
        navigate(.forward, uuid: uuid)
    }
    
    func goBack(uuid: UUID) {
        advanceNavigationRequestGeneration(uuid: uuid)
        navigate(.back, uuid: uuid)
    }

    func restartCollection(uuid: UUID) {
        guard let display = displays[uuid] else { return }
        let requestGeneration = advanceNavigationRequestGeneration(uuid: uuid)
        let startingPagePosition = display.getCurrentPagePosition()
        dataSource(uuid: uuid)?.acknowledgeIntentionalViewingPosition()
        let collectionId = dataSource(uuid: uuid)?
            .collectionTokenContext(pagePosition: startingPagePosition)?.collectionId
        let tracker = viewingSessionTracker(uuid: uuid)
        Task {
            let update = await tracker.prepareRestartUpdate(collectionId: collectionId)
            guard navigationRequestGenerations[uuid] == requestGeneration,
                  viewingSessionTrackers[uuid] === tracker,
                  let currentDisplay = displays[uuid],
                  currentDisplay.getCurrentPagePosition() == startingPagePosition else {
                return
            }
            PlayerPersistenceUpdates.enqueue {
                await tracker.beginRestart(update: update)
            }
            navigate(.restartCollection, uuid: uuid)
        }
    }

    private func navigate(_ direction: PlaybackNavigationDirection, uuid: UUID) {
        displays[uuid]?.navigate(direction)
    }

    func cancelPendingCollectionRestart(uuid: UUID) {
        advanceNavigationRequestGeneration(uuid: uuid)
    }

    @discardableResult
    private func advanceNavigationRequestGeneration(uuid: UUID) -> UInt {
        let generation = (navigationRequestGenerations[uuid] ?? 0) &+ 1
        navigationRequestGenerations[uuid] = generation
        return generation
    }
    
    func subscribe(config: MobilePlayerConfig, display: MobilePlaybackControllerDisplay) {
        displays[config.id] = display
        initialConfigs[config.id] = config
        navigationRequestGenerations[config.id] = 0
        viewingSessionTrackers[config.id] = PlayerViewingSessionTracker(
            continueViewingCollectionId: config.continueViewingCollectionId
        )
    }
    
    func stopAndDisconnect(uuid: UUID) {
        displays[uuid]?.flushPendingViewingProgress()
        displays.removeValue(forKey: uuid)
        initialConfigs.removeValue(forKey: uuid)
        tokensDataSources.removeValue(forKey: uuid)
        viewingSessionTrackers.removeValue(forKey: uuid)
        navigationRequestGenerations.removeValue(forKey: uuid)
        if displays.isEmpty {
            DownloadableMediaCache.shared.cancelAllDownloads()
        } else {
            clearDownloadableMediaWindow(uuid: uuid)
        }
    }

    func clearDownloadableMediaWindow(uuid: UUID) {
        DownloadableMediaCache.shared.clearActiveWindow(ownerId: uuid)
    }
    
    func getToken(uuid: UUID, pagePosition: PlayerPagePosition) -> GeneratedToken {
        dataSource(uuid: uuid)?.getToken(pagePosition: pagePosition) ?? .empty
    }

    func canRender(uuid: UUID, pagePosition: PlayerPagePosition) -> Bool {
        dataSource(uuid: uuid)?.canRender(pagePosition: pagePosition) ?? false
    }

    func pageLabel(uuid: UUID, pagePosition: PlayerPagePosition) -> String? {
        dataSource(uuid: uuid)?.pageLabel(pagePosition: pagePosition)
    }

    func isInsertedWidgetToken(uuid: UUID, pagePosition: PlayerPagePosition) -> Bool {
        dataSource(uuid: uuid)?.isInsertedWidgetToken(pagePosition: pagePosition) ?? false
    }

    func collectionBrowseSnapshot(uuid: UUID) -> PlayerCollectionBrowseSnapshot? {
        dataSource(uuid: uuid)?.collectionBrowseSnapshot()
    }

    func prepareCollectionBrowse(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition
    ) -> PlayerCollectionBrowsePreparation? {
        dataSource(uuid: uuid)?.prepareCollectionBrowse(containing: pagePosition)
    }

    func commitCollectionBrowse(
        uuid: UUID,
        preparation: PlayerCollectionBrowsePreparation
    ) -> PlayerCollectionBrowsePositionResolution {
        dataSource(uuid: uuid)?.commitCollectionBrowse(preparation) ?? .unavailable
    }

    func collectionBrowseThumbnailDescriptor(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> DownloadableMediaDescriptor? {
        guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else { return nil }

        return MobileCollectionCatalog.collectionBrowseThumbnailDescriptor(
            specificCollectionId: snapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    func collectionBrowseImageSources(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else { return nil }

        return MobileCollectionCatalog.collectionBrowseImageSources(
            specificCollectionId: snapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    func collectionBrowseImageDescriptor(
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

    func collectionBrowsePrefetchDescriptor(
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

    func collectionBrowseThumbnailAspectRatioProfile(
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

    func collectionBrowseThumbnailDescriptor(
        uuid: UUID,
        pagePosition: PlayerPagePosition
    ) -> DownloadableMediaDescriptor? {
        guard let context = collectionTokenContext(uuid: uuid, pagePosition: pagePosition) else {
            return nil
        }

        return MobileCollectionCatalog.collectionBrowseThumbnailDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func layoutInteractionState(
        uuid: UUID,
        displayMode: MobilePlayerDisplayMode,
        pagePosition: PlayerPagePosition?,
        collectionBrowserAvailable expectedCollectionBrowserAvailability: Bool? = nil
    ) -> MobilePlayerLayoutInteractionState {
        let currentDescriptor = pagePosition.flatMap {
            collectionBrowseThumbnailDescriptor(uuid: uuid, pagePosition: $0)
                ?? downloadableMediaDescriptor(uuid: uuid, pagePosition: $0)
        }
        let collectionBrowserAvailable = expectedCollectionBrowserAvailability
            ?? PlayerCollectionBrowserSupport.isAvailable(for: currentDescriptor)
        guard let pagePosition,
              collectionTokenContext(
                uuid: uuid,
                pagePosition: pagePosition
              ) != nil,
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
            browserSwitchMode: isInsertedWidgetToken(uuid: uuid, pagePosition: pagePosition)
                ? .offscreenInsertion
                : .animated
        )
    }

    func prepareDownloadableMediaWindow(
        uuid: UUID,
        pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        guard let window = dataSource(uuid: uuid)?.downloadableMediaWindow(
            pagePosition: pagePosition,
            direction: direction
        ) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }

        DownloadableMediaCache.shared.prepareWindow(window, ownerId: uuid)
        return window
    }

    func prepareCollectionBrowseThumbnailWindow(
        uuid: UUID,
        centeredAt tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        prefetchStride: Int,
        columnCount: Int,
        quality: CollectionBrowseImageQuality,
        requiredTokenRange: ClosedRange<Int>?,
        displayedHigherQualityThumbnailTokenIndices: Set<Int>,
        displayedLargeTokenIndices: Set<Int>,
        locallyAvailableLargeTokenIndices: Set<Int>
    ) {
        guard let snapshot = collectionBrowseSnapshot(uuid: uuid) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return
        }
        let compactCoverage = Self.collectionBrowseCompactCoverage(
            imageSources: collectionBrowseImageSources(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            ),
            centeredAt: tokenIndex,
            direction: direction,
            itemCount: snapshot.itemCount,
            columnCount: columnCount,
            prefetchStride: prefetchStride,
            quality: quality,
            requiredTokenRange: requiredTokenRange
        )
        guard let preparedWindow = PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: tokenIndex,
                itemCount: snapshot.itemCount,
                direction: direction,
                prefetchStride: prefetchStride,
                compactCoverage: compactCoverage,
                descriptorForTokenIndex: { candidateTokenIndex in
                    let selection = CollectionBrowseImageWindowSelection.resolve(
                        requiredQuality: quality,
                        isDisplayingSatisfyingThumbnail:
                            displayedHigherQualityThumbnailTokenIndices.contains(
                                candidateTokenIndex
                            ),
                        isDisplayingLargeImage:
                            displayedLargeTokenIndices.contains(
                                candidateTokenIndex
                            ),
                        largeImageIsLocallyAvailable:
                            locallyAvailableLargeTokenIndices.contains(
                                candidateTokenIndex
                            )
                    )
                    switch selection {
                    case .requestedQuality:
                        return collectionBrowseImageDescriptor(
                            snapshot: snapshot,
                            tokenIndex: candidateTokenIndex,
                            quality: quality
                        )
                    case .locallyAvailableLarge:
                        return collectionBrowseImageDescriptor(
                            snapshot: snapshot,
                            tokenIndex: candidateTokenIndex,
                            quality: .large
                        )
                    case .omitSatisfiedToken:
                        return nil
                    }
                }
              ) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return
        }
        DownloadableMediaCache.shared.prepareWindow(preparedWindow, ownerId: uuid)
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

    func downloadableMediaDescriptor(uuid: UUID, pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor? {
        guard let context = downloadableMediaTokenContext(uuid: uuid, pagePosition: pagePosition) else {
            return nil
        }

        return MobileCollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func hasNavigationDestination(
        uuid: UUID,
        from pagePosition: PlayerPagePosition,
        direction: PlaybackNavigationDirection
    ) -> Bool {
        guard let targetOffset = direction.pageOffset else { return false }

        return canRender(uuid: uuid, pagePosition: pagePosition.advanced(by: targetOffset))
    }

    private func downloadableMediaTokenContext(
        uuid: UUID,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let dataSource = dataSource(uuid: uuid) else { return nil }
        return downloadableMediaTokenContext(dataSource: dataSource, pagePosition: pagePosition)
    }

    private func collectionTokenContext(
        uuid: UUID,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        dataSource(uuid: uuid)?.collectionTokenContext(pagePosition: pagePosition)
    }

    private func downloadableMediaTokenContext(
        dataSource: PlayerTokenPagingDataSource,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let context = dataSource.collectionTokenContext(pagePosition: pagePosition),
              MobileCollectionCatalog.hasDownloadableMediaDescriptor(specificCollectionId: context.collectionId) else {
            return nil
        }
        return context
    }

    func markViewed(
        uuid: UUID,
        pagePosition: PlayerPagePosition,
        hasViewedToEnd: Bool = false
    ) -> MobileViewingProgress? {
        guard let dataSource = dataSource(uuid: uuid),
              let progress = dataSource.progress(
                  pagePosition: pagePosition,
                  hasViewedToEnd: hasViewedToEnd
              ) else {
            return nil
        }
        let tracker = viewingSessionTracker(uuid: uuid)
        PlayerPersistenceUpdates.enqueue {
            await tracker.markViewed(progress)
        }
        return progress
    }

    func acknowledgeIntentionalViewingPosition(uuid: UUID) {
        advanceNavigationRequestGeneration(uuid: uuid)
        dataSource(uuid: uuid)?.acknowledgeIntentionalViewingPosition()
    }

    func progress(
        uuid: UUID,
        pagePosition: PlayerPagePosition,
        resolvedToken: GeneratedToken
    ) -> MobileViewingProgress? {
        dataSource(uuid: uuid)?.progress(
            pagePosition: pagePosition,
            resolvedToken: resolvedToken
        )
    }

    func downloadedFileShareItem(uuid: UUID, pagePosition: PlayerPagePosition) -> MobilePlayerFileShareItem? {
        guard let dataSource = dataSource(uuid: uuid),
              let context = downloadableMediaTokenContext(dataSource: dataSource, pagePosition: pagePosition),
              let descriptor = MobileCollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: context.tokenIndex
              ) else {
            return nil
        }

        let releaseFile = DownloadableMediaCache.shared.retainFile(for: descriptor)
        guard let fileURL = DownloadableMediaCache.shared.localFileURL(for: descriptor) else {
            releaseFile()
            return nil
        }
        let token = dataSource.getToken(pagePosition: pagePosition)
        return MobilePlayerFileShareItem(
            fileURL: fileURL,
            previewTitle: MobilePlayerFileShareItem.previewTitle(
                for: token,
                progressText: dataSource.pageLabel(pagePosition: pagePosition)
                    ?? Strings.pagePosition(current: context.tokenIndex + 1, total: context.tokenCount)
            ),
            releaseFile: releaseFile
        ) {
            DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor)
        }
    }

    func startPagePosition(uuid: UUID) -> PlayerPagePosition {
        dataSource(uuid: uuid)?.pagePosition(forTokenIndex: 0) ?? .initial
    }

    private func dataSource(uuid: UUID) -> PlayerTokenPagingDataSource? {
        guard let initialConfig = initialConfigs[uuid] else { return nil }
        if let dataSource = tokensDataSources[uuid] {
            return dataSource
        }

        let newDataSource = PlayerTokenPagingDataSource(
            initialCollectionId: initialConfig.initialItemId,
            specificInitialToken: initialConfig.specificToken,
            initialTokenId: initialConfig.initialTokenId,
            initialTokenIndex: initialConfig.initialTokenIndex,
            widgetTokenInsertion: initialConfig.widgetTokenInsertion
        )
        tokensDataSources[uuid] = newDataSource
        return newDataSource
    }

    private func viewingSessionTracker(uuid: UUID) -> PlayerViewingSessionTracker {
        if let tracker = viewingSessionTrackers[uuid] {
            return tracker
        }

        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: initialConfigs[uuid]?.continueViewingCollectionId
        )
        viewingSessionTrackers[uuid] = tracker
        return tracker
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
