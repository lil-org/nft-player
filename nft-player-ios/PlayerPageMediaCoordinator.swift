import ImageIO
import UIKit

@MainActor
protocol PlayerPageMediaRendering: AnyObject {
    func clearContent()
    func displayLoadedImage(_ image: UIImage, key: DownloadableMediaDescriptor)
    func displayProvisionalImageOverLoadingWebContent(_ image: UIImage)
    func invalidateLocalWebContentLoad()
    func renderImage(
        key: DownloadableMediaDescriptor,
        hideImageUntilLoaded: Bool,
        provisionalImage: UIImage?,
        loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)?,
        onBegin: (() -> Void)?,
        load: (@escaping (UIImage?) -> Void) -> (() -> Void)?,
        fallbackToWebContent: @escaping () -> Void,
        shouldAnimateLoadedImageReplacement: @escaping () -> Bool,
        onDisplayedProvisionalImage: ((UIImage) -> Void)?,
        onLoadedImage: ((UIImage) -> Void)?,
        onSuccess: (() -> Void)?
    )
    func renderWebContent(
        _ html: String,
        hidesEmptyWebContent: Bool,
        onBegin: (() -> Void)?
    )
    func renderLocalWebContent(
        _ html: String,
        contentKind: DownloadableWebMediaKind,
        htmlDirectoryURL: URL,
        readAccessURL: URL,
        hidesEmptyWebContent: Bool,
        provisionalImage: UIImage?,
        onBegin: (() -> Void)?,
        onLoadSuccess: (() async -> Bool)?,
        onLoadFailure: (() async -> Void)?
    )
    func renderNativeMetalCard(
        tokenId: String,
        renderKind: NativeMetalCardRenderKind,
        provisionalImage: UIImage?,
        loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)?
    )
    func preloadWebImage(_ imageURL: URL, completion: ((Bool) -> Void)?)
}

extension FullscreenTokenMediaRenderer: PlayerPageMediaRendering {}

@MainActor
final class PlayerPageMediaCoordinator {
    enum Request {
        case image(DownloadableMediaDescriptor, fallbackHTML: String)
        case downloadableWebMedia(
            DownloadableMediaDescriptor,
            adjacentDescriptor: DownloadableMediaDescriptor?,
            fallbackHTML: String,
            kind: DownloadableWebMediaKind
        )
        case nativeCard(
            tokenId: String,
            kind: NativeMetalCardRenderKind,
            descriptor: DownloadableMediaDescriptor?
        )
        case web(String, onBegin: (() -> Void)? = nil)
    }

    enum ContentMetrics: Equatable {
        case viewport
        case staticImage(CGSize)
        case nativeCard
    }

    enum ReplacementPolicy: Equatable {
        case reset
        case preserveActiveZoom
        case deferWhileZooming
    }

    struct Dependencies {
        var thumbnailDescriptor: (DownloadableMediaDescriptor) -> DownloadableMediaDescriptor?
        var cachedImage: (DownloadableMediaDescriptor) -> UIImage?
        var image: (DownloadableMediaDescriptor, DownloadableMediaRequestPriority) async -> UIImage?
        var knownLocalFileURL: (DownloadableMediaDescriptor) -> URL?
        var existingFileURL: (DownloadableMediaDescriptor) async -> URL?
        var fileVersion: (URL, DownloadableMediaDescriptor) async -> LocalMediaFileVersion
        var imageSize: (URL) async -> CGSize?
        var videoSize: (URL) async -> CGSize?
        var downloadedSourceURL: (DownloadableMediaDescriptor) async -> URL
        var renderDocument: (URL, String) async -> DownloadableTokenHTMLDocument?
        var htmlDirectoryURL: URL
        var readAccessURL: URL

