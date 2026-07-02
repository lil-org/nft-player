import SwiftUI
import UIKit

private let playerCrossfadeAnimation = Animation.easeInOut(duration: 0.18)
private let playerStatusBarRevealAnimation = Animation.easeInOut(duration: 0.38)
private let playerStatusBarRevealDuration: TimeInterval = 0.3
private let initialCollectionItemFadeDuration: TimeInterval = 0.3
private let initialCollectionItemFadeAnimationKey = "initialGridItemFade"
private let continueViewingLargeIPadMinimumWidth: CGFloat = 700
private let continueViewingContentSizedCollectionNameMaxWidth: CGFloat = 250
private let continueViewingCoverThumbnailSize: CGFloat = 14
private let continueViewingCoverThumbnailCornerRadius: CGFloat = 3
private let mobileCollectionsGridScrollPositionKey = "mobileCollectionsGridScrollPosition"

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
                    let usesContentSizedContinueViewingButton = UIDevice.current.userInterfaceIdiom == .pad
                        && geometry.size.width >= continueViewingLargeIPadMinimumWidth

                    VStack {
                        Spacer()
                        ContinueViewingButton(
                            progress: continueViewingProgress,
                            coverAssetName: coverAssetName(for: continueViewingProgress.collectionId),
                            usesContentSizedLayout: usesContentSizedContinueViewingButton
                        ) {
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

    private func coverAssetName(for collectionId: String) -> String {
        collectionItems.first { $0.id == collectionId }?.coverAssetName ?? collectionId
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
                limit: 2
            )
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

        func setInitialScrollPosition(
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

private final class InfiniteCollectionsGridContainerView: UIView {
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

    deinit {
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
    let coverAssetName: String
    var usesContentSizedLayout = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ContinueViewingCoverThumbnail(assetName: coverAssetName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.continueViewing)
                        .font(.caption.weight(.semibold))
                    collectionName
                }

                if !usesContentSizedLayout {
                    Spacer(minLength: 12)
                }

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

    @ViewBuilder
    private var collectionName: some View {
        let text = Text(progress.collectionName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)

        if usesContentSizedLayout {
            text
                .frame(maxWidth: continueViewingContentSizedCollectionNameMaxWidth, alignment: .leading)
                .layoutPriority(1)
        } else {
            text
        }
    }
}

private struct ContinueViewingCoverThumbnail: View {
    let assetName: String

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: LoadedImage?
    @State private var pendingThumbnailLoadKey: String?

    var body: some View {
        ZStack {
            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.18)
            }
        }
        .frame(width: continueViewingCoverThumbnailSize, height: continueViewingCoverThumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: continueViewingCoverThumbnailCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: continueViewingCoverThumbnailCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: thumbnailLoadKey) {
            await loadImage(for: thumbnailLoadKey)
        }
    }

    private var thumbnailLoadKey: String {
        "\(assetName)-\(displayScale)"
    }

    private var displayedImage: UIImage? {
        guard loadedImage?.loadKey == thumbnailLoadKey else { return nil }
        return loadedImage?.image
    }

    private var targetSize: CGSize {
        CGSize(width: continueViewingCoverThumbnailSize, height: continueViewingCoverThumbnailSize)
    }

    @MainActor
    private func loadImage(for loadKey: String) async {
        let scale = displayScale > 0 ? displayScale : UIScreen.main.scale
        pendingThumbnailLoadKey = loadKey
        if let cachedImage = MobileCollectionCoverImageCache.shared.cachedImage(
            assetName: assetName,
            targetSize: targetSize,
            displayScale: scale
        ) {
            loadedImage = LoadedImage(loadKey: loadKey, image: cachedImage)
            return
        }

        loadedImage = nil
        let requestedAssetName = assetName
        MobileCollectionCoverImageCache.shared.loadImage(
            assetName: requestedAssetName,
            targetSize: targetSize,
            displayScale: scale
        ) { loadedImage in
            guard pendingThumbnailLoadKey == loadKey,
                  let loadedImage else {
                return
            }
            self.loadedImage = LoadedImage(loadKey: loadKey, image: loadedImage)
        }
    }

    private struct LoadedImage {
        let loadKey: String
        let image: UIImage
    }
}

private struct PlayerNavigationOverlay: UIViewControllerRepresentable {

    let config: MobilePlayerConfig
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PlayerOverlayViewController {
        let chrome = MobilePlayerChromeController(playerBackgroundColor: MobilePlayerBackgroundColor.color(for: config))
        let playerViewController = makeMobilePlayerViewController(
            config: config,
            onDismiss: onDismiss,
            chrome: chrome
        )
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
    let playerViewController = MobilePlayerHostingController(
        rootView: MobilePlayerView(
            config: config,
            onDismiss: onDismiss,
            chrome: chrome
        )
    )
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

private final class CardTransitionUnderlayView: UIView {

    private static let lateLoadedImageFadeDuration: TimeInterval = 0.14

    private let descriptors: [DownloadableMediaDescriptor]
    private let hiddenSlotIndex: Int
    private let layoutImageSizes: [CGSize]
    private var imageViews = [UIImageView]()
    private var imageLoadCancellations = [(() -> Void)?]()
    private var otherCardsRevealProgress: CGFloat = 0

    init(
        descriptors: [DownloadableMediaDescriptor],
        hiddenSlotIndex: Int,
        fallbackImageSize: CGSize,
        layoutImageSizes: [CGSize]? = nil,
        initialImages: [UIImage]? = nil
    ) {
        let validFallbackImageSize = fallbackImageSize.validOrDefault
        self.descriptors = descriptors
        self.hiddenSlotIndex = hiddenSlotIndex
        if let layoutImageSizes,
           layoutImageSizes.count == descriptors.count {
            self.layoutImageSizes = layoutImageSizes.map(\.validOrDefault)
        } else {
            self.layoutImageSizes = descriptors.map { descriptor in
                DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor)?.size.validOrDefault
                    ?? validFallbackImageSize
            }
        }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        makeBackgroundTransparent()
        installImageViews()
        let validInitialImages = initialImages?.count == descriptors.count ? initialImages : nil
        loadImages(initialImages: validInitialImages)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        imageLoadCancellations.forEach { $0?() }
    }

    var hiddenSlotFrame: CGRect? {
        layoutIfNeeded()
        guard imageViews.indices.contains(hiddenSlotIndex) else { return nil }
        return imageViews[hiddenSlotIndex].frame
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyImageFrames()
    }

    func setOtherCardsRevealProgress(_ progress: CGFloat) {
        let clampedProgress = min(max(progress, 0), 1)
        otherCardsRevealProgress = clampedProgress
        for (index, imageView) in imageViews.enumerated() {
            if index == hiddenSlotIndex {
                imageView.alpha = 0
                imageView.isHidden = true
            } else {
                imageView.alpha = clampedProgress
                imageView.isHidden = false
            }
        }
    }

    private func installImageViews() {
        imageViews = descriptors.indices.map { index in
            let imageView = UIImageView()
            imageView.makeBackgroundTransparent()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            imageView.alpha = 0
            imageView.isHidden = index == hiddenSlotIndex
            addSubview(imageView)
            return imageView
        }
        imageLoadCancellations = Array(repeating: nil, count: descriptors.count)
    }

    private func loadImages(initialImages: [UIImage]?) {
        for (index, descriptor) in descriptors.enumerated() {
            guard index != hiddenSlotIndex else { continue }

            if let initialImage = initialImages?[index] {
                setImage(initialImage, at: index)
                continue
            }

            if let cachedImage = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
                setImage(cachedImage, at: index)
                continue
            }

            imageLoadCancellations[index] = DownloadableMediaCache.shared.loadImage(for: descriptor) { [weak self] image in
                guard let self, let image else { return }
                self.setImage(image, at: index)
            }
        }
    }

    private func setImage(_ image: UIImage, at index: Int) {
        guard imageViews.indices.contains(index) else { return }

        let imageView = imageViews[index]
        let shouldFadeInLateImage = index != hiddenSlotIndex
            && imageView.image == nil
            && otherCardsRevealProgress > 0

        if shouldFadeInLateImage {
            imageView.alpha = 0
        }
        imageView.image = image

        if shouldFadeInLateImage {
            let targetRevealProgress = otherCardsRevealProgress
            UIView.animate(
                withDuration: Self.lateLoadedImageFadeDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    imageView.alpha = targetRevealProgress
                }
            )
        }
    }

    private func applyImageFrames() {
        let frames = MobileStaticImageSpreadLayout(imageSizes: layoutImageSizes).itemFrames(fitting: bounds.size)
        for (imageView, frame) in zip(imageViews, frames) {
            imageView.frame = frame
        }
    }

}

private extension CGSize {
    var validOrDefault: CGSize {
        guard width > 0,
              height > 0,
              width.isFinite,
              height.isFinite else {
            return CGSize(width: 1, height: 1)
        }
        return self
    }
}

private enum CardLayoutPinchDirection {
    case inward
    case outward

    func hasReachedActivation(scale: CGFloat, activationScale: CGFloat) -> Bool {
        switch self {
        case .inward:
            return scale <= activationScale
        case .outward:
            return scale >= activationScale
        }
    }

    func hasMovedOppositeDirection(scale: CGFloat, failureScale: CGFloat) -> Bool {
        switch self {
        case .inward:
            return scale > failureScale
        case .outward:
            return scale < failureScale
        }
    }
}

private final class CardLayoutPinchGestureRecognizer: UIGestureRecognizer {

