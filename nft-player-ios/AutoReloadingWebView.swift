// ∅ 2026 lil org

import UIKit
import WebKit
import CryptoKit

private final class ArtBlocksRenderingMessageHandler: NSObject, WKScriptMessageHandler {
    weak var webView: AutoReloadingWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        webView?.receiveArtBlocksRenderingMessage(message)
    }

    @objc func startupDisplayFrame(_ displayLink: CADisplayLink) {
        guard let webView else { displayLink.invalidate(); return }
        webView.loadArtworkOnDisplayFrame(displayLink)
    }
}

class AutoReloadingWebView: WKWebView, WKNavigationDelegate {

    private struct ArtworkResolutionKey: Hashable {
        let collectionId: String
        let tokenId: String
        let screenScale: CGFloat
    }

    private struct ArtworkResolutionState {
        var key: ArtworkResolutionKey?
        var attempts = 0
        var previousFactor: Double?
        var previousCanvasSize: CGSize?
        var previousDisplayedSize: CGSize?
        var previousSurfaceKey: String?
        var ignoresReports = false
    }

    private static var prewarmTimer: Timer?
    private static var prewarmedWebView: AutoReloadingWebView?
    private static var didSchedulePrewarm = false
    private static var artworkResolutionZooms: [ArtworkResolutionKey: CGFloat] = [:]
    private static var artworkResolutionCacheOrder: [ArtworkResolutionKey] = []
    private struct StartupCalibration: Codable, Equatable {
        let zoom: Double
        let ignoresReports: Bool
    }
    private static let startupCalibrationStorageKey = "artBlocksReview.startupCalibrations.v1"
    private static var startupCalibrations: [String: StartupCalibration] = {
        guard let data = UserDefaults.standard.data(forKey: startupCalibrationStorageKey),
              let values = try? JSONDecoder().decode([String: StartupCalibration].self, from: data),
              values.count <= 256 else { return [:] }
        return values.filter { $0.value.zoom.isFinite && $0.value.zoom > 0 && $0.value.zoom <= 1 }
    }()
    private var artworkCollectionId: String?
    private var artworkTokenId: String?
    private var artworkErrorHandler: ((String) -> Void)?
    private var artworkHTML: String?
    private var preparedArtworkHTML: String?
    private let dependencyLoadGate = ArtworkContentResolver.makeLoadGate()
    private var dependencySourceHTML: (html: String, baseURL: URL?)?
    private var dependencyNavigation: WKNavigation?
    private var didReportDependencyError = false
    private var artworkDependencyCover: UIView?
    var dependencyErrorHandler: ((String) -> Void)?
    var hasPersistentDependencyContent: Bool { dependencySourceHTML != nil }
    var artworkDependencyCache: PersistentArtworkDependencyCache {
        get { dependencyLoadGate.cache }
        set { dependencyLoadGate.cache = newValue }
    }
    private var artworkBaseURL: URL?
    private var artworkLogicalRenderSize: CGSize?
    private var artworkStartupProfile: ArtBlocksRenderingStartupProfiles.Profile?
    private var hasArtworkPresentationHandler = false
    private var artworkStartupTask: Task<Void, Never>?
    private var artworkStartupDisplayLink: CADisplayLink?
    private var artworkStartupFrameSize: CGSize?
    private var artworkPendingStartup: (id: UUID, html: String, baseURL: URL?)?
    private var artworkRevealTask: Task<Void, Never>?
    private var artworkPresentationReady = false
    private var artworkCover: UIImageView?
    private var artworkLastPresentedImage: UIImage?
    private(set) var artworkRenderedSize: CGSize?
    var usesStableArtworkPresentation: Bool { artworkStartupProfile != nil }
    var artworkIsPresented: Bool { artworkStartupProfile != nil && artworkCover?.isHidden == true }
#if DEBUG
    var startupTimeoutForTesting: Duration?
    static func resetStartupCalibrationsForTesting() {
        startupCalibrations = [:]
        UserDefaults.standard.removeObject(forKey: startupCalibrationStorageKey)
    }
#endif
    private var artworkGeneration: String?
    private var artworkNavigation: WKNavigation?
    private var artworkLoadTimeout: Task<Void, Never>?
    private var artworkResolutionReloadTask: Task<Void, Never>?
    private var artworkResolutionState = ArtworkResolutionState()
    private var isReloadingArtworkResolution = false
    private var didReportArtworkError = false
    private let artworkMessageHandler = ArtBlocksRenderingMessageHandler()

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

