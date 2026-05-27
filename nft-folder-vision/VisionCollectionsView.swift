// ∅ 2026 lil org

import SwiftUI

private let visionCollectionsMinimumWindowWidth: CGFloat = 720
private let visionCollectionsMinimumWindowHeight: CGFloat = 540
private let visionCollectionsTopOrnamentSpacing: CGFloat = 10
private let visionCollectionsTopOrnamentHorizontalPadding: CGFloat = 24
private let visionCollectionsContinueViewingMinWidth: CGFloat = 360
private let visionCollectionsContinueViewingMaxWidth: CGFloat = 520
private let visionCollectionsControlButtonSize: CGFloat = 46
private let visionCollectionsControlsGroupHeight: CGFloat = visionCollectionsControlButtonSize + 8
private let visionCollectionsTopOrnamentWidth: CGFloat = 640

struct VisionCollectionsView: View {
    
    private let collectionItems: [CollectionCatalogItem]
    @State private var gridPassCount = 1
    @State private var playerConfig: VisionPlayerConfig?

    @State private var viewingProgressByCollectionId: [String: Int]
    @State private var viewedToEndCollectionIds: Set<String>
    @State private var continueViewingProgress: PlayerViewingProgress?

    init(collectionItems: [CollectionCatalogItem] = CollectionCatalog.allItems) {
        self.collectionItems = collectionItems
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        _viewingProgressByCollectionId = State(initialValue: progressSnapshot.percentagesByCollectionId)
        _viewedToEndCollectionIds = State(initialValue: progressSnapshot.viewedToEndCollectionIds)
        _continueViewingProgress = State(
            initialValue: Self.visibleContinueViewingProgress(
                progressSnapshot.continueViewingProgress,
                collectionItems: collectionItems
            )
        )
    }

    var body: some View {
        ZStack {
            ScrollView {
                createGrid().frame(maxWidth: .infinity)
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
                continueViewingProgress: continueViewingProgress,
                onContinueViewing: { progress in resumeViewing(progress) },
                onShowRandomPlayer: showRandomPlayer
            )
            .padding(.horizontal, visionCollectionsTopOrnamentHorizontalPadding)
            .padding(.bottom, 10)
        }
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
    
    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: 150), spacing: 0)]
        let grid = LazyVGrid(columns: gridLayout, alignment: .leading, spacing: 0) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let item = item(at: index)
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
        guard let item = randomCollectionItemPreferringUnfinishedCollections() else { return }
        let progress = PlayerViewingProgressStore.progress(collectionId: item.id)
        let initialTokenId = progress?.isComplete == false ? progress?.tokenId : nil

        openPlayer(
            initialItemId: item.id,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: item.id
        )
    }

    private func dismissPlayer(_ config: VisionPlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        playerConfig = nil
        refreshViewingProgress()
    }

    private func schedulePlayerPrewarm() {
        VisionPlayerPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: likelyInitialCollectionIds()
        )
    }

    private func likelyInitialCollectionIds() -> [String] {
        collectionItems.prefix(2).map(\.id)
    }

    private func openCollection(
        collectionId: String,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        guard isVisibleCollection(collectionId) else { return }

        if let progress = PlayerViewingProgressStore.progress(collectionId: collectionId) {
            resumeViewing(progress, trackingMode: trackingMode)
            return
        }

        openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            trackingMode: trackingMode
        )
    }

    private func resumeViewing(
        _ progress: PlayerViewingProgress,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing
    ) {
        guard isVisibleCollection(progress.collectionId) else {
            refreshViewingProgress()
            return
        }

        openPlayer(
            initialItemId: progress.collectionId,
            initialTokenId: progress.tokenId,
            continueViewingCollectionId: progress.collectionId,
            trackingMode: trackingMode
        )
    }

    private func openWidgetURL(_ url: URL) {
        guard let deepLink = WidgetDeepLink(url: url),
              case let .collection(collectionId, tokenId) = deepLink,
              isVisibleCollection(collectionId) else {
            return
        }

        let trackingMode = widgetOpenTrackingMode()
        if let tokenId {
            openWidgetToken(collectionId: collectionId, tokenId: tokenId, trackingMode: trackingMode)
        } else {
            openCollection(collectionId: collectionId, trackingMode: trackingMode)
        }
    }

    private func openWidgetToken(
        collectionId: String,
        tokenId: String,
        trackingMode: PlayerViewingSessionTrackingMode
    ) {
        guard let widgetTokenInsertion = CollectionCatalog.widgetTokenInsertion(
            collectionId: collectionId,
            widgetTokenId: tokenId,
            progress: PlayerViewingProgressStore.progress(collectionId: collectionId)
        ) else {
            openCollection(collectionId: collectionId, trackingMode: trackingMode)
            return
        }

        openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            trackingMode: trackingMode,
            widgetTokenInsertion: widgetTokenInsertion
        )
        PlayerViewingProgressStore.save(widgetTokenInsertion.updatedAnchorProgress())
    }

    private func openPlayer(
        initialItemId: String?,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil
    ) {
        guard isVisibleCollection(continueViewingCollectionId),
              initialItemId.map({ isVisibleCollection($0) }) ?? true else {
            refreshViewingProgress()
            return
        }

        let config = VisionPlayerPrewarmer.preparedConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId,
            trackingMode: trackingMode,
            widgetTokenInsertion: widgetTokenInsertion
        )
        playerConfig = config
        if trackingMode.updatesContinueViewing {
            PlayerViewingProgressStore.setContinueViewingCollectionId(continueViewingCollectionId)
        }
    }

    private func randomCollectionItemPreferringUnfinishedCollections() -> CollectionCatalogItem? {
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        let unfinishedItems = collectionItems.filter { !progressSnapshot.viewedToEndCollectionIds.contains($0.id) }
        return (unfinishedItems.isEmpty ? collectionItems : unfinishedItems).randomElement()
    }

    private func refreshViewingProgress() {
        let progressSnapshot = PlayerViewingProgressStore.progressSnapshot()
        viewingProgressByCollectionId = progressSnapshot.percentagesByCollectionId
        viewedToEndCollectionIds = progressSnapshot.viewedToEndCollectionIds
        continueViewingProgress = Self.visibleContinueViewingProgress(
            progressSnapshot.continueViewingProgress,
            collectionItems: collectionItems
        )
    }

    private func isVisibleCollection(_ collectionId: String) -> Bool {
        collectionItems.contains { $0.id == collectionId }
    }

    private func widgetOpenTrackingMode() -> PlayerViewingSessionTrackingMode {
        PlayerViewingProgressStore.progressSnapshot().continueViewingProgress == nil
            ? .updateContinueViewing
            : .progressOnly
    }

    private static func visibleContinueViewingProgress(
        _ progress: PlayerViewingProgress?,
        collectionItems: [CollectionCatalogItem]
    ) -> PlayerViewingProgress? {
        guard let progress,
              collectionItems.contains(where: { $0.id == progress.collectionId }) else {
            return nil
        }
        return progress
    }

}

