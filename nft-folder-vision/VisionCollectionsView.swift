// ∅ 2026 lil org

import SwiftUI

struct VisionCollectionsView: View {
    
    private let suggestedItems = VisionCollectionCatalog.allItems
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
            ForEach(suggestedItems) { item in
                Button(action: {
                    didSelectSuggestedItem(item)
                }) {
                    ZStack {
                        Image(item.id)
                            .resizable()
                            .scaledToFill()
                            .clipped()
                            .aspectRatio(1, contentMode: .fill)
                            .contentShape(Rectangle())
                        VStack {
                            Spacer()
                            gridItemText(item.name) {
                                didSelectSuggestedItem(item)
                            }
                        }
                    }
                }.aspectRatio(1, contentMode: .fit).contextMenu { suggestedItemContextMenu(item: item) }
            }
        }
        return grid
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
    
    private func suggestedItemContextMenu(item: SuggestedItem) -> some View {
        Group {
            Text(item.name)
            Divider()
            Button(Strings.play, action: {
                didSelectSuggestedItem(item)
            })
        }
    }
    
    private func didSelectSuggestedItem(_ item: SuggestedItem) {
        guard TokenGenerator.canGenerate(id: item.id) else { return }
        playerConfig = VisionPlayerConfig(initialItemId: item.id)
    }

    private func showRandomPlayer() {
        playerConfig = VisionPlayerConfig(initialItemId: nil)
    }

    private func dismissPlayer(_ config: VisionPlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        playerConfig = nil
    }

}

private enum VisionCollectionCatalog {

    static let allItems: [SuggestedItem] = {
        dedupedItems(generativeItemsForGrid + downloadableItemsForGrid)
            .filter { !TokenGenerator.isCollectionDisabledOnCurrentPlatform(id: $0.id) }
    }()

    private static var generativeItemsForGrid: [SuggestedItem] {
        return TokenGenerator.allGenerativeSuggestedItems.filter {
            !$0.isSolanaCollection && !$0.isTezosCollection
        }
    }

    private static var downloadableItemsForGrid: [SuggestedItem] {
        return SuggestedItemsService.allDownloadableCollectionItems
    }

    private static func dedupedItems(_ items: [SuggestedItem]) -> [SuggestedItem] {
        var seenIds = Set<String>()
        return items.filter { item in
            guard !seenIds.contains(item.id) else { return false }
            seenIds.insert(item.id)
            return true
        }
    }

}
