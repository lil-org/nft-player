// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerCardMinimizePinchPolicyTests: XCTestCase {

    func testProgressUsesCanonicalScalesAndClamps() {
        XCTAssertEqual(
            PlayerCardMinimizePinchPolicy.progress(forScale: 1),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerCardMinimizePinchPolicy.progress(forScale: 0.96),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerCardMinimizePinchPolicy.progress(forScale: 0.79),
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerCardMinimizePinchPolicy.progress(forScale: 0.62),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerCardMinimizePinchPolicy.progress(forScale: 1.2),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlayerCardMinimizePinchPolicy.progress(forScale: 0.4),
            1,
            accuracy: 0.000_001
        )
    }

    func testStaticCompletionBracketsFloatingPointHalfProgressBoundary() {
        let algebraicHalfProgressScale =
            PlayerCardMinimizePinchPolicy.activationScale
                - (PlayerCardMinimizePinchPolicy.activationScale
                    - PlayerCardMinimizePinchPolicy.fullProgressScale)
                    * PlayerCardMinimizePinchPolicy.completionProgress
        let completingScale = algebraicHalfProgressScale.nextDown
        let cancellingScale = algebraicHalfProgressScale

        XCTAssertEqual(completingScale.nextUp, cancellingScale)
        XCTAssertGreaterThanOrEqual(
            PlayerCardMinimizePinchPolicy.progress(forScale: completingScale),
            PlayerCardMinimizePinchPolicy.completionProgress
        )
        XCTAssertTrue(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: completingScale,
            velocity: 0
        ))
        XCTAssertLessThan(
            PlayerCardMinimizePinchPolicy.progress(forScale: cancellingScale),
            PlayerCardMinimizePinchPolicy.completionProgress
        )
        XCTAssertFalse(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: cancellingScale,
            velocity: 0
        ))
    }

    func testVelocityCommitRequiresMinimumProgress() {
        let minimumVelocityScale =
            PlayerCardMinimizePinchPolicy.activationScale
                - (PlayerCardMinimizePinchPolicy.activationScale
                    - PlayerCardMinimizePinchPolicy.fullProgressScale)
                    * PlayerCardMinimizePinchPolicy.minimumVelocityCommitProgress

        XCTAssertTrue(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: minimumVelocityScale,
            velocity: -1.2
        ))
        XCTAssertFalse(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: minimumVelocityScale + 0.000_001,
            velocity: -10
        ))
    }

    func testVelocityProjectionAndDirection() {
        XCTAssertTrue(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: 0.89,
            velocity: -0.6
        ))
        XCTAssertTrue(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: 0.89,
            velocity: -1.2
        ))
        XCTAssertFalse(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: 0.89,
            velocity: 0
        ))
        XCTAssertFalse(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: 0.89,
            velocity: 1.2
        ))
        XCTAssertFalse(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: 0.93,
            velocity: -10
        ))
    }

    func testMagnificationSampleAccumulatesDeltasAndUsesSeconds() {
        var sample = PlayerCardMagnificationSample(
            magnificationDelta: -0.01,
            timestamp: 10
        )

        XCTAssertEqual(sample.scale, 0.99, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, 0, accuracy: 0.000_001)

        sample.add(magnificationDelta: -0.04, timestamp: 10.02)

        XCTAssertEqual(sample.scale, 0.95, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, -2, accuracy: 0.000_001)
    }

    func testMagnificationSampleIncludesFinalEventDelta() {
        var sample = PlayerCardMagnificationSample(
            magnificationDelta: -0.01,
            timestamp: 10
        )
        sample.add(magnificationDelta: -0.04, timestamp: 10.02)
        sample.add(magnificationDelta: -0.02, timestamp: 10.04)

        XCTAssertEqual(sample.scale, 0.93, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, -1, accuracy: 0.000_001)
    }

    func testStationaryPauseAdvancesVelocityBaselineWithoutChangingScale() {
        var sample = PlayerCardMagnificationSample(
            magnificationDelta: -0.01,
            timestamp: 10
        )
        sample.add(magnificationDelta: -0.06, timestamp: 10.1)
        let scaleBeforePause = sample.scale

        sample.add(magnificationDelta: 0, timestamp: 11.1)

        XCTAssertEqual(sample.scale, scaleBeforePause, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, 0, accuracy: 0.000_001)

        sample.add(magnificationDelta: -0.04, timestamp: 11.12)

        XCTAssertEqual(sample.scale, 0.89, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, -2, accuracy: 0.000_001)
        XCTAssertTrue(PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: sample.scale,
            velocity: sample.velocity
        ))
    }

    func testZeroDeltaFinalEventProducesZeroVelocity() {
        var sample = PlayerCardMagnificationSample(
            magnificationDelta: 0,
            timestamp: 10
        )
        sample.add(magnificationDelta: -0.04, timestamp: 10.02)
        sample.add(magnificationDelta: 0, timestamp: 10.04)

        XCTAssertEqual(sample.scale, 0.96, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, 0, accuracy: 0.000_001)
    }

    func testNonIncreasingTimestampsProduceZeroVelocityAndAdvanceBaseline() {
        var sample = PlayerCardMagnificationSample(
            magnificationDelta: 0,
            timestamp: 10
        )
        sample.add(magnificationDelta: -0.02, timestamp: 10)

        XCTAssertEqual(sample.scale, 0.98, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, 0, accuracy: 0.000_001)

        sample.add(magnificationDelta: -0.02, timestamp: 9)

        XCTAssertEqual(sample.scale, 0.96, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, 0, accuracy: 0.000_001)

        sample.add(magnificationDelta: -0.03, timestamp: 9.5)

        XCTAssertEqual(sample.scale, 0.93, accuracy: 0.000_001)
        XCTAssertEqual(sample.velocity, -0.06, accuracy: 0.000_001)
    }
}
