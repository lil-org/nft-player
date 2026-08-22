// ∅ 2026 lil org

import CoreGraphics
import Foundation

nonisolated struct PlayerBrowserGridCrossfadePlane: Equatable, Sendable {
    let scaleX: CGFloat
    let scaleY: CGFloat
    let translation: CGPoint
    let outgoingContentOffsetY: CGFloat
    let incomingContentOffsetY: CGFloat
}

nonisolated struct PlayerBrowserGridPhantomCandidate: Equatable, Sendable {
    let destinationItemIndex: Int
    let sourceFrame: CGRect
    let destinationFrame: CGRect
}

nonisolated struct PlayerBrowserGridRepeatedPhantomRows: Equatable, Sendable {
    let firstRowFrames: [CGRect]
    let rowCount: Int
    let rowPitch: CGFloat
    let finalRowFrames: [CGRect]
    let excludedFrames: [CGRect]

    var coverageBounds: CGRect? {
        var frames = finalRowFrames
        if rowCount > 0 {
            frames += firstRowFrames
            if rowCount > 1 {
                let finalOffsetY = CGFloat(rowCount - 1) * rowPitch
                frames += firstRowFrames.map {
                    $0.offsetBy(dx: 0, dy: finalOffsetY)
                }
            }
        }
        guard let firstFrame = frames.first else { return nil }
        return frames.dropFirst().reduce(firstFrame) { $0.union($1) }
    }
}

nonisolated struct PlayerBrowserGridSolidPhantomCoverage: Equatable, Sendable {
    let frame: CGRect
    let excludedFrames: [CGRect]
}

nonisolated enum PlayerBrowserGridPhantomShapeCoverage: Equatable, Sendable {
    case repeatedRows(PlayerBrowserGridRepeatedPhantomRows)
    case solid(PlayerBrowserGridSolidPhantomCoverage)

    var coverageBounds: CGRect? {
        switch self {
        case let .repeatedRows(rows):
            return rows.coverageBounds
        case let .solid(coverage):
            return coverage.frame
        }
    }

    var excludedFrames: [CGRect] {
        switch self {
        case let .repeatedRows(rows):
            return rows.excludedFrames
        case let .solid(coverage):
            return coverage.excludedFrames
        }
    }

    func replacingExcludedFrames(_ excludedFrames: [CGRect]) -> Self {
        switch self {
        case let .repeatedRows(rows):
            return .repeatedRows(PlayerBrowserGridRepeatedPhantomRows(
                firstRowFrames: rows.firstRowFrames,
                rowCount: rows.rowCount,
                rowPitch: rows.rowPitch,
                finalRowFrames: rows.finalRowFrames,
                excludedFrames: excludedFrames
            ))
        case let .solid(coverage):
            return .solid(PlayerBrowserGridSolidPhantomCoverage(
                frame: coverage.frame,
                excludedFrames: excludedFrames
            ))
        }
    }
}

nonisolated private func playerBrowserGridItemPrecedes(
    _ lhs: Int,
    _ rhs: Int,
    anchor: Int
) -> Bool {
    let lhsDistance = lhs >= anchor ? lhs - anchor : anchor - lhs
    let rhsDistance = rhs >= anchor ? rhs - anchor : anchor - rhs
    if lhsDistance == rhsDistance {
        return lhs < rhs
    }
    return lhsDistance < rhsDistance
}

nonisolated private func playerBrowserGridPrioritizedItemIndices(
    candidateItemIndices: [Int],
    anchorItemIndex: Int?,
    maximumCount: Int
) -> [Int] {
    let candidates = Set(candidateItemIndices.filter { $0 >= 0 }).sorted()
    guard maximumCount > 0, !candidates.isEmpty else { return [] }
    let anchor = anchorItemIndex.flatMap { $0 >= 0 ? $0 : nil }
        ?? candidates[candidates.count / 2]
    return Array(candidates.sorted { lhs, rhs in
        playerBrowserGridItemPrecedes(lhs, rhs, anchor: anchor)
    }.prefix(maximumCount))
}

nonisolated struct PlayerBrowserGridDetailPlan: Equatable, Sendable {
    let itemIndices: [Int]

    init(
        candidateItemIndices: [Int],
        anchorItemIndex: Int?,
        maximumCount: Int
    ) {
        itemIndices = playerBrowserGridPrioritizedItemIndices(
            candidateItemIndices: candidateItemIndices,
            anchorItemIndex: anchorItemIndex,
            maximumCount: maximumCount
        ).sorted()
    }
}

nonisolated enum PlayerBrowserGridRenderBudget: Sendable {
    static let maximumVisualCellCount = 120
    static let maximumCarryoverSourceCount = maximumVisualCellCount * 2
}

