import QuartzCore
import UIKit

struct GridModePinchFrame: Equatable {
    let sample: PlayerBrowserGridInteractionCoordinator.PinchSample
    let viewLocation: CGPoint

    /// Captured before coalescing so release motion uses the real sample age.
    init(
        scale: CGFloat,
        viewLocation: CGPoint,
        timestamp: TimeInterval = CACurrentMediaTime()
    ) {
        sample = PlayerBrowserGridInteractionCoordinator.PinchSample(
            scale: scale,
            centroidY: viewLocation.y,
            timestamp: timestamp
        )
        self.viewLocation = viewLocation
    }
}

final class GridModePinchFrameCoalescer {
    private var pendingFrame: GridModePinchFrame?
    private let apply: (GridModePinchFrame) -> Void
    private lazy var update = PendingMainQueueUpdate { [weak self] in
        self?.applyPendingFrame()
    }

    init(apply: @escaping (GridModePinchFrame) -> Void) {
        self.apply = apply
    }

    func seed(_ frame: GridModePinchFrame) {
        pendingFrame = frame
    }

    func stage(_ frame: GridModePinchFrame) {
        pendingFrame = frame
        update.schedule()
    }

    func flush() {
        update.invalidate()
        applyPendingFrame()
    }

    func invalidate() {
        update.invalidate()
        pendingFrame = nil
    }

    private func applyPendingFrame() {
        guard let pendingFrame else { return }
        self.pendingFrame = nil
        apply(pendingFrame)
    }
}

struct CachedGridModeDestination {
    let anchorTokenIndex: Int
    let layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    let layout: MobilePlayerBrowserLayout
}

/// Excludes the initial token because settled-position echoes do not change geometry.
struct GridModeGeometryCacheIdentity: Equatable {
    let collectionId: String
    let itemCount: Int
    let viewportSize: CGSize
    let displayScale: CGFloat
    let topContentInset: CGFloat
    let bottomContentInset: CGFloat
}

struct CachedGridModeGeometry {
    let aspectProfile: MobilePlayerBrowserAspectProfile
    let layout: MobilePlayerBrowserLayout
}

struct GridModeGeometryCache {
    let identity: GridModeGeometryCacheIdentity
    var geometries: [MobileCollectionBrowserGridMode: CachedGridModeGeometry]
}

struct GridModeGeometryPrewarmPlan {
    let identity: GridModeGeometryCacheIdentity
    var modes: [MobileCollectionBrowserGridMode]
}

@MainActor
final class MobilePlayerCollectionBrowserGridModeCoordinator {
    struct ContentAccess {
        let applyPinchFrame: @MainActor (GridModePinchFrame) -> Void
        let prewarmNextGeometry: @MainActor () -> Void
        let settleTick: @MainActor () -> Void
        let interactionFadeTick: @MainActor () -> Void
    }

    private final class SettleDisplayLinkTarget: NSObject {
        weak var coordinator: MobilePlayerCollectionBrowserGridModeCoordinator?

        @MainActor @objc func tick(_ displayLink: CADisplayLink) {
            coordinator?.contentAccess?.settleTick()
        }
    }

    private final class InteractionFadeDisplayLinkTarget: NSObject {
        weak var coordinator: MobilePlayerCollectionBrowserGridModeCoordinator?

        @MainActor @objc func tick(_ displayLink: CADisplayLink) {
            coordinator?.contentAccess?.interactionFadeTick()
        }
    }

    private static let commitFadeWindow: TimeInterval = 1.5

    private let commitSnapshotFactory: (UIView) -> UIView?
    private weak var collectionView:
        MobilePlayerCollectionBrowserCollectionView?
    private var contentAccess: ContentAccess?
    private let settleDisplayLinkTarget = SettleDisplayLinkTarget()
    private let interactionFadeDisplayLinkTarget =
        InteractionFadeDisplayLinkTarget()
    private var isInvalidated = false

