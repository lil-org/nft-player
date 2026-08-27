// ∅ 2026 lil org

import CoreImage
import UIKit
import XCTest
@testable import nft_player_ios

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

    func testDenseGridImageRefreshBatchScalesToNineColumnsWithinBounds() {
        XCTAssertEqual(DenseGridImageRefreshPolicy.batchSize(baseColumnCount: 0), 5)
        XCTAssertEqual(DenseGridImageRefreshPolicy.batchSize(baseColumnCount: 3), 5)
        XCTAssertEqual(DenseGridImageRefreshPolicy.batchSize(baseColumnCount: 5), 5)
        XCTAssertEqual(DenseGridImageRefreshPolicy.batchSize(baseColumnCount: 9), 9)
        XCTAssertEqual(DenseGridImageRefreshPolicy.batchSize(baseColumnCount: 18), 9)
        XCTAssertEqual(
            DenseGridImageRefreshPolicy.batchSize(baseColumnCount: Int.max),
            9
        )
    }

    func testBrowseImageDescriptorsSelectSizedTiersForDenseModes() throws {
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
        let smallestThumbnailURL = try XCTUnwrap(URL(
            string: "https://cdn.lil.org/player/\(metadata.internalSlug)/thumbs/140/0.webp"
        ))
        let smallestThumbnailDescriptor = try XCTUnwrap(
            sources.smallestThumbnailDescriptor
        )

        XCTAssertEqual(sources.thumbnailDescriptor.url, standardThumbnailURL)
        XCTAssertEqual(sources.smallThumbnailDescriptor.url, smallThumbnailURL)
        XCTAssertEqual(
            smallestThumbnailDescriptor.url,
            smallestThumbnailURL
        )
        XCTAssertEqual(
            MobilePlaybackController.shared.collectionBrowseImageDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallThumbnail
            ),
            sources.smallThumbnailDescriptor
        )
        XCTAssertEqual(
            MobilePlaybackController.shared.collectionBrowseImageDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallestThumbnail
            ),
            smallestThumbnailDescriptor
        )
    }

#if DEBUG
    func testNineColumnPrefetchReusesCachedHigherQualityThumbnails() throws {
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
        let cache = DownloadableMediaCache.shared
        let smallestThumbnailDescriptor = try XCTUnwrap(
            sources.smallestThumbnailDescriptor
        )
        let descriptors = [
            smallestThumbnailDescriptor,
            sources.smallThumbnailDescriptor,
            sources.thumbnailDescriptor,
        ]
        descriptors.forEach { cache.removeDecodedImageForTesting(for: $0) }
        defer {
            descriptors.forEach { cache.removeDecodedImageForTesting(for: $0) }
        }

        XCTAssertEqual(
            MobilePlaybackController.shared.collectionBrowsePrefetchDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallestThumbnail
            ),
            smallestThumbnailDescriptor
        )

        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2)
        ).image { _ in }
        cache.installDecodedImageForTesting(
            image,
            for: sources.smallThumbnailDescriptor
        )
        XCTAssertNil(
            MobilePlaybackController.shared.collectionBrowsePrefetchDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallestThumbnail
            )
        )

        cache.removeDecodedImageForTesting(
            for: sources.smallThumbnailDescriptor
        )
        cache.installDecodedImageForTesting(
            image,
            for: sources.thumbnailDescriptor
        )
        XCTAssertNil(
            MobilePlaybackController.shared.collectionBrowsePrefetchDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallestThumbnail
            )
        )
    }
#endif

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
        let smallest = try descriptor("smallest")
        let thumbnail = try descriptor("thumbnail")
        let distinctSources = CollectionBrowseImageSources(
            smallestThumbnailDescriptor: smallest,
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
        XCTAssertEqual(
            MobilePlaybackController.collectionBrowseCompactCoverage(
                imageSources: distinctSources,
                centeredAt: 50,
                direction: .forward,
                itemCount: 200,
                columnCount: 9,
                prefetchStride: 45,
                quality: .smallestThumbnail,
                requiredTokenRange: 18...107
            ),
            PlayerCollectionBrowseMediaWindowPolicy.CompactCoverage(
                decodedRange: 18...107,
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
                imageSources: fallbackSources,
                centeredAt: 50,
                direction: .forward,
                itemCount: 200,
                columnCount: 9,
                prefetchStride: 45,
                quality: .smallestThumbnail,
                requiredTokenRange: 18...107
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
            let smallestThumbnailDescriptor = try XCTUnwrap(
                sources.smallestThumbnailDescriptor
            )

            XCTAssertEqual(
                sources.thumbnailDescriptor.url,
                URL(string: entry.thumbnail),
                entry.internalSlug
            )
            XCTAssertEqual(
                smallestThumbnailDescriptor.url,
                URL(string: entry.width140),
                entry.internalSlug
            )
            XCTAssertEqual(
                width140Descriptor,
                smallestThumbnailDescriptor,
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

    func testNineColumnDragDefersForegroundImageLoadsUntilDragEnds()
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
            .nineColumns,
            controller: fixture.controller
        )
        await waitForNextMainQueueTurn()
        XCTAssertEqual(fixture.controller.gridMode, .nineColumns)
        XCTAssertFalse(collectionView.visibleCells.isEmpty)
        XCTAssertTrue(collectionView.visibleCells.allSatisfy {
            ($0 as? MobilePlayerCollectionBrowserCell)?
                .usesForegroundImageLoading == true
        })

        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(collectionView.visibleCells.allSatisfy {
            ($0 as? MobilePlayerCollectionBrowserCell)?
                .usesForegroundImageLoading == false
        })

        fixture.controller.scrollViewDidEndDragging(
            collectionView,
            willDecelerate: false
        )
        XCTAssertTrue(collectionView.visibleCells.allSatisfy {
            ($0 as? MobilePlayerCollectionBrowserCell)?
                .usesForegroundImageLoading == true
        })
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
}
