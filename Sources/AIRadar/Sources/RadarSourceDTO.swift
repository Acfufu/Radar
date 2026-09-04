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

    enum CodingKeys: String, CodingKey {
        case ok, models
        case updatedAt = "updated_at"
    }

    struct Model: Decodable, Sendable {
        let id: String
        let label: String
        let average: RadarDecimal?
        let count: Int?
    }
}
