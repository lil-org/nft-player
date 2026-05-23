// ∅ 2026 lil org

import Cocoa
import Combine
import Darwin
import SwiftUI

class LocalHtmlWindow: NSWindow {
    
    private var playerModel: PlayerModel
    private let navigationBridge = MacPlayerNavigationBridge()
    private var cursorHideTimer: Timer?
    private var mouseMoveEventMonitor: Any?
    private var navigationKeysEventMonitor: Any?
    private var currentTokenObserver: AnyCancellable?
    private var bookmarkChangesObserver: AnyCancellable?
    private let mediaFileWorkQueue = DispatchQueue(label: "org.lil.nft-folder.player-media-file-actions", qos: .utility)
    private var activeCopyMediaRequest: CopyMediaRequest?
    private weak var titleLabel: NSTextField?
    private weak var bookmarkButton: NSButton?

    private struct MediaFileRequest {
        let descriptor: CollectionCatalogDownloadableMediaDescriptor
        let defaultFileName: String
    }

    private final class CopyMediaRequest {
        let pasteboardChangeCount: Int
        private let lock = NSLock()
        private let releaseFileClosure: () -> Void
        private var cancelFileLoad: (() -> Void)?
        private var isCancelledValue = false
        private var didReleaseFile = false

        var isCancelled: Bool {
            lock.withLock { isCancelledValue }
        }

        init(pasteboardChangeCount: Int, releaseFile: @escaping () -> Void) {
            self.pasteboardChangeCount = pasteboardChangeCount
            self.releaseFileClosure = releaseFile
        }

        func setCancelFileLoad(_ cancelFileLoad: (() -> Void)?) {
            let shouldCancel = lock.withLock {
                self.cancelFileLoad = cancelFileLoad
                return isCancelledValue
            }
            if shouldCancel {
                cancelFileLoad?()
            }
        }

        func cancel() {
            let cancelFileLoad = lock.withLock { () -> (() -> Void)? in
                guard !isCancelledValue else { return nil }
                isCancelledValue = true
                return self.cancelFileLoad
            }
            cancelFileLoad?()
            releaseFile()
        }

        func releaseFile() {
            let shouldRelease = lock.withLock {
                guard !didReleaseFile else { return false }
                didReleaseFile = true
                return true
            }
            if shouldRelease {
                releaseFileClosure()
            }
        }
    }

    private static let pasteboardMediaDirectoryName = "CopiedTokenMedia"
    private static let pasteboardMediaMaximumAge: TimeInterval = 24 * 60 * 60

    private var isFullScreenOnActiveSpace: Bool {
        return styleMask.contains(.fullScreen) && isOnActiveSpace
    }
    
