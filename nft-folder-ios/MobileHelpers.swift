// ∅ 2026 lil org

import UIKit
import SwiftUI

struct Images {
    
    static let close = Image(systemName: "xmark")
    static let preferences = Image(systemName: "gearshape")
    static let play = Image(systemName: "play")
    
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
    static let dismissHorizontalEdgeExclusion: CGFloat = 44
    static let dismissUnderlayFadeCompletionProgress: CGFloat = 0.68
    static let controlsRevealVelocity: CGFloat = 80
    static let controlsRevealVerticalIntentRatio: CGFloat = 1.05
    static let playerPageGap: CGFloat = 23
    static let pageBoundaryRevealTranslation: CGFloat = 18
    static let pageBoundaryRevealHorizontalIntentRatio: CGFloat = 1.15

}
