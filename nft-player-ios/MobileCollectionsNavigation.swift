import SwiftUI
import UIKit

struct MobileCollectionsNavigationView<RootView: View>: UIViewControllerRepresentable {

    let rootView: RootView
    let playerConfig: MobilePlayerConfig?
    let presentationTransition: PlayerPresentationTransition
    let onWillDismissPlayer: () -> ((Bool) -> Void)?
    let onDidPresentPlayer: (MobilePlayerConfig) -> Void
    let onDismissPlayer: (MobilePlayerConfig) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> PlayerNavigationController {
        let rootViewController = UIHostingController(rootView: rootView)
        rootViewController.navigationItem.backButtonDisplayMode = .minimal
        rootViewController.navigationItem.backButtonTitle = Strings.nftPlayer

        let navigationController = PlayerNavigationController(
            rootViewController: rootViewController
        )
        navigationController.navigationBar.isTranslucent = true
        navigationController.setNavigationBarHidden(false, animated: false)
        configureNavigationBarAppearance(navigationController.navigationBar)
        navigationController.delegate = context.coordinator

        context.coordinator.attach(
            navigationController: navigationController,
            rootViewController: rootViewController
        )
        context.coordinator.update(
            playerConfig: playerConfig,
            presentationTransition: presentationTransition,
            onWillDismissPlayer: onWillDismissPlayer,
            onDidPresentPlayer: onDidPresentPlayer,
            onDismissPlayer: onDismissPlayer
        )
        return navigationController
    }

    func updateUIViewController(
        _ navigationController: PlayerNavigationController,
        context: Context
    ) {
        context.coordinator.rootViewController?.rootView = rootView
        context.coordinator.update(
            playerConfig: playerConfig,
            presentationTransition: presentationTransition,
            onWillDismissPlayer: onWillDismissPlayer,
            onDidPresentPlayer: onDidPresentPlayer,
            onDismissPlayer: onDismissPlayer
        )
    }

    static func dismantleUIViewController(
        _ navigationController: PlayerNavigationController,
        coordinator: Coordinator
    ) {
        coordinator.invalidate()
    }

