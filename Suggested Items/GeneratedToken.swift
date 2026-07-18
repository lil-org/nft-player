// ∅ 2026 lil org

import Foundation

enum GeneratedTokenRenderKind: String, Hashable {
    case html
    case ponchoDrifellaMetal
    case cardNft2Metal
}

enum NativeMetalCardRenderKind: String, Hashable, CaseIterable {
    case ponchoDrifella
    case cardNft2
}

extension NativeMetalCardRenderKind {
    var collectionId: String {
        switch self {
        case .cardNft2:
            return "EAzEpagtyeRAx9npnpVMpygoA8ouX7DRpLTghhPvYTiu"
        case .ponchoDrifella:
            return "JCTP3kK3xGtWs5mDHxJBuRro38HftaiCDdKsfkXuK2gH"
        }
    }

    init?(collectionId: String) {
        guard let renderKind = Self.allCases.first(where: { $0.collectionId == collectionId }) else {
            return nil
        }
        self = renderKind
    }
}

extension GeneratedTokenRenderKind {
    var nativeMetalCardRenderKind: NativeMetalCardRenderKind? {
        switch self {
        case .ponchoDrifellaMetal:
            return .ponchoDrifella
        case .cardNft2Metal:
            return .cardNft2
        case .html:
            return nil
        }
    }
}

enum GeneratedTokenMedia: Hashable {
    case staticImage(url: URL, fileExtension: String)
    case animatedImage(url: URL, fileExtension: String)
    case video(url: URL, fileExtension: String)
    case html(url: URL, fileExtension: String)

    var url: URL {
        switch self {
        case let .staticImage(url, _), let .animatedImage(url, _), let .video(url, _), let .html(url, _):
            return url
        }
    }

    var fileExtension: String {
        switch self {
        case let .staticImage(_, fileExtension), let .animatedImage(_, fileExtension), let .video(_, fileExtension), let .html(_, fileExtension):
            return fileExtension
        }
    }

    var isStaticImage: Bool {
        if case .staticImage = self {
            return true
        }
        return false
    }

}

struct GeneratedToken: Hashable, Identifiable {
    let fullCollectionId: String
    let collectionName: String
    let address: String
    let id: String
    let html: String
    let displayName: String
    let displayTokenId: String
    let url: URL?
    let media: GeneratedTokenMedia?
    let renderKind: GeneratedTokenRenderKind?

    var nativeMetalCardRenderKind: NativeMetalCardRenderKind? {
        renderKind?.nativeMetalCardRenderKind
    }

    init(
        fullCollectionId: String,
        collectionName: String,
        address: String,
        id: String,
        html: String,
        displayName: String,
        displayTokenId: String,
        url: URL?,
        media: GeneratedTokenMedia? = nil,
        renderKind: GeneratedTokenRenderKind? = nil
    ) {
        self.fullCollectionId = fullCollectionId
        self.collectionName = collectionName
        self.address = address
        self.id = id
        self.html = html
        self.displayName = displayName
        self.displayTokenId = displayTokenId
        self.url = url
        self.media = media
        self.renderKind = renderKind
    }

    static let empty = GeneratedToken(
        fullCollectionId: "",
        collectionName: "",
        address: "",
        id: "",
        html: "",
        displayName: "",
        displayTokenId: "",
        url: nil
    )
}
