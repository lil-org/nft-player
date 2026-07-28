// ∅ 2026 lil org

import Foundation

struct PlayerCollectionVisibleItem: Equatable {
    let index: Int
    let frame: CGRect
}

struct PlayerCollectionScrollFocalGeometry: Equatable {
    let minimumOffsetY: CGFloat
    let maximumOffsetY: CGFloat
    let viewportHeight: CGFloat
    let viewportCenterX: CGFloat
    let firstItemCenter: CGPoint
    let lastItemCenter: CGPoint
    let lastRowFocalEntryY: CGFloat

    init?(
        minimumOffsetY: CGFloat,
        maximumOffsetY: CGFloat,
        viewportHeight: CGFloat,
        viewportCenterX: CGFloat,
        firstItemCenter: CGPoint,
        lastItemCenter: CGPoint,
        lastRowFocalEntryY: CGFloat
    ) {
        guard minimumOffsetY.isFinite,
              maximumOffsetY.isFinite,
              maximumOffsetY >= minimumOffsetY,
              viewportHeight.isFinite,
              viewportHeight > 0,
              viewportCenterX.isFinite,
              firstItemCenter.x.isFinite,
              firstItemCenter.y.isFinite,
              lastItemCenter.x.isFinite,
              lastItemCenter.y.isFinite,
              lastItemCenter.y >= firstItemCenter.y,
              lastRowFocalEntryY.isFinite,
              lastRowFocalEntryY >= firstItemCenter.y,
              lastRowFocalEntryY <= lastItemCenter.y else {
            return nil
        }

        self.minimumOffsetY = minimumOffsetY
        self.maximumOffsetY = maximumOffsetY
        self.viewportHeight = viewportHeight
        self.viewportCenterX = viewportCenterX
        self.firstItemCenter = firstItemCenter
        self.lastItemCenter = lastItemCenter
        self.lastRowFocalEntryY = lastRowFocalEntryY
    }

    func focalPoint(at contentOffsetY: CGFloat) -> CGPoint {
        let clampedOffsetY = min(
            max(contentOffsetY.isFinite ? contentOffsetY : minimumOffsetY, minimumOffsetY),
            maximumOffsetY
        )
        let scrollRange = maximumOffsetY - minimumOffsetY
        guard scrollRange > 0,
              lastItemCenter.y > firstItemCenter.y else {
            return firstItemCenter
        }

        let viewportMidY = viewportHeight / 2
        let topSpan = max(
            minimumOffsetY + viewportMidY - firstItemCenter.y,
            0
        )
        let bottomSpan = max(
            lastItemCenter.y - maximumOffsetY - viewportMidY,
            0
        )
        let distanceFromTop = clampedOffsetY - minimumOffsetY
        let distanceFromBottom = maximumOffsetY - clampedOffsetY

        if scrollRange < topSpan + bottomSpan {
            let progress = distanceFromTop / scrollRange
            return interpolatedPoint(
                from: firstItemCenter,
                to: lastItemCenter,
                progress: progress
            )
        }

        if topSpan > 0,
           distanceFromTop < topSpan {
            return CGPoint(
                x: interpolatedValue(
                    from: firstItemCenter.x,
                    to: viewportCenterX,
                    progress: distanceFromTop / topSpan
                ),
                y: firstItemCenter.y + distanceFromTop * 2
            )
        }

        if bottomSpan > 0,
           distanceFromBottom < bottomSpan {
            let focalY = lastItemCenter.y - distanceFromBottom * 2
            let bottomEdgeStartY = lastItemCenter.y - bottomSpan * 2
            let horizontalTransitionStartY = max(
                bottomEdgeStartY,
                lastRowFocalEntryY
            )
            let horizontalTransitionDistance = max(
                lastItemCenter.y - horizontalTransitionStartY,
                0
            )
            let horizontalProgress = horizontalTransitionDistance > 0
                ? (focalY - horizontalTransitionStartY) / horizontalTransitionDistance
                : 1
            return CGPoint(
                x: interpolatedValue(
                    from: viewportCenterX,
                    to: lastItemCenter.x,
                    progress: horizontalProgress
                ),
                y: focalY
            )
        }

        return CGPoint(
            x: viewportCenterX,
            y: clampedOffsetY + viewportMidY
        )
    }

