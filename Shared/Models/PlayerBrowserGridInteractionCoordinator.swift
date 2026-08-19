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
        /// Monotonic recognizer time used to distinguish motion from a dwell.
        let timestamp: TimeInterval
    }

    private struct ScaleSample: Equatable {
        let logScale: CGFloat
        let timestamp: TimeInterval
    }

    private struct ReleaseMotionSamples: Equatable {
        var values: [ScaleSample] = []
        var lastObservedTimestamp: TimeInterval?

        mutating func record(scale: CGFloat, timestamp: TimeInterval) {
            guard scale.isFinite, scale > 0, timestamp.isFinite else { return }
            if let lastObservedTimestamp {
                guard timestamp >= lastObservedTimestamp else { return }
                if timestamp == lastObservedTimestamp,
                   values.last?.timestamp == timestamp {
                    values.removeLast()
                } else if timestamp > lastObservedTimestamp {
                    compactValues()
                }
            }
            lastObservedTimestamp = timestamp
            let value = ScaleSample(
                logScale: log(max(scale, 0.000_1)),
                timestamp: timestamp
            )
            guard values.last.map({
                abs(value.logScale - $0.logScale)
                    > PlayerBrowserGridPinchPolicy
                        .releaseMotionLogScaleNoiseFloor
            }) ?? true else { return }
            values.append(value)
        }

        private mutating func compactValues() {
            guard let newest = values.last else { return }
            let horizon = newest.timestamp
                - PlayerBrowserGridPinchPolicy.releaseMotionRateWindow * 1.5
            values.removeAll { $0.timestamp < horizon }
            if values.count > 12 {
                values.removeFirst(values.count - 12)
            }
        }

        func logScaleRate(at releaseTime: TimeInterval) -> CGFloat {
            guard let lastObservedTimestamp,
                  releaseTime >= lastObservedTimestamp,
                  let newest = values.last else { return 0 }
            let newestAge = releaseTime - newest.timestamp
            guard newestAge.isFinite,
                  (0...PlayerBrowserGridPinchPolicy.releaseMotionHoldTimeout)
                    .contains(newestAge),
                  let firstIndex = values.firstIndex(where: {
                      newest.timestamp - $0.timestamp
                          <= PlayerBrowserGridPinchPolicy.releaseMotionRateWindow
                  }),
                  firstIndex < values.count - 1 else {
                return 0
            }

            var direction: FloatingPointSign?
            var reference = values[firstIndex]
            var previous = reference
            for sample in values[(firstIndex + 1)...] {
                let delta = sample.logScale - previous.logScale
                if direction != delta.sign {
                    reference = previous
                    direction = delta.sign
                }
                previous = sample
            }

            let deltaTime = CGFloat(newest.timestamp - reference.timestamp)
            guard deltaTime > 0.000_5 else { return 0 }
            return (newest.logScale - reference.logScale) / deltaTime
        }
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
            scale: CGFloat,
            reduceMotion: Bool,
            timestamp: TimeInterval
        )
        case pinchCancelled(reduceMotion: Bool)
        case settleStarted(timestamp: TimeInterval)
        case interactionFadeTick(timestamp: TimeInterval)
        case settleTick(timestamp: TimeInterval)
        case rendererSucceeded
        case interrupt
        case rendererFailed
    }

    enum Effect: Equatable {
        case beginInteraction
        case coverPlaneChange
        case installPlane(Plane)
        case renderZoom(planeId: UUID?, scale: CGFloat, panDeltaY: CGFloat)
        case renderSettle(
            id: UUID,
            scale: CGFloat,
            settleProgress: CGFloat,
            presentationProgress: CGFloat,
            panDeltaY: CGFloat
        )
        case renderInteractionFade(id: UUID, presentationProgress: CGFloat)
        case commitPlane(id: UUID, mode: MobileCollectionBrowserGridMode)
        case discardPlane(id: UUID)
        case applyMode(MobileCollectionBrowserGridMode)
        case selectionHaptic
        case startDisplayLink
        case stopDisplayLink
        case startInteractionFadeTicks
        case stopInteractionFadeTicks
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

        func nearestTarget(
            logScale: CGFloat,
            renderScale: CGFloat,
            denser: Bool
        ) -> ModeRatio? {
            modeRatios
                .lazy
                .filter {
                    denser
                        ? $0.itemWidthRatio < 1
                            && $0.itemWidthRatio <= renderScale
                        : $0.itemWidthRatio > 1
                }
                .min { lhs, rhs in
                    abs(logScale - log(lhs.itemWidthRatio))
                        < abs(logScale - log(rhs.itemWidthRatio))
                }
        }

        /// The rendered scale a settle onto `mode` comes to rest at.
        /// `makeModeRatios` pins `initialMode` to exactly 1, so the fallback
        /// only covers a mode that never entered the session.
        func scale(landingOn mode: MobileCollectionBrowserGridMode) -> CGFloat {
            ratio(for: mode) ?? 1
        }
    }

    private struct TrackingState: Equatable {
        let session: Session
        var centroidY: CGFloat
        var releaseMotionSamples = ReleaseMotionSamples()
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
            let preservesAdoptedProgress: Bool
            var handoffTargetProgress: CGFloat? = nil
            var handoffProgress: CGFloat = 0

            /// Holds the adopted frame through the dead zone, then blends it
            /// toward the direct endpoint for the current adjustment direction.
            func renderedProgress(direct: CGFloat) -> CGFloat {
                guard preservesAdoptedProgress, let context else {
                    return direct
                }
                guard handoffProgress < 1 else { return direct }
                guard let handoffTargetProgress else {
                    return context.progressAtAdoption
                }
                return PlayerBrowserGridCrossfade.sanitizedProgress(
                    context.progressAtAdoption
                        + (handoffTargetProgress - context.progressAtAdoption)
                            * handoffProgress
                )
            }

            var releaseContext: AdoptedSettleContext? {
                if let heldContext { return heldContext }
                return retainsPlane ? context : nil
            }

            var pinsPlane: Bool {
                heldContext != nil || retainsPlane
            }

            private var retainsPlane: Bool {
                guard preservesAdoptedProgress, let context else {
                    return false
                }
                return context.progressAtAdoption * (1 - handoffProgress) > 0
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
                    preservesAdoptedProgress: false
                )

            case let .holding(context):
                return Resolution(
                    context: context,
                    heldContext: context,
                    preservesAdoptedProgress:
                        plane?.id == context.planeIdAtAdoption
                )

            case let .adjusted(context):
                guard let plane,
                      plane.id == context.planeIdAtAdoption else {
                    return Resolution(
                        context: context,
                        heldContext: nil,
                        preservesAdoptedProgress: false
                    )
                }
                let scaleDeviation = abs(scale / context.scaleAtAdoption - 1)
                guard scaleDeviation.isFinite else {
                    return Resolution(
                        context: context,
                        heldContext: nil,
                        preservesAdoptedProgress: false
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
                let handedOff = min(handoffProgress, 1)
                let endpointScale = context.scaleAtAdoption * (
                    scale < context.scaleAtAdoption
                        ? 1 - PlayerBrowserGridPinchPolicy
                            .activationScaleDeviation
                        : 1 + PlayerBrowserGridPinchPolicy
                            .activationScaleDeviation
                )
                return Resolution(
                    context: context,
                    heldContext: nil,
                    preservesAdoptedProgress: true,
                    handoffTargetProgress:
                        PlayerBrowserGridInteractionCoordinator
                            .crossfadeProgress(
                                scale: endpointScale,
                                plane: plane
                            ),
                    handoffProgress: handedOff
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
        var plane: Plane?
        var adoptedSettlePhase: AdoptedSettlePhase
        var presentationProgressMap: PresentationProgressMap?
        var lastPresentationProgress: CGFloat
        /// Seconds the current plane has been alive, advanced by interaction
        /// fade ticks; drives the Photos time channel of the crossfade.
        var fadeClockElapsed: CGFloat = 0
        var lastFadeTickTime: TimeInterval?
        var releaseMotionSamples = ReleaseMotionSamples()

        func presentationProgress(
            for geometryProgress: CGFloat,
            handoffProgress: CGFloat
        ) -> CGFloat {
            presentationProgressMap?.progress(
                for: geometryProgress,
                handoffProgress: handoffProgress
            ) ?? PlayerBrowserGridCrossfade.sanitizedProgress(
                geometryProgress
            )
        }
    }

    private struct PresentationProgressMap: Equatable {
        private enum EndpointBehavior: Equatable {
            case preserveAnchor
            case normalizeThroughHandoff
        }

        private let anchorGeometryProgress: CGFloat
        private let anchorPresentationProgress: CGFloat
        private let endpointBehavior: EndpointBehavior

        private init(
            geometryProgress: CGFloat,
            presentationProgress: CGFloat,
            endpointBehavior: EndpointBehavior
        ) {
            let geometryProgress = PlayerBrowserGridCrossfade
                .sanitizedProgress(geometryProgress)
            anchorGeometryProgress = geometryProgress
            self.endpointBehavior = endpointBehavior
            anchorPresentationProgress = PlayerBrowserGridCrossfade
                .sanitizedProgress(presentationProgress)
        }

        static func liveRetarget(
            geometryProgress: CGFloat,
            presentationProgress: CGFloat
        ) -> Self {
            Self(
                geometryProgress: geometryProgress,
                presentationProgress: presentationProgress,
                endpointBehavior: .preserveAnchor
            )
        }

        static func adoptingSettle(
            geometryProgress: CGFloat,
            presentationProgress: CGFloat
        ) -> Self {
            Self(
                geometryProgress: geometryProgress,
                presentationProgress: presentationProgress,
                endpointBehavior: .normalizeThroughHandoff
            )
        }

        func progress(
            for geometryProgress: CGFloat,
            handoffProgress: CGFloat
        ) -> CGFloat {
            let geometryProgress = PlayerBrowserGridCrossfade
                .sanitizedProgress(geometryProgress)
            let preservedProgress = mappedProgress(
                for: geometryProgress,
                anchorPresentationProgress: anchorPresentationProgress
            )
            guard endpointBehavior == .normalizeThroughHandoff else {
                return preservedProgress
            }
            let normalizedAnchorProgress: CGFloat
            if anchorGeometryProgress <= 0 {
                normalizedAnchorProgress = 0
            } else if anchorGeometryProgress >= 1 {
                normalizedAnchorProgress = 1
            } else {
                return preservedProgress
            }
            guard normalizedAnchorProgress != anchorPresentationProgress else {
                return preservedProgress
            }
            let normalizedProgress = mappedProgress(
                for: geometryProgress,
                anchorPresentationProgress: normalizedAnchorProgress
            )
            let handoffProgress = PlayerBrowserGridCrossfade
                .sanitizedProgress(handoffProgress)
            let blendedProgress = PlayerBrowserGridCrossfade.sanitizedProgress(
                preservedProgress
                    + (normalizedProgress - preservedProgress)
                        * handoffProgress
            )
            guard geometryProgress < anchorGeometryProgress else {
                return blendedProgress
            }
            return min(blendedProgress, anchorPresentationProgress)
        }

        private func mappedProgress(
            for geometryProgress: CGFloat,
            anchorPresentationProgress: CGFloat
        ) -> CGFloat {
            if geometryProgress <= anchorGeometryProgress {
                guard anchorGeometryProgress > 0 else {
                    return anchorPresentationProgress
                }
                return anchorPresentationProgress
                    * geometryProgress / anchorGeometryProgress
            }
            guard anchorGeometryProgress < 1 else {
                return anchorPresentationProgress
            }
            return anchorPresentationProgress
                + (1 - anchorPresentationProgress)
                    * (geometryProgress - anchorGeometryProgress)
                    / (1 - anchorGeometryProgress)
        }
    }

    private enum PlaneDecision {
        case keep
        case replace(ModeRatio)
        case discard
    }

    private struct SettleProgressSpring: Equatable {
        var offset: CGFloat
        var velocity: CGFloat = 0

        var isAtRest: Bool {
            PlayerBrowserGridPinchPolicy.isSettleSpringAtRest(
                logOffset: offset,
                logVelocity: velocity
            )
        }

        mutating func advance(deltaTime: CGFloat) {
            let stepped = PlayerBrowserGridPinchPolicy.settleSpringStep(
                logOffset: offset,
                logVelocity: velocity,
                deltaTime: deltaTime
            )
            offset = stepped.logOffset
            velocity = stepped.logVelocity
        }

        func progress(commits: Bool) -> CGFloat {
            PlayerBrowserGridCrossfade.sanitizedProgress(
                (commits ? 1 : 0) + offset
            )
        }
    }

    private struct SettleState: Equatable {
        let session: Session
        let plane: Plane?
        let targetMode: MobileCollectionBrowserGridMode
        let initialLogDistance: CGFloat
        let initialProgress: CGFloat
        let initialPresentationProgress: CGFloat
        let panDeltaY: CGFloat
        var logOffset: CGFloat
        var logVelocity: CGFloat
        var settleProgressSpring: SettleProgressSpring? = nil
        var presentationSpring: SettleProgressSpring? = nil
        var fadeClockElapsed: CGFloat = 0
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
            if let settleProgressSpring {
                return settleProgressSpring.progress(commits: commits)
            }
            return advancedProgress(from: initialProgress)
        }

        var currentPresentationProgress: CGFloat {
            if let presentationSpring {
                return presentationSpring.progress(commits: commits)
            }
            return advancedProgress(from: initialPresentationProgress)
        }

        var presentationSpringIsAtRest: Bool {
            presentationSpring?.isAtRest ?? true
        }

        var settleProgressSpringIsAtRest: Bool {
            settleProgressSpring?.isAtRest ?? true
        }

        private func advancedProgress(from initial: CGFloat) -> CGFloat {
            guard initialLogDistance > 0 else { return commits ? 1 : 0 }
            return commits
                ? initial + (1 - initial) * travelProgress
                : initial * (1 - travelProgress)
        }

        private var travelProgress: CGFloat {
            min(max(1 - abs(logOffset) / initialLogDistance, 0), 1)
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
        case tracking(TrackingState)
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

        case let .pinchEnded(scale, reduceMotion, timestamp):
            return handlePinchEnded(
                scale: scale,
                reduceMotion: reduceMotion,
                timestamp: timestamp
            )

        case let .pinchCancelled(reduceMotion):
            return handlePinchCancelled(reduceMotion: reduceMotion)

        case let .settleStarted(timestamp):
            return handleSettleStarted(timestamp: timestamp)

        case let .interactionFadeTick(timestamp):
            return handleInteractionFadeTick(timestamp: timestamp)

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
            initialPresentationProgress: 0,
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
                presentationProgress: 0,
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
            var tracking = TrackingState(
                session: Session(
                    initialMode: currentMode,
                    modeRatios: Self.makeModeRatios(
                        fromMode: currentMode,
                        provided: ratioProvider(currentMode)
                    )
                ),
                centroidY: sample.centroidY
            )
            tracking.releaseMotionSamples.record(
                scale: sample.scale,
                timestamp: sample.timestamp
            )
            state = .tracking(tracking)
            return []

        case let .settling(settle):
            let presentationProgress = settle.currentPresentationProgress
            let referenceScale = sample.scale / settle.currentScale
            guard settle.currentScale.isFinite,
                  settle.currentScale > 0,
                  referenceScale.isFinite,
                  referenceScale > 0 else {
                return []
            }
            var interaction = InteractionState(
                session: settle.session,
                referenceScale: referenceScale,
                referenceCentroidY: sample.centroidY,
                basePanDeltaY: settle.panDeltaY,
                panDeltaY: settle.panDeltaY,
                scale: settle.currentScale,
                activationAdjustment: 1,
                plane: settle.plane,
                adoptedSettlePhase: .holding(AdoptedSettleContext(
                    targetMode: settle.targetMode,
                    usesMenuFallback: settle.usesMenuFallback,
                    planeIdAtAdoption: settle.plane?.id,
                    scaleAtAdoption: settle.currentScale,
                    progressAtAdoption: settle.currentProgress
                )),
                presentationProgressMap: PresentationProgressMap.adoptingSettle(
                    geometryProgress: settle.currentProgress,
                    presentationProgress: presentationProgress
                ),
                lastPresentationProgress: presentationProgress,
                fadeClockElapsed: min(
                    settle.fadeClockElapsed,
                    PlayerBrowserGridPinchPolicy.interactionFadeElapsed(
                        matchingProgress: presentationProgress
                    )
                )
            )
            interaction.releaseMotionSamples.record(
                scale: sample.scale,
                timestamp: sample.timestamp
            )
            state = .interacting(interaction)
            // `beginInteraction` states that the pinch owns the grid again.
            // The renderer session is already live, but the settle handed
            // scrolling back and only this reclaims it.
            guard settle.plane != nil else {
                return [.stopDisplayLink, .beginInteraction]
            }
            return [
                .stopDisplayLink,
                .beginInteraction,
                .startInteractionFadeTicks
            ]

        case .tracking, .interacting, .awaitingRenderer:
            return []
        }
    }

    private mutating func handlePinchChanged(_ sample: PinchSample) -> [Effect] {
        guard isValid(sample: sample) else { return [] }

        switch state {
        case var .tracking(tracking):
            // The tracking scale is the recognizer's own cumulative ratio —
            // `handlePinchBegan` deliberately does not rebase it.
            tracking.centroidY = sample.centroidY
            tracking.releaseMotionSamples.record(
                scale: sample.scale,
                timestamp: sample.timestamp
            )
            guard var interaction = interaction(
                activating: tracking,
                scale: sample.scale
            ) else {
                state = .tracking(tracking)
                return []
            }
            var effects = [Effect.beginInteraction]
            effects += zoomEffects(interaction: &interaction)
            state = .interacting(interaction)
            return effects

        case var .interacting(interaction):
            let effectiveScale = sample.scale / interaction.referenceScale
            guard effectiveScale.isFinite, effectiveScale > 0 else { return [] }
            interaction.scale = effectiveScale
            interaction.panDeltaY = interaction.basePanDeltaY
                + sample.centroidY
                - interaction.referenceCentroidY
            interaction.adoptedSettlePhase.registerScale(effectiveScale)
            interaction.releaseMotionSamples.record(
                scale: sample.scale,
                timestamp: sample.timestamp
            )
            let effects = zoomEffects(interaction: &interaction)
            state = .interacting(interaction)
            return effects

        case .idle, .settling, .awaitingRenderer:
            return []
        }
    }

    private func interaction(
        activating tracking: TrackingState,
        scale: CGFloat
    ) -> InteractionState? {
        guard scale.isFinite,
              scale > 0,
              abs(scale - 1)
                > PlayerBrowserGridPinchPolicy.activationScaleDeviation else {
            return nil
        }
        let effectiveScale = PlayerBrowserGridPinchPolicy
            .effectiveScaleAfterActivation(scale)
        var interaction = InteractionState(
            session: tracking.session,
            referenceScale: scale / effectiveScale,
            referenceCentroidY: tracking.centroidY,
            basePanDeltaY: 0,
            panDeltaY: 0,
            scale: effectiveScale,
            activationAdjustment: PlayerBrowserGridPinchPolicy
                .activationTrimDivisor(scale),
            plane: nil,
            adoptedSettlePhase: .none,
            presentationProgressMap: nil,
            lastPresentationProgress: 0
        )
        interaction.releaseMotionSamples = tracking.releaseMotionSamples
        return interaction
    }

    private func zoomEffects(interaction: inout InteractionState) -> [Effect] {
        var effects = [Effect]()
        var geometryPresentationBeforePlaneChanges: CGFloat?
        let renderScale = PlayerBrowserGridPinchPolicy.rubberBandedScale(
            interaction.scale,
            minimumRatio: interaction.session.minimumRatio,
            maximumRatio: interaction.session.maximumRatio
        )
        let previousPlane = interaction.plane
        let adoptedSettle = interaction.adoptedSettlePhase.resolve(
            scale: interaction.scale,
            plane: previousPlane
        )
        let planeWouldUnderfillViewport = previousPlane.map {
            renderScale < min($0.itemWidthRatio, 1)
        } ?? false
        // A held adopted settle owns the plane until the pinch actually
        // moves: the release still commits its target, so retargeting
        // under it renders a frame on a lattice nothing will land on and costs
        // two extra grid rebuilds. A plane that would underfill the viewport
        // loses that pin: coverage outranks the adopted settle.
        let decision = adoptedSettle.pinsPlane
            && !planeWouldUnderfillViewport
            ? PlaneDecision.keep
            : planeDecision(
                scale: interaction.scale,
                renderScale: renderScale,
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
                if previousPlane != nil {
                    geometryPresentationBeforePlaneChanges = interaction
                        .presentationProgress(
                            for: adoptedSettle.renderedProgress(
                                direct: Self.crossfadeProgress(
                                    scale: renderScale,
                                    plane: previousPlane
                                )
                            ),
                            handoffProgress: adoptedSettle.handoffProgress
                        )
                    effects.append(.coverPlaneChange)
                }
                interaction.plane = plane
                interaction.adoptedSettlePhase = .none
                interaction.fadeClockElapsed = 0
                interaction.lastFadeTickTime = nil
                effects.append(.installPlane(plane))
                effects.append(.startInteractionFadeTicks)
            }

        case .discard:
            if let plane = interaction.plane {
                effects.append(.coverPlaneChange)
                interaction.plane = nil
                interaction.adoptedSettlePhase = .none
                interaction.presentationProgressMap = nil
                interaction.lastPresentationProgress = 0
                interaction.fadeClockElapsed = 0
                interaction.lastFadeTickTime = nil
                effects.append(.discardPlane(id: plane.id))
                effects.append(.stopInteractionFadeTicks)
            }
        }

        // The destination crossfades in during the pinch, not on release. An
        // adopted settle hands its progress over to the live pinch across the
        // activation travel, so grabbing a running settle neither replays the
        // fade from zero nor snaps when the handoff completes.
        if let plane = interaction.plane {
            let renderingSettle = interaction.adoptedSettlePhase.resolve(
                scale: interaction.scale,
                plane: plane
            )
            let settleProgress = renderingSettle.renderedProgress(
                direct: Self.crossfadeProgress(
                    scale: renderScale,
                    plane: plane
                )
            )
            if let geometryPresentationBeforePlaneChanges {
                interaction.presentationProgressMap = .liveRetarget(
                    geometryProgress: settleProgress,
                    presentationProgress:
                        geometryPresentationBeforePlaneChanges
                )
            }
            let presentationProgress = max(
                interaction.presentationProgress(
                    for: settleProgress,
                    handoffProgress: renderingSettle.handoffProgress
                ),
                PlayerBrowserGridPinchPolicy.interactionFadeTimeProgress(
                    elapsed: interaction.fadeClockElapsed
                )
            )
            interaction.lastPresentationProgress = presentationProgress
            effects.append(.renderSettle(
                id: plane.id,
                scale: renderScale,
                settleProgress: settleProgress,
                presentationProgress: presentationProgress,
                panDeltaY: interaction.panDeltaY
            ))
            return effects
        }
        effects.append(.renderZoom(
            planeId: nil,
            scale: renderScale,
            panDeltaY: interaction.panDeltaY
        ))
        return effects
    }

    private static func crossfadeProgress(
        scale: CGFloat,
        plane: Plane?
    ) -> CGFloat {
        guard let plane else { return 0 }
        return PlayerBrowserGridCrossfade.driftProgress(
            forScale: scale,
            itemWidthRatio: plane.itemWidthRatio
        )
    }

    /// Hysteresis prevents synchronous plane rebuilds from churning near a
    /// target threshold.
    private func planeDecision(
        scale: CGFloat,
        renderScale: CGFloat,
        session: Session,
        installedPlane: Plane?
    ) -> PlaneDecision {
        let logScale = log(max(scale, 0.000_1))

        let wantsDenser: Bool
        if let installedPlane {
            let planeIsDenser = installedPlane.itemWidthRatio < 1
            if planeIsDenser,
               renderScale < installedPlane.itemWidthRatio,
               let target = session.nearestTarget(
                   logScale: logScale,
                   renderScale: renderScale,
                   denser: true
               ) {
                return .replace(target)
            }
            let reversesBeyondDiscard = planeIsDenser
                ? scale > PlayerBrowserGridPinchPolicy.underPlaneDiscardScale
                : scale < PlayerBrowserGridPinchPolicy.overPlaneDiscardScale
            guard reversesBeyondDiscard else {
                guard let target = sameDirectionTarget(
                    logScale: logScale,
                    renderScale: renderScale,
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

        guard let target = session.nearestTarget(
            logScale: logScale,
            renderScale: renderScale,
            denser: wantsDenser
        ) else {
            return installedPlane == nil ? .keep : .discard
        }
        return .replace(target)
    }

    /// A continuous pinch that sails past its plane's target re-aims the
    /// plane at the next mode in the same direction, so a deep zoom
    /// crossfades toward the lattice the release will actually land on.
    /// Sparse re-aims where the release ladder commits, so the lattice on
    /// screen is the lattice a release lands on; the scale is biased toward
    /// the installed target by the hysteresis margin so fingers hovering a
    /// boundary cannot churn planes. Dense keeps the nearest coverage-safe
    /// target — a plane must never aim wider than the rendered scale.
    private func sameDirectionTarget(
        logScale: CGFloat,
        renderScale: CGFloat,
        session: Session,
        installedPlane: Plane,
        denser: Bool
    ) -> ModeRatio? {
        guard denser else {
            return ladderTarget(
                logScale: logScale,
                session: session,
                installedPlane: installedPlane
            )
        }
        guard let target = session.nearestTarget(
            logScale: logScale,
            renderScale: renderScale,
            denser: denser
        ), target.mode != installedPlane.toMode else {
            return nil
        }
        let movesTowardLargerDenseCells =
            target.itemWidthRatio > installedPlane.itemWidthRatio
        if movesTowardLargerDenseCells,
           log(renderScale / target.itemWidthRatio)
            <= PlayerBrowserGridPinchPolicy.planeRetargetHysteresis {
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

    private func ladderTarget(
        logScale: CGFloat,
        session: Session,
        installedPlane: Plane
    ) -> ModeRatio? {
        let installedLogRatio = log(installedPlane.itemWidthRatio)
        let biasedLogScale = logScale > installedLogRatio
            ? max(
                logScale
                    - PlayerBrowserGridPinchPolicy.planeRetargetHysteresis,
                installedLogRatio
            )
            : min(
                logScale
                    + PlayerBrowserGridPinchPolicy.planeRetargetHysteresis,
                installedLogRatio
            )
        guard let targetIndex = PlayerBrowserGridPinchPolicy.settleTargetIndex(
            scale: exp(biasedLogScale),
            itemWidthRatios: session.modeRatios.map(\.itemWidthRatio)
        ) else {
            return nil
        }
        let target = session.modeRatios[targetIndex]
        guard target.itemWidthRatio > 1,
              target.mode != installedPlane.toMode else {
            return nil
        }
        return target
    }

    private mutating func handlePinchEnded(
        scale: CGFloat,
        reduceMotion: Bool,
        timestamp: TimeInterval
    ) -> [Effect] {
        switch state {
        case .idle, .awaitingRenderer:
            return []

        case var .tracking(tracking):
            tracking.releaseMotionSamples.record(
                scale: scale,
                timestamp: timestamp
            )
            guard var interaction = interaction(
                activating: tracking,
                scale: scale
            ) else {
                state = .idle
                return []
            }
            var effects = [Effect.beginInteraction]
            effects += zoomEffects(interaction: &interaction)
            return effects + release(
                interaction: interaction,
                reduceMotion: reduceMotion,
                timestamp: timestamp
            )

        case let .settling(settle):
            return settleSynchronously(settle, settlesPosition: true)

        case var .interacting(interaction):
            var scaleChanged = false
            if scale.isFinite, scale > 0 {
                let effectiveScale = scale / interaction.referenceScale
                if effectiveScale.isFinite, effectiveScale > 0 {
                    scaleChanged = effectiveScale != interaction.scale
                    interaction.scale = effectiveScale
                    interaction.adoptedSettlePhase.registerScale(effectiveScale)
                }
            }
            interaction.releaseMotionSamples.record(
                scale: scale,
                timestamp: timestamp
            )
            let effects = scaleChanged
                ? zoomEffects(interaction: &interaction)
                : []
            return effects + release(
                interaction: interaction,
                reduceMotion: reduceMotion,
                timestamp: timestamp
            )
        }
    }

    private mutating func release(
        interaction: InteractionState,
        reduceMotion: Bool,
        timestamp: TimeInterval
    ) -> [Effect] {
        let adoptedSettle = interaction.adoptedSettlePhase.resolve(
            scale: interaction.scale,
            plane: interaction.plane
        )
        let releaseContext = adoptedSettle.releaseContext
        let selectedTargetMode: MobileCollectionBrowserGridMode
        // Do not replace a plane while its adopted cell corrections are
        // still visibly handing off to direct manipulation.
        if let releaseContext {
            selectedTargetMode = releaseContext.targetMode
        } else if let targetIndex = PlayerBrowserGridPinchPolicy
            .settleTargetIndex(
                scale: PlayerBrowserGridPinchPolicy.projectedReleaseScale(
                    scale: interaction.scale
                        * interaction.activationAdjustment,
                    logScaleRate: interaction.releaseMotionSamples
                        .logScaleRate(at: timestamp),
                    itemWidthRatios: interaction.session.modeRatios.map(
                        \.itemWidthRatio
                    )
                ),
                itemWidthRatios: interaction.session.modeRatios.map(
                    \.itemWidthRatio
                )
            ) {
            selectedTargetMode = interaction.session
                .modeRatios[targetIndex].mode
        } else {
            selectedTargetMode = interaction.session.initialMode
        }
        let targetMode = releaseTargetMode(
            selectedTargetMode,
            interaction: interaction,
            adoptedSettle: adoptedSettle
        )
        return beginSettle(
            interaction: interaction,
            targetMode: targetMode,
            reduceMotion: reduceMotion,
            usesMenuFallback: releaseContext?.usesMenuFallback ?? false,
            adoptedSettle: adoptedSettle
        )
    }

    private func releaseTargetMode(
        _ selectedTargetMode: MobileCollectionBrowserGridMode,
        interaction: InteractionState,
        adoptedSettle: AdoptedSettlePhase.Resolution
    ) -> MobileCollectionBrowserGridMode {
        guard selectedTargetMode != interaction.session.initialMode,
              var selectedRatio = interaction.session.ratio(
                  for: selectedTargetMode
              ) else {
            return selectedTargetMode
        }
        let renderScale = PlayerBrowserGridPinchPolicy.rubberBandedScale(
            interaction.scale,
            minimumRatio: interaction.session.minimumRatio,
            maximumRatio: interaction.session.maximumRatio
        )
        var coverageSafeTargetMode = selectedTargetMode
        if selectedRatio > 1, renderScale < 1 {
            return interaction.session.initialMode
        }
        if selectedRatio < 1, selectedRatio > renderScale,
           let coverageSafeTarget = interaction.session.nearestTarget(
               logScale: log(interaction.scale),
               renderScale: renderScale,
               denser: true
           ) {
            coverageSafeTargetMode = coverageSafeTarget.mode
            selectedRatio = coverageSafeTarget.itemWidthRatio
        }
        guard let plane = interaction.plane,
              plane.toMode != coverageSafeTargetMode,
              (selectedRatio > 1) == (plane.itemWidthRatio > 1),
              abs(log(selectedRatio)) > abs(log(plane.itemWidthRatio)) else {
            return coverageSafeTargetMode
        }
        let renderedProgress = adoptedSettle.renderedProgress(
            direct: Self.crossfadeProgress(scale: renderScale, plane: plane)
        )
        return renderedProgress > 0 ? plane.toMode : coverageSafeTargetMode
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
                reduceMotion: reduceMotion,
                usesMenuFallback: cancellationContext?.usesMenuFallback ?? false,
                adoptedSettle: adoptedSettle
            )
        }
    }

    private mutating func beginSettle(
        interaction: InteractionState,
        targetMode: MobileCollectionBrowserGridMode,
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
        var fadeClockElapsed = interaction.fadeClockElapsed
        var replacementInitialProgress: CGFloat?
        let initialPresentationProgress = interaction.lastPresentationProgress
        let fromScale = PlayerBrowserGridPinchPolicy.rubberBandedScale(
            interaction.scale,
            minimumRatio: session.minimumRatio,
            maximumRatio: session.maximumRatio
        )

        // A plane already aimed at `targetMode` was built from that mode's
        // ratio, so reaching it here means the lookup below cannot fail.
        if commits, plane?.toMode != targetMode {
            let replacesLivePlane = plane != nil
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
            fadeClockElapsed = 0
            let initialProgress = Self.crossfadeProgress(
                scale: fromScale,
                plane: installedPlane
            )
            replacementInitialProgress = initialProgress
            if replacesLivePlane {
                effects.append(.coverPlaneChange)
            }
            effects.append(.installPlane(installedPlane))
            effects.append(.renderSettle(
                id: installedPlane.id,
                scale: fromScale,
                settleProgress: initialProgress,
                presentationProgress: initialPresentationProgress,
                panDeltaY: interaction.panDeltaY
            ))
        }
        let logOffset = log(fromScale / session.scale(landingOn: targetMode))
        let geometryIsAtRest = abs(logOffset)
            <= PlayerBrowserGridPinchPolicy.settleRestLogDistance
        // Resume whatever the last pinch frame rendered, never replay from
        // zero: the same adopted-settle blend, over the same plane.
        let initialProgress: CGFloat
        if let replacementInitialProgress {
            initialProgress = replacementInitialProgress
        } else if plane?.id == interaction.plane?.id
            || plane?.id == adoptedSettle.context?.planeIdAtAdoption {
            initialProgress = adoptedSettle.renderedProgress(
                direct: Self.crossfadeProgress(scale: fromScale, plane: plane)
            )
        } else {
            initialProgress = 0
        }
        let terminalSettleProgress: CGFloat = commits ? 1 : 0
        let settleProgressSpringOffset = initialProgress
            - terminalSettleProgress
        let terminalPresentationProgress: CGFloat = commits ? 1 : 0
        let presentationSpringOffset = initialPresentationProgress
            - terminalPresentationProgress
        let directProgress = Self.crossfadeProgress(
            scale: fromScale,
            plane: plane
        )
        let progressRestDistance = PlayerBrowserGridPinchPolicy
            .settleRestLogDistance
        let needsSettleProgressSpring = plane != nil
            && abs(settleProgressSpringOffset) > progressRestDistance
            && (geometryIsAtRest
                || abs(initialProgress - directProgress)
                    > progressRestDistance)
        let needsPresentationSpring = plane != nil
            && abs(presentationSpringOffset) > progressRestDistance
            && (geometryIsAtRest
                || abs(initialPresentationProgress - directProgress)
                    > progressRestDistance)
        let needsEndpointProgressSettle = needsSettleProgressSpring
            || needsPresentationSpring
        if reduceMotion || (geometryIsAtRest && !needsEndpointProgressSettle) {
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

        state = .settling(SettleState(
            session: session,
            plane: plane,
            targetMode: targetMode,
            initialLogDistance: geometryIsAtRest ? 0 : abs(logOffset),
            initialProgress: initialProgress,
            initialPresentationProgress: initialPresentationProgress,
            panDeltaY: interaction.panDeltaY,
            logOffset: geometryIsAtRest ? 0 : logOffset,
            logVelocity: 0,
            settleProgressSpring: needsSettleProgressSpring
                ? SettleProgressSpring(offset: settleProgressSpringOffset)
                : nil,
            presentationSpring: needsPresentationSpring
                ? SettleProgressSpring(offset: presentationSpringOffset)
                : nil,
            fadeClockElapsed: fadeClockElapsed,
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
                presentationProgress: 1,
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

        if plane != nil {
            effects.append(.coverPlaneChange)
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

    private mutating func handleInteractionFadeTick(
        timestamp: TimeInterval
    ) -> [Effect] {
        guard case var .interacting(interaction) = state else { return [] }
        guard interaction.plane != nil else {
            interaction.lastFadeTickTime = nil
            state = .interacting(interaction)
            return [.stopInteractionFadeTicks]
        }
        let tickTime = sanitizedTimestamp(timestamp)
        let deltaTime = CGFloat(
            max(tickTime - (interaction.lastFadeTickTime ?? tickTime), 0)
        )
        interaction.lastFadeTickTime = tickTime
        guard PlayerBrowserGridPinchPolicy.interactionFadeTimeProgress(
            elapsed: interaction.fadeClockElapsed
        ) < 1 else {
            state = .interacting(interaction)
            return [.stopInteractionFadeTicks]
        }
        interaction.fadeClockElapsed += deltaTime
        let presentationProgress = max(
            interaction.lastPresentationProgress,
            PlayerBrowserGridPinchPolicy.interactionFadeTimeProgress(
                elapsed: interaction.fadeClockElapsed
            )
        )
        let previousPresentationProgress = interaction.lastPresentationProgress
        interaction.lastPresentationProgress = presentationProgress
        state = .interacting(interaction)
        guard presentationProgress != previousPresentationProgress,
              let plane = interaction.plane else {
            return []
        }
        return [.renderInteractionFade(
            id: plane.id,
            presentationProgress: presentationProgress
        )]
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
        settle.fadeClockElapsed = min(
            settle.fadeClockElapsed + deltaTime,
            PlayerBrowserGridPinchPolicy.interactionFadeDuration
        )
        let stepped = PlayerBrowserGridPinchPolicy.settleSpringStep(
            logOffset: settle.logOffset,
            logVelocity: settle.logVelocity,
            deltaTime: deltaTime
        )
        settle.logOffset = stepped.logOffset
        settle.logVelocity = stepped.logVelocity
        settle.settleProgressSpring?.advance(deltaTime: deltaTime)
        settle.presentationSpring?.advance(deltaTime: deltaTime)
        if PlayerBrowserGridPinchPolicy.isSettleSpringAtRest(
            logOffset: settle.logOffset,
            logVelocity: settle.logVelocity
        ) && settle.settleProgressSpringIsAtRest
            && settle.presentationSpringIsAtRest {
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
           settle.commits || settle.currentProgress > 0
               || settle.currentPresentationProgress > 0 {
            return [.renderSettle(
                id: plane.id,
                scale: settle.currentScale,
                settleProgress: settle.currentProgress,
                presentationProgress: settle.currentPresentationProgress,
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
            && sample.timestamp.isFinite
    }

    private func sanitizedTimestamp(_ timestamp: TimeInterval) -> TimeInterval {
        timestamp.isFinite ? timestamp : 0
    }
}
