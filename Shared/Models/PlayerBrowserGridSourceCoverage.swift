// ∅ 2026 lil org

import Foundation

nonisolated struct PlayerBrowserGridSourceRepresentation<ID: Hashable>: Hashable {
    let id: ID
    let sourceItem: Int
}

nonisolated struct PlayerBrowserGridSourceCoveragePlan<ID: Hashable>: Equatable {
    let readyDestinationByRepresentation: [ID: Int]
    let fallbackRepresentationIDs: Set<ID>
    let coveredDestinationItems: Set<Int>

    static var empty: Self {
        Self(
            representations: [],
            selectedSourceItems: [],
            preparedRepresentationIDs: [],
            destinationBySourceItem: { _ in nil }
        )
    }

    init(
        representations: [PlayerBrowserGridSourceRepresentation<ID>],
        selectedSourceItems: Set<Int>,
        preparedRepresentationIDs: Set<ID>,
        destinationBySourceItem: (Int) -> Int?
    ) {
        var readyDestinationByRepresentation = [ID: Int]()
        var fallbackRepresentationIDs = Set(representations.map(\.id))
        var coveredDestinationItems = Set<Int>()

        for representation in representations where
            selectedSourceItems.contains(representation.sourceItem)
                && preparedRepresentationIDs.contains(representation.id) {
            guard let destinationItem = destinationBySourceItem(
                representation.sourceItem
            ) else {
                continue
            }
            readyDestinationByRepresentation[representation.id] = destinationItem
            fallbackRepresentationIDs.remove(representation.id)
            coveredDestinationItems.insert(destinationItem)
        }

        self.readyDestinationByRepresentation = readyDestinationByRepresentation
        self.fallbackRepresentationIDs = fallbackRepresentationIDs
        self.coveredDestinationItems = coveredDestinationItems
    }
}

extension PlayerBrowserGridSourceRepresentation: Sendable where ID: Sendable {}

extension PlayerBrowserGridSourceCoveragePlan: Sendable where ID: Sendable {}
