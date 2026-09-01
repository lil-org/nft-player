// ∅ 2026 lil org

import Foundation

#if os(macOS)
import AppKit
typealias DownloadableMediaImage = NSImage
#else
import UIKit
typealias DownloadableMediaImage = UIImage
#endif

nonisolated enum DownloadableMediaRequestPriority: Sendable {
    case foreground
    case preservingPrefetch
}

nonisolated enum DownloadableMediaImageDecodeVariant: Hashable, Sendable {
    case full
    case downsampled(maxPixelWidth: Int)

    var normalized: Self {
        switch self {
        case .full:
            return .full
        case let .downsampled(maxPixelWidth):
            return .downsampled(maxPixelWidth: max(maxPixelWidth, 1))
        }
    }

    var cacheKeyComponent: String {
        switch normalized {
        case .full:
            return "full"
        case let .downsampled(maxPixelWidth):
            return "downsampled-\(maxPixelWidth)"
        }
    }

    func satisfies(_ requestedVariant: Self) -> Bool {
        switch (normalized, requestedVariant.normalized) {
        case (.full, _):
            return true
        case (.downsampled, .full):
            return false
        case let (
            .downsampled(maxPixelWidth: availableWidth),
            .downsampled(maxPixelWidth: requestedWidth)
        ):
            return availableWidth >= requestedWidth
        }
    }
}

