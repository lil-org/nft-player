import Foundation
@testable import nft_player_ios

nonisolated private final class JavaScriptLibraryFixtureBundleAnchor: NSObject {}

nonisolated enum JavaScriptLibraryFixtures {
    static let cache = makeCache(rootURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("JavaScriptLibraryFixtures-" + UUID().uuidString))

    static func data(for dependency: PersistentArtworkDependency) throws -> Data {
        let bundle = Bundle(for: JavaScriptLibraryFixtureBundleAnchor.self)
        let directory = dependency == .hypertype ? "Hypertype" : "JavaScriptLibraries"
        let filename = dependency.remoteURL.lastPathComponent
        guard let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: directory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func sources() throws -> [Script.Kind: String] {
        try Dictionary(uniqueKeysWithValues: PersistentJavaScriptLibrary.all.map { dependency in
            let name = dependency.remoteURL.deletingPathExtension().lastPathComponent
            guard let kind = Script.Kind(rawValue: name),
                  let source = String(data: try data(for: dependency), encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return (kind, source)
        })
    }

    static func makeCache(rootURL: URL? = nil) -> PersistentArtworkDependencyCache {
        PersistentArtworkDependencyCache(rootURL: rootURL) { url in
            guard let dependency = (PersistentJavaScriptLibrary.all + [.hypertype]).first(where: { $0.remoteURL == url }) else {
                throw URLError(.unsupportedURL)
            }
            return (try data(for: dependency), 200)
        }
    }

    static func seedSharedCache() async throws {
        let cache = makeCache()
        for dependency in PersistentJavaScriptLibrary.all + [.hypertype] {
            _ = try await cache.data(for: dependency)
        }
    }
}
