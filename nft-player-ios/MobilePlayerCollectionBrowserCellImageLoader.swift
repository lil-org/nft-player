// ∅ 2026 lil org

import UIKit

enum CachedImageSelectionPolicy: Equatable {
    case highestAvailable
    case base(
        requiredQuality: CollectionBrowseImageQuality,
        allowsLocalLargeUpgrade: Bool
    )
}

struct CachedImageDescriptorRetention {
    let descriptor: DownloadableMediaDescriptor?
    let rejectsDisplayedImage: Bool
}

func cachedImageDescriptorRetention(
    displayedDescriptor: DownloadableMediaDescriptor?,
    displayedImageIsPresent: Bool,
    representedContentIdentity: MobilePlayerBrowserContentIdentity?,
    targetContentIdentity: MobilePlayerBrowserContentIdentity,
    imageSources: CollectionBrowseImageSources?,
    selectionPolicy: CachedImageSelectionPolicy
) -> CachedImageDescriptorRetention {
    guard representedContentIdentity == targetContentIdentity,
          displayedImageIsPresent,
          let displayedDescriptor else {
        return CachedImageDescriptorRetention(
            descriptor: nil,
            rejectsDisplayedImage: false
        )
    }
    guard let imageSources,
          imageSources.quality(of: displayedDescriptor) != nil,
          imageSources.cachedImageCandidateDescriptors(
              selectionPolicy: selectionPolicy
          ).contains(displayedDescriptor) else {
        return CachedImageDescriptorRetention(
            descriptor: nil,
            rejectsDisplayedImage: true
        )
    }
    return CachedImageDescriptorRetention(
        descriptor: displayedDescriptor,
        rejectsDisplayedImage: false
    )
}

@MainActor
final class MobilePlayerCollectionBrowserCellImageLoader {
    enum ImageLoadPolicy: Equatable {
        case disabled
        case cachedOnly
        case foreground
    }

    enum StartImageLoadResult: Equatable {
        case active
        case missingDescriptor
        case ignored
    }

    enum ImageInstallDisposition: Equatable {
        case install(cachedStaticImageURL: URL?)
        case deferred
        case rejected
    }

    struct CachedImage {
        let tokenIndex: Int
        let descriptor: DownloadableMediaDescriptor
        let quality: CollectionBrowseImageQuality
        let image: UIImage
    }

    struct LoadCompletion {
        let image: UIImage?
        let descriptor: DownloadableMediaDescriptor
        let quality: CollectionBrowseImageQuality
        let tokenIndex: Int
        let animatedWhenLoaded: Bool
        let fallbackQualityOnFailure: CollectionBrowseImageQuality?
        let hasActiveLoads: Bool
    }

    struct DeferredImageInstall {
        let image: UIImage
        let descriptor: DownloadableMediaDescriptor
        let quality: CollectionBrowseImageQuality
        let contentIdentity: MobilePlayerBrowserContentIdentity
    }

    private struct ImageLoad {
        let id: UUID
        let cancellation: (() -> Void)?
        var fallbackQualityOnFailure: CollectionBrowseImageQuality?
    }

    private(set) var contentIdentity: MobilePlayerBrowserContentIdentity?
    private(set) var imageSources: CollectionBrowseImageSources?
    private(set) var requiredImageQuality = CollectionBrowseImageQuality.thumbnail
    private(set) var imageLoadPolicy = ImageLoadPolicy.disabled
    private(set) var allowsLocalLargeImageUpgrade = true
    private(set) var descriptor: DownloadableMediaDescriptor?
    private(set) var displayedImageDescriptor: DownloadableMediaDescriptor?
    private(set) var displayedImageHasLocalFile = false
    private(set) var displayedImageSize = CGSize(width: 1, height: 1)
    private(set) var deferredImageInstall: DeferredImageInstall?
    private var imageLoads = [CollectionBrowseImageQuality: ImageLoad]()

    var tokenIndex: Int? {
        contentIdentity?.tokenIndex
    }

