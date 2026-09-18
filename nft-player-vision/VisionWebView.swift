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
    let allowsDependencyDownloads: Bool

    init(htmlString: String, allowsDependencyDownloads: Bool = true) {
        self.content = .html(htmlString)
        self.onLocalLoadFailure = nil
        self.allowsDependencyDownloads = allowsDependencyDownloads
    }

    init(
        content: VisionWebContent,
        onLocalLoadFailure: (() -> Void)? = nil
    ) {
        self.content = content
        self.onLocalLoadFailure = onLocalLoadFailure
        self.allowsDependencyDownloads = true
    }

    func makeUIView(context: Context) -> VisionPlayerWebView {
        VisionPlayerWebView.make()
    }
    
    func updateUIView(_ uiView: VisionPlayerWebView, context: Context) {
        uiView.allowsDependencyDownloads = allowsDependencyDownloads
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

    var artworkDependencyCache: PersistentArtworkDependencyCache {
        get { dependencyLoadGate.cache }
        set { dependencyLoadGate.cache = newValue }
    }

    var allowsDependencyDownloads = true

    private let dependencyLoadGate = ArtworkContentResolver.makeLoadGate()
    private var requestedDependencyHTML: String?
    private var requestedDependencyBaseURL: URL?
    private var requestedDependencyAllowsDownloads = true
    private var dependencyStatusView: UIView?

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
        let allowsDownloads = allowsDependencyDownloads
        if requestedDependencyHTML == string,
           requestedDependencyBaseURL == baseURL,
           requestedDependencyAllowsDownloads == allowsDownloads {
            return nil
        }
        requestedDependencyHTML = string
        requestedDependencyBaseURL = baseURL
        requestedDependencyAllowsDownloads = allowsDownloads
        let handled = dependencyLoadGate.load(
            string,
            context: baseURL?.absoluteString ?? "",
            allowsDownloads: allowsDownloads,
            onStart: { [weak self] in
                self?.contentLoadCoordinator.unloadContent()
                if allowsDownloads {
                    self?.showDependencyStatus(failed: false)
                } else {
                    self?.showDependencyStatus(failed: false, isPreview: true)
                }
            },
            onReady: { [weak self] preparedHTML in
                guard let self else { return }
                self.clearDependencyStatus()
                self.contentLoadCoordinator.loadHTMLString(preparedHTML, baseURL: baseURL)
            },
            onFailure: { [weak self] _ in
                if allowsDownloads {
                    self?.showDependencyStatus(failed: true)
                } else {
                    self?.requestedDependencyHTML = nil
                    self?.showDependencyStatus(failed: false, isPreview: true)
                }
            }
        )
        guard !handled else { return nil }
        requestedDependencyHTML = nil
        requestedDependencyBaseURL = nil
        clearDependencyStatus()
        return contentLoadCoordinator.loadHTMLString(string, baseURL: baseURL)
    }

    @discardableResult func loadLocalHTMLString(
        _ string: String,
        htmlDirectoryURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        resetDependencyLoad()
        return contentLoadCoordinator.loadLocalHTMLString(
            string,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onFailure: onFailure
        )
    }

    func unloadContent() {
        resetDependencyLoad()
        contentLoadCoordinator.unloadContent()
    }

    override func stopLoading() {
        resetDependencyLoad()
        contentLoadCoordinator.prepareForStopLoading()
        super.stopLoading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        contentLoadCoordinator.didFinish(navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if contentLoadCoordinator.didFail(navigation, error: error) {
            requestedDependencyHTML = nil
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if contentLoadCoordinator.didFail(navigation, error: error) {
            requestedDependencyHTML = nil
        }
    }

    @objc private func retryDependencyLoad() {
        guard let html = requestedDependencyHTML else { return }
        let baseURL = requestedDependencyBaseURL
        requestedDependencyHTML = nil
        dependencyLoadGate.cancel()
        loadHTMLString(html, baseURL: baseURL)
    }

    private func resetDependencyLoad() {
        dependencyLoadGate.reset()
        requestedDependencyHTML = nil
        requestedDependencyBaseURL = nil
        clearDependencyStatus()
    }

    private func clearDependencyStatus() {
        dependencyStatusView?.removeFromSuperview()
        dependencyStatusView = nil
        isUserInteractionEnabled = false
    }

    private func showDependencyStatus(failed: Bool, isPreview: Bool = false) {
        clearDependencyStatus()
        isUserInteractionEnabled = failed
        let overlay = UIView(frame: bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .black
        if isPreview {
            addSubview(overlay)
            dependencyStatusView = overlay
            return
        }
        let label = UILabel()
        label.text = failed ? "The artwork could not load its required files." : "Loading artwork…"
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        if failed {
            let retry = UIButton(type: .system)
            retry.setTitle("Retry", for: .normal)
            retry.addTarget(self, action: #selector(retryDependencyLoad), for: .touchUpInside)
            stack.addArrangedSubview(retry)
        } else {
            let progress = UIActivityIndicatorView(style: .medium)
            progress.startAnimating()
            stack.addArrangedSubview(progress)
        }
        overlay.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, multiplier: 0.85)
        ])
        addSubview(overlay)
        dependencyStatusView = overlay
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
