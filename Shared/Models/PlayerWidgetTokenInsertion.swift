// ∅ 2026 lil org

import Foundation

struct PlayerWidgetTokenInsertion: Hashable, Codable {
    let insertedToken: GeneratedToken
    let insertedTokenIndex: Int
    let anchorProgress: PlayerViewingProgress
    let isAnchorProgressResolved: Bool

    init(
        insertedToken: GeneratedToken,
        insertedTokenIndex: Int,
        anchorProgress: PlayerViewingProgress,
        isAnchorProgressResolved: Bool
    ) {
        self.insertedToken = insertedToken
        self.insertedTokenIndex = insertedTokenIndex
        self.anchorProgress = anchorProgress
        self.isAnchorProgressResolved = isAnchorProgressResolved
    }

    private enum CodingKeys: String, CodingKey {
        case insertedToken
        case insertedTokenIndex
        case anchorProgress
        case isAnchorProgressResolved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        insertedToken = try container.decode(GeneratedToken.self, forKey: .insertedToken)
        insertedTokenIndex = try container.decode(Int.self, forKey: .insertedTokenIndex)
        anchorProgress = try container.decode(PlayerViewingProgress.self, forKey: .anchorProgress)
        // Legacy payloads cannot prove that a synthesized zero anchor was valid.
        isAnchorProgressResolved = try container.decodeIfPresent(
            Bool.self,
            forKey: .isAnchorProgressResolved
        ) ?? false
    }

    var collectionId: String {
        anchorProgress.collectionId
    }

    var anchorTokenId: String {
        anchorProgress.tokenId
    }

    var anchorTokenIndex: Int {
        anchorProgress.tokenIndex
    }

    func tokenIndex(for pagePosition: PlayerPagePosition) -> Int? {
        if pagePosition.position == 0 {
            return insertedTokenIndex
        }
        return tokenIndex(adjacentToInsertedTokenBy: pagePosition.position)
    }

    func pagePosition(forTokenIndex tokenIndex: Int) -> PlayerPagePosition {
        if tokenIndex < anchorTokenIndex {
            return PlayerPagePosition(position: tokenIndex - anchorTokenIndex)
        }
        return PlayerPagePosition(position: tokenIndex - anchorTokenIndex + 1)
    }

    func tokenIndex(adjacentToInsertedTokenBy offset: Int) -> Int? {
        let relativeIndex = offset < 0 ? offset : offset - 1
        let (tokenIndex, overflow) = anchorTokenIndex.addingReportingOverflow(relativeIndex)
        return overflow ? nil : tokenIndex
    }

    func automaticAnchorProgress() -> PlayerViewingProgress? {
        guard isAnchorProgressResolved else { return nil }

        return PlayerViewingProgress(
            collectionId: anchorProgress.collectionId,
            collectionName: anchorProgress.collectionName,
            tokenId: anchorProgress.tokenId,
            tokenIndex: anchorProgress.tokenIndex,
            tokenCount: anchorProgress.tokenCount,
            updatedAt: Date(),
            hasViewedToEnd: anchorProgress.hasViewedToEnd
        )
    }
}
