// ∅ 2026 lil org

import QuartzCore
import UIKit

final class MobilePlayerCollectionBrowserCell: UICollectionViewCell {
    typealias ImageLoadPolicy =
        MobilePlayerCollectionBrowserCellImageLoader.ImageLoadPolicy

    enum CachedImageRefreshResult: Equatable {
        case satisfied
        case retry
        case unavailable
    }

    struct TransitionSnapshot {
        let frameInWindow: CGRect
        let view: UIView
    }

    private let placeholderView = PlayerMediaPlaceholderView()
    private let imageView = MobilePlayerCollectionBrowserCell
        .makeContentImageView(frame: .zero)
    private let imageLoader = MobilePlayerCollectionBrowserCellImageLoader()
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
    var descriptor: DownloadableMediaDescriptor? {
        imageLoader.descriptor
    }
    var displayedImageSize: CGSize {
        imageLoader.displayedImageSize
    }
    private var representedContentIdentity: MobilePlayerBrowserContentIdentity? {
        imageLoader.contentIdentity
    }
    private var representedTokenIndex: Int? {
        representedContentIdentity?.tokenIndex
    }
    private var imageSources: CollectionBrowseImageSources? {
        imageLoader.imageSources
    }
    private var requiredImageQuality: CollectionBrowseImageQuality {
        imageLoader.requiredImageQuality
    }
    private var configuredImageLoadPolicy: ImageLoadPolicy {
        imageLoader.imageLoadPolicy
    }
    private var allowsLocalLargeImageUpgrade: Bool {
        imageLoader.allowsLocalLargeImageUpgrade
    }
    private var displayedImageDescriptor: DownloadableMediaDescriptor? {
        imageLoader.displayedImageDescriptor
    }
    private var displayedImageQuality: CollectionBrowseImageQuality? {
        imageLoader.displayedImageQuality
    }
    private var displayedImageHasLocalFile: Bool {
        imageLoader.displayedImageHasLocalFile
    }
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

    var displayedThumbnailWindowEntry: (
        tokenIndex: Int,
        quality: CollectionBrowseImageQuality
    )? {
        guard imageView.image != nil,
              let displayedImageQuality,
              displayedImageQuality != .large,
              let representedTokenIndex else {
            return nil
        }
        return (representedTokenIndex, displayedImageQuality)
    }

