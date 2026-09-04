import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobilePlayerInteractionCoordinatorTests: XCTestCase {}

private actor PlayerInteractionTestViewingTracker:
    MobilePlaybackViewingSessionTracking {

    func prepareRestartUpdate(
        collectionId: String?
    ) async -> PlayerContinueViewingUpdate? {
        nil
    }

    func beginRestart(update: PlayerContinueViewingUpdate?) async {}

    func markViewed(_ progress: MobileViewingProgress) async {}
}

@MainActor
private final class PlayerInteractionDismissRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private final class PlayerInteractionDisconnectFlushDisplay:
    MobilePlaybackSessionDisplay {

    private let onFlush: () -> Void

    init(onFlush: @escaping () -> Void) {
        self.onFlush = onFlush
    }

    func navigate(_ direction: PlaybackNavigationDirection) {}

    func getCurrentPagePosition() -> PlayerPagePosition {
        .initial
    }

    func flushPendingViewingProgress() {
        onFlush()
    }
}

@MainActor
private final class PlayerInteractionTestFixture {
    let registry: MobilePlaybackSessionRegistry
    let playbackSession: MobilePlaybackSession
    let chrome: MobilePlayerChromeController
    let rootViewController: UIViewController
    let playerViewController: MobilePlayerHostingController
    let browserViewController: MobilePlayerBrowserPageViewController
    let navigationController: PlayerNavigationController
    let modeController: MobilePlayerSessionModeController
    let dismissRecorder = PlayerInteractionDismissRecorder()
    let window: UIWindow
    var interactionController: PlayerInteractionController?

