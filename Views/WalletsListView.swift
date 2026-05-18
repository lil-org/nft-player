// ∅ 2026 lil org

import Cocoa
import SwiftUI

struct WalletsListView: View {

    private let collectionItems = CollectionCatalog.allItems

    var body: some View {
        InfiniteCollectionsGridView(items: collectionItems) { item in
            showPlayer(id: item.id)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Spacer()
                ControlGroup {
                    settingsMenu
                    Button(action: {
                        showPlayer(id: nil)
                    }) {
                        Images.shuffle
                    }
                }
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Text(Strings.sendFeedback)
            Button(Strings.github, action: { open(URL.github) })
            Button(Strings.mail, action: { open(URL.mail) })
            Button(Strings.x, action: { open(URL.x) })
            Divider()
            Button(Strings.rateOnTheAppStore) { open(URL.writeAppStoreReview) }
        } label: {
            Images.gearshape
        }
        .menuIndicator(.hidden)
    }

    private func showPlayer(id: String?) {
        guard let token = CollectionCatalog.generateRandomToken(
            specificCollectionId: id,
            notTokenId: nil
        ) else {
            return
        }
        Navigator.shared.showPlayer(model: PlayerModel(token: token))
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

}

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

    static func initialScrollPosition(itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        return centeredIndex(sourceIndex: initialSourceOffset % itemCount, itemCount: itemCount)
    }

    static func shouldRecenter(repetition: Int) -> Bool {
        repetition <= recenterThreshold || repetition >= repetitionCount - recenterThreshold
    }
}

private struct InfiniteCollectionsGridView: NSViewRepresentable {
    let items: [CollectionCatalogItem]
    let onSelect: (CollectionCatalogItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(items: [], onSelect: onSelect)
    }

    func makeNSView(context: Context) -> InfiniteCollectionsGridContainerView {
        let containerView = InfiniteCollectionsGridContainerView()
        containerView.update(items: items, coordinator: context.coordinator)
        return containerView
    }

    func updateNSView(_ containerView: InfiniteCollectionsGridContainerView, context: Context) {
        context.coordinator.onSelect = onSelect
        containerView.update(items: items, coordinator: context.coordinator)
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewPrefetching {
        var items: [CollectionCatalogItem]
        var onSelect: (CollectionCatalogItem) -> Void
        private var isRecentering = false

        init(items: [CollectionCatalogItem], onSelect: @escaping (CollectionCatalogItem) -> Void) {
            self.items = items
            self.onSelect = onSelect
        }

        func update(items: [CollectionCatalogItem]) -> Bool {
            guard self.items != items else { return false }
            self.items = items
            return true
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            InfiniteCollectionsLoop.virtualItemCount(itemCount: items.count)
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: CollectionGridItem.reuseIdentifier,
                for: indexPath
            )
            guard let gridItem = item as? CollectionGridItem else { return item }
            configure(gridItem, at: indexPath)
            return gridItem
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            collectionView.deselectItems(at: indexPaths)
            guard let indexPath = indexPaths.first,
                  !items.isEmpty else {
                return
            }
            onSelect(item(for: indexPath.item))
        }

        func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            prefetchImages(for: indexPaths)
        }