        static var live: Self {
            Self(
                thumbnailDescriptor: {
                    MobileCollectionCatalog.collectionBrowseThumbnailDescriptor(for: $0)
                },
                cachedImage: { DownloadableMediaCache.shared.cachedDecodedImage(for: $0) },
                image: { await DownloadableMediaCache.shared.image(for: $0, priority: $1) },
                knownLocalFileURL: { DownloadableMediaCache.shared.knownLocalFileURL(for: $0) },
                existingFileURL: { await DownloadableMediaCache.shared.existingFileURL(for: $0) },
                fileVersion: { await LocalMediaFileVersion.load(fileURL: $0, descriptor: $1) },
                imageSize: { await PlayerPageMediaCoordinator.imageSize(at: $0) },
                videoSize: { await DownloadableMediaVideoLayout.displaySize(at: $0) },
                downloadedSourceURL: { await DownloadableMediaCache.shared.downloadedSourceURL(for: $0) },
                renderDocument: {
                    await DownloadableTokenHTML.renderDocument(
                        at: $0,
                        baseURL: $1,
                        includesViewportSizeInDocument: false
                    )
                },
                htmlDirectoryURL: DownloadableMediaCache.shared.webViewHTMLDirectoryURL,
                readAccessURL: DownloadableMediaCache.shared.webViewReadAccessURL
            )
        }
    }

    private let renderer: any PlayerPageMediaRendering
    private let dependencies: Dependencies
    private let notificationCenter: NotificationCenter
    private let onContentMetrics: (ContentMetrics, ReplacementPolicy) -> Void
    private let hasActiveZoomTransform: () -> Bool
    private var renderGeneration: UInt = 0

    init(
        renderer: any PlayerPageMediaRendering,
        dependencies: Dependencies = .live,
        notificationCenter: NotificationCenter = .default,
        onContentMetrics: @escaping (ContentMetrics, ReplacementPolicy) -> Void,
        hasActiveZoomTransform: @escaping () -> Bool
    ) {
        self.renderer = renderer
        self.dependencies = dependencies
        self.notificationCenter = notificationCenter
        self.onContentMetrics = onContentMetrics
        self.hasActiveZoomTransform = hasActiveZoomTransform
    }

    isolated deinit {
        cancelVideoSizeLoad()
        cancelLocalMediaMetadataTasks()
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        removeDownloadableMediaCacheObserver()
    }

    func render(_ request: Request) {
        renderGeneration &+= 1
        switch request {
        case let .image(descriptor, fallbackHTML):
            renderImage(descriptor, fallbackHTML: fallbackHTML)
        case let .downloadableWebMedia(descriptor, adjacentDescriptor, fallbackHTML, kind):
            renderDownloadableWebMedia(
                descriptor,
                adjacentDescriptor: adjacentDescriptor,
                fallbackHTML: fallbackHTML,
                mediaKind: kind
            )
        case let .nativeCard(tokenId, kind, descriptor):
            renderNativeMetalCard(tokenId: tokenId, renderKind: kind, descriptor: descriptor)
        case let .web(html, onBegin):
            clearAnimatedRenderContext()
            renderer.renderWebContent(html, hidesEmptyWebContent: false, onBegin: onBegin)
        }
    }

    func displayCachedImage(_ image: UIImage, descriptor: DownloadableMediaDescriptor) {
        renderGeneration &+= 1
        clearAnimatedRenderContext()
        publishContentMetrics(.staticImage(image.size))
        renderer.displayLoadedImage(image, key: descriptor)
    }

    func clear() {
        renderGeneration &+= 1
        clearAnimatedRenderContext()
        renderer.clearContent()
    }

    private func publishContentMetrics(
        _ metrics: ContentMetrics,
        policy: ReplacementPolicy = .reset
    ) {
        onContentMetrics(metrics, policy)
    }

    private static let maximumCachedVideoSizeCount = 24

    private struct AnimatedRenderContext: Equatable {
        let id = UUID()
        let descriptor: DownloadableMediaDescriptor
        let adjacentDescriptor: DownloadableMediaDescriptor?
        let fallbackHTML: String
        let mediaKind: DownloadableWebMediaKind
    }

