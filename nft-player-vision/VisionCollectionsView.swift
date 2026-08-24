// ∅ 2026 lil org

import SwiftUI

private let visionCollectionsMinimumWindowWidth: CGFloat = 720
private let visionCollectionsMinimumWindowHeight: CGFloat = 540
private let visionCollectionsContinueViewingMinWidth: CGFloat = 360
private let visionCollectionsContinueViewingMaxWidth: CGFloat = 520
private let visionCollectionsGridMinimumItemWidth: CGFloat = 150
private let visionCollectionsGridColumnSpacing: CGFloat = 0
private let visionCollectionsGridRowSpacing: CGFloat = 0
private let visionCollectionsTopOrnamentWidth: CGFloat = (
    visionCollectionsMinimumWindowWidth
    - VisionOrnamentMetrics.horizontalPadding * 2
    - VisionOrnamentMetrics.trailingControlReservedWidth
)

private enum VisionImmersiveSpaceState {
    case closed
    case opening
    case open

    var isOpening: Bool {
        self == .opening
    }
}

struct VisionCollectionsView: View {
    
    private let collectionItems: [CollectionCatalogItem]
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(VisionImmersiveModeModel.self) private var immersiveMode
    private let widgetLaunchPresentationState: WidgetLaunchPresentationState
    @State private var gridPassCount: Int
    @State private var gridScrollMemoryTracker: CollectionsGridScrollMemoryTracker
    @State private var hasRestoredInitialGridScrollPosition: Bool
    @State private var playerConfig: VisionPlayerConfig?
    @State private var immersiveSpaceState = VisionImmersiveSpaceState.closed
    @State private var immersiveModeRequestID = 0
    @State private var shouldEnableImmersiveModeWhenReady = false
    @State private var playerPresentationGate = PlayerPresentationRequestGate()
    @State private var hasLoadedViewingProgress = false
    @State private var viewingProgressRefreshID = 0
    @State private var shouldPrewarmAfterViewingProgressRefresh = true

    @State private var viewingProgressSnapshot = PlayerViewingProgressSnapshot.empty

    init(
        collectionItems: [CollectionCatalogItem] = CollectionCatalog.allItems,
        widgetLaunchPresentationState: WidgetLaunchPresentationState = .shared
    ) {
        self.collectionItems = collectionItems
        self.widgetLaunchPresentationState = widgetLaunchPresentationState
        let gridScrollMemoryTracker = CollectionsGridScrollMemoryTracker(items: collectionItems)
        _gridPassCount = State(initialValue: gridScrollMemoryTracker.initialGridPassCount)
        _gridScrollMemoryTracker = State(initialValue: gridScrollMemoryTracker)
        _hasRestoredInitialGridScrollPosition = State(
            initialValue: gridScrollMemoryTracker.initialDisplayedIndex == nil
        )
    }

    private var viewingProgressByCollectionId: [String: Int] {
        viewingProgressSnapshot.percentagesByCollectionId
    }

    private var viewedToEndCollectionIds: Set<String> {
        viewingProgressSnapshot.viewedToEndCollectionIds
    }

    private var continueViewingProgress: PlayerViewingProgress? {
        viewingProgressSnapshot.firstVisibleContinueViewingProgress { collectionId in
            collectionItems.contains { $0.id == collectionId }
        }
    }

