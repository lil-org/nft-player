// ∅ 2026 lil org

import CoreGraphics

struct MobilePlayerBrowserAspectProfile: Equatable {
    private enum Storage: Equatable {
        case uniform(CGFloat)
        case variableRows([CGFloat])
    }

    let itemCount: Int
    let columnCount: Int
    private let storage: Storage

    var usesUniformAspectRatio: Bool {
        if case .uniform = storage {
            return true
        }
        return false
    }

    init(
        itemCount: Int,
        uniformImageSize: CGSize,
        columnCount: Int = MobilePlayerBrowserLayout.defaultColumnCount
    ) {
        self.itemCount = max(itemCount, 0)
        self.columnCount = Self.sanitizedColumnCount(columnCount)
        self.storage = .uniform(Self.heightToWidthRatio(for: uniformImageSize))
    }

    init(
        itemImageSizes: [CGSize],
        columnCount: Int = MobilePlayerBrowserLayout.defaultColumnCount
    ) {
        self.init(
            heightToWidthRatios: itemImageSizes.map(Self.heightToWidthRatio(for:)),
            columnCount: columnCount
        )
    }

    init(
        heightToWidthRatios: [CGFloat],
        columnCount: Int = MobilePlayerBrowserLayout.defaultColumnCount
    ) {
        itemCount = heightToWidthRatios.count
        self.columnCount = Self.sanitizedColumnCount(columnCount)
        guard let firstRatio = heightToWidthRatios.first.map(
            Self.sanitizedHeightToWidthRatio
        ) else {
            storage = .uniform(1)
            return
        }

        var allItemsUseFirstRatio = true
        var rowMaximumRatios = [CGFloat]()
        let rowCount = heightToWidthRatios.isEmpty
            ? 0
            : (heightToWidthRatios.count - 1)
                / self.columnCount + 1
        rowMaximumRatios.reserveCapacity(
            rowCount
        )
        for rowStartIndex in stride(
            from: 0,
            to: heightToWidthRatios.count,
            by: self.columnCount
        ) {
            let rowEndIndex = min(
                rowStartIndex + self.columnCount,
                heightToWidthRatios.count
            )
            var rowMaximumRatio: CGFloat = 0
            for itemIndex in rowStartIndex..<rowEndIndex {
                let ratio = Self.sanitizedHeightToWidthRatio(
                    heightToWidthRatios[itemIndex]
                )
                allItemsUseFirstRatio = allItemsUseFirstRatio && ratio == firstRatio
                rowMaximumRatio = max(rowMaximumRatio, ratio)
            }
            rowMaximumRatios.append(rowMaximumRatio)
        }

        if allItemsUseFirstRatio {
            storage = .uniform(firstRatio)
        } else {
            storage = .variableRows(rowMaximumRatios)
        }
    }

    fileprivate func heightToWidthRatio(
        atRow rowIndex: Int,
        effectiveColumnCount: Int
    ) -> CGFloat? {
        let rowCount = itemCount > 0
            ? (itemCount - 1) / effectiveColumnCount + 1
            : 0
        guard (0..<rowCount).contains(rowIndex) else { return nil }
        switch storage {
        case let .uniform(ratio):
            return ratio
        case let .variableRows(ratios):
            let profileRowsPerLayoutRow = effectiveColumnCount / columnCount
            guard profileRowsPerLayoutRow > 0 else { return nil }
            let firstProfileRow = rowIndex * profileRowsPerLayoutRow
            let lastProfileRow = min(
                firstProfileRow + profileRowsPerLayoutRow,
                ratios.count
            )
            guard firstProfileRow < lastProfileRow else { return nil }
            return ratios[firstProfileRow..<lastProfileRow].max()
        }
    }

    fileprivate var uniformHeightToWidthRatio: CGFloat? {
        guard case let .uniform(ratio) = storage else { return nil }
        return ratio
    }

    private static func heightToWidthRatio(for size: CGSize) -> CGFloat {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return 1
        }
        return size.height / size.width
    }

    private static func sanitizedHeightToWidthRatio(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return 1 }
        return ratio
    }

    private static func sanitizedColumnCount(_ columnCount: Int) -> Int {
        columnCount > 0
            ? columnCount
            : MobilePlayerBrowserLayout.defaultColumnCount
    }
}

