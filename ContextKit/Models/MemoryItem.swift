import Foundation

struct MemoryItem: Identifiable, Decodable, Hashable {
    let id: String
    let collection: String
    let text: String
    let timestamp: String
    let metadata: [String: MetadataValue]

    var summary: String {
        if case .string(let value) = metadata["summary"], !value.isEmpty {
            return value
        }
        return String(text.prefix(160))
    }

    var source: String {
        if case .string(let value) = metadata["source"] { return value }
        return "unknown"
    }
}

enum MetadataValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        self = .null
    }

    var displayString: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return ""
        }
    }
}
