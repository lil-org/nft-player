// ∅ 2026 lil org

import UIKit
import SwiftUI
import WebKit
import ImageIO
import AVFoundation

enum FullscreenTokenMediaView {
    static func imageView(in containerView: UIView) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        install(imageView, in: containerView)
        return imageView
    }

    static func webView(in containerView: UIView) -> AutoReloadingWebView {
        let webView = AutoReloadingWebView.new
        webView.isUserInteractionEnabled = false
        install(webView, in: containerView)
        return webView
    }

    static func nativeMetalCardView(in containerView: UIView) -> NativeMetalCardView {
        let cardView = NativeMetalCardView()
        cardView.isUserInteractionEnabled = false
        cardView.isHidden = true
        install(cardView, in: containerView)
        return cardView
    }

    private static func install(_ view: UIView, in containerView: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            view.topAnchor.constraint(equalTo: containerView.topAnchor),
            view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
}

fileprivate enum DownloadableWebMediaKind: Equatable {
    case image, video, htmlDocument
}

final class FullscreenTokenMediaRenderer {
    private typealias ImageLoadCancellation = () -> Void

    private let containerView: UIView
    private var webView: AutoReloadingWebView!
    private var imageView: UIImageView!
    private var imageSpreadStackView: UIStackView!
    private var imageSpreadArrangement: ImageSpreadArrangement?
    private var imageSpreadNestedStackViews = [UIStackView]()
    private var imageSpreadViews = [UIImageView]()
    private var imageSpreadPlaceholderViews = [PlayerMediaPlaceholderView]()
    private var imageSpreadPlaceholderSpecs = [PlayerMediaPlaceholderSpec]()
    private var imageSpreadVerifiedImages = [Bool]()
    private var imageSpreadResolvedImages = [Bool]()
    private var imageSpreadNativeMetalCardCornerMaskIndices = Set<Int>()
    private var nativeMetalCardView: NativeMetalCardView!
    private var representedImageKey: AnyHashable?
    private var activeImageLoadId: UUID?
    private var cancelActiveImageLoad: ImageLoadCancellation?
    private var webViewMayContainContent = false
    private var activeLocalWebReadinessID: UUID?
    private var usesTransparentPlayerBackground = false
    private var representedImageSpreadSlotKeys = [AnyHashable]()
    private var rememberedImageSpread: RememberedImageSpread?

    private enum ImageSpreadArrangement: Equatable {
        case linear
        case grid(MobileStaticImageSpreadGrid)
    }

    private struct RememberedImageSpread {
        let key: AnyHashable
        let slotKeys: [AnyHashable]
        let images: [UIImage?]
        let resolvedImages: [Bool]
    }

    init(containerView: UIView) {
        self.containerView = containerView
    }

    deinit {
        cancelCurrentImageLoad()
        nativeMetalCardView?.stop()
    }

    func clearContent() {
        activeLocalWebReadinessID = nil
        cancelCurrentImageLoad()
        hideNativeMetalCardView()
        representedImageKey = nil
        representedImageSpreadSlotKeys = []
        unloadWebContentIfNeeded()
        imageView?.layer.removeAllAnimations()
        imageView?.image = nil
        clearImageSpread()
        rememberedImageSpread = nil
    }

    func displayLoadedImage<Key: Hashable>(_ image: UIImage, key: Key) {
        cancelCurrentImageLoad()
        hideNativeMetalCardView()
        hideImageSpread()
        let imageKey = AnyHashable(key)
        representedImageKey = imageKey
        representedImageSpreadSlotKeys = []
        webView?.isHidden = true
        displayMainImage(image)

        unloadWebContentAfterImageDisplay(imageKey: imageKey)
    }

    func displayProvisionalImageOverLoadingWebContent(_ image: UIImage) {
        cancelCurrentImageLoad()
        representedImageKey = nil
        representedImageSpreadSlotKeys = []
        hideNativeMetalCardView()
        hideImageSpread()
        displayMainImage(image, bringsToFront: true)
    }

    func invalidateLocalWebContentLoad() {
        activeLocalWebReadinessID = nil
        webView?.invalidateRequestedContent()
    }

    func displayedImage() -> UIImage? {
        guard let imageView,
              !imageView.isHidden else {
            return nil
        }

        return imageView.image
    }

    func imageSpreadIndex(
        at location: CGPoint,
        in coordinateView: UIView,
        requiresVerifiedImage: Bool = true
    ) -> Int? {
        guard let imageSpreadStackView,
              !imageSpreadStackView.isHidden,
              imageSpreadStackView.window != nil else {
            return nil
        }

        return imageSpreadViews.enumerated().first { index, imageView in
            guard !imageView.isHidden,
                  imageView.window != nil else {
                return false
            }
            if requiresVerifiedImage {
                guard imageView.image != nil,
                      isImageSpreadImageVerified(at: index) else {
                    return false
                }
            }

            let locationInImageView = imageView.convert(location, from: coordinateView)
            return imageView.bounds.contains(locationInImageView)
        }?.offset
    }

    func imageSpreadImages() -> [UIImage?]? {
        guard let imageSpreadStackView,
              !imageSpreadStackView.isHidden,
              imageSpreadStackView.window != nil else {
            return nil
        }

        guard imageSpreadVerifiedImages.count == imageSpreadViews.count else {
            return Array<UIImage?>(repeating: nil, count: imageSpreadViews.count)
        }

        return verifiedImageSpreadImages()
    }

    @discardableResult
    func displayRecoveredImage<SpreadKey: Hashable, SlotKey: Hashable>(
        _ image: UIImage,
        at index: Int,
        spreadKey: SpreadKey,
        slotKey: SlotKey
    ) -> Bool {
        let imageKey = AnyHashable(spreadKey)
        guard representedImageKey == imageKey,
              representedImageSpreadSlotKeys.indices.contains(index),
              representedImageSpreadSlotKeys[index] == AnyHashable(slotKey),
              imageSpreadViews.indices.contains(index),
              imageSpreadVerifiedImages.indices.contains(index),
              imageSpreadResolvedImages.indices.contains(index),
              imageSpreadPlaceholderViews.indices.contains(index),
              let imageSpreadStackView,
              !imageSpreadStackView.isHidden else {
            return false
        }

        displayImage(image, in: imageSpreadViews[index])
        imageSpreadVerifiedImages[index] = true
        imageSpreadResolvedImages[index] = true
        hideImageSpreadPlaceholder(at: index, animated: true)
        unloadWebContentAfterImageDisplay(imageKey: imageKey)
        return true
    }

    func renderImage<Key: Hashable>(
        key: Key,
        hideImageUntilLoaded: Bool,
        provisionalImage: UIImage? = nil,
        loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)? = nil,
        onBegin: (() -> Void)? = nil,
        load: (@escaping (UIImage?) -> Void) -> (() -> Void)?,
        fallbackToWebContent: @escaping () -> Void,
        onDisplayedProvisionalImage: ((UIImage) -> Void)? = nil,
        onLoadedImage: ((UIImage) -> Void)? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        cancelCurrentImageLoad()
        ensureImageView()
        imageView.layer.removeAllAnimations()
        hideWebContent()
        hideNativeMetalCardView()
        hideImageSpread()
        imageView.isHidden = hideImageUntilLoaded && provisionalImage == nil
        imageView.image = provisionalImage
        if let provisionalImage {
            onDisplayedProvisionalImage?(provisionalImage)
        }
        onBegin?()

        let imageKey = AnyHashable(key)
        let imageLoadId = UUID()
        representedImageKey = imageKey
        activeImageLoadId = imageLoadId
        var primaryImageResolved = false
        var provisionalImageResolved = provisionalImage != nil || loadProvisionalImage == nil
        var primaryCancellation: ImageLoadCancellation?
        var provisionalCancellation: ImageLoadCancellation?

        func isCurrentLoad(in renderer: FullscreenTokenMediaRenderer) -> Bool {
            renderer.representedImageKey == imageKey && renderer.activeImageLoadId == imageLoadId
        }

        func cancelLoads() {
            let cancelPrimary = primaryCancellation
            let cancelProvisional = provisionalCancellation
            primaryCancellation = nil
            provisionalCancellation = nil
            cancelPrimary?()
            cancelProvisional?()
        }

        func finishFailedPrimaryIfReady(in renderer: FullscreenTokenMediaRenderer) {
            guard isCurrentLoad(in: renderer),
                  primaryImageResolved,
                  provisionalImageResolved else {
                return
            }

            renderer.cancelActiveImageLoad = nil
            renderer.activeImageLoadId = nil
            cancelLoads()
            if renderer.imageView.image != nil {
                renderer.imageView.isHidden = false
                renderer.unloadWebContentAfterImageDisplay(imageKey: imageKey)
            } else {
                fallbackToWebContent()
            }
        }

        cancelActiveImageLoad = {
            cancelLoads()
        }

        primaryCancellation = load { [weak self] image in
            guard let self, isCurrentLoad(in: self) else { return }

            primaryCancellation = nil
            primaryImageResolved = true
            guard let image else {
                finishFailedPrimaryIfReady(in: self)
                return
            }

            self.cancelActiveImageLoad = nil
            self.activeImageLoadId = nil
            cancelLoads()
            onSuccess?()
            self.webView?.isHidden = true
            self.imageView.isHidden = false
            self.displayImage(image, in: self.imageView)
            self.unloadWebContentAfterImageDisplay(imageKey: imageKey)
            onLoadedImage?(image)
        }

        guard isCurrentLoad(in: self) else {
            cancelLoads()
            return
        }

        if provisionalImage == nil, let loadProvisionalImage {
            provisionalCancellation = loadProvisionalImage { [weak self] image in
                guard let self, isCurrentLoad(in: self) else { return }

                provisionalCancellation = nil
                provisionalImageResolved = true
                if let image {
                    self.imageView.image = image
                    self.imageView.isHidden = false
                    onDisplayedProvisionalImage?(image)
                }
                finishFailedPrimaryIfReady(in: self)
            }
        }

