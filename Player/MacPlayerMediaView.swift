// ∅ 2026 lil org

import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import WebKit

struct MacPlayerMediaView: NSViewRepresentable {

    let token: GeneratedToken
    weak var playerMenuDelegate: PlayerMenuDelegate?

    func makeNSView(context: Context) -> MacPlayerMediaContainerView {
        let view = MacPlayerMediaContainerView(playerMenuDelegate: playerMenuDelegate)
        view.render(token)
        return view
    }

    func updateNSView(_ nsView: MacPlayerMediaContainerView, context: Context) {
        nsView.updatePlayerMenuDelegate(playerMenuDelegate)
        nsView.render(token)
    }

    static func dismantleNSView(_ nsView: MacPlayerMediaContainerView, coordinator: ()) {
        nsView.cleanup()
    }
}

enum MacPlayerMediaRenderMode {
    case active
    case transitionDestination
    case preview

    var canDemandLoad: Bool {
        self != .preview
    }

    var managesDownloadWindow: Bool {
        self == .active
    }
}

final class MacPlayerMediaContainerView: NSView {

    private enum ZoomTuning {
        static let minimumScale: CGFloat = 1
        static let maximumScale: CGFloat = 4
        static let doubleTapScale: CGFloat = 2.5
        static let resetTolerance: CGFloat = 0.01
        static let edgePaginationTolerance: CGFloat = 2
        static let horizontalIntentRatio: CGFloat = 1.15
    }

    private enum WebMediaKind {
        case image, video, html
    }

    private enum ZoomContentLayout: Equatable {
        case viewport
        case staticImage(CGSize)
    }

    private enum ZoomAllowedContent: Equatable {
        case fullContent
        case ponchoDrifellaCard
    }

    private struct VideoSizeRequest: Equatable, Hashable {
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
    }

    private struct VideoSizeLoad {
        let request: VideoSizeRequest
        let task: Task<Void, Never>
    }

    private struct WebMediaContext: Equatable {
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let adjacentDescriptor: CollectionCatalogDownloadableMediaDescriptor?
        let fallbackHTML: String
        let mediaKind: WebMediaKind
    }

    private static let maximumCachedVideoSizeCount = 24

    private weak var playerMenuDelegate: PlayerMenuDelegate?
    private let zoomScrollView = MacPlayerZoomScrollView()
    private let zoomContentView = MacPlayerZoomContentView()
    private var imageView: AspectFitImageView?
    private var webView: PlayerWebView?
    private var ponchoDrifellaMetalCardView: PonchoDrifellaMetalCardView?
    private var currentToken: GeneratedToken?
    private var currentTokenContext: PlayerTokenContext?
    private var renderMode: MacPlayerMediaRenderMode?
    private var representedImageKey: AnyHashable?
    private var activeImageLoadId: UUID?
    private var cancelActiveImageLoad: (() -> Void)?
    private var activeFileLoadId: UUID?
    private var cancelActiveFileLoad: (() -> Void)?
    private var webMediaContext: WebMediaContext?
    private var downloadableMediaCacheObserver: NSObjectProtocol?
    private var pendingLocalWebURL: URL?
    private var renderedLocalWebURL: URL?
    private var renderedNextLocalWebURL: URL?
    private var pendingNextLocalWebURL: URL?
    private var webViewMayContainContent = false
    private var laidOutZoomViewportSize: CGSize = .zero
    private var videoSizeLoad: VideoSizeLoad?
    private var cachedVideoSizes = [VideoSizeRequest: CGSize]()
    private var cachedVideoSizeRequests = [VideoSizeRequest]()
    private var isNativeMagnifyGestureActive = false
    private var activeZoomAnimationCount = 0
    private var zoomContentLayout: ZoomContentLayout = .viewport
    private var zoomAllowedContent: ZoomAllowedContent = .fullContent
    private var lastPlayerMenuEventNumber: Int?
    private var lastZoomToggleEventNumber: Int?
    private let downloadableMediaWindowOwnerId = UUID()
    private var activeDownloadableMediaCollectionId: String?
    private let htmlDocumentRenderQueue = DispatchQueue(
        label: "org.lil.nft-folder.mac-html-document-render",
        qos: .userInitiated
    )

    init(playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerMenuDelegate = playerMenuDelegate
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        zoomScrollView.eventDelegate = self
        zoomScrollView.constrainVisibleRect = { [weak self] proposedRect in
            self?.constrainedZoomVisibleRect(proposedRect) ?? proposedRect
        }
        zoomScrollView.drawsBackground = false
        zoomScrollView.hasHorizontalScroller = false
        zoomScrollView.hasVerticalScroller = false
        zoomScrollView.autohidesScrollers = true
        zoomScrollView.borderType = .noBorder
        zoomScrollView.horizontalScrollElasticity = .none
        zoomScrollView.verticalScrollElasticity = .none
        zoomScrollView.allowsMagnification = true
        zoomScrollView.minMagnification = ZoomTuning.minimumScale
        zoomScrollView.maxMagnification = ZoomTuning.maximumScale
        zoomContentView.wantsLayer = true
        zoomContentView.layer?.backgroundColor = NSColor.black.cgColor
        zoomScrollView.documentView = zoomContentView
        addSubview(zoomScrollView)
        installPlayerMenuGesture(on: self)
        installPlayerMenuGesture(on: zoomScrollView)
        installPlayerMenuGesture(on: zoomContentView)
        installPlayerZoomGestures(on: self)
        installPlayerZoomGestures(on: zoomScrollView)
        installPlayerZoomGestures(on: zoomContentView)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        cleanup()
    }

    override var bounds: NSRect {
        didSet {
            updateZoomViewportLayoutIfNeeded()
        }
    }

