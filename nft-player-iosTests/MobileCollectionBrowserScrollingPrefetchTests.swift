// ∅ 2026 lil org

import CoreImage
import Dispatch
import os
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
extension MobileCollectionBrowserGridModePresentationTests {

    func testThumbnailWindowPlannerCachesSourcesAcrossPlansAndSkipsSatisfiedTokens()
        async throws {
        let resolutionCount = OSAllocatedUnfairLock(initialState: 0)
        let resolvedTokenIndices = OSAllocatedUnfairLock(
            initialState: Set<Int>()
        )
        let snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: "planner-cache",
            itemCount: 200,
            initialTokenIndex: 0
        )
        let cache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            resolutionCount.withLock { $0 += 1 }
            resolvedTokenIndices.withLock { _ = $0.insert(tokenIndex) }
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath: "/planner-cache/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            let smallDescriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/planner-cache/260/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                smallThumbnailDescriptor: smallDescriptor,
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let planner = MobileCollectionBrowseThumbnailWindowPlanner(
            imageSourcesCache: cache
        )
        let request = MobileCollectionBrowseThumbnailWindowPlanRequest(
            snapshot: snapshot,
            tokenIndex: 100,
            direction: .forward,
            prefetchStride: 25,
            columnCount: 5,
            quality: .smallThumbnail,
            requiredTokenRange: 99...101,
            visibleTokenRange: 99...101,
            isFileOnly: false,
            decodeVariant: .downsampled(maxPixelWidth: 256),
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [101],
            locallyAvailableLargeTokenIndices: []
        )

        let firstWindow = await planner.makeWindow(for: request)
        let firstResolutionCount = resolutionCount.withLock { $0 }
        let secondWindow = await planner.makeWindow(for: request)

