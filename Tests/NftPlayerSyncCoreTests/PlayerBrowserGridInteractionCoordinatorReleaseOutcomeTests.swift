// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

extension PlayerBrowserGridInteractionCoordinatorTests {

    func testReleaseNearTheOriginalScaleCancelsWithAScaleBackSettle() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.1)
        let plane = installedPlane(activation)

        let release = endStationaryPinch(&coordinator)
        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertEqual(release, [.startDisplayLink])
        XCTAssertFalse(release.contains(.selectionHaptic))

        let settle = drainSettle(&coordinator)
        XCTAssertTrue(settle.contains(
            .renderZoom(planeId: plane?.id, scale: 1, panDeltaY: 0)
        ))
        assertDiscards(settle, planeId: plane?.id)
        XCTAssertFalse(settle.contains { effect in
            if case .reconcileMedia = effect { return true }
            if case .commitPlane = effect { return true }
            return false
        })
        // The pinch had already crossfaded part way in, so the cancel walks
        // that fade back out instead of snapping it away.
        var progresses: [CGFloat] = []
        for effect in settle {
            if case let .renderSettle(_, _, progress, _, _) = effect {
                progresses.append(progress)
            }
        }
        XCTAssertFalse(progresses.isEmpty)
        XCTAssertEqual(
            progresses,
            progresses.sorted(by: >),
            "the crossfade only ever recedes on a cancel"
        )
        XCTAssertEqual(progresses.last ?? 1, 0, accuracy: 0.01)

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: true)))
    }

    func testReleaseNearACommitScaleSettlesIntoThatModeAndReconciles() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .large)

        let release = endPinch(&coordinator)
        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertEqual(release.first, .selectionHaptic)
        XCTAssertNil(
            installedPlane(release),
            "the plane that tracked the gesture is reused for the settle"
        )
        XCTAssertEqual(release.last, .startDisplayLink)

        var sawIntermediateSettleFrame = false
        let settle = drainSettle(&coordinator)
        for effect in settle {
            if case let .renderSettle(_, _, settleProgress, _, _) = effect,
               settleProgress > 0,
               settleProgress < 1 {
                sawIntermediateSettleFrame = true
            }
        }
        XCTAssertTrue(sawIntermediateSettleFrame)
        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertFalse(coordinator.canBeginPinch)

        assertCommits(settle, planeId: plane?.id, mode: .large)

        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: true)))
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
    }

    func testReleaseCanJumpMultipleModesInOneGesture() {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.22,
            fromMode: .large
        )
        let plane = installedPlane(activation)
        XCTAssertEqual(
            plane?.toMode,
            .fiveColumns,
            "deep zooms retarget the plane past intermediate modes"
        )

        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: plane?.id, mode: .fiveColumns)
    }

    func testReleaseAtMeasuredHoldScaleReturnsToOriginalMode() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.169)

        let release = endStationaryPinch(&coordinator)
        XCTAssertNil(installedPlane(release))
        XCTAssertFalse(release.contains(.selectionHaptic))
        let settle = drainSettle(&coordinator)
        XCTAssertTrue(committedModes(settle).isEmpty)
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: true)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testReleaseAtMeasuredCommitScaleAdvancesToLargeMode() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.25)
        let plane = installedPlane(activation)

        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)

        assertCommits(settle, planeId: plane?.id, mode: .large)
    }

    func testReleaseTargetsThePhysicalPinchScaleNotTheTrimmedRenderScale() {
        var coordinator = Coordinator()
        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1.16),
                    currentMode: .threeColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            []
        )
        let activation = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 2.0))
        )
        let plane = installedPlane(activation)

        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: plane?.id, mode: .large)
    }

    func testZoomOutReleaseCommitsUsingTheAlreadyInstalledUnderPlane() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 0.72)
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .fiveColumns)

        let release = endPinch(&coordinator)
        XCTAssertNil(installedPlane(release), "the gesture plane is reused")
        XCTAssertEqual(release.first, .selectionHaptic)

        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: plane?.id, mode: .fiveColumns)
    }

    func testDirectProgressDoesNotExtendOrdinarySettleTiming() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 0.72)
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .fiveColumns)
        XCTAssertTrue(endPinch(&coordinator).contains(.startDisplayLink))
        XCTAssertEqual(
            coordinator.handle(.settleStarted(timestamp: 100)),
            []
        )

        var terminalTick: Int?
        for tick in 1 ... 60 where coordinator.phase == .settling {
            let effects = coordinator.handle(.settleTick(
                timestamp: 100 + Double(tick) / 60
            ))
            if effects.contains(where: {
                if case .commitPlane = $0 { return true }
                return false
            }) {
                terminalTick = tick
            }
        }

        XCTAssertEqual(terminalTick, 45)
    }

    func testReduceMotionReleaseCommitsWithoutAnimation() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)

        let release = endPinch(&coordinator, reduceMotion: true)
        XCTAssertFalse(release.contains(.startDisplayLink))
        assertCommits(release, planeId: plane?.id, mode: .large)
        _ = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPinchCancelledReturnsToTheOriginalMode() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.5)

        let cancelled = coordinator.handle(
            .pinchCancelled(reduceMotion: false)
        )
        XCTAssertFalse(cancelled.contains(.selectionHaptic))
        XCTAssertNil(installedPlane(cancelled))
        let settle = drainSettle(&coordinator)
        XCTAssertTrue(committedModes(settle).isEmpty)
        _ = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPinchCancelledWithAnUnadjustedAdoptedSettleCommitsItsTarget() {
        var coordinator = Coordinator()
        let effects = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = installedPlane(effects)
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        // A system cancellation of an unmoved hold is not a change of mind:
        // the adopted menu selection still lands.
        _ = coordinator.handle(.pinchCancelled(reduceMotion: false))
        let settle = drainSettle(&coordinator, startTime: 101)
        assertCommits(settle, planeId: plane?.id, mode: .large)
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPinchCancelledAfterAdjustingRevertsToTheOriginalMode() {
        var coordinator = Coordinator()
        let effects = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let plane = installedPlane(effects)
        settlePartway(&coordinator)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 2))
        )

        // Once the user has taken the gesture over, a cancellation abandons
        // the stale adopted target instead of committing it.
        let cancelled = coordinator.handle(.pinchCancelled(reduceMotion: false))
        let settle = drainSettle(&coordinator)
        XCTAssertTrue(committedModes(cancelled + settle).isEmpty)
        assertDiscards(cancelled + settle, planeId: plane?.id)
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertFalse(wrapUp.contains { effect in
            if case .reconcileMedia = effect { return true }
            return false
        })
        XCTAssertEqual(coordinator.phase, .idle)
    }
}