    private func configureNavigationBarAppearance(_ navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate {

        private final class PlayerPresentationSession {
            let playbackSession: MobilePlaybackSession
            let chrome: MobilePlayerChromeController
            let pagerViewController: MobilePlayerHostingController
            let browserViewController: MobilePlayerBrowserPageViewController?
            let modeController: MobilePlayerSessionModeController
            let interactionController: PlayerInteractionController
            let initialStack: [UIViewController]

            var config: MobilePlayerConfig {
                playbackSession.config
            }

            init(
                playbackSession: MobilePlaybackSession,
                chrome: MobilePlayerChromeController,
                pagerViewController: MobilePlayerHostingController,
                browserViewController: MobilePlayerBrowserPageViewController?,
                modeController: MobilePlayerSessionModeController,
                interactionController: PlayerInteractionController,
                initialStack: [UIViewController]
            ) {
                self.playbackSession = playbackSession
                self.chrome = chrome
                self.pagerViewController = pagerViewController
                self.browserViewController = browserViewController
                self.modeController = modeController
                self.interactionController = interactionController
                self.initialStack = initialStack
            }

            @inline(never)
            deinit {}

            func owns(_ viewController: UIViewController?) -> Bool {
                guard let viewController else { return false }
                return viewController === pagerViewController
                    || viewController === browserViewController
            }

            func invalidate() {
                updateExternalDisplayToken(GeneratedToken.empty)
                NativeMetalCardView.resetMotionCalibration()
                playbackSession.stopAndDisconnect()
                interactionController.invalidate()
                modeController.invalidate()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }

        weak var rootViewController: UIHostingController<RootView>?
        private weak var navigationController: PlayerNavigationController?
        private var activeSession: PlayerPresentationSession?
        private var desiredPlayerConfig: MobilePlayerConfig?
        private var desiredPresentationTransition: PlayerPresentationTransition = .animated
        private var onWillDismissPlayer: (() -> ((Bool) -> Void)?)?
        private var onDidPresentPlayer: ((MobilePlayerConfig) -> Void)?
        private var onDismissPlayer: ((MobilePlayerConfig) -> Void)?
        private var dismissedConfigIDAwaitingStateUpdate: UUID?
        private var isReconcileScheduled = false
        private var reconcileTask: Task<Void, Never>?
        private var isAwaitingNavigationTransition = false

        @inline(never)
        deinit {}

        func attach(
            navigationController: PlayerNavigationController,
            rootViewController: UIHostingController<RootView>
        ) {
            self.navigationController = navigationController
            self.rootViewController = rootViewController
        }

        func update(
            playerConfig: MobilePlayerConfig?,
            presentationTransition: PlayerPresentationTransition,
            onWillDismissPlayer: @escaping () -> ((Bool) -> Void)?,
            onDidPresentPlayer: @escaping (MobilePlayerConfig) -> Void,
            onDismissPlayer: @escaping (MobilePlayerConfig) -> Void
        ) {
            desiredPlayerConfig = playerConfig
            desiredPresentationTransition = presentationTransition
            self.onWillDismissPlayer = onWillDismissPlayer
            self.onDidPresentPlayer = onDidPresentPlayer
            self.onDismissPlayer = onDismissPlayer
            if dismissedConfigIDAwaitingStateUpdate != playerConfig?.id {
                dismissedConfigIDAwaitingStateUpdate = nil
            }
            if playerConfig != nil,
               !presentationTransition.animatesNavigationTransition {
                reconcileNavigationState()
            } else {
                scheduleReconcile()
            }
        }

        func invalidate() {
            isReconcileScheduled = false
            reconcileTask?.cancel()
            reconcileTask = nil
            isAwaitingNavigationTransition = false
            activeSession?.invalidate()
            activeSession = nil
            navigationController?.delegate = nil
            navigationController = nil
            rootViewController = nil
            onWillDismissPlayer = nil
            onDidPresentPlayer = nil
            onDismissPlayer = nil
        }

        private func scheduleReconcile() {
            guard !isReconcileScheduled else { return }
            isReconcileScheduled = true
            reconcileTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                self.isReconcileScheduled = false
                self.reconcileTask = nil
                self.reconcileNavigationState()
            }
        }

        private func reconcileNavigationState() {
            guard let navigationController,
                  let rootViewController else {
                return
            }

            if let transitionCoordinator = navigationController.transitionCoordinator {
                awaitNavigationTransition(transitionCoordinator)
                return
            }

            guard let desiredPlayerConfig else {
                guard let activeSession,
                      activeSession.owns(navigationController.topViewController) else {
                    return
                }
                navigationController.popToRootViewController(animated: true)
                return
            }

            guard dismissedConfigIDAwaitingStateUpdate != desiredPlayerConfig.id else {
                return
            }
            if activeSession?.config.id == desiredPlayerConfig.id {
                return
            }

            if activeSession == nil,
               navigationController.topViewController === rootViewController {
                let session = makePlayerSession(
                    config: desiredPlayerConfig,
                    navigationController: navigationController
                )
                activeSession = session
                navigationController.navigationBar.layer.removeAllAnimations()
                session.interactionController.prepareForPlayerPresentation(
                    for: session.initialStack.last,
                    using: nil
                )
                if session.initialStack.count == 1,
                   let playerViewController = session.initialStack.first {
                    navigationController.pushViewController(
                        playerViewController,
                        animated: desiredPresentationTransition.animatesNavigationTransition
                    )
                } else {
                    navigationController.setViewControllers(
                        [rootViewController] + session.initialStack,
                        animated: false
                    )
                }
                session.interactionController.prepareForPlayerPresentation(
                    for: session.initialStack.last,
                    using: navigationController.transitionCoordinator
                )
                return
            }

            replaceActivePlayer(
                with: desiredPlayerConfig,
                navigationController: navigationController,
                rootViewController: rootViewController
            )
        }

        private func awaitNavigationTransition(
            _ transitionCoordinator: any UIViewControllerTransitionCoordinator
        ) {
            guard !isAwaitingNavigationTransition else { return }
            isAwaitingNavigationTransition = true
            let didRegisterCompletion = transitionCoordinator.animate(
                alongsideTransition: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.isAwaitingNavigationTransition = false
                self.scheduleReconcile()
            }
            if !didRegisterCompletion {
                isAwaitingNavigationTransition = false
                scheduleReconcile()
            }
        }

        private func makePlayerSession(
            config: MobilePlayerConfig,
            navigationController: PlayerNavigationController
        ) -> PlayerPresentationSession {
            let playbackSession = MobilePlaybackController.shared.startSession(
                config: config
            )
            let collectionBrowserAvailable = PlayerCollectionBrowserSupport.isAvailable(
                for: config
            )
            let initialDisplayMode = MobilePlayerDisplayMode.initialMode(
                for: config,
                collectionBrowserAvailable: collectionBrowserAvailable
            )
            let chrome = MobilePlayerChromeController(
                playerBackgroundColor: MobilePlayerBackgroundColor.color(for: config),
                allowsNavigationBackSwipe: initialDisplayMode == .collectionBrowser
            )
            if let widgetTokenInsertion = config.widgetTokenInsertion {
                chrome.setPlayerNavigationTitle(
                    collectionTitle: widgetTokenInsertion.insertedToken.collectionName,
                    pageLabel: Strings.pagePosition(
                        current: widgetTokenInsertion.insertedTokenIndex + 1,
                        total: widgetTokenInsertion.anchorProgress.tokenCount
                    )
                )
            }
            let onDismiss: () -> Void = { [weak self] in
                self?.requestPop(configID: config.id)
            }
            let browserViewController = collectionBrowserAvailable
                ? MobilePlayerBrowserPageViewController(
                    playbackSession: playbackSession,
                    chrome: chrome
                )
                : nil
            let playerViewController = makeMobilePlayerViewController(
                playbackSession: playbackSession,
                onDismiss: onDismiss,
                chrome: chrome
            )
            let modeController = MobilePlayerSessionModeController(
                playbackSession: playbackSession,
                chrome: chrome,
                navigationController: navigationController,
                browserViewController: browserViewController,
                pagerViewController: playerViewController,
                initialMode: initialDisplayMode
            )
            browserViewController?.modeController = modeController
            NativeMetalCardView.resetMotionCalibration()
            UIApplication.shared.isIdleTimerDisabled = true

            navigationController.loadViewIfNeeded()
            let navigationBounds = navigationController.view.bounds
            playerViewController.loadViewIfNeeded()
            playerViewController.view.frame = navigationBounds
            playerViewController.view.layoutIfNeeded()
            if let browserViewController {
                browserViewController.loadViewIfNeeded()
                browserViewController.view.frame = navigationBounds
                browserViewController.view.layoutIfNeeded()
                browserViewController.seedNavigationTitles()
            }
            if initialDisplayMode == .collectionBrowser {
                chrome.pagerProvider?.deactivatePagerForCollectionBrowser()
                browserViewController?.setBrowserActive(true)
            }

            let interactionController = PlayerInteractionController(
                navigationController: navigationController,
                playerViewController: playerViewController,
                browserViewController: browserViewController,
                modeController: modeController,
                chrome: chrome,
                onDismiss: onDismiss
            )
            interactionController.install()

            let initialStack: [UIViewController]
            if let browserViewController {
                initialStack = initialDisplayMode == .collectionBrowser
                    ? [browserViewController]
                    : [browserViewController, playerViewController]
            } else {
                initialStack = [playerViewController]
            }
            return PlayerPresentationSession(
                playbackSession: playbackSession,
                chrome: chrome,
                pagerViewController: playerViewController,
                browserViewController: browserViewController,
                modeController: modeController,
                interactionController: interactionController,
                initialStack: initialStack
            )
        }

        private func replaceActivePlayer(
            with config: MobilePlayerConfig,
            navigationController: PlayerNavigationController,
            rootViewController: UIHostingController<RootView>
        ) {
            activeSession?.invalidate()

            let session = makePlayerSession(
                config: config,
                navigationController: navigationController
            )
            activeSession = session
            navigationController.setViewControllers(
                [rootViewController] + session.initialStack,
                animated: desiredPresentationTransition.animatesNavigationTransition
                    && session.initialStack.count == 1
            )
            session.interactionController.prepareForPlayerPresentation(
                for: session.initialStack.last,
                using: navigationController.transitionCoordinator
            )
        }

        private func requestPop(configID: UUID) {
            guard let navigationController,
                  let activeSession,
                  activeSession.config.id == configID,
                  activeSession.owns(navigationController.topViewController),
                  navigationController.transitionCoordinator == nil else {
                return
            }
            let resolvePendingPresentation = onWillDismissPlayer?()
            resolvePendingPresentation?(true)
            activeSession.playbackSession.cancelPendingCollectionRestart()
            navigationController.popToRootViewController(animated: true)
        }

        func navigationController(
            _ navigationController: UINavigationController,
            willShow viewController: UIViewController,
            animated: Bool
        ) {
            if let activeSession,
               activeSession.owns(viewController) {
                activeSession.modeController.noteNavigationWillShow(viewController)
                activeSession.interactionController.prepareForPlayerPresentation(
                    for: viewController,
                    using: navigationController.transitionCoordinator
                )
                return
            }

            guard viewController === rootViewController,
                  let activeSession else { return }
            schedulePendingPresentationCancellation(
                using: navigationController.transitionCoordinator
            )
            activeSession.interactionController.prepareForNavigationPopTransition(
                using: navigationController.transitionCoordinator
            )
        }

        private func schedulePendingPresentationCancellation(
            using transitionCoordinator: (any UIViewControllerTransitionCoordinator)?
        ) {
            guard let resolution = onWillDismissPlayer?() else { return }
            guard let transitionCoordinator else {
                resolution(true)
                return
            }
            let didRegisterCompletion = transitionCoordinator.animate(
                alongsideTransition: nil
            ) { context in
                resolution(!context.isCancelled)
            }
            if !didRegisterCompletion {
                resolution(true)
            }
        }

        func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            if let activeSession,
               activeSession.owns(viewController) {
                activeSession.modeController.noteNavigationDidShow(viewController)
                activeSession.interactionController.didShowPlayerAfterNavigationTransition()
                let presentedConfig = activeSession.config
                Task { @MainActor [weak self] in
                    self?.onDidPresentPlayer?(presentedConfig)
                }
                scheduleReconcile()
                return
            }

            guard viewController === rootViewController,
                  let completedSession = activeSession else {
                restoreRootNavigationState(navigationController)
                scheduleReconcile()
                return
            }

            activeSession = nil
            dismissedConfigIDAwaitingStateUpdate = completedSession.config.id
            completedSession.invalidate()
            restoreRootNavigationState(navigationController)
            let completedConfig = completedSession.config
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.onDismissPlayer?(completedConfig)
            }
            scheduleReconcile()
        }

