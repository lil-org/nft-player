import Foundation
import XCTest
@testable import NftPlayerSyncCore

@MainActor
final class PlayerBookmarkControllerTests: XCTestCase {
    private let firstTarget = PlayerBookmarkController.Target(
        collectionId: "collection-a",
        tokenId: "token-a"
    )
    private let secondTarget = PlayerBookmarkController.Target(
        collectionId: "collection-b",
        tokenId: "token-b"
    )

    func testTargetSwitchRejectsDelayedReadAndAcceptsCurrentRead() async {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget, isReady: false)
        backend.setState(false, for: secondTarget, isReady: false)
        let controller = backend.makeController()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        controller.start()
        _ = await backend.nextRead()

        let oldRefresh = Task { await controller.refresh() }
        let oldRead = await backend.nextRead()
        XCTAssertEqual(oldRead.target, firstTarget)
        XCTAssertFalse(controller.canToggle)

        controller.updateTarget(secondTarget)
        let switchedRead = await backend.nextRead()
        XCTAssertEqual(switchedRead.target, secondTarget)

        oldRead.resolve(true)
        await oldRefresh.value

        XCTAssertFalse(controller.isBookmarked)
        XCTAssertFalse(controller.canToggle)

        let currentRefresh = Task { await controller.refresh() }
        let currentRead = await backend.nextRead()
        XCTAssertEqual(currentRead.target, secondTarget)
        currentRead.resolve(true)
        await currentRefresh.value

