// ∅ 2026 lil org

import Combine
import UIKit

/// Pager-side operations the session mode controller drives on the
/// one-per-page player. Implemented by `HorizontalPlayerContainer` and
/// registered on the shared `MobilePlayerChromeController`.
protocol MobilePlayerPagerProviding: AnyObject {

    func pagerCurrentPagePosition() -> PlayerPagePosition
    @discardableResult
    func reanchorPager(
        to pagePosition: PlayerPagePosition,
        completion: @escaping () -> Void
    ) -> Bool
    func activatePagerAfterModeSwitch(destination: PlayerPagePosition)
    func deactivatePagerForCollectionBrowser()
    func navigatePager(_ direction: PlaybackNavigationDirection)
    func makePagerTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView?
    func flushPagerViewingProgress()

}

/// Navigation-stack entry hosting the in-player collection browser.
/// Contributes the browser's more menu and never hides the status bar,
/// matching the browser display mode of the previous single-controller player.
final class MobilePlayerBrowserPageViewController: UIViewController {

    weak var modeController: MobilePlayerSessionModeController?
    var onAccessibilityEscape: (() -> Bool)?
    var onPlayerLayout: (() -> Void)?

    private let configID: UUID
    private let chrome: MobilePlayerChromeController
    private let contentViewController: VerticalCollectionBrowserViewController
    private var playerPageBackgroundColor = MobilePlayerBackgroundColor.defaultColor
    private var chromeCancellables = Set<AnyCancellable>()
    private lazy var moreMenu = makeMoreMenu()
    private lazy var moreBarButtonItem = makeMoreBarButtonItem()

    var currentPagePosition: PlayerPagePosition? {
        contentViewController.currentPagePosition
    }

    init(uuid: UUID, chrome: MobilePlayerChromeController) {
        self.configID = uuid
        self.chrome = chrome
        self.contentViewController = VerticalCollectionBrowserViewController(uuid: uuid)
        super.init(nibName: nil, bundle: nil)

        // Keep the pager's visible back button chevron-only while its
        // long-press menu still lists this entry by collection name.
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.rightBarButtonItem = moreBarButtonItem

        contentViewController.onFocusedPagePosition = { [weak self] pagePosition in
            guard let self,
                  self.modeController?.activeMode == .collectionBrowser else { return }
            self.handleFocusedPagePosition(pagePosition)
        }
        contentViewController.onSettledPagePosition = { [weak self] pagePosition, hasViewedToEnd in
            guard let self,
                  self.modeController?.activeMode == .collectionBrowser else { return false }
            return MobilePlaybackController.shared.markViewed(
                uuid: self.configID,
                pagePosition: pagePosition,
                hasViewedToEnd: hasViewedToEnd
            ) != nil
        }
        contentViewController.onSelection = { [weak self] selection in
            self?.openSelection(selection) == true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .none
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyPlayerPageBackground()

        addChild(contentViewController)
        view.addSubview(contentViewController.view)
        contentViewController.didMove(toParent: self)
        contentViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        contentViewController.view.makeBackgroundTransparent()

        chrome.$isPlayerContentHiddenForCardTransition
            .sink { [weak self] isHidden in
                guard let self else { return }
                self.contentViewController.view.alpha = isHidden ? 0 : 1
                self.contentViewController.view.isUserInteractionEnabled = !isHidden
                self.moreBarButtonItem.menu = isHidden ? nil : self.moreMenu
            }
            .store(in: &chromeCancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyPlayerPageBackground()
        onPlayerLayout?()
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

    func seedNavigationTitles() {
        let token = MobilePlaybackController.shared.getToken(
            uuid: configID,
            pagePosition: MobilePlaybackController.shared.startPagePosition(uuid: configID)
        )
        refreshBackButtonTitle(with: token)
        refreshMoreMenu(with: token)
    }

    func setBrowserActive(_ active: Bool) {
        contentViewController.setActive(active)
    }

    func flushSettledPosition() {
        contentViewController.flushSettledPosition()
    }

    func scrollToFirstItemAndPublish() {
        contentViewController.scrollToFirstItemAndPublish()
    }

    func prepareForDisplay(
        using preparation: PlayerCollectionBrowsePreparation,
        publishWhenStable: Bool,
        completion: @escaping (MobilePlayerCollectionBrowserDisplayPreparationResult) -> Void
    ) {
        contentViewController.prepareForDisplay(
            using: preparation,
            publishWhenStable: publishWhenStable,
            completion: completion
        )
    }

    func finalizePreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) -> Bool {
        contentViewController.finalizePreparedDisplay(preparation)
    }

    func canCommitPreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) -> Bool {
        contentViewController.canCommitPreparedDisplay(preparation)
    }

    func commitPreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) {
        contentViewController.commitPreparedDisplay(preparation)
    }

