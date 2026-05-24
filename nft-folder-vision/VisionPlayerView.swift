// ∅ 2026 lil org

import AVFoundation
import ImageIO
import SwiftUI
import UIKit

struct VisionPlayerConfig: Hashable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
    var initialTokenId: String?
}

struct VisionPlayerView: View {
    
    private let onDismiss: () -> Void
    @StateObject private var playerModel: VisionPlayerModel
    @State private var navigationBridge = VisionPlayerNavigationBridge()
    
    init(config: VisionPlayerConfig, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _playerModel = StateObject(wrappedValue: VisionPlayerModel(config: config))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VisionPlayerPagerView(
                playerModel: playerModel,
                navigationBridge: navigationBridge
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: onDismiss) {
                    Images.back
                }
                .accessibilityLabel(Strings.back)

                Spacer()

                HStack {
                    Button(action: goBack) {
                        Images.back
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!playerModel.canGoBack)
                    .accessibilityLabel(Strings.back)

                    Button(action: goForward) {
                        Images.forward
                    }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!playerModel.canGoForward)
                    .accessibilityLabel(Strings.forward)
                }

                Spacer()

                moreMenu
            }
            .padding()
        }
        .background(Color.black)
        .onDisappear {
            DownloadableMediaCache.shared.clearActiveWindow(ownerId: playerModel.id)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(Strings.viewOnBlockExplorer, action: viewOnWeb)
                .disabled(playerModel.currentToken.url == nil)
        } label: {
            Images.ellipsis
        }
        .accessibilityLabel(Strings.more)
    }
    
    private func viewOnWeb() {
        if let url = playerModel.currentToken.url {
            UIApplication.shared.open(url)
        }
    }

    private func goBack() {
        navigationBridge.goBack()
    }

    private func goForward() {
        navigationBridge.goForward()
    }

}

private final class VisionPlayerModel: ObservableObject {

    let id: UUID
    private let dataSource: PlayerTokenPagingDataSource
    @Published private var displayState: VisionPlayerDisplayState

    init(config: VisionPlayerConfig) {
        let initialCoordinate = PlayerCoordinate(x: 0, y: 0)
        id = config.id
        dataSource = PlayerTokenPagingDataSource(
            initialCollectionId: config.initialItemId,
            specificInitialToken: config.specificToken,
            initialTokenId: config.initialTokenId
        )
        displayState = VisionPlayerDisplayState(
            coordinate: initialCoordinate,
            token: dataSource.getToken(coordinate: initialCoordinate),
            preferredPrefetchDirection: .forward
        )
    }

    var currentToken: GeneratedToken {
        displayState.token
    }

    var currentCoordinate: PlayerCoordinate {
        displayState.coordinate
    }

    var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection {
        displayState.preferredPrefetchDirection
    }

    var canGoBack: Bool {
        canRender(offset: -1)
    }

    var canGoForward: Bool {
        canRender(offset: 1)
    }

    func token(for coordinate: PlayerCoordinate) -> GeneratedToken {
        dataSource.getToken(coordinate: coordinate)
    }

    func context(for coordinate: PlayerCoordinate) -> PlayerTokenContext? {
        dataSource.collectionTokenContext(coordinate: coordinate)
    }

    func canRender(_ coordinate: PlayerCoordinate) -> Bool {
        dataSource.canRender(coordinate: coordinate)
    }

    func coordinate(adjacentTo coordinate: PlayerCoordinate, offset: Int) -> PlayerCoordinate {
        PlayerCoordinate(
            x: coordinate.x + offset,
            y: coordinate.y
        )
    }

    func display(
        coordinate: PlayerCoordinate,
        direction: DownloadableMediaCache.PrefetchDirection
    ) {
        guard dataSource.canRender(coordinate: coordinate) else { return }

        displayState = VisionPlayerDisplayState(
            coordinate: coordinate,
            token: dataSource.getToken(coordinate: coordinate),
            preferredPrefetchDirection: direction
        )
    }

    private func canRender(offset: Int) -> Bool {
        canRender(coordinate(adjacentTo: currentCoordinate, offset: offset))
    }
}

private struct VisionPlayerDisplayState {
    let coordinate: PlayerCoordinate
    let token: GeneratedToken
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
}

private final class VisionPlayerNavigationBridge {

    fileprivate weak var pageController: VisionPlayerPageController?

    @discardableResult
    func goBack(animated: Bool = true) -> Bool {
        pageController?.goBack(animated: animated) ?? false
    }

    @discardableResult
    func goForward(animated: Bool = true) -> Bool {
        pageController?.goForward(animated: animated) ?? false
    }

}

private enum VisionPlayerPagingTuning {
    static let pageGap: CGFloat = 23
}

private enum VisionPlayerZoomTuning {
    static let maximumScale: CGFloat = 4
    static let doubleTapScale: CGFloat = 2.5
    static let resetTolerance: CGFloat = 0.01
    static let edgePaginationTolerance: CGFloat = 2
    static let horizontalIntentRatio: CGFloat = 1.15
}

private enum VisionPlayerZoomContentLayout: Equatable {
    case viewport
    case intrinsicMediaSize(CGSize)
}

private enum VisionPlayerPageNavigation {
    case back, forward

    var offset: Int {
        switch self {
        case .back:
            return -1
        case .forward:
            return 1
        }
    }

    var pageDirection: UIPageViewController.NavigationDirection {
        switch self {
        case .back:
            return .reverse
        case .forward:
            return .forward
        }
    }

    var prefetchDirection: DownloadableMediaCache.PrefetchDirection {
        switch self {
        case .back:
            return .backward
        case .forward:
            return .forward
        }
    }
}

private struct VisionPlayerPagerView: UIViewControllerRepresentable {

    @ObservedObject var playerModel: VisionPlayerModel
    let navigationBridge: VisionPlayerNavigationBridge

    func makeUIViewController(context: Context) -> VisionPlayerPageController {
        let pageController = VisionPlayerPageController(playerModel: playerModel)
        navigationBridge.pageController = pageController
        return pageController
    }

    func updateUIViewController(_ pageController: VisionPlayerPageController, context: Context) {
        navigationBridge.pageController = pageController
        pageController.update()
    }

    static func dismantleUIViewController(_ pageController: VisionPlayerPageController, coordinator: ()) {
        pageController.cleanup()
    }
}

