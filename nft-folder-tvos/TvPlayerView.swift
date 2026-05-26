// ∅ 2026 lil org

import SwiftUI

struct TvPlayerView: View {
    
    @StateObject private var playerModel: PlayerModel
    @State private var showInfoPopover = false
    @State private var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    
    init(initialItemId: String?) {
        _playerModel = StateObject(wrappedValue: Self.makePlayerModel(initialItemId: initialItemId))
    }

    private static func makePlayerModel(initialItemId: String?) -> PlayerModel {
        TvPlayerPrewarmer.preparedModel(initialItemId: initialItemId)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            mediaView(for: playerModel.currentToken)
                .edgesIgnoringSafeArea(.all)
                .focusable()
                .onMoveCommand { direction in
                    switch direction {
                    case .left, .down:
                        navigateBack()
                    case .right, .up:
                        navigateForward()
                    default:
                        break
                    }
                }
                .onPlayPauseCommand {
                    showInfoPopover.toggle()
                }
                .onAppear {
                    playerModel.markCurrentTokenViewed()
                }
                .onChange(of: playerModel.currentToken) { _ in
                    playerModel.markCurrentTokenViewed()
                }
            
            if showInfoPopover {
                infoPopoverView()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                    .padding()
            }
        }
    }

    private func mediaView(for token: GeneratedToken) -> some View {
        let context = CollectionCatalog.tokenContext(for: token)
        return TvPlayerMediaView(
            token: token,
            context: context,
            preferredPrefetchDirection: preferredPrefetchDirection
        )
        .id(TvPlayerMediaIdentity(token: token, context: context))
    }

    private func navigateBack() {
        DispatchQueue.main.async {
            preferredPrefetchDirection = .backward
            playerModel.goBack()
        }
    }

    private func navigateForward() {
        DispatchQueue.main.async {
            preferredPrefetchDirection = .forward
            playerModel.goForward()
        }
    }
    
    private func infoPopoverView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(uiImage: Images.generateQRCode(playerModel.currentToken.url?.absoluteString ?? ""))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
        }
        .padding().frame(width: 230)
    }
    
}

private struct TvPlayerMediaIdentity: Hashable {
    let collectionId: String
    let tokenId: String
    let media: GeneratedTokenMedia?

    init(token: GeneratedToken, context: PlayerTokenContext?) {
        self.collectionId = context?.collectionId ?? token.fullCollectionId
        self.tokenId = token.id
        self.media = token.media
    }
}