    var displayedImageQuality: CollectionBrowseImageQuality? {
        guard let displayedImageDescriptor else { return nil }
        return imageSources?.quality(of: displayedImageDescriptor)
    }

    var usesForegroundImageLoading: Bool {
        imageLoadPolicy == .foreground
    }

    var hasActiveLoads: Bool {
        !imageLoads.isEmpty
    }

    var deferredImageQuality: CollectionBrowseImageQuality? {
        deferredImageInstall?.quality
    }

    isolated deinit {
        cancelImageLoads()
    }

    func discardDeferredImageInstallIfIncompatible(
        contentIdentity: MobilePlayerBrowserContentIdentity,
        imageSources: CollectionBrowseImageSources?,
        selectionPolicy: CachedImageSelectionPolicy
    ) {
        guard let deferredImageInstall else { return }
        guard deferredImageInstall.contentIdentity == contentIdentity,
              imageSources?.descriptor(for: deferredImageInstall.quality)
                == deferredImageInstall.descriptor,
              imageSources?.cachedImageCandidateDescriptors(
                  selectionPolicy: selectionPolicy
              ).contains(deferredImageInstall.descriptor) == true else {
            self.deferredImageInstall = nil
            return
        }
    }

    func cancelIncompatibleImageLoads(
        tokenIndex: Int,
        imageSources: CollectionBrowseImageSources?,
        requiredImageQuality: CollectionBrowseImageQuality,
        allowsImageLoading: Bool,
        allowsLocalLargeImageUpgrade: Bool
    ) {
        guard self.tokenIndex == tokenIndex,
              allowsImageLoading,
              let previousSources = self.imageSources,
              let imageSources else {
            cancelImageLoads()
            return
        }

        let incompatibleQualities = imageLoads.keys.filter { quality in
            guard let descriptor = imageSources.descriptor(for: quality) else {
                return true
            }
            if previousSources.descriptor(for: quality) != descriptor
                || imageSources.quality(of: descriptor) != quality {
                return true
            }
            return quality == .large
                && !CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                    requiredQuality: requiredImageQuality,
                    hasDistinctLargeImage: imageSources.largeDescriptor
                        != imageSources.thumbnailDescriptor,
                    largeImageIsLocallyAvailable:
                        DownloadableMediaCache.shared.localFileURL(
                            for: descriptor
                        ) != nil,
                    allowsLocalPromotion: allowsLocalLargeImageUpgrade
                )
        }
        let cancellations = incompatibleQualities.compactMap { quality in
            imageLoads.removeValue(forKey: quality)?.cancellation
        }
        cancellations.forEach { $0() }
    }

    func configure(
        contentIdentity: MobilePlayerBrowserContentIdentity,
        imageSources: CollectionBrowseImageSources?,
        requiredImageQuality: CollectionBrowseImageQuality,
        imageLoadPolicy: ImageLoadPolicy,
        allowsLocalLargeImageUpgrade: Bool,
        retainedDescriptor: DownloadableMediaDescriptor?,
        retainedImageHasLocalFile: Bool,
        fallbackImageSize: CGSize
    ) {
        self.contentIdentity = contentIdentity
        self.imageSources = imageSources
        self.requiredImageQuality = requiredImageQuality
        self.imageLoadPolicy = imageLoadPolicy
        self.allowsLocalLargeImageUpgrade = allowsLocalLargeImageUpgrade
        displayedImageDescriptor = retainedDescriptor
        displayedImageHasLocalFile = retainedImageHasLocalFile
        descriptor = retainedDescriptor
            ?? imageSources?.descriptor(for: requiredImageQuality)
        if retainedDescriptor == nil {
            displayedImageSize = fallbackImageSize
        }
    }

    func reset() {
        cancelImageLoads()
        deferredImageInstall = nil
        contentIdentity = nil
        imageSources = nil
        requiredImageQuality = .thumbnail
        imageLoadPolicy = .disabled
        allowsLocalLargeImageUpgrade = true
        descriptor = nil
        displayedImageDescriptor = nil
        displayedImageHasLocalFile = false
        displayedImageSize = CGSize(width: 1, height: 1)
    }

    @discardableResult
    func promoteImageLoadingToForeground() -> Bool {
        guard imageLoadPolicy != .foreground else { return false }
        imageLoadPolicy = .foreground
        return true
    }

    @discardableResult
    func demoteImageLoadingToCachedOnly() -> Bool {
        guard imageLoadPolicy == .foreground else { return false }
        imageLoadPolicy = .cachedOnly
        cancelImageLoads()
        return true
    }

    func needsCachedImageRefresh(tokenIndex: Int) -> Bool {
        guard self.tokenIndex == tokenIndex,
              imageLoadPolicy == .cachedOnly,
              imageSources != nil else {
            return false
        }
        return displayedImageQuality?.canReplace(requiredImageQuality) != true
            && deferredImageInstall?.quality.canReplace(requiredImageQuality)
                != true
    }

    func cachedImageIfAvailable(
        displayedImageIsPresent: Bool
    ) -> CachedImage? {
        guard let tokenIndex,
              let imageSources,
              let cachedImage = imageSources.highestQualityCachedImage(
                  in: DownloadableMediaCache.shared,
                  selectionPolicy: .base(
                      requiredQuality: requiredImageQuality,
                      allowsLocalLargeUpgrade: allowsLocalLargeImageUpgrade
                  )
              ),
              displayedImageDescriptor != cachedImage.descriptor
                || !displayedImageIsPresent else {
            return nil
        }
        return CachedImage(
            tokenIndex: tokenIndex,
            descriptor: cachedImage.descriptor,
            quality: cachedImage.quality,
            image: cachedImage.image
        )
    }

    func startImageLoad(
        quality requestedQuality: CollectionBrowseImageQuality,
        animatedWhenLoaded: Bool,
        fallbackQualityOnFailure: CollectionBrowseImageQuality? = nil,
        completion: @escaping @MainActor (LoadCompletion) -> Void
    ) -> StartImageLoadResult {
        guard let tokenIndex,
              let imageSources else {
            return .ignored
        }
        guard let descriptor = imageSources.descriptor(
            for: requestedQuality
        ) else {
            return .missingDescriptor
        }
        guard let resolvedQuality = imageSources.quality(of: descriptor) else {
            return .ignored
        }
        if var imageLoad = imageLoads[resolvedQuality] {
            imageLoad.fallbackQualityOnFailure = fallbackQualityOnFailure
            imageLoads[resolvedQuality] = imageLoad
            return .active
        }

        let loadID = UUID()
        let cancellation = DownloadableMediaCache.shared.loadImage(
            for: descriptor
        ) { [weak self] image in
            Task { @MainActor in
                guard let self,
                      let imageLoad = self.imageLoads[resolvedQuality],
                      imageLoad.id == loadID else {
                    return
                }
                self.imageLoads.removeValue(forKey: resolvedQuality)
                guard self.tokenIndex == tokenIndex,
                      self.imageSources?.descriptor(for: resolvedQuality)
                        == descriptor else {
                    return
                }
                completion(LoadCompletion(
                    image: image,
                    descriptor: descriptor,
                    quality: resolvedQuality,
                    tokenIndex: tokenIndex,
                    animatedWhenLoaded: animatedWhenLoaded,
                    fallbackQualityOnFailure:
                        imageLoad.fallbackQualityOnFailure,
                    hasActiveLoads: !self.imageLoads.isEmpty
                ))
            }
        }
        if imageLoads[resolvedQuality] == nil {
            imageLoads[resolvedQuality] = ImageLoad(
                id: loadID,
                cancellation: cancellation,
                fallbackQualityOnFailure: fallbackQualityOnFailure
            )
        }
        return .active
    }

    func cancelImageLoads() {
        let cancellations = imageLoads.values.compactMap(\.cancellation)
        imageLoads.removeAll()
        cancellations.forEach { $0() }
    }

    func prepareImageInstall(
        _ image: UIImage,
        descriptor: DownloadableMediaDescriptor,
        quality: CollectionBrowseImageQuality,
        tokenIndex: Int,
        defersInstall: Bool,
        tracksLocalFileAvailability: Bool,
        prewarmsNativeMetalCardFace: Bool
    ) -> ImageInstallDisposition {
        guard self.tokenIndex == tokenIndex,
              imageSources?.descriptor(for: quality) == descriptor,
              quality.canReplace(displayedImageQuality) else {
            return .rejected
        }

        cancelImageLoads(satisfiedBy: quality)
        if let deferredImageInstall,
           !quality.canReplace(deferredImageInstall.quality) {
            return .rejected
        }
        if defersInstall, let contentIdentity {
            deferredImageInstall = DeferredImageInstall(
                image: image,
                descriptor: descriptor,
                quality: quality,
                contentIdentity: contentIdentity
            )
            return .deferred
        }

        deferredImageInstall = nil
        self.descriptor = descriptor
        displayedImageDescriptor = descriptor
        let descriptorCanSatisfyLarge = imageSources?.largeDescriptor
            == descriptor
        let cachedStaticImageURL = descriptorCanSatisfyLarge
            && (tracksLocalFileAvailability || prewarmsNativeMetalCardFace)
            ? DownloadableMediaCache.shared.localFileURL(for: descriptor)
            : nil
        displayedImageHasLocalFile = tracksLocalFileAvailability
            && descriptorCanSatisfyLarge
            && cachedStaticImageURL != nil
        displayedImageSize = image.size
        return .install(cachedStaticImageURL: cachedStaticImageURL)
    }

    func takeDeferredImageInstall(
        contentIdentity: MobilePlayerBrowserContentIdentity?,
        canInstall: Bool
    ) -> DeferredImageInstall? {
        guard canInstall,
              let deferredImageInstall else {
            return nil
        }
        self.deferredImageInstall = nil
        guard contentIdentity == deferredImageInstall.contentIdentity else {
            return nil
        }
        return deferredImageInstall
    }

