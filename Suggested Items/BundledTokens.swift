// ∅ 2026 lil org

import CoreGraphics
import Foundation

nonisolated struct ArtworkReferencePixelSize: Codable, Hashable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "Reference pixel dimensions must be positive")
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let width = try container.decode(Int.self)
        let height = try container.decode(Int.self)
        guard width > 0, height > 0, container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Reference pixel size must be a [positiveWidth, positiveHeight] pair"
            )
        }
        self.init(width: width, height: height)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }

    var size: CGSize { CGSize(width: width, height: height) }
}

nonisolated struct AspectRatio: Codable, Hashable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "Aspect-ratio dimensions must be positive")
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
                debugDescription: "Aspect ratio must be a [positiveWidth, positiveHeight] pair"
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

nonisolated struct AspectRatioOverride: Codable, Sendable {
    let tokenIndex: Int
    let ratioIndex: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        tokenIndex = try container.decode(Int.self)
        ratioIndex = try container.decode(Int.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Aspect-ratio override must be a [tokenIndex, ratioIndex] pair"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(tokenIndex)
        try container.encode(ratioIndex)
    }
}

nonisolated enum AspectRatioProfile: Hashable, Sendable {
    case uniform(AspectRatio)
    case variable([AspectRatio])

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

nonisolated struct AspectRatioProfileBuilder: Sendable {
    private var itemCount = 0
    private var firstAspectRatio: AspectRatio?
    private var variableAspectRatios: [AspectRatio]?
    private var hasMissingAspectRatio = false

    mutating func append(_ aspectRatio: AspectRatio?) {
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

    var profile: AspectRatioProfile? {
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

nonisolated enum AspectRatioMetadata {
    static func resolve(
        aspectRatios: [AspectRatio]?,
        overrides: [AspectRatioOverride]?,
        itemCount: Int,
        codingPath: [CodingKey]
    ) throws -> [AspectRatio]? {
        guard aspectRatios != nil || overrides != nil else { return nil }
        guard let aspectRatios, !aspectRatios.isEmpty else {
            throw corrupted(
                codingPath: codingPath,
                description: "aspectRatios must be a non-empty array when aspect-ratio metadata is present"
            )
        }
        guard Set(aspectRatios).count == aspectRatios.count else {
            throw corrupted(
                codingPath: codingPath,
                description: "aspectRatios must not contain duplicate ratios"
            )
        }

        var resolved = Array(repeating: aspectRatios[0], count: itemCount)
        var overriddenTokenIndices = Set<Int>()
        for override in overrides ?? [] {
            guard resolved.indices.contains(override.tokenIndex) else {
                throw corrupted(
                    codingPath: codingPath,
                    description: "Aspect-ratio override has an invalid token index: \(override.tokenIndex)"
                )
            }
            guard override.ratioIndex > 0,
                  aspectRatios.indices.contains(override.ratioIndex) else {
                throw corrupted(
                    codingPath: codingPath,
                    description: "Aspect-ratio override has an invalid ratio index: \(override.ratioIndex)"
                )
            }
            guard overriddenTokenIndices.insert(override.tokenIndex).inserted else {
                throw corrupted(
                    codingPath: codingPath,
                    description: "Aspect-ratio overrides repeat token index: \(override.tokenIndex)"
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

nonisolated struct BundledTokens: Codable, Sendable {
    
    struct Item: Codable, Sendable {
        let id: String
        let name: String?
        let url: String?
        let sh: String?
        let hash: String?
        let aspectRatio: AspectRatio?
        let imageAspectRatio: AspectRatio?
        let referencePixelSize: ArtworkReferencePixelSize?
        let contractParameters: [String: String]?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case url
            case sh
            case hash
            case imageAspectRatio
            case referencePixelSize
            case contractParameters
            case previewImageAspectRatio
            case previewReferencePixelSize
            case previewContractParameters
        }

        init(
            id: String,
            name: String?,
            url: String?,
            sh: String?,
            hash: String?,
            aspectRatio: AspectRatio? = nil,
            imageAspectRatio: AspectRatio? = nil,
            referencePixelSize: ArtworkReferencePixelSize? = nil,
            contractParameters: [String: String]? = nil
        ) {
            self.id = id
            self.name = name
            self.url = url
            self.sh = sh
            self.hash = hash
            self.aspectRatio = aspectRatio
            self.imageAspectRatio = imageAspectRatio
            self.referencePixelSize = referencePixelSize
            self.contractParameters = contractParameters
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            sh = try container.decodeIfPresent(String.self, forKey: .sh)
            hash = try container.decodeIfPresent(String.self, forKey: .hash)
            aspectRatio = nil
            imageAspectRatio = try container.decodeIfPresent(AspectRatio.self, forKey: .imageAspectRatio)
                ?? container.decodeIfPresent(AspectRatio.self, forKey: .previewImageAspectRatio)
            referencePixelSize = try container.decodeIfPresent(ArtworkReferencePixelSize.self, forKey: .referencePixelSize)
                ?? container.decodeIfPresent(ArtworkReferencePixelSize.self, forKey: .previewReferencePixelSize)
            contractParameters = try container.decodeIfPresent([String: String].self, forKey: .contractParameters)
                ?? container.decodeIfPresent([String: String].self, forKey: .previewContractParameters)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(url, forKey: .url)
            try container.encodeIfPresent(sh, forKey: .sh)
            try container.encodeIfPresent(hash, forKey: .hash)
            try container.encodeIfPresent(imageAspectRatio, forKey: .imageAspectRatio)
            try container.encodeIfPresent(referencePixelSize, forKey: .referencePixelSize)
            try container.encodeIfPresent(contractParameters, forKey: .contractParameters)
        }
    }

    private struct CompactItem: Decodable, Sendable {
        struct Metadata: Decodable, Sendable {
            let name: String?
            let hash: String?
        }

        let id: String
        let prefixIndex: Int
        let urlSuffix: String
        let metadata: Metadata?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            id = try container.decode(String.self)
            prefixIndex = try container.decode(Int.self)
            urlSuffix = try container.decode(String.self)
            if !container.isAtEnd {
                _ = try container.decodeIfPresent(String.self)
            }
            metadata = container.isAtEnd ? nil : try container.decodeIfPresent(Metadata.self)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isComplete
        case items
        case aspectRatios
        case aspectRatioOverrides
        case urlPrefixes
    }
    
    let isComplete: Bool
    let items: [Item]
    private let aspectRatios: [AspectRatio]?
    private let aspectRatioOverrides: [AspectRatioOverride]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
        aspectRatios = try container.decodeIfPresent(
            [AspectRatio].self,
            forKey: .aspectRatios
        )
        aspectRatioOverrides = try container.decodeIfPresent(
            [AspectRatioOverride].self,
            forKey: .aspectRatioOverrides
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
                return Item(
                    id: compactItem.id,
                    name: compactItem.metadata?.name,
                    url: url,
                    sh: nil,
                    hash: compactItem.metadata?.hash
                )
            }
        }

        let resolvedAspectRatios = try AspectRatioMetadata.resolve(
            aspectRatios: aspectRatios,
            overrides: aspectRatioOverrides,
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
                aspectRatio: resolvedAspectRatios?[index],
                imageAspectRatio: item.imageAspectRatio,
                referencePixelSize: item.referencePixelSize,
                contractParameters: item.contractParameters
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(aspectRatios, forKey: .aspectRatios)
        try container.encodeIfPresent(aspectRatioOverrides, forKey: .aspectRatioOverrides)
    }
    
}