    override var frame: NSRect {
        didSet {
            updateZoomViewportLayoutIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        updateZoomViewportLayoutIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        handleNativeSmartMagnify(event)
    }

    override func magnify(with event: NSEvent) {
        zoomScrollView.magnify(with: event)
    }

    override func swipe(with event: NSEvent) {
        nextResponder?.swipe(with: event)
    }

    func updatePlayerMenuDelegate(_ playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerMenuDelegate = playerMenuDelegate
        webView?.updatePlayerMenuDelegate(playerMenuDelegate)
    }

    func render(_ token: GeneratedToken, mode: MacPlayerMediaRenderMode = .active) {
        let tokenChanged = currentToken != token
        let modeChanged = renderMode != mode
        guard tokenChanged || modeChanged else { return }

        currentToken = token
        renderMode = mode

        if tokenChanged || modeChanged {
            resetZoom(animated: false)
        }

        if tokenChanged || !mode.canDemandLoad {
            representedImageKey = nil
            activeImageLoadId = nil
            cancelActiveImageLoad?()
            cancelActiveImageLoad = nil
            activeFileLoadId = nil
            cancelActiveFileLoad?()
            cancelActiveFileLoad = nil
        }

        if !mode.managesDownloadWindow {
            clearManagedDownloadableMediaWindow()
        }

        let previousContext = currentTokenContext
        let tokenContext = CollectionCatalog.tokenContext(for: token)
        currentTokenContext = tokenContext
        let direction = Self.prefetchDirection(from: previousContext, to: tokenContext)
        let isDownloadableToken = tokenContext.map {
            CollectionCatalog.isDownloadableCollection(specificCollectionId: $0.collectionId)
        } == true

        if token.usesPonchoDrifellaMetalRenderer {
            clearWebMediaContext()
            clearManagedDownloadableMediaWindow()
            renderPonchoDrifellaMetalCard(token)
            return
        }

        guard let descriptor = Self.downloadableMediaDescriptor(for: token, context: tokenContext) else {
            clearWebMediaContext()
            clearManagedDownloadableMediaWindow()
            if !mode.canDemandLoad, isDownloadableToken {
                clearVisibleContentForPendingDownload()
                return
            }
            renderWebContent(token.html)
            return
        }

        if mode.managesDownloadWindow {
            prepareDownloadableMediaWindow(context: tokenContext, direction: direction)
        }

        switch descriptor.media {
        case .staticImage:
            clearWebMediaContext()
            renderImage(descriptor, fallbackHTML: token.html, mode: mode)
        case .animatedImage:
            renderDownloadableWebMedia(
                descriptor,
                adjacentDescriptor: adjacentDownloadableMediaDescriptor(for: tokenContext, direction: direction),
                fallbackHTML: token.html,
                mediaKind: .image,
                mode: mode
            )
        case .video:
            renderDownloadableWebMedia(descriptor, fallbackHTML: token.html, mediaKind: .video, mode: mode)
        case .html:
            renderDownloadableWebMedia(descriptor, fallbackHTML: token.html, mediaKind: .html, mode: mode)
        }
    }

    func cleanup() {
        cancelActiveImageLoad?()
        cancelActiveImageLoad = nil
        cancelActiveFileLoad?()
        cancelActiveFileLoad = nil
        activeFileLoadId = nil
        cancelVideoSizeLoad()
        isNativeMagnifyGestureActive = false
        activeZoomAnimationCount = 0
        clearWebMediaContext()
        clearManagedDownloadableMediaWindow()
        ponchoDrifellaMetalCardView?.stop()
        PonchoDrifellaMetalCardView.resetMotionCalibration()
        unloadWebContentIfNeeded()
        webView?.isHidden = true
        imageView?.image = nil
        clearZoomContentLayout()
        currentToken = nil
        renderMode = nil
        cancelDownloadsIfNoPlayerWindows()
    }

    func resetZoomForReuse() {
        resetZoom(animated: false)
    }

    private func renderImage(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fallbackHTML: String,
        mode: MacPlayerMediaRenderMode
    ) {
        let imageKey = AnyHashable(descriptor)
        if let cachedImage = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            displayLoadedImage(cachedImage, key: descriptor)
            return
        }

        hideWebView()
        hidePonchoDrifellaMetalCardView()
        let imageView = ensureImageView()
        if representedImageKey != imageKey {
            imageView.image = nil
        }
        imageView.isHidden = false

        representedImageKey = imageKey
        guard mode.canDemandLoad else { return }

        if representedImageKey == imageKey, activeImageLoadId != nil {
            return
        }

        let imageLoadId = UUID()
        activeImageLoadId = imageLoadId

        cancelActiveImageLoad = DownloadableMediaCache.shared.loadImage(for: descriptor) { [weak self] image in
            guard let self,
                  self.representedImageKey == imageKey,
                  self.activeImageLoadId == imageLoadId else {
                return
            }

            self.cancelActiveImageLoad = nil
            self.activeImageLoadId = nil
            guard let image else {
                self.renderWebContent(fallbackHTML)
                return
            }

            self.displayLoadedImage(image, key: descriptor)
        }
    }

    private func displayLoadedImage<Key: Hashable>(_ image: NSImage, key: Key) {
        cancelActiveImageLoad?()
        cancelActiveImageLoad = nil
        activeImageLoadId = nil
        hideWebView()
        hidePonchoDrifellaMetalCardView()
        representedImageKey = AnyHashable(key)
        let imageView = ensureImageView()
        imageView.image = image
        imageView.isHidden = false
        setZoomContentLayout(.staticImage(Self.zoomImageSize(for: image) ?? image.size))
    }

    private func renderDownloadableWebMedia(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        adjacentDescriptor: CollectionCatalogDownloadableMediaDescriptor? = nil,
        fallbackHTML: String,
        mediaKind: WebMediaKind,
        mode: MacPlayerMediaRenderMode
    ) {
        let context = WebMediaContext(
            descriptor: descriptor,
            adjacentDescriptor: adjacentDescriptor,
            fallbackHTML: fallbackHTML,
            mediaKind: mediaKind
        )
        if webMediaContext != context {
            cancelVideoSizeLoad()
        }
        webMediaContext = context
        if mode.managesDownloadWindow {
            installDownloadableMediaCacheObserverIfNeeded()
        } else {
            removeDownloadableMediaCacheObserver()
        }
        renderAvailableLocalWebContent()
        if mode.canDemandLoad {
            requestLocalWebContentIfNeeded()
        }
    }