nonisolated struct PlayerBrowserGridCarryoverSource<Content> {
    let destinationItem: Int?
    let viewportRect: CGRect
    let content: Content?

    init(
        destinationItem: Int? = nil,
        viewportRect: CGRect,
        content: Content?
    ) {
        self.destinationItem = destinationItem
        self.viewportRect = viewportRect
        self.content = content
    }
}

extension PlayerBrowserGridCarryoverSource: Sendable where Content: Sendable {}

nonisolated enum PlayerBrowserGridGeometry: Sendable {
    static func visibleRect(
        _ rect: CGRect,
        clippedTo viewportRect: CGRect
    ) -> CGRect? {
        guard isValid(rect), isValid(viewportRect) else { return nil }
        let visibleRect = rect.intersection(viewportRect)
        guard isValid(visibleRect) else {
            return nil
        }
        return visibleRect
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull
            && !rect.isEmpty
            && rect.minX.isFinite
            && rect.minY.isFinite
            && rect.maxX.isFinite
            && rect.maxY.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
    }
}

nonisolated enum PlayerBrowserGridCarryoverSelection: Sendable {
    static func selectedItemIndices(
        candidateItemIndices: [Int],
        anchorItemIndex: Int?
    ) -> Set<Int> {
        Set(PlayerBrowserGridDetailPlan(
            candidateItemIndices: candidateItemIndices,
            anchorItemIndex: anchorItemIndex,
            maximumCount: PlayerBrowserGridRenderBudget.maximumVisualCellCount
        ).itemIndices)
    }

    static func prioritizedItemIndices(
        candidateItemIndices: [Int],
        anchorItemIndex: Int?
    ) -> [Int] {
        playerBrowserGridPrioritizedItemIndices(
            candidateItemIndices: candidateItemIndices,
            anchorItemIndex: anchorItemIndex,
            maximumCount:
                PlayerBrowserGridRenderBudget.maximumVisualCellCount
        )
    }

    static func bestSource<Content>(
        for destinationRect: CGRect,
        among sources: [PlayerBrowserGridCarryoverSource<Content>]
    ) -> PlayerBrowserGridCarryoverSource<Content>? {
        bestSource(
            for: destinationRect,
            among: sources,
            maximumCount:
                PlayerBrowserGridRenderBudget.maximumCarryoverSourceCount,
            sourceRect: \.viewportRect
        )
    }

    static func bestSource<Source>(
        for destinationRect: CGRect,
        among sources: [Source],
        maximumCount: Int,
        sourceRect: (Source) -> CGRect
    ) -> Source? {
        guard maximumCount > 0,
              !destinationRect.isNull,
              !destinationRect.isEmpty else {
            return nil
        }
        let destinationArea = destinationRect.width * destinationRect.height
        guard destinationArea.isFinite, destinationArea > 0 else { return nil }

        var bestSource: Source?
        var bestOverlap: CGFloat = 0
        for source in sources.prefix(maximumCount) {
            let overlap = sourceRect(source).intersection(destinationRect)
            guard !overlap.isNull else { continue }
            let overlapArea = overlap.width * overlap.height
            if overlapArea > bestOverlap {
                bestOverlap = overlapArea
                bestSource = source
            }
        }
        return bestOverlap > destinationArea / 2 ? bestSource : nil
    }
}