private final class VisionPlayerPageController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    private let playerModel: VisionPlayerModel
    private var isTransitioning = false
    private var queuedNavigationRequest: VisionPlayerPageNavigation?
    private weak var transitionDestinationPage: VisionPlayerPageHostController?
    private var configuredPagingPanGestures = [ObjectIdentifier: UIPanGestureRecognizer]()
    private var zoomedPagingPanRestingOffsets = [ObjectIdentifier: CGFloat]()
    private var unlockedZoomedPagingPanGestures = Set<ObjectIdentifier>()

    init(playerModel: VisionPlayerModel) {
        self.playerModel = playerModel
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: VisionPlayerPagingTuning.pageGap]
        )
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        dataSource = self
        delegate = self
        setCurrentPage(
            coordinate: playerModel.currentCoordinate,
            preferredPrefetchDirection: playerModel.preferredPrefetchDirection,
            direction: .forward,
            animated: false
        )
        configurePagingScrollViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePagingScrollViews()
    }

    func update() {
        guard isViewLoaded else { return }
        guard let currentPage else {
            setCurrentPage(
                coordinate: playerModel.currentCoordinate,
                preferredPrefetchDirection: playerModel.preferredPrefetchDirection,
                direction: .forward,
                animated: false
            )
            return
        }

        guard !isTransitioning else { return }

        if currentPage.coordinate != playerModel.currentCoordinate {
            setCurrentPage(
                coordinate: playerModel.currentCoordinate,
                preferredPrefetchDirection: playerModel.preferredPrefetchDirection,
                direction: pageDirection(
                    from: currentPage.coordinate,
                    to: playerModel.currentCoordinate
                ),
                animated: false
            )
        } else {
            currentPage.update(
                coordinate: playerModel.currentCoordinate,
                preferredPrefetchDirection: playerModel.preferredPrefetchDirection
            )
        }
    }

    func cleanup() {
        queuedNavigationRequest = nil
        transitionDestinationPage = nil
        dataSource = nil
        delegate = nil
        configuredPagingPanGestures.values.forEach {
            $0.removeTarget(self, action: #selector(handlePagingPan(_:)))
        }
        configuredPagingPanGestures.removeAll()
        zoomedPagingPanRestingOffsets.removeAll()
        unlockedZoomedPagingPanGestures.removeAll()
    }

    @discardableResult
    func goBack(animated: Bool) -> Bool {
        navigate(.back, animated: animated)
    }

    @discardableResult
    func goForward(animated: Bool) -> Bool {
        navigate(.forward, animated: animated)
    }

    private var currentPage: VisionPlayerPageHostController? {
        viewControllers?.first as? VisionPlayerPageHostController
    }

    private var displayedCoordinate: PlayerCoordinate {
        currentPage?.coordinate ?? playerModel.currentCoordinate
    }

    private func setCurrentPage(
        coordinate: PlayerCoordinate,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection,
        direction: UIPageViewController.NavigationDirection,
        animated: Bool
    ) {
        let page = makePage(
            coordinate: coordinate,
            preferredPrefetchDirection: preferredPrefetchDirection
        )
        setViewControllers([page], direction: direction, animated: animated, completion: nil)
    }

    private func makePage(
        coordinate: PlayerCoordinate,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection,
        ownsDownloadableMediaWindow: Bool = true
    ) -> VisionPlayerPageHostController {
        let page = VisionPlayerPageHostController(
            playerModel: playerModel,
            coordinate: coordinate,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow
        )
        pagingPanGestures.forEach { page.registerPagingPanGesture($0) }
        return page
    }

    @discardableResult
    private func navigate(_ request: VisionPlayerPageNavigation, animated: Bool) -> Bool {
        let sourceCoordinate = displayedCoordinate
        let targetCoordinate = targetCoordinate(from: sourceCoordinate, for: request)
        guard playerModel.canRender(targetCoordinate) else {
            queuedNavigationRequest = nil
            return false
        }

        guard !isTransitioning else {
            queuedNavigationRequest = request
            return true
        }

        return startNavigation(
            request,
            from: sourceCoordinate,
            animated: animated
        )
    }

    @discardableResult
    private func startNavigation(
        _ request: VisionPlayerPageNavigation,
        from sourceCoordinate: PlayerCoordinate,
        animated: Bool
    ) -> Bool {
        let targetCoordinate = targetCoordinate(from: sourceCoordinate, for: request)
        guard playerModel.canRender(targetCoordinate) else { return false }

        let targetPage = makePage(
            coordinate: targetCoordinate,
            preferredPrefetchDirection: request.prefetchDirection
        )
        let sourcePage = currentPage
        isTransitioning = true
        sourcePage?.resetZoomForReuse()
        setViewControllers([targetPage], direction: request.pageDirection, animated: animated) { [weak self] completed in
            guard let self else { return }

            if completed {
                self.markPageAsNotOwningDownloadableMediaWindow(sourcePage)
                self.playerModel.display(
                    coordinate: targetCoordinate,
                    direction: request.prefetchDirection
                )
            } else {
                self.markPageAsNotOwningDownloadableMediaWindow(targetPage)
                self.refreshCurrentDownloadableMediaWindow()
            }
            self.finishTransition()
        }
        return true
    }

    private func refreshCurrentDownloadableMediaWindow() {
        guard let currentPage else { return }
        currentPage.refreshDownloadableMediaWindow()
    }

    private func finishTransition() {
        let request = queuedNavigationRequest
        queuedNavigationRequest = nil
        isTransitioning = false
        configurePagingScrollViews()

        guard let request else { return }
        DispatchQueue.main.async { [weak self] in
            self?.navigate(request, animated: true)
        }
    }

    private func pageDirection(
        from source: PlayerCoordinate,
        to target: PlayerCoordinate
    ) -> UIPageViewController.NavigationDirection {
        target.x < source.x ? .reverse : .forward
    }

    private func targetCoordinate(
        from sourceCoordinate: PlayerCoordinate,
        for navigation: VisionPlayerPageNavigation
    ) -> PlayerCoordinate {
        playerModel.coordinate(
            adjacentTo: sourceCoordinate,
            offset: navigation.offset
        )
    }

    private func adjacentPage(
        from viewController: UIViewController,
        navigation: VisionPlayerPageNavigation
    ) -> UIViewController? {
        guard let sourcePage = viewController as? VisionPlayerPageHostController else { return nil }
        let targetCoordinate = targetCoordinate(from: sourcePage.coordinate, for: navigation)
        guard playerModel.canRender(targetCoordinate) else { return nil }
        return makePage(
            coordinate: targetCoordinate,
            preferredPrefetchDirection: navigation.prefetchDirection,
            ownsDownloadableMediaWindow: false
        )
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        adjacentPage(from: viewController, navigation: .back)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        adjacentPage(from: viewController, navigation: .forward)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        guard let pendingPage = pendingViewControllers.first as? VisionPlayerPageHostController else { return }
        pendingPage.setOwnsDownloadableMediaWindow(true, forceRefresh: true)
        transitionDestinationPage = pendingPage
        isTransitioning = true
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        let destinationPage = transitionDestinationPage
        transitionDestinationPage = nil

        if completed, let currentPage {
            previousViewControllers.forEach {
                resetZoomForInactivePage($0)
                markPageAsNotOwningDownloadableMediaWindow($0)
            }
            playerModel.display(
                coordinate: currentPage.coordinate,
                direction: currentPage.preferredPrefetchDirection
            )
        } else {
            markPageAsNotOwningDownloadableMediaWindow(destinationPage)
            refreshCurrentDownloadableMediaWindow()
        }
        finishTransition()
    }

    private var pagingScrollViews: [UIScrollView] {
        view.subviews.compactMap { $0 as? UIScrollView }
    }

    private var pagingPanGestures: [UIPanGestureRecognizer] {
        pagingScrollViews.map(\.panGestureRecognizer)
    }

    private func configurePagingScrollViews() {
        pagingScrollViews.forEach { scrollView in
            let panGesture = scrollView.panGestureRecognizer
            let panGestureId = ObjectIdentifier(panGesture)
            if configuredPagingPanGestures[panGestureId] == nil {
                panGesture.addTarget(self, action: #selector(handlePagingPan(_:)))
                configuredPagingPanGestures[panGestureId] = panGesture
            }
        }
        registerPagingPanGesturesWithActivePages()
    }

    private func registerPagingPanGesturesWithActivePages() {
        let gestures = pagingPanGestures
        guard !gestures.isEmpty else { return }

        activePages.forEach { page in
            gestures.forEach { page.registerPagingPanGesture($0) }
        }
    }

    private var activePages: [VisionPlayerPageHostController] {
        var pages = [VisionPlayerPageHostController]()
        func append(_ page: VisionPlayerPageHostController?) {
            guard let page,
                  !pages.contains(where: { $0 === page }) else {
                return
            }
            pages.append(page)
        }

        append(currentPage)
        append(transitionDestinationPage)
        viewControllers?
            .compactMap { $0 as? VisionPlayerPageHostController }
            .forEach { append($0) }
        return pages
    }

    @objc private func handlePagingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginZoomedPagingPanIfNeeded(gesture)

        case .changed:
            updateZoomedPagingPanLock(for: gesture)

        case .ended, .cancelled, .failed:
            endZoomedPagingPan(gesture)

        default:
            break
        }
    }

    private func beginZoomedPagingPanIfNeeded(_ gesture: UIPanGestureRecognizer) {
        guard currentPage?.isZoomed == true,
              let scrollView = pagingScrollView(for: gesture) else {
            return
        }

        let gestureId = ObjectIdentifier(gesture)
        zoomedPagingPanRestingOffsets[gestureId] = scrollView.contentOffset.x
        unlockedZoomedPagingPanGestures.remove(gestureId)
    }

    private func updateZoomedPagingPanLock(for gesture: UIPanGestureRecognizer) {
        guard let currentPage,
              currentPage.isZoomed,
              let scrollView = pagingScrollView(for: gesture) else {
            return
        }

        let gestureId = ObjectIdentifier(gesture)
        let restingOffsetX = zoomedPagingPanRestingOffsets[gestureId] ?? scrollView.contentOffset.x
        guard !unlockedZoomedPagingPanGestures.contains(gestureId) else { return }

        if currentPage.allowsPagingPanFromCurrentZoomEdge(gesture) {
            scrollView.contentOffset.x = restingOffsetX
            gesture.setTranslation(.zero, in: view)
            zoomedPagingPanRestingOffsets[gestureId] = scrollView.contentOffset.x
            unlockedZoomedPagingPanGestures.insert(gestureId)
        } else {
            scrollView.contentOffset.x = restingOffsetX
        }
    }

    private func endZoomedPagingPan(_ gesture: UIPanGestureRecognizer) {
        let gestureId = ObjectIdentifier(gesture)
        zoomedPagingPanRestingOffsets.removeValue(forKey: gestureId)
        unlockedZoomedPagingPanGestures.remove(gestureId)
    }

    private func pagingScrollView(for gesture: UIPanGestureRecognizer) -> UIScrollView? {
        if let scrollView = gesture.view as? UIScrollView {
            return scrollView
        }

        return pagingScrollViews.first { $0.panGestureRecognizer === gesture }
    }

    private func resetZoomForInactivePage(_ viewController: UIViewController?) {
        guard let page = viewController as? VisionPlayerPageHostController,
              page !== currentPage else {
            return
        }

        page.resetZoomForReuse()
    }

    private func markPageAsNotOwningDownloadableMediaWindow(_ viewController: UIViewController?) {
        guard let page = viewController as? VisionPlayerPageHostController,
              page !== currentPage else {
            return
        }

        page.setOwnsDownloadableMediaWindow(false)
    }
}