        func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            cancelPrefetchingImages(for: indexPaths)
        }

        func visibleAnchor(in collectionView: NSCollectionView, scrollView: NSScrollView) -> VisibleAnchor? {
            guard !items.isEmpty,
                  let topIndexPath = collectionView.indexPathsForVisibleItems().min(by: { $0.item < $1.item }),
                  let topAttributes = collectionView.layoutAttributesForItem(at: topIndexPath) else {
                return nil
            }

            return VisibleAnchor(
                sourceIndex: InfiniteCollectionsLoop.sourceIndex(for: topIndexPath.item, itemCount: items.count),
                offsetWithinItem: scrollView.contentView.bounds.origin.y - topAttributes.frame.minY
            )
        }

        func restore(_ anchor: VisibleAnchor, in collectionView: NSCollectionView, scrollView: NSScrollView) {
            guard !items.isEmpty else { return }

            collectionView.layoutSubtreeIfNeeded()
            let targetIndexPath = IndexPath(
                item: InfiniteCollectionsLoop.centeredIndex(sourceIndex: anchor.sourceIndex, itemCount: items.count),
                section: 0
            )
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else {
                return
            }
            setScrollY(targetAttributes.frame.minY + anchor.offsetWithinItem, in: scrollView)
        }

        func setInitialScrollPosition(in collectionView: NSCollectionView, scrollView: NSScrollView) {
            guard !items.isEmpty,
                  let targetIndex = InfiniteCollectionsLoop.initialScrollPosition(itemCount: items.count) else {
                return
            }

            collectionView.layoutSubtreeIfNeeded()
            let targetIndexPath = IndexPath(item: targetIndex, section: 0)
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else {
                return
            }

            isRecentering = true
            setScrollY(targetAttributes.frame.minY, in: scrollView)
            isRecentering = false
        }

        func scrollViewDidScroll(_ scrollView: NSScrollView, collectionView: NSCollectionView) {
            guard !isRecentering,
                  !items.isEmpty,
                  let topIndexPath = collectionView.indexPathsForVisibleItems().min(by: { $0.item < $1.item }),
                  let topAttributes = collectionView.layoutAttributesForItem(at: topIndexPath) else {
                return
            }

            let itemCount = items.count
            let repetition = InfiniteCollectionsLoop.repetition(for: topIndexPath.item, itemCount: itemCount)
            guard InfiniteCollectionsLoop.shouldRecenter(repetition: repetition) else { return }

            let sourceIndex = InfiniteCollectionsLoop.sourceIndex(for: topIndexPath.item, itemCount: itemCount)
            let targetIndexPath = IndexPath(
                item: InfiniteCollectionsLoop.centeredIndex(sourceIndex: sourceIndex, itemCount: itemCount),
                section: 0
            )
            collectionView.layoutSubtreeIfNeeded()
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else { return }

            isRecentering = true
            let offsetWithinTopItem = scrollView.contentView.bounds.origin.y - topAttributes.frame.minY
            setScrollY(targetAttributes.frame.minY + offsetWithinTopItem, in: scrollView)
            isRecentering = false
        }

        func updateVisibleItems(in collectionView: NSCollectionView) {
            collectionView.indexPathsForVisibleItems().forEach { indexPath in
                guard let item = collectionView.item(at: indexPath) as? CollectionGridItem else { return }
                configure(item, at: indexPath)
            }
        }

        func prefetchImages(aroundVisibleItemsIn collectionView: NSCollectionView) {
            guard !items.isEmpty else { return }
            let visibleItems = collectionView.indexPathsForVisibleItems().map(\.item)
            guard let firstVisibleItem = visibleItems.min(),
                  let lastVisibleItem = visibleItems.max() else {
                return
            }

            let itemWidth = max((collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.width ?? collectionView.bounds.width, 1)
            let visibleColumnCount = max(Int(collectionView.bounds.width / itemWidth), 1)
            let prefetchDistance = visibleColumnCount * 3
            let maximumItem = max(collectionView.numberOfItems(inSection: 0) - 1, 0)
            let itemRange = max(firstVisibleItem - prefetchDistance, 0)...min(lastVisibleItem + prefetchDistance, maximumItem)
            prefetchImages(
                for: itemRange.map { IndexPath(item: $0, section: 0) }
            )
        }

        private func item(for virtualIndex: Int) -> CollectionCatalogItem {
            items[InfiniteCollectionsLoop.sourceIndex(for: virtualIndex, itemCount: items.count)]
        }

        private func configure(_ gridItem: CollectionGridItem, at indexPath: IndexPath) {
            let item = item(for: indexPath.item)
            gridItem.configure(item: item)
        }

        private func prefetchImages(for indexPaths: [IndexPath]) {
            guard !items.isEmpty else { return }
            let assetNames = Set(indexPaths.map { item(for: $0.item).coverAssetName })
            CollectionCoverImageCache.shared.prefetch(assetNames: Array(assetNames))
        }

        private func cancelPrefetchingImages(for indexPaths: [IndexPath]) {
            guard !items.isEmpty else { return }
            let assetNames = Set(indexPaths.map { item(for: $0.item).coverAssetName })
            CollectionCoverImageCache.shared.cancelPrefetch(assetNames: Array(assetNames))
        }

        private func setScrollY(_ y: CGFloat, in scrollView: NSScrollView) {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(y, 0)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    struct VisibleAnchor {
        let sourceIndex: Int
        let offsetWithinItem: CGFloat
    }
}

private final class InfiniteCollectionsGridContainerView: NSView {
    private let scrollView = NSScrollView()
    private let collectionView: NSCollectionView
    private let flowLayout = NSCollectionViewFlowLayout()
    private weak var coordinator: InfiniteCollectionsGridView.Coordinator?
    private var boundsObserver: NSObjectProtocol?
    private var didSetInitialScrollPosition = false
    private var previousBoundsSize = CGSize.zero

    override init(frame frameRect: NSRect) {
        flowLayout.scrollDirection = .vertical
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        flowLayout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        collectionView.backgroundColors = [.black]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.register(CollectionGridItem.self, forItemWithIdentifier: CollectionGridItem.reuseIdentifier)
        scrollView.documentView = collectionView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self, let coordinator = self.coordinator else { return }
            coordinator.scrollViewDidScroll(self.scrollView, collectionView: self.collectionView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func update(
        items: [CollectionCatalogItem],
        coordinator: InfiniteCollectionsGridView.Coordinator
    ) {
        self.coordinator = coordinator
        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator
        collectionView.prefetchDataSource = coordinator

        if coordinator.update(items: items) {
            didSetInitialScrollPosition = false
            collectionView.reloadData()
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        collectionView.setFrameSize(CGSize(width: bounds.width, height: max(collectionView.frame.height, bounds.height)))
        if previousBoundsSize != bounds.size {
            let anchor = coordinator?.visibleAnchor(in: collectionView, scrollView: scrollView)
            previousBoundsSize = bounds.size

            if updateGridLayoutItemSize() {
                collectionView.layoutSubtreeIfNeeded()
                updateCollectionViewContentHeight()
                if let anchor {
                    coordinator?.restore(anchor, in: collectionView, scrollView: scrollView)
                }
                coordinator?.updateVisibleItems(in: collectionView)
                coordinator?.prefetchImages(aroundVisibleItemsIn: collectionView)
            }
        }

        guard !didSetInitialScrollPosition,
              collectionView.numberOfItems(inSection: 0) > 0 else {
            return
        }

        collectionView.layoutSubtreeIfNeeded()
        updateCollectionViewContentHeight()
        coordinator?.setInitialScrollPosition(in: collectionView, scrollView: scrollView)
        didSetInitialScrollPosition = true
        coordinator?.prefetchImages(aroundVisibleItemsIn: collectionView)
    }

    fileprivate static func itemSize(forWidth width: CGFloat) -> CGSize {
        let minimumItemWidth: CGFloat = 100
        let columns = max(Int(width / minimumItemWidth), 1)
        let itemWidth = width / CGFloat(columns)
        return CGSize(width: itemWidth, height: itemWidth)
    }

    private func updateGridLayoutItemSize() -> Bool {
        let itemSize = Self.itemSize(forWidth: bounds.width)
        guard flowLayout.itemSize != itemSize else { return false }
        flowLayout.itemSize = itemSize
        flowLayout.invalidateLayout()
        return true
    }

    private func updateCollectionViewContentHeight() {
        let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? bounds.height
        let targetSize = CGSize(width: bounds.width, height: max(bounds.height, contentHeight))
        guard collectionView.frame.size != targetSize else { return }
        collectionView.setFrameSize(targetSize)
    }
}

private final class CollectionCoverImageCache {
    static let shared = CollectionCoverImageCache()

    private typealias ImageCompletion = (NSImage?) -> Void
    private static let preparedPixelSide = 300

    private let visibleQueue = DispatchQueue(label: "org.lil.nft-folder.collection-cover-cache.visible", qos: .userInitiated)
    private let prefetchQueue = DispatchQueue(label: "org.lil.nft-folder.collection-cover-cache.prefetch", qos: .userInitiated)
    private let lock = NSLock()
    private let cache = NSCache<NSString, NSImage>()
    private var pendingVisibleCompletions = [String: [ImageCompletion]]()
    private var pendingPrefetchKeys = Set<String>()
    private var cancelledPrefetchKeys = Set<String>()

    private init() {
        cache.countLimit = 320
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(assetName: String) -> NSImage? {
        cache.object(forKey: assetName as NSString)
    }

    func loadImage(
        assetName: String,
        completion: @escaping (NSImage?) -> Void
    ) {
        if let image = cache.object(forKey: assetName as NSString) {
            completion(image)
            return
        }

        guard scheduleVisibleLoad(forKey: assetName, completion: completion) else { return }

        visibleQueue.async {
            let image: NSImage?
            if let cachedImage = self.cache.object(forKey: assetName as NSString) {
                image = cachedImage
            } else {
                let loadedImage = Self.preparedImage(assetName: assetName)
                if let loadedImage {
                    self.store(loadedImage, key: assetName)
                }
                image = loadedImage
            }

            let completions = self.finishVisibleLoad(forKey: assetName)
            DispatchQueue.main.async {
                completions.forEach { $0(image) }
            }
        }
    }

    func prefetch(assetNames: [String]) {
        assetNames.forEach { assetName in
            guard cache.object(forKey: assetName as NSString) == nil else { return }
            guard shouldSchedulePrefetch(forKey: assetName) else { return }

            prefetchQueue.async {
                guard self.shouldRunPrefetch(forKey: assetName) else { return }
                guard self.cache.object(forKey: assetName as NSString) == nil else {
                    self.finishPrefetch(forKey: assetName)
                    return
                }

                let image = Self.preparedImage(assetName: assetName)
                if let image {
                    self.store(image, key: assetName)
                }
                self.finishPrefetch(forKey: assetName)
            }
        }
    }

    func cancelPrefetch(assetNames: [String]) {
        lock.withLock {
            assetNames.forEach { assetName in
                guard pendingPrefetchKeys.contains(assetName) else { return }
                cancelledPrefetchKeys.insert(assetName)
            }
        }
    }

    private func store(_ image: NSImage, key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.memoryCost)
    }

    private func scheduleVisibleLoad(
        forKey key: String,
        completion: @escaping ImageCompletion
    ) -> Bool {
        lock.withLock {
            if pendingVisibleCompletions[key] != nil {
                pendingVisibleCompletions[key]?.append(completion)
                return false
            }
            pendingVisibleCompletions[key] = [completion]
            return true
        }
    }

    private func finishVisibleLoad(forKey key: String) -> [ImageCompletion] {
        lock.withLock {
            return pendingVisibleCompletions.removeValue(forKey: key) ?? []
        }
    }

    private func shouldSchedulePrefetch(forKey key: String) -> Bool {
        lock.withLock {
            if pendingPrefetchKeys.contains(key) {
                cancelledPrefetchKeys.remove(key)
                return false
            }
            cancelledPrefetchKeys.remove(key)
            pendingPrefetchKeys.insert(key)
            return true
        }
    }

    private func shouldRunPrefetch(forKey key: String) -> Bool {
        lock.withLock {
            if cancelledPrefetchKeys.contains(key) {
                pendingPrefetchKeys.remove(key)
                cancelledPrefetchKeys.remove(key)
                return false
            }
            return true
        }
    }

    private func finishPrefetch(forKey key: String) {
        lock.withLock {
            pendingPrefetchKeys.remove(key)
            cancelledPrefetchKeys.remove(key)
        }
    }

    private static func preparedImage(assetName: String) -> NSImage? {
        autoreleasepool {
            guard let sourceImage = NSImage(named: assetName) else { return nil }
            var proposedRect = CGRect(origin: .zero, size: sourceImage.size)
            guard let sourceCGImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
                  let colorSpace = sourceCGImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: preparedPixelSide,
                    height: preparedPixelSide,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return sourceImage
            }

            context.interpolationQuality = .high
            let sourceSize = CGSize(width: sourceCGImage.width, height: sourceCGImage.height)
            guard sourceSize.width > 0, sourceSize.height > 0 else { return sourceImage }

            let targetSize = CGSize(width: preparedPixelSide, height: preparedPixelSide)
            let fillScale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
            let scaledSize = CGSize(width: sourceSize.width * fillScale, height: sourceSize.height * fillScale)
            let drawRect = CGRect(
                x: (targetSize.width - scaledSize.width) / 2,
                y: (targetSize.height - scaledSize.height) / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )
            context.draw(sourceCGImage, in: drawRect)

            guard let image = context.makeImage() else { return sourceImage }
            return NSImage(cgImage: image, size: targetSize)
        }
    }
}

private extension NSImage {
    var memoryCost: Int {
        if let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage.bytesPerRow * cgImage.height
        }
        return Int(size.width * size.height * 4)
    }
}

private final class CollectionGridItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("CollectionGridItem")

    private var cellView: CollectionGridCellView {
        view as! CollectionGridCellView
    }

    private var representedCoverAssetName: String?

    override func loadView() {
        view = CollectionGridCellView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedCoverAssetName = nil
        cellView.image = nil
        cellView.title = nil
    }

    func configure(item: CollectionCatalogItem) {
        let coverAssetChanged = representedCoverAssetName != item.coverAssetName
        let shouldUpdateCover = coverAssetChanged || cellView.image == nil
        representedCoverAssetName = item.coverAssetName
        cellView.title = item.name
        view.setAccessibilityLabel(item.name)

        guard shouldUpdateCover else { return }
        if let cachedCoverImage = CollectionCoverImageCache.shared.cachedImage(assetName: item.coverAssetName) {
            cellView.image = cachedCoverImage
            return
        }

        if coverAssetChanged || cellView.image == nil {
            cellView.image = nil
        }
        CollectionCoverImageCache.shared.loadImage(assetName: item.coverAssetName) { [weak self] image in
            guard let self,
                  self.representedCoverAssetName == item.coverAssetName else {
                return
            }
            self.cellView.image = image
        }
    }
}

private final class CollectionGridCellView: NSView {
    var image: NSImage? {
        didSet {
            imageView.image = image
        }
    }

    var title: String? {
        didSet {
            guard title != oldValue else { return }
            titleLabel.text = title ?? ""
            needsLayout = true
        }
    }

    private let imageView = CoverImageView()
    private let titleLabel = GridTitleLabel()
    private let imageBleed: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: -imageBleed),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: imageBleed),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -imageBleed),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: imageBleed)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = frame.size != newSize
        super.setFrameSize(newSize)
        if sizeChanged {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()

        let maximumLabelWidth = max(bounds.width - 8, 0)
        guard maximumLabelWidth > 0, !titleLabel.text.isEmpty else {
            titleLabel.frame = .zero
            return
        }

        let measuredSize = titleLabel.sizeThatFits(
            CGSize(width: maximumLabelWidth, height: .greatestFiniteMagnitude)
        )
        let labelWidth = min(maximumLabelWidth, max(ceil(measuredSize.width) + 2, 12))
        let labelHeight = min(max(ceil(measuredSize.height), titleLabel.minimumHeight), 30)
        titleLabel.frame = CGRect(
            x: 4,
            y: 3,
            width: labelWidth,
            height: labelHeight
        )
    }
}