struct MobilePlayerBrowserViewportTransition {
    let needsInitialLayout: Bool
    let geometryChanged: Bool
    let retainedFocusTokenIndex: Int?
    let layout: MobilePlayerBrowserLayout?

    var needsLayout: Bool {
        needsInitialLayout || geometryChanged
    }
}

struct MobilePlayerBrowserLayout: Equatable {
    private enum RowStorage: Equatable {
        case uniform(height: CGFloat)
        case variable(starts: [CGFloat], heights: [CGFloat])
    }

    private struct HorizontalMetrics {
        let itemWidth: CGFloat
        let columnCount: Int
        let interItemSpacing: CGFloat
    }

    static let defaultColumnCount = 3
    static let itemSpacing: CGFloat = 1
    static let maximumAspectSampleCount = 15
    static let maximumPrefetchStride = 15

    let itemWidth: CGFloat
    let itemCount: Int
    let columnCount: Int
    let interItemSpacing: CGFloat
    let rowCount: Int
    let contentSize: CGSize
    let visibleRowCount: Int
    let prefetchStride: Int

    private let topContentInset: CGFloat
    private let rowStorage: RowStorage

    var usesUniformRowHeights: Bool {
        if case .uniform = rowStorage {
            return true
        }
        return false
    }

    var cachedVariableRowCount: Int {
        if case let .variable(_, heights) = rowStorage {
            return heights.count
        }
        return 0
    }

    var uniformItemSize: CGSize? {
        guard case let .uniform(height) = rowStorage else { return nil }
        return CGSize(width: itemWidth, height: height)
    }

    static func itemWidth(
        viewportSize: CGSize,
        columnCount: Int
    ) -> CGFloat? {
        horizontalMetrics(
            viewportSize: viewportSize,
            columnCount: columnCount
        )?.itemWidth
    }

    static func viewportTransition(
        previousViewportSize: CGSize,
        viewportSize: CGSize,
        needsSafeAreaRefresh: Bool,
        topContentInset: CGFloat = 0,
        bottomContentInset: CGFloat = 0,
        aspectProfile: MobilePlayerBrowserAspectProfile,
        forcedTokenIndex: Int?,
        interactionAnchorTokenIndex: Int? = nil,
        focusedTokenIndex: Int?
    ) -> MobilePlayerBrowserViewportTransition {
        let needsInitialLayout = previousViewportSize == .zero
        let sizeChanged = !needsInitialLayout
            && previousViewportSize != viewportSize
        let geometryChanged = sizeChanged || needsSafeAreaRefresh
        let needsLayout = needsInitialLayout || geometryChanged

        return MobilePlayerBrowserViewportTransition(
            needsInitialLayout: needsInitialLayout,
            geometryChanged: geometryChanged,
            retainedFocusTokenIndex: geometryChanged
                ? interactionAnchorTokenIndex
                    ?? forcedTokenIndex
                    ?? focusedTokenIndex
                : nil,
            layout: needsLayout
                ? MobilePlayerBrowserLayout(
                    viewportSize: viewportSize,
                    topContentInset: topContentInset,
                    bottomContentInset: bottomContentInset,
                    aspectProfile: aspectProfile
                )
                : nil
        )
    }

