// ∅ 2026 lil org

import XCTest
@testable import NftPlayerSyncCore

final class PlayerCollectionBrowseMediaWindowRefreshPolicyTests: XCTestCase {
    private func shouldRefresh(
        previousTokenIndex: Int?,
        nextTokenIndex: Int,
        prefetchStride: Int = 25,
        force: Bool = false
    ) -> Bool {
        PlayerCollectionBrowseMediaWindowPolicy.shouldRefresh(
            previousTokenIndex: previousTokenIndex,
            nextTokenIndex: nextTokenIndex,
            prefetchStride: prefetchStride,
            force: force
        )
    }

    func testMissingPreviousTokenAndForceRefresh() {
        XCTAssertTrue(shouldRefresh(
            previousTokenIndex: nil,
            nextTokenIndex: 10
        ))
        XCTAssertTrue(shouldRefresh(
            previousTokenIndex: 10,
            nextTokenIndex: 10,
            force: true
        ))
    }

    func testCommittedOriginBoundsDeferredRefreshToOneStride() {
        var previousTokenIndex: Int?
        var preparedTokenIndices = [Int]()

        for tokenIndex in [0, 5, 10, 20, 24, 25, 30, 49, 50] {
            guard shouldRefresh(
                previousTokenIndex: previousTokenIndex,
                nextTokenIndex: tokenIndex
            ) else {
                continue
            }
            previousTokenIndex = tokenIndex
            preparedTokenIndices.append(tokenIndex)
        }

        XCTAssertEqual(preparedTokenIndices, [0, 25, 50])
    }

    func testStrideBoundaryRefreshesInEitherDirection() {
        XCTAssertFalse(shouldRefresh(
            previousTokenIndex: 50,
            nextTokenIndex: 26
        ))
        XCTAssertTrue(shouldRefresh(
            previousTokenIndex: 50,
            nextTokenIndex: 25
        ))
        XCTAssertFalse(shouldRefresh(
            previousTokenIndex: 50,
            nextTokenIndex: 74
        ))
        XCTAssertTrue(shouldRefresh(
            previousTokenIndex: 50,
            nextTokenIndex: 75
        ))
    }

    func testRefreshStrideUsesMediaWindowNormalization() {
        XCTAssertFalse(shouldRefresh(
            previousTokenIndex: 0,
            nextTokenIndex: 24,
            prefetchStride: 100
        ))
        XCTAssertTrue(shouldRefresh(
            previousTokenIndex: 0,
            nextTokenIndex: 25,
            prefetchStride: 100
        ))
        for prefetchStride in [0, -1] {
            XCTAssertFalse(shouldRefresh(
                previousTokenIndex: 0,
                nextTokenIndex: 0,
                prefetchStride: prefetchStride
            ))
            XCTAssertTrue(shouldRefresh(
                previousTokenIndex: 0,
                nextTokenIndex: 1,
                prefetchStride: prefetchStride
            ))
        }
    }

    func testExtremeTokenDistancesRefreshWithoutOverflow() {
        let transitions = [
            (Int.min, Int.max),
            (Int.max, Int.min),
            (0, Int.min),
        ]

        for transition in transitions {
            XCTAssertTrue(shouldRefresh(
                previousTokenIndex: transition.0,
                nextTokenIndex: transition.1
            ))
        }
    }
}
