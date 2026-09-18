import CryptoKit
import Foundation
@testable import nft_player_ios

nonisolated private final class JavaScriptLibraryFixtureBundleAnchor: NSObject {}

nonisolated enum JavaScriptLibraryFixtures {
    enum Failure: LocalizedError {
        case missingArtworkFixture(String)

        var errorDescription: String? {
            switch self {
            case .missingArtworkFixture(let filename):
                return "Missing artwork fixture \(filename). Run node scripts/hydrate-artwork-test-sources.mjs, then rebuild the test bundle."
            }
        }
    }

    static let dependencies = PersistentJavaScriptLibrary.all + [.hypertype]
        + SuggestedItemsService.allItems.compactMap(\.scriptDependency)
    static let cache = makeCache(rootURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("JavaScriptLibraryFixtures-" + UUID().uuidString))

    static func data(for dependency: PersistentArtworkDependency) throws -> Data {
        let url: URL
        if dependency.id.hasPrefix("script:") {
            url = try artworkURL(for: dependency)
        } else {
            let directory = dependency == .hypertype ? "Hypertype" : "JavaScriptLibraries"
            guard let resourceURL = Bundle(for: JavaScriptLibraryFixtureBundleAnchor.self).url(
                forResource: dependency.remoteURL.lastPathComponent, withExtension: nil, subdirectory: directory
            ) else { throw CocoaError(.fileNoSuchFile) }
            url = resourceURL
        }
        let data = try Data(contentsOf: url)
        guard data.count == dependency.expectedByteCount else {
            throw PersistentArtworkDependencyCache.Failure.byteCount(expected: dependency.expectedByteCount, actual: data.count)
        }
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == dependency.sha256 else {
            throw PersistentArtworkDependencyCache.Failure.checksum
        }
        return data
    }

    static func scriptURL(collectionId: String) throws -> URL {
        guard let item = SuggestedItemsService.scriptItem(collectionId: collectionId),
              let dependency = item.scriptDependency else { throw CocoaError(.fileNoSuchFile) }
        return try artworkURL(for: dependency)
    }

    private static func artworkURL(for dependency: PersistentArtworkDependency) throws -> URL {
        let slug = String(dependency.id.dropFirst("script:".count))
        guard let fileExtension = SuggestedItemsService.item(resourceName: slug)?.script?.kind.sourceFileExtension else {
            throw PersistentArtworkDependencyCache.Failure.invalidDescriptor
        }
        let filename = dependency.sha256 + "." + fileExtension
        guard let url = Bundle(for: JavaScriptLibraryFixtureBundleAnchor.self).url(
            forResource: filename, withExtension: nil, subdirectory: "ArtworkScripts"
        ) else { throw Failure.missingArtworkFixture(filename) }
        return url
    }

    static func script(collectionId: String) throws -> Script {
        guard let item = SuggestedItemsService.scriptItem(collectionId: collectionId),
              let metadata = item.script else { throw CocoaError(.fileNoSuchFile) }
        let source: String
        if metadata.kind.isNativeRenderer {
            source = ""
        } else {
            guard let dependency = item.scriptDependency,
                  let value = String(data: try data(for: dependency), encoding: .utf8) else {
                throw PersistentArtworkDependencyCache.Failure.invalidUTF8
            }
            source = value
        }
        guard let script = Script(item: item, value: source) else { throw CocoaError(.fileReadCorruptFile) }
        return script
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
            guard let dependency = dependencies.first(where: { $0.remoteURL == url }) else {
                throw URLError(.unsupportedURL)
            }
            return (try data(for: dependency), 200)
        }
    }

}

extension Script {
    func replacing(
        id: String? = nil,
        address: String? = nil,
        name: String? = nil,
        abId: String? = nil,
        chain: Chain? = nil,
        value: String? = nil,
        metadata: Metadata? = nil
    ) -> Script {
        Script(
            id: id ?? self.id,
            address: address ?? self.address,
            name: name ?? self.name,
            abId: abId ?? self.abId,
            chain: chain ?? self.chain,
            chainId: chainId,
            value: value ?? self.value,
            metadata: metadata ?? self.metadata
        )
    }

    func modifyingMetadata(_ update: (inout Metadata) -> Void) -> Script {
        var metadata = metadata
        update(&metadata)
        return replacing(metadata: metadata)
    }
}
