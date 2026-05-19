// ∅ 2026 lil org

import SwiftUI

struct VisionPlayerWindowConfig: Hashable, Codable, Identifiable {
    var id = UUID()
    var initialItemId: String?
}

struct VisionPlayerView: View {
    
    @ObservedObject private var playerModel: PlayerModel
    private var config: VisionPlayerWindowConfig
    
    init(config: VisionPlayerWindowConfig) {
        self.config = config
        self.playerModel = PlayerModel(specificCollectionId: config.initialItemId, notTokenId: nil)
    }
    
    var body: some View {
        VStack {
            VisionWebView(htmlString: playerModel.currentToken.html)
            HStack {
                Button(action: {
                    DispatchQueue.main.async { playerModel.goBack() }
                }) {
                    Images.back
                }.keyboardShortcut("[", modifiers: .command)
                Button(action: {
                    DispatchQueue.main.async { playerModel.goForward() }
                }) {
                    Images.forward
                }.keyboardShortcut("]", modifiers: .command)
                Button(action: {
                    DispatchQueue.main.async { playerModel.changeCollection() }
                }) {
                    Images.changeCollection
                }
                Button(action: {
                    DispatchQueue.main.async { playerModel.showingInfoPopover.toggle() }
                }) {
                    Images.info
                }.keyboardShortcut("i", modifiers: .command).popover(isPresented: Binding(
                    get: { playerModel.showingInfoPopover },
                    set: { newValue in
                        DispatchQueue.main.async {
                            playerModel.showingInfoPopover = newValue
                        }
                    }
                ), attachmentAnchor: .point(.top), arrowEdge: .top, content: {
                    infoPopoverView()
                })
            }
            .padding()
        }
    }
    
    private func viewOnWeb() {
        if let url = playerModel.currentToken.url {
            UIApplication.shared.open(url)
        }
    }
    
    private func infoPopoverView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(playerModel.currentToken.displayName)
            Divider()
            Button(Strings.viewOnBlockExplorer, action: viewOnWeb)
            if let instructions = playerModel.currentToken.instructions {
                Divider()
                Text(instructions).font(.body)
            }
        }
        .padding().frame(width: 230)
    }
    
}
