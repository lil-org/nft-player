// ∅ 2026 lil org

import CoreGraphics
import Foundation

struct CollectionCatalogItem: Hashable, Identifiable {
    let id: String
    let name: String
    let coverAssetName: String

    init(item: SuggestedItem) {
        id = item.id
        name = item.name
        coverAssetName = item.id
    }
}

struct CollectionCatalogDownloadableMediaDescriptor: Hashable {
    let collectionId: String
    let tokenId: String
    let tokenIndex: Int
    let media: GeneratedTokenMedia

    var url: URL {
        media.url
    }

    var fileExtension: String {
        media.fileExtension
    }

    var isStaticImage: Bool {
        media.isStaticImage
    }
}

struct PlayerPagePosition: Hashable {
    let position: Int

    static let initial = PlayerPagePosition(position: 0)

    func advanced(by offset: Int) -> PlayerPagePosition {
        PlayerPagePosition(position: position + offset)
    }
}

struct PlayerStablePagePositionResult: Hashable {
    let pagePosition: PlayerPagePosition
    let didExitWidgetInsertion: Bool
}

struct PlayerTokenContext: Hashable {
    let collectionId: String
    let tokenIndex: Int
    let tokenCount: Int
}

enum PlayerMediaPrefetchDirection: Hashable {
    case forward, backward

    var adjacentOffset: Int {
        switch self {
        case .forward:
            return 1
        case .backward:
            return -1
        }
    }
}

enum PlayerDownloadableMediaWindowLayout {
    static let windowRadius = 10
    static let decodedPreferredRadius = 3
    static let decodedOppositeRadius = 1
    static let decodedWindowCapacity = decodedPreferredRadius + decodedOppositeRadius + 1

    static func orderedWindowOffsets(direction: PlayerMediaPrefetchDirection) -> [Int] {
        return [0] + preferredOffsets(radius: windowRadius, direction: direction)
            + oppositeOffsets(radius: windowRadius, direction: direction)
    }

    static func decodedWindowOffsets(direction: PlayerMediaPrefetchDirection) -> [Int] {
        return [0] + preferredOffsets(radius: decodedPreferredRadius, direction: direction)
            + oppositeOffsets(radius: decodedOppositeRadius, direction: direction)
    }

    static func orderedWindowIndices(
        currentIndex: Int,
        tokenCount: Int,
        direction: PlayerMediaPrefetchDirection
    ) -> [Int] {
        indices(
            currentIndex: currentIndex,
            tokenCount: tokenCount,
            offsets: orderedWindowOffsets(direction: direction)
        )
    }

    static func decodedWindowIndices(
        currentIndex: Int,
        tokenCount: Int,
        direction: PlayerMediaPrefetchDirection
    ) -> [Int] {
        indices(
            currentIndex: currentIndex,
            tokenCount: tokenCount,
            offsets: decodedWindowOffsets(direction: direction)
        )
    }

    private static func preferredOffsets(radius: Int, direction: PlayerMediaPrefetchDirection) -> [Int] {
        guard radius > 0 else { return [] }

        let offsets = Array(1...radius)
        switch direction {
        case .forward:
            return offsets
        case .backward:
            return offsets.map { -$0 }
        }
    }

    private static func oppositeOffsets(radius: Int, direction: PlayerMediaPrefetchDirection) -> [Int] {
        guard radius > 0 else { return [] }

        let offsets = Array(1...radius)
        switch direction {
        case .forward:
            return offsets.map { -$0 }
        case .backward:
            return offsets
        }
    }

    private static func indices(currentIndex: Int, tokenCount: Int, offsets: [Int]) -> [Int] {
        guard tokenCount > 0 else { return [] }

        return offsets.compactMap { offset in
            let index = currentIndex + offset
            guard index >= 0, index < tokenCount else { return nil }
            return index
        }
    }
}

struct PlayerDownloadableMediaWindow: Hashable {
    let currentDescriptor: CollectionCatalogDownloadableMediaDescriptor
    let descriptors: [CollectionCatalogDownloadableMediaDescriptor]
    let decodedDescriptors: [CollectionCatalogDownloadableMediaDescriptor]
    let adjacentDescriptor: CollectionCatalogDownloadableMediaDescriptor?

    init(
        currentDescriptor: CollectionCatalogDownloadableMediaDescriptor,
        descriptors: [CollectionCatalogDownloadableMediaDescriptor],
        decodedDescriptors: [CollectionCatalogDownloadableMediaDescriptor],
        adjacentDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    ) {
        self.currentDescriptor = currentDescriptor
        self.descriptors = Self.uniqueDescriptors(
            currentDescriptor: currentDescriptor,
            descriptors: descriptors
        )
        self.decodedDescriptors = Array(
            Self.uniqueDescriptors(
                currentDescriptor: currentDescriptor,
                descriptors: decodedDescriptors
            )
            .filter(\.isStaticImage)
            .prefix(PlayerDownloadableMediaWindowLayout.decodedWindowCapacity)
        )
        self.adjacentDescriptor = adjacentDescriptor
    }

    private static func uniqueDescriptors(
        currentDescriptor: CollectionCatalogDownloadableMediaDescriptor,
        descriptors: [CollectionCatalogDownloadableMediaDescriptor]
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        var orderedDescriptors = [CollectionCatalogDownloadableMediaDescriptor]()
        var usedDescriptors = Set<CollectionCatalogDownloadableMediaDescriptor>()

        func appendDescriptor(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
            guard usedDescriptors.insert(descriptor).inserted else { return }
            orderedDescriptors.append(descriptor)
        }

        appendDescriptor(currentDescriptor)
        descriptors.forEach(appendDescriptor)
        return orderedDescriptors
    }
}

enum PlaybackNavigationDirection {
    case back, forward, restartCollection

    var isPagingDirection: Bool {
        self == .back || self == .forward
    }

    func pageOffset(forStride stride: Int) -> Int? {
        switch self {
        case .back:
            return -stride
        case .forward:
            return stride
        case .restartCollection:
            return nil
        }
    }
}

final class PlayerTokenPagingDataSource {

    private let initialCollectionId: String?
    private let specificInitialToken: GeneratedToken?
    private let initialTokenId: String?

    private var collectionId: String?
    private var collectionBaseTokenIndex: Int?
    private var latestToken: GeneratedToken?
    private var latestPagePosition: PlayerPagePosition?
    private var activeWidgetTokenInsertion: PlayerWidgetTokenInsertion?

