// ∅ 2026 lil org

import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
final class MobileCollectionBrowserGridModePresentationTests: XCTestCase {

    private final class PlaybackDisplay: MobilePlaybackControllerDisplay {
        func navigate(_ direction: PlaybackNavigationDirection) {}

        func getCurrentPagePosition() -> PlayerPagePosition {
            .initial
        }

        func flushPendingViewingProgress() {}
    }

    private struct Fixture {
        let uuid: UUID
        let controller: VerticalCollectionBrowserViewController
        let window: UIWindow
    }

    private func collectionMetadata() throws -> (
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
                return tokenCount >= 4 && tokenCount <= 512
                    && CollectionCatalog.canGenerateToken(
                        specificCollectionId: item.id,
                        tokenIndex: 0
                    )
            }
        )
        return (item.id, try XCTUnwrap(item.internalSlug))
    }

    private func makeFixture(collectionId: String) throws -> Fixture {
        let uuid = UUID()
        let display = PlaybackDisplay()
        MobilePlaybackController.shared.subscribe(
            config: MobilePlayerConfig(
                id: uuid,
                initialItemId: collectionId,
                initialTokenIndex: 0
            ),
            display: display
        )

        let controller = VerticalCollectionBrowserViewController(uuid: uuid)
        let window = UIWindow(frame: CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        ))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.setActive(true)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.gridMode, .threeColumns)
        XCTAssertNotNil(controller.currentPagePosition)
        return Fixture(uuid: uuid, controller: controller, window: window)
    }

    private func tearDownFixture(_ fixture: Fixture) {
        fixture.controller.cancelPendingDisplayPreparation()
        fixture.controller.setActive(false)
        fixture.window.isHidden = true
        fixture.window.rootViewController = nil
        MobilePlaybackController.shared.stopAndDisconnect(uuid: fixture.uuid)
    }

    private func selectGridMode(
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

    private func prepare(
        _ controller: VerticalCollectionBrowserViewController,
        using preparation: PlayerCollectionBrowsePreparation
    ) async -> MobilePlayerCollectionBrowserDisplayPreparationResult {
        await withCheckedContinuation { continuation in
            controller.prepareForDisplay(
                using: preparation,
                publishWhenStable: false
            ) {
                continuation.resume(returning: $0)
            }
        }
    }

    private func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func skipIfReduceMotionEnabled() throws {
        try XCTSkipIf(
            UIAccessibility.isReduceMotionEnabled,
            "Reduce Motion applies grid modes directly without a settle"
        )
    }

    func testRestartCollectionPreservesTemporaryGridMode() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(
            .fiveColumns,
            controller: fixture.controller
        )

        fixture.controller.scrollToFirstItemAndPublish()
        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
    }

    func testSettleReservesCollectionPanForOneFingerAndRestoresIt() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let platformMaximumNumberOfTouches = panGestureRecognizer
            .maximumNumberOfTouches
        defer {
            panGestureRecognizer.maximumNumberOfTouches =
                platformMaximumNumberOfTouches
        }
        let configuredMaximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches =
            configuredMaximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))

        XCTAssertEqual(panGestureRecognizer.minimumNumberOfTouches, 1)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        fixture.controller.setActive(false)

        XCTAssertEqual(
            panGestureRecognizer.maximumNumberOfTouches,
            configuredMaximumNumberOfTouches
        )
    }

    func testFreshGridModeSuspensionSurvivesPendingLayoutScrollEndReentry()
        throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let platformMaximumNumberOfTouches = panGestureRecognizer
            .maximumNumberOfTouches
        defer {
            panGestureRecognizer.maximumNumberOfTouches =
                platformMaximumNumberOfTouches
        }
        let configuredMaximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches =
            configuredMaximumNumberOfTouches
        var pendingBounds = fixture.controller.view.bounds
        pendingBounds.size.height -= 1
        fixture.controller.view.bounds = pendingBounds
        fixture.controller.view.setNeedsLayout()
        var didReenterScrollEnd = false
        let observation = collectionView.observe(
            \.isScrollEnabled,
            options: [.new]
        ) { _, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated {
                didReenterScrollEnd = true
                fixture.controller.scrollViewDidEndDecelerating(collectionView)
            }
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        withExtendedLifetime(observation) {}
        XCTAssertTrue(didReenterScrollEnd)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        fixture.controller.setActive(false)

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertEqual(
            panGestureRecognizer.maximumNumberOfTouches,
            configuredMaximumNumberOfTouches
        )
    }

    func testSettleStartupIgnoresSynchronousDragReentry() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let platformMaximumNumberOfTouches = panGestureRecognizer
            .maximumNumberOfTouches
        defer {
            panGestureRecognizer.maximumNumberOfTouches =
                platformMaximumNumberOfTouches
        }
        let configuredMaximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches =
            configuredMaximumNumberOfTouches
        var didReenterDrag = false
        let observation = collectionView.observe(
            \.isScrollEnabled,
            options: [.new]
        ) { _, change in
            guard change.newValue == true, !didReenterDrag else { return }
            MainActor.assumeIsolated {
                didReenterDrag = true
                fixture.controller.scrollViewWillBeginDragging(collectionView)
            }
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        withExtendedLifetime(observation) {}

        XCTAssertTrue(didReenterDrag)
        XCTAssertEqual(fixture.controller.gridMode, .threeColumns)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        fixture.controller.setActive(false)

        XCTAssertEqual(
            panGestureRecognizer.maximumNumberOfTouches,
            configuredMaximumNumberOfTouches
        )
    }

    func testDragDuringRendererHandoffSkipsPositionSettlement() async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        )
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: PlayerPagePosition(position: tokenCount - 1)
            )
        )
        let preparationResult = await prepare(
            fixture.controller,
            using: preparation
        )
        XCTAssertEqual(preparationResult, .prepared)
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }
        var didReenterDrag = false
        let observation = collectionView.observe(
            \.contentOffset,
            options: [.new]
        ) { _, _ in
            MainActor.assumeIsolated {
                guard fixture.controller.gridMode == .fiveColumns,
                      !didReenterDrag else {
                    return
                }
                didReenterDrag = true
                fixture.controller.scrollViewWillBeginDragging(collectionView)
            }
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        for _ in 0..<200 {
            if fixture.controller.gridMode == .fiveColumns {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        withExtendedLifetime(observation) {}

        XCTAssertTrue(didReenterDrag)
        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertTrue(settledPagePositions.isEmpty)
    }

    func testAccessibilityScrollInterruptsSettleBeforeScrolling() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let platformMaximumNumberOfTouches = panGestureRecognizer
            .maximumNumberOfTouches
        defer {
            panGestureRecognizer.maximumNumberOfTouches =
                platformMaximumNumberOfTouches
        }
        let configuredMaximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches =
            configuredMaximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        _ = collectionView.accessibilityScroll(.down)

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertEqual(
            panGestureRecognizer.maximumNumberOfTouches,
            configuredMaximumNumberOfTouches
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
    }

    func testFailedAccessibilityScrollSettlesInterruptedPosition() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertFalse(collectionView.accessibilityScroll(.left))

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
    }

    func testFailedAccessibilityScrollAppliesPendingSafeAreaRefreshBeforeSettlement()
        throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        var settledContentSizeHeights = [CGFloat]()
        fixture.controller.onSettledPagePosition = { _, _ in
            settledContentSizeHeights.append(collectionView.contentSize.height)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        fixture.controller.additionalSafeAreaInsets.bottom += 37
        XCTAssertFalse(collectionView.accessibilityScroll(.left))

        XCTAssertEqual(settledContentSizeHeights.count, 1)
        fixture.controller.view.layoutIfNeeded()
        XCTAssertEqual(
            settledContentSizeHeights,
            [collectionView.contentSize.height]
        )
    }

    func testScrollToTopInterruptsSettleBeforeAcceptance() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let platformMaximumNumberOfTouches = panGestureRecognizer
            .maximumNumberOfTouches
        defer {
            panGestureRecognizer.maximumNumberOfTouches =
                platformMaximumNumberOfTouches
        }
        let configuredMaximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches =
            configuredMaximumNumberOfTouches
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        XCTAssertTrue(
            fixture.controller.scrollViewShouldScrollToTop(collectionView)
        )

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertEqual(
            panGestureRecognizer.maximumNumberOfTouches,
            configuredMaximumNumberOfTouches
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            -collectionView.adjustedContentInset.top,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
        fixture.controller.scrollViewDidScrollToTop(collectionView)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
    }

    func testScrollToTopWithMotionDefersInterruptedPositionSettlement() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        let scrolledOffsetY = min(maximumOffsetY, 1_000)
        XCTAssertGreaterThan(scrolledOffsetY, minimumOffsetY)
        collectionView.contentOffset.y = scrolledOffsetY
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertTrue(
            fixture.controller.scrollViewShouldScrollToTop(collectionView)
        )

        XCTAssertGreaterThan(
            collectionView.contentOffset.y,
            -collectionView.adjustedContentInset.top
        )
        XCTAssertTrue(settledPagePositions.isEmpty)

        collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        fixture.controller.scrollViewDidScrollToTop(collectionView)

        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
    }

    func testProgrammaticScrollPreservesOffsetDeltaAfterSettleCommit() async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let focusedPagePosition = PlayerPagePosition(position: 3)
        let committedOffsetY = try await { () async throws -> CGFloat in
            let baselineFixture = try makeFixture(collectionId: metadata.id)
            defer { tearDownFixture(baselineFixture) }
            let preparation = try XCTUnwrap(
                MobilePlaybackController.shared.prepareCollectionBrowse(
                    uuid: baselineFixture.uuid,
                    containing: focusedPagePosition
                )
            )
            let preparationResult = await prepare(
                baselineFixture.controller,
                using: preparation
            )
            XCTAssertEqual(preparationResult, .prepared)
            let baselineCollectionView = try XCTUnwrap(
                baselineFixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            XCTAssertTrue(baselineFixture.controller.setGridMode(.large))
            baselineFixture.controller.setActive(false)
            return baselineCollectionView.contentOffset.y
        }()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: focusedPagePosition
            )
        )
        let preparationResult = await prepare(
            fixture.controller,
            using: preparation
        )
        XCTAssertEqual(preparationResult, .prepared)
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let sourceOffsetY = collectionView.contentOffset.y
        XCTAssertGreaterThan(abs(committedOffsetY - sourceOffsetY), 1)
        let requestedDeltaY: CGFloat = 24
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        let targetOffset = CGPoint(
            x: collectionView.contentOffset.x,
            y: collectionView.contentOffset.y + requestedDeltaY
        )
        collectionView.setContentOffset(targetOffset, animated: false)

        XCTAssertEqual(fixture.controller.gridMode, .large)
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        XCTAssertEqual(
            collectionView.contentOffset.y,
            min(
                max(committedOffsetY + requestedDeltaY, minimumOffsetY),
                maximumOffsetY
            ),
            accuracy: 0.000_001
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
    }

    func testProgrammaticNoOpOffsetsDoNotInterruptSettle() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let maximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches = maximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
        let settleContentOffset = collectionView.contentOffset

        collectionView.setContentOffset(
            settleContentOffset,
            animated: false
        )
        collectionView.setContentOffset(
            CGPoint(
                x: settleContentOffset.x + 10,
                y: settleContentOffset.y
            ),
            animated: false
        )

        XCTAssertEqual(collectionView.contentOffset, settleContentOffset)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
    }

    func testObservedNonDragScrollPreservesOffsetDeltaAfterSettleCommit()
        async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let focusedPagePosition = PlayerPagePosition(position: 3)
        let committedContentOffsetY = try await {
            () async throws -> CGFloat in
            let baselineFixture = try makeFixture(
                collectionId: metadata.id
            )
            defer { tearDownFixture(baselineFixture) }
            let preparation = try XCTUnwrap(
                MobilePlaybackController.shared.prepareCollectionBrowse(
                    uuid: baselineFixture.uuid,
                    containing: focusedPagePosition
                )
            )
            let preparationResult = await prepare(
                baselineFixture.controller,
                using: preparation
            )
            XCTAssertEqual(preparationResult, .prepared)
            let baselineCollectionView = try XCTUnwrap(
                baselineFixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            XCTAssertTrue(
                baselineFixture.controller.setGridMode(.large)
            )
            baselineFixture.controller.setActive(false)
            return baselineCollectionView.contentOffset.y
        }()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: focusedPagePosition
            )
        )
        let preparationResult = await prepare(
            fixture.controller,
            using: preparation
        )
        XCTAssertEqual(preparationResult, .prepared)
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let sourceContentOffsetY = collectionView.contentOffset.y
        XCTAssertGreaterThan(
            abs(committedContentOffsetY - sourceContentOffsetY),
            1
        )
        let observedDeltaY: CGFloat = 24
        let shiftedSourceContentOffsetY = sourceContentOffsetY
            + observedDeltaY
        var settledPagePositions = [PlayerPagePosition]()
        var settledContentOffsetYs = [CGFloat]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            settledContentOffsetYs.append(collectionView.contentOffset.y)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        collectionView.contentOffset = CGPoint(
            x: collectionView.contentOffset.x,
            y: shiftedSourceContentOffsetY
        )

        let accuracy: CGFloat = 0.000_001
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        let expectedContentOffsetY = min(
            max(
                committedContentOffsetY + observedDeltaY,
                minimumOffsetY
            ),
            maximumOffsetY
        )
        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            expectedContentOffsetY,
            accuracy: accuracy
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
        XCTAssertEqual(settledContentOffsetYs.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(settledContentOffsetYs.first),
            expectedContentOffsetY,
            accuracy: accuracy
        )
    }

    func testObservedNonDragScrollPreservesItsOffsetDelta() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let committedOffsetY = try { () throws -> CGFloat in
            let baselineFixture = try makeFixture(collectionId: metadata.id)
            defer { tearDownFixture(baselineFixture) }
            let baselineCollectionView = try XCTUnwrap(
                baselineFixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            XCTAssertTrue(baselineFixture.controller.setGridMode(.large))
            baselineFixture.controller.setActive(false)
            return baselineCollectionView.contentOffset.y
        }()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let targetOffset = CGPoint(
            x: collectionView.contentOffset.x,
            y: collectionView.contentOffset.y + 24
        )
        var settledPagePositions = [PlayerPagePosition]()
        var settledContentOffsetYs = [CGFloat]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            settledContentOffsetYs.append(collectionView.contentOffset.y)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        collectionView.contentOffset = targetOffset

        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            committedOffsetY + 24,
            accuracy: 0.000_001
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
        XCTAssertEqual(settledContentOffsetYs.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(settledContentOffsetYs.first),
            committedOffsetY + 24,
            accuracy: 0.000_001
        )
    }

    func testObservedNonDragScrollUpdatesPrefetchDirectionAfterSettleCommit()
        async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        )
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: PlayerPagePosition(position: tokenCount - 1)
            )
        )
        let preparationResult = await prepare(
            fixture.controller,
            using: preparation
        )
        XCTAssertEqual(preparationResult, .prepared)
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let backwardOffsetY = max(
            collectionView.contentOffset.y - 24,
            minimumOffsetY
        )
        XCTAssertLessThan(backwardOffsetY, collectionView.contentOffset.y)
        collectionView.contentOffset.y = backwardOffsetY
        XCTAssertEqual(fixture.controller.lastPrefetchDirection, .backward)

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        collectionView.contentOffset.y += 24

        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(fixture.controller.lastPrefetchDirection, .forward)
    }

    func testObservedNonDragScrollClampsResumedOffsetAtBothBoundaries()
        throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()

        try [false, true].forEach { movesTowardEnd in
            let fixture = try makeFixture(collectionId: metadata.id)
            defer { tearDownFixture(fixture) }
            let collectionView = try XCTUnwrap(
                fixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            var settledContentOffsetYs = [CGFloat]()
            fixture.controller.onSettledPagePosition = { _, _ in
                settledContentOffsetYs.append(collectionView.contentOffset.y)
                return true
            }

            XCTAssertTrue(fixture.controller.setGridMode(.large))
            let offsetDeltaY: CGFloat = movesTowardEnd
                ? 1_000_000
                : -1_000_000
            collectionView.contentOffset = CGPoint(
                x: collectionView.contentOffset.x,
                y: collectionView.contentOffset.y + offsetDeltaY
            )
            collectionView.layoutIfNeeded()

            let minimumOffsetY = -collectionView.adjustedContentInset.top
            let maximumOffsetY = max(
                minimumOffsetY,
                collectionView.contentSize.height
                    - collectionView.bounds.height
                    + collectionView.adjustedContentInset.bottom
            )
            let expectedOffsetY = movesTowardEnd
                ? maximumOffsetY
                : minimumOffsetY
            XCTAssertEqual(
                collectionView.contentOffset.y,
                expectedOffsetY,
                accuracy: 0.000_001
            )
            XCTAssertEqual(settledContentOffsetYs.count, 1)
            XCTAssertEqual(
                try XCTUnwrap(settledContentOffsetYs.first),
                expectedOffsetY,
                accuracy: 0.000_001
            )
        }
    }

    func testNoMotionScrollNotificationDoesNotInterruptSettle() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let maximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches = maximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        fixture.controller.scrollViewDidScroll(collectionView)

        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
    }

    func testObservedHorizontalOffsetIsRejectedWithoutInterruptingSettle()
        throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let maximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches = maximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
        let settleContentOffset = collectionView.contentOffset

        collectionView.contentOffset = CGPoint(
            x: settleContentOffset.x + 10,
            y: settleContentOffset.y
        )

        XCTAssertEqual(collectionView.contentOffset, settleContentOffset)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
    }

    func testLegacyGridModeValueIsIgnored() throws {
        let metadata = try collectionMetadata()
        let key = "iosCollectionBrowserColumnCountOverride.\(metadata.internalSlug)"
        let userDefaults = UserDefaults.standard
        let previousValue = userDefaults.object(forKey: key)
        userDefaults.set(MobileCollectionBrowserGridMode.large.rawValue, forKey: key)
        defer {
            if let previousValue {
                userDefaults.set(previousValue, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }

        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        XCTAssertEqual(fixture.controller.gridMode, .threeColumns)
    }

    func testOnePerPageRoundTripPreservesTemporaryGridModeAndFocus() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let targetPagePosition = PlayerPagePosition(position: 3)
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: targetPagePosition
            )
        )

        let result = await prepare(
            fixture.controller,
            using: preparation
        )
        XCTAssertEqual(result, .prepared)
        XCTAssertEqual(
            fixture.controller.currentPagePosition,
            targetPagePosition
        )
        try await selectGridMode(.large, controller: fixture.controller)

        fixture.controller.setActive(false)
        XCTAssertEqual(fixture.controller.gridMode, .large)
        let returnPreparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: targetPagePosition
            )
        )
        let returnResult = await prepare(
            fixture.controller,
            using: returnPreparation
        )
        XCTAssertEqual(returnResult, .prepared)
        fixture.controller.setActive(true)

        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(
            fixture.controller.currentPagePosition,
            targetPagePosition
        )
    }

    func testCancelledPreparationPreservesTemporaryModeAndPosition() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(.large, controller: fixture.controller)
        fixture.controller.setActive(false)
        let originalPosition = fixture.controller.currentPagePosition
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: .initial
            )
        )
        let completion = expectation(description: "Preparation superseded")
        var result: MobilePlayerCollectionBrowserDisplayPreparationResult?

        fixture.controller.prepareForDisplay(
            using: preparation,
            publishWhenStable: false
        ) {
            result = $0
            completion.fulfill()
        }
        XCTAssertEqual(fixture.controller.gridMode, .large)

        fixture.controller.cancelPendingDisplayPreparation()
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(fixture.controller.currentPagePosition, originalPosition)
    }

    func testPreparationPreservesTemporaryModeAndRetainsTargetFocus() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(.fiveColumns, controller: fixture.controller)
        fixture.controller.setActive(false)
        let targetPagePosition = PlayerPagePosition(position: 3)
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: targetPagePosition
            )
        )

        let result = await prepare(
            fixture.controller,
            using: preparation
        )

        XCTAssertEqual(result, .prepared)
        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertEqual(
            fixture.controller.currentPagePosition,
            targetPagePosition
        )
    }
}
