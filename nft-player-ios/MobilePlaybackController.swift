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

@MainActor
enum MobileCollectionBrowseMediaResolver {

    static func collectionBrowseThumbnailDescriptor(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> DownloadableMediaDescriptor? {
        guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else { return nil }

        return MobileCollectionCatalog.collectionBrowseThumbnailDescriptor(
            specificCollectionId: snapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    static func collectionBrowseImageSources(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        guard snapshot.pagePosition(forTokenIndex: tokenIndex) != nil else { return nil }

        return MobileCollectionCatalog.collectionBrowseImageSources(
            specificCollectionId: snapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    static func collectionBrowseImageDescriptor(
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

@MainActor
final class MobilePlaybackSession {

    private enum LifecycleState: Equatable {
        case active
        case disconnecting
        case disconnected
    }

    let config: MobilePlayerConfig

    var id: UUID {
        config.id
    }

    private weak var display: MobilePlaybackSessionDisplay?
    private let viewingSessionTracker: any MobilePlaybackViewingSessionTracking
    fileprivate let mediaWindowOwnerID = UUID()
    private let disconnect: @MainActor (MobilePlaybackSession) -> Void
    private var lifecycleState = LifecycleState.active
    private var navigationRequestGeneration: UInt = 0
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
        disconnect: @escaping @MainActor (MobilePlaybackSession) -> Void
    ) {
        self.config = config
        self.viewingSessionTracker = viewingSessionTracker
        self.disconnect = disconnect
    }

    func attach(display: MobilePlaybackSessionDisplay) {
        guard lifecycleState == .active else { return }
        self.display = display
    }

    func stopAndDisconnect() {
        guard lifecycleState == .active else { return }
        lifecycleState = .disconnecting
        advanceNavigationRequestGeneration()
        display?.flushPendingViewingProgress()
        display = nil
        lifecycleState = .disconnected
        disconnect(self)
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
        DownloadableMediaCache.shared.clearActiveWindow(ownerId: mediaWindowOwnerID)
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
        guard lifecycleState == .active,
              let window = dataSource.downloadableMediaWindow(
                  pagePosition: pagePosition,
                  direction: direction
              ) else {
            clearDownloadableMediaWindow()
            return nil
        }

        DownloadableMediaCache.shared.prepareWindow(
            window,
            ownerId: mediaWindowOwnerID
        )
        return window
    }

    func prepareCollectionBrowseThumbnailWindow(
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
        guard lifecycleState == .active,
              let snapshot = collectionBrowseSnapshot() else {
            clearDownloadableMediaWindow()
            return
        }
        let compactCoverage = MobileCollectionBrowseMediaResolver
            .collectionBrowseCompactCoverage(
                imageSources: MobileCollectionBrowseMediaResolver
                    .collectionBrowseImageSources(
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
                        return MobileCollectionBrowseMediaResolver
                            .collectionBrowseImageDescriptor(
                                snapshot: snapshot,
                                tokenIndex: candidateTokenIndex,
                                quality: quality
                            )
                    case .locallyAvailableLarge:
                        return MobileCollectionBrowseMediaResolver
                            .collectionBrowseImageDescriptor(
                                snapshot: snapshot,
                                tokenIndex: candidateTokenIndex,
                                quality: .large
                            )
                    case .omitSatisfiedToken:
                        return nil
                    }
                }
              ) else {
            clearDownloadableMediaWindow()
            return
        }
        DownloadableMediaCache.shared.prepareWindow(
            preparedWindow,
            ownerId: mediaWindowOwnerID
        )
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
    ) -> MobilePlayerFileShareItem? {
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
                    ?? Strings.pagePosition(
                        current: context.tokenIndex + 1,
                        total: context.tokenCount
                    )
            ),
            releaseFile: releaseFile
        ) {
            DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor)
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
            )
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
