import Foundation

struct PageEnvelope: Codable, Equatable, Sendable {
    let dataset: String
    let schemaVersion: Int
    let page: Int
    let pageSize: Int
    let recordCount: Int
    let totalRecords: Int
    let hasNextPage: Bool
    let records: [ExportRecord]
}

struct ExportRecord: Codable, Equatable, Sendable {
    let fields: [String: ExportJSONValue]

    init(fields: [String: ExportJSONValue]) {
        self.fields = fields
    }

    init(from decoder: Decoder) throws {
        fields = try [String: ExportJSONValue](from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try fields.encode(to: encoder)
    }
}

indirect enum ExportJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([ExportJSONValue])
    case object([String: ExportJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ExportJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: ExportJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

extension JSONEncoder {
    static var export: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var export: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
