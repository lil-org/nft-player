// ∅ 2026 lil org

import UIKit

@MainActor
enum MobilePlayerCollectionBrowserTransitionSupport {
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
        in viewportView: UIView
    ) -> [MobilePlayerBrowserGridCarryoverSource] {
        cells.map { cell in
            MobilePlayerBrowserGridCarryoverSource(
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
        resolveContent: (
            MobilePlayerBrowserGridCarryoverSource?,
            Int,
            MobilePlayerCollectionBrowserCell
        ) -> MobilePlayerBrowserCarryoverContent?
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
                cell.clearTransitionContent()
                cell.setTransitionPlaceholderTone(false)
                continue
            }
            eligibleCells.append((indexPath, cell))
        }
        let selectedItems = PlayerBrowserGridCarryoverSelection
            .selectedItemIndices(
                candidateItemIndices: eligibleCells.map { $0.indexPath.item },
                anchorItemIndex: anchorItemIndex
            )
        var holdsPlaceholderTone = false
        for (indexPath, cell) in eligibleCells where
            selectedItems.contains(indexPath.item) {
            guard let cellRect = PlayerBrowserGridGeometry.visibleRect(
                cell.convert(cell.bounds, to: viewportView),
                clippedTo: viewportView.bounds
            ) else {
                continue
            }
            let bestSource = PlayerBrowserGridCarryoverSelection.bestSource(
                for: cellRect,
                among: sources
            )
            guard let content = resolveContent(
                bestSource,
                indexPath.item,
                cell
            ) else {
                if cell.needsCarryoverContent {
                    cell.setTransitionPlaceholderTone(true)
                    holdsPlaceholderTone = true
                }
                continue
            }
            cell.setCarryoverContent(content)
            cell.fadeOutCarryoverContentIfBaseReady()
        }
        return holdsPlaceholderTone
    }
}
