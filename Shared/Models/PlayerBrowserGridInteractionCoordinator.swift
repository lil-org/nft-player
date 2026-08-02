// ∅ 2026 lil org

import CoreGraphics
import Foundation

struct PlayerBrowserGridInteractionCoordinator {

    enum Phase: Equatable {
        case idle
        case tracking
        case interacting
        case settling
    }

    struct PinchSample: Equatable {
        let scale: CGFloat
        let centroidY: CGFloat
    }

    struct Transition: Equatable {
        let id: UUID
        let fromMode: MobileCollectionBrowserGridMode
        let toMode: MobileCollectionBrowserGridMode
        let itemWidthRatio: CGFloat

        init?(
            id: UUID = UUID(),
            fromMode: MobileCollectionBrowserGridMode,
            toMode: MobileCollectionBrowserGridMode,
            itemWidthRatio: CGFloat
        ) {
            guard fromMode != toMode,
                  itemWidthRatio.isFinite,
                  itemWidthRatio > 0,
                  itemWidthRatio != 1,
                  (itemWidthRatio > 1)
                    == (toMode.columnCount < fromMode.columnCount) else {
                return nil
            }
            self.id = id
            self.fromMode = fromMode
            self.toMode = toMode
            self.itemWidthRatio = itemWidthRatio
        }

        func matches(
            fromMode: MobileCollectionBrowserGridMode,
            toMode: MobileCollectionBrowserGridMode
        ) -> Bool {
            self.fromMode == fromMode && self.toMode == toMode
        }
    }

    enum SettleOutcome: Equatable {
        case commit
        case cancel

        var targetProgress: CGFloat {
            self == .commit ? 1 : 0
        }
    }

    enum AnimationCurve: Equatable {
        case easeOutCubic
        case easeInOutCubic

        func value(at fraction: CGFloat) -> CGFloat {
            let clamped = min(max(fraction, 0), 1)
            switch self {
            case .easeOutCubic:
                let inverse = 1 - clamped
                return 1 - inverse * inverse * inverse
            case .easeInOutCubic:
                if clamped < 0.5 {
                    return 4 * clamped * clamped * clamped
                }
                let inverse = 2 - 2 * clamped
                return 1 - inverse * inverse * inverse / 2
            }
        }
    }

    struct MediaReconciliation: Equatable {
        let finalMode: MobileCollectionBrowserGridMode
        let cancelsPrefetchLoads: Bool
    }

    enum Event: Equatable {
        case menuSelected(
            fromMode: MobileCollectionBrowserGridMode,
            toMode: MobileCollectionBrowserGridMode,
            defaultMode: MobileCollectionBrowserGridMode,
            reduceMotion: Bool
        )
        case pinchBegan(
            sample: PinchSample,
            currentMode: MobileCollectionBrowserGridMode,
            defaultMode: MobileCollectionBrowserGridMode,
            adoptedTransitionWasReanchored: Bool
        )
        case pinchChanged(sample: PinchSample)
        case pinchEnded(
            velocity: CGFloat,
            timestamp: TimeInterval,
            reduceMotion: Bool
        )
        case pinchCancelled(
            timestamp: TimeInterval,
            reduceMotion: Bool
        )
        case settleStarted(timestamp: TimeInterval)
        case settleTick(timestamp: TimeInterval)
        case rendererSucceeded
        case interrupt
        case rendererFailed
    }

    enum Effect: Equatable {
        case beginInteraction
        case installTransition(Transition)
        case renderTransition(id: UUID, progress: CGFloat, panDeltaY: CGFloat)
        case commitTransition(id: UUID, mode: MobileCollectionBrowserGridMode)
        case discardTransition(id: UUID)
        case applyMode(MobileCollectionBrowserGridMode)
        case applyOvershoot(scale: CGFloat)
        case resetOvershoot(animated: Bool)
        case selectionHaptic
        case startDisplayLink
        case stopDisplayLink
        case persistMode(MobileCollectionBrowserGridMode)
        case reconcileMedia(MediaReconciliation)
        case finishInteraction(settlesPosition: Bool)
        case continuePinch(PinchSample)
        case resetRenderer
    }

    typealias TransitionProvider = (
        MobileCollectionBrowserGridMode,
        MobileCollectionBrowserGridMode
    ) -> Transition?

    private struct Session: Equatable {
        let initialMode: MobileCollectionBrowserGridMode
        var currentMode: MobileCollectionBrowserGridMode
        let defaultMode: MobileCollectionBrowserGridMode
        var didCommitGeometry: Bool
    }

