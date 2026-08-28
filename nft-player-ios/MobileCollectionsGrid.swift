import SwiftUI
import UIKit

private let initialCollectionItemFadeDuration: TimeInterval = 0.3
private let initialCollectionItemFadeAnimationKey = "initialGridItemFade"
private let mobileCollectionsGridScrollPositionKey = "mobileCollectionsGridScrollPosition"

private enum InfiniteCollectionsLoop {
    private static let repetitionCount = 31
    private static let middleRepetition = repetitionCount / 2
    private static let recenterThreshold = 5
    private static let initialSourceOffset = 12

    static func virtualItemCount(itemCount: Int) -> Int {
        repetitionCount * itemCount
    }

    static func repetition(for virtualIndex: Int, itemCount: Int) -> Int {
        virtualIndex / itemCount
    }

    static func sourceIndex(for virtualIndex: Int, itemCount: Int) -> Int {
        virtualIndex % itemCount
    }

    static func centeredIndex(sourceIndex: Int, itemCount: Int) -> Int {
        middleRepetition * itemCount + sourceIndex
    }

    static func centeredIndex(
        sourceIndex: Int,
        itemCount: Int,
        columnCount: Int
    ) -> Int {
        let fallbackIndex = centeredIndex(sourceIndex: sourceIndex, itemCount: itemCount)
        guard itemCount > 0,
              columnCount > 1 else {
            return fallbackIndex
        }

        var targetIndex = fallbackIndex
        for _ in 0..<min(columnCount, repetitionCount - middleRepetition) {
            guard targetIndex % columnCount != 0 else { return targetIndex }
            targetIndex += itemCount
        }

        return fallbackIndex
    }

    static func defaultInitialSourceIndex(itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        return initialSourceOffset % itemCount
    }

    static func initialScrollPosition(
        sourceIndex: Int,
        itemCount: Int,
        columnCount: Int = 1
    ) -> Int? {
        guard itemCount > 0,
              sourceIndex >= 0,
              sourceIndex < itemCount else {
            return nil
        }
        return centeredIndex(
            sourceIndex: sourceIndex,
            itemCount: itemCount,
            columnCount: columnCount
        )
    }

    static func initialSourceIndices(
        startingAt sourceIndex: Int,
        itemCount: Int,
        limit: Int
    ) -> [Int] {
        guard itemCount > 0,
              limit > 0,
              sourceIndex >= 0,
              sourceIndex < itemCount else {
            return []
        }
        return (0..<min(itemCount, limit)).map { (sourceIndex + $0) % itemCount }
    }

    static func shouldRecenter(repetition: Int) -> Bool {
        repetition <= recenterThreshold || repetition >= repetitionCount - recenterThreshold
    }
}

private struct MobileCollectionsGridScrollPosition: Codable, Equatable {
    let collectionId: String
    let sourceIndex: Int
    let offsetFractionWithinItem: Double

    init(collectionId: String, sourceIndex: Int, offsetFractionWithinItem: CGFloat) {
        self.collectionId = collectionId
        self.sourceIndex = sourceIndex
        self.offsetFractionWithinItem = Double(offsetFractionWithinItem).clamped(to: 0..<1)
    }

    var offsetFraction: CGFloat {
        guard offsetFractionWithinItem.isFinite else { return 0 }
        return CGFloat(offsetFractionWithinItem.clamped(to: 0..<1))
    }

    func resolvedSourceIndex(in items: [MobileCollectionItem]) -> Int? {
        if let collectionIndex = items.firstIndex(where: { $0.id == collectionId }) {
            return collectionIndex
        }
        guard sourceIndex >= 0, sourceIndex < items.count else { return nil }
        return sourceIndex
    }
}

private func resolvedInitialSourceIndex(
    in items: [MobileCollectionItem],
    savedPosition: MobileCollectionsGridScrollPosition?
) -> Int? {
    savedPosition?.resolvedSourceIndex(in: items)
        ?? InfiniteCollectionsLoop.defaultInitialSourceIndex(itemCount: items.count)
}

private enum MobileCollectionsGridScrollPositionStore {
    private static let userDefaults = UserDefaults.standard

    static func load() -> MobileCollectionsGridScrollPosition? {
        guard let data = userDefaults.data(forKey: mobileCollectionsGridScrollPositionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MobileCollectionsGridScrollPosition.self, from: data)
    }

