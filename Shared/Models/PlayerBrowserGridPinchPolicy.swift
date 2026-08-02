// ∅ 2026 lil org

import CoreGraphics
import Foundation

enum PlayerBrowserGridPinchPolicy {

    static let completionProgress: CGFloat = 0.5
    static let minimumVelocityCommitProgress: CGFloat = 0.12
    static let commitVelocity: CGFloat = 1.6
    static let activationScaleDeviation: CGFloat = 0.04
    static let overshootMaximumDeviation: CGFloat = 0.05
    static let minimumSettleDuration: Double = 0.12
    static let maximumSettleDuration: Double = 0.26

    static func progress(
        effectiveScale: CGFloat,
        itemWidthRatio: CGFloat
    ) -> CGFloat {
        guard effectiveScale.isFinite,
              effectiveScale > 0,
              itemWidthRatio.isFinite,
              itemWidthRatio > 0,
              itemWidthRatio != 1 else {
            return 0
        }
        return (effectiveScale - 1) / (itemWidthRatio - 1)
    }

    static func effectiveScaleAfterActivation(_ effectiveScale: CGFloat) -> CGFloat {
        guard effectiveScale.isFinite, effectiveScale > 0 else { return 1 }
        if effectiveScale > 1 + activationScaleDeviation {
            return effectiveScale / (1 + activationScaleDeviation)
        }
        if effectiveScale < 1 - activationScaleDeviation {
            return effectiveScale / (1 - activationScaleDeviation)
        }
        return 1
    }

    static func shouldComplete(
        progress: CGFloat,
        velocityTowardTarget: CGFloat
    ) -> Bool {
        guard progress > 0 else { return false }
        let sanitizedVelocity = velocityTowardTarget.isFinite
            ? velocityTowardTarget
            : 0
        if sanitizedVelocity <= -commitVelocity {
            return false
        }
        if sanitizedVelocity >= commitVelocity {
            return progress >= minimumVelocityCommitProgress
        }
        return progress >= completionProgress
    }

    static func overshootScale(forEffectiveScale effectiveScale: CGFloat) -> CGFloat {
        guard effectiveScale.isFinite, effectiveScale > 0 else { return 1 }
        return 1 + overshootMaximumDeviation * tanh(log(effectiveScale) * 2)
    }

    static func settleDuration(remainingProgress: CGFloat) -> Double {
        guard remainingProgress.isFinite else { return minimumSettleDuration }
        let span = min(abs(Double(remainingProgress)), 1)
        return minimumSettleDuration
            + (maximumSettleDuration - minimumSettleDuration) * span
    }
}