    var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    createGrid()
                        .frame(maxWidth: .infinity)
                        .collectionsGridScrollMemoryContent()
                }
                .collectionsGridScrollMemoryTracking(
                    tracker: gridScrollMemoryTracker,
                    minimumItemWidth: visionCollectionsGridMinimumItemWidth,
                    columnSpacing: visionCollectionsGridColumnSpacing,
                    rowSpacing: visionCollectionsGridRowSpacing,
                    visibleItemCount: visibleItemCount
                )
                .opacity(
                    hasRestoredInitialGridScrollPosition && hasLoadedViewingProgress
                        ? 1
                        : 0
                )
                .allowsHitTesting(
                    hasRestoredInitialGridScrollPosition && hasLoadedViewingProgress
                )
                .collectionsGridScrollMemoryRestoration(
                    using: scrollProxy,
                    tracker: gridScrollMemoryTracker,
                    hasRestored: $hasRestoredInitialGridScrollPosition
                )
            }

            if let playerConfig {
                VisionPlayerView(config: playerConfig) {
                    dismissPlayer(playerConfig)
                }
                .ignoresSafeArea()
                .zIndex(1)
                .id(playerConfig.id)
                .transition(.opacity)
            }
        }
        .frame(
            minWidth: visionCollectionsMinimumWindowWidth,
            minHeight: visionCollectionsMinimumWindowHeight
        )
        .ornament(
            visibility: playerConfig == nil ? .visible : .hidden,
            attachmentAnchor: .scene(.top),
            contentAlignment: .bottom
        ) {
            VisionCollectionsTopOrnament(
                continueViewingProgress: widgetLaunchPresentationState.isPreparingWidgetPlayerPresentation
                    ? nil
                    : continueViewingProgress,
                onContinueViewing: { progress in resumeViewing(progress) },
                onShowRandomPlayer: showRandomPlayer
            )
            .padding(.leading, VisionOrnamentMetrics.horizontalPadding)
            .padding(
                .trailing,
                VisionOrnamentMetrics.horizontalPadding + VisionOrnamentMetrics.trailingControlReservedWidth
            )
            .padding(.bottom, VisionOrnamentMetrics.bottomPadding)
        }
        .ornament(
            visibility: .visible,
            attachmentAnchor: .scene(.topTrailing),
            contentAlignment: .bottomTrailing
        ) {
            VisionImmersiveModeButton(
                isEnabled: immersiveMode.isEnabled,
                isOpening: immersiveSpaceState.isOpening,
                action: toggleImmersiveMode
            )
            .padding(.trailing, VisionOrnamentMetrics.horizontalPadding)
            .padding(.bottom, VisionOrnamentMetrics.bottomPadding)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            requestViewingProgressRefresh(prewarm: true)
        }
        .onChange(of: immersiveMode.isSpaceVisible) { _, _ in
            reconcileImmersiveSpaceVisibility()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            guard playerConfig == nil else { return }
            requestViewingProgressRefresh()
        }
        .task(id: viewingProgressRefreshID) {
            await performViewingProgressRefresh(id: viewingProgressRefreshID)
        }
        .collectionsGridScrollMemoryLifecycleFlush(tracker: gridScrollMemoryTracker)
        .onDisappear {
            cancelPendingPlayerPresentation()
            dismissImmersiveSpaceIfNeeded()
        }
        .onOpenURL(perform: requestWidgetURL)
    }
    
    private func createGrid() -> some View {
        let gridLayout = [
            GridItem(
                .adaptive(minimum: visionCollectionsGridMinimumItemWidth),
                spacing: visionCollectionsGridColumnSpacing
            )
        ]
        let grid = LazyVGrid(columns: gridLayout, alignment: .leading, spacing: visionCollectionsGridRowSpacing) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let sourceIndex = sourceIndex(for: index)
                let item = collectionItems[sourceIndex]
                Button(action: {
                    didSelectCollectionItem(item)
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(item.coverAssetName)
                            .resizable()
                            .scaledToFill()
                            .clipped()
                            .aspectRatio(1, contentMode: .fill)
                            .contentShape(Rectangle())
                        VStack {
                            Spacer()
                            gridItemText(item.name) {
                                didSelectCollectionItem(item)
                            }
                        }
                        gridProgressBadge(for: item)
                            .padding(6)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .contextMenu { collectionItemContextMenu(item: item) }
                .collectionsGridMemoryItem(
                    displayedIndex: index,
                    tracker: gridScrollMemoryTracker
                )
                .onAppear {
                    appendNextPassIfNeeded(for: index)
                }
            }
        }
        return grid
    }

    private var visibleItemCount: Int {
        collectionItems.count * gridPassCount
    }

    private func sourceIndex(for displayedIndex: Int) -> Int {
        CollectionsGridLoop.sourceIndex(
            forDisplayedIndex: displayedIndex,
            itemCount: collectionItems.count
        )
    }

    private func appendNextPassIfNeeded(for index: Int) {
        guard CollectionsGridLoop.shouldAppendNextPass(
            forDisplayedIndex: index,
            itemCount: collectionItems.count,
            visibleItemCount: visibleItemCount
        ) else { return }
        gridPassCount += 1
    }
    
    private func gridItemText(_ text: String, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.system(size: 15, weight: .regular)).lineLimit(2)
                .foregroundColor(.white)
                .padding(.horizontal, 1)
                .background(Color.black.opacity(0.7)).cornerRadius(3)
                .multilineTextAlignment(.leading)
                .padding(.leading, 4).padding(.bottom, 3).onTapGesture {
                    onTap()
                }
            Spacer()
        }
    }

    @ViewBuilder
    private func gridProgressBadge(for item: CollectionCatalogItem) -> some View {
        if viewedToEndCollectionIds.contains(item.id) {
            VisionGridProgressBadge {
                Images.checkmark
                    .font(.caption.weight(.semibold))
            }
        } else if let progressPercent = viewingProgressByCollectionId[item.id], progressPercent > 0 {
            VisionGridProgressBadge {
                Text(Strings.percent(progressPercent))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }
    
    private func collectionItemContextMenu(item: CollectionCatalogItem) -> some View {
        Group {
            Text(item.name)
            Divider()
            Button(Strings.play, action: {
                didSelectCollectionItem(item)
            })
        }
    }
    
    private func didSelectCollectionItem(_ item: CollectionCatalogItem) {
        openCollection(collectionId: item.id)
    }

    private func showRandomPlayer() {
        let request = playerPresentationGate.begin()
        Task {
            await PlayerPersistenceUpdates.flush()
            guard playerPresentationGate.isPending(request) else { return }
            guard let item = await randomCollectionItemPreferringUnfinishedCollections() else { return }
            guard playerPresentationGate.isPending(request) else { return }
            let progress = await PlayerViewingProgressStore.shared.progress(collectionId: item.id)
            guard playerPresentationGate.isPending(request) else { return }
            let initialTokenId = progress?.isComplete == false ? progress?.tokenId : nil
            let initialTokenIndex = progress?.isComplete == false ? progress?.tokenIndex : nil

            await openPlayer(
                initialItemId: item.id,
                initialTokenId: initialTokenId,
                initialTokenIndex: initialTokenIndex,
                continueViewingCollectionId: item.id,
                request: request
            )
        }
    }

    private func dismissPlayer(_ config: VisionPlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        cancelPendingPlayerPresentation()
        playerConfig = nil
        requestViewingProgressRefresh()
    }

    private func toggleImmersiveMode() {
        if immersiveMode.isEnabled {
            immersiveMode.isEnabled = false
        } else {
            enableImmersiveMode()
        }
    }

    private func enableImmersiveMode() {
        if immersiveMode.isSpaceVisible {
            immersiveSpaceState = .open
            immersiveMode.isEnabled = true
            shouldEnableImmersiveModeWhenReady = false
        } else if immersiveSpaceState == .opening {
            shouldEnableImmersiveModeWhenReady = true
        } else {
            prepareImmersiveSpaceIfNeeded(shouldEnableWhenReady: true)
        }
    }

    private func prepareImmersiveSpaceIfNeeded(shouldEnableWhenReady: Bool = false) {
        if shouldEnableWhenReady {
            shouldEnableImmersiveModeWhenReady = true
        }

        if immersiveMode.isSpaceVisible {
            immersiveSpaceState = .open
            if shouldEnableImmersiveModeWhenReady {
                immersiveMode.isEnabled = true
                shouldEnableImmersiveModeWhenReady = false
            }
            return
        }

        guard immersiveSpaceState != .opening else { return }

        immersiveModeRequestID += 1
        let requestID = immersiveModeRequestID
        immersiveSpaceState = .opening

        Task { @MainActor in
            await finishOpeningImmersiveSpace(requestID: requestID)
        }
    }

    private func finishOpeningImmersiveSpace(requestID: Int) async {
        let result = await openImmersiveSpace(id: WindowId.blackImmersiveBackdrop)

        guard requestID == immersiveModeRequestID else {
            if case .opened = result {
                await dismissImmersiveSpace()
            }
            return
        }

        switch result {
        case .opened:
            immersiveSpaceState = .open
            if shouldEnableImmersiveModeWhenReady {
                immersiveMode.isEnabled = true
                shouldEnableImmersiveModeWhenReady = false
            }
        case .userCancelled, .error:
            immersiveSpaceState = .closed
            immersiveMode.isEnabled = false
            shouldEnableImmersiveModeWhenReady = false
        @unknown default:
            immersiveSpaceState = .closed
            immersiveMode.isEnabled = false
            shouldEnableImmersiveModeWhenReady = false
        }
    }

    private func reconcileImmersiveSpaceVisibility() {
        if immersiveMode.isSpaceVisible {
            immersiveSpaceState = .open
            if shouldEnableImmersiveModeWhenReady {
                immersiveMode.isEnabled = true
                shouldEnableImmersiveModeWhenReady = false
            }
        } else if immersiveSpaceState != .closed {
            immersiveSpaceState = .closed
            shouldEnableImmersiveModeWhenReady = false
        }
    }

    private func dismissImmersiveSpaceIfNeeded() {
        guard immersiveSpaceState != .closed || immersiveMode.isEnabled || immersiveMode.isSpaceVisible else { return }

        immersiveModeRequestID += 1
        immersiveMode.isEnabled = false
        shouldEnableImmersiveModeWhenReady = false

        let shouldDismissVisibleSpace = immersiveMode.isSpaceVisible
        immersiveSpaceState = .closed

        guard shouldDismissVisibleSpace else { return }
        Task { @MainActor in
            await dismissImmersiveSpace()
        }
    }

    private func schedulePlayerPrewarm() {
        VisionPlayerPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: likelyInitialCollectionIds()
        )
    }

    private func likelyInitialCollectionIds() -> [String] {
        gridScrollMemoryTracker.initialCollectionIds(limit: 2)
    }

    private func openCollection(collectionId: String) {
        guard isVisibleCollection(collectionId) else { return }

        let request = playerPresentationGate.begin()
        Task {
            await openCollection(
                collectionId: collectionId,
                request: request
            )
        }
    }

    private func openCollection(
        collectionId: String,
        request: PlayerPresentationRequestGate.Request
    ) async {
        guard playerPresentationGate.isPending(request) else { return }
        guard isVisibleCollection(collectionId) else { return }

        await PlayerPersistenceUpdates.flush()
        guard playerPresentationGate.isPending(request) else { return }
        if let progress = await PlayerViewingProgressStore.shared.progress(collectionId: collectionId) {
            guard playerPresentationGate.isPending(request) else { return }
            await resumeViewing(progress, request: request)
            return
        }

        guard playerPresentationGate.isPending(request) else { return }
        await openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            request: request
        )
    }

    private func resumeViewing(_ progress: PlayerViewingProgress) {
        let request = playerPresentationGate.begin()
        Task {
            await openCollection(
                collectionId: progress.collectionId,
                request: request
            )
        }
    }

    private func resumeViewing(
        _ progress: PlayerViewingProgress,
        request: PlayerPresentationRequestGate.Request
    ) async {
        guard playerPresentationGate.isPending(request) else { return }
        guard isVisibleCollection(progress.collectionId) else {
            requestViewingProgressRefresh()
            return
        }

        await openPlayer(
            initialItemId: progress.collectionId,
            initialTokenId: progress.tokenId,
            initialTokenIndex: progress.tokenIndex,
            continueViewingCollectionId: progress.collectionId,
            request: request
        )
    }

    private func requestWidgetURL(_ url: URL) {
        guard let deepLink = WidgetDeepLink(url: url),
              case let .collection(collectionId, tokenId) = deepLink,
              isVisibleCollection(collectionId) else {
            widgetLaunchPresentationState.finishWidgetPlayerHandoff(for: url)
            return
        }

        let request = playerPresentationGate.begin()
        let handoffRequest = widgetLaunchPresentationState.beginWidgetPlayerHandoff(for: url)
        Task {
            defer {
                widgetLaunchPresentationState.finishWidgetPlayerHandoff(handoffRequest)
            }
            if let tokenId {
                await openWidgetToken(
                    collectionId: collectionId,
                    tokenId: tokenId,
                    request: request
                )
            } else {
                await openCollection(
                    collectionId: collectionId,
                    request: request
                )
            }
        }
    }

    private func openWidgetToken(
        collectionId: String,
        tokenId: String,
        request: PlayerPresentationRequestGate.Request
    ) async {
        await PlayerPersistenceUpdates.flush()
        guard playerPresentationGate.isPending(request) else { return }
        let progress = await PlayerViewingProgressStore.shared.progress(collectionId: collectionId)
        guard playerPresentationGate.isPending(request) else { return }
        guard let widgetTokenInsertion = CollectionCatalog.widgetTokenInsertion(
            collectionId: collectionId,
            widgetTokenId: tokenId,
            progress: progress
        ) else {
            await openCollection(
                collectionId: collectionId,
                request: request
            )
            return
        }

        guard playerPresentationGate.isPending(request) else { return }
        await openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            widgetTokenInsertion: widgetTokenInsertion,
            anchorProgress: widgetTokenInsertion.automaticAnchorProgress(),
            request: request
        )
    }

    private func openPlayer(
        initialItemId: String?,
        initialTokenId: String? = nil,
        initialTokenIndex: Int? = nil,
        continueViewingCollectionId: String,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil,
        anchorProgress: PlayerViewingProgress? = nil,
        request: PlayerPresentationRequestGate.Request
    ) async {
        guard playerPresentationGate.isPending(request) else { return }
        guard isVisibleCollection(continueViewingCollectionId),
              initialItemId.map({ isVisibleCollection($0) }) ?? true else {
            requestViewingProgressRefresh()
            return
        }
        guard let continueViewingUpdate = await PlayerViewingProgressStore.shared
            .prepareContinueViewingUpdate(collectionId: continueViewingCollectionId),
              playerPresentationGate.isPending(request) else {
            return
        }

        let config = VisionPlayerPrewarmer.preparedConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            initialTokenIndex: initialTokenIndex,
            continueViewingCollectionId: continueViewingCollectionId,
            widgetTokenInsertion: widgetTokenInsertion
        )
        playerPresentationGate.commit(
            request,
            present: {
                playerConfig = config
            },
            persist: {
                if let anchorProgress {
                    await PlayerViewingProgressStore.shared.save(anchorProgress)
                }
                await PlayerViewingProgressStore.shared.applyContinueViewingUpdate(
                    continueViewingUpdate
                )
            }
        )
    }

    private func cancelPendingPlayerPresentation() {
        playerPresentationGate.cancel()
    }

    private func randomCollectionItemPreferringUnfinishedCollections() async -> CollectionCatalogItem? {
        let progressSnapshot = await PlayerViewingProgressStore.shared.progressSnapshot()
        let unfinishedItems = collectionItems.filter { !progressSnapshot.viewedToEndCollectionIds.contains($0.id) }
        return (unfinishedItems.isEmpty ? collectionItems : unfinishedItems).randomElement()
    }

    private func requestViewingProgressRefresh(prewarm: Bool = false) {
        shouldPrewarmAfterViewingProgressRefresh =
            shouldPrewarmAfterViewingProgressRefresh || prewarm
        viewingProgressRefreshID &+= 1
    }

    private func performViewingProgressRefresh(id refreshID: Int) async {
        let shouldPrewarm = shouldPrewarmAfterViewingProgressRefresh
        let snapshot = await PlayerViewingProgressStore.shared.progressSnapshot()
        guard !Task.isCancelled, refreshID == viewingProgressRefreshID else { return }

        viewingProgressSnapshot = snapshot
        shouldPrewarmAfterViewingProgressRefresh = false
        if !hasLoadedViewingProgress {
            hasLoadedViewingProgress = true
        }
        if shouldPrewarm {
            schedulePlayerPrewarm()
        }
    }

    private func isVisibleCollection(_ collectionId: String) -> Bool {
        collectionItems.contains { $0.id == collectionId }
    }

}