    func contentOffsetY(anchoringFocalY focalY: CGFloat) -> CGFloat {
        let targetFocalY = min(
            max(focalY.isFinite ? focalY : firstItemCenter.y, firstItemCenter.y),
            lastItemCenter.y
        )
        let scrollRange = maximumOffsetY - minimumOffsetY
        let focalRange = lastItemCenter.y - firstItemCenter.y
        guard scrollRange > 0,
              focalRange > 0 else {
            return minimumOffsetY
        }

        let viewportMidY = viewportHeight / 2
        let topSpan = max(
            minimumOffsetY + viewportMidY - firstItemCenter.y,
            0
        )
        let bottomSpan = max(
            lastItemCenter.y - maximumOffsetY - viewportMidY,
            0
        )
        let proposedOffsetY: CGFloat
        if scrollRange < topSpan + bottomSpan {
            let progress = (targetFocalY - firstItemCenter.y) / focalRange
            proposedOffsetY = minimumOffsetY + scrollRange * progress
        } else if topSpan > 0,
                  targetFocalY < firstItemCenter.y + topSpan * 2 {
            proposedOffsetY = minimumOffsetY
                + (targetFocalY - firstItemCenter.y) / 2
        } else if bottomSpan > 0,
                  targetFocalY > lastItemCenter.y - bottomSpan * 2 {
            proposedOffsetY = maximumOffsetY
                - (lastItemCenter.y - targetFocalY) / 2
        } else {
            proposedOffsetY = targetFocalY - viewportMidY
        }

        return min(max(proposedOffsetY, minimumOffsetY), maximumOffsetY)
    }

    private func interpolatedPoint(
        from start: CGPoint,
        to end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: interpolatedValue(from: start.x, to: end.x, progress: progress),
            y: interpolatedValue(from: start.y, to: end.y, progress: progress)
        )
    }

    private func interpolatedValue(
        from start: CGFloat,
        to end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        let progress = min(max(progress, 0), 1)
        return start + (end - start) * progress
    }
}

struct PlayerCollectionScrollFocalBias: Equatable {
    let referenceFocalY: CGFloat
    let deltaY: CGFloat
    let decayDistance: CGFloat

    init?(
        referenceFocalY: CGFloat,
        deltaY: CGFloat,
        decayDistance: CGFloat
    ) {
        guard referenceFocalY.isFinite,
              deltaY.isFinite,
              decayDistance.isFinite,
              decayDistance > 0 else {
            return nil
        }

        self.referenceFocalY = referenceFocalY
        self.deltaY = deltaY
        self.decayDistance = decayDistance
    }

    func adjustedFocalPoint(
        from focalPoint: CGPoint,
        minimumFocalY: CGFloat,
        maximumFocalY: CGFloat
    ) -> CGPoint {
        let remaining = remainingProgress(
            at: focalPoint.y,
            minimumFocalY: minimumFocalY,
            maximumFocalY: maximumFocalY
        )
        return CGPoint(
            x: focalPoint.x,
            y: focalPoint.y + deltaY * remaining
        )
    }

    func isExpired(
        at focalY: CGFloat,
        minimumFocalY: CGFloat,
        maximumFocalY: CGFloat
    ) -> Bool {
        remainingProgress(
            at: focalY,
            minimumFocalY: minimumFocalY,
            maximumFocalY: maximumFocalY
        ) == 0
    }

    private func remainingProgress(
        at focalY: CGFloat,
        minimumFocalY: CGFloat,
        maximumFocalY: CGFloat
    ) -> CGFloat {
        guard focalY.isFinite,
              minimumFocalY.isFinite,
              maximumFocalY.isFinite,
              maximumFocalY >= minimumFocalY else {
            return 1
        }

        let clampedReferenceFocalY = min(
            max(referenceFocalY, minimumFocalY),
            maximumFocalY
        )
        let clampedFocalY = min(
            max(focalY, minimumFocalY),
            maximumFocalY
        )
        let travel = abs(clampedFocalY - clampedReferenceFocalY)
        guard travel > 0 else { return 1 }

        let availableTravel = clampedFocalY > clampedReferenceFocalY
            ? maximumFocalY - clampedReferenceFocalY
            : clampedReferenceFocalY - minimumFocalY
        let effectiveDecayDistance = min(decayDistance, availableTravel)
        guard effectiveDecayDistance > 0 else { return 0 }
        return max(1 - travel / effectiveDecayDistance, 0)
    }
}

struct PlayerCollectionRestorationResolution: Equatable {
    let tokenIndex: Int?
    let didResolveRequestedPosition: Bool
}

enum PlayerCollectionScrollPolicy {

