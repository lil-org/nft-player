// ∅ 2026 lil org

import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobilePlayerCollectionBrowserCoordinatorContractTests:
    XCTestCase {}

@MainActor
private final class CollectionBrowserDecodeVariantState {
    var value: DownloadableMediaImageDecodeVariant

    init(_ value: DownloadableMediaImageDecodeVariant) {
        self.value = value
    }
}

@MainActor
private final class SettlementAcceptance {
    var value = false
}

#if DEBUG
@MainActor
private final class GridModeContractPinchGestureRecognizer:
    UIPinchGestureRecognizer {
    var reportedState: UIGestureRecognizer.State = .possible
    var reportedLocation = CGPoint.zero

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { reportedState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint {
        reportedLocation
    }
}

@MainActor
private final class GridModeContractState {
    var browseSnapshot: PlayerCollectionBrowseSnapshot?
    var layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    var focusedTokenIndex: Int?

    init(
        browseSnapshot: PlayerCollectionBrowseSnapshot,
        layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    ) {
        self.browseSnapshot = browseSnapshot
        self.layoutAspectState = layoutAspectState
        focusedTokenIndex = browseSnapshot.initialTokenIndex
    }
}

@MainActor
private final class GridModeContractDataSource: NSObject,
    UICollectionViewDataSource {
    private let collectionId: String
    private let itemCount: Int

    init(collectionId: String, itemCount: Int) {
        self.collectionId = collectionId
        self.itemCount = itemCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        itemCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "grid-mode-contract",
            for: indexPath
        ) as! MobilePlayerCollectionBrowserCell
        cell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: collectionId,
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

@MainActor
private final class GridModeContractScrollDelegate: NSObject,
    UICollectionViewDelegate {
    weak var coordinator: MobilePlayerCollectionBrowserGridModeCoordinator?
    var lifecycleStates = [
        MobilePlayerCollectionBrowserGridModeCoordinator
            .LifecycleStateForTesting
    ]()

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let coordinator else { return }
        lifecycleStates.append(coordinator.lifecycleStateForTesting)
    }
}

@MainActor
private struct GridModeCoordinatorContractFixture {
    let coordinator: MobilePlayerCollectionBrowserGridModeCoordinator
    let collectionView: MobilePlayerCollectionBrowserCollectionView
    let viewportView: UIView
    let collectionLayout: MobilePlayerCollectionBrowserLayout
    let scrollCoordinator: MobilePlayerCollectionBrowserScrollCoordinator
    let imagePipeline: MobilePlayerCollectionBrowserImagePipeline
    let state: GridModeContractState
    let dataSource: GridModeContractDataSource
    let hostViewController: UIViewController
    let window: UIWindow

    func tearDown() {
        coordinator.invalidate()
        imagePipeline.invalidate()
        scrollCoordinator.invalidate()
        window.isHidden = true
        window.rootViewController = nil
    }
}
#endif

@MainActor
extension MobilePlayerCollectionBrowserCoordinatorContractTests {
    func testThumbnailWindowPreparationOrderTracksLatestCommit() {
        let order = MobileCollectionBrowseThumbnailWindowPreparationOrder()
        let firstClaim = order.claim()
        let secondClaim = order.claim()

        XCTAssertTrue(order.commitIfNewer(firstClaim))
        XCTAssertTrue(order.commitIfNewer(secondClaim))
        XCTAssertFalse(order.commitIfNewer(firstClaim))

        let thirdClaim = order.claim()
        order.supersedePendingClaims()
        XCTAssertFalse(order.commitIfNewer(thirdClaim))
        XCTAssertTrue(order.commitIfNewer(order.claim()))
    }

    private func makeImageContentAccess(
        visibleIndexPaths: @escaping @MainActor () -> [IndexPath] = { [] },
        cell: @escaping @MainActor (
            IndexPath
        ) -> MobilePlayerCollectionBrowserCell? = { _ in nil },
        visibleCells: @escaping @MainActor ()
            -> [MobilePlayerCollectionBrowserCell] = { [] },
        viewportRenderCells: @escaping @MainActor (Int?)
            -> [MobilePlayerCollectionBrowserCell] = { _ in [] },
        collectionID: @escaping @MainActor () -> String? = { nil },
        requiredImageQuality: @escaping @MainActor ()
            -> CollectionBrowseImageQuality = { .large },
        imageDecodeVariant: @escaping @MainActor ()
            -> DownloadableMediaImageDecodeVariant = { .full },
        baseColumnCount: @escaping @MainActor () -> Int = { 5 },
        configuredPrefetchStride: @escaping @MainActor () -> Int = { 9 },
        configuredColumnCount: @escaping @MainActor () -> Int = { 5 },
        isRendererActive: @escaping @MainActor () -> Bool = { false },
        isPreparedTransitionActive: @escaping @MainActor () -> Bool = {
            false
        },
        isForegroundActive: @escaping @MainActor () -> Bool = { true },
        prepareThumbnailWindow: @escaping @MainActor (
            MobilePlayerCollectionBrowserImagePipeline
                .ThumbnailWindowPreparation,
            @escaping @MainActor () -> Bool,
            @escaping @MainActor (
                MobileCollectionBrowseThumbnailWindowPreparationResult
            ) -> Void
        ) -> Void = { _, shouldApply, completion in
            completion(shouldApply() ? .committed : .planned)
        },
        cancelThumbnailWindowPreparation: @escaping @MainActor () -> Void = {},
        thumbnailWindowPreparationDidFinish:
            @escaping @MainActor () -> Void = {}
    ) -> MobilePlayerCollectionBrowserImagePipeline.ContentAccess {
        .init(
            visibleIndexPaths: visibleIndexPaths,
            cell: cell,
            visibleCells: visibleCells,
            viewportRenderCells: viewportRenderCells,
            collectionID: collectionID,
            requiredImageQuality: requiredImageQuality,
            imageDecodeVariant: imageDecodeVariant,
            baseColumnCount: baseColumnCount,
            configuredPrefetchStride: configuredPrefetchStride,
            configuredColumnCount: configuredColumnCount,
            isRendererActive: isRendererActive,
            isApplyingPosition: { false },
            isPreparedTransitionActive: isPreparedTransitionActive,
            isForegroundActive: isForegroundActive,
            projectedTokenRange: { _, _, _ in nil },
            prepareThumbnailWindow: {
                preparation, shouldApply, completion in
                prepareThumbnailWindow(
                    preparation,
                    shouldApply,
                    completion
                )
            },
            cancelThumbnailWindowPreparation:
                cancelThumbnailWindowPreparation,
            thumbnailWindowPreparationDidFinish:
                thumbnailWindowPreparationDidFinish
        )
    }

    private func makeScrollContentAccess(
        publishFocusedPagePosition: @escaping @MainActor (
            PlayerPagePosition
        ) -> Void = { _ in },
        publishSettledPosition: @escaping @MainActor (
            PlayerCollectionScrollPublication
        ) -> Bool = { _ in true },
        performScheduledScrollObservation: @escaping @MainActor () -> Void = {},
        scrollMotionAnimationDidExpire: @escaping @MainActor () -> Void = {}
    ) -> MobilePlayerCollectionBrowserScrollCoordinator.ContentAccess {
        .init(
            pagePosition: { PlayerPagePosition(position: $0) },
            publishFocusedPagePosition: publishFocusedPagePosition,
            publishSettledPosition: publishSettledPosition,
            performScheduledScrollObservation:
                performScheduledScrollObservation,
            scrollMotionAnimationDidExpire: scrollMotionAnimationDidExpire
        )
    }

#if DEBUG
    private func makeGridModeAspectProfile(
        snapshot: PlayerCollectionBrowseSnapshot,
        columnCount: Int,
        profile: ThumbnailAspectRatioProfile
    ) -> MobilePlayerBrowserAspectProfile {
        switch profile {
        case let .uniform(aspectRatio):
            return MobilePlayerBrowserAspectProfile(
                itemCount: snapshot.itemCount,
                uniformImageSize: aspectRatio.size,
                columnCount: columnCount
            )
        case let .variable(aspectRatios):
            return MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: aspectRatios.map {
                    CGFloat($0.height) / CGFloat($0.width)
                },
                columnCount: columnCount
            )
        }
    }

    private func makeGridModeCoordinatorFixture() throws
        -> GridModeCoordinatorContractFixture {
        let collectionId = try XCTUnwrap(
            SuggestedItemsService.visibleItems.first {
                $0.internalSlug == "in_your_dreams"
            }?.id
        )
        let itemCount = CollectionCatalog.tokenCount(
            specificCollectionId: collectionId
        )
        let snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: collectionId,
            itemCount: itemCount,
            initialTokenIndex: 0
        )
        let thumbnailProfile = try XCTUnwrap(
            MobileCollectionBrowseMediaResolver
                .collectionBrowseThumbnailAspectRatioProfile(
                    snapshot: snapshot
                )
        )
        let viewportSize = CGSize(width: 390, height: 844)
        let currentAspectProfile = makeGridModeAspectProfile(
            snapshot: snapshot,
            columnCount: MobileCollectionBrowserGridMode.defaultMode
                .columnCount,
            profile: thumbnailProfile
        )
        let currentLayout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            displayScale: 3,
            aspectProfile: currentAspectProfile
        ))
        let collectionLayout = MobilePlayerCollectionBrowserLayout()
        collectionLayout.browserLayout = currentLayout
        let collectionView = MobilePlayerCollectionBrowserCollectionView(
            frame: CGRect(origin: .zero, size: viewportSize),
            collectionViewLayout: collectionLayout
        )
        collectionView.register(
            MobilePlayerCollectionBrowserCell.self,
            forCellWithReuseIdentifier: "grid-mode-contract"
        )
        let dataSource = GridModeContractDataSource(
            collectionId: collectionId,
            itemCount: itemCount
        )
        collectionView.dataSource = dataSource

        let hostViewController = UIViewController()
        hostViewController.view.frame = CGRect(
            origin: .zero,
            size: viewportSize
        )
        hostViewController.view.addSubview(collectionView)
        let foregroundScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        let window = UIWindow(windowScene: foregroundScene)
        window.frame = CGRect(origin: .zero, size: viewportSize)
        window.rootViewController = hostViewController
        window.isHidden = false
        window.layoutIfNeeded()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let state = GridModeContractState(
            browseSnapshot: snapshot,
            layoutAspectState: .init(
                aspectProfile: currentAspectProfile,
                fallbackSpec: PlayerMediaPlaceholderSpec(
                    thumbnailAspectRatio: nil
                )
            )
        )
        let scrollCoordinator =
            MobilePlayerCollectionBrowserScrollCoordinator()
        scrollCoordinator.configure(contentAccess: makeScrollContentAccess())
        scrollCoordinator.setActive(true)
        scrollCoordinator.hasFinishedInitialPositioning = true
        scrollCoordinator.focusedTokenIndex = snapshot.initialTokenIndex
        scrollCoordinator.lastScrollOffsetY = collectionView.contentOffset.y
        let imagePipeline = MobilePlayerCollectionBrowserImagePipeline()
        imagePipeline.configure(contentAccess: makeImageContentAccess())
        imagePipeline.setActive(true)
        imagePipeline.setVisible(true)
        let coordinator = MobilePlayerCollectionBrowserGridModeCoordinator(
            commitSnapshotFactory: { view in
                UIView(frame: view.bounds)
            }
        )
        coordinator.configure(
            collectionView: collectionView,
            viewportView: hostViewController.view,
            collectionLayout: collectionLayout,
            scrollCoordinator: scrollCoordinator,
            imagePipeline: imagePipeline,
            rendererContentAccess: .init(
                configureCell: { cell, indexPath, configuration in
                    cell.configure(
                        contentIdentity: MobilePlayerBrowserContentIdentity(
                            collectionId: collectionId,
                            tokenIndex: indexPath.item
                        ),
                        itemCount: itemCount,
                        imageSources: nil,
                        requiredImageQuality:
                            configuration.requiredImageQuality ?? .thumbnail,
                        missingDescriptorFallbackSpec:
                            PlayerMediaPlaceholderSpec(
                                thumbnailAspectRatio: nil
                            ),
                        imageLoadPolicy: configuration.imageLoadPolicy,
                        allowsLocalLargeImageUpgrade:
                            configuration.allowsLocalLargeImageUpgrade
                    )
                },
                contentIdentity: {
                    guard (0..<itemCount).contains($0) else { return nil }
                    return MobilePlayerBrowserContentIdentity(
                        collectionId: collectionId,
                        tokenIndex: $0
                    )
                },
                imageSources: { _ in nil }
            ),
            currentState: {
                .init(
                    browseSnapshot: state.browseSnapshot,
                    layoutAspectState: state.layoutAspectState,
                    isActive: true,
                    isViewVisible: true,
                    isApplyingPosition:
                        scrollCoordinator.isApplyingPosition,
                    hasFinishedInitialPositioning: true,
                    focusedTokenIndex: state.focusedTokenIndex,
                    forcedFocusedTokenIndex: nil,
                    isScrollMotionActive:
                        scrollCoordinator.isScrollMotionActive,
                    needsWindowSafeAreaRefresh: false,
                    hasPreparedTransition: false,
                    currentLayoutDisplayScale: 3,
                    layoutWindowSafeAreaInsets: .zero
                )
            },
            layoutOperations: .init(
                makeLayoutAspectState: {
                    updatedSnapshot, columnCount, _, profile in
                    let aspectProfile = self.makeGridModeAspectProfile(
                        snapshot: updatedSnapshot,
                        columnCount: columnCount,
                        profile: profile ?? thumbnailProfile
                    )
                    return .init(
                        aspectProfile: aspectProfile,
                        fallbackSpec: PlayerMediaPlaceholderSpec(
                            thumbnailAspectRatio: nil
                        )
                    )
                },
                makeLayoutFallbackSpec: { _, _ in
                    PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil)
                },
                makeLayoutAspectProfile: {
                    updatedSnapshot, columnCount, profile in
                    self.makeGridModeAspectProfile(
                        snapshot: updatedSnapshot,
                        columnCount: columnCount,
                        profile: profile
                    )
                },
                makeBrowserLayout: { profile in
                    MobilePlayerBrowserLayout(
                        viewportSize: viewportSize,
                        displayScale: 3,
                        aspectProfile: profile
                    )
                },
                installCollectionLayout: { layout in
                    collectionLayout.browserLayout = layout
                },
                centerContent: { tokenIndex in
                    guard let itemFrame = collectionLayout.browserLayout?
                        .itemFrame(at: tokenIndex) else {
                        return
                    }
                    let maximumOffsetY = max(
                        0,
                        collectionView.contentSize.height
                            - collectionView.bounds.height
                    )
                    collectionView.setContentOffsetWithoutResolution(CGPoint(
                        x: 0,
                        y: min(
                            max(itemFrame.midY - viewportSize.height / 2, 0),
                            maximumOffsetY
                        )
                    ))
                },
                currentAnchorTokenIndex: {
                    state.focusedTokenIndex
                },
                currentFocalPoint: {
                    CGPoint(
                        x: viewportSize.width / 2,
                        y: viewportSize.height / 2
                    )
                },
                retainFocusedTokenIndex: {
                    state.focusedTokenIndex = $0
                }
            ),
            browserEffects: .init(
                setBrowseSnapshot: { state.browseSnapshot = $0 },
                setLayoutAspectState: { state.layoutAspectState = $0 },
                updateLayoutAspectProfile: {
                    updatedSnapshot, _, columnCount in
                    guard let updatedSnapshot else { return }
                    state.layoutAspectState = .init(
                        aspectProfile: self.makeGridModeAspectProfile(
                            snapshot: updatedSnapshot,
                            columnCount: columnCount,
                            profile: thumbnailProfile
                        ),
                        fallbackSpec: PlayerMediaPlaceholderSpec(
                            thumbnailAspectRatio: nil
                        )
                    )
                },
                configureCollectionLayout: {
                    collectionLayout.browserLayout =
                        MobilePlayerBrowserLayout(
                            viewportSize: viewportSize,
                            displayScale: 3,
                            aspectProfile:
                                state.layoutAspectState.aspectProfile
                        )
                },
                endScrollMotionAndResetDragState: {},
                settleCurrentPosition: {},
                prepareCurrentImageWindowIfPossible: {},
                settleAfterApplyingPendingWindowSafeAreaRefresh: {},
                reloadVisibleCells: {},
                browseImageSources: { _ in nil }
            )
        )
        return GridModeCoordinatorContractFixture(
            coordinator: coordinator,
            collectionView: collectionView,
            viewportView: hostViewController.view,
            collectionLayout: collectionLayout,
            scrollCoordinator: scrollCoordinator,
            imagePipeline: imagePipeline,
            state: state,
            dataSource: dataSource,
            hostViewController: hostViewController,
            window: window
        )
    }
