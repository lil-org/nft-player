import QuartzCore
import UIKit

@MainActor
final class MobilePlayerCollectionBrowserImagePipeline {
    struct Snapshot: Equatable {
        let lastThumbnailWindowRequest: ThumbnailWindowRequest?
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
    }

    struct ThumbnailWindowPreparation {
        let tokenIndex: Int
        let direction: DownloadableMediaCache.PrefetchDirection
        let prefetchStride: Int
        let columnCount: Int
        let quality: CollectionBrowseImageQuality
        let requiredTokenRange: ClosedRange<Int>?
        let displayedHigherQualityThumbnailTokenIndices: Set<Int>
        let displayedLargeTokenIndices: Set<Int>
        let locallyAvailableLargeTokenIndices: Set<Int>
    }

    struct ContentAccess {
        let visibleIndexPaths: @MainActor () -> [IndexPath]
        let cell: @MainActor (IndexPath) -> MobilePlayerCollectionBrowserCell?
        let visibleCells: @MainActor () -> [MobilePlayerCollectionBrowserCell]
        let viewportRenderCells: @MainActor () -> [MobilePlayerCollectionBrowserCell]
        let requiredImageQuality: @MainActor () -> CollectionBrowseImageQuality
        let baseColumnCount: @MainActor () -> Int
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
            ThumbnailWindowPreparation
        ) -> Void
    }

#if DEBUG
    struct ThumbnailWindowMetrics: Equatable {
        var skippedDisplayedImageScans = 0
        var displayedImageScans = 0
        var preparations = 0
    }

    private(set) var thumbnailWindowMetrics = ThumbnailWindowMetrics()
