import Foundation
import Observation

@MainActor
@Observable
final class CollectionPreparationState {
    private(set) var isLoading = false
    var errorMessage: String?

    private var generation = 0
    private var task: Task<Void, Error>?
    private var retryAction: (@MainActor () -> Void)?

    func prepare(
        collectionId: String,
        operation: @escaping @MainActor (String) async throws -> Void = {
            try await CollectionCatalog.prepareCollection(collectionId: $0)
        },
        isCurrent: @MainActor () -> Bool,
        retry: @escaping @MainActor () -> Void
    ) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        cancel()
        let generation = generation
        isLoading = true
        let task = Task { try await operation(collectionId) }
        self.task = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard self.generation == generation else { return false }
            self.task = nil
            isLoading = false
            return isCurrent() && !Task.isCancelled
        } catch {
            guard self.generation == generation else { return false }
            self.task = nil
            isLoading = false
            guard isCurrent(), !Task.isCancelled, !(error is CancellationError) else { return false }
            errorMessage = error.localizedDescription
            retryAction = retry
            return false
        }
    }

    func retry() {
        let action = retryAction
        cancel()
        action?()
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        isLoading = false
        errorMessage = nil
        retryAction = nil
    }
}
