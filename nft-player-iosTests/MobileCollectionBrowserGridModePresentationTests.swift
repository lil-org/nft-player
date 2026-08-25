// ∅ 2026 lil org

import CoreImage
import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class MobileCollectionBrowserGridModePresentationTests: XCTestCase {}

@MainActor
extension MobileCollectionBrowserGridModePresentationTests {

    func testDenseGridImageRefreshQueueRotatesRetriesFairly() {
        var queue = DenseGridImageRefreshQueue()
        for tokenIndex in 0..<10 {
            XCTAssertTrue(queue.enqueue(tokenIndex))
            XCTAssertFalse(queue.enqueue(tokenIndex))
        }

        let firstFrame = queue.dequeue(limit: 5)
        firstFrame.forEach { XCTAssertTrue(queue.enqueue($0)) }
        let secondFrame = queue.dequeue(limit: 5)

        XCTAssertEqual(firstFrame, Array(0..<5))
        XCTAssertEqual(secondFrame, Array(5..<10))
        XCTAssertEqual(queue.count, 5)
    }

    func testDenseGridImageRefreshQueueRemovesOffscreenWork() {
        var queue = DenseGridImageRefreshQueue()
        for tokenIndex in 0..<10 {
            queue.enqueue(tokenIndex)
        }
        for tokenIndex in 0..<10 {
            XCTAssertTrue(queue.remove(tokenIndex))
            XCTAssertFalse(queue.remove(tokenIndex))
        }
        for tokenIndex in 10..<15 {
            queue.enqueue(tokenIndex)
        }

        XCTAssertEqual(queue.count, 5)
        XCTAssertEqual(queue.dequeue(limit: 5), Array(10..<15))
    }

    private final class PlaybackDisplay: MobilePlaybackControllerDisplay {
        func navigate(_ direction: PlaybackNavigationDirection) {}

        func getCurrentPagePosition() -> PlayerPagePosition {
            .initial
        }

        func flushPendingViewingProgress() {}
    }

    private final class TestPinchGestureRecognizer: UIPinchGestureRecognizer {
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
    private final class Fixture {
        let uuid: UUID
        let controller: VerticalCollectionBrowserViewController
        let window: UIWindow

        init(
            uuid: UUID,
            controller: VerticalCollectionBrowserViewController,
            window: UIWindow
        ) {
            self.uuid = uuid
            self.controller = controller
            self.window = window
        }
    }

    @MainActor
    private final class ReentryState {
        var didReenter = false
    }

    private func collectionMetadata(
        minimumTokenCount: Int = 4,
        requiresBundledGenerativeToken: Bool = false
    ) throws -> (
        id: String,
        internalSlug: String
    ) {
        let item = try XCTUnwrap(
            SuggestedItemsService.visibleItems.first { item in
                guard let internalSlug = item.internalSlug,
                      !internalSlug.isEmpty,
                      PlayerCollectionBrowserSupport.isAvailable(
                          forCollectionId: item.id
                      ) else {
                    return false
                }
                let tokenCount = CollectionCatalog.tokenCount(
                    specificCollectionId: item.id
                )
                return tokenCount >= minimumTokenCount && tokenCount <= 512
                    && CollectionCatalog.canGenerateToken(
                        specificCollectionId: item.id,
                        tokenIndex: 0
                    )
                    && (!requiresBundledGenerativeToken
                        || TokenGenerator.bundledWebGenerativeToken(
                            specificCollectionId: item.id,
                            tokenIndex: 0
                        ) != nil)
            }
        )
        return (item.id, try XCTUnwrap(item.internalSlug))
    }

    private func collectionId(internalSlug: String) throws -> String {
        try XCTUnwrap(
            SuggestedItemsService.visibleItems.first {
                $0.internalSlug == internalSlug
            }?.id
        )
    }

    private func makeFixture(
        collectionId: String,
        gridModeCommitSnapshotFactory: ((UIView) -> UIView?)? = nil
    ) throws -> Fixture {
        let uuid = UUID()
        let display = PlaybackDisplay()
        MobilePlaybackController.shared.subscribe(
            config: MobilePlayerConfig(
                id: uuid,
                initialItemId: collectionId,
                initialTokenIndex: 0
            ),
            display: display
        )

        let controller: VerticalCollectionBrowserViewController
        if let gridModeCommitSnapshotFactory {
            controller = VerticalCollectionBrowserViewController(
                uuid: uuid,
                gridModeCommitSnapshotFactory: gridModeCommitSnapshotFactory
            )
        } else {
            controller = VerticalCollectionBrowserViewController(uuid: uuid)
        }
        let foregroundScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        let window = UIWindow(windowScene: foregroundScene)
        window.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.viewDidAppear(false)
        controller.setActive(true)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.gridMode, .threeColumns)
        XCTAssertNotNil(controller.currentPagePosition)
        return Fixture(uuid: uuid, controller: controller, window: window)
    }

    private func tearDownFixture(_ fixture: Fixture) {
        fixture.controller.cancelPendingDisplayPreparation()
        fixture.controller.setActive(false)
        fixture.window.isHidden = true
        fixture.window.rootViewController = nil
        MobilePlaybackController.shared.stopAndDisconnect(uuid: fixture.uuid)
    }