    private struct TrackingState: Equatable {
        var session: Session
        let referenceScale: CGFloat
        let referenceCentroidY: CGFloat
    }

    private struct AdoptedSettleIntent: Equatable {
        let outcome: SettleOutcome
        let progressAtAdoption: CGFloat
        let usesMenuFallback: Bool
        var hasAdjustedProgress: Bool
    }

    private struct InteractionState: Equatable {
        var session: Session
        var referenceScale: CGFloat
        var referenceCentroidY: CGFloat
        var basePanDeltaY: CGFloat
        var panDeltaY: CGFloat
        var transition: Transition?
        var progress: CGFloat
        var adoptedSettleIntent: AdoptedSettleIntent?
    }

    private struct SettleState: Equatable {
        var session: Session
        let transition: Transition
        let panDeltaY: CGFloat
        let fromProgress: CGFloat
        var currentProgress: CGFloat
        let outcome: SettleOutcome
        var startTime: TimeInterval?
        let duration: TimeInterval
        let curve: AnimationCurve
        let usesMenuFallback: Bool
    }

    private enum PendingRendererAction: Equatable {
        case boundaryCommit(
            sample: PinchSample,
            transition: Transition,
            emitsHaptic: Bool
        )
        case reversalDiscard(
            sample: PinchSample,
            transition: Transition
        )
        case terminalTransition(
            session: Session,
            transition: Transition,
            outcome: SettleOutcome,
            settlesPosition: Bool,
            resetsOvershoot: Bool,
            usesMenuFallback: Bool,
            stopsDisplayLink: Bool
        )
        case directMode(
            session: Session,
            mode: MobileCollectionBrowserGridMode,
            settlesPosition: Bool
        )
    }

    private enum State: Equatable {
        case idle
        case tracking(TrackingState)
        case interacting(InteractionState)
        case settling(SettleState)
        case applying(Session)

        var session: Session? {
            switch self {
            case .idle:
                return nil
            case let .tracking(tracking):
                return tracking.session
            case let .interacting(interaction):
                return interaction.session
            case let .settling(settle):
                return settle.session
            case let .applying(session):
                return session
            }
        }
    }

    private static let menuTransitionDuration: TimeInterval = 0.36
    private static let adjustmentDeadZone: CGFloat = 0.001

    private var state = State.idle
    private var pendingRendererAction: PendingRendererAction?
    private var hasPendingInterrupt = false

    var phase: Phase {
        switch state {
        case .idle:
            return .idle
        case .tracking:
            return .tracking
        case .interacting:
            return .interacting
        case .settling:
            return .settling
        case .applying:
            return .settling
        }
    }

    var currentMode: MobileCollectionBrowserGridMode? {
        state.session?.currentMode
    }

    var didCommitGeometry: Bool {
        state.session?.didCommitGeometry ?? false
    }

    mutating func handle(
        _ event: Event,
        transitionProvider: TransitionProvider = { _, _ in nil }
    ) -> [Effect] {
        if pendingRendererAction != nil {
            switch event {
            case .rendererSucceeded:
                let wasInterrupted = hasPendingInterrupt
                hasPendingInterrupt = false
                return handleRendererSuccess(
                    wasInterrupted: wasInterrupted
                )
            case .rendererFailed:
                return handleRendererFailure(
                    wasInterrupted: hasPendingInterrupt
                )
            case .interrupt:
                hasPendingInterrupt = true
                return []
            default:
                return []
            }
        }

        switch event {
        case let .menuSelected(
            fromMode,
            toMode,
            defaultMode,
            reduceMotion
        ):
            return handleMenuSelection(
                fromMode: fromMode,
                toMode: toMode,
                defaultMode: defaultMode,
                reduceMotion: reduceMotion,
                transitionProvider: transitionProvider
            )

        case let .pinchBegan(
            sample,
            currentMode,
            defaultMode,
            adoptedTransitionWasReanchored
        ):
            return handlePinchBegan(
                sample: sample,
                currentMode: currentMode,
                defaultMode: defaultMode,
                adoptedTransitionWasReanchored:
                    adoptedTransitionWasReanchored
            )

        case let .pinchChanged(sample):
            return handlePinchChanged(
                sample,
                transitionProvider: transitionProvider
            )

        case let .pinchEnded(velocity, timestamp, reduceMotion):
            return handlePinchEnded(
                velocity: velocity,
                timestamp: timestamp,
                reduceMotion: reduceMotion
            )

        case let .pinchCancelled(timestamp, reduceMotion):
            return handlePinchCancelled(
                timestamp: timestamp,
                reduceMotion: reduceMotion
            )

        case let .settleStarted(timestamp):
            return handleSettleStarted(timestamp: timestamp)

        case let .settleTick(timestamp):
            return handleSettleTick(timestamp: timestamp)

        case .rendererSucceeded:
            return []

        case .interrupt:
            return handleInterrupt()

        case .rendererFailed:
            return handleRendererFailure(wasInterrupted: false)
        }
    }

