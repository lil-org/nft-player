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
        let timestamp: TimeInterval
    }

    struct ModeRatio: Equatable {
        let mode: MobileCollectionBrowserGridMode
        let itemWidthRatio: CGFloat
    }

    struct Plane: Equatable {
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
            guard Self.supportsTransition(
                fromMode: fromMode,
                toMode: toMode,
                itemWidthRatio: itemWidthRatio
            ) else {
                return nil
            }
            self.id = id
            self.fromMode = fromMode
            self.toMode = toMode
            self.itemWidthRatio = itemWidthRatio
        }

        static func supportsTransition(
            fromMode: MobileCollectionBrowserGridMode,
            toMode: MobileCollectionBrowserGridMode,
            itemWidthRatio: CGFloat
        ) -> Bool {
            fromMode != toMode
                && itemWidthRatio.isFinite
                && itemWidthRatio > 0
                && itemWidthRatio != 1
                && (itemWidthRatio > 1)
                    == (toMode.columnCount < fromMode.columnCount)
        }
    }

    enum Event: Equatable {
        case menuSelected(
            fromMode: MobileCollectionBrowserGridMode,
            toMode: MobileCollectionBrowserGridMode,
            reduceMotion: Bool
        )
        case pinchBegan(
            sample: PinchSample,
            currentMode: MobileCollectionBrowserGridMode
        )
        case pinchChanged(sample: PinchSample)
        case pinchEnded(
            velocity: CGFloat,
            timestamp: TimeInterval,
            reduceMotion: Bool
        )
        case pinchCancelled(reduceMotion: Bool)
        case settleStarted(timestamp: TimeInterval)
        case settleTick(timestamp: TimeInterval)
        case rendererSucceeded
        case interrupt
        case rendererFailed
    }

    enum Effect: Equatable {
        case beginInteraction
        case installPlane(Plane)
        case renderZoom(planeId: UUID?, scale: CGFloat, panDeltaY: CGFloat)
        case renderSettle(
            id: UUID,
            scale: CGFloat,
            settleProgress: CGFloat,
            panDeltaY: CGFloat
        )
        case commitPlane(id: UUID, mode: MobileCollectionBrowserGridMode)
        case discardPlane(id: UUID)
        case applyMode(MobileCollectionBrowserGridMode)
        case selectionHaptic
        case startDisplayLink
        case stopDisplayLink
        case persistMode(MobileCollectionBrowserGridMode)
        case reconcileMedia(cancelsPrefetchLoads: Bool)
        case finishInteraction(settlesPosition: Bool)
        case resetRenderer
    }

    typealias RatioProvider = (MobileCollectionBrowserGridMode) -> [ModeRatio]

    private struct Session: Equatable {
        let initialMode: MobileCollectionBrowserGridMode
        let modeRatios: [ModeRatio]

        var minimumRatio: CGFloat {
            modeRatios.first?.itemWidthRatio ?? 1
        }

        var maximumRatio: CGFloat {
            modeRatios.last?.itemWidthRatio ?? 1
        }

        func ratio(for mode: MobileCollectionBrowserGridMode) -> CGFloat? {
            modeRatios.first { $0.mode == mode }?.itemWidthRatio
        }

        /// The rendered scale a settle onto `mode` comes to rest at.
        /// `makeModeRatios` pins `initialMode` to exactly 1, so the fallback
        /// only covers a mode that never entered the session.
        func scale(landingOn mode: MobileCollectionBrowserGridMode) -> CGFloat {
            ratio(for: mode) ?? 1
        }
    }

    private struct AdoptedSettleContext: Equatable {
        let targetMode: MobileCollectionBrowserGridMode
        let usesMenuFallback: Bool
        let planeIdAtAdoption: UUID?
        let scaleAtAdoption: CGFloat
        /// How far the adopted settle had already crossfaded. The hold keeps
        /// rendering at this progress and the release resumes from it, so
        /// grabbing a running settle never replays the fade from zero.
        let progressAtAdoption: CGFloat
    }

    private enum AdoptedSettlePhase: Equatable {
        struct Resolution {
            let context: AdoptedSettleContext?
            let heldContext: AdoptedSettleContext?
            let preservedPlaneProgress: CGFloat?

            var releaseContext: AdoptedSettleContext? {
                if let heldContext { return heldContext }
                guard preservedPlaneProgress.map({ $0 > 0 }) == true else {
                    return nil
                }
                return context
            }

            var pinsPlane: Bool {
                heldContext != nil
                    || preservedPlaneProgress.map({ $0 > 0 }) == true
            }
        }

        case none
        case holding(AdoptedSettleContext)
        case adjusted(AdoptedSettleContext)

        mutating func registerScale(_ scale: CGFloat) {
            guard case let .holding(context) = self,
                  abs(scale / context.scaleAtAdoption - 1)
                    > PlayerBrowserGridInteractionCoordinator
                        .adjustmentScaleDeviationDeadZone else {
                return
            }
            self = .adjusted(context)
        }

        func resolve(
            scale: CGFloat,
            plane: Plane?
        ) -> Resolution {
            switch self {
            case .none:
                return Resolution(
                    context: nil,
                    heldContext: nil,
                    preservedPlaneProgress: nil
                )

            case let .holding(context):
                return Resolution(
                    context: context,
                    heldContext: context,
                    preservedPlaneProgress: plane.flatMap {
                        $0.id == context.planeIdAtAdoption
                            ? context.progressAtAdoption
                            : nil
                    }
                )

            case let .adjusted(context):
                guard let plane,
                      plane.id == context.planeIdAtAdoption else {
                    return Resolution(
                        context: context,
                        heldContext: nil,
                        preservedPlaneProgress: nil
                    )
                }
                let scaleDeviation = abs(scale / context.scaleAtAdoption - 1)
                guard scaleDeviation.isFinite else {
                    return Resolution(
                        context: context,
                        heldContext: nil,
                        preservedPlaneProgress: 0
                    )
                }
                let handoffProgress = max(
                    scaleDeviation
                        - PlayerBrowserGridInteractionCoordinator
                            .adjustmentScaleDeviationDeadZone,
                    0
                ) / (
                    PlayerBrowserGridPinchPolicy.activationScaleDeviation
                        - PlayerBrowserGridInteractionCoordinator
                            .adjustmentScaleDeviationDeadZone
                )
                let retainedProgress = 1 - min(handoffProgress, 1)
                return Resolution(
                    context: context,
                    heldContext: nil,
                    preservedPlaneProgress:
                        context.progressAtAdoption * retainedProgress
                )
            }
        }
    }

    private struct InteractionState: Equatable {
        let session: Session
        let referenceScale: CGFloat
        let referenceCentroidY: CGFloat
        let basePanDeltaY: CGFloat
        var panDeltaY: CGFloat
        var scale: CGFloat
        /// What the activation trim divided out of the rendered scale. The
        /// release multiplies it back so the settle target is chosen from the
        /// physical pinch ratio, not the trimmed render scale.
        let activationAdjustment: CGFloat
        var latestSampleTimestamp: TimeInterval
        var plane: Plane?
        var adoptedSettlePhase: AdoptedSettlePhase
    }

    private enum PlaneDecision {
        case keep
        case replace(ModeRatio)
        case discard
    }

    private struct SettleState: Equatable {
        let session: Session
        let plane: Plane?
        let targetMode: MobileCollectionBrowserGridMode
        let initialLogDistance: CGFloat
        let initialProgress: CGFloat
        let panDeltaY: CGFloat
        var logOffset: CGFloat
        var logVelocity: CGFloat
        var lastTickTime: TimeInterval?
        let usesMenuFallback: Bool

        var commits: Bool {
            targetMode != session.initialMode
        }

        var targetScale: CGFloat {
            session.scale(landingOn: targetMode)
        }

        var currentScale: CGFloat {
            targetScale * exp(logOffset)
        }

        var currentProgress: CGFloat {
            guard initialLogDistance > 0 else { return commits ? 1 : 0 }
            let travelProgress = min(
                max(1 - abs(logOffset) / initialLogDistance, 0),
                1
            )
            return commits
                ? initialProgress + (1 - initialProgress) * travelProgress
                : initialProgress * (1 - travelProgress)
        }
    }

    private struct PendingRendererAction: Equatable {
        let session: Session
        let mode: MobileCollectionBrowserGridMode
        let settlesPosition: Bool
        /// A menu selection has no gesture to fall back to, so a renderer
        /// failure re-applies its mode directly. A direct-mode application is
        /// already that fallback and must not retry itself.
        let retriesWithDirectMode: Bool
        var wasInterrupted = false
    }

    private enum State: Equatable {
        case idle
        case tracking(Session)
        case interacting(InteractionState)
        case settling(SettleState)
        case awaitingRenderer(PendingRendererAction)
    }

    private static let adjustmentScaleDeviationDeadZone: CGFloat = 0.001

    private var state = State.idle

    var phase: Phase {
        switch state {
        case .idle:
            return .idle
        case .tracking:
            return .tracking
        case .interacting:
            return .interacting
        case .settling, .awaitingRenderer:
            return .settling
        }
    }

    var canBeginPinch: Bool {
        switch state {
        case .idle, .settling:
            return true
        case .tracking, .interacting, .awaitingRenderer:
            return false
        }
    }

    mutating func handle(
        _ event: Event,
        ratioProvider: RatioProvider = { _ in [] }
    ) -> [Effect] {
        if case var .awaitingRenderer(action) = state {
            switch event {
            case .rendererSucceeded:
                return handleRendererSuccess(action)
            case .rendererFailed:
                return handleRendererFailure(action)
            case .interrupt:
                action.wasInterrupted = true
                state = .awaitingRenderer(action)
                return []
            default:
                return []
            }
        }

        switch event {
        case let .menuSelected(fromMode, toMode, reduceMotion):
            return handleMenuSelection(
                fromMode: fromMode,
                toMode: toMode,
                reduceMotion: reduceMotion,
                ratioProvider: ratioProvider
            )

        case let .pinchBegan(sample, currentMode):
            return handlePinchBegan(
                sample: sample,
                currentMode: currentMode,
                ratioProvider: ratioProvider
            )

        case let .pinchChanged(sample):
            return handlePinchChanged(sample)

        case let .pinchEnded(velocity, timestamp, reduceMotion):
            return handlePinchEnded(
                velocity: velocity,
                timestamp: timestamp,
                reduceMotion: reduceMotion
            )

        case let .pinchCancelled(reduceMotion):
            return handlePinchCancelled(reduceMotion: reduceMotion)

        case let .settleStarted(timestamp):
            return handleSettleStarted(timestamp: timestamp)

        case let .settleTick(timestamp):
            return handleSettleTick(timestamp: timestamp)

        case .rendererSucceeded:
            return []

        case .interrupt:
            return handleInterrupt()

        case .rendererFailed:
            return handleRendererFailure()
        }
    }

    private static func makeModeRatios(
        fromMode: MobileCollectionBrowserGridMode,
        provided: [ModeRatio]
    ) -> [ModeRatio] {
        var ratios = provided
            .filter { candidate in
                guard candidate.itemWidthRatio.isFinite,
                      candidate.itemWidthRatio > 0 else {
                    return false
                }
                if candidate.mode == fromMode {
                    return candidate.itemWidthRatio == 1
                }
                return Plane.supportsTransition(
                    fromMode: fromMode,
                    toMode: candidate.mode,
                    itemWidthRatio: candidate.itemWidthRatio
                )
            }
        if !ratios.contains(where: { $0.mode == fromMode }) {
            ratios.append(ModeRatio(mode: fromMode, itemWidthRatio: 1))
        }
        var seenModes = Set<MobileCollectionBrowserGridMode>()
        return ratios
            .filter { seenModes.insert($0.mode).inserted }
            .sorted { $0.itemWidthRatio < $1.itemWidthRatio }
    }

    private mutating func handleMenuSelection(
        fromMode: MobileCollectionBrowserGridMode,
        toMode: MobileCollectionBrowserGridMode,
        reduceMotion: Bool,
        ratioProvider: RatioProvider
    ) -> [Effect] {
        guard case .idle = state,
              fromMode != toMode else {
            return []
        }

        let session = Session(
            initialMode: fromMode,
            modeRatios: Self.makeModeRatios(
                fromMode: fromMode,
                provided: ratioProvider(fromMode)
            )
        )
        guard !reduceMotion,
              let targetRatio = session.ratio(for: toMode),
              let plane = Plane(
                  fromMode: fromMode,
                  toMode: toMode,
                  itemWidthRatio: targetRatio
              ) else {
            return [.beginInteraction, beginDirectModeApplication(
                session: session,
                mode: toMode,
                settlesPosition: true
            )]
        }

        state = .settling(SettleState(
            session: session,
            plane: plane,
            targetMode: toMode,
            initialLogDistance: abs(log(targetRatio)),
            initialProgress: 0,
            panDeltaY: 0,
            logOffset: -log(targetRatio),
            logVelocity: 0,
            lastTickTime: nil,
            usesMenuFallback: true
        ))
        return [
            .beginInteraction,
            .installPlane(plane),
            .renderSettle(
                id: plane.id,
                scale: 1,
                settleProgress: 0,
                panDeltaY: 0
            ),
            .startDisplayLink
        ]
    }

    private mutating func handlePinchBegan(
        sample: PinchSample,
        currentMode: MobileCollectionBrowserGridMode,
        ratioProvider: RatioProvider
    ) -> [Effect] {
        guard isValid(sample: sample) else { return [] }

        switch state {
        case .idle:
            // The recognizer's scale is cumulative from the initial touch
            // separation, so by the time it begins it already carries the
            // movement that made it recognize. That travel is real finger
            // movement and must count toward the pinch — rebasing here made
            // every gesture read ~15% shallower than the physical pinch and
            // borderline releases settle back where Photos commits.
            state = .tracking(Session(
                initialMode: currentMode,
                modeRatios: Self.makeModeRatios(
                    fromMode: currentMode,
                    provided: ratioProvider(currentMode)
                )
            ))
            return []

        case let .settling(settle):
            let referenceScale = sample.scale / settle.currentScale
            guard settle.currentScale.isFinite,
                  settle.currentScale > 0,
                  referenceScale.isFinite,
                  referenceScale > 0 else {
                return []
            }
            state = .interacting(InteractionState(
                session: settle.session,
                referenceScale: referenceScale,
                referenceCentroidY: sample.centroidY,
                basePanDeltaY: settle.panDeltaY,
                panDeltaY: settle.panDeltaY,
                scale: settle.currentScale,
                activationAdjustment: 1,
                latestSampleTimestamp: sample.timestamp,
                plane: settle.plane,
                adoptedSettlePhase: .holding(AdoptedSettleContext(
                    targetMode: settle.targetMode,
                    usesMenuFallback: settle.usesMenuFallback,
                    planeIdAtAdoption: settle.plane?.id,
                    scaleAtAdoption: settle.currentScale,
                    progressAtAdoption: settle.currentProgress
                ))
            ))
            return [.stopDisplayLink]

        case .tracking, .interacting, .awaitingRenderer:
            return []
        }
    }

    private mutating func handlePinchChanged(_ sample: PinchSample) -> [Effect] {
        guard isValid(sample: sample) else { return [] }

        switch state {
        case let .tracking(session):
            // The tracking scale is the recognizer's own cumulative ratio —
            // `handlePinchBegan` deliberately does not rebase it.
            let rawEffectiveScale = sample.scale
            guard rawEffectiveScale.isFinite,
                  rawEffectiveScale > 0,
                  abs(rawEffectiveScale - 1)
                    > PlayerBrowserGridPinchPolicy.activationScaleDeviation else {
                return []
            }
            let effectiveScale = PlayerBrowserGridPinchPolicy
                .effectiveScaleAfterActivation(rawEffectiveScale)
            var interaction = InteractionState(
                session: session,
                referenceScale: sample.scale / effectiveScale,
                referenceCentroidY: sample.centroidY,
                basePanDeltaY: 0,
                panDeltaY: 0,
                scale: effectiveScale,
                activationAdjustment: PlayerBrowserGridPinchPolicy
                    .activationTrimDivisor(rawEffectiveScale),
                latestSampleTimestamp: sample.timestamp,
                plane: nil,
                adoptedSettlePhase: .none
            )
            var effects = [Effect.beginInteraction]
            effects += zoomEffects(interaction: &interaction)
            state = .interacting(interaction)
            return effects

        case var .interacting(interaction):
            let effectiveScale = sample.scale / interaction.referenceScale
            guard effectiveScale.isFinite, effectiveScale > 0 else { return [] }
            interaction.latestSampleTimestamp = sample.timestamp
            interaction.scale = effectiveScale
            interaction.panDeltaY = interaction.basePanDeltaY
                + sample.centroidY
                - interaction.referenceCentroidY
            interaction.adoptedSettlePhase.registerScale(effectiveScale)
            let effects = zoomEffects(interaction: &interaction)
            state = .interacting(interaction)
            return effects

        case .idle, .settling, .awaitingRenderer:
            return []
        }
    }

    private func zoomEffects(interaction: inout InteractionState) -> [Effect] {
        var effects = [Effect]()
        let adoptedSettle = interaction.adoptedSettlePhase.resolve(
            scale: interaction.scale,
            plane: interaction.plane
        )

        // A held adopted settle owns the plane until the pinch actually
        // moves: the release still commits its target, so retargeting
        // under it renders a frame on a lattice nothing will land on and costs
        // two extra grid rebuilds.
        let decision = adoptedSettle.pinsPlane
            ? PlaneDecision.keep
            : planeDecision(
                scale: interaction.scale,
                session: interaction.session,
                installedPlane: interaction.plane
            )

        switch decision {
        case .keep:
            break

        case let .replace(target):
            if interaction.plane?.toMode != target.mode,
               let plane = Plane(
                   fromMode: interaction.session.initialMode,
                   toMode: target.mode,
                   itemWidthRatio: target.itemWidthRatio
               ) {
                interaction.plane = plane
                effects.append(.installPlane(plane))
            }

        case .discard:
            if let plane = interaction.plane {
                interaction.plane = nil
                effects.append(.discardPlane(id: plane.id))
            }
        }

        let renderScale = PlayerBrowserGridPinchPolicy.rubberBandedScale(
            interaction.scale,
            minimumRatio: interaction.session.minimumRatio,
            maximumRatio: interaction.session.maximumRatio
        )
        // The exact adopted plane hands its crossfade back to direct
        // manipulation over the same travel used to activate a fresh pinch.
        // That keeps the first adjusted frame continuous without leaving stale
        // destination content behind after the user changes direction.
        if let preservedProgress = adoptedSettle.preservedPlaneProgress,
           preservedProgress > 0,
           let plane = interaction.plane {
            effects.append(.renderSettle(
                id: plane.id,
                scale: renderScale,
                settleProgress: preservedProgress,
                panDeltaY: interaction.panDeltaY
            ))
            return effects
        }
        effects.append(.renderZoom(
            planeId: interaction.plane?.id,
            scale: renderScale,
            panDeltaY: interaction.panDeltaY
        ))
        return effects
    }

    /// Hysteresis prevents synchronous plane rebuilds from churning near a
    /// target threshold.
    private func planeDecision(
        scale: CGFloat,
        session: Session,
        installedPlane: Plane?
    ) -> PlaneDecision {
        let logScale = log(max(scale, 0.000_1))

        let wantsDenser: Bool
        if let installedPlane {
            let planeIsDenser = installedPlane.itemWidthRatio < 1
            let reversesBeyondDiscard = planeIsDenser
                ? scale > PlayerBrowserGridPinchPolicy.underPlaneDiscardScale
                : scale < PlayerBrowserGridPinchPolicy.overPlaneDiscardScale
            guard reversesBeyondDiscard else {
                guard let target = sameDirectionTarget(
                    logScale: logScale,
                    session: session,
                    installedPlane: installedPlane,
                    denser: planeIsDenser
                ) else {
                    return .keep
                }
                return .replace(target)
            }
            wantsDenser = !planeIsDenser
        } else if scale < PlayerBrowserGridPinchPolicy.underPlaneInstallScale {
            wantsDenser = true
        } else if scale > PlayerBrowserGridPinchPolicy.overPlaneInstallScale {
            wantsDenser = false
        } else {
            return .keep
        }

        guard let target = nearestTarget(
            logScale: logScale,
            session: session,
            denser: wantsDenser
        ) else {
            return installedPlane == nil ? .keep : .discard
        }
        return .replace(target)
    }

    /// A continuous pinch that sails past its plane's target re-aims the
    /// plane at the next mode in the same direction, so a deep zoom
    /// crossfades toward the lattice the release will actually land on. The
    /// gesture must clear the midpoint between the two targets by the
    /// hysteresis margin — a bare nearest-target comparison would rebuild
    /// the plane every frame while the fingers hover on the boundary.
    private func sameDirectionTarget(
        logScale: CGFloat,
        session: Session,
        installedPlane: Plane,
        denser: Bool
    ) -> ModeRatio? {
        guard let target = nearestTarget(
            logScale: logScale,
            session: session,
            denser: denser
        ), target.mode != installedPlane.toMode else {
            return nil
        }
        let installedDistance = abs(logScale - log(installedPlane.itemWidthRatio))
        let replacementDistance = abs(logScale - log(target.itemWidthRatio))
        guard installedDistance - replacementDistance
            > PlayerBrowserGridPinchPolicy.planeRetargetHysteresis else {
            return nil
        }
        return target
    }

    private func nearestTarget(
        logScale: CGFloat,
        session: Session,
        denser: Bool
    ) -> ModeRatio? {
        session.modeRatios
            .lazy
            .filter { denser ? $0.itemWidthRatio < 1 : $0.itemWidthRatio > 1 }
            .min { lhs, rhs in
                abs(logScale - log(lhs.itemWidthRatio))
                    < abs(logScale - log(rhs.itemWidthRatio))
            }
    }

    private mutating func handlePinchEnded(
        velocity: CGFloat,
        timestamp: TimeInterval,
        reduceMotion: Bool
    ) -> [Effect] {
        switch state {
        case .idle, .awaitingRenderer:
            return []

        case .tracking:
            state = .idle
            return []

        case let .settling(settle):
            return settleSynchronously(settle, settlesPosition: true)

        case let .interacting(interaction):
            let adoptedSettle = interaction.adoptedSettlePhase.resolve(
                scale: interaction.scale,
                plane: interaction.plane
            )
            // The recognizer's velocity freezes at its last touch sample, so
            // after a still hold it reports the speed from before the hold.
            // A release with no recent sample is a still release.
            let sampleAge = timestamp - interaction.latestSampleTimestamp
            let velocityIsFresh = sampleAge.isFinite
                && sampleAge >= 0
                && sampleAge
                    <= PlayerBrowserGridPinchPolicy.velocityHoldTimeout
            let effectiveVelocity = velocityIsFresh
                && velocity.isFinite
                && interaction.referenceScale > 0
                ? velocity / interaction.referenceScale
                : 0
            let releaseContext = adoptedSettle.releaseContext
            let targetMode: MobileCollectionBrowserGridMode
            // Do not replace a plane while its adopted cell corrections are
            // still visibly handing off to direct manipulation.
            if let releaseContext {
                targetMode = releaseContext.targetMode
            } else if let targetIndex = PlayerBrowserGridPinchPolicy.settleTargetIndex(
                scale: interaction.scale * interaction.activationAdjustment,
                velocity: effectiveVelocity * interaction.activationAdjustment,
                itemWidthRatios: interaction.session.modeRatios.map(\.itemWidthRatio)
            ) {
                targetMode = interaction.session.modeRatios[targetIndex].mode
            } else {
                targetMode = interaction.session.initialMode
            }
            return beginSettle(
                interaction: interaction,
                targetMode: targetMode,
                effectiveVelocity: effectiveVelocity,
                reduceMotion: reduceMotion,
                usesMenuFallback: releaseContext?.usesMenuFallback ?? false,
                adoptedSettle: adoptedSettle
            )
        }
    }

    private mutating func handlePinchCancelled(
        reduceMotion: Bool
    ) -> [Effect] {
        switch state {
        case .idle, .awaitingRenderer:
            return []

        case .tracking:
            state = .idle
            return []

        case let .settling(settle):
            return settleSynchronously(settle, settlesPosition: true)

        case let .interacting(interaction):
            let adoptedSettle = interaction.adoptedSettlePhase.resolve(
                scale: interaction.scale,
                plane: interaction.plane
            )
            let cancellationContext = adoptedSettle.heldContext
            return beginSettle(
                interaction: interaction,
                targetMode: cancellationContext?.targetMode
                    ?? interaction.session.initialMode,
                effectiveVelocity: 0,
                reduceMotion: reduceMotion,
                usesMenuFallback: cancellationContext?.usesMenuFallback ?? false,
                adoptedSettle: adoptedSettle
            )
        }
    }

    private mutating func beginSettle(
        interaction: InteractionState,
        targetMode: MobileCollectionBrowserGridMode,
        effectiveVelocity: CGFloat,
        reduceMotion: Bool,
        usesMenuFallback: Bool,
        adoptedSettle: AdoptedSettlePhase.Resolution
    ) -> [Effect] {
        let session = interaction.session
        let commits = targetMode != session.initialMode
        let emitsHaptic = commits
            && adoptedSettle.context?.targetMode != targetMode
        var effects = emitsHaptic ? [Effect.selectionHaptic] : []
        var plane = interaction.plane
        let fromScale = PlayerBrowserGridPinchPolicy.rubberBandedScale(
            interaction.scale,
            minimumRatio: session.minimumRatio,
            maximumRatio: session.maximumRatio
        )

        // A plane already aimed at `targetMode` was built from that mode's
        // ratio, so reaching it here means the lookup below cannot fail.
        if commits, plane?.toMode != targetMode {
            guard let targetRatio = session.ratio(for: targetMode),
                  let installedPlane = Plane(
                      fromMode: session.initialMode,
                      toMode: targetMode,
                      itemWidthRatio: targetRatio
                  ) else {
                return effects + [beginDirectModeApplication(
                    session: session,
                    mode: targetMode,
                    settlesPosition: true
                )]
            }
            plane = installedPlane
            effects.append(.installPlane(installedPlane))
            effects.append(.renderSettle(
                id: installedPlane.id,
                scale: fromScale,
                settleProgress: 0,
                panDeltaY: interaction.panDeltaY
            ))
        }
        let logOffset = log(fromScale / session.scale(landingOn: targetMode))
        if reduceMotion
            || abs(logOffset)
                <= PlayerBrowserGridPinchPolicy.settleRestLogDistance {
            return effects + terminalSettleEffects(
                session: session,
                plane: plane,
                targetMode: targetMode,
                panDeltaY: interaction.panDeltaY,
                settlesPosition: true,
                usesMenuFallback: usesMenuFallback,
                stopsDisplayLink: false
            )
        }

        let initialProgress: CGFloat
        if let context = adoptedSettle.context,
           plane?.id == context.planeIdAtAdoption {
            initialProgress = adoptedSettle.preservedPlaneProgress ?? 0
        } else {
            initialProgress = 0
        }

        state = .settling(SettleState(
            session: session,
            plane: plane,
            targetMode: targetMode,
            initialLogDistance: abs(logOffset),
            initialProgress: initialProgress,
            panDeltaY: interaction.panDeltaY,
            logOffset: logOffset,
            logVelocity: PlayerBrowserGridPinchPolicy.settleSeedVelocity(
                forLogOffset: logOffset,
                effectiveVelocity: effectiveVelocity,
                scale: fromScale
            ),
            // The clock starts at the first display-link tick — anchoring it
            // to the release event would integrate the event-delivery latency
            // as a visible first-frame jump.
            lastTickTime: nil,
            usesMenuFallback: usesMenuFallback
        ))
        effects.append(.startDisplayLink)
        return effects
    }

    private mutating func terminalSettleEffects(
        session: Session,
        plane: Plane?,
        targetMode: MobileCollectionBrowserGridMode,
        panDeltaY: CGFloat,
        settlesPosition: Bool,
        usesMenuFallback: Bool,
        stopsDisplayLink: Bool
    ) -> [Effect] {
        let commits = targetMode != session.initialMode
        var effects = stopsDisplayLink ? [Effect.stopDisplayLink] : []

        if commits, let plane, plane.toMode == targetMode {
            state = .awaitingRenderer(PendingRendererAction(
                session: session,
                mode: targetMode,
                settlesPosition: settlesPosition,
                retriesWithDirectMode: usesMenuFallback
            ))
            effects.append(.renderSettle(
                id: plane.id,
                scale: session.scale(landingOn: targetMode),
                settleProgress: 1,
                panDeltaY: panDeltaY
            ))
            effects.append(.commitPlane(id: plane.id, mode: targetMode))
            return effects
        }

        if commits {
            effects.append(beginDirectModeApplication(
                session: session,
                mode: targetMode,
                settlesPosition: settlesPosition
            ))
            return effects
        }

        effects.append(.renderZoom(
            planeId: plane?.id,
            scale: 1,
            panDeltaY: panDeltaY
        ))
        if let plane {
            state = .awaitingRenderer(PendingRendererAction(
                session: session,
                mode: targetMode,
                settlesPosition: settlesPosition,
                retriesWithDirectMode: usesMenuFallback
            ))
            effects.append(.discardPlane(id: plane.id))
            return effects
        }

        state = .idle
        return effects + terminalEffects(
            for: session,
            settlesPosition: settlesPosition
        )
    }

    private mutating func handleSettleStarted(
        timestamp: TimeInterval
    ) -> [Effect] {
        guard case var .settling(settle) = state,
              settle.lastTickTime == nil else {
            return []
        }
        settle.lastTickTime = sanitizedTimestamp(timestamp)
        state = .settling(settle)
        return []
    }

    private mutating func handleSettleTick(
        timestamp: TimeInterval
    ) -> [Effect] {
        guard case var .settling(settle) = state else { return [] }
        let tickTime = sanitizedTimestamp(timestamp)
        let deltaTime = CGFloat(
            max(tickTime - (settle.lastTickTime ?? tickTime), 0)
        )
        settle.lastTickTime = tickTime
        let stepped = PlayerBrowserGridPinchPolicy.settleSpringStep(
            logOffset: settle.logOffset,
            logVelocity: settle.logVelocity,
            deltaTime: deltaTime
        )
        settle.logOffset = stepped.logOffset
        settle.logVelocity = stepped.logVelocity
        if PlayerBrowserGridPinchPolicy.isSettleSpringAtRest(
            logOffset: settle.logOffset,
            logVelocity: settle.logVelocity
        ) {
            return terminalSettleEffects(
                session: settle.session,
                plane: settle.plane,
                targetMode: settle.targetMode,
                panDeltaY: settle.panDeltaY,
                settlesPosition: true,
                usesMenuFallback: settle.usesMenuFallback,
                stopsDisplayLink: true
            )
        }

        state = .settling(settle)
        if let plane = settle.plane,
           settle.commits || settle.currentProgress > 0 {
            return [.renderSettle(
                id: plane.id,
                scale: settle.currentScale,
                settleProgress: settle.currentProgress,
                panDeltaY: settle.panDeltaY
            )]
        }
        return [.renderZoom(
            planeId: settle.plane?.id,
            scale: settle.currentScale,
            panDeltaY: settle.panDeltaY
        )]
    }

    private mutating func handleInterrupt() -> [Effect] {
        switch state {
        case .idle, .awaitingRenderer:
            return []

        case .tracking:
            state = .idle
            return []

        case let .interacting(interaction):
            let adoptedSettle = interaction.adoptedSettlePhase.resolve(
                scale: interaction.scale,
                plane: interaction.plane
            )
            var targetMode = interaction.session.initialMode
            if let heldContext = adoptedSettle.heldContext,
               interaction.plane?.toMode == heldContext.targetMode
                || heldContext.targetMode == interaction.session.initialMode {
                targetMode = heldContext.targetMode
            }
            return terminalSettleEffects(
                session: interaction.session,
                plane: interaction.plane,
                targetMode: targetMode,
                panDeltaY: interaction.panDeltaY,
                settlesPosition: false,
                usesMenuFallback: adoptedSettle.context?.usesMenuFallback
                    ?? false,
                stopsDisplayLink: false
            )

        case let .settling(settle):
            return settleSynchronously(settle, settlesPosition: false)
        }
    }

    private mutating func settleSynchronously(
        _ settle: SettleState,
        settlesPosition: Bool
    ) -> [Effect] {
        terminalSettleEffects(
            session: settle.session,
            plane: settle.plane,
            targetMode: settle.targetMode,
            panDeltaY: settle.panDeltaY,
            settlesPosition: settlesPosition,
            usesMenuFallback: settle.usesMenuFallback,
            stopsDisplayLink: true
        )
    }

    private mutating func handleRendererSuccess(
        _ action: PendingRendererAction
    ) -> [Effect] {
        state = .idle
        return terminalEffects(
            for: action.session,
            committedMode: action.mode,
            settlesPosition: action.settlesPosition
                && !action.wasInterrupted
        )
    }

    private mutating func handleRendererFailure(
        _ action: PendingRendererAction
    ) -> [Effect] {
        let effectiveSettlesPosition = action.settlesPosition
            && !action.wasInterrupted
        if action.retriesWithDirectMode,
           action.mode != action.session.initialMode {
            let applyMode = beginDirectModeApplication(
                session: action.session,
                mode: action.mode,
                settlesPosition: action.settlesPosition,
                wasInterrupted: action.wasInterrupted
            )
            return [.resetRenderer, applyMode]
        }
        state = .idle
        return [.resetRenderer] + terminalEffects(
            for: action.session,
            settlesPosition: effectiveSettlesPosition
        )
    }

    private mutating func handleRendererFailure() -> [Effect] {
        switch state {
        case .idle:
            return []

        case .tracking:
            state = .idle
            return []

        case let .interacting(interaction):
            let adoptedSettle = interaction.adoptedSettlePhase.resolve(
                scale: interaction.scale,
                plane: interaction.plane
            )
            // The adopted menu selection still owns the visual handoff while
            // its plane retains progress, so renderer recovery must preserve
            // the same target as a normal release.
            if let context = adoptedSettle.releaseContext,
               context.usesMenuFallback,
               context.targetMode != interaction.session.initialMode {
                return [.resetRenderer, beginDirectModeApplication(
                    session: interaction.session,
                    mode: context.targetMode,
                    settlesPosition: true
                )]
            }
            state = .idle
            return [.resetRenderer] + terminalEffects(
                for: interaction.session,
                settlesPosition: true
            )

        case let .settling(settle):
            if settle.usesMenuFallback, settle.commits {
                return [
                    .stopDisplayLink,
                    .resetRenderer,
                    beginDirectModeApplication(
                        session: settle.session,
                        mode: settle.targetMode,
                        settlesPosition: true
                    )
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

        case .awaitingRenderer:
            preconditionFailure("Awaiting renderer failures are handled before event dispatch")
        }
    }

    private mutating func beginDirectModeApplication(
        session: Session,
        mode: MobileCollectionBrowserGridMode,
        settlesPosition: Bool,
        wasInterrupted: Bool = false
    ) -> Effect {
        state = .awaitingRenderer(PendingRendererAction(
            session: session,
            mode: mode,
            settlesPosition: settlesPosition,
            retriesWithDirectMode: false,
            wasInterrupted: wasInterrupted
        ))
        return .applyMode(mode)
    }

    /// `committedMode` is the mode the renderer acknowledged; it is nil or
    /// `session.initialMode` on paths that end the interaction where it
    /// started.
    private func terminalEffects(
        for session: Session,
        committedMode: MobileCollectionBrowserGridMode? = nil,
        settlesPosition: Bool
    ) -> [Effect] {
        var effects = [Effect]()
        if let committedMode, committedMode != session.initialMode {
            effects.append(.persistMode(committedMode))
            effects.append(.reconcileMedia(
                cancelsPrefetchLoads:
                    session.initialMode.requiredImageQuality
                        != committedMode.requiredImageQuality
            ))
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
