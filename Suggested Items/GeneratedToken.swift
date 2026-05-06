// ∅ 2026 lil org

import Foundation

struct GeneratedToken: Hashable, Codable, Identifiable {
    let fullCollectionId: String
    let collectionName: String
    let address: String
    let id: String
    let html: String
    let displayName: String
    let displayTokenId: String
    let url: URL?
    let instructions: String?
    let screensaver: URL?
    
    static let empty = GeneratedToken(fullCollectionId: "", collectionName: "", address: "", id: "", html: "", displayName: "", displayTokenId: "", url: nil, instructions: nil, screensaver: nil)
}
