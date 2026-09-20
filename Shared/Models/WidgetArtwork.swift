import Foundation

nonisolated struct WidgetCollection: Decodable, Hashable, Sendable {
    let address: String
    let internalSlug: String?
    let collectionId: String?
    let abId: String?
    let name: String
    let urlPrefix: String?
    let hasMid: Bool
    let standardThumbsPathsAvailable: Bool
    let standardThumbsBaseURL: String?
    private let script: WidgetCollectionScript?
    private let iosOnly: Bool?
    private let generativeOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case address
        case internalSlug = "internal_slug"
        case collectionId
        case abId
        case name
        case urlPrefix
        case hasMid
        case standardThumbsPathsAvailable
        case standardThumbsBaseURL
        case script
        case iosOnly
        case generativeOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        internalSlug = try container.decodeIfPresent(String.self, forKey: .internalSlug)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId)
        abId = try container.decodeIfPresent(String.self, forKey: .abId)
        urlPrefix = try container.decodeIfPresent(String.self, forKey: .urlPrefix)
        hasMid = try container.decodeIfPresent(Bool.self, forKey: .hasMid) ?? true
        standardThumbsPathsAvailable = try container.decodeIfPresent(
            Bool.self,
            forKey: .standardThumbsPathsAvailable
        ) ?? false
        standardThumbsBaseURL = try container.decodeIfPresent(String.self, forKey: .standardThumbsBaseURL)
        script = try container.decodeIfPresent(WidgetCollectionScript.self, forKey: .script)
        iosOnly = try container.decodeIfPresent(Bool.self, forKey: .iosOnly)
        generativeOnly = try container.decodeIfPresent(Bool.self, forKey: .generativeOnly)

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

    func isAvailable(on platform: CollectionPlatformAvailability.Platform = .current) -> Bool {
        CollectionPlatformAvailability.isAvailable(iosOnly: iosOnly, generativeOnly: generativeOnly, on: platform)
            && CollectionPlatformAvailability.isRendererAvailable(
                collectionId: id,
                isNative: script?.kind.hasPrefix("native.") == true,
                on: platform
            )
    }

    fileprivate var hasWebGenerativeScript: Bool {
        guard let kind = script?.kind else { return false }
        return !kind.isEmpty && !kind.hasPrefix("native.")
    }
}

nonisolated struct WidgetStaticImageReference: Hashable, Sendable {
    let tokenId: String
    let url: URL
}

nonisolated private struct WidgetCollectionScript: Decodable, Hashable, Sendable {
    let kind: String
}

nonisolated struct WidgetTokenPayload: Decodable {
    private let manifest: CompactTokenManifest

    init(from decoder: Decoder) throws {
        manifest = try CompactTokenManifest(from: decoder)
    }

    var count: Int { manifest.count }

    func item(at index: Int) -> WidgetTokenItem {
        let id = manifest.id(at: index)
        return WidgetTokenItem(
            id: id,
            urlSuffix: manifest.urlSuffix(at: index, id: id),
            sourceIndex: index
        )
    }

    func randomStaticImageReference(collection: WidgetCollection) -> WidgetStaticImageReference? {
        var generator = SystemRandomNumberGenerator()
        return randomStaticImageReference(collection: collection, using: &generator)
    }

    func randomStaticImageReference<G: RandomNumberGenerator>(
        collection: WidgetCollection,
        using generator: inout G
    ) -> WidgetStaticImageReference? {
        var remainingCount = count
        var swaps = [Int: Int]()
        while remainingCount > 0 {
            let position = Int.random(in: 0..<remainingCount, using: &generator)
            let index = swaps[position] ?? position
            if let reference = item(at: index).staticImageReference(collection: collection) {
                return reference
            }
            remainingCount -= 1
            swaps[position] = swaps[remainingCount] ?? remainingCount
            swaps[remainingCount] = nil
        }
        return nil
    }
}

nonisolated struct WidgetTokenItem: Decodable, Hashable, Sendable {
    let id: String
    let urlSuffix: String?
    let sourceIndex: Int?

    init(id: String, urlSuffix: String?, sourceIndex: Int? = nil) {
        self.id = id
        self.urlSuffix = urlSuffix
        self.sourceIndex = sourceIndex
    }

    func staticImageReference(collection: WidgetCollection) -> WidgetStaticImageReference? {
        if urlSuffix == nil, collection.hasMid, collection.hasWebGenerativeScript {
            guard let url = CollectionBrowseImageURLMapping.generativeMidURL(
                slug: collection.internalSlug,
                sourceIndex: sourceIndex
            ) else {
                return nil
            }
            return WidgetStaticImageReference(tokenId: id, url: url)
        }

        guard let urlString = resolvedURLString(collection: collection),
              let resolved = BundledMediaResolver.resolve(urlString),
              let components = URLComponents(url: resolved.url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            return nil
        }

        let url: URL
        if collection.hasMid {
            guard let midURL = CollectionBrowseImageURLMapping.downloadableMidURL(
                    for: resolved.url,
                    standardThumbsPathsAvailable: collection.standardThumbsPathsAvailable,
                    standardThumbsBaseURL: collection.standardThumbsBaseURL
                  ) else {
                return nil
            }
            url = midURL
        } else {
            guard case .staticImage? = resolved.kind else { return nil }
            url = resolved.url
        }
        guard ArtworkAssetPolicy.allowsRemoteURL(url) else { return nil }
        return WidgetStaticImageReference(tokenId: id, url: url)
    }

    private func resolvedURLString(collection: WidgetCollection) -> String? {
        if let urlSuffix {
            return (collection.urlPrefix ?? "") + urlSuffix
        }
        return nil
    }
}

nonisolated struct WidgetCachedImage: Sendable {
    let data: Data
    let tokenId: String?
}

nonisolated enum WidgetImageCacheCodec {
    private struct Record: Codable {
        let version: Int
        let data: Data
        let tokenId: String?
    }

    private static let version = 2

    static func decode(_ data: Data) -> WidgetCachedImage? {
        guard let record = try? PropertyListDecoder().decode(Record.self, from: data),
              record.version == version else {
            return nil
        }
        return WidgetCachedImage(data: record.data, tokenId: record.tokenId)
    }

    static func encode(_ image: WidgetCachedImage) -> Data? {
        let record = Record(
            version: version,
            data: image.data,
            tokenId: image.tokenId?.isEmpty == false ? image.tokenId : nil
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(record)
    }
}
