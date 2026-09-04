import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobilePlayerBookmarkMenuActionTests: XCTestCase {}

@MainActor
extension MobilePlayerBookmarkMenuActionTests {
    private var target: PlayerBookmarkController.Target {
        .init(collectionId: "collection-a", tokenId: "token-a")
    }

    func testMenuKeepsTargetAndExplicitIntentAfterSyncChanges() async throws {
        for initiallyBookmarked in [false, true] {
            let backend = BookmarkMenuBackend()
            backend.setState(initiallyBookmarked, for: target)
            var acceptedCount = 0
            var menu: MobilePlayerBookmarkMenuAction? = .init(
                target: target,
                controller: backend.makeController(),
                onAccepted: { acceptedCount += 1 }
            )
            weak var weakMenu = menu
            let action = try await resolveAction(try XCTUnwrap(menu))
            XCTAssertEqual(
                action.title,
                initiallyBookmarked ? Strings.removeBookmark : Strings.bookmark
            )

            menu = nil
            XCTAssertNotNil(weakMenu)
            backend.setState(!initiallyBookmarked, for: target)
            backend.postChange()
            perform(action)
            perform(action)

            XCTAssertEqual(backend.updates.map(\.target), [target])
            XCTAssertEqual(backend.updates.map(\.isBookmarked), [!initiallyBookmarked])
            XCTAssertEqual(acceptedCount, 1)
            backend.completeUpdate()
        }
    }

    func testPendingUpdateDisablesActionWithoutHaptics() async throws {
        let backend = BookmarkMenuBackend()
        backend.setState(false, for: target, isPending: true)
        var acceptedCount = 0
        let menu = MobilePlayerBookmarkMenuAction(
            target: target,
            controller: backend.makeController(),
            onAccepted: { acceptedCount += 1 }
        )
        let action = try await resolveAction(menu)

        XCTAssertTrue(action.attributes.contains(.disabled))
        perform(action)
        XCTAssertTrue(backend.updates.isEmpty)
        XCTAssertEqual(acceptedCount, 0)
    }

    func testRejectedUpdateDoesNotProduceHaptic() async throws {
        let backend = BookmarkMenuBackend()
        backend.setState(false, for: target)
        backend.admitsUpdates = false
        var acceptedCount = 0
        let menu = MobilePlayerBookmarkMenuAction(
            target: target,
            controller: backend.makeController(),
            onAccepted: { acceptedCount += 1 }
        )
        let action = try await resolveAction(menu)

        perform(action)

        XCTAssertEqual(backend.updates.count, 1)
        XCTAssertEqual(acceptedCount, 0)
    }

    func testDelayedReadCannotReplaceNewSyncedState() async throws {
        let backend = BookmarkMenuBackend()
        backend.setState(false, for: target, isReady: false)
        backend.suspendsReads = true
        defer { backend.finishReads(returning: false) }
        let readStarted = expectation(description: "Bookmark read started")
        backend.onRead = { readStarted.fulfill() }
        let resolved = expectation(description: "Menu resolved")
        var elements = [UIMenuElement]()
        let menu = MobilePlayerBookmarkMenuAction(
            target: target,
            controller: backend.makeController()
        )
        menu.resolve {
            elements = $0
            resolved.fulfill()
        }
        await fulfillment(of: [readStarted], timeout: 2)

        backend.setState(true, for: target)
        backend.postChange()
        backend.finishReads(returning: false)
        await fulfillment(of: [resolved], timeout: 2)

        let action = try XCTUnwrap(elements.first as? UIAction)
        XCTAssertEqual(action.title, Strings.removeBookmark)
        XCTAssertFalse(action.attributes.contains(.disabled))
    }

    func testRepeatedResolutionCompletesOnceWhenOlderReadsReturnLast() async throws {
        let backend = BookmarkMenuBackend()
        backend.setState(false, for: target, isReady: false)
        backend.suspendsReads = true
        defer { backend.finishReads(returning: false) }
        let controller = backend.makeController()
        let menu = MobilePlayerBookmarkMenuAction(target: target, controller: controller)
        let startupRead = await backend.nextRead()
        var supersededCompletionCount = 0
        menu.resolve {
            XCTAssertTrue($0.isEmpty)
            supersededCompletionCount += 1
        }
        let supersededRead = await backend.nextRead()
        var replacementCompletionCount = 0
        var replacementElements = [UIMenuElement]()
        let replacementResolved = expectation(description: "Replacement menu resolved")
        menu.resolve {
            replacementCompletionCount += 1
            replacementElements = $0
            replacementResolved.fulfill()
        }
        let replacementRead = await backend.nextRead()

        XCTAssertEqual(supersededCompletionCount, 1)
        XCTAssertEqual(replacementCompletionCount, 0)
        replacementRead.resolve(true)
        await fulfillment(of: [replacementResolved], timeout: 2)

        let action = try XCTUnwrap(replacementElements.first as? UIAction)
        XCTAssertEqual(replacementElements.count, 1)
        XCTAssertEqual(action.title, Strings.removeBookmark)
        XCTAssertFalse(action.attributes.contains(.disabled))
        XCTAssertTrue(controller.isBookmarked)

        let staleReadsReturned = expectation(description: "Stale reads returned")
        staleReadsReturned.expectedFulfillmentCount = 2
        supersededRead.onReturn = { staleReadsReturned.fulfill() }
        startupRead.onReturn = { staleReadsReturned.fulfill() }
        supersededRead.resolve(false)
        startupRead.resolve(false)
        await fulfillment(of: [staleReadsReturned], timeout: 2)

        XCTAssertEqual(supersededCompletionCount, 1)
        XCTAssertEqual(replacementCompletionCount, 1)
        XCTAssertTrue(controller.isBookmarked)
    }

