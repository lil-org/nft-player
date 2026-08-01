import SwiftUI
import Combine
import UIKit
import UIKit.UIGestureRecognizerSubclass

private let playerCrossfadeAnimation = Animation.easeInOut(duration: 0.18)
private let initialCollectionItemFadeDuration: TimeInterval = 0.3
private let initialCollectionItemFadeAnimationKey = "initialGridItemFade"
private let maximumVisibleRecentContinueViewingCount = 10
private let continueViewingContentSizedCollectionNameMaxWidth: CGFloat = 250
private let continueViewingCoverThumbnailSize: CGFloat = 14
private let continueViewingCoverThumbnailCornerRadius: CGFloat = 3
private let continueViewingPillSpacing: CGFloat = 8
private let continueViewingPillScrollHorizontalInset: CGFloat = 16
private let mobileCollectionsGridScrollPositionKey = "mobileCollectionsGridScrollPosition"

private enum PlayerPresentationTransition {
    case animated
    case instant

    var animatesNavigationTransition: Bool {
        switch self {
        case .animated:
            return true
        case .instant:
            return false
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
    private let collectionItems: [MobileCollectionItem]
    @ObservedObject private var widgetLaunchPresentationState: WidgetLaunchPresentationState
    @Environment(\.displayScale) private var displayScale
    @State private var playerConfig: MobilePlayerConfig?
    @State private var playerPresentationTransition: PlayerPresentationTransition = .animated
    @State private var viewingProgressByCollectionId: [String: Int]
    @State private var viewedToEndCollectionIds: Set<String>
    @State private var recentContinueViewingProgresses: [MobileViewingProgress]
    @State private var continueViewingScrollResetID = 0
    @State private var isSearchActive = false
    @State private var collectionSearchQuery = ""
    
    init(
        collectionItems: [MobileCollectionItem] = MobileCollectionCatalog.allItems,
        widgetLaunchPresentationState: WidgetLaunchPresentationState = .shared
    ) {
        self.collectionItems = collectionItems
        _widgetLaunchPresentationState = ObservedObject(wrappedValue: widgetLaunchPresentationState)
        let progressSnapshot = MobileViewingProgressStore.progressSnapshot()
        _viewingProgressByCollectionId = State(initialValue: progressSnapshot.percentagesByCollectionId)
        _viewedToEndCollectionIds = State(initialValue: progressSnapshot.viewedToEndCollectionIds)
        _recentContinueViewingProgresses = State(
            initialValue: Self.visibleRecentContinueViewingProgresses(
                from: progressSnapshot,
                collectionItems: collectionItems
            )
        )
    }
    
    var body: some View {
        MobileCollectionsNavigationView(
            rootView: collectionsRootView,
            playerConfig: playerConfig,
            presentationTransition: playerPresentationTransition,
            onDismissPlayer: dismissPlayer
        )
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            refreshViewingProgressAndResetContinueViewingScrollOffset()
            schedulePlayerPrewarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshViewingProgressAndResetContinueViewingScrollOffset()
            schedulePlayerPrewarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)) { _ in
            guard playerConfig == nil else { return }
            refreshViewingProgress()
        }
        .onOpenURL(perform: openWidgetURL)
    }

    private var collectionsRootView: some View {
        ZStack {
            InfiniteCollectionsGridView(
                items: collectionItems,
                progressByCollectionId: viewingProgressByCollectionId,
                viewedToEndCollectionIds: viewedToEndCollectionIds,
                onSelect: didSelectCollectionItem
            )
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSearchActive {
                    ToolbarItem(placement: .principal) {
                        MobileCollectionsSearchBar(
                            query: $collectionSearchQuery,
                            isFocusSuspended: playerConfig != nil
                        )
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(Strings.cancel) { deactivateSearch() }
                    }
                } else {
                    ToolbarItem(placement: .principal) {}
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
                        Button { activateSearch() } label: {
                            Images.search
                        }
                    }
                }
            }

            if !widgetLaunchPresentationState.isSuppressingContinueViewing,
               !recentContinueViewingProgresses.isEmpty,
               !isSearchActive {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        ContinueViewingPillsScrollView(
                            progresses: Array(
                                recentContinueViewingProgresses.prefix(maximumVisibleRecentContinueViewingCount)
                            ),
                            availableWidth: geometry.size.width,
                            horizontalContentInset: continueViewingPillScrollHorizontalInset,
                            resetID: continueViewingScrollResetID,
                            coverAssetName: coverAssetName(for:),
                            onSelect: { progress in resumeViewing(progress) }
                        )
                        .padding(.bottom, MobileBottomChromeSpacing.continueViewingPadding(forSafeAreaBottom: geometry.safeAreaInsets.bottom))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea(edges: .bottom)
                }
                .transition(.opacity)
                .zIndex(0.5)
            }

            if isSearchActive {
                MobileCollectionsSearchResultsView(
                    query: collectionSearchQuery,
                    onSelect: didSelectSearchResult
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .persistentSystemOverlays(.hidden)
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

    private func activateSearch() {
        collectionSearchQuery = ""
        MobileCollectionCoverImageCache.shared.prefetch(
            assetNames: collectionItems.prefix(24).map(\.coverAssetName),
            targetSize: CGSize(width: searchResultCoverThumbnailSize, height: searchResultCoverThumbnailSize),
            displayScale: displayScale > 0 ? displayScale : UIScreen.main.scale
        )
        withAnimation(playerCrossfadeAnimation) {
            isSearchActive = true
        }
    }

    private func deactivateSearch() {
        withAnimation(playerCrossfadeAnimation) {
            isSearchActive = false
        }
    }

    private func didSelectSearchResult(_ item: MobileCollectionItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        openCollection(collectionId: item.id)
    }

    private func coverAssetName(for collectionId: String) -> String {
        collectionItems.first { $0.id == collectionId }?.coverAssetName ?? collectionId
    }

    private func openCollection(
        collectionId: String,
        presentationTransition: PlayerPresentationTransition = .animated
    ) {
        if let progress = MobileViewingProgressStore.progress(collectionId: collectionId) {
            resumeViewing(progress, presentationTransition: presentationTransition)
            return
        }

        openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            presentationTransition: presentationTransition
        )
    }
    
    private func resumeViewing(
        _ progress: MobileViewingProgress,
        presentationTransition: PlayerPresentationTransition = .animated
    ) {
        openPlayer(
            initialItemId: progress.collectionId,
            initialTokenId: progress.tokenId,
            initialTokenIndex: progress.tokenIndex,
            continueViewingCollectionId: progress.collectionId,
            presentationTransition: presentationTransition
        )
    }

    private func openWidgetURL(_ url: URL) {
        defer {
            widgetLaunchPresentationState.finishWidgetPlayerHandoff(for: url)
        }

        guard let deepLink = WidgetDeepLink(url: url),
              case let .collection(collectionId, tokenId) = deepLink,
              collectionItems.contains(where: { $0.id == collectionId }) else {
            return
        }

        if let tokenId {
            openWidgetToken(
                collectionId: collectionId,
                tokenId: tokenId
            )
        } else {
            openCollection(
                collectionId: collectionId,
                presentationTransition: .instant
            )
        }
    }

    private func openWidgetToken(
        collectionId: String,
        tokenId: String
    ) {
        guard let widgetTokenInsertion = MobileCollectionCatalog.widgetTokenInsertion(
            collectionId: collectionId,
            widgetTokenId: tokenId,
            progress: MobileViewingProgressStore.progress(collectionId: collectionId)
        ) else {
            openCollection(
                collectionId: collectionId,
                presentationTransition: .instant
            )
            return
        }

        if let anchorProgress = widgetTokenInsertion.automaticAnchorProgress() {
            MobileViewingProgressStore.save(anchorProgress)
        }
        openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            widgetTokenInsertion: widgetTokenInsertion,
            presentationTransition: .instant
        )
    }

    private func openPlayer(
        initialItemId: String,
        initialTokenId: String? = nil,
        initialTokenIndex: Int? = nil,
        continueViewingCollectionId: String,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil,
        presentationTransition: PlayerPresentationTransition = .animated
    ) {
        let config = MobilePlayerPrewarmer.preparedConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            initialTokenIndex: initialTokenIndex,
            continueViewingCollectionId: continueViewingCollectionId,
            widgetTokenInsertion: widgetTokenInsertion
        )

        let presentPlayer = {
            playerPresentationTransition = presentationTransition
            playerConfig = config
            MobileViewingProgressStore.setContinueViewingCollectionId(continueViewingCollectionId)
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
            refreshViewingProgressAndResetContinueViewingScrollOffset()
        }
    }

    private func refreshViewingProgress(resetScrollOnLeadingChange: Bool = true) {
        let previousLeadingCollectionId = recentContinueViewingProgresses.first?.collectionId
        let progressSnapshot = MobileViewingProgressStore.progressSnapshot()
        viewingProgressByCollectionId = progressSnapshot.percentagesByCollectionId
        viewedToEndCollectionIds = progressSnapshot.viewedToEndCollectionIds
        recentContinueViewingProgresses = Self.visibleRecentContinueViewingProgresses(
            from: progressSnapshot,
            collectionItems: collectionItems
        )

        guard resetScrollOnLeadingChange,
              playerConfig == nil,
              previousLeadingCollectionId != recentContinueViewingProgresses.first?.collectionId else {
            return
        }
        resetContinueViewingScrollOffset()
    }

    private func refreshViewingProgressAndResetContinueViewingScrollOffset() {
        refreshViewingProgress(resetScrollOnLeadingChange: false)
        resetContinueViewingScrollOffset()
    }

    private func resetContinueViewingScrollOffset() {
        continueViewingScrollResetID += 1
    }

    private func schedulePlayerPrewarm() {
        MobilePlayerPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: recentContinueViewingProgresses.first,
            initialCollectionIds: likelyInitialCollectionIds()
        )
    }

    private static func visibleRecentContinueViewingProgresses(
        from progressSnapshot: PlayerViewingProgressSnapshot,
        collectionItems: [MobileCollectionItem]
    ) -> [MobileViewingProgress] {
        let visibleCollectionIds = Set(collectionItems.map(\.id))
        return progressSnapshot.recentContinueViewingProgresses.filter { progress in
            visibleCollectionIds.contains(progress.collectionId)
                && MobileCollectionCatalog.canOpenCollection(specificCollectionId: progress.collectionId)
        }
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

private struct ContinueViewingPillsScrollView: View {
    let progresses: [MobileViewingProgress]
    let availableWidth: CGFloat
    let horizontalContentInset: CGFloat
    let resetID: Int
    let coverAssetName: (String) -> String
    let onSelect: (MobileViewingProgress) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: continueViewingPillSpacing) {
                ForEach(progresses, id: \.collectionId) { progress in
                    ContinueViewingButton(
                        progress: progress,
                        coverAssetName: coverAssetName(progress.collectionId)
                    ) {
                        onSelect(progress)
                    }
                }
            }
            .padding(.horizontal, horizontalContentInset)
            .frame(
                minWidth: availableWidth,
                alignment: progresses.count == 1 ? .center : .leading
            )
        }
        .frame(width: availableWidth)
        .id(resetID)
    }
}

private struct ContinueViewingButton: View {
    let progress: MobileViewingProgress
    let coverAssetName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CollectionCoverThumbnail(assetName: coverAssetName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.continueViewing)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    collectionName
                }

                Text(Strings.percent(progress.percent))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                CapsuleButtonBackground(isInteractive: true)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(Strings.continueViewing), \(progress.collectionName)"))
    }

    private var collectionName: some View {
        Text(progress.collectionName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: continueViewingContentSizedCollectionNameMaxWidth, alignment: .leading)
            .layoutPriority(1)
    }
}

