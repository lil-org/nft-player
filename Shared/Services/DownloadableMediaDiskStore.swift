// ∅ 2026 lil org

import Foundation

nonisolated struct DownloadableMediaDiskPreparation: Sendable {
    let cacheRoot: URL
    let stagingRoot: URL
    let fileRemovalTombstoneDirectoryURL: URL?
}

nonisolated struct DownloadableMediaDiskUnavailablePathClaim:
    Hashable, Sendable {

    let path: String
    let generation: UInt64
}

nonisolated struct DownloadableMediaDiskAvailabilitySnapshot: Sendable {
    let availability: DownloadableMediaFileAvailability
    let unavailablePathClaims: Set<DownloadableMediaDiskUnavailablePathClaim>
    let mutationGeneration: UInt64
}

nonisolated struct DownloadableMediaDiskURLAvailabilitySnapshot: Sendable {
    let checkedURLs: Set<URL>
    let availableURLs: Set<URL>
    let unavailablePathClaims: Set<DownloadableMediaDiskUnavailablePathClaim>
    let mutationGeneration: UInt64
}

nonisolated struct DownloadableMediaDiskFinalization: Sendable {
    let succeeded: Bool
    let didRemoveExistingItem: Bool
    let cacheBytes: Int64
    let mediaURL: URL
    let mutationGeneration: UInt64
}

nonisolated struct DownloadableMediaDiskRemoval: Sendable {
    let mediaURL: URL
    let result: DownloadableMediaFileRemovalToken.PairRemovalResult
    let mediaURLIsUnavailable: Bool
    let mutationGeneration: UInt64

    var didRemoveItem: Bool {
        result.primary.removedFromCache
            || result.sidecar?.removedFromCache == true
    }
}

nonisolated struct DownloadableMediaDiskEvictionResult: Sendable {
    let collectionDirectoryURL: URL
    let didRemoveItem: Bool
    let removedMediaURLs: Set<URL>
    let wasCancelled: Bool
    let mutationGeneration: UInt64
}

nonisolated enum DownloadableMediaDiskPruneReason: Sendable {
    case routine
    case afterWrite
}

nonisolated struct DownloadableMediaDiskPruneResult: Sendable {
    let didRun: Bool
    let wasCurrent: Bool
    let didRemoveItem: Bool
    let removedMediaURLs: Set<URL>
    let cacheBytesAfterPrune: Int64
    let availableDiskBytesAfterPrune: Int64?
    let mutationGeneration: UInt64
}

nonisolated struct DownloadableMediaDiskEstimate: Sendable {
    let cacheBytes: Int64?
    let availableDiskBytes: Int64?
    let bytesAddedSinceEstimate: Int64
}

nonisolated private struct DownloadableMediaDiskMetadata: Codable, Sendable {
    let sourceURL: URL
}

nonisolated private struct DownloadableMediaDiskPruneFile: Sendable {
    let url: URL
    let size: Int64
}

nonisolated private struct DownloadableMediaDiskPruneCandidate: Sendable {
    let paths: Set<String>
    let primaryFile: DownloadableMediaDiskPruneFile
    let sidecarFile: DownloadableMediaDiskPruneFile?
    let requiredMissingURL: URL?
    let unavailableMediaURL: URL?
}

nonisolated private struct DownloadableMediaDiskPruneRemovalResult: Sendable {
    let wasCurrent: Bool
    let processedCandidateCount: Int
    let didRemoveItem: Bool
    let removedMediaURLs: Set<URL>
    let removedCacheBytes: Int64
    let freedDiskBytes: Int64
    let fileStateGeneration: UInt64
}

nonisolated private struct DownloadableMediaDiskPruneContext: Sendable {
    let id: UUID
    let mutationGeneration: UInt64
    let fileStateGeneration: UInt64
    let requestedProtectedPaths: Set<String>
    let token: DownloadableMediaFileRemovalToken
}

nonisolated private struct DownloadableMediaDiskPruneCompletion: Sendable {
    let wasCurrent: Bool
    let fileStateGeneration: UInt64
}

nonisolated private struct DownloadableMediaDiskFileSnapshot: Sendable {
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let contentAccessDate: Date?
    let contentModificationDate: Date?

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .contentAccessDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
        ])
        self.url = url
        isDirectory = values?.isDirectory == true
        size = Int64(values?.fileSize ?? 0)
        contentAccessDate = values?.contentAccessDate
        contentModificationDate = values?.contentModificationDate
    }
}

nonisolated private struct DownloadableMediaDiskCacheEntry: Sendable {
    let mediaURL: URL
    let metadataURL: URL?
    let paths: Set<String>
    let mediaSize: Int64
    let metadataSize: Int64
    let lastAccessDate: Date

    var size: Int64 {
        mediaSize + metadataSize
    }
}

nonisolated private struct DownloadableMediaDiskOrphanMetadataEntry: Sendable {
    let url: URL
    let mediaURL: URL
    let path: String
    let size: Int64
}

nonisolated private struct DownloadableMediaDiskCacheSnapshot: Sendable {
    let entries: [DownloadableMediaDiskCacheEntry]
    let orphanMetadataEntries: [DownloadableMediaDiskOrphanMetadataEntry]
}

nonisolated private struct DownloadableMediaDiskMediaPairRemoval: Sendable {
    let result: DownloadableMediaFileRemovalToken.PairRemovalResult
    let unavailablePathClaim: DownloadableMediaDiskUnavailablePathClaim?
}

nonisolated private final class DownloadableMediaDiskAvailabilityGate:
    @unchecked Sendable {

    private let lock = NSLock()
    private var unavailableGenerations = [String: UInt64]()
    private var nextGeneration: UInt64 = 0

    func markUnavailable(
        _ path: String
    ) -> DownloadableMediaDiskUnavailablePathClaim {
        lock.withLock {
            nextGeneration &+= 1
            unavailableGenerations[path] = nextGeneration
            return DownloadableMediaDiskUnavailablePathClaim(
                path: path,
                generation: nextGeneration
            )
        }
    }

    func markAvailable(_ path: String) {
        lock.withLock {
            _ = unavailableGenerations.removeValue(forKey: path)
        }
    }

    func restoreAvailable(
        for claim: DownloadableMediaDiskUnavailablePathClaim
    ) {
        lock.withLock {
            guard unavailableGenerations[claim.path] == claim.generation else {
                return
            }
            _ = unavailableGenerations.removeValue(forKey: claim.path)
        }
    }

    func isUnavailable(_ path: String) -> Bool {
        lock.withLock { unavailableGenerations[path] != nil }
    }

    func acknowledge(
        _ claims: Set<DownloadableMediaDiskUnavailablePathClaim>
    ) {
        lock.withLock {
            for claim in claims
            where unavailableGenerations[claim.path] == claim.generation {
                _ = unavailableGenerations.removeValue(forKey: claim.path)
            }
        }
    }
}

