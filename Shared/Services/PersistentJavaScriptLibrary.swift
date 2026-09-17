import Foundation

nonisolated enum PersistentJavaScriptLibrary {
    enum ReferenceFormat: CaseIterable, Sendable {
        case inline, escapedInline, dataURL
    }

    static let all: [PersistentArtworkDependency] = [
        PersistentArtworkDependency(
            id: "library:p5js100",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/p5js100.js")!,
            expectedByteCount: 623_013,
            sha256: "3e0d5d8be7c1179dd16e1f68651fc5783d71b05cd32c2f7ade571a7350f489ab"
        ),
        PersistentArtworkDependency(
            id: "library:p5js11111",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/p5js11111.js")!,
            expectedByteCount: 1_057_680,
            sha256: "1343f616bf9914da8253faae00201ea5f72772916998bc6add4c2a07e00a662c"
        ),
        PersistentArtworkDependency(
            id: "library:p5js190",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/p5js190.js")!,
            expectedByteCount: 1_029_097,
            sha256: "726ac96626b93f5bcaff83a910b6c60d3a9728f063e0eb73b5d0819ffc356915"
        ),
        PersistentArtworkDependency(
            id: "library:paper",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/paper.js")!,
            expectedByteCount: 235_545,
            sha256: "7cef19f56270df49c30d5c6246f3806e3990d847ff9e3b6f9cdf1e4db72d16e9"
        ),
        PersistentArtworkDependency(
            id: "library:processingjs146",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/processingjs146.js")!,
            expectedByteCount: 224_507,
            sha256: "5fe82ab91f2aa66bc7c736e4a5b50981b9e694318472217457b1b2acead6b1f6"
        ),
        PersistentArtworkDependency(
            id: "library:regl",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/regl.js")!,
            expectedByteCount: 86_891,
            sha256: "1e85c84ef254125921378d82f4da4e457a0a399bc315880c8c997dd5af8c534d"
        ),
        PersistentArtworkDependency(
            id: "library:three",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/three.js")!,
            expectedByteCount: 653_449,
            sha256: "a8a966c3de0bac23630957e8b6ceb1330725bc2889a0b2dad952d710797ba179"
        ),
        PersistentArtworkDependency(
            id: "library:three167",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/three167.js")!,
            expectedByteCount: 684_042,
            sha256: "54a7a52ddce0ad06fbd1d021fd03b1e1812d946114a2111e1260bcd490c6b840"
        ),
        PersistentArtworkDependency(
            id: "library:tone",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/tone.js")!,
            expectedByteCount: 349_761,
            sha256: "4d7c4cf19549784271e12048a2492326cfddd1f1f769b8e414f683f409d33890"
        ),
        PersistentArtworkDependency(
            id: "library:tone1504",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/tone1504.js")!,
            expectedByteCount: 345_744,
            sha256: "33c3fdc2f26f66f203631deb2c51a5ade54cdffb8271d2d98106c295de89bc0d"
        ),
        PersistentArtworkDependency(
            id: "library:twemoji",
            remoteURL: URL(string: "https://cdn.lil.org/player/lib/twemoji.js")!,
            expectedByteCount: 17_437,
            sha256: "706224d8dc5440460f8ed91c1a6aad25d732af6e0ee6fb31151b157ab485babb"
        )
    ]

    static let hypertypeReference = "nft-player-dependency:hypertype:" + PersistentArtworkDependency.hypertype.sha256

    private struct Reference {
        let dependency: PersistentArtworkDependency
        let format: ReferenceFormat
        let text: String
        let prefixOffset: Int
        let length: Int

        init(dependency: PersistentArtworkDependency, format: ReferenceFormat, text: String) {
            self.dependency = dependency
            self.format = format
            self.text = text
            prefixOffset = text.hasPrefix("/*") ? 2 : 0
            length = text.utf8.count
        }
    }

    private struct Occurrence {
        let reference: Reference
        let range: NSRange
    }

    private static let librariesByName = Dictionary(uniqueKeysWithValues: all.map {
        (String($0.id.dropFirst("library:".count)), $0)
    })

    private static let references = all.flatMap { dependency in
        ReferenceFormat.allCases.map { format in
            Reference(dependency: dependency, format: format, text: reference(for: dependency, format: format))
        }
    } + [Reference(dependency: .hypertype, format: .dataURL, text: hypertypeReference)]

    private static let dataURLReferencesByInlineReference = Dictionary(uniqueKeysWithValues: all.map {
        (reference(for: $0), reference(for: $0, format: .dataURL))
    })

    static func library(named name: String) -> PersistentArtworkDependency? {
        let name = name.hasSuffix(".js") ? String(name.dropLast(3)) : name
        return librariesByName[name]
    }

    static func reference(for dependency: PersistentArtworkDependency, format: ReferenceFormat = .inline) -> String {
        if dependency == .hypertype { return hypertypeReference }
        let identity = dependency.id + ":" + dependency.sha256
        switch format {
        case .inline: return "/*nft-player-library:" + identity + ":inline*/"
        case .escapedInline: return "/*nft-player-library:" + identity + ":escaped-inline*/"
        case .dataURL: return "nft-player-library:" + identity + ":data-url"
        }
    }

    static func dataURLReference(forInlineReference reference: String) -> String? {
        dataURLReferencesByInlineReference[reference]
    }

    private static func occurrences(in document: NSString, firstOnly: Bool) -> [Occurrence] {
        let length = document.length
        var search = NSRange(location: 0, length: length)
        var prefix = document.range(of: "nft-player-", options: .literal, range: search)
        guard prefix.location != NSNotFound else { return [] }
        var found: [Occurrence] = []
        var seen: Set<String> = []
        while prefix.location != NSNotFound {
            for reference in references where !firstOnly || !seen.contains(reference.text) {
                let start = prefix.location - reference.prefixOffset
                guard start >= 0, start + reference.length <= length else { continue }
                let window = NSRange(location: start, length: reference.length)
                let range = document.range(of: reference.text, options: .literal, range: window)
                guard range.location != NSNotFound else { continue }
                found.append(Occurrence(reference: reference, range: range))
                seen.insert(reference.text)
            }
            let next = NSMaxRange(prefix)
            search = NSRange(location: next, length: length - next)
            prefix = document.range(of: "nft-player-", options: .literal, range: search)
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    private static func dependencies(in occurrences: [Occurrence]) -> [PersistentArtworkDependency] {
        var seen: Set<PersistentArtworkDependency> = []
        return occurrences.compactMap { occurrence in
            seen.insert(occurrence.reference.dependency).inserted ? occurrence.reference.dependency : nil
        }
    }

    static func requiredDependencies(in html: String) -> [PersistentArtworkDependency] {
        dependencies(in: occurrences(in: html as NSString, firstOnly: true))
    }

    @concurrent
    static func resolve(
        _ html: String,
        cache: PersistentArtworkDependencyCache = .shared,
        allowsDownloads: Bool = true
    ) async throws -> String {
        let occurrences = occurrences(in: html as NSString, firstOnly: false)
        let dependencies = dependencies(in: occurrences)
        guard !dependencies.isEmpty else { return html }
        let bytes = try await withThrowingTaskGroup(of: (PersistentArtworkDependency, Data).self) { group in
            for dependency in dependencies {
                group.addTask {
                    if allowsDownloads { return (dependency, try await cache.data(for: dependency)) }
                    guard let data = try await cache.cachedData(for: dependency) else {
                        throw PersistentArtworkDependencyCache.Failure.notCached
                    }
                    return (dependency, data)
                }
            }
            var result: [PersistentArtworkDependency: Data] = [:]
            for try await (dependency, data) in group { result[dependency] = data }
            return result
        }
        try Task.checkCancellation()
        var replacements: [String: String] = [:]
        for occurrence in occurrences where replacements[occurrence.reference.text] == nil {
            let reference = occurrence.reference
            guard let data = bytes[reference.dependency], let source = String(data: data, encoding: .utf8) else {
                throw PersistentArtworkDependencyCache.Failure.invalidUTF8
            }
            switch reference.format {
            case .inline:
                replacements[reference.text] = source
            case .escapedInline:
                replacements[reference.text] = (source as NSString).replacingOccurrences(
                    of: "</script", with: "<\\/script", options: .literal,
                    range: NSRange(location: 0, length: (source as NSString).length)
                )
            case .dataURL:
                replacements[reference.text] = "data:text/javascript;base64," + data.base64EncodedString()
            }
        }
        let result = NSMutableString(string: html)
        for occurrence in occurrences.reversed() {
            if let replacement = replacements[occurrence.reference.text] {
                result.replaceCharacters(in: occurrence.range, with: replacement)
            }
        }
        return result as String
    }
}
