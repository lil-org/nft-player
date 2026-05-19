// ∅ 2026 lil org

import AppKit
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

    private enum WebMediaKind {
        case image, video, html
    }

    private struct WebMediaContext: Equatable {
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let adjacentDescriptor: CollectionCatalogDownloadableMediaDescriptor?
        let fallbackHTML: String
        let mediaKind: WebMediaKind
    }

    private weak var playerMenuDelegate: PlayerMenuDelegate?
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
    private var lastPlayerMenuEventNumber: Int?
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
        installPlayerMenuGesture(on: self)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        cleanup()
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

        if token.usesPonchoDrifellaMetalRenderer {
            clearWebMediaContext()
            clearManagedDownloadableMediaWindow()
            renderPonchoDrifellaMetalCard(token)
            return
        }

        guard let descriptor = Self.downloadableMediaDescriptor(for: token, context: tokenContext) else {
            clearWebMediaContext()
            clearManagedDownloadableMediaWindow()
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
        clearWebMediaContext()
        clearManagedDownloadableMediaWindow()
        ponchoDrifellaMetalCardView?.stop()
        PonchoDrifellaMetalCardView.resetMotionCalibration()
        unloadWebContentIfNeeded()
        webView?.isHidden = true
        imageView?.image = nil
        currentToken = nil
        renderMode = nil
        cancelDownloadsIfNoPlayerWindows()
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
    }

    private func renderDownloadableWebMedia(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        adjacentDescriptor: CollectionCatalogDownloadableMediaDescriptor? = nil,
        fallbackHTML: String,
        mediaKind: WebMediaKind,
        mode: MacPlayerMediaRenderMode
    ) {
        webMediaContext = WebMediaContext(
            descriptor: descriptor,
            adjacentDescriptor: adjacentDescriptor,
            fallbackHTML: fallbackHTML,
            mediaKind: mediaKind
        )
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
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: localFileURL.absoluteString,
                nextImageURL: nextLocalFileURL?.absoluteString
            )
        case .video:
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
                DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                    documentHTML: documentHTML,
                    baseURL: imageCache.downloadedSourceURL(for: context.descriptor).absoluteString
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

                self.renderLocalWebContent(
                    renderedDocument,
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
        addSubviewFillingBounds(imageView)
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
        addSubviewFillingBounds(webView)
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
        cardView.subviews.forEach(installPlayerMenuGesture)
        addSubviewFillingBounds(cardView)
        ponchoDrifellaMetalCardView = cardView
        return cardView
    }

    private func installPlayerMenuGesture(on view: NSView) {
        let rightClickGestureRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClickGestureRecognizer.buttonMask = 0x2
        view.addGestureRecognizer(rightClickGestureRecognizer)
    }

    @objc private func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        if let eventNumber = NSApp.currentEvent?.eventNumber {
            guard lastPlayerMenuEventNumber != eventNumber else { return }
            lastPlayerMenuEventNumber = eventNumber
        }
        playerMenuDelegate?.popUpMenu(view: gestureRecognizer.view ?? self)
    }

    private func addSubviewFillingBounds(_ subview: NSView) {
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.leadingAnchor.constraint(equalTo: leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor)
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