nonisolated struct PlayerBrowserGridPhantomPlan: Equatable, Sendable {
    let cellCandidates: [PlayerBrowserGridPhantomCandidate]
    let shapeCandidates: [PlayerBrowserGridPhantomCandidate]
    let shapeCoverage: PlayerBrowserGridPhantomShapeCoverage?

    static let renderingComplexityLimit = 512
    static let repeatedRowInstanceLimit = 512
    private static let repeatedShapeCandidateThreshold =
        renderingComplexityLimit
    private static let repeatedShapeExclusionLimit =
        renderingComplexityLimit

    private struct PlanningContext: Sendable {
        let destinationGeometry: MobilePlayerBrowserVisualLayoutGeometry
        let latticeMap: MobilePlayerBrowserGridLatticeMap
        let coverageRect: CGRect
        let candidateIndices: Range<Int>
        let coveredDestinationItems: Set<Int>
    }

    init(
        destinationGeometry: MobilePlayerBrowserVisualLayoutGeometry,
        latticeMap: MobilePlayerBrowserGridLatticeMap,
        coverageRect: CGRect,
        priorityRect: CGRect,
        coveredDestinationItems: Set<Int>,
        maximumCellCount: Int
    ) {
        let context = PlanningContext(
            destinationGeometry: destinationGeometry,
            latticeMap: latticeMap,
            coverageRect: coverageRect,
            candidateIndices: destinationGeometry.layout.candidateItemIndices(
                intersecting: coverageRect
            ),
            coveredDestinationItems: coveredDestinationItems
        )
        let maximumCellCount = max(maximumCellCount, 0)
        let exceedsExplicitShapeLimit =
            Self.hasMoreThanRepeatedShapeThresholdUncoveredItems(
                context: context
            )
        if exceedsExplicitShapeLimit {
            let cellCandidates = Self.boundedCellCandidates(
                context: context,
                priorityRect: priorityRect,
                maximumCellCount: maximumCellCount
            )
            self.cellCandidates = cellCandidates
            shapeCandidates = []
            if let repeatedRows = Self.repeatedShapeRows(context: context),
               repeatedRows.rowCount <= Self.repeatedRowInstanceLimit {
                shapeCoverage = .repeatedRows(
                    PlayerBrowserGridRepeatedPhantomRows(
                        firstRowFrames: repeatedRows.firstRowFrames,
                        rowCount: repeatedRows.rowCount,
                        rowPitch: repeatedRows.rowPitch,
                        finalRowFrames: repeatedRows.finalRowFrames,
                        excludedFrames: repeatedRows.excludedFrames
                            + cellCandidates.map(\.sourceFrame)
                    )
                )
            } else {
                shapeCoverage = Self.solidShapeCoverage(
                    context: context,
                    excludedFrames: cellCandidates.map(\.sourceFrame)
                )
            }
            return
        }

        var candidates = [PlayerBrowserGridPhantomCandidate]()
        for itemIndex in context.candidateIndices {
            if let candidate = Self.candidate(
                at: itemIndex,
                context: context
            ) {
                candidates.append(candidate)
            }
        }

        let cellCandidates = Self.prioritizedCellCandidates(
            candidates,
            priorityRect: priorityRect,
            maximumCellCount: maximumCellCount
        )
        self.cellCandidates = cellCandidates
        let cellItemIndices = Set(
            cellCandidates.map(\.destinationItemIndex)
        )
        shapeCandidates = candidates.filter {
            !cellItemIndices.contains($0.destinationItemIndex)
        }
        shapeCoverage = nil
    }

    private static func boundedCellCandidates(
        context: PlanningContext,
        priorityRect: CGRect,
        maximumCellCount: Int
    ) -> [PlayerBrowserGridPhantomCandidate] {
        guard maximumCellCount > 0 else { return [] }
        let candidateCount = maximumCellCount.addingReportingOverflow(
            Self.repeatedShapeCandidateThreshold
        )
        let candidates = Self.boundedCandidates(
            context: context,
            priorityRect: priorityRect,
            maximumCount: candidateCount.overflow
                ? Int.max
                : candidateCount.partialValue
        )
        return Self.prioritizedCellCandidates(
            candidates,
            priorityRect: priorityRect,
            maximumCellCount: maximumCellCount
        )
    }

    private static func hasMoreThanRepeatedShapeThresholdUncoveredItems(
        context: PlanningContext
    ) -> Bool {
        if context.candidateIndices.count - min(
            context.coveredDestinationItems.count,
            context.candidateIndices.count
        ) > repeatedShapeCandidateThreshold {
            return true
        }
        var uncoveredCount = 0
        for itemIndex in context.candidateIndices where
            !context.coveredDestinationItems.contains(itemIndex) {
            guard let frame = context.destinationGeometry.itemFrame(
                at: itemIndex
            ), context.coverageRect.intersects(frame) else {
                continue
            }
            uncoveredCount += 1
            if uncoveredCount > repeatedShapeCandidateThreshold {
                return true
            }
        }
        return false
    }

    private static func prioritizedCellCandidates<Candidates: Sequence>(
        _ candidates: Candidates,
        priorityRect: CGRect,
        maximumCellCount: Int
    ) -> [PlayerBrowserGridPhantomCandidate] where
        Candidates.Element == PlayerBrowserGridPhantomCandidate {
        guard maximumCellCount > 0 else { return [] }
        var prioritized = [PlayerBrowserGridPhantomCandidate]()
        var marginCandidates = [PlayerBrowserGridPhantomCandidate]()
        for candidate in candidates {
            if priorityRect.intersects(candidate.destinationFrame) {
                prioritized.append(candidate)
            } else {
                marginCandidates.append(candidate)
            }
        }
        prioritized.sort { lhs, rhs in
            let lhsDistance = abs(lhs.destinationFrame.midY - priorityRect.midY)
            let rhsDistance = abs(rhs.destinationFrame.midY - priorityRect.midY)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs.destinationItemIndex < rhs.destinationItemIndex
        }
        if prioritized.count >= maximumCellCount {
            return Array(prioritized.prefix(maximumCellCount))
        }
        marginCandidates.sort { lhs, rhs in
            let lhsDistance = abs(lhs.destinationFrame.midY - priorityRect.midY)
            let rhsDistance = abs(rhs.destinationFrame.midY - priorityRect.midY)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs.destinationItemIndex < rhs.destinationItemIndex
        }
        prioritized.append(contentsOf: marginCandidates.prefix(
            maximumCellCount - prioritized.count
        ))
        return prioritized
    }

    private static func boundedCandidates(
        context: PlanningContext,
        priorityRect: CGRect,
        maximumCount: Int
    ) -> [PlayerBrowserGridPhantomCandidate] {
        guard maximumCount > 0, !context.candidateIndices.isEmpty else {
            return []
        }
        let priorityIndices = context.destinationGeometry.layout
            .candidateItemIndices(intersecting: priorityRect)
        let priorityLowerBound = max(
            priorityIndices.lowerBound,
            context.candidateIndices.lowerBound
        )
        let priorityUpperBound = min(
            priorityIndices.upperBound,
            context.candidateIndices.upperBound
        )
        let anchorIndex: Int
        if priorityLowerBound < priorityUpperBound {
            anchorIndex = priorityLowerBound
                + (priorityUpperBound - priorityLowerBound) / 2
        } else {
            anchorIndex = context.candidateIndices.lowerBound
                + context.candidateIndices.count / 2
        }
        let candidateCount = min(
            maximumCount,
            context.candidateIndices.count
        )
        var lowerBound = anchorIndex - min(
            anchorIndex - context.candidateIndices.lowerBound,
            candidateCount / 2
        )
        if context.candidateIndices.upperBound - lowerBound < candidateCount {
            lowerBound = context.candidateIndices.upperBound - candidateCount
        }
        return (lowerBound..<(lowerBound + candidateCount)).compactMap {
            candidate(at: $0, context: context)
        }
    }

    private static func solidShapeCoverage(
        context: PlanningContext,
        excludedFrames: [CGRect]
    ) -> PlayerBrowserGridPhantomShapeCoverage? {
        let contentRect = CGRect(
            origin: .zero,
            size: context.destinationGeometry.layout.contentSize
        )
        let destinationFrame = context.coverageRect.intersection(contentRect)
        guard let sourceFrame = validSourceFrame(
            destinationFrame,
            context: context
        ) else {
            return nil
        }
        return .solid(
            PlayerBrowserGridSolidPhantomCoverage(
                frame: sourceFrame,
                excludedFrames: repeatedShapeExclusionFrames(context: context)
                    + excludedFrames
            )
        )
    }

    private static func candidate(
        at itemIndex: Int,
        context: PlanningContext
    ) -> PlayerBrowserGridPhantomCandidate? {
        guard !context.coveredDestinationItems.contains(itemIndex),
              let frames = mappedFrames(
                  at: itemIndex,
                  context: context
              ) else {
            return nil
        }
        return PlayerBrowserGridPhantomCandidate(
            destinationItemIndex: itemIndex,
            sourceFrame: frames.source,
            destinationFrame: frames.destination
        )
    }

    private static func repeatedShapeRows(
        context: PlanningContext
    ) -> PlayerBrowserGridRepeatedPhantomRows? {
        let layout = context.destinationGeometry.layout
        guard let itemSize = layout.uniformItemSize,
              context.latticeMap.rowPitchRatio.isFinite,
              context.latticeMap.rowPitchRatio > 0,
              !context.candidateIndices.isEmpty else {
            return nil
        }
        var firstRow = context.candidateIndices.lowerBound / layout.columnCount
        var lastRow = (context.candidateIndices.upperBound - 1)
            / layout.columnCount
        while firstRow <= lastRow,
              !rowIntersectsCoverage(
                  firstRow,
                  context: context
              ) {
            firstRow += 1
        }
        while lastRow >= firstRow,
              !rowIntersectsCoverage(
                  lastRow,
                  context: context
              ) {
            lastRow -= 1
        }
        guard firstRow <= lastRow else { return nil }

        let fullRowCount = layout.itemCount / layout.columnCount
        let firstFullRow = firstRow < fullRowCount ? firstRow : nil
        let lastFullRow = min(lastRow, fullRowCount - 1)
        let repeatedRowCount = firstFullRow.map {
            max(lastFullRow - $0 + 1, 0)
        } ?? 0
        let firstRowFrames = firstFullRow.map { rowIndex in
            sourceFrames(
                in: rowIndex,
                context: context
            )
        } ?? []

        let partialRowIndex = fullRowCount
        let hasPartialRow = layout.itemCount % layout.columnCount != 0
            && (firstRow...lastRow).contains(partialRowIndex)
        let finalRowFrames = hasPartialRow
            ? sourceFrames(
                in: partialRowIndex,
                context: context
            )
            : []
        guard !firstRowFrames.isEmpty || !finalRowFrames.isEmpty else {
            return nil
        }
        let rowPitch = (itemSize.height + layout.interItemSpacing)
            / context.latticeMap.rowPitchRatio
        guard rowPitch.isFinite, rowPitch > 0 else { return nil }
        return PlayerBrowserGridRepeatedPhantomRows(
            firstRowFrames: firstRowFrames,
            rowCount: repeatedRowCount,
            rowPitch: rowPitch,
            finalRowFrames: finalRowFrames,
            excludedFrames: repeatedShapeExclusionFrames(
                context: context
            )
        )
    }

    private static func repeatedShapeExclusionFrames(
        context: PlanningContext
    ) -> [CGRect] {
        var frames = [CGRect]()
        frames.reserveCapacity(min(
            context.coveredDestinationItems.count,
            repeatedShapeExclusionLimit
        ))
        let coveredCandidateIndices = context.coveredDestinationItems
            .filter { context.candidateIndices.contains($0) }
            .sorted()
        for itemIndex in coveredCandidateIndices {
            guard let mappedFrames = mappedFrames(
                at: itemIndex,
                context: context
            ) else {
                continue
            }
            frames.append(mappedFrames.source)
            if frames.count == repeatedShapeExclusionLimit {
                break
            }
        }
        return frames
    }

    private static func rowIntersectsCoverage(
        _ rowIndex: Int,
        context: PlanningContext
    ) -> Bool {
        context.destinationGeometry.layout.itemIndices(
            inRow: rowIndex
        ).contains { itemIndex in
            context.destinationGeometry.itemFrame(at: itemIndex).map {
                context.coverageRect.intersects($0)
            } == true
        }
    }

    private static func sourceFrames(
        in rowIndex: Int,
        context: PlanningContext
    ) -> [CGRect] {
        context.destinationGeometry.layout.itemIndices(
            inRow: rowIndex
        ).compactMap { itemIndex in
            mappedFrames(at: itemIndex, context: context)?.source
        }
    }

    private static func mappedFrames(
        at itemIndex: Int,
        context: PlanningContext
    ) -> (source: CGRect, destination: CGRect)? {
        guard let destination = context.destinationGeometry.itemFrame(
            at: itemIndex
        ), context.coverageRect.intersects(destination),
              let source = validSourceFrame(
                  destination,
                  context: context
              ) else {
            return nil
        }
        return (source, destination)
    }

    private static func validSourceFrame(
        _ destinationFrame: CGRect,
        context: PlanningContext
    ) -> CGRect? {
        let sourceFrame = context.latticeMap.sourceRect(
            fromDestination: destinationFrame
        )
        guard sourceFrame.minX.isFinite,
              sourceFrame.minY.isFinite,
              sourceFrame.maxX.isFinite,
              sourceFrame.maxY.isFinite,
              sourceFrame.width.isFinite,
              sourceFrame.width > 0,
              sourceFrame.height.isFinite,
              sourceFrame.height > 0 else {
            return nil
        }
        return sourceFrame
    }
}