        private func restoreRootNavigationState(_ navigationController: UINavigationController) {
            navigationController.navigationBar.layer.removeAllAnimations()
            navigationController.navigationBar.layer.isHidden = false
            navigationController.navigationBar.alpha = 1
            navigationController.navigationBar.accessibilityElementsHidden = false
            navigationController.setNeedsStatusBarAppearanceUpdate()
            rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
}

private func makeMobilePlayerViewController(
    playbackSession: MobilePlaybackSession,
    onDismiss: @escaping () -> Void,
    chrome: MobilePlayerChromeController
) -> MobilePlayerHostingController {
    let playerViewController = MobilePlayerHostingController(
        rootView: MobilePlayerView(
            playbackSession: playbackSession,
            onDismiss: onDismiss,
            chrome: chrome
        )
    )
    playerViewController.installNavigationTitle(chrome: chrome)
    return playerViewController
}

final class MobilePlayerHostingController: UIHostingController<MobilePlayerView> {

    private var playerPageBackgroundColor = MobilePlayerBackgroundColor.defaultColor
    private var playerNavigationTitleView: UIView?
    var onAccessibilityEscape: (() -> Bool)?
    var onPlayerLayout: (() -> Void)?

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .none
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyPlayerPageBackground()
        restoreNavigationTitleIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restoreNavigationTitleIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyPlayerPageBackground()
        onPlayerLayout?()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyPlayerPageBackground()
    }

