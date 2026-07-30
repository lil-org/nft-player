// ∅ 2026 lil org

import Cocoa
import Combine
import SwiftUI

/// The one-per-page screen. Wraps the `NSPageController` based pager and owns the
/// keyboard navigation, cursor hiding and completion controls that used to live on
/// the standalone player window.
final class MacPlayerPagerViewController: NSViewController, MacNavigationScreen {

    private enum MinimizeGestureTuning {
        /// Fraction of the view height a two-finger drag covers to fully minimize.
        static let scrollRangeHeightFraction: CGFloat = 0.45
        static let scrollCommitProgress: CGFloat = 0.32
        static let scrollStartThreshold: CGFloat = 6
        static let scrollDominanceRatio: CGFloat = 1.5
    }

    private enum MinimizeGesture {
        case magnification(sample: PlayerCardMagnificationSample)
        case scroll(translation: CGFloat)
    }

    let session: MacPlayerSession
    weak var minimizeHandler: MacPlayerMinimizeHandling?

    private let model: MacNavigationModel
    private let mediaActions: MacPlayerMediaActions
    private let pageController: MacPlayerPageController
    private static let completionControlsFadeDuration: TimeInterval = 0.16

    private var completionControlsView: NSHostingView<MacPlayerCompletionControls>?
    private var completionControlsFadeGeneration = 0
    private var currentTokenObserver: AnyCancellable?
    private var completionObserver: AnyCancellable?
    private var navigationKeysEventMonitor: Any?
    private var mouseMoveEventMonitor: Any?
    private var cursorHideTimer: Timer?
    private var fullScreenObserver: NSObjectProtocol?
    private var magnifyEventMonitor: Any?
    private var scrollEventMonitor: Any?
    private var swipeEventMonitor: Any?
    private var activeMinimizeGesture: MinimizeGesture?
    private var isActive = false
    private var isAccessibilityHiddenForModeTransition = false

    var playerModel: PlayerModel { session.playerModel }

    private var ownsActiveSession: Bool {
        model.session?.id == session.id
    }