    init(
        displayMode: MobilePlayerDisplayMode,
        config: MobilePlayerConfig = MobilePlayerConfig(),
        tokenProvider:
            (@MainActor (PlayerPagePosition) -> GeneratedToken)? = nil,
        externalDisplayTokenUpdater:
            (@MainActor (GeneratedToken) -> Void)? = nil,
        windowScene: UIWindowScene? = nil,
        installDownloadableMediaWindow: @escaping @MainActor (
            PlayerDownloadableMediaWindow,
            UUID
        ) -> Void = {
            DownloadableMediaCache.shared.prepareWindow($0, ownerId: $1)
        }
    ) {
        let registry = MobilePlaybackSessionRegistry(
            dependencies: .init(
                makeViewingSessionTracker: { _ in
                    PlayerInteractionTestViewingTracker()
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {},
                installDownloadableMediaWindow:
                    installDownloadableMediaWindow
            )
        )
        let playbackSession = registry.startSession(
            config: config
        )
        let chrome = MobilePlayerChromeController(
            playerBackgroundColor: .red,
            allowsNavigationBackSwipe: displayMode == .collectionBrowser
        )
        let rootViewController = UIViewController()
        let navigationController = PlayerNavigationController(
            rootViewController: rootViewController
        )
        let playerViewController = MobilePlayerHostingController(
            rootView: MobilePlayerView(
                playbackSession: playbackSession,
                onDismiss: {},
                chrome: chrome
            )
        )
        playerViewController.installNavigationTitle(chrome: chrome)
        let browserViewController = MobilePlayerBrowserPageViewController(
            playbackSession: playbackSession,
            chrome: chrome,
            tokenProvider: tokenProvider,
            externalDisplayTokenUpdater: externalDisplayTokenUpdater
        )
        let modeController = MobilePlayerSessionModeController(
            playbackSession: playbackSession,
            chrome: chrome,
            navigationController: navigationController,
            browserViewController: browserViewController,
            pagerViewController: playerViewController,
            initialMode: displayMode
        )
        browserViewController.modeController = modeController

        let viewControllers: [UIViewController]
        switch displayMode {
        case .onePerPage:
            viewControllers = [
                rootViewController,
                browserViewController,
                playerViewController,
            ]
        case .collectionBrowser:
            viewControllers = [rootViewController, browserViewController]
        }
        navigationController.setViewControllers(
            viewControllers,
            animated: false
        )

        let window = windowScene.map(UIWindow.init(windowScene:))
            ?? UIWindow(frame: .zero)
        window.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.view.frame = window.bounds
        navigationController.view.layoutIfNeeded()
        playerViewController.loadViewIfNeeded()
        playerViewController.view.frame = navigationController.view.bounds
        playerViewController.view.layoutIfNeeded()
        browserViewController.loadViewIfNeeded()
        browserViewController.view.frame = navigationController.view.bounds
        browserViewController.view.layoutIfNeeded()

        self.registry = registry
        self.playbackSession = playbackSession
        self.chrome = chrome
        self.rootViewController = rootViewController
        self.playerViewController = playerViewController
        self.browserViewController = browserViewController
        self.navigationController = navigationController
        self.modeController = modeController
        self.window = window
        interactionController = PlayerInteractionController(
            navigationController: navigationController,
            playerViewController: playerViewController,
            browserViewController: browserViewController,
            modeController: modeController,
            chrome: chrome,
            onDismiss: { [dismissRecorder] in
                dismissRecorder.record()
            }
        )
    }

    func tearDown() {
        playbackSession.stopAndDisconnect()
        interactionController?.invalidate()
        modeController.invalidate()
        interactionController = nil
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
extension MobilePlayerInteractionCoordinatorTests {

    func testBrowserFocusDefersTokenAndExternalDisplayUntilSettle() throws {
        let item = try XCTUnwrap(
            SuggestedItemsService.visibleItems.first {
                let itemCount = CollectionCatalog.tokenCount(
                    specificCollectionId: $0.id
                )
                return itemCount >= 4
                    && itemCount <= 512
                    && !$0.name.isEmpty
                    && PlayerCollectionBrowserSupport.isAvailable(
                        forCollectionId: $0.id
                    )
                    && CollectionCatalog.canGenerateToken(
                        specificCollectionId: $0.id,
                        tokenIndex: 0
                    )
            }
        )
        let itemCount = CollectionCatalog.tokenCount(
            specificCollectionId: item.id
        )
        let token = GeneratedToken(
            fullCollectionId: item.id,
            collectionName: item.name,
            address: item.address,
            id: "1",
            html: "",
            displayName: item.name,
            displayTokenId: "#1",
            url: nil
        )
        var resolvedPagePositions = [PlayerPagePosition]()
        var externalDisplayTokens = [GeneratedToken]()
        let fixture = PlayerInteractionTestFixture(
            displayMode: .collectionBrowser,
            config: MobilePlayerConfig(
                initialItemId: item.id,
                initialTokenIndex: 2
            ),
            tokenProvider: {
                resolvedPagePositions.append($0)
                return token
            },
            externalDisplayTokenUpdater: {
                externalDisplayTokens.append($0)
            }
        )
        defer { fixture.tearDown() }
        let contentViewController = try XCTUnwrap(
            fixture.browserViewController.children.first
                as? VerticalCollectionBrowserViewController
        )
        fixture.chrome.setPlayerNavigationTitle(
            collectionTitle: token.collectionName,
            pageLabel: ""
        )
        resolvedPagePositions.removeAll()
        externalDisplayTokens.removeAll()

        let backwardPosition = PlayerPagePosition(position: -1)
        contentViewController.onFocusedPagePosition?(backwardPosition)

        XCTAssertEqual(
            fixture.chrome.playerNavigationTitleController.title,
            MobilePlayerNavigationTitleState(
                collectionTitle: token.collectionName,
                pageLabel: Strings.pagePosition(
                    current: 2,
                    total: itemCount
                )
            )
        )
        let forwardPosition = PlayerPagePosition(position: 1)
        contentViewController.onFocusedPagePosition?(forwardPosition)
        XCTAssertEqual(
            fixture.chrome.playerNavigationTitleController.title,
            MobilePlayerNavigationTitleState(
                collectionTitle: token.collectionName,
                pageLabel: Strings.pagePosition(
                    current: 4,
                    total: itemCount
                )
            )
        )
        XCTAssertTrue(resolvedPagePositions.isEmpty)
        XCTAssertTrue(externalDisplayTokens.isEmpty)

        XCTAssertEqual(
            contentViewController.onSettledPagePosition?(
                forwardPosition,
                false
            ),
            true
        )
        XCTAssertEqual(resolvedPagePositions, [forwardPosition])
        XCTAssertEqual(externalDisplayTokens, [token])
    }

    func testDisconnectFlushDoesNotUpdateExternalDisplay() throws {
        let token = GeneratedToken(
            fullCollectionId: "collection",
            collectionName: "Collection",
            address: "",
            id: "1",
            html: "",
            displayName: "Collection #1",
            displayTokenId: "#1",
            url: nil
        )
        var resolvedPagePositions = [PlayerPagePosition]()
        var externalDisplayTokens = [GeneratedToken]()
        let fixture = PlayerInteractionTestFixture(
            displayMode: .collectionBrowser,
            tokenProvider: {
                resolvedPagePositions.append($0)
                return token
            },
            externalDisplayTokenUpdater: {
                externalDisplayTokens.append($0)
            }
        )
        defer { fixture.tearDown() }
        let contentViewController = try XCTUnwrap(
            fixture.browserViewController.children.first
                as? VerticalCollectionBrowserViewController
        )
        resolvedPagePositions.removeAll()
        externalDisplayTokens.removeAll()
        let display = PlayerInteractionDisconnectFlushDisplay {
            _ = contentViewController.onSettledPagePosition?(.initial, false)
        }
        fixture.playbackSession.attach(display: display)

        fixture.playbackSession.stopAndDisconnect()

        XCTAssertEqual(resolvedPagePositions, [.initial])
        XCTAssertTrue(externalDisplayTokens.isEmpty)
    }

    func testWidgetReconciliationPreparesPostCommitThumbnailWindow()
        async throws {
        let item = try XCTUnwrap(
            SuggestedItemsService.visibleItems.first { item in
                let count = CollectionCatalog.tokenCount(
                    specificCollectionId: item.id
                )
                return count > 3
                    && PlayerCollectionBrowserSupport.isAvailable(
                        forCollectionId: item.id
                    )
                    && MobileCollectionCatalog.downloadableMediaDescriptor(
                        specificCollectionId: item.id,
                        tokenIndex: 2
                    ) != nil
                    && MobileCollectionCatalog.collectionBrowseImageSources(
                        specificCollectionId: item.id,
                        tokenIndex: 2
                    ) != nil
            }
        )
        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: item.id
        )
        let anchorTokenIndex = 2
        let insertedTokenIndex = 3
        let insertion = PlayerWidgetTokenInsertion(
            insertedToken: GeneratedToken(
                fullCollectionId: item.id,
                collectionName: item.name,
                address: item.address,
                id: "widget-token",
                html: "",
                displayName: "Widget token",
                displayTokenId: "widget-token",
                url: nil
            ),
            insertedTokenIndex: insertedTokenIndex,
            anchorProgress: PlayerViewingProgress(
                collectionId: item.id,
                collectionName: item.name,
                tokenId: "anchor-token",
                tokenIndex: anchorTokenIndex,
                tokenCount: tokenCount,
                updatedAt: .distantPast
            ),
            isAnchorProgressResolved: true
        )
        let foregroundScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        var installedWindows = [PlayerDownloadableMediaWindow]()
        let fixture = PlayerInteractionTestFixture(
            displayMode: .onePerPage,
            config: MobilePlayerConfig(
                initialItemId: item.id,
                widgetTokenInsertion: insertion
            ),
            windowScene: foregroundScene,
            installDownloadableMediaWindow: { window, _ in
                installedWindows.append(window)
            }
        )
        defer { fixture.tearDown() }
        XCTAssertNil(fixture.playbackSession.collectionBrowseSnapshot())
        let initialWindowCount = installedWindows.count

        fixture.navigationController.setViewControllers(
            [fixture.rootViewController, fixture.browserViewController],
            animated: false
        )
        fixture.navigationController.view.layoutIfNeeded()
        fixture.modeController.noteNavigationDidShow(
            fixture.browserViewController
        )
        XCTAssertEqual(
            fixture.playbackSession.collectionBrowseSnapshot()?.collectionId,
            item.id
        )

        let didInstallPostCommitWindow = await waitUntil(timeout: 2) {
            fixture.playbackSession.collectionBrowseSnapshot()?.collectionId
                == item.id
                && installedWindows.dropFirst(initialWindowCount).contains {
                    $0.currentDescriptor.collectionId == item.id
                        && $0.currentDescriptor.tokenIndex == anchorTokenIndex
                }
        }
        XCTAssertTrue(didInstallPostCommitWindow)
        XCTAssertEqual(fixture.modeController.activeMode, .collectionBrowser)
        XCTAssertEqual(
            fixture.navigationController.viewControllers,
            [fixture.rootViewController, fixture.browserViewController]
        )

        let reconciledWindowCount = installedWindows.count
        fixture.modeController.noteNavigationDidShow(
            fixture.browserViewController
        )
        await waitForNextMainQueueTurn()

        XCTAssertEqual(installedWindows.count, reconciledWindowCount)
    }

    private func gestureIdentifiers(in view: UIView) -> Set<ObjectIdentifier> {
        Set((view.gestureRecognizers ?? []).map(ObjectIdentifier.init))
    }

    private func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), deadline.timeIntervalSinceNow > 0 {
            await waitForNextMainQueueTurn()
        }
        return condition()
    }

