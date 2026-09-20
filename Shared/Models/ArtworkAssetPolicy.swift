import Foundation

nonisolated enum ArtworkAssetPolicy {
    static let contentSecurityPolicy = [
        "default-src https://cdn.lil.org file: data: blob:",
        "script-src https://cdn.lil.org file: data: blob: 'unsafe-inline' 'unsafe-eval'",
        "style-src https://cdn.lil.org file: data: blob: 'unsafe-inline'",
        "connect-src https://cdn.lil.org file: data: blob:",
        "frame-src file: data: blob:",
        "worker-src data: blob:",
        "object-src 'none'",
    ].joined(separator: "; ")

    static let contentSecurityPolicyMetaTag =
        "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"

    private static let documentPrefix = try! NSRegularExpression(
        pattern: #"\A(?:\s|<!--[\s\S]*?-->|<!doctype(?:[^>"']|"[^"]*"|'[^']*')*>)*(?:<html\b(?:[^>"']|"[^"]*"|'[^']*')*>)?(?:\s|<!--[\s\S]*?-->)*(?:<head\b(?:[^>"']|"[^"]*"|'[^']*')*>)?"#,
        options: .caseInsensitive
    )

    static func allowsRemoteURL(_ url: URL, allowsTerraforms: Bool = false) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443 else { return false }
        if components.host?.lowercased() == "cdn.lil.org" { return true }
        guard allowsTerraforms,
              components.host?.lowercased() == "tokens.mathcastles.xyz",
              components.percentEncodedPath.hasPrefix("/terraforms/token-html/") else { return false }
        let tokenID = components.percentEncodedPath.dropFirst("/terraforms/token-html/".count)
        return !tokenID.isEmpty && tokenID.utf8.allSatisfy({ (48...57).contains($0) })
            && components.queryItems == [URLQueryItem(name: "ext", value: "html")]
    }

    static func validateRemoteURL(_ url: URL, allowsTerraforms: Bool = false) throws {
        guard allowsRemoteURL(url, allowsTerraforms: allowsTerraforms) else {
            throw URLError(.unsupportedURL)
        }
    }

    static func protectHTML(_ html: String) -> String {
        guard !html.isEmpty,
              let prefix = documentPrefix.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(prefix.range, in: html) else { return html }
        let insertionIndex = range.upperBound
        guard !html[insertionIndex...].hasPrefix(contentSecurityPolicyMetaTag) else { return html }
        var result = html
        result.insert(contentsOf: contentSecurityPolicyMetaTag + "\n", at: insertionIndex)
        return result
    }

    static func makeSession(
        configuration: URLSessionConfiguration,
        allowsTerraforms: Bool = false
    ) -> URLSession {
        URLSession(
            configuration: configuration,
            delegate: ArtworkAssetRedirectDelegate(allowsTerraforms: allowsTerraforms),
            delegateQueue: nil
        )
    }

    static let cdnSession = makeSession(configuration: .ephemeral)
}

nonisolated private final class ArtworkAssetRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let allowsTerraforms: Bool

    init(allowsTerraforms: Bool) {
        self.allowsTerraforms = allowsTerraforms
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              ArtworkAssetPolicy.allowsRemoteURL(url, allowsTerraforms: allowsTerraforms) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
