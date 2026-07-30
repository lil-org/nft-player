// ∅ 2026 lil org

import Cocoa

/// Switches between the collection browser and the one-per-page pager, drawing the
/// hero card zoom on the canvas instead of animating the view controllers.
final class MacPlayerModeController: MacPlayerMinimizeHandling {

    private enum MinimizeState {
        case interactive
        case committing
        case cancelling
    }

    private enum Phase {
        case idle
        case resettingZoom
        case expanding
        case minimizing(
            from: CGRect,
            to: CGRect,
            targetTokenIndex: Int,
            state: MinimizeState
        )
    }

    private let model: MacNavigationModel
    private let session: MacPlayerSession
    private weak var container: MacNavigationContainerViewController?
    private weak var browserViewController: MacCollectionBrowserViewController?
    private weak var pagerViewController: MacPlayerPagerViewController?
    private weak var canvas: MacPlayerCardTransitionCanvas?

    private var phase = Phase.idle
    private var hiddenBrowserTokenIndex: Int?
    private var pendingCleanup: DispatchWorkItem?
    private var pendingCleanupId: UUID?
    private var isPagerHiddenForTransition = false
    private var transitionGeneration: UInt = 0

    init(
        model: MacNavigationModel,
        session: MacPlayerSession,
        container: MacNavigationContainerViewController,
        browserViewController: MacCollectionBrowserViewController,
        pagerViewController: MacPlayerPagerViewController,
        canvas: MacPlayerCardTransitionCanvas
    ) {
        self.model = model
        self.session = session
        self.container = container
        self.browserViewController = browserViewController
        self.pagerViewController = pagerViewController
        self.canvas = canvas
    }

    private var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    var isTransitionInFlight: Bool {
        !isIdle
    }

    private var ownsActiveSession: Bool {
        model.session?.id == session.id
    }

    /// Retires the previous transition's deferred cleanup before a new one arms the
    /// shared canvas, so a stale block can never hide the canvas mid-flight or leave
    /// the wrong cell hidden.
    private func flushPendingCleanup() {
        guard let pendingCleanup else { return }
        self.pendingCleanup = nil
        pendingCleanupId = nil
        pendingCleanup.cancel()
        canvas?.end()
        unhideBrowserCell()
        restorePagerVisibility()
    }

    private func restorePagerVisibility() {
        guard isPagerHiddenForTransition else { return }
        isPagerHiddenForTransition = false
        pagerViewController?.view.alphaValue = 1
        pagerViewController?.setModeTransitionAccessibilityHidden(false)
    }

    private func unhideBrowserCell() {
        guard let hiddenBrowserTokenIndex else { return }
        self.hiddenBrowserTokenIndex = nil
        browserViewController?.setItemHidden(false, tokenIndex: hiddenBrowserTokenIndex)
    }

    // MARK: - Browser → item

    func expand(_ snapshot: MacPlayerBrowserItemSnapshot) {
        guard ownsActiveSession,
              isIdle,
              let container,
              let canvas,
              let browserViewController,
              let pagerViewController else {
            return
        }

        container.stageBehindCurrentChild(pagerViewController)
        guard pagerViewController.anchor(toTokenIndex: snapshot.tokenIndex) else {
            container.unstage(pagerViewController)
            return
        }

        flushPendingCleanup()
        canvas.setBackdropColor(MacPlayerBackgroundColor.color(forCollectionId: session.collectionId))

        guard let image = snapshot.image else {
            // Nothing decoded to fly up yet — just switch, the way iOS falls back.
            showOnePerPageNow()
            return
        }

        let collapsedFrame = canvas.convert(snapshot.frameInWindow, from: nil)
        let expandedFrame = MacPlayerCardGeometry.expandedFrame(
            for: image.size,
            in: canvas.bounds,
            usesNativeMetalCardPresentation: snapshot.usesNativeMetalCardCornerMask
        )
        guard collapsedFrame.width > 1, collapsedFrame.height > 1 else {
            showOnePerPageNow()
            return
        }

        transitionGeneration &+= 1
        let transitionGeneration = self.transitionGeneration
        phase = .expanding
        hiddenBrowserTokenIndex = snapshot.tokenIndex
        browserViewController.setItemHidden(true, tokenIndex: snapshot.tokenIndex)
        canvas.begin(
            image: image,
            usesNativeMetalCardCornerMask: snapshot.usesNativeMetalCardCornerMask,
            cardFrame: collapsedFrame,
            backdropAlpha: 0
        )
        container.bringCardTransitionCanvasToFront()

        canvas.animate(
            toCardFrame: expandedFrame,
            backdropAlpha: 1,
            duration: MacPlayerCardTransitionCanvas.expandDuration
        ) { [weak self] in
            guard let self else { return }
            guard self.transitionGeneration == transitionGeneration,
                  case .expanding = self.phase else {
                return
            }
            guard self.ownsActiveSession else {
                self.cancelTransitionForSessionChange()
                return
            }
            self.showOnePerPageNow()
            guard self.transitionGeneration == transitionGeneration,
                  case .expanding = self.phase else {
                return
            }
            self.finishTransition()
        }
    }