    init(
        initialCollectionId: String?,
        specificInitialToken: GeneratedToken?,
        initialTokenId: String?,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil
    ) {
        self.initialCollectionId = initialCollectionId
        self.specificInitialToken = specificInitialToken
        self.initialTokenId = initialTokenId
        self.activeWidgetTokenInsertion = widgetTokenInsertion

        if let widgetTokenInsertion {
            collectionId = widgetTokenInsertion.collectionId
            latestToken = widgetTokenInsertion.insertedToken
            latestPagePosition = .initial
        } else if let specificInitialToken {
            collectionId = specificInitialToken.fullCollectionId
            collectionBaseTokenIndex = CollectionCatalog.tokenIndex(
                specificCollectionId: specificInitialToken.fullCollectionId,
                tokenId: specificInitialToken.id
            ) ?? 0
            latestToken = specificInitialToken
            latestPagePosition = .initial
        }
    }

    func canRender(pagePosition: PlayerPagePosition) -> Bool {
        collectionTokenContext(pagePosition: pagePosition) != nil
    }

    func collectionTokenContext(pagePosition: PlayerPagePosition) -> PlayerTokenContext? {
        guard let collectionId = activeCollectionId(),
              let tokenIndex = tokenIndex(pagePosition: pagePosition) else {
            return nil
        }

        let tokenCount = CollectionCatalog.tokenCount(specificCollectionId: collectionId)
        guard tokenIndex >= 0,
              tokenIndex < tokenCount,
              CollectionCatalog.canGenerateToken(specificCollectionId: collectionId, tokenIndex: tokenIndex) else {
            return nil
        }
        return PlayerTokenContext(collectionId: collectionId, tokenIndex: tokenIndex, tokenCount: tokenCount)
    }

    func downloadableMediaWindow(
        pagePosition: PlayerPagePosition,
        direction: PlayerMediaPrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        guard let context = collectionTokenContext(pagePosition: pagePosition),
              CollectionCatalog.isDownloadableCollection(specificCollectionId: context.collectionId) else {
            return nil
        }

        if isWidgetPositionSpace {
            return logicalDownloadableMediaWindow(pagePosition: pagePosition, direction: direction)
        }

        return indexedDownloadableMediaWindow(context: context, direction: direction)
    }

    func pagePosition(forTokenIndex tokenIndex: Int) -> PlayerPagePosition {
        if let widgetTokenInsertion = activeWidgetTokenInsertion {
            return widgetTokenInsertion.pagePosition(forTokenIndex: tokenIndex)
        }
        ensureCollectionLoaded()
        return PlayerPagePosition(position: tokenIndex - (collectionBaseTokenIndex ?? 0))
    }

    func stablePagePosition(
        containing pagePosition: PlayerPagePosition,
        pageSize: Int
    ) -> PlayerPagePosition? {
        guard pageSize > 1 else { return pagePosition }
        guard let context = collectionTokenContext(pagePosition: pagePosition) else { return nil }

        let tokenIndex = stableTokenIndex(containing: context.tokenIndex, pageSize: pageSize)
        return self.pagePosition(forTokenIndex: tokenIndex)
    }

    func exitWidgetInsertionForStablePage(
        containing pagePosition: PlayerPagePosition,
        pageSize: Int
    ) -> PlayerStablePagePositionResult? {
        guard pageSize > 1 else {
            return PlayerStablePagePositionResult(
                pagePosition: pagePosition,
                didExitWidgetInsertion: false
            )
        }
        guard let target = stableTokenTarget(containing: pagePosition, pageSize: pageSize) else { return nil }

        let didExitWidgetInsertion = isWidgetPositionSpace
        if didExitWidgetInsertion {
            deactivateWidgetInsertion(using: target.context)
        }
        return PlayerStablePagePositionResult(
            pagePosition: self.pagePosition(forTokenIndex: target.tokenIndex),
            didExitWidgetInsertion: didExitWidgetInsertion
        )
    }

    func progress(pagePosition: PlayerPagePosition) -> PlayerViewingProgress? {
        if isInsertedWidgetToken(pagePosition: pagePosition),
           let widgetTokenInsertion = activeWidgetTokenInsertion {
            return widgetTokenInsertion.updatedAnchorProgress()
        }

        guard let context = collectionTokenContext(pagePosition: pagePosition) else { return nil }

        let token = getToken(pagePosition: pagePosition)
        guard !token.fullCollectionId.isEmpty else { return nil }
        return PlayerViewingProgress(
            collectionId: context.collectionId,
            collectionName: token.collectionName,
            tokenId: token.id,
            tokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            updatedAt: Date()
        )
    }

    func pageLabel(pagePosition: PlayerPagePosition) -> String? {
        guard let context = collectionTokenContext(pagePosition: pagePosition) else { return nil }
        return Strings.pagePosition(current: context.tokenIndex + 1, total: context.tokenCount)
    }

    func isInsertedWidgetToken(pagePosition: PlayerPagePosition) -> Bool {
        activeWidgetTokenInsertion != nil && pagePosition == .initial
    }

    func getToken(pagePosition: PlayerPagePosition) -> GeneratedToken {
        if latestPagePosition == pagePosition, let token = latestToken {
            return token
        }

        if isInsertedWidgetToken(pagePosition: pagePosition),
           let widgetTokenInsertion = activeWidgetTokenInsertion {
            latestToken = widgetTokenInsertion.insertedToken
            latestPagePosition = pagePosition
            return widgetTokenInsertion.insertedToken
        }

        guard let collectionId = activeCollectionId(),
              let tokenIndex = tokenIndex(pagePosition: pagePosition),
              let token = CollectionCatalog.generateToken(specificCollectionId: collectionId, tokenIndex: tokenIndex) else {
            return .empty
        }

        latestToken = token
        latestPagePosition = pagePosition
        return token
    }

    private func tokenIndex(pagePosition: PlayerPagePosition) -> Int? {
        if let widgetTokenInsertion = activeWidgetTokenInsertion {
            return widgetTokenInsertion.tokenIndex(for: pagePosition)
        }

        guard let collectionBaseTokenIndex else { return nil }
        return collectionBaseTokenIndex + pagePosition.position
    }

    private var isWidgetPositionSpace: Bool {
        activeWidgetTokenInsertion != nil
    }

