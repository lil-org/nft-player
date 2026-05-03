// ∅ 2026 lil org

import SwiftUI
import WebKit

class AutoReloadingWebView: WKWebView {
    
    private static var isResizeReloadEnabled = true
    
    private var lastLoadedHtmlString: String?
    private var needsLoadWhenVisible = false
    
    static var new: AutoReloadingWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.suppressesIncrementalRendering = true
        let wkWebView = AutoReloadingWebView(frame: .zero, configuration: webConfiguration)
        wkWebView.isOpaque = false
        wkWebView.backgroundColor = .black
        wkWebView.scrollView.backgroundColor = .black
        wkWebView.scrollView.contentInsetAdjustmentBehavior = .never
        wkWebView.scrollView.hideAutomaticScrollEdgeEffects()
        wkWebView.configuration.userContentController.addUserScript(WKUserScript(source: "document.addEventListener('contextmenu', function(e) { e.preventDefault(); }, false);", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        return wkWebView
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