    func cancelPendingDisplayPreparation() {
        contentViewController.cancelPendingDisplayPreparation()
    }

    func preparedTransitionSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection? {
        contentViewController.preparedTransitionSelection(for: pagePosition)
    }

    func cancelPreparedTransition() {
        contentViewController.cancelPreparedTransition()
    }

    private func applyPlayerPageBackground() {
        view.backgroundColor = playerPageBackgroundColor
        view.isOpaque = true
    }

    /// Mirrors the collection grid's context menu: collection name, primary
    /// action, then artist links. The browser's primary action opens the
    /// collection address in the block explorer instead of playing an item.
    private func makeMoreMenu(for token: GeneratedToken? = nil) -> UIMenu {
        let token = token ?? currentMenuToken
        let collectionId = token.fullCollectionId
        let deferredElement = UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.moreMenuElements(forCollectionId: collectionId) ?? [])
        }
        return UIMenu(title: token.collectionName, children: [deferredElement])
    }

    private func makeMoreBarButtonItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: moreMenu
        )
        item.preferredMenuElementOrder = .fixed
        item.accessibilityLabel = Strings.more
        return item
    }

    private func moreMenuElements(forCollectionId collectionId: String) -> [UIMenuElement] {
        guard !chrome.isPlayerContentHiddenForCardTransition else { return [] }

        var elements: [UIMenuElement] = []

        if let collectionURL = CollectionCatalog.collectionWebURL(
            specificCollectionId: collectionId
        ) {
            let blockExplorerAction = UIAction(
                title: Strings.viewOnBlockExplorer
            ) { [weak self] _ in
                self?.openMoreMenuURL(collectionURL)
            }
            elements.append(blockExplorerAction)
        }

        elements.append(contentsOf: artistLinkMenus(forCollectionId: collectionId))
        return elements
    }

    private var currentMenuToken: GeneratedToken {
        let pagePosition = contentViewController.currentPagePosition
            ?? MobilePlaybackController.shared.startPagePosition(uuid: configID)
        return MobilePlaybackController.shared.getToken(
            uuid: configID,
            pagePosition: pagePosition
        )
    }

    private func artistLinkMenus(forCollectionId collectionId: String) -> [UIMenu] {
        SuggestedItemsService.artists(forCollectionId: collectionId).compactMap { artist in
            let actions = artist.links.map { link in
                UIAction(
                    title: link.title,
                    image: Self.artistLinkImage(for: link.kind)
                ) { [weak self] _ in
                    self?.openMoreMenuURL(link.destination)
                }
            }

            guard !actions.isEmpty else { return nil }
            return UIMenu(options: .displayInline, children: actions)
        }
    }

    private func openMoreMenuURL(_ url: URL) {
        guard !chrome.isPlayerContentHiddenForCardTransition else { return }
        UIApplication.shared.open(url)
    }

    private static func artistLinkImage(for kind: SuggestedArtistLink.Kind) -> UIImage? {
        switch kind {
        case .website:
            UIImage(systemName: "globe")
        case .x:
            UIImage(named: "XLogo")
        case .bluesky:
            UIImage(named: "BlueskyLogo")
        }
    }

    private func handleFocusedPagePosition(_ pagePosition: PlayerPagePosition) {
        let token = MobilePlaybackController.shared.getToken(
            uuid: configID,
            pagePosition: pagePosition
        )
        chrome.setPlayerBackgroundColor(MobilePlayerBackgroundColor.color(for: token))
        chrome.setLayoutInteractionState(
            MobilePlaybackController.shared.layoutInteractionState(
                uuid: configID,
                displayMode: .collectionBrowser,
                pagePosition: pagePosition,
                collectionBrowserAvailable: true
            )
        )
        refreshBackButtonTitle(with: token)
        refreshMoreMenu(with: token)
        updateExternalDisplayToken(token)
    }

    private func refreshBackButtonTitle(with token: GeneratedToken) {
        let title = token.collectionName
        guard !title.isEmpty,
              navigationItem.backButtonTitle != title else {
            return
        }
        navigationItem.backButtonTitle = title
    }

    private func refreshMoreMenu(with token: GeneratedToken) {
        moreMenu = makeMoreMenu(for: token)
        if !chrome.isPlayerContentHiddenForCardTransition {
            moreBarButtonItem.menu = moreMenu
        }
    }

    private func openSelection(
        _ selection: MobilePlayerBrowserTransitionSelection
    ) -> Bool {
        guard modeController?.activeMode == .collectionBrowser else { return false }

        switch chrome.requestCollectionBrowserExpand(selection) {
        case .started:
            Haptic.selectionChanged()
            return true
        case .busy:
            return false
        case .fallbackToImmediateOpen:
            modeController?.switchToOnePerPage(
                targetPagePosition: selection.selectedSnapshot.pagePosition
            )
            Haptic.selectionChanged()
            return true
        case .rejected:
            return false
        }
    }

}