nonisolated struct PlayerBrowserGridPhantomCoverage: Equatable, Sendable {
    private(set) var installedRect: CGRect?

    mutating func replacementRect(
        requiredRect: CGRect,
        buffer: CGSize
    ) -> CGRect? {
        guard requiredRect.minX.isFinite,
              requiredRect.minY.isFinite,
              requiredRect.maxX.isFinite,
              requiredRect.maxY.isFinite,
              requiredRect.width > 0,
              requiredRect.height > 0 else {
            return nil
        }
        guard installedRect?.contains(requiredRect) != true else { return nil }
        let horizontalBuffer = buffer.width.isFinite
            ? max(buffer.width, 0)
            : 0
        let verticalBuffer = buffer.height.isFinite
            ? max(buffer.height, 0)
            : 0
        let replacement = requiredRect.insetBy(
            dx: -horizontalBuffer,
            dy: -verticalBuffer
        )
        guard replacement.minX.isFinite,
              replacement.minY.isFinite,
              replacement.maxX.isFinite,
              replacement.maxY.isFinite else {
            return nil
        }
        installedRect = replacement
        return replacement
    }

    mutating func reset() {
        installedRect = nil
    }
}

/// Carries the plane's pre-install transform across a mid-gesture plane swap:
/// the leftover difference is ramped back in and out around the installation
/// point so neither the swap frame nor the terminal frame jumps.
///
/// An `installationProgress` of 0 means the ramp has no room to run in — the
/// clock it is driven by already sits at the install point — so the leftover
/// simply decays from full to nothing as that clock travels to 1.
nonisolated struct PlayerBrowserGridCrossfadePlaneRebase: Equatable, Sendable {
    let installationProgress: CGFloat
    let delta: CGAffineTransform

    init?(
        currentTransform: CGAffineTransform,
        baseTransform: CGAffineTransform,
        installationProgress: CGFloat
    ) {
        guard installationProgress >= 0,
              installationProgress < 1,
              currentTransform != baseTransform else {
            return nil
        }
        self.installationProgress = installationProgress
        delta = CGAffineTransform(
            a: currentTransform.a - baseTransform.a,
            b: currentTransform.b - baseTransform.b,
            c: currentTransform.c - baseTransform.c,
            d: currentTransform.d - baseTransform.d,
            tx: currentTransform.tx - baseTransform.tx,
            ty: currentTransform.ty - baseTransform.ty
        )
    }

    func applying(
        to transform: CGAffineTransform,
        progress: CGFloat
    ) -> CGAffineTransform {
        guard progress.isFinite else { return transform }
        let progress = PlayerBrowserGridCrossfade.sanitizedProgress(progress)
        let weight: CGFloat
        if installationProgress <= 0 {
            weight = 1 - progress
        } else if progress <= installationProgress {
            weight = progress / installationProgress
        } else {
            weight = (1 - progress) / (1 - installationProgress)
        }
        return CGAffineTransform(
            a: transform.a + delta.a * weight,
            b: transform.b + delta.b * weight,
            c: transform.c + delta.c * weight,
            d: transform.d + delta.d * weight,
            tx: transform.tx + delta.tx * weight,
            ty: transform.ty + delta.ty * weight
        )
    }

    static func endpointClockProgress(
        previousProgress: CGFloat,
        driftProgress: CGFloat,
        settleProgress: CGFloat
    ) -> CGFloat {
        let previousProgress = PlayerBrowserGridCrossfade.sanitizedProgress(
            previousProgress
        )
        let driftProgress = PlayerBrowserGridCrossfade.sanitizedProgress(
            driftProgress
        )
        let settleProgress = PlayerBrowserGridCrossfade.sanitizedProgress(
            settleProgress
        )
        return max(
            previousProgress,
            max(settleProgress, 1 - driftProgress)
        )
    }

    static func sourceEndpointClockProgress(
        previousProgress: CGFloat,
        scale: CGFloat,
        installationScale: CGFloat
    ) -> CGFloat {
        let previousProgress = PlayerBrowserGridCrossfade.sanitizedProgress(
            previousProgress
        )
        guard scale.isFinite,
              scale > 0,
              installationScale.isFinite,
              installationScale > 0 else {
            return previousProgress
        }
        let installationLogScale = log(installationScale)
        guard installationLogScale != 0 else { return 1 }
        let progress = PlayerBrowserGridCrossfade.sanitizedProgress(
            1 - log(scale) / installationLogScale
        )
        return max(previousProgress, progress)
    }
}

