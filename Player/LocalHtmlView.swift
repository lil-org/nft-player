// ∅ 2026 lil org

import SwiftUI
import AppKit

struct LocalHtmlView: View {
    
    private var windowNumber = 0
    private weak var playerMenuDelegate: PlayerMenuDelegate?
    private let navigationBridge: MacPlayerNavigationBridge
    private let onViewAgain: () -> Void
    private let onFinish: () -> Void
    
    @ObservedObject var playerModel: PlayerModel
    
    init(
        playerModel: PlayerModel,
        windowNumber: Int,
        playerMenuDelegate: PlayerMenuDelegate,
        navigationBridge: MacPlayerNavigationBridge,
        onViewAgain: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.playerModel = playerModel
        self.windowNumber = windowNumber
        self.playerMenuDelegate = playerMenuDelegate
        self.navigationBridge = navigationBridge
        self.onViewAgain = onViewAgain
        self.onFinish = onFinish
    }
    
    var body: some View {
        let isCollectionComplete = playerModel.currentProgress?.isComplete == true
            && !playerModel.isCurrentTokenInsertedWidgetToken

        ZStack(alignment: .bottom) {
            MacPlayerPageControllerView(
                playerModel: playerModel,
                playerMenuDelegate: playerMenuDelegate,
                navigationBridge: navigationBridge
            )
                .onAppear {
                    hideCursorIfFullscreen()
                }
                .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .background(.black)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
                    if (notification.object as? NSWindow)?.windowNumber == windowNumber {
                        NSCursor.setHiddenUntilMouseMoves(true)
                    }
                }

            if isCollectionComplete {
                MacPlayerCompletionControls(
                    onViewAgain: onViewAgain,
                    onFinish: onFinish
                )
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isCollectionComplete)
    }
    