    var activationScale: CGFloat = 1
    var oppositeDirectionFailureScale: CGFloat = 1
    var direction: CardLayoutPinchDirection = .inward
    var canTrackPinch: ((CardLayoutPinchGestureRecognizer) -> Bool)?
    var onReset: (() -> Void)?

    private(set) var scale: CGFloat = 1
    private(set) var velocity: CGFloat = 0

    private var trackedTouches: [UITouch] = []
    private var initialDistance: CGFloat = 0
    private var initialLocationInView = CGPoint.zero
    private var previousScale: CGFloat = 1
    private var previousTimestamp: TimeInterval = 0
    private var hasEvaluatedCanTrackPinch = false

    var isFirstPinchTrackingEvaluation: Bool {
        !hasEvaluatedCanTrackPinch
    }

    var isTrackingPinch: Bool {
        switch state {
        case .possible, .began, .changed:
            return trackedTouches.count == 2
        default:
            return false
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible,
              trackedTouches.count + touches.count <= 2 else {
            cancelOrFail()
            return
        }

        trackedTouches.append(contentsOf: touches.prefix(2 - trackedTouches.count))

        guard trackedTouches.count == 2 else { return }
        guard let view,
              let distance = distanceBetweenTrackedTouches(in: view),
              distance > 0 else {
            state = .failed
            return
        }

        initialDistance = distance
        initialLocationInView = currentPinchLocation(in: view)
        previousTimestamp = event.timestamp
        scale = 1
        previousScale = 1
        velocity = 0
        hasEvaluatedCanTrackPinch = false

        guard canTrackCurrentPinch() else {
            state = .failed
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard isTrackingPinch,
              touches.contains(where: { trackedTouches.contains($0) }) else {
            return
        }

        updateScaleAndVelocity(timestamp: event.timestamp)

        switch state {
        case .possible:
            guard canTrackCurrentPinch() else {
                state = .failed
                return
            }

            if direction.hasMovedOppositeDirection(scale: scale, failureScale: oppositeDirectionFailureScale) {
                state = .failed
            } else if direction.hasReachedActivation(scale: scale, activationScale: activationScale) {
                state = .began
            }

        case .began, .changed:
            state = .changed

        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.contains(where: { trackedTouches.contains($0) }) else { return }

        switch state {
        case .began, .changed:
            updateScaleAndVelocity(timestamp: event.timestamp)
            state = .ended
        case .possible:
            state = .failed
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelOrFail()
    }

    override func reset() {
        trackedTouches = []
        initialDistance = 0
        initialLocationInView = .zero
        previousScale = 1
        previousTimestamp = 0
        scale = 1
        velocity = 0
        hasEvaluatedCanTrackPinch = false
        onReset?()
    }

    func pinchLocation(in targetView: UIView?) -> CGPoint {
        currentPinchLocation(in: targetView)
    }

    func initialPinchLocation(in targetView: UIView?) -> CGPoint {
        guard let view else { return initialLocationInView }
        return view.convert(initialLocationInView, to: targetView)
    }

    private func updateScaleAndVelocity(timestamp: TimeInterval) {
        guard let view,
              let distance = distanceBetweenTrackedTouches(in: view),
              initialDistance > 0 else {
            return
        }

        let nextScale = distance / initialDistance
        let elapsed = timestamp - previousTimestamp
        velocity = elapsed > 0 ? (nextScale - previousScale) / CGFloat(elapsed) : 0
        scale = nextScale
        previousScale = nextScale
        previousTimestamp = timestamp
    }

    private func canTrackCurrentPinch() -> Bool {
        defer {
            hasEvaluatedCanTrackPinch = true
        }

        return canTrackPinch?(self) == true
    }

    private func currentPinchLocation(in targetView: UIView?) -> CGPoint {
        guard trackedTouches.count == 2 else { return .zero }

        let firstLocation = trackedTouches[0].location(in: targetView)
        let secondLocation = trackedTouches[1].location(in: targetView)
        return CGPoint(
            x: (firstLocation.x + secondLocation.x) / 2,
            y: (firstLocation.y + secondLocation.y) / 2
        )
    }

    private func distanceBetweenTrackedTouches(in targetView: UIView) -> CGFloat? {
        guard trackedTouches.count == 2 else { return nil }

        let firstLocation = trackedTouches[0].location(in: targetView)
        let secondLocation = trackedTouches[1].location(in: targetView)
        return hypot(firstLocation.x - secondLocation.x, firstLocation.y - secondLocation.y)
    }

    private func cancelOrFail() {
        switch state {
        case .began, .changed:
            state = .cancelled
        default:
            state = .failed
        }
    }

}

private final class PendingGesturePresentationUpdate {

    private var isScheduled = false
    private var generation = 0
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func schedule() {
        assert(Thread.isMainThread)
        guard !isScheduled else { return }

        isScheduled = true
        let scheduledGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isScheduled,
                  self.generation == scheduledGeneration else {
                return
            }

            self.isScheduled = false
            self.action()
        }
    }

    func flush() {
        assert(Thread.isMainThread)
        guard isScheduled else { return }

        invalidate()
        action()
    }

    func invalidate() {
        assert(Thread.isMainThread)
        guard isScheduled else { return }

        isScheduled = false
        generation += 1
    }

}

private final class PlayerOverlayViewController: UIViewController, UIGestureRecognizerDelegate {

    private static let dismissBackgroundClearPassDelay: TimeInterval = 0.05
    private static let dismissGestureBackgroundClearPasses = 4
    private static let finalDismissBackgroundClearPasses = 2
    private static let cardExpandContentReadyFallbackDelay: TimeInterval = 1.0
    private static let cardTransitionHorizontalDragDamping: CGFloat = 0.18
    private static let cardTransitionVerticalDragDamping: CGFloat = 0.32
    private static let navigationBarSideControlRegionWidth: CGFloat = 96

    private struct PlayerBackgroundSnapshot {
        weak var view: UIView?
        let backgroundColor: UIColor?
        let isOpaque: Bool
    }

    private struct CardMinimizeTransitionContext {
        let sourceFrame: CGRect
        let targetFrame: CGRect?
        let targetScale: CGFloat
        let foregroundView: UIView
        let underlayView: CardTransitionUnderlayView
    }

    private struct CardExpandTransitionContext {
        let id: UUID
        let targetPagePosition: PlayerPagePosition
        let sourceFrame: CGRect
        let targetFrame: CGRect
        let targetScale: CGFloat
        let foregroundView: UIView
        let underlayView: CardTransitionUnderlayView
    }

    let playerNavigationController: UINavigationController
    let chrome: MobilePlayerChromeController
    var onDismiss: () -> Void

    private lazy var navigationBarTap = UITapGestureRecognizer(target: self, action: #selector(handleNavigationBarTap(_:)))
    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    private lazy var playerDismissPinch: CardLayoutPinchGestureRecognizer = {
        let gesture = CardLayoutPinchGestureRecognizer(target: self, action: #selector(handlePlayerDismissPinch(_:)))
        gesture.direction = .inward
        gesture.activationScale = MobilePlayerGestureTuning.playerDismissPinchActivationScale
        gesture.oppositeDirectionFailureScale = MobilePlayerGestureTuning.playerDismissPinchZoomInFailureScale
        gesture.canTrackPinch = { [weak self] gesture in
            guard let self else { return false }
            if gesture.isFirstPinchTrackingEvaluation {
                self.configurePagingScrollViews()
            }
            return self.canBeginPlayerDismissPinch(
                location: gesture.pinchLocation(in: self.playerNavigationController.view)
            )
        }
        gesture.onReset = { [weak self] in
            self?.resetPlayerDismissPinchState()
        }
        return gesture
    }()
    private lazy var controlsPan = UIPanGestureRecognizer(target: self, action: #selector(handleControlsPan(_:)))
    private lazy var cardMinimizePinch: CardLayoutPinchGestureRecognizer = {
        let gesture = CardLayoutPinchGestureRecognizer(target: self, action: #selector(handleCardMinimizePinch(_:)))
        gesture.direction = .inward
        gesture.activationScale = MobilePlayerGestureTuning.cardMinimizePinchActivationScale
        gesture.oppositeDirectionFailureScale = MobilePlayerGestureTuning.cardMinimizePinchZoomInFailureScale
        gesture.canTrackPinch = { [weak self] gesture in
            guard let self else { return false }
            if gesture.isFirstPinchTrackingEvaluation {
                self.configurePagingScrollViews()
            }
            return self.canBeginCardMinimizeInteraction(
                location: gesture.pinchLocation(in: self.playerNavigationController.view)
            )
        }
        return gesture
    }()
    private lazy var cardExpandPinch: CardLayoutPinchGestureRecognizer = {
        let gesture = CardLayoutPinchGestureRecognizer(target: self, action: #selector(handleCardExpandPinch(_:)))
        gesture.direction = .outward
        gesture.activationScale = MobilePlayerGestureTuning.cardExpandPinchActivationScale
        gesture.oppositeDirectionFailureScale = MobilePlayerGestureTuning.cardExpandPinchZoomOutFailureScale
        gesture.canTrackPinch = { [weak self] gesture in
            guard let self else { return false }
            if gesture.isFirstPinchTrackingEvaluation {
                self.configurePagingScrollViews()
            }
            return self.canSelectCardExpandPinch(for: gesture)
        }
        gesture.onReset = { [weak self] in
            self?.resetCardExpandPinchState()
        }
        return gesture
    }()
    private lazy var cardMinimizeRotation = UIRotationGestureRecognizer(target: self, action: #selector(handleCardMinimizeRotation(_:)))
    private let dimmingView = UIView()
    private var configuredScrollPanGestures = Set<ObjectIdentifier>()
    private var configuredScrollPinchGestures = Set<ObjectIdentifier>()
    private var isDismissing = false
    private var isDismissPanDrivingPlayerDismiss = false
    private var isPlayerDismissPinchDrivingPlayerDismiss = false
    private var playerDismissPinchStartLocation = CGPoint.zero
    private lazy var playerDismissPinchPresentationUpdate = PendingGesturePresentationUpdate { [weak self] in
        guard let self else { return }
        guard self.isPlayerDismissPinchDrivingPlayerDismiss else { return }

        self.applyPlayerDismissPinchPresentation(self.playerDismissPinch)
    }
    private var isDismissPanDrivingCardMinimize = false
    private var isCardMinimizePinchDrivingCardMinimize = false
    private var cardMinimizePinchStartLocation = CGPoint.zero
    private var cardMinimizePinchStartRotation: CGFloat = 0
    private var cardMinimizePinchRotation: CGFloat = 0
    private lazy var cardMinimizePinchPresentationUpdate = PendingGesturePresentationUpdate { [weak self] in
        guard let self else { return }
        guard self.isCardMinimizePinchDrivingCardMinimize else { return }

        self.applyCardMinimizePinchPresentation(self.cardMinimizePinch)
    }
    private var isCardExpandPinchDrivingCardExpand = false
    private var cardExpandPinchStartLocation = CGPoint.zero
    private lazy var cardExpandPinchPresentationUpdate = PendingGesturePresentationUpdate { [weak self] in
        guard let self else { return }
        guard self.isCardExpandPinchDrivingCardExpand else { return }

        self.applyCardExpandPinchPresentation(self.cardExpandPinch)
    }
    private var activeCardMinimizeContext: CardMinimizeTransitionContext?
    private var activeCardExpandContext: CardExpandTransitionContext?
    private var isCardExpandAnimationComplete = false
    private var isCardExpandContentReady = false
    private var cardExpandContentReadyFallbackWorkItem: DispatchWorkItem?
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
        chrome.onCardNftMinimizeToFourPerPageRequest = { [weak self] in
            self?.beginProgrammaticCardMinimize() ?? false
        }
        chrome.onCardNftExpandFromFourPerPageRequest = { [weak self] selection in
            self?.beginProgrammaticCardExpand(selection: selection) ?? .rejected
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

        navigationBarTap.delegate = self
        navigationBarTap.numberOfTapsRequired = 1
        navigationBarTap.numberOfTouchesRequired = 1
        navigationBarTap.cancelsTouchesInView = false
        playerNavigationController.navigationBar.addGestureRecognizer(navigationBarTap)

        dismissPan.delegate = self
        dismissPan.cancelsTouchesInView = false
        dismissPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(dismissPan)

        playerDismissPinch.delegate = self
        playerDismissPinch.cancelsTouchesInView = false
        view.addGestureRecognizer(playerDismissPinch)

        controlsPan.delegate = self
        controlsPan.cancelsTouchesInView = false
        controlsPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(controlsPan)

        cardMinimizePinch.delegate = self
        cardMinimizePinch.cancelsTouchesInView = false
        view.addGestureRecognizer(cardMinimizePinch)

        cardExpandPinch.delegate = self
        cardExpandPinch.cancelsTouchesInView = false
        view.addGestureRecognizer(cardExpandPinch)

        cardMinimizeRotation.delegate = self
        cardMinimizeRotation.cancelsTouchesInView = false
        view.addGestureRecognizer(cardMinimizeRotation)
    }

    @objc private func handleNavigationBarTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        chrome.setControlsVisible(false)
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
                if let pinchGesture = scrollView.pinchGestureRecognizer {
                    let pinchGestureId = ObjectIdentifier(pinchGesture)
                    if !configuredScrollPinchGestures.contains(pinchGestureId) {
                        pinchGesture.require(toFail: playerDismissPinch)
                        pinchGesture.require(toFail: cardMinimizePinch)
                        pinchGesture.require(toFail: cardExpandPinch)
                        configuredScrollPinchGestures.insert(pinchGestureId)
                    }
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
            let cardMinimizeState = cardMinimizeStateForIntent(location: location, velocity: velocity)
            let hasPlayerDismissIntent = hasPlayerDismissIntent(location: location, velocity: velocity)
            let shouldHideControls = chrome.showControls && hasControlsHideIntent(location: location, velocity: velocity)
            isDismissPanDrivingPlayerDismiss = false
            isDismissPanDrivingCardMinimize = false

            if let cardMinimizeState {
                guard beginCardMinimizeFromDismissPan(state: cardMinimizeState) else { return }
            } else {
                isDismissPanDrivingPlayerDismiss = hasPlayerDismissIntent
            }

            if isDismissPanDrivingPlayerDismiss {
                playerNavigationController.view.layer.removeAllAnimations()
                dimmingView.layer.removeAllAnimations()
                startDismissBackgroundClearing()
                setDismissStatusBarRevealed(true)
            }
            if !isDismissPanDrivingCardMinimize && (isDismissPanDrivingPlayerDismiss || shouldHideControls) {
                chrome.setControlsVisible(false)
            }

        case .changed:
            if isDismissPanDrivingCardMinimize {
                applyCardMinimizePresentation(translation: translation)
                return
            }
            guard isDismissPanDrivingPlayerDismiss else { return }
            let progress = min(clampedY / MobilePlayerGestureTuning.dismissProgressDistance, 1)
            applyDismissPresentation(offsetY: clampedY, progress: progress)

        case .ended:
            if isDismissPanDrivingCardMinimize {
                isDismissPanDrivingCardMinimize = false
                finishCardMinimizeGesture(
                    translation: translation,
                    velocity: gesture.velocity(in: view)
                )
                return
            }
            guard isDismissPanDrivingPlayerDismiss else { return }
            isDismissPanDrivingPlayerDismiss = false
            finishDismissGesture(translation: translation, velocity: gesture.velocity(in: view))

        case .cancelled, .failed:
            if isDismissPanDrivingCardMinimize {
                isDismissPanDrivingCardMinimize = false
                resetCardMinimizeTransform()
                return
            }
            guard isDismissPanDrivingPlayerDismiss else { return }
            isDismissPanDrivingPlayerDismiss = false
            resetDismissTransform()

        default:
            break
        }
    }

    @objc private func handlePlayerDismissPinch(_ gesture: CardLayoutPinchGestureRecognizer) {
        guard !isDismissing else { return }

        switch gesture.state {
        case .began:
            isPlayerDismissPinchDrivingPlayerDismiss = false
            playerDismissPinchStartLocation = gesture.initialPinchLocation(in: view)

            guard beginPlayerDismissPinchGesture(
                location: gesture.pinchLocation(in: playerNavigationController.view)
            ) else {
                resetPlayerDismissPinchState()
                return
            }

            applyPlayerDismissPinchPresentation(gesture)

        case .changed:
            guard isPlayerDismissPinchDrivingPlayerDismiss else { return }

            schedulePlayerDismissPinchPresentationUpdate()

        case .ended:
            if isPlayerDismissPinchDrivingPlayerDismiss {
                flushPendingPlayerDismissPinchPresentationUpdate()
                isPlayerDismissPinchDrivingPlayerDismiss = false
                finishPlayerDismissPinchGesture(scale: gesture.scale, velocity: gesture.velocity)
            }
            resetPlayerDismissPinchState()

        case .cancelled, .failed:
            if isPlayerDismissPinchDrivingPlayerDismiss {
                flushPendingPlayerDismissPinchPresentationUpdate()
                isPlayerDismissPinchDrivingPlayerDismiss = false
                resetDismissTransform()
            }
            resetPlayerDismissPinchState()

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

    @objc private func handleCardMinimizePinch(_ gesture: CardLayoutPinchGestureRecognizer) {
        guard !isDismissing else { return }

        switch gesture.state {
        case .began:
            isCardMinimizePinchDrivingCardMinimize = false
            cardMinimizePinchStartLocation = gesture.initialPinchLocation(in: view)

            guard let state = cardMinimizeStateForPinch(location: gesture.pinchLocation(in: playerNavigationController.view)),
                  beginCardMinimizePinchGesture(state: state) else {
                resetCardMinimizePinchState()
                return
            }

            applyCardMinimizePinchPresentation(gesture)

        case .changed:
            guard isCardMinimizePinchDrivingCardMinimize else { return }

            scheduleCardMinimizePinchPresentationUpdate()

        case .ended:
            if isCardMinimizePinchDrivingCardMinimize {
                flushPendingCardMinimizePinchPresentationUpdate()
                finishCardMinimizePinchGesture(
                    scale: gesture.scale,
                    velocity: gesture.velocity
                )
            }
            resetCardMinimizePinchState()

        case .cancelled, .failed:
            if isCardMinimizePinchDrivingCardMinimize {
                flushPendingCardMinimizePinchPresentationUpdate()
                resetCardMinimizeTransform()
            }
            resetCardMinimizePinchState()

        default:
            break
        }
    }

    @objc private func handleCardExpandPinch(_ gesture: CardLayoutPinchGestureRecognizer) {
        guard !isDismissing else { return }

        switch gesture.state {
        case .began:
            isCardExpandPinchDrivingCardExpand = false
            cardExpandPinchStartLocation = gesture.initialPinchLocation(in: view)

            guard let selection = cardExpandPinchSelection(for: gesture),
                  beginCardExpandPinchGesture(selection: selection) else {
                resetCardExpandPinchState()
                return
            }

            applyCardExpandPinchPresentation(gesture)

        case .changed:
            guard isCardExpandPinchDrivingCardExpand else { return }

            scheduleCardExpandPinchPresentationUpdate()

        case .ended:
            if isCardExpandPinchDrivingCardExpand {
                flushPendingCardExpandPinchPresentationUpdate()
                finishCardExpandPinchGesture(scale: gesture.scale, velocity: gesture.velocity)
            }
            resetCardExpandPinchState()

        case .cancelled, .failed:
            if isCardExpandPinchDrivingCardExpand {
                flushPendingCardExpandPinchPresentationUpdate()
                resetCardExpandTransform()
            }
            resetCardExpandPinchState()

        default:
            break
        }
    }

    @objc private func handleCardMinimizeRotation(_ gesture: UIRotationGestureRecognizer) {
        guard !isDismissing else { return }

        switch gesture.state {
        case .began:
            guard isCardMinimizePinchDrivingCardMinimize else { return }

            cardMinimizePinchStartRotation = gesture.rotation
            cardMinimizePinchRotation = 0

        case .changed:
            guard isCardMinimizePinchDrivingCardMinimize else { return }

            cardMinimizePinchRotation = gesture.rotation - cardMinimizePinchStartRotation
            scheduleCardMinimizePinchPresentationUpdate()

        case .ended, .cancelled, .failed:
            if !isCardMinimizePinchDrivingCardMinimize {
                cardMinimizePinchRotation = 0
                cardMinimizePinchStartRotation = 0
            }

        default:
            break
        }
    }

    private func beginPlayerDismissPinchGesture(location: CGPoint) -> Bool {
        guard canBeginPlayerDismissPinch(location: location) else {
            return false
        }

        playerNavigationController.view.layer.removeAllAnimations()
        dimmingView.layer.removeAllAnimations()
        isPlayerDismissPinchDrivingPlayerDismiss = true
        startDismissBackgroundClearing()
        setDismissStatusBarRevealed(true)
        chrome.setControlsVisible(false)
        return true
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

    private func finishPlayerDismissPinchGesture(scale: CGFloat, velocity: CGFloat) {
        let currentProgress = playerDismissPinchProgress(forScale: scale)
        let projectedScale = scale + min(velocity, 0) * MobilePlayerGestureTuning.playerDismissPinchVelocityProjectionDuration
        let projectedProgress = max(
            currentProgress,
            playerDismissPinchProgress(forScale: projectedScale)
        )
        let hasEnoughProgressForVelocityCommit = currentProgress >= MobilePlayerGestureTuning.playerDismissPinchMinimumVelocityCommitProgress
        let shouldDismiss = currentProgress >= MobilePlayerGestureTuning.playerDismissPinchCompletionProgress
            || (hasEnoughProgressForVelocityCommit
                && (projectedProgress >= MobilePlayerGestureTuning.playerDismissPinchCompletionProgress
                    || velocity < -MobilePlayerGestureTuning.playerDismissPinchFastVelocity))

        guard shouldDismiss else {
            resetDismissTransform()
            return
        }

        isDismissing = true
        view.isUserInteractionEnabled = false
        setDismissStatusBarRevealed(true)
        makePlayerDismissBackgroundsTransparent()
        scheduleDismissBackgroundClearPasses(Self.finalDismissBackgroundClearPasses)

        let remainingScaleDistance = max(
            scale - MobilePlayerGestureTuning.playerDismissPinchFullProgressScale,
            0
        )
        let velocityDuration = velocity < 0 ? remainingScaleDistance / abs(velocity) : 0.22
        let duration = min(max(TimeInterval(velocityDuration), 0.14), 0.24)

        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.applyFinalPlayerDismissPinchPresentation()
        }, completion: { _ in
            self.onDismiss()
        })
    }

    private var isCardMinimizeTransitionActive: Bool {
        activeCardMinimizeContext != nil || isDismissPanDrivingCardMinimize || isCardMinimizePinchDrivingCardMinimize
    }

    private var isCardTransitionActive: Bool {
        isCardMinimizeTransitionActive || activeCardExpandContext != nil
    }

    private func beginCardMinimizeFromDismissPan(state: MobilePlayerLayoutInteractionState) -> Bool {
        beginCardMinimizeTransition(state: state, isDrivenByDismissPan: true)
    }

    private func beginCardMinimizePinchGesture(state: MobilePlayerLayoutInteractionState) -> Bool {
        guard beginCardMinimizeTransition(state: state, isDrivenByDismissPan: false) else {
            return false
        }

        cardMinimizePinchStartRotation = currentCardMinimizeRotationGestureValue()
        cardMinimizePinchRotation = 0
        isCardMinimizePinchDrivingCardMinimize = true
        return true
    }

    private func beginCardExpandPinchGesture(selection: MobilePlayerCardNftGridSelection) -> Bool {
        guard beginCardExpandTransition(selection: selection) else {
            return false
        }

        isCardExpandPinchDrivingCardExpand = true
        return true
    }

    private func beginProgrammaticCardMinimize() -> Bool {
        guard !isDismissing,
              !chrome.isPlayerContentZoomed else {
            return false
        }

        guard !isCardTransitionActive else {
            return true
        }

        guard beginCardMinimizeTransition(
            state: chrome.layoutInteractionState,
            isDrivenByDismissPan: false
        ) else {
            return false
        }

        completeCardMinimizeTransition()
        return true
    }

    private func beginProgrammaticCardExpand(
        selection: MobilePlayerCardNftGridSelection
    ) -> MobilePlayerCardNftExpandSelectionResult {
        guard !isDismissing,
              !chrome.isPlayerContentZoomed else {
            return .rejected
        }

        guard !isCardTransitionActive else {
            return .busy
        }

        guard beginCardExpandTransition(selection: selection) else {
            return .fallbackToImmediateOpen
        }

        completeCardExpandTransition()
        return .started
    }

    private func beginCardMinimizeTransition(
        state: MobilePlayerLayoutInteractionState,
        isDrivenByDismissPan: Bool
    ) -> Bool {
        playerNavigationController.view.layer.removeAllAnimations()
        dimmingView.layer.removeAllAnimations()

        guard let context = makeCardMinimizeTransitionContext(state: state) else {
            return false
        }

        activeCardMinimizeContext = context
        isDismissPanDrivingCardMinimize = isDrivenByDismissPan
        chrome.setPlayerContentHiddenForCardTransition(true)
        return true
    }

    private func beginCardExpandTransition(selection: MobilePlayerCardNftGridSelection) -> Bool {
        playerNavigationController.view.layer.removeAllAnimations()
        dimmingView.layer.removeAllAnimations()

        guard let context = makeCardExpandTransitionContext(selection: selection) else {
            return false
        }

        activeCardExpandContext = context
        isCardExpandAnimationComplete = false
        isCardExpandContentReady = false
        chrome.setPlayerContentHiddenForCardTransition(true)
        applyCardExpandPresentation(progress: 0)
        return true
    }

    private func finishCardMinimizeGesture(
        translation: CGPoint,
        velocity: CGPoint
    ) {
        guard activeCardMinimizeContext != nil else {
            resetCardMinimizeTransform()
            return
        }

        let clampedY = max(0, translation.y)
        let projectedY = clampedY + max(velocity.y, 0) * MobilePlayerGestureTuning.dismissVelocityProjectionDuration
        let translationThreshold = max(
            MobilePlayerGestureTuning.cardMinimizeMinimumTranslation,
            view.bounds.height * MobilePlayerGestureTuning.cardMinimizeTranslationHeightRatio
        )
        let shouldMinimize = projectedY > translationThreshold
            || (velocity.y > MobilePlayerGestureTuning.cardMinimizeFastSwipeVelocity
                && clampedY > MobilePlayerGestureTuning.cardMinimizeMinimumFastSwipeTranslation)

        guard shouldMinimize else {
            resetCardMinimizeTransform()
            return
        }

        completeCardMinimizeTransition()
    }

    private func completeCardMinimizeTransition() {
        guard let context = activeCardMinimizeContext,
              let targetFrame = context.targetFrame else {
            chrome.requestPageLayout(.fourPerPage) { [weak self] in
                self?.cleanupCardMinimizeTransition(revealPlayer: true)
            }
            return
        }

        let foregroundView = context.foregroundView

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            foregroundView.transform = .identity
            foregroundView.bounds = CGRect(origin: .zero, size: targetFrame.size)
            foregroundView.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            context.underlayView.setOtherCardsRevealProgress(1)
        }, completion: { [weak self] _ in
            guard let self else { return }

            self.chrome.requestPageLayout(.fourPerPage) { [weak self] in
                guard let self else { return }
                self.cleanupCardMinimizeTransition(revealPlayer: true)
            }
        })
    }

    private func completeCardExpandTransition() {
        guard let context = activeCardExpandContext else { return }
        let contextID = context.id

        let pageLayoutRequestID = chrome.requestPageLayout(
            .onePerPage,
            targetPagePosition: context.targetPagePosition
        ) { [weak self] in
            guard let self,
                  self.activeCardExpandContext?.id == contextID else {
                return
            }

            self.isCardExpandContentReady = true
            self.finishCardExpandTransitionIfReady()
        }

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.applyCardExpandPresentation(progress: 1)
        }, completion: { [weak self] _ in
            guard let self,
                  self.activeCardExpandContext?.id == contextID else {
                return
            }

            self.isCardExpandAnimationComplete = true
            self.finishCardExpandTransitionIfReady()
            self.scheduleCardExpandContentReadyFallbackIfNeeded(
                for: contextID,
                pageLayoutRequestID: pageLayoutRequestID
            )
        })
    }

    private func finishCardExpandTransitionIfReady() {
        guard activeCardExpandContext != nil,
              isCardExpandAnimationComplete,
              isCardExpandContentReady else {
            return
        }

        cleanupCardExpandTransition(revealPlayer: true)
    }

    private func scheduleCardExpandContentReadyFallbackIfNeeded(
        for contextID: UUID,
        pageLayoutRequestID: UUID
    ) {
        guard activeCardExpandContext?.id == contextID,
              isCardExpandAnimationComplete,
              !isCardExpandContentReady else {
            return
        }

        cancelCardExpandContentReadyFallback()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeCardExpandContext?.id == contextID,
                  self.isCardExpandAnimationComplete,
                  !self.isCardExpandContentReady else {
                return
            }

            self.chrome.cancelPageLayoutRequestCompletion(pageLayoutRequestID)
            self.cleanupCardExpandTransition(revealPlayer: true)
        }
        cardExpandContentReadyFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.cardExpandContentReadyFallbackDelay,
            execute: workItem
        )
    }

    private func cancelCardExpandContentReadyFallback() {
        cardExpandContentReadyFallbackWorkItem?.cancel()
        cardExpandContentReadyFallbackWorkItem = nil
    }

    private func applyPlayerDismissPinchPresentation(_ gesture: CardLayoutPinchGestureRecognizer) {
        let location = gesture.pinchLocation(in: view)
        let translation = CGPoint(
            x: location.x - playerDismissPinchStartLocation.x,
            y: location.y - playerDismissPinchStartLocation.y
        )
        applyPlayerDismissPinchPresentation(
            progress: playerDismissPinchProgress(forScale: gesture.scale),
            translation: translation,
            pinchScale: gesture.scale
        )
    }

    private func schedulePlayerDismissPinchPresentationUpdate() {
        playerDismissPinchPresentationUpdate.schedule()
    }

    private func flushPendingPlayerDismissPinchPresentationUpdate() {
        playerDismissPinchPresentationUpdate.flush()
    }

    private func invalidatePendingPlayerDismissPinchPresentationUpdate() {
        playerDismissPinchPresentationUpdate.invalidate()
    }

    private func applyPlayerDismissPinchPresentation(
        progress: CGFloat,
        translation: CGPoint,
        pinchScale: CGFloat
    ) {
        let progress = min(max(progress, 0), 1)
        let easedProgress = easeOutQuadratic(progress)
        let dragOffset = cardTransitionDragOffset(
            translation: translation,
            easedProgress: easedProgress
        )
        let scale = playerDismissPinchPresentationScale(
            easedProgress: easedProgress,
            pinchScale: pinchScale
        )

        playerNavigationController.view.transform = CGAffineTransform(
            translationX: dragOffset.x,
            y: dragOffset.y
        ).scaledBy(x: scale, y: scale)
        dimmingView.alpha = playerDismissPinchInteractiveDimmingAlpha(progress: progress)
    }

    private func applyFinalPlayerDismissPinchPresentation() {
        let scale = playerDismissPinchPresentationScale(
            easedProgress: 1,
            pinchScale: MobilePlayerGestureTuning.playerDismissPinchFullProgressScale
        )

        playerNavigationController.view.transform = CGAffineTransform(
            translationX: 0,
            y: view.bounds.height
        ).scaledBy(x: scale, y: scale)
        dimmingView.alpha = 0
    }

    private func playerDismissPinchInteractiveDimmingAlpha(progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        let fade = easeOutQuadratic(clampedProgress)
            * MobilePlayerGestureTuning.playerDismissPinchInteractiveMaximumDimmingFade
        return 1 - fade
    }

    private func playerDismissPinchPresentationScale(
        easedProgress: CGFloat,
        pinchScale: CGFloat
    ) -> CGFloat {
        let fullProgressScale = MobilePlayerGestureTuning.playerDismissPinchFullProgressScale
        let normalScale = 1 - (1 - fullProgressScale) * easedProgress
        guard pinchScale < fullProgressScale,
              fullProgressScale > 0 else {
            return normalScale
        }

        let minimumScaleRatio = MobilePlayerGestureTuning.playerDismissPinchMinimumPresentationScaleRatio
        let scaleRatio = max(pinchScale / fullProgressScale, minimumScaleRatio)
        return fullProgressScale * scaleRatio
    }

    private func playerDismissPinchProgress(forScale scale: CGFloat) -> CGFloat {
        let activationScale = MobilePlayerGestureTuning.playerDismissPinchActivationScale
        let fullProgressScale = MobilePlayerGestureTuning.playerDismissPinchFullProgressScale
        let progressDistance = activationScale - fullProgressScale
        guard progressDistance > 0 else { return 0 }

        return min(max((activationScale - scale) / progressDistance, 0), 1)
    }

    private func resetPlayerDismissPinchState() {
        isPlayerDismissPinchDrivingPlayerDismiss = false
        playerDismissPinchStartLocation = .zero
        invalidatePendingPlayerDismissPinchPresentationUpdate()
    }

    private func applyCardExpandPinchPresentation(_ gesture: CardLayoutPinchGestureRecognizer) {
        let location = gesture.pinchLocation(in: view)
        let translation = CGPoint(
            x: location.x - cardExpandPinchStartLocation.x,
            y: location.y - cardExpandPinchStartLocation.y
        )
        applyCardExpandInteractivePresentation(
            progress: cardExpandPinchProgress(forScale: gesture.scale),
            translation: translation,
            pinchScale: gesture.scale
        )
    }

    private func scheduleCardExpandPinchPresentationUpdate() {
        cardExpandPinchPresentationUpdate.schedule()
    }

    private func flushPendingCardExpandPinchPresentationUpdate() {
        cardExpandPinchPresentationUpdate.flush()
    }

    private func invalidatePendingCardExpandPinchPresentationUpdate() {
        cardExpandPinchPresentationUpdate.invalidate()
    }

    private func applyCardExpandPresentation(progress: CGFloat) {
        guard let context = activeCardExpandContext else { return }

        let progress = min(max(progress, 0), 1)
        let easedProgress = easeOutQuadratic(progress)
        let foregroundFrame = interpolatedRect(
            from: context.sourceFrame,
            to: context.targetFrame,
            progress: easedProgress
        )

        context.foregroundView.transform = .identity
        context.foregroundView.bounds = CGRect(origin: .zero, size: foregroundFrame.size)
        context.foregroundView.center = CGPoint(x: foregroundFrame.midX, y: foregroundFrame.midY)
        context.underlayView.setOtherCardsRevealProgress(1 - easedProgress)
    }

    private func applyCardExpandInteractivePresentation(
        progress: CGFloat,
        translation: CGPoint,
        pinchScale: CGFloat
    ) {
        guard let context = activeCardExpandContext else { return }

        let progress = min(max(progress, 0), 1)
        let easedProgress = easeOutQuadratic(progress)
        let dragOffset = cardTransitionDragOffset(
            translation: translation,
            easedProgress: easedProgress
        )
        let scale = cardExpandPresentationScale(
            forPinchScale: pinchScale,
            targetScale: context.targetScale
        )
        let displayedSize = CGSize(
            width: context.sourceFrame.width * scale,
            height: context.sourceFrame.height * scale
        )
        let unclampedCenter = CGPoint(
            x: context.sourceFrame.midX + dragOffset.x,
            y: context.sourceFrame.midY + dragOffset.y
        )
        let targetPullProgress = cardExpandTargetPullProgress(
            scale: scale,
            targetScale: context.targetScale
        )
        let targetPulledCenter = interpolatedPoint(
            from: unclampedCenter,
            to: rubberBandedCardExpandCenter(
                unclampedCenter,
                displayedSize: displayedSize,
                inside: context.targetFrame
            ),
            progress: targetPullProgress
        )
        let playerBounds = playerNavigationController.view.convert(playerNavigationController.view.bounds, to: view)
        let rubberBandedCenter = rubberBandedCardExpandCenter(
            targetPulledCenter,
            displayedSize: displayedSize,
            inside: playerBounds
        )

        context.foregroundView.bounds = CGRect(origin: .zero, size: context.sourceFrame.size)
        context.foregroundView.center = rubberBandedCenter
        context.foregroundView.transform = CGAffineTransform(scaleX: scale, y: scale)
        context.underlayView.setOtherCardsRevealProgress(1 - easedProgress)
    }

    private func finishCardExpandPinchGesture(scale: CGFloat, velocity: CGFloat) {
        guard let context = activeCardExpandContext else {
            resetCardExpandTransform()
            return
        }

        let targetScale = max(context.targetScale, 1)
        let commitScale = targetScale * MobilePlayerGestureTuning.cardExpandPinchCommitScaleMultiplier
        let velocityCommitMinimumScale = targetScale * MobilePlayerGestureTuning.cardExpandPinchVelocityCommitMinimumScaleMultiplier
        let projectedScale = scale + max(velocity, 0) * MobilePlayerGestureTuning.cardExpandPinchVelocityProjectionDuration
        let canVelocityCommit = scale >= velocityCommitMinimumScale
        let shouldExpand = scale >= commitScale
            || (canVelocityCommit
                && (projectedScale >= commitScale
                    || velocity > MobilePlayerGestureTuning.cardExpandPinchFastVelocity))

        guard shouldExpand else {
            resetCardExpandTransform()
            return
        }

        completeCardExpandTransition()
    }

    private func cardExpandPinchProgress(forScale scale: CGFloat) -> CGFloat {
        let activationScale = MobilePlayerGestureTuning.cardExpandPinchActivationScale
        let fullProgressScale = activeCardExpandContext.map(cardExpandPinchFullProgressScale)
            ?? MobilePlayerGestureTuning.cardExpandPinchFullProgressScale
        let progressDistance = fullProgressScale - activationScale
        guard progressDistance > 0 else { return 0 }

        return min(max((scale - activationScale) / progressDistance, 0), 1)
    }

    private func cardExpandPinchFullProgressScale(context: CardExpandTransitionContext) -> CGFloat {
        max(MobilePlayerGestureTuning.cardExpandPinchFullProgressScale, context.targetScale)
    }

    private func resetCardExpandPinchState() {
        isCardExpandPinchDrivingCardExpand = false
        cardExpandPinchStartLocation = .zero
        invalidatePendingCardExpandPinchPresentationUpdate()
    }

    private func applyCardMinimizePresentation(translation: CGPoint) {
        let offsetY = max(0, translation.y)
        let progress = min(offsetY / MobilePlayerGestureTuning.cardMinimizeProgressDistance, 1)
        applyCardMinimizePresentation(
            progress: progress,
            translation: CGPoint(x: translation.x, y: offsetY)
        )
    }

    private func applyCardMinimizePinchPresentation(_ gesture: CardLayoutPinchGestureRecognizer) {
        let location = gesture.pinchLocation(in: view)
        let translation = CGPoint(
            x: location.x - cardMinimizePinchStartLocation.x,
            y: location.y - cardMinimizePinchStartLocation.y
        )
        applyCardMinimizePresentation(
            progress: cardMinimizePinchProgress(forScale: gesture.scale),
            translation: translation,
            rotation: cardMinimizePinchRotation,
            pinchScale: gesture.scale
        )
    }

    private func scheduleCardMinimizePinchPresentationUpdate() {
        cardMinimizePinchPresentationUpdate.schedule()
    }

    private func flushPendingCardMinimizePinchPresentationUpdate() {
        cardMinimizePinchPresentationUpdate.flush()
    }

    private func invalidatePendingCardMinimizePinchPresentationUpdate() {
        cardMinimizePinchPresentationUpdate.invalidate()
    }

    private func applyCardMinimizePresentation(
        progress: CGFloat,
        translation: CGPoint,
        rotation: CGFloat = 0,
        pinchScale: CGFloat? = nil
    ) {
        guard let context = activeCardMinimizeContext else { return }

        let progress = min(max(progress, 0), 1)
        let easedProgress = easeOutQuadratic(progress)
        let scale = cardMinimizeForegroundScale(
            targetScale: context.targetScale,
            easedProgress: easedProgress,
            pinchScale: pinchScale
        )
        let dragOffset = cardTransitionDragOffset(
            translation: translation,
            easedProgress: easedProgress
        )
        let underlayFadeProgress = min(
            progress / MobilePlayerGestureTuning.cardMinimizeInteractiveOtherCardsRevealCompletionProgress,
            1
        )

        context.foregroundView.center = CGPoint(
            x: context.sourceFrame.midX + dragOffset.x,
            y: context.sourceFrame.midY + dragOffset.y
        )
        context.foregroundView.transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
        let otherCardsRevealProgress = easeOutQuadratic(underlayFadeProgress)
            * MobilePlayerGestureTuning.cardMinimizeInteractiveOtherCardsMaximumRevealProgress
        context.underlayView.setOtherCardsRevealProgress(otherCardsRevealProgress)
    }

    private func cardMinimizeForegroundScale(
        targetScale: CGFloat,
        easedProgress: CGFloat,
        pinchScale: CGFloat?
    ) -> CGFloat {
        let normalScale = 1 - (1 - targetScale) * easedProgress
        guard let pinchScale,
              pinchScale < MobilePlayerGestureTuning.cardMinimizePinchFullProgressScale,
              MobilePlayerGestureTuning.cardMinimizePinchFullProgressScale > 0 else {
            return normalScale
        }

        let minimumScaleRatio = MobilePlayerGestureTuning.cardMinimizePinchMinimumPresentationScaleRatio
        let scaleRatio = max(pinchScale / MobilePlayerGestureTuning.cardMinimizePinchFullProgressScale, minimumScaleRatio)
        return targetScale * scaleRatio
    }

    private func finishCardMinimizePinchGesture(
        scale: CGFloat,
        velocity: CGFloat
    ) {
        guard activeCardMinimizeContext != nil else {
            resetCardMinimizeTransform()
            return
        }

        let currentProgress = cardMinimizePinchProgress(forScale: scale)
        let projectedScale = scale + min(velocity, 0) * MobilePlayerGestureTuning.cardMinimizePinchVelocityProjectionDuration
        let projectedProgress = max(
            currentProgress,
            cardMinimizePinchProgress(forScale: projectedScale)
        )
        let hasEnoughProgressForVelocityCommit = currentProgress >= MobilePlayerGestureTuning.cardMinimizePinchMinimumVelocityCommitProgress
        let shouldMinimize = currentProgress >= MobilePlayerGestureTuning.cardMinimizePinchCompletionProgress
            || (hasEnoughProgressForVelocityCommit
                && (projectedProgress >= MobilePlayerGestureTuning.cardMinimizePinchCompletionProgress
                    || velocity < -MobilePlayerGestureTuning.cardMinimizePinchFastVelocity))

        guard shouldMinimize else {
            resetCardMinimizeTransform()
            return
        }

        completeCardMinimizeTransition()
    }

    private func cardMinimizePinchProgress(forScale scale: CGFloat) -> CGFloat {
        let activationScale = MobilePlayerGestureTuning.cardMinimizePinchActivationScale
        let fullProgressScale = MobilePlayerGestureTuning.cardMinimizePinchFullProgressScale
        let progressDistance = activationScale - fullProgressScale
        guard progressDistance > 0 else { return 0 }

        return min(max((activationScale - scale) / progressDistance, 0), 1)
    }

    private func resetCardMinimizePinchState() {
        isCardMinimizePinchDrivingCardMinimize = false
        cardMinimizePinchStartLocation = .zero
        cardMinimizePinchStartRotation = 0
        cardMinimizePinchRotation = 0
        invalidatePendingCardMinimizePinchPresentationUpdate()
    }

    private func resetCardMinimizeTransform() {
        guard let context = activeCardMinimizeContext else {
            revealPlayerAfterCardTransition()
            return
        }

        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            context.foregroundView.transform = .identity
            context.foregroundView.bounds = CGRect(origin: .zero, size: context.sourceFrame.size)
            context.foregroundView.center = CGPoint(x: context.sourceFrame.midX, y: context.sourceFrame.midY)
            context.underlayView.setOtherCardsRevealProgress(0)
        }, completion: { [weak self] _ in
            self?.cleanupCardMinimizeTransition(revealPlayer: true)
        })
    }

    private func resetCardExpandTransform() {
        guard activeCardExpandContext != nil else {
            revealPlayerAfterCardTransition()
            return
        }

        UIView.animate(withDuration: 0.26, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            self.applyCardExpandPresentation(progress: 0)
        }, completion: { [weak self] _ in
            self?.cleanupCardExpandTransition(revealPlayer: true)
        })
    }

