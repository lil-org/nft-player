// ∅ 2026 lil org

import UIKit
import SwiftUI

enum MobilePlayerBrowserLayoutMetrics {
    static let itemSpacing: CGFloat = 4
    static let screenEdgeInset: CGFloat = 2
}

enum MobilePlayerAspectFitLayout {
    static func size(for contentSize: CGSize, fitting maximumSize: CGSize) -> CGSize {
        guard contentSize.width > 0,
              contentSize.height > 0,
              maximumSize.width > 0,
              maximumSize.height > 0 else {
            return .zero
        }

        let scale = min(
            maximumSize.width / contentSize.width,
            maximumSize.height / contentSize.height
        )
        return CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
    }

    static func centeredRect(for contentSize: CGSize, in bounds: CGRect) -> CGRect {
        let fittedSize = size(for: contentSize, fitting: bounds.size)
        guard fittedSize.width > 0, fittedSize.height > 0 else { return bounds }

        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

extension CGSize {
    var validOrDefault: CGSize {
        guard width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return self
    }
}

struct PlayerMediaPlaceholderSpec: Equatable {
    private static let neutralColor = UIColor(white: 0.65, alpha: 0.18)

    let aspectSize: CGSize
    let usesNativeMetalCardCornerMask: Bool

    var color: UIColor {
        Self.neutralColor
    }

    init(
        thumbnailAspectRatio: ThumbnailAspectRatio?,
        usesNativeMetalCardCornerMask: Bool = false
    ) {
        self.init(
            aspectSize: thumbnailAspectRatio?.size ?? CGSize(width: 1, height: 1),
            usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask
        )
    }

    init(
        aspectSize: CGSize,
        usesNativeMetalCardCornerMask: Bool = false
    ) {
        self.aspectSize = aspectSize.validOrDefault
        self.usesNativeMetalCardCornerMask = usesNativeMetalCardCornerMask
    }
}

private enum NativeMetalCardCornerMask {
    static func update(
        layer: CALayer,
        bounds: CGRect,
        isEnabled: Bool,
        appliedBounds: inout CGRect?
    ) {
        guard isEnabled,
              bounds.width > 0,
              bounds.height > 0 else {
            layer.mask = nil
            appliedBounds = nil
            return
        }

        guard appliedBounds != bounds || !(layer.mask is CAShapeLayer) else { return }

        let maskLayer = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        maskLayer.frame = bounds
        maskLayer.path = UIBezierPath(
            roundedRect: bounds,
            byRoundingCorners: .allCorners,
            cornerRadii: NativeMetalCardLayout.cardCornerRadii(in: bounds.size)
        ).cgPath
        layer.mask = maskLayer
        appliedBounds = bounds
    }
}

final class PlayerMediaPlaceholderView: UIView {
    private static let transitionDuration: TimeInterval = 0.12

    private let shapeLayer = CALayer()
    private var spec: PlayerMediaPlaceholderSpec?
    private var appliedNativeMetalCardMaskBounds: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with spec: PlayerMediaPlaceholderSpec) {
        layer.removeAllAnimations()
        shapeLayer.removeAllAnimations()
        self.spec = spec
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.backgroundColor = spec.color.cgColor
        CATransaction.commit()
        isHidden = false
        alpha = 1
        setNeedsLayout()
    }

    func setHidden(_ hidden: Bool, animated: Bool) {
        guard animated else {
            layer.removeAllAnimations()
            alpha = hidden ? 0 : 1
            isHidden = hidden
            return
        }

        if hidden {
            guard !isHidden else { return }
            UIView.animate(
                withDuration: Self.transitionDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.alpha = 0
            } completion: { finished in
                if finished, self.alpha == 0 {
                    self.isHidden = true
                }
            }
        } else {
            guard isHidden || alpha < 1 else { return }
            isHidden = false
            UIView.animate(
                withDuration: Self.transitionDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.alpha = 1
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let spec else {
            shapeLayer.frame = .zero
            updateNativeMetalCardCornerMask()
            return
        }

        shapeLayer.frame = MobilePlayerAspectFitLayout.centeredRect(
            for: spec.aspectSize,
            in: bounds
        )
        updateNativeMetalCardCornerMask()
    }

    private func setUp() {
        makeBackgroundTransparent()
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        layer.addSublayer(shapeLayer)
    }

    private func updateNativeMetalCardCornerMask() {
        NativeMetalCardCornerMask.update(
            layer: shapeLayer,
            bounds: shapeLayer.bounds,
            isEnabled: spec?.usesNativeMetalCardCornerMask == true,
            appliedBounds: &appliedNativeMetalCardMaskBounds
        )
    }
}

final class NativeMetalCardCornerMaskedImageView: UIImageView {

    private var appliedNativeMetalCardMaskBounds: CGRect?

    var usesNativeMetalCardCornerMask = false {
        didSet {
            guard oldValue != usesNativeMetalCardCornerMask else { return }
            updateNativeMetalCardCornerMask()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateNativeMetalCardCornerMask()
    }

    private func updateNativeMetalCardCornerMask() {
        NativeMetalCardCornerMask.update(
            layer: layer,
            bounds: bounds,
            isEnabled: usesNativeMetalCardCornerMask,
            appliedBounds: &appliedNativeMetalCardMaskBounds
        )
    }
}

struct Images {
    
    static let close = Image(systemName: "xmark")
    static let preferences = Image(systemName: "gearshape")
    static let play = Image(systemName: "play")
    static let share = Image(systemName: "square.and.arrow.up")
    static let bookmark = Image(systemName: "bookmark")
    static let bookmarkFill = Image(systemName: "bookmark.fill")
    
    static let appIcon: UIImage? = {
        let icons = (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconFiles = icons?["CFBundleIconFiles"] as? [String]
        return UIImage(named: iconFiles?.last ?? "AppIcon")
    }()
    
}

struct Haptic {
    
    static func selectionChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
}

enum MobilePlayerBackgroundColor {

    static let defaultColor = UIColor.black
    private static var cachedColorsByCollectionId = [String: UIColor]()

    static func color(for config: MobilePlayerConfig) -> UIColor {
        color(forCollectionId: config.specificToken?.fullCollectionId ?? config.initialItemId)
    }

    static func color(for token: GeneratedToken) -> UIColor {
        color(forCollectionId: token.fullCollectionId)
    }

    static func color(forCollectionId collectionId: String?) -> UIColor {
        guard let collectionId else {
            return defaultColor
        }
        if let cachedColor = cachedColorsByCollectionId[collectionId] {
            return cachedColor
        }

        let color = MobileCollectionCatalog.playerBackgroundColor(specificCollectionId: collectionId)
            .flatMap(UIColor.init(playerBackgroundColorString:))
            ?? defaultColor

        cachedColorsByCollectionId[collectionId] = color
        return color
    }

}

extension UIView {

    func makeBackgroundTransparent() {
        backgroundColor = .clear
        isOpaque = false
    }

}

extension UIColor {

    convenience init?(playerBackgroundColorString string: String) {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized.lowercased() {
        case "black":
            self.init(red: 0, green: 0, blue: 0, alpha: 1)
            return
        case "white":
            self.init(red: 1, green: 1, blue: 1, alpha: 1)
            return
        default:
            break
        }

        var hex = normalized
        if hex.hasPrefix("#") {
            hex.removeFirst()
        } else if hex.lowercased().hasPrefix("0x") {
            hex.removeFirst(2)
        }

        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }

        guard hex.count == 6,
              let value = UInt32(hex, radix: 16) else {
            return nil
        }

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func isVisuallyEqual(to otherColor: UIColor, tolerance: CGFloat = 0.01) -> Bool {
        guard let lhs = rgbaComponents,
              let rhs = otherColor.rgbaComponents else {
            return self == otherColor
        }

        return abs(lhs.red - rhs.red) <= tolerance
            && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
            && abs(lhs.alpha - rhs.alpha) <= tolerance
    }

    private var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return (red, green, blue, alpha)
    }

}

enum MobilePlayerGestureTuning {

    static let dismissVerticalIntentRatio: CGFloat = 1.45
    static let dismissVelocityProjectionDuration: CGFloat = 0.07
    static let dismissInitialVelocity: CGFloat = 120
    static let cardMinimizeProgressDistance: CGFloat = 360
    static let cardMinimizeInteractiveOtherCardsRevealCompletionProgress: CGFloat = 0.68
    static let cardMinimizeInteractiveOtherCardsMaximumRevealProgress: CGFloat = 0.42
    static let cardMinimizeMinimumTranslation: CGFloat = 110
    static let cardMinimizeTranslationHeightRatio: CGFloat = 0.18
    static let cardMinimizeFastSwipeVelocity: CGFloat = 1150
    static let cardMinimizeMinimumFastSwipeTranslation: CGFloat = 80
    static let cardMinimizePinchActivationScale: CGFloat = 0.96
    static let cardMinimizePinchZoomInFailureScale: CGFloat = 1.01
    static let cardMinimizePinchFullProgressScale: CGFloat = 0.62
    static let cardMinimizePinchMinimumPresentationScaleRatio: CGFloat = 0.72
    static let cardMinimizePinchCompletionProgress: CGFloat = 0.5
    static let cardMinimizePinchMinimumVelocityCommitProgress: CGFloat = 0.18
    static let cardMinimizePinchVelocityProjectionDuration: CGFloat = 0.18
    static let cardMinimizePinchFastVelocity: CGFloat = 1.1
    static let controlsRevealVelocity: CGFloat = 150
    static let controlsRevealMinimumTranslation: CGFloat = 44
    static let controlsRevealVerticalIntentRatio: CGFloat = 1.45
    static let controlsRevealHorizontalScrollTolerance: CGFloat = 8
    static let playerPageGap: CGFloat = 23
    static let pageBoundaryRevealTranslation: CGFloat = 18
    static let pageBoundaryRevealHorizontalIntentRatio: CGFloat = 1.15
    static let edgeTapNavigationWidth: CGFloat = 44
    static let edgeTapHighlightWidth: CGFloat = 50
    static let edgeTapMaximumMovement: CGFloat = 12
    static let edgeTapHighlightMaximumMovement: CGFloat = edgeTapMaximumMovement / 2
    static let edgeTapHighlightActivationDelay: TimeInterval = 0.3
    static let edgeTapHighlightTapFlashDuration: TimeInterval = 0.09
    static let edgeTapHighlightFadeInDuration: TimeInterval = 0.1
    static let edgeTapHighlightFadeOutDuration: TimeInterval = 0.34
    static let playerMaximumZoomScale: CGFloat = 4
    static let playerDoubleTapZoomScale: CGFloat = 2.5
    static let playerZoomResetTolerance: CGFloat = 0.01
    static let playerZoomEdgePaginationTolerance: CGFloat = 2

}

enum MobileBottomChromeSpacing {

    private static let rectangularDisplayPadding: CGFloat = 12
    private static let roundedDisplayMinimumPadding: CGFloat = 16
    private static let roundedDisplaySafeAreaOverlap: CGFloat = 10
    private static let continueViewingRoundedDisplayPadding: CGFloat = 14

    static func padding(forSafeAreaBottom safeAreaBottom: CGFloat) -> CGFloat {
        guard safeAreaBottom > 0 else { return rectangularDisplayPadding }

        return max(roundedDisplayMinimumPadding, safeAreaBottom - roundedDisplaySafeAreaOverlap)
    }

    static func continueViewingPadding(forSafeAreaBottom safeAreaBottom: CGFloat) -> CGFloat {
        guard safeAreaBottom > 0 else { return rectangularDisplayPadding }

        return continueViewingRoundedDisplayPadding
    }

}

struct CapsuleButtonBackground: View {
    var isInteractive = false

    var body: some View {
        if #available(iOS 26.0, *) {
            liquidGlassBase
        } else {
            fallbackBase
        }
    }

    private var fallbackBase: some View {
        Capsule()
            .fill(.black.opacity(0.66))
            .background(.ultraThinMaterial, in: Capsule())
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var liquidGlassBase: some View {
        if isInteractive {
            Capsule()
                .fill(.white.opacity(0.08))
                .glassEffect(.regular.tint(.black.opacity(0.42)).interactive(), in: Capsule())
                .glassEffectTransition(.materialize)
        } else {
            Capsule()
                .fill(.white.opacity(0.08))
                .glassEffect(.regular.tint(.black.opacity(0.42)), in: Capsule())
                .glassEffectTransition(.materialize)
        }
    }
}