    static func newArtBlocksRenderer() -> AutoReloadingWebView {
        let webView = AutoReloadingWebView(
            frame: .zero,
            configuration: webConfiguration(suppressesIncrementalRendering: false)
        )
        webView.applyPlayerDefaults()
        return webView
    }

    isolated deinit {
        dependencyLoadGate.cancel()
        artworkLoadTimeout?.cancel()
        artworkResolutionReloadTask?.cancel()
        artworkStartupTask?.cancel()
        artworkStartupDisplayLink?.invalidate()
        artworkRevealTask?.cancel()
    }

    func configureArtBlocksRendering(
        collectionId: String,
        tokenId: String,
        onError: @escaping (String) -> Void
    ) {
        clearArtBlocksRendering()
        artworkCollectionId = collectionId
        artworkTokenId = tokenId
        pageZoom = 1
        artworkErrorHandler = onError
        artworkMessageHandler.webView = self
        configuration.userContentController.add(artworkMessageHandler, name: "artBlocksPreviewError")
        configuration.userContentController.add(artworkMessageHandler, name: "artBlocksPreviewReady")
        configuration.userContentController.add(artworkMessageHandler, name: "artBlocksPreviewResolution")
    }

    func clearArtBlocksRendering() {
        let wasArtBlocksRendering = artworkCollectionId != nil
        cancelArtworkLoad()
        artworkResolutionState = ArtworkResolutionState()
        if wasArtBlocksRendering {
            pageZoom = 1
        }
        artworkCollectionId = nil
        artworkTokenId = nil
        artworkErrorHandler = nil
        artworkHTML = nil
        preparedArtworkHTML = nil
        dependencyLoadGate.reset()
        dependencySourceHTML = nil
        dependencyNavigation = nil
        didReportDependencyError = false
        removeArtworkDependencyCover()
        artworkBaseURL = nil
        artworkLogicalRenderSize = nil
        artworkStartupTask?.cancel()
        artworkStartupTask = nil
        cancelArtworkStartupFrame()
        artworkPendingStartup = nil
        artworkStartupProfile = nil
        artworkRenderedSize = nil
        artworkRevealTask?.cancel()
        artworkRevealTask = nil
        artworkCover?.removeFromSuperview()
        artworkCover = nil
        artworkLastPresentedImage = nil
        configuration.userContentController.removeScriptMessageHandler(forName: "artBlocksPreviewError")
        configuration.userContentController.removeScriptMessageHandler(forName: "artBlocksPreviewReady")
        configuration.userContentController.removeScriptMessageHandler(forName: "artBlocksPreviewResolution")
        configuration.userContentController.removeScriptMessageHandler(forName: "artBlocksPreviewPresentation")
        hasArtworkPresentationHandler = false
    }

    func retryArtwork() {
        if let source = dependencySourceHTML {
            invalidateRequestedContent()
            loadHTMLString(source.html, baseURL: source.baseURL)
            return
        }
        guard artworkCollectionId != nil, let artworkHTML else { return }
        let baseURL = artworkBaseURL
        invalidateRequestedContent()
        loadHTMLString(artworkHTML, baseURL: baseURL)
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
        let webView = prewarmedWebView
        prewarmedWebView = nil
        prewarmTimer?.invalidate()
        prewarmTimer = nil
        return webView
    }

    private static func webConfiguration(suppressesIncrementalRendering: Bool = true) -> WKWebViewConfiguration {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.suppressesIncrementalRendering = suppressesIncrementalRendering
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
        let resolvedBaseURL = artworkCollectionId != nil
            ? (baseURL ?? URL(string: "https://preview.artblocks.invalid/"))
            : baseURL
        let context = [artworkCollectionId ?? "", artworkTokenId ?? "", resolvedBaseURL?.absoluteString ?? ""].joined(separator: "|")
        if dependencyLoadGate.load(string, context: context, onStart: { [weak self] in
            guard let self else { return }
            self.invalidateRequestedContent(preservingDependencyRequest: true)
            self.dependencySourceHTML = (string, resolvedBaseURL)
            self.didReportDependencyError = false
            self.artworkHTML = self.artworkCollectionId == nil ? nil : string
            self.preparedArtworkHTML = nil
            self.artworkBaseURL = resolvedBaseURL
            self.artworkLogicalRenderSize = nil
            self.artworkStartupProfile = nil
            self.artworkRenderedSize = nil
            self.showArtworkDependencyCover()
            if self.url != nil { self.performSuperBlankLoad() }
        }, onReady: { [weak self] resolved in
            guard let self else { return }
            self.dependencySourceHTML = (string, resolvedBaseURL)
            self.didReportDependencyError = false
            self.loadPreparedHTML(resolved, originalHTML: string, baseURL: resolvedBaseURL)
        }, onFailure: { [weak self] _ in
            self?.reportDependencyError()
        }) {
            return nil
        }
        dependencySourceHTML = nil
        dependencyNavigation = nil
        didReportDependencyError = false
        removeArtworkDependencyCover()
        return loadPreparedHTML(string, originalHTML: string, baseURL: resolvedBaseURL)
    }