#endif

    func testImagePipelineSnapshotRestoreRoundTripsAllSnapshotState() throws {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var preparations = [
            MobilePlayerCollectionBrowserImagePipeline
                .ThumbnailWindowPreparation
        ]()
        var cancellationCount = 0
        pipeline.configure(contentAccess: makeImageContentAccess(
            prepareThumbnailWindow: {
                preparation, shouldApply, completion in
                preparations.append(preparation)
                completion(shouldApply() ? .committed : .planned)
            },
            cancelThumbnailWindowPreparation: {
                cancellationCount += 1
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .backward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .large
        )
        let snapshot = pipeline.snapshot()

        pipeline.resetThumbnailWindow()
        pipeline.restore(snapshot)

        XCTAssertEqual(pipeline.snapshot(), snapshot)
        let request = try XCTUnwrap(snapshot.lastThumbnailWindowRequest)
        XCTAssertEqual(request.tokenIndex, 18)
        XCTAssertEqual(request.direction, .backward)
        XCTAssertEqual(request.prefetchStride, 9)
        XCTAssertEqual(request.columnCount, 5)
        XCTAssertEqual(request.quality, .large)
        XCTAssertEqual(preparations.count, 2)
        XCTAssertEqual(preparations.dropFirst().first, preparations.first)
        XCTAssertEqual(cancellationCount, 2)
    }

    func testDenseThumbnailWindowRefreshesWhenDecodeVariantChanges() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        let variant = CollectionBrowserDecodeVariantState(
            .downsampled(maxPixelWidth: 160)
        )
        var preparations = [
            MobilePlayerCollectionBrowserImagePipeline
                .ThumbnailWindowPreparation
        ]()
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: { .smallThumbnail },
            imageDecodeVariant: { variant.value },
            prepareThumbnailWindow: {
                preparation, shouldApply, completion in
                preparations.append(preparation)
                completion(shouldApply() ? .committed : .planned)
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )

        variant.value = .downsampled(maxPixelWidth: 320)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: false,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )

        XCTAssertEqual(preparations.count, 2)
        XCTAssertEqual(
            preparations.map(\.decodeVariant),
            [
                .downsampled(maxPixelWidth: 160),
                .downsampled(maxPixelWidth: 320),
            ]
        )
    }

    func testImagePipelineInactiveRestorePreservesSnapshotWithoutPreparing() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var preparationCount = 0
        pipeline.configure(contentAccess: makeImageContentAccess(
            prepareThumbnailWindow: {
                _, shouldApply, completion in
                preparationCount += 1
                completion(shouldApply() ? .committed : .planned)
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )
        let snapshot = pipeline.snapshot()

        pipeline.setActive(false)
        pipeline.setVisible(false)
        pipeline.resetThumbnailWindow()
        pipeline.restore(snapshot)

        XCTAssertEqual(pipeline.snapshot(), snapshot)
        XCTAssertEqual(preparationCount, 1)
    }

    func testImagePipelineInvalidateIsIdempotentAndRejectsStateChanges() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var requiredQualityAccessCount = 0
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: {
                requiredQualityAccessCount += 1
                return .smallThumbnail
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.setScrollMotionActive(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .backward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .large
        )
        let snapshot = pipeline.snapshot()

        pipeline.invalidate()
        pipeline.invalidate()
        pipeline.setActive(false)
        pipeline.setVisible(false)
        pipeline.setScrollMotionActive(false)
        pipeline.resetThumbnailWindow()
        pipeline.restore(.init(
            lastThumbnailWindowRequest: nil
        ))
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: {
                requiredQualityAccessCount += 100
                return .large
            }
        ))

        XCTAssertTrue(pipeline.isActive)
        XCTAssertTrue(pipeline.isVisible)
        XCTAssertTrue(pipeline.isScrollMotionActive)
        XCTAssertEqual(pipeline.snapshot(), snapshot)
        XCTAssertFalse(pipeline.defersDenseGridImageLoading)
        XCTAssertEqual(requiredQualityAccessCount, 0)
    }

    func testImagePipelineHidingCancelsPendingThumbnailWindowPreparation() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var cancellationCount = 0
        pipeline.configure(contentAccess: makeImageContentAccess(
            cancelThumbnailWindowPreparation: {
                cancellationCount += 1
            }
        ))

        pipeline.setVisible(true)
        pipeline.setVisible(false)

        XCTAssertEqual(cancellationCount, 1)
    }

    func testImagePipelineDemotesForegroundCellWhenHiddenOrStaged() {
        let tokenIndex = 4
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "policy",
            tokenIndex: tokenIndex
        )
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 80,
            height: 80
        ))
        let fallbackSpec = PlayerMediaPlaceholderSpec(
            thumbnailAspectRatio: nil
        )
        let stagedState = SettlementAcceptance()
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        pipeline.configure(contentAccess: makeImageContentAccess(
            visibleCells: { [cell] },
            isPreparedTransitionActive: { stagedState.value }
        ))
        defer { pipeline.invalidate() }

        let configureCell: @MainActor (
            MobilePlayerCollectionBrowserCell.ImageLoadPolicy
        ) -> Void = { policy in
            cell.configure(
                contentIdentity: identity,
                itemCount: 10,
                imageSources: nil,
                requiredImageQuality: .thumbnail,
                missingDescriptorFallbackSpec: fallbackSpec,
                imageLoadPolicy: policy
            )
        }
        let configureThroughPipeline = {
            pipeline.configure(
                cell: cell,
                tokenIndex: tokenIndex,
                requiredImageQuality: nil,
                imageLoadPolicy: nil
            ) { _, policy, _ in
                configureCell(policy)
            }
        }

        pipeline.setActive(true)
        pipeline.setVisible(true)
        configureThroughPipeline()
        XCTAssertTrue(cell.usesForegroundImageLoading)
        pipeline.setVisible(false)
        XCTAssertFalse(cell.usesForegroundImageLoading)
        configureThroughPipeline()
        XCTAssertFalse(cell.usesForegroundImageLoading)

        pipeline.setVisible(true)
        configureThroughPipeline()
        XCTAssertTrue(cell.usesForegroundImageLoading)
        pipeline.setActive(false)
        pipeline.setVisible(false)
        stagedState.value = true
        configureThroughPipeline()
        XCTAssertFalse(cell.usesForegroundImageLoading)
    }

    func testImagePipelineRetriesRejectedThumbnailWindowPreparation() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var preparationCount = 0
        var completionCount = 0
        pipeline.configure(contentAccess: makeImageContentAccess(
            prepareThumbnailWindow: {
                _, shouldApply, completion in
                preparationCount += 1
                completion(
                    preparationCount > 1 && shouldApply()
                        ? .committed
                        : .planned
                )
            },
            thumbnailWindowPreparationDidFinish: {
                completionCount += 1
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)

        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )
        XCTAssertNil(pipeline.snapshot().lastThumbnailWindowRequest)

        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: false,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )

        XCTAssertEqual(preparationCount, 2)
        XCTAssertEqual(completionCount, 2)
        XCTAssertEqual(
            pipeline.snapshot().lastThumbnailWindowRequest?.tokenIndex,
            18
        )
    }

    func testImagePipelineIgnoresSupersededPreparationCompletion() throws {
        typealias ShouldApply = @MainActor () -> Bool
        typealias Completion = @MainActor (
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ) -> Void
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var shouldApplyCallbacks = [ShouldApply]()
        var completions = [Completion]()
        var completionCount = 0
        pipeline.configure(contentAccess: makeImageContentAccess(
            prepareThumbnailWindow: {
                _, shouldApply, completion in
                shouldApplyCallbacks.append(shouldApply)
                completions.append(completion)
            },
            thumbnailWindowPreparationDidFinish: {
                completionCount += 1
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)

        pipeline.prepareThumbnailWindow(
            around: 7,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )
        guard shouldApplyCallbacks.count == 2, completions.count == 2 else {
            XCTFail("Expected two pending preparations")
            return
        }

        XCTAssertFalse(shouldApplyCallbacks[0]())
        completions[0](.committed)
        XCTAssertEqual(completionCount, 0)
        XCTAssertNil(pipeline.snapshot().lastThumbnailWindowRequest)
        XCTAssertEqual(
            pipeline.snapshot().pendingThumbnailWindowRequest?.tokenIndex,
            18
        )

        XCTAssertTrue(shouldApplyCallbacks[1]())
        completions[1](.committed)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(
            pipeline.snapshot().lastThumbnailWindowRequest?.tokenIndex,
            18
        )
        XCTAssertNil(pipeline.snapshot().pendingThumbnailWindowRequest)
    }

    func testImagePipelineRestoreRecomputesCurrentWindowConfiguration() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var requiredQuality = CollectionBrowseImageQuality.smallThumbnail
        var decodeVariant = DownloadableMediaImageDecodeVariant.downsampled(
            maxPixelWidth: 160
        )
        var prefetchStride = 9
        var columnCount = 5
        var preparations = [
            MobilePlayerCollectionBrowserImagePipeline
                .ThumbnailWindowPreparation
        ]()
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: { requiredQuality },
            imageDecodeVariant: { decodeVariant },
            configuredPrefetchStride: { prefetchStride },
            configuredColumnCount: { columnCount },
            prepareThumbnailWindow: {
                preparation, shouldApply, completion in
                preparations.append(preparation)
                completion(shouldApply() ? .committed : .planned)
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: true,
            configuredPrefetchStride: prefetchStride,
            configuredColumnCount: columnCount,
            requiredImageQuality: requiredQuality
        )
        let snapshot = pipeline.snapshot()

        requiredQuality = .smallestThumbnail
        decodeVariant = .downsampled(maxPixelWidth: 320)
        prefetchStride = 18
        columnCount = 9
        pipeline.restore(snapshot)

        let restoredPreparation = preparations.last
        XCTAssertEqual(restoredPreparation?.quality, .smallestThumbnail)
        XCTAssertEqual(restoredPreparation?.decodeVariant, decodeVariant)
        XCTAssertEqual(restoredPreparation?.prefetchStride, 18)
        XCTAssertEqual(restoredPreparation?.columnCount, 9)
    }

    func testImagePipelineRejectsCompletionAfterLeavingForeground() throws {
        typealias ShouldApply = @MainActor () -> Bool
        typealias Completion = @MainActor (
            MobileCollectionBrowseThumbnailWindowPreparationResult
        ) -> Void
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        let foregroundState = SettlementAcceptance()
        foregroundState.value = true
        var shouldApply: ShouldApply?
        var completion: Completion?
        pipeline.configure(contentAccess: makeImageContentAccess(
            isForegroundActive: { foregroundState.value },
            prepareThumbnailWindow: {
                _, pendingShouldApply, pendingCompletion in
                shouldApply = pendingShouldApply
                completion = pendingCompletion
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.prepareThumbnailWindow(
            around: 18,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 9,
            configuredColumnCount: 5,
            requiredImageQuality: .smallThumbnail
        )

        foregroundState.value = false
        let pendingShouldApply = try XCTUnwrap(shouldApply)
        let pendingCompletion = try XCTUnwrap(completion)
        XCTAssertFalse(pendingShouldApply())
        pendingCompletion(pendingShouldApply() ? .committed : .planned)

        XCTAssertNil(pipeline.snapshot().lastThumbnailWindowRequest)
        XCTAssertNil(pipeline.snapshot().pendingThumbnailWindowRequest)
    }

    private func makeFileAvailabilityCell(
        collectionID: String,
        tokenIndex: Int
    ) -> (
        cell: MobilePlayerCollectionBrowserCell,
        descriptor: DownloadableMediaDescriptor
    ) {
        let descriptor = DownloadableMediaDescriptor(
            collectionId: collectionID,
            tokenId: "token-\(tokenIndex)",
            tokenIndex: tokenIndex,
            media: .staticImage(
                url: URL(fileURLWithPath: "/availability-\(tokenIndex).png"),
                fileExtension: "png"
            )
        )
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0, y: 0, width: 80, height: 80
        ))
        cell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: collectionID,
                tokenIndex: tokenIndex
            ),
            itemCount: 10,
            imageSources: CollectionBrowseImageSources(
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            ),
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
                .image { _ in },
            descriptor: descriptor,
            quality: .large,
            tokenIndex: tokenIndex,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        return (cell, descriptor)
    }

    private func deliverFileAvailability(
        _ change: DownloadableMediaCacheFileAvailabilityChange,
        scope: DownloadableMediaAvailabilityPublisher.Scope,
        to pipeline: MobilePlayerCollectionBrowserImagePipeline
    ) async {
        let center = NotificationCenter()
        let publisher = DownloadableMediaAvailabilityPublisher(
            layout: .live,
            notificationCenter: center
        )
        let delivered = expectation(description: "File availability delivered")
        let observer = center.addObserver(
            forName: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
            queue: nil
        ) { notification in
            let name = notification.name
            let change = notification.object
                as? DownloadableMediaCacheFileAvailabilityChange
            let userInfo = notification.userInfo
                as? [String: DownloadableMediaAvailabilityPublisher.Scope]
            MainActor.assumeIsolated {
                pipeline.handleCacheNotification(Notification(
                    name: name,
                    object: change,
                    userInfo: userInfo
                ))
                delivered.fulfill()
            }
        }
        defer { center.removeObserver(observer) }
        publisher.post(change, scope: scope)
        await fulfillment(of: [delivered], timeout: 1)
    }

    func testFileAvailabilityTargetsCellAndPreservesFilteringDuringScroll()
        async {
        let collectionID = "targeted-availability-\(UUID())"
        let (target, descriptor) = makeFileAvailabilityCell(
            collectionID: collectionID, tokenIndex: 4
        )
        let (unrelated, _) = makeFileAvailabilityCell(
            collectionID: collectionID, tokenIndex: 5
        )
        let fileURL = DownloadableMediaCacheLayout.live
            .location(for: descriptor).mediaURL
        var cellLookups = [IndexPath]()
        var viewportLookups = [Int?]()
        var visibleCellScans = 0
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        pipeline.configure(contentAccess: makeImageContentAccess(
            cell: {
                cellLookups.append($0)
                return $0.item == 4 ? target : nil
            },
            visibleCells: {
                visibleCellScans += 1
                return [target, unrelated]
            },
            viewportRenderCells: {
                viewportLookups.append($0)
                return []
            },
            collectionID: { collectionID },
            requiredImageQuality: { .smallThumbnail }
        ))
        pipeline.setActive(true)
        defer { pipeline.invalidate() }

        await deliverFileAvailability(
            .becameAvailable, scope: .file(fileURL), to: pipeline
        )

        XCTAssertEqual(target.displayedLargeImageWindowEntry?.isLocallyAvailable, true)
        XCTAssertEqual(unrelated.displayedLargeImageWindowEntry?.isLocallyAvailable, false)
        XCTAssertEqual(cellLookups, [IndexPath(item: 4, section: 0)])
        XCTAssertEqual(viewportLookups, [4])
        XCTAssertEqual(visibleCellScans, 0)

        let otherVariantURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("000004-other-variant.png")
        await deliverFileAvailability(
            .becameUnavailable, scope: .file(otherVariantURL), to: pipeline
        )
        XCTAssertEqual(target.displayedLargeImageWindowEntry?.isLocallyAvailable, true)

        pipeline.setScrollMotionActive(true)
        await deliverFileAvailability(
            .becameUnavailable, scope: .file(fileURL), to: pipeline
        )
        XCTAssertEqual(target.displayedLargeImageWindowEntry?.isLocallyAvailable, false)
        await deliverFileAvailability(
            .becameAvailable, scope: .file(fileURL), to: pipeline
        )
        XCTAssertEqual(target.displayedLargeImageWindowEntry?.isLocallyAvailable, true)
        XCTAssertEqual(viewportLookups, [4])
        XCTAssertEqual(visibleCellScans, 0)

        let lookupCount = cellLookups.count
        let foreignURL = DownloadableMediaCacheLayout.live
            .collectionDirectory(collectionId: "other-collection")
            .appendingPathComponent(fileURL.lastPathComponent)
        await deliverFileAvailability(
            .becameAvailable, scope: .file(foreignURL), to: pipeline
        )
        XCTAssertEqual(cellLookups.count, lookupCount)
        XCTAssertEqual(visibleCellScans, 0)
    }

    func testBroadFileAvailabilityPreservesVisibleCellRefresh() async {
        let collectionID = "broad-availability-\(UUID())"
        let (first, _) = makeFileAvailabilityCell(
            collectionID: collectionID, tokenIndex: 1
        )
        let (second, _) = makeFileAvailabilityCell(
            collectionID: collectionID, tokenIndex: 2
        )
        var visibleCellScans = 0
        var viewportLookups = [Int?]()
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        pipeline.configure(contentAccess: makeImageContentAccess(
            cell: { _ in
                XCTFail("Broad changes must refresh every visible cell")
                return nil
            },
            visibleCells: {
                visibleCellScans += 1
                return [first, second]
            },
            viewportRenderCells: {
                viewportLookups.append($0)
                return []
            },
            collectionID: { collectionID }
        ))
        pipeline.setActive(true)
        defer { pipeline.invalidate() }

        await deliverFileAvailability(
            .becameAvailable, scope: .all, to: pipeline
        )
        XCTAssertEqual(first.displayedLargeImageWindowEntry?.isLocallyAvailable, true)
        XCTAssertEqual(second.displayedLargeImageWindowEntry?.isLocallyAvailable, true)
        XCTAssertEqual(viewportLookups, [nil])

        await deliverFileAvailability(
            .becameUnavailable,
            scope: .collection(DownloadableMediaCacheLayout.live
                .collectionDirectory(collectionId: collectionID)),
            to: pipeline
        )
        XCTAssertEqual(first.displayedLargeImageWindowEntry?.isLocallyAvailable, false)
        XCTAssertEqual(second.displayedLargeImageWindowEntry?.isLocallyAvailable, false)
        pipeline.handleCacheNotification(Notification(
            name: .downloadableMediaCacheFileAvailabilityDidChange,
            object: DownloadableMediaCacheFileAvailabilityChange.becameAvailable
        ))
        XCTAssertEqual(first.displayedLargeImageWindowEntry?.isLocallyAvailable, true)
        XCTAssertEqual(second.displayedLargeImageWindowEntry?.isLocallyAvailable, true)
        XCTAssertEqual(visibleCellScans, 3)
        XCTAssertEqual(viewportLookups, [nil, nil])
    }

#if DEBUG
    private func makeDecodedAvailabilityCell(
        collectionID: String,
        tokenIndex: Int
    ) -> (
        cell: MobilePlayerCollectionBrowserCell,
        descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        let descriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: collectionID,
            tokenId: String(tokenIndex),
            tokenIndex: tokenIndex,
            media: .staticImage(
                url: URL(fileURLWithPath: "/decoded-image-wake.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 80,
            height: 80
        ))
        cell.configure(
            contentIdentity: MobilePlayerBrowserContentIdentity(
                collectionId: collectionID,
                tokenIndex: tokenIndex
            ),
            itemCount: 10,
            imageSources: CollectionBrowseImageSources(
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            ),
            requiredImageQuality: .smallThumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .cachedOnly,
            allowsLocalLargeImageUpgrade: false
        )
        return (cell, descriptor)
    }

    private func decodedImageNotification(
        collectionID: String,
        tokenIndex: Int
    ) -> Notification {
        Notification(
            name: .downloadableMediaCacheDecodedImageDidBecomeAvailable,
            object: DownloadableMediaCacheDecodedImageAvailability(
                collectionId: collectionID,
                tokenIndex: tokenIndex
            )
        )
    }

    func testDecodedImageAvailabilityRequeuesVisibleDenseCacheMiss() throws {
        let collectionID = "decoded-image-wake"
        let tokenIndex = 4
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        let (cell, descriptor) = makeDecodedAvailabilityCell(
            collectionID: collectionID,
            tokenIndex: tokenIndex
        )
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        pipeline.configure(contentAccess: makeImageContentAccess(
            visibleIndexPaths: { [indexPath] },
            cell: { $0 == indexPath ? cell : nil },
            collectionID: { collectionID },
            requiredImageQuality: { .smallThumbnail }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.setScrollMotionActive(true)
        let cache = DownloadableMediaCache.shared
        cache.resetDecodedImagesForTesting()
        defer {
            pipeline.invalidate()
            cache.resetDecodedImagesForTesting()
        }

        pipeline.willDisplay(
            cell: cell,
            tokenIndex: tokenIndex,
            intersectsViewport: { true }
        )
        XCTAssertEqual(
            pipeline.drainDenseGridImageDisplayLinkFrameForTesting(),
            1
        )
        XCTAssertFalse(
            cell.refreshCachedImageIfAvailable(tokenIndex: tokenIndex)
        )
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)

        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2)
        ).image { _ in }
        cache.installDecodedImageForTesting(image, for: descriptor)
        pipeline.handleDecodedImageNotification(decodedImageNotification(
            collectionID: collectionID,
            tokenIndex: tokenIndex
        ))

        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 1)
        XCTAssertEqual(
            pipeline.drainDenseGridImageDisplayLinkFrameForTesting(),
            1
        )
        let imageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertTrue(imageView.image === image)
        pipeline.handleDecodedImageNotification(decodedImageNotification(
            collectionID: collectionID,
            tokenIndex: tokenIndex
        ))
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
    }

    func testDecodedImageNotificationsFilterTrackedTokensWithoutVisibilityScans() {
        for columnCount in [5, 9] {
            let collectionID = "tracked-notification-\(UUID())"
            let (cell, _) = makeDecodedAvailabilityCell(
                collectionID: collectionID,
                tokenIndex: 4
            )
            let (offscreenCell, _) = makeDecodedAvailabilityCell(
                collectionID: collectionID,
                tokenIndex: 5
            )
            var visibilityScans = 0
            var cellLookups = [Int]()
            let pipeline = MobilePlayerCollectionBrowserImagePipeline()
            defer { pipeline.invalidate() }
            pipeline.configure(contentAccess: makeImageContentAccess(
                visibleIndexPaths: {
                    visibilityScans += 1
                    return [IndexPath(item: 4, section: 0)]
                },
                cell: {
                    cellLookups.append($0.item)
                    return $0.item == 4 ? cell : offscreenCell
                },
                collectionID: { collectionID },
                requiredImageQuality: { .smallThumbnail },
                baseColumnCount: { columnCount }
            ))
            pipeline.setScrollMotionActive(true)
            pipeline.willDisplay(
                cell: cell,
                tokenIndex: 4,
                intersectsViewport: { true }
            )
            pipeline.setActive(true)
            pipeline.setVisible(true)

            pipeline.handleDecodedImageNotification(decodedImageNotification(
                collectionID: "another-collection",
                tokenIndex: 4
            ))
            pipeline.handleDecodedImageNotification(decodedImageNotification(
                collectionID: collectionID,
                tokenIndex: 5
            ))
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
            XCTAssertTrue(cellLookups.isEmpty)

            for _ in 0..<3 {
                pipeline.handleDecodedImageNotification(decodedImageNotification(
                    collectionID: collectionID,
                    tokenIndex: 4
                ))
            }
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 1)
            XCTAssertEqual(cellLookups, [4, 4, 4])
            XCTAssertEqual(visibilityScans, 0)

            pipeline.willEndDisplaying(cell: cell, tokenIndex: 4)
            pipeline.handleDecodedImageNotification(decodedImageNotification(
                collectionID: collectionID,
                tokenIndex: 4
            ))
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
            XCTAssertEqual(cellLookups, [4, 4, 4])
            XCTAssertEqual(visibilityScans, 0)
        }
    }

    func testVisibleTrackingKeepsReplacementRefreshUntilItsLastCellLeaves() {
        let collectionID = "replacement-visibility-\(UUID())"
        let (oldCell, _) = makeDecodedAvailabilityCell(
            collectionID: collectionID,
            tokenIndex: 4
        )
        let (replacementCell, _) = makeDecodedAvailabilityCell(
            collectionID: collectionID,
            tokenIndex: 4
        )
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        defer { pipeline.invalidate() }
        pipeline.configure(contentAccess: makeImageContentAccess(
            requiredImageQuality: { .smallThumbnail }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.setScrollMotionActive(true)

        for cell in [oldCell, oldCell, replacementCell] {
            pipeline.willDisplay(
                cell: cell,
                tokenIndex: 4,
                intersectsViewport: { true }
            )
        }
        XCTAssertEqual(pipeline.trackedVisibleTokenIndicesForTesting, [4])
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 1)

        pipeline.willEndDisplaying(cell: oldCell, tokenIndex: 4)
        pipeline.willEndDisplaying(cell: UICollectionViewCell(), tokenIndex: 4)
        XCTAssertEqual(pipeline.trackedVisibleTokenIndicesForTesting, [4])
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 1)

        pipeline.willEndDisplaying(cell: replacementCell, tokenIndex: 4)
        XCTAssertTrue(pipeline.trackedVisibleTokenIndicesForTesting.isEmpty)
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
        pipeline.willEndDisplaying(cell: oldCell, tokenIndex: 4)
        XCTAssertTrue(pipeline.trackedVisibleTokenIndicesForTesting.isEmpty)
    }

    func testVisibleTrackingRegistersBeforeEligibilityAndSurvivesLifecycleChanges() {
        let eligibilityStates = [
            (active: false, visible: true, foreground: true, renderer: false),
            (active: true, visible: false, foreground: true, renderer: false),
            (active: true, visible: true, foreground: false, renderer: false),
            (active: true, visible: true, foreground: true, renderer: true),
        ]
        for eligibility in eligibilityStates {
            let collectionID = "inactive-visibility-\(UUID())"
            let (cell, _) = makeDecodedAvailabilityCell(
                collectionID: collectionID,
                tokenIndex: 4
            )
            let foregroundState = SettlementAcceptance()
            foregroundState.value = eligibility.foreground
            let rendererState = SettlementAcceptance()
            rendererState.value = eligibility.renderer
            let pipeline = MobilePlayerCollectionBrowserImagePipeline()
            defer { pipeline.invalidate() }
            pipeline.configure(contentAccess: makeImageContentAccess(
                cell: { $0.item == 4 ? cell : nil },
                visibleCells: { [cell] },
                collectionID: { collectionID },
                requiredImageQuality: { .smallThumbnail },
                isRendererActive: { rendererState.value },
                isForegroundActive: { foregroundState.value }
            ))
            pipeline.setActive(eligibility.active)
            pipeline.setVisible(eligibility.visible)
            pipeline.setScrollMotionActive(true)
            pipeline.willDisplay(
                cell: cell,
                tokenIndex: 4,
                intersectsViewport: { true }
            )
            XCTAssertEqual(pipeline.trackedVisibleTokenIndicesForTesting, [4])
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)

            pipeline.setActive(false)
            pipeline.setVisible(false)
            pipeline.setScrollMotionActive(false)
            pipeline.resetThumbnailWindow()
            pipeline.cancelDenseGridImageRefreshes()
            XCTAssertEqual(pipeline.trackedVisibleTokenIndicesForTesting, [4])

            foregroundState.value = true
            rendererState.value = false
            pipeline.setActive(true)
            pipeline.setVisible(true)
            pipeline.setScrollMotionActive(true)
            pipeline.handleDecodedImageNotification(decodedImageNotification(
                collectionID: collectionID,
                tokenIndex: 4
            ))
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 1)
        }
    }

    func testVisibleTrackingResetAndReconcileUseCurrentCellsAndPreserveNewWork() {
        let collectionID = "reconciled-visibility-\(UUID())"
        let (oldCell, _) = makeDecodedAvailabilityCell(
            collectionID: collectionID,
            tokenIndex: 4
        )
        let (currentCell, _) = makeDecodedAvailabilityCell(
            collectionID: collectionID,
            tokenIndex: 5
        )
        var visibilityScans = 0
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        defer { pipeline.invalidate() }
        pipeline.configure(contentAccess: makeImageContentAccess(
            visibleIndexPaths: {
                visibilityScans += 1
                return [
                    IndexPath(item: 5, section: 0),
                    IndexPath(item: 6, section: 0),
                ]
            },
            cell: { $0.item == 5 ? currentCell : nil },
            collectionID: { collectionID },
            requiredImageQuality: { .smallThumbnail }
        ))
        pipeline.setScrollMotionActive(true)
        pipeline.willDisplay(
            cell: oldCell,
            tokenIndex: 4,
            intersectsViewport: { true }
        )
        pipeline.replacePendingDenseGridImageRefreshesForTesting(tokenIndices: [4])
        pipeline.resetVisibleCellTracking()
        XCTAssertTrue(pipeline.trackedVisibleTokenIndicesForTesting.isEmpty)
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
        XCTAssertFalse(pipeline.isDenseGridImageDisplayLinkActive)

        pipeline.reconcileVisibleCells()
        XCTAssertEqual(pipeline.trackedVisibleTokenIndicesForTesting, [5])
        XCTAssertEqual(visibilityScans, 1)
        pipeline.setActive(true)
        pipeline.setVisible(true)
        pipeline.handleDecodedImageNotification(decodedImageNotification(
            collectionID: collectionID,
            tokenIndex: 5
        ))
        pipeline.reconcileVisibleCells()
        pipeline.willEndDisplaying(cell: oldCell, tokenIndex: 4)
        XCTAssertEqual(pipeline.trackedVisibleTokenIndicesForTesting, [5])
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 1)
        XCTAssertEqual(visibilityScans, 2)

        pipeline.willEndDisplaying(cell: currentCell, tokenIndex: 5)
        XCTAssertTrue(pipeline.trackedVisibleTokenIndicesForTesting.isEmpty)
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
    }

    func testDenseGridImageRefreshBudgetPreservesPendingWorkInOrder() {
        for columnCount in [5, 9] {
            let pipeline = MobilePlayerCollectionBrowserImagePipeline()
            defer { pipeline.invalidate() }
            var currentTime = 0.0
            var refreshedTokenIndices = [Int]()
            pipeline.configure(contentAccess: makeImageContentAccess(
                cell: { indexPath in
                    refreshedTokenIndices.append(indexPath.item)
                    currentTime += DenseGridImageRefreshPolicy.frameTimeBudget * 0.75
                    return nil
                },
                requiredImageQuality: { .smallThumbnail },
                baseColumnCount: { columnCount }
            ))
            pipeline.setScrollMotionActive(true)
            pipeline.replacePendingDenseGridImageRefreshesForTesting(
                tokenIndices: [3, 5, 8, 13]
            )

            XCTAssertEqual(
                pipeline.drainDenseGridImageDisplayLinkFrameForTesting(
                    currentTime: { currentTime }
                ),
                2
            )
            XCTAssertEqual(refreshedTokenIndices, [3, 5])
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 2)
            XCTAssertEqual(
                pipeline.thumbnailWindowMetrics.outstandingCachedImageRefreshes,
                2
            )
            XCTAssertTrue(pipeline.isDenseGridImageDisplayLinkActive)

            XCTAssertEqual(
                pipeline.drainDenseGridImageDisplayLinkFrameForTesting(
                    currentTime: { currentTime }
                ),
                2
            )
            XCTAssertEqual(refreshedTokenIndices, [3, 5, 8, 13])
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
            XCTAssertEqual(
                pipeline.thumbnailWindowMetrics.outstandingCachedImageRefreshes,
                0
            )
            XCTAssertFalse(pipeline.isDenseGridImageDisplayLinkActive)
        }
    }

    func testDenseGridImageRefreshBudgetAllowsOneExpensiveItemPerFrame() {
        for columnCount in [5, 9] {
            let pipeline = MobilePlayerCollectionBrowserImagePipeline()
            defer { pipeline.invalidate() }
            var currentTime = 0.0
            var refreshedTokenIndices = [Int]()
            pipeline.configure(contentAccess: makeImageContentAccess(
                cell: { indexPath in
                    refreshedTokenIndices.append(indexPath.item)
                    currentTime += DenseGridImageRefreshPolicy.frameTimeBudget * 2
                    return nil
                },
                requiredImageQuality: { .smallThumbnail },
                baseColumnCount: { columnCount }
            ))
            pipeline.setScrollMotionActive(true)
            pipeline.replacePendingDenseGridImageRefreshesForTesting(
                tokenIndices: [3, 5]
            )

            XCTAssertEqual(
                pipeline.drainDenseGridImageDisplayLinkFrameForTesting(
                    currentTime: { currentTime }
                ),
                1
            )
            XCTAssertEqual(refreshedTokenIndices, [3])
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 1)
            XCTAssertTrue(pipeline.isDenseGridImageDisplayLinkActive)

            XCTAssertEqual(
                pipeline.drainDenseGridImageDisplayLinkFrameForTesting(
                    currentTime: { currentTime }
                ),
                1
            )
            XCTAssertEqual(refreshedTokenIndices, [3, 5])
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
            XCTAssertFalse(pipeline.isDenseGridImageDisplayLinkActive)
        }
    }

    func testDenseGridImageRefreshBudgetKeepsColumnBasedLimitForCheapWork() {
        for columnCount in [5, 9] {
            let pipeline = MobilePlayerCollectionBrowserImagePipeline()
            defer { pipeline.invalidate() }
            var currentTime = 0.0
            var refreshedTokenIndices = [Int]()
            pipeline.configure(contentAccess: makeImageContentAccess(
                cell: { indexPath in
                    refreshedTokenIndices.append(indexPath.item)
                    currentTime += DenseGridImageRefreshPolicy.frameTimeBudget / 100
                    return nil
                },
                requiredImageQuality: { .smallThumbnail },
                baseColumnCount: { columnCount }
            ))
            pipeline.setScrollMotionActive(true)
            pipeline.replacePendingDenseGridImageRefreshesForTesting(
                tokenIndices: Array(0..<(columnCount + 2))
            )

            XCTAssertEqual(
                pipeline.drainDenseGridImageDisplayLinkFrameForTesting(
                    currentTime: { currentTime }
                ),
                columnCount
            )
            XCTAssertEqual(refreshedTokenIndices, Array(0..<columnCount))
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 2)
            XCTAssertTrue(pipeline.isDenseGridImageDisplayLinkActive)

            XCTAssertEqual(
                pipeline.drainDenseGridImageDisplayLinkFrameForTesting(
                    currentTime: { currentTime }
                ),
                2
            )
            XCTAssertEqual(
                refreshedTokenIndices,
                Array(0..<(columnCount + 2))
            )
            XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
            XCTAssertFalse(pipeline.isDenseGridImageDisplayLinkActive)
        }
    }

    func testImagePipelineInvalidationClearsAndRejectsPendingDenseGridWork() {
        let (cell, _) = makeDecodedAvailabilityCell(
            collectionID: "invalidated-visibility-\(UUID())",
            tokenIndex: 3
        )
        var visibilityScans = 0
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        pipeline.configure(contentAccess: makeImageContentAccess(
            visibleIndexPaths: {
                visibilityScans += 1
                return [IndexPath(item: 3, section: 0)]
            },
            cell: { _ in cell },
            requiredImageQuality: { .smallThumbnail }
        ))
        pipeline.setScrollMotionActive(true)
        pipeline.willDisplay(
            cell: cell,
            tokenIndex: 3,
            intersectsViewport: { true }
        )
        XCTAssertEqual(pipeline.trackedVisibleTokenIndicesForTesting, [3])
        pipeline.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: [3, 5, 3, 8]
        )

        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 3)
        XCTAssertTrue(pipeline.isDenseGridImageDisplayLinkActive)

        pipeline.invalidate()
        pipeline.invalidate()
        pipeline.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: [13, 21]
        )
        pipeline.willDisplay(
            cell: cell,
            tokenIndex: 3,
            intersectsViewport: { true }
        )
        pipeline.reconcileVisibleCells()
        pipeline.resetVisibleCellTracking()

        XCTAssertTrue(pipeline.trackedVisibleTokenIndicesForTesting.isEmpty)
        XCTAssertEqual(visibilityScans, 0)
        XCTAssertEqual(pipeline.pendingDenseGridImageRefreshCount, 0)
        XCTAssertFalse(pipeline.isDenseGridImageDisplayLinkActive)
        XCTAssertEqual(
            pipeline.drainDenseGridImageDisplayLinkFrameForTesting(),
            0
        )
    }
