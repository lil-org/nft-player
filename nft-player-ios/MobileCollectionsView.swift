import SwiftUI
import UIKit

private let playerCrossfadeAnimation = Animation.easeInOut(duration: 0.18)
private let playerStatusBarRevealAnimation = Animation.easeInOut(duration: 0.38)
private let playerStatusBarRevealDuration: TimeInterval = 0.3
private let initialCollectionItemFadeDuration: TimeInterval = 0.3
private let initialCollectionItemFadeAnimationKey = "initialGridItemFade"

private enum PlayerPresentationTransition {
    case animated
    case instant

    var overlayTransition: AnyTransition {
        switch self {
        case .animated:
            return .opacity
        case .instant:
            return .identity
        }
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

    static func initialSourceIndices(itemCount: Int, limit: Int) -> [Int] {
        guard itemCount > 0, limit > 0 else { return [] }
        return (0..<min(itemCount, limit)).map { (initialSourceOffset + $0) % itemCount }
    }

    static func shouldRecenter(repetition: Int) -> Bool {
        repetition <= recenterThreshold || repetition >= repetitionCount - recenterThreshold
    }
}

struct MobileCollectionsView: View {
    private let collectionItems = MobileCollectionCatalog.allItems
    @State private var playerConfig: MobilePlayerConfig?
    @State private var playerPresentationTransition: PlayerPresentationTransition = .animated
    @State private var viewingProgressByCollectionId: [String: Int]
    @State private var viewedToEndCollectionIds: Set<String>
    @State private var continueViewingProgress: MobileViewingProgress?
    
