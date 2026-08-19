// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridPinchPolicyTests: XCTestCase {

    func testQuickReversalBelowSourceCannotProjectAcrossSourceMode() throws {
        let ratios: [CGFloat] = [0.6, 1, 3]
        let logScaleRate = (log(CGFloat(0.75)) - log(CGFloat(0.70))) / 0.02
        let projectedScale = PlayerBrowserGridPinchPolicy
            .projectedReleaseScale(
                scale: 0.75,
                logScaleRate: logScaleRate,
                itemWidthRatios: ratios
            )
        let targetIndex = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: projectedScale,
                itemWidthRatios: ratios
            )
        )

        XCTAssertEqual(projectedScale, 1, accuracy: 0.000_001)
        XCTAssertEqual(ratios[targetIndex], 1)
    }

    func testEndpointMotionTowardSourceRatioAffectsSelection() throws {
        let largeModeRatios: [CGFloat] = [0.2, 1.0 / 3.0, 1]
        let zoomInRate = (log(CGFloat(0.75)) - log(CGFloat(0.70))) / 0.02
        try assertMotionReturnsToSource(
            scale: 0.75,
            logScaleRate: zoomInRate,
            ratios: largeModeRatios
        )

        let fiveColumnRatios: [CGFloat] = [1, 5.0 / 3.0, 5]
        let zoomOutRate = (log(CGFloat(1.25)) - log(CGFloat(1.30))) / 0.02
        try assertMotionReturnsToSource(
            scale: 1.25,
            logScaleRate: zoomOutRate,
            ratios: fiveColumnRatios
        )
    }

    func testProjectionCanCrossUnityOnlyFromTheCurrentSourceTarget() throws {
        let ratios: [CGFloat] = [0.6, 1, 3]
        let sourcewardRate = (log(CGFloat(1.05)) - log(CGFloat(1.09))) / 0.02
        let projectedFromSource = PlayerBrowserGridPinchPolicy
            .projectedReleaseScale(
                scale: 1.05,
                logScaleRate: sourcewardRate,
                itemWidthRatios: ratios
            )
        let sourceTarget = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: projectedFromSource,
                itemWidthRatios: ratios
            )
        )
        XCTAssertEqual(ratios[sourceTarget], 0.6)

        let projectedFromLarge = PlayerBrowserGridPinchPolicy
            .projectedReleaseScale(
                scale: 1.5,
                logScaleRate: sourcewardRate,
                itemWidthRatios: ratios
            )
        let returningTarget = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: projectedFromLarge,
                itemWidthRatios: ratios
            )
        )
        XCTAssertGreaterThanOrEqual(projectedFromLarge, 1)
        XCTAssertEqual(ratios[returningTarget], 1)
    }

    func testInteractionFadeElapsedInvertsTimeProgress() {
        let duration = PlayerBrowserGridPinchPolicy.interactionFadeDuration
        for elapsed in [CGFloat.zero, duration / 4, duration / 2, duration] {
            let progress = PlayerBrowserGridPinchPolicy
                .interactionFadeTimeProgress(elapsed: elapsed)
            XCTAssertEqual(
                PlayerBrowserGridPinchPolicy.interactionFadeElapsed(
                    matchingProgress: progress
                ),
                elapsed,
                accuracy: 0.000_001
            )
        }
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.interactionFadeElapsed(
                matchingProgress: -.infinity
            ),
            0
        )
        XCTAssertEqual(
            PlayerBrowserGridPinchPolicy.interactionFadeElapsed(
                matchingProgress: 2
            ),
            duration
        )
    }

    private func assertMotionReturnsToSource(
        scale: CGFloat,
        logScaleRate: CGFloat,
        ratios: [CGFloat],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let positionalIndex = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: scale,
                itemWidthRatios: ratios
            ),
            file: file,
            line: line
        )
        let projectedScale = PlayerBrowserGridPinchPolicy
            .projectedReleaseScale(
                scale: scale,
                logScaleRate: logScaleRate,
                itemWidthRatios: ratios
            )
        let projectedIndex = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: projectedScale,
                itemWidthRatios: ratios
            ),
            file: file,
            line: line
        )

        XCTAssertNotEqual(ratios[positionalIndex], 1, file: file, line: line)
        XCTAssertEqual(projectedScale, 1, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(ratios[projectedIndex], 1, file: file, line: line)
    }
}