#endif

#if DEBUG
    func testGridModeCoordinatorInvalidationCancelsPrewarmAndRejectsWork()
        throws {
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator

        XCTAssertTrue(
            coordinator.lifecycleStateForTesting.isPinchRecognizerAttached
        )
        coordinator.scheduleGeometryPrewarmIfPossible()
        XCTAssertTrue(
            coordinator.lifecycleStateForTesting.hasPendingGeometryPrewarm
        )

        coordinator.invalidate()
        coordinator.invalidate()
        coordinator.scheduleGeometryPrewarmIfPossible()
        coordinator.resetGeometryState()
        coordinator.discardTransitionCover()

        let state = coordinator.lifecycleStateForTesting
        XCTAssertTrue(state.isInvalidated)
        XCTAssertFalse(state.hasPendingPinchFrame)
        XCTAssertFalse(state.hasPendingGeometryPrewarm)
        XCTAssertFalse(state.isSettleDisplayLinkActive)
        XCTAssertFalse(state.isInteractionFadeDisplayLinkActive)
        XCTAssertFalse(state.isFrameDriverActive)
        XCTAssertFalse(state.hasCommitSnapshot)
        XCTAssertFalse(state.isRendererActive)
        XCTAssertFalse(state.isPinchRecognizerAttached)
        XCTAssertFalse(state.isDrainingEffects)
        XCTAssertFalse(state.isRestoringContentOffset)
        XCTAssertFalse(coordinator.setGridMode(.fiveColumns))
    }

    func testGridModeCoordinatorInvalidationCancelsPendingPinchFrame()
        async throws {
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator
        let recognizer = GridModeContractPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: fixture.viewportView.bounds.midX,
            y: fixture.viewportView.bounds.midY
        )
        recognizer.reportedState = .began
        recognizer.scale = 1
        coordinator.handleGridModePinchForTesting(recognizer)
        recognizer.reportedState = .changed
        recognizer.scale = 1.2
        coordinator.handleGridModePinchForTesting(recognizer)

        XCTAssertTrue(
            coordinator.lifecycleStateForTesting.hasPendingPinchFrame
        )

        coordinator.invalidate()
        coordinator.handleGridModePinchForTesting(recognizer)
        await Task.yield()
        await Task.yield()

        let state = coordinator.lifecycleStateForTesting
        XCTAssertTrue(state.isInvalidated)
        XCTAssertFalse(state.hasPendingPinchFrame)
        XCTAssertFalse(state.isRendererActive)
        XCTAssertFalse(state.isPinchRecognizerAttached)
    }

    func testGridModeCoordinatorInvalidationStopsSettleAndRestoresPanLimit()
        throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator
        let panGestureRecognizer = fixture.collectionView
            .panGestureRecognizer
        panGestureRecognizer.maximumNumberOfTouches = 4

        XCTAssertTrue(coordinator.setGridMode(.fiveColumns))
        let settlingState = coordinator.lifecycleStateForTesting
        XCTAssertTrue(settlingState.isSettleDisplayLinkActive)
        XCTAssertTrue(settlingState.isFrameDriverActive)
        XCTAssertTrue(settlingState.isRendererActive)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        coordinator.invalidate()
        coordinator.invalidate()

        let invalidatedState = coordinator.lifecycleStateForTesting
        XCTAssertFalse(invalidatedState.isSettleDisplayLinkActive)
        XCTAssertFalse(invalidatedState.isInteractionFadeDisplayLinkActive)
        XCTAssertFalse(invalidatedState.isFrameDriverActive)
        XCTAssertFalse(invalidatedState.isRendererActive)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 4)
        XCTAssertFalse(coordinator.hasInteractionState)
        XCTAssertFalse(fixture.scrollCoordinator.isApplyingPosition)
        XCTAssertTrue(fixture.collectionView.isPrefetchingEnabled)
        XCTAssertTrue(fixture.collectionView.clipsToBounds)
        XCTAssertTrue(fixture.collectionView.isScrollEnabled)
    }

    func testGridModeCoordinatorInvalidationStopsInteractionFadeDisplayLink()
        throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator
        let recognizer = GridModeContractPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: fixture.viewportView.bounds.midX,
            y: fixture.viewportView.bounds.midY
        )

        XCTAssertTrue(coordinator.setGridMode(.fiveColumns))
        recognizer.reportedState = .began
        recognizer.scale = 1
        coordinator.handleGridModePinchForTesting(recognizer)
        let interactionState = coordinator.lifecycleStateForTesting
        XCTAssertFalse(interactionState.isSettleDisplayLinkActive)
        XCTAssertTrue(interactionState.isInteractionFadeDisplayLinkActive)
        XCTAssertTrue(interactionState.isFrameDriverActive)
        XCTAssertTrue(interactionState.isRendererActive)

        coordinator.invalidate()

        let invalidatedState = coordinator.lifecycleStateForTesting
        XCTAssertFalse(invalidatedState.isInteractionFadeDisplayLinkActive)
        XCTAssertFalse(invalidatedState.isFrameDriverActive)
        XCTAssertFalse(invalidatedState.isRendererActive)
    }

    func testGridModeCoordinatorReanchorsWhenPinchGrabsSettle() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator
        let recognizer = GridModeContractPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(x: 80, y: 180)
        recognizer.reportedState = .began
        recognizer.scale = 1

        XCTAssertTrue(coordinator.setGridMode(.fiveColumns))
        XCTAssertEqual(
            coordinator.lifecycleStateForTesting.settlingReanchorCount,
            0
        )

        coordinator.handleGridModePinchForTesting(recognizer)

        XCTAssertEqual(
            coordinator.lifecycleStateForTesting.settlingReanchorCount,
            1
        )
    }

    func testGridModeCoordinatorInvalidationRemovesCommitSnapshot() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator

        XCTAssertTrue(coordinator.setGridMode(.fiveColumns))
        XCTAssertTrue(coordinator.finalizeInterruptibleSettle())
        XCTAssertTrue(coordinator.lifecycleStateForTesting.hasCommitSnapshot)
        let snapshot = try XCTUnwrap(
            fixture.viewportView.subviews.first {
                $0 !== fixture.collectionView
            }
        )

        coordinator.invalidate()

        XCTAssertFalse(
            coordinator.lifecycleStateForTesting.hasCommitSnapshot
        )
        XCTAssertNil(snapshot.superview)
    }

    func testGridModeCoordinatorMarksEffectDrainBeforeSynchronousReentry()
        throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator
        var callbackStates = [
            MobilePlayerCollectionBrowserGridModeCoordinator
                .LifecycleStateForTesting
        ]()
        fixture.collectionView.contentOffsetTarget = {
            requestedContentOffset, _ in
            callbackStates.append(coordinator.lifecycleStateForTesting)
            _ = coordinator.observeScrollDuringGridMode(
                fixture.collectionView
            )
            return (requestedContentOffset, false)
        }

        XCTAssertTrue(coordinator.setGridMode(.fiveColumns))

        XCTAssertFalse(callbackStates.isEmpty)
        XCTAssertTrue(callbackStates.allSatisfy(\.isDrainingEffects))
        XCTAssertFalse(
            coordinator.lifecycleStateForTesting.isDrainingEffects
        )
    }

    func testGridModeCoordinatorMarksContentOffsetRestorationBeforeCallbacks()
        throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = try makeGridModeCoordinatorFixture()
        defer { fixture.tearDown() }
        let coordinator = fixture.coordinator

        XCTAssertTrue(coordinator.setGridMode(.fiveColumns))
        fixture.collectionView.setContentOffsetWithoutResolution(CGPoint(
            x: 0,
            y: fixture.collectionView.contentOffset.y + 40
        ))
        let delegate = GridModeContractScrollDelegate()
        delegate.coordinator = coordinator
        fixture.collectionView.delegate = delegate

        let observation = coordinator.observeScrollDuringGridMode(
            fixture.collectionView
        )

        XCTAssertTrue(observation.shouldContinue)
        XCTAssertTrue(observation.settlesAfterImmediateOffset)
        XCTAssertFalse(delegate.lifecycleStates.isEmpty)
        XCTAssertTrue(
            delegate.lifecycleStates.allSatisfy(\.isRestoringContentOffset)
        )
        XCTAssertFalse(
            coordinator.lifecycleStateForTesting.isRestoringContentOffset
        )
    }
