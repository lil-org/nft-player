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

    init(
        initialConfig: MobilePlayerConfig,
        onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void
    ) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
    }

    func makeUIViewController(context: Context) -> FourDirectionalPlayerContainer {
        return FourDirectionalPlayerContainer(initialConfig: initialConfig, onCoordinateUpdate: onCoordinateUpdate)
    }

    func updateUIViewController(_ uiViewController: FourDirectionalPlayerContainer, context: Context) {}
}

class FourDirectionalPlayerContainer: UIViewController, FourDirectionalPlayerDataSource, MobilePlaybackControllerDisplay, UIGestureRecognizerDelegate {

    private let initialConfig: MobilePlayerConfig
    private let onCoordinateUpdate: ((PlayerCoordinate) -> Void)

    private lazy var pagingVC = HorizontalPageViewController(fourDirectionalPlayerDataSource: self)
    private var renderedCoordinates = Set<PlayerCoordinate>()

    init(initialConfig: MobilePlayerConfig, onCoordinateUpdate: @escaping (PlayerCoordinate) -> Void) {
        self.initialConfig = initialConfig
        self.onCoordinateUpdate = onCoordinateUpdate
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enableNavigationBackSwipe()
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

    private func enableNavigationBackSwipe() {
        guard let navigationController = navigationController,
              let popGesture = navigationController.interactivePopGestureRecognizer else {
            return
        }

        popGesture.isEnabled = navigationController.viewControllers.count > 1
        popGesture.delegate = self
        pagingVC.requirePagingPanToFail(for: popGesture)
    }

    fileprivate func getHtml(x: Int, y: Int) -> String {
        return MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: PlayerCoordinate(x: x, y: y)).html
    }

    fileprivate func didRenderCoordinate(_ coordinate: (Int, Int)) {
        guard renderedCoordinates.count < 2 else { return }
        renderedCoordinates.insert(PlayerCoordinate(x: coordinate.0, y: coordinate.1))
        didUpdateRenderedCoordinates()
    }

    fileprivate func didCleanupCoordinate(_ coordinate: (Int, Int)) {
        renderedCoordinates.remove(PlayerCoordinate(x: coordinate.0, y: coordinate.1))
        didUpdateRenderedCoordinates()
    }

    private func didUpdateRenderedCoordinates() {
        if renderedCoordinates.count == 1, let coordinate = renderedCoordinates.first {
            onCoordinateUpdate(coordinate)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === navigationController?.interactivePopGestureRecognizer else {
            return true
        }

        return navigationController?.viewControllers.count ?? 0 > 1
    }

}

private protocol FourDirectionalPlayerDataSource: AnyObject {

    func getHtml(x: Int, y: Int) -> String
    func didRenderCoordinate(_ coordinate: (Int, Int))
    func didCleanupCoordinate(_ coordinate: (Int, Int))

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
        self.horizontalIndex = horizontalIndex
    }

    func update(verticalIndex: Int) {
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
        } else {
            renderedCoordinate = newCoordinate
            if let html = fourDirectionalPlayerDataSource?.getHtml(x: horizontalIndex, y: verticalIndex) {
                webView.loadHTMLString(html, baseURL: nil)
            }
            fourDirectionalPlayerDataSource?.didRenderCoordinate(newCoordinate)
        }
    }

}

private class HorizontalPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {

    let pageA: SpecificPageViewController
    let pageB: SpecificPageViewController
    let pageC: SpecificPageViewController

