// ∅ 2026 lil org

import QuartzCore
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

final class MobilePlayerCollectionBrowserCell: UICollectionViewCell {
    enum ImageLoadPolicy: Equatable {
        case disabled
        case cachedOnly
        case foreground
    }

    struct TransitionSnapshot {
        let frameInWindow: CGRect
        let view: UIView
    }

    private struct ImageLoad {
        let id: UUID
        let cancellation: (() -> Void)?
        var fallbackQualityOnFailure: CollectionBrowseImageQuality?
    }

    private struct DeferredImageInstall {
        let image: UIImage
        let descriptor: DownloadableMediaDescriptor
        let quality: CollectionBrowseImageQuality
        let contentIdentity: MobilePlayerBrowserContentIdentity
    }

    private let placeholderView = PlayerMediaPlaceholderView()
    private let imageView = MobilePlayerCollectionBrowserCell
        .makeContentImageView(frame: .zero)
    private lazy var transitionPresentation =
        MobilePlayerCollectionBrowserTransitionPresentation(
            contentView: contentView
        )
    var hasCarryoverContent: Bool {
        transitionPresentation.hasCarryoverContent
    }
    private var fadesFirstImage = false
    private var configuredMediaTime: CFTimeInterval = 0
    /// Cached images found by a scan in the cell's own configure frame may
    /// install instantly — the cell has not been drawn yet. Anything later
    /// (a resumed load, a cache-availability notification) lands in a cell
    /// the user is already looking at and must fade.
    private static let configureFrameInstallGrace: CFTimeInterval = 0.05
    private static let contentFadeDuration =
        MobilePlayerCollectionBrowserTransitionPresentation.contentFadeDuration
    private(set) var descriptor: DownloadableMediaDescriptor?
    private(set) var displayedImageSize = CGSize(width: 1, height: 1)
    private var representedContentIdentity: MobilePlayerBrowserContentIdentity?
    private var representedTokenIndex: Int? {
        representedContentIdentity?.tokenIndex
    }
    private var imageSources: CollectionBrowseImageSources?
    private var requiredImageQuality = CollectionBrowseImageQuality.thumbnail
    private var configuredImageLoadPolicy = ImageLoadPolicy.disabled
    private var allowsLocalLargeImageUpgrade = true
    private var displayedImageDescriptor: DownloadableMediaDescriptor?
    private var displayedImageQuality: CollectionBrowseImageQuality? {
        guard let displayedImageDescriptor else { return nil }
        return imageSources?.quality(of: displayedImageDescriptor)
    }
    private var displayedImageHasLocalFile = false
    private var imageLoads = [CollectionBrowseImageQuality: ImageLoad]()
    private var deferredImageInstall: DeferredImageInstall?
    private var installedIncomingTransitionContentDescriptor:
        DownloadableMediaDescriptor?

    var displayedLargeImageWindowEntry: (
        tokenIndex: Int,
        isLocallyAvailable: Bool
    )? {
        guard imageView.image != nil,
              displayedImageQuality == .large,
              let representedTokenIndex else {
            return nil
        }
        return (representedTokenIndex, displayedImageHasLocalFile)
    }

    var displayedRegularThumbnailTokenIndex: Int? {
        guard imageView.image != nil,
              displayedImageQuality == .thumbnail else {
            return nil
        }
        return representedTokenIndex
    }

    var usesForegroundImageLoading: Bool {
        configuredImageLoadPolicy == .foreground
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        contentView.backgroundColor = .clear
        contentView.isOpaque = false
        contentView.clipsToBounds = false

        placeholderView.frame = contentView.bounds
        placeholderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(placeholderView)

        _ = transitionPresentation
        imageView.frame = contentView.bounds
        contentView.addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        Self.cancelImageLoads(&imageLoads)
    }

    private static func makeContentImageView(
        frame: CGRect
    ) -> NativeMetalCardCornerMaskedImageView {
        MobilePlayerCollectionBrowserTransitionPresentation
            .makeContentImageView(frame: frame)
    }

    private static func animateContentFade(
        _ animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        MobilePlayerCollectionBrowserTransitionPresentation
            .animateContentFade(animations, completion: completion)
    }