        XCTAssertTrue(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)
    }

    func testStoppedRefreshCannotPublishAndRestartAcceptsCurrentRead() async {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget, isReady: false)
        let controller = backend.makeController()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        controller.start()
        _ = await backend.nextRead()

        let stoppedRefresh = Task { await controller.refresh() }
        let stoppedRead = await backend.nextRead()
        controller.stop()
        stoppedRead.resolve(true)
        await stoppedRefresh.value

        XCTAssertFalse(controller.isBookmarked)
        XCTAssertFalse(controller.canToggle)

        controller.start()
        _ = await backend.nextRead()
        let currentRefresh = Task { await controller.refresh() }
        let currentRead = await backend.nextRead()
        currentRead.resolve(true)
        await currentRefresh.value

        XCTAssertTrue(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)
    }

    func testNotificationsRefreshExactlyOnceAcrossStartStopAndRestart() {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget)
        let controller = backend.makeController()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        XCTAssertEqual(backend.storedStateRequests, [firstTarget])
        XCTAssertFalse(controller.canToggle)

        controller.start()
        controller.start()
        XCTAssertEqual(backend.storedStateRequests.count, 2)
        XCTAssertTrue(controller.canToggle)

        backend.setState(true, for: firstTarget)
        backend.postChange()
        XCTAssertEqual(backend.storedStateRequests.count, 3)
        XCTAssertTrue(controller.isBookmarked)

        controller.stop()
        controller.stop()
        backend.setState(false, for: firstTarget)
        backend.postChange()
        XCTAssertEqual(backend.storedStateRequests.count, 3)
        XCTAssertTrue(controller.isBookmarked)
        XCTAssertFalse(controller.canToggle)

        controller.start()
        controller.start()
        XCTAssertEqual(backend.storedStateRequests.count, 4)
        XCTAssertFalse(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)

        backend.setState(true, for: firstTarget)
        backend.postChange()
        XCTAssertEqual(backend.storedStateRequests.count, 5)
        XCTAssertTrue(controller.isBookmarked)
    }

    func testToggleRejectsDuplicatesAndRecoversAfterAdmissionRejection() {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget)
        let controller = backend.makeController()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        controller.start()

        XCTAssertTrue(controller.toggle())
        XCTAssertFalse(controller.canToggle)
        XCTAssertFalse(controller.toggle())
        XCTAssertEqual(backend.updateAttempts.count, 1)
        backend.completeNextUpdate(isBookmarked: true)
        XCTAssertTrue(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)

        backend.admitsUpdates = false
        XCTAssertFalse(controller.toggle())
        XCTAssertTrue(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)

        backend.admitsUpdates = true
        XCTAssertTrue(controller.toggle())
        XCTAssertEqual(
            backend.updateAttempts.map(\.isBookmarked),
            [true, false, false]
        )
        XCTAssertTrue(backend.updateAttempts.allSatisfy {
            $0.target == firstTarget
        })
        backend.completeNextUpdate(isBookmarked: false)
        XCTAssertFalse(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)
    }

    func testToggleCompletionKeepsOriginalTargetAfterSwitch() {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget)
        backend.setState(false, for: secondTarget)
        let controller = backend.makeController()
        let recorder = PlayerBookmarkCompletionRecorder()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        controller.start()

        XCTAssertTrue(controller.toggle { target, isBookmarked in
            recorder.record(target: target, isBookmarked: isBookmarked)
        })
        controller.updateTarget(secondTarget)
        backend.completeNextUpdate(isBookmarked: true)

        XCTAssertEqual(recorder.targets, [firstTarget])
        XCTAssertEqual(recorder.values, [true])
        XCTAssertFalse(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)
    }

    func testExplicitUpdatePreservesIntentAfterSyncedStateChanges() {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget)
        let controller = backend.makeController()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        controller.start()

        backend.setState(true, for: firstTarget)
        backend.postChange()
        XCTAssertTrue(controller.isBookmarked)
        XCTAssertTrue(controller.setBookmarked(true))
        XCTAssertFalse(controller.setBookmarked(false))
        XCTAssertEqual(backend.updateAttempts.map(\.isBookmarked), [true])

        backend.completeNextUpdate(isBookmarked: true)
        backend.setState(false, for: firstTarget)
        backend.postChange()
        XCTAssertTrue(controller.setBookmarked(false))
        XCTAssertEqual(backend.updateAttempts.map(\.isBookmarked), [true, false])
        backend.completeNextUpdate(isBookmarked: false)
        XCTAssertTrue(controller.canToggle)
    }

    func testExplicitUpdateRejectsUnreadyStoppedAndPendingTargets() {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget, isReady: false)
        let controller = backend.makeController()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        XCTAssertFalse(controller.setBookmarked(true))
        controller.start()
        XCTAssertFalse(controller.setBookmarked(true))

        backend.setState(false, for: firstTarget, isTogglePending: true)
        backend.postChange()
        XCTAssertFalse(controller.setBookmarked(true))
        XCTAssertTrue(backend.updateAttempts.isEmpty)

        backend.setState(false, for: firstTarget)
        backend.postChange()
        XCTAssertTrue(controller.setBookmarked(true))
        controller.stop()
        backend.completeNextUpdate(isBookmarked: true)
        XCTAssertFalse(controller.setBookmarked(false))
        controller.start()
        XCTAssertTrue(controller.isBookmarked)
    }

    func testPendingSaveCompletesAfterStopAndRestartReadsItsResult() {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget)
        let controller = backend.makeController()
        let recorder = PlayerBookmarkCompletionRecorder()
        defer {
            controller.stop()
            backend.finishReads()
        }
        controller.updateTarget(firstTarget)
        controller.start()

        XCTAssertTrue(controller.toggle { target, isBookmarked in
            recorder.record(target: target, isBookmarked: isBookmarked)
        })
        controller.stop()
        backend.completeNextUpdate(isBookmarked: true)

        XCTAssertEqual(recorder.targets, [firstTarget])
        XCTAssertEqual(recorder.values, [true])
        XCTAssertFalse(controller.isBookmarked)
        XCTAssertFalse(controller.canToggle)
        XCTAssertFalse(controller.toggle())
        XCTAssertEqual(backend.updateAttempts.count, 1)

        controller.start()
        XCTAssertTrue(controller.isBookmarked)
        XCTAssertTrue(controller.canToggle)
    }

    func testOutstandingReadDoesNotRetainController() async {
        let backend = PlayerBookmarkTestBackend()
        backend.setState(false, for: firstTarget, isReady: false)
        defer { backend.finishReads() }
        var controller: PlayerBookmarkController? = backend.makeController()
        weak var weakController: PlayerBookmarkController?
        weakController = controller
        controller?.updateTarget(firstTarget)
        controller?.start()
        let read = await backend.nextRead()

        controller = nil

        XCTAssertNil(weakController)
        read.resolve(true)
        backend.postChange()
        XCTAssertEqual(backend.storedStateRequests.count, 2)
    }
}

