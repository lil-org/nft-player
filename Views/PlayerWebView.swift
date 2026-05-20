// ∅ 2026 lil org

import AppKit
import WebKit

final class PlayerWebView: WebViewWithMenu, WKNavigationDelegate {

    private static var isResizeReloadEnabled = true
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
        contentLoadCoordinator.loadHTMLString(string, baseURL: baseURL)
    }

    @discardableResult func loadLocalHTMLString(
        _ string: String,
        htmlDirectoryURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        contentLoadCoordinator.loadLocalHTMLString(
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
        hasVisibleSize(bounds)
    }

    static func setResizeReloadEnabled(_ isEnabled: Bool) {
        isResizeReloadEnabled = isEnabled
    }

    private func loadPendingContentIfNeeded(oldRect: NSRect) {
        guard Self.isResizeReloadEnabled else { return }
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
