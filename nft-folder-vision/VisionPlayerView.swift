// ∅ 2026 lil org

import SwiftUI

struct VisionPlayerConfig: Hashable, Identifiable {
    var id = UUID()
    var initialItemId: String?
}

struct VisionPlayerView: View {
    
    private let onDismiss: () -> Void
    @State private var playerState: VisionPlayerState
    
    init(config: VisionPlayerConfig, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _playerState = State(initialValue: VisionPlayerState(initialCollectionId: config.initialItemId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VisionWebView(htmlString: playerState.currentToken.html)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: onDismiss) {
                    Images.back
                }
                .accessibilityLabel(Strings.back)

                Spacer()

                HStack {
                    Button(action: goBack) {
                        Images.back
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!playerState.canGoBack)
                    .accessibilityLabel(Strings.back)

                    Button(action: goForward) {
                        Images.forward
                    }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!playerState.canGoForward)
                    .accessibilityLabel(Strings.forward)
                }

                Spacer()

                moreMenu
            }
            .padding()
        }
        .background(Color.black)
    }

    private var moreMenu: some View {
        Menu {
            Button(Strings.viewOnBlockExplorer, action: viewOnWeb)
                .disabled(playerState.currentToken.url == nil)
        } label: {
            Images.ellipsis
        }
        .accessibilityLabel(Strings.more)
    }
    
    private func viewOnWeb() {
        if let url = playerState.currentToken.url {
            UIApplication.shared.open(url)
        }
    }

    private func goBack() {
        playerState.goBack()
    }

    private func goForward() {
        playerState.goForward()
    }

}

private struct VisionPlayerState {

    private let collectionId: String?
    private(set) var currentToken: GeneratedToken
    private var tokenIndex: Int
    private let tokenCount: Int

    init(initialCollectionId: String?) {
        let collectionId = initialCollectionId ?? TokenGenerator.nextShuffledCollectionId()
        let tokenCount = collectionId.map { TokenGenerator.tokenCount(specificCollectionId: $0) } ?? 0
        let currentToken = collectionId
            .flatMap { TokenGenerator.generateToken(specificCollectionId: $0, tokenIndex: 0) }
            ?? .empty

        self.collectionId = collectionId
        self.currentToken = currentToken
        self.tokenIndex = 0
        self.tokenCount = tokenCount
    }

    var canGoBack: Bool {
        tokenIndex > 0
    }

    var canGoForward: Bool {
        tokenIndex < tokenCount - 1
    }

    mutating func goBack() {
        showToken(at: tokenIndex - 1)
    }

    mutating func goForward() {
        showToken(at: tokenIndex + 1)
    }

    private mutating func showToken(at index: Int) {
        guard let collectionId,
              index >= 0,
              index < tokenCount,
              let token = TokenGenerator.generateToken(specificCollectionId: collectionId, tokenIndex: index) else {
            return
        }

        tokenIndex = index
        currentToken = token
    }

}
