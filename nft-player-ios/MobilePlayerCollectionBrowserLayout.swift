import UIKit

final class MobilePlayerCollectionBrowserLayout: UICollectionViewLayout {
    private var cachedItemAttributes = [
        Int: UICollectionViewLayoutAttributes
    ]()
    private var retainedItemRange: Range<Int>?

    override var developmentLayoutDirection: UIUserInterfaceLayoutDirection {
        .leftToRight
    }

    override var flipsHorizontallyInOppositeLayoutDirection: Bool {
        true
    }

    var browserLayout: MobilePlayerBrowserLayout? {
        didSet {
            guard browserLayout != oldValue else { return }
            cachedItemAttributes.removeAll(keepingCapacity: false)
            retainedItemRange = nil
            invalidateLayout()
        }
    }

    override var collectionViewContentSize: CGSize {
        browserLayout?.contentSize ?? .zero
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        let candidateItemIndices = browserLayout?.candidateItemIndices(
            intersecting: rect
        ) ?? 0..<0
        retainCandidateWindow(candidateItemIndices)
        return candidateItemIndices
            .compactMap { itemIndex in
                let indexPath = IndexPath(item: itemIndex, section: 0)
                guard let attributes = layoutAttributesForItem(at: indexPath),
                      attributes.frame.intersects(rect) else {
                    return nil
                }
                return attributes
            }
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0,
              let browserLayout,
              (0..<browserLayout.itemCount).contains(indexPath.item) else {
            return nil
        }
        if let attributes = cachedItemAttributes[indexPath.item] {
            return attributes
        }
        guard let frame = browserLayout.itemFrame(at: indexPath.item) else {
            return nil
        }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame
        if let retainedItemRange {
            if retainedItemRange.contains(indexPath.item) {
                cachedItemAttributes[indexPath.item] = attributes
            }
        } else {
            cachedItemAttributes.removeAll(keepingCapacity: true)
            cachedItemAttributes[indexPath.item] = attributes
        }
        return attributes
    }

    private func retainCandidateWindow(
        _ candidateItemIndices: Range<Int>
    ) {
        guard !candidateItemIndices.isEmpty,
              let browserLayout,
              candidateItemIndices.lowerBound >= 0,
              candidateItemIndices.upperBound <= browserLayout.itemCount else {
            return
        }
        if let retainedItemRange,
           retainedItemRange.lowerBound <= candidateItemIndices.lowerBound,
           retainedItemRange.upperBound >= candidateItemIndices.upperBound {
            return
        }

        let windowCount = candidateItemIndices.count
        let lowerBound = candidateItemIndices.lowerBound - min(
            candidateItemIndices.lowerBound,
            windowCount
        )
        let availableUpperMargin = browserLayout.itemCount
            - candidateItemIndices.upperBound
        let upperBound = candidateItemIndices.upperBound + min(
            availableUpperMargin,
            windowCount
        )
        let nextRetainedItemRange = lowerBound..<upperBound
        cachedItemAttributes = cachedItemAttributes.filter {
            nextRetainedItemRange.contains($0.key)
        }
        retainedItemRange = nextRetainedItemRange
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        collectionView?.bounds.size != newBounds.size
    }
}
