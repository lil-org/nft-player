import Darwin
import Foundation
import os

actor PersistentCollectionTokenCache {
    typealias Transport = @Sendable (URL) async throws -> (data: Data, statusCode: Int)
    nonisolated struct BackgroundActivity: Sendable {
        let perform: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void
    }

    nonisolated static var backgroundActivity: BackgroundActivity? {
#if os(macOS)
        nil
#else
        BackgroundActivity { handler in
            ProcessInfo.processInfo.performExpiringActivity(
                withReason: "Download collection data", using: handler
            )
        }
#endif
    }

    nonisolated enum Failure: LocalizedError, Equatable {
        case sharedContainerUnavailable
        case invalidResourceName
        case httpStatus(Int)
        case invalidManifest
        case unsafeCacheFile
        case lockTimeout

        var errorDescription: String? {
            switch self {
            case .sharedContainerUnavailable:
                String(localized: "Shared collection storage is unavailable.")
            case .invalidResourceName:
                String(localized: "This collection has an invalid resource name.")
            case let .httpStatus(status):
                String(localized: "Collection data could not be downloaded (HTTP \(status)).")
            case .invalidManifest:
                String(localized: "The downloaded collection data is invalid.")
            case .unsafeCacheFile:
                String(localized: "The saved collection data could not be accessed safely.")
            case .lockTimeout:
                String(localized: "Another download is using this collection. Please try again.")
            }
        }
    }

    nonisolated static let appGroupIdentifier = "group.org.lil.nft-folder"
    nonisolated static let baseURL = URL(string: "https://cdn.lil.org/player/collections/")!
    nonisolated static let shared = PersistentCollectionTokenCache()

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private struct Pending {
        let id: UUID
        var waiters: [UUID: CheckedContinuation<Data, Error>]
        var task: Task<Void, Never>?
    }

    private nonisolated struct ValidatedManifest: Decodable {
        init(from decoder: Decoder) throws {
            let manifest = try CompactTokenManifest(from: decoder)
            _ = try manifest.decodeColumn(String.self, forKey: .name)
            _ = try manifest.decodeColumn(String.self, forKey: .hash)
            _ = try manifest.decodeColumn(ValidatedAspectRatio.self, forKey: .aspectRatio)
            _ = try manifest.decodeColumn([String: String].self, forKey: .contractParameters)
        }
    }

    private nonisolated struct ValidatedAspectRatio: Decodable {
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let width = try container.decode(Int.self)
            let height = try container.decode(Int.self)
            guard width > 0, height > 0, container.isAtEnd else {
                throw Failure.invalidManifest
            }
        }
    }

    private let rootURL: URL?
    private let transport: Transport
    private let activity: BackgroundActivity?
    private let lockTimeout: Duration
    private var pending: [String: Pending] = [:]

    init(
        rootURL: URL? = nil,
        activity: BackgroundActivity? = PersistentCollectionTokenCache.backgroundActivity,
        transport: @escaping Transport = PersistentCollectionTokenCache.download,
        lockTimeout: Duration = .seconds(65)
    ) {
        self.rootURL = rootURL ?? Self.sharedRootURL()
        self.transport = transport
        self.activity = activity
        self.lockTimeout = lockTimeout
    }

    func data(for resourceName: String) async throws -> Data {
        try Self.validateResourceName(resourceName)
        let waiterID = UUID()
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                do {
                    try Task.checkCancellation()
                    if pending[resourceName] != nil {
                        pending[resourceName]?.waiters[waiterID] = continuation
                        return
                    }
                    guard let rootURL else { throw Failure.sharedContainerUnavailable }
                    let requestID = UUID()
                    pending[resourceName] = Pending(id: requestID, waiters: [waiterID: continuation])
                    let transport = transport
                    let activity = activity
                    let lockTimeout = lockTimeout
                    pending[resourceName]?.task = Task.detached(priority: .utility) {
                        let result: Result<Data, Error>
                        do {
                            result = .success(try await Self.load(
                                resourceName,
                                rootURL: rootURL,
                                transport: transport,
                                activity: activity,
                                lockTimeout: lockTimeout
                            ))
                        } catch {
                            result = .failure(error)
                        }
                        await self.finish(resourceName, requestID: requestID, result: result)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, resourceName: resourceName) }
        }
        try Task.checkCancellation()
        return data
    }

    func cachedData(for resourceName: String) async throws -> Data? {
        try Task.checkCancellation()
        try Self.validateResourceName(resourceName)
        guard let rootURL else { throw Failure.sharedContainerUnavailable }
        let data = try await Task.detached(priority: .utility) {
            try Self.existing(Self.file(for: resourceName, rootURL: rootURL))
        }.value
        try Task.checkCancellation()
        return data
    }

    private func cancelWaiter(_ id: UUID, resourceName: String) {
        guard var request = pending[resourceName],
              let waiter = request.waiters.removeValue(forKey: id) else { return }
        if request.waiters.isEmpty {
            pending.removeValue(forKey: resourceName)
            request.task?.cancel()
        } else {
            pending[resourceName] = request
        }
        waiter.resume(throwing: CancellationError())
    }

    private func finish(_ resourceName: String, requestID: UUID, result: Result<Data, Error>) {
        guard pending[resourceName]?.id == requestID,
              let request = pending.removeValue(forKey: resourceName) else { return }
        for waiter in request.waiters.values { waiter.resume(with: result) }
    }

    private nonisolated static func sharedRootURL() -> URL? {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
#if os(tvOS)
        return container?.appendingPathComponent("Library/Caches/CollectionTokens", isDirectory: true)
#else
        return container?.appendingPathComponent("Library/Application Support/CollectionTokens", isDirectory: true)
#endif
    }

    private nonisolated static func download(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private nonisolated static func validateResourceName(_ resourceName: String) throws {
        guard !resourceName.isEmpty, resourceName.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { throw Failure.invalidResourceName }
    }

    private nonisolated static func validate(_ data: Data) throws {
        do {
            _ = try JSONDecoder().decode(ValidatedManifest.self, from: data)
        } catch {
            throw Failure.invalidManifest
        }
    }

    private nonisolated static func file(for resourceName: String, rootURL: URL) -> URL {
        rootURL.appendingPathComponent(resourceName + ".json")
    }

    private nonisolated static func existing(_ file: URL) throws -> Data? {
        var info = stat()
        guard lstat(file.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.unsafeCacheFile }
        let data = try Data(contentsOf: file)
        guard (try? validate(data)) != nil else { return nil }
        return data
    }

    private nonisolated static func acquireLock(at url: URL, timeout: Duration) async throws -> Int32 {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError() }
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { throw posixError() }
            guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.unsafeCacheFile }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while true {
                try Task.checkCancellation()
                if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
                guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else { throw posixError() }
                guard clock.now < deadline else { throw Failure.lockTimeout }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            close(descriptor)
            throw error
        }
    }

    private nonisolated static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private nonisolated static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    private nonisolated static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private nonisolated static func load(
        _ resourceName: String,
        rootURL: URL,
        transport: @escaping Transport,
        activity: BackgroundActivity?,
        lockTimeout: Duration
    ) async throws -> Data {
        try Task.checkCancellation()
        let destination = file(for: resourceName, rootURL: rootURL)
        if let data = try existing(destination) { return data }
        if let activity {
            let operation = ExpiringLoad()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    operation.start(continuation: continuation, activity: activity) {
                        try await loadLocked(resourceName, rootURL: rootURL, transport: transport, lockTimeout: lockTimeout)
                    }
                }
            } onCancel: {
                operation.cancel()
            }
        }
        return try await loadLocked(resourceName, rootURL: rootURL, transport: transport, lockTimeout: lockTimeout)
    }

    private nonisolated static func loadLocked(
        _ resourceName: String,
        rootURL: URL,
        transport: Transport,
        lockTimeout: Duration
    ) async throws -> Data {
        try Task.checkCancellation()
        let destination = file(for: resourceName, rootURL: rootURL)
        let manager = FileManager.default
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try excludeFromBackup(rootURL)
        let descriptor = try await acquireLock(
            at: rootURL.appendingPathComponent(resourceName + ".lock"),
            timeout: lockTimeout
        )
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        try Task.checkCancellation()
        if let data = try existing(destination) { return data }
        let stagingPrefix = ".\(resourceName)."
        for file in try manager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        where file.lastPathComponent.hasPrefix(stagingPrefix) && file.pathExtension == "partial" {
            try manager.removeItem(at: file)
        }
        let response = try await transport(baseURL.appendingPathComponent(resourceName + ".json"))
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw Failure.httpStatus(response.statusCode) }
        try validate(response.data)
        let staging = rootURL.appendingPathComponent(stagingPrefix + UUID().uuidString + ".partial")
        defer { try? manager.removeItem(at: staging) }
        try response.data.write(to: staging, options: .withoutOverwriting)
        try excludeFromBackup(staging)
        let handle = try FileHandle(forWritingTo: staging)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw posixError() }
        try synchronizeDirectory(rootURL)
        try synchronizeDirectory(rootURL.deletingLastPathComponent())
        return response.data
    }
}

