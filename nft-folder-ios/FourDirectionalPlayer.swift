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

    static func webView(in containerView: UIView) -> WKWebView {
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
    private var webView: WKWebView!
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
        representedImageKey = nil
        ensureWebView()
        imageView?.isHidden = true
        imageView?.image = nil
        webView.stopLoading()
        webView.isHidden = hidesEmptyWebContent && html.isEmpty
        onBegin?()
        webView.loadHTMLString(html, baseURL: nil)
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

    init(
        initialConfig: MobilePlayerConfig,
        onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void
    ) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
    }

    func makeUIViewController(context: Context) -> FourDirectionalPlayerContainer {
        return FourDirectionalPlayerContainer(
            initialConfig: initialConfig,
            onCoordinateUpdate: onCoordinateUpdate,
            onPaginationAttempt: onPaginationAttempt,
            onUnavailableNavigation: onUnavailableNavigation
        )
    }

    func updateUIViewController(_ uiViewController: FourDirectionalPlayerContainer, context: Context) {}
}

class FourDirectionalPlayerContainer: UIViewController, FourDirectionalPlayerDataSource, MobilePlaybackControllerDisplay {

    private let initialConfig: MobilePlayerConfig
    private let onCoordinateUpdate: ((PlayerCoordinate) -> Void)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)

    private lazy var pagingVC = HorizontalPageViewController(fourDirectionalPlayerDataSource: self)
    private var renderedCoordinates = Set<PlayerCoordinate>()
    private var displayedCoordinate: PlayerCoordinate?

    init(
        initialConfig: MobilePlayerConfig,
        onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void
    ) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        MobilePlaybackController.shared.subscribe(config: initialConfig, display: self)
        view.backgroundColor = .black
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
    func canRenderCoordinate(_ coordinate: (Int, Int)) -> Bool
    func startHorizontalCoordinate(verticalIndex: Int) -> Int
    func didRenderCoordinate(_ coordinate: (Int, Int))
    func didCleanupCoordinate(_ coordinate: (Int, Int))
    func didAttemptPagination()
    func didAttemptUnavailableHorizontalNavigation()
    func didDisplayCoordinate(_ coordinate: (Int, Int))

}

private class SpecificPageViewController: UIViewController {

    private weak var fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource?
    private lazy var mediaRenderer = FullscreenTokenMediaRenderer(containerView: view)

    private(set) var horizontalIndex: Int
    private(set) var verticalIndex: Int

    private var renderedCoordinate: (Int, Int)?
    private var willOrDidAppear = false
    var preferredPrefetchDirection: SolanaImageCache.PrefetchDirection = .forward

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

        if let descriptor = solanaImageDescriptor,
           descriptor.isStaticImage {
            renderImage(descriptor, fallbackHTML: token.html)
        } else {
            renderWebContent(token.html)
        }
        fourDirectionalPlayerDataSource?.didRenderCoordinate(newCoordinate)
    }

    private func renderImage(_ descriptor: SolanaImageDescriptor, fallbackHTML: String) {
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
        mediaRenderer.renderWebContent(html)
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
    private weak var fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource?

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

    private func configurePagingScrollViews() {
        pagingScrollViews.forEach { scrollView in
            scrollView.hideAutomaticScrollEdgeEffects()
            let panGesture = scrollView.panGestureRecognizer
            let panGestureId = ObjectIdentifier(panGesture)
            if !configuredPagingPanGestures.contains(panGestureId) {
                panGesture.addTarget(self, action: #selector(handlePagingPan(_:)))
                configuredPagingPanGestures.insert(panGestureId)
            }
        }
    }

    @objc private func handlePagingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            didNotifyPaginationAttemptDuringCurrentPan = false
            didNotifyUnavailableNavigationDuringCurrentPan = false

        case .changed:
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

        default:
            break
        }
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
