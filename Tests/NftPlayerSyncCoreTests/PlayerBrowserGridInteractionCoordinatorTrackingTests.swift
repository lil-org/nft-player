// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

extension PlayerBrowserGridInteractionCoordinatorTests {

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
        assertLastRenderedPlaneId(effects, plane?.id)
        XCTAssertEqual(renderedScale(effects), activatedScale(1.2))
        XCTAssertEqual(renderedPanDeltaY(effects), 0)
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
        XCTAssertEqual(effects.count, 1)
        assertLastRenderedPlaneId(effects, plane?.id)
        XCTAssertEqual(renderedScale(effects), activatedScale(1.8))
        XCTAssertEqual(renderedPanDeltaY(effects), 60)
    }

    func testZoomCrossfadesTheDestinationWhileTheFingersAreDown() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.2)
        let plane = try XCTUnwrap(installedPlane(activation))

        var progresses: [CGFloat] = []
        for scale in [CGFloat(1.2), 1.5, 1.9, 2.4] {
            let effects = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale))
            )
            let rendered = try XCTUnwrap(settleProgress(effects))
            XCTAssertEqual(
                rendered,
                log(activatedScale(scale)) / log(plane.itemWidthRatio),
                accuracy: 0.000_1
            )
            progresses.append(rendered)
        }
        XCTAssertEqual(progresses, progresses.sorted())
        XCTAssertGreaterThan(try XCTUnwrap(progresses.last), 0.5)

        // The release resumes the fade rather than restarting it.
        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)
        let firstSettleProgress = try XCTUnwrap(
            settle.compactMap { effect -> CGFloat? in
                if case let .renderSettle(_, _, progress, _, _) = effect {
                    return progress
                }
                return nil
            }.first
        )
        XCTAssertGreaterThanOrEqual(
            firstSettleProgress,
            try XCTUnwrap(progresses.last) - 0.05
        )
        assertCommits(settle, planeId: plane.id, mode: .large)
    }

    func testZoomRubberBandsBeyondTheOutermostGrids() {
        var coordinator = Coordinator()
        _ = activatePinch(&coordinator, scale: 1.2)

        let effects = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 8))
        )
        let scale = renderedScale(effects)
        XCTAssertNotNil(scale)
        XCTAssertGreaterThan(scale ?? 0, 3)
        XCTAssertLessThan(
            scale ?? 0,
            3 * (1 + PlayerBrowserGridPinchPolicy.overshootMaximumDeviation)
        )
    }


    func testZoomOutInstallsTheNearestDenserPlaneWithoutReinstalling() {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 0.9)

        let firstPlane = installedPlane(activation)
        XCTAssertEqual(firstPlane?.toMode, .fiveColumns)
        XCTAssertEqual(firstPlane?.itemWidthRatio, 0.6)
        assertLastRenderedPlaneId(activation, firstPlane?.id)

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
        assertLastRenderedPlaneId(jitter, plane?.id)

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.152))
        )
        let replacement = installedPlane(reversal)
        XCTAssertEqual(
            replacement?.toMode,
            .large,
            "a decisive reversal swaps the plane for the new heading"
        )
        assertLastRenderedPlaneId(reversal, replacement?.id)
    }

    func testReversingAtTheDenseBoundaryDiscardsTheStalePlane() {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 1.2,
            fromMode: .nineColumns
        )
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .fiveColumns)

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.9))
        )
        assertDiscards(reversal, planeId: plane?.id)
        assertLastRenderedPlaneId(reversal, nil)
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
        assertLastRenderedPlaneId(reversal, nil)
    }

    func testReversingBelowUnityNeverRendersTheSparsePlane() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(&coordinator, scale: 1.2)
        let sparsePlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertGreaterThan(sparsePlane.itemWidthRatio, 1)

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        let replacement = installedPlane(reversal)
        let discarded = reversal.contains(.discardPlane(id: sparsePlane.id))

        XCTAssertLessThan(try XCTUnwrap(renderedScale(reversal)), 1)
        XCTAssertTrue(
            replacement != nil || discarded,
            "the sparse plane must leave before a sub-unity render"
        )
        XCTAssertNotEqual(replacement?.id, sparsePlane.id)
        if let replacement {
            XCTAssertLessThan(replacement.itemWidthRatio, 1)
        }
        assertLastRenderedPlaneId(reversal, replacement?.id)
    }

    func testAdoptedSparsePlaneYieldsToCoverageSafetyBelowUnity() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let sparsePlane = try XCTUnwrap(installedPlane(menu))
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        _ = coordinator.handle(.settleTick(timestamp: 100 + 1.0 / 60))
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .threeColumns
            ),
            ratioProvider: Self.ratioProvider
        )

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.97))
        )
        let replacement = try XCTUnwrap(installedPlane(reversal))
        let scale = try XCTUnwrap(renderedScale(reversal))

        XCTAssertGreaterThan(sparsePlane.itemWidthRatio, 1)
        XCTAssertLessThan(scale, 1)
        XCTAssertNotEqual(replacement.id, sparsePlane.id)
        XCTAssertLessThan(replacement.itemWidthRatio, 1)
        assertLastRenderedPlaneId(reversal, replacement.id)
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(reversal)),
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: scale,
                itemWidthRatio: replacement.itemWidthRatio
            ),
            accuracy: 0.000_1,
            "adopted progress from the sparse plane must not transfer to its replacement"
        )
    }

    func testAdoptedDensePlaneYieldsToCoverageSafetyBelowItsRatio() throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .large,
                toMode: .threeColumns,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let densePlane = try XCTUnwrap(installedPlane(menu))
        var tickTime: TimeInterval = 100
        var runningScale: CGFloat = 1
        _ = coordinator.handle(.settleStarted(timestamp: tickTime))
        advanceSettle(
            &coordinator,
            tickTime: &tickTime,
            runningScale: &runningScale,
            untilAtMost: 0.34
        )
        XCTAssertGreaterThan(runningScale, densePlane.itemWidthRatio)
        _ = coordinator.handle(
            .pinchBegan(
                sample: makeSample(scale: 1),
                currentMode: .large
            ),
            ratioProvider: Self.ratioProvider
        )

        let reversal = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.97))
        )
        let replacement = try XCTUnwrap(installedPlane(reversal))
        let scale = try XCTUnwrap(renderedScale(reversal))

        XCTAssertLessThan(scale, densePlane.itemWidthRatio)
        XCTAssertNotEqual(replacement.id, densePlane.id)
        XCTAssertLessThan(replacement.itemWidthRatio, densePlane.itemWidthRatio)
        XCTAssertLessThanOrEqual(replacement.itemWidthRatio, scale)
        assertLastRenderedPlaneId(reversal, replacement.id)
    }

    func testMidpointJitterPerformsOneCoverageRetargetWithoutChurn() {
        var coordinator = Coordinator()
        _ = activatePinch(
            &coordinator,
            scale: 0.5,
            fromMode: .large
        )
        var installCount = 0
        var replacement: Coordinator.Plane?
        let midpointScales: [CGFloat] = [0.245, 0.252, 0.246, 0.251, 0.247, 0.25]
        for scale in midpointScales {
            let effects = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale))
            )
            if let plane = installedPlane(effects) {
                installCount += 1
                replacement = plane
            }
        }
        XCTAssertEqual(
            installCount,
            1,
            "coverage requires one retarget, then midpoint jitter must not churn it"
        )
        XCTAssertEqual(replacement?.toMode, .fiveColumns)
    }

    func testCoverageBoundaryJitterRetargetsOnceWithoutChurn() {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.5,
            fromMode: .large
        )
        XCTAssertEqual(installedPlane(activation)?.toMode, .threeColumns)

        let underfill = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.319))
        )
        XCTAssertEqual(installedPlane(underfill)?.toMode, .fiveColumns)

        for scale in [0.321, 0.319, 0.321, 0.319, 0.321] as [CGFloat] {
            let effects = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale))
            )
            XCTAssertNil(
                installedPlane(effects),
                "coverage-boundary jitter must keep the safe plane"
            )
        }

        let decisiveReturn = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.34))
        )
        XCTAssertEqual(installedPlane(decisiveReturn)?.toMode, .threeColumns)
    }

    func testDensePlaneRetargetsBeforeItUnderfillsAndReleaseReusesIt() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.5,
            fromMode: .large
        )
        let livePlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(livePlane.toMode, .threeColumns)

        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.29))
        )
        let replacement = try XCTUnwrap(installedPlane(held))
        XCTAssertEqual(replacement.toMode, .fiveColumns)
        XCTAssertNotEqual(replacement.id, livePlane.id)
        let heldScale = try XCTUnwrap(renderedScale(held))
        XCTAssertLessThanOrEqual(replacement.itemWidthRatio, heldScale)
        let heldProgress = try XCTUnwrap(settleProgress(held))
        XCTAssertEqual(
            heldProgress,
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: heldScale,
                itemWidthRatio: replacement.itemWidthRatio
            ),
            accuracy: 0.000_1
        )
        let policyRatios = Self.ratios(from: .large)
        let policyTarget = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 0.29,
                itemWidthRatios: policyRatios.map(\.itemWidthRatio)
            )
        )
        XCTAssertEqual(policyRatios[policyTarget].mode, .fiveColumns)

        let release = endPinch(&coordinator)
        XCTAssertNil(
            installedPlane(release),
            "release must reuse the coverage-safe live plane"
        )
        let settle = drainSettle(&coordinator)
        let progresses = settle.compactMap { effect -> CGFloat? in
            guard case let .renderSettle(_, _, progress, _, _) = effect else {
                return nil
            }
            return progress
        }
        XCTAssertFalse(progresses.isEmpty)
        XCTAssertTrue(progresses.allSatisfy {
            $0 >= heldProgress - 0.000_1
        })
        assertCommits(settle, planeId: replacement.id, mode: .fiveColumns)
    }

    func testDensePlaneRetargetPreservesPresentationWithoutRewindingGeometry() throws {
        var coordinator = Coordinator()
        let activationScale: CGFloat = 0.5
        let activation = activatePinch(
            &coordinator,
            scale: activationScale,
            fromMode: .large
        )
        let firstPlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(firstPlane.toMode, .threeColumns)
        let referenceScale = activationScale / activatedScale(activationScale)
        let aboveBoundaryScale = firstPlane.itemWidthRatio

        let aboveBoundary = coordinator.handle(
            .pinchChanged(sample: makeSample(
                scale: aboveBoundaryScale * referenceScale
            ))
        )
        XCTAssertNil(installedPlane(aboveBoundary))
        let priorGeometryProgress = try XCTUnwrap(
            settleProgress(aboveBoundary)
        )
        let priorPresentationProgress = try XCTUnwrap(
            presentationProgress(aboveBoundary)
        )
        XCTAssertEqual(
            try XCTUnwrap(renderedScale(aboveBoundary)),
            aboveBoundaryScale,
            accuracy: 0.000_1
        )

        let belowBoundary = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.332 * referenceScale))
        )
        let replacement = try XCTUnwrap(installedPlane(belowBoundary))
        XCTAssertEqual(replacement.toMode, .fiveColumns)
        let replacementGeometryProgress = try XCTUnwrap(
            settleProgress(belowBoundary)
        )
        let replacementPresentationProgress = try XCTUnwrap(
            presentationProgress(belowBoundary)
        )
        XCTAssertLessThan(replacementGeometryProgress, priorGeometryProgress)
        XCTAssertEqual(
            replacementGeometryProgress,
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: 0.332,
                itemWidthRatio: replacement.itemWidthRatio
            ),
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            replacementPresentationProgress,
            priorPresentationProgress,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: replacementPresentationProgress
            ),
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: priorPresentationProgress
            ),
            accuracy: 0.000_1
        )

        _ = endPinch(&coordinator)
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        let firstTick = coordinator.handle(.settleTick(timestamp: 100))
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(firstTick)),
            replacementGeometryProgress,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(firstTick)),
            replacementPresentationProgress,
            accuracy: 0.000_1
        )
    }

    func testJumpRetargetAtDestinationEndpointUsesEndpointPresentation() throws {
        var coordinator = Coordinator()
        let activationScale: CGFloat = 0.5
        let activation = activatePinch(
            &coordinator,
            scale: activationScale,
            fromMode: .large
        )
        XCTAssertEqual(installedPlane(activation)?.toMode, .threeColumns)
        XCTAssertLessThan(
            try XCTUnwrap(presentationProgress(activation)),
            1
        )
        let referenceScale = activationScale / activatedScale(activationScale)

        let jump = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.2 * referenceScale))
        )
        let replacement = try XCTUnwrap(installedPlane(jump))
        XCTAssertEqual(replacement.toMode, .fiveColumns)
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(jump)),
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(jump)),
            1,
            accuracy: 0.000_1
        )
    }

    func testReleaseCannotReinstallADensePlaneThatWouldUnderfill() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 0.5,
            fromMode: .large
        )
        let firstPlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(firstPlane.toMode, .threeColumns)

        let retarget = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.31))
        )
        let coveragePlane = try XCTUnwrap(installedPlane(retarget))
        let scale = try XCTUnwrap(renderedScale(retarget))
        XCTAssertEqual(coveragePlane.toMode, .fiveColumns)
        XCTAssertLessThan(scale, firstPlane.itemWidthRatio)
        XCTAssertLessThanOrEqual(coveragePlane.itemWidthRatio, scale)
        let policyRatios = Self.ratios(from: .large)
        let policyTarget = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 0.31,
                itemWidthRatios: policyRatios.map(\.itemWidthRatio)
            )
        )
        XCTAssertEqual(policyRatios[policyTarget].mode, .threeColumns)

        let release = endPinch(&coordinator)
        XCTAssertNil(
            installedPlane(release),
            "release must not reinstall a plane whose ratio exceeds its scale"
        )
        let settle = drainSettle(&coordinator)
        assertCommits(
            settle,
            planeId: coveragePlane.id,
            mode: .fiveColumns
        )
    }

    func testSparseReleaseInsideRetargetHysteresisKeepsVisiblePlane() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 1.2,
            fromMode: .fiveColumns
        )
        let livePlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(livePlane.toMode, .threeColumns)

        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 2.1))
        )
        XCTAssertNil(installedPlane(held))
        let heldProgress = try XCTUnwrap(settleProgress(held))
        XCTAssertEqual(heldProgress, 1, accuracy: 0.000_1)
        let policyRatios = Self.ratios(from: .fiveColumns)
        let policyTarget = try XCTUnwrap(
            PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: 2.1,
                itemWidthRatios: policyRatios.map(\.itemWidthRatio)
            )
        )
        XCTAssertEqual(policyRatios[policyTarget].mode, .large)

        let release = endPinch(&coordinator)
        XCTAssertNil(
            installedPlane(release),
            "release must not swap lattices after fully revealing the live plane"
        )
        let settle = drainSettle(&coordinator)
        let progresses = settle.compactMap { effect -> CGFloat? in
            guard case let .renderSettle(_, _, progress, _, _) = effect else {
                return nil
            }
            return progress
        }
        XCTAssertFalse(progresses.isEmpty)
        XCTAssertTrue(progresses.allSatisfy {
            $0 >= heldProgress - 0.000_1
        })
        assertCommits(settle, planeId: livePlane.id, mode: .threeColumns)
    }

    func testDeepSparseZoomRetargetsAtTheReleaseLadderBoundary() throws {
        var coordinator = Coordinator()
        let activation = activatePinch(
            &coordinator,
            scale: 1.2,
            fromMode: .fiveColumns
        )
        let livePlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(livePlane.toMode, .threeColumns)

        let retargeted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 2.5))
        )
        let deepPlane = try XCTUnwrap(installedPlane(retargeted))
        XCTAssertEqual(
            deepPlane.toMode,
            .large,
            "past the ladder boundary the plane shows the lattice a release lands on"
        )

        _ = endPinch(&coordinator)
        let settle = drainSettle(&coordinator)
        assertCommits(settle, planeId: deepPlane.id, mode: .large)
    }

    func testReleaseMayRetreatFromADeeperPlaneInsideHysteresis() throws {
        var coordinator = Coordinator()
        let ratios = [
            Coordinator.ModeRatio(mode: .large, itemWidthRatio: 1),
            Coordinator.ModeRatio(mode: .threeColumns, itemWidthRatio: 0.5),
            Coordinator.ModeRatio(mode: .fiveColumns, itemWidthRatio: 0.48)
        ]
        let activation = activatePinch(
            &coordinator,
            scale: 0.46,
            fromMode: .large,
            ratios: ratios
        )
        let deepPlane = try XCTUnwrap(installedPlane(activation))
        XCTAssertEqual(deepPlane.toMode, .fiveColumns)

        let retreated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.5))
        )
        XCTAssertNil(installedPlane(retreated))
        let liveProgress = try XCTUnwrap(settleProgress(retreated))

        let release = endStationaryPinch(&coordinator)
        let replacement = try XCTUnwrap(installedPlane(release))
        XCTAssertEqual(replacement.toMode, .threeColumns)
        let releaseScale = try XCTUnwrap(renderedScale(release))
        let releaseProgress = try XCTUnwrap(settleProgress(release))
        XCTAssertEqual(
            releaseProgress,
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: releaseScale,
                itemWidthRatio: replacement.itemWidthRatio
            ),
            accuracy: 0.000_1
        )
        XCTAssertGreaterThanOrEqual(
            releaseProgress,
            liveProgress,
            "retreating to a sourceward target may replace the deeper plane when it does not rewind"
        )
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        let firstTick = coordinator.handle(.settleTick(timestamp: 100.01))
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(settleProgress(firstTick)),
            releaseProgress
        )
    }

    func testSaturatedReleaseReplacementPreservesPresentationUnderCover()
        throws {
        var coordinator = Coordinator()
        let ratios = [
            Coordinator.ModeRatio(mode: .large, itemWidthRatio: 1),
            Coordinator.ModeRatio(mode: .threeColumns, itemWidthRatio: 0.6),
            Coordinator.ModeRatio(mode: .fiveColumns, itemWidthRatio: 0.4)
        ]
        let activation = activatePinch(
            &coordinator,
            scale: 0.38,
            fromMode: .large,
            ratios: ratios
        )
        XCTAssertEqual(installedPlane(activation)?.toMode, .fiveColumns)
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10))
        _ = coordinator.handle(.interactionFadeTick(timestamp: 10.8))

        let retreated = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.6))
        )
        XCTAssertNil(installedPlane(retreated))
        XCTAssertLessThan(
            try XCTUnwrap(settleProgress(retreated)),
            PlayerBrowserGridCrossfade.contentFadeEndSettleProgress
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(retreated)),
            1,
            accuracy: 0.000_1
        )

        let release = endStationaryPinch(&coordinator)
        let replacement = try XCTUnwrap(installedPlane(release))
        XCTAssertEqual(replacement.toMode, .threeColumns)
        let coverIndex = try XCTUnwrap(
            release.firstIndex(of: .coverPlaneChange)
        )
        let installIndex = try XCTUnwrap(
            release.firstIndex(of: .installPlane(replacement))
        )
        XCTAssertLessThan(coverIndex, installIndex)
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(release)),
            1,
            accuracy: 0.000_1
        )
    }

    func testRegrabbingEndpointReplacementPreservesPresentationThroughHandoff() throws {
        var coordinator = Coordinator()
        let ratios = [
            Coordinator.ModeRatio(mode: .fiveColumns, itemWidthRatio: 1),
            Coordinator.ModeRatio(mode: .threeColumns, itemWidthRatio: 1.05),
            Coordinator.ModeRatio(mode: .large, itemWidthRatio: 1.11)
        ]
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .fiveColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: { _ in ratios }
        )
        let deepPlane = try XCTUnwrap(installedPlane(menu))
        XCTAssertEqual(deepPlane.toMode, .large)
        _ = coordinator.handle(.settleStarted(timestamp: 100))

        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1),
                    currentMode: .fiveColumns
                ),
                ratioProvider: { _ in ratios }
            ),
            [.stopDisplayLink, .beginInteraction, .startInteractionFadeTicks]
        )
        let adjusted = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.052))
        )
        assertLastRenderedPlaneId(adjusted, deepPlane.id)
        let carriedPresentation = try XCTUnwrap(
            presentationProgress(adjusted)
        )
        XCTAssertEqual(
            carriedPresentation,
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: 1.052,
                itemWidthRatio: deepPlane.itemWidthRatio
            ),
            accuracy: 0.000_1
        )
        let carriedAlpha = PlayerBrowserGridCrossfade.incomingContentAlpha(
            settleProgress: carriedPresentation
        )
        XCTAssertGreaterThan(carriedAlpha, 0)
        XCTAssertLessThan(carriedAlpha, 1)

        let released = endStationaryPinch(&coordinator)
        let replacement = try XCTUnwrap(installedPlane(released))
        XCTAssertEqual(replacement.toMode, .threeColumns)
        let coverIndex = try XCTUnwrap(
            released.firstIndex(of: .coverPlaneChange)
        )
        let installIndex = try XCTUnwrap(
            released.firstIndex(of: .installPlane(replacement))
        )
        XCTAssertLessThan(coverIndex, installIndex)
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(released)),
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(released)),
            carriedPresentation,
            accuracy: 0.000_1
        )
        XCTAssertTrue(released.contains(.startDisplayLink))
        _ = coordinator.handle(.settleStarted(timestamp: 101))

        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1),
                    currentMode: .fiveColumns
                ),
                ratioProvider: { _ in ratios }
            ),
            [.stopDisplayLink, .beginInteraction, .startInteractionFadeTicks]
        )
        let held = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(held)),
            1,
            accuracy: 0.000_1
        )
        let heldPresentation = try XCTUnwrap(presentationProgress(held))
        XCTAssertEqual(
            heldPresentation,
            carriedPresentation,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: heldPresentation
            ),
            carriedAlpha,
            accuracy: 0.000_1
        )

        let sourceward = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.997))
        )
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(presentationProgress(sourceward)),
            heldPresentation + 0.000_1,
            "moving toward the source must not advance destination content"
        )

        _ = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1))
        )

        let handingOff = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.02))
        )
        let handoffPresentation = try XCTUnwrap(
            presentationProgress(handingOff)
        )
        XCTAssertGreaterThan(handoffPresentation, heldPresentation)
        XCTAssertLessThan(handoffPresentation, 1)

        let handedOff = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 1.05))
        )
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(handedOff)),
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(handedOff)),
            1,
            accuracy: 0.000_1
        )
    }

    func testRegrabRetargetAtGeometryEndpointPreservesPartialPresentation()
        throws {
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .fiveColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: Self.ratioProvider
        )
        let largePlane = try XCTUnwrap(installedPlane(menu))
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        var tickTime: TimeInterval = 100
        var latestAdoptedScale: CGFloat?
        for _ in 0 ..< 7 {
            tickTime += 1 / 60
            let tick = coordinator.handle(.settleTick(timestamp: tickTime))
            latestAdoptedScale = renderedScale(tick)
        }
        let adoptedScale = try XCTUnwrap(latestAdoptedScale)
        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1),
                    currentMode: .fiveColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            [.stopDisplayLink, .beginInteraction, .startInteractionFadeTicks]
        )

        var previousPresentation: CGFloat?
        for scale in [1, 0.99, 0.98, 0.97] as [CGFloat] {
            let effects = coordinator.handle(
                .pinchChanged(sample: makeSample(scale: scale))
            )
            previousPresentation = presentationProgress(effects)
        }
        let retarget = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.96))
        )
        let replacement = try XCTUnwrap(installedPlane(retarget))
        XCTAssertEqual(replacement.toMode, .threeColumns)
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(retarget)),
            1,
            accuracy: 0.000_1
        )
        let retargetPresentation = try XCTUnwrap(
            presentationProgress(retarget)
        )
        let priorPresentation = try XCTUnwrap(previousPresentation)
        XCTAssertGreaterThan(retargetPresentation, 0)
        XCTAssertLessThan(retargetPresentation, 1)
        XCTAssertLessThan(
            abs(retargetPresentation - priorPresentation),
            0.02
        )
        XCTAssertEqual(
            retargetPresentation,
            PlayerBrowserGridCrossfade.driftProgress(
                forScale: try XCTUnwrap(renderedScale(retarget)),
                itemWidthRatio: largePlane.itemWidthRatio
            ),
            accuracy: 0.000_1
        )

        let sourceward = coordinator.handle(
            .pinchChanged(sample: makeSample(scale: 0.955))
        )
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(presentationProgress(sourceward)),
            retargetPresentation + 0.000_1
        )

        let atTarget = coordinator.handle(.pinchChanged(sample: makeSample(
            scale: replacement.itemWidthRatio / adoptedScale
        )))
        XCTAssertEqual(
            try XCTUnwrap(renderedScale(atTarget)),
            replacement.itemWidthRatio,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(atTarget)),
            1,
            accuracy: 0.000_1
        )
        let presentationAtTarget = try XCTUnwrap(
            presentationProgress(atTarget)
        )
        XCTAssertEqual(
            presentationAtTarget,
            retargetPresentation,
            accuracy: 0.000_1
        )

        let nearTarget = coordinator.handle(.pinchChanged(sample: makeSample(
            scale: replacement.itemWidthRatio
                * exp(
                    PlayerBrowserGridPinchPolicy.settleRestLogDistance
                        * 1.005
                ) / adoptedScale
        )))
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(nearTarget)),
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(nearTarget)),
            presentationAtTarget,
            accuracy: 0.000_1
        )

        let release = endPinch(&coordinator)
        XCTAssertTrue(release.contains(.startDisplayLink))
        XCTAssertNil(presentationProgress(release))
        XCTAssertFalse(release.contains {
            if case .commitPlane = $0 { return true }
            return false
        })

        let settleStart = tickTime + 0.01
        XCTAssertEqual(
            coordinator.handle(.settleStarted(timestamp: settleStart)),
            []
        )
        let firstTick = coordinator.handle(.settleTick(
            timestamp: settleStart
        ))
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(firstTick)),
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(firstTick)),
            presentationAtTarget,
            accuracy: 0.000_1
        )
        let nextTickTime = settleStart + 1 / 60
        let nextTick = coordinator.handle(.settleTick(
            timestamp: nextTickTime
        ))
        let nextPresentation = try XCTUnwrap(
            presentationProgress(nextTick)
        )
        XCTAssertGreaterThan(nextPresentation, presentationAtTarget)
        XCTAssertLessThan(nextPresentation, 1)
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(nextTick)),
            1,
            accuracy: 0.000_1
        )

        let settle = drainSettle(&coordinator, startTime: nextTickTime)
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(settle)),
            1,
            accuracy: 0.000_1
        )
        assertCommits(
            settle,
            planeId: replacement.id,
            mode: .threeColumns
        )
    }

    func testExactTargetReleasePreservesPartialAdoptedSettleGeometry()
        throws {
        let ratios = [
            Coordinator.ModeRatio(
                mode: .fiveColumns,
                itemWidthRatio: 1
            ),
            Coordinator.ModeRatio(
                mode: .threeColumns,
                itemWidthRatio: 1.01
            ),
            Coordinator.ModeRatio(
                mode: .large,
                itemWidthRatio: 1.02
            )
        ]
        var coordinator = Coordinator()
        let menu = coordinator.handle(
            .menuSelected(
                fromMode: .fiveColumns,
                toMode: .large,
                reduceMotion: false
            ),
            ratioProvider: { _ in ratios }
        )
        let plane = try XCTUnwrap(installedPlane(menu))
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        var adoptedScale: CGFloat?
        for step in 1 ... 3 {
            adoptedScale = renderedScale(coordinator.handle(
                .settleTick(timestamp: 100 + Double(step) / 60)
            ))
        }
        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1),
                    currentMode: .fiveColumns
                ),
                ratioProvider: { _ in ratios }
            ),
            [.stopDisplayLink, .beginInteraction, .startInteractionFadeTicks]
        )
        let resolvedAdoptedScale = try XCTUnwrap(adoptedScale)
        let atTarget = coordinator.handle(.pinchChanged(sample: makeSample(
            scale: plane.itemWidthRatio / resolvedAdoptedScale
        )))
        XCTAssertEqual(
            try XCTUnwrap(renderedScale(atTarget)),
            plane.itemWidthRatio,
            accuracy: 0.000_1
        )
        let progressAtTarget = try XCTUnwrap(settleProgress(atTarget))
        let presentationAtTarget = try XCTUnwrap(
            presentationProgress(atTarget)
        )
        XCTAssertGreaterThan(progressAtTarget, 0)
        XCTAssertLessThan(progressAtTarget, 1)
        XCTAssertEqual(
            presentationAtTarget,
            progressAtTarget,
            accuracy: 0.000_1
        )

        XCTAssertEqual(endPinch(&coordinator), [.startDisplayLink])
        XCTAssertEqual(
            coordinator.handle(.settleStarted(timestamp: 200)),
            []
        )
        let firstTick = coordinator.handle(.settleTick(timestamp: 200))
        XCTAssertEqual(
            try XCTUnwrap(renderedScale(firstTick)),
            plane.itemWidthRatio,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(firstTick)),
            progressAtTarget,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(firstTick)),
            presentationAtTarget,
            accuracy: 0.000_1
        )

        let nextTickTime: TimeInterval = 200 + 1.0 / 60
        let nextTick = coordinator.handle(.settleTick(
            timestamp: nextTickTime
        ))
        let nextProgress = try XCTUnwrap(settleProgress(nextTick))
        let nextPresentation = try XCTUnwrap(
            presentationProgress(nextTick)
        )
        XCTAssertGreaterThan(nextProgress, progressAtTarget)
        XCTAssertLessThan(nextProgress, 1)
        XCTAssertEqual(nextPresentation, nextProgress, accuracy: 0.000_1)

        let settle = drainSettle(&coordinator, startTime: nextTickTime)
        XCTAssertEqual(
            try XCTUnwrap(settleProgress(settle)),
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(presentationProgress(settle)),
            1,
            accuracy: 0.000_1
        )
        assertCommits(settle, planeId: plane.id, mode: .large)
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
            try XCTUnwrap(renderedScale(activation)),
            activatedScale(2.0),
            accuracy: 0.000_1,
            "an in-range scale is rendered untouched, not banded toward 1"
        )

        let beyond = coordinator.handle(.pinchChanged(sample: makeSample(scale: 8)))
        let banded = try XCTUnwrap(renderedScale(beyond))
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

        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1, timestamp: .nan),
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
            try XCTUnwrap(renderedScale(activation)),
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
        assertLastRenderedPlaneId(changed, plane.id)
        guard let panDeltaY = renderedPanDeltaY(changed) else {
            return XCTFail("expected a render effect, got \(changed)")
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
            .pinchEnded(
                scale: lastSampleScale,
                reduceMotion: false,
                timestamp: 1
            ),
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

    func testTrackingReleaseActivatesFromTerminalScale() throws {
        var coordinator = Coordinator()
        XCTAssertEqual(
            coordinator.handle(
                .pinchBegan(
                    sample: makeSample(scale: 1, timestamp: 0),
                    currentMode: .threeColumns
                ),
                ratioProvider: Self.ratioProvider
            ),
            []
        )

        let released = coordinator.handle(
            .pinchEnded(
                scale: 0.5,
                reduceMotion: false,
                timestamp: 0.02
            )
        )
        let plane = try XCTUnwrap(installedPlane(released))
        XCTAssertEqual(plane.toMode, .nineColumns)
        XCTAssertTrue(released.contains(.beginInteraction))
        XCTAssertEqual(coordinator.phase, .settling)
        assertCommits(
            released + drainSettle(&coordinator),
            planeId: plane.id,
            mode: .nineColumns
        )
    }
}
