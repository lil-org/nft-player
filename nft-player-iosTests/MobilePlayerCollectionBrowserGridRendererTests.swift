// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
final class MobilePlayerCollectionBrowserGridRendererTests: XCTestCase {
    private typealias PromotionKey =
        MobilePlayerCollectionBrowserGridRenderer.PromotionRepresentationKey

    private final class Counter {
        var value = 0
    }

    private final class Box<Value> {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private final class SourceDataSource: NSObject, UICollectionViewDataSource {
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

    private struct Fixture {
        let containerView: UIView
        let collectionView: MobilePlayerCollectionBrowserCollectionView
        let viewportView: UIView
        let sourceLayout: MobilePlayerBrowserLayout
        let destinationLayout: MobilePlayerBrowserLayout
        let planeRequest: GridModePlaneRequest
        let configureCount: Counter
        let contentIdentityAccessCount: Counter
        let imageSourcesAccessCount: Counter
        let renderer: MobilePlayerCollectionBrowserGridRenderer
        let sourceDataSource: SourceDataSource?
    }

    private func makeImageSources() -> CollectionBrowseImageSources {
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

    private func makeDistinctImageSources() -> CollectionBrowseImageSources {
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

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func transitionContentContainer(
        in cell: MobilePlayerCollectionBrowserCell
    ) -> UIView? {
        cell.contentView.subviews.first { subview in
            subview.subviews.contains {
                $0 is NativeMetalCardCornerMaskedImageView
            }
        }
    }

    private func primaryTransitionImage(
        in cell: MobilePlayerCollectionBrowserCell
    ) -> UIImage? {
        transitionContentContainer(in: cell)?.subviews.compactMap {
            ($0 as? NativeMetalCardCornerMaskedImageView)?.image
        }.first
    }

    private struct PhantomShapeLayers {
        let repeatedRows: CAReplicatorLayer
        let repeatedRow: CAShapeLayer
        let finalRow: CAShapeLayer
        let solidCoverage: CAShapeLayer
        let candidates: CAShapeLayer
    }

    private func phantomShapeLayers(
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

    private func assertNoAnimations(
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

    func testVisualGeometryUsesEffectiveLayoutDirection() throws {
        let fixture = try makeFixture(itemCount: 6)
        fixture.collectionView.semanticContentAttribute = .forceRightToLeft

        let rightToLeftGeometry = fixture.collectionView.visualGeometry(
            for: fixture.sourceLayout
        )

        XCTAssertTrue(rightToLeftGeometry.mirrorsHorizontally)
        fixture.collectionView.semanticContentAttribute = .forceLeftToRight
        let leftToRightGeometry = fixture.collectionView.visualGeometry(
            for: fixture.sourceLayout
        )
        XCTAssertFalse(leftToRightGeometry.mirrorsHorizontally)
    }

    private func makeFixture(
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
        contentImageSources: CollectionBrowseImageSources? = nil,
        imageAccess: MobilePlayerCollectionBrowserGridRenderer.ImageAccess?
            = nil,
        clock: @escaping () -> CFTimeInterval = { 0 }
    ) throws -> Fixture {
        precondition(!showsSourceCell || !showsSourceGrid)
        let viewportSize = CGSize(width: 320, height: 640)
        let sourceProfile = MobilePlayerBrowserAspectProfile(
            itemCount: itemCount,
            uniformImageSize: uniformImageSize,
            columnCount: sourceColumnCount
        )
        let destinationProfile = MobilePlayerBrowserAspectProfile(
            itemCount: itemCount,
            uniformImageSize: uniformImageSize,
            columnCount: destinationColumnCount
        )
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
        let viewportAnchor = CGPoint(
            x: viewportSize.width / 2,
            y: viewportSize.height / 2
        )
        let crossfade = try XCTUnwrap(PlayerBrowserGridCrossfade(
            itemWidthRatio: transition.itemWidthRatio,
            terminalScaleX: transition.columnPitchRatio,
            terminalScaleY: transition.rowPitchRatio,
            outgoingAnchor: viewportAnchor,
            incomingAnchor: viewportAnchor,
            outgoingContentOffsetY: 0,
            incomingContentOffsetY: 0,
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
            )
        )
        let collectionLayout = UICollectionViewFlowLayout()
        if showsSourceGrid {
            collectionLayout.itemSize = try XCTUnwrap(
                sourceLayout.uniformItemSize
            )
            collectionLayout.minimumLineSpacing =
                sourceLayout.interItemSpacing
            collectionLayout.minimumInteritemSpacing =
                sourceLayout.interItemSpacing
            collectionLayout.sectionInset.top = try XCTUnwrap(
                sourceLayout.itemFrame(at: 0)
            ).minY
        } else if showsSourceCell {
            collectionLayout.itemSize = viewportSize
            collectionLayout.minimumLineSpacing = 0
            collectionLayout.minimumInteritemSpacing = 0
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
            collectionView.layoutIfNeeded()
        }
        let configureCount = Counter()
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
                            configuration.allowsLocalLargeImageUpgrade
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
            contentIdentityAccessCount: contentIdentityAccessCount,
            imageSourcesAccessCount: imageSourcesAccessCount,
            renderer: renderer,
            sourceDataSource: sourceDataSource
        )
    }

    private func begin(
        _ fixture: Fixture,
        gestureAnchor: GridModeGestureAnchor? = nil
    ) {
        XCTAssertTrue(fixture.renderer.begin(
            gestureAnchor: gestureAnchor,
            sourceLayout: fixture.sourceLayout,
            wasCollectionViewPrefetchingEnabled: true
        ))
    }

    private func drainQueuedWork(_ fixture: Fixture) {
        for _ in 0 ..< 100 {
            let result = fixture.renderer.drainMaterializationWork()
            if fixture.renderer.pendingMaterializationWorkCount == 0,
               result.processedCount == 0 {
                return
            }
        }
        XCTFail("Materialization work did not drain")
    }

    private struct ForegroundEligibilityContext {
        let currentViewportRect: CGRect
        let terminalViewportRect: CGRect
    }

    private func foregroundEligibilityContext(
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

    private func isForegroundEligible(
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

    private func foregroundEligibleRepresentationIDs(
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
        return Set(session.cachedSourceRepresentations.compactMap {
            representationID, representation -> ObjectIdentifier? in
            guard session.selectedSourceItems.contains(
                representation.itemIndex
            ),
            !session.lockedFallbackRepresentationIDs.contains(
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

    private func reenterPreparedRepresentation(
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
                session.cachedSourceRepresentations[$0] != nil
                    && session.preparedRepresentationIDs.contains($0)
            }
        )
        XCTAssertTrue(
            session.preparedRepresentationIDs.contains(representationID)
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
            session.foregroundEligibleRepresentationIDs.contains(
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
            session.cachedSourceRepresentations[representationID]?.cell
        )
        return (session, representationID, cell)
    }

    private func foregroundEligiblePhantomItems(
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

    private func phantomPromotionKeys(
        session: MobilePlayerCollectionBrowserGridRenderer.Session
    ) -> Set<PromotionKey> {
        Set(session.phantomCells.map { tokenIndex, cell in
            PromotionKey(
                representationID: ObjectIdentifier(cell),
                tokenIndex: tokenIndex
            )
        })
    }

    private func runOnNextMainQueueTurn(
        _ action: @escaping () -> Void = {}
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                action()
                continuation.resume()
            }
        }
    }

    private func requestWithFailedMapping(
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
            )
        )
    }

    private func replacementRequest(
        for request: GridModePlaneRequest
    ) -> GridModePlaneRequest {
        GridModePlaneRequest(
            id: UUID(),
            toMode: request.toMode,
            layoutAspectState: request.layoutAspectState,
            anchorTokenIndex: request.anchorTokenIndex,
            transitionLayout: request.transitionLayout,
            crossfade: request.crossfade,
            latticeMap: request.latticeMap
        )
    }

    private func frameCorrection(
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
        return try XCTUnwrap(session.cellFrameCorrections.first {
            $0.cell === sourceCell
        }?.correction)
    }

    private func assertTransform(
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
        XCTAssertTrue(session.sourceCoverage.coveredDestinationItems.isEmpty)
        XCTAssertTrue(session.detailedSourceCellItems.isEmpty)
        XCTAssertTrue(session.cachedSourceRepresentations.isEmpty)
        XCTAssertTrue(session.transitionImageLoads.isEmpty)
        XCTAssertTrue(session.foregroundEligibleRepresentationIDs.isEmpty)
        XCTAssertTrue(session.currentViewportRepresentationIDs.isEmpty)
        XCTAssertTrue(session.cellFrameCorrections.isEmpty)
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

    func testReplacementPlaneRejectsQueuedSourceMaterialization() throws {
        let fixture = try makeFixture(clock: { 0 })
        let replacementFixture = try makeFixture(itemCount: 1, clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )

        XCTAssertTrue(fixture.renderer.installPlane(
            replacementFixture.planeRequest
        ))
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
        drainQueuedWork(fixture)

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertEqual(Set(session.sourceOverscanCells.keys), [0])
        let sourceCell = try XCTUnwrap(session.sourceOverscanCells[0])
        XCTAssertEqual(
            sourceCell.frame,
            replacementFixture.sourceLayout.itemFrame(at: 0)
        )
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

    func testImmediateFinishCancelsWorkBeforeFirstTick() throws {
        let fixture = try makeFixture()
        begin(fixture)

        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
        XCTAssertFalse(fixture.collectionView.subviews.contains {
            $0 is MobilePlayerCollectionBrowserCell
        })
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )

        XCTAssertNotNil(fixture.renderer.finish(preservingCarryover: false))
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 0)
        XCTAssertEqual(fixture.configureCount.value, 0)
    }

    func testPlaneTaggedSourceOverscanMaterializesAfterInstallation() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)

        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(sessionBeforeDrain) = fixture.renderer.lifecycle
        else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(sessionBeforeDrain.sourceOverscanCells.isEmpty)

        drainQueuedWork(fixture)

        guard case let .active(sessionAfterDrain) = fixture.renderer.lifecycle
        else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertFalse(sessionAfterDrain.sourceOverscanCells.isEmpty)
        XCTAssertTrue(sessionAfterDrain.sourceOverscanCells.values.allSatisfy {
            $0.alpha == 1 - sessionAfterDrain.lastContentFadeAlpha
        })
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testVisibleNoPlaneSourceCellsPromoteWithoutAnotherRender() throws {
        let fixture = try makeFixture(
            itemCount: 30,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: 0,
                viewportPoint: CGPoint(
                    x: fixture.viewportView.bounds.midX,
                    y: fixture.viewportView.bounds.midY
                ),
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

        drainQueuedWork(fixture)

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let sourceCellIDs = Set(session.sourceOverscanCells.values.map(
            ObjectIdentifier.init
        ))
        let visibleSourceCells = fixture.renderer.viewportRenderCells.filter {
            sourceCellIDs.contains(ObjectIdentifier($0))
        }
        XCTAssertFalse(visibleSourceCells.isEmpty)
        XCTAssertTrue(visibleSourceCells.allSatisfy(\.usesForegroundImageLoading))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testVisibleActivePlaneSourceCellsPromoteWithoutAnotherRender() throws {
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
        let sourceCellIDs = Set(session.sourceOverscanCells.values.map(
            ObjectIdentifier.init
        ))
        let visibleSourceCells = fixture.renderer.viewportRenderCells.filter {
            sourceCellIDs.contains(ObjectIdentifier($0))
        }
        XCTAssertFalse(visibleSourceCells.isEmpty)
        XCTAssertTrue(visibleSourceCells.allSatisfy(\.usesForegroundImageLoading))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testVisiblePhantomCellsPromoteWithoutAnotherRender() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let eligibilityReconciliationCount = fixture.renderer
            .foregroundEligibilityReconciliationCount

        drainQueuedWork(fixture)

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let phantomCellIDs = Set(session.phantomCells.values.map(
            ObjectIdentifier.init
        ))
        let visiblePhantomCells = fixture.renderer.viewportRenderCells.filter {
            phantomCellIDs.contains(ObjectIdentifier($0))
        }
        XCTAssertTrue(session.sourceOverscanCells.isEmpty)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(visiblePhantomCells.isEmpty)
        XCTAssertTrue(visiblePhantomCells.allSatisfy(
            \.usesForegroundImageLoading
        ))
        XCTAssertEqual(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            eligibilityReconciliationCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testActivePlaneExtendsSourceOverscanAfterTransform() throws {
        let fixture = try makeFixture(
            sourceColumnCount: 1,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let initialCoverage = try XCTUnwrap(
            session.sourceOverscanCoverage.installedRect
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0,
            panDeltaY: 0
        ))

        let transformedCoverage = try XCTUnwrap(
            session.sourceOverscanCoverage.installedRect
        )
        let transformedViewport = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        )
        XCTAssertGreaterThan(
            transformedCoverage.width,
            initialCoverage.width
        )
        XCTAssertGreaterThan(
            transformedCoverage.height,
            initialCoverage.height
        )
        XCTAssertTrue(transformedCoverage.contains(transformedViewport))
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertTrue(fixture.renderer.managedCells.isEmpty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDetailSelectionUsesPostTransformViewport() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        let cell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        cell.frame.origin.y = fixture.viewportView.bounds.maxY
            + fixture.viewportView.bounds.height / 4 + 20
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertFalse(session.selectedSourceItems.contains(0))
        let sourceCoverageBuildCount = fixture.renderer
            .sourceCoverageBuildCount

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0,
            panDeltaY: 0
        ))

        let postTransformViewport = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        )
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertEqual(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount
        )
        XCTAssertTrue(
            session.viewportDetailCoverage.installedRect?.contains(
                postTransformViewport
            ) == true
        )
        drainQueuedWork(fixture)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertGreaterThan(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount
        )
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

    func testTransitionImageCompletionWaitsForPump() async throws {
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
        let loaded = try XCTUnwrap(completion.value)

        loaded(makeImage())
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                sourceCell.contentView.subviews.map(ObjectIdentifier.init),
                originalSubviewIDs
            )
            XCTAssertEqual(
                fixture.renderer.pendingMaterializationWorkCount,
                1
            )
            _ = fixture.renderer.drainMaterializationWork()
        }

        XCTAssertGreaterThan(
            sourceCell.contentView.subviews.count,
            originalSubviewIDs.count
        )
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.preparedRepresentationIDs.contains(
            ObjectIdentifier(sourceCell)
        ))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testFrameCorrectionUsesViewportCoordinates() throws {
        let originCorrection = try frameCorrection(viewportOrigin: .zero)
        let translatedCorrection = try frameCorrection(
            viewportOrigin: CGPoint(x: 37, y: 83)
        )

        XCTAssertEqual(
            translatedCorrection.centerDelta.x,
            originCorrection.centerDelta.x,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            translatedCorrection.centerDelta.y,
            originCorrection.centerDelta.y,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            translatedCorrection.sizeDelta.width,
            originCorrection.sizeDelta.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            translatedCorrection.sizeDelta.height,
            originCorrection.sizeDelta.height,
            accuracy: 0.000_001
        )
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

    func testCellEndDisplayRemovesDetailWithoutFilteringWholeQueue()
        throws {
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
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(
            fixture.renderer.pendingDetailMaterializationWorkCount,
            1
        )
        let filterPassCount = fixture.renderer
            .transitionWorkQueueFilterPassCount

        fixture.renderer.didEndDisplayingCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )

        XCTAssertEqual(
            fixture.renderer.pendingDetailMaterializationWorkCount,
            0
        )
        XCTAssertEqual(
            fixture.renderer.transitionWorkQueueFilterPassCount,
            filterPassCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
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

    func testQueuedDetailDemotesWhenCellLeavesCurrentViewport() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0
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
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(
            fixture.renderer
                .pendingVisibleDetailMaterializationRepresentationIDs
                .contains(representationID)
        )

        sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY
        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )

        XCTAssertTrue(
            session.foregroundEligibleRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.currentViewportRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            fixture.renderer
                .pendingDetailMaterializationRepresentationIDs
                .contains(representationID)
        )
        XCTAssertFalse(
            fixture.renderer
                .pendingVisibleDetailMaterializationRepresentationIDs
                .contains(representationID)
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

    func testForegroundEligibilityReconciliationUsesBufferedCoverage()
        throws {
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 5,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0
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
        let currentViewportRect = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        )
        let expectedCurrentCoverage = currentViewportRect.insetBy(
            dx: -currentViewportRect.width / 4,
            dy: -currentViewportRect.height / 4
        )
        let currentCoverage = try XCTUnwrap(
            session.foregroundCurrentViewportCoverage.installedRect
        )
        XCTAssertEqual(
            currentCoverage.width,
            expectedCurrentCoverage.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            currentCoverage.height,
            expectedCurrentCoverage.height,
            accuracy: 0.000_001
        )
        let reconciliationCount = fixture.renderer
            .foregroundEligibilityReconciliationCount

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale * 0.999,
            settleProgress: 0,
            panDeltaY: -1
        ))

        XCTAssertEqual(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            reconciliationCount
        )
        let actuallyEligibleIDs = foregroundEligibleRepresentationIDs(
            fixture: fixture,
            session: session,
            panDeltaY: -1,
            usesBufferedCoverage: false
        )
        XCTAssertTrue(actuallyEligibleIDs.isSubset(
            of: session.foregroundEligibleRepresentationIDs
        ))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: -fixture.viewportView.bounds.height
        ))
        XCTAssertGreaterThan(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            reconciliationCount
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testInstalledPhantomsStayEligibleWithinBufferedCoverage()
        throws {
        let fixture = try makeFixture(
            itemCount: 240,
            sourceColumnCount: 1,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 0
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
        let firstEligibleItems = foregroundEligiblePhantomItems(
            fixture: fixture,
            session: session,
            panDeltaY: 0
        )
        XCTAssertFalse(firstEligibleItems.isEmpty)
        XCTAssertEqual(firstEligibleItems, Set(session.phantomCells.keys))
        XCTAssertTrue(firstEligibleItems.allSatisfy {
            session.phantomCells[$0]?.usesForegroundImageLoading == true
        })

        let panDeltaY = -fixture.viewportView.bounds.height / 2
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: panDeltaY
        ))
        drainQueuedWork(fixture)
        let secondEligibleItems = foregroundEligiblePhantomItems(
            fixture: fixture,
            session: session,
            panDeltaY: panDeltaY
        )
        XCTAssertFalse(
            firstEligibleItems.subtracting(secondEligibleItems).isEmpty
        )
        XCTAssertFalse(
            secondEligibleItems.subtracting(firstEligibleItems).isEmpty
        )
        XCTAssertEqual(secondEligibleItems, Set(session.phantomCells.keys))
        XCTAssertTrue(secondEligibleItems.allSatisfy {
            session.phantomCells[$0]?.usesForegroundImageLoading == true
        })
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPhantomPlaneShiftRetiresOldCellsAndPromotesNewCells() throws {
        let fixture = try makeFixture(
            itemCount: 1_000,
            sourceColumnCount: 1,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 500
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
        let firstPhantomKeys = phantomPromotionKeys(session: session)

        let panDeltaY = -fixture.viewportView.bounds.height / 2
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: panDeltaY
        ))
        drainQueuedWork(fixture)
        let secondPhantomKeys = phantomPromotionKeys(session: session)
        XCTAssertFalse(firstPhantomKeys.subtracting(secondPhantomKeys).isEmpty)
        XCTAssertFalse(secondPhantomKeys.subtracting(firstPhantomKeys).isEmpty)
        XCTAssertTrue(session.phantomCells.values.allSatisfy(
            \.usesForegroundImageLoading
        ))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0,
            panDeltaY: -fixture.viewportView.bounds.height * 10
        ))
        drainQueuedWork(fixture)
        let finalPhantomKeys = phantomPromotionKeys(session: session)
        XCTAssertFalse(
            secondPhantomKeys.subtracting(finalPhantomKeys).isEmpty
        )
        XCTAssertTrue(session.phantomCells.values.allSatisfy(
            \.usesForegroundImageLoading
        ))
        XCTAssertTrue(
            fixture.renderer.pendingPromotionRepresentationKeys.isEmpty
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testInvalidTransitionCompletionIsRetiredByPump() async throws {
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
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        try XCTUnwrap(completion.value)(makeImage())
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
        await runOnNextMainQueueTurn {
            XCTAssertEqual(
                fixture.renderer.pendingMaterializationWorkCount,
                1
            )
            _ = fixture.renderer.drainMaterializationWork()
        }
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.transitionImageLoads.isEmpty)
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
        XCTAssertLessThan(sourceCell.alpha, 1)
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
        XCTAssertLessThan(sourceCell.alpha, 1)
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

    func testTwoPhaseCommitInstallsCapturedPhantomCarryover() throws {
        let fixture = try makeFixture(
            showsSourceCell: true,
            providesContentAccess: true,
            installsSyntheticContent: true,
            clock: { 0 }
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
        let phantom = try XCTUnwrap(session.phantomCells.values.first)
        phantom.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let expectedIdentity = try XCTUnwrap(
            phantom.carryoverSourceContent?.identity
        )
        sourceCell.frame = phantom.frame

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .fiveColumns
        ))

        XCTAssertGreaterThan(preparation.carryoverSourceCount, 0)
        XCTAssertNil(sourceCell.carryoverSourceContent)
        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        XCTAssertEqual(
            sourceCell.carryoverSourceContent?.identity,
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

    func testCommitRecordsMappingFailuresWithoutCachingThem() throws {
        let cacheAccessCount = Counter()
        let cachedImage = makeImage()
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
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertNil(session.reassignments[0])

        let preparation = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: request.id,
            mode: .fiveColumns
        ))
        guard case let .committing(commit) = fixture.renderer.lifecycle else {
            return XCTFail("Expected a committing renderer session")
        }
        XCTAssertTrue(commit.ineligibleFallbackSourceItems.contains(0))
        XCTAssertNil(commit.session.reassignments[0])
        XCTAssertTrue(fixture.renderer.completeCommit(preparation))
        XCTAssertEqual(cacheAccessCount.value, 0)
        XCTAssertNil(destinationCell.carryoverSourceContent)
        let finish = try XCTUnwrap(
            fixture.renderer.finish(preservingCarryover: true)
        )
        XCTAssertTrue(finish.clearsTransitionPlaceholderTones)
    }

    func testCommitReconcilesSourceInstalledAtBudgetBoundary() throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            providesContentAccess: true,
            anchorItemIndex: 0,
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.003
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

        guard case let .committing(commit) = fixture.renderer.lifecycle else {
            return XCTFail("Expected a committing renderer session")
        }
        XCTAssertTrue(commit.ineligibleFallbackSourceItems.contains(0))
        fixture.renderer.abortCommit(preparation)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testFadeFlushesPreparedSourceCoverageBeforeLockingFallbacks()
        throws {
        let image = makeImage()
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.003
            }
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        _ = fixture.renderer.drainMaterializationWork()

        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let representationID = ObjectIdentifier(sourceCell)
        XCTAssertTrue(session.preparedRepresentationIDs.contains(
            representationID
        ))
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            panDeltaY: 0
        ))

        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertNotNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )
        XCTAssertFalse(session.lockedFallbackRepresentationIDs.contains(
            representationID
        ))
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testRendererDeallocatesWithPendingDisplayLinkWork() throws {
        weak var renderer: MobilePlayerCollectionBrowserGridRenderer?

        do {
            let fixture = try makeFixture()
            begin(fixture)
            XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
            XCTAssertGreaterThan(
                fixture.renderer.pendingMaterializationWorkCount,
                0
            )
            renderer = fixture.renderer
        }

        XCTAssertNil(renderer)
    }

