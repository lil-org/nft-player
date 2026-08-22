// ∅ 2026 lil org

import UIKit
import SwiftUI
import WebKit
import ImageIO
import AVFoundation

fileprivate final class NativeMetalCardProvisionalOverlayView: UIView {
    private let imageView = NativeMetalCardCornerMaskedImageView()

    var hasImage: Bool {
        imageView.image != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        makeBackgroundTransparent()
        isUserInteractionEnabled = false

        imageView.makeBackgroundTransparent()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.usesNativeMetalCardCornerMask = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = NativeMetalCardLayout.cardContentRect(in: bounds.size)
    }

    func display(_ image: UIImage) {
        layer.removeAllAnimations()
        imageView.layer.removeAllAnimations()
        imageView.image = image
        alpha = 1
        isHidden = false
        setNeedsLayout()
    }

    func hide(animated: Bool) {
        layer.removeAllAnimations()
        guard animated, !isHidden, hasImage else {
            clear()
            return
        }

        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.alpha = 0
        } completion: { [weak self] finished in
            guard finished, self?.alpha == 0 else { return }
            self?.clear()
        }
    }

    func clear() {
        layer.removeAllAnimations()
        imageView.layer.removeAllAnimations()
        imageView.image = nil
        alpha = 1
        isHidden = true
    }
}

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

    fileprivate static func nativeMetalCardProvisionalOverlayView(
        in containerView: UIView
    ) -> NativeMetalCardProvisionalOverlayView {
        let overlayView = NativeMetalCardProvisionalOverlayView()
        overlayView.isHidden = true
        install(overlayView, in: containerView)
        return overlayView
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
    private var nativeMetalCardView: NativeMetalCardView!
    private var nativeMetalCardProvisionalOverlayView: NativeMetalCardProvisionalOverlayView!
    private var representedImageKey: AnyHashable?
    private var activeImageLoadId: UUID?
    private var cancelActiveImageLoad: ImageLoadCancellation?
    private var activeNativeMetalCardPresentationID: UUID?
    private var cancelNativeMetalCardProvisionalImageLoad: ImageLoadCancellation?
    private var webViewMayContainContent = false
    private var activeLocalWebReadinessID: UUID?
    private var usesTransparentPlayerBackground = false

    init(containerView: UIView) {
        self.containerView = containerView
    }

    isolated deinit {
        cancelCurrentImageLoad()
        cancelNativeMetalCardProvisionalImageLoad?()
        nativeMetalCardView?.stop()
    }

    func clearContent() {
        activeLocalWebReadinessID = nil
        cancelCurrentImageLoad()
        hideNativeMetalCardView()
        representedImageKey = nil
        unloadWebContentIfNeeded()
        imageView?.layer.removeAllAnimations()
        imageView?.image = nil
    }

    func displayLoadedImage<Key: Hashable>(_ image: UIImage, key: Key) {
        cancelCurrentImageLoad()
        hideNativeMetalCardView()
        let imageKey = AnyHashable(key)
        representedImageKey = imageKey
        webView?.isHidden = true
        displayMainImage(image)

        unloadWebContentAfterImageDisplay(imageKey: imageKey)
    }

    func displayProvisionalImageOverLoadingWebContent(_ image: UIImage) {
        cancelCurrentImageLoad()
        representedImageKey = nil
        hideNativeMetalCardView()
        displayMainImage(image, bringsToFront: true)
    }

    func invalidateLocalWebContentLoad() {
        activeLocalWebReadinessID = nil
        webView?.invalidateRequestedContent()
    }

    func renderImage<Key: Hashable>(
        key: Key,
        hideImageUntilLoaded: Bool,
        provisionalImage: UIImage? = nil,
        loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)? = nil,
        onBegin: (() -> Void)? = nil,
        load: (@escaping (UIImage?) -> Void) -> (() -> Void)?,
        fallbackToWebContent: @escaping () -> Void,
        shouldAnimateLoadedImageReplacement: @escaping () -> Bool = { true },
        onDisplayedProvisionalImage: ((UIImage) -> Void)? = nil,
        onLoadedImage: ((UIImage) -> Void)? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        cancelCurrentImageLoad()
        ensureImageView()
        imageView.layer.removeAllAnimations()
        hideWebContent()
        hideNativeMetalCardView()
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
            self.displayImage(
                image,
                in: self.imageView,
                animated: shouldAnimateLoadedImageReplacement()
            )
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
        renderKind: NativeMetalCardRenderKind,
        provisionalImage: UIImage? = nil,
        loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)? = nil
    ) {
        resetNativeMetalCardPresentation()
        cancelCurrentImageLoad()
        representedImageKey = nil
        ensureNativeMetalCardView()
        ensureNativeMetalCardProvisionalOverlayView()
        imageView?.isHidden = true
        imageView?.image = nil
        hideWebContent()

        let presentationID = UUID()
        activeNativeMetalCardPresentationID = presentationID
        if let provisionalImage {
            displayNativeMetalCardProvisionalImage(provisionalImage)
        }
        if provisionalImage == nil, let loadProvisionalImage {
            cancelNativeMetalCardProvisionalImageLoad = loadProvisionalImage { [weak self] image in
                Task { @MainActor in
                    guard let self,
                          self.activeNativeMetalCardPresentationID == presentationID,
                          let image else {
                        return
                    }

                    self.cancelNativeMetalCardProvisionalImageLoad = nil
                    self.displayNativeMetalCardProvisionalImage(image)
                }
            }
        }

        nativeMetalCardView.display(
            tokenId: tokenId,
            renderKind: renderKind,
            onContentReady: { [weak self] in
                guard let self,
                      self.activeNativeMetalCardPresentationID == presentationID else {
                    return
                }

                self.activeNativeMetalCardPresentationID = nil
                self.cancelNativeMetalCardProvisionalImageLoad?()
                self.cancelNativeMetalCardProvisionalImageLoad = nil
                self.nativeMetalCardProvisionalOverlayView.hide(
                    animated: self.nativeMetalCardProvisionalOverlayView.hasImage
                )
            }
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

            Task { @MainActor [weak self] in
                await Task.yield()
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
        cancelCurrentImageLoad()
        representedImageKey = nil
        ensureWebView()
        if let provisionalImage {
            displayMainImage(provisionalImage, bringsToFront: true)
        } else {
            imageView?.isHidden = true
            imageView?.image = nil
        }
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

    private func displayImage(
        _ image: UIImage,
        in imageView: UIImageView,
        animated: Bool
    ) {
        guard animated, imageView.image != nil else {
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

    private func ensureNativeMetalCardProvisionalOverlayView() {
        guard nativeMetalCardProvisionalOverlayView == nil else { return }

        nativeMetalCardProvisionalOverlayView =
            FullscreenTokenMediaView.nativeMetalCardProvisionalOverlayView(in: containerView)
    }

    private func displayNativeMetalCardProvisionalImage(_ image: UIImage) {
        nativeMetalCardProvisionalOverlayView.display(image)
        containerView.bringSubviewToFront(nativeMetalCardProvisionalOverlayView)
    }

    private func hideWebContent() {
        invalidateLocalWebContentLoad()
        webView?.isHidden = true
    }

    private func hideNativeMetalCardView() {
        resetNativeMetalCardPresentation()
        nativeMetalCardView?.stop()
        nativeMetalCardView?.isHidden = true
    }

    private func resetNativeMetalCardPresentation() {
        activeNativeMetalCardPresentationID = nil
        cancelNativeMetalCardProvisionalImageLoad?()
        cancelNativeMetalCardProvisionalImageLoad = nil
        nativeMetalCardProvisionalOverlayView?.clear()
    }

    private func unloadWebContentAfterImageDisplay(imageKey: AnyHashable) {
        invalidateLocalWebContentLoad()
        guard webViewMayContainContent else { return }

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.representedImageKey == imageKey else {
                return
            }

            self.unloadWebContentIfNeeded()
        }
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

    final class Coordinator {
        private var lastBundledGenerativePresentationMode: MobileBundledGenerativePresentationMode?

        func shouldApplyBundledGenerativePresentationMode(
            _ mode: MobileBundledGenerativePresentationMode
        ) -> Bool {
            guard lastBundledGenerativePresentationMode != mode else { return false }
            lastBundledGenerativePresentationMode = mode
            return true
        }
    }

    private let initialConfig: MobilePlayerConfig
    private let chrome: MobilePlayerChromeController
    private let bundledGenerativePresentationMode: MobileBundledGenerativePresentationMode
    private let onFocusedPagePositionUpdate: ((PlayerPagePosition) -> Void)
    private let onSettledPagePositionUpdate: ((PlayerPagePosition, Bool) -> Bool)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)
    private let onToggleChrome: (() -> Void)
    private let onZoomStateChange: ((Bool) -> Void)

    init(
        initialConfig: MobilePlayerConfig,
        chrome: MobilePlayerChromeController,
        bundledGenerativePresentationMode: MobileBundledGenerativePresentationMode,
        onFocusedPagePositionUpdate: @escaping (PlayerPagePosition) -> Void,
        onSettledPagePositionUpdate: @escaping (PlayerPagePosition, Bool) -> Bool,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void,
        onToggleChrome: @escaping () -> Void,
        onZoomStateChange: @escaping (Bool) -> Void
    ) {
        self.initialConfig = initialConfig
        self.chrome = chrome
        self.bundledGenerativePresentationMode = bundledGenerativePresentationMode
        self.onFocusedPagePositionUpdate = onFocusedPagePositionUpdate
        self.onSettledPagePositionUpdate = onSettledPagePositionUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
        self.onToggleChrome = onToggleChrome
        self.onZoomStateChange = onZoomStateChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> HorizontalPlayerContainer {
        return HorizontalPlayerContainer(
            initialConfig: initialConfig,
            chrome: chrome,
            bundledGenerativePresentationMode: bundledGenerativePresentationMode,
            onFocusedPagePositionUpdate: onFocusedPagePositionUpdate,
            onSettledPagePositionUpdate: onSettledPagePositionUpdate,
            onPaginationAttempt: onPaginationAttempt,
            onUnavailableNavigation: onUnavailableNavigation,
            onToggleChrome: onToggleChrome,
            onZoomStateChange: onZoomStateChange
        )
    }

    func updateUIViewController(_ uiViewController: HorizontalPlayerContainer, context: Context) {
        if context.coordinator.shouldApplyBundledGenerativePresentationMode(
            bundledGenerativePresentationMode
        ) {
            uiViewController.setBundledGenerativePresentationMode(
                bundledGenerativePresentationMode
            )
        }
    }
}

class HorizontalPlayerContainer: UIViewController, HorizontalPlayerDataSource, UIGestureRecognizerDelegate, MobilePlayerPagerProviding {

    private let initialConfig: MobilePlayerConfig
    private let chrome: MobilePlayerChromeController
    private var bundledGenerativePresentationMode: MobileBundledGenerativePresentationMode
    private let onFocusedPagePositionUpdate: ((PlayerPagePosition) -> Void)
    private let onSettledPagePositionUpdate: ((PlayerPagePosition, Bool) -> Bool)
    private let onPaginationAttempt: (() -> Void)
    private let onUnavailableNavigation: (() -> Void)
    private let onToggleChrome: (() -> Void)
    private let onZoomStateChange: ((Bool) -> Void)

    private lazy var pagingVC = HorizontalPageViewController(playerDataSource: self)
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
    private var persistedPagePosition: PlayerPagePosition?
    private var pendingEdgeTapHighlightSide: PlayerEdgeTapSide?
    private var edgeTapHighlightTask: Task<Void, Never>?
    private var edgeTapFlashTask: Task<Void, Never>?
    private var edgeTapHighlightRequestId = 0

    init(
        initialConfig: MobilePlayerConfig,
        chrome: MobilePlayerChromeController,
        bundledGenerativePresentationMode: MobileBundledGenerativePresentationMode,
        onFocusedPagePositionUpdate: @escaping (PlayerPagePosition) -> Void,
        onSettledPagePositionUpdate: @escaping (PlayerPagePosition, Bool) -> Bool,
        onPaginationAttempt: @escaping () -> Void,
        onUnavailableNavigation: @escaping () -> Void,
        onToggleChrome: @escaping () -> Void,
        onZoomStateChange: @escaping (Bool) -> Void
    ) {
        self.initialConfig = initialConfig
        self.chrome = chrome
        self.bundledGenerativePresentationMode = bundledGenerativePresentationMode
        self.onFocusedPagePositionUpdate = onFocusedPagePositionUpdate
        self.onSettledPagePositionUpdate = onSettledPagePositionUpdate
        self.onPaginationAttempt = onPaginationAttempt
        self.onUnavailableNavigation = onUnavailableNavigation
        self.onToggleChrome = onToggleChrome
        self.onZoomStateChange = onZoomStateChange
        super.init(nibName: nil, bundle: nil)
        chrome.setPagerProvider(self)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        makePlayerBackgroundTransparent()
        pagingVC.onCurrentZoomStateChange = { [weak self] isZoomed in
            self?.onZoomStateChange(isZoomed)
        }
        installContentController(pagingVC)
        installEdgeTapHighlights()
        installTapGestures()
    }

    override func viewWillDisappear(_ animated: Bool) {
        flushPagerViewingProgress()
        super.viewWillDisappear(animated)
    }

    private func installContentController(_ controller: UIViewController) {
        addChild(controller)
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func makePlayerBackgroundTransparent() {
        view.makeBackgroundTransparent()
        pagingVC.makePlayerBackgroundTransparent()
    }

    isolated deinit {
        chrome.clearPagerProvider(self)
        edgeTapHighlightTask?.cancel()
        edgeTapFlashTask?.cancel()
    }

    func pagerCurrentPagePosition() -> PlayerPagePosition {
        pagingVC.getCurrentPagePosition()
    }

    @discardableResult
    func reanchorPager(
        to pagePosition: PlayerPagePosition,
        completion: @escaping () -> Void
    ) -> Bool {
        pagingVC.setPagePosition(pagePosition, completion: completion)
    }

    func activatePagerAfterModeSwitch(destination: PlayerPagePosition) {
        pagingVC.setActive(true)
        displayedPagePosition = nil
        if !pagingVC.publishCurrentPagePosition(forceUpdate: true) {
            updateDisplayedPagePosition(destination, forceUpdate: true)
        }
        clearEdgeTapHighlights()
    }

    func deactivatePagerForCollectionBrowser() {
        clearEdgeTapHighlights()
        onZoomStateChange(false)
        pagingVC.setActive(false)
    }

    func navigatePager(_ direction: PlaybackNavigationDirection) {
        pagingVC.navigate(direction)
    }

    func makePagerTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView? {
        pagingVC.makeCurrentPageTransitionSnapshot(
            from: sourceFrame,
            in: coordinateView
        )
    }

    func flushPagerViewingProgress() {
        _ = persistPagePositionIfNeeded(
            pagingVC.getCurrentPagePosition(),
            forceUpdate: false
        )
    }

    fileprivate func setBundledGenerativePresentationMode(
        _ presentationMode: MobileBundledGenerativePresentationMode
    ) {
        guard bundledGenerativePresentationMode != presentationMode else { return }

        bundledGenerativePresentationMode = presentationMode
        pagingVC.reloadRenderedBundledGenerativeWebContent()
    }

    private var allowsEdgeTapNavigation: Bool {
        pagingVC.isActive
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
        guard pagingVC.isActive else { return }

        if isEdgeTapLocation(gesture.location(in: view)) {
            return
        }

        onToggleChrome()
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
        edgeTapHighlightTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(
                        MobilePlayerGestureTuning.edgeTapHighlightActivationDelay
                    )
                )
            } catch {
                return
            }
            guard let self,
                  self.edgeTapHighlightRequestId == requestId,
                  self.pendingEdgeTapHighlightSide == side else {
                return
            }

            self.pendingEdgeTapHighlightSide = nil
            self.edgeTapHighlightTask = nil
            self.edgeTapHighlight(for: side).setHighlighted(true)
        }
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

        edgeTapHighlightTask?.cancel()
        edgeTapHighlightTask = nil
        pendingEdgeTapHighlightSide = nil
        edgeTapHighlightRequestId += 1
        return true
    }

    private func clearEdgeTapHighlights() {
        edgeTapHighlightTask?.cancel()
        edgeTapHighlightTask = nil
        edgeTapFlashTask?.cancel()
        edgeTapFlashTask = nil
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

        edgeTapFlashTask?.cancel()
        edgeTapFlashTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(
                        MobilePlayerGestureTuning.edgeTapHighlightTapFlashDuration
                    )
                )
            } catch {
                return
            }
            guard let self, self.edgeTapHighlightRequestId == requestId else { return }

            self.edgeTapFlashTask = nil
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
        guard pagingVC.isActive,
              gesture.state == .ended else { return }

        let location = gesture.location(in: view)
        guard !isEdgeTapLocation(location) else { return }

        pagingVC.toggleZoom(at: location, in: view)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === doubleTapRecognizer else { return true }

        return !isEdgeTapLocation(gestureRecognizer.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
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
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        MobilePlaybackController.shared.prepareDownloadableMediaWindow(
            uuid: initialConfig.id,
            pagePosition: pagePosition,
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

    fileprivate func currentBundledGenerativePresentationMode()
        -> MobileBundledGenerativePresentationMode {
        bundledGenerativePresentationMode
    }

    fileprivate func bundledGenerativeThumbnailAspectRatio(
        for pagePosition: PlayerPagePosition
    ) -> ThumbnailAspectRatio? {
        let token = getToken(pagePosition: pagePosition)
        guard token.media == nil,
              token.nativeMetalCardRenderKind == nil,
              TokenGenerator.isBundledWebGenerativeCollection(
                id: token.fullCollectionId
              ) else {
            return nil
        }

        guard let descriptor = MobilePlaybackController.shared.collectionBrowseThumbnailDescriptor(
            uuid: initialConfig.id,
            pagePosition: pagePosition
        ) else {
            return nil
        }

        guard descriptor.collectionId == token.fullCollectionId,
              descriptor.tokenId == token.id else {
            return nil
        }
        return descriptor.thumbnailAspectRatio
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
        guard pagingVC.isActive else { return }
        let shouldUpdateDisplay = forceUpdate || displayedPagePosition != pagePosition
        let shouldPersist = forceUpdate || persistedPagePosition != pagePosition
        guard shouldUpdateDisplay || shouldPersist else { return }

        if shouldUpdateDisplay {
            displayedPagePosition = pagePosition
            onFocusedPagePositionUpdate(pagePosition)
        }
        if shouldPersist {
            _ = persistPagePositionIfNeeded(pagePosition, forceUpdate: forceUpdate)
        }
    }

    @discardableResult
    private func persistPagePositionIfNeeded(
        _ pagePosition: PlayerPagePosition,
        forceUpdate: Bool
    ) -> Bool {
        guard forceUpdate || persistedPagePosition != pagePosition else { return true }
        guard onSettledPagePositionUpdate(pagePosition, false) else { return false }
        persistedPagePosition = pagePosition
        return true
    }

}

private protocol HorizontalPlayerDataSource: AnyObject {

    func getToken(pagePosition: PlayerPagePosition) -> GeneratedToken
    func prepareDownloadableMediaWindow(
        for pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow?
    func clearDownloadableMediaWindow()
    func downloadableMediaDescriptor(for pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor?
    func currentBundledGenerativePresentationMode()
        -> MobileBundledGenerativePresentationMode
    func bundledGenerativeThumbnailAspectRatio(
        for pagePosition: PlayerPagePosition
    ) -> ThumbnailAspectRatio?
    func canRenderPagePosition(_ pagePosition: PlayerPagePosition) -> Bool
    func startPagePosition() -> PlayerPagePosition
    func didRenderPagePosition(_ pagePosition: PlayerPagePosition)
    func didCleanupPagePosition(_ pagePosition: PlayerPagePosition)
    func didAttemptPagination()
    func didAttemptUnavailableHorizontalNavigation()
    func didDisplayPagePosition(_ pagePosition: PlayerPagePosition, forceUpdate: Bool)

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

    private enum ZoomContentLayout: Equatable {
        case viewport
        case staticImage(CGSize)
        case fittedWebContent(CGSize)
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
    private lazy var mediaRenderer = FullscreenTokenMediaRenderer(containerView: mediaContentView)

    private(set) var pagePosition: PlayerPagePosition

    private var renderedPagePosition: PlayerPagePosition?
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
    private var htmlDocumentRenderTask: Task<Void, Never>?
    private var imageSizeTask: Task<Void, Never>?
    private var cachedVideoSizes = [VideoSizeRequest: CGSize]()
    private var cachedVideoSizeRequests = [VideoSizeRequest]()
    private var willOrDidAppear = false
    private var isPlaybackActive = true
    private var isZoomInteractionActive = false
    private var zoomContentLayout: ZoomContentLayout = .viewport
    private var zoomAllowedContent: ZoomAllowedContent = .fullContent
    private var laidOutZoomViewportSize: CGSize = .zero
    var onZoomStateChange: (() -> Void)?
    var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    var isZoomed: Bool {
        zoomScrollView.zoomScale > zoomScrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance
    }
    private var hasActiveZoomTransform: Bool {
        zoomScrollView.zoomScale != zoomScrollView.minimumZoomScale || zoomScrollView.isZooming
    }

    init(
        pagePosition: PlayerPagePosition,
        playerDataSource: HorizontalPlayerDataSource?
    ) {
        self.playerDataSource = playerDataSource
        self.pagePosition = pagePosition
        super.init(nibName: nil, bundle: nil)
        renderCurrentItem()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    isolated deinit {
        cancelVideoSizeLoad()
        cancelLocalMediaMetadataTasks()
        cancelProvisionalAnimatedMediaImageLoadIfNeeded()
        removeDownloadableMediaCacheObserver()
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

    func setPlaybackActive(_ active: Bool, renderIfNeeded: Bool = true) {
        guard isPlaybackActive != active else {
            if active, renderIfNeeded {
                renderCurrentItem()
            }
            return
        }
        isPlaybackActive = active
        if active {
            if renderIfNeeded {
                renderCurrentItem()
            }
        } else {
            cleanupDisplayedContent()
        }
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
        resetZoom(animated: false)
        setZoomContentLayout(.viewport)
        clearAnimatedRenderContext()
        mediaRenderer.clearContent()
        if let renderedPagePosition {
            playerDataSource?.didCleanupPagePosition(renderedPagePosition)
        }
        renderedPagePosition = nil
    }

    func update(pagePosition: PlayerPagePosition) {
        guard self.pagePosition != pagePosition else { return }
        cleanupDisplayedContent()
        self.pagePosition = pagePosition
    }

    func toggleZoom(at location: CGPoint, in coordinateView: UIView) {
        guard isViewLoaded else { return }
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

    func makeTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView? {
        guard isViewLoaded,
              view.window != nil else {
            return nil
        }

        view.layoutIfNeeded()
        let viewportContainmentTolerance = 1 / max(
            view.window?.screen.scale ?? 1,
            1
        )
        return makeTransitionSnapshot(
            snapshotting: mediaContentView,
            from: sourceFrame,
            in: coordinateView,
            containmentTolerance: 0
        ) ?? makeTransitionSnapshot(
            snapshotting: zoomScrollView,
            from: sourceFrame,
            in: coordinateView,
            containmentTolerance: viewportContainmentTolerance
        )
    }

    private func makeTransitionSnapshot(
        snapshotting sourceView: UIView,
        from sourceFrame: CGRect,
        in coordinateView: UIView,
        containmentTolerance: CGFloat
    ) -> UIView? {
        let requestedFrame = sourceView
            .convert(sourceFrame, from: coordinateView)
            .standardized
        let toleratedBounds = sourceView.bounds.insetBy(
            dx: -containmentTolerance,
            dy: -containmentTolerance
        )
        guard !requestedFrame.isNull,
              !requestedFrame.isInfinite,
              !requestedFrame.isEmpty,
              toleratedBounds.contains(requestedFrame) else {
            return nil
        }

        let snapshotFrame = requestedFrame.intersection(sourceView.bounds)
        guard !snapshotFrame.isNull,
              !snapshotFrame.isEmpty else {
            return nil
        }

        return sourceView.resizableSnapshotView(
            from: snapshotFrame,
            afterScreenUpdates: false,
            withCapInsets: .zero
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

    func resetZoom(animated: Bool) {
        guard isViewLoaded else { return }
        guard zoomScrollView.zoomScale != zoomScrollView.minimumZoomScale else {
            updateZoomContentFrame(resetOffset: true)
            updateZoomInteraction()
            return
        }

        zoomScrollView.setZoomScale(zoomScrollView.minimumZoomScale, animated: animated)
        if !animated {
            updateZoomContentFrame(resetOffset: true)
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
        preservingActiveZoomDuringMediaReplacement: Bool = false
    ) {
        if preservingActiveZoomDuringMediaReplacement,
           hasActiveZoomTransform {
            zoomContentLayout = layout
            zoomAllowedContent = allowedContent
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

    private func updateZoomContentFrame(resetOffset: Bool) {
        let viewportSize = zoomScrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let contentSize = zoomContentSize(fitting: viewportSize)
        if zoomScrollView.zoomScale <= zoomScrollView.minimumZoomScale + MobilePlayerGestureTuning.playerZoomResetTolerance {
            mediaContentView.transform = .identity
            mediaContentView.frame = CGRect(origin: .zero, size: contentSize)
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

        case .staticImage(let contentSize),
             .fittedWebContent(let contentSize):
            guard contentSize.width > 0, contentSize.height > 0 else { return viewportSize }

            return PlayerAspectFitLayout.size(for: contentSize, fitting: viewportSize)

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
        mediaContentView
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
        guard willOrDidAppear,
              isPlaybackActive else { return }

        guard playerDataSource?.canRenderPagePosition(pagePosition) == true else {
            cleanupDisplayedContent()
            playerDataSource?.clearDownloadableMediaWindow()
            return
        }
        if renderedPagePosition == pagePosition {
            return
        }
        beginRenderingPagePosition(pagePosition)

        guard let token = playerDataSource?.getToken(pagePosition: pagePosition) else {
            playerDataSource?.clearDownloadableMediaWindow()
            playerDataSource?.didRenderPagePosition(pagePosition)
            return
        }

        if let nativeRenderKind = token.nativeMetalCardRenderKind {
            playerDataSource?.clearDownloadableMediaWindow()
            renderNativeMetalCard(token, renderKind: nativeRenderKind)
        } else if token.media == nil {
            playerDataSource?.clearDownloadableMediaWindow()
            if TokenGenerator.isBundledWebGenerativeCollection(
                id: token.fullCollectionId
            ) {
                renderBundledGenerativeWebContent(token.html)
            } else {
                renderWebContent(token.html)
            }
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
            renderWebContent(token.html)
        }
        playerDataSource?.didRenderPagePosition(pagePosition)
    }

    fileprivate func reloadRenderedBundledGenerativeWebContentIfNeeded() {
        guard renderedPagePosition == pagePosition,
              willOrDidAppear,
              isPlaybackActive,
              let token = playerDataSource?.getToken(pagePosition: pagePosition),
              token.media == nil,
              token.nativeMetalCardRenderKind == nil,
              TokenGenerator.isBundledWebGenerativeCollection(
                id: token.fullCollectionId
              ) else {
            return
        }

        resetZoom(animated: false)
        clearAnimatedRenderContext()
        mediaRenderer.clearContent()
        renderBundledGenerativeWebContent(token.html)
    }

    fileprivate func refreshDownloadableMediaWindow() {
        guard willOrDidAppear,
              isPlaybackActive else { return }
        guard let token = playerDataSource?.getToken(pagePosition: pagePosition) else {
            playerDataSource?.clearDownloadableMediaWindow()
            return
        }
        guard token.media != nil else {
            playerDataSource?.clearDownloadableMediaWindow()
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

    fileprivate func replaceVisibleContentIfAvailable(
        targetPagePosition: PlayerPagePosition,
        preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    ) -> Bool {
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
        willOrDidAppear && isPlaybackActive && isViewLoaded && view.window != nil
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
        renderedPagePosition = pagePosition
    }

    private func standardThumbnailDescriptor(
        matching descriptor: DownloadableMediaDescriptor
    ) -> DownloadableMediaDescriptor? {
        let thumbnailDescriptor = MobileCollectionCatalog.collectionBrowseThumbnailDescriptor(
            for: descriptor
        )
        return thumbnailDescriptor == descriptor ? nil : thumbnailDescriptor
    }

    private func renderImage(_ descriptor: DownloadableMediaDescriptor, fallbackHTML: String) {
        let thumbnailDescriptor = standardThumbnailDescriptor(matching: descriptor)
        let provisionalImage = thumbnailDescriptor.flatMap {
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
            shouldAnimateLoadedImageReplacement: { [weak self] in
                guard let self else { return false }
                return !self.hasActiveZoomTransform
            },
            onDisplayedProvisionalImage: { [weak self] image in
                self?.setZoomContentLayout(.staticImage(image.size))
            },
            onLoadedImage: { [weak self] image in
                guard let self else { return }
                self.setZoomContentLayout(
                    .staticImage(image.size),
                    preservingActiveZoomDuringMediaReplacement: true
                )
            }
        )
    }

    private func renderWebContent(_ html: String) {
        clearAnimatedRenderContext()
        setZoomContentLayout(.viewport)
        renderAnimatedFallbackWebContent(html)
    }

    private func renderBundledGenerativeWebContent(_ html: String) {
        clearAnimatedRenderContext()
        if isViewLoaded {
            view.layoutIfNeeded()
        }
        setZoomContentLayout(bundledGenerativeWebContentLayout)
        mediaRenderer.renderWebContent(
            html,
            onBegin: { [weak self] in
                self?.mediaContentView.layoutIfNeeded()
            }
        )
    }

    private var bundledGenerativeWebContentLayout: ZoomContentLayout {
        guard playerDataSource?.currentBundledGenerativePresentationMode()
                == .thumbnailAspectFit,
              let thumbnailAspectRatio = playerDataSource?
                .bundledGenerativeThumbnailAspectRatio(for: pagePosition) else {
            return .viewport
        }

        return .fittedWebContent(thumbnailAspectRatio.size)
    }

    private func renderNativeMetalCard(_ token: GeneratedToken, renderKind: NativeMetalCardRenderKind) {
        clearAnimatedRenderContext()
        setZoomContentLayout(.viewport, allowedContent: .nativeMetalCard)
        let thumbnailDescriptor = playerDataSource?
            .downloadableMediaDescriptor(for: pagePosition)
            .flatMap(standardThumbnailDescriptor(matching:))
        let provisionalImage = thumbnailDescriptor.flatMap {
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

        mediaRenderer.renderNativeMetalCard(
            tokenId: token.id,
            renderKind: renderKind,
            provisionalImage: provisionalImage,
            loadProvisionalImage: loadProvisionalImage
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
        let thumbnailDescriptor = standardThumbnailDescriptor(matching: descriptor)
        let provisionalImage = thumbnailDescriptor.flatMap {
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
            loadImageSizeIfNeeded(at: localFileURL, context: context)
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
        let downloadedSourceURLString = imageCache
            .downloadedSourceURL(for: context.descriptor)
            .absoluteString
        displayProvisionalAnimatedMediaImageOrClearContent(for: context)
        pendingAnimatedImageURL = fileURL
        htmlDocumentRenderTask?.cancel()
        htmlDocumentRenderTask = Task { [weak self] in
            let renderedDocument = await DownloadableTokenHTML.renderDocument(
                at: fileURL,
                baseURL: downloadedSourceURLString,
                includesViewportSizeInDocument: false
            )
            guard let self,
                  !Task.isCancelled,
                  validateAnimatedLocalContentResult(
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
                setZoomContentLayout(
                    .staticImage(viewportSize),
                    preservingActiveZoomDuringMediaReplacement: true
                )
            } else {
                setZoomContentLayout(.viewport)
            }
            renderAnimatedLocalWebContent(
                renderedDocument.html,
                context: context,
                localContentVersion: localContentVersion,
                htmlDirectoryURL: imageCache.webViewHTMLDirectoryURL,
                readAccessURL: imageCache.webViewHTMLDirectoryURL
            )
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

    private func loadImageSizeIfNeeded(
        at fileURL: URL,
        context: AnimatedRenderContext
    ) {
        imageSizeTask?.cancel()
        imageSizeTask = Task { [weak self] in
            let size = await Self.imageSize(at: fileURL)
            guard let self,
                  !Task.isCancelled,
                  animatedRenderContext == context,
                  (pendingAnimatedImageURL == fileURL
                    || renderedAnimatedImageURL == fileURL) else {
                return
            }
            imageSizeTask = nil
            guard let size else { return }
            setZoomContentLayout(
                .staticImage(size),
                preservingActiveZoomDuringMediaReplacement: true
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

        let task = Task { [weak self, fileURL, request] in
            let size = await DownloadableMediaVideoLayout.displaySize(at: fileURL)
            guard !Task.isCancelled,
                  let self,
                  videoSizeLoad?.request == request else {
                return
            }

            videoSizeLoad = nil
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
            MainActor.assumeIsolated {
                self?.renderAvailableAnimatedLocalContent()
            }
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
    private var pendingNavigationRetryTask: Task<Void, Never>?
    private var configuredPagingPanGestures = Set<ObjectIdentifier>()
    private var didNotifyPaginationAttemptDuringCurrentPan = false
    private var didNotifyUnavailableNavigationDuringCurrentPan = false
    private var isPagingScrollEnabled = true
    private var isPlaybackActive = true
    private var isCurrentPageZoomed = false
    private var lastSettledPagePosition: PlayerPagePosition?
    private var zoomedPagingPanRestingOffsets = [ObjectIdentifier: CGFloat]()
    private var unlockedZoomedPagingPanGestures = Set<ObjectIdentifier>()
    private weak var playerDataSource: HorizontalPlayerDataSource?
    var onCurrentZoomStateChange: ((Bool) -> Void)?

    init(playerDataSource: HorizontalPlayerDataSource) {
        let initialPagePosition = PlayerPagePosition.initial
        self.playerDataSource = playerDataSource
        pageA = SpecificPageViewController(
            pagePosition: initialPagePosition,
            playerDataSource: playerDataSource
        )
        pageB = SpecificPageViewController(
            pagePosition: initialPagePosition.advanced(by: 1),
            playerDataSource: playerDataSource
        )
        pageC = SpecificPageViewController(
            pagePosition: initialPagePosition.advanced(by: -1),
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

    var isActive: Bool {
        isPlaybackActive
    }

    func setActive(_ active: Bool) {
        guard isPlaybackActive != active else { return }
        isPlaybackActive = active
        let currentPage = self.currentPage
        let pages: [SpecificPageViewController] = [pageA, pageB, pageC]
        pages.forEach { page in
            page.setPlaybackActive(
                active,
                renderIfNeeded: active && page === currentPage
            )
        }
        view.isUserInteractionEnabled = active
    }

    func reloadRenderedBundledGenerativeWebContent() {
        [pageA, pageB, pageC].forEach {
            $0.reloadRenderedBundledGenerativeWebContentIfNeeded()
        }
        updatePagingScrollEnabled()
    }

    @discardableResult
    func publishCurrentPagePosition(forceUpdate: Bool) -> Bool {
        guard isPlaybackActive,
              let currentPage,
              canRender(currentPage.pagePosition) else {
            return false
        }

        didDisplayRenderablePagePosition(
            currentPage.pagePosition,
            forceUpdate: forceUpdate
        )
        return true
    }

    func toggleZoom(at location: CGPoint, in coordinateView: UIView) {
        currentPage?.toggleZoom(at: location, in: coordinateView)
        updatePagingScrollEnabled()
    }

    func makeCurrentPageTransitionSnapshot(
        from sourceFrame: CGRect,
        in coordinateView: UIView
    ) -> UIView? {
        guard canStartNavigation else { return nil }
        return currentPage?.makeTransitionSnapshot(
            from: sourceFrame,
            in: coordinateView
        )
    }

    @discardableResult
    func setPagePosition(
        _ targetPagePosition: PlayerPagePosition,
        completion: @escaping () -> Void = {}
    ) -> Bool {
        reanchorCurrentPage(
            to: targetPagePosition,
            forceDisplayUpdate: true,
            completion: completion
        )
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
            let targetOffset = translation.x > 0 ? -1 : 1
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

    private func update(currentPagePosition: PlayerPagePosition) {
        guard let currentPage = viewControllers?.first as? SpecificPageViewController else { return }
        switch currentPage {
        case pageA:
            pageA.update(pagePosition: currentPagePosition)
            pageB.update(pagePosition: currentPagePosition.advanced(by: 1))
            pageC.update(pagePosition: currentPagePosition.advanced(by: -1))
        case pageB:
            pageA.update(pagePosition: currentPagePosition.advanced(by: -1))
            pageB.update(pagePosition: currentPagePosition)
            pageC.update(pagePosition: currentPagePosition.advanced(by: 1))
        case pageC:
            pageA.update(pagePosition: currentPagePosition.advanced(by: 1))
            pageB.update(pagePosition: currentPagePosition.advanced(by: -1))
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
        pageA.preferredPrefetchDirection = .forward
        pageB.preferredPrefetchDirection = .forward
        pageC.preferredPrefetchDirection = .forward

        update(currentPagePosition: pagePosition)
        if isPlaybackActive {
            currentPage.renderCurrentItem()
            didDisplayRenderablePagePosition(pagePosition, forceUpdate: forceDisplayUpdate)
        }
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
        pageA.update(pagePosition: pagePosition)
        pageB.update(pagePosition: pagePosition.advanced(by: 1))
        pageC.update(pagePosition: pagePosition.advanced(by: -1))

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
        for candidatePagePosition in [pagePosition.advanced(by: -1), pagePosition.advanced(by: 1)] {
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
        let targetPagePosition = sourcePage.pagePosition.advanced(by: offset)
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

        guard let targetOffset = direction.pageOffset else { return false }
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
        Task { @MainActor in
            await Task.yield()
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

        guard let targetOffset = direction.pageOffset else { return false }
        return canRender(currentPage.pagePosition.advanced(by: targetOffset))
    }

    private var canStartNavigation: Bool {
        !isPageTransitioning && transitionCoordinator == nil
    }

    private func performPendingNavigationIfNeeded() {
        guard let pendingNavigationDirection else { return }
        guard canStartNavigation else {
            guard pendingNavigationRetryTask == nil else { return }
            pendingNavigationRetryTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(30))
                } catch {
                    return
                }
                guard let self else { return }
                pendingNavigationRetryTask = nil
                performPendingNavigationIfNeeded()
            }
            return
        }
        pendingNavigationRetryTask?.cancel()
        pendingNavigationRetryTask = nil
        self.pendingNavigationDirection = nil
        navigate(pendingNavigationDirection)
    }

    private func canRender(_ pagePosition: PlayerPagePosition) -> Bool {
        playerDataSource?.canRenderPagePosition(pagePosition) ?? false
    }

}