    init(
        session: MacPlayerSession,
        model: MacNavigationModel,
        mediaActions: MacPlayerMediaActions
    ) {
        self.session = session
        self.model = model
        self.mediaActions = mediaActions
        self.pageController = MacPlayerPageController(
            playerModel: session.playerModel,
            playerMenuDelegate: nil
        )
        super.init(nibName: nil, bundle: nil)
        pageController.isPagingInteractionAllowed = { [weak self] in
            self?.allowsPagingInteraction == true
        }
        pageController.onNavigationStateChange = { [weak self] in
            guard let self, self.ownsActiveSession else { return }
            self.model.refreshCommandState()
        }
        pageController.update(playerMenuDelegate: self)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        removeEventMonitors()
        if let fullScreenObserver {
            NotificationCenter.default.removeObserver(fullScreenObserver)
        }
        cursorHideTimer?.invalidate()
        pageController.cleanup()
    }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = MacPlayerBackgroundColor
            .color(forCollectionId: session.collectionId).cgColor
        view.setAccessibilityHidden(true)
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(pageController)
        let pagerView = pageController.view
        pagerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pagerView)
        NSLayoutConstraint.activate([
            pagerView.topAnchor.constraint(equalTo: view.topAnchor),
            pagerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        currentTokenObserver = playerModel.$currentToken
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                guard let self else { return }
                // Catches any token change the pager did not originate; a no-op when
                // the page controller is already on `token`.
                self.pageController.syncSelection()
                self.playerModel.markTokenViewed(token)
                self.updateCompletionControls()
            }
        completionObserver = playerModel.$isCurrentTokenInsertedWidgetToken
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateCompletionControls()
            }
        fullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  self.isActive,
                  let window = notification.object as? NSWindow,
                  window === self.view.window else {
                return
            }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        mediaActions.updatePresentingWindow(view.window)
        hideCursorIfFullScreen()
    }

    // MARK: - MacNavigationScreen

    func navigationScreenDidBecomeActive() {
        guard ownsActiveSession else { return }
        isActive = true
        updateAccessibilityVisibility()
        pageController.activateContent()
        mediaActions.updatePresentingWindow(view.window)
        installEventMonitors()
        updateCompletionControls()
        hideCursorIfFullScreen()
    }

    func navigationScreenDidResignActive() {
        guard isActive else { return }
        isActive = false
        updateAccessibilityVisibility()
        removeEventMonitors()
        cursorHideTimer?.invalidate()
        cursorHideTimer = nil
    }

    func navigationScreenDidMoveOffstage() {
        isActive = false
        updateAccessibilityVisibility()
        pageController.deactivateContent()
    }

    func setModeTransitionAccessibilityHidden(_ isHidden: Bool) {
        isAccessibilityHiddenForModeTransition = isHidden
        updateAccessibilityVisibility()
    }

    // MARK: - Paging

    /// Puts the given token index under the pager without any page animation, so a
    /// mode switch lands on the item the browser was showing.
    @discardableResult
    func anchor(toTokenIndex tokenIndex: Int) -> Bool {
        guard !pageController.isTransitionInFlight,
              !session.collectionId.isEmpty,
              let token = CollectionCatalog.generateToken(
                specificCollectionId: session.collectionId,
                tokenIndex: tokenIndex
              ) else {
            return false
        }
        playerModel.showPagedToken(token)
        pageController.activateContent()
        return true
    }

    func commitCollectionBrowserHandoff(toTokenIndex tokenIndex: Int) {
        guard playerModel.exitWidgetTokenInsertion(selectingTokenAt: tokenIndex) else { return }
        pageController.rebuildCollectionAfterWidgetInsertionExit()
    }

    var currentTokenIndex: Int? {
        CollectionCatalog.tokenContext(for: playerModel.currentToken)?.tokenIndex
    }

    var isPageTransitionInFlight: Bool {
        pageController.isTransitionInFlight
    }

    var isCurrentPageZoomed: Bool {
        pageController.isCurrentPageZoomed
    }

    func resetZoom(completion: @escaping () -> Void) {
        pageController.resetCurrentPageZoom(completion: completion)
    }

    func resetMinimizeGestureState() {
        activeMinimizeGesture = nil
        isMinimizeInProgress = false
    }

    func goBack() {
        guard allowsPagingInteraction else { return }
        pageController.navigateBackFromChrome(animation: .immediate)
    }

    func goForward() {
        guard allowsPagingInteraction else { return }
        pageController.navigateForwardFromChrome(animation: .immediate)
    }

    var canGoBack: Bool {
        allowsPagingInteraction && pageController.canNavigateBackFromChrome
    }

    var canGoForward: Bool {
        allowsPagingInteraction && pageController.canNavigateForwardFromChrome
    }

    /// A still of what is on screen right now, used as the hero card when minimizing.
    func snapshotOfCurrentMedia() -> NSImage? {
        guard let contentRect = currentMediaFrameInWindow(),
              contentRect.width > 1,
              contentRect.height > 1 else {
            return nil
        }
        let rectInView = view.convert(contentRect, from: nil)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rectInView) else { return nil }
        view.cacheDisplay(in: rectInView, to: rep)
        let image = NSImage(size: rectInView.size)
        image.addRepresentation(rep)
        return image
    }

    /// The on-screen rect of the media itself (aspect fit inside the pager), in window coordinates.
    func currentMediaFrameInWindow() -> CGRect? {
        pageController.currentMediaFrameInWindow()
    }

    // MARK: - Completion controls

    private func updateCompletionControls() {
        let isComplete = playerModel.currentProgress?.isComplete == true
            && !playerModel.isCurrentTokenInsertedWidgetToken
        guard isComplete else {
            guard let completionControlsView else { return }
            completionControlsFadeGeneration += 1
            let generation = completionControlsFadeGeneration
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.completionControlsFadeDuration
                completionControlsView.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                // A fade back in bumps the generation, so a superseded fade-out can
                // never tear the controls down underneath it.
                guard let self,
                      self.completionControlsFadeGeneration == generation,
                      let view = self.completionControlsView else {
                    return
                }
                view.removeFromSuperview()
                self.completionControlsView = nil
            }
            return
        }

        if let completionControlsView {
            completionControlsFadeGeneration += 1
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.completionControlsFadeDuration
                completionControlsView.animator().alphaValue = 1
            }
            return
        }

        let controls = MacPlayerCompletionControls(
            onViewAgain: { [weak self] in self?.viewAgain() },
            onFinish: { [weak self] in self?.finish() }
        )
        let hostingView = NSHostingView(rootView: controls)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.alphaValue = 0
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        completionControlsView = hostingView
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.completionControlsFadeDuration
            hostingView.animator().alphaValue = 1
        }
    }

    private func viewAgain() {
        guard allowsPagingInteraction, !isPageTransitionInFlight else { return }
        playerModel.restartCollection()
        // restartCollection rewrites the model's history; the page controller has to
        // be told, or the pager stays parked on the last token.
        pageController.syncSelection()
    }

    /// "Finish" leaves the player entirely, the way closing the old player window did.
    private func finish() {
        guard allowsPagingInteraction, !isPageTransitionInFlight else { return }
        model.showCollections()
    }

    // MARK: - Cursor

    private func hideCursorIfFullScreen() {
        guard let window = view.window, window.styleMask.contains(.fullScreen) else { return }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private var isFullScreenOnActiveSpace: Bool {
        guard let window = view.window else { return false }
        return window.styleMask.contains(.fullScreen) && window.isOnActiveSpace
    }

    private func resetCursorHideTimer() {
        cursorHideTimer?.invalidate()
        guard isFullScreenOnActiveSpace else { return }
        cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 2.3, repeats: false) { [weak self] _ in
            if self?.isFullScreenOnActiveSpace == true {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    // MARK: - Keyboard

    private func installEventMonitors() {
        removeEventMonitors()

        navigationKeysEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.shouldHandleNavigationKeyEvent(event) else { return event }
            guard let navigationAction = Self.navigationAction(for: event) else { return event }
            switch navigationAction {
            case let .back(animation):
                guard self.allowsPagingInteraction else { return nil }
                self.pageController.navigateBackFromChrome(animation: animation)
            case let .forward(animation):
                guard self.allowsPagingInteraction else { return nil }
                self.pageController.navigateForwardFromChrome(animation: animation)
            case .exit:
                self.model.goBack()
            }
            return nil
        }

        magnifyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, self.shouldHandleGestureEvent(event) else { return event }
            if self.shouldConsumeMagnifyDuringModeTransition {
                return nil
            }
            return self.handleMagnify(event) ? nil : event
        }

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.shouldHandleGestureEvent(event) else { return event }
            if self.shouldConsumeScrollDuringModeTransition {
                return nil
            }
            return self.handleScroll(event) ? nil : event
        }

        swipeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            guard let self, self.shouldHandleGestureEvent(event) else { return event }
            return self.minimizeHandler?.isTransitionInFlight == true ? nil : event
        }

        if NSScreen.screens.count <= 1 {
            mouseMoveEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseUp, .rightMouseUp, .mouseEntered]
            ) { [weak self] event in
                self?.resetCursorHideTimer()
                return event
            }
        }
    }

    private func removeEventMonitors() {
        for monitor in [
            navigationKeysEventMonitor,
            mouseMoveEventMonitor,
            magnifyEventMonitor,
            scrollEventMonitor,
            swipeEventMonitor
        ] {
            guard let monitor else { continue }
            NSEvent.removeMonitor(monitor)
        }
        navigationKeysEventMonitor = nil
        mouseMoveEventMonitor = nil
        magnifyEventMonitor = nil
        scrollEventMonitor = nil
        swipeEventMonitor = nil
        cancelActiveMinimizeGesture()
    }

    // MARK: - Minimize gestures

    private func shouldHandleGestureEvent(_ event: NSEvent) -> Bool {
        guard isActive, let window = view.window else { return false }
        return event.window === window
    }

    private var allowsPagingInteraction: Bool {
        ownsActiveSession
            && isActive
            && minimizeHandler?.isTransitionInFlight != true
    }

    private func updateAccessibilityVisibility() {
        guard isViewLoaded else { return }
        view.setAccessibilityHidden(
            !isActive
                || !ownsActiveSession
                || isAccessibilityHiddenForModeTransition
        )
    }

    private var shouldConsumeMagnifyDuringModeTransition: Bool {
        guard minimizeHandler?.isTransitionInFlight == true else { return false }
        guard case .magnification = activeMinimizeGesture else { return true }
        return false
    }

    private var shouldConsumeScrollDuringModeTransition: Bool {
        guard minimizeHandler?.isTransitionInFlight == true else { return false }
        guard case .scroll = activeMinimizeGesture else { return true }
        return false
    }

    /// Pinch in shrinks the card back into its browser cell; pinch out is left to
    /// the media view's own zoom.
    private func handleMagnify(_ event: NSEvent) -> Bool {
        if event.phase.contains(.cancelled) {
            guard case .magnification = activeMinimizeGesture else { return false }
            return finishMinimizeGesture(commit: false)
        }

        if event.phase.contains(.stationary) {
            guard case var .magnification(sample) = activeMinimizeGesture,
                  isMinimizeInProgress else {
                return false
            }
            sample.add(
                magnificationDelta: 0,
                timestamp: event.timestamp
            )
            activeMinimizeGesture = .magnification(sample: sample)
            return true
        }

        switch event.phase {
        case .began:
            guard activeMinimizeGesture == nil, minimizeHandler?.canMinimize == true else { return false }
            activeMinimizeGesture = .magnification(sample: PlayerCardMagnificationSample(
                magnificationDelta: event.magnification,
                timestamp: event.timestamp
            ))
            return false
        case .changed:
            guard case var .magnification(sample) = activeMinimizeGesture else { return false }
            sample.add(
                magnificationDelta: event.magnification,
                timestamp: event.timestamp
            )
            activeMinimizeGesture = .magnification(sample: sample)

            if !isMinimizeInProgress {
                // Opening the pinch past the slack fails the gesture for good, so the
                // rest of it reaches the zoom scroll view — iOS's `.failed` semantics.
                if sample.scale > PlayerCardMinimizePinchPolicy.zoomInFailureScale {
                    activeMinimizeGesture = nil
                    return false
                }
                // Deadband: a twitch inward must not tear down the live page.
                guard sample.scale <= PlayerCardMinimizePinchPolicy.activationScale else {
                    return false
                }
                guard startMinimizeIfNeeded() else { return false }
            }
            minimizeHandler?.updateMinimize(
                progress: PlayerCardMinimizePinchPolicy.progress(forScale: sample.scale)
            )
            return true
        case .ended:
            guard case var .magnification(sample) = activeMinimizeGesture else { return false }
            sample.add(
                magnificationDelta: event.magnification,
                timestamp: event.timestamp
            )
            activeMinimizeGesture = .magnification(sample: sample)
            if isMinimizeInProgress {
                minimizeHandler?.updateMinimize(
                    progress: PlayerCardMinimizePinchPolicy.progress(forScale: sample.scale)
                )
            }
            return finishMinimizeGesture(
                commit: PlayerCardMinimizePinchPolicy.shouldComplete(
                    scale: sample.scale,
                    velocity: sample.velocity
                )
            )
        default:
            return false
        }
    }

    /// A precise two-finger drag downwards dismisses to the browser.
    private func handleScroll(_ event: NSEvent) -> Bool {
        if event.phase.contains(.cancelled) {
            guard case .scroll = activeMinimizeGesture else { return false }
            return finishMinimizeGesture(commit: false)
        }

        guard event.hasPreciseScrollingDeltas else { return false }

        switch event.phase {
        case .began:
            guard activeMinimizeGesture == nil, minimizeHandler?.canMinimize == true else { return false }
            activeMinimizeGesture = .scroll(translation: 0)
            return false
        case .changed:
            guard case let .scroll(translation) = activeMinimizeGesture else { return false }
            let downwardDelta = physicalDownwardScrollDelta(for: event)
            guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) * MinimizeGestureTuning.scrollDominanceRatio
                    || isMinimizeInProgress else {
                activeMinimizeGesture = nil
                return false
            }
            let updated = translation + downwardDelta
            activeMinimizeGesture = .scroll(translation: updated)
            guard updated > MinimizeGestureTuning.scrollStartThreshold else {
                if isMinimizeInProgress {
                    minimizeHandler?.updateMinimize(progress: 0)
                    return true
                }
                return false
            }
            guard startMinimizeIfNeeded() else { return false }
            minimizeHandler?.updateMinimize(progress: scrollProgress(for: updated))
            return true
        case .ended:
            guard case let .scroll(translation) = activeMinimizeGesture else { return false }
            return finishMinimizeGesture(
                commit: scrollProgress(for: translation) >= MinimizeGestureTuning.scrollCommitProgress
            )
        default:
            return false
        }
    }

    private func physicalDownwardScrollDelta(for event: NSEvent) -> CGFloat {
        event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? 1 : -1)
    }

    private func scrollProgress(for translation: CGFloat) -> CGFloat {
        let range = max(view.bounds.height * MinimizeGestureTuning.scrollRangeHeightFraction, 1)
        return min(max(translation, 0) / range, 1)
    }

    private var isMinimizeInProgress = false

    private func startMinimizeIfNeeded() -> Bool {
        if isMinimizeInProgress { return true }
        let shouldRelinquishNativeMagnify: Bool
        if case .magnification = activeMinimizeGesture {
            shouldRelinquishNativeMagnify = true
        } else {
            shouldRelinquishNativeMagnify = false
        }
        guard minimizeHandler?.beginMinimize() == true else {
            activeMinimizeGesture = nil
            return false
        }
        isMinimizeInProgress = true
        if shouldRelinquishNativeMagnify {
            pageController.relinquishCurrentPageNativeMagnifyGesture()
        }
        return true
    }

    private func finishMinimizeGesture(commit: Bool) -> Bool {
        activeMinimizeGesture = nil
        guard isMinimizeInProgress else { return false }
        isMinimizeInProgress = false
        minimizeHandler?.endMinimize(commit: commit)
        return true
    }

    private func cancelActiveMinimizeGesture() {
        _ = finishMinimizeGesture(commit: false)
    }

    private func shouldHandleNavigationKeyEvent(_ event: NSEvent) -> Bool {
        guard ownsActiveSession, isActive, let window = view.window else { return false }
        guard window.isKeyWindow, event.window === window else { return false }
        guard !(window.firstResponder is NSTextView) else { return false }
        return true
    }

    private static func navigationAction(for event: NSEvent) -> PlayerNavigationKeyAction? {
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(shortcutModifiers).isEmpty else { return nil }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              let scalar = characters.unicodeScalars.first else {
            return nil
        }

        switch scalar.value {
        case 0x1B:
            return .exit
        case 0x20:
            return .forward(animation: .animated)
        case 0xF700, 0xF703:
            return .forward(animation: .immediate)
        case 0xF701, 0xF702:
            return .back(animation: .immediate)
        default:
            break
        }

        switch characters {
        case "w", "d":
            return .forward(animation: .immediate)
        case "a", "s":
            return .back(animation: .immediate)
        default:
            return nil
        }
    }

}

private enum PlayerNavigationKeyAction {
    case back(animation: MacPlayerNavigationAnimation)
    case forward(animation: MacPlayerNavigationAnimation)
    case exit
}

extension MacPlayerPagerViewController: PlayerMenuDelegate {

    func popUpMenu(view: NSView) {
        mediaActions.popUpContextMenu(for: view)
    }

}
