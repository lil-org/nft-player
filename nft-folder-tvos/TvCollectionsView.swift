// ∅ 2026 lil org

import Foundation
import SwiftUI
import Combine
import UIKit

private let tvContinueViewingButtonMaxWidth: CGFloat = 500
private let tvContinueViewingCollectionNameMaxWidth: CGFloat = 440
private let tvCollectionGridItemInset: CGFloat = 8

struct TvCollectionsView: View {
    
    private let collectionItems: [CollectionCatalogItem]
    @State private var gridPassCount = 1
    @State private var playerNavigationRequest: TvPlayerNavigationRequest?
    @State private var isNavigatingToPlayer = false
    @State private var showPreferencesAlert = false
    @State private var progressSnapshot: PlayerViewingProgressSnapshot

    init(collectionItems: [CollectionCatalogItem] = CollectionCatalog.allItems) {
        self.collectionItems = collectionItems
        _progressSnapshot = State(initialValue: PlayerViewingProgressStore.progressSnapshot())
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                createGrid()
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
            .background(
                NavigationLink(
                    destination: playerDestination,
                    isActive: $isNavigatingToPlayer
                ) {
                    EmptyView().hidden()
                }.hidden()
            )
            .onAppear {
                refreshViewingProgress()
                schedulePlayerPrewarm()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                guard !isNavigatingToPlayer else { return }
                refreshViewingProgress()
                schedulePlayerPrewarm()
            }
            .onReceive(NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)) { _ in
                guard !isNavigatingToPlayer else { return }
                refreshViewingProgress()
            }
            .onChange(of: isNavigatingToPlayer) { isNavigatingToPlayer in
                guard !isNavigatingToPlayer else { return }
                refreshViewingProgress()
                schedulePlayerPrewarm()
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
        Self.visibleContinueViewingProgress(
            progressSnapshot.continueViewingProgress,
            collectionItems: collectionItems
        )
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
    
    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: 230), spacing: 20)]
        let grid = LazyVGrid(columns: gridLayout, alignment: .center, spacing: 23) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let item = item(at: index)
                TvCollectionGridItemButton(
                    item: item,
                    progressPercent: progressSnapshot.percentagesByCollectionId[item.id],
                    hasViewedToEnd: progressSnapshot.viewedToEndCollectionIds.contains(item.id)
                ) {
                    didSelectCollectionItem(item)
                }
                .padding(tvCollectionGridItemInset)
                .contextMenu { collectionItemContextMenu(item: item) }
                .onAppear {
                    appendNextPassIfNeeded(for: index)
                }
            }
        }
        .padding(.horizontal)
        return grid
    }

    private var visibleItemCount: Int {
        collectionItems.count * gridPassCount
    }

    private func item(at index: Int) -> CollectionCatalogItem {
        collectionItems[index % collectionItems.count]
    }

    private func appendNextPassIfNeeded(for index: Int) {
        guard !collectionItems.isEmpty else { return }

        let appendThreshold = min(max(collectionItems.count / 2, 24), collectionItems.count)
        let triggerIndex = visibleItemCount - appendThreshold
        guard index >= triggerIndex else { return }

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

        if let progress = PlayerViewingProgressStore.progress(collectionId: item.id) {
            resumeViewing(progress)
            return
        }

        openPlayer(
            initialItemId: item.id,
            continueViewingCollectionId: item.id
        )
    }
    
    private func showRandomPlayer() {
        guard let item = randomCollectionItemPreferringUnfinishedCollections() else { return }

        let progress = PlayerViewingProgressStore.progress(collectionId: item.id)
        let initialTokenId = progress?.isComplete == false ? progress?.tokenId : nil

        openPlayer(
            initialItemId: item.id,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: item.id
        )
    }

    private func isPlayableCollectionItem(_ item: CollectionCatalogItem) -> Bool {
        CollectionCatalog.canOpenCollection(specificCollectionId: item.id)
    }

    private func resumeViewing(_ progress: PlayerViewingProgress) {
        guard Self.isVisiblePlayableCollection(
            progress.collectionId,
            collectionItems: collectionItems
        ) else {
            refreshViewingProgress()
            return
        }

        openPlayer(
            initialItemId: progress.collectionId,
            initialTokenId: progress.tokenId,
            continueViewingCollectionId: progress.collectionId
        )
    }

    private func openPlayer(
        initialItemId: String,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String
    ) {
        guard CollectionCatalog.canOpenCollection(specificCollectionId: initialItemId) else { return }

        PlayerViewingProgressStore.setContinueViewingCollectionId(continueViewingCollectionId)
        playerNavigationRequest = TvPlayerNavigationRequest(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId
        )
        isNavigatingToPlayer = true
    }

    private func randomCollectionItemPreferringUnfinishedCollections() -> CollectionCatalogItem? {
        let playableItems = collectionItems.filter(isPlayableCollectionItem)
        guard !playableItems.isEmpty else { return nil }

        let unfinishedItems = playableItems.filter { !progressSnapshot.viewedToEndCollectionIds.contains($0.id) }
        return (unfinishedItems.isEmpty ? playableItems : unfinishedItems).randomElement()
    }

    private func refreshViewingProgress() {
        progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
    }

    private func schedulePlayerPrewarm() {
        TvPlayerPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: likelyInitialCollectionIds()
        )
    }

    private func likelyInitialCollectionIds() -> [String] {
        collectionItems.prefix(2).map(\.id)
    }

    private static func visibleContinueViewingProgress(
        _ progress: PlayerViewingProgress?,
        collectionItems: [CollectionCatalogItem]
    ) -> PlayerViewingProgress? {
        guard let progress,
              isVisiblePlayableCollection(progress.collectionId, collectionItems: collectionItems) else {
            return nil
        }
        return progress
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
    let action: () -> Void
    @FocusState private var isFocused: Bool

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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.92), lineWidth: 6)
                }
            }
            .shadow(color: isFocused ? .black.opacity(0.34) : .clear, radius: 18, y: 8)
            .scaleEffect(isFocused ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
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
        .accessibilityLabel("\(Strings.continueViewing), \(progress.collectionName)")
    }
}