nonisolated private final class DownloadableMediaDiskPruneGate:
    @unchecked Sendable {

    private let lock = NSLock()
    private weak var token: DownloadableMediaFileRemovalToken?
    private var epoch: UInt64 = 0

    func activate(
        _ token: DownloadableMediaFileRemovalToken,
        expectedEpoch: UInt64
    ) -> Bool {
        lock.withLock {
            guard epoch == expectedEpoch else { return false }
            self.token?.cancel()
            self.token = token
            return true
        }
    }

    func cancel() {
        lock.withLock {
            epoch &+= 1
            token?.cancel()
            token = nil
        }
    }

    func snapshot() -> UInt64 {
        lock.withLock { epoch }
    }

    func clear(_ token: DownloadableMediaFileRemovalToken) {
        lock.withLock {
            guard self.token === token else { return }
            self.token = nil
        }
    }
}

nonisolated private final class DownloadableMediaDiskProtectionGate:
    @unchecked Sendable {

    private let lock = NSLock()
    private var paths = Set<String>()
    private var revision: UInt64 = 0

    func update(_ paths: Set<String>, revision: UInt64) -> Bool {
        lock.withLock {
            guard revision >= self.revision else { return false }
            self.revision = revision
            guard self.paths != paths else { return false }
            self.paths = paths
            return true
        }
    }

    func snapshot() -> Set<String> {
        lock.withLock { paths }
    }
}

nonisolated final class DownloadableMediaFileStateRevision:
    @unchecked Sendable {

    private let lock = NSLock()
    private var value: UInt64 = 0

    func invalidate() {
        lock.withLock { value &+= 1 }
    }

    func snapshot() -> UInt64 {
        lock.withLock { value }
    }

    func withCurrent(
        _ expectedValue: UInt64,
        perform: () -> Void
    ) -> Bool {
        lock.withLock {
            guard value == expectedValue else { return false }
            perform()
            return true
        }
    }
}

