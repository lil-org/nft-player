// ∅ 2026 lil org

import Foundation

struct RawNftsApi {
    
    private static let urlSession = URLSession.shared
    private static let queue = DispatchQueue(label: "\(Bundle.hostBundleId).RawNftsApi", qos: .default)
    
    static func get(owner: String, network: Network = .mainnet, nextCursor: String?, completion: @escaping (NftsResponse?) -> Void) {
        guard let url = URL(string: "https://api.opensea.io/api/v2/chain/\(network.openSeaChain)/account/\(owner)/nfts") else {
            completion(nil)
            return
        }
        
        getNfts(url: url, nextCursor: nextCursor, completion: completion)
    }
    
    static func get(contract: String, network: Network = .mainnet, nextCursor: String?, completion: @escaping (NftsResponse?) -> Void) {
        guard let url = URL(string: "https://api.opensea.io/api/v2/chain/\(network.openSeaChain)/contract/\(contract)/nfts") else {
            completion(nil)
            return
        }
        
        getNfts(url: url, nextCursor: nextCursor, completion: completion)
    }
    
    static func getCollectionInfo(contract: String, completion: @escaping (CollectionInfoResponse?) -> Void) {
        guard let url = URL(string: "https://api.opensea.io/api/v2/chain/ethereum/contract/\(contract)") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        setupRequest(&request)
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            if let data = data, error == nil, let collectionInfo = try? JSONDecoder().decode(CollectionInfoResponse.self, from: data) {
                completion(collectionInfo)
            } else {
                completion(nil)
            }
        }
        task.resume()
    }
    
    private static func getNfts(url: URL, nextCursor: String?, retryCount: Int = 0, completion: @escaping (NftsResponse?) -> Void) {
        var request = URLRequest(url: url)
        if let nextCursor = nextCursor, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            let queryItems: [URLQueryItem] = [
                URLQueryItem(name: "next", value: nextCursor),
            ]
            components.queryItems = components.queryItems.map { $0 + queryItems } ?? queryItems
            if let nextUrl = components.url {
                request = URLRequest(url: nextUrl)
            }
        }
        
        setupRequest(&request)
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            let maxRetryCount = 3
            guard let data = data, error == nil, let nftsResponse = try? JSONDecoder().decode(NftsResponse.self, from: data) else {
                if retryCount > maxRetryCount {
                    completion(nil)
                } else {
                    queue.asyncAfter(deadline: .now() + .seconds(retryCount + 1)) {
                        getNfts(url: url, nextCursor: nextCursor, retryCount: retryCount + 1, completion: completion)
                    }
                }
                return
            }
            completion(nftsResponse)
        }
        task.resume()
    }
    
    private static func setupRequest(_ request: inout URLRequest) {
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.allHTTPHeaderFields = [
            "accept": "application/json",
            "x-api-key": Secrets.openSea ?? ""
        ]
    }
    
}

struct CollectionInfoResponse: Codable {
    let address: String
    let chain: String
    let collection: String
    let name: String
}

struct NftsResponse: Codable {
    let nfts: [OpenSeaNft]
    let next: String?
}

struct OpenSeaNft: Codable {
    let identifier: String
    let collection: String
    let contract: String
    let tokenStandard: String
    let name: String?
    let description: String?
    let imageUrl: String?
    let displayImageUrl: String?
    let displayAnimationUrl: String?
    let metadataUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case identifier
        case collection
        case contract
        case tokenStandard = "token_standard"
        case name
        case description
        case imageUrl = "image_url"
        case displayImageUrl = "display_image_url"
        case displayAnimationUrl = "display_animation_url"
        case metadataUrl = "metadata_url"
    }
}

extension OpenSeaNft {
    
    func detailedMetadata(network: Network, chain: Chain?) -> DetailedTokenMetadata {
        let rawContentRepresentations = [
            ContentRepresentation(url: displayAnimationUrl, size: nil, mimeType: nil, knownKind: .video),
            ContentRepresentation(url: imageUrl, size: nil, mimeType: nil, knownKind: .image),
            ContentRepresentation(url: displayImageUrl, size: nil, mimeType: nil, knownKind: .image),
            ContentRepresentation(url: metadataUrl, size: nil, mimeType: nil, knownKind: nil),
        ]
        
        var contentRepresentations = [ContentRepresentation]()
        var hasDataRepresentation = false
        for item in rawContentRepresentations {
            guard let item = item else { continue }
            switch item.dataOrUrl {
            case .data:
                if !hasDataRepresentation {
                    hasDataRepresentation = true
                    contentRepresentations.append(item)
                }
            case .url:
                if !contentRepresentations.contains(where: { $0.dataOrUrl == item.dataOrUrl }) {
                    contentRepresentations.append(item)
                }
            }
        }
        
        return DetailedTokenMetadata(name: name,
                                     collectionName: collection,
                                     collectionAddress: contract,
                                     tokenId: identifier,
                                     chain: chain,
                                     network: network,
                                     tokenStandard: tokenStandard,
                                     contentRepresentations: contentRepresentations)
    }
    
}

private extension Network {

    var openSeaChain: String {
        switch self {
        case .mainnet:
            return "ethereum"
        case .optimism:
            return "optimism"
        case .zora:
            return "zora"
        case .base:
            return "base"
        case .arbitrum:
            return "arbitrum"
        case .blast:
            return "blast"
        }
    }

}

struct InlineContentJSON: Decodable {
    
    private let animationURL: String?
    private let image: String?
    private let svgImageData: String?
    private let imageData: String?
    
    var dataString: String? {
        return animationURL ?? image ?? svgImageData ?? imageData
    }
    
    enum CodingKeys: String, CodingKey {
        case animationURL = "animation_url"
        case image = "image"
        case svgImageData = "svg_image_data"
        case imageData = "image_data"
    }
    
}