    private(set) var renderer: MobilePlayerCollectionBrowserGridRenderer!
    private(set) var pinchRecognizer: UIPinchGestureRecognizer!
    private(set) var pinchFrameCoalescer: GridModePinchFrameCoalescer!
    private(set) var geometryPrewarmUpdate: PendingMainQueueUpdate!
    var interactionCoordinator = PlayerBrowserGridInteractionCoordinator()
    var effectDrainDepth = 0
    var contentOffsetRestorationDepth = 0
    var commitFadeDeadline: TimeInterval = 0
    var settleDisplayLink: CADisplayLink?
    var commitSnapshotView: UIView?
    var commitSnapshotContentOffset: CGPoint?
    var commitSnapshotDissolveTask: Task<Void, Never>?
    var interactionFadeDisplayLink: CADisplayLink?
    var settleContentOffsetY: CGFloat?
    var settlePanMaximumNumberOfTouches: Int?
    var geometryCache: GridModeGeometryCache?
    var geometryPrewarmPlan: GridModeGeometryPrewarmPlan?
    var destinationCache = [
        MobileCollectionBrowserGridMode: CachedGridModeDestination
    ]()
    var lastPinchViewLocation: CGPoint?

    init(commitSnapshotFactory: @escaping (UIView) -> UIView?) {
        self.commitSnapshotFactory = commitSnapshotFactory
        settleDisplayLinkTarget.coordinator = self
        interactionFadeDisplayLinkTarget.coordinator = self
    }

    func configure(
        collectionView: MobilePlayerCollectionBrowserCollectionView,
        viewportView: UIView,
        gestureTarget: Any,
        gestureAction: Selector,
        gestureDelegate: UIGestureRecognizerDelegate,
        rendererContentAccess:
            MobilePlayerCollectionBrowserGridRenderer.ContentAccess,
        contentAccess: ContentAccess
    ) {
        guard !isInvalidated else { return }
        self.collectionView = collectionView
        self.contentAccess = contentAccess
        renderer = MobilePlayerCollectionBrowserGridRenderer(
            collectionView: collectionView,
            viewportView: viewportView,
            contentAccess: rendererContentAccess
        )
        let recognizer = UIPinchGestureRecognizer(
            target: gestureTarget,
            action: gestureAction
        )
        recognizer.delegate = gestureDelegate
        pinchRecognizer = recognizer
        pinchFrameCoalescer = GridModePinchFrameCoalescer(
            apply: contentAccess.applyPinchFrame
        )
        geometryPrewarmUpdate = PendingMainQueueUpdate(
            action: contentAccess.prewarmNextGeometry
        )
    }

    var hasInteractionState: Bool {
        interactionCoordinator.phase != .idle
    }

    var fadesFirstImage: Bool {
        CACurrentMediaTime() < commitFadeDeadline
    }

    func makeMenu(
        currentMode: MobileCollectionBrowserGridMode,
        selection: @escaping @MainActor (
            MobileCollectionBrowserGridMode
        ) -> Void
    ) -> UIMenu {
        let actions = MobileCollectionBrowserGridMode.allCases.reversed().map {
            mode in
            UIAction(
                title: menuTitle(for: mode),
                image: UIImage(systemName: menuSystemImageName(for: mode)),
                state: mode == currentMode ? .on : .off
            ) { _ in
                MainActor.assumeIsolated {
                    selection(mode)
                }
            }
        }
        return UIMenu(
            options: [.displayInline, .singleSelection, .displayAsPalette],
            children: actions
        )
    }

    func beginCommitFadeWindow() {
        guard !isInvalidated else { return }
        commitFadeDeadline = CACurrentMediaTime() + Self.commitFadeWindow
    }

    @discardableResult
    func installSnapshotCover(
        viewportView: UIView,
        collectionView: UICollectionView
    ) -> UIView {
        let snapshot = commitSnapshotFactory(viewportView)
            ?? makeBitmapSnapshotCover(viewportView: viewportView)
        removeCommitSnapshot()
        snapshot.frame = snapshotFrame(for: viewportView)
        snapshot.isUserInteractionEnabled = false
        viewportView.insertSubview(snapshot, aboveSubview: collectionView)
        commitSnapshotView = snapshot
        commitSnapshotContentOffset = collectionView.contentOffset
        return snapshot
    }

