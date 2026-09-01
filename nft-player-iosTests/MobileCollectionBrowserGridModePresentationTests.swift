// ∅ 2026 lil org

import CoreImage
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobileCollectionBrowserGridModePresentationTests:
    XCTestCase {}

@MainActor
extension MobileCollectionBrowserGridModePresentationTests {

    final class PlaybackDisplay: MobilePlaybackSessionDisplay {
        func navigate(_ direction: PlaybackNavigationDirection) {}

        func getCurrentPagePosition() -> PlayerPagePosition {
            .initial
        }

        func flushPendingViewingProgress() {}
    }

    final class TestPinchGestureRecognizer: UIPinchGestureRecognizer {
        var reportedState: UIGestureRecognizer.State = .possible
        var reportedLocation = CGPoint.zero

        override var state: UIGestureRecognizer.State {
            get { reportedState }
            set { reportedState = newValue }
        }

        override func location(in view: UIView?) -> CGPoint {
            reportedLocation
        }
    }

    final class ManualGridTransitionFrameDriver: GridTransitionFrameDriving {
        private var onFrame: (@MainActor (GridTransitionFrame) -> Void)?
        private var isInvalidated = false

        private(set) var now: TimeInterval
        private(set) var isRunning = false

        init(now: TimeInterval = CACurrentMediaTime()) {
            self.now = now
        }

        func start(
            onFrame: @escaping @MainActor (GridTransitionFrame) -> Void
        ) {
            guard !isInvalidated else { return }
            self.onFrame = onFrame
            isRunning = true
        }

        func stop() {
            isRunning = false
            onFrame = nil
        }

        func invalidate() {
            guard !isInvalidated else { return }
            isInvalidated = true
            stop()
        }

        func advance(by interval: TimeInterval = 1 / 60) {
            precondition(interval.isFinite && interval >= 0)
            advance(to: now + interval)
        }

        func advance(to timestamp: TimeInterval) {
            precondition(timestamp.isFinite && timestamp >= now)
            now = timestamp
            guard isRunning else { return }
            onFrame?(GridTransitionFrame(
                timestamp: timestamp,
                targetTimestamp: timestamp + 1 / 60
            ))
        }
    }

    @MainActor
    final class Fixture {
        let session: MobilePlaybackSession
        let display: PlaybackDisplay
        let controller: VerticalCollectionBrowserViewController
        let window: UIWindow
        let gridTransitionFrameDriver: ManualGridTransitionFrameDriver?

        init(
            session: MobilePlaybackSession,
            display: PlaybackDisplay,
            controller: VerticalCollectionBrowserViewController,
            window: UIWindow,
            gridTransitionFrameDriver: ManualGridTransitionFrameDriver?
        ) {
            self.session = session
            self.display = display
            self.controller = controller
            self.window = window
            self.gridTransitionFrameDriver = gridTransitionFrameDriver
        }
    }

    @MainActor
    final class ReentryState {
        var didReenter = false
    }

    func collectionMetadata(
        minimumTokenCount: Int = 4,
        requiresBundledGenerativeToken: Bool = false
    ) throws -> (
        id: String,
        internalSlug: String
    ) {
        let item = try XCTUnwrap(
            SuggestedItemsService.visibleItems.first { item in
                guard let internalSlug = item.internalSlug,
                      !internalSlug.isEmpty,
                      PlayerCollectionBrowserSupport.isAvailable(
                          forCollectionId: item.id
                      ) else {
                    return false
                }
                let tokenCount = CollectionCatalog.tokenCount(
                    specificCollectionId: item.id
                )
                return tokenCount >= minimumTokenCount && tokenCount <= 512
                    && CollectionCatalog.canGenerateToken(
                        specificCollectionId: item.id,
                        tokenIndex: 0
                    )
                    && (!requiresBundledGenerativeToken
                        || TokenGenerator.bundledWebGenerativeToken(
                            specificCollectionId: item.id,
                            tokenIndex: 0
                        ) != nil)
            }
        )
        return (item.id, try XCTUnwrap(item.internalSlug))
    }

    func collectionId(internalSlug: String) throws -> String {
        try XCTUnwrap(
            SuggestedItemsService.visibleItems.first {
                $0.internalSlug == internalSlug
            }?.id
        )
    }