private final class VisionPlayerPageHostController: UIViewController, UIScrollViewDelegate {

    private static let maximumCachedVideoSizeCount = 24

    private let playerModel: VisionPlayerModel
    private let zoomScrollView = VisionPlayerZoomScrollView()
    private let zoomContentView = UIView()
    private lazy var hostingController: UIHostingController<VisionPlayerPageHostView> = {
        UIHostingController(rootView: makeRootView())
    }()
    private var renderGeneration = 0
    private var mediaRefreshGeneration = 0
    private var zoomContentLayout: VisionPlayerZoomContentLayout = .viewport
    private var laidOutZoomViewportSize: CGSize = .zero
    private var currentVideoSizeRequest: VisionVideoSizeRequest?
    private var videoSizeLoad: VisionVideoSizeLoad?
    private var cachedVideoSizes = [VisionVideoSizeRequest: CGSize]()
    private var cachedVideoSizeRequests = [VisionVideoSizeRequest]()
    private(set) var coordinate: PlayerCoordinate
    private(set) var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    private(set) var ownsDownloadableMediaWindow: Bool
    var isZoomed: Bool {
        zoomScrollView.isZoomed
    }

    init(
        playerModel: VisionPlayerModel,
        coordinate: PlayerCoordinate,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection,
        ownsDownloadableMediaWindow: Bool
    ) {
        self.playerModel = playerModel
        self.coordinate = coordinate
        self.preferredPrefetchDirection = preferredPrefetchDirection
        self.ownsDownloadableMediaWindow = ownsDownloadableMediaWindow
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .black
    }