private struct VisionCollectionsTopOrnament: View {
    let continueViewingProgress: PlayerViewingProgress?
    let onContinueViewing: (PlayerViewingProgress) -> Void
    let onShowRandomPlayer: () -> Void

    var body: some View {
        HStack(spacing: visionCollectionsTopOrnamentSpacing) {
            if let continueViewingProgress {
                VisionContinueViewingButton(progress: continueViewingProgress) {
                    onContinueViewing(continueViewingProgress)
                }
                .transition(.opacity)
            }

            Spacer(minLength: visionCollectionsTopOrnamentSpacing)

            controlsGroup
        }
        .frame(width: visionCollectionsTopOrnamentWidth)
        .animation(.easeInOut(duration: 0.16), value: continueViewingProgress)
    }

    private var controlsGroup: some View {
        HStack(spacing: 8) {
            settingsMenu

            Button(action: onShowRandomPlayer) {
                Images.shuffle
                    .font(.title3.weight(.semibold))
                    .frame(
                        width: visionCollectionsControlButtonSize,
                        height: visionCollectionsControlButtonSize
                    )
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: Circle())
            .contentShape(Circle())
            .accessibilityLabel(Strings.shuffle)
        }
        .padding(4)
        .frame(height: visionCollectionsControlsGroupHeight)
        .background(.ultraThinMaterial, in: Capsule())
        .clipShape(Capsule())
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
            Images.preferences
                .font(.title3.weight(.semibold))
                .frame(
                    width: visionCollectionsControlButtonSize,
                    height: visionCollectionsControlButtonSize
                )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
        .contentShape(Circle())
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
                minHeight: visionCollectionsControlsGroupHeight,
                maxHeight: visionCollectionsControlsGroupHeight
            )
            .background {
                VisionProgressCapsuleBackground(progress: progress.fraction)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Strings.continueViewing), \(progress.collectionName)")
    }
}

private struct VisionProgressCapsuleBackground: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .background(.ultraThinMaterial, in: Capsule())

                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: geometry.size.width * clampedProgress)
            }
        }
    }
}
