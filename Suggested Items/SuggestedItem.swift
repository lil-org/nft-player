// ∅ 2026 lil org

import Foundation

struct SuggestedItem: Identifiable, Hashable, Codable {
    
    var id: String { address + (abId ?? collectionId ?? "") }

    var isSolanaCollection: Bool {
        chain == .solana
    }
    
    var network: Network {
        return Network(rawValue: chainId) ?? .mainnet
    }
    
    let name: String
    let address: String
    let chainId: Int
    let chain: Chain
    let collectionId: String?
    let abId: String?
    let tokenCount: Int?
    
}