        guard isCurrentLoad(in: self) else {
            cancelLoads()
            return
        }
    }

    func renderImageSpread<Key: Hashable>(
        key: Key,
        pageLayout: MobilePlayerPageLayout,
        viewportSize: CGSize? = nil,
        nativeMetalCardCornerMaskIndices: Set<Int> = [],
        mediaPlaceholderSpecs: [PlayerMediaPlaceholderSpec]? = nil,
        initialImages: [UIImage?]? = nil,
        placeholderImages: [UIImage?]? = nil,
        imageSlotKeys: [AnyHashable]? = nil,
        loadImages: [(@escaping (UIImage?) -> Void) -> (() -> Void)?],
        onEmptySpread: @escaping () -> Void,
        onImageLoadFailure: ((Int) -> Void)? = nil,
        onLoadedImages: (([UIImage?]) -> Void)? = nil
    ) {
        guard !loadImages.isEmpty else {
            onEmptySpread()
            return
        }

        rememberCurrentImageSpread()
        let imageKey = AnyHashable(key)
        cancelCurrentImageLoad()
        imageSpreadNativeMetalCardCornerMaskIndices = nativeMetalCardCornerMaskIndices
        imageSpreadPlaceholderSpecs = mediaPlaceholderSpecs?.count == loadImages.count
            ? mediaPlaceholderSpecs ?? []
            : []
        ensureImageSpreadStackView(
            imageCount: loadImages.count,
            pageLayout: pageLayout,
            viewportSize: viewportSize
        )
        configureImageSpreadCornerMasks()
        hideWebContent()
        hideNativeMetalCardView()
        imageView?.layer.removeAllAnimations()
        imageView?.isHidden = true
        imageView?.image = nil
        imageSpreadStackView.isHidden = false
        let validInitialImages = initialImages?.count == loadImages.count ? initialImages : nil
        let validPlaceholderImages = placeholderImages?.count == loadImages.count ? placeholderImages : nil
        let validImageSlotKeys = imageSlotKeys?.count == loadImages.count ? imageSlotKeys : nil
        let rememberedSpread = rememberedImageSpread(
            for: imageKey,
            slotKeys: validImageSlotKeys,
            imageCount: loadImages.count
        )
        let seedImages = loadImages.indices.map { index in
            validInitialImages?[index] ?? rememberedSpread?.images[index] ?? validPlaceholderImages?[index]
        }
        let seedImagesResolved = loadImages.indices.map { index in
            validInitialImages?[index] != nil
                || (rememberedSpread?.images[index] != nil && rememberedSpread?.resolvedImages[index] == true)
        }
        for (index, imageView) in imageSpreadViews.enumerated() {
            imageView.layer.removeAllAnimations()
            imageView.image = seedImages[index]
        }
        configureImageSpreadPlaceholders(seedImages: seedImages)
        imageSpreadVerifiedImages = seedImages.map { $0 != nil }
        imageSpreadResolvedImages = seedImagesResolved

        let imageLoadId = UUID()
        representedImageKey = imageKey
        representedImageSpreadSlotKeys = validImageSlotKeys ?? []
        activeImageLoadId = imageLoadId

        var loadedImages = seedImages
        var resolvedSlots = seedImagesResolved
        var cancellations = Array<ImageLoadCancellation?>(repeating: nil, count: loadImages.count)

        func isCurrentLoad(in renderer: FullscreenTokenMediaRenderer) -> Bool {
            renderer.representedImageKey == imageKey && renderer.activeImageLoadId == imageLoadId
        }

        func cancelSpreadLoads() {
            cancellations.forEach { $0?() }
            cancellations = Array(repeating: nil, count: loadImages.count)
        }

        func completeWithFallbackIfCurrent(in renderer: FullscreenTokenMediaRenderer) {
            guard isCurrentLoad(in: renderer) else { return }

            renderer.cancelActiveImageLoad = nil
            renderer.activeImageLoadId = nil
            cancelSpreadLoads()
            onEmptySpread()
        }

        func finishIfReady(in renderer: FullscreenTokenMediaRenderer) {
            guard isCurrentLoad(in: renderer) else { return }
            guard resolvedSlots.allSatisfy({ $0 }) else { return }
            guard loadedImages.contains(where: { $0 != nil }) else {
                completeWithFallbackIfCurrent(in: renderer)
                return
            }

            renderer.cancelActiveImageLoad = nil
            renderer.activeImageLoadId = nil
            cancellations = Array(repeating: nil, count: loadImages.count)
            renderer.webView?.isHidden = true
            renderer.imageSpreadStackView?.isHidden = false
            renderer.unloadWebContentAfterImageDisplay(imageKey: imageKey)
            onLoadedImages?(loadedImages)
        }

        finishIfReady(in: self)
        guard isCurrentLoad(in: self) else { return }

        for (index, loadImage) in loadImages.enumerated() {
            guard !resolvedSlots[index] else { continue }

            cancellations[index] = loadImage { [weak self] image in
                guard let self, isCurrentLoad(in: self) else { return }
                guard let image else {
                    resolvedSlots[index] = true
                    onImageLoadFailure?(index)
                    finishIfReady(in: self)
                    return
                }

                loadedImages[index] = image
                resolvedSlots[index] = true
                if self.imageSpreadViews.indices.contains(index) {
                    self.displayImage(image, in: self.imageSpreadViews[index])
                    self.hideImageSpreadPlaceholder(at: index, animated: true)
                }
                if self.imageSpreadVerifiedImages.indices.contains(index) {
                    self.imageSpreadVerifiedImages[index] = true
                }
                if self.imageSpreadResolvedImages.indices.contains(index) {
                    self.imageSpreadResolvedImages[index] = true
                }
                finishIfReady(in: self)
            }
        }

        guard isCurrentLoad(in: self) else {
            cancelSpreadLoads()
            return
        }

        cancelActiveImageLoad = {
            cancelSpreadLoads()
        }
    }

    func renderWebContent(
        _ html: String,
        hidesEmptyWebContent: Bool = false,
        onBegin: (() -> Void)? = nil
    ) {
        prepareWebContent(
            html,
            hidesEmptyWebContent: hidesEmptyWebContent,
            provisionalImage: nil,
            onBegin: onBegin
        )
        webView.loadHTMLString(html, baseURL: nil)
    }

    fileprivate func renderLocalWebContent(
        _ html: String,
        contentKind: DownloadableWebMediaKind,
        htmlDirectoryURL: URL,
        readAccessURL: URL,
        hidesEmptyWebContent: Bool = false,
        provisionalImage: UIImage? = nil,
        onBegin: (() -> Void)? = nil,
        onLoadSuccess: (() -> Bool)? = nil,
        onLoadFailure: (() -> Void)? = nil
    ) {
        prepareWebContent(
            html,
            hidesEmptyWebContent: hidesEmptyWebContent,
            provisionalImage: provisionalImage,
            onBegin: onBegin
        )
        let readinessID = UUID()
        activeLocalWebReadinessID = readinessID
        webView.loadLocalHTMLString(
            html,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onSuccess: { [weak self] in
                self?.revealLocalWebContentWhenReady(
                    html,
                    contentKind: contentKind,
                    hidesEmptyWebContent: hidesEmptyWebContent,
                    readinessID: readinessID,
                    onLoadSuccess: onLoadSuccess,
                    onLoadFailure: onLoadFailure
                )
            },
            onFailure: { [weak self] in
                guard let self,
                      self.activeLocalWebReadinessID == readinessID else {
                    return
                }

                self.activeLocalWebReadinessID = nil
                onLoadFailure?()
            }
        )
    }

    func renderNativeMetalCard(
        tokenId: String,
        renderKind: NativeMetalCardRenderKind
    ) {
        rememberCurrentImageSpread()
        cancelCurrentImageLoad()
        representedImageKey = nil
        representedImageSpreadSlotKeys = []
        ensureNativeMetalCardView()
        imageView?.isHidden = true
        imageView?.image = nil
        hideImageSpread()
        hideWebContent()
        nativeMetalCardView.display(
            tokenId: tokenId,
            renderKind: renderKind
        )
    }

    func setImageSpreadAxis(_ axis: NSLayoutConstraint.Axis) {
        guard imageSpreadStackView != nil,
              !imageSpreadViews.isEmpty else {
            return
        }

        if imageSpreadArrangement != .linear {
            rebuildImageSpreadStackView(
                imageCount: imageSpreadViews.count,
                arrangement: .linear,
                preservedImages: imageSpreadViews.map(\.image),
                preservedImageVerification: imageSpreadVerifiedImages,
                preservedImageResolution: imageSpreadResolvedImages,
                isHidden: imageSpreadStackView?.isHidden ?? true
            )
        }

        imageSpreadStackView?.axis = axis
    }

    func setImageSpreadGrid(_ grid: MobileStaticImageSpreadGrid) {
        guard imageSpreadStackView != nil,
              !imageSpreadViews.isEmpty,
              imageSpreadArrangement != .grid(grid) else {
            return
        }

        rebuildImageSpreadStackView(
            imageCount: imageSpreadViews.count,
            arrangement: .grid(grid),
            preservedImages: imageSpreadViews.map(\.image),
            preservedImageVerification: imageSpreadVerifiedImages,
            preservedImageResolution: imageSpreadResolvedImages,
            isHidden: imageSpreadStackView?.isHidden ?? true
        )
    }

    func preloadWebImage(_ imageURL: URL, completion: ((Bool) -> Void)? = nil) {
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

    func makePlayerBackgroundTransparent() {
        usesTransparentPlayerBackground = true
        containerView.makeBackgroundTransparent()
        if let imageView = imageView {
            imageView.makeBackgroundTransparent()
        }
        if let imageSpreadStackView {
            imageSpreadStackView.makeBackgroundTransparent()
            imageSpreadNestedStackViews.forEach { $0.makeBackgroundTransparent() }
            imageSpreadViews.forEach { $0.makeBackgroundTransparent() }
        }
        webView?.makePlayerBackgroundTransparent()
        if let nativeMetalCardView = nativeMetalCardView {
            nativeMetalCardView.makeBackgroundTransparent()
        }
    }

    private func revealLocalWebContentWhenReady(
        _ html: String,
        contentKind: DownloadableWebMediaKind,
        hidesEmptyWebContent: Bool,
        readinessID: UUID,
        onLoadSuccess: (() -> Bool)?,
        onLoadFailure: (() -> Void)?
    ) {
        guard activeLocalWebReadinessID == readinessID else { return }

        webView.isHidden = hidesEmptyWebContent && html.isEmpty
        if let imageView, !imageView.isHidden {
            containerView.bringSubviewToFront(imageView)
        }
        webView.callAsyncJavaScript(
            Self.localWebMediaReadinessJavaScript(for: contentKind),
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self,
                  self.activeLocalWebReadinessID == readinessID else {
                return
            }

            guard case .success(let value) = result,
                  (value as? Bool) == true else {
                self.invalidateLocalWebContentLoad()
                onLoadFailure?()
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.activeLocalWebReadinessID == readinessID else {
                    return
                }

                self.activeLocalWebReadinessID = nil
                guard onLoadSuccess?() ?? true else { return }

                self.revealLoadedWebContent(
                    html,
                    hidesEmptyWebContent: hidesEmptyWebContent
                )
            }
        }
    }

    private static func localWebMediaReadinessJavaScript(
        for contentKind: DownloadableWebMediaKind
    ) -> String {
        let kind: String
        let elementID: String
        switch contentKind {
        case .image:
            kind = "image"
            elementID = DownloadableTokenHTML.imageElementId
        case .video:
            kind = "video"
            elementID = DownloadableTokenHTML.videoElementId
        case .htmlDocument:
            kind = "iframe"
            elementID = DownloadableTokenHTML.htmlDocumentElementId
        }

        return """
        const kind = "\(kind)";
        const element = document.getElementById("\(elementID)");

        if (!element) {
            return false;
        }

        function waitForTerminalEvent(successEventNames) {
            return new Promise((resolve) => {
                let isSettled = false;
                const settle = (didLoad) => {
                    if (!isSettled) {
                        isSettled = true;
                        resolve(didLoad);
                    }
                };
                for (const eventName of successEventNames) {
                    element.addEventListener(eventName, () => settle(true), { once: true });
                }
                element.addEventListener("error", () => settle(false), { once: true });
            });
        }

        async function waitForMedia() {
            if (kind === "image") {
                if (!element.complete && !(await waitForTerminalEvent(["load"]))) {
                    return false;
                }
                if (typeof element.decode === "function") {
                    try {
                        await element.decode();
                    } catch (_) {}
                }
                return element.complete
                    && element.naturalWidth > 0
                    && element.naturalHeight > 0;
            }

            if (kind === "video") {
                if (element.error) {
                    return false;
                }
                if (element.readyState < HTMLMediaElement.HAVE_CURRENT_DATA
                    && !(await waitForTerminalEvent(["loadeddata", "canplay"]))) {
                    return false;
                }
                if (element.error
                    || element.readyState < HTMLMediaElement.HAVE_CURRENT_DATA
                    || element.videoWidth <= 0
                    || element.videoHeight <= 0) {
                    return false;
                }
                try {
                    const playPromise = element.play();
                    if (playPromise && typeof playPromise.catch === "function") {
                        playPromise.catch(() => {});
                    }
                } catch (_) {}
                if (typeof element.requestVideoFrameCallback === "function") {
                    await Promise.race([
                        new Promise((resolve) => element.requestVideoFrameCallback(resolve)),
                        new Promise((resolve) => setTimeout(resolve, 250)),
                    ]);
                }
                return true;
            }

            try {
                if (element.contentDocument?.readyState === "complete") {
                    return true;
                }
            } catch (_) {}
            return await waitForTerminalEvent(["load"]);
        }

        const didBecomeReady = await waitForMedia();
        if (!didBecomeReady) {
            return false;
        }
        await new Promise((resolve) => {
            requestAnimationFrame(() => requestAnimationFrame(resolve));
        });
        return true;
        """
    }

    private func prepareWebContent(
        _ html: String,
        hidesEmptyWebContent: Bool,
        provisionalImage: UIImage?,
        onBegin: (() -> Void)?
    ) {
        activeLocalWebReadinessID = nil
        rememberCurrentImageSpread()
        cancelCurrentImageLoad()
        representedImageKey = nil
        representedImageSpreadSlotKeys = []
        ensureWebView()
        if let provisionalImage {
            displayMainImage(provisionalImage, bringsToFront: true)
        } else {
            imageView?.isHidden = true
            imageView?.image = nil
        }
        hideImageSpread()
        hideNativeMetalCardView()
        webView.stopLoading()
        webViewMayContainContent = !html.isEmpty
        webView.isHidden = provisionalImage != nil || (hidesEmptyWebContent && html.isEmpty)
        onBegin?()
    }

    private func revealLoadedWebContent(
        _ html: String,
        hidesEmptyWebContent: Bool
    ) {
        imageView?.layer.removeAllAnimations()
        imageView?.isHidden = true
        imageView?.image = nil
        webView.isHidden = hidesEmptyWebContent && html.isEmpty
    }

    private func displayMainImage(_ image: UIImage, bringsToFront: Bool = false) {
        ensureImageView()
        imageView.layer.removeAllAnimations()
        imageView.image = image
        imageView.isHidden = false
        if bringsToFront {
            containerView.bringSubviewToFront(imageView)
        }
    }

    private func cancelCurrentImageLoad() {
        let cancellation = cancelActiveImageLoad
        cancelActiveImageLoad = nil
        activeImageLoadId = nil
        cancellation?()
    }

    private func rememberCurrentImageSpread() {
        guard let imageSpreadStackView,
              !imageSpreadStackView.isHidden,
              let representedImageKey,
              !imageSpreadViews.isEmpty else {
            return
        }

        guard let verifiedImages = verifiedImageSpreadImages(),
              representedImageSpreadSlotKeys.count == verifiedImages.count,
              imageSpreadResolvedImages.count == verifiedImages.count else { return }

        guard verifiedImages.contains(where: { $0 != nil }) else { return }

        rememberedImageSpread = RememberedImageSpread(
            key: representedImageKey,
            slotKeys: representedImageSpreadSlotKeys,
            images: verifiedImages,
            resolvedImages: imageSpreadResolvedImages
        )
    }

    private func rememberedImageSpread(
        for imageKey: AnyHashable,
        slotKeys: [AnyHashable]?,
        imageCount: Int
    ) -> RememberedImageSpread? {
        guard let rememberedImageSpread,
              rememberedImageSpread.key == imageKey,
              rememberedImageSpread.images.count == imageCount,
              rememberedImageSpread.resolvedImages.count == imageCount,
              let slotKeys,
              rememberedImageSpread.slotKeys == slotKeys else {
            self.rememberedImageSpread = nil
            return nil
        }

        self.rememberedImageSpread = nil
        return rememberedImageSpread
    }

    private func verifiedImageSpreadImages() -> [UIImage?]? {
        guard imageSpreadVerifiedImages.count == imageSpreadViews.count else {
            return nil
        }

        return zip(imageSpreadViews, imageSpreadVerifiedImages).map { imageView, isVerified in
            isVerified ? imageView.image : nil
        }
    }

    private func displayImage(_ image: UIImage, in imageView: UIImageView) {
        guard imageView.image != nil else {
            imageView.image = image
            return
        }

        UIView.transition(
            with: imageView,
            duration: 0.12,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
            animations: {
                imageView.image = image
            }
        )
    }

    private func ensureImageView() {
        guard imageView == nil else { return }

        imageView = FullscreenTokenMediaView.imageView(in: containerView)
        if usesTransparentPlayerBackground {
            imageView.makeBackgroundTransparent()
        }
    }

    private func ensureImageSpreadStackView(
        imageCount: Int,
        pageLayout: MobilePlayerPageLayout,
        viewportSize: CGSize? = nil
    ) {
        guard imageCount > 0 else { return }
        let arrangement = imageSpreadArrangement(
            imageCount: imageCount,
            pageLayout: pageLayout,
            viewportSize: viewportSize
        )
        if imageSpreadStackView != nil,
           imageSpreadViews.count == imageCount,
           imageSpreadArrangement == arrangement {
            return
        }

        rebuildImageSpreadStackView(
            imageCount: imageCount,
            arrangement: arrangement,
            preservedImages: imageSpreadViews.count == imageCount ? imageSpreadViews.map(\.image) : [],
            preservedImageVerification: imageSpreadViews.count == imageCount ? imageSpreadVerifiedImages : [],
            preservedImageResolution: imageSpreadViews.count == imageCount ? imageSpreadResolvedImages : [],
            isHidden: imageSpreadStackView?.isHidden ?? true
        )
    }

    private func imageSpreadArrangement(
        imageCount: Int,
        pageLayout: MobilePlayerPageLayout,
        viewportSize: CGSize?
    ) -> ImageSpreadArrangement {
        let fittingSize = viewportSize ?? containerView.bounds.size
        if let grid = MobileStaticImageSpreadGrid.grid(
            for: pageLayout,
            imageCount: imageCount,
            fitting: fittingSize
        ) {
            return .grid(grid)
        }

        return .linear
    }

    private func rebuildImageSpreadStackView(
        imageCount: Int,
        arrangement: ImageSpreadArrangement,
        preservedImages: [UIImage?],
        preservedImageVerification: [Bool],
        preservedImageResolution: [Bool],
        isHidden: Bool
    ) {
        imageSpreadStackView?.removeFromSuperview()
        imageSpreadStackView = nil
        imageSpreadArrangement = nil
        imageSpreadNestedStackViews.removeAll()
        imageSpreadPlaceholderViews.removeAll()

        imageSpreadViews = (0..<imageCount).map { _ in
            let imageView = NativeMetalCardCornerMaskedImageView()
            imageView.backgroundColor = .black
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            if usesTransparentPlayerBackground {
                imageView.makeBackgroundTransparent()
            }
            return imageView
        }
        imageSpreadPlaceholderViews = (0..<imageCount).map { _ in
            PlayerMediaPlaceholderView()
        }

        let populatedSlotViews = zip(imageSpreadPlaceholderViews, imageSpreadViews).map { placeholderView, imageView in
            let slotView = UIView()
            slotView.backgroundColor = .clear
            slotView.isUserInteractionEnabled = false
            placeholderView.translatesAutoresizingMaskIntoConstraints = false
            imageView.translatesAutoresizingMaskIntoConstraints = false
            slotView.addSubview(imageView)
            slotView.addSubview(placeholderView)
            NSLayoutConstraint.activate([
                placeholderView.leadingAnchor.constraint(equalTo: slotView.leadingAnchor),
                placeholderView.trailingAnchor.constraint(equalTo: slotView.trailingAnchor),
                placeholderView.topAnchor.constraint(equalTo: slotView.topAnchor),
                placeholderView.bottomAnchor.constraint(equalTo: slotView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: slotView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: slotView.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: slotView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: slotView.bottomAnchor),
            ])
            return slotView
        }

        if preservedImages.count == imageSpreadViews.count {
            for (imageView, image) in zip(imageSpreadViews, preservedImages) {
                imageView.image = image
            }
        }
        if preservedImages.count == imageSpreadViews.count,
           preservedImageVerification.count == imageSpreadViews.count {
            imageSpreadVerifiedImages = zip(preservedImages, preservedImageVerification).map { image, isVerified in
                image != nil && isVerified
            }
        } else {
            imageSpreadVerifiedImages = Array(repeating: false, count: imageCount)
        }
        if preservedImages.count == imageSpreadViews.count,
           preservedImageResolution.count == imageSpreadViews.count {
            imageSpreadResolvedImages = zip(preservedImages, preservedImageResolution).map { image, isResolved in
                image != nil && isResolved
            }
        } else {
            imageSpreadResolvedImages = Array(repeating: false, count: imageCount)
        }
        configureImageSpreadPlaceholders(
            seedImages: preservedImages.count == imageCount
                ? preservedImages
                : Array(repeating: nil, count: imageCount)
        )

        let stackView: UIStackView
        switch arrangement {
        case .linear:
            stackView = makeImageSpreadStackView(arrangedSubviews: populatedSlotViews, axis: .horizontal)
        case .grid(let grid):
            let slotCount = grid.columnCount * grid.rowCount
            let emptySlotViews = (imageSpreadViews.count..<slotCount).map { _ -> UIView in
                let emptySlotView = UIView()
                emptySlotView.backgroundColor = .clear
                emptySlotView.isUserInteractionEnabled = false
                return emptySlotView
            }
            let slotViews = populatedSlotViews + emptySlotViews
            let rowStackViews = (0..<grid.rowCount).map { row -> UIStackView in
                let startIndex = row * grid.columnCount
                let endIndex = startIndex + grid.columnCount
                return makeImageSpreadStackView(
                    arrangedSubviews: Array(slotViews[startIndex..<endIndex]),
                    axis: .horizontal,
                    spacing: grid.spacing
                )
            }
            imageSpreadNestedStackViews = rowStackViews
            stackView = makeImageSpreadStackView(
                arrangedSubviews: rowStackViews,
                axis: .vertical,
                spacing: grid.spacing
            )
        }

        stackView.isUserInteractionEnabled = false
        stackView.isHidden = isHidden
        stackView.translatesAutoresizingMaskIntoConstraints = false
        if usesTransparentPlayerBackground {
            stackView.makeBackgroundTransparent()
            imageSpreadNestedStackViews.forEach { $0.makeBackgroundTransparent() }
        }

        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        imageSpreadStackView = stackView
        imageSpreadArrangement = arrangement
        configureImageSpreadCornerMasks()
    }

    private func configureImageSpreadCornerMasks() {
        for (index, imageView) in imageSpreadViews.enumerated() {
            guard let imageView = imageView as? NativeMetalCardCornerMaskedImageView else { continue }

            imageView.usesNativeMetalCardCornerMask = imageSpreadNativeMetalCardCornerMaskIndices.contains(index)
        }
    }

    private func configureImageSpreadPlaceholders(seedImages: [UIImage?]) {
        for (index, placeholderView) in imageSpreadPlaceholderViews.enumerated() {
            guard imageSpreadPlaceholderSpecs.indices.contains(index) else {
                placeholderView.setHidden(true, animated: false)
                continue
            }

            placeholderView.configure(with: imageSpreadPlaceholderSpecs[index])
            placeholderView.setHidden(seedImages.indices.contains(index) && seedImages[index] != nil, animated: false)
        }
    }

    private func hideImageSpreadPlaceholder(at index: Int, animated: Bool) {
        guard imageSpreadPlaceholderViews.indices.contains(index) else { return }
        imageSpreadPlaceholderViews[index].setHidden(true, animated: animated)
    }

    private func makeImageSpreadStackView(
        arrangedSubviews: [UIView],
        axis: NSLayoutConstraint.Axis,
        spacing: CGFloat = MobilePlayerPageLayoutMetrics.spreadCardSpacing
    ) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.axis = axis
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = spacing
        stackView.isUserInteractionEnabled = false
        return stackView
    }

    private func ensureWebView() {
        guard webView == nil else { return }

        webView = FullscreenTokenMediaView.webView(in: containerView)
        if usesTransparentPlayerBackground {
            webView.makePlayerBackgroundTransparent()
        }
    }

    private func ensureNativeMetalCardView() {
        guard nativeMetalCardView == nil else { return }

        nativeMetalCardView = FullscreenTokenMediaView.nativeMetalCardView(in: containerView)
        if usesTransparentPlayerBackground {
            nativeMetalCardView.makeBackgroundTransparent()
        }
    }

    private func hideWebContent() {
        invalidateLocalWebContentLoad()
        webView?.isHidden = true
    }

    private func hideNativeMetalCardView() {
        nativeMetalCardView?.stop()
        nativeMetalCardView?.isHidden = true
    }

    private func unloadWebContentAfterImageDisplay(imageKey: AnyHashable) {
        invalidateLocalWebContentLoad()
        guard webViewMayContainContent else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.representedImageKey == imageKey else {
                return
            }

            self.unloadWebContentIfNeeded()
        }
    }

    private func hideImageSpread() {
        rememberCurrentImageSpread()
        clearImageSpread()
    }

    private func isImageSpreadImageVerified(at index: Int) -> Bool {
        guard imageSpreadVerifiedImages.indices.contains(index) else { return false }
        return imageSpreadVerifiedImages[index]
    }

    private func clearImageSpread() {
        imageSpreadStackView?.isHidden = true
        imageSpreadViews.forEach {
            $0.layer.removeAllAnimations()
            $0.image = nil
        }
        imageSpreadVerifiedImages = Array(repeating: false, count: imageSpreadViews.count)
        imageSpreadResolvedImages = Array(repeating: false, count: imageSpreadViews.count)
        representedImageSpreadSlotKeys = []
    }

    private func unloadWebContentIfNeeded() {
        activeLocalWebReadinessID = nil
        guard webViewMayContainContent else {
            webView?.invalidateRequestedContent()
            return
        }

        webView?.unloadContent()
        webViewMayContainContent = false
    }

}