    // MARK: - Item → browser

    /// Gates the trackpad gestures. A zoomed page must not minimize on a pinch —
    /// that pinch is a zoom.
    var canMinimize: Bool {
        canMinimizeFromChrome && pagerViewController?.isCurrentPageZoomed == false
    }

    /// Gates the toolbar back button, Cmd+[ and Esc, which should always run the hero.
    /// A zoomed page is un-zoomed first; see `minimizeImmediately()`.
    var canMinimizeFromChrome: Bool {
        ownsActiveSession
            && isIdle
            && session.supportsCollectionBrowser
            && model.route.displayMode == .onePerPage
            && pagerViewController?.isPageTransitionInFlight == false
    }

    @discardableResult
    func beginMinimize() -> Bool {
        guard canMinimize,
              let container,
              let canvas,
              let browserViewController,
              let pagerViewController,
              let sourceTokenIndex = pagerViewController.currentTokenIndex,
              let targetTokenIndex = session.collectionBrowserTokenIndex else {
            return false
        }

        flushPendingCleanup()
        canvas.setBackdropColor(MacPlayerBackgroundColor.color(forCollectionId: session.collectionId))

        // The browser is off-stack, so put its view back under the pager and lay it
        // out before asking it where the destination cell is.
        container.stageBehindCurrentChild(browserViewController)
        browserViewController.scroll(toTokenIndex: targetTokenIndex, animated: false)
        browserViewController.view.layoutSubtreeIfNeeded()
        browserViewController.prepareForIncomingTransition()

        guard let destinationFrameInWindow = browserViewController.itemFrameInWindow(
            tokenIndex: targetTokenIndex
        ),
              let sourceFrameInWindow = pagerViewController.currentMediaFrameInWindow() else {
            container.unstage(browserViewController)
            return false
        }

        // The decoded primary image is exactly what the pager is drawing, and unlike a
        // view snapshot it also works for web and video pages the moment they cache.
        let image = decodedPrimaryImage(tokenIndex: sourceTokenIndex)
            ?? browserViewController.thumbnailImage(tokenIndex: sourceTokenIndex)
            ?? pagerViewController.snapshotOfCurrentMedia()
        guard let image else {
            container.unstage(browserViewController)
            return false
        }

        let sourceFrame = canvas.convert(sourceFrameInWindow, from: nil)
        let destinationFrame = canvas.convert(destinationFrameInWindow, from: nil)
        transitionGeneration &+= 1
        phase = .minimizing(
            from: sourceFrame,
            to: destinationFrame,
            targetTokenIndex: targetTokenIndex,
            state: .interactive
        )
        hiddenBrowserTokenIndex = targetTokenIndex
        browserViewController.setItemHidden(true, tokenIndex: targetTokenIndex)
        // Hide the live page for the flight, the way iOS does, so what the shrinking
        // card uncovers is the thumbnail wall rather than the page it came from.
        // alphaValue, not isHidden: hiding a subtree with a WKWebView or video layer
        // invites occlusion throttling on content that must resume instantly on cancel.
        isPagerHiddenForTransition = true
        pagerViewController.setModeTransitionAccessibilityHidden(true)
        pagerViewController.view.alphaValue = 0
        canvas.begin(
            image: image,
            usesNativeMetalCardCornerMask: browserViewController.usesNativeMetalCardCornerMask(
                tokenIndex: targetTokenIndex
            ),
            cardFrame: sourceFrame,
            backdropAlpha: 1
        )
        container.bringCardTransitionCanvasToFront()
        return true
    }