    override func accessibilityPerformEscape() -> Bool {
        if onAccessibilityEscape?() == true {
            return true
        }

        return super.accessibilityPerformEscape()
    }

    func setPlayerPageBackground(color: UIColor) {
        playerPageBackgroundColor = color

        guard isViewLoaded else { return }
        applyPlayerPageBackground()
    }

    func installNavigationTitle(chrome: MobilePlayerChromeController) {
        guard playerNavigationTitleView == nil else {
            restoreNavigationTitleIfNeeded()
            return
        }

        let titleView = UIHostingConfiguration {
            PlayerNavigationTitleView(chrome: chrome)
        }
        .margins(.all, 0)
        .makeContentView()
        playerNavigationTitleView = titleView
        navigationItem.titleView = titleView
    }

    func restoreNavigationTitleIfNeeded() {
        guard let playerNavigationTitleView,
              navigationItem.titleView !== playerNavigationTitleView else {
            return
        }
        navigationItem.titleView = playerNavigationTitleView
    }

    private func applyPlayerPageBackground() {
        view.backgroundColor = playerPageBackgroundColor
        view.isOpaque = true
    }

}

private final class NavigationBackGestureGate:
    UIPanGestureRecognizer,
    UIGestureRecognizerDelegate {

    var shouldBlockNavigationBack: () -> Bool = { false }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)

        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        maximumNumberOfTouches = 1
        allowedScrollTypesMask = .all
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        shouldBlockNavigationBack()
    }

    override func canPrevent(
        _ preventedGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    override func canBePrevented(
        by preventingGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

private final class NavigationBackDirectTouchGate: UIGestureRecognizer {

    var shouldBlockNavigationBack: () -> Bool = { false }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)

        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func shouldReceive(_ event: UIEvent) -> Bool {
        guard super.shouldReceive(event) else { return false }
        return event.type == .touches
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard state == .possible else { return }

        state = shouldBlockNavigationBack() ? .recognized : .failed
    }

    override func canPrevent(
        _ preventedGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    override func canBePrevented(
        by preventingGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

private final class PlayerTopEdgeTintView: UIView {

    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.68).cgColor,
            UIColor.black.withAlphaComponent(0.50).cgColor,
            UIColor.black.withAlphaComponent(0.32).cgColor,
            UIColor.black.withAlphaComponent(0.17).cgColor,
            UIColor.black.withAlphaComponent(0.06).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor,
        ]
        gradientLayer.locations = [0, 0.2, 0.4, 0.6, 0.8, 1]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        CATransaction.commit()
    }
}

final class PlayerNavigationController: UINavigationController {

    var canEnforceNavigationBarChromeVisibility: (() -> Bool)?
    weak var cardTransitionOverlayView: UIView?
    private let topEdgeTintView = PlayerTopEdgeTintView()
    private var navigationBarChromeTargetAlpha: CGFloat?
    private var isNavigationBarChromeVisibilityEnforcementSuspended = false
    private var forcesStatusBarVisibleForCollectionBrowserTransition = false
    private weak var navigationBackGestureBlockingProviderOwner: AnyObject?
    private var navigationBackGestureBlockingProvider: (() -> Bool)?
    private let navigationBackGestureFailureRequirements =
        GestureFailureRequirementRegistry()
    private lazy var navigationBackDirectTouchGate:
        NavigationBackDirectTouchGate = {
            let gestureRecognizer = NavigationBackDirectTouchGate(
                target: nil,
                action: nil
            )
            gestureRecognizer.shouldBlockNavigationBack = { [weak self] in
                self?.navigationBackGestureBlockingProvider?() ?? false
            }
            return gestureRecognizer
        }()
    private lazy var navigationBackGestureGate: NavigationBackGestureGate = {
        let gestureRecognizer = NavigationBackGestureGate(
            target: nil,
            action: nil
        )
        gestureRecognizer.shouldBlockNavigationBack = { [weak self] in
            self?.navigationBackGestureBlockingProvider?() ?? false
        }
        return gestureRecognizer
    }()

    var interactiveBackGestureRecognizers: [UIGestureRecognizer] {
        var gestureRecognizers = [UIGestureRecognizer]()
        if let interactivePopGestureRecognizer {
            gestureRecognizers.append(interactivePopGestureRecognizer)
        }
        if #available(iOS 26.0, *),
           let interactiveContentPopGestureRecognizer {
            gestureRecognizers.append(interactiveContentPopGestureRecognizer)
        }
        return gestureRecognizers
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.insertSubview(topEdgeTintView, belowSubview: navigationBar)
        view.addGestureRecognizer(navigationBackDirectTouchGate)
        view.addGestureRecognizer(navigationBackGestureGate)
        configureNavigationBackGestureBlocking()
    }

    func setNavigationBackGestureBlockingProvider(
        owner: AnyObject,
        provider: @escaping () -> Bool
    ) {
        navigationBackGestureBlockingProviderOwner = owner
        navigationBackGestureBlockingProvider = provider
        configureNavigationBackGestureBlocking()
    }

    func clearNavigationBackGestureBlockingProvider(owner: AnyObject) {
        guard navigationBackGestureBlockingProviderOwner === owner else {
            return
        }

        navigationBackGestureBlockingProviderOwner = nil
        navigationBackGestureBlockingProvider = nil
    }

    func configureNavigationBackGestureBlocking() {
        loadViewIfNeeded()
        navigationBackGestureFailureRequirements.removeInvalidRequirements()
        interactiveBackGestureRecognizers.forEach { gestureRecognizer in
            navigationBackGestureFailureRequirements.require(
                gestureRecognizer,
                toFail: navigationBackDirectTouchGate
            )
            navigationBackGestureFailureRequirements.require(
                gestureRecognizer,
                toFail: navigationBackGestureGate
            )
        }
    }

    override var childForStatusBarHidden: UIViewController? {
        forcesStatusBarVisibleForCollectionBrowserTransition
            ? nil
            : topViewController
    }

    override var prefersStatusBarHidden: Bool {
        forcesStatusBarVisibleForCollectionBrowserTransition
            ? false
            : super.prefersStatusBarHidden
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .none
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        alignNavigationBarBelowForcedStatusBar()
        synchronizeNavigationBarChromeVisibility()
        keepCardTransitionOverlayBelowNavigationBar()
        layoutTopEdgeTint()
    }

    private func keepCardTransitionOverlayBelowNavigationBar() {
        guard let cardTransitionOverlayView,
              cardTransitionOverlayView.superview === view else {
            return
        }

        cardTransitionOverlayView.frame = view.bounds
        view.insertSubview(cardTransitionOverlayView, belowSubview: navigationBar)
    }

    func assertTopEdgeTintPlacement() {
        layoutTopEdgeTint()
    }

    private func layoutTopEdgeTint() {
        let statusBarInset = view.safeAreaInsets.top
        let hasStatusBarRegion = statusBarInset >= 20
        topEdgeTintView.isHidden = !hasStatusBarRegion
        topEdgeTintView.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: statusBarInset * 2.9
        )
        view.insertSubview(topEdgeTintView, belowSubview: navigationBar)
    }

    func setTopEdgeTintAlpha(_ alpha: CGFloat) {
        topEdgeTintView.alpha = min(max(alpha, 0), 1)
    }

    var topEdgeTintAlpha: CGFloat {
        topEdgeTintView.alpha
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(hidden, animated: animated)

        guard !hidden else { return }
        synchronizeNavigationBarChromeVisibility()
    }

    func setCollectionBrowserTransitionStatusBarVisible(_ isVisible: Bool) {
        guard forcesStatusBarVisibleForCollectionBrowserTransition != isVisible else {
            return
        }

        forcesStatusBarVisibleForCollectionBrowserTransition = isVisible
        setNeedsStatusBarAppearanceUpdate()
        alignNavigationBarBelowForcedStatusBar()
    }

    private func alignNavigationBarBelowForcedStatusBar() {
        guard forcesStatusBarVisibleForCollectionBrowserTransition,
              let window = view.window,
              let statusBarManager = window.windowScene?.statusBarManager,
              !statusBarManager.isStatusBarHidden else {
            return
        }

        let statusBarFrameInWindow = window.convert(
            statusBarManager.statusBarFrame,
            from: window.screen.coordinateSpace
        )
        let statusBarFrameInView = view.convert(
            statusBarFrameInWindow,
            from: window
        )
        let navigationBarMinY = max(
            view.safeAreaInsets.top,
            statusBarFrameInView.maxY
        )
        guard navigationBarMinY.isFinite,
              abs(navigationBar.frame.minY - navigationBarMinY)
                > 1 / window.screen.scale else {
            return
        }

        var frame = navigationBar.frame
        frame.origin.y = navigationBarMinY
        navigationBar.frame = frame
    }

    func setNavigationBarChromeVisible(
        _ isVisible: Bool,
        animationDuration: TimeInterval?
    ) {
        let targetAlpha: CGFloat = isVisible ? 1 : 0
        navigationBarChromeTargetAlpha = targetAlpha

        guard !isNavigationBarChromeVisibilityEnforcementSuspended else {
            return
        }

        navigationBar.accessibilityElementsHidden = !isVisible
        if !isVisible {
            navigationBar.layer.isHidden = true
        }

        guard let animationDuration else {
            guard navigationBar.alpha != targetAlpha else {
                if isVisible {
                    navigationBar.layer.isHidden = false
                }
                return
            }

            navigationBar.layer.removeAllAnimations()
            navigationBar.alpha = targetAlpha
            if isVisible {
                navigationBar.layer.isHidden = false
            }
            return
        }

        if isVisible {
            navigationBar.layer.isHidden = false
        }
        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.navigationBar.alpha = targetAlpha
        } completion: { [weak self] _ in
            self?.synchronizeNavigationBarChromeVisibility()
        }
    }

    func finishNavigationBarChromeHideAnimation() {
        navigationBarChromeTargetAlpha = 0

        guard !isNavigationBarChromeVisibilityEnforcementSuspended,
              canEnforceNavigationBarChromeVisibility?() == true else {
            return
        }

        navigationBar.accessibilityElementsHidden = true
        navigationBar.layer.isHidden = true
        removeNavigationBarOpacityAnimations()
        UIView.performWithoutAnimation {
            navigationBar.alpha = 0
        }
    }

    func setNavigationBarChromeVisibilityEnforcementSuspended(
        _ isSuspended: Bool
    ) {
        isNavigationBarChromeVisibilityEnforcementSuspended = isSuspended
    }

    func resetNavigationBarChromeVisibilityState() {
        navigationBarChromeTargetAlpha = nil
        isNavigationBarChromeVisibilityEnforcementSuspended = false
        navigationBar.accessibilityElementsHidden = false
        navigationBar.layer.isHidden = false
    }

    func synchronizeNavigationBarChromeVisibility() {
        guard !isNavigationBarChromeVisibilityEnforcementSuspended,
              canEnforceNavigationBarChromeVisibility?() == true,
              let targetAlpha = navigationBarChromeTargetAlpha else {
            return
        }

        navigationBar.accessibilityElementsHidden = targetAlpha == 0
        if targetAlpha == 0 {
            navigationBar.layer.isHidden = true
        }
        guard navigationBar.alpha != targetAlpha else {
            if targetAlpha != 0 {
                navigationBar.layer.isHidden = false
            }
            return
        }

        navigationBar.layer.removeAllAnimations()
        navigationBar.alpha = targetAlpha
        if targetAlpha != 0 {
            navigationBar.layer.isHidden = false
        }
    }

    private func removeNavigationBarOpacityAnimations() {
        let layer = navigationBar.layer
        (layer.animationKeys() ?? []).forEach { key in
            guard let animation = layer.animation(forKey: key),
                  Self.affectsOpacity(animation) else {
                return
            }

            layer.removeAnimation(forKey: key)
        }
    }

    private static func affectsOpacity(_ animation: CAAnimation) -> Bool {
        if let propertyAnimation = animation as? CAPropertyAnimation,
           propertyAnimation.keyPath == "opacity" {
            return true
        }

        return (animation as? CAAnimationGroup)?
            .animations?
            .contains(where: affectsOpacity) == true
    }

}

