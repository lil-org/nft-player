import Foundation

nonisolated enum BundledMediaResolver {
    enum Kind: Sendable {
        case staticImage
        case animatedImage
        case video
        case html
    }

    struct Resolved: Sendable {
        let url: URL
        let fileExtension: String?
        let kind: Kind?
    }

    static func resolve(_ source: String) -> Resolved? {
        guard let url = URL(string: source) else { return nil }
        let rawExtension = url.pathExtension.isEmpty
            ? URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "ext" }?.value
            : url.pathExtension
        let normalized = rawExtension?.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t\r"))
            .lowercased()
        let fileExtension = normalized?.isEmpty == false ? normalized : nil
        return Resolved(url: url, fileExtension: fileExtension, kind: fileExtension.flatMap(kind))
    }

    static func kind(for fileExtension: String) -> Kind? {
        switch fileExtension {
        case "png", "jpg", "jpeg", "webp", "heic", "heif", "tiff": .staticImage
        case "gif", "svg": .animatedImage
        case "mp4", "mov": .video
        case "html", "htm", "xhtml": .html
        default: nil
        }
    }
}
