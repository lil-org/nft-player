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
    private let chain: WidgetCollectionChain

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
        case chain
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

nonisolated struct WidgetTokenPayload: Decodable, Sendable {
    let items: [WidgetTokenItem]

    init(from decoder: Decoder) throws {
        let manifest = try CompactTokenManifest(from: decoder)
        items = (0..<manifest.count).map { index in
            let id = manifest.id(at: index)
            return WidgetTokenItem(id: id, urlSuffix: manifest.urlSuffix(at: index, id: id))
        }
    }
}

nonisolated struct WidgetTokenItem: Decodable, Hashable, Sendable {
    let id: String
    let urlSuffix: String?

    func staticImageReference(collection: WidgetCollection) -> WidgetStaticImageReference? {
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
            guard collection.standardThumbsPathsAvailable,
                  let thumbnailURL = CollectionBrowseImageURLMapping.standardThumbnailURL(
                    for: resolved.url,
                    standardThumbsBaseURL: collection.standardThumbsBaseURL
                  ),
                  let midURL = CollectionBrowseImageURLMapping.midURL(for: thumbnailURL) else {
                return nil
            }
            url = midURL
        } else {
            guard case .staticImage? = resolved.kind else { return nil }
            url = resolved.url
        }
        return WidgetStaticImageReference(tokenId: id, url: url)
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
