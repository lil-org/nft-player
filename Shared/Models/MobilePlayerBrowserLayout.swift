// ∅ 2026 lil org

import CoreGraphics

struct MobilePlayerBrowserLayout: Equatable {
    static let columnCount = 3
    static let itemSpacing: CGFloat = 1
    static let maximumAspectSampleCount = 15
    static let maximumPrefetchStride = 15

    let itemSize: CGSize
    let visibleRowCount: Int
    let prefetchStride: Int

    static func retainedFocusTokenIndex(
        geometryChanged: Bool,
        forcedTokenIndex: Int?,
        focusedTokenIndex: Int?
    ) -> Int? {
        guard geometryChanged else { return nil }
        return forcedTokenIndex ?? focusedTokenIndex
    }

    init?(
        viewportSize: CGSize,
        topContentInset: CGFloat = 0,
        bottomContentInset: CGFloat = 0,
        sampledImageSizes: [CGSize]
    ) {
        guard viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > Self.itemSpacing * CGFloat(Self.columnCount - 1),
              viewportSize.height > 0 else {
            return nil
        }

        let horizontalSpacing = Self.itemSpacing * CGFloat(Self.columnCount - 1)
        let itemWidth = (viewportSize.width - horizontalSpacing) / CGFloat(Self.columnCount)
        let sampledAspectRatios = sampledImageSizes.compactMap { size -> CGFloat? in
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }
            return size.height / size.width
        }
        let rowAspectRatio = sampledAspectRatios.max() ?? 1
        let itemHeight = itemWidth * rowAspectRatio
        let sanitizedTopInset = topContentInset.isFinite ? max(topContentInset, 0) : 0
        let sanitizedBottomInset = bottomContentInset.isFinite ? max(bottomContentInset, 0) : 0
        let visibleHeight = max(
            viewportSize.height - sanitizedTopInset - sanitizedBottomInset,
            0
        )
        let rowTravel = itemHeight + Self.itemSpacing
        let visibleRowCount = max(
            Int(ceil((visibleHeight + Self.itemSpacing) / rowTravel)),
            1
        )

        self.itemSize = CGSize(width: itemWidth, height: itemHeight)
        self.visibleRowCount = visibleRowCount
        self.prefetchStride = min(
            visibleRowCount * Self.columnCount,
            Self.maximumPrefetchStride
        )
    }
}
