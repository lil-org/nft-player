// ∅ 2026 lil org

import UIKit

protocol MobilePlaybackControllerDisplay: AnyObject {
    
    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentCoordinate() -> (Int, Int)
    
}

enum PlaybackNavigationDirection {
    case up, down, back, forward, nextCollection, restartCollection
}

struct MobileViewingProgress: Codable, Hashable {
    let collectionId: String
    let collectionName: String
    let tokenId: String
    let tokenIndex: Int
    let tokenCount: Int
    let updatedAt: Date
    var hasViewedToEnd: Bool

    init(
        collectionId: String,
        collectionName: String,
        tokenId: String,
        tokenIndex: Int,
        tokenCount: Int,
        updatedAt: Date,
        hasViewedToEnd: Bool = false
    ) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.tokenId = tokenId
        self.tokenIndex = tokenIndex
        self.tokenCount = tokenCount
        self.updatedAt = updatedAt
        self.hasViewedToEnd = hasViewedToEnd
    }

    enum CodingKeys: String, CodingKey {
        case collectionId
        case collectionName
        case tokenId
        case tokenIndex
        case tokenCount
        case updatedAt
        case hasViewedToEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collectionId = try container.decode(String.self, forKey: .collectionId)
        collectionName = try container.decode(String.self, forKey: .collectionName)
        tokenId = try container.decode(String.self, forKey: .tokenId)
        tokenIndex = try container.decode(Int.self, forKey: .tokenIndex)
        tokenCount = try container.decode(Int.self, forKey: .tokenCount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        hasViewedToEnd = try container.decodeIfPresent(Bool.self, forKey: .hasViewedToEnd) ?? false
    }

    var fraction: Double {
        guard tokenCount > 0 else { return 0 }
        return min(max(Double(tokenIndex + 1) / Double(tokenCount), 0), 1)
    }

    var percent: Int {
        guard fraction > 0 else { return 0 }
        guard !isComplete else { return 100 }
        return min(max(Int((fraction * 100).rounded(.up)), 1), 99)
    }

    var isComplete: Bool {
        tokenCount > 0 && tokenIndex >= tokenCount - 1
    }

    var hasBeenViewedToEnd: Bool {
        hasViewedToEnd || isComplete
    }

    var pageLabel: String {
        guard tokenCount > 0 else { return "" }
        return Strings.pagePosition(current: tokenIndex + 1, total: tokenCount)
    }
}

enum MobileViewingProgressStore {
    private static let progressKey = "mobileViewingProgressByCollectionId"
    private static let continueViewingCollectionIdKey = "mobileContinueViewingCollectionId"
    private static let userDefaults = UserDefaults.standard
    private static var cachedProgressByCollectionId: [String: MobileViewingProgress]?
    private static var cachedProgressData: Data?

    static func save(_ progress: MobileViewingProgress) {
        var allProgress = allProgressByCollectionId()
        var updatedProgress = progress
        updatedProgress.hasViewedToEnd = progress.hasBeenViewedToEnd || allProgress[progress.collectionId]?.hasBeenViewedToEnd == true
        allProgress[progress.collectionId] = updatedProgress
        save(allProgress)
    }

    static func progressSnapshot() -> (
        percentagesByCollectionId: [String: Int],
        viewedToEndCollectionIds: Set<String>,
        continueViewingProgress: MobileViewingProgress?
    ) {
        let progressByCollectionId = allProgressByCollectionId()
        let viewedToEndCollectionIds = Set(progressByCollectionId.compactMap { collectionId, progress in
            progress.hasBeenViewedToEnd ? collectionId : nil
        })
        return (
            progressByCollectionId.mapValues(\.percent),
            viewedToEndCollectionIds,
            continueViewingProgress(in: progressByCollectionId)
        )
    }

    static func progress(collectionId: String) -> MobileViewingProgress? {
        allProgressByCollectionId()[collectionId]
    }

    static func setContinueViewingCollectionId(_ collectionId: String) {
        userDefaults.set(collectionId, forKey: continueViewingCollectionIdKey)
    }

    static func clearContinueViewingCollectionId() {
        userDefaults.removeObject(forKey: continueViewingCollectionIdKey)
    }

    private static func continueViewingProgress(in progressByCollectionId: [String: MobileViewingProgress]) -> MobileViewingProgress? {
        guard let collectionId = userDefaults.string(forKey: continueViewingCollectionIdKey),
              let progress = progressByCollectionId[collectionId],
              !progress.isComplete else {
            return nil
        }
        return progress
    }