    func startCommitSnapshotDissolve(_ snapshot: UIView) {
        guard !isInvalidated, commitSnapshotView === snapshot else { return }
        guard snapshot.layer.animation(forKey: "opacity") == nil else { return }
        // The layer animation commits with insertion; a deferred UIView fade can blink.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = MobilePlayerCollectionBrowserTransitionPresentation
            .contentFadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        snapshot.layer.opacity = 0
        snapshot.layer.add(fade, forKey: "opacity")
        let dissolveDelay = MobilePlayerCollectionBrowserTransitionPresentation
            .contentFadeDuration + 0.05
        commitSnapshotDissolveTask?.cancel()
        commitSnapshotDissolveTask = Task { [weak self, weak snapshot] in
            do {
                try await Task.sleep(for: .seconds(dissolveDelay))
            } catch {
                return
            }
            guard let snapshot else { return }
            snapshot.removeFromSuperview()
            if let self, self.commitSnapshotView === snapshot {
                self.commitSnapshotDissolveTask = nil
                self.commitSnapshotView = nil
                self.commitSnapshotContentOffset = nil
            }
        }
    }

    func removeCommitSnapshot() {
        commitSnapshotDissolveTask?.cancel()
        commitSnapshotDissolveTask = nil
        commitSnapshotView?.removeFromSuperview()
        commitSnapshotView = nil
        commitSnapshotContentOffset = nil
    }

    func startSettleDisplayLink(
        collectionView: MobilePlayerCollectionBrowserCollectionView
    ) {
        guard !isInvalidated else { return }
        if settleContentOffsetY == nil {
            settleContentOffsetY = collectionView.contentOffset.y
        }
        if settlePanMaximumNumberOfTouches == nil {
            let panGestureRecognizer = collectionView.panGestureRecognizer
            settlePanMaximumNumberOfTouches = panGestureRecognizer
                .maximumNumberOfTouches
            panGestureRecognizer.maximumNumberOfTouches = 1
        }
        guard settleDisplayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: settleDisplayLinkTarget,
            selector: #selector(SettleDisplayLinkTarget.tick(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        settleDisplayLink = displayLink
    }

    func stopSettleDisplayLink(
        collectionView: MobilePlayerCollectionBrowserCollectionView
    ) {
        settleDisplayLink?.invalidate()
        settleDisplayLink = nil
        settleContentOffsetY = nil
        if let maximumNumberOfTouches = settlePanMaximumNumberOfTouches {
            collectionView.panGestureRecognizer.maximumNumberOfTouches =
                maximumNumberOfTouches
            settlePanMaximumNumberOfTouches = nil
        }
    }

    func startInteractionFadeDisplayLink() {
        guard !isInvalidated, interactionFadeDisplayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: interactionFadeDisplayLinkTarget,
            selector: #selector(InteractionFadeDisplayLinkTarget.tick(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        interactionFadeDisplayLink = displayLink
    }

    func stopInteractionFadeDisplayLink() {
        interactionFadeDisplayLink?.invalidate()
        interactionFadeDisplayLink = nil
    }

    func invalidate() {
        guard !isInvalidated else { return }
        pinchFrameCoalescer?.invalidate()
        geometryPrewarmUpdate?.invalidate()
        if let collectionView {
            stopSettleDisplayLink(collectionView: collectionView)
        } else {
            settleDisplayLink?.invalidate()
            settleDisplayLink = nil
            settleContentOffsetY = nil
            settlePanMaximumNumberOfTouches = nil
        }
        stopInteractionFadeDisplayLink()
        removeCommitSnapshot()
        _ = renderer?.reset()
        isInvalidated = true
        contentAccess = nil
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

    private func makeBitmapSnapshotCover(viewportView: UIView) -> UIView {
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

    private func menuTitle(
        for mode: MobileCollectionBrowserGridMode
    ) -> String {
        switch mode {
        case .large:
            Strings.largeGrid
        case .threeColumns:
            Strings.threeColumns
        case .fiveColumns:
            Strings.fiveColumns
        case .nineColumns:
            Strings.nineColumns
        }
    }

    private func menuSystemImageName(
        for mode: MobileCollectionBrowserGridMode
    ) -> String {
        switch mode {
        case .large:
            "rectangle.grid.1x2"
        case .threeColumns:
            "square.grid.3x2"
        case .fiveColumns:
            "square.grid.4x3.fill"
        case .nineColumns:
            "square.grid.3x3.fill"
        }
    }
}
