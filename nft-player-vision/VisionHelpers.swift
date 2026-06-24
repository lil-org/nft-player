// ∅ 2026 lil org

import SwiftUI

struct WindowId {
    
    static let collections = "collections"
    static let player = "player"
    static let blackImmersiveBackdrop = "blackImmersiveBackdrop"
    
}

struct Images {
    
    static let preferences = Image(systemName: "gearshape")
    static let bookmark = Image(systemName: "bookmark")
    static let bookmarkFill = Image(systemName: "bookmark.fill")
    static let play = Image(systemName: "play")
    static let enterImmersiveMode = Image(systemName: "moon.stars.fill")
    static let exitImmersiveMode = Image(systemName: "sun.max.fill")
    
}

@MainActor
final class VisionImmersiveModeModel: ObservableObject {
    @Published var isEnabled = false
    @Published private(set) var isSpaceVisible = false

    func didShowSpace() {
        isSpaceVisible = true
    }

    func didHideSpace() {
        isSpaceVisible = false
        isEnabled = false
    }
}

struct VisionBlackImmersiveBackdropView: View {

    @EnvironmentObject private var immersiveMode: VisionImmersiveModeModel

    var body: some View {
        Color.clear
            .preferredSurroundingsEffect(immersiveMode.isEnabled ? .colorMultiply(.black) : nil)
            .onAppear {
                immersiveMode.didShowSpace()
            }
            .onDisappear {
                immersiveMode.didHideSpace()
            }
    }

}
