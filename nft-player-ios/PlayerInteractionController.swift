import UIKit

final class GestureFailureRequirementRegistry {

    private final class RequirementSet {
        weak var gestureRecognizer: UIGestureRecognizer?
        let requiredGestureRecognizers =
            NSHashTable<UIGestureRecognizer>(
                options: [.weakMemory, .objectPointerPersonality]
            )

        init(gestureRecognizer: UIGestureRecognizer) {
            self.gestureRecognizer = gestureRecognizer
        }
    }

    private var requirementSetsByGestureRecognizer =
        [ObjectIdentifier: RequirementSet]()

    func require(
        _ gestureRecognizer: UIGestureRecognizer,
        toFail requiredToFailGestureRecognizer: UIGestureRecognizer
    ) {
        let requirementSet = requirementSet(for: gestureRecognizer)
        let requiredGestureRecognizers =
            requirementSet.requiredGestureRecognizers
        guard !requiredGestureRecognizers.contains(
            requiredToFailGestureRecognizer
        ) else {
            return
        }

        gestureRecognizer.require(toFail: requiredToFailGestureRecognizer)
        requiredGestureRecognizers.add(requiredToFailGestureRecognizer)
    }

    func contains(
        _ gestureRecognizer: UIGestureRecognizer,
        requiringFailureOf requiredToFailGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let identifier = ObjectIdentifier(gestureRecognizer)
        guard let requirementSet = requirementSetsByGestureRecognizer[identifier],
              requirementSet.gestureRecognizer === gestureRecognizer else {
            return false
        }

        return requirementSet.requiredGestureRecognizers.contains(
            requiredToFailGestureRecognizer
        )
    }

    func removeInvalidRequirements() {
        requirementSetsByGestureRecognizer =
            requirementSetsByGestureRecognizer.filter {
                $0.value.gestureRecognizer != nil
            }
    }

    private func requirementSet(
        for gestureRecognizer: UIGestureRecognizer
    ) -> RequirementSet {
        let identifier = ObjectIdentifier(gestureRecognizer)
        if let requirementSet = requirementSetsByGestureRecognizer[identifier],
           requirementSet.gestureRecognizer === gestureRecognizer {
            return requirementSet
        }

        let requirementSet = RequirementSet(
            gestureRecognizer: gestureRecognizer
        )
        requirementSetsByGestureRecognizer[identifier] = requirementSet
        return requirementSet
    }
}

final class PlayerInteractionController: NSObject, UIGestureRecognizerDelegate {

    private let playerNavigationController: PlayerNavigationController
    private let playerViewController: MobilePlayerHostingController
    private let browserViewController: MobilePlayerBrowserPageViewController?

    private let navigationChromeCoordinator: PlayerNavigationChromeCoordinator
    private let cardTransitionCoordinator: PlayerCardTransitionCoordinator
    private let gestureFailureRequirements = GestureFailureRequirementRegistry()
    private var isInstalled = false

    private var view: UIView {
        playerViewController.view
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
        navigationChromeCoordinator = PlayerNavigationChromeCoordinator(
            navigationController: navigationController,
            playerViewController: playerViewController,
            browserViewController: browserViewController,
            modeController: modeController,
            chrome: chrome,
            onDismiss: onDismiss
        )
        cardTransitionCoordinator = PlayerCardTransitionCoordinator(
            navigationController: navigationController,
            playerViewController: playerViewController,
            browserViewController: browserViewController,
            modeController: modeController,
            chrome: chrome
        )
        super.init()
        navigationChromeCoordinator.delegate = self
        cardTransitionCoordinator.delegate = self
        navigationChromeCoordinator.configureNavigationBarChromeVisibilityEnforcement()
        cardTransitionCoordinator.configureCollectionBrowserExpandRequest()
        navigationChromeCoordinator.startChromeObservation()
    }

    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        navigationChromeCoordinator.installNavigationBackAction()
        playerViewController.onAccessibilityEscape = { [weak self] in
            self?.navigationChromeCoordinator.handleNavigationBackAction() ?? false
        }
        playerViewController.onPlayerLayout = { [weak self] in
            guard let self else { return }

            self.navigationChromeCoordinator.installNavigationBackAction()
            self.playerViewController.restoreNavigationTitleIfNeeded()
            self.playerNavigationController
                .configureNavigationBackGestureBlocking()
            self.configurePagerScrollViews()
        }
        browserViewController?.onAccessibilityEscape = { [weak self] in
            self?.navigationChromeCoordinator.handleNavigationBackAction() ?? false
        }
        browserViewController?.onPlayerLayout = { [weak self] in
            guard let self else { return }

            self.navigationChromeCoordinator.installNavigationBackAction()
            self.playerNavigationController
                .configureNavigationBackGestureBlocking()
            self.configureBrowserScrollViews()
        }
        playerViewController.loadViewIfNeeded()
        browserViewController?.loadViewIfNeeded()