    private mutating func handleMenuSelection(
        fromMode: MobileCollectionBrowserGridMode,
        toMode: MobileCollectionBrowserGridMode,
        defaultMode: MobileCollectionBrowserGridMode,
        reduceMotion: Bool,
        transitionProvider: TransitionProvider
    ) -> [Effect] {
        guard case .idle = state,
              fromMode != toMode else {
            return []
        }

        let session = Session(
            initialMode: fromMode,
            currentMode: fromMode,
            defaultMode: defaultMode,
            didCommitGeometry: false
        )
        guard !reduceMotion,
              let transition = transitionProvider(fromMode, toMode),
              transition.matches(fromMode: fromMode, toMode: toMode) else {
            state = .applying(session)
            pendingRendererAction = .directMode(
                session: session,
                mode: toMode,
                settlesPosition: true
            )
            return [.beginInteraction, .applyMode(toMode)]
        }

        let effects: [Effect] = [
            .beginInteraction,
            .installTransition(transition),
            .renderTransition(
                id: transition.id,
                progress: 0,
                panDeltaY: 0
            )
        ]
        state = .settling(SettleState(
            session: session,
            transition: transition,
            panDeltaY: 0,
            fromProgress: 0,
            currentProgress: 0,
            outcome: .commit,
            startTime: nil,
            duration: Self.menuTransitionDuration,
            curve: .easeInOutCubic,
            usesMenuFallback: true
        ))
        return effects + [.startDisplayLink]
    }

    private mutating func handlePinchBegan(
        sample: PinchSample,
        currentMode: MobileCollectionBrowserGridMode,
        defaultMode: MobileCollectionBrowserGridMode,
        adoptedTransitionWasReanchored: Bool
    ) -> [Effect] {
        guard isValid(sample: sample) else { return [] }

        switch state {
        case .idle:
            state = .tracking(TrackingState(
                session: Session(
                    initialMode: currentMode,
                    currentMode: currentMode,
                    defaultMode: defaultMode,
                    didCommitGeometry: false
                ),
                referenceScale: sample.scale,
                referenceCentroidY: sample.centroidY
            ))
            return []

        case let .settling(settle):
            let effectiveScale = 1
                + (settle.transition.itemWidthRatio - 1)
                    * settle.currentProgress
            let referenceScale = sample.scale / effectiveScale
            guard effectiveScale.isFinite,
                  effectiveScale > 0,
                  referenceScale.isFinite,
                  referenceScale > 0 else {
                return []
            }
            state = .interacting(InteractionState(
                session: settle.session,
                referenceScale: referenceScale,
                referenceCentroidY: sample.centroidY,
                basePanDeltaY: adoptedTransitionWasReanchored
                    ? 0
                    : settle.panDeltaY,
                panDeltaY: adoptedTransitionWasReanchored
                    ? 0
                    : settle.panDeltaY,
                transition: settle.transition,
                progress: settle.currentProgress,
                adoptedSettleIntent: AdoptedSettleIntent(
                    outcome: settle.outcome,
                    progressAtAdoption: settle.currentProgress,
                    usesMenuFallback: settle.usesMenuFallback,
                    hasAdjustedProgress: false
                )
            ))
            return [.stopDisplayLink]

        case .tracking, .interacting, .applying:
            return []
        }
    }

