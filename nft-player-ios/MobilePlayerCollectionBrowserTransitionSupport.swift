// ∅ 2026 lil org

import UIKit

@MainActor
enum MobilePlayerCollectionBrowserTransitionSupport {
    private struct CarryoverDestination {
        let item: Int
        let cell: MobilePlayerCollectionBrowserCell
        let rect: CGRect
    }

    static func itemIntersectsViewport(
        at indexPath: IndexPath,
        cell: UICollectionViewCell?,
        collectionView: UICollectionView,
        viewportView: UIView
    ) -> Bool {
        let frameInViewport: CGRect
        if let cell, cell.superview != nil {
            frameInViewport = cell.convert(cell.bounds, to: viewportView)
        } else if let frame = collectionView.collectionViewLayout
            .layoutAttributesForItem(at: indexPath)?.frame {
            frameInViewport = collectionView.convert(frame, to: viewportView)
        } else {
            return false
        }
        return PlayerBrowserGridGeometry.visibleRect(
            frameInViewport,
            clippedTo: viewportView.bounds
        ) != nil
    }

    static func captureSources(
        from cells: [MobilePlayerCollectionBrowserCell],
        in viewportView: UIView,
        destinationItem: (MobilePlayerCollectionBrowserCell) -> Int? = { _ in
            nil
        }
    ) -> [MobilePlayerBrowserGridCarryoverSource] {
        cells.map { cell in
            MobilePlayerBrowserGridCarryoverSource(
                destinationItem: destinationItem(cell),
                viewportRect: cell.convert(cell.bounds, to: viewportView),
                content: cell.carryoverSourceContent
            )
        }
    }