    static func contentOffsetYAfterSafeAreaChange(
        previousContentOffsetY: CGFloat,
        previousRange: ClosedRange<CGFloat>,
        updatedRange: ClosedRange<CGFloat>,
        topContentInsetDelta: CGFloat,
        boundaryEpsilon: CGFloat
    ) -> CGFloat {
        guard updatedRange.lowerBound.isFinite,
              updatedRange.upperBound.isFinite else {
            return 0
        }
        guard previousContentOffsetY.isFinite,
              previousRange.lowerBound.isFinite,
              previousRange.upperBound.isFinite,
              previousRange.lowerBound <= previousRange.upperBound,
              updatedRange.lowerBound <= updatedRange.upperBound else {
            return updatedRange.lowerBound
        }

        let epsilon = boundaryEpsilon.isFinite
            ? max(boundaryEpsilon, 0)
            : 0
        let clampedPreviousContentOffsetY = min(
            max(previousContentOffsetY, previousRange.lowerBound),
            previousRange.upperBound
        )
        let distanceToLowerBound =
            clampedPreviousContentOffsetY - previousRange.lowerBound
        let distanceToUpperBound =
            previousRange.upperBound - clampedPreviousContentOffsetY
        if min(distanceToLowerBound, distanceToUpperBound) <= epsilon {
            return distanceToUpperBound < distanceToLowerBound
                ? updatedRange.upperBound
                : updatedRange.lowerBound
        }

        let insetDelta = topContentInsetDelta.isFinite
            ? topContentInsetDelta
            : 0
        let proposedContentOffsetY =
            clampedPreviousContentOffsetY + insetDelta
        guard proposedContentOffsetY.isFinite else {
            return insetDelta > 0
                ? updatedRange.upperBound
                : updatedRange.lowerBound
        }
        return min(
            max(proposedContentOffsetY, updatedRange.lowerBound),
            updatedRange.upperBound
        )
    }

    init?(
        viewportSize: CGSize,
        topContentInset: CGFloat = 0,
        bottomContentInset: CGFloat = 0,
        aspectProfile: MobilePlayerBrowserAspectProfile
    ) {
        guard let horizontalMetrics = Self.horizontalMetrics(
            viewportSize: viewportSize,
            columnCount: aspectProfile.columnCount
        ) else {
            return nil
        }

        let effectiveColumnCount = horizontalMetrics.columnCount
        let interItemSpacing = horizontalMetrics.interItemSpacing
        let itemWidth = horizontalMetrics.itemWidth
        let sanitizedTopInset = topContentInset.isFinite ? max(topContentInset, 0) : 0
        let sanitizedBottomInset = bottomContentInset.isFinite ? max(bottomContentInset, 0) : 0
        let itemCount = aspectProfile.itemCount
        let rowCount = itemCount > 0
            ? (itemCount - 1) / effectiveColumnCount + 1
            : 0

        let rowStorage: RowStorage
        let rowsHeight: CGFloat
        let shortestRowHeight: CGFloat
        if let uniformRatio = aspectProfile.uniformHeightToWidthRatio {
            let rowHeight = itemWidth * uniformRatio
            rowStorage = .uniform(height: rowHeight)
            rowsHeight = rowHeight * CGFloat(rowCount)
                + interItemSpacing * CGFloat(max(rowCount - 1, 0))
            shortestRowHeight = rowHeight
        } else {
            var rowHeights = [CGFloat]()
            rowHeights.reserveCapacity(rowCount)
            for rowIndex in 0..<rowCount {
                let rowRatio = aspectProfile.heightToWidthRatio(
                    atRow: rowIndex,
                    effectiveColumnCount: effectiveColumnCount
                ) ?? 1
                rowHeights.append(itemWidth * rowRatio)
            }

            if let firstHeight = rowHeights.first,
               rowHeights.dropFirst().allSatisfy({ $0 == firstHeight }) {
                rowStorage = .uniform(height: firstHeight)
            } else {
                var starts = [CGFloat]()
                starts.reserveCapacity(rowCount)
                var nextStart = sanitizedTopInset
                for height in rowHeights {
                    starts.append(nextStart)
                    nextStart += height + interItemSpacing
                }
                rowStorage = .variable(starts: starts, heights: rowHeights)
            }
            rowsHeight = rowHeights.reduce(0, +)
                + interItemSpacing * CGFloat(max(rowCount - 1, 0))
            shortestRowHeight = rowHeights.min() ?? itemWidth
        }

        let visibleHeight = max(
            viewportSize.height - sanitizedTopInset - sanitizedBottomInset,
            0
        )
        let visibleRowEstimate = ceil(
            (visibleHeight + interItemSpacing)
                / (shortestRowHeight + interItemSpacing)
        )
        let visibleRowCount = visibleRowEstimate.isFinite
            && visibleRowEstimate < CGFloat(Int.max)
            ? max(Int(visibleRowEstimate), 1)
            : Int.max
        let maximumPrefetchRowCount =
            (Self.maximumPrefetchStride - 1) / effectiveColumnCount + 1

        self.itemWidth = itemWidth
        self.itemCount = itemCount
        self.columnCount = effectiveColumnCount
        self.interItemSpacing = interItemSpacing
        self.rowCount = rowCount
        self.contentSize = CGSize(
            width: viewportSize.width,
            height: sanitizedTopInset + rowsHeight + sanitizedBottomInset
        )
        self.visibleRowCount = visibleRowCount
        self.prefetchStride = min(
            min(visibleRowCount, maximumPrefetchRowCount) * effectiveColumnCount,
            Self.maximumPrefetchStride
        )
        self.topContentInset = sanitizedTopInset
        self.rowStorage = rowStorage
    }

