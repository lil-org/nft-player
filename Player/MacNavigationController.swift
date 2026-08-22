// ∅ 2026 lil org

import Cocoa
import SwiftUI

protocol MacNavigationScreen: NSViewController {
    func navigationScreenDidBecomeActive()
    func navigationScreenDidResignActive()
    func navigationScreenDidMoveOffstage()
}

extension MacNavigationScreen {
    func navigationScreenDidMoveOffstage() {}
}

extension MacRoute {
    /// How deep in the stack this route sits, which decides the slide direction.
    var depth: Int {
        switch self {
        case .collections:
            return 0
        case let .player(_, mode):
            return mode == .collectionBrowser ? 1 : 2
        }
    }
}

/// The single window's content: a small navigation stack over collections grid →
/// collection browser → one-per-page, plus the overlay canvas the hero card
/// transition draws on.
final class MacNavigationContainerViewController: NSViewController {

    private struct CollectionBrowserHandoff {
        let tokenIndex: Int
        let requiresWidgetInsertionExit: Bool
    }

    private let model: MacNavigationModel
    private let cardTransitionCanvas = MacPlayerCardTransitionCanvas()

    private var currentRoute: MacRoute?
    private var currentChild: NSViewController?
    private var stagedChild: NSViewController?
    private var isTransitioning = false
    private var isPreparingForWindowClose = false
    private var lastLayoutSize: CGSize?
    private var requestedCollectionBrowserTokenIndex: Int?
    private var pendingCollectionBrowserHandoff: CollectionBrowserHandoff?

    /// Held separately from the accessor so `disposeOrphanedChildren()` can ask
    /// whether the grid exists without bringing it into existence.
    private var loadedCollectionsViewController: NSViewController?

    private var collectionsViewController: NSViewController {
        if let loadedCollectionsViewController {
            return loadedCollectionsViewController
        }
        let hostingController = NSHostingController(rootView: MacCollectionsScreen())
        loadedCollectionsViewController = hostingController
        return hostingController
    }

    private var sessionId: UUID?
    private var mediaActions: MacPlayerMediaActions?
    private var pagerViewController: MacPlayerPagerViewController?
    private var browserViewController: MacCollectionBrowserViewController?
    private var modeController: MacPlayerModeController?

    init(model: MacNavigationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        cardTransitionCanvas.frame = view.bounds
        cardTransitionCanvas.autoresizingMask = [.width, .height]
        view.addSubview(cardTransitionCanvas)
        model.commands = self
        apply(route: model.route, transition: .none)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let layoutSize = view.bounds.size
        let previousLayoutSize = lastLayoutSize
        lastLayoutSize = layoutSize
        guard let previousLayoutSize,
              previousLayoutSize.width > 0,
              previousLayoutSize.height > 0,
              layoutSize.width > 0,
              layoutSize.height > 0,
              layoutSize != previousLayoutSize else {
            return
        }
        modeController?.containerBoundsDidChange()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        mediaActions?.updatePresentingWindow(view.window)
        updateWindowAppearance()
    }

    // MARK: - Reconciliation

    func apply(route: MacRoute, transition: MacRouteTransition) {
        guard isViewLoaded else { return }
        guard !isTransitioning else { return }
        if isPreparingForWindowClose, route != .collections {
            isPreparingForWindowClose = false
        }
        guard route != currentRoute else { return }

        let previousRoute = currentRoute
        syncSession(for: route)

        guard let viewController = viewController(for: route) else {
            if route != .collections {
                model.showCollections()
            }
            return
        }

        currentRoute = route
        prepareScreen(viewController, for: route)
        show(
            viewController,
            routeTransition: transition,
            slidesForward: (previousRoute?.depth ?? -1) < route.depth
        )
        updateWindowAppearance()
    }

    private func viewController(for route: MacRoute) -> NSViewController? {
        switch route {
        case .collections:
            return collectionsViewController
        case let .player(_, mode):
            switch mode {
            case .collectionBrowser:
                return browserViewController ?? pagerViewController
            case .onePerPage:
                return pagerViewController
            }
        }
    }

