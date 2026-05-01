// ∅ 2026 lil org

import Foundation

enum MetadataKind: String, CaseIterable {
    case description
    case keywords
    case name
    case subtitle
    case promotionalText = "promotional_text"
    case releaseNotes = "release_notes"
    case marketingURL = "marketing_url"
    case privacyURL = "privacy_url"
    case supportURL = "support_url"
    case appleTvPrivacyPolicy = "apple_tv_privacy_policy"

    var fileName: String {
        return rawValue
    }

    var jsonFieldName: String {
        switch self {
        case .description:
            return "description"
        case .keywords:
            return "keywords"
        case .name:
            return "name"
        case .subtitle:
            return "subtitle"
        case .promotionalText:
            return "promotionalText"
        case .releaseNotes:
            return "whatsNew"
        case .marketingURL:
            return "marketingUrl"
        case .privacyURL:
            return "privacyPolicyUrl"
        case .supportURL:
            return "supportUrl"
        case .appleTvPrivacyPolicy:
            return "privacyPolicyText"
        }
    }

    var metadataDirectory: MetadataDirectory {
        switch self {
        case .name, .subtitle, .privacyURL, .appleTvPrivacyPolicy:
            return .appInfo
        case .description, .keywords, .promotionalText, .releaseNotes, .marketingURL, .supportURL:
            return .version
        }
    }

    var toTranslate: Bool {
        switch self {
        case .description, .keywords, .subtitle, .promotionalText, .releaseNotes, .name:
            return true
        case .marketingURL, .privacyURL, .supportURL, .appleTvPrivacyPolicy:
            return false
        }
    }

    var isCommonForAllPlatforms: Bool {
        switch self {
        case .description, .releaseNotes, .keywords, .promotionalText:
            return false
        case .marketingURL, .privacyURL, .supportURL, .appleTvPrivacyPolicy, .name, .subtitle:
            return true
        }
    }
    
}

enum MetadataDirectory: String {
    case appInfo = "app-info"
    case version = "versions"
}