    private func makeCardMinimizeTransitionContext(
        state: MobilePlayerLayoutInteractionState
    ) -> CardMinimizeTransitionContext? {
        guard state.canMinimizeCardNftToFourPerPage,
              let selectedSlot = state.fourPerPageSelectedSlot,
              state.fourPerPageDescriptors.indices.contains(selectedSlot),
              let currentDescriptor = state.currentDescriptor else {
            return nil
        }

        let fallbackImageSize = cardTransitionFallbackImageSize(
            selectedDescriptor: currentDescriptor,
            descriptors: state.fourPerPageDescriptors
        )
        let sourceFrame = onePerPageCardFrame(for: fallbackImageSize)
        guard !sourceFrame.isEmpty else {
            return nil
        }
        let foregroundView = makeCardTransitionForegroundView(
            sourceFrame: sourceFrame,
            descriptor: currentDescriptor
        )

        let underlayView = makeCardTransitionUnderlayView(
            descriptors: state.fourPerPageDescriptors,
            hiddenSlotIndex: selectedSlot,
            fallbackImageSize: fallbackImageSize,
            otherCardsRevealProgress: 0
        )
        view.insertSubview(foregroundView, aboveSubview: underlayView)
        let targetFrame = gridSlotFrame(in: underlayView)
        let targetScale = cardMinimizeTargetScale(sourceFrame: sourceFrame, targetFrame: targetFrame)

        return CardMinimizeTransitionContext(
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            targetScale: targetScale,
            foregroundView: foregroundView,
            underlayView: underlayView
        )
    }

