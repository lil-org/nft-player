// ∅ 2026 lil org

import UIKit

protocol MobilePlaybackControllerDisplay: AnyObject {

    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentCoordinate() -> (Int, Int)

}

struct MobilePlayerFileShareItem {
    let fileURL: URL
    let previewTitle: String
    let previewImage: () -> UIImage?
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
            baseTitle = Strings.nftFolder
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
            DownloadableMediaCache.shared.cancelAllDownloads()
        } else {
            clearDownloadableMediaWindow(uuid: uuid)
        }
    }

    func clearDownloadableMediaWindow(uuid: UUID) {
        DownloadableMediaCache.shared.clearActiveWindow(ownerId: uuid)
    }
    
    func getToken(uuid: UUID, coordinate: PlayerCoordinate) -> GeneratedToken {
        dataSource(uuid: uuid)?.getToken(coordinate: coordinate) ?? .empty
    }

    func canRender(uuid: UUID, coordinate: PlayerCoordinate) -> Bool {
        dataSource(uuid: uuid)?.canRender(coordinate: coordinate) ?? false
    }

    func prepareDownloadableMediaWindow(
        uuid: UUID,
        coordinate: PlayerCoordinate,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> DownloadableMediaDescriptor? {
        guard let context = downloadableCollectionTokenContext(uuid: uuid, coordinate: coordinate) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }

        let descriptors = DownloadableMediaCache.windowDescriptors(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
        DownloadableMediaCache.shared.prepareWindow(
            collectionId: context.collectionId,
            ownerId: uuid,
            currentTokenIndex: context.tokenIndex,
            descriptors: descriptors,
            direction: direction
        )
        return descriptors.first { $0.tokenIndex == context.tokenIndex }
    }

    func downloadableMediaDescriptor(uuid: UUID, coordinate: PlayerCoordinate) -> DownloadableMediaDescriptor? {
        guard let context = downloadableCollectionTokenContext(uuid: uuid, coordinate: coordinate) else {
            return nil
        }

        return MobileCollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func adjacentDownloadableMediaDescriptor(
        uuid: UUID,
        coordinate: PlayerCoordinate,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> DownloadableMediaDescriptor? {
        guard let context = downloadableCollectionTokenContext(uuid: uuid, coordinate: coordinate) else {
            return nil
        }

        return DownloadableMediaCache.adjacentDescriptor(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
    }

    private func downloadableCollectionTokenContext(
        uuid: UUID,
        coordinate: PlayerCoordinate
    ) -> PlayerTokenContext? {
        guard let dataSource = dataSource(uuid: uuid) else { return nil }
        return downloadableCollectionTokenContext(dataSource: dataSource, coordinate: coordinate)
    }

    private func downloadableCollectionTokenContext(
        dataSource: PlayerTokenPagingDataSource,
        coordinate: PlayerCoordinate
    ) -> PlayerTokenContext? {
        guard let context = dataSource.collectionTokenContext(coordinate: coordinate),
              MobileCollectionCatalog.isDownloadableCollection(specificCollectionId: context.collectionId) else {
            return nil
        }
        return context
    }

    func markViewed(uuid: UUID, coordinate: PlayerCoordinate) -> MobileViewingProgress? {
        guard let progress = dataSource(uuid: uuid)?.progress(coordinate: coordinate) else { return nil }
        MobileViewingProgressStore.save(progress)
        updateContinueViewingCollection(for: progress, uuid: uuid)
        return progress
    }

    func downloadedFileShareItem(uuid: UUID, coordinate: PlayerCoordinate) -> MobilePlayerFileShareItem? {
        guard let dataSource = dataSource(uuid: uuid),
              let context = downloadableCollectionTokenContext(dataSource: dataSource, coordinate: coordinate),
              let descriptor = MobileCollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: context.tokenIndex
              ) else {
            return nil
        }

        guard let fileURL = DownloadableMediaCache.shared.localFileURL(for: descriptor) else { return nil }
        let token = dataSource.getToken(coordinate: coordinate)
        return MobilePlayerFileShareItem(
            fileURL: fileURL,
            previewTitle: MobilePlayerFileShareItem.previewTitle(
                for: token,
                progressText: Strings.pagePosition(current: context.tokenIndex + 1, total: context.tokenCount)
            )
        ) {
            DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor)
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

        MobileViewingProgressStore.updateContinueViewingCollection(
            for: progress,
            expectedCollectionId: initialConfigs[uuid]?.continueViewingCollectionId
        )
    }

    private func suppressContinueViewingUntilMovementAfterRestart(uuid: UUID) {
        guard let coordinate = displays[uuid]?.getCurrentCoordinate(),
              let progress = dataSource(uuid: uuid)?.progress(coordinate: PlayerCoordinate(x: coordinate.0, y: coordinate.1)) else {
            restartSuppressedCollectionIds.removeValue(forKey: uuid)
            return
        }

        restartSuppressedCollectionIds[uuid] = progress.collectionId
        MobileViewingProgressStore.recordContinueViewingClearedForSync()
    }

    func startHorizontalCoordinate(uuid: UUID, verticalIndex: Int) -> Int {
        dataSource(uuid: uuid)?.horizontalCoordinateForTokenIndex(0, verticalIndex: verticalIndex) ?? 0
    }

    private func dataSource(uuid: UUID) -> PlayerTokenPagingDataSource? {
        guard let initialConfig = initialConfigs[uuid] else { return nil }
        if let dataSource = tokensDataSources[uuid] {
            return dataSource
        }

        let newDataSource = PlayerTokenPagingDataSource(
            initialCollectionId: initialConfig.initialItemId,
            specificInitialToken: initialConfig.specificToken,
            initialTokenId: initialConfig.initialTokenId
        )
        tokensDataSources[uuid] = newDataSource
        return newDataSource
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
        continueViewingCollectionId: String?
    ) -> MobilePlayerConfig {
        var config = MobilePlayerConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId
        )
        config.specificToken = PlayerTokenPrewarmer.preparedToken(
            initialCollectionId: initialItemId,
            initialTokenId: initialTokenId
        )
        return config
    }
}