    init() {
        let progressSnapshot = MobileViewingProgressStore.progressSnapshot()
        _viewingProgressByCollectionId = State(initialValue: progressSnapshot.percentagesByCollectionId)
        _viewedToEndCollectionIds = State(initialValue: progressSnapshot.viewedToEndCollectionIds)
        _continueViewingProgress = State(initialValue: progressSnapshot.continueViewingProgress)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                InfiniteCollectionsGridView(
                    items: collectionItems,
                    progressByCollectionId: viewingProgressByCollectionId,
                    viewedToEndCollectionIds: viewedToEndCollectionIds,
                    onSelect: didSelectCollectionItem
                )
                .ignoresSafeArea()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {}
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Text(Strings.sendFeedback)
                            Button(Strings.github) { UIApplication.shared.open(URL.github) }
                            Button(Strings.mail) { UIApplication.shared.open(URL.mail) }
                            Button(Strings.x) { UIApplication.shared.open(URL.x) }
                            Divider()
                            Button(Strings.rateOnTheAppStore) { UIApplication.shared.open(URL.writeAppStoreReview) }
                            Divider()
                            Button(Strings.changeAppIcon) { didClickToggleAppIcon() }
                        } label: {
                            Images.preferences
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showShuffledCollectionPlayer() } label: {
                            Images.shuffle
                        }
                    }
                }
            }

            if playerConfig == nil, let continueViewingProgress {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        ContinueViewingButton(progress: continueViewingProgress) {
                            resumeViewing(continueViewingProgress)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, MobileBottomChromeSpacing.continueViewingPadding(forSafeAreaBottom: geometry.safeAreaInsets.bottom))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea(edges: .bottom)
                }
                .transition(.opacity)
                .zIndex(0.5)
            }

            if let playerConfig {
                PlayerNavigationOverlay(config: playerConfig) {
                    dismissPlayer(playerConfig)
                }
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .zIndex(1)
                .id(playerConfig.id)
                .transition(playerPresentationTransition.overlayTransition)
            }
        }
        .persistentSystemOverlays(.hidden)
        .onAppear {
            refreshViewingProgress()
            schedulePlayerPrewarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshViewingProgress()
            schedulePlayerPrewarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)) { _ in
            guard playerConfig == nil else { return }
            refreshViewingProgress()
        }
        .onOpenURL(perform: openWidgetURL)
    }
    
    private func didClickToggleAppIcon() {
        if UIApplication.shared.alternateIconName == nil {
            UIApplication.shared.setAlternateIconName("AppIconLegacy")
        } else {
            UIApplication.shared.setAlternateIconName(nil)
        }
    }

    private func didSelectCollectionItem(_ item: MobileCollectionItem) {
        openCollection(collectionId: item.id)
    }

    private func openCollection(
        collectionId: String,
        presentationTransition: PlayerPresentationTransition = .animated,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        if let progress = MobileViewingProgressStore.progress(collectionId: collectionId) {
            resumeViewing(progress, presentationTransition: presentationTransition, trackingMode: trackingMode)
            return
        }

        openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            presentationTransition: presentationTransition,
            trackingMode: trackingMode
        )
    }
    
    private func showShuffledCollectionPlayer() {
        guard let item = randomCollectionItemPreferringUnfinishedCollections() else { return }
        let progress = MobileViewingProgressStore.progress(collectionId: item.id)
        let initialTokenId = progress?.isComplete == false ? progress?.tokenId : nil

        openPlayer(
            initialItemId: item.id,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: item.id
        )
    }

    private func randomCollectionItemPreferringUnfinishedCollections() -> MobileCollectionItem? {
        let progressSnapshot = MobileViewingProgressStore.progressSnapshot()
        let unfinishedItems = collectionItems.filter { !progressSnapshot.viewedToEndCollectionIds.contains($0.id) }
        return (unfinishedItems.isEmpty ? collectionItems : unfinishedItems).randomElement()
    }

    private func resumeViewing(
        _ progress: MobileViewingProgress,
        presentationTransition: PlayerPresentationTransition = .animated,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        openPlayer(
            initialItemId: progress.collectionId,
            initialTokenId: progress.tokenId,
            continueViewingCollectionId: progress.collectionId,
            presentationTransition: presentationTransition,
            trackingMode: trackingMode
        )
    }

    private func openWidgetURL(_ url: URL) {
        guard let deepLink = WidgetDeepLink(url: url),
              case let .collection(collectionId, tokenId) = deepLink,
              collectionItems.contains(where: { $0.id == collectionId }) else {
            return
        }

        let trackingMode = widgetOpenTrackingMode()
        if let tokenId {
            openWidgetToken(collectionId: collectionId, tokenId: tokenId, trackingMode: trackingMode)
        } else {
            openCollection(
                collectionId: collectionId,
                presentationTransition: .instant,
                trackingMode: trackingMode
            )
        }
    }

    private func openWidgetToken(
        collectionId: String,
        tokenId: String,
        trackingMode: PlayerViewingSessionTrackingMode
    ) {
        guard let widgetTokenInsertion = MobileCollectionCatalog.widgetTokenInsertion(
            collectionId: collectionId,
            widgetTokenId: tokenId,
            progress: MobileViewingProgressStore.progress(collectionId: collectionId)
        ) else {
            openCollection(
                collectionId: collectionId,
                presentationTransition: .instant,
                trackingMode: trackingMode
            )
            return
        }

        MobileViewingProgressStore.save(widgetTokenInsertion.updatedAnchorProgress())
        openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            widgetTokenInsertion: widgetTokenInsertion,
            presentationTransition: .instant,
            trackingMode: trackingMode
        )
    }

    private func openPlayer(
        initialItemId: String,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil,
        presentationTransition: PlayerPresentationTransition = .animated,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        if trackingMode.updatesContinueViewing {
            MobileViewingProgressStore.setContinueViewingCollectionId(continueViewingCollectionId)
        }
        let config = MobilePlayerPrewarmer.preparedConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId,
            trackingMode: trackingMode,
            widgetTokenInsertion: widgetTokenInsertion
        )

        let presentPlayer = {
            playerPresentationTransition = presentationTransition
            playerConfig = config
        }
        switch presentationTransition {
        case .animated:
            withAnimation(playerCrossfadeAnimation) {
                presentPlayer()
            }
        case .instant:
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presentPlayer()
            }
        }
        Haptic.selectionChanged()
    }

    private func dismissPlayer(_ config: MobilePlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        playerPresentationTransition = .animated
        withAnimation(playerCrossfadeAnimation) {
            playerConfig = nil
            refreshViewingProgress()
        }
    }

    private func refreshViewingProgress() {
        let progressSnapshot = MobileViewingProgressStore.progressSnapshot()
        viewingProgressByCollectionId = progressSnapshot.percentagesByCollectionId
        viewedToEndCollectionIds = progressSnapshot.viewedToEndCollectionIds
        continueViewingProgress = progressSnapshot.continueViewingProgress
    }

    private func schedulePlayerPrewarm() {
        MobilePlayerPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: likelyInitialCollectionIds()
        )
    }

    private func widgetOpenTrackingMode() -> PlayerViewingSessionTrackingMode {
        MobileViewingProgressStore.progressSnapshot().continueViewingProgress == nil
            ? .updateContinueViewing
            : .progressOnly
    }

    private func likelyInitialCollectionIds() -> [String] {
        InfiniteCollectionsLoop
            .initialSourceIndices(itemCount: collectionItems.count, limit: 2)
            .map { collectionItems[$0].id }
    }
    
}