    private func makeSelection(
        hasLoadedImage: Bool
    ) -> MobilePlayerBrowserTransitionSelection {
        MobilePlayerBrowserTransitionSelection(
            selectedSnapshot: MobilePlayerBrowserItemSnapshot(
                tokenIndex: 0,
                pagePosition: .initial,
                descriptor: nil,
                fallbackImageSize: CGSize(width: 120, height: 120),
                hasLoadedImage: hasLoadedImage,
                frameInWindow: CGRect(x: 20, y: 120, width: 120, height: 120),
                snapshotView: UIView(frame: CGRect(
                    x: 0,
                    y: 0,
                    width: 120,
                    height: 120
                ))
            ),
            visibleNeighborSnapshots: []
        )
    }

    func testUninstalledControllerHasNoSideEffectsAndDeallocates() async throws {
        let fixture = PlayerInteractionTestFixture(displayMode: .onePerPage)
        defer { fixture.tearDown() }
        weak var weakController: PlayerInteractionController?

        do {
            let controller = try XCTUnwrap(fixture.interactionController)
            weakController = controller
            XCTAssertNil(
                fixture.navigationController.canEnforceNavigationBarChromeVisibility
            )
            XCTAssertNil(fixture.chrome.onCollectionBrowserExpandRequest)
            XCTAssertNil(fixture.navigationController.cardTransitionOverlayView)
            XCTAssertNil(fixture.playerViewController.onAccessibilityEscape)
            XCTAssertNil(fixture.playerViewController.onPlayerLayout)
            XCTAssertNil(fixture.browserViewController.onAccessibilityEscape)
            XCTAssertNil(fixture.browserViewController.onPlayerLayout)

            fixture.browserViewController.setPlayerPageBackground(color: .orange)
            fixture.chrome.setPlayerBackgroundColor(.green)
            await Task.yield()
            await waitForNextMainQueueTurn()

            XCTAssertTrue(
                fixture.browserViewController.view.backgroundColor?
                    .isVisuallyEqual(to: .orange) == true
            )

            controller.invalidate()
            fixture.interactionController = nil
        }

        XCTAssertNil(weakController)
    }