    private func stableTokenIndex(containing tokenIndex: Int, pageSize: Int) -> Int {
        guard pageSize > 1 else { return tokenIndex }
        return (tokenIndex / pageSize) * pageSize
    }

    private func stableTokenTarget(
        containing pagePosition: PlayerPagePosition,
        pageSize: Int
    ) -> (context: PlayerTokenContext, tokenIndex: Int)? {
        guard let context = collectionTokenContext(pagePosition: pagePosition) else { return nil }

        let tokenIndex = stableTokenIndex(containing: context.tokenIndex, pageSize: pageSize)
        guard tokenIndex >= 0,
              tokenIndex < context.tokenCount,
              CollectionCatalog.canGenerateToken(
                specificCollectionId: context.collectionId,
                tokenIndex: tokenIndex
              ) else {
            return nil
        }
        return (context, tokenIndex)
    }

    private func deactivateWidgetInsertion(using context: PlayerTokenContext) {
        guard isWidgetPositionSpace else { return }

        activeWidgetTokenInsertion = nil
        collectionId = context.collectionId
        collectionBaseTokenIndex = context.tokenIndex
        latestToken = nil
        latestPagePosition = nil
    }

    private func indexedDownloadableMediaWindow(
        context: PlayerTokenContext,
        direction: PlayerMediaPrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        let descriptors = downloadableMediaDescriptors(
            collectionId: context.collectionId,
            tokenIndices: PlayerDownloadableMediaWindowLayout.orderedWindowIndices(
                currentIndex: context.tokenIndex,
                tokenCount: context.tokenCount,
                direction: direction
            )
        )
        let decodedDescriptors = downloadableMediaDescriptors(
            collectionId: context.collectionId,
            tokenIndices: PlayerDownloadableMediaWindowLayout.decodedWindowIndices(
                currentIndex: context.tokenIndex,
                tokenCount: context.tokenCount,
                direction: direction
            )
        )
        guard let currentDescriptor = descriptors.first(where: { $0.tokenIndex == context.tokenIndex }) else {
            return nil
        }

        return PlayerDownloadableMediaWindow(
            currentDescriptor: currentDescriptor,
            descriptors: descriptors,
            decodedDescriptors: decodedDescriptors,
            adjacentDescriptor: adjacentDownloadableMediaDescriptor(
                context: context,
                direction: direction
            )
        )
    }

    private func logicalDownloadableMediaWindow(
        pagePosition: PlayerPagePosition,
        direction: PlayerMediaPrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        guard let currentDescriptor = downloadableMediaDescriptor(pagePosition: pagePosition) else { return nil }

        let descriptors = uniqueDownloadableMediaDescriptors(
            PlayerDownloadableMediaWindowLayout.orderedWindowOffsets(direction: direction).map {
                pagePosition.advanced(by: $0)
            }
        )
        let decodedDescriptors = uniqueDownloadableMediaDescriptors(
            PlayerDownloadableMediaWindowLayout.decodedWindowOffsets(direction: direction).map {
                pagePosition.advanced(by: $0)
            }
        )

        return PlayerDownloadableMediaWindow(
            currentDescriptor: currentDescriptor,
            descriptors: descriptors,
            decodedDescriptors: decodedDescriptors,
            adjacentDescriptor: downloadableMediaDescriptor(
                pagePosition: pagePosition.advanced(by: direction.adjacentOffset)
            )
        )
    }

    private func downloadableMediaDescriptors(
        collectionId: String,
        tokenIndices: [Int]
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        tokenIndices.compactMap {
            CollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: collectionId,
                tokenIndex: $0
            )
        }
    }

    private func adjacentDownloadableMediaDescriptor(
        context: PlayerTokenContext,
        direction: PlayerMediaPrefetchDirection
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        let targetTokenIndex = context.tokenIndex + direction.adjacentOffset
        guard targetTokenIndex >= 0, targetTokenIndex < context.tokenCount else { return nil }
        return CollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: targetTokenIndex
        )
    }

    private func uniqueDownloadableMediaDescriptors(
        _ pagePositions: [PlayerPagePosition]
    ) -> [CollectionCatalogDownloadableMediaDescriptor] {
        var descriptors = [CollectionCatalogDownloadableMediaDescriptor]()
        var usedDescriptors = Set<CollectionCatalogDownloadableMediaDescriptor>()

        for pagePosition in pagePositions {
            guard let descriptor = downloadableMediaDescriptor(pagePosition: pagePosition),
                  usedDescriptors.insert(descriptor).inserted else {
                continue
            }
            descriptors.append(descriptor)
        }
        return descriptors
    }

    private func downloadableMediaDescriptor(
        pagePosition: PlayerPagePosition
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let context = collectionTokenContext(pagePosition: pagePosition),
              CollectionCatalog.isDownloadableCollection(specificCollectionId: context.collectionId) else {
            return nil
        }

        return CollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    private func ensureCollectionLoaded() {
        _ = activeCollectionId()
    }

    private func activeCollectionId() -> String? {
        if let collectionId {
            return collectionId
        }

        let collection = (
            id: activeWidgetTokenInsertion?.collectionId ?? specificInitialToken?.fullCollectionId ?? initialCollectionId ?? CollectionCatalog.nextShuffledCollectionId(),
            requestedTokenId: activeWidgetTokenInsertion?.anchorTokenId ?? specificInitialToken?.id ?? initialTokenId
        )

        guard let collectionId = collection.id else { return nil }
        self.collectionId = collectionId

        let baseTokenIndex: Int
        if let requestedTokenId = collection.requestedTokenId,
           let requestedIndex = CollectionCatalog.tokenIndex(specificCollectionId: collectionId, tokenId: requestedTokenId) {
            baseTokenIndex = requestedIndex
        } else {
            baseTokenIndex = 0
        }
        collectionBaseTokenIndex = baseTokenIndex
        return collectionId
    }
}

enum CollectionCatalog {
    private static let shuffleLock = NSLock()
    private static var currentPassCollectionIds = Set<String>()

    static let allItems: [CollectionCatalogItem] = {
        dedupedItems(
            generativeItemsForGrid
                + downloadableItemsForGrid
        )
        .filter { !TokenGenerator.isCollectionDisabledOnCurrentPlatform(id: $0.id) }
        .map(CollectionCatalogItem.init(item:))
    }()