private struct CollectionCoverThumbnail: View {
    let assetName: String
    var size: CGFloat = continueViewingCoverThumbnailSize
    var cornerRadius: CGFloat = continueViewingCoverThumbnailCornerRadius

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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
        if let loadedImage, loadedImage.loadKey == thumbnailLoadKey {
            return loadedImage.image
        }
        let scale = displayScale > 0 ? displayScale : UIScreen.main.scale
        return MobileCollectionCoverImageCache.shared.cachedImage(
            assetName: assetName,
            targetSize: targetSize,
            displayScale: scale
        )
    }

    private var targetSize: CGSize {
        CGSize(width: size, height: size)
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

private struct MobileCollectionsNavigationView<RootView: View>: UIViewControllerRepresentable {

    let rootView: RootView
    let playerConfig: MobilePlayerConfig?
    let presentationTransition: PlayerPresentationTransition
    let onDismissPlayer: (MobilePlayerConfig) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> PlayerNavigationController {
        let rootViewController = UIHostingController(rootView: rootView)
        rootViewController.navigationItem.backButtonDisplayMode = .minimal
        rootViewController.navigationItem.backButtonTitle = Strings.nftPlayer

        let navigationController = PlayerNavigationController(
            rootViewController: rootViewController
        )
        navigationController.navigationBar.isTranslucent = true
        navigationController.setNavigationBarHidden(false, animated: false)
        configureNavigationBarAppearance(navigationController.navigationBar)
        navigationController.delegate = context.coordinator

        context.coordinator.attach(
            navigationController: navigationController,
            rootViewController: rootViewController
        )
        context.coordinator.update(
            playerConfig: playerConfig,
            presentationTransition: presentationTransition,
            onDismissPlayer: onDismissPlayer
        )
        return navigationController
    }

    func updateUIViewController(
        _ navigationController: PlayerNavigationController,
        context: Context
    ) {
        context.coordinator.rootViewController?.rootView = rootView
        context.coordinator.update(
            playerConfig: playerConfig,
            presentationTransition: presentationTransition,
            onDismissPlayer: onDismissPlayer
        )
    }

    static func dismantleUIViewController(
        _ navigationController: PlayerNavigationController,
        coordinator: Coordinator
    ) {
        coordinator.invalidate()
    }

    private func configureNavigationBarAppearance(_ navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate {

        private final class PlayerSession {
            let config: MobilePlayerConfig
            let chrome: MobilePlayerChromeController
            let pagerViewController: MobilePlayerHostingController
            let browserViewController: MobilePlayerBrowserPageViewController?
            let modeController: MobilePlayerSessionModeController
            let interactionController: PlayerInteractionController
            let initialStack: [UIViewController]

            init(
                config: MobilePlayerConfig,
                chrome: MobilePlayerChromeController,
                pagerViewController: MobilePlayerHostingController,
                browserViewController: MobilePlayerBrowserPageViewController?,
                modeController: MobilePlayerSessionModeController,
                interactionController: PlayerInteractionController,
                initialStack: [UIViewController]
            ) {
                self.config = config
                self.chrome = chrome
                self.pagerViewController = pagerViewController
                self.browserViewController = browserViewController
                self.modeController = modeController
                self.interactionController = interactionController
                self.initialStack = initialStack
            }

            func owns(_ viewController: UIViewController?) -> Bool {
                guard let viewController else { return false }
                return viewController === pagerViewController
                    || viewController === browserViewController
            }

            func invalidate() {
                pagerViewController.finalizePlayerSession()
                interactionController.invalidate()
                modeController.invalidate()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }

        weak var rootViewController: UIHostingController<RootView>?
        private weak var navigationController: PlayerNavigationController?
        private var activeSession: PlayerSession?
        private var desiredPlayerConfig: MobilePlayerConfig?
        private var desiredPresentationTransition: PlayerPresentationTransition = .animated
        private var onDismissPlayer: ((MobilePlayerConfig) -> Void)?
        private var dismissedConfigIDAwaitingStateUpdate: UUID?
        private var isReconcileScheduled = false
        private var isAwaitingNavigationTransition = false

        func attach(
            navigationController: PlayerNavigationController,
            rootViewController: UIHostingController<RootView>
        ) {
            self.navigationController = navigationController
            self.rootViewController = rootViewController
        }

        func update(
            playerConfig: MobilePlayerConfig?,
            presentationTransition: PlayerPresentationTransition,
            onDismissPlayer: @escaping (MobilePlayerConfig) -> Void
        ) {
            desiredPlayerConfig = playerConfig
            desiredPresentationTransition = presentationTransition
            self.onDismissPlayer = onDismissPlayer
            if dismissedConfigIDAwaitingStateUpdate != playerConfig?.id {
                dismissedConfigIDAwaitingStateUpdate = nil
            }
            if playerConfig != nil,
               !presentationTransition.animatesNavigationTransition {
                reconcileNavigationState()
            } else {
                scheduleReconcile()
            }
        }

        func invalidate() {
            isReconcileScheduled = false
            isAwaitingNavigationTransition = false
            activeSession?.invalidate()
            activeSession = nil
            navigationController?.delegate = nil
            navigationController = nil
            rootViewController = nil
        }

        private func scheduleReconcile() {
            guard !isReconcileScheduled else { return }
            isReconcileScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReconcileScheduled = false
                self.reconcileNavigationState()
            }
        }

        private func reconcileNavigationState() {
            guard let navigationController,
                  let rootViewController else {
                return
            }

            if let transitionCoordinator = navigationController.transitionCoordinator {
                awaitNavigationTransition(transitionCoordinator)
                return
            }

            guard let desiredPlayerConfig else {
                guard let activeSession,
                      activeSession.owns(navigationController.topViewController) else {
                    return
                }
                navigationController.popToRootViewController(animated: true)
                return
            }

            guard dismissedConfigIDAwaitingStateUpdate != desiredPlayerConfig.id else {
                return
            }
            if activeSession?.config.id == desiredPlayerConfig.id {
                return
            }

            if activeSession == nil,
               navigationController.topViewController === rootViewController {
                let session = makePlayerSession(
                    config: desiredPlayerConfig,
                    navigationController: navigationController
                )
                activeSession = session
                navigationController.navigationBar.layer.removeAllAnimations()
                session.interactionController.prepareForPlayerPresentation(
                    for: session.initialStack.last,
                    using: nil
                )
                if session.initialStack.count == 1,
                   let playerViewController = session.initialStack.first {
                    navigationController.pushViewController(
                        playerViewController,
                        animated: desiredPresentationTransition.animatesNavigationTransition
                    )
                } else {
                    navigationController.setViewControllers(
                        [rootViewController] + session.initialStack,
                        animated: false
                    )
                }
                session.interactionController.prepareForPlayerPresentation(
                    for: session.initialStack.last,
                    using: navigationController.transitionCoordinator
                )
                return
            }

            replaceActivePlayer(
                with: desiredPlayerConfig,
                navigationController: navigationController,
                rootViewController: rootViewController
            )
        }

        private func awaitNavigationTransition(
            _ transitionCoordinator: any UIViewControllerTransitionCoordinator
        ) {
            guard !isAwaitingNavigationTransition else { return }
            isAwaitingNavigationTransition = true
            let didRegisterCompletion = transitionCoordinator.animate(
                alongsideTransition: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.isAwaitingNavigationTransition = false
                self.scheduleReconcile()
            }
            if !didRegisterCompletion {
                isAwaitingNavigationTransition = false
                scheduleReconcile()
            }
        }

        private func makePlayerSession(
            config: MobilePlayerConfig,
            navigationController: PlayerNavigationController
        ) -> PlayerSession {
            let collectionBrowserAvailable = PlayerCollectionBrowserSupport.isAvailable(
                for: config
            )
            let initialDisplayMode = MobilePlayerDisplayMode.initialMode(
                for: config,
                collectionBrowserAvailable: collectionBrowserAvailable
            )
            let chrome = MobilePlayerChromeController(
                playerBackgroundColor: MobilePlayerBackgroundColor.color(for: config),
                allowsNavigationBackSwipe: initialDisplayMode == .collectionBrowser
            )
            if let widgetTokenInsertion = config.widgetTokenInsertion {
                chrome.setPlayerNavigationTitle(
                    collectionTitle: widgetTokenInsertion.insertedToken.collectionName,
                    pageLabel: Strings.pagePosition(
                        current: widgetTokenInsertion.insertedTokenIndex + 1,
                        total: widgetTokenInsertion.anchorProgress.tokenCount
                    )
                )
            }
            let onDismiss: () -> Void = { [weak self] in
                self?.requestPop(configID: config.id)
            }
            let browserViewController = collectionBrowserAvailable
                ? MobilePlayerBrowserPageViewController(uuid: config.id, chrome: chrome)
                : nil
            let playerViewController = makeMobilePlayerViewController(
                config: config,
                onDismiss: onDismiss,
                chrome: chrome
            )
            let modeController = MobilePlayerSessionModeController(
                config: config,
                chrome: chrome,
                navigationController: navigationController,
                browserViewController: browserViewController,
                pagerViewController: playerViewController,
                initialMode: initialDisplayMode
            )
            browserViewController?.modeController = modeController
            NativeMetalCardView.resetMotionCalibration()
            UIApplication.shared.isIdleTimerDisabled = true

            navigationController.loadViewIfNeeded()
            let navigationBounds = navigationController.view.bounds
            playerViewController.loadViewIfNeeded()
            playerViewController.view.frame = navigationBounds
            playerViewController.view.layoutIfNeeded()
            if let browserViewController {
                browserViewController.loadViewIfNeeded()
                browserViewController.view.frame = navigationBounds
                browserViewController.view.layoutIfNeeded()
                browserViewController.seedNavigationTitles()
            }
            if initialDisplayMode == .collectionBrowser {
                chrome.pagerProvider?.deactivatePagerForCollectionBrowser()
                browserViewController?.setBrowserActive(true)
            }

            let interactionController = PlayerInteractionController(
                navigationController: navigationController,
                playerViewController: playerViewController,
                browserViewController: browserViewController,
                modeController: modeController,
                chrome: chrome,
                onDismiss: onDismiss
            )
            interactionController.install()

            let initialStack: [UIViewController]
            if let browserViewController {
                initialStack = initialDisplayMode == .collectionBrowser
                    ? [browserViewController]
                    : [browserViewController, playerViewController]
            } else {
                initialStack = [playerViewController]
            }
            return PlayerSession(
                config: config,
                chrome: chrome,
                pagerViewController: playerViewController,
                browserViewController: browserViewController,
                modeController: modeController,
                interactionController: interactionController,
                initialStack: initialStack
            )
        }

        private func replaceActivePlayer(
            with config: MobilePlayerConfig,
            navigationController: PlayerNavigationController,
            rootViewController: UIHostingController<RootView>
        ) {
            activeSession?.invalidate()

            let session = makePlayerSession(
                config: config,
                navigationController: navigationController
            )
            activeSession = session
            navigationController.setViewControllers(
                [rootViewController] + session.initialStack,
                animated: desiredPresentationTransition.animatesNavigationTransition
                    && session.initialStack.count == 1
            )
            session.interactionController.prepareForPlayerPresentation(
                for: session.initialStack.last,
                using: navigationController.transitionCoordinator
            )
        }

        private func requestPop(configID: UUID) {
            guard let navigationController,
                  let activeSession,
                  activeSession.config.id == configID,
                  activeSession.owns(navigationController.topViewController),
                  navigationController.transitionCoordinator == nil else {
                return
            }
            navigationController.popToRootViewController(animated: true)
        }

        func navigationController(
            _ navigationController: UINavigationController,
            willShow viewController: UIViewController,
            animated: Bool
        ) {
            if let activeSession,
               activeSession.owns(viewController) {
                activeSession.modeController.noteNavigationWillShow(viewController)
                activeSession.interactionController.prepareForPlayerPresentation(
                    for: viewController,
                    using: navigationController.transitionCoordinator
                )
                return
            }

            guard viewController === rootViewController else { return }
            activeSession?.interactionController.prepareForNavigationPopTransition(
                using: navigationController.transitionCoordinator
            )
        }

        func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            if let activeSession,
               activeSession.owns(viewController) {
                activeSession.modeController.noteNavigationDidShow(viewController)
                activeSession.interactionController.didShowPlayerAfterNavigationTransition()
                scheduleReconcile()
                return
            }

            guard viewController === rootViewController,
                  let completedSession = activeSession else {
                restoreRootNavigationState(navigationController)
                scheduleReconcile()
                return
            }

            activeSession = nil
            dismissedConfigIDAwaitingStateUpdate = completedSession.config.id
            completedSession.invalidate()
            restoreRootNavigationState(navigationController)
            let completedConfig = completedSession.config
            DispatchQueue.main.async { [weak self] in
                self?.onDismissPlayer?(completedConfig)
            }
            scheduleReconcile()
        }

        private func restoreRootNavigationState(_ navigationController: UINavigationController) {
            navigationController.navigationBar.layer.removeAllAnimations()
            navigationController.navigationBar.layer.isHidden = false
            navigationController.navigationBar.alpha = 1
            navigationController.navigationBar.accessibilityElementsHidden = false
            navigationController.setNeedsStatusBarAppearanceUpdate()
            rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
}

private func makeMobilePlayerViewController(
    config: MobilePlayerConfig,
    onDismiss: @escaping () -> Void,
    chrome: MobilePlayerChromeController
) -> MobilePlayerHostingController {
    let playerViewController = MobilePlayerHostingController(
        rootView: MobilePlayerView(
            config: config,
            onDismiss: onDismiss,
            chrome: chrome
        )
    )
    playerViewController.installNavigationTitle(chrome: chrome)
    playerViewController.onPermanentRemoval = {
        updateExternalDisplayToken(GeneratedToken.empty)
        NativeMetalCardView.resetMotionCalibration()
        MobilePlaybackController.shared.stopAndDisconnect(uuid: config.id)
    }
    return playerViewController
}

private final class MobilePlayerHostingController: UIHostingController<MobilePlayerView> {

    private var playerPageBackgroundColor = MobilePlayerBackgroundColor.defaultColor
    private var didFinalizePlayerSession = false
    private var playerNavigationTitleView: UIView?
    var onAccessibilityEscape: (() -> Bool)?
    var onPlayerLayout: (() -> Void)?
    var onPermanentRemoval: (() -> Void)?

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .none
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyPlayerPageBackground()
        restoreNavigationTitleIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restoreNavigationTitleIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyPlayerPageBackground()
        onPlayerLayout?()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyPlayerPageBackground()
    }

    override func accessibilityPerformEscape() -> Bool {
        if onAccessibilityEscape?() == true {
            return true
        }

        return super.accessibilityPerformEscape()
    }

    func setPlayerPageBackground(color: UIColor) {
        playerPageBackgroundColor = color

        guard isViewLoaded else { return }
        applyPlayerPageBackground()
    }

    func installNavigationTitle(chrome: MobilePlayerChromeController) {
        guard playerNavigationTitleView == nil else {
            restoreNavigationTitleIfNeeded()
            return
        }

        let titleView = UIHostingConfiguration {
            PlayerNavigationTitleView(chrome: chrome)
        }
        .margins(.all, 0)
        .makeContentView()
        playerNavigationTitleView = titleView
        navigationItem.titleView = titleView
    }

    func restoreNavigationTitleIfNeeded() {
        guard let playerNavigationTitleView,
              navigationItem.titleView !== playerNavigationTitleView else {
            return
        }
        navigationItem.titleView = playerNavigationTitleView
    }

    func finalizePlayerSession() {
        guard !didFinalizePlayerSession else { return }
        didFinalizePlayerSession = true
        let finalizer = onPermanentRemoval
        onPermanentRemoval = nil
        finalizer?()
    }

    private func applyPlayerPageBackground() {
        view.backgroundColor = playerPageBackgroundColor
        view.isOpaque = true
    }

}

private final class GestureFailureRequirementRegistry {

    private final class RequirementSet {
        weak var gestureRecognizer: UIGestureRecognizer?
        let requiredGestureRecognizers =
            NSHashTable<UIGestureRecognizer>(
                options: [.weakMemory, .objectPointerPersonality]
            )

        init(gestureRecognizer: UIGestureRecognizer) {
            self.gestureRecognizer = gestureRecognizer
        }
    }

    private var requirementSetsByGestureRecognizer =
        [ObjectIdentifier: RequirementSet]()

    func require(
        _ gestureRecognizer: UIGestureRecognizer,
        toFail requiredToFailGestureRecognizer: UIGestureRecognizer
    ) {
        let requirementSet = requirementSet(for: gestureRecognizer)
        let requiredGestureRecognizers =
            requirementSet.requiredGestureRecognizers
        guard !requiredGestureRecognizers.contains(
            requiredToFailGestureRecognizer
        ) else {
            return
        }

        gestureRecognizer.require(toFail: requiredToFailGestureRecognizer)
        requiredGestureRecognizers.add(requiredToFailGestureRecognizer)
    }

    func contains(
        _ gestureRecognizer: UIGestureRecognizer,
        requiringFailureOf requiredToFailGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let identifier = ObjectIdentifier(gestureRecognizer)
        guard let requirementSet = requirementSetsByGestureRecognizer[identifier],
              requirementSet.gestureRecognizer === gestureRecognizer else {
            return false
        }

        return requirementSet.requiredGestureRecognizers.contains(
            requiredToFailGestureRecognizer
        )
    }

    func removeInvalidRequirements() {
        requirementSetsByGestureRecognizer =
            requirementSetsByGestureRecognizer.filter {
                $0.value.gestureRecognizer != nil
            }
    }

    private func requirementSet(
        for gestureRecognizer: UIGestureRecognizer
    ) -> RequirementSet {
        let identifier = ObjectIdentifier(gestureRecognizer)
        if let requirementSet = requirementSetsByGestureRecognizer[identifier],
           requirementSet.gestureRecognizer === gestureRecognizer {
            return requirementSet
        }

        let requirementSet = RequirementSet(
            gestureRecognizer: gestureRecognizer
        )
        requirementSetsByGestureRecognizer[identifier] = requirementSet
        return requirementSet
    }
}

private final class NavigationBackGestureGate:
    UIPanGestureRecognizer,
    UIGestureRecognizerDelegate {

    var shouldBlockNavigationBack: () -> Bool = { false }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)

        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        maximumNumberOfTouches = 1
        allowedScrollTypesMask = .all
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        shouldBlockNavigationBack()
    }

    override func canPrevent(
        _ preventedGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    override func canBePrevented(
        by preventingGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

private final class NavigationBackDirectTouchGate: UIGestureRecognizer {

    var shouldBlockNavigationBack: () -> Bool = { false }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)

        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func shouldReceive(_ event: UIEvent) -> Bool {
        guard super.shouldReceive(event) else { return false }
        return event.type == .touches
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard state == .possible else { return }

        state = shouldBlockNavigationBack() ? .recognized : .failed
    }

    override func canPrevent(
        _ preventedGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    override func canBePrevented(
        by preventingGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

private final class PlayerTopEdgeTintView: UIView {

    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.68).cgColor,
            UIColor.black.withAlphaComponent(0.50).cgColor,
            UIColor.black.withAlphaComponent(0.32).cgColor,
            UIColor.black.withAlphaComponent(0.17).cgColor,
            UIColor.black.withAlphaComponent(0.06).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor,
        ]
        gradientLayer.locations = [0, 0.2, 0.4, 0.6, 0.8, 1]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        CATransaction.commit()
    }
}

private final class PlayerNavigationController: UINavigationController {

    var canEnforceNavigationBarChromeVisibility: (() -> Bool)?
    weak var cardTransitionOverlayView: UIView?
    private let topEdgeTintView = PlayerTopEdgeTintView()
    private var navigationBarChromeTargetAlpha: CGFloat?
    private var isNavigationBarChromeVisibilityEnforcementSuspended = false
    private var forcesStatusBarVisibleForCollectionBrowserTransition = false
    private weak var navigationBackGestureBlockingProviderOwner: AnyObject?
    private var navigationBackGestureBlockingProvider: (() -> Bool)?
    private let navigationBackGestureFailureRequirements =
        GestureFailureRequirementRegistry()
    private lazy var navigationBackDirectTouchGate:
        NavigationBackDirectTouchGate = {
            let gestureRecognizer = NavigationBackDirectTouchGate(
                target: nil,
                action: nil
            )
            gestureRecognizer.shouldBlockNavigationBack = { [weak self] in
                self?.navigationBackGestureBlockingProvider?() ?? false
            }
            return gestureRecognizer
        }()
    private lazy var navigationBackGestureGate: NavigationBackGestureGate = {
        let gestureRecognizer = NavigationBackGestureGate(
            target: nil,
            action: nil
        )
        gestureRecognizer.shouldBlockNavigationBack = { [weak self] in
            self?.navigationBackGestureBlockingProvider?() ?? false
        }
        return gestureRecognizer
    }()

    var interactiveBackGestureRecognizers: [UIGestureRecognizer] {
        var gestureRecognizers = [UIGestureRecognizer]()
        if let interactivePopGestureRecognizer {
            gestureRecognizers.append(interactivePopGestureRecognizer)
        }
        if #available(iOS 26.0, *),
           let interactiveContentPopGestureRecognizer {
            gestureRecognizers.append(interactiveContentPopGestureRecognizer)
        }
        return gestureRecognizers
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.insertSubview(topEdgeTintView, belowSubview: navigationBar)
        view.addGestureRecognizer(navigationBackDirectTouchGate)
        view.addGestureRecognizer(navigationBackGestureGate)
        configureNavigationBackGestureBlocking()
    }

    func setNavigationBackGestureBlockingProvider(
        owner: AnyObject,
        provider: @escaping () -> Bool
    ) {
        navigationBackGestureBlockingProviderOwner = owner
        navigationBackGestureBlockingProvider = provider
        configureNavigationBackGestureBlocking()
    }

    func clearNavigationBackGestureBlockingProvider(owner: AnyObject) {
        guard navigationBackGestureBlockingProviderOwner === owner else {
            return
        }

        navigationBackGestureBlockingProviderOwner = nil
        navigationBackGestureBlockingProvider = nil
    }

    func configureNavigationBackGestureBlocking() {
        loadViewIfNeeded()
        navigationBackGestureFailureRequirements.removeInvalidRequirements()
        interactiveBackGestureRecognizers.forEach { gestureRecognizer in
            navigationBackGestureFailureRequirements.require(
                gestureRecognizer,
                toFail: navigationBackDirectTouchGate
            )
            navigationBackGestureFailureRequirements.require(
                gestureRecognizer,
                toFail: navigationBackGestureGate
            )
        }
    }

    override var childForStatusBarHidden: UIViewController? {
        forcesStatusBarVisibleForCollectionBrowserTransition
            ? nil
            : topViewController
    }

    override var prefersStatusBarHidden: Bool {
        forcesStatusBarVisibleForCollectionBrowserTransition
            ? false
            : super.prefersStatusBarHidden
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .none
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        alignNavigationBarBelowForcedStatusBar()
        synchronizeNavigationBarChromeVisibility()
        keepCardTransitionOverlayBelowNavigationBar()
        layoutTopEdgeTint()
    }

    private func keepCardTransitionOverlayBelowNavigationBar() {
        guard let cardTransitionOverlayView,
              cardTransitionOverlayView.superview === view else {
            return
        }

        cardTransitionOverlayView.frame = view.bounds
        view.insertSubview(cardTransitionOverlayView, belowSubview: navigationBar)
    }

    func assertTopEdgeTintPlacement() {
        layoutTopEdgeTint()
    }

    private func layoutTopEdgeTint() {
        let statusBarInset = view.safeAreaInsets.top
        let hasStatusBarRegion = statusBarInset >= 20
        topEdgeTintView.isHidden = !hasStatusBarRegion
        topEdgeTintView.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: statusBarInset * 2.9
        )
        view.insertSubview(topEdgeTintView, belowSubview: navigationBar)
    }

    func setTopEdgeTintAlpha(_ alpha: CGFloat) {
        topEdgeTintView.alpha = min(max(alpha, 0), 1)
    }

    var topEdgeTintAlpha: CGFloat {
        topEdgeTintView.alpha
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(hidden, animated: animated)

        guard !hidden else { return }
        synchronizeNavigationBarChromeVisibility()
    }

    func setCollectionBrowserTransitionStatusBarVisible(_ isVisible: Bool) {
        guard forcesStatusBarVisibleForCollectionBrowserTransition != isVisible else {
            return
        }

        forcesStatusBarVisibleForCollectionBrowserTransition = isVisible
        setNeedsStatusBarAppearanceUpdate()
        alignNavigationBarBelowForcedStatusBar()
    }

    private func alignNavigationBarBelowForcedStatusBar() {
        guard forcesStatusBarVisibleForCollectionBrowserTransition,
              let window = view.window,
              let statusBarManager = window.windowScene?.statusBarManager,
              !statusBarManager.isStatusBarHidden else {
            return
        }

        let statusBarFrameInWindow = window.convert(
            statusBarManager.statusBarFrame,
            from: window.screen.coordinateSpace
        )
        let statusBarFrameInView = view.convert(
            statusBarFrameInWindow,
            from: window
        )
        let navigationBarMinY = max(
            view.safeAreaInsets.top,
            statusBarFrameInView.maxY
        )
        guard navigationBarMinY.isFinite,
              abs(navigationBar.frame.minY - navigationBarMinY)
                > 1 / window.screen.scale else {
            return
        }

        var frame = navigationBar.frame
        frame.origin.y = navigationBarMinY
        navigationBar.frame = frame
    }

    func setNavigationBarChromeVisible(
        _ isVisible: Bool,
        animationDuration: TimeInterval?
    ) {
        let targetAlpha: CGFloat = isVisible ? 1 : 0
        navigationBarChromeTargetAlpha = targetAlpha

        guard !isNavigationBarChromeVisibilityEnforcementSuspended else {
            return
        }

        navigationBar.accessibilityElementsHidden = !isVisible
        if !isVisible {
            navigationBar.layer.isHidden = true
        }

        guard let animationDuration else {
            guard navigationBar.alpha != targetAlpha else {
                if isVisible {
                    navigationBar.layer.isHidden = false
                }
                return
            }

            navigationBar.layer.removeAllAnimations()
            navigationBar.alpha = targetAlpha
            if isVisible {
                navigationBar.layer.isHidden = false
            }
            return
        }

        if isVisible {
            navigationBar.layer.isHidden = false
        }
        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.navigationBar.alpha = targetAlpha
        } completion: { [weak self] _ in
            self?.synchronizeNavigationBarChromeVisibility()
        }
    }

    func finishNavigationBarChromeHideAnimation() {
        navigationBarChromeTargetAlpha = 0

        guard !isNavigationBarChromeVisibilityEnforcementSuspended,
              canEnforceNavigationBarChromeVisibility?() == true else {
            return
        }

        navigationBar.accessibilityElementsHidden = true
        navigationBar.layer.isHidden = true
        removeNavigationBarOpacityAnimations()
        UIView.performWithoutAnimation {
            navigationBar.alpha = 0
        }
    }

    func setNavigationBarChromeVisibilityEnforcementSuspended(
        _ isSuspended: Bool
    ) {
        isNavigationBarChromeVisibilityEnforcementSuspended = isSuspended
    }

    func resetNavigationBarChromeVisibilityState() {
        navigationBarChromeTargetAlpha = nil
        isNavigationBarChromeVisibilityEnforcementSuspended = false
        navigationBar.accessibilityElementsHidden = false
        navigationBar.layer.isHidden = false
    }

    func synchronizeNavigationBarChromeVisibility() {
        guard !isNavigationBarChromeVisibilityEnforcementSuspended,
              canEnforceNavigationBarChromeVisibility?() == true,
              let targetAlpha = navigationBarChromeTargetAlpha else {
            return
        }

        navigationBar.accessibilityElementsHidden = targetAlpha == 0
        if targetAlpha == 0 {
            navigationBar.layer.isHidden = true
        }
        guard navigationBar.alpha != targetAlpha else {
            if targetAlpha != 0 {
                navigationBar.layer.isHidden = false
            }
            return
        }

        navigationBar.layer.removeAllAnimations()
        navigationBar.alpha = targetAlpha
        if targetAlpha != 0 {
            navigationBar.layer.isHidden = false
        }
    }

    private func removeNavigationBarOpacityAnimations() {
        let layer = navigationBar.layer
        (layer.animationKeys() ?? []).forEach { key in
            guard let animation = layer.animation(forKey: key),
                  Self.affectsOpacity(animation) else {
                return
            }

            layer.removeAnimation(forKey: key)
        }
    }

    private static func affectsOpacity(_ animation: CAAnimation) -> Bool {
        if let propertyAnimation = animation as? CAPropertyAnimation,
           propertyAnimation.keyPath == "opacity" {
            return true
        }

        return (animation as? CAAnimationGroup)?
            .animations?
            .contains(where: affectsOpacity) == true
    }

}

