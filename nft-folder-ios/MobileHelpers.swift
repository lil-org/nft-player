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
