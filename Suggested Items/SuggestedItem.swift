// ∅ 2026 lil org

import Foundation

nonisolated struct SuggestedItem: Identifiable, Hashable, Codable, Sendable {
    
    var id: String { address + (abId ?? collectionId ?? "") }

    var resourceName: String {
        internalSlug
    }

    var scriptProjectId: String {
        script?.projectId ?? abId ?? ""
    }

    var scriptDependency: PersistentArtworkDependency? {
        guard let script,
              let fileExtension = script.kind.sourceFileExtension,
              let expectedByteCount = script.expectedByteCount, expectedByteCount > 0,
              let sha256 = script.sha256,
              sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            return nil
        }
        guard !resourceName.isEmpty,
              resourceName != ".", resourceName != "..",
              !resourceName.contains("/"), !resourceName.contains("\\") else { return nil }
        let remoteURL: URL
        if let sourceURL = script.sourceURL {
            guard let components = URLComponents(string: sourceURL),
                  components.scheme?.lowercased() == "https",
                  components.host?.isEmpty == false,
                  components.user == nil, components.password == nil,
                  components.fragment == nil,
                  let url = components.url,
                  ArtworkAssetPolicy.allowsRemoteURL(url) else { return nil }
            remoteURL = url
        } else {
            remoteURL = URL(string: "https://cdn.lil.org/player/scripts/")!
                .appendingPathComponent(resourceName + "." + fileExtension)
        }
        return PersistentArtworkDependency(
            id: "script:" + resourceName,
            remoteURL: remoteURL,
            expectedByteCount: expectedByteCount,
            sha256: sha256
        )
    }

    var isSolanaCollection: Bool {
        chain == .solana
    }

    var isTezosCollection: Bool {
        chain == .tezos
    }

    var isDownloadableCollection: Bool {
        generativeOnly != true && (isSolanaCollection || isTezosCollection || tokenCount != nil)
    }
    
    var network: Network {
        return Network(rawValue: chainId) ?? .mainnet
    }

    let name: String
    let internalSlug: String
    let address: String
    let chainId: Int
    let chain: Chain
    let collectionId: String?
    let abId: String?
    let tokenCount: Int?
    let manifestTokenCount: Int?
    let hasUniformAspectRatio: Bool?
    let iosOnly: Bool?
    let generativeOnly: Bool?
    let hasCover: Bool?
    let hasThumbnails: Bool?
    let urlPrefix: String?
    let aspectRatio: AspectRatio?
    let hasMid: Bool?
    let iosCollectionBrowserColumnCount: Int?
    let playerBackgroundColor: String?
    let webURL: String?
    let collectionWebURL: String?
    let standardThumbsPathsAvailable: Bool?
    let standardThumbsBaseURL: String?
    let sizedThumbsIndexOffset: Int?
    let artists: [String]
    let script: Script.Metadata?

    enum CodingKeys: String, CodingKey {
        case name
        case internalSlug = "internal_slug"
        case address
        case chainId
        case chain
        case collectionId
        case abId
        case tokenCount
        case manifestTokenCount
        case hasUniformAspectRatio
        case iosOnly
        case generativeOnly
        case hasCover
        case hasThumbnails
        case urlPrefix
        case aspectRatio
        case hasMid
        case iosCollectionBrowserColumnCount
        case playerBackgroundColor
        case webURL
        case collectionWebURL
        case standardThumbsPathsAvailable
        case standardThumbsBaseURL
        case sizedThumbsIndexOffset
        case artists
        case script
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        internalSlug = try container.decode(String.self, forKey: .internalSlug)
        guard !internalSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .internalSlug,
                in: container,
                debugDescription: "Collection resource slug must not be empty"
            )
        }
        address = try container.decode(String.self, forKey: .address)
        chainId = try container.decode(Int.self, forKey: .chainId)
        chain = try container.decode(Chain.self, forKey: .chain)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId)
        abId = try container.decodeIfPresent(String.self, forKey: .abId)
        tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount)
        script = try container.decodeIfPresent(Script.Metadata.self, forKey: .script)
        if internalSlug == "card_nft_2", script?.kind == .cardNft2Native {
            manifestTokenCount = nil
            hasUniformAspectRatio = nil
        } else {
            let count = try container.decode(Int.self, forKey: .manifestTokenCount)
            guard count >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .manifestTokenCount,
                    in: container,
                    debugDescription: "Manifest token count must be nonnegative"
                )
            }
            manifestTokenCount = count
            hasUniformAspectRatio = try container.decode(Bool.self, forKey: .hasUniformAspectRatio)
        }
        iosOnly = try container.decodeIfPresent(Bool.self, forKey: .iosOnly)
        generativeOnly = try container.decodeIfPresent(Bool.self, forKey: .generativeOnly)
        hasCover = try container.decodeIfPresent(Bool.self, forKey: .hasCover)
        hasThumbnails = try container.decodeIfPresent(Bool.self, forKey: .hasThumbnails)
        urlPrefix = try container.decodeIfPresent(String.self, forKey: .urlPrefix)
        aspectRatio = try container.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio)
        hasMid = try container.decodeIfPresent(Bool.self, forKey: .hasMid)
        iosCollectionBrowserColumnCount = try container.decodeIfPresent(Int.self, forKey: .iosCollectionBrowserColumnCount)
        playerBackgroundColor = try container.decodeIfPresent(String.self, forKey: .playerBackgroundColor)
        webURL = try container.decodeIfPresent(String.self, forKey: .webURL)
        collectionWebURL = try container.decodeIfPresent(String.self, forKey: .collectionWebURL)
        standardThumbsPathsAvailable = try container.decodeIfPresent(Bool.self, forKey: .standardThumbsPathsAvailable)
        standardThumbsBaseURL = try container.decodeIfPresent(String.self, forKey: .standardThumbsBaseURL)
        sizedThumbsIndexOffset = try container.decodeIfPresent(Int.self, forKey: .sizedThumbsIndexOffset)
        artists = try container.decode([String].self, forKey: .artists)
    }
    
}

nonisolated struct SuggestedArtist: Identifiable, Hashable, Sendable {

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

nonisolated struct SuggestedArtistLink: Identifiable, Hashable, Sendable {

    enum Kind: Hashable, Sendable {
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
