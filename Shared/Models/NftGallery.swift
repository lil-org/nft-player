// ∅ 2026 lil org

import Foundation
#if canImport(AppKit)
import Cocoa
#endif

enum NftGallery: Int, CaseIterable, Codable {

    case opensea, blockExplorer
    
#if canImport(AppKit)
    var image: NSImage {
        switch self {
        case .blockExplorer:
            return Images.infoTitleBar
        case .opensea:
            return Images.opensea
        }
    }
#endif
    
    var title: String {
        switch self {
        case .opensea:
            Strings.opensea
        case .blockExplorer:
            Strings.blockExplorer
        }
    }

    func url(network: Network, chain: Chain?, collectionAddress: String, tokenId: String?) -> URL? {
        switch self {
        case .blockExplorer:
            if chain == .tezos {
                let tokenPath = tokenId.map { "/tokens/\($0)" } ?? ""
                return URL(string: "https://tzkt.io/\(collectionAddress)\(tokenPath)")
            }
            let tokenInstancePath = tokenId.map { "/instance/\($0)?tab=metadata" } ?? ""
            let urlString = "\(network.blockExplorerBaseURLString)/token/\(collectionAddress)\(tokenInstancePath)"
            return URL(string: urlString)
        case .opensea:
            let prefix: String
            switch network {
            case .mainnet:
                prefix = "ethereum"
            case .optimism:
                prefix = "optimism"
            case .zora:
                prefix = "zora"
            case .base:
                prefix = "base"
            case .arbitrum:
                prefix = "arbitrum"
            case .blast:
                prefix = "blast"
            }
            return URL(string: "https://opensea.io/assets/\(prefix)/\(collectionAddress)/\(tokenId ?? "")")
        }
    }
    
}

private extension Network {
    var blockExplorerBaseURLString: String {
        switch self {
        case .mainnet:
            return "https://eth.blockscout.com"
        case .optimism:
            return "https://explorer.optimism.io"
        case .zora:
            return "https://explorer.zora.energy"
        case .base:
            return "https://base.blockscout.com"
        case .arbitrum:
            return "https://arbitrum.blockscout.com"
        case .blast:
            return "https://blast.blockscout.com"
        }
    }
}
