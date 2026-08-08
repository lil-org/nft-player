// ∅ 2026 lil org

import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridSourceCoverageTests: XCTestCase {

    func testDetailCapPartitions119120And121Representations() {
        for representationCount in [119, 120, 121] {
            let representations = (0..<representationCount).map {
                PlayerBrowserGridSourceRepresentation(id: $0, sourceItem: $0)
            }
            let selectedSourceItems = Set(PlayerBrowserGridDetailPlan(
                candidateItemIndices: Array(0..<representationCount),
                anchorItemIndex: representationCount / 2,
                maximumCount: 120
            ).itemIndices)
            let preparedRepresentationIDs = Set(representations.map(\.id))
            let plan = PlayerBrowserGridSourceCoveragePlan(
                representations: representations,
                selectedSourceItems: selectedSourceItems,
                preparedRepresentationIDs: preparedRepresentationIDs,
                destinationBySourceItem: { $0 + 1_000 }
            )

            XCTAssertEqual(
                plan.readyDestinationByRepresentation.count,
                min(representationCount, 120)
            )
            XCTAssertEqual(
                plan.fallbackRepresentationIDs,
                Set(0..<representationCount).subtracting(selectedSourceItems)
            )
            XCTAssertEqual(
                plan.coveredDestinationItems,
                Set(selectedSourceItems.map { $0 + 1_000 })
            )
        }
    }

    func testDuplicateRepresentationsHaveIndependentReadiness() {
        let representations = [
            PlayerBrowserGridSourceRepresentation(id: 1, sourceItem: 7),
            PlayerBrowserGridSourceRepresentation(id: 2, sourceItem: 7),
        ]
        let plan = PlayerBrowserGridSourceCoveragePlan(
            representations: representations,
            selectedSourceItems: [7],
            preparedRepresentationIDs: [1],
            destinationBySourceItem: { $0 * 10 }
        )

        XCTAssertEqual(plan.readyDestinationByRepresentation, [1: 70])
        XCTAssertEqual(plan.fallbackRepresentationIDs, [2])
        XCTAssertEqual(plan.coveredDestinationItems, [70])
    }

    func testUnselectedUnpreparedAndUnmappedRepresentationsAreFallback() {
        let representations = [
            PlayerBrowserGridSourceRepresentation(id: 1, sourceItem: 10),
            PlayerBrowserGridSourceRepresentation(id: 2, sourceItem: 20),
            PlayerBrowserGridSourceRepresentation(id: 3, sourceItem: 30),
            PlayerBrowserGridSourceRepresentation(id: 4, sourceItem: 40),
        ]
        let destinationBySourceItem = [10: 100, 20: 200, 30: 300]
        let plan = PlayerBrowserGridSourceCoveragePlan(
            representations: representations,
            selectedSourceItems: [10, 20, 40],
            preparedRepresentationIDs: [1, 3, 4],
            destinationBySourceItem: { destinationBySourceItem[$0] }
        )

        XCTAssertEqual(plan.readyDestinationByRepresentation, [1: 100])
        XCTAssertEqual(plan.fallbackRepresentationIDs, [2, 3, 4])
        XCTAssertEqual(plan.coveredDestinationItems, [100])
    }

    func testMissingMappingCanBecomeReadyInANewPlan() {
        let representations = [
            PlayerBrowserGridSourceRepresentation(id: 1, sourceItem: 7),
        ]
        var destination: Int? = nil
        let missingPlan = PlayerBrowserGridSourceCoveragePlan(
            representations: representations,
            selectedSourceItems: [7],
            preparedRepresentationIDs: [1],
            destinationBySourceItem: { _ in destination }
        )

        destination = 70
        let mappedPlan = PlayerBrowserGridSourceCoveragePlan(
            representations: representations,
            selectedSourceItems: [7],
            preparedRepresentationIDs: [1],
            destinationBySourceItem: { _ in destination }
        )

        XCTAssertTrue(missingPlan.readyDestinationByRepresentation.isEmpty)
        XCTAssertEqual(missingPlan.fallbackRepresentationIDs, [1])
        XCTAssertTrue(missingPlan.coveredDestinationItems.isEmpty)
        XCTAssertEqual(mappedPlan.readyDestinationByRepresentation, [1: 70])
        XCTAssertTrue(mappedPlan.fallbackRepresentationIDs.isEmpty)
        XCTAssertEqual(mappedPlan.coveredDestinationItems, [70])
    }

    func testSelectionDemotionMovesPreparedRepresentationToFallback() {
        let representations = [
            PlayerBrowserGridSourceRepresentation(id: 1, sourceItem: 7),
        ]
        let readyPlan = PlayerBrowserGridSourceCoveragePlan(
            representations: representations,
            selectedSourceItems: [7],
            preparedRepresentationIDs: [1],
            destinationBySourceItem: { $0 * 10 }
        )
        let demotedPlan = PlayerBrowserGridSourceCoveragePlan(
            representations: representations,
            selectedSourceItems: [],
            preparedRepresentationIDs: [1],
            destinationBySourceItem: { $0 * 10 }
        )

        XCTAssertEqual(readyPlan.readyDestinationByRepresentation, [1: 70])
        XCTAssertEqual(readyPlan.coveredDestinationItems, [70])
        XCTAssertTrue(demotedPlan.readyDestinationByRepresentation.isEmpty)
        XCTAssertEqual(demotedPlan.fallbackRepresentationIDs, [1])
        XCTAssertTrue(demotedPlan.coveredDestinationItems.isEmpty)
    }
}
