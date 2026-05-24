// ∅ 2026 lil org

import SwiftUI

struct VisionCollectionsView: View {
    
    private let collectionItems = CollectionCatalog.allItems
    @State private var gridPassCount = 1
    @State private var playerConfig: VisionPlayerConfig?
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                controlsBar
                ScrollView {
                    createGrid().frame(maxWidth: .infinity)
                }
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
        .onAppear {
            schedulePlayerPrewarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            schedulePlayerPrewarm()
        }
    }

    private var controlsBar: some View {
        HStack {
            Spacer()
            Menu {
                Text(Strings.sendFeedback)
                Button(Strings.github, action: { UIApplication.shared.open(URL.github) })
                Button(Strings.mail, action: { UIApplication.shared.open(URL.mail) })
                Button(Strings.x, action: { UIApplication.shared.open(URL.x) })
                Divider()
                Button(Strings.rateOnTheAppStore) { UIApplication.shared.open(URL.writeAppStoreReview) }
            } label: {
                Images.preferences
            }
            Button(action: {
                showRandomPlayer()
            }) {
                Images.shuffle
            }
        }
        .frame(height: 42)
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: 150), spacing: 0)]
        let grid = LazyVGrid(columns: gridLayout, alignment: .leading, spacing: 0) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let item = item(at: index)
                Button(action: {
                    didSelectCollectionItem(item)
                }) {
                    ZStack {
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
        playerConfig = VisionPlayerPrewarmer.preparedConfig(initialItemId: item.id)
    }

    private func showRandomPlayer() {
        playerConfig = VisionPlayerPrewarmer.preparedConfig(initialItemId: nil)
    }

    private func dismissPlayer(_ config: VisionPlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        playerConfig = nil
    }

    private func schedulePlayerPrewarm() {
        VisionPlayerPrewarmer.scheduleAfterLaunch(initialCollectionIds: likelyInitialCollectionIds())
    }

    private func likelyInitialCollectionIds() -> [String] {
        collectionItems.prefix(2).map(\.id)
    }

}
