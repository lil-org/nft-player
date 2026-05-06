// ∅ 2026 lil org

import UIKit
import SwiftUI
import WebKit

struct PlayerCoordinate: Hashable {
    let x: Int
    let y: Int
}

struct FourDirectionalPlayerContainerView: UIViewControllerRepresentable {

    private let initialConfig: MobilePlayerConfig
    private let onCoordinateUpdate: ((PlayerCoordinate) -> Void)
    private let onUnavailableNavigation: (() -> Void)

    init(
        initialConfig: MobilePlayerConfig,
        onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void,
        onUnavailableNavigation: @escaping () -> Void
    ) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
        self.onUnavailableNavigation = onUnavailableNavigation
    }

    func makeUIViewController(context: Context) -> FourDirectionalPlayerContainer {
        return FourDirectionalPlayerContainer(
            initialConfig: initialConfig,
            onCoordinateUpdate: onCoordinateUpdate,
            onUnavailableNavigation: onUnavailableNavigation
        )
    }

    func updateUIViewController(_ uiViewController: FourDirectionalPlayerContainer, context: Context) {}
}

class FourDirectionalPlayerContainer: UIViewController, FourDirectionalPlayerDataSource, MobilePlaybackControllerDisplay {

    private let initialConfig: MobilePlayerConfig
    private let onCoordinateUpdate: ((PlayerCoordinate) -> Void)
    private let onUnavailableNavigation: (() -> Void)

    private lazy var pagingVC = HorizontalPageViewController(fourDirectionalPlayerDataSource: self)
    private var renderedCoordinates = Set<PlayerCoordinate>()
    private var displayedCoordinate: PlayerCoordinate?

    init(
        initialConfig: MobilePlayerConfig,
        onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void,
        onUnavailableNavigation: @escaping () -> Void
    ) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
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

    fileprivate func getHtml(x: Int, y: Int) -> String {
        return MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: PlayerCoordinate(x: x, y: y)).html
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

    func getHtml(x: Int, y: Int) -> String
    func canRenderCoordinate(_ coordinate: (Int, Int)) -> Bool
    func startHorizontalCoordinate(verticalIndex: Int) -> Int
    func didRenderCoordinate(_ coordinate: (Int, Int))
    func didCleanupCoordinate(_ coordinate: (Int, Int))
    func didAttemptUnavailableHorizontalNavigation()
    func didDisplayCoordinate(_ coordinate: (Int, Int))

}

private class SpecificPageViewController: UIViewController {

    private weak var fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource?
    private var webView: WKWebView!

    private(set) var horizontalIndex: Int
    private(set) var verticalIndex: Int

    private var renderedCoordinate: (Int, Int)?
    private var willOrDidAppear = false

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
        webView?.loadHTMLString("", baseURL: nil)
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

        if webView == nil {
            webView = AutoReloadingWebView.new
            webView.isUserInteractionEnabled = false
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                webView.topAnchor.constraint(equalTo: view.topAnchor),
                webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        let newCoordinate = (horizontalIndex, verticalIndex)
        if let renderedCoordinate = renderedCoordinate, renderedCoordinate == newCoordinate {
            return
        }

        if let renderedCoordinate {
            fourDirectionalPlayerDataSource?.didCleanupCoordinate(renderedCoordinate)
        }

        renderedCoordinate = newCoordinate
        if let html = fourDirectionalPlayerDataSource?.getHtml(x: horizontalIndex, y: verticalIndex) {
            webView.loadHTMLString(html, baseURL: nil)
        }
        fourDirectionalPlayerDataSource?.didRenderCoordinate(newCoordinate)
    }

}

private class HorizontalPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    let pageA: SpecificPageViewController
    let pageB: SpecificPageViewController
    let pageC: SpecificPageViewController

    private var isPageTransitioning = false
    private var pendingNavigationDirection: PlaybackNavigationDirection?
    private var configuredPagingPanGestures = Set<ObjectIdentifier>()
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
            didNotifyUnavailableNavigationDuringCurrentPan = false

        case .changed:
            guard !didNotifyUnavailableNavigationDuringCurrentPan else { return }

            let translation = gesture.translation(in: view)
            let hasHorizontalIntent = abs(translation.x) > MobilePlayerGestureTuning.pageBoundaryRevealTranslation
                && abs(translation.x) > abs(translation.y) * MobilePlayerGestureTuning.pageBoundaryRevealHorizontalIntentRatio
            guard hasHorizontalIntent else { return }

            let targetOffset = translation.x > 0 ? -1 : 1
            let coordinate = getCurrentCoordinate()
            guard !canRender(horizontalIndex: coordinate.0 + targetOffset, verticalIndex: coordinate.1) else { return }

            didNotifyUnavailableNavigationDuringCurrentPan = true
            fourDirectionalPlayerDataSource?.didAttemptUnavailableHorizontalNavigation()

        case .ended, .cancelled, .failed:
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
        targetPage.update(horizontalIndex: targetIndex)
        return targetPage
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let destinationPage = pendingViewControllers.first as? SpecificPageViewController else { return }
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
