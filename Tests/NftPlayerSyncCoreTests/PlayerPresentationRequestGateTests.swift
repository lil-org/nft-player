// ∅ 2026 lil org

import XCTest
@testable import NftPlayerSyncCore

@MainActor
final class PlayerPresentationRequestGateTests: XCTestCase {

    func testCancellationRejectsCommitWithoutEffects() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let request = gate.begin()

        gate.cancel()
        let didCommit = gate.commit(
            request,
            present: { recorder.events.append("present") },
            persist: { recorder.events.append("persist") }
        )
        await PlayerPersistenceUpdates.flush()

        XCTAssertFalse(didCommit)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testSupersededRequestIsRejected() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let firstRequest = gate.begin()
        let secondRequest = gate.begin()

        let didCommitFirst = gate.commit(
            firstRequest,
            present: { recorder.events.append("present-first") },
            persist: { recorder.events.append("persist-first") }
        )
        let didCommitSecond = gate.commit(
            secondRequest,
            present: { recorder.events.append("present-second") },
            persist: { recorder.events.append("persist-second") }
        )
        await PlayerPersistenceUpdates.flush()

        XCTAssertFalse(didCommitFirst)
        XCTAssertTrue(didCommitSecond)
        XCTAssertEqual(recorder.events, ["present-second", "persist-second"])
    }

    func testCompletedResolutionRejectsCapturedRequest() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let request = gate.begin()
        let resolution = gate.resolutionForPendingRequest()

        resolution?(true)
        let didCommit = gate.commit(
            request,
            present: { recorder.events.append("present") },
            persist: { recorder.events.append("persist") }
        )
        await PlayerPersistenceUpdates.flush()

        XCTAssertFalse(didCommit)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testCompletedResolutionPreservesReplacementRequest() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        _ = gate.begin()
        let resolution = gate.resolutionForPendingRequest()
        let replacementRequest = gate.begin()

        resolution?(true)
        let didCommit = gate.commit(
            replacementRequest,
            present: { recorder.events.append("present") },
            persist: { recorder.events.append("persist") }
        )
        await PlayerPersistenceUpdates.flush()

        XCTAssertTrue(didCommit)
        XCTAssertEqual(recorder.events, ["present", "persist"])
    }

    func testDeferredCommitRunsAfterCancelledResolution() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let request = gate.begin()
        let resolution = gate.resolutionForPendingRequest()

        XCTAssertTrue(
            gate.commit(
                request,
                present: { recorder.events.append("present") },
                persist: { recorder.events.append("persist") }
            )
        )
        XCTAssertTrue(recorder.events.isEmpty)

        resolution?(false)
        await PlayerPersistenceUpdates.flush()

        XCTAssertEqual(recorder.events, ["present", "persist"])
    }

    func testDeferredCommitIsDroppedAfterCompletedResolution() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let request = gate.begin()
        let resolution = gate.resolutionForPendingRequest()

        XCTAssertTrue(
            gate.commit(
                request,
                present: { recorder.events.append("present") },
                persist: { recorder.events.append("persist") }
            )
        )
        resolution?(true)
        await PlayerPersistenceUpdates.flush()

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testDeferredRequestCanOnlyCommitOnce() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let request = gate.begin()
        let resolution = gate.resolutionForPendingRequest()

        XCTAssertTrue(
            gate.commit(
                request,
                present: { recorder.events.append("present") },
                persist: { recorder.events.append("persist") }
            )
        )
        XCTAssertFalse(
            gate.commit(
                request,
                present: { recorder.events.append("present-again") },
                persist: { recorder.events.append("persist-again") }
            )
        )
        resolution?(false)
        await PlayerPersistenceUpdates.flush()

        XCTAssertEqual(recorder.events, ["present", "persist"])
    }

    func testCommittedRequestCanOnlyCommitOnce() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let request = gate.begin()

        let didCommitFirst = gate.commit(
            request,
            present: { recorder.events.append("present") },
            persist: { recorder.events.append("persist") }
        )
        let didCommitSecond = gate.commit(
            request,
            present: { recorder.events.append("present-again") },
            persist: { recorder.events.append("persist-again") }
        )
        await PlayerPersistenceUpdates.flush()

        XCTAssertTrue(didCommitFirst)
        XCTAssertFalse(didCommitSecond)
        XCTAssertEqual(recorder.events, ["present", "persist"])
    }

    func testPresentationRunsBeforePersistence() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let request = gate.begin()

        XCTAssertTrue(
            gate.commit(
                request,
                present: { recorder.events.append("present") },
                persist: { recorder.events.append("persist") }
            )
        )
        XCTAssertEqual(recorder.events, ["present"])

        await PlayerPersistenceUpdates.flush()

        XCTAssertEqual(recorder.events, ["present", "persist"])
    }

    func testCommittedPersistenceRunsInFIFOOrder() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let blocker = PlayerPresentationPersistenceBlocker()

        let firstRequest = gate.begin()
        XCTAssertTrue(
            gate.commit(
                firstRequest,
                present: { recorder.events.append("present-first") },
                persist: {
                    await blocker.wait()
                    recorder.events.append("persist-first")
                }
            )
        )

        let secondRequest = gate.begin()
        XCTAssertTrue(
            gate.commit(
                secondRequest,
                present: { recorder.events.append("present-second") },
                persist: { recorder.events.append("persist-second") }
            )
        )
        XCTAssertEqual(recorder.events, ["present-first", "present-second"])

        await blocker.open()
        await PlayerPersistenceUpdates.flush()

        XCTAssertEqual(
            recorder.events,
            ["present-first", "present-second", "persist-first", "persist-second"]
        )
    }

    func testNestedCommitPreservesPresentationPersistenceOrder() async {
        await PlayerPersistenceUpdates.flush()
        let gate = PlayerPresentationRequestGate()
        let recorder = PlayerPresentationRecorder()
        let firstRequest = gate.begin()

        XCTAssertTrue(
            gate.commit(
                firstRequest,
                present: {
                    recorder.events.append("present-first")
                    let secondRequest = gate.begin()
                    XCTAssertTrue(
                        gate.commit(
                            secondRequest,
                            present: { recorder.events.append("present-second") },
                            persist: { recorder.events.append("persist-second") }
                        )
                    )
                },
                persist: { recorder.events.append("persist-first") }
            )
        )
        XCTAssertEqual(recorder.events, ["present-first", "present-second"])

        await PlayerPersistenceUpdates.flush()

        XCTAssertEqual(
            recorder.events,
            ["present-first", "present-second", "persist-first", "persist-second"]
        )
    }
}

@MainActor
private final class PlayerPresentationRecorder {
    var events = [String]()
}

private actor PlayerPresentationPersistenceBlocker {
    private var isOpen = false
    private var continuations = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waitingContinuations = continuations
        continuations.removeAll()
        waitingContinuations.forEach { $0.resume() }
    }
}