    private func hideCursorIfFullscreen() {
        if let window = NSApplication.shared.windows.first(where: { $0.windowNumber == windowNumber }) {
            if window.styleMask.contains(.fullScreen) {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }
    
}

final class MacPlayerNavigationBridge {
    fileprivate weak var pageController: MacPlayerPageController?

    @discardableResult
    func goBack(animation: MacPlayerNavigationAnimation) -> Bool {
        pageController?.navigateBackFromChrome(animation: animation) ?? false
    }

    @discardableResult
    func goForward(animation: MacPlayerNavigationAnimation) -> Bool {
        pageController?.navigateForwardFromChrome(animation: animation) ?? false
    }
}

enum MacPlayerNavigationAnimation {
    case animated
    case immediate
}

private enum MacPlayerEdgeClickTuning {
    static let navigationWidth: CGFloat = 44
    static let highlightWidth: CGFloat = 50
    static let maximumMovement: CGFloat = 12
    static let highlightMaximumMovement: CGFloat = maximumMovement / 2
    static let highlightActivationDelay: TimeInterval = 0.3
    static let highlightTapFlashDuration: TimeInterval = 0.09
    static let highlightFadeInDuration: TimeInterval = 0.1
    static let highlightFadeOutDuration: TimeInterval = 0.34
}

private enum MacPlayerEdgeClickSide {
    case left, right

    var navigationOffset: Int {
        switch self {
        case .left:
            return -1
        case .right:
            return 1
        }
    }
}

private struct MacPlayerPageControllerView: NSViewControllerRepresentable {

    @ObservedObject var playerModel: PlayerModel
    weak var playerMenuDelegate: PlayerMenuDelegate?
    let navigationBridge: MacPlayerNavigationBridge

    func makeNSViewController(context: Context) -> MacPlayerPageController {
        let pageController = MacPlayerPageController(
            playerModel: playerModel,
            playerMenuDelegate: playerMenuDelegate
        )
        navigationBridge.pageController = pageController
        return pageController
    }

    func updateNSViewController(_ nsViewController: MacPlayerPageController, context: Context) {
        navigationBridge.pageController = nsViewController
        nsViewController.update(playerMenuDelegate: playerMenuDelegate)
    }

    static func dismantleNSViewController(_ nsViewController: MacPlayerPageController, coordinator: ()) {
        nsViewController.cleanup()
    }
}

final class MacPlayerPageController: NSPageController, NSPageControllerDelegate {

    private static let fallbackPageIdentifier = NSPageController.ObjectIdentifier("MacPlayerPage")

    private let playerModel: PlayerModel
    private weak var playerMenuDelegate: PlayerMenuDelegate?
    private lazy var edgeClickNavigationView: MacPlayerEdgeClickNavigationView = {
        let view = MacPlayerEdgeClickNavigationView()
        view.canNavigate = { [weak self] side in
            self?.canNavigateFromChrome(offset: side.navigationOffset) == true
        }
        view.navigate = { [weak self] side in
            self?.navigateFromChrome(offset: side.navigationOffset, animation: .immediate) == true
        }
        return view
    }()
    private var edgeClickNavigationConstraints = [NSLayoutConstraint]()
    private var displayedCollectionId: String?
    private var displayedCollectionTokenCount: Int?
    private var tokenPagingDataSource: PlayerTokenPagingDataSource?
    private var pageObjects = [MacPlayerPageObject]()
    private var pageObjectIndices = [MacPlayerPageObject: Int]()
    private let pageViewControllers = NSHashTable<MacPlayerPageViewController>.weakObjects()
    private var isSyncingSelectionFromModel = false
    private var shouldSyncSelectionAfterTransition = false
    private var isTransitioning = false
    private var isLiveTransitioning = false
    private var transitionSourceIndex: Int?
    private var transitionDestinationIndex: Int?
    private var lastActivePrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    private var queuedNavigationRequests = [QueuedNavigationRequest]()
    private weak var liveTransitionSourceViewController: MacPlayerPageViewController?
    private var liveTransitionSourcePageObject: MacPlayerPageObject?

    init(playerModel: PlayerModel, playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerModel = playerModel
        self.playerMenuDelegate = playerMenuDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        transitionStyle = .horizontalStrip
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        syncSelectionWithModel()
        installEdgeClickNavigationOverlay()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        bringEdgeClickNavigationOverlayToFront()
        guard !isLiveTransitioning else { return }
        resizePageViewControllersToCurrentBounds()
    }

    func update(playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerMenuDelegate = playerMenuDelegate
        (selectedViewController as? MacPlayerPageViewController)?.updatePlayerMenuDelegate(playerMenuDelegate)
        syncSelectionWithModel()
    }

    func cleanup() {
        edgeClickNavigationView.cancelActivePressAndHighlights()
        pageViewControllers.allObjects.forEach { $0.cleanup() }
    }

    @discardableResult
    func navigateBackFromChrome(animation: MacPlayerNavigationAnimation) -> Bool {
        navigateFromChrome(offset: -1, animation: animation)
    }

    @discardableResult
    func navigateForwardFromChrome(animation: MacPlayerNavigationAnimation) -> Bool {
        navigateFromChrome(offset: 1, animation: animation)
    }

    private func installEdgeClickNavigationOverlay() {
        guard edgeClickNavigationView.superview == nil else { return }

        edgeClickNavigationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edgeClickNavigationView)
        edgeClickNavigationConstraints = edgeClickNavigationConstraints(for: edgeClickNavigationView)
        NSLayoutConstraint.activate(edgeClickNavigationConstraints)
    }

    private func bringEdgeClickNavigationOverlayToFront() {
        guard edgeClickNavigationView.superview === view else {
            installEdgeClickNavigationOverlay()
            return
        }
        guard view.subviews.last !== edgeClickNavigationView else { return }

        NSLayoutConstraint.deactivate(edgeClickNavigationConstraints)
        edgeClickNavigationView.removeFromSuperview()
        view.addSubview(edgeClickNavigationView)
        edgeClickNavigationConstraints = edgeClickNavigationConstraints(for: edgeClickNavigationView)
        NSLayoutConstraint.activate(edgeClickNavigationConstraints)
    }

    private func edgeClickNavigationConstraints(for overlayView: NSView) -> [NSLayoutConstraint] {
        [
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
    }

    private func syncSelectionWithModel() {
        guard isViewLoaded else { return }
        guard !isTransitioning else {
            shouldSyncSelectionAfterTransition = true
            return
        }

        isSyncingSelectionFromModel = true
        defer { isSyncingSelectionFromModel = false }

        let token = playerModel.currentToken
        guard let tokenContext = CollectionCatalog.tokenContext(for: token) else {
            displayFallbackToken(token)
            return
        }

        if displayedCollectionId != tokenContext.collectionId || displayedCollectionTokenCount != tokenContext.tokenCount {
            displayCollection(tokenContext)
            return
        }

        if currentPageObject?.matches(
            tokenContext,
            isInsertedWidgetToken: playerModel.isCurrentTokenInsertedWidgetToken
        ) != true {
            guard let targetIndex = pageObjects.firstIndex(where: {
                $0.matches(tokenContext, isInsertedWidgetToken: playerModel.isCurrentTokenInsertedWidgetToken)
            }) else {
                displayFallbackToken(token)
                return
            }
            queuedNavigationRequests.removeAll()
            lastActivePrefetchDirection = targetIndex < selectedIndex ? .backward : .forward
            transitionSourceIndex = nil
            transitionDestinationIndex = nil
            withoutImplicitAnimation {
                selectedIndex = targetIndex
            }
        }
    }

    private func displayCollection(_ context: PlayerTokenContext) {
        displayedCollectionId = context.collectionId
        displayedCollectionTokenCount = context.tokenCount
        queuedNavigationRequests.removeAll()
        transitionSourceIndex = nil
        transitionDestinationIndex = nil
        lastActivePrefetchDirection = .forward
        let dataSource = PlayerTokenPagingDataSource(
            initialCollectionId: context.collectionId,
            specificInitialToken: playerModel.currentToken,
            initialTokenId: playerModel.currentToken.id,
            widgetTokenInsertion: playerModel.widgetTokenInsertion
        )
        tokenPagingDataSource = dataSource
        let requiresRenderabilityFilter = CollectionCatalog.isDownloadableCollection(
            specificCollectionId: context.collectionId
        )
        var nextPageObjects = [MacPlayerPageObject]()
        nextPageObjects.reserveCapacity(
            context.tokenCount + (playerModel.widgetTokenInsertion?.collectionId == context.collectionId ? 1 : 0)
        )
        for tokenIndex in 0..<context.tokenCount {
            if let widgetTokenInsertion = playerModel.widgetTokenInsertion,
               widgetTokenInsertion.collectionId == context.collectionId,
               tokenIndex == widgetTokenInsertion.anchorTokenIndex {
                nextPageObjects.append(
                    MacPlayerPageObject(
                        collectionId: context.collectionId,
                        tokenIndex: widgetTokenInsertion.insertedTokenIndex,
                        coordinate: PlayerCoordinate(x: 0, y: 0),
                        isInsertedWidgetToken: true
                    )
                )
            }

            if requiresRenderabilityFilter,
               !CollectionCatalog.canGenerateToken(specificCollectionId: context.collectionId, tokenIndex: tokenIndex) {
                continue
            }

            nextPageObjects.append(MacPlayerPageObject(
                collectionId: context.collectionId,
                tokenIndex: tokenIndex,
                coordinate: PlayerCoordinate(
                    x: dataSource.horizontalCoordinateForTokenIndex(tokenIndex, verticalIndex: 0),
                    y: 0
                )
            ))
        }
        setPageObjects(nextPageObjects)
        guard !pageObjects.isEmpty else {
            displayFallbackToken(playerModel.currentToken)
            return
        }

        let targetIndex = pageObjects.firstIndex {
            $0.matches(context, isInsertedWidgetToken: playerModel.isCurrentTokenInsertedWidgetToken)
        } ?? 0
        withoutImplicitAnimation {
            arrangedObjects = pageObjects
            selectedIndex = targetIndex
        }
        resizePageViewControllersToCurrentBounds()
    }

    private func displayFallbackToken(_ token: GeneratedToken) {
        displayedCollectionId = nil
        displayedCollectionTokenCount = nil
        tokenPagingDataSource = nil
        queuedNavigationRequests.removeAll()
        transitionSourceIndex = nil
        transitionDestinationIndex = nil
        setPageObjects([MacPlayerPageObject(fallbackToken: token)])
        withoutImplicitAnimation {
            arrangedObjects = pageObjects
            selectedIndex = 0
        }
        resizePageViewControllersToCurrentBounds()
    }

    private func token(for pageObject: MacPlayerPageObject) -> GeneratedToken? {
        if let fallbackToken = pageObject.fallbackToken {
            return fallbackToken
        }

        guard let token = tokenPagingDataSource?.getToken(coordinate: pageObject.coordinate),
              !token.fullCollectionId.isEmpty else {
            return nil
        }
        return token
    }

    func pageController(
        _ pageController: NSPageController,
        identifierFor object: Any
    ) -> NSPageController.ObjectIdentifier {
        Self.pageIdentifier(for: object)
    }

    func pageController(
        _ pageController: NSPageController,
        viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier
    ) -> NSViewController {
        let viewController = MacPlayerPageViewController(playerMenuDelegate: playerMenuDelegate)
        pageViewControllers.add(viewController)
        return viewController
    }

    func pageController(
        _ pageController: NSPageController,
        prepare viewController: NSViewController,
        with object: Any?
    ) {
        guard let viewController = viewController as? MacPlayerPageViewController,
              let pageObject = object as? MacPlayerPageObject else {
            return
        }

        if viewController === liveTransitionSourceViewController,
           pageObject != liveTransitionSourcePageObject {
            return
        }

        viewController.resizeContent(to: view.bounds.size)
        guard let token = token(for: pageObject) else {
            viewController.cleanup()
            return
        }

        viewController.render(
            token,
            playerMenuDelegate: playerMenuDelegate,
            mode: renderMode(for: pageObject),
            downloadableMediaWindow: downloadableMediaWindow(for: pageObject)
        )
    }

    func pageController(
        _ pageController: NSPageController,
        didTransitionTo object: Any
    ) {
        guard !isSyncingSelectionFromModel else { return }
        guard let pageObject = object as? MacPlayerPageObject else { return }

        guard let token = token(for: pageObject) else {
            if !isLiveTransitioning {
                DispatchQueue.main.async { [weak self] in
                    self?.finishTransition()
                }
            }
            return
        }

        if !isLiveTransitioning {
            renderSelectedViewController(token, mode: .active)
            resetZoomInPageViewControllers()
        }
        playerModel.showPagedToken(token, isInsertedWidgetToken: pageObject.isInsertedWidgetToken)
        if !isLiveTransitioning {
            DispatchQueue.main.async { [weak self] in
                self?.finishTransition()
            }
        }
    }

    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        let sourcePageObject = liveTransitionSourcePageObject
        completeTransition()
        if let transitionSourceIndex, selectedIndex != transitionSourceIndex {
            lastActivePrefetchDirection = selectedIndex < transitionSourceIndex ? .backward : .forward
        }
        let didChangePage = currentPageObject != sourcePageObject
        isLiveTransitioning = false
        liveTransitionSourceViewController = nil
        liveTransitionSourcePageObject = nil
        renderCurrentPageViewController(mode: .active)
        if didChangePage {
            resetZoomInPageViewControllers()
        }
        finishTransition()
    }

    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
        isTransitioning = true
        isLiveTransitioning = true
        transitionSourceIndex = selectedIndex
        transitionDestinationIndex = nil
        liveTransitionSourceViewController = selectedViewController as? MacPlayerPageViewController
        liveTransitionSourcePageObject = currentPageObject
    }

