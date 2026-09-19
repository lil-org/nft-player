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

nonisolated struct BundledTokens: Codable, Sendable {
    
    struct Item: Codable, Sendable {
        let id: String
        let name: String?
        let url: String?
        let urlSuffix: String?
        let fileExtension: String?
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
            case urlSuffix
            case fileExtension
            case aspectRatio
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
            contractParameters: [String: String]? = nil,
            urlSuffix: String? = nil,
            fileExtension: String? = nil
        ) {
            self.id = id
            self.name = name
            self.url = url
            self.urlSuffix = urlSuffix
            self.fileExtension = fileExtension
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
            urlSuffix = try container.decodeIfPresent(String.self, forKey: .urlSuffix)
            fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
            sh = try container.decodeIfPresent(String.self, forKey: .sh)
            hash = try container.decodeIfPresent(String.self, forKey: .hash)
            aspectRatio = try container.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio)
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
            if let url {
                try container.encode(url, forKey: .url)
            } else {
                try container.encodeIfPresent(urlSuffix, forKey: .urlSuffix)
            }
            try container.encodeIfPresent(fileExtension, forKey: .fileExtension)
            try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
            try container.encodeIfPresent(sh, forKey: .sh)
            try container.encodeIfPresent(hash, forKey: .hash)
            try container.encodeIfPresent(imageAspectRatio, forKey: .imageAspectRatio)
            try container.encodeIfPresent(referencePixelSize, forKey: .referencePixelSize)
            try container.encodeIfPresent(contractParameters, forKey: .contractParameters)
        }
    }

    let items: [Item]

    init(data: Data, collection: SuggestedItem) throws {
        let payload = try JSONDecoder().decode(Self.self, from: data)
        let prefix = collection.urlPrefix ?? ""
        items = payload.items.map { item in
            Item(
                id: item.id,
                name: item.name,
                url: item.url ?? item.urlSuffix.map { prefix + $0 },
                sh: item.sh,
                hash: item.hash,
                aspectRatio: item.aspectRatio ?? collection.aspectRatio,
                imageAspectRatio: item.imageAspectRatio,
                referencePixelSize: item.referencePixelSize,
                contractParameters: item.contractParameters,
                fileExtension: item.fileExtension
            )
        }
    }
}