private struct InfiniteCollectionsGridView: UIViewRepresentable {
    let items: [MobileCollectionItem]
    let progressByCollectionId: [String: Int]
    let viewedToEndCollectionIds: Set<String>
    let onSelect: (MobileCollectionItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(items: [], progressByCollectionId: [:], viewedToEndCollectionIds: [], onSelect: onSelect)
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

        enum UpdateResult {
            case noChange
            case progressOnly
            case itemsChanged
        }

        init(
            items: [MobileCollectionItem],
            progressByCollectionId: [String: Int],
            viewedToEndCollectionIds: Set<String>,
            onSelect: @escaping (MobileCollectionItem) -> Void
        ) {
            self.items = items
            self.progressByCollectionId = progressByCollectionId
            self.viewedToEndCollectionIds = viewedToEndCollectionIds
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
                return UIMenu(title: item.name, children: [playAction])
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isRecentering,
                  let collectionView = scrollView as? UICollectionView,
                  !items.isEmpty,
                  let topIndexPath = collectionView.indexPathsForVisibleItems.min(by: { $0.item < $1.item }) else {
                return
            }

            let itemCount = items.count
            let repetition = InfiniteCollectionsLoop.repetition(for: topIndexPath.item, itemCount: itemCount)
            guard InfiniteCollectionsLoop.shouldRecenter(repetition: repetition),
                  let topAttributes = collectionView.layoutAttributesForItem(at: topIndexPath) else {
                return
            }

            let sourceIndex = InfiniteCollectionsLoop.sourceIndex(for: topIndexPath.item, itemCount: itemCount)
            let targetIndexPath = IndexPath(item: InfiniteCollectionsLoop.centeredIndex(sourceIndex: sourceIndex, itemCount: itemCount), section: 0)
            collectionView.layoutIfNeeded()
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else { return }

            isRecentering = true
            let offsetWithinTopItem = collectionView.contentOffset.y - topAttributes.frame.minY
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: targetAttributes.frame.minY + offsetWithinTopItem),
                animated: false
            )
            isRecentering = false
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            prefetchImages(for: indexPaths, in: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            cancelPrefetchingImages(for: indexPaths, in: collectionView)
        }

        func setInitialScrollPosition(in collectionView: UICollectionView) {
            guard !items.isEmpty,
                  let targetIndex = InfiniteCollectionsLoop.initialScrollPosition(itemCount: items.count) else {
                return
            }

            collectionView.layoutIfNeeded()
            let targetIndexPath = IndexPath(item: targetIndex, section: 0)
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else {
                collectionView.scrollToItem(at: targetIndexPath, at: .top, animated: false)
                return
            }

            let targetContentOffset = CGPoint(x: 0, y: targetAttributes.frame.minY)
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
    }
}

