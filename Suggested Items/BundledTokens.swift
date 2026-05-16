// ∅ 2026 lil org

import Foundation

struct BundledTokens: Codable {
    
    struct Item: Codable {
        let id: String
        let name: String?
        let url: String?
        let sh: String?
        let hash: String?
    }

    private struct CompactItem: Decodable {
        let id: String
        let prefixIndex: Int
        let urlSuffix: String

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            id = try container.decode(String.self)
            prefixIndex = try container.decode(Int.self)
            urlSuffix = try container.decode(String.self)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isComplete
        case items
        case urlPrefixes
    }
    
    let isComplete: Bool
    let items: [Item]

    init(isComplete: Bool, items: [Item]) {
        self.isComplete = isComplete
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true

        if let objectItems = try? container.decode([Item].self, forKey: .items) {
            items = objectItems
            return
        }

        let urlPrefixes = try container.decodeIfPresent([String].self, forKey: .urlPrefixes) ?? []
        items = try container.decode([CompactItem].self, forKey: .items).map { compactItem in
            let url: String
            if urlPrefixes.indices.contains(compactItem.prefixIndex) {
                url = urlPrefixes[compactItem.prefixIndex] + compactItem.urlSuffix
            } else {
                url = compactItem.urlSuffix
            }
            return Item(id: compactItem.id, name: nil, url: url, sh: nil, hash: nil)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(items, forKey: .items)
    }
    
}
