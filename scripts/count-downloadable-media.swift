import Foundation

@main
enum DownloadableMediaIndices {
    static func main() throws {
        let groups = try JSONDecoder().decode(
            [[String?]].self,
            from: FileHandle.standardInput.readDataToEndOfFile()
        )
        let excludedIndices = groups.map { sources in
            sources.enumerated().compactMap { index, source -> Int? in
                guard let source,
                      let media = BundledMediaResolver.resolve(source),
                      media.kind != nil,
                      ArtworkAssetPolicy.allowsRemoteURL(media.url, allowsTerraforms: true) else {
                    return index
                }
                return nil
            }
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(excludedIndices))
    }
}
