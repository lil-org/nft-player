// ∅ 2026 lil org

import SwiftUI
import UIKit

struct MobilePlayerConfig: Hashable, Codable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
}

private let doNotShowInstructionsTmp = true

struct MobilePlayerView: View {
    
    private let initialConfig: MobilePlayerConfig
    
    @State private var showControls = false
    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentCoordinate = PlayerCoordinate(x: 0, y: 0)
    
    init(config: MobilePlayerConfig) {
        self.initialConfig = config
    }

    var body: some View {
        ZStack {
            FourDirectionalPlayerContainerView(initialConfig: initialConfig, onCoordinateUpdate: { newCoordinate in
                DispatchQueue.main.async {
                    self.currentCoordinate = newCoordinate
                    self.currentToken = MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: newCoordinate)
                    updateExternalDisplayToken(currentToken)
                }
            }).edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    showControls.toggle()
                }
                .onLongPressGesture {
                    showControls.toggle()
                }
                .statusBar(hidden: isAllowedToHideStatusBar && !showControls)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                infoMenu
            }
        }
        .onDisappear {
            updateExternalDisplayToken(GeneratedToken.empty)
            MobilePlaybackController.shared.stopAndDisconnect(uuid: initialConfig.id)
        }
        .onAppear {
            if !isAllowedToHideStatusBar {
                let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                let window = scene?.windows.first
                let topSafeArea = window?.safeAreaInsets.top ?? 0
                if topSafeArea < 44 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAllowedToHideStatusBar = true
                        }
                    }
                } else {
                    isAllowedToHideStatusBar = true
                }
            }
        }
    }
    
    private var infoMenu: some View {
        Menu {
            if !doNotShowInstructionsTmp, let instructions = currentToken.instructions {
                Text(instructions)
            }
            Button(Strings.viewOnBlockscout, action: viewOnWeb)
            Text(currentToken.displayName)
        } label: {
            Images.info
        }
    }
    
    private func viewOnWeb() {
        if let url = currentToken.url {
            UIApplication.shared.open(url)
        }
    }
    
}
