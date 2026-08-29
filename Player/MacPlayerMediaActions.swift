// ∅ 2026 lil org

import Cocoa
import Darwin

/// Copy media / save as / view on block explorer, plus the ⋯ menu that exposes them.
/// Lifted out of the old standalone player window so the actions can be driven from
/// the toolbar, the media view's context menu, or anywhere else in the single window.
final class MacPlayerMediaActions: NSObject {

    private actor MediaFileLane {
        private static let pasteboardMediaDirectoryName = "CopiedTokenMedia"

        func copyMediaFile(from sourceURL: URL, to destinationURL: URL) throws {
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

            let stagedURL = replacementDirectoryURL.appendingPathComponent(
                destinationURL.lastPathComponent
            )
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

        func preparePasteboardMediaFile(from sourceURL: URL, fileName: String) throws -> URL {
            let directoryURL = try pasteboardMediaDirectoryURL()
            let destinationURL = uniqueFileURL(for: fileName, in: directoryURL)
            try materializePasteboardMediaFile(
                from: sourceURL,
                to: destinationURL
            )
            return destinationURL
        }

        private func materializePasteboardMediaFile(
            from sourceURL: URL,
            to destinationURL: URL
        ) throws {
            let fileManager = FileManager.default
            if clonefile(sourceURL.path, destinationURL.path, 0) != 0 {
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            try? fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destinationURL.path
            )
        }

        func removePasteboardMediaFile(_ fileURL: URL) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        private func pasteboardMediaDirectoryURL() throws -> URL {
            let fileManager = FileManager.default
            let applicationSupportDirectory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            let directoryURL = applicationSupportDirectory.appendingPathComponent(
                Self.pasteboardMediaDirectoryName,
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            var excludedFromBackupURL = directoryURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? excludedFromBackupURL.setResourceValues(resourceValues)
            return directoryURL
        }

        private func uniqueFileURL(
            for fileName: String,
            in directoryURL: URL
        ) -> URL {
            let fileManager = FileManager.default
            let fileURL = directoryURL.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return fileURL
            }

            let fileExtension = fileURL.pathExtension
            let baseName = fileExtension.isEmpty
                ? fileURL.lastPathComponent
                : fileURL.deletingPathExtension().lastPathComponent
            for index in 2...1000 {
                let indexedFileName = fileExtension.isEmpty
                    ? "\(baseName)-\(index)"
                    : "\(baseName)-\(index).\(fileExtension)"
                let indexedURL = directoryURL.appendingPathComponent(
                    indexedFileName
                )
                if !fileManager.fileExists(atPath: indexedURL.path) {
                    return indexedURL
                }
            }

            let fallbackFileName = fileExtension.isEmpty
                ? "\(baseName)-\(UUID().uuidString)"
                : "\(baseName)-\(UUID().uuidString).\(fileExtension)"
            return directoryURL.appendingPathComponent(fallbackFileName)
        }

        func prunePasteboardMediaDirectory(
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
    }

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
        private let fileLease: DownloadableMediaFileLease
        private var task: Task<Void, Never>?
        private var isCancelledValue = false

        var isCancelled: Bool {
            lock.withLock { isCancelledValue }
        }

        init(
            pasteboardChangeCount: Int,
            fileLease: DownloadableMediaFileLease
        ) {
            self.pasteboardChangeCount = pasteboardChangeCount
            self.fileLease = fileLease
        }

        func setTask(_ task: Task<Void, Never>) {
            let shouldCancel = lock.withLock {
                self.task = task
                return isCancelledValue
            }
            if shouldCancel {
                task.cancel()
            }
        }

        func cancel() {
            let task = lock.withLock { () -> Task<Void, Never>? in
                guard !isCancelledValue else { return nil }
                isCancelledValue = true
                return self.task
            }
            task?.cancel()
            releaseFile()
        }

        func releaseFile() {
            fileLease.release()
        }
    }

    nonisolated private static let pasteboardMediaMaximumAge: TimeInterval = 24 * 60 * 60
    private static let mediaFileLane = MediaFileLane()

    private var activeCopyMediaRequest: CopyMediaRequest?
    private var activeSaveTasks = [UUID: Task<Void, Never>]()
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
        Task {
            await Self.mediaFileLane.prunePasteboardMediaDirectory(
                keeping: nil,
                removingItemsOlderThan: Self.pasteboardMediaMaximumAge
            )
        }
    }