    static func save(_ position: MobileCollectionsGridScrollPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        userDefaults.set(data, forKey: mobileCollectionsGridScrollPositionKey)
    }
}

enum MobileCollectionsGridInitialState {
    static func prewarmCollectionIDs(
        in collectionItems: [MobileCollectionItem],
        limit: Int
    ) -> [String] {
        guard let sourceIndex = resolvedInitialSourceIndex(
            in: collectionItems,
            savedPosition: MobileCollectionsGridScrollPositionStore.load()
        ) else {
            return []
        }

        return InfiniteCollectionsLoop
            .initialSourceIndices(
                startingAt: sourceIndex,
                itemCount: collectionItems.count,
                limit: limit
            )
            .map { collectionItems[$0].id }
    }
}

struct InfiniteCollectionsGridView: UIViewRepresentable {
    let items: [MobileCollectionItem]
    let progressByCollectionId: [String: Int]
    let viewedToEndCollectionIds: Set<String>
    let animatesInitialAppearance: Bool
    let onSelect: (MobileCollectionItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            items: [],
            progressByCollectionId: [:],
            viewedToEndCollectionIds: [],
            animatesInitialAppearance: animatesInitialAppearance,
            onSelect: onSelect
        )
    }

    func makeUIView(context: Context) -> InfiniteCollectionsGridContainerView {
        let containerView = InfiniteCollectionsGridContainerView()
        containerView.update(
            items: items,
            progressByCollectionId: progressByCollectionId,
            viewedToEndCollectionIds: viewedToEndCollectionIds,
            coordinator: context.coordinator
        )
        return containerView
    }

    func updateUIView(_ containerView: InfiniteCollectionsGridContainerView, context: Context) {
        context.coordinator.onSelect = onSelect
        containerView.update(
            items: items,
            progressByCollectionId: progressByCollectionId,
            viewedToEndCollectionIds: viewedToEndCollectionIds,
            coordinator: context.coordinator
        )
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        var items: [MobileCollectionItem]
        var progressByCollectionId: [String: Int]
        var viewedToEndCollectionIds: Set<String>
        var onSelect: (MobileCollectionItem) -> Void
        private var isRecentering = false
        private var isInitialCoverImageFadeActive = true
        private var pendingInitialCoverFadeIndexPaths = Set<IndexPath>()
        private var pendingScrollPosition: MobileCollectionsGridScrollPosition?
        private var lastSavedScrollPosition: MobileCollectionsGridScrollPosition?

        enum UpdateResult {
            case noChange
            case progressOnly
            case itemsChanged
        }

        init(
            items: [MobileCollectionItem],
            progressByCollectionId: [String: Int],
            viewedToEndCollectionIds: Set<String>,
            animatesInitialAppearance: Bool,
            onSelect: @escaping (MobileCollectionItem) -> Void
        ) {
            self.items = items
            self.progressByCollectionId = progressByCollectionId
            self.viewedToEndCollectionIds = viewedToEndCollectionIds
            self.isInitialCoverImageFadeActive = animatesInitialAppearance
            self.onSelect = onSelect
        }

        func update(
            items: [MobileCollectionItem],
            progressByCollectionId: [String: Int],
            viewedToEndCollectionIds: Set<String>
        ) -> UpdateResult {
            let itemsChanged = self.items != items
            let progressChanged = self.progressByCollectionId != progressByCollectionId
                || self.viewedToEndCollectionIds != viewedToEndCollectionIds
            guard itemsChanged || progressChanged else { return .noChange }
            self.items = items
            self.progressByCollectionId = progressByCollectionId
            self.viewedToEndCollectionIds = viewedToEndCollectionIds
            return itemsChanged ? .itemsChanged : .progressOnly
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            InfiniteCollectionsLoop.virtualItemCount(itemCount: items.count)
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CollectionGridCell.reuseIdentifier, for: indexPath)
            guard let gridCell = cell as? CollectionGridCell else { return cell }
            configureCell(gridCell, at: indexPath, in: collectionView)
            return gridCell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            onSelect(item(for: indexPath.item))
        }

        func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
            let item = item(for: indexPath.item)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let playAction = UIAction(title: Strings.play, image: UIImage(systemName: "play")) { _ in
                    self?.onSelect(item)
                }
                let artistLinkMenus = Self.artistLinkMenus(forCollectionId: item.id)
                let children: [UIMenuElement] = [playAction] + artistLinkMenus

                return UIMenu(title: item.name, children: children)
            }
        }

        private static func artistLinkMenus(forCollectionId collectionId: String) -> [UIMenu] {
            SuggestedItemsService.artists(forCollectionId: collectionId).compactMap { artist in
                let actions = artist.links.map { link in
                    UIAction(
                        title: link.title,
                        image: artistLinkImage(for: link.kind)
                    ) { _ in
                        UIApplication.shared.open(link.destination)
                    }
                }

                guard !actions.isEmpty else { return nil }
                return UIMenu(options: .displayInline, children: actions)
            }
        }

        private static func artistLinkImage(for kind: SuggestedArtistLink.Kind) -> UIImage? {
            switch kind {
            case .website:
                UIImage(systemName: "globe")
            case .x:
                UIImage(named: "XLogo")
            case .bluesky:
                UIImage(named: "BlueskyLogo")
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isRecentering,
                  let collectionView = scrollView as? UICollectionView,
                  !items.isEmpty,
                  let topIndexPath = topVisibleIndexPath(in: collectionView) else {
                return
            }

            let itemCount = items.count
            let repetition = InfiniteCollectionsLoop.repetition(for: topIndexPath.item, itemCount: itemCount)
            guard InfiniteCollectionsLoop.shouldRecenter(repetition: repetition) else {
                return
            }

            guard let topAttributes = collectionView.layoutAttributesForItem(at: topIndexPath) else {
                return
            }

            let sourceIndex = InfiniteCollectionsLoop.sourceIndex(for: topIndexPath.item, itemCount: itemCount)
            let targetIndexPath = IndexPath(
                item: InfiniteCollectionsLoop.centeredIndex(
                    sourceIndex: sourceIndex,
                    itemCount: itemCount,
                    columnCount: columnCount(in: collectionView)
                ),
                section: 0
            )
            collectionView.layoutIfNeeded()
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else {
                rememberScrollPosition(in: collectionView, topIndexPath: topIndexPath, topAttributes: topAttributes)
                return
            }

            isRecentering = true
            let offsetWithinTopItem = collectionView.contentOffset.y - topAttributes.frame.minY
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: targetAttributes.frame.minY + offsetWithinTopItem),
                animated: false
            )
            isRecentering = false
            rememberScrollPosition(in: collectionView, topIndexPath: targetIndexPath, topAttributes: targetAttributes)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, let collectionView = scrollView as? UICollectionView else { return }
            flushScrollPosition(in: collectionView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            flushScrollPosition(in: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            prefetchImages(for: indexPaths, in: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            cancelPrefetchingImages(for: indexPaths, in: collectionView)
        }

        fileprivate func setInitialScrollPosition(
            in collectionView: UICollectionView,
            savedPosition: MobileCollectionsGridScrollPosition?
        ) {
            let savedSourceIndex = savedPosition?.resolvedSourceIndex(in: items)
            let sourceIndex = savedSourceIndex
                ?? InfiniteCollectionsLoop.defaultInitialSourceIndex(itemCount: items.count)
            let restoreColumnCount = savedSourceIndex == nil ? 1 : columnCount(in: collectionView)
            guard !items.isEmpty,
                  let sourceIndex,
                  let targetIndex = InfiniteCollectionsLoop.initialScrollPosition(
                    sourceIndex: sourceIndex,
                    itemCount: items.count,
                    columnCount: restoreColumnCount
                  ) else {
                return
            }

            collectionView.layoutIfNeeded()
            let targetIndexPath = IndexPath(item: targetIndex, section: 0)
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else {
                collectionView.scrollToItem(at: targetIndexPath, at: .top, animated: false)
                return
            }

            let offsetFraction = savedSourceIndex == nil ? 0 : savedPosition?.offsetFraction ?? 0
            let offsetWithinItem = targetAttributes.frame.height * offsetFraction
            let targetContentOffset = CGPoint(x: 0, y: targetAttributes.frame.minY + offsetWithinItem)
            prepareInitialCoverFade(
                in: collectionView,
                visibleRect: CGRect(origin: targetContentOffset, size: collectionView.bounds.size)
            )
            isRecentering = true
            collectionView.setContentOffset(targetContentOffset, animated: false)
            isRecentering = false
        }

        func updateVisibleProgressCells(in collectionView: UICollectionView) {
            collectionView.indexPathsForVisibleItems.forEach { indexPath in
                guard let gridCell = collectionView.cellForItem(at: indexPath) as? CollectionGridCell else { return }
                configureCell(gridCell, at: indexPath, in: collectionView)
            }
        }

        func flushScrollPosition(in collectionView: UICollectionView) {
            if let currentPosition = scrollPosition(in: collectionView) {
                pendingScrollPosition = currentPosition
            }
            savePendingScrollPosition()
        }

        private func prepareInitialCoverFade(in collectionView: UICollectionView, visibleRect: CGRect) {
            guard isInitialCoverImageFadeActive,
                  pendingInitialCoverFadeIndexPaths.isEmpty,
                  !items.isEmpty else {
                return
            }

            let visibleIndexPaths = collectionView.collectionViewLayout
                .layoutAttributesForElements(in: visibleRect)?
                .compactMap { attributes -> IndexPath? in
                    guard attributes.representedElementCategory == .cell else { return nil }
                    return attributes.indexPath
                } ?? []

            guard !visibleIndexPaths.isEmpty else { return }
            pendingInitialCoverFadeIndexPaths = Set(visibleIndexPaths)
        }

        func finishInitialCoverFadeScheduling() {
            isInitialCoverImageFadeActive = false
            pendingInitialCoverFadeIndexPaths.removeAll()
        }

        func prefetchImages(aroundVisibleItemsIn collectionView: UICollectionView) {
            guard !items.isEmpty else { return }
            let visibleItems = collectionView.indexPathsForVisibleItems.map(\.item)
            guard let firstVisibleItem = visibleItems.min(),
                  let lastVisibleItem = visibleItems.max() else {
                return
            }

            let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let itemWidth = max(flowLayout?.itemSize.width ?? collectionView.bounds.width, 1)
            let visibleColumnCount = max(Int(collectionView.bounds.width / itemWidth), 1)
            let prefetchDistance = visibleColumnCount * 3
            let itemRange = max(firstVisibleItem - prefetchDistance, 0)...min(lastVisibleItem + prefetchDistance, collectionView.numberOfItems(inSection: 0) - 1)
            prefetchImages(
                for: itemRange.map { IndexPath(item: $0, section: 0) },
                in: collectionView
            )
        }

        private func item(for virtualIndex: Int) -> MobileCollectionItem {
            items[InfiniteCollectionsLoop.sourceIndex(for: virtualIndex, itemCount: items.count)]
        }

        private func configureCell(_ gridCell: CollectionGridCell, at indexPath: IndexPath, in collectionView: UICollectionView) {
            let item = item(for: indexPath.item)
            gridCell.configure(
                item: item,
                progressPercent: progressByCollectionId[item.id],
                hasViewedToEnd: viewedToEndCollectionIds.contains(item.id),
                coverSize: coverImageTargetSize(in: collectionView),
                displayScale: displayScale(in: collectionView),
                shouldAnimateInitialAppearance: consumeInitialCoverFade(at: indexPath)
            )
        }

        private func prefetchImages(for indexPaths: [IndexPath], in collectionView: UICollectionView) {
            guard !items.isEmpty else { return }
            let assetNames = Set(indexPaths.map { item(for: $0.item).coverAssetName })
            MobileCollectionCoverImageCache.shared.prefetch(
                assetNames: Array(assetNames),
                targetSize: coverImageTargetSize(in: collectionView),
                displayScale: displayScale(in: collectionView)
            )
        }

        private func cancelPrefetchingImages(for indexPaths: [IndexPath], in collectionView: UICollectionView) {
            guard !items.isEmpty else { return }
            let assetNames = Set(indexPaths.map { item(for: $0.item).coverAssetName })
            MobileCollectionCoverImageCache.shared.cancelPrefetch(
                assetNames: Array(assetNames),
                targetSize: coverImageTargetSize(in: collectionView),
                displayScale: displayScale(in: collectionView)
            )
        }

        private func coverImageTargetSize(in collectionView: UICollectionView) -> CGSize {
            if let itemSize = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize,
               itemSize.width > 0,
               itemSize.height > 0 {
                return itemSize
            }
            return InfiniteCollectionsGridContainerView.itemSize(forWidth: collectionView.bounds.width)
        }

        private func displayScale(in collectionView: UICollectionView) -> CGFloat {
            let scale = collectionView.traitCollection.displayScale
            return scale > 0 ? scale : UIScreen.main.scale
        }

        private func consumeInitialCoverFade(at indexPath: IndexPath) -> Bool {
            guard isInitialCoverImageFadeActive else { return false }
            return pendingInitialCoverFadeIndexPaths.remove(indexPath) != nil
        }

        private func rememberScrollPosition(
            in collectionView: UICollectionView,
            topIndexPath: IndexPath? = nil,
            topAttributes: UICollectionViewLayoutAttributes? = nil
        ) {
            guard let scrollPosition = scrollPosition(
                in: collectionView,
                topIndexPath: topIndexPath,
                topAttributes: topAttributes
            ) else { return }
            pendingScrollPosition = scrollPosition
        }

        private func savePendingScrollPosition() {
            guard let pendingScrollPosition,
                  pendingScrollPosition != lastSavedScrollPosition else {
                self.pendingScrollPosition = nil
                return
            }
            MobileCollectionsGridScrollPositionStore.save(pendingScrollPosition)
            lastSavedScrollPosition = pendingScrollPosition
            self.pendingScrollPosition = nil
        }

        private func scrollPosition(
            in collectionView: UICollectionView,
            topIndexPath: IndexPath? = nil,
            topAttributes: UICollectionViewLayoutAttributes? = nil
        ) -> MobileCollectionsGridScrollPosition? {
            guard !items.isEmpty else { return nil }
            guard let topIndexPath = topIndexPath ?? topVisibleIndexPath(in: collectionView),
                  let topAttributes = topAttributes ?? collectionView.layoutAttributesForItem(at: topIndexPath),
                  topAttributes.frame.height > 0 else {
                return nil
            }

            let sourceIndex = InfiniteCollectionsLoop.sourceIndex(for: topIndexPath.item, itemCount: items.count)
            let offsetWithinItem = collectionView.contentOffset.y - topAttributes.frame.minY
            let offsetFraction = offsetWithinItem / topAttributes.frame.height
            return MobileCollectionsGridScrollPosition(
                collectionId: items[sourceIndex].id,
                sourceIndex: sourceIndex,
                offsetFractionWithinItem: offsetFraction
            )
        }

        private func topVisibleIndexPath(in collectionView: UICollectionView) -> IndexPath? {
            collectionView.indexPathsForVisibleItems.min { $0.item < $1.item }
        }

        private func columnCount(in collectionView: UICollectionView) -> Int {
            guard collectionView.bounds.width > 0 else { return 1 }
            if let itemWidth = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize.width,
               itemWidth > 0 {
                return max(Int(round(collectionView.bounds.width / itemWidth)), 1)
            }
            let itemWidth = InfiniteCollectionsGridContainerView.itemSize(forWidth: collectionView.bounds.width).width
            return max(Int(round(collectionView.bounds.width / itemWidth)), 1)
        }
    }
}

