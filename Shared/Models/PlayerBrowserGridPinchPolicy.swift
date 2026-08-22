// ∅ 2026 lil org

import CoreGraphics
import Foundation

nonisolated enum PlayerBrowserGridPinchPolicy: Sendable {

    static let activationScaleDeviation: CGFloat = 0.04
    static let overshootMaximumDeviation: CGFloat = 0.05
    static let underPlaneInstallScale: CGFloat = 0.995
    static let underPlaneDiscardScale: CGFloat = 1.08
    static let overPlaneInstallScale: CGFloat = 1.005
    static let overPlaneDiscardScale: CGFloat = 1
    static let planeRetargetHysteresis: CGFloat = 0.06
    static let settleCommitIntervalProgress: CGFloat = 0.2
    /// Photos settles a released pinch on a critically damped spring whose
    /// period is 0.5s — `UIView.animate(springDuration: 0.5, bounce: 0)`.
    static let settleAngularFrequency: CGFloat = 2 * .pi / 0.5
    /// Terminal render snaps the residual offset, so rest must be genuinely
    /// sub-pixel even for one-column cells (~800 device pixels wide):
    /// 0.0002 in log scale is under a fifth of a pixel there.
    static let settleRestLogDistance: CGFloat = 0.000_2
    static let settleRestLogVelocity: CGFloat = 0.003
    static let maximumSettleTickDuration: CGFloat = 1.0 / 15

    static func effectiveScaleAfterActivation(_ effectiveScale: CGFloat) -> CGFloat {
        guard effectiveScale.isFinite, effectiveScale > 0 else { return 1 }
        return effectiveScale / activationTrimDivisor(effectiveScale)
    }

    /// What `effectiveScaleAfterActivation` divided out. The release
    /// multiplies it back to recover the physical pinch ratio, so it has to
    /// come from here — reconstructing it from `activationScaleDeviation`
    /// encodes the shape of the trim a second time.
    static func activationTrimDivisor(_ effectiveScale: CGFloat) -> CGFloat {
        guard effectiveScale.isFinite, effectiveScale > 0 else { return 1 }
        if effectiveScale > 1 + activationScaleDeviation {
            return 1 + activationScaleDeviation
        }
        if effectiveScale < 1 - activationScaleDeviation {
            return 1 - activationScaleDeviation
        }
        return effectiveScale
    }

    static func rubberBandedScale(
        _ scale: CGFloat,
        minimumRatio: CGFloat,
        maximumRatio: CGFloat
    ) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return 1 }
        let sanitizedMinimum = minimumRatio.isFinite && minimumRatio > 0
            ? min(minimumRatio, 1)
            : 1
        let sanitizedMaximum = maximumRatio.isFinite && maximumRatio > 0
            ? max(maximumRatio, 1)
            : 1
        if scale > sanitizedMaximum {
            return sanitizedMaximum * overshootScale(
                forEffectiveScale: scale / sanitizedMaximum
            )
        }
        // The densest lattice exactly fills the viewport, so any overshoot
        // below it renders a grid narrower than the screen and uncovers the
        // background at both edges. Photos clamps here — pinching hard past
        // its densest level still shows 0px of background — so we do too.
        // The zoom-in end has no such floor: that tile already overflows.
        return max(scale, sanitizedMinimum)
    }

    static func overshootScale(forEffectiveScale effectiveScale: CGFloat) -> CGFloat {
        guard effectiveScale.isFinite, effectiveScale > 0 else { return 1 }
        return 1 + overshootMaximumDeviation * tanh(log(effectiveScale) * 2)
    }

    /// Photos completes the crossfade on a clock even when the fingers stop
    /// moving mid-transition: measured alpha follows
    /// `max(scale-progress, time-progress)`, the time channel finishing in
    /// ~713ms of plane lifetime with an ease-in shape. A fast pinch's scale
    /// channel outruns this; the clock only shows when the pinch stalls.
    static let interactionFadeDuration: CGFloat = 0.713

    static func interactionFadeTimeProgress(elapsed: CGFloat) -> CGFloat {
        guard elapsed.isFinite, elapsed > 0, interactionFadeDuration > 0 else {
            return 0
        }
        let linearProgress = min(elapsed / interactionFadeDuration, 1)
        return linearProgress * linearProgress
    }

    static func interactionFadeElapsed(
        matchingProgress progress: CGFloat
    ) -> CGFloat {
        guard progress.isFinite, progress > 0, interactionFadeDuration > 0 else {
            return 0
        }
        return interactionFadeDuration * sqrt(min(progress, 1))
    }

    /// Photos ignores flick magnitude — a violent flick never slams across
    /// distant modes — but a release that is STILL MOVING toward the next
    /// mode commits across its boundary (measured: an out-then-back pinch
    /// released at ~1.05 with inward motion commits one step outward).
    /// The projection is capped at the adjacent mode beyond the current
    /// positional target, so motion direction seals at most one boundary.
    static let releaseProjectionInterval: CGFloat = 0.18
    /// The recognizer's last movement can be long before the lift: a
    /// stationary tail must release positionally, not on stale motion.
    static let releaseMotionHoldTimeout: TimeInterval = 0.1
    /// The release rate spans this much recent sample history, so a brief
    /// decelerating tail cannot mask an otherwise-moving release.
    static let releaseMotionRateWindow: TimeInterval = 0.1
    static let releaseMotionLogScaleNoiseFloor: CGFloat = 0.000_2

    static func projectedReleaseScale(
        scale: CGFloat,
        logScaleRate: CGFloat,
        itemWidthRatios: [CGFloat]
    ) -> CGFloat {
        guard scale.isFinite, scale > 0,
              logScaleRate.isFinite, logScaleRate != 0 else {
            return scale
        }
        let logScale = log(scale)
        var projected = logScale
            + logScaleRate * releaseProjectionInterval
        guard let currentTargetIndex = settleTargetIndex(
            scale: scale,
            itemWidthRatios: itemWidthRatios
        ) else {
            return scale
        }
        let orderedIndices = itemWidthRatios.indices.sorted {
            itemWidthRatios[$0] < itemWidthRatios[$1]
        }
        guard let currentPosition = orderedIndices.firstIndex(
            of: currentTargetIndex
        ) else {
            return scale
        }
        let targetPosition = currentPosition + (logScaleRate > 0 ? 1 : -1)
        guard orderedIndices.indices.contains(targetPosition) else { return scale }
        let boundaryCap = log(itemWidthRatios[orderedIndices[targetPosition]])
        projected = logScaleRate > 0
            ? min(projected, boundaryCap)
            : max(projected, boundaryCap)
        return exp(projected)
    }

    /// Positional ladder walk. Each adjacent boundary commits after one fifth
    /// of its log-distance, so deep physical travel can cross modes while
    /// flick magnitude cannot project across them.
    static func settleTargetIndex(
        scale: CGFloat,
        itemWidthRatios: [CGFloat]
    ) -> Int? {
        guard scale.isFinite, scale > 0 else { return nil }
        let logRatios = itemWidthRatios.map { ratio -> CGFloat in
            guard ratio.isFinite, ratio > 0 else { return .nan }
            return log(ratio)
        }
        guard !logRatios.isEmpty, logRatios.allSatisfy({ !$0.isNaN }) else {
            return nil
        }

        let orderedIndices = logRatios.indices.sorted {
            logRatios[$0] < logRatios[$1]
        }
        guard let initialPosition = orderedIndices.firstIndex(where: {
            logRatios[$0] == 0
        }) else {
            return nil
        }

        let logScale = log(scale)
        guard logScale != 0 else { return orderedIndices[initialPosition] }
        let step = logScale > 0 ? 1 : -1
        var position = initialPosition
        while orderedIndices.indices.contains(position + step) {
            let nextPosition = position + step
            let fromLogRatio = logRatios[orderedIndices[position]]
            let toLogRatio = logRatios[orderedIndices[nextPosition]]
            let threshold = fromLogRatio
                + (toLogRatio - fromLogRatio) * settleCommitIntervalProgress
            let crossesThreshold = step > 0
                ? logScale >= threshold
                : logScale <= threshold
            guard crossesThreshold else { break }
            position = nextPosition
        }
        return orderedIndices[position]
    }

    /// One critically damped spring step in symmetric log-scale space.
    static func settleSpringStep(
        logOffset: CGFloat,
        logVelocity: CGFloat,
        deltaTime: CGFloat
    ) -> (logOffset: CGFloat, logVelocity: CGFloat) {
        guard logOffset.isFinite, logVelocity.isFinite else { return (0, 0) }
        let omega = settleAngularFrequency
        let clampedDeltaTime = min(
            max(deltaTime.isFinite ? deltaTime : 0, 0),
            maximumSettleTickDuration
        )
        let decay = exp(-omega * clampedDeltaTime)
        let coefficient = logVelocity + omega * logOffset
        let steppedOffset = (logOffset + coefficient * clampedDeltaTime) * decay
        let steppedVelocity = (logVelocity
            - omega * coefficient * clampedDeltaTime) * decay
        return (steppedOffset, steppedVelocity)
    }

    static func isSettleSpringAtRest(
        logOffset: CGFloat,
        logVelocity: CGFloat
    ) -> Bool {
        abs(logOffset) < settleRestLogDistance
            && abs(logVelocity) < settleRestLogVelocity
    }

}
