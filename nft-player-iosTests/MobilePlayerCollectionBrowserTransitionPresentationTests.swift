// ∅ 2026 lil org

import QuartzCore
import UIKit
import XCTest
@testable import nft_player_ios

@MainActor
private func runTransitionTrackingRunLoop(
    until condition: () -> Bool,
    timeout: TimeInterval = 0.25
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), deadline.timeIntervalSinceNow > 0 {
        _ = RunLoop.main.run(mode: .tracking, before: deadline)
    }
    return condition()
}

nonisolated final class MobilePlayerCollectionBrowserTransitionPresentationTests: XCTestCase {}

@MainActor
extension MobilePlayerCollectionBrowserTransitionPresentationTests {

    private final class TransitionSupportCollectionView: UICollectionView {
        var reversesVisibleItemOrder = false

        override var indexPathsForVisibleItems: [IndexPath] {
            let indexPaths = super.indexPathsForVisibleItems
            guard reversesVisibleItemOrder else { return indexPaths }
            return indexPaths.sorted { $0.item > $1.item }
        }
    }

    private final class TransitionSupportDataSource: NSObject,
        UICollectionViewDataSource {
        let itemCount: Int

        init(itemCount: Int = 1) {
            self.itemCount = itemCount
        }

        func collectionView(
            _: UICollectionView,
            numberOfItemsInSection _: Int
        ) -> Int {
            itemCount
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(
                withReuseIdentifier: "cell",
                for: indexPath
            )
        }
    }

    private final class ControlledFadeAnimator {
        private var completions = [((Bool) -> Void)]()

        var pendingCompletionCount: Int {
            completions.count
        }

        func animate(
            _ animations: @escaping () -> Void,
            completion: ((Bool) -> Void)?
        ) {
            animations()
            if let completion {
                completions.append(completion)
            }
        }

        func completeNext() {
            completions.removeFirst()(true)
        }
    }

