// ∅ 2026 lil org

import UIKit

enum CachedImageSelectionPolicy: Equatable {
    case highestAvailable
    case base(
        requiredQuality: CollectionBrowseImageQuality,
        allowsLocalLargeUpgrade: Bool
    )
}

nonisolated enum CollectionBrowseCachedImageDecodeSelection:
    Equatable, Sendable {
    case satisfying(DownloadableMediaImageDecodeVariant)
    case bestAvailable(
        preferredVariants: [DownloadableMediaImageDecodeVariant]
    )

    var normalized: Self {
        switch self {
        case let .satisfying(variant):
            return .satisfying(variant.normalized)
        case let .bestAvailable(preferredVariants):
            var usedVariants = Set<DownloadableMediaImageDecodeVariant>()
            let normalizedVariants = preferredVariants.compactMap { variant in
                let variant = variant.normalized
                return usedVariants.insert(variant).inserted ? variant : nil
            }
            return .bestAvailable(preferredVariants: normalizedVariants)
        }
    }
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
        let imageDecodeVariant: DownloadableMediaImageDecodeVariant
    }

    struct LoadCompletion {
        let image: UIImage?
        let descriptor: DownloadableMediaDescriptor
        let quality: CollectionBrowseImageQuality
        let tokenIndex: Int
        let animatedWhenLoaded: Bool
        let fallbackQualityOnFailure: CollectionBrowseImageQuality?
        let hasActiveLoads: Bool
        let imageDecodeVariant: DownloadableMediaImageDecodeVariant
    }

    struct DeferredImageInstall {
        let image: UIImage
        let descriptor: DownloadableMediaDescriptor
        let quality: CollectionBrowseImageQuality
        let contentIdentity: MobilePlayerBrowserContentIdentity
        let imageDecodeVariant: DownloadableMediaImageDecodeVariant
    }

    private struct ImageLoad {
        let id: UUID
        let task: Task<Void, Never>
        let imageDecodeVariant: DownloadableMediaImageDecodeVariant
        var fallbackQualityOnFailure: CollectionBrowseImageQuality?
    }

    private(set) var contentIdentity: MobilePlayerBrowserContentIdentity?
    private(set) var imageSources: CollectionBrowseImageSources?
    private(set) var requiredImageQuality = CollectionBrowseImageQuality.thumbnail
    private(set) var imageDecodeVariant = DownloadableMediaImageDecodeVariant.full
    private(set) var imageLoadPolicy = ImageLoadPolicy.disabled
    private(set) var allowsLocalLargeImageUpgrade = true
    private(set) var descriptor: DownloadableMediaDescriptor?
    private(set) var displayedImageDescriptor: DownloadableMediaDescriptor?
    private(set) var displayedImageHasLocalFile = false
    private(set) var displayedImageDecodeVariant:
        DownloadableMediaImageDecodeVariant?
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
        selectionPolicy: CachedImageSelectionPolicy,
        requiredImageDecodeVariant: DownloadableMediaImageDecodeVariant
    ) {
        guard let deferredImageInstall else { return }
        guard deferredImageInstall.contentIdentity == contentIdentity,
              imageSources?.descriptor(for: deferredImageInstall.quality)
                == deferredImageInstall.descriptor,
              imageSources?.cachedImageCandidateDescriptors(
                  selectionPolicy: selectionPolicy
              ).contains(deferredImageInstall.descriptor) == true,
              deferredImageInstall.imageDecodeVariant.satisfies(
                  requiredImageDecodeVariant
              ) else {
            self.deferredImageInstall = nil
            return
        }
    }

    func cancelIncompatibleImageLoads(
        tokenIndex: Int,
        imageSources: CollectionBrowseImageSources?,
        requiredImageQuality: CollectionBrowseImageQuality,
        allowsImageLoading: Bool,
        allowsLocalLargeImageUpgrade: Bool,
        imageDecodeVariant: DownloadableMediaImageDecodeVariant
    ) {
        guard self.tokenIndex == tokenIndex,
              allowsImageLoading,
              let previousSources = self.imageSources,
              let imageSources else {
            cancelImageLoads()
            return
        }

        let incompatibleQualities = imageLoads.keys.filter { quality in
            guard let imageLoad = imageLoads[quality] else { return true }
            guard let descriptor = imageSources.descriptor(for: quality) else {
                return true
            }
            if previousSources.descriptor(for: quality) != descriptor
                || imageSources.quality(of: descriptor) != quality {
                return true
            }
            if !imageLoad.imageDecodeVariant.satisfies(imageDecodeVariant) {
                return true
            }
            return quality == .large
                && !CollectionBrowseImageLoadPolicy.allowsLargeImageLoad(
                    requiredQuality: requiredImageQuality,
                    hasDistinctLargeImage: imageSources.largeDescriptor
                        != imageSources.thumbnailDescriptor,
                    largeImageIsLocallyAvailable:
                        DownloadableMediaCache.shared.knownLocalFileURL(
                            for: descriptor
                        ) != nil,
                    allowsLocalPromotion: allowsLocalLargeImageUpgrade
                )
        }
        let tasks = incompatibleQualities.compactMap { quality in
            imageLoads.removeValue(forKey: quality)?.task
        }
        tasks.forEach { $0.cancel() }
    }

    func configure(
        contentIdentity: MobilePlayerBrowserContentIdentity,
        imageSources: CollectionBrowseImageSources?,
        requiredImageQuality: CollectionBrowseImageQuality,
        imageDecodeVariant: DownloadableMediaImageDecodeVariant,
        imageLoadPolicy: ImageLoadPolicy,
        allowsLocalLargeImageUpgrade: Bool,
        retainedDescriptor: DownloadableMediaDescriptor?,
        retainedImageHasLocalFile: Bool,
        fallbackImageSize: CGSize
    ) {
        self.contentIdentity = contentIdentity
        self.imageSources = imageSources
        self.requiredImageQuality = requiredImageQuality
        self.imageDecodeVariant = imageDecodeVariant.normalized
        self.imageLoadPolicy = imageLoadPolicy
        self.allowsLocalLargeImageUpgrade = allowsLocalLargeImageUpgrade
        if retainedDescriptor == nil
            || retainedDescriptor != displayedImageDescriptor {
            displayedImageDecodeVariant = nil
        }
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
        imageDecodeVariant = .full
        imageLoadPolicy = .disabled
        allowsLocalLargeImageUpgrade = true
        descriptor = nil
        displayedImageDescriptor = nil
        displayedImageHasLocalFile = false
        displayedImageDecodeVariant = nil
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
        return !hasSatisfyingDisplayedOrDeferredImage
    }

    var hasSatisfyingDisplayedOrDeferredImage: Bool {
        let displayedSatisfies = displayedImageQuality?.canReplace(
            requiredImageQuality
        ) == true && displayedImageDecodeVariant?.satisfies(
            imageDecodeVariant
        ) == true
        let deferredSatisfies = deferredImageInstall?.quality.canReplace(
            requiredImageQuality
        ) == true && deferredImageInstall?.imageDecodeVariant.satisfies(
            imageDecodeVariant
        ) == true
        return displayedSatisfies || deferredSatisfies
    }

    var hasActiveCompatibleImageLoad: Bool {
        imageLoads.values.contains {
            $0.imageDecodeVariant.satisfies(imageDecodeVariant)
        }
    }

    func cachedImageIfAvailable(
        displayedImageIsPresent: Bool
    ) -> CachedImage? {
        guard let tokenIndex,
              let imageSources,
              let cachedImage = imageSources.highestQualityCachedImageEntry(
                  in: DownloadableMediaCache.shared,
                  selectionPolicy: .base(
                      requiredQuality: requiredImageQuality,
                      allowsLocalLargeUpgrade: allowsLocalLargeImageUpgrade
                  ),
                  variant: imageDecodeVariant
              ),
              displayedImageDescriptor != cachedImage.descriptor
                || !displayedImageIsPresent
                || displayedImageDecodeVariant?.satisfies(imageDecodeVariant)
                    != true else {
            return nil
        }
        return CachedImage(
            tokenIndex: tokenIndex,
            descriptor: cachedImage.descriptor,
            quality: cachedImage.quality,
            image: cachedImage.image,
            imageDecodeVariant: cachedImage.variant
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
            if imageLoad.imageDecodeVariant.satisfies(imageDecodeVariant) {
                imageLoad.fallbackQualityOnFailure = fallbackQualityOnFailure
                imageLoads[resolvedQuality] = imageLoad
                return .active
            }
            imageLoads.removeValue(forKey: resolvedQuality)?.task.cancel()
        }

        let loadID = UUID()
        let imageDecodeVariant = self.imageDecodeVariant
        let task = Task { @MainActor [weak self] in
            let entry = await DownloadableMediaCache.shared.imageEntry(
                for: descriptor,
                variant: imageDecodeVariant
            )
            guard !Task.isCancelled,
                  let self,
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
                image: entry?.image,
                descriptor: descriptor,
                quality: resolvedQuality,
                tokenIndex: tokenIndex,
                animatedWhenLoaded: animatedWhenLoaded,
                fallbackQualityOnFailure:
                    imageLoad.fallbackQualityOnFailure,
                hasActiveLoads: !self.imageLoads.isEmpty,
                imageDecodeVariant:
                    entry?.variant ?? imageLoad.imageDecodeVariant
            ))
        }
        if imageLoads[resolvedQuality] == nil {
            imageLoads[resolvedQuality] = ImageLoad(
                id: loadID,
                task: task,
                imageDecodeVariant: imageDecodeVariant,
                fallbackQualityOnFailure: fallbackQualityOnFailure
            )
        } else {
            task.cancel()
        }
        return .active
    }

    func cancelImageLoads() {
        let tasks = imageLoads.values.map(\.task)
        imageLoads.removeAll()
        tasks.forEach { $0.cancel() }
    }

    func prepareImageInstall(
        _ image: UIImage,
        descriptor: DownloadableMediaDescriptor,
        quality: CollectionBrowseImageQuality,
        tokenIndex: Int,
        imageDecodeVariant: DownloadableMediaImageDecodeVariant,
        defersInstall: Bool,
        tracksLocalFileAvailability: Bool,
        prewarmsNativeMetalCardFace: Bool
    ) -> ImageInstallDisposition {
        guard self.tokenIndex == tokenIndex,
              imageSources?.descriptor(for: quality) == descriptor,
              imageDecodeVariant.satisfies(self.imageDecodeVariant),
              quality.canReplace(displayedImageQuality) else {
            return .rejected
        }

        cancelImageLoads(
            satisfiedBy: quality,
            imageDecodeVariant: imageDecodeVariant
        )
        if let deferredImageInstall,
           (!quality.canReplace(deferredImageInstall.quality)
                || !imageDecodeVariant.satisfies(
                    deferredImageInstall.imageDecodeVariant
                )) {
            return .rejected
        }
        if defersInstall, let contentIdentity {
            deferredImageInstall = DeferredImageInstall(
                image: image,
                descriptor: descriptor,
                quality: quality,
                contentIdentity: contentIdentity,
                imageDecodeVariant: imageDecodeVariant.normalized
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
            ? DownloadableMediaCache.shared.knownLocalFileURL(for: descriptor)
            : nil
        displayedImageHasLocalFile = tracksLocalFileAvailability
            && descriptorCanSatisfyLarge
            && cachedStaticImageURL != nil
        displayedImageSize = image.size
        displayedImageDecodeVariant = imageDecodeVariant.normalized
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
        guard deferredImageInstall.imageDecodeVariant.satisfies(
            imageDecodeVariant
        ) else {
            return nil
        }
        return deferredImageInstall
    }

#if DEBUG
    func clearDisplayedImageForTesting() {
        deferredImageInstall = nil
        displayedImageDescriptor = nil
        displayedImageHasLocalFile = false
        displayedImageDecodeVariant = nil
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
        if displayedImageIsPresent,
           displayedImageQuality == .large,
           displayedImageDecodeVariant?.satisfies(imageDecodeVariant) == true {
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
            ? DownloadableMediaCache.shared.knownLocalFileURL(
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
        satisfiedBy quality: CollectionBrowseImageQuality,
        imageDecodeVariant: DownloadableMediaImageDecodeVariant
    ) {
        let satisfiedLoads = imageLoads.compactMap { loadQuality, imageLoad in
            loadQuality.rawValue <= quality.rawValue
                && imageDecodeVariant.satisfies(imageLoad.imageDecodeVariant)
                ? loadQuality : nil
        }
        let replacedLoads = satisfiedLoads.compactMap {
            imageLoads.removeValue(forKey: $0)?.task
        }
        replacedLoads.forEach { $0.cancel() }
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

    func highestQualityCachedImageEntry(
        in cache: DownloadableMediaCache,
        selectionPolicy: CachedImageSelectionPolicy,
        variant: DownloadableMediaImageDecodeVariant = .full
    ) -> (
        descriptor: DownloadableMediaDescriptor,
        quality: CollectionBrowseImageQuality,
        image: UIImage,
        variant: DownloadableMediaImageDecodeVariant
    )? {
        for descriptor in cachedImageCandidateDescriptors(
            selectionPolicy: selectionPolicy
        ) {
            guard let quality = self.quality(of: descriptor),
                  let entry = cache.cachedDecodedImageEntry(
                      for: descriptor,
                      variant: variant
                  ) else {
                continue
            }
            return (descriptor, quality, entry.image, entry.variant)
        }
        return nil
    }

    func cachedImageEntry(
        in cache: DownloadableMediaCache,
        selectionPolicy: CachedImageSelectionPolicy,
        decodeSelection: CollectionBrowseCachedImageDecodeSelection
    ) -> (
        descriptor: DownloadableMediaDescriptor,
        quality: CollectionBrowseImageQuality,
        image: UIImage,
        variant: DownloadableMediaImageDecodeVariant
    )? {
        switch decodeSelection.normalized {
        case let .satisfying(variant):
            return highestQualityCachedImageEntry(
                in: cache,
                selectionPolicy: selectionPolicy,
                variant: variant
            )
        case let .bestAvailable(preferredVariants):
            for variant in preferredVariants {
                if let entry = highestQualityCachedImageEntry(
                    in: cache,
                    selectionPolicy: selectionPolicy,
                    variant: variant
                ) {
                    return entry
                }
            }
            for descriptor in cachedImageCandidateDescriptors(
                selectionPolicy: selectionPolicy
            ) {
                guard let quality = quality(of: descriptor),
                      let entry = cache.anyCachedDecodedImageEntry(
                          for: descriptor
                      ) else {
                    continue
                }
                return (
                    descriptor,
                    quality,
                    entry.image,
                    entry.variant
                )
            }
            return nil
        }
    }

}