    func installTransitionContent(
        image: UIImage,
        descriptor: DownloadableMediaDescriptor,
        usesNativeMetalCardCornerMask: Bool,
        targetAlpha: CGFloat,
        animated: Bool,
        identity: MobilePlayerBrowserContentIdentity
    ) {
        transitionPresentation.installIncoming(
            image: image,
            usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask,
            targetAlpha: targetAlpha,
            animated: animated,
            identity: identity
        )
        installedIncomingTransitionContentDescriptor = descriptor
    }

    func setTransitionContentAlpha(
        _ alpha: CGFloat,
        interruptingAnimation: Bool = false
    ) {
        applyDeferredImageInstallIfPossible(requiresOpaqueOverlay: true)
        transitionPresentation.setIncomingAlpha(
            alpha,
            interruptingAnimation: interruptingAnimation
        )
        applyDeferredImageInstallIfPossible(requiresOpaqueOverlay: true)
    }

    func represents(tokenIndex: Int) -> Bool {
        representedTokenIndex == tokenIndex
    }

    func canSelect(
        representing identity: MobilePlayerBrowserContentIdentity
    ) -> Bool {
        representedContentIdentity == identity
            && transitionPresentation.allowsSelection(
                representing: identity
            )
    }

    func incomingTransitionContentQuality(
        representing identity: MobilePlayerBrowserContentIdentity,
        from imageSources: CollectionBrowseImageSources
    ) -> CollectionBrowseImageQuality? {
        guard case let .incoming(incomingIdentity) =
            transitionPresentation.presentationState else {
            return nil
        }
        guard incomingIdentity == identity else { return nil }
        guard let installedIncomingTransitionContentDescriptor else {
            return nil
        }
        return imageSources.quality(
            of: installedIncomingTransitionContentDescriptor
        )
    }

    func clearTransitionContent(
        preservingCarryover: Bool = false
    ) {
        transitionPresentation.clear(
            preservingCarryover: preservingCarryover
        )
        installedIncomingTransitionContentDescriptor = nil
    }

    func finishTransitionContent(
        preservingCarryover: Bool = false
    ) {
        clearTransitionContent(preservingCarryover: preservingCarryover)
        installDeferredBaseImageIfNoIncomingOverlay()
    }

    func installDeferredBaseImageIfNoIncomingOverlay() {
        applyDeferredImageInstallIfPossible()
    }

    var needsCarryoverContent: Bool {
        imageView.image == nil
    }

    var holdsCarryoverForPendingBaseImage: Bool {
        imageView.image == nil && hasCarryoverContent
    }

    var keepsTransitionPlaceholderToneForPendingLoad: Bool {
        transitionPresentation.holdsToneForBaseLoad
            && imageView.image == nil
            && !imageLoads.isEmpty
    }

    func setTransitionPlaceholderTone(_ isOn: Bool) {
        guard isOn else {
            clearTransitionPlaceholderTone(animated: false)
            return
        }
        transitionPresentation.holdTone()
        placeholderView.setHidden(true, animated: false)
    }

    private func clearTransitionPlaceholderTone(animated: Bool) {
        placeholderView.setHidden(
            imageView.image != nil,
            animated: false
        )
        transitionPresentation.clearTone(animated: animated)
    }

    var carryoverSourceContent: MobilePlayerBrowserCarryoverContent? {
        transitionPresentation.sourceContent(
            baseImageView: imageView,
            baseIdentity: representedContentIdentity
        )
    }

    func fadeOutCarryoverContentIfBaseReady() {
        guard imageView.image != nil else { return }
        imageView.layer.removeAllAnimations()
        imageView.alpha = 1
        fadeOutCarryoverContentIfNeeded()
    }

    func setCarryoverContent(_ content: MobilePlayerBrowserCarryoverContent) {
        transitionPresentation.installCarryover(content)
        installedIncomingTransitionContentDescriptor = nil
    }

    private func fadeOutCarryoverContentIfNeeded() {
        transitionPresentation.fadeCarryoverIfNeeded()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetForReuse()
    }

    func prepareForGridModePhantomReuse() {
        resetForReuse()
    }