        cardTransitionCoordinator.installCanvas()

        playerNavigationController.setNavigationBackGestureBlockingProvider(
            owner: self
        ) { [weak self] in
            self?.navigationChromeCoordinator.shouldBlockNavigationBackGesture ?? false
        }

        let navigationBarTap = navigationChromeCoordinator.navigationBarTap
        navigationBarTap.delegate = self
        navigationBarTap.numberOfTapsRequired = 1
        navigationBarTap.numberOfTouchesRequired = 1
        navigationBarTap.cancelsTouchesInView = false
        playerNavigationController.navigationBar.addGestureRecognizer(navigationBarTap)

        let dismissPan = cardTransitionCoordinator.dismissPan
        dismissPan.delegate = self
        dismissPan.cancelsTouchesInView = false
        dismissPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(dismissPan)

        let controlsPan = navigationChromeCoordinator.controlsPan
        controlsPan.delegate = self
        controlsPan.cancelsTouchesInView = false
        controlsPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(controlsPan)

        playerNavigationController.configureNavigationBackGestureBlocking()

        let cardMinimizePinch = cardTransitionCoordinator.cardMinimizePinch
        cardMinimizePinch.delegate = self
        cardMinimizePinch.cancelsTouchesInView = false
        view.addGestureRecognizer(cardMinimizePinch)

        let pinchRotation = cardTransitionCoordinator.pinchRotation
        pinchRotation.delegate = self
        pinchRotation.cancelsTouchesInView = false
        view.addGestureRecognizer(pinchRotation)