    static func nextShuffledCollectionId() -> String? {
        shuffleLock.withLock {
            if currentPassCollectionIds.isEmpty {
                currentPassCollectionIds = Set(allItems.map(\.id))
            }
            let nextCollectionId = currentPassCollectionIds.randomElement()
            if let nextCollectionId {
                currentPassCollectionIds.remove(nextCollectionId)
            }
            return nextCollectionId
        }
    }

    static func tokenCount(specificCollectionId: String) -> Int {
        if DownloadableCollectionService.hasCollection(id: specificCollectionId) {
            return DownloadableCollectionService.tokenCount(collectionId: specificCollectionId)
        }
        return TokenGenerator.tokenCount(specificCollectionId: specificCollectionId)
    }

    static func canOpenCollection(specificCollectionId: String) -> Bool {
        if let tokenCount = DownloadableCollectionService.indexedTokenCount(collectionId: specificCollectionId) {
            return tokenCount > 0
        }
        return TokenGenerator.canGenerate(id: specificCollectionId)
    }

    static func isDownloadableCollection(specificCollectionId: String) -> Bool {
        DownloadableCollectionService.hasCollection(id: specificCollectionId)
    }

    static func tokenIndex(specificCollectionId: String, tokenId: String) -> Int? {
        if DownloadableCollectionService.hasCollection(id: specificCollectionId) {
            return DownloadableCollectionService.tokenIndex(collectionId: specificCollectionId, tokenId: tokenId)
        }
        return TokenGenerator.tokenIndex(specificCollectionId: specificCollectionId, tokenId: tokenId)
    }

    static func tokenContext(for token: GeneratedToken) -> PlayerTokenContext? {
        guard !token.fullCollectionId.isEmpty,
              !token.id.isEmpty,
              let tokenIndex = tokenIndex(
                specificCollectionId: token.fullCollectionId,
                tokenId: token.id
              ) else {
            return nil
        }

        let tokenCount = tokenCount(specificCollectionId: token.fullCollectionId)
        guard tokenCount > 0 else { return nil }
        return PlayerTokenContext(
            collectionId: token.fullCollectionId,
            tokenIndex: tokenIndex,
            tokenCount: tokenCount
        )
    }

    static func widgetTokenInsertion(
        collectionId: String,
        widgetTokenId: String,
        progress: PlayerViewingProgress?
    ) -> PlayerWidgetTokenInsertion? {
        guard allItems.contains(where: { $0.id == collectionId }),
              let insertedTokenIndex = tokenIndex(specificCollectionId: collectionId, tokenId: widgetTokenId),
              let insertedToken = generateToken(specificCollectionId: collectionId, tokenIndex: insertedTokenIndex) else {
            return nil
        }

        let tokenCount = tokenCount(specificCollectionId: collectionId)
        guard tokenCount > 0 else { return nil }

        let anchorTokenIndex: Int
        if let progress,
           progress.collectionId == collectionId,
           progress.tokenIndex >= 0,
           progress.tokenIndex < tokenCount,
           tokenIndex(specificCollectionId: collectionId, tokenId: progress.tokenId) == progress.tokenIndex {
            anchorTokenIndex = progress.tokenIndex
        } else {
            anchorTokenIndex = 0
        }

        guard let anchorToken = generateToken(specificCollectionId: collectionId, tokenIndex: anchorTokenIndex) else {
            return nil
        }

        let anchorProgress = PlayerViewingProgress(
            collectionId: collectionId,
            collectionName: anchorToken.collectionName,
            tokenId: anchorToken.id,
            tokenIndex: anchorTokenIndex,
            tokenCount: tokenCount,
            updatedAt: Date(),
            hasViewedToEnd: progress?.hasBeenViewedToEnd == true
        )

        return PlayerWidgetTokenInsertion(
            insertedToken: insertedToken,
            insertedTokenIndex: insertedTokenIndex,
            anchorProgress: anchorProgress
        )
    }

    static func generateRandomToken(specificCollectionId: String?, notTokenId: String?) -> GeneratedToken? {
        if specificCollectionId == nil {
            for _ in 0..<allItems.count {
                guard let collectionId = nextShuffledCollectionId() else { return nil }
                if let token = generateRandomToken(specificCollectionId: collectionId, notTokenId: notTokenId) {
                    return token
                }
            }
            return nil
        }

        guard let collectionId = specificCollectionId else {
            return nil
        }

        if DownloadableCollectionService.hasCollection(id: collectionId) {
            return generateRandomDownloadableToken(collectionId: collectionId, notTokenId: notTokenId)
        }

        return TokenGenerator.generateRandomToken(specificCollectionId: collectionId, notTokenId: notTokenId)
    }

    static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        if DownloadableCollectionService.hasCollection(id: specificCollectionId) {
            return DownloadableCollectionService.generateToken(collectionId: specificCollectionId, tokenIndex: tokenIndex)
        }
        return TokenGenerator.generateToken(specificCollectionId: specificCollectionId, tokenIndex: tokenIndex)
    }

    static func canGenerateToken(specificCollectionId: String, tokenIndex: Int) -> Bool {
        guard tokenIndex >= 0 else { return false }
        if DownloadableCollectionService.hasCollection(id: specificCollectionId) {
            return DownloadableCollectionService.mediaDescriptor(collectionId: specificCollectionId, tokenIndex: tokenIndex) != nil
        }
        return tokenIndex < TokenGenerator.tokenCount(specificCollectionId: specificCollectionId)
    }

    static func downloadableMediaDescriptor(specificCollectionId: String, tokenIndex: Int) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard DownloadableCollectionService.hasCollection(id: specificCollectionId) else { return nil }
        return DownloadableCollectionService.mediaDescriptor(collectionId: specificCollectionId, tokenIndex: tokenIndex)
    }

    static func downloadableMediaDescriptor(for context: PlayerTokenContext?) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let context else { return nil }
        return downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    static func playerBackgroundColor(specificCollectionId: String) -> String? {
        SuggestedItemsService.item(id: specificCollectionId)?.playerBackgroundColor
    }

    private static func dedupedItems(_ items: [SuggestedItem]) -> [SuggestedItem] {
        var seenIds = Set<String>()
        return items.filter { item in
            guard !seenIds.contains(item.id) else { return false }
            seenIds.insert(item.id)
            return true
        }
    }

    private static var generativeItemsForGrid: [SuggestedItem] {
        return TokenGenerator.allGenerativeSuggestedItems.filter {
            !$0.isSolanaCollection && !$0.isTezosCollection
        }
    }

    private static var downloadableItemsForGrid: [SuggestedItem] {
        return SuggestedItemsService.allDownloadableCollectionItems.filter {
            $0.tokenCount != nil || TokenGenerator.canGenerate(id: $0.id)
        }
    }

    private static func generateRandomDownloadableToken(collectionId: String, notTokenId: String?) -> GeneratedToken? {
        let count = DownloadableCollectionService.tokenCount(collectionId: collectionId)
        guard count > 0 else { return nil }

        var tokenIndex = Int.random(in: 0..<count)
        if let notTokenId,
           let excludedIndex = DownloadableCollectionService.tokenIndex(collectionId: collectionId, tokenId: notTokenId),
           tokenIndex == excludedIndex,
           count > 1 {
            tokenIndex = (tokenIndex + Int.random(in: 1..<count)) % count
        }

        return DownloadableCollectionService.generateToken(collectionId: collectionId, tokenIndex: tokenIndex)
    }
}