actor DownloadableMediaDiskStore {
    private struct ActivePrune {
        let context: DownloadableMediaDiskPruneContext
    }

    let layout: DownloadableMediaCacheLayout

    private nonisolated let pruneGate = DownloadableMediaDiskPruneGate()
    private nonisolated let protectionGate =
        DownloadableMediaDiskProtectionGate()
    private nonisolated let availabilityGate =
        DownloadableMediaDiskAvailabilityGate()
    nonisolated let fileStateRevision =
        DownloadableMediaFileStateRevision()
    private let processTombstoneDirectoryName = UUID().uuidString
    private var preparation: DownloadableMediaDiskPreparation?
    private var mutationGeneration: UInt64 = 0
    private var activePrune: ActivePrune?

#if os(iOS) || os(macOS)
    private static let cachedFileTouchDebounceInterval: Duration = .seconds(2)
    private static let cachedFileTouchMinimumInterval: TimeInterval = 30
    private static let cachedFileTouchHistoryLimit = 4096
    private var pendingCachedFileTouchURLs = [String: URL]()
    private var cachedFileTouchDates = [String: Date]()
    private var cachedFileTouchTask: Task<Void, Never>?
#endif

    init(layout: DownloadableMediaCacheLayout) {
        self.layout = layout
    }

    func prepare() -> DownloadableMediaDiskPreparation {
        prepareIfNeeded()
    }

    nonisolated func isMediaURLUnavailable(_ mediaURL: URL) -> Bool {
        availabilityGate.isUnavailable(mediaURL.standardizedFileURL.path)
    }

    nonisolated func acknowledgeUnavailablePaths(
        _ claims: Set<DownloadableMediaDiskUnavailablePathClaim>
    ) {
        availabilityGate.acknowledge(claims)
    }

    func availability(
        for locations: [DownloadableMediaDiskLocation]
    ) -> DownloadableMediaFileAvailability {
        availabilitySnapshot(for: locations).availability
    }

    func availabilitySnapshot(
        for locations: [DownloadableMediaDiskLocation]
    ) -> DownloadableMediaDiskAvailabilitySnapshot {
        _ = prepareIfNeeded()
        let fileManager = FileManager.default
        var checkedKeys = Set<String>()
        var availableKeys = Set<String>()
        var unavailablePathClaims =
            Set<DownloadableMediaDiskUnavailablePathClaim>()
        for location in locations {
            guard !Task.isCancelled else { break }
            checkedKeys.insert(location.key)
            let path = layout.diskPath(for: location.mediaURL)
            if fileManager.fileExists(atPath: location.mediaURL.path) {
                availableKeys.insert(location.key)
                availabilityGate.markAvailable(path)
            } else {
                unavailablePathClaims.insert(
                    availabilityGate.markUnavailable(path)
                )
            }
        }
        return DownloadableMediaDiskAvailabilitySnapshot(
            availability: DownloadableMediaFileAvailability(
                checkedKeys: checkedKeys,
                availableKeys: availableKeys
            ),
            unavailablePathClaims: unavailablePathClaims,
            mutationGeneration: fileStateRevision.snapshot()
        )
    }

    func availabilitySnapshot(
        forMediaURLs mediaURLs: Set<URL>
    ) -> DownloadableMediaDiskURLAvailabilitySnapshot {
        _ = prepareIfNeeded()
        let fileManager = FileManager.default
        var checkedURLs = Set<URL>()
        var availableURLs = Set<URL>()
        var unavailablePathClaims =
            Set<DownloadableMediaDiskUnavailablePathClaim>()
        for mediaURL in mediaURLs {
            let standardizedURL = mediaURL.standardizedFileURL
            let path = layout.diskPath(for: standardizedURL)
            checkedURLs.insert(standardizedURL)
            if fileManager.fileExists(atPath: standardizedURL.path) {
                availableURLs.insert(standardizedURL)
                availabilityGate.markAvailable(path)
            } else {
                unavailablePathClaims.insert(
                    availabilityGate.markUnavailable(path)
                )
            }
        }
        return DownloadableMediaDiskURLAvailabilitySnapshot(
            checkedURLs: checkedURLs,
            availableURLs: availableURLs,
            unavailablePathClaims: unavailablePathClaims,
            mutationGeneration: fileStateRevision.snapshot()
        )
    }

    nonisolated func isMutationGenerationCurrent(
        _ generation: UInt64
    ) -> Bool {
        fileStateRevision.snapshot() == generation
    }

    func currentMutationGeneration() -> UInt64 {
        mutationGeneration
    }

    func existingFileURL(
        at location: DownloadableMediaDiskLocation,
        recordsAccess: Bool = true
    ) -> URL? {
        _ = prepareIfNeeded()
        let path = layout.diskPath(for: location.mediaURL)
        guard FileManager.default.fileExists(atPath: location.mediaURL.path) else {
            _ = availabilityGate.markUnavailable(path)
            return nil
        }
        availabilityGate.markAvailable(path)
#if os(iOS) || os(macOS)
        if recordsAccess {
            scheduleCachedFileTouch(at: location.mediaURL)
        }
#endif
        return location.mediaURL
    }

    func sourceURL(at location: DownloadableMediaDiskLocation) -> URL? {
        _ = prepareIfNeeded()
        guard let data = try? Data(contentsOf: location.metadataURL),
              let metadata = try? JSONDecoder().decode(
                  DownloadableMediaDiskMetadata.self,
                  from: data
              ) else {
            return nil
        }
        return metadata.sourceURL
    }

    func finalizeDownload(
        at stagedURL: URL,
        location: DownloadableMediaDiskLocation,
        sourceURL: URL
    ) -> DownloadableMediaDiskFinalization {
        _ = prepareIfNeeded()
        beginForegroundMutation()
        let fileManager = FileManager.default
        let mediaPath = layout.diskPath(for: location.mediaURL)
        var didRemoveExistingItem = false
        var didClearMediaPath = false
        var unavailablePathClaim:
            DownloadableMediaDiskUnavailablePathClaim?

        do {
            try fileManager.createDirectory(
                at: location.collectionDirectoryURL,
                withIntermediateDirectories: true
            )
            unavailablePathClaim = availabilityGate.markUnavailable(mediaPath)
            do {
                try fileManager.removeItem(at: location.mediaURL)
                didRemoveExistingItem = true
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError {}
            didClearMediaPath = true

            let metadataBytes: Int64
            do {
                let metadata = DownloadableMediaDiskMetadata(sourceURL: sourceURL)
                let data = try JSONEncoder().encode(metadata)
                try data.write(to: location.metadataURL, options: .atomic)
                metadataBytes = fileSize(at: location.metadataURL)
            } catch {
                try? fileManager.removeItem(at: location.metadataURL)
                metadataBytes = 0
            }

            try fileManager.moveItem(at: stagedURL, to: location.mediaURL)
            availabilityGate.markAvailable(mediaPath)
            return DownloadableMediaDiskFinalization(
                succeeded: true,
                didRemoveExistingItem: didRemoveExistingItem,
                cacheBytes: fileSize(at: location.mediaURL) + metadataBytes,
                mediaURL: location.mediaURL,
                mutationGeneration: fileStateRevision.snapshot()
            )
        } catch {
            if fileManager.fileExists(atPath: location.mediaURL.path) {
                availabilityGate.markAvailable(mediaPath)
            } else if unavailablePathClaim == nil {
                unavailablePathClaim = availabilityGate.markUnavailable(
                    mediaPath
                )
            }
            if didClearMediaPath {
                try? fileManager.removeItem(at: location.metadataURL)
            }
            try? fileManager.removeItem(at: stagedURL)
            return DownloadableMediaDiskFinalization(
                succeeded: false,
                didRemoveExistingItem: didRemoveExistingItem,
                cacheBytes: 0,
                mediaURL: location.mediaURL,
                mutationGeneration: fileStateRevision.snapshot()
            )
        }
    }

    func removeCorruptFile(
        at location: DownloadableMediaDiskLocation,
        token requestedToken: DownloadableMediaFileRemovalToken? = nil
    ) -> DownloadableMediaDiskRemoval {
        removePair(at: location, token: requestedToken)
    }

    func removePair(
        at location: DownloadableMediaDiskLocation,
        token requestedToken: DownloadableMediaFileRemovalToken? = nil
    ) -> DownloadableMediaDiskRemoval {
        _ = prepareIfNeeded()
        beginForegroundMutation()
        let token = requestedToken ?? makeRemovalTokenAfterPreparation()
        let removal = removeMediaPair(
            mediaURL: location.mediaURL,
            metadataURL: location.metadataURL,
            token: token
        )
        return DownloadableMediaDiskRemoval(
            mediaURL: location.mediaURL,
            result: removal.result,
            mediaURLIsUnavailable:
                removal.unavailablePathClaim != nil,
            mutationGeneration: fileStateRevision.snapshot()
        )
    }

    func discardStagedFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func makeRemovalToken() -> DownloadableMediaFileRemovalToken {
        _ = prepareIfNeeded()
        return makeRemovalTokenAfterPreparation()
    }

    func cleanupRemovalTombstones() {
        let preparation = prepareIfNeeded()
        if let tombstoneDirectoryURL = preparation.fileRemovalTombstoneDirectoryURL {
            removeContents(of: tombstoneDirectoryURL)
        }
        removeFallbackTombstones(at: layout.cacheRoot)
    }

    nonisolated func setProtectedPaths(
        _ paths: Set<String>,
        revision: UInt64
    ) {
        if protectionGate.update(paths, revision: revision) {
            pruneGate.cancel()
        }
    }

    nonisolated func cancelPrune() {
        pruneGate.cancel()
    }

    nonisolated func pruneCancellationEpoch() -> UInt64 {
        pruneGate.snapshot()
    }

    func touch(_ location: DownloadableMediaDiskLocation) {
#if os(iOS) || os(macOS)
        scheduleCachedFileTouch(at: location.mediaURL)
#endif
    }

    func evictFilesOutsideWindow(
        collectionId: String,
        protectedFileNames: Set<String>,
        token requestedToken: DownloadableMediaFileRemovalToken? = nil
    ) -> DownloadableMediaDiskEvictionResult {
        _ = prepareIfNeeded()
        cleanupRemovalTombstones()
        beginForegroundMutation()
        let directoryURL = layout.collectionDirectory(collectionId: collectionId)
        let token = requestedToken ?? makeRemovalTokenAfterPreparation()
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return DownloadableMediaDiskEvictionResult(
                collectionDirectoryURL: directoryURL,
                didRemoveItem: false,
                removedMediaURLs: [],
                wasCancelled: !token.isActive,
                mutationGeneration: fileStateRevision.snapshot()
            )
        }

        let urlsByName = Dictionary(uniqueKeysWithValues: contents.map {
            ($0.lastPathComponent, $0)
        })
        let metadataSuffix = DownloadableMediaCacheLayout.downloadedMediaMetadataFileSuffix
        let mediaURLs = contents
            .filter { !$0.lastPathComponent.hasSuffix(metadataSuffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var didRemoveItem = false
        var removedMediaURLs = Set<URL>()
        var wasCancelled = false

        for mediaURL in mediaURLs {
            let mediaFileName = mediaURL.lastPathComponent
            let metadataFileName = mediaFileName + metadataSuffix
            guard !protectedFileNames.contains(mediaFileName),
                  !protectedFileNames.contains(metadataFileName) else {
                continue
            }
            let mediaRemoval = removeMediaPair(
                mediaURL: mediaURL,
                metadataURL: urlsByName[metadataFileName],
                token: token
            )
            let removal = mediaRemoval.result
            if mediaRemoval.unavailablePathClaim != nil {
                removedMediaURLs.insert(mediaURL.standardizedFileURL)
            }
            switch removal.primary {
            case .removed, .stagedForCleanup:
                didRemoveItem = true
            case .notRemoved:
                continue
            case .cancelled:
                wasCancelled = true
            }
            if wasCancelled {
                break
            }
        }

        if !wasCancelled {
            let mediaFileNames = Set(mediaURLs.map(\.lastPathComponent))
            let orphanMetadataURLs = contents
                .filter { $0.lastPathComponent.hasSuffix(metadataSuffix) }
                .filter { metadataURL in
                    let mediaFileName = String(
                        metadataURL.lastPathComponent.dropLast(metadataSuffix.count)
                    )
                    return !mediaFileNames.contains(mediaFileName)
                        && !protectedFileNames.contains(mediaFileName)
                        && !protectedFileNames.contains(metadataURL.lastPathComponent)
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for metadataURL in orphanMetadataURLs {
                switch token.removeIfActive(at: metadataURL) {
                case .removed, .stagedForCleanup:
                    didRemoveItem = true
                case .notRemoved:
                    continue
                case .cancelled:
                    wasCancelled = true
                }
                if wasCancelled {
                    break
                }
            }
        }

        return DownloadableMediaDiskEvictionResult(
            collectionDirectoryURL: directoryURL,
            didRemoveItem: didRemoveItem,
            removedMediaURLs: removedMediaURLs,
            wasCancelled: wasCancelled,
            mutationGeneration: fileStateRevision.snapshot()
        )
    }

    private func prepareIfNeeded() -> DownloadableMediaDiskPreparation {
        if let preparation {
            return preparation
        }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: layout.cacheRoot,
            withIntermediateDirectories: true
        )

        var cacheRoot = layout.cacheRoot
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? cacheRoot.setResourceValues(resourceValues)
        try? fileManager.removeItem(at: layout.webViewHTMLDirectoryURL)

        let trashDirectoryURL = layout.fileRemovalTrashDirectoryURL
        let requestedTombstoneDirectoryURL = trashDirectoryURL.appendingPathComponent(
            processTombstoneDirectoryName,
            isDirectory: true
        )
        let tombstoneDirectoryURL: URL?
        do {
            try fileManager.createDirectory(
                at: requestedTombstoneDirectoryURL,
                withIntermediateDirectories: true
            )
            tombstoneDirectoryURL = requestedTombstoneDirectoryURL
        } catch {
            tombstoneDirectoryURL = nil
        }

        removeStaleTrash(
            at: trashDirectoryURL,
            keeping: tombstoneDirectoryURL
        )
        removeFallbackTombstones(at: layout.cacheRoot)

#if os(macOS)
        try? fileManager.removeItem(
            at: layout.cacheRoot.appendingPathComponent(
                ".DiskPruneTrash",
                isDirectory: true
            )
        )
#elseif os(tvOS) || os(visionOS)
        try? fileManager.removeItem(
            at: layout.cacheRoot.appendingPathComponent(
                ".FileEvictionTrash",
                isDirectory: true
            )
        )
#endif

        let result = DownloadableMediaDiskPreparation(
            cacheRoot: layout.cacheRoot,
            stagingRoot: layout.stagingRoot,
            fileRemovalTombstoneDirectoryURL: tombstoneDirectoryURL
        )
        preparation = result
        return result
    }

    private func beginForegroundMutation() {
        cancelActivePrune(incrementsGeneration: false)
        mutationGeneration &+= 1
        fileStateRevision.invalidate()
    }

    private func cancelActivePrune(incrementsGeneration: Bool) {
        guard let activePrune else { return }
        activePrune.context.token.cancel()
        pruneGate.clear(activePrune.context.token)
        self.activePrune = nil
        if incrementsGeneration {
            mutationGeneration &+= 1
        }
    }

    private func makeRemovalTokenAfterPreparation() -> DownloadableMediaFileRemovalToken {
        DownloadableMediaFileRemovalToken(
            tombstoneDirectoryURL: preparation?.fileRemovalTombstoneDirectoryURL
        )
    }

    private func removeMediaPair(
        mediaURL: URL,
        metadataURL: URL?,
        token: DownloadableMediaFileRemovalToken
    ) -> DownloadableMediaDiskMediaPairRemoval {
        let mediaPath = layout.diskPath(for: mediaURL)
        let claim = availabilityGate.markUnavailable(mediaPath)
        let result = token.removePairIfActive(
            primaryURL: mediaURL,
            sidecarURL: metadataURL
        )
        if result.primary.removedFromCache
            || !FileManager.default.fileExists(atPath: mediaURL.path) {
            return DownloadableMediaDiskMediaPairRemoval(
                result: result,
                unavailablePathClaim: claim
            )
        }
        availabilityGate.restoreAvailable(for: claim)
        return DownloadableMediaDiskMediaPairRemoval(
            result: result,
            unavailablePathClaim: nil
        )
    }

    private func removeContents(of directoryURL: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeStaleTrash(at directoryURL: URL, keeping keptURL: URL?) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let standardizedKeptURL = keptURL?.standardizedFileURL
        for url in contents where url.standardizedFileURL != standardizedKeptURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeFallbackTombstones(at rootURL: URL) {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return
        }
        for directoryURL in directories {
            guard (try? directoryURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) == true,
                  let contents = try? fileManager.contentsOfDirectory(
                      at: directoryURL,
                      includingPropertiesForKeys: nil
                  ) else {
                continue
            }
            for url in contents where url.lastPathComponent.hasPrefix(
                DownloadableMediaCacheLayout.fileRemovalTombstonePrefix
            ) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

#if os(iOS) || os(macOS)
    private func scheduleCachedFileTouch(at url: URL) {
        let path = layout.diskPath(for: url)
        let now = Date()
        if let lastTouchDate = cachedFileTouchDates[path],
           now.timeIntervalSince(lastTouchDate)
               < Self.cachedFileTouchMinimumInterval {
            return
        }

        pendingCachedFileTouchURLs[path] = url
        guard cachedFileTouchTask == nil else { return }

        cachedFileTouchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.cachedFileTouchDebounceInterval)
            guard !Task.isCancelled else { return }
            await self?.flushCachedFileTouches()
        }
    }

    private func flushCachedFileTouches() {
        cachedFileTouchTask = nil
        let pendingTouches = pendingCachedFileTouchURLs
        pendingCachedFileTouchURLs.removeAll(keepingCapacity: true)
        guard !pendingTouches.isEmpty else { return }

        let now = Date()
        for (path, url) in pendingTouches {
            cachedFileTouchDates[path] = now
            var mutableURL = url
            var values = URLResourceValues()
            values.contentAccessDate = now
            try? mutableURL.setResourceValues(values)
        }

        guard cachedFileTouchDates.count > Self.cachedFileTouchHistoryLimit else {
            return
        }
        cachedFileTouchDates = Dictionary(uniqueKeysWithValues: cachedFileTouchDates
            .sorted { $0.value > $1.value }
            .prefix(Self.cachedFileTouchHistoryLimit)
            .map { ($0.key, $0.value) })
    }
#endif

    fileprivate func beginPrune(
        protectedPaths requestedProtectedPaths: Set<String>,
        cancellationEpoch: UInt64
    ) -> DownloadableMediaDiskPruneContext {
        _ = prepareIfNeeded()
        cancelActivePrune(incrementsGeneration: false)
        let context = DownloadableMediaDiskPruneContext(
            id: UUID(),
            mutationGeneration: mutationGeneration,
            fileStateGeneration: fileStateRevision.snapshot(),
            requestedProtectedPaths: requestedProtectedPaths,
            token: makeRemovalTokenAfterPreparation()
        )
        guard pruneGate.activate(
            context.token,
            expectedEpoch: cancellationEpoch
        ) else {
            context.token.cancel()
            return context
        }
        activePrune = ActivePrune(context: context)
        return context
    }

    fileprivate func removePruneCandidates(
        _ candidates: [DownloadableMediaDiskPruneCandidate],
        removalByteTarget: Int64?,
        maximumFileCount: Int,
        context: DownloadableMediaDiskPruneContext
    ) -> DownloadableMediaDiskPruneRemovalResult {
        guard isCurrent(context) else {
            return DownloadableMediaDiskPruneRemovalResult(
                wasCurrent: false,
                processedCandidateCount: 0,
                didRemoveItem: false,
                removedMediaURLs: [],
                removedCacheBytes: 0,
                freedDiskBytes: 0,
                fileStateGeneration: fileStateRevision.snapshot()
            )
        }

        let effectiveProtectedPaths = protectionGate.snapshot()
            .union(context.requestedProtectedPaths)
        var processedCandidateCount = 0
        var removedFileCount = 0
        var removedMediaURLs = Set<URL>()
        var removedCacheBytes: Int64 = 0
        var freedDiskBytes: Int64 = 0

        for candidate in candidates {
            if let removalByteTarget,
               removedCacheBytes >= removalByteTarget {
                break
            }
            processedCandidateCount += 1
            guard candidate.paths.isDisjoint(with: effectiveProtectedPaths) else {
                continue
            }
            if let requiredMissingURL = candidate.requiredMissingURL,
               FileManager.default.fileExists(atPath: requiredMissingURL.path) {
                continue
            }
            guard removedFileCount < maximumFileCount else { break }

            let canRemoveSidecar = removedFileCount + 1 < maximumFileCount
            let removal: DownloadableMediaFileRemovalToken.PairRemovalResult
            if let mediaURL = candidate.unavailableMediaURL {
                let mediaRemoval = removeMediaPair(
                    mediaURL: mediaURL,
                    metadataURL: canRemoveSidecar
                        ? candidate.sidecarFile?.url
                        : nil,
                    token: context.token
                )
                removal = mediaRemoval.result
                if mediaRemoval.unavailablePathClaim != nil {
                    removedMediaURLs.insert(mediaURL.standardizedFileURL)
                }
            } else {
                removal = context.token.removePairIfActive(
                    primaryURL: candidate.primaryFile.url,
                    sidecarURL: nil
                )
            }
            switch removal.primary {
            case .cancelled:
                return DownloadableMediaDiskPruneRemovalResult(
                    wasCurrent: false,
                    processedCandidateCount: processedCandidateCount,
                    didRemoveItem: removedFileCount > 0,
                    removedMediaURLs: removedMediaURLs,
                    removedCacheBytes: removedCacheBytes,
                    freedDiskBytes: freedDiskBytes,
                    fileStateGeneration: recordPruneFileStateMutation(
                        didRemoveItem: removedFileCount > 0
                    )
                )
            case .notRemoved:
                continue
            case .removed:
                removedFileCount += 1
                removedCacheBytes += candidate.primaryFile.size
                freedDiskBytes += candidate.primaryFile.size
            case .stagedForCleanup:
                removedFileCount += 1
                removedCacheBytes += candidate.primaryFile.size
            }

            if let sidecarRemoval = removal.sidecar,
               sidecarRemoval.removedFromCache,
               let sidecarFile = candidate.sidecarFile {
                removedFileCount += 1
                removedCacheBytes += sidecarFile.size
                if sidecarRemoval.freedStorage {
                    freedDiskBytes += sidecarFile.size
                }
            }
        }

        let didRemoveItem = removedFileCount > 0
        return DownloadableMediaDiskPruneRemovalResult(
            wasCurrent: isCurrent(context),
            processedCandidateCount: processedCandidateCount,
            didRemoveItem: didRemoveItem,
            removedMediaURLs: removedMediaURLs,
            removedCacheBytes: removedCacheBytes,
            freedDiskBytes: freedDiskBytes,
            fileStateGeneration: recordPruneFileStateMutation(
                didRemoveItem: didRemoveItem
            )
        )
    }

    fileprivate func finishPrune(
        _ context: DownloadableMediaDiskPruneContext
    ) -> DownloadableMediaDiskPruneCompletion {
        let wasCurrent = isCurrent(context)
        if activePrune?.context.id == context.id {
            activePrune = nil
        }
        pruneGate.clear(context.token)
        return DownloadableMediaDiskPruneCompletion(
            wasCurrent: wasCurrent,
            fileStateGeneration: fileStateRevision.snapshot()
        )
    }

    private func recordPruneFileStateMutation(
        didRemoveItem: Bool
    ) -> UInt64 {
        if didRemoveItem {
            fileStateRevision.invalidate()
        }
        return fileStateRevision.snapshot()
    }

    private func isCurrent(_ context: DownloadableMediaDiskPruneContext) -> Bool {
        activePrune?.context.id == context.id
            && activePrune?.context.token === context.token
            && mutationGeneration == context.mutationGeneration
            && context.token.isActive
    }
}

actor DownloadableMediaDiskPruner {
    private struct Request {
        var bypassesRoutineThrottle: Bool
        var additionalProtectedPaths: Set<String>
        var cancellationEpoch: UInt64

        mutating func merge(_ other: Request) {
            bypassesRoutineThrottle = bypassesRoutineThrottle
                || other.bypassesRoutineThrottle
            additionalProtectedPaths.formUnion(
                other.additionalProtectedPaths
            )
            cancellationEpoch = max(
                cancellationEpoch,
                other.cancellationEpoch
            )
        }
    }

    private static let maximumDiskCacheBytes: Int64 = 10 * 1024 * 1024 * 1024
    private static let targetDiskCacheBytes: Int64 = 8 * 1024 * 1024 * 1024
    private static let minimumAvailableDiskBytes: Int64 = 1 * 1024 * 1024 * 1024
    private static let checkDebounceInterval: Duration = .seconds(2)
    private static let routineCheckInterval: TimeInterval = 60
    private static let candidateBatchSize = 16
    private static let maximumRemovalFileCount = 32
#if os(macOS)
    private static let maximumMutationDeferralInterval: Duration = .seconds(10)
#endif

    let layout: DownloadableMediaCacheLayout
    let store: DownloadableMediaDiskStore

    private var pendingRequest: Request?
    private var scheduleGeneration: UInt64 = 0
    private var lastRoutineCheckDate: Date?
    private var isRunning = false
    private var estimatedCacheBytes: Int64?
    private var estimatedAvailableDiskBytes: Int64?
    private var bytesAddedSinceEstimate: Int64 = 0

    init(
        layout: DownloadableMediaCacheLayout,
        store: DownloadableMediaDiskStore
    ) {
        self.layout = layout
        self.store = store
    }

    func estimate() -> DownloadableMediaDiskEstimate {
        DownloadableMediaDiskEstimate(
            cacheBytes: estimatedCacheBytes,
            availableDiskBytes: estimatedAvailableDiskBytes,
            bytesAddedSinceEstimate: bytesAddedSinceEstimate
        )
    }

    func invalidateEstimatedState() {
        estimatedCacheBytes = nil
        estimatedAvailableDiskBytes = nil
        bytesAddedSinceEstimate = 0
    }

    func cancelScheduledPrune() async {
        scheduleGeneration &+= 1
        pendingRequest = nil
        store.cancelPrune()
    }

    func recordWrite(
        cacheBytes: Int64,
        protecting additionalProtectedPaths: Set<String>
    ) async -> DownloadableMediaDiskPruneResult {
        bytesAddedSinceEstimate = addingWithoutOverflow(
            bytesAddedSinceEstimate,
            max(cacheBytes, 0)
        )
        guard shouldSchedulePostWritePrune() else {
            return skippedResult()
        }
        return await prune(
            protecting: additionalProtectedPaths,
            reason: .afterWrite
        )
    }

    func prune(
        protecting additionalProtectedPaths: Set<String>,
        reason: DownloadableMediaDiskPruneReason = .routine
    ) async -> DownloadableMediaDiskPruneResult {
        let request = Request(
            bypassesRoutineThrottle: reason == .afterWrite,
            additionalProtectedPaths: additionalProtectedPaths,
            cancellationEpoch: store.pruneCancellationEpoch()
        )
        if var pendingRequest {
            pendingRequest.merge(request)
            self.pendingRequest = pendingRequest
        } else {
            pendingRequest = request
        }

        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        try? await Task.sleep(for: Self.checkDebounceInterval)
        guard generation == scheduleGeneration,
              !isRunning,
              let request = pendingRequest else {
            return skippedResult()
        }
        pendingRequest = nil
        guard consumeRoutineThrottle(for: request) else {
            return skippedResult()
        }

        isRunning = true
        var result = await performPruneWithMutationRetry(
            additionalProtectedPaths: request.additionalProtectedPaths,
            cancellationGeneration: generation,
            cancellationEpoch: request.cancellationEpoch
        )
#if !os(macOS)
        if !result.wasCurrent,
           generation == scheduleGeneration,
           !Task.isCancelled {
            pendingRequest = Request(
                bypassesRoutineThrottle: true,
                additionalProtectedPaths: request.additionalProtectedPaths,
                cancellationEpoch: store.pruneCancellationEpoch()
            )
            scheduleGeneration &+= 1
        }
#endif
        while pendingRequest != nil {
            let pendingGeneration = scheduleGeneration
            try? await Task.sleep(for: Self.checkDebounceInterval)
            guard pendingGeneration == scheduleGeneration,
                  let nextRequest = pendingRequest else {
                continue
            }
            pendingRequest = nil
            guard consumeRoutineThrottle(for: nextRequest) else {
                continue
            }
            let nextResult = await performPruneWithMutationRetry(
                additionalProtectedPaths:
                    nextRequest.additionalProtectedPaths,
                cancellationGeneration: pendingGeneration,
                cancellationEpoch: nextRequest.cancellationEpoch
            )
            result = DownloadableMediaDiskPruneResult(
                didRun: result.didRun || nextResult.didRun,
                wasCurrent: nextResult.wasCurrent,
                didRemoveItem: result.didRemoveItem
                    || nextResult.didRemoveItem,
                removedMediaURLs: result.removedMediaURLs.union(
                    nextResult.removedMediaURLs
                ),
                cacheBytesAfterPrune: nextResult.cacheBytesAfterPrune,
                availableDiskBytesAfterPrune:
                    nextResult.availableDiskBytesAfterPrune,
                mutationGeneration: nextResult.mutationGeneration
            )
#if !os(macOS)
            if !nextResult.wasCurrent,
               pendingGeneration == scheduleGeneration,
               !Task.isCancelled {
                pendingRequest = Request(
                    bypassesRoutineThrottle: true,
                    additionalProtectedPaths:
                        nextRequest.additionalProtectedPaths,
                    cancellationEpoch: store.pruneCancellationEpoch()
                )
                scheduleGeneration &+= 1
            }
#endif
        }
        isRunning = false

        if result.wasCurrent {
            estimatedCacheBytes = result.cacheBytesAfterPrune
            estimatedAvailableDiskBytes = result.availableDiskBytesAfterPrune
            bytesAddedSinceEstimate = 0
        } else if result.didRemoveItem {
            invalidateEstimatedState()
        }
        return result
    }

    func pruneImmediately(
        protecting additionalProtectedPaths: Set<String>
    ) async -> DownloadableMediaDiskPruneResult {
        guard !isRunning else { return skippedResult() }
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        isRunning = true
        let result = await performPruneWithMutationRetry(
            additionalProtectedPaths: additionalProtectedPaths,
            cancellationGeneration: generation,
            cancellationEpoch: store.pruneCancellationEpoch()
        )
        isRunning = false
        if result.wasCurrent {
            estimatedCacheBytes = result.cacheBytesAfterPrune
            estimatedAvailableDiskBytes = result.availableDiskBytesAfterPrune
            bytesAddedSinceEstimate = 0
        }
        return result
    }

    private func consumeRoutineThrottle(for request: Request) -> Bool {
        guard !request.bypassesRoutineThrottle else { return true }
        let now = Date()
        if let lastRoutineCheckDate,
           now.timeIntervalSince(lastRoutineCheckDate)
               < Self.routineCheckInterval {
            return false
        }
        lastRoutineCheckDate = now
        return true
    }

    private func shouldSchedulePostWritePrune() -> Bool {
        guard let estimatedCacheBytes else { return true }
        let projectedCacheBytes = addingWithoutOverflow(
            estimatedCacheBytes,
            bytesAddedSinceEstimate
        )
        if projectedCacheBytes > Self.maximumDiskCacheBytes {
            return true
        }
        guard let estimatedAvailableDiskBytes else { return false }
        return subtractingWithoutOverflow(
            estimatedAvailableDiskBytes,
            bytesAddedSinceEstimate
        ) < Self.minimumAvailableDiskBytes
    }

    private func performPruneWithMutationRetry(
        additionalProtectedPaths: Set<String>,
        cancellationGeneration: UInt64,
        cancellationEpoch: UInt64
    ) async -> DownloadableMediaDiskPruneResult {
#if os(macOS)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.maximumMutationDeferralInterval
        )
        var lastGeneration = await store.currentMutationGeneration()
        var activeCancellationEpoch = cancellationEpoch
        guard cancellationGeneration == scheduleGeneration,
              !Task.isCancelled else {
            return skippedResult()
        }
        var result = await performPrune(
            additionalProtectedPaths: additionalProtectedPaths,
            cancellationEpoch: activeCancellationEpoch
        )
        while !result.wasCurrent, clock.now < deadline {
            guard cancellationGeneration == scheduleGeneration,
                  !Task.isCancelled else {
                return result
            }
            try? await Task.sleep(for: Self.checkDebounceInterval)
            guard cancellationGeneration == scheduleGeneration,
                  !Task.isCancelled else {
                return result
            }
            let generation = await store.currentMutationGeneration()
            activeCancellationEpoch = store.pruneCancellationEpoch()
            guard generation == lastGeneration else {
                lastGeneration = generation
                continue
            }
            result = await performPrune(
                additionalProtectedPaths: additionalProtectedPaths,
                cancellationEpoch: activeCancellationEpoch
            )
        }
        if !result.wasCurrent,
           cancellationGeneration == scheduleGeneration,
           !Task.isCancelled {
            result = await performPrune(
                additionalProtectedPaths: additionalProtectedPaths,
                cancellationEpoch: store.pruneCancellationEpoch()
            )
        }
        return result
#else
        guard cancellationGeneration == scheduleGeneration,
              !Task.isCancelled else {
            return skippedResult()
        }
        return await performPrune(
            additionalProtectedPaths: additionalProtectedPaths,
            cancellationEpoch: cancellationEpoch
        )
#endif
    }

    private func performPrune(
        additionalProtectedPaths: Set<String>,
        cancellationEpoch: UInt64
    ) async -> DownloadableMediaDiskPruneResult {
        let context = await store.beginPrune(
            protectedPaths: additionalProtectedPaths,
            cancellationEpoch: cancellationEpoch
        )
        await store.cleanupRemovalTombstones()
        let snapshot = diskCacheSnapshot()
        let mediaCacheBytes = snapshot.entries.reduce(Int64(0)) {
            addingWithoutOverflow($0, $1.size)
        }
        let orphanMetadataBytes = snapshot.orphanMetadataEntries.reduce(Int64(0)) {
            addingWithoutOverflow($0, $1.size)
        }
        let totalCacheBytes = addingWithoutOverflow(
            mediaCacheBytes,
            orphanMetadataBytes
        )
        let availableDiskBytes = availableDiskBytes()
        let isOverCacheLimit = totalCacheBytes > Self.maximumDiskCacheBytes
        let isUnderFreeSpaceLimit = availableDiskBytes.map {
            $0 < Self.minimumAvailableDiskBytes
        } ?? false

        guard isOverCacheLimit || isUnderFreeSpaceLimit else {
            let completion = await store.finishPrune(context)
            return DownloadableMediaDiskPruneResult(
                didRun: true,
                wasCurrent: completion.wasCurrent,
                didRemoveItem: false,
                removedMediaURLs: [],
                cacheBytesAfterPrune: totalCacheBytes,
                availableDiskBytesAfterPrune: availableDiskBytes,
                mutationGeneration: completion.fileStateGeneration
            )
        }

        var removedCacheBytes: Int64 = 0
        var freedDiskBytes: Int64 = 0
        var didRemoveItem = false
        var removedMediaURLs = Set<URL>()
        var wasCurrent = true
        var resultFileStateGeneration = context.fileStateGeneration

        func currentResult() -> DownloadableMediaDiskPruneResult {
            DownloadableMediaDiskPruneResult(
                didRun: true,
                wasCurrent: wasCurrent,
                didRemoveItem: didRemoveItem,
                removedMediaURLs: removedMediaURLs,
                cacheBytesAfterPrune: max(
                    subtractingWithoutOverflow(
                        totalCacheBytes,
                        removedCacheBytes
                    ),
                    0
                ),
                availableDiskBytesAfterPrune: availableDiskBytes.map {
                    addingWithoutOverflow($0, freedDiskBytes)
                },
                mutationGeneration: resultFileStateGeneration
            )
        }

        func apply(_ removal: DownloadableMediaDiskPruneRemovalResult) {
            removedCacheBytes = addingWithoutOverflow(
                removedCacheBytes,
                removal.removedCacheBytes
            )
            freedDiskBytes = addingWithoutOverflow(
                freedDiskBytes,
                removal.freedDiskBytes
            )
            didRemoveItem = didRemoveItem || removal.didRemoveItem
            removedMediaURLs.formUnion(removal.removedMediaURLs)
            wasCurrent = wasCurrent && removal.wasCurrent
            resultFileStateGeneration = removal.fileStateGeneration
        }

        func didReachTargets() -> Bool {
            let projectedCacheBytes = subtractingWithoutOverflow(
                totalCacheBytes,
                removedCacheBytes
            )
            let projectedAvailableDiskBytes = availableDiskBytes.map {
                addingWithoutOverflow($0, freedDiskBytes)
            }
            return projectedCacheBytes <= Self.targetDiskCacheBytes
                && projectedAvailableDiskBytes.map {
                    $0 >= Self.minimumAvailableDiskBytes
                } ?? true
        }

        var orphanIndex = 0
        while orphanIndex < snapshot.orphanMetadataEntries.count {
            let batchEnd = min(
                orphanIndex + Self.candidateBatchSize,
                snapshot.orphanMetadataEntries.count
            )
            let candidates = snapshot.orphanMetadataEntries[orphanIndex..<batchEnd]
                .map { entry in
                    DownloadableMediaDiskPruneCandidate(
                        paths: [entry.path],
                        primaryFile: DownloadableMediaDiskPruneFile(
                            url: entry.url,
                            size: entry.size
                        ),
                        sidecarFile: nil,
                        requiredMissingURL: entry.mediaURL,
                        unavailableMediaURL: nil
                    )
                }
            let removal = await store.removePruneCandidates(
                candidates,
                removalByteTarget: nil,
                maximumFileCount: Self.maximumRemovalFileCount,
                context: context
            )
            apply(removal)
            guard removal.wasCurrent,
                  removal.processedCandidateCount > 0 else {
                let completion = await store.finishPrune(context)
                resultFileStateGeneration = completion.fileStateGeneration
                return currentResult()
            }
            orphanIndex += removal.processedCandidateCount
        }

        if didReachTargets() {
            let completion = await store.finishPrune(context)
            wasCurrent = completion.wasCurrent
            resultFileStateGeneration = completion.fileStateGeneration
            return currentResult()
        }

        let sortedEntries = snapshot.entries.sorted {
            $0.lastAccessDate < $1.lastAccessDate
        }
        var mediaIndex = 0
        while mediaIndex < sortedEntries.count, !didReachTargets() {
            let remainingCacheDeficit = max(
                subtractingWithoutOverflow(
                    subtractingWithoutOverflow(
                        totalCacheBytes,
                        removedCacheBytes
                    ),
                    Self.targetDiskCacheBytes
                ),
                0
            )
            let remainingFreeSpaceDeficit = availableDiskBytes.map {
                max(
                    subtractingWithoutOverflow(
                        Self.minimumAvailableDiskBytes,
                        addingWithoutOverflow($0, freedDiskBytes)
                    ),
                    0
                )
            } ?? 0
            let removalByteTarget = max(
                remainingCacheDeficit,
                remainingFreeSpaceDeficit
            )
            guard removalByteTarget > 0 else { break }

            let batchEnd = min(
                mediaIndex + Self.candidateBatchSize,
                sortedEntries.count
            )
            let candidates = sortedEntries[mediaIndex..<batchEnd].map { entry in
                DownloadableMediaDiskPruneCandidate(
                    paths: entry.paths,
                    primaryFile: DownloadableMediaDiskPruneFile(
                        url: entry.mediaURL,
                        size: entry.mediaSize
                    ),
                    sidecarFile: entry.metadataURL.map {
                        DownloadableMediaDiskPruneFile(
                            url: $0,
                            size: entry.metadataSize
                        )
                    },
                    requiredMissingURL: nil,
                    unavailableMediaURL: entry.mediaURL
                )
            }
            let removal = await store.removePruneCandidates(
                candidates,
                removalByteTarget: removalByteTarget,
                maximumFileCount: Self.maximumRemovalFileCount,
                context: context
            )
            apply(removal)
            guard removal.wasCurrent,
                  removal.processedCandidateCount > 0 else {
                let completion = await store.finishPrune(context)
                resultFileStateGeneration = completion.fileStateGeneration
                return currentResult()
            }
            mediaIndex += removal.processedCandidateCount
        }

        let completion = await store.finishPrune(context)
        wasCurrent = completion.wasCurrent
        resultFileStateGeneration = completion.fileStateGeneration
        return currentResult()
    }

    private func diskCacheSnapshot() -> DownloadableMediaDiskCacheSnapshot {
        let fileManager = FileManager.default
        guard let collectionDirectories = try? fileManager.contentsOfDirectory(
            at: layout.cacheRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return DownloadableMediaDiskCacheSnapshot(
                entries: [],
                orphanMetadataEntries: []
            )
        }

        var entries = [DownloadableMediaDiskCacheEntry]()
        var orphanMetadataEntries = [DownloadableMediaDiskOrphanMetadataEntry]()
        let metadataSuffix = DownloadableMediaCacheLayout.downloadedMediaMetadataFileSuffix

        for directoryURL in collectionDirectories
        where directoryURL.lastPathComponent
            != DownloadableMediaCacheLayout.webViewHTMLDirectoryName {
            guard (try? directoryURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) == true,
                  let fileURLs = try? fileManager.contentsOfDirectory(
                      at: directoryURL,
                      includingPropertiesForKeys: [
                          .contentAccessDateKey,
                          .contentModificationDateKey,
                          .fileSizeKey,
                          .isDirectoryKey,
                      ],
                      options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            let snapshotsByName = Dictionary(uniqueKeysWithValues: fileURLs.map {
                ($0.lastPathComponent, DownloadableMediaDiskFileSnapshot(url: $0))
            })
            let fileNames = Set(snapshotsByName.keys)
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                guard let snapshot = snapshotsByName[fileName],
                      !snapshot.isDirectory else {
                    continue
                }

                if fileName.hasSuffix(metadataSuffix) {
                    let mediaFileName = String(
                        fileName.dropLast(metadataSuffix.count)
                    )
                    if !fileNames.contains(mediaFileName) {
                        orphanMetadataEntries.append(
                            DownloadableMediaDiskOrphanMetadataEntry(
                                url: snapshot.url,
                                mediaURL: directoryURL.appendingPathComponent(
                                    mediaFileName
                                ),
                                path: layout.diskPath(for: snapshot.url),
                                size: snapshot.size
                            )
                        )
                    }
                    continue
                }

                let metadataFileName = fileName + metadataSuffix
                let metadataSnapshot = snapshotsByName[metadataFileName]
                let metadataURL = metadataSnapshot?.url
                var paths: Set<String> = [layout.diskPath(for: fileURL)]
                if let metadataURL {
                    paths.insert(layout.diskPath(for: metadataURL))
                }
                entries.append(DownloadableMediaDiskCacheEntry(
                    mediaURL: fileURL,
                    metadataURL: metadataURL,
                    paths: paths,
                    mediaSize: snapshot.size,
                    metadataSize: metadataSnapshot?.size ?? 0,
                    lastAccessDate: snapshot.contentAccessDate
                        ?? snapshot.contentModificationDate
                        ?? .distantPast
                ))
            }
        }

        return DownloadableMediaDiskCacheSnapshot(
            entries: entries,
            orphanMetadataEntries: orphanMetadataEntries
        )
    }

    private func availableDiskBytes() -> Int64? {
#if os(tvOS)
        guard let values = try? layout.cacheRoot.resourceValues(forKeys: [
            .volumeAvailableCapacityKey,
        ]) else {
            return nil
        }
        return values.volumeAvailableCapacity.map(Int64.init)
#else
        guard let values = try? layout.cacheRoot.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]) else {
            return nil
        }
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        return values.volumeAvailableCapacity.map(Int64.init)
#endif
    }

    private func skippedResult() -> DownloadableMediaDiskPruneResult {
        DownloadableMediaDiskPruneResult(
            didRun: false,
            wasCurrent: true,
            didRemoveItem: false,
            removedMediaURLs: [],
            cacheBytesAfterPrune: estimatedCacheBytes ?? 0,
            availableDiskBytesAfterPrune: estimatedAvailableDiskBytes,
            mutationGeneration: 0
        )
    }

    private func addingWithoutOverflow(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? (rhs >= 0 ? .max : .min) : value
    }

    private func subtractingWithoutOverflow(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
        return overflow ? (rhs >= 0 ? .min : .max) : value
    }
}