final class InfiniteCollectionsGridContainerView: UIView {
    private let collectionView: UICollectionView
    private let initialScrollPosition = MobileCollectionsGridScrollPositionStore.load()
    private weak var coordinator: InfiniteCollectionsGridView.Coordinator?
    private var didSetInitialScrollPosition = false
    private var previousBoundsSize = CGSize.zero

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = .zero
        layout.estimatedItemSize = .zero

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)

        backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.isPrefetchingEnabled = true
        collectionView.hideAutomaticScrollEdgeEffects()
        collectionView.register(CollectionGridCell.self, forCellWithReuseIdentifier: CollectionGridCell.reuseIdentifier)
        addSubview(collectionView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flushRememberedScrollPosition),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flushRememberedScrollPosition),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        coordinator?.flushScrollPosition(in: collectionView)
        NotificationCenter.default.removeObserver(self)
    }

    func update(
        items: [MobileCollectionItem],
        progressByCollectionId: [String: Int],
        viewedToEndCollectionIds: Set<String>,
        coordinator: InfiniteCollectionsGridView.Coordinator
    ) {
        self.coordinator = coordinator
        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator
        collectionView.prefetchDataSource = coordinator

        switch coordinator.update(
            items: items,
            progressByCollectionId: progressByCollectionId,
            viewedToEndCollectionIds: viewedToEndCollectionIds
        ) {
        case .itemsChanged:
            didSetInitialScrollPosition = false
            collectionView.reloadData()
        case .progressOnly:
            coordinator.updateVisibleProgressCells(in: collectionView)
        case .noChange:
            break
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        collectionView.frame = bounds
        let itemSizeDidChange: Bool
        if previousBoundsSize != bounds.size {
            previousBoundsSize = bounds.size
            itemSizeDidChange = updateGridLayoutItemSize()
        } else {
            itemSizeDidChange = false
        }

        guard bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        if !didSetInitialScrollPosition,
           collectionView.numberOfItems(inSection: 0) > 0 {
            coordinator?.setInitialScrollPosition(in: collectionView, savedPosition: initialScrollPosition)
            didSetInitialScrollPosition = true
            collectionView.layoutIfNeeded()
            coordinator?.prefetchImages(aroundVisibleItemsIn: collectionView)
            coordinator?.finishInitialCoverFadeScheduling()
            return
        }

        if itemSizeDidChange {
            coordinator?.updateVisibleProgressCells(in: collectionView)
            coordinator?.prefetchImages(aroundVisibleItemsIn: collectionView)
        }
    }

    fileprivate static func itemSize(forWidth width: CGFloat) -> CGSize {
        let minimumItemWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 130 : 77
        let columns = max(Int(width / minimumItemWidth), 1)
        let itemWidth = width / CGFloat(columns)
        return CGSize(width: itemWidth, height: itemWidth)
    }

    private func updateGridLayoutItemSize() -> Bool {
        guard bounds.width > 0,
              let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return false
        }

        let itemSize = Self.itemSize(forWidth: bounds.width)
        guard flowLayout.itemSize != itemSize else { return false }
        flowLayout.itemSize = itemSize
        flowLayout.invalidateLayout()
        return true
    }

    @objc private func flushRememberedScrollPosition() {
        coordinator?.flushScrollPosition(in: collectionView)
    }
}