    private func finishTransition() {
        isTransitioning = false
        transitionSourceIndex = nil
        transitionDestinationIndex = nil
        resizePageViewControllersToCurrentBounds()
        if shouldSyncSelectionAfterTransition {
            shouldSyncSelectionAfterTransition = false
            syncSelectionWithModel()
        }
        startQueuedNavigationIfNeeded()
    }

    private func navigateFromChrome(offset: Int, animation: MacPlayerNavigationAnimation) -> Bool {
        guard pageObjects.count > 1 else { return false }

        if isTransitioning {
            queueNavigation(offset: offset, animation: animation)
            return true
        }

        guard pageObjects.indices.contains(selectedIndex + offset) else {
            queuedNavigationRequests.removeAll()
            return true
        }

        return startNavigation(offset: offset, animation: animation)
    }

    private func canNavigateFromChrome(offset: Int) -> Bool {
        guard pageObjects.count > 1, !isTransitioning else { return false }
        let targetIndex = selectedIndex + offset
        guard pageObjects.indices.contains(targetIndex) else { return false }
        return token(for: pageObjects[targetIndex]) != nil
    }

    private func queueNavigation(offset: Int, animation: MacPlayerNavigationAnimation) {
        queuedNavigationRequests = [QueuedNavigationRequest(offset: offset, animation: animation)]
    }

