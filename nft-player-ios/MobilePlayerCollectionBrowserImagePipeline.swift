import os
import QuartzCore
import UIKit

@MainActor
final class MobilePlayerCollectionBrowserImagePipeline {
    struct Snapshot: Equatable {
        let lastThumbnailWindowRequest: ThumbnailWindowRequest?
        let pendingThumbnailWindowRequest: ThumbnailWindowRequest?

        init(
            lastThumbnailWindowRequest: ThumbnailWindowRequest?,
            pendingThumbnailWindowRequest: ThumbnailWindowRequest? = nil
        ) {
            self.lastThumbnailWindowRequest = lastThumbnailWindowRequest
            self.pendingThumbnailWindowRequest =
                pendingThumbnailWindowRequest
        }
    }

    struct ThumbnailWindowRequest: Equatable {
        let tokenIndex: Int
        let direction: DownloadableMediaCache.PrefetchDirection
        let prefetchStride: Int
        let columnCount: Int
        let quality: CollectionBrowseImageQuality
        let displayedHigherQualityThumbnailTokenIndices: Set<Int>
        let displayedLargeTokenIndices: Set<Int>
        let locallyAvailableLargeTokenIndices: Set<Int>
        let isFileOnly: Bool
        let decodeVariant: DownloadableMediaImageDecodeVariant
        var transitionTokenRange: ClosedRange<Int>? = nil
    }

    struct TransitionWindow {
        let tokenIndex: Int
        let tokenRange: ClosedRange<Int>
        let layout: MobilePlayerBrowserLayout
        let quality: CollectionBrowseImageQuality
        let decodeVariant: DownloadableMediaImageDecodeVariant
    }

    struct ThumbnailWindowPreparation: Equatable {
        let tokenIndex: Int
        let direction: DownloadableMediaCache.PrefetchDirection
        let prefetchStride: Int
        let columnCount: Int
        let quality: CollectionBrowseImageQuality
        let requiredTokenRange: ClosedRange<Int>?
        let visibleTokenRange: ClosedRange<Int>?
        let isFileOnly: Bool
        let decodeVariant: DownloadableMediaImageDecodeVariant
        let displayedHigherQualityThumbnailTokenIndices: Set<Int>
        let displayedLargeTokenIndices: Set<Int>
        let locallyAvailableLargeTokenIndices: Set<Int>
    }

    struct ContentAccess {
        let visibleIndexPaths: @MainActor () -> [IndexPath]
        let cell: @MainActor (IndexPath) -> MobilePlayerCollectionBrowserCell?
        let visibleCells: @MainActor () -> [MobilePlayerCollectionBrowserCell]
        let viewportRenderCells: @MainActor (Int?) -> [MobilePlayerCollectionBrowserCell]
        let collectionID: @MainActor () -> String?
        let requiredImageQuality: @MainActor () -> CollectionBrowseImageQuality
        let imageDecodeVariant: @MainActor () -> DownloadableMediaImageDecodeVariant
        let baseColumnCount: @MainActor () -> Int
        let configuredPrefetchStride: @MainActor () -> Int
        let configuredColumnCount: @MainActor () -> Int
        let isRendererActive: @MainActor () -> Bool
        let isApplyingPosition: @MainActor () -> Bool
        let isPreparedTransitionActive: @MainActor () -> Bool
        let isForegroundActive: @MainActor () -> Bool
        let projectedTokenRange: @MainActor (
            Int,
            DownloadableMediaCache.PrefetchDirection,
            Int
        ) -> ClosedRange<Int>?
        let prepareThumbnailWindow: @MainActor (
            ThumbnailWindowPreparation,
            @escaping @MainActor () -> Bool,
            @escaping @MainActor (
                MobileCollectionBrowseThumbnailWindowPreparationResult
            ) -> Void
        ) -> Void
        let cancelThumbnailWindowPreparation: @MainActor () -> Void
        let thumbnailWindowPreparationDidFinish: @MainActor () -> Void
    }

#if DEBUG
    struct ThumbnailWindowMetrics: Equatable {
        var skippedDisplayedImageScans = 0
        var displayedImageScans = 0
        var preparations = 0
        var fileOnlyPreparations = 0
        var visibleCellCount = 0
        var emptyVisibleCellCount = 0
        var outstandingCachedImageRefreshes = 0
        var denseGridImageRefreshEnqueues = 0
    }