#endif

    private struct CancellableLoad {
        let id: UUID
        let task: Task<Void, Never>
    }

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

    private static let maximumPrefetchLoadCount = 96

    private var contentAccess: ContentAccess?
    private var prefetchLoads = [Int: CancellableLoad]()
    private var lastThumbnailWindowRequest: ThumbnailWindowRequest?
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
        guard let contentAccess else { return false }
        return contentAccess.requiredImageQuality().isDenseGridThumbnail
            && !contentAccess.isRendererActive()
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
        Snapshot(lastThumbnailWindowRequest: lastThumbnailWindowRequest)
    }

    func restore(_ snapshot: Snapshot) {
        guard !isInvalidated else { return }
        lastThumbnailWindowRequest = snapshot.lastThumbnailWindowRequest
    }

    func setActive(_ active: Bool) {
        guard !isInvalidated else { return }
        isActive = active
    }

    func setVisible(_ visible: Bool) {
        guard !isInvalidated else { return }
        isVisible = visible
    }

    func setScrollMotionActive(_ active: Bool) {
        guard !isInvalidated else { return }
        isScrollMotionActive = active
    }

    func resetThumbnailWindow() {
        guard !isInvalidated else { return }
        lastThumbnailWindowRequest = nil
    }

    func invalidate() {
        guard !isInvalidated else { return }
        cancelVisibleCellImageLoads()
        isInvalidated = true
        cancelAllPrefetchLoads()
        stopDenseGridImageDisplayLink()
        contentAccess = nil
    }

    func prefetch(
        indexPaths: [IndexPath],
        centerTokenIndex: @MainActor () -> Int,
        requiredImageQuality: CollectionBrowseImageQuality,
        descriptor: @MainActor (Int) -> DownloadableMediaDescriptor?
    ) {
        guard !isInvalidated,
              isActive,
              contentAccess?.isApplyingPosition() == false,
              !requiredImageQuality.isDenseGridThumbnail,
              prefetchLoads.count < Self.maximumPrefetchLoadCount else {
            return
        }

        let centerTokenIndex = centerTokenIndex()
        let orderedIndices = Set(indexPaths.map(\.item)).sorted {
            let lhsDistance = abs($0 - centerTokenIndex)
            let rhsDistance = abs($1 - centerTokenIndex)
            return lhsDistance == rhsDistance ? $0 < $1 : lhsDistance < rhsDistance
        }

        for tokenIndex in orderedIndices {
            guard prefetchLoads.count < Self.maximumPrefetchLoadCount,
                  prefetchLoads[tokenIndex] == nil else {
                continue
            }
            let loadID = UUID()
            guard let descriptor = descriptor(tokenIndex) else { continue }
            startPrefetch(
                descriptor: descriptor,
                tokenIndex: tokenIndex,
                loadID: loadID
            )
        }
    }

    func cancelPrefetching(indexPaths: [IndexPath]) {
        guard !isInvalidated else { return }
        for tokenIndex in Set(indexPaths.map(\.item)) {
            prefetchLoads.removeValue(forKey: tokenIndex)?.task.cancel()
        }
    }

    func cancelAllPrefetchLoads() {
        let tasks = prefetchLoads.values.map(\.task)
        prefetchLoads.removeAll()
        tasks.forEach { $0.cancel() }
    }

    func cancelVisibleCellImageLoads() {
        guard !isInvalidated else { return }
        contentAccess?.visibleCells().forEach { $0.cancelImageLoad() }
    }

    func prepareThumbnailWindow(
        around tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        force: Bool,
        configuredPrefetchStride: Int,
        configuredColumnCount: Int,
        requiredImageQuality: CollectionBrowseImageQuality
    ) {
        guard !isInvalidated, isActive, let contentAccess else { return }
        let prefetchStride = PlayerCollectionBrowseMediaWindowPolicy
            .normalizedPrefetchStride(configuredPrefetchStride)
        let columnCount = configuredColumnCount
        let quality = requiredImageQuality
        let refreshDistance = quality.isDenseGridThumbnail
            ? PlayerCollectionBrowseMediaWindowPolicy.rowAlignedRefreshDistance(
                prefetchStride: prefetchStride,
                columnCount: columnCount
            )
            : prefetchStride
        let previousTokenIndex = lastThumbnailWindowRequest.flatMap {
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
                force: force
            )
        if quality.isDenseGridThumbnail, !shouldRefreshStableWindow {
#if DEBUG
            thumbnailWindowMetrics.skippedDisplayedImageScans += 1
#endif
            return
        }

        let visibleTokenRange = quality.isDenseGridThumbnail
            ? visibleBrowserTokenRange(contentAccess: contentAccess)
            : nil
        let requiredTokenRange = visibleTokenRange.map {
            requiredThumbnailWindowTokenRange(
                around: tokenIndex,
                direction: direction,
                refreshDistance: refreshDistance,
                visibleTokenRange: $0,
                contentAccess: contentAccess
            )
        }
        let displayedImages: DisplayedImageWindowState
        if quality == .large {
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
                displayedImages.locallyAvailableTokenIndices
        )
        if !force,
           let lastThumbnailWindowRequest,
           lastThumbnailWindowRequest
                .displayedHigherQualityThumbnailTokenIndices
                == displayedHigherQualityThumbnailTokenIndices,
           lastThumbnailWindowRequest.displayedLargeTokenIndices
                == displayedImages.tokenIndices,
           lastThumbnailWindowRequest.locallyAvailableLargeTokenIndices
                == displayedImages.locallyAvailableTokenIndices,
           !shouldRefreshStableWindow {
            return
        }

        contentAccess.prepareThumbnailWindow(ThumbnailWindowPreparation(
            tokenIndex: tokenIndex,
            direction: direction,
            prefetchStride: prefetchStride,
            columnCount: columnCount,
            quality: quality,
            requiredTokenRange: requiredTokenRange,
            displayedHigherQualityThumbnailTokenIndices:
                displayedHigherQualityThumbnailTokenIndices,
            displayedLargeTokenIndices: displayedImages.tokenIndices,
            locallyAvailableLargeTokenIndices:
                displayedImages.locallyAvailableTokenIndices
        ))
#if DEBUG
        thumbnailWindowMetrics.preparations += 1
#endif
        lastThumbnailWindowRequest = request
    }

    func configure(
        cell: MobilePlayerCollectionBrowserCell,
        tokenIndex: Int,
        requiredImageQuality: CollectionBrowseImageQuality?,
        imageLoadPolicy: MobilePlayerCollectionBrowserCell.ImageLoadPolicy?,
        apply: @MainActor (
            CollectionBrowseImageQuality,
            MobilePlayerCollectionBrowserCell.ImageLoadPolicy
        ) -> Void
    ) {
        guard !isInvalidated else { return }
        let defersDenseGridImageLoading = self.defersDenseGridImageLoading
        if imageLoadPolicy == nil, defersDenseGridImageLoading {
            cell.demoteImageLoadToCachedOnlyIfNeeded(tokenIndex: tokenIndex)
        }
        let resolvedImageLoadPolicy = imageLoadPolicy
            ?? (isActive || contentAccess?.isPreparedTransitionActive() == true
                ? (defersDenseGridImageLoading ? .cachedOnly : .foreground)
                : .disabled)
        let resolvedRequiredImageQuality = requiredImageQuality
            ?? contentAccess?.requiredImageQuality()
            ?? .large
        apply(resolvedRequiredImageQuality, resolvedImageLoadPolicy)

        guard resolvedImageLoadPolicy == .cachedOnly else { return }
        if imageLoadPolicy != nil {
            _ = cell.refreshCachedImageIfAvailable(tokenIndex: tokenIndex)
        } else if defersDenseGridImageLoading,
                  cell.needsCachedImageRefresh(tokenIndex: tokenIndex) {
            enqueueDenseGridImageRefresh(tokenIndex: tokenIndex)
        }
    }

    func willDisplay(
        cell: MobilePlayerCollectionBrowserCell,
        tokenIndex: Int,
        intersectsViewport: @MainActor () -> Bool
    ) {
        guard !isInvalidated,
              isActive || contentAccess?.isPreparedTransitionActive() == true,
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
        contentAccess.visibleCells().forEach {
            $0.updateLocalFileAvailability(
                notification: notification,
                isAvailable: change == .becameAvailable
            )
        }
        if defersDenseGridImageLoading || change == .becameUnavailable {
            return
        }
        contentAccess.viewportRenderCells().forEach {
            $0.refreshAvailableImageIfNeeded(notification: notification)
        }
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

    func drainDenseGridImageDisplayLinkFrameForTesting() -> Int {
        drainDenseGridImageRefreshes(limit: denseGridImageRefreshBatchSize)
    }

    func replacePendingDenseGridImageRefreshesForTesting(
        tokenIndices: [Int]
    ) {
        stopDenseGridImageDisplayLink()
        tokenIndices.forEach { enqueueDenseGridImageRefresh(tokenIndex: $0) }
    }
#endif

    private func startPrefetch(
        descriptor: DownloadableMediaDescriptor,
        tokenIndex: Int,
        loadID: UUID
    ) {
        let task = Task { @MainActor [weak self] in
            _ = await DownloadableMediaCache.shared.image(
                for: descriptor,
                priority: .preservingPrefetch
            )
            guard !Task.isCancelled else { return }
            await Task.yield()
            guard self?.prefetchLoads[tokenIndex]?.id == loadID else {
                return
            }
            self?.prefetchLoads.removeValue(forKey: tokenIndex)
        }
        prefetchLoads[tokenIndex] = CancellableLoad(
            id: loadID,
            task: task
        )
    }

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
        startDenseGridImageDisplayLinkIfNeeded()
    }

    @discardableResult
    private func drainDenseGridImageRefreshes(limit: Int) -> Int {
        guard defersDenseGridImageLoading else {
            stopDenseGridImageDisplayLink()
            return 0
        }
        var processedCount = 0
        let tokenIndices = denseGridImageRefreshQueue.dequeue(limit: limit)
        var retryTokenIndices = [Int]()
        retryTokenIndices.reserveCapacity(tokenIndices.count)
        for tokenIndex in tokenIndices {
            processedCount += 1
            let indexPath = IndexPath(item: tokenIndex, section: 0)
            guard let cell = contentAccess?.cell(indexPath) else { continue }
            switch cell.refreshCachedImageIfAvailable(tokenIndex: tokenIndex) {
            case .satisfied, .unavailable:
                break
            case .retry:
                retryTokenIndices.append(tokenIndex)
            }
        }
        retryTokenIndices.forEach {
            enqueueDenseGridImageRefresh(tokenIndex: $0)
        }
        if denseGridImageRefreshQueue.count == 0 {
            stopDenseGridImageDisplayLink()
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

    mutating func dequeue(limit: Int) -> [Int] {
        let count = min(max(limit, 0), tokenIndices.count)
        let result = Array(tokenIndices.prefix(count))
        tokenIndices.removeFirst(count)
        result.forEach { tokenIndexSet.remove($0) }
        return result
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
    static let minimumBatchSize = 5
    static let maximumBatchSize = 9

    static func batchSize(baseColumnCount: Int) -> Int {
        min(max(baseColumnCount, minimumBatchSize), maximumBatchSize)
    }
}
