// ∅ 2026 lil org

import Foundation
import ImageIO

#if os(iOS)
import UIKit
typealias WidgetPlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias WidgetPlatformImage = NSImage
#endif

enum CollectionOfTheDayWidgetData {
    private static let retryInterval: TimeInterval = 30 * 60
    private static let imageScale: CGFloat = 3
    private static let minimumImagePixelSize = 512
    private static let maximumImagePixelSize = 1_600
    private static let pngImageType = "public.png" as CFString
    private static let cacheLock = NSLock()
    private static let eligibleCollectionIds = [
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27023",
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270159",
        "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27022",
        "0x46ac8540d698167fcbb9e846511beb8cf8af9bd8f09dc93e48530b0803410a2b32c56cbf",
        "0x46ac8540d698167fcbb9e846511beb8cf8af9bd82b0b7d3bb471c1e4580baed3a35067cf",
        "0x72f28b86749cba12bbac8783a67bbc48d80c92e922c88225c2e244fcfb994a12b654d85b",
        "0x17abd4cc1382397ec2b675f98621c3ba809897de",
        "0x32d6ba9aa1b06fbcaeb3f6c5ff05cd6a77dcf387",
        "0x0c640779dbd6cda40d54350344dfd37d99aed8aa",
        "0x1ee3bcc37b747c29a0583352b3d9541f393cea82",
        "0x1d2550d198197df1a10af515cf2ea0d790889b93eeb4d062d7c79f1145c10a7d200781b1",
        "0x92e64d1a27f4f42ecaf0ef7f725f119751113a38a5e40fa144e354b53d60abaaef1732e2",
        "3dWnCTx5gY3F9hVhiMu7b5we6WSKnyzL9CYdE1rW1HUm",
        "4rWMqk4PXKrWdmA9QSJB27CYwThYmDvZ9rwcZsQfnJ6K",
        "5AVocDEamuwaZf3bXP6tcg52w7cgBvMNJAYvG9rmouCh",
        "JDmZF2EsfWHcq9evTLDfqqUhAHh3zTYMy2rTeEfhx9hy",
        "Bkp4sEpGBgHkjtXpBdZiCxiMhAnx2aY6m3a5E8RdgY6S",
        "r1pCPYkbbpZWv7RCvuCMtpA3NSQY3fzVFo6HL43A4ot",
        "21nXQ4m9zfTsqAHADNjFHRJBxnoynMsL9HRSpdwqKHQH",
        "GVQ4Zsd7jLZbVCxq9QsmQySuKekwT1XbMSjGbwt8UtcB",
        "BBkMWyu4RRrNSdjGDV27FGgZZ58o7jfvQY1MrD2iTfs6",
        "HCWQe6eVmzawiQTf58kM795eGTvvqNZSUrbvnEYokd4B",
        "8bP9cNrTrwuMnmUsSHZ9ReTiJhKVmyjXUfUUrjkqEmef",
        "CjL5WpAmf4cMEEGwZGTfTDKWok9a92ykq9aLZrEK2D5H",
        "2W68ofaUBEQYoFUwEWWHoYq8MBauPbxhZtv71vqZsyhp",
        "9xAjzT43stvxq8fNLtWxYu3sBYWdbZP22fQqzQdNYMzY",
        "AU9F91RsrqQEeN8sshErtQnT8CgYxrg9YD9n4AHHvus7",
        "CHuQxKgso7sGagfakRPeii6xQGByJtnMm3V3ho7ZTJBn",
        "0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d",
        "0xd497a414bb00803e846b53d07fcb742831b24906",
        "0x6873e99fb85de770cc89fa37bc9c859fc2ebaf60",
        "0xEC0a7A26456B8451aefc4b00393ce1BefF5eB3e9",
        "0xc62e3fd5b02618f90dd07d1e478963038fa9089c",
        "0x44096d6de5d17020ce0c41d75ce27b33c6d28e1a",
    ]
    private static let eligibleCollections: [WidgetCollection] = {
        let collectionsById = catalogCollectionsById()
        return eligibleCollectionIds.compactMap { collectionsById[$0] }
    }()
    private static var cachedStaticImageURLsByCollectionId = [String: [URL]]()