private final class InfiniteCollectionsGridContainerView: UIView {
    private let collectionView: UICollectionView
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
        collectionView.register(CollectionGridCell.self, forCellWithReuseIdentifier: CollectionGridCell.reuseIdentifier)
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        if previousBoundsSize != bounds.size {
            previousBoundsSize = bounds.size
            if updateGridLayoutItemSize() {
                coordinator?.updateVisibleProgressCells(in: collectionView)
                coordinator?.prefetchImages(aroundVisibleItemsIn: collectionView)
            }
        }

        guard !didSetInitialScrollPosition,
              bounds.width > 0,
              bounds.height > 0,
              collectionView.numberOfItems(inSection: 0) > 0 else {
            return
        }

        coordinator?.setInitialScrollPosition(in: collectionView)
        didSetInitialScrollPosition = true
        coordinator?.prefetchImages(aroundVisibleItemsIn: collectionView)
        collectionView.layoutIfNeeded()
        coordinator?.finishInitialCoverFadeScheduling()
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
}

private final class MobileCollectionCoverImageCache {
    static let shared = MobileCollectionCoverImageCache()

    private let visibleQueue = DispatchQueue(label: "org.lil.nft-player.mobile-collection-cover-cache.visible", qos: .userInitiated)
    private let prefetchQueue = DispatchQueue(label: "org.lil.nft-player.mobile-collection-cover-cache.prefetch", qos: .utility)
    private let lock = NSLock()
    private let cache = NSCache<NSString, UIImage>()
    private var pendingPrefetchKeys = Set<String>()
    private var cancelledPrefetchKeys = Set<String>()

