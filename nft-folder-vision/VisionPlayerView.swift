// ∅ 2026 lil org

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
        VisionPlayerPageHostController(
            playerModel: playerModel,
            coordinate: coordinate,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow
        )
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
                self.refreshCurrentPage()
            }
            self.finishTransition()
        }
        return true
    }

    private func refreshCurrentPage() {
        guard let currentPage else { return }
        currentPage.update(
            coordinate: currentPage.coordinate,
            preferredPrefetchDirection: playerModel.preferredPrefetchDirection,
            forceRefresh: true
        )
    }

    private func finishTransition() {
        let request = queuedNavigationRequest
        queuedNavigationRequest = nil
        isTransitioning = false

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
            previousViewControllers.forEach { markPageAsNotOwningDownloadableMediaWindow($0) }
            playerModel.display(
                coordinate: currentPage.coordinate,
                direction: currentPage.preferredPrefetchDirection
            )
        } else {
            markPageAsNotOwningDownloadableMediaWindow(destinationPage)
            refreshCurrentPage()
        }
        finishTransition()
    }

    private func markPageAsNotOwningDownloadableMediaWindow(_ viewController: UIViewController?) {
        guard let page = viewController as? VisionPlayerPageHostController,
              page !== currentPage else {
            return
        }

        page.setOwnsDownloadableMediaWindow(false)
    }
}

private final class VisionPlayerPageHostController: UIHostingController<VisionPlayerPageHostView> {

    private let playerModel: VisionPlayerModel
    private var renderGeneration = 0
    private(set) var coordinate: PlayerCoordinate
    private(set) var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    private(set) var ownsDownloadableMediaWindow: Bool

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
        super.init(rootView: Self.rootView(
            playerModel: playerModel,
            coordinate: coordinate,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow,
            renderGeneration: 0
        ))
        view.backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
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

        self.coordinate = coordinate
        self.preferredPrefetchDirection = preferredPrefetchDirection
        self.ownsDownloadableMediaWindow = ownsDownloadableMediaWindow
        if forceRefresh || didBecomeDownloadableMediaWindowOwner {
            renderGeneration += 1
        }
        rootView = Self.rootView(
            playerModel: playerModel,
            coordinate: coordinate,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow,
            renderGeneration: renderGeneration
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

    private static func rootView(
        playerModel: VisionPlayerModel,
        coordinate: PlayerCoordinate,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection,
        ownsDownloadableMediaWindow: Bool,
        renderGeneration: Int
    ) -> VisionPlayerPageHostView {
        VisionPlayerPageHostView(
            token: playerModel.token(for: coordinate),
            context: playerModel.context(for: coordinate),
            ownerId: playerModel.id,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow,
            renderGeneration: renderGeneration
        )
    }
}

private struct VisionPlayerPageHostView: View {

    let token: GeneratedToken
    let context: PlayerTokenContext?
    let ownerId: UUID
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    let ownsDownloadableMediaWindow: Bool
    let renderGeneration: Int

    var body: some View {
        VisionPlayerMediaView(
            token: token,
            context: context,
            ownerId: ownerId,
            preferredPrefetchDirection: preferredPrefetchDirection,
            ownsDownloadableMediaWindow: ownsDownloadableMediaWindow
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
            clearDownloadableMediaFallback()
        }

        if let cachedImage = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            cancelActiveLoad?()
            cancelActiveLoad = nil
            clearDownloadableMediaFallback()
            staticImage = cachedImage
            staticImageDescriptor = descriptor
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
        }
    }

    private func renderLocalWebMedia(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        staticImage = nil
        staticImageDescriptor = nil

        if localWebContentDescriptor == descriptor,
           localWebContent != nil {
            return
        }

        if localWebContentDescriptor != descriptor {
            cancelActiveLoad?()
            cancelActiveLoad = nil
            localWebContent = nil
            localWebContentDescriptor = descriptor
            pendingHTMLDocumentRender = nil
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
        clearDownloadableMediaFallback()

        let htmlDirectoryURL = DownloadableMediaCache.shared.webViewHTMLDirectoryURL

        Self.htmlDocumentRenderQueue.async {
            let baseURL = DownloadableMediaCache.shared.downloadedSourceURL(for: descriptor).absoluteString
            let content = (try? String(contentsOf: fileURL, encoding: .utf8)).map { documentHTML in
                let viewportSize = DownloadableTokenHTMLLayout.rootSVGViewBoxSize(in: documentHTML)

                return VisionWebContent.localHTML(
                    string: DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                        documentHTML: documentHTML,
                        baseURL: baseURL,
                        contentSize: viewportSize
                    ),
                    htmlDirectoryURL: htmlDirectoryURL,
                    readAccessURL: htmlDirectoryURL
                )
            }

            DispatchQueue.main.async {
                guard pendingHTMLDocumentRender == request,
                      localWebContentDescriptor == descriptor else {
                    return
                }

                pendingHTMLDocumentRender = nil
                guard let content else {
                    localWebContent = nil
                    renderDownloadableMediaFallback(for: descriptor)
                    return
                }

                clearDownloadableMediaFallback()
                localWebContent = content
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

        fallbackHTMLDescriptor = descriptor
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
