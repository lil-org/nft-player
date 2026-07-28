// ∅ 2026 lil org

enum NativeMetalCardEffect: UInt8 {
    case rareHoloV = 0
    case supporter = 1
    case amazingRare = 2
    case rareHolo = 3
    case cardNft2Common = 4

    var requiresEffectAssets: Bool {
        self != .cardNft2Common
    }
}

struct NativeMetalCardMetadata {
    let effect: NativeMetalCardEffect
    let glowKind: UInt8

    var effectKind: UInt8 {
        effect.rawValue
    }

    var requiresEffectAssets: Bool {
        effect.requiresEffectAssets
    }

    init(effect: NativeMetalCardEffect, glowKind: UInt8) {
        self.effect = effect
        self.glowKind = glowKind
    }

    init(effectKind: UInt8, glowKind: UInt8) {
        guard let effect = NativeMetalCardEffect(rawValue: effectKind) else {
            preconditionFailure("Unknown native metal card effect: \(effectKind)")
        }
        self.effect = effect
        self.glowKind = glowKind
    }

    static func ponchoDrifella(for tokenID: Int) -> NativeMetalCardMetadata {
        let metadata = PonchoDrifellaCardMetadata.metadata(for: tokenID)
        return NativeMetalCardMetadata(
            effectKind: metadata.effectKind,
            glowKind: metadata.glowKind
        )
    }

    static func cardNft2(for tokenID: Int) -> NativeMetalCardMetadata {
        CardNft2CardMetadata.metadata(for: tokenID).nativeMetalMetadata
    }
}

extension NativeMetalCardRenderKind {
    var tokenCount: Int {
        switch self {
        case .cardNft2:
            return CardNft2CardMetadata.tokenCount
        case .ponchoDrifella:
            return PonchoDrifellaCardMetadata.tokenCount
        }
    }

    func metadata(for tokenID: Int) -> NativeMetalCardMetadata {
        switch self {
        case .cardNft2:
            return .cardNft2(for: tokenID)
        case .ponchoDrifella:
            return .ponchoDrifella(for: tokenID)
        }
    }
}
