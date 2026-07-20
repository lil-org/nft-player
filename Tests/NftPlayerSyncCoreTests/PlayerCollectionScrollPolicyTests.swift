// ∅ 2026 lil org

import Foundation
import XCTest
@testable import NftPlayerSyncCore

final class PlayerCollectionScrollPolicyTests: XCTestCase {

    func testBoundedContentOffsetDeltaIgnoresTopAndBottomBounceRecovery() {
        let validRange: ClosedRange<CGFloat> = 0...100

        XCTAssertEqual(PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
            previousOffsetY: -30,
            currentOffsetY: -12,
            validRange: validRange
        ), 0)
        XCTAssertEqual(PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
            previousOffsetY: -12,
            currentOffsetY: 0,
            validRange: validRange
        ), 0)
        XCTAssertEqual(PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
            previousOffsetY: 130,
            currentOffsetY: 112,
            validRange: validRange
        ), 0)
        XCTAssertEqual(PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
            previousOffsetY: 112,
            currentOffsetY: 100,
            validRange: validRange
        ), 0)
    }

    func testBoundedContentOffsetDeltaKeepsOnlyRealScrollableMovement() {
        let validRange: ClosedRange<CGFloat> = 0...100

        XCTAssertEqual(PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
            previousOffsetY: -20,
            currentOffsetY: 12,
            validRange: validRange
        ), 12)
        XCTAssertEqual(PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
            previousOffsetY: 80,
            currentOffsetY: 120,
            validRange: validRange
        ), 20)
        XCTAssertEqual(PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
            previousOffsetY: 70,
            currentOffsetY: 45,
            validRange: validRange
        ), -25)
    }

    func testFocalGeometryMovesContinuouslyFromEdgeItemsToViewportCenter() throws {
        let geometry = try makeTallFocalGeometry()

        XCTAssertEqual(geometry.focalPoint(at: 0), CGPoint(x: 65, y: 79))
        XCTAssertEqual(geometry.focalPoint(at: 0.75).y, 80.5, accuracy: 0.001)
        XCTAssertEqual(geometry.focalPoint(at: 0.76).y, 80.52, accuracy: 0.001)
        XCTAssertEqual(geometry.focalPoint(at: 343), CGPoint(x: 195, y: 765))
        XCTAssertEqual(geometry.focalPoint(at: 1_000), CGPoint(x: 195, y: 1_422))
        XCTAssertEqual(geometry.focalPoint(at: 3_604), CGPoint(x: 325, y: 4_369))

        let focalYs: [CGFloat] = [79, 209, 339, 765, 1_422, 4_239, 4_369]
        for focalY in focalYs {
            let offsetY = geometry.contentOffsetY(anchoringFocalY: focalY)
            XCTAssertEqual(geometry.focalPoint(at: offsetY).y, focalY, accuracy: 0.001)
        }
        XCTAssertEqual(geometry.contentOffsetY(anchoringFocalY: 209), 65)
        XCTAssertEqual(geometry.contentOffsetY(anchoringFocalY: 4_239), 3_539)
    }

    func testFocalGeometryKeepsTinyEdgeMovementInTheEdgeRow() throws {
        let geometry = try makeTallFocalGeometry()
        let topItems = makeGridItems(indices: 0..<12)

        XCTAssertEqual(
            PlayerCollectionScrollPolicy.anchorIndex(
                visibleItems: topItems,
                focalPoint: geometry.focalPoint(at: 0.76),
                itemCount: 102
            ),
            0
        )

        let bottomItems = makeGridItems(indices: 90..<102)
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.anchorIndex(
                visibleItems: bottomItems,
                focalPoint: geometry.focalPoint(at: 3_603.24),
                itemCount: 102
            ),
            101
        )
    }

    func testBottomFocalAlignmentDoesNotRegressAcrossPartialLastRow() throws {
        let geometry = try makeTallFocalGeometry(
            lastItemCenter: CGPoint(x: 65, y: 4_369)
        )
        let items = makeGridItems(indices: 0..<100)

        var previousIndex = 0
        let sampledOffsets: [CGFloat] = [
            3_261, 3_350, 3_421, 3_436, 3_500, 3_570, 3_572, 3_604,
        ]
        for offsetY in sampledOffsets {
            let index = try XCTUnwrap(PlayerCollectionScrollPolicy.anchorIndex(
                visibleItems: items,
                focalPoint: geometry.focalPoint(at: offsetY),
                itemCount: items.count
            ))
            XCTAssertGreaterThanOrEqual(index, previousIndex)
            previousIndex = index
        }
        XCTAssertEqual(previousIndex, 99)

        let penultimateRowOffsetY = geometry.contentOffsetY(anchoringFocalY: 4_239)
        let penultimateRowCandidate = PlayerCollectionScrollPolicy.anchorIndex(
            visibleItems: items,
            focalPoint: geometry.focalPoint(at: penultimateRowOffsetY),
            itemCount: items.count
        )
        XCTAssertLessThan(penultimateRowOffsetY, geometry.maximumOffsetY)
        XCTAssertEqual(PlayerCollectionScrollPolicy.resolvedAnchorIndex(
            retainedIndex: 98,
            candidateIndex: penultimateRowCandidate,
            itemCount: items.count,
            configuredColumnCount: 3
        ), 98)
        let finalCandidate = PlayerCollectionScrollPolicy.anchorIndex(
            visibleItems: items,
            focalPoint: geometry.focalPoint(at: geometry.maximumOffsetY),
            itemCount: items.count
        )
        XCTAssertEqual(PlayerCollectionScrollPolicy.resolvedAnchorIndex(
            retainedIndex: 98,
            candidateIndex: finalCandidate,
            itemCount: items.count,
            configuredColumnCount: 3
        ), 99)
    }

    func testRetainedFocalBiasPreservesVisibleTargetAtClampedBoundary() throws {
        let geometry = try makeTallFocalGeometry()
        let bias = try XCTUnwrap(PlayerCollectionScrollFocalBias(
            referenceFocalY: geometry.focalPoint(at: 0).y,
            deltaY: 260,
            decayDistance: 260
        ))

        let standardTinyMovementFocalPoint = geometry.focalPoint(at: 0.76)
        let tinyMovementFocalPoint = bias.adjustedFocalPoint(
            from: standardTinyMovementFocalPoint,
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        )
        XCTAssertEqual(tinyMovementFocalPoint.y, 339, accuracy: 0.001)
        XCTAssertEqual(tinyMovementFocalPoint.x, standardTinyMovementFocalPoint.x)

        let bouncedFocalPoint = bias.adjustedFocalPoint(
            from: geometry.focalPoint(at: -40),
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        )
        XCTAssertEqual(bouncedFocalPoint, CGPoint(x: 65, y: 339))
        XCTAssertFalse(bias.isExpired(
            at: geometry.focalPoint(at: 129).y,
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        ))
        XCTAssertTrue(bias.isExpired(
            at: geometry.focalPoint(at: 130).y,
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        ))
    }

    func testRetainedFocalBiasDoesNotSweepAcrossColumns() throws {
        let geometry = try makeTallFocalGeometry()
        let bias = try XCTUnwrap(PlayerCollectionScrollFocalBias(
            referenceFocalY: geometry.focalPoint(at: 0).y,
            deltaY: 260,
            decayDistance: 260
        ))
        let items = makeGridItems(indices: 0..<24)

        var retainedIndex: Int? = 8
        var previousIndex = 8
        let sampledOffsets: [CGFloat] = [
            0, 32, 64, 66, 100, 130, 195, 260, 300, 343, 400,
        ]
        for offsetY in sampledOffsets {
            let focalPoint = bias.adjustedFocalPoint(
                from: geometry.focalPoint(at: offsetY),
                minimumFocalY: geometry.firstItemCenter.y,
                maximumFocalY: geometry.lastItemCenter.y
            )
            let candidateIndex = PlayerCollectionScrollPolicy.anchorIndex(
                visibleItems: items,
                focalPoint: focalPoint,
                itemCount: items.count
            )
            let resolvedIndex = try XCTUnwrap(PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: retainedIndex,
                candidateIndex: candidateIndex,
                itemCount: items.count,
                configuredColumnCount: 3
            ))
            if resolvedIndex != retainedIndex {
                retainedIndex = nil
            }
            XCTAssertGreaterThanOrEqual(resolvedIndex, previousIndex)
            previousIndex = resolvedIndex
        }
    }

    func testRetainedFocalBiasPreservesTargetWhenContentDoesNotScroll() throws {
        let geometry = try XCTUnwrap(PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: 0,
            maximumOffsetY: 0,
            viewportHeight: 844,
            viewportCenterX: 195,
            firstItemCenter: CGPoint(x: 65, y: 79),
            lastItemCenter: CGPoint(x: 325, y: 339),
            lastRowFocalEntryY: 274
        ))
        let bias = try XCTUnwrap(PlayerCollectionScrollFocalBias(
            referenceFocalY: geometry.focalPoint(at: 0).y,
            deltaY: 260,
            decayDistance: 260
        ))
        let targetFocalPoint = bias.adjustedFocalPoint(
            from: geometry.focalPoint(at: -40),
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        )
        let items = makeGridItems(indices: 0..<9)
        let candidateIndex = PlayerCollectionScrollPolicy.anchorIndex(
            visibleItems: items,
            focalPoint: targetFocalPoint,
            itemCount: items.count
        )

        XCTAssertEqual(targetFocalPoint, CGPoint(x: 65, y: 339))
        XCTAssertEqual(geometry.contentOffsetY(anchoringFocalY: 339), 0)
        XCTAssertEqual(PlayerCollectionScrollPolicy.resolvedAnchorIndex(
            retainedIndex: 8,
            candidateIndex: candidateIndex,
            itemCount: items.count,
            configuredColumnCount: 3
        ), 8)
        XCTAssertFalse(bias.isExpired(
            at: geometry.focalPoint(at: 40).y,
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        ))
    }

    func testRetainedFocalBiasExpiresBeforeEitherShortContentBoundary() throws {
        let geometry = try makeShortFocalGeometry()
        let referenceFocalPoint = geometry.focalPoint(at: 50)
        let upperTargetBias = try XCTUnwrap(PlayerCollectionScrollFocalBias(
            referenceFocalY: referenceFocalPoint.y,
            deltaY: -100,
            decayDistance: 100
        ))
        let lowerTargetBias = try XCTUnwrap(PlayerCollectionScrollFocalBias(
            referenceFocalY: referenceFocalPoint.y,
            deltaY: 100,
            decayDistance: 100
        ))

        XCTAssertEqual(upperTargetBias.adjustedFocalPoint(
            from: geometry.focalPoint(at: 100),
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        ), geometry.lastItemCenter)
        XCTAssertEqual(lowerTargetBias.adjustedFocalPoint(
            from: geometry.focalPoint(at: 0),
            minimumFocalY: geometry.firstItemCenter.y,
            maximumFocalY: geometry.lastItemCenter.y
        ), geometry.firstItemCenter)
    }

    func testFocalGeometryHandlesShortAndInvalidContent() throws {
        let shortGeometry = try makeShortFocalGeometry()
        XCTAssertEqual(shortGeometry.focalPoint(at: 50), CGPoint(x: 100, y: 250))
        XCTAssertEqual(shortGeometry.contentOffsetY(anchoringFocalY: 150), 25)
        XCTAssertEqual(
            shortGeometry.focalPoint(
                at: shortGeometry.contentOffsetY(anchoringFocalY: 350)
            ).y,
            350
        )

        XCTAssertNil(PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: 100,
            maximumOffsetY: 0,
            viewportHeight: 400,
            viewportCenterX: 100,
            firstItemCenter: CGPoint(x: 20, y: 50),
            lastItemCenter: CGPoint(x: 180, y: 450),
            lastRowFocalEntryY: 400
        ))
        XCTAssertNil(PlayerCollectionScrollFocalBias(
            referenceFocalY: 0,
            deltaY: 1,
            decayDistance: 0
        ))
    }

    func testResolvedAnchorPreservesExactIndexForSameRowCandidate() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 1,
                candidateIndex: 0,
                itemCount: 12,
                configuredColumnCount: 3
            ),
            1
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 10,
                candidateIndex: 11,
                itemCount: 12,
                configuredColumnCount: 3
            ),
            10
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 2,
                candidateIndex: 0,
                itemCount: 3,
                configuredColumnCount: 3
            ),
            2
        )
    }

    func testResolvedAnchorReleasesRetainedIndexAfterMovingToAnotherRow() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 1,
                candidateIndex: 3,
                itemCount: 12,
                configuredColumnCount: 3
            ),
            3
        )
    }

    func testResolvedAnchorUsesConfiguredTwoColumnRows() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 1,
                candidateIndex: 0,
                itemCount: 8,
                configuredColumnCount: 2
            ),
            1
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 1,
                candidateIndex: 2,
                itemCount: 8,
                configuredColumnCount: 2
            ),
            2
        )
    }

    func testRotationTransitionsRetainFocusAndResolveEffectiveRows() throws {
        let portraitSize = CGSize(width: 430, height: 932)
        let landscapeSize = CGSize(width: 932, height: 430)

        for portraitColumnCount in [2, 3] {
            let aspectProfile = MobilePlayerBrowserAspectProfile(
                itemCount: 37,
                uniformImageSize: CGSize(width: 1, height: 1),
                columnCount: portraitColumnCount
            )
            let retainedIndex = portraitColumnCount + 1
            let candidateIndex = 0
            let portraitTransition = MobilePlayerBrowserLayout.viewportTransition(
                previousViewportSize: .zero,
                viewportSize: portraitSize,
                needsSafeAreaRefresh: true,
                topContentInset: 59,
                bottomContentInset: 34,
                aspectProfile: aspectProfile,
                forcedTokenIndex: nil,
                focusedTokenIndex: retainedIndex
            )
            let landscapeTransition = MobilePlayerBrowserLayout.viewportTransition(
                previousViewportSize: portraitSize,
                viewportSize: landscapeSize,
                needsSafeAreaRefresh: false,
                bottomContentInset: 21,
                aspectProfile: aspectProfile,
                forcedTokenIndex: nil,
                focusedTokenIndex: retainedIndex
            )
            let returnedPortraitTransition = MobilePlayerBrowserLayout.viewportTransition(
                previousViewportSize: landscapeSize,
                viewportSize: portraitSize,
                needsSafeAreaRefresh: false,
                topContentInset: 59,
                bottomContentInset: 34,
                aspectProfile: aspectProfile,
                forcedTokenIndex: retainedIndex,
                focusedTokenIndex: candidateIndex
            )
            let portraitLayout = try XCTUnwrap(portraitTransition.layout)
            let landscapeLayout = try XCTUnwrap(landscapeTransition.layout)
            let returnedPortraitLayout = try XCTUnwrap(
                returnedPortraitTransition.layout
            )

            XCTAssertTrue(portraitTransition.needsInitialLayout)
            XCTAssertTrue(landscapeTransition.geometryChanged)
            XCTAssertTrue(returnedPortraitTransition.geometryChanged)
            XCTAssertEqual(
                landscapeTransition.retainedFocusTokenIndex,
                retainedIndex
            )
            XCTAssertEqual(
                returnedPortraitTransition.retainedFocusTokenIndex,
                retainedIndex
            )
            XCTAssertEqual(
                [
                    portraitLayout.columnCount,
                    landscapeLayout.columnCount,
                    returnedPortraitLayout.columnCount,
                ],
                [portraitColumnCount, portraitColumnCount * 2, portraitColumnCount]
            )

            XCTAssertNotEqual(
                retainedIndex / portraitLayout.columnCount,
                candidateIndex / portraitLayout.columnCount
            )
            XCTAssertEqual(
                retainedIndex / landscapeLayout.columnCount,
                candidateIndex / landscapeLayout.columnCount
            )
            XCTAssertEqual(
                PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                    retainedIndex: retainedIndex,
                    candidateIndex: candidateIndex,
                    itemCount: aspectProfile.itemCount,
                    configuredColumnCount: landscapeLayout.columnCount
                ),
                retainedIndex
            )
            XCTAssertEqual(
                PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                    retainedIndex: retainedIndex,
                    candidateIndex: candidateIndex,
                    itemCount: aspectProfile.itemCount,
                    configuredColumnCount: returnedPortraitLayout.columnCount
                ),
                candidateIndex
            )
        }
    }

    func testResolvedAnchorHandlesUnavailableAndInvalidInputs() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 2,
                candidateIndex: nil,
                itemCount: 12,
                configuredColumnCount: 3
            ),
            2
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 2,
                candidateIndex: 4,
                itemCount: 12,
                configuredColumnCount: 0
            ),
            2
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: -1,
                candidateIndex: 4,
                itemCount: 12,
                configuredColumnCount: 3
            ),
            4
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 2,
                candidateIndex: 12,
                itemCount: 12,
                configuredColumnCount: 3
            ),
            2
        )
        XCTAssertNil(
            PlayerCollectionScrollPolicy.resolvedAnchorIndex(
                retainedIndex: 2,
                candidateIndex: 4,
                itemCount: 0,
                configuredColumnCount: 3
            )
        )
    }

    func testFullVisibilityAcceptsContainedAndEpsilonAlignedFrames() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertTrue(
            PlayerCollectionScrollPolicy.isItemFullyVisible(
                frame: CGRect(x: 10, y: 10, width: 80, height: 80),
                viewport: viewport,
                epsilon: 0.75
            )
        )
        XCTAssertTrue(
            PlayerCollectionScrollPolicy.isItemFullyVisible(
                frame: CGRect(x: -0.5, y: 0, width: 101, height: 100),
                viewport: viewport,
                epsilon: 0.75
            )
        )
    }

    func testFullVisibilityRejectsClippedAndInvalidFrames() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertFalse(
            PlayerCollectionScrollPolicy.isItemFullyVisible(
                frame: CGRect(x: 0, y: 99, width: 20, height: 20),
                viewport: viewport,
                epsilon: 0.75
            )
        )
        XCTAssertFalse(
            PlayerCollectionScrollPolicy.isItemFullyVisible(
                frame: .zero,
                viewport: viewport,
                epsilon: 0.75
            )
        )
        XCTAssertFalse(
            PlayerCollectionScrollPolicy.isItemFullyVisible(
                frame: CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20),
                viewport: viewport,
                epsilon: 0.75
            )
        )
    }

    func testViewedToEndAcceptsFullyVisibleFinalItemBeforeBottom() {
        XCTAssertTrue(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: CGRect(x: 10, y: 110, width: 80, height: 80),
                viewport: CGRect(x: 0, y: 100, width: 100, height: 100),
                maximumContentOffsetY: 200,
                epsilon: 0.75
            )
        )
    }

    func testViewedToEndAcceptsOversizedFinalItemOnlyAtBottom() {
        let finalItemFrame = CGRect(x: 0, y: 50, width: 100, height: 150)

        XCTAssertFalse(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: finalItemFrame,
                viewport: CGRect(x: 0, y: 80, width: 100, height: 100),
                maximumContentOffsetY: 100,
                epsilon: 0.75
            )
        )
        XCTAssertTrue(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: finalItemFrame,
                viewport: CGRect(x: 0, y: 100, width: 100, height: 100),
                maximumContentOffsetY: 100,
                epsilon: 0.75
            )
        )
    }

    func testViewedToEndRejectsOrdinaryClippedItemAtBottom() {
        XCTAssertFalse(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: CGRect(x: 0, y: 80, width: 100, height: 80),
                viewport: CGRect(x: 0, y: 100, width: 100, height: 100),
                maximumContentOffsetY: 100,
                epsilon: 0.75
            )
        )
    }

    func testViewedToEndRejectsOversizedItemWhoseBottomIsNotVisible() {
        XCTAssertFalse(
            PlayerCollectionScrollPolicy.hasViewedToEnd(
                finalItemFrame: CGRect(x: 0, y: 75, width: 100, height: 150),
                viewport: CGRect(x: 0, y: 100, width: 100, height: 100),
                maximumContentOffsetY: 100,
                epsilon: 0.75
            )
        )
    }

    func testRestorationKeepsExactValidSavedIndex() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationIndex(savedIndex: 7, itemCount: 12),
            7
        )
    }

    func testRestorationFallsBackToZeroForMissingOrStaleIndex() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationIndex(savedIndex: nil, itemCount: 12),
            0
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationIndex(savedIndex: -1, itemCount: 12),
            0
        )
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationIndex(savedIndex: 12, itemCount: 12),
            0
        )
    }

    func testRestorationReturnsNilForEmptyCollection() {
        XCTAssertNil(
            PlayerCollectionScrollPolicy.restorationIndex(savedIndex: 0, itemCount: 0)
        )
    }

    func testRestorationResolutionPrefersValidSavedIndexOverTokenId() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationResolution(
                savedIndex: 7,
                tokenIdIndex: 3,
                itemCount: 12,
                hasRequestedPosition: true
            ),
            PlayerCollectionRestorationResolution(
                tokenIndex: 7,
                didResolveRequestedPosition: true
            )
        )
    }

    func testRestorationResolutionFallsBackToTokenIdWhenSavedIndexIsUnavailable() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationResolution(
                savedIndex: 7,
                tokenIdIndex: 3,
                itemCount: 12,
                hasRequestedPosition: true,
                isIndexAvailable: { $0 != 7 }
            ),
            PlayerCollectionRestorationResolution(
                tokenIndex: 3,
                didResolveRequestedPosition: true
            )
        )
    }

    func testRestorationResolutionMarksRequestedFallbackAsUnresolved() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationResolution(
                savedIndex: 20,
                tokenIdIndex: nil,
                itemCount: 12,
                hasRequestedPosition: true
            ),
            PlayerCollectionRestorationResolution(
                tokenIndex: 0,
                didResolveRequestedPosition: false
            )
        )
    }

    func testRestorationResolutionTreatsUnrequestedStartAsResolved() {
        XCTAssertEqual(
            PlayerCollectionScrollPolicy.restorationResolution(
                savedIndex: nil,
                tokenIdIndex: nil,
                itemCount: 12,
                hasRequestedPosition: false
            ),
            PlayerCollectionRestorationResolution(
                tokenIndex: 0,
                didResolveRequestedPosition: true
            )
        )
    }

    func testAnchorPrioritizesNearestRowBeforeColumn() {
        let visibleItems = [
            PlayerCollectionVisibleItem(
                index: 4,
                frame: CGRect(x: 45, y: 0, width: 10, height: 10)
            ),
            PlayerCollectionVisibleItem(
                index: 5,
                frame: CGRect(x: 0, y: 45, width: 10, height: 10)
            ),
            PlayerCollectionVisibleItem(
                index: 6,
                frame: CGRect(x: 41, y: 41, width: 10, height: 10)
            )
        ]

        XCTAssertEqual(
            PlayerCollectionScrollPolicy.anchorIndex(
                visibleItems: visibleItems,
                focalPoint: CGPoint(x: 50, y: 50),
                itemCount: 20
            ),
            5
        )
    }

    func testAnchorTieChoosesLowerIndexIndependentOfInputOrder() {
        let lowerIndex = PlayerCollectionVisibleItem(
            index: 2,
            frame: CGRect(x: 30, y: 45, width: 10, height: 10)
        )
        let higherIndex = PlayerCollectionVisibleItem(
            index: 9,
            frame: CGRect(x: 60, y: 45, width: 10, height: 10)
        )

        for visibleItems in [[lowerIndex, higherIndex], [higherIndex, lowerIndex]] {
            XCTAssertEqual(
                PlayerCollectionScrollPolicy.anchorIndex(
                    visibleItems: visibleItems,
                    focalPoint: CGPoint(x: 50, y: 50),
                    itemCount: 12
                ),
                2
            )
        }
    }

    func testAnchorIgnoresInvalidItemsAndReturnsNilWithoutCandidate() {
        let visibleItems = [
            PlayerCollectionVisibleItem(
                index: -1,
                frame: CGRect(x: 45, y: 45, width: 10, height: 10)
            ),
            PlayerCollectionVisibleItem(
                index: 12,
                frame: CGRect(x: 45, y: 45, width: 10, height: 10)
            )
        ]

        XCTAssertNil(
            PlayerCollectionScrollPolicy.anchorIndex(
                visibleItems: visibleItems,
                focalPoint: CGPoint(x: 50, y: 50),
                itemCount: 12
            )
        )
    }

    func testInitialPositioningSuppressesCandidatesUntilSettledThenPublishesExactRestore() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 7)

        state.observeCandidate(4)
        XCTAssertNil(state.settle())

        state.finishInitialPositioning()
        XCTAssertEqual(state.settle()?.tokenIndex, 7)
    }

    func testSameRowCandidateDoesNotOverwriteExactRestoredProgress() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 10)
        state.finishInitialPositioning()
        XCTAssertEqual(state.settle()?.tokenIndex, 10)

        let resolvedIndex = PlayerCollectionScrollPolicy.resolvedAnchorIndex(
            retainedIndex: 10,
            candidateIndex: 11,
            itemCount: 12,
            configuredColumnCount: 3
        )
        XCTAssertEqual(resolvedIndex, 10)
        state.observeCandidate(resolvedIndex ?? -1)
        XCTAssertNil(state.settle())
    }

    func testProgrammaticPositioningSuppressesCandidatesUntilSettledThenPublishesTarget() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 2)
        state.finishInitialPositioning()
        XCTAssertEqual(state.settle()?.tokenIndex, 2)

        state.beginProgrammaticPositioning(at: 9)
        state.observeCandidate(8)
        XCTAssertNil(state.settle())

        state.finishProgrammaticPositioning()
        XCTAssertEqual(state.settle()?.tokenIndex, 9)
    }

    func testOrdinaryCandidatePublishesOnlyOnSettleAndDeduplicates() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 2)
        state.finishInitialPositioning()
        XCTAssertEqual(state.settle()?.tokenIndex, 2)

        state.observeCandidate(6)
        state.observeCandidate(6)
        XCTAssertEqual(state.settle()?.tokenIndex, 6)
        XCTAssertNil(state.settle())

        state.observeCandidate(6)
        XCTAssertNil(state.settle())
    }

    func testFinalFlushPublishesPendingCandidateAndDeduplicatesLaterSettles() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 2)
        state.finishInitialPositioning()
        XCTAssertEqual(state.settle()?.tokenIndex, 2)

        state.observeCandidate(8)
        XCTAssertEqual(state.finalFlush()?.tokenIndex, 8)
        XCTAssertNil(state.finalFlush())
        XCTAssertNil(state.settle())
    }

    func testFinalFlushUsesExactProgrammaticTargetWhilePositioning() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 2)
        state.finishInitialPositioning()
        XCTAssertEqual(state.settle()?.tokenIndex, 2)

        state.beginProgrammaticPositioning(at: 10)
        state.observeCandidate(7)

        XCTAssertEqual(state.finalFlush()?.tokenIndex, 10)
        state.finishProgrammaticPositioning()
        XCTAssertNil(state.settle())
    }

    func testFailedPublicationCanBeRetriedByFinalFlush() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 4)
        state.finishInitialPositioning()

        let publication = PlayerCollectionScrollPublication(
            tokenIndex: 4,
            hasViewedToEnd: false
        )
        XCTAssertEqual(state.settle(), publication)
        state.retryPublication(of: publication)
        XCTAssertEqual(state.finalFlush(), publication)
        XCTAssertNil(state.finalFlush())
    }

    func testCompletionPublishesWhenItChangesAtTheSameIndex() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 4)
        state.finishInitialPositioning()

        XCTAssertEqual(
            state.settle(hasViewedToEnd: false),
            PlayerCollectionScrollPublication(
                tokenIndex: 4,
                hasViewedToEnd: false
            )
        )
        XCTAssertEqual(
            state.settle(hasViewedToEnd: true),
            PlayerCollectionScrollPublication(
                tokenIndex: 4,
                hasViewedToEnd: true
            )
        )
        XCTAssertNil(state.settle(hasViewedToEnd: true))
    }

    func testFailedCompletionPublicationCanBeRetried() {
        var state = PlayerCollectionScrollPublicationState(initialIndex: 4)
        state.finishInitialPositioning()
        _ = state.settle(hasViewedToEnd: false)
        let completion = PlayerCollectionScrollPublication(
            tokenIndex: 4,
            hasViewedToEnd: true
        )

        XCTAssertEqual(state.settle(hasViewedToEnd: true), completion)
        state.retryPublication(of: completion)
        XCTAssertEqual(state.finalFlush(hasViewedToEnd: false), completion)
        XCTAssertNil(state.finalFlush(hasViewedToEnd: false))
    }

    private func makeTallFocalGeometry(
        lastItemCenter: CGPoint = CGPoint(x: 325, y: 4_369)
    ) throws -> PlayerCollectionScrollFocalGeometry {
        try XCTUnwrap(PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: 0,
            maximumOffsetY: 3_604,
            viewportHeight: 844,
            viewportCenterX: 195,
            firstItemCenter: CGPoint(x: 65, y: 79),
            lastItemCenter: lastItemCenter,
            lastRowFocalEntryY: 4_304
        ))
    }

    private func makeShortFocalGeometry() throws -> PlayerCollectionScrollFocalGeometry {
        try XCTUnwrap(PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: 0,
            maximumOffsetY: 100,
            viewportHeight: 400,
            viewportCenterX: 100,
            firstItemCenter: CGPoint(x: 20, y: 50),
            lastItemCenter: CGPoint(x: 180, y: 450),
            lastRowFocalEntryY: 400
        ))
    }

    private func makeGridItems(
        indices: Range<Int>,
        columnCount: Int = 3
    ) -> [PlayerCollectionVisibleItem] {
        indices.map { index in
            let row = index / columnCount
            let column = index % columnCount
            return PlayerCollectionVisibleItem(
                index: index,
                frame: CGRect(
                    x: 2 + CGFloat(column) * 130,
                    y: 16 + CGFloat(row) * 130,
                    width: 126,
                    height: 126
                )
            )
        }
    }
}
