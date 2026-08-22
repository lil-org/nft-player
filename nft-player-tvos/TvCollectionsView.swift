// ∅ 2026 lil org

import Foundation
import SwiftUI
import UIKit

private let tvContinueViewingButtonMaxWidth: CGFloat = 500
private let tvContinueViewingCollectionNameMaxWidth: CGFloat = 440
private let tvCollectionGridMinimumItemWidth: CGFloat = 230
private let tvCollectionGridColumnSpacing: CGFloat = 32
private let tvCollectionGridRowSpacing: CGFloat = 32
private let tvCollectionGridItemInset: CGFloat = 10
private let tvCollectionGridCornerRadius: CGFloat = 10
private let tvCollectionGridFocusedScale: CGFloat = 1.025
private let tvCollectionGridFocusRingOutset: CGFloat = 6
private let tvCollectionGridFocusRingWidth: CGFloat = 4

struct TvCollectionsView: View {
    
    private let collectionItems: [CollectionCatalogItem]
    @FocusState private var focusedGridDisplayedIndex: Int?
    @State private var gridPassCount: Int
    @State private var gridScrollMemoryTracker: CollectionsGridScrollMemoryTracker
    @State private var hasRestoredInitialGridScrollPosition: Bool
    @State private var playerNavigationRequest: TvPlayerNavigationRequest?
    @State private var isNavigatingToPlayer = false
    @State private var showPreferencesAlert = false
    @State private var progressSnapshot: PlayerViewingProgressSnapshot
    @State private var pendingRestoredFocusDisplayedIndex: Int?
    @State private var restoredFocusTask: Task<Void, Never>?
    @State private var playerPresentationGate = PlayerPresentationRequestGate()
    @State private var hasLoadedViewingProgress = false
    @State private var viewingProgressRefreshID = 0
    @State private var shouldPrewarmAfterViewingProgressRefresh = true

