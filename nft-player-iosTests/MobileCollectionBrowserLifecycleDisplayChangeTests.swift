// ∅ 2026 lil org

import CoreImage
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobileCollectionBrowserGridModePresentationTests {

    func testPreViewActivationLoadsGridCoordinator() throws {
        let metadata = try collectionMetadata()
        let uuid = UUID()
        let session = MobilePlaybackController.shared.startSession(
            config: MobilePlayerConfig(
                id: uuid,
                initialItemId: metadata.id,
                initialTokenIndex: 0
            )
        )
        let display = PlaybackDisplay()
        session.attach(display: display)
        let controller = VerticalCollectionBrowserViewController(
            playbackSession: session
        )
        defer {
            controller.setActive(false)
            session.stopAndDisconnect()
        }

        XCTAssertFalse(controller.isViewLoaded)
        controller.setActive(true)

        XCTAssertTrue(controller.isViewLoaded)
        XCTAssertNotNil(controller.currentPagePosition)
    }

    func testControllerDeallocatesWithActiveInteractionFadeDisplayLink()
        async throws {
        let metadata = try collectionMetadata()
        let uuid = UUID()
        let session = MobilePlaybackController.shared.startSession(
            config: MobilePlayerConfig(
                id: uuid,
                initialItemId: metadata.id,
                initialTokenIndex: 0
            )
        )
        let display = PlaybackDisplay()
        session.attach(display: display)
        var candidate: VerticalCollectionBrowserViewController? =
            VerticalCollectionBrowserViewController(playbackSession: session)
        candidate?.loadViewIfNeeded()
        candidate?.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        candidate?.setActive(true)
        candidate?.view.layoutIfNeeded()
        let recognizer = TestPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(x: 195, y: 422)
        recognizer.reportedState = .began
        recognizer.scale = 1
        sendPinch(recognizer, to: try XCTUnwrap(candidate))
        recognizer.reportedState = .changed
        recognizer.scale = 0.8
        sendPinch(recognizer, to: try XCTUnwrap(candidate))
        await waitForNextMainQueueTurn()
        let collectionView = try XCTUnwrap(
            candidate?.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        XCTAssertFalse(collectionView.isScrollEnabled)
        weak var controller: VerticalCollectionBrowserViewController?
        controller = candidate

        candidate = nil
        session.stopAndDisconnect()
        await waitForNextMainQueueTurn()

        XCTAssertNil(controller)
    }

    func testRestartCollectionPreservesTemporaryGridMode() async throws {
        let metadata = try collectionMetadata()
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
        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }.allSatisfy {
            !$0.usesForegroundImageLoading
        })

        fixture.controller.scrollToFirstItemAndPublish()
        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        try await waitUntil("Restart did not resume visible image loads") {
            let visibleCells = collectionView.visibleCells.compactMap {
                $0 as? MobilePlayerCollectionBrowserCell
            }
            return !visibleCells.isEmpty
                && visibleCells.allSatisfy(\.usesForegroundImageLoading)
        }
    }


    func testDisplayScaleChangeRelayoutsSameSizeViewport() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let viewportSize = controller.view.bounds.size

        func itemSpacing(at displayScale: CGFloat) async throws -> CGFloat {
            controller.traitOverrides.displayScale = displayScale
            await waitForNextMainQueueTurn()
            controller.view.layoutIfNeeded()
            let first = try XCTUnwrap(
                collectionView.collectionViewLayout.layoutAttributesForItem(
                    at: IndexPath(item: 0, section: 0)
                )
            )
            let second = try XCTUnwrap(
                collectionView.collectionViewLayout.layoutAttributesForItem(
                    at: IndexPath(item: 1, section: 0)
                )
            )
            return second.frame.minX - first.frame.maxX
        }

        let threeTimesSpacing = try await itemSpacing(at: 3)
        let twoTimesSpacing = try await itemSpacing(at: 2)

        XCTAssertEqual(controller.view.bounds.size, viewportSize)
        XCTAssertEqual(threeTimesSpacing, 5.0 / 3.0, accuracy: 0.000_1)
        XCTAssertEqual(twoTimesSpacing, 1.5, accuracy: 0.000_1)
    }

    func testDisplayScaleChangeRecentersRetainedDeepFocus() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 300)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        controller.traitOverrides.displayScale = 3
        await waitForNextMainQueueTurn()
        controller.view.layoutIfNeeded()
        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        )
        let targetTokenIndex = tokenCount / 2
        let targetPagePosition = PlayerPagePosition(
            position: targetTokenIndex
        )
        let preparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
                containing: targetPagePosition
            )
        )
        let preparationResult = await prepare(
            controller,
            using: preparation,
            forcePosition: true
        )
        XCTAssertEqual(preparationResult, .prepared)

        func targetViewportCenterY() throws -> CGFloat {
            let attributes = try XCTUnwrap(
                collectionView.collectionViewLayout.layoutAttributesForItem(
                    at: IndexPath(item: targetTokenIndex, section: 0)
                )
            )
            return collectionView.convert(
                CGPoint(x: attributes.frame.midX, y: attributes.frame.midY),
                to: controller.view
            ).y
        }

        let centerYAtThreeTimes = try targetViewportCenterY()
        controller.traitOverrides.displayScale = 2
        await waitForNextMainQueueTurn()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.currentPagePosition, targetPagePosition)
        XCTAssertEqual(
            try targetViewportCenterY(),
            centerYAtThreeTimes,
            accuracy: 0.5
        )
    }

    func testDisplayScaleChangeReconfiguresVisibleDecodeVariants() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(
            .fiveColumns,
            controller: fixture.controller
        )
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let initialVariants = Set(collectionView.visibleCells.compactMap {
            ($0 as? MobilePlayerCollectionBrowserCell)?
                .configuredImageDecodeVariantForTesting
        })

        fixture.controller.traitOverrides.displayScale = 4
        await waitForNextMainQueueTurn()
        fixture.controller.view.layoutIfNeeded()
        let resizedVariants = Set(collectionView.visibleCells.compactMap {
            ($0 as? MobilePlayerCollectionBrowserCell)?
                .configuredImageDecodeVariantForTesting
        })

        XCTAssertFalse(initialVariants.isEmpty)
        XCTAssertEqual(resizedVariants.count, 1)
        XCTAssertNotEqual(initialVariants, resizedVariants)
    }