    func testInstallAndInvalidateAreIdempotentAndCleanUp() throws {
        let fixture = PlayerInteractionTestFixture(displayMode: .onePerPage)
        defer { fixture.tearDown() }
        let controller = try XCTUnwrap(fixture.interactionController)
        let playerGestureIdentifiersBeforeInstall = gestureIdentifiers(
            in: fixture.playerViewController.view
        )
        let navigationBarGestureIdentifiersBeforeInstall = gestureIdentifiers(
            in: fixture.navigationController.navigationBar
        )

        controller.install()

        let installedPlayerGestures = (
            fixture.playerViewController.view.gestureRecognizers ?? []
        ).filter {
            !playerGestureIdentifiersBeforeInstall.contains(ObjectIdentifier($0))
        }
        let installedNavigationBarGestures = (
            fixture.navigationController.navigationBar.gestureRecognizers ?? []
        ).filter {
            !navigationBarGestureIdentifiersBeforeInstall.contains(
                ObjectIdentifier($0)
            )
        }
        let installedPlayerGestureIdentifiers = Set(
            installedPlayerGestures.map(ObjectIdentifier.init)
        )
        let installedNavigationBarGestureIdentifiers = Set(
            installedNavigationBarGestures.map(ObjectIdentifier.init)
        )
        let canvasView = try XCTUnwrap(
            fixture.navigationController.cardTransitionOverlayView
        )

        XCTAssertEqual(installedPlayerGestures.count, 4)
        XCTAssertEqual(installedNavigationBarGestures.count, 1)
        XCTAssertTrue(installedPlayerGestures.allSatisfy {
            $0.delegate === controller
        })
        XCTAssertTrue(installedNavigationBarGestures.allSatisfy {
            $0.delegate === controller
        })
        XCTAssertTrue(canvasView.superview === fixture.navigationController.view)
        XCTAssertNotNil(fixture.playerViewController.onAccessibilityEscape)
        XCTAssertNotNil(fixture.playerViewController.onPlayerLayout)
        XCTAssertNotNil(fixture.browserViewController.onAccessibilityEscape)
        XCTAssertNotNil(fixture.browserViewController.onPlayerLayout)

        controller.install()

        XCTAssertEqual(
            gestureIdentifiers(in: fixture.playerViewController.view)
                .subtracting(playerGestureIdentifiersBeforeInstall),
            installedPlayerGestureIdentifiers
        )
        XCTAssertEqual(
            gestureIdentifiers(in: fixture.navigationController.navigationBar)
                .subtracting(navigationBarGestureIdentifiersBeforeInstall),
            installedNavigationBarGestureIdentifiers
        )
        XCTAssertTrue(
            fixture.navigationController.cardTransitionOverlayView === canvasView
        )

        controller.invalidate()
        controller.invalidate()

        XCTAssertTrue(
            gestureIdentifiers(in: fixture.playerViewController.view)
                .isDisjoint(with: installedPlayerGestureIdentifiers)
        )
        XCTAssertTrue(
            gestureIdentifiers(in: fixture.navigationController.navigationBar)
                .isDisjoint(with: installedNavigationBarGestureIdentifiers)
        )
        XCTAssertNil(fixture.navigationController.cardTransitionOverlayView)
        XCTAssertNil(canvasView.superview)
        XCTAssertTrue(canvasView.subviews.isEmpty)
        XCTAssertNil(fixture.playerViewController.onAccessibilityEscape)
        XCTAssertNil(fixture.playerViewController.onPlayerLayout)
        XCTAssertNil(fixture.browserViewController.onAccessibilityEscape)
        XCTAssertNil(fixture.browserViewController.onPlayerLayout)
        XCTAssertNil(
            fixture.navigationController.canEnforceNavigationBarChromeVisibility
        )

    }

