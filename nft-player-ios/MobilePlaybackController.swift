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

enum MobilePlayerDisplayMode: Hashable {
    case collectionBrowser
    case onePerPage

    static func initialMode(
        for config: MobilePlayerConfig,
        collectionBrowserAvailable: Bool
    ) -> MobilePlayerDisplayMode {
        guard config.widgetTokenInsertion == nil,
              collectionBrowserAvailable else {
            return .onePerPage
        }
        return .collectionBrowser
    }
}

enum MobilePlayerCollectionBrowserSupport {
    static let cardNftCollectionId = "HpGDYGz6aRUs5qbvp1dmWGKTicQctX4PixfcouAQDCHF"
    static let drifella2CollectionId = "7cHTjqr2S8uUCrG3TVFvFix3vcLjhPiwrtRsAeJtESRj"
    static let driladyCollectionId = "96THxzqE5yukFxzsqJaR2SrsLL2wJtuapi6827gkUD6T"
    static let johnCollectionId = "r1pCPYkbbpZWv7RCvuCMtpA3NSQY3fzVFo6HL43A4ot"
    static let miladyAura2AfterDeathCollectionId = "0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d"
    static let miladyAuraPetzCollectionId = "0xc62e3fd5b02618f90dd07d1e478963038fa9089c"
    static let superMetalMonsCollectionId = "0x17abd4cc1382397ec2b675f98621c3ba809897desmm"

    private static let explicitlySupportedCollectionIds: Set<String> = {
        var collectionIds: Set<String> = [
            cardNftCollectionId,
            drifella2CollectionId,
            driladyCollectionId,
            johnCollectionId,
            miladyAura2AfterDeathCollectionId,
            miladyAuraPetzCollectionId,
            superMetalMonsCollectionId,
        ]
        for renderKind in NativeMetalCardRenderKind.allCases {
            collectionIds.insert(renderKind.collectionId)
        }
        return collectionIds
    }()

    static func isAvailable(for descriptor: DownloadableMediaDescriptor?) -> Bool {
        guard let descriptor,
              descriptor.isStaticImage else {
            return false
        }

        if isAvailable(forCollectionId: descriptor.collectionId) {
            return true
        }

        return descriptor.isCollectionBrowserThumbnail
    }

    static func isAvailable(forCollectionId collectionId: String) -> Bool {
        if TokenGenerator.isBundledWebGenerativeCollection(id: collectionId) {
            return true
        }

        if explicitlySupportedCollectionIds.contains(collectionId) {
            return true
        }

        return MobileCollectionCatalog.standardThumbsPathsAvailable(
            specificCollectionId: collectionId
        )
    }

    static func isAvailable(for config: MobilePlayerConfig) -> Bool {
        guard let collectionId = config.specificToken?.fullCollectionId ?? config.initialItemId else {
            return false
        }
        return isAvailable(forCollectionId: collectionId)
    }

    static func fallbackImageSize(for descriptor: DownloadableMediaDescriptor) -> CGSize {
        if let thumbnailAspectRatio = descriptor.thumbnailAspectRatio {
            return thumbnailAspectRatio.size
        }

        if let renderKind = descriptor.nativeMetalCardRenderKind {
            return renderKind.staticImageSize
        }

        switch descriptor.collectionId {
        case cardNftCollectionId:
            return CGSize(width: 776, height: 1098)
        case drifella2CollectionId:
            return CGSize(width: 1200, height: 1295)
        case driladyCollectionId:
            return CGSize(width: 932, height: 1006)
        default:
            return CGSize(width: 1, height: 1)
        }
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

private enum MobileCollectionBrowseMediaWindowLayout {
    private static let decodedPreferredViewportRadius = 2
    private static let decodedOppositeViewportRadius = 1
    private static let filePreferredViewportRadius = 6
    private static let fileOppositeViewportRadius = 2

    static func fileOffsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        offsets(
            prefetchStride: prefetchStride,
            direction: direction,
            preferredViewportRadius: filePreferredViewportRadius,
            oppositeViewportRadius: fileOppositeViewportRadius
        )
    }

    static func decodedOffsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        offsets(
            prefetchStride: prefetchStride,
            direction: direction,
            preferredViewportRadius: decodedPreferredViewportRadius,
            oppositeViewportRadius: decodedOppositeViewportRadius
        )
    }

