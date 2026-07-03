// ∅ 2026 lil org

import UIKit

protocol MobilePlaybackControllerDisplay: AnyObject {

    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentPagePosition() -> PlayerPagePosition

}

struct MobilePlayerFileShareItem {
    let fileURL: URL
    let previewTitle: String
    let previewImage: () -> UIImage?
}

enum MobilePlayerPageLayout: CaseIterable, Hashable, Identifiable {
    case onePerPage
    case fourPerPage

    static let cardNftCollectionId = "HpGDYGz6aRUs5qbvp1dmWGKTicQctX4PixfcouAQDCHF"
    static let drifella2CollectionId = "7cHTjqr2S8uUCrG3TVFvFix3vcLjhPiwrtRsAeJtESRj"
    static let miladyAura2AfterDeathCollectionId = "0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d"

    private static let fourPerPageStaticImageCollectionIds = Set([
        cardNftCollectionId,
        drifella2CollectionId,
        miladyAura2AfterDeathCollectionId,
    ])

    static func initialLayout(for config: MobilePlayerConfig) -> MobilePlayerPageLayout {
        guard config.widgetTokenInsertion == nil else {
            return .onePerPage
        }

        guard Self.fourPerPage.supports(descriptor: initialDownloadableMediaDescriptor(for: config)) else {
            return .onePerPage
        }

        return .fourPerPage
    }

    var id: Self { self }

    var pageSize: Int {
        switch self {
        case .onePerPage:
            return 1
        case .fourPerPage:
            return 4
        }
    }

    static func isFourPerPageStaticImageCollection(_ collectionId: String) -> Bool {
        fourPerPageStaticImageCollectionIds.contains(collectionId)
    }

    static func fourPerPageFallbackImageSize(for descriptor: DownloadableMediaDescriptor) -> CGSize {
        switch descriptor.collectionId {
        case drifella2CollectionId:
            return CGSize(width: 1200, height: 1295)
        default:
            return CGSize(width: 1, height: 1)
        }
    }

    var title: String {
        switch self {
        case .onePerPage:
            return Strings.onePerPage
        case .fourPerPage:
            return Strings.fourPerPage
        }
    }

    func supports(descriptor: DownloadableMediaDescriptor?) -> Bool {
        switch self {
        case .onePerPage:
            return true
        case .fourPerPage:
            guard let descriptor,
                  descriptor.isStaticImage,
                  Self.isFourPerPageStaticImageCollection(descriptor.collectionId) else {
                return false
            }
            return true
        }
    }

    private static func initialDownloadableMediaDescriptor(for config: MobilePlayerConfig) -> DownloadableMediaDescriptor? {
        if let specificToken = config.specificToken {
            return CollectionCatalog.downloadableMediaDescriptor(
                for: CollectionCatalog.tokenContext(for: specificToken)
            )
        }

        guard let collectionId = config.initialItemId else { return nil }

        let tokenIndex: Int
        if let initialTokenId = config.initialTokenId {
            guard let requestedTokenIndex = CollectionCatalog.tokenIndex(
                specificCollectionId: collectionId,
                tokenId: initialTokenId
            ) else {
                return nil
            }
            tokenIndex = requestedTokenIndex
        } else {
            tokenIndex = 0
        }

        return CollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: collectionId,
            tokenIndex: tokenIndex
        )
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
            continueViewingCollectionId: config.continueViewingCollectionId,
            trackingMode: config.trackingMode
        )
    }
    
    func stopAndDisconnect(uuid: UUID) {
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

    func downloadableMediaDescriptor(uuid: UUID, pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor? {
        guard let context = downloadableCollectionTokenContext(uuid: uuid, pagePosition: pagePosition) else {
            return nil
        }

        return MobileCollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func supportsPageLayout(_ pageLayout: MobilePlayerPageLayout, uuid: UUID, pagePosition: PlayerPagePosition) -> Bool {
        pageLayout.supports(
            descriptor: downloadableMediaDescriptor(uuid: uuid, pagePosition: pagePosition)
        )
    }

    func stablePagePosition(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> PlayerPagePosition {
        dataSource(uuid: uuid)?.stablePagePosition(
            containing: pagePosition,
            pageSize: pageLayout.pageSize
        ) ?? pagePosition
    }

    func exitWidgetInsertionForStablePage(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> PlayerStablePagePositionResult {
        dataSource(uuid: uuid)?.exitWidgetInsertionForStablePage(
            containing: pagePosition,
            pageSize: pageLayout.pageSize
        ) ?? PlayerStablePagePositionResult(
            pagePosition: pagePosition,
            didExitWidgetInsertion: false
        )
    }

    func navigationStride(
        uuid: UUID,
        from pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> Int {
        guard pageLayout == .fourPerPage,
              supportsPageLayout(.fourPerPage, uuid: uuid, pagePosition: pagePosition) else {
            return MobilePlayerPageLayout.onePerPage.pageSize
        }

        return pageLayout.pageSize
    }

    func hasNavigationDestination(
        uuid: UUID,
        from pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        direction: PlaybackNavigationDirection
    ) -> Bool {
        guard direction.isPagingDirection else { return false }

        let stride = navigationStride(uuid: uuid, from: pagePosition, pageLayout: pageLayout)
        guard let targetOffset = direction.pageOffset(forStride: stride) else { return false }

        return canRender(uuid: uuid, pagePosition: pagePosition.advanced(by: targetOffset))
    }

    private func downloadableCollectionTokenContext(
        uuid: UUID,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let dataSource = dataSource(uuid: uuid) else { return nil }
        return downloadableCollectionTokenContext(dataSource: dataSource, pagePosition: pagePosition)
    }

    private func downloadableCollectionTokenContext(
        dataSource: PlayerTokenPagingDataSource,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let context = dataSource.collectionTokenContext(pagePosition: pagePosition),
              MobileCollectionCatalog.isDownloadableCollection(specificCollectionId: context.collectionId) else {
            return nil
        }
        return context
    }

    func markViewed(uuid: UUID, pagePosition: PlayerPagePosition) -> MobileViewingProgress? {
        guard let progress = dataSource(uuid: uuid)?.progress(pagePosition: pagePosition) else { return nil }
        updateViewingSessionTracker(uuid: uuid) { tracker in
            tracker.markViewed(progress)
        }
        return progress
    }

    func downloadedFileShareItem(uuid: UUID, pagePosition: PlayerPagePosition) -> MobilePlayerFileShareItem? {
        guard let dataSource = dataSource(uuid: uuid),
              let context = downloadableCollectionTokenContext(dataSource: dataSource, pagePosition: pagePosition),
              let descriptor = MobileCollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: context.tokenIndex
              ) else {
            return nil
        }

        guard let fileURL = DownloadableMediaCache.shared.localFileURL(for: descriptor) else { return nil }
        let token = dataSource.getToken(pagePosition: pagePosition)
        return MobilePlayerFileShareItem(
            fileURL: fileURL,
            previewTitle: MobilePlayerFileShareItem.previewTitle(
                for: token,
                progressText: dataSource.pageLabel(pagePosition: pagePosition)
                    ?? Strings.pagePosition(current: context.tokenIndex + 1, total: context.tokenCount)
            )
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
            continueViewingCollectionId: initialConfigs[uuid]?.continueViewingCollectionId,
            trackingMode: initialConfigs[uuid]?.trackingMode ?? .updateContinueViewing
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
        continueViewingCollectionId: String?,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil
    ) -> MobilePlayerConfig {
        var config = MobilePlayerConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId,
            trackingMode: trackingMode,
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
