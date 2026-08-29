// ∅ 2026 lil org

import CoreImage
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobileCollectionBrowserGridModePresentationTests {

    func testGridModeMenuListsNineThroughLargeWithThreeSelected() throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let actions = fixture.controller.makeGridModeMenu().children.compactMap {
            $0 as? UIAction
        }

        XCTAssertEqual(
            actions.map(\.title),
            [
                Strings.nineColumns,
                Strings.fiveColumns,
                Strings.threeColumns,
                Strings.largeGrid,
            ]
        )
        XCTAssertEqual(actions.map(\.state), [.off, .off, .on, .off])
    }


    func testDirectNineAndLargeModeTransitionsRetainFocus() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let initialPosition = try XCTUnwrap(
            fixture.controller.currentPagePosition
        )

        selectGridMode(.large, fixture: fixture)
        XCTAssertEqual(fixture.controller.currentPagePosition, initialPosition)

        selectGridMode(.nineColumns, fixture: fixture)
        XCTAssertEqual(fixture.controller.currentPagePosition, initialPosition)

        selectGridMode(.large, fixture: fixture)
        XCTAssertEqual(fixture.controller.currentPagePosition, initialPosition)
    }

#if DEBUG

    func testForcedPreparationEndsScrollMotion() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        selectGridMode(.fiveColumns, fixture: fixture)
        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(fixture.controller.isScrollMotionActiveForTesting)
        let preparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
                containing: PlayerPagePosition(position: 25)
            )
        )

        let result = await prepare(
            fixture.controller,
            using: preparation,
            forcePosition: true
        )

        XCTAssertEqual(result, .prepared)
        XCTAssertFalse(fixture.controller.isScrollMotionActiveForTesting)
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
    }

    func testPreparedTransitionSelectionEndsScrollMotion() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        selectGridMode(.fiveColumns, fixture: fixture)
        let pagePosition = try XCTUnwrap(fixture.controller.currentPagePosition)
        let preparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
                containing: pagePosition
            )
        )
        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(fixture.controller.isScrollMotionActiveForTesting)

        let selection = fixture.controller.preparedTransitionSelection(
            using: preparation
        )

        XCTAssertNotNil(selection)
        XCTAssertFalse(fixture.controller.isScrollMotionActiveForTesting)
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
    }

    func testOrdinarySelectionEndsScrollMotion() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        selectGridMode(.fiveColumns, fixture: fixture)
        let indexPath = try XCTUnwrap(
            collectionView.indexPathsForVisibleItems.sorted().first {
                guard let cell = collectionView.cellForItem(at: $0)
                    as? MobilePlayerCollectionBrowserCell else {
                    return false
                }
                return cell.canSelect(representing: .init(
                    collectionId: metadata.id,
                    tokenIndex: $0.item
                ))
            }
        )
        var selectionCount = 0
        fixture.controller.onSelection = { _ in
            selectionCount += 1
            return true
        }
        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(fixture.controller.isScrollMotionActiveForTesting)

        fixture.controller.collectionView(
            collectionView,
            didSelectItemAt: indexPath
        )

        XCTAssertEqual(selectionCount, 1)
        XCTAssertFalse(fixture.controller.isScrollMotionActiveForTesting)
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
    }

    func testRejectedSelectionRestoresForegroundImageLoading() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        selectGridMode(.fiveColumns, fixture: fixture)
        let indexPath = try XCTUnwrap(
            collectionView.indexPathsForVisibleItems.sorted().first {
                guard let cell = collectionView.cellForItem(at: $0)
                    as? MobilePlayerCollectionBrowserCell else {
                    return false
                }
                return cell.canSelect(representing: .init(
                    collectionId: metadata.id,
                    tokenIndex: $0.item
                ))
            }
        )
        fixture.controller.onSelection = { _ in false }
        fixture.controller.scrollViewWillBeginDragging(collectionView)

        fixture.controller.collectionView(
            collectionView,
            didSelectItemAt: indexPath
        )

        XCTAssertFalse(fixture.controller.isScrollMotionActiveForTesting)
        let visibleCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(visibleCells.isEmpty)
        XCTAssertTrue(visibleCells.allSatisfy(\.usesForegroundImageLoading))
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
    }

    func testLateScrollToTopCallbackDoesNotEndInterruptingDrag()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        selectGridMode(.fiveColumns, fixture: fixture)
        collectionView.contentOffset.y = min(
            1_000,
            max(
                -collectionView.adjustedContentInset.top,
                collectionView.contentSize.height - collectionView.bounds.height
            )
        )
        XCTAssertTrue(
            fixture.controller.scrollViewShouldScrollToTop(collectionView)
        )
        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(fixture.controller.isScrollMotionActiveForTesting)

        fixture.controller.scrollViewDidScrollToTop(collectionView)

        XCTAssertTrue(fixture.controller.isScrollMotionActiveForTesting)
        let deferredCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(deferredCells.isEmpty)
        XCTAssertTrue(deferredCells.allSatisfy {
            !$0.usesForegroundImageLoading
        })
        fixture.controller.scrollViewDidEndDragging(
            collectionView,
            willDecelerate: false
        )
        XCTAssertFalse(fixture.controller.isScrollMotionActiveForTesting)
    }