    init(playerModel: PlayerModel, contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.playerModel = playerModel
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        let htmlView = LocalHtmlView(
            playerModel: playerModel,
            windowNumber: windowNumber,
            playerMenuDelegate: self,
            navigationBridge: navigationBridge,
            onViewAgain: { [weak self] in self?.viewAgainButtonClicked() },
            onFinish: { [weak self] in self?.finishButtonClicked() }
        )
        .background(.black)
        self.contentView = NSHostingView(rootView: htmlView.frame(minWidth: 251, minHeight: 130))
        
        if NSScreen.screens.count <= 1 {
            mouseMoveEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp, .rightMouseUp, .mouseEntered]) { [weak self] event in
                self?.resetCursorHideTimer()
                return event
            }
        }
        
        setupTitleBar()
        currentTokenObserver = playerModel.$currentToken
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                self?.updatePlayerChrome(for: token)
            }
        bookmarkChangesObserver = NotificationCenter.default.publisher(for: .playerBookmarksDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateBookmarkButton()
            }
        playerModel.markCurrentTokenViewed()
        Window.registerPlayerWindow(self)
        mediaFileWorkQueue.async {
            Self.prunePasteboardMediaDirectory(
                keeping: nil,
                removingItemsOlderThan: Self.pasteboardMediaMaximumAge
            )
        }
    }

    override func close() {
        cancelActiveCopyMediaRequest()
        Window.unregisterPlayerWindow(self)
        super.close()
    }
    
    private func setupTitleBar() {
        guard let closeButton = standardWindowButton(.closeButton), let titleBarView = closeButton.superview else { return }
        
        titleBarView.wantsLayer = true
        titleBarView.layer?.backgroundColor = .black
        
        let titleLabel = NSTextField(labelWithString: playerModel.playerWindowTitle)
        titleLabel.font = NSFont.preferredFont(forTextStyle: .callout)
        titleLabel.textColor = .gray
        titleLabel.backgroundColor = .clear
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.addSubview(titleLabel)
        self.titleLabel = titleLabel
        updateTitle()
        
        let moreButton = NSButton(image: Images.moreTitleBar, target: self, action: #selector(moreButtonClicked(_:)))
        moreButton.isBordered = false
        moreButton.contentTintColor = .gray
        moreButton.imageScaling = .scaleProportionallyDown
        moreButton.toolTip = Strings.more
        moreButton.setAccessibilityLabel(Strings.more)
        titleBarView.addSubview(moreButton)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            moreButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: titleBarView.trailingAnchor, constant: -8),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            moreButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        let bookmarkButton = NSButton(image: Images.bookmarkTitleBar, target: self, action: #selector(bookmarkButtonClicked))
        bookmarkButton.isBordered = false
        bookmarkButton.contentTintColor = .gray
        bookmarkButton.imageScaling = .scaleProportionallyDown
        titleBarView.addSubview(bookmarkButton)
        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false
        self.bookmarkButton = bookmarkButton
        updateBookmarkButton()
        NSLayoutConstraint.activate([
            bookmarkButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            bookmarkButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -4),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 28),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        let leftButton = NSButton(image: Images.backTitleBar, target: self, action: #selector(backButtonClicked))
        leftButton.isBordered = false
        leftButton.contentTintColor = .gray
        titleBarView.addSubview(leftButton)
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            leftButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 54)
        ])
        
        let rightButton = NSButton(image: Images.forwardTitleBar, target: self, action: #selector(forwardButtonClicked))
        rightButton.isBordered = false
        rightButton.contentTintColor = .gray
        titleBarView.addSubview(rightButton)
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            rightButton.leadingAnchor.constraint(equalTo: leftButton.trailingAnchor, constant: 8)
        ])
        
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            {
                let constraint = titleLabel.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor)
                constraint.priority = .defaultLow
                return constraint
            }(),
            {
                let constraint = titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: rightButton.trailingAnchor, constant: 8)
                constraint.priority = .defaultHigh
                return constraint
            }(),
            {
                let constraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: bookmarkButton.leadingAnchor, constant: -8)
                constraint.priority = .defaultHigh
                return constraint
            }()
        ])
        
        navigationKeysEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldHandleNavigationKeyEvent(event) else {
                return event
            }
            guard let navigationAction = Self.navigationAction(for: event) else {
                return event
            }
            self.performNavigation(navigationAction)
            return nil
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            return false
        } else {
            return super.performKeyEquivalent(with: event)
        }
    }
    
    private func resetCursorHideTimer() {
        cursorHideTimer?.invalidate()
        if isFullScreenOnActiveSpace {
            cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 2.3, repeats: false) { [weak self] _ in
                if self?.isFullScreenOnActiveSpace == true {
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
    }
    
    @objc private func moreButtonClicked(_ sender: NSButton) {
        popUpMoreMenu(from: sender)
    }

    @objc private func bookmarkButtonClicked() {
        guard canBookmark(playerModel.currentToken) else { return }

        PlayerBookmarksStore.toggleBookmark(
            collectionId: playerModel.currentToken.fullCollectionId,
            tokenId: playerModel.currentToken.id
        )
        updateBookmarkButton()
    }

    @objc private func viewAgainButtonClicked() {
        playerModel.restartCollection()
    }

    @objc private func finishButtonClicked() {
        close()
    }
    
    @objc private func forwardButtonClicked() {
        navigationBridge.goForward(animation: .immediate)
    }
    
    @objc private func backButtonClicked() {
        navigationBridge.goBack(animation: .immediate)
    }
    
    @objc private func viewOnWeb() {
        if let url = playerModel.currentToken.url {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func copyMedia() {
        guard let request = currentMediaFileRequest() else { return }

        let copyRequest = beginCopyMediaRequest(for: request.descriptor)
        let cancelFileLoad = DownloadableMediaCache.shared.loadFile(for: request.descriptor) { [weak self, copyRequest] fileURL in
            guard let self else {
                copyRequest.releaseFile()
                return
            }
            guard let fileURL else {
                let shouldShowFailure = self.isCurrentCopyMediaRequest(copyRequest)
                self.finishCopyMediaRequest(copyRequest)
                if shouldShowFailure {
                    self.showMediaAlert(message: Strings.copyMediaFailed)
                }
                return
            }
            guard self.isCurrentCopyMediaRequest(copyRequest) else {
                self.finishCopyMediaRequest(copyRequest)
                return
            }

            let workQueue = self.mediaFileWorkQueue
            workQueue.async { [copyRequest] in
                guard !copyRequest.isCancelled else {
                    copyRequest.releaseFile()
                    return
                }

                let pasteboardFileURL = Result {
                    try Self.preparePasteboardMediaFile(
                        from: fileURL,
                        fileName: request.defaultFileName
                    )
                }
                copyRequest.releaseFile()

                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        Self.removePreparedPasteboardMediaFile(pasteboardFileURL, on: workQueue)
                        return
                    }
                    let shouldWriteToPasteboard = self.isCurrentCopyMediaRequest(copyRequest)
                    self.finishCopyMediaRequest(copyRequest)
                    guard shouldWriteToPasteboard else {
                        Self.removePreparedPasteboardMediaFile(pasteboardFileURL, on: workQueue)
                        return
                    }

                    switch pasteboardFileURL {
                    case .success(let fileURL):
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        let didCopy = pasteboard.writeObjects([fileURL as NSURL])
                        if didCopy {
                            workQueue.async {
                                Self.prunePasteboardMediaDirectory(keeping: fileURL)
                            }
                        } else {
                            Self.removePasteboardMediaFile(fileURL, on: workQueue)
                            self.showMediaAlert(message: Strings.copyMediaFailed)
                        }
                    case .failure:
                        self.showMediaAlert(message: Strings.copyMediaFailed)
                    }
                }
            }
        }
        copyRequest.setCancelFileLoad(cancelFileLoad)
    }

    @objc private func saveMediaAs() {
        guard let request = currentMediaFileRequest() else { return }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = request.defaultFileName
        savePanel.beginSheetModal(for: self) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let destinationURL = savePanel.url else { return }
            let didStartAccessing = destinationURL.startAccessingSecurityScopedResource()
            self.saveMedia(
                request.descriptor,
                to: destinationURL,
                stopAccessingWhenDone: didStartAccessing
            )
        }
    }

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let canUseMediaFile = currentMediaDescriptor() != nil

        let copyMediaItem = NSMenuItem(
            title: Strings.copyMedia,
            action: #selector(copyMedia),
            keyEquivalent: ""
        )
        copyMediaItem.target = self
        copyMediaItem.isEnabled = canUseMediaFile
        menu.addItem(copyMediaItem)

        let saveAsItem = NSMenuItem(
            title: Strings.saveAs,
            action: #selector(saveMediaAs),
            keyEquivalent: ""
        )
        saveAsItem.target = self
        saveAsItem.isEnabled = canUseMediaFile
        menu.addItem(saveAsItem)

        menu.addItem(.separator())

        let viewOnWebItem = NSMenuItem(
            title: Strings.viewOnBlockExplorer,
            action: #selector(viewOnWeb),
            keyEquivalent: ""
        )
        viewOnWebItem.target = self
        menu.addItem(viewOnWebItem)
        return menu
    }

    private func popUpMoreMenu(from view: NSView) {
        makeMoreMenu().popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: view.bounds.height),
            in: view
        )
    }

    private func currentMediaFileRequest() -> MediaFileRequest? {
        let token = playerModel.currentToken
        guard let descriptor = currentMediaDescriptor(for: token) else { return nil }
        return MediaFileRequest(
            descriptor: descriptor,
            defaultFileName: defaultMediaFileName(for: token, descriptor: descriptor)
        )
    }

    private func currentMediaDescriptor(for token: GeneratedToken? = nil) -> CollectionCatalogDownloadableMediaDescriptor? {
        CollectionCatalog.downloadableMediaDescriptor(
            for: CollectionCatalog.tokenContext(for: token ?? playerModel.currentToken)
        )
    }

    private func beginCopyMediaRequest(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> CopyMediaRequest {
        cancelActiveCopyMediaRequest()
        let request = CopyMediaRequest(
            pasteboardChangeCount: NSPasteboard.general.changeCount,
            releaseFile: DownloadableMediaCache.shared.retainFile(for: descriptor)
        )
        activeCopyMediaRequest = request
        return request
    }

    private func cancelActiveCopyMediaRequest() {
        activeCopyMediaRequest?.cancel()
        activeCopyMediaRequest = nil
    }

    private func finishCopyMediaRequest(_ request: CopyMediaRequest) {
        request.releaseFile()
        if activeCopyMediaRequest === request {
            activeCopyMediaRequest = nil
        }
    }

    private func defaultMediaFileName(
        for token: GeneratedToken,
        descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> String {
        let rawBaseName = [
            token.displayName,
            token.displayTokenId,
            token.id
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? "media"

        let baseName = sanitizedFileNameBase(rawBaseName)
        let fileExtension = sanitizedFileExtension(descriptor.fileExtension)
        guard !fileExtension.isEmpty else { return baseName }
        return "\(baseName).\(fileExtension)"
    }

    private func sanitizedFileNameBase(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = value.unicodeScalars
            .map { invalidCharacters.contains($0) ? "-" : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitized.isEmpty ? "media" : sanitized
        return String(baseName.prefix(120))
    }

    private func sanitizedFileExtension(_ value: String) -> String {
        let trimCharacters = CharacterSet(charactersIn: ".")
            .union(.whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        return value
            .trimmingCharacters(in: trimCharacters)
            .unicodeScalars
            .map { invalidCharacters.contains($0) ? "-" : String($0) }
            .joined()
    }

    private func saveMedia(
        _ descriptor: CollectionCatalogDownloadableMediaDescriptor,
        to destinationURL: URL,
        stopAccessingWhenDone: Bool
    ) {
        let workQueue = mediaFileWorkQueue
        let releaseFile = DownloadableMediaCache.shared.retainFile(for: descriptor)
        DownloadableMediaCache.shared.loadFile(for: descriptor) { [weak self] fileURL in
            guard let fileURL else {
                releaseFile()
                if stopAccessingWhenDone {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
                self?.showMediaAlert(message: Strings.saveMediaFailed)
                return
            }

            workQueue.async { [weak self] in
                let result = Result {
                    try Self.copyMediaFile(from: fileURL, to: destinationURL)
                }
                releaseFile()
                if stopAccessingWhenDone {
                    destinationURL.stopAccessingSecurityScopedResource()
                }

                if case .failure = result {
                    DispatchQueue.main.async { [weak self] in
                        self?.showMediaAlert(message: Strings.saveMediaFailed)
                    }
                }
            }
        }
    }

    private func isCurrentCopyMediaRequest(_ request: CopyMediaRequest) -> Bool {
        activeCopyMediaRequest === request
            && !request.isCancelled
            && NSPasteboard.general.changeCount == request.pasteboardChangeCount
    }

    private static func copyMediaFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let sourceURL = sourceURL.standardizedFileURL
        let destinationURL = destinationURL.standardizedFileURL
        guard sourceURL != destinationURL else { return }

        let replacementDirectoryURL = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationURL,
            create: true
        )
        defer {
            try? fileManager.removeItem(at: replacementDirectoryURL)
        }

        let stagedURL = replacementDirectoryURL.appendingPathComponent(destinationURL.lastPathComponent)
        try fileManager.copyItem(at: sourceURL, to: stagedURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
        }
    }

    private static func preparePasteboardMediaFile(from sourceURL: URL, fileName: String) throws -> URL {
        let directoryURL = try pasteboardMediaDirectoryURL()
        let destinationURL = uniqueFileURL(for: fileName, in: directoryURL)
        try materializePasteboardMediaFile(from: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func materializePasteboardMediaFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if clonefile(sourceURL.path, destinationURL.path, 0) != 0 {
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)
    }

    private static func removePreparedPasteboardMediaFile(
        _ result: Result<URL, Error>,
        on workQueue: DispatchQueue
    ) {
        guard case .success(let fileURL) = result else { return }
        removePasteboardMediaFile(fileURL, on: workQueue)
    }

    private static func removePasteboardMediaFile(_ fileURL: URL, on workQueue: DispatchQueue) {
        workQueue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func pasteboardMediaDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directoryURL = applicationSupportDirectory.appendingPathComponent(
            Self.pasteboardMediaDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var excludedFromBackupURL = directoryURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludedFromBackupURL.setResourceValues(resourceValues)
        return directoryURL
    }

    private static func uniqueFileURL(for fileName: String, in directoryURL: URL) -> URL {
        let fileManager = FileManager.default
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else { return fileURL }

        let fileExtension = fileURL.pathExtension
        let baseName = fileExtension.isEmpty
            ? fileURL.lastPathComponent
            : fileURL.deletingPathExtension().lastPathComponent
        for index in 2...1000 {
            let indexedFileName = fileExtension.isEmpty
                ? "\(baseName)-\(index)"
                : "\(baseName)-\(index).\(fileExtension)"
            let indexedURL = directoryURL.appendingPathComponent(indexedFileName)
            if !fileManager.fileExists(atPath: indexedURL.path) {
                return indexedURL
            }
        }

        let fallbackFileName = fileExtension.isEmpty
            ? "\(baseName)-\(UUID().uuidString)"
            : "\(baseName)-\(UUID().uuidString).\(fileExtension)"
        return directoryURL.appendingPathComponent(fallbackFileName)
    }

    private static func prunePasteboardMediaDirectory(
        keeping keptURL: URL?,
        removingItemsOlderThan maximumAge: TimeInterval? = nil
    ) {
        guard let directoryURL = try? pasteboardMediaDirectoryURL(),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey]
              ) else {
            return
        }

        let keptURL = keptURL?.standardizedFileURL
        let now = Date()
        for url in contents {
            if url.standardizedFileURL == keptURL {
                continue
            }
            if let maximumAge {
                guard let modificationDate = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate,
                      now.timeIntervalSince(modificationDate) > maximumAge else {
                    continue
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func showMediaAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: Strings.ok)
        alert.beginSheetModal(for: self)
    }

    private func updateTitle(for token: GeneratedToken? = nil) {
        let newTitle = token.map { playerModel.playerWindowTitle(for: $0) } ?? playerModel.playerWindowTitle
        titleLabel?.stringValue = newTitle
        title = newTitle
    }

    private func canBookmark(_ token: GeneratedToken) -> Bool {
        !token.fullCollectionId.isEmpty && !token.id.isEmpty
    }

    private func isTokenBookmarked(_ token: GeneratedToken) -> Bool {
        PlayerBookmarksStore.isBookmarked(
            collectionId: token.fullCollectionId,
            tokenId: token.id
        )
    }

    private func updateBookmarkButton(for token: GeneratedToken? = nil) {
        guard let bookmarkButton else { return }

        let token = token ?? playerModel.currentToken
        let canBookmark = canBookmark(token)
        bookmarkButton.isHidden = !canBookmark
        let isBookmarked = canBookmark && isTokenBookmarked(token)
        bookmarkButton.image = isBookmarked ? Images.bookmarkFillTitleBar : Images.bookmarkTitleBar
        let label = isBookmarked ? Strings.removeBookmark : Strings.bookmark
        bookmarkButton.toolTip = label
        bookmarkButton.setAccessibilityLabel(label)
    }

    private func updatePlayerChrome(for token: GeneratedToken? = nil) {
        let token = token ?? playerModel.currentToken
        playerModel.markTokenViewed(token)
        updateTitle(for: token)
        updateBookmarkButton(for: token)
    }

    private func performNavigation(_ action: PlayerNavigationKeyAction) {
        switch action {
        case .back(let animation):
            navigationBridge.goBack(animation: animation)
        case .forward(let animation):
            navigationBridge.goForward(animation: animation)
        }
    }

    private func shouldHandleNavigationKeyEvent(_ event: NSEvent) -> Bool {
        guard isKeyWindow, event.window === self else { return false }
        guard !(firstResponder is NSTextView) else { return false }
        return true
    }

    private static func navigationAction(for event: NSEvent) -> PlayerNavigationKeyAction? {
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(shortcutModifiers).isEmpty else { return nil }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              let scalar = characters.unicodeScalars.first else {
            return nil
        }

        switch scalar.value {
        case 0x20:
            return .forward(animation: .animated)
        case 0xF700, 0xF703:
            return .forward(animation: .immediate)
        case 0xF701, 0xF702:
            return .back(animation: .immediate)
        default:
            break
        }

        switch characters {
        case "w", "d":
            return .forward(animation: .immediate)
        case "a", "s":
            return .back(animation: .immediate)
        default:
            return nil
        }
    }
    
    deinit {
        if let monitor = mouseMoveEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        if let monitor = navigationKeysEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        Window.unregisterPlayerWindow(self)
    }
    
}

private enum PlayerNavigationKeyAction {
    case back(animation: MacPlayerNavigationAnimation)
    case forward(animation: MacPlayerNavigationAnimation)
}

extension LocalHtmlWindow: PlayerMenuDelegate {
    
    func popUpMenu(view: NSView) {
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(makeMoreMenu(), with: event, for: view)
        } else {
            popUpMoreMenu(from: view)
        }
    }

}