struct DownloadableCollectionIndexItem: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let address: String
    let chain: Chain
    let network: Network
    let tokenCount: Int

    init?(item: SuggestedItem) {
        guard item.isDownloadableCollection,
              let tokenCount = item.tokenCount else {
            return nil
        }
        id = item.id
        name = item.name
        address = item.address
        chain = item.chain
        network = item.network
        self.tokenCount = tokenCount
    }
}

private enum DownloadableCollectionService {
    private static let collectionAddressOnlyBlockExplorerAddresses: Set<String> = [
        "0xc2276a4a03e7c2e2fa122692b07a870eff43cf51",
    ]
    private static let lock = NSLock()
    private static var cachedIndex: DownloadableCollectionsIndex?
    private static var cachedTokenDataByCollectionId = [String: DownloadableCollectionTokenData]()

    static func hasCollection(id: String) -> Bool {
        index.collectionById[id] != nil
    }

    static func tokenCount(collectionId: String) -> Int {
        tokenData(collectionId: collectionId)?.tokens.count
            ?? index.collectionById[collectionId]?.tokenCount
            ?? 0
    }

    static func indexedTokenCount(collectionId: String) -> Int? {
        index.collectionById[collectionId]?.tokenCount
    }

    static func tokenIndex(collectionId: String, tokenId: String) -> Int? {
        tokenData(collectionId: collectionId)?.tokenIndicesById[tokenId]
    }

    static func generateToken(collectionId: String, tokenIndex: Int) -> GeneratedToken? {
        guard let collection = index.collectionById[collectionId],
              let tokenData = tokenData(collectionId: collectionId),
              tokenData.tokens.indices.contains(tokenIndex) else {
            return nil
        }

        let token = tokenData.tokens[tokenIndex]
        guard let media = resolvedMedia(
            for: token,
            collection: collection,
            defaultFileExtension: tokenData.defaultFileExtension
        ) else {
            return nil
        }

        let displayTokenId = Self.displayTokenId(
            chain: collection.chain,
            token: token,
            tokenIndex: tokenIndex
        )
        let webURL = Self.webURL(collection: collection, tokenId: token.id)

        let html: String
        switch media {
        case .staticImage, .animatedImage:
            let nextMedia = tokenData.tokens.indices.contains(tokenIndex + 1)
                ? resolvedMedia(
                    for: tokenData.tokens[tokenIndex + 1],
                    collection: collection,
                    defaultFileExtension: tokenData.defaultFileExtension
                )
                : nil
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: media.url.absoluteString,
                nextImageURL: nextMedia?.url.absoluteString
            )
        case .video:
            html = DownloadableTokenHTML.createVideoHTML(videoURL: media.url.absoluteString)
        case .html:
            html = DownloadableTokenHTML.createHTMLDocumentHTML(documentURL: media.url.absoluteString)
        }

        return GeneratedToken(
            fullCollectionId: collection.id,
            collectionName: collection.name,
            address: collection.address,
            id: token.id,
            html: html,
            displayName: token.name ?? "\(collection.name) \(displayTokenId)",
            displayTokenId: displayTokenId,
            url: webURL,
            instructions: nil,
            screensaver: nil,
            media: media
        )
    }

    static func mediaDescriptor(collectionId: String, tokenIndex: Int) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let collection = index.collectionById[collectionId],
              let tokenData = tokenData(collectionId: collectionId),
              tokenData.tokens.indices.contains(tokenIndex) else {
            return nil
        }

        let token = tokenData.tokens[tokenIndex]
        guard let media = resolvedMedia(
            for: token,
            collection: collection,
            defaultFileExtension: tokenData.defaultFileExtension
        ) else {
            return nil
        }

        return CollectionCatalogDownloadableMediaDescriptor(
            collectionId: collectionId,
            tokenId: token.id,
            tokenIndex: tokenIndex,
            media: media
        )
    }

    private static func displayTokenId(
        chain: Chain,
        token: DownloadableTokenItem,
        tokenIndex: Int
    ) -> String {
        if chain == .solana {
            return "#\(tokenIndex + 1)"
        }
        return "#\(token.id)"
    }

    private static func webURL(collection: DownloadableCollectionIndexItem, tokenId: String) -> URL? {
        if collection.chain == .solana {
            return URL(string: "https://explorer.solana.com/address/\(tokenId)")
        }
        if collection.chain == .tezos {
            return URL(string: "https://tzkt.io/\(collection.address)/tokens/\(tokenId)")
        }
        let blockExplorerTokenId = collectionAddressOnlyBlockExplorerAddresses.contains(collection.address.lowercased())
            ? nil
            : tokenId
        return NftGallery.blockExplorer.url(
            network: collection.network,
            chain: collection.chain,
            collectionAddress: collection.address,
            tokenId: blockExplorerTokenId
        )
    }

    private static func resolvedMedia(
        for token: DownloadableTokenItem,
        collection: DownloadableCollectionIndexItem,
        defaultFileExtension: String?
    ) -> GeneratedTokenMedia? {
        guard let urlString = token.resolvedURLString(collection: collection),
              let url = URL(string: urlString),
              let fileExtension = token.resolvedFileExtension(
                collection: collection,
                defaultFileExtension: defaultFileExtension
              ) else {
            return nil
        }

        if DownloadableMediaFileExtension.isAnimatedImage(fileExtension) {
            return .animatedImage(url: url, fileExtension: fileExtension)
        }
        if DownloadableMediaFileExtension.isVideo(fileExtension) {
            return .video(url: url, fileExtension: fileExtension)
        }
        if DownloadableMediaFileExtension.isHTML(fileExtension) {
            return .html(url: url, fileExtension: fileExtension)
        }
        if DownloadableMediaFileExtension.isStaticImage(fileExtension) {
            return .staticImage(url: url, fileExtension: fileExtension)
        }
        return nil
    }

    private static var index: DownloadableCollectionsIndex {
        if let cachedIndex = lock.withLock({ cachedIndex }) {
            return cachedIndex
        }

        let loadedIndex = loadIndex()
        return lock.withLock {
            if let cachedIndex = Self.cachedIndex {
                return cachedIndex
            }
            Self.cachedIndex = loadedIndex
            return loadedIndex
        }
    }

    private static func tokenData(collectionId: String) -> DownloadableCollectionTokenData? {
        if let cachedTokenData = lock.withLock({ cachedTokenDataByCollectionId[collectionId] }) {
            return cachedTokenData
        }

        guard let loadedTokenData = loadTokenData(collectionId: collectionId) else {
            return nil
        }

        return lock.withLock {
            if let cachedTokenData = cachedTokenDataByCollectionId[collectionId] {
                return cachedTokenData
            }
            cachedTokenDataByCollectionId[collectionId] = loadedTokenData
            return loadedTokenData
        }
    }

    private static func loadIndex() -> DownloadableCollectionsIndex {
        DownloadableCollectionsIndex(
            collections: SuggestedItemsService.allDownloadableCollectionItems.compactMap(DownloadableCollectionIndexItem.init(item:))
        )
    }

    private static func loadTokenData(collectionId: String) -> DownloadableCollectionTokenData? {
        guard let collection = index.collectionById[collectionId],
              let url = SuggestedItemsService.bundle.url(forResource: collectionId, withExtension: "json", subdirectory: "Tokens")
                ?? SuggestedItemsService.bundle.url(forResource: collectionId.lowercased(), withExtension: "json", subdirectory: "Tokens"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(DownloadableCollectionTokensPayload.self, from: data) else {
            return nil
        }
        return DownloadableCollectionTokenData(
            defaultFileExtension: payload.defaultFileExtension,
            tokens: payload.items.filter {
                resolvedMedia(
                    for: $0,
                    collection: collection,
                    defaultFileExtension: payload.defaultFileExtension
                ) != nil
            }
        )
    }
}

