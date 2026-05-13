// ∅ 2026 lil org

import Foundation
#if canImport(AppKit)
import Cocoa
#endif

enum NftGallery: Int, CaseIterable, Codable {
    
    static let referrer = "0xE26067c76fdbe877F48b0a8400cf5Db8B47aF0fE"
    
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
    
    func url(wallet: WatchOnlyWallet) -> URL? {
        if let collectionNetwork = wallet.collections?.first?.network {
            return url(network: collectionNetwork, chain: wallet.chain, collectionAddress: wallet.address, tokenId: nil)
        } else {
            return url(walletAddress: wallet.address, chain: wallet.chain)
        }
    }
    
    private func url(walletAddress: String, chain: Chain?) -> URL? {
        switch self {
        case .blockExplorer:
            let network = chain?.network ?? .mainnet
            return URL(string: "\(network.blockExplorerBaseURLString)/address/\(walletAddress)")
        case .opensea:
            return URL(string: "https://opensea.io/\(walletAddress)")
        }
    }
    
    func url(network: Network, chain: Chain?, collectionAddress: String, tokenId: String?) -> URL? {
        switch self {
        case .blockExplorer:
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