    static func boundedContentOffsetDelta(
        previousOffsetY: CGFloat,
        currentOffsetY: CGFloat,
        validRange: ClosedRange<CGFloat>
    ) -> CGFloat {
        guard previousOffsetY.isFinite,
              currentOffsetY.isFinite,
              validRange.lowerBound.isFinite,
              validRange.upperBound.isFinite else {
            return 0
        }

        let boundedPreviousOffsetY = min(
            max(previousOffsetY, validRange.lowerBound),
            validRange.upperBound
        )
        let boundedCurrentOffsetY = min(
            max(currentOffsetY, validRange.lowerBound),
            validRange.upperBound
        )
        let delta = boundedCurrentOffsetY - boundedPreviousOffsetY
        return delta.isFinite ? delta : 0
    }

    static func restorationResolution(
        savedIndex: Int?,
        tokenIdIndex: Int?,
        itemCount: Int,
        hasRequestedPosition: Bool,
        isIndexAvailable: (Int) -> Bool = { _ in true }
    ) -> PlayerCollectionRestorationResolution {
        guard itemCount > 0 else {
            return PlayerCollectionRestorationResolution(
                tokenIndex: nil,
                didResolveRequestedPosition: false
            )
        }

        func isValid(_ index: Int?) -> Bool {
            guard let index,
                  (0..<itemCount).contains(index) else {
                return false
            }
            return isIndexAvailable(index)
        }

        if isValid(savedIndex) {
            return PlayerCollectionRestorationResolution(
                tokenIndex: savedIndex,
                didResolveRequestedPosition: true
            )
        }
        if isValid(tokenIdIndex) {
            return PlayerCollectionRestorationResolution(
                tokenIndex: tokenIdIndex,
                didResolveRequestedPosition: true
            )
        }

        let isCollectionStartAvailable = isIndexAvailable(0)
        return PlayerCollectionRestorationResolution(
            tokenIndex: isCollectionStartAvailable ? 0 : nil,
            didResolveRequestedPosition: !hasRequestedPosition && isCollectionStartAvailable
        )
    }

    static func restorationIndex(savedIndex: Int?, itemCount: Int) -> Int? {
        restorationResolution(
            savedIndex: savedIndex,
            tokenIdIndex: nil,
            itemCount: itemCount,
            hasRequestedPosition: savedIndex != nil
        ).tokenIndex
    }

    static func resolvedAnchorIndex(
        retainedIndex: Int?,
        candidateIndex: Int?,
        itemCount: Int,
        configuredColumnCount: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }

        let retainedIndex = retainedIndex.flatMap {
            (0..<itemCount).contains($0) ? $0 : nil
        }
        let candidateIndex = candidateIndex.flatMap {
            (0..<itemCount).contains($0) ? $0 : nil
        }

        guard let retainedIndex else { return candidateIndex }
        guard let candidateIndex,
              configuredColumnCount > 0 else {
            return retainedIndex
        }

