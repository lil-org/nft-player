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
    
}

enum MobilePlayerGestureTuning {

    static let dismissVerticalIntentRatio: CGFloat = 0.65
    static let dismissProgressDistance: CGFloat = 560
    static let dismissVelocityProjectionDuration: CGFloat = 0.16
    static let dismissFastSwipeVelocity: CGFloat = 420
    static let dismissMinimumFastSwipeTranslation: CGFloat = 16
    static let dismissMinimumTranslation: CGFloat = 88
    static let dismissTranslationHeightRatio: CGFloat = 0.13

}
