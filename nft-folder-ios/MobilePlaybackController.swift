// ∅ 2026 lil org

import UIKit

protocol MobilePlaybackControllerDisplay: AnyObject {
    
    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentCoordinate() -> (Int, Int)
    
}

enum PlaybackNavigationDirection {
    case up, down, back, forward, nextCollection, restartCollection
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
            DownloadableMediaCache.shared.cancelAllDownloads()
        }
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
    ) -> (collectionId: String, tokenIndex: Int, tokenCount: Int)? {
        guard let dataSource = dataSource(uuid: uuid) else { return nil }
        return downloadableCollectionTokenContext(dataSource: dataSource, coordinate: coordinate)
    }

    private func downloadableCollectionTokenContext(
        dataSource: GeneratedTokensDataSource,
        coordinate: PlayerCoordinate
    ) -> (collectionId: String, tokenIndex: Int, tokenCount: Int)? {
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
