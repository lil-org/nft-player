// ∅ 2026 lil org

import UIKit
import WebKit

class AutoReloadingWebView: WKWebView, WKNavigationDelegate {

    private enum WebContentLoad: Equatable {
        case html(string: String, baseURL: URL?)
        case localHTML(string: String, htmlDirectoryURL: URL, readAccessURL: URL)

        var requiresSuccessfulNavigation: Bool {
            switch self {
            case .html:
                return false
            case .localHTML:
                return true
            }
        }
    }

    private static var isResizeReloadEnabled = true
    private static var prewarmTimer: Timer?
    private static var prewarmedWebView: AutoReloadingWebView?
    private static var didSchedulePrewarm = false

    private var lastRequestedLoad: WebContentLoad?
    private var needsLoadWhenVisible = false
    private var pendingLoadSuccessHandler: (() -> Void)?
    private var pendingLoadFailureHandler: (() -> Void)?
    private var activeNavigation: WKNavigation?
    private var activeNavigationContent: WebContentLoad?
    private var activeNavigationSuccessHandler: (() -> Void)?
    private var activeNavigationFailureHandler: (() -> Void)?
    private var successfullyLoadedContent: WebContentLoad?
    private let localHTMLFileName = "\(UUID().uuidString).html"
    private var localHTMLFileURL: URL?

    static var new: AutoReloadingWebView {
        let wkWebView = takePrewarmedWebView() ?? AutoReloadingWebView(frame: .zero, configuration: webConfiguration())
        wkWebView.frame = .zero
        wkWebView.applyPlayerDefaults()
        wkWebView.isHidden = false
        return wkWebView
    }

    deinit {
        if let localHTMLFileURL {
            try? FileManager.default.removeItem(at: localHTMLFileURL)
        }
    }

