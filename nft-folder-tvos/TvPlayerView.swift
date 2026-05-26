// ∅ 2026 lil org

import SwiftUI

struct TvPlayerView: View {
    
    @StateObject private var playerModel: PlayerModel
    @State private var showInfoPopover = false
    
    init(initialItemId: String?) {
        _playerModel = StateObject(wrappedValue: Self.makePlayerModel(initialItemId: initialItemId))
    }

    private static func makePlayerModel(initialItemId: String?) -> PlayerModel {
        if let initialItemId {
            return PlayerModel(collectionId: initialItemId)
        }
        return PlayerModel(specificCollectionId: nil, notTokenId: nil)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            TvGeneratedTokenView(contentString: playerModel.currentToken.html, fallbackURL: fallbackURL()).edgesIgnoringSafeArea(.all)
                .focusable()
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        DispatchQueue.main.async { playerModel.goBack() }
                    case .right:
                        DispatchQueue.main.async { playerModel.goForward() }
                    case .up:
                        DispatchQueue.main.async { playerModel.goForward() }
                    case .down:
                        DispatchQueue.main.async { playerModel.goBack() }
                    default:
                        break
                    }
                }
                .onPlayPauseCommand {
                    showInfoPopover.toggle()
                }
            
            if showInfoPopover {
                infoPopoverView()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                    .padding()
            }
        }
    }
    
    private func fallbackURL() -> URL? {
        return URL(string: "https://media-proxy.artblocks.io/\(playerModel.currentToken.address)/\(playerModel.currentToken.id).png")
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