    /// Lines the destination screen up with what the other one was showing before it
    /// comes on stage.
    private func prepareScreen(_ viewController: NSViewController, for route: MacRoute) {
        guard case let .player(_, mode) = route else { return }
        switch mode {
        case .collectionBrowser:
            let requestedTokenIndex = requestedCollectionBrowserTokenIndex
            requestedCollectionBrowserTokenIndex = nil
            pendingCollectionBrowserHandoff = nil
            guard let browserViewController = viewController as? MacCollectionBrowserViewController,
                  let session = model.session else {
                return
            }
            let tokenIndex = requestedTokenIndex.flatMap {
                (0..<session.tokenCount).contains($0) ? $0 : nil
            } ?? session.collectionBrowserTokenIndex
                ?? pagerViewController?.currentTokenIndex
            guard let tokenIndex, (0..<session.tokenCount).contains(tokenIndex) else { return }
            browserViewController.scroll(toTokenIndex: tokenIndex, animated: false)
            pendingCollectionBrowserHandoff = CollectionBrowserHandoff(
                tokenIndex: tokenIndex,
                requiresWidgetInsertionExit: session.playerModel.widgetTokenInsertion != nil
            )
        case .onePerPage:
            requestedCollectionBrowserTokenIndex = nil
            pendingCollectionBrowserHandoff = nil
        }
    }

    private func syncSession(for route: MacRoute) {
        guard let sessionId = route.sessionId,
              let session = model.session,
              session.id == sessionId else {
            tearDownSession()
            return
        }
        guard self.sessionId != sessionId else { return }

        tearDownSession()
        self.sessionId = sessionId

        let mediaActions = MacPlayerMediaActions(
            contextProvider: { [weak self] in
                guard let self,
                      self.sessionId == sessionId,
                      self.model.session?.id == sessionId else {
                    return nil
                }
                return self.actionTargetContext
            },
            targetProvider: { [weak self] in
                guard let self,
                      self.sessionId == sessionId,
                      self.model.session?.id == sessionId else {
                    return nil
                }
                return self.actionTarget
            }
        )
        mediaActions.updatePresentingWindow(view.window)
        self.mediaActions = mediaActions

        let pagerViewController = MacPlayerPagerViewController(
            session: session,
            model: model,
            mediaActions: mediaActions
        )
        self.pagerViewController = pagerViewController

        guard session.supportsCollectionBrowser else { return }

        let browserViewController = MacCollectionBrowserViewController(
            session: session,
            model: model
        )
        self.browserViewController = browserViewController
        let modeController = MacPlayerModeController(
            model: model,
            session: session,
            container: self,
            browserViewController: browserViewController,
            pagerViewController: pagerViewController,
            canvas: cardTransitionCanvas
        )
        self.modeController = modeController
        browserViewController.onSelection = { [weak modeController] snapshot in
            modeController?.expand(snapshot)
        }
        browserViewController.onFocusedTokenIndex = { [weak model] tokenIndex in
            guard model?.session?.id == sessionId else { return }
            model?.updateBrowserFocus(tokenIndex: tokenIndex)
        }
        pagerViewController.minimizeHandler = modeController
    }

    private var actionTargetContext: PlayerTokenContext? {
        guard let session = model.session,
              session.id == sessionId else {
            return nil
        }
        guard currentRoute?.displayMode == .collectionBrowser,
              let focusedTokenContext = browserViewController?.focusedTokenContext else {
            return CollectionCatalog.tokenContext(for: session.playerModel.currentToken)
        }
        return focusedTokenContext
    }

    private var actionTarget: MacPlayerMediaActions.Target? {
        guard let session = model.session,
              session.id == sessionId else {
            return nil
        }

        let currentToken = session.playerModel.currentToken
        let currentTarget = MacPlayerMediaActions.Target(
            token: currentToken,
            context: CollectionCatalog.tokenContext(for: currentToken)
        )
        guard currentRoute?.displayMode == .collectionBrowser,
              let focusedTokenContext = browserViewController?.focusedTokenContext else {
            return currentTarget
        }
        guard let focusedToken = CollectionCatalog.generateToken(
            specificCollectionId: focusedTokenContext.collectionId,
            tokenIndex: focusedTokenContext.tokenIndex
        ) else {
            return nil
        }
        return MacPlayerMediaActions.Target(
            token: focusedToken,
            context: focusedTokenContext
        )
    }