private final class CardTransitionUnderlayView: UIView {

    private final class LateImageEntry {
        let itemSnapshot: MobilePlayerBrowserItemSnapshot
        let imageView = NativeMetalCardCornerMaskedImageView()
        var cancellation: (() -> Void)?
        var hasLoadedImage = false

        init(itemSnapshot: MobilePlayerBrowserItemSnapshot) {
            self.itemSnapshot = itemSnapshot
        }
    }

    private static let lateImageFadeDuration: TimeInterval = 0.12
    private let itemSnapshots: [MobilePlayerBrowserItemSnapshot]
    private var lateImageEntries = [LateImageEntry]()
    private var revealProgress: CGFloat = 0

    init(itemSnapshots: [MobilePlayerBrowserItemSnapshot]) {
        self.itemSnapshots = itemSnapshots
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        makeBackgroundTransparent()
        clipsToBounds = true

        itemSnapshots.forEach { itemSnapshot in
            let snapshotView = itemSnapshot.snapshotView
            snapshotView.removeFromSuperview()
            snapshotView.layer.removeAllAnimations()
            snapshotView.transform = .identity
            snapshotView.alpha = 0
            snapshotView.isHidden = false
            snapshotView.isUserInteractionEnabled = false
            addSubview(snapshotView)
        }
        startLateImageLoads()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        lateImageEntries.forEach { $0.cancellation?() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for itemSnapshot in itemSnapshots {
            itemSnapshot.snapshotView.frame = convert(itemSnapshot.frameInWindow, from: nil)
        }
        lateImageEntries.forEach { entry in
            entry.imageView.frame = entry.itemSnapshot.snapshotView.frame
        }
    }

    func setOtherCardsRevealProgress(_ progress: CGFloat) {
        let clampedProgress = min(max(progress, 0), 1)
        revealProgress = clampedProgress
        itemSnapshots.forEach { itemSnapshot in
            itemSnapshot.snapshotView.alpha = clampedProgress
        }
        lateImageEntries.forEach { entry in
            entry.itemSnapshot.snapshotView.alpha = entry.hasLoadedImage ? 0 : clampedProgress
            entry.imageView.alpha = entry.hasLoadedImage ? clampedProgress : 0
        }
    }

    private func startLateImageLoads() {
        for itemSnapshot in itemSnapshots where !itemSnapshot.hasLoadedImage {
            guard let descriptor = itemSnapshot.descriptor,
                  descriptor.isStaticImage else {
                continue
            }

            let entry = LateImageEntry(itemSnapshot: itemSnapshot)
            entry.imageView.backgroundColor = .clear
            entry.imageView.contentMode = .scaleAspectFit
            entry.imageView.clipsToBounds = true
            entry.imageView.isUserInteractionEnabled = false
            entry.imageView.usesNativeMetalCardCornerMask = descriptor.usesNativeMetalCardPresentation
            entry.imageView.alpha = 0
            addSubview(entry.imageView)
            lateImageEntries.append(entry)

            if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
                displayLateImage(image, for: entry, animated: false)
                continue
            }

            entry.cancellation = DownloadableMediaCache.shared.loadImage(for: descriptor) { [weak self, weak entry] image in
                DispatchQueue.main.async {
                    guard let self,
                          let entry,
                          self.lateImageEntries.contains(where: { $0 === entry }) else {
                        return
                    }
                    entry.cancellation = nil
                    guard let image else { return }
                    self.displayLateImage(image, for: entry, animated: true)
                }
            }
        }
    }