    private func resetForReuse() {
        cancelImageLoad()
        deferredImageInstall = nil
        clearTransitionContent()
        representedContentIdentity = nil
        imageSources = nil
        configuredImageLoadPolicy = .disabled
        fadesFirstImage = false
        allowsLocalLargeImageUpgrade = true
        setTransitionPlaceholderTone(false)
        descriptor = nil
        displayedImageDescriptor = nil
        displayedImageHasLocalFile = false
        displayedImageSize = CGSize(width: 1, height: 1)
        layer.removeAnimation(forKey: "opacity")
        alpha = 1
        transform = .identity
        imageView.layer.removeAllAnimations()
        imageView.alpha = 1
        imageView.image = nil
        imageView.usesNativeMetalCardCornerMask = false
        placeholderView.configure(with: PlayerMediaPlaceholderSpec(thumbnailAspectRatio: nil))
        placeholderView.setHidden(false, animated: false)
    }

    func configure(
        contentIdentity: MobilePlayerBrowserContentIdentity,
        itemCount: Int,
        imageSources: CollectionBrowseImageSources?,
        requiredImageQuality: CollectionBrowseImageQuality,
        missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec,
        imageLoadPolicy: ImageLoadPolicy,
        fadesFirstImage: Bool = false,
        allowsLocalLargeImageUpgrade: Bool = true
    ) {
        let tokenIndex = contentIdentity.tokenIndex
        self.fadesFirstImage = fadesFirstImage
        let previousContentIdentity = representedContentIdentity
        let previousImageLoadPolicy = configuredImageLoadPolicy
        let changesContentIdentity = previousContentIdentity != nil
            && previousContentIdentity != contentIdentity
        if changesContentIdentity {
            transitionPresentation.holdCarryoverForRetarget()
            installedIncomingTransitionContentDescriptor = nil
        }
        let previousVisualContent = changesContentIdentity
            && !hasCarryoverContent
            ? carryoverSourceContent
            : nil
        let resolvedImageLoadPolicy: ImageLoadPolicy =
            previousContentIdentity == contentIdentity
                && previousImageLoadPolicy == .foreground
                && imageLoadPolicy == .cachedOnly
                ? .foreground
                : imageLoadPolicy
        let cachedImageSelectionPolicy = CachedImageSelectionPolicy.base(
            requiredQuality: requiredImageQuality,
            allowsLocalLargeUpgrade: allowsLocalLargeImageUpgrade
        )
        if let deferredImageInstall,
           deferredImageInstall.contentIdentity != contentIdentity
            || imageSources?.descriptor(for: deferredImageInstall.quality)
                != deferredImageInstall.descriptor
            || imageSources?.cachedImageCandidateDescriptors(
                selectionPolicy: cachedImageSelectionPolicy
            ).contains(deferredImageInstall.descriptor) != true {
            self.deferredImageInstall = nil
        }
        let descriptorRetention = cachedImageDescriptorRetention(
            displayedDescriptor: displayedImageDescriptor,
            displayedImageIsPresent: imageView.image != nil,
            representedContentIdentity: representedContentIdentity,
            targetContentIdentity: contentIdentity,
            imageSources: imageSources,
            selectionPolicy: cachedImageSelectionPolicy
        )
        let rejectsDisplayedImageForSelectionPolicy =
            descriptorRetention.rejectsDisplayedImage
        let retainedDescriptor = descriptorRetention.descriptor
        let retainedCachedStaticImageURL = retainedDescriptor.flatMap {
            imageSources?.largeDescriptor == $0
                ? DownloadableMediaCache.shared.localFileURL(for: $0)
                : nil
        }
        cancelIncompatibleImageLoads(
            tokenIndex: tokenIndex,
            imageSources: imageSources,
            requiredImageQuality: requiredImageQuality,
            allowsImageLoading: resolvedImageLoadPolicy == .foreground,
            allowsLocalLargeImageUpgrade: allowsLocalLargeImageUpgrade
        )
        representedContentIdentity = contentIdentity
        self.imageSources = imageSources
        self.requiredImageQuality = requiredImageQuality
        configuredImageLoadPolicy = resolvedImageLoadPolicy
        self.allowsLocalLargeImageUpgrade = allowsLocalLargeImageUpgrade
        displayedImageDescriptor = retainedDescriptor
        displayedImageHasLocalFile = retainedCachedStaticImageURL != nil

        let requiredDescriptor = imageSources?.descriptor(
            for: requiredImageQuality
        )
        descriptor = retainedDescriptor ?? requiredDescriptor
        if retainedDescriptor == nil {
            if rejectsDisplayedImageForSelectionPolicy {
                finishTransitionContent()
            } else if imageSources != nil,
               let previousVisualContent {
                setCarryoverContent(previousVisualContent)
            } else if imageSources != nil,
               let previousContentIdentity,
               let previousImage = imageView.image,
               !hasCarryoverContent {
                // A visible cell retargeted to a different token keeps its
                // old art as a carryover so the new content crossfades in —
                // an instant retoken reads as a pop. An already-active
                // carryover stays: it holds the region's pre-change pixels.
                setCarryoverContent(MobilePlayerBrowserCarryoverContent(
                    identity: previousContentIdentity,
                    image: previousImage,
                    usesNativeMetalCardCornerMask:
                        imageView.usesNativeMetalCardCornerMask
                ))
            } else if changesContentIdentity, !hasCarryoverContent {
                clearTransitionContent()
            }
            if displayedImageDescriptor == nil {
                imageView.image = nil
            }
        }
        if imageSources == nil {
            clearTransitionContent()
            setTransitionPlaceholderTone(false)
        }
        if previousContentIdentity != contentIdentity {
            configuredMediaTime = CACurrentMediaTime()
        }
        let usesNativeMetalCardCornerMask = (displayedImageDescriptor
            ?? requiredDescriptor)?
            .usesNativeMetalCardPresentation
            ?? missingDescriptorFallbackSpec.usesNativeMetalCardCornerMask
        imageView.usesNativeMetalCardCornerMask = usesNativeMetalCardCornerMask

        if displayedImageDescriptor == nil, let requiredDescriptor {
            displayedImageSize = PlayerCollectionBrowserSupport.fallbackImageSize(
                for: requiredDescriptor
            )
        } else if displayedImageDescriptor == nil {
            displayedImageSize = missingDescriptorFallbackSpec.aspectSize
        }
        placeholderView.configure(
            with: PlayerMediaPlaceholderSpec(
                aspectSize: displayedImageSize,
                usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask
            )
        )
        placeholderView.setHidden(
            displayedImageDescriptor != nil
                || transitionPresentation.holdsToneForBaseLoad,
            animated: false
        )
        accessibilityLabel = Strings.pagePosition(
            current: tokenIndex + 1,
            total: max(itemCount, tokenIndex + 1)
        )

        switch resolvedImageLoadPolicy {
        case .disabled:
            break
        case .cachedOnly:
            installCachedImageIfAvailable(
                animatedWhenLoaded: false,
                tracksLocalFileAvailability: false,
                prewarmsNativeMetalCardFace: false
            )
        case .foreground:
            if previousImageLoadPolicy != .foreground,
               let retainedDescriptor {
                prewarmNativeMetalCardFaceIfNeeded(
                    for: retainedDescriptor,
                    cachedStaticImageURL: retainedCachedStaticImageURL
                )
            }
            startImageLoadIfNeeded(animatedWhenLoaded: true)
        }
    }