    func itemSize(at itemIndex: Int) -> CGSize? {
        guard let height = rowHeight(containingItemAt: itemIndex) else { return nil }
        return CGSize(width: itemWidth, height: height)
    }

    func itemFrame(at itemIndex: Int) -> CGRect? {
        guard (0..<itemCount).contains(itemIndex) else { return nil }
        let rowIndex = itemIndex / columnCount
        let columnIndex = itemIndex % columnCount
        guard let rowStart = rowStart(at: rowIndex),
              let rowHeight = rowHeight(at: rowIndex) else {
            return nil
        }
        return CGRect(
            x: CGFloat(columnIndex) * (itemWidth + interItemSpacing),
            y: rowStart,
            width: itemWidth,
            height: rowHeight
        )
    }

    func candidateItemIndices(intersecting rect: CGRect) -> Range<Int> {
        guard itemCount > 0,
              rowCount > 0,
              rect.minY.isFinite,
              rect.maxY.isFinite else {
            return 0..<0
        }
        if let firstRowStart = rowStart(at: 0),
           let lastRowStart = rowStart(at: rowCount - 1),
           let lastRowHeight = rowHeight(at: rowCount - 1) {
            let lastRowEnd = lastRowStart + lastRowHeight
            if rect.maxY <= firstRowStart
                || (lastRowEnd.isFinite && rect.minY >= lastRowEnd) {
                return 0..<0
            }
        }

        let rowRange: Range<Int>
        switch rowStorage {
        case let .uniform(height):
            let travel = height + interItemSpacing
            let firstRowEstimate = floor((rect.minY - topContentInset) / travel)
            let lastRowEstimate = floor((rect.maxY - topContentInset) / travel)
            guard !firstRowEstimate.isNaN,
                  !lastRowEstimate.isNaN else {
                return 0..<0
            }
            let approximateFirstRow = Self.clampedRowIndex(
                firstRowEstimate,
                rowCount: rowCount
            )
            let approximateLastRow = Self.clampedRowIndex(
                lastRowEstimate,
                rowCount: rowCount
            )
            let lowerBound = approximateFirstRow > 0
                ? approximateFirstRow - 1
                : 0
            let upperBound = approximateLastRow >= rowCount - 2
                ? rowCount
                : approximateLastRow + 2
            rowRange = lowerBound..<max(lowerBound, upperBound)

        case let .variable(starts, _):
            let firstInsertionIndex = Self.upperBound(in: starts, for: rect.minY)
            let lastInsertionIndex = Self.upperBound(in: starts, for: rect.maxY)
            let lowerBound = firstInsertionIndex > 0
                ? firstInsertionIndex - 1
                : 0
            let upperBound = lastInsertionIndex < rowCount
                ? lastInsertionIndex + 1
                : rowCount
            rowRange = lowerBound..<max(lowerBound, upperBound)
        }

        let firstItemIndex = itemIndex(atRowBoundary: rowRange.lowerBound)
        let lastItemIndex = itemIndex(atRowBoundary: rowRange.upperBound)
        guard firstItemIndex < lastItemIndex else { return 0..<0 }
        return firstItemIndex..<lastItemIndex
    }