    deinit {
        cancelVideoSizeLoad()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureZoomScrollView()
        installHostingController()
        installTapGestures()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        if laidOutZoomViewportSize != viewportSize {
            laidOutZoomViewportSize = viewportSize
            if isZoomed {
                resetZoom(animated: false)
            }
            updateZoomContentFrame(resetOffset: true)
        } else {
            updateZoomContentInsets()
            clampZoomContentOffsetIfNeeded()
        }
    }

    func update(
        coordinate: PlayerCoordinate,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection,
        ownsDownloadableMediaWindow: Bool = true,
        forceRefresh: Bool = false
    ) {
        let didBecomeDownloadableMediaWindowOwner = !self.ownsDownloadableMediaWindow && ownsDownloadableMediaWindow
        guard forceRefresh
                || self.coordinate != coordinate
                || self.preferredPrefetchDirection != preferredPrefetchDirection
                || self.ownsDownloadableMediaWindow != ownsDownloadableMediaWindow else {
            return
        }

        if forceRefresh || self.coordinate != coordinate {
            clearVideoZoomContentLayout()
            resetZoomForReuse()
            setZoomContentLayout(.viewport)
        }
        self.coordinate = coordinate
        self.preferredPrefetchDirection = preferredPrefetchDirection
        self.ownsDownloadableMediaWindow = ownsDownloadableMediaWindow
        if forceRefresh || didBecomeDownloadableMediaWindowOwner {
            renderGeneration += 1
        }
        updateHostedRootView()
    }

    private func updateHostedRootView() {
        hostingController.rootView = makeRootView()
    }

    private func makeRootView() -> VisionPlayerPageHostView {
        VisionPlayerPageHostView(
            token: playerModel.token(for: coordinate),
            context: playerModel.context(for: coordinate),
            ownerId: playerModel.id,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow,
            renderGeneration: renderGeneration,
            mediaRefreshGeneration: mediaRefreshGeneration,
            onZoomContentLayoutChange: { [weak self] layout, generation in
                self?.setZoomContentLayout(layout, from: generation)
            },
            onVideoZoomContentLayoutRequest: { [weak self] descriptor, fileURL, generation in
                self?.requestVideoZoomContentLayout(
                    descriptor: descriptor,
                    fileURL: fileURL,
                    from: generation
                )
            }
        )
    }

    func setOwnsDownloadableMediaWindow(
        _ ownsDownloadableMediaWindow: Bool,
        forceRefresh: Bool = false
    ) {
        update(
            coordinate: coordinate,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow,
            forceRefresh: forceRefresh
        )
    }

    func registerPagingPanGesture(_ panGesture: UIPanGestureRecognizer) {
        zoomScrollView.registerPagingPanGesture(panGesture)
    }

    func allowsPagingPanFromCurrentZoomEdge(_ panGesture: UIPanGestureRecognizer) -> Bool {
        zoomScrollView.allowsPagingPanFromCurrentZoomEdge(panGesture)
    }

    func resetZoomForReuse() {
        resetZoom(animated: false)
    }

    func refreshDownloadableMediaWindow() {
        guard ownsDownloadableMediaWindow else { return }
        mediaRefreshGeneration += 1
        updateHostedRootView()
    }

    private func configureZoomScrollView() {
        zoomScrollView.delegate = self
        zoomScrollView.minimumZoomScale = 1
        zoomScrollView.maximumZoomScale = VisionPlayerZoomTuning.maximumScale
        zoomScrollView.bounces = true
        zoomScrollView.bouncesZoom = true
        zoomScrollView.showsHorizontalScrollIndicator = false
        zoomScrollView.showsVerticalScrollIndicator = false
        zoomScrollView.contentInsetAdjustmentBehavior = .never
        zoomScrollView.backgroundColor = .black
        zoomContentView.backgroundColor = .black

        zoomScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomScrollView)
        zoomScrollView.addSubview(zoomContentView)

