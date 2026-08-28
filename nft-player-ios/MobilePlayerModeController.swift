// ∅ 2026 lil org

import UIKit

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

final class MobilePlayerSessionModeController {

    private(set) var activeMode: MobilePlayerDisplayMode

    private let playbackSession: MobilePlaybackSession
    private let chrome: MobilePlayerChromeController
    private weak var navigationController: UINavigationController?
    private let browserViewController: MobilePlayerBrowserPageViewController?
    private let pagerViewController: UIViewController
    private let liveLayoutInteractionStateProviderID = UUID()
    private var operationGeneration: UInt = 0
    private var activeOperationGeneration: UInt?

    init(
        playbackSession: MobilePlaybackSession,
        chrome: MobilePlayerChromeController,
        navigationController: UINavigationController,
        browserViewController: MobilePlayerBrowserPageViewController?,
        pagerViewController: UIViewController,
        initialMode: MobilePlayerDisplayMode
    ) {
        self.playbackSession = playbackSession
        self.chrome = chrome
        self.navigationController = navigationController
        self.browserViewController = browserViewController
        self.pagerViewController = pagerViewController
        self.activeMode = initialMode

        playbackSession.attach(display: self)
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

    func switchToCollectionBrowser(
        targetPagePosition: PlayerPagePosition?,
        completion: (@MainActor (Bool) -> Void)? = nil
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
        guard playbackSession.canRender(
            pagePosition: sourcePagePosition
        ),
              let preparation = playbackSession.prepareCollectionBrowse(
                containing: sourcePagePosition
              ) else {
            completion?(false)
            return
        }

        playbackSession.acknowledgeIntentionalViewingPosition()
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

            guard preparationResult == .prepared else {
                self.rejectCollectionBrowserOperation(
                    browserViewController: browserViewController,
                    generation: generation,
                    completion: completion
                )
                return
            }

            guard self.activeMode == .onePerPage,
                  let navigationController = self.navigationController,
                  navigationController.transitionCoordinator == nil,
                  navigationController.topViewController === self.pagerViewController,
                  self.chrome.pagerProvider?.pagerCurrentPagePosition()
                    == preparation.sourcePagePosition else {
                self.rejectCollectionBrowserOperation(
                    browserViewController: browserViewController,
                    generation: generation,
                    completion: completion
                )
                return
            }

            guard let expectedPagePosition = preparation.snapshot.pagePosition(
                forTokenIndex: preparation.focusedTokenIndex
            ),
                  browserViewController.canCommitPreparedDisplay(preparation) else {
                self.rejectCollectionBrowserOperation(
                    browserViewController: browserViewController,
                    generation: generation,
                    completion: completion
                )
                return
            }

            let resolution = self.playbackSession.commitCollectionBrowse(
                preparation: preparation
            )
            guard case .resolved(let resolvedPagePosition) = resolution else {
                self.rejectCollectionBrowserOperation(
                    browserViewController: browserViewController,
                    generation: generation,
                    completion: completion
                )
                return
            }

            assert(resolvedPagePosition == expectedPagePosition)
            assert(
                self.playbackSession.collectionBrowseSnapshot() == preparation.snapshot
            )
            browserViewController.commitPreparedDisplay(preparation)
            self.commitCollectionBrowserPresentation(performsPop: true)
            self.finishOperation(generation)
            completion?(true)
        }
    }

    private func rejectCollectionBrowserOperation(
        browserViewController: MobilePlayerBrowserPageViewController,
        generation: UInt,
        completion: (@MainActor (Bool) -> Void)?
    ) {
        browserViewController.cancelPendingDisplayPreparation()
        unstageBrowserViewIfNeeded()
        finishOperation(generation)
        completion?(false)
    }

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
           !playbackSession.canRender(
            pagePosition: targetPagePosition
           ) {
            completion?(false)
            return
        }

        browserViewController.flushSettledPosition()
        let destination = targetPagePosition
            ?? browserViewController.currentPagePosition
            ?? pagerProvider.pagerCurrentPagePosition()

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

            self.updatePlayerNavigationTitle(for: destination)
            self.browserViewController?.setBrowserActive(false)
            self.activeMode = .onePerPage
            self.unstagePagerViewIfNeeded()
            navigationController.pushViewController(self.pagerViewController, animated: false)
            self.playbackSession.acknowledgeIntentionalViewingPosition()
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

    func noteNavigationWillShow(_ viewController: UIViewController) {
        reconcileBrowserPresentationIfNeeded(shownViewController: viewController)
    }

    func noteNavigationDidShow(_ viewController: UIViewController) {
        reconcileBrowserPresentationIfNeeded(shownViewController: viewController)
    }

    private func reconcileBrowserPresentationIfNeeded(
        shownViewController: UIViewController
    ) {
        guard let browserViewController,
              shownViewController === browserViewController,
              activeMode == .onePerPage else {
            return
        }

        playbackSession.acknowledgeIntentionalViewingPosition()
        supersedeActiveOperation()
        let sourcePagePosition = chrome.pagerProvider?.pagerCurrentPagePosition()
        commitCollectionBrowserPresentation(performsPop: false)

        guard let sourcePagePosition,
              let preparation = playbackSession.prepareCollectionBrowse(
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

            _ = self.playbackSession.commitCollectionBrowse(
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

    private func updatePlayerNavigationTitle(
        for pagePosition: PlayerPagePosition
    ) {
        let token = playbackSession.getToken(
            pagePosition: pagePosition
        )
        chrome.setPlayerNavigationTitle(
            collectionTitle: token.collectionName,
            pageLabel: playbackSession.pageLabel(
                pagePosition: pagePosition
            ) ?? ""
        )
    }

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
        playbackSession.layoutInteractionState(
            displayMode: activeMode,
            pagePosition: getCurrentPagePosition(),
            collectionBrowserAvailable: browserViewController != nil
        )
    }

}

extension MobilePlayerSessionModeController: MobilePlaybackSessionDisplay {

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
            ?? playbackSession.startPagePosition()
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