    @discardableResult
    private func startNavigation(offset: Int, animation: MacPlayerNavigationAnimation) -> Bool {
        guard !isTransitioning else { return false }
        guard pageObjects.indices.contains(selectedIndex + offset) else { return false }

        switch animation {
        case .animated:
            return startAnimatedNavigation(offset: offset)
        case .immediate:
            return navigateImmediately(offset: offset)
        }
    }

    @discardableResult
    private func startAnimatedNavigation(offset: Int) -> Bool {
        switch offset {
        case ..<0:
            transitionSourceIndex = selectedIndex
            transitionDestinationIndex = selectedIndex + offset
            lastActivePrefetchDirection = .backward
            isTransitioning = true
            navigateBack(nil)
        case 1...:
            transitionSourceIndex = selectedIndex
            transitionDestinationIndex = selectedIndex + offset
            lastActivePrefetchDirection = .forward
            isTransitioning = true
            navigateForward(nil)
        default:
            transitionSourceIndex = nil
            transitionDestinationIndex = nil
            return false
        }

        return true
    }

    @discardableResult
    private func navigateImmediately(offset: Int) -> Bool {
        let targetIndex = selectedIndex + offset
        guard pageObjects.indices.contains(targetIndex) else { return false }

        let pageObject = pageObjects[targetIndex]
        guard let token = token(for: pageObject) else { return false }

        lastActivePrefetchDirection = targetIndex < selectedIndex ? .backward : .forward
        transitionSourceIndex = nil
        transitionDestinationIndex = nil
        isSyncingSelectionFromModel = true
        withoutImplicitAnimation {
            selectedIndex = targetIndex
        }
        isSyncingSelectionFromModel = false

        renderSelectedViewController(token, mode: .active)
        resetZoomInPageViewControllers()
        playerModel.showPagedToken(token, isInsertedWidgetToken: pageObject.isInsertedWidgetToken)
        resizePageViewControllersToCurrentBounds()
        return true
    }

