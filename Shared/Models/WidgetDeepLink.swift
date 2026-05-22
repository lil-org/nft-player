// ∅ 2026 lil org

import Foundation

enum WidgetDeepLink: Hashable {
    private static let scheme = "nft-folder"
    private static let collectionHost = "collection"

    case collection(id: String)

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }

        switch url.host {
        case Self.collectionHost:
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let collectionId = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  !collectionId.isEmpty else {
                return nil
            }
            self = .collection(id: collectionId)
        default:
            return nil
        }
    }

    var url: URL? {
        switch self {
        case let .collection(id):
            guard !id.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = Self.collectionHost
            components.queryItems = [
                URLQueryItem(name: "id", value: id),
            ]
            return components.url
        }
    }
}