/// Session-scoped authority over which display mode owns the top of the
/// navigation stack. Replaces the old in-place child swap inside
/// `HorizontalPlayerContainer` with non-animated pushes/pops of the browser
/// and pager view controllers, keeping every visible transition identical.
final class MobilePlayerSessionModeController {

    private(set) var activeMode: MobilePlayerDisplayMode

    private let config: MobilePlayerConfig
    private let chrome: MobilePlayerChromeController
    private weak var navigationController: UINavigationController?
    private let browserViewController: MobilePlayerBrowserPageViewController?
    private let pagerViewController: UIViewController
    private let liveLayoutInteractionStateProviderID = UUID()
    private var operationGeneration: UInt = 0
    private var activeOperationGeneration: UInt?

    init(
        config: MobilePlayerConfig,
        chrome: MobilePlayerChromeController,
        navigationController: UINavigationController,
        browserViewController: MobilePlayerBrowserPageViewController?,
        pagerViewController: UIViewController,
        initialMode: MobilePlayerDisplayMode
    ) {
        self.config = config
        self.chrome = chrome
        self.navigationController = navigationController
        self.browserViewController = browserViewController
        self.pagerViewController = pagerViewController
        self.activeMode = initialMode

        MobilePlaybackController.shared.subscribe(config: config, display: self)
        chrome.setCollectionBrowserTransitionProvider(self)
        chrome.setLiveLayoutInteractionStateProvider(
            id: liveLayoutInteractionStateProviderID
        ) { [weak self] in
            self?.currentLayoutInteractionState() ?? .empty
        }
    }

    func invalidate() {
        supersedeActiveOperation()
        chrome.clearLiveLayoutInteractionStateProvider(id: liveLayoutInteractionStateProviderID)
        chrome.clearCollectionBrowserTransitionProvider(self)
        chrome.setLayoutInteractionState(.empty)
        unstageBrowserViewIfNeeded()
        unstagePagerViewIfNeeded()
    }

    // MARK: - Mode switches