    private mutating func handlePinchChanged(
        _ sample: PinchSample,
        transitionProvider: TransitionProvider
    ) -> [Effect] {
        guard isValid(sample: sample) else { return [] }

        switch state {
        case let .tracking(tracking):
            let rawEffectiveScale = sample.scale / tracking.referenceScale
            guard rawEffectiveScale.isFinite,
                  rawEffectiveScale > 0,
                  abs(rawEffectiveScale - 1)
                    > PlayerBrowserGridPinchPolicy.activationScaleDeviation else {
                return []
            }
            let effectiveScale = PlayerBrowserGridPinchPolicy
                .effectiveScaleAfterActivation(rawEffectiveScale)
            var interaction = InteractionState(
                session: tracking.session,
                referenceScale: sample.scale / effectiveScale,
                referenceCentroidY: sample.centroidY,
                basePanDeltaY: 0,
                panDeltaY: 0,
                transition: nil,
                progress: 0,
                adoptedSettleIntent: nil
            )
            var effects = [Effect.beginInteraction]
            effects += processPinchChanged(
                sample,
                interaction: &interaction,
                transitionProvider: transitionProvider
            )
            state = .interacting(interaction)
            return effects

        case var .interacting(interaction):
            let effects = processPinchChanged(
                sample,
                interaction: &interaction,
                transitionProvider: transitionProvider
            )
            state = .interacting(interaction)
            return effects

        case .idle, .settling, .applying:
            return []
        }
    }

    private mutating func processPinchChanged(
        _ sample: PinchSample,
        interaction: inout InteractionState,
        transitionProvider: TransitionProvider
    ) -> [Effect] {
        let effectiveScale = sample.scale / interaction.referenceScale
        guard effectiveScale.isFinite, effectiveScale > 0 else { return [] }

        interaction.panDeltaY = interaction.basePanDeltaY
            + sample.centroidY
            - interaction.referenceCentroidY
        var effects = [Effect]()

        if let transition = interaction.transition {
            let progress = PlayerBrowserGridPinchPolicy.progress(
                effectiveScale: effectiveScale,
                itemWidthRatio: transition.itemWidthRatio
            )
            if var intent = interaction.adoptedSettleIntent,
               !intent.hasAdjustedProgress,
               abs(progress - intent.progressAtAdoption)
                    > Self.adjustmentDeadZone {
                intent.hasAdjustedProgress = true
                interaction.adoptedSettleIntent = intent
            }
            if let intent = interaction.adoptedSettleIntent,
               !intent.hasAdjustedProgress {
                interaction.progress = min(max(progress, 0), 1)
                effects.append(.renderTransition(
                    id: transition.id,
                    progress: interaction.progress,
                    panDeltaY: interaction.panDeltaY
                ))
                return effects
            }
            if progress >= 1 {
                let emitsHaptic = interaction.adoptedSettleIntent.map {
                    $0.outcome != .commit
                } ?? true
                return effects + boundaryCommitEffects(
                    sample: sample,
                    transition: transition,
                    panDeltaY: interaction.panDeltaY,
                    emitsHaptic: emitsHaptic
                )
            }
            if progress > 0 {
                interaction.progress = progress
                effects.append(.renderTransition(
                    id: transition.id,
                    progress: progress,
                    panDeltaY: interaction.panDeltaY
                ))
                return effects
            }

            interaction.progress = 0
            effects.append(.renderTransition(
                id: transition.id,
                progress: 0,
                panDeltaY: interaction.panDeltaY
            ))
            effects.append(.discardTransition(id: transition.id))
            pendingRendererAction = .reversalDiscard(
                sample: sample,
                transition: transition
            )
            return effects
        }

        guard abs(effectiveScale - 1) > Self.adjustmentDeadZone else {
            interaction.panDeltaY = 0
            effects.append(.resetOvershoot(animated: false))
            return effects
        }

        let targetMode = effectiveScale > 1
            ? interaction.session.currentMode.modeWithLargerItems
            : interaction.session.currentMode.modeWithSmallerItems
        guard let targetMode else {
            effects.append(.applyOvershoot(
                scale: PlayerBrowserGridPinchPolicy.overshootScale(
                    forEffectiveScale: effectiveScale
                )
            ))
            return effects
        }

        interaction.referenceCentroidY = sample.centroidY
        interaction.basePanDeltaY = 0
        interaction.panDeltaY = 0
        effects.append(.resetOvershoot(animated: false))
        let currentMode = interaction.session.currentMode
        guard let transition = transitionProvider(currentMode, targetMode),
              transition.matches(
                  fromMode: currentMode,
                  toMode: targetMode
              ) else {
            return effects
        }

        interaction.transition = transition
        effects.append(.installTransition(transition))
        let progress = PlayerBrowserGridPinchPolicy.progress(
            effectiveScale: effectiveScale,
            itemWidthRatio: transition.itemWidthRatio
        )
        if progress >= 1 {
            return effects + boundaryCommitEffects(
                sample: sample,
                transition: transition,
                panDeltaY: 0,
                emitsHaptic: true
            )
        }

        interaction.progress = max(progress, 0)
        effects.append(.renderTransition(
            id: transition.id,
            progress: interaction.progress,
            panDeltaY: 0
        ))
        return effects
    }

