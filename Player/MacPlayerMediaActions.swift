// ∅ 2026 lil org

import Cocoa
import Darwin

/// Copy media / save as / view on block explorer, plus the ⋯ menu that exposes them.
/// Lifted out of the old standalone player window so the actions can be driven from
/// the toolbar, the media view's context menu, or anywhere else in the single window.
final class MacPlayerMediaActions: NSObject {

    struct Target {
        let token: GeneratedToken
        let context: PlayerTokenContext?
    }

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
            releaseFileClosure()
        }
    }

    private static let pasteboardMediaDirectoryName = "CopiedTokenMedia"
    private static let pasteboardMediaMaximumAge: TimeInterval = 24 * 60 * 60

    private let mediaFileWorkQueue = DispatchQueue(
        label: "org.lil.nft-player.player-media-file-actions",
        qos: .utility
    )
    private var activeCopyMediaRequest: CopyMediaRequest?
    private let contextProvider: () -> PlayerTokenContext?
    private let targetProvider: () -> Target?
    private weak var presentingWindow: NSWindow?

    init(
        contextProvider: @escaping () -> PlayerTokenContext?,
        targetProvider: @escaping () -> Target?
    ) {
        self.contextProvider = contextProvider
        self.targetProvider = targetProvider
        super.init()
        mediaFileWorkQueue.async {
            Self.prunePasteboardMediaDirectory(
                keeping: nil,
                removingItemsOlderThan: Self.pasteboardMediaMaximumAge
            )
        }
    }

    deinit {
        activeCopyMediaRequest?.cancel()
    }

    func updatePresentingWindow(_ window: NSWindow?) {
        presentingWindow = window
    }

    func cancelActiveCopyMediaRequest() {
        activeCopyMediaRequest?.cancel()
        activeCopyMediaRequest = nil
    }

    var canUseMediaFile: Bool {
        CollectionCatalog.downloadableMediaDescriptor(for: contextProvider()) != nil
    }

    func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let canUseMediaFile = canUseMediaFile

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

    func popUpMoreMenu(from view: NSView) {
        makeMoreMenu().popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: view.bounds.height),
            in: view
        )
    }

    func popUpContextMenu(for view: NSView) {
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(makeMoreMenu(), with: event, for: view)
        } else {
            popUpMoreMenu(from: view)
        }
    }

    @objc func viewOnWeb() {
        if let url = targetProvider()?.token.url {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func copyMedia() {
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

    @objc func saveMediaAs() {
        guard let request = currentMediaFileRequest() else { return }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = request.defaultFileName
        savePanel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let destinationURL = savePanel.url else { return }
            let didStartAccessing = destinationURL.startAccessingSecurityScopedResource()
            self.saveMedia(
                request.descriptor,
                to: destinationURL,
                stopAccessingWhenDone: didStartAccessing
            )
        }

        if let presentingWindow {
            savePanel.beginSheetModal(for: presentingWindow, completionHandler: completion)
        } else {
            savePanel.begin(completionHandler: completion)
        }
    }

    private func currentMediaFileRequest() -> MediaFileRequest? {
        guard let target = targetProvider(),
              let descriptor = CollectionCatalog.downloadableMediaDescriptor(
                for: target.context
              ) else {
            return nil
        }
        return MediaFileRequest(
            descriptor: descriptor,
            defaultFileName: defaultMediaFileName(
                for: target.token,
                descriptor: descriptor
            )
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
        if let presentingWindow {
            alert.beginSheetModal(for: presentingWindow)
        } else {
            alert.runModal()
        }
    }

}