#endif

    func testImagePipelineCommitsWindowAfterSynchronousPreparationEffect() {
        let pipeline = MobilePlayerCollectionBrowserImagePipeline()
        var callbackSnapshot:
            MobilePlayerCollectionBrowserImagePipeline.Snapshot?
        pipeline.configure(contentAccess: makeImageContentAccess(
            prepareThumbnailWindow: { _, shouldApply, completion in
                callbackSnapshot = pipeline.snapshot()
                completion(shouldApply() ? .committed : .planned)
            }
        ))
        pipeline.setActive(true)
        pipeline.setVisible(true)

        pipeline.prepareThumbnailWindow(
            around: 7,
            direction: .forward,
            force: true,
            configuredPrefetchStride: 6,
            configuredColumnCount: 3,
            requiredImageQuality: .large
        )

        XCTAssertNil(callbackSnapshot?.lastThumbnailWindowRequest)
        XCTAssertEqual(
            pipeline.snapshot().lastThumbnailWindowRequest?.tokenIndex,
            7
        )
    }

    func testScrollCoordinatorSnapshotRestoreRoundTripsAllSnapshotState()
        throws {
        var sourcePublications = [PlayerCollectionScrollPublication]()
        let source = MobilePlayerCollectionBrowserScrollCoordinator()
        source.configure(contentAccess: makeScrollContentAccess(
            publishSettledPosition: {
                sourcePublications.append($0)
                return true
            }
        ))
        source.beginPublicationPositioning(at: 2, snapshotChanged: true)
        source.finishInitialPositioning()
        source.publicationState?.observeCandidate(9)
        source.focusedTokenIndex = 9
        source.forcedFocusedTokenIndex = 8
        source.retainedFocusFocalBias = try XCTUnwrap(
            PlayerCollectionScrollFocalBias(
                referenceFocalY: 240,
                deltaY: -32,
                decayDistance: 120
            )
        )
        source.lastEmittedFocusedTokenIndex = 7
        source.lastScrollOffsetY = 315
        source.setPrefetchDirection(.backward)
        let snapshot = source.snapshot()

        var restoredPublications = [PlayerCollectionScrollPublication]()
        let restored = MobilePlayerCollectionBrowserScrollCoordinator()
        restored.configure(contentAccess: makeScrollContentAccess(
            publishSettledPosition: {
                restoredPublications.append($0)
                return true
            }
        ))
        restored.restore(
            snapshot,
            retainedFocusFocalBias: snapshot.retainedFocusFocalBias,
            lastScrollOffsetY: snapshot.lastScrollOffsetY
        )
        let roundTrip = restored.snapshot()

        XCTAssertEqual(
            roundTrip.publicationState?.lastPublishedTokenIndex,
            snapshot.publicationState?.lastPublishedTokenIndex
        )
        XCTAssertEqual(
            roundTrip.hasFinishedInitialPositioning,
            snapshot.hasFinishedInitialPositioning
        )
        XCTAssertEqual(roundTrip.focusedTokenIndex, snapshot.focusedTokenIndex)
        XCTAssertEqual(
            roundTrip.forcedFocusedTokenIndex,
            snapshot.forcedFocusedTokenIndex
        )
        XCTAssertEqual(
            roundTrip.retainedFocusFocalBias,
            snapshot.retainedFocusFocalBias
        )
        XCTAssertEqual(
            roundTrip.lastEmittedFocusedTokenIndex,
            snapshot.lastEmittedFocusedTokenIndex
        )
        XCTAssertEqual(roundTrip.lastScrollOffsetY, snapshot.lastScrollOffsetY)
        XCTAssertEqual(
            roundTrip.lastPrefetchDirection,
            snapshot.lastPrefetchDirection
        )

        source.settle(hasViewedToEnd: true)
        restored.settle(hasViewedToEnd: true)
        XCTAssertEqual(sourcePublications, restoredPublications)
        XCTAssertEqual(
            source.snapshot().publicationState?.lastPublishedTokenIndex,
            restored.snapshot().publicationState?.lastPublishedTokenIndex
        )
    }

    func testScrollCoordinatorInvalidateIsIdempotentAndRejectsStateChanges() {
        let coordinator = MobilePlayerCollectionBrowserScrollCoordinator()
        coordinator.configure(contentAccess: makeScrollContentAccess())
        coordinator.setActive(true)
        coordinator.setApplyingPosition(true)
        XCTAssertTrue(coordinator.beginScrollMotion())
        coordinator.beginPublicationPositioning(at: 4, snapshotChanged: true)
        coordinator.focusedTokenIndex = 4
        coordinator.forcedFocusedTokenIndex = 5
        coordinator.lastEmittedFocusedTokenIndex = 3
        coordinator.lastScrollOffsetY = 180
        coordinator.setPrefetchDirection(.backward)
        let snapshot = coordinator.snapshot()

        coordinator.invalidate()
        coordinator.invalidate()
        coordinator.setActive(false)
        coordinator.setApplyingPosition(false)
        coordinator.endScrollMotion()
        coordinator.resetInitialPositioning(
            at: 99,
            resetsLastEmittedFocus: true
        )
        coordinator.setPrefetchDirection(.forward)
        coordinator.restore(
            snapshot,
            retainedFocusFocalBias: nil,
            lastScrollOffsetY: 999
        )

        XCTAssertTrue(coordinator.isActive)
        XCTAssertTrue(coordinator.isApplyingPosition)
        XCTAssertTrue(coordinator.isScrollMotionActive)
        XCTAssertEqual(coordinator.focusedTokenIndex, 4)
        XCTAssertEqual(coordinator.forcedFocusedTokenIndex, 5)
        XCTAssertEqual(coordinator.lastEmittedFocusedTokenIndex, 3)
        XCTAssertEqual(coordinator.lastScrollOffsetY, 180)
        XCTAssertEqual(coordinator.lastPrefetchDirection, .backward)
        XCTAssertFalse(coordinator.beginScrollMotion())
        XCTAssertFalse(coordinator.beginDrag(
            contentOffsetY: 20,
            clampedContentOffsetY: 20
        ))
        XCTAssertNil(coordinator.observeContentOffset(20))
        XCTAssertNil(coordinator.updatePrefetchDirection(
            offsetDelta: 10,
            epsilon: 0.5
        ))
        let generation = coordinator.beginPositioning()
        XCTAssertFalse(coordinator.isCurrentPositioningGeneration(generation))
    }

