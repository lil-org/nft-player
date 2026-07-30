// ∅ 2026 lil org

import Cocoa
import SwiftUI

private let continueViewingButtonPadding: CGFloat = 16
private let maximumVisibleRecentContinueViewingCount = 10
private let continueViewingCollectionNameMaxWidth: CGFloat = 250
private let continueViewingCoverThumbnailSize: CGFloat = 14
private let continueViewingCoverThumbnailCornerRadius: CGFloat = 3
private let continueViewingPillSpacing: CGFloat = 8
private let continueViewingPillScrollHorizontalInset: CGFloat = 16
private let collectionsGridMinimumItemWidth: CGFloat = 100
private let collectionsGridColumnSpacing: CGFloat = 0
private let collectionsGridRowSpacing: CGFloat = 0

struct WalletsListView: View {

    private let collectionItems: [CollectionCatalogItem]
    @ObservedObject private var widgetLaunchPresentationState = WidgetLaunchPresentationState.shared
    @State private var gridPassCount: Int
    @State private var gridScrollMemoryTracker: CollectionsGridScrollMemoryTracker
    @State private var hasRestoredInitialGridScrollPosition: Bool
    @State private var viewingProgressByCollectionId: [String: Int]
    @State private var viewedToEndCollectionIds: Set<String>
    @State private var recentContinueViewingProgresses: [PlayerViewingProgress]
    @State private var continueViewingScrollResetID = 0

