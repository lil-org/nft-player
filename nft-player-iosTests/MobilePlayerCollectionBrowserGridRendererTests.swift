// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobilePlayerCollectionBrowserGridRendererTests {
    func testCellConfigurationEncodesMaterializationInvariants() {
        let sourceConfiguration =
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
                .sourceOverscan
        XCTAssertNil(sourceConfiguration.requiredImageQuality)
        XCTAssertEqual(sourceConfiguration.imageLoadPolicy, .cachedOnly)
        XCTAssertFalse(sourceConfiguration.allowsLocalLargeImageUpgrade)

        let destinationConfiguration =
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
                .destinationPhantom(requiredImageQuality: .large)
        XCTAssertEqual(destinationConfiguration.requiredImageQuality, .large)
        XCTAssertEqual(destinationConfiguration.imageLoadPolicy, .cachedOnly)
        XCTAssertFalse(destinationConfiguration.allowsLocalLargeImageUpgrade)
    }

    func testLifecycleCleanupIsIdempotent() throws {
        let fixture = try makeFixture()

        XCTAssertEqual(fixture.renderer.lifecycleName, .idle)
        begin(fixture)
        XCTAssertEqual(fixture.renderer.lifecycleName, .active)
        XCTAssertFalse(fixture.renderer.begin(
            gestureAnchor: nil,
            sourceLayout: fixture.sourceLayout,
            wasCollectionViewPrefetchingEnabled: true
        ))

        XCTAssertNotNil(fixture.renderer.finish(preservingCarryover: false))
        XCTAssertEqual(fixture.renderer.lifecycleName, .idle)
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 0)
        XCTAssertNil(fixture.renderer.finish(preservingCarryover: false))
        XCTAssertNil(fixture.renderer.reset())
    }

    func testFinishPreservesBaseContentOffsetWithoutPan() throws {
        let fixture = try makeFixture()
        let baseContentOffsetY: CGFloat = 320
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(x: 160, y: 320),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: baseContentOffsetY
            )
        )
        XCTAssertTrue(fixture.renderer.renderZoom(
            planeID: nil,
            scale: 1.1,
            panDeltaY: 0,
            sourceLayout: fixture.sourceLayout
        ))

        let finishState = try XCTUnwrap(
            fixture.renderer.finish(preservingCarryover: false)
        )

        XCTAssertEqual(
            finishState.pannedContentOffsetY,
            baseContentOffsetY
        )
    }

    func testFinishRetainsIntentionalPinchPan() throws {
        let fixture = try makeFixture()
        let baseContentOffsetY: CGFloat = 320
        let panDeltaY: CGFloat = 60
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(x: 160, y: 320),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: baseContentOffsetY
            )
        )
        XCTAssertTrue(fixture.renderer.renderZoom(
            planeID: nil,
            scale: 1.1,
            panDeltaY: panDeltaY,
            sourceLayout: fixture.sourceLayout
        ))

        let finishState = try XCTUnwrap(
            fixture.renderer.finish(preservingCarryover: false)
        )

        XCTAssertEqual(
            finishState.pannedContentOffsetY,
            baseContentOffsetY - panDeltaY
        )
    }

    func testFinishClearsAllTransitionSessionState() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 12,
            showsSourceGrid: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertFalse(session.selectedSourceItems.isEmpty)
        XCTAssertNotNil(
            session.foregroundCurrentViewportCoverage.installedRect
        )

        XCTAssertNotNil(fixture.renderer.finish(preservingCarryover: false))

        XCTAssertTrue(session.reassignments.isEmpty)
        XCTAssertTrue(session.selectedSourceItems.isEmpty)
        XCTAssertTrue(session.preparedRepresentationIDs.isEmpty)
        XCTAssertTrue(session.lockedFallbackRepresentationIDs.isEmpty)
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.isEmpty
        )
        XCTAssertTrue(session.sourceCoverage.coveredDestinationItems.isEmpty)
        XCTAssertTrue(session.detailedSourceCellItems.isEmpty)
        XCTAssertTrue(session.cachedSourceRepresentations.isEmpty)
        XCTAssertTrue(session.transitionImageLoads.isEmpty)
        XCTAssertTrue(session.foregroundEligibleRepresentationIDs.isEmpty)
        XCTAssertTrue(session.currentViewportRepresentationIDs.isEmpty)
        XCTAssertTrue(session.cellFrameCorrections.isEmpty)
        XCTAssertTrue(session.marginCoverageRepresentationIDs.isEmpty)
        XCTAssertFalse(session.hasSourceSeamCompensationTransforms)
        XCTAssertNil(session.foregroundCurrentViewportCoverage.installedRect)
        XCTAssertNil(session.foregroundTerminalViewportCoverage.installedRect)
        XCTAssertNil(session.currentPhantomPlan)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        XCTAssertFalse(session.phantomShapeRefreshIsDirty)
    }

    func testMismatchedPlaneOperationsAreRejected() throws {
        let fixture = try makeFixture()
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        XCTAssertFalse(fixture.renderer.renderSettle(
            id: UUID(),
            scale: 1,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertNil(fixture.renderer.prepareCommit(
            id: UUID(),
            mode: .fiveColumns
        ))
        XCTAssertFalse(fixture.renderer.discardPlane(
            id: UUID(),
            sourceLayout: fixture.sourceLayout
        ))
        XCTAssertNotNil(fixture.renderer.finish(preservingCarryover: false))
    }

    func testNoPlaneReanchorPreservesCurrentTransform() throws {
        let fixture = try makeFixture()
        let viewportAnchor = CGPoint(
            x: fixture.viewportView.bounds.midX,
            y: fixture.viewportView.bounds.midY
        )
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: viewportAnchor,
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.renderZoom(
            planeID: nil,
            scale: 0.8,
            panDeltaY: 0,
            sourceLayout: fixture.sourceLayout
        ))
        let transformBeforeReanchor = fixture.collectionView.transform

        fixture.renderer.reanchorSettlingRendering(
            at: CGPoint(x: 40, y: 120)
        )
        XCTAssertTrue(fixture.renderer.renderZoom(
            planeID: nil,
            scale: 0.8,
            panDeltaY: 0,
            sourceLayout: fixture.sourceLayout
        ))

        assertTransform(
            fixture.collectionView.transform,
            equals: transformBeforeReanchor
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testInstallingPlaneReplacesActivePlane() throws {
        let fixture = try makeFixture()
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0,
            panDeltaY: 12
        ))
        let previousTransform = fixture.collectionView.transform
        let replacement = replacementRequest(for: fixture.planeRequest)

        XCTAssertTrue(fixture.renderer.installPlane(replacement))
        XCTAssertEqual(fixture.collectionView.transform, previousTransform)
        XCTAssertFalse(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0,
            panDeltaY: 12
        ))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: replacement.id,
            scale: 0.8,
            settleProgress: 0,
            panDeltaY: 12
        ))
        XCTAssertEqual(fixture.renderer.lifecycleName, .active)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testCommitAbortAndCompletionTransitions() throws {
        let fixture = try makeFixture()
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let abortedPreparation = try XCTUnwrap(
            fixture.renderer.prepareCommit(
                id: fixture.planeRequest.id,
                mode: .fiveColumns
            )
        )
        XCTAssertEqual(fixture.renderer.lifecycleName, .committing)

        fixture.renderer.abortCommit(abortedPreparation)
        XCTAssertEqual(fixture.renderer.lifecycleName, .active)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let completedPreparation = try XCTUnwrap(
            fixture.renderer.prepareCommit(
                id: fixture.planeRequest.id,
                mode: .fiveColumns
            )
        )
        XCTAssertTrue(fixture.renderer.completeCommit(completedPreparation))
        XCTAssertEqual(fixture.renderer.lifecycleName, .committing)
        XCTAssertFalse(fixture.renderer.completeCommit(completedPreparation))
        XCTAssertNotNil(fixture.renderer.finish(preservingCarryover: true))
    }

    func testPlaneChangeVisualCoverTracksOnlyActiveVisiblePresentation()
        throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true
        )
        XCTAssertFalse(fixture.renderer.planeChangeNeedsVisualCover)
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertFalse(fixture.renderer.planeChangeNeedsVisualCover)
        let session = try activeSession(fixture)
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(session.lastContentFadeAlpha, 0)
        XCTAssertTrue(fixture.renderer.planeChangeNeedsVisualCover)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertEqual(session.lastContentFadeAlpha, 0, accuracy: 0.000_001)
        XCTAssertTrue(session.contentFadeAnimationMayBeActive)
        XCTAssertTrue(fixture.renderer.planeChangeNeedsVisualCover)

        _ = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: fixture.planeRequest.toMode
        ))
        XCTAssertFalse(fixture.renderer.planeChangeNeedsVisualCover)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testNonanimatedSettleInterruptsOnlyCellOpacityAnimation() throws {
        let fixture = try makeFixture(showsSourceCell: true)
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        let transform = CABasicAnimation(keyPath: "transform.scale")
        transform.duration = 10
        sourceCell.layer.add(opacity, forKey: "opacity")
        sourceCell.layer.add(transform, forKey: "transform")

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertNil(sourceCell.layer.animation(forKey: "opacity"))
        XCTAssertNotNil(sourceCell.layer.animation(forKey: "transform"))
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testNonanimatedSettleInterruptsDestinationOpacityAnimation() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let container = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        let transform = CABasicAnimation(keyPath: "transform.scale")
        transform.duration = 10
        container.layer.add(opacity, forKey: "opacity")
        container.layer.add(transform, forKey: "transform")

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertNil(container.layer.animation(forKey: "opacity"))
        XCTAssertNotNil(container.layer.animation(forKey: "transform"))
        XCTAssertEqual(sourceCell.alpha, 1)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testEqualAlphaNonanimatedSettleInterruptsPriorContentFadeOnce()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let container = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(session.lastContentFadeAlpha, 0)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertTrue(session.contentFadeAnimationMayBeActive)

        let sourceOpacity = CABasicAnimation(keyPath: "opacity")
        sourceOpacity.duration = 10
        sourceCell.layer.add(sourceOpacity, forKey: "opacity")
        let contentOpacity = CABasicAnimation(keyPath: "opacity")
        contentOpacity.duration = 10
        container.layer.add(contentOpacity, forKey: "opacity")
        let zeroAlphaPresentationProgress: CGFloat = 0.2
        XCTAssertEqual(
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: zeroAlphaPresentationProgress
            ),
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: zeroAlphaPresentationProgress,
            panDeltaY: 0
        ))
        XCTAssertNil(sourceCell.layer.animation(forKey: "opacity"))
        XCTAssertNil(container.layer.animation(forKey: "opacity"))
        XCTAssertFalse(session.contentFadeAnimationMayBeActive)

        let laterContentOpacity = CABasicAnimation(keyPath: "opacity")
        laterContentOpacity.duration = 10
        container.layer.add(laterContentOpacity, forKey: "opacity")
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: zeroAlphaPresentationProgress,
            panDeltaY: 0
        ))
        XCTAssertFalse(session.contentFadeAnimationMayBeActive)
        XCTAssertNotNil(container.layer.animation(forKey: "opacity"))

        let laterSourceOpacity = CABasicAnimation(keyPath: "opacity")
        laterSourceOpacity.duration = 10
        sourceCell.layer.add(laterSourceOpacity, forKey: "opacity")
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.6,
            panDeltaY: 0
        ))
        XCTAssertNil(sourceCell.layer.animation(forKey: "opacity"))
        XCTAssertNil(container.layer.animation(forKey: "opacity"))
    }

    func testDirectCommitCanCompleteOrAbort() throws {
        let fixture = try makeFixture()
        begin(fixture)
        let abortedPreparation = try XCTUnwrap(
            fixture.renderer.prepareDirectCommit()
        )
        XCTAssertEqual(fixture.renderer.lifecycleName, .committing)
        fixture.renderer.abortDirectCommit(abortedPreparation)
        XCTAssertEqual(fixture.renderer.lifecycleName, .active)

        let completedPreparation = try XCTUnwrap(
            fixture.renderer.prepareDirectCommit()
        )
        XCTAssertTrue(fixture.renderer.completeDirectCommit(
            completedPreparation
        ))
        XCTAssertEqual(fixture.renderer.lifecycleName, .committing)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }
}
