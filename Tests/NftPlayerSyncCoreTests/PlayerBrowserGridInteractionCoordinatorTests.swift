// ∅ 2026 lil org

import CoreGraphics
import XCTest
@testable import NftPlayerSyncCore

final class PlayerBrowserGridInteractionCoordinatorTests: XCTestCase {

    private typealias Coordinator = PlayerBrowserGridInteractionCoordinator
    private typealias Effect = Coordinator.Effect
    private typealias Mode = MobileCollectionBrowserGridMode
    private static let viewportSize = CGSize(width: 390, height: 844)

    private func itemWidth(for mode: Mode) -> CGFloat {
        guard let itemWidth = MobilePlayerBrowserLayout.itemWidth(
            viewportSize: Self.viewportSize,
            columnCount: mode.columnCount
        ) else {
            fatalError("Expected valid test viewport geometry")
        }
        return itemWidth
    }

    private func sample(
        scale: CGFloat,
        centroidY: CGFloat = 200
    ) -> Coordinator.PinchSample {
        Coordinator.PinchSample(
            scale: scale,
            centroidY: centroidY
        )
    }

    private func transition(
        from fromMode: Mode,
        to toMode: Mode
    ) -> Coordinator.Transition {
        let id = UUID(uuidString: String(
            format: "00000000-0000-0000-0000-0000000000%d%d",
            fromMode.rawValue,
            toMode.rawValue
        ))!
        return Coordinator.Transition(
            id: id,
            fromMode: fromMode,
            toMode: toMode,
            itemWidthRatio: itemWidth(for: toMode)
                / itemWidth(for: fromMode)
        )!
    }

    private func transitionProvider(
        from fromMode: Mode,
        to toMode: Mode
    ) -> Coordinator.Transition? {
        transition(from: fromMode, to: toMode)
    }

    private func activatedScale(
        from fromMode: Mode,
        to toMode: Mode,
        progress: CGFloat
    ) -> CGFloat {
        let ratio = itemWidth(for: toMode) / itemWidth(for: fromMode)
        let effectiveScale = effectiveScaleAtProgress(
            from: fromMode,
            to: toMode,
            progress: progress
        )
        let activationBoundary = ratio > 1
            ? 1 + PlayerBrowserGridPinchPolicy.activationScaleDeviation
            : 1 - PlayerBrowserGridPinchPolicy.activationScaleDeviation
        return activationBoundary * effectiveScale
    }

    private func effectiveScaleAtProgress(
        from fromMode: Mode,
        to toMode: Mode,
        progress: CGFloat
    ) -> CGFloat {
        let ratio = itemWidth(for: toMode) / itemWidth(for: fromMode)
        return 1 + (ratio - 1) * progress
    }

    @discardableResult
    private func beginPinch(
        _ coordinator: inout Coordinator,
        mode: Mode,
        defaultMode: Mode,
        scale: CGFloat = 1,
        centroidY: CGFloat = 200
    ) -> [Effect] {
        coordinator.handle(.pinchBegan(
            sample: sample(scale: scale, centroidY: centroidY),
            currentMode: mode,
            defaultMode: defaultMode,
            adoptedTransitionWasReanchored: false
        ))
    }

    private func drainChanged(
        _ sample: Coordinator.PinchSample,
        coordinator: inout Coordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Effect] {
        driveEffects(
            coordinator.handle(
                .pinchChanged(sample: sample),
                transitionProvider: transitionProvider(from:to:)
            ),
            coordinator: &coordinator,
            file: file,
            line: line
        )
    }

    private func handleAndDrive(
        _ event: Coordinator.Event,
        coordinator: inout Coordinator,
        usesTransitionProvider: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Effect] {
        let effects = usesTransitionProvider
            ? coordinator.handle(
                event,
                transitionProvider: transitionProvider(from:to:)
            )
            : coordinator.handle(event)
        return driveEffects(
            effects,
            coordinator: &coordinator,
            file: file,
            line: line
        )
    }

    private func driveEffects(
        _ initialEffects: [Effect],
        coordinator: inout Coordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Effect] {
        var allEffects = [Effect]()
        var pendingEffects = initialEffects
        var continuationCount = 0
        var rendererActionCount = 0
        while !pendingEffects.isEmpty {
            let effect = pendingEffects.removeFirst()
            allEffects.append(effect)
            let nextEffects: [Effect]
            switch effect {
            case .commitTransition, .discardTransition, .applyMode:
                rendererActionCount += 1
                XCTAssertLessThanOrEqual(
                    rendererActionCount,
                    Mode.allCases.count + 1,
                    file: file,
                    line: line
                )
                nextEffects = coordinator.handle(.rendererSucceeded)

            case let .continuePinch(sample):
                continuationCount += 1
                XCTAssertLessThanOrEqual(
                    continuationCount,
                    Mode.allCases.count,
                    file: file,
                    line: line
                )
                nextEffects = coordinator.handle(
                    .pinchChanged(sample: sample),
                    transitionProvider: transitionProvider(from:to:)
                )

            default:
                nextEffects = []
            }
            pendingEffects.insert(contentsOf: nextEffects, at: 0)
        }
        return allEffects
    }

    private func committedModes(in effects: [Effect]) -> [Mode] {
        effects.compactMap { effect in
            guard case let .commitTransition(_, mode) = effect else { return nil }
            return mode
        }
    }

    private func discardedTransitionIDs(in effects: [Effect]) -> [UUID] {
        effects.compactMap { effect in
            guard case let .discardTransition(id) = effect else { return nil }
            return id
        }
    }

    private func installedTransitions(
        in effects: [Effect]
    ) -> [Coordinator.Transition] {
        effects.compactMap { effect in
            guard case let .installTransition(transition) = effect else {
                return nil
            }
            return transition
        }
    }

    private func renderedProgresses(in effects: [Effect]) -> [CGFloat] {
        effects.compactMap { effect in
            guard case let .renderTransition(_, progress, _) = effect else {
                return nil
            }
            return progress
        }
    }

    private func reconciliations(
        in effects: [Effect]
    ) -> [Coordinator.MediaReconciliation] {
        effects.compactMap { effect in
            guard case let .reconcileMedia(reconciliation) = effect else {
                return nil
            }
            return reconciliation
        }
    }

    private func persistedModes(in effects: [Effect]) -> [Mode] {
        effects.compactMap { effect in
            guard case let .persistMode(mode) = effect else { return nil }
            return mode
        }
    }

