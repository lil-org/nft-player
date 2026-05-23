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
    static let tojibaCPUCorpCollectionId = "AU9F91RsrqQEeN8sshErtQnT8CgYxrg9YD9n4AHHvus7"

    private static let retryInterval: TimeInterval = 30 * 60
    private static let imageScale: CGFloat = 3
    private static let minimumImagePixelSize = 512
    private static let maximumImagePixelSize = 1_600
    private static let pngImageType = "public.png" as CFString
    private static let cacheLock = NSLock()
    private static let eligibleCollections = catalogCollections()
    private static let collectionsById = eligibleCollections.reduce(into: [String: WidgetCollection]()) { result, item in
        result[item.id] = result[item.id] ?? item
    }
    private static var cachedStaticImageReferencesByCollectionId = [String: [WidgetStaticImageReference]]()

    static func collection(for date: Date = Date(), calendar: Calendar? = nil) -> WidgetCollection? {
        guard !eligibleCollections.isEmpty else { return nil }

        let calendar = calendar ?? localGregorianCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        let index = Int(stableHash(dayKey) % UInt64(eligibleCollections.count))
        return eligibleCollections[index]
    }

    static func collection(id: String) -> WidgetCollection? {
        collectionsById[id]
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

    static func randomStaticImageReference(collection: WidgetCollection) -> WidgetStaticImageReference? {
        staticImageReferences(collection: collection).randomElement()
    }

    static func cachedImage(collectionId: String) -> WidgetPlatformImage? {
        guard let data = try? Data(contentsOf: cacheURL(collectionId: collectionId)) else { return nil }
        return platformImage(data: data)
    }

    static func cachedTokenId(collectionId: String) -> String? {
        guard let tokenId = try? String(contentsOf: cacheTokenIdURL(collectionId: collectionId), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !tokenId.isEmpty else {
            return nil
        }
        return tokenId
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

    static func cacheImageData(_ data: Data, collectionId: String, tokenId: String?) {
        let fileURL = cacheURL(collectionId: collectionId)
        let tokenIdURL = cacheTokenIdURL(collectionId: collectionId)

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        // Clear first so a failed partial cache refresh cannot pair a new image with an old token id.
        guard clearCachedTokenId(at: tokenIdURL) else { return }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        if let tokenId, !tokenId.isEmpty {
            do {
                try tokenId.write(to: tokenIdURL, atomically: true, encoding: .utf8)
            } catch {
                _ = clearCachedTokenId(at: tokenIdURL)
            }
        }
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

    private static func catalogCollections() -> [WidgetCollection] {
        guard let url = suggestedBundle.url(forResource: "items", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([WidgetCollection].self, from: data) else {
            return []
        }

        return items
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

    private static func staticImageReferences(collection: WidgetCollection) -> [WidgetStaticImageReference] {
        if let cachedImageReferences = cacheLock.withLock({ cachedStaticImageReferencesByCollectionId[collection.id] }) {
            return cachedImageReferences
        }

        let imageReferences: [WidgetStaticImageReference]
        if let payload = tokenPayload(collectionId: collection.id) {
            imageReferences = payload.items.compactMap { item in
                item.staticImageReference(collection: collection, defaultFileExtension: payload.defaultFileExtension)
            }
        } else {
            imageReferences = []
        }

        return cacheLock.withLock {
            if let cachedImageReferences = cachedStaticImageReferencesByCollectionId[collection.id] {
                return cachedImageReferences
            }
            cachedStaticImageReferencesByCollectionId[collection.id] = imageReferences
            return imageReferences
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

    private static func clearCachedTokenId(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            let nsError = error as NSError
            return nsError.domain == NSCocoaErrorDomain
                && nsError.code == CocoaError.fileNoSuchFile.rawValue
        }
    }

    private static var suggestedBundle: Bundle {
        if let bundleURL = Bundle.main.url(forResource: "WidgetSuggested", withExtension: "bundle"),
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

struct WidgetStaticImageReference: Hashable {
    let tokenId: String
    let url: URL
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

    func staticImageReference(collection: WidgetCollection, defaultFileExtension: String?) -> WidgetStaticImageReference? {
        guard let urlString = resolvedURLString(collection: collection),
              let url = URL(string: urlString),
              let fileExtension = resolvedFileExtension(urlString: urlString, defaultFileExtension: defaultFileExtension),
              WidgetMediaFileExtension.isStaticImage(fileExtension) else {
            return nil
        }
        return WidgetStaticImageReference(tokenId: id, url: url)
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