#if DEBUG
    func testScrollCoordinatorInvalidationRejectsPendingFocusScrollAndTimeoutWork()
        async throws {
        var focusedPositions = [PlayerPagePosition]()
        var scheduledScrollObservationCount = 0
        var timeoutCount = 0
        let coordinator = MobilePlayerCollectionBrowserScrollCoordinator()
        coordinator.configure(contentAccess: makeScrollContentAccess(
            publishFocusedPagePosition: { focusedPositions.append($0) },
            performScheduledScrollObservation: {
                scheduledScrollObservationCount += 1
            },
            scrollMotionAnimationDidExpire: { timeoutCount += 1 }
        ))
        coordinator.setActive(true)
        coordinator.hasFinishedInitialPositioning = true
        coordinator.publishFocus(tokenIndex: 1, cadence: .continuous)
        coordinator.publishFocus(tokenIndex: 2, cadence: .continuous)
        coordinator.scheduleScrollUpdate()
        XCTAssertTrue(coordinator.beginScrollMotion())
        coordinator.scheduleScrollMotionAnimationTimeout()
        XCTAssertTrue(coordinator.isScrollMotionAnimationTimeoutScheduled)

        coordinator.invalidate()
        coordinator.invalidate()
        coordinator.scheduleScrollUpdate()
        coordinator.scheduleScrollMotionAnimationTimeout()
        XCTAssertFalse(coordinator.isScrollMotionAnimationTimeoutScheduled)
        await Task.yield()
        await Task.yield()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(focusedPositions, [PlayerPagePosition(position: 1)])
        XCTAssertEqual(scheduledScrollObservationCount, 0)
        XCTAssertEqual(timeoutCount, 0)
    }
