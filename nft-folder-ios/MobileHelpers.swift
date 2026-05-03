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

    static let verticalPagingAxisDominance: CGFloat = 1.15
    static let verticalPagingMinimumVelocity: CGFloat = 160
    static let verticalPagingCommitTranslation: CGFloat = 50
    static let verticalPagingCommitVelocity: CGFloat = 450
    static let topDismissVerticalIntentRatio: CGFloat = 0.8
    static let pageTransitionSettleDelay: TimeInterval = 0.18

    static func topDismissActivationHeight(safeAreaTop: CGFloat) -> CGFloat {
        max(132, safeAreaTop + 96)
    }

}
