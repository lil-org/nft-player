import QuartzCore
import UIKit

@MainActor
final class MobilePlayerCollectionBrowserScrollCoordinator {
    enum FocusPublicationCadence {
        case immediate
        case continuous
    }

    struct Snapshot {
        let publicationState: PlayerCollectionScrollPublicationState?
        let hasFinishedInitialPositioning: Bool
        let focusedTokenIndex: Int?
        let forcedFocusedTokenIndex: Int?
        let retainedFocusFocalBias: PlayerCollectionScrollFocalBias?
        let lastEmittedFocusedTokenIndex: Int?
        let lastScrollOffsetY: CGFloat?
        let lastPrefetchDirection: DownloadableMediaCache.PrefetchDirection
    }

    struct ContentAccess {
        let pagePosition: @MainActor (Int) -> PlayerPagePosition?
        let publishFocusedPagePosition: @MainActor (
            PlayerPagePosition
        ) -> Void
        let publishSettledPosition: @MainActor (
            PlayerCollectionScrollPublication
        ) -> Bool
        let performScheduledScrollObservation: @MainActor () -> Void
        let scrollMotionAnimationDidExpire: @MainActor () -> Void
    }

    private static let continuousFocusPublicationInterval: CFTimeInterval =
        1 / 12
    private static let scrollMotionAnimationTimeout: TimeInterval = 2

    private var contentAccess: ContentAccess?
    private var positioningGeneration: UInt = 0
    private var focusPublicationGeneration: UInt = 0
    private var isFocusPublicationScheduled = false
    private var pendingFocusedTokenIndex: Int?
    private var lastFocusPublicationTime: CFTimeInterval?
    private var scrollUpdateGeneration: UInt = 0
    private var isScrollUpdateScheduled = false
    private var positionSettlementGeneration: UInt = 0
    private var scrollMotionAnimationTimeoutGeneration: UInt = 0
    private var hasAcknowledgedCurrentDrag = false
    private var scrollUpdateTask: Task<Void, Never>?
    private var focusPublicationTask: Task<Void, Never>?
    private var scrollMotionAnimationTimeoutTask: Task<Void, Never>?
    private var isInvalidated = false

    private(set) var isActive = false
    private(set) var isApplyingPosition = false
    private(set) var isScrollMotionActive = false
    var publicationState: PlayerCollectionScrollPublicationState?
    var hasFinishedInitialPositioning = false
    var focusedTokenIndex: Int?
    var forcedFocusedTokenIndex: Int?
    var retainedFocusFocalBias: PlayerCollectionScrollFocalBias?
    var lastEmittedFocusedTokenIndex: Int?
    var lastScrollOffsetY: CGFloat?
    var dragStartContentOffsetY: CGFloat?
    private(set) var lastPrefetchDirection:
        DownloadableMediaCache.PrefetchDirection = .forward

    func configure(contentAccess: ContentAccess) {
        guard !isInvalidated else { return }
        self.contentAccess = contentAccess
    }

    func snapshot() -> Snapshot {
        Snapshot(
            publicationState: publicationState,
            hasFinishedInitialPositioning: hasFinishedInitialPositioning,
            focusedTokenIndex: focusedTokenIndex,
            forcedFocusedTokenIndex: forcedFocusedTokenIndex,
            retainedFocusFocalBias: retainedFocusFocalBias,
            lastEmittedFocusedTokenIndex: lastEmittedFocusedTokenIndex,
            lastScrollOffsetY: lastScrollOffsetY,
            lastPrefetchDirection: lastPrefetchDirection
        )
    }

    func restore(
        _ snapshot: Snapshot,
        retainedFocusFocalBias: PlayerCollectionScrollFocalBias?,
        lastScrollOffsetY: CGFloat?
    ) {
        guard !isInvalidated else { return }
        publicationState = snapshot.publicationState
        hasFinishedInitialPositioning = snapshot.hasFinishedInitialPositioning
        focusedTokenIndex = snapshot.focusedTokenIndex
        forcedFocusedTokenIndex = snapshot.forcedFocusedTokenIndex
        self.retainedFocusFocalBias = retainedFocusFocalBias
        lastEmittedFocusedTokenIndex = snapshot.lastEmittedFocusedTokenIndex
        self.lastScrollOffsetY = lastScrollOffsetY
        lastPrefetchDirection = snapshot.lastPrefetchDirection
    }

    func setActive(_ active: Bool) {
        guard !isInvalidated else { return }
        isActive = active
    }

    func setApplyingPosition(_ applying: Bool) {
        guard !isInvalidated else { return }
        isApplyingPosition = applying
    }

    func beginPositioning() -> UInt {
        guard !isInvalidated else { return positioningGeneration }
        positioningGeneration &+= 1
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        return positioningGeneration
    }

    func cancelPositioning() {
        guard !isInvalidated else { return }
        positioningGeneration &+= 1
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
    }

    func isCurrentPositioningGeneration(_ generation: UInt) -> Bool {
        !isInvalidated && positioningGeneration == generation
    }

