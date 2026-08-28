import UIKit

protocol PlayerCardTransitionCoordinatorDelegate: AnyObject {
    func configurePagerScrollViews()
    func finishNavigationBarChromeHideAnimation()
    func setTopEdgeTintAlphaDirectly(_ alpha: CGFloat)
    func animateTopEdgeTint(to alpha: CGFloat, delay: TimeInterval)
}

final class PlayerCardTransitionCoordinator: NSObject {

    private static let cardTransitionHorizontalDragDamping: CGFloat = 0.18
    private static let cardTransitionVerticalDragDamping: CGFloat = 0.32
    private static let cardMinimizeAnimationDuration: TimeInterval = 0.22

    private enum CardMinimizeCommitDestination {
        case browserCell(CGRect)
        case offscreen
    }

    private struct ZoomedCardMinimizeForeground {
        let view: UIView
        let sourceFrame: CGRect
    }

    private struct CardMinimizeTransitionContext {
        let id: UUID
        let sourcePagePosition: PlayerPagePosition
        let sourceFrame: CGRect
        let targetScale: CGFloat
        let commitDestination: CardMinimizeCommitDestination
        let foregroundView: UIView
        let zoomedForeground: ZoomedCardMinimizeForeground?
        let underlayView: CardTransitionUnderlayView
        let hasPreparedBrowserSelection: Bool
    }

    private struct CardExpandTransitionContext {
        let id: UUID
        let targetPagePosition: PlayerPagePosition
        let sourceFrame: CGRect
        let targetFrame: CGRect
        let foregroundView: UIView
        let underlayView: CardTransitionUnderlayView
    }

    @MainActor
    private final class CardMinimizeBrowserRequestState {
        var requestReturned = false
        var wasRejectedSynchronously = false
    }

    weak var delegate: (any PlayerCardTransitionCoordinatorDelegate)?

    private let playerNavigationController: PlayerNavigationController
    private let playerViewController: MobilePlayerHostingController
    private let browserViewController: MobilePlayerBrowserPageViewController?
    private let modeController: MobilePlayerSessionModeController
    private let chrome: MobilePlayerChromeController

    private let cardTransitionCanvas = MobilePlayerCardTransitionCanvas()

    private var view: UIView {
        playerViewController.view
    }

    private var shouldShowNavigationBarChrome: Bool {
        chrome.isPlayerChromeVisible
    }

    private var cardTransitionCanvasView: UIView {
        cardTransitionCanvas.view
    }

