// ∅ 2026 lil org

import UIKit
import SwiftUI
import WebKit
import ImageIO
import AVFoundation

enum FullscreenTokenMediaView {
    static func imageView(in containerView: UIView) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        install(imageView, in: containerView)
        return imageView
    }

    static func webView(in containerView: UIView) -> AutoReloadingWebView {
        let webView = AutoReloadingWebView.new
        webView.isUserInteractionEnabled = false
        install(webView, in: containerView)
        return webView
    }

    static func ponchoDrifellaMetalCardView(in containerView: UIView) -> PonchoDrifellaMetalCardView {
        let cardView = PonchoDrifellaMetalCardView()
        cardView.isUserInteractionEnabled = false
        install(cardView, in: containerView)
        return cardView
    }

    private static func install(_ view: UIView, in containerView: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            view.topAnchor.constraint(equalTo: containerView.topAnchor),
            view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
}

final class FullscreenTokenMediaRenderer {
    private typealias ImageLoadCancellation = () -> Void

    private let containerView: UIView
    private var webView: AutoReloadingWebView!
    private var imageView: UIImageView!
    private var ponchoDrifellaMetalCardView: PonchoDrifellaMetalCardView!
    private var representedImageKey: AnyHashable?
    private var activeImageLoadId: UUID?
    private var cancelActiveImageLoad: ImageLoadCancellation?
    private var webViewMayContainContent = false
    private var usesTransparentPlayerBackground = false

    init(containerView: UIView) {
        self.containerView = containerView
    }

    deinit {
        cancelCurrentImageLoad()
        ponchoDrifellaMetalCardView?.stop()
    }

    func clearContent() {
        cancelCurrentImageLoad()
        hidePonchoDrifellaMetalCardView()
        representedImageKey = nil
        unloadWebContentIfNeeded()
        imageView?.image = nil
    }

    func displayLoadedImage<Key: Hashable>(_ image: UIImage, key: Key) {
        cancelCurrentImageLoad()
        hidePonchoDrifellaMetalCardView()
        let imageKey = AnyHashable(key)
        representedImageKey = imageKey
        ensureImageView()
        webView?.isHidden = true
        imageView.isHidden = false
        imageView.image = image

        webView?.invalidateRequestedContent()
        guard webViewMayContainContent else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.representedImageKey == imageKey else {
                return
            }

            self.unloadWebContentIfNeeded()
        }
    }

    func renderImage<Key: Hashable>(
        key: Key,
        hideImageUntilLoaded: Bool,
        onBegin: (() -> Void)? = nil,
        load: (@escaping (UIImage?) -> Void) -> (() -> Void)?,
        fallbackToWebContent: @escaping () -> Void,
        onLoadedImage: ((UIImage) -> Void)? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        cancelCurrentImageLoad()
        ensureImageView()
        hideWebContent()
        hidePonchoDrifellaMetalCardView()
        imageView.isHidden = hideImageUntilLoaded
        imageView.image = nil
        onBegin?()

        let imageKey = AnyHashable(key)
        let imageLoadId = UUID()
        representedImageKey = imageKey
        activeImageLoadId = imageLoadId
        let cancellation = load { [weak self] image in
            guard let self,
                  self.representedImageKey == imageKey,
                  self.activeImageLoadId == imageLoadId else {
                return
            }

            self.cancelActiveImageLoad = nil
            self.activeImageLoadId = nil

            guard let image else {
                fallbackToWebContent()
                return
            }

            onSuccess?()
            self.displayLoadedImage(image, key: key)
            onLoadedImage?(image)
        }
        guard representedImageKey == imageKey, activeImageLoadId == imageLoadId else {
            cancellation?()
            return
        }
        cancelActiveImageLoad = cancellation
    }

    func renderWebContent(
        _ html: String,
        hidesEmptyWebContent: Bool = false,
        onBegin: (() -> Void)? = nil
    ) {
        prepareWebContent(html, hidesEmptyWebContent: hidesEmptyWebContent, onBegin: onBegin)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func renderLocalWebContent(
        _ html: String,
        htmlDirectoryURL: URL,
        readAccessURL: URL,
        hidesEmptyWebContent: Bool = false,
        onBegin: (() -> Void)? = nil,
        onLoadSuccess: (() -> Void)? = nil,
        onLoadFailure: (() -> Void)? = nil
    ) {
        prepareWebContent(html, hidesEmptyWebContent: hidesEmptyWebContent, onBegin: onBegin)
        webView.loadLocalHTMLString(
            html,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onSuccess: onLoadSuccess,
            onFailure: onLoadFailure
        )
    }

    func renderPonchoDrifellaMetalCard(tokenId: String) {
        cancelCurrentImageLoad()
        representedImageKey = nil
        ensurePonchoDrifellaMetalCardView()
        imageView?.isHidden = true
        imageView?.image = nil
        hideWebContent()
        ponchoDrifellaMetalCardView.isHidden = false
        ponchoDrifellaMetalCardView.display(tokenId: tokenId)
    }

    func preloadWebImage(_ imageURL: URL, completion: ((Bool) -> Void)? = nil) {
        guard let webView else {
            completion?(false)
            return
        }

        webView.callAsyncJavaScript(
            DownloadableTokenHTML.preloadImageJavaScript(imageURL: imageURL),
            arguments: [:],
            in: nil,
            in: .page
        ) { result in
            switch result {
            case .success(let value):
                completion?((value as? Bool) == true)
            case .failure:
                completion?(false)
            }
        }
    }

    func makePlayerBackgroundTransparent() {
        usesTransparentPlayerBackground = true
        containerView.makeBackgroundTransparent()
        if let imageView = imageView {
            imageView.makeBackgroundTransparent()
        }
        webView?.makePlayerBackgroundTransparent()
        if let ponchoDrifellaMetalCardView = ponchoDrifellaMetalCardView {
            ponchoDrifellaMetalCardView.makeBackgroundTransparent()
        }
    }

    private func prepareWebContent(
        _ html: String,
        hidesEmptyWebContent: Bool,
        onBegin: (() -> Void)?
    ) {
        cancelCurrentImageLoad()
        representedImageKey = nil
        ensureWebView()
        imageView?.isHidden = true
        imageView?.image = nil
        hidePonchoDrifellaMetalCardView()
        webView.stopLoading()
        webViewMayContainContent = !html.isEmpty
        webView.isHidden = hidesEmptyWebContent && html.isEmpty
        onBegin?()
    }

    private func cancelCurrentImageLoad() {
        let cancellation = cancelActiveImageLoad
        cancelActiveImageLoad = nil
        activeImageLoadId = nil
        cancellation?()
    }

    private func ensureImageView() {
        guard imageView == nil else { return }

        imageView = FullscreenTokenMediaView.imageView(in: containerView)
        if usesTransparentPlayerBackground {
            imageView.makeBackgroundTransparent()
        }
    }

    private func ensureWebView() {
        guard webView == nil else { return }

        webView = FullscreenTokenMediaView.webView(in: containerView)
        if usesTransparentPlayerBackground {
            webView.makePlayerBackgroundTransparent()
        }
    }

    private func ensurePonchoDrifellaMetalCardView() {
        guard ponchoDrifellaMetalCardView == nil else { return }

        ponchoDrifellaMetalCardView = FullscreenTokenMediaView.ponchoDrifellaMetalCardView(in: containerView)
        if usesTransparentPlayerBackground {
            ponchoDrifellaMetalCardView.makeBackgroundTransparent()
        }
    }

    private func hideWebContent() {
        webView?.invalidateRequestedContent()
        webView?.isHidden = true
    }

    private func hidePonchoDrifellaMetalCardView() {
        ponchoDrifellaMetalCardView?.stop()
        ponchoDrifellaMetalCardView?.isHidden = true
    }

    private func unloadWebContentIfNeeded() {
        guard webViewMayContainContent else {
            webView?.invalidateRequestedContent()
            return
        }

        webView?.unloadContent()
        webViewMayContainContent = false
    }

}

private enum PlayerEdgeTapSide {
    case left, right

    var navigationDirection: PlaybackNavigationDirection {
        switch self {
        case .left:
            return .back
        case .right:
            return .forward
        }
    }
}

private final class PlayerEdgeTapGestureRecognizer: UIGestureRecognizer {

    var edgeSideProvider: ((CGPoint) -> PlayerEdgeTapSide?)?
    var canBeginEdgeTap: ((PlayerEdgeTapSide) -> Bool)?
    var onEdgePressBegan: ((PlayerEdgeTapSide) -> Void)?
    var onEdgePressMoved: ((PlayerEdgeTapSide) -> Void)?
    var onEdgePressCancelled: ((PlayerEdgeTapSide) -> Void)?
    var onEdgeTapRecognized: ((PlayerEdgeTapSide) -> Void)?

    private var trackedTouch: UITouch?
    private var initialLocation = CGPoint.zero
    private var activeSide: PlayerEdgeTapSide?
    private var didMoveEnoughToCancelHighlight = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil,
              event.allTouches?.count == 1,
              let touch = touches.first,
              let view else {
            cancelOrFailActivePress()
            return
        }

        let location = touch.location(in: view)
        guard let side = edgeSideProvider?(location),
              canBeginEdgeTap?(side) == true else {
            state = .failed
            return
        }

        trackedTouch = touch
        initialLocation = location
        activeSide = side
        didMoveEnoughToCancelHighlight = false
        onEdgePressBegan?(side)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let view, let activeSide else { return }

        let location = trackedTouch.location(in: view)
        guard isTapStillValid(at: location, for: activeSide) else {
            cancelOrFailActivePress()
            return
        }

        if !didMoveEnoughToCancelHighlight,
           hasMovedEnoughToCancelHighlight(at: location) {
            didMoveEnoughToCancelHighlight = true
            onEdgePressMoved?(activeSide)
        }

        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let view, let activeSide else {
            cancelOrFailActivePress()
            return
        }