    private func renderAvailableLocalWebContent() {
        guard let context = webMediaContext else { return }

        let imageCache = DownloadableMediaCache.shared
        guard let localFileURL = imageCache.localFileURL(for: context.descriptor) else {
            cancelVideoSizeLoad()
            clearLocalWebURLState()
            clearVisibleContentForPendingDownload()
            return
        }
        cancelActiveFileLoad?()
        cancelActiveFileLoad = nil
        activeFileLoadId = nil

        let nextLocalFileURL = context.adjacentDescriptor.flatMap {
            imageCache.localFileURL(for: $0)
        }

        if pendingLocalWebURL == localFileURL {
            return
        }

        if renderedLocalWebURL == localFileURL {
            guard renderedNextLocalWebURL != nextLocalFileURL else { return }
            guard pendingNextLocalWebURL != nextLocalFileURL else { return }
            guard let nextLocalFileURL else {
                pendingNextLocalWebURL = nil
                renderedNextLocalWebURL = nil
                return
            }

            pendingNextLocalWebURL = nextLocalFileURL
            preloadWebImage(nextLocalFileURL) { [weak self] didPreload in
                guard let self,
                      self.webMediaContext == context,
                      self.renderedLocalWebURL == localFileURL else {
                    return
                }

                if self.pendingNextLocalWebURL == nextLocalFileURL {
                    self.pendingNextLocalWebURL = nil
                }
                guard didPreload else { return }

                self.renderedNextLocalWebURL = nextLocalFileURL
            }
            return
        }

        let html: String
        switch context.mediaKind {
        case .image:
            if let imageSize = imageOrSVGSize(at: localFileURL) {
                setZoomContentLayout(.staticImage(imageSize))
            } else {
                setZoomContentLayout(.viewport)
            }
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: localFileURL.absoluteString,
                nextImageURL: nextLocalFileURL?.absoluteString
            )
        case .video:
            loadVideoSizeIfNeeded(at: localFileURL, context: context)
            html = DownloadableTokenHTML.createVideoHTML(videoURL: localFileURL.absoluteString)
        case .html:
            renderCachedHTMLDocument(fileURL: localFileURL, context: context, imageCache: imageCache)
            return
        }