    lazy var dismissPan = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleDismissPan(_:))
    )
    lazy var cardMinimizePinch: CardLayoutPinchGestureRecognizer = {
        let gesture = CardLayoutPinchGestureRecognizer(
            target: self,
            action: #selector(handleCardMinimizePinch(_:))
        )
        gesture.activationScale = MobilePlayerGestureTuning.cardMinimizePinchActivationScale
        gesture.oppositeDirectionFailureScale = MobilePlayerGestureTuning.cardMinimizePinchZoomInFailureScale
        gesture.canTrackPinch = { [weak self] gesture in
            guard let self else { return false }
            if gesture.isFirstPinchTrackingEvaluation {
                self.configurePagerScrollViews()
            }
            return self.canBeginCardMinimizeInteraction(
                location: gesture.pinchLocation(in: self.view)
            )
        }
        return gesture
    }()
    lazy var pinchRotation = UIRotationGestureRecognizer(
        target: self,
        action: #selector(handlePinchRotation(_:))
    )

    private var isDismissPanDrivingCardMinimize = false
    private var isCardMinimizePinchDrivingCardMinimize = false
    private var cardMinimizePinchStartLocation = CGPoint.zero
    private var cardMinimizePinchStartRotation: CGFloat = 0
    private var cardMinimizePinchRotation: CGFloat = 0
    private lazy var cardMinimizePinchPresentationUpdate = PendingMainQueueUpdate { [weak self] in
        guard let self else { return }
        guard self.isCardMinimizePinchDrivingCardMinimize else { return }

        self.applyCardMinimizePinchPresentation(self.cardMinimizePinch)
    }
    private var activeCardMinimizeContext: CardMinimizeTransitionContext?
    private var activeCardExpandContext: CardExpandTransitionContext?
    private var isCardMinimizeAnimationComplete = false
    private var isCardMinimizeLayoutApplied = false
    private var isCardExpandAnimationComplete = false
    private var isCardExpandLayoutApplied = false
    private var playerInteractionEnabledBeforeLivePagerFade: Bool?

    init(
        navigationController: PlayerNavigationController,
        playerViewController: MobilePlayerHostingController,
        browserViewController: MobilePlayerBrowserPageViewController?,
        modeController: MobilePlayerSessionModeController,
        chrome: MobilePlayerChromeController
    ) {
        self.playerNavigationController = navigationController
        self.playerViewController = playerViewController
        self.browserViewController = browserViewController
        self.modeController = modeController
        self.chrome = chrome
        super.init()
    }

    func configureCollectionBrowserExpandRequest() {
        chrome.onCollectionBrowserExpandRequest = { [weak self] selection in
            self?.beginProgrammaticCardExpand(selection: selection) ?? .rejected
        }
    }

    func installCanvas() {
        playerNavigationController.loadViewIfNeeded()
        cardTransitionCanvasView.frame = playerNavigationController.view.bounds
        cardTransitionCanvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerNavigationController.view.insertSubview(
            cardTransitionCanvasView,
            belowSubview: playerNavigationController.navigationBar
        )
        playerNavigationController.cardTransitionOverlayView = cardTransitionCanvasView
    }

    func setCanvasBackgroundColor(_ color: UIColor) {
        cardTransitionCanvasView.backgroundColor = color
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            let location = gesture.location(in: view)
            let velocity = gesture.velocity(in: view)
            let hasPlayerDismissIntent = hasPlayerDismissIntent(location: location, velocity: velocity)
            let cardMinimizeAvailability = hasPlayerDismissIntent
                ? cardMinimizeAvailability(at: location)
                : .empty
            let shouldHideControls = chrome.showControls && hasControlsHideIntent(location: location, velocity: velocity)
            isDismissPanDrivingCardMinimize = false

            if let cardMinimizeState = cardMinimizeAvailability.animated {
                guard beginCardMinimizeFromDismissPan(state: cardMinimizeState) else { return }
            } else if let directCardMinimizeState = cardMinimizeAvailability.direct {
                guard beginDirectCardMinimizeFromDismissPan(state: directCardMinimizeState) else { return }
            }

            if !isDismissPanDrivingCardMinimize, shouldHideControls {
                chrome.setControlsVisible(false)
            }

        case .changed:
            guard isDismissPanDrivingCardMinimize else { return }
            applyCardMinimizePresentation(translation: translation)

        case .ended:
            guard isDismissPanDrivingCardMinimize else { return }
            isDismissPanDrivingCardMinimize = false
            finishCardMinimizeGesture(
                translation: translation,
                velocity: gesture.velocity(in: view)
            )

        case .cancelled, .failed:
            guard isDismissPanDrivingCardMinimize else { return }
            isDismissPanDrivingCardMinimize = false
            resetCardMinimizeTransform()

        default:
            break
        }
    }

    @objc private func handleCardMinimizePinch(_ gesture: CardLayoutPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            isCardMinimizePinchDrivingCardMinimize = false
            cardMinimizePinchStartLocation = gesture.initialPinchLocation(in: view)

            let location = gesture.pinchLocation(in: view)
            let availability = cardMinimizeAvailability(at: location)
            if let state = availability.animated {
                guard beginCardMinimizePinchGesture(state: state) else {
                    resetCardMinimizePinchState()
                    return
                }

                applyCardMinimizePinchPresentation(gesture)
                return
            }

            guard let state = availability.direct,
                  beginDirectCardMinimizePinchGesture(state: state) else {
                resetCardMinimizePinchState()
                return
            }
            applyCardMinimizePinchPresentation(gesture)

        case .changed:
            guard isCardMinimizePinchDrivingCardMinimize else { return }

            scheduleCardMinimizePinchPresentationUpdate()

        case .ended:
            if isCardMinimizePinchDrivingCardMinimize {
                flushPendingCardMinimizePinchPresentationUpdate()
                finishCardMinimizePinchGesture(
                    scale: gesture.scale,
                    velocity: gesture.velocity
                )
            }
            resetCardMinimizePinchState()

        case .cancelled, .failed:
            if isCardMinimizePinchDrivingCardMinimize {
                flushPendingCardMinimizePinchPresentationUpdate()
                resetCardMinimizeTransform()
            }
            resetCardMinimizePinchState()

        default:
            break
        }
    }

    @objc private func handlePinchRotation(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            if isCardMinimizePinchDrivingCardMinimize {
                cardMinimizePinchStartRotation = gesture.rotation
                cardMinimizePinchRotation = 0
            }

        case .changed:
            if isCardMinimizePinchDrivingCardMinimize {
                cardMinimizePinchRotation = gesture.rotation - cardMinimizePinchStartRotation
                scheduleCardMinimizePinchPresentationUpdate()
            }

        case .ended, .cancelled, .failed:
            if !isCardMinimizePinchDrivingCardMinimize {
                cardMinimizePinchRotation = 0
                cardMinimizePinchStartRotation = 0
            }

        default:
            break
        }
    }

    private var isCardMinimizeTransitionActive: Bool {
        activeCardMinimizeContext != nil
            || isDismissPanDrivingCardMinimize
            || isCardMinimizePinchDrivingCardMinimize
    }

    var isCardTransitionActive: Bool {
        isCardMinimizeTransitionActive || activeCardExpandContext != nil
    }

    private func beginCardMinimizeFromDismissPan(state: MobilePlayerLayoutInteractionState) -> Bool {
        beginCardMinimizeTransition(state: state, isDrivenByDismissPan: true)
    }

    private func beginDirectCardMinimizeFromDismissPan(state: MobilePlayerLayoutInteractionState) -> Bool {
        beginDirectCardMinimizeTransition(state: state, isDrivenByDismissPan: true)
    }

    private func beginCardMinimizePinchGesture(state: MobilePlayerLayoutInteractionState) -> Bool {
        guard beginCardMinimizeTransition(state: state, isDrivenByDismissPan: false) else {
            return false
        }

        beginCardMinimizePinchDriving()
        return true
    }

    private func beginDirectCardMinimizePinchGesture(state: MobilePlayerLayoutInteractionState) -> Bool {
        guard beginDirectCardMinimizeTransition(state: state, isDrivenByDismissPan: false) else {
            return false
        }

        beginCardMinimizePinchDriving()
        return true
    }

    private func beginCardMinimizePinchDriving() {
        cardMinimizePinchStartRotation = currentPinchRotationGestureValue()
        cardMinimizePinchRotation = 0
        isCardMinimizePinchDrivingCardMinimize = true
    }

    func beginProgrammaticCardMinimize() -> Bool {
        guard !isCardTransitionActive else {
            return true
        }

        let state = chrome.currentLayoutInteractionState()
        guard beginCardMinimizeTransition(
            state: state,
            isDrivenByDismissPan: false
        ) || beginDirectCardMinimizeTransition(
            state: state,
            isDrivenByDismissPan: false
        ) else {
            return false
        }

        completeCardMinimizeTransition()
        return true
    }

    func beginProgrammaticCardExpand(
        selection: MobilePlayerBrowserTransitionSelection
    ) -> MobilePlayerBrowserExpandSelectionResult {
        guard !chrome.isPlayerContentZoomed else {
            return .rejected
        }

        guard !isCardTransitionActive else {
            return .busy
        }
        guard beginCardExpandTransition(selection: selection) else {
            return .fallbackToImmediateOpen
        }

        completeCardExpandTransition()
        return .started
    }

    private func beginCardMinimizeTransition(
        state: MobilePlayerLayoutInteractionState,
        isDrivenByDismissPan: Bool
    ) -> Bool {
        view.layer.removeAllAnimations()

        guard let context = makeCardMinimizeTransitionContext(state: state) else {
            return false
        }

        return beginCardMinimizeTransition(
            context: context,
            isDrivenByDismissPan: isDrivenByDismissPan
        )
    }

    private func beginDirectCardMinimizeTransition(
        state: MobilePlayerLayoutInteractionState,
        isDrivenByDismissPan: Bool
    ) -> Bool {
        view.layer.removeAllAnimations()

        guard let context = makeDirectCardMinimizeTransitionContext(state: state) else {
            return false
        }

        return beginCardMinimizeTransition(
            context: context,
            isDrivenByDismissPan: isDrivenByDismissPan
        )
    }

    private func beginCardMinimizeTransition(
        context: CardMinimizeTransitionContext,
        isDrivenByDismissPan: Bool
    ) -> Bool {
        if !shouldShowNavigationBarChrome {
            delegate?.finishNavigationBarChromeHideAnimation()
        }

        activeCardMinimizeContext = context
        isDismissPanDrivingCardMinimize = isDrivenByDismissPan
        isCardMinimizeAnimationComplete = false
        isCardMinimizeLayoutApplied = false
        playerNavigationController
            .setCollectionBrowserTransitionStatusBarVisible(true)
        chrome.setPlayerContentHiddenForCardTransition(true)
        setTopEdgeTintAlphaDirectly(1)
        return true
    }

    private func beginCardExpandTransition(
        selection: MobilePlayerBrowserTransitionSelection
    ) -> Bool {
        view.layer.removeAllAnimations()

        modeController.stagePagerViewForTransition()

        guard let context = makeCardExpandTransitionContext(selection: selection) else {
            modeController.unstagePagerViewIfNeeded()
            return false
        }

        activeCardExpandContext = context
        isCardExpandAnimationComplete = false
        isCardExpandLayoutApplied = false
        chrome.setPlayerContentHiddenForCardTransition(true)
        applyCardExpandPresentation(progress: 0)
        return true
    }

    private func finishCardMinimizeGesture(
        translation: CGPoint,
        velocity: CGPoint
    ) {
        guard activeCardMinimizeContext != nil else {
            resetCardMinimizeTransform()
            return
        }

        guard shouldCompleteCardMinimizeGesture(translation: translation, velocity: velocity) else {
            resetCardMinimizeTransform()
            return
        }

        completeCardMinimizeTransition()
    }

    private func shouldCompleteCardMinimizeGesture(
        translation: CGPoint,
        velocity: CGPoint
    ) -> Bool {
        let clampedY = max(0, translation.y)
        let projectedY = clampedY + max(velocity.y, 0) * MobilePlayerGestureTuning.dismissVelocityProjectionDuration
        let translationThreshold = max(
            MobilePlayerGestureTuning.cardMinimizeMinimumTranslation,
            view.bounds.height * MobilePlayerGestureTuning.cardMinimizeTranslationHeightRatio
        )
        return projectedY > translationThreshold
            || (velocity.y > MobilePlayerGestureTuning.cardMinimizeFastSwipeVelocity
                && clampedY > MobilePlayerGestureTuning.cardMinimizeMinimumFastSwipeTranslation)
    }

    private func completeCardMinimizeTransition() {
        guard let context = activeCardMinimizeContext else {
            cleanupCardMinimizeTransition(revealPlayer: true)
            return
        }
        let contextID = context.id
        let requestState = CardMinimizeBrowserRequestState()

        modeController.switchToCollectionBrowser(
            targetPagePosition: context.sourcePagePosition
        ) { [weak self] didApply in
            guard let self,
                  self.activeCardMinimizeContext?.id == contextID else {
                return
            }
            guard didApply else {
                if requestState.requestReturned {
                    self.resetCardMinimizeTransform()
                } else {
                    requestState.wasRejectedSynchronously = true
                }
                return
            }

            self.isCardMinimizeLayoutApplied = true
            self.finishCardMinimizeTransitionIfReady()
        }
        requestState.requestReturned = true
        if requestState.wasRejectedSynchronously {
            resetCardMinimizeTransform()
            return
        }

        switch context.commitDestination {
        case .offscreen:
            completeOffscreenCardMinimizeTransition(context)
            return
        case .browserCell(let targetFrame):
            let foregroundView = context.foregroundView

            animateCardMinimizeTransition(
                context: context,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                foregroundView.transform = .identity
                foregroundView.bounds = CGRect(origin: .zero, size: targetFrame.size)
                foregroundView.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                if let zoomedForeground = context.zoomedForeground {
                    self.applyZoomedCardMinimizePresentation(
                        zoomedForeground,
                        frame: targetFrame
                    )
                }
                context.underlayView.setOtherCardsRevealProgress(1)
            }
            animateTopEdgeTint(to: 1)
        }
    }

    private func completeOffscreenCardMinimizeTransition(_ context: CardMinimizeTransitionContext) {
        let foregroundView = context.foregroundView
        let finalCenter = CGPoint(
            x: foregroundView.center.x,
            y: view.bounds.maxY + max(foregroundView.bounds.height, context.sourceFrame.height)
        )

        animateCardMinimizeTransition(
            context: context,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            foregroundView.center = finalCenter
            if let zoomedForeground = context.zoomedForeground {
                let targetFrame = CGRect(
                    x: finalCenter.x - context.sourceFrame.width / 2,
                    y: finalCenter.y - context.sourceFrame.height / 2,
                    width: context.sourceFrame.width,
                    height: context.sourceFrame.height
                )
                self.applyZoomedCardMinimizePresentation(
                    zoomedForeground,
                    frame: targetFrame
                )
            }
            context.underlayView.setOtherCardsRevealProgress(1)
        }
        animateTopEdgeTint(to: 1)
    }

    private func animateCardMinimizeTransition(
        context: CardMinimizeTransitionContext,
        options: UIView.AnimationOptions,
        animations: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: Self.cardMinimizeAnimationDuration,
            delay: 0,
            options: options,
            animations: animations,
            completion: { [weak self] _ in
                guard let self else { return }

                self.isCardMinimizeAnimationComplete = true
                self.finishCardMinimizeTransitionIfReady()
            }
        )

        guard let zoomedForeground = context.zoomedForeground,
              case .browserCell = context.commitDestination else {
            return
        }

        UIView.animate(
            withDuration: Self.cardMinimizeAnimationDuration * 0.4,
            delay: Self.cardMinimizeAnimationDuration * 0.55,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            context.foregroundView.alpha = 1
            zoomedForeground.view.alpha = 0
        }
    }

    private func finishCardMinimizeTransitionIfReady() {
        guard activeCardMinimizeContext != nil,
              isCardMinimizeAnimationComplete,
              isCardMinimizeLayoutApplied else {
            return
        }

        cleanupCardMinimizeTransition(revealPlayer: true)
    }

    private func completeCardExpandTransition() {
        guard let context = activeCardExpandContext else { return }
        let contextID = context.id
        var requestReturned = false
        var wasRejectedSynchronously = false

        modeController.switchToOnePerPage(
            targetPagePosition: context.targetPagePosition
        ) { [weak self] didApply in
            guard let self,
                  self.activeCardExpandContext?.id == contextID else {
                return
            }
            guard didApply else {
                if requestReturned {
                    self.resetCardExpandTransform()
                } else {
                    wasRejectedSynchronously = true
                }
                return
            }

            self.isCardExpandLayoutApplied = true
            self.finishCardExpandTransitionIfReady()
        }
        requestReturned = true
        if wasRejectedSynchronously {
            resetCardExpandTransform()
            return
        }

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.applyCardExpandPresentation(progress: 1)
        }, completion: { [weak self] _ in
            guard let self,
                  self.activeCardExpandContext?.id == contextID else {
                return
            }

            self.isCardExpandAnimationComplete = true
            self.finishCardExpandTransitionIfReady()
        })
        animateTopEdgeTint(to: 0, delay: 0.12)
    }

    private func finishCardExpandTransitionIfReady() {
        guard activeCardExpandContext != nil,
              isCardExpandAnimationComplete,
              isCardExpandLayoutApplied else {
            return
        }

        cleanupCardExpandTransition(revealPlayer: true)
    }

    private func applyCardExpandPresentation(progress: CGFloat) {
        guard let context = activeCardExpandContext else { return }

        let progress = min(max(progress, 0), 1)
        let easedProgress = easeOutQuadratic(progress)
        let foregroundFrame = interpolatedRect(
            from: context.sourceFrame,
            to: context.targetFrame,
            progress: easedProgress
        )

        context.foregroundView.transform = .identity
        context.foregroundView.bounds = CGRect(origin: .zero, size: foregroundFrame.size)
        context.foregroundView.center = CGPoint(x: foregroundFrame.midX, y: foregroundFrame.midY)
        context.underlayView.setOtherCardsRevealProgress(1 - easedProgress)
    }

    private func applyCardMinimizePresentation(translation: CGPoint) {
        let offsetY = max(0, translation.y)
        let progress = min(offsetY / MobilePlayerGestureTuning.cardMinimizeProgressDistance, 1)
        applyCardMinimizePresentation(
            progress: progress,
            translation: CGPoint(x: translation.x, y: offsetY)
        )
    }

    private func applyCardMinimizePinchPresentation(_ gesture: CardLayoutPinchGestureRecognizer) {
        let location = gesture.pinchLocation(in: view)
        let translation = CGPoint(
            x: location.x - cardMinimizePinchStartLocation.x,
            y: location.y - cardMinimizePinchStartLocation.y
        )
        applyCardMinimizePresentation(
            progress: cardMinimizePinchProgress(forScale: gesture.scale),
            translation: translation,
            rotation: cardMinimizePinchRotation,
            pinchScale: gesture.scale
        )
    }

    private func scheduleCardMinimizePinchPresentationUpdate() {
        cardMinimizePinchPresentationUpdate.schedule()
    }

    private func flushPendingCardMinimizePinchPresentationUpdate() {
        cardMinimizePinchPresentationUpdate.flush()
    }

    private func invalidatePendingCardMinimizePinchPresentationUpdate() {
        cardMinimizePinchPresentationUpdate.invalidate()
    }

    private func applyCardMinimizePresentation(
        progress: CGFloat,
        translation: CGPoint,
        rotation: CGFloat = 0,
        pinchScale: CGFloat? = nil
    ) {
        guard let context = activeCardMinimizeContext else { return }

        let progress = min(max(progress, 0), 1)
        let easedProgress = easeOutQuadratic(progress)
        let scale = cardMinimizeForegroundScale(
            targetScale: context.targetScale,
            easedProgress: easedProgress,
            pinchScale: pinchScale
        )
        let dragOffset = cardTransitionDragOffset(
            translation: translation,
            easedProgress: easedProgress
        )
        let underlayFadeProgress = min(
            progress / MobilePlayerGestureTuning.cardMinimizeInteractiveOtherCardsRevealCompletionProgress,
            1
        )

        context.foregroundView.center = CGPoint(
            x: context.sourceFrame.midX + dragOffset.x,
            y: context.sourceFrame.midY + dragOffset.y
        )
        context.foregroundView.transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
        let otherCardsRevealProgress = easeOutQuadratic(underlayFadeProgress)
            * MobilePlayerGestureTuning.cardMinimizeInteractiveOtherCardsMaximumRevealProgress
        context.underlayView.setOtherCardsRevealProgress(otherCardsRevealProgress)
        setTopEdgeTintAlphaDirectly(1)
    }

    private func cardMinimizeForegroundScale(
        targetScale: CGFloat,
        easedProgress: CGFloat,
        pinchScale: CGFloat?
    ) -> CGFloat {
        let normalScale = 1 - (1 - targetScale) * easedProgress
        guard let pinchScale,
              pinchScale < MobilePlayerGestureTuning.cardMinimizePinchFullProgressScale,
              MobilePlayerGestureTuning.cardMinimizePinchFullProgressScale > 0 else {
            return normalScale
        }

        let minimumScaleRatio = MobilePlayerGestureTuning.cardMinimizePinchMinimumPresentationScaleRatio
        let scaleRatio = max(pinchScale / MobilePlayerGestureTuning.cardMinimizePinchFullProgressScale, minimumScaleRatio)
        return targetScale * scaleRatio
    }

    private func finishCardMinimizePinchGesture(
        scale: CGFloat,
        velocity: CGFloat
    ) {
        guard activeCardMinimizeContext != nil else {
            resetCardMinimizeTransform()
            return
        }

        guard shouldCompleteCardMinimizePinch(scale: scale, velocity: velocity) else {
            resetCardMinimizeTransform()
            return
        }

        completeCardMinimizeTransition()
    }

    private func shouldCompleteCardMinimizePinch(
        scale: CGFloat,
        velocity: CGFloat
    ) -> Bool {
        PlayerCardMinimizePinchPolicy.shouldComplete(
            scale: scale,
            velocity: velocity
        )
    }

    private func cardMinimizePinchProgress(forScale scale: CGFloat) -> CGFloat {
        PlayerCardMinimizePinchPolicy.progress(forScale: scale)
    }

    private func resetCardMinimizePinchState() {
        isCardMinimizePinchDrivingCardMinimize = false
        cardMinimizePinchStartLocation = .zero
        cardMinimizePinchStartRotation = 0
        cardMinimizePinchRotation = 0
        invalidatePendingCardMinimizePinchPresentationUpdate()
    }

    private func resetCardMinimizeTransform() {
        guard let context = activeCardMinimizeContext else {
            revealPlayerAfterCardTransition()
            return
        }

        if context.zoomedForeground != nil,
           !chrome.isPlayerContentZoomed {
            crossfadeCardMinimizeTransitionToLivePager()
            return
        }

        let shouldRestoreZoomedForeground = context.zoomedForeground != nil
            && chrome.isPlayerContentZoomed

        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            context.foregroundView.transform = .identity
            context.foregroundView.bounds = CGRect(origin: .zero, size: context.sourceFrame.size)
            context.foregroundView.center = CGPoint(x: context.sourceFrame.midX, y: context.sourceFrame.midY)
            context.foregroundView.alpha = shouldRestoreZoomedForeground ? 0 : 1
            if let zoomedForeground = context.zoomedForeground {
                self.applyZoomedCardMinimizePresentation(
                    zoomedForeground,
                    frame: zoomedForeground.sourceFrame
                )
                zoomedForeground.view.alpha = shouldRestoreZoomedForeground ? 1 : 0
            }
            context.underlayView.setOtherCardsRevealProgress(0)
        }, completion: { [weak self] _ in
            self?.cleanupCardMinimizeTransition(
                revealPlayer: true,
                cancelPreparedBrowserSelection: true
            )
        })
        animateTopEdgeTint(to: 0, delay: Self.cardMinimizeAnimationDuration)
    }

    private func crossfadeCardMinimizeTransitionToLivePager() {
        if playerInteractionEnabledBeforeLivePagerFade == nil {
            playerInteractionEnabledBeforeLivePagerFade = view.isUserInteractionEnabled
        }
        view.isUserInteractionEnabled = false
        playerNavigationController
            .setCollectionBrowserTransitionStatusBarVisible(false)
        playerNavigationController.view.setNeedsLayout()
        playerNavigationController.view.layoutIfNeeded()
        revealPlayerAfterCardTransition()
        playerNavigationController.view.layoutIfNeeded()

        UIView.animate(
            withDuration: Self.cardMinimizeAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.cardTransitionCanvasView.alpha = 0
        } completion: { [weak self] _ in
            self?.cleanupCardMinimizeTransition(
                revealPlayer: false,
                cancelPreparedBrowserSelection: true
            )
        }
        animateTopEdgeTint(to: 0)
    }

    private func resetCardExpandTransform() {
        guard activeCardExpandContext != nil else {
            revealPlayerAfterCardTransition()
            return
        }

        UIView.animate(withDuration: 0.26, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            self.applyCardExpandPresentation(progress: 0)
        }, completion: { [weak self] _ in
            self?.cleanupCardExpandTransition(revealPlayer: true)
        })
        animateTopEdgeTint(to: 1)
    }

    private func makeCardMinimizeTransitionContext(
        state: MobilePlayerLayoutInteractionState
    ) -> CardMinimizeTransitionContext? {
        guard state.canMinimizeToCollectionBrowser,
              let pagePosition = state.pagePosition else {
            return nil
        }
        let currentDescriptor = state.currentDescriptor

        guard let selection = chrome.prepareCollectionBrowserSelection(for: pagePosition) else {
            return nil
        }
        var shouldCancelPreparedSelection = true
        defer {
            if shouldCancelPreparedSelection {
                chrome.cancelPreparedCollectionBrowserSelection()
            }
        }

        let selectedSnapshot = selection.selectedSnapshot
        guard let targetFrame = browserItemFrameInOverlay(selectedSnapshot) else {
            return nil
        }

        let fallbackImageSize = currentDescriptor.map {
            cardTransitionFallbackImageSize(selectedDescriptor: $0)
        } ?? selectedSnapshot.fallbackImageSize.validOrDefault
        let sourceFrame = onePerPageCardFrame(
            for: currentDescriptor,
            fallbackImageSize: fallbackImageSize
        )
        guard !sourceFrame.isEmpty else {
            return nil
        }
        let usesCellHero = selectedSnapshot.hasLoadedImage
        let zoomedForeground = makeZoomedCardMinimizeForeground()
        guard !chrome.isPlayerContentZoomed || zoomedForeground != nil else {
            return nil
        }
        let foregroundView: UIView
        if zoomedForeground != nil, usesCellHero {
            foregroundView = makeBrowserCardTransitionForegroundView(
                selectedSnapshot,
                sourceFrame: sourceFrame
            )
        } else {
            foregroundView = makeCardTransitionForegroundView(
                sourceFrame: sourceFrame,
                descriptor: currentDescriptor
            )
        }

        var underlayItemSnapshots = selection.visibleNeighborSnapshots
        if !usesCellHero {
            underlayItemSnapshots.removeAll { $0.tokenIndex == selectedSnapshot.tokenIndex }
            underlayItemSnapshots.insert(selectedSnapshot, at: 0)
        }
        let underlayView = makeCardTransitionUnderlayView(
            itemSnapshots: underlayItemSnapshots,
            otherCardsRevealProgress: 0
        )
        installCardMinimizeForeground(
            foregroundView,
            zoomedForeground: zoomedForeground,
            above: underlayView
        )
        let targetScale = cardMinimizeTargetScale(
            sourceFrame: sourceFrame,
            targetFrame: usesCellHero ? targetFrame : nil
        )
        shouldCancelPreparedSelection = false

        return CardMinimizeTransitionContext(
            id: UUID(),
            sourcePagePosition: pagePosition,
            sourceFrame: sourceFrame,
            targetScale: targetScale,
            commitDestination: usesCellHero ? .browserCell(targetFrame) : .offscreen,
            foregroundView: foregroundView,
            zoomedForeground: zoomedForeground,
            underlayView: underlayView,
            hasPreparedBrowserSelection: true
        )
    }

    private func makeDirectCardMinimizeTransitionContext(
        state: MobilePlayerLayoutInteractionState
    ) -> CardMinimizeTransitionContext? {
        guard state.canSwitchDirectlyToCollectionBrowser,
              let pagePosition = state.pagePosition else {
            return nil
        }
        let currentDescriptor = state.currentDescriptor

        let preparedSelection = chrome.prepareCollectionBrowserSelection(for: pagePosition)
        var shouldCancelPreparedSelection = preparedSelection != nil
        defer {
            if shouldCancelPreparedSelection {
                chrome.cancelPreparedCollectionBrowserSelection()
            }
        }

        let fallbackImageSize = currentDescriptor.map {
            cardTransitionFallbackImageSize(selectedDescriptor: $0)
        } ?? preparedSelection?.selectedSnapshot.fallbackImageSize.validOrDefault
            ?? CGSize(width: 1, height: 1)
        let sourceFrame = onePerPageCardFrame(
            for: currentDescriptor,
            fallbackImageSize: fallbackImageSize
        )
        guard !sourceFrame.isEmpty else {
            return nil
        }

        let foregroundView = makeCardTransitionForegroundView(
            sourceFrame: sourceFrame,
            descriptor: currentDescriptor
        )
        let zoomedForeground = makeZoomedCardMinimizeForeground()
        guard !chrome.isPlayerContentZoomed || zoomedForeground != nil else {
            return nil
        }
        var underlayItemSnapshots = preparedSelection?.visibleNeighborSnapshots ?? []
        if let selectedSnapshot = preparedSelection?.selectedSnapshot {
            underlayItemSnapshots.removeAll { $0.tokenIndex == selectedSnapshot.tokenIndex }
            underlayItemSnapshots.insert(selectedSnapshot, at: 0)
        }
        let underlayView = makeCardTransitionUnderlayView(
            itemSnapshots: underlayItemSnapshots,
            otherCardsRevealProgress: 0
        )
        installCardMinimizeForeground(
            foregroundView,
            zoomedForeground: zoomedForeground,
            above: underlayView
        )
        shouldCancelPreparedSelection = false

        return CardMinimizeTransitionContext(
            id: UUID(),
            sourcePagePosition: pagePosition,
            sourceFrame: sourceFrame,
            targetScale: cardMinimizeTargetScale(sourceFrame: sourceFrame, targetFrame: nil),
            commitDestination: .offscreen,
            foregroundView: foregroundView,
            zoomedForeground: zoomedForeground,
            underlayView: underlayView,
            hasPreparedBrowserSelection: preparedSelection != nil
        )
    }

    private func installCardMinimizeForeground(
        _ foregroundView: UIView,
        zoomedForeground: ZoomedCardMinimizeForeground?,
        above underlayView: CardTransitionUnderlayView
    ) {
        cardTransitionCanvasView.insertSubview(foregroundView, aboveSubview: underlayView)
        guard let zoomedForeground else { return }

        foregroundView.alpha = 0
        cardTransitionCanvasView.insertSubview(
            zoomedForeground.view,
            aboveSubview: foregroundView
        )
    }

    private func makeCardExpandTransitionContext(
        selection: MobilePlayerBrowserTransitionSelection
    ) -> CardExpandTransitionContext? {
        let selectedSnapshot = selection.selectedSnapshot
        guard selectedSnapshot.hasLoadedImage else {
            return nil
        }
        guard let sourceFrame = browserItemFrameInOverlay(selectedSnapshot) else {
            return nil
        }

        let underlayView = makeCardTransitionUnderlayView(
            itemSnapshots: selection.visibleNeighborSnapshots,
            otherCardsRevealProgress: 1
        )

        let targetFrame = onePerPageCardFrame(
            for: selectedSnapshot.descriptor,
            fallbackImageSize: selectedSnapshot.fallbackImageSize.validOrDefault
        )
        guard !targetFrame.isEmpty else {
            underlayView.removeFromSuperview()
            updateCardTransitionCanvasVisibility()
            return nil
        }

        let foregroundView = makeBrowserCardTransitionForegroundView(
            selectedSnapshot,
            sourceFrame: sourceFrame
        )
        cardTransitionCanvasView.insertSubview(foregroundView, aboveSubview: underlayView)

        return CardExpandTransitionContext(
            id: UUID(),
            targetPagePosition: selectedSnapshot.pagePosition,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            foregroundView: foregroundView,
            underlayView: underlayView
        )
    }

    private func makeCardTransitionUnderlayView(
        itemSnapshots: [MobilePlayerBrowserItemSnapshot],
        otherCardsRevealProgress: CGFloat
    ) -> CardTransitionUnderlayView {
        setCardTransitionCanvasActive(true)
        playerNavigationController.view.layoutIfNeeded()
        playerNavigationController.assertTopEdgeTintPlacement()
        let underlayView = CardTransitionUnderlayView(itemSnapshots: itemSnapshots)
        underlayView.frame = cardTransitionCanvasView.bounds
        underlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cardTransitionCanvasView.addSubview(underlayView)
        underlayView.setOtherCardsRevealProgress(otherCardsRevealProgress)
        underlayView.setNeedsLayout()
        underlayView.layoutIfNeeded()
        return underlayView
    }

    private func makeCardTransitionForegroundView(
        sourceFrame: CGRect,
        descriptor: DownloadableMediaDescriptor?
    ) -> UIView {
        if let descriptor,
           (descriptor.usesNativeMetalCardPresentation || descriptor.isCollectionBrowserImage),
           let snapshot = makeCardTransitionSnapshotView(sourceFrame: sourceFrame) {
            return snapshot
        }

        if let descriptor,
           let image = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            let imageView = NativeMetalCardCornerMaskedImageView(frame: sourceFrame)
            imageView.makeBackgroundTransparent()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.image = image
            imageView.usesNativeMetalCardCornerMask = descriptor.usesNativeMetalCardPresentation
            return imageView
        }

        if let snapshot = makeCardTransitionSnapshotView(sourceFrame: sourceFrame) {
            return snapshot
        }

        let placeholderView = UIView(frame: sourceFrame)
        placeholderView.backgroundColor = MobilePlayerBackgroundColor.defaultColor
        placeholderView.clipsToBounds = true
        return placeholderView
    }

    private func makeBrowserCardTransitionForegroundView(
        _ itemSnapshot: MobilePlayerBrowserItemSnapshot,
        sourceFrame: CGRect
    ) -> UIView {
        let foregroundView = itemSnapshot.snapshotView
        foregroundView.removeFromSuperview()
        foregroundView.layer.removeAllAnimations()
        foregroundView.transform = .identity
        foregroundView.frame = sourceFrame
        foregroundView.alpha = 1
        foregroundView.isHidden = false
        foregroundView.isUserInteractionEnabled = false
        return foregroundView
    }

    private func makeZoomedCardMinimizeForeground() -> ZoomedCardMinimizeForeground? {
        guard chrome.isPlayerContentZoomed else { return nil }

        let sourceFrame = view.convert(view.bounds, to: cardTransitionCanvasView)
        guard !sourceFrame.isEmpty,
              let snapshot = chrome.makeOnePerPageTransitionSnapshot(
                from: view.bounds,
                in: view
              ) else {
            return nil
        }

        let containerView = UIView(frame: sourceFrame)
        containerView.backgroundColor = chrome.playerBackgroundColor
        containerView.isOpaque = true
        containerView.clipsToBounds = true
        containerView.isUserInteractionEnabled = false

        snapshot.frame = containerView.bounds
        snapshot.isUserInteractionEnabled = false
        containerView.addSubview(snapshot)
        return ZoomedCardMinimizeForeground(
            view: containerView,
            sourceFrame: sourceFrame
        )
    }

    private func applyZoomedCardMinimizePresentation(
        _ foreground: ZoomedCardMinimizeForeground,
        frame: CGRect
    ) {
        let sourceSize = foreground.sourceFrame.size
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0,
              frame.width > 0,
              frame.height > 0 else {
            return
        }

        foreground.view.bounds = CGRect(origin: .zero, size: sourceSize)
        foreground.view.center = CGPoint(x: frame.midX, y: frame.midY)

        let scale = min(
            frame.width / sourceSize.width,
            frame.height / sourceSize.height
        )
        foreground.view.transform = CGAffineTransform(
            scaleX: scale,
            y: scale
        )
    }

    private func makeCardTransitionSnapshotView(sourceFrame: CGRect) -> UIView? {
        let sourceFrameInPlayer = cardTransitionCanvasView.convert(sourceFrame, to: view)
        let snapshot = chrome.makeOnePerPageTransitionSnapshot(
            from: sourceFrameInPlayer,
            in: view
        ) ?? view.resizableSnapshotView(
            from: sourceFrameInPlayer,
            afterScreenUpdates: false,
            withCapInsets: .zero
        )
        guard let snapshot else {
            return nil
        }
        snapshot.frame = sourceFrame
        snapshot.clipsToBounds = true
        return snapshot
    }

    private func cardTransitionFallbackImageSize(
        selectedDescriptor: DownloadableMediaDescriptor
    ) -> CGSize {
        if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: selectedDescriptor) {
            return image.size.validOrDefault
        }

        return PlayerCollectionBrowserSupport.fallbackImageSize(for: selectedDescriptor)
    }

    private func onePerPageCardFrame(
        for descriptor: DownloadableMediaDescriptor?,
        fallbackImageSize: CGSize
    ) -> CGRect {
        let playerBounds = view.bounds
        if descriptor?.usesNativeMetalCardPresentation == true {
            let nativeCardFrame = NativeMetalCardLayout.cardContentRect(in: playerBounds.size)
            let clippedNativeCardFrame = nativeCardFrame.intersection(playerBounds)
            guard !clippedNativeCardFrame.isNull, !clippedNativeCardFrame.isEmpty else {
                return view.convert(playerBounds, to: cardTransitionCanvasView)
            }
            return view.convert(clippedNativeCardFrame, to: cardTransitionCanvasView)
        }

        let frameInPlayer = PlayerAspectFitLayout.centeredRect(
            for: fallbackImageSize.validOrDefault,
            in: playerBounds
        )
        let clippedFrame = frameInPlayer.intersection(playerBounds)
        guard !clippedFrame.isNull, !clippedFrame.isEmpty else {
            return view.convert(playerBounds, to: cardTransitionCanvasView)
        }
        return view.convert(clippedFrame, to: cardTransitionCanvasView)
    }

    private func browserItemFrameInOverlay(_ snapshot: MobilePlayerBrowserItemSnapshot) -> CGRect? {
        let frame = cardTransitionCanvasView.convert(snapshot.frameInWindow, from: nil)
        guard !frame.isNull,
              !frame.isInfinite,
              !frame.isEmpty,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            return nil
        }

        return frame
    }

    private func cardMinimizeTargetScale(sourceFrame: CGRect, targetFrame: CGRect?) -> CGFloat {
        cardTransitionTargetScale(sourceFrame: sourceFrame, targetFrame: targetFrame, fallback: 0.5)
    }

    private func cardTransitionTargetScale(
        sourceFrame: CGRect,
        targetFrame: CGRect?,
        fallback: CGFloat
    ) -> CGFloat {
        guard let targetFrame,
              sourceFrame.width > 0,
              sourceFrame.height > 0 else {
            return fallback
        }

        return min(targetFrame.width / sourceFrame.width, targetFrame.height / sourceFrame.height)
    }

    private func cardTransitionDragOffset(
        translation: CGPoint,
        easedProgress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: translation.x * (1 - Self.cardTransitionHorizontalDragDamping * easedProgress),
            y: translation.y * (1 - Self.cardTransitionVerticalDragDamping * easedProgress)
        )
    }

    private func interpolatedRect(from sourceFrame: CGRect, to targetFrame: CGRect, progress: CGFloat) -> CGRect {
        let progress = min(max(progress, 0), 1)
        return CGRect(
            x: sourceFrame.minX + (targetFrame.minX - sourceFrame.minX) * progress,
            y: sourceFrame.minY + (targetFrame.minY - sourceFrame.minY) * progress,
            width: sourceFrame.width + (targetFrame.width - sourceFrame.width) * progress,
            height: sourceFrame.height + (targetFrame.height - sourceFrame.height) * progress
        )
    }

    private func cleanupCardMinimizeTransition(
        revealPlayer: Bool,
        cancelPreparedBrowserSelection: Bool = false
    ) {
        cardTransitionCanvasView.layer.removeAllAnimations()
        cardTransitionCanvasView.alpha = 1

        let context = activeCardMinimizeContext
        activeCardMinimizeContext = nil
        isDismissPanDrivingCardMinimize = false
        isCardMinimizeAnimationComplete = false
        isCardMinimizeLayoutApplied = false
        resetCardMinimizePinchState()
        playerNavigationController
            .setCollectionBrowserTransitionStatusBarVisible(false)

        if cancelPreparedBrowserSelection,
           context?.hasPreparedBrowserSelection == true {
            chrome.cancelPreparedCollectionBrowserSelection()
        }

        if revealPlayer {
            revealPlayerAfterCardTransition()
        }

        context?.foregroundView.removeFromSuperview()
        context?.zoomedForeground?.view.removeFromSuperview()
        context?.underlayView.removeFromSuperview()
        updateCardTransitionCanvasVisibility()

        if let wasInteractionEnabled = playerInteractionEnabledBeforeLivePagerFade {
            playerInteractionEnabledBeforeLivePagerFade = nil
            view.isUserInteractionEnabled = wasInteractionEnabled
        }
    }

    private func cleanupCardExpandTransition(revealPlayer: Bool) {
        let context = activeCardExpandContext
        activeCardExpandContext = nil
        isCardExpandAnimationComplete = false
        isCardExpandLayoutApplied = false
        modeController.unstagePagerViewIfNeeded()

        if revealPlayer {
            revealPlayerAfterCardTransition()
        }

        context?.foregroundView.removeFromSuperview()
        context?.underlayView.removeFromSuperview()
        updateCardTransitionCanvasVisibility()
    }

    private func revealPlayerAfterCardTransition() {
        chrome.setPlayerContentHiddenForCardTransition(false)
        view.alpha = 1
        view.transform = .identity
    }

    private func updateCardTransitionCanvasVisibility() {
        setCardTransitionCanvasActive(
            activeCardMinimizeContext != nil || activeCardExpandContext != nil
        )
    }

    private func setCardTransitionCanvasActive(_ isActive: Bool) {
        cardTransitionCanvasView.isHidden = !isActive
    }

    private func easeOutQuadratic(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return 1 - pow(1 - clampedProgress, 2)
    }

    func canBeginCardMinimizePinch() -> Bool {
        canBeginCardMinimizeInteraction(location: cardMinimizePinch.pinchLocation(in: view))
    }

    func canBeginPinchRotation() -> Bool {
        if isCardMinimizePinchDrivingCardMinimize {
            return true
        }

        let location = pinchRotation.location(in: view)
        guard cardMinimizePinch.isTrackingPinch else {
            return false
        }

        return canBeginCardMinimizeInteraction(location: location)
    }

    private func canBeginCardMinimizeInteraction(location: CGPoint) -> Bool {
        guard !isCardTransitionActive else {
            return false
        }

        return cardMinimizeAvailability(at: location).canMinimize
    }

    private func hasZoomedPlayerContent(at location: CGPoint) -> Bool {
        chrome.isPlayerContentZoomed && view.bounds.contains(location)
    }

    private func hasPlayerDismissIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        let bounds = view.bounds

        return bounds.contains(location)
            && velocity.y > MobilePlayerGestureTuning.dismissInitialVelocity
            && velocity.y > abs(velocity.x) * MobilePlayerGestureTuning.dismissVerticalIntentRatio
    }

    private struct CardMinimizeAvailability {
        let animated: MobilePlayerLayoutInteractionState?
        let direct: MobilePlayerLayoutInteractionState?

        static let empty = CardMinimizeAvailability(animated: nil, direct: nil)

        var canMinimize: Bool {
            animated != nil || direct != nil
        }
    }

    private func cardMinimizeAvailability(at location: CGPoint) -> CardMinimizeAvailability {
        guard view.bounds.contains(location),
              !isCardTransitionActive,
              !chrome.isPlayerContentZoomed else {
            return .empty
        }

        let state = chrome.currentLayoutInteractionState()
        return CardMinimizeAvailability(
            animated: state.canMinimizeToCollectionBrowser ? state : nil,
            direct: state.canSwitchDirectlyToCollectionBrowser ? state : nil
        )
    }

    private func hasControlsHideIntent(location: CGPoint, velocity: CGPoint) -> Bool {
        view.bounds.contains(location)
            && velocity.y > 0
            && velocity.y > abs(velocity.x)
    }

    private func currentPinchRotationGestureValue() -> CGFloat {
        switch pinchRotation.state {
        case .began, .changed:
            return pinchRotation.rotation
        default:
            return 0
        }
    }


    func shouldBeginDismissPan() -> Bool {
        guard playerNavigationController.topViewController === playerViewController,
              playerNavigationController.transitionCoordinator == nil,
              !isCardTransitionActive,
              !chrome.isCollectionBrowserActive else {
            return false
        }

        let location = dismissPan.location(in: view)
        let velocity = dismissPan.velocity(in: view)

        guard !hasZoomedPlayerContent(at: location) else {
            return false
        }

        let canMinimizeToCollectionBrowser = hasPlayerDismissIntent(
            location: location,
            velocity: velocity
        ) && cardMinimizeAvailability(at: location).canMinimize

        return canMinimizeToCollectionBrowser
            || (chrome.showControls && hasControlsHideIntent(location: location, velocity: velocity))
    }

    func invalidatePendingCardMinimizePinchUpdate() {
        cardMinimizePinchPresentationUpdate.invalidate()
    }

    func cleanupTransitionsAndCanvas() {
        cleanupCardMinimizeTransition(
            revealPlayer: false,
            cancelPreparedBrowserSelection: true
        )
        cleanupCardExpandTransition(revealPlayer: false)
        cardTransitionCanvasView.subviews.forEach { $0.removeFromSuperview() }
        setCardTransitionCanvasActive(false)
        cardTransitionCanvasView.removeFromSuperview()
        if playerNavigationController.cardTransitionOverlayView === cardTransitionCanvasView {
            playerNavigationController.cardTransitionOverlayView = nil
        }
    }

    func finishInvalidation() {
        chrome.onCollectionBrowserExpandRequest = nil
        chrome.setPlayerContentHiddenForCardTransition(false)

        view.layer.removeAllAnimations()
        view.alpha = 1
        view.transform = .identity
    }

    private func configurePagerScrollViews() {
        delegate?.configurePagerScrollViews()
    }

    private func setTopEdgeTintAlphaDirectly(_ alpha: CGFloat) {
        delegate?.setTopEdgeTintAlphaDirectly(alpha)
    }

    private func animateTopEdgeTint(to alpha: CGFloat, delay: TimeInterval = 0) {
        delegate?.animateTopEdgeTint(to: alpha, delay: delay)
    }

}
