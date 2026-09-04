import Foundation

struct CodexRadarDTO: Decodable, Sendable {
    let schemaVersion: String
    let monitoredAt: String?
    let timezone: String?
    let windowOpen: Bool?
    let status: String?
    let recommendedAction: String?
    let window: WindowInfo?
    let prediction: Prediction?
    let tiboPresence: TiboPresence?
    let modelIQ: ModelIQ

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case monitoredAt = "monitored_at"
        case timezone
        case windowOpen = "window_open"
        case status
        case recommendedAction = "recommended_action"
        case window
        case prediction
        case tiboPresence = "tibo_presence"
        case modelIQ = "model_iq"
    }

    struct WindowInfo: Decodable, Sendable {
        let isOpen: Bool?
        let status: String?
        let action: String?
        let message: String?
        let title: String?
        let scope: String?
        let openedAt: String?
        let closedAt: String?
        let sourceURL: String?

        enum CodingKeys: String, CodingKey {
            case isOpen = "open"
            case status, action, message, title, scope
            case openedAt = "opened_at"
            case closedAt = "closed_at"
            case sourceURL = "source_url"
        }
    }

    struct Prediction: Decodable, Sendable {
        let level: String?
        let probability24h: Double?
        let probability48h: Double?
        let summary: String?
        let summaryEN: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case level, summary
            case probability24h = "probability_24h"
            case probability48h = "probability_48h"
            case summaryEN = "summary_en"
            case updatedAt = "updated_at"
        }
    }

    struct TiboPresence: Decodable, Sendable {
        let timezone: String?
        let locationLabelZH: String?
        let locationLabelEN: String?
        let probability: Double?
        let confidence: String?
        let evidenceSummaryZH: String?
        let evidenceSummaryEN: String?
        let sourceURLs: [String]?
        let shouldDisplay: Bool?
        let safetyNoteZH: String?
        let safetyNoteEN: String?
        let observedAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case timezone, probability, confidence
            case locationLabelZH = "location_label_zh"
            case locationLabelEN = "location_label_en"
            case evidenceSummaryZH = "evidence_summary_zh"
            case evidenceSummaryEN = "evidence_summary_en"
            case sourceURLs = "source_urls"
            case shouldDisplay = "should_display"
            case safetyNoteZH = "safety_note_zh"
            case safetyNoteEN = "safety_note_en"
            case observedAt = "observed_at"
            case updatedAt = "updated_at"
        }
    }

    struct DataSource: Decodable, Sendable {
        let type: String?
        let url: String?
        let selection: String?
        let checkedAt: String?
        let validCells: Int?

        enum CodingKeys: String, CodingKey {
            case type, url, selection
            case checkedAt = "checked_at"
            case validCells = "valid_cells"
        }
    }

    struct QuotaCalibration: Decodable, Sendable {
        let date: String?
        let status: String?
        let primaryWindow: String?
        let globalConcurrency: Int?
        let checkedAt: String?

        enum CodingKeys: String, CodingKey {
            case date, status
            case primaryWindow = "primary_window"
            case globalConcurrency = "global_concurrency"
            case checkedAt = "checked_at"
        }
    }

    struct QuotaCheck: Decodable, Sendable {
        let planType: String?
        let creditsAvailable: Int?
        let limitReached: Bool?
        let allowed: Bool?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case creditsAvailable = "rate_limit_reset_credits_available_count"
            case limitReached = "limit_reached"
            case allowed
        }
    }

    struct ModelIQ: Decodable, Sendable {
        let latest: Run?
        let comparisons: [String: Comparison]
        let quotaRadar: QuotaRadar?
        let dataSource: DataSource?
        let quotaCalibration: QuotaCalibration?
        let quotaCheck: QuotaCheck?

        enum CodingKeys: String, CodingKey {
            case latest, comparisons
            case quotaRadar = "quota_radar"
            case dataSource = "data_source"
            case quotaCalibration = "quota_calibration"
            case quotaCheck = "quota_check"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            latest = try values.decodeIfPresent(Run.self, forKey: .latest)
            comparisons = try values.decodeIfPresent([String: Comparison].self, forKey: .comparisons) ?? [:]
            quotaRadar = try values.decodeIfPresent(QuotaRadar.self, forKey: .quotaRadar)
            dataSource = try values.decodeIfPresent(DataSource.self, forKey: .dataSource)
            quotaCalibration = try values.decodeIfPresent(QuotaCalibration.self, forKey: .quotaCalibration)
            quotaCheck = try values.decodeIfPresent(QuotaCheck.self, forKey: .quotaCheck)
        }
    }

    struct Comparison: Decodable, Sendable {
        let label: String
        let model: String
        let reasoningEffort: String
        let latest: Run
        let recentDays: [Run]?

        enum CodingKeys: String, CodingKey {
            case label, model, latest
            case reasoningEffort = "reasoning_effort"
            case recentDays = "recent_days"
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
        let wallTimeHuman: String?
        let averageCostUSD: RadarDecimal?
        let averageTaskSeconds: Double?
        let averageTaskTimeHuman: String?
        let costUSDBasis: String?

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
            case wallTimeHuman = "wall_time_human"
            case averageCostUSD = "average_cost_usd"
            case averageTaskSeconds = "average_task_seconds"
            case averageTaskTimeHuman = "average_task_time_human"
            case costUSDBasis = "cost_usd_basis"
        }
    }

    struct QuotaRadar: Decodable, Sendable {
        let updatedAt: String?
        let basisWindowLabel: String?
        let rows: [QuotaRow]
        let trend: [TrendPoint]?

        enum CodingKeys: String, CodingKey {
            case rows, trend
            case updatedAt = "updated_at"
            case basisWindowLabel = "basis_window_label"
        }
    }

    struct TrendPoint: Decodable, Sendable {
        let date: String?
        let fiveH5x: RadarDecimal?
        let fiveH20x: RadarDecimal?
        let fiveHPlus: RadarDecimal?
        let rate: RadarDecimal?
        let offset: RadarDecimal?

        enum CodingKeys: String, CodingKey {
            case date, rate, offset
            case fiveH5x = "five_h_5x"
            case fiveH20x = "five_h_20x"
            case fiveHPlus = "five_h_plus"
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
