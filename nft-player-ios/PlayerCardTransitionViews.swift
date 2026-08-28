import UIKit
import UIKit.UIGestureRecognizerSubclass

final class CardTransitionUnderlayView: UIView {

    private final class LateImageEntry {
        let itemSnapshot: MobilePlayerBrowserItemSnapshot
        let imageView = NativeMetalCardCornerMaskedImageView()
        var cancellation: (() -> Void)?
        var hasLoadedImage = false

        init(itemSnapshot: MobilePlayerBrowserItemSnapshot) {
            self.itemSnapshot = itemSnapshot
        }
    }

    private static let lateImageFadeDuration: TimeInterval = 0.12
    private let itemSnapshots: [MobilePlayerBrowserItemSnapshot]
    private var lateImageEntries = [LateImageEntry]()
    private var revealProgress: CGFloat = 0

    init(itemSnapshots: [MobilePlayerBrowserItemSnapshot]) {
        self.itemSnapshots = itemSnapshots
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        makeBackgroundTransparent()
        clipsToBounds = true

        itemSnapshots.forEach { itemSnapshot in
            let snapshotView = itemSnapshot.snapshotView
            snapshotView.removeFromSuperview()
            snapshotView.layer.removeAllAnimations()
            snapshotView.transform = .identity
            snapshotView.alpha = 0
            snapshotView.isHidden = false
            snapshotView.isUserInteractionEnabled = false
            addSubview(snapshotView)
        }
        startLateImageLoads()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    isolated deinit {
        lateImageEntries.forEach { $0.cancellation?() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for itemSnapshot in itemSnapshots {
            itemSnapshot.snapshotView.frame = convert(itemSnapshot.frameInWindow, from: nil)
        }
        lateImageEntries.forEach { entry in
            entry.imageView.frame = entry.itemSnapshot.snapshotView.frame
        }
    }

    func setOtherCardsRevealProgress(_ progress: CGFloat) {
        let clampedProgress = min(max(progress, 0), 1)
        revealProgress = clampedProgress
        itemSnapshots.forEach { itemSnapshot in
            itemSnapshot.snapshotView.alpha = clampedProgress
        }
        lateImageEntries.forEach { entry in
            entry.itemSnapshot.snapshotView.alpha = entry.hasLoadedImage ? 0 : clampedProgress
            entry.imageView.alpha = entry.hasLoadedImage ? clampedProgress : 0
        }
    }

    private func startLateImageLoads() {
        for itemSnapshot in itemSnapshots where !itemSnapshot.hasLoadedImage {
            guard let descriptor = itemSnapshot.descriptor,
                  descriptor.isStaticImage else {
                continue
            }

            let entry = LateImageEntry(itemSnapshot: itemSnapshot)
            entry.imageView.backgroundColor = .clear
            entry.imageView.contentMode = .scaleAspectFit
            entry.imageView.clipsToBounds = true
            entry.imageView.isUserInteractionEnabled = false
            entry.imageView.usesNativeMetalCardCornerMask = descriptor.usesNativeMetalCardPresentation
            entry.imageView.alpha = 0
            addSubview(entry.imageView)
            lateImageEntries.append(entry)

            if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
                displayLateImage(image, for: entry, animated: false)
                continue
            }

            entry.cancellation = DownloadableMediaCache.shared.loadImage(for: descriptor) { [weak self, weak entry] image in
                Task { @MainActor in
                    await Task.yield()
                    guard let self,
                          let entry,
                          self.lateImageEntries.contains(where: { $0 === entry }) else {
                        return
                    }
                    entry.cancellation = nil
                    guard let image else { return }
                    self.displayLateImage(image, for: entry, animated: true)
                }
            }
        }
    }

    private func displayLateImage(
        _ image: UIImage,
        for entry: LateImageEntry,
        animated: Bool
    ) {
        entry.hasLoadedImage = true
        entry.imageView.image = image
        entry.imageView.frame = entry.itemSnapshot.snapshotView.frame

        let updates = {
            entry.itemSnapshot.snapshotView.alpha = 0
            entry.imageView.alpha = self.revealProgress
        }
        guard animated,
              revealProgress > 0 else {
            updates()
            return
        }

        entry.imageView.alpha = 0
        UIView.animate(
            withDuration: Self.lateImageFadeDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: updates
        )
    }

}

final class CardLayoutPinchGestureRecognizer: UIGestureRecognizer {