    @discardableResult private func loadPreparedHTML(
        _ string: String,
        originalHTML: String,
        baseURL resolvedBaseURL: URL?
    ) -> WKNavigation? {
        if artworkStartupProfile != nil, artworkHTML == originalHTML, artworkBaseURL == resolvedBaseURL,
           artworkGeneration != nil, !didReportArtworkError, artworkPendingStartup == nil,
           artworkRenderedSize == bounds.size {
            return nil
        }
        if artworkCollectionId != nil {
            artworkHTML = originalHTML
            preparedArtworkHTML = string
            artworkBaseURL = resolvedBaseURL
            artworkLogicalRenderSize = nil
            artworkStartupProfile = nil
            let prefix = "<meta name=\"artblocks-review-render-size\" content=\""
            if let start = string.range(of: prefix), let end = string[start.upperBound...].firstIndex(of: "\"") {
                let values = string[start.upperBound..<end].split(separator: ",").compactMap { Double($0) }
                if values.count == 2, values.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 16384 }) {
                    artworkLogicalRenderSize = CGSize(width: values[0], height: values[1])
                }
            }
            let startupPrefix = "<meta name=\"artblocks-review-startup\" content=\""
            if let start = string.range(of: startupPrefix), let end = string[start.upperBound...].firstIndex(of: "\""),
               let data = Data(base64Encoded: String(string[start.upperBound..<end])),
               let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               fields["collectionId"] as? String == artworkCollectionId,
               fields["tokenId"] as? String == artworkTokenId {
                artworkStartupProfile = try? JSONDecoder().decode(ArtBlocksRenderingStartupProfiles.Profile.self, from: data)
            }
            if artworkStartupProfile != nil {
                if !hasArtworkPresentationHandler {
                    configuration.userContentController.add(artworkMessageHandler, name: "artBlocksPreviewPresentation")
                    hasArtworkPresentationHandler = true
                }
                artworkPendingStartup = (UUID(), string, resolvedBaseURL)
                showArtworkCover()
                scheduleArtworkStartup()
                return nil
            }
        }
        return contentLoadCoordinator.loadHTMLString(string, baseURL: resolvedBaseURL)
    }

    @discardableResult func loadLocalHTMLString(
        _ string: String,
        htmlDirectoryURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        dependencyLoadGate.reset()
        dependencySourceHTML = nil
        dependencyNavigation = nil
        removeArtworkDependencyCover()
        return contentLoadCoordinator.loadLocalHTMLString(
            string,
            htmlDirectoryURL: htmlDirectoryURL,
            allowingReadAccessTo: readAccessURL,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    func invalidateRequestedContent() {
        invalidateRequestedContent(preservingDependencyRequest: false)
    }

    private func invalidateRequestedContent(preservingDependencyRequest: Bool) {
        if !preservingDependencyRequest { dependencySourceHTML = nil }
        artworkStartupTask?.cancel()
        artworkStartupTask = nil
        cancelArtworkStartupFrame()
        artworkPendingStartup = nil
        cancelArtworkLoad(preservingDependencyRequest: preservingDependencyRequest)
        contentLoadCoordinator.invalidateRequestedContent()
    }

    func unloadContent() {
        clearArtBlocksRendering()
        contentLoadCoordinator.unloadContent()
    }

    override func stopLoading() {
        dependencySourceHTML = nil
        artworkStartupTask?.cancel()
        artworkStartupTask = nil
        cancelArtworkStartupFrame()
        artworkPendingStartup = nil
        cancelArtworkLoad()
        contentLoadCoordinator.prepareForStopLoading()
        super.stopLoading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        contentLoadCoordinator.didFinish(navigation)
        if let navigation, navigation === dependencyNavigation {
            removeArtworkDependencyCover()
        }
        if let navigation, navigation === artworkNavigation, artworkStartupProfile == nil {
            artworkLoadTimeout?.cancel()
            artworkLoadTimeout = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        contentLoadCoordinator.didFail(navigation, error: error)
        reportArtworkNavigationFailure(navigation, error: error)
        reportDependencyNavigationFailure(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        contentLoadCoordinator.didFail(navigation, error: error)
        reportArtworkNavigationFailure(navigation, error: error)
        reportDependencyNavigationFailure(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if artworkCollectionId == nil, dependencyNavigation != nil { reportDependencyError() }
        guard artworkGeneration != nil else { return }
        reportArtworkError("The artwork renderer stopped. Try again, or move to another item.")
    }

    private func performSuperLoadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        guard artworkCollectionId != nil else {
            let navigation = super.loadHTMLString(string, baseURL: baseURL)
            dependencyNavigation = dependencySourceHTML == nil ? nil : navigation
            return navigation
        }
        cancelArtworkLoad()
        let resolutionKey = currentArtworkResolutionKey
        if !isReloadingArtworkResolution || artworkResolutionState.key != resolutionKey {
            artworkResolutionState = ArtworkResolutionState(key: resolutionKey)
            let calibration = startupCalibration()
            let cachedZoom = artworkStartupProfile != nil
                ? CGFloat(calibration?.zoom ?? Double(initialArtworkPageZoom))
                : resolutionKey.flatMap { Self.artworkResolutionZooms[$0] } ?? preferredArtworkPageZoom
            pageZoom = min(preferredArtworkPageZoom, max(minimumArtworkPageZoom, cachedZoom))
            if artworkStartupProfile != nil {
                artworkResolutionState.ignoresReports = calibration?.ignoresReports == true || artworkStartupProfile?.fixedResolution == true
            }
        }
        if artworkStartupProfile != nil {
            artworkRenderedSize = bounds.size
            artworkPresentationReady = false
            showArtworkCover()
        }
        let generation = UUID().uuidString
        artworkGeneration = generation
        didReportArtworkError = false
        let viewportStyle: String
        if artworkStartupProfile != nil {
            viewportStyle = "<style>html, body { position: relative; width: \(bounds.width / pageZoom)px !important; min-width: \(bounds.width / pageZoom)px !important; height: \(bounds.height / pageZoom)px !important; min-height: \(bounds.height / pageZoom)px !important; }</style>"
        } else {
            viewportStyle = pageZoom < 1
                ? "<style>html, body { position: relative; height: \(bounds.height / pageZoom)px !important; min-height: \(bounds.height / pageZoom)px !important; }</style>"
                : ""
        }
        let marker = "<script>window.__artBlocksPreviewGeneration='\(generation)';</script>" + viewportStyle
        let document: String
        if let headRange = string.range(of: "<head>") {
            document = string.replacingCharacters(in: headRange, with: "<head>\(marker)")
        } else {
            document = marker + string
        }
        let navigation = super.loadHTMLString(document, baseURL: baseURL)
        artworkNavigation = navigation
        dependencyNavigation = dependencySourceHTML == nil ? nil : navigation
        if artworkStartupProfile != nil, artworkResolutionState.ignoresReports { saveStartupCalibration() }
        var timeout: Duration = .seconds(60)
#if DEBUG
        if artworkStartupProfile != nil, let startupTimeoutForTesting { timeout = startupTimeoutForTesting }
#endif
        artworkLoadTimeout = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self, self.artworkGeneration == generation else { return }
            self.reportArtworkError("The artwork could not finish loading. Retry or move to another item.")
        }
        return navigation
    }

    private func performSuperLoadFileURL(_ fileURL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        super.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
    }

    private func performSuperStopLoading() {
        super.stopLoading()
    }

    fileprivate func receiveArtBlocksRenderingMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let generation = artworkGeneration,
              body["generation"] as? String == generation,
              body["collectionId"] as? String == artworkCollectionId,
              body["tokenId"] as? String == artworkTokenId else {
            return
        }
        if message.name == "artBlocksPreviewReady" {
            if artworkStartupProfile == nil {
                artworkLoadTimeout?.cancel()
                artworkLoadTimeout = nil
            }
        } else if message.name == "artBlocksPreviewPresentation" {
            artworkPresentationReady = true
            revealStableArtworkIfPossible(generation: generation)
        } else if message.name == "artBlocksPreviewResolution" {
            receiveArtworkResolution(body, generation: generation)
        } else if let message = body["message"] as? String {
            reportArtworkError(message)
        }
    }

    private var artworkScreenScale: CGFloat {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        return scale.isFinite && scale > 0 ? max(scale, 1) : 1
    }

    private var minimumArtworkPageZoom: CGFloat {
        min(1 / artworkScreenScale, preferredArtworkPageZoom)
    }

    private var preferredArtworkPageZoom: CGFloat {
        guard let size = artworkLogicalRenderSize, hasVisibleSize else { return 1 }
        return min(1, bounds.width / size.width, bounds.height / size.height)
    }

    private var initialArtworkPageZoom: CGFloat {
        guard let profile = artworkStartupProfile, !profile.fixedResolution else { return preferredArtworkPageZoom }
        let idiomDensity = traitCollection.userInterfaceIdiom == .pad ? profile.iPadPixelDensity : profile.phonePixelDensity
        guard let density = idiomDensity ?? profile.coarsePointerPixelDensity ?? profile.authoredPixelDensity,
              density.isFinite, density > 0 else { return preferredArtworkPageZoom }
        let zoom = min(preferredArtworkPageZoom, max(minimumArtworkPageZoom, CGFloat(density) / artworkScreenScale))
        if let maximum = profile.maximumLogicalDimension,
           max(bounds.width, bounds.height) / zoom > maximum { return preferredArtworkPageZoom }
        return zoom
    }

    private var startupCalibrationKey: String? {
        guard let collection = artworkCollectionId else { return nil }
        return startupCalibrationKey(collectionId: collection)
    }

    private func startupCalibrationKey(collectionId: String) -> String? {
        guard let profile = artworkStartupProfile, let token = artworkTokenId, hasVisibleSize else { return nil }
        let values = [collectionId, token, profile.revision, String(Double(bounds.width)), String(Double(bounds.height)),
                      String(Double(artworkScreenScale)), String(traitCollection.userInterfaceIdiom.rawValue), ProcessInfo.processInfo.operatingSystemVersionString]
        return SHA256.hash(data: Data(values.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func startupCalibration() -> StartupCalibration? {
        guard let key = startupCalibrationKey else { return nil }
        if let calibration = Self.startupCalibrations[key] { return calibration }
        guard let collection = artworkCollectionId,
              let legacyID = TokenGenerator.legacyArtBlocksCollectionId(collectionId: collection),
              let legacyKey = startupCalibrationKey(collectionId: legacyID),
              let calibration = Self.startupCalibrations[legacyKey] else { return nil }
        Self.startupCalibrations.removeValue(forKey: legacyKey)
        Self.startupCalibrations[key] = calibration
        if let data = try? JSONEncoder().encode(Self.startupCalibrations) {
            UserDefaults.standard.set(data, forKey: Self.startupCalibrationStorageKey)
        }
        return calibration
    }

    private func saveStartupCalibration() {
        guard let key = startupCalibrationKey else { return }
        let value = StartupCalibration(zoom: Double(pageZoom), ignoresReports: artworkResolutionState.ignoresReports)
        guard Self.startupCalibrations[key] != value else { return }
        if Self.startupCalibrations[key] == nil, Self.startupCalibrations.count >= 256,
           let oldest = Self.startupCalibrations.keys.sorted().first { Self.startupCalibrations.removeValue(forKey: oldest) }
        Self.startupCalibrations[key] = value
        if let data = try? JSONEncoder().encode(Self.startupCalibrations) {
            UserDefaults.standard.set(data, forKey: Self.startupCalibrationStorageKey)
        }
    }

    private func scheduleArtworkStartup() {
        artworkStartupTask?.cancel()
        artworkStartupTask = nil
        cancelArtworkStartupFrame()
        guard artworkPendingStartup != nil, hasVisibleSize else { return }
        artworkStartupFrameSize = bounds.size
        let displayLink = CADisplayLink(target: artworkMessageHandler,
                                      selector: #selector(ArtBlocksRenderingMessageHandler.startupDisplayFrame(_:)))
        artworkStartupDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    private func cancelArtworkStartupFrame() {
        artworkStartupDisplayLink?.invalidate()
        artworkStartupDisplayLink = nil
        artworkStartupFrameSize = nil
    }

    fileprivate func loadArtworkOnDisplayFrame(_ displayLink: CADisplayLink) {
        guard displayLink === artworkStartupDisplayLink, let pending = artworkPendingStartup else {
            displayLink.invalidate()
            return
        }
        superview?.layoutIfNeeded()
        guard displayLink === artworkStartupDisplayLink, artworkPendingStartup?.id == pending.id else { return }
        guard hasVisibleSize else { cancelArtworkStartupFrame(); return }
        guard artworkStartupFrameSize == bounds.size else {
            artworkStartupFrameSize = bounds.size
            return
        }
        cancelArtworkStartupFrame()
        artworkPendingStartup = nil
        if artworkGeneration == nil { contentLoadCoordinator.invalidateRequestedContent() }
        let navigation = contentLoadCoordinator.loadHTMLString(pending.html, baseURL: pending.baseURL)
        if navigation == nil, let generation = artworkGeneration {
            revealStableArtworkIfPossible(generation: generation)
        }
    }

    private func showArtworkCover(image: UIImage? = nil) {
        guard artworkStartupProfile != nil else { return }
        artworkRevealTask?.cancel()
        artworkRevealTask = nil
        if artworkCover == nil {
            let cover = UIImageView(frame: bounds)
            cover.backgroundColor = .black
            cover.contentMode = .scaleAspectFit
            cover.isUserInteractionEnabled = false
            cover.isAccessibilityElement = false
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(cover)
            artworkCover = cover
        }
        if let image { artworkCover?.image = image }
        artworkCover?.isHidden = false
        if let artworkCover { bringSubviewToFront(artworkCover) }
    }

    private func revealStableArtworkIfPossible(generation: String) {
        guard artworkStartupProfile != nil, artworkPresentationReady, !didReportArtworkError,
              artworkCover?.isHidden != true,
              artworkResolutionReloadTask == nil, artworkGeneration == generation,
              artworkPendingStartup == nil, artworkStartupTask == nil,
              let size = artworkRenderedSize,
              abs(size.width - bounds.width) <= 1 / artworkScreenScale,
              abs(size.height - bounds.height) <= 1 / artworkScreenScale else { return }
        artworkCover?.isHidden = true
        artworkCover?.image = nil
        artworkLoadTimeout?.cancel()
        artworkLoadTimeout = nil
        artworkRevealTask?.cancel()
        artworkRevealTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.artworkGeneration == generation, self.artworkResolutionReloadTask == nil,
                  self.artworkPendingStartup == nil, self.artworkStartupTask == nil,
                  let size = self.artworkRenderedSize,
                  abs(size.width - self.bounds.width) <= 1 / self.artworkScreenScale,
                  abs(size.height - self.bounds.height) <= 1 / self.artworkScreenScale,
                  !self.didReportArtworkError else { return }
            let image = try? await self.takeSnapshot(configuration: nil)
            guard !Task.isCancelled, self.artworkGeneration == generation else { return }
            self.artworkRevealTask = nil
            self.artworkLastPresentedImage = image
        }
    }

    private var currentArtworkResolutionKey: ArtworkResolutionKey? {
        guard let collectionId = artworkCollectionId,
              let tokenId = artworkTokenId,
              bounds.width.isFinite, bounds.height.isFinite,
              hasVisibleSize else { return nil }
        return ArtworkResolutionKey(
            collectionId: collectionId,
            tokenId: tokenId,
            screenScale: artworkScreenScale
        )
    }

    private func receiveArtworkResolution(_ body: [String: Any], generation: String) {
        guard !didReportArtworkError,
              !artworkResolutionState.ignoresReports,
              artworkResolutionReloadTask == nil,
              let key = artworkResolutionState.key,
              key == currentArtworkResolutionKey,
              let factor = body["factor"] as? Double,
              let canvasWidth = body["canvasWidth"] as? Double,
              let canvasHeight = body["canvasHeight"] as? Double,
              let cssWidth = body["cssWidth"] as? Double,
              let cssHeight = body["cssHeight"] as? Double,
              factor.isFinite, factor > 0,
              canvasWidth.isFinite, canvasWidth > 0,
              canvasHeight.isFinite, canvasHeight > 0,
              cssWidth.isFinite, cssWidth > 0,
              cssHeight.isFinite, cssHeight > 0 else { return }

        let viewportScale = (body["viewportScale"] as? Double) ?? 1
        guard viewportScale.isFinite, viewportScale > 0 else { return }
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        let displayedSize = CGSize(
            width: cssWidth * Double(pageZoom) * viewportScale,
            height: cssHeight * Double(pageZoom) * viewportScale
        )
        if let previousCanvasSize = artworkResolutionState.previousCanvasSize,
           let previousDisplayedSize = artworkResolutionState.previousDisplayedSize {
            var measuredCanvasSize = canvasSize
            var measuredDisplayedSize = displayedSize
            if let surfaceKey = artworkResolutionState.previousSurfaceKey {
                guard let surfaces = body["surfaces"] as? [[String: Any]],
                      let surface = surfaces.first(where: { $0["key"] as? String == surfaceKey }),
                      let width = surface["canvasWidth"] as? Double, let height = surface["canvasHeight"] as? Double,
                      let cssWidth = surface["cssWidth"] as? Double, let cssHeight = surface["cssHeight"] as? Double,
                      [width, height, cssWidth, cssHeight].allSatisfy({ $0.isFinite && $0 > 0 }) else { return }
                measuredCanvasSize = CGSize(width: width, height: height)
                measuredDisplayedSize = CGSize(width: cssWidth * Double(pageZoom) * viewportScale,
                                                height: cssHeight * Double(pageZoom) * viewportScale)
            }
            let bitmapDidNotGrow = measuredCanvasSize.width <= previousCanvasSize.width + 1
                && measuredCanvasSize.height <= previousCanvasSize.height + 1
            let displayedSizeChanged = abs(measuredDisplayedSize.width - previousDisplayedSize.width) > max(2, previousDisplayedSize.width * 0.025)
                || abs(measuredDisplayedSize.height - previousDisplayedSize.height) > max(2, previousDisplayedSize.height * 0.025)
            if bitmapDidNotGrow || displayedSizeChanged {
                revertArtworkResolution(generation: generation, key: key)
                return
            }
        }

        if factor <= 1.02 {
            artworkResolutionState.previousFactor = nil
            artworkResolutionState.previousCanvasSize = nil
            artworkResolutionState.previousDisplayedSize = nil
            artworkResolutionState.previousSurfaceKey = nil
            Self.artworkResolutionZooms[key] = pageZoom
            Self.artworkResolutionCacheOrder.removeAll { $0 == key }
            Self.artworkResolutionCacheOrder.append(key)
            if Self.artworkResolutionCacheOrder.count > 256 {
                let evicted = Self.artworkResolutionCacheOrder.removeFirst()
                Self.artworkResolutionZooms.removeValue(forKey: evicted)
            }
            saveStartupCalibration()
            revealStableArtworkIfPossible(generation: generation)
            return
        }

        let hasStoppedImproving = artworkResolutionState.previousFactor.map { factor >= $0 * 0.98 } ?? false
        if hasStoppedImproving || pageZoom <= minimumArtworkPageZoom + 0.000001 || artworkResolutionState.attempts >= 2 {
            revertArtworkResolution(generation: generation, key: key)
            return
        }

        let targetZoom = max(minimumArtworkPageZoom, pageZoom / CGFloat(factor))
        guard targetZoom < pageZoom else { return }
        artworkResolutionState.attempts += 1
        artworkResolutionState.previousFactor = factor
        artworkResolutionState.previousCanvasSize = canvasSize
        artworkResolutionState.previousDisplayedSize = displayedSize
        artworkResolutionState.previousSurfaceKey = body["measuredSurfaceKey"] as? String
        scheduleArtworkResolutionReload(zoom: targetZoom, generation: generation, key: key)
    }

    private func revertArtworkResolution(generation: String, key: ArtworkResolutionKey) {
        artworkResolutionState.ignoresReports = true
        Self.artworkResolutionZooms.removeValue(forKey: key)
        Self.artworkResolutionCacheOrder.removeAll { $0 == key }
        if pageZoom != preferredArtworkPageZoom {
            scheduleArtworkResolutionReload(zoom: preferredArtworkPageZoom, generation: generation, key: key)
        } else {
            saveStartupCalibration()
            revealStableArtworkIfPossible(generation: generation)
        }
    }

    private func scheduleArtworkResolutionReload(zoom: CGFloat, generation: String, key: ArtworkResolutionKey) {
        artworkResolutionReloadTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self else { return }
            if self.artworkStartupProfile == nil { self.artworkResolutionReloadTask = nil }
            guard self.artworkGeneration == generation,
                  self.currentArtworkResolutionKey == key,
                  let html = self.preparedArtworkHTML else { return }
            if self.artworkStartupProfile != nil {
                let snapshot = self.artworkCover?.isHidden == true ? try? await self.takeSnapshot(configuration: nil) : nil
                guard !Task.isCancelled, self.artworkGeneration == generation, self.currentArtworkResolutionKey == key else { return }
                self.showArtworkCover(image: snapshot)
            }
            self.artworkResolutionReloadTask = nil
            let baseURL = self.artworkBaseURL
            self.cancelArtworkLoad()
            self.pageZoom = zoom
            self.isReloadingArtworkResolution = true
            defer { self.isReloadingArtworkResolution = false }
            self.contentLoadCoordinator.invalidateRequestedContent()
            self.contentLoadCoordinator.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func reportArtworkNavigationFailure(_ navigation: WKNavigation?, error: Error) {
        guard let navigation, navigation === artworkNavigation else { return }
        let error = error as NSError
        guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
        reportArtworkError(error.localizedDescription)
    }

    private func reportArtworkError(_ message: String) {
        guard let collectionId = artworkCollectionId,
              let tokenId = artworkTokenId,
              !didReportArtworkError else { return }
        didReportArtworkError = true
        artworkResolutionReloadTask?.cancel()
        artworkResolutionReloadTask = nil
        artworkResolutionState.ignoresReports = true
        artworkLoadTimeout?.cancel()
        artworkLoadTimeout = nil
        print("Art Blocks [\(collectionId)] token \(tokenId): \(message)")
        artworkErrorHandler?(message)
    }

    private func cancelArtworkLoad(preservingDependencyRequest: Bool = false) {
        if !preservingDependencyRequest { dependencyLoadGate.cancel() }
        dependencyNavigation = nil
        artworkGeneration = nil
        artworkNavigation = nil
        artworkLoadTimeout?.cancel()
        artworkLoadTimeout = nil
        artworkResolutionReloadTask?.cancel()
        artworkResolutionReloadTask = nil
        artworkRevealTask?.cancel()
        artworkRevealTask = nil
        didReportArtworkError = false
    }

    private func performSuperBlankLoad() {
        super.loadHTMLString("", baseURL: nil)
    }

    private func reportDependencyError() {
        guard dependencySourceHTML != nil, !didReportDependencyError else { return }
        didReportDependencyError = true
        let message = "The artwork dependencies could not be loaded. Retry or move to another item."
        if let dependencyErrorHandler { dependencyErrorHandler(message) }
        else { artworkErrorHandler?(message) }
    }

    private func reportDependencyNavigationFailure(_ navigation: WKNavigation?, error: Error) {
        let error = error as NSError
        guard artworkCollectionId == nil, let navigation, navigation === dependencyNavigation,
              error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
        reportDependencyError()
    }

    private func showArtworkDependencyCover() {
        guard artworkDependencyCover == nil else { return }
        let cover = UIView(frame: bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .black
        cover.isUserInteractionEnabled = false
        addSubview(cover)
        artworkDependencyCover = cover
        accessibilityElementsHidden = true
    }

    private func removeArtworkDependencyCover() {
        guard let artworkDependencyCover else { return }
        artworkDependencyCover.removeFromSuperview()
        self.artworkDependencyCover = nil
        accessibilityElementsHidden = false
    }

    func reloadStableArtworkAfterResize() {
        guard artworkStartupProfile != nil else { return }
        if artworkPendingStartup != nil { scheduleArtworkStartup(); return }
        guard let renderedSize = artworkRenderedSize, let html = artworkHTML else { return }
        guard abs(renderedSize.width - bounds.width) > 1 / artworkScreenScale
                || abs(renderedSize.height - bounds.height) > 1 / artworkScreenScale else {
            artworkStartupTask?.cancel()
            artworkStartupTask = nil
            if let generation = artworkGeneration { revealStableArtworkIfPossible(generation: generation) }
            return
        }
        let generation = artworkGeneration
        artworkStartupTask?.cancel()
        artworkStartupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = self.artworkCover?.isHidden == true ? try? await self.takeSnapshot(configuration: nil) : nil
            guard !Task.isCancelled, self.artworkGeneration == generation else { return }
            self.artworkStartupTask = nil
            self.showArtworkCover(image: snapshot)
            self.contentLoadCoordinator.invalidateRequestedContent()
            self.loadHTMLString(html, baseURL: self.artworkBaseURL)
        }
    }
    
    private var hasVisibleSize: Bool {
        return bounds.size.width > 5 && bounds.size.height > 5
    }
    
    private func loadPendingContentIfNeeded(oldRect: CGRect) {
        if artworkStartupProfile != nil, let renderedSize = artworkRenderedSize,
           abs(renderedSize.width - bounds.width) > 1 / artworkScreenScale
            || abs(renderedSize.height - bounds.height) > 1 / artworkScreenScale {
            showArtworkCover(image: artworkLastPresentedImage)
        }
        if artworkStartupProfile != nil, artworkPendingStartup != nil {
            if oldRect.size != bounds.size { scheduleArtworkStartup() }
            return
        }
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
