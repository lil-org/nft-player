import Observation
import UIKit

protocol PlayerNavigationChromeCoordinatorDelegate: AnyObject {
    var isPlayerInteractionInstalled: Bool { get }
    var isCardTransitionActive: Bool { get }

    func beginProgrammaticCardMinimize() -> Bool
    func configurePagingScrollViews()
    func setCardTransitionCanvasBackgroundColor(_ color: UIColor)
}

final class PlayerNavigationChromeCoordinator: NSObject {

    private static let navigationBarSideControlRegionWidth: CGFloat = 96
    private static let navigationBarShowDuration: TimeInterval = 0
    private static let navigationBarHideDuration: TimeInterval = 0

    weak var delegate: (any PlayerNavigationChromeCoordinatorDelegate)?

    private let playerNavigationController: PlayerNavigationController
    private let playerViewController: MobilePlayerHostingController
    private let browserViewController: MobilePlayerBrowserPageViewController?
    private let modeController: MobilePlayerSessionModeController
    private let chrome: MobilePlayerChromeController
    private let onDismiss: () -> Void

    private var view: UIView {
        playerViewController.view
    }

    private func isSessionViewController(_ viewController: UIViewController?) -> Bool {
        guard let viewController else { return false }
        return viewController === playerViewController
            || viewController === browserViewController
    }