    private mutating func boundaryCommitEffects(
        sample: PinchSample,
        transition: Transition,
        panDeltaY: CGFloat,
        emitsHaptic: Bool
    ) -> [Effect] {
        pendingRendererAction = .boundaryCommit(
            sample: sample,
            transition: transition,
            emitsHaptic: emitsHaptic
        )
        return [
            .renderTransition(
                id: transition.id,
                progress: 1,
                panDeltaY: panDeltaY
            ),
            .commitTransition(
                id: transition.id,
                mode: transition.toMode
            )
        ]
    }

    private mutating func handlePinchEnded(
        velocity: CGFloat,
        timestamp: TimeInterval,
        reduceMotion: Bool
    ) -> [Effect] {
        switch state {
        case .idle, .applying:
            return []

        case .tracking:
            state = .idle
            return []

        case let .settling(settle):
            return settleSynchronously(
                settle,
                settlesPosition: true
            )

        case let .interacting(interaction):
            guard let transition = interaction.transition else {
                state = .idle
                return [.resetOvershoot(animated: !reduceMotion)]
                    + terminalEffects(
                        for: interaction.session,
                        settlesPosition: true
                    )
            }

            let effectiveVelocity = velocity.isFinite
                ? velocity / interaction.referenceScale
                : 0
            let velocityTowardTarget = transition.itemWidthRatio > 1
                ? effectiveVelocity
                : -effectiveVelocity
            let adoptedIntent = interaction.adoptedSettleIntent
            let outcome: SettleOutcome
            if let adoptedIntent,
               !adoptedIntent.hasAdjustedProgress {
                outcome = adoptedIntent.outcome
            } else {
                outcome = PlayerBrowserGridPinchPolicy.shouldComplete(
                    progress: interaction.progress,
                    velocityTowardTarget: velocityTowardTarget
                ) ? .commit : .cancel
            }
            let emitsHaptic = outcome == .commit
                && adoptedIntent?.outcome != .commit
            return beginSettle(
                interaction: interaction,
                outcome: outcome,
                timestamp: timestamp,
                reduceMotion: reduceMotion,
                emitsHaptic: emitsHaptic
            )
        }
    }

    private mutating func handlePinchCancelled(
        timestamp: TimeInterval,
        reduceMotion: Bool
    ) -> [Effect] {
        switch state {
        case .idle, .applying:
            return []

        case .tracking:
            state = .idle
            return []

        case let .settling(settle):
            return settleSynchronously(
                settle,
                settlesPosition: true
            )

        case let .interacting(interaction):
            guard interaction.transition != nil else {
                state = .idle
                return [.resetOvershoot(animated: !reduceMotion)]
                    + terminalEffects(
                        for: interaction.session,
                        settlesPosition: true
                    )
            }
            let outcome = interaction.adoptedSettleIntent?.outcome ?? .cancel
            return beginSettle(
                interaction: interaction,
                outcome: outcome,
                timestamp: timestamp,
                reduceMotion: reduceMotion,
                emitsHaptic: false
            )
        }
    }

    private mutating func beginSettle(
        interaction: InteractionState,
        outcome: SettleOutcome,
        timestamp: TimeInterval,
        reduceMotion: Bool,
        emitsHaptic: Bool
    ) -> [Effect] {
        guard let transition = interaction.transition else { return [] }
        var effects = emitsHaptic ? [Effect.selectionHaptic] : []
        let usesMenuFallback = outcome == .commit
            && interaction.adoptedSettleIntent?.usesMenuFallback == true
        let duration = PlayerBrowserGridPinchPolicy.settleDuration(
            remainingProgress: outcome.targetProgress - interaction.progress
        )
        if reduceMotion
            || duration <= 0
            || abs(outcome.targetProgress - interaction.progress) <= 0.000_1 {
            return effects + terminalTransitionEffects(
                session: interaction.session,
                transition: transition,
                outcome: outcome,
                panDeltaY: interaction.panDeltaY,
                settlesPosition: true,
                resetsOvershoot: true,
                usesMenuFallback: usesMenuFallback,
                stopsDisplayLink: false
            )
        }

        state = .settling(SettleState(
            session: interaction.session,
            transition: transition,
            panDeltaY: interaction.panDeltaY,
            fromProgress: interaction.progress,
            currentProgress: interaction.progress,
            outcome: outcome,
            startTime: sanitizedTimestamp(timestamp),
            duration: duration,
            curve: .easeOutCubic,
            usesMenuFallback: usesMenuFallback
        ))
        effects.append(.startDisplayLink)
        return effects
    }

