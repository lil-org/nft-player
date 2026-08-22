// ∅ 2026 lil org

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import WebKit

@MainActor
final class PlayerWebContentLoadCoordinator {

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

    private struct PendingLoad {
        let content: WebContentLoad
        let successHandler: (() -> Void)?
        let failureHandler: (() -> Void)?
    }

    private struct ActiveNavigation {
        let navigation: WKNavigation
        let content: WebContentLoad
        var successHandler: (() -> Void)?
        var failureHandler: (() -> Void)?
    }

    private var lastRequestedLoad: WebContentLoad?
    private var pendingLoad: PendingLoad?
    private var activeNavigation: ActiveNavigation?
    private var successfullyLoadedContent: WebContentLoad?
    private let localHTMLFileName = "\(UUID().uuidString).html"
    private var localHTMLFileURL: URL?

    private let hasVisibleSize: () -> Bool
    private let performStopLoading: () -> Void
    private let performHTMLLoad: (String, URL?) -> WKNavigation?
    private let performFileLoad: (URL, URL) -> WKNavigation?

    init(
        hasVisibleSize: @escaping () -> Bool,
        stopLoading: @escaping () -> Void,
        loadHTMLString: @escaping (String, URL?) -> WKNavigation?,
        loadFileURL: @escaping (URL, URL) -> WKNavigation?
    ) {
        self.hasVisibleSize = hasVisibleSize
        self.performStopLoading = stopLoading
        self.performHTMLLoad = loadHTMLString
        self.performFileLoad = loadFileURL
    }

    deinit {
        if let localHTMLFileURL {
            try? FileManager.default.removeItem(at: localHTMLFileURL)
        }
    }

    @discardableResult
    func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        loadWebContent(.html(string: string, baseURL: baseURL))
    }

    @discardableResult
    func loadLocalHTMLString(
        _ string: String,
        htmlDirectoryURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        loadWebContent(
            .localHTML(string: string, htmlDirectoryURL: htmlDirectoryURL, readAccessURL: readAccessURL),
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    func invalidateRequestedContent() {
        cancelActiveLoad()
        clearRequestedContentState()
    }

    func unloadContent() {
        cancelActiveLoad()
        _ = performHTMLLoad("", nil)
        clearRequestedContentState()
    }

    func prepareForStopLoading() {
        clearActiveNavigationCallbacks()
    }

    func didFinish(_ navigation: WKNavigation?) {
        guard let navigation,
              let completedNavigation = activeNavigation,
              navigation === completedNavigation.navigation else {
            return
        }

        clearActiveNavigationCallbacks()
        if completedNavigation.content.requiresSuccessfulNavigation {
            successfullyLoadedContent = completedNavigation.content
        }
        completedNavigation.successHandler?()
    }

    func didFail(_ navigation: WKNavigation?, error: Error) {
        guard let navigation,
              let failedNavigation = activeNavigation,
              navigation === failedNavigation.navigation else {
            return
        }
        guard !Self.isCancelledNavigationError(error) else {
            clearActiveNavigationCallbacks()
            return
        }

        clearActiveNavigationCallbacks()
        clearRequestedContentState()
        failedNavigation.failureHandler?()
    }

    func loadPendingContentIfNeeded(wasVisible: Bool, isVisible: Bool) {
        guard !wasVisible, isVisible else { return }
        guard let pendingLoad else { return }
        _ = loadWebContent(
            pendingLoad.content,
            onSuccess: pendingLoad.successHandler,
            onFailure: pendingLoad.failureHandler
        )
    }

    private func loadWebContent(
        _ content: WebContentLoad,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) -> WKNavigation? {
        let newContent = lastRequestedLoad != content

        if !hasVisibleSize() {
            if newContent {
                lastRequestedLoad = content
            }
            pendingLoad = PendingLoad(
                content: content,
                successHandler: onSuccess,
                failureHandler: onFailure
            )
            cancelActiveLoad()
            return nil
        }

        if !newContent && pendingLoad == nil {
            if handleDuplicateLoadRequest(content, onSuccess: onSuccess, onFailure: onFailure) {
                return nil
            }
        }

        clearActiveNavigationCallbacks()
        if newContent {
            successfullyLoadedContent = nil
        }
        let navigation = performLoad(content)
        if navigation == nil, content.requiresSuccessfulNavigation {
            pendingLoad = nil
            onFailure?()
            return nil
        }

        if let navigation {
            activeNavigation = ActiveNavigation(
                navigation: navigation,
                content: content,
                successHandler: content.requiresSuccessfulNavigation ? onSuccess : nil,
                failureHandler: content.requiresSuccessfulNavigation ? onFailure : nil
            )
        }
        lastRequestedLoad = content
        pendingLoad = nil
        return navigation
    }

    private func performLoad(_ content: WebContentLoad) -> WKNavigation? {
        switch content {
        case let .html(string, baseURL):
            return performHTMLLoad(string, baseURL)

        case let .localHTML(string, htmlDirectoryURL, readAccessURL):
            guard let localHTMLFileURL = writeLocalHTMLString(string, in: htmlDirectoryURL) else {
                return nil
            }
            return performFileLoad(localHTMLFileURL, readAccessURL)
        }
    }

    private func cancelActiveLoad() {
        clearActiveNavigationCallbacks()
        performStopLoading()
    }

    private func clearRequestedContentState() {
        lastRequestedLoad = nil
        pendingLoad = nil
        successfullyLoadedContent = nil
    }

    private func clearActiveNavigationCallbacks() {
        activeNavigation = nil
    }

    private func handleDuplicateLoadRequest(
        _ content: WebContentLoad,
        onSuccess: (() -> Void)?,
        onFailure: (() -> Void)?
    ) -> Bool {
        guard content.requiresSuccessfulNavigation else { return true }

        if successfullyLoadedContent == content {
            Task { @MainActor in
                await Task.yield()
                onSuccess?()
            }
            return true
        }

        guard var activeNavigation,
              activeNavigation.content == content else {
            return false
        }
        activeNavigation.successHandler = combined(activeNavigation.successHandler, onSuccess)
        activeNavigation.failureHandler = combined(activeNavigation.failureHandler, onFailure)
        self.activeNavigation = activeNavigation
        return true
    }

    private func combined(_ first: (() -> Void)?, _ second: (() -> Void)?) -> (() -> Void)? {
        guard first != nil || second != nil else { return nil }
        return {
            first?()
            second?()
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

    private static func isCancelledNavigationError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}
#endif
