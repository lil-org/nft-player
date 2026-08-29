// ∅ 2026 lil org

import QuartzCore
import UIKit

extension GridPlaneRenderer {
    enum PhantomShapeOccupantKey: Hashable {
        case phantom(Int)
        case source(ObjectIdentifier)
    }

    final class PhantomShapeView: UIView {
        let repeatedRowLayer = CAShapeLayer()
        let repeatedRowsLayer = CAReplicatorLayer()
        let finalRowLayer = CAShapeLayer()
        let solidCoverageLayer = CAShapeLayer()
        let candidateLayer = CAShapeLayer()
        let exclusionMaskLayer = CAShapeLayer()
        let occupantExclusionMaskLayer = CAShapeLayer()
        var rawCandidateFrames = [CGRect]()
        var rawShapeCoverage: PlayerBrowserGridPhantomShapeCoverage?
        var renderedFrameCompensation: PhantomShapeFrameCompensation?
        var renderedCoverageBounds: CGRect?
        var renderedShapeExclusionFrames = [CGRect]()
        var renderedShapeExclusionPath: CGPath?
        var maskedCoverageBounds: CGRect?
        var renderedOccupantFrames = [PhantomShapeOccupantKey: CGRect]()

        override init(frame: CGRect) {
            super.init(frame: frame)
            makeBackgroundTransparent()
            isUserInteractionEnabled = false
            repeatedRowsLayer.addSublayer(repeatedRowLayer)
            layer.addSublayer(repeatedRowsLayer)
            layer.addSublayer(finalRowLayer)
            layer.addSublayer(solidCoverageLayer)
            layer.addSublayer(candidateLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError()
        }

        func reset(fillColor: CGColor) {
            repeatedRowsLayer.isHidden = true
            repeatedRowsLayer.instanceCount = 0
            repeatedRowLayer.path = nil
            finalRowLayer.isHidden = true
            finalRowLayer.path = nil
            solidCoverageLayer.isHidden = true
            solidCoverageLayer.path = nil
            candidateLayer.isHidden = true
            candidateLayer.path = nil
            layer.mask = nil
            exclusionMaskLayer.mask = nil
            occupantExclusionMaskLayer.path = nil
            for shapeLayer in [
                repeatedRowLayer,
                finalRowLayer,
                solidCoverageLayer,
                candidateLayer
            ] {
                shapeLayer.fillColor = fillColor
            }
        }
    }

    enum PhantomShapePathRenderer {
        static func exclusionMaskPath(
            exclusionPath: CGPath?,
            maskBounds: CGRect
        ) -> CGPath {
            let path = CGMutablePath()
            path.addRect(maskBounds)
            if let exclusionPath {
                path.addPath(exclusionPath)
            }
            return path
        }

        static func path<Frames: Sequence>(
            frames: Frames,
            relativeTo bounds: CGRect
        ) -> CGPath where Frames.Element == CGRect {
            let path = CGMutablePath()
            for frame in frames {
                path.addRect(frame.offsetBy(
                    dx: -bounds.minX,
                    dy: -bounds.minY
                ))
            }
            return path
        }

        static func hasOverlappingVerticallySortedFrames(
            _ frames: [CGRect]
        ) -> Bool {
            guard frames.count > 1 else { return false }
            for index in frames.indices.dropLast() {
                let frame = frames[index]
                for otherFrame in frames[(index + 1)...] {
                    if otherFrame.minY >= frame.maxY {
                        break
                    }
                    if frame.intersects(otherFrame) {
                        return true
                    }
                }
            }
            return false
        }
    }
}