nonisolated private final class ExpiringLoad: Sendable {
    private struct State {
        var task: Task<Void, Never>?
        var continuation: CheckedContinuation<Data, Error>?
        var isCancelled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let finished = DispatchGroup()

    init() {
        finished.enter()
    }

    func start(
        continuation: CheckedContinuation<Data, Error>,
        activity: PersistentCollectionTokenCache.BackgroundActivity,
        operation: @escaping @Sendable () async throws -> Data
    ) {
        state.withLock { $0.continuation = continuation }
        activity.perform { [self] expired in
            if expired {
                cancel()
            } else {
                state.withLock { state in
                    guard !state.isCancelled, state.continuation != nil, state.task == nil else { return }
                    state.task = Task.detached(priority: .utility) {
                        let result: Result<Data, Error>
                        do { result = .success(try await operation()) }
                        catch { result = .failure(error) }
                        self.complete(result)
                    }
                }
            }
            if state.withLock({ $0.isCancelled && $0.task == nil }) {
                complete(.failure(CancellationError()))
            }
            // ProcessInfo owns this callback queue; keep its assertion until the file lock is released.
            finished.wait()
        }
    }

    func cancel() {
        state.withLock { state in
            state.isCancelled = true
            state.task?.cancel()
        }
    }

    private func complete(_ result: Result<Data, Error>) {
        let continuation = state.withLock { state in
            defer {
                state.continuation = nil
                state.task = nil
            }
            return state.continuation
        }
        guard let continuation else { return }
        finished.leave()
        continuation.resume(with: result)
    }
}