#if DEBUG
    func testSceneActivationRestoresDecodedWindowAfterScrolling() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(
            .fiveColumns,
            controller: fixture.controller
        )
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let scene = try XCTUnwrap(fixture.window.windowScene)

        fixture.controller.scrollViewWillBeginDragging(collectionView)
        let scrollingMetrics = fixture.controller.thumbnailWindowMetrics
        XCTAssertGreaterThan(scrollingMetrics.fileOnlyPreparations, 0)

        NotificationCenter.default.post(
            name: UIScene.didEnterBackgroundNotification,
            object: scene
        )
        NotificationCenter.default.post(
            name: UIScene.didActivateNotification,
            object: scene
        )
        let activatedMetrics = fixture.controller.thumbnailWindowMetrics

        XCTAssertEqual(
            activatedMetrics.preparations,
            scrollingMetrics.preparations + 1
        )
        XCTAssertEqual(
            activatedMetrics.fileOnlyPreparations,
            scrollingMetrics.fileOnlyPreparations
        )
    }

    func testViewReappearanceRestoresDecodedWindowAfterScrolling() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(
            .fiveColumns,
            controller: fixture.controller
        )
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )

        fixture.controller.scrollViewWillBeginDragging(collectionView)
        let scrollingMetrics = fixture.controller.thumbnailWindowMetrics
        XCTAssertGreaterThan(scrollingMetrics.fileOnlyPreparations, 0)

        fixture.controller.viewWillDisappear(false)
        fixture.controller.viewDidAppear(false)
        let reappearedMetrics = fixture.controller.thumbnailWindowMetrics

        XCTAssertEqual(
            reappearedMetrics.preparations,
            scrollingMetrics.preparations + 1
        )
        XCTAssertEqual(
            reappearedMetrics.fileOnlyPreparations,
            scrollingMetrics.fileOnlyPreparations
        )
    }
