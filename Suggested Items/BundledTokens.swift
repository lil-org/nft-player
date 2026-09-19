// ∅ 2026 lil org

import CoreGraphics
import Foundation

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

nonisolated enum BundledTokenMetadata {
    static func count(_ count: Int?, loading fallback: () -> Int) -> Int {
        if let count, count >= 0 {
            return count
        }
        return fallback()
    }

    static func aspectRatioProfile(
        count: Int?,
        isUniform: Bool?,
        defaultAspectRatio: AspectRatio?,
        loading fallback: () -> AspectRatioProfile?
    ) -> AspectRatioProfile? {
        if count == 0 {
            return nil
        }
        if let count, count > 0,
           isUniform == true,
           let defaultAspectRatio {
            return .uniform(defaultAspectRatio)
        }
        return fallback()
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
        let urlSuffix: String?
        let hash: String?
        let aspectRatio: AspectRatio?
        let contractParameters: [String: String]?

        init(
            id: String,
            name: String?,
            hash: String?,
            aspectRatio: AspectRatio? = nil,
            contractParameters: [String: String]? = nil,
            urlSuffix: String? = nil
        ) {
            self.id = id
            self.name = name
            self.urlSuffix = urlSuffix
            self.hash = hash
            self.aspectRatio = aspectRatio
            self.contractParameters = contractParameters
        }

        func resolvingAspectRatio(default defaultAspectRatio: AspectRatio?) -> Self {
            guard aspectRatio == nil, let defaultAspectRatio else { return self }
            return Self(
                id: id,
                name: name,
                hash: hash,
                aspectRatio: defaultAspectRatio,
                contractParameters: contractParameters,
                urlSuffix: urlSuffix
            )
        }
    }

    let items: [Item]

    init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}