        let location = trackedTouch.location(in: view)
        guard isTapStillValid(at: location, for: activeSide) else {
            cancelOrFailActivePress()
            return
        }

        onEdgeTapRecognized?(activeSide)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelOrFailActivePress()
    }

    override func reset() {
        trackedTouch = nil
        initialLocation = .zero
        activeSide = nil
        didMoveEnoughToCancelHighlight = false
    }

    private func isTapStillValid(at location: CGPoint, for side: PlayerEdgeTapSide) -> Bool {
        guard edgeSideProvider?(location) == side else { return false }

        let distance = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
        return distance <= MobilePlayerGestureTuning.edgeTapMaximumMovement
    }

    private func hasMovedEnoughToCancelHighlight(at location: CGPoint) -> Bool {
        let distance = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
        return distance > MobilePlayerGestureTuning.edgeTapHighlightMaximumMovement
    }

    private func cancelOrFailActivePress() {
        if let activeSide {
            onEdgePressCancelled?(activeSide)
            state = .cancelled
        } else {
            state = .failed
        }
    }
}

private final class PlayerEdgeTapHighlightView: UIView {

    private let side: PlayerEdgeTapSide

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    init(side: PlayerEdgeTapSide) {
        self.side = side
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        configureGradient()
        gradientLayer.opacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    func setHighlighted(_ isHighlighted: Bool) {
        let currentOpacity = gradientLayer.presentation()?.opacity ?? gradientLayer.opacity
        gradientLayer.removeAnimation(forKey: "edgeTapHighlightOpacity")

        let targetOpacity: Float = isHighlighted ? 1 : 0
        gradientLayer.opacity = targetOpacity

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = currentOpacity
        animation.toValue = targetOpacity
        animation.duration = isHighlighted
            ? MobilePlayerGestureTuning.edgeTapHighlightFadeInDuration
            : MobilePlayerGestureTuning.edgeTapHighlightFadeOutDuration
        animation.timingFunction = isHighlighted
            ? CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            : CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        gradientLayer.add(animation, forKey: "edgeTapHighlightOpacity")
    }

    private func configureGradient() {
        let edgeColor = UIColor.black.withAlphaComponent(0.36).cgColor
        let midColor = UIColor.black.withAlphaComponent(0.18).cgColor
        let featherColor = UIColor.black.withAlphaComponent(0.05).cgColor
        let clearColor = UIColor.black.withAlphaComponent(0).cgColor
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.colors = side == .left
            ? [edgeColor, midColor, featherColor, clearColor]
            : [clearColor, featherColor, midColor, edgeColor]
        gradientLayer.locations = [0, 0.34, 0.72, 1]
    }
}

struct FourDirectionalPlayerContainerView: UIViewControllerRepresentable {

    private let initialConfig: MobilePlayerConfig
    private let onCoordinateUpdate: ((PlayerCoordinate) -> Void)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)
    private let onToggleChrome: (() -> Void)
    private let onZoomStateChange: ((Bool) -> Void)

    init(
        initialConfig: MobilePlayerConfig,
        onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void,
        onToggleChrome: @escaping () -> Void,
        onZoomStateChange: @escaping (Bool) -> Void
    ) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
        self.onToggleChrome = onToggleChrome
        self.onZoomStateChange = onZoomStateChange
    }

    func makeUIViewController(context: Context) -> FourDirectionalPlayerContainer {
        return FourDirectionalPlayerContainer(
            initialConfig: initialConfig,
            onCoordinateUpdate: onCoordinateUpdate,
            onPaginationAttempt: onPaginationAttempt,
            onUnavailableNavigation: onUnavailableNavigation,
            onToggleChrome: onToggleChrome,
            onZoomStateChange: onZoomStateChange
        )
    }

    func updateUIViewController(_ uiViewController: FourDirectionalPlayerContainer, context: Context) {}
}

class FourDirectionalPlayerContainer: UIViewController, FourDirectionalPlayerDataSource, MobilePlaybackControllerDisplay, UIGestureRecognizerDelegate {

