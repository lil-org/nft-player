// ∅ 2026 lil org

import CoreGraphics
import Foundation

nonisolated struct PlayerBrowserGridTransitionRuntime: Sendable {
    typealias Coordinator = PlayerBrowserGridInteractionCoordinator
    typealias InteractionEffect = Coordinator.Effect

    struct Configuration: Equatable, Sendable {
        let coverFadeDuration: TimeInterval
        let coverRemovalGrace: TimeInterval
        let rendererFadeDuration: TimeInterval
        let firstImageFadeWindow: TimeInterval

        init(
            coverFadeDuration: TimeInterval = 0.25,
            coverRemovalGrace: TimeInterval = 0.05,
            rendererFadeDuration: TimeInterval = 0.12,
            firstImageFadeWindow: TimeInterval = 1.5
        ) {
            self.coverFadeDuration = Self.duration(coverFadeDuration)
            self.coverRemovalGrace = Self.duration(coverRemovalGrace)
            self.rendererFadeDuration = Self.duration(rendererFadeDuration)
            self.firstImageFadeWindow = Self.duration(firstImageFadeWindow)
        }

        private static func duration(_ value: TimeInterval) -> TimeInterval {
            value.isFinite ? max(value, 0) : 0
        }
    }

    struct PinchFrame: Equatable, Sendable {
        let sample: Coordinator.PinchSample
        let viewLocation: CGPoint

        init(sample: Coordinator.PinchSample, viewLocation: CGPoint) {
            self.sample = sample
            self.viewLocation = viewLocation
        }

        init(
            scale: CGFloat,
            viewLocation: CGPoint,
            timestamp: TimeInterval
        ) {
            self.init(
                sample: Coordinator.PinchSample(
                    scale: scale,
                    centroidY: viewLocation.y,
                    timestamp: timestamp
                ),
                viewLocation: viewLocation
            )
        }
    }

    struct Cover: Equatable, Sendable {
        typealias Generation = UInt64

        let generation: Generation
        let installedAt: TimeInterval
        var contentOffset: CGPoint
        var removalDeadline: TimeInterval?

        var id: Generation {
            generation
        }
    }

    struct Output: Equatable, Sendable {
        var effects: [InteractionEffect] = []
        var appliedPinchFrame: PinchFrame?
        var expiredCoverGeneration: Cover.Generation?

        var expiredCoverID: Cover.Generation? {
            expiredCoverGeneration
        }

        var isEmpty: Bool {
            effects.isEmpty
                && appliedPinchFrame == nil
                && expiredCoverGeneration == nil
        }

        mutating func append(_ other: Self) {
            effects += other.effects
            if let appliedPinchFrame = other.appliedPinchFrame {
                self.appliedPinchFrame = appliedPinchFrame
            }
            if let expiredCoverGeneration = other.expiredCoverGeneration {
                self.expiredCoverGeneration = expiredCoverGeneration
            }
        }
    }

    private let configuration: Configuration
    private var coordinator: Coordinator
    private var pendingPinchFrame: PinchFrame?
    private var settleFramesRequested = false
    private var interactionFadeFramesRequested = false
    private var coverGeneration: Cover.Generation = 0
    private(set) var activeCover: Cover?
    private var incomingContentAlpha: CGFloat = 0
    private var contentFadeDeadline: TimeInterval?
    private var firstImageFadeDeadline: TimeInterval?

    init(
        coordinator: Coordinator = Coordinator(),
        configuration: Configuration = Configuration()
    ) {
        self.coordinator = coordinator
        self.configuration = configuration
    }

    var phase: Coordinator.Phase {
        coordinator.phase
    }

    var canBeginPinch: Bool {
        coordinator.canBeginPinch
    }

    var needsSettleFrames: Bool {
        settleFramesRequested
    }

    var needsInteractionFadeFrames: Bool {
        interactionFadeFramesRequested
    }

    var hasPendingPinchFrame: Bool {
        pendingPinchFrame != nil
    }

    var needsFrames: Bool {
        pendingPinchFrame != nil
            || settleFramesRequested
            || interactionFadeFramesRequested
            || activeCover?.removalDeadline != nil
    }

    var hasCover: Bool {
        activeCover != nil
    }

    var blocksSelection: Bool {
        hasCover
    }

    func fadesFirstImage(at timestamp: TimeInterval) -> Bool {
        guard let firstImageFadeDeadline else { return false }
        return sanitizedTimestamp(timestamp) < firstImageFadeDeadline
    }

    func planeChangeNeedsVisualCover(at timestamp: TimeInterval) -> Bool {
        incomingContentAlpha > 0 || logicalContentFadeIsActive(at: timestamp)
    }

    mutating func handle(
        _ event: Coordinator.Event,
        at timestamp: TimeInterval,
        ratioProvider: Coordinator.RatioProvider = { _ in [] }
    ) -> Output {
        var output = Output()
        switch event {
        case .pinchEnded, .pinchCancelled:
            output.append(flushPendingPinch(at: timestamp))
        case .interrupt:
            pendingPinchFrame = nil
        default:
            break
        }
        output.append(process(
            coordinator.handle(event, ratioProvider: ratioProvider)
        ))
        return output
    }

    mutating func beginPinch(
        _ frame: PinchFrame,
        currentMode: MobileCollectionBrowserGridMode,
        at timestamp: TimeInterval,
        ratioProvider: Coordinator.RatioProvider
    ) -> Output {
        pendingPinchFrame = frame
        return process(
            coordinator.handle(
                .pinchBegan(
                    sample: frame.sample,
                    currentMode: currentMode
                ),
                ratioProvider: ratioProvider
            )
        )
    }

    mutating func stagePinch(_ frame: PinchFrame) {
        pendingPinchFrame = frame
    }

    mutating func discardPendingPinch() {
        pendingPinchFrame = nil
    }

    mutating func flushPendingPinch(at timestamp: TimeInterval) -> Output {
        guard let frame = pendingPinchFrame else { return Output() }
        pendingPinchFrame = nil
        var output = process(
            coordinator.handle(.pinchChanged(sample: frame.sample))
        )
        output.appliedPinchFrame = frame
        return output
    }

    mutating func endPinch(
        scale: CGFloat,
        reduceMotion: Bool,
        timestamp: TimeInterval
    ) -> Output {
        handle(
            .pinchEnded(
                scale: scale,
                reduceMotion: reduceMotion,
                timestamp: timestamp
            ),
            at: timestamp
        )
    }

    mutating func cancelPinch(
        reduceMotion: Bool,
        at timestamp: TimeInterval
    ) -> Output {
        handle(
            .pinchCancelled(reduceMotion: reduceMotion),
            at: timestamp
        )
    }

    mutating func advanceFrame(to timestamp: TimeInterval) -> Output {
        let timestamp = sanitizedTimestamp(timestamp)
        var output = flushPendingPinch(at: timestamp)
        if settleFramesRequested {
            output.append(process(
                coordinator.handle(.settleTick(timestamp: timestamp))
            ))
        }
        if interactionFadeFramesRequested {
            output.append(process(
                coordinator.handle(.interactionFadeTick(timestamp: timestamp))
            ))
        }
        if let cover = activeCover,
           let removalDeadline = cover.removalDeadline,
           timestamp >= removalDeadline {
            activeCover = nil
            output.expiredCoverGeneration = cover.generation
        }
        return output
    }

    mutating func acknowledgeTimingEffect(
        _ effect: InteractionEffect,
        at timestamp: TimeInterval
    ) -> Output {
        switch effect {
        case .startDisplayLink:
            interactionFadeFramesRequested = false
            settleFramesRequested = true
            return process(coordinator.handle(
                .settleStarted(timestamp: sanitizedTimestamp(timestamp))
            ))

        case .stopDisplayLink:
            settleFramesRequested = false

        case .startInteractionFadeTicks:
            interactionFadeFramesRequested = true

        case .stopInteractionFadeTicks:
            interactionFadeFramesRequested = false

        default:
            break
        }
        return Output()
    }

    @discardableResult
    mutating func installCover(
        contentOffset: CGPoint,
        at timestamp: TimeInterval
    ) -> Cover {
        precondition(coverGeneration < .max)
        coverGeneration += 1
        let cover = Cover(
            generation: coverGeneration,
            installedAt: sanitizedTimestamp(timestamp),
            contentOffset: contentOffset,
            removalDeadline: nil
        )
        activeCover = cover
        return cover
    }

    @discardableResult
    mutating func beginCoverFade(
        generation: Cover.Generation,
        at timestamp: TimeInterval
    ) -> Cover? {
        guard var cover = activeCover,
              cover.generation == generation else {
            return nil
        }
        cover.removalDeadline = sanitizedTimestamp(timestamp)
            + configuration.coverFadeDuration
            + configuration.coverRemovalGrace
        activeCover = cover
        return cover
    }

    @discardableResult
    mutating func updateCoverContentOffset(
        generation: Cover.Generation,
        contentOffset: CGPoint
    ) -> Cover? {
        guard var cover = activeCover,
              cover.generation == generation else {
            return nil
        }
        cover.contentOffset = contentOffset
        activeCover = cover
        return cover
    }

    @discardableResult
    mutating func removeCover(
        generation: Cover.Generation? = nil
    ) -> Cover.Generation? {
        guard let cover = activeCover,
              generation == nil || cover.generation == generation else {
            return nil
        }
        activeCover = nil
        return cover.generation
    }

    mutating func beginFirstImageFade(at timestamp: TimeInterval) {
        firstImageFadeDeadline = sanitizedTimestamp(timestamp)
            + configuration.firstImageFadeWindow
    }

    mutating func recordRendererEffect(
        _ effect: InteractionEffect,
        at timestamp: TimeInterval
    ) {
        let timestamp = sanitizedTimestamp(timestamp)
        switch effect {
        case .installPlane:
            incomingContentAlpha = 0
            contentFadeDeadline = nil

        case let .renderSettle(_, _, _, presentationProgress, _):
            let alpha = PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: presentationProgress
            )
            if presentationProgress > 0 {
                contentFadeDeadline = nil
            } else if incomingContentAlpha > 0 {
                contentFadeDeadline = timestamp
                    + configuration.rendererFadeDuration
            }
            incomingContentAlpha = alpha

        case let .renderInteractionFade(_, presentationProgress):
            incomingContentAlpha = PlayerBrowserGridCrossfade
                .incomingContentAlpha(settleProgress: presentationProgress)
            contentFadeDeadline = nil

        case .renderZoom:
            if incomingContentAlpha > 0 {
                contentFadeDeadline = timestamp
                    + configuration.rendererFadeDuration
            }
            incomingContentAlpha = 0

        case .commitPlane:
            incomingContentAlpha = 0
            contentFadeDeadline = nil

        case .finishInteraction:
            pendingPinchFrame = nil
            settleFramesRequested = false
            interactionFadeFramesRequested = false
            incomingContentAlpha = 0
            contentFadeDeadline = nil

        case .applyMode, .discardPlane, .resetRenderer:
            incomingContentAlpha = 0
            contentFadeDeadline = nil

        default:
            break
        }
    }

    @discardableResult
    mutating func invalidate() -> Cover.Generation? {
        let removedCoverGeneration = activeCover?.generation
        coordinator = Coordinator()
        pendingPinchFrame = nil
        settleFramesRequested = false
        interactionFadeFramesRequested = false
        activeCover = nil
        incomingContentAlpha = 0
        contentFadeDeadline = nil
        firstImageFadeDeadline = nil
        return removedCoverGeneration
    }

    private func process(_ effects: [InteractionEffect]) -> Output {
        Output(effects: effects)
    }

    private func logicalContentFadeIsActive(
        at timestamp: TimeInterval
    ) -> Bool {
        guard let contentFadeDeadline else { return false }
        return sanitizedTimestamp(timestamp) < contentFadeDeadline
    }

    private func sanitizedTimestamp(_ timestamp: TimeInterval) -> TimeInterval {
        guard timestamp.isFinite else { return 0 }
        return max(timestamp, 0)
    }
}