        NSLayoutConstraint.activate([
            zoomScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        updateZoomContentFrame(resetOffset: true)
        updateZoomInteraction()
    }

    private func installHostingController() {
        addChild(hostingController)
        hostingController.view.backgroundColor = .black
        hostingController.view.isUserInteractionEnabled = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        zoomContentView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: zoomContentView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: zoomContentView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: zoomContentView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: zoomContentView.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func installTapGestures() {
        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTapRecognizer)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        toggleZoom(at: gesture.location(in: view), in: view)
    }

    private func toggleZoom(at location: CGPoint, in coordinateView: UIView) {
        guard isViewLoaded else { return }
        guard zoomScrollView.bounds.width > 0, zoomScrollView.bounds.height > 0 else { return }

        if isZoomed {
            resetZoom(animated: true)
            return
        }

        applyCachedCurrentVideoSizeIfAvailable()

        let locationInContent = coordinateView.convert(location, to: zoomContentView)
        let targetScale = min(
            VisionPlayerZoomTuning.doubleTapScale,
            zoomScrollView.maximumZoomScale
        )
        let zoomSize = CGSize(
            width: zoomScrollView.bounds.width / targetScale,
            height: zoomScrollView.bounds.height / targetScale
        )
        let allowedContentRect = zoomAllowedContentRect()
        let zoomOrigin = CGPoint(
            x: boundedZoomOrigin(
                centeredAt: locationInContent.x,
                zoomLength: zoomSize.width,
                allowedMin: allowedContentRect.minX,
                allowedMax: allowedContentRect.maxX
            ),
            y: boundedZoomOrigin(
                centeredAt: locationInContent.y,
                zoomLength: zoomSize.height,
                allowedMin: allowedContentRect.minY,
                allowedMax: allowedContentRect.maxY
            )
        )
        let zoomRect = CGRect(origin: zoomOrigin, size: zoomSize)
        zoomScrollView.zoom(to: zoomRect, animated: true)
    }

    private func resetZoom(animated: Bool) {
        guard isViewLoaded else { return }
        guard zoomScrollView.zoomScale != zoomScrollView.minimumZoomScale else {
            updateZoomInteraction()
            return
        }

        zoomScrollView.setZoomScale(zoomScrollView.minimumZoomScale, animated: animated)
        if !animated {
            updateZoomContentInsets()
            zoomScrollView.contentOffset = centeredZoomContentOffset
            updateZoomInteraction()
        }
    }

    private func setZoomContentLayout(
        _ layout: VisionPlayerZoomContentLayout,
        from generation: Int
    ) {
        guard generation == renderGeneration else { return }

        clearVideoZoomContentLayout()
        setZoomContentLayout(layout)
    }

    private func setZoomContentLayout(_ layout: VisionPlayerZoomContentLayout) {
        guard zoomContentLayout != layout else { return }

        zoomContentLayout = layout
        resetZoom(animated: false)
        updateZoomContentFrame(resetOffset: true)
    }

    private func updateZoomContentFrame(resetOffset: Bool) {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let contentSize = zoomContentSize(fitting: viewportSize)
        if !zoomScrollView.isZoomed {
            zoomContentView.transform = .identity
            zoomContentView.frame = CGRect(origin: .zero, size: contentSize)
            zoomScrollView.contentSize = contentSize
        }

        updateZoomContentInsets()
        if resetOffset {
            zoomScrollView.contentOffset = centeredZoomContentOffset
        } else {
            clampZoomContentOffsetIfNeeded()
        }
    }

    private func zoomContentSize(fitting viewportSize: CGSize) -> CGSize {
        switch zoomContentLayout {
        case .viewport:
            return viewportSize

        case .intrinsicMediaSize(let imageSize):
            guard imageSize.width > 0, imageSize.height > 0 else { return viewportSize }

            let scale = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
            return CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
        }
    }

    private func updateZoomContentInsets() {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let offsetRanges = zoomContentOffsetRanges()
        let contentSize = zoomScrollView.contentSize
        let contentInset = UIEdgeInsets(
            top: -offsetRanges.y.lowerBound,
            left: -offsetRanges.x.lowerBound,
            bottom: offsetRanges.y.upperBound - (contentSize.height - viewportSize.height),
            right: offsetRanges.x.upperBound - (contentSize.width - viewportSize.width)
        )

        if zoomScrollView.contentInset != contentInset {
            zoomScrollView.contentInset = contentInset
        }
    }

    private var centeredZoomContentOffset: CGPoint {
        let offsetRanges = zoomContentOffsetRanges()
        return CGPoint(
            x: offsetRanges.x.lowerBound,
            y: offsetRanges.y.lowerBound
        )
    }

    private func clampZoomContentOffsetIfNeeded() {
        let offsetRanges = zoomContentOffsetRanges()
        let clampedOffset = CGPoint(
            x: min(max(zoomScrollView.contentOffset.x, offsetRanges.x.lowerBound), offsetRanges.x.upperBound),
            y: min(max(zoomScrollView.contentOffset.y, offsetRanges.y.lowerBound), offsetRanges.y.upperBound)
        )

        if zoomScrollView.contentOffset != clampedOffset {
            zoomScrollView.contentOffset = clampedOffset
        }
    }

    private func zoomContentOffsetRanges() -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return (x: 0...0, y: 0...0)
        }

        let scale = zoomScrollView.zoomScale
        let allowedContentRect = zoomAllowedContentRect()
        return (
            x: zoomContentOffsetRange(
                allowedMin: allowedContentRect.minX * scale,
                allowedMax: allowedContentRect.maxX * scale,
                viewportLength: viewportSize.width
            ),
            y: zoomContentOffsetRange(
                allowedMin: allowedContentRect.minY * scale,
                allowedMax: allowedContentRect.maxY * scale,
                viewportLength: viewportSize.height
            )
        )
    }

    private func zoomContentOffsetRange(
        allowedMin: CGFloat,
        allowedMax: CGFloat,
        viewportLength: CGFloat
    ) -> ClosedRange<CGFloat> {
        let contentLength = max(allowedMax - allowedMin, 0)
        guard contentLength > viewportLength else {
            let centeredOffset = (allowedMin + allowedMax - viewportLength) / 2
            return centeredOffset...centeredOffset
        }

        return allowedMin...(allowedMax - viewportLength)
    }

    private func zoomAllowedContentRect() -> CGRect {
        let contentBounds = CGRect(origin: .zero, size: zoomContentView.bounds.size)
        guard contentBounds.width > 0, contentBounds.height > 0 else { return .zero }
        return contentBounds
    }

    private func boundedZoomOrigin(
        centeredAt center: CGFloat,
        zoomLength: CGFloat,
        allowedMin: CGFloat,
        allowedMax: CGFloat
    ) -> CGFloat {
        let clampedCenter = min(max(center, allowedMin), allowedMax)
        let contentLength = allowedMax - allowedMin
        guard contentLength > zoomLength else {
            return (allowedMin + allowedMax - zoomLength) / 2
        }

        return min(max(clampedCenter - zoomLength / 2, allowedMin), allowedMax - zoomLength)
    }

    private func updateZoomInteraction() {
        let shouldActivateZoomInteraction = isZoomed
        if zoomScrollView.panGestureRecognizer.isEnabled != shouldActivateZoomInteraction {
            zoomScrollView.panGestureRecognizer.isEnabled = shouldActivateZoomInteraction
        }
    }

    private func requestVideoZoomContentLayout(
        descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL,
        from generation: Int
    ) {
        guard generation == renderGeneration else { return }

        let request = VisionVideoSizeRequest(fileURL: fileURL, descriptor: descriptor)
        currentVideoSizeRequest = request

        if let videoSizeLoad, videoSizeLoad.request != request {
            cancelVideoSizeLoad()
        }

        if let cachedSize = cachedVideoSizes[request] {
            applyVideoSizeIfCurrent(cachedSize, for: request)
            return
        }

        setZoomContentLayout(.viewport)
        guard videoSizeLoad == nil else { return }

        let task = Task.detached(priority: .utility) { [fileURL, request] in
            let size = await VisionVideoAssetLayout.displaySize(at: fileURL)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard !Task.isCancelled,
                      let self,
                      self.videoSizeLoad?.request == request else {
                    return
                }

                self.videoSizeLoad = nil
                guard let size else { return }

                self.cacheVideoSize(size, for: request)
                self.applyVideoSizeIfCurrent(size, for: request)
            }
        }

        videoSizeLoad = VisionVideoSizeLoad(request: request, task: task)
    }

    private func cacheVideoSize(_ size: CGSize, for request: VisionVideoSizeRequest) {
        if cachedVideoSizes[request] == nil {
            cachedVideoSizeRequests.append(request)
        }
        cachedVideoSizes[request] = size

        while cachedVideoSizeRequests.count > Self.maximumCachedVideoSizeCount {
            let removedRequest = cachedVideoSizeRequests.removeFirst()
            cachedVideoSizes.removeValue(forKey: removedRequest)
        }
    }

    private func applyCachedCurrentVideoSizeIfAvailable() {
        guard let currentVideoSizeRequest,
              let cachedSize = cachedVideoSizes[currentVideoSizeRequest] else {
            return
        }

        applyVideoSizeIfCurrent(cachedSize, for: currentVideoSizeRequest)
    }

    private func applyVideoSizeIfCurrent(_ size: CGSize, for request: VisionVideoSizeRequest) {
        guard currentVideoSizeRequest == request,
              DownloadableMediaCache.shared.localFileURL(for: request.descriptor) == request.fileURL,
              request.matchesCurrentFileVersion(),
              !zoomScrollView.isZoomed,
              !zoomScrollView.isZooming else {
            return
        }

        setZoomContentLayout(.intrinsicMediaSize(size))
    }

    private func clearVideoZoomContentLayout() {
        currentVideoSizeRequest = nil
        cancelVideoSizeLoad()
    }

    private func cancelVideoSizeLoad() {
        videoSizeLoad?.task.cancel()
        videoSizeLoad = nil
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomContentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateZoomContentInsets()
        clampZoomContentOffsetIfNeeded()
        updateZoomInteraction()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= scrollView.minimumZoomScale + VisionPlayerZoomTuning.resetTolerance {
            resetZoom(animated: true)
        } else {
            updateZoomContentInsets()
            clampZoomContentOffsetIfNeeded()
            updateZoomInteraction()
        }
    }

}

