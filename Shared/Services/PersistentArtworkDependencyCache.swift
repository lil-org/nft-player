import CryptoKit
import Darwin
import Foundation

nonisolated struct PersistentArtworkDependency: Hashable, Sendable {
    let id: String
    var collectionId: String { id }
    let remoteURL: URL
    let expectedByteCount: Int
    let sha256: String

    init(id: String, remoteURL: URL, expectedByteCount: Int, sha256: String) {
        self.id = id
        self.remoteURL = remoteURL
        self.expectedByteCount = expectedByteCount
        self.sha256 = sha256
    }

    init(collectionId: String, remoteURL: URL, expectedByteCount: Int, sha256: String) {
        self.init(id: collectionId, remoteURL: remoteURL, expectedByteCount: expectedByteCount, sha256: sha256)
    }

    static let hypertype = PersistentArtworkDependency(
        collectionId: "0xbb5471c292065d3b01b2e81e299267221ae9a2500",
        remoteURL: URL(string: "https://cdn.lil.org/player/hypertype/dependency.js")!,
        expectedByteCount: 712_587,
        sha256: "48d2613055cacdf43217ed43710990150ef2afaa15540c69d2b840d80fd4b6c8"
    )

    static func forCollection(_ id: String) -> Self? {
        id.lowercased() == hypertype.collectionId ? hypertype : nil
    }

    fileprivate var directoryName: String {
        if id == Self.hypertype.id { return "hypertype" }
        if id.hasPrefix("library:") { return "libraries" }
        return Self.digest(Data(id.utf8))
    }

    fileprivate static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

actor PersistentArtworkDependencyCache {
    typealias Transport = @Sendable (URL) async throws -> (data: Data, statusCode: Int)

    enum Failure: Error, Equatable {
        case applicationSupportUnavailable
        case invalidDescriptor
        case notCached
        case httpStatus(Int)
        case byteCount(expected: Int, actual: Int)
        case checksum
        case invalidUTF8
        case unsafeCacheFile
    }

    static let shared = PersistentArtworkDependencyCache()

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return ArtworkAssetPolicy.makeSession(configuration: configuration)
    }()

    private struct Pending {
        let id: UUID
        var waiters: [UUID: CheckedContinuation<Data?, Error>]
    }

    private let rootURL: URL?
    private let transport: Transport
    private var pending: [PersistentArtworkDependency: Pending] = [:]
    private var activeDownloads = 0
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []

    init(rootURL: URL? = nil, transport: @escaping Transport = PersistentArtworkDependencyCache.download) {
#if os(tvOS)
        let storageDirectory: FileManager.SearchPathDirectory = .cachesDirectory
#else
        let storageDirectory: FileManager.SearchPathDirectory = .applicationSupportDirectory
#endif
        self.rootURL = rootURL ?? FileManager.default.urls(for: storageDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ArtworkDependencies", isDirectory: true)
        self.transport = transport
    }

    func data(for dependency: PersistentArtworkDependency) async throws -> Data {
        guard let data = try await requestData(for: dependency, allowsDownloads: true) else { throw Failure.notCached }
        return data
    }

    func cachedData(for dependency: PersistentArtworkDependency) async throws -> Data? {
        try await requestData(for: dependency, allowsDownloads: false)
    }

    private func requestData(for dependency: PersistentArtworkDependency, allowsDownloads: Bool) async throws -> Data? {
        let waiterID = UUID()
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                do {
                    try Task.checkCancellation()
                    if pending[dependency] != nil {
                        pending[dependency]?.waiters[waiterID] = continuation
                        return
                    }
                    guard let rootURL else { throw Failure.applicationSupportUnavailable }
                    if !allowsDownloads {
                        try Self.validateDescriptor(dependency)
                        let file = rootURL.appendingPathComponent(dependency.directoryName, isDirectory: true)
                            .appendingPathComponent(dependency.sha256 + ".js")
                        continuation.resume(returning: try Self.existing(file, dependency: dependency))
                        return
                    }
                    let requestID = UUID()
                    pending[dependency] = Pending(id: requestID, waiters: [waiterID: continuation])
                    Task.detached(priority: .utility) {
                        let result: Result<Data, Error>
                        do {
                            result = .success(try await Self.load(dependency, rootURL: rootURL, transport: { url in
                                try await self.downloadWithLimit(url)
                            }))
                        } catch {
                            result = .failure(error)
                        }
                        await self.finish(dependency, requestID: requestID, result: result)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, for: dependency) }
        }
        try Task.checkCancellation()
        return data
    }

    private func cancelWaiter(_ id: UUID, for dependency: PersistentArtworkDependency) {
        pending[dependency]?.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func finish(_ dependency: PersistentArtworkDependency, requestID: UUID, result: Result<Data, Error>) {
        guard pending[dependency]?.id == requestID,
              let request = pending.removeValue(forKey: dependency) else { return }
        for waiter in request.waiters.values { waiter.resume(with: result.map { Optional($0) }) }
    }

    private func downloadWithLimit(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        if activeDownloads == 4 {
            await withCheckedContinuation { downloadWaiters.append($0) }
        } else {
            activeDownloads += 1
        }
        defer {
            if downloadWaiters.isEmpty {
                activeDownloads -= 1
            } else {
                downloadWaiters.removeFirst().resume()
            }
        }
        return try await transport(url)
    }

    private nonisolated static func download(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        try ArtworkAssetPolicy.validateRemoteURL(url)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private nonisolated static func validate(_ data: Data, for dependency: PersistentArtworkDependency) throws {
        guard data.count == dependency.expectedByteCount else { throw Failure.byteCount(expected: dependency.expectedByteCount, actual: data.count) }
        guard PersistentArtworkDependency.digest(data) == dependency.sha256 else { throw Failure.checksum }
        guard String(data: data, encoding: .utf8) != nil else { throw Failure.invalidUTF8 }
    }

    private nonisolated static func existing(_ file: URL, dependency: PersistentArtworkDependency) throws -> Data? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsafeCacheFile }
        let data = try Data(contentsOf: file)
        do {
            try validate(data, for: dependency)
            return data
        } catch {
            try manager.removeItem(at: file)
            return nil
        }
    }

    private nonisolated static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private nonisolated static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private nonisolated static func validateDescriptor(_ dependency: PersistentArtworkDependency) throws {
        guard ArtworkAssetPolicy.allowsRemoteURL(dependency.remoteURL),
              dependency.expectedByteCount > 0,
              dependency.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw Failure.invalidDescriptor }
    }

    private nonisolated static func load(_ dependency: PersistentArtworkDependency, rootURL: URL, transport: Transport) async throws -> Data {
        try validateDescriptor(dependency)
        let manager = FileManager.default
        let directory = rootURL.appendingPathComponent(dependency.directoryName, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(rootURL)
        try excludeFromBackup(directory)
        let stagingPrefix = ".\(dependency.sha256)-"
        for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        where file.lastPathComponent.hasPrefix(stagingPrefix) && file.pathExtension == "partial" {
            try manager.removeItem(at: file)
        }
        let destination = directory.appendingPathComponent(dependency.sha256 + ".js")
        if let data = try existing(destination, dependency: dependency) { return data }
        let response = try await transport(dependency.remoteURL)
        guard response.statusCode == 200 else { throw Failure.httpStatus(response.statusCode) }
        try validate(response.data, for: dependency)
        if let data = try existing(destination, dependency: dependency) { return data }
        let staging = directory.appendingPathComponent(stagingPrefix + UUID().uuidString + ".partial")
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
        try validate(Data(contentsOf: staging), for: dependency)
        try manager.moveItem(at: staging, to: destination)
        try synchronizeDirectory(directory)
        try synchronizeDirectory(rootURL)
        try synchronizeDirectory(rootURL.deletingLastPathComponent())
        return response.data
    }
}
