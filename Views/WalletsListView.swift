// ∅ 2026 lil org

import Cocoa
import SwiftUI

struct WalletsListView: View {

    private let collectionItems = CollectionCatalog.allItems
    @State private var gridPassCount = 1

    var body: some View {
        ScrollView {
            createGrid()
                .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Spacer()
                ControlGroup {
                    settingsMenu
                    Button(action: {
                        showPlayer(id: nil)
                    }) {
                        Images.shuffle
                    }
                }
            }
        }
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

    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: 100), spacing: 0)]
        let grid = LazyVGrid(columns: gridLayout, alignment: .leading, spacing: 0) {
            ForEach(0..<visibleItemCount, id: \.self) { index in
                let item = item(at: index)
                CollectionTile(item: item) {
                    showPlayer(id: item.id)
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

    private func showPlayer(id: String?) {
        guard let token = CollectionCatalog.generateRandomToken(
            specificCollectionId: id,
            notTokenId: nil
        ) else {
            return
        }
        Navigator.shared.showPlayer(model: PlayerModel(token: token))
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

}

private struct CollectionTile: View {

    let item: CollectionCatalogItem
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

}