private final class VisionPlayerZoomScrollView: UIScrollView {

    private var pagingPanGestureRecognizerIds = Set<ObjectIdentifier>()
    var isZoomed: Bool {
        zoomScale > minimumZoomScale + VisionPlayerZoomTuning.resetTolerance
    }

    func registerPagingPanGesture(_ panGesture: UIPanGestureRecognizer) {
        pagingPanGestureRecognizerIds.insert(ObjectIdentifier(panGesture))
    }

    func allowsPagingPanFromCurrentZoomEdge(_ panGesture: UIPanGestureRecognizer) -> Bool {
        guard isZoomed else { return false }

        let velocity = panGesture.velocity(in: self)
        let isHorizontalPan = abs(velocity.x) > abs(velocity.y) * VisionPlayerZoomTuning.horizontalIntentRatio
        guard isHorizontalPan else { return false }

        if velocity.x > 0 {
            return isAtLeftContentEdge
        } else if velocity.x < 0 {
            return isAtRightContentEdge
        } else {
            return false
        }
    }

    @objc func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard isZoomed else { return false }

        return gestureRecognizer === panGestureRecognizer && isPagingPanGesture(otherGestureRecognizer)
            || otherGestureRecognizer === panGestureRecognizer && isPagingPanGesture(gestureRecognizer)
    }

    private func isPagingPanGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }

        return pagingPanGestureRecognizerIds.contains(ObjectIdentifier(panGesture))
    }

    private var isAtLeftContentEdge: Bool {
        contentOffset.x <= minimumContentOffsetX + VisionPlayerZoomTuning.edgePaginationTolerance
    }

    private var isAtRightContentEdge: Bool {
        contentOffset.x >= maximumContentOffsetX - VisionPlayerZoomTuning.edgePaginationTolerance
    }

    private var minimumContentOffsetX: CGFloat {
        -adjustedContentInset.left
    }

    private var maximumContentOffsetX: CGFloat {
        max(minimumContentOffsetX, contentSize.width - bounds.width + adjustedContentInset.right)
    }
}

private struct VisionPlayerPageHostView: View {

    let token: GeneratedToken
    let context: PlayerTokenContext?
    let ownerId: UUID
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    let ownsDownloadableMediaWindow: Bool
    let renderGeneration: Int
    let mediaRefreshGeneration: Int
    let onZoomContentLayoutChange: (VisionPlayerZoomContentLayout, Int) -> Void
    let onVideoZoomContentLayoutRequest: (CollectionCatalogDownloadableMediaDescriptor, URL, Int) -> Void