#endif


    func testCommitSnapshotBlocksSelectionUntilItDissolves() async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeDeterministicFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: {
                UIView(frame: $0.bounds)
            }
        )
        defer { tearDownFixture(fixture) }
        let frameDriver = try XCTUnwrap(
            fixture.gridTransitionFrameDriver
        )
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )

        selectGridMode(.fiveColumns, fixture: fixture)

        let indexPath = try XCTUnwrap(
            collectionView.indexPathsForVisibleItems.sorted().first {
                guard let cell = collectionView.cellForItem(at: $0)
                    as? MobilePlayerCollectionBrowserCell else {
                    return false
                }
                return cell.canSelect(representing: .init(
                    collectionId: metadata.id,
                    tokenIndex: $0.item
                ))
            }
        )
        let cell = try XCTUnwrap(collectionView.cellForItem(at: indexPath))

        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertFalse(fixture.controller.canSelectItem(
            at: cell.center,
            in: collectionView
        ))
        XCTAssertFalse(fixture.controller.collectionView(
            collectionView,
            shouldSelectItemAt: indexPath
        ))

        let coverRemovalDeadline = frameDriver.now
            + MobilePlayerCollectionBrowserTransitionPresentation
                .contentFadeDuration
            + 0.05
        frameDriver.advance(to: coverRemovalDeadline.nextDown)

        XCTAssertFalse(fixture.controller.collectionView(
            collectionView,
            shouldSelectItemAt: indexPath
        ))

        frameDriver.advance(to: coverRemovalDeadline)

        XCTAssertTrue(fixture.controller.canSelectItem(
            at: cell.center,
            in: collectionView
        ))
        XCTAssertTrue(fixture.controller.collectionView(
            collectionView,
            shouldSelectItemAt: indexPath
        ))
    }

    func testNilPlaneChangeSnapshotUsesBitmapCoverWithoutCancelingPinch()
        async throws {
        let metadata = try collectionMetadata()
        var snapshotRequestCount = 0
        let fixture = try makeDeterministicFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: { _ in
                snapshotRequestCount += 1
                return nil
            }
        )
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let frameDriver = try XCTUnwrap(
            fixture.gridTransitionFrameDriver
        )
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let recognizer = TestPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY
        )
        recognizer.reportedState = .began
        recognizer.scale = 1
        sendPinch(recognizer, to: controller)
        recognizer.reportedState = .changed
        recognizer.scale = 1.5
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertFalse(collectionView.isScrollEnabled)

        recognizer.scale = 0.9
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertGreaterThan(snapshotRequestCount, 0)
        let fallbackCover = try XCTUnwrap(
            controller.view.subviews.first { $0 is UIImageView }
                as? UIImageView
        )
        let fallbackImage = try XCTUnwrap(fallbackCover.image)
        XCTAssertEqual(fallbackImage.scale, 1)
        XCTAssertEqual(fallbackCover.frame, controller.view.bounds)
        XCTAssertFalse(fallbackCover.isUserInteractionEnabled)
        XCTAssertTrue(fallbackCover.superview === controller.view)
        XCTAssertFalse(collectionView.isScrollEnabled)
    }

    func testBitmapFallbackCapturesAnimatedPresentationPixels() async throws {
        let metadata = try collectionMetadata()
        var snapshotRequestCount = 0
        let fixture = try makeDeterministicFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: { _ in
                snapshotRequestCount += 1
                return nil
            }
        )
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let frameDriver = try XCTUnwrap(
            fixture.gridTransitionFrameDriver
        )
        let foregroundScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .sorted {
                    $0.session.persistentIdentifier
                        < $1.session.persistentIdentifier
                }
                .first
        )
        let previousKeyWindow = try XCTUnwrap(
            foregroundScene.windows.first { $0.isKeyWindow }
        )
        fixture.window.windowScene = foregroundScene
        fixture.window.makeKeyAndVisible()
        let overlay = UIView(frame: controller.view.bounds)
        overlay.backgroundColor = .magenta
        controller.view.addSubview(overlay)
        defer {
            overlay.layer.removeAllAnimations()
            overlay.removeFromSuperview()
            previousKeyWindow.makeKey()
        }
        controller.view.layoutIfNeeded()
        await waitForNextMainQueueTurn()
        UIView.animate(
            withDuration: 100,
            delay: 0,
            options: .curveLinear
        ) {
            overlay.alpha = 0
        }
        CATransaction.flush()
        try await waitUntil("Overlay presentation did not become visible") {
            overlay.layer.presentation()?.opacity ?? 0 > 0.9
        }
        XCTAssertEqual(overlay.layer.opacity, 0)

        let recognizer = TestPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY
        )
        recognizer.reportedState = .began
        recognizer.scale = 1
        sendPinch(recognizer, to: controller)
        recognizer.reportedState = .changed
        recognizer.scale = 1.5
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        recognizer.scale = 0.9
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertGreaterThan(snapshotRequestCount, 0)
        let fallbackCover = try XCTUnwrap(
            controller.view.subviews.first { $0 is UIImageView }
                as? UIImageView
        )
        let fallbackImage = try XCTUnwrap(fallbackCover.image)
        XCTAssertEqual(fallbackImage.scale, 1)
        let pixel = try centerPixelRGBA(
            in: fallbackImage
        )
        XCTAssertGreaterThan(pixel.red, 200)
        XCTAssertLessThan(pixel.green, 60)
        XCTAssertGreaterThan(pixel.blue, 200)
        XCTAssertGreaterThan(pixel.alpha, 200)
    }

    func testNilRapidReplacementRetiresPreviousCoverAndKeepsFallback()
        async throws {
        let metadata = try collectionMetadata()
        var snapshots = [UIView]()
        var snapshotRequestCount = 0
        let fixture = try makeDeterministicFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: { view in
                snapshotRequestCount += 1
                guard snapshotRequestCount == 1 else { return nil }
                let snapshot = UIView(frame: view.bounds)
                snapshots.append(snapshot)
                return snapshot
            }
        )
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let frameDriver = try XCTUnwrap(
            fixture.gridTransitionFrameDriver
        )
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let recognizer = TestPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY
        )
        recognizer.reportedState = .began
        recognizer.scale = 1
        sendPinch(recognizer, to: controller)
        recognizer.reportedState = .changed
        recognizer.scale = 1.5
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertEqual(snapshotRequestCount, 0)

        recognizer.scale = 0.9
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        let firstSnapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshotRequestCount, 1)
        XCTAssertTrue(firstSnapshot.superview === controller.view)
        let firstCoverRemovalDeadline = frameDriver.now
            + MobilePlayerCollectionBrowserTransitionPresentation
                .contentFadeDuration
            + 0.05

        recognizer.scale = 0.5
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertEqual(snapshotRequestCount, 1)
        XCTAssertTrue(firstSnapshot.superview === controller.view)

        recognizer.scale = 1.5
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertEqual(snapshotRequestCount, 2)
        XCTAssertNil(firstSnapshot.superview)
        let fallbackCover = try XCTUnwrap(
            controller.view.subviews.first { $0 is UIImageView }
                as? UIImageView
        )
        let replacementCoverRemovalDeadline = frameDriver.now
            + MobilePlayerCollectionBrowserTransitionPresentation
                .contentFadeDuration
            + 0.05
        XCTAssertEqual(try XCTUnwrap(fallbackCover.image).scale, 1)
        XCTAssertTrue(fallbackCover.superview === controller.view)
        XCTAssertFalse(collectionView.isScrollEnabled)

        frameDriver.advance(to: firstCoverRemovalDeadline)

        XCTAssertTrue(fallbackCover.superview === controller.view)

        frameDriver.advance(to: replacementCoverRemovalDeadline.nextDown)

        XCTAssertTrue(fallbackCover.superview === controller.view)

        frameDriver.advance(to: replacementCoverRemovalDeadline)

        XCTAssertNil(fallbackCover.superview)
        XCTAssertFalse(collectionView.isScrollEnabled)
    }