    func minimumAdjacentRowCenterDistance(containingItemAt itemIndex: Int) -> CGFloat? {
        guard (0..<itemCount).contains(itemIndex) else { return nil }
        let rowIndex = itemIndex / columnCount
        guard let center = rowCenter(at: rowIndex) else { return nil }

        var minimumDistance: CGFloat?
        if let previousCenter = rowCenter(at: rowIndex - 1) {
            minimumDistance = center - previousCenter
        }
        if let nextCenter = rowCenter(at: rowIndex + 1) {
            let nextDistance = nextCenter - center
            minimumDistance = minimumDistance.map { min($0, nextDistance) }
                ?? nextDistance
        }
        return minimumDistance
            ?? rowHeight(at: rowIndex).map { $0 + interItemSpacing }
    }

    private func rowHeight(containingItemAt itemIndex: Int) -> CGFloat? {
        guard (0..<itemCount).contains(itemIndex) else { return nil }
        return rowHeight(at: itemIndex / columnCount)
    }

    private func rowHeight(at rowIndex: Int) -> CGFloat? {
        guard (0..<rowCount).contains(rowIndex) else { return nil }
        switch rowStorage {
        case let .uniform(height):
            return height
        case let .variable(_, heights):
            return heights[rowIndex]
        }
    }

    private func rowStart(at rowIndex: Int) -> CGFloat? {
        guard (0..<rowCount).contains(rowIndex) else { return nil }
        switch rowStorage {
        case let .uniform(height):
            return topContentInset + CGFloat(rowIndex) * (height + interItemSpacing)
        case let .variable(starts, _):
            return starts[rowIndex]
        }
    }

    private func rowCenter(at rowIndex: Int) -> CGFloat? {
        guard let start = rowStart(at: rowIndex),
              let height = rowHeight(at: rowIndex) else {
            return nil
        }
        return start + height / 2
    }

    private func itemIndex(atRowBoundary rowBoundary: Int) -> Int {
        guard rowBoundary > 0 else { return 0 }
        guard rowBoundary < rowCount else { return itemCount }
        let (itemIndex, overflowed) = rowBoundary.multipliedReportingOverflow(
            by: columnCount
        )
        return overflowed ? itemCount : min(itemIndex, itemCount)
    }

    private static func clampedRowIndex(
        _ estimate: CGFloat,
        rowCount: Int
    ) -> Int {
        guard rowCount > 1 else { return 0 }
        guard estimate > 0 else { return 0 }
        let lastRowIndex = rowCount - 1
        guard estimate < CGFloat(lastRowIndex) else { return lastRowIndex }
        return min(Int(estimate), lastRowIndex)
    }

