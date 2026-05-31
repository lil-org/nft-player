// ∅ 2026 lil org

import Cocoa
import SwiftUI

private let continueViewingButtonPadding: CGFloat = 16
private let continueViewingCollectionNameMaxWidth: CGFloat = 250

struct WalletsListView: View {

    private let collectionItems = CollectionCatalog.allItems
    @State private var gridPassCount = 1
    @State private var viewingProgressByCollectionId: [String: Int]
    @State private var viewedToEndCollectionIds: Set<String>
    @State private var continueViewingProgress: PlayerViewingProgress?
    @State private var hasOpenPlayerWindows: Bool

    init() {
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        _viewingProgressByCollectionId = State(initialValue: progressSnapshot.percentagesByCollectionId)
        _viewedToEndCollectionIds = State(initialValue: progressSnapshot.viewedToEndCollectionIds)
        _continueViewingProgress = State(initialValue: progressSnapshot.continueViewingProgress)
        _hasOpenPlayerWindows = State(initialValue: Window.hasOpenPlayerWindows)
    }

    var body: some View {
        ScrollView {
            createGrid()
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            if shouldShowContinueViewingControl, let continueViewingProgress {
                ContinueViewingButton(progress: continueViewingProgress) {
                    resumeViewing(continueViewingProgress)
                }
                .padding(.horizontal, continueViewingButtonPadding)
                .padding(.top, continueViewingButtonPadding / 2)
                .padding(.bottom, continueViewingButtonPadding)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Spacer()
                ControlGroup {
                    settingsMenu
                    Button(action: {
                        showShuffledCollectionPlayer()
                    }) {
                        Images.shuffle
                    }
                }
            }
        }
        .onAppear {
            refreshViewingProgress()
            refreshPlayerWindowState()
            schedulePlayerPrewarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)) { _ in
            refreshViewingProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerWindowsDidChange)) { _ in
            refreshPlayerWindowState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshViewingProgress()
            refreshPlayerWindowState()
        }
        .animation(continueViewingControlAnimation, value: continueViewingProgress)
        .animation(continueViewingControlAnimation, value: hasOpenPlayerWindows)
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

    private var shouldShowContinueViewingControl: Bool {
        continueViewingProgress != nil && !hasOpenPlayerWindows
    }

    private var continueViewingControlAnimation: Animation? {
        shouldShowContinueViewingControl ? .easeInOut(duration: 0.16) : nil
    }

    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: 100), spacing: 0)]
        let grid = LazyVGrid(columns: gridLayout, alignment: .leading, spacing: 0) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let item = item(at: index)
                CollectionTile(
                    item: item,
                    progressPercent: viewingProgressByCollectionId[item.id],
                    hasViewedToEnd: viewedToEndCollectionIds.contains(item.id)
                ) {
                    didSelectCollectionItem(item)
                }
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

    private func didSelectCollectionItem(_ item: CollectionCatalogItem) {
        if let progress = PlayerViewingProgressStore.progress(collectionId: item.id) {
            resumeViewing(progress)
            return
        }

        Navigator.shared.showPlayer(collectionId: item.id, continueViewingCollectionId: item.id)
    }

    private func showShuffledCollectionPlayer() {
        guard let item = randomCollectionItemPreferringUnfinishedCollections() else { return }
        let progress = PlayerViewingProgressStore.progress(collectionId: item.id)
        let initialTokenId = progress?.isComplete == false ? progress?.tokenId : nil

        Navigator.shared.showPlayer(
            collectionId: item.id,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: item.id
        )
    }

    private func randomCollectionItemPreferringUnfinishedCollections() -> CollectionCatalogItem? {
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        let unfinishedItems = collectionItems.filter { !progressSnapshot.viewedToEndCollectionIds.contains($0.id) }
        return (unfinishedItems.isEmpty ? collectionItems : unfinishedItems).randomElement()
    }

    private func resumeViewing(_ progress: PlayerViewingProgress) {
        Navigator.shared.showPlayer(
            collectionId: progress.collectionId,
            initialTokenId: progress.tokenId,
            continueViewingCollectionId: progress.collectionId
        )
    }

    private func refreshViewingProgress() {
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        viewingProgressByCollectionId = progressSnapshot.percentagesByCollectionId
        viewedToEndCollectionIds = progressSnapshot.viewedToEndCollectionIds
        continueViewingProgress = progressSnapshot.continueViewingProgress
    }

    private func refreshPlayerWindowState() {
        hasOpenPlayerWindows = Window.hasOpenPlayerWindows
    }

    private func schedulePlayerPrewarm() {
        PlayerWebView.scheduleFirstUsePrewarm()
        PlayerTokenPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: Array(collectionItems.prefix(2).map(\.id))
        )
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

}

private struct CollectionTile: View {

    let item: CollectionCatalogItem
    let progressPercent: Int?
    let hasViewedToEnd: Bool
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            Image(item.coverAssetName)
                .resizable()
                .scaledToFill()
                .clipped()
                .aspectRatio(1, contentMode: .fit)

            VStack {
                Spacer()
                title
            }

            VStack {
                HStack {
                    Spacer()
                    progressBadge
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var title: some View {
        HStack {
            Text(item.name)
                .font(.system(size: 10, weight: .regular))
                .lineLimit(2)
                .foregroundColor(.white)
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
            badgeImage(Images.checkmark)
        } else if let progressPercent, progressPercent > 0 {
            badgeText(Strings.percent(progressPercent))
        }
    }

    private func badgeText(_ text: String) -> some View {
        badge {
            Text(text)
                .monospacedDigit()
        }
    }

    private func badgeImage(_ image: Image) -> some View {
        image
            .font(.system(size: 9, weight: .semibold))
            .imageScale(.small)
            .foregroundColor(.white)
            .frame(width: 15, height: 15)
            .background(Color.black.opacity(0.72), in: Circle())
            .padding(.top, 4)
            .padding(.trailing, 4)
    }

    private func badge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Color.black.opacity(0.72), in: Capsule())
            .padding(.top, 4)
            .padding(.trailing, 4)
    }

}

private struct ContinueViewingButton: View {
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
                        .frame(maxWidth: continueViewingCollectionNameMaxWidth, alignment: .leading)
                        .layoutPriority(1)
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
                ContinueViewingCapsuleBackground(progress: progress.fraction)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityLabel(Text(verbatim: "\(Strings.continueViewing), \(progress.collectionName)"))
    }
}

private struct ContinueViewingCapsuleBackground: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                base

                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: geometry.size.width * clampedProgress)
            }
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var base: some View {
        if #available(macOS 26.0, *) {
            liquidGlassBase
        } else {
            Capsule()
                .fill(.black.opacity(0.66))
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlassBase: some View {
        Capsule()
            .fill(.white.opacity(0.08))
            .glassEffect(.regular.tint(.black.opacity(0.42)).interactive(), in: Capsule())
            .glassEffectTransition(.materialize)
    }
}