    var activationScale: CGFloat = 1
    var oppositeDirectionFailureScale: CGFloat = 1
    var canTrackPinch: ((CardLayoutPinchGestureRecognizer) -> Bool)?

    private(set) var scale: CGFloat = 1
    private(set) var velocity: CGFloat = 0

    private var trackedTouches: [UITouch] = []
    private var initialDistance: CGFloat = 0
    private var initialLocationInView = CGPoint.zero
    private var previousScale: CGFloat = 1
    private var previousTimestamp: TimeInterval = 0
    private var hasEvaluatedCanTrackPinch = false

    var isFirstPinchTrackingEvaluation: Bool {
        !hasEvaluatedCanTrackPinch
    }

    var isTrackingPinch: Bool {
        switch state {
        case .possible, .began, .changed:
            return trackedTouches.count == 2
        default:
            return false
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible,
              trackedTouches.count + touches.count <= 2 else {
            cancelOrFail()
            return
        }

        trackedTouches.append(contentsOf: touches.prefix(2 - trackedTouches.count))

        guard trackedTouches.count == 2 else { return }
        guard let view,
              let distance = distanceBetweenTrackedTouches(in: view),
              distance > 0 else {
            state = .failed
            return
        }

        initialDistance = distance
        initialLocationInView = currentPinchLocation(in: view)
        previousTimestamp = event.timestamp
        scale = 1
        previousScale = 1
        velocity = 0
        hasEvaluatedCanTrackPinch = false

        guard canTrackCurrentPinch() else {
            state = .failed
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard isTrackingPinch,
              touches.contains(where: { trackedTouches.contains($0) }) else {
            return
        }

        updateScaleAndVelocity(timestamp: event.timestamp)

        switch state {
        case .possible:
            guard canTrackCurrentPinch() else {
                state = .failed
                return
            }

            if scale > oppositeDirectionFailureScale {
                state = .failed
            } else if scale <= activationScale {
                state = .began
            }

        case .began, .changed:
            state = .changed

        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.contains(where: { trackedTouches.contains($0) }) else { return }

        switch state {
        case .began, .changed:
            updateScaleAndVelocity(timestamp: event.timestamp)
            state = .ended
        case .possible:
            state = .failed
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelOrFail()
    }

    override func reset() {
        trackedTouches = []
        initialDistance = 0
        initialLocationInView = .zero
        previousScale = 1
        previousTimestamp = 0
        scale = 1
        velocity = 0
        hasEvaluatedCanTrackPinch = false
    }

    func pinchLocation(in targetView: UIView?) -> CGPoint {
        currentPinchLocation(in: targetView)
    }

    func initialPinchLocation(in targetView: UIView?) -> CGPoint {
        guard let view else { return initialLocationInView }
        return view.convert(initialLocationInView, to: targetView)
    }

    private func updateScaleAndVelocity(timestamp: TimeInterval) {
        guard let view,
              let distance = distanceBetweenTrackedTouches(in: view),
              initialDistance > 0 else {
            return
        }

        let nextScale = distance / initialDistance
        let elapsed = timestamp - previousTimestamp
        velocity = elapsed > 0 ? (nextScale - previousScale) / CGFloat(elapsed) : 0
        scale = nextScale
        previousScale = nextScale
        previousTimestamp = timestamp
    }

    private func canTrackCurrentPinch() -> Bool {
        defer {
            hasEvaluatedCanTrackPinch = true
        }

        return canTrackPinch?(self) == true
    }

    private func currentPinchLocation(in targetView: UIView?) -> CGPoint {
        guard trackedTouches.count == 2 else { return .zero }

        let firstLocation = trackedTouches[0].location(in: targetView)
        let secondLocation = trackedTouches[1].location(in: targetView)
        return CGPoint(
            x: (firstLocation.x + secondLocation.x) / 2,
            y: (firstLocation.y + secondLocation.y) / 2
        )
    }

    private func distanceBetweenTrackedTouches(in targetView: UIView) -> CGFloat? {
        guard trackedTouches.count == 2 else { return nil }

        let firstLocation = trackedTouches[0].location(in: targetView)
        let secondLocation = trackedTouches[1].location(in: targetView)
        return hypot(firstLocation.x - secondLocation.x, firstLocation.y - secondLocation.y)
    }

    private func cancelOrFail() {
        switch state {
        case .began, .changed:
            state = .cancelled
        default:
            state = .failed
        }
    }

}