    func resumeImageLoadIfNeeded(tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex,
              configuredImageLoadPolicy == .foreground else {
            return
        }
        startImageLoadIfNeeded(animatedWhenLoaded: true)
    }

    func promoteImageLoadToForegroundIfNeeded(tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex,
              configuredImageLoadPolicy != .foreground else {
            return
        }
        configuredImageLoadPolicy = .foreground
        reconcileForegroundImageState()
        startImageLoadIfNeeded(animatedWhenLoaded: true)
    }

    func demoteImageLoadToCachedOnlyIfNeeded(tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex,
              configuredImageLoadPolicy == .foreground else {
            return
        }
        configuredImageLoadPolicy = .cachedOnly
        cancelImageLoad()
    }

    func prepareForTransitionSnapshot(tokenIndex: Int) -> Bool {
        guard representedTokenIndex == tokenIndex else { return false }
        startImageLoadIfNeeded(animatedWhenLoaded: false)
        guard imageView.image != nil else { return false }
        placeholderView.setHidden(true, animated: false)
        return true
    }

    func cancelImageLoad(ifRepresenting tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex else { return }
        cancelImageLoad()
    }

    func cancelImageLoad() {
        Self.cancelImageLoads(&imageLoads)
    }

    private static func cancelImageLoads(
        _ imageLoads: inout [CollectionBrowseImageQuality: ImageLoad]
    ) {
        let cancellations = imageLoads.values.compactMap { $0.cancellation }
        imageLoads.removeAll()
        cancellations.forEach { $0() }
    }