    private func displayLateImage(
        _ image: UIImage,
        for entry: LateImageEntry,
        animated: Bool
    ) {
        entry.hasLoadedImage = true
        entry.imageView.image = image
        entry.imageView.frame = entry.itemSnapshot.snapshotView.frame

        let updates = {
            entry.itemSnapshot.snapshotView.alpha = 0
            entry.imageView.alpha = self.revealProgress
        }
        guard animated,
              revealProgress > 0 else {
            updates()
            return
        }

        entry.imageView.alpha = 0
        UIView.animate(
            withDuration: Self.lateImageFadeDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: updates
        )
    }

}

private final class CardLayoutPinchGestureRecognizer: UIGestureRecognizer {

    var activationScale: CGFloat = 1
    var oppositeDirectionFailureScale: CGFloat = 1
    var canTrackPinch: ((CardLayoutPinchGestureRecognizer) -> Bool)?

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

            if scale > oppositeDirectionFailureScale {
                state = .failed
            } else if scale <= activationScale {
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

final class PendingMainQueueUpdate {

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

private final class PlayerInteractionController: NSObject, UIGestureRecognizerDelegate {

    private static let cardTransitionHorizontalDragDamping: CGFloat = 0.18
    private static let cardTransitionVerticalDragDamping: CGFloat = 0.32
    private static let cardMinimizeAnimationDuration: TimeInterval = 0.22
    private static let navigationBarSideControlRegionWidth: CGFloat = 96
    private static let navigationBarShowDuration: TimeInterval = 0
    private static let navigationBarHideDuration: TimeInterval = 0

    private enum CardMinimizeCommitDestination {
        case browserCell(CGRect)
        case offscreen
    }

    private struct ZoomedCardMinimizeForeground {
        let view: UIView
        let sourceFrame: CGRect
    }

    private struct CardMinimizeTransitionContext {
        let id: UUID
        let sourcePagePosition: PlayerPagePosition
        let sourceFrame: CGRect
        let targetScale: CGFloat
        let commitDestination: CardMinimizeCommitDestination
        let foregroundView: UIView
        let zoomedForeground: ZoomedCardMinimizeForeground?
        let underlayView: CardTransitionUnderlayView
        let hasPreparedBrowserSelection: Bool
    }

    private struct CardExpandTransitionContext {
        let id: UUID
        let targetPagePosition: PlayerPagePosition
        let sourceFrame: CGRect
        let targetFrame: CGRect
        let foregroundView: UIView
        let underlayView: CardTransitionUnderlayView
    }

    let playerNavigationController: PlayerNavigationController
    let playerViewController: MobilePlayerHostingController
    let browserViewController: MobilePlayerBrowserPageViewController?
    let modeController: MobilePlayerSessionModeController
    let chrome: MobilePlayerChromeController
    let onDismiss: () -> Void

    private let cardTransitionCanvas = MobilePlayerCardTransitionCanvas()

    private var view: UIView {
        playerViewController.view
    }

    private var cardTransitionCanvasView: UIView {
        cardTransitionCanvas.view
    }

    private func isSessionViewController(_ viewController: UIViewController?) -> Bool {
        guard let viewController else { return false }
        return viewController === playerViewController
            || viewController === browserViewController
    }

    private lazy var navigationBarTap = UITapGestureRecognizer(target: self, action: #selector(handleNavigationBarTap(_:)))
    private lazy var navigationBackAction = UIAction(
        title: Strings.back
    ) { [weak self] _ in
        _ = self?.handleNavigationBackAction()
    }
    private lazy var pagerBackBarButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "chevron.backward"),
            primaryAction: navigationBackAction,
            menu: makePagerBackMenu()
        )
        item.accessibilityLabel = Strings.back
        return item
    }()
    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    private lazy var controlsPan = UIPanGestureRecognizer(target: self, action: #selector(handleControlsPan(_:)))
    private lazy var cardMinimizePinch: CardLayoutPinchGestureRecognizer = {
        let gesture = CardLayoutPinchGestureRecognizer(target: self, action: #selector(handleCardMinimizePinch(_:)))
        gesture.activationScale = MobilePlayerGestureTuning.cardMinimizePinchActivationScale
        gesture.oppositeDirectionFailureScale = MobilePlayerGestureTuning.cardMinimizePinchZoomInFailureScale
        gesture.canTrackPinch = { [weak self] gesture in
            guard let self else { return false }
            if gesture.isFirstPinchTrackingEvaluation {
                self.configurePagerScrollViews()
            }
            return self.canBeginCardMinimizeInteraction(
                location: gesture.pinchLocation(in: self.view)
            )
        }
        return gesture
    }()
    private lazy var pinchRotation = UIRotationGestureRecognizer(target: self, action: #selector(handlePinchRotation(_:)))
    private let gestureFailureRequirements =
        GestureFailureRequirementRegistry()
    private var isInstalled = false
    private var isDismissPanDrivingCardMinimize = false
    private var isCardMinimizePinchDrivingCardMinimize = false
    private var cardMinimizePinchStartLocation = CGPoint.zero
    private var cardMinimizePinchStartRotation: CGFloat = 0
    private var cardMinimizePinchRotation: CGFloat = 0
    private lazy var cardMinimizePinchPresentationUpdate = PendingMainQueueUpdate { [weak self] in
        guard let self else { return }
        guard self.isCardMinimizePinchDrivingCardMinimize else { return }

        self.applyCardMinimizePinchPresentation(self.cardMinimizePinch)
    }
    private lazy var navigationToolbarUpdate = PendingMainQueueUpdate { [weak self] in
        self?.synchronizeNavigationBarAfterToolbarUpdate()
    }
    private var activeCardMinimizeContext: CardMinimizeTransitionContext?
    private var activeCardExpandContext: CardExpandTransitionContext?
    private var isCardMinimizeAnimationComplete = false
    private var isCardMinimizeLayoutApplied = false
    private var isCardExpandAnimationComplete = false
    private var isCardExpandLayoutApplied = false
    private var playerInteractionEnabledBeforeLivePagerFade: Bool?
    private var topEdgeTintAnimator: UIViewPropertyAnimator?
    private var pendingTopEdgeTintWorkItem: DispatchWorkItem?
    private var didControlsPanConflictWithHorizontalScroll = false
    private var isNavigationBackDisplayModeRequestPending = false
    private var chromeCancellables = Set<AnyCancellable>()

    init(
        navigationController: PlayerNavigationController,
        playerViewController: MobilePlayerHostingController,
        browserViewController: MobilePlayerBrowserPageViewController?,
        modeController: MobilePlayerSessionModeController,
        chrome: MobilePlayerChromeController,
        onDismiss: @escaping () -> Void
    ) {
        self.playerNavigationController = navigationController
        self.playerViewController = playerViewController
        self.browserViewController = browserViewController
        self.modeController = modeController
        self.chrome = chrome
        self.onDismiss = onDismiss
        super.init()
        playerNavigationController.canEnforceNavigationBarChromeVisibility = {
            [weak navigationController, weak playerViewController, weak browserViewController] in
            guard let navigationController,
                  let topViewController = navigationController.topViewController,
                  topViewController === playerViewController
                    || (browserViewController != nil && topViewController === browserViewController),
                  navigationController.transitionCoordinator == nil else {
                return false
            }

            return true
        }
        chrome.onCollectionBrowserExpandRequest = { [weak self] selection in
            self?.beginProgrammaticCardExpand(selection: selection) ?? .rejected
        }
        setNavigationBarChromeVisible(
            shouldShowNavigationBarChrome,
            animated: false
        )
        observePlayerBackgroundColor()
        observeNavigationToolbarUpdates()
        observeNavigationBarChromeVisibility()
    }

    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        installNavigationBackAction()
        playerViewController.onAccessibilityEscape = { [weak self] in
            self?.handleNavigationBackAction() ?? false
        }
        playerViewController.onPlayerLayout = { [weak self] in
            guard let self else { return }

            self.installNavigationBackAction()
            self.playerViewController.restoreNavigationTitleIfNeeded()
            self.playerNavigationController
                .configureNavigationBackGestureBlocking()
            self.configurePagerScrollViews()
        }
        browserViewController?.onAccessibilityEscape = { [weak self] in
            self?.handleNavigationBackAction() ?? false
        }
        browserViewController?.onPlayerLayout = { [weak self] in
            guard let self else { return }

            self.installNavigationBackAction()
            self.playerNavigationController
                .configureNavigationBackGestureBlocking()
            self.configureBrowserScrollViews()
        }
        playerViewController.loadViewIfNeeded()
        browserViewController?.loadViewIfNeeded()

        playerNavigationController.loadViewIfNeeded()
        cardTransitionCanvasView.frame = playerNavigationController.view.bounds
        cardTransitionCanvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerNavigationController.view.insertSubview(
            cardTransitionCanvasView,
            belowSubview: playerNavigationController.navigationBar
        )
        playerNavigationController.cardTransitionOverlayView = cardTransitionCanvasView

        playerNavigationController.setNavigationBackGestureBlockingProvider(
            owner: self
        ) { [weak self] in
            self?.shouldBlockNavigationBackGesture ?? false
        }

        navigationBarTap.delegate = self
        navigationBarTap.numberOfTapsRequired = 1
        navigationBarTap.numberOfTouchesRequired = 1
        navigationBarTap.cancelsTouchesInView = false
        playerNavigationController.navigationBar.addGestureRecognizer(navigationBarTap)

        dismissPan.delegate = self
        dismissPan.cancelsTouchesInView = false
        dismissPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(dismissPan)

        controlsPan.delegate = self
        controlsPan.cancelsTouchesInView = false
        controlsPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(controlsPan)

        playerNavigationController.configureNavigationBackGestureBlocking()

        cardMinimizePinch.delegate = self
        cardMinimizePinch.cancelsTouchesInView = false
        view.addGestureRecognizer(cardMinimizePinch)

        pinchRotation.delegate = self
        pinchRotation.cancelsTouchesInView = false
        view.addGestureRecognizer(pinchRotation)

        configurePagingScrollViews()
    }

    func invalidate() {
        guard isInstalled else { return }
        isInstalled = false
        isNavigationBackDisplayModeRequestPending = false
        cardMinimizePinchPresentationUpdate.invalidate()
        navigationToolbarUpdate.invalidate()
        chromeCancellables.removeAll()
        playerViewController.onAccessibilityEscape = nil
        playerViewController.onPlayerLayout = nil
        browserViewController?.onAccessibilityEscape = nil
        browserViewController?.onPlayerLayout = nil

        if playerViewController.navigationItem.leftBarButtonItem === pagerBackBarButtonItem {
            playerViewController.navigationItem.leftBarButtonItem = nil
        }
        if let browserViewController,
           browserViewController.navigationItem.backAction?.identifier
            == navigationBackAction.identifier {
            browserViewController.navigationItem.backAction = nil
        }
        playerNavigationController.clearNavigationBackGestureBlockingProvider(
            owner: self
        )
        playerNavigationController.canEnforceNavigationBarChromeVisibility = nil
        playerNavigationController.resetNavigationBarChromeVisibilityState()
        playerNavigationController.navigationBar.removeGestureRecognizer(navigationBarTap)
        view.removeGestureRecognizer(dismissPan)
        view.removeGestureRecognizer(controlsPan)
        view.removeGestureRecognizer(cardMinimizePinch)
        view.removeGestureRecognizer(pinchRotation)

        cleanupCardMinimizeTransition(
            revealPlayer: false,
            cancelPreparedBrowserSelection: true
        )
        cleanupCardExpandTransition(revealPlayer: false)
        cardTransitionCanvasView.subviews.forEach { $0.removeFromSuperview() }
        setCardTransitionCanvasActive(false)
        cardTransitionCanvasView.removeFromSuperview()
        if playerNavigationController.cardTransitionOverlayView === cardTransitionCanvasView {
            playerNavigationController.cardTransitionOverlayView = nil
        }

        chrome.onCollectionBrowserExpandRequest = nil
        chrome.setPlayerContentHiddenForCardTransition(false)

        view.layer.removeAllAnimations()
        view.alpha = 1
        view.transform = .identity
        playerNavigationController.navigationBar.layer.removeAllAnimations()
        playerNavigationController.navigationBar.alpha = 1
        setTopEdgeTintAlphaDirectly(1)
        playerNavigationController.setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func handleNavigationBarTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard !chrome.isCollectionBrowserActive else { return }

        chrome.setControlsVisible(false)
    }

    func didShowPlayerAfterNavigationTransition() {
        guard isInstalled else { return }
        playerNavigationController
            .setNavigationBarChromeVisibilityEnforcementSuspended(false)
        installNavigationBackAction()
        setNavigationBarChromeVisible(shouldShowNavigationBarChrome, animated: true)
        updateTopEdgeTint(
            forPagerTarget: playerNavigationController.topViewController === playerViewController,
            using: nil
        )
        playerNavigationController.configureNavigationBackGestureBlocking()
        configurePagingScrollViews()
        playerNavigationController.setNeedsStatusBarAppearanceUpdate()
        playerNavigationController.topViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    func prepareForNavigationPopTransition(
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        playerNavigationController
            .setNavigationBarChromeVisibilityEnforcementSuspended(true)
        let navigationBar = playerNavigationController.navigationBar
        navigationBar.accessibilityElementsHidden = false
        navigationBar.layer.isHidden = false
        navigationBar.layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            navigationBar.alpha = 1
        }
        updateTopEdgeTint(forPagerTarget: false, using: transitionCoordinator)
        guard let transitionCoordinator else { return }

        transitionCoordinator.animate { _ in
            UIView.performWithoutAnimation {
                navigationBar.alpha = 1
            }
        }
    }

    func prepareForPlayerPresentation(
        for targetViewController: UIViewController?,
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        playerNavigationController
            .setNavigationBarChromeVisibilityEnforcementSuspended(false)
        installNavigationBackAction()
        playerNavigationController.configureNavigationBackGestureBlocking()
        let navigationBar = playerNavigationController.navigationBar
        navigationBar.layer.removeAllAnimations()
        let targetAlpha: CGFloat = shouldShowNavigationBarChrome ? 1 : 0
        setNavigationBarChromeVisible(
            shouldShowNavigationBarChrome,
            animated: false
        )
        updateTopEdgeTint(
            forPagerTarget: targetViewController === playerViewController,
            using: transitionCoordinator
        )
        guard let transitionCoordinator else {
            return
        }

        transitionCoordinator.animate { _ in
            UIView.performWithoutAnimation {
                navigationBar.alpha = targetAlpha
            }
        }
    }

    private func updateTopEdgeTint(
        forPagerTarget isPagerTarget: Bool,
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        guard !isCardTransitionActive else { return }

        let targetAlpha: CGFloat = isPagerTarget ? 0 : 1
        guard playerNavigationController.topEdgeTintAlpha != targetAlpha else {
            cancelScheduledTopEdgeTintChanges()
            return
        }
        guard let transitionCoordinator else {
            setTopEdgeTintAlphaDirectly(targetAlpha)
            return
        }

        cancelScheduledTopEdgeTintChanges()
        transitionCoordinator.animate { [weak self] _ in
            self?.playerNavigationController.setTopEdgeTintAlpha(targetAlpha)
        }
    }

    private func cancelScheduledTopEdgeTintChanges() {
        pendingTopEdgeTintWorkItem?.cancel()
        pendingTopEdgeTintWorkItem = nil
        if let topEdgeTintAnimator, topEdgeTintAnimator.state != .inactive {
            topEdgeTintAnimator.stopAnimation(true)
        }
        topEdgeTintAnimator = nil
    }

    private func setTopEdgeTintAlphaDirectly(_ alpha: CGFloat) {
        cancelScheduledTopEdgeTintChanges()
        playerNavigationController.setTopEdgeTintAlpha(alpha)
    }

    private func animateTopEdgeTint(to alpha: CGFloat, delay: TimeInterval = 0) {
        cancelScheduledTopEdgeTintChanges()

        let startAnimation = { [weak self] in
            guard let self else { return }
            let animator = UIViewPropertyAnimator(duration: 0.06, curve: .linear) {
                self.playerNavigationController.setTopEdgeTintAlpha(alpha)
            }
            self.topEdgeTintAnimator = animator
            animator.startAnimation()
        }
        guard delay > 0 else {
            startAnimation()
            return
        }

        let workItem = DispatchWorkItem(block: startAnimation)
        pendingTopEdgeTintWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func observePlayerBackgroundColor() {
        chrome.$playerBackgroundColor
            .sink { [weak self] color in
                guard let self else { return }
                self.playerViewController.setPlayerPageBackground(color: color)
                self.browserViewController?.setPlayerPageBackground(color: color)
                self.cardTransitionCanvasView.backgroundColor = color
            }
            .store(in: &chromeCancellables)
    }

    private func observeNavigationToolbarUpdates() {
        chrome.$allowsNavigationBackSwipe
            .combineLatest(chrome.$isPlayerContentHiddenForCardTransition)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.scheduleNavigationBarSynchronization()
            }
            .store(in: &chromeCancellables)
    }

    private func scheduleNavigationBarSynchronization() {
        navigationToolbarUpdate.invalidate()
        navigationToolbarUpdate.schedule()
    }

    private func synchronizeNavigationBarAfterToolbarUpdate() {
        guard isInstalled,
              isSessionViewController(playerNavigationController.topViewController),
              playerNavigationController.transitionCoordinator == nil else {
            return
        }

        installNavigationBackAction()
        playerViewController.restoreNavigationTitleIfNeeded()
        playerNavigationController.configureNavigationBackGestureBlocking()
        configurePagingScrollViews()
        playerNavigationController.synchronizeNavigationBarChromeVisibility()
    }

    private func observeNavigationBarChromeVisibility() {
        chrome.$showControls
            .combineLatest(chrome.$allowsNavigationBackSwipe)
            .map { showControls, allowsNavigationBackSwipe in
                MobilePlayerChromeController.shouldShowPlayerChrome(
                    showControls: showControls,
                    allowsNavigationBackSwipe: allowsNavigationBackSwipe
                )
            }
            .removeDuplicates()
            .sink { [weak self] isVisible in
                guard let self else { return }

                self.setNavigationBarChromeVisible(isVisible, animated: true)
                self.scheduleNavigationBarSynchronization()
            }
            .store(in: &chromeCancellables)
    }

    private var shouldShowNavigationBarChrome: Bool {
        chrome.isPlayerChromeVisible
    }

    private func installNavigationBackAction() {
        let stackedViewControllers = playerNavigationController.viewControllers.dropFirst()

        if let browserViewController,
           stackedViewControllers.contains(where: { $0 === browserViewController }) {
            let navigationItem = browserViewController.navigationItem
            if navigationItem.backAction?.identifier != navigationBackAction.identifier {
                navigationItem.backAction = navigationBackAction
            }
        }

        if stackedViewControllers.contains(where: { $0 === playerViewController }) {
            let navigationItem = playerViewController.navigationItem
            if navigationItem.leftBarButtonItem !== pagerBackBarButtonItem {
                navigationItem.leftBarButtonItem = pagerBackBarButtonItem
            }
        }
    }

    private func makePagerBackMenu() -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self else {
                    completion([])
                    return
                }

                var actions = [UIAction]()
                if let browserViewController = self.browserViewController,
                   self.playerNavigationController.viewControllers
                    .contains(where: { $0 === browserViewController }) {
                    let title = browserViewController.navigationItem.backButtonTitle
                        ?? Strings.back
                    actions.append(
                        UIAction(title: title) { [weak self] _ in
                            self?.popExternallyToBrowser()
                        }
                    )
                }
                actions.append(
                    UIAction(title: Strings.nftPlayer) { [weak self] _ in
                        self?.popExternallyToRoot()
                    }
                )
                completion(actions)
            }
        ])
    }

    private func popExternallyToBrowser() {
        guard isInstalled,
              let browserViewController,
              playerNavigationController.transitionCoordinator == nil,
              playerNavigationController.topViewController === playerViewController,
              playerNavigationController.viewControllers
                .contains(where: { $0 === browserViewController }),
              !isCardTransitionActive,
              !chrome.isPlayerContentHiddenForCardTransition else {
            return
        }

        playerNavigationController.popToViewController(
            browserViewController,
            animated: true
        )
    }

    private func popExternallyToRoot() {
        guard isInstalled,
              playerNavigationController.transitionCoordinator == nil,
              !isCardTransitionActive,
              !chrome.isPlayerContentHiddenForCardTransition else {
            return
        }

        onDismiss()
    }

    @discardableResult
    private func handleNavigationBackAction() -> Bool {
        guard isInstalled,
              let topViewController = playerNavigationController.topViewController,
              isSessionViewController(topViewController) else {
            return false
        }

        guard playerNavigationController.transitionCoordinator == nil,
              !isCardTransitionActive,
              !chrome.isPlayerContentHiddenForCardTransition else {
            return true
        }
        guard topViewController === playerViewController else {
            onDismiss()
            return true
        }
        guard !isNavigationBackDisplayModeRequestPending else {
            return true
        }

        let state = chrome.currentLayoutInteractionState()
        guard state.canSwitchToCollectionBrowser,
              let pagePosition = state.pagePosition else {
            onDismiss()
            return true
        }

        guard !beginProgrammaticCardMinimize() else {
            return true
        }

        isNavigationBackDisplayModeRequestPending = true
        modeController.switchToCollectionBrowser(
            targetPagePosition: pagePosition
        ) { [weak self] _ in
            self?.isNavigationBackDisplayModeRequestPending = false
        }
        return true
    }

    private func setNavigationBarChromeVisible(_ isVisible: Bool, animated: Bool) {
        let animationDuration: TimeInterval?
        if animated {
            animationDuration = isVisible
                ? Self.navigationBarShowDuration
                : Self.navigationBarHideDuration
        } else {
            animationDuration = nil
        }

        playerNavigationController.setNavigationBarChromeVisible(
            isVisible,
            animationDuration: animationDuration
        )
    }

    private var shouldBlockNavigationBackGesture: Bool {
        guard isInstalled,
              let topViewController = playerNavigationController.topViewController,
              isSessionViewController(topViewController) else {
            return false
        }

        return playerNavigationController.transitionCoordinator != nil
            || topViewController === playerViewController
            || chrome.isPlayerContentHiddenForCardTransition
            || isCardTransitionActive
    }

    private func requireNavigationBackGesturesToTakePriority(
        over gestureRecognizer: UIGestureRecognizer
    ) {
        playerNavigationController.interactiveBackGestureRecognizers.forEach {
            navigationBackGestureRecognizer in
            gestureFailureRequirements.require(
                gestureRecognizer,
                toFail: navigationBackGestureRecognizer
            )
        }
    }

    private func configurePagingScrollViews() {
        configurePagerScrollViews()
        configureBrowserScrollViews()
    }

    private func configurePagerScrollViews() {
        gestureFailureRequirements.removeInvalidRequirements()
        playerViewController.view
            .allSubviews(ofType: UIScrollView.self)
            .forEach { scrollView in
                gestureFailureRequirements.require(
                    scrollView.panGestureRecognizer,
                    toFail: dismissPan
                )
                if let pinchGesture = scrollView.pinchGestureRecognizer {
                    gestureFailureRequirements.require(
                        pinchGesture,
                        toFail: cardMinimizePinch
                    )
                }
                scrollView.hideAutomaticScrollEdgeEffects()
            }
    }

    private func configureBrowserScrollViews() {
        guard let browserViewController else { return }

        gestureFailureRequirements.removeInvalidRequirements()
        browserViewController.view
            .allSubviews(ofType: UIScrollView.self)
            .forEach { scrollView in
                if scrollView is MobilePlayerCollectionBrowserCollectionView {
                    requireNavigationBackGesturesToTakePriority(
                        over: scrollView.panGestureRecognizer
                    )
                }
                scrollView.hideAutomaticScrollEdgeEffects()
            }
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            let location = gesture.location(in: view)
            let velocity = gesture.velocity(in: view)
            let hasPlayerDismissIntent = hasPlayerDismissIntent(location: location, velocity: velocity)
            let cardMinimizeAvailability = hasPlayerDismissIntent
                ? cardMinimizeAvailability(at: location)
                : .empty
            let shouldHideControls = chrome.showControls && hasControlsHideIntent(location: location, velocity: velocity)
            isDismissPanDrivingCardMinimize = false

            if let cardMinimizeState = cardMinimizeAvailability.animated {
                guard beginCardMinimizeFromDismissPan(state: cardMinimizeState) else { return }
            } else if let directCardMinimizeState = cardMinimizeAvailability.direct {
                guard beginDirectCardMinimizeFromDismissPan(state: directCardMinimizeState) else { return }
            }

            if !isDismissPanDrivingCardMinimize, shouldHideControls {
                chrome.setControlsVisible(false)
            }

        case .changed:
            guard isDismissPanDrivingCardMinimize else { return }
            applyCardMinimizePresentation(translation: translation)

        case .ended:
            guard isDismissPanDrivingCardMinimize else { return }
            isDismissPanDrivingCardMinimize = false
            finishCardMinimizeGesture(
                translation: translation,
                velocity: gesture.velocity(in: view)
            )

        case .cancelled, .failed:
            guard isDismissPanDrivingCardMinimize else { return }
            isDismissPanDrivingCardMinimize = false
            resetCardMinimizeTransform()

        default:
            break
        }
    }

    @objc private func handleControlsPan(_ gesture: UIPanGestureRecognizer) {
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
        switch gesture.state {
        case .began:
            isCardMinimizePinchDrivingCardMinimize = false
            cardMinimizePinchStartLocation = gesture.initialPinchLocation(in: view)

            let location = gesture.pinchLocation(in: view)
            let availability = cardMinimizeAvailability(at: location)
            if let state = availability.animated {
                guard beginCardMinimizePinchGesture(state: state) else {
                    resetCardMinimizePinchState()
                    return
                }

                applyCardMinimizePinchPresentation(gesture)
                return
            }

            guard let state = availability.direct,
                  beginDirectCardMinimizePinchGesture(state: state) else {
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

    @objc private func handlePinchRotation(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            if isCardMinimizePinchDrivingCardMinimize {
                cardMinimizePinchStartRotation = gesture.rotation
                cardMinimizePinchRotation = 0
            }

        case .changed:
            if isCardMinimizePinchDrivingCardMinimize {
                cardMinimizePinchRotation = gesture.rotation - cardMinimizePinchStartRotation
                scheduleCardMinimizePinchPresentationUpdate()
            }

        case .ended, .cancelled, .failed:
            if !isCardMinimizePinchDrivingCardMinimize {
                cardMinimizePinchRotation = 0
                cardMinimizePinchStartRotation = 0
            }

        default:
            break
        }
    }

    private var isCardMinimizeTransitionActive: Bool {
        activeCardMinimizeContext != nil
            || isDismissPanDrivingCardMinimize
            || isCardMinimizePinchDrivingCardMinimize
    }

    private var isCardTransitionActive: Bool {
        isCardMinimizeTransitionActive || activeCardExpandContext != nil
    }

    private func beginCardMinimizeFromDismissPan(state: MobilePlayerLayoutInteractionState) -> Bool {
        beginCardMinimizeTransition(state: state, isDrivenByDismissPan: true)
    }

    private func beginDirectCardMinimizeFromDismissPan(state: MobilePlayerLayoutInteractionState) -> Bool {
        beginDirectCardMinimizeTransition(state: state, isDrivenByDismissPan: true)
    }

    private func beginCardMinimizePinchGesture(state: MobilePlayerLayoutInteractionState) -> Bool {
        guard beginCardMinimizeTransition(state: state, isDrivenByDismissPan: false) else {
            return false
        }

        beginCardMinimizePinchDriving()
        return true
    }

    private func beginDirectCardMinimizePinchGesture(state: MobilePlayerLayoutInteractionState) -> Bool {
        guard beginDirectCardMinimizeTransition(state: state, isDrivenByDismissPan: false) else {
            return false
        }

        beginCardMinimizePinchDriving()
        return true
    }

    private func beginCardMinimizePinchDriving() {
        cardMinimizePinchStartRotation = currentPinchRotationGestureValue()
        cardMinimizePinchRotation = 0
        isCardMinimizePinchDrivingCardMinimize = true
    }

    private func beginProgrammaticCardMinimize() -> Bool {
        guard !isCardTransitionActive else {
            return true
        }

        let state = chrome.currentLayoutInteractionState()
        guard beginCardMinimizeTransition(
            state: state,
            isDrivenByDismissPan: false
        ) || beginDirectCardMinimizeTransition(
            state: state,
            isDrivenByDismissPan: false
        ) else {
            return false
        }

        completeCardMinimizeTransition()
        return true
    }

    private func beginProgrammaticCardExpand(
        selection: MobilePlayerBrowserTransitionSelection
    ) -> MobilePlayerBrowserExpandSelectionResult {
        guard !chrome.isPlayerContentZoomed else {
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
        view.layer.removeAllAnimations()

        guard let context = makeCardMinimizeTransitionContext(state: state) else {
            return false
        }

        return beginCardMinimizeTransition(
            context: context,
            isDrivenByDismissPan: isDrivenByDismissPan
        )
    }

    private func beginDirectCardMinimizeTransition(
        state: MobilePlayerLayoutInteractionState,
        isDrivenByDismissPan: Bool
    ) -> Bool {
        view.layer.removeAllAnimations()

        guard let context = makeDirectCardMinimizeTransitionContext(state: state) else {
            return false
        }

        return beginCardMinimizeTransition(
            context: context,
            isDrivenByDismissPan: isDrivenByDismissPan
        )
    }

    private func beginCardMinimizeTransition(
        context: CardMinimizeTransitionContext,
        isDrivenByDismissPan: Bool
    ) -> Bool {
        if !shouldShowNavigationBarChrome {
            playerNavigationController.finishNavigationBarChromeHideAnimation()
        }

        activeCardMinimizeContext = context
        isDismissPanDrivingCardMinimize = isDrivenByDismissPan
        isCardMinimizeAnimationComplete = false
        isCardMinimizeLayoutApplied = false
        playerNavigationController
            .setCollectionBrowserTransitionStatusBarVisible(true)
        chrome.setPlayerContentHiddenForCardTransition(true)
        setTopEdgeTintAlphaDirectly(1)
        return true
    }

    private func beginCardExpandTransition(
        selection: MobilePlayerBrowserTransitionSelection
    ) -> Bool {
        view.layer.removeAllAnimations()

        modeController.stagePagerViewForTransition()

        guard let context = makeCardExpandTransitionContext(selection: selection) else {
            modeController.unstagePagerViewIfNeeded()
            return false
        }

        activeCardExpandContext = context
        isCardExpandAnimationComplete = false
        isCardExpandLayoutApplied = false
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

        guard shouldCompleteCardMinimizeGesture(translation: translation, velocity: velocity) else {
            resetCardMinimizeTransform()
            return
        }

        completeCardMinimizeTransition()
    }

    private func shouldCompleteCardMinimizeGesture(
        translation: CGPoint,
        velocity: CGPoint
    ) -> Bool {
        let clampedY = max(0, translation.y)
        let projectedY = clampedY + max(velocity.y, 0) * MobilePlayerGestureTuning.dismissVelocityProjectionDuration
        let translationThreshold = max(
            MobilePlayerGestureTuning.cardMinimizeMinimumTranslation,
            view.bounds.height * MobilePlayerGestureTuning.cardMinimizeTranslationHeightRatio
        )
        return projectedY > translationThreshold
            || (velocity.y > MobilePlayerGestureTuning.cardMinimizeFastSwipeVelocity
                && clampedY > MobilePlayerGestureTuning.cardMinimizeMinimumFastSwipeTranslation)
    }

    private func completeCardMinimizeTransition() {
        guard let context = activeCardMinimizeContext else {
            cleanupCardMinimizeTransition(revealPlayer: true)
            return
        }
        let contextID = context.id
        var requestReturned = false
        var wasRejectedSynchronously = false

        modeController.switchToCollectionBrowser(
            targetPagePosition: context.sourcePagePosition
        ) { [weak self] didApply in
            guard let self,
                  self.activeCardMinimizeContext?.id == contextID else {
                return
            }
            guard didApply else {
                if requestReturned {
                    self.resetCardMinimizeTransform()
                } else {
                    wasRejectedSynchronously = true
                }
                return
            }

            self.isCardMinimizeLayoutApplied = true
            self.finishCardMinimizeTransitionIfReady()
        }
        requestReturned = true
        if wasRejectedSynchronously {
            resetCardMinimizeTransform()
            return
        }

        switch context.commitDestination {
        case .offscreen:
            completeOffscreenCardMinimizeTransition(context)
            return
        case .browserCell(let targetFrame):
            let foregroundView = context.foregroundView

            animateCardMinimizeTransition(
                context: context,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                foregroundView.transform = .identity
                foregroundView.bounds = CGRect(origin: .zero, size: targetFrame.size)
                foregroundView.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                if let zoomedForeground = context.zoomedForeground {
                    self.applyZoomedCardMinimizePresentation(
                        zoomedForeground,
                        frame: targetFrame
                    )
                }
                context.underlayView.setOtherCardsRevealProgress(1)
            }
            animateTopEdgeTint(to: 1)
        }
    }

    private func completeOffscreenCardMinimizeTransition(_ context: CardMinimizeTransitionContext) {
        let foregroundView = context.foregroundView
        let finalCenter = CGPoint(
            x: foregroundView.center.x,
            y: view.bounds.maxY + max(foregroundView.bounds.height, context.sourceFrame.height)
        )

        animateCardMinimizeTransition(
            context: context,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            foregroundView.center = finalCenter
            if let zoomedForeground = context.zoomedForeground {
                let targetFrame = CGRect(
                    x: finalCenter.x - context.sourceFrame.width / 2,
                    y: finalCenter.y - context.sourceFrame.height / 2,
                    width: context.sourceFrame.width,
                    height: context.sourceFrame.height
                )
                self.applyZoomedCardMinimizePresentation(
                    zoomedForeground,
                    frame: targetFrame
                )
            }
            context.underlayView.setOtherCardsRevealProgress(1)
        }
        animateTopEdgeTint(to: 1)
    }

    private func animateCardMinimizeTransition(
        context: CardMinimizeTransitionContext,
        options: UIView.AnimationOptions,
        animations: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: Self.cardMinimizeAnimationDuration,
            delay: 0,
            options: options,
            animations: animations,
            completion: { [weak self] _ in
                guard let self else { return }

                self.isCardMinimizeAnimationComplete = true
                self.finishCardMinimizeTransitionIfReady()
            }
        )

        guard let zoomedForeground = context.zoomedForeground,
              case .browserCell = context.commitDestination else {
            return
        }

        UIView.animate(
            withDuration: Self.cardMinimizeAnimationDuration * 0.4,
            delay: Self.cardMinimizeAnimationDuration * 0.55,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            context.foregroundView.alpha = 1
            zoomedForeground.view.alpha = 0
        }
    }

    private func finishCardMinimizeTransitionIfReady() {
        guard activeCardMinimizeContext != nil,
              isCardMinimizeAnimationComplete,
              isCardMinimizeLayoutApplied else {
            return
        }

        cleanupCardMinimizeTransition(revealPlayer: true)
    }

    private func completeCardExpandTransition() {
        guard let context = activeCardExpandContext else { return }
        let contextID = context.id
        var requestReturned = false
        var wasRejectedSynchronously = false

        modeController.switchToOnePerPage(
            targetPagePosition: context.targetPagePosition
        ) { [weak self] didApply in
            guard let self,
                  self.activeCardExpandContext?.id == contextID else {
                return
            }
            guard didApply else {
                if requestReturned {
                    self.resetCardExpandTransform()
                } else {
                    wasRejectedSynchronously = true
                }
                return
            }

            self.isCardExpandLayoutApplied = true
            self.finishCardExpandTransitionIfReady()
        }
        requestReturned = true
        if wasRejectedSynchronously {
            resetCardExpandTransform()
            return
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
        })
        animateTopEdgeTint(to: 0, delay: 0.12)
    }

    private func finishCardExpandTransitionIfReady() {
        guard activeCardExpandContext != nil,
              isCardExpandAnimationComplete,
              isCardExpandLayoutApplied else {
            return
        }

        cleanupCardExpandTransition(revealPlayer: true)
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
        setTopEdgeTintAlphaDirectly(1)
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

        guard shouldCompleteCardMinimizePinch(scale: scale, velocity: velocity) else {
            resetCardMinimizeTransform()
            return
        }

        completeCardMinimizeTransition()
    }

    private func shouldCompleteCardMinimizePinch(
        scale: CGFloat,
        velocity: CGFloat
    ) -> Bool {
        PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: scale,
            velocity: velocity
        )
    }

    private func cardMinimizePinchProgress(forScale scale: CGFloat) -> CGFloat {
        PlayerCardMinimizePinchPolicy.progress(forScale: scale)
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

        if context.zoomedForeground != nil,
           !chrome.isPlayerContentZoomed {
            crossfadeCardMinimizeTransitionToLivePager()
            return
        }

        let shouldRestoreZoomedForeground = context.zoomedForeground != nil
            && chrome.isPlayerContentZoomed

        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            context.foregroundView.transform = .identity
            context.foregroundView.bounds = CGRect(origin: .zero, size: context.sourceFrame.size)
            context.foregroundView.center = CGPoint(x: context.sourceFrame.midX, y: context.sourceFrame.midY)
            context.foregroundView.alpha = shouldRestoreZoomedForeground ? 0 : 1
            if let zoomedForeground = context.zoomedForeground {
                self.applyZoomedCardMinimizePresentation(
                    zoomedForeground,
                    frame: zoomedForeground.sourceFrame
                )
                zoomedForeground.view.alpha = shouldRestoreZoomedForeground ? 1 : 0
            }
            context.underlayView.setOtherCardsRevealProgress(0)
        }, completion: { [weak self] _ in
            self?.cleanupCardMinimizeTransition(
                revealPlayer: true,
                cancelPreparedBrowserSelection: true
            )
        })
        animateTopEdgeTint(to: 0, delay: Self.cardMinimizeAnimationDuration)
    }

    private func crossfadeCardMinimizeTransitionToLivePager() {
        if playerInteractionEnabledBeforeLivePagerFade == nil {
            playerInteractionEnabledBeforeLivePagerFade = view.isUserInteractionEnabled
        }
        view.isUserInteractionEnabled = false
        playerNavigationController
            .setCollectionBrowserTransitionStatusBarVisible(false)
        playerNavigationController.view.setNeedsLayout()
        playerNavigationController.view.layoutIfNeeded()
        revealPlayerAfterCardTransition()
        playerNavigationController.view.layoutIfNeeded()

        UIView.animate(
            withDuration: Self.cardMinimizeAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.cardTransitionCanvasView.alpha = 0
        } completion: { [weak self] _ in
            self?.cleanupCardMinimizeTransition(
                revealPlayer: false,
                cancelPreparedBrowserSelection: true
            )
        }
        animateTopEdgeTint(to: 0)
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
        animateTopEdgeTint(to: 1)
    }

    private func makeCardMinimizeTransitionContext(
        state: MobilePlayerLayoutInteractionState
    ) -> CardMinimizeTransitionContext? {
        guard state.canMinimizeToCollectionBrowser,
              let pagePosition = state.pagePosition else {
            return nil
        }
        let currentDescriptor = state.currentDescriptor

        guard let selection = chrome.prepareCollectionBrowserSelection(for: pagePosition) else {
            return nil
        }
        var shouldCancelPreparedSelection = true
        defer {
            if shouldCancelPreparedSelection {
                chrome.cancelPreparedCollectionBrowserSelection()
            }
        }

        let selectedSnapshot = selection.selectedSnapshot
        guard let targetFrame = browserItemFrameInOverlay(selectedSnapshot) else {
            return nil
        }

        let fallbackImageSize = currentDescriptor.map {
            cardTransitionFallbackImageSize(selectedDescriptor: $0)
        } ?? selectedSnapshot.fallbackImageSize.validOrDefault
        let sourceFrame = onePerPageCardFrame(
            for: currentDescriptor,
            fallbackImageSize: fallbackImageSize
        )
        guard !sourceFrame.isEmpty else {
            return nil
        }
        let usesCellHero = selectedSnapshot.hasLoadedImage
        let zoomedForeground = makeZoomedCardMinimizeForeground()
        guard !chrome.isPlayerContentZoomed || zoomedForeground != nil else {
            return nil
        }
        let foregroundView: UIView
        if zoomedForeground != nil, usesCellHero {
            foregroundView = makeBrowserCardTransitionForegroundView(
                selectedSnapshot,
                sourceFrame: sourceFrame
            )
        } else {
            foregroundView = makeCardTransitionForegroundView(
                sourceFrame: sourceFrame,
                descriptor: currentDescriptor
            )
        }

        var underlayItemSnapshots = selection.visibleNeighborSnapshots
        if !usesCellHero {
            underlayItemSnapshots.removeAll { $0.tokenIndex == selectedSnapshot.tokenIndex }
            underlayItemSnapshots.insert(selectedSnapshot, at: 0)
        }
        let underlayView = makeCardTransitionUnderlayView(
            itemSnapshots: underlayItemSnapshots,
            otherCardsRevealProgress: 0
        )
        installCardMinimizeForeground(
            foregroundView,
            zoomedForeground: zoomedForeground,
            above: underlayView
        )
        let targetScale = cardMinimizeTargetScale(
            sourceFrame: sourceFrame,
            targetFrame: usesCellHero ? targetFrame : nil
        )
        shouldCancelPreparedSelection = false

        return CardMinimizeTransitionContext(
            id: UUID(),
            sourcePagePosition: pagePosition,
            sourceFrame: sourceFrame,
            targetScale: targetScale,
            commitDestination: usesCellHero ? .browserCell(targetFrame) : .offscreen,
            foregroundView: foregroundView,
            zoomedForeground: zoomedForeground,
            underlayView: underlayView,
            hasPreparedBrowserSelection: true
        )
    }

    private func makeDirectCardMinimizeTransitionContext(
        state: MobilePlayerLayoutInteractionState
    ) -> CardMinimizeTransitionContext? {
        guard state.canSwitchDirectlyToCollectionBrowser,
              let pagePosition = state.pagePosition else {
            return nil
        }
        let currentDescriptor = state.currentDescriptor

        let preparedSelection = chrome.prepareCollectionBrowserSelection(for: pagePosition)
        var shouldCancelPreparedSelection = preparedSelection != nil
        defer {
            if shouldCancelPreparedSelection {
                chrome.cancelPreparedCollectionBrowserSelection()
            }
        }

        let fallbackImageSize = currentDescriptor.map {
            cardTransitionFallbackImageSize(selectedDescriptor: $0)
        } ?? preparedSelection?.selectedSnapshot.fallbackImageSize.validOrDefault
            ?? CGSize(width: 1, height: 1)
        let sourceFrame = onePerPageCardFrame(
            for: currentDescriptor,
            fallbackImageSize: fallbackImageSize
        )
        guard !sourceFrame.isEmpty else {
            return nil
        }

        let foregroundView = makeCardTransitionForegroundView(
            sourceFrame: sourceFrame,
            descriptor: currentDescriptor
        )
        let zoomedForeground = makeZoomedCardMinimizeForeground()
        guard !chrome.isPlayerContentZoomed || zoomedForeground != nil else {
            return nil
        }
        var underlayItemSnapshots = preparedSelection?.visibleNeighborSnapshots ?? []
        if let selectedSnapshot = preparedSelection?.selectedSnapshot {
            underlayItemSnapshots.removeAll { $0.tokenIndex == selectedSnapshot.tokenIndex }
            underlayItemSnapshots.insert(selectedSnapshot, at: 0)
        }
        let underlayView = makeCardTransitionUnderlayView(
            itemSnapshots: underlayItemSnapshots,
            otherCardsRevealProgress: 0
        )
        installCardMinimizeForeground(
            foregroundView,
            zoomedForeground: zoomedForeground,
            above: underlayView
        )
        shouldCancelPreparedSelection = false

        return CardMinimizeTransitionContext(
            id: UUID(),
            sourcePagePosition: pagePosition,
            sourceFrame: sourceFrame,
            targetScale: cardMinimizeTargetScale(sourceFrame: sourceFrame, targetFrame: nil),
            commitDestination: .offscreen,
            foregroundView: foregroundView,
            zoomedForeground: zoomedForeground,
            underlayView: underlayView,
            hasPreparedBrowserSelection: preparedSelection != nil
        )
    }

    private func installCardMinimizeForeground(
        _ foregroundView: UIView,
        zoomedForeground: ZoomedCardMinimizeForeground?,
        above underlayView: CardTransitionUnderlayView
    ) {
        cardTransitionCanvasView.insertSubview(foregroundView, aboveSubview: underlayView)
        guard let zoomedForeground else { return }

        foregroundView.alpha = 0
        cardTransitionCanvasView.insertSubview(
            zoomedForeground.view,
            aboveSubview: foregroundView
        )
    }

    private func makeCardExpandTransitionContext(
        selection: MobilePlayerBrowserTransitionSelection
    ) -> CardExpandTransitionContext? {
        let selectedSnapshot = selection.selectedSnapshot
        guard selectedSnapshot.hasLoadedImage else {
            return nil
        }
        guard let sourceFrame = browserItemFrameInOverlay(selectedSnapshot) else {
            return nil
        }

        let underlayView = makeCardTransitionUnderlayView(
            itemSnapshots: selection.visibleNeighborSnapshots,
            otherCardsRevealProgress: 1
        )

        let targetFrame = onePerPageCardFrame(
            for: selectedSnapshot.descriptor,
            fallbackImageSize: selectedSnapshot.fallbackImageSize.validOrDefault
        )
        guard !targetFrame.isEmpty else {
            underlayView.removeFromSuperview()
            updateCardTransitionCanvasVisibility()
            return nil
        }

        let foregroundView = makeBrowserCardTransitionForegroundView(
            selectedSnapshot,
            sourceFrame: sourceFrame
        )
        cardTransitionCanvasView.insertSubview(foregroundView, aboveSubview: underlayView)

        return CardExpandTransitionContext(
            id: UUID(),
            targetPagePosition: selectedSnapshot.pagePosition,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            foregroundView: foregroundView,
            underlayView: underlayView
        )
    }

    private func makeCardTransitionUnderlayView(
        itemSnapshots: [MobilePlayerBrowserItemSnapshot],
        otherCardsRevealProgress: CGFloat
    ) -> CardTransitionUnderlayView {
        setCardTransitionCanvasActive(true)
        playerNavigationController.view.layoutIfNeeded()
        playerNavigationController.assertTopEdgeTintPlacement()
        let underlayView = CardTransitionUnderlayView(itemSnapshots: itemSnapshots)
        underlayView.frame = cardTransitionCanvasView.bounds
        underlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cardTransitionCanvasView.addSubview(underlayView)
        underlayView.setOtherCardsRevealProgress(otherCardsRevealProgress)
        underlayView.setNeedsLayout()
        underlayView.layoutIfNeeded()
        return underlayView
    }

    private func makeCardTransitionForegroundView(
        sourceFrame: CGRect,
        descriptor: DownloadableMediaDescriptor?
    ) -> UIView {
        if let descriptor,
           (descriptor.usesNativeMetalCardPresentation || descriptor.isCollectionBrowserImage),
           let snapshot = makeCardTransitionSnapshotView(sourceFrame: sourceFrame) {
            return snapshot
        }

        if let descriptor,
           let image = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            let imageView = NativeMetalCardCornerMaskedImageView(frame: sourceFrame)
            imageView.makeBackgroundTransparent()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.image = image
            imageView.usesNativeMetalCardCornerMask = descriptor.usesNativeMetalCardPresentation
            return imageView
        }

        if let snapshot = makeCardTransitionSnapshotView(sourceFrame: sourceFrame) {
            return snapshot
        }

        let placeholderView = UIView(frame: sourceFrame)
        placeholderView.backgroundColor = MobilePlayerBackgroundColor.defaultColor
        placeholderView.clipsToBounds = true
        return placeholderView
    }

    private func makeBrowserCardTransitionForegroundView(
        _ itemSnapshot: MobilePlayerBrowserItemSnapshot,
        sourceFrame: CGRect
    ) -> UIView {
        let foregroundView = itemSnapshot.snapshotView
        foregroundView.removeFromSuperview()
        foregroundView.layer.removeAllAnimations()
        foregroundView.transform = .identity
        foregroundView.frame = sourceFrame
        foregroundView.alpha = 1
        foregroundView.isHidden = false
        foregroundView.isUserInteractionEnabled = false
        return foregroundView
    }

    private func makeZoomedCardMinimizeForeground() -> ZoomedCardMinimizeForeground? {
        guard chrome.isPlayerContentZoomed else { return nil }

        let sourceFrame = view.convert(view.bounds, to: cardTransitionCanvasView)
        guard !sourceFrame.isEmpty,
              let snapshot = chrome.makeOnePerPageTransitionSnapshot(
                from: view.bounds,
                in: view
              ) else {
            return nil
        }

        let containerView = UIView(frame: sourceFrame)
        containerView.backgroundColor = chrome.playerBackgroundColor
        containerView.isOpaque = true
        containerView.clipsToBounds = true
        containerView.isUserInteractionEnabled = false

        snapshot.frame = containerView.bounds
        snapshot.isUserInteractionEnabled = false
        containerView.addSubview(snapshot)
        return ZoomedCardMinimizeForeground(
            view: containerView,
            sourceFrame: sourceFrame
        )
    }

    private func applyZoomedCardMinimizePresentation(
        _ foreground: ZoomedCardMinimizeForeground,
        frame: CGRect
    ) {
        let sourceSize = foreground.sourceFrame.size
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0,
              frame.width > 0,
              frame.height > 0 else {
            return
        }

        foreground.view.bounds = CGRect(origin: .zero, size: sourceSize)
        foreground.view.center = CGPoint(x: frame.midX, y: frame.midY)

        let scale = min(
            frame.width / sourceSize.width,
            frame.height / sourceSize.height
        )
        foreground.view.transform = CGAffineTransform(
            scaleX: scale,
            y: scale
        )
    }

    private func makeCardTransitionSnapshotView(sourceFrame: CGRect) -> UIView? {
        let sourceFrameInPlayer = cardTransitionCanvasView.convert(sourceFrame, to: view)
        let snapshot = chrome.makeOnePerPageTransitionSnapshot(
            from: sourceFrameInPlayer,
            in: view
        ) ?? view.resizableSnapshotView(
            from: sourceFrameInPlayer,
            afterScreenUpdates: false,
            withCapInsets: .zero
        )
        guard let snapshot else {
            return nil
        }
        snapshot.frame = sourceFrame
        snapshot.clipsToBounds = true
        return snapshot
    }

    private func cardTransitionFallbackImageSize(
        selectedDescriptor: DownloadableMediaDescriptor
    ) -> CGSize {
        if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: selectedDescriptor) {
            return image.size.validOrDefault
        }

        return PlayerCollectionBrowserSupport.fallbackImageSize(for: selectedDescriptor)
    }

    private func onePerPageCardFrame(
        for descriptor: DownloadableMediaDescriptor?,
        fallbackImageSize: CGSize
    ) -> CGRect {
        let playerBounds = view.bounds
        if descriptor?.usesNativeMetalCardPresentation == true {
            let nativeCardFrame = NativeMetalCardLayout.cardContentRect(in: playerBounds.size)
            let clippedNativeCardFrame = nativeCardFrame.intersection(playerBounds)
            guard !clippedNativeCardFrame.isNull, !clippedNativeCardFrame.isEmpty else {
                return view.convert(playerBounds, to: cardTransitionCanvasView)
            }
            return view.convert(clippedNativeCardFrame, to: cardTransitionCanvasView)
        }

        let frameInPlayer = PlayerAspectFitLayout.centeredRect(
            for: fallbackImageSize.validOrDefault,
            in: playerBounds
        )
        let clippedFrame = frameInPlayer.intersection(playerBounds)
        guard !clippedFrame.isNull, !clippedFrame.isEmpty else {
            return view.convert(playerBounds, to: cardTransitionCanvasView)
        }
        return view.convert(clippedFrame, to: cardTransitionCanvasView)
    }

    private func browserItemFrameInOverlay(_ snapshot: MobilePlayerBrowserItemSnapshot) -> CGRect? {
        let frame = cardTransitionCanvasView.convert(snapshot.frameInWindow, from: nil)
        guard !frame.isNull,
              !frame.isInfinite,
              !frame.isEmpty,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            return nil
        }

        return frame
    }

    private func cardMinimizeTargetScale(sourceFrame: CGRect, targetFrame: CGRect?) -> CGFloat {
        cardTransitionTargetScale(sourceFrame: sourceFrame, targetFrame: targetFrame, fallback: 0.5)
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

    private func cardTransitionDragOffset(
        translation: CGPoint,
        easedProgress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: translation.x * (1 - Self.cardTransitionHorizontalDragDamping * easedProgress),
            y: translation.y * (1 - Self.cardTransitionVerticalDragDamping * easedProgress)
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

    private func cleanupCardMinimizeTransition(
        revealPlayer: Bool,
        cancelPreparedBrowserSelection: Bool = false
    ) {
        cardTransitionCanvasView.layer.removeAllAnimations()
        cardTransitionCanvasView.alpha = 1

        let context = activeCardMinimizeContext
        activeCardMinimizeContext = nil
        isDismissPanDrivingCardMinimize = false
        isCardMinimizeAnimationComplete = false
        isCardMinimizeLayoutApplied = false
        resetCardMinimizePinchState()
        playerNavigationController
            .setCollectionBrowserTransitionStatusBarVisible(false)

        if cancelPreparedBrowserSelection,
           context?.hasPreparedBrowserSelection == true {
            chrome.cancelPreparedCollectionBrowserSelection()
        }

        if revealPlayer {
            revealPlayerAfterCardTransition()
        }

        context?.foregroundView.removeFromSuperview()
        context?.zoomedForeground?.view.removeFromSuperview()
        context?.underlayView.removeFromSuperview()
        updateCardTransitionCanvasVisibility()

        if let wasInteractionEnabled = playerInteractionEnabledBeforeLivePagerFade {
            playerInteractionEnabledBeforeLivePagerFade = nil
            view.isUserInteractionEnabled = wasInteractionEnabled
        }
    }

    private func cleanupCardExpandTransition(revealPlayer: Bool) {
        let context = activeCardExpandContext
        activeCardExpandContext = nil
        isCardExpandAnimationComplete = false
        isCardExpandLayoutApplied = false
        modeController.unstagePagerViewIfNeeded()

        if revealPlayer {
            revealPlayerAfterCardTransition()
        }

        context?.foregroundView.removeFromSuperview()
        context?.underlayView.removeFromSuperview()
        updateCardTransitionCanvasVisibility()
    }

    private func revealPlayerAfterCardTransition() {
        chrome.setPlayerContentHiddenForCardTransition(false)
        view.alpha = 1
        view.transform = .identity
    }

    private func updateCardTransitionCanvasVisibility() {
        setCardTransitionCanvasActive(
            activeCardMinimizeContext != nil || activeCardExpandContext != nil
        )
    }

    private func setCardTransitionCanvasActive(_ isActive: Bool) {
        cardTransitionCanvasView.isHidden = !isActive
    }

    private func easeOutQuadratic(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return 1 - pow(1 - clampedProgress, 2)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === navigationBarTap {
            guard !isCardTransitionActive,
                  !chrome.isCollectionBrowserActive else {
                return false
            }

            return chrome.showControls
        }

        if gestureRecognizer === controlsPan {
            guard !isCardTransitionActive,
                  !chrome.isCollectionBrowserActive else {
                return false
            }

            let location = controlsPan.location(in: view)
            guard !hasZoomedPlayerContent(at: location) else {
                return false
            }

            let velocity = controlsPan.velocity(in: view)
            return hasControlsRevealIntent(location: location, velocity: velocity)
        }

        if gestureRecognizer === cardMinimizePinch {
            return canBeginCardMinimizePinch()
        }

        if gestureRecognizer === pinchRotation {
            return canBeginPinchRotation()
        }

        guard gestureRecognizer === dismissPan else {
            return true
        }
        guard playerNavigationController.topViewController === playerViewController,
              playerNavigationController.transitionCoordinator == nil,
              !isCardTransitionActive,
              !chrome.isCollectionBrowserActive else {
            return false
        }

        let location = dismissPan.location(in: view)
        let velocity = dismissPan.velocity(in: view)

        guard !hasZoomedPlayerContent(at: location) else {
            return false
        }

        let canMinimizeToCollectionBrowser = hasPlayerDismissIntent(
            location: location,
            velocity: velocity
        ) && cardMinimizeAvailability(at: location).canMinimize

        return canMinimizeToCollectionBrowser
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
        canBeginCardMinimizeInteraction(location: cardMinimizePinch.pinchLocation(in: view))
    }

    private func canBeginPinchRotation() -> Bool {
        if isCardMinimizePinchDrivingCardMinimize {
            return true
        }

        let location = pinchRotation.location(in: view)
        guard cardMinimizePinch.isTrackingPinch else {
            return false
        }

        return canBeginCardMinimizeInteraction(location: location)
    }

    private func canBeginCardMinimizeInteraction(location: CGPoint) -> Bool {
        guard !isCardTransitionActive else {
            return false
        }

        return cardMinimizeAvailability(at: location).canMinimize
    }

    private func hasZoomedPlayerContent(at location: CGPoint) -> Bool {
        chrome.isPlayerContentZoomed && view.bounds.contains(location)
    }

    private func hasPlayerDismissIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        let bounds = view.bounds

        return bounds.contains(location)
            && velocity.y > MobilePlayerGestureTuning.dismissInitialVelocity
            && velocity.y > abs(velocity.x) * MobilePlayerGestureTuning.dismissVerticalIntentRatio
    }

    private struct CardMinimizeAvailability {
        let animated: MobilePlayerLayoutInteractionState?
        let direct: MobilePlayerLayoutInteractionState?

        static let empty = CardMinimizeAvailability(animated: nil, direct: nil)

        var canMinimize: Bool {
            animated != nil || direct != nil
        }
    }

    private func cardMinimizeAvailability(at location: CGPoint) -> CardMinimizeAvailability {
        guard view.bounds.contains(location),
              !isCardTransitionActive,
              !chrome.isPlayerContentZoomed else {
            return .empty
        }

        let state = chrome.currentLayoutInteractionState()
        return CardMinimizeAvailability(
            animated: state.canMinimizeToCollectionBrowser ? state : nil,
            direct: state.canSwitchDirectlyToCollectionBrowser ? state : nil
        )
    }

    private func hasControlsRevealIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        view.bounds.contains(location)
            && velocity.y < -MobilePlayerGestureTuning.controlsRevealVelocity
            && abs(velocity.y) > abs(velocity.x) * MobilePlayerGestureTuning.controlsRevealVerticalIntentRatio
    }

    private func revealControlsIfAllowed(for gesture: UIPanGestureRecognizer) {
        guard !chrome.isCollectionBrowserActive,
              !didControlsPanConflictWithHorizontalScroll else {
            return
        }

        let translation = gesture.translation(in: view)
        guard hasControlsRevealTranslation(translation) else { return }

        chrome.setControlsVisible(true)
    }

    private func hasControlsRevealTranslation(_ translation: CGPoint) -> Bool {
        translation.y < -MobilePlayerGestureTuning.controlsRevealMinimumTranslation
            && abs(translation.y) > abs(translation.x) * MobilePlayerGestureTuning.controlsRevealVerticalIntentRatio
    }

    private func isHorizontalPlayerScrollActive() -> Bool {
        playerViewController.view
            .allSubviews(ofType: UIScrollView.self)
            .contains { scrollView in
                let panGesture = scrollView.panGestureRecognizer
                guard panGesture.state == .began || panGesture.state == .changed else { return false }

                let translation = panGesture.translation(in: view)
                return abs(translation.x) > MobilePlayerGestureTuning.controlsRevealHorizontalScrollTolerance
            }
    }

    private func hasControlsHideIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        view.bounds.contains(location)
            && velocity.y > 0
            && velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if isPinchAndRotationPair(gestureRecognizer, otherGestureRecognizer) {
            return true
        }

        if gestureRecognizer === pinchRotation {
            return isPlayerScrollViewPinchGesture(otherGestureRecognizer)
        }
        if otherGestureRecognizer === pinchRotation {
            return isPlayerScrollViewPinchGesture(gestureRecognizer)
        }

        if gestureRecognizer === navigationBarTap || otherGestureRecognizer === navigationBarTap {
            return false
        }

        return gestureRecognizer === controlsPan || otherGestureRecognizer === controlsPan
    }

    private func isPinchAndRotationPair(
        _ gestureRecognizer: UIGestureRecognizer,
        _ otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === pinchRotation && isRotationEnabledPinch(otherGestureRecognizer))
            || (otherGestureRecognizer === pinchRotation && isRotationEnabledPinch(gestureRecognizer))
    }

    private func isRotationEnabledPinch(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === cardMinimizePinch
    }

    private func currentPinchRotationGestureValue() -> CGFloat {
        switch pinchRotation.state {
        case .began, .changed:
            return pinchRotation.rotation
        default:
            return 0
        }
    }

    private func isPlayerScrollViewPinchGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureFailureRequirements.contains(
            gestureRecognizer,
            requiringFailureOf: cardMinimizePinch
        )
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