    func updateMinimize(progress: CGFloat) {
        guard case let .minimizing(from, to, _, .interactive) = phase else { return }
        guard ownsActiveSession else {
            cancelTransitionForSessionChange()
            return
        }
        guard let canvas else { return }
        let eased = MacPlayerCardGeometry.easeOutQuadratic(progress)
        canvas.setCardFrame(MacPlayerCardGeometry.interpolate(from: from, to: to, progress: eased))
        canvas.setBackdropAlpha(1 - eased)
    }

    func endMinimize(commit: Bool) {
        guard case let .minimizing(from, to, targetTokenIndex, .interactive) = phase else {
            return
        }
        guard ownsActiveSession else {
            cancelTransitionForSessionChange()
            return
        }
        guard let canvas else { return }

        if commit {
            phase = .minimizing(
                from: from,
                to: to,
                targetTokenIndex: targetTokenIndex,
                state: .committing
            )
            let transitionGeneration = self.transitionGeneration
            canvas.animate(
                toCardFrame: to,
                backdropAlpha: 0,
                duration: MacPlayerCardTransitionCanvas.minimizeDuration
            ) { [weak self] in
                guard let self else { return }
                guard self.transitionGeneration == transitionGeneration,
                      case .minimizing(_, _, _, .committing) = self.phase else {
                    return
                }
                guard self.ownsActiveSession else {
                    self.cancelTransitionForSessionChange()
                    return
                }
                self.showCollectionBrowserNow(targetTokenIndex: targetTokenIndex)
                guard self.transitionGeneration == transitionGeneration,
                      case .minimizing(_, _, _, .committing) = self.phase else {
                    return
                }
                self.finishTransition()
            }
        } else {
            phase = .minimizing(
                from: from,
                to: to,
                targetTokenIndex: targetTokenIndex,
                state: .cancelling
            )
            let transitionGeneration = self.transitionGeneration
            canvas.animate(
                toCardFrame: from,
                backdropAlpha: 1,
                duration: MacPlayerCardTransitionCanvas.cancelDuration
            ) { [weak self] in
                guard let self else { return }
                guard self.transitionGeneration == transitionGeneration,
                      case .minimizing(_, _, _, .cancelling) = self.phase else {
                    return
                }
                guard self.ownsActiveSession else {
                    self.cancelTransitionForSessionChange()
                    return
                }
                self.container?.unstageStagedChild()
                guard self.transitionGeneration == transitionGeneration,
                      case .minimizing(_, _, _, .cancelling) = self.phase else {
                    return
                }
                self.finishTransition()
            }
        }
    }

    func minimizeImmediately() {
        guard canMinimizeFromChrome else { return }

        // While zoomed, the media rect extends well outside the window, so the hero
        // would fly from an enormous off-screen card. Settle back to fit first.
        guard let pagerViewController, pagerViewController.isCurrentPageZoomed else {
            runImmediateMinimize()
            return
        }
        phase = .resettingZoom
        pagerViewController.resetZoom { [weak self] in
            guard let self, case .resettingZoom = self.phase else { return }
            guard self.ownsActiveSession else {
                self.cancelTransitionForSessionChange()
                return
            }
            self.phase = .idle
            self.runImmediateMinimize()
        }
    }