private struct VisionImmersiveModeButton: View {
    let isEnabled: Bool
    let isOpening: Bool
    let action: () -> Void

    var body: some View {
        VisionOrnamentIconButton(
            image: image,
            accessibilityLabel: accessibilityLabel,
            isDisabled: isOpening,
            action: action
        )
    }

    private var image: Image {
        isEnabled ? Images.exitImmersiveMode : Images.enterImmersiveMode
    }

    private var accessibilityLabel: String {
        isEnabled ? Strings.exitImmersiveMode : Strings.enterImmersiveMode
    }
}

private struct VisionCollectionsTopOrnament: View {
    let continueViewingProgress: PlayerViewingProgress?
    let onContinueViewing: (PlayerViewingProgress) -> Void
    let onShowRandomPlayer: () -> Void

    var body: some View {
        HStack(spacing: VisionOrnamentMetrics.spacing) {
            if let continueViewingProgress {
                VisionContinueViewingButton(progress: continueViewingProgress) {
                    onContinueViewing(continueViewingProgress)
                }
                .transition(.opacity)
            }

            Spacer(minLength: VisionOrnamentMetrics.spacing)

            controlsGroup
        }
        .frame(width: visionCollectionsTopOrnamentWidth)
        .animation(.easeInOut(duration: 0.16), value: continueViewingProgress)
    }

