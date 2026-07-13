// ∅ 2026 lil org

import Combine
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

final class WidgetLaunchPresentationState: ObservableObject {
    static let shared = WidgetLaunchPresentationState()

    @Published private var pendingWidgetPlayerHandoffs = Set<WidgetDeepLink>()

    var isSuppressingContinueViewing: Bool {
        !pendingWidgetPlayerHandoffs.isEmpty
    }

    func prepareForIncomingURLs(
        _ urls: [URL],
        isApplicationLaunch: Bool,
        isSupportedCollection: (String) -> Bool
    ) {
        guard isApplicationLaunch else { return }

        let incomingHandoffs = Set(urls.compactMap { url -> WidgetDeepLink? in
            guard let deepLink = WidgetDeepLink(url: url),
                  case let .collection(collectionId, _) = deepLink,
                  isSupportedCollection(collectionId) else {
                return nil
            }
            return deepLink
        })
        let updatedHandoffs = pendingWidgetPlayerHandoffs.union(incomingHandoffs)
        guard updatedHandoffs != pendingWidgetPlayerHandoffs else { return }
        pendingWidgetPlayerHandoffs = updatedHandoffs
    }

    func finishWidgetPlayerHandoff(for url: URL) {
        guard let deepLink = WidgetDeepLink(url: url),
              pendingWidgetPlayerHandoffs.contains(deepLink) else {
            return
        }
        pendingWidgetPlayerHandoffs.remove(deepLink)
    }

    func cancelAllWidgetPlayerHandoffs() {
        guard !pendingWidgetPlayerHandoffs.isEmpty else { return }
        pendingWidgetPlayerHandoffs.removeAll()
    }
}