private struct DownloadableCollectionsIndex {
    let collectionById: [String: DownloadableCollectionIndexItem]

    init(collections: [DownloadableCollectionIndexItem]) {
        collectionById = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })
    }
}

private struct DownloadableCollectionTokensPayload: Decodable {
    let defaultFileExtension: String?
    let items: [DownloadableTokenItem]

    enum CodingKeys: String, CodingKey {
        case defaultFileExtension
        case items
        case urlPrefixes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultFileExtension = Self.normalizedFileExtension(
            try container.decodeIfPresent(String.self, forKey: .defaultFileExtension)
        )
        let urlPrefixes = try container.decodeIfPresent([String].self, forKey: .urlPrefixes) ?? []

        if let compactRows = try? container.decode([DownloadableCompactTokenRow].self, forKey: .items) {
            items = compactRows.map { row in
                DownloadableTokenItem(
                    id: row.id,
                    name: nil,
                    url: row.url(prefixes: urlPrefixes),
                    sh: nil,
                    fileExtension: row.fileExtension
                )
            }
        } else {
            items = try container.decode([DownloadableTokenItem].self, forKey: .items).map { item in
                DownloadableTokenItem(
                    id: item.id,
                    name: item.name,
                    url: item.url,
                    sh: item.sh,
                    fileExtension: Self.normalizedFileExtension(item.fileExtension)
                )
            }
        }
    }

    private static func normalizedFileExtension(_ value: String?) -> String? {
        DownloadableMediaFileExtension.normalized(value)
    }
}

private struct DownloadableTokenItem: Codable, Hashable {
    let id: String
    let name: String?
    let url: String?
    let sh: String?
    let fileExtension: String?

    func resolvedURLString(collection: DownloadableCollectionIndexItem) -> String? {
        if let url {
            return url
        }
        if let sh {
            return "https://cdn.simplehash.com/assets/\(sh)"
        }
        if collection.chain == .ethereum {
            return "https://media-proxy.artblocks.io/\(collection.address)/\(id).png"
        }
        return nil
    }

    func resolvedFileExtension(
        collection: DownloadableCollectionIndexItem,
        defaultFileExtension: String?
    ) -> String? {
        guard let url = resolvedURLString(collection: collection) else { return nil }
        return DownloadableMediaFileExtension.explicitPathExtension(in: url)
            ?? DownloadableMediaFileExtension.normalized(fileExtension)
            ?? defaultFileExtension
    }
}

private struct DownloadableCompactTokenRow: Decodable {
    let id: String
    let prefixIndex: Int
    let urlSuffix: String
    let fileExtension: String?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        prefixIndex = try container.decode(Int.self)
        urlSuffix = try container.decode(String.self)
        fileExtension = DownloadableMediaFileExtension.normalized(try? container.decode(String.self))
    }

    func url(prefixes: [String]) -> String {
        guard prefixes.indices.contains(prefixIndex) else { return urlSuffix }
        return prefixes[prefixIndex] + urlSuffix
    }
}

private struct DownloadableCollectionTokenData {
    let defaultFileExtension: String?
    let tokens: [DownloadableTokenItem]
    let tokenIndicesById: [String: Int]

    init(defaultFileExtension: String?, tokens: [DownloadableTokenItem]) {
        self.defaultFileExtension = defaultFileExtension
        self.tokens = tokens

        var tokenIndicesById = [String: Int]()
        for (index, token) in tokens.enumerated() where tokenIndicesById[token.id] == nil {
            tokenIndicesById[token.id] = index
        }
        self.tokenIndicesById = tokenIndicesById
    }
}

