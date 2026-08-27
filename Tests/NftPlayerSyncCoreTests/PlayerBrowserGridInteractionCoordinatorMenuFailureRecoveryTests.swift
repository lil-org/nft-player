// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

extension PlayerBrowserGridInteractionCoordinatorTests {

    func testMenuSelectionRunsACommitSettleWithThePlaneRenderer() {
        var coordinator = Coordinator()
        let effects = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )

        XCTAssertEqual(effects.first, .beginInteraction)
        let plane = installedPlane(effects)
        XCTAssertEqual(plane?.toMode, .large)
        XCTAssertEqual(plane?.itemWidthRatio, 3)
        XCTAssertEqual(effects.last, .startDisplayLink)
        XCTAssertEqual(coordinator.phase, .settling)

        let settle = drainSettle(&coordinator, stepDuration: 0.05)
        assertCommits(settle, planeId: plane?.id, mode: .large)
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testMenuSelectionWithReduceMotionAppliesTheModeDirectly() {
        var coordinator = Coordinator()
        let effects = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .fiveColumns,
                reduceMotion: true
            ),
            ratioProvider: Self.ratioProvider
        )
        XCTAssertEqual(effects, [.beginInteraction, .applyMode(.fiveColumns)])

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: true)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testMenuCommitFallsBackToDirectApplyWhenTheRendererFails() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.stopDisplayLink))
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertTrue(failure.contains(.applyMode(.large)))

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }


    func testInterruptDuringGestureCancelsInstantlyWithoutSettlingPosition() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.5)
        let plane = installedPlane(activation)

        let effects = coordinator.handle(.interrupt)
        XCTAssertTrue(effects.contains(
            .renderZoom(planeId: plane?.id, scale: 1, panDeltaY: 0)
        ))
        assertDiscards(effects, planeId: plane?.id)

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: false)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptDuringCommitSettleJumpsToTheCommittedEndState() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)
        endPinch(&coordinator)
        settlePartway(&coordinator)

        let interrupt = coordinator.handle(.interrupt)
        XCTAssertTrue(interrupt.contains(.stopDisplayLink))
        assertCommits(interrupt, planeId: plane?.id, mode: .large)
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: false)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testRendererFailureDuringGestureResetsAndFinishes() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.5)

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertEqual(failure.first, .resetRenderer)
        XCTAssertTrue(failure.contains(.finishInteraction(settlesPosition: true)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testCommitPlaneFailureWithoutMenuFallbackResetsCleanly() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)
        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: plane?.id, mode: .large)

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertTrue(failure.contains(.finishInteraction(settlesPosition: true)))
        XCTAssertFalse(failure.contains { effect in
            if case .reconcileMedia = effect { return true }
            return false
        })
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testQualityReconciliationCancelsPrefetchesOnlyWhenQualityChanges() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 2.0)
        _ = endPinch(&coordinator)
        _ = drainSettle(&coordinator)
        let wrapUp = coordinator.handle(.rendererSucceeded)

        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true)),
            "three columns uses thumbnails while the large grid needs large images"
        )
    }

    func testQualityReconciliationCancelsPrefetchesForDenseGridEntry() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .fiveColumns,
                reduceMotion: true
            ),
            ratioProvider: Self.ratioProvider
        )
        let wrapUp = coordinator.handle(.rendererSucceeded)

        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true)),
            "five columns uses small thumbnails while three columns uses regular thumbnails"
        )
        XCTAssertFalse(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: false))
        )
    }

    func testQualityReconciliationCancelsPrefetchesBetweenDenseGridTiers() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .fiveColumns,
                toMode: .nineColumns,
                reduceMotion: true
            ),
            ratioProvider: Self.ratioProvider
        )
        let wrapUp = coordinator.handle(.rendererSucceeded)

        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true)),
            "nine columns uses 140 px thumbnails while five columns uses 260 px thumbnails"
        )
    }

    func testInterruptBeforeTheRendererAcknowledgesSkipsPositionSettling() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)
        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: plane?.id, mode: .large)

        // A layout pass can interrupt between the commit render and its ack.
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertTrue(
            wrapUp.contains(.finishInteraction(settlesPosition: false)),
            "the interrupted host must not be scrolled to a re-anchored offset"
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testMenuSelectionSurvivesAFailedTerminalCommitRender() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let settle = drainSettle(&coordinator, stepDuration: 0.05)
        XCTAssertFalse(committedModes(settle).isEmpty)

        // Unlike a pre-terminal failure, this one arrives while the commit is
        // already awaiting its acknowledgement.
        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertTrue(
            failure.contains(.applyMode(.large)),
            "a menu selection is reapplied directly rather than discarded"
        )

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptedSettlePhaseHoldsItsPlaneUntilThePinchMoves() {
        var coordinator = Coordinator()
        let effects = coordinator.handle(
            .menuSelected(
                fromMode: .large,
                toMode: .fiveColumns,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = installedPlane(effects)
        XCTAssertEqual(plane?.toMode, .fiveColumns)

        // Stop where the three-column ratio (1/3) is the nearest lattice, so a
        // retarget would fire if the adopted phase did not hold the plane.
        var tickTime: TimeInterval = 100
        var adoptedScale: CGFloat = 1
        _ = coordinator.handle(.settleStarted(timestamp: tickTime))
        advanceSettle(
            &coordinator,
            tickTime: &tickTime,
            runningScale: &adoptedScale,
            untilAtMost: 0.4
        )
        XCTAssertGreaterThan(adoptedScale, 0.27)
        XCTAssertLessThan(adoptedScale, 0.4)

        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1),
                    currentMode: .large
                ),
                ratioProvider: Self.ratioProvider
            ),
            [.stopDisplayLink, .beginInteraction, .startInteractionFadeTicks]
        )

        // The host always delivers one pinchChanged before the release.
        let held = coordinator.handle(.pinchChanged(sample: makeSample(scale: 1)))
        XCTAssertNil(
            installedPlane(held),
            "an unmoved adopted pinch keeps the settle's plane"
        )
        XCTAssertFalse(held.contains { effect in
            if case .discardPlane = effect { return true }
            return false
        })

        let release = endPinch(&coordinator)
        XCTAssertNil(
            installedPlane(release),
            "and releases onto it without reinstalling"
        )
        let settle = drainSettle(&coordinator, startTime: tickTime + 0.01)
        assertCommits(settle, planeId: plane?.id, mode: .fiveColumns)
    }

    func testRendererFailureWhileHoldingAnAdoptedMenuSettleReappliesTheMenuMode() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        XCTAssertEqual(coordinator.phase, .interacting)

        // An unmoved hold is still the menu's selection: losing the renderer
        // mid-hold must not silently drop it.
        let failure = coordinator.handle(.rendererFailed)
        XCTAssertEqual(failure, [.resetRenderer, .applyMode(.large)])

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testRendererFailureDuringAdjustedAdoptedMenuHandoffReappliesMenuMode() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        settlePartway(&coordinator)
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
        guard case let .renderSettle(_, _, progress, _, _)? = adjusted.last else {
            return XCTFail("expected retained handoff render, got \(adjusted)")
        }
        XCTAssertGreaterThan(progress, 0)

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertEqual(failure, [.resetRenderer, .applyMode(.large)])
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptedMenuCommitRetriesDirectlyWhenTheTerminalRenderFails() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator, startTime: 101)
        XCTAssertEqual(committedModes(settle), [.large])

        // The menu fallback survives the adoption round-trip: a failed
        // terminal commit still re-applies the selection directly.
        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertTrue(failure.contains(.applyMode(.large)))
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdjustedAdoptedMenuCommitRetainsFallbackDuringVisualHandoff() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        settlePartway(&coordinator)
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
        guard case let .renderSettle(_, _, progress, _, _)? = adjusted.last else {
            return XCTFail("expected retained handoff render, got \(adjusted)")
        }
        XCTAssertGreaterThan(progress, 0)

        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator, startTime: 100.08)
        XCTAssertEqual(committedModes(settle), [.large])

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertTrue(failure.contains(.applyMode(.large)))
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdjustedAdoptedCancelReleaseDoesNotUseTheMenuFallback() {
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
        let runningScale = settleScale(
            coordinator.handle(.settleTick(timestamp: 100.05))
        ) ?? 1
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        // Pinching back to the original scale abandons the adopted menu
        // selection, so the release cancels in place.
        _ = coordinator.handle(
            .pinchChanged(
                sample: makeSample(scale: 1 / runningScale)
            )
        )
        let release = endStationaryPinch(&coordinator)
        let settle = drainSettle(&coordinator, startTime: 100.08)
        XCTAssertTrue(committedModes(release + settle).isEmpty)

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertFalse(
            failure.contains(.applyMode(.large)),
            "an abandoned selection is not re-applied on failure"
        )
        XCTAssertTrue(failure.contains(.finishInteraction(settlesPosition: true)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPendingInterruptSurvivesTheMenuFallbackRetry() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let settle = drainSettle(&coordinator, stepDuration: 0.05)
        XCTAssertEqual(committedModes(settle), [.large])

        // The interrupt lands between the commit render and its ack, the
        // renderer then fails, and the direct-apply retry succeeds: the
        // interrupted host must still not be scrolled to a re-anchored offset.
        XCTAssertEqual(coordinator.handle(.interrupt), [])
        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.applyMode(.large)))

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: false)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptDuringCancelSettleDiscardsWithoutReconcilingMedia() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.1)
        let plane = installedPlane(activation)
        _ = endStationaryPinch(&coordinator)
        settlePartway(&coordinator)

        let interrupt = coordinator.handle(.interrupt)
        XCTAssertTrue(interrupt.contains(.stopDisplayLink))
        XCTAssertTrue(interrupt.contains(
            .renderZoom(planeId: plane?.id, scale: 1, panDeltaY: 0)
        ))
        assertDiscards(interrupt, planeId: plane?.id)
        XCTAssertFalse(interrupt.contains { effect in
            if case .commitPlane = effect { return true }
            if case .renderSettle = effect { return true }
            return false
        })

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: false)))
        XCTAssertFalse(wrapUp.contains { effect in
            if case .reconcileMedia = effect { return true }
            return false
        })
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testFailedDirectApplyFallbackTerminatesWithoutRetrying() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let settle = drainSettle(&coordinator, stepDuration: 0.05)
        XCTAssertEqual(committedModes(settle), [.large])
        let firstFailure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(firstFailure.contains(.applyMode(.large)))

        // The direct apply is already the fallback: a second failure must
        // terminate cleanly instead of ping-ponging retries forever.
        let secondFailure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(secondFailure.contains(.resetRenderer))
        XCTAssertTrue(
            secondFailure.contains(.finishInteraction(settlesPosition: true))
        )
        XCTAssertFalse(secondFailure.contains { effect in
            if case .applyMode = effect { return true }
            if case .reconcileMedia = effect { return true }
            return false
        })
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testMenuSelectionWithoutAUsableRatioAppliesTheModeDirectly() {
        var coordinator = Coordinator()
        let effects = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            // The live provider returns nothing until the browser has
            // finished its initial positioning.
            ratioProvider: { _ in [] }
        )
        XCTAssertEqual(effects, [.beginInteraction, .applyMode(.large)])
        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertFalse(coordinator.canBeginPinch)
        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1.2),
                    currentMode: .threeColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            []
        )
        XCTAssertEqual(coordinator.handle(.settleTick(timestamp: 101)), [])
        XCTAssertEqual(coordinator.phase, .settling)

        XCTAssertEqual(
            coordinator.handle(.rendererSucceeded),
            [
                .reconcileMedia(cancelsPrefetchLoads: true),
                .finishInteraction(settlesPosition: true)
            ]
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }
}