    private func renderSelectedViewController(_ token: GeneratedToken, mode: MacPlayerMediaRenderMode) {
        guard let viewController = selectedViewController as? MacPlayerPageViewController,
              let pageObject = currentPageObject else { return }
        viewController.resizeContent(to: view.bounds.size)
        viewController.render(
            token,
            playerMenuDelegate: playerMenuDelegate,
            mode: mode,
            downloadableMediaWindow: downloadableMediaWindow(for: pageObject)
        )
    }

    private func renderCurrentPageViewController(mode: MacPlayerMediaRenderMode) {
        guard let pageObject = currentPageObject,
              let token = token(for: pageObject) else {
            return
        }
        renderSelectedViewController(token, mode: mode)
    }

    private func startQueuedNavigationIfNeeded() {
        guard !queuedNavigationRequests.isEmpty, !isTransitioning else { return }

        while !queuedNavigationRequests.isEmpty, !isTransitioning {
            let request = queuedNavigationRequests.removeFirst()
            guard startNavigation(offset: request.offset, animation: request.animation) else {
                continue
            }

            if request.animation == .animated {
                return
            }
        }
    }

    private func resizePageViewControllersToCurrentBounds() {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        pageViewControllers.allObjects.forEach { $0.resizeContent(to: size) }
    }

    private func resetZoomInPageViewControllers() {
        pageViewControllers.allObjects.forEach { $0.resetZoomForReuse() }
    }

    private var currentPageObject: MacPlayerPageObject? {
        guard pageObjects.indices.contains(selectedIndex) else { return nil }
        return pageObjects[selectedIndex]
    }

    private func setPageObjects(_ nextPageObjects: [MacPlayerPageObject]) {
        pageObjects = nextPageObjects
        pageObjectIndices.removeAll(keepingCapacity: true)
        for (index, pageObject) in nextPageObjects.enumerated() where pageObjectIndices[pageObject] == nil {
            pageObjectIndices[pageObject] = index
        }
    }

    private func downloadableMediaWindow(for pageObject: MacPlayerPageObject) -> PlayerDownloadableMediaWindow? {
        tokenPagingDataSource?.downloadableMediaWindow(
            coordinate: pageObject.coordinate,
            direction: prefetchDirection(for: pageObject)
        )
    }

    private func prefetchDirection(for pageObject: MacPlayerPageObject) -> DownloadableMediaCache.PrefetchDirection {
        guard let pageIndex = pageObjectIndices[pageObject] else {
            return lastActivePrefetchDirection
        }

        if let transitionSourceIndex, pageIndex != transitionSourceIndex {
            return pageIndex < transitionSourceIndex ? .backward : .forward
        }

        if pageIndex == selectedIndex {
            return lastActivePrefetchDirection
        }

        return pageIndex < selectedIndex ? .backward : .forward
    }

