// ∅ 2026 lil org

import Foundation
import Observation

nonisolated enum WidgetDeepLink: Hashable, Sendable {
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

    func collectionTarget(
        ifSupported isSupportedCollection: (String) -> Bool
    ) -> WidgetCollectionDeepLinkTarget? {
        guard case let .collection(collectionId, tokenId) = self,
              isSupportedCollection(collectionId) else {
            return nil
        }
        return WidgetCollectionDeepLinkTarget(
            collectionId: collectionId,
            tokenId: tokenId
        )
    }
}

nonisolated struct WidgetCollectionDeepLinkTarget: Equatable, Sendable {
    let collectionId: String
    let tokenId: String?
}

@MainActor
@Observable
final class WidgetLaunchPresentationState {
    struct Request: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate let deepLink: WidgetDeepLink
    }

    static let shared = WidgetLaunchPresentationState()

    private var pendingWidgetPlayerHandoffs = [WidgetDeepLink: UUID]()

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
                  deepLink.collectionTarget(
                    ifSupported: isSupportedCollection
                  ) != nil else {
                return nil
            }
            return deepLink
        })
        for deepLink in incomingHandoffs where pendingWidgetPlayerHandoffs[deepLink] == nil {
            pendingWidgetPlayerHandoffs[deepLink] = UUID()
        }
    }

    func beginWidgetPlayerHandoff(for url: URL) -> Request? {
        guard let deepLink = WidgetDeepLink(url: url),
              pendingWidgetPlayerHandoffs[deepLink] != nil else {
            return nil
        }
        let request = Request(id: UUID(), deepLink: deepLink)
        pendingWidgetPlayerHandoffs[deepLink] = request.id
        return request
    }

    func finishWidgetPlayerHandoff(_ request: Request?) {
        guard let request,
              pendingWidgetPlayerHandoffs[request.deepLink] == request.id else {
            return
        }
        pendingWidgetPlayerHandoffs.removeValue(forKey: request.deepLink)
    }

    func finishWidgetPlayerHandoff(for url: URL) {
        guard let deepLink = WidgetDeepLink(url: url) else { return }
        pendingWidgetPlayerHandoffs.removeValue(forKey: deepLink)
    }

    func cancelAllWidgetPlayerHandoffs() {
        guard !pendingWidgetPlayerHandoffs.isEmpty else { return }
        pendingWidgetPlayerHandoffs.removeAll()
    }
}
