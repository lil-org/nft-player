// ∅ 2026 lil org

import Foundation

struct PlayerWidgetTokenInsertion: Hashable, Codable {
    let insertedToken: GeneratedToken
    let insertedTokenIndex: Int
    let anchorProgress: PlayerViewingProgress

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

    func tokenIndex(adjacentToInsertedTokenBy offset: Int) -> Int {
        anchorTokenIndex + (offset < 0 ? offset : offset - 1)
    }

    func updatedAnchorProgress() -> PlayerViewingProgress {
        PlayerViewingProgress(
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