    private mutating func terminalTransitionEffects(
        session: Session,
        transition: Transition,
        outcome: SettleOutcome,
        panDeltaY: CGFloat,
        settlesPosition: Bool,
        resetsOvershoot: Bool,
        usesMenuFallback: Bool,
        stopsDisplayLink: Bool
    ) -> [Effect] {
        pendingRendererAction = .terminalTransition(
            session: session,
            transition: transition,
            outcome: outcome,
            settlesPosition: settlesPosition,
            resetsOvershoot: resetsOvershoot,
            usesMenuFallback: usesMenuFallback,
            stopsDisplayLink: stopsDisplayLink
        )
        var effects = [Effect.renderTransition(
            id: transition.id,
            progress: outcome.targetProgress,
            panDeltaY: panDeltaY
        )]
        switch outcome {
        case .commit:
            effects.append(.commitTransition(
                id: transition.id,
                mode: transition.toMode
            ))
        case .cancel:
            effects.append(.discardTransition(id: transition.id))
        }
        return effects
    }

    private mutating func handleSettleStarted(
        timestamp: TimeInterval
    ) -> [Effect] {
        guard case var .settling(settle) = state,
              settle.startTime == nil else {
            return []
        }
        settle.startTime = sanitizedTimestamp(timestamp)
        state = .settling(settle)
        return []
    }

    private mutating func handleSettleTick(
        timestamp: TimeInterval
    ) -> [Effect] {
        guard case var .settling(settle) = state else { return [] }
        let tickTime = sanitizedTimestamp(timestamp)
        if settle.startTime == nil {
            settle.startTime = tickTime
        }
        let elapsed = max(tickTime - (settle.startTime ?? tickTime), 0)
        let fraction = min(max(elapsed / settle.duration, 0), 1)
        let easedFraction = settle.curve.value(at: CGFloat(fraction))
        let progress = settle.fromProgress
            + (settle.outcome.targetProgress - settle.fromProgress)
                * easedFraction
        if fraction >= 1 {
            return terminalTransitionEffects(
                session: settle.session,
                transition: settle.transition,
                outcome: settle.outcome,
                panDeltaY: settle.panDeltaY,
                settlesPosition: true,
                resetsOvershoot: false,
                usesMenuFallback: settle.usesMenuFallback,
                stopsDisplayLink: true
            )
        }

        settle.currentProgress = progress
        state = .settling(settle)
        return [.renderTransition(
            id: settle.transition.id,
            progress: progress,
            panDeltaY: settle.panDeltaY
        )]
    }

    private mutating func handleInterrupt() -> [Effect] {
        switch state {
        case .idle, .applying:
            return []

        case .tracking:
            state = .idle
            return []

        case let .interacting(interaction):
            guard let transition = interaction.transition else {
                state = .idle
                return [.resetOvershoot(animated: false)]
                    + terminalEffects(
                        for: interaction.session,
                        settlesPosition: false
                    )
            }
            let outcome = interaction.adoptedSettleIntent?.outcome ?? .cancel
            let usesMenuFallback = outcome == .commit
                && interaction.adoptedSettleIntent?.usesMenuFallback == true
            return terminalTransitionEffects(
                session: interaction.session,
                transition: transition,
                outcome: outcome,
                panDeltaY: interaction.panDeltaY,
                settlesPosition: false,
                resetsOvershoot: true,
                usesMenuFallback: usesMenuFallback,
                stopsDisplayLink: false
            )

        case let .settling(settle):
            return settleSynchronously(
                settle,
                settlesPosition: false
            )
        }
    }

    private mutating func settleSynchronously(
        _ settle: SettleState,
        settlesPosition: Bool
    ) -> [Effect] {
        terminalTransitionEffects(
            session: settle.session,
            transition: settle.transition,
            outcome: settle.outcome,
            panDeltaY: settle.panDeltaY,
            settlesPosition: settlesPosition,
            resetsOvershoot: true,
            usesMenuFallback: settle.usesMenuFallback,
            stopsDisplayLink: true
        )
    }