    private func makeImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image {
            color.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func makePresentation(
        contentFadeAnimator: MobilePlayerCollectionBrowserTransitionPresentation
            .ContentFadeAnimator? = nil
    ) -> (
        UIView,
        MobilePlayerCollectionBrowserTransitionPresentation
    ) {
        let contentView = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        return (
            contentView,
            MobilePlayerCollectionBrowserTransitionPresentation(
                contentView: contentView,
                contentFadeAnimator: contentFadeAnimator
            )
        )
    }

    private func incomingContentContainer(in contentView: UIView) -> UIView? {
        contentView.subviews.first { subview in
            subview.subviews.contains {
                $0 is NativeMetalCardCornerMaskedImageView
            }
        }
    }

    private func makeImageSources() -> CollectionBrowseImageSources {
        let descriptor = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "0",
            tokenIndex: 0,
            media: .staticImage(
                url: URL(fileURLWithPath: "/thumbnail.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
        return CollectionBrowseImageSources(
            thumbnailDescriptor: descriptor,
            largeDescriptor: descriptor
        )
    }

    private func makeDistinctImageSources() -> CollectionBrowseImageSources {
        let thumbnail = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "0",
            tokenIndex: 0,
            media: .staticImage(
                url: URL(fileURLWithPath: "/thumbnail.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
        let large = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "0",
            tokenIndex: 0,
            media: .staticImage(
                url: URL(fileURLWithPath: "/large.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserMid
        )
        return CollectionBrowseImageSources(
            thumbnailDescriptor: thumbnail,
            largeDescriptor: large
        )
    }

    private func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func installBaseImage(
        _ image: UIImage,
        in cell: MobilePlayerCollectionBrowserCell
    ) {
        guard let imageView = cell.contentView.subviews.first(where: {
            $0 is NativeMetalCardCornerMaskedImageView
        }) as? NativeMetalCardCornerMaskedImageView else {
            XCTFail("Missing base image view")
            return
        }
        imageView.image = image
    }

    private func makeTransitionSupportFixture(
        itemCount: Int = 1,
        itemSize: CGSize? = nil
    ) -> (
        viewportView: UIView,
        collectionView: TransitionSupportCollectionView,
        dataSource: TransitionSupportDataSource,
        cell: MobilePlayerCollectionBrowserCell
    ) {
        let viewportView = UIView(frame: CGRect(
            x: 37,
            y: 83,
            width: 100,
            height: 100
        ))
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = itemSize ?? viewportView.bounds.size
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let collectionView = TransitionSupportCollectionView(
            frame: viewportView.bounds,
            collectionViewLayout: layout
        )
        collectionView.register(
            MobilePlayerCollectionBrowserCell.self,
            forCellWithReuseIdentifier: "cell"
        )
        let dataSource = TransitionSupportDataSource(itemCount: itemCount)
        collectionView.dataSource = dataSource
        viewportView.addSubview(collectionView)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let cell = collectionView.cellForItem(
            at: IndexPath(item: 0, section: 0)
        ) as! MobilePlayerCollectionBrowserCell
        return (viewportView, collectionView, dataSource, cell)
    }

    func testIncomingContentCanBeReplacedAndCleared() {
        let (_, presentation) = makePresentation()
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 7
        )

        presentation.installIncoming(
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.4,
            animated: false,
            identity: identity
        )
        XCTAssertEqual(
            presentation.presentationState,
            .incoming(identity: identity)
        )
        XCTAssertEqual(
            presentation.destinationOverlayOpacity ?? -1,
            0.4,
            accuracy: 0.0001
        )

        let replacementImage = makeImage(.blue)
        presentation.installIncoming(
            image: replacementImage,
            usesNativeMetalCardCornerMask: true,
            targetAlpha: 0.8,
            animated: false,
            identity: identity
        )
        XCTAssertEqual(
            presentation.presentationState,
            .incoming(identity: identity)
        )
        XCTAssertEqual(presentation.upgradeState, .none)
        XCTAssertEqual(
            presentation.destinationOverlayOpacity ?? -1,
            0.8,
            accuracy: 0.0001
        )
        let sourceContent = presentation.sourceContent(
            baseImageView: NativeMetalCardCornerMaskedImageView(frame: .zero),
            baseIdentity: nil
        )
        XCTAssertTrue(sourceContent?.primary.image === replacementImage)
        XCTAssertEqual(
            sourceContent?.primary.usesNativeMetalCardCornerMask,
            true
        )

        presentation.clear()
        XCTAssertEqual(presentation.presentationState, .empty)
        XCTAssertNil(presentation.destinationOverlayOpacity)
    }

    func testIncomingAlphaInterruptsOnlyOpacityWhenRequested() throws {
        let (contentView, presentation) = makePresentation()
        presentation.installIncoming(
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 1,
            animated: false,
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            )
        )
        let container = try XCTUnwrap(
            incomingContentContainer(in: contentView)
        )
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        let transform = CABasicAnimation(keyPath: "transform.scale")
        transform.duration = 10
        container.layer.add(opacity, forKey: "opacity")
        container.layer.add(transform, forKey: "transform")

        presentation.setIncomingAlpha(0.4)

        XCTAssertNotNil(container.layer.animation(forKey: "opacity"))
        XCTAssertNotNil(container.layer.animation(forKey: "transform"))

        presentation.setIncomingAlpha(0.7, interruptingAnimation: true)

        XCTAssertNil(container.layer.animation(forKey: "opacity"))
        XCTAssertNotNil(container.layer.animation(forKey: "transform"))
        XCTAssertEqual(container.alpha, 0.7, accuracy: 0.0001)
    }

    func testPreservingClearRetainsOnlyCarryover() {
        let (_, presentation) = makePresentation()
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 9
        )
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: makeImage(.green),
            usesNativeMetalCardCornerMask: false
        ))

        presentation.clear(preservingCarryover: true)
        XCTAssertEqual(
            presentation.presentationState,
            .carryover(identity: identity, phase: .held)
        )
        XCTAssertTrue(presentation.hasCarryoverContent)

        presentation.clear()
        XCTAssertEqual(presentation.presentationState, .empty)
        XCTAssertFalse(presentation.hasCarryoverContent)
    }

    func testClearingInvalidatesScheduledCarryoverFade() async {
        let (_, presentation) = makePresentation()
        let carryoverIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 11
        )
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: carryoverIdentity,
            image: makeImage(.yellow),
            usesNativeMetalCardCornerMask: false
        ))

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        presentation.fadeCarryoverIfNeeded()
        XCTAssertEqual(
            presentation.presentationState,
            .carryover(identity: carryoverIdentity, phase: .fading)
        )
        presentation.clear()
        let replacementIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 12
        )
        presentation.installIncoming(
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.7,
            animated: false,
            identity: replacementIdentity
        )
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        XCTAssertEqual(
            presentation.presentationState,
            .incoming(identity: replacementIdentity)
        )
        XCTAssertFalse(presentation.hasCarryoverContent)
        XCTAssertEqual(
            presentation.destinationOverlayOpacity ?? -1,
            0.7,
            accuracy: 0.0001
        )
    }

    func testCarryoverFadeStartsDuringTrackingRunLoopMode() {
        let animator = ControlledFadeAnimator()
        let (_, presentation) = makePresentation {
            animator.animate($0, completion: $1)
        }
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 13
        )
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: makeImage(.yellow),
            usesNativeMetalCardCornerMask: false
        ))

        presentation.fadeCarryoverIfNeeded()

        XCTAssertTrue(runTransitionTrackingRunLoop {
            animator.pendingCompletionCount == 1
        })
        animator.completeNext()
        XCTAssertEqual(presentation.presentationState, .empty)
    }

    func testRetargetReholdsScheduledCarryoverFade() async {
        let animator = ControlledFadeAnimator()
        let (_, presentation) = makePresentation {
            animator.animate($0, completion: $1)
        }
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 20
        )
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        ))

        presentation.fadeCarryoverIfNeeded()
        presentation.holdCarryoverForRetarget()
        await waitForNextMainQueueTurn()

        XCTAssertEqual(animator.pendingCompletionCount, 0)
        XCTAssertEqual(
            presentation.presentationState,
            .carryover(identity: identity, phase: .held)
        )
        XCTAssertTrue(presentation.hasCarryoverContent)
        XCTAssertEqual(
            presentation.sourceContent(
                baseImageView: NativeMetalCardCornerMaskedImageView(frame: .zero),
                baseIdentity: nil
            )?.identity,
            identity
        )
    }

    func testRetargetRejectsRunningCarryoverFadeCompletion() async {
        let animator = ControlledFadeAnimator()
        let (_, presentation) = makePresentation {
            animator.animate($0, completion: $1)
        }
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 21
        )
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        ))

        presentation.fadeCarryoverIfNeeded()
        await waitForNextMainQueueTurn()
        XCTAssertEqual(animator.pendingCompletionCount, 1)

        presentation.holdCarryoverForRetarget()
        animator.completeNext()

        XCTAssertEqual(
            presentation.presentationState,
            .carryover(identity: identity, phase: .held)
        )
        XCTAssertTrue(presentation.hasCarryoverContent)
        XCTAssertEqual(
            presentation.sourceContent(
                baseImageView: NativeMetalCardCornerMaskedImageView(frame: .zero),
                baseIdentity: nil
            )?.identity,
            identity
        )
    }

    func testCellRetargetReholdsFadingCarryover() async {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let originalIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 22
        )
        let replacementIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 23
        )
        let imageSources = makeImageSources()
        cell.configure(
            contentIdentity: originalIdentity,
            itemCount: 24,
            imageSources: imageSources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        installBaseImage(makeImage(.red), in: cell)
        cell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: originalIdentity,
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        ))

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        cell.fadeOutCarryoverContentIfBaseReady()
        cell.configure(
            contentIdentity: replacementIdentity,
            itemCount: 24,
            imageSources: imageSources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        await waitForNextMainQueueTurn()

        XCTAssertEqual(
            cell.carryoverSourceContent?.identity,
            originalIdentity
        )
        XCTAssertFalse(cell.canSelect(representing: replacementIdentity))
    }

    func testSameIdentityConfigureDoesNotReholdFadingCarryover() async {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 24
        )
        let imageSources = makeImageSources()
        let configure = {
            cell.configure(
                contentIdentity: identity,
                itemCount: 25,
                imageSources: imageSources,
                requiredImageQuality: .thumbnail,
                missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                    thumbnailAspectRatio: nil
                ),
                imageLoadPolicy: .disabled
            )
        }
        configure()
        installBaseImage(makeImage(.red), in: cell)
        cell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        ))

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        cell.fadeOutCarryoverContentIfBaseReady()
        configure()
        await waitForNextMainQueueTurn()

        XCTAssertNil(cell.carryoverSourceContent)
    }

    func testToneStateIsExplicitAndResettable() {
        let (_, presentation) = makePresentation()

        XCTAssertEqual(presentation.toneState, .hidden)
        presentation.holdTone()
        XCTAssertEqual(presentation.toneState, .heldForBaseLoad)
        XCTAssertTrue(presentation.holdsToneForBaseLoad)

        presentation.clearTone(animated: false)
        XCTAssertEqual(presentation.toneState, .hidden)
        XCTAssertFalse(presentation.holdsToneForBaseLoad)
    }

    func testToneFadeAndStaleCompletionAreDeterministic() {
        let animator = ControlledFadeAnimator()
        let (_, presentation) = makePresentation {
            animator.animate($0, completion: $1)
        }

        presentation.holdTone()
        presentation.clearTone(animated: true)

        XCTAssertEqual(presentation.toneState, .fading)
        XCTAssertEqual(animator.pendingCompletionCount, 1)

        presentation.holdTone()
        animator.completeNext()

        XCTAssertEqual(presentation.toneState, .heldForBaseLoad)
        XCTAssertTrue(presentation.holdsToneForBaseLoad)

        presentation.clearTone(animated: true)
        XCTAssertEqual(presentation.toneState, .fading)
        animator.completeNext()

        XCTAssertEqual(presentation.toneState, .hidden)
        XCTAssertFalse(presentation.holdsToneForBaseLoad)
    }

    func testCarryoverUpgradeIsInstalledWithItsPresentationAlpha() {
        let (_, presentation) = makePresentation()
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 13
        )
        let primaryImage = makeImage(.red)
        let upgradeImage = makeImage(.blue)
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            primary: MobilePlayerBrowserCarryoverLayer(
                image: primaryImage,
                usesNativeMetalCardCornerMask: false,
                alpha: 1
            ),
            qualityUpgrade: MobilePlayerBrowserCarryoverLayer(
                image: upgradeImage,
                usesNativeMetalCardCornerMask: true,
                alpha: 0.35
            )
        ))

        XCTAssertEqual(presentation.upgradeState, .installed)
        let content = presentation.sourceContent(
            baseImageView: NativeMetalCardCornerMaskedImageView(frame: .zero),
            baseIdentity: nil
        )
        XCTAssertTrue(content?.primary.image === primaryImage)
        XCTAssertTrue(content?.qualityUpgrade?.image === upgradeImage)
        XCTAssertEqual(
            content?.qualityUpgrade?.alpha ?? -1,
            0.35,
            accuracy: 0.0001
        )
    }

    func testUpgradeFadeRejectsStaleCompletionAndCommitsCurrentCompletion() {
        let animator = ControlledFadeAnimator()
        let (_, presentation) = makePresentation {
            animator.animate($0, completion: $1)
        }
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 14
        )
        let initialImage = makeImage(.red)
        presentation.installIncoming(
            image: initialImage,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 1,
            animated: false,
            identity: identity
        )

        presentation.installIncoming(
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: true,
            targetAlpha: 0.8,
            animated: true,
            identity: identity
        )

        XCTAssertEqual(presentation.upgradeState, .fading)
        XCTAssertEqual(animator.pendingCompletionCount, 1)

        let replacementImage = makeImage(.green)
        presentation.installIncoming(
            image: replacementImage,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.6,
            animated: false,
            identity: identity
        )
        animator.completeNext()

        XCTAssertEqual(presentation.upgradeState, .none)
        var content = presentation.sourceContent(
            baseImageView: NativeMetalCardCornerMaskedImageView(frame: .zero),
            baseIdentity: nil
        )
        XCTAssertTrue(content?.primary.image === replacementImage)

        let committedImage = makeImage(.yellow)
        presentation.installIncoming(
            image: committedImage,
            usesNativeMetalCardCornerMask: true,
            targetAlpha: 1,
            animated: true,
            identity: identity
        )

        XCTAssertEqual(presentation.upgradeState, .fading)
        animator.completeNext()

        XCTAssertEqual(presentation.upgradeState, .none)
        content = presentation.sourceContent(
            baseImageView: NativeMetalCardCornerMaskedImageView(frame: .zero),
            baseIdentity: nil
        )
        XCTAssertTrue(content?.primary.image === committedImage)
        XCTAssertTrue(
            content?.primary.usesNativeMetalCardCornerMask == true
        )
    }

    func testReplacementInvalidatesCarryoverAnimationCompletion() async {
        let animator = ControlledFadeAnimator()
        let (_, presentation) = makePresentation {
            animator.animate($0, completion: $1)
        }
        let carryoverIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 15
        )
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: carryoverIdentity,
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        ))
        presentation.fadeCarryoverIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        XCTAssertEqual(animator.pendingCompletionCount, 1)

        let replacementIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 16
        )
        let replacementImage = makeImage(.blue)
        presentation.installIncoming(
            image: replacementImage,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.7,
            animated: false,
            identity: replacementIdentity
        )
        animator.completeNext()

        XCTAssertEqual(
            presentation.presentationState,
            .incoming(identity: replacementIdentity)
        )
        let content = presentation.sourceContent(
            baseImageView: NativeMetalCardCornerMaskedImageView(frame: .zero),
            baseIdentity: nil
        )
        XCTAssertTrue(content?.primary.image === replacementImage)
    }

    func testCarryoverIdentityControlsSelection() {
        let (_, presentation) = makePresentation()
        let previousIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 3
        )
        let currentIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 4
        )
        presentation.installCarryover(MobilePlayerBrowserCarryoverContent(
            identity: previousIdentity,
            image: makeImage(.purple),
            usesNativeMetalCardCornerMask: false
        ))

        XCTAssertTrue(presentation.allowsSelection(
            representing: previousIdentity
        ))
        XCTAssertFalse(presentation.allowsSelection(
            representing: currentIdentity
        ))
    }

    func testCellRetargetConvertsIncomingOverlayIntoCarryover() {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let sources = makeImageSources()
        let originalIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        cell.configure(
            contentIdentity: originalIdentity,
            itemCount: 3,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        let overlayIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 1
        )
        cell.installTransitionContent(
            image: makeImage(.red),
            descriptor: sources.thumbnailDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 1,
            animated: false,
            identity: overlayIdentity
        )
        let replacementIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 2
        )

        cell.configure(
            contentIdentity: replacementIdentity,
            itemCount: 3,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )

        XCTAssertEqual(
            cell.carryoverSourceContent?.identity,
            overlayIdentity
        )
        XCTAssertFalse(cell.canSelect(representing: replacementIdentity))
    }

    func testCellQualityUpgradeUsesCapturableCarryover() throws {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let sources = makeDistinctImageSources()
        let thumbnail = makeImage(.red)
        let large = makeImage(.blue)
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        let carryover = try XCTUnwrap(cell.carryoverSourceContent)
        XCTAssertTrue(carryover.primary.image === thumbnail)
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertTrue(baseImageView.image === large)
    }

    func testCellQualityUpgradeWaitsForPartialOverlayToClear() throws {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let sources = makeDistinctImageSources()
        let thumbnail = makeImage(.red)
        let large = makeImage(.blue)
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        cell.installTransitionContent(
            image: makeImage(.green),
            descriptor: sources.largeDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )

        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )
        XCTAssertTrue(baseImageView.image === thumbnail)
        XCTAssertNil(baseImageView.layer.animationKeys())
        XCTAssertTrue(cell.carryoverSourceContent?.primary.image === thumbnail)

        cell.clearTransitionContent()

        XCTAssertTrue(baseImageView.image === thumbnail)
        XCTAssertFalse(cell.hasCarryoverContent)

        cell.installDeferredBaseImageIfNoIncomingOverlay()

        XCTAssertTrue(baseImageView.image === large)
        XCTAssertNil(baseImageView.layer.animationKeys())
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(cell.carryoverSourceContent?.primary.image === thumbnail)
    }

    func testDeferredQualityUpgradeSurvivesRepeatedOverlayReplacement() throws {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let sources = makeDistinctImageSources()
        let thumbnail = makeImage(.red)
        let large = makeImage(.blue)
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            thumbnail,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        let baseImageView = try XCTUnwrap(
            cell.contentView.subviews.first {
                $0 is NativeMetalCardCornerMaskedImageView
            } as? NativeMetalCardCornerMaskedImageView
        )

        cell.installTransitionContent(
            image: makeImage(.green),
            descriptor: sources.largeDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )
        cell.setImage(
            large,
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        for color in [UIColor.purple, .green] {
            cell.clearTransitionContent()
            XCTAssertTrue(baseImageView.image === thumbnail)
            XCTAssertFalse(cell.hasCarryoverContent)
            cell.installTransitionContent(
                image: makeImage(color),
                descriptor: sources.largeDescriptor,
                usesNativeMetalCardCornerMask: false,
                targetAlpha: 0.25,
                animated: false,
                identity: identity
            )
        }

        cell.finishTransitionContent()

        XCTAssertTrue(baseImageView.image === large)
        XCTAssertTrue(cell.hasCarryoverContent)
        XCTAssertTrue(cell.carryoverSourceContent?.primary.image === thumbnail)
    }

    func testDeferredQualityUpgradeDoesNotSurviveIdentityChanges() {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let replacementIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 1
        )
        let sources = makeDistinctImageSources()
        let configure = { (contentIdentity: MobilePlayerBrowserContentIdentity) in
            cell.configure(
                contentIdentity: contentIdentity,
                itemCount: 2,
                imageSources: sources,
                requiredImageQuality: .large,
                missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                    thumbnailAspectRatio: nil
                ),
                imageLoadPolicy: .disabled
            )
        }
        configure(identity)
        cell.setImage(
            makeImage(.red),
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        cell.installTransitionContent(
            image: makeImage(.green),
            descriptor: sources.largeDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )
        cell.setImage(
            makeImage(.blue),
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        configure(replacementIdentity)
        configure(identity)
        cell.clearTransitionContent()
        cell.installDeferredBaseImageIfNoIncomingOverlay()

        XCTAssertTrue(cell.needsCarryoverContent)
        XCTAssertFalse(cell.hasCarryoverContent)
    }

    func testDeferredQualityUpgradeDoesNotSurviveReuse() {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let sources = makeDistinctImageSources()
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .large,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setImage(
            makeImage(.red),
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )
        cell.installTransitionContent(
            image: makeImage(.green),
            descriptor: sources.largeDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 0.25,
            animated: false,
            identity: identity
        )
        cell.setImage(
            makeImage(.blue),
            descriptor: sources.largeDescriptor,
            quality: .large,
            tokenIndex: 0,
            animated: true,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        cell.prepareForGridModePhantomReuse()

        XCTAssertTrue(cell.needsCarryoverContent)
        XCTAssertFalse(cell.hasCarryoverContent)
    }

    func testNonanimatedImageInstallClearsCarryoverSynchronously() throws {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 0
        )
        let sources = makeImageSources()
        let previousImage = makeImage(.red)
        let image = makeImage(.blue)
        cell.configure(
            contentIdentity: identity,
            itemCount: 1,
            imageSources: sources,
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.setCarryoverContent(MobilePlayerBrowserCarryoverContent(
            identity: identity,
            image: previousImage,
            usesNativeMetalCardCornerMask: false
        ))

        cell.setImage(
            image,
            descriptor: sources.thumbnailDescriptor,
            quality: .thumbnail,
            tokenIndex: 0,
            animated: false,
            tracksLocalFileAvailability: false,
            prewarmsNativeMetalCardFace: false
        )

        XCTAssertFalse(cell.hasCarryoverContent)
        let source = try XCTUnwrap(cell.carryoverSourceContent)
        XCTAssertTrue(source.primary.image === image)
    }

    func testCellReuseClearsPresentationIdentityToneAndContent() {
        let cell = MobilePlayerCollectionBrowserCell(frame: CGRect(
            x: 0,
            y: 0,
            width: 120,
            height: 80
        ))
        let originalIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 17
        )
        cell.configure(
            contentIdentity: originalIdentity,
            itemCount: 20,
            imageSources: makeImageSources(),
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )
        cell.installTransitionContent(
            image: makeImage(.purple),
            descriptor: makeImageSources().thumbnailDescriptor,
            usesNativeMetalCardCornerMask: false,
            targetAlpha: 1,
            animated: false,
            identity: originalIdentity
        )
        cell.setTransitionPlaceholderTone(true)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.duration = 10
        cell.layer.add(opacity, forKey: "opacity")
        cell.alpha = 0.2

        XCTAssertEqual(
            cell.carryoverSourceContent?.identity,
            originalIdentity
        )

        cell.prepareForGridModePhantomReuse()

        XCTAssertNil(cell.carryoverSourceContent)
        XCTAssertFalse(cell.keepsTransitionPlaceholderToneForPendingLoad)
        XCTAssertFalse(cell.canSelect(representing: originalIdentity))
        XCTAssertNil(cell.layer.animation(forKey: "opacity"))
        XCTAssertEqual(cell.alpha, 1)

        let replacementIdentity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 18
        )
        cell.configure(
            contentIdentity: replacementIdentity,
            itemCount: 20,
            imageSources: makeImageSources(),
            requiredImageQuality: .thumbnail,
            missingDescriptorFallbackSpec: PlayerMediaPlaceholderSpec(
                thumbnailAspectRatio: nil
            ),
            imageLoadPolicy: .disabled
        )

        XCTAssertTrue(cell.canSelect(representing: replacementIdentity))
        XCTAssertNil(cell.carryoverSourceContent)
    }

    func testSameIdentityThumbnailPolicyRejectsDistinctLargeDescriptor() {
        let thumbnail = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "19",
            tokenIndex: 19,
            media: .staticImage(
                url: URL(fileURLWithPath: "/thumbnail-19.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserThumbnail
        )
        let large = CollectionCatalogDownloadableMediaDescriptor(
            collectionId: "collection",
            tokenId: "19",
            tokenIndex: 19,
            media: .staticImage(
                url: URL(fileURLWithPath: "/large-19.webp"),
                fileExtension: "webp"
            ),
            purpose: .collectionBrowserMid
        )
        let sources = CollectionBrowseImageSources(
            thumbnailDescriptor: thumbnail,
            largeDescriptor: large
        )
        let identity = MobilePlayerBrowserContentIdentity(
            collectionId: "collection",
            tokenIndex: 19
        )

        let rejected = cachedImageDescriptorRetention(
            displayedDescriptor: large,
            displayedImageIsPresent: true,
            representedContentIdentity: identity,
            targetContentIdentity: identity,
            imageSources: sources,
            selectionPolicy: .base(
                requiredQuality: .thumbnail,
                allowsLocalLargeUpgrade: false
            )
        )

        XCTAssertNil(rejected.descriptor)
        XCTAssertTrue(rejected.rejectsDisplayedImage)

        let retained = cachedImageDescriptorRetention(
            displayedDescriptor: large,
            displayedImageIsPresent: true,
            representedContentIdentity: identity,
            targetContentIdentity: identity,
            imageSources: sources,
            selectionPolicy: .base(
                requiredQuality: .thumbnail,
                allowsLocalLargeUpgrade: true
            )
        )

        XCTAssertEqual(retained.descriptor, large)
        XCTAssertFalse(retained.rejectsDisplayedImage)
    }

    func testTransitionSupportUsesAttachedCellThenLayoutForViewportIntersection() {
        let fixture = makeTransitionSupportFixture()
        let indexPath = IndexPath(item: 0, section: 0)
        fixture.cell.frame.origin.x = fixture.viewportView.bounds.maxX

        XCTAssertFalse(
            MobilePlayerCollectionBrowserTransitionSupport
                .itemIntersectsViewport(
                    at: indexPath,
                    cell: fixture.cell,
                    collectionView: fixture.collectionView,
                    viewportView: fixture.viewportView
                )
        )
        XCTAssertTrue(
            MobilePlayerCollectionBrowserTransitionSupport
                .itemIntersectsViewport(
                    at: indexPath,
                    cell: nil,
                    collectionView: fixture.collectionView,
                    viewportView: fixture.viewportView
                )
        )
    }

    func testTransitionSupportCapturesInViewportCoordinates() {
        let fixture = makeTransitionSupportFixture()
        fixture.collectionView.frame.origin = CGPoint(x: 9, y: 13)
        let content = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 7
            ),
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        )
        fixture.cell.setCarryoverContent(content)

        let sources = MobilePlayerCollectionBrowserTransitionSupport
            .captureSources(from: [fixture.cell], in: fixture.viewportView)

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].viewportRect.origin, CGPoint(x: 9, y: 13))
        XCTAssertEqual(sources[0].content?.identity, content.identity)
    }

    func testTransitionSupportMatchesAgainstClippedDestinationArea() {
        let fixture = makeTransitionSupportFixture()
        fixture.cell.frame = CGRect(x: -80, y: 0, width: 100, height: 100)
        let content = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            ),
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        )
        let source = MobilePlayerBrowserGridCarryoverSource(
            viewportRect: CGRect(x: 0, y: 0, width: 11, height: 100),
            content: content
        )

        let result = MobilePlayerCollectionBrowserTransitionSupport
            .installCarryover(
                sources: [source],
                in: fixture.collectionView,
                viewportView: fixture.viewportView,
                anchorItemIndex: 0,
                hasImageSources: { _ in true }
            )

        XCTAssertFalse(result)
        XCTAssertEqual(
            fixture.cell.carryoverSourceContent?.identity,
            content.identity
        )
    }

    func testTransitionSupportConsumesCapturedCarryoverSource() throws {
        let fixture = makeTransitionSupportFixture(
            itemCount: 2,
            itemSize: CGSize(width: 100, height: 50)
        )
        fixture.collectionView.reversesVisibleItemOrder = true
        let content = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            ),
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        )
        let source = MobilePlayerBrowserGridCarryoverSource(
            viewportRect: fixture.viewportView.bounds,
            content: content
        )

        let holdsTone = MobilePlayerCollectionBrowserTransitionSupport
            .installCarryover(
                sources: [source],
                in: fixture.collectionView,
                viewportView: fixture.viewportView,
                anchorItemIndex: 0,
                hasImageSources: { _ in true }
            )
        let installedCount = fixture.collectionView.visibleCells.compactMap {
            ($0 as? MobilePlayerCollectionBrowserCell)?
                .carryoverSourceContent
        }.count
        let anchorCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 0, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)
        let neighborCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 1, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)

        XCTAssertTrue(holdsTone)
        XCTAssertEqual(installedCount, 1)
        XCTAssertEqual(
            anchorCell.carryoverSourceContent?.identity,
            content.identity
        )
        XCTAssertNil(neighborCell.carryoverSourceContent)
    }

    func testTransitionSupportPreservesMaximumWildcardCoverage() throws {
        let fixture = makeTransitionSupportFixture(
            itemCount: 2,
            itemSize: CGSize(width: 100, height: 50)
        )
        let flexibleContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            ),
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        )
        let constrainedContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 9
            ),
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        )
        let sources = [
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: fixture.viewportView.bounds,
                content: flexibleContent
            ),
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: CGRect(x: 0, y: 0, width: 100, height: 45),
                content: constrainedContent
            ),
        ]

        let holdsTone = MobilePlayerCollectionBrowserTransitionSupport
            .installCarryover(
                sources: sources,
                in: fixture.collectionView,
                viewportView: fixture.viewportView,
                anchorItemIndex: 0,
                hasImageSources: { _ in true }
            )
        let firstCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 0, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)
        let secondCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 1, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)

        XCTAssertFalse(holdsTone)
        XCTAssertEqual(
            firstCell.carryoverSourceContent?.identity,
            constrainedContent.identity
        )
        XCTAssertEqual(
            secondCell.carryoverSourceContent?.identity,
            flexibleContent.identity
        )
    }

    func testTransitionSupportPrefersAssignedSourceOverWildcard() throws {
        let fixture = makeTransitionSupportFixture(
            itemCount: 2,
            itemSize: CGSize(width: 100, height: 50)
        )
        let wildcardContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            ),
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        )
        let assignedContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 9
            ),
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        )
        let sources = [
            MobilePlayerBrowserGridCarryoverSource(
                destinationItem: 0,
                viewportRect: fixture.viewportView.bounds,
                content: nil
            ),
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: fixture.viewportView.bounds,
                content: wildcardContent
            ),
            MobilePlayerBrowserGridCarryoverSource(
                destinationItem: 0,
                viewportRect: CGRect(x: 0, y: 0, width: 100, height: 50),
                content: assignedContent
            ),
        ]

        _ = MobilePlayerCollectionBrowserTransitionSupport.installCarryover(
            sources: sources,
            in: fixture.collectionView,
            viewportView: fixture.viewportView,
            anchorItemIndex: 0,
            hasImageSources: { _ in true }
        )
        let assignedCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 0, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)
        let wildcardCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 1, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)

        XCTAssertEqual(
            assignedCell.carryoverSourceContent?.identity,
            assignedContent.identity
        )
        XCTAssertEqual(
            wildcardCell.carryoverSourceContent?.identity,
            wildcardContent.identity
        )
    }

    func testTransitionSupportUsesWildcardWhenAssignmentDoesNotOverlap() {
        let fixture = makeTransitionSupportFixture()
        let assignedContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            ),
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        )
        let wildcardContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 9
            ),
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        )
        let sources = [
            MobilePlayerBrowserGridCarryoverSource(
                destinationItem: 0,
                viewportRect: CGRect(x: 200, y: 0, width: 100, height: 100),
                content: assignedContent
            ),
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: fixture.viewportView.bounds,
                content: nil
            ),
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: fixture.viewportView.bounds,
                content: wildcardContent
            ),
        ]

        let holdsTone = MobilePlayerCollectionBrowserTransitionSupport
            .installCarryover(
                sources: sources,
                in: fixture.collectionView,
                viewportView: fixture.viewportView,
                anchorItemIndex: 0,
                hasImageSources: { _ in true }
            )

        XCTAssertFalse(holdsTone)
        XCTAssertEqual(
            fixture.cell.carryoverSourceContent?.identity,
            wildcardContent.identity
        )
    }

    func testTransitionSupportUsesWildcardWhenAssignmentHasNoContent() {
        let fixture = makeTransitionSupportFixture()
        let wildcardContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 9
            ),
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        )
        let sources = [
            MobilePlayerBrowserGridCarryoverSource(
                destinationItem: 0,
                viewportRect: fixture.viewportView.bounds,
                content: nil
            ),
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: fixture.viewportView.bounds,
                content: wildcardContent
            ),
        ]

        let holdsTone = MobilePlayerCollectionBrowserTransitionSupport
            .installCarryover(
                sources: sources,
                in: fixture.collectionView,
                viewportView: fixture.viewportView,
                anchorItemIndex: 0,
                hasImageSources: { _ in true }
            )

        XCTAssertFalse(holdsTone)
        XCTAssertEqual(
            fixture.cell.carryoverSourceContent?.identity,
            wildcardContent.identity
        )
    }

    func testTransitionSupportHonorsCapturedDestinationAssignment() throws {
        let fixture = makeTransitionSupportFixture(
            itemCount: 2,
            itemSize: CGSize(width: 100, height: 50)
        )
        let content = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            ),
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        )
        let source = MobilePlayerBrowserGridCarryoverSource(
            destinationItem: 1,
            viewportRect: fixture.viewportView.bounds,
            content: content
        )

        _ = MobilePlayerCollectionBrowserTransitionSupport.installCarryover(
            sources: [source],
            in: fixture.collectionView,
            viewportView: fixture.viewportView,
            anchorItemIndex: 0,
            hasImageSources: { _ in true }
        )
        let firstCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 0, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)
        let secondCell = try XCTUnwrap(fixture.collectionView.cellForItem(
            at: IndexPath(item: 1, section: 0)
        ) as? MobilePlayerCollectionBrowserCell)

        XCTAssertNil(firstCell.carryoverSourceContent)
        XCTAssertEqual(secondCell.carryoverSourceContent?.identity, content.identity)
    }

    func testTransitionSupportRequiresMoreThanHalfWildcardCoverage() {
        func installsSource(width: CGFloat) -> Bool {
            let fixture = makeTransitionSupportFixture()
            let content = MobilePlayerBrowserCarryoverContent(
                identity: MobilePlayerBrowserContentIdentity(
                    collectionId: "collection",
                    tokenIndex: 8
                ),
                image: makeImage(.blue),
                usesNativeMetalCardCornerMask: false
            )
            _ = MobilePlayerCollectionBrowserTransitionSupport.installCarryover(
                sources: [MobilePlayerBrowserGridCarryoverSource(
                    viewportRect: CGRect(
                        x: 0,
                        y: 0,
                        width: width,
                        height: 100
                    ),
                    content: content
                )],
                in: fixture.collectionView,
                viewportView: fixture.viewportView,
                anchorItemIndex: 0,
                hasImageSources: { _ in true }
            )
            return fixture.cell.carryoverSourceContent != nil
        }

        XCTAssertFalse(installsSource(width: 50))
        XCTAssertTrue(installsSource(width: 50.01))
    }

    func testTransitionSupportBreaksEqualWildcardOverlapBySourceOrder() throws {
        let fixture = makeTransitionSupportFixture()
        let firstContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 8
            ),
            image: makeImage(.blue),
            usesNativeMetalCardCornerMask: false
        )
        let secondContent = MobilePlayerBrowserCarryoverContent(
            identity: MobilePlayerBrowserContentIdentity(
                collectionId: "collection",
                tokenIndex: 9
            ),
            image: makeImage(.red),
            usesNativeMetalCardCornerMask: false
        )
        let sources = [
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: CGRect(x: 0, y: 0, width: 60, height: 100),
                content: firstContent
            ),
            MobilePlayerBrowserGridCarryoverSource(
                viewportRect: CGRect(x: 40, y: 0, width: 60, height: 100),
                content: secondContent
            ),
        ]

        _ = MobilePlayerCollectionBrowserTransitionSupport.installCarryover(
            sources: sources,
            in: fixture.collectionView,
            viewportView: fixture.viewportView,
            anchorItemIndex: 0,
            hasImageSources: { _ in true }
        )

        XCTAssertEqual(
            try XCTUnwrap(fixture.cell.carryoverSourceContent).identity,
            firstContent.identity
        )
    }

    func testTransitionSupportReportsHeldPlaceholderTone() {
        let fixture = makeTransitionSupportFixture()

        let result = MobilePlayerCollectionBrowserTransitionSupport
            .installCarryover(
                sources: [],
                in: fixture.collectionView,
                viewportView: fixture.viewportView,
                anchorItemIndex: 0,
                hasImageSources: { _ in true }
            )

        XCTAssertTrue(result)
    }
}