private final class GridTitleLabel: NSView {
    var text: String = "" {
        didSet {
            needsDisplay = true
        }
    }

    var minimumHeight: CGFloat {
        ceil(font.boundingRectForFont.height) + textInsets.top + textInsets.bottom
    }

    private let font = NSFont.systemFont(ofSize: 10, weight: .regular)
    private let textInsets = NSEdgeInsets(top: 1, left: 3, bottom: 1, right: 3)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func sizeThatFits(_ size: CGSize) -> CGSize {
        guard !text.isEmpty else { return .zero }

        let textSize = CGSize(
            width: max(size.width - textInsets.left - textInsets.right, 0),
            height: .greatestFiniteMagnitude
        )
        let measuredSize = attributedText.boundingRect(
            with: textSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        return CGSize(
            width: measuredSize.width + textInsets.left + textInsets.right,
            height: measuredSize.height + textInsets.top + textInsets.bottom
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !text.isEmpty else { return }

        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()

        attributedText.draw(
            with: CGRect(
                x: textInsets.left,
                y: textInsets.top,
                width: max(bounds.width - textInsets.left - textInsets.right, 0),
                height: max(bounds.height - textInsets.top - textInsets.bottom, 0)
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    private var attributedText: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}

private final class CoverImageView: NSView {
    var image: NSImage? {
        didSet {
            layer?.contents = image?.cgImage
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }
}

private extension NSImage {
    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
