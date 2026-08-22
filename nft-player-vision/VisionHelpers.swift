// ∅ 2026 lil org

import Observation
import SwiftUI

enum VisionOrnamentMetrics {
    static let spacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 24
    static let bottomPadding: CGFloat = 10
    static let controlButtonSize: CGFloat = 46
    static let controlGroupPadding: CGFloat = 4
    static let controlGroupSpacing: CGFloat = 8

    static var controlGroupHeight: CGFloat {
        controlButtonSize + controlGroupPadding * 2
    }

    static var trailingControlReservedWidth: CGFloat {
        controlButtonSize + horizontalPadding + spacing
    }
}

struct VisionOrnamentIconButton: View {
    let image: Image
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    init(
        image: Image,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.image = image
        self.accessibilityLabel = accessibilityLabel
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VisionOrnamentIconLabel(image: image)
        }
        .visionOrnamentIconControlStyle()
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct VisionOrnamentIconLabel: View {
    let image: Image

    var body: some View {
        image
            .font(.title3.weight(.semibold))
            .frame(
                width: VisionOrnamentMetrics.controlButtonSize,
                height: VisionOrnamentMetrics.controlButtonSize
            )
    }
}

extension View {
    func visionOrnamentIconControlStyle() -> some View {
        buttonStyle(.plain)
            .background(.regularMaterial, in: Circle())
            .contentShape(Circle())
    }

    func visionOrnamentControlGroupStyle() -> some View {
        padding(VisionOrnamentMetrics.controlGroupPadding)
            .frame(height: VisionOrnamentMetrics.controlGroupHeight)
            .background(.ultraThinMaterial, in: Capsule())
            .clipShape(Capsule())
    }
}

struct WindowId {
    
    static let collections = "collections"
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

@MainActor @Observable
final class VisionImmersiveModeModel {
    var isEnabled = false
    private(set) var isSpaceVisible = false

    func didShowSpace() {
        isSpaceVisible = true
    }

    func didHideSpace() {
        isSpaceVisible = false
        isEnabled = false
    }
}

struct VisionBlackImmersiveBackdropView: View {

    @Environment(VisionImmersiveModeModel.self) private var immersiveMode

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