    private mutating func handleRendererSuccess(
        wasInterrupted: Bool
    ) -> [Effect] {
        guard let pendingRendererAction else { return [] }
        self.pendingRendererAction = nil

        switch pendingRendererAction {
        case let .boundaryCommit(sample, transition, emitsHaptic):
            guard case var .interacting(interaction) = state,
                  interaction.transition?.id == transition.id else {
                return rendererInvariantFailureEffects()
            }
            interaction.session.currentMode = transition.toMode
            interaction.session.didCommitGeometry = true
            interaction.referenceScale *= transition.itemWidthRatio
            interaction.referenceCentroidY = sample.centroidY
            interaction.basePanDeltaY = 0
            interaction.panDeltaY = 0
            interaction.transition = nil
            interaction.progress = 0
            interaction.adoptedSettleIntent = nil
            var effects = emitsHaptic ? [Effect.selectionHaptic] : []
            if wasInterrupted {
                state = .idle
                effects.append(.resetOvershoot(animated: false))
                return effects + terminalEffects(
                    for: interaction.session,
                    settlesPosition: false
                )
            }
            state = .interacting(interaction)
            effects.append(.continuePinch(sample))
            return effects

        case let .reversalDiscard(sample, transition):
            guard case var .interacting(interaction) = state,
                  interaction.transition?.id == transition.id else {
                return rendererInvariantFailureEffects()
            }
            interaction.transition = nil
            interaction.progress = 0
            interaction.adoptedSettleIntent = nil
            if wasInterrupted {
                state = .idle
                return [.resetOvershoot(animated: false)]
                    + terminalEffects(
                        for: interaction.session,
                        settlesPosition: false
                    )
            }
            state = .interacting(interaction)
            return [.continuePinch(sample)]

        case let .terminalTransition(
            session,
            transition,
            outcome,
            settlesPosition,
            resetsOvershoot,
            _,
            stopsDisplayLink
        ):
            var acknowledgedSession = session
            if outcome == .commit {
                acknowledgedSession.currentMode = transition.toMode
                acknowledgedSession.didCommitGeometry = true
            }
            state = .idle
            var effects = [Effect]()
            if stopsDisplayLink {
                effects.append(.stopDisplayLink)
            }
            if resetsOvershoot || wasInterrupted {
                effects.append(.resetOvershoot(animated: false))
            }
            return effects + terminalEffects(
                for: acknowledgedSession,
                settlesPosition: settlesPosition && !wasInterrupted
            )

        case let .directMode(pendingSession, mode, settlesPosition):
            var session = pendingSession
            session.currentMode = mode
            session.didCommitGeometry = true
            state = .idle
            return terminalEffects(
                for: session,
                settlesPosition: settlesPosition && !wasInterrupted
            )
        }
    }

    private mutating func rendererInvariantFailureEffects() -> [Effect] {
        let session = state.session
        let stopsDisplayLink: Bool
        if case .settling = state {
            stopsDisplayLink = true
        } else {
            stopsDisplayLink = false
        }
        hasPendingInterrupt = false
        state = .idle
        var effects = stopsDisplayLink
            ? [Effect.stopDisplayLink, .resetRenderer]
            : [.resetRenderer]
        guard let session else {
            effects.append(.finishInteraction(settlesPosition: false))
            return effects
        }
        return effects + terminalEffects(
            for: session,
            settlesPosition: false
        )
    }