    private static func upperBound(in values: [CGFloat], for target: CGFloat) -> Int {
        var lowerBound = 0
        var upperBound = values.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if values[middle] <= target {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private static func horizontalMetrics(
        viewportSize: CGSize,
        columnCount: Int
    ) -> HorizontalMetrics? {
        guard columnCount > 0,
              viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.height > 0 else {
            return nil
        }

        let columnMultiplier = viewportSize.width > viewportSize.height ? 2 : 1
        let (effectiveColumnCount, overflowed) =
            columnCount.multipliedReportingOverflow(by: columnMultiplier)
        let interItemSpacing = columnCount == 1
            ? itemSpacing * 2
            : itemSpacing
        guard !overflowed,
              viewportSize.width
                > interItemSpacing * CGFloat(effectiveColumnCount - 1) else {
            return nil
        }

        let horizontalSpacing =
            interItemSpacing * CGFloat(effectiveColumnCount - 1)
        return HorizontalMetrics(
            itemWidth: (viewportSize.width - horizontalSpacing)
                / CGFloat(effectiveColumnCount),
            columnCount: effectiveColumnCount,
            interItemSpacing: interItemSpacing
        )
    }
}

struct MobilePlayerBrowserGridTransition {
    let fromLayout: MobilePlayerBrowserLayout
    let toLayout: MobilePlayerBrowserLayout
    private(set) var progress: CGFloat

    init?(
        fromLayout: MobilePlayerBrowserLayout,
        toLayout: MobilePlayerBrowserLayout
    ) {
        guard fromLayout.itemWidth > 0,
              toLayout.itemWidth > 0,
              fromLayout.itemCount == toLayout.itemCount,
              fromLayout.itemWidth != toLayout.itemWidth else {
            return nil
        }
        self.fromLayout = fromLayout
        self.toLayout = toLayout
        self.progress = 0
    }

    var itemCount: Int {
        fromLayout.itemCount
    }

    var itemWidthRatio: CGFloat {
        toLayout.itemWidth / fromLayout.itemWidth
    }

    var contentSize: CGSize {
        CGSize(
            width: interpolated(fromLayout.contentSize.width, toLayout.contentSize.width),
            height: interpolated(fromLayout.contentSize.height, toLayout.contentSize.height)
        )
    }

    mutating func setProgress(_ progress: CGFloat) {
        guard progress.isFinite else { return }
        self.progress = min(max(progress, 0), 1)
    }

    func itemFrame(at itemIndex: Int) -> CGRect? {
        guard itemIndex < itemCount,
              let fromFrame = fromLayout.itemFrame(at: itemIndex),
              let toFrame = toLayout.itemFrame(at: itemIndex) else {
            return nil
        }
        return CGRect(
            x: interpolated(fromFrame.minX, toFrame.minX),
            y: interpolated(fromFrame.minY, toFrame.minY),
            width: interpolated(fromFrame.width, toFrame.width),
            height: interpolated(fromFrame.height, toFrame.height)
        )
    }

    func candidateItemIndices(intersecting rect: CGRect) -> Range<Int> {
        guard itemCount > 0,
              rect.minY.isFinite,
              rect.maxY.isFinite,
              rect.minY <= rect.maxY else {
            return 0..<0
        }

        let firstIndex = lowestItemIndex { $0.maxY >= rect.minY }
        let endIndex = lowestItemIndex { $0.minY > rect.maxY }
        guard firstIndex < endIndex else { return 0..<0 }
        return firstIndex..<endIndex
    }

    func contentOffsetY(
        fromContentOffsetY: CGFloat,
        toContentOffsetY: CGFloat,
        panDeltaY: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let sanitizedPanDeltaY = panDeltaY.isFinite ? panDeltaY : 0
        let proposedOffsetY = interpolated(fromContentOffsetY, toContentOffsetY)
            - sanitizedPanDeltaY
        return Self.clampedContentOffsetY(
            proposedOffsetY,
            contentHeight: contentSize.height,
            viewportHeight: viewportHeight
        )
    }

    static func anchorRelativeY(
        contentY: CGFloat,
        itemFrame: CGRect
    ) -> CGFloat {
        guard contentY.isFinite,
              itemFrame.minY.isFinite,
              itemFrame.height.isFinite,
              itemFrame.height > 0 else {
            return 0.5
        }
        return min(max((contentY - itemFrame.minY) / itemFrame.height, 0), 1)
    }

    static func anchorY(
        itemFrame: CGRect,
        relativeY: CGFloat
    ) -> CGFloat {
        guard itemFrame.minY.isFinite,
              itemFrame.height.isFinite,
              itemFrame.height > 0 else {
            return itemFrame.midY.isFinite ? itemFrame.midY : 0
        }
        let sanitizedRelativeY = relativeY.isFinite
            ? min(max(relativeY, 0), 1)
            : 0.5
        return itemFrame.minY + itemFrame.height * sanitizedRelativeY
    }

    static func targetContentOffsetY(
        anchorFrame: CGRect,
        anchorRelativeY: CGFloat,
        anchorViewportY: CGFloat
    ) -> CGFloat {
        anchorY(
            itemFrame: anchorFrame,
            relativeY: anchorRelativeY
        ) - anchorViewportY
    }

    static func clampedContentOffsetY(
        _ contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        guard contentOffsetY.isFinite else { return 0 }
        let maximumOffsetY = max(contentHeight - viewportHeight, 0)
        return min(max(contentOffsetY, 0), maximumOffsetY)
    }

    private func interpolated(_ fromValue: CGFloat, _ toValue: CGFloat) -> CGFloat {
        fromValue + (toValue - fromValue) * progress
    }

    private func lowestItemIndex(
        where predicate: (CGRect) -> Bool
    ) -> Int {
        var lowerBound = 0
        var upperBound = itemCount
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            guard let frame = itemFrame(at: middle) else {
                return itemCount
            }
            if predicate(frame) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        return lowerBound
    }
}
