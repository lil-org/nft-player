// ∅ 2026 lil org

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private nonisolated final class DownloadableMediaMemoryRetirement:
    @unchecked Sendable {

    private var cache: NSCache<NSString, DownloadableMediaImage>?
    private var retainedImages: [DownloadableMediaImage]

    init(
        cache: NSCache<NSString, DownloadableMediaImage>,
        retainedImages: [DownloadableMediaImage]
    ) {
        self.cache = cache
        self.retainedImages = retainedImages
    }

    func releaseContents() {
        cache?.removeAllObjects()
        cache = nil
        retainedImages.removeAll(keepingCapacity: false)
    }
}

private actor DownloadableMediaMemoryRetirementLane {
    func retire(_ retirement: DownloadableMediaMemoryRetirement) -> Bool {
        let ranOnMainThread = Thread.isMainThread
        retirement.releaseContents()
        return ranOnMainThread
    }
}

@MainActor
final class DownloadableMediaMemoryCache {
    struct Lookup {
        let image: DownloadableMediaImage?
        let recordsDiskAccess: Bool
    }

    private static let defaultMemoryCostLimit = 512 * 1024 * 1024
    private static let memoryCostLimitPerDescriptor = 64 * 1024 * 1024
#if os(iOS)
    private static let mediaFirstCountLimit = 240
    private static let minimumMediaFirstMemoryCostLimit: UInt64 = 768 * 1024 * 1024
    private static let maximumMediaFirstMemoryCostLimit: UInt64 = 2 * 1024 * 1024 * 1024
#endif

    private var cache = NSCache<NSString, DownloadableMediaImage>()
    private let retirementLane = DownloadableMediaMemoryRetirementLane()
    private var retirementTask: Task<Bool, Never>?
#if !os(iOS)
    private var keysByCollection = [String: Set<String>]()
#endif
#if DEBUG && os(iOS)
    private var injectedImages = [String: DownloadableMediaImage]()
    private var acceptsInsertionsForTesting = true
#endif

    init(
        decodedDescriptorCount: Int = PlayerDownloadableMediaWindowLayout
            .decodedWindowCapacity
    ) {
        configureLimits(decodedDescriptorCount: decodedDescriptorCount)
    }

    func lookup(forKey key: String) -> Lookup {
#if DEBUG && os(iOS)
        if let image = injectedImages[key] {
            return Lookup(image: image, recordsDiskAccess: false)
        }
#endif
        return Lookup(
            image: cache.object(forKey: key as NSString),
            recordsDiskAccess: true
        )
    }

    func image(forKey key: String) -> DownloadableMediaImage? {
        lookup(forKey: key).image
    }