    private func finishEffects(in effects: [Effect]) -> [Bool] {
        effects.compactMap { effect in
            guard case let .finishInteraction(settlesPosition) = effect else {
                return nil
            }
            return settlesPosition
        }
    }

    private func hapticCount(in effects: [Effect]) -> Int {
        effects.filter { $0 == .selectionHaptic }.count
    }

    func testTransitionRetainsSourceModeAndRejectsContradictoryRatios() {
        let validTransition = transition(from: .threeColumns, to: .twoColumns)

        XCTAssertEqual(validTransition.fromMode, .threeColumns)
        XCTAssertEqual(validTransition.toMode, .twoColumns)
        XCTAssertNil(Coordinator.Transition(
            fromMode: .threeColumns,
            toMode: .twoColumns,
            itemWidthRatio: 0.8
        ))
        XCTAssertNil(Coordinator.Transition(
            fromMode: .twoColumns,
            toMode: .threeColumns,
            itemWidthRatio: 1.2
        ))
    }

    func testMenuRejectsTransitionsThatDoNotMatchRequestedModes() {
        let invalidTransitions = [
            transition(from: .fourColumns, to: .large),
            transition(from: .threeColumns, to: .twoColumns),
        ]

        for invalidTransition in invalidTransitions {
            var coordinator = Coordinator()
            let effects = coordinator.handle(
                .menuSelected(
                    fromMode: .threeColumns,
                    toMode: .large,
                    defaultMode: .threeColumns,
                    reduceMotion: false
                ),
                transitionProvider: { _, _ in invalidTransition }
            )

            XCTAssertEqual(effects, [
                .beginInteraction,
                .applyMode(.large),
            ])
            XCTAssertEqual(coordinator.currentMode, .threeColumns)
            XCTAssertEqual(coordinator.phase, .settling)
        }
    }

    func testPinchRejectsTransitionsThatDoNotMatchRequestedModes() {
        let invalidTransitions = [
            transition(from: .fourColumns, to: .twoColumns),
            transition(from: .threeColumns, to: .large),
        ]

        for invalidTransition in invalidTransitions {
            var coordinator = Coordinator()
            beginPinch(
                &coordinator,
                mode: .threeColumns,
                defaultMode: .threeColumns
            )
            let effects = coordinator.handle(
                .pinchChanged(sample: sample(scale: 1.05)),
                transitionProvider: { _, _ in invalidTransition }
            )

            XCTAssertTrue(effects.contains(.beginInteraction))
            XCTAssertEqual(installedTransitions(in: effects), [])
            XCTAssertEqual(committedModes(in: effects), [])
            XCTAssertEqual(coordinator.currentMode, .threeColumns)
            XCTAssertEqual(coordinator.phase, .interacting)
        }
    }

    func testActivationDeadZoneTracksWithoutBeginningInteractionInBothDirections() {
        for scale in [CGFloat(1.039), 0.961] {
            var coordinator = Coordinator()
            XCTAssertEqual(
                beginPinch(
                    &coordinator,
                    mode: .threeColumns,
                    defaultMode: .threeColumns
                ),
                []
            )

            let effects = coordinator.handle(
                .pinchChanged(sample: sample(scale: scale)),
                transitionProvider: transitionProvider(from:to:)
            )

            XCTAssertEqual(effects, [])
            XCTAssertEqual(coordinator.phase, .tracking)
            XCTAssertEqual(coordinator.currentMode, .threeColumns)
            XCTAssertFalse(coordinator.didCommitGeometry)
            XCTAssertEqual(coordinator.handle(.interrupt), [])
            XCTAssertEqual(coordinator.phase, .idle)
        }
    }

    func testActivationBeyondDeadZoneBeginsTowardTheExpectedNeighbor() {
        for (scale, expectedMode) in [
            (CGFloat(1.05), Mode.twoColumns),
            (CGFloat(0.95), Mode.fourColumns)
        ] {
            var coordinator = Coordinator()
            beginPinch(
                &coordinator,
                mode: .threeColumns,
                defaultMode: .threeColumns
            )

            let effects = coordinator.handle(
                .pinchChanged(sample: sample(scale: scale)),
                transitionProvider: transitionProvider(from:to:)
            )

            XCTAssertEqual(effects.first, .beginInteraction)
            XCTAssertEqual(installedTransitions(in: effects).map(\.toMode), [expectedMode])
            XCTAssertEqual(coordinator.phase, .interacting)
        }
    }

    func testPinchCompletionUsesProgressThresholdWithoutVelocity() {
        for (progress, expectedMode) in [
            (CGFloat(0.4), Mode.threeColumns),
            (CGFloat(0.6), Mode.twoColumns)
        ] {
            var coordinator = Coordinator()
            beginPinch(
                &coordinator,
                mode: .threeColumns,
                defaultMode: .threeColumns
            )
            _ = drainChanged(
                sample(scale: activatedScale(
                    from: .threeColumns,
                    to: .twoColumns,
                    progress: progress
                )),
                coordinator: &coordinator
            )

            let effects = handleAndDrive(
                .pinchEnded(
                    velocity: 0,
                    timestamp: 10,
                    reduceMotion: true
                ),
                coordinator: &coordinator
            )

            XCTAssertEqual(committedModes(in: effects).last, expectedMode == .twoColumns ? .twoColumns : nil)
            XCTAssertEqual(persistedModes(in: effects), expectedMode == .twoColumns ? [.twoColumns] : [])
            XCTAssertEqual(coordinator.phase, .idle)
        }
    }

