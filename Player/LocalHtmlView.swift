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
    private var displayedCollectionId: String?
    private var displayedCollectionTokenCount: Int?
    private var tokenPagingDataSource: PlayerTokenPagingDataSource?
    private var pageObjects = [MacPlayerPageObject]()
    private let pageViewControllers = NSHashTable<MacPlayerPageViewController>.weakObjects()
    private var isSyncingSelectionFromModel = false
    private var shouldSyncSelectionAfterTransition = false
    private var isTransitioning = false
    private var isLiveTransitioning = false
    private var transitionDestinationIndex: Int?
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
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !isLiveTransitioning else { return }
        resizePageViewControllersToCurrentBounds()
    }

    func update(playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerMenuDelegate = playerMenuDelegate
        (selectedViewController as? MacPlayerPageViewController)?.updatePlayerMenuDelegate(playerMenuDelegate)
        syncSelectionWithModel()
    }

    func cleanup() {
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

        if currentPageObject?.tokenIndex != tokenContext.tokenIndex {
            guard let targetIndex = pageObjects.firstIndex(where: { $0.tokenIndex == tokenContext.tokenIndex }) else {
                displayFallbackToken(token)
                return
            }
            queuedNavigationRequests.removeAll()
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
        transitionDestinationIndex = nil
        let dataSource = PlayerTokenPagingDataSource(
            initialCollectionId: context.collectionId,
            specificInitialToken: playerModel.currentToken,
            initialTokenId: playerModel.currentToken.id
        )
        tokenPagingDataSource = dataSource
        let requiresRenderabilityFilter = CollectionCatalog.isDownloadableCollection(
            specificCollectionId: context.collectionId
        )
        pageObjects = (0..<context.tokenCount).compactMap { tokenIndex in
            if requiresRenderabilityFilter,
               !CollectionCatalog.canGenerateToken(specificCollectionId: context.collectionId, tokenIndex: tokenIndex) {
                return nil
            }
            return MacPlayerPageObject(
                collectionId: context.collectionId,
                tokenIndex: tokenIndex,
                coordinate: PlayerCoordinate(
                    x: tokenIndex - context.tokenIndex,
                    y: 0
                )
            )
        }
        guard !pageObjects.isEmpty else {
            displayFallbackToken(playerModel.currentToken)
            return
        }

        let targetIndex = pageObjects.firstIndex { $0.tokenIndex == context.tokenIndex } ?? 0
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
        transitionDestinationIndex = nil
        pageObjects = [MacPlayerPageObject(fallbackToken: token)]
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
            mode: renderMode(for: pageObject)
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
        }
        playerModel.showPagedToken(token)
        if !isLiveTransitioning {
            DispatchQueue.main.async { [weak self] in
                self?.finishTransition()
            }
        }
    }

    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        completeTransition()
        isLiveTransitioning = false
        liveTransitionSourceViewController = nil
        liveTransitionSourcePageObject = nil
        renderCurrentPageViewController(mode: .active)
        finishTransition()
    }

    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
        isTransitioning = true
        isLiveTransitioning = true
        liveTransitionSourceViewController = selectedViewController as? MacPlayerPageViewController
        liveTransitionSourcePageObject = currentPageObject
    }

    private func finishTransition() {
        isTransitioning = false
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
            transitionDestinationIndex = selectedIndex + offset
            isTransitioning = true
            navigateBack(nil)
        case 1...:
            transitionDestinationIndex = selectedIndex + offset
            isTransitioning = true
            navigateForward(nil)
        default:
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

        isSyncingSelectionFromModel = true
        withoutImplicitAnimation {
            selectedIndex = targetIndex
        }
        isSyncingSelectionFromModel = false

        renderSelectedViewController(token, mode: .active)
        playerModel.showPagedToken(token)
        resizePageViewControllersToCurrentBounds()
        return true
    }

    private func renderSelectedViewController(_ token: GeneratedToken, mode: MacPlayerMediaRenderMode) {
        guard let viewController = selectedViewController as? MacPlayerPageViewController else { return }
        viewController.resizeContent(to: view.bounds.size)
        viewController.render(token, playerMenuDelegate: playerMenuDelegate, mode: mode)
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

    private var currentPageObject: MacPlayerPageObject? {
        guard pageObjects.indices.contains(selectedIndex) else { return nil }
        return pageObjects[selectedIndex]
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
            "MacPlayerPage:\(pageObject.collectionId):\(pageObject.tokenIndex):\(pageObject.fallbackToken?.id ?? "")"
        )
    }
}

private final class MacPlayerPageObject: NSObject {
    let collectionId: String
    let tokenIndex: Int
    let coordinate: PlayerCoordinate
    let fallbackToken: GeneratedToken?

    init(collectionId: String, tokenIndex: Int, coordinate: PlayerCoordinate) {
        self.collectionId = collectionId
        self.tokenIndex = tokenIndex
        self.coordinate = coordinate
        self.fallbackToken = nil
        super.init()
    }

    init(fallbackToken: GeneratedToken) {
        self.collectionId = fallbackToken.fullCollectionId
        self.tokenIndex = 0
        self.coordinate = PlayerCoordinate(x: 0, y: 0)
        self.fallbackToken = fallbackToken
        super.init()
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(collectionId)
        hasher.combine(tokenIndex)
        hasher.combine(fallbackToken?.id)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MacPlayerPageObject else { return false }
        return collectionId == other.collectionId
            && tokenIndex == other.tokenIndex
            && fallbackToken?.id == other.fallbackToken?.id
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
        mode: MacPlayerMediaRenderMode
    ) {
        updatePlayerMenuDelegate(playerMenuDelegate)
        let mediaView = ensureMediaView()
        mediaView.render(token, mode: mode)
    }

    func cleanup() {
        mediaView?.cleanup()
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
