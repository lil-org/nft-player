// ∅ 2026 lil org

import Foundation

enum Network: Int, CaseIterable, Codable {
    
    case zora = 7777777, base = 8453, mainnet = 1, optimism = 10, arbitrum = 42161, blast = 238
    
    var name: String {
        switch self {
        case .mainnet:
            return "ETHEREUM"
        case .optimism:
            return "OPTIMISM"
        case .zora:
            return "ZORA"
        case .base:
            return "BASE"
        case .arbitrum:
            return "ARBITRUM"
        case .blast:
            return "BLAST"
        }
    }
    
}
