import SwiftUI
import Combine

struct MobileCollectionsView: View {
    @State private var showSettingsPopup = false
    @State private var suggestedItems = TokenGenerator.allGenerativeSuggestedItems
    @State private var didAppear = false
    @State private var showMorePreferences = false
    @State private var navigationPath = [MobilePlayerConfig]()
    
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                ScrollView {
                    createGrid().frame(maxWidth: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {}
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Text(Strings.sendFeedback)
                        Button(Strings.github) { UIApplication.shared.open(URL.github) }
                        Button(Strings.mail) { UIApplication.shared.open(URL.mail) }
                        Button(Strings.x) { UIApplication.shared.open(URL.x) }
                        Divider()
                        Button(Strings.rateOnTheAppStore) { UIApplication.shared.open(URL.writeAppStoreReview) }
                        Divider()
                        Button(Strings.changeAppIcon) { didClickToggleAppIcon() }
                    } label: {
                        Images.preferences
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button { showRandomPlayer() } label: {
                            Images.shuffle
                        }
                    }
                    
                }
            }
            .navigationDestination(for: MobilePlayerConfig.self) { config in
                MobilePlayerView(config: config)
                    .edgesIgnoringSafeArea(.all)
                    .persistentSystemOverlays(.hidden)
                    .id(config.id)
            }
        }
        .persistentSystemOverlays(.hidden)
    }
    
    private func didClickToggleAppIcon() {
        if UIApplication.shared.alternateIconName == nil {
            UIApplication.shared.setAlternateIconName("AppIconLegacy")
        } else {
            UIApplication.shared.setAlternateIconName(nil)
        }
    }
    
    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 130 : 77), spacing: 0)]
        return LazyVGrid(columns: gridLayout, alignment: .leading, spacing: 0) {
            ForEach(suggestedItems) { item in
                Button {
                    didSelectSuggestedItem(item)
                } label: {
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
                }
                .aspectRatio(1, contentMode: .fit)
                .contextMenu { suggestedItemContextMenu(item: item) }
            }
        }
    }
    
    private func gridItemText(_ text: String, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .regular))
                .lineLimit(2)
                .foregroundColor(.white)
                .padding(.horizontal, 1)
                .background(Color.black.opacity(0.7))
                .cornerRadius(3)
                .padding(.leading, 4)
                .padding(.bottom, 3)
                .multilineTextAlignment(.leading)
                .onTapGesture { onTap() }
            Spacer()
        }
    }
    private func suggestedItemContextMenu(item: SuggestedItem) -> some View {
        Group {
            Text(item.name)
            Button(action: {
                didSelectSuggestedItem(item)
            }) {
                HStack {
                    Images.play
                    Text(Strings.play)
                }
            }
        }
    }
    
    private func didSelectSuggestedItem(_ item: SuggestedItem) {
        navigationPath.append(MobilePlayerConfig(initialItemId: item.id))
        Haptic.selectionChanged()
    }
    
    private func showRandomPlayer() {
        navigationPath.append(MobilePlayerConfig(initialItemId: nil))
        Haptic.selectionChanged()
    }
    
}