nonisolated struct DownloadableMediaCacheLayout: Sendable {
    static let webViewHTMLDirectoryName = "_WebViewHTML"
    static let downloadedMediaMetadataFileSuffix = ".metadata.json"
    static let fileRemovalTombstonePrefix = ".nft-player-removing-"
    static let fileRemovalTrashDirectoryName = ".FileRemovalTrash"

    let cacheRoot: URL
    let stagingRoot: URL

    static var live: Self {
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return Self(
            cacheRoot: applicationSupportDirectory.appendingPathComponent(
                "DownloadableTokenMedia",
                isDirectory: true
            ),
            stagingRoot: fileManager.temporaryDirectory.appendingPathComponent(
                "DownloadableTokenMedia",
                isDirectory: true
            )
        )
    }

    var webViewHTMLDirectoryURL: URL {
        cacheRoot.appendingPathComponent(
            Self.webViewHTMLDirectoryName,
            isDirectory: true
        )
    }

    var webViewReadAccessURL: URL {
        cacheRoot
    }

    var fileRemovalTrashDirectoryURL: URL {
        cacheRoot.appendingPathComponent(
            Self.fileRemovalTrashDirectoryName,
            isDirectory: true
        )
    }

    func location(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> DownloadableMediaDiskLocation {
        let directoryURL = collectionDirectory(
            collectionId: descriptor.collectionId
        )
        let mediaFileName = fileName(for: descriptor)
        return DownloadableMediaDiskLocation(
            key: cacheKey(for: descriptor),
            descriptor: descriptor,
            collectionDirectoryURL: directoryURL,
            mediaURL: directoryURL.appendingPathComponent(mediaFileName),
            metadataURL: directoryURL.appendingPathComponent(
                Self.metadataFileName(forFileName: mediaFileName)
            )
        )
    }

    func cacheKey(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> String {
        "\(descriptor.collectionId)|\(descriptor.tokenIndex)|\(descriptor.tokenId)|\(sourceURLHash(for: descriptor))|\(descriptor.fileExtension)"
    }

    func collectionDirectory(collectionId: String) -> URL {
        cacheRoot.appendingPathComponent(
            safePathComponent(collectionId),
            isDirectory: true
        )
    }

    func fileNames(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> [String] {
        let mediaFileName = fileName(for: descriptor)
        return [
            mediaFileName,
            Self.metadataFileName(forFileName: mediaFileName),
        ]
    }

    func diskPaths(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> [String] {
        let location = location(for: descriptor)
        return [location.mediaURL, location.metadataURL].map(diskPath(for:))
    }

    func diskPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func fileName(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> String {
        let paddedIndex = String(format: "%06d", descriptor.tokenIndex)
        return "\(paddedIndex)-\(safePathComponent(descriptor.tokenId))-\(sourceURLHash(for: descriptor)).\(descriptor.fileExtension)"
    }

    private static func metadataFileName(forFileName fileName: String) -> String {
        "\(fileName)\(downloadedMediaMetadataFileSuffix)"
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        return String(value.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        })
    }

    private func sourceURLHash(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in descriptor.url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

nonisolated struct DownloadableMediaDiskLocation: Hashable, Sendable {
    let key: String
    let descriptor: CollectionCatalogDownloadableMediaDescriptor
    let collectionDirectoryURL: URL
    let mediaURL: URL
    let metadataURL: URL
}

nonisolated struct DownloadableMediaFileAvailability: Sendable {
    let checkedKeys: Set<String>
    let availableKeys: Set<String>

    func hasFile(forKey key: String) -> Bool? {
        checkedKeys.contains(key) ? availableKeys.contains(key) : nil
    }
}

nonisolated struct DownloadableMediaDownloadRequest: Sendable {
    let id: UUID
    let sourceURL: URL
    let priority: Float
    let stagingRoot: URL
}

nonisolated enum DownloadableMediaDownloadFailure: Sendable {
    case cancelled
    case transport
    case invalidResponse
    case staging
}

nonisolated struct DownloadableMediaDownloadResult: Sendable {
    let requestID: UUID
    let stagedURL: URL?
    let sourceURL: URL?
    let failure: DownloadableMediaDownloadFailure?
}

nonisolated final class DownloadableMediaImageDecodeGeneration:
    @unchecked Sendable {

    private enum State: Equatable {
        case pending
        case decoding
        case invalidated
    }

    private let lock = NSLock()
    private var state = State.pending

    func beginIfCurrent() -> Bool {
        lock.withLock {
            guard state == .pending else { return false }
            state = .decoding
            return true
        }
    }

    func invalidateIfPending() -> Bool {
        lock.withLock {
            guard state == .pending else { return false }
            state = .invalidated
            return true
        }
    }

    func invalidate() {
        lock.withLock {
            state = .invalidated
        }
    }
}

nonisolated struct DownloadableMediaDecodedImageTransfer:
    @unchecked Sendable {
    let image: DownloadableMediaImage?
    let variant: DownloadableMediaImageDecodeVariant?

    init(
        image: DownloadableMediaImage?,
        variant: DownloadableMediaImageDecodeVariant? = nil
    ) {
        self.image = image
        self.variant = variant?.normalized
    }
}

nonisolated struct DownloadableMediaImageEntry: @unchecked Sendable {
    let image: DownloadableMediaImage
    let variant: DownloadableMediaImageDecodeVariant
}

nonisolated struct DownloadableMediaCacheDecodedImageAvailability:
    Equatable, Sendable {
    let collectionId: String
    let tokenIndex: Int
}

nonisolated final class DownloadableMediaFileLease: @unchecked Sendable {
    private let lock = NSLock()
    private var releaseAction: (@Sendable () -> Void)?

    init(release: @escaping @Sendable () -> Void) {
        releaseAction = release
    }

    func release() {
        let action = lock.withLock {
            let action = releaseAction
            releaseAction = nil
            return action
        }
        action?()
    }

    deinit {
        release()
    }
}

nonisolated final class DownloadableMediaAsyncRequest<Value: Sendable>:
    @unchecked Sendable {

    private enum State {
        case pending
        case completed(Value, cancelled: Bool)
    }

    private let lock = NSLock()
    private var state = State.pending
    private var continuation: CheckedContinuation<Value, Never>?
    private var cancellation: (@MainActor @Sendable () -> Void)?

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            let completed = lock.withLock { () -> (Bool, Value?) in
                switch state {
                case .pending:
                    self.continuation = continuation
                    return (false, nil)
                case let .completed(value, _):
                    return (true, value)
                }
            }
            if completed.0 {
                continuation.resume(returning: completed.1!)
            }
        }
    }

    func installCancellation(
        _ cancellation: @escaping @MainActor @Sendable () -> Void
    ) {
        let shouldCancel = lock.withLock {
            switch state {
            case .pending:
                self.cancellation = cancellation
                return false
            case let .completed(_, cancelled):
                return cancelled
            }
        }
        if shouldCancel {
            Task { @MainActor in
                cancellation()
            }
        }
    }

    func finish(_ value: Value) {
        complete(value, cancelled: false)
    }

    func cancel(returning value: Value) {
        complete(value, cancelled: true)
    }

    private func complete(_ value: Value, cancelled: Bool) {
        let completion = lock.withLock { () -> (
            CheckedContinuation<Value, Never>?,
            (@MainActor @Sendable () -> Void)?
        )? in
            guard case .pending = state else { return nil }
            state = .completed(value, cancelled: cancelled)
            let continuation = self.continuation
            self.continuation = nil
            let cancellation = cancelled ? self.cancellation : nil
            self.cancellation = nil
            return (continuation, cancellation)
        }
        guard let completion else { return }
        if let cancellation = completion.1 {
            Task { @MainActor in
                cancellation()
            }
        }
        completion.0?.resume(returning: value)
    }
}

nonisolated final class DownloadableMediaFileRemovalToken:
    @unchecked Sendable {

    private enum RemovalClaim {
        case claimed(URL)
        case notRemoved
        case cancelled
    }

    enum RemovalResult: Equatable, Sendable {
        case removed
        case stagedForCleanup
        case notRemoved
        case cancelled

        var removedFromCache: Bool {
            self == .removed || self == .stagedForCleanup
        }

        var freedStorage: Bool {
            self == .removed
        }
    }

    struct PairRemovalResult: Equatable, Sendable {
        let primary: RemovalResult
        let sidecar: RemovalResult?
    }

    private let lock = NSLock()
    private let tombstoneDirectoryURL: URL?
    private let willClaimRemoval: @Sendable () -> Void
    private let didClaimRemoval: @Sendable () -> Void
    private let removeItem: @Sendable (URL) throws -> Void
    private var isCancelled = false

    init(
        tombstoneDirectoryURL: URL? = nil,
        willClaimRemoval: @escaping @Sendable () -> Void = {},
        didClaimRemoval: @escaping @Sendable () -> Void = {},
        removeItem: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        }
    ) {
        self.tombstoneDirectoryURL = tombstoneDirectoryURL
        self.willClaimRemoval = willClaimRemoval
        self.didClaimRemoval = didClaimRemoval
        self.removeItem = removeItem
    }

    var isActive: Bool {
        lock.withLock { !isCancelled }
    }

    func cancel() {
        lock.withLock { isCancelled = true }
    }

    func removeIfActive(at url: URL) -> RemovalResult {
        switch claimRemoval(at: url) {
        case let .claimed(tombstoneURL):
            return removeClaimedItem(at: tombstoneURL)
        case .notRemoved:
            return .notRemoved
        case .cancelled:
            return .cancelled
        }
    }

    func removePairIfActive(
        primaryURL: URL,
        sidecarURL: URL?
    ) -> PairRemovalResult {
        let primaryResult = removeIfActive(at: primaryURL)
        guard primaryResult.removedFromCache, let sidecarURL else {
            return PairRemovalResult(primary: primaryResult, sidecar: nil)
        }
        return PairRemovalResult(
            primary: primaryResult,
            sidecar: removeIfActive(at: sidecarURL)
        )
    }

    private func claimRemoval(at url: URL) -> RemovalClaim {
        lock.withLock {
            guard !isCancelled else { return .cancelled }
            willClaimRemoval()
            defer { didClaimRemoval() }
            let directoryURL = tombstoneDirectoryURL
                ?? url.deletingLastPathComponent()
            let tombstoneURL = directoryURL.appendingPathComponent(
                DownloadableMediaCacheLayout.fileRemovalTombstonePrefix
                    + UUID().uuidString
            )
            do {
                try FileManager.default.moveItem(at: url, to: tombstoneURL)
                return .claimed(tombstoneURL)
            } catch {
                return .notRemoved
            }
        }
    }

    private func removeClaimedItem(at tombstoneURL: URL) -> RemovalResult {
        do {
            try removeItem(tombstoneURL)
            return .removed
        } catch {
            return .stagedForCleanup
        }
    }
}

nonisolated protocol DownloadableMediaDownloading: Actor {
    func download(
        _ request: DownloadableMediaDownloadRequest
    ) async -> DownloadableMediaDownloadResult
    func setPriority(
        _ priority: Float,
        for requestID: UUID,
        revision: UInt64
    )
    func cancel(requestID: UUID)
    func cancelAll()
}

nonisolated protocol DownloadableMediaImageDecoding: Actor {
    func decode(
        at fileURL: URL,
        generation: DownloadableMediaImageDecodeGeneration
    ) async -> DownloadableMediaDecodedImageTransfer?
}

nonisolated protocol DownloadableMediaVariantImageDecoding:
    DownloadableMediaImageDecoding {
    func decode(
        at fileURL: URL,
        variant: DownloadableMediaImageDecodeVariant,
        generation: DownloadableMediaImageDecodeGeneration
    ) async -> DownloadableMediaDecodedImageTransfer?
}

extension DownloadableMediaVariantImageDecoding {
    func decode(
        at fileURL: URL,
        generation: DownloadableMediaImageDecodeGeneration
    ) async -> DownloadableMediaDecodedImageTransfer? {
        await decode(at: fileURL, variant: .full, generation: generation)
    }
}

@MainActor
final class DownloadableMediaAvailabilityPublisher {
    enum Scope: Sendable {
        case file(URL)
        case collection(URL)
        case all
    }

    private static let scopeUserInfoKey =
        "DownloadableMediaCacheFileAvailabilityScope"

    private let layout: DownloadableMediaCacheLayout
    private let notificationCenter: NotificationCenter

    init(
        layout: DownloadableMediaCacheLayout,
        notificationCenter: NotificationCenter = .default
    ) {
        self.layout = layout
        self.notificationCenter = notificationCenter
    }

    func post(
        _ change: DownloadableMediaCacheFileAvailabilityChange,
        scope: Scope = .all
    ) {
        Task { @MainActor [notificationCenter] in
            notificationCenter.post(
                name: .downloadableMediaCacheFileAvailabilityDidChange,
                object: change,
                userInfo: [Self.scopeUserInfoKey: scope]
            )
        }
    }

    func postDecodedImageAvailable(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        let availability = DownloadableMediaCacheDecodedImageAvailability(
            collectionId: descriptor.collectionId,
            tokenIndex: descriptor.tokenIndex
        )
        Task { @MainActor [notificationCenter] in
            notificationCenter.post(
                name: .downloadableMediaCacheDecodedImageDidBecomeAvailable,
                object: availability
            )
        }
    }

    func change(
        _ notification: Notification,
        affects descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> Bool {
        guard let scope = notification.userInfo?[Self.scopeUserInfoKey]
            as? Scope else {
            return true
        }
        switch scope {
        case let .file(fileURL):
            return fileURL.standardizedFileURL
                == layout.location(for: descriptor).mediaURL.standardizedFileURL
        case let .collection(directoryURL):
            return directoryURL.standardizedFileURL
                == layout.collectionDirectory(
                    collectionId: descriptor.collectionId
                ).standardizedFileURL
        case .all:
            return true
        }
    }

    func change(
        _ notification: Notification,
        affectsCollection collectionId: String
    ) -> Bool {
        guard let scope = notification.userInfo?[Self.scopeUserInfoKey]
            as? Scope else {
            return true
        }
        let directoryURL = layout.collectionDirectory(
            collectionId: collectionId
        ).standardizedFileURL
        switch scope {
        case let .file(fileURL):
            return fileURL.deletingLastPathComponent().standardizedFileURL
                == directoryURL
        case let .collection(changedDirectoryURL):
            return changedDirectoryURL.standardizedFileURL == directoryURL
        case .all:
            return true
        }
    }
}
