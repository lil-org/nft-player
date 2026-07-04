// ∅ 2026 lil org

import UIKit
import SwiftUI

enum MobilePlayerPageLayoutMetrics {
    static let spreadCardSpacing: CGFloat = 8
    static let denseSpreadCardSpacing: CGFloat = 1
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
}

struct MobileStaticImageSpreadGrid: Equatable {
    let columnCount: Int
    let rowCount: Int
    let spacing: CGFloat

    static func grid(
        for pageLayout: MobilePlayerPageLayout,
        imageCount: Int,
        fitting viewportSize: CGSize
    ) -> MobileStaticImageSpreadGrid? {
        guard imageCount == pageLayout.pageSize else { return nil }

        switch pageLayout {
        case .fourPerPage:
            return MobileStaticImageSpreadGrid(
                columnCount: 2,
                rowCount: 2,
                spacing: MobilePlayerPageLayoutMetrics.spreadCardSpacing
            )
        case .sixPerPage:
            let usesHorizontalLayout = viewportSize.width >= viewportSize.height
            return MobileStaticImageSpreadGrid(
                columnCount: usesHorizontalLayout ? 3 : 2,
                rowCount: usesHorizontalLayout ? 2 : 3,
                spacing: MobilePlayerPageLayoutMetrics.denseSpreadCardSpacing
            )
        case .onePerPage:
            return nil
        }
    }
}

struct MobileStaticImageSpreadLayout: Equatable {
    let pageLayout: MobilePlayerPageLayout
    let imageSizes: [CGSize]

    func contentSize(fitting viewportSize: CGSize) -> CGSize {
        guard !imageSizes.isEmpty else { return viewportSize }

        if let grid = grid(fitting: viewportSize) {
            return gridContentSize(fitting: viewportSize, grid: grid)
        }

        let axis = linearAxis(fitting: viewportSize)
        let imageCount = CGFloat(imageSizes.count)
        let totalSpacing = CGFloat(imageSizes.count - 1) * MobilePlayerPageLayoutMetrics.spreadCardSpacing
        let maximumSlotSize: CGSize
        switch axis {
        case .horizontal:
            maximumSlotSize = CGSize(
                width: max((viewportSize.width - totalSpacing) / imageCount, 0),
                height: viewportSize.height
            )
        case .vertical:
            maximumSlotSize = CGSize(
                width: viewportSize.width,
                height: max((viewportSize.height - totalSpacing) / imageCount, 0)
            )
        @unknown default:
            maximumSlotSize = viewportSize
        }

        let slotSize = imageSlotSize(fitting: maximumSlotSize)
        switch axis {
        case .horizontal:
            return CGSize(
                width: slotSize.width * imageCount + totalSpacing,
                height: slotSize.height
            )
        case .vertical:
            return CGSize(
                width: slotSize.width,
                height: slotSize.height * imageCount + totalSpacing
            )
        @unknown default:
            return slotSize
        }
    }

    func axis(fitting viewportSize: CGSize) -> NSLayoutConstraint.Axis? {
        guard grid(fitting: viewportSize) == nil else { return nil }
        return linearAxis(fitting: viewportSize)
    }

    func grid(fitting viewportSize: CGSize) -> MobileStaticImageSpreadGrid? {
        MobileStaticImageSpreadGrid.grid(
            for: pageLayout,
            imageCount: imageSizes.count,
            fitting: viewportSize
        )
    }

    func itemFrames(fitting viewportSize: CGSize) -> [CGRect] {
        guard !imageSizes.isEmpty,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return []
        }

        let contentSize = contentSize(fitting: viewportSize)
        let contentOrigin = CGPoint(
            x: (viewportSize.width - contentSize.width) / 2,
            y: (viewportSize.height - contentSize.height) / 2
        )

        if let grid = grid(fitting: viewportSize) {
            let spacing = grid.spacing
            let columnCount = CGFloat(grid.columnCount)
            let rowCount = CGFloat(grid.rowCount)
            let slotWidth = max((contentSize.width - CGFloat(grid.columnCount - 1) * spacing) / columnCount, 0)
            let slotHeight = max((contentSize.height - CGFloat(grid.rowCount - 1) * spacing) / rowCount, 0)
            return imageSizes.indices.map { index in
                let column = CGFloat(index % grid.columnCount)
                let row = CGFloat(index / grid.columnCount)
                return CGRect(
                    x: contentOrigin.x + column * (slotWidth + spacing),
                    y: contentOrigin.y + row * (slotHeight + spacing),
                    width: slotWidth,
                    height: slotHeight
                )
            }
        }

