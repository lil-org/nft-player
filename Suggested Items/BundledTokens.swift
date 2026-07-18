// ∅ 2026 lil org

import CoreGraphics
import Foundation

struct ThumbnailAspectRatio: Codable, Hashable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "Thumbnail aspect-ratio dimensions must be positive")
        let divisor = Self.greatestCommonDivisor(width, height)
        self.width = width / divisor
        self.height = height / divisor
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let width = try container.decode(Int.self)
        let height = try container.decode(Int.self)
        guard width > 0, height > 0, container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Thumbnail aspect ratio must be a [positiveWidth, positiveHeight] pair"
            )
        }
        self.init(width: width, height: height)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    var value: CGFloat {
        CGFloat(width) / CGFloat(height)
    }

    private static func greatestCommonDivisor(_ left: Int, _ right: Int) -> Int {
        var a = left
        var b = right
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }
}

struct ThumbnailAspectRatioOverride: Codable {
    let tokenIndex: Int
    let ratioIndex: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        tokenIndex = try container.decode(Int.self)
        ratioIndex = try container.decode(Int.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Thumbnail aspect-ratio override must be a [tokenIndex, ratioIndex] pair"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(tokenIndex)
        try container.encode(ratioIndex)
    }
}

enum ThumbnailAspectRatioProfile: Hashable {
    case uniform(ThumbnailAspectRatio)
    case variable([ThumbnailAspectRatio])

    func isCompatible(withItemCount itemCount: Int) -> Bool {
        guard itemCount > 0 else { return false }
        switch self {
        case .uniform:
            return true
        case let .variable(aspectRatios):
            return aspectRatios.count == itemCount
        }
    }
}

struct ThumbnailAspectRatioProfileBuilder {
    private var itemCount = 0
    private var firstAspectRatio: ThumbnailAspectRatio?
    private var variableAspectRatios: [ThumbnailAspectRatio]?
    private var hasMissingAspectRatio = false

    mutating func append(_ aspectRatio: ThumbnailAspectRatio?) {
        defer { itemCount += 1 }
        guard !hasMissingAspectRatio,
              let aspectRatio else {
            hasMissingAspectRatio = true
            variableAspectRatios = nil
            return
        }

        guard let firstAspectRatio else {
            self.firstAspectRatio = aspectRatio
            return
        }
        if variableAspectRatios != nil {
            variableAspectRatios?.append(aspectRatio)
        } else if aspectRatio != firstAspectRatio {
            variableAspectRatios = Array(repeating: firstAspectRatio, count: itemCount)
            variableAspectRatios?.append(aspectRatio)
        }
    }

    var profile: ThumbnailAspectRatioProfile? {
        guard itemCount > 0,
              !hasMissingAspectRatio,
              let firstAspectRatio else {
            return nil
        }
        if let variableAspectRatios {
            return .variable(variableAspectRatios)
        }
        return .uniform(firstAspectRatio)
    }
}

enum ThumbnailAspectRatioMetadata {
    static func resolve(
        aspectRatios: [ThumbnailAspectRatio]?,
        overrides: [ThumbnailAspectRatioOverride]?,
        itemCount: Int,
        codingPath: [CodingKey]
    ) throws -> [ThumbnailAspectRatio]? {
        guard aspectRatios != nil || overrides != nil else { return nil }
        guard let aspectRatios, !aspectRatios.isEmpty else {
            throw corrupted(
                codingPath: codingPath,
                description: "thumbnailAspectRatios must be a non-empty array when aspect-ratio metadata is present"
            )
        }
        guard Set(aspectRatios).count == aspectRatios.count else {
            throw corrupted(
                codingPath: codingPath,
                description: "thumbnailAspectRatios must not contain duplicate ratios"
            )
        }

        var resolved = Array(repeating: aspectRatios[0], count: itemCount)
        var overriddenTokenIndices = Set<Int>()
        for override in overrides ?? [] {
            guard resolved.indices.contains(override.tokenIndex) else {
                throw corrupted(
                    codingPath: codingPath,
                    description: "Thumbnail aspect-ratio override has an invalid token index: \(override.tokenIndex)"
                )
            }
            guard override.ratioIndex > 0,
                  aspectRatios.indices.contains(override.ratioIndex) else {
                throw corrupted(
                    codingPath: codingPath,
                    description: "Thumbnail aspect-ratio override has an invalid ratio index: \(override.ratioIndex)"
                )
            }
            guard overriddenTokenIndices.insert(override.tokenIndex).inserted else {
                throw corrupted(
                    codingPath: codingPath,
                    description: "Thumbnail aspect-ratio overrides repeat token index: \(override.tokenIndex)"
                )
            }
            resolved[override.tokenIndex] = aspectRatios[override.ratioIndex]
        }
        return resolved
    }