    private init() {
        cache.countLimit = 320
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(assetName: String, targetSize: CGSize, displayScale: CGFloat) -> UIImage? {
        let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
        return cache.object(forKey: cacheKey(assetName: assetName, targetPixelSide: targetPixelSide) as NSString)
    }

    func loadImage(
        assetName: String,
        targetSize: CGSize,
        displayScale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) {
        let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
        let key = cacheKey(assetName: assetName, targetPixelSide: targetPixelSide)
        if let image = cache.object(forKey: key as NSString) {
            completion(image)
            return
        }

        visibleQueue.async { [cache] in
            if let cachedImage = cache.object(forKey: key as NSString) {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }

            let image = Self.preparedImage(
                assetName: assetName,
                targetPixelSide: targetPixelSide,
                displayScale: displayScale
            )
            if let image {
                cache.setObject(image, forKey: key as NSString, cost: image.memoryCost)
            }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func prefetch(assetNames: [String], targetSize: CGSize, displayScale: CGFloat) {
        assetNames.forEach { assetName in
            let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
            let key = cacheKey(assetName: assetName, targetPixelSide: targetPixelSide)
            guard cache.object(forKey: key as NSString) == nil else { return }
            guard shouldSchedulePrefetch(forKey: key) else { return }

            prefetchQueue.async { [cache] in
                guard self.shouldRunPrefetch(forKey: key) else { return }
                guard cache.object(forKey: key as NSString) == nil else {
                    self.finishPrefetch(forKey: key)
                    return
                }

                let image = Self.preparedImage(
                    assetName: assetName,
                    targetPixelSide: targetPixelSide,
                    displayScale: displayScale
                )
                if let image {
                    cache.setObject(image, forKey: key as NSString, cost: image.memoryCost)
                }
                self.finishPrefetch(forKey: key)
            }
        }
    }

    func cancelPrefetch(assetNames: [String], targetSize: CGSize, displayScale: CGFloat) {
        let targetPixelSide = targetPixelSide(for: targetSize, displayScale: displayScale)
        let keys = assetNames.map { assetName in
            cacheKey(assetName: assetName, targetPixelSide: targetPixelSide)
        }
        lock.withLock {
            keys.forEach { key in
                guard pendingPrefetchKeys.contains(key) else { return }
                cancelledPrefetchKeys.insert(key)
            }
        }
    }

    private func targetPixelSide(for targetSize: CGSize, displayScale: CGFloat) -> Int {
        let pointSide = max(max(targetSize.width, targetSize.height), 1)
        return max(Int(ceil(pointSide * displayScale)), 1)
    }

    private func cacheKey(assetName: String, targetPixelSide: Int) -> String {
        "\(assetName)-\(targetPixelSide)"
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

    private static func preparedImage(assetName: String, targetPixelSide: Int, displayScale: CGFloat) -> UIImage? {
        autoreleasepool {
            guard let image = UIImage(named: assetName) else { return nil }

            let scale = max(displayScale, 1)
            let targetSide = CGFloat(targetPixelSide) / scale
            let targetSize = CGSize(width: targetSide, height: targetSide)
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return image }

            let fillScale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
            let scaledSize = CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
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
    }
}

private extension UIImage {
    var memoryCost: Int {
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

private struct ContinueViewingButton: View {
    let progress: MobileViewingProgress
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Images.play
                    .font(.subheadline.weight(.bold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.continueViewing)
                        .font(.caption.weight(.semibold))
                    Text(progress.collectionName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(Strings.percent(progress.percent))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                ProgressCapsuleBackground(progress: progress.fraction, isInteractive: true)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerNavigationOverlay: UIViewControllerRepresentable {

    let config: MobilePlayerConfig
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PlayerOverlayViewController {
        let chrome = MobilePlayerChromeController(playerBackgroundColor: MobilePlayerBackgroundColor.color(for: config))
        let playerViewController = makeMobilePlayerViewController(config: config, onDismiss: onDismiss, chrome: chrome)
        let navigationController = PlayerNavigationController(rootViewController: playerViewController)
        navigationController.view.makeBackgroundTransparent()
        navigationController.navigationBar.isTranslucent = true
        navigationController.interactivePopGestureRecognizer?.isEnabled = false
        navigationController.setNavigationBarHidden(false, animated: false)

        return PlayerOverlayViewController(
            navigationController: navigationController,
            chrome: chrome,
            onDismiss: onDismiss
        )
    }

    func updateUIViewController(_ overlayViewController: PlayerOverlayViewController, context: Context) {
        overlayViewController.onDismiss = onDismiss
    }

}

private func makeMobilePlayerViewController(
    config: MobilePlayerConfig,
    onDismiss: @escaping () -> Void,
    chrome: MobilePlayerChromeController
) -> UIHostingController<MobilePlayerView> {
    let playerViewController = MobilePlayerHostingController(rootView: MobilePlayerView(config: config, onDismiss: onDismiss, chrome: chrome))
    playerViewController.view.makeBackgroundTransparent()
    return playerViewController
}

private final class MobilePlayerHostingController: UIHostingController<MobilePlayerView> {

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

}

private final class PlayerNavigationController: UINavigationController {

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

}

private final class PlayerOverlayViewController: UIViewController, UIGestureRecognizerDelegate {

    private static let dismissBackgroundClearPassDelay: TimeInterval = 0.05
    private static let dismissGestureBackgroundClearPasses = 4
    private static let finalDismissBackgroundClearPasses = 2

    private struct PlayerBackgroundSnapshot {
        weak var view: UIView?
        let backgroundColor: UIColor?
        let isOpaque: Bool
    }

    let playerNavigationController: UINavigationController
    let chrome: MobilePlayerChromeController
    var onDismiss: () -> Void

    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    private lazy var controlsPan = UIPanGestureRecognizer(target: self, action: #selector(handleControlsPan(_:)))
    private let dimmingView = UIView()
    private var configuredScrollPanGestures = Set<ObjectIdentifier>()
    private var isDismissing = false
    private var isDismissPanDrivingPlayerDismiss = false
    private var didControlsPanConflictWithHorizontalScroll = false
    private var dismissBackgroundSnapshots: [PlayerBackgroundSnapshot] = []

    init(
        navigationController: UINavigationController,
        chrome: MobilePlayerChromeController,
        onDismiss: @escaping () -> Void
    ) {
        self.playerNavigationController = navigationController
        self.chrome = chrome
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        chrome.onPlayerBackgroundColorChange = { [weak self] color in
            self?.setPlayerBackgroundColor(color)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override var childForStatusBarHidden: UIViewController? {
        playerNavigationController
    }

    override var childForStatusBarStyle: UIViewController? {
        playerNavigationController
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.makeBackgroundTransparent()

        dimmingView.backgroundColor = chrome.playerBackgroundColor
        dimmingView.alpha = 1
        view.addSubview(dimmingView)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        addChild(playerNavigationController)
        view.addSubview(playerNavigationController.view)
        playerNavigationController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerNavigationController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerNavigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerNavigationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerNavigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        playerNavigationController.didMove(toParent: self)

        dismissPan.delegate = self
        dismissPan.cancelsTouchesInView = false
        dismissPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(dismissPan)

        controlsPan.delegate = self
        controlsPan.cancelsTouchesInView = false
        controlsPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(controlsPan)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configurePagingScrollViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePagingScrollViews()
    }

    private func configurePagingScrollViews() {
        playerNavigationController.view
            .allSubviews(ofType: UIScrollView.self)
            .forEach { scrollView in
                let panGestureId = ObjectIdentifier(scrollView.panGestureRecognizer)
                if !configuredScrollPanGestures.contains(panGestureId) {
                    scrollView.panGestureRecognizer.require(toFail: dismissPan)
                    configuredScrollPanGestures.insert(panGestureId)
                }
                scrollView.hideAutomaticScrollEdgeEffects()
            }
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else { return }

        let translation = gesture.translation(in: view)
        let clampedY = max(0, translation.y)

        switch gesture.state {
        case .began:
            let location = gesture.location(in: playerNavigationController.view)
            let velocity = gesture.velocity(in: view)
            isDismissPanDrivingPlayerDismiss = hasPlayerDismissIntent(location: location, velocity: velocity)

            if isDismissPanDrivingPlayerDismiss {
                playerNavigationController.view.layer.removeAllAnimations()
                dimmingView.layer.removeAllAnimations()
                startDismissBackgroundClearing()
                setDismissStatusBarRevealed(true)
            }
            chrome.setControlsVisible(false)

        case .changed:
            guard isDismissPanDrivingPlayerDismiss else { return }
            let progress = min(clampedY / MobilePlayerGestureTuning.dismissProgressDistance, 1)
            applyDismissPresentation(offsetY: clampedY, progress: progress)

        case .ended:
            guard isDismissPanDrivingPlayerDismiss else { return }
            isDismissPanDrivingPlayerDismiss = false
            finishDismissGesture(translation: translation, velocity: gesture.velocity(in: view))

        case .cancelled, .failed:
            guard isDismissPanDrivingPlayerDismiss else { return }
            isDismissPanDrivingPlayerDismiss = false
            resetDismissTransform()

        default:
            break
        }
    }

    @objc private func handleControlsPan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else { return }

        switch gesture.state {
        case .began:
            didControlsPanConflictWithHorizontalScroll = isHorizontalPlayerScrollActive()
            revealControlsIfAllowed(for: gesture)

        case .changed:
            if isHorizontalPlayerScrollActive() {
                didControlsPanConflictWithHorizontalScroll = true
            }
            revealControlsIfAllowed(for: gesture)

        case .ended, .cancelled, .failed:
            didControlsPanConflictWithHorizontalScroll = false

        default:
            break
        }
    }

    private func finishDismissGesture(translation: CGPoint, velocity: CGPoint) {
        let clampedY = max(0, translation.y)
        let projectedY = clampedY + max(velocity.y, 0) * MobilePlayerGestureTuning.dismissVelocityProjectionDuration
        let translationThreshold = max(
            MobilePlayerGestureTuning.dismissMinimumTranslation,
            view.bounds.height * MobilePlayerGestureTuning.dismissTranslationHeightRatio
        )
        let shouldDismiss = projectedY > translationThreshold
            || (velocity.y > MobilePlayerGestureTuning.dismissFastSwipeVelocity
                && clampedY > MobilePlayerGestureTuning.dismissMinimumFastSwipeTranslation)

        if shouldDismiss {
            isDismissing = true
            view.isUserInteractionEnabled = false
            setDismissStatusBarRevealed(true)
            makePlayerDismissBackgroundsTransparent()
            scheduleDismissBackgroundClearPasses(Self.finalDismissBackgroundClearPasses)
            let remainingDistance = max(view.bounds.height - clampedY, 0)
            let velocityDuration = velocity.y > 0 ? remainingDistance / velocity.y : 0.24
            let duration = min(max(TimeInterval(velocityDuration), 0.14), 0.24)
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
                self.applyDismissPresentation(offsetY: self.view.bounds.height, progress: 1)
            }, completion: { _ in
                self.onDismiss()
            })
        } else {
            resetDismissTransform()
        }
    }

    private func applyDismissPresentation(offsetY: CGFloat, progress: CGFloat) {
        let clampedProgress = min(max(progress, 0), 1)
        let underlayFadeProgress = min(clampedProgress / MobilePlayerGestureTuning.dismissUnderlayFadeCompletionProgress, 1)

        playerNavigationController.view.transform = CGAffineTransform(translationX: 0, y: offsetY)
        dimmingView.alpha = 1 - easeOutQuadratic(underlayFadeProgress)
    }

    private func resetDismissTransform() {
        setDismissStatusBarRevealed(false)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            self.playerNavigationController.view.transform = .identity
            self.dimmingView.alpha = 1
        }, completion: { _ in
            guard !self.isDismissPanDrivingPlayerDismiss else { return }
            self.restorePlayerDismissBackgrounds()
        })
    }

    private func setPlayerBackgroundColor(_ color: UIColor) {
        guard isViewLoaded else { return }

        dimmingView.backgroundColor = color
    }

    private func startDismissBackgroundClearing() {
        makePlayerDismissBackgroundsTransparent()
        scheduleDismissBackgroundClearPasses(Self.dismissGestureBackgroundClearPasses)
    }

    private func scheduleDismissBackgroundClearPasses(_ remainingPasses: Int) {
        guard remainingPasses > 0, isDismissPanDrivingPlayerDismiss || isDismissing else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissBackgroundClearPassDelay) { [weak self] in
            guard let self else { return }
            guard self.isDismissPanDrivingPlayerDismiss || self.isDismissing else { return }

            self.makePlayerDismissBackgroundsTransparent()
            self.scheduleDismissBackgroundClearPasses(remainingPasses - 1)
        }
    }

    private func makePlayerDismissBackgroundsTransparent() {
        guard let rootView = playerNavigationController.view else { return }

        ([rootView] + rootView.allSubviews(ofType: UIView.self)).forEach { view in
            guard shouldClearDismissBackground(view, relativeTo: rootView) else { return }
            if !hasDismissBackgroundSnapshot(for: view) {
                dismissBackgroundSnapshots.append(
                    PlayerBackgroundSnapshot(
                        view: view,
                        backgroundColor: view.backgroundColor,
                        isOpaque: view.isOpaque
                    )
                )
            }
            view.makeBackgroundTransparent()
        }
    }

    private func shouldClearDismissBackground(_ view: UIView, relativeTo rootView: UIView) -> Bool {
        guard isOpaquePlayerBackground(view.backgroundColor) else { return false }
        guard view === rootView || !rootView.bounds.isEmpty else { return view === rootView }

        let boundsInRoot = view.convert(view.bounds, to: rootView)
        return boundsInRoot.width >= rootView.bounds.width * 0.85
            && boundsInRoot.height >= rootView.bounds.height * 0.85
    }

    private func hasDismissBackgroundSnapshot(for view: UIView) -> Bool {
        dismissBackgroundSnapshots.contains { $0.view === view }
    }

    private func restorePlayerDismissBackgrounds() {
        dismissBackgroundSnapshots.forEach { snapshot in
            snapshot.view?.backgroundColor = snapshot.backgroundColor
            snapshot.view?.isOpaque = snapshot.isOpaque
        }
        dismissBackgroundSnapshots.removeAll()
    }

    private func isOpaquePlayerBackground(_ color: UIColor?) -> Bool {
        guard let color else { return false }

        return color.isOpaqueAndVisuallyEqual(to: chrome.playerBackgroundColor)
            || color.isOpaqueAndVisuallyEqual(to: MobilePlayerBackgroundColor.defaultColor)
    }

    private func easeOutQuadratic(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return 1 - pow(1 - clampedProgress, 2)
    }

    private func setDismissStatusBarRevealed(_ isRevealed: Bool) {
        guard chrome.isStatusBarRevealedByDismiss != isRevealed else { return }

        UIView.animate(withDuration: playerStatusBarRevealDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            withAnimation(playerStatusBarRevealAnimation) {
                self.chrome.setStatusBarRevealedByDismiss(isRevealed)
            }
            self.setNeedsStatusBarAppearanceUpdate()
            self.playerNavigationController.setNeedsStatusBarAppearanceUpdate()
            self.playerNavigationController.topViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === controlsPan {
            let location = controlsPan.location(in: playerNavigationController.view)
            guard !hasZoomedPlayerContent(at: location) else {
                return false
            }

            let velocity = controlsPan.velocity(in: view)
            return hasControlsRevealIntent(location: location, velocity: velocity)
        }

        guard gestureRecognizer === dismissPan else {
            return true
        }
        guard !isDismissing else {
            return false
        }

        let location = dismissPan.location(in: playerNavigationController.view)
        let velocity = dismissPan.velocity(in: view)

        guard !hasZoomedPlayerContent(at: location) else {
            return false
        }

        return hasPlayerDismissIntent(location: location, velocity: velocity)
            || (chrome.showControls && hasControlsHideIntent(location: location, velocity: velocity))
    }

    private func hasZoomedPlayerContent(at location: CGPoint) -> Bool {
        chrome.isPlayerContentZoomed && playerNavigationController.view.bounds.contains(location)
    }

    private func hasPlayerDismissIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        let bounds = playerNavigationController.view.bounds

        return bounds.contains(location)
            && velocity.y > MobilePlayerGestureTuning.dismissInitialVelocity
            && velocity.y > abs(velocity.x) * MobilePlayerGestureTuning.dismissVerticalIntentRatio
    }

    private func hasControlsRevealIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        playerNavigationController.view.bounds.contains(location)
            && velocity.y < -MobilePlayerGestureTuning.controlsRevealVelocity
            && abs(velocity.y) > abs(velocity.x) * MobilePlayerGestureTuning.controlsRevealVerticalIntentRatio
    }

    private func revealControlsIfAllowed(for gesture: UIPanGestureRecognizer) {
        guard !didControlsPanConflictWithHorizontalScroll else { return }

        let translation = gesture.translation(in: view)
        guard hasControlsRevealTranslation(translation) else { return }

        chrome.setControlsVisible(true)
    }

    private func hasControlsRevealTranslation(_ translation: CGPoint) -> Bool {
        translation.y < -MobilePlayerGestureTuning.controlsRevealMinimumTranslation
            && abs(translation.y) > abs(translation.x) * MobilePlayerGestureTuning.controlsRevealVerticalIntentRatio
    }

    private func isHorizontalPlayerScrollActive() -> Bool {
        playerNavigationController.view
            .allSubviews(ofType: UIScrollView.self)
            .contains { scrollView in
                let panGesture = scrollView.panGestureRecognizer
                guard panGesture.state == .began || panGesture.state == .changed else { return false }

                let translation = panGesture.translation(in: view)
                return abs(translation.x) > MobilePlayerGestureTuning.controlsRevealHorizontalScrollTolerance
            }
    }

    private func hasControlsHideIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        playerNavigationController.view.bounds.contains(location)
            && velocity.y > 0
            && velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === controlsPan || otherGestureRecognizer === controlsPan
    }

}

private extension UIView {

    func allSubviews<T: UIView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            var matchingSubviews = subview.allSubviews(ofType: type)
            if let subview = subview as? T {
                matchingSubviews.append(subview)
            }
            return matchingSubviews
        }
    }

}
