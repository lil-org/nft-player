// ∅ 2026 lil org

struct Script: Codable {
    
    var id: String { address + abId }
    
    let address: String
    let name: String
    let abId: String
    let chain: Chain?
    let value: String
    let kind: Kind
    let nftPlayerDisplayTuning: String?
    
    enum Kind: String, Codable {
        case svg, js, p5js100, regl, twemoji, three, tone, paper, p5js190
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
