// ∅ 2026 lil org

import QuartzCore
import UIKit
import os

private let gridPlaneRendererSignposter = OSSignposter(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "GridPlaneRenderer"
)

@MainActor
final class GridPlaneRenderer {
    typealias GridModeCellFrameCorrection = GridRenderCellFrameCorrection

    enum ManualCellRole {
        case sourceOverscan
        case destinationPhantom
    }

    enum SourcePresentationRole {
        case awaitingClassification
        case marginCoverage
        case destinationTransition
        case sourceFallback
    }

    struct GridModeCellFrameCorrectionGeometry {
        let currentToTerminal: CGAffineTransform
        let terminalScreenOffsetY: CGFloat
        let destinationGeometry: MobilePlayerBrowserVisualLayoutGeometry
    }

    struct AppliedPlaneScale {
        let x: CGFloat
        let y: CGFloat
    }

    private struct CellFrameCorrectionTransformContext {
        let settleProgress: CGFloat
        let appliedScale: AppliedPlaneScale
        let terminalScale: AppliedPlaneScale
        let sourceSpacing: CGFloat
        let destinationSpacing: CGFloat
        let targetSpacing: CGFloat
    }

    struct SeamCompensation {
        static let minimumScaleFactor: CGFloat = 0.5

        let excessX: CGFloat
        let excessY: CGFloat
        let appliedScale: AppliedPlaneScale

        init?(
            naturalSpacing: CGFloat,
            targetSpacing: CGFloat,
            relativeScaleX: CGFloat,
            relativeScaleY: CGFloat,
            appliedScale: AppliedPlaneScale
        ) {
            let excessX = naturalSpacing * relativeScaleX - targetSpacing
            let excessY = naturalSpacing * relativeScaleY - targetSpacing
            guard excessX.isFinite,
                  excessY.isFinite,
                  excessX != 0 || excessY != 0 else {
                return nil
            }
            self.excessX = excessX
            self.excessY = excessY
            self.appliedScale = appliedScale
        }
    }

    struct PhantomShapeFrameCompensation: Equatable {
        let localExcessX: CGFloat
        let localExcessY: CGFloat
        let minimumScaleFactor: CGFloat

        init?(
            excessX: CGFloat,
            excessY: CGFloat,
            appliedScaleX: CGFloat,
            appliedScaleY: CGFloat,
            minimumScaleFactor: CGFloat
        ) {
            guard appliedScaleX > 0, appliedScaleY > 0 else { return nil }
            localExcessX = excessX / appliedScaleX
            localExcessY = excessY / appliedScaleY
            self.minimumScaleFactor = minimumScaleFactor
            guard localExcessX.isFinite, localExcessY.isFinite else {
                return nil
            }
        }

        func applying(to frame: CGRect) -> CGRect {
            guard frame.width > 0, frame.height > 0 else { return frame }
            let width = max(
                frame.width + localExcessX,
                frame.width * minimumScaleFactor
            )
            let height = max(
                frame.height + localExcessY,
                frame.height * minimumScaleFactor
            )
            return CGRect(
                x: frame.midX - width / 2,
                y: frame.midY - height / 2,
                width: width,
                height: height
            )
        }
    }

    private static let edgeHandoffDistance: CGFloat = 128
    static let contentFadeOutDuration: TimeInterval = 0.12

    private weak var collectionView:
        MobilePlayerCollectionBrowserCollectionView?
    private weak var viewportView: UIView?
    private(set) var phantomShapeStructureBuildCount = 0
    private(set) var phantomShapeMaskBuildCount = 0

#if DEBUG
    private(set) var phantomShapeMaskCommitAttemptCount = 0
#endif

    init(
        collectionView: MobilePlayerCollectionBrowserCollectionView,
        viewportView: UIView
    ) {
        self.collectionView = collectionView
        self.viewportView = viewportView
    }

    func applySourcePresentation(
        to cell: MobilePlayerCollectionBrowserCell,
        role: SourcePresentationRole,
        visibleAlpha: CGFloat,
        interruptingAnimation: Bool = false
    ) {
        setSourceCellAlpha(1, on: cell)
        switch role {
        case .awaitingClassification:
            if cell.holdsCarryoverForPendingBaseImage {
                cell.setTransitionContentAlpha(
                    1,
                    interruptingAnimation: interruptingAnimation
                )
            }
        case .marginCoverage:
            cell.setTransitionContentAlpha(
                cell.holdsCarryoverForPendingBaseImage ? 1 : 0,
                interruptingAnimation: interruptingAnimation
            )
        case .destinationTransition:
            cell.setTransitionContentAlpha(
                visibleAlpha,
                interruptingAnimation: interruptingAnimation
            )
        case .sourceFallback:
            // Photos never fades the outgoing plane: a cell whose destination
            // content has not arrived keeps its old pixels at full opacity
            // until the arrival crossfades in or the commit carries them over.
            // Fading it out uncovers the background wherever nothing else
            // paints that region — the flanks of a zoom-in most visibly.
            if cell.holdsCarryoverForPendingBaseImage {
                cell.setTransitionContentAlpha(
                    1,
                    interruptingAnimation: interruptingAnimation
                )
            } else if !cell.hasCarryoverContent {
                cell.setTransitionContentAlpha(
                    0,
                    interruptingAnimation: interruptingAnimation
                )
            }
        }
    }

    func interruptSourceOpacityAnimation(on cell: UICollectionViewCell) {
        guard cell.layer.animation(forKey: "opacity") != nil else { return }
        cell.layer.removeAnimation(forKey: "opacity")
    }

    func resetSourcePresentation(
        on cell: UICollectionViewCell,
        removingOpacityAnimation: Bool
    ) {
        if removingOpacityAnimation {
            interruptSourceOpacityAnimation(on: cell)
        }
        cell.alpha = 1
        cell.transform = .identity
    }

    func resetCollectionTransform() {
        collectionView?.transform = .identity
    }

