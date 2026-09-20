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
    static let tojibaCPUCorpCollectionId = "AU9F91RsrqQEeN8sshErtQnT8CgYxrg9YD9n4AHHvus7"
    static let defaultSelectedCollectionId = "0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d"

    private static let retryInterval: TimeInterval = 30 * 60
    private static let imageScale: CGFloat = 3
    private static let minimumImagePixelSize = 512
    private static let maximumImagePixelSize = 1_600
    private static let eligibleCollections = catalogCollections()
    private static let collectionsById = eligibleCollections.reduce(into: [String: WidgetCollection]()) { result, item in
        result[item.id] = result[item.id] ?? item
    }
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

    static func cachedImage(collectionId: String) -> WidgetCachedImage? {
        let fileURL = cacheURL(collectionId: collectionId)
        return imageCacheLock.withLock { () -> WidgetCachedImage? in
            guard let storedData = try? Data(contentsOf: fileURL),
                  let cachedImage = WidgetImageCacheCodec.decode(storedData),
                  isValidImageData(cachedImage.data) else {
                return nil
            }
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
        let image = WidgetCachedImage(
            data: data,
            tokenId: tokenId
        )
        guard let recordData = WidgetImageCacheCodec.encode(image) else { return }

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

        return items.filter { $0.isAvailable() }
    }

    @concurrent
    static func randomStaticImageReference(collection: WidgetCollection) async -> WidgetStaticImageReference? {
        do {
            let data = try await PersistentCollectionTokenCache.shared.data(for: collection.bundledResourceName)
            let payload = try JSONDecoder().decode(WidgetTokenPayload.self, from: data)
            return payload.randomStaticImageReference(collection: collection)
        } catch {
            return nil
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