    private(set) var thumbnailWindowMetrics = ThumbnailWindowMetrics()
#endif

    private struct DisplayedImageWindowState {
        let higherQualityThumbnailTokenIndices: Set<Int>
        let tokenIndices: Set<Int>
        let locallyAvailableTokenIndices: Set<Int>

        static let empty = Self(
            higherQualityThumbnailTokenIndices: [],
            tokenIndices: [],
            locallyAvailableTokenIndices: []
        )
    }

    private final class DisplayLinkTarget: NSObject {
        weak var pipeline: MobilePlayerCollectionBrowserImagePipeline?

        @MainActor @objc func tick(_ displayLink: CADisplayLink) {
            pipeline?.handleDenseGridImageDisplayLinkTick()
        }
    }

    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
        category: "CollectionBrowserImages"
    )

    private var contentAccess: ContentAccess?
    private var lastThumbnailWindowRequest: ThumbnailWindowRequest?
    private var pendingThumbnailWindowRequest: (
        generation: UInt,
        request: ThumbnailWindowRequest
    )?
    private var thumbnailWindowPreparationGeneration: UInt = 0
    private var denseGridImageDisplayLink: CADisplayLink?
    private let displayLinkTarget = DisplayLinkTarget()
    private var denseGridImageRefreshQueue = DenseGridImageRefreshQueue()
    private var isInvalidated = false

    private(set) var isActive = false
    private(set) var isVisible = false
    private(set) var isScrollMotionActive = false

    init() {
        displayLinkTarget.pipeline = self
    }

    var defersDenseGridImageLoading: Bool {
        contentAccess?.requiredImageQuality().isDenseGridThumbnail == true
            && contentAccess?.isRendererActive() == false
            && isScrollMotionActive
    }

    var denseGridImageRefreshBatchSize: Int {
        DenseGridImageRefreshPolicy.batchSize(
            baseColumnCount: contentAccess?.baseColumnCount() ?? 0
        )
    }

    func configure(contentAccess: ContentAccess) {
        guard !isInvalidated else { return }
        self.contentAccess = contentAccess
    }

    func snapshot() -> Snapshot {
        Snapshot(
            lastThumbnailWindowRequest: lastThumbnailWindowRequest,
            pendingThumbnailWindowRequest:
                pendingThumbnailWindowRequest?.request
        )
    }

    func restore(_ snapshot: Snapshot) {
        guard !isInvalidated else { return }
        cancelPendingThumbnailWindowPreparation()
        lastThumbnailWindowRequest = snapshot.lastThumbnailWindowRequest
        guard isActive,
              isVisible,
              let contentAccess,
              contentAccess.isForegroundActive(),
              let request = snapshot.pendingThumbnailWindowRequest
                ?? snapshot.lastThumbnailWindowRequest else {
            return
        }
        prepareThumbnailWindow(
            around: request.tokenIndex,
            direction: request.direction,
            force: true,
            configuredPrefetchStride:
                contentAccess.configuredPrefetchStride(),
            configuredColumnCount: contentAccess.configuredColumnCount(),
            requiredImageQuality: contentAccess.requiredImageQuality()
        )
    }

    func setActive(_ active: Bool) {
        guard !isInvalidated else { return }
        isActive = active
        if !active {
            cancelPendingThumbnailWindowPreparation()
        }
    }

    func setVisible(_ visible: Bool) {
        guard !isInvalidated else { return }
        isVisible = visible
        if !visible {
            suspendRenderedImageLoads()
        }
    }

    func setScrollMotionActive(_ active: Bool) {
        guard !isInvalidated else { return }
        isScrollMotionActive = active
    }

    func resetThumbnailWindow() {
        guard !isInvalidated else { return }
        cancelPendingThumbnailWindowPreparation()
        lastThumbnailWindowRequest = nil
    }

    func invalidate() {
        guard !isInvalidated else { return }
        cancelVisibleCellImageLoads()
        cancelPendingThumbnailWindowPreparation()
        isInvalidated = true
        stopDenseGridImageDisplayLink()
        contentAccess = nil
    }

    func cancelVisibleCellImageLoads() {
        guard !isInvalidated else { return }
        contentAccess?.visibleCells().forEach { $0.cancelImageLoad() }
    }

    func suspendRenderedImageLoads() {
        guard !isInvalidated else { return }
        if let contentAccess {
            var cellIDs = Set<ObjectIdentifier>()
            let cells = contentAccess.visibleCells()
                + contentAccess.viewportRenderCells(nil)
            for cell in cells {
                guard cellIDs.insert(ObjectIdentifier(cell)).inserted else {
                    continue
                }
                cell.demoteImageLoadToCachedOnlyIfNeeded()
            }
        }
        stopDenseGridImageDisplayLink()
        cancelPendingThumbnailWindowPreparation()
    }

    func prepareThumbnailWindow(
        around tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        force: Bool,
        configuredPrefetchStride: Int,
        configuredColumnCount: Int,
        requiredImageQuality: CollectionBrowseImageQuality,
        transitionWindow: TransitionWindow? = nil
    ) {
        guard !isInvalidated,
              let contentAccess,
              isActive || contentAccess.isPreparedTransitionActive() else {
            return
        }
        guard transitionWindow == nil
            || isActive && isVisible && contentAccess.isForegroundActive() else {
            return
        }
        let prefetchStride = PlayerCollectionBrowseMediaWindowPolicy
            .normalizedPrefetchStride(configuredPrefetchStride)
        let columnCount = configuredColumnCount
        let quality = requiredImageQuality
        let decodeVariant = transitionWindow?.decodeVariant
            ?? contentAccess.imageDecodeVariant()
        let isFileOnly = transitionWindow != nil
            || quality.isDenseGridThumbnail && isScrollMotionActive
        let refreshDistance = quality.isDenseGridThumbnail
            ? PlayerCollectionBrowseMediaWindowPolicy.rowAlignedRefreshDistance(
                prefetchStride: prefetchStride,
                columnCount: columnCount
            )
            : prefetchStride
        let comparisonRequest = pendingThumbnailWindowRequest?.request
            ?? lastThumbnailWindowRequest
        if let transitionWindow,
           let comparisonRequest,
           comparisonRequest.columnCount == columnCount,
           comparisonRequest.quality == quality,
           comparisonRequest.decodeVariant == decodeVariant,
           let preparedRange = comparisonRequest.transitionTokenRange,
           preparedRange.contains(transitionWindow.tokenRange.lowerBound),
           preparedRange.contains(transitionWindow.tokenRange.upperBound) {
            return
        }
        let previousTokenIndex = comparisonRequest.flatMap {
            $0.direction == direction
                && $0.prefetchStride == prefetchStride
                && $0.columnCount == columnCount
                && $0.quality == quality
                ? $0.tokenIndex
                : nil
        }
        let shouldRefreshStableWindow =
            PlayerCollectionBrowseMediaWindowPolicy.shouldRefresh(
                previousTokenIndex: previousTokenIndex,
                nextTokenIndex: tokenIndex,
                refreshDistance: refreshDistance,
                force: force || transitionWindow != nil
            )
        if quality.isDenseGridThumbnail,
           !shouldRefreshStableWindow,
           comparisonRequest?.isFileOnly == isFileOnly,
           comparisonRequest?.decodeVariant == decodeVariant {
#if DEBUG
            thumbnailWindowMetrics.skippedDisplayedImageScans += 1
#endif
            return
        }

        let transitionTokenRange = transitionWindow.map { window in
            let first = max(window.tokenRange.lowerBound - columnCount * 2, 0)
            let last = min(
                window.tokenRange.upperBound + columnCount * 2,
                window.layout.itemCount - 1
            )
            return first...last
        }
        let visibleTokenRange = transitionTokenRange
            ?? visibleBrowserTokenRange(contentAccess: contentAccess)
        let requiredTokenRange = transitionTokenRange ?? visibleTokenRange.map {
            requiredThumbnailWindowTokenRange(
                around: tokenIndex,
                direction: direction,
                refreshDistance: refreshDistance,
                visibleTokenRange: $0,
                contentAccess: contentAccess
            )
        }
        let displayedImages: DisplayedImageWindowState
        if quality == .large || transitionWindow != nil {
            displayedImages = .empty
        } else {
            displayedImages = displayedImageWindowState(
                requiredQuality: quality,
                contentAccess: contentAccess
            )
#if DEBUG
            thumbnailWindowMetrics.displayedImageScans += 1
#endif
        }
        let displayedHigherQualityThumbnailTokenIndices =
            quality.isDenseGridThumbnail
            ? displayedImages.higherQualityThumbnailTokenIndices
            : []
        let request = ThumbnailWindowRequest(
            tokenIndex: tokenIndex,
            direction: direction,
            prefetchStride: prefetchStride,
            columnCount: columnCount,
            quality: quality,
            displayedHigherQualityThumbnailTokenIndices:
                displayedHigherQualityThumbnailTokenIndices,
            displayedLargeTokenIndices: displayedImages.tokenIndices,
            locallyAvailableLargeTokenIndices:
                displayedImages.locallyAvailableTokenIndices,
            isFileOnly: isFileOnly,
            decodeVariant: decodeVariant,
            transitionTokenRange: transitionTokenRange
        )
        if !force,
           let comparisonRequest,
           comparisonRequest
                .displayedHigherQualityThumbnailTokenIndices
                == displayedHigherQualityThumbnailTokenIndices,
           comparisonRequest.displayedLargeTokenIndices
                == displayedImages.tokenIndices,
           comparisonRequest.locallyAvailableLargeTokenIndices
                == displayedImages.locallyAvailableTokenIndices,
           comparisonRequest.isFileOnly == isFileOnly,
           comparisonRequest.decodeVariant == decodeVariant,
           !shouldRefreshStableWindow {
            return
        }

        let preparation = ThumbnailWindowPreparation(
            tokenIndex: tokenIndex,
            direction: direction,
            prefetchStride: prefetchStride,
            columnCount: columnCount,
            quality: quality,
            requiredTokenRange: requiredTokenRange,
            visibleTokenRange: visibleTokenRange,
            isFileOnly: isFileOnly,
            decodeVariant: decodeVariant,
            displayedHigherQualityThumbnailTokenIndices:
                displayedHigherQualityThumbnailTokenIndices,
            displayedLargeTokenIndices: displayedImages.tokenIndices,
            locallyAvailableLargeTokenIndices:
                displayedImages.locallyAvailableTokenIndices
        )
        thumbnailWindowPreparationGeneration &+= 1
        let generation = thumbnailWindowPreparationGeneration
        pendingThumbnailWindowRequest = (generation, request)
        contentAccess.prepareThumbnailWindow(
            preparation,
            { [weak self] in
                self?.canApplyThumbnailWindowPreparation(
                    generation: generation
                ) == true
            },
            { [weak self] result in
                self?.finishThumbnailWindowPreparation(
                    generation: generation,
                    request: request,
                    result: result
                )
            }
        )
#if DEBUG
        thumbnailWindowMetrics.preparations += 1
        thumbnailWindowMetrics.fileOnlyPreparations += isFileOnly ? 1 : 0
        let visibleCells = contentAccess.visibleCells()
        thumbnailWindowMetrics.visibleCellCount = visibleCells.count
        thumbnailWindowMetrics.emptyVisibleCellCount = visibleCells.filter {
            $0.displayedLargeImageWindowEntry == nil
                && $0.displayedThumbnailWindowEntry == nil
        }.count
#endif
        Self.signposter.emitEvent("ThumbnailWindow")
    }

    func cancelPendingThumbnailWindowPreparation() {
        guard !isInvalidated else { return }
        thumbnailWindowPreparationGeneration &+= 1
        pendingThumbnailWindowRequest = nil
        contentAccess?.cancelThumbnailWindowPreparation()
    }

    private func canApplyThumbnailWindowPreparation(
        generation: UInt
    ) -> Bool {
        !isInvalidated
            && isActive
            && isVisible
            && pendingThumbnailWindowRequest?.generation == generation
            && contentAccess?.isForegroundActive() == true
    }

    private func finishThumbnailWindowPreparation(
        generation: UInt,
        request: ThumbnailWindowRequest,
        result: MobileCollectionBrowseThumbnailWindowPreparationResult
    ) {
        guard pendingThumbnailWindowRequest?.generation == generation else {
            return
        }
        pendingThumbnailWindowRequest = nil
        let preparedTransitionSources = result == .planned
            && request.transitionTokenRange != nil
        lastThumbnailWindowRequest = result == .committed || preparedTransitionSources
            ? request
            : nil
        if result == .planned || result == .committed {
            contentAccess?.thumbnailWindowPreparationDidFinish()
        }
    }

    func configure(
        cell: MobilePlayerCollectionBrowserCell,
        tokenIndex: Int,
        requiredImageQuality: CollectionBrowseImageQuality?,
        imageLoadPolicy: MobilePlayerCollectionBrowserCell.ImageLoadPolicy?,
        apply: @MainActor (
            CollectionBrowseImageQuality,
            MobilePlayerCollectionBrowserCell.ImageLoadPolicy,
            DownloadableMediaImageDecodeVariant
        ) -> Void
    ) {
        guard !isInvalidated else { return }
        let defersDenseGridImageLoading = self.defersDenseGridImageLoading
        let isForegroundEligible = isActive
            && isVisible
            && contentAccess?.isForegroundActive() == true
        let participatesInPreparation = isActive
            || contentAccess?.isPreparedTransitionActive() == true
        let requestedImageLoadPolicy = imageLoadPolicy
            ?? (participatesInPreparation
                ? (defersDenseGridImageLoading || !isForegroundEligible
                    ? .cachedOnly
                    : .foreground)
                : .disabled)
        let resolvedImageLoadPolicy = (
            defersDenseGridImageLoading || !isForegroundEligible
        )
            && requestedImageLoadPolicy == .foreground
            ? .cachedOnly
            : requestedImageLoadPolicy
        let shouldDemoteForegroundLoad = resolvedImageLoadPolicy == .cachedOnly
            && (!isForegroundEligible
                || imageLoadPolicy == nil && defersDenseGridImageLoading)
        if shouldDemoteForegroundLoad {
            cell.demoteImageLoadToCachedOnlyIfNeeded(tokenIndex: tokenIndex)
        }
        let resolvedRequiredImageQuality = requiredImageQuality
            ?? contentAccess?.requiredImageQuality()
            ?? .large
        apply(
            resolvedRequiredImageQuality,
            resolvedImageLoadPolicy,
            contentAccess?.imageDecodeVariant() ?? .full
        )

        guard resolvedImageLoadPolicy == .cachedOnly else { return }
        if defersDenseGridImageLoading,
           cell.needsCachedImageRefresh(tokenIndex: tokenIndex) {
            enqueueDenseGridImageRefresh(tokenIndex: tokenIndex)
        } else if imageLoadPolicy != nil || !isForegroundEligible {
            _ = cell.refreshCachedImageIfAvailable(tokenIndex: tokenIndex)
        }
    }

    func willDisplay(
        cell: MobilePlayerCollectionBrowserCell,
        tokenIndex: Int,
        intersectsViewport: @MainActor () -> Bool
    ) {
        guard !isInvalidated,
              isActive,
              isVisible,
              contentAccess?.isForegroundActive() == true,
              contentAccess?.isRendererActive() == false else {
            return
        }
        if defersDenseGridImageLoading {
            cell.demoteImageLoadToCachedOnlyIfNeeded(tokenIndex: tokenIndex)
            if cell.needsCachedImageRefresh(tokenIndex: tokenIndex) {
                enqueueDenseGridImageRefresh(tokenIndex: tokenIndex)
            }
            return
        }
        cell.resumeImageLoadIfNeeded(tokenIndex: tokenIndex)
        if intersectsViewport() {
            cell.promoteImageLoadToForegroundIfNeeded(tokenIndex: tokenIndex)
        }
    }

    func willEndDisplaying(tokenIndex: Int) {
        guard !isInvalidated else { return }
        denseGridImageRefreshQueue.remove(tokenIndex)
#if DEBUG
        thumbnailWindowMetrics.outstandingCachedImageRefreshes =
            denseGridImageRefreshQueue.count
#endif
    }

    func didEndDisplaying(
        cell: MobilePlayerCollectionBrowserCell,
        tokenIndex: Int
    ) {
        guard !isInvalidated else { return }
        cell.cancelImageLoad(ifRepresenting: tokenIndex)
    }

    func handleCacheNotification(_ notification: Notification) {
        guard !isInvalidated,
              isActive || contentAccess?.isPreparedTransitionActive() == true,
              let change = notification.object
                as? DownloadableMediaCacheFileAvailabilityChange,
              let contentAccess else {
            return
        }
        let cache = DownloadableMediaCache.shared
        let collectionID = contentAccess.collectionID()
        if let collectionID,
           !cache.fileAvailabilityChange(
               notification,
               affectsCollection: collectionID
           ) {
            return
        }
        let tokenIndex = collectionID.flatMap {
            cache.fileAvailabilityTokenIndex(notification, inCollection: $0)
        }
        let cells: [MobilePlayerCollectionBrowserCell]
        if let tokenIndex {
            let indexPath = IndexPath(item: tokenIndex, section: 0)
            cells = contentAccess.cell(indexPath).map { [$0] } ?? []
        } else {
            cells = contentAccess.visibleCells()
        }
        cells.forEach {
            $0.updateLocalFileAvailability(
                notification: notification,
                isAvailable: change == .becameAvailable
            )
        }
        if defersDenseGridImageLoading || change == .becameUnavailable {
            return
        }
        contentAccess.viewportRenderCells(tokenIndex).forEach {
            $0.refreshAvailableImageIfNeeded(notification: notification)
        }
    }

    func handleDecodedImageNotification(_ notification: Notification) {
        guard !isInvalidated,
              isActive || contentAccess?.isPreparedTransitionActive() == true,
              defersDenseGridImageLoading,
              let availability = notification.object
                as? DownloadableMediaCacheDecodedImageAvailability,
              let contentAccess,
              contentAccess.collectionID() == availability.collectionId else {
            return
        }
        let indexPath = IndexPath(
            item: availability.tokenIndex,
            section: 0
        )
        guard contentAccess.visibleIndexPaths().contains(indexPath),
              let cell = contentAccess.cell(indexPath),
              cell.needsCachedImageRefresh(
                  tokenIndex: availability.tokenIndex
              ) else {
            return
        }
        enqueueDenseGridImageRefresh(tokenIndex: availability.tokenIndex)
    }

    func demoteVisibleImageLoadsIfNeeded() {
        guard !isInvalidated,
              defersDenseGridImageLoading,
              let contentAccess else {
            return
        }
        for indexPath in contentAccess.visibleIndexPaths() {
            guard let cell = contentAccess.cell(indexPath) else { continue }
            cell.demoteImageLoadToCachedOnlyIfNeeded(tokenIndex: indexPath.item)
            if cell.needsCachedImageRefresh(tokenIndex: indexPath.item) {
                enqueueDenseGridImageRefresh(tokenIndex: indexPath.item)
            }
        }
    }

    func resumeVisibleImageLoadsIfNeeded() {
        guard !isInvalidated else { return }
        guard !defersDenseGridImageLoading else { return }
        stopDenseGridImageDisplayLink()
        guard isActive,
              isVisible,
              let contentAccess,
              contentAccess.isForegroundActive(),
              !contentAccess.isApplyingPosition(),
              !contentAccess.isRendererActive() else {
            return
        }
        for indexPath in contentAccess.visibleIndexPaths() {
            contentAccess.cell(indexPath)?
                .promoteImageLoadToForegroundIfNeeded(tokenIndex: indexPath.item)
        }
    }

    func cancelDenseGridImageRefreshes() {
        stopDenseGridImageDisplayLink()
    }

