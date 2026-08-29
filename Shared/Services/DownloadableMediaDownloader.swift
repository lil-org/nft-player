// ∅ 2026 lil org

import Foundation

actor DownloadableMediaDownloader: DownloadableMediaDownloading {
    private struct ActiveDownload {
        let completionID: UUID
        let task: URLSessionDownloadTask
        let continuation: CheckedContinuation<DownloadableMediaDownloadResult, Never>
        var priorityRevision: UInt64
    }

    private let session: URLSession
    private var activeDownloads = [UUID: ActiveDownload]()
    private var pendingPriorities = [UUID: (priority: Float, revision: UInt64)]()
    private var terminalRequestIDs = Set<UUID>()
    private var terminalRequestOrder = [UUID]()

    init(maximumConcurrentDownloads: Int = 4) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = maximumConcurrentDownloads
        session = URLSession(configuration: configuration)
    }

    func download(
        _ request: DownloadableMediaDownloadRequest
    ) async -> DownloadableMediaDownloadResult {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                return Self.cancelledResult(requestID: request.id)
            }

            return await withCheckedContinuation { continuation in
                start(request, continuation: continuation)
            }
        } onCancel: {
            Task {
                await self.cancel(requestID: request.id)
            }
        }
    }

    func setPriority(
        _ priority: Float,
        for requestID: UUID,
        revision: UInt64
    ) {
        guard !terminalRequestIDs.contains(requestID) else { return }
        guard var download = activeDownloads[requestID] else {
            if revision >= (pendingPriorities[requestID]?.revision ?? 0) {
                pendingPriorities[requestID] = (priority, revision)
                if pendingPriorities.count > 256,
                   let staleRequestID = pendingPriorities.keys.first(
                       where: { activeDownloads[$0] == nil }
                   ) {
                    pendingPriorities.removeValue(forKey: staleRequestID)
                }
            }
            return
        }
        guard revision >= download.priorityRevision else { return }
        download.priorityRevision = revision
        download.task.priority = priority
        activeDownloads[requestID] = download
    }

    func cancel(requestID: UUID) {
        guard let download = activeDownloads.removeValue(forKey: requestID) else {
            markTerminal(requestID)
            return
        }
        markTerminal(requestID)
        download.task.cancel()
        download.continuation.resume(
            returning: Self.cancelledResult(requestID: requestID)
        )
    }

    func cancelAll() {
        let downloads = activeDownloads
        activeDownloads.removeAll(keepingCapacity: true)
        for (requestID, download) in downloads {
            markTerminal(requestID)
            download.task.cancel()
            download.continuation.resume(
                returning: Self.cancelledResult(requestID: requestID)
            )
        }
    }

    private func start(
        _ request: DownloadableMediaDownloadRequest,
        continuation: CheckedContinuation<DownloadableMediaDownloadResult, Never>
    ) {
        if let previousDownload = activeDownloads.removeValue(forKey: request.id) {
            previousDownload.task.cancel()
            previousDownload.continuation.resume(
                returning: Self.cancelledResult(requestID: request.id)
            )
        }

        let completionID = UUID()
        let task = session.downloadTask(with: request.sourceURL) { temporaryURL, response, error in
            let result = Self.makeResult(
                request: request,
                temporaryURL: temporaryURL,
                response: response,
                error: error
            )
            Task {
                await self.finish(
                    requestID: request.id,
                    completionID: completionID,
                    result: result
                )
            }
        }
        let pendingPriority = pendingPriorities.removeValue(forKey: request.id)
        task.priority = pendingPriority?.priority ?? request.priority
        activeDownloads[request.id] = ActiveDownload(
            completionID: completionID,
            task: task,
            continuation: continuation,
            priorityRevision: pendingPriority?.revision ?? 0
        )
        task.resume()

        if Task.isCancelled {
            cancel(requestID: request.id)
        }
    }

    private func finish(
        requestID: UUID,
        completionID: UUID,
        result: DownloadableMediaDownloadResult
    ) {
        guard activeDownloads[requestID]?.completionID == completionID,
              let download = activeDownloads.removeValue(forKey: requestID) else {
            if let stagedURL = result.stagedURL {
                try? FileManager.default.removeItem(at: stagedURL)
            }
            return
        }
        markTerminal(requestID)
        download.continuation.resume(returning: result)
    }

    private func markTerminal(_ requestID: UUID) {
        pendingPriorities.removeValue(forKey: requestID)
        guard terminalRequestIDs.insert(requestID).inserted else { return }
        terminalRequestOrder.append(requestID)
        if terminalRequestOrder.count > 256 {
            let removalCount = terminalRequestOrder.count - 256
            let removed = terminalRequestOrder.prefix(removalCount)
            terminalRequestIDs.subtract(removed)
            terminalRequestOrder.removeFirst(removalCount)
        }
    }

    nonisolated private static func makeResult(
        request: DownloadableMediaDownloadRequest,
        temporaryURL: URL?,
        response: URLResponse?,
        error: Error?
    ) -> DownloadableMediaDownloadResult {
        if let error {
            let failure: DownloadableMediaDownloadFailure = isCancellation(error)
                ? .cancelled
                : .transport
            return DownloadableMediaDownloadResult(
                requestID: request.id,
                stagedURL: nil,
                sourceURL: nil,
                failure: failure
            )
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return DownloadableMediaDownloadResult(
                requestID: request.id,
                stagedURL: nil,
                sourceURL: nil,
                failure: .invalidResponse
            )
        }

        guard let temporaryURL,
              let stagedURL = stageDownloadFile(
            temporaryURL,
            stagingRoot: request.stagingRoot
        ) else {
            return DownloadableMediaDownloadResult(
                requestID: request.id,
                stagedURL: nil,
                sourceURL: nil,
                failure: .staging
            )
        }

        return DownloadableMediaDownloadResult(
            requestID: request.id,
            stagedURL: stagedURL,
            sourceURL: httpResponse.url ?? request.sourceURL,
            failure: nil
        )
    }

    nonisolated private static func isCancellation(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    nonisolated private static func stageDownloadFile(
        _ temporaryURL: URL,
        stagingRoot: URL
    ) -> URL? {
        let fileManager = FileManager.default
        let stagedURL = stagingRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: false
        )

        do {
            try fileManager.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try fileManager.moveItem(at: temporaryURL, to: stagedURL)
            return stagedURL
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            do {
                try fileManager.copyItem(at: temporaryURL, to: stagedURL)
                return stagedURL
            } catch {
                try? fileManager.removeItem(at: stagedURL)
                return nil
            }
        }
    }

    nonisolated private static func cancelledResult(
        requestID: UUID
    ) -> DownloadableMediaDownloadResult {
        DownloadableMediaDownloadResult(
            requestID: requestID,
            stagedURL: nil,
            sourceURL: nil,
            failure: .cancelled
        )
    }
}