    func beginPublicationPositioning(
        at tokenIndex: Int,
        snapshotChanged: Bool
    ) {
        guard !isInvalidated else { return }
        if hasFinishedInitialPositioning, !snapshotChanged {
            if publicationState == nil {
                publicationState = PlayerCollectionScrollPublicationState(
                    initialIndex: tokenIndex
                )
                publicationState?.finishInitialPositioning()
            }
            publicationState?.beginProgrammaticPositioning(at: tokenIndex)
        } else {
            publicationState = PlayerCollectionScrollPublicationState(
                initialIndex: tokenIndex
            )
            hasFinishedInitialPositioning = false
        }
    }

    func resetInitialPositioning(
        at tokenIndex: Int?,
        resetsLastEmittedFocus: Bool
    ) {
        guard !isInvalidated else { return }
        publicationState = tokenIndex.map {
            PlayerCollectionScrollPublicationState(initialIndex: $0)
        }
        hasFinishedInitialPositioning = false
        focusedTokenIndex = tokenIndex
        if resetsLastEmittedFocus {
            lastEmittedFocusedTokenIndex = nil
        }
    }

    func finishPositioning() {
        guard !isInvalidated else { return }
        if !hasFinishedInitialPositioning {
            hasFinishedInitialPositioning = true
            publicationState?.finishInitialPositioning()
        } else {
            publicationState?.finishProgrammaticPositioning()
        }
        isApplyingPosition = false
    }

    func finishInitialPositioning() {
        guard !isInvalidated else { return }
        hasFinishedInitialPositioning = true
        publicationState?.finishInitialPositioning()
    }

    func observe(
        tokenIndex: Int,
        focusCadence: FocusPublicationCadence
    ) {
        guard !isInvalidated else { return }
        publicationState?.observeCandidate(tokenIndex)
        publishFocus(tokenIndex: tokenIndex, cadence: focusCadence)
    }