        XCTAssertNotNil(firstWindow)
        XCTAssertEqual(secondWindow, firstWindow)
        XCTAssertGreaterThan(firstResolutionCount, 0)
        XCTAssertEqual(
            resolutionCount.withLock { $0 },
            firstResolutionCount
        )
        XCTAssertFalse(resolvedTokenIndices.withLock { $0.contains(101) })
        XCTAssertEqual(
            firstWindow?.decodedDescriptors.map(\.tokenIndex),
            [100, 99, 102, 98, 103, 97, 104, 96, 95]
        )
    }

    func testThumbnailWindowPlannerPublishesSharedSourcesWithoutBlockingMainActor()
        async throws {
        let resolutionState = OSAllocatedUnfairLock(
            initialState: (
                tokenIndices: Set<Int>(),
                invocationCount: 0,
                didBlockCenter: false
            )
        )
        let resolutionStarted = expectation(
            description: "Descriptor resolution started"
        )
        let resumeResolution = DispatchSemaphore(value: 0)
        let resolutionWaitTimedOut = OSAllocatedUnfairLock(
            initialState: false
        )
        let snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: "shared-planner-cache",
            itemCount: 40,
            initialTokenIndex: 10
        )
        let cache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            let shouldBlock = resolutionState.withLock { state in
                _ = state.tokenIndices.insert(tokenIndex)
                state.invocationCount += 1
                guard tokenIndex == 10, !state.didBlockCenter else {
                    return false
                }
                state.didBlockCenter = true
                return true
            }
            if shouldBlock {
                resolutionStarted.fulfill()
                if resumeResolution.wait(
                    timeout: .now() + .seconds(2)
                ) == .timedOut {
                    resolutionWaitTimedOut.withLock { $0 = true }
                }
            }
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/shared-planner-cache/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                smallThumbnailDescriptor: descriptor,
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let planner = MobileCollectionBrowseThumbnailWindowPlanner(
            imageSourcesCache: cache
        )
        let request = MobileCollectionBrowseThumbnailWindowPlanRequest(
            snapshot: snapshot,
            tokenIndex: 10,
            direction: .forward,
            prefetchStride: 10,
            columnCount: 5,
            quality: .smallThumbnail,
            requiredTokenRange: 5...19,
            visibleTokenRange: 5...19,
            isFileOnly: false,
            decodeVariant: .downsampled(maxPixelWidth: 256),
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: []
        )

        XCTAssertNil(cache.cachedImageSources(
            snapshot: snapshot,
            tokenIndex: 10
        ))
        let firstPlan = Task { await planner.makeWindow(for: request) }
        await fulfillment(of: [resolutionStarted], timeout: 1)
        let secondPlan = Task { await planner.makeWindow(for: request) }
        let heartbeat = expectation(description: "Main actor remained responsive")
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 1)
        resumeResolution.signal()

        let firstWindow = await firstPlan.value
        let secondWindow = await secondPlan.value
        let resolutionSnapshot = resolutionState.withLock { $0 }
        let resolvedCount = resolutionSnapshot.tokenIndices.count
        let invocationCount = resolutionSnapshot.invocationCount

        XCTAssertNotNil(firstWindow)
        XCTAssertEqual(secondWindow, firstWindow)
        XCTAssertFalse(resolutionWaitTimedOut.withLock { $0 })
        XCTAssertGreaterThan(resolvedCount, 0)
        XCTAssertEqual(invocationCount, resolvedCount)
        XCTAssertNotNil(cache.cachedImageSources(
            snapshot: snapshot,
            tokenIndex: 10
        ))
        let repeatedWindow = await planner.makeWindow(for: request)
        XCTAssertNotNil(repeatedWindow)
        XCTAssertEqual(
            resolutionState.withLock { $0.invocationCount },
            invocationCount
        )
    }

    func testSnapshotChangeRetainsInFlightPlannerPublication() async {
        let staleResolutionStarted = expectation(
            description: "Stale image source resolution started"
        )
        let resumeStaleResolution = DispatchSemaphore(value: 0)
        let staleResolutionWaitTimedOut = OSAllocatedUnfairLock(
            initialState: false
        )
        let cache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            if snapshot.collectionId == "stale" {
                staleResolutionStarted.fulfill()
                if resumeStaleResolution.wait(
                    timeout: .now() + .seconds(2)
                ) == .timedOut {
                    staleResolutionWaitTimedOut.withLock { $0 = true }
                }
            }
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/stale-planner/\(snapshot.collectionId)/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let staleSnapshot = PlayerCollectionBrowseSnapshot(
            collectionId: "stale",
            itemCount: 10,
            initialTokenIndex: 0
        )
        let activeSnapshot = PlayerCollectionBrowseSnapshot(
            collectionId: "active",
            itemCount: 10,
            initialTokenIndex: 0
        )
        let staleRequest = isolatedPlannerRequest(
            snapshot: staleSnapshot,
            tokenIndex: 0
        )
        let planner = MobileCollectionBrowseThumbnailWindowPlanner(
            imageSourcesCache: cache
        )
        let staleResolution = Task {
            await planner.makeWindow(for: staleRequest)
        }
        await fulfillment(of: [staleResolutionStarted], timeout: 1)
        resumeStaleResolution.signal()
        let staleWindow = await staleResolution.value

        XCTAssertNotNil(staleWindow)
        XCTAssertFalse(staleResolutionWaitTimedOut.withLock { $0 })
        XCTAssertEqual(cache.cachedImageSourceCount, 1)
        XCTAssertNotNil(cache.cachedImageSources(
            snapshot: staleSnapshot,
            tokenIndex: 0
        ))

        let activeWindow = await planner.makeWindow(
            for: isolatedPlannerRequest(
                snapshot: activeSnapshot,
                tokenIndex: 0
            )
        )

        XCTAssertNotNil(activeWindow)
        XCTAssertNotNil(cache.cachedImageSources(
            snapshot: activeSnapshot,
            tokenIndex: 0
        ))
        XCTAssertNotNil(cache.cachedImageSources(
            snapshot: staleSnapshot,
            tokenIndex: 0
        ))
        XCTAssertEqual(cache.cachedImageSourceCount, 2)
    }

    func testThumbnailWindowPlannerBuildsNineColumnCompactWindow() async throws {
        let snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: "planner-nine-column",
            itemCount: 200,
            initialTokenIndex: 0
        )
        let cache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            let thumbnail = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/planner-nine/thumbnail/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            let smallest = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/planner-nine/140/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                smallestThumbnailDescriptor: smallest,
                thumbnailDescriptor: thumbnail,
                largeDescriptor: thumbnail
            )
        }
        let planner = MobileCollectionBrowseThumbnailWindowPlanner(
            imageSourcesCache: cache
        )
        let request = MobileCollectionBrowseThumbnailWindowPlanRequest(
            snapshot: snapshot,
            tokenIndex: 100,
            direction: .backward,
            prefetchStride: 25,
            columnCount: 9,
            quality: .smallestThumbnail,
            requiredTokenRange: 99...101,
            visibleTokenRange: 99...101,
            isFileOnly: false,
            decodeVariant: .downsampled(maxPixelWidth: 160),
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: []
        )

        let plannedWindow = await planner.makeWindow(for: request)
        let window = try XCTUnwrap(plannedWindow)

        XCTAssertFalse(window.descriptors.isEmpty)
        XCTAssertFalse(window.decodedDescriptors.isEmpty)
        XCTAssertTrue(window.descriptors.allSatisfy {
            $0.url.path.contains("/140/")
        })
        XCTAssertEqual(
            window.descriptors.map(\.tokenIndex),
            [100, 99, 101]
                + Array(stride(from: 98, through: 48, by: -1))
                + Array(102...107)
        )
        XCTAssertEqual(
            window.decodedDescriptors.map(\.tokenIndex),
            [100, 99, 101, 102, 103, 104, 105, 106, 107]
        )
        XCTAssertEqual(window.decodeVariant, request.decodeVariant)

        let fileOnlyRequest = MobileCollectionBrowseThumbnailWindowPlanRequest(
            snapshot: snapshot,
            tokenIndex: request.tokenIndex,
            direction: request.direction,
            prefetchStride: request.prefetchStride,
            columnCount: request.columnCount,
            quality: request.quality,
            requiredTokenRange: request.requiredTokenRange,
            visibleTokenRange: request.visibleTokenRange,
            isFileOnly: true,
            decodeVariant: request.decodeVariant,
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: []
        )
        let plannedFileOnlyWindow = await planner.makeWindow(
            for: fileOnlyRequest
        )
        let fileOnlyWindow = try XCTUnwrap(plannedFileOnlyWindow)

        XCTAssertEqual(
            fileOnlyWindow.descriptors.map(\.tokenIndex),
            [100, 99, 101] + Array(stride(from: 98, through: 42, by: -1))
        )
        XCTAssertTrue(fileOnlyWindow.decodedDescriptors.isEmpty)
    }

    func testThumbnailWindowPlannerRetainsVisibleSourcesBeyondCacheCapacity()
        async throws {
        let collectionId = "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27088"
        let snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: collectionId,
            itemCount: CollectionCatalog.tokenCount(
                specificCollectionId: collectionId
            ),
            initialTokenIndex: 0
        )
        let imageSize = try XCTUnwrap(
            CollectionCatalog.collectionBrowseThumbnailDescriptor(
                specificCollectionId: collectionId,
                tokenIndex: 0
            )?.thumbnailAspectRatio?.size
        )
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let layout = try XCTUnwrap(MobilePlayerBrowserLayout(
            viewportSize: viewport.size,
            topContentInset: 59,
            bottomContentInset: 34,
            aspectProfile: MobilePlayerBrowserAspectProfile(
                itemCount: snapshot.itemCount,
                uniformImageSize: imageSize,
                columnCount: 9
            )
        ))
        let candidates = layout.candidateItemIndices(intersecting: viewport)
        let visibleRange = candidates.lowerBound...(candidates.upperBound - 1)
        let cache = MobileCollectionBrowseImageSourcesCache()
        let planner = MobileCollectionBrowseThumbnailWindowPlanner(
            imageSourcesCache: cache
        )

        let window = await planner.makeWindow(for: .init(
            snapshot: snapshot,
            tokenIndex: 0,
            direction: .forward,
            prefetchStride: layout.prefetchStride,
            columnCount: layout.columnCount,
            quality: .smallestThumbnail,
            requiredTokenRange: visibleRange,
            visibleTokenRange: visibleRange,
            isFileOnly: true,
            decodeVariant: .downsampled(maxPixelWidth: 160),
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: []
        ))

        XCTAssertGreaterThan(visibleRange.count, 512)
        XCTAssertGreaterThan(try XCTUnwrap(window).descriptors.count, 512)
        XCTAssertTrue(visibleRange.allSatisfy {
            cache.cachedImageSources(snapshot: snapshot, tokenIndex: $0) != nil
        })

        let nextTokenIndex = snapshot.itemCount - 1
        _ = await planner.makeWindow(for: isolatedPlannerRequest(
            snapshot: snapshot,
            tokenIndex: nextTokenIndex
        ))

        XCTAssertLessThanOrEqual(cache.cachedImageSourceCount, 512)
        XCTAssertNil(cache.cachedImageSources(snapshot: snapshot, tokenIndex: 0))
        XCTAssertNotNil(cache.cachedImageSources(
            snapshot: snapshot,
            tokenIndex: nextTokenIndex
        ))

        cache.clear()

        XCTAssertEqual(cache.cachedImageSourceCount, 0)
        XCTAssertNil(cache.cachedImageSources(
            snapshot: snapshot,
            tokenIndex: nextTokenIndex
        ))
    }

    func testThumbnailWindowPlannerCacheIsBoundedAndMemoizesUnavailableSources()
        async {
        let resolutionCounts = OSAllocatedUnfairLock(
            initialState: [String: Int]()
        )
        let firstSnapshot = PlayerCollectionBrowseSnapshot(
            collectionId: "lru-a",
            itemCount: 4,
            initialTokenIndex: 0
        )
        let cache = MobileCollectionBrowseImageSourcesCache(
            maximumCachedImageSourceCount: 2
        ) { snapshot, tokenIndex in
            let key = "\(snapshot.collectionId):\(tokenIndex)"
            resolutionCounts.withLock { $0[key, default: 0] += 1 }
            guard tokenIndex != 3 else { return nil }
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(fileURLWithPath: "/lru/\(key).webp"),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let planner = MobileCollectionBrowseThumbnailWindowPlanner(
            imageSourcesCache: cache
        )

        for tokenIndex in [0, 1, 0, 2, 0, 1, 3, 3] {
            _ = await planner.makeWindow(
                for: isolatedPlannerRequest(
                    snapshot: firstSnapshot,
                    tokenIndex: tokenIndex
                )
            )
        }

        XCTAssertEqual(resolutionCounts.withLock { $0["lru-a:0"] }, 1)
        XCTAssertEqual(resolutionCounts.withLock { $0["lru-a:1"] }, 2)
        XCTAssertEqual(resolutionCounts.withLock { $0["lru-a:2"] }, 1)
        XCTAssertEqual(resolutionCounts.withLock { $0["lru-a:3"] }, 1)
        XCTAssertEqual(cache.cachedImageSourceCount, 2)
        XCTAssertNil(cache.cachedImageSources(
            snapshot: firstSnapshot,
            tokenIndex: 3
        ))

        let secondSnapshot = PlayerCollectionBrowseSnapshot(
            collectionId: "lru-b",
            itemCount: 4,
            initialTokenIndex: 0
        )
        _ = await planner.makeWindow(
            for: isolatedPlannerRequest(
                snapshot: secondSnapshot,
                tokenIndex: 0
            )
        )
        XCTAssertEqual(resolutionCounts.withLock { $0["lru-b:0"] }, 1)
        XCTAssertEqual(cache.cachedImageSourceCount, 2)
        _ = await planner.makeWindow(
            for: isolatedPlannerRequest(
                snapshot: firstSnapshot,
                tokenIndex: 3
            )
        )
        XCTAssertEqual(resolutionCounts.withLock { $0["lru-a:3"] }, 1)
    }

    private func isolatedPlannerRequest(
        snapshot: PlayerCollectionBrowseSnapshot,
        tokenIndex: Int
    ) -> MobileCollectionBrowseThumbnailWindowPlanRequest {
        MobileCollectionBrowseThumbnailWindowPlanRequest(
            snapshot: snapshot,
            tokenIndex: tokenIndex,
            direction: .forward,
            prefetchStride: 1,
            columnCount: 1,
            quality: .thumbnail,
            requiredTokenRange: tokenIndex...tokenIndex,
            visibleTokenRange: tokenIndex...tokenIndex,
            isFileOnly: false,
            decodeVariant: .full,
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: Set(0..<snapshot.itemCount)
                .subtracting([tokenIndex]),
            locallyAvailableLargeTokenIndices: []
        )
    }

#if DEBUG
    func testSessionPlannerPublishesSourcesToControllerAndDisconnectClearsThem()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let resolutionCounts = OSAllocatedUnfairLock(initialState: [Int: Int]())
        let imageSourcesCache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            resolutionCounts.withLock { $0[tokenIndex, default: 0] += 1 }
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/shared-session-cache/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
            return CollectionBrowseImageSources(
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let registry = MobilePlaybackSessionRegistry(dependencies: .init(
            makeViewingSessionTracker: {
                PlayerViewingSessionTracker(continueViewingCollectionId: $0)
            },
            clearActiveMediaWindow: { _ in },
            cancelAllMediaDownloads: {},
            makeCollectionBrowseImageSourcesCache: { imageSourcesCache },
            installDownloadableMediaWindow: { _, _ in }
        ))
        let session = registry.startSession(
            config: MobilePlayerConfig(
                id: UUID(),
                initialItemId: metadata.id,
                initialTokenIndex: 0
            )
        )
        let display = PlaybackDisplay()
        session.attach(display: display)
        let controller = VerticalCollectionBrowserViewController(
            playbackSession: session
        )
        controller.loadViewIfNeeded()

        let originalSnapshot = try XCTUnwrap(
            session.collectionBrowseSnapshot()
        )
        let tokenIndex = originalSnapshot.itemCount - 1
        XCTAssertNil(controller.browseImageSourcesForTesting(
            tokenIndex: tokenIndex
        ))
        let prepared = expectation(description: "Thumbnail sources prepared")
        session.prepareCollectionBrowseThumbnailWindow(
            centeredAt: tokenIndex,
            direction: .backward,
            prefetchStride: 25,
            columnCount: 5,
            quality: .smallThumbnail,
            requiredTokenRange: tokenIndex...tokenIndex,
            visibleTokenRange: tokenIndex...tokenIndex,
            displayedHigherQualityThumbnailTokenIndices: [],
            displayedLargeTokenIndices: [],
            locallyAvailableLargeTokenIndices: [],
            completion: { _ in prepared.fulfill() }
        )
        await fulfillment(of: [prepared], timeout: 1)

        XCTAssertNotNil(controller.browseImageSourcesForTesting(
            tokenIndex: tokenIndex
        ))
        XCTAssertNotNil(controller.browseImageSourcesForTesting(
            tokenIndex: tokenIndex
        ))
        XCTAssertEqual(
            resolutionCounts.withLock { $0[tokenIndex, default: 0] },
            1
        )

        session.stopAndDisconnect()
        XCTAssertNil(controller.browseImageSourcesForTesting(
            tokenIndex: tokenIndex
        ))
        XCTAssertEqual(controller.cachedImageSourceCountForTesting, 0)
    }

    func testHiddenDeepFocusPreparationUsesPlaceholdersAndRestoresStagedSnapshot()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 300)
        let replacementCollectionID = "wide-descriptor-preparation"
        let imageSourcesCache = MobileCollectionBrowseImageSourcesCache {
            snapshot, tokenIndex in
            let descriptor = CollectionCatalogDownloadableMediaDescriptor(
                collectionId: snapshot.collectionId,
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(
                        fileURLWithPath:
                            "/wide-descriptor-preparation/\(tokenIndex).webp"
                    ),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail,
                thumbnailAspectRatio: snapshot.collectionId
                    == replacementCollectionID
                    ? ThumbnailAspectRatio(width: 2, height: 1)
                    : ThumbnailAspectRatio(width: 1, height: 1)
            )
            return CollectionBrowseImageSources(
                smallestThumbnailDescriptor: descriptor,
                smallThumbnailDescriptor: descriptor,
                thumbnailDescriptor: descriptor,
                largeDescriptor: descriptor
            )
        }
        let registry = MobilePlaybackSessionRegistry(dependencies: .init(
            makeViewingSessionTracker: {
                PlayerViewingSessionTracker(continueViewingCollectionId: $0)
            },
            clearActiveMediaWindow: { _ in },
            cancelAllMediaDownloads: {},
            makeCollectionBrowseImageSourcesCache: { imageSourcesCache },
            installDownloadableMediaWindow: { _, _ in }
        ))
        let session = registry.startSession(config: MobilePlayerConfig(
            id: UUID(),
            initialItemId: metadata.id,
            initialTokenIndex: 0
        ))
        let display = PlaybackDisplay()
        session.attach(display: display)
        let controller = VerticalCollectionBrowserViewController(
            playbackSession: session
        )
        let foregroundScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        let window = UIWindow(windowScene: foregroundScene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.viewDidAppear(false)
        controller.setActive(true)
        controller.view.layoutIfNeeded()
        defer {
            controller.cancelPendingDisplayPreparation()
            controller.setActive(false)
            window.isHidden = true
            window.rootViewController = nil
            session.stopAndDisconnect()
        }
        try await selectGridMode(.fiveColumns, controller: controller)
        let originalSnapshot = try XCTUnwrap(
            session.collectionBrowseSnapshot()
        )
        let originalPosition = controller.currentPagePosition
        try await waitUntil("Initial descriptors were not prepared") {
            controller.browseImageSourcesForTesting(
                tokenIndex: originalSnapshot.initialTokenIndex
            ) != nil
        }
        controller.viewWillDisappear(false)
        controller.viewDidDisappear(false)
        controller.setActive(false)
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let snapshot = PlayerCollectionBrowseSnapshot(
            collectionId: replacementCollectionID,
            itemCount: 300,
            initialTokenIndex: 0
        )
        let preparation = PlayerCollectionBrowsePreparation(
            sourcePagePosition: .initial,
            snapshot: snapshot,
            focusedTokenIndex: 150,
            requiresWidgetInsertionExit: false
        )
        let completion = expectation(description: "Hidden preparation finished")
        var result: MobilePlayerCollectionBrowserDisplayPreparationResult?
        controller.view.layoutIfNeeded()
        var focusedTokenWasVisible = false

        controller.prepareForDisplay(
            using: preparation,
            publishWhenStable: false
        ) {
            result = $0
            controller.view.layoutIfNeeded()
            let visibleTokenIndices = Set(
                collectionView.indexPathsForVisibleItems.map(\.item)
            )
            focusedTokenWasVisible = visibleTokenIndices.contains(150)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
        XCTAssertEqual(result, .prepared)
        XCTAssertEqual(
            controller.currentPagePosition,
            PlayerPagePosition(position: 150)
        )
        XCTAssertTrue(focusedTokenWasVisible)

        controller.cancelPendingDisplayPreparation()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.currentPagePosition, originalPosition)
        XCTAssertEqual(
            controller.browseImageSourcesForTesting(
                tokenIndex: originalSnapshot.initialTokenIndex
            )?.thumbnailDescriptor.collectionId,
            originalSnapshot.collectionId
        )
    }

    func testUnavailableDescriptorsAllowNavigationRestartAndGridChanges()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let imageSourcesCache = MobileCollectionBrowseImageSourcesCache {
            _, _ in nil
        }
        let registry = MobilePlaybackSessionRegistry(dependencies: .init(
            makeViewingSessionTracker: {
                PlayerViewingSessionTracker(continueViewingCollectionId: $0)
            },
            clearActiveMediaWindow: { _ in },
            cancelAllMediaDownloads: {},
            makeCollectionBrowseImageSourcesCache: {
                imageSourcesCache
            },
            installDownloadableMediaWindow: { _, _ in }
        ))
        let session = registry.startSession(config: MobilePlayerConfig(
            id: UUID(),
            initialItemId: metadata.id,
            initialTokenIndex: 0
        ))
        let display = PlaybackDisplay()
        session.attach(display: display)
        let controller = VerticalCollectionBrowserViewController(
            playbackSession: session
        )
        let foregroundScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        let window = UIWindow(windowScene: foregroundScene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.viewDidAppear(false)
        controller.setActive(true)
        controller.view.layoutIfNeeded()
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        var focusedPagePositions = [PlayerPagePosition]()
        controller.onFocusedPagePosition = {
            focusedPagePositions.append($0)
        }
        var settledPagePositions = [PlayerPagePosition]()
        controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }
        defer {
            controller.cancelPendingDisplayPreparation()
            controller.setActive(false)
            window.isHidden = true
            window.rootViewController = nil
            session.stopAndDisconnect()
        }

        let preparation = try XCTUnwrap(
            session.prepareCollectionBrowse(
                containing: PlayerPagePosition(position: 50)
            )
        )
        let completion = expectation(description: "Layout prepared")
        var result: MobilePlayerCollectionBrowserDisplayPreparationResult?
        controller.prepareForDisplay(
            using: preparation,
            forcePosition: true,
            publishWhenStable: true
        ) {
            result = $0
            completion.fulfill()
        }
        XCTAssertTrue(focusedPagePositions.isEmpty)
        XCTAssertTrue(settledPagePositions.isEmpty)

        await fulfillment(of: [completion], timeout: 1)

        let target = PlayerPagePosition(position: 50)
        XCTAssertEqual(result, .prepared)
        XCTAssertEqual(controller.currentPagePosition, target)
        XCTAssertEqual(focusedPagePositions.last, target)
        XCTAssertEqual(settledPagePositions, [target])
        XCTAssertTrue(collectionView.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        }.allSatisfy { $0.descriptor == nil })

        controller.scrollToFirstItemAndPublish()
        try await waitUntil("Restart did not settle without descriptors") {
            settledPagePositions.last == .initial
        }
        XCTAssertEqual(controller.currentPagePosition, .initial)
        XCTAssertTrue(controller.setGridMode(.fiveColumns))
    }

    func testActivePreparationCancelledBeforeYieldPreservesUserMotion()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)
        let fixture = try makeFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        let preparation = try XCTUnwrap(
            fixture.session.prepareCollectionBrowse(
                containing: PlayerPagePosition(position: 50)
            )
        )
        let completion = expectation(description: "Preparation superseded")
        var result: MobilePlayerCollectionBrowserDisplayPreparationResult?
        var settledPagePositions = [PlayerPagePosition]()
        controller.onSettledPagePosition = { pagePosition, _ in
            settledPagePositions.append(pagePosition)
            return true
        }

        controller.prepareForDisplay(
            using: preparation,
            forcePosition: true,
            publishWhenStable: false
        ) {
            result = $0
            completion.fulfill()
        }
        let preparedOffset = collectionView.contentOffset
        controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(settledPagePositions.isEmpty)
        collectionView.contentOffset.y += collectionView.bounds.height
        collectionView.layoutIfNeeded()
        let userOffset = collectionView.contentOffset
        controller.scrollViewDidEndDragging(
            collectionView,
            willDecelerate: false
        )

        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(result, .superseded)
        XCTAssertNotEqual(userOffset.y, preparedOffset.y)
        XCTAssertEqual(
            collectionView.contentOffset.y,
            userOffset.y,
            accuracy: 0.5
        )
        let settledPosition = try XCTUnwrap(controller.currentPagePosition)
        XCTAssertNotEqual(settledPosition, PlayerPagePosition(position: 50))
        XCTAssertEqual(settledPagePositions, [settledPosition])
        controller.flushSettledPosition()
        XCTAssertEqual(settledPagePositions, [settledPosition])
        XCTAssertTrue(controller.setGridMode(.fiveColumns))
    }

    func testLayoutAndLifecycleRemainIndependentOfBlockedDescriptors()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 100)

        let targetTokenIndex = CollectionCatalog.tokenCount(
            specificCollectionId: metadata.id
        ) - 1
        for interruption in [
            "activation",
            "drag",
            "accessibility",
            "scrollToTop",
            "disappearance",
            "deactivation",
        ] {
            let resolutionStarted = expectation(
                description: "\(interruption) resolution started"
            )
            let resumeResolution = DispatchSemaphore(value: 0)
            let didBlockResolution = OSAllocatedUnfairLock(
                initialState: false
            )
            let resolutionWaitTimedOut = OSAllocatedUnfairLock(
                initialState: false
            )
            let imageSourcesCache = MobileCollectionBrowseImageSourcesCache {
                snapshot, tokenIndex in
                let shouldBlock = didBlockResolution.withLock { didBlock in
                    guard tokenIndex == targetTokenIndex, !didBlock else {
                        return false
                    }
                    didBlock = true
                    return true
                }
                if shouldBlock {
                    resolutionStarted.fulfill()
                    if resumeResolution.wait(
                        timeout: .now() + .seconds(2)
                    ) == .timedOut {
                        resolutionWaitTimedOut.withLock { $0 = true }
                    }
                }
                let descriptor =
                    CollectionCatalogDownloadableMediaDescriptor(
                        collectionId: snapshot.collectionId,
                        tokenId: String(tokenIndex),
                        tokenIndex: tokenIndex,
                        media: .staticImage(
                            url: URL(
                                fileURLWithPath:
                                    "/lifecycle-preparation/\(tokenIndex).webp"
                            ),
                            fileExtension: "webp"
                        ),
                        purpose: .collectionBrowserThumbnail
                    )
                return CollectionBrowseImageSources(
                    thumbnailDescriptor: descriptor,
                    largeDescriptor: descriptor
                )
            }
            let registry = MobilePlaybackSessionRegistry(dependencies: .init(
                makeViewingSessionTracker: {
                    PlayerViewingSessionTracker(
                        continueViewingCollectionId: $0
                    )
                },
                clearActiveMediaWindow: { _ in },
                cancelAllMediaDownloads: {},
                makeCollectionBrowseImageSourcesCache: {
                    imageSourcesCache
                },
                installDownloadableMediaWindow: { _, _ in }
            ))
            let session = registry.startSession(config: MobilePlayerConfig(
                id: UUID(),
                initialItemId: metadata.id,
                initialTokenIndex: 0
            ))
            let display = PlaybackDisplay()
            session.attach(display: display)
            let controller = VerticalCollectionBrowserViewController(
                playbackSession: session
            )
            let foregroundScene = try XCTUnwrap(
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
            )
            let window = UIWindow(windowScene: foregroundScene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.isHidden = false
            window.layoutIfNeeded()
            controller.viewDidAppear(false)
            controller.setActive(true)
            controller.view.layoutIfNeeded()

            do {
                defer {
                    resumeResolution.signal()
                    controller.cancelPendingDisplayPreparation()
                    controller.setActive(false)
                    window.isHidden = true
                    window.rootViewController = nil
                    session.stopAndDisconnect()
                }
                let collectionView = try XCTUnwrap(
                    controller.view.subviews.first {
                        $0 is MobilePlayerCollectionBrowserCollectionView
                    } as? MobilePlayerCollectionBrowserCollectionView
                )
                let preparation = try XCTUnwrap(
                    session.prepareCollectionBrowse(
                        containing: PlayerPagePosition(
                            position: targetTokenIndex
                        )
                    )
                )
                session.prepareCollectionBrowseThumbnailWindow(
                    centeredAt: targetTokenIndex,
                    direction: .forward,
                    prefetchStride: 1,
                    columnCount: 3,
                    quality: .thumbnail,
                    requiredTokenRange: targetTokenIndex...targetTokenIndex,
                    visibleTokenRange: targetTokenIndex...targetTokenIndex,
                    displayedHigherQualityThumbnailTokenIndices: [],
                    displayedLargeTokenIndices: [],
                    locallyAvailableLargeTokenIndices: []
                )
                await fulfillment(of: [resolutionStarted], timeout: 1)
                let completion = expectation(
                    description: "\(interruption) preparation finished"
                )
                var results =
                    [MobilePlayerCollectionBrowserDisplayPreparationResult]()
                var focusedPagePositions = [PlayerPagePosition]()
                controller.onFocusedPagePosition = {
                    focusedPagePositions.append($0)
                }
                controller.prepareForDisplay(
                    using: preparation,
                    publishWhenStable: false
                ) {
                    results.append($0)
                    completion.fulfill()
                }
                XCTAssertTrue(focusedPagePositions.isEmpty, interruption)

                switch interruption {
                case "activation":
                    NotificationCenter.default.post(
                        name: UIScene.didActivateNotification,
                        object: foregroundScene
                    )
                    await fulfillment(of: [completion], timeout: 1)
                case "drag":
                    controller.scrollViewWillBeginDragging(collectionView)
                    controller.scrollViewDidEndDragging(
                        collectionView,
                        willDecelerate: false
                    )
                case "accessibility":
                    if let attempt = collectionView.onWillAccessibilityScroll?() {
                        collectionView.onAccessibilityScrollResult?(
                            false,
                            attempt
                        )
                    }
                case "scrollToTop":
                    XCTAssertTrue(
                        controller.scrollViewShouldScrollToTop(collectionView)
                    )
                    controller.scrollViewDidScrollToTop(collectionView)
                case "disappearance":
                    controller.viewWillDisappear(false)
                default:
                    let visibleCells = collectionView.visibleCells.compactMap {
                        $0 as? MobilePlayerCollectionBrowserCell
                    }
                    XCTAssertFalse(visibleCells.isEmpty)
                    XCTAssertTrue(visibleCells.allSatisfy {
                        $0.usesForegroundImageLoading
                    })
                    NotificationCenter.default.post(
                        name: UIScene.willDeactivateNotification,
                        object: foregroundScene
                    )
                    XCTAssertTrue(visibleCells.allSatisfy {
                        !$0.usesForegroundImageLoading
                    })
                }
                let expectedResults:
                    [MobilePlayerCollectionBrowserDisplayPreparationResult] =
                        interruption == "activation" ? [.prepared] : [.superseded]
                XCTAssertEqual(results, expectedResults, interruption)
                XCTAssertNil(controller.browseImageSourcesForTesting(
                    tokenIndex: targetTokenIndex
                ))
                XCTAssertFalse(
                    resolutionWaitTimedOut.withLock { $0 },
                    interruption
                )
                XCTAssertTrue(
                    controller.setGridMode(.fiveColumns),
                    interruption
                )
                resumeResolution.signal()
                if interruption != "activation" {
                    await fulfillment(of: [completion], timeout: 1)
                }
                await waitForNextMainQueueTurn()
                XCTAssertEqual(results, expectedResults, interruption)
            }
        }
    }
