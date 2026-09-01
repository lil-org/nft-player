// ∅ 2026 lil org

import CoreGraphics
import Foundation

nonisolated enum PlayerAspectFitLayout {
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

nonisolated enum PlayerDisplayMode: Hashable, Sendable {
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

nonisolated enum PlayerCollectionBrowserSupport {
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

nonisolated enum PlayerCollectionBrowseMediaWindowLayout {
    static let fileDescriptorCapacity = 60
    static let decodedDescriptorCapacity = 30

    static func fileOffsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        offsets(
            direction: direction,
            radii: PlayerCollectionBrowseMediaWindowPolicy.fileRadii(
                prefetchStride: prefetchStride
            )
        )
    }

    static func decodedOffsets(
        prefetchStride: Int,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        offsets(
            direction: direction,
            radii: PlayerCollectionBrowseMediaWindowPolicy.decodedRadii(
                prefetchStride: prefetchStride
            )
        )
    }

    static func makeWindow(
        centeredAt tokenIndex: Int,
        itemCount: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        prefetchStride: Int,
        columnCount: Int,
        compactCoverage: PlayerCollectionBrowseMediaWindowPolicy.CompactCoverage? = nil,
        visibleTokenRange: ClosedRange<Int>? = nil,
        includesDecodedDescriptors: Bool = true,
        decodeVariant: DownloadableMediaImageDecodeVariant = .full,
        descriptorForTokenIndex: (Int) -> CollectionCatalogDownloadableMediaDescriptor?
    ) -> PlayerDownloadableMediaWindow? {
        guard itemCount > 0, (0..<itemCount).contains(tokenIndex) else { return nil }

        let compactCoverage = validatedCompactCoverage(
            compactCoverage,
            centeredAt: tokenIndex,
            itemCount: itemCount
        )
        let effectiveVisibleTokenRange = visibleTokenRange
            ?? compactCoverage?.decodedRange
        let rawFileTokenIndices: [Int]
        let rawDecodedTokenIndices: [Int]
        if let compactCoverage {
            rawFileTokenIndices = directionallyOrderedTokenIndices(
                centeredAt: tokenIndex,
                in: compactCoverage.fileRange,
                direction: direction
            )
            rawDecodedTokenIndices = PlayerCollectionBrowseMediaWindowPolicy
                .nearestFirstTokenIndices(
                    centeredAt: tokenIndex,
                    in: compactCoverage.decodedRange,
                    prefersIncreasingIndices: direction == .forward
                )
        } else {
            rawFileTokenIndices = PlayerDownloadableMediaWindowLayout.indices(
                currentIndex: tokenIndex,
                tokenCount: itemCount,
                offsets: fileOffsets(
                    prefetchStride: prefetchStride,
                    direction: direction
                )
            )
            rawDecodedTokenIndices = PlayerDownloadableMediaWindowLayout.indices(
                currentIndex: tokenIndex,
                tokenCount: itemCount,
                offsets: decodedOffsets(
                    prefetchStride: prefetchStride,
                    direction: direction
                )
            )
        }
        let orderedFileTokenIndices = prioritizedTokenIndices(
            currentIndex: tokenIndex,
            candidateTokenIndices: rawFileTokenIndices,
            visibleTokenRange: effectiveVisibleTokenRange,
            itemCount: itemCount,
            direction: direction
        )
        let orderedDecodedTokenIndices = includesDecodedDescriptors
            ? prioritizedTokenIndices(
                currentIndex: tokenIndex,
                candidateTokenIndices: rawDecodedTokenIndices,
                visibleTokenRange: effectiveVisibleTokenRange,
                itemCount: itemCount,
                direction: direction
            )
            : []
        var descriptorLookup = [Int: CollectionCatalogDownloadableMediaDescriptor]()
        var resolvedTokenIndices = Set<Int>()

        func descriptor(at index: Int) -> CollectionCatalogDownloadableMediaDescriptor? {
            guard resolvedTokenIndices.insert(index).inserted else {
                return descriptorLookup[index]
            }
            guard let descriptor = descriptorForTokenIndex(index),
                  PlayerCollectionBrowserSupport.isAvailable(for: descriptor) else {
                return nil
            }
            descriptorLookup[index] = descriptor
            return descriptor
        }

        let visibleTokenIndices: [Int] = effectiveVisibleTokenRange.map {
            range -> [Int] in
            let lowerBound = max(range.lowerBound, 0)
            let upperBound = min(range.upperBound, itemCount - 1)
            return lowerBound <= upperBound
                ? Array(lowerBound...upperBound)
                : []
        } ?? []
        let availableVisibleTokenIndices = Set<Int>(visibleTokenIndices.filter {
            descriptor(at: $0) != nil
        })
        let decodedTokenIndices = availableTokenIndices(
            orderedTokenIndices: orderedDecodedTokenIndices,
            requiredTokenIndices: availableVisibleTokenIndices,
            capacity: max(
                decodedDescriptorCapacity,
                availableVisibleTokenIndices.count
            ),
            descriptorForTokenIndex: descriptor(at:)
        )
        let fileLookahead = PlayerCollectionBrowseMediaWindowPolicy
            .rowAlignedRefreshDistance(
                prefetchStride: prefetchStride,
                columnCount: columnCount
            )
        let visibleFileCapacity = availableVisibleTokenIndices.count
            .addingReportingOverflow(fileLookahead)
        let fileTokenIndices = availableTokenIndices(
            orderedTokenIndices: orderedFileTokenIndices,
            requiredTokenIndices: availableVisibleTokenIndices.union(
                decodedTokenIndices
            ),
            capacity: max(
                fileDescriptorCapacity,
                visibleFileCapacity.overflow
                    ? Int.max
                    : visibleFileCapacity.partialValue
            ),
            descriptorForTokenIndex: descriptor(at:)
        )

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
            decodedDescriptorCapacity: max(decodedDescriptors.count, 1),
            includesCurrentInDecodedDescriptors: includesDecodedDescriptors,
            decodeVariant: decodeVariant
        )
    }

    private static func validatedCompactCoverage(
        _ coverage: PlayerCollectionBrowseMediaWindowPolicy.CompactCoverage?,
        centeredAt tokenIndex: Int,
        itemCount: Int
    ) -> PlayerCollectionBrowseMediaWindowPolicy.CompactCoverage? {
        guard let coverage,
              coverage.fileRange.lowerBound >= 0,
              coverage.fileRange.upperBound < itemCount,
              coverage.fileRange.contains(tokenIndex),
              coverage.decodedRange.lowerBound >= coverage.fileRange.lowerBound,
              coverage.decodedRange.upperBound <= coverage.fileRange.upperBound,
              coverage.decodedRange.contains(tokenIndex) else {
            return nil
        }
        return coverage
    }

    private static func directionallyOrderedTokenIndices(
        centeredAt tokenIndex: Int,
        in range: ClosedRange<Int>,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        var indices = [tokenIndex]

        func appendIncreasingIndices() {
            var index = tokenIndex
            while index < range.upperBound {
                index += 1
                indices.append(index)
            }
        }

        func appendDecreasingIndices() {
            var index = tokenIndex
            while index > range.lowerBound {
                index -= 1
                indices.append(index)
            }
        }

        switch direction {
        case .forward:
            appendIncreasingIndices()
            appendDecreasingIndices()
        case .backward:
            appendDecreasingIndices()
            appendIncreasingIndices()
        }
        return indices
    }

    private static func prioritizedTokenIndices(
        currentIndex: Int,
        candidateTokenIndices: [Int],
        visibleTokenRange: ClosedRange<Int>?,
        itemCount: Int,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> [Int] {
        let visibleIndices: [Int]
        if let visibleTokenRange {
            let lowerBound = max(visibleTokenRange.lowerBound, 0)
            let upperBound = min(visibleTokenRange.upperBound, itemCount - 1)
            visibleIndices = lowerBound <= upperBound
                ? Array(lowerBound...upperBound)
                : []
        } else {
            visibleIndices = []
        }
        let candidates = Set(candidateTokenIndices).union(visibleIndices)
        guard !candidates.isEmpty else { return [] }
        let visibleCandidates = candidates.filter {
            visibleTokenRange?.contains($0) == true
        }
        var result = [Int]()
        var included = Set<Int>()

        func append(_ index: Int) {
            guard candidates.contains(index), included.insert(index).inserted else {
                return
            }
            result.append(index)
        }

        append(currentIndex)
        visibleCandidates.sorted {
            let lhsDistance = abs($0 - currentIndex)
            let rhsDistance = abs($1 - currentIndex)
            guard lhsDistance == rhsDistance else { return lhsDistance < rhsDistance }
            switch direction {
            case .forward:
                return $0 > $1
            case .backward:
                return $0 < $1
            }
        }.forEach(append)
        candidateTokenIndices.forEach(append)
        return result
    }

    private static func availableTokenIndices(
        orderedTokenIndices: [Int],
        requiredTokenIndices: Set<Int>,
        capacity: Int,
        descriptorForTokenIndex: (Int) -> CollectionCatalogDownloadableMediaDescriptor?
    ) -> [Int] {
        var remainingRequiredTokenIndices = requiredTokenIndices.intersection(
            orderedTokenIndices
        )
        let limit = max(capacity, remainingRequiredTokenIndices.count)
        var result = [Int]()
        result.reserveCapacity(min(limit, orderedTokenIndices.count))

        for tokenIndex in orderedTokenIndices {
            guard descriptorForTokenIndex(tokenIndex) != nil else { continue }
            if remainingRequiredTokenIndices.remove(tokenIndex) != nil {
                result.append(tokenIndex)
            } else if result.count + remainingRequiredTokenIndices.count < limit {
                result.append(tokenIndex)
            }
            if result.count >= limit, remainingRequiredTokenIndices.isEmpty {
                break
            }
        }
        return result
    }

    private static func offsets(
        direction: DownloadableMediaCache.PrefetchDirection,
        radii: PlayerCollectionBrowseMediaWindowPolicy.Radii
    ) -> [Int] {
        return PlayerDownloadableMediaWindowLayout.orderedOffsets(
            direction: direction,
            preferredRadius: radii.preferred,
            oppositeRadius: radii.opposite
        )
    }
}