    private func runImmediateMinimize() {
        guard ownsActiveSession else {
            cancelTransitionForSessionChange()
            return
        }
        let targetTokenIndex = session.collectionBrowserTokenIndex
        guard beginMinimize() else {
            if let targetTokenIndex {
                container?.prepareCollectionBrowserHandoff(toTokenIndex: targetTokenIndex)
            }
            model.showCollectionBrowser(transition: .slide)
            return
        }
        endMinimize(commit: true)
    }

    /// Swap the container synchronously rather than waiting for SwiftUI to push the
    /// route change through, so the canvas never lifts before the new screen is up.
    private func showOnePerPageNow() {
        guard ownsActiveSession else {
            cancelTransitionForSessionChange()
            return
        }
        model.showOnePerPage(transition: .none)
        applyRouteNow()
    }

    private func showCollectionBrowserNow(targetTokenIndex: Int) {
        guard ownsActiveSession else {
            cancelTransitionForSessionChange()
            return
        }
        container?.prepareCollectionBrowserHandoff(toTokenIndex: targetTokenIndex)
        model.showCollectionBrowser(transition: .none)
        applyRouteNow()
    }

    private func applyRouteNow() {
        container?.apply(route: model.route, transition: model.routeTransition)
    }

    private func decodedPrimaryImage(tokenIndex: Int) -> NSImage? {
        guard let descriptor = CollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: session.collectionId,
            tokenIndex: tokenIndex
        ), descriptor.isStaticImage else {
            return nil
        }
        return DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor)
    }

    func containerBoundsDidChange() {
        guard ownsActiveSession else {
            cancelTransitionForSessionChange()
            return
        }

        switch phase {
        case .idle:
            if pendingCleanup != nil {
                finishTransitionImmediately()
            }
            return
        case .resettingZoom:
            return
        case .expanding:
            transitionGeneration &+= 1
            canvas?.cancelAnimations()
            phase = .idle
            showOnePerPageNow()
            pagerViewController?.view.layoutSubtreeIfNeeded()
            finishTransitionImmediately()
        case let .minimizing(_, _, targetTokenIndex, state):
            transitionGeneration &+= 1
            canvas?.cancelAnimations()
            phase = .idle
            pagerViewController?.resetMinimizeGestureState()
            switch state {
            case .committing:
                showCollectionBrowserNow(targetTokenIndex: targetTokenIndex)
                browserViewController?.view.layoutSubtreeIfNeeded()
            case .interactive, .cancelling:
                container?.unstageStagedChild()
                pagerViewController?.view.layoutSubtreeIfNeeded()
            }
            finishTransitionImmediately()
        }
    }

    // MARK: - Cleanup

    func prepareForSessionTeardown() {
        cancelTransitionForSessionChange()
    }

    private func cancelTransitionForSessionChange() {
        transitionGeneration &+= 1
        phase = .idle
        container?.unstageStagedChild()
        finishTransitionImmediately()
    }

    private func finishTransitionImmediately() {
        pendingCleanup?.cancel()
        pendingCleanup = nil
        pendingCleanupId = nil
        unhideBrowserCell()
        restorePagerVisibility()
        canvas?.end()
    }

    private func finishTransition() {
        phase = .idle
        pendingCleanup?.cancel()
        pendingCleanup = nil
        pendingCleanupId = nil
        // Give the newly installed screen a beat to draw before lifting the card.
        // Cancellable and bound to this transition, so a new transition starting
        // inside the window cannot be torn down by it.
        let cleanupId = UUID()
        let cleanup = DispatchWorkItem { [weak self] in
            guard let self, self.pendingCleanupId == cleanupId else { return }
            self.pendingCleanup = nil
            self.pendingCleanupId = nil
            self.canvas?.end()
            self.unhideBrowserCell()
            // On commit the pager is off-stage by now, so this just resets it for the
            // next expand; on cancel the backdrop is opaque again, so the page comes
            // back under cover and is revealed as the canvas hides.
            self.restorePagerVisibility()
        }
        pendingCleanup = cleanup
        pendingCleanupId = cleanupId
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cleanupDelay, execute: cleanup)
    }

    private static let cleanupDelay: TimeInterval = 0.05

}
