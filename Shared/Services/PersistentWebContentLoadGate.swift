import Foundation

@MainActor
final class PersistentWebContentLoadGate {
    typealias PreparationCheck = @Sendable (String) -> Bool
    typealias Resolver = @Sendable (String, PersistentArtworkDependencyCache, Bool) async throws -> String

    var cache: PersistentArtworkDependencyCache = .shared

    private let requiresPreparation: PreparationCheck
    private let resolveContent: Resolver

    private struct Request: Equatable {
        let html: String
        let context: String
        let allowsDownloads: Bool
    }

    private struct Prepared {
        let request: Request
        let html: String
    }

    private struct Callbacks {
        let ready: @MainActor (String) -> Void
        let failure: @MainActor (Error) -> Void
    }

    private var generation = UUID()
    private var pending: Request?
    private var prepared: Prepared?
    private var callbacks: Callbacks?
    private var task: Task<Void, Never>?

    init(requiresPreparation: @escaping PreparationCheck, resolve: @escaping Resolver) {
        self.requiresPreparation = requiresPreparation
        self.resolveContent = resolve
    }

    convenience init() {
        self.init(
            requiresPreparation: { !PersistentJavaScriptLibrary.requiredDependencies(in: $0).isEmpty },
            resolve: { try await PersistentJavaScriptLibrary.resolve($0, cache: $1, allowsDownloads: $2) }
        )
    }

    deinit {
        task?.cancel()
    }

    @discardableResult
    func load(
        _ html: String,
        context: String,
        allowsDownloads: Bool = true,
        onStart: @MainActor () -> Void,
        onReady: @escaping @MainActor (String) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Bool {
        guard requiresPreparation(html) else {
            cancel()
            return false
        }
        let request = Request(html: html, context: context, allowsDownloads: allowsDownloads)
        if pending == request {
            callbacks = Callbacks(ready: onReady, failure: onFailure)
            return true
        }
        cancel()
        if prepared?.request == request, let resolved = prepared?.html {
            onReady(resolved)
            return true
        }
        pending = request
        callbacks = Callbacks(ready: onReady, failure: onFailure)
        let generation = generation
        let cache = cache
        let resolveContent = resolveContent
        onStart()
        guard self.generation == generation, pending == request else { return true }
        task = Task { [weak self] in
            do {
                let resolved = try await resolveContent(html, cache, allowsDownloads)
                guard let self, !Task.isCancelled, self.generation == generation, self.pending == request else { return }
                let callback = self.callbacks?.ready
                self.prepared = Prepared(request: request, html: resolved)
                self.pending = nil
                self.callbacks = nil
                self.task = nil
                callback?(resolved)
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation, self.pending == request else { return }
                let callback = self.callbacks?.failure
                self.pending = nil
                self.callbacks = nil
                self.task = nil
                callback?(error)
            }
        }
        return true
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        pending = nil
        callbacks = nil
    }

    func reset() {
        cancel()
        prepared = nil
    }
}