    var usesForegroundImageLoading: Bool {
        imageLoader.usesForegroundImageLoading
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
            && imageLoader.hasActiveLoads
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
        imageLoader.reset()
        clearTransitionContent()
        fadesFirstImage = false
        setTransitionPlaceholderTone(false)
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
        imageLoader.discardDeferredImageInstallIfIncompatible(
            contentIdentity: contentIdentity,
            imageSources: imageSources,
            selectionPolicy: cachedImageSelectionPolicy
        )
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
        imageLoader.cancelIncompatibleImageLoads(
            tokenIndex: tokenIndex,
            imageSources: imageSources,
            requiredImageQuality: requiredImageQuality,
            allowsImageLoading: resolvedImageLoadPolicy == .foreground,
            allowsLocalLargeImageUpgrade: allowsLocalLargeImageUpgrade
        )
        let requiredDescriptor = imageSources?.descriptor(
            for: requiredImageQuality
        )
        let fallbackImageSize = requiredDescriptor.map {
            PlayerCollectionBrowserSupport.fallbackImageSize(for: $0)
        } ?? missingDescriptorFallbackSpec.aspectSize
        imageLoader.configure(
            contentIdentity: contentIdentity,
            imageSources: imageSources,
            requiredImageQuality: requiredImageQuality,
            imageLoadPolicy: resolvedImageLoadPolicy,
            allowsLocalLargeImageUpgrade: allowsLocalLargeImageUpgrade,
            retainedDescriptor: retainedDescriptor,
            retainedImageHasLocalFile: retainedCachedStaticImageURL != nil,
            fallbackImageSize: fallbackImageSize
        )
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
            break
        case .foreground:
            if previousImageLoadPolicy != .foreground,
               retainedDescriptor != nil {
                imageLoader.prewarmDisplayedImageIfNeeded(
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
              imageLoader.promoteImageLoadingToForeground() else {
            return
        }
        imageLoader.reconcileForegroundImageState()
        startImageLoadIfNeeded(animatedWhenLoaded: true)
    }

    func demoteImageLoadToCachedOnlyIfNeeded(tokenIndex: Int) {
        guard representedTokenIndex == tokenIndex,
              imageLoader.demoteImageLoadingToCachedOnly() else {
            return
        }
    }

    func refreshCachedImageIfAvailable(
        tokenIndex: Int
    ) -> CachedImageRefreshResult {
        guard representedTokenIndex == tokenIndex,
              configuredImageLoadPolicy == .cachedOnly,
              imageSources != nil else {
            return .unavailable
        }
        guard needsCachedImageRefresh(tokenIndex: tokenIndex) else {
            return .satisfied
        }
        installCachedImageIfAvailable(
            animatedWhenLoaded: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        guard needsCachedImageRefresh(tokenIndex: tokenIndex) else {
            return .satisfied
        }
        guard imageSources?.descriptor(for: requiredImageQuality) != nil else {
            return .unavailable
        }
        return .retry
    }

    func needsCachedImageRefresh(tokenIndex: Int) -> Bool {
        imageLoader.needsCachedImageRefresh(tokenIndex: tokenIndex)
    }

#if DEBUG
    func clearDisplayedImageForTesting() {
        imageLoader.clearDisplayedImageForTesting()
        clearTransitionContent()
        imageView.image = nil
    }
#endif

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
        imageLoader.cancelImageLoads()
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
        if imageLoader.deferredImageQuality?.canReplace(requiredImageQuality)
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
                fallbackQualityOnFailure: imageView.image == nil
                    ? imageSources.fallbackQuality(after: .large)
                    : nil
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

    private func installCachedImageIfAvailable(
        animatedWhenLoaded: Bool,
        tracksLocalFileAvailability: Bool,
        prewarmsNativeMetalCardFace: Bool
    ) {
        guard let cachedImage = imageLoader.cachedImageIfAvailable(
            displayedImageIsPresent: imageView.image != nil
        ) else {
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
            tokenIndex: cachedImage.tokenIndex,
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
        let result = imageLoader.startImageLoad(
            quality: requestedQuality,
            animatedWhenLoaded: animatedWhenLoaded,
            fallbackQualityOnFailure: fallbackQualityOnFailure
        ) { [weak self] completion in
            guard let self else { return }
            guard let image = completion.image else {
                if let fallbackQualityOnFailure =
                    completion.fallbackQualityOnFailure,
                   self.imageView.image == nil {
                    self.startImageLoad(
                        quality: fallbackQualityOnFailure,
                        animatedWhenLoaded: completion.animatedWhenLoaded,
                        fallbackQualityOnFailure: self.imageSources?
                            .fallbackQuality(
                                after: fallbackQualityOnFailure
                            )
                    )
                } else if self.imageView.image == nil,
                          !completion.hasActiveLoads {
                    // No other completion can clear a held transition tone.
                    self.fadeOutCarryoverContentIfNeeded()
                    self.clearTransitionPlaceholderTone(animated: true)
                }
                return
            }
            self.setImage(
                image,
                descriptor: completion.descriptor,
                quality: completion.quality,
                tokenIndex: completion.tokenIndex,
                animated: completion.animatedWhenLoaded
            )
        }
        if result == .missingDescriptor {
            if imageView.image == nil, !imageLoader.hasActiveLoads {
                fadeOutCarryoverContentIfNeeded()
                clearTransitionPlaceholderTone(animated: true)
            }
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
        guard imageLoader.shouldRefreshAvailableImage(
            notification: notification,
            displayedImageIsPresent: imageView.image != nil
        ) else {
            return
        }
        startImageLoadIfNeeded(animatedWhenLoaded: true)
    }

    func updateLocalFileAvailability(
        notification: Notification,
        isAvailable: Bool
    ) {
        imageLoader.updateLocalFileAvailability(
            notification: notification,
            isAvailable: isAvailable
        )
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
        let previousImage = imageView.image
        let destinationOverlayOpacity =
            transitionPresentation.destinationOverlayOpacity
        let disposition = imageLoader.prepareImageInstall(
            image,
            descriptor: descriptor,
            quality: quality,
            tokenIndex: tokenIndex,
            defersInstall: animated
                && previousImage.map { $0 !== image } == true
                && destinationOverlayOpacity.map { $0 < 1 } == true
                && representedContentIdentity != nil,
            tracksLocalFileAvailability: tracksLocalFileAvailability,
            prewarmsNativeMetalCardFace: prewarmsNativeMetalCardFace
        )
        guard case let .install(cachedStaticImageURL) = disposition else {
            return
        }
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
            imageLoader.prewarmImageIfNeeded(
                for: descriptor,
                cachedStaticImageURL: cachedStaticImageURL
            )
        }
    }

    private func applyDeferredImageInstallIfPossible(
        requiresOpaqueOverlay: Bool = false
    ) {
        let overlayOpacity = transitionPresentation.destinationOverlayOpacity
        let canInstall = requiresOpaqueOverlay
            ? overlayOpacity.map { $0 >= 1 } == true
            : overlayOpacity == nil
        guard let deferredImageInstall = imageLoader.takeDeferredImageInstall(
            contentIdentity: representedContentIdentity,
            canInstall: canInstall
        ) else { return }
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

}