private enum PlayerEdgeTapSide {
    case left, right

    var navigationDirection: PlaybackNavigationDirection {
        switch self {
        case .left:
            return .back
        case .right:
            return .forward
        }
    }
}

private final class PlayerEdgeTapGestureRecognizer: UIGestureRecognizer {

    var edgeSideProvider: ((CGPoint) -> PlayerEdgeTapSide?)?
    var canBeginEdgeTap: ((PlayerEdgeTapSide) -> Bool)?
    var onEdgePressBegan: ((PlayerEdgeTapSide) -> Void)?
    var onEdgePressMoved: ((PlayerEdgeTapSide) -> Void)?
    var onEdgePressCancelled: ((PlayerEdgeTapSide) -> Void)?
    var onEdgeTapRecognized: ((PlayerEdgeTapSide) -> Void)?

    private var trackedTouch: UITouch?
    private var initialLocation = CGPoint.zero
    private var activeSide: PlayerEdgeTapSide?
    private var didMoveEnoughToCancelHighlight = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil,
              event.allTouches?.count == 1,
              let touch = touches.first,
              let view else {
            cancelOrFailActivePress()
            return
        }

        let location = touch.location(in: view)
        guard let side = edgeSideProvider?(location),
              canBeginEdgeTap?(side) == true else {
            state = .failed
            return
        }

        trackedTouch = touch
        initialLocation = location
        activeSide = side
        didMoveEnoughToCancelHighlight = false
        onEdgePressBegan?(side)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let view, let activeSide else { return }

        let location = trackedTouch.location(in: view)
        guard isTapStillValid(at: location, for: activeSide) else {
            cancelOrFailActivePress()
            return
        }

        if !didMoveEnoughToCancelHighlight,
           hasMovedEnoughToCancelHighlight(at: location) {
            didMoveEnoughToCancelHighlight = true
            onEdgePressMoved?(activeSide)
        }

        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let view, let activeSide else {
            cancelOrFailActivePress()
            return
        }

        let location = trackedTouch.location(in: view)
        guard isTapStillValid(at: location, for: activeSide) else {
            cancelOrFailActivePress()
            return
        }

        onEdgeTapRecognized?(activeSide)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelOrFailActivePress()
    }

    override func reset() {
        trackedTouch = nil
        initialLocation = .zero
        activeSide = nil
        didMoveEnoughToCancelHighlight = false
    }

    private func isTapStillValid(at location: CGPoint, for side: PlayerEdgeTapSide) -> Bool {
        guard edgeSideProvider?(location) == side else { return false }

        let distance = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
        return distance <= MobilePlayerGestureTuning.edgeTapMaximumMovement
    }

    private func hasMovedEnoughToCancelHighlight(at location: CGPoint) -> Bool {
        let distance = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
        return distance > MobilePlayerGestureTuning.edgeTapHighlightMaximumMovement
    }

    private func cancelOrFailActivePress() {
        if let activeSide {
            onEdgePressCancelled?(activeSide)
            state = .cancelled
        } else {
            state = .failed
        }
    }
}

private final class PlayerEdgeTapHighlightView: UIView {

    private let side: PlayerEdgeTapSide

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    init(side: PlayerEdgeTapSide) {
        self.side = side
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        configureGradient()
        gradientLayer.opacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    func setHighlighted(_ isHighlighted: Bool) {
        let currentOpacity = gradientLayer.presentation()?.opacity ?? gradientLayer.opacity
        gradientLayer.removeAnimation(forKey: "edgeTapHighlightOpacity")

        let targetOpacity: Float = isHighlighted ? 1 : 0
        gradientLayer.opacity = targetOpacity

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = currentOpacity
        animation.toValue = targetOpacity
        animation.duration = isHighlighted
            ? MobilePlayerGestureTuning.edgeTapHighlightFadeInDuration
            : MobilePlayerGestureTuning.edgeTapHighlightFadeOutDuration
        animation.timingFunction = isHighlighted
            ? CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            : CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        gradientLayer.add(animation, forKey: "edgeTapHighlightOpacity")
    }

    private func configureGradient() {
        let edgeColor = UIColor.black.withAlphaComponent(0.36).cgColor
        let midColor = UIColor.black.withAlphaComponent(0.18).cgColor
        let featherColor = UIColor.black.withAlphaComponent(0.05).cgColor
        let clearColor = UIColor.black.withAlphaComponent(0).cgColor
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.colors = side == .left
            ? [edgeColor, midColor, featherColor, clearColor]
            : [clearColor, featherColor, midColor, edgeColor]
        gradientLayer.locations = [0, 0.34, 0.72, 1]
    }
}

struct HorizontalPlayerContainerView: UIViewControllerRepresentable {

    private let initialConfig: MobilePlayerConfig
    private let chrome: MobilePlayerChromeController
    private let pageLayout: MobilePlayerPageLayout
    private let pageLayoutChangeID: UUID
    private let pageLayoutTargetPagePosition: PlayerPagePosition?
    private let onPagePositionUpdate: ((PlayerPagePosition) -> Void)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)
    private let onToggleChrome: (() -> Void)
    private let onPageLayoutChangeRequest: ((MobilePlayerPageLayout) -> Void)
    private let onPageLayoutApplied: ((MobilePlayerPageLayoutApplication) -> Void)
    private let onPageLayoutChangeRejected: ((MobilePlayerPageLayoutRejection) -> Void)
    private let onZoomStateChange: ((Bool) -> Void)

    init(
        initialConfig: MobilePlayerConfig,
        chrome: MobilePlayerChromeController,
        pageLayout: MobilePlayerPageLayout,
        pageLayoutChangeID: UUID,
        pageLayoutTargetPagePosition: PlayerPagePosition?,
        onPagePositionUpdate: @escaping (PlayerPagePosition) -> Void,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void,
        onToggleChrome: @escaping () -> Void,
        onPageLayoutChangeRequest: @escaping (MobilePlayerPageLayout) -> Void,
        onPageLayoutApplied: @escaping (MobilePlayerPageLayoutApplication) -> Void,
        onPageLayoutChangeRejected: @escaping (MobilePlayerPageLayoutRejection) -> Void,
        onZoomStateChange: @escaping (Bool) -> Void
    ) {
        self.initialConfig = initialConfig
        self.chrome = chrome
        self.pageLayout = pageLayout
        self.pageLayoutChangeID = pageLayoutChangeID
        self.pageLayoutTargetPagePosition = pageLayoutTargetPagePosition
        self.onPagePositionUpdate = onPagePositionUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
        self.onToggleChrome = onToggleChrome
        self.onPageLayoutChangeRequest = onPageLayoutChangeRequest
        self.onPageLayoutApplied = onPageLayoutApplied
        self.onPageLayoutChangeRejected = onPageLayoutChangeRejected
        self.onZoomStateChange = onZoomStateChange
    }

    func makeUIViewController(context: Context) -> HorizontalPlayerContainer {
        return HorizontalPlayerContainer(
            initialConfig: initialConfig,
            chrome: chrome,
            pageLayout: pageLayout,
            onPagePositionUpdate: onPagePositionUpdate,
            onPaginationAttempt: onPaginationAttempt,
            onUnavailableNavigation: onUnavailableNavigation,
            onToggleChrome: onToggleChrome,
            onPageLayoutChangeRequest: onPageLayoutChangeRequest,
            onZoomStateChange: onZoomStateChange
        )
    }

    func updateUIViewController(_ uiViewController: HorizontalPlayerContainer, context: Context) {
        uiViewController.setPageLayout(
            pageLayout,
            targetPagePosition: pageLayoutTargetPagePosition
        ) { result in
            switch result {
            case .applied:
                let application = MobilePlayerPageLayoutApplication(
                    pageLayoutChangeID: pageLayoutChangeID,
                    requestedPageLayout: pageLayout,
                    targetPagePosition: pageLayoutTargetPagePosition
                )
                DispatchQueue.main.async {
                    self.onPageLayoutApplied(application)
                }
            case .unchanged:
                break

            case .rejected(let currentPageLayout):
                let rejection = MobilePlayerPageLayoutRejection(
                    pageLayoutChangeID: pageLayoutChangeID,
                    requestedPageLayout: pageLayout,
                    targetPagePosition: pageLayoutTargetPagePosition,
                    currentPageLayout: currentPageLayout
                )
                DispatchQueue.main.async {
                    self.onPageLayoutChangeRejected(rejection)
                }
            }
        }
    }
}

fileprivate enum HorizontalPlayerPageLayoutApplicationResult {
    case applied
    case unchanged
    case rejected(currentPageLayout: MobilePlayerPageLayout)
}

class HorizontalPlayerContainer: UIViewController, HorizontalPlayerDataSource, MobilePlaybackControllerDisplay, UIGestureRecognizerDelegate, MobilePlayerStaticImageGridSelectionProviding {

