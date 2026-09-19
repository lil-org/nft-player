import Foundation

nonisolated struct CompactTokenManifest {
    enum CodingKeys: String, CodingKey {
        case version, count, firstId, ids, items
        case name, hash, urlSuffix, aspectRatio, contractParameters
        case urlTemplate, excludedMediaIndices
    }

    enum Column: String, CaseIterable {
        case name, hash, urlSuffix, aspectRatio, contractParameters

        var codingKey: CodingKeys { CodingKeys(rawValue: rawValue)! }
    }

    struct URLTemplate: Codable {
        enum Value: String, Codable {
            case id, index0, index1
        }

        let value: Value
        let suffix: String

        func resolve(id: String, index: Int) -> String {
            switch value {
            case .id: id + suffix
            case .index0: String(index) + suffix
            case .index1: String(index + 1) + suffix
            }
        }
    }

    let count: Int
    let excludedMediaIndices: [Int]
    private let firstId: Int64?
    private let ids: [String]?
    private let urlSuffixes: [String?]?
    private let urlTemplate: URLTemplate?
    private let container: KeyedDecodingContainer<CodingKeys>

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.container = container
        guard try container.decode(Int.self, forKey: .version) == 2 else {
            throw Self.invalid(.version, in: container, "Unsupported token manifest version")
        }
        guard !container.contains(.items) else {
            throw Self.invalid(.items, in: container, "Legacy items cannot be combined with compact token columns")
        }
        let count = try container.decode(Int.self, forKey: .count)
        guard count >= 0 else {
            throw Self.invalid(.count, in: container, "Token count must be nonnegative")
        }
        self.count = count
        guard container.contains(.firstId) != container.contains(.ids) else {
            throw Self.invalid(.ids, in: container, "Provide exactly one of firstId and ids")
        }
        if container.contains(.firstId) {
            let value = try container.decode(String.self, forKey: .firstId)
            guard let firstId = Self.rangeStart(value),
                  count == 0 || !firstId.addingReportingOverflow(Int64(count - 1)).overflow else {
                throw Self.invalid(.firstId, in: container, "ID range must contain canonical nonnegative Int64 values")
            }
            self.firstId = firstId
            ids = nil
        } else {
            let ids = try container.decode([String].self, forKey: .ids)
            guard ids.count == count, ids.allSatisfy({ !$0.isEmpty }) else {
                throw Self.invalid(.ids, in: container, "IDs must be nonempty and match token count")
            }
            self.ids = ids
            firstId = nil
        }
        for column in Column.allCases where container.contains(column.codingKey) {
            let values = try container.nestedUnkeyedContainer(forKey: column.codingKey)
            guard values.count == count else {
                throw Self.invalid(column.codingKey, in: container, "Column length does not match token count")
            }
        }
        guard !container.contains(.urlTemplate) || !container.contains(.urlSuffix) else {
            throw Self.invalid(.urlTemplate, in: container, "URL templates and URL suffix columns are mutually exclusive")
        }
        urlTemplate = container.contains(.urlTemplate)
            ? try container.decode(URLTemplate.self, forKey: .urlTemplate)
            : nil
        urlSuffixes = container.contains(.urlSuffix)
            ? try container.decode([String?].self, forKey: .urlSuffix)
            : nil
        let exclusions = container.contains(.excludedMediaIndices)
            ? try container.decode([Int].self, forKey: .excludedMediaIndices)
            : []
        var previous = -1
        for index in exclusions {
            guard index > previous, index < count else {
                throw Self.invalid(.excludedMediaIndices, in: container, "Excluded media indices must be sorted, unique, and within the manifest")
            }
            previous = index
        }
        excludedMediaIndices = exclusions
    }

    func id(at index: Int) -> String {
        if let firstId { return String(firstId + Int64(index)) }
        return ids![index]
    }

    func urlSuffix(at index: Int, id: String) -> String? {
        if let urlTemplate { return urlTemplate.resolve(id: id, index: index) }
        return urlSuffixes?[index]
    }

    func decodeColumn<T: Decodable>(_ type: T.Type, forKey column: Column) throws -> [T?]? {
        guard container.contains(column.codingKey) else { return nil }
        return try container.decode([T?].self, forKey: column.codingKey)
    }

    static func rangeStart(_ value: String) -> Int64? {
        guard !value.isEmpty,
              value == "0" || value.first != "0",
              value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let result = Int64(value) else { return nil }
        return result
    }

    private static func invalid(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        _ description: String
    ) -> DecodingError {
        .dataCorruptedError(forKey: key, in: container, debugDescription: description)
    }
}