    var body: some View {
        VisionPlayerMediaView(
            token: token,
            context: context,
            ownerId: ownerId,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow,
            mediaRefreshGeneration: mediaRefreshGeneration,
            layoutGeneration: renderGeneration,
            onZoomContentLayoutChange: onZoomContentLayoutChange,
            onVideoZoomContentLayoutRequest: onVideoZoomContentLayoutRequest
        )
        .id(renderGeneration)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct VisionPlayerMediaView: View {

    private static let htmlDocumentRenderQueue = DispatchQueue(
        label: "org.lil.nft-folder.vision-html-document-render",
        qos: .userInitiated
    )

    let token: GeneratedToken
    let context: PlayerTokenContext?
    let ownerId: UUID
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    let ownsDownloadableMediaWindow: Bool
    let mediaRefreshGeneration: Int
    let layoutGeneration: Int
    let onZoomContentLayoutChange: (VisionPlayerZoomContentLayout, Int) -> Void
    let onVideoZoomContentLayoutRequest: (CollectionCatalogDownloadableMediaDescriptor, URL, Int) -> Void

    @State private var staticImage: UIImage?
    @State private var staticImageDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var localWebContent: VisionWebContent?
    @State private var localWebContentDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var fallbackHTMLDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var pendingHTMLDocumentRender: VisionHTMLDocumentRenderRequest?
    @State private var cancelActiveLoad: (() -> Void)?

    var body: some View {
        content
            .onAppear(perform: renderCurrentContent)
            .onChange(of: renderKey) {
                renderCurrentContent()
            }
            .onChange(of: mediaRefreshGeneration) {
                renderCurrentContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadableMediaCacheFileAvailabilityDidChange)) { _ in
                renderAvailableContent()
            }
            .onDisappear(perform: cleanup)
    }

    @ViewBuilder
    private var content: some View {
        if let descriptor = downloadableMediaDescriptor {
            if descriptor.isStaticImage,
               staticImageDescriptor == descriptor,
               let staticImage {
                Image(uiImage: staticImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else if !descriptor.isStaticImage,
                      localWebContentDescriptor == descriptor,
                      let localWebContent {
                VisionWebView(
                    content: localWebContent,
                    onLocalLoadFailure: {
                        handleLocalWebContentLoadFailure(for: descriptor)
                    }
                )
            } else if fallbackHTMLDescriptor == descriptor {
                VisionWebView(htmlString: token.html)
            } else {
                Color.black
            }
        } else {
            VisionWebView(htmlString: token.html)
        }
    }

    private var renderKey: VisionPlayerRenderKey {
        VisionPlayerRenderKey(
            collectionId: context?.collectionId ?? token.fullCollectionId,
            tokenId: token.id,
            context: context,
            media: token.media,
            preferredPrefetchDirection: preferredPrefetchDirection
        )
    }

    private var downloadableMediaDescriptor: CollectionCatalogDownloadableMediaDescriptor? {
        CollectionCatalog.downloadableMediaDescriptor(for: context)
    }

    private func renderCurrentContent() {
        renderCurrentContent(shouldPrepareWindow: true)
    }

    private func renderAvailableContent() {
        renderCurrentContent(shouldPrepareWindow: false)
    }

    private func renderCurrentContent(shouldPrepareWindow: Bool) {
        let descriptor = shouldPrepareWindow
            ? prepareCurrentDownloadableMediaWindow()
            : downloadableMediaDescriptor

        guard let descriptor else {
            cleanup()
            return
        }

        if descriptor.isStaticImage {
            renderStaticImage(descriptor)
        } else {
            renderLocalWebMedia(descriptor)
        }
    }

    private func prepareCurrentDownloadableMediaWindow() -> CollectionCatalogDownloadableMediaDescriptor? {
        guard ownsDownloadableMediaWindow else {
            return downloadableMediaDescriptor
        }

        let cache = DownloadableMediaCache.shared
        guard let descriptor = cache.prepareWindow(
            for: context,
            ownerId: ownerId,
            direction: preferredPrefetchDirection
        ) else {
            cache.clearActiveWindow(ownerId: ownerId)
            return nil
        }

        return descriptor
    }

    private func renderStaticImage(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        guard staticImageDescriptor != descriptor || staticImage == nil else { return }

        localWebContent = nil
        localWebContentDescriptor = nil
        pendingHTMLDocumentRender = nil

        if staticImageDescriptor != descriptor {
            cancelActiveLoad?()
            cancelActiveLoad = nil
            staticImage = nil
            staticImageDescriptor = descriptor
            updateZoomContentLayout(.viewport)
            clearDownloadableMediaFallback()
        }

        if let cachedImage = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            cancelActiveLoad?()
            cancelActiveLoad = nil
            clearDownloadableMediaFallback()
            staticImage = cachedImage
            staticImageDescriptor = descriptor
            updateZoomContentLayout(.intrinsicMediaSize(cachedImage.size))
            return
        }

        guard cancelActiveLoad == nil else { return }

        cancelActiveLoad = DownloadableMediaCache.shared.loadImage(for: descriptor) { image in
            cancelActiveLoad = nil
            guard staticImageDescriptor == descriptor else {
                return
            }
            guard let image else {
                renderDownloadableMediaFallback(for: descriptor)
                return
            }

            clearDownloadableMediaFallback()
            staticImage = image
            updateZoomContentLayout(.intrinsicMediaSize(image.size))
        }
    }

    private func renderLocalWebMedia(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        staticImage = nil
        staticImageDescriptor = nil

        if localWebContentDescriptor == descriptor,
           localWebContent != nil {
            if case .html = descriptor.media {
                return
            }
            updateLocalWebZoomContentLayoutIfAvailable(for: descriptor)
            return
        }

        if localWebContentDescriptor != descriptor {
            cancelActiveLoad?()
            cancelActiveLoad = nil
            localWebContent = nil
            localWebContentDescriptor = descriptor
            pendingHTMLDocumentRender = nil
            updateZoomContentLayout(.viewport)
            clearDownloadableMediaFallback()
        }

        let cache = DownloadableMediaCache.shared
        guard let localFileURL = cache.localFileURL(for: descriptor) else {
            guard cancelActiveLoad == nil else { return }
            cancelActiveLoad = cache.loadFile(for: descriptor) { fileURL in
                cancelActiveLoad = nil
                guard localWebContentDescriptor == descriptor else {
                    return
                }
                guard let fileURL else {
                    renderDownloadableMediaFallback(for: descriptor)
                    return
                }

                setLocalWebContent(
                    for: descriptor,
                    fileURL: fileURL,
                    nextLocalFileURL: adjacentLocalFileURL(for: descriptor)
                )
            }
            return
        }

        if pendingHTMLDocumentRender == VisionHTMLDocumentRenderRequest(
            descriptor: descriptor,
            fileURL: localFileURL
        ) {
            return
        }

        cancelActiveLoad?()
        cancelActiveLoad = nil
        setLocalWebContent(
            for: descriptor,
            fileURL: localFileURL,
            nextLocalFileURL: adjacentLocalFileURL(for: descriptor)
        )
    }

    private func setLocalWebContent(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL,
        nextLocalFileURL: URL?
    ) {
        if case .html = descriptor.media {
            renderLocalHTMLDocument(for: descriptor, fileURL: fileURL)
            return
        }

        pendingHTMLDocumentRender = nil
        updateLocalWebZoomContentLayout(for: descriptor, fileURL: fileURL)
        guard let content = localWebContent(
            for: descriptor,
            fileURL: fileURL,
            nextLocalFileURL: nextLocalFileURL
        ) else {
            localWebContent = nil
            renderDownloadableMediaFallback(for: descriptor)
            return
        }

        clearDownloadableMediaFallback()
        localWebContentDescriptor = descriptor
        localWebContent = content
    }

    private func renderLocalHTMLDocument(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL
    ) {
        let request = VisionHTMLDocumentRenderRequest(descriptor: descriptor, fileURL: fileURL)
        guard pendingHTMLDocumentRender != request else { return }

        pendingHTMLDocumentRender = request
        localWebContent = nil
        updateZoomContentLayout(.viewport)
        clearDownloadableMediaFallback()

        let htmlDirectoryURL = DownloadableMediaCache.shared.webViewHTMLDirectoryURL

        Self.htmlDocumentRenderQueue.async {
            let baseURL = DownloadableMediaCache.shared.downloadedSourceURL(for: descriptor).absoluteString
            let renderedDocument = (try? String(contentsOf: fileURL, encoding: .utf8)).map { documentHTML in
                let viewportSize = DownloadableTokenHTMLLayout.rootSVGViewBoxSize(in: documentHTML)

                return (
                    content: VisionWebContent.localHTML(
                        string: DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                            documentHTML: documentHTML,
                            baseURL: baseURL,
                            contentSize: viewportSize
                        ),
                        htmlDirectoryURL: htmlDirectoryURL,
                        readAccessURL: htmlDirectoryURL
                    ),
                    viewportSize: viewportSize
                )
            }

            DispatchQueue.main.async {
                guard pendingHTMLDocumentRender == request,
                      localWebContentDescriptor == descriptor else {
                    return
                }

                pendingHTMLDocumentRender = nil
                guard let renderedDocument else {
                    localWebContent = nil
                    renderDownloadableMediaFallback(for: descriptor)
                    return
                }

                if let viewportSize = renderedDocument.viewportSize {
                    updateZoomContentLayout(.intrinsicMediaSize(viewportSize))
                } else {
                    updateZoomContentLayout(.viewport)
                }
                clearDownloadableMediaFallback()
                localWebContent = renderedDocument.content
            }
        }
    }

    private func localWebContent(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL,
        nextLocalFileURL: URL?
    ) -> VisionWebContent? {
        let cache = DownloadableMediaCache.shared
        let html: String
        let readAccessURL: URL

        switch descriptor.media {
        case .staticImage:
            return nil
        case .animatedImage:
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: fileURL.absoluteString,
                nextImageURL: nextLocalFileURL?.absoluteString
            )
            readAccessURL = cache.webViewReadAccessURL
        case .video:
            html = DownloadableTokenHTML.createVideoHTML(videoURL: fileURL.absoluteString)
            readAccessURL = cache.webViewReadAccessURL
        case .html:
            return nil
        }

        return .localHTML(
            string: html,
            htmlDirectoryURL: cache.webViewHTMLDirectoryURL,
            readAccessURL: readAccessURL
        )
    }

