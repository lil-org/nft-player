// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridInteractionCoordinatorTests: XCTestCase {

    private typealias Coordinator = PlayerBrowserGridInteractionCoordinator
    private typealias Effect = Coordinator.Effect
    private var sampleTimestamp: TimeInterval = 0
    private var lastSampleScale: CGFloat = 1

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
        timestamp: TimeInterval? = nil
    ) -> Coordinator.PinchSample {
        let timestamp = timestamp ?? nextSampleTimestamp()
        if timestamp.isFinite {
            sampleTimestamp = max(sampleTimestamp, timestamp)
        }
        if scale.isFinite, scale > 0 {
            lastSampleScale = scale
        }
        return Coordinator.PinchSample(
            scale: scale,
            centroidY: centroidY,
            timestamp: timestamp
        )
    }

    private func nextSampleTimestamp() -> TimeInterval {
        sampleTimestamp += 0.02
        return sampleTimestamp
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

    private func renderedScale(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            switch effect {
            case let .renderZoom(_, scale, _):
                return scale
            case let .renderSettle(_, scale, _, _, _):
                return scale
            default:
                continue
            }
        }
        return nil
    }

    private func settleProgress(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            if case let .renderSettle(_, _, progress, _, _) = effect {
                return progress
            }
        }
        return nil
    }

    private func presentationProgress(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            switch effect {
            case let .renderSettle(_, _, _, progress, _),
                 let .renderInteractionFade(_, progress):
                return progress
            default:
                continue
            }
        }
        return nil
    }

    private func renderedPanDeltaY(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            switch effect {
            case let .renderZoom(_, _, panDeltaY):
                return panDeltaY
            case let .renderSettle(_, _, _, _, panDeltaY):
                return panDeltaY
            default:
                continue
            }
        }
        return nil
    }

    private func settleScale(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            if case let .renderSettle(_, scale, _, _, _) = effect {
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

    private func assertLastRenderedPlaneId(
        _ effects: [Effect],
        _ expected: UUID?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let effect = effects.last else {
            return XCTFail(
                "expected a render effect, got \(effects)",
                file: file,
                line: line
            )
        }
        let planeId: UUID?
        switch effect {
        case let .renderZoom(id, _, _):
            planeId = id
        case let .renderSettle(id, _, _, _, _):
            planeId = id
        case let .renderInteractionFade(id, _):
            planeId = id
        default:
            return XCTFail(
                "expected a render effect, got \(effects)",
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
        guard let discardIndex = effects.firstIndex(
            of: .discardPlane(id: planeId)
        ) else {
            return XCTFail("plane was not discarded", file: file, line: line)
        }
        guard let coverIndex = effects[..<discardIndex].lastIndex(
            of: .coverPlaneChange
        ) else {
            return XCTFail("discard was not covered", file: file, line: line)
        }
        XCTAssertLessThan(coverIndex, discardIndex, file: file, line: line)
    }

    @discardableResult
    private func endPinch(
        _ coordinator: inout Coordinator,
        reduceMotion: Bool = false
    ) -> [Effect] {
        return coordinator.handle(.pinchEnded(
            scale: lastSampleScale,
            reduceMotion: reduceMotion,
            timestamp: nextSampleTimestamp()
        ))
    }

    @discardableResult
    private func endStationaryPinch(
        _ coordinator: inout Coordinator,
        reduceMotion: Bool = false
    ) -> [Effect] {
        sampleTimestamp += PlayerBrowserGridPinchPolicy
            .releaseMotionHoldTimeout + 0.02
        return coordinator.handle(.pinchEnded(
            scale: lastSampleScale,
            reduceMotion: reduceMotion,
            timestamp: sampleTimestamp
        ))
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

    // MARK: - Under plane while zooming out

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
            fromMode: .fiveColumns
        )
        let plane = installedPlane(activation)
        XCTAssertEqual(plane?.toMode, .threeColumns)

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

    // MARK: - Release outcomes

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
            wrapUp.contains(.reconcileMedia(cancelsPrefetchLoads: false))
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
        XCTAssertEqual(plane.toMode, .fiveColumns)
        XCTAssertTrue(released.contains(.beginInteraction))
        XCTAssertEqual(coordinator.phase, .settling)
        assertCommits(
            released + drainSettle(&coordinator),
            planeId: plane.id,
            mode: .fiveColumns
        )
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

    // MARK: - Photos fade clock and release motion

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