    private func renderMode(for pageObject: MacPlayerPageObject) -> MacPlayerMediaRenderMode {
        if pageObject == currentPageObject {
            return .active
        }

        if let transitionDestinationIndex,
           pageObjects.indices.contains(transitionDestinationIndex),
           pageObjects[transitionDestinationIndex] == pageObject {
            return .transitionDestination
        }

        if isLiveTransitioning, pageObject != liveTransitionSourcePageObject {
            return .transitionDestination
        }

        return .preview
    }

    private func withoutImplicitAnimation(_ updates: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            updates()
        }
    }

    private struct QueuedNavigationRequest {
        let offset: Int
        let animation: MacPlayerNavigationAnimation
    }

    private static func pageIdentifier(for object: Any) -> NSPageController.ObjectIdentifier {
        guard let pageObject = object as? MacPlayerPageObject else {
            return fallbackPageIdentifier
        }

        return NSPageController.ObjectIdentifier(
            "MacPlayerPage:\(pageObject.collectionId):\(pageObject.tokenIndex):\(pageObject.isInsertedWidgetToken):\(pageObject.fallbackToken?.id ?? "")"
        )
    }
}

private final class MacPlayerEdgeClickNavigationView: NSView {

    var canNavigate: ((MacPlayerEdgeClickSide) -> Bool)?
    var navigate: ((MacPlayerEdgeClickSide) -> Bool)?

