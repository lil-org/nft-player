import Observation
import UIKit

final class MobilePlayerBrowserPageViewController: UIViewController {

    weak var modeController: MobilePlayerSessionModeController?
    var onAccessibilityEscape: (() -> Bool)?
    var onPlayerLayout: (() -> Void)?

    private let playbackSession: MobilePlaybackSession
    private let chrome: MobilePlayerChromeController
    private let contentViewController: VerticalCollectionBrowserViewController
    private let tokenProvider: @MainActor (PlayerPagePosition) -> GeneratedToken
    private let externalDisplayTokenUpdater: @MainActor (GeneratedToken) -> Void
    private var playerPageBackgroundColor = MobilePlayerBackgroundColor.defaultColor
    private var chromeObservationGeneration: UInt = 0
    private lazy var moreMenu = makeMoreMenu()
    private lazy var moreBarButtonItem = makeMoreBarButtonItem()

    var currentPagePosition: PlayerPagePosition? {
        contentViewController.currentPagePosition
    }

    init(
        playbackSession: MobilePlaybackSession,
        chrome: MobilePlayerChromeController,
        tokenProvider: (@MainActor (PlayerPagePosition) -> GeneratedToken)? = nil,
        externalDisplayTokenUpdater:
            (@MainActor (GeneratedToken) -> Void)? = nil
    ) {
        self.playbackSession = playbackSession
        self.chrome = chrome
        self.tokenProvider = tokenProvider ?? {
            playbackSession.getToken(pagePosition: $0)
        }
        self.externalDisplayTokenUpdater = externalDisplayTokenUpdater ?? {
            updateExternalDisplayToken($0)
        }
        self.contentViewController = VerticalCollectionBrowserViewController(
            playbackSession: playbackSession
        )
        super.init(nibName: nil, bundle: nil)

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
            return self.handleSettledPagePosition(
                pagePosition: pagePosition,
                hasViewedToEnd: hasViewedToEnd
            )
        }
        contentViewController.onSelection = { [weak self] selection in
            self?.openSelection(selection) == true
        }
        contentViewController.onImmediateSelection = { [weak self] pagePosition, onFailure in
            self?.openImmediateSelection(pagePosition, onFailure: onFailure) == true
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

        chromeObservationGeneration &+= 1
        applyPlayerContentVisibility()
        observePlayerContentVisibility(
            generation: chromeObservationGeneration
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyPlayerPageBackground()
        onPlayerLayout?()
    }

    private func observePlayerContentVisibility(generation: UInt) {
        withObservationTracking {
            _ = chrome.isPlayerContentHiddenForCardTransition
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      chromeObservationGeneration == generation else {
                    return
                }
                applyPlayerContentVisibility()
                observePlayerContentVisibility(generation: generation)
            }
        }
    }

    private func applyPlayerContentVisibility() {
        let isHidden = chrome.isPlayerContentHiddenForCardTransition
        contentViewController.view.alpha = isHidden ? 0 : 1
        contentViewController.view.isUserInteractionEnabled = !isHidden
        moreBarButtonItem.menu = isHidden ? nil : moreMenu
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
        let token = tokenProvider(playbackSession.startPagePosition())
        refreshNavigationTitles(with: token)
    }

    func setBrowserActive(_ active: Bool) {
        contentViewController.setActive(active)
        guard active else { return }
        let pagePosition = currentMenuPagePosition
        updatePlayerNavigationTitle(
            for: pagePosition,
            token: tokenProvider(pagePosition)
        )
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
        completion: @escaping @MainActor (
            MobilePlayerCollectionBrowserDisplayPreparationResult
        ) -> Void
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
        if let pagePosition = preparation.snapshot.pagePosition(
            forTokenIndex: preparation.focusedTokenIndex
        ) {
            let token = tokenProvider(pagePosition)
            refreshNavigationTitles(with: token)
        }
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

        var elements: [UIMenuElement] = [contentViewController.makeGridModeMenu()]

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

    private var currentMenuPagePosition: PlayerPagePosition {
        contentViewController.currentPagePosition
            ?? playbackSession.startPagePosition()
    }

    private var currentMenuToken: GeneratedToken {
        tokenProvider(currentMenuPagePosition)
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
        chrome.setPlayerNavigationPageLabel(
            contentViewController.pageLabel(for: pagePosition) ?? ""
        )
    }

    private func handleSettledPagePosition(
        pagePosition: PlayerPagePosition,
        hasViewedToEnd: Bool
    ) -> Bool {
        let token = tokenProvider(pagePosition)
        updatePlayerNavigationTitle(for: pagePosition, token: token)
        if playbackSession.isActive {
            externalDisplayTokenUpdater(token)
        }
        chrome.setPlayerBackgroundColor(MobilePlayerBackgroundColor.color(for: token))
        chrome.setLayoutInteractionState(
            playbackSession.layoutInteractionState(
                displayMode: .collectionBrowser,
                pagePosition: pagePosition,
                collectionBrowserAvailable: true
            )
        )
        refreshNavigationTitles(with: token)
        return playbackSession.markViewed(
            pagePosition: pagePosition,
            hasViewedToEnd: hasViewedToEnd
        ) != nil
    }

    private func updatePlayerNavigationTitle(
        for pagePosition: PlayerPagePosition,
        token: GeneratedToken
    ) {
        chrome.setPlayerNavigationTitle(
            collectionTitle: token.collectionName,
            pageLabel: playbackSession.pageLabel(
                pagePosition: pagePosition
            ) ?? ""
        )
    }

    private func refreshNavigationTitles(with token: GeneratedToken) {
        refreshBackButtonTitle(with: token)
        refreshMoreMenu(with: token)
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

    private func openImmediateSelection(
        _ pagePosition: PlayerPagePosition,
        onFailure: @escaping () -> Void
    ) -> Bool {
        guard let modeController, modeController.activeMode == .collectionBrowser else { return false }

        var requestReturned = false
        var didFailSynchronously = false
        modeController.switchToOnePerPage(targetPagePosition: pagePosition) { didSwitch in
            guard !didSwitch else { return }
            if requestReturned {
                onFailure()
            } else {
                didFailSynchronously = true
            }
        }
        requestReturned = true
        guard !didFailSynchronously else { return false }

        Haptic.selectionChanged()
        return true
    }

}