    static func scheduleFirstUsePrewarm() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { scheduleFirstUsePrewarm() }
            return
        }

        guard !didSchedulePrewarm, prewarmedWebView == nil else { return }
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
        guard prewarmedWebView == nil else { return }
        guard UIApplication.shared.applicationState == .active else {
            didSchedulePrewarm = false
            return
        }

        let webView = AutoReloadingWebView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), configuration: webConfiguration())
        webView.isHidden = true
        webView.isUserInteractionEnabled = false
        webView.applyPlayerDefaults()
        webView.loadHTMLString("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>", baseURL: nil)
        prewarmedWebView = webView
    }

    private static func takePrewarmedWebView() -> AutoReloadingWebView? {
        guard Thread.isMainThread else { return nil }
        let webView = prewarmedWebView
        prewarmedWebView = nil
        prewarmTimer?.invalidate()
        prewarmTimer = nil
        return webView
    }

    private static func webConfiguration() -> WKWebViewConfiguration {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.suppressesIncrementalRendering = true
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webConfiguration.userContentController.addUserScript(
            WKUserScript(
                source: "document.addEventListener('contextmenu', function(e) { e.preventDefault(); }, false);",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        return webConfiguration
    }

    private func applyPlayerDefaults() {
        navigationDelegate = self
        isOpaque = false
        backgroundColor = .black
        underPageBackgroundColor = .black
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.hideAutomaticScrollEdgeEffects()
    }

    func makePlayerBackgroundTransparent() {
        makeBackgroundTransparent()
        underPageBackgroundColor = .clear
        scrollView.makeBackgroundTransparent()
    }
    
    override var bounds: CGRect {
        didSet {
            loadPendingContentIfNeeded(oldRect: oldValue)
        }
    }
    
    override var frame: CGRect {
        didSet {
            loadPendingContentIfNeeded(oldRect: oldValue)
        }
    }
    
    @discardableResult override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        return loadWebContent(.html(string: string, baseURL: baseURL))
    }

    @discardableResult func loadLocalHTMLString(
        _ string: String,
        htmlDirectoryURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        return loadWebContent(
            .localHTML(string: string, htmlDirectoryURL: htmlDirectoryURL, readAccessURL: readAccessURL),
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    func invalidateRequestedContent() {
        stopLoading()
        clearRequestedContentState()
    }

    func unloadContent() {
        stopLoading()
        _ = super.loadHTMLString("", baseURL: nil)
        clearRequestedContentState()
    }

    private func clearRequestedContentState() {
        lastRequestedLoad = nil
        pendingLoadSuccessHandler = nil
        pendingLoadFailureHandler = nil
        needsLoadWhenVisible = false
        successfullyLoadedContent = nil
    }

    private func loadWebContent(
        _ content: WebContentLoad,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        let newContent = lastRequestedLoad != content

        if !hasVisibleSize {
            if newContent {
                lastRequestedLoad = content
            }
            pendingLoadSuccessHandler = onSuccess
            pendingLoadFailureHandler = onFailure
            needsLoadWhenVisible = true
            stopLoading()
            return nil
        }

        if !newContent && !needsLoadWhenVisible {
            if handleDuplicateLoadRequest(
                content,
                onSuccess: onSuccess,
                onFailure: onFailure
            ) {
                return nil
            }
        }

        clearActiveNavigationCallbacks()
        if newContent {
            successfullyLoadedContent = nil
        }
        let navigation = performLoad(content)
        if navigation == nil, content.requiresSuccessfulNavigation {
            pendingLoadSuccessHandler = nil
            pendingLoadFailureHandler = nil
            needsLoadWhenVisible = false
            onFailure?()
            return nil
        }

        if let navigation {
            activeNavigation = navigation
            activeNavigationContent = content
            activeNavigationSuccessHandler = content.requiresSuccessfulNavigation ? onSuccess : nil
            activeNavigationFailureHandler = content.requiresSuccessfulNavigation ? onFailure : nil
        }
        lastRequestedLoad = content
        pendingLoadSuccessHandler = nil
        pendingLoadFailureHandler = nil
        needsLoadWhenVisible = false
        return navigation
    }

    override func stopLoading() {
        clearActiveNavigationCallbacks()
        super.stopLoading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }

        let content = activeNavigationContent
        let successHandler = activeNavigationSuccessHandler
        clearActiveNavigationCallbacks()
        if content?.requiresSuccessfulNavigation == true {
            successfullyLoadedContent = content
        }
        successHandler?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishActiveNavigationWithFailure(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishActiveNavigationWithFailure(navigation, error: error)
    }

    private func finishActiveNavigationWithFailure(_ navigation: WKNavigation?, error: Error) {
        guard let navigation, navigation === activeNavigation else { return }
        guard !Self.isCancelledNavigationError(error) else {
            clearActiveNavigationCallbacks()
            return
        }

        let failureHandler = activeNavigationFailureHandler
        clearActiveNavigationCallbacks()
        clearRequestedContentState()
        failureHandler?()
    }

    private static func isCancelledNavigationError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    private func clearActiveNavigationCallbacks() {
        activeNavigation = nil
        activeNavigationContent = nil
        activeNavigationSuccessHandler = nil
        activeNavigationFailureHandler = nil
    }

    private func handleDuplicateLoadRequest(
        _ content: WebContentLoad,
        onSuccess: (() -> Void)?,
        onFailure: (() -> Void)?
    ) -> Bool {
        guard content.requiresSuccessfulNavigation else { return true }

        if successfullyLoadedContent == content {
            DispatchQueue.main.async {
                onSuccess?()
            }
            return true
        }

        guard activeNavigationContent == content else { return false }
        activeNavigationSuccessHandler = combined(
            activeNavigationSuccessHandler,
            onSuccess
        )
        activeNavigationFailureHandler = combined(
            activeNavigationFailureHandler,
            onFailure
        )
        return true
    }

    private func combined(_ first: (() -> Void)?, _ second: (() -> Void)?) -> (() -> Void)? {
        guard first != nil || second != nil else { return nil }
        return {
            first?()
            second?()
        }
    }

    private func performLoad(_ content: WebContentLoad) -> WKNavigation? {
        switch content {
        case let .html(string, baseURL):
            return super.loadHTMLString(string, baseURL: baseURL)

        case let .localHTML(string, htmlDirectoryURL, readAccessURL):
            guard let localHTMLFileURL = writeLocalHTMLString(string, in: htmlDirectoryURL) else {
                return nil
            }
            return super.loadFileURL(localHTMLFileURL, allowingReadAccessTo: readAccessURL)
        }
    }

    private func writeLocalHTMLString(_ string: String, in directoryURL: URL) -> URL? {
        let data = Data(string.utf8)
        let fileURL = directoryURL.appendingPathComponent(localHTMLFileName, isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: fileURL, options: .atomic)
            if let localHTMLFileURL, localHTMLFileURL != fileURL {
                try? FileManager.default.removeItem(at: localHTMLFileURL)
            }
            localHTMLFileURL = fileURL
            return fileURL
        } catch {
            return nil
        }
    }
    
    private var hasVisibleSize: Bool {
        return bounds.size.width > 5 && bounds.size.height > 5
    }
    
    static func setResizeReloadEnabled(_ isEnabled: Bool) {
        isResizeReloadEnabled = isEnabled
    }
    
    private func loadPendingContentIfNeeded(oldRect: CGRect) {
        guard Self.isResizeReloadEnabled else { return }
        guard !hasVisibleSize(oldRect), hasVisibleSize else { return }
        guard needsLoadWhenVisible, let lastRequestedLoad else { return }
        _ = loadWebContent(
            lastRequestedLoad,
            onSuccess: pendingLoadSuccessHandler,
            onFailure: pendingLoadFailureHandler
        )
    }
    
    private func hasVisibleSize(_ rect: CGRect) -> Bool {
        return rect.size.width > 5 && rect.size.height > 5
    }
    
}

extension UIScrollView {
    
    func hideAutomaticScrollEdgeEffects() {
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = true
            bottomEdgeEffect.isHidden = true
            leftEdgeEffect.isHidden = true
            rightEdgeEffect.isHidden = true
        }
    }
    
}
