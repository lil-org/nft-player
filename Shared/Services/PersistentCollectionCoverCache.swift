import Foundation
import ImageIO

nonisolated extension Notification.Name {
    static let collectionCoverDidBecomeAvailable = Notification.Name("CollectionCoverDidBecomeAvailable")
}

actor PersistentCollectionCoverCache {
    nonisolated enum Priority: Int, Sendable {
        case visible
        case prefetch
        case background
    }

    nonisolated enum Failure: Error, Equatable {
        case invalidAssetName
        case httpStatus(Int)
        case invalidImage
        case unsafeCacheFile
    }

    typealias Transport = @Sendable (URL) async throws -> (data: Data, statusCode: Int)

    nonisolated static let shared = PersistentCollectionCoverCache()
    nonisolated static let baseURL = URL(string: "https://cdn.lil.org/player/covers/v1/")!

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private struct Waiter {
        let priority: Priority
        let continuation: CheckedContinuation<Data, Error>
    }

    private struct Running {
        let id: UUID
        let priority: Priority
        let task: Task<Void, Never>
        var preempted = false
        var retryAfterRecovery = false
    }

    private struct Pending {
        var running: Running?
        var waiters: [UUID: Waiter] = [:]

        var priority: Priority {
            waiters.values.map(\.priority).min { $0.rawValue < $1.rawValue } ?? .background
        }
    }

    private nonisolated struct Loaded: Sendable {
        let data: Data
        let persisted: Bool
        let newlyPersisted: Bool
    }

    private let rootURL: URL?
    private let transport: Transport
    private var pending: [String: Pending] = [:]
    private var queue: [String] = []
    private var activeJobs = 0
    private var activeSpeculativeJobs = 0
    private var activeBackgroundJobs = 0
    private var attemptedPreloads: Set<String> = []
    private var failedPreloads: Set<String> = []

    init(rootURL: URL? = nil, transport: @escaping Transport = PersistentCollectionCoverCache.download) {
#if os(tvOS)
        let storageDirectory: FileManager.SearchPathDirectory = .cachesDirectory
#else
        let storageDirectory: FileManager.SearchPathDirectory = .applicationSupportDirectory
#endif
        self.rootURL = rootURL ?? FileManager.default.urls(for: storageDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CollectionCovers", isDirectory: true)
        self.transport = transport
    }

    func data(for assetName: String, priority: Priority = .visible) async throws -> Data {
        try Task.checkCancellation()
        if let data = try await cachedData(for: assetName) {
            try Task.checkCancellation()
            return data
        }
        let waiterID = UUID()
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                do {
                    try Task.checkCancellation()
                    enqueue(assetName)
                    pending[assetName]?.waiters[waiterID] = Waiter(priority: priority, continuation: continuation)
                    schedule()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, assetName: assetName) }
        }
        try Task.checkCancellation()
        return data
    }

    func cachedData(for assetName: String) async throws -> Data? {
        try Self.validateAssetName(assetName)
        guard let rootURL else { return nil }
        return await Task.detached(priority: .utility) {
            try? Self.existing(Self.file(for: assetName, rootURL: rootURL))
        }.value
    }

    func preload(assetNames: [String], retryFailures: Bool = false) {
        for assetName in assetNames {
            guard (try? Self.validateAssetName(assetName)) != nil else { continue }
            let firstAttempt = attemptedPreloads.insert(assetName).inserted
            guard firstAttempt || (retryFailures && failedPreloads.remove(assetName) != nil) else { continue }
            enqueue(assetName)
        }
        schedule()
    }

    func connectionRecovered() {
        for assetName in pending.keys {
            pending[assetName]?.running?.retryAfterRecovery = true
        }
    }

    private func enqueue(_ assetName: String) {
        guard pending[assetName] == nil else { return }
        pending[assetName] = Pending()
        queue.append(assetName)
    }

    private func schedule() {
        while activeJobs < 4 {
            let nextIndex = queue.indices.filter { index in
                guard let request = pending[queue[index]] else { return false }
                guard request.priority == .visible || activeSpeculativeJobs < 2 else { return false }
                return request.priority != .background || activeBackgroundJobs == 0
            }.min { left, right in
                pending[queue[left]]!.priority.rawValue < pending[queue[right]]!.priority.rawValue
            }
            guard let nextIndex else { return }
            let assetName = queue.remove(at: nextIndex)
            guard let priority = pending[assetName]?.priority else { continue }
            let runID = UUID()
            activeJobs += 1
            if priority != .visible { activeSpeculativeJobs += 1 }
            if priority == .background { activeBackgroundJobs += 1 }
            let rootURL = rootURL
            let transport = transport
            let task = Task.detached(priority: priority == .visible ? .userInitiated : .utility) {
                let result: Result<Loaded, Error>
                do {
                    let loaded = try await Self.load(assetName, rootURL: rootURL, transport: transport)
                    if loaded.newlyPersisted {
                        await MainActor.run {
                            NotificationCenter.default.post(name: .collectionCoverDidBecomeAvailable, object: assetName)
                        }
                    }
                    result = .success(loaded)
                } catch {
                    result = .failure(error)
                }
                await self.finish(assetName, runID: runID, result: result)
            }
            pending[assetName]?.running = Running(id: runID, priority: priority, task: task)
        }
        guard queue.contains(where: { pending[$0]?.priority == .visible }),
              !pending.values.contains(where: { $0.running?.preempted == true }),
              let candidate = pending.first(where: { $0.value.running != nil && $0.value.priority != .visible }) else { return }
        pending[candidate.key]?.running?.preempted = true
        candidate.value.running?.task.cancel()
    }

    private func finish(_ assetName: String, runID: UUID, result: Result<Loaded, Error>) {
        guard var request = pending[assetName], let running = request.running, running.id == runID else { return }
        activeJobs -= 1
        if running.priority != .visible { activeSpeculativeJobs -= 1 }
        if running.priority == .background { activeBackgroundJobs -= 1 }
        if case .failure(let error) = result,
           running.preempted || (running.retryAfterRecovery && (!request.waiters.isEmpty || attemptedPreloads.contains(assetName)) && Self.isRetryable(error)) {
            request.running = nil
            pending[assetName] = request
            queue.append(assetName)
        } else {
            pending.removeValue(forKey: assetName)
            if attemptedPreloads.contains(assetName) {
                switch result {
                case .success(let loaded) where loaded.persisted: failedPreloads.remove(assetName)
                default: failedPreloads.insert(assetName)
                }
            }
            for waiter in request.waiters.values { waiter.continuation.resume(with: result.map(\.data)) }
        }
        schedule()
    }

    private func cancelWaiter(_ id: UUID, assetName: String) {
        pending[assetName]?.waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
        schedule()
    }

    private nonisolated static func download(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private nonisolated static func isRetryable(_ error: Error) -> Bool {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return false }
        guard let failure = error as? Failure else { return true }
        if case .httpStatus(let status) = failure {
            return status == 408 || status == 429 || (500..<600).contains(status)
        }
        return false
    }

    private nonisolated static func validateAssetName(_ assetName: String) throws {
        guard !assetName.isEmpty, assetName != ".", assetName != "..",
              !assetName.contains("/"), !assetName.contains("\\") else { throw Failure.invalidAssetName }
    }

    private nonisolated static func validate(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) != nil else {
            throw Failure.invalidImage
        }
    }

    private nonisolated static func file(for assetName: String, rootURL: URL) -> URL {
        rootURL.appendingPathComponent("v1", isDirectory: true).appendingPathComponent(assetName + ".jpg")
    }

    private nonisolated static func existing(_ file: URL) throws -> Data? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsafeCacheFile }
        let data = try Data(contentsOf: file)
        do {
            try validate(data)
            return data
        } catch {
            return nil
        }
    }

    private nonisolated static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private nonisolated static func load(_ assetName: String, rootURL: URL?, transport: Transport) async throws -> Loaded {
        var destination = rootURL.map { file(for: assetName, rootURL: $0) }
        do {
            if let destination, let data = try existing(destination) {
                return Loaded(data: data, persisted: true, newlyPersisted: false)
            }
        } catch {
            destination = nil
        }
        let response = try await transport(baseURL.appendingPathComponent(assetName + ".jpg"))
        guard (200..<300).contains(response.statusCode) else { throw Failure.httpStatus(response.statusCode) }
        try validate(response.data)
        var persisted = false
        if let destination, let rootURL {
            do {
                let directory = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try excludeFromBackup(rootURL)
                try excludeFromBackup(directory)
                try response.data.write(to: destination, options: .atomic)
                persisted = true
                try? excludeFromBackup(destination)
            } catch {}
        }
        return Loaded(data: response.data, persisted: persisted, newlyPersisted: persisted)
    }
}