    private let initialConfig: MobilePlayerConfig
    private let onCoordinateUpdate: ((PlayerCoordinate) -> Void)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)
    private let onToggleChrome: (() -> Void)
    private let onZoomStateChange: ((Bool) -> Void)

    private lazy var pagingVC = HorizontalPageViewController(fourDirectionalPlayerDataSource: self)
    private let leftEdgeTapHighlight = PlayerEdgeTapHighlightView(side: .left)
    private let rightEdgeTapHighlight = PlayerEdgeTapHighlightView(side: .right)
    private lazy var singleTapRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gesture.numberOfTapsRequired = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    private lazy var doubleTapRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    private lazy var edgeTapRecognizer: PlayerEdgeTapGestureRecognizer = {
        let gesture = PlayerEdgeTapGestureRecognizer()
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        gesture.edgeSideProvider = { [weak self] location in
            self?.edgeTapSide(at: location)
        }
        gesture.canBeginEdgeTap = { [weak self] side in
            self?.canRecognizeEdgeTap(on: side) == true
        }
        gesture.onEdgePressBegan = { [weak self] side in
            self?.beginEdgeTapHighlight(on: side)
        }
        gesture.onEdgePressMoved = { [weak self] side in
            self?.endEdgeTapHighlight(on: side)
        }
        gesture.onEdgePressCancelled = { [weak self] side in
            self?.endEdgeTapHighlight(on: side)
        }
        gesture.onEdgeTapRecognized = { [weak self] side in
            self?.handleEdgeTap(on: side)
        }
        return gesture
    }()
    private var renderedCoordinateCounts = [PlayerCoordinate: Int]()
    private var displayedCoordinate: PlayerCoordinate?
    private var pendingEdgeTapHighlightSide: PlayerEdgeTapSide?
    private var edgeTapHighlightWorkItem: DispatchWorkItem?
    private var edgeTapHighlightRequestId = 0

    init(
        initialConfig: MobilePlayerConfig,
        onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void,
        onToggleChrome: @escaping () -> Void,
        onZoomStateChange: @escaping (Bool) -> Void
    ) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
        self.onToggleChrome = onToggleChrome
        self.onZoomStateChange = onZoomStateChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        PonchoDrifellaMetalCardView.resetMotionCalibration()
        MobilePlaybackController.shared.subscribe(config: initialConfig, display: self)
        makePlayerBackgroundTransparent()
        pagingVC.onCurrentZoomStateChange = { [weak self] isZoomed in
            self?.onZoomStateChange(isZoomed)
        }
        addChild(pagingVC)
        view.addSubview(pagingVC.view)
        pagingVC.didMove(toParent: self)
        pagingVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pagingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pagingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pagingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        installEdgeTapHighlights()
        installTapGestures()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func makePlayerBackgroundTransparent() {
        view.makeBackgroundTransparent()
        pagingVC.makePlayerBackgroundTransparent()
    }

    deinit {
        edgeTapHighlightWorkItem?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func getCurrentCoordinate() -> (Int, Int) {
        return pagingVC.getCurrentCoordinate()
    }

    func navigate(_ direction: PlaybackNavigationDirection) {
        pagingVC.navigate(direction)
    }

    private func installTapGestures() {
        singleTapRecognizer.require(toFail: doubleTapRecognizer)
        view.addGestureRecognizer(edgeTapRecognizer)
        view.addGestureRecognizer(singleTapRecognizer)
        view.addGestureRecognizer(doubleTapRecognizer)
    }

    private func installEdgeTapHighlights() {
        [leftEdgeTapHighlight, rightEdgeTapHighlight].forEach { highlightView in
            highlightView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(highlightView)
        }

        NSLayoutConstraint.activate([
            leftEdgeTapHighlight.topAnchor.constraint(equalTo: view.topAnchor),
            leftEdgeTapHighlight.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftEdgeTapHighlight.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftEdgeTapHighlight.widthAnchor.constraint(equalToConstant: MobilePlayerGestureTuning.edgeTapHighlightWidth),

            rightEdgeTapHighlight.topAnchor.constraint(equalTo: view.topAnchor),
            rightEdgeTapHighlight.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rightEdgeTapHighlight.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightEdgeTapHighlight.widthAnchor.constraint(equalToConstant: MobilePlayerGestureTuning.edgeTapHighlightWidth)
        ])
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        if isEdgeTapLocation(gesture.location(in: view)) {
            return
        }

        onToggleChrome()
    }

    private func edgeTapSide(at location: CGPoint) -> PlayerEdgeTapSide? {
        let edgeWidth = min(MobilePlayerGestureTuning.edgeTapNavigationWidth, view.bounds.width / 2)
        if location.x <= edgeWidth {
            return .left
        }
        if location.x >= view.bounds.width - edgeWidth {
            return .right
        }
        return nil
    }

    private func isEdgeTapLocation(_ location: CGPoint) -> Bool {
        edgeTapSide(at: location) != nil
    }

    private func canRecognizeEdgeTap(on side: PlayerEdgeTapSide) -> Bool {
        let direction = side.navigationDirection
        return pagingVC.canNavigateWithoutAnimation(direction)
            || !pagingVC.hasNavigationDestination(direction)
    }

    private func beginEdgeTapHighlight(on side: PlayerEdgeTapSide) {
        cancelPendingEdgeTapHighlight()
        edgeTapHighlight(for: oppositeSide(of: side)).setHighlighted(false)
        edgeTapHighlight(for: side).setHighlighted(false)

        guard pagingVC.canNavigateWithoutAnimation(side.navigationDirection) else { return }

        pendingEdgeTapHighlightSide = side
        edgeTapHighlightRequestId += 1
        let requestId = edgeTapHighlightRequestId
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.edgeTapHighlightRequestId == requestId,
                  self.pendingEdgeTapHighlightSide == side else {
                return
            }

            self.pendingEdgeTapHighlightSide = nil
            self.edgeTapHighlightWorkItem = nil
            self.edgeTapHighlight(for: side).setHighlighted(true)
        }
        edgeTapHighlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MobilePlayerGestureTuning.edgeTapHighlightActivationDelay,
            execute: workItem
        )
    }

    private func endEdgeTapHighlight(on side: PlayerEdgeTapSide) {
        cancelPendingEdgeTapHighlight()
        edgeTapHighlightRequestId += 1
        edgeTapHighlight(for: side).setHighlighted(false)
    }

    private func handleEdgeTap(on side: PlayerEdgeTapSide) {
        let direction = side.navigationDirection
        guard pagingVC.canNavigateWithoutAnimation(direction) else {
            endEdgeTapHighlight(on: side)
            if !pagingVC.hasNavigationDestination(direction) {
                onUnavailableNavigation()
            }
            return
        }

        if cancelPendingEdgeTapHighlight(on: side) {
            flashEdgeTapHighlight(on: side)
        } else {
            endEdgeTapHighlight(on: side)
        }
        guard pagingVC.navigateWithoutAnimation(direction) else { return }

        Haptic.selectionChanged()
    }

    @discardableResult
    private func cancelPendingEdgeTapHighlight(on side: PlayerEdgeTapSide? = nil) -> Bool {
        guard let pendingSide = pendingEdgeTapHighlightSide else {
            return false
        }
        if let side, pendingSide != side {
            return false
        }

        edgeTapHighlightWorkItem?.cancel()
        edgeTapHighlightWorkItem = nil
        pendingEdgeTapHighlightSide = nil
        edgeTapHighlightRequestId += 1
        return true
    }

    private func flashEdgeTapHighlight(on side: PlayerEdgeTapSide) {
        edgeTapHighlight(for: oppositeSide(of: side)).setHighlighted(false)
        edgeTapHighlight(for: side).setHighlighted(true)
        edgeTapHighlightRequestId += 1
        let requestId = edgeTapHighlightRequestId

        DispatchQueue.main.asyncAfter(
            deadline: .now() + MobilePlayerGestureTuning.edgeTapHighlightTapFlashDuration
        ) { [weak self] in
            guard let self, self.edgeTapHighlightRequestId == requestId else { return }

            self.edgeTapHighlight(for: side).setHighlighted(false)
        }
    }

    private func oppositeSide(of side: PlayerEdgeTapSide) -> PlayerEdgeTapSide {
        switch side {
        case .left:
            return .right
        case .right:
            return .left
        }
    }

    private func edgeTapHighlight(for side: PlayerEdgeTapSide) -> PlayerEdgeTapHighlightView {
        switch side {
        case .left:
            return leftEdgeTapHighlight
        case .right:
            return rightEdgeTapHighlight
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        let location = gesture.location(in: view)
        guard !isEdgeTapLocation(location) else { return }

        pagingVC.toggleZoom(at: location, in: view)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === doubleTapRecognizer else { return true }

        return !isEdgeTapLocation(gestureRecognizer.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === singleTapRecognizer || gestureRecognizer === doubleTapRecognizer else {
            return true
        }

        return !isEdgeTapLocation(touch.location(in: view))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === edgeTapRecognizer || otherGestureRecognizer === edgeTapRecognizer
    }

    fileprivate func getToken(x: Int, y: Int) -> GeneratedToken {
        MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: PlayerCoordinate(x: x, y: y))
    }

    fileprivate func prepareDownloadableMediaWindow(
        for coordinate: (Int, Int),
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        MobilePlaybackController.shared.prepareDownloadableMediaWindow(
            uuid: initialConfig.id,
            coordinate: PlayerCoordinate(x: coordinate.0, y: coordinate.1),
            direction: direction
        )
    }

    fileprivate func clearDownloadableMediaWindow() {
        MobilePlaybackController.shared.clearDownloadableMediaWindow(uuid: initialConfig.id)
    }

    fileprivate func downloadableMediaDescriptor(for coordinate: (Int, Int)) -> DownloadableMediaDescriptor? {
        MobilePlaybackController.shared.downloadableMediaDescriptor(
            uuid: initialConfig.id,
            coordinate: PlayerCoordinate(x: coordinate.0, y: coordinate.1)
        )
    }

    fileprivate func canRenderCoordinate(_ coordinate: (Int, Int)) -> Bool {
        MobilePlaybackController.shared.canRender(
            uuid: initialConfig.id,
            coordinate: PlayerCoordinate(x: coordinate.0, y: coordinate.1)
        )
    }

    fileprivate func startHorizontalCoordinate(verticalIndex: Int) -> Int {
        MobilePlaybackController.shared.startHorizontalCoordinate(uuid: initialConfig.id, verticalIndex: verticalIndex)
    }

    fileprivate func didRenderCoordinate(_ coordinate: (Int, Int)) {
        let playerCoordinate = PlayerCoordinate(x: coordinate.0, y: coordinate.1)
        renderedCoordinateCounts[playerCoordinate, default: 0] += 1
        didUpdateRenderedCoordinates()
    }

    fileprivate func didCleanupCoordinate(_ coordinate: (Int, Int)) {
        let playerCoordinate = PlayerCoordinate(x: coordinate.0, y: coordinate.1)
        if let count = renderedCoordinateCounts[playerCoordinate], count > 1 {
            renderedCoordinateCounts[playerCoordinate] = count - 1
        } else {
            renderedCoordinateCounts.removeValue(forKey: playerCoordinate)
        }
        didUpdateRenderedCoordinates()
    }

    fileprivate func didAttemptUnavailableHorizontalNavigation() {
        onUnavailableNavigation()
    }

    fileprivate func didAttemptPagination() {
        onPaginationAttempt()
    }

    fileprivate func didDisplayCoordinate(_ coordinate: (Int, Int)) {
        updateDisplayedCoordinate(PlayerCoordinate(x: coordinate.0, y: coordinate.1))
    }

    private func didUpdateRenderedCoordinates() {
        if renderedCoordinateCounts.count == 1, let coordinate = renderedCoordinateCounts.keys.first {
            updateDisplayedCoordinate(coordinate)
        }
    }

    private func updateDisplayedCoordinate(_ coordinate: PlayerCoordinate) {
        guard displayedCoordinate != coordinate else { return }
        displayedCoordinate = coordinate
        onCoordinateUpdate(coordinate)
    }

}

private protocol FourDirectionalPlayerDataSource: AnyObject {

    func getToken(x: Int, y: Int) -> GeneratedToken
    func prepareDownloadableMediaWindow(
        for coordinate: (Int, Int),
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow?
    func clearDownloadableMediaWindow()
    func downloadableMediaDescriptor(for coordinate: (Int, Int)) -> DownloadableMediaDescriptor?
    func canRenderCoordinate(_ coordinate: (Int, Int)) -> Bool
    func startHorizontalCoordinate(verticalIndex: Int) -> Int
    func didRenderCoordinate(_ coordinate: (Int, Int))
    func didCleanupCoordinate(_ coordinate: (Int, Int))
    func didAttemptPagination()
    func didAttemptUnavailableHorizontalNavigation()
    func didDisplayCoordinate(_ coordinate: (Int, Int))

}

private final class PlayerZoomScrollView: UIScrollView {

    private var pagingPanGestureRecognizerIds = Set<ObjectIdentifier>()
    var pagingContentOffsetXRange: ClosedRange<CGFloat>?

    func registerPagingPanGesture(_ panGesture: UIPanGestureRecognizer) {
        pagingPanGestureRecognizerIds.insert(ObjectIdentifier(panGesture))
    }

    func allowsPagingPanFromCurrentZoomEdge(_ panGesture: UIPanGestureRecognizer) -> Bool {
        guard zoomScale > minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance else { return false }

        let velocity = panGesture.velocity(in: self)
        let isHorizontalPan = abs(velocity.x) > abs(velocity.y) * MobilePlayerGestureTuning.pageBoundaryRevealHorizontalIntentRatio
        guard isHorizontalPan else { return false }

        if velocity.x > 0 {
            return isAtLeftContentEdge
        } else if velocity.x < 0 {
            return isAtRightContentEdge
        } else {
            return false
        }
    }

    @objc func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard zoomScale > minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance else { return false }

        return gestureRecognizer === panGestureRecognizer && isPagingPanGesture(otherGestureRecognizer)
            || otherGestureRecognizer === panGestureRecognizer && isPagingPanGesture(gestureRecognizer)
    }

    private func isPagingPanGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }

        return pagingPanGestureRecognizerIds.contains(ObjectIdentifier(panGesture))
    }

    private var isAtLeftContentEdge: Bool {
        contentOffset.x <= minimumContentOffsetX + MobilePlayerGestureTuning.playerZoomEdgePaginationTolerance
    }

    private var isAtRightContentEdge: Bool {
        contentOffset.x >= maximumContentOffsetX - MobilePlayerGestureTuning.playerZoomEdgePaginationTolerance
    }

    private var minimumContentOffsetX: CGFloat {
        if let pagingContentOffsetXRange {
            return pagingContentOffsetXRange.lowerBound
        }

        return -adjustedContentInset.left
    }

    private var maximumContentOffsetX: CGFloat {
        if let pagingContentOffsetXRange {
            return pagingContentOffsetXRange.upperBound
        }

        return max(minimumContentOffsetX, contentSize.width - bounds.width + adjustedContentInset.right)
    }

}

private enum VideoAssetLayout {
    static func displaySize(at fileURL: URL) async -> CGSize? {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }

        async let naturalSize = track.load(.naturalSize)
        async let preferredTransform = track.load(.preferredTransform)

        guard let (loadedNaturalSize, loadedPreferredTransform) = try? await (naturalSize, preferredTransform) else {
            return nil
        }

        let transformedSize = loadedNaturalSize.applying(loadedPreferredTransform)
        let size = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }
}

private class SpecificPageViewController: UIViewController, UIScrollViewDelegate {

    private static let maximumCachedVideoSizeCount = 24

    private struct AnimatedRenderContext: Equatable {
        enum MediaKind: Equatable {
            case image, video, html
        }

