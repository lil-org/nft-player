// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
func runMainTrackingRunLoop(
    until condition: () -> Bool,
    timeout: TimeInterval = 0.25
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), deadline.timeIntervalSinceNow > 0 {
        _ = RunLoop.main.run(mode: .tracking, before: deadline)
    }
    return condition()
}

nonisolated final class MobilePlayerCollectionBrowserGridRendererTests: XCTestCase {}

@MainActor
extension MobilePlayerCollectionBrowserGridRendererTests {
    typealias PromotionKey =
        MobilePlayerCollectionBrowserGridRenderer.PromotionRepresentationKey

    final class Counter {
        var value = 0
    }

    final class Box<Value> {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    final class SourceDataSource: NSObject, UICollectionViewDataSource {
        let itemCount: Int

        init(itemCount: Int) {
            self.itemCount = itemCount
        }

        func collectionView(
            _: UICollectionView,
            numberOfItemsInSection _: Int
        ) -> Int {
            itemCount
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "source",
                for: indexPath
            ) as! MobilePlayerCollectionBrowserCell
            cell.configure(
                contentIdentity: MobilePlayerBrowserContentIdentity(
                    collectionId: "collection",
                    tokenIndex: indexPath.item
                ),
                itemCount: itemCount,
                imageSources: nil,
                requiredImageQuality: .thumbnail,
                missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                    thumbnailAspectRatio: nil
                ),
                imageLoadPolicy: .disabled
            )
            return cell
        }
    }

    func makeCollectionViewLayout(
        browserLayout: MobilePlayerBrowserLayout
    ) -> MobilePlayerCollectionBrowserLayout {
        let layout = MobilePlayerCollectionBrowserLayout()
        layout.browserLayout = browserLayout
        return layout
    }

    struct Fixture {
        let containerView: UIView
        let collectionView: MobilePlayerCollectionBrowserCollectionView
        let viewportView: UIView
        let sourceLayout: MobilePlayerBrowserLayout
        let destinationLayout: MobilePlayerBrowserLayout
        let planeRequest: GridModePlaneRequest
        let configureCount: Counter
        let cellConfigurations: Box<[
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
        ]>
        let contentIdentityAccessCount: Counter
        let imageSourcesAccessCount: Counter
        let renderer: MobilePlayerCollectionBrowserGridRenderer
        let sourceDataSource: SourceDataSource?
    }

    func makeImageSources() -> CollectionBrowseImageSources {
        let descriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "0",
            tokenIndex: 0,
            media: .staticImage(
                url: URL(fileURLWithPath: "/thumbnail.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
        return CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
    }

    func makeDistinctImageSources() -> CollectionBrowseImageSources {
        let thumbnailDescriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "0",
            tokenIndex: 0,
            media: .staticImage(
                url: URL(fileURLWithPath: "/thumbnail.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
        let largeDescriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "0",
            tokenIndex: 0,
            media: .staticImage(
                url: URL(fileURLWithPath: "/large.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserMid
        )
        return CollectionBrowseImageSources(
            thumbnailDescriptor: thumbnailDescriptor,
            largeDescriptor: largeDescriptor
        )
    }

    func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    func transitionContentContainer(
        in cell: MobilePlayerCollectionBrowserCell
    ) -> UIView? {
        cell.contentView.subviews.first { subview in
            subview.subviews.contains {
                $0 is NativeMetalCardCornerMaskedImageView
            }
        }
    }

    func primaryTransitionImage(
        in cell: MobilePlayerCollectionBrowserCell
    ) -> UIImage? {
        transitionContentContainer(in: cell)?.subviews.compactMap {
            ($0 as? NativeMetalCardCornerMaskedImageView)?.image
        }.first
    }

    struct PhantomShapeLayers {
        let repeatedRows: CAReplicatorLayer
        let repeatedRow: CAShapeLayer
        let finalRow: CAShapeLayer
        let solidCoverage: CAShapeLayer
        let candidates: CAShapeLayer
    }

    func phantomShapeLayers(
        in view: UIView
    ) throws -> PhantomShapeLayers {
        let layers = try XCTUnwrap(view.layer.sublayers)
        XCTAssertEqual(layers.count, 4)
        let repeatedRows = try XCTUnwrap(layers[0] as? CAReplicatorLayer)
        return PhantomShapeLayers(
            repeatedRows: repeatedRows,
            repeatedRow: try XCTUnwrap(
                repeatedRows.sublayers?.first as? CAShapeLayer
            ),
            finalRow: try XCTUnwrap(layers[1] as? CAShapeLayer),
            solidCoverage: try XCTUnwrap(layers[2] as? CAShapeLayer),
            candidates: try XCTUnwrap(layers[3] as? CAShapeLayer)
        )
    }

    func phantomShapeMaskContains(
        _ point: CGPoint,
        in shapeView: UIView
    ) throws -> Bool {
        let localPoint = CGPoint(
            x: point.x - shapeView.frame.minX,
            y: point.y - shapeView.frame.minY
        )
        var mask = try XCTUnwrap(shapeView.layer.mask as? CAShapeLayer)
        while true {
            let path = try XCTUnwrap(mask.path)
            if !path.contains(localPoint, using: .evenOdd) {
                return false
            }
            guard let nestedMask = mask.mask as? CAShapeLayer else {
                return true
            }
            mask = nestedMask
        }
    }

    func assertNoAnimations(
        in layer: CALayer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            layer.animationKeys()?.isEmpty != false,
            file: file,
            line: line
        )
        for sublayer in layer.sublayers ?? [] {
            assertNoAnimations(in: sublayer, file: file, line: line)
        }
        if let mask = layer.mask {
            assertNoAnimations(in: mask, file: file, line: line)
        }
    }

    func onePixelAccuracy(in view: UIView) -> CGFloat {
        let scale = view.window?.screen.scale
            ?? view.traitCollection.displayScale
        return 1 / max(scale, 1)
    }

    func makeFixture(
        itemCount: Int = 300,
        sourceColumnCount: Int = 3,
        destinationColumnCount: Int = 5,
        destinationMode: MobileCollectionBrowserGridMode = .fiveColumns,
        showsSourceCell: Bool = false,
        showsSourceGrid: Bool = false,
        providesContentAccess: Bool = false,
        installsSyntheticContent: Bool = false,
        anchorItemIndex: Int? = nil,
        viewportOrigin: CGPoint = .zero,
        uniformImageSize: CGSize = CGSize(width: 1, height: 1),
        heightToWidthRatios: [CGFloat]? = nil,
        sourceContentOffsetY: CGFloat? = nil,
        contentImageSources: CollectionBrowseImageSources? = nil,
        imageAccess: MobilePlayerCollectionBrowserGridRenderer.ImageAccess?
            = nil,
        imageDecodeVariant: DownloadableMediaImageDecodeVariant? = nil,
        clock: @escaping () -> CFTimeInterval = { 0 }
    ) throws -> Fixture {
        precondition(!showsSourceCell || !showsSourceGrid)
        let viewportSize = CGSize(width: 320, height: 640)
        let sourceProfile: MobilePlayerBrowserAspectProfile
        let destinationProfile: MobilePlayerBrowserAspectProfile
        if let heightToWidthRatios {
            precondition(heightToWidthRatios.count == itemCount)
            sourceProfile = MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: heightToWidthRatios,
                columnCount: sourceColumnCount
            )
            destinationProfile = MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: heightToWidthRatios,
                columnCount: destinationColumnCount
            )
        } else {
            sourceProfile = MobilePlayerBrowserAspectProfile(
                itemCount: itemCount,
                uniformImageSize: uniformImageSize,
                columnCount: sourceColumnCount
            )
            destinationProfile = MobilePlayerBrowserAspectProfile(
                itemCount: itemCount,
                uniformImageSize: uniformImageSize,
                columnCount: destinationColumnCount
            )
        }
        let sourceLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            aspectProfile: sourceProfile
        ))
        let destinationLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            aspectProfile: destinationProfile
        ))
        let transition = try XCTUnwrap(MobilePlayerBrowserGridTransition(
            fromLayout: sourceLayout,
            toLayout: destinationLayout
        ))
        let anchorItem = min(
            max(anchorItemIndex ?? itemCount / 2, 0),
            max(itemCount - 1, 0)
        )
        let sourceFrame = try XCTUnwrap(sourceLayout.itemFrame(at: anchorItem))
        let destinationFrame = try XCTUnwrap(
            destinationLayout.itemFrame(at: anchorItem)
        )
        let sourceAnchor = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let destinationAnchor = CGPoint(
            x: destinationFrame.midX,
            y: destinationFrame.midY
        )
        let viewportCenter = CGPoint(
            x: viewportSize.width / 2,
            y: viewportSize.height / 2
        )
        let outgoingContentOffsetY = sourceContentOffsetY ?? 0
        let outgoingAnchor: CGPoint
        let incomingAnchor: CGPoint
        let incomingContentOffsetY: CGFloat
        if sourceContentOffsetY != nil {
            outgoingAnchor = CGPoint(
                x: sourceAnchor.x,
                y: sourceAnchor.y - outgoingContentOffsetY
            )
            incomingContentOffsetY = MobilePlayerBrowserGridTransition
                .clampedContentOffsetY(
                    destinationAnchor.y - outgoingAnchor.y,
                    contentHeight: destinationLayout.contentSize.height,
                    viewportHeight: viewportSize.height
                )
            incomingAnchor = CGPoint(
                x: destinationAnchor.x,
                y: destinationAnchor.y - incomingContentOffsetY
            )
        } else {
            outgoingAnchor = viewportCenter
            incomingAnchor = viewportCenter
            incomingContentOffsetY = 0
        }
        let crossfade = try XCTUnwrap(PlayerBrowserGridCrossfade(
            itemWidthRatio: transition.itemWidthRatio,
            terminalScaleX: transition.columnPitchRatio,
            terminalScaleY: transition.rowPitchRatio,
            outgoingAnchor: outgoingAnchor,
            incomingAnchor: incomingAnchor,
            outgoingContentOffsetY: outgoingContentOffsetY,
            incomingContentOffsetY: incomingContentOffsetY,
            outgoingContentHeight: sourceLayout.contentSize.height,
            incomingContentHeight: destinationLayout.contentSize.height,
            viewportSize: viewportSize
        ))
        let request = GridModePlaneRequest(
            id: UUID(),
            toMode: destinationMode,
            layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState(
                aspectProfile: destinationProfile,
                fallbackSpec: PlayerMediaPlaceholderSpec(
                    aspectSize: CGSize(width: 1, height: 1)
                )
            ),
            anchorTokenIndex: anchorItem,
            transitionLayout: transition,
            crossfade: crossfade,
            latticeMap: transition.latticeMap(
                fromAnchorContentPoint: sourceAnchor,
                toAnchorContentPoint: destinationAnchor
            ),
            imageDecodeVariant: imageDecodeVariant
                ?? MobilePlayerCollectionBrowserGridImageDecodeVariant.resolve(
                    for: destinationLayout,
                    displayScale: 3
                )
        )
        let collectionLayout: UICollectionViewLayout
        if showsSourceGrid {
            if let itemSize = sourceLayout.uniformItemSize {
                let flowLayout = UICollectionViewFlowLayout()
                flowLayout.itemSize = itemSize
                flowLayout.minimumLineSpacing = sourceLayout.interItemSpacing
                flowLayout.minimumInteritemSpacing =
                    sourceLayout.interItemSpacing
                flowLayout.sectionInset.top = try XCTUnwrap(
                    sourceLayout.itemFrame(at: 0)
                ).minY
                collectionLayout = flowLayout
            } else {
                collectionLayout = makeCollectionViewLayout(
                    browserLayout: sourceLayout
                )
            }
        } else if showsSourceCell {
            let flowLayout = UICollectionViewFlowLayout()
            flowLayout.itemSize = viewportSize
            flowLayout.minimumLineSpacing = 0
            flowLayout.minimumInteritemSpacing = 0
            collectionLayout = flowLayout
        } else {
            collectionLayout = UICollectionViewFlowLayout()
        }
        let collectionView = MobilePlayerCollectionBrowserCollectionView(
            frame: CGRect(origin: .zero, size: viewportSize),
            collectionViewLayout: collectionLayout
        )
        let viewportView = UIView(frame: CGRect(
            origin: viewportOrigin,
            size: viewportSize
        ))
        let containerView = UIView(frame: CGRect(
            origin: .zero,
            size: CGSize(
                width: viewportSize.width + viewportOrigin.x,
                height: viewportSize.height + viewportOrigin.y
            )
        ))
        containerView.addSubview(viewportView)
        viewportView.addSubview(collectionView)
        var sourceDataSource: SourceDataSource?
        if showsSourceCell || showsSourceGrid {
            collectionView.register(
                MobilePlayerCollectionBrowserCell.self,
                forCellWithReuseIdentifier: "source"
            )
            let dataSource = SourceDataSource(itemCount: itemCount)
            collectionView.dataSource = dataSource
            sourceDataSource = dataSource
            collectionView.reloadData()
            if let sourceContentOffsetY {
                collectionView.contentOffset.y = sourceContentOffsetY
            }
            collectionView.layoutIfNeeded()
        }
        let configureCount = Counter()
        let cellConfigurations = Box<[
            MobilePlayerCollectionBrowserGridRenderer.CellConfiguration
        ]>([])
        let contentIdentityAccessCount = Counter()
        let imageSourcesAccessCount = Counter()
        let imageSources = contentImageSources ?? makeImageSources()
        let syntheticImage = makeImage()
        let imageAccess = imageAccess ?? .init(
            cachedImage: { _, _ in nil },
            loadImage: { _, _ in {} }
        )
        let renderer = MobilePlayerCollectionBrowserGridRenderer(
            collectionView: collectionView,
            viewportView: viewportView,
            contentAccess: .init(
                configureCell: {
                    cell, indexPath, configuration in
                    configureCount.value += 1
                    cellConfigurations.value.append(configuration)
                    let identity = MobilePlayerBrowserContentIdentity(
                        collectionId: "collection",
                        tokenIndex: indexPath.item
                    )
                    cell.configure(
                        contentIdentity: identity,
                        itemCount: itemCount,
                        imageSources: nil,
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
                    guard installsSyntheticContent else { return }
                    cell.installTransitionContent(
                        image: syntheticImage,
                        descriptor: imageSources.thumbnailDescriptor,
                        usesNativeMetalCardCornerMask: false,
                        targetAlpha: 1,
                        animated: false,
                        identity: identity
                    )
                },
                contentIdentity: { itemIndex in
                    contentIdentityAccessCount.value += 1
                    return providesContentAccess
                        ? MobilePlayerBrowserContentIdentity(
                            collectionId: "collection",
                            tokenIndex: itemIndex
                        )
                        : nil
                },
                imageSources: { _ in
                    imageSourcesAccessCount.value += 1
                    return providesContentAccess ? imageSources : nil
                }
            ),
            imageAccess: imageAccess,
            clock: clock
        )
        return Fixture(
            containerView: containerView,
            collectionView: collectionView,
            viewportView: viewportView,
            sourceLayout: sourceLayout,
            destinationLayout: destinationLayout,
            planeRequest: request,
            configureCount: configureCount,
            cellConfigurations: cellConfigurations,
            contentIdentityAccessCount: contentIdentityAccessCount,
            imageSourcesAccessCount: imageSourcesAccessCount,
            renderer: renderer,
            sourceDataSource: sourceDataSource
        )
    }

    func begin(
        _ fixture: Fixture,
        gestureAnchor: GridModeGestureAnchor? = nil
    ) {
        XCTAssertTrue(fixture.renderer.begin(
            gestureAnchor: gestureAnchor,
            sourceLayout: fixture.sourceLayout,
            sourceImageDecodeVariant:
                MobilePlayerCollectionBrowserGridImageDecodeVariant.resolve(
                    for: fixture.sourceLayout,
                    displayScale: 3
                ),
            wasCollectionViewPrefetchingEnabled: true
        ))
    }

    func activeSession(
        _ fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> MobilePlayerCollectionBrowserGridRenderer.Session {
        let session: MobilePlayerCollectionBrowserGridRenderer.Session?
        if case let .active(activeSession) = fixture.renderer.lifecycle {
            session = activeSession
        } else {
            session = nil
        }
        return try XCTUnwrap(
            session,
            "Expected an active renderer session",
            file: file,
            line: line
        )
    }

    func assertSourceRepresentationIndexesConsistent(
        _ session: GridRenderSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let store = session.sourceRepresentations
        let records = store.records
        func ids(
            where predicate: (GridSourceRepresentationStore.Record) -> Bool
        ) -> Set<ObjectIdentifier> {
            Set(records.compactMap { predicate($0.value) ? $0.key : nil })
        }

        XCTAssertTrue(records.allSatisfy {
            $0.key == ObjectIdentifier($0.value.cell)
        }, file: file, line: line)
        XCTAssertEqual(
            store.preparedRepresentationIDs,
            ids(where: \.isPrepared),
            file: file, line: line
        )
        XCTAssertEqual(
            store.lockedFallbackRepresentationIDs,
            ids(where: \.isFallbackLocked),
            file: file, line: line
        )
        XCTAssertEqual(
            store.unpreparedMarginTrackingRepresentationIDs,
            ids(where: \.tracksUnpreparedMargin),
            file: file, line: line
        )
        XCTAssertEqual(
            store.deferredClassificationPaintRepresentationIDs,
            ids(where: \.needsClassificationPaint),
            file: file, line: line
        )
        XCTAssertEqual(
            store.marginCoverageRepresentationIDs,
            ids { $0.geometry == .marginHeld },
            file: file, line: line
        )
        XCTAssertEqual(
            store.foregroundEligibleRepresentationIDs,
            ids { $0.foregroundEligibility != .none },
            file: file, line: line
        )
        XCTAssertEqual(
            store.currentViewportRepresentationIDs,
            ids { $0.foregroundEligibility == .current },
            file: file, line: line
        )
        XCTAssertEqual(
            store.detailedSourceCellItems,
            records.compactMapValues(\.detailedSourceItem),
            file: file, line: line
        )
        XCTAssertEqual(
            store.transitionImageSourcesWaiters,
            records.compactMapValues(\.imageWork.waiter),
            file: file, line: line
        )
        XCTAssertEqual(
            store.transitionImageLoads.mapValues(\.id),
            records.compactMapValues(\.imageWork.load?.id),
            file: file, line: line
        )
        XCTAssertEqual(
            store.cellFrameCorrections.mapValues(\.correction),
            records.compactMapValues(\.geometry.correction),
            file: file, line: line
        )
        XCTAssertTrue(store.cellFrameCorrections.allSatisfy {
            records[$0.key]?.cell === $0.value.cell
        }, file: file, line: line)
    }

    func drainQueuedWork(_ fixture: Fixture) {
        for _ in 0 ..< 100 {
            let result = fixture.renderer.drainMaterializationWork()
            if fixture.renderer.pendingMaterializationWorkCount == 0,
               result.processedCount == 0 {
                return
            }
        }
        XCTFail("Materialization work did not drain")
    }

    struct ForegroundEligibilityContext {
        let currentViewportRect: CGRect
        let terminalViewportRect: CGRect
    }

    func foregroundEligibilityContext(
        fixture: Fixture,
        panDeltaY: CGFloat,
        session: MobilePlayerCollectionBrowserGridRenderer.Session? = nil
    ) -> ForegroundEligibilityContext {
        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            panDeltaY: panDeltaY
        )
        let currentViewportRect = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        )
        let terminalViewportRect = CGRect(
            x: 0,
            y: terminalPlane.incomingContentOffsetY,
            width: fixture.viewportView.bounds.width,
            height: fixture.viewportView.bounds.height
        )
        return ForegroundEligibilityContext(
            currentViewportRect: session?.foregroundCurrentViewportCoverage
                .installedRect ?? currentViewportRect,
            terminalViewportRect: session?.foregroundTerminalViewportCoverage
                .installedRect ?? terminalViewportRect
        )
    }

    func isForegroundEligible(
        cell: MobilePlayerCollectionBrowserCell,
        destinationItem: Int,
        fixture: Fixture,
        context: ForegroundEligibilityContext
    ) -> Bool {
        guard let destinationFrame = fixture.destinationLayout.itemFrame(
            at: destinationItem
        ) else {
            return false
        }
        let currentFrame = cell.convert(
            cell.bounds,
            to: fixture.collectionView
        )
        let isCurrent = PlayerBrowserGridGeometry.visibleRect(
            currentFrame,
            clippedTo: context.currentViewportRect
        ) != nil
        let isTerminal = PlayerBrowserGridGeometry.visibleRect(
            destinationFrame,
            clippedTo: context.terminalViewportRect
        ) != nil
        return isCurrent || isTerminal
    }

    func foregroundEligibleRepresentationIDs(
        fixture: Fixture,
        session: MobilePlayerCollectionBrowserGridRenderer.Session,
        panDeltaY: CGFloat,
        usesBufferedCoverage: Bool = true
    ) -> Set<ObjectIdentifier> {
        let context = foregroundEligibilityContext(
            fixture: fixture,
            panDeltaY: panDeltaY,
            session: usesBufferedCoverage ? session : nil
        )
        return Set(session.sourceRepresentations.records.compactMap {
            representationID, representation -> ObjectIdentifier? in
            guard session.selectedSourceItems.contains(
                representation.itemIndex
            ),
            !session.sourceRepresentations.lockedFallbackRepresentationIDs.contains(
                representationID
            ),
            representation.cell.represents(
                tokenIndex: representation.itemIndex
            ),
            let destinationItem = session.reassignments[
                representation.itemIndex
            ] else {
                return nil
            }
            return isForegroundEligible(
                cell: representation.cell,
                destinationItem: destinationItem,
                fixture: fixture,
                context: context
            ) ? representationID : nil
        })
    }

    func reenterPreparedRepresentation(
        fixture: Fixture,
        panDistanceInViewports: CGFloat = 1,
        afterInitialMaterialization: () -> Void
    ) throws -> (
        session: MobilePlayerCollectionBrowserGridRenderer.Session,
        representationID: ObjectIdentifier,
        cell: MobilePlayerCollectionBrowserCell
    ) {
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try XCTUnwrap({
            if case let .active(session) = fixture.renderer.lifecycle {
                return session
            }
            return nil
        }())
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
        afterInitialMaterialization()

        let shiftedPanDeltaY = -fixture.viewportView.bounds.height
            * panDistanceInViewports
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: shiftedPanDeltaY
        ))
        drainQueuedWork(fixture)
        let shiftedEligibleIDs = foregroundEligibleRepresentationIDs(
            fixture: fixture,
            session: session,
            panDeltaY: shiftedPanDeltaY
        )
        let departingEligibleIDs = firstEligibleIDs.subtracting(
            shiftedEligibleIDs
        )
        let representationID = try XCTUnwrap(
            departingEligibleIDs.first {
                session.sourceRepresentations.records[$0] != nil
                    && session.sourceRepresentations.preparedRepresentationIDs.contains($0)
            }
        )
        XCTAssertTrue(
            session.sourceRepresentations.preparedRepresentationIDs.contains(representationID)
        )

        let imageSourcesAccessCountBeforeReentry =
            fixture.imageSourcesAccessCount.value
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.sourceRepresentations.foregroundEligibleRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            fixture.renderer
                .pendingDetailMaterializationRepresentationIDs
                .contains(representationID)
        )
        drainQueuedWork(fixture)
        XCTAssertTrue(foregroundEligibleRepresentationIDs(
            fixture: fixture,
            session: session,
            panDeltaY: 0
        ).contains(representationID))
        XCTAssertGreaterThan(
            fixture.imageSourcesAccessCount.value,
            imageSourcesAccessCountBeforeReentry
        )
        let cell = try XCTUnwrap(
            session.sourceRepresentations.records[representationID]?.cell
        )
        return (session, representationID, cell)
    }

    func foregroundEligiblePhantomItems(
        fixture: Fixture,
        session: MobilePlayerCollectionBrowserGridRenderer.Session,
        panDeltaY: CGFloat
    ) -> Set<Int> {
        let context = foregroundEligibilityContext(
            fixture: fixture,
            panDeltaY: panDeltaY,
            session: session
        )
        return Set(session.phantomCells.compactMap {
            destinationItem, cell -> Int? in
            isForegroundEligible(
                cell: cell,
                destinationItem: destinationItem,
                fixture: fixture,
                context: context
            ) ? destinationItem : nil
        })
    }

    func phantomPromotionKeys(
        session: MobilePlayerCollectionBrowserGridRenderer.Session
    ) -> Set<PromotionKey> {
        Set(session.phantomCells.map { tokenIndex, cell in
            PromotionKey(
                representationID: ObjectIdentifier(cell),
                tokenIndex: tokenIndex
            )
        })
    }

    @MainActor
    final class MainRunLoopAction {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func call() {
            action()
        }
    }

    func runOnNextMainQueueTurn(
        _ action: @escaping () -> Void = {}
    ) async {
        await Task.yield()
        let runLoopAction = MainRunLoopAction(action: action)
        await withCheckedContinuation { continuation in
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    runLoopAction.call()
                    continuation.resume()
                }
            }
        }
    }

    func requestWithFailedMapping(
        fixture: Fixture
    ) throws -> GridModePlaneRequest {
        let sourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 0)
        )
        let destinationFrame = try XCTUnwrap(
            fixture.planeRequest.transitionLayout.toLayout.itemFrame(at: 0)
        )
        return GridModePlaneRequest(
            id: UUID(),
            toMode: fixture.planeRequest.toMode,
            layoutAspectState: fixture.planeRequest.layoutAspectState,
            anchorTokenIndex: 0,
            transitionLayout: fixture.planeRequest.transitionLayout,
            crossfade: fixture.planeRequest.crossfade,
            latticeMap: MobilePlayerBrowserGridLatticeMap(
                columnPitchRatio: 100,
                rowPitchRatio: 1,
                fromAnchorContentPoint: CGPoint(
                    x: sourceFrame.midX,
                    y: sourceFrame.midY
                ),
                toAnchorContentPoint: CGPoint(
                    x: destinationFrame.midX + 400,
                    y: destinationFrame.midY
                )
            ),
            imageDecodeVariant: fixture.planeRequest.imageDecodeVariant
        )
    }

    func replacementRequest(
        for request: GridModePlaneRequest
    ) -> GridModePlaneRequest {
        GridModePlaneRequest(
            id: UUID(),
            toMode: request.toMode,
            layoutAspectState: request.layoutAspectState,
            anchorTokenIndex: request.anchorTokenIndex,
            transitionLayout: request.transitionLayout,
            crossfade: request.crossfade,
            latticeMap: request.latticeMap,
            imageDecodeVariant: request.imageDecodeVariant
        )
    }

    func frameCorrection(
        viewportOrigin: CGPoint
    ) throws -> MobilePlayerCollectionBrowserGridRenderer
        .GridModeCellFrameCorrection {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            viewportOrigin: viewportOrigin,
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
        defer {
            _ = fixture.renderer.finish(preservingCarryover: false)
        }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        var activeSession: MobilePlayerCollectionBrowserGridRenderer.Session?
        if case let .active(session) = fixture.renderer.lifecycle {
            activeSession = session
        }
        let session = try XCTUnwrap(
            activeSession,
            "Expected an active renderer session"
        )
        return try XCTUnwrap(
            session.sourceRepresentations.cellFrameCorrections[ObjectIdentifier(sourceCell)]?
                .correction
        )
    }

    func assertTransform(
        _ lhs: CGAffineTransform,
        equals rhs: CGAffineTransform,
        accuracy: CGFloat = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.a, rhs.a, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.b, rhs.b, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.c, rhs.c, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.d, rhs.d, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.tx, rhs.tx, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.ty, rhs.ty, accuracy: accuracy, file: file, line: line)
    }

    func horizontallyAdjacentCorrectedCells(
        fixture: Fixture,
        session: MobilePlayerCollectionBrowserGridRenderer.Session
    ) -> (
        leftItem: Int,
        left: MobilePlayerCollectionBrowserCell,
        rightItem: Int,
        right: MobilePlayerCollectionBrowserCell
    )? {
        let representations = session.sourceRepresentations.records.compactMap {
            representationID, representation in
            session.sourceRepresentations.cellFrameCorrections[representationID] == nil
                ? nil
                : representation
        }
        for left in representations {
            guard let leftFrame = fixture.sourceLayout.itemFrame(
                at: left.itemIndex
            ) else {
                continue
            }
            for right in representations where
                right.itemIndex != left.itemIndex {
                guard let rightFrame = fixture.sourceLayout.itemFrame(
                    at: right.itemIndex
                ),
                abs(leftFrame.midY - rightFrame.midY) < 0.001,
                abs(
                    rightFrame.minX - leftFrame.maxX
                        - fixture.sourceLayout.interItemSpacing
                ) < 0.001 else {
                    continue
                }
                return (
                    left.itemIndex,
                    left.cell,
                    right.itemIndex,
                    right.cell
                )
            }
        }
        return nil
    }

    func horizontalScreenGap(
        left: UICollectionViewCell,
        right: UICollectionViewCell,
        in viewportView: UIView
    ) -> CGFloat {
        let leftFrame = left.convert(left.bounds, to: viewportView)
        let rightFrame = right.convert(right.bounds, to: viewportView)
        return rightFrame.minX - leftFrame.maxX
    }
}
