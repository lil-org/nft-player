// ∅ 2026 lil org

import UIKit
import SwiftUI

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

    func isOpaqueAndVisuallyEqual(to otherColor: UIColor, tolerance: CGFloat = 0.01) -> Bool {
        guard let lhs = rgbaComponents else { return false }

        return lhs.alpha > 0.98 && isVisuallyEqual(to: otherColor, tolerance: tolerance)
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
    static let dismissProgressDistance: CGFloat = 720
    static let dismissVelocityProjectionDuration: CGFloat = 0.07
    static let dismissFastSwipeVelocity: CGFloat = 1450
    static let dismissMinimumFastSwipeTranslation: CGFloat = 140
    static let dismissMinimumTranslation: CGFloat = 180
    static let dismissTranslationHeightRatio: CGFloat = 0.28
    static let dismissInitialVelocity: CGFloat = 120
    static let dismissUnderlayFadeCompletionProgress: CGFloat = 0.68
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