    func animateContentFade(
        _ animations: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: Self.contentFadeOutDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut],
            animations: animations
        ) { _ in
            completion()
        }
    }

    func insertManualCell(
        _ cell: MobilePlayerCollectionBrowserCell,
        role: ManualCellRole,
        session: GridRenderSession
    ) {
        guard let collectionView else { return }
        if role == .sourceOverscan {
            let manualCellIDs = Set(
                session.sourceOverscanCells.values.map(ObjectIdentifier.init)
                    + session.phantomCells.values.map(ObjectIdentifier.init)
            )
            if let topmostManualCell = collectionView.subviews.last(where: {
                manualCellIDs.contains(ObjectIdentifier($0))
            }) {
                collectionView.insertSubview(
                    cell,
                    aboveSubview: topmostManualCell
                )
                return
            }
        }
        if let phantomShapeView = session.phantomShapeView,
           phantomShapeView.superview === collectionView {
            collectionView.insertSubview(cell, aboveSubview: phantomShapeView)
        } else {
            collectionView.insertSubview(cell, at: 0)
        }
    }

    func phantomShapeMaskedFrames(
        session: GridRenderSession?
    ) -> [CGRect] {
        guard let placeholderView = session?.phantomShapeView
            as? PhantomShapeView else {
            return []
        }
        return placeholderView.renderedShapeExclusionFrames
            + Array(placeholderView.renderedOccupantFrames.values)
    }

    func removePhantomShape(session: GridRenderSession) {
        session.phantomShapeView?.removeFromSuperview()
    }

    func makePlaneContext(
        request: GridModePlaneRequest,
        session: GridRenderSession
    ) -> GridModePlaneContext? {
        guard let collectionView, let viewportView else { return nil }
        let installationScale = session.lastRenderedScale
        let installationPlane = request.crossfade.outgoingPlane(
            scale: installationScale,
            panDeltaY: session.lastPanDeltaY
        )
        let installationDrift = request.crossfade.driftProgress(
            forScale: installationScale
        )
        let rebase = Self.makeRebase(
            currentTransform: collectionView.transform,
            baseTransform: request.crossfade.transform(
                for: installationPlane,
                viewCenter: CGPoint(
                    x: viewportView.bounds.midX,
                    y: viewportView.bounds.midY
                )
            ),
            installationScale: installationScale,
            driftProgress: installationDrift
        )
        return GridModePlaneContext(request: request, rebase: rebase)
    }

    @discardableResult
    func applyZoomTransform(
        session: GridRenderSession,
        scale: CGFloat,
        panDeltaY: CGFloat,
        sourceLayout: MobilePlayerBrowserLayout
    ) -> Bool {
        guard let collectionView,
              let viewportView,
              let anchor = session.gestureAnchor else {
            return false
        }
        session.sourceLayout = sourceLayout
        session.lastRenderedScale = scale
        let transform = zoomTransform(
            scale: scale,
            panDeltaY: panDeltaY,
            anchor: session.visualAnchor ?? anchor.viewportPoint,
            layout: sourceLayout,
            baseContentOffsetY: anchor.baseContentOffsetY,
            viewportSize: viewportView.bounds.size
        )
        if var rebase = session.zoomRebase {
            collectionView.transform = rebase.applying(
                to: transform,
                scale: scale,
                driftProgress: 0,
                settleProgress: 0
            )
            session.zoomRebase = rebase.progress >= 1 ? nil : rebase
        } else {
            collectionView.transform = transform
        }
        return true
    }

    func installZoomRebase(
        session: GridRenderSession,
        currentTransform: CGAffineTransform,
        scale: CGFloat,
        panDeltaY: CGFloat,
        anchor: CGPoint,
        sourceLayout: MobilePlayerBrowserLayout
    ) {
        guard let viewportView,
              scale.isFinite,
              scale > 0,
              scale != 1,
              let gestureAnchor = session.gestureAnchor else {
            session.zoomRebase = nil
            return
        }
        let baseTransform = zoomTransform(
            scale: scale,
            panDeltaY: panDeltaY,
            anchor: anchor,
            layout: sourceLayout,
            baseContentOffsetY: gestureAnchor.baseContentOffsetY,
            viewportSize: viewportView.bounds.size
        )
        session.zoomRebase = Self.makeRebase(
            currentTransform: currentTransform,
            baseTransform: baseTransform,
            installationScale: scale,
            driftProgress: 0
        )
    }

    func reanchorSettlingRendering(
        session: GridRenderSession,
        at screenPoint: CGPoint
    ) {
        guard let collectionView,
              let viewportView,
              screenPoint.x.isFinite,
              screenPoint.y.isFinite else {
            return
        }
        let currentTransform = collectionView.transform
        let determinant = currentTransform.a * currentTransform.d
            - currentTransform.b * currentTransform.c
        guard determinant.isFinite, abs(determinant) > .ulpOfOne else {
            return
        }
        let pivot = CGPoint(
            x: viewportView.bounds.midX,
            y: viewportView.bounds.midY
        )
        let centeredPoint = CGPoint(
            x: screenPoint.x - pivot.x,
            y: screenPoint.y - pivot.y
        ).applying(currentTransform.inverted())
        let outgoingAnchor = CGPoint(
            x: centeredPoint.x + pivot.x,
            y: centeredPoint.y + pivot.y
        )
        guard let plane = session.plane else {
            session.visualAnchor = outgoingAnchor
            installZoomRebase(
                session: session,
                currentTransform: currentTransform,
                scale: session.lastRenderedScale,
                panDeltaY: session.lastPanDeltaY,
                anchor: outgoingAnchor,
                sourceLayout: session.sourceLayout
            )
            return
        }
        guard let crossfade = plane.crossfade.reanchored(
            outgoingAnchor: outgoingAnchor
        ) else {
            return
        }
        let outgoingPlane = crossfade.outgoingPlane(
            scale: session.lastRenderedScale,
            panDeltaY: session.lastPanDeltaY
        )
        let installationDrift = crossfade.driftProgress(
            forScale: session.lastRenderedScale
        )
        guard installationDrift < 1 || session.lastSettleProgress < 1 else {
            return
        }
        let rebase = Self.makeRebase(
            currentTransform: currentTransform,
            baseTransform: crossfade.transform(
                for: outgoingPlane,
                viewCenter: pivot
            ),
            installationScale: session.lastRenderedScale,
            driftProgress: installationDrift,
            settleProgress: session.lastSettleProgress
        )
        session.visualAnchor = outgoingAnchor
        session.zoomRebase = nil
        session.plane = GridModePlaneContext(
            request: GridModePlaneRequest(
                id: plane.id,
                toMode: plane.toMode,
                layoutAspectState: plane.layoutAspectState,
                anchorTokenIndex: plane.anchorTokenIndex,
                transitionLayout: plane.transitionLayout,
                crossfade: crossfade,
                latticeMap: plane.latticeMap,
                imageDecodeVariant: plane.imageDecodeVariant
            ),
            rebase: rebase
        )
        session.lastPlaneFrameRevision = nil
    }

    static func makeRebase(
        currentTransform: CGAffineTransform,
        baseTransform: CGAffineTransform,
        installationScale: CGFloat,
        driftProgress: CGFloat,
        settleProgress: CGFloat = 0
    ) -> GridModeRebase? {
        let clock: GridModeRebaseClock
        let installationProgress: CGFloat
        if driftProgress >= 1 {
            clock = .destinationEndpoint
            installationProgress = PlayerBrowserGridCrossfade
                .sanitizedProgress(settleProgress)
        } else if driftProgress <= 0, installationScale != 1 {
            clock = .sourceEndpoint(installationScale: installationScale)
            installationProgress = 0
        } else {
            clock = .drift
            installationProgress = driftProgress
        }
        guard let transform = PlayerBrowserGridCrossfadePlaneRebase(
            currentTransform: currentTransform,
            baseTransform: baseTransform,
            installationProgress: installationProgress
        ) else {
            return nil
        }
        return GridModeRebase(
            transform: transform,
            clock: clock,
            progress: installationProgress
        )
    }

    func zoomTransform(
        scale: CGFloat,
        panDeltaY: CGFloat,
        anchor: CGPoint,
        layout: MobilePlayerBrowserLayout,
        baseContentOffsetY: CGFloat,
        viewportSize: CGSize
    ) -> CGAffineTransform {
        let panScreenShiftY = PlayerBrowserGridCrossfade.safePanDeltaY(
            restContentOffsetY: baseContentOffsetY,
            maximumContentOffsetY: max(
                layout.contentSize.height - viewportSize.height,
                0
            ),
            scale: scale,
            panDeltaY: panDeltaY
        )
        return PlayerBrowserGridCrossfade.anchoredScaleTransform(
            scaleX: scale,
            scaleY: scale,
            anchor: anchor,
            translation: CGPoint(x: 0, y: panScreenShiftY),
            viewCenter: CGPoint(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            )
        )
    }

    @discardableResult
    func applyPlaneTransform(
        session: GridRenderSession,
        plane: inout GridModePlaneContext,
        scale: CGFloat,
        settleProgress: CGFloat
    ) -> Bool {
        guard let collectionView, let viewportView else { return false }
        let outgoingPlane = plane.crossfade.outgoingPlane(
            scale: scale,
            panDeltaY: session.lastPanDeltaY
        )
        let driftProgress = plane.crossfade.driftProgress(forScale: scale)
        let baseTransform = plane.crossfade.transform(
            for: outgoingPlane,
            viewCenter: CGPoint(
                x: viewportView.bounds.midX,
                y: viewportView.bounds.midY
            )
        )
        if var rebase = plane.rebase {
            collectionView.transform = rebase.applying(
                to: baseTransform,
                scale: scale,
                driftProgress: driftProgress,
                settleProgress: settleProgress
            )
            plane.rebase = rebase
        } else {
            collectionView.transform = baseTransform
        }
        return true
    }

    func visualGeometry(
        for layout: MobilePlayerBrowserLayout
    ) -> MobilePlayerBrowserVisualLayoutGeometry {
        collectionView?.visualGeometry(for: layout)
            ?? MobilePlayerBrowserVisualLayoutGeometry(
                layout: layout,
                mirrorsHorizontally: false
            )
    }

    func appliedPlaneScale() -> AppliedPlaneScale? {
        guard let transform = collectionView?.transform,
              transform.a.isFinite,
              transform.d.isFinite,
              transform.a > 0,
              transform.d > 0 else {
            return nil
        }
        return AppliedPlaneScale(x: transform.a, y: transform.d)
    }

    func applyCellFrameCorrections(
        session: GridRenderSession,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) {
        guard !session.cellFrameCorrections.isEmpty,
              let context = cellFrameCorrectionTransformContext(
                  session: session,
                  plane: plane,
                  appliedScale: appliedScale
              ) else {
            for (cell, _) in session.cellFrameCorrections.values {
                setTransform(.identity, on: cell)
            }
            session.hasCellFrameCorrectionTransforms = false
            return
        }
        var hasTransforms = false
        for (cell, correction) in session.cellFrameCorrections.values {
            let applied = applyCellFrameCorrection(
                correction,
                to: cell,
                context: context
            )
            if !applied {
                setTransform(.identity, on: cell)
            }
            hasTransforms = applied || hasTransforms
        }
        session.hasCellFrameCorrectionTransforms = hasTransforms
    }

    func cellFrameCorrectionGeometry(
        session: GridRenderSession,
        plane: GridModePlaneContext
    ) -> GridModeCellFrameCorrectionGeometry? {
        guard let collectionView, let viewportView else { return nil }
        let currentTransform = collectionView.transform
        guard currentTransform.a != 0, currentTransform.d != 0 else {
            return nil
        }
        let terminalPlane = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        )
        let pivot = CGPoint(
            x: viewportView.bounds.midX,
            y: viewportView.bounds.midY
        )
        let terminalTransform = plane.crossfade.transform(
            for: terminalPlane,
            viewCenter: pivot
        )
        let currentToTerminal = CGAffineTransform(
            translationX: -pivot.x,
            y: -pivot.y
        )
        .concatenating(currentTransform.inverted())
        .concatenating(terminalTransform)
        .concatenating(CGAffineTransform(
            translationX: pivot.x,
            y: pivot.y
        ))
        return GridModeCellFrameCorrectionGeometry(
            currentToTerminal: currentToTerminal,
            terminalScreenOffsetY: terminalPlane.incomingContentOffsetY,
            destinationGeometry: visualGeometry(
                for: plane.transitionLayout.toLayout
            )
        )
    }

    func cellFrameCorrection(
        for cell: UICollectionViewCell,
        destinationItem: Int,
        geometry: GridModeCellFrameCorrectionGeometry,
        settleProgress: CGFloat
    ) -> GridModeCellFrameCorrection? {
        guard let viewportView,
              let superview = cell.superview,
              let destinationScreenFrame = destinationScreenFrame(
                  destinationItem: destinationItem,
                  geometry: geometry
              ) else {
            return nil
        }
        let currentScreenFrame = superview.convert(
            CGRect(
                x: cell.center.x - cell.bounds.width / 2,
                y: cell.center.y - cell.bounds.height / 2,
                width: cell.bounds.width,
                height: cell.bounds.height
            ),
            to: viewportView
        )
        let terminalScreenFrame = currentScreenFrame.applying(
            geometry.currentToTerminal
        )
        let centerDelta = CGPoint(
            x: destinationScreenFrame.midX - terminalScreenFrame.midX,
            y: destinationScreenFrame.midY - terminalScreenFrame.midY
        )
        let sizeDelta = CGSize(
            width: destinationScreenFrame.width - terminalScreenFrame.width,
            height: destinationScreenFrame.height - terminalScreenFrame.height
        )
        let destinationEdgeVisibilityProgress = edgeVisibilityProgress(
            of: destinationScreenFrame,
            in: viewportView.bounds,
            settleProgress: settleProgress
        )
        let retirementStart = PlayerBrowserGridCrossfade
            .contentFadeEndSettleProgress
        let retirementProgress = PlayerBrowserGridCrossfade
            .sanitizedProgress(
                (settleProgress - retirementStart)
                    / (1 - retirementStart)
            )
        let terminalRetirementVisibilityProgress = retirementProgress
            * edgeVisibilityProgress(
                of: terminalScreenFrame,
                in: viewportView.bounds,
                settleProgress: settleProgress
            )
        let destinationVisibilityProgress = max(
            destinationEdgeVisibilityProgress,
            terminalRetirementVisibilityProgress
        )
        guard centerDelta.x.isFinite,
              centerDelta.y.isFinite,
              sizeDelta.width.isFinite,
              sizeDelta.height.isFinite else {
            return nil
        }
        return GridModeCellFrameCorrection(
            centerDelta: centerDelta,
            sizeDelta: sizeDelta,
            destinationVisibilityProgress: destinationVisibilityProgress
        )
    }

    @discardableResult
    func applyCellFrameCorrection(
        _ correction: GridModeCellFrameCorrection,
        to cell: UICollectionViewCell,
        session: GridRenderSession,
        plane: GridModePlaneContext
    ) -> Bool {
        guard let appliedScale = appliedPlaneScale(),
              let context = cellFrameCorrectionTransformContext(
                  session: session,
                  plane: plane,
                  appliedScale: appliedScale
              ),
              applyCellFrameCorrection(
                  correction,
                  to: cell,
                  context: context
              ) else {
            setTransform(.identity, on: cell)
            return false
        }
        return true
    }

    func removeCellFrameCorrection(
        session: GridRenderSession,
        for cell: UICollectionViewCell
    ) {
        removeCellFrameCorrections(session: session, for: [cell])
    }

    func removeCellFrameCorrections<Cells: Sequence>(
        session: GridRenderSession,
        for cells: Cells
    ) where Cells.Element: UICollectionViewCell {
        let cells = Array(cells)
        let cellIDs = Set(cells.map(ObjectIdentifier.init))
        guard !cellIDs.isEmpty else { return }
        session.dropCellFrameCorrections(for: cellIDs)
        for cell in cells {
            setTransform(.identity, on: cell)
        }
        guard let plane = session.plane,
              let appliedScale = appliedPlaneScale(),
              let compensation = sourceSeamCompensation(
                  session: session,
                  plane: plane,
                  appliedScale: appliedScale
              ) else {
            return
        }
        for cell in cells {
            let representationID = ObjectIdentifier(cell)
            guard session.cachedSourceRepresentations[representationID]?
                .cell === cell,
                  cell.superview != nil else {
                continue
            }
            if applySeamCompensation(
                to: cell,
                compensation: compensation
            ) {
                session.hasSourceSeamCompensationTransforms = true
            }
        }
    }

    func sourceSeamCompensation(
        session: GridRenderSession,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        sourceSeamCompensation(
            naturalSpacing:
                plane.transitionLayout.fromLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            ),
            appliedScale: appliedScale
        )
    }

    func noPlaneSourceSeamCompensation(
        session: GridRenderSession,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        sourceSeamCompensation(
            naturalSpacing: session.sourceLayout.interItemSpacing,
            targetSpacing: session.sourceLayout.interItemSpacing,
            appliedScale: appliedScale
        )
    }

    func currentSourceSeamCompensation(
        session: GridRenderSession,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        guard let plane = session.plane else {
            return noPlaneSourceSeamCompensation(
                session: session,
                appliedScale: appliedScale
            )
        }
        return sourceSeamCompensation(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        )
    }

    func phantomSeamCompensation(
        session: GridRenderSession,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        let terminal = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        )
        guard terminal.scaleX != 0, terminal.scaleY != 0 else { return nil }
        return SeamCompensation(
            naturalSpacing:
                plane.transitionLayout.toLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            ),
            relativeScaleX: appliedScale.x / terminal.scaleX,
            relativeScaleY: appliedScale.y / terminal.scaleY,
            appliedScale: appliedScale
        )
    }

    func applySeamCompensations(
        session: GridRenderSession,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) {
        if let phantomCompensation = phantomSeamCompensation(
            session: session,
            plane: plane,
            appliedScale: appliedScale
        ) {
            for phantom in session.phantomCells.values
            where phantom.superview != nil {
                if applySeamCompensation(
                    to: phantom,
                    compensation: phantomCompensation
                ) {
                    session.hasPhantomSeamCompensationTransforms = true
                }
            }
        } else {
            clearPhantomSeamCompensation(session: session)
        }
        applySourceSeamCompensations(
            session: session,
            naturalSpacing:
                plane.transitionLayout.fromLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            ),
            appliedScale: appliedScale
        )
        refreshPhantomShapeStructure(session: session)
    }

    func applySourceSeamCompensations(
        session: GridRenderSession,
        naturalSpacing: CGFloat,
        targetSpacing: CGFloat,
        appliedScale: AppliedPlaneScale
    ) {
        guard let compensation = sourceSeamCompensation(
            naturalSpacing: naturalSpacing,
            targetSpacing: targetSpacing,
            appliedScale: appliedScale
        ) else {
            clearSourceSeamCompensation(session: session)
            return
        }
        var hasTransforms = false
        for (representationID, representation) in
            session.cachedSourceRepresentations
        where session.cellFrameCorrections[representationID] == nil
            && representation.cell.superview != nil
            && representation.cell.represents(
                tokenIndex: representation.itemIndex
            ) {
            hasTransforms = applySeamCompensation(
                to: representation.cell,
                compensation: compensation
            ) || hasTransforms
        }
        session.hasSourceSeamCompensationTransforms = hasTransforms
    }

    func applyNoPlaneSourceSeamCompensation(
        session: GridRenderSession,
        to cell: MobilePlayerCollectionBrowserCell
    ) {
        guard session.plane == nil,
              let appliedScale = appliedPlaneScale(),
              let compensation = noPlaneSourceSeamCompensation(
                  session: session,
                  appliedScale: appliedScale
              ) else {
            setTransform(.identity, on: cell)
            return
        }
        if applySeamCompensation(to: cell, compensation: compensation) {
            session.hasSourceSeamCompensationTransforms = true
        }
    }

    func currentPhantomShapeFrameCompensation(
        session: GridRenderSession
    ) -> PhantomShapeFrameCompensation? {
        guard let appliedScale = appliedPlaneScale() else {
            return nil
        }
        let compensation: SeamCompensation?
        if let plane = session.plane {
            compensation = phantomSeamCompensation(
                session: session,
                plane: plane,
                appliedScale: appliedScale
            )
        } else {
            compensation = noPlaneSourceSeamCompensation(
                session: session,
                appliedScale: appliedScale
            )
        }
        guard let compensation else { return nil }
        return PhantomShapeFrameCompensation(
            excessX: compensation.excessX,
            excessY: compensation.excessY,
            appliedScaleX: compensation.appliedScale.x,
            appliedScaleY: compensation.appliedScale.y,
            minimumScaleFactor: SeamCompensation.minimumScaleFactor
        )
    }

    func replacePhantomShapeCoverage(
        session: GridRenderSession,
        plan: PlayerBrowserGridPhantomPlan,
        installedItemIndices: Set<Int>
    ) {
        let pendingCandidates = plan.cellCandidates.filter {
            !installedItemIndices.contains($0.destinationItemIndex)
        }
        guard let shapeCoverage = plan.shapeCoverage else {
            replacePhantomShapeCoverage(
                session: session,
                candidates: pendingCandidates + plan.shapeCandidates,
                shapeCoverage: nil
            )
            return
        }
        let pendingFrames = pendingCandidates.map(\.sourceFrame)
        let excludedFrames = shapeCoverage.excludedFrames.filter {
            !pendingFrames.contains($0)
        }
        replacePhantomShapeCoverage(
            session: session,
            candidates: plan.shapeCandidates,
            shapeCoverage: shapeCoverage.replacingExcludedFrames(
                excludedFrames
            )
        )
    }

    func refreshPhantomShapeStructure(session: GridRenderSession) {
        guard let placeholderView = session.phantomShapeView
            as? PhantomShapeView else {
            return
        }
        renderPhantomShapeStructure(
            session: session,
            in: placeholderView,
            rebuildsTopology: false
        )
    }

    func refreshPhantomShapeExclusionMask(session: GridRenderSession) {
        session.phantomShapeMaskIsDirty = true
        guard !session.defersPhantomShapeMaskCommits else { return }
        commitPhantomShapeExclusionMask(session: session)
    }

    func commitPhantomShapeExclusionMask(session: GridRenderSession) {
        guard session.phantomShapeMaskIsDirty else { return }
        defer { session.phantomShapeMaskIsDirty = false }
#if DEBUG
        phantomShapeMaskCommitAttemptCount += 1
#endif
        guard let placeholderView = session.phantomShapeView
            as? PhantomShapeView,
              let coverageBounds = placeholderView.renderedCoverageBounds
        else {
            return
        }
        let occupantFrames = phantomShapeOccupantFrames(session: session)
        guard placeholderView.renderedOccupantFrames != occupantFrames
            || placeholderView.maskedCoverageBounds != coverageBounds else {
            return
        }
        let signpostState = gridPlaneRendererSignposter.beginInterval(
            "PhantomMaskCommit"
        )
        defer {
            gridPlaneRendererSignposter.endInterval(
                "PhantomMaskCommit",
                signpostState
            )
        }
        phantomShapeMaskBuildCount += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        placeholderView.renderedOccupantFrames = occupantFrames
        placeholderView.maskedCoverageBounds = coverageBounds
        let hasShapeExclusions = placeholderView
            .renderedShapeExclusionPath != nil
        guard hasShapeExclusions || !occupantFrames.isEmpty else {
            placeholderView.layer.mask = nil
            return
        }
        placeholderView.exclusionMaskLayer.frame = placeholderView.bounds
        placeholderView.exclusionMaskLayer.path = placeholderView
            .renderedShapeExclusionPath
                ?? PhantomShapePathRenderer.exclusionMaskPath(
                    exclusionPath: nil,
                    maskBounds: placeholderView.bounds
                )
        placeholderView.exclusionMaskLayer.fillRule = .evenOdd
        placeholderView.exclusionMaskLayer.fillColor = UIColor.white.cgColor
        if occupantFrames.isEmpty {
            placeholderView.exclusionMaskLayer.mask = nil
        } else {
            let occupantFrameValues = occupantFrames.values.sorted {
                lhs, rhs in
                lhs.minY == rhs.minY
                    ? lhs.minX < rhs.minX
                    : lhs.minY < rhs.minY
            }
            let occupantPath = PhantomShapePathRenderer.path(
                frames: occupantFrameValues,
                relativeTo: coverageBounds
            )
            let normalizedOccupantPath = PhantomShapePathRenderer
                .hasOverlappingVerticallySortedFrames(occupantFrameValues)
                ? occupantPath.normalized(using: .winding)
                : occupantPath
            placeholderView.occupantExclusionMaskLayer.frame =
                placeholderView.exclusionMaskLayer.bounds
            placeholderView.occupantExclusionMaskLayer.path =
                PhantomShapePathRenderer.exclusionMaskPath(
                    exclusionPath: normalizedOccupantPath,
                    maskBounds: placeholderView.bounds
                )
            placeholderView.occupantExclusionMaskLayer.fillRule = .evenOdd
            placeholderView.occupantExclusionMaskLayer.fillColor =
                UIColor.white.cgColor
            placeholderView.exclusionMaskLayer.mask =
                placeholderView.occupantExclusionMaskLayer
        }
        placeholderView.layer.mask = placeholderView.exclusionMaskLayer
    }

    private var visibleBrowserCells: [MobilePlayerCollectionBrowserCell] {
        collectionView?.visibleCells.compactMap {
            $0 as? MobilePlayerCollectionBrowserCell
        } ?? []
    }

    private func phantomShapeOccupantFrames(
        session: GridRenderSession
    ) -> [PhantomShapeOccupantKey: CGRect] {
        guard let collectionView else { return [:] }
        var frames = [PhantomShapeOccupantKey: CGRect]()
        if session.plane == nil {
            for (itemIndex, cell) in session.sourceOverscanCells
            where cell.superview != nil
                && cell.represents(tokenIndex: itemIndex) {
                frames[.source(ObjectIdentifier(cell))] = cell.convert(
                    cell.bounds,
                    to: collectionView
                )
            }
            for cell in visibleBrowserCells {
                guard let indexPath = collectionView.indexPath(for: cell),
                      cell.represents(tokenIndex: indexPath.item) else {
                    continue
                }
                frames[.source(ObjectIdentifier(cell))] = cell.convert(
                    cell.bounds,
                    to: collectionView
                )
            }
            return frames
        }
        for (itemIndex, cell) in session.phantomCells
        where cell.superview != nil && cell.represents(tokenIndex: itemIndex) {
            frames[.phantom(itemIndex)] = cell.convert(
                cell.bounds,
                to: collectionView
            )
        }
        let transitionVisualRepresentationIDs = Set(
            session.sourceCoverage.readyDestinationByRepresentation.keys
        ).union(
            session.cellFrameCorrections.keys
        ).filter {
            session.sourceRepresentationOwnsTransitionVisual($0)
        }
        let sourceOccupantRepresentationIDs = transitionVisualRepresentationIDs
            .union(session.marginCoverageRepresentationIDs)
        for representationID in sourceOccupantRepresentationIDs {
            guard let representation = session.cachedSourceRepresentations[
                representationID
            ], representation.cell.superview != nil,
            representation.cell.represents(
                tokenIndex: representation.itemIndex
            ) else {
                continue
            }
            frames[.source(representationID)] = representation.cell.convert(
                representation.cell.bounds,
                to: collectionView
            )
        }
        return frames
    }

    private func replacePhantomShapeCoverage(
        session: GridRenderSession,
        candidates: [PlayerBrowserGridPhantomCandidate],
        shapeCoverage: PlayerBrowserGridPhantomShapeCoverage?
    ) {
        guard let collectionView else { return }
        guard !candidates.isEmpty || shapeCoverage?.coverageBounds != nil else {
            if let placeholderView = session.phantomShapeView
                as? PhantomShapeView {
                placeholderView.rawCandidateFrames.removeAll(
                    keepingCapacity: true
                )
                placeholderView.rawShapeCoverage = nil
                placeholderView.renderedCoverageBounds = nil
                placeholderView.renderedShapeExclusionFrames.removeAll(
                    keepingCapacity: true
                )
                placeholderView.renderedShapeExclusionPath = nil
                placeholderView.maskedCoverageBounds = nil
                placeholderView.renderedOccupantFrames.removeAll(
                    keepingCapacity: true
                )
                placeholderView.layer.mask = nil
                placeholderView.isHidden = true
            }
            return
        }
        let placeholderView: PhantomShapeView
        if let existingView = session.phantomShapeView as? PhantomShapeView {
            placeholderView = existingView
        } else {
            session.phantomShapeView?.removeFromSuperview()
            placeholderView = PhantomShapeView(frame: .zero)
            session.phantomShapeView = placeholderView
        }
        placeholderView.rawCandidateFrames = candidates.map(\.sourceFrame)
        placeholderView.rawShapeCoverage = shapeCoverage
        if placeholderView.superview !== collectionView
            || collectionView.subviews.first !== placeholderView {
            collectionView.insertSubview(placeholderView, at: 0)
        }
        renderPhantomShapeStructure(
            session: session,
            in: placeholderView,
            rebuildsTopology: true
        )
        refreshPhantomShapeExclusionMask(session: session)
    }

    private func renderPhantomShapeStructure(
        session: GridRenderSession,
        in placeholderView: PhantomShapeView,
        rebuildsTopology: Bool
    ) {
        let frameCompensation = currentPhantomShapeFrameCompensation(
            session: session
        )
        guard rebuildsTopology || placeholderView.renderedFrameCompensation
            != frameCompensation else {
            return
        }
        phantomShapeStructureBuildCount += 1
        let candidateFrames = placeholderView.rawCandidateFrames.map {
            frameCompensation?.applying(to: $0) ?? $0
        }
        let candidateBounds = candidateFrames.first.map { first in
            candidateFrames.dropFirst().reduce(first) { $0.union($1) }
        }
        let shapeBounds = placeholderView.rawShapeCoverage?.coverageBounds.map {
            frameCompensation?.applying(to: $0) ?? $0
        }
        let shapeExclusionFrames = placeholderView.rawShapeCoverage?
            .excludedFrames.map {
                frameCompensation?.applying(to: $0) ?? $0
            } ?? []
        let coverageBounds: CGRect
        if let candidateBounds, let shapeBounds {
            coverageBounds = candidateBounds.union(shapeBounds)
        } else if let candidateBounds {
            coverageBounds = candidateBounds
        } else if let shapeBounds {
            coverageBounds = shapeBounds
        } else {
            placeholderView.isHidden = true
            placeholderView.renderedFrameCompensation = frameCompensation
            placeholderView.renderedCoverageBounds = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        placeholderView.isHidden = false
        placeholderView.frame = coverageBounds
        if placeholderView.renderedShapeExclusionFrames
            != shapeExclusionFrames {
            placeholderView.maskedCoverageBounds = nil
        }
        placeholderView.renderedShapeExclusionFrames = shapeExclusionFrames
        if shapeExclusionFrames.isEmpty {
            placeholderView.renderedShapeExclusionPath = nil
        } else {
            let exclusionPath = PhantomShapePathRenderer.path(
                frames: shapeExclusionFrames,
                relativeTo: coverageBounds
            )
            placeholderView.renderedShapeExclusionPath =
                PhantomShapePathRenderer.exclusionMaskPath(
                    exclusionPath: exclusionPath,
                    maskBounds: placeholderView.bounds
                )
        }
        if rebuildsTopology {
            placeholderView.reset(
                fillColor: mobilePlayerBrowserPlaceholderToneColor.cgColor
            )
            placeholderView.renderedOccupantFrames.removeAll(
                keepingCapacity: true
            )
            placeholderView.maskedCoverageBounds = nil
        }
        if let shapeCoverage = placeholderView.rawShapeCoverage {
            installPhantomShapeCoverage(
                shapeCoverage,
                coverageBounds: coverageBounds,
                in: placeholderView,
                frameCompensation: frameCompensation,
                configuresTopology: rebuildsTopology
            )
        }
        if !candidateFrames.isEmpty {
            if rebuildsTopology {
                placeholderView.candidateLayer.isHidden = false
            }
            placeholderView.candidateLayer.frame = placeholderView.bounds
            placeholderView.candidateLayer.path = PhantomShapePathRenderer.path(
                frames: candidateFrames,
                relativeTo: coverageBounds
            )
        }
        placeholderView.renderedFrameCompensation = frameCompensation
        placeholderView.renderedCoverageBounds = coverageBounds
    }

    private func installPhantomShapeCoverage(
        _ coverage: PlayerBrowserGridPhantomShapeCoverage,
        coverageBounds: CGRect,
        in placeholderView: PhantomShapeView,
        frameCompensation: PhantomShapeFrameCompensation?,
        configuresTopology: Bool
    ) {
        let adjustedFrame: (CGRect) -> CGRect = { frame in
            frameCompensation?.applying(to: frame) ?? frame
        }
        switch coverage {
        case let .repeatedRows(rows):
            let firstRowFrames = rows.firstRowFrames.map(adjustedFrame)
            if rows.rowCount > 0, let firstFrame = firstRowFrames.first {
                let rowBounds = firstRowFrames.dropFirst().reduce(
                    firstFrame
                ) { $0.union($1) }
                if configuresTopology {
                    placeholderView.repeatedRowsLayer.isHidden = false
                    placeholderView.repeatedRowsLayer.masksToBounds = true
                    placeholderView.repeatedRowsLayer.instanceCount =
                        rows.rowCount
                    placeholderView.repeatedRowsLayer.instanceTransform =
                        CATransform3DMakeTranslation(0, rows.rowPitch, 0)
                }
                placeholderView.repeatedRowsLayer.frame =
                    placeholderView.bounds
                placeholderView.repeatedRowLayer.frame = rowBounds.offsetBy(
                    dx: -coverageBounds.minX,
                    dy: -coverageBounds.minY
                )
                placeholderView.repeatedRowLayer.path =
                    PhantomShapePathRenderer.path(
                        frames: firstRowFrames,
                        relativeTo: rowBounds
                    )
            }
            let finalRowFrames = rows.finalRowFrames.map(adjustedFrame)
            if !finalRowFrames.isEmpty {
                if configuresTopology {
                    placeholderView.finalRowLayer.isHidden = false
                }
                placeholderView.finalRowLayer.frame = placeholderView.bounds
                placeholderView.finalRowLayer.path =
                    PhantomShapePathRenderer.path(
                        frames: finalRowFrames,
                        relativeTo: coverageBounds
                    )
            }
        case let .solid(solidCoverage):
            if configuresTopology {
                placeholderView.solidCoverageLayer.isHidden = false
            }
            placeholderView.solidCoverageLayer.frame = placeholderView.bounds
            placeholderView.solidCoverageLayer.path =
                PhantomShapePathRenderer.path(
                    frames: [adjustedFrame(solidCoverage.frame)],
                    relativeTo: coverageBounds
                )
        }
    }

    func clearPhantomSeamCompensation(session: GridRenderSession) {
        guard session.hasPhantomSeamCompensationTransforms else { return }
        session.hasPhantomSeamCompensationTransforms = false
        for phantom in session.phantomCells.values {
            setTransform(.identity, on: phantom)
        }
    }

    func clearSourceSeamCompensation(session: GridRenderSession) {
        guard session.hasSourceSeamCompensationTransforms else { return }
        session.hasSourceSeamCompensationTransforms = false
        for (representationID, representation) in
            session.cachedSourceRepresentations
        where session.cellFrameCorrections[representationID] == nil
            && representation.cell.superview != nil
            && representation.cell.represents(
                tokenIndex: representation.itemIndex
            ) {
            setTransform(.identity, on: representation.cell)
        }
    }

    @discardableResult
    func applySeamCompensation(
        to cell: UICollectionViewCell,
        compensation: SeamCompensation
    ) -> Bool {
        let screenWidth = cell.bounds.width * compensation.appliedScale.x
        let screenHeight = cell.bounds.height * compensation.appliedScale.y
        guard screenWidth > 0, screenHeight > 0 else { return false }
        setTransform(
            CGAffineTransform(
                scaleX: max(
                    1 + compensation.excessX / screenWidth,
                    SeamCompensation.minimumScaleFactor
                ),
                y: max(
                    1 + compensation.excessY / screenHeight,
                    SeamCompensation.minimumScaleFactor
                )
            ),
            on: cell
        )
        return true
    }

    func setTransform(
        _ transform: CGAffineTransform,
        on cell: UICollectionViewCell
    ) {
        guard cell.transform != transform else { return }
        cell.transform = transform
    }

    private func setSourceCellAlpha(
        _ alpha: CGFloat,
        on cell: UICollectionViewCell
    ) {
        guard cell.alpha != alpha else { return }
        cell.alpha = alpha
    }

    private func cellFrameCorrectionTransformContext(
        session: GridRenderSession,
        plane: GridModePlaneContext,
        appliedScale: AppliedPlaneScale
    ) -> CellFrameCorrectionTransformContext? {
        let terminalPlane = plane.terminalOutgoingPlane(
            panDeltaY: session.lastPanDeltaY
        )
        guard terminalPlane.scaleX.isFinite,
              terminalPlane.scaleY.isFinite,
              terminalPlane.scaleX > 0,
              terminalPlane.scaleY > 0 else {
            return nil
        }
        return CellFrameCorrectionTransformContext(
            settleProgress: session.lastSettleProgress,
            appliedScale: appliedScale,
            terminalScale: AppliedPlaneScale(
                x: terminalPlane.scaleX,
                y: terminalPlane.scaleY
            ),
            sourceSpacing:
                plane.transitionLayout.fromLayout.interItemSpacing,
            destinationSpacing:
                plane.transitionLayout.toLayout.interItemSpacing,
            targetSpacing: transitionSeamSpacing(
                session: session,
                plane: plane
            )
        )
    }

    private func applyCellFrameCorrection(
        _ correction: GridModeCellFrameCorrection,
        to cell: UICollectionViewCell,
        context: CellFrameCorrectionTransformContext
    ) -> Bool {
        let progress = context.settleProgress
            * correction.destinationVisibilityProgress
        let screenWidth = cell.bounds.width * context.appliedScale.x
        let screenHeight = cell.bounds.height * context.appliedScale.y
        let seamExcessX = context.sourceSpacing * context.appliedScale.x
            + progress * (
                context.destinationSpacing
                    - context.sourceSpacing * context.terminalScale.x
            ) - context.targetSpacing
        let seamExcessY = context.sourceSpacing * context.appliedScale.y
            + progress * (
                context.destinationSpacing
                    - context.sourceSpacing * context.terminalScale.y
            ) - context.targetSpacing
        let scaleX = screenWidth > 0
            ? 1 + (
                progress * correction.sizeDelta.width + seamExcessX
            ) / screenWidth
            : 1
        let scaleY = screenHeight > 0
            ? 1 + (
                progress * correction.sizeDelta.height + seamExcessY
            ) / screenHeight
            : 1
        let transform = CGAffineTransform(
            translationX: progress * correction.centerDelta.x
                / context.appliedScale.x,
            y: progress * correction.centerDelta.y
                / context.appliedScale.y
        ).scaledBy(x: scaleX, y: scaleY)
        guard transform.a.isFinite,
              transform.b.isFinite,
              transform.c.isFinite,
              transform.d.isFinite,
              transform.tx.isFinite,
              transform.ty.isFinite else {
            return false
        }
        setTransform(transform, on: cell)
        return transform != .identity
    }

    func sourceSeamCompensation(
        naturalSpacing: CGFloat,
        targetSpacing: CGFloat,
        appliedScale: AppliedPlaneScale
    ) -> SeamCompensation? {
        SeamCompensation(
            naturalSpacing: naturalSpacing,
            targetSpacing: targetSpacing,
            relativeScaleX: appliedScale.x,
            relativeScaleY: appliedScale.y,
            appliedScale: appliedScale
        )
    }

    private func transitionSeamSpacing(
        session: GridRenderSession,
        plane: GridModePlaneContext
    ) -> CGFloat {
        let sourceSpacing = plane.transitionLayout.fromLayout.interItemSpacing
        let destinationSpacing = plane.transitionLayout.toLayout.interItemSpacing
        let progress = plane.crossfade.driftProgress(
            forScale: session.lastRenderedScale
        )
        return sourceSpacing
            + (destinationSpacing - sourceSpacing)
                * progress
    }

    private func edgeVisibilityProgress(
        of frame: CGRect,
        in viewportBounds: CGRect,
        settleProgress: CGFloat
    ) -> CGFloat {
        guard let visibleRect = PlayerBrowserGridGeometry.visibleRect(
            frame,
            clippedTo: viewportBounds
        ) else {
            return 0
        }
        let handoffDistance = min(
            Self.edgeHandoffDistance * (1 - settleProgress),
            min(frame.width, frame.height)
        )
        guard handoffDistance > 0 else { return 1 }
        return PlayerBrowserGridCrossfade.sanitizedProgress(
            min(visibleRect.width, visibleRect.height) / handoffDistance
        )
    }

    private func destinationScreenFrame(
        destinationItem: Int,
        geometry: GridModeCellFrameCorrectionGeometry
    ) -> CGRect? {
        guard let collectionView,
              let destinationFrame = geometry.destinationGeometry.itemFrame(
                  at: destinationItem
              ) else {
            return nil
        }
        return destinationFrame.offsetBy(
            dx: -collectionView.contentOffset.x,
            dy: -geometry.terminalScreenOffsetY
        )
    }
}
