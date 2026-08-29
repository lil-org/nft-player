// ∅ 2026 lil org

import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

actor DownloadableMediaImageDecoder: DownloadableMediaImageDecoding {
    func decode(
        at fileURL: URL,
        generation: DownloadableMediaImageDecodeGeneration
    ) async -> DownloadableMediaDecodedImageTransfer? {
        guard generation.beginIfCurrent() else { return nil }

        return autoreleasepool {
            guard let image = DownloadableMediaImage(
                contentsOfFile: fileURL.path
            ) else {
                return DownloadableMediaDecodedImageTransfer(image: nil)
            }
            return DownloadableMediaDecodedImageTransfer(
                image: image.downloadableMediaDecodedForDisplay()
            )
        }
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
