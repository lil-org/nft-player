import QuartzCore
import UIKit
import os

private let gridTransitionFrameSignposter = OSSignposter(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "GridTransitionFrame"
)

struct GridTransitionFrame: Equatable {
    static let minimumDuration: TimeInterval = 1.0 / 120
    static let maximumDuration: TimeInterval = 1.0 / 60

    let timestamp: TimeInterval
    let targetTimestamp: TimeInterval
    let duration: TimeInterval

    init(timestamp: TimeInterval, targetTimestamp: TimeInterval) {
        self.timestamp = timestamp
        self.targetTimestamp = targetTimestamp
        duration = max(targetTimestamp - timestamp, 0)
    }

    var adaptiveDuration: TimeInterval {
        min(max(duration, Self.minimumDuration), Self.maximumDuration)
    }
}

@MainActor
protocol GridTransitionFrameDriving: AnyObject {
    var now: TimeInterval { get }
    var isRunning: Bool { get }

    func start(
        onFrame: @escaping @MainActor (GridTransitionFrame) -> Void
    )
    func stop()
    func invalidate()
}

@MainActor
final class GridTransitionDisplayLinkFrameDriver:
    GridTransitionFrameDriving {
    @MainActor
    private final class DisplayLinkTarget: NSObject {
        weak var driver: GridTransitionDisplayLinkFrameDriver?

        @objc func tick(_ displayLink: CADisplayLink) {
            driver?.tick(at: displayLink.timestamp)
        }
    }

    private let displayLinkTarget = DisplayLinkTarget()
    private var displayLink: CADisplayLink?
    private var onFrame: (@MainActor (GridTransitionFrame) -> Void)?
    private var isInvalidated = false

    init() {
        displayLinkTarget.driver = self
    }

    var now: TimeInterval {
        CACurrentMediaTime()
    }

    var isRunning: Bool {
        displayLink != nil
    }

    func start(
        onFrame: @escaping @MainActor (GridTransitionFrame) -> Void
    ) {
        guard !isInvalidated else { return }
        self.onFrame = onFrame
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: displayLinkTarget,
            selector: #selector(DisplayLinkTarget.tick(_:))
        )
        configureMaximumFrameRate(of: displayLink)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        onFrame = nil
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        stop()
    }

    private func tick(at timestamp: TimeInterval) {
        guard !isInvalidated else { return }
        guard let displayLink else { return }
        let frame = GridTransitionFrame(
            timestamp: timestamp,
            targetTimestamp: displayLink.targetTimestamp
        )
        let state = gridTransitionFrameSignposter.beginInterval(
            "TransitionFrame"
        )
        onFrame?(frame)
        gridTransitionFrameSignposter.endInterval(
            "TransitionFrame",
            state
        )
    }

    private func configureMaximumFrameRate(of displayLink: CADisplayLink) {
        let maximum = min(UIScreen.main.maximumFramesPerSecond, 120)
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(maximum),
            maximum: Float(maximum),
            preferred: Float(maximum)
        )
    }
}