@MainActor
private final class PlayerBookmarkTestBackend {
    typealias Target = PlayerBookmarkController.Target
    typealias Update = PlayerBookmarkPresentationState.ToggleRequest

    @MainActor
    final class Read {
        let target: Target
        private var continuation: CheckedContinuation<Bool, Never>?

        init(target: Target, continuation: CheckedContinuation<Bool, Never>) {
            self.target = target
            self.continuation = continuation
        }

        func resolve(_ value: Bool) {
            let continuation = continuation
            self.continuation = nil
            continuation?.resume(returning: value)
        }
    }

    private struct PendingUpdate {
        let request: Update
        let completion: @MainActor @Sendable (Bool) -> Void
    }

    private let notificationCenter = NotificationCenter()
    private var states = [Target: PlayerStoredBookmarkState]()
    private var reads = [Read]()
    private var unreadReads = [Read]()
    private var readWaiters = [CheckedContinuation<Read, Never>]()
    private var pendingUpdates = [PendingUpdate]()
    private var didFinishReads = false
    private(set) var storedStateRequests = [Target]()
    private(set) var updateAttempts = [Update]()
    var admitsUpdates = true

    func makeController() -> PlayerBookmarkController {
        PlayerBookmarkController(
            dependencies: .init(
                storedState: { [self] target in
                    storedStateRequests.append(target)
                    return state(for: target)
                },
                isBookmarked: { [self] target in
                    await read(target)
                },
                enqueueUpdate: { [self] target, isBookmarked, completion in
                    let request = Update(target: target, isBookmarked: isBookmarked)
                    updateAttempts.append(request)
                    guard admitsUpdates else { return false }
                    setState(
                        state(for: target).isBookmarked,
                        for: target,
                        isTogglePending: true
                    )
                    pendingUpdates.append(PendingUpdate(
                        request: request,
                        completion: completion
                    ))
                    return true
                }
            ),
            notificationCenter: notificationCenter
        )
    }

    func setState(
        _ isBookmarked: Bool,
        for target: Target,
        isTogglePending: Bool = false,
        isReady: Bool = true
    ) {
        states[target] = PlayerStoredBookmarkState(
            isBookmarked: isBookmarked,
            isTogglePending: isTogglePending,
            isReady: isReady
        )
    }

    private func state(for target: Target) -> PlayerStoredBookmarkState {
        states[target] ?? PlayerStoredBookmarkState(
            isBookmarked: false,
            isTogglePending: false,
            isReady: true
        )
    }

    private func read(_ target: Target) async -> Bool {
        guard !didFinishReads else { return state(for: target).isBookmarked }
        return await withCheckedContinuation { continuation in
            let read = Read(target: target, continuation: continuation)
            reads.append(read)
            if readWaiters.isEmpty {
                unreadReads.append(read)
            } else {
                readWaiters.removeFirst().resume(returning: read)
            }
        }
    }

    func nextRead() async -> Read {
        if !unreadReads.isEmpty {
            return unreadReads.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            readWaiters.append(continuation)
        }
    }

    func finishReads() {
        didFinishReads = true
        reads.forEach { $0.resolve(false) }
        reads.removeAll()
        unreadReads.removeAll()
    }

    func postChange() {
        notificationCenter.post(name: .playerBookmarksDidChange, object: nil)
    }

    func completeNextUpdate(isBookmarked: Bool) {
        let update = pendingUpdates.removeFirst()
        setState(isBookmarked, for: update.request.target)
        update.completion(isBookmarked)
    }
}

@MainActor
private final class PlayerBookmarkCompletionRecorder {
    private(set) var targets = [PlayerBookmarkController.Target]()
    private(set) var values = [Bool]()

    func record(target: PlayerBookmarkController.Target, isBookmarked: Bool) {
        targets.append(target)
        values.append(isBookmarked)
    }
}
