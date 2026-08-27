// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobilePlayerCollectionBrowserGridRendererTests {
    func testReplacingPlaneInstallsDeferredBaseImage() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true
        )
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let sources = makeDistinctImageSources()
        let thumbnail = makeImage()
        let large = makeImage()
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        cell.installTransitionContent(
            image: makeImage(),
            descriptor: sources.largeDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )
        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        XCTAssertTrue(baseImageView.image === thumbnail)

        XCTAssertTrue(fixture.renderer.installPlane(
            replacementRequest(for: fixture.planeRequest)
        ))

        XCTAssertTrue(baseImageView.image === thumbnail)
        drainQueuedWork(fixture)
        XCTAssertTrue(baseImageView.image === large)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testReplacingPlaneDefersBaseImageUntilPreparedIncomingIsOpaque()
        async throws {
        let sources = makeDistinctImageSources()
        let replacementOverlay = makeImage()
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            contentImageSources: sources,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    completion.value = callback
                    return {}
                }
            )
        )
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let thumbnail = makeImage()
        let large = makeImage()
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        cell.installTransitionContent(
            image: makeImage(),
            descriptor: sources.largeDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )
        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        XCTAssertTrue(fixture.renderer.installPlane(
            replacementRequest(for: fixture.planeRequest)
        ))
        XCTAssertTrue(baseImageView.image === thumbnail)
        drainQueuedWork(fixture)
        XCTAssertTrue(baseImageView.image === thumbnail)
        XCTAssertNil(primaryTransitionImage(in: cell))
        XCTAssertFalse(cell.hasCarryoverContent)

        try XCTUnwrap(completion.value)(replacementOverlay)
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)

        XCTAssertTrue(baseImageView.image === thumbnail)
        XCTAssertTrue(primaryTransitionImage(in: cell) === replacementOverlay)
        XCTAssertFalse(cell.hasCarryoverContent)

        cell.setTransitionContentAlpha(1)

        XCTAssertTrue(baseImageView.image === large)
        XCTAssertTrue(primaryTransitionImage(in: cell) === replacementOverlay)
        XCTAssertFalse(cell.hasCarryoverContent)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testFadeCancellationInstallsDeferredBaseForPendingReplacement()
        async throws {
        let sources = makeDistinctImageSources()
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let cancellationCount = Counter()
        let cachedImage = Box<
            MobilePlayerCollectionBrowserGridRenderer.ImageAccess.CachedImage?
        >(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            contentImageSources: sources,
            imageAccess: .init(
                cachedImage: { _, _ in cachedImage.value },
                loadImage: { _, callback in
                    completion.value = callback
                    return { cancellationCount.value += 1 }
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let thumbnail = makeImage()
        let large = makeImage()
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        cell.installTransitionContent(
            image: makeImage(),
            descriptor: sources.largeDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )
        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let replacement = replacementRequest(for: fixture.planeRequest)
        XCTAssertTrue(fixture.renderer.installPlane(replacement))
        drainQueuedWork(fixture)
        let pendingCompletion = try XCTUnwrap(completion.value)
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(cell)
        XCTAssertTrue(baseImageView.image === thumbnail)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: replacement.id,
            scale: replacement.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertTrue(baseImageView.image === large)
        XCTAssertNil(cell.incomingTransitionContentQuality(
            representing: identity,
            from: sources
        ))
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(primaryTransitionImage(in: cell) === thumbnail)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: replacement.id,
            scale: replacement.transitionLayout.itemWidthRatio,
            settleProgress: 0.2,
            panDeltaY: 0
        ))

        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(primaryTransitionImage(in: cell) === thumbnail)

        let destinationImage = makeImage()
        cachedImage.value = (
            sources.largeDescriptor,
            .large,
            destinationImage
        )
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: replacement.id,
            scale: replacement.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(baseImageView.image === large)
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(primaryTransitionImage(in: cell) === thumbnail)
        XCTAssertFalse(primaryTransitionImage(in: cell) === destinationImage)

        let rejectedImage = makeImage()
        pendingCompletion(rejectedImage)
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)

        XCTAssertTrue(baseImageView.image === large)
        XCTAssertNil(cell.incomingTransitionContentQuality(
            representing: identity,
            from: sources
        ))
        XCTAssertFalse(primaryTransitionImage(in: cell) === rejectedImage)
    }

    func testQueuedDetailDoesNotReplaceActiveBaseUpgradeCarryover() throws {
        let sources = makeDistinctImageSources()
        let destinationImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            contentImageSources: sources,
            imageAccess: .init(
                cachedImage: { _, _ in
                    (sources.largeDescriptor, .large, destinationImage)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let thumbnail = makeImage()
        let large = makeImage()
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(primaryTransitionImage(in: cell) === thumbnail)

        drainQueuedWork(fixture)

        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(cell)
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(primaryTransitionImage(in: cell) === thumbnail)
        XCTAssertFalse(primaryTransitionImage(in: cell) === destinationImage)
    }

    func testTransitionCompletionDoesNotReplaceActiveBaseUpgradeCarryover()
        async throws {
        let sources = makeDistinctImageSources()
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            contentImageSources: sources,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    completion.value = callback
                    return {}
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let thumbnail = makeImage()
        let large = makeImage()
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let pendingCompletion = try XCTUnwrap(completion.value)

        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(primaryTransitionImage(in: cell) === thumbnail)
        let heldCarryover = try XCTUnwrap(cell.carryoverSourceContent)
        cell.setCarryoverContent(heldCarryover)
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(cell)
        XCTAssertNotNil(session.transitionImageLoads[representationID])

        let destinationImage = makeImage()
        pendingCompletion(destinationImage)
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)

        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(primaryTransitionImage(in: cell) === thumbnail)
        XCTAssertFalse(primaryTransitionImage(in: cell) === destinationImage)
    }

    func testPendingBaseCarryoverSurvivesFollowUpPlaneLifecycle() throws {
        let carryoverImage = makeImage()
        let destinationImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        destinationImage
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        sourceCell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: carryoverImage,
            usesNativeMetalCardCornerMask: false
        ))
        let sourceCellID = ObjectIdentifier(sourceCell)

        func assertCarryoverSurvives() throws {
            let carryover = try XCTUnwrap(sourceCell.carryoverSourceContent)
            XCTAssertTrue(carryover.primary.image === carryoverImage)
        }

        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        try assertCarryoverSurvives()
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(sourceCellID)
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(sourceCellID)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(sourceCellID)
        )
        try assertCarryoverSurvives()
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)
        try assertCarryoverSurvives()
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(sourceCellID)
        )
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)

        let replacement = replacementRequest(for: fixture.planeRequest)
        XCTAssertTrue(fixture.renderer.installPlane(replacement))
        drainQueuedWork(fixture)
        try assertCarryoverSurvives()
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(sourceCellID)
        )

        XCTAssertTrue(fixture.renderer.discardPlane(
            id: replacement.id,
            sourceLayout: fixture.sourceLayout
        ))
        try assertCarryoverSurvives()

        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        _ = fixture.renderer.reset()
        try assertCarryoverSurvives()

        _ = fixture.renderer.finish(preservingCarryover: false)
        XCTAssertNil(sourceCell.carryoverSourceContent)
    }

    func testResolvedPendingBaseUsesCachedDestinationAfterCarryoverCompletes()
        throws {
        let carryoverImage = makeImage()
        let baseImage = makeImage()
        let destinationImage = makeImage()
        let loadCount = Counter()
        let cacheAccessCount = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    cacheAccessCount.value += 1
                    return (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        destinationImage
                    )
                },
                loadImage: { _, _ in
                    loadCount.value += 1
                    return {}
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        sourceCell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: carryoverImage,
            usesNativeMetalCardCornerMask: false
        ))
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertEqual(session.lastContentFadeAlpha, 0, accuracy: 0.000_001)

        let baseImageView = try XCTUnwrap(
            sourceCell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        baseImageView.image = baseImage
        sourceCell.fadeOutCarryoverContentIfBaseReady()
        XCTAssertFalse(sourceCell.holdsCarryoverForPendingBaseImage)
        XCTAssertTrue(sourceCell.hasCarryoverContent)
        sourceCell.clearTransitionContent()
        XCTAssertFalse(sourceCell.hasCarryoverContent)
        let contentIdentityAccessCount = fixture.contentIdentityAccessCount.value
        let imageSourcesAccessCount = fixture.imageSourcesAccessCount.value
        let cachedImageAccessCount = cacheAccessCount.value
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ],
            0
        )
        XCTAssertTrue(primaryTransitionImage(in: sourceCell) === destinationImage)
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(
            try XCTUnwrap(transitionContentContainer(in: sourceCell)).alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )
        XCTAssertEqual(loadCount.value, 0)
        XCTAssertEqual(
            fixture.contentIdentityAccessCount.value - contentIdentityAccessCount,
            1
        )
        XCTAssertEqual(
            fixture.imageSourcesAccessCount.value - imageSourcesAccessCount,
            1
        )
        XCTAssertEqual(cacheAccessCount.value - cachedImageAccessCount, 1)
    }

    func testResolvedPendingBaseCarryoverKeepsFallbackOnDestinationCacheMiss()
        throws {
        let carryoverImage = makeImage()
        let baseImage = makeImage()
        let loadCount = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    loadCount.value += 1
                    return {}
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        sourceCell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: carryoverImage,
            usesNativeMetalCardCornerMask: false
        ))
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.2,
            panDeltaY: 0
        ))

        let baseImageView = try XCTUnwrap(
            sourceCell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        baseImageView.image = baseImage
        sourceCell.fadeOutCarryoverContentIfBaseReady()
        XCTAssertFalse(sourceCell.holdsCarryoverForPendingBaseImage)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            sourceCell.carryoverSourceContent?.primary.image === carryoverImage
        )
        XCTAssertEqual(loadCount.value, 0)
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
    }

    func testInstallingPlaneClearsStaleIncomingContent() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        sourceCell.installTransitionContent(
            image: makeImage(),
            descriptor: makeImageSources().thumbnailDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 1,
            animated: false,
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 0
            )
        )
        XCTAssertNotNil(sourceCell.carryoverSourceContent)

        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        XCTAssertNil(sourceCell.carryoverSourceContent)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testInstallingPlaneClearsCarryoverWhenBaseImageIsReady() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let baseImageView = try XCTUnwrap(
            sourceCell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        let baseImage = makeImage()
        let carryoverImage = makeImage()
        baseImageView.image = baseImage
        sourceCell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 0
            ),
            image: carryoverImage,
            usesNativeMetalCardCornerMask: false
        ))
        let carryover = try XCTUnwrap(sourceCell.carryoverSourceContent)
        XCTAssertTrue(carryover.primary.image === carryoverImage)

        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        let visibleBase = try XCTUnwrap(sourceCell.carryoverSourceContent)
        XCTAssertTrue(visibleBase.primary.image === baseImage)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPlaneInstallationDoesNotProbeContentOrCreateTransitionViews()
        throws {
        let fixture = try makeFixture(
            showsSourceCell: true,
            providesContentAccess: true
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let originalSubviewIDs = sourceCell.contentView.subviews.map(
            ObjectIdentifier.init
        )
        begin(fixture)

        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertEqual(fixture.contentIdentityAccessCount.value, 0)
        XCTAssertEqual(fixture.imageSourcesAccessCount.value, 0)
        XCTAssertEqual(
            sourceCell.contentView.subviews.map(ObjectIdentifier.init),
            originalSubviewIDs
        )
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testQueuedTransitionImageCompletionIsDiscardedOnPlaneReplacement()
        async throws {
        let callbacks = Box<[(UIImage?) -> Void]>([])
        let cancellationCount = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    callbacks.value.append(callback)
                    return { cancellationCount.value += 1 }
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let originalSubviewIDs = sourceCell.contentView.subviews.map(
            ObjectIdentifier.init
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        try XCTUnwrap(callbacks.value.first)(makeImage())
        let replacement = GridModePlaneRequest(
            id: UUID(),
            toMode: fixture.planeRequest.toMode,
            layoutAspectState: fixture.planeRequest.layoutAspectState,
            anchorTokenIndex: fixture.planeRequest.anchorTokenIndex,
            transitionLayout: fixture.planeRequest.transitionLayout,
            crossfade: fixture.planeRequest.crossfade,
            latticeMap: fixture.planeRequest.latticeMap
        )
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                fixture.renderer.pendingMaterializationWorkCount,
                1
            )
            XCTAssertTrue(fixture.renderer.installPlane(replacement))
            XCTAssertEqual(cancellationCount.value, 1)
            self.drainQueuedWork(fixture)
        }

        XCTAssertEqual(
            sourceCell.contentView.subviews.map(ObjectIdentifier.init),
            originalSubviewIDs
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testRepeatedDetailWorkKeepsMatchingImageLoad() throws {
        let callbacks = Box<[(UIImage?) -> Void]>([])
        let cancellationCount = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    callbacks.value.append(callback)
                    return { cancellationCount.value += 1 }
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        XCTAssertEqual(callbacks.value.count, 1)

        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )
        drainQueuedWork(fixture)

        XCTAssertEqual(callbacks.value.count, 1)
        XCTAssertEqual(cancellationCount.value, 0)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertEqual(session.transitionImageLoads.count, 1)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testFadeInvalidatesFallbackImageWorkInSingleQueuePass()
        async throws {
        let callbacks = Box<[(UIImage?) -> Void]>([])
        let cancellationCount = Counter()
        let fixture = try makeFixture(
            itemCount: 120,
            sourceColumnCount: 5,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    callbacks.value.append(callback)
                    return { cancellationCount.value += 1 }
                }
            )
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let activeLoadCount = session.transitionImageLoads.count
        XCTAssertGreaterThan(activeLoadCount, 2)
        XCTAssertEqual(callbacks.value.count, activeLoadCount)

        let image = makeImage()
        callbacks.value.forEach { $0(image) }
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                fixture.renderer
                    .pendingTransitionImageCompletionWorkCount,
                activeLoadCount
            )
            let filterPassCount = fixture.renderer
                .transitionWorkQueueFilterPassCount

            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: 1,
                settleProgress: 0.5,
                panDeltaY: 0
            ))

            XCTAssertEqual(
                fixture.renderer.transitionWorkQueueFilterPassCount
                    - filterPassCount,
                1
            )
            XCTAssertEqual(cancellationCount.value, activeLoadCount)
            XCTAssertTrue(session.transitionImageLoads.isEmpty)
            XCTAssertEqual(
                fixture.renderer
                    .pendingTransitionImageCompletionWorkCount,
                0
            )
            XCTAssertEqual(
                fixture.renderer
                    .pendingDetailMaterializationWorkCount,
                0
            )
        }

        callbacks.value.forEach { $0(image) }
        await runOnNextMainQueueTurn()
        XCTAssertEqual(
            fixture.renderer.pendingTransitionImageCompletionWorkCount,
            0
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testFadeReversalRetriesPreviouslyLockedFallback() async throws {
        let callbacks = Box<[(UIImage?) -> Void]>([])
        let cancellationCount = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    callbacks.value.append(callback)
                    return { cancellationCount.value += 1 }
                }
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
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertEqual(callbacks.value.count, 1)
        XCTAssertEqual(session.transitionImageLoads.count, 1)
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertTrue(session.transitionImageLoads.isEmpty)

        // Just below the fade start is the rearm dead band: the fallback must
        // stay locked so threshold hover cannot churn image work.
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: PlayerBrowserGridCrossfade
                .contentFadeRearmSettleProgress + 0.02,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        drainQueuedWork(fixture)
        XCTAssertEqual(callbacks.value.count, 1)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        drainQueuedWork(fixture)
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(callbacks.value.count, 2)
        XCTAssertEqual(session.transitionImageLoads.count, 1)

        let oldImage = makeImage()
        callbacks.value[0](oldImage)
        await runOnNextMainQueueTurn()
        XCTAssertEqual(
            fixture.renderer.pendingTransitionImageCompletionWorkCount,
            0
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(session.transitionImageLoads.count, 1)
        XCTAssertNil(primaryTransitionImage(in: sourceCell))

        let newImage = makeImage()
        callbacks.value[1](newImage)
        await runOnNextMainQueueTurn()
        XCTAssertEqual(
            fixture.renderer.pendingTransitionImageCompletionWorkCount,
            1
        )
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(primaryTransitionImage(in: sourceCell) === newImage)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )
        XCTAssertEqual(
            contentContainer.alpha,
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: 0.5
            ),
            accuracy: 0.000_001
        )
    }

    func testFadePreservesReadyImageUpgradeLoad() async throws {
        let callback = Box<((UIImage?) -> Void)?>(nil)
        let cancellationCount = Counter()
        let cachedImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            contentImageSources: makeDistinctImageSources(),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        cachedImage
                    )
                },
                loadImage: { _, completion in
                    callback.value = completion
                    return { cancellationCount.value += 1 }
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let sourceCellID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(session.preparedRepresentationIDs.contains(sourceCellID))
        XCTAssertNotNil(session.transitionImageLoads[sourceCellID])

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertEqual(cancellationCount.value, 0)
        XCTAssertNotNil(session.transitionImageLoads[sourceCellID])
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(sourceCellID)
        )

        try XCTUnwrap(callback.value)(makeImage())
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)
        XCTAssertNil(session.transitionImageLoads[sourceCellID])
        XCTAssertEqual(cancellationCount.value, 0)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testReadyImageUpgradeCompletionKeepsMarginHeldContentHidden()
        async throws {
        let callbacks = Box<[(UIImage?) -> Void]>([])
        let cachedImage = makeImage()
        let imageSources = makeDistinctImageSources()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            contentImageSources: imageSources,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        cachedImage
                    )
                },
                loadImage: { _, completion in
                    callbacks.value.append(completion)
                    return {}
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.first {
                session.transitionImageLoads[$0] != nil
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(session.lastContentFadeAlpha, 0)
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.transitionImageLoads[representationID])
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)
        let destinationItem = try XCTUnwrap(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: destinationItem
        )
        XCTAssertEqual(
            representation.cell.incomingTransitionContentQuality(
                representing: identity,
                from: imageSources
            ),
            .thumbnail
        )

        let upgradeImage = makeImage()
        callbacks.value.forEach { $0(upgradeImage) }
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)

        XCTAssertNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(
            representation.cell.incomingTransitionContentQuality(
                representing: identity,
                from: imageSources
            ),
            .large
        )
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)
    }

    func testPreparedContentSurvivesEligibilityReentryAfterCacheEviction()
        throws {
        let returnsCachedImage = Box(true)
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 5,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            contentImageSources: makeDistinctImageSources(),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    guard returnsCachedImage.value else { return nil }
                    return (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        let reentered = try reenterPreparedRepresentation(
            fixture: fixture,
            afterInitialMaterialization: {
                returnsCachedImage.value = false
            }
        )

        XCTAssertTrue(
            reentered.session.preparedRepresentationIDs.contains(
                reentered.representationID
            )
        )
        XCTAssertTrue(
            primaryTransitionImage(in: reentered.cell) === image
        )
        XCTAssertNotNil(
            reentered.session.transitionImageLoads[
                reentered.representationID
            ]
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPreparedLargeContentIsNotDowngradedOnEligibilityReentry()
        throws {
        let returnsLargeImage = Box(true)
        let largeImage = makeImage()
        let thumbnailImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 5,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            contentImageSources: makeDistinctImageSources(),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    returnsLargeImage.value
                        ? (
                            imageSources.largeDescriptor,
                            .large,
                            largeImage
                        )
                        : (
                            imageSources.thumbnailDescriptor,
                            .thumbnail,
                            thumbnailImage
                        )
                },
                loadImage: { _, _ in {} }
            )
        )
        let reentered = try reenterPreparedRepresentation(
            fixture: fixture,
            afterInitialMaterialization: {
                returnsLargeImage.value = false
            }
        )

        XCTAssertTrue(
            primaryTransitionImage(in: reentered.cell) === largeImage
        )
        XCTAssertNil(
            reentered.session.transitionImageLoads[
                reentered.representationID
            ]
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPreparedThumbnailModeContentUsesNewCachedLargeOnReentry()
        throws {
        let returnsThumbnailImage = Box(true)
        let thumbnailImage = makeImage()
        let largeImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            contentImageSources: makeDistinctImageSources(),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    returnsThumbnailImage.value
                        ? (
                            imageSources.thumbnailDescriptor,
                            .thumbnail,
                            thumbnailImage
                        )
                        : (
                            imageSources.largeDescriptor,
                            .large,
                            largeImage
                        )
                },
                loadImage: { _, _ in {} }
            )
        )
        let reentered = try reenterPreparedRepresentation(
            fixture: fixture,
            panDistanceInViewports: 0.5,
            afterInitialMaterialization: {
                returnsThumbnailImage.value = false
            }
        )

        XCTAssertTrue(
            primaryTransitionImage(in: reentered.cell) === largeImage
        )
        XCTAssertNil(
            reentered.session.transitionImageLoads[
                reentered.representationID
            ]
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPreparedThumbnailModeContentKeepsHigherCachedQualityOnReentry()
        throws {
        let returnsLargeImage = Box(true)
        let largeImage = makeImage()
        let thumbnailImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            contentImageSources: makeDistinctImageSources(),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    returnsLargeImage.value
                        ? (
                            imageSources.largeDescriptor,
                            .large,
                            largeImage
                        )
                        : (
                            imageSources.thumbnailDescriptor,
                            .thumbnail,
                            thumbnailImage
                        )
                },
                loadImage: { _, _ in {} }
            )
        )
        let reentered = try reenterPreparedRepresentation(
            fixture: fixture,
            panDistanceInViewports: 0.5,
            afterInitialMaterialization: {
                returnsLargeImage.value = false
            }
        )

        XCTAssertTrue(
            primaryTransitionImage(in: reentered.cell) === largeImage
        )
        XCTAssertNil(
            reentered.session.transitionImageLoads[
                reentered.representationID
            ]
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testTransitionCompletionPriorityTracksCurrentViewport()
        async throws {
        let callback = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, completion in
                    callback.value = completion
                    return {}
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let loaded = try XCTUnwrap(callback.value)
        sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY
        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertNotNil(session.cachedSourceRepresentations[representationID])
        XCTAssertNotNil(session.transitionImageLoads[representationID])

        loaded(makeImage())
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                fixture.renderer
                    .pendingTransitionImageCompletionWorkCount,
                1
            )
            XCTAssertEqual(
                fixture.renderer
                    .pendingVisibleTransitionImageCompletionWorkCount,
                0
            )

            sourceCell.frame.origin.y =
                fixture.viewportView.bounds.minY
            fixture.renderer.didConfigureCell(
                sourceCell,
                at: IndexPath(item: 0, section: 0)
            )

            XCTAssertEqual(
                fixture.renderer
                    .pendingTransitionImageCompletionWorkCount,
                1
            )
            XCTAssertEqual(
                fixture.renderer
                    .pendingVisibleTransitionImageCompletionWorkCount,
                1
            )

            sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY
            fixture.renderer.didConfigureCell(
                sourceCell,
                at: IndexPath(item: 0, section: 0)
            )

            XCTAssertEqual(
                fixture.renderer
                    .pendingVisibleTransitionImageCompletionWorkCount,
                0
            )
        }
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testForegroundTransitionLoadsTrackCurrentOrTerminalViewport()
        throws {
        let cancellationCount = Counter()
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 5,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    return { cancellationCount.value += 1 }
                }
            )
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let terminalScale = fixture.planeRequest.transitionLayout
            .itemWidthRatio

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)

        let firstEligibleIDs = foregroundEligibleRepresentationIDs(
            fixture: fixture,
            session: session,
            panDeltaY: 0
        )
        let firstLoadIDs = Set(session.transitionImageLoads.keys)
        let selectedRepresentationIDs = Set(
            session.cachedSourceRepresentations.compactMap {
                representationID, representation in
                session.selectedSourceItems.contains(
                    representation.itemIndex
                ) ? representationID : nil
            }
        )
        XCTAssertEqual(firstLoadIDs, firstEligibleIDs)
        XCTAssertTrue(firstLoadIDs.isSubset(of: selectedRepresentationIDs))

        let cancellationCountBeforePan = cancellationCount.value
        let panDeltaY = -fixture.viewportView.bounds.height
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: panDeltaY
        ))
        drainQueuedWork(fixture)

        let secondEligibleIDs = foregroundEligibleRepresentationIDs(
            fixture: fixture,
            session: session,
            panDeltaY: panDeltaY
        )
        let secondLoadIDs = Set(session.transitionImageLoads.keys)
        let removedIDs = firstLoadIDs.subtracting(secondLoadIDs)
        let addedIDs = secondLoadIDs.subtracting(firstLoadIDs)
        XCTAssertEqual(secondLoadIDs, secondEligibleIDs)
        XCTAssertFalse(removedIDs.isEmpty)
        XCTAssertFalse(addedIDs.isEmpty)
        XCTAssertGreaterThanOrEqual(
            cancellationCount.value - cancellationCountBeforePan,
            removedIDs.count
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testQueuedTransitionImageCompletionIsDiscardedOnFinish() async throws {
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    completion.value = callback
                    return {}
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let originalSubviewIDs = sourceCell.contentView.subviews.map(
            ObjectIdentifier.init
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        try XCTUnwrap(completion.value)(makeImage())
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                fixture.renderer.pendingMaterializationWorkCount,
                1
            )
            XCTAssertNotNil(fixture.renderer.finish(
                preservingCarryover: false
            ))
        }
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 0)
        _ = fixture.renderer.drainMaterializationWork()
        XCTAssertEqual(
            sourceCell.contentView.subviews.map(ObjectIdentifier.init),
            originalSubviewIDs
        )
    }

    func testUnreadyCompletionCannotInstallAfterFadeStarts() async throws {
        let completion = Box<((UIImage?) -> Void)?>(nil)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    completion.value = callback
                    return {}
                }
            )
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let originalSubviewIDs = sourceCell.contentView.subviews.map(
            ObjectIdentifier.init
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        try XCTUnwrap(completion.value)(makeImage())
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                fixture.renderer.pendingMaterializationWorkCount,
                1
            )
            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: 0.8,
                settleProgress: 0.6,
                panDeltaY: 0
            ))
            self.drainQueuedWork(fixture)
        }

        XCTAssertEqual(
            sourceCell.contentView.subviews.map(ObjectIdentifier.init),
            originalSubviewIDs
        )
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertFalse(session.preparedRepresentationIDs.contains(
            ObjectIdentifier(sourceCell)
        ))
        XCTAssertTrue(session.lockedFallbackRepresentationIDs.contains(
            ObjectIdentifier(sourceCell)
        ))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testFallbackSourceIsExcludedFromCommitAndRestoredOnAbort() throws {
        let fixture = try makeFixture(showsSourceCell: true)
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        sourceCell.layer.add(opacity, forKey: "opacity")

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .fiveColumns
        ))

        XCTAssertEqual(preparation.carryoverSourceCount, 0)
        XCTAssertNil(sourceCell.layer.animation(forKey: "opacity"))
        XCTAssertEqual(sourceCell.alpha, 1)
        fixture.renderer.abortCommit(preparation)
        XCTAssertEqual(fixture.renderer.lifecycleName, .active)
        XCTAssertEqual(sourceCell.alpha, 1)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testCommitCapturesFallbackSourceWhenRequested() throws {
        let fallbackImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        sourceCell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 0
            ),
            image: fallbackImage,
            usesNativeMetalCardCornerMask: false
        ))
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        XCTAssertTrue(
            session.sourceCoverage.fallbackRepresentationIDs.contains(
                ObjectIdentifier(sourceCell)
            )
        )

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .fiveColumns,
            capturesFallbackSources: true
        ))

        XCTAssertGreaterThan(preparation.carryoverSourceCount, 0)
        XCTAssertNil(sourceCell.carryoverSourceContent)
        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        XCTAssertTrue(
            sourceCell.carryoverSourceContent?.primary.image === fallbackImage
        )
        _ = fixture.renderer.finish(preservingCarryover: true)
    }

    func testFallbackSourceStaysOpaqueOverDestinationCoverage() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            anchorItemIndex: 0
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
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(
            session.sourceCoverage.fallbackRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.sourceCoverage.coveredDestinationItems.contains(0)
        )
        let destinationCoverage: UIView
        if let phantom = session.phantomCells[0] {
            destinationCoverage = phantom
        } else {
            destinationCoverage = try XCTUnwrap(session.phantomShapeView)
        }
        XCTAssertFalse(destinationCoverage.isHidden)
        let coverageIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: destinationCoverage)
        )
        let sourceIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: sourceCell)
        )
        XCTAssertLessThan(coverageIndex, sourceIndex)

        let progress: CGFloat = 0.5
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: progress,
            panDeltaY: 0
        ))
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 1,
            panDeltaY: 0
        ))
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
    }

    func testReadySourceDemotionInstallsBackingCoverageBeforeFading() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
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
        let representationID = ObjectIdentifier(sourceCell)
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )
        XCTAssertEqual(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ],
            0
        )

        let progress: CGFloat = 0.5
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: progress,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(contentContainer.alpha, 0)
        let destinationPlanBuildCount = fixture.renderer
            .destinationPlanBuildCount
        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )

        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.sourceCoverage.coveredDestinationItems.contains(0)
        )
        XCTAssertGreaterThan(
            fixture.renderer.destinationPlanBuildCount,
            destinationPlanBuildCount
        )
        XCTAssertTrue(
            session.currentPhantomPlan?.cellCandidates.contains {
                $0.destinationItemIndex == 0
            } == true
        )
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        XCTAssertFalse(shapeView.isHidden)
        XCTAssertNotNil(layers.candidates.path)
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)
        XCTAssertLessThan(
            try XCTUnwrap(
                fixture.collectionView.subviews.firstIndex(of: shapeView)
            ),
            try XCTUnwrap(
                fixture.collectionView.subviews.firstIndex(of: sourceCell)
            )
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
    }

    func testTwoPhaseCommitInstallsCapturedPhantomCarryover() throws {
        let fixture = try makeFixture(
            showsSourceCell: true,
            providesContentAccess: true,
            installsSyntheticContent: true,
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let (phantomDestinationItem, phantom) = try XCTUnwrap(
            session.phantomCells.first
        )
        phantom.frame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: phantomDestinationItem)
        )
        let expectedIdentity = try XCTUnwrap(
            phantom.carryoverSourceContent?.identity
        )

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .fiveColumns,
            capturesFallbackSources: true
        ))

        XCTAssertGreaterThan(preparation.carryoverSourceCount, 0)
        guard case let .committing(commit) = fixture.renderer.lifecycle else {
            return XCTFail("Expected a committing renderer session")
        }
        let capturedPhantom = try XCTUnwrap(commit.sources.first {
            $0.content?.identity == expectedIdentity
        })
        XCTAssertEqual(
            capturedPhantom.destinationItem,
            phantomDestinationItem
        )
        fixture.collectionView.setCollectionViewLayout(
            makeCollectionViewLayout(
                browserLayout: fixture.destinationLayout
            ),
            animated: false
        )
        fixture.collectionView.contentOffset.y =
            preparation.terminalContentOffsetY
        fixture.collectionView.reloadData()
        fixture.collectionView.layoutIfNeeded()
        let destinationCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: phantomDestinationItem, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        XCTAssertNil(destinationCell.carryoverSourceContent)
        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        XCTAssertEqual(
            destinationCell.carryoverSourceContent?.identity,
            expectedIdentity
        )
        _ = fixture.renderer.finish(preservingCarryover: true)
    }

    func testCommitUsesMappedHighestAvailableCachedFallback() throws {
        let cacheAccessCount = Counter()
        let selectionPolicies = Box<[CachedImageSelectionPolicy]>([])
        let fallbackImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, selectionPolicy in
                    cacheAccessCount.value += 1
                    selectionPolicies.value.append(selectionPolicy)
                    let descriptor = imageSources.thumbnailDescriptor
                    return (
                        descriptor,
                        .thumbnail,
                        fallbackImage
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        let destinationCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let destinationItem = 0
        let destinationFrame = try XCTUnwrap(
            fixture.planeRequest.transitionLayout.toLayout.itemFrame(
                at: destinationItem
            )
        )
        let expectedSourceItem = try XCTUnwrap(
            fixture.sourceLayout.nearestItemIndex(
                to: fixture.planeRequest.latticeMap.sourcePoint(
                    fromDestination: CGPoint(
                        x: destinationFrame.midX,
                        y: destinationFrame.midY
                    )
                ),
                tolerance: fixture.sourceLayout.interItemSpacing + 1
            )
        )

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .fiveColumns
        ))
        XCTAssertEqual(preparation.carryoverSourceCount, 0)

        XCTAssertTrue(fixture.renderer.completeCommit(preparation))

        let carryover = try XCTUnwrap(destinationCell.carryoverSourceContent)
        XCTAssertTrue(carryover.primary.image === fallbackImage)
        XCTAssertEqual(
            carryover.identity,
            MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: expectedSourceItem
            )
        )
        XCTAssertEqual(cacheAccessCount.value, 1)
        XCTAssertEqual(selectionPolicies.value.last, .highestAvailable)
        _ = fixture.renderer.finish(preservingCarryover: true)
    }

    func testCommitFallbackUsesRetainedDegradedWinner() throws {
        let cacheIsReady = Box(false)
        let cacheAccessCount = Counter()
        let fallbackImage = makeImage()
        var ratios = Array(repeating: CGFloat(1), count: 12)
        ratios[3] = 2
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            heightToWidthRatios: ratios,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    cacheAccessCount.value += 1
                    guard cacheIsReady.value else { return nil }
                    return (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        fallbackImage
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: true) }
        let firstCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let laterCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 1, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let visibleFrame = firstCell.frame
        let bufferedFrame = CGRect(
            x: visibleFrame.minX,
            y: fixture.viewportView.bounds.maxY + 8,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        firstCell.frame = bufferedFrame
        laterCell.frame = visibleFrame
        let firstSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 0)
        )
        let laterSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 1)
        )
        let firstDestinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: 0)
        )
        let request = GridModePlaneRequest(
            id: UUID(),
            toMode: fixture.planeRequest.toMode,
            layoutAspectState: fixture.planeRequest.layoutAspectState,
            anchorTokenIndex: 0,
            transitionLayout: fixture.planeRequest.transitionLayout,
            crossfade: fixture.planeRequest.crossfade,
            latticeMap: MobilePlayerBrowserGridLatticeMap(
                columnPitchRatio: 1,
                rowPitchRatio: 1,
                fromAnchorContentPoint: CGPoint(
                    x: firstSourceFrame.midX,
                    y: firstSourceFrame.midY
                ),
                toAnchorContentPoint: CGPoint(
                    x: firstDestinationFrame.midX,
                    y: firstDestinationFrame.midY
                )
            )
        )
        let destinationItem = try XCTUnwrap(
            fixture.destinationLayout.nearestItemIndex(
                to: request.latticeMap.destinationPoint(
                    fromSource: CGPoint(
                        x: laterSourceFrame.midX,
                        y: laterSourceFrame.midY
                    )
                ),
                tolerance: fixture.destinationLayout.interItemSpacing + 1
            )
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        XCTAssertNil(session.reassignments[0])
        XCTAssertEqual(session.reassignments[1], destinationItem)

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: request.id,
            mode: .large,
            capturesFallbackSources: true
        ))
        guard case let .committing(commit) = fixture.renderer.lifecycle else {
            return XCTFail("Expected a committing renderer session")
        }
        XCTAssertEqual(
            commit.fallbackSourceItemByDestinationItem[destinationItem],
            1
        )
        XCTAssertTrue(commit.session.reassignments.isEmpty)
        firstCell.frame = visibleFrame
        laterCell.frame = bufferedFrame
        let cacheAccessCountBeforeCompletion = cacheAccessCount.value
        cacheIsReady.value = true

        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        let carryover = try XCTUnwrap(firstCell.carryoverSourceContent)
        XCTAssertTrue(carryover.primary.image === fallbackImage)
        XCTAssertEqual(
            carryover.identity,
            MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 1
            )
        )
        XCTAssertGreaterThan(
            cacheAccessCount.value,
            cacheAccessCountBeforeCompletion
        )
    }

    func testCommitDoesNotInverseFillMissingRetainedMapping() throws {
        let itemCount = PlayerBrowserGridRenderBudget.maximumVisualCellCount + 5
        let cacheIsReady = Box(false)
        let cacheAccessCount = Counter()
        let fixture = try makeFixture(
            itemCount: itemCount,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            heightToWidthRatios: Array(
                repeating: 0.01,
                count: itemCount
            ),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    cacheAccessCount.value += 1
                    guard cacheIsReady.value else { return nil }
                    return (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        self.makeImage()
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: true) }
        let sourceItem = itemCount - 1
        let sourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: sourceItem)
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: 0)
        )
        let request = GridModePlaneRequest(
            id: UUID(),
            toMode: fixture.planeRequest.toMode,
            layoutAspectState: fixture.planeRequest.layoutAspectState,
            anchorTokenIndex: 0,
            transitionLayout: fixture.planeRequest.transitionLayout,
            crossfade: fixture.planeRequest.crossfade,
            latticeMap: MobilePlayerBrowserGridLatticeMap(
                columnPitchRatio: 1,
                rowPitchRatio: 1,
                fromAnchorContentPoint: CGPoint(
                    x: sourceFrame.midX,
                    y: sourceFrame.midY
                ),
                toAnchorContentPoint: CGPoint(
                    x: destinationFrame.midX,
                    y: destinationFrame.midY
                )
            )
        )
        let destinationCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        let session = try activeSession(fixture)
        XCTAssertFalse(session.selectedSourceItems.contains(sourceItem))

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: request.id,
            mode: .fiveColumns,
            capturesFallbackSources: true
        ))
        guard case let .committing(commit) = fixture.renderer.lifecycle else {
            return XCTFail("Expected a committing renderer session")
        }
        XCTAssertNil(commit.fallbackSourceItemByDestinationItem[0])
        let cacheAccessCountBeforeCompletion = cacheAccessCount.value
        cacheIsReady.value = true

        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        XCTAssertEqual(cacheAccessCount.value, cacheAccessCountBeforeCompletion)
        XCTAssertNil(destinationCell.carryoverSourceContent)
    }

    func testNilCapturedOverlapFallsBackToMappedCachedImage() throws {
        let cacheIsReady = Box(false)
        let fallbackImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    guard cacheIsReady.value else { return nil }
                    return (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        fallbackImage
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        let destinationCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let phantom = try XCTUnwrap(session.phantomCells.values.first)
        XCTAssertNil(phantom.carryoverSourceContent)
        phantom.frame = destinationCell.frame

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .fiveColumns
        ))
        XCTAssertGreaterThan(preparation.carryoverSourceCount, 0)
        cacheIsReady.value = true

        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        let carryover = try XCTUnwrap(destinationCell.carryoverSourceContent)
        XCTAssertTrue(carryover.primary.image === fallbackImage)
        _ = fixture.renderer.finish(preservingCarryover: true)
    }

    func testUnavailableMappedFallbackRetainsTone() throws {
        let selectionPolicies = Box<[CachedImageSelectionPolicy]>([])
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, selectionPolicy in
                    selectionPolicies.value.append(selectionPolicy)
                    return nil
                },
                loadImage: { _, _ in {} }
            )
        )
        let destinationCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .fiveColumns
        ))

        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        XCTAssertNil(destinationCell.carryoverSourceContent)
        XCTAssertEqual(selectionPolicies.value, [.highestAvailable])
        let finish = try XCTUnwrap(
            fixture.renderer.finish(preservingCarryover: true)
        )
        XCTAssertTrue(finish.clearsTransitionPlaceholderTones)
    }

    func testCommitExcludesMappingFailuresFromFallbacks() throws {
        let cacheAccessCount = Counter()
        let cachedImage = makeImage()
        let sourceImage = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    cacheAccessCount.value += 1
                    return (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        cachedImage
                    )
                },
                loadImage: { _, _ in {} }
            )
        )
        let request = try requestWithFailedMapping(fixture: fixture)
        let destinationCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        destinationCell.setCarryoverContent(
            MobilePlayerBrowserCarryoverContent(
                identity: MobilePlayerBrowserContentIdentity(
                    collectionId: "collection",
                    tokenIndex: 0
                ),
                image: sourceImage,
                usesNativeMetalCardCornerMask: false
            )
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertNil(session.reassignments[0])

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: request.id,
            mode: .fiveColumns,
            capturesFallbackSources: true
        ))
        XCTAssertEqual(preparation.carryoverSourceCount, 0)
        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        XCTAssertEqual(cacheAccessCount.value, 0)
        XCTAssertNil(destinationCell.carryoverSourceContent)
        let finish = try XCTUnwrap(
            fixture.renderer.finish(preservingCarryover: true)
        )
        XCTAssertTrue(finish.clearsTransitionPlaceholderTones)
    }

    func testCommitDoesNotRefillFallbacksBeyondMappedSourceBudget() throws {
        let itemCount = PlayerBrowserGridRenderBudget
            .maximumVisualCellCount + 5
        let fixture = try makeFixture(
            itemCount: itemCount,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            heightToWidthRatios: Array(
                repeating: 0.01,
                count: itemCount
            )
        )
        let request = try requestWithFailedMapping(fixture: fixture)
        let sourceImage = makeImage()
        for indexPath in fixture.collectionView.indexPathsForVisibleItems {
            let cell = try XCTUnwrap(
                fixture.collectionView.cellForItem(at: indexPath)
                    as? MobilePlayerCollectionBrowserCell
            )
            cell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
                identity: MobilePlayerBrowserContentIdentity(
                    collectionId: "collection",
                    tokenIndex: indexPath.item
                ),
                image: sourceImage,
                usesNativeMetalCardCornerMask: false
            ))
        }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let selectedItems = session.selectedSourceItems
        XCTAssertEqual(
            selectedItems.count,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        XCTAssertGreaterThan(
            fixture.collectionView.indexPathsForVisibleItems.count,
            selectedItems.count
        )

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: request.id,
            mode: .fiveColumns,
            capturesFallbackSources: true
        ))
        XCTAssertEqual(preparation.carryoverSourceCount, 0)

        fixture.renderer.abortCommit(preparation)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testCommitReconcilesSourceInstalledAtBudgetBoundary() throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            providesContentAccess: true,
            anchorItemIndex: 0,
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        let request = try requestWithFailedMapping(fixture: fixture)
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        for _ in 0 ..< 20 {
            guard session.sourceOverscanCells[0] == nil else { break }
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertNotNil(session.sourceOverscanCells[0])
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(session.selectedSourceItems.contains(0))
        let sourceCoverageBuildCount = fixture.renderer
            .sourceCoverageBuildCount

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: request.id,
            mode: .fiveColumns
        ))
        XCTAssertEqual(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount + 1
        )

        fixture.renderer.abortCommit(preparation)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testSourceFadeCacheRetainsValidBufferedRepresentations() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let sourceCellID = ObjectIdentifier(sourceCell)
        XCTAssertEqual(
            session.cachedSourceRepresentations[sourceCellID]?.itemIndex,
            0
        )

        sourceCell.frame.origin.y = fixture.collectionView.bounds.maxY + 2_000
        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )

        XCTAssertTrue(
            session.cachedSourceRepresentations[sourceCellID]?.cell
                === sourceCell
        )
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 1,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            sourceCell.alpha,
            1,
            accuracy: 0.000_001,
            "a buffered fallback keeps its old pixels opaque, Photos-style"
        )

        sourceCell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 1
            ),
            itemCount: 2,
            imageSources: nil,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        sourceCell.alpha = 0.625
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertEqual(sourceCell.alpha, 0.625, accuracy: 0.000_001)

        fixture.renderer.didEndDisplayingCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertNil(session.cachedSourceRepresentations[sourceCellID])
        _ = fixture.renderer.finish(preservingCarryover: false)
        XCTAssertTrue(session.cachedSourceRepresentations.isEmpty)
    }

    func testSourceFadeCacheDropsRecycledOverscanRepresentation() throws {
        let fixture = try makeFixture(
            itemCount: 30,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let cachedOverscan = try XCTUnwrap(
            session.sourceOverscanCells.first { _, cell in
                session.cachedSourceRepresentations[
                    ObjectIdentifier(cell)
                ] != nil
            }
        )
        let itemIndex = cachedOverscan.key
        let overscanCell = cachedOverscan.value
        let overscanID = ObjectIdentifier(overscanCell)
        let replacementCell = MobilePlayerCollectionBrowserCell(frame: .zero)
        replacementCell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: itemIndex
            ),
            itemCount: 30,
            imageSources: nil,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )

        fixture.renderer.didConfigureCell(
            replacementCell,
            at: IndexPath(item: itemIndex, section: 0)
        )

        XCTAssertNil(session.sourceOverscanCells[itemIndex])
        XCTAssertNil(session.cachedSourceRepresentations[overscanID])
        XCTAssertNil(overscanCell.superview)
        XCTAssertFalse(overscanCell.represents(tokenIndex: itemIndex))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testReconfiguredRepresentationCancelsOldItemWork() throws {
        let cancellationCount = Counter()
        let fixture = try makeFixture(
            itemCount: 30,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    return { cancellationCount.value += 1 }
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(cell)
        XCTAssertNotNil(session.transitionImageLoads[representationID])
        fixture.renderer.willDisplayCell(
            cell,
            at: IndexPath(item: 0, section: 0)
        )

        cell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        cell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 1
            ),
            itemCount: 30,
            imageSources: nil,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        fixture.renderer.didConfigureCell(
            cell,
            at: IndexPath(item: 1, section: 0)
        )

        XCTAssertGreaterThan(cancellationCount.value, 0)
        XCTAssertNil(session.transitionImageLoads[representationID])
        XCTAssertFalse(
            fixture.renderer.pendingDetailMaterializationRepresentationKeys
                .contains(.init(
                    representationID: representationID,
                    sourceItem: 0
                ))
        )
        XCTAssertFalse(
            fixture.renderer.pendingPromotionRepresentationKeys.contains(
                .init(representationID: representationID, tokenIndex: 0)
            )
        )
    }
}
