// ∅ 2026 lil org

import CoreImage
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobileCollectionBrowserGridModePresentationTests {

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
        let visibleCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(visibleCells.isEmpty)
        XCTAssertTrue(visibleCells.allSatisfy(\.usesForegroundImageLoading))
    }

    func testFailedAccessibilityAttemptKeepsActiveScrollImageDeferral()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )

        try await selectGridMode(
            .fiveColumns,
            controller: fixture.controller
        )
        let activeAttempt = try XCTUnwrap(
            collectionView.onWillAccessibilityScroll?()
        )
        collectionView.onAccessibilityScrollResult?(true, activeAttempt)
#if DEBUG
        XCTAssertTrue(
            fixture.controller
                .isScrollMotionAnimationTimeoutScheduled
        )
#endif
        let failedAttempt = try XCTUnwrap(
            collectionView.onWillAccessibilityScroll?()
        )
        collectionView.onAccessibilityScrollResult?(false, failedAttempt)

        let deferredCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(deferredCells.isEmpty)
        XCTAssertTrue(deferredCells.allSatisfy {
            !$0.usesForegroundImageLoading
        })

#if DEBUG
        XCTAssertTrue(
            fixture.controller
                .isScrollMotionAnimationTimeoutScheduled
        )
        fixture.controller.expireScrollMotionAnimationForTesting()
        XCTAssertFalse(
            fixture.controller
                .isScrollMotionAnimationTimeoutScheduled
        )
#else
        fixture.controller.scrollViewDidEndScrollingAnimation(collectionView)
#endif
        let resumedCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(resumedCells.isEmpty)
        XCTAssertTrue(resumedCells.allSatisfy(\.usesForegroundImageLoading))
#if DEBUG
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
        XCTAssertFalse(fixture.controller.isDenseGridImageDisplayLinkActive)
#endif
    }

#if DEBUG
    func testFailedAccessibilityAttemptReschedulesGeometryPrewarming() throws {
        let fixture = try makeFixture(
            collectionId: collectionId(internalSlug: "in_your_dreams")
        )
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        fixture.controller.resetGridModeGeometryPrewarmingForTesting()
        XCTAssertFalse(
            fixture.controller.hasPendingGridModeGeometryPrewarmForTesting
        )
        let attempt = try XCTUnwrap(
            collectionView.onWillAccessibilityScroll?()
        )
        XCTAssertFalse(attempt.interruptedGridModeSettle)

        collectionView.onAccessibilityScrollResult?(false, attempt)

        XCTAssertTrue(
            fixture.controller.hasPendingGridModeGeometryPrewarmForTesting
        )
    }
#endif


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
}
