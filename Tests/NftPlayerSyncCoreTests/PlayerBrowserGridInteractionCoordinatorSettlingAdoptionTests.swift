// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

extension PlayerBrowserGridInteractionCoordinatorTests {

    func testPinchDuringSettleAdoptsTheRunningScaleAndResumesOnQuickRelease() {
        var coordinator = Coordinator()
        XCTAssertTrue(coordinator.canBeginPinch)
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)
        XCTAssertFalse(coordinator.canBeginPinch)
        endPinch(&coordinator)
        settlePartway(&coordinator)
        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertTrue(coordinator.canBeginPinch)

        let adoption = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        XCTAssertEqual(
            adoption,
            [.stopDisplayLink, .beginInteraction, .startInteractionFadeTicks],
            "adoption must reclaim what the settle handed back"
        )
        XCTAssertEqual(coordinator.phase, .interacting)
        XCTAssertFalse(coordinator.canBeginPinch)

        let resumed = endPinch(&coordinator)
        XCTAssertFalse(
            resumed.contains(.selectionHaptic),
            "resuming the adopted commit does not repeat the haptic"
        )
        XCTAssertNil(installedPlane(resumed), "the adopted plane is reused")
        let settle = drainSettle(&coordinator, startTime: 101)
        assertCommits(settle, planeId: plane?.id, mode: .large)
    }

    func testAdjustingTheAdoptedPinchReevaluatesTheOutcome() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 2.0)
        endPinch(&coordinator)
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        _ = coordinator.handle(.pinchChanged(sample: makeSample(scale: 0.6)))
        let release = endPinch(&coordinator)
        let settle = drainSettle(&coordinator, startTime: 101)
        XCTAssertFalse(
            committedModes(release + settle).contains(.large),
            "after adjustment the stale adopted target no longer applies"
        )
    }

    func testAdoptedSettleStaysHeldInsideAdjustmentDeadZone() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        let baseline = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.000_5))
        )
        guard case let .renderSettle(id, _, progress, _, _)? = held.last else {
            return XCTFail("expected held settle render, got \(held)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertEqual(
            progress,
            try XCTUnwrap(settleProgress(baseline)),
            accuracy: 0.000_1,
            "movement inside the adjustment dead zone must hold the exact frame"
        )

        _ = coordinator.handle(.pinchCancelled(reduceMotion: false))
        let settle = drainSettle(&coordinator, startTime: 100.08)
        assertCommits(settle, planeId: plane.id, mode: .large)
    }

    func testAdoptedSettleAdjustmentIsOneWayForCancellation() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01))
        )
        let returned = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        guard case let .renderSettle(id, _, progress, _, _)? = returned.last else {
            return XCTFail("expected recovered settle render, got \(returned)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertGreaterThan(progress, 0)

        let cancelled = coordinator.handle(.pinchCancelled(reduceMotion: false))
        let settle = drainSettle(&coordinator, startTime: 100.09)
        XCTAssertTrue(committedModes(cancelled + settle).isEmpty)
        assertDiscards(cancelled + settle, planeId: plane.id)
    }

    func testAdjustedAdoptedSettleRecoversProgressAndFallbackOnOriginalPlane() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        let expired = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.05))
        )
        assertLastRenderedPlaneId(expired, plane.id)
        XCTAssertNil(installedPlane(expired))

        let recovered = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01))
        )
        guard case let .renderSettle(id, _, progress, _, _)? = recovered.last else {
            return XCTFail("expected recovered settle render, got \(recovered)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertGreaterThan(progress, 0)

        let release = endPinch(&coordinator)
        XCTAssertFalse(release.contains(.selectionHaptic))
        XCTAssertNil(installedPlane(release))
        let settle = drainSettle(&coordinator, startTime: 100.09)
        assertCommits(settle, planeId: plane.id, mode: .large)
        XCTAssertEqual(
            coordinator.handle(.rendererFailed),
            [.resetRenderer, .applyMode(.large)]
        )
    }

    func testReplacementPlaneDropsAdoptedFallbackAndEmitsNewHaptic() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .large,
                toMode: .fiveColumns,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let adoptedPlane = try XCTUnwrap(installedPlane(menu))
        var tickTime: TimeInterval = 100
        var runningScale: CGFloat = 1
        _ = coordinator.handle(.settleStarted(timestamp: tickTime))
        advanceSettle(
            &coordinator,
            tickTime: &tickTime,
            runningScale: &runningScale,
            untilAtMost: 0.35
        )
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .large
            ),
            ratioProvider: Self.ratioProvider
        )

        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.05))
        )
        let replacement = try XCTUnwrap(installedPlane(adjusted))
        XCTAssertNotEqual(replacement.id, adoptedPlane.id)
        XCTAssertEqual(replacement.toMode, .threeColumns)

        let release = endPinch(&coordinator)
        XCTAssertTrue(release.contains(.selectionHaptic))
        let settle = drainSettle(
            &coordinator,
            startTime: tickTime + 0.03
        )
        assertCommits(settle, planeId: replacement.id, mode: .threeColumns)
        XCTAssertEqual(
            coordinator.handle(.rendererFailed),
            [.resetRenderer, .finishInteraction(settlesPosition: true)]
        )
    }

    func testAdoptingASettleKeepsThePanAccumulatedBeforeIt() throws {
        var coordinator = Coordinator()
        // Pan 60pt down while zooming, then release into a settle.
        _ = activatePinch(&coordinator, scale: 1.5, centroidY: 400)
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.5, centroidY: 460))
        )
        _ = endPinch(&coordinator)
        XCTAssertEqual(coordinator.phase, .settling)
        _ = coordinator.handle(.settleStarted(timestamp: 100))

        // Grab the settle and drag 40pt further: the plane must sit at the
        // full 100pt, not restart the pan from the re-pinch centroid.
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(
                    scale: 1,
                    centroidY: 460
                ),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        XCTAssertEqual(coordinator.phase, .interacting)
        let dragged = coordinator.handle(
            .pinchChanged(
                sample: makeSample(scale: 1, centroidY: 500)
            )
        )
        let panDeltaY: CGFloat
        switch dragged.last {
        case let .renderZoom(_, _, delta)?:
            panDeltaY = delta
        case let .renderSettle(_, _, _, _, delta)?:
            panDeltaY = delta
        default:
            return XCTFail("expected a render effect, got \(dragged)")
        }
        XCTAssertEqual(panDeltaY, 100, accuracy: 0.000_1)
    }

    func testPinchEndUsesTerminalScaleWithoutMovingThePanAnchor() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 1.05,
            centroidY: 400
        )
        let changed = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.1, centroidY: 460))
        )
        let changedScale = try XCTUnwrap(renderedScale(changed))
        XCTAssertEqual(
            try XCTUnwrap(renderedPanDeltaY(changed)),
            60,
            accuracy: 0.000_1
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: 1.3,
                reduceMotion: false,
                timestamp: nextSampleTimestamp()
            )
        )
        XCTAssertEqual(coordinator.phase, .settling)
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        let firstTick = coordinator.handle(.settleTick(timestamp: 100.02))
        XCTAssertGreaterThan(
            try XCTUnwrap(settleScale(firstTick)),
            changedScale
        )
        XCTAssertEqual(
            try XCTUnwrap(renderedPanDeltaY(firstTick)),
            60,
            accuracy: 0.000_1
        )

        assertCommits(
            released + firstTick + drainSettle(
                &coordinator,
                startTime: 100.02
            ),
            planeId: installedPlane(activation)?.id,
            mode: .large
        )
    }

    func testPinchEndRetargetsAcrossUnityBeforeSettling() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.3)
        let initialPlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(initialPlane.toMode, .large)

        let released = coordinator.handle(.pinchEnded(
            scale: 0.9,
            reduceMotion: false,
            timestamp: nextSampleTimestamp()
        ))
        let replacement = try XCTUnwrap(installedPlane(released))
        XCTAssertEqual(replacement.toMode, .fiveColumns)
        XCTAssertLessThan(
            try XCTUnwrap(released.firstIndex(of: .coverPlaneChange)),
            try XCTUnwrap(released.firstIndex(of: .installPlane(replacement)))
        )
        XCTAssertTrue(released.contains { effect in
            if case let .renderSettle(id, _, _, _, _) = effect {
                return id == replacement.id
            }
            return false
        })
    }

    func testHoldingAnAdoptedSettleKeepsItsCrossfadeProgress() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        // Run the settle far enough that its crossfade is visibly underway.
        var settleProgress: CGFloat = 0
        for step in 1...12 {
            let ticked = coordinator.handle(
                .settleTick(timestamp: 100 + Double(step) * 1.0 / 60)
            )
            if case let .renderSettle(_, _, progress, _, _)? = ticked.last {
                settleProgress = progress
            }
        }
        XCTAssertGreaterThan(
            settleProgress,
            PlayerBrowserGridCrossfade.contentFadeStartSettleProgress,
            "the destination content is already fading in"
        )

        // Grab it and hold still: the render must not rewind to progress 0.
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        guard case let .renderSettle(id, _, heldProgress, _, _)? = held.last else {
            return XCTFail("expected renderSettle while holding, got \(held)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertEqual(heldProgress, settleProgress, accuracy: 0.000_1)

        // Releasing resumes from there rather than replaying the fade.
        let released = endPinch(&coordinator)
        _ = coordinator.handle(.settleStarted(timestamp: 100.36))
        let resumed = coordinator.handle(
            .settleTick(timestamp: 100.36 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, resumedProgress, _, _)? = resumed.last else {
            return XCTFail("expected renderSettle after release, got \(resumed)")
        }
        XCTAssertGreaterThanOrEqual(
            resumedProgress,
            settleProgress,
            "the resumed settle continues the crossfade instead of restarting it"
        )
        XCTAssertFalse(
            released.contains { effect in
                if case .installPlane = effect { return true }
                return false
            },
            "the held plane is reused, not rebuilt"
        )
    }

    func testAdjustingAnAdoptedSettlePreservesItsPlaneProgress() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        var settleProgress: CGFloat = 0
        for step in 1...12 {
            let ticked = coordinator.handle(
                .settleTick(timestamp: 100 + Double(step) / 60)
            )
            if case let .renderSettle(_, _, progress, _, _)? = ticked.last {
                settleProgress = progress
            }
        }
        XCTAssertGreaterThan(
            settleProgress,
            PlayerBrowserGridCrossfade.contentFadeStartSettleProgress
        )

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01))
        )

        guard case let .renderSettle(id, _, adjustedProgress, _, _)? = adjusted.last else {
            return XCTFail("expected preserved settle render, got \(adjusted)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertEqual(
            adjustedProgress,
            settleProgress,
            accuracy: 0.05,
            "the handoff blends the adopted progress into the live pinch "
                + "instead of dropping it and snapping back"
        )
        XCTAssertNil(installedPlane(adjusted))
        XCTAssertFalse(adjusted.contains { effect in
            if case .discardPlane = effect { return true }
            return false
        })

        let released = endPinch(&coordinator)
        XCTAssertNil(installedPlane(released))
        _ = coordinator.handle(.settleStarted(timestamp: 100.36))
        let resumed = coordinator.handle(
            .settleTick(timestamp: 100.36 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, resumedProgress, _, _)? = resumed.last else {
            return XCTFail("expected resumed settle render, got \(resumed)")
        }
        XCTAssertGreaterThanOrEqual(resumedProgress, adjustedProgress)
    }

    /// Grabbing a running settle hands its crossfade over to the live pinch
    /// across the activation travel. Rendered progress must stay monotone and
    /// step-free the whole way through, including the frame the handoff
    /// completes and the release that follows — a reversal or a jump there is
    /// visible as the whole grid's imagery blinking.
    func testAdoptedSettleHandoffIsMonotoneAndStepFree() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        for step in 1...12 {
            _ = coordinator.handle(
                .settleTick(timestamp: 100 + Double(step) / 60)
            )
        }
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        // Sweep well past the 4% activation travel where the handoff finishes.
        var progresses = [CGFloat]()
        for step in 0...40 {
            let scale = 1 + CGFloat(step) * 0.005
            let effects = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale))
            )
            if let progress = settleProgress(effects) {
                progresses.append(progress)
            }
        }
        XCTAssertGreaterThan(progresses.count, 20)

        let steps = zip(progresses, progresses.dropFirst()).map { $1 - $0 }
        let moving = steps.filter { abs($0) > 0.000_1 }
        XCTAssertFalse(moving.isEmpty)
        for (index, step) in steps.enumerated() {
            XCTAssertGreaterThanOrEqual(
                step,
                -0.000_1,
                "progress reversed at sample \(index): \(progresses)"
            )
        }
        let typical = moving.map { abs($0) }.reduce(0, +)
            / CGFloat(moving.count)
        for (index, step) in steps.enumerated() {
            XCTAssertLessThan(
                abs(step),
                typical * 8,
                "progress stepped at sample \(index): \(progresses)"
            )
        }

        let completedHandoff = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.2))
        )
        let completedScale = try XCTUnwrap(renderedScale(completedHandoff))
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(completedHandoff)),
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: completedScale,
                itemWidthRatio: plane.itemWidthRatio
            ),
            accuracy: 0.000_1,
            "the destinationward handoff must finish at direct progress"
        )

        // The release must resume from the last rendered frame, not zero.
        let released = endPinch(&coordinator)
        _ = coordinator.handle(.settleStarted(timestamp: 200))
        let resumed = coordinator.handle(.settleTick(timestamp: 200 + 1.0 / 60))
        let resumedProgress = try XCTUnwrap(
            settleProgress(resumed) ?? settleProgress(released)
        )
        XCTAssertGreaterThanOrEqual(
            resumedProgress,
            try XCTUnwrap(progresses.last) - 0.05,
            "the settle restarted the crossfade instead of resuming it"
        )
    }

    func testAdoptedProgressDoesNotTransferToAReplacementPlane() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .large,
                toMode: .fiveColumns,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let adoptedPlane = try XCTUnwrap(installedPlane(menu))
        var tickTime: TimeInterval = 100
        var runningScale: CGFloat = 1
        _ = coordinator.handle(.settleStarted(timestamp: tickTime))
        advanceSettle(
            &coordinator,
            tickTime: &tickTime,
            runningScale: &runningScale,
            untilAtMost: 0.35
        )

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .large
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.05))
        )
        let replacement = try XCTUnwrap(installedPlane(adjusted))

        XCTAssertNotEqual(replacement.id, adoptedPlane.id)
        XCTAssertEqual(replacement.toMode, .threeColumns)
        assertLastRenderedPlaneId(adjusted, replacement.id)
    }

    func testReleaseWaitsForTheAdoptedVisualHandoffBeforeRetargeting() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .large,
                toMode: .fiveColumns,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let adoptedPlane = try XCTUnwrap(installedPlane(menu))
        var tickTime: TimeInterval = 100
        var runningScale: CGFloat = 1
        _ = coordinator.handle(.settleStarted(timestamp: tickTime))
        advanceSettle(
            &coordinator,
            tickTime: &tickTime,
            runningScale: &runningScale,
            untilAtMost: 0.35
        )
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .large
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01))
        )
        guard case let .renderSettle(id, _, progress, _, _)? = adjusted.last else {
            return XCTFail("expected visual handoff render, got \(adjusted)")
        }
        XCTAssertEqual(id, adoptedPlane.id)
        XCTAssertGreaterThan(progress, 0)

        let released = endPinch(&coordinator)
        XCTAssertNil(installedPlane(released))
        let settle = drainSettle(
            &coordinator,
            startTime: tickTime + 0.03
        )
        assertCommits(settle, planeId: adoptedPlane.id, mode: .fiveColumns)
    }

    func testCancellingAnAdjustedAdoptedSettleFadesFromDisplayedProgress() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        for step in 1...12 {
            _ = coordinator.handle(
                .settleTick(timestamp: 100 + Double(step) / 60)
            )
        }
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01))
        )
        guard case let .renderSettle(_, _, adjustedProgress, _, _)? = adjusted.last else {
            return XCTFail("expected preserved settle render, got \(adjusted)")
        }

        _ = coordinator.handle(.pinchCancelled(reduceMotion: false))
        _ = coordinator.handle(.settleStarted(timestamp: 100.36))
        let settlingBack = coordinator.handle(
            .settleTick(timestamp: 100.36 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, returnedProgress, _, _)? = settlingBack.last else {
            return XCTFail("expected a continuous return render, got \(settlingBack)")
        }
        XCTAssertGreaterThan(returnedProgress, 0)
        XCTAssertLessThanOrEqual(returnedProgress, adjustedProgress)

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let heldReturn = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        guard case let .renderSettle(_, _, heldProgress, _, _)? = heldReturn.last else {
            return XCTFail("expected held return progress, got \(heldReturn)")
        }
        XCTAssertEqual(heldProgress, returnedProgress, accuracy: 0.000_1)

        _ = endPinch(&coordinator)
        _ = coordinator.handle(.settleStarted(timestamp: 100.41))
        let resumedReturn = coordinator.handle(
            .settleTick(timestamp: 100.41 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, resumedProgress, _, _)? = resumedReturn.last else {
            return XCTFail("expected resumed return progress, got \(resumedReturn)")
        }
        XCTAssertLessThanOrEqual(resumedProgress, heldProgress)
    }

    func testSourcewardAdjustmentAfterReadoptingReturnDoesNotAdvanceFade() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        for step in 1...12 {
            _ = coordinator.handle(
                .settleTick(timestamp: 100 + Double(step) / 60)
            )
        }

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.02))
        )
        _ = coordinator.handle(.pinchCancelled(reduceMotion: false))
        _ = coordinator.handle(.settleStarted(timestamp: 101))
        _ = coordinator.handle(.settleTick(timestamp: 101 + 1.0 / 60))

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        let destinationward = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.005))
        )
        let returned = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        let sourceward = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.995))
        )
        let heldScale = try XCTUnwrap(renderedScale(held))
        let destinationwardScale = try XCTUnwrap(renderedScale(destinationward))
        let sourcewardScale = try XCTUnwrap(renderedScale(sourceward))
        let heldProgress = try XCTUnwrap(settleProgress(held))
        let destinationwardProgress = try XCTUnwrap(
            settleProgress(destinationward)
        )
        let sourcewardProgress = try XCTUnwrap(settleProgress(sourceward))

        XCTAssertGreaterThan(destinationwardScale, heldScale)
        XCTAssertGreaterThanOrEqual(
            destinationwardProgress,
            heldProgress - 0.000_1,
            "moving toward the destination must not reverse its fade"
        )
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(returned)),
            heldProgress,
            accuracy: 0.000_1,
            "returning to the adoption scale must restore the held frame"
        )
        XCTAssertLessThan(sourcewardScale, heldScale)
        XCTAssertLessThanOrEqual(
            sourcewardProgress,
            heldProgress + 0.000_1,
            "moving toward the source must not advance destination content"
        )

        let handedOff = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.96))
        )
        let handoffScale = try XCTUnwrap(renderedScale(handedOff))
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(handedOff)),
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: handoffScale,
                itemWidthRatio: plane.itemWidthRatio
            ),
            accuracy: 0.000_1,
            "a completed handoff must use direct progress"
        )
    }


    func testStalledPinchCrossfadeCompletesOnTheFadeClock() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.3)
        XCTAssertNotNil(installedPlane(activation))
        XCTAssertTrue(activation.contains(.startInteractionFadeTicks))
        let initialPresentation = try XCTUnwrap(
            presentationProgress(activation)
        )
        XCTAssertLessThan(initialPresentation, 1)

        var tickTime: TimeInterval = 10
        _ = coordinator.handle(.interactionFadeTick(timestamp: tickTime))
        var lastPresentation = initialPresentation
        for _ in 0 ..< 90 {
            tickTime += 1.0 / 60
            let effects = coordinator.handle(
                .interactionFadeTick(timestamp: tickTime)
            )
            if let presentation = presentationProgress(effects) {
                XCTAssertTrue(effects.allSatisfy { effect in
                    if case .renderInteractionFade = effect { return true }
                    return false
                })
                XCTAssertGreaterThanOrEqual(
                    presentation,
                    lastPresentation - 0.000_001
                )
                lastPresentation = presentation
            }
        }
        XCTAssertEqual(lastPresentation, 1, accuracy: 0.000_1)

        tickTime += 1.0 / 60
        XCTAssertEqual(
            coordinator.handle(.interactionFadeTick(timestamp: tickTime)),
            [.stopInteractionFadeTicks],
            "a saturated fade clock stops its own ticks"
        )
    }

    func testRegrabbingACommitSettleContinuesThePlaneFadeClock() throws {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.3)
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10))
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10.5))
        _ = endPinch(&coordinator)
        _ = coordinator.handle(.settleStarted(timestamp: 20))
        let settling = coordinator.handle(.settleTick(timestamp: 20.02))
        let settledPresentation = try XCTUnwrap(
            presentationProgress(settling)
        )

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        XCTAssertEqual(
            coordinator.handle(.interactionFadeTick(timestamp: 30)),
            []
        )

        let nextTick = coordinator.handle(
            .interactionFadeTick(timestamp: 30.01)
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(presentationProgress(nextTick)),
            settledPresentation
        )
    }

    func testRegrabbingACancelSettleClampsTheCarriedFadeClock() throws {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.3)
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10))
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10.5))
        let retreated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.1))
        )
        let presentationBeforeCancel = try XCTUnwrap(
            presentationProgress(retreated)
        )
        _ = endStationaryPinch(&coordinator)
        _ = coordinator.handle(.settleStarted(timestamp: 20))
        let cancelling = coordinator.handle(.settleTick(timestamp: 20.06))
        let cancelPresentation = try XCTUnwrap(
            presentationProgress(cancelling)
        )
        XCTAssertLessThan(cancelPresentation, presentationBeforeCancel)

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        XCTAssertEqual(
            coordinator.handle(.interactionFadeTick(timestamp: 30)),
            []
        )

        let nextTick = coordinator.handle(
            .interactionFadeTick(timestamp: 30.01)
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(presentationProgress(nextTick)),
            cancelPresentation
        )
    }

    func testScaleCompletedFadeKeepsItsClockAliveAfterReversal() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 3.12)
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(activation)),
            1,
            accuracy: 0.000_1
        )

        let firstTick = coordinator.handle(.interactionFadeTick(timestamp: 10))
        XCTAssertFalse(firstTick.contains(.stopInteractionFadeTicks))

        let reversed = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.56))
        )
        XCTAssertLessThan(
            try XCTUnwrap(presentationProgress(reversed)),
            1
        )

        let stalled = coordinator.handle(.interactionFadeTick(timestamp: 10.1))
        XCTAssertFalse(stalled.contains(.stopInteractionFadeTicks))
        XCTAssertTrue(stalled.isEmpty)
        let advanced = coordinator.handle(
            .interactionFadeTick(timestamp: 10.6)
        )
        XCTAssertLessThan(
            try XCTUnwrap(presentationProgress(advanced)),
            1
        )
    }
}