    func publishFocus(
        tokenIndex: Int,
        cadence: FocusPublicationCadence
    ) {
        guard !isInvalidated else { return }
        focusedTokenIndex = tokenIndex
        switch cadence {
        case .immediate:
            cancelPendingFocusPublication(resetLastPublicationTime: false)
            emitFocus(tokenIndex: tokenIndex)

        case .continuous:
            guard isActive else { return }
            if lastEmittedFocusedTokenIndex == tokenIndex {
                cancelPendingFocusPublication(resetLastPublicationTime: false)
                return
            }
            pendingFocusedTokenIndex = tokenIndex
            let now = CACurrentMediaTime()
            let elapsed = lastFocusPublicationTime.map { now - $0 }
                ?? Self.continuousFocusPublicationInterval
            guard elapsed < Self.continuousFocusPublicationInterval else {
                cancelPendingFocusPublication(resetLastPublicationTime: false)
                emitFocus(tokenIndex: tokenIndex)
                return
            }
            guard !isFocusPublicationScheduled else { return }

            isFocusPublicationScheduled = true
            focusPublicationGeneration &+= 1
            let generation = focusPublicationGeneration
            let delay = Self.continuousFocusPublicationInterval - elapsed
            focusPublicationTask?.cancel()
            focusPublicationTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard let self,
                      !self.isInvalidated,
                      self.focusPublicationGeneration == generation else {
                    return
                }
                self.isFocusPublicationScheduled = false
                self.focusPublicationTask = nil
                guard let tokenIndex = self.pendingFocusedTokenIndex else {
                    return
                }
                self.pendingFocusedTokenIndex = nil
                self.emitFocus(tokenIndex: tokenIndex)
            }
        }
    }

    func cancelPendingFocusPublication(resetLastPublicationTime: Bool) {
        focusPublicationGeneration &+= 1
        isFocusPublicationScheduled = false
        focusPublicationTask?.cancel()
        focusPublicationTask = nil
        pendingFocusedTokenIndex = nil
        if resetLastPublicationTime {
            lastFocusPublicationTime = nil
        }
    }

    func settle(hasViewedToEnd: Bool) {
        guard !isInvalidated,
              let publication = publicationState?.settle(
                hasViewedToEnd: hasViewedToEnd
              ) else {
            return
        }
        guard contentAccess?.publishSettledPosition(publication) == true else {
            publicationState?.retryPublication(of: publication)
            return
        }
    }

    func finalFlush(hasViewedToEnd: Bool) {
        guard !isInvalidated,
              let publication = publicationState?.finalFlush(
                hasViewedToEnd: hasViewedToEnd
              ) else {
            return
        }
        guard contentAccess?.publishSettledPosition(publication) == true else {
            publicationState?.retryPublication(of: publication)
            return
        }
    }

    func beginSettlement() {
        guard !isInvalidated else { return }
        positionSettlementGeneration &+= 1
        cancelScheduledScrollUpdate()
    }

    var settlementGeneration: UInt {
        positionSettlementGeneration
    }

    func beginScrollMotion() -> Bool {
        guard !isInvalidated, !isScrollMotionActive else { return false }
        isScrollMotionActive = true
        return true
    }

    func endScrollMotion() {
        guard !isInvalidated else { return }
        isScrollMotionActive = false
        cancelScrollMotionAnimationTimeout()
    }

    func beginDrag(
        contentOffsetY: CGFloat,
        clampedContentOffsetY: CGFloat
    ) -> Bool {
        guard !isInvalidated else { return false }
        lastScrollOffsetY = contentOffsetY
        dragStartContentOffsetY = clampedContentOffsetY
        hasAcknowledgedCurrentDrag = false
        return beginScrollMotion()
    }

    func resetDragState() {
        guard !isInvalidated else { return }
        dragStartContentOffsetY = nil
        hasAcknowledgedCurrentDrag = false
    }

    func markCurrentDragAcknowledged() -> Bool {
        guard !isInvalidated, !hasAcknowledgedCurrentDrag else { return false }
        hasAcknowledgedCurrentDrag = true
        return true
    }

    func acknowledgeIntentionalScrollIfNeeded(
        clampedContentOffsetY: CGFloat,
        epsilon: CGFloat
    ) -> Bool {
        guard !isInvalidated,
              !hasAcknowledgedCurrentDrag,
              let dragStartContentOffsetY,
              abs(clampedContentOffsetY - dragStartContentOffsetY) > epsilon else {
            return false
        }
        hasAcknowledgedCurrentDrag = true
        return true
    }

    func observeContentOffset(_ contentOffsetY: CGFloat) -> CGFloat? {
        guard !isInvalidated else { return nil }
        let previousOffsetY = lastScrollOffsetY
        lastScrollOffsetY = contentOffsetY
        return previousOffsetY
    }

    func adjustDragStartContentOffset(by offsetDeltaY: CGFloat) {
        guard !isInvalidated, let dragStartContentOffsetY else { return }
        self.dragStartContentOffsetY = dragStartContentOffsetY + offsetDeltaY
    }

    func updatePrefetchDirection(
        offsetDelta: CGFloat,
        epsilon: CGFloat
    ) -> DownloadableMediaCache.PrefetchDirection? {
        guard !isInvalidated, abs(offsetDelta) > epsilon else { return nil }
        lastPrefetchDirection = offsetDelta > 0 ? .forward : .backward
        return lastPrefetchDirection
    }

    func setPrefetchDirection(
        _ direction: DownloadableMediaCache.PrefetchDirection
    ) {
        guard !isInvalidated else { return }
        lastPrefetchDirection = direction
    }

    func scheduleScrollUpdate() {
        guard !isInvalidated, !isScrollUpdateScheduled else { return }
        isScrollUpdateScheduled = true
        scrollUpdateGeneration &+= 1
        let generation = scrollUpdateGeneration
        scrollUpdateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !self.isInvalidated,
                  self.scrollUpdateGeneration == generation else {
                return
            }
            self.isScrollUpdateScheduled = false
            self.scrollUpdateTask = nil
            guard self.isActive,
                  self.hasFinishedInitialPositioning,
                  !self.isApplyingPosition else {
                return
            }
            self.contentAccess?.performScheduledScrollObservation()
        }
    }

    func cancelScheduledScrollUpdate() {
        scrollUpdateGeneration &+= 1
        isScrollUpdateScheduled = false
        scrollUpdateTask?.cancel()
        scrollUpdateTask = nil
    }

    func scheduleScrollMotionAnimationTimeout() {
        guard !isInvalidated, isScrollMotionActive else { return }
        cancelScrollMotionAnimationTimeout()
        let generation = scrollMotionAnimationTimeoutGeneration
        scrollMotionAnimationTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(Self.scrollMotionAnimationTimeout)
                )
            } catch {
                return
            }
            guard let self,
                  !self.isInvalidated,
                  self.isScrollMotionActive,
                  self.scrollMotionAnimationTimeoutGeneration == generation else {
                return
            }
            self.scrollMotionAnimationTimeoutTask = nil
            self.contentAccess?.scrollMotionAnimationDidExpire()
        }
    }

    func cancelScrollMotionAnimationTimeout() {
        scrollMotionAnimationTimeoutGeneration &+= 1
        scrollMotionAnimationTimeoutTask?.cancel()
        scrollMotionAnimationTimeoutTask = nil
    }

#if DEBUG
    var isScrollMotionAnimationTimeoutScheduled: Bool {
        scrollMotionAnimationTimeoutTask != nil
    }
#endif

    func invalidate() {
        guard !isInvalidated else { return }
        positioningGeneration &+= 1
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        cancelScheduledScrollUpdate()
        cancelScrollMotionAnimationTimeout()
        isInvalidated = true
        contentAccess = nil
    }

    private func emitFocus(tokenIndex: Int) {
        guard isActive,
              lastEmittedFocusedTokenIndex != tokenIndex,
              let pagePosition = contentAccess?.pagePosition(tokenIndex) else {
            return
        }
        lastEmittedFocusedTokenIndex = tokenIndex
        lastFocusPublicationTime = CACurrentMediaTime()
        contentAccess?.publishFocusedPagePosition(pagePosition)
    }
}
