// ∅ 2026 lil org

import Foundation

enum WidgetDeepLink: Hashable {
    private static let scheme = "nft-folder"
    private static let collectionHost = "collection"

    case collection(id: String, tokenId: String?)

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }

        switch url.host {
        case Self.collectionHost:
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let collectionId = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  !collectionId.isEmpty else {
                return nil
            }
            let tokenId = components.queryItems?.first(where: { $0.name == "tokenId" })?.value
            self = .collection(id: collectionId, tokenId: tokenId?.isEmpty == false ? tokenId : nil)
        default:
            return nil
        }
    }

    var url: URL? {
        switch self {
        case let .collection(id, tokenId):
            guard !id.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = Self.collectionHost
            var queryItems = [
                URLQueryItem(name: "id", value: id),
            ]
            if let tokenId, !tokenId.isEmpty {
                queryItems.append(URLQueryItem(name: "tokenId", value: tokenId))
            }
            components.queryItems = queryItems
            return components.url
        }
    }
}