    private func tearDownSession(removingOffstageChildren: Bool = true) {
        guard sessionId != nil else { return }
        sessionId = nil
        // The mode controller is about to go away; if a hero animation is in flight its
        // completion will never run, so retire the canvas here rather than leaving it
        // frozen on top of every later screen. Only reached on a real session change —
        // the hero's own route swaps keep the same sessionId and never land here.
        modeController?.prepareForSessionTeardown()
        cardTransitionCanvas.end()
        modeController = nil
        mediaActions?.cancelActiveCopyMediaRequest()
        mediaActions = nil
        for child in [pagerViewController as NSViewController?, browserViewController as NSViewController?] {
            guard let child, child !== currentChild else { continue }
            (child as? MacNavigationScreen)?.navigationScreenDidMoveOffstage()
            guard removingOffstageChildren else { continue }
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        // The screen still on stage is swept by disposeOrphanedChildren() once it has
        // slid off; clearing these first is what makes it fall through that filter.
        pagerViewController = nil
        browserViewController = nil
        stagedChild = nil
        requestedCollectionBrowserTokenIndex = nil
        pendingCollectionBrowserHandoff = nil
    }

    // MARK: - Child swapping

    private func show(
        _ viewController: NSViewController,
        routeTransition: MacRouteTransition,
        slidesForward: Bool
    ) {
        guard currentChild !== viewController else { return }

        if viewController.parent !== self {
            addChild(viewController)
        }
        viewController.view.autoresizingMask = [.width, .height]
        viewController.view.frame = view.bounds

        let previousChild = currentChild
        currentChild = viewController
        if !isPreparingForWindowClose {
            (previousChild as? MacNavigationScreen)?.navigationScreenDidResignActive()
        }

        if stagedChild === viewController {
            stagedChild = nil
        }

        guard let previousChild, case .slide = routeTransition else {
            unstageStagedChild()
            previousChild?.view.removeFromSuperview()
            if viewController.view.superview !== view {
                view.addSubview(viewController.view, positioned: .below, relativeTo: cardTransitionCanvas)
            }
            finishShow(viewController, outgoing: previousChild)
            return
        }

        unstageStagedChild()
        if let browserViewController = viewController as? MacCollectionBrowserViewController {
            browserViewController.view.layoutSubtreeIfNeeded()
            browserViewController.prepareForIncomingTransition()
        }
        isTransitioning = true
        self.transition(
            from: previousChild,
            to: viewController,
            options: slidesForward ? NSViewController.TransitionOptions.slideForward : .slideBackward
        ) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isTransitioning = false
                self.finishShow(viewController, outgoing: previousChild)
                self.reconcileModelRouteAfterTransition()
            }
        }
    }

    private func reconcileModelRouteAfterTransition() {
        guard model.route != currentRoute else { return }
        apply(route: model.route, transition: model.routeTransition)
    }

    private func finishShow(_ viewController: NSViewController, outgoing: NSViewController?) {
        let shouldCompletePresentation = !isPreparingForWindowClose
            && model.route == currentRoute
        if shouldCompletePresentation {
            commitCollectionBrowserHandoffIfNeeded(for: viewController)
        }
        bringCardTransitionCanvasToFront()
        if shouldCompletePresentation {
            (viewController as? MacNavigationScreen)?.navigationScreenDidBecomeActive()
        }
        if outgoing !== viewController {
            (outgoing as? MacNavigationScreen)?.navigationScreenDidMoveOffstage()
        }
        disposeOrphanedChildren()
        if shouldCompletePresentation, currentRoute == .collections {
            // Back on the grid: stop the abandoned collection's prefetching rather than
            // waiting on a screen's deinit. Done here, after the slide, so cells that
            // are still on screen during the animation are not blanked. Nothing on the
            // grid reads this cache, so cancelling cannot affect what is now visible.
            DownloadableMediaCache.shared.cancelAllDownloads()
        }
        // The toolbar's paging state comes from this container, which is not
        // observable — refresh it now that the screen is up.
        model.refreshCommandState()
        if isPreparingForWindowClose, currentRoute == .collections {
            isPreparingForWindowClose = false
        }
    }

    private func commitCollectionBrowserHandoffIfNeeded(for viewController: NSViewController) {
        guard viewController === browserViewController,
              let handoff = pendingCollectionBrowserHandoff else {
            return
        }
        pendingCollectionBrowserHandoff = nil
        guard handoff.requiresWidgetInsertionExit else { return }
        pagerViewController?.commitCollectionBrowserHandoff(toTokenIndex: handoff.tokenIndex)
    }

    /// Drops screens the container no longer owns. `NSViewController.transition` only
    /// swaps views, so without this the outgoing screen of a finished session stays in
    /// `children` forever and its `deinit` — which is what unloads web content and
    /// tears down cache observers — never runs.
    private func disposeOrphanedChildren() {
        for child in children where child !== currentChild
            && child !== stagedChild
            && child !== loadedCollectionsViewController
            && child !== pagerViewController
            && child !== browserViewController {
            (child as? MacNavigationScreen)?.navigationScreenDidMoveOffstage()
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }

    // MARK: - Hero transition support

    func prepareCollectionBrowserHandoff(toTokenIndex tokenIndex: Int) {
        requestedCollectionBrowserTokenIndex = tokenIndex
    }

    func bringCardTransitionCanvasToFront() {
        cardTransitionCanvas.removeFromSuperview()
        cardTransitionCanvas.frame = view.bounds
        cardTransitionCanvas.autoresizingMask = [.width, .height]
        view.addSubview(cardTransitionCanvas)
    }

    /// Puts an off-stack screen back in the hierarchy underneath the current one so
    /// it lays out and can report cell geometry mid-transition.
    func stageBehindCurrentChild(_ viewController: NSViewController) {
        guard viewController !== currentChild else { return }
        if viewController.parent !== self {
            addChild(viewController)
        }
        viewController.view.autoresizingMask = [.width, .height]
        viewController.view.frame = view.bounds
        if viewController.view.superview !== view {
            view.addSubview(viewController.view, positioned: .below, relativeTo: currentChild?.view)
        }
        view.layoutSubtreeIfNeeded()
        stagedChild = viewController
    }

    func unstage(_ viewController: NSViewController) {
        guard stagedChild === viewController else { return }
        unstageStagedChild()
    }

    func unstageStagedChild() {
        guard let stagedChild, stagedChild !== currentChild else {
            self.stagedChild = nil
            return
        }
        self.stagedChild = nil
        (stagedChild as? MacNavigationScreen)?.navigationScreenDidMoveOffstage()
        stagedChild.view.removeFromSuperview()
    }

    // MARK: - Window appearance

    private func updateWindowAppearance() {
        let isPlayerScreen = currentRoute != .collections
        let backgroundColor: NSColor = isPlayerScreen ? .black : .windowBackgroundColor
        view.layer?.backgroundColor = backgroundColor.cgColor
        view.window?.backgroundColor = backgroundColor
    }

}