    init(collectionItems: [CollectionCatalogItem] = CollectionCatalog.allItems) {
        self.collectionItems = collectionItems
        let gridScrollMemoryTracker = CollectionsGridScrollMemoryTracker(items: collectionItems)
        _gridPassCount = State(initialValue: gridScrollMemoryTracker.initialGridPassCount)
        _gridScrollMemoryTracker = State(initialValue: gridScrollMemoryTracker)
        _hasRestoredInitialGridScrollPosition = State(
            initialValue: gridScrollMemoryTracker.initialDisplayedIndex == nil
        )
        _progressSnapshot = State(
            initialValue: .empty
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    createGrid()
                }
                .collectionsGridScrollMemoryTracking(
                    tracker: gridScrollMemoryTracker,
                    minimumItemWidth: tvCollectionGridMinimumItemWidth,
                    columnSpacing: tvCollectionGridColumnSpacing,
                    rowSpacing: tvCollectionGridRowSpacing,
                    visibleItemCount: visibleItemCount
                )
                .opacity(
                    hasRestoredInitialGridScrollPosition && hasLoadedViewingProgress
                        ? 1
                        : 0
                )
                .disabled(
                    !hasRestoredInitialGridScrollPosition || !hasLoadedViewingProgress
                )
                .collectionsGridScrollMemoryRestoration(
                    using: scrollProxy,
                    tracker: gridScrollMemoryTracker,
                    hasRestored: $hasRestoredInitialGridScrollPosition,
                    onRestored: { displayedIndex in
                        pendingRestoredFocusDisplayedIndex = displayedIndex
                        scheduleInitialGridFocusIfReady()
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .principal) {}
            }
            .navigationBarItems(
                leading: continueViewingNavigationItem,
                trailing: HStack {
                    Button(action: {
                        showPreferencesAlert = true
                    }) {
                        Images.preferences
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(.tertiary)
                    .alert(isPresented: $showPreferencesAlert) {
                        Alert(
                            title: Text(Strings.sendFeedback),
                            message: Text(Strings.lilOrgLinkWithEmojis),
                            dismissButton: .default(Text(Strings.ok))
                        )
                    }
                    
                    shuffleButton
                }
            )
            .navigationDestination(isPresented: $isNavigatingToPlayer) {
                playerDestination
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                guard !isNavigatingToPlayer else { return }
                requestViewingProgressRefresh(prewarm: true)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)
                    .receive(on: RunLoop.main)
            ) { _ in
                guard !isNavigatingToPlayer else { return }
                requestViewingProgressRefresh()
            }
            .task(id: viewingProgressRefreshID) {
                await performViewingProgressRefresh(id: viewingProgressRefreshID)
            }
            .collectionsGridScrollMemoryLifecycleFlush(tracker: gridScrollMemoryTracker)
            .onChange(of: isNavigatingToPlayer) { _, isNavigatingToPlayer in
                if isNavigatingToPlayer {
                    cancelRestoredGridFocus()
                    return
                }
                requestViewingProgressRefresh(prewarm: true)
            }
            .onDisappear {
                playerPresentationGate.cancel()
                cancelRestoredGridFocus()
            }
            .animation(.easeInOut(duration: 0.16), value: continueViewingProgress)
        }
    }
    
    private var shuffleButton: some View {
        Button(action: showRandomPlayer) {
            Images.shuffle
        }.buttonStyle(PlainButtonStyle()).foregroundStyle(.tertiary)
    }

    private var playerDestination: some View {
        TvPlayerView(
            initialItemId: playerNavigationRequest?.initialItemId,
            initialTokenId: playerNavigationRequest?.initialTokenId,
            continueViewingCollectionId: playerNavigationRequest?.continueViewingCollectionId
        )
        .id(playerNavigationRequest?.id)
        .edgesIgnoringSafeArea(.all)
    }

    private var continueViewingProgress: PlayerViewingProgress? {
        progressSnapshot.firstVisibleContinueViewingProgress { collectionId in
            Self.isVisiblePlayableCollection(collectionId, collectionItems: collectionItems)
        }
    }

    @ViewBuilder
    private var continueViewingNavigationItem: some View {
        if let continueViewingProgress {
            TvContinueViewingButton(progress: continueViewingProgress) {
                resumeViewing(continueViewingProgress)
            }
            .transition(.opacity)
        }
    }

    private func resetGridFocus(to displayedIndex: Int) {
        restoredFocusTask?.cancel()
        restoredFocusTask = Task { @MainActor in
            await nextMainRunLoopTurn()
            guard !Task.isCancelled,
                  !isNavigatingToPlayer else {
                return
            }
            focusedGridDisplayedIndex = displayedIndex
            restoredFocusTask = nil
        }
    }

    private func scheduleInitialGridFocusIfReady() {
        guard hasLoadedViewingProgress,
              hasRestoredInitialGridScrollPosition,
              visibleItemCount > 0 else {
            return
        }
        let displayedIndex = pendingRestoredFocusDisplayedIndex ?? 0
        pendingRestoredFocusDisplayedIndex = nil
        resetGridFocus(to: displayedIndex)
    }

    private func cancelRestoredGridFocus() {
        restoredFocusTask?.cancel()
        restoredFocusTask = nil
        pendingRestoredFocusDisplayedIndex = nil
    }

    private func nextMainRunLoopTurn() async {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform {
                continuation.resume()
            }
        }
    }
    
    private func createGrid() -> some View {
        let gridLayout = [
            GridItem(
                .adaptive(minimum: tvCollectionGridMinimumItemWidth),
                spacing: tvCollectionGridColumnSpacing
            )
        ]
        let grid = LazyVGrid(columns: gridLayout, alignment: .center, spacing: tvCollectionGridRowSpacing) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let sourceIndex = sourceIndex(for: index)
                let item = collectionItems[sourceIndex]
                TvCollectionGridItemButton(
                    item: item,
                    progressPercent: progressSnapshot.percentagesByCollectionId[item.id],
                    hasViewedToEnd: progressSnapshot.viewedToEndCollectionIds.contains(item.id),
                    displayedIndex: index,
                    focusedDisplayedIndex: $focusedGridDisplayedIndex
                ) {
                    didSelectCollectionItem(item)
                }
                .padding(tvCollectionGridItemInset)
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
            .collectionsGridScrollMemoryContent()
            .padding(.horizontal)
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
    
    private func collectionItemContextMenu(item: CollectionCatalogItem) -> some View {
        Group {
            Text(item.name)
            if isPlayableCollectionItem(item) {
                Divider()
                Button(Strings.play, action: {
                    didSelectCollectionItem(item)
                })
            }
        }
    }
    
    private func didSelectCollectionItem(_ item: CollectionCatalogItem) {
        guard isPlayableCollectionItem(item) else { return }

        let request = playerPresentationGate.begin()
        Task {
            await PlayerPersistenceUpdates.flush()
            guard playerPresentationGate.isPending(request) else { return }
            let progress = await PlayerViewingProgressStore.shared.progress(collectionId: item.id)
            guard playerPresentationGate.isPending(request) else { return }
            await openPlayer(
                initialItemId: item.id,
                initialTokenId: progress?.tokenId,
                continueViewingCollectionId: item.id,
                request: request
            )
        }
    }
    
    private func showRandomPlayer() {
        let request = playerPresentationGate.begin()
        Task {
            await PlayerPersistenceUpdates.flush()
            guard playerPresentationGate.isPending(request) else { return }
            let progressSnapshot = await PlayerViewingProgressStore.shared.progressSnapshot()
            guard playerPresentationGate.isPending(request) else { return }
            guard let item = randomCollectionItemPreferringUnfinishedCollections(
                progressSnapshot: progressSnapshot
            ) else { return }
            let progress = await PlayerViewingProgressStore.shared.progress(collectionId: item.id)
            guard playerPresentationGate.isPending(request) else { return }
            let initialTokenId = progress?.isComplete == false ? progress?.tokenId : nil

            await openPlayer(
                initialItemId: item.id,
                initialTokenId: initialTokenId,
                continueViewingCollectionId: item.id,
                request: request
            )
        }
    }

    private func isPlayableCollectionItem(_ item: CollectionCatalogItem) -> Bool {
        CollectionCatalog.canOpenCollection(specificCollectionId: item.id)
    }

    private func resumeViewing(_ progress: PlayerViewingProgress) {
        let request = playerPresentationGate.begin()
        Task { await resumeViewing(progress, request: request) }
    }

    private func resumeViewing(
        _ progress: PlayerViewingProgress,
        request: PlayerPresentationRequestGate.Request
    ) async {
        await PlayerPersistenceUpdates.flush()
        guard playerPresentationGate.isPending(request) else { return }
        guard Self.isVisiblePlayableCollection(
            progress.collectionId,
            collectionItems: collectionItems
        ) else {
            requestViewingProgressRefresh()
            return
        }

        let latestProgress = await PlayerViewingProgressStore.shared.progress(
            collectionId: progress.collectionId
        )
        guard playerPresentationGate.isPending(request) else { return }
        await openPlayer(
            initialItemId: progress.collectionId,
            initialTokenId: latestProgress?.tokenId,
            continueViewingCollectionId: progress.collectionId,
            request: request
        )
    }

    private func openPlayer(
        initialItemId: String,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String,
        request: PlayerPresentationRequestGate.Request
    ) async {
        guard CollectionCatalog.canOpenCollection(specificCollectionId: initialItemId) else { return }

        guard playerPresentationGate.isPending(request) else { return }
        guard let continueViewingUpdate = await PlayerViewingProgressStore.shared
            .prepareContinueViewingUpdate(collectionId: continueViewingCollectionId),
              playerPresentationGate.isPending(request) else {
            return
        }
        let navigationRequest = TvPlayerNavigationRequest(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId
        )
        playerPresentationGate.commit(
            request,
            present: {
                playerNavigationRequest = navigationRequest
                isNavigatingToPlayer = true
            },
            persist: {
                await PlayerViewingProgressStore.shared.applyContinueViewingUpdate(
                    continueViewingUpdate
                )
            }
        )
    }

    private func randomCollectionItemPreferringUnfinishedCollections(
        progressSnapshot: PlayerViewingProgressSnapshot
    ) -> CollectionCatalogItem? {
        let playableItems = collectionItems.filter(isPlayableCollectionItem)
        guard !playableItems.isEmpty else { return nil }

        let unfinishedItems = playableItems.filter { !progressSnapshot.viewedToEndCollectionIds.contains($0.id) }
        return (unfinishedItems.isEmpty ? playableItems : unfinishedItems).randomElement()
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

        progressSnapshot = snapshot
        shouldPrewarmAfterViewingProgressRefresh = false
        if !hasLoadedViewingProgress {
            hasLoadedViewingProgress = true
            scheduleInitialGridFocusIfReady()
        }
        if shouldPrewarm {
            schedulePlayerPrewarm()
        }
    }

    private func schedulePlayerPrewarm() {
        TvPlayerPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: likelyInitialCollectionIds()
        )
    }

    private func likelyInitialCollectionIds() -> [String] {
        gridScrollMemoryTracker.initialCollectionIds(limit: 2)
    }

    private static func isVisiblePlayableCollection(
        _ collectionId: String,
        collectionItems: [CollectionCatalogItem]
    ) -> Bool {
        collectionItems.contains(where: { $0.id == collectionId })
            && CollectionCatalog.canOpenCollection(specificCollectionId: collectionId)
    }
    
}