    func testInvalidatedFacadeDeallocates() throws {
        let fixture = PlayerInteractionTestFixture(displayMode: .onePerPage)
        defer { fixture.tearDown() }
        weak var weakController: PlayerInteractionController?

        do {
            let controller = try XCTUnwrap(fixture.interactionController)
            controller.install()
            controller.invalidate()
            weakController = controller
            fixture.interactionController = nil
        }

        XCTAssertNil(weakController)
    }

    func testReinstallRestoresChromeStateAndObservations() async throws {
        let fixture = PlayerInteractionTestFixture(displayMode: .onePerPage)
        defer { fixture.tearDown() }
        let controller = try XCTUnwrap(fixture.interactionController)
        let didFinishInitialNavigationTransition = await waitUntil {
            fixture.navigationController.transitionCoordinator == nil
        }
        XCTAssertTrue(didFinishInitialNavigationTransition)
        controller.install()

        let installedPlayerGestures = gestureIdentifiers(
            in: fixture.playerViewController.view
        )
        let installedNavigationBarGestures = gestureIdentifiers(
            in: fixture.navigationController.navigationBar
        )
        let canvasView = try XCTUnwrap(
            fixture.navigationController.cardTransitionOverlayView
        )

        controller.invalidate()
        fixture.chrome.setPlayerBackgroundColor(.green)
        fixture.chrome.setControlsVisible(false)

        controller.install()
        controller.install()

        XCTAssertEqual(
            gestureIdentifiers(in: fixture.playerViewController.view),
            installedPlayerGestures
        )
        XCTAssertEqual(
            gestureIdentifiers(in: fixture.navigationController.navigationBar),
            installedNavigationBarGestures
        )
        XCTAssertTrue(
            fixture.navigationController.cardTransitionOverlayView === canvasView
        )
        XCTAssertTrue(canvasView.superview === fixture.navigationController.view)
        XCTAssertTrue(canvasView.backgroundColor?.isVisuallyEqual(to: .green) == true)
        XCTAssertEqual(fixture.navigationController.navigationBar.alpha, 0)
        XCTAssertEqual(
            fixture.navigationController.canEnforceNavigationBarChromeVisibility?(),
            true
        )
        XCTAssertNotNil(fixture.chrome.onCollectionBrowserExpandRequest)
        XCTAssertNotNil(fixture.playerViewController.onAccessibilityEscape)
        XCTAssertNotNil(fixture.playerViewController.onPlayerLayout)
        XCTAssertNotNil(fixture.browserViewController.onAccessibilityEscape)
        XCTAssertNotNil(fixture.browserViewController.onPlayerLayout)

        fixture.chrome.setPlayerBackgroundColor(.blue)
        fixture.chrome.setControlsVisible(true)
        let didApplyChromeChanges = await waitUntil {
            canvasView.backgroundColor?.isVisuallyEqual(to: .blue) == true
                && fixture.navigationController.navigationBar.alpha == 1
        }
        XCTAssertTrue(didApplyChromeChanges)
    }

