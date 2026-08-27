// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

extension PlayerBrowserGridInteractionCoordinatorTests {

    func testReleaseStillMovingTowardTheNextModeCommitsAcrossIt() throws {
        var coordinator = Coordinator()
        // Out-then-back-in wobble: geometry ends barely past unity, but the
        // release is still moving outward — Photos commits one step outward.
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.7, timestamp: 0.2))
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.02, timestamp: 0.38))
        )
        let retargeted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.4))
        )
        let plane = try XCTUnwrap(installedPlane(retargeted))
        XCTAssertEqual(plane.toMode, .large)
        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.42
            )
        )
        XCTAssertTrue(released.contains(.startDisplayLink))
        let settled = drainSettle(&coordinator)
        assertCommits(
            settled,
            planeId: plane.id,
            mode: .large
        )
    }

    func testReleaseNeverInstallsSparsePlaneBelowUnity() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let activation = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.70, timestamp: 0.2))
        )
        let densePlane = installedPlane(activation)
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.95, timestamp: 0.22))
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.23
            )
        )
        XCTAssertFalse(released.contains { effect in
            if case let .installPlane(plane) = effect {
                return plane.toMode == .large
            }
            return false
        })
        let settled = released + drainSettle(&coordinator)
        assertDiscards(settled, planeId: densePlane?.id)
        XCTAssertFalse(settled.contains { effect in
            if case .commitPlane(_, .large) = effect { return true }
            if case .applyMode(.large) = effect { return true }
            return false
        })
    }

    func testQuickReleaseReversalUsesTerminalDirection() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.18),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.2, timestamp: 0.2))
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.94, timestamp: 0.28))
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.05, timestamp: 0.3))
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.32
            )
        )
        let settled = released + drainSettle(&coordinator)
        XCTAssertTrue(
            settled.contains { effect in
                if case .commitPlane(_, .large) = effect { return true }
                if case .applyMode(.large) = effect { return true }
                return false
            }
        )
    }

    func testMicroscopicReleaseJitterDoesNotReverseTerminalDirection() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.18),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.2, timestamp: 0.2))
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.94, timestamp: 0.28))
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.05, timestamp: 0.3))
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.0499, timestamp: 0.31))
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.32
            )
        )
        let settled = released + drainSettle(&coordinator)
        XCTAssertTrue(
            settled.contains { effect in
                if case .commitPlane(_, .large) = effect { return true }
                if case .applyMode(.large) = effect { return true }
                return false
            }
        )
    }

    func testCumulativeSubNoiseTerminalReversalUsesTerminalDirection() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.18),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let activated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.2))
        )
        let plane = try XCTUnwrap(installedPlane(activated))
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.08985, timestamp: 0.22))
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: 1.08970,
                reduceMotion: false,
                timestamp: 0.24
            )
        )
        let settled = released + drainSettle(&coordinator)
        assertDiscards(settled, planeId: plane.id)
        XCTAssertFalse(settled.contains { effect in
            if case .commitPlane(_, .large) = effect { return true }
            if case .applyMode(.large) = effect { return true }
            return false
        })
    }

    func testSameTimestampTerminalCorrectionPreservesPriorMotionWindow() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let activated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.09))
        )
        let plane = try XCTUnwrap(installedPlane(activated))
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.2, timestamp: 0.18))
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: 1.09,
                reduceMotion: false,
                timestamp: 0.18
            )
        )
        assertCommits(
            released + drainSettle(&coordinator),
            planeId: plane.id,
            mode: .large
        )
    }

    func testOscillatingMicroscopicJitterDoesNotReverseReleaseDirection() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.18),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.15, timestamp: 0.22))
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.2, timestamp: 0.24))
        )
        for (index, scale) in [
            1.1999, 1.2, 1.1999, 1.2,
            1.1999, 1.2, 1.1999, 1.2
        ].enumerated() {
            _ = coordinator.handle(
                .pinchChanged(sample: makeSample(
                    scale: scale,
                    timestamp: 0.25 + TimeInterval(index) * 0.01
                ))
            )
        }

        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.33
            )
        )
        let settled = released + drainSettle(&coordinator)
        XCTAssertTrue(
            settled.contains { effect in
                if case .commitPlane(_, .large) = effect { return true }
                if case .applyMode(.large) = effect { return true }
                return false
            }
        )
    }

    func testSlowMonotoneReleaseReversalUsesCumulativeDirection() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.18),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let activation = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.15, timestamp: 0.22))
        )
        let plane = installedPlane(activation)
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.2, timestamp: 0.24))
        )
        for (index, scale) in stride(
            from: CGFloat(1.1998),
            through: 1.1984,
            by: -0.0002
        ).enumerated() {
            _ = coordinator.handle(
                .pinchChanged(sample: makeSample(
                    scale: scale,
                    timestamp: 0.25 + TimeInterval(index) * 0.01
                ))
            )
        }

        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.33
            )
        )
        let settled = released + drainSettle(&coordinator)
        assertDiscards(settled, planeId: plane?.id)
        XCTAssertFalse(settled.contains { effect in
            if case .commitPlane(_, .large) = effect { return true }
            if case .applyMode(.large) = effect { return true }
            return false
        })
    }

    func testReplacementPlaneRequestsCoverAndStartsWithAFreshFadeTickBaseline()
        throws {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.3)
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10))
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10.05))

        let replacementEffects = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.9))
        )
        let replacement = try XCTUnwrap(installedPlane(replacementEffects))
        let coverIndex = try XCTUnwrap(
            replacementEffects.firstIndex(of: .coverPlaneChange)
        )
        let installIndex = try XCTUnwrap(
            replacementEffects.firstIndex(of: .installPlane(replacement))
        )
        XCTAssertLessThan(coverIndex, installIndex)
        let replacementPresentation = try XCTUnwrap(
            presentationProgress(replacementEffects)
        )
        XCTAssertLessThan(replacementPresentation, 1)

        XCTAssertEqual(
            coordinator.handle(.interactionFadeTick(timestamp: 20)),
            []
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(presentationProgress(
                coordinator.handle(.interactionFadeTick(timestamp: 20.01))
            )),
            replacementPresentation
        )
    }

    func testSaturatedReplacementRequestsVisualCoverBeforeInstall() throws {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.3)
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10))
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10.8))

        let replacement = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.9))
        )
        let coverIndex = try XCTUnwrap(
            replacement.firstIndex(of: .coverPlaneChange)
        )
        let installIndex = try XCTUnwrap(
            replacement.firstIndex { effect in
                if case .installPlane = effect { return true }
                return false
            }
        )
        XCTAssertLessThan(coverIndex, installIndex)
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(replacement)),
            0,
            accuracy: 0.000_1
        )
    }

    func testSaturatedDiscardRequestsVisualCoverBeforeDiscard() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.9,
            fromMode: .large
        )
        let plane = try XCTUnwrap(installedPlane(activation))
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10))
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10.8))

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.1))
        )
        let coverIndex = try XCTUnwrap(
            reversal.firstIndex(of: .coverPlaneChange)
        )
        let discardIndex = try XCTUnwrap(
            reversal.firstIndex(of: .discardPlane(id: plane.id))
        )
        XCTAssertLessThan(coverIndex, discardIndex)
    }

    func testRapidReversalCoversDiscardAfterAZeroProgressFrame() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.7,
            fromMode: .large
        )
        let plane = try XCTUnwrap(installedPlane(activation))
        XCTAssertGreaterThan(
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: try XCTUnwrap(
                    presentationProgress(activation)
                )
            ),
            0
        )

        let zeroProgress = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.96))
        )
        assertLastRenderedPlaneId(zeroProgress, plane.id)
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(zeroProgress)),
            0,
            accuracy: 0.000_1
        )

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.04))
        )
        let coverIndex = try XCTUnwrap(
            reversal.firstIndex(of: .coverPlaneChange)
        )
        let discardIndex = try XCTUnwrap(
            reversal.firstIndex(of: .discardPlane(id: plane.id))
        )
        XCTAssertLessThan(coverIndex, discardIndex)
    }

    func testFutureDatedMotionDoesNotProjectRelease() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.2),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let activated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.22))
        )
        let plane = try XCTUnwrap(installedPlane(activated))

        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.21
            )
        )
        let settled = released + drainSettle(&coordinator)
        assertDiscards(settled, planeId: plane.id)
        XCTAssertFalse(settled.contains { effect in
            if case .commitPlane(_, .large) = effect { return true }
            if case .applyMode(.large) = effect { return true }
            return false
        })
    }

    func testOutOfOrderMotionSampleDoesNotReplaceTheNewestSample() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.18),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.9, timestamp: 0.2))
        )
        let activated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.3))
        )
        let plane = try XCTUnwrap(installedPlane(activated))
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.21))
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.32
            )
        )
        assertCommits(
            released + drainSettle(&coordinator),
            planeId: plane.id,
            mode: .large
        )
    }

    func testOneChangedFrameFlickUsesPinchBeganSample() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0.2),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        let activated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.22))
        )
        let plane = try XCTUnwrap(installedPlane(activated))
        XCTAssertEqual(plane.toMode, .large)

        _ = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.24
            )
        )
        assertCommits(
            drainSettle(&coordinator),
            planeId: plane.id,
            mode: .large
        )
    }

    func testDeceleratingTailStillCommitsOnWindowedMotion() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        // Fast outward motion whose final two samples flatten (an eased
        // gesture tail): the windowed rate must still read as moving.
        for (scale, time) in [(0.7, 0.20), (0.95, 0.30), (1.06, 0.36),
                              (1.09, 0.372), (1.09, 0.384)] as [(CGFloat, TimeInterval)] {
            _ = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale, timestamp: time))
            )
        }
        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.4
            )
        )
        XCTAssertTrue(released.contains(.startDisplayLink))
        var settleTarget: MobileCollectionBrowserGridMode?
        let settled = drainSettle(&coordinator)
        for effect in settled {
            if case let .commitPlane(_, mode) = effect { settleTarget = mode }
            if case let .applyMode(mode) = effect { settleTarget = mode }
        }
        XCTAssertEqual(
            settleTarget,
            .large,
            "a flattened release tail must not mask the outward motion"
        )
    }

    func testStationaryTailReleasesPositionally() throws {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1, timestamp: 0),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )
        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.02, timestamp: 0.2))
        )
        let retargeted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.09, timestamp: 0.22))
        )
        let plane = try XCTUnwrap(installedPlane(retargeted))
        XCTAssertEqual(plane.toMode, .large)
        // Same motion as the moving release, but the fingers dwell before
        // lifting: stale motion must not seal a boundary.
        let released = coordinator.handle(
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 0.9
            )
        )
        let settled = released + drainSettle(&coordinator)
        let terminalModes = settled.compactMap { effect in
            switch effect {
            case let .commitPlane(_, mode), let .applyMode(mode):
                mode
            default:
                nil
            }
        }
        assertDiscards(settled, planeId: plane.id)
        XCTAssertEqual(
            terminalModes.last ?? .threeColumns,
            .threeColumns,
            "a stationary release at 1.09 stays at three columns"
        )
        XCTAssertFalse(terminalModes.contains(.large))
    }
}
