import UIKit

final class MobilePlayerCollectionBrowserCollectionView: UICollectionView {
    struct AccessibilityScrollAttempt {
        let interruptedGridModeSettle: Bool
        let wasScrollMotionActive: Bool
    }

    var onWillAccessibilityScroll: (() -> AccessibilityScrollAttempt)?
    var onAccessibilityScrollResult: ((Bool, AccessibilityScrollAttempt) -> Void)?
    var contentOffsetTarget: ((CGPoint, Bool) -> (
        target: CGPoint,
        settlesAfterApplying: Bool
    ))?
    var onDidApplyImmediateContentOffset: (() -> Void)?

    override func accessibilityScroll(
        _ direction: UIAccessibilityScrollDirection
    ) -> Bool {
        let attempt = onWillAccessibilityScroll?()
        let succeeded = super.accessibilityScroll(direction)
        if let attempt {
            onAccessibilityScrollResult?(succeeded, attempt)
        }
        return succeeded
    }

    override func setContentOffset(
        _ contentOffset: CGPoint,
        animated: Bool
    ) {
        let resolution = contentOffsetTarget?(contentOffset, animated)
        super.setContentOffset(
            resolution?.target ?? contentOffset,
            animated: animated
        )
        if resolution?.settlesAfterApplying == true {
            onDidApplyImmediateContentOffset?()
        }
    }

    func setContentOffsetWithoutResolution(_ contentOffset: CGPoint) {
        super.setContentOffset(contentOffset, animated: false)
    }

    func visualGeometry(
        for layout: MobilePlayerBrowserLayout
    ) -> MobilePlayerBrowserVisualLayoutGeometry {
        MobilePlayerBrowserVisualLayoutGeometry(
            layout: layout,
            mirrorsHorizontally:
                effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
    }
}