#if DEBUG
    func testZeroAlphaPlaneReversalSkipsSnapshotAndKeepsPinchActive() throws {
        let metadata = try collectionMetadata()
        var snapshotRequestCount = 0
        let fixture = try makeDeterministicFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: { view in
                snapshotRequestCount += 1
                return UIView(frame: view.bounds)
            }
        )
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let frameDriver = try XCTUnwrap(
            fixture.gridTransitionFrameDriver
        )
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let recognizer = TestPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY
        )
        recognizer.reportedState = .began
        recognizer.scale = 1
        sendPinch(recognizer, to: controller)

        recognizer.reportedState = .changed
        recognizer.scale = 1.05
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        recognizer.scale = 1.03
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertFalse(collectionView.isScrollEnabled)

        recognizer.scale = 1.05
        sendPinch(recognizer, to: controller)
        frameDriver.advance()

        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertFalse(collectionView.isScrollEnabled)
    }
#endif

    func testPinchEndAppliesTerminalScaleWithoutTerminalCentroid() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let recognizer = TestPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY
        )
        recognizer.reportedState = .began
        recognizer.scale = 1
        sendPinch(recognizer, to: controller)

        recognizer.reportedState = .ended
        recognizer.scale = 0.5
        recognizer.reportedLocation.y -= 200
        sendPinch(recognizer, to: controller)

        advanceGridTransitionFrames(
            "Terminal pinch scale did not settle to nine columns",
            fixture: fixture
        ) {
            controller.gridMode == .nineColumns
        }

        XCTAssertEqual(controller.gridMode, .nineColumns)
    }


    func testSettleReservesCollectionPanForOneFingerAndRestoresIt() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
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
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
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
        let reentryState = ReentryState()
        let observation = collectionView.observe(
            \.isScrollEnabled,
            options: [.new]
        ) { _, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated {
                guard let currentCollectionView = fixture.controller.view
                    .subviews.first(where: {
                        $0 is MobilePlayerCollectionBrowserCollectionView
                    }) as? MobilePlayerCollectionBrowserCollectionView else {
                    return
                }
                reentryState.didReenter = true
                fixture.controller.scrollViewDidEndDecelerating(
                    currentCollectionView
                )
            }
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        withExtendedLifetime(observation) {}
        XCTAssertTrue(reentryState.didReenter)
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
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
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
        let reentryState = ReentryState()
        let observation = collectionView.observe(
            \.isScrollEnabled,
            options: [.new]
        ) { _, change in
            guard change.newValue == true else { return }
            MainActor.assumeIsolated {
                guard !reentryState.didReenter else { return }
                guard let currentCollectionView = fixture.controller.view
                    .subviews.first(where: {
                        $0 is MobilePlayerCollectionBrowserCollectionView
                    }) as? MobilePlayerCollectionBrowserCollectionView else {
                    return
                }
                reentryState.didReenter = true
                fixture.controller.scrollViewWillBeginDragging(
                    currentCollectionView
                )
            }
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        withExtendedLifetime(observation) {}

        XCTAssertTrue(reentryState.didReenter)
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
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        )
        let preparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
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
        let reentryState = ReentryState()
        let observation = collectionView.observe(
            \.contentOffset,
            options: [.new]
        ) { _, _ in
            MainActor.assumeIsolated {
                guard fixture.controller.gridMode == .fiveColumns,
                      !reentryState.didReenter else {
                    return
                }
                guard let currentCollectionView = fixture.controller.view
                    .subviews.first(where: {
                        $0 is MobilePlayerCollectionBrowserCollectionView
                    }) as? MobilePlayerCollectionBrowserCollectionView else {
                    return
                }
                reentryState.didReenter = true
                fixture.controller.scrollViewWillBeginDragging(
                    currentCollectionView
                )
            }
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        advanceGridTransitionFrames(
            "Renderer handoff did not reach five columns",
            fixture: fixture
        ) {
            fixture.controller.gridMode == .fiveColumns
        }
        withExtendedLifetime(observation) {}

        XCTAssertTrue(reentryState.didReenter)
        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertTrue(settledPagePositions.isEmpty)
        let visibleCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(visibleCells.isEmpty)
        XCTAssertTrue(visibleCells.allSatisfy {
            !$0.usesForegroundImageLoading
        })
    }
}