    func makeFixture(
        collectionId: String,
        gridModeCommitSnapshotFactory: ((UIView) -> UIView?)? = nil,
        gridTransitionFrameDriver: ManualGridTransitionFrameDriver? = nil
    ) throws -> Fixture {
        let uuid = UUID()
        let session = MobilePlaybackController.shared.startSession(
            config: MobilePlayerConfig(
                id: uuid,
                initialItemId: collectionId,
                initialTokenIndex: 0
            )
        )
        let display = PlaybackDisplay()
        session.attach(display: display)

        let controller: VerticalCollectionBrowserViewController
        if let gridModeCommitSnapshotFactory {
            controller = VerticalCollectionBrowserViewController(
                playbackSession: session,
                gridModeCommitSnapshotFactory: gridModeCommitSnapshotFactory,
                gridTransitionFrameDriver: gridTransitionFrameDriver
            )
        } else {
            controller = VerticalCollectionBrowserViewController(
                playbackSession: session,
                gridTransitionFrameDriver: gridTransitionFrameDriver
            )
        }
        let foregroundScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        let window = UIWindow(windowScene: foregroundScene)
        window.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.viewDidAppear(false)
        controller.setActive(true)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.gridMode, .threeColumns)
        XCTAssertNotNil(controller.currentPagePosition)
        return Fixture(
            session: session,
            display: display,
            controller: controller,
            window: window,
            gridTransitionFrameDriver: gridTransitionFrameDriver
        )
    }

    func makeDeterministicFixture(
        collectionId: String,
        gridModeCommitSnapshotFactory: ((UIView) -> UIView?)? = nil
    ) throws -> Fixture {
        try makeFixture(
            collectionId: collectionId,
            gridModeCommitSnapshotFactory: gridModeCommitSnapshotFactory,
            gridTransitionFrameDriver: ManualGridTransitionFrameDriver()
        )
    }

    func tearDownFixture(_ fixture: Fixture) {
        fixture.controller.cancelPendingDisplayPreparation()
        fixture.controller.setActive(false)
        fixture.window.isHidden = true
        fixture.window.rootViewController = nil
        fixture.session.stopAndDisconnect()
    }

    func selectGridMode(
        _ mode: MobileCollectionBrowserGridMode,
        controller: VerticalCollectionBrowserViewController
    ) async throws {
        XCTAssertTrue(controller.setGridMode(mode))
        for _ in 0..<200 {
            if controller.gridMode == mode {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Grid mode did not settle to \(mode)")
    }

    func selectGridMode(
        _ mode: MobileCollectionBrowserGridMode,
        fixture: Fixture
    ) {
        XCTAssertTrue(fixture.controller.setGridMode(mode))
        advanceGridTransitionFrames(
            "Grid mode did not settle to \(mode)",
            fixture: fixture
        ) {
            fixture.controller.gridMode == mode
        }
    }

    func advanceGridTransitionFrames(
        _ failureMessage: String,
        fixture: Fixture,
        maximumFrameCount: Int = 200,
        until condition: () -> Bool
    ) {
        guard let frameDriver = fixture.gridTransitionFrameDriver else {
            XCTFail("Fixture does not have a manual grid-transition frame driver")
            return
        }
        for _ in 0..<maximumFrameCount {
            if condition() {
                return
            }
            frameDriver.advance()
        }
        XCTFail(failureMessage)
    }

    func prepare(
        _ controller: VerticalCollectionBrowserViewController,
        using preparation: PlayerCollectionBrowsePreparation,
        forcePosition: Bool = false
    ) async -> MobilePlayerCollectionBrowserDisplayPreparationResult {
        await withCheckedContinuation { continuation in
            controller.prepareForDisplay(
                using: preparation,
                forcePosition: forcePosition,
                publishWhenStable: false
            ) {
                continuation.resume(returning: $0)
            }
        }
    }

    func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    func waitUntil(
        _ description: String,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(description)
    }

    func sendPinch(
        _ recognizer: UIPinchGestureRecognizer,
        to controller: VerticalCollectionBrowserViewController
    ) {
        controller.handleGridModePinchForTesting(recognizer)
    }

    func skipIfReduceMotionEnabled() throws {
        try XCTSkipIf(
            UIAccessibility.isReduceMotionEnabled,
            "Reduce Motion applies grid modes directly without a settle"
        )
    }

    func centerPixelRGBA(
        in image: UIImage
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let ciImage = CIImage(cgImage: cgImage)
        let sampleBounds = CGRect(
            x: floor(ciImage.extent.midX),
            y: floor(ciImage.extent.midY),
            width: 1,
            height: 1
        )
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            CIContext().render(
                ciImage,
                toBitmap: bytes.baseAddress!,
                rowBytes: 4,
                bounds: sampleBounds,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}