    static func collection(for date: Date = Date(), calendar: Calendar? = nil) -> WidgetCollection? {
        guard !eligibleCollections.isEmpty else { return nil }

        let calendar = calendar ?? localGregorianCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        let index = Int(stableHash(dayKey) % UInt64(eligibleCollections.count))
        return eligibleCollections[index]
    }

    static func nextRotationDate(after date: Date, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? localGregorianCalendar
        let startOfDay = calendar.startOfDay(for: date)
        for hour in [8, 16] {
            if let candidate = calendar.date(byAdding: .hour, value: hour, to: startOfDay),
               candidate > date {
                return candidate
            }
        }
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? date.addingTimeInterval(8 * 60 * 60)
    }

    static func retryDate(after date: Date) -> Date {
        date.addingTimeInterval(retryInterval)
    }

    static func randomStaticImageURL(collection: WidgetCollection) -> URL? {
        staticImageURLs(collection: collection).randomElement()
    }

    static func cachedImage(collectionId: String) -> WidgetPlatformImage? {
        guard let data = try? Data(contentsOf: cacheURL(collectionId: collectionId)) else { return nil }
        return platformImage(data: data)
    }

    static func maxImagePixelSize(displaySize: CGSize) -> Int {
        let longestSide = max(displaySize.width, displaySize.height)
        guard longestSide.isFinite, longestSide > 0 else {
            return maximumImagePixelSize
        }

        let scaledLongestSide = Int((longestSide * imageScale).rounded(.up))
        return min(max(scaledLongestSide, minimumImagePixelSize), maximumImagePixelSize)
    }

    static func preparedWidgetImageData(_ data: Data, maxPixelSize: Int) -> Data? {
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

    static func cacheImageData(_ data: Data, collectionId: String) {
        let fileURL = cacheURL(collectionId: collectionId)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    static func platformImage(data: Data) -> WidgetPlatformImage? {
#if os(iOS)
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
#elseif os(macOS)
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
#endif
    }

    private static func catalogCollectionsById() -> [String: WidgetCollection] {
        guard let url = suggestedBundle.url(forResource: "items", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([WidgetCollection].self, from: data) else {
            return [:]
        }

        return items.reduce(into: [String: WidgetCollection]()) { result, item in
            result[item.id] = result[item.id] ?? item
        }
    }

    private static func tokenPayload(collectionId: String) -> WidgetTokenPayload? {
        let url = suggestedBundle.url(forResource: collectionId, withExtension: "json", subdirectory: "Tokens")
            ?? suggestedBundle.url(forResource: collectionId.lowercased(), withExtension: "json", subdirectory: "Tokens")
        guard let url,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(WidgetTokenPayload.self, from: data) else {
            return nil
        }
        return payload
    }

    private static func staticImageURLs(collection: WidgetCollection) -> [URL] {
        if let cachedImageURLs = cacheLock.withLock({ cachedStaticImageURLsByCollectionId[collection.id] }) {
            return cachedImageURLs
        }

        let imageURLs: [URL]
        if let payload = tokenPayload(collectionId: collection.id) {
            imageURLs = payload.items.compactMap { item in
                item.staticImageURL(collection: collection, defaultFileExtension: payload.defaultFileExtension)
            }
        } else {
            imageURLs = []
        }

        return cacheLock.withLock {
            if let cachedImageURLs = cachedStaticImageURLsByCollectionId[collection.id] {
                return cachedImageURLs
            }
            cachedStaticImageURLsByCollectionId[collection.id] = imageURLs
            return imageURLs
        }
    }

    private static func cacheURL(collectionId: String) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CollectionOfTheDayWidgetImages", isDirectory: true)
        return directory.appendingPathComponent(cacheFileName(collectionId: collectionId))
    }

    private static var suggestedBundle: Bundle {
        if let bundleURL = Bundle.main.url(forResource: "Suggested", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL) {
            return bundle
        }
        return Bundle.main
    }

    private static var localGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func encodedImageData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, pngImageType, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
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

struct WidgetCollection: Decodable, Hashable {
    let address: String
    let collectionId: String?
    let abId: String?
    private let chain: WidgetCollectionChain

    var id: String {
        address + (abId ?? collectionId ?? "")
    }

    var coverAssetName: String {
        id
    }

    var usesEthereumMediaProxyFallback: Bool {
        chain == .ethereum
    }
}

private enum WidgetCollectionChain: Decodable, Hashable {
    case ethereum
    case other

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == "ethereum" ? .ethereum : .other
    }
}

private enum WidgetMediaFileExtension {
    private static let staticImageExtensions = Set(["png", "jpg", "jpeg", "webp", "heic", "heif"])

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t\r")).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func explicitPathExtension(in urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return normalized(url.pathExtension)
    }

    static func isStaticImage(_ fileExtension: String) -> Bool {
        staticImageExtensions.contains(fileExtension)
    }
}

private struct WidgetTokenPayload: Decodable {
    let defaultFileExtension: String?
    let items: [WidgetTokenItem]

