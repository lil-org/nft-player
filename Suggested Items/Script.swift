// ∅ 2026 lil org

nonisolated struct Script: Codable, Sendable {
    
    var id: String { collectionIdOverride ?? address + abId }
    
    let collectionIdOverride: String?
    let address: String
    let name: String
    let abId: String
    let chain: Chain?
    let value: String
    let kind: Kind
    let nftPlayerDisplayTuning: String?
    let renderingProfile: RenderingProfile?
    let chainId: Int?
    let requiresInitialCanvas: Bool?
    let additionalLibraries: [Kind]?
    let isModule: Bool?
    let externalAssetDependencies: [ExternalAssetDependency]?
    var usesArtBlocksRenderer: Bool { renderingProfile == .artBlocks }

    var legacyArtBlocksCollectionId: String? {
        guard usesArtBlocksRenderer else { return nil }
        return address + "-dev-good-" + String(chainId ?? 1) + "-" + abId
    }

    enum RenderingProfile: String, Codable, Sendable {
        case artBlocks
    }

    struct ExternalAssetDependency: Codable, Sendable {
        let index: Int
        let cid: String
        let dependency_type: String
        let data: String?
        let bytecode_address: String?
    }
    
    enum Kind: String, Codable, Hashable, Sendable {
        case svg, js, p5js100, regl, twemoji, three, tone, paper, p5js190, processingjs146
        case html, p5js140, p5js11111, three160, three167, babylon500, tone1504
        case ort1140, p5js160, seedrandom305, p5svg, three155
        case ponchoDrifellaNative = "native.poncho-drifella"
        case cardNft2Native = "native.card-nft-2"

        var generatedTokenRenderKind: GeneratedTokenRenderKind? {
            switch self {
            case .ponchoDrifellaNative:
                return .ponchoDrifellaMetal
            case .cardNft2Native:
                return .cardNft2Metal
            default:
                return nil
            }
        }

        var isNativeRenderer: Bool {
            generatedTokenRenderKind != nil
        }
    }
}
