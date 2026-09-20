// ∅ 2026 lil org

import Foundation
import ImageIO
import os

#if canImport(UIKit)
import UIKit
typealias WidgetPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias WidgetPlatformImage = NSImage
#endif

nonisolated enum CollectionOfTheDayWidgetData {
    struct CachedImage: Sendable {
        let data: Data
        let tokenId: String?
    }

    private struct CachedImageRecord: Codable, Sendable {
        let version: Int
        let data: Data
        let tokenId: String?
    }

    static let tojibaCPUCorpCollectionId = "AU9F91RsrqQEeN8sshErtQnT8CgYxrg9YD9n4AHHvus7"
    static let defaultSelectedCollectionId = "0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d"

    private static let retryInterval: TimeInterval = 30 * 60
    private static let imageScale: CGFloat = 3
    private static let minimumImagePixelSize = 512
    private static let maximumImagePixelSize = 1_600
    private static let cachedImageRecordVersion = 1
    private static let eligibleCollections = catalogCollections()
    private static let collectionsById = eligibleCollections.reduce(into: [String: WidgetCollection]()) { result, item in
        result[item.id] = result[item.id] ?? item
    }
    private static let staticImageReferenceCache = OSAllocatedUnfairLock(
        initialState: [String: [WidgetStaticImageReference]]()
    )
    private static let imageCacheLock = OSAllocatedUnfairLock(initialState: ())

    static func collection(for date: Date = Date(), calendar: Calendar? = nil) -> WidgetCollection? {
        stableCollection(for: date, calendar: calendar, salt: nil)
    }

    static func defaultSelectedCollection() -> WidgetCollection? {
        collection(id: defaultSelectedCollectionId)
    }

    private static func stableCollection(for date: Date, calendar: Calendar?, salt: String?) -> WidgetCollection? {
        guard !eligibleCollections.isEmpty else { return nil }

        let calendar = calendar ?? localGregorianCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        let dayKey = salt.map { "\($0)-\(dateKey)" } ?? dateKey
        let index = Int(stableHash(dayKey) % UInt64(eligibleCollections.count))
        return eligibleCollections[index]
    }

    static func collection(id: String) -> WidgetCollection? {
        collectionsById[id]
    }

    static func configurationCollections() -> [WidgetCollection] {
        eligibleCollections.sorted {
            let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameComparison == .orderedSame {
                return $0.id < $1.id
            }
            return nameComparison == .orderedAscending
        }
    }

    static func nextRotationDate(after date: Date, calendar: Calendar? = nil) -> Date {
        nextRotationDate(
            after: date,
            hours: [8, 16],
            wrapToFirstHourOnNextDay: false,
            fallbackHourInterval: 8,
            calendar: calendar
        )
    }

    static func nextRotationDate(
        after date: Date,
        frequency: WidgetRotationFrequency,
        calendar: Calendar? = nil
    ) -> Date {
        nextRotationDate(
            after: date,
            hours: frequency.rotationHours,
            wrapToFirstHourOnNextDay: true,
            fallbackHourInterval: frequency.fallbackHourInterval,
            calendar: calendar
        )
    }

    private static func nextRotationDate(
        after date: Date,
        hours: [Int],
        wrapToFirstHourOnNextDay: Bool,
        fallbackHourInterval: Int,
        calendar: Calendar?
    ) -> Date {
        let calendar = calendar ?? localGregorianCalendar
        let startOfDay = calendar.startOfDay(for: date)
        for hour in hours {
            if let candidate = calendar.date(byAdding: .hour, value: hour, to: startOfDay),
               candidate > date {
                return candidate
            }
        }
        if wrapToFirstHourOnNextDay,
           let firstHour = hours.first,
           let nextDayStart = calendar.date(byAdding: .day, value: 1, to: startOfDay),
           let candidate = calendar.date(byAdding: .hour, value: firstHour, to: nextDayStart) {
            return candidate
        }
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? date.addingTimeInterval(TimeInterval(fallbackHourInterval * 60 * 60))
    }

    static func retryDate(after date: Date) -> Date {
        date.addingTimeInterval(retryInterval)
    }

    static func randomStaticImageReference(collection: WidgetCollection) async -> WidgetStaticImageReference? {
        await staticImageReferences(collection: collection).randomElement()
    }

    static func cachedImage(collectionId: String) -> CachedImage? {
        let fileURL = cacheURL(collectionId: collectionId)
        let tokenIdURL = cacheTokenIdURL(collectionId: collectionId)
        return imageCacheLock.withLock { () -> CachedImage? in
            guard let storedData = try? Data(contentsOf: fileURL) else {
                return nil
            }

            let cachedImage: CachedImage
            if let record = try? PropertyListDecoder().decode(
                CachedImageRecord.self,
                from: storedData
            ), record.version == cachedImageRecordVersion {
                cachedImage = CachedImage(data: record.data, tokenId: record.tokenId)
            } else {
                cachedImage = CachedImage(
                    data: storedData,
                    tokenId: cachedTokenId(at: tokenIdURL)
                )
            }
            guard isValidImageData(cachedImage.data) else { return nil }
            return cachedImage
        }
    }

    static func maxImagePixelSize(displaySize: CGSize) -> Int {
        let longestSide = max(displaySize.width, displaySize.height)
        guard longestSide.isFinite, longestSide > 0 else {
            return maximumImagePixelSize
        }

        let scaledLongestSide = Int((longestSide * imageScale).rounded(.up))
        return min(max(scaledLongestSide, minimumImagePixelSize), maximumImagePixelSize)
    }

    @concurrent
    static func preparedWidgetImageData(_ data: Data, maxPixelSize: Int) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return encodedImageData(thumbnail)
    }

    @concurrent
    static func cacheImageData(_ data: Data, collectionId: String, tokenId: String?) async {
        let fileURL = cacheURL(collectionId: collectionId)
        let tokenIdURL = cacheTokenIdURL(collectionId: collectionId)
        let record = CachedImageRecord(
            version: cachedImageRecordVersion,
            data: data,
            tokenId: tokenId?.isEmpty == false ? tokenId : nil
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let recordData = try? encoder.encode(record) else { return }

        imageCacheLock.withLock {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                return
            }

            do {
                try recordData.write(to: fileURL, options: .atomic)
            } catch {
                return
            }
            clearCachedTokenId(at: tokenIdURL)
        }
    }

    @MainActor
    static func platformImage(data: Data) -> WidgetPlatformImage? {
#if canImport(UIKit)
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
#elseif canImport(AppKit)
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
#endif
    }

    private static func catalogCollections() -> [WidgetCollection] {
        guard let url = Bundle.main.url(forResource: "widget-items", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([WidgetCollection].self, from: data) else {
            return []
        }

        return items
    }

    @concurrent
    private static func staticImageReferences(collection: WidgetCollection) async -> [WidgetStaticImageReference] {
        if let cached = staticImageReferenceCache.withLock({ $0[collection.id] }) {
            return cached
        }
        do {
            let data = try await PersistentCollectionTokenCache.shared.data(for: collection.bundledResourceName)
            let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: data)
            let references = payload.items.compactMap { $0.staticImageReference(collection: collection) }
            return staticImageReferenceCache.withLock { cache in
                if let cached = cache[collection.id] { return cached }
                cache[collection.id] = references
                return references
            }
        } catch {
            return []
        }
    }

    private static func cacheURL(collectionId: String) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CollectionOfTheDayWidgetImages", isDirectory: true)
        return directory.appendingPathComponent(cacheFileName(collectionId: collectionId))
    }

    private static func cacheTokenIdURL(collectionId: String) -> URL {
        cacheURL(collectionId: collectionId).appendingPathExtension("token-id")
    }

    private static func clearCachedTokenId(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func cachedTokenId(at url: URL) -> String? {
        guard let tokenId = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !tokenId.isEmpty else {
            return nil
        }
        return tokenId
    }

    private static var localGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func encodedImageData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func isValidImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            return false
        }
        return image.width > 0 && image.height > 0
    }

    private static func cacheFileName(collectionId: String) -> String {
        collectionId.map { character in
            character.isLetter || character.isNumber ? String(character) : "_"
        }.joined()
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

nonisolated struct WidgetCollection: Decodable, Hashable, Sendable {
    let address: String
    let internalSlug: String?
    let collectionId: String?
    let abId: String?
    let name: String
    let hasCover: Bool
    let urlPrefix: String?
    private let chain: WidgetCollectionChain

    enum CodingKeys: String, CodingKey {
        case address
        case internalSlug = "internal_slug"
        case collectionId
        case abId
        case name
        case hasCover
        case urlPrefix
        case chain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        internalSlug = try container.decodeIfPresent(String.self, forKey: .internalSlug)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId)
        abId = try container.decodeIfPresent(String.self, forKey: .abId)
        hasCover = try container.decodeIfPresent(Bool.self, forKey: .hasCover) ?? true
        urlPrefix = try container.decodeIfPresent(String.self, forKey: .urlPrefix)
        chain = try container.decode(WidgetCollectionChain.self, forKey: .chain)

        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = address + (abId ?? collectionId ?? "")
        if let decodedName, !decodedName.isEmpty {
            name = decodedName
        } else {
            name = fallbackName
        }
    }

    var id: String {
        address + (abId ?? collectionId ?? "")
    }

    var bundledResourceName: String {
        guard let internalSlug, !internalSlug.isEmpty else { return id }
        return internalSlug
    }

    var coverAssetName: String {
        bundledResourceName
    }

    var usesEthereumMediaProxyFallback: Bool {
        chain == .ethereum
    }
}