// MARK: - Toolbar commands

extension MacNavigationContainerViewController: MacNavigationCommands {

    var isNavigationTransitionInFlight: Bool {
        isTransitioning
            || modeController?.isTransitionInFlight == true
            || pagerViewController?.isPageTransitionInFlight == true
    }

    var canGoToPreviousPage: Bool {
        !isNavigationTransitionInFlight && pagerViewController?.canGoBack == true
    }

    var canGoToNextPage: Bool {
        !isNavigationTransitionInFlight && pagerViewController?.canGoForward == true
    }

    var canUseMediaFile: Bool {
        mediaActions?.canUseMediaFile == true
    }

    func goToPreviousPage() {
        guard !isNavigationTransitionInFlight else { return }
        pagerViewController?.goBack()
    }

    func goToNextPage() {
        guard !isNavigationTransitionInFlight else { return }
        pagerViewController?.goForward()
    }

    func copyMedia() {
        mediaActions?.copyMedia()
    }

    func saveMediaAs() {
        mediaActions?.saveMediaAs()
    }

    func viewOnBlockExplorer() {
        mediaActions?.viewOnWeb()
    }

    func navigateBackWithHeroTransition() -> Bool {
        // A hero transition already owns the destination. Swallow the press instead of
        // racing a slide against the flying card (and, for a live drag, instead of
        // cancelling the gesture out from under the user).
        if isNavigationTransitionInFlight {
            return true
        }
        guard currentRoute?.displayMode == .onePerPage,
              let modeController,
              modeController.canMinimizeFromChrome else {
            return false
        }
        modeController.minimizeImmediately()
        return true
    }

    func prepareForWindowClose() {
        let wasTransitioning = isTransitioning
        isPreparingForWindowClose = true
        cardTransitionCanvas.end()
        if wasTransitioning {
            children.forEach {
                ($0 as? MacNavigationScreen)?.navigationScreenDidMoveOffstage()
            }
        } else {
            (currentChild as? MacNavigationScreen)?.navigationScreenDidResignActive()
        }
        tearDownSession(removingOffstageChildren: !wasTransitioning)
        apply(route: model.route, transition: .none)
        if !isTransitioning, currentRoute == .collections {
            isPreparingForWindowClose = false
        }
    }

}

struct MacNavigationContainerView: NSViewControllerRepresentable {

    let model: MacNavigationModel

    func makeNSViewController(context: Context) -> MacNavigationContainerViewController {
        MacNavigationContainerViewController(model: model)
    }

    func updateNSViewController(_ nsViewController: MacNavigationContainerViewController, context: Context) {
        nsViewController.apply(route: model.route, transition: model.routeTransition)
    }

}
