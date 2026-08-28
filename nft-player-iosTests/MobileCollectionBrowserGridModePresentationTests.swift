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

    @MainActor
    final class Fixture {
        let session: MobilePlaybackSession
        let display: PlaybackDisplay
        let controller: VerticalCollectionBrowserViewController
        let window: UIWindow

        init(
            session: MobilePlaybackSession,
            display: PlaybackDisplay,
            controller: VerticalCollectionBrowserViewController,
            window: UIWindow
        ) {
            self.session = session
            self.display = display
            self.controller = controller
            self.window = window
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
        gridModeCommitSnapshotFactory: ((UIView) -> UIView?)? = nil
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
                gridModeCommitSnapshotFactory: gridModeCommitSnapshotFactory
            )
        } else {
            controller = VerticalCollectionBrowserViewController(
                playbackSession: session
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
            window: window
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
