// ∅ 2026 lil org

import CoreGraphics
import Foundation

nonisolated enum PlayerCardMinimizePinchPolicy: Sendable {

    static let activationScale: CGFloat = 0.96
    static let zoomInFailureScale: CGFloat = 1.01
    static let fullProgressScale: CGFloat = 0.62
    static let minimumPresentationScaleRatio: CGFloat = 0.72
    static let completionProgress: CGFloat = 0.5
    static let minimumVelocityCommitProgress: CGFloat = 0.18
    static let velocityProjectionDuration: CGFloat = 0.18
    static let fastVelocity: CGFloat = 1.1

    static func progress(forScale scale: CGFloat) -> CGFloat {
        let progressDistance = activationScale - fullProgressScale
        guard progressDistance > 0 else { return 0 }

        return min(max((activationScale - scale) / progressDistance, 0), 1)
    }

    static func shouldComplete(scale: CGFloat, velocity: CGFloat) -> Bool {
        let currentProgress = progress(forScale: scale)
        let projectedScale = scale + min(velocity, 0) * velocityProjectionDuration
        let projectedProgress = max(
            currentProgress,
            progress(forScale: projectedScale)
        )
        let hasEnoughProgressForVelocityCommit =
            currentProgress >= minimumVelocityCommitProgress
        return currentProgress >= completionProgress
            || (hasEnoughProgressForVelocityCommit
                && (projectedProgress >= completionProgress
                    || velocity < -fastVelocity))
    }
}

nonisolated struct PlayerCardMagnificationSample: Sendable {

    private(set) var scale: CGFloat
    private(set) var velocity: CGFloat
    private var lastTimestamp: TimeInterval

    init(magnificationDelta: CGFloat, timestamp: TimeInterval) {
        scale = 1 + magnificationDelta
        velocity = 0
        lastTimestamp = timestamp
    }

    mutating func add(magnificationDelta: CGFloat, timestamp: TimeInterval) {
        scale += magnificationDelta
        let elapsed = timestamp - lastTimestamp
        velocity = elapsed > 0
            ? magnificationDelta / CGFloat(elapsed)
            : 0
        lastTimestamp = timestamp
    }
}