private extension Double {
    func clamped(to range: Range<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return min(max(self, range.lowerBound), range.upperBound.nextDown)
    }
}

nonisolated private final class MobileCollectionCoverImageStorage: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 320
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.memoryCost)
    }
}

private actor MobileCollectionCoverImageDecodeLane {
    func image(
        assetName: String,
        key: String,
        targetPixelSide: Int,
        displayScale: CGFloat,
        storage: MobileCollectionCoverImageStorage
    ) -> UIImage? {
        if let image = storage.image(forKey: key) {
            return image
        }
        guard !Task.isCancelled else { return nil }

        let image = autoreleasepool { () -> UIImage? in
            guard let image = UIImage(named: assetName) else { return nil }

            let scale = max(displayScale, 1)
            let targetSide = CGFloat(targetPixelSide) / scale
            let targetSize = CGSize(width: targetSide, height: targetSide)
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return image }

            let fillScale = max(
                targetSize.width / imageSize.width,
                targetSize.height / imageSize.height
            )
            let scaledSize = CGSize(
                width: imageSize.width * fillScale,
                height: imageSize.height * fillScale
            )
            let drawRect = CGRect(
                x: (targetSize.width - scaledSize.width) / 2,
                y: (targetSize.height - scaledSize.height) / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )

            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                image.draw(in: drawRect)
            }
        }

        guard !Task.isCancelled else { return nil }
        if let image {
            storage.insert(image, forKey: key)
        }
        return image
    }
}