    private func makeCardExpandTransitionContext(
        selection: MobilePlayerCardNftGridSelection
    ) -> CardExpandTransitionContext? {
        let selectedImageSize = selection.selectedImageSize.validOrDefault
        let underlayView = makeCardTransitionUnderlayView(
            descriptors: selection.fourPerPageDescriptors,
            hiddenSlotIndex: selection.selectedSlotIndex,
            fallbackImageSize: selectedImageSize,
            layoutImageSizes: selection.fourPerPageImageSizes,
            initialImages: selection.fourPerPageImages,
            otherCardsRevealProgress: 1
        )

        guard let sourceFrame = gridSlotFrame(in: underlayView),
              !sourceFrame.isEmpty else {
            underlayView.removeFromSuperview()
            return nil
        }

        let targetFrame = onePerPageCardFrame(for: selectedImageSize)
        guard !targetFrame.isEmpty else {
            underlayView.removeFromSuperview()
            return nil
        }

        let foregroundView = makeCardTransitionForegroundView(
            sourceFrame: sourceFrame,
            descriptor: selection.selectedDescriptor,
            image: selection.selectedImage
        )
        view.insertSubview(foregroundView, aboveSubview: underlayView)

        return CardExpandTransitionContext(
            id: UUID(),
            targetPagePosition: selection.pagePosition,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            targetScale: cardExpandTargetScale(sourceFrame: sourceFrame, targetFrame: targetFrame),
            foregroundView: foregroundView,
            underlayView: underlayView
        )
    }