    private static func offsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        preferredViewportRadius: Int,
        oppositeViewportRadius: Int
    ) -> [Int] {
        let cappedPrefetchStride = min(
            max(prefetchStride, 1),
            MobilePlayerBrowserLayout.maximumPrefetchStride
        )
        return PlayerDownloadableMediaWindowLayout.orderedOffsets(
            direction: direction,
            preferredRadius: cappedPrefetchStride * preferredViewportRadius,
            oppositeRadius: cappedPrefetchStride * oppositeViewportRadius
        )
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
            ?? MobilePlayerCollectionBrowserSupport.isAvailable(for: currentDescriptor)
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
        prefetchStride: Int
    ) -> PlayerDownloadableMediaWindow? {
        guard let snapshot = collectionBrowseSnapshot(uuid: uuid),
              tokenIndex >= 0,
              tokenIndex < snapshot.itemCount else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }

        let fileOffsets = MobileCollectionBrowseMediaWindowLayout.fileOffsets(
            prefetchStride: prefetchStride,
            direction: direction
        )
        let decodedOffsets = MobileCollectionBrowseMediaWindowLayout.decodedOffsets(
            prefetchStride: prefetchStride,
            direction: direction
        )
        let fileTokenIndices = PlayerDownloadableMediaWindowLayout.indices(
            currentIndex: tokenIndex,
            tokenCount: snapshot.itemCount,
            offsets: fileOffsets
        )
        let decodedTokenIndices = PlayerDownloadableMediaWindowLayout.indices(
            currentIndex: tokenIndex,
            tokenCount: snapshot.itemCount,
            offsets: decodedOffsets
        )
        let adjacentTokenIndex = PlayerDownloadableMediaWindowLayout.indices(
            currentIndex: tokenIndex,
            tokenCount: snapshot.itemCount,
            offsets: [direction.adjacentOffset]
        ).first
        let descriptorLookup = collectionBrowseThumbnailDescriptorLookup(
            snapshot: snapshot,
            tokenIndices: fileTokenIndices
        )
        let descriptors = fileTokenIndices.compactMap { descriptorLookup[$0] }
        let centeredDescriptor = descriptorLookup[tokenIndex]
        guard let currentDescriptor = centeredDescriptor ?? descriptors.min(by: { lhs, rhs in
            let lhsDistance = abs(lhs.tokenIndex - tokenIndex)
            let rhsDistance = abs(rhs.tokenIndex - tokenIndex)
            return lhsDistance == rhsDistance
                ? lhs.tokenIndex < rhs.tokenIndex
                : lhsDistance < rhsDistance
        }) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }
        let decodedDescriptors = decodedTokenIndices.compactMap { descriptorLookup[$0] }
        let adjacentDescriptor = adjacentTokenIndex.flatMap { descriptorLookup[$0] }
        let preparedWindow = PlayerDownloadableMediaWindow(
            currentDescriptor: currentDescriptor,
            descriptors: descriptors,
            decodedDescriptors: decodedDescriptors,
            adjacentDescriptor: adjacentDescriptor,
            decodedDescriptorCapacity: max(decodedDescriptors.count, 1)
        )
        DownloadableMediaCache.shared.prepareWindow(preparedWindow, ownerId: uuid)
        return preparedWindow
    }

    private func collectionBrowseThumbnailDescriptorLookup(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndices: [Int]
    ) -> [Int: DownloadableMediaDescriptor] {
        var descriptorLookup = [Int: DownloadableMediaDescriptor]()
        descriptorLookup.reserveCapacity(tokenIndices.count)
        for tokenIndex in tokenIndices {
            guard let descriptor = collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            ), MobilePlayerCollectionBrowserSupport.isAvailable(for: descriptor) else {
                continue
            }
            descriptorLookup[tokenIndex] = descriptor
        }
        return descriptorLookup
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