    private func selectGridMode(
        _ mode: MobileCollectionBrowserGridMode,
        controller: VerticalCollectionBrowserViewController
    ) async throws {
        XCTAssertTrue(controller.setGridMode(mode))
        for _ in 0..<200 {
            if controller.gridMode == mode {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Grid mode did not settle to \(mode)")
    }

    private func prepare(
        _ controller: VerticalCollectionBrowserViewController,
        using preparation: PlayerCollectionBrowsePreparation,
        forcePosition: Bool = false
    ) async -> MobilePlayerCollectionBrowserDisplayPreparationResult {
        await withCheckedContinuation { continuation in
            controller.prepareForDisplay(
                using: preparation,
                forcePosition: forcePosition,
                publishWhenStable: false
            ) {
                continuation.resume(returning: $0)
            }
        }
    }

    private func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func waitUntil(
        _ description: String,
        condition: () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(description)
    }

    private func sendPinch(
        _ recognizer: UIPinchGestureRecognizer,
        to controller: VerticalCollectionBrowserViewController
    ) {
        let selector = NSSelectorFromString("handleGridModePinch:")
        XCTAssertTrue(controller.responds(to: selector))
        controller.perform(selector, with: recognizer)
    }

    private func skipIfReduceMotionEnabled() throws {
        try XCTSkipIf(
            UIAccessibility.isReduceMotionEnabled,
            "Reduce Motion applies grid modes directly without a settle"
        )
    }

    private func centerPixelRGBA(
        in image: UIImage
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let ciImage = CIImage(cgImage: cgImage)
        let sampleBounds = CGRect(
            x: floor(ciImage.extent.midX),
            y: floor(ciImage.extent.midY),
            width: 1,
            height: 1
        )
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            CIContext().render(
                ciImage,
                toBitmap: bytes.baseAddress!,
                rowBytes: 4,
                bounds: sampleBounds,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    func testBrowseImageDescriptorSelects260TierForFiveColumns() throws {
        let metadata = try collectionMetadata(
            requiresBundledGenerativeToken: true
        )
        let snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: metadata.id,
            itemCount: CollectionCatalog.tokenCount(
                specificCollectionId: metadata.id
            ),
            initialTokenIndex: 0
        )
        let sources = try XCTUnwrap(
            CollectionCatalog.collectionBrowseImageSources(
                specificCollectionId: metadata.id,
                tokenIndex: 0
            )
        )
        let standardThumbnailURL = try XCTUnwrap(URL(
            string: "https://cdn.lil.org/player/\(metadata.internalSlug)/thumbs/0.webp"
        ))
        let smallThumbnailURL = try XCTUnwrap(URL(
            string: "https://cdn.lil.org/player/\(metadata.internalSlug)/thumbs/260/0.webp"
        ))

        XCTAssertEqual(sources.thumbnailDescriptor.url, standardThumbnailURL)
        XCTAssertEqual(sources.smallThumbnailDescriptor.url, smallThumbnailURL)
        XCTAssertEqual(
            CollectionCatalog.collectionBrowseSizedThumbnailDescriptor(
                specificCollectionId: metadata.id,
                tokenIndex: 0,
                width: .width140
            )?.url,
            URL(string: "https://cdn.lil.org/player/\(metadata.internalSlug)/thumbs/140/0.webp")
        )
        XCTAssertEqual(
            MobilePlaybackController.shared.collectionBrowseImageDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallThumbnail
            ),
            sources.smallThumbnailDescriptor
        )
    }

    func testCompactCoverageRequiresDistinctSmallThumbnails() throws {
        func descriptor(_ name: String) throws
            -> CollectionCatalogDownloadableMediaDescriptor {
            CollectionCatalogDownloadableMediaDescriptor(
                collectionId: "dense-radii",
                tokenId: name,
                tokenIndex: 50,
                media: .staticImage(
                    url: try XCTUnwrap(URL(
                        string: "https://example.com/\(name).webp"
                    )),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
        }
        let small = try descriptor("small")
        let thumbnail = try descriptor("thumbnail")
        let distinctSources = CollectionBrowseImageSources(
            smallThumbnailDescriptor: small,
            thumbnailDescriptor: thumbnail,
            largeDescriptor: thumbnail
        )
        let fallbackSources = CollectionBrowseImageSources(
            thumbnailDescriptor: thumbnail,
            largeDescriptor: thumbnail
        )

        XCTAssertEqual(
            MobilePlaybackController.collectionBrowseCompactCoverage(
                imageSources: distinctSources,
                centeredAt: 50,
                direction: .forward,
                itemCount: 200,
                columnCount: 5,
                prefetchStride: 25,
                quality: .smallThumbnail,
                requiredTokenRange: 20...109
            ),
            PlayerCollectionBrowseMediaWindowPolicy.CompactCoverage(
                decodedRange: 20...109,
                fileRange: 0...199
            )
        )
        XCTAssertNil(
            MobilePlaybackController.collectionBrowseCompactCoverage(
                imageSources: fallbackSources,
                centeredAt: 50,
                direction: .forward,
                itemCount: 200,
                columnCount: 5,
                prefetchStride: 25,
                quality: .smallThumbnail,
                requiredTokenRange: 20...109
            )
        )
        XCTAssertNil(
            MobilePlaybackController.collectionBrowseCompactCoverage(
                imageSources: distinctSources,
                centeredAt: 50,
                direction: .forward,
                itemCount: 200,
                columnCount: 5,
                prefetchStride: 25,
                quality: .thumbnail,
                requiredTokenRange: 20...109
            )
        )
    }

    func testCompactWindowUsesNearestFirstOrdering() throws {
        let descriptor: (Int) -> CollectionCatalogDownloadableMediaDescriptor = {
            tokenIndex in
            CollectionCatalogDownloadableMediaDescriptor(
                collectionId: "dense-window",
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(fileURLWithPath: "/dense-window/\(tokenIndex).webp"),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
        }

        let forward = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 5,
                itemCount: 12,
                direction: .forward,
                prefetchStride: 1,
                compactCoverage: .init(
                    decodedRange: 3...8,
                    fileRange: 0...11
                ),
                descriptorForTokenIndex: descriptor
            )
        )
        let backward = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 5,
                itemCount: 12,
                direction: .backward,
                prefetchStride: 1,
                compactCoverage: .init(
                    decodedRange: 2...7,
                    fileRange: 0...11
                ),
                descriptorForTokenIndex: descriptor
            )
        )
        let standard = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 5,
                itemCount: 12,
                direction: .forward,
                prefetchStride: 1,
                descriptorForTokenIndex: descriptor
            )
        )