    nonisolated private struct LocalMediaFileIdentity: Equatable, Hashable, Sendable {
        let descriptor: DownloadableMediaDescriptor
        let fileURL: URL
    }

    nonisolated struct LocalMediaFileVersion: Equatable, Hashable, Sendable {
        let descriptor: DownloadableMediaDescriptor
        let fileURL: URL
        let fileSize: Int?
        let contentModificationDate: Date?

        init(
            fileURL: URL,
            descriptor: DownloadableMediaDescriptor,
            fileSize: Int?,
            contentModificationDate: Date?
        ) {
            self.descriptor = descriptor
            self.fileURL = fileURL
            self.fileSize = fileSize
            self.contentModificationDate = contentModificationDate
        }

        @concurrent
        static func load(
            fileURL: URL,
            descriptor: DownloadableMediaDescriptor
        ) async -> Self {
            let resourceValues = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            return Self(
                fileURL: fileURL,
                descriptor: descriptor,
                fileSize: resourceValues?.fileSize,
                contentModificationDate: resourceValues?.contentModificationDate
            )
        }
    }

    private typealias VideoSizeRequest = LocalMediaFileVersion

    private struct VideoSizeLoad {
        let request: VideoSizeRequest
        let task: Task<Void, Never>
    }

    private struct LocalMediaFileVersionLoad {
        let identity: LocalMediaFileIdentity
        let task: Task<Void, Never>
    }

    private var animatedRenderContext: AnimatedRenderContext?
    private var pendingAnimatedImageURL: URL?
    private var renderedAnimatedImageURL: URL?
    private var renderedAnimatedNextImageURL: URL?
    private var pendingAnimatedNextImageURL: URL?
    private var failedAnimatedLocalContentVersion: LocalMediaFileVersion?
    private var activeAnimatedLocalContentVersion: LocalMediaFileVersion?
    private var provisionalAnimatedMediaImage: UIImage?
    private var provisionalAnimatedMediaImageLoadTask: Task<Void, Never>?
    private var downloadableMediaCacheObserver: NSObjectProtocol?
    private var videoSizeLoad: VideoSizeLoad?
    private var localMediaFileVersionLoad: LocalMediaFileVersionLoad?
    private var htmlDocumentRenderTask: Task<Void, Never>?
    private var imageSizeTask: Task<Void, Never>?
    private var existingAnimatedMediaFileTask: Task<Void, Never>?
    private var checkedAnimatedMediaFileDescriptor: DownloadableMediaDescriptor?
    private var cachedVideoSizes = [VideoSizeRequest: CGSize]()
    private var cachedVideoSizeRequests = [VideoSizeRequest]()

    private func standardThumbnailDescriptor(
        matching descriptor: DownloadableMediaDescriptor
    ) -> DownloadableMediaDescriptor? {
        let thumbnailDescriptor = dependencies.thumbnailDescriptor(descriptor)
        return thumbnailDescriptor == descriptor ? nil : thumbnailDescriptor
    }

    private func renderImage(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        let dependencies = self.dependencies
        let generation = renderGeneration
        let thumbnailDescriptor = standardThumbnailDescriptor(matching: descriptor)
        let provisionalImage = thumbnailDescriptor.flatMap {
            dependencies.cachedImage($0)
        }
        let loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)? = {
            guard provisionalImage == nil, let thumbnailDescriptor else { return nil }
            return { completion in
                let task = Task { @MainActor in
                    let image = await dependencies.image(thumbnailDescriptor, .preservingPrefetch)
                    guard !Task.isCancelled else { return }
                    completion(image)
                }
                return { task.cancel() }
            }
        }()

