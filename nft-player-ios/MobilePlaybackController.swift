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
        releaseFile: @escaping () -> Void,
        previewImage: @escaping () -> UIImage?
    ) {
        self.fileURL = fileURL
        self.previewTitle = previewTitle
        self.previewImage = previewImage
        self.retainedFile = MobilePlayerFileShareRetainedFile(releaseFile: releaseFile)
    }
}

private final class MobilePlayerFileShareRetainedFile {
    private let releaseFile: () -> Void

    init(releaseFile: @escaping () -> Void) {
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
    
    func goForward(uuid: UUID) {
        navigate(.forward, uuid: uuid)
    }
    
    func goBack(uuid: UUID) {
        navigate(.back, uuid: uuid)
    }

    func restartCollection(uuid: UUID) {
        dataSource(uuid: uuid)?.acknowledgeIntentionalViewingPosition()
        suppressContinueViewingUntilMovementAfterRestart(uuid: uuid)
        navigate(.restartCollection, uuid: uuid)
    }

    private func navigate(_ direction: PlaybackNavigationDirection, uuid: UUID) {
        displays[uuid]?.navigate(direction)
    }
    
    func subscribe(config: MobilePlayerConfig, display: MobilePlaybackControllerDisplay) {
        displays[config.id] = display
        initialConfigs[config.id] = config
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

    func collectionBrowseGridMode(
        snapshot: PlayerCollectionBrowseSnapshot
    ) -> MobileCollectionBrowserGridMode {
        MobileCollectionBrowserGridModeStore.gridMode(
            specificCollectionId: snapshot.collectionId
        )
    }

    func saveCollectionBrowseGridMode(
        _ gridMode: MobileCollectionBrowserGridMode,
        snapshot: PlayerCollectionBrowseSnapshot
    ) {
        MobileCollectionBrowserGridModeStore.save(
            gridMode: gridMode,
            specificCollectionId: snapshot.collectionId
        )
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
        quality: CollectionBrowseImageQuality,
        displayedLargeTokenIndices: Set<Int>,
        locallyAvailableLargeTokenIndices: Set<Int>
    ) -> PlayerDownloadableMediaWindow? {
        guard let snapshot = collectionBrowseSnapshot(uuid: uuid),
              let preparedWindow = PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: tokenIndex,
                itemCount: snapshot.itemCount,
                direction: direction,
                prefetchStride: prefetchStride,
                descriptorForTokenIndex: {
                    let selection = CollectionBrowseImageWindowSelection.resolve(
                        requiredQuality: quality,
                        isDisplayingLargeImage:
                            displayedLargeTokenIndices.contains($0),
                        largeImageIsLocallyAvailable:
                            locallyAvailableLargeTokenIndices.contains($0)
                    )
                    switch selection {
                    case .requestedQuality:
                        return collectionBrowseImageDescriptor(
                            snapshot: snapshot,
                            tokenIndex: $0,
                            quality: quality
                        )
                    case .locallyAvailableLarge:
                        return collectionBrowseImageDescriptor(
                            snapshot: snapshot,
                            tokenIndex: $0,
                            quality: .large
                        )
                    case .omitSatisfiedToken:
                        return nil
                    }
                }
              ) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }
        DownloadableMediaCache.shared.prepareWindow(preparedWindow, ownerId: uuid)
        return preparedWindow
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
        updateViewingSessionTracker(uuid: uuid) { tracker in
            tracker.markViewed(progress)
        }
        return progress
    }

    func acknowledgeIntentionalViewingPosition(uuid: UUID) {
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

    private func suppressContinueViewingUntilMovementAfterRestart(uuid: UUID) {
        let collectionId: String?
        if let pagePosition = displays[uuid]?.getCurrentPagePosition() {
            collectionId = dataSource(uuid: uuid)?.collectionTokenContext(pagePosition: pagePosition)?.collectionId
        } else {
            collectionId = nil
        }

        updateViewingSessionTracker(uuid: uuid) { tracker in
            tracker.beginRestart(collectionId: collectionId)
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

    private func updateViewingSessionTracker<T>(
        uuid: UUID,
        _ update: (inout PlayerViewingSessionTracker) -> T
    ) -> T {
        var tracker = viewingSessionTracker(uuid: uuid)
        let result = update(&tracker)
        viewingSessionTrackers[uuid] = tracker
        return result
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