private enum DownloadableMediaFileExtension {
    private static let staticImageExtensions = Set(["png", "jpg", "jpeg", "webp", "heic", "heif"])
    private static let animatedImageExtensions = Set(["gif", "svg"])
    private static let videoExtensions = Set(["mp4", "mov"])
    private static let htmlExtensions = Set(["html", "htm", "xhtml"])

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t\r")).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func explicitPathExtension(in urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        return normalized(url.pathExtension)
    }

    static func isStaticImage(_ fileExtension: String) -> Bool {
        staticImageExtensions.contains(fileExtension)
    }

    static func isAnimatedImage(_ fileExtension: String) -> Bool {
        animatedImageExtensions.contains(fileExtension)
    }

    static func isVideo(_ fileExtension: String) -> Bool {
        videoExtensions.contains(fileExtension)
    }

    static func isHTML(_ fileExtension: String) -> Bool {
        htmlExtensions.contains(fileExtension)
    }
}

enum DownloadableTokenHTML {
    static let imageElementId = "tokenImage"
    static let videoElementId = "tokenVideo"

    private static let trustedHTMLDocumentSandbox = "allow-scripts allow-same-origin"

    static func createImageHTML(imageURL: String, nextImageURL: String? = nil) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #\(imageElementId) {
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
        }
        </style>
        </head>
        <body>
        <img id="\(imageElementId)" alt="">
        <script>
        \(retainedPreloadFunctionJavaScript)
        const imageURL = \(javaScriptStringLiteral(imageURL));
        const nextImageURL = \(javaScriptStringLiteral(nextImageURL));
        const tokenImage = document.getElementById(\(javaScriptStringLiteral(imageElementId)));
        tokenImage.decoding = "async";
        tokenImage.src = imageURL;

        if (nextImageURL) {
            retainDownloadableTokenImagePreload(nextImageURL);
        }
        </script>
        </body>
        </html>
        """
    }

    static func createVideoHTML(videoURL: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #\(videoElementId) {
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
        }
        </style>
        </head>
        <body>
        <video id="\(videoElementId)" autoplay loop muted playsinline webkit-playsinline preload="auto"></video>
        <script>
        const videoURL = \(javaScriptStringLiteral(videoURL));
        const tokenVideo = document.getElementById(\(javaScriptStringLiteral(videoElementId)));
        tokenVideo.muted = true;
        tokenVideo.loop = true;
        tokenVideo.playsInline = true;
        tokenVideo.autoplay = true;
        tokenVideo.src = videoURL;

        function playTokenVideo() {
            const playPromise = tokenVideo.play();
            if (playPromise && playPromise.catch) {
                playPromise.catch(() => {});
            }
        }

        tokenVideo.addEventListener("canplay", playTokenVideo, { once: true });
        tokenVideo.addEventListener("loadeddata", playTokenVideo, { once: true });
        document.addEventListener("visibilitychange", () => {
            if (!document.hidden) {
                playTokenVideo();
            }
        });
        playTokenVideo();
        </script>
        </body>
        </html>
        """
    }

    static func createHTMLDocumentHTML(documentURL: String) -> String {
        createHTMLDocumentFrameHTML(
            iframeSandbox: trustedHTMLDocumentSandbox,
            iframeSourceJavaScript: """
        const documentURL = \(javaScriptStringLiteral(documentURL));
        document.getElementById("tokenDocument").src = documentURL;
        """
        )
    }

    static func createInlineHTMLDocumentHTML(
        documentHTML: String,
        baseURL: String?,
        contentSize: CGSize? = nil
    ) -> String {
        let documentHTML = htmlDocument(documentHTML, insertingBaseURL: baseURL)
        return createHTMLDocumentFrameHTML(
            iframeSandbox: trustedHTMLDocumentSandbox,
            contentSize: contentSize,
            iframeSourceJavaScript: """
        const documentHTML = \(javaScriptStringLiteral(documentHTML));
        document.getElementById("tokenDocument").srcdoc = documentHTML;
        """
        )
    }

    private static func createHTMLDocumentFrameHTML(
        iframeSandbox: String,
        contentSize: CGSize? = nil,
        iframeSourceJavaScript: String
    ) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #tokenDocument {
            width: 100%;
            height: 100%;
            border: 0;
            display: block;
            background: transparent;
        }
        </style>
        </head>
        <body>
        <iframe id="tokenDocument" sandbox="\(iframeSandbox)" allow="autoplay; fullscreen"></iframe>
        <script>
        \(htmlDocumentAspectFitJavaScript(contentSize: contentSize))
        \(iframeSourceJavaScript)
        </script>
        </body>
        </html>
        """
    }

    static func preloadImageJavaScript(imageURL: URL) -> String {
        """
        \(retainedPreloadFunctionJavaScript)
        return await retainDownloadableTokenImagePreload(\(javaScriptStringLiteral(imageURL.absoluteString)));
        """
    }

    private static var retainedPreloadFunctionJavaScript: String {
        """
        function retainDownloadableTokenImagePreload(url) {
            if (!url) {
                return Promise.resolve(false);
            }

            const maximumRetainedPreloads = 4;
            const releasePreload = (entry) => {
                if (!entry) {
                    return;
                }
                if (entry.cancel) {
                    entry.cancel();
                    return;
                }
                if (entry.timeoutId) {
                    clearTimeout(entry.timeoutId);
                    entry.timeoutId = null;
                }
                if (entry.image) {
                    entry.image.onload = null;
                    entry.image.onerror = null;
                    entry.image.removeAttribute("src");
                }
                entry.promise = null;
            };

            let existingPreloads = window.__downloadableTokenImagePreloads || [];
            const existingPreload = existingPreloads.find((entry) => entry.url === url);
            if (existingPreload) {
                if (existingPreload.promise) {
                    return existingPreload.promise;
                }
                if (existingPreload.didLoad === true) {
                    return Promise.resolve(true);
                }

                const existingImage = existingPreload.image;
                if (existingImage && existingImage.complete && (existingImage.naturalWidth > 0 || existingImage.naturalHeight > 0)) {
                    existingPreload.didLoad = true;
                    return Promise.resolve(true);
                }

                existingPreloads = existingPreloads.filter((entry) => entry !== existingPreload);
                releasePreload(existingPreload);
            }

            const preloadImage = new Image();
            const preloadEntry = {
                url,
                image: preloadImage,
                didLoad: false,
                promise: null,
                timeoutId: null,
                cancel: null
            };
            let finishPreload = null;
            const preloadPromise = new Promise((resolve) => {
                let didFinish = false;
                const finish = (didLoad) => {
                    if (didFinish) {
                        return;
                    }
                    didFinish = true;
                    if (preloadEntry.timeoutId) {
                        clearTimeout(preloadEntry.timeoutId);
                        preloadEntry.timeoutId = null;
                    }
                    preloadImage.onload = null;
                    preloadImage.onerror = null;
                    preloadEntry.didLoad = didLoad;
                    preloadEntry.promise = null;
                    preloadEntry.cancel = null;
                    resolve(didLoad);
                };
                finishPreload = finish;

                preloadEntry.timeoutId = setTimeout(() => finish(false), 8000);
                preloadImage.onload = () => finish(true);
                preloadImage.onerror = () => finish(false);
            });
            preloadEntry.promise = preloadPromise;
            preloadEntry.cancel = () => {
                preloadImage.onload = null;
                preloadImage.onerror = null;
                preloadImage.removeAttribute("src");
                if (finishPreload) {
                    finishPreload(false);
                }
            };

            preloadImage.decoding = "async";
            preloadImage.src = url;
            Promise.resolve().then(() => {
                if (preloadImage.complete && finishPreload) {
                    finishPreload(preloadImage.naturalWidth > 0 || preloadImage.naturalHeight > 0);
                }
            });

            const nextPreloads = existingPreloads.concat(preloadEntry);
            const evictedPreloads = nextPreloads.slice(0, Math.max(0, nextPreloads.length - maximumRetainedPreloads));
            window.__downloadableTokenImagePreloads = nextPreloads.slice(-maximumRetainedPreloads);
            evictedPreloads.forEach(releasePreload);
            return preloadPromise;
        }
        """
    }

    private static func htmlDocument(_ html: String, insertingBaseURL baseURL: String?) -> String {
        guard let baseURL,
              !baseURL.isEmpty,
              openingTagRange("base", in: html) == nil else {
            return html
        }

        let baseElement = "<base href=\"\(htmlAttributeValue(baseURL))\">"
        if let headRange = openingTagRange("head", in: html) {
            var html = html
            html.insert(contentsOf: "\n\(baseElement)", at: headRange.upperBound)
            return html
        }

        if let htmlRange = openingTagRange("html", in: html) {
            var html = html
            html.insert(contentsOf: "\n<head>\(baseElement)</head>", at: htmlRange.upperBound)
            return html
        }

        return "\(baseElement)\n\(html)"
    }

    private static func htmlDocumentAspectFitJavaScript(contentSize: CGSize?) -> String {
        guard let contentSize,
              contentSize.width > 0,
              contentSize.height > 0,
              contentSize.width.isFinite,
              contentSize.height.isFinite else {
            return ""
        }

        return """
        const tokenDocumentAspectWidth = \(javaScriptNumberLiteral(Double(contentSize.width)));
        const tokenDocumentAspectHeight = \(javaScriptNumberLiteral(Double(contentSize.height)));
        const tokenDocumentAspectRatio = tokenDocumentAspectWidth / tokenDocumentAspectHeight;
        const tokenDocument = document.getElementById("tokenDocument");

        function layoutTokenDocument() {
            const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
            const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
            if (!viewportWidth || !viewportHeight || !tokenDocumentAspectRatio) {
                tokenDocument.style.width = "100%";
                tokenDocument.style.height = "100%";
                return;
            }

            let width = viewportWidth;
            let height = width / tokenDocumentAspectRatio;
            if (height > viewportHeight) {
                height = viewportHeight;
                width = height * tokenDocumentAspectRatio;
            }

            tokenDocument.style.width = `${width}px`;
            tokenDocument.style.height = `${height}px`;
        }

        window.addEventListener("resize", layoutTokenDocument);
        layoutTokenDocument();
        requestAnimationFrame(layoutTokenDocument);
        """
    }

    private static func openingTagRange(_ tagName: String, in html: String) -> Range<String.Index>? {
        html.range(
            of: "<\(tagName)(?=\\s|/?>)[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func htmlAttributeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func javaScriptStringLiteral(_ value: String?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              var literal = String(data: data, encoding: .utf8) else {
            return "null"
        }
        literal = literal
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return literal
    }

    private static func javaScriptNumberLiteral(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(value)
    }
}

enum DownloadableTokenHTMLLayout {
    static func rootSVGViewBoxSize(in html: String) -> CGSize? {
        guard let svgOpeningTag = rootSVGOpeningTag(in: html) else { return nil }

        if let viewBox = attribute("viewBox", in: svgOpeningTag),
           let viewBoxSize = size(fromViewBox: viewBox) {
            return viewBoxSize
        }

        guard let width = absoluteLengthAttribute("width", in: svgOpeningTag),
              let height = absoluteLengthAttribute("height", in: svgOpeningTag),
              width > 0,
              height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private static func size(fromViewBox viewBox: String) -> CGSize? {
        let components = viewBox
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .compactMap { Double($0) }

        guard components.count == 4,
              components.allSatisfy({ $0.isFinite }),
              components[2] > 0,
              components[3] > 0 else {
            return nil
        }

        return CGSize(width: components[2], height: components[3])
    }

    private static func rootSVGOpeningTag(in html: String) -> String? {
        let patterns = [
            "<body(?=\\s|>)[^>]*>\\s*(<svg(?=\\s|/?>)[^>]*>)",
            "^\\s*(?:(?:<\\?xml\\b[^>]*\\?>|<!doctype\\b[^>]*>)\\s*)*(<svg(?=\\s|/?>)[^>]*>)",
        ]

        for pattern in patterns {
            if let match = firstCapturedMatch(pattern: pattern, in: html) {
                return match
            }
        }

        return nil
    }

    private static func firstCapturedMatch(pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[capturedRange])
    }

    private static func absoluteLengthAttribute(_ name: String, in openingTag: String) -> CGFloat? {
        guard let value = attribute(name, in: openingTag)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        guard let regex = try? NSRegularExpression(
            pattern: "^([-+]?(?:\\d+\\.?\\d*|\\.\\d+))(?:px)?$",
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let numberRange = Range(match.range(at: 1), in: value),
              let number = Double(value[numberRange]),
              number.isFinite else {
            return nil
        }

        return CGFloat(number)
    }

    private static func attribute(_ name: String, in openingTag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?:^|[\\s<])\(escapedName)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(openingTag.startIndex..<openingTag.endIndex, in: openingTag)
        guard let match = regex.firstMatch(in: openingTag, range: range) else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            guard let capturedRange = Range(match.range(at: index), in: openingTag) else {
                continue
            }
            return String(openingTag[capturedRange])
        }

        return nil
    }
}