#if DEBUG
    var pendingDenseGridImageRefreshCount: Int {
        denseGridImageRefreshQueue.count
    }

    var isDenseGridImageDisplayLinkActive: Bool {
        denseGridImageDisplayLink != nil
    }

    func drainDenseGridImageDisplayLinkFrameForTesting(
        currentTime: () -> CFTimeInterval = CACurrentMediaTime
    ) -> Int {
        drainDenseGridImageRefreshes(
            limit: denseGridImageRefreshBatchSize,
            currentTime: currentTime
        )
    }

    func replacePendingDenseGridImageRefreshesForTesting(
        tokenIndices: [Int]
    ) {
        stopDenseGridImageDisplayLink()
        tokenIndices.forEach { enqueueDenseGridImageRefresh(tokenIndex: $0) }
    }
#endif

    private func visibleBrowserTokenRange(
        contentAccess: ContentAccess
    ) -> ClosedRange<Int>? {
        let tokenIndices = contentAccess.visibleIndexPaths().map(\.item)
        guard let first = tokenIndices.min(),
              let last = tokenIndices.max() else {
            return nil
        }
        return first...last
    }

    private func requiredThumbnailWindowTokenRange(
        around tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        refreshDistance: Int,
        visibleTokenRange: ClosedRange<Int>,
        contentAccess: ContentAccess
    ) -> ClosedRange<Int> {
        guard let projectedTokenRange = contentAccess.projectedTokenRange(
            tokenIndex,
            direction,
            refreshDistance
        ) else {
            return visibleTokenRange
        }
        return min(
            visibleTokenRange.lowerBound,
            projectedTokenRange.lowerBound
        )...max(
            visibleTokenRange.upperBound,
            projectedTokenRange.upperBound
        )
    }

    private func displayedImageWindowState(
        requiredQuality: CollectionBrowseImageQuality,
        contentAccess: ContentAccess
    ) -> DisplayedImageWindowState {
        var higherQualityThumbnailTokenIndices = Set<Int>()
        var tokenIndices = Set<Int>()
        var locallyAvailableTokenIndices = Set<Int>()
        for cell in contentAccess.visibleCells() {
            if let entry = cell.displayedThumbnailWindowEntry,
               entry.quality.rawValue > requiredQuality.rawValue {
                higherQualityThumbnailTokenIndices.insert(entry.tokenIndex)
            }
            guard let entry = cell.displayedLargeImageWindowEntry else { continue }
            tokenIndices.insert(entry.tokenIndex)
            if entry.isLocallyAvailable {
                locallyAvailableTokenIndices.insert(entry.tokenIndex)
            }
        }
        return DisplayedImageWindowState(
            higherQualityThumbnailTokenIndices:
                higherQualityThumbnailTokenIndices,
            tokenIndices: tokenIndices,
            locallyAvailableTokenIndices: locallyAvailableTokenIndices
        )
    }

    private func startDenseGridImageDisplayLinkIfNeeded() {
        guard !isInvalidated,
              defersDenseGridImageLoading,
              denseGridImageRefreshQueue.count > 0,
              denseGridImageDisplayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(
            target: displayLinkTarget,
            selector: #selector(DisplayLinkTarget.tick(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 60,
            preferred: 60
        )
        displayLink.add(to: .main, forMode: .common)
        denseGridImageDisplayLink = displayLink
    }

    private func stopDenseGridImageDisplayLink() {
        denseGridImageDisplayLink?.invalidate()
        denseGridImageDisplayLink = nil
        denseGridImageRefreshQueue.removeAll()
#if DEBUG
        thumbnailWindowMetrics.outstandingCachedImageRefreshes = 0
#endif
    }

    private func handleDenseGridImageDisplayLinkTick() {
        _ = drainDenseGridImageRefreshes(limit: denseGridImageRefreshBatchSize)
    }

    private func enqueueDenseGridImageRefresh(tokenIndex: Int) {
        guard !isInvalidated,
              defersDenseGridImageLoading,
              denseGridImageRefreshQueue.enqueue(tokenIndex) else {
            return
        }
#if DEBUG
        thumbnailWindowMetrics.denseGridImageRefreshEnqueues += 1
        thumbnailWindowMetrics.outstandingCachedImageRefreshes =
            denseGridImageRefreshQueue.count
#endif
        startDenseGridImageDisplayLinkIfNeeded()
    }

    @discardableResult
    private func drainDenseGridImageRefreshes(
        limit: Int,
        currentTime: () -> CFTimeInterval = CACurrentMediaTime
    ) -> Int {
        guard defersDenseGridImageLoading else {
            stopDenseGridImageDisplayLink()
            return 0
        }
        let deadline = currentTime() + DenseGridImageRefreshPolicy.frameTimeBudget
        var processedCount = 0
        while processedCount < limit,
              processedCount == 0 || currentTime() < deadline,
              let tokenIndex = denseGridImageRefreshQueue.dequeue() {
            processedCount += 1
            let indexPath = IndexPath(item: tokenIndex, section: 0)
            guard let cell = contentAccess?.cell(indexPath) else { continue }
            _ = cell.refreshCachedImageIfAvailable(tokenIndex: tokenIndex)
        }
        if denseGridImageRefreshQueue.count == 0 {
            stopDenseGridImageDisplayLink()
        } else {
#if DEBUG
            thumbnailWindowMetrics.outstandingCachedImageRefreshes =
                denseGridImageRefreshQueue.count
#endif
        }
        return processedCount
    }
}