        let axis = linearAxis(fitting: viewportSize)
        let spacing = MobilePlayerPageLayoutMetrics.spreadCardSpacing
        switch axis {
        case .horizontal:
            let slotWidth = max(
                (contentSize.width - CGFloat(imageSizes.count - 1) * spacing) / CGFloat(imageSizes.count),
                0
            )
            return imageSizes.indices.map { index in
                CGRect(
                    x: contentOrigin.x + CGFloat(index) * (slotWidth + spacing),
                    y: contentOrigin.y,
                    width: slotWidth,
                    height: contentSize.height
                )
            }
        case .vertical:
            let slotHeight = max(
                (contentSize.height - CGFloat(imageSizes.count - 1) * spacing) / CGFloat(imageSizes.count),
                0
            )
            return imageSizes.indices.map { index in
                CGRect(
                    x: contentOrigin.x,
                    y: contentOrigin.y + CGFloat(index) * (slotHeight + spacing),
                    width: contentSize.width,
                    height: slotHeight
                )
            }
        @unknown default:
            return [CGRect(origin: contentOrigin, size: contentSize)]
        }
    }

    static func centeredAspectFitRect(for contentSize: CGSize, in bounds: CGRect) -> CGRect {
        let fittedSize = MobilePlayerAspectFitLayout.size(for: contentSize, fitting: bounds.size)
        guard fittedSize.width > 0, fittedSize.height > 0 else { return bounds }

        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func linearAxis(fitting viewportSize: CGSize) -> NSLayoutConstraint.Axis {
        viewportSize.width >= viewportSize.height ? .horizontal : .vertical
    }

    private func gridContentSize(fitting viewportSize: CGSize, grid: MobileStaticImageSpreadGrid) -> CGSize {
        let columnCount = CGFloat(grid.columnCount)
        let rowCount = CGFloat(grid.rowCount)
        let horizontalSpacing = CGFloat(grid.columnCount - 1) * grid.spacing
        let verticalSpacing = CGFloat(grid.rowCount - 1) * grid.spacing
        let maximumSlotSize = CGSize(
            width: max((viewportSize.width - horizontalSpacing) / columnCount, 0),
            height: max((viewportSize.height - verticalSpacing) / rowCount, 0)
        )
        let slotSize = imageSlotSize(fitting: maximumSlotSize)
        return CGSize(
            width: slotSize.width * columnCount + horizontalSpacing,
            height: slotSize.height * rowCount + verticalSpacing
        )
    }

    private func imageSlotSize(fitting maximumSize: CGSize) -> CGSize {
        imageSizes
            .map { MobilePlayerAspectFitLayout.size(for: $0, fitting: maximumSize) }
            .reduce(.zero) { result, slotSize in
                CGSize(
                    width: max(result.width, slotSize.width),
                    height: max(result.height, slotSize.height)
                )
            }
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
    static let playerDismissPinchActivationScale: CGFloat = 0.96
    static let playerDismissPinchZoomInFailureScale: CGFloat = 1.01
    static let playerDismissPinchFullProgressScale: CGFloat = 0.62
    static let playerDismissPinchMinimumPresentationScaleRatio: CGFloat = 0.72
    static let playerDismissPinchCompletionProgress: CGFloat = 0.5
    static let playerDismissPinchMinimumVelocityCommitProgress: CGFloat = 0.18
    static let playerDismissPinchVelocityProjectionDuration: CGFloat = 0.18
    static let playerDismissPinchFastVelocity: CGFloat = 1.1
    static let playerDismissPinchInteractiveMaximumDimmingFade: CGFloat = 0.22
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
    static let cardExpandPinchActivationScale: CGFloat = 1.04
    static let cardExpandPinchZoomOutFailureScale: CGFloat = 0.99
    static let cardExpandPinchFullProgressScale: CGFloat = 1.9
    static let cardExpandPinchCommitScaleMultiplier: CGFloat = 0.98
    static let cardExpandPinchVelocityCommitMinimumScaleMultiplier: CGFloat = 0.9
    static let cardExpandPinchVelocityProjectionDuration: CGFloat = 0.18
    static let cardExpandPinchFastVelocity: CGFloat = 0.95
    static let cardExpandPinchOverscaleResistance: CGFloat = 0.42
    static let cardExpandPinchCenterRubberBandResistance: CGFloat = 0.55
    static let cardExpandPinchTargetPullRampScaleDistance: CGFloat = 0.18
    static let cardExpandPinchMinimumTargetPullProgress: CGFloat = 0.08
    static let cardExpandPinchMaximumTargetPullProgress: CGFloat = 0.42
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
