// ∅ 2026 lil org

import CoreGraphics
import Foundation

enum PlayerBrowserGridPinchPolicy {

    static let activationScaleDeviation: CGFloat = 0.04
    static let overshootMaximumDeviation: CGFloat = 0.05
    static let velocityProjectionInterval: CGFloat = 0.18
    static let velocityProjectionMaximumTravel: CGFloat = 1.7
    static let underPlaneInstallScale: CGFloat = 0.995
    static let underPlaneDiscardScale: CGFloat = 1.08
    static let overPlaneInstallScale: CGFloat = 1.005
    static let overPlaneDiscardScale: CGFloat = 0.925
    static let planeRetargetHysteresis: CGFloat = 0.06
    /// A release whose last pinch sample is older than this held still first —
    /// its recognizer velocity is stale and must not flick or seed the settle.
    static let velocityHoldTimeout: TimeInterval = 0.1
    static let settleAngularFrequency: CGFloat = 9.5
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
        if scale < sanitizedMinimum {
            return sanitizedMinimum * overshootScale(
                forEffectiveScale: scale / sanitizedMinimum
            )
        }
        return scale
    }

    static func overshootScale(forEffectiveScale effectiveScale: CGFloat) -> CGFloat {
        guard effectiveScale.isFinite, effectiveScale > 0 else { return 1 }
        return 1 + overshootMaximumDeviation * tanh(log(effectiveScale) * 2)
    }

    static func settleTargetIndex(
        scale: CGFloat,
        velocity: CGFloat,
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

        let sanitizedVelocity = velocity.isFinite ? velocity : 0
        let projectionTravel = min(
            max(
                sanitizedVelocity / scale * velocityProjectionInterval,
                -velocityProjectionMaximumTravel
            ),
            velocityProjectionMaximumTravel
        )
        let projectedLogScale = log(scale) + projectionTravel
        return logRatios.indices.min { lhs, rhs in
            abs(projectedLogScale - logRatios[lhs])
                < abs(projectedLogScale - logRatios[rhs])
        }
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

    /// Caps the velocity toward the target at the spring's no-overshoot bound.
    static func settleSeedVelocity(
        forLogOffset logOffset: CGFloat,
        effectiveVelocity: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        guard logOffset.isFinite, logOffset != 0 else { return 0 }
        let limit = settleAngularFrequency * abs(logOffset)
        guard effectiveVelocity.isFinite, scale.isFinite, scale > 0 else {
            return logOffset > 0 ? -limit : limit
        }
        let speed = min(abs(effectiveVelocity / scale), limit)
        return logOffset > 0 ? -speed : speed
    }
}
