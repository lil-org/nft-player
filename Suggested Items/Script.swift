// ∅ 2026 lil org

nonisolated struct Script: Sendable {

    let id: String
    let address: String
    let name: String
    let abId: String
    let chain: Chain?
    let chainId: Int?
    let value: String
    let metadata: Metadata

    var kind: Kind { metadata.kind }
    var nftPlayerDisplayTuning: String? { metadata.nftPlayerDisplayTuning }
    var renderingProfile: RenderingProfile? { metadata.renderingProfile }
    var requiresInitialCanvas: Bool? { metadata.requiresInitialCanvas }
    var additionalLibraries: [Kind]? { metadata.additionalLibraries }
    var isModule: Bool? { metadata.isModule }
    var externalAssetDependencies: [ExternalAssetDependency]? { metadata.externalAssetDependencies }
    var usesArtBlocksRenderer: Bool { renderingProfile == .artBlocks }

    init(
        id: String,
        address: String,
        name: String,
        abId: String = "",
        chain: Chain? = nil,
        chainId: Int? = nil,
        value: String,
        metadata: Metadata
    ) {
        self.id = id
        self.address = address
        self.name = name
        self.abId = abId
        self.chain = chain
        self.chainId = chainId
        self.value = value
        self.metadata = metadata
    }

    init?(item: SuggestedItem, value: String) {
        guard let metadata = item.script else { return nil }
        self.init(
            id: item.id,
            address: item.address,
            name: item.name,
            abId: metadata.projectId ?? item.abId ?? "",
            chain: item.chain,
            chainId: item.chainId,
            value: value,
            metadata: metadata
        )
    }

    var legacyArtBlocksCollectionId: String? {
        guard usesArtBlocksRenderer else { return nil }
        return address + "-dev-good-" + String(chainId ?? 1) + "-" + abId
    }

    struct Metadata: Codable, Hashable, Sendable {
        var kind: Kind
        var projectId: String? = nil
        var renderingProfile: RenderingProfile? = nil
        var nftPlayerDisplayTuning: String? = nil
        var requiresInitialCanvas: Bool? = nil
        var additionalLibraries: [Kind]? = nil
        var isModule: Bool? = nil
        var externalAssetDependencies: [ExternalAssetDependency]? = nil
    }

    enum RenderingProfile: String, Codable, Hashable, Sendable {
        case artBlocks
    }

    struct ExternalAssetDependency: Codable, Hashable, Sendable {
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

        var sourceFileExtension: String? {
            switch self {
            case .ponchoDrifellaNative, .cardNft2Native:
                return nil
            case .html:
                return "html"
            case .processingjs146:
                return "pde"
            default:
                return "js"
            }
        }
    }
}
