// ∅ 2026 lil org

import Cocoa

struct MacPlayerBrowserItemSnapshot {
    let tokenIndex: Int
    let frameInWindow: CGRect
    let image: NSImage?
    let usesNativeMetalCardCornerMask: Bool
}

protocol MacPlayerMinimizeHandling: AnyObject {
    var canMinimize: Bool { get }
    /// True while a hero animation or an interactive drag owns the screen.
    var isTransitionInFlight: Bool { get }
    @discardableResult
    func beginMinimize() -> Bool
    func updateMinimize(progress: CGFloat)
    func endMinimize(commit: Bool)
    func minimizeImmediately()
}

final class MacPlayerCardTransitionCanvas: NSView {

    static let expandDuration: TimeInterval = 0.18
    static let minimizeDuration: TimeInterval = 0.22
    static let cancelDuration: TimeInterval = 0.28

    private let backdropView = NSView()
    private let cardView = MacCollectionBrowserThumbnailView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        isHidden = true

        backdropView.wantsLayer = true
        backdropView.layer?.backgroundColor = NSColor.black.cgColor
        backdropView.layer?.actions = ["backgroundColor": NSNull()]
        backdropView.autoresizingMask = [.width, .height]
        addSubview(backdropView)
        addSubview(cardView)
    }

    /// The canvas is decoration only — clicks belong to whatever is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// The colour the hero flies over. Matches the screens either side of it, so the
    /// zoom does not flash black between two light-backed screens.
    func setBackdropColor(_ color: NSColor) {
        backdropView.layer?.backgroundColor = color.cgColor
    }

    func begin(
        image: NSImage,
        usesNativeMetalCardCornerMask: Bool,
        cardFrame: CGRect,
        backdropAlpha: CGFloat
    ) {
        isHidden = false
        backdropView.frame = bounds
        cardView.usesNativeMetalCardCornerMask = usesNativeMetalCardCornerMask
        cardView.image = image
        setCardFrame(cardFrame)
        setBackdropAlpha(backdropAlpha)
    }

    func setCardFrame(_ frame: CGRect) {
        withoutAnimation {
            cardView.frame = frame
            cardView.layoutSubtreeIfNeeded()
        }
    }

    func setBackdropAlpha(_ alpha: CGFloat) {
        withoutAnimation {
            backdropView.alphaValue = min(max(alpha, 0), 1)
        }
    }

    func animate(
        toCardFrame cardFrame: CGRect,
        backdropAlpha: CGFloat,
        duration: TimeInterval,
        completion: @MainActor @Sendable @escaping () -> Void
    ) {
        let timingFunction = CAMediaTimingFunction(name: .easeOut)
        cardView.animateCornerMask(
            fromBounds: CGRect(origin: .zero, size: cardView.frame.size),
            toBounds: CGRect(origin: .zero, size: cardFrame.size),
            duration: duration,
            timingFunction: timingFunction
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = true
            cardView.animator().frame = cardFrame
            backdropView.animator().alphaValue = min(max(backdropAlpha, 0), 1)
        } completionHandler: {
            Task { @MainActor in
                completion()
            }
        }
    }

    func cancelAnimations() {
        cardView.layer?.removeAllAnimations()
        cardView.layer?.mask?.removeAllAnimations()
        backdropView.layer?.removeAllAnimations()
    }

    func end() {
        cancelAnimations()
        isHidden = true
        cardView.image = nil
        cardView.frame = .zero
    }

    private func withoutAnimation(_ updates: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            updates()
        }
    }

}

enum MacPlayerCardGeometry {

    /// Where the pager will draw the media once it is on screen — the hero's landing
    /// rect. Native metal cards are drawn inset inside their viewport rather than
    /// simply aspect fit, so they need their own geometry.
    static func expandedFrame(
        for contentSize: CGSize,
        in bounds: CGRect,
        usesNativeMetalCardPresentation: Bool
    ) -> CGRect {
        guard usesNativeMetalCardPresentation else {
            return expandedFrame(for: contentSize, in: bounds)
        }
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        return NativeMetalCardLayout.cardContentRect(in: bounds.size)
            .offsetBy(dx: bounds.minX, dy: bounds.minY)
    }

    /// Aspect fit of the given content size inside the container, the same rect the
    /// pager will end up drawing the media in.
    static func expandedFrame(for contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              contentSize.width.isFinite,
              contentSize.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }
        return PlayerAspectFitLayout.centeredRect(for: contentSize, in: bounds)
    }

    static func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        let progress = min(max(progress, 0), 1)
        return CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    static func easeOutQuadratic(_ progress: CGFloat) -> CGFloat {
        let progress = min(max(progress, 0), 1)
        return 1 - (1 - progress) * (1 - progress)
    }

}
