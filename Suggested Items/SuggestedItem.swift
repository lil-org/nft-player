// ∅ 2026 lil org

import Foundation

nonisolated struct SuggestedItem: Identifiable, Hashable, Codable, Sendable {
    
    var id: String { address + (abId ?? collectionId ?? "") }

    var bundledResourceName: String {
        guard let internalSlug, !internalSlug.isEmpty else { return id }
        return internalSlug
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
        let resourceName = bundledResourceName
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
                  let url = components.url else { return nil }
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

    var isIOSOnlyCollection: Bool {
        isSolanaCollection || isTezosCollection || iosOnly == true
    }

    var isDownloadableCollection: Bool {
        generativeOnly != true && (isSolanaCollection || isTezosCollection || tokenCount != nil)
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
    let bundledDate: String?
    let iosOnly: Bool?
    let generativeOnly: Bool?
    let hasCover: Bool?
    let hasThumbnails: Bool?
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
        case bundledDate
        case iosOnly
        case generativeOnly
        case hasCover
        case hasThumbnails
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