    private func makeCardTransitionUnderlayView(
        descriptors: [DownloadableMediaDescriptor],
        hiddenSlotIndex: Int,
        fallbackImageSize: CGSize,
        layoutImageSizes: [CGSize]? = nil,
        initialImages: [UIImage]? = nil,
        otherCardsRevealProgress: CGFloat
    ) -> CardTransitionUnderlayView {
        let underlayView = CardTransitionUnderlayView(
            descriptors: descriptors,
            hiddenSlotIndex: hiddenSlotIndex,
            fallbackImageSize: fallbackImageSize,
            layoutImageSizes: layoutImageSizes,
            initialImages: initialImages
        )
        underlayView.frame = playerNavigationController.view.frame
        underlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(underlayView, belowSubview: playerNavigationController.view)
        underlayView.setOtherCardsRevealProgress(otherCardsRevealProgress)
        underlayView.setNeedsLayout()
        underlayView.layoutIfNeeded()
        return underlayView
    }

    private func makeCardTransitionForegroundView(
        sourceFrame: CGRect,
        descriptor: DownloadableMediaDescriptor,
        image: UIImage? = nil
    ) -> UIView {
        if let image = image ?? DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            let imageView = UIImageView(frame: sourceFrame)
            imageView.makeBackgroundTransparent()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.image = image
            return imageView
        }