    private var controlsGroup: some View {
        HStack(spacing: VisionOrnamentMetrics.controlGroupSpacing) {
            settingsMenu

            VisionOrnamentIconButton(
                image: Images.shuffle,
                accessibilityLabel: Strings.shuffle,
                action: onShowRandomPlayer
            )
        }
        .visionOrnamentControlGroupStyle()
    }

    private var settingsMenu: some View {
        Menu {
            Text(Strings.sendFeedback)
            Button(Strings.github, action: { UIApplication.shared.open(URL.github) })
            Button(Strings.mail, action: { UIApplication.shared.open(URL.mail) })
            Button(Strings.x, action: { UIApplication.shared.open(URL.x) })
            Divider()
            Button(Strings.rateOnTheAppStore) { UIApplication.shared.open(URL.writeAppStoreReview) }
        } label: {
            VisionOrnamentIconLabel(image: Images.preferences)
        }
        .menuIndicator(.hidden)
        .visionOrnamentIconControlStyle()
        .accessibilityLabel(Strings.settings)
    }
}

private struct VisionGridProgressBadge<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background(Color.black.opacity(0.72), in: Capsule())
    }
}

private struct VisionContinueViewingButton: View {
    let progress: PlayerViewingProgress
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Images.play
                    .font(.subheadline.weight(.bold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.continueViewing)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(progress.collectionName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }

                Spacer(minLength: 16)

                Text(Strings.percent(progress.percent))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(
                minWidth: visionCollectionsContinueViewingMinWidth,
                maxWidth: visionCollectionsContinueViewingMaxWidth,
                minHeight: VisionOrnamentMetrics.controlGroupHeight,
                maxHeight: VisionOrnamentMetrics.controlGroupHeight
            )
            .background {
                VisionContinueViewingCapsuleBackground()
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(Strings.continueViewing), \(progress.collectionName)"))
    }
}

private struct VisionContinueViewingCapsuleBackground: View {
    var body: some View {
        Capsule()
            .fill(.clear)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
