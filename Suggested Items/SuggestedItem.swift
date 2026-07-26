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
    let artists: [String]

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
        case artists
    }
    
}

struct SuggestedArtist: Identifiable, Hashable {

    let id: String
    let name: String
    let website: URL?
    let x: URL?
    let bluesky: URL?

    var links: [SuggestedArtistLink] {
        [
            website.map {
                SuggestedArtistLink(
                    kind: .website,
                    destination: $0
                )
            },
            x.map {
                SuggestedArtistLink(
                    kind: .x,
                    destination: $0
                )
            },
            bluesky.map {
                SuggestedArtistLink(
                    kind: .bluesky,
                    destination: $0
                )
            },
        ]
        .compactMap { $0 }
    }

}

struct SuggestedArtistLink: Identifiable, Hashable {

    enum Kind: Hashable {
        case website
        case x
        case bluesky
    }

    var id: Kind { kind }

    let kind: Kind
    let destination: URL

    var title: String {
        switch kind {
        case .website:
            return Self.websiteAddress(from: destination)
        case .x, .bluesky:
            return Self.socialHandle(from: destination)
        }
    }

    private static func websiteAddress(from url: URL) -> String {
        var address = url.absoluteString
        if let scheme = url.scheme {
            let schemePrefix = scheme + "://"
            if address.lowercased().hasPrefix(schemePrefix.lowercased()) {
                address.removeFirst(schemePrefix.count)
            }
        }
        return address.hasSuffix("/")
            ? String(address.dropLast())
            : address
    }

    private static func socialHandle(from url: URL) -> String {
        let pathComponent = url.lastPathComponent.removingPercentEncoding
            ?? url.lastPathComponent
        guard !pathComponent.isEmpty else { return url.absoluteString }
        return pathComponent.hasPrefix("@") ? pathComponent : "@" + pathComponent
    }

}
