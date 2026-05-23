// ∅ 2026 lil org

import Foundation

struct PlayerCoordinate: Hashable {
    let x: Int
    let y: Int
}

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

    func tokenIndex(for coordinate: PlayerCoordinate) -> Int? {
        guard coordinate.y == 0 else { return nil }
        if coordinate.x == 0 {
            return insertedTokenIndex
        }
        return anchorTokenIndex + (coordinate.x < 0 ? coordinate.x : coordinate.x - 1)
    }

    func coordinateX(forTokenIndex tokenIndex: Int) -> Int {
        if tokenIndex < anchorTokenIndex {
            return tokenIndex - anchorTokenIndex
        }
        return tokenIndex - anchorTokenIndex + 1
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
