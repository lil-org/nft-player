// ∅ 2026 lil org

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private nonisolated final class DownloadableMediaMemoryEntry {
    let key: String
    let image: DownloadableMediaImage
    private let evictionRecorder: DownloadableMediaMemoryEvictionRecorder

    init(
        key: String,
        image: DownloadableMediaImage,
        evictionRecorder: DownloadableMediaMemoryEvictionRecorder
    ) {
        self.key = key
        self.image = image
        self.evictionRecorder = evictionRecorder
    }

    deinit {
        evictionRecorder.recordEviction(forKey: key)
    }
}

private nonisolated final class DownloadableMediaMemoryEvictionRecorder:
    @unchecked Sendable {

    private let lock = NSLock()
    private var evictedKeys = Set<String>()

    func recordEviction(forKey key: String) {
        _ = lock.withLock { evictedKeys.insert(key) }
    }

    func takeEvictedKeys() -> Set<String> {
        lock.withLock {
            let result = evictedKeys
            evictedKeys.removeAll(keepingCapacity: false)
            return result
        }
    }
}

private nonisolated final class DownloadableMediaMemoryRetirement:
    @unchecked Sendable {

    private var caches: [NSCache<NSString, DownloadableMediaMemoryEntry>]
    private var retainedImages: [DownloadableMediaImage]

    init(
        caches: [NSCache<NSString, DownloadableMediaMemoryEntry>],
        retainedImages: [DownloadableMediaImage]
    ) {
        self.caches = caches
        self.retainedImages = retainedImages
    }

    func releaseContents() {
        autoreleasepool {
            caches.forEach { $0.removeAllObjects() }
            caches.removeAll(keepingCapacity: false)
            retainedImages.removeAll(keepingCapacity: false)
        }
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
    private static let thumbnailCountLimit = 4096
    private static let maximumThumbnailImageCost = 2 * 1024 * 1024
    private static let minimumThumbnailMemoryCostLimit: UInt64 = 256 * 1024 * 1024
    private static let maximumThumbnailMemoryCostLimit: UInt64 = 512 * 1024 * 1024
#endif

    private var cache = NSCache<NSString, DownloadableMediaMemoryEntry>()
#if os(iOS)
    private var thumbnailCache = NSCache<NSString, DownloadableMediaMemoryEntry>()
#endif
    private var evictionRecorder = DownloadableMediaMemoryEvictionRecorder()
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
        return autoreleasepool {
#if os(iOS)
            if let entry = thumbnailCache.object(forKey: key as NSString) {
                return Lookup(image: entry.image, recordsDiskAccess: true)
            }
#endif
            return Lookup(
                image: cache.object(forKey: key as NSString)?.image,
                recordsDiskAccess: true
            )
        }
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
        let imageCost = estimatedCost(of: image)
        let wasAdmitted = autoreleasepool {
#if os(iOS)
            let destinationCache: NSCache<NSString, DownloadableMediaMemoryEntry>
            if imageCost <= Self.maximumThumbnailImageCost {
                destinationCache = thumbnailCache
                cache.removeObject(forKey: key as NSString)
            } else {
                destinationCache = cache
                thumbnailCache.removeObject(forKey: key as NSString)
            }
#else
            let destinationCache = cache
#endif
            destinationCache.setObject(
                DownloadableMediaMemoryEntry(
                    key: key,
                    image: image,
                    evictionRecorder: evictionRecorder
                ),
                forKey: key as NSString,
                cost: imageCost
            )
            return destinationCache.object(forKey: key as NSString) != nil
        }
#if !os(iOS)
        if wasAdmitted {
            keysByCollection[collectionId, default: []].insert(key)
        }
#endif
        return wasAdmitted
    }

    var metadataEntryCapacity: Int {
#if os(iOS)
        max(cache.countLimit + thumbnailCache.countLimit, 1)
#else
        max(cache.countLimit, 1)
#endif
    }

    func takeEvictedKeys() -> Set<String> {
        evictionRecorder.takeEvictedKeys()
    }

    func configureLimits(decodedDescriptorCount: Int) {
#if os(iOS)
        if cache.countLimit != Self.mediaFirstCountLimit {
            cache.countLimit = Self.mediaFirstCountLimit
        }
        let thumbnailCostLimit = Self.thumbnailMemoryCostLimit
        if thumbnailCache.countLimit != Self.thumbnailCountLimit {
            thumbnailCache.countLimit = Self.thumbnailCountLimit
        }
        if thumbnailCache.totalCostLimit != thumbnailCostLimit {
            thumbnailCache.totalCostLimit = thumbnailCostLimit
        }
        let totalCostLimit = Self.mediaFirstMemoryCostLimit - thumbnailCostLimit
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
        var retiredCaches = [cache]
        cache = replacementCache(for: cache)
#if os(iOS)
        retiredCaches.append(thumbnailCache)
        thumbnailCache = replacementCache(for: thumbnailCache)
#endif
        evictionRecorder = DownloadableMediaMemoryEvictionRecorder()
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
            caches: retiredCaches,
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
        evictionRecorder.recordEviction(forKey: key)
    }

    func setAcceptsInsertionsForTesting(_ acceptsInsertions: Bool) {
        acceptsInsertionsForTesting = acceptsInsertions
    }

    func waitForRetirementForTesting() async -> Bool? {
        await retirementTask?.value
    }

    func thumbnailImageForTesting(forKey key: String) -> DownloadableMediaImage? {
        autoreleasepool {
            thumbnailCache.object(forKey: key as NSString)?.image
        }
    }

    func mediaImageForTesting(forKey key: String) -> DownloadableMediaImage? {
        autoreleasepool {
            cache.object(forKey: key as NSString)?.image
        }
    }

    func removeImageForTesting(forKey key: String) {
        thumbnailCache.removeObject(forKey: key as NSString)
        cache.removeObject(forKey: key as NSString)
    }

    var limitsForTesting: (
        thumbnailCount: Int,
        thumbnailCost: Int,
        mediaCount: Int,
        mediaCost: Int,
        combinedCost: Int
    ) {
        (
            thumbnailCache.countLimit,
            thumbnailCache.totalCostLimit,
            cache.countLimit,
            cache.totalCostLimit,
            Self.mediaFirstMemoryCostLimit
        )
    }
#endif

    private func replacementCache(
        for retiredCache: NSCache<NSString, DownloadableMediaMemoryEntry>
    ) -> NSCache<NSString, DownloadableMediaMemoryEntry> {
        let replacement = NSCache<NSString, DownloadableMediaMemoryEntry>()
        replacement.countLimit = retiredCache.countLimit
        replacement.totalCostLimit = retiredCache.totalCostLimit
        return replacement
    }

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
    private static var thumbnailMemoryCostLimit: Int {
        Int(min(
            max(
                ProcessInfo.processInfo.physicalMemory / 16,
                minimumThumbnailMemoryCostLimit
            ),
            maximumThumbnailMemoryCostLimit
        ))
    }

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
