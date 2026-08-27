// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridInteractionCoordinatorTests: XCTestCase {

    typealias Coordinator = PlayerBrowserGridInteractionCoordinator
    typealias Effect = Coordinator.Effect
    var sampleTimestamp: TimeInterval = 0
    var lastSampleScale: CGFloat = 1

    static func ratios(
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

    static let ratioProvider: Coordinator.RatioProvider = {
        ratios(from: $0)
    }

    func makeSample(
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

    func nextSampleTimestamp() -> TimeInterval {
        sampleTimestamp += 0.02
        return sampleTimestamp
    }

    /// Starts a pinch and crosses the activation dead zone at the given scale.
    func activatePinch(
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

    func activatedScale(_ rawScale: CGFloat) -> CGFloat {
        PlayerBrowserGridPinchPolicy.effectiveScaleAfterActivation(rawScale)
    }

    func renderedScale(_ effects: [Effect]) -> CGFloat? {
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

    func settleProgress(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            if case let .renderSettle(_, _, progress, _, _) = effect {
                return progress
            }
        }
        return nil
    }

    func presentationProgress(_ effects: [Effect]) -> CGFloat? {
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

    func renderedPanDeltaY(_ effects: [Effect]) -> CGFloat? {
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

    func settleScale(_ effects: [Effect]) -> CGFloat? {
        for effect in effects.reversed() {
            if case let .renderSettle(_, scale, _, _, _) = effect {
                return scale
            }
        }
        return nil
    }

    func installedPlane(_ effects: [Effect]) -> Coordinator.Plane? {
        for effect in effects {
            if case let .installPlane(plane) = effect {
                return plane
            }
        }
        return nil
    }

    func committedModes(
        _ effects: [Effect]
    ) -> [MobileCollectionBrowserGridMode] {
        effects.compactMap { effect in
            if case let .commitPlane(_, mode) = effect {
                return mode
            }
            return nil
        }
    }

    func assertLastRenderedPlaneId(
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

    func assertCommits(
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

    func assertDiscards(
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
    func endPinch(
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
    func endStationaryPinch(
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
    func settlePartway(_ coordinator: inout Coordinator) {
        _ = coordinator.handle(.settleStarted(timestamp: 100))
        _ = coordinator.handle(.settleTick(timestamp: 100.05))
    }

    func drainSettle(
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

    func advanceSettle(
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
}