        XCTAssertEqual(
            forward.decodedDescriptors.map(\.tokenIndex),
            [5, 6, 4, 7, 3, 8]
        )
        XCTAssertEqual(
            backward.decodedDescriptors.map(\.tokenIndex),
            [5, 4, 6, 3, 7, 2]
        )
        XCTAssertEqual(
            standard.decodedDescriptors.map(\.tokenIndex),
            [5, 6, 7, 4]
        )
    }

    func testCompactWindowContainsFullVisibleRangeAtCollectionEnd() throws {
        let coverage = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowPolicy.compactCoverage(
                centeredAt: 499,
                requiredTokenRange: 445...499,
                itemCount: 500,
                columnCount: 5,
                prefetchStride: 25,
                prefersIncreasingIndices: true
            )
        )
        let window = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 499,
                itemCount: 500,
                direction: .forward,
                prefetchStride: 25,
                compactCoverage: coverage,
                descriptorForTokenIndex: { tokenIndex in
                    CollectionCatalogDownloadableMediaDescriptor(
                        collectionId: "dense-boundary",
                        tokenId: String(tokenIndex),
                        tokenIndex: tokenIndex,
                        media: .staticImage(
                            url: URL(fileURLWithPath:
                                "/dense-boundary/\(tokenIndex).webp"),
                            fileExtension: "webp"
                        ),
                        purpose: .collectionBrowserThumbnail
                    )
                }
            )
        )
        let visibleTokenIndices = Set(445...499)

        XCTAssertEqual(coverage.decodedRange, 445...499)
        XCTAssertTrue(
            visibleTokenIndices.isSubset(of: Set(
                window.descriptors.map(\.tokenIndex)
            ))
        )
        XCTAssertTrue(
            visibleTokenIndices.isSubset(of: Set(
                window.decodedDescriptors.map(\.tokenIndex)
            ))
        )
    }

    func testBrowseImageSourcesFollowCatalogTierLayouts() throws {
        let cases = [
            (
                internalSlug: "card_nft_2",
                thumbnail: "https://cdn.lil.org/nft/card_nft_2/fronts_1400/thumbs/0001.webp",
                width140: "https://cdn.lil.org/nft/card_nft_2/fronts_1400/thumbs/140/0.webp",
                width260: "https://cdn.lil.org/nft/card_nft_2/fronts_1400/thumbs/260/0.webp",
                large: "https://cdn.lil.org/nft/card_nft_2/fronts_1400/0001.webp"
            ),
            (
                internalSlug: "poncho_drifella",
                thumbnail: "https://cdn.lil.org/nft/poncho_drifella/fronts/thumbs/1.webp",
                width140: "https://cdn.lil.org/nft/poncho_drifella/thumbs/140/0.webp",
                width260: "https://cdn.lil.org/nft/poncho_drifella/thumbs/260/0.webp",
                large: "https://cdn.lil.org/nft/poncho_drifella/fronts/1.webp"
            ),
            (
                internalSlug: "drifella_2",
                thumbnail: "https://cdn.lil.org/nft/drifella_2/thumbs/0001.webp",
                width140: "https://cdn.lil.org/nft/drifella_2/thumbs/140/0.webp",
                width260: "https://cdn.lil.org/nft/drifella_2/thumbs/260/0.webp",
                large: "https://cdn.lil.org/nft/drifella_2/mid/0001.webp"
            ),
            (
                internalSlug: "super_metal_mons_2",
                thumbnail: "https://cdn.lil.org/nft/smm2/thumbs/001.webp",
                width140: "https://cdn.lil.org/nft/smm2/thumbs/140/0.webp",
                width260: "https://cdn.lil.org/nft/smm2/thumbs/260/0.webp",
                large: "https://cdn.lil.org/nft/smm2/mid/001.webp"
            ),
            (
                internalSlug: "super_metal_mons",
                thumbnail: "https://cdn.lil.org/nft/smm/thumbs/1.webp",
                width140: "https://cdn.lil.org/nft/smm/thumbs/140/0.webp",
                width260: "https://cdn.lil.org/nft/smm/thumbs/260/0.webp",
                large: "https://cdn.lil.org/nft/smm/mid/1.webp"
            ),
        ]

        for entry in cases {
            let collectionId = try collectionId(
                internalSlug: entry.internalSlug
            )
            let sources = try XCTUnwrap(
                CollectionCatalog.collectionBrowseImageSources(
                    specificCollectionId: collectionId,
                    tokenIndex: 0
                )
            )
            let width140Descriptor = try XCTUnwrap(
                CollectionCatalog.collectionBrowseSizedThumbnailDescriptor(
                    specificCollectionId: collectionId,
                    tokenIndex: 0,
                    width: .width140
                )
            )

            XCTAssertEqual(
                sources.thumbnailDescriptor.url,
                URL(string: entry.thumbnail),
                entry.internalSlug
            )
            XCTAssertEqual(
                width140Descriptor.url,
                URL(string: entry.width140),
                entry.internalSlug
            )
            XCTAssertEqual(
                sources.smallThumbnailDescriptor.url,
                URL(string: entry.width260),
                entry.internalSlug
            )
            XCTAssertEqual(
                sources.largeDescriptor.url,
                URL(string: entry.large),
                entry.internalSlug
            )
        }
    }

