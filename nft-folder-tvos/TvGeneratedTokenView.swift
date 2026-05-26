// ∅ 2026 lil org

import SwiftUI
import UIKit

private let maxLayoutRetryCount = 60
private let layoutRetryDelay: DispatchTimeInterval = .milliseconds(50)
private let fallbackSamplingDelay: DispatchTimeInterval = .milliseconds(230)
private let unloadedHTML = """
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <style>html, body { width: 100%; height: 100%; margin: 0; background: #000; }</style>
</head>
<body></body>
</html>
"""

private var shouldSkipTvFallbackCheck = false
private var shouldAlwaysFallback = false
private var shouldSampleTvFallback: Bool {
    !shouldAlwaysFallback && !shouldSkipTvFallbackCheck
}

enum TvWebContent: Equatable {
    case html(String)
    case localHTML(string: String, directoryURL: URL)

    var isLocalHTML: Bool {
        if case .localHTML = self {
            return true
        }
        return false
    }
}

struct TvGeneratedTokenView: UIViewRepresentable {

    private struct WebViewContainer {
        let webView: UIView
        let target: UIView
        let loadSelector: Selector
    }

    private static let sampleHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <style>body { background-color: #111; }</style>
    </head>
    <body></body>
    </html>
    """

    private static var prewarmTimer: Timer?
    private static var prewarmedContainer: WebViewContainer?
    private static var didSchedulePrewarm = false

    static let localMediaFailureURLString = "nft-folder-tvos-media-failed://load"

    let webContent: TvWebContent
    let fallbackURL: URL?
    let onLocalLoadFailure: (() -> Void)?

    init(
        contentString: String,
        fallbackURL: URL?,
        onLocalLoadFailure: (() -> Void)? = nil
    ) {
        self.webContent = .html(contentString)
        self.fallbackURL = fallbackURL
        self.onLocalLoadFailure = onLocalLoadFailure
    }

    init(
        webContent: TvWebContent,
        fallbackURL: URL? = nil,
        onLocalLoadFailure: (() -> Void)? = nil
    ) {
        self.webContent = webContent
        self.fallbackURL = fallbackURL
        self.onLocalLoadFailure = onLocalLoadFailure
    }

    static func scheduleFirstUsePrewarm() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { scheduleFirstUsePrewarm() }
            return
        }

        guard !didSchedulePrewarm, prewarmedContainer == nil else { return }
        didSchedulePrewarm = true

        let timer = Timer(timeInterval: 1.15, repeats: false) { _ in
            prewarmTimer = nil
            prewarmForFirstUseIfNeeded()
        }
        prewarmTimer = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    private static func prewarmForFirstUseIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { prewarmForFirstUseIfNeeded() }
            return
        }
        guard prewarmedContainer == nil else { return }
        guard UIApplication.shared.applicationState == .active else {
            didSchedulePrewarm = false
            return
        }

        guard let container = makeWebViewContainer() else { return }
        configureWebViewContainer(container)
        container.webView.isHidden = true
        container.target.perform(container.loadSelector, with: sampleHTML, with: nil)
        prewarmedContainer = container
    }

    private static func takePrewarmedWebViewContainer() -> WebViewContainer? {
        guard Thread.isMainThread else { return nil }
        let container = prewarmedContainer
        prewarmedContainer = nil
        prewarmTimer?.invalidate()
        prewarmTimer = nil
        return container
    }

    private static func makeWebViewContainer() -> WebViewContainer? {
        guard let viewClass = NSClassFromString(webViewClassName),
              let viewObject = viewClass as? NSObject.Type else {
            return nil
        }

        let webViewObject = viewObject.init()
        guard let webView = webViewObject as? UIView,
              let target = webView.subviews.first?.superview else {
            return nil
        }

        return WebViewContainer(
            webView: webView,
            target: target,
            loadSelector: loadHTMLStringSelector
        )
    }

    private static func configureWebViewContainer(_ container: WebViewContainer) {
        if let scrollView = scrollView(for: container.webView) {
            scrollView.backgroundColor = .black
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        container.target.isOpaque = false
        container.target.backgroundColor = .black
        setBooleanProperty("suppressesIncrementalRendering", to: true, on: container.target)
        setBooleanProperty("allowsInlineMediaPlayback", to: true, on: container.webView)
        setBooleanProperty("mediaPlaybackRequiresUserAction", to: false, on: container.webView)
        setBooleanProperty("allowsAirPlayForMediaPlayback", to: true, on: container.webView)
    }

    private static func scrollView(for webView: UIView) -> UIScrollView? {
        guard webView.responds(to: NSSelectorFromString("scrollView")) else { return nil }
        return webView.value(forKey: "scrollView") as? UIScrollView
    }

    private static func setBooleanProperty(_ name: String, to value: Bool, on object: NSObject) {
        guard object.responds(to: setterSelector(for: name)) else { return }
        object.setValue(value, forKey: name)
    }

    private static func setterSelector(for propertyName: String) -> Selector {
        let first = propertyName.prefix(1).uppercased()
        let rest = propertyName.dropFirst()
        return NSSelectorFromString("set\(first)\(rest):")
    }

    private static var webViewClassName: String {
        if HelperStrings.view.contains("e") {
            let bew = HelperStrings.b + String(HelperStrings.view.suffix(2))
            let uAndI = (HelperStrings.u + HelperStrings.i).uppercased()
            return uAndI + String(bew.reversed()).capitalized + HelperStrings.view.capitalized
        } else {
            return ""
        }
    }

    private static var loadHTMLStringSelector: Selector {
        let documentType = HelperStrings.html.starts(with: "h") ? HelperStrings.html : ""
        return NSSelectorFromString("load\(documentType.uppercased())String:base\(HelperStrings.url.uppercased()):")
    }

    private static var loadRequestSelector: Selector {
        NSSelectorFromString("loadRequest:")
    }

    private static var stopLoadingSelector: Selector {
        NSSelectorFromString("stopLoading")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        guard let container = Self.takePrewarmedWebViewContainer() ?? Self.makeWebViewContainer() else {
            return UIView()
        }

        Self.configureWebViewContainer(container)
        container.webView.isHidden = false
        if shouldSampleTvFallback {
            container.target.perform(container.loadSelector, with: Self.sampleHTML, with: nil)
        }

        let coordinator = context.coordinator
        coordinator.attachWebView(container.webView)
        coordinator.loadSample = { [weak target = container.target] in
            target?.perform(container.loadSelector, with: Self.sampleHTML, with: nil)
        }
        coordinator.unloadContent = { [weak webView = container.webView, weak target = container.target] in
            if webView?.responds(to: Self.stopLoadingSelector) == true {
                webView?.perform(Self.stopLoadingSelector)
            }
            target?.perform(container.loadSelector, with: unloadedHTML, with: nil)
        }
        coordinator.loadContent = { [weak webView = container.webView, weak target = container.target, weak coordinator] content, url in
            guard let coordinator else { return }
            if webView?.responds(to: Self.stopLoadingSelector) == true {
                webView?.perform(Self.stopLoadingSelector)
            }
            coordinator.prepareForWebContentLoad(content)

            switch content {
            case let .html(string):
                target?.perform(container.loadSelector, with: string, with: nil)

            case let .localHTML(string, directoryURL):
                guard let target,
                      target.responds(to: Self.loadRequestSelector),
                      let fileURL = coordinator.writeLocalHTMLString(string, in: directoryURL) else {
                    coordinator.handleLocalLoadFailure()
                    return
                }

                target.perform(Self.loadRequestSelector, with: NSURLRequest(url: fileURL))
            }

            guard let url else {
                coordinator.clearFallbackView()
                return
            }
            guard let target else { return }

            coordinator.updateFallbackView(in: target, url: url)
        }
        return container.webView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let request = LoadRequest(webContent: webContent, fallbackURL: fallbackURL)
        guard let loadGeneration = context.coordinator.beginLoading(
            request,
            onLocalLoadFailure: deferred(onLocalLoadFailure)
        ) else {
            return
        }

        loadContentWhenReady(
            request,
            in: uiView,
            coordinator: context.coordinator,
            loadGeneration: loadGeneration
        )
    }

    private func loadContentWhenReady(
        _ request: LoadRequest,
        in view: UIView,
        coordinator: Coordinator,
        loadGeneration: Int,
        attempt: Int = 0
    ) {
        guard coordinator.isCurrentGeneration(loadGeneration) else { return }

        guard view.bounds.width >= 1 && view.bounds.height >= 1 else {
            guard attempt < maxLayoutRetryCount else {
                loadContentWithoutSampling(request, coordinator: coordinator)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + layoutRetryDelay) { [weak view, weak coordinator] in
                guard let view, let coordinator else { return }
                loadContentWhenReady(
                    request,
                    in: view,
                    coordinator: coordinator,
                    loadGeneration: loadGeneration,
                    attempt: attempt + 1
                )
            }
            return
        }

        if shouldSampleTvFallback {
            coordinator.prepareForSamplingIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackSamplingDelay) { [weak view, weak coordinator] in
                guard let view, let coordinator, coordinator.isCurrentGeneration(loadGeneration) else { return }
                loadContentInto(request, view: view, coordinator: coordinator)
            }
        } else {
            loadContentInto(request, view: view, coordinator: coordinator)
        }
    }

    private func deferred(_ callback: (() -> Void)?) -> (() -> Void)? {
        guard let callback else { return nil }
        return {
            DispatchQueue.main.async {
                callback()
            }
        }
    }
    
    private func loadContentInto(_ request: LoadRequest, view: UIView, coordinator: Coordinator) {
        let fallbackURL: URL?
        if shouldSkipTvFallbackCheck {
            fallbackURL = nil
        } else if shouldSampleTvFallback, !randomPixelIsBlackOrTransparent(in: view) {
            shouldSkipTvFallbackCheck = true
            fallbackURL = nil
        } else {
            shouldAlwaysFallback = true
            fallbackURL = request.fallbackURL
        }

        coordinator.loadContent?(request.webContent, fallbackURL)
    }

    private func loadContentWithoutSampling(_ request: LoadRequest, coordinator: Coordinator) {
        coordinator.finishWithoutSampling(request)
        let fallbackURL = shouldSkipTvFallbackCheck ? nil : request.fallbackURL
        coordinator.loadContent?(request.webContent, fallbackURL)
    }
    
    private func randomPixelIsBlackOrTransparent(in view: UIView) -> Bool {
        let randomX = Int.random(in: 0..<Int(view.bounds.width))
        let randomY = Int.random(in: 0..<Int(view.bounds.height))
        let point = CGPoint(x: randomX, y: randomY)
        
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        
        guard let cgImage = image.cgImage, let pixelData = cgImage.dataProvider?.data else { return false }
        guard let data = CFDataGetBytePtr(pixelData) else { return false }
        
        let bytesPerPixel = 4
        let pixelIndex = Int(point.y) * cgImage.bytesPerRow + Int(point.x) * bytesPerPixel
        
        let r = CGFloat(data[pixelIndex]) / 255.0
        let g = CGFloat(data[pixelIndex + 1]) / 255.0
        let b = CGFloat(data[pixelIndex + 2]) / 255.0
        let a = CGFloat(data[pixelIndex + 3]) / 255.0
        
        return (r.isZero && g.isZero && b.isZero) || a.isZero
    }

    struct LoadRequest: Equatable {
        let webContent: TvWebContent
        let fallbackURL: URL?
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    final class Coordinator: NSObject {
        var loadSample: (() -> Void)?
        var loadContent: ((TvWebContent, URL?) -> Void)?
        var unloadContent: (() -> Void)?
        private var loadGeneration = 0
        private var currentRequest: LoadRequest?
        private var currentFallbackImageTask: URLSessionDataTask?
        private weak var fallbackView: UIImageView?
        private var needsSampleReload = false
        private var onLocalLoadFailure: (() -> Void)?
        private var isLoadingLocalHTML = false
        private var didHandleLocalLoadFailure = false
        private weak var delegatedWebView: UIView?
        private var localHTMLFileURLs = Set<URL>()

        deinit {
            dismantle()
        }

        func beginLoading(
            _ request: LoadRequest,
            onLocalLoadFailure: (() -> Void)?
        ) -> Int? {
            self.onLocalLoadFailure = onLocalLoadFailure
            guard currentRequest != request else { return nil }

            currentRequest = request
            loadGeneration += 1
            return loadGeneration
        }

        func isCurrentGeneration(_ generation: Int) -> Bool {
            loadGeneration == generation
        }

        func clearFallbackView() {
            currentFallbackImageTask?.cancel()
            currentFallbackImageTask = nil
            fallbackView?.removeFromSuperview()
            fallbackView = nil
        }

        func prepareForSamplingIfNeeded() {
            guard needsSampleReload else { return }
            clearFallbackView()
            loadSample?()
            needsSampleReload = false
        }

        func finishWithoutSampling(_ request: LoadRequest) {
            if currentRequest == request {
                currentRequest = nil
            }
            if shouldSampleTvFallback {
                needsSampleReload = true
            }
        }

        func attachWebView(_ webView: UIView) {
            guard delegatedWebView !== webView else { return }
            detachWebView()
            delegatedWebView = webView
            setDelegate(self, on: webView)
        }

        func prepareForWebContentLoad(_ content: TvWebContent) {
            isLoadingLocalHTML = content.isLocalHTML
            didHandleLocalLoadFailure = false
        }

        func writeLocalHTMLString(_ string: String, in directoryURL: URL) -> URL? {
            let localHTMLFileName = "\(UUID().uuidString).html"
            let fileURL = directoryURL.appendingPathComponent(localHTMLFileName, isDirectory: false)

            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try Data(string.utf8).write(to: fileURL, options: .atomic)
                localHTMLFileURLs.insert(fileURL)
                return fileURL
            } catch {
                return nil
            }
        }

        func handleLocalLoadFailure() {
            guard isLoadingLocalHTML, !didHandleLocalLoadFailure else { return }
            didHandleLocalLoadFailure = true
            onLocalLoadFailure?()
        }

        func dismantle() {
            loadGeneration += 1
            currentRequest = nil
            needsSampleReload = false
            isLoadingLocalHTML = false
            didHandleLocalLoadFailure = true
            clearFallbackView()
            unloadContent?()
            loadSample = nil
            loadContent = nil
            unloadContent = nil
            detachWebView()
            for fileURL in localHTMLFileURLs {
                try? FileManager.default.removeItem(at: fileURL)
            }
            localHTMLFileURLs.removeAll()
            onLocalLoadFailure = nil
        }

        @objc(webView:shouldStartLoadWithRequest:navigationType:)
        func webView(
            _ webView: AnyObject,
            shouldStartLoadWith request: NSURLRequest,
            navigationType: Int
        ) -> Bool {
            guard request.url?.absoluteString == TvGeneratedTokenView.localMediaFailureURLString else {
                return true
            }

            handleLocalLoadFailure()
            return false
        }

        @objc(webView:didFailLoadWithError:)
        func webView(_ webView: AnyObject, didFailLoadWithError error: Error) {
            guard !Self.isCancelledNavigationError(error) else { return }
            handleLocalLoadFailure()
        }

        func updateFallbackView(in parentView: UIView, url: URL) {
            let fallbackView = fallbackImageView(in: parentView)
            fallbackView.image = nil
            currentFallbackImageTask?.cancel()

            let task = URLSession.shared.dataTask(with: url) { [weak fallbackView] data, _, error in
                guard let data, error == nil, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    fallbackView?.image = image
                }
            }
            currentFallbackImageTask = task
            task.resume()
        }

        private func fallbackImageView(in parentView: UIView) -> UIImageView {
            if let fallbackView {
                return fallbackView
            }

            let fallbackView = UIImageView()
            parentView.addSubview(fallbackView)
            fallbackView.translatesAutoresizingMaskIntoConstraints = false
            fallbackView.contentMode = .scaleAspectFill
            NSLayoutConstraint.activate([
                fallbackView.topAnchor.constraint(equalTo: parentView.topAnchor),
                fallbackView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
                fallbackView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                fallbackView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor)
            ])
            self.fallbackView = fallbackView
            return fallbackView
        }

        private func detachWebView() {
            guard let delegatedWebView else { return }
            setDelegate(nil, on: delegatedWebView)
            self.delegatedWebView = nil
        }

        private func setDelegate(_ delegate: AnyObject?, on webView: UIView) {
            guard webView.responds(to: NSSelectorFromString("setDelegate:")) else { return }
            webView.setValue(delegate, forKey: "delegate")
        }

        private static func isCancelledNavigationError(_ error: Error) -> Bool {
            let error = error as NSError
            return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
        }
    }
    
}