        let descriptor: DownloadableMediaDescriptor
        let adjacentDescriptor: DownloadableMediaDescriptor?
        let fallbackHTML: String
        let mediaKind: MediaKind
    }

    private struct VideoSizeRequest: Equatable, Hashable {
        let descriptor: DownloadableMediaDescriptor
        let fileURL: URL
        let fileSize: Int?
        let contentModificationDate: Date?

        init(fileURL: URL, descriptor: DownloadableMediaDescriptor) {
            let resourceValues = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            self.descriptor = descriptor
            self.fileURL = fileURL
            self.fileSize = resourceValues?.fileSize
            self.contentModificationDate = resourceValues?.contentModificationDate
        }
    }

    private struct VideoSizeLoad {
        let request: VideoSizeRequest
        let task: Task<Void, Never>
    }

    private enum ZoomContentLayout: Equatable {
        case viewport
        case staticImage(CGSize)
    }

    private enum ZoomAllowedContent: Equatable {
        case fullContent
        case ponchoDrifellaCard

        func rect(in contentBounds: CGRect) -> CGRect {
            switch self {
            case .fullContent:
                return contentBounds
            case .ponchoDrifellaCard:
                return PonchoDrifellaMetalCardView.cardContentRect(in: contentBounds.size)
            }
        }
    }

    private weak var fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource?
    private let zoomScrollView = PlayerZoomScrollView()
    private let mediaContentView = UIView()
    private let htmlDocumentRenderQueue = DispatchQueue(
        label: "org.lil.nft-player.html-document-render",
        qos: .userInitiated
    )
    private lazy var mediaRenderer = FullscreenTokenMediaRenderer(containerView: mediaContentView)

    private(set) var horizontalIndex: Int
    private(set) var verticalIndex: Int

    private var renderedCoordinate: (Int, Int)?
    private var animatedRenderContext: AnimatedRenderContext?
    private var pendingAnimatedImageURL: URL?
    private var renderedAnimatedImageURL: URL?
    private var renderedAnimatedNextImageURL: URL?
    private var pendingAnimatedNextImageURL: URL?
    private var downloadableMediaCacheObserver: NSObjectProtocol?
    private var videoSizeLoad: VideoSizeLoad?
    private var cachedVideoSizes = [VideoSizeRequest: CGSize]()
    private var cachedVideoSizeRequests = [VideoSizeRequest]()
    private var willOrDidAppear = false
    private var isZoomInteractionActive = false
    private var zoomContentLayout: ZoomContentLayout = .viewport
    private var zoomAllowedContent: ZoomAllowedContent = .fullContent
    private var laidOutZoomViewportSize: CGSize = .zero
    var onZoomStateChange: (() -> Void)?
    var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    var isZoomed: Bool {
        zoomScrollView.zoomScale > zoomScrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance
    }

    init(horizontalIndex: Int, verticalIndex: Int, fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource?) {
        self.fourDirectionalPlayerDataSource = fourDirectionalPlayerDataSource
        self.horizontalIndex = horizontalIndex
        self.verticalIndex = verticalIndex
        super.init(nibName: nil, bundle: nil)
        renderCurrentItem()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        cancelVideoSizeLoad()
        removeDownloadableMediaCacheObserver()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureZoomScrollView()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cleanupDisplayedContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        willOrDidAppear = true
        renderCurrentItem()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        if laidOutZoomViewportSize != viewportSize {
            laidOutZoomViewportSize = viewportSize
            if isZoomed {
                resetZoom(animated: false)
            }
            updateZoomContentFrame(resetOffset: true)
        } else {
            updateZoomContentInsets()
            clampZoomContentOffsetIfNeeded()
        }
    }

    private func cleanupDisplayedContent() {
        resetZoom(animated: false)
        setZoomContentLayout(.viewport)
        clearAnimatedRenderContext()
        mediaRenderer.clearContent()
        if let renderedCoordinate = renderedCoordinate {
            fourDirectionalPlayerDataSource?.didCleanupCoordinate(renderedCoordinate)
        }
        renderedCoordinate = nil
    }

    func update(horizontalIndex: Int) {
        guard self.horizontalIndex != horizontalIndex else { return }
        cleanupDisplayedContent()
        self.horizontalIndex = horizontalIndex
    }

    func update(verticalIndex: Int) {
        guard self.verticalIndex != verticalIndex else { return }
        cleanupDisplayedContent()
        self.verticalIndex = verticalIndex
    }

    func toggleZoom(at location: CGPoint, in coordinateView: UIView) {
        guard isViewLoaded else { return }
        guard zoomScrollView.bounds.width > 0, zoomScrollView.bounds.height > 0 else { return }

        if isZoomed {
            resetZoom(animated: true)
            return
        }

        applyCachedCurrentVideoSizeIfAvailable()

        let locationInContent = coordinateView.convert(location, to: mediaContentView)
        let targetScale = min(
            MobilePlayerGestureTuning.playerDoubleTapZoomScale,
            zoomScrollView.maximumZoomScale
        )
        let zoomSize = CGSize(
            width: zoomScrollView.bounds.width / targetScale,
            height: zoomScrollView.bounds.height / targetScale
        )
        let allowedContentRect = zoomAllowedContentRect()
        let zoomOrigin = CGPoint(
            x: boundedZoomOrigin(
                centeredAt: locationInContent.x,
                zoomLength: zoomSize.width,
                allowedMin: allowedContentRect.minX,
                allowedMax: allowedContentRect.maxX
            ),
            y: boundedZoomOrigin(
                centeredAt: locationInContent.y,
                zoomLength: zoomSize.height,
                allowedMin: allowedContentRect.minY,
                allowedMax: allowedContentRect.maxY
            )
        )
        let zoomRect = CGRect(
            x: zoomOrigin.x,
            y: zoomOrigin.y,
            width: zoomSize.width,
            height: zoomSize.height
        )

        zoomScrollView.zoom(to: zoomRect, animated: true)
    }

    private func boundedZoomOrigin(
        centeredAt center: CGFloat,
        zoomLength: CGFloat,
        allowedMin: CGFloat,
        allowedMax: CGFloat
    ) -> CGFloat {
        let clampedCenter = min(max(center, allowedMin), allowedMax)
        let contentLength = allowedMax - allowedMin
        guard contentLength > zoomLength else {
            return (allowedMin + allowedMax - zoomLength) / 2
        }

        return min(max(clampedCenter - zoomLength / 2, allowedMin), allowedMax - zoomLength)
    }

    func resetZoom(animated: Bool) {
        guard isViewLoaded else { return }
        guard zoomScrollView.zoomScale != zoomScrollView.minimumZoomScale else {
            updateZoomInteraction()
            return
        }

        zoomScrollView.setZoomScale(zoomScrollView.minimumZoomScale, animated: animated)
        if !animated {
            updateZoomContentInsets()
            zoomScrollView.contentOffset = centeredZoomContentOffset
            updateZoomInteraction()
        }
    }

    func registerPagingPanGesture(_ panGesture: UIPanGestureRecognizer) {
        zoomScrollView.registerPagingPanGesture(panGesture)
    }

    func allowsPagingPanFromCurrentZoomEdge(_ panGesture: UIPanGestureRecognizer) -> Bool {
        zoomScrollView.allowsPagingPanFromCurrentZoomEdge(panGesture)
    }

    private func configureZoomScrollView() {
        makePlayerBackgroundTransparent()
        zoomScrollView.delegate = self
        zoomScrollView.minimumZoomScale = 1
        zoomScrollView.maximumZoomScale = MobilePlayerGestureTuning.playerMaximumZoomScale
        zoomScrollView.bounces = true
        zoomScrollView.bouncesZoom = true
        zoomScrollView.showsHorizontalScrollIndicator = false
        zoomScrollView.showsVerticalScrollIndicator = false
        zoomScrollView.contentInsetAdjustmentBehavior = .never
        zoomScrollView.hideAutomaticScrollEdgeEffects()

        zoomScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomScrollView)
        zoomScrollView.addSubview(mediaContentView)

        NSLayoutConstraint.activate([
            zoomScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        updateZoomContentFrame(resetOffset: true)
        updateZoomInteraction()
    }

    fileprivate func makePlayerBackgroundTransparent() {
        guard isViewLoaded else { return }

        applyPlayerBackgroundTransparency()
    }

    private func applyPlayerBackgroundTransparency() {
        view.makeBackgroundTransparent()
        mediaContentView.makeBackgroundTransparent()
        zoomScrollView.makeBackgroundTransparent()
        mediaRenderer.makePlayerBackgroundTransparent()
    }

    private func setZoomContentLayout(
        _ layout: ZoomContentLayout,
        allowedContent: ZoomAllowedContent = .fullContent
    ) {
        guard zoomContentLayout != layout || zoomAllowedContent != allowedContent else {
            updateZoomContentFrame(resetOffset: false)
            return
        }

        zoomContentLayout = layout
        zoomAllowedContent = allowedContent
        resetZoom(animated: false)
        updateZoomContentFrame(resetOffset: true)
    }

    private func updateZoomContentFrame(resetOffset: Bool) {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let contentSize = zoomContentSize(fitting: viewportSize)
        if zoomScrollView.zoomScale <= zoomScrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance {
            mediaContentView.transform = .identity
            mediaContentView.frame = CGRect(origin: .zero, size: contentSize)
            zoomScrollView.contentSize = contentSize
        }

        updateZoomContentInsets()
        if resetOffset {
            zoomScrollView.contentOffset = centeredZoomContentOffset
        } else {
            clampZoomContentOffsetIfNeeded()
        }
    }

    private func zoomContentSize(fitting viewportSize: CGSize) -> CGSize {
        switch zoomContentLayout {
        case .viewport:
            return viewportSize

        case .staticImage(let imageSize):
            guard imageSize.width > 0, imageSize.height > 0 else { return viewportSize }

            let scale = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
            return CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
        }
    }

    private func updateZoomContentInsets() {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let offsetRanges = zoomContentOffsetRanges()
        zoomScrollView.pagingContentOffsetXRange = zoomAllowedContent == .fullContent ? nil : offsetRanges.x
        let contentSize = zoomScrollView.contentSize
        let contentInset = UIEdgeInsets(
            top: -offsetRanges.y.lowerBound,
            left: -offsetRanges.x.lowerBound,
            bottom: offsetRanges.y.upperBound - (contentSize.height - viewportSize.height),
            right: offsetRanges.x.upperBound - (contentSize.width - viewportSize.width)
        )

        if zoomScrollView.contentInset != contentInset {
            zoomScrollView.contentInset = contentInset
        }
    }

    private var centeredZoomContentOffset: CGPoint {
        let offsetRanges = zoomContentOffsetRanges()
        return CGPoint(
            x: offsetRanges.x.lowerBound,
            y: offsetRanges.y.lowerBound
        )
    }

    private func clampZoomContentOffsetIfNeeded() {
        let offsetRanges = zoomContentOffsetRanges()
        let clampedOffset = CGPoint(
            x: min(max(zoomScrollView.contentOffset.x, offsetRanges.x.lowerBound), offsetRanges.x.upperBound),
            y: min(max(zoomScrollView.contentOffset.y, offsetRanges.y.lowerBound), offsetRanges.y.upperBound)
        )

        if zoomScrollView.contentOffset != clampedOffset {
            zoomScrollView.contentOffset = clampedOffset
        }
    }

    private func zoomContentOffsetRanges() -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return (x: 0...0, y: 0...0)
        }