#if DEBUG
    func testFiveColumnThumbnailWindowSkipsContinuousScanAndForcesSettlement()
        async throws {
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
        await waitForNextMainQueueTurn()

        let baseline = fixture.controller.thumbnailWindowMetrics
        let firstRow = try XCTUnwrap(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )
        )
        let secondRow = try XCTUnwrap(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 5, section: 0)
            )
        )
        collectionView.contentOffset.y += secondRow.frame.midY
            - firstRow.frame.midY
        fixture.controller.scrollViewDidScroll(collectionView)
        try await waitUntil("Sub-stride scroll update did not run") {
            fixture.controller.thumbnailWindowMetrics
                .skippedDisplayedImageScans
                > baseline.skippedDisplayedImageScans
        }
        XCTAssertEqual(
            fixture.controller.thumbnailWindowMetrics.displayedImageScans,
            baseline.displayedImageScans
        )
        XCTAssertEqual(
            fixture.controller.thumbnailWindowMetrics.preparations,
            baseline.preparations
        )

        fixture.controller.scrollViewDidEndDragging(
            collectionView,
            willDecelerate: false
        )
        XCTAssertEqual(
            fixture.controller.thumbnailWindowMetrics.displayedImageScans,
            baseline.displayedImageScans + 1
        )
        XCTAssertEqual(
            fixture.controller.thumbnailWindowMetrics.preparations,
            baseline.preparations + 1
        )
    }
#endif

    func testFiveColumnDragDefersForegroundImageLoadsUntilDecelerationEnds()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 300)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        func visibleCells() -> [MobilePlayerCollectionBrowserCell] {
            collectionView.visibleCells.compactMap {
                $0 as? MobilePlayerCollectionBrowserCell
            }
        }

        try await selectGridMode(
            .fiveColumns,
            controller: fixture.controller
        )
        await waitForNextMainQueueTurn()
#if DEBUG
        let baselineThumbnailWindowMetrics =
            fixture.controller.thumbnailWindowMetrics
#endif

        XCTAssertFalse(visibleCells().isEmpty)
        XCTAssertTrue(visibleCells().allSatisfy(\.usesForegroundImageLoading))
        let initialVisibleIndexPaths = Set(
            collectionView.indexPathsForVisibleItems
        )

        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(visibleCells().allSatisfy {
            !$0.usesForegroundImageLoading
        })

        let firstRow = try XCTUnwrap(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )
        )
        let distantRow = try XCTUnwrap(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 200, section: 0)
            )
        )
        let distantOffsetDeltaY = distantRow.frame.midY - firstRow.frame.midY
        collectionView.contentOffset.y += distantOffsetDeltaY
        collectionView.layoutIfNeeded()
        fixture.controller.scrollViewDidScroll(collectionView)

        let movedVisibleIndexPaths = Set(
            collectionView.indexPathsForVisibleItems
        )
        XCTAssertFalse(
            movedVisibleIndexPaths.subtracting(initialVisibleIndexPaths)
                .isEmpty
        )
#if DEBUG
        let pendingRefreshCount =
            fixture.controller.pendingDenseGridImageRefreshCount
        XCTAssertGreaterThan(pendingRefreshCount, 0)
        XCTAssertLessThanOrEqual(
            pendingRefreshCount,
            movedVisibleIndexPaths.count
        )
        XCTAssertTrue(fixture.controller.isDenseGridImageDisplayLinkActive)
        XCTAssertEqual(
            fixture.controller
                .drainDenseGridImageDisplayLinkFrameForTesting(),
            min(pendingRefreshCount, 5)
        )

        let refreshIndexPath = try XCTUnwrap(
            collectionView.indexPathsForVisibleItems.first
        )
        let refreshCell = try XCTUnwrap(
            collectionView.cellForItem(
                at: refreshIndexPath
            ) as? MobilePlayerCollectionBrowserCell
        )
        refreshCell.clearDisplayedImageForTesting()
        let refreshDescriptor = try XCTUnwrap(refreshCell.descriptor)
        let injectedImage = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2)
        ).image {
            UIColor.cyan.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        DownloadableMediaCache.shared.installDecodedImageForTesting(
            injectedImage,
            for: refreshDescriptor
        )
        defer {
            DownloadableMediaCache.shared.removeDecodedImageForTesting(
                for: refreshDescriptor
            )
        }
        let baseImageView = try XCTUnwrap(
            refreshCell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertNil(baseImageView.image)
        fixture.controller.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: [refreshIndexPath.item]
        )
        XCTAssertEqual(
            fixture.controller
                .drainDenseGridImageDisplayLinkFrameForTesting(),
            1
        )
        XCTAssertTrue(baseImageView.image === injectedImage)
        XCTAssertFalse(refreshCell.usesForegroundImageLoading)
#endif
#if DEBUG
        try await waitUntil("Rolling thumbnail window did not advance") {
            fixture.controller.thumbnailWindowMetrics.preparations
                > baselineThumbnailWindowMetrics.preparations
        }
#endif

        XCTAssertFalse(visibleCells().isEmpty)
        XCTAssertTrue(visibleCells().allSatisfy {
            !$0.usesForegroundImageLoading
        })

        fixture.controller.scrollViewDidEndDragging(
            collectionView,
            willDecelerate: true
        )
        XCTAssertTrue(visibleCells().allSatisfy {
            !$0.usesForegroundImageLoading
        })

        fixture.controller.scrollViewDidEndDecelerating(collectionView)
        XCTAssertFalse(visibleCells().isEmpty)
        XCTAssertTrue(visibleCells().allSatisfy(\.usesForegroundImageLoading))
#if DEBUG
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
        XCTAssertFalse(fixture.controller.isDenseGridImageDisplayLinkActive)
#endif

        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(visibleCells().allSatisfy {
            !$0.usesForegroundImageLoading
        })
#if DEBUG
        let reverseThumbnailWindowMetrics =
            fixture.controller.thumbnailWindowMetrics
#endif
        collectionView.contentOffset.y -= distantOffsetDeltaY
        collectionView.layoutIfNeeded()
        fixture.controller.scrollViewDidScroll(collectionView)

        XCTAssertEqual(fixture.controller.lastPrefetchDirection, .backward)
        XCTAssertTrue(visibleCells().allSatisfy {
            !$0.usesForegroundImageLoading
        })
#if DEBUG
        try await waitUntil("Reverse thumbnail window did not advance") {
            fixture.controller.thumbnailWindowMetrics.preparations
                > reverseThumbnailWindowMetrics.preparations
        }
        XCTAssertLessThanOrEqual(
            fixture.controller.pendingDenseGridImageRefreshCount,
            collectionView.indexPathsForVisibleItems.count
        )
#endif
        fixture.controller.scrollViewDidEndDragging(
            collectionView,
            willDecelerate: false
        )
        XCTAssertTrue(visibleCells().allSatisfy(\.usesForegroundImageLoading))
#if DEBUG
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
        XCTAssertFalse(fixture.controller.isDenseGridImageDisplayLinkActive)
#endif
    }

