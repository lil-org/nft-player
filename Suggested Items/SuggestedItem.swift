// ∅ 2026 lil org

import Foundation

struct SuggestedItem: Identifiable, Hashable, Codable {
    
    var id: String { address + (abId ?? collectionId ?? "") }

    var isSolanaCollection: Bool {
        chain == .solana
    }

    var isTezosCollection: Bool {
        chain == .tezos
    }

    var isIOSOnlyCollection: Bool {
        isSolanaCollection || isTezosCollection || iosOnly == true
    }

    var isDownloadableCollection: Bool {
        isIOSOnlyCollection || tokenCount != nil
    }
    
    var network: Network {
        return Network(rawValue: chainId) ?? .mainnet
    }
    
    let name: String
    let internalSlug: String?
    let address: String
    let chainId: Int
    let chain: Chain
    let collectionId: String?
    let abId: String?
    let tokenCount: Int?
    let iosOnly: Bool?
    let iosCollectionBrowserColumnCount: Int?
    let playerBackgroundColor: String?
    let webURL: String?
    let standardThumbsPathsAvailable: Bool?
    let standardThumbsBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case internalSlug = "internal_slug"
        case address
        case chainId
        case chain
        case collectionId
        case abId
        case tokenCount
        case iosOnly
        case iosCollectionBrowserColumnCount
        case playerBackgroundColor
        case webURL
        case standardThumbsPathsAvailable
        case standardThumbsBaseURL
    }
    
}
