import ImageIO
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
private var collectionCoverActivationNotification: Notification.Name {
#if os(macOS)
    NSApplication.didBecomeActiveNotification
#else
    UIApplication.didBecomeActiveNotification
#endif
}

@MainActor
struct CollectionCoverImage: View {
    let assetName: String
    var hasCover = true

    @State private var loadedImage: DecodedCollectionCover?
    @State private var loadedAssetName: String?
    @State private var loadingID: UUID?
    @State private var isVisible = false
    @State private var refreshID = 0

    private var image: DecodedCollectionCover? {
        guard hasCover else { return nil }
        if loadedAssetName == assetName, let loadedImage {
            return loadedImage
        }
        return CollectionCoverImageCache.shared.cachedImage(for: assetName)
    }

    var body: some View {
        Color.black
            .overlay {
                if let image {
                    Image(decorative: image.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .task(id: RequestID(assetName: assetName, hasCover: hasCover, refreshID: refreshID)) {
                guard hasCover else { return }
                let requestedAssetName = assetName
                let requestID = UUID()
                loadingID = requestID
                defer {
                    if loadingID == requestID {
                        loadingID = nil
                    }
                }
                let decodedImage = await CollectionCoverImageCache.shared.image(for: requestedAssetName)
                guard !Task.isCancelled else { return }
                loadedAssetName = requestedAssetName
                loadedImage = decodedImage
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onReceive(
                NotificationCenter.default.publisher(for: collectionCoverActivationNotification)
                    .merge(with: NotificationCenter.default.publisher(for: .collectionCoverConnectionRecovered))
                    .receive(on: RunLoop.main)
            ) { _ in
                guard isVisible, hasCover, image == nil else { return }
                refreshID &+= 1
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .collectionCoverDidBecomeAvailable)
                    .receive(on: RunLoop.main)
            ) { notification in
                guard isVisible, hasCover,
                      notification.object as? String == assetName,
                      loadingID == nil,
                      image == nil else { return }
                refreshID &+= 1
            }
    }

    private struct RequestID: Hashable {
        let assetName: String
        let hasCover: Bool
        let refreshID: Int
    }
}

nonisolated private final class DecodedCollectionCover: Sendable {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }
}

@MainActor
private final class CollectionCoverImageCache {
    static let shared = CollectionCoverImageCache()

    private let images = NSCache<NSString, DecodedCollectionCover>()

    private init() {
        images.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(for assetName: String) -> DecodedCollectionCover? {
        images.object(forKey: assetName as NSString)
    }

    func image(for assetName: String) async -> DecodedCollectionCover? {
        guard !Task.isCancelled else { return nil }
        if let image = cachedImage(for: assetName) { return image }
        guard let data = try? await PersistentCollectionCoverCache.shared.data(
            for: assetName,
            priority: .visible
        ), !Task.isCancelled else { return nil }
        if let image = cachedImage(for: assetName) { return image }
        let image = await Self.decode(data)
        guard !Task.isCancelled else { return nil }
        if let image {
            images.setObject(
                image,
                forKey: assetName as NSString,
                cost: image.image.bytesPerRow * image.image.height
            )
        }
        return image
    }

    @concurrent
    private static func decode(_ data: Data) async -> DecodedCollectionCover? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_024,
                  ] as CFDictionary) else { return nil }
            return DecodedCollectionCover(image: image)
        }
    }
}

@MainActor
private struct CollectionCoverPreloadModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .task {
                CollectionCoverRecovery.shared.start()
                await Task.yield()
                guard !Task.isCancelled else { return }
                await preload(retryFailures: false)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: collectionCoverActivationNotification)
                    .merge(with: NotificationCenter.default.publisher(for: .collectionCoverConnectionRecovered))
                    .receive(on: RunLoop.main)
            ) { _ in
                Task {
                    await Task.yield()
                    await preload(retryFailures: true)
                }
            }
    }

    private func preload(retryFailures: Bool) async {
        await PersistentCollectionCoverCache.shared.preload(
            assetNames: SuggestedItemsService.allItems
                .filter { $0.hasCover != false }
                .map(\.bundledResourceName),
            retryFailures: retryFailures
        )
    }
}

extension View {
    func preloadCollectionCovers() -> some View {
        modifier(CollectionCoverPreloadModifier())
    }
}