    private static func allProgressByCollectionId() -> [String: MobileViewingProgress] {
        let storedData = userDefaults.data(forKey: progressKey)
        if let cachedProgressByCollectionId, cachedProgressData == storedData {
            return cachedProgressByCollectionId
        }

        guard let storedData,
              let progress = try? JSONDecoder().decode([String: MobileViewingProgress].self, from: storedData) else {
            cachedProgressByCollectionId = [:]
            cachedProgressData = storedData
            return [:]
        }
        cachedProgressByCollectionId = progress
        cachedProgressData = storedData
        return progress
    }

    private static func save(_ progress: [String: MobileViewingProgress]) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        cachedProgressByCollectionId = progress
        cachedProgressData = data
        userDefaults.set(data, forKey: progressKey)
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
    }
    
    func getToken(uuid: UUID, coordinate: PlayerCoordinate) -> GeneratedToken {
        dataSource(uuid: uuid)?.getToken(coordinate: coordinate) ?? .empty
    }

    func canRender(uuid: UUID, coordinate: PlayerCoordinate) -> Bool {
        dataSource(uuid: uuid)?.canRender(coordinate: coordinate) ?? false
    }

    func markViewed(uuid: UUID, coordinate: PlayerCoordinate) -> MobileViewingProgress? {
        guard let progress = dataSource(uuid: uuid)?.progress(coordinate: coordinate) else { return nil }
        MobileViewingProgressStore.save(progress)
        updateContinueViewingCollection(for: progress, uuid: uuid)
        return progress
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

private class GeneratedTokensDataSource {
    
    private let initialCollectionId: String?
    private let specificInitialToken: GeneratedToken?
    private let initialTokenId: String?
    
    init(initialCollectionId: String?, specificInitialToken: GeneratedToken?, initialTokenId: String?) {
        self.initialCollectionId = initialCollectionId
        self.specificInitialToken = specificInitialToken
        self.initialTokenId = initialTokenId
    }
    
    private var collectionIds = [Int: String]()
    private var collectionBaseTokenIndices = [Int: Int]()
    
    private var latestToken: GeneratedToken?
    private var latestCoordinate: PlayerCoordinate?
    
    func pushToken(_ token: GeneratedToken, coordinate: PlayerCoordinate, sameCollection: Bool) {
        let newCoordinate = sameCollection
            ? PlayerCoordinate(x: coordinate.x + 1, y: coordinate.y)
            : PlayerCoordinate(x: 0, y: coordinate.y + 1)
        let tokenIndex = TokenGenerator.tokenIndex(specificCollectionId: token.fullCollectionId, tokenId: token.id) ?? 0
        collectionIds[newCoordinate.y] = token.fullCollectionId
        collectionBaseTokenIndices[newCoordinate.y] = tokenIndex - newCoordinate.x
        latestToken = nil
        latestCoordinate = nil
    }

    func canRender(coordinate: PlayerCoordinate) -> Bool {
        guard let collectionId = collectionId(verticalIndex: coordinate.y),
              let tokenIndex = tokenIndex(coordinate: coordinate) else { return false }
        return tokenIndex >= 0 && tokenIndex < TokenGenerator.tokenCount(specificCollectionId: collectionId)
    }

    func horizontalCoordinateForTokenIndex(_ tokenIndex: Int, verticalIndex: Int) -> Int {
        ensureCollectionLoaded(verticalIndex: verticalIndex)
        return tokenIndex - (collectionBaseTokenIndices[verticalIndex] ?? 0)
    }

    func progress(coordinate: PlayerCoordinate) -> MobileViewingProgress? {
        let token = getToken(coordinate: coordinate)
        guard !token.fullCollectionId.isEmpty,
              let tokenIndex = tokenIndex(coordinate: coordinate) else { return nil }

        let tokenCount = TokenGenerator.tokenCount(specificCollectionId: token.fullCollectionId)
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
              let token = TokenGenerator.generateToken(specificCollectionId: collectionId, tokenIndex: tokenIndex) else {
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
                specificInitialToken?.fullCollectionId ?? initialCollectionId ?? TokenGenerator.nextShuffledCollectionId(),
                specificInitialToken?.id ?? initialTokenId
            )
        } else {
            collection = (TokenGenerator.nextShuffledCollectionId(), nil)
        }

        guard let collectionId = collection.id else { return nil }
        collectionIds[verticalIndex] = collectionId

        let baseTokenIndex: Int
        if let requestedTokenId = collection.requestedTokenId,
           let requestedIndex = TokenGenerator.tokenIndex(specificCollectionId: collectionId, tokenId: requestedTokenId) {
            baseTokenIndex = requestedIndex
        } else {
            baseTokenIndex = 0
        }
        collectionBaseTokenIndices[verticalIndex] = baseTokenIndex
        return collectionId
    }

}