    /// Commits the pager → browser switch: prepares and centers the browser
    /// offscreen, commits the browse position, then pops the pager without
    /// animation. Mirrors the old `applyCollectionBrowserDisplayMode` flow.
    func switchToCollectionBrowser(
        targetPagePosition: PlayerPagePosition?,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let navigationController,
              let browserViewController,
              activeMode == .onePerPage,
              navigationController.transitionCoordinator == nil,
              navigationController.topViewController === pagerViewController,
              let pagerProvider = chrome.pagerProvider else {
            completion?(false)
            return
        }

        let sourcePagePosition = targetPagePosition ?? pagerProvider.pagerCurrentPagePosition()
        guard MobilePlaybackController.shared.canRender(
            uuid: config.id,
            pagePosition: sourcePagePosition
        ),
              let preparation = MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: config.id,
                containing: sourcePagePosition
              ) else {
            completion?(false)
            return
        }

        let generation = beginOperation()
        stageBrowserViewForTransition()
        browserViewController.prepareForDisplay(
            using: preparation,
            publishWhenStable: false
        ) { [weak self, weak browserViewController] preparationResult in
            guard let self,
                  let browserViewController,
                  self.isCurrentOperation(generation) else {
                completion?(false)
                return
            }

            func rejectOperation() {
                browserViewController.cancelPendingDisplayPreparation()
                // The morph-driven flows unstage through their prepared-selection
                // cleanup; the direct-switch flows have no other unstage point.
                self.unstageBrowserViewIfNeeded()
                self.finishOperation(generation)
                completion?(false)
            }

            guard preparationResult == .prepared else {
                rejectOperation()
                return
            }

            guard self.activeMode == .onePerPage,
                  self.navigationController?.topViewController === self.pagerViewController,
                  self.chrome.pagerProvider?.pagerCurrentPagePosition()
                    == preparation.sourcePagePosition else {
                rejectOperation()
                return
            }

            guard let expectedPagePosition = preparation.snapshot.pagePosition(
                forTokenIndex: preparation.focusedTokenIndex
            ),
                  browserViewController.canCommitPreparedDisplay(preparation) else {
                rejectOperation()
                return
            }

            let resolution = MobilePlaybackController.shared.commitCollectionBrowse(
                uuid: self.config.id,
                preparation: preparation
            )
            guard case .resolved(let resolvedPagePosition) = resolution else {
                rejectOperation()
                return
            }

            // A resolved commit may have exited widget position space. From
            // here onward, consume the already-validated browser transition
            // without running a cancellation path against the mutated model.
            assert(resolvedPagePosition == expectedPagePosition)
            assert(
                MobilePlaybackController.shared.collectionBrowseSnapshot(
                    uuid: self.config.id
                ) == preparation.snapshot
            )
            browserViewController.commitPreparedDisplay(preparation)
            self.commitCollectionBrowserPresentation(performsPop: true)
            self.finishOperation(generation)
            completion?(true)
        }
    }

    /// Commits the browser → pager switch: re-anchors the pager offscreen,
    /// then pushes it without animation. Mirrors the old
    /// `applyOnePerPageDisplayMode` flow.
    func switchToOnePerPage(
        targetPagePosition: PlayerPagePosition?,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let navigationController,
              let browserViewController,
              activeMode == .collectionBrowser,
              navigationController.transitionCoordinator == nil,
              navigationController.topViewController === browserViewController,
              let pagerProvider = chrome.pagerProvider else {
            completion?(false)
            return
        }
        if let targetPagePosition,
           !MobilePlaybackController.shared.canRender(
            uuid: config.id,
            pagePosition: targetPagePosition
           ) {
            completion?(false)
            return
        }

        browserViewController.flushSettledPosition()
        let destination = targetPagePosition
            ?? browserViewController.currentPagePosition
            ?? pagerProvider.pagerCurrentPagePosition()

        // Restore the player-owned chrome before browser mode stops
        // pinning the navigation bar visible. This keeps the navbar
        // continuous through expansion and starts every player visit
        // with its bottom controls visible.
        chrome.setControlsVisible(true)
        chrome.setNavigationBackSwipeAllowed(false)

        let generation = beginOperation()
        let didReanchor = pagerProvider.reanchorPager(to: destination) { [weak self] in
            guard let self,
                  self.isCurrentOperation(generation) else {
                completion?(false)
                return
            }

            guard self.chrome.pagerProvider?.pagerCurrentPagePosition() == destination,
                  self.activeMode == .collectionBrowser,
                  let navigationController = self.navigationController,
                  navigationController.topViewController === self.browserViewController else {
                self.chrome.setNavigationBackSwipeAllowed(
                    self.activeMode == .collectionBrowser
                )
                self.finishOperation(generation)
                completion?(false)
                return
            }

            self.browserViewController?.setBrowserActive(false)
            self.activeMode = .onePerPage
            self.unstagePagerViewIfNeeded()
            navigationController.pushViewController(self.pagerViewController, animated: false)
            MobilePlaybackController.shared.acknowledgeIntentionalViewingPosition(
                uuid: self.config.id
            )
            self.chrome.pagerProvider?.activatePagerAfterModeSwitch(destination: destination)
            self.finishOperation(generation)
            completion?(true)
        }

        guard didReanchor else {
            chrome.setNavigationBackSwipeAllowed(true)
            finishOperation(generation)
            completion?(false)
            return
        }
    }

    // MARK: - External navigation reconciliation

    func noteNavigationWillShow(_ viewController: UIViewController) {
        reconcileBrowserPresentationIfNeeded(shownViewController: viewController)
    }

    func noteNavigationDidShow(_ viewController: UIViewController) {
        reconcileBrowserPresentationIfNeeded(shownViewController: viewController)
    }

    /// A pop landed on the browser without the minimize flow — e.g. the
    /// back button's long-press menu. Re-align mode state immediately and
    /// re-center the browser on the pager's current item best-effort.
    private func reconcileBrowserPresentationIfNeeded(
        shownViewController: UIViewController
    ) {
        guard let browserViewController,
              shownViewController === browserViewController,
              activeMode == .onePerPage else {
            return
        }

        supersedeActiveOperation()
        let sourcePagePosition = chrome.pagerProvider?.pagerCurrentPagePosition()
        commitCollectionBrowserPresentation(performsPop: false)

        guard let sourcePagePosition,
              let preparation = MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: config.id,
                containing: sourcePagePosition
              ) else {
            return
        }

        let generation = beginOperation()
        browserViewController.prepareForDisplay(
            using: preparation,
            publishWhenStable: true
        ) { [weak self, weak browserViewController] preparationResult in
            guard let self,
                  let browserViewController,
                  self.isCurrentOperation(generation) else {
                return
            }
            defer {
                self.finishOperation(generation)
            }
            guard preparationResult == .prepared else {
                browserViewController.cancelPendingDisplayPreparation()
                return
            }

            _ = MobilePlaybackController.shared.commitCollectionBrowse(
                uuid: self.config.id,
                preparation: preparation
            )
            _ = browserViewController.finalizePreparedDisplay(preparation)
        }
    }

    private func commitCollectionBrowserPresentation(performsPop: Bool) {
        guard let browserViewController else { return }

        activeMode = .collectionBrowser
        chrome.pagerProvider?.deactivatePagerForCollectionBrowser()
        browserViewController.setBrowserActive(true)
        unstageBrowserViewIfNeeded()
        if performsPop {
            navigationController?.popViewController(animated: false)
        }
        chrome.setNavigationBackSwipeAllowed(true)
    }

    // MARK: - Offscreen staging

    /// The vertical browser assumes it stays window-mounted (safe-area
    /// capture and cell snapshots resolve against the window). While the
    /// pager owns the top of the stack, transitions temporarily attach the
    /// browser's view beneath the navigation controller's content; it is
    /// detached again right before UIKit re-hosts it during the pop.
    private func stageBrowserViewForTransition() {
        guard let navigationController,
              let browserViewController else {
            return
        }
        let browserView: UIView = browserViewController.view
        guard browserView.window == nil else { return }

        navigationController.view.insertSubview(browserView, at: 0)
        browserView.frame = navigationController.view.bounds
        browserView.layoutIfNeeded()
    }

    private func unstageBrowserViewIfNeeded() {
        guard let navigationController,
              let browserView = browserViewController?.viewIfLoaded,
              browserView.superview === navigationController.view else {
            return
        }
        browserView.removeFromSuperview()
    }

    /// The expand morph measures the destination card frame against the
    /// pager's laid-out view before the pager is pushed.
    func stagePagerViewForTransition() {
        guard let navigationController else { return }
        let pagerView: UIView = pagerViewController.view
        guard pagerView.window == nil else { return }

        navigationController.view.insertSubview(pagerView, at: 0)
        pagerView.frame = navigationController.view.bounds
        pagerView.layoutIfNeeded()
    }

    func unstagePagerViewIfNeeded() {
        guard let navigationController,
              let pagerView = pagerViewController.viewIfLoaded,
              pagerView.superview === navigationController.view else {
            return
        }
        pagerView.removeFromSuperview()
    }

    // MARK: - Operations

    private func beginOperation() -> UInt {
        if activeOperationGeneration != nil {
            browserViewController?.cancelPendingDisplayPreparation()
        }
        operationGeneration &+= 1
        activeOperationGeneration = operationGeneration
        return operationGeneration
    }

    private func isCurrentOperation(_ generation: UInt) -> Bool {
        activeOperationGeneration == generation
    }

    private func finishOperation(_ generation: UInt) {
        guard activeOperationGeneration == generation else { return }
        activeOperationGeneration = nil
    }

    private func supersedeActiveOperation() {
        guard activeOperationGeneration != nil else { return }
        activeOperationGeneration = nil
        operationGeneration &+= 1
        browserViewController?.cancelPendingDisplayPreparation()
    }

    private func currentLayoutInteractionState() -> MobilePlayerLayoutInteractionState {
        MobilePlaybackController.shared.layoutInteractionState(
            uuid: config.id,
            displayMode: activeMode,
            pagePosition: getCurrentPagePosition(),
            collectionBrowserAvailable: browserViewController != nil
        )
    }

}