#endif

    func testDenseGridImageRefreshQueuePreservesFairRequeueOrder() {
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
            MobileCollectionBrowseMediaResolver.collectionBrowseImageDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallThumbnail
            ),
            sources.smallThumbnailDescriptor
        )
        XCTAssertEqual(
            MobileCollectionBrowseMediaResolver.collectionBrowseImageDescriptor(
                snapshot: snapshot,
                tokenIndex: 0,
                quality: .smallestThumbnail
            ),
            smallestThumbnailDescriptor
        )
    }

    func testArtifactMagazineUsesOneBasedCDNMediaTiers() throws {
        let collectionId = try collectionId(
            internalSlug: "artifact_magazine_3"
        )

        for (tokenIndex, cdnIndex) in [(0, 1), (592, 593)] {
            let primaryDescriptor = try XCTUnwrap(
                CollectionCatalog.downloadableMediaDescriptor(
                    specificCollectionId: collectionId,
                    tokenIndex: tokenIndex
                )
            )
            let sources = try XCTUnwrap(
                CollectionCatalog.collectionBrowseImageSources(
                    specificCollectionId: collectionId,
                    tokenIndex: tokenIndex
                )
            )

            XCTAssertEqual(
                primaryDescriptor.url,
                URL(string: "https://cdn.lil.org/player/artifact_magazine_3/\(cdnIndex).png")
            )
            XCTAssertEqual(
                sources.thumbnailDescriptor.url,
                URL(string: "https://cdn.lil.org/player/artifact_magazine_3/thumbs/\(cdnIndex).webp")
            )
            XCTAssertEqual(
                sources.smallestThumbnailDescriptor?.url,
                URL(string: "https://cdn.lil.org/player/artifact_magazine_3/thumbs/140/\(cdnIndex).webp")
            )
            XCTAssertEqual(
                sources.smallThumbnailDescriptor.url,
                URL(string: "https://cdn.lil.org/player/artifact_magazine_3/thumbs/260/\(cdnIndex).webp")
            )
            XCTAssertEqual(
                sources.largeDescriptor.url,
                URL(string: "https://cdn.lil.org/player/artifact_magazine_3/mid/\(cdnIndex).webp")
            )
        }
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
            MobileCollectionBrowseMediaResolver.collectionBrowsePrefetchDescriptor(
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
            MobileCollectionBrowseMediaResolver.collectionBrowsePrefetchDescriptor(
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
            MobileCollectionBrowseMediaResolver.collectionBrowsePrefetchDescriptor(
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
            MobileCollectionBrowseMediaResolver.collectionBrowseCompactCoverage(
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
            MobileCollectionBrowseMediaResolver.collectionBrowseCompactCoverage(
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
            MobileCollectionBrowseMediaResolver.collectionBrowseCompactCoverage(
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
            MobileCollectionBrowseMediaResolver.collectionBrowseCompactCoverage(
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
            MobileCollectionBrowseMediaResolver.collectionBrowseCompactCoverage(
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
                columnCount: 1,
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
                columnCount: 1,
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
                columnCount: 1,
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

    func testMediaWindowPrioritizesVisibleItemsWithinBoundedCapacities() throws {
        let descriptor: (Int) -> CollectionCatalogDownloadableMediaDescriptor = {
            tokenIndex in
            CollectionCatalogDownloadableMediaDescriptor(
                collectionId: "bounded-window",
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(fileURLWithPath: "/bounded-window/\(tokenIndex).webp"),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
        }
        let window = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 50,
                itemCount: 500,
                direction: .forward,
                prefetchStride: 25,
                columnCount: 5,
                visibleTokenRange: 46...55,
                descriptorForTokenIndex: descriptor
            )
        )

        XCTAssertLessThanOrEqual(window.descriptors.count, 60)
        XCTAssertLessThanOrEqual(window.decodedDescriptors.count, 30)
        XCTAssertEqual(
            Array(window.descriptors.map(\.tokenIndex).prefix(6)),
            [50, 51, 49, 52, 48, 53]
        )
        XCTAssertEqual(
            Array(window.decodedDescriptors.map(\.tokenIndex).prefix(6)),
            [50, 51, 49, 52, 48, 53]
        )
    }

    func testFileOnlyMediaWindowHasNoDecodeDemand() throws {
        let window = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 5,
                itemCount: 12,
                direction: .forward,
                prefetchStride: 1,
                columnCount: 1,
                includesDecodedDescriptors: false,
                descriptorForTokenIndex: { tokenIndex in
                    CollectionCatalogDownloadableMediaDescriptor(
                        collectionId: "file-only-window",
                        tokenId: String(tokenIndex),
                        tokenIndex: tokenIndex,
                        media: .staticImage(
                            url: URL(fileURLWithPath:
                                "/file-only-window/\(tokenIndex).webp"),
                            fileExtension: "webp"
                        ),
                        purpose: .collectionBrowserThumbnail
                    )
                }
            )
        )

        XCTAssertFalse(window.descriptors.isEmpty)
        XCTAssertTrue(window.decodedDescriptors.isEmpty)
    }

    func testFileOnlyDenseWindowCoversEachRowAlignedRefreshInterval() throws {
        let layouts = [
            (columnCount: 5, prefetchStride: 25),
            (columnCount: 9, prefetchStride: 25),
            (columnCount: 10, prefetchStride: 25),
            (columnCount: 18, prefetchStride: 25),
        ]
        let visibleRange = 200...269
        let descriptor: (Int) -> CollectionCatalogDownloadableMediaDescriptor = {
            tokenIndex in
            CollectionCatalogDownloadableMediaDescriptor(
                collectionId: "dense-file-window",
                tokenId: String(tokenIndex),
                tokenIndex: tokenIndex,
                media: .staticImage(
                    url: URL(fileURLWithPath:
                        "/dense-file-window/\(tokenIndex).webp"),
                    fileExtension: "webp"
                ),
                purpose: .collectionBrowserThumbnail
            )
        }

        for layout in layouts {
            let refreshDistance = PlayerCollectionBrowseMediaWindowPolicy
                .rowAlignedRefreshDistance(
                    prefetchStride: layout.prefetchStride,
                    columnCount: layout.columnCount
                )
            for direction in [
                DownloadableMediaCache.PrefetchDirection.forward,
                .backward,
            ] {
                let window = try XCTUnwrap(
                    PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                        centeredAt: 235,
                        itemCount: 1_000,
                        direction: direction,
                        prefetchStride: layout.prefetchStride,
                        columnCount: layout.columnCount,
                        visibleTokenRange: visibleRange,
                        includesDecodedDescriptors: false,
                        descriptorForTokenIndex: descriptor
                    )
                )
                let requiredLookahead: ClosedRange<Int>
                switch direction {
                case .forward:
                    requiredLookahead = (visibleRange.upperBound + 1)...(
                        visibleRange.upperBound + refreshDistance
                    )
                case .backward:
                    requiredLookahead = (
                        visibleRange.lowerBound - refreshDistance
                    )...(visibleRange.lowerBound - 1)
                }
                let fileTokenIndices = Set(window.descriptors.map(\.tokenIndex))

                XCTAssertTrue(
                    requiredLookahead.allSatisfy(fileTokenIndices.contains),
                    "missing \(direction) coverage for \(layout.columnCount) columns"
                )
                XCTAssertTrue(window.decodedDescriptors.isEmpty)
            }
        }
    }

    func testMediaWindowExpandsOnlyToVisibleFloorAndLookahead() throws {
        let visibleRange = 40...109
        let window = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 75,
                itemCount: 500,
                direction: .forward,
                prefetchStride: 25,
                columnCount: 5,
                visibleTokenRange: visibleRange,
                descriptorForTokenIndex: { tokenIndex in
                    CollectionCatalogDownloadableMediaDescriptor(
                        collectionId: "visible-floor-window",
                        tokenId: String(tokenIndex),
                        tokenIndex: tokenIndex,
                        media: .staticImage(
                            url: URL(fileURLWithPath:
                                "/visible-floor-window/\(tokenIndex).webp"),
                            fileExtension: "webp"
                        ),
                        purpose: .collectionBrowserThumbnail
                    )
                }
            )
        )

        let fileIndices = Set(window.descriptors.map(\.tokenIndex))
        let decodedIndices = Set(window.decodedDescriptors.map(\.tokenIndex))
        XCTAssertTrue(visibleRange.allSatisfy(fileIndices.contains))
        XCTAssertTrue(visibleRange.allSatisfy(decodedIndices.contains))
        XCTAssertEqual(window.descriptors.count, visibleRange.count + 25)
        XCTAssertEqual(window.decodedDescriptors.count, visibleRange.count)
    }

    func testMediaWindowBackfillsNilDescriptorCandidates() throws {
        let visibleRange = 46...55
        let omittedTokenIndices = Set(40...69)
        let window = try XCTUnwrap(
            PlayerCollectionBrowseMediaWindowLayout.makeWindow(
                centeredAt: 50,
                itemCount: 500,
                direction: .forward,
                prefetchStride: 25,
                columnCount: 5,
                visibleTokenRange: visibleRange,
                descriptorForTokenIndex: { tokenIndex in
                    guard !omittedTokenIndices.contains(tokenIndex) else {
                        return nil
                    }
                    return CollectionCatalogDownloadableMediaDescriptor(
                        collectionId: "backfilled-window",
                        tokenId: String(tokenIndex),
                        tokenIndex: tokenIndex,
                        media: .staticImage(
                            url: URL(fileURLWithPath:
                                "/backfilled-window/\(tokenIndex).webp"),
                            fileExtension: "webp"
                        ),
                        purpose: .collectionBrowserThumbnail
                    )
                }
            )
        )

        XCTAssertEqual(window.descriptors.count, 60)
        XCTAssertEqual(window.decodedDescriptors.count, 30)
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
                columnCount: 5,
                compactCoverage: coverage,
                visibleTokenRange: 445...499,
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
#if DEBUG
        let baselineDenseGridImageRefreshEnqueues = fixture.controller
            .thumbnailWindowMetrics.denseGridImageRefreshEnqueues
#endif

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
        try await waitUntil("Rolling thumbnail window did not prepare sources") {
            fixture.controller.thumbnailWindowMetrics.preparations
                > baselineThumbnailWindowMetrics.preparations
                && fixture.controller.thumbnailWindowMetrics
                    .denseGridImageRefreshEnqueues
                    > baselineDenseGridImageRefreshEnqueues
                && movedVisibleIndexPaths.allSatisfy { indexPath in
                    (collectionView.cellForItem(at: indexPath)
                        as? MobilePlayerCollectionBrowserCell)?.descriptor != nil
                }
        }

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
#if DEBUG
        let fileOnlyPreparationCount = fixture.controller
            .thumbnailWindowMetrics.fileOnlyPreparations
#endif

        fixture.controller.scrollViewWillBeginDragging(collectionView)
        XCTAssertTrue(visibleCells.allSatisfy(\.usesForegroundImageLoading))
#if DEBUG
        XCTAssertEqual(
            fixture.controller.thumbnailWindowMetrics.fileOnlyPreparations,
            fileOnlyPreparationCount
        )
#endif

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
                baselineFixture.session.prepareCollectionBrowse(
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
            fixture.session.prepareCollectionBrowse(
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
                baselineFixture.session.prepareCollectionBrowse(
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
            fixture.session.prepareCollectionBrowse(
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
            fixture.session.prepareCollectionBrowse(
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

#if DEBUG
    func testHeldPinchPreparesSourcesBeyondTheInitialThumbnailWindow()
        async throws {
        let metadata = try collectionMetadata(minimumTokenCount: 300)
        let fixture = try makeDeterministicFixture(collectionId: metadata.id)
        defer { tearDownFixture(fixture) }
        let controller = fixture.controller
        let frameDriver = try XCTUnwrap(fixture.gridTransitionFrameDriver)
        let collectionView = try XCTUnwrap(
            controller.view.subviews.first {
                $0 is MobilePlayerCollectionBrowserCollectionView
            } as? MobilePlayerCollectionBrowserCollectionView
        )
        try await waitUntil("Initial thumbnail sources were not prepared") {
            controller.browseImageSourcesForTesting(tokenIndex: 0) != nil
        }
        let revealedTokenIndex = 100
        XCTAssertNil(controller.browseImageSourcesForTesting(
            tokenIndex: revealedTokenIndex
        ))
        let recognizer = TestPinchGestureRecognizer()
        recognizer.reportedLocation = CGPoint(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY
        )
        recognizer.reportedState = .began
        recognizer.scale = 1
        sendPinch(recognizer, to: controller)
        recognizer.reportedState = .changed
        recognizer.scale = 0.5
        sendPinch(recognizer, to: controller)

        try await waitUntil("Held pinch did not prepare newly revealed sources") {
            frameDriver.advance()
            return controller.browseImageSourcesForTesting(
                tokenIndex: revealedTokenIndex
            ) != nil
        }

        XCTAssertEqual(recognizer.reportedState, .changed)
        XCTAssertEqual(controller.gridMode, .threeColumns)
        XCTAssertFalse(collectionView.isScrollEnabled)
        let preparations = controller.thumbnailWindowMetrics.preparations
        for _ in 0..<5 {
            sendPinch(recognizer, to: controller)
            frameDriver.advance()
        }
        XCTAssertEqual(
            controller.thumbnailWindowMetrics.preparations,
            preparations
        )
    }
#endif

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
