// ∅ 2026 lil org

import Foundation

struct MetadataTask: AI.Task {
    
    let model: AI.Model
    let metadataKind: MetadataKind
    let platform: Platform
    let language: Language
    let englishText: String
    let russianText: String
    
    var description: String {
        return "\(language.name) \(metadataKind.fileName) \(platform.rawValue)"
    }
    
    var prompt: String {
        let metadataName: String
        let clarifications: String
        let finalWarning: String
        
        switch metadataKind {
        case .subtitle:
            finalWarning = """
            your response should be max 30 symbols.
            
            if it does not fit, rewrite it to make sure it fits 30 symbols.
            
            find a way to communicate the same meaning while fitting in 30 chars. do not say "HD".
            """
        default:
            finalWarning = ""
        }
        
        switch metadataKind {
        case .description:
            metadataName = "app description"
        case .keywords:
            metadataName = "app store keywords"
        case .name:
            metadataName = "app name"
        case .subtitle:
            metadataName = "app store page subtitle"
        case .promotionalText:
            metadataName = "app store promotional text"
        case .releaseNotes:
            metadataName = "app release notes"
        default:
            metadataName = "text"
        }
        
        switch metadataKind {
        case .name:
            clarifications = """
            i prefer NFT to be spelled as Nft (in russian: Нфт). use a similar capitalization style when transliterating.
            """
        case .subtitle:
            clarifications = """
            feel free to tune it to make \(language.name) version sound natural.
            """
        case .keywords:
            clarifications = """
            separate keywords with an english comma.
            
            do not add whitespaces after comma — in order to fit more keywords in.
            
            feel free to change and reorder the words used.
            
            your response should be good to be used as app store keywords.
            
            make sure your response fits in 100 chars.
            """
        default:
            clarifications = """
            feel free to tune it to make \(language.name) version sound natural.
            
            keep formatting, capitalization, and punctuation style as close to the original as possible.
            """
        }
        
        let output = """
        help me localize the \(metadataName).
        
        i need that in \(language.name). use both english and russian versions below as a reference.
        
        english:
        "\(englishText)"
        
        russian:
        "\(russianText)"
        
        \(clarifications)
        
        keep it simple and straightforward.
        
        respond only with a \(language.name) version. do not add anything else to the response.
        
        do not surround the response with quotation marks.
        
        \(finalWarning)
        """
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var wasCompletedBefore: Bool {
        if let data = try? Data(contentsOf: hashURL),
           let text = String(data: data, encoding: .utf8) {
            return hash == text
        } else {
            return false
        }
    }
    
    func storeAsCompleted() {
        let data = hash.data(using: .utf8)!
        try! data.write(to: hashURL)
    }
    
    private var hashURL: URL {
        return URL(fileURLWithPath: projectDir + "/translate/latest/" + "\(language.metadataLocalizationKey)-\(metadataKind.fileName)-\(platform.rawValue)")
    }
    
}
