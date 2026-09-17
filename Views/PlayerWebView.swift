// ∅ 2026 lil org

import AppKit
import WebKit

final class PlayerWebView: WebViewWithMenu, WKNavigationDelegate {

    private static var prewarmTimer: Timer?
    private static var prewarmedWebView: PlayerWebView?
    private static var didSchedulePrewarm = false

    var passesPlayerGesturesThrough = false {
        didSet {
            updateLockedCursorTrackingArea()
            invalidateCursorRects()
        }
    }

    private var lockedCursorTrackingArea: NSTrackingArea?

    var artworkDependencyCache: PersistentArtworkDependencyCache {
        get { dependencyLoadGate.cache }
        set { dependencyLoadGate.cache = newValue }
    }

    var allowsDependencyDownloads = true

    private let dependencyLoadGate = PersistentWebContentLoadGate()
    private var requestedDependencyHTML: String?
    private var requestedDependencyBaseURL: URL?
    private var requestedDependencyAllowsDownloads = true
    private var dependencyStatusView: NSView?

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

    static func make(playerMenuDelegate: PlayerMenuDelegate?) -> PlayerWebView {
        let webView = takePrewarmedWebView(playerMenuDelegate: playerMenuDelegate)
            ?? PlayerWebView(frame: .zero, configuration: webConfiguration(), playerMenuDelegate: playerMenuDelegate)
        webView.applyPlayerDefaults()
        webView.isHidden = false
        return webView
    }

    static func scheduleFirstUsePrewarm() {
        guard !didSchedulePrewarm, prewarmedWebView == nil else { return }
        didSchedulePrewarm = true

        let timer = Timer(timeInterval: 1.15, repeats: false) { _ in
            MainActor.assumeIsolated {
                prewarmTimer = nil
                prewarmForFirstUseIfNeeded()
            }
        }
        prewarmTimer = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    private static func prewarmForFirstUseIfNeeded() {
        guard prewarmedWebView == nil else { return }
        guard NSApplication.shared.isActive else {
            didSchedulePrewarm = false
            return
        }

        let webView = PlayerWebView(
            frame: NSRect(x: 0, y: 0, width: 8, height: 8),
            configuration: webConfiguration(),
            playerMenuDelegate: nil
        )
        webView.isHidden = true
        webView.applyPlayerDefaults()
        webView.loadHTMLString("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>", baseURL: nil)
        prewarmedWebView = webView
    }

    private static func takePrewarmedWebView(playerMenuDelegate: PlayerMenuDelegate?) -> PlayerWebView? {
        guard Thread.isMainThread else { return nil }

        let webView = prewarmedWebView
        prewarmedWebView = nil
        prewarmTimer?.invalidate()
        prewarmTimer = nil
        webView?.frame = .zero
        webView?.updatePlayerMenuDelegate(playerMenuDelegate)
        webView?.invalidateRequestedContent()
        return webView
    }

    private static func webConfiguration() -> WKWebViewConfiguration {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.suppressesIncrementalRendering = true
        webConfiguration.allowsAirPlayForMediaPlayback = true
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
        allowsBackForwardNavigationGestures = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setValue(true, forKey: "drawsTransparentBackground")
        updateLockedCursorTrackingArea()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLockedCursorTrackingArea()
        invalidateCursorRects()
    }

    override var mouseDownCanMoveWindow: Bool {
        passesPlayerGesturesThrough || super.mouseDownCanMoveWindow
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let dependencyStatusView,
           let hit = dependencyStatusView.hitTest(convert(point, from: superview)) {
            return hit
        }
        guard passesPlayerGesturesThrough else {
            return super.hitTest(point)
        }

        return bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard passesPlayerGesturesThrough else {
            super.mouseDown(with: event)
            return
        }

        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard passesPlayerGesturesThrough else {
            super.scrollWheel(with: event)
            return
        }

        nextResponder?.scrollWheel(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        guard passesPlayerGesturesThrough else {
            super.smartMagnify(with: event)
            return
        }

        nextResponder?.smartMagnify(with: event)
    }

    override func magnify(with event: NSEvent) {
        guard passesPlayerGesturesThrough else {
            super.magnify(with: event)
            return
        }

        nextResponder?.magnify(with: event)
    }

    override func swipe(with event: NSEvent) {
        guard passesPlayerGesturesThrough else {
            super.swipe(with: event)
            return
        }

        nextResponder?.swipe(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard locksPlayedContentCursor else {
            super.cursorUpdate(with: event)
            return
        }

        super.cursorUpdate(with: event)
        setLockedCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        guard locksPlayedContentCursor else {
            super.mouseEntered(with: event)
            return
        }

        super.mouseEntered(with: event)
        setLockedCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        guard locksPlayedContentCursor else {
            super.mouseMoved(with: event)
            return
        }

        super.mouseMoved(with: event)
        setLockedCursor()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard locksPlayedContentCursor else { return }
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateLockedCursorTrackingArea()
    }

    override var bounds: NSRect {
        didSet {
            loadPendingContentIfNeeded(oldRect: oldValue)
        }
    }

    override var frame: NSRect {
        didSet {
            loadPendingContentIfNeeded(oldRect: oldValue)
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
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        resetDependencyLoad()
        return contentLoadCoordinator.loadLocalHTMLString(
            string,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    func invalidateRequestedContent() {
        resetDependencyLoad()
        contentLoadCoordinator.invalidateRequestedContent()
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
    }

    private func showDependencyStatus(failed: Bool, isPreview: Bool = false) {
        clearDependencyStatus()
        let overlay = NSView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.cgColor
        if isPreview {
            addSubview(overlay)
            dependencyStatusView = overlay
            return
        }
        let label = NSTextField(wrappingLabelWithString: failed
            ? "The artwork could not load its required files."
            : "Loading artwork…")
        label.textColor = .white
        label.alignment = .center
        let stack = NSStackView(views: [label])
        stack.orientation = .vertical
        stack.spacing = 14
        if failed {
            stack.addArrangedSubview(NSButton(title: "Retry", target: self, action: #selector(retryDependencyLoad)))
        } else {
            let progress = NSProgressIndicator()
            progress.style = .spinning
            progress.startAnimation(nil)
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

    private func loadPendingContentIfNeeded(oldRect: NSRect) {
        contentLoadCoordinator.loadPendingContentIfNeeded(
            wasVisible: hasVisibleSize(oldRect),
            isVisible: hasVisibleSize
        )
    }

    private func hasVisibleSize(_ rect: NSRect) -> Bool {
        rect.size.width > 5 && rect.size.height > 5
    }

    private var locksPlayedContentCursor: Bool {
        passesPlayerGesturesThrough
    }

    private func updateLockedCursorTrackingArea() {
        if let lockedCursorTrackingArea {
            removeTrackingArea(lockedCursorTrackingArea)
            self.lockedCursorTrackingArea = nil
        }

        guard locksPlayedContentCursor else { return }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self
        )
        addTrackingArea(trackingArea)
        lockedCursorTrackingArea = trackingArea
    }

    private func invalidateCursorRects() {
        guard let window else { return }
        window.invalidateCursorRects(for: self)
    }

    private func setLockedCursor() {
        NSCursor.arrow.set()
    }
}
