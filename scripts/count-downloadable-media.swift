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
                guard let source, BundledMediaResolver.resolve(source)?.kind != nil else { return index }
                return nil
            }
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(excludedIndices))
    }
}