private struct TvPlayerNavigationRequest: Identifiable {
    let id = UUID()
    let initialItemId: String
    let initialTokenId: String?
    let continueViewingCollectionId: String
}

private struct TvCollectionGridItemButton: View {
    let item: CollectionCatalogItem
    let progressPercent: Int?
    let hasViewedToEnd: Bool
    let displayedIndex: Int
    let focusedDisplayedIndex: FocusState<Int?>.Binding
    let action: () -> Void

    private var isFocused: Bool {
        focusedDisplayedIndex.wrappedValue == displayedIndex
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(item.coverAssetName)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .aspectRatio(1, contentMode: .fill)
                    .contentShape(Rectangle())

                VStack {
                    Spacer()
                    title
                }

                progressBadge
                    .padding(8)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: tvCollectionGridCornerRadius, style: .continuous))
            .overlay {
                if isFocused {
                    RoundedRectangle(
                        cornerRadius: tvCollectionGridCornerRadius + tvCollectionGridFocusRingOutset,
                        style: .continuous
                    )
                        .strokeBorder(.white.opacity(0.92), lineWidth: tvCollectionGridFocusRingWidth)
                        .padding(-tvCollectionGridFocusRingOutset)
                }
            }
            .shadow(color: isFocused ? .black.opacity(0.24) : .clear, radius: 10, y: 5)
            .scaleEffect(isFocused ? tvCollectionGridFocusedScale : 1)
        }
        .buttonStyle(TvCollectionGridButtonStyle())
        .focused(focusedDisplayedIndex, equals: displayedIndex)
        .tvCollectionGridFocusEffectDisabled()
        .zIndex(isFocused ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }

    private var title: some View {
        HStack {
            Text(item.name)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(2)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 1)
                .background(Color.black.opacity(0.7))
                .cornerRadius(3)
                .padding(.leading, 4)
                .padding(.bottom, 3)
            Spacer()
        }
    }

    @ViewBuilder
    private var progressBadge: some View {
        if hasViewedToEnd {
            TvGridProgressBadge {
                Images.checkmark
                    .font(.caption.weight(.semibold))
            }
        } else if let progressPercent, progressPercent > 0 {
            TvGridProgressBadge {
                Text(Strings.percent(progressPercent))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }
}

private struct TvCollectionGridButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

private extension View {
    @ViewBuilder
    func tvCollectionGridFocusEffectDisabled() -> some View {
        if #available(tvOS 17.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}

private struct TvGridProgressBadge<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 30)
            .background(Color.black.opacity(0.72), in: Capsule())
    }
}

private struct TvContinueViewingButton: View {
    let progress: PlayerViewingProgress
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Images.play
                    .font(.subheadline.weight(.bold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.continueViewing)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(progress.collectionName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: tvContinueViewingCollectionNameMaxWidth, alignment: .leading)
                        .layoutPriority(1)
                }
            }
            .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.64))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: tvContinueViewingButtonMaxWidth, alignment: .leading)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityLabel(Text(verbatim: "\(Strings.continueViewing), \(progress.collectionName)"))
    }
}