        let sourceFrameInPlayer = view.convert(sourceFrame, to: playerNavigationController.view)
        if let snapshot = playerNavigationController.view.resizableSnapshotView(
            from: sourceFrameInPlayer,
            afterScreenUpdates: false,
            withCapInsets: .zero
        ) {
            snapshot.frame = sourceFrame
            snapshot.clipsToBounds = true
            return snapshot
        }

        let placeholderView = UIView(frame: sourceFrame)
        placeholderView.backgroundColor = MobilePlayerBackgroundColor.defaultColor
        placeholderView.clipsToBounds = true
        return placeholderView
    }

    private func cardTransitionFallbackImageSize(
        selectedDescriptor: DownloadableMediaDescriptor,
        descriptors: [DownloadableMediaDescriptor]
    ) -> CGSize {
        if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: selectedDescriptor) {
            return image.size.validOrDefault
        }

        for descriptor in descriptors {
            if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
                return image.size.validOrDefault
            }
        }

        return CGSize(width: 1, height: 1)
    }

    private func onePerPageCardFrame(for imageSize: CGSize) -> CGRect {
        let playerBounds = playerNavigationController.view.bounds
        let frameInPlayer = MobileStaticImageSpreadLayout.centeredAspectFitRect(
            for: imageSize.validOrDefault,
            in: playerBounds
        )
        let clippedFrame = frameInPlayer.intersection(playerBounds)
        guard !clippedFrame.isNull, !clippedFrame.isEmpty else {
            return playerNavigationController.view.convert(playerBounds, to: view)
        }
        return playerNavigationController.view.convert(clippedFrame, to: view)
    }

    private func gridSlotFrame(in underlayView: CardTransitionUnderlayView) -> CGRect? {
        guard let targetFrame = underlayView.hiddenSlotFrame else { return nil }
        return underlayView.convert(targetFrame, to: view)
    }

    private func cardMinimizeTargetScale(sourceFrame: CGRect, targetFrame: CGRect?) -> CGFloat {
        cardTransitionTargetScale(sourceFrame: sourceFrame, targetFrame: targetFrame, fallback: 0.5)
    }

    private func cardExpandTargetScale(sourceFrame: CGRect, targetFrame: CGRect) -> CGFloat {
        cardTransitionTargetScale(
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            fallback: MobilePlayerGestureTuning.cardExpandPinchFullProgressScale
        )
    }

    private func cardTransitionTargetScale(
        sourceFrame: CGRect,
        targetFrame: CGRect?,
        fallback: CGFloat
    ) -> CGFloat {
        guard let targetFrame,
              sourceFrame.width > 0,
              sourceFrame.height > 0 else {
            return fallback
        }

        return min(targetFrame.width / sourceFrame.width, targetFrame.height / sourceFrame.height)
    }

    private func cardExpandPinchSelection(
        for gesture: CardLayoutPinchGestureRecognizer
    ) -> MobilePlayerCardNftGridSelection? {
        let location = gesture.initialPinchLocation(in: playerNavigationController.view)
        guard canUseCardExpandPinchSelection(at: location) else {
            return nil
        }

        return chrome.cardNftGridSelection(at: location, in: playerNavigationController.view)
    }

    private func cardTransitionDragOffset(
        translation: CGPoint,
        easedProgress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: translation.x * (1 - Self.cardTransitionHorizontalDragDamping * easedProgress),
            y: translation.y * (1 - Self.cardTransitionVerticalDragDamping * easedProgress)
        )
    }

    private func rubberBandedCardExpandCenter(
        _ center: CGPoint,
        displayedSize: CGSize,
        inside containingRect: CGRect
    ) -> CGPoint {
        guard !containingRect.isNull,
              containingRect.width > 0,
              containingRect.height > 0 else {
            return center
        }

        return CGPoint(
            x: rubberBandedCardExpandCenterAxis(
                center.x,
                contentLength: displayedSize.width,
                minBound: containingRect.minX,
                maxBound: containingRect.maxX
            ),
            y: rubberBandedCardExpandCenterAxis(
                center.y,
                contentLength: displayedSize.height,
                minBound: containingRect.minY,
                maxBound: containingRect.maxY
            )
        )
    }

    private func rubberBandedCardExpandCenterAxis(
        _ value: CGFloat,
        contentLength: CGFloat,
        minBound: CGFloat,
        maxBound: CGFloat
    ) -> CGFloat {
        let boundsLength = max(maxBound - minBound, 1)
        let halfExtent = contentLength / 2
        let allowedRange: ClosedRange<CGFloat>
        if contentLength <= boundsLength {
            allowedRange = (minBound + halfExtent)...(maxBound - halfExtent)
        } else {
            allowedRange = (maxBound - halfExtent)...(minBound + halfExtent)
        }

        if value < allowedRange.lowerBound {
            return allowedRange.lowerBound - rubberBandedCardExpandOvershoot(
                allowedRange.lowerBound - value,
                dimension: boundsLength
            )
        }
        if value > allowedRange.upperBound {
            return allowedRange.upperBound + rubberBandedCardExpandOvershoot(
                value - allowedRange.upperBound,
                dimension: boundsLength
            )
        }

        return value
    }

    private func rubberBandedCardExpandOvershoot(_ overshoot: CGFloat, dimension: CGFloat) -> CGFloat {
        rubberBandOvershoot(
            overshoot,
            dimension: dimension,
            resistance: MobilePlayerGestureTuning.cardExpandPinchCenterRubberBandResistance
        )
    }

    private func cardExpandTargetPullProgress(scale: CGFloat, targetScale: CGFloat) -> CGFloat {
        let activationScale = MobilePlayerGestureTuning.cardExpandPinchActivationScale
        let rampDistance = MobilePlayerGestureTuning.cardExpandPinchTargetPullRampScaleDistance
        let rampProgress = min(max((scale - activationScale) / rampDistance, 0), 1)
        let targetScale = max(targetScale, activationScale + 0.01)
        let scaleProgress = min(max((scale - activationScale) / (targetScale - activationScale), 0), 1)
        let earlyScalePull = pow(1 - scaleProgress, 2)
        let minimumPullProgress = MobilePlayerGestureTuning.cardExpandPinchMinimumTargetPullProgress
        let maximumPullProgress = MobilePlayerGestureTuning.cardExpandPinchMaximumTargetPullProgress
        let pullProgress = minimumPullProgress
            + (maximumPullProgress - minimumPullProgress) * earlyScalePull

        return rampProgress * pullProgress
    }

    private func cardExpandPresentationScale(forPinchScale pinchScale: CGFloat, targetScale: CGFloat) -> CGFloat {
        let scale = max(pinchScale, 1)
        let targetScale = max(targetScale, 1)
        guard scale > targetScale else { return scale }

        let overscale = scale - targetScale
        let rubberBandedOverscale = rubberBandOvershoot(
            overscale,
            dimension: targetScale,
            resistance: MobilePlayerGestureTuning.cardExpandPinchOverscaleResistance
        )
        return targetScale + rubberBandedOverscale
    }

    private func rubberBandOvershoot(
        _ overshoot: CGFloat,
        dimension: CGFloat,
        resistance: CGFloat
    ) -> CGFloat {
        let dimension = max(dimension, 1)
        let scaledOvershoot = abs(overshoot) * resistance / dimension
        return dimension * (1 - 1 / (scaledOvershoot + 1))
    }

    private func interpolatedPoint(from sourcePoint: CGPoint, to targetPoint: CGPoint, progress: CGFloat) -> CGPoint {
        let progress = min(max(progress, 0), 1)
        return CGPoint(
            x: sourcePoint.x + (targetPoint.x - sourcePoint.x) * progress,
            y: sourcePoint.y + (targetPoint.y - sourcePoint.y) * progress
        )
    }

    private func interpolatedRect(from sourceFrame: CGRect, to targetFrame: CGRect, progress: CGFloat) -> CGRect {
        let progress = min(max(progress, 0), 1)
        return CGRect(
            x: sourceFrame.minX + (targetFrame.minX - sourceFrame.minX) * progress,
            y: sourceFrame.minY + (targetFrame.minY - sourceFrame.minY) * progress,
            width: sourceFrame.width + (targetFrame.width - sourceFrame.width) * progress,
            height: sourceFrame.height + (targetFrame.height - sourceFrame.height) * progress
        )
    }

    private func cleanupCardMinimizeTransition(revealPlayer: Bool) {
        let context = activeCardMinimizeContext
        activeCardMinimizeContext = nil
        isDismissPanDrivingCardMinimize = false
        resetCardMinimizePinchState()

        if revealPlayer {
            revealPlayerAfterCardTransition()
        }

        context?.foregroundView.removeFromSuperview()
        context?.underlayView.removeFromSuperview()
    }

    private func cleanupCardExpandTransition(revealPlayer: Bool) {
        let context = activeCardExpandContext
        activeCardExpandContext = nil
        isCardExpandAnimationComplete = false
        isCardExpandContentReady = false
        resetCardExpandPinchState()
        cancelCardExpandContentReadyFallback()

        if revealPlayer {
            revealPlayerAfterCardTransition()
        }

        context?.foregroundView.removeFromSuperview()
        context?.underlayView.removeFromSuperview()
    }

    private func revealPlayerAfterCardTransition() {
        chrome.setPlayerContentHiddenForCardTransition(false)
        playerNavigationController.view.alpha = 1
        playerNavigationController.view.transform = .identity
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
            guard !self.isPlayerDismissGestureActive,
                  !self.isDismissing else { return }
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
        guard remainingPasses > 0, isPlayerDismissGestureActive || isDismissing else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissBackgroundClearPassDelay) { [weak self] in
            guard let self else { return }
            guard self.isPlayerDismissGestureActive || self.isDismissing else { return }

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

    private var isPlayerDismissGestureActive: Bool {
        isDismissPanDrivingPlayerDismiss || isPlayerDismissPinchDrivingPlayerDismiss
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
        if gestureRecognizer === navigationBarTap {
            guard !isDismissing, !isCardTransitionActive else {
                return false
            }

            return chrome.showControls
        }

        if gestureRecognizer === controlsPan {
            guard !isCardTransitionActive else {
                return false
            }

            let location = controlsPan.location(in: playerNavigationController.view)
            guard !hasZoomedPlayerContent(at: location) else {
                return false
            }

            let velocity = controlsPan.velocity(in: view)
            return hasControlsRevealIntent(location: location, velocity: velocity)
        }

        if gestureRecognizer === cardMinimizePinch {
            return canBeginCardMinimizePinch()
        }

        if gestureRecognizer === playerDismissPinch {
            return canBeginPlayerDismissPinch()
        }

        if gestureRecognizer === cardExpandPinch {
            return canBeginCardExpandPinch()
        }

        if gestureRecognizer === cardMinimizeRotation {
            return canBeginCardMinimizeRotation()
        }

        guard gestureRecognizer === dismissPan else {
            return true
        }
        guard !isDismissing else {
            return false
        }
        guard !isCardTransitionActive else {
            return false
        }

        let location = dismissPan.location(in: playerNavigationController.view)
        let velocity = dismissPan.velocity(in: view)

        guard !hasZoomedPlayerContent(at: location) else {
            return false
        }

        return cardMinimizeStateForIntent(location: location, velocity: velocity) != nil
            || hasPlayerDismissIntent(location: location, velocity: velocity)
            || (chrome.showControls && hasControlsHideIntent(location: location, velocity: velocity))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === navigationBarTap else {
            return true
        }

        return shouldReceiveNavigationBarTap(touch)
    }

    private func shouldReceiveNavigationBarTap(_ touch: UITouch) -> Bool {
        let navigationBar = playerNavigationController.navigationBar
        let location = touch.location(in: navigationBar)
        guard navigationBar.bounds.contains(location) else {
            return false
        }

        return !isTouchInsideSideNavigationBarItem(touch, in: navigationBar)
    }

    private func isTouchInsideSideNavigationBarItem(
        _ touch: UITouch,
        in navigationBar: UINavigationBar
    ) -> Bool {
        var currentView = touch.view
        while let view = currentView, view !== navigationBar {
            if isSideNavigationBarItemView(view, in: navigationBar) {
                return true
            }

            currentView = view.superview
        }

        return false
    }

    private func isSideNavigationBarItemView(
        _ itemView: UIView,
        in navigationBar: UINavigationBar
    ) -> Bool {
        let itemFrame = itemView.convert(itemView.bounds, to: navigationBar)
        guard !itemFrame.isEmpty else {
            return false
        }

        let sideRegionWidth = min(
            Self.navigationBarSideControlRegionWidth,
            navigationBar.bounds.width / 3
        )

        let isInsideSideRegion = itemFrame.midX <= navigationBar.bounds.minX + sideRegionWidth
            || itemFrame.midX >= navigationBar.bounds.maxX - sideRegionWidth
        guard isInsideSideRegion else {
            return false
        }

        return itemView is UIControl || itemFrame.width <= Self.navigationBarSideControlRegionWidth
    }

    private func canBeginCardMinimizePinch() -> Bool {
        canBeginCardMinimizeInteraction(location: cardMinimizePinch.pinchLocation(in: playerNavigationController.view))
    }

    private func canBeginPlayerDismissPinch() -> Bool {
        canBeginPlayerDismissPinch(location: playerDismissPinch.pinchLocation(in: playerNavigationController.view))
    }

    private func canBeginPlayerDismissPinch(location: CGPoint) -> Bool {
        guard !isDismissing,
              !isCardTransitionActive,
              !chrome.isPlayerContentZoomed,
              playerNavigationController.view.bounds.contains(location) else {
            return false
        }

        return cardMinimizeStateForPinch(location: location) == nil
    }

    private func canBeginCardMinimizeRotation() -> Bool {
        if isCardMinimizePinchDrivingCardMinimize {
            return true
        }
        guard cardMinimizePinch.isTrackingPinch else {
            return false
        }

        return canBeginCardMinimizeInteraction(location: cardMinimizeRotation.location(in: playerNavigationController.view))
    }

    private func canBeginCardMinimizeInteraction(location: CGPoint) -> Bool {
        guard !isDismissing,
              !isCardTransitionActive else {
            return false
        }

        return cardMinimizeStateForPinch(location: location) != nil
    }

    private func canBeginCardExpandPinch() -> Bool {
        canSelectCardExpandPinch(for: cardExpandPinch)
    }

    private func canSelectCardExpandPinch(for gesture: CardLayoutPinchGestureRecognizer) -> Bool {
        let location = gesture.initialPinchLocation(in: playerNavigationController.view)
        guard canUseCardExpandPinchSelection(at: location) else {
            return false
        }

        return chrome.canSelectCardNftGrid(at: location, in: playerNavigationController.view)
    }

    private func canUseCardExpandPinchSelection(at location: CGPoint) -> Bool {
        !isDismissing
            && !isCardTransitionActive
            && !chrome.isPlayerContentZoomed
            && playerNavigationController.view.bounds.contains(location)
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

    private func cardMinimizeStateForIntent(
        location: CGPoint,
        velocity: CGPoint
    ) -> MobilePlayerLayoutInteractionState? {
        guard let state = cardMinimizeAvailableState(),
              hasPlayerDismissIntent(location: location, velocity: velocity) else {
            return nil
        }

        return state
    }

    private func cardMinimizeStateForPinch(
        location: CGPoint
    ) -> MobilePlayerLayoutInteractionState? {
        guard let state = cardMinimizeAvailableState(),
              playerNavigationController.view.bounds.contains(location) else {
            return nil
        }

        return state
    }

    private func cardMinimizeAvailableState() -> MobilePlayerLayoutInteractionState? {
        let state = chrome.layoutInteractionState
        guard state.canMinimizeCardNftToFourPerPage,
              !chrome.isPlayerContentZoomed else {
            return nil
        }

        return state
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
        if isCardMinimizePinchAndRotationPair(gestureRecognizer, otherGestureRecognizer) {
            return true
        }

        if gestureRecognizer === cardMinimizeRotation {
            return isPlayerScrollViewPinchGesture(otherGestureRecognizer)
        }
        if otherGestureRecognizer === cardMinimizeRotation {
            return isPlayerScrollViewPinchGesture(gestureRecognizer)
        }

        if gestureRecognizer === navigationBarTap || otherGestureRecognizer === navigationBarTap {
            return false
        }

        return gestureRecognizer === controlsPan || otherGestureRecognizer === controlsPan
    }

    private func isCardMinimizePinchAndRotationPair(
        _ gestureRecognizer: UIGestureRecognizer,
        _ otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === cardMinimizePinch && otherGestureRecognizer === cardMinimizeRotation)
            || (gestureRecognizer === cardMinimizeRotation && otherGestureRecognizer === cardMinimizePinch)
    }

    private func currentCardMinimizeRotationGestureValue() -> CGFloat {
        switch cardMinimizeRotation.state {
        case .began, .changed:
            return cardMinimizeRotation.rotation
        default:
            return 0
        }
    }

    private func isPlayerScrollViewPinchGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        configuredScrollPinchGestures.contains(ObjectIdentifier(gestureRecognizer))
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