    func testDiscardedMenuReleasesObservationAndCompletesPendingResolutionOnce() async {
        let backend = BookmarkMenuBackend()
        backend.setState(false, for: target, isReady: false)
        backend.suspendsReads = true
        defer { backend.finishReads(returning: false) }
        let readStarted = expectation(description: "Bookmark read started")
        backend.onRead = { readStarted.fulfill() }
        var menu: MobilePlayerBookmarkMenuAction? = .init(
            target: target,
            controller: backend.makeController()
        )
        weak var weakMenu = menu
        var completionCount = 0
        menu?.resolve {
            XCTAssertTrue($0.isEmpty)
            completionCount += 1
        }
        await fulfillment(of: [readStarted], timeout: 2)

        menu = nil

        XCTAssertNil(weakMenu)
        XCTAssertEqual(completionCount, 1)
        let readCount = backend.storedStateReadCount
        backend.postChange()
        XCTAssertEqual(backend.storedStateReadCount, readCount)
        backend.finishReads(returning: true)
        await Task.yield()
        XCTAssertEqual(completionCount, 1)
    }

    private func resolveAction(_ menu: MobilePlayerBookmarkMenuAction) async throws -> UIAction {
        let elements = await withCheckedContinuation { continuation in
            menu.resolve { continuation.resume(returning: $0) }
        }
        return try XCTUnwrap(elements.first as? UIAction)
    }

    private func perform(_ action: UIAction) {
        let button = UIButton()
        button.addAction(action, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
    }
}

@MainActor
private final class BookmarkMenuBackend {
    typealias Target = PlayerBookmarkController.Target
    typealias Update = PlayerBookmarkPresentationState.ToggleRequest

    @MainActor
    final class Read {
        private var continuation: CheckedContinuation<Bool, Never>?
        var onReturn: (() -> Void)?

        init(continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resolve(_ value: Bool) {
            let continuation = continuation
            self.continuation = nil
            continuation?.resume(returning: value)
        }
    }

    private let notificationCenter = NotificationCenter()
    private var states = [Target: PlayerStoredBookmarkState]()
    private var reads = [Read]()
    private var unreadReads = [Read]()
    private var readWaiters = [CheckedContinuation<Read, Never>]()
    private var updateCompletion: (@MainActor @Sendable (Bool) -> Void)?
    private(set) var updates = [Update]()
    private(set) var storedStateReadCount = 0
    var suspendsReads = false
    var admitsUpdates = true
    var onRead: (() -> Void)?

    func makeController() -> PlayerBookmarkController {
        PlayerBookmarkController(
            dependencies: .init(
                storedState: { [self] target in
                    storedStateReadCount += 1
                    return state(for: target)
                },
                isBookmarked: { [self] target in
                    guard suspendsReads else { return state(for: target).isBookmarked }
                    var startedRead: Read?
                    let value = await withCheckedContinuation { continuation in
                        let read = Read(continuation: continuation)
                        startedRead = read
                        reads.append(read)
                        if readWaiters.isEmpty {
                            unreadReads.append(read)
                        } else {
                            readWaiters.removeFirst().resume(returning: read)
                        }
                        let callback = onRead
                        onRead = nil
                        callback?()
                    }
                    startedRead?.onReturn?()
                    return value
                },
                enqueueUpdate: { [self] target, isBookmarked, completion in
                    updates.append(Update(target: target, isBookmarked: isBookmarked))
                    guard admitsUpdates else { return false }
                    setState(state(for: target).isBookmarked, for: target, isPending: true)
                    updateCompletion = completion
                    return true
                }
            ),
            notificationCenter: notificationCenter
        )
    }

    func setState(
        _ isBookmarked: Bool,
        for target: Target,
        isPending: Bool = false,
        isReady: Bool = true
    ) {
        states[target] = PlayerStoredBookmarkState(
            isBookmarked: isBookmarked,
            isTogglePending: isPending,
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

    func nextRead() async -> Read {
        if !unreadReads.isEmpty {
            return unreadReads.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            readWaiters.append(continuation)
        }
    }

    func finishReads(returning value: Bool) {
        suspendsReads = false
        let reads = reads
        self.reads.removeAll()
        unreadReads.removeAll()
        reads.forEach { $0.resolve(value) }
    }

    func completeUpdate() {
        guard let update = updates.last else { return }
        setState(update.isBookmarked, for: update.target)
        let completion = updateCompletion
        updateCompletion = nil
        completion?(update.isBookmarked)
    }

    func postChange() {
        notificationCenter.post(name: .playerBookmarksDidChange, object: nil)
    }
}