    private let leftHighlight = MacPlayerEdgeClickHighlightView(side: .left)
    private let rightHighlight = MacPlayerEdgeClickHighlightView(side: .right)
    private var activeSide: MacPlayerEdgeClickSide?
    private var initialLocation = CGPoint.zero
    private var didMoveEnoughToCancelHighlight = false
    private var pendingHighlightSide: MacPlayerEdgeClickSide?
    private var highlightWorkItem: DispatchWorkItem?
    private var highlightRequestId = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        installHighlights()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        highlightWorkItem?.cancel()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shouldReceiveCurrentMouseDownEvent,
              navigableEdgeClickSide(at: point) != nil else {
            return nil
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let side = navigableEdgeClickSide(at: location) else { return }

        activeSide = side
        initialLocation = location
        didMoveEnoughToCancelHighlight = false
        beginHighlight(on: side)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeSide else { return }

        let location = convert(event.locationInWindow, from: nil)
        guard isClickStillValid(at: location, for: activeSide) else {
            cancelActivePress()
            return
        }

        if !didMoveEnoughToCancelHighlight,
           hasMovedEnoughToCancelHighlight(at: location) {
            didMoveEnoughToCancelHighlight = true
            endHighlight(on: activeSide)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let activeSide else { return }

        let location = convert(event.locationInWindow, from: nil)
        guard isClickStillValid(at: location, for: activeSide) else {
            cancelActivePress()
            return
        }

        handleClick(on: activeSide)
        clearActivePress()
    }

    func cancelActivePressAndHighlights() {
        cancelPendingHighlight()
        clearActivePress()
        highlightRequestId += 1
        leftHighlight.setHighlighted(false)
        rightHighlight.setHighlighted(false)
    }

    private var shouldReceiveCurrentMouseDownEvent: Bool {
        guard let event = window?.currentEvent ?? NSApp.currentEvent else { return false }
        return event.type == .leftMouseDown
            && (event.window ?? window)?.isKeyWindow == true
    }

    private func installHighlights() {
        [leftHighlight, rightHighlight].forEach { highlightView in
            highlightView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(highlightView)
        }

        NSLayoutConstraint.activate([
            leftHighlight.topAnchor.constraint(equalTo: topAnchor),
            leftHighlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftHighlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftHighlight.widthAnchor.constraint(equalToConstant: MacPlayerEdgeClickTuning.highlightWidth),

            rightHighlight.topAnchor.constraint(equalTo: topAnchor),
            rightHighlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightHighlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightHighlight.widthAnchor.constraint(equalToConstant: MacPlayerEdgeClickTuning.highlightWidth)
        ])
    }

    private func edgeClickSide(at location: CGPoint) -> MacPlayerEdgeClickSide? {
        let edgeWidth = min(MacPlayerEdgeClickTuning.navigationWidth, bounds.width / 2)
        if location.x <= edgeWidth {
            return .left
        }
        if location.x >= bounds.width - edgeWidth {
            return .right
        }
        return nil
    }

    private func navigableEdgeClickSide(at location: CGPoint) -> MacPlayerEdgeClickSide? {
        guard let side = edgeClickSide(at: location),
              canNavigate?(side) == true else {
            return nil
        }
        return side
    }

    private func isClickStillValid(at location: CGPoint, for side: MacPlayerEdgeClickSide) -> Bool {
        guard edgeClickSide(at: location) == side else { return false }

        let distance = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
        return distance <= MacPlayerEdgeClickTuning.maximumMovement
    }

    private func hasMovedEnoughToCancelHighlight(at location: CGPoint) -> Bool {
        let distance = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
        return distance > MacPlayerEdgeClickTuning.highlightMaximumMovement
    }

    private func beginHighlight(on side: MacPlayerEdgeClickSide) {
        cancelPendingHighlight()
        highlight(for: oppositeSide(of: side)).setHighlighted(false)
        highlight(for: side).setHighlighted(false)

        guard canNavigate?(side) == true else { return }

        pendingHighlightSide = side
        highlightRequestId += 1
        let requestId = highlightRequestId
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.highlightRequestId == requestId,
                  self.pendingHighlightSide == side,
                  self.canNavigate?(side) == true else {
                return
            }

            self.pendingHighlightSide = nil
            self.highlightWorkItem = nil
            self.highlight(for: side).setHighlighted(true)
        }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MacPlayerEdgeClickTuning.highlightActivationDelay,
            execute: workItem
        )
    }

    private func endHighlight(on side: MacPlayerEdgeClickSide) {
        cancelPendingHighlight()
        highlightRequestId += 1
        highlight(for: side).setHighlighted(false)
    }

    private func handleClick(on side: MacPlayerEdgeClickSide) {
        guard canNavigate?(side) == true else {
            endHighlight(on: side)
            return
        }

        if cancelPendingHighlight(on: side) {
            flashHighlight(on: side)
        } else {
            endHighlight(on: side)
        }

        _ = navigate?(side)
    }

    @discardableResult
    private func cancelPendingHighlight(on side: MacPlayerEdgeClickSide? = nil) -> Bool {
        guard let pendingSide = pendingHighlightSide else {
            return false
        }
        if let side, pendingSide != side {
            return false
        }

        highlightWorkItem?.cancel()
        highlightWorkItem = nil
        pendingHighlightSide = nil
        highlightRequestId += 1
        return true
    }

    private func flashHighlight(on side: MacPlayerEdgeClickSide) {
        highlight(for: oppositeSide(of: side)).setHighlighted(false)
        highlight(for: side).setHighlighted(true)
        highlightRequestId += 1
        let requestId = highlightRequestId

        DispatchQueue.main.asyncAfter(
            deadline: .now() + MacPlayerEdgeClickTuning.highlightTapFlashDuration
        ) { [weak self] in
            guard let self, self.highlightRequestId == requestId else { return }

            self.highlight(for: side).setHighlighted(false)
        }
    }

    private func cancelActivePress() {
        if let activeSide {
            endHighlight(on: activeSide)
        }
        clearActivePress()
    }

    private func clearActivePress() {
        activeSide = nil
        initialLocation = .zero
        didMoveEnoughToCancelHighlight = false
    }

    private func oppositeSide(of side: MacPlayerEdgeClickSide) -> MacPlayerEdgeClickSide {
        switch side {
        case .left:
            return .right
        case .right:
            return .left
        }
    }

    private func highlight(for side: MacPlayerEdgeClickSide) -> MacPlayerEdgeClickHighlightView {
        switch side {
        case .left:
            return leftHighlight
        case .right:
            return rightHighlight
        }
    }
}

private final class MacPlayerEdgeClickHighlightView: NSView {