#if DEBUG
    func testFiveColumnMotionLimitsCachedImageInstallsPerFrame() async throws {
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
        let indexPaths = Array(
            collectionView.indexPathsForVisibleItems.sorted().prefix(6)
        )
        XCTAssertEqual(indexPaths.count, 6)
        let cells = try indexPaths.map { indexPath in
            try XCTUnwrap(
                collectionView.cellForItem(at: indexPath)
                    as? MobilePlayerCollectionBrowserCell
            )
        }
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2)
        ).image {
            UIColor.cyan.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let descriptors = try cells.map { cell in
            cell.clearDisplayedImageForTesting()
            return try XCTUnwrap(cell.descriptor)
        }
        descriptors.forEach {
            DownloadableMediaCache.shared.installDecodedImageForTesting(
                image,
                for: $0
            )
        }
        defer {
            descriptors.forEach {
                DownloadableMediaCache.shared.removeDecodedImageForTesting(
                    for: $0
                )
            }
        }
        func installedImageCount() -> Int {
            cells.filter { cell in
                cell.contentView.subviews.contains {
                    ($0 as? NativeMetalCardCornerMaskedImageView)?.image != nil
                }
            }.count
        }
        fixture.controller.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: indexPaths.map(\.item)
        )

        XCTAssertEqual(installedImageCount(), 0)
        XCTAssertEqual(
            fixture.controller.drainDenseGridImageDisplayLinkFrameForTesting(),
            5
        )
        XCTAssertEqual(installedImageCount(), 5)
        XCTAssertEqual(
            fixture.controller.drainDenseGridImageDisplayLinkFrameForTesting(),
            1
        )
        XCTAssertEqual(installedImageCount(), 6)
    }
#endif

    func testThreeColumnDragKeepsForegroundImageLoads() throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let visibleCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }

        XCTAssertFalse(visibleCells.isEmpty)
        XCTAssertTrue(visibleCells.allSatisfy(\.usesForegroundImageLoading))

        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(visibleCells.allSatisfy(\.usesForegroundImageLoading))

        fixture.controller.scrollViewDidEndDragging(
            collectionView,
            willDecelerate: false
        )
        XCTAssertTrue(visibleCells.allSatisfy(\.usesForegroundImageLoading))
    }

