// ∅ 2026 lil org

import SwiftUI

protocol MacNavigationCommands: AnyObject {
    var isNavigationTransitionInFlight: Bool { get }
    var canGoToPreviousPage: Bool { get }
    var canGoToNextPage: Bool { get }
    var canUseMediaFile: Bool { get }
    func goToPreviousPage()
    func goToNextPage()
    func copyMedia()
    func saveMediaAs()
    func viewOnBlockExplorer()
    /// Returns true when the container took over going back, shrinking the card
    /// into its browser cell instead of sliding screens.
    func navigateBackWithHeroTransition() -> Bool
    func prepareForWindowClose()
}

struct MacRootView: View {

    let model: MacNavigationModel

    var body: some View {
        MacNavigationContainerView(model: model)
            .frame(minWidth: 320, minHeight: 240)
            .toolbar {
                toolbarContent
            }
            .navigationTitle(model.title)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch model.route {
        case .collections:
            collectionsToolbar
        case let .player(_, mode):
            playerToolbar(mode: mode)
        }
    }

    @ToolbarContentBuilder
    private var collectionsToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Spacer()
            ControlGroup {
                settingsMenu
                Button {
                    Navigator.shared.requestShuffledPlayer()
                } label: {
                    Images.shuffle
                }
                .help(Strings.shuffle)
                .accessibilityLabel(Strings.shuffle)
            }
        }
    }

    @ToolbarContentBuilder
    private func playerToolbar(mode: MacPlayerDisplayMode) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.goBack()
            } label: {
                Images.back
            }
            .help(Strings.back)
            .accessibilityLabel(Strings.back)
            .keyboardShortcut("[", modifiers: .command)
        }

        ToolbarItemGroup {
            Spacer()
            if mode == .onePerPage {
                ControlGroup {
                    Button {
                        model.commands?.goToPreviousPage()
                    } label: {
                        Images.back
                    }
                    .help(Strings.back)
                    .accessibilityLabel(Strings.back)
                    .disabled(!model.canGoToPreviousPage)

                    Button {
                        model.commands?.goToNextPage()
                    } label: {
                        Images.forward
                    }
                    .help(Strings.forward)
                    .accessibilityLabel(Strings.forward)
                    .disabled(!model.canGoToNextPage)
                }

                if model.canBookmarkCurrentToken {
                    Button {
                        model.toggleCurrentTokenBookmark()
                    } label: {
                        model.isCurrentTokenBookmarked ? Images.bookmarkFill : Images.bookmark
                    }
                    .help(model.isCurrentTokenBookmarked ? Strings.removeBookmark : Strings.bookmark)
                    .accessibilityLabel(
                        model.isCurrentTokenBookmarked ? Strings.removeBookmark : Strings.bookmark
                    )
                    .disabled(!model.canToggleCurrentTokenBookmark)
                }
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        let canUseMediaFile = model.commands?.canUseMediaFile == true
        return Menu {
            Button(Strings.copyMedia) { model.commands?.copyMedia() }
                .disabled(!canUseMediaFile)
            Button(Strings.saveAs) { model.commands?.saveMediaAs() }
                .disabled(!canUseMediaFile)
            Divider()
            Button(Strings.viewOnBlockExplorer) { model.commands?.viewOnBlockExplorer() }
        } label: {
            Images.ellipsis
        }
        .menuIndicator(.hidden)
        .help(Strings.more)
        .accessibilityLabel(Strings.more)
    }

    private var settingsMenu: some View {
        Menu {
            Text(Strings.sendFeedback)
            Button(Strings.github) { open(URL.github) }
            Button(Strings.mail) { open(URL.mail) }
            Button(Strings.x) { open(URL.x) }
            Divider()
            Button(Strings.rateOnTheAppStore) { open(URL.writeAppStoreReview) }
        } label: {
            Images.gearshape
        }
        .menuIndicator(.hidden)
        .help(Strings.settings)
        .accessibilityLabel(Strings.settings)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

}

struct MacCollectionsScreen: View {

    var body: some View {
        WalletsListView()
            .background(Color(nsColor: .controlBackgroundColor))
    }

}