    lazy var navigationBarTap = UITapGestureRecognizer(
        target: self,
        action: #selector(handleNavigationBarTap(_:))
    )
    private lazy var navigationBackAction = UIAction(
        title: Strings.back
    ) { [weak self] _ in
        _ = self?.handleNavigationBackAction()
    }
    private lazy var pagerBackBarButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "chevron.backward"),
            primaryAction: navigationBackAction,
            menu: makePagerBackMenu()
        )
        item.accessibilityLabel = Strings.back
        return item
    }()
    lazy var controlsPan = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleControlsPan(_:))
    )
    private lazy var navigationToolbarUpdate = PendingMainQueueUpdate { [weak self] in
        self?.synchronizeNavigationBarAfterToolbarUpdate()
    }
    private var topEdgeTintAnimator: UIViewPropertyAnimator?
    private var pendingTopEdgeTintTask: Task<Void, Never>?
    private var didControlsPanConflictWithHorizontalScroll = false
    private var isNavigationBackDisplayModeRequestPending = false
    private var chromeObservationGeneration: UInt = 0

    private var isInstalled: Bool {
        delegate?.isPlayerInteractionInstalled == true
    }

    private var isCardTransitionActive: Bool {
        delegate?.isCardTransitionActive == true
    }

    init(
        navigationController: PlayerNavigationController,
        playerViewController: MobilePlayerHostingController,
        browserViewController: MobilePlayerBrowserPageViewController?,
        modeController: MobilePlayerSessionModeController,
        chrome: MobilePlayerChromeController,
        onDismiss: @escaping () -> Void
    ) {
        self.playerNavigationController = navigationController
        self.playerViewController = playerViewController
        self.browserViewController = browserViewController
        self.modeController = modeController
        self.chrome = chrome
        self.onDismiss = onDismiss
        super.init()
    }

    func configureNavigationBarChromeVisibilityEnforcement() {
        playerNavigationController.canEnforceNavigationBarChromeVisibility = {
            [weak navigationController = playerNavigationController,
             weak playerViewController,
             weak browserViewController] in
            guard let navigationController,
                  let topViewController = navigationController.topViewController,
                  topViewController === playerViewController
                    || (browserViewController != nil && topViewController === browserViewController),
                  navigationController.transitionCoordinator == nil else {
                return false
            }

            return true
        }
    }

    func startChromeObservation() {
        setNavigationBarChromeVisible(
            shouldShowNavigationBarChrome,
            animated: false
        )
        chromeObservationGeneration &+= 1
        let observationGeneration = chromeObservationGeneration
        applyPlayerBackgroundColor(chrome.playerBackgroundColor)
        observePlayerBackgroundColor(generation: observationGeneration)
        observeNavigationToolbarUpdates(generation: observationGeneration)
        observeNavigationBarChromeVisibility(generation: observationGeneration)
    }

    @objc private func handleNavigationBarTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard !chrome.isCollectionBrowserActive else { return }

        chrome.setControlsVisible(false)
    }

    func didShowPlayerAfterNavigationTransition() {
        guard isInstalled else { return }
        playerNavigationController
            .setNavigationBarChromeVisibilityEnforcementSuspended(false)
        installNavigationBackAction()
        setNavigationBarChromeVisible(shouldShowNavigationBarChrome, animated: true)
        updateTopEdgeTint(
            forPagerTarget: playerNavigationController.topViewController === playerViewController,
            using: nil
        )
        playerNavigationController.configureNavigationBackGestureBlocking()
        configurePagingScrollViews()
        playerNavigationController.setNeedsStatusBarAppearanceUpdate()
        playerNavigationController.topViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    func prepareForNavigationPopTransition(
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        playerNavigationController
            .setNavigationBarChromeVisibilityEnforcementSuspended(true)
        let navigationBar = playerNavigationController.navigationBar
        navigationBar.accessibilityElementsHidden = false
        navigationBar.layer.isHidden = false
        navigationBar.layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            navigationBar.alpha = 1
        }
        updateTopEdgeTint(forPagerTarget: false, using: transitionCoordinator)
        guard let transitionCoordinator else { return }

        transitionCoordinator.animate { _ in
            UIView.performWithoutAnimation {
                navigationBar.alpha = 1
            }
        }
    }

    func prepareForPlayerPresentation(
        for targetViewController: UIViewController?,
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        playerNavigationController
            .setNavigationBarChromeVisibilityEnforcementSuspended(false)
        installNavigationBackAction()
        playerNavigationController.configureNavigationBackGestureBlocking()
        let navigationBar = playerNavigationController.navigationBar
        navigationBar.layer.removeAllAnimations()
        let targetAlpha: CGFloat = shouldShowNavigationBarChrome ? 1 : 0
        setNavigationBarChromeVisible(
            shouldShowNavigationBarChrome,
            animated: false
        )
        updateTopEdgeTint(
            forPagerTarget: targetViewController === playerViewController,
            using: transitionCoordinator
        )
        guard let transitionCoordinator else {
            return
        }

        transitionCoordinator.animate { _ in
            UIView.performWithoutAnimation {
                navigationBar.alpha = targetAlpha
            }
        }
    }

    private func updateTopEdgeTint(
        forPagerTarget isPagerTarget: Bool,
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        guard !isCardTransitionActive else { return }

        let targetAlpha: CGFloat = isPagerTarget ? 0 : 1
        guard playerNavigationController.topEdgeTintAlpha != targetAlpha else {
            cancelScheduledTopEdgeTintChanges()
            return
        }
        guard let transitionCoordinator else {
            setTopEdgeTintAlphaDirectly(targetAlpha)
            return
        }

        cancelScheduledTopEdgeTintChanges()
        transitionCoordinator.animate { [weak self] _ in
            self?.playerNavigationController.setTopEdgeTintAlpha(targetAlpha)
        }
    }

    private func cancelScheduledTopEdgeTintChanges() {
        pendingTopEdgeTintTask?.cancel()
        pendingTopEdgeTintTask = nil
        if let topEdgeTintAnimator, topEdgeTintAnimator.state != .inactive {
            topEdgeTintAnimator.stopAnimation(true)
        }
        topEdgeTintAnimator = nil
    }

    func setTopEdgeTintAlphaDirectly(_ alpha: CGFloat) {
        cancelScheduledTopEdgeTintChanges()
        playerNavigationController.setTopEdgeTintAlpha(alpha)
    }

    func animateTopEdgeTint(to alpha: CGFloat, delay: TimeInterval = 0) {
        cancelScheduledTopEdgeTintChanges()

        guard delay > 0 else {
            startTopEdgeTintAnimation(to: alpha)
            return
        }

        pendingTopEdgeTintTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            pendingTopEdgeTintTask = nil
            startTopEdgeTintAnimation(to: alpha)
        }
    }

    private func startTopEdgeTintAnimation(to alpha: CGFloat) {
        let animator = UIViewPropertyAnimator(duration: 0.06, curve: .linear) {
            self.playerNavigationController.setTopEdgeTintAlpha(alpha)
        }
        topEdgeTintAnimator = animator
        animator.startAnimation()
    }

    private func observePlayerBackgroundColor(generation: UInt) {
        withObservationTracking {
            _ = chrome.playerBackgroundColor
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      chromeObservationGeneration == generation else {
                    return
                }
                applyPlayerBackgroundColor(chrome.playerBackgroundColor)
                observePlayerBackgroundColor(generation: generation)
            }
        }
    }

    private func applyPlayerBackgroundColor(_ color: UIColor) {
        playerViewController.setPlayerPageBackground(color: color)
        browserViewController?.setPlayerPageBackground(color: color)
        delegate?.setCardTransitionCanvasBackgroundColor(color)
    }

    private func observeNavigationToolbarUpdates(generation: UInt) {
        withObservationTracking {
            _ = chrome.allowsNavigationBackSwipe
            _ = chrome.isPlayerContentHiddenForCardTransition
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      chromeObservationGeneration == generation else {
                    return
                }
                scheduleNavigationBarSynchronization()
                observeNavigationToolbarUpdates(generation: generation)
            }
        }
    }

    private func scheduleNavigationBarSynchronization() {
        navigationToolbarUpdate.invalidate()
        navigationToolbarUpdate.schedule()
    }

    private func synchronizeNavigationBarAfterToolbarUpdate() {
        guard isInstalled,
              isSessionViewController(playerNavigationController.topViewController),
              playerNavigationController.transitionCoordinator == nil else {
            return
        }

        installNavigationBackAction()
        playerViewController.restoreNavigationTitleIfNeeded()
        playerNavigationController.configureNavigationBackGestureBlocking()
        configurePagingScrollViews()
        playerNavigationController.synchronizeNavigationBarChromeVisibility()
    }

    private func observeNavigationBarChromeVisibility(generation: UInt) {
        withObservationTracking {
            _ = chrome.showControls
            _ = chrome.allowsNavigationBackSwipe
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      chromeObservationGeneration == generation else {
                    return
                }
                setNavigationBarChromeVisible(
                    shouldShowNavigationBarChrome,
                    animated: true
                )
                scheduleNavigationBarSynchronization()
                observeNavigationBarChromeVisibility(generation: generation)
            }
        }
    }

    private var shouldShowNavigationBarChrome: Bool {
        chrome.isPlayerChromeVisible
    }

    func installNavigationBackAction() {
        let stackedViewControllers = playerNavigationController.viewControllers.dropFirst()

        if let browserViewController,
           stackedViewControllers.contains(where: { $0 === browserViewController }) {
            let navigationItem = browserViewController.navigationItem
            if navigationItem.backAction?.identifier != navigationBackAction.identifier {
                navigationItem.backAction = navigationBackAction
            }
        }

        if stackedViewControllers.contains(where: { $0 === playerViewController }) {
            let navigationItem = playerViewController.navigationItem
            if navigationItem.leftBarButtonItem !== pagerBackBarButtonItem {
                navigationItem.leftBarButtonItem = pagerBackBarButtonItem
            }
        }
    }

    private func makePagerBackMenu() -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self else {
                    completion([])
                    return
                }

                var actions = [UIAction]()
                if let browserViewController = self.browserViewController,
                   self.playerNavigationController.viewControllers
                    .contains(where: { $0 === browserViewController }) {
                    let title = browserViewController.navigationItem.backButtonTitle
                        ?? Strings.back
                    actions.append(
                        UIAction(title: title) { [weak self] _ in
                            self?.popExternallyToBrowser()
                        }
                    )
                }
                actions.append(
                    UIAction(title: Strings.nftPlayer) { [weak self] _ in
                        self?.popExternallyToRoot()
                    }
                )
                completion(actions)
            }
        ])
    }

    private func popExternallyToBrowser() {
        guard isInstalled,
              let browserViewController,
              playerNavigationController.transitionCoordinator == nil,
              playerNavigationController.topViewController === playerViewController,
              playerNavigationController.viewControllers
                .contains(where: { $0 === browserViewController }),
              !isCardTransitionActive,
              !chrome.isPlayerContentHiddenForCardTransition else {
            return
        }

        playerNavigationController.popToViewController(
            browserViewController,
            animated: true
        )
    }

    private func popExternallyToRoot() {
        guard isInstalled,
              playerNavigationController.transitionCoordinator == nil,
              !isCardTransitionActive,
              !chrome.isPlayerContentHiddenForCardTransition else {
            return
        }

        onDismiss()
    }

    @discardableResult
    func handleNavigationBackAction() -> Bool {
        guard isInstalled,
              let topViewController = playerNavigationController.topViewController,
              isSessionViewController(topViewController) else {
            return false
        }

        guard playerNavigationController.transitionCoordinator == nil,
              !isCardTransitionActive,
              !chrome.isPlayerContentHiddenForCardTransition else {
            return true
        }
        guard topViewController === playerViewController else {
            onDismiss()
            return true
        }
        guard !isNavigationBackDisplayModeRequestPending else {
            return true
        }

        let state = chrome.currentLayoutInteractionState()
        guard state.canSwitchToCollectionBrowser,
              let pagePosition = state.pagePosition else {
            onDismiss()
            return true
        }

        guard !beginProgrammaticCardMinimize() else {
            return true
        }

        isNavigationBackDisplayModeRequestPending = true
        modeController.switchToCollectionBrowser(
            targetPagePosition: pagePosition
        ) { [weak self] _ in
            self?.isNavigationBackDisplayModeRequestPending = false
        }
        return true
    }

    private func setNavigationBarChromeVisible(_ isVisible: Bool, animated: Bool) {
        let animationDuration: TimeInterval?
        if animated {
            animationDuration = isVisible
                ? Self.navigationBarShowDuration
                : Self.navigationBarHideDuration
        } else {
            animationDuration = nil
        }

        playerNavigationController.setNavigationBarChromeVisible(
            isVisible,
            animationDuration: animationDuration
        )
    }

    var shouldBlockNavigationBackGesture: Bool {
        guard isInstalled,
              let topViewController = playerNavigationController.topViewController,
              isSessionViewController(topViewController) else {
            return false
        }

        return playerNavigationController.transitionCoordinator != nil
            || topViewController === playerViewController
            || chrome.isPlayerContentHiddenForCardTransition
            || isCardTransitionActive
    }

    @objc private func handleControlsPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            didControlsPanConflictWithHorizontalScroll = isHorizontalPlayerScrollActive()
            revealControlsIfAllowed(for: gesture)

        case .changed:
            if isHorizontalPlayerScrollActive() {
                didControlsPanConflictWithHorizontalScroll = true
            }
            revealControlsIfAllowed(for: gesture)

        case .ended, .cancelled, .failed:
            didControlsPanConflictWithHorizontalScroll = false

        default:
            break
        }
    }

    func shouldReceiveNavigationBarTap(_ touch: UITouch) -> Bool {
        let navigationBar = playerNavigationController.navigationBar
        let location = touch.location(in: navigationBar)
        guard navigationBar.bounds.contains(location) else {
            return false
        }

        return !isTouchInsideSideNavigationBarItem(touch, in: navigationBar)
    }

    private func isTouchInsideSideNavigationBarItem(
        _ touch: UITouch,
        in navigationBar: UINavigationBar
    ) -> Bool {
        var currentView = touch.view
        while let view = currentView, view !== navigationBar {
            if isSideNavigationBarItemView(view, in: navigationBar) {
                return true
            }

            currentView = view.superview
        }

        return false
    }

    private func isSideNavigationBarItemView(
        _ itemView: UIView,
        in navigationBar: UINavigationBar
    ) -> Bool {
        let itemFrame = itemView.convert(itemView.bounds, to: navigationBar)
        guard !itemFrame.isEmpty else {
            return false
        }

        let sideRegionWidth = min(
            Self.navigationBarSideControlRegionWidth,
            navigationBar.bounds.width / 3
        )

        let isInsideSideRegion = itemFrame.midX <= navigationBar.bounds.minX + sideRegionWidth
            || itemFrame.midX >= navigationBar.bounds.maxX - sideRegionWidth
        guard isInsideSideRegion else {
            return false
        }

        return itemView is UIControl || itemFrame.width <= Self.navigationBarSideControlRegionWidth
    }

    private func hasControlsRevealIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        view.bounds.contains(location)
            && velocity.y < -MobilePlayerGestureTuning.controlsRevealVelocity
            && abs(velocity.y) > abs(velocity.x) * MobilePlayerGestureTuning.controlsRevealVerticalIntentRatio
    }

    private func revealControlsIfAllowed(for gesture: UIPanGestureRecognizer) {
        guard !chrome.isCollectionBrowserActive,
              !didControlsPanConflictWithHorizontalScroll else {
            return
        }

        let translation = gesture.translation(in: view)
        guard hasControlsRevealTranslation(translation) else { return }

        chrome.setControlsVisible(true)
    }

    private func hasControlsRevealTranslation(_ translation: CGPoint) -> Bool {
        translation.y < -MobilePlayerGestureTuning.controlsRevealMinimumTranslation
            && abs(translation.y) > abs(translation.x) * MobilePlayerGestureTuning.controlsRevealVerticalIntentRatio
    }

    private func isHorizontalPlayerScrollActive() -> Bool {
        playerViewController.view
            .allSubviews(ofType: UIScrollView.self)
            .contains { scrollView in
                let panGesture = scrollView.panGestureRecognizer
                guard panGesture.state == .began || panGesture.state == .changed else { return false }

                let translation = panGesture.translation(in: view)
                return abs(translation.x) > MobilePlayerGestureTuning.controlsRevealHorizontalScrollTolerance
            }
    }


    func shouldBeginNavigationBarTap() -> Bool {
        guard !isCardTransitionActive,
              !chrome.isCollectionBrowserActive else {
            return false
        }

        return chrome.showControls
    }

    func shouldBeginControlsPan() -> Bool {
        guard !isCardTransitionActive,
              !chrome.isCollectionBrowserActive else {
            return false
        }

        let location = controlsPan.location(in: view)
        guard !hasZoomedPlayerContent(at: location) else {
            return false
        }

        let velocity = controlsPan.velocity(in: view)
        return hasControlsRevealIntent(location: location, velocity: velocity)
    }

    func clearPendingNavigationBackDisplayModeRequest() {
        isNavigationBackDisplayModeRequestPending = false
    }

    func invalidatePendingChromeUpdatesAndObservations() {
        navigationToolbarUpdate.invalidate()
        chromeObservationGeneration &+= 1
    }

    func removeNavigationBackActions() {
        if playerViewController.navigationItem.leftBarButtonItem === pagerBackBarButtonItem {
            playerViewController.navigationItem.leftBarButtonItem = nil
        }
        if let browserViewController,
           browserViewController.navigationItem.backAction?.identifier
            == navigationBackAction.identifier {
            browserViewController.navigationItem.backAction = nil
        }
    }

    func finishInvalidation() {
        playerNavigationController.navigationBar.layer.removeAllAnimations()
        playerNavigationController.navigationBar.alpha = 1
        setTopEdgeTintAlphaDirectly(1)
        playerNavigationController.setNeedsStatusBarAppearanceUpdate()
    }

    func finishNavigationBarChromeHideAnimation() {
        playerNavigationController.finishNavigationBarChromeHideAnimation()
    }

    private func configurePagingScrollViews() {
        delegate?.configurePagingScrollViews()
    }

    private func beginProgrammaticCardMinimize() -> Bool {
        delegate?.beginProgrammaticCardMinimize() ?? false
    }

    private func hasZoomedPlayerContent(at location: CGPoint) -> Bool {
        chrome.isPlayerContentZoomed && view.bounds.contains(location)
    }
}
