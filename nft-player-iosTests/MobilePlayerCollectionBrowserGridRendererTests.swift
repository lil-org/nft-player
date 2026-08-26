// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
private func runMainTrackingRunLoop(
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

    private final class SourceBrowserLayout: UICollectionViewLayout {
        let browserLayout: MobilePlayerBrowserLayout

        init(browserLayout: MobilePlayerBrowserLayout) {
            self.browserLayout = browserLayout
            super.init()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var collectionViewContentSize: CGSize {
            browserLayout.contentSize
        }

        override func layoutAttributesForElements(
            in rect: CGRect
        ) -> [UICollectionViewLayoutAttributes]? {
            browserLayout.candidateItemIndices(intersecting: rect).compactMap {
                itemIndex in
                let indexPath = IndexPath(item: itemIndex, section: 0)
                guard let attributes = layoutAttributesForItem(at: indexPath),
                      attributes.frame.intersects(rect) else {
                    return nil
                }
                return attributes
            }
        }

        override func layoutAttributesForItem(
            at indexPath: IndexPath
        ) -> UICollectionViewLayoutAttributes? {
            guard indexPath.section == 0,
                  let frame = browserLayout.itemFrame(at: indexPath.item) else {
                return nil
            }
            let attributes = UICollectionViewLayoutAttributes(
                forCellWith: indexPath
            )
            attributes.frame = frame
            return attributes
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

    private func phantomShapeMaskContains(
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

    private func onePixelAccuracy(in view: UIView) -> CGFloat {
        let scale = view.window?.screen.scale
            ?? view.traitCollection.displayScale
        return 1 / max(scale, 1)
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
        heightToWidthRatios: [CGFloat]? = nil,
        sourceContentOffsetY: CGFloat? = nil,
        contentImageSources: CollectionBrowseImageSources? = nil,
        imageAccess: MobilePlayerCollectionBrowserGridRenderer.ImageAccess?
            = nil,
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
                collectionLayout = SourceBrowserLayout(
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

    private func activeSession(
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

    @MainActor
    private final class MainRunLoopAction {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func call() {
            action()
        }
    }

    private func runOnNextMainQueueTurn(
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
        return try XCTUnwrap(
            session.cellFrameCorrections[ObjectIdentifier(sourceCell)]?
                .correction
        )
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

    private func horizontallyAdjacentCorrectedCells(
        fixture: Fixture,
        session: MobilePlayerCollectionBrowserGridRenderer.Session
    ) -> (
        leftItem: Int,
        left: MobilePlayerCollectionBrowserCell,
        rightItem: Int,
        right: MobilePlayerCollectionBrowserCell
    )? {
        let representations = session.cachedSourceRepresentations.compactMap {
            representationID, representation in
            session.cellFrameCorrections[representationID] == nil
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

    private func horizontalScreenGap(
        left: UICollectionViewCell,
        right: UICollectionViewCell,
        in viewportView: UIView
    ) -> CGFloat {
        let leftFrame = left.convert(left.bounds, to: viewportView)
        let rightFrame = right.convert(right.bounds, to: viewportView)
        return rightFrame.minX - leftFrame.maxX
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

    func testCellWhoseDestinationLeavesTheViewportIsHeldForMarginCoverage() throws {
        let image = makeImage()
        func counts(
            anchorItemIndex: Int
        ) throws -> (corrections: Int, held: Int) {
            let fixture = try makeFixture(
                itemCount: 300,
                sourceColumnCount: 3,
                destinationColumnCount: 1,
                destinationMode: .large,
                showsSourceCell: true,
                providesContentAccess: true,
                anchorItemIndex: anchorItemIndex,
                imageAccess: .init(
                    cachedImage: { imageSources, _ in
                        (imageSources.thumbnailDescriptor, .thumbnail, image)
                    },
                    loadImage: { _, _ in {} }
                )
            )
            defer { _ = fixture.renderer.finish(preservingCarryover: false) }
            begin(fixture)
            XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
            drainQueuedWork(fixture)
            let session = try activeSession(fixture)
            XCTAssertTrue(
                fixture.collectionView.visibleCells.allSatisfy {
                    $0.alpha == 1
                },
                "no source cell fades out and leaves a hole in the margins"
            )
            return (
                session.cellFrameCorrections.count,
                session.marginCoverageRepresentationIDs.count
            )
        }

        let onScreen = try counts(anchorItemIndex: 0)
        XCTAssertGreaterThan(
            onScreen.corrections,
            0,
            "an on-screen destination still gets its frame correction"
        )

        let offScreen = try counts(anchorItemIndex: 200)
        XCTAssertEqual(
            offScreen.corrections,
            0,
            "an off-screen destination gets no frame correction"
        )
        XCTAssertGreaterThan(
            offScreen.held,
            0,
            "an off-screen destination is held on the source lattice"
        )
    }

    func testCacheMissOffscreenDestinationStaysHeldThroughRetry()
        async throws {
        let callbacks = Box<[(UIImage?) -> Void]>([])
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 3,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, callback in
                    callbacks.value.append(callback)
                    return {}
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
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(sourceCell)
        let destinationItem = try XCTUnwrap(
            session.reassignments[0]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )

        XCTAssertEqual(callbacks.value.count, 0)
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )

        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertEqual(callbacks.value.count, 0)
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        drainQueuedWork(fixture)
        let firstLoadCount = callbacks.value.count
        XCTAssertGreaterThan(firstLoadCount, 0)

        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            presentationProgress: 0,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertEqual(callbacks.value.count, firstLoadCount)
        XCTAssertNotNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            presentationProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertNotNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        for callback in callbacks.value.prefix(firstLoadCount) {
            callback(nil)
        }
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)
        XCTAssertNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        drainQueuedWork(fixture)
        let retryCallbacks = callbacks.value.dropFirst(firstLoadCount)
        XCTAssertFalse(retryCallbacks.isEmpty)

        let image = makeImage()
        for callback in retryCallbacks {
            callback(image)
        }
        await runOnNextMainQueueTurn()
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertFalse(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(primaryTransitionImage(in: sourceCell) === image)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: -targetOffsetY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertGreaterThan(contentContainer.alpha, 0)
    }

    func testPendingBaseCarryoverReclassifiesWithoutAnOnScreenCorrection()
        throws {
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 3,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        sourceCell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 0
            ),
            image: makeImage(),
            usesNativeMetalCardCornerMask: false
        ))
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = ObjectIdentifier(sourceCell)
        let destinationItem = try XCTUnwrap(session.reassignments[0])
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: sourceCell)
        )

        XCTAssertNil(session.transitionImageLoads[representationID])
        XCTAssertTrue(sourceCell.holdsCarryoverForPendingBaseImage)
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 1, accuracy: 0.000_001)

        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 1, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(sourceCell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                sourceCell.convert(
                    sourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )
    }

    func testTerminalSettleContinuouslyRetiresVisibleMarginSourceToOffscreenDestination()
        throws {
        let ratios: [CGFloat] = [
            1, 1, 4, 1, 1, 0.25,
            1, 1, 4, 1, 1, 0.25,
        ]
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 3,
            heightToWidthRatios: ratios,
            sourceContentOffsetY: 158,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceAnchorFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 3)
        )
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: 3,
                viewportPoint: CGPoint(
                    x: sourceAnchorFrame.midX,
                    y: sourceAnchorFrame.midY
                        - fixture.collectionView.contentOffset.y
                ),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: fixture.collectionView.contentOffset.y
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let sourceRepresentation = try XCTUnwrap(
            session.cachedSourceRepresentations.values.first {
                $0.itemIndex == 6
            }
        )
        let representationID = ObjectIdentifier(sourceRepresentation.cell)
        let destinationItem = try XCTUnwrap(
            session.reassignments[sourceRepresentation.itemIndex]
        )
        XCTAssertEqual(destinationItem, 6)
        XCTAssertNotNil(session.phantomCells[4])

        let initialSourceFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertNotNil(PlayerBrowserGridGeometry.visibleRect(
            initialSourceFrame,
            clippedTo: fixture.viewportView.bounds
        ))

        let terminalScale = fixture.planeRequest.transitionLayout.itemWidthRatio
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let marginFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(PlayerBrowserGridGeometry.visibleRect(
            marginFrame,
            clippedTo: fixture.viewportView.bounds
        ))
        let marginOccupantFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                marginOccupantFrame
            )
        )

        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: terminalScale,
            panDeltaY: 0
        )
        let destinationLayoutFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let destinationFrame = destinationLayoutFrame.offsetBy(
            dx: 0,
            dy: -terminalPlane.incomingContentOffsetY
        )
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            destinationFrame,
            clippedTo: fixture.viewportView.bounds
        ))

        let tailStart = PlayerBrowserGridCrossfade
            .contentFadeEndSettleProgress
        let progressAtNinety = (0.9 - tailStart) / (1 - tailStart)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.9,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress),
            progressAtNinety,
            accuracy: 0.000_001
        )
        // The overlay fades uniformly with the content fade — the retirement
        // visibility ramp shapes only the flight transform, never the alpha.
        XCTAssertEqual(
            try XCTUnwrap(transitionContentContainer(
                in: sourceRepresentation.cell
            )).alpha,
            1,
            accuracy: 0.000_001
        )
        let ninetyPercentFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertNotNil(PlayerBrowserGridGeometry.visibleRect(
            ninetyPercentFrame,
            clippedTo: fixture.viewportView.bounds
        ))
        let ninetyPercentOccupantFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                ninetyPercentOccupantFrame
            )
        )
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                marginOccupantFrame
            )
        )

        let offscreenBoundaryPan = -(
            destinationFrame.minY - fixture.viewportView.bounds.maxY - 1
        )
        let offscreenBoundaryPlane = fixture.planeRequest.crossfade
            .outgoingPlane(
                scale: terminalScale,
                panDeltaY: offscreenBoundaryPan
            )
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            destinationLayoutFrame.offsetBy(
                dx: 0,
                dy: -offscreenBoundaryPlane.incomingContentOffsetY
            ),
            clippedTo: fixture.viewportView.bounds
        ))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.9,
            panDeltaY: offscreenBoundaryPan
        ))
        let offscreenBoundaryProgress = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )

        let shallowBoundaryPan = -(
            destinationFrame.minY - fixture.viewportView.bounds.maxY + 1
        )
        let shallowBoundaryPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: terminalScale,
            panDeltaY: shallowBoundaryPan
        )
        let shallowVisibleRect = try XCTUnwrap(
            PlayerBrowserGridGeometry.visibleRect(
                destinationLayoutFrame.offsetBy(
                    dx: 0,
                    dy: -shallowBoundaryPlane.incomingContentOffsetY
                ),
                clippedTo: fixture.viewportView.bounds
            )
        )
        XCTAssertEqual(shallowVisibleRect.height, 1, accuracy: 0.000_001)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.9,
            panDeltaY: shallowBoundaryPan
        ))
        let shallowBoundaryProgress = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertEqual(
            offscreenBoundaryProgress,
            progressAtNinety,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            shallowBoundaryProgress,
            offscreenBoundaryProgress,
            accuracy: 0.000_001
        )

        let progressAtNinetyNine = (0.99 - tailStart) / (1 - tailStart)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.99,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            try XCTUnwrap(session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress),
            progressAtNinetyNine,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(transitionContentContainer(
                in: sourceRepresentation.cell
            )).alpha,
            1,
            accuracy: 0.000_001
        )
        let ninetyNinePercentFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertGreaterThan(
            ninetyNinePercentFrame.minY,
            ninetyPercentFrame.minY
        )
        XCTAssertLessThan(
            ninetyNinePercentFrame.maxY,
            ninetyPercentFrame.maxY
        )
        XCTAssertGreaterThan(destinationFrame.minY, ninetyNinePercentFrame.minY)
        XCTAssertLessThan(destinationFrame.maxY, ninetyNinePercentFrame.maxY)
        XCTAssertLessThan(
            destinationFrame.minY - ninetyNinePercentFrame.minY,
            ninetyNinePercentFrame.minY - ninetyPercentFrame.minY
        )
        XCTAssertLessThan(
            ninetyNinePercentFrame.maxY - destinationFrame.maxY,
            ninetyPercentFrame.maxY - ninetyNinePercentFrame.maxY
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 1,
            panDeltaY: 0
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress,
            1
        )
        XCTAssertEqual(
            try XCTUnwrap(transitionContentContainer(
                in: sourceRepresentation.cell
            )).alpha,
            1,
            accuracy: 0.000_001
        )
        let terminalSourceFrame = sourceRepresentation.cell.convert(
            sourceRepresentation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertEqual(
            terminalSourceFrame.minY,
            destinationFrame.minY,
            accuracy: 0.01
        )
        XCTAssertEqual(
            terminalSourceFrame.height,
            destinationFrame.height,
            accuracy: 0.01
        )
        XCTAssertNil(PlayerBrowserGridGeometry.visibleRect(
            terminalSourceFrame,
            clippedTo: fixture.viewportView.bounds
        ))
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                marginOccupantFrame
            )
        )

        _ = try XCTUnwrap(fixture.renderer.prepareCommit(
            id: fixture.planeRequest.id,
            mode: .large
        ))
        guard case let .committing(commit) = fixture.renderer.lifecycle else {
            return XCTFail("Expected a committing renderer session")
        }
        XCTAssertFalse(commit.sources.contains {
            $0.content?.identity.tokenIndex == sourceRepresentation.itemIndex
        })
    }

    func testMarginCoverageReclassifiesAndRestoresPreparedContentDuringPan()
        throws {
        let returnsCachedImage = Box(true)
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    returnsCachedImage.value
                        ? (
                            imageSources.thumbnailDescriptor,
                            .thumbnail,
                            image
                        )
                        : nil
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.filter {
                representationID in
                guard let representation = session
                    .cachedSourceRepresentations[representationID],
                      let destinationItem = session.reassignments[
                          representation.itemIndex
                      ],
                      let destinationFrame = fixture.destinationLayout
                          .itemFrame(at: destinationItem) else {
                    return false
                }
                return destinationFrame.minY
                    >= fixture.viewportView.bounds.maxY
            }.min { lhs, rhs in
                let lhsItem = session.cachedSourceRepresentations[lhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let rhsItem = session.cachedSourceRepresentations[rhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let lhsY = lhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                let rhsY = rhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                return lhsY < rhsY
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let settleProgress: CGFloat = 0.5

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(session.lastContentFadeAlpha, 0)
        XCTAssertEqual(representation.cell.alpha, 1, accuracy: 0.000_001)
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)
        XCTAssertNil(session.cellFrameCorrections[representationID])
        let marginTransform = representation.cell.transform
        XCTAssertEqual(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ],
            destinationItem
        )

        returnsCachedImage.value = false
        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: scale,
            panDeltaY: onScreenPanDeltaY
        )
        XCTAssertTrue(destinationFrame.offsetBy(
            dx: -fixture.collectionView.contentOffset.x,
            dy: -terminalPlane.incomingContentOffsetY
        ).intersects(fixture.viewportView.bounds))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        let visibilityProgress = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertGreaterThan(visibilityProgress, 0)
        XCTAssertLessThan(visibilityProgress, 0.1)
        XCTAssertEqual(
            representation.cell.transform.a,
            marginTransform.a,
            accuracy: 0.01
        )
        XCTAssertEqual(
            representation.cell.transform.d,
            marginTransform.d,
            accuracy: 0.01
        )
        XCTAssertEqual(
            representation.cell.transform.tx,
            marginTransform.tx,
            accuracy: 2
        )
        XCTAssertEqual(
            representation.cell.transform.ty,
            marginTransform.ty,
            accuracy: 2
        )
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )
        drainQueuedWork(fixture)
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(representation.cell.transform, marginTransform)
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)
        XCTAssertNil(contentContainer.layer.animation(forKey: "opacity"))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(contentContainer.alpha, 0, accuracy: 0.000_001)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertEqual(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ],
            destinationItem
        )
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 1,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertEqual(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress,
            1
        )
        let expectedTerminalFrame = destinationFrame.offsetBy(
            dx: -fixture.collectionView.contentOffset.x,
            dy: -terminalPlane.incomingContentOffsetY
        )
        let actualTerminalFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertEqual(
            actualTerminalFrame.minX,
            expectedTerminalFrame.minX,
            accuracy: 0.01
        )
        XCTAssertEqual(
            actualTerminalFrame.minY,
            expectedTerminalFrame.minY,
            accuracy: 0.01
        )
        XCTAssertEqual(
            actualTerminalFrame.width,
            expectedTerminalFrame.width,
            accuracy: 0.01
        )
        XCTAssertEqual(
            actualTerminalFrame.height,
            expectedTerminalFrame.height,
            accuracy: 0.01
        )
    }

    func testLockedMarginCoverageFadesWhenPanReclassifiesItOnScreen()
        throws {
        let returnsCachedImage = Box(true)
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    returnsCachedImage.value
                        ? (
                            imageSources.thumbnailDescriptor,
                            .thumbnail,
                            image
                        )
                        : nil
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.filter {
                representationID in
                guard let representation = session
                    .cachedSourceRepresentations[representationID],
                      fixture.collectionView.indexPath(
                          for: representation.cell
                      ) != nil,
                      let destinationItem = session.reassignments[
                          representation.itemIndex
                      ],
                      let destinationFrame = fixture.destinationLayout
                          .itemFrame(at: destinationItem) else {
                    return false
                }
                return destinationFrame.minY
                    >= fixture.viewportView.bounds.maxY
            }.min { lhs, rhs in
                let lhsItem = session.cachedSourceRepresentations[lhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let rhsItem = session.cachedSourceRepresentations[rhs]
                    .flatMap { session.reassignments[$0.itemIndex] }
                let lhsY = lhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                let rhsY = rhsItem.flatMap {
                    fixture.destinationLayout.itemFrame(at: $0)?.minY
                } ?? .greatestFiniteMagnitude
                return lhsY < rhsY
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let indexPath = try XCTUnwrap(
            fixture.collectionView.indexPath(for: representation.cell)
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let settleProgress: CGFloat = 0.5
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        fixture.renderer.didConfigureCell(
            representation.cell,
            at: indexPath
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(representation.cell.alpha, 1, accuracy: 0.000_001)

        returnsCachedImage.value = false
        let targetOffsetY = destinationFrame.minY
            - fixture.viewportView.bounds.maxY + 1
        let onScreenPanDeltaY = -targetOffsetY
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        contentContainer.layer.add(opacity, forKey: "opacity")
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            presentationProgress: 0,
            panDeltaY: onScreenPanDeltaY
        ))
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertNil(contentContainer.layer.animation(forKey: "opacity"))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            presentationProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertEqual(session.lastContentFadeAlpha, 0, accuracy: 0.000_001)
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))

        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNotNil(session.cellFrameCorrections[representationID])
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        _ = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertEqual(
            representation.cell.alpha,
            1,
            accuracy: 0.000_001
        )
        let inactiveContentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        XCTAssertEqual(
            inactiveContentContainer.alpha,
            0,
            accuracy: 0.000_001
        )
    }

    func testShapeMaskKeepsLockedMarginSourceCutOut() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            sourceColumnCount: 3,
            destinationColumnCount: 2,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 1_200,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        for _ in 0 ..< 200 {
            _ = fixture.renderer.drainMaterializationWork()
            if session.currentPhantomPlan?.shapeCoverage != nil,
               !session.marginCoverageRepresentationIDs.isEmpty,
               !session.sourceCoverageRefreshIsDirty,
               !session.destinationPlanRefreshIsDirty,
               !session.phantomShapeRefreshIsDirty {
                break
            }
        }
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        let representationID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.first {
                representationID in
                guard let representation = session
                    .cachedSourceRepresentations[representationID],
                      fixture.collectionView.indexPath(
                          for: representation.cell
                      ) != nil,
                      let destinationItem = session.reassignments[
                          representation.itemIndex
                      ],
                      let destinationFrame = fixture.destinationLayout
                          .itemFrame(at: destinationItem) else {
                    return false
                }
                let sourceFrame = representation.cell.convert(
                    representation.cell.bounds,
                    to: fixture.collectionView
                )
                return destinationFrame.minY
                    >= fixture.viewportView.bounds.maxY
                    && shapeView.frame.contains(CGPoint(
                        x: sourceFrame.midX,
                        y: sourceFrame.midY
                    ))
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let indexPath = try XCTUnwrap(
            fixture.collectionView.indexPath(for: representation.cell)
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let terminalScale = fixture.planeRequest.transitionLayout
            .itemWidthRatio
        let settleProgress: CGFloat = 0.5
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        fixture.renderer.didConfigureCell(
            representation.cell,
            at: indexPath
        )

        let sourceFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.collectionView
        )
        let sourcePoint = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let shapeCoverage = try XCTUnwrap(
            session.currentPhantomPlan?.shapeCoverage
        )
        XCTAssertTrue(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )
        XCTAssertEqual(representation.cell.alpha, 1, accuracy: 0.000_001)
        XCTAssertTrue(shapeView.frame.contains(sourcePoint))
        XCTAssertFalse(shapeCoverage.excludedFrames.contains(sourceFrame))
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(sourceFrame)
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            sourcePoint,
            in: shapeView
        ))

        let onScreenPanDeltaY = -(
            destinationFrame.minY - fixture.viewportView.bounds.maxY + 1
        )
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: settleProgress,
            panDeltaY: onScreenPanDeltaY
        ))
        let reclassifiedFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        _ = try XCTUnwrap(
            session.cellFrameCorrections[representationID]?
                .correction.destinationVisibilityProgress
        )
        XCTAssertEqual(
            representation.cell.alpha,
            1,
            accuracy: 0.000_001
        )
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                reclassifiedFrame
            )
        )
    }

    /// The seam has to stay `spacing` wide at any plane scale, so cells grow
    /// above unity and shrink below it. A pinch that reverses through unity
    /// must pick up the opposite correction, never keep the stale one, and must
    /// be back to identity at exactly unity.
    func testSeamCompensationTracksThePlaneThroughUnity() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 200,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(
                    x: fixture.viewportView.bounds.midX,
                    y: fixture.viewportView.bounds.midY
                ),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        XCTAssertGreaterThan(fixture.sourceLayout.interItemSpacing, 0)

        func factors(scale: CGFloat, settleProgress: CGFloat) -> [CGFloat] {
            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: scale,
                settleProgress: settleProgress,
                panDeltaY: 0
            ))
            return session.cachedSourceRepresentations
                .filter { session.cellFrameCorrections[$0.key] == nil }
                .map { $0.value.cell.transform.a }
        }

        let grown = factors(scale: 2, settleProgress: 0.5)
        XCTAssertFalse(grown.isEmpty)
        for factor in grown {
            XCTAssertGreaterThan(
                factor,
                1,
                "magnifying the plane grows the cells to hold the seams"
            )
        }

        let shrunk = factors(scale: 0.9, settleProgress: 0)
        XCTAssertFalse(shrunk.isEmpty)
        for factor in shrunk {
            XCTAssertLessThan(
                factor,
                1,
                "below unity the cells shrink to hold the seams open"
            )
        }

        for factor in factors(scale: 1, settleProgress: 0) {
            XCTAssertEqual(
                factor,
                1,
                accuracy: 0.000_001,
                "at unity there is no excess to hide"
            )
        }
    }

    func testCorrectedCellSeamsSurviveDecoupledScaleAndProgress() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(x: 160, y: 320),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let pair = try XCTUnwrap(
            horizontallyAdjacentCorrectedCells(
                fixture: fixture,
                session: session
            ),
            "Expected adjacent corrected source cells"
        )
        let settleProgress: CGFloat = 0.2
        let driftProgress: CGFloat = 0.7
        let scale = pow(
            fixture.planeRequest.transitionLayout.itemWidthRatio,
            driftProgress
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: settleProgress,
            panDeltaY: 0
        ))
        let expectedSpacing = fixture.sourceLayout.interItemSpacing
            + settleProgress * (
                fixture.destinationLayout.interItemSpacing
                    - fixture.sourceLayout.interItemSpacing
            )
        XCTAssertEqual(
            horizontalScreenGap(
                left: pair.left,
                right: pair.right,
                in: fixture.viewportView
            ),
            expectedSpacing,
            accuracy: onePixelAccuracy(in: fixture.viewportView)
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))
        assertTransform(pair.left.transform, equals: .identity)
        assertTransform(pair.right.transform, equals: .identity)
        XCTAssertFalse(session.hasCellFrameCorrectionTransforms)
    }

    func testPresentationProgressDrivesFadeIndependentlyFromGeometryProgress()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representation = try XCTUnwrap(
            session.cellFrameCorrections.first.flatMap {
                session.cachedSourceRepresentations[$0.key]
            }
        )
        let contentContainer = try XCTUnwrap(
            transitionContentContainer(in: representation.cell)
        )
        let scale = fixture.planeRequest.transitionLayout.itemWidthRatio
        let firstGeometryProgress: CGFloat = 0.2
        let secondGeometryProgress: CGFloat = 0.7
        let firstPresentationProgress: CGFloat = 0.6
        let secondPresentationProgress: CGFloat = 0.8

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: firstGeometryProgress,
            presentationProgress: firstPresentationProgress,
            panDeltaY: 0
        ))
        let firstGeometryTransform = representation.cell.transform
        let firstCollectionTransform = fixture.collectionView.transform
        let destinationPlanBuildCount = fixture.renderer
            .destinationPlanBuildCount
        let sourceCoverageBuildCount = fixture.renderer
            .sourceCoverageBuildCount
        let foregroundEligibilityReconciliationCount = fixture.renderer
            .foregroundEligibilityReconciliationCount
        XCTAssertEqual(
            session.lastSettleProgress,
            firstGeometryProgress,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            session.lastContentFadeAlpha,
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: firstPresentationProgress
            ),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            contentContainer.alpha,
            session.lastContentFadeAlpha,
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderInteractionFade(
            id: fixture.planeRequest.id,
            presentationProgress: secondPresentationProgress
        ))
        assertTransform(
            representation.cell.transform,
            equals: firstGeometryTransform
        )
        assertTransform(
            fixture.collectionView.transform,
            equals: firstCollectionTransform
        )
        XCTAssertEqual(
            session.lastSettleProgress,
            firstGeometryProgress,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            fixture.renderer.destinationPlanBuildCount,
            destinationPlanBuildCount
        )
        XCTAssertEqual(
            fixture.renderer.sourceCoverageBuildCount,
            sourceCoverageBuildCount
        )
        XCTAssertEqual(
            fixture.renderer.foregroundEligibilityReconciliationCount,
            foregroundEligibilityReconciliationCount
        )
        XCTAssertEqual(
            contentContainer.alpha,
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: secondPresentationProgress
            ),
            accuracy: 0.000_001
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: secondGeometryProgress,
            presentationProgress: secondPresentationProgress,
            panDeltaY: 0
        ))
        XCTAssertNotEqual(
            representation.cell.transform,
            firstGeometryTransform
        )
        XCTAssertEqual(
            session.lastSettleProgress,
            secondGeometryProgress,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            contentContainer.alpha,
            PlayerBrowserGridCrossfade.incomingContentAlpha(
                settleProgress: secondPresentationProgress
            ),
            accuracy: 0.000_001
        )
    }

    func testLateCorrectedCellsReceiveSeamCompensationOnRebasedPlane()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(x: 160, y: 320),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        let installationScale: CGFloat = 0.8
        XCTAssertTrue(fixture.renderer.renderZoom(
            planeID: nil,
            scale: installationScale,
            panDeltaY: 0,
            sourceLayout: fixture.sourceLayout
        ))
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let pair = try XCTUnwrap(
            horizontallyAdjacentCorrectedCells(
                fixture: fixture,
                session: session
            ),
            "Expected adjacent corrected source cells"
        )

        XCTAssertEqual(session.lastSettleProgress, 0)
        XCTAssertEqual(
            horizontalScreenGap(
                left: pair.left,
                right: pair.right,
                in: fixture.viewportView
            ),
            fixture.sourceLayout.interItemSpacing,
            // The fractional Photos-matched spacing rounds cell frames to the
            // pixel grid, so a measured pair gap legitimately varies by up to
            // one device pixel.
            accuracy: onePixelAccuracy(in: fixture.viewportView)
        )
        XCTAssertTrue(session.hasCellFrameCorrectionTransforms)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.7,
            settleProgress: 0.25,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            horizontalScreenGap(
                left: pair.left,
                right: pair.right,
                in: fixture.viewportView
            ),
            fixture.sourceLayout.interItemSpacing,
            accuracy: onePixelAccuracy(in: fixture.viewportView)
        )
    }

    func testLateMaterializedCellsReceiveCurrentSeamCompensation() throws {
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 12,
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let sourceCell = try XCTUnwrap(
            session.sourceOverscanCells.values.first
        )
        let phantomCell = try XCTUnwrap(session.phantomCells.values.first)
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let sourceSpacing = fixture.sourceLayout.interItemSpacing
        let expectedSourceScaleX = 1
            + sourceSpacing * (appliedScaleX - 1)
                / (sourceCell.bounds.width * appliedScaleX)
        let expectedSourceScaleY = 1
            + sourceSpacing * (appliedScaleY - 1)
                / (sourceCell.bounds.height * appliedScaleY)
        XCTAssertEqual(
            sourceCell.transform.a,
            expectedSourceScaleX,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            sourceCell.transform.d,
            expectedSourceScaleY,
            accuracy: 0.000_001
        )
        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            panDeltaY: 0
        )
        let destinationSpacing = fixture.destinationLayout.interItemSpacing
        let expectedPhantomScaleX = 1
            + destinationSpacing
                * (appliedScaleX / terminalPlane.scaleX - 1)
                / (phantomCell.bounds.width * appliedScaleX)
        let expectedPhantomScaleY = 1
            + destinationSpacing
                * (appliedScaleY / terminalPlane.scaleY - 1)
                / (phantomCell.bounds.height * appliedScaleY)
        XCTAssertEqual(
            phantomCell.transform.a,
            expectedPhantomScaleX,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            phantomCell.transform.d,
            expectedPhantomScaleY,
            accuracy: 0.000_001
        )
    }

    func testRemovedCorrectionImmediatelyReturnsToSourceSeam()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 12,
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let scale: CGFloat = 0.8
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: 0
        ))
        let correctedRepresentationIDs = Set(
            session.cellFrameCorrections.keys
        )
        XCTAssertFalse(correctedRepresentationIDs.isEmpty)

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0,
            panDeltaY: -fixture.viewportView.bounds.height
        ))
        let removedRepresentationID = try XCTUnwrap(
            correctedRepresentationIDs.first {
                representationID in
                session.cellFrameCorrections[representationID] == nil
                    && !session.preparedRepresentationIDs.contains(
                        representationID
                    )
                    && session.detailedSourceCellItems[representationID] == nil
                    && session.cachedSourceRepresentations[representationID]?
                        .cell.superview != nil
            }
        )
        let cell = try XCTUnwrap(
            session.cachedSourceRepresentations[removedRepresentationID]?.cell
        )
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let spacing = fixture.sourceLayout.interItemSpacing
        let expectedScaleX = 1 + spacing * (appliedScaleX - 1)
            / (cell.bounds.width * appliedScaleX)
        let expectedScaleY = 1 + spacing * (appliedScaleY - 1)
            / (cell.bounds.height * appliedScaleY)
        XCTAssertEqual(cell.transform.a, expectedScaleX, accuracy: 0.000_001)
        XCTAssertEqual(cell.transform.d, expectedScaleY, accuracy: 0.000_001)
    }

    func testCorrectedCellLandsExactlyOnLargeDestinationAtTerminal()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
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
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.cellFrameCorrections.keys.first {
                session.cachedSourceRepresentations[$0] != nil
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let destinationItem = try XCTUnwrap(
            session.reassignments[representation.itemIndex]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let terminalScale = fixture.planeRequest.transitionLayout
            .itemWidthRatio

        XCTAssertEqual(
            fixture.sourceLayout.interItemSpacing,
            fixture.destinationLayout.interItemSpacing,
            "the seam is constant across grid modes, matching Photos"
        )
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 1,
            panDeltaY: 0
        ))
        let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
            scale: terminalScale,
            panDeltaY: 0
        )
        let expectedFrame = destinationFrame.offsetBy(
            dx: -fixture.collectionView.contentOffset.x,
            dy: -terminalPlane.incomingContentOffsetY
        )
        let actualFrame = representation.cell.convert(
            representation.cell.bounds,
            to: fixture.viewportView
        )
        XCTAssertEqual(actualFrame.minX, expectedFrame.minX, accuracy: 0.01)
        XCTAssertEqual(actualFrame.minY, expectedFrame.minY, accuracy: 0.01)
        XCTAssertEqual(actualFrame.width, expectedFrame.width, accuracy: 0.01)
        XCTAssertEqual(
            actualFrame.height,
            expectedFrame.height,
            accuracy: 0.01
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
            $0.alpha == 1
        })
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testSourceOverscanIsLayeredAboveDestinationPhantoms() throws {
        let fixture = try makeFixture(
            itemCount: 6,
            showsSourceCell: true,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)

        let session = try activeSession(fixture)
        let source = try XCTUnwrap(session.sourceOverscanCells[3])
        let phantom = try XCTUnwrap(session.phantomCells[5])
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let visibleSource = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
        )
        let overlap = source.frame.intersection(phantom.frame)
        XCTAssertFalse(overlap.isNull)
        XCTAssertGreaterThan(overlap.width, 0)
        XCTAssertGreaterThan(overlap.height, 0)

        let shapeIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: shapeView)
        )
        let phantomIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: phantom)
        )
        let sourceIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: source)
        )
        let visibleSourceIndex = try XCTUnwrap(
            fixture.collectionView.subviews.firstIndex(of: visibleSource)
        )
        XCTAssertLessThan(shapeIndex, phantomIndex)
        XCTAssertLessThan(phantomIndex, sourceIndex)
        XCTAssertLessThan(sourceIndex, visibleSourceIndex)
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

    func testUniformMappingRefreshesSelectionInsideRetainedDetailCoverage()
        throws {
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 100, height: 1)
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let departingCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let enteringItem = PlayerBrowserGridRenderBudget.maximumVisualCellCount
        let enteringCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: enteringItem, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        let departingFrame = departingCell.frame
        enteringCell.frame = CGRect(
            x: departingFrame.minX,
            y: fixture.viewportView.bounds.maxY + 8,
            width: departingFrame.width,
            height: departingFrame.height
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))
        let session = try activeSession(fixture)
        let initialSelectedItems = session.selectedSourceItems
        let detailCoverageRect = try XCTUnwrap(
            session.viewportDetailCoverage.installedRect
        )
        XCTAssertTrue(initialSelectedItems.contains(0))
        XCTAssertFalse(initialSelectedItems.contains(enteringItem))
        departingCell.frame = enteringCell.frame
        enteringCell.frame = departingFrame

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))

        XCTAssertEqual(
            session.viewportDetailCoverage.installedRect,
            detailCoverageRect
        )
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(
            enteringItem
        ))
        XCTAssertTrue(session.selectedSourceItems.contains(enteringItem))
        XCTAssertTrue(session.viewportSelectedSourceItems.isSubset(
            of: session.selectedSourceItems
        ))
        XCTAssertEqual(
            session.selectedSourceItems.count,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        XCTAssertFalse(
            initialSelectedItems.subtracting(session.selectedSourceItems).isEmpty
        )
        XCTAssertTrue(session.assignedDestinationItems.isEmpty)
    }

    func testRetainedDetailCoverageSelectsRegisteredHorizontalBufferCell()
        throws {
        let fixture = try makeFixture(
            itemCount: 30,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            anchorItemIndex: 0
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let edgeItem = 4
        let edgeCell = try XCTUnwrap(
            fixture.collectionView.cellForItem(
                at: IndexPath(item: edgeItem, section: 0)
            ) as? MobilePlayerCollectionBrowserCell
        )
        edgeCell.frame.origin.x = fixture.viewportView.bounds.maxX + 8
        let edgeRepresentationID = ObjectIdentifier(edgeCell)
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        XCTAssertEqual(
            session.cachedSourceRepresentations[edgeRepresentationID]?.itemIndex,
            edgeItem
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))

        let detailCoverageRect = try XCTUnwrap(
            session.viewportDetailCoverage.installedRect
        )
        XCTAssertTrue(
            session.cachedSourceRepresentations[edgeRepresentationID]?.cell
                === edgeCell
        )
        XCTAssertFalse(session.viewportSelectedSourceItems.contains(edgeItem))
        XCTAssertNil(session.cellFrameCorrections[edgeRepresentationID])
        edgeCell.frame.origin.x = 0

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))

        XCTAssertEqual(
            session.viewportDetailCoverage.installedRect,
            detailCoverageRect
        )
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(edgeItem))
    }

    func testDegradedMappingReleasesClaimWhenSelectedSourceLeaves() throws {
        var ratios = Array(repeating: CGFloat(1), count: 12)
        ratios[3] = 2
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            anchorItemIndex: 0,
            heightToWidthRatios: ratios
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
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
        laterCell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
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
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertFalse(session.selectedSourceItems.contains(1))
        XCTAssertEqual(session.reassignments[0], destinationItem)

        firstCell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        laterCell.frame = visibleFrame
        fixture.renderer.didConfigureCell(
            laterCell,
            at: IndexPath(item: 1, section: 0)
        )
        drainQueuedWork(fixture)

        XCTAssertFalse(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.selectedSourceItems.contains(1))
        XCTAssertNil(session.reassignments[0])
        XCTAssertEqual(session.reassignments[1], destinationItem)
        XCTAssertTrue(session.assignedDestinationItems.contains(
            destinationItem
        ))
    }

    func testDegradedMappingPrioritizesVisibleSourceOverBufferedSource()
        throws {
        var ratios = Array(repeating: CGFloat(1), count: 12)
        ratios[3] = 2
        let fixture = try makeFixture(
            itemCount: ratios.count,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
            anchorItemIndex: 0,
            heightToWidthRatios: ratios
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
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
        laterCell.frame = bufferedFrame
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
        fixture.renderer.didConfigureCell(
            firstCell,
            at: IndexPath(item: 0, section: 0)
        )
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.selectedSourceItems.contains(1))
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(0))
        XCTAssertFalse(session.viewportSelectedSourceItems.contains(1))
        XCTAssertEqual(session.reassignments[0], destinationItem)
        XCTAssertNil(session.reassignments[1])
        let detailCoverageRect = try XCTUnwrap(
            session.viewportDetailCoverage.installedRect
        )

        firstCell.frame = bufferedFrame
        laterCell.frame = visibleFrame
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: request.id,
            scale: 1,
            settleProgress: 0,
            panDeltaY: 0
        ))
        drainQueuedWork(fixture)

        XCTAssertEqual(
            session.viewportDetailCoverage.installedRect,
            detailCoverageRect
        )
        XCTAssertTrue(session.selectedSourceItems.contains(0))
        XCTAssertTrue(session.selectedSourceItems.contains(1))
        XCTAssertFalse(session.viewportSelectedSourceItems.contains(0))
        XCTAssertTrue(session.viewportSelectedSourceItems.contains(1))
        XCTAssertNil(session.reassignments[0])
        XCTAssertEqual(session.reassignments[1], destinationItem)
        XCTAssertTrue(session.assignedDestinationItems.contains(
            destinationItem
        ))
    }

    func testDegradedMappingRequeuesBufferedCollisionLoserWhenClaimFrees()
        throws {
        let image = makeImage()
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
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let firstSourceFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: 0)
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
        var sourceItemsByDestination = [Int: [Int]]()
        for sourceItem in 0 ..< ratios.count {
            guard let sourceFrame = fixture.sourceLayout.itemFrame(
                at: sourceItem
            ), let destinationItem = fixture.destinationLayout
                .nearestItemIndex(
                    to: request.latticeMap.destinationPoint(
                        fromSource: CGPoint(
                            x: sourceFrame.midX,
                            y: sourceFrame.midY
                        )
                    ),
                    tolerance: fixture.destinationLayout.interItemSpacing + 1
                ) else {
                continue
            }
            sourceItemsByDestination[destinationItem, default: []].append(
                sourceItem
            )
        }
        let collision = try XCTUnwrap(
            sourceItemsByDestination.sorted { $0.key < $1.key }.first {
                entry in
                entry.value.count >= 2
                    && sourceItemsByDestination.keys.contains {
                        $0 != entry.key
                    }
            }
        )
        let collisionItems = collision.value.sorted()
        let winnerItem = collisionItems[0]
        let loserItem = collisionItems[1]
        let visibleItem = try XCTUnwrap(
            sourceItemsByDestination.sorted { $0.key < $1.key }.first {
                $0.key != collision.key
            }?.value.first
        )
        var cells = [Int: MobilePlayerCollectionBrowserCell]()
        for item in 0 ..< ratios.count {
            cells[item] = try XCTUnwrap(
                fixture.collectionView.cellForItem(
                    at: IndexPath(item: item, section: 0)
                ) as? MobilePlayerCollectionBrowserCell
            )
        }
        let winnerCell = try XCTUnwrap(cells[winnerItem])
        let loserCell = try XCTUnwrap(cells[loserItem])
        let visibleCell = try XCTUnwrap(cells[visibleItem])
        for cell in cells.values {
            cell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        }
        let bufferedY = fixture.viewportView.bounds.maxY + 8
        winnerCell.frame = CGRect(
            x: 0,
            y: bufferedY,
            width: winnerCell.bounds.width,
            height: winnerCell.bounds.height
        )
        loserCell.frame = CGRect(
            x: winnerCell.frame.maxX
                + fixture.sourceLayout.interItemSpacing,
            y: bufferedY,
            width: loserCell.bounds.width,
            height: loserCell.bounds.height
        )
        visibleCell.frame = CGRect(
            x: 0,
            y: 0,
            width: visibleCell.bounds.width,
            height: visibleCell.bounds.height
        )

        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(request))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let loserRepresentationID = ObjectIdentifier(loserCell)
        let initialViewportItems = session.viewportSelectedSourceItems
        XCTAssertTrue(initialViewportItems.contains(visibleItem))
        XCTAssertFalse(initialViewportItems.contains(winnerItem))
        XCTAssertFalse(initialViewportItems.contains(loserItem))
        XCTAssertEqual(session.reassignments[winnerItem], collision.key)
        XCTAssertNil(session.reassignments[loserItem])
        XCTAssertEqual(
            session.detailedSourceCellItems[loserRepresentationID],
            loserItem
        )
        XCTAssertFalse(
            session.preparedRepresentationIDs.contains(loserRepresentationID)
        )

        winnerCell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        fixture.renderer.didConfigureCell(
            winnerCell,
            at: IndexPath(item: winnerItem, section: 0)
        )

        XCTAssertEqual(
            session.viewportSelectedSourceItems,
            initialViewportItems
        )
        XCTAssertFalse(session.selectedSourceItems.contains(winnerItem))
        XCTAssertTrue(session.selectedSourceItems.contains(loserItem))
        XCTAssertNil(session.reassignments[winnerItem])
        XCTAssertEqual(session.reassignments[loserItem], collision.key)
        XCTAssertNil(session.detailedSourceCellItems[loserRepresentationID])
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.preparedRepresentationIDs.contains(loserRepresentationID)
        )
        XCTAssertEqual(
            session.detailedSourceCellItems[loserRepresentationID],
            loserItem
        )
        XCTAssertTrue(primaryTransitionImage(in: loserCell) === image)
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

    func testTransitionImageCompletionProcessesDuringTrackingRunLoopMode() throws {
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
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
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

        XCTAssertTrue(runMainTrackingRunLoop {
            fixture.renderer.pendingMaterializationWorkCount > 0
                || sourceCell.contentView.subviews.count
                    > originalSubviewIDs.count
        })
        if fixture.renderer.pendingMaterializationWorkCount > 0 {
            XCTAssertEqual(
                sourceCell.contentView.subviews.map(ObjectIdentifier.init),
                originalSubviewIDs
            )
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertGreaterThan(
            sourceCell.contentView.subviews.count,
            originalSubviewIDs.count
        )
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

    /// Source cells and phantoms sit side by side on screen but are laid out
    /// on lattices whose spacings differ by the pitch ratio. Both are held to
    /// their own layout's spacing, so at any scale the whole screen shows one
    /// seam width — Photos never shows two.
    func testPhantomAndSourceSeamsMatchAtEveryScale() throws {
        let fixture = try makeFixture(
            itemCount: 1_000,
            sourceColumnCount: 1,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceCell: true,
            anchorItemIndex: 12
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
                viewportPoint: CGPoint(
                    x: fixture.viewportView.bounds.midX,
                    y: fixture.viewportView.bounds.midY
                ),
                relativeItemPoint: CGPoint(x: 0.5, y: 0.5),
                baseContentOffsetY: 0
            )
        )
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let layout = fixture.planeRequest.transitionLayout
        let terminalScale = layout.itemWidthRatio
        XCTAssertLessThan(terminalScale, 1, "1->3 shrinks the tiles")
        XCTAssertEqual(
            fixture.sourceLayout.interItemSpacing,
            fixture.destinationLayout.interItemSpacing,
            "the seam is constant across grid modes, matching Photos"
        )

        var compared = 0
        for step in 0...8 {
            let progress = CGFloat(step) / 8
            let scale = 1 + (terminalScale - 1) * progress
            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: scale,
                settleProgress: progress,
                panDeltaY: 0
            ))
            drainQueuedWork(fixture)
            guard let phantom = session.phantomCells.values.first(where: {
                $0.bounds.width > 0
            }) else {
                continue
            }
            guard let source = session.sourceOverscanCells.values
                .first(where: { $0.bounds.width > 0 }) else {
                continue
            }
            // Both lattices share the source pitch, and the plane scales both
            // by the same factor, so it cancels: equal rendered widths in
            // content space is exactly one seam width on screen.
            let sourceWidth = source.bounds.width * source.transform.a
            let phantomWidth = phantom.bounds.width * phantom.transform.a
            XCTAssertEqual(
                phantomWidth,
                sourceWidth,
                accuracy: 0.05,
                "seams differ at scale \(scale): phantom renders "
                    + "\(phantomWidth)pt wide, source \(sourceWidth)pt"
            )
            compared += 1
        }
        XCTAssertGreaterThan(compared, 4, "not enough scales compared")
        XCTAssertEqual(
            fixture.planeRequest.crossfade.driftProgress(
                forScale: terminalScale
            ),
            1,
            accuracy: 0.000_001
        )
    }

    func testNineColumnViewportKeepsPlaceholderCoverageBeyondCellBudget()
        throws {
        let fixture = try makeFixture(
            itemCount: 500,
            sourceColumnCount: 5,
            destinationColumnCount: 9,
            destinationMode: .nineColumns,
            anchorItemIndex: 0
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let plan = try XCTUnwrap(session.currentPhantomPlan)
        let visibleItems = Set(
            fixture.destinationLayout.candidateItemIndices(
                intersecting: fixture.viewportView.bounds
            ).filter {
                fixture.destinationLayout.itemFrame(at: $0)?
                    .intersects(fixture.viewportView.bounds) == true
            }
        )
        let coveredItems = Set(plan.cellCandidates.map(
            \.destinationItemIndex
        )).union(plan.shapeCandidates.map(\.destinationItemIndex))

        XCTAssertGreaterThan(
            visibleItems.count,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        XCTAssertEqual(
            plan.cellCandidates.count,
            PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
        XCTAssertTrue(visibleItems.isSubset(of: coveredItems))
        XCTAssertTrue(
            !plan.shapeCandidates.isEmpty || plan.shapeCoverage != nil
        )
        XCTAssertNotNil(session.phantomShapeView)
    }

    func testPhantomShapeUsesCurrentSeamCompensation() throws {
        let fixture = try makeFixture(
            itemCount: 1,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            destinationMode: .fiveColumns,
            anchorItemIndex: 0,
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
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
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)

        func assertShapeSize() throws {
            let candidate = try XCTUnwrap(
                session.currentPhantomPlan?.cellCandidates.first
            )
            let shapeView = try XCTUnwrap(session.phantomShapeView)
            let layers = try phantomShapeLayers(in: shapeView)
            let pathBounds = try XCTUnwrap(layers.candidates.path)
                .boundingBoxOfPath
            let appliedScaleX = fixture.collectionView.transform.a
            let appliedScaleY = fixture.collectionView.transform.d
            let terminalPlane = fixture.planeRequest.crossfade.outgoingPlane(
                scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
                panDeltaY: 0
            )
            let spacing = fixture.destinationLayout.interItemSpacing
            let expectedWidth = max(
                candidate.sourceFrame.width
                    + spacing * (appliedScaleX / terminalPlane.scaleX - 1)
                        / appliedScaleX,
                candidate.sourceFrame.width * 0.5
            )
            let expectedHeight = max(
                candidate.sourceFrame.height
                    + spacing * (appliedScaleY / terminalPlane.scaleY - 1)
                        / appliedScaleY,
                candidate.sourceFrame.height * 0.5
            )
            XCTAssertEqual(pathBounds.width, expectedWidth, accuracy: 0.001)
            XCTAssertEqual(pathBounds.height, expectedHeight, accuracy: 0.001)
        }

        try assertShapeSize()
        let initialBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.7,
            settleProgress: 0,
            panDeltaY: 0
        ))
        try assertShapeSize()
        let scaledBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        XCTAssertGreaterThan(
            scaledBuildCount,
            initialBuildCount
        )

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.7,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertEqual(
            fixture.renderer.phantomShapeStructureBuildCount,
            scaledBuildCount
        )
    }

    func testPhantomShapeMaskTracksCorrectedSourceWithoutRebuildingStructure()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 1_000,
            sourceColumnCount: 1,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 100, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        for _ in 0 ..< 100 where session.cellFrameCorrections.isEmpty {
            _ = fixture.renderer.drainMaterializationWork()
        }
        XCTAssertFalse(session.cellFrameCorrections.isEmpty)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        let shapeCoverage = try XCTUnwrap(
            session.currentPhantomPlan?.shapeCoverage
        )

        let scale: CGFloat = 0.8
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.8,
            panDeltaY: 0
        ))
        let firstCorrectedFrames = session.cellFrameCorrections.values
            .compactMap { entry -> (
                cell: MobilePlayerCollectionBrowserCell,
                frame: CGRect
            )? in
                guard let cell = entry.cell
                    as? MobilePlayerCollectionBrowserCell else {
                    return nil
                }
                return (
                    cell,
                    cell.convert(cell.bounds, to: fixture.collectionView)
                )
            }
        XCTAssertFalse(firstCorrectedFrames.isEmpty)
        let structuralLayer: CAShapeLayer
        switch shapeCoverage {
        case .repeatedRows:
            structuralLayer = layers.repeatedRow
        case .solid:
            structuralLayer = layers.solidCoverage
        }
        XCTAssertNotNil(structuralLayer.path)
        let structureBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: scale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let changedSource = try XCTUnwrap(
            firstCorrectedFrames.compactMap { entry -> CGRect? in
                guard session.cellFrameCorrections[
                    ObjectIdentifier(entry.cell)
                ] != nil else {
                    return nil
                }
                let secondFrame = entry.cell.convert(
                    entry.cell.bounds,
                    to: fixture.collectionView
                )
                guard entry.frame != secondFrame,
                      fixture.renderer.phantomShapeMaskedFrames.contains(
                          secondFrame
                      ) else {
                    return nil
                }
                return secondFrame
            }.min { lhs, rhs in
                if lhs.minY == rhs.minY {
                    return lhs.minX < rhs.minX
                }
                return lhs.minY < rhs.minY
            }
        )
        XCTAssertEqual(
            fixture.renderer.phantomShapeStructureBuildCount,
            structureBuildCount
        )
        XCTAssertGreaterThan(
            fixture.renderer.phantomShapeMaskBuildCount,
            maskBuildCount
        )
        XCTAssertNotNil((shapeView.layer.mask as? CAShapeLayer)?.path)
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                changedSource
            )
        )
    }

    func testPhantomShapeMaskUnionsCoveredSlotAndCorrectedSource() throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            showsSourceCell: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: { 0 }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        let sourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells.first
                as? MobilePlayerCollectionBrowserCell
        )
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        for _ in 0 ..< 100 {
            _ = fixture.renderer.drainMaterializationWork()
            if !session.cellFrameCorrections.isEmpty,
               !session.sourceCoverageRefreshIsDirty,
               !session.destinationPlanRefreshIsDirty,
               !session.phantomShapeRefreshIsDirty {
                break
            }
        }
        XCTAssertFalse(session.cellFrameCorrections.isEmpty)
        let terminalScale = fixture.planeRequest.transitionLayout.itemWidthRatio
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: terminalScale,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let shapeCoverage = try XCTUnwrap(
            session.currentPhantomPlan?.shapeCoverage
        )
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let representationID = ObjectIdentifier(sourceCell)
        let destinationItem = try XCTUnwrap(
            session.sourceCoverage.readyDestinationByRepresentation[
                representationID
            ]
        )
        let destinationFrame = try XCTUnwrap(
            fixture.destinationLayout.itemFrame(at: destinationItem)
        )
        let mappedFrame = fixture.planeRequest.latticeMap.sourceRect(
            fromDestination: destinationFrame
        )
        let currentFrame = sourceCell.convert(
            sourceCell.bounds,
            to: fixture.collectionView
        )
        let mappedPoint = CGPoint(x: mappedFrame.midX, y: mappedFrame.midY)
        let currentPoint = CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        XCTAssertTrue(shapeCoverage.excludedFrames.contains(mappedFrame))
        XCTAssertNotEqual(mappedFrame, currentFrame)
        XCTAssertTrue(shapeView.frame.contains(mappedPoint))
        XCTAssertTrue(shapeView.frame.contains(currentPoint))
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                mappedFrame
            )
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                currentFrame
            )
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            mappedPoint,
            in: shapeView
        ))
        XCTAssertFalse(try phantomShapeMaskContains(
            currentPoint,
            in: shapeView
        ))
    }

    func testSolidShapePaintsPendingCandidateUntilInstallation() throws {
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(true)
        let fixture = try makeFixture(
            itemCount: 10_000,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            clock: {
                defer { clockCalls.value += 1 }
                guard limitsDrainToOneJob.value else { return 0 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let plan = try XCTUnwrap(session.currentPhantomPlan)
        let shapeCoverage = try XCTUnwrap(plan.shapeCoverage)
        guard case .solid = shapeCoverage else {
            return XCTFail("Expected solid phantom shape coverage")
        }
        let candidate = try XCTUnwrap(plan.cellCandidates.first)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let layers = try phantomShapeLayers(in: shapeView)
        let point = CGPoint(
            x: candidate.sourceFrame.midX,
            y: candidate.sourceFrame.midY
        )
        let localPoint = CGPoint(
            x: point.x - shapeView.frame.minX,
            y: point.y - shapeView.frame.minY
        )

        XCTAssertNil(shapeView.layer.mask)
        XCTAssertTrue(try XCTUnwrap(layers.solidCoverage.path).contains(
            localPoint
        ))

        for _ in 0 ..< 100 {
            let installedItems = Set(session.phantomCells.keys)
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
            let newItems = Set(session.phantomCells.keys).subtracting(
                installedItems
            )
            if let newItem = newItems.first,
               let newPhantom = session.phantomCells[newItem] {
                let newFrame = newPhantom.convert(
                    newPhantom.bounds,
                    to: fixture.collectionView
                )
                XCTAssertTrue(
                    fixture.renderer.phantomShapeMaskedFrames.contains(newFrame)
                )
                XCTAssertFalse(try phantomShapeMaskContains(
                    CGPoint(x: newFrame.midX, y: newFrame.midY),
                    in: shapeView
                ))
                XCTAssertEqual(
                    fixture.renderer.phantomShapeStructureBuildCount,
                    structureBuildCount
                )
                XCTAssertEqual(
                    fixture.renderer.phantomShapeMaskBuildCount,
                    maskBuildCount + 1
                )
            }
            if session.phantomCells[candidate.destinationItemIndex] != nil {
                break
            }
        }

        let phantom = try XCTUnwrap(
            session.phantomCells[candidate.destinationItemIndex]
        )
        limitsDrainToOneJob.value = false
        clockCalls.value = 0
        _ = fixture.renderer.drainMaterializationWork()
        let installedFrame = phantom.convert(
            phantom.bounds,
            to: fixture.collectionView
        )
        XCTAssertGreaterThanOrEqual(
            fixture.renderer.phantomShapeMaskedFrames.filter {
                $0.contains(CGPoint(
                    x: installedFrame.midX,
                    y: installedFrame.midY
                ))
            }.count,
            2
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(x: installedFrame.midX, y: installedFrame.midY),
            in: shapeView
        ))
    }

    func testLateCandidateOnlyPhantomIsMaskedWhenDrainBudgetExpires()
        throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 1,
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        let plan = try XCTUnwrap(session.currentPhantomPlan)
        XCTAssertNil(plan.shapeCoverage)
        let candidate = try XCTUnwrap(plan.cellCandidates.first)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        XCTAssertNil(shapeView.layer.mask)
        let structureBuildCount = fixture.renderer
            .phantomShapeStructureBuildCount
        let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount

        clockCalls.value = 0
        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertTrue(result.stoppedForTimeLimit)
        XCTAssertTrue(session.phantomShapeRefreshIsDirty)
        let phantom = try XCTUnwrap(
            session.phantomCells[candidate.destinationItemIndex]
        )
        let frame = phantom.convert(
            phantom.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(fixture.renderer.phantomShapeMaskedFrames.contains(frame))
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(x: frame.midX, y: frame.midY),
            in: shapeView
        ))
        XCTAssertEqual(
            fixture.renderer.phantomShapeStructureBuildCount,
            structureBuildCount
        )
        XCTAssertEqual(
            fixture.renderer.phantomShapeMaskBuildCount,
            maskBuildCount + 1
        )
    }

    func testBudgetedDetailMarginIsMaskedBeforeDrainReturns() throws {
        let clockCalls = Counter()
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            sourceColumnCount: 3,
            destinationColumnCount: 2,
            destinationMode: .threeColumns,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 1_200,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        let preinstalledMarginID = try XCTUnwrap(
            session.marginCoverageRepresentationIDs.first
        )
        let preinstalledRepresentation = try XCTUnwrap(
            session.cachedSourceRepresentations[preinstalledMarginID]
        )
        let preinstalledFrame = preinstalledRepresentation.cell.convert(
            preinstalledRepresentation.cell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                preinstalledMarginID
            )
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                preinstalledFrame
            )
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(x: preinstalledFrame.midX, y: preinstalledFrame.midY),
            in: shapeView
        ))

        var preparedMarginID: ObjectIdentifier?
        for _ in 0 ..< 100 where preparedMarginID == nil {
            let trackedMarginIDs = session.marginCoverageRepresentationIDs
                .intersection(
                    session.unpreparedMarginTrackingRepresentationIDs
                )
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            let result = fixture.renderer.drainMaterializationWork()
            let newlyPreparedMarginIDs = trackedMarginIDs.intersection(
                session.preparedRepresentationIDs
            ).intersection(
                session.marginCoverageRepresentationIDs
            ).subtracting(
                session.unpreparedMarginTrackingRepresentationIDs
            )
            guard let representationID = newlyPreparedMarginIDs.first else {
                continue
            }
            preparedMarginID = representationID
            XCTAssertEqual(result.processedCount, 1)
            XCTAssertTrue(result.stoppedForTimeLimit)
            XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
            let representation = try XCTUnwrap(
                session.cachedSourceRepresentations[representationID]
            )
            let frame = representation.cell.convert(
                representation.cell.bounds,
                to: fixture.collectionView
            )
            XCTAssertTrue(
                fixture.renderer.phantomShapeMaskedFrames.contains(frame)
            )
            XCTAssertFalse(try phantomShapeMaskContains(
                CGPoint(x: frame.midX, y: frame.midY),
                in: shapeView
            ))
            XCTAssertEqual(
                fixture.renderer.phantomShapeStructureBuildCount,
                structureBuildCount
            )
            XCTAssertEqual(
                fixture.renderer.phantomShapeMaskBuildCount,
                maskBuildCount
            )
        }
        XCTAssertNotNil(preparedMarginID)
    }

    func testBudgetedReadyCorrectionIsMaskedBeforeSourceCoverageRefresh()
        throws {
        let clockCalls = Counter()
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 10_000,
            showsSourceGrid: true,
            providesContentAccess: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 1_000, height: 1),
            imageAccess: .init(
                cachedImage: { imageSources, _ in
                    (imageSources.thumbnailDescriptor, .thumbnail, image)
                },
                loadImage: { _, _ in {} }
            ),
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        XCTAssertTrue(session.cellFrameCorrections.isEmpty)
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            presentationProgress: 0.2,
            panDeltaY: 0
        ))
        XCTAssertEqual(session.lastContentFadeAlpha, 0, accuracy: 0.000_001)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        var selectedCorrectionRepresentationID: ObjectIdentifier?

        for _ in 0 ..< 100 where selectedCorrectionRepresentationID == nil {
            let preparedRepresentationIDs = session.preparedRepresentationIDs
            let maskedFrames = fixture.renderer.phantomShapeMaskedFrames
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            let result = fixture.renderer.drainMaterializationWork()
            let newlyPreparedRepresentationIDs = session
                .preparedRepresentationIDs
                .subtracting(preparedRepresentationIDs)
            guard let representationID = newlyPreparedRepresentationIDs
                .first(where: { representationID in
                    guard !session.lockedFallbackRepresentationIDs.contains(
                        representationID
                    ),
                    session.sourceCoverage
                        .readyDestinationByRepresentation[representationID]
                        == nil,
                    let entry = session.cellFrameCorrections[
                        representationID
                    ],
                    entry.cell.superview != nil else {
                        return false
                    }
                    let frame = entry.cell.convert(
                        entry.cell.bounds,
                        to: fixture.collectionView
                    )
                    return shapeView.frame.contains(CGPoint(
                        x: frame.midX,
                        y: frame.midY
                    )) && !maskedFrames.contains(frame)
                }) else {
                continue
            }
            selectedCorrectionRepresentationID = representationID
            XCTAssertEqual(result.processedCount, 1)
            XCTAssertTrue(result.stoppedForTimeLimit)
            XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
            XCTAssertEqual(
                fixture.renderer.phantomShapeStructureBuildCount,
                structureBuildCount
            )
            XCTAssertEqual(
                fixture.renderer.phantomShapeMaskBuildCount,
                maskBuildCount + 1
            )
        }
        let correctedRepresentationID = try XCTUnwrap(
            selectedCorrectionRepresentationID
        )
        let corrected = try XCTUnwrap(
            session.cellFrameCorrections[correctedRepresentationID]
        )
        let frame = corrected.cell.convert(
            corrected.cell.bounds,
            to: fixture.collectionView
        )
        let correctedCell = try XCTUnwrap(
            corrected.cell as? MobilePlayerCollectionBrowserCell
        )
        let point = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(shapeView.frame.contains(point))
        XCTAssertTrue(fixture.renderer.phantomShapeMaskedFrames.contains(frame))
        XCTAssertFalse(try phantomShapeMaskContains(point, in: shapeView))

        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            presentationProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertNotNil(
            session.sourceCoverage.readyDestinationByRepresentation[
                correctedRepresentationID
            ]
        )
        XCTAssertEqual(correctedCell.alpha, 1, accuracy: 0.000_001)
        let positiveFadeFrame = correctedCell.convert(
            correctedCell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                positiveFadeFrame
            )
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            CGPoint(
                x: positiveFadeFrame.midX,
                y: positiveFadeFrame.midY
            ),
            in: shapeView
        ))
    }

    func testNoPlanePhantomShapeMasksVisibleSourceCells() throws {
        let limitsDeferredDrain = Box(false)
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 2_000,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            showsSourceCell: true,
            anchorItemIndex: 0,
            uniformImageSize: CGSize(width: 100, height: 1),
            clock: {
                guard limitsDeferredDrain.value else { return 0 }
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
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
        let session = try activeSession(fixture)
        XCTAssertNotNil(session.currentPhantomPlan?.shapeCoverage)
        let visibleSourceCell = try XCTUnwrap(
            fixture.collectionView.visibleCells
                .compactMap { $0 as? MobilePlayerCollectionBrowserCell }
                .first
        )
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        XCTAssertNotNil((shapeView.layer.mask as? CAShapeLayer)?.path)
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let spacing = fixture.sourceLayout.interItemSpacing
        XCTAssertEqual(
            visibleSourceCell.transform.a,
            1 + spacing * (appliedScaleX - 1)
                / (visibleSourceCell.bounds.width * appliedScaleX),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            visibleSourceCell.transform.d,
            1 + spacing * (appliedScaleY - 1)
                / (visibleSourceCell.bounds.height * appliedScaleY),
            accuracy: 0.000_001
        )
        let sourceFrame = visibleSourceCell.convert(
            visibleSourceCell.bounds,
            to: fixture.collectionView
        )
        XCTAssertTrue(shapeView.bounds.contains(CGPoint(
            x: sourceFrame.midX - shapeView.frame.minX,
            y: sourceFrame.midY - shapeView.frame.minY
        )))
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(sourceFrame)
        )

        let indexPath = try XCTUnwrap(
            fixture.collectionView.indexPath(for: visibleSourceCell)
        )
        visibleSourceCell.transform = .identity
        fixture.renderer.willDisplayCell(
            visibleSourceCell,
            at: indexPath
        )
        XCTAssertEqual(
            visibleSourceCell.transform.a,
            1 + spacing * (appliedScaleX - 1)
                / (visibleSourceCell.bounds.width * appliedScaleX),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            visibleSourceCell.transform.d,
            1 + spacing * (appliedScaleY - 1)
                / (visibleSourceCell.bounds.height * appliedScaleY),
            accuracy: 0.000_001
        )
        XCTAssertTrue(
            fixture.renderer.phantomShapeMaskedFrames.contains(
                visibleSourceCell.convert(
                    visibleSourceCell.bounds,
                    to: fixture.collectionView
                )
            )
        )

        let departedSlotFrame = try XCTUnwrap(
            fixture.sourceLayout.itemFrame(at: indexPath.item)
        )
        let departedSlotPoint = CGPoint(
            x: departedSlotFrame.midX,
            y: departedSlotFrame.midY
        )
        XCTAssertTrue(
            try XCTUnwrap(session.currentPhantomPlan?.shapeCoverage)
                .excludedFrames.contains(departedSlotFrame)
        )
        XCTAssertFalse(try phantomShapeMaskContains(
            departedSlotPoint,
            in: shapeView
        ))

        for _ in 0 ..< 100
        where fixture.renderer.pendingMaterializationWorkCount > 0 {
            _ = fixture.renderer.drainMaterializationWork()
        }
        let departedFrame = visibleSourceCell.convert(
            visibleSourceCell.bounds,
            to: fixture.collectionView
        )
        fixture.collectionView.dataSource = nil
        fixture.collectionView.reloadData()
        fixture.collectionView.layoutIfNeeded()
        XCTAssertFalse(fixture.collectionView.visibleCells.contains {
            $0 === visibleSourceCell
        })

        limitsDeferredDrain.value = true
        clockCalls.value = 0
        fixture.renderer.didEndDisplayingCell(
            visibleSourceCell,
            at: indexPath
        )
        XCTAssertTrue(session.managedCellPlanRefreshIsPending)
        let viewportBounds = fixture.viewportView.bounds
        fixture.viewportView.bounds = .zero
        let stalledRefresh = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(stalledRefresh.processedCount, 0)
        XCTAssertTrue(session.managedCellPlanRefreshIsPending)

        fixture.viewportView.bounds = viewportBounds
        clockCalls.value = 0
        let refresh = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(refresh.processedCount, 1)
        XCTAssertFalse(session.managedCellPlanRefreshIsPending)
        XCTAssertFalse(
            fixture.renderer.phantomShapeMaskedFrames.contains(departedFrame)
        )
        let departedSlotLocalPoint = CGPoint(
            x: departedSlotPoint.x - shapeView.frame.minX,
            y: departedSlotPoint.y - shapeView.frame.minY
        )
        XCTAssertTrue(shapeView.bounds.contains(departedSlotLocalPoint))
        XCTAssertTrue(try phantomShapeMaskContains(
            departedSlotPoint,
            in: shapeView
        ))
    }

    func testLateNoPlaneSourceOverscanReceivesCurrentSeamCompensation()
        throws {
        let clockCalls = Counter()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 5,
            showsSourceGrid: true,
            anchorItemIndex: 12,
            clock: {
                defer { clockCalls.value += 1 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(
            fixture,
            gestureAnchor: GridModeGestureAnchor(
                tokenIndex: fixture.planeRequest.anchorTokenIndex,
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
        let session = try activeSession(fixture)
        let shapeView = try XCTUnwrap(session.phantomShapeView)
        for _ in 0 ..< 100 where session.sourceOverscanCells.isEmpty {
            let installedItems = Set(session.sourceOverscanCells.keys)
            let structureBuildCount = fixture.renderer
                .phantomShapeStructureBuildCount
            let maskBuildCount = fixture.renderer.phantomShapeMaskBuildCount
            clockCalls.value = 0
            _ = fixture.renderer.drainMaterializationWork()
            let newItems = Set(session.sourceOverscanCells.keys).subtracting(
                installedItems
            )
            if let newItem = newItems.first,
               let newSource = session.sourceOverscanCells[newItem] {
                let newFrame = newSource.convert(
                    newSource.bounds,
                    to: fixture.collectionView
                )
                XCTAssertTrue(
                    fixture.renderer.phantomShapeMaskedFrames.contains(newFrame)
                )
                XCTAssertFalse(try phantomShapeMaskContains(
                    CGPoint(x: newFrame.midX, y: newFrame.midY),
                    in: shapeView
                ))
                XCTAssertEqual(
                    fixture.renderer.phantomShapeStructureBuildCount,
                    structureBuildCount
                )
                XCTAssertEqual(
                    fixture.renderer.phantomShapeMaskBuildCount,
                    maskBuildCount + 1
                )
            }
        }
        let sourceCell = try XCTUnwrap(
            session.sourceOverscanCells.values.first
        )
        let appliedScaleX = fixture.collectionView.transform.a
        let appliedScaleY = fixture.collectionView.transform.d
        let spacing = fixture.sourceLayout.interItemSpacing
        XCTAssertEqual(
            sourceCell.transform.a,
            1 + spacing * (appliedScaleX - 1)
                / (sourceCell.bounds.width * appliedScaleX),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            sourceCell.transform.d,
            1 + spacing * (appliedScaleY - 1)
                / (sourceCell.bounds.height * appliedScaleY),
            accuracy: 0.000_001
        )
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
            SourceBrowserLayout(browserLayout: fixture.destinationLayout),
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
                return clockCalls.value < 2 ? 0 : 0.005
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
        // Reconfiguring a cell must not advance the generation: that would
        // discard every queued phantom, and the replan that re-enqueues them
        // is the lowest-priority job in the drain.
        XCTAssertEqual(
            session.destinationPlaneCellPlanGeneration,
            planGeneration
        )

        let refreshResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )
        XCTAssertEqual(refreshResult.processedCount, 8)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 2)
        XCTAssertGreaterThan(
            session.destinationPlaneCellPlanGeneration,
            planGeneration,
            "the replan itself advances the generation"
        )
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

        let result = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

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

    func testDrainRunsAtBurstBudgetAfterGestureRender() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        fixture.renderer.requestGestureMaterializationBurst()
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            32
        )

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertEqual(result.processedCount, 32)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        XCTAssertLessThanOrEqual(
            fixture.renderer.drainMaterializationWork().processedCount,
            8
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testGestureDrainScalesItsTimeBudgetWithFrameDuration() throws {
        func processedCount(frameDuration: CFTimeInterval) throws -> Int {
            let time = Box<CFTimeInterval>(0)
            let fixture = try makeFixture(clock: {
                defer { time.value += 0.000_25 }
                return time.value
            })
            begin(fixture)
            XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
            XCTAssertTrue(fixture.renderer.renderSettle(
                id: fixture.planeRequest.id,
                scale: 0.8,
                settleProgress: 0.5,
                panDeltaY: 0
            ))
            fixture.renderer.requestGestureMaterializationBurst()
            time.value = 0

            let result = fixture.renderer.drainMaterializationWork(
                frameDuration: frameDuration
            )
            _ = fixture.renderer.finish(preservingCarryover: false)
            XCTAssertTrue(result.stoppedForTimeLimit)
            return result.processedCount
        }

        let thirtyHertzCount = try processedCount(frameDuration: 1.0 / 30)
        let sixtyHertzCount = try processedCount(frameDuration: 1.0 / 60)
        let oneTwentyHertzCount = try processedCount(frameDuration: 1.0 / 120)

        XCTAssertEqual(thirtyHertzCount, sixtyHertzCount)
        XCTAssertGreaterThan(sixtyHertzCount, oneTwentyHertzCount)
    }

    func testInteractionFadePreservesOnlyTheNextMaterializationBurst() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        fixture.renderer.requestGestureMaterializationBurst()
        XCTAssertTrue(fixture.renderer.renderInteractionFade(
            id: fixture.planeRequest.id,
            presentationProgress: 0.6
        ))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )

        let result = fixture.renderer.drainMaterializationWork()

        XCTAssertGreaterThan(result.processedCount, 8)
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            0
        )
        XCTAssertLessThanOrEqual(
            fixture.renderer.drainMaterializationWork().processedCount,
            8
        )
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testMaterializationBurstRequestWithoutWorkIsIgnored() throws {
        let fixture = try makeFixture(clock: { 0 })
        begin(fixture)
        fixture.renderer.requestGestureMaterializationBurst()
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: 0.8,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        XCTAssertGreaterThan(
            fixture.renderer.pendingMaterializationWorkCount,
            8
        )

        XCTAssertLessThanOrEqual(
            fixture.renderer.drainMaterializationWork().processedCount,
            8
        )
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
                return clockCalls.value < 2 ? 0 : 0.005
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
        let sourceResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

        XCTAssertLessThanOrEqual(sourceResult.processedCount, 8)
        XCTAssertFalse(session.sourceOverscanCells.isEmpty)
        XCTAssertGreaterThan(imageLoadCount.value, 0)
        XCTAssertFalse(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(session.destinationPlanRefreshIsDirty)
        _ = fixture.renderer.finish(preservingCarryover: false)
    }

    func testDrainFlushesDeferredClassificationPaint() throws {
        let fixture = try makeFixture(
            providesContentAccess: true,
            anchorItemIndex: 0,
            imageAccess: .init(
                cachedImage: { _, _ in nil },
                loadImage: { _, _ in {} }
            )
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            presentationProgress: 0.5,
            panDeltaY: 0
        ))
        let session = try activeSession(fixture)
        drainQueuedWork(fixture)
        let sourceRepresentationIDs = Set(
            session.sourceOverscanCells.values.map(ObjectIdentifier.init)
        )
        XCTAssertFalse(sourceRepresentationIDs.isEmpty)
        let unpreparedSourceRepresentationIDs = sourceRepresentationIDs
            .intersection(
                session.unpreparedMarginTrackingRepresentationIDs
            )
        let visibleRepresentationID = try XCTUnwrap(
            unpreparedSourceRepresentationIDs.first { representationID in
                guard let itemIndex = session.cachedSourceRepresentations[
                    representationID
                ]?.itemIndex else {
                    return false
                }
                return session.viewportSelectedSourceItems.contains(itemIndex)
            }
        )
        let bufferedRepresentationID = try XCTUnwrap(
            unpreparedSourceRepresentationIDs.first { representationID in
                guard let itemIndex = session.cachedSourceRepresentations[
                    representationID
                ]?.itemIndex else {
                    return false
                }
                return !session.viewportSelectedSourceItems.contains(itemIndex)
            }
        )
        session.deferClassificationPaint(for: bufferedRepresentationID)
        session.deferClassificationPaint(for: visibleRepresentationID)

        let paintResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 1, time: 1)
        )
        XCTAssertEqual(paintResult.processedCount, 1)
        XCTAssertFalse(
            session.deferredClassificationPaintRepresentationIDs.contains(
                visibleRepresentationID
            )
        )
        XCTAssertTrue(
            session.deferredClassificationPaintRepresentationIDs.contains(
                bufferedRepresentationID
            )
        )
        drainQueuedWork(fixture)
        XCTAssertTrue(
            session.deferredClassificationPaintRepresentationIDs.isEmpty
        )
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
                    return clockCalls.value < 2 ? 0 : 0.005
                case 1:
                    return clockCalls.value == 0 ? 0 : 0.005
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

    func testLateSourceOverscanOutsideRepresentationRectStaysUnclassified()
        throws {
        let clockCalls = Counter()
        let limitsDrainToOneJob = Box(true)
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            providesContentAccess: true,
            anchorItemIndex: 3,
            clock: {
                defer { clockCalls.value += 1 }
                guard limitsDrainToOneJob.value else { return 0 }
                return clockCalls.value < 2 ? 0 : 0.005
            }
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        XCTAssertTrue(fixture.renderer.renderSettle(
            id: fixture.planeRequest.id,
            scale: fixture.planeRequest.transitionLayout.itemWidthRatio,
            settleProgress: 0.5,
            panDeltaY: 0
        ))
        let session = try activeSession(fixture)
        let sourceRect = fixture.collectionView.convert(
            fixture.viewportView.bounds,
            from: fixture.viewportView
        ).insetBy(dx: 0, dy: -fixture.viewportView.bounds.height / 2)
        var lateSource: MobilePlayerCollectionBrowserCell?
        for _ in 0 ..< 100 where lateSource == nil {
            let existingIDs = Set(
                session.sourceOverscanCells.values.map(ObjectIdentifier.init)
            )
            clockCalls.value = 0
            let result = fixture.renderer.drainMaterializationWork()
            lateSource = session.sourceOverscanCells.values.first { cell in
                !existingIDs.contains(ObjectIdentifier(cell))
                    && !cell.convert(cell.bounds, to: fixture.collectionView)
                        .intersects(sourceRect)
            }
            if lateSource != nil {
                XCTAssertTrue(result.stoppedForTimeLimit)
            }
        }
        let source = try XCTUnwrap(lateSource)
        let representationID = ObjectIdentifier(source)

        XCTAssertTrue(session.sourceCoverageRefreshIsDirty)
        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertTrue(
            session.lockedFallbackRepresentationIDs.contains(representationID)
        )
        XCTAssertEqual(source.alpha, 1, accuracy: 0.000_001)

        limitsDrainToOneJob.value = false
        drainQueuedWork(fixture)

        XCTAssertFalse(
            session.marginCoverageRepresentationIDs.contains(representationID)
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertFalse(
            session.unpreparedMarginTrackingRepresentationIDs.contains(
                representationID
            )
        )
        XCTAssertEqual(source.alpha, 1, accuracy: 0.000_001)
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

        let result = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

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
                return clockCalls.value < 2 ? 0 : 0.005
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
            return clockCalls.value < 2 ? 0 : 0.002_001
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
            return clockCalls.value == 0 ? 0 : 0.005
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

        let expiredResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

        XCTAssertEqual(expiredResult.processedCount, 0)
        XCTAssertTrue(expiredResult.stoppedForTimeLimit)
        XCTAssertEqual(fixture.renderer.destinationPlanBuildCount, 1)

        returnsExpiredTime.value = false
        let refreshResult = fixture.renderer.drainMaterializationWork(
            budgetOverride: (jobs: 8, time: 0.002)
        )

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

    func testReconfiguredRepresentationClearsCorrectionAndReindexesRegistry()
        throws {
        let image = makeImage()
        let fixture = try makeFixture(
            itemCount: 300,
            sourceColumnCount: 3,
            destinationColumnCount: 1,
            destinationMode: .large,
            showsSourceGrid: true,
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
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        drainQueuedWork(fixture)
        let session = try activeSession(fixture)
        let representationID = try XCTUnwrap(
            session.cellFrameCorrections.keys.first {
                session.cachedSourceRepresentations[$0] != nil
            }
        )
        let representation = try XCTUnwrap(
            session.cachedSourceRepresentations[representationID]
        )
        let cell = representation.cell
        let previousItem = representation.itemIndex
        let replacementItem = previousItem == 0 ? 1 : 0

        cell.frame.origin.y = fixture.viewportView.bounds.maxY * 4
        cell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: replacementItem
            ),
            itemCount: 300,
            imageSources: nil,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        fixture.renderer.didConfigureCell(
            cell,
            at: IndexPath(item: replacementItem, section: 0)
        )

        XCTAssertEqual(
            session.cachedSourceRepresentations[representationID]?.itemIndex,
            replacementItem
        )
        XCTAssertNil(session.cellFrameCorrections[representationID])
        XCTAssertFalse(session.cachedSourceRepresentations.values.contains {
            $0.itemIndex == previousItem && $0.cell === cell
        })
        fixture.renderer.didEndDisplayingCell(
            cell,
            at: IndexPath(item: replacementItem, section: 0)
        )
        XCTAssertNil(session.cachedSourceRepresentations[representationID])
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

    func testNarrowRTLViewportUsesMirroredSourceGeometry() throws {
        let fixture = try makeFixture(
            itemCount: 30,
            sourceColumnCount: 5,
            destinationColumnCount: 3,
            destinationMode: .threeColumns,
            showsSourceGrid: true
        )
        defer { _ = fixture.renderer.finish(preservingCarryover: false) }
        fixture.collectionView.semanticContentAttribute = .forceRightToLeft
        fixture.collectionView.layoutIfNeeded()
        let viewportWidth = fixture.sourceLayout.itemWidth
        fixture.viewportView.frame.size.width = viewportWidth
        fixture.viewportView.bounds.size.width = viewportWidth
        let geometry = fixture.collectionView.visualGeometry(
            for: fixture.sourceLayout
        )
        for itemIndex in 0..<30 {
            guard let cell = fixture.collectionView.cellForItem(
                at: IndexPath(item: itemIndex, section: 0)
            ), let frame = geometry.itemFrame(at: itemIndex) else {
                continue
            }
            cell.frame = frame
        }
        begin(fixture)
        XCTAssertTrue(fixture.renderer.installPlane(fixture.planeRequest))
        let session = try activeSession(fixture)

        XCTAssertEqual(
            session.viewportSelectedSourceItems,
            Set([4, 9, 14, 19, 24, 29])
        )
    }
}

nonisolated final class MobilePlayerCollectionBrowserPinchFrameCoalescerTests: XCTestCase {}

@MainActor
extension MobilePlayerCollectionBrowserPinchFrameCoalescerTests {
    private func makeFrame(
        scale: CGFloat,
        location: CGPoint
    ) -> GridModePinchFrame {
        GridModePinchFrame(scale: scale, viewLocation: location)
    }

    func testTerminationFlushAppliesLatestChangedFrameOnce() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        coalescer.seed(makeFrame(
            scale: 1.2,
            location: CGPoint(x: 160, y: 320)
        ))
        let latestFrame = makeFrame(
            scale: 1.01,
            location: CGPoint(x: 160, y: 320)
        )
        coalescer.stage(latestFrame)

        coalescer.flush()
        coalescer.flush()

        XCTAssertEqual(appliedFrames, [latestFrame])
        XCTAssertEqual(latestFrame.sample.centroidY, latestFrame.viewLocation.y)
    }

    func testTerminationFlushAppliesBeganFrameWithoutChangedFrame() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        let beganFrame = makeFrame(
            scale: 1.2,
            location: CGPoint(x: 160, y: 320)
        )
        coalescer.seed(beganFrame)

        coalescer.flush()
        coalescer.flush()

        XCTAssertEqual(appliedFrames, [beganFrame])
    }

    func testInvalidationDropsPendingFrame() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        coalescer.stage(makeFrame(
            scale: 1.2,
            location: CGPoint(x: 160, y: 320)
        ))

        coalescer.invalidate()
        coalescer.flush()

        XCTAssertTrue(appliedFrames.isEmpty)
    }

    func testStagedFrameAppliesDuringTrackingRunLoopMode() {
        var appliedFrames = [GridModePinchFrame]()
        let coalescer = GridModePinchFrameCoalescer {
            appliedFrames.append($0)
        }
        defer { coalescer.invalidate() }
        let firstFrame = makeFrame(
            scale: 1.1,
            location: CGPoint(x: 140, y: 280)
        )
        let latestFrame = makeFrame(
            scale: 1.2,
            location: CGPoint(x: 150, y: 300)
        )
        coalescer.stage(firstFrame)
        coalescer.stage(latestFrame)

        XCTAssertTrue(runMainTrackingRunLoop {
            !appliedFrames.isEmpty
        })
        XCTAssertEqual(appliedFrames, [latestFrame])
    }
}