    private lazy var verticalPagingPanGestureRecognizer: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleVerticalPagingPan(_:)))
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    private var configuredPagingScrollPanGestures = Set<ObjectIdentifier>()
    private var isPagingScrollEnabled = true
    private var isVerticalNavigating = false
    private var navigationUnlockWorkItem: DispatchWorkItem?

    init(fourDirectionalPlayerDataSource: FourDirectionalPlayerDataSource) {
        pageA = SpecificPageViewController(horizontalIndex: 0, verticalIndex: 0, fourDirectionalPlayerDataSource: fourDirectionalPlayerDataSource)
        pageB = SpecificPageViewController(horizontalIndex: 1, verticalIndex: 0, fourDirectionalPlayerDataSource: fourDirectionalPlayerDataSource)
        pageC = SpecificPageViewController(horizontalIndex: -1, verticalIndex: 0, fourDirectionalPlayerDataSource: fourDirectionalPlayerDataSource)
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        setViewControllers([pageA], direction: .forward, animated: false, completion: nil)
        view.addGestureRecognizer(verticalPagingPanGestureRecognizer)
        configurePagingScrollViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePagingScrollViews()
    }

    func requirePagingPanToFail(for gestureRecognizer: UIGestureRecognizer) {
        verticalPagingPanGestureRecognizer.require(toFail: gestureRecognizer)
        pagingScrollViews.forEach { scrollView in
            scrollView.panGestureRecognizer.require(toFail: gestureRecognizer)
            scrollView.hideAutomaticScrollEdgeEffects()
        }
    }

    private var pagingScrollViews: [UIScrollView] {
        view.subviews.compactMap { $0 as? UIScrollView }
    }

    private func configurePagingScrollViews() {
        pagingScrollViews.forEach { scrollView in
            let panGestureId = ObjectIdentifier(scrollView.panGestureRecognizer)
            if !configuredPagingScrollPanGestures.contains(panGestureId) {
                scrollView.panGestureRecognizer.require(toFail: verticalPagingPanGestureRecognizer)
                configuredPagingScrollPanGestures.insert(panGestureId)
            }
            scrollView.isScrollEnabled = isPagingScrollEnabled
            scrollView.hideAutomaticScrollEdgeEffects()
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
        update(verticalIndex: coordinate.1 + 1)
        if let currentPage = viewControllers?.first as? SpecificPageViewController {
            currentPage.renderCurrentItem()
        }
    }

    @objc private func handleVerticalPagingPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        guard abs(translation.y) >= MobilePlayerGestureTuning.verticalPagingCommitTranslation
                || abs(velocity.y) >= MobilePlayerGestureTuning.verticalPagingCommitVelocity else {
            return
        }

        let shouldMoveForward: Bool
        if abs(velocity.y) >= MobilePlayerGestureTuning.verticalPagingCommitVelocity {
            shouldMoveForward = velocity.y < 0
        } else {
            shouldMoveForward = translation.y < 0
        }

        let direction: PlaybackNavigationDirection = shouldMoveForward ? .forward : .back
        navigate(direction)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === verticalPagingPanGestureRecognizer else {
            return true
        }

        guard !isVerticalNavigating else { return false }

        let velocity = verticalPagingPanGestureRecognizer.velocity(in: view)
        let absoluteXVelocity = abs(velocity.x)
        let absoluteYVelocity = abs(velocity.y)

        guard absoluteYVelocity >= MobilePlayerGestureTuning.verticalPagingMinimumVelocity,
              absoluteYVelocity > absoluteXVelocity * MobilePlayerGestureTuning.verticalPagingAxisDominance else {
            return false
        }

        if shouldYieldToTopDismissGesture(velocity: velocity) {
            return false
        }

        return true
    }

    private func shouldYieldToTopDismissGesture(velocity: CGPoint) -> Bool {
        guard velocity.y > 0 else { return false }
        let location = verticalPagingPanGestureRecognizer.location(in: view)
        let activationHeight = MobilePlayerGestureTuning.topDismissActivationHeight(safeAreaTop: view.safeAreaInsets.top)
        return location.y <= activationHeight
            && velocity.y > abs(velocity.x) * MobilePlayerGestureTuning.topDismissVerticalIntentRatio
    }

    private func beginVerticalPageTransition() -> Bool {
        guard !isVerticalNavigating else { return false }
        guard transitionCoordinator == nil else { return false }
        navigationUnlockWorkItem?.cancel()
        navigationUnlockWorkItem = nil
        isVerticalNavigating = true
        setPagingScrollEnabled(false)
        return true
    }

    private func finishVerticalPageTransition() {
        navigationUnlockWorkItem?.cancel()
        setPagingScrollEnabled(false)
        let workItem = DispatchWorkItem { [weak self] in
            self?.isVerticalNavigating = false
            self?.setPagingScrollEnabled(true)
            self?.navigationUnlockWorkItem = nil
        }
        navigationUnlockWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MobilePlayerGestureTuning.pageTransitionSettleDelay,
            execute: workItem
        )
    }

    private func setPagingScrollEnabled(_ isEnabled: Bool) {
        isPagingScrollEnabled = isEnabled
        pagingScrollViews.forEach { scrollView in
            scrollView.isScrollEnabled = isEnabled
        }
    }

    private func didSettleOnCurrentPage() {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return }
        update(currentHorizontalIndex: currentPage.horizontalIndex)
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        switch vc {
        case pageA:
            pageC.update(horizontalIndex: pageA.horizontalIndex - 1)
            return pageC
        case pageB:
            pageA.update(horizontalIndex: pageB.horizontalIndex - 1)
            return pageA
        case pageC:
            pageB.update(horizontalIndex: pageC.horizontalIndex - 1)
            return pageB
        default:
            return pageA
        }
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        switch vc {
        case pageA:
            pageB.update(horizontalIndex: pageA.horizontalIndex + 1)
            return pageB
        case pageB:
            pageC.update(horizontalIndex: pageB.horizontalIndex + 1)
            return pageC
        case pageC:
            pageA.update(horizontalIndex: pageC.horizontalIndex + 1)
            return pageA
        default:
            return pageA
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let destinationPage = pendingViewControllers.first as? SpecificPageViewController else { return }
        destinationPage.renderCurrentItem()
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        didSettleOnCurrentPage()
    }

    private func performPageTransition(
        _ direction: UIPageViewController.NavigationDirection,
        completion: @escaping () -> Void
    ) {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else {
            completion()
            return
        }

        let targetViewControllers: [UIViewController]
        switch direction {
        case .reverse:
            guard let targetViewController = pageViewController(self, viewControllerBefore: currentPage) else {
                completion()
                return
            }
            targetViewControllers = [targetViewController]
        case .forward:
            guard let targetViewController = pageViewController(self, viewControllerAfter: currentPage) else {
                completion()
                return
            }
            targetViewControllers = [targetViewController]
        default:
            completion()
            return
        }

        if let destinationPage = targetViewControllers.first as? SpecificPageViewController {
            destinationPage.renderCurrentItem()
        }

        setViewControllers(targetViewControllers, direction: direction, animated: true) { _ in
            self.didSettleOnCurrentPage()
            completion()
        }
    }

    func navigate(_ direction: PlaybackNavigationDirection) {
        guard !isVerticalNavigating else { return }

        switch direction {
        case .back, .forward:
            guard beginVerticalPageTransition() else { return }
            performPageTransition(direction == .back ? .reverse : .forward) { [weak self] in
                self?.finishVerticalPageTransition()
            }
        case .down, .nextCollection:
            changeCollection()
        case .up:
            return
        }
    }

}