#endif

    func testScrollCoordinatorCommitsStateBeforeSynchronousEffectsAndRetry() {
        let coordinator = MobilePlayerCollectionBrowserScrollCoordinator()
        var callbackEvents = [String]()
        var emittedFocusAtCallback: Int?
        var settledIndexAtCallback: Int?
        let acceptsSettlement = SettlementAcceptance()
        coordinator.configure(contentAccess: makeScrollContentAccess(
            publishFocusedPagePosition: { _ in
                emittedFocusAtCallback =
                    coordinator.lastEmittedFocusedTokenIndex
                callbackEvents.append("focus")
            },
            publishSettledPosition: { _ in
                settledIndexAtCallback = coordinator.snapshot()
                    .publicationState?.lastPublishedTokenIndex
                callbackEvents.append(
                    acceptsSettlement.value ? "settled" : "retry"
                )
                return acceptsSettlement.value
            }
        ))
        coordinator.setActive(true)

        coordinator.publishFocus(tokenIndex: 6, cadence: .immediate)
        coordinator.beginPublicationPositioning(at: 2, snapshotChanged: true)
        coordinator.finishInitialPositioning()
        coordinator.publicationState?.observeCandidate(11)
        coordinator.settle(hasViewedToEnd: false)

        XCTAssertEqual(emittedFocusAtCallback, 6)
        XCTAssertEqual(settledIndexAtCallback, 11)
        XCTAssertNil(
            coordinator.snapshot().publicationState?.lastPublishedTokenIndex
        )

        acceptsSettlement.value = true
        coordinator.settle(hasViewedToEnd: false)

        XCTAssertEqual(callbackEvents, ["focus", "retry", "settled"])
        XCTAssertEqual(
            coordinator.snapshot().publicationState?.lastPublishedTokenIndex,
            11
        )
    }
}