    func testBackAndAccessibilityRoutingAndObservationTeardown() async throws {
        let fixture = PlayerInteractionTestFixture(displayMode: .onePerPage)
        defer { fixture.tearDown() }
        let layoutStateProviderID = UUID()
        fixture.chrome.setLiveLayoutInteractionStateProvider(
            id: layoutStateProviderID
        ) {
            .empty
        }
        defer {
            fixture.chrome.clearLiveLayoutInteractionStateProvider(
                id: layoutStateProviderID
            )
        }
        let controller = try XCTUnwrap(fixture.interactionController)
        controller.install()
        let canvasView = try XCTUnwrap(
            fixture.navigationController.cardTransitionOverlayView
        )

        let didFinishInitialNavigationTransition = await waitUntil {
            fixture.navigationController.transitionCoordinator == nil
        }
        XCTAssertTrue(didFinishInitialNavigationTransition)

        XCTAssertNotNil(
            fixture.playerViewController.navigationItem.leftBarButtonItem
        )
        XCTAssertNotNil(fixture.browserViewController.navigationItem.backAction)
        XCTAssertTrue(fixture.playerViewController.accessibilityPerformEscape())
        XCTAssertEqual(fixture.dismissRecorder.count, 1)

        fixture.navigationController.setViewControllers(
            [fixture.rootViewController, fixture.browserViewController],
            animated: false
        )
        controller.didShowPlayerAfterNavigationTransition()

        let didFinishBrowserNavigationTransition = await waitUntil {
            fixture.navigationController.transitionCoordinator == nil
        }
        XCTAssertTrue(didFinishBrowserNavigationTransition)

        XCTAssertTrue(fixture.browserViewController.accessibilityPerformEscape())
        XCTAssertEqual(fixture.dismissRecorder.count, 2)

        fixture.chrome.setPlayerBackgroundColor(.green)
        let didApplyBackgroundColor = await waitUntil {
            canvasView.backgroundColor?.isVisuallyEqual(to: .green) == true
        }
        XCTAssertTrue(didApplyBackgroundColor)

        controller.invalidate()
        fixture.chrome.setPlayerBackgroundColor(.blue)
        fixture.chrome.setControlsVisible(false)
        fixture.chrome.setNavigationBackSwipeAllowed(false)
        await Task.yield()
        await waitForNextMainQueueTurn()

        XCTAssertTrue(
            canvasView.backgroundColor?
                .isVisuallyEqual(to: .green) == true
        )
        XCTAssertNil(
            fixture.playerViewController.navigationItem.leftBarButtonItem
        )
        XCTAssertNil(fixture.browserViewController.navigationItem.backAction)
        XCTAssertNil(fixture.playerViewController.onAccessibilityEscape)
        XCTAssertNil(fixture.browserViewController.onAccessibilityEscape)
    }