    @discardableResult
    func insert(
        _ image: DownloadableMediaImage,
        forKey key: String,
        collectionId: String
    ) -> Bool {
#if DEBUG && os(iOS)
        guard acceptsInsertionsForTesting else { return false }
#endif
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: estimatedCost(of: image)
        )
        let wasAdmitted = cache.object(forKey: key as NSString) != nil
#if !os(iOS)
        if wasAdmitted {
            keysByCollection[collectionId, default: []].insert(key)
        }
#endif
        return wasAdmitted
    }

    var metadataEntryCapacity: Int {
        max(cache.countLimit, 1)
    }

    func configureLimits(decodedDescriptorCount: Int) {
#if os(iOS)
        if cache.countLimit != Self.mediaFirstCountLimit {
            cache.countLimit = Self.mediaFirstCountLimit
        }
        let totalCostLimit = Self.mediaFirstMemoryCostLimit
        if cache.totalCostLimit != totalCostLimit {
            cache.totalCostLimit = totalCostLimit
        }
#else
        let countLimit = max(
            PlayerDownloadableMediaWindowLayout.decodedWindowCapacity,
            decodedDescriptorCount
        )
        if cache.countLimit != countLimit {
            cache.countLimit = countLimit
        }
        let descriptorDerivedCostLimit = Self.memoryCostLimit(
            for: countLimit
        )
#if os(macOS)
        let totalCostLimit = min(
            descriptorDerivedCostLimit,
            Self.macMemoryCostLimit
        )
#else
        let totalCostLimit = descriptorDerivedCostLimit
#endif
        if cache.totalCostLimit != totalCostLimit {
            cache.totalCostLimit = totalCostLimit
        }
#endif
    }

    func evictOutsideWindow(
        collectionId: String,
        allowedKeys: Set<String>
    ) {
#if !os(iOS)
        let existingKeys = keysByCollection[collectionId] ?? []
        for key in existingKeys where !allowedKeys.contains(key) {
            cache.removeObject(forKey: key as NSString)
        }
        keysByCollection[collectionId] = existingKeys.intersection(allowedKeys)
#endif
    }

    func evictOutsideActiveCollection(_ collectionId: String) {
#if !os(iOS)
        for (storedCollectionId, keys) in keysByCollection
        where storedCollectionId != collectionId {
            keys.forEach { cache.removeObject(forKey: $0 as NSString) }
        }
        keysByCollection = keysByCollection.filter {
            $0.key == collectionId
        }
#endif
    }

    func clear() {
        let retiredCache = cache
        let replacementCache = NSCache<NSString, DownloadableMediaImage>()
        replacementCache.countLimit = retiredCache.countLimit
        replacementCache.totalCostLimit = retiredCache.totalCostLimit
        cache = replacementCache
#if !os(iOS)
        keysByCollection.removeAll(keepingCapacity: false)
#endif

#if DEBUG && os(iOS)
        let retainedImages = Array(injectedImages.values)
        injectedImages.removeAll(keepingCapacity: false)
#else
        let retainedImages = [DownloadableMediaImage]()
#endif
        let retirement = DownloadableMediaMemoryRetirement(
            cache: retiredCache,
            retainedImages: retainedImages
        )
        let previousTask = retirementTask
        let retirementLane = retirementLane
        retirementTask = Task(priority: .utility) {
            _ = await previousTask?.value
            return await retirementLane.retire(retirement)
        }
    }

#if DEBUG && os(iOS)
    func installInjectedImage(
        _ image: DownloadableMediaImage,
        forKey key: String
    ) {
        injectedImages[key] = image
    }

    func removeInjectedImage(forKey key: String) {
        injectedImages.removeValue(forKey: key)
    }

    func setAcceptsInsertionsForTesting(_ acceptsInsertions: Bool) {
        acceptsInsertionsForTesting = acceptsInsertions
    }

    func waitForRetirementForTesting() async -> Bool? {
        await retirementTask?.value
    }
#endif

    private func estimatedCost(of image: DownloadableMediaImage) -> Int {
#if os(macOS)
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            return max(width * height * 4, 1)
        }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
#else
        if let cgImage = image.cgImage {
            return max(cgImage.bytesPerRow * cgImage.height, 1)
        }
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(width * height * 4, 1)
#endif
    }

    private static func memoryCostLimit(
        for decodedDescriptorCapacity: Int
    ) -> Int {
        max(
            defaultMemoryCostLimit,
            max(decodedDescriptorCapacity, 1) * memoryCostLimitPerDescriptor
        )
    }

#if os(macOS)
    private static var macMemoryCostLimit: Int {
        let physicalMemoryLimit = min(
            ProcessInfo.processInfo.physicalMemory / 8,
            UInt64(1024 * 1024 * 1024)
        )
        return max(defaultMemoryCostLimit, Int(physicalMemoryLimit))
    }
#endif

#if os(iOS)
    private static var mediaFirstMemoryCostLimit: Int {
        let boundedLimit = min(
            max(
                ProcessInfo.processInfo.physicalMemory / 4,
                minimumMediaFirstMemoryCostLimit
            ),
            maximumMediaFirstMemoryCostLimit
        )
        return Int(boundedLimit)
    }
#endif
}