    func testPinchCompletionUsesVelocityThresholdAndHonorsReverseVelocity() {
        var committingCoordinator = Coordinator()
        beginPinch(
            &committingCoordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.2
            )),
            coordinator: &committingCoordinator
        )
        let commitEffects = handleAndDrive(
            .pinchEnded(
                velocity: 10,
                timestamp: 10,
                reduceMotion: true
            ),
            coordinator: &committingCoordinator
        )
        XCTAssertEqual(committedModes(in: commitEffects), [.twoColumns])

        var cancellingCoordinator = Coordinator()
        beginPinch(
            &cancellingCoordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.8
            )),
            coordinator: &cancellingCoordinator
        )
        let cancelEffects = handleAndDrive(
            .pinchEnded(
                velocity: -10,
                timestamp: 10,
                reduceMotion: true
            ),
            coordinator: &cancellingCoordinator
        )
        XCTAssertEqual(committedModes(in: cancelEffects), [])
        XCTAssertEqual(discardedTransitionIDs(in: cancelEffects).count, 1)
    }

    func testMultiBoundaryPinchCommitsFourColumnsToLarge() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .fourColumns,
            defaultMode: .threeColumns
        )

        let changedEffects = drainChanged(
            sample(scale: activatedScale(
                from: .fourColumns,
                to: .large,
                progress: 1
            )),
            coordinator: &coordinator
        )

        XCTAssertEqual(
            committedModes(in: changedEffects),
            [.threeColumns, .twoColumns, .large]
        )
        XCTAssertEqual(hapticCount(in: changedEffects), 3)
        XCTAssertEqual(coordinator.currentMode, .large)
        XCTAssertTrue(coordinator.didCommitGeometry)

        let terminalEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        XCTAssertEqual(persistedModes(in: terminalEffects), [.large])
        XCTAssertEqual(reconciliations(in: terminalEffects), [
            Coordinator.MediaReconciliation(
                finalMode: .large,
                cancelsPrefetchLoads: true
            )
        ])
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
    }

    func testMultiBoundaryPinchCommitsLargeToFourColumns() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .large,
            defaultMode: .threeColumns
        )

        let changedEffects = drainChanged(
            sample(scale: activatedScale(
                from: .large,
                to: .fourColumns,
                progress: 1.05
            )),
            coordinator: &coordinator
        )

        XCTAssertEqual(
            committedModes(in: changedEffects),
            [.twoColumns, .threeColumns, .fourColumns]
        )
        XCTAssertEqual(hapticCount(in: changedEffects), 3)
        XCTAssertEqual(coordinator.currentMode, .fourColumns)

        let terminalEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        XCTAssertEqual(persistedModes(in: terminalEffects), [.fourColumns])
        XCTAssertEqual(reconciliations(in: terminalEffects).map(\.cancelsPrefetchLoads), [true])
    }

    func testExactBoundaryCommitContinuesWithoutInstallingAnotherTransition() throws {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .twoColumns,
            defaultMode: .threeColumns
        )

        let effects = drainChanged(
            sample(scale: activatedScale(
                from: .twoColumns,
                to: .threeColumns,
                progress: 1
            )),
            coordinator: &coordinator
        )

        XCTAssertEqual(committedModes(in: effects), [.threeColumns])
        XCTAssertEqual(
            installedTransitions(in: effects).map(\.toMode),
            [.threeColumns]
        )
        XCTAssertEqual(effects.filter {
            if case .continuePinch = $0 { return true }
            return false
        }.count, 1)
        let commitIndex = try XCTUnwrap(effects.firstIndex {
            if case .commitTransition = $0 { return true }
            return false
        })
        let continuationIndex = try XCTUnwrap(effects.firstIndex {
            if case .continuePinch = $0 { return true }
            return false
        })
        XCTAssertLessThan(commitIndex, continuationIndex)
        XCTAssertEqual(coordinator.currentMode, .threeColumns)
        XCTAssertTrue(coordinator.didCommitGeometry)
        XCTAssertEqual(coordinator.phase, .interacting)
    }

    func testPartialReversalDiscardsTheFirstTransitionAndInstallsTheOppositeOne() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        let outwardTransition = transition(
            from: .threeColumns,
            to: .twoColumns
        )
        _ = coordinator.handle(
            .pinchChanged(sample: sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            ))),
            transitionProvider: transitionProvider(from:to:)
        )

        let effects = handleAndDrive(
            .pinchChanged(sample: sample(scale: 1)),
            coordinator: &coordinator,
            usesTransitionProvider: true
        )

        XCTAssertEqual(discardedTransitionIDs(in: effects), [outwardTransition.id])
        XCTAssertEqual(installedTransitions(in: effects).map(\.toMode), [.fourColumns])
        XCTAssertEqual(coordinator.currentMode, .threeColumns)
        XCTAssertFalse(coordinator.didCommitGeometry)
    }

    func testLargeQualityReversalDiscardsBeforeInstallingThumbnailTarget() throws {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .twoColumns,
            defaultMode: .threeColumns
        )
        let outwardTransition = transition(
            from: .twoColumns,
            to: .large
        )
        _ = coordinator.handle(
            .pinchChanged(sample: sample(scale: activatedScale(
                from: .twoColumns,
                to: .large,
                progress: 0.4
            ))),
            transitionProvider: transitionProvider(from:to:)
        )

        let effects = handleAndDrive(
            .pinchChanged(sample: sample(scale: 1)),
            coordinator: &coordinator,
            usesTransitionProvider: true
        )
        let discardIndex = try XCTUnwrap(effects.firstIndex {
            if case let .discardTransition(id) = $0 {
                return id == outwardTransition.id
            }
            return false
        })
        let continuationIndex = try XCTUnwrap(effects.firstIndex {
            if case .continuePinch = $0 { return true }
            return false
        })
        let oppositeInstallIndex = try XCTUnwrap(effects.firstIndex {
            if case let .installTransition(transition) = $0 {
                return transition.toMode == .threeColumns
            }
            return false
        })

        XCTAssertLessThan(discardIndex, continuationIndex)
        XCTAssertLessThan(continuationIndex, oppositeInstallIndex)
        XCTAssertEqual(discardedTransitionIDs(in: effects), [outwardTransition.id])
        XCTAssertEqual(
            installedTransitions(in: effects).map(\.toMode),
            [.threeColumns]
        )
        XCTAssertEqual(coordinator.currentMode, .twoColumns)
        XCTAssertFalse(coordinator.didCommitGeometry)
    }

    func testPostCommitReversalCanReturnToTheInitialMode() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 1
            )),
            coordinator: &coordinator
        )

        let reversalEffects = drainChanged(
            sample(scale: 1.04),
            coordinator: &coordinator
        )
        XCTAssertEqual(committedModes(in: reversalEffects), [.threeColumns])
        XCTAssertEqual(coordinator.currentMode, .threeColumns)

        let terminalEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        XCTAssertEqual(persistedModes(in: terminalEffects), [])
        XCTAssertEqual(reconciliations(in: terminalEffects), [
            Coordinator.MediaReconciliation(
                finalMode: .threeColumns,
                cancelsPrefetchLoads: false
            )
        ])
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
    }

    func testEndpointPinchUsesDampedOvershootAndResetsAtEnd() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .large,
            defaultMode: .threeColumns
        )

        let changedEffects = coordinator.handle(
            .pinchChanged(sample: sample(scale: 1.4)),
            transitionProvider: transitionProvider(from:to:)
        )
        let overshootScales = changedEffects.compactMap { effect -> CGFloat? in
            guard case let .applyOvershoot(scale) = effect else { return nil }
            return scale
        }
        XCTAssertEqual(changedEffects.first, .beginInteraction)
        XCTAssertEqual(overshootScales.count, 1)
        XCTAssertGreaterThan(overshootScales[0], 1)
        XCTAssertLessThan(
            overshootScales[0],
            1 + PlayerBrowserGridPinchPolicy.overshootMaximumDeviation
        )

        let terminalEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        XCTAssertTrue(terminalEffects.contains(.resetOvershoot(animated: true)))
        XCTAssertEqual(reconciliations(in: terminalEffects), [])
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
    }

    func testMenuTransitionStartsWithDisplayLinkAndTerminatesExactlyOnce() {
        var coordinator = Coordinator()
        let initialEffects = coordinator.handle(
            .menuSelected(
                fromMode: .fourColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )

        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertEqual(initialEffects.first, .beginInteraction)
        XCTAssertEqual(installedTransitions(in: initialEffects).map(\.toMode), [.large])
        XCTAssertEqual(renderedProgresses(in: initialEffects), [0])
        XCTAssertEqual(initialEffects.filter { $0 == .startDisplayLink }.count, 1)

        XCTAssertEqual(
            coordinator.handle(.settleStarted(timestamp: 30)),
            []
        )
        XCTAssertEqual(
            coordinator.handle(.settleStarted(timestamp: 30.1)),
            []
        )

        let midpointEffects = coordinator.handle(.settleTick(timestamp: 30.18))
        XCTAssertEqual(renderedProgresses(in: midpointEffects).count, 1)
        XCTAssertEqual(
            renderedProgresses(in: midpointEffects)[0],
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(finishEffects(in: midpointEffects), [])

        let terminalEffects = handleAndDrive(
            .settleTick(timestamp: 31),
            coordinator: &coordinator
        )
        XCTAssertEqual(terminalEffects.filter { $0 == .stopDisplayLink }.count, 1)
        XCTAssertEqual(committedModes(in: terminalEffects), [.large])
        XCTAssertEqual(persistedModes(in: terminalEffects), [.large])
        XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.handle(.settleTick(timestamp: 12)), [])
        XCTAssertEqual(coordinator.handle(.interrupt), [])
    }

    func testUnchangedPinchAdoptsMenuCommitAtZeroProgress() {
        for advancesToFirstTick in [false, true] {
            var coordinator = Coordinator()
            _ = coordinator.handle(
                .menuSelected(
                    fromMode: .threeColumns,
                    toMode: .large,
                    defaultMode: .threeColumns,
                    reduceMotion: false
                ),
                transitionProvider: transitionProvider(from:to:)
            )
            if advancesToFirstTick {
                XCTAssertEqual(
                    coordinator.handle(.settleStarted(timestamp: 30)),
                    []
                )
                let tickEffects = coordinator.handle(
                    .settleTick(timestamp: 30)
                )
                XCTAssertEqual(renderedProgresses(in: tickEffects), [0])
            }

            XCTAssertEqual(coordinator.handle(.pinchBegan(
                sample: sample(scale: 1),
                currentMode: .threeColumns,
                defaultMode: .threeColumns,
                adoptedTransitionWasReanchored: true
            )), [.stopDisplayLink])
            let unchangedEffects = coordinator.handle(
                .pinchChanged(sample: sample(scale: 1)),
                transitionProvider: transitionProvider(from:to:)
            )
            XCTAssertEqual(renderedProgresses(in: unchangedEffects), [0])
            XCTAssertEqual(discardedTransitionIDs(in: unchangedEffects), [])

            let terminalEffects = handleAndDrive(
                .pinchEnded(
                    velocity: -100,
                    timestamp: 31,
                    reduceMotion: true
                ),
                coordinator: &coordinator
            )
            XCTAssertEqual(committedModes(in: terminalEffects), [.large])
            XCTAssertEqual(persistedModes(in: terminalEffects), [.large])
            XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
            XCTAssertEqual(finishEffects(in: terminalEffects), [true])
            XCTAssertEqual(coordinator.phase, .idle)
        }
    }

    func testAdoptedMenuCommitRetainsFallbackDuringSettleFailure() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))
        _ = coordinator.handle(
            .pinchChanged(sample: sample(scale: 1)),
            transitionProvider: transitionProvider(from:to:)
        )

        let settleEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 20,
            reduceMotion: false
        ))
        XCTAssertTrue(settleEffects.contains(.startDisplayLink))

        let fallbackEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(fallbackEffects.contains(.stopDisplayLink))
        XCTAssertTrue(fallbackEffects.contains(.resetRenderer))
        XCTAssertTrue(fallbackEffects.contains(.applyMode(.large)))
        XCTAssertEqual(finishEffects(in: fallbackEffects), [])

        let terminalEffects = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(persistedModes(in: terminalEffects), [.large])
        XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptedMenuCommitRetainsFallbackOnTerminalFailure() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))
        _ = coordinator.handle(
            .pinchChanged(sample: sample(scale: 1)),
            transitionProvider: transitionProvider(from:to:)
        )

        let commandEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 20,
            reduceMotion: true
        ))
        XCTAssertEqual(committedModes(in: commandEffects), [.large])

        let fallbackEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(fallbackEffects.contains(.resetRenderer))
        XCTAssertTrue(fallbackEffects.contains(.applyMode(.large)))
        XCTAssertEqual(finishEffects(in: fallbackEffects), [])

        let terminalEffects = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(persistedModes(in: terminalEffects), [.large])
        XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptedMenuCommitRetainsFallbackOnRenderFailure() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))
        let renderEffects = coordinator.handle(
            .pinchChanged(sample: sample(scale: 1)),
            transitionProvider: transitionProvider(from:to:)
        )
        XCTAssertEqual(renderedProgresses(in: renderEffects), [0])

        let fallbackEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(fallbackEffects.contains(.resetRenderer))
        XCTAssertTrue(fallbackEffects.contains(.applyMode(.large)))
        XCTAssertEqual(finishEffects(in: fallbackEffects), [])

        let terminalEffects = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(persistedModes(in: terminalEffects), [.large])
        XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptedMenuCommitRetainsFallbackOnBoundaryFailure() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))
        let itemWidthRatio = transition(
            from: .threeColumns,
            to: .large
        ).itemWidthRatio
        let commandEffects = coordinator.handle(
            .pinchChanged(sample: sample(scale: itemWidthRatio + 0.1)),
            transitionProvider: transitionProvider(from:to:)
        )
        XCTAssertEqual(committedModes(in: commandEffects), [.large])

        let fallbackEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(fallbackEffects.contains(.resetRenderer))
        XCTAssertTrue(fallbackEffects.contains(.applyMode(.large)))
        XCTAssertEqual(finishEffects(in: fallbackEffects), [])

        let terminalEffects = coordinator.handle(.rendererSucceeded)
        XCTAssertEqual(persistedModes(in: terminalEffects), [.large])
        XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
        XCTAssertEqual(finishEffects(in: terminalEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptedMenuCancelDoesNotUseCommitFallback() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))
        _ = coordinator.handle(
            .pinchChanged(sample: sample(scale: 1.4)),
            transitionProvider: transitionProvider(from:to:)
        )

        let commandEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 20,
            reduceMotion: true
        ))
        XCTAssertEqual(committedModes(in: commandEffects), [])
        XCTAssertEqual(discardedTransitionIDs(in: commandEffects).count, 1)

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(failureEffects.contains(.resetRenderer))
        XCTAssertFalse(failureEffects.contains(.applyMode(.large)))
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(finishEffects(in: failureEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testReduceMotionMenuTransitionUsesDirectFallback() {
        var coordinator = Coordinator()

        let effects = handleAndDrive(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: true
            ),
            coordinator: &coordinator,
            usesTransitionProvider: true
        )

        XCTAssertTrue(effects.contains(.applyMode(.large)))
        XCTAssertEqual(installedTransitions(in: effects), [])
        XCTAssertEqual(renderedProgresses(in: effects), [])
        XCTAssertEqual(committedModes(in: effects), [])
        XCTAssertFalse(effects.contains(.startDisplayLink))
        XCTAssertEqual(persistedModes(in: effects), [.large])
        XCTAssertEqual(reconciliations(in: effects).count, 1)
        XCTAssertEqual(finishEffects(in: effects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testUnavailableMenuTransitionUsesDirectFallbackAndTerminalReconciliation() {
        var coordinator = Coordinator()

        let effects = handleAndDrive(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .fourColumns,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            coordinator: &coordinator
        )

        XCTAssertEqual(effects.first, .beginInteraction)
        XCTAssertTrue(effects.contains(.applyMode(.fourColumns)))
        XCTAssertEqual(persistedModes(in: effects), [.fourColumns])
        XCTAssertEqual(reconciliations(in: effects), [
            Coordinator.MediaReconciliation(
                finalMode: .fourColumns,
                cancelsPrefetchLoads: false
            )
        ])
        XCTAssertEqual(finishEffects(in: effects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAdoptedCommitSettleKeepsIntentWithoutAdjustment() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        let settleEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        XCTAssertEqual(hapticCount(in: settleEffects), 1)
        XCTAssertTrue(settleEffects.contains(.startDisplayLink))

        let adoptionEffects = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))
        XCTAssertEqual(adoptionEffects, [.stopDisplayLink])
        XCTAssertEqual(coordinator.phase, .interacting)

        let resumedEffects = handleAndDrive(
            .pinchEnded(
                velocity: -100,
                timestamp: 11,
                reduceMotion: true
            ),
            coordinator: &coordinator
        )
        XCTAssertEqual(committedModes(in: resumedEffects), [.twoColumns])
        XCTAssertEqual(hapticCount(in: resumedEffects), 0)
    }

    func testAdoptedCancelSettleKeepsIntentWithoutAdjustment() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        XCTAssertEqual(coordinator.phase, .settling)

        XCTAssertEqual(coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        )), [.stopDisplayLink])
        let terminalEffects = handleAndDrive(
            .pinchEnded(
                velocity: 100,
                timestamp: 11,
                reduceMotion: true
            ),
            coordinator: &coordinator
        )

        XCTAssertEqual(committedModes(in: terminalEffects), [])
        XCTAssertEqual(discardedTransitionIDs(in: terminalEffects).count, 1)
        XCTAssertEqual(hapticCount(in: terminalEffects), 0)
        XCTAssertEqual(persistedModes(in: terminalEffects), [])
        XCTAssertEqual(reconciliations(in: terminalEffects), [])
    }

    func testNormalEndAfterAdjustingAdoptedCancelCanCommit() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))

        let adoptionReferenceScale = CGFloat(1) / effectiveScaleAtProgress(
            from: .threeColumns,
            to: .twoColumns,
            progress: 0.4
        )
        _ = coordinator.handle(
            .pinchChanged(sample: sample(
                scale: adoptionReferenceScale * 1.4
            )),
            transitionProvider: transitionProvider(from:to:)
        )
        let terminalEffects = handleAndDrive(
            .pinchEnded(
                velocity: 0,
                timestamp: 11,
                reduceMotion: true
            ),
            coordinator: &coordinator
        )

        XCTAssertEqual(committedModes(in: terminalEffects), [.twoColumns])
        XCTAssertEqual(hapticCount(in: terminalEffects), 1)
        XCTAssertEqual(persistedModes(in: terminalEffects), [.twoColumns])
        XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
    }

    func testNormalEndAfterAdjustingAdoptedSettleReevaluatesOutcome() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))

        let adoptionReferenceScale = CGFloat(1) / effectiveScaleAtProgress(
            from: .threeColumns,
            to: .twoColumns,
            progress: 0.6
        )
        _ = coordinator.handle(
            .pinchChanged(sample: sample(
                scale: adoptionReferenceScale * 1.1
            )),
            transitionProvider: transitionProvider(from:to:)
        )
        let terminalEffects = handleAndDrive(
            .pinchEnded(
                velocity: 0,
                timestamp: 11,
                reduceMotion: true
            ),
            coordinator: &coordinator
        )

        XCTAssertEqual(committedModes(in: terminalEffects), [])
        XCTAssertEqual(discardedTransitionIDs(in: terminalEffects).count, 1)
        XCTAssertEqual(persistedModes(in: terminalEffects), [])
        XCTAssertEqual(reconciliations(in: terminalEffects), [])
    }

    func testCancellationAfterAdjustingAdoptedSettleKeepsOriginalIntent() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: false
        ))
        let adoptionReferenceScale = CGFloat(1) / effectiveScaleAtProgress(
            from: .threeColumns,
            to: .twoColumns,
            progress: 0.6
        )
        _ = coordinator.handle(
            .pinchChanged(sample: sample(
                scale: adoptionReferenceScale * 1.1
            )),
            transitionProvider: transitionProvider(from:to:)
        )

        let terminalEffects = handleAndDrive(
            .pinchCancelled(
                timestamp: 11,
                reduceMotion: true
            ),
            coordinator: &coordinator
        )

        XCTAssertEqual(committedModes(in: terminalEffects), [.twoColumns])
        XCTAssertEqual(hapticCount(in: terminalEffects), 0)
        XCTAssertEqual(persistedModes(in: terminalEffects), [.twoColumns])
        XCTAssertEqual(reconciliations(in: terminalEffects).count, 1)
    }

    func testReversalClearsAdoptedSettleIntent() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        _ = coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: true
        ))
        let adoptionReferenceScale = CGFloat(1) / effectiveScaleAtProgress(
            from: .threeColumns,
            to: .twoColumns,
            progress: 0.6
        )

        let reversalEffects = handleAndDrive(
            .pinchChanged(sample: sample(scale: adoptionReferenceScale)),
            coordinator: &coordinator,
            usesTransitionProvider: true
        )
        XCTAssertEqual(discardedTransitionIDs(in: reversalEffects).count, 1)

        let terminalEffects = coordinator.handle(.interrupt)
        XCTAssertEqual(committedModes(in: terminalEffects), [])
        XCTAssertEqual(persistedModes(in: terminalEffects), [])
        XCTAssertEqual(reconciliations(in: terminalEffects), [])
        XCTAssertEqual(finishEffects(in: terminalEffects), [false])
    }

    func testCancellationAfterNoCommitDiscardsWithoutMediaWork() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            )),
            coordinator: &coordinator
        )

        let effects = handleAndDrive(
            .pinchCancelled(
                timestamp: 10,
                reduceMotion: true
            ),
            coordinator: &coordinator
        )

        XCTAssertEqual(discardedTransitionIDs(in: effects).count, 1)
        XCTAssertEqual(persistedModes(in: effects), [])
        XCTAssertEqual(reconciliations(in: effects), [])
        XCTAssertEqual(finishEffects(in: effects), [true])
    }

    func testCancellationAfterSeveralCommittedBoundariesReconcilesOnlyOnce() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .fourColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .fourColumns,
                to: .large,
                progress: 0.5
            )),
            coordinator: &coordinator
        )
        XCTAssertEqual(coordinator.currentMode, .twoColumns)

        let effects = handleAndDrive(
            .pinchCancelled(
                timestamp: 10,
                reduceMotion: true
            ),
            coordinator: &coordinator
        )

        XCTAssertEqual(persistedModes(in: effects), [.twoColumns])
        XCTAssertEqual(reconciliations(in: effects), [
            Coordinator.MediaReconciliation(
                finalMode: .twoColumns,
                cancelsPrefetchLoads: true
            )
        ])
        XCTAssertEqual(finishEffects(in: effects), [true])
        XCTAssertEqual(coordinator.handle(.rendererFailed), [])
    }

    func testInterruptDuringTrackingHasNoUIKitLifecycleEffects() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )

        XCTAssertEqual(coordinator.phase, .tracking)
        XCTAssertEqual(coordinator.handle(.interrupt), [])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptDuringActivePinchCancelsRegardlessOfProgress() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.9
            )),
            coordinator: &coordinator
        )

        let effects = handleAndDrive(
            .interrupt,
            coordinator: &coordinator
        )

        XCTAssertEqual(renderedProgresses(in: effects), [0])
        XCTAssertEqual(committedModes(in: effects), [])
        XCTAssertEqual(discardedTransitionIDs(in: effects).count, 1)
        XCTAssertEqual(finishEffects(in: effects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptDuringSettlePreservesCommitOutcomeAndStopsDisplayLink() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))

        let effects = handleAndDrive(
            .interrupt,
            coordinator: &coordinator
        )

        XCTAssertEqual(effects.filter { $0 == .stopDisplayLink }.count, 1)
        XCTAssertEqual(renderedProgresses(in: effects), [1])
        XCTAssertEqual(committedModes(in: effects), [.twoColumns])
        XCTAssertEqual(persistedModes(in: effects), [.twoColumns])
        XCTAssertEqual(reconciliations(in: effects).count, 1)
        XCTAssertEqual(finishEffects(in: effects), [false])
    }

    func testInterruptDuringCancelSettlePreservesCancelOutcome() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))

        let effects = handleAndDrive(
            .interrupt,
            coordinator: &coordinator
        )

        XCTAssertEqual(effects.filter { $0 == .stopDisplayLink }.count, 1)
        XCTAssertEqual(renderedProgresses(in: effects), [0])
        XCTAssertEqual(committedModes(in: effects), [])
        XCTAssertEqual(discardedTransitionIDs(in: effects).count, 1)
        XCTAssertEqual(persistedModes(in: effects), [])
        XCTAssertEqual(reconciliations(in: effects), [])
        XCTAssertEqual(finishEffects(in: effects), [false])
    }

    func testInterruptedBoundaryCommitFailureRollsBackAndDoesNotSettlePosition() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .fourColumns,
            defaultMode: .threeColumns
        )

        let commandEffects = coordinator.handle(
            .pinchChanged(sample: sample(scale: activatedScale(
                from: .fourColumns,
                to: .threeColumns,
                progress: 1.1
            ))),
            transitionProvider: transitionProvider(from:to:)
        )

        XCTAssertEqual(committedModes(in: commandEffects), [.threeColumns])
        XCTAssertEqual(hapticCount(in: commandEffects), 0)
        XCTAssertFalse(commandEffects.contains(where: {
            if case .continuePinch = $0 { return true }
            return false
        }))
        XCTAssertEqual(persistedModes(in: commandEffects), [])
        XCTAssertEqual(reconciliations(in: commandEffects), [])
        XCTAssertEqual(finishEffects(in: commandEffects), [])
        XCTAssertEqual(coordinator.currentMode, .fourColumns)
        XCTAssertFalse(coordinator.didCommitGeometry)
        XCTAssertEqual(coordinator.handle(.interrupt), [])
        XCTAssertEqual(coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: true
        )), [])

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertEqual(failureEffects.first, .resetRenderer)
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(hapticCount(in: failureEffects), 0)
        XCTAssertEqual(finishEffects(in: failureEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.handle(.rendererSucceeded), [])
        XCTAssertEqual(coordinator.handle(.rendererFailed), [])
    }

    func testInterruptedBoundaryCommitSuccessTerminatesWithoutContinuingPinch() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .fourColumns,
            defaultMode: .threeColumns
        )
        let commandEffects = coordinator.handle(
            .pinchChanged(sample: sample(scale: activatedScale(
                from: .fourColumns,
                to: .threeColumns,
                progress: 1.1
            ))),
            transitionProvider: transitionProvider(from:to:)
        )

        XCTAssertEqual(committedModes(in: commandEffects), [.threeColumns])
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let successEffects = coordinator.handle(.rendererSucceeded)

        XCTAssertFalse(successEffects.contains(where: {
            if case .continuePinch = $0 { return true }
            return false
        }))
        XCTAssertTrue(successEffects.contains(.resetOvershoot(animated: false)))
        XCTAssertEqual(hapticCount(in: successEffects), 1)
        XCTAssertEqual(persistedModes(in: successEffects), [.threeColumns])
        XCTAssertEqual(reconciliations(in: successEffects).count, 1)
        XCTAssertEqual(finishEffects(in: successEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptedReversalDiscardSuccessTerminatesWithoutContinuingPinch() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            )),
            coordinator: &coordinator
        )
        let commandEffects = coordinator.handle(
            .pinchChanged(sample: sample(scale: 1.03)),
            transitionProvider: transitionProvider(from:to:)
        )

        XCTAssertEqual(discardedTransitionIDs(in: commandEffects).count, 1)
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let successEffects = coordinator.handle(.rendererSucceeded)

        XCTAssertFalse(successEffects.contains(where: {
            if case .continuePinch = $0 { return true }
            return false
        }))
        XCTAssertTrue(successEffects.contains(.resetOvershoot(animated: false)))
        XCTAssertEqual(persistedModes(in: successEffects), [])
        XCTAssertEqual(reconciliations(in: successEffects), [])
        XCTAssertEqual(finishEffects(in: successEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptedReversalDiscardFailureTerminatesWithoutSettlingPosition() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            )),
            coordinator: &coordinator
        )
        let commandEffects = coordinator.handle(
            .pinchChanged(sample: sample(scale: 1.03)),
            transitionProvider: transitionProvider(from:to:)
        )

        XCTAssertEqual(discardedTransitionIDs(in: commandEffects).count, 1)
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(failureEffects.contains(.resetRenderer))
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(finishEffects(in: failureEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testTerminalSettleFailureStopsDisplayLinkAndDoesNotCommit() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        let settleEffects = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        XCTAssertTrue(settleEffects.contains(.startDisplayLink))

        let commandEffects = coordinator.handle(.settleTick(timestamp: 11))
        XCTAssertEqual(committedModes(in: commandEffects), [.twoColumns])
        XCTAssertFalse(commandEffects.contains(.stopDisplayLink))
        XCTAssertEqual(hapticCount(in: commandEffects), 0)
        XCTAssertEqual(finishEffects(in: commandEffects), [])
        XCTAssertEqual(coordinator.currentMode, .threeColumns)
        XCTAssertFalse(coordinator.didCommitGeometry)

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertEqual(failureEffects.filter { $0 == .stopDisplayLink }.count, 1)
        XCTAssertEqual(failureEffects.filter { $0 == .resetRenderer }.count, 1)
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(hapticCount(in: failureEffects), 0)
        XCTAssertEqual(finishEffects(in: failureEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptedPendingTerminalSuccessUsesInterruptionSemantics() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        let commandEffects = coordinator.handle(.settleTick(timestamp: 11))

        XCTAssertEqual(committedModes(in: commandEffects), [.twoColumns])
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let successEffects = coordinator.handle(.rendererSucceeded)

        XCTAssertEqual(successEffects.filter { $0 == .stopDisplayLink }.count, 1)
        XCTAssertTrue(successEffects.contains(.resetOvershoot(animated: false)))
        XCTAssertEqual(persistedModes(in: successEffects), [.twoColumns])
        XCTAssertEqual(reconciliations(in: successEffects).count, 1)
        XCTAssertEqual(finishEffects(in: successEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptedPendingTerminalFailureUsesInterruptionSemantics() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.6
            )),
            coordinator: &coordinator
        )
        _ = coordinator.handle(.pinchEnded(
            velocity: 0,
            timestamp: 10,
            reduceMotion: false
        ))
        let commandEffects = coordinator.handle(.settleTick(timestamp: 11))

        XCTAssertEqual(committedModes(in: commandEffects), [.twoColumns])
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertEqual(failureEffects.filter { $0 == .stopDisplayLink }.count, 1)
        XCTAssertTrue(failureEffects.contains(.resetRenderer))
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(finishEffects(in: failureEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testTerminalInterruptFailureFinishesWithoutAcknowledgingCommand() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.9
            )),
            coordinator: &coordinator
        )

        let commandEffects = coordinator.handle(.interrupt)
        XCTAssertEqual(discardedTransitionIDs(in: commandEffects).count, 1)
        XCTAssertEqual(finishEffects(in: commandEffects), [])
        XCTAssertEqual(coordinator.phase, .interacting)

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(failureEffects.contains(.resetRenderer))
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(finishEffects(in: failureEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptedDirectApplyFailureFinishesWithoutSettlingPosition() {
        var coordinator = Coordinator()
        let commandEffects = coordinator.handle(.menuSelected(
            fromMode: .threeColumns,
            toMode: .large,
            defaultMode: .threeColumns,
            reduceMotion: true
        ))

        XCTAssertEqual(commandEffects, [
            .beginInteraction,
            .applyMode(.large)
        ])
        XCTAssertEqual(coordinator.phase, .settling)
        XCTAssertEqual(coordinator.currentMode, .threeColumns)
        XCTAssertFalse(coordinator.didCommitGeometry)
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertEqual(failureEffects.first, .resetRenderer)
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(finishEffects(in: failureEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.handle(.rendererFailed), [])
        XCTAssertEqual(coordinator.handle(.rendererSucceeded), [])
    }

    func testAnimatedMenuFallbackApplyFailureDoesNotPersistTargetMode() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )

        let fallbackEffects = coordinator.handle(.rendererFailed)
        XCTAssertTrue(fallbackEffects.contains(.stopDisplayLink))
        XCTAssertTrue(fallbackEffects.contains(.resetRenderer))
        XCTAssertTrue(fallbackEffects.contains(.applyMode(.large)))
        XCTAssertEqual(finishEffects(in: fallbackEffects), [])
        XCTAssertEqual(coordinator.currentMode, .threeColumns)

        let failureEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(failureEffects.contains(.resetRenderer))
        XCTAssertEqual(persistedModes(in: failureEffects), [])
        XCTAssertEqual(reconciliations(in: failureEffects), [])
        XCTAssertEqual(finishEffects(in: failureEffects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPendingInterruptSurvivesAnimatedMenuFallbackRetry() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )
        _ = coordinator.handle(.settleStarted(timestamp: 20))
        let commandEffects = coordinator.handle(.settleTick(timestamp: 21))

        XCTAssertEqual(committedModes(in: commandEffects), [.large])
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let fallbackEffects = coordinator.handle(.rendererFailed)

        XCTAssertTrue(fallbackEffects.contains(.stopDisplayLink))
        XCTAssertTrue(fallbackEffects.contains(.resetRenderer))
        XCTAssertTrue(fallbackEffects.contains(.applyMode(.large)))
        XCTAssertEqual(finishEffects(in: fallbackEffects), [])

        let successEffects = coordinator.handle(.rendererSucceeded)

        XCTAssertEqual(persistedModes(in: successEffects), [.large])
        XCTAssertEqual(reconciliations(in: successEffects).count, 1)
        XCTAssertEqual(finishEffects(in: successEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testInterruptedDirectApplySuccessAppliesTerminalEffectsOnce() {
        var coordinator = Coordinator()
        _ = coordinator.handle(.menuSelected(
            fromMode: .threeColumns,
            toMode: .fourColumns,
            defaultMode: .threeColumns,
            reduceMotion: true
        ))
        XCTAssertEqual(coordinator.handle(.interrupt), [])

        let successEffects = coordinator.handle(.rendererSucceeded)

        XCTAssertEqual(persistedModes(in: successEffects), [.fourColumns])
        XCTAssertEqual(reconciliations(in: successEffects).count, 1)
        XCTAssertEqual(finishEffects(in: successEffects), [false])
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.handle(.rendererSucceeded), [])
        XCTAssertEqual(coordinator.handle(.rendererFailed), [])
    }

    func testRendererFailureCleansUpActivePinchIdempotently() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        _ = drainChanged(
            sample(scale: activatedScale(
                from: .threeColumns,
                to: .twoColumns,
                progress: 0.4
            )),
            coordinator: &coordinator
        )

        let effects = driveEffects(
            coordinator.handle(.rendererFailed),
            coordinator: &coordinator
        )

        XCTAssertEqual(discardedTransitionIDs(in: effects).count, 0)
        XCTAssertTrue(effects.contains(.resetRenderer))
        XCTAssertEqual(finishEffects(in: effects), [true])
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.handle(.rendererFailed), [])
        XCTAssertEqual(coordinator.handle(.interrupt), [])
    }

    func testRendererFailureDuringMenuSettleUsesDirectFallback() {
        var coordinator = Coordinator()
        _ = coordinator.handle(
            .menuSelected(
                fromMode: .threeColumns,
                toMode: .large,
                defaultMode: .threeColumns,
                reduceMotion: false
            ),
            transitionProvider: transitionProvider(from:to:)
        )

        let effects = driveEffects(
            coordinator.handle(.rendererFailed),
            coordinator: &coordinator
        )

        XCTAssertTrue(effects.contains(.stopDisplayLink))
        XCTAssertTrue(effects.contains(.resetRenderer))
        XCTAssertEqual(discardedTransitionIDs(in: effects).count, 0)
        XCTAssertTrue(effects.contains(.applyMode(.large)))
        XCTAssertEqual(persistedModes(in: effects), [.large])
        XCTAssertEqual(reconciliations(in: effects).count, 1)
        XCTAssertEqual(finishEffects(in: effects), [true])
        XCTAssertEqual(coordinator.handle(.rendererFailed), [])
    }

    func testMediaReconciliationUsesBothSupportedDefaultModeQualityBoundaries() {
        let cases: [(Mode, Mode, Mode, Bool)] = [
            (.threeColumns, .fourColumns, .threeColumns, false),
            (.threeColumns, .twoColumns, .threeColumns, true),
            (.twoColumns, .fourColumns, .twoColumns, false),
            (.twoColumns, .large, .twoColumns, true)
        ]

        for (fromMode, toMode, defaultMode, cancelsPrefetchLoads) in cases {
            var coordinator = Coordinator()
            let effects = handleAndDrive(
                .menuSelected(
                    fromMode: fromMode,
                    toMode: toMode,
                    defaultMode: defaultMode,
                    reduceMotion: true
                ),
                coordinator: &coordinator,
                usesTransitionProvider: true
            )

            XCTAssertEqual(reconciliations(in: effects), [
                Coordinator.MediaReconciliation(
                    finalMode: toMode,
                    cancelsPrefetchLoads: cancelsPrefetchLoads
                )
            ])
        }
    }

    func testPanDeltaIsRenderedFromTheActivationCentroid() {
        var coordinator = Coordinator()
        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns,
            centroidY: 100
        )
        let scale = activatedScale(
            from: .threeColumns,
            to: .twoColumns,
            progress: 0.2
        )
        _ = coordinator.handle(
            .pinchChanged(sample: sample(scale: scale, centroidY: 100)),
            transitionProvider: transitionProvider(from:to:)
        )

        let effects = coordinator.handle(
            .pinchChanged(sample: sample(scale: scale, centroidY: 140)),
            transitionProvider: transitionProvider(from:to:)
        )
        let panDeltas = effects.compactMap { effect -> CGFloat? in
            guard case let .renderTransition(_, _, panDeltaY) = effect else {
                return nil
            }
            return panDeltaY
        }

        XCTAssertEqual(panDeltas, [40])
    }

    func testInvalidSamplesAndDuplicateBeginsDoNotCorruptState() {
        var coordinator = Coordinator()
        XCTAssertEqual(coordinator.handle(.pinchBegan(
            sample: sample(scale: 0),
            currentMode: .threeColumns,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: false
        )), [])
        XCTAssertEqual(coordinator.phase, .idle)

        beginPinch(
            &coordinator,
            mode: .threeColumns,
            defaultMode: .threeColumns
        )
        XCTAssertEqual(coordinator.handle(.pinchBegan(
            sample: sample(scale: 1),
            currentMode: .large,
            defaultMode: .threeColumns,
            adoptedTransitionWasReanchored: false
        )), [])
        XCTAssertEqual(coordinator.currentMode, .threeColumns)
        XCTAssertEqual(coordinator.handle(
            .pinchChanged(sample: sample(scale: .nan)),
            transitionProvider: transitionProvider(from:to:)
        ), [])
        XCTAssertEqual(coordinator.phase, .tracking)
    }
}