        let scale = zoomScrollView.zoomScale
        let allowedContentRect = zoomAllowedContentRect()
        return (
            x: zoomContentOffsetRange(
                allowedMin: allowedContentRect.minX * scale,
                allowedMax: allowedContentRect.maxX * scale,
                viewportLength: viewportSize.width
            ),
            y: zoomContentOffsetRange(
                allowedMin: allowedContentRect.minY * scale,
                allowedMax: allowedContentRect.maxY * scale,
                viewportLength: viewportSize.height
            )
        )
    }

    private func zoomContentOffsetRange(
        allowedMin: CGFloat,
        allowedMax: CGFloat,
        viewportLength: CGFloat
    ) -> ClosedRange<CGFloat> {
        let contentLength = max(allowedMax - allowedMin, 0)
        guard contentLength > viewportLength else {
            let centeredOffset = (allowedMin + allowedMax - viewportLength) / 2
            return centeredOffset...centeredOffset
        }

        return allowedMin...(allowedMax - viewportLength)
    }

    private func zoomAllowedContentRect() -> CGRect {
        let contentBounds = CGRect(origin: .zero, size: mediaContentView.bounds.size)
        guard contentBounds.width > 0, contentBounds.height > 0 else { return .zero }

        let allowedRect = zoomAllowedContent.rect(in: contentBounds)
        guard !allowedRect.isNull, !allowedRect.isEmpty else { return contentBounds }

        let clippedRect = allowedRect.intersection(contentBounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else { return contentBounds }
        return clippedRect
    }

    private func updateZoomInteraction() {
        let shouldActivateZoomInteraction = isZoomed
        if zoomScrollView.panGestureRecognizer.isEnabled != shouldActivateZoomInteraction {
            zoomScrollView.panGestureRecognizer.isEnabled = shouldActivateZoomInteraction
        }
        guard isZoomInteractionActive != shouldActivateZoomInteraction else { return }

        isZoomInteractionActive = shouldActivateZoomInteraction
        onZoomStateChange?()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        mediaContentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateZoomContentInsets()
        clampZoomContentOffsetIfNeeded()
        updateZoomInteraction()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= scrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance {
            resetZoom(animated: true)
        } else {
            updateZoomContentInsets()
            clampZoomContentOffsetIfNeeded()
            updateZoomInteraction()
        }
    }

    func renderCurrentItem() {
        guard willOrDidAppear else { return }

        let newCoordinate = (horizontalIndex, verticalIndex)
        guard fourDirectionalPlayerDataSource?.canRenderCoordinate(newCoordinate) == true else {
            cleanupDisplayedContent()
            fourDirectionalPlayerDataSource?.clearDownloadableMediaWindow()
            return
        }
        if let renderedCoordinate = renderedCoordinate, renderedCoordinate == newCoordinate {
            return
        }

        beginRenderingCoordinate(newCoordinate)

        guard let token = fourDirectionalPlayerDataSource?.getToken(x: horizontalIndex, y: verticalIndex) else {
            fourDirectionalPlayerDataSource?.clearDownloadableMediaWindow()
            fourDirectionalPlayerDataSource?.didRenderCoordinate(newCoordinate)
            return
        }

        if token.usesPonchoDrifellaMetalRenderer {
            fourDirectionalPlayerDataSource?.clearDownloadableMediaWindow()
            renderPonchoDrifellaMetalCard(token)
        } else if let mediaWindow = prepareCurrentDownloadableMediaWindow() {
            let descriptor = mediaWindow.currentDescriptor
            switch descriptor.media {
            case .staticImage:
                renderImage(descriptor, fallbackHTML: token.html)
            case .animatedImage:
                renderAnimatedImage(
                    descriptor,
                    adjacentDescriptor: mediaWindow.adjacentDescriptor,
                    fallbackHTML: token.html
                )
            case .video:
                renderVideo(descriptor, fallbackHTML: token.html)
            case .html:
                renderHTMLDocument(descriptor, fallbackHTML: token.html)
            }
        } else {
            renderWebContent(token.html)
        }
        fourDirectionalPlayerDataSource?.didRenderCoordinate(newCoordinate)
    }

    fileprivate func refreshDownloadableMediaWindow() {
        guard willOrDidAppear else { return }
        guard let token = fourDirectionalPlayerDataSource?.getToken(x: horizontalIndex, y: verticalIndex),
              !token.usesPonchoDrifellaMetalRenderer else {
            fourDirectionalPlayerDataSource?.clearDownloadableMediaWindow()
            return
        }

        _ = prepareCurrentDownloadableMediaWindow()
    }

    private func prepareCurrentDownloadableMediaWindow() -> PlayerDownloadableMediaWindow? {
        fourDirectionalPlayerDataSource?.prepareDownloadableMediaWindow(
            for: (horizontalIndex, verticalIndex),
            direction: preferredPrefetchDirection
        )
    }

    fileprivate func replaceVisibleContentIfAvailable(
        targetHorizontalIndex: Int,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    ) -> Bool {
        guard canReplaceVisibleContent else { return false }

        let newCoordinate = (targetHorizontalIndex, verticalIndex)
        if let renderedCoordinate, renderedCoordinate == newCoordinate {
            return false
        }

        guard let descriptor = fourDirectionalPlayerDataSource?.downloadableMediaDescriptor(for: newCoordinate),
              descriptor.isStaticImage else {
            return false
        }

        if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            guard commitStaticImageReplacement(
                image,
                descriptor: descriptor,
                coordinate: newCoordinate,
                preferredPrefetchDirection: preferredPrefetchDirection
            ) else { return false }
            return true
        }

        return false
    }

    private var canReplaceVisibleContent: Bool {
        willOrDidAppear && isViewLoaded && view.window != nil
    }

    private func commitStaticImageReplacement(
        _ image: UIImage,
        descriptor: DownloadableMediaDescriptor,
        coordinate: (Int, Int),
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    ) -> Bool {
        guard fourDirectionalPlayerDataSource?.prepareDownloadableMediaWindow(
            for: coordinate,
            direction: preferredPrefetchDirection
        ) != nil else {
            return false
        }

        self.preferredPrefetchDirection = preferredPrefetchDirection
        horizontalIndex = coordinate.0
        resetZoom(animated: false)
        beginRenderingCoordinate(coordinate)
        clearAnimatedRenderContext()
        setZoomContentLayout(.staticImage(image.size))
        mediaRenderer.displayLoadedImage(image, key: descriptor)
        fourDirectionalPlayerDataSource?.didRenderCoordinate(coordinate)
        return true
    }

    private func beginRenderingCoordinate(_ coordinate: (Int, Int)) {
        if let renderedCoordinate {
            fourDirectionalPlayerDataSource?.didCleanupCoordinate(renderedCoordinate)
        }
        renderedCoordinate = coordinate
    }

    private func renderImage(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        clearAnimatedRenderContext()
        mediaRenderer.renderImage(
            key: descriptor,
            hideImageUntilLoaded: false,
            load: { completion in
                DownloadableMediaCache.shared.loadImage(for: descriptor, completion: completion)
            },
            fallbackToWebContent: { [weak self] in
                self?.renderWebContent(fallbackHTML)
            },
            onLoadedImage: { [weak self] image in
                self?.setZoomContentLayout(.staticImage(image.size))
            }
        )
    }

    private func renderWebContent(_ html: String) {
        clearAnimatedRenderContext()
        setZoomContentLayout(.viewport)
        renderAnimatedFallbackWebContent(html)
    }

    private func renderPonchoDrifellaMetalCard(_ token: GeneratedToken) {
        clearAnimatedRenderContext()
        setZoomContentLayout(.viewport, allowedContent: .ponchoDrifellaCard)
        mediaRenderer.renderPonchoDrifellaMetalCard(tokenId: token.id)
    }

    private func renderAnimatedFallbackWebContent(_ html: String) {
        setZoomContentLayout(.viewport)
        mediaRenderer.renderWebContent(html)
    }

    private func renderAnimatedImage(
        _ descriptor: DownloadableMediaDescriptor,
        adjacentDescriptor: DownloadableMediaDescriptor?,
        fallbackHTML: String
    ) {
        renderDownloadableWebMedia(
            descriptor,
            adjacentDescriptor: adjacentDescriptor,
            fallbackHTML: fallbackHTML,
            mediaKind: .image
        )
    }

    private func renderVideo(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        renderDownloadableWebMedia(descriptor, fallbackHTML: fallbackHTML, mediaKind: .video)
    }

    private func renderHTMLDocument(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        renderDownloadableWebMedia(descriptor, fallbackHTML: fallbackHTML, mediaKind: .html)
    }

    private func renderDownloadableWebMedia(
        _ descriptor: DownloadableMediaDescriptor,
        adjacentDescriptor: DownloadableMediaDescriptor? = nil,
        fallbackHTML: String,
        mediaKind: AnimatedRenderContext.MediaKind
    ) {
        setZoomContentLayout(.viewport)
        setAnimatedRenderContext(
            AnimatedRenderContext(
                descriptor: descriptor,
                adjacentDescriptor: adjacentDescriptor,
                fallbackHTML: fallbackHTML,
                mediaKind: mediaKind
            )
        )
        renderAvailableAnimatedLocalContent()
    }

    private func renderAvailableAnimatedLocalContent() {
        guard let context = animatedRenderContext else { return }

        let imageCache = DownloadableMediaCache.shared
        guard let localFileURL = imageCache.localFileURL(for: context.descriptor) else {
            cancelVideoSizeLoad()
            clearAnimatedImageURLState()
            mediaRenderer.clearContent()
            return
        }

        let nextLocalFileURL = context.adjacentDescriptor.flatMap {
            imageCache.localFileURL(for: $0)
        }
        if pendingAnimatedImageURL == localFileURL {
            return
        }
        if renderedAnimatedImageURL == localFileURL {
            guard renderedAnimatedNextImageURL != nextLocalFileURL else { return }
            guard pendingAnimatedNextImageURL != nextLocalFileURL else { return }
            guard let nextLocalFileURL else {
                pendingAnimatedNextImageURL = nil
                renderedAnimatedNextImageURL = nil
                return
            }

            pendingAnimatedNextImageURL = nextLocalFileURL
            mediaRenderer.preloadWebImage(nextLocalFileURL) { [weak self] didPreload in
                guard let self,
                      self.animatedRenderContext == context,
                      self.renderedAnimatedImageURL == localFileURL else {
                    return
                }

                if self.pendingAnimatedNextImageURL == nextLocalFileURL {
                    self.pendingAnimatedNextImageURL = nil
                }
                guard didPreload else { return }

                self.renderedAnimatedNextImageURL = nextLocalFileURL
            }
            return
        }

        let html: String
        switch context.mediaKind {
        case .image:
            if let imageSize = imageSize(at: localFileURL) {
                setZoomContentLayout(.staticImage(imageSize))
            }
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: localFileURL.absoluteString,
                nextImageURL: nextLocalFileURL?.absoluteString
            )
        case .video:
            loadVideoSizeIfNeeded(at: localFileURL, context: context)
            html = DownloadableTokenHTML.createVideoHTML(videoURL: localFileURL.absoluteString)
        case .html:
            renderCachedHTMLDocument(
                fileURL: localFileURL,
                context: context,
                imageCache: imageCache
            )
            return
        }

        renderAnimatedLocalWebContent(
            html,
            fileURL: localFileURL,
            context: context,
            htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
            readAccessURL: imageCache.webViewReadAccessURL
        )
    }

    private func renderAnimatedLocalWebContent(
        _ html: String,
        fileURL: URL,
        context: AnimatedRenderContext,
        htmlDirectoryURL: URL,
        readAccessURL: URL
    ) {
        pendingAnimatedImageURL = fileURL
        mediaRenderer.renderLocalWebContent(
            html,
            htmlDirectoryURL: htmlDirectoryURL,
            readAccessURL: readAccessURL,
            onLoadSuccess: { [weak self] in
                guard let self,
                      self.animatedRenderContext == context,
                      self.pendingAnimatedImageURL == fileURL else {
                    return
                }

                self.clearAnimatedImageURLState()
                self.renderedAnimatedImageURL = fileURL
                self.renderAvailableAnimatedLocalContent()
            },
            onLoadFailure: { [weak self] in
                guard let self,
                      self.animatedRenderContext == context,
                      self.pendingAnimatedImageURL == fileURL else {
                    return
                }

                self.clearAnimatedRenderContext()
                self.renderAnimatedFallbackWebContent(context.fallbackHTML)
            }
        )
    }

    private func renderCachedHTMLDocument(
        fileURL: URL,
        context: AnimatedRenderContext,
        imageCache: DownloadableMediaCache
    ) {
        mediaRenderer.clearContent()
        pendingAnimatedImageURL = fileURL
        htmlDocumentRenderQueue.async {
            let renderedDocument = (try? String(contentsOf: fileURL, encoding: .utf8)).map { documentHTML in
                (
                    html: DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                        documentHTML: documentHTML,
                        baseURL: imageCache.downloadedSourceURL(for: context.descriptor).absoluteString
                    ),
                    viewportSize: DownloadableTokenHTMLLayout.rootSVGViewBoxSize(in: documentHTML)
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.animatedRenderContext == context,
                      self.pendingAnimatedImageURL == fileURL else {
                    return
                }

                guard let renderedDocument else {
                    self.clearAnimatedRenderContext()
                    self.renderAnimatedFallbackWebContent(context.fallbackHTML)
                    return
                }

                if let viewportSize = renderedDocument.viewportSize {
                    self.setZoomContentLayout(.staticImage(viewportSize))
                } else {
                    self.setZoomContentLayout(.viewport)
                }
                self.renderAnimatedLocalWebContent(
                    renderedDocument.html,
                    fileURL: fileURL,
                    context: context,
                    htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
                    readAccessURL: imageCache.webViewHTMLDirectoryURL
                )
            }
        }
    }

    private func imageSize(at fileURL: URL) -> CGSize? {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        let size = CGSize(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue))
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    private func loadVideoSizeIfNeeded(at fileURL: URL, context: AnimatedRenderContext) {
        let request = VideoSizeRequest(fileURL: fileURL, descriptor: context.descriptor)

        if let videoSizeLoad, videoSizeLoad.request != request {
            cancelVideoSizeLoad()
        }

        if let cachedSize = cachedVideoSizes[request] {
            applyVideoSizeIfCurrent(cachedSize, for: request)
            return
        }

        guard videoSizeLoad == nil else { return }

        let task = Task.detached(priority: .utility) { [fileURL, request] in
            let size = await VideoAssetLayout.displaySize(at: fileURL)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard !Task.isCancelled,
                      let self,
                      self.videoSizeLoad?.request == request else {
                    return
                }

                self.videoSizeLoad = nil
                guard let size else { return }

                self.cacheVideoSize(size, for: request)
                self.applyVideoSizeIfCurrent(size, for: request)
            }
        }

        videoSizeLoad = VideoSizeLoad(request: request, task: task)
    }

    private func cacheVideoSize(_ size: CGSize, for request: VideoSizeRequest) {
        if cachedVideoSizes[request] == nil {
            cachedVideoSizeRequests.append(request)
        }
        cachedVideoSizes[request] = size

        while cachedVideoSizeRequests.count > Self.maximumCachedVideoSizeCount {
            let removedRequest = cachedVideoSizeRequests.removeFirst()
            cachedVideoSizes.removeValue(forKey: removedRequest)
        }
    }

    private func applyCachedCurrentVideoSizeIfAvailable() {
        guard let context = animatedRenderContext,
              context.mediaKind == .video,
              let fileURL = DownloadableMediaCache.shared.localFileURL(for: context.descriptor) else {
            return
        }

        let request = VideoSizeRequest(fileURL: fileURL, descriptor: context.descriptor)
        guard let cachedSize = cachedVideoSizes[request] else { return }

        applyVideoSizeIfCurrent(cachedSize, for: request)
    }

    private func applyVideoSizeIfCurrent(_ size: CGSize, for request: VideoSizeRequest) {
        guard let context = animatedRenderContext,
              context.mediaKind == .video,
              context.descriptor == request.descriptor,
              DownloadableMediaCache.shared.localFileURL(for: request.descriptor) == request.fileURL,
              VideoSizeRequest(fileURL: request.fileURL, descriptor: request.descriptor) == request,
              !isZoomed,
              !zoomScrollView.isZooming else {
            return
        }

        setZoomContentLayout(.staticImage(size))
    }

    private func cancelVideoSizeLoad() {
        videoSizeLoad?.task.cancel()
        videoSizeLoad = nil
    }

    private func setAnimatedRenderContext(_ context: AnimatedRenderContext) {
        cancelVideoSizeLoad()
        animatedRenderContext = context
        clearAnimatedImageURLState()
        installDownloadableMediaCacheObserverIfNeeded()
    }

    private func clearAnimatedRenderContext() {
        cancelVideoSizeLoad()
        animatedRenderContext = nil
        clearAnimatedImageURLState()
        removeDownloadableMediaCacheObserver()
    }

    private func clearAnimatedImageURLState() {
        pendingAnimatedImageURL = nil
        renderedAnimatedImageURL = nil
        renderedAnimatedNextImageURL = nil
        pendingAnimatedNextImageURL = nil
    }

    private func installDownloadableMediaCacheObserverIfNeeded() {
        guard downloadableMediaCacheObserver == nil else { return }

        downloadableMediaCacheObserver = NotificationCenter.default.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderAvailableAnimatedLocalContent()
        }
    }

    private func removeDownloadableMediaCacheObserver() {
        guard let downloadableMediaCacheObserver else { return }

        NotificationCenter.default.removeObserver(downloadableMediaCacheObserver)
        self.downloadableMediaCacheObserver = nil
    }

}

