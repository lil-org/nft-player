// ∅ 2026 lil org

import SwiftUI
import Combine

struct TvCollectionsView: View {
    
    private let collectionItems: [CollectionCatalogItem]
    @State private var selectedItemId: String?
    @State private var isNavigatingToPlayer = false
    @State private var showPreferencesAlert = false

    init(collectionItems: [CollectionCatalogItem] = CollectionCatalog.allItems) {
        self.collectionItems = collectionItems
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                createGrid()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {}
            }
            .navigationBarItems(trailing: HStack {
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
            })
            .background(
                NavigationLink(destination: TvPlayerView(initialItemId: selectedItemId).edgesIgnoringSafeArea(.all), isActive: $isNavigatingToPlayer) {
                    EmptyView().hidden()
                }.hidden()
            )
        }
    }
    
    private var shuffleButton: some View {
        Button(action: showRandomPlayer) {
            Images.shuffle
        }.buttonStyle(PlainButtonStyle()).foregroundStyle(.tertiary)
    }
    
    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: 230), spacing: 20)]
        let grid = LazyVGrid(columns: gridLayout, alignment: .center, spacing: 23) {
            ForEach(collectionItems) { item in
                Button(action: {
                    didSelectCollectionItem(item)
                }) {
                    VStack {
                        Image(item.coverAssetName)
                            .resizable()
                            .scaledToFit()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(10)
                        gridItemText(item.name)
                    }
                }
                .contextMenu { collectionItemContextMenu(item: item) }
            }
        }
        .padding(.horizontal)
        return grid
    }
    
    private func gridItemText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .regular))
            .lineLimit(2)
            .foregroundColor(.white)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.7))
            .cornerRadius(5)
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

        selectedItemId = item.id
        isNavigatingToPlayer = true
    }
    
    private func showRandomPlayer() {
        guard let item = collectionItems.filter(isPlayableCollectionItem).randomElement() else { return }

        selectedItemId = item.id
        isNavigatingToPlayer = true
    }

    private func isPlayableCollectionItem(_ item: CollectionCatalogItem) -> Bool {
        TokenGenerator.canGenerate(id: item.id)
    }
    
}