    enum CodingKeys: String, CodingKey {
        case defaultFileExtension
        case items
        case urlPrefixes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultFileExtension = WidgetMediaFileExtension.normalized(
            try container.decodeIfPresent(String.self, forKey: .defaultFileExtension)
        )
        let urlPrefixes = try container.decodeIfPresent([String].self, forKey: .urlPrefixes) ?? []

        if let compactRows = try? container.decode([WidgetCompactTokenRow].self, forKey: .items) {
            items = compactRows.map { row in
                WidgetTokenItem(
                    id: row.id,
                    url: row.url(prefixes: urlPrefixes),
                    sh: nil,
                    fileExtension: row.fileExtension
                )
            }
        } else {
            items = try container.decode([WidgetTokenItem].self, forKey: .items).map { item in
                WidgetTokenItem(
                    id: item.id,
                    url: item.url,
                    sh: item.sh,
                    fileExtension: WidgetMediaFileExtension.normalized(item.fileExtension)
                )
            }
        }
    }
}

private struct WidgetTokenItem: Decodable, Hashable {
    let id: String
    let url: String?
    let sh: String?
    let fileExtension: String?

    func staticImageURL(collection: WidgetCollection, defaultFileExtension: String?) -> URL? {
        guard let urlString = resolvedURLString(collection: collection),
              let url = URL(string: urlString),
              let fileExtension = resolvedFileExtension(urlString: urlString, defaultFileExtension: defaultFileExtension),
              WidgetMediaFileExtension.isStaticImage(fileExtension) else {
            return nil
        }
        return url
    }

    private func resolvedURLString(collection: WidgetCollection) -> String? {
        if let url {
            return url
        }
        if let sh {
            return "https://cdn.simplehash.com/assets/\(sh)"
        }
        if collection.usesEthereumMediaProxyFallback {
            return "https://media-proxy.artblocks.io/\(collection.address)/\(id).png"
        }
        return nil
    }

    private func resolvedFileExtension(urlString: String, defaultFileExtension: String?) -> String? {
        WidgetMediaFileExtension.explicitPathExtension(in: urlString)
            ?? WidgetMediaFileExtension.normalized(fileExtension)
            ?? defaultFileExtension
    }
}

private struct WidgetCompactTokenRow: Decodable {
    let id: String
    let prefixIndex: Int
    let urlSuffix: String
    let fileExtension: String?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        prefixIndex = try container.decode(Int.self)
        urlSuffix = try container.decode(String.self)
        fileExtension = WidgetMediaFileExtension.normalized(try? container.decode(String.self))
    }

    func url(prefixes: [String]) -> String {
        guard prefixes.indices.contains(prefixIndex) else { return urlSuffix }
        return prefixes[prefixIndex] + urlSuffix
    }
}
