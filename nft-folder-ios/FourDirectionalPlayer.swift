// ∅ 2026 lil org

import UIKit
import SwiftUI
import WebKit

struct PlayerCoordinate: Hashable {
    let x: Int
    let y: Int
}

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
    private let containerView: UIView
    private var webView: AutoReloadingWebView!
    private var imageView: UIImageView!
    private var representedImageKey: AnyHashable?

    init(containerView: UIView) {
        self.containerView = containerView
    }

    func clearContent() {
        representedImageKey = nil
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        imageView?.image = nil
    }

    func renderImage<Key: Hashable>(
        key: Key,
        hideImageUntilLoaded: Bool,
        onBegin: (() -> Void)? = nil,
        load: (@escaping (UIImage?) -> Void) -> Void,
        fallbackToWebContent: @escaping () -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        ensureImageView()
        hideWebContent()
        imageView.isHidden = hideImageUntilLoaded
        imageView.image = nil
        onBegin?()

        let imageKey = AnyHashable(key)
        representedImageKey = imageKey
        load { [weak self] image in
            guard let self,
                  self.representedImageKey == imageKey else {
                return
            }

            guard let image else {
                fallbackToWebContent()
                return
            }

            onSuccess?()
            self.webView?.isHidden = true
            self.imageView.isHidden = false
            self.imageView.image = image
        }
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
        onLoadFailure: (() -> Void)? = nil
    ) {
        prepareWebContent(html, hidesEmptyWebContent: hidesEmptyWebContent, onBegin: onBegin)
        webView.loadLocalHTMLString(
            html,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onFailure: onLoadFailure
        )
    }

    private func prepareWebContent(
        _ html: String,
        hidesEmptyWebContent: Bool,
        onBegin: (() -> Void)?
    ) {
        representedImageKey = nil
        ensureWebView()
        imageView?.isHidden = true
        imageView?.image = nil
        webView.stopLoading()
        webView.isHidden = hidesEmptyWebContent && html.isEmpty
        onBegin?()
    }

    private func ensureImageView() {
        guard imageView == nil else { return }

        imageView = FullscreenTokenMediaView.imageView(in: containerView)
    }

    private func ensureWebView() {
        guard webView == nil else { return }

        webView = FullscreenTokenMediaView.webView(in: containerView)
    }

    private func hideWebContent() {
        webView?.stopLoading()
        webView?.isHidden = true
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

class FourDirectionalPlayerContainer: UIViewController, FourDirectionalPlayerDataSource, MobilePlaybackControllerDisplay {

    private let initialConfig: MobilePlayerConfig
    private let onCoordinateUpdate: ((PlayerCoordinate) -> Void)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)
    private let onToggleChrome: (() -> Void)
    private let onZoomStateChange: ((Bool) -> Void)

    private lazy var pagingVC = HorizontalPageViewController(fourDirectionalPlayerDataSource: self)
    private lazy var singleTapRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gesture.numberOfTapsRequired = 1
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    private lazy var doubleTapRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    private lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    private var renderedCoordinates = Set<PlayerCoordinate>()
    private var displayedCoordinate: PlayerCoordinate?

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
        MobilePlaybackController.shared.subscribe(config: initialConfig, display: self)
        view.backgroundColor = .black
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
        installTapGestures()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    deinit {
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
        view.addGestureRecognizer(singleTapRecognizer)
        view.addGestureRecognizer(doubleTapRecognizer)
        view.addGestureRecognizer(longPressRecognizer)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        onToggleChrome()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        pagingVC.toggleZoom(at: gesture.location(in: view), in: view)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        onToggleChrome()
    }

    fileprivate func getToken(x: Int, y: Int) -> GeneratedToken {
        MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: PlayerCoordinate(x: x, y: y))
    }

    fileprivate func prepareSolanaImageWindow(
        for coordinate: (Int, Int),
        direction: SolanaImageCache.PrefetchDirection
    ) -> SolanaImageDescriptor? {
        MobilePlaybackController.shared.prepareSolanaImageWindow(
            uuid: initialConfig.id,
            coordinate: PlayerCoordinate(x: coordinate.0, y: coordinate.1),
            direction: direction
        )
    }

    fileprivate func adjacentSolanaImageDescriptor(
        for coordinate: (Int, Int),
        direction: SolanaImageCache.PrefetchDirection
    ) -> SolanaImageDescriptor? {
        MobilePlaybackController.shared.adjacentSolanaImageDescriptor(
            uuid: initialConfig.id,
            coordinate: PlayerCoordinate(x: coordinate.0, y: coordinate.1),
            direction: direction
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
        renderedCoordinates.insert(PlayerCoordinate(x: coordinate.0, y: coordinate.1))
        didUpdateRenderedCoordinates()
    }

    fileprivate func didCleanupCoordinate(_ coordinate: (Int, Int)) {
        renderedCoordinates.remove(PlayerCoordinate(x: coordinate.0, y: coordinate.1))
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
        if renderedCoordinates.count == 1, let coordinate = renderedCoordinates.first {
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
    func prepareSolanaImageWindow(
        for coordinate: (Int, Int),
        direction: SolanaImageCache.PrefetchDirection
    ) -> SolanaImageDescriptor?
    func adjacentSolanaImageDescriptor(
        for coordinate: (Int, Int),
        direction: SolanaImageCache.PrefetchDirection
    ) -> SolanaImageDescriptor?
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
        -adjustedContentInset.left
    }

    private var maximumContentOffsetX: CGFloat {
        max(minimumContentOffsetX, contentSize.width - bounds.width + adjustedContentInset.right)
    }

}

private class SpecificPageViewController: UIViewController, UIScrollViewDelegate {

    private struct AnimatedRenderContext: Equatable {
        let descriptor: SolanaImageDescriptor
        let adjacentDescriptor: SolanaImageDescriptor?
        let fallbackHTML: String
    }

    private weak var fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource?
    private let zoomScrollView = PlayerZoomScrollView()
    private let mediaContentView = UIView()
    private lazy var mediaRenderer = FullscreenTokenMediaRenderer(containerView: mediaContentView)

    private(set) var horizontalIndex: Int
    private(set) var verticalIndex: Int

    private var renderedCoordinate: (Int, Int)?
    private var animatedRenderContext: AnimatedRenderContext?
    private var renderedAnimatedImageURL: URL?
    private var renderedAnimatedNextImageURL: URL?
    private var solanaImageCacheObserver: NSObjectProtocol?
    private var willOrDidAppear = false
    private var isZoomInteractionActive = false
    var onZoomStateChange: (() -> Void)?
    var preferredPrefetchDirection: SolanaImageCache.PrefetchDirection = .forward
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
        removeSolanaImageCacheObserver()
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

    private func cleanupDisplayedContent() {
        resetZoom(animated: false)
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

        let locationInContent = coordinateView.convert(location, to: mediaContentView)
        let targetScale = min(
            MobilePlayerGestureTuning.playerDoubleTapZoomScale,
            zoomScrollView.maximumZoomScale
        )
        let zoomSize = CGSize(
            width: zoomScrollView.bounds.width / targetScale,
            height: zoomScrollView.bounds.height / targetScale
        )
        let zoomRect = CGRect(
            x: locationInContent.x - zoomSize.width / 2,
            y: locationInContent.y - zoomSize.height / 2,
            width: zoomSize.width,
            height: zoomSize.height
        )

        zoomScrollView.zoom(to: zoomRect, animated: true)
    }

    func resetZoom(animated: Bool) {
        guard isViewLoaded else { return }
        guard zoomScrollView.zoomScale != zoomScrollView.minimumZoomScale else {
            updateZoomInteraction()
            return
        }

        zoomScrollView.setZoomScale(zoomScrollView.minimumZoomScale, animated: animated)
        if !animated {
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
        view.backgroundColor = .black
        mediaContentView.backgroundColor = .black

        zoomScrollView.backgroundColor = .black
        zoomScrollView.delegate = self
        zoomScrollView.minimumZoomScale = 1
        zoomScrollView.maximumZoomScale = MobilePlayerGestureTuning.playerMaximumZoomScale
        zoomScrollView.bouncesZoom = true
        zoomScrollView.showsHorizontalScrollIndicator = false
        zoomScrollView.showsVerticalScrollIndicator = false
        zoomScrollView.contentInsetAdjustmentBehavior = .never
        zoomScrollView.hideAutomaticScrollEdgeEffects()

        zoomScrollView.translatesAutoresizingMaskIntoConstraints = false
        mediaContentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomScrollView)
        zoomScrollView.addSubview(mediaContentView)

        NSLayoutConstraint.activate([
            zoomScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            mediaContentView.topAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.topAnchor),
            mediaContentView.bottomAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.bottomAnchor),
            mediaContentView.leadingAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.leadingAnchor),
            mediaContentView.trailingAnchor.constraint(equalTo: zoomScrollView.contentLayoutGuide.trailingAnchor),
            mediaContentView.widthAnchor.constraint(equalTo: zoomScrollView.frameLayoutGuide.widthAnchor),
            mediaContentView.heightAnchor.constraint(equalTo: zoomScrollView.frameLayoutGuide.heightAnchor)
        ])

        updateZoomInteraction()
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
        updateZoomInteraction()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= scrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance {
            resetZoom(animated: true)
        } else {
            updateZoomInteraction()
        }
    }

    func renderCurrentItem() {
        guard willOrDidAppear else { return }

        let newCoordinate = (horizontalIndex, verticalIndex)
        if let renderedCoordinate = renderedCoordinate, renderedCoordinate == newCoordinate {
            return
        }

        if let renderedCoordinate {
            fourDirectionalPlayerDataSource?.didCleanupCoordinate(renderedCoordinate)
        }

        renderedCoordinate = newCoordinate
        let solanaImageDescriptor = fourDirectionalPlayerDataSource?.prepareSolanaImageWindow(
            for: newCoordinate,
            direction: preferredPrefetchDirection
        )

        guard let token = fourDirectionalPlayerDataSource?.getToken(x: horizontalIndex, y: verticalIndex) else {
            fourDirectionalPlayerDataSource?.didRenderCoordinate(newCoordinate)
            return
        }

        if let descriptor = solanaImageDescriptor {
            switch descriptor.media {
            case .staticImage:
                renderImage(descriptor, fallbackHTML: token.html)
            case .animatedImage:
                let adjacentDescriptor = fourDirectionalPlayerDataSource?.adjacentSolanaImageDescriptor(
                    for: newCoordinate,
                    direction: preferredPrefetchDirection
                )
                renderAnimatedImage(descriptor, adjacentDescriptor: adjacentDescriptor, fallbackHTML: token.html)
            }
        } else {
            renderWebContent(token.html)
        }
        fourDirectionalPlayerDataSource?.didRenderCoordinate(newCoordinate)
    }

    private func renderImage(_ descriptor: SolanaImageDescriptor, fallbackHTML: String) {
        clearAnimatedRenderContext()
        mediaRenderer.renderImage(
            key: descriptor,
            hideImageUntilLoaded: false,
            load: { completion in
                SolanaImageCache.shared.loadImage(for: descriptor, completion: completion)
            },
            fallbackToWebContent: { [weak self] in
                self?.renderWebContent(fallbackHTML)
            }
        )
    }

    private func renderWebContent(_ html: String) {
        clearAnimatedRenderContext()
        renderAnimatedFallbackWebContent(html)
    }

    private func renderAnimatedFallbackWebContent(_ html: String) {
        mediaRenderer.renderWebContent(html)
    }

    private func renderAnimatedImage(
        _ descriptor: SolanaImageDescriptor,
        adjacentDescriptor: SolanaImageDescriptor?,
        fallbackHTML: String
    ) {
        setAnimatedRenderContext(
            AnimatedRenderContext(
                descriptor: descriptor,
                adjacentDescriptor: adjacentDescriptor,
                fallbackHTML: fallbackHTML
            )
        )
        renderAvailableAnimatedLocalContent(allowFallback: true)
    }

    private func renderAvailableAnimatedLocalContent(allowFallback: Bool) {
        guard let context = animatedRenderContext else { return }

        let imageCache = SolanaImageCache.shared
        guard let localFileURL = imageCache.localFileURL(for: context.descriptor) else {
            renderedAnimatedImageURL = nil
            renderedAnimatedNextImageURL = nil
            if allowFallback {
                renderAnimatedFallbackWebContent(context.fallbackHTML)
            }
            return
        }

        let nextLocalFileURL = context.adjacentDescriptor.flatMap {
            imageCache.localFileURL(for: $0)
        }
        if renderedAnimatedImageURL == localFileURL {
            renderedAnimatedNextImageURL = nextLocalFileURL
            return
        }

        let html = SolanaTokenHTML.createImageHTML(
            imageURL: localFileURL.absoluteString,
            nextImageURL: nextLocalFileURL?.absoluteString
        )
        var didFailLocalLoad = false
        mediaRenderer.renderLocalWebContent(
            html,
            htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
            readAccessURL: imageCache.webViewReadAccessURL,
            onLoadFailure: { [weak self] in
                guard let self,
                      self.animatedRenderContext == context else {
                    return
                }

                didFailLocalLoad = true
                self.renderedAnimatedImageURL = nil
                self.renderedAnimatedNextImageURL = nil
                self.renderAnimatedFallbackWebContent(context.fallbackHTML)
            }
        )
        guard !didFailLocalLoad else { return }

        renderedAnimatedImageURL = localFileURL
        renderedAnimatedNextImageURL = nextLocalFileURL
    }

    private func setAnimatedRenderContext(_ context: AnimatedRenderContext) {
        animatedRenderContext = context
        renderedAnimatedImageURL = nil
        renderedAnimatedNextImageURL = nil
        installSolanaImageCacheObserverIfNeeded()
    }

    private func clearAnimatedRenderContext() {
        animatedRenderContext = nil
        renderedAnimatedImageURL = nil
        renderedAnimatedNextImageURL = nil
        removeSolanaImageCacheObserver()
    }

    private func installSolanaImageCacheObserverIfNeeded() {
        guard solanaImageCacheObserver == nil else { return }

        solanaImageCacheObserver = NotificationCenter.default.addObserver(
            forName: .solanaImageCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderAvailableAnimatedLocalContent(allowFallback: false)
        }
    }

    private func removeSolanaImageCacheObserver() {
        guard let solanaImageCacheObserver else { return }

        NotificationCenter.default.removeObserver(solanaImageCacheObserver)
        self.solanaImageCacheObserver = nil
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

    private func changeCollection() {
        let coordinate = getCurrentCoordinate()
        jumpToCoordinate(horizontalIndex: 0, verticalIndex: coordinate.1 + 1)
    }

    private func restartCollection() {
        let coordinate = getCurrentCoordinate()
        let targetHorizontalIndex = fourDirectionalPlayerDataSource?.startHorizontalCoordinate(verticalIndex: coordinate.1) ?? 0
        guard canRender(horizontalIndex: targetHorizontalIndex, verticalIndex: coordinate.1) else { return }
        jumpToCoordinate(horizontalIndex: targetHorizontalIndex, verticalIndex: coordinate.1)
    }

    private func jumpToCoordinate(horizontalIndex: Int, verticalIndex: Int) {
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
            self?.pageA.renderCurrentItem()
            self?.fourDirectionalPlayerDataSource?.didDisplayCoordinate((horizontalIndex, verticalIndex))
        }
    }

    private func didSettleOnCurrentPage() {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return }
        update(currentHorizontalIndex: currentPage.horizontalIndex)
        updatePagingScrollEnabled()
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
        didSettleOnCurrentPage()
        performPendingNavigationIfNeeded()
    }

    private func performPageTransition(
        _ direction: UIPageViewController.NavigationDirection,
        completion: @escaping () -> Void
    ) {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else {
            completion()
            return
        }

        let targetViewController: UIViewController?
        switch direction {
        case .reverse:
            targetViewController = pageViewController(self, viewControllerBefore: currentPage)
        case .forward:
            targetViewController = pageViewController(self, viewControllerAfter: currentPage)
        default:
            completion()
            return
        }

        guard let targetViewController else {
            completion()
            return
        }

        resetCurrentZoom(animated: false)
        fourDirectionalPlayerDataSource?.didAttemptPagination()

        if let destinationPage = targetViewController as? SpecificPageViewController {
            destinationPage.renderCurrentItem()
        }

        setViewControllers([targetViewController], direction: direction, animated: true) { _ in
            self.didSettleOnCurrentPage()
            completion()
        }
    }

    func navigate(_ direction: PlaybackNavigationDirection) {
        switch direction {
        case .back, .forward:
            guard canStartNavigation else { return }
            isPageTransitioning = true
            performPageTransition(direction == .back ? .reverse : .forward) { [weak self] in
                self?.isPageTransitioning = false
                self?.performPendingNavigationIfNeeded()
            }
        case .down, .nextCollection:
            guard canStartNavigation else { return }
            changeCollection()
        case .up:
            return
        case .restartCollection:
            guard canStartNavigation else {
                pendingNavigationDirection = direction
                return
            }
            restartCollection()
        }
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