final class MobileCollectionCoverImageCache {
    static let shared = MobileCollectionCoverImageCache()

    private let storage = MobileCollectionCoverImageStorage()
    private let visibleDecodeLane = MobileCollectionCoverImageDecodeLane()
    private let prefetchDecodeLane = MobileCollectionCoverImageDecodeLane()
    private var prefetchTasks = [String: (id: UUID, task: Task<Void, Never>)]()

    private init() {}

    func cachedImage(assetName: String, targetSize: CGSize, displayScale: CGFloat) -> UIImage? {
        let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
        return storage.image(
            forKey: cacheKey(assetName: assetName, targetPixelSide: targetPixelSide)
        )
    }

    func loadImage(
        assetName: String,
        targetSize: CGSize,
        displayScale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) {
        let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
        let key = cacheKey(assetName: assetName, targetPixelSide: targetPixelSide)
        if let image = storage.image(forKey: key) {
            completion(image)
            return
        }

        Task(priority: .userInitiated) {
            let image = await visibleDecodeLane.image(
                assetName: assetName,
                key: key,
                targetPixelSide: targetPixelSide,
                displayScale: displayScale,
                storage: storage
            )
            completion(image)
        }
    }

    func prefetch(assetNames: [String], targetSize: CGSize, displayScale: CGFloat) {
        assetNames.forEach { assetName in
            let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
            let key = cacheKey(assetName: assetName, targetPixelSide: targetPixelSide)
            guard storage.image(forKey: key) == nil else { return }
            guard prefetchTasks[key] == nil else { return }

            let id = UUID()
            let task = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                _ = await prefetchDecodeLane.image(
                    assetName: assetName,
                    key: key,
                    targetPixelSide: targetPixelSide,
                    displayScale: displayScale,
                    storage: storage
                )
                guard !Task.isCancelled,
                      prefetchTasks[key]?.id == id else {
                    return
                }
                prefetchTasks.removeValue(forKey: key)
            }
            prefetchTasks[key] = (id, task)
        }
    }

    func cancelPrefetch(assetNames: [String], targetSize: CGSize, displayScale: CGFloat) {
        let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
        let keys = assetNames.map { assetName in
            cacheKey(assetName: assetName, targetPixelSide: targetPixelSide)
        }
        keys.forEach { key in
            prefetchTasks.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func targetPixelSide(for targetSize: CGSize, displayScale: CGFloat) -> Int {
        let pointSide = max(max(targetSize.width, targetSize.height), 1)
        return max(Int(ceil(pointSide * displayScale)), 1)
    }

    private func cacheKey(assetName: String, targetPixelSide: Int) -> String {
        "\(assetName)-\(targetPixelSide)"
    }
}

private extension UIImage {
    nonisolated var memoryCost: Int {
        guard let cgImage else {
            return Int(size.width * scale * size.height * scale * 4)
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

private final class CollectionGridCell: UICollectionViewCell {
    static let reuseIdentifier = "CollectionGridCell"

    private let imageView = UIImageView()
    private let titleLabel = GridTitleLabel()
    private let progressLabel = GridTitleLabel()
    private var showsCompletedBadge = false
    private var representedCoverAssetName: String?
    private var representedCoverSize = CGSize.zero
    private var representedProgressPercent: Int?
    private var representedHasViewedToEnd = false
    private var hasInitialCoverAppearanceState = false
    private var isInitialCoverAppearancePending = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = false
        contentView.clipsToBounds = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 9, weight: .regular)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .left
        titleLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        titleLabel.layer.cornerRadius = 3
        titleLabel.clipsToBounds = true
        contentView.addSubview(titleLabel)

        progressLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        progressLabel.textColor = .white
        progressLabel.numberOfLines = 1
        progressLabel.textAlignment = .center
        progressLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        progressLabel.layer.cornerRadius = 3
        progressLabel.clipsToBounds = true
        progressLabel.isHidden = true
        contentView.addSubview(progressLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedCoverAssetName = nil
        representedCoverSize = .zero
        representedProgressPercent = nil
        representedHasViewedToEnd = false
        cancelInitialCoverAppearance()
        imageView.image = nil
        titleLabel.text = nil
        progressLabel.text = nil
        progressLabel.isHidden = true
        showsCompletedBadge = false
    }

    func configure(
        item: MobileCollectionItem,
        progressPercent: Int?,
        hasViewedToEnd: Bool,
        coverSize: CGSize,
        displayScale: CGFloat,
        shouldAnimateInitialAppearance: Bool
    ) {
        let coverAssetChanged = representedCoverAssetName != item.coverAssetName
        let shouldUpdateCover = coverAssetChanged
            || representedCoverSize != coverSize
            || imageView.image == nil
        representedCoverAssetName = item.coverAssetName
        representedCoverSize = coverSize
        let cachedCoverImage: UIImage?
        if shouldUpdateCover {
            cachedCoverImage = MobileCollectionCoverImageCache.shared.cachedImage(
                assetName: item.coverAssetName,
                targetSize: coverSize,
                displayScale: displayScale
            )
        } else {
            cachedCoverImage = nil
        }

        if shouldUpdateCover {
            if shouldAnimateInitialAppearance {
                prepareInitialCoverAppearance()
            }

            if cachedCoverImage == nil {
                if coverAssetChanged || imageView.image == nil {
                    imageView.image = nil
                }
                MobileCollectionCoverImageCache.shared.loadImage(
                    assetName: item.coverAssetName,
                    targetSize: coverSize,
                    displayScale: displayScale
                ) { [weak self] image in
                    guard let self,
                          self.representedCoverAssetName == item.coverAssetName,
                          self.representedCoverSize == coverSize,
                          self.imageView.image == nil else {
                        return
                    }
                    self.setCoverImage(image, animated: self.consumeInitialCoverAppearance())
                }
            }
        }
        titleLabel.text = item.name
        if representedProgressPercent != progressPercent || representedHasViewedToEnd != hasViewedToEnd {
            representedProgressPercent = progressPercent
            representedHasViewedToEnd = hasViewedToEnd
            showsCompletedBadge = hasViewedToEnd
            if hasViewedToEnd {
                progressLabel.text = "✓"
                progressLabel.font = .systemFont(ofSize: 9, weight: .semibold)
                progressLabel.isHidden = false
            } else if let progressPercent, progressPercent > 0 {
                progressLabel.text = Strings.percent(progressPercent)
                progressLabel.font = .systemFont(ofSize: 9, weight: .semibold)
                progressLabel.isHidden = false
            } else {
                progressLabel.text = nil
                progressLabel.isHidden = true
            }
        }
        accessibilityLabel = item.name
        if let cachedCoverImage {
            setCoverImage(cachedCoverImage, animated: consumeInitialCoverAppearance())
        }
        setNeedsLayout()
    }

    private func cancelInitialCoverAppearance() {
        guard hasInitialCoverAppearanceState else { return }
        contentView.layer.removeAnimation(forKey: initialCollectionItemFadeAnimationKey)
        contentView.alpha = 1
        hasInitialCoverAppearanceState = false
        isInitialCoverAppearancePending = false
    }

    private func prepareInitialCoverAppearance() {
        contentView.layer.removeAnimation(forKey: initialCollectionItemFadeAnimationKey)
        contentView.alpha = 0
        hasInitialCoverAppearanceState = true
        isInitialCoverAppearancePending = true
    }

    private func consumeInitialCoverAppearance() -> Bool {
        guard isInitialCoverAppearancePending else { return false }
        isInitialCoverAppearancePending = false
        return true
    }

    private func setCoverImage(_ image: UIImage?, animated: Bool) {
        imageView.image = image

        guard animated, image != nil else {
            cancelInitialCoverAppearance()
            return
        }

        contentView.layer.removeAnimation(forKey: initialCollectionItemFadeAnimationKey)
        contentView.alpha = 1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = initialCollectionItemFadeDuration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        contentView.layer.add(animation, forKey: initialCollectionItemFadeAnimationKey)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        imageView.frame = contentView.bounds.insetBy(dx: -0.5, dy: -0.5)

        let maximumLabelWidth = max(contentView.bounds.width - 8, 0)
        let maximumLabelSize = CGSize(width: maximumLabelWidth, height: CGFloat.greatestFiniteMagnitude)
        let labelSize = titleLabel.sizeThatFits(maximumLabelSize)
        let labelWidth = min(maximumLabelWidth, ceil(labelSize.width))
        let labelHeight = min(ceil(labelSize.height), 28)
        titleLabel.frame = CGRect(
            x: 4,
            y: contentView.bounds.height - labelHeight - 3,
            width: labelWidth,
            height: labelHeight
        )

        if !progressLabel.isHidden {
            if showsCompletedBadge {
                let badgeSide: CGFloat = 15
                progressLabel.frame = CGRect(
                    x: contentView.bounds.width - badgeSide - 4,
                    y: 4,
                    width: badgeSide,
                    height: badgeSide
                )
                progressLabel.layer.cornerRadius = badgeSide / 2
            } else {
                let progressSize = progressLabel.sizeThatFits(CGSize(width: 42, height: 16))
                let progressWidth = min(max(ceil(progressSize.width), 28), 44)
                progressLabel.frame = CGRect(
                    x: contentView.bounds.width - progressWidth - 4,
                    y: 4,
                    width: progressWidth,
                    height: 15
                )
                progressLabel.layer.cornerRadius = 3
            }
        }
    }
}

private final class GridTitleLabel: UILabel {
    private let textInsets = UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let adjustedSize = CGSize(
            width: max(size.width - textInsets.left - textInsets.right, 0),
            height: max(size.height - textInsets.top - textInsets.bottom, 0)
        )
        let measuredSize = super.sizeThatFits(adjustedSize)
        return CGSize(
            width: measuredSize.width + textInsets.left + textInsets.right,
            height: measuredSize.height + textInsets.top + textInsets.bottom
        )
    }
}
