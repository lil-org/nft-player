// ∅ 2026 lil org

import Foundation

let appStoreMetadataVersion = ProcessInfo.processInfo.environment["VERSION"] ?? projectMarketingVersion()
let metadataJSONLock = NSLock()

func translateAppStoreMetadata(_ model: AI.Model) {
    var tasks = [MetadataTask]()
    
    for platform in Platform.allCases {
        for metadataKind in MetadataKind.allCases {
            if metadataKind.isCommonForAllPlatforms && platform != .common || !metadataKind.isCommonForAllPlatforms && platform == .common { continue }
            
            let englishText = originalMetadata(kind: metadataKind, platform: platform, language: .english)
            let russianText = originalMetadata(kind: metadataKind, platform: platform, language: .russian)
            write(englishText, englishOriginal: englishText, metadataKind: metadataKind, platform: platform, language: .english)
            write(russianText, englishOriginal: englishText, metadataKind: metadataKind, platform: platform, language: .russian)
            
            if let russianOverrideText = overrideMetadata(kind: metadataKind, platform: platform, language: .russian) {
                write(russianOverrideText, englishOriginal: englishText, metadataKind: metadataKind, platform: platform, language: .russian)
            }
            
            if let englishOverrideText = overrideMetadata(kind: metadataKind, platform: platform, language: .english) {
                write(englishOverrideText, englishOriginal: englishText, metadataKind: metadataKind, platform: platform, language: .english)
            }
            
            let notEmpty = !englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            for language in Language.allCases where language != .english && language != .russian {
                if metadataKind.toTranslate && notEmpty {
                    let task = MetadataTask(model: model, metadataKind: metadataKind, platform: platform, language: language, englishText: englishText, russianText: russianText)
                    if !task.wasCompletedBefore {
                        tasks.append(task)
                    }
                } else {
                    write(englishText, englishOriginal: englishText, metadataKind: metadataKind, platform: platform, language: language)
                }
            }
        }
    }
    
    var finalTasksCount = tasks.count
    for task in tasks {
        AI.translate(task: task) { translation in
            write(translation, englishOriginal: task.englishText, metadataKind: task.metadataKind, platform: task.platform, language: task.language)
            task.storeAsCompleted()
            finalTasksCount -= 1
            if finalTasksCount == 0 {
                semaphore.signal()
            }
        }
    }
    
    if !tasks.isEmpty {
        semaphore.wait()
    }
}

func write(_ newValue: String, englishOriginal: String, metadataKind: MetadataKind, platform: Platform, language: Language) {
    let toWrite: String
    if metadataKind == .subtitle && newValue.count > 30 {
        toWrite = englishOriginal
    } else if metadataKind == .keywords && newValue.count > 100 {
        toWrite = englishOriginal
    } else {
        toWrite = newValue
    }
    
    let actualPlatformsToWrite = platform == .common ? Platform.allCases.filter { $0 != .common } : [platform]
    for p in actualPlatformsToWrite {
        let url = metadataURL(kind: metadataKind, platform: p, language: language)
        updateMetadataJSON(at: url, metadataKind: metadataKind, value: toWrite)
    }
}

func originalMetadata(kind: MetadataKind, platform: Platform, language: Language) -> String {
    let metadata = readMetadataJSON(at: metadataURL(kind: kind, platform: metadataSourcePlatform(platform), language: language))
    return (metadata[kind.jsonFieldName] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

func overrideMetadata(kind: MetadataKind, platform: Platform, language: Language) -> String? {
    let url = URL(fileURLWithPath: projectDir + "/app_store/overrides/\(metadataSourcePlatform(platform).rawValue)/\(language.metadataLocalizationKey)/\(kind.fileName).txt")
    if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        return nil
    }
}

func metadataURL(kind: MetadataKind, platform: Platform, language: Language) -> URL {
    let locale = language.metadataLocalizationKey
    let directory = kind.metadataDirectory
    let basePath = projectDir + "/app_store/metadata/\(platform.rawValue)/\(directory.rawValue)"
    if directory == .version {
        return URL(fileURLWithPath: basePath + "/\(appStoreMetadataVersion)/\(locale).json")
    } else {
        return URL(fileURLWithPath: basePath + "/\(locale).json")
    }
}

func metadataSourcePlatform(_ platform: Platform) -> Platform {
    platform == .common ? .ios : platform
}

func updateMetadataJSON(at url: URL, metadataKind: MetadataKind, value: String) {
    metadataJSONLock.lock()
    defer { metadataJSONLock.unlock() }

    var metadata = readMetadataJSON(at: url)
    metadata[metadataKind.jsonFieldName] = value
    writeMetadataJSON(metadata, to: url)
}

func readMetadataJSON(at url: URL) -> [String: String] {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else {
        return [:]
    }
    let object = try! JSONSerialization.jsonObject(with: data)
    guard let metadata = object as? [String: String] else {
        fatalError("Metadata JSON must be a string dictionary: \(url.path)")
    }
    return metadata
}

func writeMetadataJSON(_ metadata: [String: String], to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try! (data + Data("\n".utf8)).write(to: url)
}

func projectMarketingVersion() -> String {
    let projectFile = projectDir + "/nft-folder.xcodeproj/project.pbxproj"
    let text = try! String(contentsOfFile: projectFile, encoding: .utf8)
    let regex = try! NSRegularExpression(pattern: #"MARKETING_VERSION = ([^;]+);"#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let match = regex.firstMatch(in: text, range: range)!
    let versionRange = Range(match.range(at: 1), in: text)!
    return String(text[versionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
}