#endif


    func testHiddenControllerDoesNotResumeVisibleImageLoads() async throws {
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
        fixture.controller.scrollViewWillBeginDragging(collectionView)

        fixture.controller.viewWillDisappear(false)
        fixture.controller.scrollViewDidEndScrollingAnimation(collectionView)

        let visibleCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(visibleCells.isEmpty)
        XCTAssertTrue(visibleCells.allSatisfy {
            !$0.usesForegroundImageLoading
        })
    }

    func testDetachedControllerDoesNotResumeVisibleImageLoads() async throws {
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
        fixture.controller.scrollViewWillBeginDragging(collectionView)
        fixture.window.rootViewController = nil

        fixture.controller.viewDidAppear(false)
        fixture.controller.scrollViewDidEndScrollingAnimation(collectionView)

        let visibleCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(visibleCells.isEmpty)
        XCTAssertTrue(visibleCells.allSatisfy {
            !$0.usesForegroundImageLoading
        })
    }

    func testLateAnimatedScrollEndDoesNotEndInterruptingDrag() async throws {
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
        let attempt = try XCTUnwrap(
            collectionView.onWillAccessibilityScroll?()
        )
        collectionView.onAccessibilityScrollResult?(true, attempt)
        fixture.controller.scrollViewWillBeginDragging(collectionView)

        fixture.controller.scrollViewDidEndScrollingAnimation(collectionView)

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
        XCTAssertTrue(collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }.allSatisfy(\.usesForegroundImageLoading))
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
            fixture.session.prepareCollectionBrowse(
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
            fixture.session.prepareCollectionBrowse(
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
            fixture.session.prepareCollectionBrowse(
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

    func testCancelledPreparationPreservesFocusAcrossDisplayScaleChange() async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 300)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        controller.traitOverrides.displayScale = 3
        await waitForNextMainQueueTurn()
        controller.view.layoutIfNeeded()
        try await selectGridMode(.large, controller: controller)

        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        )
        let originalTokenIndex = tokenCount / 2
        let originalPosition = PlayerPagePosition(position: originalTokenIndex)
        let originalPreparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
                containing: originalPosition
            )
        )
        let originalPreparationResult = await prepare(
            controller,
            using: originalPreparation,
            forcePosition: true
        )
        XCTAssertEqual(originalPreparationResult, .prepared)

        func viewportCenterY(of tokenIndex: Int) throws -> CGFloat {
            let attributes = try XCTUnwrap(
                collectionView.collectionViewLayout.layoutAttributesForItem(
                    at: IndexPath(item: tokenIndex, section: 0)
                )
            )
            return collectionView.convert(
                CGPoint(x: attributes.frame.midX, y: attributes.frame.midY),
                to: controller.view
            ).y
        }

        let originalBounds = controller.view.bounds
        let originalCenterY = try viewportCenterY(of: originalTokenIndex)
        controller.setActive(false)
        let replacementPreparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
                containing: .initial
            )
        )
        let replacementPreparationResult = await prepare(
            controller,
            using: replacementPreparation
        )
        XCTAssertEqual(replacementPreparationResult, .prepared)

        controller.traitOverrides.displayScale = 1
        await waitForNextMainQueueTurn()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.view.bounds, originalBounds)

        controller.cancelPendingDisplayPreparation()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.currentPagePosition, originalPosition)
        XCTAssertEqual(controller.gridMode, .large)
        XCTAssertEqual(
            try viewportCenterY(of: originalTokenIndex),
            originalCenterY,
            accuracy: 0.5
        )
    }

    func testPreparationPreservesTemporaryModeAndRetainsTargetFocus() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        try await selectGridMode(.fiveColumns, controller: fixture.controller)
        fixture.controller.setActive(false)
        let targetPagePosition = PlayerPagePosition(position: 3)
        let preparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
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