extension MobilePlayerSessionModeController: MobilePlaybackControllerDisplay {

    func navigate(_ direction: PlaybackNavigationDirection) {
        guard activeMode == .collectionBrowser else {
            chrome.pagerProvider?.navigatePager(direction)
            return
        }

        if direction == .restartCollection {
            browserViewController?.scrollToFirstItemAndPublish()
        }
    }

    func getCurrentPagePosition() -> PlayerPagePosition {
        if activeMode == .collectionBrowser,
           let pagePosition = browserViewController?.currentPagePosition {
            return pagePosition
        }
        return chrome.pagerProvider?.pagerCurrentPagePosition()
            ?? MobilePlaybackController.shared.startPagePosition(uuid: config.id)
    }

    func flushPendingViewingProgress() {
        if activeMode == .collectionBrowser {
            browserViewController?.flushSettledPosition()
            return
        }

        chrome.pagerProvider?.flushPagerViewingProgress()
    }

}

extension MobilePlayerSessionModeController: MobilePlayerBrowserTransitionProviding {

    var isCollectionBrowserActive: Bool {
        activeMode == .collectionBrowser
    }

    func makeOnePerPageTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView? {
        guard activeMode == .onePerPage else { return nil }
        return chrome.pagerProvider?.makePagerTransitionSnapshot(
            from: sourceFrame,
            in: coordinateView
        )
    }

    func prepareCollectionBrowserSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection? {
        guard let browserViewController else { return nil }

        stageBrowserViewForTransition()
        let selection = browserViewController.preparedTransitionSelection(for: pagePosition)
        if selection == nil {
            unstageBrowserViewIfNeeded()
        }
        return selection
    }

    func cancelPreparedCollectionBrowserSelection() {
        browserViewController?.cancelPreparedTransition()
        unstageBrowserViewIfNeeded()
    }

}
