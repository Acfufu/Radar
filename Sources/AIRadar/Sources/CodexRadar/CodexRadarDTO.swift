import Foundation

struct CodexRadarDTO: Decodable, Sendable {
    let schemaVersion: String
    let monitoredAt: String?
    let modelIQ: ModelIQ

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case monitoredAt = "monitored_at"
        case modelIQ = "model_iq"
    }

    struct ModelIQ: Decodable, Sendable {
        let latest: Run?
        let comparisons: [String: Comparison]
        let quotaRadar: QuotaRadar?

        enum CodingKeys: String, CodingKey {
            case latest, comparisons
            case quotaRadar = "quota_radar"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            latest = try values.decodeIfPresent(Run.self, forKey: .latest)
            comparisons = try values.decodeIfPresent([String: Comparison].self, forKey: .comparisons) ?? [:]
            quotaRadar = try values.decodeIfPresent(QuotaRadar.self, forKey: .quotaRadar)
        }
    }

    struct Comparison: Decodable, Sendable {
        let label: String
        let model: String
        let reasoningEffort: String
        let latest: Run

        enum CodingKeys: String, CodingKey {
            case label, model, latest
            case reasoningEffort = "reasoning_effort"
        }
    }

    struct Run: Decodable, Sendable {
        let score: RadarDecimal?
        let passed: Int?
        let tasks: Int?
        let invalid: Int?
        let totalTokens: Int64?
        let inputTokens: Int64?
        let cachedInputTokens: Int64?
        let outputTokens: Int64?
        let wallSeconds: Double?
        let model: String?
        let reasoningEffort: String?
        let validTasks: Int?
        let costUSD: RadarDecimal?

        enum CodingKeys: String, CodingKey {
            case score, passed, tasks, invalid, model
            case totalTokens = "total_tokens"
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case wallSeconds = "wall_seconds"
            case reasoningEffort = "reasoning_effort"
            case validTasks = "valid_tasks"
            case costUSD = "cost_usd"
        }
    }

    struct QuotaRadar: Decodable, Sendable {
        let updatedAt: String?
        let basisWindowLabel: String?
        let rows: [QuotaRow]

        enum CodingKeys: String, CodingKey {
            case rows
            case updatedAt = "updated_at"
            case basisWindowLabel = "basis_window_label"
        }
    }

    struct QuotaRow: Decodable, Sendable {
        let tier: String
        let basis: String?
        let fiveHour: RadarDecimal?
        let sevenDay: RadarDecimal?

        enum CodingKeys: String, CodingKey {
            case tier, basis
            case fiveHour = "five_h"
            case sevenDay = "seven_d"
        }
    }
}