/// Scales one grid plane while its cell content crossfades to the destination
/// grid and its axes settle onto the destination lattice pitch.
nonisolated struct PlayerBrowserGridCrossfade: Equatable, Sendable {

    static let contentFadeStartSettleProgress: CGFloat = 0.25
    static let contentFadeEndSettleProgress: CGFloat = 0.85
    /// Rearm fires below the fade start, never at it, so presentation
    /// hovering at that threshold cannot alternate rearm and relock,
    /// churning image work every frame. 0.2 is the reversal depth the
    /// fade-reversal retry behavior is calibrated against.
    static let contentFadeRearmSettleProgress: CGFloat = 0.2

    let itemWidthRatio: CGFloat
    let terminalScaleX: CGFloat
    let terminalScaleY: CGFloat
    let outgoingAnchor: CGPoint
    let incomingAnchor: CGPoint
    let outgoingRestContentOffsetY: CGFloat
    let incomingRestContentOffsetY: CGFloat
    private let outgoingMaximumContentOffsetY: CGFloat
    private let incomingMaximumContentOffsetY: CGFloat
    private let viewportWidth: CGFloat

    private init(
        reanchoring crossfade: PlayerBrowserGridCrossfade,
        outgoingAnchor: CGPoint,
        incomingAnchor: CGPoint
    ) {
        itemWidthRatio = crossfade.itemWidthRatio
        terminalScaleX = crossfade.terminalScaleX
        terminalScaleY = crossfade.terminalScaleY
        self.outgoingAnchor = outgoingAnchor
        self.incomingAnchor = incomingAnchor
        outgoingRestContentOffsetY = crossfade.outgoingRestContentOffsetY
        incomingRestContentOffsetY = crossfade.incomingRestContentOffsetY
        outgoingMaximumContentOffsetY =
            crossfade.outgoingMaximumContentOffsetY
        incomingMaximumContentOffsetY =
            crossfade.incomingMaximumContentOffsetY
        viewportWidth = crossfade.viewportWidth
    }

    init?(
        itemWidthRatio: CGFloat,
        terminalScaleX: CGFloat,
        terminalScaleY: CGFloat,
        outgoingAnchor: CGPoint,
        incomingAnchor: CGPoint,
        outgoingContentOffsetY: CGFloat,
        incomingContentOffsetY: CGFloat,
        outgoingContentHeight: CGFloat,
        incomingContentHeight: CGFloat,
        viewportSize: CGSize
    ) {
        guard itemWidthRatio.isFinite,
              itemWidthRatio > 0,
              itemWidthRatio != 1,
              terminalScaleX.isFinite,
              terminalScaleX > 0,
              terminalScaleY.isFinite,
              terminalScaleY > 0,
              outgoingAnchor.x.isFinite,
              outgoingAnchor.y.isFinite,
              incomingAnchor.x.isFinite,
              incomingAnchor.y.isFinite,
              outgoingContentOffsetY.isFinite,
              incomingContentOffsetY.isFinite,
              outgoingContentHeight.isFinite,
              incomingContentHeight.isFinite,
              viewportSize.width.isFinite,
              viewportSize.width > 0,
              viewportSize.height.isFinite,
              viewportSize.height > 0 else {
            return nil
        }
        self.itemWidthRatio = itemWidthRatio
        viewportWidth = viewportSize.width
        self.terminalScaleX = terminalScaleX
        self.terminalScaleY = terminalScaleY
        self.outgoingAnchor = outgoingAnchor
        self.incomingAnchor = incomingAnchor
        outgoingMaximumContentOffsetY = max(
            outgoingContentHeight - viewportSize.height,
            0
        )
        incomingMaximumContentOffsetY = max(
            incomingContentHeight - viewportSize.height,
            0
        )
        outgoingRestContentOffsetY = Self.clamped(
            outgoingContentOffsetY,
            maximum: outgoingMaximumContentOffsetY
        )
        incomingRestContentOffsetY = Self.clamped(
            incomingContentOffsetY,
            maximum: incomingMaximumContentOffsetY
        )
    }

    func reanchored(outgoingAnchor: CGPoint) -> Self? {
        guard outgoingAnchor.x.isFinite, outgoingAnchor.y.isFinite else {
            return nil
        }
        let anchorDelta = CGPoint(
            x: outgoingAnchor.x - self.outgoingAnchor.x,
            y: outgoingAnchor.y - self.outgoingAnchor.y
        )
        let incomingAnchor = CGPoint(
            x: self.incomingAnchor.x + terminalScaleX * anchorDelta.x,
            y: self.incomingAnchor.y + terminalScaleY * anchorDelta.y
        )
        guard incomingAnchor.x.isFinite, incomingAnchor.y.isFinite else {
            return nil
        }
        return Self(
            reanchoring: self,
            outgoingAnchor: outgoingAnchor,
            incomingAnchor: incomingAnchor
        )
    }

    func outgoingPlane(
        scale: CGFloat,
        panDeltaY: CGFloat
    ) -> PlayerBrowserGridCrossfadePlane {
        let scale = Self.sanitizedScale(scale)
        let driftProgress = driftProgress(forScale: scale)
        let scaleX = scale * anisotropyFactor(
            terminalScale: terminalScaleX,
            driftProgress: driftProgress
        )
        let scaleY = scale * anisotropyFactor(
            terminalScale: terminalScaleY,
            driftProgress: driftProgress
        )
        let sourceSafePanDeltaY = Self.safePanDeltaY(
            restContentOffsetY: outgoingRestContentOffsetY,
            maximumContentOffsetY: outgoingMaximumContentOffsetY,
            scale: scaleY,
            panDeltaY: panDeltaY
        )
        let destinationSafePanDeltaY = Self.safePanDeltaY(
            restContentOffsetY: incomingRestContentOffsetY,
            maximumContentOffsetY: incomingMaximumContentOffsetY,
            scale: 1,
            panDeltaY: panDeltaY
        )
        let effectivePanDeltaY = sourceSafePanDeltaY
            + (destinationSafePanDeltaY - sourceSafePanDeltaY)
                * driftProgress
        let contentOffsetY = Self.clamped(
            outgoingRestContentOffsetY - effectivePanDeltaY / scaleY,
            maximum: outgoingMaximumContentOffsetY
        )
        let incomingContentOffsetY = Self.clamped(
            incomingRestContentOffsetY - effectivePanDeltaY,
            maximum: incomingMaximumContentOffsetY
        )
        let sourceRenderedPanDeltaY = (
            outgoingRestContentOffsetY - contentOffsetY
        ) * scaleY
        let translationPanDeltaY = effectivePanDeltaY
            - sourceRenderedPanDeltaY
        return PlayerBrowserGridCrossfadePlane(
            scaleX: scaleX,
            scaleY: scaleY,
            translation: CGPoint(
                x: coveringTranslationX(
                    (incomingAnchor.x - outgoingAnchor.x) * driftProgress,
                    scaleX: scaleX
                ),
                y: (incomingAnchor.y - outgoingAnchor.y) * driftProgress
                    + translationPanDeltaY
            ),
            outgoingContentOffsetY: contentOffsetY,
            incomingContentOffsetY: incomingContentOffsetY
        )
    }

    func transform(
        for plane: PlayerBrowserGridCrossfadePlane,
        viewCenter: CGPoint
    ) -> CGAffineTransform {
        Self.anchoredScaleTransform(
            scaleX: plane.scaleX,
            scaleY: plane.scaleY,
            anchor: outgoingAnchor,
            translation: CGPoint(
                x: plane.translation.x,
                y: plane.translation.y
                    + (outgoingRestContentOffsetY
                        - plane.outgoingContentOffsetY) * plane.scaleY
            ),
            viewCenter: viewCenter
        )
    }

    /// Clamps the anchored slide so painted content never leaves a viewport edge
    /// uncovered. The source grid spans `[A(1-s), A + s(W-A)]` on screen and the
    /// destination lattice, laid out about its own anchor, spans
    /// `[A - kI, A + k(W-I)]` for `k = s / terminalScaleX`; bounding on their
    /// union is exact at both endpoints, so the landing is unchanged. It holds
    /// at every scale in both directions — when neither span reaches across,
    /// `lower > upper` and the raw drift stands rather than being clamped to
    /// something arbitrary.
    private func coveringTranslationX(
        _ translationX: CGFloat,
        scaleX: CGFloat
    ) -> CGFloat {
        guard translationX.isFinite else { return 0 }
        guard scaleX.isFinite, scaleX > 0 else { return translationX }
        let anchorX = outgoingAnchor.x
        let k = scaleX / terminalScaleX
        let sourceLeft = anchorX * (1 - scaleX)
        let sourceRight = anchorX + scaleX * (viewportWidth - anchorX)
        let destinationLeft = anchorX - k * incomingAnchor.x
        let destinationRight = anchorX
            + k * (viewportWidth - incomingAnchor.x)
        let upper = -min(sourceLeft, destinationLeft)
        let lower = viewportWidth - max(sourceRight, destinationRight)
        guard lower <= upper else { return translationX }
        return min(max(translationX, lower), upper)
    }

    static func anchoredScaleTransform(
        scaleX: CGFloat,
        scaleY: CGFloat,
        anchor: CGPoint,
        translation: CGPoint,
        viewCenter: CGPoint
    ) -> CGAffineTransform {
        CGAffineTransform(
            translationX: translation.x
                + (1 - scaleX) * (anchor.x - viewCenter.x),
            y: translation.y
                + (1 - scaleY) * (anchor.y - viewCenter.y)
        ).scaledBy(x: scaleX, y: scaleY)
    }

    /// The pan a plane at `scale` can absorb without scrolling past a content
    /// edge, measured on screen: the request is converted to content space,
    /// clamped there, and converted back.
    static func safePanDeltaY(
        restContentOffsetY: CGFloat,
        maximumContentOffsetY: CGFloat,
        scale: CGFloat,
        panDeltaY: CGFloat
    ) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return 0 }
        let panContentDeltaY = panDeltaY.isFinite ? panDeltaY / scale : 0
        return (restContentOffsetY - clamped(
            restContentOffsetY - panContentDeltaY,
            maximum: maximumContentOffsetY
        )) * scale
    }

    func driftProgress(forScale scale: CGFloat) -> CGFloat {
        Self.driftProgress(forScale: scale, itemWidthRatio: itemWidthRatio)
    }

    static func driftProgress(
        forScale scale: CGFloat,
        itemWidthRatio: CGFloat
    ) -> CGFloat {
        let logRatio = log(itemWidthRatio)
        guard logRatio != 0 else { return 0 }
        return sanitizedProgress(log(sanitizedScale(scale)) / logRatio)
    }

    private func anisotropyFactor(
        terminalScale: CGFloat,
        driftProgress: CGFloat
    ) -> CGFloat {
        guard terminalScale != itemWidthRatio, driftProgress > 0 else {
            return 1
        }
        return pow(terminalScale / itemWidthRatio, driftProgress)
    }

    static func incomingContentAlpha(settleProgress: CGFloat) -> CGFloat {
        let settleProgress = sanitizedProgress(settleProgress)
        guard settleProgress > contentFadeStartSettleProgress else { return 0 }
        guard settleProgress < contentFadeEndSettleProgress else { return 1 }
        let fade = (settleProgress - contentFadeStartSettleProgress)
            / (contentFadeEndSettleProgress - contentFadeStartSettleProgress)
        return fade * fade * (3 - 2 * fade)
    }

    private static func clamped(
        _ contentOffsetY: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        min(max(contentOffsetY, 0), maximum)
    }

    private static func sanitizedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return 1 }
        return scale
    }

    static func sanitizedProgress(_ progress: CGFloat) -> CGFloat {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }
}
