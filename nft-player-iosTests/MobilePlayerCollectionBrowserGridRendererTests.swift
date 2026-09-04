// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobilePlayerCollectionBrowserGridRendererTests {
    func testFiveAndNineColumnTransitionsUseDestinationDecodeVariant()
        throws {
        try assertTransitionDecodeVariants(
            sourceColumnCount: 5,
            destinationColumnCount: 9,
            destinationMode: .nineColumns,
            expectedVariant: .downsampled(maxPixelWidth: 160)
        )
        try assertTransitionDecodeVariants(
            sourceColumnCount: 9,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            expectedVariant: .downsampled(maxPixelWidth: 288)
        )
    }

    func testFiveAndThreeColumnTransitionsUseDestinationDecodeVariant()
        throws {
        try assertTransitionDecodeVariants(
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            expectedVariant: .full
        )
        try assertTransitionDecodeVariants(
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            expectedVariant: .downsampled(maxPixelWidth: 288)
        )
    }

    private func assertTransitionDecodeVariants(
        sourceColumnCount: Int,
        destinationColumnCount: Int,
        destinationMode: MobileCollectionBrowserGridMode,
        expectedVariant: DownloadableMediaImageDecodeVariant
    ) throws {
        let cachedImageVariants = Box<[
            DownloadableMediaImageDecodeVariant
        ]>([])
        let loadVariants = Box<[
            DownloadableMediaImageDecodeVariant
        ]>([])
        let defaultImageSources = makeImageSources()
        let imageSources = CollectionBrowseImageSources(
            smallestThumbnailDescriptor:
                defaultImageSources.thumbnailDescriptor,
            smallThumbnailDescriptor:
                defaultImageSources.thumbnailDescriptor,
            thumbnailDescriptor: defaultImageSources.thumbnailDescriptor,
            largeDescriptor: defaultImageSources.largeDescriptor
        )
        let fixture = try makeFixture(
            itemCount: 90,
            sourceColumnCount: sourceColumnCount,
            destinationColumnCount: destinationColumnCount,
            destinationMode: destinationMode,
            showsSourceGrid: true,
            providesContentAccess: true,
            contentImageSources: imageSources,
            imageAccess: .init(
                cachedImage: { _, _, decodeSelection in
                    guard case let .satisfying(variant) =
                        decodeSelection.normalized else {
                        return nil
                    }
                    cachedImageVariants.value.append(variant)
                    return nil
                },
                loadImage: { _, variant, _ in
                    loadVariants.value.append(variant)
                    return {}
                }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }

        XCTAssertEqual(fixture.planeRequest.imageDecodeVariant, expectedVariant)
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        XCTAssertFalse(cachedImageVariants.value.isEmpty)
        XCTAssertTrue(cachedImageVariants.value.allSatisfy {
            $0 == expectedVariant
        })
        XCTAssertFalse(
            loadVariants.value.isEmpty,
            "\(sourceColumnCount)→\(destinationColumnCount) did not load"
        )
        XCTAssertTrue(loadVariants.value.allSatisfy {
            $0 == expectedVariant
        })
        let phantomVariants = fixture.cellConfigurations.value.compactMap {
            configuration -> DownloadableMediaImageDecodeVariant? in
            guard case let .destinationPhantom(_, variant) = configuration else {
                return nil
            }
            return variant
        }
        XCTAssertTrue(phantomVariants.allSatisfy { $0 == expectedVariant })
    }

    func testCellConfigurationEncodesMaterializationInvariants() {
        let sourceConfiguration =
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
                .sourceOverscan(
                    imageDecodeVariant: .downsampled(maxPixelWidth: 160)
                )
        XCTAssertNil(sourceConfiguration.requiredImageQuality)
        XCTAssertEqual(sourceConfiguration.imageLoadPolicy, .cachedOnly)
        XCTAssertFalse(sourceConfiguration.allowsLocalLargeImageUpgrade)
        XCTAssertEqual(
            sourceConfiguration.imageDecodeVariant,
            .downsampled(maxPixelWidth: 160)
        )

        let destinationConfiguration =
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
                .destinationPhantom(
                    requiredImageQuality: .large,
                    imageDecodeVariant: .downsampled(maxPixelWidth: 288)
                )
        XCTAssertEqual(destinationConfiguration.requiredImageQuality, .large)
        XCTAssertEqual(destinationConfiguration.imageLoadPolicy, .cachedOnly)
        XCTAssertFalse(destinationConfiguration.allowsLocalLargeImageUpgrade)
        XCTAssertEqual(
            destinationConfiguration.imageDecodeVariant,
            .downsampled(maxPixelWidth: 288)
        )
    }

    func testPublishedImageSourcesReconfigureEveryActiveCellRole() throws {
        let itemCount = 30
        let fixture = try makeFixture(
            itemCount: itemCount,
            sourceColumnCount: 3,
            destinationColumnCount: 9,
            destinationMode: .nineColumns,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        let imageSourcesByToken = (0..<itemCount).map { tokenIndex in
            let thumbnailDescriptor =
                CollectionCatalogDownloadableMediaDescriptor(
                    collectionId: "collection",
                    tokenId: String(tokenIndex),
                    tokenIndex: tokenIndex,
                    media: .staticImage(
                        url: URL(fileURLWithPath:
                            "/thumbnail-\(tokenIndex).webp"),
                        fileExtension: "webp"
                    ),
                    purpose: .collectionBrowserThumbnail
                )
            let largeDescriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: "collection",
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(fileURLWithPath: "/large-\(tokenIndex).webp"),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserMid
            )
            return CollectionBrowseImageSources(
                smallestThumbnailDescriptor: thumbnailDescriptor,
                smallThumbnailDescriptor: thumbnailDescriptor,
                thumbnailDescriptor: thumbnailDescriptor,
                largeDescriptor: largeDescriptor
            )
        }
        let publishedTokenIndices = Box<Set<Int>>([])
        let configurations = Box<[
            ObjectIdentifier: [
                MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
            ]
        ]>([:])
        let configuredWithImageSources = Box<Set<ObjectIdentifier>>([])
        let detailLoadAttempts = Box<[
            CollectionCatalogDownloadableMediaDescriptor
        ]>([])
        let sourceVariant =
            MobilePlayerCollectionBrowserGridImageDecodeVariant.resolve(
                for: fixture.sourceLayout,
                displayScale: 3
            )
        let renderer = MobilePlayerCollectionBrowserGridRenderer(
            collectionView: fixture.collectionView,
            viewportView: fixture.viewportView,
            contentAccess: .init(
                configureCell: { cell, indexPath, configuration in
                    let cellID = ObjectIdentifier(cell)
                    configurations.value[cellID, default: []].append(
                        configuration
                    )
                    let publishedImageSources = publishedTokenIndices.value
                        .contains(indexPath.item)
                        ? imageSourcesByToken[indexPath.item]
                        : nil
                    if publishedImageSources != nil {
                        configuredWithImageSources.value.insert(cellID)
                    }
                    cell.configure(
                        contentIdentity: MobilePlayerBrowserContentIdentity(
                            collectionId: "collection",
                            tokenIndex: indexPath.item
                        ),
                        itemCount: itemCount,
                        imageSources: publishedImageSources,
                        requiredImageQuality:
                            configuration.requiredImageQuality ?? .thumbnail,
                        missingDescriptorFallbackSpec:
                            PlayerMediaPlaceholderSpec(
                                thumbnailAspectRatio: nil
                            ),
                        imageLoadPolicy: configuration.imageLoadPolicy,
                        fadesFirstImage: false,
                        allowsLocalLargeImageUpgrade:
                            configuration.allowsLocalLargeImageUpgrade,
                        imageDecodeVariant: configuration.imageDecodeVariant
                    )
                },
                contentIdentity: {
                    MobilePlayerBrowserContentIdentity(
                        collectionId: "collection",
                        tokenIndex: $0
                    )
                },
                imageSources: { tokenIndex in
                    return publishedTokenIndices.value.contains(tokenIndex)
                        ? imageSourcesByToken[tokenIndex]
                        : nil
                }
            ),
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { descriptor, _ in
                    detailLoadAttempts.value.append(descriptor)
                    return nil
                }
            ),
            clock: { 0 }
        )
        defer { _ = renderer.finish(preservingCarryover: false) }

        XCTAssertTrue(renderer.begin(
            gestureAnchor: nil,
            sourceLayout: fixture.sourceLayout,
            sourceImageDecodeVariant: sourceVariant,
            wasCollectionViewPrefetchingEnabled: true
        ))
        XCTAssertTrue(renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(renderer)
        guard case let .active(session) = renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let collectionSource = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        let sourceOverscanEntry = try XCTUnwrap(
            session.sourceOverscanCells.first
        )
        let destinationPhantomEntry = try XCTUnwrap(
            session.phantomCells.first
        )
        let sourceOverscan = sourceOverscanEntry.value
        let destinationPhantom = destinationPhantomEntry.value
        let collectionSourceID = ObjectIdentifier(collectionSource)
        let sourceOverscanID = ObjectIdentifier(sourceOverscan)
        let destinationPhantomID = ObjectIdentifier(destinationPhantom)
        let sourceOverscanConfiguration =
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
                .sourceOverscan(imageDecodeVariant: sourceVariant)
        let destinationPhantomConfiguration =
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
                .destinationPhantom(
                    requiredImageQuality:
                        fixture.planeRequest.toMode.requiredImageQuality,
                    imageDecodeVariant: fixture.planeRequest.imageDecodeVariant
                )

        XCTAssertEqual(
            configurations.value[sourceOverscanID]?.last,
            sourceOverscanConfiguration
        )
        XCTAssertEqual(
            configurations.value[destinationPhantomID]?.last,
            destinationPhantomConfiguration
        )
        let sourceOverscanConfigurationCount =
            configurations.value[sourceOverscanID]?.count
        let destinationPhantomConfigurationCount =
            configurations.value[destinationPhantomID]?.count
        XCTAssertFalse(
            configuredWithImageSources.value.contains(sourceOverscanID)
        )
        XCTAssertFalse(
            configuredWithImageSources.value.contains(destinationPhantomID)
        )
        let expectedWaiters = Dictionary(uniqueKeysWithValues:
            session.cachedSourceRepresentations.compactMap {
                representationID, representation -> (
                    ObjectIdentifier,
                    GridRenderTransitionImageSourcesWaiter
                )? in
                let sourceItem = representation.itemIndex
                guard session.selectedSourceItems.contains(sourceItem),
                      !session.lockedFallbackRepresentationIDs.contains(
                        representationID
                      ),
                      representation.cell.superview != nil,
                      representation.cell.represents(tokenIndex: sourceItem),
                      let destinationItem = session.reassignments[sourceItem]
                else {
                    return nil
                }
                return (
                    representationID,
                    GridRenderTransitionImageSourcesWaiter(
                        sourceItem: sourceItem,
                        destinationItem: destinationItem
                    )
                )
            }
        )
        XCTAssertFalse(expectedWaiters.isEmpty)
        XCTAssertEqual(session.transitionImageSourcesWaiters, expectedWaiters)
        XCTAssertTrue(detailLoadAttempts.value.isEmpty)
        XCTAssertEqual(renderer.pendingDetailMaterializationWorkCount, 0)

        let firstDestination = try XCTUnwrap(
            expectedWaiters.values
                .filter { $0.sourceItem != $0.destinationItem }
                .map(\.destinationItem).min()
        )
        let firstDestinationWaiters = expectedWaiters.filter {
            $0.value.destinationItem == firstDestination
        }
        let remainingWaiters = expectedWaiters.filter {
            $0.value.destinationItem != firstDestination
        }
        XCTAssertFalse(remainingWaiters.isEmpty)
        publishedTokenIndices.value.insert(firstDestination)
        XCTAssertTrue(renderer.reconcilePublishedImageSources())
        XCTAssertEqual(
            renderer.pendingDetailMaterializationRepresentationIDs,
            Set(firstDestinationWaiters.keys)
        )
        XCTAssertEqual(
            session.transitionImageSourcesWaiters,
            remainingWaiters
        )
        drainQueuedWork(renderer)
        let firstDescriptor = try XCTUnwrap(
            imageSourcesByToken[firstDestination].descriptor(
                for: fixture.planeRequest.toMode.requiredImageQuality
            )
        )
        XCTAssertEqual(
            detailLoadAttempts.value,
            Array(
                repeating: firstDescriptor,
                count: firstDestinationWaiters.count
            )
        )
        XCTAssertEqual(
            session.transitionImageSourcesWaiters,
            remainingWaiters
        )
        XCTAssertEqual(renderer.pendingDetailMaterializationWorkCount, 0)

        publishedTokenIndices.value = Set(0..<itemCount)
        XCTAssertTrue(renderer.reconcilePublishedImageSources())
        XCTAssertEqual(
            renderer.pendingDetailMaterializationRepresentationIDs,
            Set(remainingWaiters.keys)
        )
        drainQueuedWork(renderer)

        XCTAssertEqual(
            configurations.value[collectionSourceID]?.last,
            .collectionSource(
                allowsLocalLargeImageUpgrade:
                    MobileCollectionBrowserGridMode.threeColumns
                        .allowsLocalLargeImageUpgrade,
                imageDecodeVariant: sourceVariant
            )
        )
        XCTAssertEqual(
            configurations.value[sourceOverscanID]?.last,
            sourceOverscanConfiguration
        )
        XCTAssertEqual(
            configurations.value[destinationPhantomID]?.last,
            destinationPhantomConfiguration
        )
        XCTAssertEqual(
            configurations.value[sourceOverscanID]?.count,
            sourceOverscanConfigurationCount.map { $0 + 1 }
        )
        XCTAssertEqual(
            configurations.value[destinationPhantomID]?.count,
            destinationPhantomConfigurationCount.map { $0 + 1 }
        )
        XCTAssertTrue(configuredWithImageSources.value.isSuperset(of: [
            collectionSourceID,
            sourceOverscanID,
            destinationPhantomID,
        ]))
        let collectionSourceItem = try XCTUnwrap(
            fixture.collectionView.indexPath(for: collectionSource)?.item
        )
        XCTAssertTrue(collectionSource.hasImageSources(
            tokenIndex: collectionSourceItem
        ))
        XCTAssertTrue(sourceOverscan.hasImageSources(
            tokenIndex: sourceOverscanEntry.key
        ))
        XCTAssertTrue(destinationPhantom.hasImageSources(
            tokenIndex: destinationPhantomEntry.key
        ))
        XCTAssertEqual(
            detailLoadAttempts.value.count,
            expectedWaiters.count
        )
        XCTAssertEqual(
            Dictionary(grouping: detailLoadAttempts.value, by: \.tokenIndex)
                .mapValues(\.count),
            Dictionary(grouping: expectedWaiters.values, by: \.destinationItem)
                .mapValues(\.count)
        )
        XCTAssertTrue(session.transitionImageSourcesWaiters.isEmpty)
        XCTAssertTrue(session.transitionImageLoads.isEmpty)
        XCTAssertEqual(renderer.pendingDetailMaterializationWorkCount, 0)

        let configurationCounts = configurations.value.mapValues(\.count)
        let terminalLoadAttempts = detailLoadAttempts.value
        XCTAssertTrue(renderer.reconcilePublishedImageSources())

        XCTAssertEqual(
            configurations.value.mapValues(\.count),
            configurationCounts
        )
        XCTAssertEqual(renderer.pendingDetailMaterializationWorkCount, 0)
        XCTAssertEqual(detailLoadAttempts.value, terminalLoadAttempts)
    }

    func testPublishedImageSourcesReconciliationIsIdleNoOp() throws {
        let fixture = try makeFixture(providesContentAccess: true)

        XCTAssertFalse(fixture.renderer.reconcilePublishedImageSources())

        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertEqual(fixture.imageSourcesAccessCount.value, 0)
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
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

#if DEBUG
    func testPlaneReanchorReconcilesAnOtherwiseIdenticalFrame() throws {
        let fixture = try makeFixture()
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let scale: CGFloat = 0.8
        let settleProgress: CGFloat = 0.4
        let panDeltaY: CGFloat = 12

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: panDeltaY
        ))
        let reconciliationCount = fixture.renderer
            .phantomShapeMaskCommitAttemptCount
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: panDeltaY
        ))
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            reconciliationCount
        )

        fixture.renderer.reanchorSettlingRendering(
            at: CGPoint(x: 40, y: 120)
        )
        XCTAssertNil(try activeSession(fixture).lastPlaneFrameRevision)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: panDeltaY
        ))
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskCommitAttemptCount,
            reconciliationCount + 1
        )
    }
