import UIKit

@MainActor
final class MobilePlayerBookmarkMenuAction {
    private let controller: PlayerBookmarkController
    private let onAccepted: () -> Void
    private var resolutionTask: Task<Void, Never>?
    private var pendingCompletion: (([UIMenuElement]) -> Void)?

    init(
        target: PlayerBookmarkController.Target,
        controller: PlayerBookmarkController = PlayerBookmarkController(),
        onAccepted: @escaping () -> Void = { Haptic.selectionChanged() }
    ) {
        self.controller = controller
        self.onAccepted = onAccepted
        controller.updateTarget(target)
        controller.start()
    }

    isolated deinit {
        resolutionTask?.cancel()
        controller.stop()
        pendingCompletion?([])
    }

    func makeDeferredElement() -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { [self] completion in
            resolve(completion: completion)
        }
    }

    func resolve(completion: @escaping ([UIMenuElement]) -> Void) {
        resolutionTask?.cancel()
        let previousCompletion = pendingCompletion
        pendingCompletion = nil
        previousCompletion?([])
        pendingCompletion = completion

        resolutionTask = Task { [weak self, controller] in
            await controller.refresh()
            guard !Task.isCancelled, let self else { return }

            resolutionTask = nil
            let isBookmarked = controller.isBookmarked
            let action = UIAction(
                title: isBookmarked ? Strings.removeBookmark : Strings.bookmark,
                image: UIImage(
                    systemName: isBookmarked ? "bookmark.fill" : "bookmark"
                ),
                attributes: controller.canToggle ? [] : .disabled
            ) { [self] _ in
                if controller.setBookmarked(!isBookmarked) {
                    onAccepted()
                }
            }
            let completion = pendingCompletion
            pendingCompletion = nil
            completion?([action])
        }
    }
}
