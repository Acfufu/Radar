import Foundation

struct RadarDecimal: Decodable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        let text = try container.decode(String.self)
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal number or decimal string"
            )
        }
        value = decimal
    }
}

struct RadarCommunityDTO: Decodable, Sendable {
    let ok: Bool
    let updatedAt: String?
    let models: [Model]
    let day: String?
    let history: [HistoryDay]?
    let myScores: [String: RadarDecimal]?

    enum CodingKeys: String, CodingKey {
        case ok, models, day, history
        case updatedAt = "updated_at"
        case myScores = "my_scores"
    }

    struct Model: Decodable, Sendable {
        let id: String
        let label: String
        let group: String?
        let average: RadarDecimal?
        let count: Int?
    }

    /// Upstream daily rating snapshot (`history[]`); the 7-day matrix takes
    /// the trailing days and the 24h column uses the current `day` bucket
    /// (spec §5.4). `my_scores` is read-only display data and is never
    /// persisted (D12).
    struct HistoryDay: Decodable, Sendable {
        let day: String?
        let updatedAt: String?
        let models: [Model]?

        enum CodingKeys: String, CodingKey {
            case day, models
            case updatedAt = "updated_at"
        }
    }
}