        configurePagingScrollViews()
    }

    func invalidate() {
        guard isInstalled else { return }
        isInstalled = false
        navigationChromeCoordinator.clearPendingNavigationBackDisplayModeRequest()
        cardTransitionCoordinator.invalidatePendingCardMinimizePinchUpdate()
        navigationChromeCoordinator.invalidatePendingChromeUpdatesAndObservations()
        playerViewController.onAccessibilityEscape = nil
        playerViewController.onPlayerLayout = nil
        browserViewController?.onAccessibilityEscape = nil
        browserViewController?.onPlayerLayout = nil

        navigationChromeCoordinator.removeNavigationBackActions()
        playerNavigationController.clearNavigationBackGestureBlockingProvider(
            owner: self
        )
        playerNavigationController.canEnforceNavigationBarChromeVisibility = nil
        playerNavigationController.resetNavigationBarChromeVisibilityState()
        playerNavigationController.navigationBar.removeGestureRecognizer(
            navigationChromeCoordinator.navigationBarTap
        )
        view.removeGestureRecognizer(cardTransitionCoordinator.dismissPan)
        view.removeGestureRecognizer(navigationChromeCoordinator.controlsPan)
        view.removeGestureRecognizer(cardTransitionCoordinator.cardMinimizePinch)
        view.removeGestureRecognizer(cardTransitionCoordinator.pinchRotation)

        cardTransitionCoordinator.cleanupTransitionsAndCanvas()
        cardTransitionCoordinator.finishInvalidation()
        navigationChromeCoordinator.finishInvalidation()
    }

    func didShowPlayerAfterNavigationTransition() {
        navigationChromeCoordinator.didShowPlayerAfterNavigationTransition()
    }

    func prepareForNavigationPopTransition(
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        navigationChromeCoordinator.prepareForNavigationPopTransition(
            using: transitionCoordinator
        )
    }

    func prepareForPlayerPresentation(
        for targetViewController: UIViewController?,
        using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        navigationChromeCoordinator.prepareForPlayerPresentation(
            for: targetViewController,
            using: transitionCoordinator
        )
    }

    private func requireNavigationBackGesturesToTakePriority(
        over gestureRecognizer: UIGestureRecognizer
    ) {
        playerNavigationController.interactiveBackGestureRecognizers.forEach {
            navigationBackGestureRecognizer in
            gestureFailureRequirements.require(
                gestureRecognizer,
                toFail: navigationBackGestureRecognizer
            )
        }
    }

    func configurePagingScrollViews() {
        configurePagerScrollViews()
        configureBrowserScrollViews()
    }

    func configurePagerScrollViews() {
        gestureFailureRequirements.removeInvalidRequirements()
        playerViewController.view
            .allSubviews(ofType: UIScrollView.self)
            .forEach { scrollView in
                gestureFailureRequirements.require(
                    scrollView.panGestureRecognizer,
                    toFail: cardTransitionCoordinator.dismissPan
                )
                if let pinchGesture = scrollView.pinchGestureRecognizer {
                    gestureFailureRequirements.require(
                        pinchGesture,
                        toFail: cardTransitionCoordinator.cardMinimizePinch
                    )
                }
                scrollView.hideAutomaticScrollEdgeEffects()
            }
    }

    private func configureBrowserScrollViews() {
        guard let browserViewController else { return }

        gestureFailureRequirements.removeInvalidRequirements()
        browserViewController.view
            .allSubviews(ofType: UIScrollView.self)
            .forEach { scrollView in
                if scrollView is MobilePlayerCollectionBrowserCollectionView {
                    requireNavigationBackGesturesToTakePriority(
                        over: scrollView.panGestureRecognizer
                    )
                }
                scrollView.hideAutomaticScrollEdgeEffects()
            }
    }

    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === navigationChromeCoordinator.navigationBarTap {
            return navigationChromeCoordinator.shouldBeginNavigationBarTap()
        }

        if gestureRecognizer === navigationChromeCoordinator.controlsPan {
            return navigationChromeCoordinator.shouldBeginControlsPan()
        }

        if gestureRecognizer === cardTransitionCoordinator.cardMinimizePinch {
            return cardTransitionCoordinator.canBeginCardMinimizePinch()
        }

        if gestureRecognizer === cardTransitionCoordinator.pinchRotation {
            return cardTransitionCoordinator.canBeginPinchRotation()
        }

        guard gestureRecognizer === cardTransitionCoordinator.dismissPan else {
            return true
        }

        return cardTransitionCoordinator.shouldBeginDismissPan()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === navigationChromeCoordinator.navigationBarTap else {
            return true
        }

        return navigationChromeCoordinator.shouldReceiveNavigationBarTap(touch)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if isPinchAndRotationPair(gestureRecognizer, otherGestureRecognizer) {
            return true
        }

        if gestureRecognizer === cardTransitionCoordinator.pinchRotation {
            return isPlayerScrollViewPinchGesture(otherGestureRecognizer)
        }
        if otherGestureRecognizer === cardTransitionCoordinator.pinchRotation {
            return isPlayerScrollViewPinchGesture(gestureRecognizer)
        }

        if gestureRecognizer === navigationChromeCoordinator.navigationBarTap
            || otherGestureRecognizer === navigationChromeCoordinator.navigationBarTap {
            return false
        }

        return gestureRecognizer === navigationChromeCoordinator.controlsPan
            || otherGestureRecognizer === navigationChromeCoordinator.controlsPan
    }

    private func isPinchAndRotationPair(
        _ gestureRecognizer: UIGestureRecognizer,
        _ otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === cardTransitionCoordinator.pinchRotation
            && isRotationEnabledPinch(otherGestureRecognizer))
            || (otherGestureRecognizer === cardTransitionCoordinator.pinchRotation
                && isRotationEnabledPinch(gestureRecognizer))
    }

    private func isRotationEnabledPinch(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === cardTransitionCoordinator.cardMinimizePinch
    }

    private func isPlayerScrollViewPinchGesture(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureFailureRequirements.contains(
            gestureRecognizer,
            requiringFailureOf: cardTransitionCoordinator.cardMinimizePinch
        )
    }
}

extension PlayerInteractionController:
    PlayerNavigationChromeCoordinatorDelegate,
    PlayerCardTransitionCoordinatorDelegate {

    var isPlayerInteractionInstalled: Bool {
        isInstalled
    }

    var isCardTransitionActive: Bool {
        cardTransitionCoordinator.isCardTransitionActive
    }

    func beginProgrammaticCardMinimize() -> Bool {
        cardTransitionCoordinator.beginProgrammaticCardMinimize()
    }

    func setCardTransitionCanvasBackgroundColor(_ color: UIColor) {
        cardTransitionCoordinator.setCanvasBackgroundColor(color)
    }

    func finishNavigationBarChromeHideAnimation() {
        navigationChromeCoordinator.finishNavigationBarChromeHideAnimation()
    }

    func setTopEdgeTintAlphaDirectly(_ alpha: CGFloat) {
        navigationChromeCoordinator.setTopEdgeTintAlphaDirectly(alpha)
    }

    func animateTopEdgeTint(to alpha: CGFloat, delay: TimeInterval) {
        navigationChromeCoordinator.animateTopEdgeTint(
            to: alpha,
            delay: delay
        )
    }
}

extension UIView {

    func allSubviews<T: UIView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            var matchingSubviews = subview.allSubviews(ofType: type)
            if let subview = subview as? T {
                matchingSubviews.append(subview)
            }
            return matchingSubviews
        }
    }
}
