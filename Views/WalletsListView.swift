// ∅ 2026 lil org

import Cocoa
import SwiftUI

struct WalletsListView: View {

    private let suggestedItems = SuggestedItemsService.visibleItems

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
            ForEach(suggestedItems) { item in
                CollectionTile(
                    item: item,
                    canGenerate: TokenGenerator.canGenerate(id: item.id),
                    onSelect: {
                        showPlayer(id: item.id)
                    }
                )
            }
        }
        return grid
    }

    private func showPlayer(id: String?) {
        Navigator.shared.showPlayer(model: PlayerModel(specificCollectionId: id, notTokenId: nil))
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

}

private struct CollectionTile: View {

    let item: SuggestedItem
    let canGenerate: Bool
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            Image(item.id)
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
        .onTapGesture {
            if canGenerate {
                onSelect()
            }
        }
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