private let searchResultCoverThumbnailSize: CGFloat = 44
private let searchResultCoverThumbnailCornerRadius: CGFloat = 10

private enum MobileCollectionSearchIndex {
    private struct Entry {
        let item: MobileCollectionItem
        let haystack: String
    }

    private static let entries: [Entry] = MobileCollectionCatalog.allItems.map { item in
        let artists = SuggestedItemsService.artists(forCollectionId: item.id)
        let components = [item.name]
            + artists.map(\.name)
            + artists.flatMap { $0.links.map(\.title) }
        return Entry(item: item, haystack: components.joined(separator: " "))
    }

    static func matches(query: String) -> [MobileCollectionItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return entries.map(\.item) }
        return entries
            .filter { $0.haystack.localizedStandardContains(trimmedQuery) }
            .map(\.item)
    }
}

private struct MobileCollectionsSearchBar: View {
    @Binding var query: String
    let isFocusSuspended: Bool

    var body: some View {
        HStack(spacing: 6) {
            Images.search
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            MobileSearchTextField(text: $query, placeholder: Strings.search, isFocusSuspended: isFocusSuspended)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Images.clearText
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            CapsuleButtonBackground()
        }
        .clipShape(Capsule())
        .frame(maxWidth: .infinity)
    }
}

private struct MobileSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocusSuspended: Bool

    func makeUIView(context: Context) -> AutoFocusTextField {
        let textField = AutoFocusTextField()
        textField.delegate = context.coordinator
        textField.font = .preferredFont(forTextStyle: .subheadline)
        textField.textColor = .white
        textField.tintColor = .white
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        )
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.returnKeyType = .search
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.isFocusSuspended = isFocusSuspended
        return textField
    }

    func updateUIView(_ textField: AutoFocusTextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        textField.isFocusSuspended = isFocusSuspended
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }

    final class AutoFocusTextField: UITextField {
        var isFocusSuspended = false {
            didSet {
                guard window != nil else { return }
                if isFocusSuspended {
                    resignFirstResponder()
                } else if oldValue {
                    scheduleAutoFocus()
                }
            }
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.layoutFittingExpandedSize.width, height: super.intrinsicContentSize.height)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !isFocusSuspended else { return }
            scheduleAutoFocus()
        }

        private func scheduleAutoFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, !self.isFocusSuspended else { return }
                self.becomeFirstResponder()
            }
        }
    }
}

private struct MobileCollectionsSearchResultsView: View {
    let query: String
    let onSelect: (MobileCollectionItem) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            let results = MobileCollectionSearchIndex.matches(query: query)
            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            resultRow(for: item)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private func resultRow(for item: MobileCollectionItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 12) {
                CollectionCoverThumbnail(
                    assetName: item.coverAssetName,
                    size: searchResultCoverThumbnailSize,
                    cornerRadius: searchResultCoverThumbnailCornerRadius
                )
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text(Strings.nothingFound)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Button {
                UIApplication.shared.open(URL.mail)
            } label: {
                Text(Strings.sendFeedback)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        CapsuleButtonBackground(isInteractive: true)
                    }
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