        return retainedIndex / configuredColumnCount == candidateIndex / configuredColumnCount
            ? retainedIndex
            : candidateIndex
    }

    static func isItemFullyVisible(
        frame: CGRect,
        viewport: CGRect,
        epsilon: CGFloat
    ) -> Bool {
        guard !frame.isNull,
              !frame.isInfinite,
              !frame.isEmpty,
              !viewport.isNull,
              !viewport.isInfinite,
              !viewport.isEmpty,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.maxX.isFinite,
              frame.maxY.isFinite,
              viewport.minX.isFinite,
              viewport.minY.isFinite,
              viewport.maxX.isFinite,
              viewport.maxY.isFinite,
              epsilon.isFinite,
              epsilon >= 0 else {
            return false
        }

        return viewport.insetBy(dx: -epsilon, dy: -epsilon).contains(frame)
    }

    static func hasViewedToEnd(
        finalItemFrame: CGRect,
        viewport: CGRect,
        maximumContentOffsetY: CGFloat,
        epsilon: CGFloat
    ) -> Bool {
        if isItemFullyVisible(
            frame: finalItemFrame,
            viewport: viewport,
            epsilon: epsilon
        ) {
            return true
        }

        guard !finalItemFrame.isNull,
              !finalItemFrame.isInfinite,
              !finalItemFrame.isEmpty,
              !viewport.isNull,
              !viewport.isInfinite,
              !viewport.isEmpty,
              finalItemFrame.minX.isFinite,
              finalItemFrame.maxX.isFinite,
              finalItemFrame.maxY.isFinite,
              finalItemFrame.height.isFinite,
              viewport.minX.isFinite,
              viewport.minY.isFinite,
              viewport.maxX.isFinite,
              viewport.maxY.isFinite,
              viewport.height.isFinite,
              maximumContentOffsetY.isFinite,
              epsilon.isFinite,
              epsilon >= 0,
              finalItemFrame.height > viewport.height + epsilon,
              viewport.minY >= maximumContentOffsetY - epsilon else {
            return false
        }

        let expandedViewport = viewport.insetBy(dx: -epsilon, dy: -epsilon)
        return finalItemFrame.minX >= expandedViewport.minX
            && finalItemFrame.maxX <= expandedViewport.maxX
            && finalItemFrame.maxY >= expandedViewport.minY
            && finalItemFrame.maxY <= expandedViewport.maxY
    }

    static func anchorIndex(
        visibleItems: [PlayerCollectionVisibleItem],
        focalPoint: CGPoint,
        itemCount: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }

        guard focalPoint.x.isFinite,
              focalPoint.y.isFinite else {
            return nil
        }

        var bestIndex: Int?
        var bestVerticalDistance: CGFloat?
        var bestHorizontalDistance: CGFloat?

        for item in visibleItems where (0..<itemCount).contains(item.index) {
            let itemCenter = CGPoint(x: item.frame.midX, y: item.frame.midY)
            guard itemCenter.x.isFinite,
                  itemCenter.y.isFinite else {
                continue
            }

            let verticalDistance = abs(itemCenter.y - focalPoint.y)
            let horizontalDistance = abs(itemCenter.x - focalPoint.x)
            guard verticalDistance.isFinite,
                  horizontalDistance.isFinite else {
                continue
            }

            let shouldSelectItem: Bool
            if let bestVerticalDistance,
               let bestHorizontalDistance,
               let bestIndex {
                shouldSelectItem = verticalDistance < bestVerticalDistance
                    || (verticalDistance == bestVerticalDistance
                        && (horizontalDistance < bestHorizontalDistance
                            || (horizontalDistance == bestHorizontalDistance
                                && item.index < bestIndex)))
            } else {
                shouldSelectItem = true
            }

            if shouldSelectItem {
                bestIndex = item.index
                bestVerticalDistance = verticalDistance
                bestHorizontalDistance = horizontalDistance
            }
        }

        return bestIndex
    }
}

struct PlayerCollectionScrollPublication: Equatable {
    let tokenIndex: Int
    let hasViewedToEnd: Bool
}

struct PlayerCollectionScrollPublicationState {
    private enum PositioningPhase {
        case initial
        case programmatic
    }

    private var positioningPhase: PositioningPhase? = .initial
    private var pendingIndex: Int
    private var pendingHasViewedToEnd = false
    private var lastPublishedValue: PlayerCollectionScrollPublication?

    init(initialIndex: Int) {
        pendingIndex = max(initialIndex, 0)
    }

    mutating func observeCandidate(_ index: Int) {
        guard positioningPhase == nil,
              index >= 0 else {
            return
        }

        pendingIndex = index
    }

    mutating func finishInitialPositioning() {
        guard positioningPhase == .initial else { return }
        positioningPhase = nil
    }

    mutating func beginProgrammaticPositioning(at index: Int) {
        pendingIndex = max(index, 0)
        positioningPhase = .programmatic
    }

    mutating func finishProgrammaticPositioning() {
        guard positioningPhase == .programmatic else { return }
        positioningPhase = nil
    }

    mutating func settle(
        hasViewedToEnd: Bool = false
    ) -> PlayerCollectionScrollPublication? {
        guard positioningPhase == nil else { return nil }
        pendingHasViewedToEnd = pendingHasViewedToEnd || hasViewedToEnd
        return publishPendingValueIfNeeded()
    }

    mutating func finalFlush(
        hasViewedToEnd: Bool = false
    ) -> PlayerCollectionScrollPublication? {
        pendingHasViewedToEnd = pendingHasViewedToEnd || hasViewedToEnd
        return publishPendingValueIfNeeded()
    }

    mutating func retryPublication(
        of value: PlayerCollectionScrollPublication
    ) {
        guard lastPublishedValue == value else { return }
        lastPublishedValue = nil
    }

    private mutating func publishPendingValueIfNeeded() -> PlayerCollectionScrollPublication? {
        let value = PlayerCollectionScrollPublication(
            tokenIndex: pendingIndex,
            hasViewedToEnd: pendingHasViewedToEnd
        )
        guard value != lastPublishedValue else { return nil }
        lastPublishedValue = value
        return value
    }
}