        renderLocalWebContent(
            html,
            fileURL: localFileURL,
            context: context,
            htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
            readAccessURL: imageCache.webViewReadAccessURL
        )
    }

    private func renderCachedHTMLDocument(
        fileURL: URL,
        context: WebMediaContext,
        imageCache: DownloadableMediaCache
    ) {
        clearVisibleContentForPendingDownload()
        pendingLocalWebURL = fileURL
        htmlDocumentRenderQueue.async {
            let renderedDocument = (try? String(contentsOf: fileURL, encoding: .utf8)).map { documentHTML in
                (
                    html: DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                        documentHTML: documentHTML,
                        baseURL: imageCache.downloadedSourceURL(for: context.descriptor).absoluteString
                    ),
                    viewportSize: DownloadableHTMLDocumentLayout.rootSVGViewBoxSize(in: documentHTML)
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.webMediaContext == context,
                      self.pendingLocalWebURL == fileURL else {
                    return
                }

                guard let renderedDocument else {
                    self.clearWebMediaContext()
                    self.renderWebContent(context.fallbackHTML)
                    return
                }

                if let viewportSize = renderedDocument.viewportSize {
                    self.setZoomContentLayout(.staticImage(viewportSize))
                } else {
                    self.setZoomContentLayout(.viewport)
                }
                self.renderLocalWebContent(
                    renderedDocument.html,
                    fileURL: fileURL,
                    context: context,
                    htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
                    readAccessURL: imageCache.webViewHTMLDirectoryURL
                )
            }
        }
    }

    private func renderLocalWebContent(
        _ html: String,
        fileURL: URL,
        context: WebMediaContext,
        htmlDirectoryURL: URL,
        readAccessURL: URL
    ) {
        pendingLocalWebURL = fileURL
        displayWebHTML(
            html,
            htmlDirectoryURL: htmlDirectoryURL,
            readAccessURL: readAccessURL,
            onSuccess: { [weak self] in
                guard let self,
                      self.webMediaContext == context,
                      self.pendingLocalWebURL == fileURL else {
                    return
                }

                self.clearLocalWebURLState()
                self.renderedLocalWebURL = fileURL
                self.renderAvailableLocalWebContent()
            },
            onFailure: { [weak self] in
                guard let self,
                      self.webMediaContext == context,
                      self.pendingLocalWebURL == fileURL else {
                    return
                }

                self.clearWebMediaContext()
                self.renderWebContent(context.fallbackHTML)
            }
        )
    }

    private func requestLocalWebContentIfNeeded() {
        guard let context = webMediaContext,
              DownloadableMediaCache.shared.localFileURL(for: context.descriptor) == nil else {
            return
        }
        guard activeFileLoadId == nil else { return }

        let fileLoadId = UUID()
        activeFileLoadId = fileLoadId
        cancelActiveFileLoad = DownloadableMediaCache.shared.loadFile(for: context.descriptor) { [weak self] fileURL in
            guard let self,
                  self.webMediaContext == context,
                  self.activeFileLoadId == fileLoadId else {
                return
            }

            self.cancelActiveFileLoad = nil
            self.activeFileLoadId = nil

            guard fileURL != nil else {
                self.renderWebMediaFallback(for: context)
                return
            }

            self.renderAvailableLocalWebContent()
        }
    }

    private func renderWebMediaFallback(for context: WebMediaContext) {
        guard webMediaContext == context else { return }
        clearWebMediaContext()
        renderWebContent(context.fallbackHTML)
    }

    private func preloadWebImage(_ imageURL: URL, completion: ((Bool) -> Void)? = nil) {
        guard let webView else {
            completion?(false)
            return
        }

        webView.callAsyncJavaScript(
            DownloadableTokenHTML.preloadImageJavaScript(imageURL: imageURL),
            arguments: [:],
            in: nil,
            in: .page
        ) { result in
            switch result {
            case .success(let value):
                completion?((value as? Bool) == true)
            case .failure:
                completion?(false)
            }
        }
    }

    private func renderWebContent(_ html: String) {
        clearWebMediaContext()
        setZoomContentLayout(.viewport)
        displayWebHTML(html)
    }

    private func displayWebHTML(
        _ html: String,
        htmlDirectoryURL: URL? = nil,
        readAccessURL: URL? = nil,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) {
        cancelActiveImageLoad?()
        cancelActiveImageLoad = nil
        representedImageKey = nil
        hideImageView()
        hidePonchoDrifellaMetalCardView()
        let webView = ensureWebView()
        webViewMayContainContent = !html.isEmpty
        webView.isHidden = false
        if let htmlDirectoryURL, let readAccessURL {
            webView.loadLocalHTMLString(
                html,
                htmlDirectoryURL: htmlDirectoryURL,
                allowingReadAccessTo: readAccessURL,
                onSuccess: onSuccess,
                onFailure: onFailure
            )
        } else {
            webView.loadHTMLString(html, baseURL: nil)
            onSuccess?()
        }
    }

    private func renderPonchoDrifellaMetalCard(_ token: GeneratedToken) {
        cancelActiveImageLoad?()
        cancelActiveImageLoad = nil
        representedImageKey = nil
        hideImageView()
        hideWebView()
        let cardView = ensurePonchoDrifellaMetalCardView()
        cardView.isHidden = false
        setZoomContentLayout(.viewport, allowedContent: .ponchoDrifellaCard)
        cardView.display(tokenId: token.id)
    }

    private func prepareDownloadableMediaWindow(
        context: PlayerTokenContext?,
        direction: DownloadableMediaCache.PrefetchDirection
    ) {
        guard let context else { return }

        let descriptors = DownloadableMediaCache.windowDescriptors(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
        DownloadableMediaCache.shared.prepareWindow(
            collectionId: context.collectionId,
            ownerId: downloadableMediaWindowOwnerId,
            currentTokenIndex: context.tokenIndex,
            descriptors: descriptors,
            direction: direction
        )
        activeDownloadableMediaCollectionId = context.collectionId
    }

    private func clearManagedDownloadableMediaWindow() {
        guard let collectionId = activeDownloadableMediaCollectionId else { return }

        DownloadableMediaCache.shared.clearActiveWindow(
            for: collectionId,
            ownerId: downloadableMediaWindowOwnerId
        )
        activeDownloadableMediaCollectionId = nil
    }

    private func adjacentDownloadableMediaDescriptor(
        for context: PlayerTokenContext?,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let context else { return nil }
        return DownloadableMediaCache.adjacentDescriptor(
            collectionId: context.collectionId,
            currentTokenIndex: context.tokenIndex,
            tokenCount: context.tokenCount,
            direction: direction
        )
    }

    private func ensureImageView() -> AspectFitImageView {
        if let imageView {
            return imageView
        }

        let imageView = AspectFitImageView()
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        installPlayerMenuGesture(on: imageView)
        installPlayerZoomGestures(on: imageView)
        addSubviewFillingZoomContent(imageView)
        self.imageView = imageView
        return imageView
    }

    private func ensureWebView() -> PlayerWebView {
        if let webView {
            return webView
        }

        let webView = PlayerWebView.make(playerMenuDelegate: playerMenuDelegate)
        webView.passesPlayerGesturesThrough = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        installPlayerZoomGestures(on: webView)
        addSubviewFillingZoomContent(webView)
        self.webView = webView
        return webView
    }

    private func ensurePonchoDrifellaMetalCardView() -> PonchoDrifellaMetalCardView {
        if let ponchoDrifellaMetalCardView {
            return ponchoDrifellaMetalCardView
        }

        let cardView = PonchoDrifellaMetalCardView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        installPlayerMenuGesture(on: cardView)
        installPlayerZoomGestures(on: cardView)
        cardView.subviews.forEach(installPlayerMenuGesture)
        cardView.subviews.forEach(installPlayerZoomGestures)
        addSubviewFillingZoomContent(cardView)
        ponchoDrifellaMetalCardView = cardView
        return cardView
    }

    private func installPlayerMenuGesture(on view: NSView) {
        let rightClickGestureRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClickGestureRecognizer.buttonMask = 0x2
        view.addGestureRecognizer(rightClickGestureRecognizer)
    }

    private func installPlayerZoomGestures(on view: NSView) {
        let doubleClickGestureRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClickGestureRecognizer.buttonMask = 0x1
        doubleClickGestureRecognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(doubleClickGestureRecognizer)
    }

    @objc private func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        guard shouldHandleCurrentMouseEvent(lastHandledEventNumber: &lastPlayerMenuEventNumber) else { return }
        playerMenuDelegate?.popUpMenu(view: gestureRecognizer.view ?? self)
    }

    @objc private func handleDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        guard shouldHandleCurrentMouseEvent(lastHandledEventNumber: &lastZoomToggleEventNumber) else { return }

        toggleZoom(at: gestureRecognizer.location(in: self), animated: true)
    }

    private func addSubviewFillingZoomContent(_ subview: NSView) {
        zoomContentView.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: zoomContentView.topAnchor),
            subview.leadingAnchor.constraint(equalTo: zoomContentView.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: zoomContentView.trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: zoomContentView.bottomAnchor)
        ])
    }

    private func hideImageView() {
        imageView?.isHidden = true
        imageView?.image = nil
    }

    private func hideWebView() {
        unloadWebContentIfNeeded()
        webView?.isHidden = true
    }

    private func hidePonchoDrifellaMetalCardView() {
        ponchoDrifellaMetalCardView?.stop()
        ponchoDrifellaMetalCardView?.isHidden = true
    }

    private func clearWebMediaContext() {
        cancelActiveFileLoad?()
        cancelActiveFileLoad = nil
        activeFileLoadId = nil
        cancelVideoSizeLoad()
        webMediaContext = nil
        clearLocalWebURLState()
        removeDownloadableMediaCacheObserver()
    }

    private func cancelDownloadsIfNoPlayerWindows() {
        guard !Window.hasOpenPlayerWindows else { return }
        DispatchQueue.main.async {
            guard !Window.hasOpenPlayerWindows else { return }
            DownloadableMediaCache.shared.cancelAllDownloads()
        }
    }

    private func clearLocalWebURLState() {
        pendingLocalWebURL = nil
        renderedLocalWebURL = nil
        renderedNextLocalWebURL = nil
        pendingNextLocalWebURL = nil
    }

    private func clearVisibleContentForPendingDownload() {
        cancelActiveImageLoad?()
        cancelActiveImageLoad = nil
        activeImageLoadId = nil
        representedImageKey = nil
        hideImageView()
        hidePonchoDrifellaMetalCardView()
        hideWebView()
        setZoomContentLayout(.viewport)
    }

    private func unloadWebContentIfNeeded() {
        guard webViewMayContainContent else {
            webView?.invalidateRequestedContent()
            return
        }

        webView?.unloadContent()
        webViewMayContainContent = false
    }

    private func installDownloadableMediaCacheObserverIfNeeded() {
        guard downloadableMediaCacheObserver == nil else { return }

        downloadableMediaCacheObserver = NotificationCenter.default.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderAvailableLocalWebContent()
        }
    }

    private func removeDownloadableMediaCacheObserver() {
        guard let downloadableMediaCacheObserver else { return }

        NotificationCenter.default.removeObserver(downloadableMediaCacheObserver)
        self.downloadableMediaCacheObserver = nil
    }

    private static func downloadableMediaDescriptor(
        for token: GeneratedToken,
        context: PlayerTokenContext?
    ) -> CollectionCatalogDownloadableMediaDescriptor? {
        guard let context,
              CollectionCatalog.isDownloadableCollection(specificCollectionId: context.collectionId) else {
            return nil
        }

        return CollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: token.fullCollectionId,
            tokenIndex: context.tokenIndex
        )
    }

    private static func prefetchDirection(
        from previousContext: PlayerTokenContext?,
        to newContext: PlayerTokenContext?
    ) -> DownloadableMediaCache.PrefetchDirection {
        guard let previousContext,
              let newContext,
              previousContext.collectionId == newContext.collectionId,
              newContext.tokenIndex < previousContext.tokenIndex else {
            return .forward
        }
        return .backward
    }

    private static func zoomImageSize(for image: NSImage) -> CGSize? {
        guard image.isValid,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private func imageOrSVGSize(at fileURL: URL) -> CGSize? {
        if let imageSize = imageSize(at: fileURL) {
            return imageSize
        }

        guard let documentHTML = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        return DownloadableHTMLDocumentLayout.rootSVGViewBoxSize(in: documentHTML)
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

    private func loadVideoSizeIfNeeded(at fileURL: URL, context: WebMediaContext) {
        let request = VideoSizeRequest(fileURL: fileURL, descriptor: context.descriptor)

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
            let size = await VideoAssetLayout.displaySize(at: fileURL)
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

        videoSizeLoad = VideoSizeLoad(request: request, task: task)
    }

    private func cacheVideoSize(_ size: CGSize, for request: VideoSizeRequest) {
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
        guard let context = webMediaContext,
              context.mediaKind == .video,
              let fileURL = DownloadableMediaCache.shared.localFileURL(for: context.descriptor) else {
            return
        }

        let request = VideoSizeRequest(fileURL: fileURL, descriptor: context.descriptor)
        guard let cachedSize = cachedVideoSizes[request] else { return }

        applyVideoSizeIfCurrent(cachedSize, for: request)
    }

    private func applyVideoSizeIfCurrent(_ size: CGSize, for request: VideoSizeRequest) {
        guard let context = webMediaContext,
              context.mediaKind == .video,
              context.descriptor == request.descriptor,
              DownloadableMediaCache.shared.localFileURL(for: request.descriptor) == request.fileURL,
              VideoSizeRequest(fileURL: request.fileURL, descriptor: request.descriptor) == request,
              !isZoomed,
              !isNativeMagnifyGestureActive,
              activeZoomAnimationCount == 0 else {
            return
        }

        setZoomContentLayout(.staticImage(size))
    }

    private func cancelVideoSizeLoad() {
        videoSizeLoad?.task.cancel()
        videoSizeLoad = nil
    }

    private func shouldHandleCurrentMouseEvent(lastHandledEventNumber: inout Int?) -> Bool {
        guard let event = NSApp.currentEvent,
              event.hasMouseEventNumber else {
            return true
        }

        let eventNumber = event.eventNumber
        guard lastHandledEventNumber != eventNumber else { return false }

        lastHandledEventNumber = eventNumber
        return true
    }

    private var isZoomed: Bool {
        zoomScrollView.magnification > ZoomTuning.minimumScale + ZoomTuning.resetTolerance
    }

    private var isProgrammaticZoomAnimationActive: Bool {
        activeZoomAnimationCount > 0 && !isNativeMagnifyGestureActive
    }

    private func updateZoomViewportLayoutIfNeeded() {
        let viewportSize = bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        if zoomScrollView.frame != bounds {
            zoomScrollView.frame = bounds
        }

        if laidOutZoomViewportSize != viewportSize {
            laidOutZoomViewportSize = viewportSize
            if isZoomed {
                resetZoom(animated: false)
            }
        }

        let documentFrame = CGRect(origin: .zero, size: viewportSize)
        guard zoomContentView.frame != documentFrame || zoomContentView.bounds.size != viewportSize else { return }

        withoutLayerAnimations {
            zoomContentView.frame = documentFrame
            zoomContentView.bounds = documentFrame
            zoomContentView.layoutSubtreeIfNeeded()
        }
        scrollDocumentToOrigin()
    }

    private func setZoomContentLayout(
        _ layout: ZoomContentLayout,
        allowedContent: ZoomAllowedContent = .fullContent
    ) {
        guard zoomContentLayout != layout || zoomAllowedContent != allowedContent else {
            clampZoomDocumentOffsetIfNeeded()
            return
        }

        zoomContentLayout = layout
        zoomAllowedContent = allowedContent
        resetZoom(animated: false)
        updateZoomViewportLayoutIfNeeded()
    }

    private func clearZoomContentLayout() {
        zoomContentLayout = .viewport
        zoomAllowedContent = .fullContent
    }

    private func toggleZoom(at locationInContainer: CGPoint, animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        if isZoomed {
            resetZoom(animated: animated)
            return
        }

        applyCachedCurrentVideoSizeIfAvailable()

        let targetScale = min(ZoomTuning.doubleTapScale, ZoomTuning.maximumScale)
        let documentPoint = zoomContentView.convert(locationInContainer, from: self)
        setZoomMagnification(targetScale, centeredAt: documentPoint, animated: animated)
    }

    private func resetZoom(animated: Bool) {
        guard animated else {
            setZoomMagnification(ZoomTuning.minimumScale, centeredAt: .zero, animated: false)
            scrollDocumentToOrigin()
            return
        }

        setZoomMagnification(
            ZoomTuning.minimumScale,
            centeredAt: .zero,
            animated: animated
        ) { [weak self] in
            self?.scrollDocumentToOrigin()
        }
    }

    private func setZoomMagnification(
        _ magnification: CGFloat,
        centeredAt documentPoint: CGPoint,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        let clampedMagnification = min(
            max(magnification, ZoomTuning.minimumScale),
            ZoomTuning.maximumScale
        )
        let centeredAt = clampedZoomCenter(for: clampedMagnification, centeredAt: documentPoint)

        let finish = { [weak self] in
            self?.clampZoomDocumentOffsetIfNeeded()
            completion?()
        }

        if animated {
            activeZoomAnimationCount += 1
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                zoomScrollView.animator().setMagnification(clampedMagnification, centeredAt: centeredAt)
            } completionHandler: { [weak self] in
                if let self = self {
                    self.activeZoomAnimationCount = max(0, self.activeZoomAnimationCount - 1)
                }
                finish()
            }
        } else {
            withoutLayerAnimations {
                zoomScrollView.setMagnification(clampedMagnification, centeredAt: centeredAt)
            }
            finish()
        }
    }

    private func settleNativeMagnification() {
        if zoomScrollView.magnification <= ZoomTuning.minimumScale + ZoomTuning.resetTolerance {
            resetZoom(animated: true)
        }
    }

    private func clampedDocumentPoint(_ point: CGPoint) -> CGPoint {
        let bounds = zoomAllowedDocumentRect()
        guard bounds.width > 0, bounds.height > 0 else { return point }
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func clampedZoomCenter(for magnification: CGFloat, centeredAt point: CGPoint) -> CGPoint {
        let visibleRect = boundedVisibleDocumentRect(for: magnification, centeredAt: clampedDocumentPoint(point))
        return CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }

    private func boundedVisibleDocumentRect(for magnification: CGFloat, centeredAt point: CGPoint) -> CGRect {
        let scale = max(magnification, ZoomTuning.minimumScale)
        let visibleSize = CGSize(
            width: bounds.width / scale,
            height: bounds.height / scale
        )
        let allowedRect = zoomAllowedDocumentRect()
        guard visibleSize.width > 0,
              visibleSize.height > 0,
              allowedRect.width > 0,
              allowedRect.height > 0 else {
            return CGRect(origin: .zero, size: visibleSize)
        }

        return CGRect(
            x: boundedZoomOrigin(
                centeredAt: point.x,
                zoomLength: visibleSize.width,
                allowedMin: allowedRect.minX,
                allowedMax: allowedRect.maxX
            ),
            y: boundedZoomOrigin(
                centeredAt: point.y,
                zoomLength: visibleSize.height,
                allowedMin: allowedRect.minY,
                allowedMax: allowedRect.maxY
            ),
            width: visibleSize.width,
            height: visibleSize.height
        )
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

    private func clampZoomDocumentOffsetIfNeeded() {
        guard isZoomed else { return }

        let visibleRect = zoomScrollView.documentVisibleRect
        guard visibleRect.width > 0, visibleRect.height > 0 else { return }

        let constrainedRect = constrainedZoomVisibleRect(visibleRect)
        let clampedOrigin = constrainedRect.origin

        guard clampedOrigin != visibleRect.origin else { return }

        zoomScrollView.contentView.scroll(to: clampedOrigin)
        zoomScrollView.reflectScrolledClipView(zoomScrollView.contentView)
    }

    private func scrollDocumentToOrigin() {
        zoomScrollView.contentView.scroll(to: .zero)
        zoomScrollView.reflectScrolledClipView(zoomScrollView.contentView)
    }

    private func shouldForwardZoomScrollWheel(_ event: NSEvent) -> Bool {
        guard isZoomed else { return true }
        return shouldHandOffZoomedHorizontalScroll(event)
    }

    private func shouldForwardZoomSwipe(_ event: NSEvent) -> Bool {
        guard isZoomed else { return true }
        return shouldHandOffZoomedHorizontalSwipe(event)
    }

    private func handleNativeSmartMagnify(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        toggleZoom(at: location, animated: true)
    }

    private func isAtLeadingZoomEdge() -> Bool {
        let visibleRect = zoomScrollView.documentVisibleRect
        let allowedRect = zoomAllowedDocumentRect()
        return visibleRect.minX <= allowedRect.minX + zoomEdgeToleranceInDocumentCoordinates
    }

    private func isAtTrailingZoomEdge() -> Bool {
        let visibleRect = zoomScrollView.documentVisibleRect
        let allowedRect = zoomAllowedDocumentRect()
        return visibleRect.maxX >= allowedRect.maxX - zoomEdgeToleranceInDocumentCoordinates
    }

    private var zoomEdgeToleranceInDocumentCoordinates: CGFloat {
        ZoomTuning.edgePaginationTolerance / max(zoomScrollView.magnification, ZoomTuning.minimumScale)
    }

    private func shouldHandOffZoomedHorizontalScroll(_ event: NSEvent) -> Bool {
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard deltaX != 0,
              abs(deltaX) > abs(deltaY) * ZoomTuning.horizontalIntentRatio else {
            return false
        }

        if deltaX > 0 {
            return isAtLeadingZoomEdge()
        }

        return isAtTrailingZoomEdge()
    }

    private func shouldHandOffZoomedHorizontalSwipe(_ event: NSEvent) -> Bool {
        let deltaX = event.deltaX
        let deltaY = event.deltaY
        guard deltaX != 0,
              abs(deltaX) > abs(deltaY) * ZoomTuning.horizontalIntentRatio else {
            return false
        }

        if deltaX > 0 {
            return isAtLeadingZoomEdge()
        }

        return isAtTrailingZoomEdge()
    }

    private func constrainedZoomVisibleRect(_ proposedRect: CGRect) -> CGRect {
        guard isZoomed,
              !isProgrammaticZoomAnimationActive,
              proposedRect.width > 0,
              proposedRect.height > 0 else {
            return proposedRect
        }

        let allowedRect = zoomAllowedDocumentRect()
        guard allowedRect.width > 0, allowedRect.height > 0 else { return proposedRect }

        return CGRect(
            x: boundedZoomOrigin(
                centeredAt: proposedRect.midX,
                zoomLength: proposedRect.width,
                allowedMin: allowedRect.minX,
                allowedMax: allowedRect.maxX
            ),
            y: boundedZoomOrigin(
                centeredAt: proposedRect.midY,
                zoomLength: proposedRect.height,
                allowedMin: allowedRect.minY,
                allowedMax: allowedRect.maxY
            ),
            width: proposedRect.width,
            height: proposedRect.height
        )
    }

    private func zoomAllowedDocumentRect() -> CGRect {
        let contentBounds = CGRect(origin: .zero, size: zoomContentView.bounds.size)
        guard contentBounds.width > 0, contentBounds.height > 0 else { return .zero }

        let layoutRect: CGRect
        switch zoomContentLayout {
        case .viewport:
            layoutRect = contentBounds
        case .staticImage(let imageSize):
            layoutRect = aspectFitRect(for: imageSize, in: contentBounds)
        }

        let allowedRect: CGRect
        switch zoomAllowedContent {
        case .fullContent:
            allowedRect = layoutRect
        case .ponchoDrifellaCard:
            allowedRect = PonchoDrifellaMetalCardView.cardContentRect(in: contentBounds.size)
        }

        let clippedRect = allowedRect.intersection(contentBounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else { return contentBounds }
        return clippedRect
    }

    private func aspectFitRect(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - scaledSize.width / 2,
            y: bounds.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    private func withoutLayerAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}

private enum VideoAssetLayout {
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

private enum DownloadableHTMLDocumentLayout {

    static func rootSVGViewBoxSize(in html: String) -> CGSize? {
        guard let svgOpeningTag = rootSVGOpeningTag(in: html) else { return nil }

        if let viewBox = attribute("viewBox", in: svgOpeningTag),
           let viewBoxSize = size(fromViewBox: viewBox) {
            return viewBoxSize
        }

        guard let width = absoluteLengthAttribute("width", in: svgOpeningTag),
              let height = absoluteLengthAttribute("height", in: svgOpeningTag),
              width > 0,
              height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private static func size(fromViewBox viewBox: String) -> CGSize? {
        let components = viewBox
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
        guard components.count == 4 else { return nil }

        let values = components.compactMap { Double($0) }
        guard values.count == 4,
              values.allSatisfy({ $0.isFinite }) else {
            return nil
        }

        let width = values[2]
        let height = values[3]
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    private static func rootSVGOpeningTag(in html: String) -> String? {
        if let bodyRootSVG = firstCapturedMatch(
            pattern: "<body(?=\\s|>)[^>]*>\\s*(<svg(?=\\s|/?>)[^>]*>)",
            in: html
        ) {
            return bodyRootSVG
        }

        return firstCapturedMatch(
            pattern: "^\\s*(?:(?:<\\?xml\\b[^>]*\\?>|<!doctype\\b[^>]*>)\\s*)*(<svg(?=\\s|/?>)[^>]*>)",
            in: html
        )
    }

    private static func firstCapturedMatch(pattern: String, in html: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, range: fullRange),
              match.numberOfRanges > 1 else {
            return nil
        }

        let range = match.range(at: 1)
        guard range.location != NSNotFound,
              let valueRange = Range(range, in: html) else {
            return nil
        }
        return String(html[valueRange])
    }

    private static func absoluteLengthAttribute(_ name: String, in openingTag: String) -> CGFloat? {
        guard let value = attribute(name, in: openingTag)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        guard let expression = try? NSRegularExpression(
            pattern: #"^([-+]?(?:\d+\.?\d*|\.\d+))(?:px)?$"#,
            options: [.caseInsensitive]
        ),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let valueRange = Range(match.range(at: 1), in: value),
              let number = Double(String(value[valueRange])) else {
            return nil
        }
        return number.isFinite ? CGFloat(number) : nil
    }

    private static func attribute(_ name: String, in openingTag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?:^|[\\s<])\(escapedName)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(openingTag.startIndex..<openingTag.endIndex, in: openingTag)
        guard let match = expression.firstMatch(in: openingTag, range: fullRange) else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let valueRange = Range(range, in: openingTag) else {
                continue
            }
            return String(openingTag[valueRange])
        }
        return nil
    }
}

private protocol MacPlayerZoomScrollViewEventDelegate: AnyObject {
    func zoomScrollViewShouldForwardScrollWheel(_ scrollView: MacPlayerZoomScrollView, event: NSEvent) -> Bool
    func zoomScrollViewShouldForwardSwipe(_ scrollView: MacPlayerZoomScrollView, event: NSEvent) -> Bool
    func zoomScrollViewSmartMagnify(_ scrollView: MacPlayerZoomScrollView, event: NSEvent)
    func zoomScrollViewDidBeginMagnify(_ scrollView: MacPlayerZoomScrollView)
    func zoomScrollViewDidEndMagnify(_ scrollView: MacPlayerZoomScrollView)
}

private final class MacPlayerZoomScrollView: NSScrollView {

    weak var eventDelegate: MacPlayerZoomScrollViewEventDelegate?
    var constrainVisibleRect: ((CGRect) -> CGRect)? {
        didSet {
            (contentView as? MacPlayerZoomClipView)?.constrainVisibleRect = constrainVisibleRect
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = MacPlayerZoomClipView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentView = MacPlayerZoomClipView()
    }

    override func scrollWheel(with event: NSEvent) {
        guard eventDelegate?.zoomScrollViewShouldForwardScrollWheel(self, event: event) != true else {
            nextResponder?.scrollWheel(with: event)
            return
        }

        super.scrollWheel(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        eventDelegate?.zoomScrollViewSmartMagnify(self, event: event)
    }

    override func magnify(with event: NSEvent) {
        let phase = event.phase
        if phase.contains(.began) || phase.contains(.changed) || phase.contains(.stationary) {
            eventDelegate?.zoomScrollViewDidBeginMagnify(self)
        }

        super.magnify(with: event)

        if phase.contains(.ended) || phase.contains(.cancelled) {
            eventDelegate?.zoomScrollViewDidEndMagnify(self)
        }
    }

    override func swipe(with event: NSEvent) {
        guard eventDelegate?.zoomScrollViewShouldForwardSwipe(self, event: event) != true else {
            nextResponder?.swipe(with: event)
            return
        }
    }
}

private final class MacPlayerZoomClipView: NSClipView {

    var constrainVisibleRect: ((CGRect) -> CGRect)?

    override func scroll(to newOrigin: NSPoint) {
        let proposedBounds = NSRect(origin: newOrigin, size: bounds.size)
        super.scroll(to: constrainBoundsRect(proposedBounds).origin)
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        let proposedBounds = NSRect(origin: newOrigin, size: bounds.size)
        super.setBoundsOrigin(constrainBoundsRect(proposedBounds).origin)
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        let constrainedBounds = super.constrainBoundsRect(proposedBounds)
        return constrainVisibleRect?(constrainedBounds) ?? constrainedBounds
    }
}

private final class MacPlayerZoomContentView: NSView {

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        nextResponder?.smartMagnify(with: event)
    }

    override func magnify(with event: NSEvent) {
        nextResponder?.magnify(with: event)
    }

    override func swipe(with event: NSEvent) {
        nextResponder?.swipe(with: event)
    }
}

extension MacPlayerMediaContainerView: MacPlayerZoomScrollViewEventDelegate {

    fileprivate func zoomScrollViewShouldForwardScrollWheel(
        _ scrollView: MacPlayerZoomScrollView,
        event: NSEvent
    ) -> Bool {
        shouldForwardZoomScrollWheel(event)
    }

    fileprivate func zoomScrollViewShouldForwardSwipe(
        _ scrollView: MacPlayerZoomScrollView,
        event: NSEvent
    ) -> Bool {
        shouldForwardZoomSwipe(event)
    }

    fileprivate func zoomScrollViewSmartMagnify(_ scrollView: MacPlayerZoomScrollView, event: NSEvent) {
        handleNativeSmartMagnify(event)
    }

    fileprivate func zoomScrollViewDidBeginMagnify(_ scrollView: MacPlayerZoomScrollView) {
        isNativeMagnifyGestureActive = true
    }

    fileprivate func zoomScrollViewDidEndMagnify(_ scrollView: MacPlayerZoomScrollView) {
        isNativeMagnifyGestureActive = false
        settleNativeMagnification()
    }
}

private extension NSEvent {
    var hasMouseEventNumber: Bool {
        switch type {
        case .leftMouseDown,
             .leftMouseUp,
             .rightMouseDown,
             .rightMouseUp,
             .otherMouseDown,
             .otherMouseUp,
             .leftMouseDragged,
             .rightMouseDragged,
             .otherMouseDragged,
             .mouseMoved,
             .mouseEntered,
             .mouseExited:
            return true
        default:
            return false
        }
    }
}

private final class AspectFitImageView: NSView {

    private let imageLayer = CALayer()
    private var imageSize: CGSize?

    var image: NSImage? {
        didSet {
            withoutLayerAnimations {
                updateLayerContents()
                updateImageLayerFrame()
            }
        }
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor.black.cgColor
        layer.masksToBounds = true
        imageLayer.contentsGravity = .resize
        imageLayer.masksToBounds = true
        layer.minificationFilter = .linear
        layer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        imageLayer.magnificationFilter = .linear
        layer.actions = Self.disabledLayerActions
        imageLayer.actions = Self.disabledLayerActions
        layer.addSublayer(imageLayer)
        return layer
    }

    override var bounds: NSRect {
        didSet {
            withoutLayerAnimations(updateImageLayerFrame)
        }
    }

    override var frame: NSRect {
        didSet {
            withoutLayerAnimations(updateImageLayerFrame)
        }
    }

    override func layout() {
        super.layout()
        withoutLayerAnimations(updateImageLayerFrame)
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        nextResponder?.smartMagnify(with: event)
    }

    override func magnify(with event: NSEvent) {
        nextResponder?.magnify(with: event)
    }

    override func swipe(with event: NSEvent) {
        nextResponder?.swipe(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        withoutLayerAnimations {
            updateLayerContents()
            updateImageLayerFrame()
        }
    }

    private func updateLayerContents() {
        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = contentsScale
        imageLayer.contentsScale = contentsScale
        guard let image,
              image.isValid,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageSize = nil
            imageLayer.contents = nil
            return
        }

        imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        imageLayer.contents = cgImage
    }

    private func updateImageLayerFrame() {
        guard let imageSize,
              imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            imageLayer.frame = .zero
            return
        }

        imageLayer.frame = aspectFitRect(
            for: imageSize,
            in: CGRect(origin: .zero, size: bounds.size)
        )
    }

    private func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - scaledSize.width / 2,
            y: bounds.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    private func withoutLayerAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    private static let disabledLayerActions: [String: CAAction] = [
        "backgroundColor": NSNull(),
        "bounds": NSNull(),
        "contents": NSNull(),
        "contentsScale": NSNull(),
        "frame": NSNull(),
        "position": NSNull()
    ]
}