        clearAnimatedRenderContext()
        renderer.renderImage(
            key: descriptor,
            hideImageUntilLoaded: false,
            provisionalImage: provisionalImage,
            loadProvisionalImage: loadProvisionalImage,
            onBegin: nil,
            load: { completion in
                let task = Task { @MainActor in
                    let image = await dependencies.image(descriptor, .foreground)
                    guard !Task.isCancelled else { return }
                    completion(image)
                }
                return { task.cancel() }
            },
            fallbackToWebContent: { [weak self] in
                guard let self, self.renderGeneration == generation else { return }
                self.renderWebContent(fallbackHTML)
            },
            shouldAnimateLoadedImageReplacement: { [weak self] in
                guard let self, self.renderGeneration == generation else { return false }
                return !self.hasActiveZoomTransform()
            },
            onDisplayedProvisionalImage: { [weak self] image in
                guard let self, self.renderGeneration == generation else { return }
                self.publishContentMetrics(.staticImage(image.size))
            },
            onLoadedImage: { [weak self] image in
                guard let self, self.renderGeneration == generation else { return }
                self.publishContentMetrics(
                    .staticImage(image.size),
                    policy: .preserveActiveZoom
                )
            },
            onSuccess: nil
        )
    }

    private func renderWebContent(_ html: String) {
        clearAnimatedRenderContext()
        publishContentMetrics(.viewport)
        renderAnimatedFallbackWebContent(html)
    }

    private func renderNativeMetalCard(
        tokenId: String,
        renderKind: NativeMetalCardRenderKind,
        descriptor: DownloadableMediaDescriptor?
    ) {
        let dependencies = self.dependencies
        clearAnimatedRenderContext()
        publishContentMetrics(.nativeCard)
        let thumbnailDescriptor = descriptor.flatMap(standardThumbnailDescriptor(matching:))
        let provisionalImage = thumbnailDescriptor.flatMap {
            dependencies.cachedImage($0)
        }
        let loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)? = {
            guard provisionalImage == nil, let thumbnailDescriptor else { return nil }
            return { completion in
                let task = Task { @MainActor in
                    let image = await dependencies.image(thumbnailDescriptor, .preservingPrefetch)
                    guard !Task.isCancelled else { return }
                    completion(image)
                }
                return { task.cancel() }
            }
        }()

        renderer.renderNativeMetalCard(
            tokenId: tokenId,
            renderKind: renderKind,
            provisionalImage: provisionalImage,
            loadProvisionalImage: loadProvisionalImage
        )
    }

    private func renderAnimatedFallbackWebContent(_ html: String) {
        publishContentMetrics(.viewport)
        renderer.renderWebContent(html, hidesEmptyWebContent: false, onBegin: nil)
    }

    private func renderDownloadableWebMedia(
        _ descriptor: DownloadableMediaDescriptor,
        adjacentDescriptor: DownloadableMediaDescriptor? = nil,
        fallbackHTML: String,
        mediaKind: DownloadableWebMediaKind
    ) {
        let thumbnailDescriptor = standardThumbnailDescriptor(matching: descriptor)
        let provisionalImage = thumbnailDescriptor.flatMap {
            dependencies.cachedImage($0)
        }
        if let provisionalImage {
            publishContentMetrics(.staticImage(provisionalImage.size))
        } else {
            publishContentMetrics(.viewport)
        }
        let context = AnimatedRenderContext(
            descriptor: descriptor,
            adjacentDescriptor: adjacentDescriptor,
            fallbackHTML: fallbackHTML,
            mediaKind: mediaKind
        )
        setAnimatedRenderContext(context, provisionalImage: provisionalImage)
        if provisionalImage == nil, let thumbnailDescriptor {
            loadProvisionalAnimatedMediaImage(
                thumbnailDescriptor,
                context: context
            )
        }
        renderAvailableAnimatedLocalContent()
    }

    private func loadProvisionalAnimatedMediaImage(
        _ thumbnailDescriptor: DownloadableMediaDescriptor,
        context: AnimatedRenderContext
    ) {
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        let dependencies = self.dependencies
        provisionalAnimatedMediaImageLoadTask = Task { @MainActor [weak self] in
            let image = await dependencies.image(thumbnailDescriptor, .preservingPrefetch)
            guard !Task.isCancelled,
                  let self,
                  self.animatedRenderContext == context else {
                return
            }

            self.provisionalAnimatedMediaImageLoadTask = nil
            guard let image,
                  self.renderedAnimatedImageURL == nil else {
                return
            }

            self.provisionalAnimatedMediaImage = image
            if dependencies.knownLocalFileURL(context.descriptor) == nil {
                self.publishContentMetrics(.staticImage(image.size))
                self.renderer.displayLoadedImage(image, key: context.descriptor)
            } else {
                self.renderer.displayProvisionalImageOverLoadingWebContent(image)
            }
        }
    }

    private func renderAvailableAnimatedLocalContent() {
        guard let context = animatedRenderContext else { return }

        let dependencies = self.dependencies
        guard let localFileURL = dependencies.knownLocalFileURL(context.descriptor) else {
            resolveExistingAnimatedMediaFileIfNeeded(for: context)
            cancelVideoSizeLoad()
            failedAnimatedLocalContentVersion = nil
            clearAnimatedImageURLState()
            if let provisionalAnimatedMediaImage {
                publishContentMetrics(.staticImage(provisionalAnimatedMediaImage.size))
            }
            displayProvisionalAnimatedMediaImageOrClearContent(for: context)
            return
        }

        let nextLocalFileURL = context.adjacentDescriptor.flatMap {
            dependencies.knownLocalFileURL($0)
        }
        if pendingAnimatedImageURL == localFileURL {
            return
        }
        if renderedAnimatedImageURL == localFileURL {
            guard renderedAnimatedNextImageURL != nextLocalFileURL else { return }
            guard pendingAnimatedNextImageURL != nextLocalFileURL else { return }
            guard let nextLocalFileURL else {
                pendingAnimatedNextImageURL = nil
                renderedAnimatedNextImageURL = nil
                return
            }

            pendingAnimatedNextImageURL = nextLocalFileURL
            renderer.preloadWebImage(nextLocalFileURL) { [weak self] didPreload in
                guard let self,
                      self.animatedRenderContext == context,
                      self.renderedAnimatedImageURL == localFileURL else {
                    return
                }

                if self.pendingAnimatedNextImageURL == nextLocalFileURL {
                    self.pendingAnimatedNextImageURL = nil
                }
                guard didPreload else { return }

                self.renderedAnimatedNextImageURL = nextLocalFileURL
            }
            return
        }

        let identity = LocalMediaFileIdentity(
            descriptor: context.descriptor,
            fileURL: localFileURL
        )
        guard localMediaFileVersionLoad?.identity != identity else { return }
        localMediaFileVersionLoad?.task.cancel()
        let task = Task { [weak self] in
            let localContentVersion = await dependencies.fileVersion(localFileURL, context.descriptor)
            guard !Task.isCancelled,
                  let self,
                  self.localMediaFileVersionLoad?.identity == identity else {
                return
            }
            self.localMediaFileVersionLoad = nil
            guard self.animatedRenderContext == context,
                  self.dependencies.knownLocalFileURL(context.descriptor) == localFileURL else {
                return
            }

            self.renderAvailableAnimatedLocalContent(
                context: context,
                localContentVersion: localContentVersion,
                nextLocalFileURL: nextLocalFileURL
            )
        }
        localMediaFileVersionLoad = LocalMediaFileVersionLoad(
            identity: identity,
            task: task
        )
    }

    private func renderAvailableAnimatedLocalContent(
        context: AnimatedRenderContext,
        localContentVersion: LocalMediaFileVersion,
        nextLocalFileURL: URL?
    ) {
        guard failedAnimatedLocalContentVersion != localContentVersion else { return }
        failedAnimatedLocalContentVersion = nil
        activeAnimatedLocalContentVersion = localContentVersion
        let localFileURL = localContentVersion.fileURL

        let html: String
        switch context.mediaKind {
        case .image:
            loadImageSizeIfNeeded(at: localFileURL, context: context)
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: localFileURL.absoluteString,
                nextImageURL: nextLocalFileURL?.absoluteString
            )
        case .video:
            loadVideoSizeIfNeeded(
                request: localContentVersion,
                context: context
            )
            html = DownloadableTokenHTML.createVideoHTML(videoURL: localFileURL.absoluteString)
        case .htmlDocument:
            renderCachedHTMLDocument(
                context: context,
                localContentVersion: localContentVersion
            )
            return
        }

        renderAnimatedLocalWebContent(
            html,
            context: context,
            localContentVersion: localContentVersion,
            htmlDirectoryURL: dependencies.htmlDirectoryURL,
            readAccessURL: dependencies.readAccessURL
        )
    }

    private func resolveExistingAnimatedMediaFileIfNeeded(
        for context: AnimatedRenderContext
    ) {
        guard existingAnimatedMediaFileTask == nil,
              checkedAnimatedMediaFileDescriptor != context.descriptor else {
            return
        }

        checkedAnimatedMediaFileDescriptor = context.descriptor
        let dependencies = self.dependencies
        existingAnimatedMediaFileTask = Task { @MainActor [weak self] in
            let fileURL = await dependencies.existingFileURL(context.descriptor)
            guard !Task.isCancelled,
                  let self,
                  self.animatedRenderContext == context else {
                return
            }
            self.existingAnimatedMediaFileTask = nil
            guard fileURL != nil else { return }
            self.renderAvailableAnimatedLocalContent()
        }
    }

    private func renderAnimatedLocalWebContent(
        _ html: String,
        context: AnimatedRenderContext,
        localContentVersion: LocalMediaFileVersion,
        htmlDirectoryURL: URL,
        readAccessURL: URL
    ) {
        let fileURL = localContentVersion.fileURL
        pendingAnimatedImageURL = fileURL
        renderer.renderLocalWebContent(
            html,
            contentKind: context.mediaKind,
            htmlDirectoryURL: htmlDirectoryURL,
            readAccessURL: readAccessURL,
            hidesEmptyWebContent: false,
            provisionalImage: provisionalAnimatedMediaImage,
            onBegin: nil,
            onLoadSuccess: { [weak self] in
                guard let self,
                      await self.validateAnimatedLocalContentResult(
                        localContentVersion,
                        context: context
                      ) else { return false }

                self.cancelProvisionalAnimatedMediaImageLoadIfNeeded()
                self.provisionalAnimatedMediaImage = nil
                self.failedAnimatedLocalContentVersion = nil
                self.clearAnimatedImageURLState()
                self.renderedAnimatedImageURL = fileURL
                self.activeAnimatedLocalContentVersion = localContentVersion
                self.renderAvailableAnimatedLocalContent()
                return true
            },
            onLoadFailure: { [weak self] in
                guard let self,
                      await self.validateAnimatedLocalContentResult(
                        localContentVersion,
                        context: context
                      ) else { return }

                self.handleAnimatedLocalContentFailure(
                    context,
                    localContentVersion: localContentVersion
                )
            }
        )
    }

    private func renderCachedHTMLDocument(
        context: AnimatedRenderContext,
        localContentVersion: LocalMediaFileVersion
    ) {
        let fileURL = localContentVersion.fileURL
        displayProvisionalAnimatedMediaImageOrClearContent(for: context)
        pendingAnimatedImageURL = fileURL
        htmlDocumentRenderTask?.cancel()
        let dependencies = self.dependencies
        htmlDocumentRenderTask = Task { [weak self] in
            let downloadedSourceURLString = await dependencies.downloadedSourceURL(context.descriptor).absoluteString
            guard !Task.isCancelled else { return }
            let renderedDocument = await dependencies.renderDocument(
                fileURL,
                downloadedSourceURLString
            )
            guard let self,
                  !Task.isCancelled,
                  await validateAnimatedLocalContentResult(
                    localContentVersion,
                    context: context
                  ) else { return }

            htmlDocumentRenderTask = nil
            guard let renderedDocument else {
                handleAnimatedLocalContentFailure(
                    context,
                    localContentVersion: localContentVersion
                )
                return
            }

            if let viewportSize = renderedDocument.viewportSize {
                publishContentMetrics(
                    .staticImage(viewportSize),
                    policy: .preserveActiveZoom
                )
            } else {
                publishContentMetrics(.viewport)
            }
            renderAnimatedLocalWebContent(
                renderedDocument.html,
                context: context,
                localContentVersion: localContentVersion,
                htmlDirectoryURL: dependencies.htmlDirectoryURL,
                readAccessURL: dependencies.htmlDirectoryURL
            )
        }
    }

    private func validateAnimatedLocalContentResult(
        _ localContentVersion: LocalMediaFileVersion,
        context: AnimatedRenderContext
    ) async -> Bool {
        guard animatedRenderContext == context,
              pendingAnimatedImageURL == localContentVersion.fileURL else {
            return false
        }

        let currentVersion: LocalMediaFileVersion?
        if let currentFileURL = dependencies.knownLocalFileURL(context.descriptor) {
            currentVersion = await dependencies.fileVersion(currentFileURL, context.descriptor)
        } else {
            currentVersion = nil
        }
        guard !Task.isCancelled,
              animatedRenderContext == context,
              pendingAnimatedImageURL == localContentVersion.fileURL else {
            return false
        }
        guard currentVersion != localContentVersion else { return true }

        failedAnimatedLocalContentVersion = nil
        clearAnimatedImageURLState()
        renderer.invalidateLocalWebContentLoad()
        renderAvailableAnimatedLocalContent()
        return false
    }

    private func displayProvisionalAnimatedMediaImageOrClearContent(
        for context: AnimatedRenderContext
    ) {
        if let provisionalAnimatedMediaImage {
            renderer.displayLoadedImage(
                provisionalAnimatedMediaImage,
                key: context.descriptor
            )
        } else {
            renderer.clearContent()
        }
    }

    private func handleAnimatedLocalContentFailure(
        _ context: AnimatedRenderContext,
        localContentVersion: LocalMediaFileVersion
    ) {
        if let provisionalAnimatedMediaImage {
            cancelVideoSizeLoad()
            publishContentMetrics(.staticImage(provisionalAnimatedMediaImage.size))
            failedAnimatedLocalContentVersion = localContentVersion
            clearAnimatedImageURLState()
            displayProvisionalAnimatedMediaImageOrClearContent(for: context)
            return
        }

        clearAnimatedRenderContext()
        renderAnimatedFallbackWebContent(context.fallbackHTML)
    }

    private func loadImageSizeIfNeeded(
        at fileURL: URL,
        context: AnimatedRenderContext
    ) {
        imageSizeTask?.cancel()
        let dependencies = self.dependencies
        imageSizeTask = Task { [weak self] in
            let size = await dependencies.imageSize(fileURL)
            guard let self,
                  !Task.isCancelled,
                  animatedRenderContext == context,
                  (pendingAnimatedImageURL == fileURL
                    || renderedAnimatedImageURL == fileURL) else {
                return
            }
            imageSizeTask = nil
            guard let size else { return }
            publishContentMetrics(
                .staticImage(size),
                policy: .preserveActiveZoom
            )
        }
    }

    @concurrent
    nonisolated private static func imageSize(at fileURL: URL) async -> CGSize? {
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

    private func loadVideoSizeIfNeeded(
        request: VideoSizeRequest,
        context: AnimatedRenderContext
    ) {
        if let videoSizeLoad, videoSizeLoad.request != request {
            cancelVideoSizeLoad()
        }

        if let cachedSize = cachedVideoSizes[request] {
            applyVideoSizeIfCurrent(cachedSize, for: request)
            return
        }

        guard videoSizeLoad == nil else { return }

        let fileURL = request.fileURL
        let dependencies = self.dependencies
        let task = Task { [weak self, fileURL, request] in
            let size = await dependencies.videoSize(fileURL)
            guard !Task.isCancelled,
                  let self,
                  videoSizeLoad?.request == request else {
                return
            }

            let currentVersion = await dependencies.fileVersion(fileURL, request.descriptor)
            guard !Task.isCancelled,
                  videoSizeLoad?.request == request else { return }
            videoSizeLoad = nil
            guard currentVersion == request else {
                failedAnimatedLocalContentVersion = nil
                clearAnimatedImageURLState()
                renderer.invalidateLocalWebContentLoad()
                renderAvailableAnimatedLocalContent()
                return
            }
            guard let size else { return }

            cacheVideoSize(size, for: request)
            applyVideoSizeIfCurrent(size, for: request)
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

    func reapplyCurrentVideoMetrics() {
        guard let context = animatedRenderContext,
              context.mediaKind == .video,
              let request = activeAnimatedLocalContentVersion,
              request.descriptor == context.descriptor else {
            return
        }

        guard let cachedSize = cachedVideoSizes[request] else { return }

        applyVideoSizeIfCurrent(cachedSize, for: request)
    }

    private func applyVideoSizeIfCurrent(_ size: CGSize, for request: VideoSizeRequest) {
        guard let context = animatedRenderContext,
              context.mediaKind == .video,
              context.descriptor == request.descriptor,
              dependencies.knownLocalFileURL(request.descriptor) == request.fileURL,
              activeAnimatedLocalContentVersion == request else {
            return
        }

        publishContentMetrics(.staticImage(size), policy: .deferWhileZooming)
    }

    private func cancelVideoSizeLoad() {
        videoSizeLoad?.task.cancel()
        videoSizeLoad = nil
    }

    private func cancelProvisionalAnimatedMediaImageLoadIfNeeded() {
        provisionalAnimatedMediaImageLoadTask?.cancel()
        provisionalAnimatedMediaImageLoadTask = nil
    }

    private func setAnimatedRenderContext(
        _ context: AnimatedRenderContext,
        provisionalImage: UIImage?
    ) {
        cancelVideoSizeLoad()
        cancelLocalMediaMetadataTasks()
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        animatedRenderContext = context
        provisionalAnimatedMediaImage = provisionalImage
        failedAnimatedLocalContentVersion = nil
        clearAnimatedImageURLState()
        installDownloadableMediaCacheObserverIfNeeded()
    }

    private func clearAnimatedRenderContext() {
        cancelVideoSizeLoad()
        cancelLocalMediaMetadataTasks()
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        animatedRenderContext = nil
        provisionalAnimatedMediaImage = nil
        failedAnimatedLocalContentVersion = nil
        clearAnimatedImageURLState()
        removeDownloadableMediaCacheObserver()
    }

    private func cancelLocalMediaMetadataTasks() {
        htmlDocumentRenderTask?.cancel()
        htmlDocumentRenderTask = nil
        imageSizeTask?.cancel()
        imageSizeTask = nil
        localMediaFileVersionLoad?.task.cancel()
        localMediaFileVersionLoad = nil
        existingAnimatedMediaFileTask?.cancel()
        existingAnimatedMediaFileTask = nil
        checkedAnimatedMediaFileDescriptor = nil
    }

    private func clearAnimatedImageURLState() {
        pendingAnimatedImageURL = nil
        renderedAnimatedImageURL = nil
        renderedAnimatedNextImageURL = nil
        pendingAnimatedNextImageURL = nil
        activeAnimatedLocalContentVersion = nil
    }

    private func installDownloadableMediaCacheObserverIfNeeded() {
        guard downloadableMediaCacheObserver == nil else { return }

        downloadableMediaCacheObserver = notificationCenter.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderAvailableAnimatedLocalContent()
            }
        }
    }

    private func removeDownloadableMediaCacheObserver() {
        guard let downloadableMediaCacheObserver else { return }

        notificationCenter.removeObserver(downloadableMediaCacheObserver)
        self.downloadableMediaCacheObserver = nil
    }

}