private class HorizontalPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    let pageA: SpecificPageViewController
    let pageB: SpecificPageViewController
    let pageC: SpecificPageViewController

    private var isPageTransitioning = false
    private var pendingNavigationDirection: PlaybackNavigationDirection?
    private var configuredPagingPanGestures = Set<ObjectIdentifier>()
    private var didNotifyPaginationAttemptDuringCurrentPan = false
    private var didNotifyUnavailableNavigationDuringCurrentPan = false
    private var isPagingScrollEnabled = true
    private var isCurrentPageZoomed = false
    private var lastSettledCoordinate: (horizontalIndex: Int, verticalIndex: Int)?
    private var zoomedPagingPanRestingOffsets = [ObjectIdentifier: CGFloat]()
    private var unlockedZoomedPagingPanGestures = Set<ObjectIdentifier>()
    private weak var fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource?
    var onCurrentZoomStateChange: ((Bool) -> Void)?

    init(fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource) {
        self.fourDirectionalPlayerDataSource = fourDirectionalPlayerDataSource
        pageA = SpecificPageViewController(horizontalIndex: 0, verticalIndex: 0, fourDirectionalPlayerDataSource: fourDirectionalPlayerDataSource)
        pageB = SpecificPageViewController(horizontalIndex: 1, verticalIndex: 0, fourDirectionalPlayerDataSource: fourDirectionalPlayerDataSource)
        pageC = SpecificPageViewController(horizontalIndex: -1, verticalIndex: 0, fourDirectionalPlayerDataSource: fourDirectionalPlayerDataSource)
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: MobilePlayerGestureTuning.playerPageGap]
        )
        [pageA, pageB, pageC].forEach { page in
            page.onZoomStateChange = { [weak self] in
                self?.updatePagingScrollEnabled()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        makePlayerBackgroundTransparent()
        dataSource = self
        delegate = self
        setViewControllers([pageA], direction: .forward, animated: false, completion: nil)
        configurePagingScrollViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePagingScrollViews()
    }

    private var pagingScrollViews: [UIScrollView] {
        view.subviews.compactMap { $0 as? UIScrollView }
    }

    private var currentPage: SpecificPageViewController? {
        viewControllers?.first as? SpecificPageViewController
    }

    func makePlayerBackgroundTransparent() {
        view.makeBackgroundTransparent()
        pagingScrollViews.forEach {
            $0.makeBackgroundTransparent()
        }
        pageA.makePlayerBackgroundTransparent()
        pageB.makePlayerBackgroundTransparent()
        pageC.makePlayerBackgroundTransparent()
    }

    func toggleZoom(at location: CGPoint, in coordinateView: UIView) {
        currentPage?.toggleZoom(at: location, in: coordinateView)
        updatePagingScrollEnabled()
    }

    private func resetCurrentZoom(animated: Bool) {
        currentPage?.resetZoom(animated: animated)
        updatePagingScrollEnabled()
    }

    private func resetAllZoom(animated: Bool) {
        [pageA, pageB, pageC].forEach { page in
            page.resetZoom(animated: animated)
        }
        updatePagingScrollEnabled()
    }

    private func configurePagingScrollViews() {
        var didConfigureNewPagingScrollView = false
        pagingScrollViews.forEach { scrollView in
            scrollView.makeBackgroundTransparent()
            scrollView.hideAutomaticScrollEdgeEffects()
            let panGesture = scrollView.panGestureRecognizer
            let panGestureId = ObjectIdentifier(panGesture)
            if !configuredPagingPanGestures.contains(panGestureId) {
                [pageA, pageB, pageC].forEach { page in
                    page.registerPagingPanGesture(panGesture)
                }
                panGesture.addTarget(self, action: #selector(handlePagingPan(_:)))
                configuredPagingPanGestures.insert(panGestureId)
                didConfigureNewPagingScrollView = true
            }
        }
        updatePagingScrollEnabled(force: didConfigureNewPagingScrollView)
    }

    private func updatePagingScrollEnabled(force: Bool = false) {
        let currentPageIsZoomed = currentPage?.isZoomed == true
        let shouldEnablePaging = true
        if force || isPagingScrollEnabled != shouldEnablePaging {
            isPagingScrollEnabled = shouldEnablePaging
            pagingScrollViews.forEach { scrollView in
                if scrollView.isScrollEnabled != shouldEnablePaging {
                    scrollView.isScrollEnabled = shouldEnablePaging
                }
            }
        }

        updateCurrentZoomState(currentPageIsZoomed)
    }

    private func updateCurrentZoomState(_ isZoomed: Bool) {
        guard isCurrentPageZoomed != isZoomed else { return }

        isCurrentPageZoomed = isZoomed
        onCurrentZoomStateChange?(isZoomed)
    }

    @objc private func handlePagingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            didNotifyPaginationAttemptDuringCurrentPan = false
            didNotifyUnavailableNavigationDuringCurrentPan = false
            beginZoomedPagingPanIfNeeded(gesture)

        case .changed:
            updateZoomedPagingPanLock(for: gesture)

            guard !didNotifyPaginationAttemptDuringCurrentPan,
                  !didNotifyUnavailableNavigationDuringCurrentPan else { return }

            let translation = gesture.translation(in: view)
            let hasHorizontalIntent = abs(translation.x) > MobilePlayerGestureTuning.pageBoundaryRevealTranslation
                && abs(translation.x) > abs(translation.y) * MobilePlayerGestureTuning.pageBoundaryRevealHorizontalIntentRatio
            guard hasHorizontalIntent else { return }

            let targetOffset = translation.x > 0 ? -1 : 1
            let coordinate = getCurrentCoordinate()
            guard !canRender(horizontalIndex: coordinate.0 + targetOffset, verticalIndex: coordinate.1) else {
                didNotifyPaginationAttemptDuringCurrentPan = true
                fourDirectionalPlayerDataSource?.didAttemptPagination()
                return
            }

            didNotifyUnavailableNavigationDuringCurrentPan = true
            fourDirectionalPlayerDataSource?.didAttemptUnavailableHorizontalNavigation()

        case .ended, .cancelled, .failed:
            didNotifyPaginationAttemptDuringCurrentPan = false
            didNotifyUnavailableNavigationDuringCurrentPan = false
            endZoomedPagingPan(gesture)

        default:
            break
        }
    }

    private func beginZoomedPagingPanIfNeeded(_ gesture: UIPanGestureRecognizer) {
        guard currentPage?.isZoomed == true,
              let scrollView = pagingScrollView(for: gesture) else { return }

        let gestureId = ObjectIdentifier(gesture)
        zoomedPagingPanRestingOffsets[gestureId] = scrollView.contentOffset.x
        unlockedZoomedPagingPanGestures.remove(gestureId)
    }

    private func updateZoomedPagingPanLock(for gesture: UIPanGestureRecognizer) {
        guard let currentPage,
              currentPage.isZoomed,
              let scrollView = pagingScrollView(for: gesture) else { return }

        let gestureId = ObjectIdentifier(gesture)
        let restingOffsetX = zoomedPagingPanRestingOffsets[gestureId] ?? scrollView.contentOffset.x
        if currentPage.allowsPagingPanFromCurrentZoomEdge(gesture) {
            if !unlockedZoomedPagingPanGestures.contains(gestureId) {
                scrollView.contentOffset.x = restingOffsetX
                gesture.setTranslation(.zero, in: view)
                zoomedPagingPanRestingOffsets[gestureId] = scrollView.contentOffset.x
                unlockedZoomedPagingPanGestures.insert(gestureId)
            }
        } else if !unlockedZoomedPagingPanGestures.contains(gestureId) {
            scrollView.contentOffset.x = restingOffsetX
        }
    }

    private func endZoomedPagingPan(_ gesture: UIPanGestureRecognizer) {
        let gestureId = ObjectIdentifier(gesture)
        zoomedPagingPanRestingOffsets.removeValue(forKey: gestureId)
        unlockedZoomedPagingPanGestures.remove(gestureId)
    }

    private func pagingScrollView(for gesture: UIPanGestureRecognizer) -> UIScrollView? {
        if let scrollView = gesture.view as? UIScrollView {
            return scrollView
        }

        return pagingScrollViews.first { $0.panGestureRecognizer === gesture }
    }

    func getCurrentCoordinate() -> (Int, Int) {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return (0, 0) }
        return (currentPage.horizontalIndex, currentPage.verticalIndex)
    }

    private func update(currentHorizontalIndex: Int) {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return }
        switch currentPage {
        case pageA:
            pageA.update(horizontalIndex: currentHorizontalIndex)
            pageB.update(horizontalIndex: currentHorizontalIndex + 1)
            pageC.update(horizontalIndex: currentHorizontalIndex - 1)
        case pageB:
            pageA.update(horizontalIndex: currentHorizontalIndex - 1)
            pageB.update(horizontalIndex: currentHorizontalIndex)
            pageC.update(horizontalIndex: currentHorizontalIndex + 1)
        case pageC:
            pageA.update(horizontalIndex: currentHorizontalIndex + 1)
            pageB.update(horizontalIndex: currentHorizontalIndex - 1)
            pageC.update(horizontalIndex: currentHorizontalIndex)
        default:
            break
        }
    }

    private func update(verticalIndex: Int) {
        pageA.update(verticalIndex: verticalIndex)
        pageB.update(verticalIndex: verticalIndex)
        pageC.update(verticalIndex: verticalIndex)
    }

    private func restartCollection() {
        let coordinate = getCurrentCoordinate()
        let targetHorizontalIndex = fourDirectionalPlayerDataSource?.startHorizontalCoordinate(verticalIndex: coordinate.1) ?? 0
        jumpToCoordinate(horizontalIndex: targetHorizontalIndex, verticalIndex: coordinate.1)
    }

    private func jumpToCoordinate(horizontalIndex: Int, verticalIndex: Int) {
        guard canRender(horizontalIndex: horizontalIndex, verticalIndex: verticalIndex) else { return }

        isPageTransitioning = true
        resetAllZoom(animated: false)
        pageA.preferredPrefetchDirection = .forward
        pageB.preferredPrefetchDirection = .forward
        pageC.preferredPrefetchDirection = .forward
        pageA.update(horizontalIndex: horizontalIndex)
        pageA.update(verticalIndex: verticalIndex)
        pageB.update(horizontalIndex: horizontalIndex + 1)
        pageB.update(verticalIndex: verticalIndex)
        pageC.update(horizontalIndex: horizontalIndex - 1)
        pageC.update(verticalIndex: verticalIndex)

        setViewControllers([pageA], direction: .forward, animated: false) { [weak self] _ in
            guard let self else { return }

            self.pageA.renderCurrentItem()
            self.didDisplayRenderableCoordinate(horizontalIndex: horizontalIndex, verticalIndex: verticalIndex)
            self.isPageTransitioning = false
            self.performPendingNavigationIfNeeded()
        }
    }

    private func didSettleOnCurrentPage() -> Bool {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return false }
        guard canRender(horizontalIndex: currentPage.horizontalIndex, verticalIndex: currentPage.verticalIndex) else {
            recoverFromInvalidCurrentPage(currentPage)
            return false
        }

        update(currentHorizontalIndex: currentPage.horizontalIndex)
        updatePagingScrollEnabled()
        didDisplayRenderableCoordinate(horizontalIndex: currentPage.horizontalIndex, verticalIndex: currentPage.verticalIndex)
        return true
    }

    private func didDisplayRenderableCoordinate(horizontalIndex: Int, verticalIndex: Int) {
        lastSettledCoordinate = (horizontalIndex, verticalIndex)
        fourDirectionalPlayerDataSource?.didDisplayCoordinate((horizontalIndex, verticalIndex))
    }

    private func recoverFromInvalidCurrentPage(_ currentPage: SpecificPageViewController) {
        guard let recoveryCoordinate = recoveryCoordinate(
            horizontalIndex: currentPage.horizontalIndex,
            verticalIndex: currentPage.verticalIndex
        ) else {
            updatePagingScrollEnabled()
            isPageTransitioning = false
            return
        }

        jumpToCoordinate(horizontalIndex: recoveryCoordinate.horizontalIndex, verticalIndex: recoveryCoordinate.verticalIndex)
    }

    private func recoveryCoordinate(
        horizontalIndex: Int,
        verticalIndex: Int
    ) -> (horizontalIndex: Int, verticalIndex: Int)? {
        for candidateHorizontalIndex in [horizontalIndex - 1, horizontalIndex + 1] {
            if canRender(horizontalIndex: candidateHorizontalIndex, verticalIndex: verticalIndex) {
                return (candidateHorizontalIndex, verticalIndex)
            }
        }

        if let lastSettledCoordinate,
           canRender(
            horizontalIndex: lastSettledCoordinate.horizontalIndex,
            verticalIndex: lastSettledCoordinate.verticalIndex
           ) {
            return lastSettledCoordinate
        }

        let startHorizontalIndex = fourDirectionalPlayerDataSource?.startHorizontalCoordinate(verticalIndex: verticalIndex) ?? 0
        if canRender(horizontalIndex: startHorizontalIndex, verticalIndex: verticalIndex) {
            return (startHorizontalIndex, verticalIndex)
        }

        return nil
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        switch vc {
        case pageA:
            return adjacentHorizontalPage(from: pageA, targetPage: pageC, offset: -1)
        case pageB:
            return adjacentHorizontalPage(from: pageB, targetPage: pageA, offset: -1)
        case pageC:
            return adjacentHorizontalPage(from: pageC, targetPage: pageB, offset: -1)
        default:
            return pageA
        }
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        switch vc {
        case pageA:
            return adjacentHorizontalPage(from: pageA, targetPage: pageB, offset: 1)
        case pageB:
            return adjacentHorizontalPage(from: pageB, targetPage: pageC, offset: 1)
        case pageC:
            return adjacentHorizontalPage(from: pageC, targetPage: pageA, offset: 1)
        default:
            return pageA
        }
    }

    private func adjacentHorizontalPage(
        from sourcePage: SpecificPageViewController,
        targetPage: SpecificPageViewController,
        offset: Int
    ) -> UIViewController? {
        let targetIndex = sourcePage.horizontalIndex + offset
        guard canRender(horizontalIndex: targetIndex, verticalIndex: sourcePage.verticalIndex) else { return nil }
        targetPage.preferredPrefetchDirection = offset < 0 ? .backward : .forward
        targetPage.update(horizontalIndex: targetIndex)
        return targetPage
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let destinationPage = pendingViewControllers.first as? SpecificPageViewController else { return }
        fourDirectionalPlayerDataSource?.didAttemptPagination()
        isPageTransitioning = true
        destinationPage.renderCurrentItem()
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        isPageTransitioning = false
        guard didSettleOnCurrentPage() else { return }

        if !completed {
            currentPage?.refreshDownloadableMediaWindow()
        }
        performPendingNavigationIfNeeded()
    }

    @discardableResult
    private func performPageTransition(
        _ direction: UIPageViewController.NavigationDirection,
        animated: Bool,
        completion: @escaping () -> Void
    ) -> Bool {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else {
            completion()
            return false
        }

        let targetViewController: UIViewController?
        switch direction {
        case .reverse:
            targetViewController = pageViewController(self, viewControllerBefore: currentPage)
        case .forward:
            targetViewController = pageViewController(self, viewControllerAfter: currentPage)
        default:
            completion()
            return false
        }

        guard let targetViewController else {
            completion()
            return false
        }

        resetCurrentZoom(animated: false)
        fourDirectionalPlayerDataSource?.didAttemptPagination()

        if let destinationPage = targetViewController as? SpecificPageViewController {
            destinationPage.renderCurrentItem()
        }

        setViewControllers([targetViewController], direction: direction, animated: animated) { _ in
            guard self.didSettleOnCurrentPage() else { return }
            completion()
        }
        return true
    }

    func navigate(_ direction: PlaybackNavigationDirection) {
        switch direction {
        case .back, .forward:
            guard canStartNavigation else { return }
            isPageTransitioning = true
            let pageDirection: UIPageViewController.NavigationDirection = direction == .back ? .reverse : .forward
            let didStartTransition = performPageTransition(pageDirection, animated: true) { [weak self] in
                self?.isPageTransitioning = false
                self?.performPendingNavigationIfNeeded()
            }
            if !didStartTransition {
                isPageTransitioning = false
            }
        case .restartCollection:
            guard canStartNavigation else {
                pendingNavigationDirection = direction
                return
            }
            restartCollection()
        }
    }

    @discardableResult
    func navigateWithoutAnimation(_ direction: PlaybackNavigationDirection) -> Bool {
        guard canNavigateWithoutAnimation(direction) else { return false }

        if replaceCurrentPageContentWithoutPageControllerTransition(direction) {
            return true
        }

        return performUnanimatedPageTransition(direction)
    }

    private func replaceCurrentPageContentWithoutPageControllerTransition(_ direction: PlaybackNavigationDirection) -> Bool {
        guard direction == .back || direction == .forward,
              let currentPage = viewControllers?.first as? SpecificPageViewController else {
            return false
        }

        let targetOffset = direction == .back ? -1 : 1
        let targetHorizontalIndex = currentPage.horizontalIndex + targetOffset

        let prefetchDirection: DownloadableMediaCache.PrefetchDirection = direction == .back ? .backward : .forward
        guard currentPage.replaceVisibleContentIfAvailable(
            targetHorizontalIndex: targetHorizontalIndex,
            preferredPrefetchDirection: prefetchDirection
        ) else { return false }

        fourDirectionalPlayerDataSource?.didAttemptPagination()
        guard didSettleOnCurrentPage() else { return true }
        reloadPageControllerAfterInPlaceNavigation(direction) { [weak self] in
            self?.performPendingNavigationIfNeeded()
        }
        return true
    }

    private func reloadPageControllerAfterInPlaceNavigation(
        _ direction: PlaybackNavigationDirection,
        completion: @escaping () -> Void
    ) {
        guard let currentPage else {
            completion()
            return
        }

        isPageTransitioning = true
        let pageDirection: UIPageViewController.NavigationDirection = direction == .back ? .reverse : .forward
        dataSource = nil
        setViewControllers([currentPage], direction: pageDirection, animated: false) { [weak self] _ in
            guard let self else { return }

            self.dataSource = self
            self.configurePagingScrollViews()
            self.isPageTransitioning = false
            completion()
        }
    }

    private func performUnanimatedPageTransition(_ direction: PlaybackNavigationDirection) -> Bool {
        isPageTransitioning = true
        let pageDirection: UIPageViewController.NavigationDirection = direction == .back ? .reverse : .forward
        let didStartTransition = performPageTransition(
            pageDirection,
            animated: false
        ) { [weak self] in
            self?.isPageTransitioning = false
            self?.performPendingNavigationIfNeeded()
        }
        if !didStartTransition {
            isPageTransitioning = false
        }
        return didStartTransition
    }

    func canNavigateWithoutAnimation(_ direction: PlaybackNavigationDirection) -> Bool {
        guard direction == .back || direction == .forward else { return false }
        guard canStartNavigation else { return false }

        return hasNavigationDestination(direction)
    }

    func hasNavigationDestination(_ direction: PlaybackNavigationDirection) -> Bool {
        guard direction == .back || direction == .forward else { return false }
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return false }

        let targetOffset = direction == .back ? -1 : 1
        return canRender(
            horizontalIndex: currentPage.horizontalIndex + targetOffset,
            verticalIndex: currentPage.verticalIndex
        )
    }

    private var canStartNavigation: Bool {
        !isPageTransitioning && transitionCoordinator == nil
    }

    private func performPendingNavigationIfNeeded() {
        guard let pendingNavigationDirection else { return }
        guard canStartNavigation else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
                self?.performPendingNavigationIfNeeded()
            }
            return
        }
        self.pendingNavigationDirection = nil
        navigate(pendingNavigationDirection)
    }

    private func canRender(horizontalIndex: Int, verticalIndex: Int) -> Bool {
        fourDirectionalPlayerDataSource?.canRenderCoordinate((horizontalIndex, verticalIndex)) ?? false
    }

}