#endif

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
        XCTAssertFalse(fixture.renderer.reconcilePublishedImageSources())

        fixture.renderer.abortCommit(abortedPreparation)
        XCTAssertEqual(fixture.renderer.lifecycleName, .active)
        XCTAssertTrue(fixture.renderer.reconcilePublishedImageSources())
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

    func testTinyPositivePresentationInterruptsZeroProgressFade() throws {
        let fixture = try makeFixture(showsSourceCell: true)
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            presentationProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            presentationProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertTrue(session.contentFadeAnimationMayBeActive)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        sourceCell.layer.add(opacity, forKey: "opacity")

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            presentationProgress: 0.0009,
            panDeltaY: 0
        ))

        XCTAssertFalse(session.contentFadeAnimationMayBeActive)
        XCTAssertNil(sourceCell.layer.animation(forKey: "opacity"))
    }

    func testRenderRejectsUnsafeScaleAndPanValues() throws {
        let fixture = try makeFixture()
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        for (scale, panDeltaY) in [
            (CGFloat.nan, CGFloat.zero),
            (CGFloat.infinity, CGFloat.zero),
            (CGFloat.greatestFiniteMagnitude, CGFloat.zero),
            (CGFloat(1), CGFloat.nan),
            (CGFloat(1), CGFloat.infinity),
            (CGFloat(1), CGFloat.greatestFiniteMagnitude),
        ] {
            XCTAssertFalse(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: scale,
                settleProgress: 0,
                panDeltaY: panDeltaY
            ))
        }

        XCTAssertEqual(try activeSession(fixture).lastPanDeltaY, 0)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testZoomRejectsUnsafePanAndFiniteOverflowingScale() throws {
        let fixture = try makeFixture()
        begin(fixture)

        XCTAssertFalse(fixture.renderer.renderZoom(
            planeID: nil,
            scale: 1,
            panDeltaY: .nan,
            sourceLayout: fixture.sourceLayout
        ))
        XCTAssertFalse(fixture.renderer.renderZoom(
            planeID: nil,
            scale: .greatestFiniteMagnitude,
            panDeltaY: 0,
            sourceLayout: fixture.sourceLayout
        ))

        XCTAssertEqual(try activeSession(fixture).lastPanDeltaY, 0)
        _ = fixture.renderer.finish(preservingCarryover: false)
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

    private func drainQueuedWork(
        _ renderer: MobilePlayerCollectionBrowserGridRenderer
    ) {
        for _ in 0 ..< 100 {
            let result = renderer.drainMaterializationWork()
            if renderer.pendingMaterializationWorkCount == 0,
               result.processedCount == 0 {
                return
            }
        }
        XCTFail("Materialization work did not drain")
    }
}