    private func cancelIncompatibleImageLoads(
        tokenIndex: Int,
        imageSources: CollectionBrowseImageSources?,
        requiredImageQuality: CollectionBrowseImageQuality,
        allowsImageLoading: Bool,
        allowsLocalLargeImageUpgrade: Bool
    ) {
        guard representedTokenIndex == tokenIndex,
              allowsImageLoading,
              let previousSources = self.imageSources,
              let imageSources else {
            cancelImageLoad()
            return
        }

        let incompatibleQualities = imageLoads.keys.filter { quality in
            let descriptor = imageSources.descriptor(for: quality)
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

    private func startImageLoadIfNeeded(animatedWhenLoaded: Bool) {
        guard representedTokenIndex != nil,
              let imageSources else {
            return
        }
        if imageView.image != nil, displayedImageQuality == .large { return }

        let cache = DownloadableMediaCache.shared
        installCachedImageIfAvailable(
            animatedWhenLoaded: animatedWhenLoaded,
            tracksLocalFileAvailability: true,
            prewarmsNativeMetalCardFace: true
        )
        if deferredImageInstall?.quality.canReplace(requiredImageQuality)
            == true {
            return
        }

        if displayedImageQuality != .large,
           CollectionBrowseImageLoadPolicy.allowsLocalLargeImagePromotion(
               requiredQuality: requiredImageQuality,
               hasDistinctLargeImage: imageSources.largeDescriptor
                   != imageSources.thumbnailDescriptor,
               largeImageIsLocallyAvailable: cache.localFileURL(
                   for: imageSources.largeDescriptor
               ) != nil,
               allowsPromotion: allowsLocalLargeImageUpgrade
           ) {
            startImageLoad(
                quality: .large,
                animatedWhenLoaded: animatedWhenLoaded,
                fallbackQualityOnFailure: imageView.image == nil ? .thumbnail : nil
            )
            return
        }

        if let displayedImageQuality,
           displayedImageQuality.canReplace(requiredImageQuality) {
            return
        }

        if requiredImageQuality == .large,
           imageView.image == nil,
           imageSources.thumbnailDescriptor != imageSources.largeDescriptor,
           cache.localFileURL(for: imageSources.thumbnailDescriptor) != nil {
            startImageLoad(
                quality: .thumbnail,
                animatedWhenLoaded: animatedWhenLoaded
            )
        }
        startImageLoad(
            quality: requiredImageQuality,
            animatedWhenLoaded: animatedWhenLoaded
        )
    }

    private func reconcileForegroundImageState() {
        guard let displayedImageDescriptor else { return }
        let descriptorCanSatisfyLarge =
            imageSources?.largeDescriptor == displayedImageDescriptor
        let cachedStaticImageURL = descriptorCanSatisfyLarge
            ? DownloadableMediaCache.shared.localFileURL(
                for: displayedImageDescriptor
            )
            : nil
        displayedImageHasLocalFile = descriptorCanSatisfyLarge
            && cachedStaticImageURL != nil
        prewarmNativeMetalCardFaceIfNeeded(
            for: displayedImageDescriptor,
            cachedStaticImageURL: cachedStaticImageURL
        )
    }

    private func installCachedImageIfAvailable(
        animatedWhenLoaded: Bool,
        tracksLocalFileAvailability: Bool,
        prewarmsNativeMetalCardFace: Bool
    ) {
        guard let tokenIndex = representedTokenIndex,
              let imageSources,
              let cachedImage = imageSources.highestQualityCachedImage(
                in: DownloadableMediaCache.shared,
                selectionPolicy: .base(
                    requiredQuality: requiredImageQuality,
                    allowsLocalLargeUpgrade: allowsLocalLargeImageUpgrade
                )
              ),
              displayedImageDescriptor != cachedImage.descriptor
                || imageView.image == nil else {
            return
        }
        let toneRequiresFade = transitionPresentation.holdsToneForBaseLoad
            && (transitionPresentation.toneHeldSince.map {
                CACurrentMediaTime() - $0 > Self.configureFrameInstallGrace
            } ?? true)
        setImage(
            cachedImage.image,
            descriptor: cachedImage.descriptor,
            quality: cachedImage.quality,
            tokenIndex: tokenIndex,
            animated: animatedWhenLoaded
                && (imageView.image != nil
                    || hasCarryoverContent
                    || fadesFirstImage
                    || toneRequiresFade
                    || CACurrentMediaTime() - configuredMediaTime
                        > Self.configureFrameInstallGrace),
            tracksLocalFileAvailability: tracksLocalFileAvailability,
            prewarmsNativeMetalCardFace: prewarmsNativeMetalCardFace
        )
    }

    private func startImageLoad(
        quality requestedQuality: CollectionBrowseImageQuality,
        animatedWhenLoaded: Bool,
        fallbackQualityOnFailure: CollectionBrowseImageQuality? = nil
    ) {
        guard let tokenIndex = representedTokenIndex,
              let imageSources else {
            return
        }

        let descriptor = imageSources.descriptor(for: requestedQuality)
        guard let resolvedQuality = imageSources.quality(of: descriptor) else {
            return
        }
        if var imageLoad = imageLoads[resolvedQuality] {
            imageLoad.fallbackQualityOnFailure = fallbackQualityOnFailure
            imageLoads[resolvedQuality] = imageLoad
            return
        }
        let loadID = UUID()
        let cancellation = DownloadableMediaCache.shared.loadImage(for: descriptor) { [weak self] image in
            Task { @MainActor in
                guard let self,
                      let imageLoad = self.imageLoads[resolvedQuality],
                      imageLoad.id == loadID else {
                    return
                }
                self.imageLoads.removeValue(forKey: resolvedQuality)
                guard self.representedTokenIndex == tokenIndex,
                      self.imageSources?.descriptor(for: resolvedQuality)
                        == descriptor else {
                    return
                }
                guard let image else {
                    if let fallbackQualityOnFailure = imageLoad.fallbackQualityOnFailure,
                       self.imageView.image == nil {
                        self.startImageLoad(
                            quality: fallbackQualityOnFailure,
                            animatedWhenLoaded: animatedWhenLoaded
                        )
                    } else if self.imageView.image == nil,
                              self.imageLoads.isEmpty {
                        // Nothing else will run for this cell, so the
                        // transition's tone has to come off here too or it
                        // stays an opaque tile until the cell is recycled.
                        self.fadeOutCarryoverContentIfNeeded()
                        self.clearTransitionPlaceholderTone(animated: true)
                    }
                    return
                }
                self.setImage(
                    image,
                    descriptor: descriptor,
                    quality: resolvedQuality,
                    tokenIndex: tokenIndex,
                    animated: animatedWhenLoaded
                )
            }
        }
        if imageLoads[resolvedQuality] == nil {
            imageLoads[resolvedQuality] = ImageLoad(
                id: loadID,
                cancellation: cancellation,
                fallbackQualityOnFailure: fallbackQualityOnFailure
            )
        }
    }

    func transitionSnapshot(afterScreenUpdates: Bool) -> TransitionSnapshot? {
        layoutIfNeeded()
        let mediaFrame = PlayerAspectFitLayout.centeredRect(
            for: displayedImageSize,
            in: contentView.bounds
        )
        guard let clippedMediaFrame = PlayerBrowserGridGeometry.visibleRect(
            mediaFrame,
            clippedTo: contentView.bounds
        ) else {
            return nil
        }

        let snapshotFrame = CGRect(origin: .zero, size: clippedMediaFrame.size)
        let snapshotView: UIView
        if let croppedSnapshot = contentView.resizableSnapshotView(
            from: clippedMediaFrame,
            afterScreenUpdates: afterScreenUpdates,
            withCapInsets: .zero
        ) {
            croppedSnapshot.frame = snapshotFrame
            snapshotView = croppedSnapshot
        } else {
            snapshotView = makeTransitionMediaFallback(frame: snapshotFrame)
        }
        snapshotView.clipsToBounds = true
        return TransitionSnapshot(
            frameInWindow: contentView.convert(clippedMediaFrame, to: nil),
            view: snapshotView
        )
    }

    private func makeTransitionMediaFallback(frame: CGRect) -> UIView {
        guard let content = carryoverSourceContent else {
            if transitionPresentation.holdsToneForBaseLoad {
                let toneView = UIView(frame: frame)
                toneView.backgroundColor = mobilePlayerBrowserPlaceholderToneColor
                toneView.isOpaque = true
                toneView.isUserInteractionEnabled = false
                return toneView
            }
            let placeholder = PlayerMediaPlaceholderView(frame: frame)
            placeholder.configure(
                with: PlayerMediaPlaceholderSpec(
                    aspectSize: displayedImageSize,
                    usesNativeMetalCardCornerMask:
                        imageView.usesNativeMetalCardCornerMask
                )
            )
            placeholder.layoutIfNeeded()
            return placeholder
        }

        let container = UIView(frame: frame)
        container.makeBackgroundTransparent()
        container.isUserInteractionEnabled = false
        if transitionPresentation.holdsToneForBaseLoad {
            container.backgroundColor = mobilePlayerBrowserPlaceholderToneColor
        }
        container.addSubview(
            makeTransitionMediaFallbackImageView(
                layer: content.primary,
                frame: container.bounds
            )
        )
        if let qualityUpgrade = content.qualityUpgrade {
            container.addSubview(
                makeTransitionMediaFallbackImageView(
                    layer: qualityUpgrade,
                    frame: container.bounds
                )
            )
        }
        container.layoutIfNeeded()
        return container
    }

    private func makeTransitionMediaFallbackImageView(
        layer: MobilePlayerBrowserCarryoverLayer,
        frame: CGRect
    ) -> NativeMetalCardCornerMaskedImageView {
        let fallbackImageView = Self.makeContentImageView(frame: frame)
        fallbackImageView.image = layer.image
        fallbackImageView.usesNativeMetalCardCornerMask =
            layer.usesNativeMetalCardCornerMask
        fallbackImageView.alpha = layer.alpha
        return fallbackImageView
    }

    func refreshAvailableImageIfNeeded(notification: Notification) {
        guard configuredImageLoadPolicy == .foreground,
              representedTokenIndex != nil,
              let imageSources else {
            return
        }
        if imageView.image != nil, displayedImageQuality == .large { return }

        let cache = DownloadableMediaCache.shared
        let descriptorsWorthLoading = imageSources.descriptorsByDescendingQuality.filter {
            guard imageView.image != nil,
                  let displayedImageQuality,
                  let quality = imageSources.quality(of: $0) else {
                return true
            }
            return quality != displayedImageQuality
                && quality.canReplace(displayedImageQuality)
        }
        guard descriptorsWorthLoading.contains(where: {
            cache.fileAvailabilityChange(notification, affects: $0)
        }) else {
            return
        }

        startImageLoadIfNeeded(animatedWhenLoaded: true)
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

    func setImage(
        _ image: UIImage,
        descriptor: DownloadableMediaDescriptor,
        quality: CollectionBrowseImageQuality,
        tokenIndex: Int,
        animated: Bool,
        tracksLocalFileAvailability: Bool = true,
        prewarmsNativeMetalCardFace: Bool = true
    ) {
        guard representedTokenIndex == tokenIndex,
              imageSources?.descriptor(for: quality) == descriptor else {
            return
        }
        guard quality.canReplace(displayedImageQuality) else {
            return
        }
        if let matchingLoad = imageLoads.removeValue(forKey: quality) {
            matchingLoad.cancellation?()
        }
        let replacedLoads = imageLoads.keys
            .filter { $0.rawValue < quality.rawValue }
            .compactMap { imageLoads.removeValue(forKey: $0)?.cancellation }
        replacedLoads.forEach { $0() }
        if let deferredImageInstall,
           !quality.canReplace(deferredImageInstall.quality) {
            return
        }
        let previousImage = imageView.image
        let destinationOverlayOpacity =
            transitionPresentation.destinationOverlayOpacity
        if animated,
           previousImage.map({ $0 !== image }) == true,
           destinationOverlayOpacity.map({ $0 < 1 }) == true,
           let representedContentIdentity {
            deferredImageInstall = DeferredImageInstall(
                image: image,
                descriptor: descriptor,
                quality: quality,
                contentIdentity: representedContentIdentity
            )
            return
        }
        deferredImageInstall = nil
        self.descriptor = descriptor
        displayedImageDescriptor = descriptor
        let descriptorCanSatisfyLarge = imageSources?.largeDescriptor == descriptor
        let cachedStaticImageURL = descriptorCanSatisfyLarge
            && (tracksLocalFileAvailability || prewarmsNativeMetalCardFace)
            ? DownloadableMediaCache.shared.localFileURL(for: descriptor)
            : nil
        displayedImageHasLocalFile = tracksLocalFileAvailability
            && descriptorCanSatisfyLarge
            && cachedStaticImageURL != nil
        displayedImageSize = image.size
        let previousMask = imageView.usesNativeMetalCardCornerMask
        imageView.usesNativeMetalCardCornerMask =
            descriptor.usesNativeMetalCardPresentation
        imageView.image = image
        placeholderView.setHidden(true, animated: animated)
        if previousImage == nil {
            clearTransitionPlaceholderTone(animated: animated)
        }
        if animated, previousImage == nil, !hasCarryoverContent {
            // A late-arriving first image fades in over the placeholder — an
            // instant reveal of detailed art reads as a pop. A cell that is
            // not in the render tree yet (materializing inside a commit's
            // own layout pass) applies the final alpha silently instead —
            // deliberate: those installs are the region's continuity content
            // and any genuinely new pixels there are covered by a carryover.
            imageView.alpha = 0
            Self.animateContentFade { self.imageView.alpha = 1 }
        } else if previousImage == nil {
            imageView.layer.removeAllAnimations()
            imageView.alpha = 1
        }
        if animated,
           let previousImage,
           let representedContentIdentity,
           previousImage !== image,
           destinationOverlayOpacity == nil,
           !hasCarryoverContent,
           imageView.layer.animation(forKey: "opacity") == nil {
            setCarryoverContent(MobilePlayerBrowserCarryoverContent(
                identity: representedContentIdentity,
                image: previousImage,
                usesNativeMetalCardCornerMask: previousMask
            ))
        }
        if animated {
            fadeOutCarryoverContentIfNeeded()
        } else if hasCarryoverContent {
            clearTransitionContent()
        }
        if prewarmsNativeMetalCardFace {
            prewarmNativeMetalCardFaceIfNeeded(
                for: descriptor,
                cachedStaticImageURL: cachedStaticImageURL
            )
        }
    }

    private func applyDeferredImageInstallIfPossible(
        requiresOpaqueOverlay: Bool = false
    ) {
        guard let deferredImageInstall else { return }
        let overlayOpacity = transitionPresentation.destinationOverlayOpacity
        let canInstall = requiresOpaqueOverlay
            ? overlayOpacity.map { $0 >= 1 } == true
            : overlayOpacity == nil
        guard canInstall else { return }
        self.deferredImageInstall = nil
        guard representedContentIdentity
                == deferredImageInstall.contentIdentity else {
            return
        }
        let usesForegroundImageLoading =
            configuredImageLoadPolicy == .foreground
        setImage(
            deferredImageInstall.image,
            descriptor: deferredImageInstall.descriptor,
            quality: deferredImageInstall.quality,
            tokenIndex: deferredImageInstall.contentIdentity.tokenIndex,
            animated: true,
            tracksLocalFileAvailability: usesForegroundImageLoading,
            prewarmsNativeMetalCardFace: usesForegroundImageLoading
        )
    }

    private func prewarmNativeMetalCardFaceIfNeeded(
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
}

extension CollectionBrowseImageSources {
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
            return [thumbnailDescriptor, smallThumbnailDescriptor]
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
