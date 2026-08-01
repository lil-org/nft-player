// ∅ 2026 lil org

import CoreGraphics
import Foundation

enum PlayerAspectFitLayout {
    static func size(for contentSize: CGSize, fitting maximumSize: CGSize) -> CGSize {
        guard contentSize.width > 0,
              contentSize.height > 0,
              maximumSize.width > 0,
              maximumSize.height > 0 else {
            return .zero
        }

        let scale = min(
            maximumSize.width / contentSize.width,
            maximumSize.height / contentSize.height
        )
        return CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
    }

    static func centeredRect(for contentSize: CGSize, in bounds: CGRect) -> CGRect {
        let fittedSize = size(for: contentSize, fitting: bounds.size)
        guard fittedSize.width > 0, fittedSize.height > 0 else { return bounds }

        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

enum PlayerDisplayMode: Hashable {
    case collectionBrowser
    case onePerPage

    static func initialMode(
        hasWidgetTokenInsertion: Bool,
        collectionBrowserAvailable: Bool
    ) -> PlayerDisplayMode {
        guard !hasWidgetTokenInsertion, collectionBrowserAvailable else {
            return .onePerPage
        }
        return .collectionBrowser
    }
}

enum PlayerCollectionBrowserSupport {
    static let cardNftCollectionId = "HpGDYGz6aRUs5qbvp1dmWGKTicQctX4PixfcouAQDCHF"
    static let drifella2CollectionId = "7cHTjqr2S8uUCrG3TVFvFix3vcLjhPiwrtRsAeJtESRj"
    static let driladyCollectionId = "96THxzqE5yukFxzsqJaR2SrsLL2wJtuapi6827gkUD6T"
    static let johnCollectionId = "r1pCPYkbbpZWv7RCvuCMtpA3NSQY3fzVFo6HL43A4ot"
    static let miladyAura2AfterDeathCollectionId = "0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d"
    static let miladyAuraPetzCollectionId = "0xc62e3fd5b02618f90dd07d1e478963038fa9089c"
    static let superMetalMonsCollectionId = "0x17abd4cc1382397ec2b675f98621c3ba809897desmm"

    private static let explicitlySupportedCollectionIds: Set<String> = {
        var collectionIds: Set<String> = [
            cardNftCollectionId,
            drifella2CollectionId,
            driladyCollectionId,
            johnCollectionId,
            miladyAura2AfterDeathCollectionId,
            miladyAuraPetzCollectionId,
            superMetalMonsCollectionId,
        ]
        for renderKind in NativeMetalCardRenderKind.allCases {
            collectionIds.insert(renderKind.collectionId)
        }
        return collectionIds
    }()

    static func isAvailable(for descriptor: CollectionCatalogDownloadableMediaDescriptor?) -> Bool {
        guard let descriptor,
              descriptor.isStaticImage else {
            return false
        }
        return isAvailable(forCollectionId: descriptor.collectionId)
            || descriptor.isCollectionBrowserImage
    }

    static func isAvailable(forCollectionId collectionId: String) -> Bool {
        TokenGenerator.isBundledWebGenerativeCollection(id: collectionId)
            || explicitlySupportedCollectionIds.contains(collectionId)
            || CollectionCatalog.standardThumbsPathsAvailable(
                specificCollectionId: collectionId
            )
    }

    static func fallbackImageSize(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) -> CGSize {
        if let thumbnailAspectRatio = descriptor.thumbnailAspectRatio {
            return thumbnailAspectRatio.size
        }

        if let renderKind = descriptor.nativeMetalCardRenderKind {
            return renderKind.staticImageSize
        }

        switch descriptor.collectionId {
        case cardNftCollectionId:
            return CGSize(width: 776, height: 1098)
        case drifella2CollectionId:
            return CGSize(width: 1200, height: 1295)
        case driladyCollectionId:
            return CGSize(width: 932, height: 1006)
        default:
            return CGSize(width: 1, height: 1)
        }
    }
}

enum PlayerCollectionBrowseMediaWindowLayout {
    private static let decodedPreferredViewportRadius = 2
    private static let decodedOppositeViewportRadius = 1
    private static let filePreferredViewportRadius = 6
    private static let fileOppositeViewportRadius = 2

    static func fileOffsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        offsets(
            prefetchStride: prefetchStride,
            direction: direction,
            preferredViewportRadius: filePreferredViewportRadius,
            oppositeViewportRadius: fileOppositeViewportRadius
        )
    }

    static func decodedOffsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        offsets(
            prefetchStride: prefetchStride,
            direction: direction,
            preferredViewportRadius: decodedPreferredViewportRadius,
            oppositeViewportRadius: decodedOppositeViewportRadius
        )
    }

    static func makeWindow(
        centeredAt tokenIndex: Int,
        itemCount: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        prefetchStride: Int,
        descriptorForTokenIndex: (Int) -> CollectionCatalogDownloadableMediaDescriptor?
    ) -> PlayerDownloadableMediaWindow? {
        guard itemCount > 0, (0..<itemCount).contains(tokenIndex) else { return nil }

        let fileTokenIndices = PlayerDownloadableMediaWindowLayout.indices(
            currentIndex: tokenIndex,
            tokenCount: itemCount,
            offsets: fileOffsets(prefetchStride: prefetchStride, direction: direction)
        )
        let decodedTokenIndices = PlayerDownloadableMediaWindowLayout.indices(
            currentIndex: tokenIndex,
            tokenCount: itemCount,
            offsets: decodedOffsets(prefetchStride: prefetchStride, direction: direction)
        )
        var descriptorLookup = [Int: CollectionCatalogDownloadableMediaDescriptor]()
        descriptorLookup.reserveCapacity(fileTokenIndices.count)
        for index in fileTokenIndices {
            guard let descriptor = descriptorForTokenIndex(index),
                  PlayerCollectionBrowserSupport.isAvailable(for: descriptor) else {
                continue
            }
            descriptorLookup[index] = descriptor
        }

        let descriptors = fileTokenIndices.compactMap { descriptorLookup[$0] }
        guard let currentDescriptor = descriptorLookup[tokenIndex] ?? descriptors.min(by: {
            let lhsDistance = abs($0.tokenIndex - tokenIndex)
            let rhsDistance = abs($1.tokenIndex - tokenIndex)
            return lhsDistance == rhsDistance
                ? $0.tokenIndex < $1.tokenIndex
                : lhsDistance < rhsDistance
        }) else {
            return nil
        }

        let decodedDescriptors = decodedTokenIndices.compactMap { descriptorLookup[$0] }
        let adjacentTokenIndex = PlayerDownloadableMediaWindowLayout.indices(
            currentIndex: tokenIndex,
            tokenCount: itemCount,
            offsets: [direction.adjacentOffset]
        ).first
        return PlayerDownloadableMediaWindow(
            currentDescriptor: currentDescriptor,
            descriptors: descriptors,
            decodedDescriptors: decodedDescriptors,
            adjacentDescriptor: adjacentTokenIndex.flatMap { descriptorLookup[$0] },
            decodedDescriptorCapacity: max(decodedDescriptors.count, 1)
        )
    }

    private static func offsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        preferredViewportRadius: Int,
        oppositeViewportRadius: Int
    ) -> [Int] {
        let cappedPrefetchStride = min(
            max(prefetchStride, 1),
            MobilePlayerBrowserLayout.maximumPrefetchStride
        )
        return PlayerDownloadableMediaWindowLayout.orderedOffsets(
            direction: direction,
            preferredRadius: cappedPrefetchStride * preferredViewportRadius,
            oppositeRadius: cappedPrefetchStride * oppositeViewportRadius
        )
    }
}
