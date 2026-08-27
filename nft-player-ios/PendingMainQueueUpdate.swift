import Foundation

final class PendingMainQueueUpdate {

    private var isScheduled = false
    private var generation = 0
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func schedule() {
        assert(Thread.isMainThread)
        guard !isScheduled else { return }

        isScheduled = true
        let scheduledGeneration = generation
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.isScheduled,
                      self.generation == scheduledGeneration else {
                    return
                }

                self.isScheduled = false
                self.action()
            }
        }
    }

    func flush() {
        assert(Thread.isMainThread)
        guard isScheduled else { return }

        invalidate()
        action()
    }

    func invalidate() {
        assert(Thread.isMainThread)
        guard isScheduled else { return }

        isScheduled = false
        generation += 1
    }

}