#if DEBUG
    func clearDisplayedImageForTesting() {
        deferredImageInstall = nil
        displayedImageDescriptor = nil
        displayedImageHasLocalFile = false
        descriptor = imageSources?.descriptor(for: requiredImageQuality)
    }
#endif

    func shouldRefreshAvailableImage(
        notification: Notification,
        displayedImageIsPresent: Bool
    ) -> Bool {
        guard imageLoadPolicy == .foreground,
              tokenIndex != nil,
              let imageSources else {
            return false
        }
        if displayedImageIsPresent, displayedImageQuality == .large {
            return false
        }

        let cache = DownloadableMediaCache.shared
        let descriptorsWorthLoading = imageSources.descriptorsByDescendingQuality
            .filter {
                guard displayedImageIsPresent,
                      let displayedImageQuality,
                      let quality = imageSources.quality(of: $0) else {
                    return true
                }
                return quality != displayedImageQuality
                    && quality.canReplace(displayedImageQuality)
            }
        return descriptorsWorthLoading.contains {
            cache.fileAvailabilityChange(notification, affects: $0)
        }
    }

    func updateLocalFileAvailability(
        notification: Notification,
        isAvailable: Bool
    ) {
        guard let displayedImageDescriptor,
              imageSources?.largeDescriptor == displayedImageDescriptor,
              DownloadableMediaCache.shared.fileAvailabilityChange(
                  notification,
                  affects: displayedImageDescriptor
              ) else {
            return
        }
        displayedImageHasLocalFile = isAvailable
    }

    func reconcileForegroundImageState() {
        guard let displayedImageDescriptor else { return }
        let descriptorCanSatisfyLarge = imageSources?.largeDescriptor
            == displayedImageDescriptor
        let cachedStaticImageURL = descriptorCanSatisfyLarge
            ? DownloadableMediaCache.shared.localFileURL(
                for: displayedImageDescriptor
            )
            : nil
        displayedImageHasLocalFile = descriptorCanSatisfyLarge
            && cachedStaticImageURL != nil
        prewarmImageIfNeeded(
            for: displayedImageDescriptor,
            cachedStaticImageURL: cachedStaticImageURL
        )
    }

    func prewarmDisplayedImageIfNeeded(cachedStaticImageURL: URL?) {
        guard let displayedImageDescriptor else { return }
        prewarmImageIfNeeded(
            for: displayedImageDescriptor,
            cachedStaticImageURL: cachedStaticImageURL
        )
    }

    func prewarmImageIfNeeded(
        for descriptor: DownloadableMediaDescriptor,
        cachedStaticImageURL: URL?
    ) {
        guard let renderKind = descriptor.nativeMetalCardRenderKind,
              let tokenID = Int(descriptor.tokenId) else {
            return
        }
        guard let cachedStaticImageURL else {
            Task {
                _ = await renderKind.loadFace(for: tokenID)
            }
            return
        }

        Task {
            let didCacheFace = await renderKind.cacheFace(
                for: tokenID,
                from: cachedStaticImageURL
            )
            guard !didCacheFace else { return }
            _ = await renderKind.loadFace(for: tokenID)
        }
    }

    private func cancelImageLoads(
        satisfiedBy quality: CollectionBrowseImageQuality
    ) {
        if let matchingLoad = imageLoads.removeValue(forKey: quality) {
            matchingLoad.cancellation?()
        }
        let replacedLoads = imageLoads.keys
            .filter { $0.rawValue < quality.rawValue }
            .compactMap { imageLoads.removeValue(forKey: $0)?.cancellation }
        replacedLoads.forEach { $0() }
    }

}