    isolated deinit {
        activeCopyMediaRequest?.cancel()
        activeSaveTasks.values.forEach { $0.cancel() }
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
        let task = Task { @MainActor [weak self, weak copyRequest] in
            guard let copyRequest else { return }
            defer { copyRequest.releaseFile() }

            let fileURL = await DownloadableMediaCache.shared.file(for: request.descriptor)
            guard !Task.isCancelled, !copyRequest.isCancelled else { return }
            guard let fileURL else {
                guard let self else { return }
                let shouldShowFailure = self.isCurrentCopyMediaRequest(copyRequest)
                self.finishCopyMediaRequest(copyRequest)
                if shouldShowFailure {
                    self.showMediaAlert(message: Strings.copyMediaFailed)
                }
                return
            }
            guard self?.isCurrentCopyMediaRequest(copyRequest) == true else {
                self?.finishCopyMediaRequest(copyRequest)
                return
            }

            let pasteboardFileURL: URL?
            do {
                pasteboardFileURL = try await Self.mediaFileLane.preparePasteboardMediaFile(
                    from: fileURL,
                    fileName: request.defaultFileName
                )
            } catch {
                pasteboardFileURL = nil
            }

            guard !Task.isCancelled, !copyRequest.isCancelled else {
                if let pasteboardFileURL {
                    await Self.mediaFileLane.removePasteboardMediaFile(pasteboardFileURL)
                }
                return
            }
            guard let self else {
                if let pasteboardFileURL {
                    await Self.mediaFileLane.removePasteboardMediaFile(pasteboardFileURL)
                }
                return
            }

            let shouldWriteToPasteboard = self.isCurrentCopyMediaRequest(copyRequest)
            self.finishCopyMediaRequest(copyRequest)
            guard shouldWriteToPasteboard else {
                if let pasteboardFileURL {
                    await Self.mediaFileLane.removePasteboardMediaFile(pasteboardFileURL)
                }
                return
            }
            guard let pasteboardFileURL else {
                self.showMediaAlert(message: Strings.copyMediaFailed)
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let didCopy = pasteboard.writeObjects([pasteboardFileURL as NSURL])
            if didCopy {
                await Self.mediaFileLane.prunePasteboardMediaDirectory(
                    keeping: pasteboardFileURL
                )
            } else {
                await Self.mediaFileLane.removePasteboardMediaFile(pasteboardFileURL)
                self.showMediaAlert(message: Strings.copyMediaFailed)
            }
        }
        copyRequest.setTask(task)
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
            fileLease: DownloadableMediaCache.shared.fileLease(for: descriptor)
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
        let taskId = UUID()
        let fileLease = DownloadableMediaCache.shared.fileLease(for: descriptor)
        let task = Task { @MainActor [weak self] in
            defer {
                fileLease.release()
                if stopAccessingWhenDone {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
                self?.activeSaveTasks[taskId] = nil
            }

            guard let fileURL = await DownloadableMediaCache.shared.file(for: descriptor),
                  !Task.isCancelled,
                  self?.activeSaveTasks[taskId] != nil else {
                if !Task.isCancelled {
                    self?.showMediaAlert(message: Strings.saveMediaFailed)
                }
                return
            }

            let didSave: Bool
            do {
                try await Self.mediaFileLane.copyMediaFile(
                    from: fileURL,
                    to: destinationURL
                )
                didSave = true
            } catch {
                didSave = false
            }

            guard !Task.isCancelled,
                  self?.activeSaveTasks[taskId] != nil else {
                return
            }
            if !didSave {
                self?.showMediaAlert(message: Strings.saveMediaFailed)
            }
        }
        activeSaveTasks[taskId] = task
    }

    private func isCurrentCopyMediaRequest(_ request: CopyMediaRequest) -> Bool {
        activeCopyMediaRequest === request
            && !request.isCancelled
            && NSPasteboard.general.changeCount == request.pasteboardChangeCount
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