    private mutating func handleRendererFailure(
        wasInterrupted: Bool
    ) -> [Effect] {
        if let pendingRendererAction {
            self.pendingRendererAction = nil
            switch pendingRendererAction {
            case let .boundaryCommit(_, transition, _):
                guard case let .interacting(interaction) = state,
                      interaction.transition?.id == transition.id else {
                    return rendererInvariantFailureEffects()
                }
                if interaction.adoptedSettleIntent?.outcome == .commit,
                   interaction.adoptedSettleIntent?.usesMenuFallback == true {
                    let settlesPosition = !wasInterrupted
                    state = .applying(interaction.session)
                    self.pendingRendererAction = .directMode(
                        session: interaction.session,
                        mode: transition.toMode,
                        settlesPosition: settlesPosition
                    )
                    hasPendingInterrupt = wasInterrupted
                    return [
                        .resetRenderer,
                        .applyMode(transition.toMode)
                    ]
                }
                hasPendingInterrupt = false
                state = .idle
                return [.resetRenderer] + terminalEffects(
                    for: interaction.session,
                    settlesPosition: !wasInterrupted
                )

            case .reversalDiscard:
                guard case let .interacting(interaction) = state else {
                    return rendererInvariantFailureEffects()
                }
                hasPendingInterrupt = false
                state = .idle
                return [.resetRenderer] + terminalEffects(
                    for: interaction.session,
                    settlesPosition: !wasInterrupted
                )

            case let .terminalTransition(
                session,
                transition,
                outcome,
                settlesPosition,
                _,
                usesMenuFallback,
                stopsDisplayLink
            ):
                let effectiveSettlesPosition =
                    settlesPosition && !wasInterrupted
                if usesMenuFallback, outcome == .commit {
                    state = .applying(session)
                    self.pendingRendererAction = .directMode(
                        session: session,
                        mode: transition.toMode,
                        settlesPosition: effectiveSettlesPosition
                    )
                    hasPendingInterrupt = wasInterrupted
                    var effects = [Effect]()
                    if stopsDisplayLink {
                        effects.append(.stopDisplayLink)
                    }
                    effects.append(.resetRenderer)
                    effects.append(.applyMode(transition.toMode))
                    return effects
                }
                hasPendingInterrupt = false
                state = .idle
                var effects = stopsDisplayLink
                    ? [Effect.stopDisplayLink]
                    : []
                effects.append(.resetRenderer)
                return effects + terminalEffects(
                    for: session,
                    settlesPosition: effectiveSettlesPosition
                )

            case let .directMode(session, _, settlesPosition):
                hasPendingInterrupt = false
                state = .idle
                return [.resetRenderer] + terminalEffects(
                    for: session,
                    settlesPosition: settlesPosition && !wasInterrupted
                )
            }
        }

        hasPendingInterrupt = false

        switch state {
        case .idle:
            return []

        case .tracking:
            state = .idle
            return []

        case let .interacting(interaction):
            if let transition = interaction.transition,
               interaction.adoptedSettleIntent?.outcome == .commit,
               interaction.adoptedSettleIntent?.usesMenuFallback == true {
                state = .applying(interaction.session)
                pendingRendererAction = .directMode(
                    session: interaction.session,
                    mode: transition.toMode,
                    settlesPosition: true
                )
                return [
                    .resetRenderer,
                    .applyMode(transition.toMode)
                ]
            }
            state = .idle
            return [.resetRenderer] + terminalEffects(
                for: interaction.session,
                settlesPosition: true
            )

        case let .settling(settle):
            if settle.usesMenuFallback, settle.outcome == .commit {
                state = .applying(settle.session)
                pendingRendererAction = .directMode(
                    session: settle.session,
                    mode: settle.transition.toMode,
                    settlesPosition: true
                )
                return [
                    .stopDisplayLink,
                    .resetRenderer,
                    .applyMode(settle.transition.toMode)
                ]
            }
            state = .idle
            return [
                .stopDisplayLink,
                .resetRenderer
            ] + terminalEffects(
                for: settle.session,
                settlesPosition: true
            )

        case let .applying(session):
            state = .idle
            return [.resetRenderer] + terminalEffects(
                for: session,
                settlesPosition: true
            )
        }
    }

    private func terminalEffects(
        for session: Session,
        settlesPosition: Bool
    ) -> [Effect] {
        var effects = [Effect]()
        if session.currentMode != session.initialMode {
            effects.append(.persistMode(session.currentMode))
        }
        if session.didCommitGeometry {
            let initialQuality = session.initialMode.requiredImageQuality(
                defaultGridMode: session.defaultMode
            )
            let finalQuality = session.currentMode.requiredImageQuality(
                defaultGridMode: session.defaultMode
            )
            effects.append(.reconcileMedia(MediaReconciliation(
                finalMode: session.currentMode,
                cancelsPrefetchLoads: initialQuality != finalQuality
            )))
        }
        effects.append(.finishInteraction(
            settlesPosition: settlesPosition
        ))
        return effects
    }

    private func isValid(sample: PinchSample) -> Bool {
        sample.scale.isFinite
            && sample.scale > 0
            && sample.centroidY.isFinite
    }

    private func sanitizedTimestamp(_ timestamp: TimeInterval) -> TimeInterval {
        timestamp.isFinite ? timestamp : 0
    }
}
