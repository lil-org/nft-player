import QuartzCore
import UIKit

@MainActor
final class MobilePlayerGridTransitionCoverRenderer {
    typealias Generation = UInt64
    typealias SnapshotFactory = (UIView) -> UIView?

    private struct ActiveCover {
        let generation: Generation
        let view: UIView
        var capturedContentOffset: CGPoint
    }

    private static let fadeAnimationKey = "opacity"

    private let snapshotFactory: SnapshotFactory
    private var activeCover: ActiveCover?

    init(snapshotFactory: @escaping SnapshotFactory) {
        self.snapshotFactory = snapshotFactory
    }

    var hasCover: Bool {
        activeCover != nil
    }

    var activeGeneration: Generation? {
        activeCover?.generation
    }

    var capturedContentOffset: CGPoint? {
        activeCover?.capturedContentOffset
    }

    @discardableResult
    func install(
        generation: Generation,
        viewportView: UIView,
        collectionView: UICollectionView
    ) -> Bool {
        guard collectionView.superview === viewportView else { return false }
        if activeCover?.generation == generation {
            return true
        }
        let snapshot = snapshotFactory(viewportView)
            ?? makeBitmapSnapshot(in: viewportView)
        removeAll()
        snapshot.frame = snapshotFrame(for: viewportView)
        snapshot.isUserInteractionEnabled = false
        snapshot.layer.removeAnimation(forKey: Self.fadeAnimationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snapshot.layer.opacity = 1
        CATransaction.commit()
        viewportView.insertSubview(snapshot, aboveSubview: collectionView)
        activeCover = ActiveCover(
            generation: generation,
            view: snapshot,
            capturedContentOffset: collectionView.contentOffset
        )
        return true
    }

    @discardableResult
    func startFade(generation: Generation) -> Bool {
        guard let activeCover,
              activeCover.generation == generation else {
            return false
        }
        let layer = activeCover.view.layer
        guard layer.animation(forKey: Self.fadeAnimationKey) == nil else {
            return true
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = MobilePlayerCollectionBrowserTransitionPresentation
            .contentFadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
        layer.add(fade, forKey: Self.fadeAnimationKey)
        return true
    }

    @discardableResult
    func updateCapturedContentOffset(
        _ contentOffset: CGPoint,
        generation: Generation
    ) -> Bool {
        guard activeCover?.generation == generation else { return false }
        activeCover?.capturedContentOffset = contentOffset
        return true
    }

    @discardableResult
    func remove(generation: Generation) -> Bool {
        guard activeCover?.generation == generation else { return false }
        removeAll()
        return true
    }

    func removeAll() {
        activeCover?.view.layer.removeAnimation(
            forKey: Self.fadeAnimationKey
        )
        activeCover?.view.removeFromSuperview()
        activeCover = nil
    }

    private func snapshotFrame(for viewportView: UIView) -> CGRect {
        let bounds = viewportView.bounds
        guard bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite else {
            return .zero
        }
        return bounds
    }

    private func makeBitmapSnapshot(in viewportView: UIView) -> UIView {
        let bounds = snapshotFrame(for: viewportView)
        guard bounds.width > 0, bounds.height > 0 else {
            return UIView(frame: bounds)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            bounds: bounds,
            format: format
        ).image { context in
            guard !viewportView.drawHierarchy(
                in: bounds,
                afterScreenUpdates: false
            ) else {
                return
            }
            (viewportView.layer.presentation() ?? viewportView.layer).render(
                in: context.cgContext
            )
        }
        return UIImageView(image: image)
    }
}
