// ∅ 2026 lil org

import UIKit
import WebKit

class AutoReloadingWebView: WKWebView, WKNavigationDelegate {

    private static var isResizeReloadEnabled = true
    private static var prewarmTimer: Timer?
    private static var prewarmedWebView: AutoReloadingWebView?
    private static var didSchedulePrewarm = false

    private lazy var contentLoadCoordinator = PlayerWebContentLoadCoordinator(
        hasVisibleSize: { [weak self] in self?.hasVisibleSize == true },
        stopLoading: { [weak self] in self?.performSuperStopLoading() },
        loadHTMLString: { [weak self] string, baseURL in
            self?.performSuperLoadHTMLString(string, baseURL: baseURL)
        },
        loadFileURL: { [weak self] fileURL, readAccessURL in
            self?.performSuperLoadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        }
    )

    static var new: AutoReloadingWebView {
        let wkWebView = takePrewarmedWebView() ?? AutoReloadingWebView(frame: .zero, configuration: webConfiguration())
        wkWebView.frame = .zero
        wkWebView.applyPlayerDefaults()
        wkWebView.isHidden = false
        return wkWebView
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
        return contentLoadCoordinator.loadHTMLString(string, baseURL: baseURL)
    }

    @discardableResult func loadLocalHTMLString(
        _ string: String,
        htmlDirectoryURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        return contentLoadCoordinator.loadLocalHTMLString(
            string,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    func invalidateRequestedContent() {
        contentLoadCoordinator.invalidateRequestedContent()
    }

    func unloadContent() {
        contentLoadCoordinator.unloadContent()
    }

    override func stopLoading() {
        contentLoadCoordinator.prepareForStopLoading()
        super.stopLoading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        contentLoadCoordinator.didFinish(navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        contentLoadCoordinator.didFail(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        contentLoadCoordinator.didFail(navigation, error: error)
    }

    private func performSuperLoadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        super.loadHTMLString(string, baseURL: baseURL)
    }

    private func performSuperLoadFileURL(_ fileURL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        super.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
    }

    private func performSuperStopLoading() {
        super.stopLoading()
    }
    
    private var hasVisibleSize: Bool {
        return bounds.size.width > 5 && bounds.size.height > 5
    }
    
    static func setResizeReloadEnabled(_ isEnabled: Bool) {
        isResizeReloadEnabled = isEnabled
    }
    
    private func loadPendingContentIfNeeded(oldRect: CGRect) {
        guard Self.isResizeReloadEnabled else { return }
        contentLoadCoordinator.loadPendingContentIfNeeded(
            wasVisible: hasVisibleSize(oldRect),
            isVisible: hasVisibleSize
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
