import QuartzCore
import UIKit

@MainActor
protocol GridTransitionFrameDriving: AnyObject {
    var now: TimeInterval { get }
    var isRunning: Bool { get }

    func start(
        onFrame: @escaping @MainActor (TimeInterval) -> Void
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
    private var onFrame: (@MainActor (TimeInterval) -> Void)?
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
        onFrame: @escaping @MainActor (TimeInterval) -> Void
    ) {
        guard !isInvalidated else { return }
        self.onFrame = onFrame
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: displayLinkTarget,
            selector: #selector(DisplayLinkTarget.tick(_:))
        )
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
        onFrame?(timestamp)
    }
}