#if DEBUG
    func testForcedPreparationEndsScrollMotion() async throws {
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
        XCTAssertTrue(fixture.controller.isScrollMotionActiveForTesting)
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
        let pagePosition = try XCTUnwrap(fixture.controller.currentPagePosition)
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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

    func testControllerDeallocatesWithActiveInteractionFadeDisplayLink()
        async throws {
        let metadata = try collectionMetadata()
        let uuid = UUID()
        let display = PlaybackDisplay()
        MobilePlaybackController.shared.subscribe(
            config: MobilePlayerConfig(
                id: uuid,
                initialItemId: metadata.id,
                initialTokenIndex: 0
            ),
            display: display
        )
        var candidate: VerticalCollectionBrowserViewController? =
            VerticalCollectionBrowserViewController(uuid: uuid)
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
        MobilePlaybackController.shared.stopAndDisconnect(uuid: uuid)
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

    func testCommitSnapshotBlocksSelectionUntilItDissolves() async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: {
                UIView(frame: $0.bounds)
            }
        )
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

        try await waitUntil("Snapshot did not finish dissolving") {
            fixture.controller.collectionView(
                collectionView,
                shouldSelectItemAt: indexPath
            )
        }

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
        let fixture = try makeFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: { _ in
                snapshotRequestCount += 1
                return nil
            }
        )
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
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
        await waitForNextMainQueueTurn()

        XCTAssertFalse(collectionView.isScrollEnabled)

        recognizer.scale = 0.9
        sendPinch(recognizer, to: controller)
        await waitForNextMainQueueTurn()

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
        let fixture = try makeFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: { _ in
                snapshotRequestCount += 1
                return nil
            }
        )
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
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
        await waitForNextMainQueueTurn()

        recognizer.scale = 0.9
        sendPinch(recognizer, to: controller)
        await waitForNextMainQueueTurn()

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
        let fixture = try makeFixture(
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
        await waitForNextMainQueueTurn()

        XCTAssertEqual(snapshotRequestCount, 0)

        recognizer.scale = 0.9
        sendPinch(recognizer, to: controller)
        await waitForNextMainQueueTurn()

        let firstSnapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshotRequestCount, 1)
        XCTAssertTrue(firstSnapshot.superview === controller.view)

        recognizer.scale = 0.5
        sendPinch(recognizer, to: controller)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(snapshotRequestCount, 1)
        XCTAssertTrue(firstSnapshot.superview === controller.view)

        recognizer.scale = 1.5
        sendPinch(recognizer, to: controller)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(snapshotRequestCount, 2)
        XCTAssertNil(firstSnapshot.superview)
        let fallbackCover = try XCTUnwrap(
            controller.view.subviews.first { $0 is UIImageView }
                as? UIImageView
        )
        XCTAssertEqual(try XCTUnwrap(fallbackCover.image).scale, 1)
        XCTAssertTrue(fallbackCover.superview === controller.view)
        XCTAssertFalse(collectionView.isScrollEnabled)
    }

    func testZeroAlphaPlaneReversalSkipsSnapshotAndKeepsPinchActive()
        async throws {
        let metadata = try collectionMetadata()
        var snapshotRequestCount = 0
        let fixture = try makeFixture(
            collectionId: metadata.id,
            gridModeCommitSnapshotFactory: { view in
                snapshotRequestCount += 1
                return UIView(frame: view.bounds)
            }
        )
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
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
        await waitForNextMainQueueTurn()

        recognizer.scale = 1.03
        sendPinch(recognizer, to: controller)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertFalse(collectionView.isScrollEnabled)

        recognizer.scale = 1.05
        sendPinch(recognizer, to: controller)
        await waitForNextMainQueueTurn()

        XCTAssertEqual(snapshotRequestCount, 0)
        XCTAssertFalse(collectionView.isScrollEnabled)
    }

    func testPinchEndAppliesTerminalScaleWithoutTerminalCentroid() async throws {
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
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

        for _ in 0..<200 {
            if controller.gridMode == .fiveColumns {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(controller.gridMode, .fiveColumns)
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
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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

    func testSettleReservesCollectionPanForOneFingerAndRestoresIt() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
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
        let fixture = try makeFixture(collectionId: metadata.id)
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
                reentryState.didReenter = true
                fixture.controller.scrollViewDidEndDecelerating(collectionView)
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
        let fixture = try makeFixture(collectionId: metadata.id)
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
                reentryState.didReenter = true
                fixture.controller.scrollViewWillBeginDragging(collectionView)
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
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        )
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
                reentryState.didReenter = true
                fixture.controller.scrollViewWillBeginDragging(collectionView)
            }
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        for _ in 0..<200 {
            if fixture.controller.gridMode == .fiveColumns {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
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

    func testAccessibilityScrollInterruptsSettleBeforeScrolling() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
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
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        _ = collectionView.accessibilityScroll(.down)

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertEqual(
            panGestureRecognizer.maximumNumberOfTouches,
            configuredMaximumNumberOfTouches
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
    }

    func testFailedAccessibilityScrollSettlesInterruptedPosition() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
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

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertFalse(collectionView.accessibilityScroll(.left))

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
        let visibleCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(visibleCells.isEmpty)
        XCTAssertTrue(visibleCells.allSatisfy(\.usesForegroundImageLoading))
    }

    func testFailedAccessibilityAttemptKeepsActiveScrollImageDeferral()
        async throws {
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
        let activeAttempt = try XCTUnwrap(
            collectionView.onWillAccessibilityScroll?()
        )
        collectionView.onAccessibilityScrollResult?(true, activeAttempt)
#if DEBUG
        XCTAssertTrue(
            fixture.controller
                .isScrollMotionAnimationTimeoutScheduled
        )
#endif
        let failedAttempt = try XCTUnwrap(
            collectionView.onWillAccessibilityScroll?()
        )
        collectionView.onAccessibilityScrollResult?(false, failedAttempt)

        let deferredCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(deferredCells.isEmpty)
        XCTAssertTrue(deferredCells.allSatisfy {
            !$0.usesForegroundImageLoading
        })

#if DEBUG
        XCTAssertTrue(
            fixture.controller
                .isScrollMotionAnimationTimeoutScheduled
        )
        fixture.controller.expireScrollMotionAnimationForTesting()
        XCTAssertFalse(
            fixture.controller
                .isScrollMotionAnimationTimeoutScheduled
        )
#else
        fixture.controller.scrollViewDidEndScrollingAnimation(collectionView)
#endif
        let resumedCells = collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }
        XCTAssertFalse(resumedCells.isEmpty)
        XCTAssertTrue(resumedCells.allSatisfy(\.usesForegroundImageLoading))
#if DEBUG
        XCTAssertEqual(fixture.controller.pendingDenseGridImageRefreshCount, 0)
        XCTAssertFalse(fixture.controller.isDenseGridImageDisplayLinkActive)
#endif
    }

#if DEBUG
    func testFailedAccessibilityAttemptReschedulesGeometryPrewarming() throws {
        let fixture = try makeFixture(
            collectionId: collectionId(internalSlug: "in_your_dreams")
        )
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        fixture.controller.resetGridModeGeometryPrewarmingForTesting()
        XCTAssertFalse(
            fixture.controller.hasPendingGridModeGeometryPrewarmForTesting
        )
        let attempt = try XCTUnwrap(
            collectionView.onWillAccessibilityScroll?()
        )
        XCTAssertFalse(attempt.interruptedGridModeSettle)

        collectionView.onAccessibilityScrollResult?(false, attempt)

        XCTAssertTrue(
            fixture.controller.hasPendingGridModeGeometryPrewarmForTesting
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

    func testFailedAccessibilityScrollAppliesPendingSafeAreaRefreshBeforeSettlement()
        throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        var settledContentSizeHeights = [CGFloat]()
        fixture.controller.onSettledPagePosition = { _, _ in
            settledContentSizeHeights.append(collectionView.contentSize.height)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        fixture.controller.additionalSafeAreaInsets.bottom += 37
        XCTAssertFalse(collectionView.accessibilityScroll(.left))

        XCTAssertEqual(settledContentSizeHeights.count, 1)
        fixture.controller.view.layoutIfNeeded()
        XCTAssertEqual(
            settledContentSizeHeights,
            [collectionView.contentSize.height]
        )
    }

    func testScrollToTopInterruptsSettleBeforeAcceptance() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
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
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        XCTAssertTrue(
            fixture.controller.scrollViewShouldScrollToTop(collectionView)
        )

        XCTAssertEqual(fixture.controller.gridMode, .fiveColumns)
        XCTAssertEqual(
            panGestureRecognizer.maximumNumberOfTouches,
            configuredMaximumNumberOfTouches
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            -collectionView.adjustedContentInset.top,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
        fixture.controller.scrollViewDidScrollToTop(collectionView)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
    }

    func testScrollToTopWithMotionDefersInterruptedPositionSettlement() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        let scrolledOffsetY = min(maximumOffsetY, 1_000)
        XCTAssertGreaterThan(scrolledOffsetY, minimumOffsetY)
        collectionView.contentOffset.y = scrolledOffsetY
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertTrue(
            fixture.controller.scrollViewShouldScrollToTop(collectionView)
        )

        XCTAssertGreaterThan(
            collectionView.contentOffset.y,
            -collectionView.adjustedContentInset.top
        )
        XCTAssertTrue(settledPagePositions.isEmpty)

        collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        fixture.controller.scrollViewDidScrollToTop(collectionView)

        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
    }

    func testProgrammaticScrollPreservesOffsetDeltaAfterSettleCommit() async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let focusedPagePosition = PlayerPagePosition(position: 3)
        let committedOffsetY = try await { () async throws -> CGFloat in
            let baselineFixture = try makeFixture(collectionId: metadata.id)
            defer { tearDownFixture(baselineFixture) }
            let preparation = try XCTUnwrap(
                MobilePlaybackController.shared.prepareCollectionBrowse(
                    uuid: baselineFixture.uuid,
                    containing: focusedPagePosition
                )
            )
            let preparationResult = await prepare(
                baselineFixture.controller,
                using: preparation
            )
            XCTAssertEqual(preparationResult, .prepared)
            let baselineCollectionView = try XCTUnwrap(
                baselineFixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            XCTAssertTrue(baselineFixture.controller.setGridMode(.large))
            baselineFixture.controller.setActive(false)
            return baselineCollectionView.contentOffset.y
        }()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: focusedPagePosition
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
        let sourceOffsetY = collectionView.contentOffset.y
        XCTAssertGreaterThan(abs(committedOffsetY - sourceOffsetY), 1)
        let requestedDeltaY: CGFloat = 24
        var settledPagePositions = [PlayerPagePosition]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        let targetOffset = CGPoint(
            x: collectionView.contentOffset.x,
            y: collectionView.contentOffset.y + requestedDeltaY
        )
        collectionView.setContentOffset(targetOffset, animated: false)

        XCTAssertEqual(fixture.controller.gridMode, .large)
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        XCTAssertEqual(
            collectionView.contentOffset.y,
            min(
                max(committedOffsetY + requestedDeltaY, minimumOffsetY),
                maximumOffsetY
            ),
            accuracy: 0.000_001
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
    }

    func testProgrammaticNoOpOffsetsDoNotInterruptSettle() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let maximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches = maximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
        let settleContentOffset = collectionView.contentOffset

        collectionView.setContentOffset(
            settleContentOffset,
            animated: false
        )
        collectionView.setContentOffset(
            CGPoint(
                x: settleContentOffset.x + 10,
                y: settleContentOffset.y
            ),
            animated: false
        )

        XCTAssertEqual(collectionView.contentOffset, settleContentOffset)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
    }

    func testObservedNonDragScrollPreservesOffsetDeltaAfterSettleCommit()
        async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let focusedPagePosition = PlayerPagePosition(position: 3)
        let committedContentOffsetY = try await {
            () async throws -> CGFloat in
            let baselineFixture = try makeFixture(
                collectionId: metadata.id
            )
            defer { tearDownFixture(baselineFixture) }
            let preparation = try XCTUnwrap(
                MobilePlaybackController.shared.prepareCollectionBrowse(
                    uuid: baselineFixture.uuid,
                    containing: focusedPagePosition
                )
            )
            let preparationResult = await prepare(
                baselineFixture.controller,
                using: preparation
            )
            XCTAssertEqual(preparationResult, .prepared)
            let baselineCollectionView = try XCTUnwrap(
                baselineFixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            XCTAssertTrue(
                baselineFixture.controller.setGridMode(.large)
            )
            baselineFixture.controller.setActive(false)
            return baselineCollectionView.contentOffset.y
        }()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
                containing: focusedPagePosition
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
        let sourceContentOffsetY = collectionView.contentOffset.y
        XCTAssertGreaterThan(
            abs(committedContentOffsetY - sourceContentOffsetY),
            1
        )
        let observedDeltaY: CGFloat = 24
        let shiftedSourceContentOffsetY = sourceContentOffsetY
            + observedDeltaY
        var settledPagePositions = [PlayerPagePosition]()
        var settledContentOffsetYs = [CGFloat]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            settledContentOffsetYs.append(collectionView.contentOffset.y)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        collectionView.contentOffset = CGPoint(
            x: collectionView.contentOffset.x,
            y: shiftedSourceContentOffsetY
        )

        let accuracy: CGFloat = 0.000_001
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        let expectedContentOffsetY = min(
            max(
                committedContentOffsetY + observedDeltaY,
                minimumOffsetY
            ),
            maximumOffsetY
        )
        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            expectedContentOffsetY,
            accuracy: accuracy
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
        XCTAssertEqual(settledContentOffsetYs.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(settledContentOffsetYs.first),
            expectedContentOffsetY,
            accuracy: accuracy
        )
    }

    func testObservedNonDragScrollPreservesItsOffsetDelta() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let committedOffsetY = try { () throws -> CGFloat in
            let baselineFixture = try makeFixture(collectionId: metadata.id)
            defer { tearDownFixture(baselineFixture) }
            let baselineCollectionView = try XCTUnwrap(
                baselineFixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            XCTAssertTrue(baselineFixture.controller.setGridMode(.large))
            baselineFixture.controller.setActive(false)
            return baselineCollectionView.contentOffset.y
        }()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let targetOffset = CGPoint(
            x: collectionView.contentOffset.x,
            y: collectionView.contentOffset.y + 24
        )
        var settledPagePositions = [PlayerPagePosition]()
        var settledContentOffsetYs = [CGFloat]()
        fixture.controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            settledContentOffsetYs.append(collectionView.contentOffset.y)
            return true
        }

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        collectionView.contentOffset = targetOffset

        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            committedOffsetY + 24,
            accuracy: 0.000_001
        )
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertEqual(
            settledPagePositions,
            [try XCTUnwrap(fixture.controller.currentPagePosition)]
        )
        XCTAssertEqual(settledContentOffsetYs.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(settledContentOffsetYs.first),
            committedOffsetY + 24,
            accuracy: 0.000_001
        )
    }

    func testObservedNonDragScrollUpdatesPrefetchDirectionAfterSettleCommit()
        async throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let tokenCount = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        )
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let preparation = try XCTUnwrap(
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let backwardOffsetY = max(
            collectionView.contentOffset.y - 24,
            minimumOffsetY
        )
        XCTAssertLessThan(backwardOffsetY, collectionView.contentOffset.y)
        collectionView.contentOffset.y = backwardOffsetY
        XCTAssertEqual(fixture.controller.lastPrefetchDirection, .backward)

        XCTAssertTrue(fixture.controller.setGridMode(.large))
        collectionView.contentOffset.y += 24

        XCTAssertEqual(fixture.controller.gridMode, .large)
        XCTAssertEqual(fixture.controller.lastPrefetchDirection, .forward)
    }

    func testObservedNonDragScrollClampsResumedOffsetAtBothBoundaries()
        throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()

        try [false, true].forEach { movesTowardEnd in
            let fixture = try makeFixture(collectionId: metadata.id)
            defer { tearDownFixture(fixture) }
            let collectionView = try XCTUnwrap(
                fixture.controller.view.subviews.first {
                    $0 is MobilePlayerCollectionBrowserCollectionView
                } as? MobilePlayerCollectionBrowserCollectionView
            )
            var settledContentOffsetYs = [CGFloat]()
            fixture.controller.onSettledPagePosition = { _, _ in
                settledContentOffsetYs.append(collectionView.contentOffset.y)
                return true
            }

            XCTAssertTrue(fixture.controller.setGridMode(.large))
            let offsetDeltaY: CGFloat = movesTowardEnd
                ? 1_000_000
                : -1_000_000
            collectionView.contentOffset = CGPoint(
                x: collectionView.contentOffset.x,
                y: collectionView.contentOffset.y + offsetDeltaY
            )
            collectionView.layoutIfNeeded()

            let minimumOffsetY = -collectionView.adjustedContentInset.top
            let maximumOffsetY = max(
                minimumOffsetY,
                collectionView.contentSize.height
                    - collectionView.bounds.height
                    + collectionView.adjustedContentInset.bottom
            )
            let expectedOffsetY = movesTowardEnd
                ? maximumOffsetY
                : minimumOffsetY
            XCTAssertEqual(
                collectionView.contentOffset.y,
                expectedOffsetY,
                accuracy: 0.000_001
            )
            XCTAssertEqual(settledContentOffsetYs.count, 1)
            XCTAssertEqual(
                try XCTUnwrap(settledContentOffsetYs.first),
                expectedOffsetY,
                accuracy: 0.000_001
            )
        }
    }

    func testNoMotionScrollNotificationDoesNotInterruptSettle() throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let maximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches = maximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)

        fixture.controller.scrollViewDidScroll(collectionView)

        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
    }

    func testObservedHorizontalOffsetIsRejectedWithoutInterruptingSettle()
        throws {
        try skipIfReduceMotionEnabled()
        let metadata = try collectionMetadata()
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let collectionView = try XCTUnwrap(
            fixture.controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let panGestureRecognizer = collectionView.panGestureRecognizer
        let maximumNumberOfTouches = 4
        panGestureRecognizer.maximumNumberOfTouches = maximumNumberOfTouches

        XCTAssertTrue(fixture.controller.setGridMode(.fiveColumns))
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
        let settleContentOffset = collectionView.contentOffset

        collectionView.contentOffset = CGPoint(
            x: settleContentOffset.x + 10,
            y: settleContentOffset.y
        )

        XCTAssertEqual(collectionView.contentOffset, settleContentOffset)
        XCTAssertEqual(panGestureRecognizer.maximumNumberOfTouches, 1)
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
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
            MobilePlaybackController.shared.prepareCollectionBrowse(
                uuid: fixture.uuid,
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
