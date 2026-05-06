// ∅ 2026 lil org

import UIKit
import WebKit

class AutoReloadingWebView: WKWebView {

    private static var isResizeReloadEnabled = true
    private static var prewarmTimer: Timer?
    private static var prewarmedWebView: AutoReloadingWebView?
    private static var didSchedulePrewarm = false

    private var lastLoadedHtmlString: String?
    private var needsLoadWhenVisible = false

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
        isOpaque = false
        backgroundColor = .black
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.hideAutomaticScrollEdgeEffects()
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
        let newHtmlContent = lastLoadedHtmlString != string
        
        if newHtmlContent {
            lastLoadedHtmlString = string
        }

        if !hasVisibleSize {
            needsLoadWhenVisible = true
            stopLoading()
            return nil
        }
        
        guard newHtmlContent || needsLoadWhenVisible else { return nil }
        needsLoadWhenVisible = false
        return super.loadHTMLString(string, baseURL: baseURL)
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
        guard needsLoadWhenVisible, let html = lastLoadedHtmlString else { return }
        loadHTMLString(html, baseURL: nil)
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