    func testDestinationPlanRefreshBatchesAndDiscardsSupersededJobs() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let planGeneration = session.destinationPlaneCellPlanGeneration

        fixture.renderer.didConfigureCell(
            MobilePlayerCollectionBrowserCell(frame: .zero),
            at: IndexPath(item: 0, section: 0)
        )
        fixture.renderer.didConfigureCell(
            MobilePlayerCollectionBrowserCell(frame: .zero),
            at: IndexPath(item: 1, section: 0)
        )

        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        XCTAssertEqual(
            session.destinationPlaneCellPlanGeneration,
            planGeneration + 1
        )

        let refreshResult = fixture.renderer.drainMaterializationWork()
        XCTAssertEqual(refreshResult.processedCount, 8)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 2)
        XCTAssertGreaterThan(fixture.configureCount.value, 0)
        XCTAssertLessThanOrEqual(fixture.configureCount.value, 7)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPendingDetailLoadKeepsDestinationPlan() throws {
        let imageLoadCount = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    imageLoadCount.value += 1
                    return {}
                }
            ),
            clock: { 0 }
        )
        XCTAssertEqual(fixture.collectionView.visibleCells.count, 1)
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let planGeneration = session.destinationPlaneCellPlanGeneration

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(result.processedCount, 0)
        XCTAssertEqual(imageLoadCount.value, 1)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertEqual(
            session.destinationPlaneCellPlanGeneration,
            planGeneration
        )
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPreparedDetailRefreshesDestinationCoverage() throws {
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
            ),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(result.processedCount, 0)
        XCTAssertEqual(fixture.configureCount.value, 0)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 2)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertEqual(
            session.sourceCoverage.coveredDestinationItems,
            Set([0])
        )
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 2)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPreparedDetailsBatchSourceCoverageRefresh() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 60,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (
                        imageSources.thumbnailDescriptor,
                        .thumbnail,
                        image
                    )
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 1)

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 8)
        XCTAssertGreaterThan(session.preparedRepresentationIDs.count, 1)
        XCTAssertEqual(fixture.renderer.sourceCoverageBuildCount, 2)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testTransitionImageCompletionsBatchSourceCoverageRefresh()
        async throws {
        let callbacks = Box<[((UIImage?) -> Void)]>([])
        let fixture = try makeFixture(
            itemCount: 60,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, completion in
                    callbacks.value.append(completion)
                    return {}
                }
            ),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertGreaterThan(callbacks.value.count, 1)
        let sourceCoverageBuildCount = fixture.renderer
            .sourceCoverageBuildCount
        XCTAssertGreaterThan(session.transitionImageLoads.count, 1)

        for callback in callbacks.value {
            callback(makeImage())
        }
        await runOnNextMainQueueTurn()
        XCTAssertGreaterThan(
            fixture.renderer.pendingTransitionImageCompletionWorkCount,
            1
        )

        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(session.preparedRepresentationIDs.count, 1)
        XCTAssertEqual(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount + 1
        )
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDrainProcessesAtMostEightJobs() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let pendingCount = fixture.renderer.pendingMaterializationWorkCount
        XCTAssertGreaterThan(pendingCount, 8)

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 8)
        XCTAssertGreaterThan(fixture.renderer.pendingMaterializationWorkCount, 0)
        XCTAssertLessThanOrEqual(
            fixture.renderer.pendingMaterializationWorkCount,
            pendingCount
        )
        XCTAssertGreaterThan(fixture.configureCount.value, 0)
        XCTAssertLessThanOrEqual(fixture.configureCount.value, 7)
        XCTAssertFalse(result.stoppedForTimeLimit)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testPhantomShapeHierarchyIsRetainedAcrossDrainBatches() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layerIDs = try XCTUnwrap(shapeView.layer.sublayers).map(
            ObjectIdentifier.init
        )
        XCTAssertFalse(layerIDs.isEmpty)

        _ = fixture.renderer.drainMaterializationWork()
        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertTrue(session.phantomShapeView === shapeView)
        XCTAssertEqual(
            shapeView.layer.sublayers?.map(ObjectIdentifier.init),
            layerIDs
        )
        XCTAssertFalse(session.phantomCells.isEmpty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testRetainedCandidateShapeHidesWithoutImplicitAnimations() throws {
        let fixture = try makeFixture(itemCount: 1, clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        XCTAssertFalse(shapeView.isHidden)
        XCTAssertFalse(layers.candidates.isHidden)
        XCTAssertNotNil(layers.candidates.path)
        XCTAssertTrue(layers.repeatedRows.isHidden)
        XCTAssertTrue(layers.finalRow.isHidden)
        XCTAssertTrue(layers.solidCoverage.isHidden)
        assertNoAnimations(in: shapeView.layer)

        drainQueuedWork(fixture)

        XCTAssertTrue(session.phantomShapeView === shapeView)
        XCTAssertTrue(shapeView.isHidden)
        XCTAssertEqual(
            shapeView.layer.sublayers?.map(ObjectIdentifier.init),
            [
                layers.repeatedRows,
                layers.finalRow,
                layers.solidCoverage,
                layers.candidates,
            ].map(ObjectIdentifier.init)
        )
        assertNoAnimations(in: shapeView.layer)
        _ = fixture.renderer.finish(preservingCarryover: false)
        XCTAssertNil(shapeView.superview)
    }

    func testRetainedRepeatedShapeUpdatesMaskWithoutImplicitAnimations()
        throws {
        let fixture = try makeFixture(
            itemCount: 603,
            uniformImageSize: CGSize(width: 10, height: 1),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        XCTAssertFalse(layers.repeatedRows.isHidden)
        XCTAssertGreaterThan(layers.repeatedRows.instanceCount, 0)
        XCTAssertNotNil(layers.repeatedRow.path)
        XCTAssertFalse(layers.finalRow.isHidden)
        XCTAssertNotNil(layers.finalRow.path)
        XCTAssertTrue(layers.solidCoverage.isHidden)
        XCTAssertNil(shapeView.layer.mask)
        assertNoAnimations(in: shapeView.layer)

        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertTrue(session.phantomShapeView === shapeView)
        let mask = try XCTUnwrap(shapeView.layer.mask as? CAShapeLayer)
        XCTAssertEqual(mask.fillRule, .evenOdd)
        XCTAssertNotNil(mask.path)
        XCTAssertFalse(layers.repeatedRows.isHidden)
        XCTAssertFalse(layers.finalRow.isHidden)
        XCTAssertTrue(layers.solidCoverage.isHidden)
        assertNoAnimations(in: shapeView.layer)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testRetainedSolidShapeUpdatesMaskWithoutImplicitAnimations() throws {
        let fixture = try makeFixture(
            itemCount: 10_000,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            clock: { 0 }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        XCTAssertTrue(layers.repeatedRows.isHidden)
        XCTAssertTrue(layers.finalRow.isHidden)
        XCTAssertFalse(layers.solidCoverage.isHidden)
        XCTAssertNotNil(layers.solidCoverage.path)
        XCTAssertNil(shapeView.layer.mask)
        assertNoAnimations(in: shapeView.layer)

        _ = fixture.renderer.drainMaterializationWork()

        XCTAssertTrue(session.phantomShapeView === shapeView)
        let mask = try XCTUnwrap(shapeView.layer.mask as? CAShapeLayer)
        XCTAssertEqual(mask.fillRule, .evenOdd)
        XCTAssertNotNil(mask.path)
        XCTAssertTrue(layers.repeatedRows.isHidden)
        XCTAssertFalse(layers.solidCoverage.isHidden)
        assertNoAnimations(in: shapeView.layer)
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
        XCTAssertEqual(sourceCell.alpha, 0, accuracy: 0.000_001)

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

    func testNewViewportDetailPreemptsRemainingSourceWorkWithinDrain()
        throws {
        let imageLoadCount = Counter()
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(true)
        let fixture = try makeFixture(
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    imageLoadCount.value += 1
                    return {}
                }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                guard limitsDrainToOneJob.value else { return 0 }
                return clockCalls.value < 2 ? 0 : 0.003
            }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        let destinationCellCount = try XCTUnwrap(
            session.currentPhantomPlan?.cellCandidates.count
        )
        for _ in 0 ..< destinationCellCount * 3 {
            guard session.phantomCells.count < destinationCellCount else {
                break
            }
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertEqual(session.phantomCells.count, destinationCellCount)

        limitsDrainToOneJob.value = false
        clockCalls.value = 0
        let sourceResult = fixture.renderer.drainMaterializationWork()

        XCTAssertLessThanOrEqual(sourceResult.processedCount, 8)
        XCTAssertFalse(session.sourceOverscanCells.isEmpty)
        XCTAssertGreaterThan(imageLoadCount.value, 0)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDirtySourceRefreshRespectsTimeAndCannotBeStarvedAcrossDrains()
        throws {
        let imageLoadCount = Counter()
        let clockCalls = Counter()
        let clockMode = Box(0)
        let fixture = try makeFixture(
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    imageLoadCount.value += 1
                    return {}
                }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                switch clockMode.value {
                case 0:
                    return clockCalls.value < 2 ? 0 : 0.003
                case 1:
                    return clockCalls.value == 0 ? 0 : 0.003
                default:
                    return 0
                }
            }
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        for _ in 0 ..< 500 {
            guard session.sourceOverscanCells.isEmpty else { break }
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertFalse(session.sourceOverscanCells.isEmpty)
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertEqual(imageLoadCount.value, 0)

        clockMode.value = 1
        clockCalls.value = 0
        let expiredResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(expiredResult.processedCount, 0)
        XCTAssertTrue(expiredResult.stoppedForTimeLimit)
        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)

        clockMode.value = 0
        clockCalls.value = 0
        let refreshResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(refreshResult.processedCount, 1)
        XCTAssertEqual(imageLoadCount.value, 0)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)

        clockCalls.value = 0
        let detailResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(detailResult.processedCount, 1)
        XCTAssertGreaterThan(imageLoadCount.value, 0)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testSourceJobWaitsWhenItsDependentWorkCannotFitInDrain() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        for itemIndex in 0 ..< 6 {
            let cell = MobilePlayerCollectionBrowserCell(frame: .zero)
            cell.configure(
                contentIdentity: MobilePlayerBrowserContentIdentity(
                    collectionId: "queued",
                    tokenIndex: itemIndex
                ),
                itemCount: 6,
                imageSources: nil,
                requiredImageQuality: .thumbnail,
                missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                    thumbnailAspectRatio: nil
                ),
                imageLoadPolicy: .disabled
            )
            fixture.renderer.willDisplayCell(
                cell,
                at: IndexPath(item: itemIndex, section: 0)
            )
        }
        XCTAssertTrue(session.destinationPlanRefreshIsDirty)

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 8)
        XCTAssertTrue(session.sourceOverscanCells.isEmpty)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testQueuedDetailIsPromotedWhenCellEntersViewport() throws {
        let imageLoadCount = Counter()
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(false)
        let fixture = try makeFixture(
            itemCount: 1,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in
                    imageLoadCount.value += 1
                    return {}
                }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                guard limitsDrainToOneJob.value else { return 0 }
                return clockCalls.value < 2 ? 0 : 0.003
            }
        )
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY + 1
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        guard case let .active(session) = fixture.renderer.lifecycle else {
            return XCTFail("Expected an active renderer session")
        }
        XCTAssertTrue(session.selectedSourceItems.isEmpty)
        drainQueuedWork(fixture)
        XCTAssertEqual(imageLoadCount.value, 0)

        sourceCell.frame.origin.y = fixture.viewportView.bounds.maxY + 1
        fixture.renderer.didConfigureCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 1)

        sourceCell.frame.origin.y = fixture.viewportView.bounds.minY
        fixture.renderer.willDisplayCell(
            sourceCell,
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertEqual(fixture.renderer.pendingMaterializationWorkCount, 2)

        limitsDrainToOneJob.value = true
        clockCalls.value = 0
        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertEqual(imageLoadCount.value, 1)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDrainStopsAtTwoMillisecondBudget() throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(clock: {
            defer { clockCalls.value += 1 }
            return clockCalls.value < 2 ? 0 : 0.003
        })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertTrue(result.stoppedForTimeLimit)
        XCTAssertGreaterThanOrEqual(result.elapsed, 0.002)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDeferredRefreshWaitsWhenBudgetIsExhausted() throws {
        let clockCalls = Counter()
        let returnsExpiredTime = Box(true)
        let fixture = try makeFixture(clock: {
            defer { clockCalls.value += 1 }
            guard returnsExpiredTime.value else { return 0 }
            return clockCalls.value == 0 ? 0 : 0.003
        })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        fixture.renderer.didConfigureCell(
            MobilePlayerCollectionBrowserCell(frame: .zero),
            at: IndexPath(item: 0, section: 0)
        )
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)

        let expiredResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(expiredResult.processedCount, 0)
        XCTAssertTrue(expiredResult.stoppedForTimeLimit)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)

        returnsExpiredTime.value = false
        let refreshResult = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(refreshResult.processedCount, 8)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 2)
        XCTAssertGreaterThan(fixture.configureCount.value, 0)
        XCTAssertLessThanOrEqual(fixture.configureCount.value, 7)
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
}
