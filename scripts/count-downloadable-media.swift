import Foundation

let extensions: Set<String> = [
    "png", "jpg", "jpeg", "webp", "heic", "heif", "tiff", "gif", "svg",
    "mp4", "mov", "html", "htm", "xhtml"
]
let groups = try JSONDecoder().decode(
    [[String?]].self,
    from: FileHandle.standardInput.readDataToEndOfFile()
)
let counts = groups.map { sources in
    sources.filter { source in
        guard let source, let url = URL(string: source) else { return false }
        let rawExtension = url.pathExtension.isEmpty
            ? URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "ext" }?.value
            : url.pathExtension
        guard let rawExtension else { return false }
        let fileExtension = rawExtension.trimmingCharacters(
            in: CharacterSet(charactersIn: ". \n\t\r")
        ).lowercased()
        return extensions.contains(fileExtension)
    }.count
}
FileHandle.standardOutput.write(try JSONEncoder().encode(counts))
