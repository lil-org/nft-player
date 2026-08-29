// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridTransitionRuntimeTests: XCTestCase {
    typealias Runtime = PlayerBrowserGridTransitionRuntime
    typealias Coordinator = PlayerBrowserGridInteractionCoordinator

    private static let ratioProvider: Coordinator.RatioProvider = { mode in
        MobileCollectionBrowserGridMode.allCases.map { target in
            Coordinator.ModeRatio(
                mode: target,
                itemWidthRatio: CGFloat(mode.columnCount)
                    / CGFloat(target.columnCount)
            )
        }
    }

    func testFrameCoalescingAppliesOnlyTheLatestPinchFrame() {
        var runtime = Runtime()
        let began = frame(scale: 1, y: 100, timestamp: 0)
        XCTAssertTrue(runtime.beginPinch(
            began,
            currentMode: .threeColumns,
            at: 0,
            ratioProvider: Self.ratioProvider
        ).isEmpty)
        XCTAssertTrue(runtime.hasPendingPinchFrame)
        XCTAssertTrue(runtime.needsFrames)

        runtime.stagePinch(frame(scale: 1.2, y: 120, timestamp: 0.01))
        let latest = frame(scale: 1.5, y: 150, timestamp: 0.02)
        runtime.stagePinch(latest)

        let output = runtime.advanceFrame(to: 0.03)

        XCTAssertEqual(output.appliedPinchFrame, latest)
        XCTAssertFalse(runtime.hasPendingPinchFrame)
        XCTAssertEqual(runtime.phase, .interacting)
        XCTAssertTrue(output.effects.contains(.beginInteraction))
        XCTAssertEqual(renderedPanDeltaY(output.effects), 0)
        XCTAssertEqual(
            renderedScale(output.effects),
            PlayerBrowserGridPinchPolicy.effectiveScaleAfterActivation(1.5)
        )
    }

    func testTerminalPinchFlushesThePendingFrameBeforeRelease() {
        var runtime = Runtime()
        _ = runtime.beginPinch(
            frame(scale: 1, timestamp: 0),
            currentMode: .threeColumns,
            at: 0,
            ratioProvider: Self.ratioProvider
        )
        let pending = frame(scale: 1.7, timestamp: 0.02)
        runtime.stagePinch(pending)

        let output = runtime.endPinch(
            scale: 1.7,
            reduceMotion: false,
            timestamp: 0.03
        )

        XCTAssertEqual(output.appliedPinchFrame, pending)
        XCTAssertFalse(runtime.hasPendingPinchFrame)
        XCTAssertEqual(runtime.phase, .settling)
        XCTAssertFalse(runtime.needsSettleFrames)
        XCTAssertFalse(runtime.needsInteractionFadeFrames)
        XCTAssertTrue(output.effects.contains(.startDisplayLink))
        XCTAssertTrue(output.effects.contains(.startInteractionFadeTicks))

        acknowledgeTimingEffects(in: output, runtime: &runtime, at: 0.04)

        XCTAssertTrue(runtime.needsSettleFrames)
        XCTAssertFalse(runtime.needsInteractionFadeFrames)
    }

    func testCancelledPinchFlushesPendingGeometry() {
        var runtime = Runtime()
        _ = runtime.beginPinch(
            frame(scale: 1, timestamp: 0),
            currentMode: .threeColumns,
            at: 0,
            ratioProvider: Self.ratioProvider
        )
        let pending = frame(scale: 0.8, y: 460, timestamp: 0.02)
        runtime.stagePinch(pending)

        let output = runtime.cancelPinch(reduceMotion: false, at: 0.03)

        XCTAssertEqual(output.appliedPinchFrame, pending)
        XCTAssertTrue(output.effects.contains(.beginInteraction))
        XCTAssertEqual(runtime.phase, .settling)

        XCTAssertFalse(runtime.needsSettleFrames)
        acknowledgeTimingEffects(in: output, runtime: &runtime, at: 0.04)
        XCTAssertTrue(runtime.needsSettleFrames)
    }

    func testDiscardPendingPinchStopsFrameDemand() {
        var runtime = Runtime()
        runtime.stagePinch(frame(scale: 1.2, timestamp: 0))

        runtime.discardPendingPinch()

        XCTAssertFalse(runtime.hasPendingPinchFrame)
        XCTAssertFalse(runtime.needsFrames)
    }

    func testFinishInteractionClearsAllInteractionFrameDemand() {
        var runtime = Runtime()
        _ = runtime.beginPinch(
            frame(scale: 1, timestamp: 0),
            currentMode: .threeColumns,
            at: 0,
            ratioProvider: Self.ratioProvider
        )
        runtime.stagePinch(frame(scale: 1.5, timestamp: 0.01))
        let output = runtime.advanceFrame(to: 0.02)
        XCTAssertTrue(output.effects.contains(.startInteractionFadeTicks))
        acknowledgeTimingEffects(in: output, runtime: &runtime, at: 0.02)
        XCTAssertTrue(runtime.needsInteractionFadeFrames)

        runtime.recordRendererEffect(
            .finishInteraction(settlesPosition: false),
            at: 0.03
        )

        XCTAssertFalse(runtime.hasPendingPinchFrame)
        XCTAssertFalse(runtime.needsSettleFrames)
        XCTAssertFalse(runtime.needsInteractionFadeFrames)
        XCTAssertFalse(runtime.needsFrames)
    }

    func testMenuSettleStartsAtDelayedTimingAcknowledgement() {
        var runtime = Runtime()
        let start = runtime.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            at: 10,
            ratioProvider: Self.ratioProvider
        )

        XCTAssertEqual(runtime.phase, .settling)
        XCTAssertFalse(runtime.needsSettleFrames)
        XCTAssertFalse(runtime.needsFrames)
        XCTAssertTrue(start.effects.contains(.startDisplayLink))

        let acknowledgement = runtime.acknowledgeTimingEffect(
            .startDisplayLink,
            at: 20
        )

        XCTAssertTrue(acknowledgement.isEmpty)
        XCTAssertTrue(runtime.needsSettleFrames)
        XCTAssertTrue(runtime.needsFrames)

        let zeroDeltaFrame = runtime.advanceFrame(to: 20)
        XCTAssertEqual(renderedScale(zeroDeltaFrame.effects), 1)

        let firstMovingFrame = runtime.advanceFrame(to: 20.1)
        XCTAssertNotEqual(renderedScale(firstMovingFrame.effects), 1)

        for step in 1...100 where runtime.needsSettleFrames {
            let timestamp = 20.1 + Double(step) / 60
            let output = runtime.advanceFrame(to: timestamp)
            acknowledgeTimingEffects(
                in: output,
                runtime: &runtime,
                at: timestamp
            )
        }

        XCTAssertFalse(runtime.needsSettleFrames)
        XCTAssertEqual(runtime.phase, .settling)
    }

    func testReduceMotionDoesNotRequestFrames() {
        var runtime = Runtime()

        let output = runtime.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: true
            ),
            at: 0,
            ratioProvider: Self.ratioProvider
        )

        XCTAssertFalse(runtime.needsFrames)
        XCTAssertTrue(output.effects.contains(.beginInteraction))
        XCTAssertTrue(output.effects.contains(.applyMode(.large)))
    }

    func testCoverExpiresAtDeterministicDeadline() throws {
        var runtime = Runtime(configuration: .init(
            coverFadeDuration: 0.25,
            coverRemovalGrace: 0.05,
            rendererFadeDuration: 0.12,
            firstImageFadeWindow: 1.5
        ))
        let cover = runtime.installCover(
            contentOffset: CGPoint(x: 0, y: 40),
            at: 1
        )
        let fadingCover = runtime.beginCoverFade(
            generation: cover.generation,
            at: 1
        )

        XCTAssertEqual(
            try XCTUnwrap(fadingCover?.removalDeadline),
            1.3,
            accuracy: 0.000_1
        )
        XCTAssertTrue(runtime.hasCover)
        XCTAssertTrue(runtime.blocksSelection)
        XCTAssertTrue(runtime.needsFrames)
        XCTAssertNil(runtime.advanceFrame(to: 1.299).expiredCoverGeneration)

        let expiry = runtime.advanceFrame(to: 1.3)

        XCTAssertEqual(expiry.expiredCoverGeneration, cover.generation)
        XCTAssertFalse(runtime.hasCover)
        XCTAssertFalse(runtime.blocksSelection)
        XCTAssertFalse(runtime.needsFrames)
    }

    func testCoverReplacementIgnoresStaleFadeAndExpiry() {
        var runtime = Runtime()
        let first = runtime.installCover(contentOffset: .zero, at: 0)
        _ = runtime.beginCoverFade(generation: first.generation, at: 0)
        let second = runtime.installCover(
            contentOffset: CGPoint(x: 0, y: 100),
            at: 0.1
        )

        XCTAssertGreaterThan(second.generation, first.generation)
        XCTAssertNil(runtime.beginCoverFade(
            generation: first.generation,
            at: 0.2
        ))
        XCTAssertNil(runtime.removeCover(generation: first.generation))
        XCTAssertNil(runtime.advanceFrame(to: 0.3).expiredCoverGeneration)
        XCTAssertEqual(runtime.activeCover, second)

        _ = runtime.beginCoverFade(generation: second.generation, at: 0.3)
        XCTAssertEqual(
            runtime.advanceFrame(to: 0.601).expiredCoverGeneration,
            second.generation
        )
    }

    func testCoverContentOffsetUpdatesOnlyMatchingGeneration() {
        var runtime = Runtime()
        let cover = runtime.installCover(contentOffset: .zero, at: 0)

        XCTAssertNil(runtime.updateCoverContentOffset(
            generation: cover.generation + 1,
            contentOffset: CGPoint(x: 0, y: 50)
        ))
        let updated = runtime.updateCoverContentOffset(
            generation: cover.generation,
            contentOffset: CGPoint(x: 0, y: 50)
        )

        XCTAssertEqual(updated?.contentOffset, CGPoint(x: 0, y: 50))
        XCTAssertEqual(runtime.activeCover?.contentOffset, CGPoint(x: 0, y: 50))
    }

    func testInstallPlaneClearsLogicalContentFade() throws {
        var runtime = Runtime()
        let firstPlane = try XCTUnwrap(Coordinator.Plane(
            fromMode: .threeColumns,
            toMode: .large,
            itemWidthRatio: 3
        ))
        runtime.recordRendererEffect(.installPlane(firstPlane), at: 0)
        runtime.recordRendererEffect(
            .renderSettle(
                id: firstPlane.id,
                scale: 2,
                settleProgress: 0.5,
                presentationProgress: 0.5,
                panDeltaY: 0
            ),
            at: 0.1
        )
        XCTAssertTrue(runtime.planeChangeNeedsVisualCover(at: 0.1))

        let secondPlane = try XCTUnwrap(Coordinator.Plane(
            fromMode: .threeColumns,
            toMode: .fiveColumns,
            itemWidthRatio: 0.6
        ))
        runtime.recordRendererEffect(.installPlane(secondPlane), at: 0.2)

        XCTAssertFalse(runtime.planeChangeNeedsVisualCover(at: 0.2))

        runtime.recordRendererEffect(
            .renderSettle(
                id: secondPlane.id,
                scale: 1,
                settleProgress: 0.5,
                presentationProgress: 0.5,
                panDeltaY: 0
            ),
            at: 0.3
        )
        runtime.recordRendererEffect(
            .renderZoom(planeId: secondPlane.id, scale: 1, panDeltaY: 0),
            at: 0.31
        )
        XCTAssertTrue(runtime.planeChangeNeedsVisualCover(at: 0.32))

        runtime.recordRendererEffect(.installPlane(firstPlane), at: 0.33)

        XCTAssertFalse(runtime.planeChangeNeedsVisualCover(at: 0.33))
    }

    func testRenderSettleTracksLogicalFadeUntilItsDeadline() throws {
        var runtime = Runtime()
        let plane = try XCTUnwrap(Coordinator.Plane(
            fromMode: .threeColumns,
            toMode: .large,
            itemWidthRatio: 3
        ))
        runtime.recordRendererEffect(
            .renderSettle(
                id: plane.id,
                scale: 2,
                settleProgress: 0.5,
                presentationProgress: 0.5,
                panDeltaY: 0
            ),
            at: 0
        )

        runtime.recordRendererEffect(
            .renderSettle(
                id: plane.id,
                scale: 1,
                settleProgress: 0,
                presentationProgress: 0,
                panDeltaY: 0
            ),
            at: 0.1
        )

        XCTAssertTrue(runtime.planeChangeNeedsVisualCover(at: 0.219))
        XCTAssertFalse(runtime.planeChangeNeedsVisualCover(at: 0.22))
    }

    func testRenderZoomTracksLogicalFadeUntilItsDeadline() throws {
        var runtime = Runtime()
        let plane = try XCTUnwrap(Coordinator.Plane(
            fromMode: .threeColumns,
            toMode: .large,
            itemWidthRatio: 3
        ))
        runtime.recordRendererEffect(
            .renderSettle(
                id: plane.id,
                scale: 2,
                settleProgress: 0.5,
                presentationProgress: 0.5,
                panDeltaY: 0
            ),
            at: 0
        )

        runtime.recordRendererEffect(
            .renderZoom(planeId: plane.id, scale: 1, panDeltaY: 0),
            at: 0.1
        )

        XCTAssertTrue(runtime.planeChangeNeedsVisualCover(at: 0.219))
        XCTAssertFalse(runtime.planeChangeNeedsVisualCover(at: 0.22))
    }

    func testFirstImageFadeWindowStartsOnlyWhenExplicitlyRequested() {
        var runtime = Runtime()
        let id = UUID()

        runtime.recordRendererEffect(
            .commitPlane(id: id, mode: .large),
            at: 2
        )

        XCTAssertFalse(runtime.fadesFirstImage(at: 2))

        runtime.beginFirstImageFade(at: 2)

        XCTAssertTrue(runtime.fadesFirstImage(at: 3.499))
        XCTAssertFalse(runtime.fadesFirstImage(at: 3.5))
    }

    func testInvalidationClearsAllOwnedState() {
        var runtime = Runtime()
        _ = runtime.beginPinch(
            frame(scale: 1, timestamp: 0),
            currentMode: .threeColumns,
            at: 0,
            ratioProvider: Self.ratioProvider
        )
        let cover = runtime.installCover(contentOffset: .zero, at: 0)
        _ = runtime.beginCoverFade(generation: cover.generation, at: 0)
        runtime.beginFirstImageFade(at: 0)

        XCTAssertEqual(runtime.invalidate(), cover.generation)
        XCTAssertEqual(runtime.phase, .idle)
        XCTAssertFalse(runtime.hasPendingPinchFrame)
        XCTAssertFalse(runtime.needsFrames)
        XCTAssertFalse(runtime.hasCover)
        XCTAssertFalse(runtime.fadesFirstImage(at: 0))
    }

    private func frame(
        scale: CGFloat,
        y: CGFloat = 400,
        timestamp: TimeInterval
    ) -> Runtime.PinchFrame {
        Runtime.PinchFrame(
            scale: scale,
            viewLocation: CGPoint(x: 200, y: y),
            timestamp: timestamp
        )
    }

    private func renderedScale(
        _ effects: [Coordinator.Effect]
    ) -> CGFloat? {
        effects.reversed().compactMap { effect in
            switch effect {
            case let .renderZoom(_, scale, _),
                 let .renderSettle(_, scale, _, _, _):
                scale
            default:
                nil
            }
        }.first
    }

    private func renderedPanDeltaY(
        _ effects: [Coordinator.Effect]
    ) -> CGFloat? {
        effects.reversed().compactMap { effect in
            switch effect {
            case let .renderZoom(_, _, panDeltaY),
                 let .renderSettle(_, _, _, _, panDeltaY):
                panDeltaY
            default:
                nil
            }
        }.first
    }

    private func acknowledgeTimingEffects(
        in output: Runtime.Output,
        runtime: inout Runtime,
        at timestamp: TimeInterval
    ) {
        for effect in output.effects {
            _ = runtime.acknowledgeTimingEffect(effect, at: timestamp)
        }
    }
}