    private static func corrupted(codingPath: [CodingKey], description: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: description))
    }
}

struct BundledTokens: Codable {
    
    struct Item: Codable {
        let id: String
        let name: String?
        let url: String?
        let sh: String?
        let hash: String?
        let thumbnailAspectRatio: ThumbnailAspectRatio?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case url
            case sh
            case hash
        }

        init(
            id: String,
            name: String?,
            url: String?,
            sh: String?,
            hash: String?,
            thumbnailAspectRatio: ThumbnailAspectRatio? = nil
        ) {
            self.id = id
            self.name = name
            self.url = url
            self.sh = sh
            self.hash = hash
            self.thumbnailAspectRatio = thumbnailAspectRatio
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            sh = try container.decodeIfPresent(String.self, forKey: .sh)
            hash = try container.decodeIfPresent(String.self, forKey: .hash)
            thumbnailAspectRatio = nil
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(url, forKey: .url)
            try container.encodeIfPresent(sh, forKey: .sh)
            try container.encodeIfPresent(hash, forKey: .hash)
        }
    }

    private struct CompactItem: Decodable {
        let id: String
        let prefixIndex: Int
        let urlSuffix: String

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            id = try container.decode(String.self)
            prefixIndex = try container.decode(Int.self)
            urlSuffix = try container.decode(String.self)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isComplete
        case items
        case thumbnailAspectRatios
        case thumbnailAspectRatioOverrides
        case urlPrefixes
    }
    
    let isComplete: Bool
    let items: [Item]
    private let thumbnailAspectRatios: [ThumbnailAspectRatio]?
    private let thumbnailAspectRatioOverrides: [ThumbnailAspectRatioOverride]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
        thumbnailAspectRatios = try container.decodeIfPresent(
            [ThumbnailAspectRatio].self,
            forKey: .thumbnailAspectRatios
        )
        thumbnailAspectRatioOverrides = try container.decodeIfPresent(
            [ThumbnailAspectRatioOverride].self,
            forKey: .thumbnailAspectRatioOverrides
        )

        let decodedItems: [Item]
        if let objectItems = try? container.decode([Item].self, forKey: .items) {
            decodedItems = objectItems
        } else {
            let urlPrefixes = try container.decodeIfPresent([String].self, forKey: .urlPrefixes) ?? []
            decodedItems = try container.decode([CompactItem].self, forKey: .items).map { compactItem in
                let url: String
                if urlPrefixes.indices.contains(compactItem.prefixIndex) {
                    url = urlPrefixes[compactItem.prefixIndex] + compactItem.urlSuffix
                } else {
                    url = compactItem.urlSuffix
                }
                return Item(id: compactItem.id, name: nil, url: url, sh: nil, hash: nil)
            }
        }

        let resolvedAspectRatios = try ThumbnailAspectRatioMetadata.resolve(
            aspectRatios: thumbnailAspectRatios,
            overrides: thumbnailAspectRatioOverrides,
            itemCount: decodedItems.count,
            codingPath: container.codingPath
        )
        items = decodedItems.enumerated().map { index, item in
            Item(
                id: item.id,
                name: item.name,
                url: item.url,
                sh: item.sh,
                hash: item.hash,
                thumbnailAspectRatio: resolvedAspectRatios?[index]
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(thumbnailAspectRatios, forKey: .thumbnailAspectRatios)
        try container.encodeIfPresent(thumbnailAspectRatioOverrides, forKey: .thumbnailAspectRatioOverrides)
    }
    
}
