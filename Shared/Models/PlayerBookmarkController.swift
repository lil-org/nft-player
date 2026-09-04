import Foundation
import Observation

@MainActor
@Observable
final class PlayerBookmarkController {
    typealias Target = PlayerBookmarkPresentationState.Target
    typealias ToggleCompletion = @MainActor @Sendable (Target, Bool) -> Void

    struct Dependencies {
        var storedState: @MainActor (Target) -> PlayerStoredBookmarkState
        var isBookmarked: @MainActor (Target) async -> Bool
        var enqueueUpdate: @MainActor (
            Target,
            Bool,
            @escaping @MainActor @Sendable (Bool) -> Void
        ) -> Bool

        static let live = Dependencies(
            storedState: {
                PlayerBookmarksStore.storedBookmarkState(
                    collectionId: $0.collectionId,
                    tokenId: $0.tokenId
                )
            },
            isBookmarked: {
                await PlayerBookmarksStore.shared.isBookmarked(
                    collectionId: $0.collectionId,
                    tokenId: $0.tokenId
                )
            },
            enqueueUpdate: {
                PlayerBookmarksStore.enqueueBookmarkUpdate(
                    collectionId: $0.collectionId,
                    tokenId: $0.tokenId,
                    isBookmarked: $1,
                    completion: $2
                )
            }
        )
    }

    private let dependencies: Dependencies
    private let notificationCenter: NotificationCenter
    private var presentationState = PlayerBookmarkPresentationState()
    private var isStarted = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var changesObserver: NSObjectProtocol?

    init(
        dependencies: Dependencies = .live,
        notificationCenter: NotificationCenter = .default
    ) {
        self.dependencies = dependencies
        self.notificationCenter = notificationCenter
    }

    isolated deinit {
        loadTask?.cancel()
        if let changesObserver {
            notificationCenter.removeObserver(changesObserver)
        }
    }

    var canToggle: Bool {
        isStarted && presentationState.canToggle
    }

    var isBookmarked: Bool {
        presentationState.isBookmarked
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        changesObserver = notificationCenter.addObserver(
            forName: .playerBookmarksDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isStarted else { return }
                self.scheduleRefresh(for: self.presentationState.target)
            }
        }
        scheduleRefresh(for: presentationState.target)
    }

    func stop() {
        isStarted = false
        cancelLoading()
        if let changesObserver {
            notificationCenter.removeObserver(changesObserver)
            self.changesObserver = nil
        }
    }

    func updateTarget(_ target: Target?) {
        let target = target.flatMap {
            $0.collectionId.isEmpty || $0.tokenId.isEmpty ? nil : $0
        }
        scheduleRefresh(for: target)
    }

    func refresh() async {
        guard isStarted,
              let task = scheduleRefresh(for: presentationState.target) else {
            return
        }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @discardableResult
    func toggle(completion: ToggleCompletion? = nil) -> Bool {
        guard isStarted,
              let request = presentationState.beginToggle() else {
            return false
        }
        cancelLoading()
        let admitted = dependencies.enqueueUpdate(
            request.target,
            request.isBookmarked
        ) { [weak self] isBookmarked in
            guard let self else { return }
            if self.isStarted {
                let storedState = self.dependencies.storedState(request.target)
                self.presentationState.applyToggleCompletion(
                    isBookmarked: isBookmarked,
                    for: request.target,
                    isTogglePending: storedState.isTogglePending
                )
            }
            completion?(request.target, isBookmarked)
        }
        if !admitted {
            scheduleRefresh(for: presentationState.target)
        }
        return admitted
    }

    @discardableResult
    private func scheduleRefresh(for target: Target?) -> Task<Void, Never>? {
        cancelLoading()
        let storedState = target.map(dependencies.storedState)
            ?? PlayerStoredBookmarkState(
                isBookmarked: false,
                isTogglePending: false,
                isReady: true
            )
        let request = presentationState.beginLoading(
            target: target,
            storedState: storedState
        )
        guard isStarted, let request else { return nil }
        let isBookmarked = dependencies.isBookmarked
        let task = Task { [weak self] in
            let result = await isBookmarked(request.target)
            guard !Task.isCancelled, let self, self.isStarted else { return }
            self.presentationState.applyLoadedState(
                isBookmarked: result,
                for: request
            )
        }
        loadTask = task
        return task
    }

    private func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}