extension CollectionBrowseImageSources {
    func fallbackQuality(
        after quality: CollectionBrowseImageQuality
    ) -> CollectionBrowseImageQuality? {
        let candidates: [CollectionBrowseImageQuality]
        switch quality {
        case .smallestThumbnail, .smallThumbnail, .thumbnail:
            candidates = []
        case .large:
            candidates = [.thumbnail]
        }
        guard let currentDescriptor = descriptor(for: quality) else {
            return nil
        }
        return candidates.first {
            descriptor(for: $0) != currentDescriptor
        }
    }

    func cachedImageCandidateDescriptors(
        selectionPolicy: CachedImageSelectionPolicy
    ) -> [DownloadableMediaDescriptor] {
        switch selectionPolicy {
        case .highestAvailable:
            return descriptorsByDescendingQuality
        case let .base(requiredQuality, allowsLocalLargeUpgrade):
            guard requiredQuality != .large,
                  !allowsLocalLargeUpgrade else {
                return descriptorsByDescendingQuality
            }
            if requiredQuality == .thumbnail {
                return [thumbnailDescriptor]
            }
            let descriptors = requiredQuality == .smallestThumbnail
                ? [
                    smallestThumbnailDescriptor,
                    smallThumbnailDescriptor,
                    thumbnailDescriptor,
                ]
                : [smallThumbnailDescriptor, thumbnailDescriptor]
            return descriptors
                .compactMap { $0 }
                .reduce(into: []) { descriptors, descriptor in
                    if !descriptors.contains(descriptor) {
                        descriptors.append(descriptor)
                    }
                }
        }
    }

    func highestQualityCachedImage(
        in cache: DownloadableMediaCache,
        selectionPolicy: CachedImageSelectionPolicy
    ) -> (
        descriptor: DownloadableMediaDescriptor,
        quality: CollectionBrowseImageQuality,
        image: UIImage
    )? {
        for descriptor in cachedImageCandidateDescriptors(
            selectionPolicy: selectionPolicy
        ) {
            guard let quality = self.quality(of: descriptor),
                  let image = cache.cachedDecodedImage(for: descriptor) else {
                continue
            }
            return (descriptor, quality, image)
        }
        return nil
    }
}