    func testExpandFallbackZoomRejectionAndCallbackClearing() throws {
        let fixture = PlayerInteractionTestFixture(
            displayMode: .collectionBrowser
        )
        defer { fixture.tearDown() }
        let controller = try XCTUnwrap(fixture.interactionController)
        controller.install()
        let invalidSelection = makeSelection(hasLoadedImage: false)

        let invalidResult = fixture.chrome.requestCollectionBrowserExpand(
            invalidSelection
        )
        if case .fallbackToImmediateOpen = invalidResult {
        } else {
            XCTFail("An invalid expand selection should fall back")
        }
        XCTAssertNil(fixture.playerViewController.view.superview)
        XCTAssertFalse(fixture.chrome.isPlayerContentHiddenForCardTransition)
        XCTAssertTrue(
            fixture.navigationController.cardTransitionOverlayView?
                .subviews.isEmpty == true
        )

        fixture.chrome.setPlayerContentZoomed(true)
        let zoomedResult = fixture.chrome.requestCollectionBrowserExpand(
            makeSelection(hasLoadedImage: true)
        )
        if case .rejected = zoomedResult {
        } else {
            XCTFail("A zoomed player should reject card expansion")
        }

        controller.invalidate()

        XCTAssertNil(fixture.chrome.onCollectionBrowserExpandRequest)
        let resultAfterInvalidation = fixture.chrome
            .requestCollectionBrowserExpand(makeSelection(hasLoadedImage: true))
        if case .fallbackToImmediateOpen = resultAfterInvalidation {
        } else {
            XCTFail("Expand should restore its fallback after invalidation")
        }

        controller.install()

        XCTAssertNotNil(fixture.chrome.onCollectionBrowserExpandRequest)
        let resultAfterReinstall = fixture.chrome
            .requestCollectionBrowserExpand(makeSelection(hasLoadedImage: true))
        if case .rejected = resultAfterReinstall {
        } else {
            XCTFail("A reinstalled controller should reject expansion while zoomed")
        }
    }
}