    private func updateLocalWebZoomContentLayoutIfAvailable(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        guard let fileURL = DownloadableMediaCache.shared.localFileURL(for: descriptor) else {
            updateZoomContentLayout(.viewport)
            return
        }

        updateLocalWebZoomContentLayout(for: descriptor, fileURL: fileURL)
    }

    private func updateLocalWebZoomContentLayout(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL
    ) {
        switch descriptor.media {
        case .staticImage:
            updateZoomContentLayout(.viewport)

        case .animatedImage:
            if let imageSize = imageOrSVGSize(at: fileURL) {
                updateZoomContentLayout(.intrinsicMediaSize(imageSize))
            } else {
                updateZoomContentLayout(.viewport)
            }

        case .video:
            requestVideoZoomContentLayout(for: descriptor, fileURL: fileURL)

        case .html:
            updateZoomContentLayout(.viewport)
        }
    }

    private func imageOrSVGSize(at fileURL: URL) -> CGSize? {
        if let imageSize = imageSize(at: fileURL) {
            return imageSize
        }

        guard let documentHTML = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        return DownloadableTokenHTMLLayout.rootSVGViewBoxSize(in: documentHTML)
    }

    private func imageSize(at fileURL: URL) -> CGSize? {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        let size = CGSize(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue))
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    private func requestVideoZoomContentLayout(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL
    ) {
        onVideoZoomContentLayoutRequest(descriptor, fileURL, layoutGeneration)
    }

    private func adjacentLocalFileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL? {
        guard let context,
              case .animatedImage = descriptor.media,
              let adjacentDescriptor = DownloadableMediaCache.adjacentDescriptor(
                for: context,
                direction: preferredPrefetchDirection
              ) else {
            return nil
        }

        return DownloadableMediaCache.shared.localFileURL(for: adjacentDescriptor)
    }

    private func handleLocalWebContentLoadFailure(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        guard localWebContentDescriptor == descriptor,
              downloadableMediaDescriptor == descriptor else {
            return
        }

        localWebContent = nil
        pendingHTMLDocumentRender = nil
        renderDownloadableMediaFallback(for: descriptor)
    }

    private func clearDownloadableMediaFallback() {
        fallbackHTMLDescriptor = nil
    }

    private func renderDownloadableMediaFallback(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        guard downloadableMediaDescriptor == descriptor else {
            return
        }

        updateZoomContentLayout(.viewport)
        fallbackHTMLDescriptor = descriptor
    }

    private func updateZoomContentLayout(_ layout: VisionPlayerZoomContentLayout) {
        onZoomContentLayoutChange(layout, layoutGeneration)
    }

    private func cleanup() {
        cancelActiveLoad?()
        cancelActiveLoad = nil
        staticImage = nil
        staticImageDescriptor = nil
        localWebContent = nil
        localWebContentDescriptor = nil
        fallbackHTMLDescriptor = nil
        pendingHTMLDocumentRender = nil
        updateZoomContentLayout(.viewport)
    }

}

private struct VisionPlayerRenderKey: Hashable {
    let collectionId: String
    let tokenId: String
    let context: PlayerTokenContext?
    let media: GeneratedTokenMedia?
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
}

private struct VisionHTMLDocumentRenderRequest: Hashable {
    let descriptor: CollectionCatalogDownloadableMediaDescriptor
    let fileURL: URL
}

private struct VisionVideoSizeRequest: Hashable {
    let descriptor: CollectionCatalogDownloadableMediaDescriptor
    let fileURL: URL
    let fileSize: Int?
    let contentModificationDate: Date?

    init(fileURL: URL, descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        let resourceValues = try? fileURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        self.descriptor = descriptor
        self.fileURL = fileURL
        self.fileSize = resourceValues?.fileSize
        self.contentModificationDate = resourceValues?.contentModificationDate
    }

    func matchesCurrentFileVersion() -> Bool {
        Self(fileURL: fileURL, descriptor: descriptor) == self
    }
}

private struct VisionVideoSizeLoad {
    let request: VisionVideoSizeRequest
    let task: Task<Void, Never>
}

private enum VisionVideoAssetLayout {
    static func displaySize(at fileURL: URL) async -> CGSize? {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }

        async let naturalSize = track.load(.naturalSize)
        async let preferredTransform = track.load(.preferredTransform)

        guard let (loadedNaturalSize, loadedPreferredTransform) = try? await (naturalSize, preferredTransform) else {
            return nil
        }

        let transformedSize = loadedNaturalSize.applying(loadedPreferredTransform)
        let size = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }
}

enum VisionPlayerPrewarmer {

    static func scheduleAfterLaunch(initialCollectionIds: [String]) {
        VisionPlayerWebView.scheduleFirstUsePrewarm()
        PlayerTokenPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: nil,
            initialCollectionIds: initialCollectionIds
        )
    }

    static func preparedConfig(
        initialItemId: String?,
        initialTokenId: String? = nil
    ) -> VisionPlayerConfig {
        var config = VisionPlayerConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId
        )
        config.specificToken = PlayerTokenPrewarmer.preparedToken(
            initialCollectionId: initialItemId,
            initialTokenId: initialTokenId
        )
        return config
    }

}
