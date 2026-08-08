// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridInteractionCoordinatorTests: XCTestCase {

    private typealias Coordinator = PlayerBrowserGridInteractionCoordinator
    private typealias Effect = Coordinator.Effect

    private static func ratios(
        from mode: MobileCollectionBrowserGridMode
    ) -> [Coordinator.ModeRatio] {
        MobileCollectionBrowserGridMode.allCases.reversed().map { targetMode in
            Coordinator.ModeRatio(
                mode: targetMode,
                itemWidthRatio: CGFloat(mode.columnCount)
                    / CGFloat(targetMode.columnCount)
            )
        }
    }

    private static let ratioProvider: Coordinator.RatioProvider = {
        ratios(from: $0)
    }

    private func makeSample(
        scale: CGFloat,
        centroidY: CGFloat = 400,
        timestamp: TimeInterval = 99.99
    ) -> Coordinator.PinchSample {
        // Tests release at timestamp 100; samples default to just before it
        // so the release velocity is fresh, not held-stale.
        Coordinator.PinchSample(
            scale: scale,
            centroidY: centroidY,
            timestamp: timestamp
        )
    }

    /// Starts a pinch and crosses the activation dead zone at the given scale.
    private func activatePinch(
        _ coordinator: inout Coordinator,
        scale: CGFloat,
        centroidY: CGFloat = 400,
        fromMode: MobileCollectionBrowserGridMode = .threeColumns,
        ratios: [Coordinator.ModeRatio]? = nil
    ) -> [Effect] {
        let resolvedRatios = ratios ?? Self.ratios(from: fromMode)
        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1, centroidY: centroidY),
                    currentMode: fromMode
                ),
                ratioProvider: { _ in resolvedRatios }
            ),
            []
        )
        return coordinator.handle(
            .pinchChanged(sample: makeSample(scale: scale, centroidY: centroidY))
        )
    }

    private func activatedScale(_ rawScale: CGFloat) -> CGFloat {
        PlayerBrowserGridPinchPolicy.effectiveScaleAfterActivation(rawScale)
    }

    private func renderedZoomScale(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            if case let .renderZoom(_, scale, _) = effect {
                return scale
            }
        }
        return nil
    }

    private func settleScale(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            if case let .renderSettle(_, scale, _, _) = effect {
                return scale
            }
        }
        return nil
    }

    private func installedPlane(_ effects: [Effect]) -> Coordinator.Plane? {
        for effect in effects {
            if case let .installPlane(plane) = effect {
                return plane
            }
        }
        return nil
    }

    private func committedModes(
        _ effects: [Effect]
    ) -> [MobileCollectionBrowserGridMode] {
        effects.compactMap { effect in
            if case let .commitPlane(_, mode) = effect {
                return mode
            }
            return nil
        }
    }

    private func assertLastRenderZoomPlaneId(
        _ effects: [Effect],
        _ expected: UUID?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .renderZoom(planeId, _, _)? = effects.last else {
            return XCTFail(
                "expected renderZoom, got \(effects)",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(planeId, expected, file: file, line: line)
    }

    private func assertCommits(
        _ effects: [Effect],
        planeId: UUID?,
        mode: MobileCollectionBrowserGridMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let planeId else {
            return XCTFail("no plane was installed", file: file, line: line)
        }
        XCTAssertTrue(
            effects.contains(.commitPlane(id: planeId, mode: mode)),
            file: file,
            line: line
        )
    }

    private func assertDiscards(
        _ effects: [Effect],
        planeId: UUID?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let planeId else {
            return XCTFail("no plane was installed", file: file, line: line)
        }
        XCTAssertTrue(
            effects.contains(.discardPlane(id: planeId)),
            file: file,
            line: line
        )
    }

    @discardableResult
    private func endPinch(
        _ coordinator: inout Coordinator,
        velocity: CGFloat = 0,
        timestamp: TimeInterval = 100,
        reduceMotion: Bool = false
    ) -> [Effect] {
        coordinator.handle(
            .pinchEnded(
                velocity: velocity,
                timestamp: timestamp,
                reduceMotion: reduceMotion
            )
        )
    }

    /// Releases into a settle and advances it partway, leaving `.settling`.
    private func settlePartway(_ coordinator: inout Coordinator) {
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        _ = coordinator.handle(.settleTick(timestamp: 100.05))
    }

    private func drainSettle(
        _ coordinator: inout Coordinator,
        startTime: TimeInterval = 100,
        stepDuration: TimeInterval = 0.02,
        maximumTicks: Int = 200,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Effect] {
        var effects = coordinator.handle(.settleStarted(timestamp: startTime))
        if coordinator.phase == .settling && !coordinator.canBeginPinch {
            return effects
        }
        var tickTime = startTime
        for _ in 0..<maximumTicks where coordinator.phase == .settling {
            tickTime += stepDuration
            let tickEffects = coordinator.handle(.settleTick(
                timestamp: tickTime
            ))
            effects += tickEffects
            let awaitsRenderer = tickEffects.contains { effect in
                switch effect {
                case .commitPlane, .discardPlane, .applyMode:
                    true
                default:
                    false
                }
            }
            if awaitsRenderer || coordinator.phase != .settling {
                return effects
            }
        }
        if coordinator.phase == .settling {
            XCTFail(
                "settle did not reach a terminal renderer action",
                file: file,
                line: line
            )
        }
        return effects
    }

    private func advanceSettle(
        _ coordinator: inout Coordinator,
        tickTime: inout TimeInterval,
        runningScale: inout CGFloat,
        untilAtMost threshold: CGFloat,
        maximumTicks: Int = 200,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maximumTicks where
            coordinator.phase == .settling && runningScale > threshold {
            tickTime += 0.01
            runningScale = settleScale(
                coordinator.handle(.settleTick(timestamp: tickTime))
            ) ?? runningScale
        }
        if coordinator.phase == .settling, runningScale > threshold {
            XCTFail(
                "settle did not reach the requested scale",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Activation and free zoom

    func testActivationConsumesDeadZoneAndBeginsInteraction() {
        var coordinator = Coordinator()

        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1),
                    currentMode: .threeColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            []
        )
        XCTAssertEqual(coordinator.phase, .tracking)
        XCTAssertEqual(
            coordinator.handle(.pinchChanged(sample: makeSample(scale: 1.02))),
            []
        )
        XCTAssertEqual(coordinator.phase, .tracking)

        let effects = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.2))
        )
        XCTAssertEqual(coordinator.phase, .interacting)
        XCTAssertEqual(effects.first, .beginInteraction)
        let plane = installedPlane(effects)
        XCTAssertEqual(
            plane?.toMode,
            .large,
            "the heading grid preloads beneath the plane from the start"
        )
        XCTAssertEqual(
            effects.last,
            .renderZoom(
                planeId: plane?.id,
                scale: activatedScale(1.2),
                panDeltaY: 0
            )
        )
    }

    func testZoomTracksScaleAndPanWithoutReinstallingTheSameTarget() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.2)
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .large)

        let effects = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.8, centroidY: 460))
        )
        XCTAssertNil(installedPlane(effects))
        XCTAssertEqual(
            effects,
            [.renderZoom(
                planeId: plane?.id,
                scale: activatedScale(1.8),
                panDeltaY: 60
            )]
        )
    }

    func testZoomRubberBandsBeyondTheOutermostGrids() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.2)

        let effects = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 8))
        )
        let scale = renderedZoomScale(effects)
        XCTAssertNotNil(scale)
        XCTAssertGreaterThan(scale ?? 0, 3)
        XCTAssertLessThan(
            scale ?? 0,
            3 * (1 + PlayerBrowserGridPinchPolicy.overshootMaximumDeviation)
        )
    }

    // MARK: - Under plane while zooming out

    func testZoomOutInstallsTheNearestDenserPlaneWithoutReinstalling() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 0.9)

        let firstPlane = installedPlane(activation)
        XCTAssertEqual(firstPlane?.toMode, .fiveColumns)
        XCTAssertEqual(firstPlane?.itemWidthRatio, 0.6)
        assertLastRenderZoomPlaneId(activation, firstPlane?.id)

        let noReinstall = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.8))
        )
        XCTAssertNil(installedPlane(noReinstall))
    }

    func testZoomOutPlaneIsReplacedOnlyOnceTheReversalIsDecisive() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 0.9)
        let plane = installedPlane(activation)
        XCTAssertNotNil(plane)

        let jitter = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.97))
        )
        XCTAssertNil(
            installedPlane(jitter),
            "finger jitter across the original scale keeps the current plane"
        )
        assertLastRenderZoomPlaneId(jitter, plane?.id)

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.152))
        )
        let replacement = installedPlane(reversal)
        XCTAssertEqual(
            replacement?.toMode,
            .large,
            "a decisive reversal swaps the plane for the new heading"
        )
        assertLastRenderZoomPlaneId(reversal, replacement?.id)
    }

    func testReversingAtTheDenseBoundaryDiscardsTheStalePlane() {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 1.2,
            fromMode: .fiveColumns
        )
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .threeColumns)

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.9))
        )
        assertDiscards(reversal, planeId: plane?.id)
        assertLastRenderZoomPlaneId(reversal, nil)
    }

    func testReversingAtTheSparseBoundaryDiscardsTheStalePlane() {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.9,
            fromMode: .large
        )
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .threeColumns)

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.1))
        )
        assertDiscards(reversal, planeId: plane?.id)
        assertLastRenderZoomPlaneId(reversal, nil)
    }

    func testMidpointJitterDoesNotChurnThePlane() {
        var coordinator = Coordinator()
        _ = activatePinch(
            &coordinator,
            scale: 0.5,
            fromMode: .large
        )
        var installCount = 0
        let midpointScales: [CGFloat] = [0.245, 0.252, 0.246, 0.251, 0.247, 0.25]
        for scale in midpointScales {
            let effects = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale))
            )
            if installedPlane(effects) != nil {
                installCount += 1
            }
        }
        XCTAssertEqual(
            installCount,
            0,
            "oscillating around the five/three-column midpoint must not reinstall planes"
        )
    }

    func testContinuousDeepZoomRetargetsThePlanePastTheIntermediateMode() {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.9,
            fromMode: .large
        )
        XCTAssertEqual(installedPlane(activation)?.toMode, .threeColumns)

        var retargeted: Coordinator.Plane?
        var installCount = 0
        for scale in [0.7, 0.5, 0.35, 0.28, 0.2] as [CGFloat] {
            let effects = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale))
            )
            if let plane = installedPlane(effects) {
                installCount += 1
                retargeted = plane
            }
        }
        XCTAssertEqual(
            installCount,
            1,
            "one decisive retarget on the way down, no churn"
        )
        XCTAssertEqual(
            retargeted?.toMode,
            .fiveColumns,
            "a continuous deep zoom re-aims the plane past the intermediate mode"
        )

        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: retargeted?.id, mode: .fiveColumns)
    }

    // MARK: - Release outcomes

    func testReleaseNearTheOriginalScaleCancelsWithAScaleBackSettle() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.1)
        let plane = installedPlane(activation)

        let release = endPinch(&coordinator)
        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertEqual(release, [.startDisplayLink])
        XCTAssertFalse(release.contains(.selectionHaptic))

        let settle = drainSettle(&coordinator)
        XCTAssertTrue(settle.contains(
            .renderZoom(planeId: plane?.id, scale: 1, panDeltaY: 0)
        ))
        assertDiscards(settle, planeId: plane?.id)
        XCTAssertFalse(settle.contains { effect in
            if case .persistMode = effect { return true }
            if case .reconcileMedia = effect { return true }
            if case .renderSettle = effect { return true }
            if case .commitPlane = effect { return true }
            return false
        })

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
            if case let .renderSettle(_, _, settleProgress, _) = effect,
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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

    func testStrongFlickExtendsTheTargetOneStepFurther() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.3)
        let plane = installedPlane(activation)

        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.3))
        )

        _ = endPinch(&coordinator, velocity: 3.2)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: plane?.id, mode: .large)
    }

    func testStrongReverseFlickCancelsInsteadOfCommitting() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.4)

        let release = endPinch(&coordinator, velocity: -3.2)
        XCTAssertNil(installedPlane(release))
        XCTAssertFalse(release.contains(.selectionHaptic))
        let settle = drainSettle(&coordinator)
        XCTAssertTrue(committedModes(settle).isEmpty)
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: true)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testHeldReleaseIgnoresStaleFlickVelocityAndSnapsToNearest() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)

        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 2.0))
        )

        _ = endPinch(&coordinator, velocity: -3.2, timestamp: 100.49)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: plane?.id, mode: .large)
    }

    func testReleaseIgnoresVelocityWhenTimestampMovesBackward() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 2.0)
        let plane = installedPlane(activation)

        _ = endPinch(&coordinator, velocity: -3.2, timestamp: 99)
        let settle = drainSettle(&coordinator)

        assertCommits(settle, planeId: plane?.id, mode: .large)
    }

    func testReleaseIgnoresVelocityWhenTimestampIsNonfinite() {
        let timestampPairs: [(sample: TimeInterval, release: TimeInterval)] = [
            (.nan, 100),
            (.infinity, 100),
            (-.infinity, 100),
            (99.99, .nan),
            (99.99, .infinity),
            (99.99, -.infinity)
        ]

        for timestamps in timestampPairs {
            var coordinator = Coordinator()
            _ = coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1, timestamp: 99.98),
                    currentMode: .threeColumns
                ),
                ratioProvider: Self.ratioProvider
            )
            let activation = coordinator.handle(
                .pinchChanged(sample: makeSample(
                    scale: 2,
                    timestamp: timestamps.sample
                ))
            )
            let plane = installedPlane(activation)

            _ = endPinch(
                &coordinator,
                velocity: -3.2,
                timestamp: timestamps.release
            )
            let settle = drainSettle(&coordinator)

            assertCommits(settle, planeId: plane?.id, mode: .large)
        }
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

        _ = endPinch(&coordinator, velocity: 0.47)
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
                sample: makeSample(scale: 1, timestamp: 100.06),
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 2, timestamp: 100.07))
        )

        // Once the user has taken the gesture over, a cancellation abandons
        // the stale adopted target instead of committing it.
        let cancelled = coordinator.handle(.pinchCancelled(reduceMotion: false))
        let settle = drainSettle(&coordinator)
        XCTAssertTrue(committedModes(cancelled + settle).isEmpty)
        assertDiscards(cancelled + settle, planeId: plane?.id)
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertFalse(wrapUp.contains { effect in
            if case .persistMode = effect { return true }
            return false
        })
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // MARK: - Settle adoption

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
        XCTAssertEqual(adoption, [.stopDisplayLink])
        XCTAssertEqual(coordinator.phase, .interacting)
        XCTAssertFalse(coordinator.canBeginPinch)

        let resumed = endPinch(&coordinator, timestamp: 101)
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
        let release = endPinch(&coordinator, timestamp: 101)
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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(
                scale: 1.000_5,
                timestamp: 100.07
            ))
        )
        guard case let .renderSettle(id, _, progress, _)? = held.last else {
            return XCTFail("expected held settle render, got \(held)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertGreaterThan(progress, 0)

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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01, timestamp: 100.07))
        )
        let returned = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1, timestamp: 100.08))
        )
        guard case let .renderSettle(id, _, progress, _)? = returned.last else {
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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        let expired = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.05, timestamp: 100.07))
        )
        assertLastRenderZoomPlaneId(expired, plane.id)
        XCTAssertNil(installedPlane(expired))

        let recovered = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01, timestamp: 100.08))
        )
        guard case let .renderSettle(id, _, progress, _)? = recovered.last else {
            return XCTFail("expected recovered settle render, got \(recovered)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertGreaterThan(progress, 0)

        let release = endPinch(&coordinator, timestamp: 100.09)
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
                sample: makeSample(scale: 1, timestamp: tickTime + 0.01),
                currentMode: .large
            ),
            ratioProvider: Self.ratioProvider
        )

        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(
                scale: 1.05,
                timestamp: tickTime + 0.02
            ))
        )
        let replacement = try XCTUnwrap(installedPlane(adjusted))
        XCTAssertNotEqual(replacement.id, adoptedPlane.id)
        XCTAssertEqual(replacement.toMode, .threeColumns)

        let release = endPinch(
            &coordinator,
            timestamp: tickTime + 0.03
        )
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

    // MARK: - Menu selection

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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.fiveColumns)))
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // MARK: - Interruption and failures

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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
            if case .persistMode = effect { return true }
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

        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
        XCTAssertTrue(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true)),
            "three columns uses thumbnails while the large grid needs large images"
        )
    }

    func testQualityReconciliationKeepsPrefetchesBetweenDenseGrids() {
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
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: false)),
            "both dense grids need only thumbnails, so loads in flight survive"
        )
        XCTAssertFalse(
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: true))
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
            [.stopDisplayLink]
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

        let release = endPinch(&coordinator, timestamp: tickTime + 0.01)
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
                sample: makeSample(scale: 1, timestamp: 100.06),
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01, timestamp: 100.07))
        )
        guard case let .renderSettle(_, _, progress, _)? = adjusted.last else {
            return XCTFail("expected retained handoff render, got \(adjusted)")
        }
        XCTAssertGreaterThan(progress, 0)

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertEqual(failure, [.resetRenderer, .applyMode(.large)])
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = endPinch(&coordinator, timestamp: 101)
        let settle = drainSettle(&coordinator, startTime: 101)
        XCTAssertEqual(committedModes(settle), [.large])

        // The menu fallback survives the adoption round-trip: a failed
        // terminal commit still re-applies the selection directly.
        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertTrue(failure.contains(.applyMode(.large)))
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01, timestamp: 100.07))
        )
        guard case let .renderSettle(_, _, progress, _)? = adjusted.last else {
            return XCTFail("expected retained handoff render, got \(adjusted)")
        }
        XCTAssertGreaterThan(progress, 0)

        _ = endPinch(&coordinator, timestamp: 100.08)
        let settle = drainSettle(&coordinator, startTime: 100.08)
        XCTAssertEqual(committedModes(settle), [.large])

        let failure = coordinator.handle(.rendererFailed)
        XCTAssertTrue(failure.contains(.resetRenderer))
        XCTAssertTrue(failure.contains(.applyMode(.large)))
        let wrapUp = coordinator.handle(.rendererSucceeded)
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
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
                sample: makeSample(scale: 1, timestamp: 100.06),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        // Pinching back to the original scale abandons the adopted menu
        // selection, so the release cancels in place.
        _ = coordinator.handle(
            .pinchChanged(
                sample: makeSample(scale: 1 / runningScale, timestamp: 100.07)
            )
        )
        let release = endPinch(&coordinator, timestamp: 100.08)
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
        XCTAssertTrue(wrapUp.contains(.persistMode(.large)))
        XCTAssertTrue(wrapUp.contains(.finishInteraction(settlesPosition: false)))
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptDuringCancelSettleDiscardsWithoutPersisting() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.1)
        let plane = installedPlane(activation)
        _ = endPinch(&coordinator)
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
            if case .persistMode = effect { return true }
            if case .reconcileMedia = effect { return true }
            return false
        })
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testFailedDirectApplyFallbackTerminatesWithoutRetryingOrPersisting() {
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
            if case .persistMode = effect { return true }
            return false
        })
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testDescendingProviderRatiosStillBoundTheRubberBand() throws {
        var coordinator = Coordinator()
        // The real provider walks `allCases`, so from three columns it emits
        // [large, threeColumns, fiveColumns] — largest ratio first.
        let descending: [Coordinator.ModeRatio] = [
            Coordinator.ModeRatio(mode: .large, itemWidthRatio: 3),
            Coordinator.ModeRatio(mode: .threeColumns, itemWidthRatio: 1),
            Coordinator.ModeRatio(mode: .fiveColumns, itemWidthRatio: 0.6)
        ]

        let activation = activatePinch(
            &coordinator,
            scale: 2.0,
            ratios: descending
        )
        XCTAssertEqual(
            try XCTUnwrap(renderedZoomScale(activation)),
            activatedScale(2.0),
            accuracy: 0.000_1,
            "an in-range scale is rendered untouched, not banded toward 1"
        )

        let beyond = coordinator.handle(.pinchChanged(sample: makeSample(scale: 8)))
        let banded = try XCTUnwrap(renderedZoomScale(beyond))
        XCTAssertGreaterThan(banded, 3)
        XCTAssertLessThan(
            banded,
            3 * (1 + PlayerBrowserGridPinchPolicy.overshootMaximumDeviation)
        )
    }

    func testDegenerateSamplesAreIgnoredEntirely() {
        var coordinator = Coordinator()
        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 0),
                    currentMode: .threeColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            []
        )
        XCTAssertEqual(
            coordinator.phase,
            .idle,
            "an unusable begin sample must not open a session"
        )

        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: .nan),
                    currentMode: .threeColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            []
        )
        XCTAssertEqual(coordinator.phase, .idle)

        _ = activatePinch(&coordinator, scale: 1.5)
        XCTAssertEqual(coordinator.phase, .interacting)
        XCTAssertEqual(
            coordinator.handle(
                .pinchChanged(sample: makeSample(scale: 1.6, centroidY: .nan))
            ),
            [],
            "a sample with an unusable centroid renders nothing"
        )
        XCTAssertEqual(coordinator.phase, .interacting)
    }

    func testASecondBeginDuringAGestureIsIgnored() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.5, centroidY: 400)
        XCTAssertEqual(
            try XCTUnwrap(renderedZoomScale(activation)),
            activatedScale(1.5),
            accuracy: 0.000_1
        )
        let plane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(plane.fromMode, .threeColumns)

        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1, centroidY: 700),
                    currentMode: .fiveColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            [],
            "a duplicate begin must not rebuild the session mid-gesture"
        )
        XCTAssertEqual(
            coordinator.phase,
            .interacting,
            "the gesture keeps running rather than dropping back to tracking"
        )

        // Zooming on stays inside the original session: no second
        // beginInteraction, and no plane rebuilt from the duplicate's mode.
        let changed = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 2.5, centroidY: 400))
        )
        XCTAssertFalse(
            changed.contains(.beginInteraction),
            "the interaction was already begun"
        )
        XCTAssertNil(
            installedPlane(changed),
            "the plane aimed at large is already installed and still valid"
        )
        assertLastRenderZoomPlaneId(changed, plane.id)
        guard case let .renderZoom(_, _, panDeltaY)? = changed.last else {
            return XCTFail("expected renderZoom, got \(changed)")
        }
        XCTAssertEqual(
            panDeltaY,
            0,
            accuracy: 0.000_1,
            "the pan reference stays on the first begin's centroid"
        )
    }

    func testEveryTrackingExitReturnsToIdleWithoutEffects() {
        let exits: [Coordinator.Event] = [
            .interrupt,
            .pinchEnded(velocity: 4, timestamp: 100, reduceMotion: false),
            .pinchCancelled(reduceMotion: false)
        ]
        for exit in exits {
            var coordinator = Coordinator()
            XCTAssertEqual(
                coordinator.handle(
                    .pinchBegan(
                        sample: makeSample(scale: 1),
                        currentMode: .threeColumns
                    ),
                    ratioProvider: Self.ratioProvider
                ),
                []
            )
            XCTAssertEqual(coordinator.phase, .tracking)
            XCTAssertEqual(
                coordinator.handle(exit),
                [],
                "\(exit) never emitted beginInteraction, so it has nothing to finish"
            )
            XCTAssertEqual(coordinator.phase, .idle)
        }
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
                .persistMode(.large),
                .reconcileMedia(cancelsPrefetchLoads: true),
                .finishInteraction(settlesPosition: true)
            ]
        )
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptingASettleKeepsThePanAccumulatedBeforeIt() throws {
        var coordinator = Coordinator()
        // Pan 60pt down while zooming, then release into a settle.
        _ = activatePinch(&coordinator, scale: 1.5, centroidY: 400)
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.5, centroidY: 460))
        )
        _ = coordinator.handle(
            .pinchEnded(velocity: 0, timestamp: 100, reduceMotion: false)
        )
        XCTAssertEqual(coordinator.phase, .settling)
        _ = coordinator.handle(.settleStarted(timestamp: 100))

        // Grab the settle and drag 40pt further: the plane must sit at the
        // full 100pt, not restart the pan from the re-pinch centroid.
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(
                    scale: 1,
                    centroidY: 460,
                    timestamp: 100.05
                ),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        XCTAssertEqual(coordinator.phase, .interacting)
        let dragged = coordinator.handle(
            .pinchChanged(
                sample: makeSample(scale: 1, centroidY: 500, timestamp: 100.1)
            )
        )
        let panDeltaY: CGFloat
        switch dragged.last {
        case let .renderZoom(_, _, delta)?:
            panDeltaY = delta
        case let .renderSettle(_, _, _, delta)?:
            panDeltaY = delta
        default:
            return XCTFail("expected a render effect, got \(dragged)")
        }
        XCTAssertEqual(panDeltaY, 100, accuracy: 0.000_1)
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
            if case let .renderSettle(_, _, progress, _)? = ticked.last {
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
                sample: makeSample(scale: 1, timestamp: 100.3),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1, timestamp: 100.35))
        )
        guard case let .renderSettle(id, _, heldProgress, _)? = held.last else {
            return XCTFail("expected renderSettle while holding, got \(held)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertEqual(heldProgress, settleProgress, accuracy: 0.000_1)

        // Releasing resumes from there rather than replaying the fade.
        let released = coordinator.handle(
            .pinchEnded(velocity: 0, timestamp: 100.36, reduceMotion: false)
        )
        _ = coordinator.handle(.settleStarted(timestamp: 100.36))
        let resumed = coordinator.handle(
            .settleTick(timestamp: 100.36 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, resumedProgress, _)? = resumed.last else {
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
            if case let .renderSettle(_, _, progress, _)? = ticked.last {
                settleProgress = progress
            }
        }
        XCTAssertGreaterThan(
            settleProgress,
            PlayerBrowserGridCrossfade.contentFadeStartSettleProgress
        )

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 100.3),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01, timestamp: 100.35))
        )

        guard case let .renderSettle(id, _, adjustedProgress, _)? = adjusted.last else {
            return XCTFail("expected preserved settle render, got \(adjusted)")
        }
        XCTAssertEqual(id, plane.id)
        XCTAssertLessThan(adjustedProgress, settleProgress)
        XCTAssertGreaterThan(adjustedProgress, settleProgress * 0.7)
        XCTAssertNil(installedPlane(adjusted))
        XCTAssertFalse(adjusted.contains { effect in
            if case .discardPlane = effect { return true }
            return false
        })

        let released = coordinator.handle(
            .pinchEnded(velocity: 0, timestamp: 100.36, reduceMotion: false)
        )
        XCTAssertNil(installedPlane(released))
        _ = coordinator.handle(.settleStarted(timestamp: 100.36))
        let resumed = coordinator.handle(
            .settleTick(timestamp: 100.36 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, resumedProgress, _)? = resumed.last else {
            return XCTFail("expected resumed settle render, got \(resumed)")
        }
        XCTAssertGreaterThanOrEqual(resumedProgress, adjustedProgress)
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
                sample: makeSample(scale: 1, timestamp: tickTime + 0.01),
                currentMode: .large
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(
                scale: 1.05,
                timestamp: tickTime + 0.02
            ))
        )
        let replacement = try XCTUnwrap(installedPlane(adjusted))

        XCTAssertNotEqual(replacement.id, adoptedPlane.id)
        XCTAssertEqual(replacement.toMode, .threeColumns)
        assertLastRenderZoomPlaneId(adjusted, replacement.id)
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
                sample: makeSample(scale: 1, timestamp: tickTime + 0.01),
                currentMode: .large
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(
                scale: 1.01,
                timestamp: tickTime + 0.02
            ))
        )
        guard case let .renderSettle(id, _, progress, _)? = adjusted.last else {
            return XCTFail("expected visual handoff render, got \(adjusted)")
        }
        XCTAssertEqual(id, adoptedPlane.id)
        XCTAssertGreaterThan(progress, 0)

        let released = endPinch(
            &coordinator,
            timestamp: tickTime + 0.03
        )
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
                sample: makeSample(scale: 1, timestamp: 100.3),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.01, timestamp: 100.35))
        )
        guard case let .renderSettle(_, _, adjustedProgress, _)? = adjusted.last else {
            return XCTFail("expected preserved settle render, got \(adjusted)")
        }

        _ = coordinator.handle(.pinchCancelled(reduceMotion: false))
        _ = coordinator.handle(.settleStarted(timestamp: 100.36))
        let settlingBack = coordinator.handle(
            .settleTick(timestamp: 100.36 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, returnedProgress, _)? = settlingBack.last else {
            return XCTFail("expected a continuous return render, got \(settlingBack)")
        }
        XCTAssertGreaterThan(returnedProgress, 0)
        XCTAssertLessThanOrEqual(returnedProgress, adjustedProgress)

        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 100.39),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let heldReturn = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1, timestamp: 100.4))
        )
        guard case let .renderSettle(_, _, heldProgress, _)? = heldReturn.last else {
            return XCTFail("expected held return progress, got \(heldReturn)")
        }
        XCTAssertEqual(heldProgress, returnedProgress, accuracy: 0.000_1)

        _ = endPinch(&coordinator, timestamp: 100.41)
        _ = coordinator.handle(.settleStarted(timestamp: 100.41))
        let resumedReturn = coordinator.handle(
            .settleTick(timestamp: 100.41 + 1.0 / 60)
        )
        guard case let .renderSettle(_, _, resumedProgress, _)? = resumedReturn.last else {
            return XCTFail("expected resumed return progress, got \(resumedReturn)")
        }
        XCTAssertLessThanOrEqual(resumedProgress, heldProgress)
    }
}