    private let initialConfig: MobilePlayerConfig
    private let chrome: MobilePlayerChromeController
    private var pageLayout: MobilePlayerPageLayout
    private let onPagePositionUpdate: ((PlayerPagePosition) -> Void)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)
    private let onToggleChrome: (() -> Void)
    private let onPageLayoutChangeRequest: ((MobilePlayerPageLayout) -> Void)
    private let onZoomStateChange: ((Bool) -> Void)
    private let liveLayoutInteractionStateProviderID = UUID()

    private lazy var pagingVC = HorizontalPageViewController(
        pageLayout: pageLayout,
        playerDataSource: self
    )
    private let leftEdgeTapHighlight = PlayerEdgeTapHighlightView(side: .left)
    private let rightEdgeTapHighlight = PlayerEdgeTapHighlightView(side: .right)
    private lazy var singleTapRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gesture.numberOfTapsRequired = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    private lazy var doubleTapRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    private lazy var edgeTapRecognizer: PlayerEdgeTapGestureRecognizer = {
        let gesture = PlayerEdgeTapGestureRecognizer()
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        gesture.edgeSideProvider = { [weak self] location in
            self?.edgeTapSide(at: location)
        }
        gesture.canBeginEdgeTap = { [weak self] side in
            self?.canRecognizeEdgeTap(on: side) == true
        }
        gesture.onEdgePressBegan = { [weak self] side in
            self?.beginEdgeTapHighlight(on: side)
        }
        gesture.onEdgePressMoved = { [weak self] side in
            self?.endEdgeTapHighlight(on: side)
        }
        gesture.onEdgePressCancelled = { [weak self] side in
            self?.endEdgeTapHighlight(on: side)
        }
        gesture.onEdgeTapRecognized = { [weak self] side in
            self?.handleEdgeTap(on: side)
        }
        return gesture
    }()
    private var renderedPagePositionCounts = [PlayerPagePosition: Int]()
    private var displayedPagePosition: PlayerPagePosition?
    private var pendingEdgeTapHighlightSide: PlayerEdgeTapSide?
    private var edgeTapHighlightWorkItem: DispatchWorkItem?
    private var edgeTapHighlightRequestId = 0

    init(
        initialConfig: MobilePlayerConfig,
        chrome: MobilePlayerChromeController,
        pageLayout: MobilePlayerPageLayout,
        onPagePositionUpdate: @escaping (PlayerPagePosition) -> Void,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void,
        onToggleChrome: @escaping () -> Void,
        onPageLayoutChangeRequest: @escaping (MobilePlayerPageLayout) -> Void,
        onZoomStateChange: @escaping (Bool) -> Void
    ) {
        self.initialConfig = initialConfig
        self.chrome = chrome
        self.pageLayout = pageLayout
        self.onPagePositionUpdate = onPagePositionUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
        self.onToggleChrome = onToggleChrome
        self.onPageLayoutChangeRequest = onPageLayoutChangeRequest
        self.onZoomStateChange = onZoomStateChange
        super.init(nibName: nil, bundle: nil)
        chrome.setStaticImageGridSelectionProvider(self)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NativeMetalCardView.resetMotionCalibration()
        MobilePlaybackController.shared.subscribe(config: initialConfig, display: self)
        chrome.setLiveLayoutInteractionStateProvider(id: liveLayoutInteractionStateProviderID) { [weak self] in
            self?.currentLayoutInteractionState() ?? .empty
        }
        makePlayerBackgroundTransparent()
        pagingVC.onCurrentZoomStateChange = { [weak self] isZoomed in
            self?.onZoomStateChange(isZoomed)
        }
        addChild(pagingVC)
        view.addSubview(pagingVC.view)
        pagingVC.didMove(toParent: self)
        pagingVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pagingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pagingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pagingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        installEdgeTapHighlights()
        installTapGestures()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func makePlayerBackgroundTransparent() {
        view.makeBackgroundTransparent()
        pagingVC.makePlayerBackgroundTransparent()
    }

    deinit {
        chrome.clearLiveLayoutInteractionStateProvider(id: liveLayoutInteractionStateProviderID)
        chrome.clearStaticImageGridSelectionProvider(self)
        edgeTapHighlightWorkItem?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func getCurrentPagePosition() -> PlayerPagePosition {
        return pagingVC.getCurrentPagePosition()
    }

    func getCurrentPageLayout() -> MobilePlayerPageLayout {
        return pageLayout
    }

    private func currentLayoutInteractionState() -> MobilePlayerLayoutInteractionState {
        MobilePlaybackController.shared.layoutInteractionState(
            uuid: initialConfig.id,
            pageLayout: pageLayout,
            pagePosition: pagingVC.getCurrentPagePosition()
        )
    }

    func navigate(_ direction: PlaybackNavigationDirection) {
        pagingVC.navigate(direction)
    }

    fileprivate func setPageLayout(
        _ pageLayout: MobilePlayerPageLayout,
        targetPagePosition: PlayerPagePosition? = nil,
        completion: @escaping (HorizontalPlayerPageLayoutApplicationResult) -> Void
    ) {
        let shouldApplyTargetPagePosition = targetPagePosition.map {
            self.pageLayout != pageLayout || pagingVC.getCurrentPagePosition() != $0
        } ?? false
        guard shouldApplyTargetPagePosition || self.pageLayout != pageLayout else {
            completion(.unchanged)
            return
        }

        let previousPageLayout = self.pageLayout
        self.pageLayout = pageLayout
        if !allowsEdgeTapNavigation {
            clearEdgeTapHighlights()
        }
        let didSetPageLayout: Bool
        let completeApplied = {
            completion(.applied)
        }
        if shouldApplyTargetPagePosition, let targetPagePosition {
            didSetPageLayout = pagingVC.setPageLayout(
                pageLayout,
                targetPagePosition: targetPagePosition,
                completion: completeApplied
            )
        } else {
            didSetPageLayout = pagingVC.setPageLayout(
                pageLayout,
                completion: completeApplied
            )
        }
        guard didSetPageLayout else {
            self.pageLayout = previousPageLayout
            completion(.rejected(currentPageLayout: previousPageLayout))
            return
        }
    }

    private var allowsEdgeTapNavigation: Bool {
        pageLayout == .onePerPage
    }

    private func installTapGestures() {
        view.addGestureRecognizer(edgeTapRecognizer)
        view.addGestureRecognizer(singleTapRecognizer)
        view.addGestureRecognizer(doubleTapRecognizer)
    }

    private func installEdgeTapHighlights() {
        [leftEdgeTapHighlight, rightEdgeTapHighlight].forEach { highlightView in
            highlightView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(highlightView)
        }

        NSLayoutConstraint.activate([
            leftEdgeTapHighlight.topAnchor.constraint(equalTo: view.topAnchor),
            leftEdgeTapHighlight.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftEdgeTapHighlight.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftEdgeTapHighlight.widthAnchor.constraint(equalToConstant: MobilePlayerGestureTuning.edgeTapHighlightWidth),

            rightEdgeTapHighlight.topAnchor.constraint(equalTo: view.topAnchor),
            rightEdgeTapHighlight.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rightEdgeTapHighlight.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightEdgeTapHighlight.widthAnchor.constraint(equalToConstant: MobilePlayerGestureTuning.edgeTapHighlightWidth)
        ])
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        if isEdgeTapLocation(gesture.location(in: view)) {
            return
        }

        if selectStaticImageGridCard(at: gesture.location(in: view)) {
            return
        }

        onToggleChrome()
    }

    private func selectStaticImageGridCard(at location: CGPoint) -> Bool {
        guard pageLayout.isStaticImageGrid,
              let selection = staticImageGridSelection(
                at: location,
                in: view,
                requiresLoadedImage: false
              ) else {
            return false
        }

        switch chrome.requestStaticImageGridExpand(selection) {
        case .started:
            Haptic.selectionChanged()
            return true
        case .busy:
            return true
        case .fallbackToImmediateOpen:
            break
        case .rejected:
            return true
        }

        guard pagingVC.openStaticImageGridSelection(selection) else {
            return false
        }
        pageLayout = .onePerPage
        onPageLayoutChangeRequest(.onePerPage)
        Haptic.selectionChanged()
        return true
    }

    func canSelectStaticImageGrid(at location: CGPoint, in coordinateView: UIView) -> Bool {
        guard pageLayout.isStaticImageGrid else {
            return false
        }

        return pagingVC.canSelectStaticImageGrid(at: location, in: coordinateView)
    }

    func staticImageGridSelection(
        at location: CGPoint,
        in coordinateView: UIView
    ) -> MobilePlayerStaticImageGridSelection? {
        guard pageLayout.isStaticImageGrid else {
            return nil
        }

        return staticImageGridSelection(
            at: location,
            in: coordinateView,
            requiresLoadedImage: true
        )
    }

    private func staticImageGridSelection(
        at location: CGPoint,
        in coordinateView: UIView,
        requiresLoadedImage: Bool
    ) -> MobilePlayerStaticImageGridSelection? {
        guard pageLayout.isStaticImageGrid else {
            return nil
        }

        return pagingVC.staticImageGridSelection(
            at: location,
            in: coordinateView,
            requiresLoadedImage: requiresLoadedImage
        )
    }

    private func edgeTapSide(at location: CGPoint) -> PlayerEdgeTapSide? {
        guard allowsEdgeTapNavigation else { return nil }

        let edgeWidth = min(MobilePlayerGestureTuning.edgeTapNavigationWidth, view.bounds.width / 2)
        if location.x <= edgeWidth {
            return .left
        }
        if location.x >= view.bounds.width - edgeWidth {
            return .right
        }
        return nil
    }

    private func isEdgeTapLocation(_ location: CGPoint) -> Bool {
        edgeTapSide(at: location) != nil
    }

    private func canRecognizeEdgeTap(on side: PlayerEdgeTapSide) -> Bool {
        guard allowsEdgeTapNavigation else { return false }

        let direction = side.navigationDirection
        return pagingVC.canNavigateWithoutAnimation(direction)
            || !pagingVC.hasNavigationDestination(direction)
    }

    private func beginEdgeTapHighlight(on side: PlayerEdgeTapSide) {
        cancelPendingEdgeTapHighlight()
        edgeTapHighlight(for: oppositeSide(of: side)).setHighlighted(false)
        edgeTapHighlight(for: side).setHighlighted(false)

        guard pagingVC.canNavigateWithoutAnimation(side.navigationDirection) else { return }

        pendingEdgeTapHighlightSide = side
        edgeTapHighlightRequestId += 1
        let requestId = edgeTapHighlightRequestId
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.edgeTapHighlightRequestId == requestId,
                  self.pendingEdgeTapHighlightSide == side else {
                return
            }

            self.pendingEdgeTapHighlightSide = nil
            self.edgeTapHighlightWorkItem = nil
            self.edgeTapHighlight(for: side).setHighlighted(true)
        }
        edgeTapHighlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MobilePlayerGestureTuning.edgeTapHighlightActivationDelay,
            execute: workItem
        )
    }

    private func endEdgeTapHighlight(on side: PlayerEdgeTapSide) {
        cancelPendingEdgeTapHighlight()
        edgeTapHighlightRequestId += 1
        edgeTapHighlight(for: side).setHighlighted(false)
    }

    private func handleEdgeTap(on side: PlayerEdgeTapSide) {
        guard allowsEdgeTapNavigation else {
            clearEdgeTapHighlights()
            return
        }

        let direction = side.navigationDirection
        guard pagingVC.canNavigateWithoutAnimation(direction) else {
            endEdgeTapHighlight(on: side)
            if !pagingVC.hasNavigationDestination(direction) {
                onUnavailableNavigation()
            }
            return
        }

        if cancelPendingEdgeTapHighlight(on: side) {
            flashEdgeTapHighlight(on: side)
        } else {
            endEdgeTapHighlight(on: side)
        }
        guard pagingVC.navigateWithoutAnimation(direction) else { return }

        Haptic.selectionChanged()
    }

    @discardableResult
    private func cancelPendingEdgeTapHighlight(on side: PlayerEdgeTapSide? = nil) -> Bool {
        guard let pendingSide = pendingEdgeTapHighlightSide else {
            return false
        }
        if let side, pendingSide != side {
            return false
        }

        edgeTapHighlightWorkItem?.cancel()
        edgeTapHighlightWorkItem = nil
        pendingEdgeTapHighlightSide = nil
        edgeTapHighlightRequestId += 1
        return true
    }

    private func clearEdgeTapHighlights() {
        edgeTapHighlightWorkItem?.cancel()
        edgeTapHighlightWorkItem = nil
        pendingEdgeTapHighlightSide = nil
        edgeTapHighlightRequestId += 1
        leftEdgeTapHighlight.setHighlighted(false)
        rightEdgeTapHighlight.setHighlighted(false)
    }

    private func flashEdgeTapHighlight(on side: PlayerEdgeTapSide) {
        edgeTapHighlight(for: oppositeSide(of: side)).setHighlighted(false)
        edgeTapHighlight(for: side).setHighlighted(true)
        edgeTapHighlightRequestId += 1
        let requestId = edgeTapHighlightRequestId

        DispatchQueue.main.asyncAfter(
            deadline: .now() + MobilePlayerGestureTuning.edgeTapHighlightTapFlashDuration
        ) { [weak self] in
            guard let self, self.edgeTapHighlightRequestId == requestId else { return }

            self.edgeTapHighlight(for: side).setHighlighted(false)
        }
    }

    private func oppositeSide(of side: PlayerEdgeTapSide) -> PlayerEdgeTapSide {
        switch side {
        case .left:
            return .right
        case .right:
            return .left
        }
    }

    private func edgeTapHighlight(for side: PlayerEdgeTapSide) -> PlayerEdgeTapHighlightView {
        switch side {
        case .left:
            return leftEdgeTapHighlight
        case .right:
            return rightEdgeTapHighlight
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard !pageLayout.isStaticImageGrid else { return }

        let location = gesture.location(in: view)
        guard !isEdgeTapLocation(location) else { return }

        pagingVC.toggleZoom(at: location, in: view)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === doubleTapRecognizer else { return true }
        guard !pageLayout.isStaticImageGrid else { return false }

        return !isEdgeTapLocation(gestureRecognizer.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === doubleTapRecognizer, pageLayout.isStaticImageGrid {
            return false
        }

        guard gestureRecognizer === singleTapRecognizer || gestureRecognizer === doubleTapRecognizer else {
            return true
        }

        return !isEdgeTapLocation(touch.location(in: view))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === singleTapRecognizer
            && otherGestureRecognizer === doubleTapRecognizer
            && !pageLayout.isStaticImageGrid
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === edgeTapRecognizer || otherGestureRecognizer === edgeTapRecognizer
    }

    fileprivate func getToken(pagePosition: PlayerPagePosition) -> GeneratedToken {
        MobilePlaybackController.shared.getToken(uuid: initialConfig.id, pagePosition: pagePosition)
    }

    fileprivate func prepareDownloadableMediaWindow(
        for pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection,
        pageLayout: MobilePlayerPageLayout? = nil
    ) -> PlayerDownloadableMediaWindow? {
        MobilePlaybackController.shared.prepareDownloadableMediaWindow(
            uuid: initialConfig.id,
            pagePosition: pagePosition,
            direction: direction,
            pageLayout: pageLayout ?? self.pageLayout
        )
    }

    fileprivate func prepareStaticImageGridMediaWindow(
        for pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        MobilePlaybackController.shared.prepareStaticImageGridMediaWindow(
            uuid: initialConfig.id,
            pagePosition: pagePosition,
            pageLayout: pageLayout,
            direction: direction
        )
    }

    fileprivate func clearDownloadableMediaWindow() {
        MobilePlaybackController.shared.clearDownloadableMediaWindow(uuid: initialConfig.id)
    }

    fileprivate func downloadableMediaDescriptor(for pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor? {
        MobilePlaybackController.shared.downloadableMediaDescriptor(
            uuid: initialConfig.id,
            pagePosition: pagePosition
        )
    }

    fileprivate func staticImageGridMediaDescriptor(for pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor? {
        MobilePlaybackController.shared.staticImageGridMediaDescriptor(
            uuid: initialConfig.id,
            pagePosition: pagePosition
        )
    }

    fileprivate func staticImageGridDescriptors(
        containing pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> [DownloadableMediaDescriptor] {
        MobilePlaybackController.shared.staticImageGridDescriptors(
            uuid: initialConfig.id,
            containing: pagePosition,
            pageLayout: pageLayout
        )
    }

    fileprivate func supportsPageLayout(_ pageLayout: MobilePlayerPageLayout, for pagePosition: PlayerPagePosition) -> Bool {
        MobilePlaybackController.shared.supportsPageLayout(
            pageLayout,
            uuid: initialConfig.id,
            pagePosition: pagePosition
        )
    }

    fileprivate func canRenderPagePosition(_ pagePosition: PlayerPagePosition) -> Bool {
        MobilePlaybackController.shared.canRender(
            uuid: initialConfig.id,
            pagePosition: pagePosition
        )
    }

    fileprivate func startPagePosition() -> PlayerPagePosition {
        MobilePlaybackController.shared.startPagePosition(uuid: initialConfig.id)
    }

    fileprivate func stablePagePosition(
        containing pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> PlayerPagePosition {
        MobilePlaybackController.shared.stablePagePosition(
            uuid: initialConfig.id,
            containing: pagePosition,
            pageLayout: pageLayout
        )
    }

    fileprivate func exitWidgetInsertionForStablePage(
        containing pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> PlayerStablePagePositionResolution {
        MobilePlaybackController.shared.exitWidgetInsertionForStablePage(
            uuid: initialConfig.id,
            containing: pagePosition,
            pageLayout: pageLayout
        )
    }

    fileprivate func navigationStride(
        from pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> Int {
        MobilePlaybackController.shared.navigationStride(
            uuid: initialConfig.id,
            from: pagePosition,
            pageLayout: pageLayout
        )
    }

    fileprivate func didRenderPagePosition(_ pagePosition: PlayerPagePosition) {
        renderedPagePositionCounts[pagePosition, default: 0] += 1
        didUpdateRenderedPagePositions()
    }

    fileprivate func didCleanupPagePosition(_ pagePosition: PlayerPagePosition) {
        if let count = renderedPagePositionCounts[pagePosition], count > 1 {
            renderedPagePositionCounts[pagePosition] = count - 1
        } else {
            renderedPagePositionCounts.removeValue(forKey: pagePosition)
        }
        didUpdateRenderedPagePositions()
    }

    fileprivate func didAttemptUnavailableHorizontalNavigation() {
        onUnavailableNavigation()
    }

    fileprivate func didAttemptPagination() {
        onPaginationAttempt()
    }

    fileprivate func didDisplayPagePosition(_ pagePosition: PlayerPagePosition, forceUpdate: Bool) {
        updateDisplayedPagePosition(pagePosition, forceUpdate: forceUpdate)
    }

    private func didUpdateRenderedPagePositions() {
        if renderedPagePositionCounts.count == 1, let pagePosition = renderedPagePositionCounts.keys.first {
            updateDisplayedPagePosition(pagePosition, forceUpdate: false)
        }
    }

    private func updateDisplayedPagePosition(_ pagePosition: PlayerPagePosition, forceUpdate: Bool) {
        guard forceUpdate || displayedPagePosition != pagePosition else { return }
        displayedPagePosition = pagePosition
        onPagePositionUpdate(pagePosition)
    }

}

private protocol HorizontalPlayerDataSource: AnyObject {

    func getToken(pagePosition: PlayerPagePosition) -> GeneratedToken
    func prepareDownloadableMediaWindow(
        for pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection,
        pageLayout: MobilePlayerPageLayout?
    ) -> PlayerDownloadableMediaWindow?
    func prepareStaticImageGridMediaWindow(
        for pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow?
    func clearDownloadableMediaWindow()
    func downloadableMediaDescriptor(for pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor?
    func staticImageGridMediaDescriptor(for pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor?
    func staticImageGridDescriptors(
        containing pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> [DownloadableMediaDescriptor]
    func supportsPageLayout(_ pageLayout: MobilePlayerPageLayout, for pagePosition: PlayerPagePosition) -> Bool
    func canRenderPagePosition(_ pagePosition: PlayerPagePosition) -> Bool
    func startPagePosition() -> PlayerPagePosition
    func stablePagePosition(
        containing pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> PlayerPagePosition
    func exitWidgetInsertionForStablePage(
        containing pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> PlayerStablePagePositionResolution
    func navigationStride(
        from pagePosition: PlayerPagePosition,
        for pageLayout: MobilePlayerPageLayout
    ) -> Int
    func didRenderPagePosition(_ pagePosition: PlayerPagePosition)
    func didCleanupPagePosition(_ pagePosition: PlayerPagePosition)
    func didAttemptPagination()
    func didAttemptUnavailableHorizontalNavigation()
    func didDisplayPagePosition(_ pagePosition: PlayerPagePosition, forceUpdate: Bool)

}

private extension HorizontalPlayerDataSource {

    func prepareDownloadableMediaWindow(
        for pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        prepareDownloadableMediaWindow(
            for: pagePosition,
            direction: direction,
            pageLayout: nil
        )
    }
}

private final class PlayerZoomScrollView: UIScrollView {

    private var pagingPanGestureRecognizerIds = Set<ObjectIdentifier>()
    var pagingContentOffsetXRange: ClosedRange<CGFloat>?

    func registerPagingPanGesture(_ panGesture: UIPanGestureRecognizer) {
        pagingPanGestureRecognizerIds.insert(ObjectIdentifier(panGesture))
    }

    func allowsPagingPanFromCurrentZoomEdge(_ panGesture: UIPanGestureRecognizer) -> Bool {
        guard zoomScale > minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance else { return false }

        let velocity = panGesture.velocity(in: self)
        let isHorizontalPan = abs(velocity.x) > abs(velocity.y) * MobilePlayerGestureTuning.pageBoundaryRevealHorizontalIntentRatio
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
        guard zoomScale > minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance else { return false }

        return gestureRecognizer === panGestureRecognizer && isPagingPanGesture(otherGestureRecognizer)
            || otherGestureRecognizer === panGestureRecognizer && isPagingPanGesture(gestureRecognizer)
    }

    private func isPagingPanGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }

        return pagingPanGestureRecognizerIds.contains(ObjectIdentifier(panGesture))
    }

    private var isAtLeftContentEdge: Bool {
        contentOffset.x <= minimumContentOffsetX + MobilePlayerGestureTuning.playerZoomEdgePaginationTolerance
    }

    private var isAtRightContentEdge: Bool {
        contentOffset.x >= maximumContentOffsetX - MobilePlayerGestureTuning.playerZoomEdgePaginationTolerance
    }

    private var minimumContentOffsetX: CGFloat {
        if let pagingContentOffsetXRange {
            return pagingContentOffsetXRange.lowerBound
        }

        return -adjustedContentInset.left
    }

    private var maximumContentOffsetX: CGFloat {
        if let pagingContentOffsetXRange {
            return pagingContentOffsetXRange.upperBound
        }

        return max(minimumContentOffsetX, contentSize.width - bounds.width + adjustedContentInset.right)
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

private struct PlayerStaticImageIdentity: Hashable {
    let collectionId: String
    let tokenId: String
    let tokenIndex: Int

    init(_ descriptor: DownloadableMediaDescriptor) {
        collectionId = descriptor.collectionId
        tokenId = descriptor.tokenId
        tokenIndex = descriptor.tokenIndex
    }
}

private struct PlayerProvisionalStaticImage {
    let identity: PlayerStaticImageIdentity
    let image: UIImage
}

private class SpecificPageViewController: UIViewController, UIScrollViewDelegate {

    private static let maximumCachedVideoSizeCount = 24

    private struct AnimatedRenderContext: Equatable {
        let descriptor: DownloadableMediaDescriptor
        let adjacentDescriptor: DownloadableMediaDescriptor?
        let fallbackHTML: String
        let mediaKind: DownloadableWebMediaKind
    }

    private struct LocalMediaFileVersion: Equatable, Hashable {
        let descriptor: DownloadableMediaDescriptor
        let fileURL: URL
        let fileSize: Int?
        let contentModificationDate: Date?

        init(fileURL: URL, descriptor: DownloadableMediaDescriptor) {
            let resourceValues = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            self.descriptor = descriptor
            self.fileURL = fileURL
            self.fileSize = resourceValues?.fileSize
            self.contentModificationDate = resourceValues?.contentModificationDate
        }
    }

    private typealias VideoSizeRequest = LocalMediaFileVersion

    private struct VideoSizeLoad {
        let request: VideoSizeRequest
        let task: Task<Void, Never>
    }

    private typealias StaticImageSpreadZoomLayout = MobileStaticImageSpreadLayout

    private struct StaticImageSpreadRenderKey: Hashable {
        let descriptors: [DownloadableMediaDescriptor]
    }

    private struct StaticImageSpreadSelection {
        let index: Int
        let pagePosition: PlayerPagePosition
    }

    private final class StaticImageSpreadRenderState {
        let renderGeneration: UInt64?
        let pagePosition: PlayerPagePosition
        let pageLayout: MobilePlayerPageLayout
        let descriptors: [DownloadableMediaDescriptor]
        let renderKey: StaticImageSpreadRenderKey
        var failedIndices = IndexSet()
        var recoveryAttemptIDs = [Int: UUID]()
        var recoveryCancellations = [Int: () -> Void]()
        var cacheObserver: NSObjectProtocol?

        init(
            renderGeneration: UInt64?,
            pagePosition: PlayerPagePosition,
            pageLayout: MobilePlayerPageLayout,
            descriptors: [DownloadableMediaDescriptor]
        ) {
            self.renderGeneration = renderGeneration
            self.pagePosition = pagePosition
            self.pageLayout = pageLayout
            self.descriptors = descriptors
            self.renderKey = StaticImageSpreadRenderKey(descriptors: descriptors)
        }

        func selection(at index: Int) -> StaticImageSpreadSelection? {
            guard descriptors.indices.contains(index) else {
                return nil
            }

            return StaticImageSpreadSelection(
                index: index,
                pagePosition: pagePosition.advanced(by: index)
            )
        }
    }

    private enum ZoomContentLayout: Equatable {
        case viewport
        case staticImage(CGSize)
        case staticImageSpread(StaticImageSpreadZoomLayout)
    }

    private enum ZoomAllowedContent: Equatable {
        case fullContent
        case nativeMetalCard

        func rect(in contentBounds: CGRect) -> CGRect {
            switch self {
            case .fullContent:
                return contentBounds
            case .nativeMetalCard:
                return NativeMetalCardLayout.cardContentRect(in: contentBounds.size)
            }
        }
    }

    private weak var playerDataSource: HorizontalPlayerDataSource?
    private let zoomScrollView = PlayerZoomScrollView()
    private let mediaContentView = UIView()
    private let htmlDocumentRenderQueue = DispatchQueue(
        label: "org.lil.nft-player.html-document-render",
        qos: .userInitiated
    )
    private lazy var mediaRenderer = FullscreenTokenMediaRenderer(containerView: mediaContentView)

    private(set) var pagePosition: PlayerPagePosition

    private var renderedPagePosition: PlayerPagePosition?
    private var renderGeneration: UInt64 = 0
    private var activeRenderGeneration: UInt64?
    private var animatedRenderContext: AnimatedRenderContext?
    private var pendingAnimatedImageURL: URL?
    private var renderedAnimatedImageURL: URL?
    private var renderedAnimatedNextImageURL: URL?
    private var pendingAnimatedNextImageURL: URL?
    private var failedAnimatedLocalContentVersion: LocalMediaFileVersion?
    private var provisionalAnimatedMediaImage: UIImage?
    private var cancelProvisionalAnimatedMediaImageLoad: (() -> Void)?
    private var downloadableMediaCacheObserver: NSObjectProtocol?
    private var videoSizeLoad: VideoSizeLoad?
    private var cachedVideoSizes = [VideoSizeRequest: CGSize]()
    private var cachedVideoSizeRequests = [VideoSizeRequest]()
    private var willOrDidAppear = false
    private var isZoomInteractionActive = false
    private var pageLayout: MobilePlayerPageLayout
    private var needsPageLayoutRender = false
    private var imageSpreadRenderState: StaticImageSpreadRenderState?
    private var pendingProvisionalStaticImage: PlayerProvisionalStaticImage?
    private var zoomContentLayout: ZoomContentLayout = .viewport
    private var zoomAllowedContent: ZoomAllowedContent = .fullContent
    private var laidOutZoomViewportSize: CGSize = .zero
    var onZoomStateChange: (() -> Void)?
    var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    var isZoomed: Bool {
        zoomScrollView.zoomScale > zoomScrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance
    }

    init(
        pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        playerDataSource: HorizontalPlayerDataSource?
    ) {
        self.playerDataSource = playerDataSource
        self.pagePosition = pagePosition
        self.pageLayout = pageLayout
        super.init(nibName: nil, bundle: nil)
        renderCurrentItem()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        cancelVideoSizeLoad()
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        removeDownloadableMediaCacheObserver()
        clearImageSpreadRenderState()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureZoomScrollView()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cleanupDisplayedContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        willOrDidAppear = true
        renderCurrentItem()
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

    private func cleanupDisplayedContent() {
        invalidateRenderGeneration()
        resetZoom(animated: false)
        setZoomContentLayout(.viewport)
        clearAnimatedRenderContext()
        clearImageSpreadRenderState()
        mediaRenderer.clearContent()
        if let renderedPagePosition {
            playerDataSource?.didCleanupPagePosition(renderedPagePosition)
        }
        renderedPagePosition = nil
        needsPageLayoutRender = false
    }

    func update(pagePosition: PlayerPagePosition) {
        guard self.pagePosition != pagePosition else { return }
        cleanupDisplayedContent()
        self.pagePosition = pagePosition
    }

    func setPageLayout(_ pageLayout: MobilePlayerPageLayout, shouldRender: Bool) {
        guard self.pageLayout != pageLayout else { return }

        let previousPageLayout = self.pageLayout
        let wasUsingStaticImageGridLayout = usesStaticImageGridLayoutForCurrentPagePosition
        self.pageLayout = pageLayout
        let isUsingStaticImageGridLayout = usesStaticImageGridLayoutForCurrentPagePosition
        let needsRenderForLayoutChange = wasUsingStaticImageGridLayout != isUsingStaticImageGridLayout
            || (wasUsingStaticImageGridLayout && isUsingStaticImageGridLayout && previousPageLayout != pageLayout)

        if isUsingStaticImageGridLayout {
            resetZoom(animated: false)
        }

        guard shouldRender else {
            if needsRenderForLayoutChange {
                needsPageLayoutRender = renderedPagePosition != nil
            }
            return
        }

        guard needsRenderForLayoutChange else {
            return
        }
        guard willOrDidAppear else { return }

        cleanupDisplayedContent()
        renderCurrentItem()
    }

    fileprivate func provisionalStaticImage(
        for targetPagePosition: PlayerPagePosition,
        pageLayout targetPageLayout: MobilePlayerPageLayout
    ) -> PlayerProvisionalStaticImage? {
        guard renderedPagePosition != nil else { return nil }

        if targetPageLayout.isStaticImageGrid {
            guard !usesStaticImageGridLayoutForCurrentPagePosition,
                  let descriptor = playerDataSource?.downloadableMediaDescriptor(for: pagePosition),
                  let gridDescriptor = playerDataSource?.staticImageGridMediaDescriptor(for: pagePosition),
                  gridDescriptor.isStaticImage,
                  PlayerStaticImageIdentity(gridDescriptor) == PlayerStaticImageIdentity(descriptor),
                  let image = mediaRenderer.displayedImage() else {
                return nil
            }

            return PlayerProvisionalStaticImage(
                identity: PlayerStaticImageIdentity(descriptor),
                image: image
            )
        }

        guard usesStaticImageGridLayoutForCurrentPagePosition,
              let targetDescriptor = playerDataSource?.staticImageGridMediaDescriptor(for: targetPagePosition),
              let renderState = imageSpreadRenderState,
              let images = mediaRenderer.imageSpreadImages(),
              images.count == renderState.descriptors.count else {
            return nil
        }

        let targetIdentity = PlayerStaticImageIdentity(targetDescriptor)
        guard let targetIndex = renderState.descriptors.firstIndex(where: {
            PlayerStaticImageIdentity($0) == targetIdentity
        }),
              let image = images[targetIndex] else {
            return nil
        }

        return PlayerProvisionalStaticImage(identity: targetIdentity, image: image)
    }

    fileprivate func setPendingProvisionalStaticImage(_ provisionalImage: PlayerProvisionalStaticImage?) {
        pendingProvisionalStaticImage = provisionalImage
    }

    private func takePendingProvisionalStaticImage(
        matching descriptor: DownloadableMediaDescriptor
    ) -> UIImage? {
        defer { pendingProvisionalStaticImage = nil }
        guard let pendingProvisionalStaticImage,
              pendingProvisionalStaticImage.identity == PlayerStaticImageIdentity(descriptor) else {
            return nil
        }

        return pendingProvisionalStaticImage.image
    }

    private func takePendingProvisionalStaticImages(
        matching descriptors: [DownloadableMediaDescriptor]
    ) -> [UIImage?] {
        defer { pendingProvisionalStaticImage = nil }
        guard let pendingProvisionalStaticImage else {
            return Array(repeating: nil, count: descriptors.count)
        }

        return descriptors.map { descriptor in
            PlayerStaticImageIdentity(descriptor) == pendingProvisionalStaticImage.identity
                ? pendingProvisionalStaticImage.image
                : nil
        }
    }

    private func discardPendingProvisionalStaticImage() {
        pendingProvisionalStaticImage = nil
    }

    func renderCurrentItemIfNeededForPageLayout() {
        guard needsPageLayoutRender else { return }

        renderCurrentItem()
    }

    private func imageSpreadSelection(
        at location: CGPoint,
        in coordinateView: UIView,
        requiresLoadedImage: Bool = true
    ) -> StaticImageSpreadSelection? {
        guard usesStaticImageGridLayoutForCurrentPagePosition,
              let spreadIndex = mediaRenderer.imageSpreadIndex(
                at: location,
                in: coordinateView,
                requiresVerifiedImage: requiresLoadedImage
              ),
              let spreadSelection = imageSpreadRenderState?.selection(at: spreadIndex) else {
            return nil
        }

        return spreadSelection
    }

    func canSelectStaticImageGrid(at location: CGPoint, in coordinateView: UIView) -> PlayerPagePosition? {
        guard let spreadSelection = imageSpreadSelection(at: location, in: coordinateView) else {
            return nil
        }

        return spreadSelection.pagePosition
    }

    func staticImageGridSelection(at location: CGPoint, in coordinateView: UIView) -> MobilePlayerStaticImageGridSelection? {
        staticImageGridSelection(
            at: location,
            in: coordinateView,
            requiresLoadedImage: true
        )
    }

    func staticImageGridSelection(
        at location: CGPoint,
        in coordinateView: UIView,
        requiresLoadedImage: Bool
    ) -> MobilePlayerStaticImageGridSelection? {
        guard let spreadSelection = imageSpreadSelection(
            at: location,
            in: coordinateView,
            requiresLoadedImage: requiresLoadedImage
        ) else {
            return nil
        }

        guard let renderState = imageSpreadRenderState,
              let images = mediaRenderer.imageSpreadImages() else {
            return nil
        }

        return MobilePlayerStaticImageGridSelection(
            pageLayout: pageLayout,
            pagePosition: spreadSelection.pagePosition,
            selectedSlotIndex: spreadSelection.index,
            descriptors: renderState.descriptors,
            images: images
        )
    }

    func toggleZoom(at location: CGPoint, in coordinateView: UIView) {
        guard isViewLoaded else { return }
        guard !usesStaticImageGridLayoutForCurrentPagePosition else { return }
        guard zoomScrollView.bounds.width > 0, zoomScrollView.bounds.height > 0 else { return }

        if isZoomed {
            resetZoom(animated: true)
            return
        }

        applyCachedCurrentVideoSizeIfAvailable()

        let locationInContent = coordinateView.convert(location, to: mediaContentView)
        let targetScale = min(
            MobilePlayerGestureTuning.playerDoubleTapZoomScale,
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
        let zoomRect = CGRect(
            x: zoomOrigin.x,
            y: zoomOrigin.y,
            width: zoomSize.width,
            height: zoomSize.height
        )

        zoomScrollView.zoom(to: zoomRect, animated: true)
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

    func resetZoom(animated: Bool) {
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

    func registerPagingPanGesture(_ panGesture: UIPanGestureRecognizer) {
        zoomScrollView.registerPagingPanGesture(panGesture)
    }

    func allowsPagingPanFromCurrentZoomEdge(_ panGesture: UIPanGestureRecognizer) -> Bool {
        zoomScrollView.allowsPagingPanFromCurrentZoomEdge(panGesture)
    }

    private func configureZoomScrollView() {
        makePlayerBackgroundTransparent()
        zoomScrollView.delegate = self
        zoomScrollView.minimumZoomScale = 1
        zoomScrollView.maximumZoomScale = MobilePlayerGestureTuning.playerMaximumZoomScale
        zoomScrollView.bounces = true
        zoomScrollView.bouncesZoom = true
        zoomScrollView.showsHorizontalScrollIndicator = false
        zoomScrollView.showsVerticalScrollIndicator = false
        zoomScrollView.contentInsetAdjustmentBehavior = .never
        zoomScrollView.hideAutomaticScrollEdgeEffects()

        zoomScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomScrollView)
        zoomScrollView.addSubview(mediaContentView)

        NSLayoutConstraint.activate([
            zoomScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        updateZoomContentFrame(resetOffset: true)
        updateZoomInteraction()
    }

    fileprivate func makePlayerBackgroundTransparent() {
        guard isViewLoaded else { return }

        applyPlayerBackgroundTransparency()
    }

    private func applyPlayerBackgroundTransparency() {
        view.makeBackgroundTransparent()
        mediaContentView.makeBackgroundTransparent()
        zoomScrollView.makeBackgroundTransparent()
        mediaRenderer.makePlayerBackgroundTransparent()
    }

    private func setZoomContentLayout(
        _ layout: ZoomContentLayout,
        allowedContent: ZoomAllowedContent = .fullContent,
        preservingZoomForEquivalentStaticImageLayout: Bool = false
    ) {
        if preservingZoomForEquivalentStaticImageLayout,
           isZoomed || zoomScrollView.isZooming,
           zoomAllowedContent == allowedContent,
           case .staticImage(let currentImageSize) = zoomContentLayout,
           case .staticImage(let nextImageSize) = layout,
           staticImageLayoutsAreEquivalent(currentImageSize, nextImageSize) {
            zoomContentLayout = layout
            if isZoomed {
                updateZoomContentFrame(resetOffset: false)
            }
            return
        }

        guard zoomContentLayout != layout || zoomAllowedContent != allowedContent else {
            updateZoomContentFrame(resetOffset: false)
            return
        }

        zoomContentLayout = layout
        zoomAllowedContent = allowedContent
        resetZoom(animated: false)
        updateZoomContentFrame(resetOffset: true)
    }

    private func staticImageLayoutsAreEquivalent(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        guard let viewportSize = validViewportSize(zoomScrollView.bounds.size) else { return false }

        let lhsFittedSize = MobilePlayerAspectFitLayout.size(for: lhs, fitting: viewportSize)
        let rhsFittedSize = MobilePlayerAspectFitLayout.size(for: rhs, fitting: viewportSize)
        guard lhsFittedSize.width > 0,
              lhsFittedSize.height > 0,
              rhsFittedSize.width > 0,
              rhsFittedSize.height > 0 else {
            return false
        }

        let magnitude = max(max(viewportSize.width, viewportSize.height), 1)
        let tolerance = magnitude * CGFloat.ulpOfOne * 16
        return abs(lhsFittedSize.width - rhsFittedSize.width) <= tolerance
            && abs(lhsFittedSize.height - rhsFittedSize.height) <= tolerance
    }

    private func updateZoomContentFrame(resetOffset: Bool) {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let contentSize = zoomContentSize(fitting: viewportSize)
        if zoomScrollView.zoomScale <= zoomScrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance {
            mediaContentView.transform = .identity
            mediaContentView.frame = CGRect(origin: .zero, size: contentSize)
            zoomScrollView.contentSize = contentSize
        }

        if case .staticImageSpread(let layout) = zoomContentLayout {
            if let grid = layout.grid(fitting: viewportSize) {
                mediaRenderer.setImageSpreadGrid(grid)
            } else if let axis = layout.axis(fitting: viewportSize) {
                mediaRenderer.setImageSpreadAxis(axis)
            }
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

        case .staticImage(let imageSize):
            guard imageSize.width > 0, imageSize.height > 0 else { return viewportSize }

            return MobilePlayerAspectFitLayout.size(for: imageSize, fitting: viewportSize)

        case .staticImageSpread(let layout):
            return layout.contentSize(fitting: viewportSize)
        }
    }

    private func updateZoomContentInsets() {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let offsetRanges = zoomContentOffsetRanges()
        zoomScrollView.pagingContentOffsetXRange = zoomAllowedContent == .fullContent ? nil : offsetRanges.x
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
        let contentBounds = CGRect(origin: .zero, size: mediaContentView.bounds.size)
        guard contentBounds.width > 0, contentBounds.height > 0 else { return .zero }

        let allowedRect = zoomAllowedContent.rect(in: contentBounds)
        guard !allowedRect.isNull, !allowedRect.isEmpty else { return contentBounds }

        let clippedRect = allowedRect.intersection(contentBounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else { return contentBounds }
        return clippedRect
    }

    private func updateZoomInteraction() {
        let shouldActivateZoomInteraction = isZoomed
        if zoomScrollView.panGestureRecognizer.isEnabled != shouldActivateZoomInteraction {
            zoomScrollView.panGestureRecognizer.isEnabled = shouldActivateZoomInteraction
        }
        guard isZoomInteractionActive != shouldActivateZoomInteraction else { return }

        isZoomInteractionActive = shouldActivateZoomInteraction
        onZoomStateChange?()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        usesStaticImageGridLayoutForCurrentPagePosition ? nil : mediaContentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateZoomContentInsets()
        clampZoomContentOffsetIfNeeded()
        updateZoomInteraction()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= scrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance {
            resetZoom(animated: true)
        } else {
            updateZoomContentInsets()
            clampZoomContentOffsetIfNeeded()
            updateZoomInteraction()
        }
    }

    func renderCurrentItem() {
        guard willOrDidAppear else { return }

        guard playerDataSource?.canRenderPagePosition(pagePosition) == true else {
            discardPendingProvisionalStaticImage()
            cleanupDisplayedContent()
            playerDataSource?.clearDownloadableMediaWindow()
            return
        }
        if let renderedPagePosition,
           renderedPagePosition == pagePosition,
           !needsPageLayoutRender {
            return
        }

        if needsPageLayoutRender {
            cleanupDisplayedContent()
        }
        beginRenderingPagePosition(pagePosition)
        clearImageSpreadRenderState()

        guard let token = playerDataSource?.getToken(pagePosition: pagePosition) else {
            discardPendingProvisionalStaticImage()
            playerDataSource?.clearDownloadableMediaWindow()
            playerDataSource?.didRenderPagePosition(pagePosition)
            return
        }

        let isUsingStaticImageGridLayout = usesStaticImageGridLayoutForCurrentPagePosition
        if isUsingStaticImageGridLayout {
            if let mediaWindow = prepareStaticImageGridMediaWindowIfAvailable(),
               case .staticImage = mediaWindow.currentDescriptor.media {
                let descriptor = mediaWindow.currentDescriptor
                renderImageSpread(
                    descriptor,
                    imageDescriptors: staticImageGridImageDescriptors(startingWith: descriptor)
                )
            } else {
                discardPendingProvisionalStaticImage()
                playerDataSource?.clearDownloadableMediaWindow()
                renderWebContent(token.html)
            }
        } else if let nativeRenderKind = token.nativeMetalCardRenderKind {
            discardPendingProvisionalStaticImage()
            if prepareStaticImageGridMediaWindowIfAvailable() == nil {
                playerDataSource?.clearDownloadableMediaWindow()
            }
            renderNativeMetalCard(token, renderKind: nativeRenderKind)
        } else if token.media == nil {
            discardPendingProvisionalStaticImage()
            if prepareStaticImageGridMediaWindowIfAvailable() == nil {
                playerDataSource?.clearDownloadableMediaWindow()
            }
            renderWebContent(token.html)
        } else if let mediaWindow = prepareCurrentDownloadableMediaWindow() {
            let descriptor = mediaWindow.currentDescriptor
            switch descriptor.media {
            case .staticImage:
                renderImage(descriptor, fallbackHTML: token.html)
            case .animatedImage:
                renderAnimatedImage(
                    descriptor,
                    adjacentDescriptor: mediaWindow.adjacentDescriptor,
                    fallbackHTML: token.html
                )
            case .video:
                renderVideo(descriptor, fallbackHTML: token.html)
            case .html:
                renderHTMLDocument(descriptor, fallbackHTML: token.html)
            }
        } else {
            discardPendingProvisionalStaticImage()
            renderWebContent(token.html)
        }
        playerDataSource?.didRenderPagePosition(pagePosition)
    }

    fileprivate func refreshDownloadableMediaWindow() {
        guard willOrDidAppear else { return }
        guard let token = playerDataSource?.getToken(pagePosition: pagePosition) else {
            playerDataSource?.clearDownloadableMediaWindow()
            return
        }
        if usesStaticImageGridLayoutForCurrentPagePosition || token.media == nil {
            if prepareStaticImageGridMediaWindowIfAvailable() == nil {
                playerDataSource?.clearDownloadableMediaWindow()
            }
            if let imageSpreadRenderState {
                recoverAvailableImageSpreadSlots(in: imageSpreadRenderState)
            }
            return
        }

        _ = prepareCurrentDownloadableMediaWindow()
    }

    private func prepareCurrentDownloadableMediaWindow() -> PlayerDownloadableMediaWindow? {
        playerDataSource?.prepareDownloadableMediaWindow(
            for: pagePosition,
            direction: preferredPrefetchDirection
        )
    }

    private func prepareStaticImageGridMediaWindowIfAvailable() -> PlayerDownloadableMediaWindow? {
        guard let descriptor = playerDataSource?.staticImageGridMediaDescriptor(for: pagePosition),
              let staticImageGridLayout = MobilePlayerPageLayout.staticImageGridLayout(for: descriptor) else {
            return nil
        }

        return playerDataSource?.prepareStaticImageGridMediaWindow(
            for: pagePosition,
            pageLayout: staticImageGridLayout,
            direction: preferredPrefetchDirection
        )
    }

    fileprivate func replaceVisibleContentIfAvailable(
        targetPagePosition: PlayerPagePosition,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    ) -> Bool {
        guard pageLayout == .onePerPage else { return false }
        guard canReplaceVisibleContent else { return false }

        if let renderedPagePosition, renderedPagePosition == targetPagePosition {
            return false
        }

        guard let targetToken = playerDataSource?.getToken(pagePosition: targetPagePosition),
              targetToken.nativeMetalCardRenderKind == nil,
              let descriptor = playerDataSource?.downloadableMediaDescriptor(for: targetPagePosition),
              descriptor.isStaticImage else {
            return false
        }

        if let image = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            guard commitStaticImageReplacement(
                image,
                descriptor: descriptor,
                pagePosition: targetPagePosition,
                preferredPrefetchDirection: preferredPrefetchDirection
            ) else { return false }
            return true
        }

        return false
    }

    private var canReplaceVisibleContent: Bool {
        willOrDidAppear && isViewLoaded && view.window != nil
    }

    private func commitStaticImageReplacement(
        _ image: UIImage,
        descriptor: DownloadableMediaDescriptor,
        pagePosition: PlayerPagePosition,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    ) -> Bool {
        guard playerDataSource?.prepareDownloadableMediaWindow(
            for: pagePosition,
            direction: preferredPrefetchDirection
        ) != nil else {
            return false
        }

        self.preferredPrefetchDirection = preferredPrefetchDirection
        self.pagePosition = pagePosition
        resetZoom(animated: false)
        beginRenderingPagePosition(pagePosition)
        clearImageSpreadRenderState()
        clearAnimatedRenderContext()
        setZoomContentLayout(.staticImage(image.size))
        mediaRenderer.displayLoadedImage(image, key: descriptor)
        playerDataSource?.didRenderPagePosition(pagePosition)
        return true
    }

    private func beginRenderingPagePosition(_ pagePosition: PlayerPagePosition) {
        if let renderedPagePosition {
            playerDataSource?.didCleanupPagePosition(renderedPagePosition)
        }
        renderGeneration &+= 1
        activeRenderGeneration = renderGeneration
        renderedPagePosition = pagePosition
    }

    private func invalidateRenderGeneration() {
        renderGeneration &+= 1
        activeRenderGeneration = nil
    }

    private func standardThumbnailDescriptor(
        matching descriptor: DownloadableMediaDescriptor
    ) -> DownloadableMediaDescriptor? {
        let thumbnailDescriptor = MobileCollectionCatalog.staticImageGridMediaDescriptor(
            for: descriptor
        )
        return thumbnailDescriptor == descriptor ? nil : thumbnailDescriptor
    }

    private func renderImage(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        let handoffImage = takePendingProvisionalStaticImage(matching: descriptor)
        let thumbnailDescriptor = standardThumbnailDescriptor(matching: descriptor)
        let provisionalImage = handoffImage ?? thumbnailDescriptor.flatMap {
            DownloadableMediaCache.shared.cachedDecodedImage(for: $0)
        }
        let loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)? = {
            guard provisionalImage == nil, let thumbnailDescriptor else { return nil }
            return { completion in
                DownloadableMediaCache.shared.loadProvisionalImage(
                    for: thumbnailDescriptor,
                    completion: completion
                )
            }
        }()

        clearAnimatedRenderContext()
        mediaRenderer.renderImage(
            key: descriptor,
            hideImageUntilLoaded: false,
            provisionalImage: provisionalImage,
            loadProvisionalImage: loadProvisionalImage,
            load: { completion in
                DownloadableMediaCache.shared.loadImage(for: descriptor, completion: completion)
            },
            fallbackToWebContent: { [weak self] in
                self?.renderWebContent(fallbackHTML)
            },
            onDisplayedProvisionalImage: { [weak self] image in
                self?.setZoomContentLayout(.staticImage(image.size))
            },
            onLoadedImage: { [weak self] image in
                guard let self else { return }
                self.setZoomContentLayout(
                    .staticImage(image.size),
                    preservingZoomForEquivalentStaticImageLayout: true
                )
            }
        )
    }

    private func renderImageSpread(
        _ descriptor: DownloadableMediaDescriptor,
        imageDescriptors staticImageDescriptors: [DownloadableMediaDescriptor]
    ) {
        let imageDescriptors = staticImageDescriptors.isEmpty ? [descriptor] : staticImageDescriptors
        clearImageSpreadRenderState()
        let renderState = StaticImageSpreadRenderState(
            renderGeneration: activeRenderGeneration,
            pagePosition: pagePosition,
            pageLayout: pageLayout,
            descriptors: imageDescriptors
        )
        imageSpreadRenderState = renderState
        let viewportSize = validViewportSize(zoomScrollView.bounds.size)
        let initialImages = imageDescriptors.map {
            DownloadableMediaCache.shared.cachedDecodedImage(for: $0)
        }
        let handoffImages = takePendingProvisionalStaticImages(matching: imageDescriptors)
        let placeholderImages = imageDescriptors.indices.map { index -> UIImage? in
            if let handoffImage = handoffImages[index] {
                return handoffImage
            }

            let imageDescriptor = imageDescriptors[index]
            guard imageDescriptor.isStaticImageGridThumbnail,
                  MobileCollectionCatalog.standardThumbsPathsAvailable(
                    specificCollectionId: imageDescriptor.collectionId
                  ),
                  let primaryDescriptor = playerDataSource?.downloadableMediaDescriptor(
                    for: pagePosition.advanced(by: index)
                  ),
                  primaryDescriptor != imageDescriptor,
                  PlayerStaticImageIdentity(primaryDescriptor) == PlayerStaticImageIdentity(imageDescriptor) else {
                return nil
            }

            return DownloadableMediaCache.shared.cachedDecodedImage(for: primaryDescriptor)
        }
        let seedImages = imageDescriptors.indices.map { index in
            initialImages[index] ?? placeholderImages[index]
        }
        clearAnimatedRenderContext()
        setZoomContentLayout(
            .staticImageSpread(
                StaticImageSpreadZoomLayout(
                    pageLayout: pageLayout,
                    imageSizes: MobilePlayerPageLayout.staticImageGridImageSizes(
                        for: imageDescriptors,
                        images: seedImages
                    )
                )
            )
        )
        mediaRenderer.renderImageSpread(
            key: renderState.renderKey,
            pageLayout: renderState.pageLayout,
            viewportSize: viewportSize,
            nativeMetalCardCornerMaskIndices: nativeMetalCardCornerMaskIndices(for: imageDescriptors),
            mediaPlaceholderSpecs: imageDescriptors.map(PlayerMediaPlaceholderSpec.init(descriptor:)),
            initialImages: initialImages,
            placeholderImages: placeholderImages,
            imageSlotKeys: imageDescriptors.map { AnyHashable($0) },
            loadImages: imageDescriptors.map { imageDescriptor in
                { completion in
                    DownloadableMediaCache.shared.loadImage(for: imageDescriptor, completion: completion)
                }
            },
            onEmptySpread: {},
            onImageLoadFailure: { [weak self, weak renderState] index in
                guard let self, let renderState else { return }
                self.handleImageSpreadLoadFailure(at: index, in: renderState)
            },
            onLoadedImages: { [weak self, weak renderState] images in
                guard let self,
                      let renderState,
                      self.isCurrentImageSpreadRenderState(renderState) else {
                    return
                }
                self.setZoomContentLayout(
                    .staticImageSpread(
                        StaticImageSpreadZoomLayout(
                            pageLayout: renderState.pageLayout,
                            imageSizes: MobilePlayerPageLayout.staticImageGridImageSizes(
                                for: imageDescriptors,
                                images: images
                            )
                        )
                    )
                )
                self.prewarmNativeMetalCardFaces(for: imageDescriptors)
            }
        )
    }

    private func isCurrentImageSpreadRenderState(_ state: StaticImageSpreadRenderState) -> Bool {
        guard imageSpreadRenderState === state,
              let renderGeneration = state.renderGeneration,
              activeRenderGeneration == renderGeneration,
              renderedPagePosition == state.pagePosition,
              pagePosition == state.pagePosition,
              pageLayout == state.pageLayout else {
            return false
        }

        return true
    }

    private func handleImageSpreadLoadFailure(
        at index: Int,
        in state: StaticImageSpreadRenderState
    ) {
        guard isCurrentImageSpreadRenderState(state),
              state.descriptors.indices.contains(index) else {
            return
        }

        let isFirstFailure = !state.failedIndices.contains(index)
        state.failedIndices.insert(index)
        installImageSpreadCacheObserverIfNeeded(for: state)
        recoverImageSpreadSlot(
            at: index,
            in: state,
            allowsNetworkRetry: isFirstFailure
        )
    }

    private func installImageSpreadCacheObserverIfNeeded(
        for state: StaticImageSpreadRenderState
    ) {
        guard state.cacheObserver == nil else { return }

        state.cacheObserver = NotificationCenter.default.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self, weak state] _ in
            guard let self, let state else { return }
            self.recoverAvailableImageSpreadSlots(in: state)
        }
    }

    private func recoverAvailableImageSpreadSlots(
        in state: StaticImageSpreadRenderState
    ) {
        guard isCurrentImageSpreadRenderState(state) else { return }

        for index in Array(state.failedIndices) {
            recoverImageSpreadSlot(
                at: index,
                in: state,
                allowsNetworkRetry: false
            )
        }
    }

    private func recoverImageSpreadSlot(
        at index: Int,
        in state: StaticImageSpreadRenderState,
        allowsNetworkRetry: Bool
    ) {
        guard isCurrentImageSpreadRenderState(state),
              state.failedIndices.contains(index),
              state.recoveryAttemptIDs[index] == nil,
              state.descriptors.indices.contains(index) else {
            return
        }

        let mediaCache = DownloadableMediaCache.shared
        let descriptor = state.descriptors[index]
        if let image = mediaCache.cachedDecodedImage(for: descriptor) {
            displayRecoveredImageSpreadImage(
                image,
                at: index,
                descriptor: descriptor,
                in: state
            )
            return
        }

        // Cache notifications are shared across descriptors. Only the initial bounded retry may
        // start a new download; notification-driven recovery waits until this slot has a local file.
        guard allowsNetworkRetry || mediaCache.localFileURL(for: descriptor) != nil else { return }

        let attemptID = UUID()
        state.recoveryAttemptIDs[index] = attemptID
        let cancellation = mediaCache.loadImage(for: descriptor) { [weak self, weak state] image in
            guard let self,
                  let state,
                  self.isCurrentImageSpreadRenderState(state),
                  state.recoveryAttemptIDs[index] == attemptID else {
                return
            }

            state.recoveryAttemptIDs.removeValue(forKey: index)
            state.recoveryCancellations.removeValue(forKey: index)
            guard let image else { return }

            self.displayRecoveredImageSpreadImage(
                image,
                at: index,
                descriptor: descriptor,
                in: state
            )
        }

        guard isCurrentImageSpreadRenderState(state),
              state.recoveryAttemptIDs[index] == attemptID else {
            cancellation?()
            return
        }
        if let cancellation {
            state.recoveryCancellations[index] = cancellation
        }
    }

    private func displayRecoveredImageSpreadImage(
        _ image: UIImage,
        at index: Int,
        descriptor: DownloadableMediaDescriptor,
        in state: StaticImageSpreadRenderState
    ) {
        guard isCurrentImageSpreadRenderState(state),
              state.failedIndices.contains(index),
              mediaRenderer.displayRecoveredImage(
                image,
                at: index,
                spreadKey: state.renderKey,
                slotKey: descriptor
              ) else {
            return
        }

        state.failedIndices.remove(index)
        if state.failedIndices.isEmpty {
            removeImageSpreadCacheObserver(from: state)
        }

        if let images = mediaRenderer.imageSpreadImages() {
            setZoomContentLayout(
                .staticImageSpread(
                    StaticImageSpreadZoomLayout(
                        pageLayout: state.pageLayout,
                        imageSizes: MobilePlayerPageLayout.staticImageGridImageSizes(
                            for: state.descriptors,
                            images: images
                        )
                    )
                )
            )
        }
        prewarmNativeMetalCardFaces(for: [descriptor])
    }

    private func removeImageSpreadCacheObserver(
        from state: StaticImageSpreadRenderState
    ) {
        guard let cacheObserver = state.cacheObserver else { return }

        NotificationCenter.default.removeObserver(cacheObserver)
        state.cacheObserver = nil
    }

    private func clearImageSpreadRenderState() {
        guard let state = imageSpreadRenderState else { return }

        imageSpreadRenderState = nil
        removeImageSpreadCacheObserver(from: state)
        let cancellations = Array(state.recoveryCancellations.values)
        state.recoveryAttemptIDs.removeAll()
        state.recoveryCancellations.removeAll()
        cancellations.forEach { $0() }
    }

    private func validViewportSize(_ size: CGSize) -> CGSize? {
        guard size.width > 0,
              size.height > 0,
              size.width.isFinite,
              size.height.isFinite else {
            return nil
        }

        return size
    }

    private func nativeMetalCardCornerMaskIndices(for descriptors: [DownloadableMediaDescriptor]) -> Set<Int> {
        Set(descriptors.enumerated().compactMap { index, descriptor in
            descriptor.isNativeMetalCard ? index : nil
        })
    }

    private func prewarmNativeMetalCardFaces(for descriptors: [DownloadableMediaDescriptor]) {
        for descriptor in descriptors {
            guard let renderKind = descriptor.nativeMetalCardRenderKind,
                  let tokenID = Int(descriptor.tokenId) else {
                continue
            }
            guard let cachedStaticImageURL = DownloadableMediaCache.shared.localFileURL(for: descriptor) else {
                renderKind.loadFace(for: tokenID) { _ in }
                continue
            }

            renderKind.cacheFace(for: tokenID, from: cachedStaticImageURL) { didCacheFace in
                guard !didCacheFace else { return }
                renderKind.loadFace(for: tokenID) { _ in }
            }
        }
    }

    private func staticImageGridImageDescriptors(
        startingWith descriptor: DownloadableMediaDescriptor
    ) -> [DownloadableMediaDescriptor] {
        guard pageLayout.isStaticImageGrid,
              pageLayout.supports(descriptor: descriptor) else {
            return [descriptor]
        }

        let descriptors = playerDataSource?.staticImageGridDescriptors(
            containing: pagePosition,
            for: pageLayout
        ) ?? []
        guard descriptors.first == descriptor else {
            return [descriptor]
        }
        return descriptors
    }

    private var usesStaticImageGridLayoutForCurrentPagePosition: Bool {
        pageLayout.isStaticImageGrid
            && playerDataSource?.supportsPageLayout(
                pageLayout,
                for: pagePosition
            ) == true
    }

    private func renderWebContent(_ html: String) {
        clearAnimatedRenderContext()
        setZoomContentLayout(.viewport)
        renderAnimatedFallbackWebContent(html)
    }

    private func renderNativeMetalCard(_ token: GeneratedToken, renderKind: NativeMetalCardRenderKind) {
        clearAnimatedRenderContext()
        setZoomContentLayout(.viewport, allowedContent: .nativeMetalCard)
        mediaRenderer.renderNativeMetalCard(
            tokenId: token.id,
            renderKind: renderKind
        )
    }

    private func renderAnimatedFallbackWebContent(_ html: String) {
        setZoomContentLayout(.viewport)
        mediaRenderer.renderWebContent(html)
    }

    private func renderAnimatedImage(
        _ descriptor: DownloadableMediaDescriptor,
        adjacentDescriptor: DownloadableMediaDescriptor?,
        fallbackHTML: String
    ) {
        renderDownloadableWebMedia(
            descriptor,
            adjacentDescriptor: adjacentDescriptor,
            fallbackHTML: fallbackHTML,
            mediaKind: .image
        )
    }

    private func renderVideo(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        renderDownloadableWebMedia(descriptor, fallbackHTML: fallbackHTML, mediaKind: .video)
    }

    private func renderHTMLDocument(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        renderDownloadableWebMedia(descriptor, fallbackHTML: fallbackHTML, mediaKind: .htmlDocument)
    }

    private func renderDownloadableWebMedia(
        _ descriptor: DownloadableMediaDescriptor,
        adjacentDescriptor: DownloadableMediaDescriptor? = nil,
        fallbackHTML: String,
        mediaKind: DownloadableWebMediaKind
    ) {
        let handoffImage = takePendingProvisionalStaticImage(matching: descriptor)
        let thumbnailDescriptor = standardThumbnailDescriptor(matching: descriptor)
        let provisionalImage = handoffImage ?? thumbnailDescriptor.flatMap {
            DownloadableMediaCache.shared.cachedDecodedImage(for: $0)
        }
        if let provisionalImage {
            setZoomContentLayout(.staticImage(provisionalImage.size))
        } else {
            setZoomContentLayout(.viewport)
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
        cancelProvisionalAnimatedMediaImageLoad = DownloadableMediaCache.shared.loadProvisionalImage(
            for: thumbnailDescriptor
        ) { [weak self] image in
            guard let self,
                  self.animatedRenderContext == context else {
                return
            }

            self.cancelProvisionalAnimatedMediaImageLoad = nil
            guard let image,
                  self.renderedAnimatedImageURL == nil else {
                return
            }

            self.provisionalAnimatedMediaImage = image
            if DownloadableMediaCache.shared.localFileURL(for: context.descriptor) == nil {
                self.setZoomContentLayout(.staticImage(image.size))
                self.mediaRenderer.displayLoadedImage(image, key: context.descriptor)
            } else {
                self.mediaRenderer.displayProvisionalImageOverLoadingWebContent(image)
            }
        }
    }

    private func renderAvailableAnimatedLocalContent() {
        guard let context = animatedRenderContext else { return }

        let imageCache = DownloadableMediaCache.shared
        guard let localFileURL = imageCache.localFileURL(for: context.descriptor) else {
            cancelVideoSizeLoad()
            failedAnimatedLocalContentVersion = nil
            clearAnimatedImageURLState()
            if let provisionalAnimatedMediaImage {
                setZoomContentLayout(.staticImage(provisionalAnimatedMediaImage.size))
            }
            displayProvisionalAnimatedMediaImageOrClearContent(for: context)
            return
        }

        let nextLocalFileURL = context.adjacentDescriptor.flatMap {
            imageCache.localFileURL(for: $0)
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
            mediaRenderer.preloadWebImage(nextLocalFileURL) { [weak self] didPreload in
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

        let localContentVersion = LocalMediaFileVersion(
            fileURL: localFileURL,
            descriptor: context.descriptor
        )
        guard failedAnimatedLocalContentVersion != localContentVersion else { return }
        failedAnimatedLocalContentVersion = nil

        let html: String
        switch context.mediaKind {
        case .image:
            if let imageSize = imageSize(at: localFileURL) {
                setZoomContentLayout(
                    .staticImage(imageSize),
                    preservingZoomForEquivalentStaticImageLayout: true
                )
            }
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: localFileURL.absoluteString,
                nextImageURL: nextLocalFileURL?.absoluteString
            )
        case .video:
            loadVideoSizeIfNeeded(at: localFileURL, context: context)
            html = DownloadableTokenHTML.createVideoHTML(videoURL: localFileURL.absoluteString)
        case .htmlDocument:
            renderCachedHTMLDocument(
                context: context,
                imageCache: imageCache,
                localContentVersion: localContentVersion
            )
            return
        }

        renderAnimatedLocalWebContent(
            html,
            context: context,
            localContentVersion: localContentVersion,
            htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
            readAccessURL: imageCache.webViewReadAccessURL
        )
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
        mediaRenderer.renderLocalWebContent(
            html,
            contentKind: context.mediaKind,
            htmlDirectoryURL: htmlDirectoryURL,
            readAccessURL: readAccessURL,
            provisionalImage: provisionalAnimatedMediaImage,
            onLoadSuccess: { [weak self] in
                guard let self,
                      self.validateAnimatedLocalContentResult(
                        localContentVersion,
                        context: context
                      ) else { return false }

                self.cancelProvisionalAnimatedMediaImageLoadIfNeeded()
                self.provisionalAnimatedMediaImage = nil
                self.failedAnimatedLocalContentVersion = nil
                self.clearAnimatedImageURLState()
                self.renderedAnimatedImageURL = fileURL
                self.renderAvailableAnimatedLocalContent()
                return true
            },
            onLoadFailure: { [weak self] in
                guard let self,
                      self.validateAnimatedLocalContentResult(
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
        imageCache: DownloadableMediaCache,
        localContentVersion: LocalMediaFileVersion
    ) {
        let fileURL = localContentVersion.fileURL
        displayProvisionalAnimatedMediaImageOrClearContent(for: context)
        pendingAnimatedImageURL = fileURL
        htmlDocumentRenderQueue.async {
            let renderedDocument = (try? String(contentsOf: fileURL, encoding: .utf8)).map { documentHTML in
                (
                    html: DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                        documentHTML: documentHTML,
                        baseURL: imageCache.downloadedSourceURL(for: context.descriptor).absoluteString
                    ),
                    viewportSize: DownloadableTokenHTMLLayout.rootSVGViewBoxSize(in: documentHTML)
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.validateAnimatedLocalContentResult(
                        localContentVersion,
                        context: context
                      ) else { return }

                guard let renderedDocument else {
                    self.handleAnimatedLocalContentFailure(
                        context,
                        localContentVersion: localContentVersion
                    )
                    return
                }

                if let viewportSize = renderedDocument.viewportSize {
                    self.setZoomContentLayout(
                        .staticImage(viewportSize),
                        preservingZoomForEquivalentStaticImageLayout: true
                    )
                } else {
                    self.setZoomContentLayout(.viewport)
                }
                self.renderAnimatedLocalWebContent(
                    renderedDocument.html,
                    context: context,
                    localContentVersion: localContentVersion,
                    htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
                    readAccessURL: imageCache.webViewHTMLDirectoryURL
                )
            }
        }
    }

    private func validateAnimatedLocalContentResult(
        _ localContentVersion: LocalMediaFileVersion,
        context: AnimatedRenderContext
    ) -> Bool {
        guard animatedRenderContext == context,
              pendingAnimatedImageURL == localContentVersion.fileURL else {
            return false
        }

        return !retryAnimatedLocalContentIfFileChanged(
            from: localContentVersion,
            context: context
        )
    }

    private func displayProvisionalAnimatedMediaImageOrClearContent(
        for context: AnimatedRenderContext
    ) {
        if let provisionalAnimatedMediaImage {
            mediaRenderer.displayLoadedImage(
                provisionalAnimatedMediaImage,
                key: context.descriptor
            )
        } else {
            mediaRenderer.clearContent()
        }
    }

    private func retryAnimatedLocalContentIfFileChanged(
        from attemptedVersion: LocalMediaFileVersion,
        context: AnimatedRenderContext
    ) -> Bool {
        let currentVersion = DownloadableMediaCache.shared
            .localFileURL(for: context.descriptor)
            .map {
                LocalMediaFileVersion(
                    fileURL: $0,
                    descriptor: context.descriptor
                )
            }
        guard currentVersion != attemptedVersion else { return false }

        failedAnimatedLocalContentVersion = nil
        clearAnimatedImageURLState()
        mediaRenderer.invalidateLocalWebContentLoad()
        renderAvailableAnimatedLocalContent()
        return true
    }

    private func handleAnimatedLocalContentFailure(
        _ context: AnimatedRenderContext,
        localContentVersion: LocalMediaFileVersion
    ) {
        if let provisionalAnimatedMediaImage {
            cancelVideoSizeLoad()
            setZoomContentLayout(.staticImage(provisionalAnimatedMediaImage.size))
            failedAnimatedLocalContentVersion = localContentVersion
            clearAnimatedImageURLState()
            displayProvisionalAnimatedMediaImageOrClearContent(for: context)
            return
        }

        clearAnimatedRenderContext()
        renderAnimatedFallbackWebContent(context.fallbackHTML)
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

    private func loadVideoSizeIfNeeded(at fileURL: URL, context: AnimatedRenderContext) {
        let request = VideoSizeRequest(fileURL: fileURL, descriptor: context.descriptor)

        if let videoSizeLoad, videoSizeLoad.request != request {
            cancelVideoSizeLoad()
        }

        if let cachedSize = cachedVideoSizes[request] {
            applyVideoSizeIfCurrent(cachedSize, for: request)
            return
        }

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
        guard let context = animatedRenderContext,
              context.mediaKind == .video,
              let fileURL = DownloadableMediaCache.shared.localFileURL(for: context.descriptor) else {
            return
        }

        let request = VideoSizeRequest(fileURL: fileURL, descriptor: context.descriptor)
        guard let cachedSize = cachedVideoSizes[request] else { return }

        applyVideoSizeIfCurrent(cachedSize, for: request)
    }

    private func applyVideoSizeIfCurrent(_ size: CGSize, for request: VideoSizeRequest) {
        guard let context = animatedRenderContext,
              context.mediaKind == .video,
              context.descriptor == request.descriptor,
              DownloadableMediaCache.shared.localFileURL(for: request.descriptor) == request.fileURL,
              VideoSizeRequest(fileURL: request.fileURL, descriptor: request.descriptor) == request,
              !isZoomed,
              !zoomScrollView.isZooming else {
            return
        }

        setZoomContentLayout(.staticImage(size))
    }

    private func cancelVideoSizeLoad() {
        videoSizeLoad?.task.cancel()
        videoSizeLoad = nil
    }

    private func cancelProvisionalAnimatedMediaImageLoadIfNeeded() {
        cancelProvisionalAnimatedMediaImageLoad?()
        cancelProvisionalAnimatedMediaImageLoad = nil
    }

    private func setAnimatedRenderContext(
        _ context: AnimatedRenderContext,
        provisionalImage: UIImage?
    ) {
        cancelVideoSizeLoad()
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        animatedRenderContext = context
        provisionalAnimatedMediaImage = provisionalImage
        failedAnimatedLocalContentVersion = nil
        clearAnimatedImageURLState()
        installDownloadableMediaCacheObserverIfNeeded()
    }

    private func clearAnimatedRenderContext() {
        cancelVideoSizeLoad()
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        animatedRenderContext = nil
        provisionalAnimatedMediaImage = nil
        failedAnimatedLocalContentVersion = nil
        clearAnimatedImageURLState()
        removeDownloadableMediaCacheObserver()
    }

    private func clearAnimatedImageURLState() {
        pendingAnimatedImageURL = nil
        renderedAnimatedImageURL = nil
        renderedAnimatedNextImageURL = nil
        pendingAnimatedNextImageURL = nil
    }

    private func installDownloadableMediaCacheObserverIfNeeded() {
        guard downloadableMediaCacheObserver == nil else { return }

        downloadableMediaCacheObserver = NotificationCenter.default.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderAvailableAnimatedLocalContent()
        }
    }

    private func removeDownloadableMediaCacheObserver() {
        guard let downloadableMediaCacheObserver else { return }

        NotificationCenter.default.removeObserver(downloadableMediaCacheObserver)
        self.downloadableMediaCacheObserver = nil
    }

}

private class HorizontalPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    let pageA: SpecificPageViewController
    let pageB: SpecificPageViewController
    let pageC: SpecificPageViewController

    private var isPageTransitioning = false
    private var inPlaceReloadGeneration = 0
    private var activeInPlaceReloadGeneration: Int?
    private var pendingNavigationDirection: PlaybackNavigationDirection?
    private var configuredPagingPanGestures = Set<ObjectIdentifier>()
    private var didNotifyPaginationAttemptDuringCurrentPan = false
    private var didNotifyUnavailableNavigationDuringCurrentPan = false
    private var isPagingScrollEnabled = true
    private var isCurrentPageZoomed = false
    private var lastSettledPagePosition: PlayerPagePosition?
    private var zoomedPagingPanRestingOffsets = [ObjectIdentifier: CGFloat]()
    private var unlockedZoomedPagingPanGestures = Set<ObjectIdentifier>()
    private weak var playerDataSource: HorizontalPlayerDataSource?
    private var pageLayout: MobilePlayerPageLayout
    var onCurrentZoomStateChange: ((Bool) -> Void)?

    init(pageLayout: MobilePlayerPageLayout, playerDataSource: HorizontalPlayerDataSource) {
        let initialPagePosition = playerDataSource.stablePagePosition(
            containing: .initial,
            for: pageLayout
        )
        let initialNavigationStride = playerDataSource.navigationStride(
            from: initialPagePosition,
            for: pageLayout
        )
        self.playerDataSource = playerDataSource
        self.pageLayout = pageLayout
        pageA = SpecificPageViewController(
            pagePosition: initialPagePosition,
            pageLayout: pageLayout,
            playerDataSource: playerDataSource
        )
        pageB = SpecificPageViewController(
            pagePosition: initialPagePosition.advanced(by: initialNavigationStride),
            pageLayout: pageLayout,
            playerDataSource: playerDataSource
        )
        pageC = SpecificPageViewController(
            pagePosition: initialPagePosition.advanced(by: -initialNavigationStride),
            pageLayout: pageLayout,
            playerDataSource: playerDataSource
        )
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: MobilePlayerGestureTuning.playerPageGap]
        )
        [pageA, pageB, pageC].forEach { page in
            page.onZoomStateChange = { [weak self] in
                self?.updatePagingScrollEnabled()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        makePlayerBackgroundTransparent()
        dataSource = self
        delegate = self
        setViewControllers([pageA], direction: .forward, animated: false, completion: nil)
        configurePagingScrollViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePagingScrollViews()
    }

    private var pagingScrollViews: [UIScrollView] {
        view.subviews.compactMap { $0 as? UIScrollView }
    }

    private var currentPage: SpecificPageViewController? {
        viewControllers?.first as? SpecificPageViewController
    }

    func makePlayerBackgroundTransparent() {
        view.makeBackgroundTransparent()
        pagingScrollViews.forEach {
            $0.makeBackgroundTransparent()
        }
        pageA.makePlayerBackgroundTransparent()
        pageB.makePlayerBackgroundTransparent()
        pageC.makePlayerBackgroundTransparent()
    }

    func toggleZoom(at location: CGPoint, in coordinateView: UIView) {
        currentPage?.toggleZoom(at: location, in: coordinateView)
        updatePagingScrollEnabled()
    }

    func staticImageGridSelection(
        at location: CGPoint,
        in coordinateView: UIView,
        requiresLoadedImage: Bool = true
    ) -> MobilePlayerStaticImageGridSelection? {
        guard pageLayout.isStaticImageGrid,
              let selection = currentPage?.staticImageGridSelection(
                at: location,
                in: coordinateView,
                requiresLoadedImage: requiresLoadedImage
              ),
              canRender(selection.pagePosition) else {
            return nil
        }

        return selection
    }

    func canSelectStaticImageGrid(at location: CGPoint, in coordinateView: UIView) -> Bool {
        guard pageLayout.isStaticImageGrid,
              let pagePosition = currentPage?.canSelectStaticImageGrid(at: location, in: coordinateView),
              canRender(pagePosition) else {
            return false
        }

        return true
    }

    @discardableResult
    func openStaticImageGridSelection(_ selection: MobilePlayerStaticImageGridSelection) -> Bool {
        let provisionalImage = currentPage?.provisionalStaticImage(
            for: selection.pagePosition,
            pageLayout: .onePerPage
        )
        return reanchorCurrentPage(
            to: selection.pagePosition,
            pageLayout: .onePerPage,
            provisionalImage: provisionalImage
        )
    }

    @discardableResult
    func setPageLayout(
        _ pageLayout: MobilePlayerPageLayout,
        targetPagePosition: PlayerPagePosition? = nil,
        completion: @escaping () -> Void = {}
    ) -> Bool {
        if let targetPagePosition {
            let provisionalImage = currentPage?.provisionalStaticImage(
                for: targetPagePosition,
                pageLayout: pageLayout
            )
            return reanchorCurrentPage(
                to: targetPagePosition,
                pageLayout: pageLayout,
                provisionalImage: provisionalImage,
                forceDisplayUpdate: true,
                completion: completion
            )
        }

        guard self.pageLayout != pageLayout else { return false }

        if pageLayout.isStaticImageGrid,
           let currentPage {
            let previousPagePosition = currentPage.pagePosition
            let provisionalImage = currentPage.provisionalStaticImage(
                for: previousPagePosition,
                pageLayout: pageLayout
            )
            let stablePageResolution = playerDataSource?.exitWidgetInsertionForStablePage(
                containing: currentPage.pagePosition,
                for: pageLayout
            ) ?? PlayerStablePagePositionResolution.resolved(
                pagePosition: previousPagePosition,
                didExitWidgetInsertion: false
            )

            switch stablePageResolution {
            case .resolved(let stablePageResult):
                let didExitWidgetInsertionWithoutChangingPagePosition = stablePageResult.didExitWidgetInsertion
                    && stablePageResult.pagePosition == previousPagePosition
                return reanchorCurrentPage(
                    to: stablePageResult.pagePosition,
                    pageLayout: pageLayout,
                    provisionalImage: provisionalImage,
                    forceDisplayUpdate: didExitWidgetInsertionWithoutChangingPagePosition,
                    completion: completion
                )
            case .unavailable:
                return false
            }
        }

        let provisionalImage = currentPage?.provisionalStaticImage(
            for: currentPage?.pagePosition ?? .initial,
            pageLayout: pageLayout
        )
        self.pageLayout = pageLayout
        let visiblePage = currentPage
        let pages: [SpecificPageViewController] = [pageA, pageB, pageC]
        pages.forEach { page in
            let shouldRender = visiblePage.map { page === $0 } ?? false
            page.setPendingProvisionalStaticImage(shouldRender ? provisionalImage : nil)
            page.setPageLayout(pageLayout, shouldRender: shouldRender)
        }
        updatePagingScrollEnabled()
        completion()
        return true
    }

    private func resetCurrentZoom(animated: Bool) {
        currentPage?.resetZoom(animated: animated)
        updatePagingScrollEnabled()
    }

    private func resetAllZoom(animated: Bool) {
        [pageA, pageB, pageC].forEach { page in
            page.resetZoom(animated: animated)
        }
        updatePagingScrollEnabled()
    }

    private func configurePagingScrollViews() {
        var didConfigureNewPagingScrollView = false
        pagingScrollViews.forEach { scrollView in
            scrollView.makeBackgroundTransparent()
            scrollView.hideAutomaticScrollEdgeEffects()
            let panGesture = scrollView.panGestureRecognizer
            let panGestureId = ObjectIdentifier(panGesture)
            if !configuredPagingPanGestures.contains(panGestureId) {
                [pageA, pageB, pageC].forEach { page in
                    page.registerPagingPanGesture(panGesture)
                }
                panGesture.addTarget(self, action: #selector(handlePagingPan(_:)))
                configuredPagingPanGestures.insert(panGestureId)
                didConfigureNewPagingScrollView = true
            }
        }
        updatePagingScrollEnabled(force: didConfigureNewPagingScrollView)
    }

    private func updatePagingScrollEnabled(force: Bool = false) {
        let currentPageIsZoomed = currentPage?.isZoomed == true
        let shouldEnablePaging = true
        if force || isPagingScrollEnabled != shouldEnablePaging {
            isPagingScrollEnabled = shouldEnablePaging
            pagingScrollViews.forEach { scrollView in
                if scrollView.isScrollEnabled != shouldEnablePaging {
                    scrollView.isScrollEnabled = shouldEnablePaging
                }
            }
        }

        updateCurrentZoomState(currentPageIsZoomed)
    }

    private func updateCurrentZoomState(_ isZoomed: Bool) {
        guard isCurrentPageZoomed != isZoomed else { return }

        isCurrentPageZoomed = isZoomed
        onCurrentZoomStateChange?(isZoomed)
    }

    @objc private func handlePagingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            didNotifyPaginationAttemptDuringCurrentPan = false
            didNotifyUnavailableNavigationDuringCurrentPan = false
            beginZoomedPagingPanIfNeeded(gesture)

        case .changed:
            updateZoomedPagingPanLock(for: gesture)

            guard !didNotifyPaginationAttemptDuringCurrentPan,
                  !didNotifyUnavailableNavigationDuringCurrentPan else { return }

            let translation = gesture.translation(in: view)
            let hasHorizontalIntent = abs(translation.x) > MobilePlayerGestureTuning.pageBoundaryRevealTranslation
                && abs(translation.x) > abs(translation.y) * MobilePlayerGestureTuning.pageBoundaryRevealHorizontalIntentRatio
            guard hasHorizontalIntent else { return }

            let pagePosition = getCurrentPagePosition()
            let targetOffset = (translation.x > 0 ? -1 : 1) * navigationStride(from: pagePosition)
            guard !canRender(pagePosition.advanced(by: targetOffset)) else {
                didNotifyPaginationAttemptDuringCurrentPan = true
                playerDataSource?.didAttemptPagination()
                return
            }

            didNotifyUnavailableNavigationDuringCurrentPan = true
            playerDataSource?.didAttemptUnavailableHorizontalNavigation()

        case .ended, .cancelled, .failed:
            didNotifyPaginationAttemptDuringCurrentPan = false
            didNotifyUnavailableNavigationDuringCurrentPan = false
            endZoomedPagingPan(gesture)

        default:
            break
        }
    }

    private func beginZoomedPagingPanIfNeeded(_ gesture: UIPanGestureRecognizer) {
        guard currentPage?.isZoomed == true,
              let scrollView = pagingScrollView(for: gesture) else { return }

        let gestureId = ObjectIdentifier(gesture)
        zoomedPagingPanRestingOffsets[gestureId] = scrollView.contentOffset.x
        unlockedZoomedPagingPanGestures.remove(gestureId)
    }

    private func updateZoomedPagingPanLock(for gesture: UIPanGestureRecognizer) {
        guard let currentPage,
              currentPage.isZoomed,
              let scrollView = pagingScrollView(for: gesture) else { return }

        let gestureId = ObjectIdentifier(gesture)
        let restingOffsetX = zoomedPagingPanRestingOffsets[gestureId] ?? scrollView.contentOffset.x
        if currentPage.allowsPagingPanFromCurrentZoomEdge(gesture) {
            if !unlockedZoomedPagingPanGestures.contains(gestureId) {
                scrollView.contentOffset.x = restingOffsetX
                gesture.setTranslation(.zero, in: view)
                zoomedPagingPanRestingOffsets[gestureId] = scrollView.contentOffset.x
                unlockedZoomedPagingPanGestures.insert(gestureId)
            }
        } else if !unlockedZoomedPagingPanGestures.contains(gestureId) {
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

    func getCurrentPagePosition() -> PlayerPagePosition {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return .initial }
        return currentPage.pagePosition
    }

    private func navigationStride(from pagePosition: PlayerPagePosition) -> Int {
        playerDataSource?.navigationStride(from: pagePosition, for: pageLayout)
            ?? MobilePlayerPageLayout.onePerPage.pageSize
    }

    private func navigationOffset(
        _ direction: PlaybackNavigationDirection,
        from pagePosition: PlayerPagePosition
    ) -> Int? {
        let stride = navigationStride(from: pagePosition)
        return direction.pageOffset(forStride: stride)
    }

    private func update(currentPagePosition: PlayerPagePosition) {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return }
        let stride = navigationStride(from: currentPagePosition)
        switch currentPage {
        case pageA:
            pageA.update(pagePosition: currentPagePosition)
            pageB.update(pagePosition: currentPagePosition.advanced(by: stride))
            pageC.update(pagePosition: currentPagePosition.advanced(by: -stride))
        case pageB:
            pageA.update(pagePosition: currentPagePosition.advanced(by: -stride))
            pageB.update(pagePosition: currentPagePosition)
            pageC.update(pagePosition: currentPagePosition.advanced(by: stride))
        case pageC:
            pageA.update(pagePosition: currentPagePosition.advanced(by: stride))
            pageB.update(pagePosition: currentPagePosition.advanced(by: -stride))
            pageC.update(pagePosition: currentPagePosition)
        default:
            break
        }
    }

    private func restartCollection() {
        jumpToPagePosition(playerDataSource?.startPagePosition() ?? .initial)
    }

    @discardableResult
    private func reanchorCurrentPage(
        to pagePosition: PlayerPagePosition,
        pageLayout targetPageLayout: MobilePlayerPageLayout,
        provisionalImage: PlayerProvisionalStaticImage?,
        forceDisplayUpdate: Bool = false,
        completion: @escaping () -> Void = {}
    ) -> Bool {
        cancelActiveInPlacePageControllerReload()

        guard canRender(pagePosition),
              let currentPage else {
            return false
        }

        let previousPagePosition = currentPage.pagePosition
        let pageDirection: UIPageViewController.NavigationDirection = pagePosition.position < previousPagePosition.position
            ? .reverse
            : .forward

        isPageTransitioning = true
        resetAllZoom(animated: false)
        pageLayout = targetPageLayout
        pageA.setPageLayout(targetPageLayout, shouldRender: false)
        pageB.setPageLayout(targetPageLayout, shouldRender: false)
        pageC.setPageLayout(targetPageLayout, shouldRender: false)
        pageA.preferredPrefetchDirection = .forward
        pageB.preferredPrefetchDirection = .forward
        pageC.preferredPrefetchDirection = .forward

        update(currentPagePosition: pagePosition)
        currentPage.setPendingProvisionalStaticImage(provisionalImage)
        currentPage.renderCurrentItem()
        didDisplayRenderablePagePosition(pagePosition, forceUpdate: forceDisplayUpdate)
        updatePagingScrollEnabled()
        reloadPageControllerAfterInPlaceNavigation(pageDirection) { [weak self] in
            self?.performPendingNavigationIfNeeded()
            completion()
        }
        return true
    }

    private func jumpToPagePosition(_ pagePosition: PlayerPagePosition) {
        guard canRender(pagePosition) else { return }

        isPageTransitioning = true
        resetAllZoom(animated: false)
        pageA.preferredPrefetchDirection = .forward
        pageB.preferredPrefetchDirection = .forward
        pageC.preferredPrefetchDirection = .forward
        let stride = navigationStride(from: pagePosition)
        pageA.update(pagePosition: pagePosition)
        pageB.update(pagePosition: pagePosition.advanced(by: stride))
        pageC.update(pagePosition: pagePosition.advanced(by: -stride))

        setViewControllers([pageA], direction: .forward, animated: false) { [weak self] _ in
            guard let self else { return }

            self.pageA.renderCurrentItem()
            self.didDisplayRenderablePagePosition(pagePosition)
            self.isPageTransitioning = false
            self.performPendingNavigationIfNeeded()
        }
    }

    private func didSettleOnCurrentPage() -> Bool {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return false }
        guard canRender(currentPage.pagePosition) else {
            recoverFromInvalidCurrentPage(currentPage)
            return false
        }

        update(currentPagePosition: currentPage.pagePosition)
        currentPage.renderCurrentItemIfNeededForPageLayout()
        updatePagingScrollEnabled()
        didDisplayRenderablePagePosition(currentPage.pagePosition)
        return true
    }

    private func didDisplayRenderablePagePosition(_ pagePosition: PlayerPagePosition, forceUpdate: Bool = false) {
        lastSettledPagePosition = pagePosition
        playerDataSource?.didDisplayPagePosition(pagePosition, forceUpdate: forceUpdate)
    }

    private func recoverFromInvalidCurrentPage(_ currentPage: SpecificPageViewController) {
        guard let recoveryPagePosition = recoveryPagePosition(from: currentPage.pagePosition) else {
            updatePagingScrollEnabled()
            isPageTransitioning = false
            return
        }

        jumpToPagePosition(recoveryPagePosition)
    }

    private func recoveryPagePosition(from pagePosition: PlayerPagePosition) -> PlayerPagePosition? {
        let stride = navigationStride(from: pagePosition)
        for candidatePagePosition in [pagePosition.advanced(by: -stride), pagePosition.advanced(by: stride)] {
            if canRender(candidatePagePosition) {
                return candidatePagePosition
            }
        }

        if let lastSettledPagePosition,
           canRender(lastSettledPagePosition) {
            return lastSettledPagePosition
        }

        let startPagePosition = playerDataSource?.startPagePosition() ?? .initial
        if canRender(startPagePosition) {
            return startPagePosition
        }

        return nil
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        switch vc {
        case pageA:
            return adjacentHorizontalPage(from: pageA, targetPage: pageC, offset: -1)
        case pageB:
            return adjacentHorizontalPage(from: pageB, targetPage: pageA, offset: -1)
        case pageC:
            return adjacentHorizontalPage(from: pageC, targetPage: pageB, offset: -1)
        default:
            return pageA
        }
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        switch vc {
        case pageA:
            return adjacentHorizontalPage(from: pageA, targetPage: pageB, offset: 1)
        case pageB:
            return adjacentHorizontalPage(from: pageB, targetPage: pageC, offset: 1)
        case pageC:
            return adjacentHorizontalPage(from: pageC, targetPage: pageA, offset: 1)
        default:
            return pageA
        }
    }

    private func adjacentHorizontalPage(
        from sourcePage: SpecificPageViewController,
        targetPage: SpecificPageViewController,
        offset: Int
    ) -> UIViewController? {
        let targetOffset = offset * navigationStride(from: sourcePage.pagePosition)
        let targetPagePosition = sourcePage.pagePosition.advanced(by: targetOffset)
        guard canRender(targetPagePosition) else { return nil }
        targetPage.preferredPrefetchDirection = offset < 0 ? .backward : .forward
        targetPage.update(pagePosition: targetPagePosition)
        return targetPage
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let destinationPage = pendingViewControllers.first as? SpecificPageViewController else { return }
        playerDataSource?.didAttemptPagination()
        isPageTransitioning = true
        destinationPage.renderCurrentItem()
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        isPageTransitioning = false
        guard didSettleOnCurrentPage() else { return }

        if !completed {
            currentPage?.refreshDownloadableMediaWindow()
        }
        performPendingNavigationIfNeeded()
    }

    @discardableResult
    private func performPageTransition(
        _ direction: UIPageViewController.NavigationDirection,
        animated: Bool,
        completion: @escaping () -> Void
    ) -> Bool {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else {
            completion()
            return false
        }

        let targetViewController: UIViewController?
        switch direction {
        case .reverse:
            targetViewController = pageViewController(self, viewControllerBefore: currentPage)
        case .forward:
            targetViewController = pageViewController(self, viewControllerAfter: currentPage)
        default:
            completion()
            return false
        }

        guard let targetViewController else {
            completion()
            return false
        }

        resetCurrentZoom(animated: false)
        playerDataSource?.didAttemptPagination()

        if let destinationPage = targetViewController as? SpecificPageViewController {
            destinationPage.renderCurrentItem()
        }

        setViewControllers([targetViewController], direction: direction, animated: animated) { _ in
            guard self.didSettleOnCurrentPage() else { return }
            completion()
        }
        return true
    }

    func navigate(_ direction: PlaybackNavigationDirection) {
        switch direction {
        case .back, .forward:
            guard canStartNavigation else { return }
            isPageTransitioning = true
            let pageDirection: UIPageViewController.NavigationDirection = direction == .back ? .reverse : .forward
            let didStartTransition = performPageTransition(pageDirection, animated: true) { [weak self] in
                self?.isPageTransitioning = false
                self?.performPendingNavigationIfNeeded()
            }
            if !didStartTransition {
                isPageTransitioning = false
            }
        case .restartCollection:
            guard canStartNavigation else {
                pendingNavigationDirection = direction
                return
            }
            restartCollection()
        }
    }

    @discardableResult
    func navigateWithoutAnimation(_ direction: PlaybackNavigationDirection) -> Bool {
        guard canNavigateWithoutAnimation(direction) else { return false }

        if replaceCurrentPageContentWithoutPageControllerTransition(direction) {
            return true
        }

        return performUnanimatedPageTransition(direction)
    }

    private func replaceCurrentPageContentWithoutPageControllerTransition(_ direction: PlaybackNavigationDirection) -> Bool {
        guard direction.isPagingDirection,
              let currentPage = viewControllers?.first as? SpecificPageViewController else {
            return false
        }

        guard let targetOffset = navigationOffset(direction, from: currentPage.pagePosition) else { return false }
        let targetPagePosition = currentPage.pagePosition.advanced(by: targetOffset)

        let prefetchDirection: DownloadableMediaCache.PrefetchDirection = direction == .back ? .backward : .forward
        guard currentPage.replaceVisibleContentIfAvailable(
            targetPagePosition: targetPagePosition,
            preferredPrefetchDirection: prefetchDirection
        ) else { return false }

        playerDataSource?.didAttemptPagination()
        guard didSettleOnCurrentPage() else { return true }
        reloadPageControllerAfterInPlaceNavigation(direction) { [weak self] in
            self?.performPendingNavigationIfNeeded()
        }
        return true
    }

    private func reloadPageControllerAfterInPlaceNavigation(
        _ direction: PlaybackNavigationDirection,
        completion: @escaping () -> Void
    ) {
        let pageDirection: UIPageViewController.NavigationDirection = direction == .back ? .reverse : .forward
        reloadPageControllerAfterInPlaceNavigation(pageDirection, completion: completion)
    }

    private func reloadPageControllerAfterInPlaceNavigation(
        _ pageDirection: UIPageViewController.NavigationDirection,
        completion: @escaping () -> Void
    ) {
        guard let currentPage else {
            isPageTransitioning = false
            dataSource = self
            completion()
            return
        }

        let reloadGeneration = beginInPlacePageControllerReload()
        isPageTransitioning = true
        dataSource = nil
        let finishReload = { [weak self] in
            self?.completeInPlacePageControllerReload(
                generation: reloadGeneration,
                completion: completion
            )
        }
        setViewControllers([currentPage], direction: pageDirection, animated: false) { [weak self] _ in
            guard self != nil else { return }

            finishReload()
        }
        DispatchQueue.main.async {
            finishReload()
        }
    }

    private func beginInPlacePageControllerReload() -> Int {
        inPlaceReloadGeneration += 1
        activeInPlaceReloadGeneration = inPlaceReloadGeneration
        return inPlaceReloadGeneration
    }

    private func completeInPlacePageControllerReload(
        generation: Int,
        completion: () -> Void
    ) {
        guard activeInPlaceReloadGeneration == generation else { return }

        activeInPlaceReloadGeneration = nil
        dataSource = self
        configurePagingScrollViews()
        isPageTransitioning = false
        completion()
    }

    private func cancelActiveInPlacePageControllerReload() {
        guard activeInPlaceReloadGeneration != nil
            || dataSource == nil
            || (isPageTransitioning && transitionCoordinator == nil) else {
            return
        }

        activeInPlaceReloadGeneration = nil
        dataSource = self
        configurePagingScrollViews()
        if transitionCoordinator == nil {
            isPageTransitioning = false
        }
    }

    private func performUnanimatedPageTransition(_ direction: PlaybackNavigationDirection) -> Bool {
        isPageTransitioning = true
        let pageDirection: UIPageViewController.NavigationDirection = direction == .back ? .reverse : .forward
        let didStartTransition = performPageTransition(
            pageDirection,
            animated: false
        ) { [weak self] in
            self?.isPageTransitioning = false
            self?.performPendingNavigationIfNeeded()
        }
        if !didStartTransition {
            isPageTransitioning = false
        }
        return didStartTransition
    }

    func canNavigateWithoutAnimation(_ direction: PlaybackNavigationDirection) -> Bool {
        guard direction.isPagingDirection else { return false }
        guard canStartNavigation else { return false }

        return hasNavigationDestination(direction)
    }

    func hasNavigationDestination(_ direction: PlaybackNavigationDirection) -> Bool {
        guard direction.isPagingDirection else { return false }
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return false }

        guard let targetOffset = navigationOffset(direction, from: currentPage.pagePosition) else { return false }
        return canRender(currentPage.pagePosition.advanced(by: targetOffset))
    }

    private var canStartNavigation: Bool {
        !isPageTransitioning && transitionCoordinator == nil
    }

    private func performPendingNavigationIfNeeded() {
        guard let pendingNavigationDirection else { return }
        guard canStartNavigation else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
                self?.performPendingNavigationIfNeeded()
            }
            return
        }
        self.pendingNavigationDirection = nil
        navigate(pendingNavigationDirection)
    }

    private func canRender(_ pagePosition: PlayerPagePosition) -> Bool {
        playerDataSource?.canRenderPagePosition(pagePosition) ?? false
    }

}