    init(collectionItems: [CollectionCatalogItem] = CollectionCatalog.allItems) {
        self.collectionItems = collectionItems
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        let gridScrollMemoryTracker = CollectionsGridScrollMemoryTracker(items: collectionItems)
        _gridPassCount = State(initialValue: gridScrollMemoryTracker.initialGridPassCount)
        _gridScrollMemoryTracker = State(initialValue: gridScrollMemoryTracker)
        _hasRestoredInitialGridScrollPosition = State(
            initialValue: gridScrollMemoryTracker.initialDisplayedIndex == nil
        )
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
        ScrollViewReader { scrollProxy in
            ScrollView {
                createGrid()
                    .frame(maxWidth: .infinity)
                    .collectionsGridScrollMemoryContent()
            }
            .collectionsGridScrollMemoryTracking(
                tracker: gridScrollMemoryTracker,
                minimumItemWidth: collectionsGridMinimumItemWidth,
                columnSpacing: collectionsGridColumnSpacing,
                rowSpacing: collectionsGridRowSpacing,
                visibleItemCount: visibleItemCount
            )
            .opacity(hasRestoredInitialGridScrollPosition ? 1 : 0)
            .allowsHitTesting(hasRestoredInitialGridScrollPosition)
            .collectionsGridScrollMemoryRestoration(
                using: scrollProxy,
                tracker: gridScrollMemoryTracker,
                hasRestored: $hasRestoredInitialGridScrollPosition
            )
        }
        .overlay(alignment: .bottom) {
            if shouldShowContinueViewingControl {
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
                        .padding(.top, continueViewingButtonPadding / 2)
                        .padding(.bottom, continueViewingButtonPadding)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .onAppear {
            refreshViewingProgress()
            schedulePlayerPrewarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)) { _ in
            refreshViewingProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshViewingProgress()
        }
        .collectionsGridScrollMemoryLifecycleFlush(tracker: gridScrollMemoryTracker)
        .animation(continueViewingControlAnimation, value: recentContinueViewingProgresses)
        .animation(
            continueViewingControlAnimation,
            value: widgetLaunchPresentationState.isSuppressingContinueViewing
        )
    }

    private var shouldShowContinueViewingControl: Bool {
        !widgetLaunchPresentationState.isSuppressingContinueViewing
            && !recentContinueViewingProgresses.isEmpty
    }

    private var continueViewingControlAnimation: Animation? {
        shouldShowContinueViewingControl ? .easeInOut(duration: 0.16) : nil
    }

    private func createGrid() -> some View {
        let gridLayout = [
            GridItem(
                .adaptive(minimum: collectionsGridMinimumItemWidth),
                spacing: collectionsGridColumnSpacing
            )
        ]
        let grid = LazyVGrid(columns: gridLayout, alignment: .leading, spacing: collectionsGridRowSpacing) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let sourceIndex = sourceIndex(for: index)
                let item = collectionItems[sourceIndex]
                CollectionTile(
                    item: item,
                    progressPercent: viewingProgressByCollectionId[item.id],
                    hasViewedToEnd: viewedToEndCollectionIds.contains(item.id)
                ) {
                    didSelectCollectionItem(item)
                }
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

    private func didSelectCollectionItem(_ item: CollectionCatalogItem) {
        if let progress = PlayerViewingProgressStore.progress(collectionId: item.id) {
            resumeViewing(progress)
            return
        }

        Navigator.shared.showPlayer(collectionId: item.id, continueViewingCollectionId: item.id)
    }

    private func resumeViewing(_ progress: PlayerViewingProgress) {
        Navigator.shared.showPlayer(
            collectionId: progress.collectionId,
            initialTokenId: progress.tokenId,
            continueViewingCollectionId: progress.collectionId
        )
    }

    private func coverAssetName(for collectionId: String) -> String {
        collectionItems.first { $0.id == collectionId }?.coverAssetName ?? collectionId
    }

    private func refreshViewingProgress() {
        let previousLeadingCollectionId = recentContinueViewingProgresses.first?.collectionId
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        viewingProgressByCollectionId = progressSnapshot.percentagesByCollectionId
        viewedToEndCollectionIds = progressSnapshot.viewedToEndCollectionIds
        recentContinueViewingProgresses = Self.visibleRecentContinueViewingProgresses(
            from: progressSnapshot,
            collectionItems: collectionItems
        )

        guard previousLeadingCollectionId != recentContinueViewingProgresses.first?.collectionId else {
            return
        }
        continueViewingScrollResetID += 1
    }

    private func schedulePlayerPrewarm() {
        PlayerWebView.scheduleFirstUsePrewarm()
        PlayerTokenPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: recentContinueViewingProgresses.first,
            initialCollectionIds: gridScrollMemoryTracker.initialCollectionIds(limit: 2)
        )
    }

    private static func visibleRecentContinueViewingProgresses(
        from progressSnapshot: PlayerViewingProgressSnapshot,
        collectionItems: [CollectionCatalogItem]
    ) -> [PlayerViewingProgress] {
        let visibleCollectionIds = Set(collectionItems.map(\.id))
        return progressSnapshot.recentContinueViewingProgresses.filter { progress in
            visibleCollectionIds.contains(progress.collectionId)
                && CollectionCatalog.canOpenCollection(specificCollectionId: progress.collectionId)
        }
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

private struct ContinueViewingPillsScrollView: View {
    let progresses: [PlayerViewingProgress]
    let availableWidth: CGFloat
    let horizontalContentInset: CGFloat
    let resetID: Int
    let coverAssetName: (String) -> String
    let onSelect: (PlayerViewingProgress) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: continueViewingPillSpacing) {
                ForEach(Array(progresses.enumerated()), id: \.element.collectionId) { index, progress in
                    ContinueViewingButton(
                        progress: progress,
                        coverAssetName: coverAssetName(progress.collectionId),
                        isDefaultKeyboardShortcut: index == 0
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
    let progress: PlayerViewingProgress
    let coverAssetName: String
    let isDefaultKeyboardShortcut: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ContinueViewingCoverThumbnail(assetName: coverAssetName)

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
                ContinueViewingCapsuleBackground()
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .modifier(DefaultReturnKeyboardShortcut(isEnabled: isDefaultKeyboardShortcut))
        .accessibilityLabel(Text(verbatim: "\(Strings.continueViewing), \(progress.collectionName)"))
    }
}

private struct ContinueViewingCoverThumbnail: View {
    let assetName: String

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: continueViewingCoverThumbnailSize, height: continueViewingCoverThumbnailSize)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: continueViewingCoverThumbnailCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: continueViewingCoverThumbnailCornerRadius,
                    style: .continuous
                )
                .stroke(.white.opacity(0.22), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct DefaultReturnKeyboardShortcut: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.keyboardShortcut(.return, modifiers: [])
        } else {
            content
        }
    }
}

private struct ContinueViewingCapsuleBackground: View {
    var body: some View {
        base
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