    private let side: MacPlayerEdgeClickSide

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    init(side: MacPlayerEdgeClickSide) {
        self.side = side
        super.init(frame: .zero)
        wantsLayer = true
        layer = CAGradientLayer()
        configureGradient()
        gradientLayer.opacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setHighlighted(_ isHighlighted: Bool) {
        let currentOpacity = gradientLayer.presentation()?.opacity ?? gradientLayer.opacity
        gradientLayer.removeAnimation(forKey: "edgeClickHighlightOpacity")

        let targetOpacity: Float = isHighlighted ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.opacity = targetOpacity
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = currentOpacity
        animation.toValue = targetOpacity
        animation.duration = isHighlighted
            ? MacPlayerEdgeClickTuning.highlightFadeInDuration
            : MacPlayerEdgeClickTuning.highlightFadeOutDuration
        animation.timingFunction = isHighlighted
            ? CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            : CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        gradientLayer.add(animation, forKey: "edgeClickHighlightOpacity")
    }

    private func configureGradient() {
        let edgeColor = NSColor.black.withAlphaComponent(0.36).cgColor
        let midColor = NSColor.black.withAlphaComponent(0.18).cgColor
        let featherColor = NSColor.black.withAlphaComponent(0.05).cgColor
        let clearColor = NSColor.black.withAlphaComponent(0).cgColor
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.colors = side == .left
            ? [edgeColor, midColor, featherColor, clearColor]
            : [clearColor, featherColor, midColor, edgeColor]
        gradientLayer.locations = [0, 0.34, 0.72, 1]
    }
}

private final class MacPlayerPageObject: NSObject {
    let collectionId: String
    let tokenIndex: Int
    let coordinate: PlayerCoordinate
    let fallbackToken: GeneratedToken?
    let isInsertedWidgetToken: Bool

    init(
        collectionId: String,
        tokenIndex: Int,
        coordinate: PlayerCoordinate,
        isInsertedWidgetToken: Bool = false
    ) {
        self.collectionId = collectionId
        self.tokenIndex = tokenIndex
        self.coordinate = coordinate
        self.fallbackToken = nil
        self.isInsertedWidgetToken = isInsertedWidgetToken
        super.init()
    }

    init(fallbackToken: GeneratedToken) {
        self.collectionId = fallbackToken.fullCollectionId
        self.tokenIndex = 0
        self.coordinate = PlayerCoordinate(x: 0, y: 0)
        self.fallbackToken = fallbackToken
        self.isInsertedWidgetToken = false
        super.init()
    }

    func matches(_ context: PlayerTokenContext, isInsertedWidgetToken: Bool) -> Bool {
        collectionId == context.collectionId
            && tokenIndex == context.tokenIndex
            && self.isInsertedWidgetToken == isInsertedWidgetToken
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(collectionId)
        hasher.combine(tokenIndex)
        hasher.combine(fallbackToken?.id)
        hasher.combine(isInsertedWidgetToken)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MacPlayerPageObject else { return false }
        return collectionId == other.collectionId
            && tokenIndex == other.tokenIndex
            && fallbackToken?.id == other.fallbackToken?.id
            && isInsertedWidgetToken == other.isInsertedWidgetToken
    }
}

private final class MacPlayerPageViewController: NSViewController {

    private weak var playerMenuDelegate: PlayerMenuDelegate?
    private var mediaView: MacPlayerMediaContainerView?

    init(playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerMenuDelegate = playerMenuDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        cleanup()
    }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        self.view = view
    }

    func updatePlayerMenuDelegate(_ playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerMenuDelegate = playerMenuDelegate
        mediaView?.updatePlayerMenuDelegate(playerMenuDelegate)
    }

    func render(
        _ token: GeneratedToken,
        playerMenuDelegate: PlayerMenuDelegate?,
        mode: MacPlayerMediaRenderMode,
        downloadableMediaWindow: PlayerDownloadableMediaWindow?
    ) {
        updatePlayerMenuDelegate(playerMenuDelegate)
        let mediaView = ensureMediaView()
        mediaView.render(token, mode: mode, downloadableMediaWindow: downloadableMediaWindow)
    }

    func cleanup() {
        mediaView?.cleanup()
    }

    func resetZoomForReuse() {
        mediaView?.resetZoomForReuse()
    }

    func resizeContent(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if view.frame.size != size {
            view.setFrameSize(size)
        }
        mediaView?.frame = view.bounds
        view.layoutSubtreeIfNeeded()
    }

    private func ensureMediaView() -> MacPlayerMediaContainerView {
        if let mediaView {
            return mediaView
        }

        let mediaView = MacPlayerMediaContainerView(playerMenuDelegate: playerMenuDelegate)
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mediaView)
        NSLayoutConstraint.activate([
            mediaView.topAnchor.constraint(equalTo: view.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.mediaView = mediaView
        return mediaView
    }
}

private struct MacPlayerCompletionControls: View {
    let onViewAgain: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(image: Images.viewAgain, title: Strings.viewAgain, action: onViewAgain)
            actionButton(image: Images.finish, title: Strings.finish, action: onFinish)
        }
    }

    private func actionButton(image: Image, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                image
                    .font(.caption.weight(.semibold))
                    .imageScale(.small)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel(title)
    }
}