    static func installCarryover(
        sources: [MobilePlayerBrowserGridCarryoverSource],
        in collectionView: UICollectionView,
        viewportView: UIView,
        anchorItemIndex: Int?,
        hasImageSources: (Int) -> Bool,
        fallbackContent: (
            Int,
            MobilePlayerCollectionBrowserCell
        ) -> MobilePlayerBrowserCarryoverContent? = { _, _ in nil }
    ) -> Bool {
        var eligibleCells = [(
            indexPath: IndexPath,
            cell: MobilePlayerCollectionBrowserCell
        )]()
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(
                at: indexPath
            ) as? MobilePlayerCollectionBrowserCell else {
                continue
            }
            guard hasImageSources(indexPath.item) else {
                cell.finishTransitionContent()
                cell.setTransitionPlaceholderTone(false)
                continue
            }
            eligibleCells.append((indexPath, cell))
        }
        let prioritizedItems = PlayerBrowserGridCarryoverSelection
            .prioritizedItemIndices(
                candidateItemIndices: eligibleCells.map { $0.indexPath.item },
                anchorItemIndex: anchorItemIndex
            )
        var eligibleCellByItem = [Int: (
            indexPath: IndexPath,
            cell: MobilePlayerCollectionBrowserCell
        )]()
        for entry in eligibleCells {
            eligibleCellByItem[entry.indexPath.item] = entry
        }
        let prioritizedCells = prioritizedItems.compactMap {
            eligibleCellByItem[$0]
        }
        var assignedSourceIndicesByItem = [Int: [Int]]()
        var assignedContentSourceIndicesByItem = [Int: [Int]]()
        var wildcardContentSourceIndices = [Int]()
        for sourceIndex in sources.indices {
            if let destinationItem = sources[sourceIndex].destinationItem {
                assignedSourceIndicesByItem[destinationItem, default: []]
                    .append(sourceIndex)
                if sources[sourceIndex].content != nil {
                    assignedContentSourceIndicesByItem[
                        destinationItem,
                        default: []
                    ].append(sourceIndex)
                }
            } else if sources[sourceIndex].content != nil {
                wildcardContentSourceIndices.append(sourceIndex)
            }
        }
        func bestSourceIndex(
            for cellRect: CGRect,
            among sourceIndices: [Int]
        ) -> Int? {
            PlayerBrowserGridCarryoverSelection.bestSource(
                for: cellRect,
                among: sourceIndices,
                maximumCount: sourceIndices.count,
                sourceRect: { sourceIndex in
                    sources[sourceIndex].viewportRect
                }
            )
        }
        let destinations: [CarryoverDestination]
        destinations = prioritizedCells.compactMap { entry in
            let (indexPath, cell) = entry
            guard let rect = PlayerBrowserGridGeometry.visibleRect(
                cell.convert(cell.bounds, to: viewportView),
                clippedTo: viewportView.bounds
            ) else {
                return nil
            }
            return CarryoverDestination(
                item: indexPath.item,
                cell: cell,
                rect: rect
            )
        }
        var resolvedContentByItem = [Int: MobilePlayerBrowserCarryoverContent]()
        var triedFallbackItems = Set<Int>()
        for destination in destinations {
            let viableAssignedSourceIndex = bestSourceIndex(
                for: destination.rect,
                among: assignedSourceIndicesByItem[destination.item] ?? []
            )
            let assignedContentSourceIndex = bestSourceIndex(
                for: destination.rect,
                among: assignedContentSourceIndicesByItem[destination.item] ?? []
            )
            if let content = assignedContentSourceIndex.flatMap({
                sources[$0].content
            }) {
                resolvedContentByItem[destination.item] = content
            } else if viableAssignedSourceIndex != nil {
                triedFallbackItems.insert(destination.item)
                resolvedContentByItem[destination.item] = fallbackContent(
                    destination.item,
                    destination.cell
                )
            }
        }
        let wildcardSourceByItem = wildcardSourceAssignments(
            sources: sources,
            sourceIndices: wildcardContentSourceIndices,
            destinations: destinations.filter {
                resolvedContentByItem[$0.item] == nil
            }
        )
        var holdsPlaceholderTone = false
        for destination in destinations {
            var resolvedContent = resolvedContentByItem[destination.item]
            if resolvedContent == nil,
               let sourceIndex = wildcardSourceByItem[destination.item] {
                resolvedContent = sources[sourceIndex].content
            }
            if resolvedContent == nil,
               !triedFallbackItems.contains(destination.item) {
                resolvedContent = fallbackContent(
                    destination.item,
                    destination.cell
                )
            }
            guard let resolvedContent else {
                if destination.cell.needsCarryoverContent {
                    destination.cell.setTransitionPlaceholderTone(true)
                    holdsPlaceholderTone = true
                }
                continue
            }
            destination.cell.setCarryoverContent(resolvedContent)
            destination.cell.fadeOutCarryoverContentIfBaseReady()
        }
        return holdsPlaceholderTone
    }

    private static func wildcardSourceAssignments(
        sources: [MobilePlayerBrowserGridCarryoverSource],
        sourceIndices: [Int],
        destinations: [CarryoverDestination]
    ) -> [Int: Int] {
        var candidatesByItem = [Int: [Int]]()
        for destination in destinations {
            let destinationArea = destination.rect.width
                * destination.rect.height
            guard destinationArea.isFinite, destinationArea > 0 else {
                continue
            }
            candidatesByItem[destination.item] = sourceIndices.compactMap {
                sourceIndex -> (index: Int, overlapArea: CGFloat)? in
                guard let overlap = PlayerBrowserGridGeometry.visibleRect(
                    sources[sourceIndex].viewportRect,
                    clippedTo: destination.rect
                ) else {
                    return nil
                }
                let overlapArea = overlap.width * overlap.height
                guard overlapArea > destinationArea / 2 else { return nil }
                return (sourceIndex, overlapArea)
            }.sorted { lhs, rhs in
                lhs.overlapArea == rhs.overlapArea
                    ? lhs.index < rhs.index
                    : lhs.overlapArea > rhs.overlapArea
            }.map(\.index)
        }

        var sourceByItem = [Int: Int]()
        var itemBySource = [Int: Int]()
        func assign(
            item: Int,
            visitedSources: inout Set<Int>
        ) -> Bool {
            for sourceIndex in candidatesByItem[item] ?? [] {
                guard itemBySource[sourceIndex] == nil,
                      visitedSources.insert(sourceIndex).inserted else {
                    continue
                }
                itemBySource[sourceIndex] = item
                sourceByItem[item] = sourceIndex
                return true
            }
            for sourceIndex in candidatesByItem[item] ?? [] {
                guard visitedSources.insert(sourceIndex).inserted,
                      let assignedItem = itemBySource[sourceIndex],
                      assign(
                          item: assignedItem,
                          visitedSources: &visitedSources
                      ) else {
                    continue
                }
                itemBySource[sourceIndex] = item
                sourceByItem[item] = sourceIndex
                return true
            }
            return false
        }

        for destination in destinations {
            var visitedSources = Set<Int>()
            _ = assign(
                item: destination.item,
                visitedSources: &visitedSources
            )
        }
        return sourceByItem
    }
}
