import Foundation

struct ClaudeDecimal: Decodable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        let text = try container.decode(String.self)
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a decimal number or decimal string")
        }
        value = decimal
    }
}

struct ClaudeRadarDTO: Decodable, Sendable {
    let ok: Bool
    let updatedAt: String?
    let labels: [String]
    let iq: IQ?
    let quota: Quota?
    let benchmarkDecoded: Bool
    let statusDecoded: Bool

    enum CodingKeys: String, CodingKey {
        case ok, labels, iq, quota
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ok = try values.decode(Bool.self, forKey: .ok)
        updatedAt = try? values.decodeIfPresent(String.self, forKey: .updatedAt)

        let benchmark: (labels: [String], iq: IQ?, decoded: Bool)
        do {
            benchmark = (
                labels: try values.decode([String].self, forKey: .labels),
                iq: try values.decode(IQ.self, forKey: .iq),
                decoded: true
            )
        } catch {
            benchmark = (labels: [], iq: nil, decoded: false)
        }
        labels = benchmark.labels
        iq = benchmark.iq
        benchmarkDecoded = benchmark.decoded

        let status: (quota: Quota?, decoded: Bool)
        do {
            status = (quota: try values.decodeIfPresent(Quota.self, forKey: .quota), decoded: true)
        } catch {
            status = (quota: nil, decoded: false)
        }
        quota = status.quota
        statusDecoded = status.decoded
    }

    struct IQ: Decodable, Sendable {
        let updatedAt: String?
        let models: [Model]

        enum CodingKeys: String, CodingKey {
            case models
            case updatedAt = "updated_at"
        }
    }

    struct Model: Decodable, Sendable {
        let key: String?
        let name: String
        let score: ClaudeDecimal?
        let iq: [ClaudeDecimal?]?
        let passed: [Int?]?
        let valid: [Int?]?
        let invalid: [Int?]?
        let cost: [ClaudeDecimal?]?
        let time: [ClaudeDecimal?]?
        let cache: [ClaudeDecimal?]?
        let latestAt: String?
        let latestLabel: String?

        enum CodingKeys: String, CodingKey {
            case key, name, score, iq, valid, invalid, cost, time, cache
            case passed = "pass"
            case latestAt = "latest_at"
            case latestLabel = "latest_label"
        }
    }

    struct Quota: Decodable, Sendable {
        let updatedAt: String?
        let metrics: [Metric]
        let usage: [Usage]

        enum CodingKeys: String, CodingKey {
            case metrics, usage
            case updatedAt = "updated_at"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
            metrics = try values.decodeIfPresent([Metric].self, forKey: .metrics) ?? []
            usage = try values.decodeIfPresent([Usage].self, forKey: .usage) ?? []
        }
    }

    struct Metric: Decodable, Sendable {
        let key: String
        let label: String?
        let value: ClaudeDecimal?

        enum CodingKeys: String, CodingKey {
            case key, value
            case label = "label_en"
        }
    }

    struct Usage: Decodable, Sendable {
        let key: String
        let usedPercent: ClaudeDecimal?
        let resetDescription: String?

        enum CodingKeys: String, CodingKey {
            case key
            case usedPercent = "used_pct"
            case resetDescription = "reset_text_en"
        }
    }
}

struct ClaudeCommunityDTO: Decodable, Sendable {
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
        let average: ClaudeDecimal?
        let count: Int?
    }
}