struct DenseGridImageRefreshQueue {
    private var tokenIndices = [Int]()
    private var tokenIndexSet = Set<Int>()

    var count: Int {
        tokenIndexSet.count
    }

    @discardableResult
    mutating func enqueue(_ tokenIndex: Int) -> Bool {
        guard tokenIndexSet.insert(tokenIndex).inserted else { return false }
        tokenIndices.append(tokenIndex)
        return true
    }

    mutating func dequeue() -> Int? {
        guard !tokenIndices.isEmpty else { return nil }
        let tokenIndex = tokenIndices.removeFirst()
        tokenIndexSet.remove(tokenIndex)
        return tokenIndex
    }

    @discardableResult
    mutating func remove(_ tokenIndex: Int) -> Bool {
        guard tokenIndexSet.contains(tokenIndex),
              let index = tokenIndices.firstIndex(of: tokenIndex) else {
            return false
        }
        tokenIndices.remove(at: index)
        tokenIndexSet.remove(tokenIndex)
        return true
    }

    mutating func removeAll() {
        tokenIndices.removeAll()
        tokenIndexSet.removeAll()
    }
}

nonisolated enum DenseGridImageRefreshPolicy {
    static let frameTimeBudget: CFTimeInterval = 0.002
    static let minimumBatchSize = 5
    static let maximumBatchSize = 9

    static func batchSize(baseColumnCount: Int) -> Int {
        min(max(baseColumnCount, minimumBatchSize), maximumBatchSize)
    }
}
