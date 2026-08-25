// ∅ 2026 lil org

import CoreGraphics

nonisolated struct MobilePlayerBrowserAspectProfile: Equatable, Sendable {
    private enum Storage: Equatable, Sendable {
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

nonisolated struct MobilePlayerBrowserViewportTransition: Sendable {
    let needsInitialLayout: Bool
    let geometryChanged: Bool
    let retainedFocusTokenIndex: Int?
    let layout: MobilePlayerBrowserLayout?

    var needsLayout: Bool {
        needsInitialLayout || geometryChanged
    }
}

nonisolated enum PlayerCollectionBrowseMediaWindowPolicy: Sendable {
    struct Radii: Equatable, Sendable {
        let preferred: Int
        let opposite: Int
    }

    struct CompactCoverage: Equatable, Sendable {
        let decodedRange: ClosedRange<Int>
        let fileRange: ClosedRange<Int>
    }

    static func decodedRadii(prefetchStride: Int) -> Radii {
        radii(
            prefetchStride: prefetchStride,
            preferredStrideCount: 2,
            oppositeStrideCount: 1
        )
    }

    static func fileRadii(prefetchStride: Int) -> Radii {
        radii(
            prefetchStride: prefetchStride,
            preferredStrideCount: 6,
            oppositeStrideCount: 2
        )
    }

    static func compactCoverage(
        centeredAt tokenIndex: Int,
        requiredTokenRange: ClosedRange<Int>,
        itemCount: Int,
        columnCount: Int,
        prefetchStride: Int,
        prefersIncreasingIndices: Bool
    ) -> CompactCoverage? {
        guard itemCount > 0,
              columnCount > 0,
              (0..<itemCount).contains(tokenIndex),
              requiredTokenRange.lowerBound >= 0,
              requiredTokenRange.upperBound < itemCount,
              requiredTokenRange.contains(tokenIndex) else {
            return nil
        }

        let lastTokenIndex = itemCount - 1
        let lastCollectionRow = lastTokenIndex / columnCount
        guard let decodedRange = rowAlignedTokenRange(
            firstRow: requiredTokenRange.lowerBound / columnCount,
            lastRow: requiredTokenRange.upperBound / columnCount,
            lastCollectionRow: lastCollectionRow,
            itemCount: itemCount,
            columnCount: columnCount
        ) else {
            return nil
        }

        let standardFileRange = directionalTokenRange(
            centeredAt: tokenIndex,
            itemCount: itemCount,
            radii: fileRadii(prefetchStride: prefetchStride),
            prefersIncreasingIndices: prefersIncreasingIndices
        )
        return CompactCoverage(
            decodedRange: decodedRange,
            fileRange: min(
                standardFileRange.lowerBound,
                decodedRange.lowerBound
            )...max(
                standardFileRange.upperBound,
                decodedRange.upperBound
            )
        )
    }

    static func nearestFirstTokenIndices(
        centeredAt tokenIndex: Int,
        in range: ClosedRange<Int>,
        prefersIncreasingIndices: Bool
    ) -> [Int] {
        guard range.lowerBound >= 0, range.contains(tokenIndex) else { return [] }

        var indices = [tokenIndex]
        var preferredIndex = nextTokenIndex(
            after: tokenIndex,
            increasing: prefersIncreasingIndices,
            in: range
        )
        var oppositeIndex = nextTokenIndex(
            after: tokenIndex,
            increasing: !prefersIncreasingIndices,
            in: range
        )
        while preferredIndex != nil || oppositeIndex != nil {
            if let index = preferredIndex {
                indices.append(index)
                preferredIndex = nextTokenIndex(
                    after: index,
                    increasing: prefersIncreasingIndices,
                    in: range
                )
            }
            if let index = oppositeIndex {
                indices.append(index)
                oppositeIndex = nextTokenIndex(
                    after: index,
                    increasing: !prefersIncreasingIndices,
                    in: range
                )
            }
        }
        return indices
    }

    static func normalizedPrefetchStride(_ prefetchStride: Int) -> Int {
        min(
            max(prefetchStride, 1),
            MobilePlayerBrowserLayout.maximumPrefetchStride
        )
    }

    static func rowAlignedRefreshDistance(
        prefetchStride: Int,
        columnCount: Int
    ) -> Int {
        let stride = normalizedPrefetchStride(prefetchStride)
        let columns = max(columnCount, 1)
        let rowCount = (stride - 1) / columns + 1
        let distance = rowCount.multipliedReportingOverflow(by: columns)
        return distance.overflow ? Int.max : distance.partialValue
    }

    static func shouldRefresh(
        previousTokenIndex: Int?,
        nextTokenIndex: Int,
        prefetchStride: Int,
        force: Bool
    ) -> Bool {
        shouldRefresh(
            previousTokenIndex: previousTokenIndex,
            nextTokenIndex: nextTokenIndex,
            refreshDistance: normalizedPrefetchStride(prefetchStride),
            force: force
        )
    }

    static func shouldRefresh(
        previousTokenIndex: Int?,
        nextTokenIndex: Int,
        refreshDistance: Int,
        force: Bool
    ) -> Bool {
        guard !force, let previousTokenIndex else {
            return true
        }
        let distance = max(refreshDistance, 1)
        let delta = nextTokenIndex.subtractingReportingOverflow(
            previousTokenIndex
        )
        return delta.overflow || delta.partialValue.magnitude >= UInt(distance)
    }

    private static func radii(
        prefetchStride: Int,
        preferredStrideCount: Int,
        oppositeStrideCount: Int
    ) -> Radii {
        let stride = normalizedPrefetchStride(prefetchStride)
        return Radii(
            preferred: stride * preferredStrideCount,
            opposite: stride * oppositeStrideCount
        )
    }

    private static func rowAlignedTokenRange(
        firstRow: Int,
        lastRow: Int,
        lastCollectionRow: Int,
        itemCount: Int,
        columnCount: Int
    ) -> ClosedRange<Int>? {
        let firstToken = firstRow.multipliedReportingOverflow(by: columnCount)
        guard !firstToken.overflow else { return nil }

        let lastToken: Int
        if lastRow == lastCollectionRow {
            lastToken = itemCount - 1
        } else {
            let nextRow = lastRow.addingReportingOverflow(1)
            guard !nextRow.overflow else { return nil }
            let nextRowToken = nextRow.partialValue
                .multipliedReportingOverflow(by: columnCount)
            guard !nextRowToken.overflow else { return nil }
            lastToken = nextRowToken.partialValue - 1
        }
        guard firstToken.partialValue <= lastToken else { return nil }
        return firstToken.partialValue...lastToken
    }

    private static func directionalTokenRange(
        centeredAt tokenIndex: Int,
        itemCount: Int,
        radii: Radii,
        prefersIncreasingIndices: Bool
    ) -> ClosedRange<Int> {
        let lastTokenIndex = itemCount - 1
        let increasingRadius = prefersIncreasingIndices
            ? radii.preferred
            : radii.opposite
        let decreasingRadius = prefersIncreasingIndices
            ? radii.opposite
            : radii.preferred
        let lowerBound = tokenIndex - min(tokenIndex, decreasingRadius)
        let upperBound = tokenIndex + min(
            lastTokenIndex - tokenIndex,
            increasingRadius
        )
        return lowerBound...upperBound
    }

    private static func nextTokenIndex(
        after tokenIndex: Int,
        increasing: Bool,
        in range: ClosedRange<Int>
    ) -> Int? {
        if increasing {
            return tokenIndex < range.upperBound ? tokenIndex + 1 : nil
        }
        return tokenIndex > range.lowerBound ? tokenIndex - 1 : nil
    }
}

nonisolated struct MobilePlayerBrowserLayout: Equatable, Sendable {
    private enum RowStorage: Equatable, Sendable {
        case uniform(height: CGFloat)
        case variable(starts: [CGFloat], heights: [CGFloat])
    }

    private struct HorizontalMetrics: Sendable {
        let itemWidth: CGFloat
        let columnCount: Int
        let interItemSpacing: CGFloat
    }

    static let defaultColumnCount = 3
    /// Photos' grid seam, measured at 5 device pixels on 3x at every zoom
    /// level and held constant through transitions.
    static let itemSpacing: CGFloat = 5.0 / 3.0
    static let maximumAspectSampleCount = 15
    static let prefetchItemBudget = 15
    static let preferredPrefetchRowCount = 5
    static let maximumPrefetchStride = 25
    private static let pointLookupProbeSize: CGFloat = 0.001

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
        columnCount: Int,
        displayScale: CGFloat = 3
    ) -> CGFloat? {
        horizontalMetrics(
            viewportSize: viewportSize,
            columnCount: columnCount,
            displayScale: displayScale
        )?.itemWidth
    }

    static func viewportTransition(
        previousViewportSize: CGSize,
        viewportSize: CGSize,
        needsGeometryRefresh: Bool,
        displayScale: CGFloat = 3,
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
        let geometryChanged = sizeChanged || needsGeometryRefresh
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
                    displayScale: displayScale,
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
        displayScale: CGFloat = 3,
        topContentInset: CGFloat = 0,
        bottomContentInset: CGFloat = 0,
        aspectProfile: MobilePlayerBrowserAspectProfile
    ) {
        guard let horizontalMetrics = Self.horizontalMetrics(
            viewportSize: viewportSize,
            columnCount: aspectProfile.columnCount,
            displayScale: displayScale
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
        let preferredPrefetchRowCount = max(
            (Self.prefetchItemBudget - 1) / effectiveColumnCount + 1,
            Self.preferredPrefetchRowCount
        )
        let prefetchRowCount = min(
            visibleRowCount,
            preferredPrefetchRowCount
        )

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
        self.prefetchStride = prefetchRowCount
            > Self.maximumPrefetchStride / effectiveColumnCount
            ? Self.maximumPrefetchStride
            : prefetchRowCount * effectiveColumnCount
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

    func itemIndices(inRow rowIndex: Int) -> Range<Int> {
        guard (0..<rowCount).contains(rowIndex) else { return 0..<0 }
        return itemIndex(atRowBoundary: rowIndex)..<itemIndex(
            atRowBoundary: rowIndex + 1
        )
    }

    func itemIndex(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let probe = CGRect(
            x: point.x,
            y: point.y,
            width: Self.pointLookupProbeSize,
            height: Self.pointLookupProbeSize
        )
        for itemIndex in candidateItemIndices(intersecting: probe)
        where itemFrame(at: itemIndex)?.contains(point) == true {
            return itemIndex
        }
        return nil
    }

    /// Like `itemIndex(at:)`, but a point that lands inside an inter-item gap
    /// or barely outside a frame still resolves to the closest item within
    /// `tolerance`. Grid-transition endpoint mapping uses this: a mapped cell
    /// center may drift into a seam by a fraction of the spacing.
    func nearestItemIndex(
        to point: CGPoint,
        tolerance: CGFloat
    ) -> Int? {
        if let exact = itemIndex(at: point) { return exact }
        guard point.x.isFinite,
              point.y.isFinite,
              tolerance.isFinite,
              tolerance > 0 else {
            return nil
        }
        let candidateTolerance = tolerance + Self.pointLookupProbeSize
        let probe = CGRect(
            x: point.x - candidateTolerance,
            y: point.y - candidateTolerance,
            width: candidateTolerance * 2,
            height: candidateTolerance * 2
        )
        var nearestIndex: Int?
        var nearestDistance = CGFloat.infinity
        for itemIndex in candidateItemIndices(intersecting: probe) {
            guard let frame = itemFrame(at: itemIndex) else { continue }
            let dx = max(frame.minX - point.x, point.x - frame.maxX, 0)
            let dy = max(frame.minY - point.y, point.y - frame.maxY, 0)
            let distance = max(dx, dy)
            if distance <= tolerance, distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = itemIndex
            }
        }
        return nearestIndex
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
        columnCount: Int,
        displayScale: CGFloat
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
        let interItemSpacing = integralPixelItemSpacing(
            displayScale: displayScale
        )
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

    /// Rounds the gap length, not individual cell edges. A single uniform
    /// pitch is required by grid transitions, so some edges remain fractional.
    private static func integralPixelItemSpacing(
        displayScale: CGFloat
    ) -> CGFloat {
        guard displayScale.isFinite, displayScale > 0 else {
            return itemSpacing
        }
        let pixelSpacing = itemSpacing * displayScale
        guard pixelSpacing.isFinite else { return itemSpacing }
        return max(pixelSpacing.rounded(), 1) / displayScale
    }
}

nonisolated struct MobilePlayerBrowserVisualLayoutGeometry: Sendable {
    let layout: MobilePlayerBrowserLayout
    let mirrorsHorizontally: Bool

    func itemFrame(at itemIndex: Int) -> CGRect? {
        guard let frame = layout.itemFrame(at: itemIndex) else { return nil }
        guard mirrorsHorizontally else { return frame }
        return CGRect(
            x: layout.contentSize.width - frame.maxX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }

    func itemIndex(at point: CGPoint) -> Int? {
        layout.itemIndex(at: mirroredPoint(point))
    }

    /// Grid-transition endpoint mapping's seam tolerance: one spacing of
    /// drift plus a point of rounding.
    func nearestItemIndex(to point: CGPoint) -> Int? {
        nearestItemIndex(
            to: point,
            tolerance: layout.interItemSpacing + 1
        )
    }

    func nearestItemIndex(
        to point: CGPoint,
        tolerance: CGFloat
    ) -> Int? {
        layout.nearestItemIndex(
            to: mirroredPoint(point),
            tolerance: tolerance
        )
    }

    /// Converts between the layout's model space and the mirrored space the
    /// views are drawn in. The mirror is its own inverse, so this maps either
    /// way.
    func mirroredPoint(_ point: CGPoint) -> CGPoint {
        guard mirrorsHorizontally else { return point }
        return CGPoint(
            x: layout.contentSize.width - point.x,
            y: point.y
        )
    }
}

nonisolated struct MobilePlayerBrowserGridTransition: Sendable {
    let fromLayout: MobilePlayerBrowserLayout
    let toLayout: MobilePlayerBrowserLayout

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
    }

    var itemWidthRatio: CGFloat {
        toLayout.itemWidth / fromLayout.itemWidth
    }

    /// Lattice pitch ratios. Inter-item spacing does not scale with the item
    /// width across grid modes, so the ratio the plane must LAND on — for
    /// seams to line up exactly at commit — is the pitch ratio per axis, not
    /// the item-width ratio. On a uniform lattice the two differ by well under
    /// a percent; the per-cell content crossfade absorbs that.
    var columnPitchRatio: CGFloat {
        let fromPitch = fromLayout.itemWidth + fromLayout.interItemSpacing
        let toPitch = toLayout.itemWidth + toLayout.interItemSpacing
        guard fromPitch > 0, toPitch > 0 else { return itemWidthRatio }
        return toPitch / fromPitch
    }

    /// Variable-aspect collections have no single row pitch: a row's height is
    /// the maximum ratio over that row, and the two modes group different items
    /// into a row, so a sampled pitch is not the lattice pitch. Scale the plane
    /// isotropically there rather than on an unrepresentative ratio.
    var rowPitchRatio: CGFloat {
        guard let fromPitch = Self.rowPitch(of: fromLayout),
              let toPitch = Self.rowPitch(of: toLayout) else {
            return itemWidthRatio
        }
        return toPitch / fromPitch
    }

    /// The horizontal fixed point of a boundary-preserving column transform,
    /// nearest to the pinch. The only affine maps that carry every source
    /// column boundary onto a destination column boundary for the whole
    /// transition are `x' = r·x + m·p_dest` for integer column shifts `m`;
    /// their fixed points `m·p_dest / (1 − r)` quantize to roughly the left
    /// edge, center, and right edge of the viewport. Photos scales about the
    /// one nearest the fingers (measured: a left-edge pinch keeps seam
    /// positions at exact multiples of the growing pitch from x = 0), which
    /// is what keeps seams from widening and columns from sliding in from
    /// the screen edges.
    static func boundaryPreservingPivotX(
        anchorX: CGFloat,
        columnPitchRatio: CGFloat,
        destinationColumnPitch: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        guard anchorX.isFinite,
              columnPitchRatio.isFinite,
              destinationColumnPitch.isFinite,
              destinationColumnPitch > 0,
              viewportWidth.isFinite,
              viewportWidth >= 0,
              abs(1 - columnPitchRatio) > 0.000_1 else {
            return anchorX.isFinite ? anchorX : 0
        }
        let fixedPointSpacing = destinationColumnPitch
            / (1 - columnPitchRatio)
        let boundedAnchorX = min(max(anchorX, 0), viewportWidth)
        let nearestShift = (boundedAnchorX / fixedPointSpacing).rounded()
        let pivotX = nearestShift * fixedPointSpacing
        guard pivotX.isFinite else { return anchorX }
        return pivotX
    }

    /// The integer lattice shift a pinned transition applies to item
    /// coordinates: destination column = source column + `columns`,
    /// destination row = source row + `rows`. Photos assigns transition
    /// content by exactly this shift — a bijection on the visible cells —
    /// never by proximity, which aliases two neighbors onto one item at the
    /// lattice edges. `mappedLogicalCenterOfItemZero` is item 0's frame
    /// center pushed through the pinned lattice map (and un-mirrored back
    /// into logical layout space). A mapped center that lands away from
    /// every destination item center means the lattices are not pinned
    /// boundary-to-boundary, and the arithmetic shift would be coherent but
    /// wrong — callers fall back to per-cell matching there.
    static func latticeItemShift(
        fromLayout: MobilePlayerBrowserLayout,
        toLayout: MobilePlayerBrowserLayout,
        mappedLogicalCenterOfItemZero point: CGPoint
    ) -> (columns: Int, rows: Int)? {
        guard fromLayout.uniformItemSize != nil,
              let toItemSize = toLayout.uniformItemSize,
              fromLayout.itemCount > fromLayout.columnCount,
              toLayout.itemCount > toLayout.columnCount,
              let referenceFrame = toLayout.itemFrame(at: 0),
              point.x.isFinite,
              point.y.isFinite else {
            return nil
        }
        let columnPitch = toItemSize.width + toLayout.interItemSpacing
        let rowPitch = toItemSize.height + toLayout.interItemSpacing
        guard columnPitch > 0, rowPitch > 0 else { return nil }
        let columnOffset = (point.x - referenceFrame.midX) / columnPitch
        let rowOffset = (point.y - referenceFrame.midY) / rowPitch
        let columns = columnOffset.rounded()
        let rows = rowOffset.rounded()
        guard abs(columnOffset - columns) < 0.35,
              abs(rowOffset - rows) < 0.35,
              let columnShift = Int(exactly: columns),
              let rowShift = Int(exactly: rows) else {
            return nil
        }
        return (columnShift, rowShift)
    }

    /// Pins the two lattices together at the anchor item while capturing their
    /// pitch ratios once for endpoint mapping.
    func latticeMap(
        fromAnchorContentPoint: CGPoint,
        toAnchorContentPoint: CGPoint
    ) -> MobilePlayerBrowserGridLatticeMap {
        MobilePlayerBrowserGridLatticeMap(
            columnPitchRatio: columnPitchRatio,
            rowPitchRatio: rowPitchRatio,
            fromAnchorContentPoint: fromAnchorContentPoint,
            toAnchorContentPoint: toAnchorContentPoint
        )
    }

    private static func rowPitch(
        of layout: MobilePlayerBrowserLayout
    ) -> CGFloat? {
        guard layout.itemCount > layout.columnCount,
              let itemSize = layout.uniformItemSize else {
            return nil
        }
        let pitch = itemSize.height + layout.interItemSpacing
        return pitch.isFinite && pitch > 0 ? pitch : nil
    }

    static func anchorRelativeX(
        contentX: CGFloat,
        itemFrame: CGRect
    ) -> CGFloat {
        anchorRelative(
            coordinate: contentX,
            origin: itemFrame.minX,
            extent: itemFrame.width
        )
    }

    static func anchorX(
        itemFrame: CGRect,
        relativeX: CGFloat
    ) -> CGFloat {
        anchor(
            origin: itemFrame.minX,
            extent: itemFrame.width,
            center: itemFrame.midX,
            relative: relativeX
        )
    }

    static func anchorRelativeY(
        contentY: CGFloat,
        itemFrame: CGRect
    ) -> CGFloat {
        anchorRelative(
            coordinate: contentY,
            origin: itemFrame.minY,
            extent: itemFrame.height
        )
    }

    static func anchorY(
        itemFrame: CGRect,
        relativeY: CGFloat
    ) -> CGFloat {
        anchor(
            origin: itemFrame.minY,
            extent: itemFrame.height,
            center: itemFrame.midY,
            relative: relativeY
        )
    }

    private static func anchorRelative(
        coordinate: CGFloat,
        origin: CGFloat,
        extent: CGFloat
    ) -> CGFloat {
        guard coordinate.isFinite,
              origin.isFinite,
              extent.isFinite,
              extent > 0 else {
            return 0.5
        }
        return min(max((coordinate - origin) / extent, 0), 1)
    }

    private static func anchor(
        origin: CGFloat,
        extent: CGFloat,
        center: CGFloat,
        relative: CGFloat
    ) -> CGFloat {
        guard origin.isFinite, extent.isFinite, extent > 0 else {
            return center.isFinite ? center : 0
        }
        let sanitizedRelative = relative.isFinite
            ? min(max(relative, 0), 1)
            : 0.5
        return origin + extent * sanitizedRelative
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
}

/// The correspondence between a grid transition's source and destination
/// lattices in content space, pinned at the anchor item. Every endpoint
/// mapping the transition needs — which destination item a live cell becomes,
/// where a phantom for a destination item sits in source space, which source
/// item supplies carryover art — is one of these three lookups.
nonisolated struct MobilePlayerBrowserGridLatticeMap: Equatable, Sendable {
    static let identity = MobilePlayerBrowserGridLatticeMap(
        columnPitchRatio: 1,
        rowPitchRatio: 1,
        fromAnchorContentPoint: .zero,
        toAnchorContentPoint: .zero
    )

    let columnPitchRatio: CGFloat
    let rowPitchRatio: CGFloat
    let fromAnchorContentPoint: CGPoint
    let toAnchorContentPoint: CGPoint

    func destinationPoint(fromSource point: CGPoint) -> CGPoint {
        CGPoint(
            x: toAnchorContentPoint.x
                + (point.x - fromAnchorContentPoint.x) * columnPitchRatio,
            y: toAnchorContentPoint.y
                + (point.y - fromAnchorContentPoint.y) * rowPitchRatio
        )
    }

    func sourcePoint(fromDestination point: CGPoint) -> CGPoint {
        CGPoint(
            x: fromAnchorContentPoint.x
                + (point.x - toAnchorContentPoint.x) / columnPitchRatio,
            y: fromAnchorContentPoint.y
                + (point.y - toAnchorContentPoint.y) / rowPitchRatio
        )
    }

    func sourceRect(fromDestination rect: CGRect) -> CGRect {
        CGRect(
            origin: sourcePoint(fromDestination: rect.origin),
            size: CGSize(
                width: rect.width / columnPitchRatio,
                height: rect.height / rowPitchRatio
            )
        )
    }
}