nonisolated struct WidgetStaticImageReference: Hashable, Sendable {
    let tokenId: String
    let url: URL
}

nonisolated private enum WidgetCollectionChain: Decodable, Hashable, Sendable {
    case ethereum
    case other

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == "ethereum" ? .ethereum : .other
    }
}

nonisolated private struct WidgetTokenPayload: Decodable, Sendable {
    let items: [WidgetTokenItem]

    init(from decoder: Decoder) throws {
        let manifest = try CompactTokenManifest(from: decoder)
        items = (0..<manifest.count).map { index in
            let id = manifest.id(at: index)
            return WidgetTokenItem(id: id, urlSuffix: manifest.urlSuffix(at: index, id: id))
        }
    }
}

nonisolated private struct WidgetTokenItem: Decodable, Hashable, Sendable {
    let id: String
    let urlSuffix: String?

    func staticImageReference(collection: WidgetCollection) -> WidgetStaticImageReference? {
        guard let urlString = resolvedURLString(collection: collection),
              let resolved = BundledMediaResolver.resolve(urlString),
              case .staticImage? = resolved.kind else {
            return nil
        }
        return WidgetStaticImageReference(tokenId: id, url: resolved.url)
    }

    private func resolvedURLString(collection: WidgetCollection) -> String? {
        if let urlSuffix {
            return (collection.urlPrefix ?? "") + urlSuffix
        }
        if collection.usesEthereumMediaProxyFallback {
            return "https://media-proxy.artblocks.io/\(collection.address)/\(id).png"
        }
        return nil
    }
}
