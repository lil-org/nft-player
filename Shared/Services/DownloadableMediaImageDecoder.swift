// ∅ 2026 lil org

import CoreGraphics
import Foundation
import ImageIO

#if os(macOS)
import AppKit
#else
import UIKit
#endif

actor DownloadableMediaImageDecoder: DownloadableMediaVariantImageDecoding {
    func decode(
        at fileURL: URL,
        variant: DownloadableMediaImageDecodeVariant = .full,
        generation: DownloadableMediaImageDecodeGeneration
    ) async -> DownloadableMediaDecodedImageTransfer? {
        guard generation.beginIfCurrent() else { return nil }

        return autoreleasepool {
            guard let decoded = Self.decodeImage(at: fileURL, variant: variant) else {
                return DownloadableMediaDecodedImageTransfer(image: nil)
            }
            return DownloadableMediaDecodedImageTransfer(
                image: decoded.image,
                variant: decoded.variant
            )
        }
    }

    nonisolated private static func decodeImage(
        at fileURL: URL,
        variant: DownloadableMediaImageDecodeVariant
    ) -> DownloadableMediaImageEntry? {
        switch variant.normalized {
        case .full:
            return decodeFullImage(at: fileURL)
        case let .downsampled(maxPixelWidth):
            return decodeDownsampledImage(
                at: fileURL,
                maxPixelWidth: maxPixelWidth
            ) { source, options in
                CGImageSourceCreateThumbnailAtIndex(source, 0, options)
            }
        }
    }

    nonisolated private static func decodeDownsampledImage(
        at fileURL: URL,
        maxPixelWidth: Int,
        createThumbnail: (CGImageSource, CFDictionary) -> CGImage?
    ) -> DownloadableMediaImageEntry? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(
            fileURL as CFURL,
            sourceOptions
        ),
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            sourceOptions
        ) as? [CFString: Any],
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
        pixelWidth > 0,
        pixelHeight > 0 else {
            return decodeFullImage(at: fileURL)
        }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32
        let displayedPixelWidth: CGFloat
        switch orientation {
        case 5, 6, 7, 8:
            displayedPixelWidth = pixelHeight
        default:
            displayedPixelWidth = pixelWidth
        }
        guard displayedPixelWidth > CGFloat(maxPixelWidth) else {
            return decodeFullImage(at: fileURL)
        }
        let scale = CGFloat(maxPixelWidth) / displayedPixelWidth
        let maximumPixelSize = max(
            Int((pixelWidth * scale).rounded(.up)),
            Int((pixelHeight * scale).rounded(.up))
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = createThumbnail(
            source,
            options as CFDictionary
        ) else {
            return decodeFullImage(at: fileURL)
        }
#if os(macOS)
        return DownloadableMediaImageEntry(
            image: NSImage(cgImage: image, size: NSSize(
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )),
            variant: .downsampled(maxPixelWidth: maxPixelWidth)
        )
#else
        return DownloadableMediaImageEntry(
            image: UIImage(cgImage: image, scale: 1, orientation: .up),
            variant: .downsampled(maxPixelWidth: maxPixelWidth)
        )
#endif
    }

#if DEBUG
    nonisolated static func decodeDownsampledImageWithFailedThumbnailForTesting(
        at fileURL: URL,
        maxPixelWidth: Int
    ) -> DownloadableMediaImageEntry? {
        decodeDownsampledImage(
            at: fileURL,
            maxPixelWidth: maxPixelWidth
        ) { _, _ in nil }
    }
#endif

    nonisolated private static func decodeFullImage(
        at fileURL: URL
    ) -> DownloadableMediaImageEntry? {
        guard let image = DownloadableMediaImage(
            contentsOfFile: fileURL.path
        ) else { return nil }
        return DownloadableMediaImageEntry(
            image: image.downloadableMediaDecodedForDisplay(),
            variant: .full
        )
    }
}

#if os(macOS)
private extension NSImage {
    nonisolated func downloadableMediaDecodedForDisplay() -> NSImage {
        guard isValid, size.width > 0, size.height > 0 else { return self }

        guard let cgImage = cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ),
        let context = CGContext(
            data: nil,
            width: max(cgImage.width, 1),
            height: max(cgImage.height, 1),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self
        }

        context.draw(
            cgImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: cgImage.width,
                height: cgImage.height
            )
        )
        guard let decodedImage = context.makeImage() else { return self }

        let image = NSImage(size: size)
        let representation = NSBitmapImageRep(cgImage: decodedImage)
        representation.size = size
        image.addRepresentation(representation)
        return image
    }
}
#else
private extension UIImage {
    nonisolated func downloadableMediaDecodedForDisplay() -> UIImage {
        guard images == nil, size.width > 0, size.height > 0 else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(
            size: size,
            format: format
        ).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
