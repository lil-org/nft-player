// ∅ 2026 lil org

import SwiftUI
import WebKit

enum VisionWebContent {
    case html(String)
    case localHTML(string: String, htmlDirectoryURL: URL, readAccessURL: URL)
}

struct VisionWebView: UIViewRepresentable {
    let content: VisionWebContent
    let onLocalLoadFailure: (() -> Void)?

    init(htmlString: String) {
        self.content = .html(htmlString)
        self.onLocalLoadFailure = nil
    }

    init(
        content: VisionWebContent,
        onLocalLoadFailure: (() -> Void)? = nil
    ) {
        self.content = content
        self.onLocalLoadFailure = onLocalLoadFailure
    }

    func makeUIView(context: Context) -> VisionPlayerWebView {
        VisionPlayerWebView.make()
    }
    
    func updateUIView(_ uiView: VisionPlayerWebView, context: Context) {
        uiView.load(
            content,
            onLocalLoadFailure: deferred(onLocalLoadFailure)
        )
    }

    static func dismantleUIView(_ uiView: VisionPlayerWebView, coordinator: ()) {
        uiView.unloadContent()
    }

    private func deferred(_ callback: (() -> Void)?) -> (() -> Void)? {
        guard let callback else { return nil }
        return {
            Task { @MainActor in callback() }
        }
    }
}

final class VisionPlayerWebView: WKWebView, WKNavigationDelegate {

    private static var prewarmTask: Task<Void, Never>?
    private static var prewarmedWebView: VisionPlayerWebView?
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

    static func make() -> VisionPlayerWebView {
        let webView = takePrewarmedWebView()
            ?? VisionPlayerWebView(frame: .zero, configuration: webConfiguration())
        webView.frame = .zero
        webView.isHidden = false
        webView.applyPlayerDefaults()
        return webView
    }

    static func scheduleFirstUsePrewarm() {
        guard !didSchedulePrewarm, prewarmedWebView == nil else { return }
        didSchedulePrewarm = true

        prewarmTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.15))
                try Task.checkCancellation()
            } catch {
                return
            }
            prewarmTask = nil
            prewarmForFirstUseIfNeeded()
        }
    }

    private static func prewarmForFirstUseIfNeeded() {
        guard prewarmedWebView == nil else { return }
        guard UIApplication.shared.applicationState == .active else {
            didSchedulePrewarm = false
            return
        }

        let webView = VisionPlayerWebView(
            frame: CGRect(x: 0, y: 0, width: 8, height: 8),
            configuration: webConfiguration()
        )
        webView.isHidden = true
        webView.applyPlayerDefaults()
        webView.loadHTMLString("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>", baseURL: nil)
        prewarmedWebView = webView
    }

    private static func takePrewarmedWebView() -> VisionPlayerWebView? {
        guard Thread.isMainThread else { return nil }
        let webView = prewarmedWebView
        prewarmedWebView = nil
        prewarmTask?.cancel()
        prewarmTask = nil
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
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .black
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
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

    func load(
        _ content: VisionWebContent,
        onLocalLoadFailure: (() -> Void)? = nil
    ) {
        switch content {
        case let .html(htmlString):
            loadHTMLString(htmlString, baseURL: nil)
        case let .localHTML(htmlString, htmlDirectoryURL, readAccessURL):
            loadLocalHTMLString(
                htmlString,
                htmlDirectoryURL: htmlDirectoryURL,
                allowingReadAccessTo: readAccessURL,
                onFailure: onLocalLoadFailure
            )
        }
    }

    @discardableResult override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        contentLoadCoordinator.loadHTMLString(string, baseURL: baseURL)
    }

    @discardableResult func loadLocalHTMLString(
        _ string: String,
        htmlDirectoryURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        contentLoadCoordinator.loadLocalHTMLString(
            string,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onFailure: onFailure
        )
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
        hasVisibleSize(bounds)
    }

    private func loadPendingContentIfNeeded(oldRect: CGRect) {
        contentLoadCoordinator.loadPendingContentIfNeeded(
            wasVisible: hasVisibleSize(oldRect),
            isVisible: hasVisibleSize
        )
    }

    private func hasVisibleSize(_ rect: CGRect) -> Bool {
        rect.size.width > 5 && rect.size.height > 5
    }
}
