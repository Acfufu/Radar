import Foundation

/// Upstream intelligence-efficiency dataset (spec §5.2), normalized from the
/// public `codexradar.com/data/intelligence-efficiency.json` payload. The
/// name carries the `Dataset` suffix because `DerivedMetrics.swift` already
/// owns the local-fit `IntelligenceEfficiency` analysis types; nothing here
/// collides with them.
///
/// All upstream fields stay optional so drift decodes tolerantly; the
/// `source`/`metricsSource` provenance strings point at the protected
/// upstream API domain and are kept for attribution only — Radar never
/// requests that host (spec §5.0). The nested value types double as the
/// tolerant wire types for the sidecar payload.
struct IntelligenceEfficiencyDataset: Codable, Hashable, Sendable {
    let sourceID: RadarSourceID
    let fetchedAt: Date
    let schema: Int?
    let mode: String?
    let type: String?
    let source: String?
    let metricsSource: String?
    let sourceUpdatedAt: String?
    let models: Int?
    let runs24hTotal: Int?
    let runs48hTotal: Int?
    let runsTotal: Int?
    let points: [Point]
    let history: [HistoryEntry]
    let fingerprint: String?
    let activityFingerprint: String?
    let method: Method?

    init(
        sourceID: RadarSourceID,
        fetchedAt: Date,
        schema: Int? = nil,
        mode: String? = nil,
        type: String? = nil,
        source: String? = nil,
        metricsSource: String? = nil,
        sourceUpdatedAt: String? = nil,
        models: Int? = nil,
        runs24hTotal: Int? = nil,
        runs48hTotal: Int? = nil,
        runsTotal: Int? = nil,
        points: [Point] = [],
        history: [HistoryEntry] = [],
        fingerprint: String? = nil,
        activityFingerprint: String? = nil,
        method: Method? = nil
    ) {
        self.sourceID = sourceID
        self.fetchedAt = fetchedAt
        self.schema = schema
        self.mode = mode
        self.type = type
        self.source = source
        self.metricsSource = metricsSource
        self.sourceUpdatedAt = sourceUpdatedAt
        self.models = models
        self.runs24hTotal = runs24hTotal
        self.runs48hTotal = runs48hTotal
        self.runsTotal = runsTotal
        self.points = points
        self.history = history
        self.fingerprint = fingerprint
        self.activityFingerprint = activityFingerprint
        self.method = method
    }

    enum CodingKeys: String, CodingKey {
        case sourceID, fetchedAt, schema, mode, type, source, models, points, history
        case metricsSource = "metricsSource"
        case sourceUpdatedAt = "sourceUpdatedAt"
        case runs24hTotal = "runs24hTotal"
        case runs48hTotal = "runs48hTotal"
        case runsTotal = "runsTotal"
        case fingerprint, activityFingerprint, method
    }

    /// One current ranking row (upstream `points[]`); payload order is the
    /// upstream ranking order and is preserved verbatim.
    struct Point: Codable, Hashable, Sendable {
        let model: String?
        let effort: String?
        let harness: String?
        let iq: Double?
        let passed: Double?
        let validTasks: Double?
        let averagePriceUSD: Decimal?
        let priceSamples: Int?
        let averageMinutes: Double?
        let durationSamples: Int?
        let incompleteCostSamples: Int?
        let totalRuns: Int?
        let latestGradedAt: String?
        let averageAgentSteps: Double?
        let agentStepsSamples: Int?
        let averageTotalTokens: Double?
        let tokenSamples: Int?
        let cacheHitRate: Double?
        let cacheTokenSamples: Int?
        let averagePriceUSDBand: PriceBand?
        let runs24h: Int?
        let runs48h: Int?
        let runsTotal: Int?
        let rawCombinedCost: Decimal?
        let combinedCostIndex: Double?

        /// Explicit all-default init so tests and seeds can construct partial
        /// rows (the synthesized memberwise init has no defaults for `let`).
        init(
            model: String? = nil,
            effort: String? = nil,
            harness: String? = nil,
            iq: Double? = nil,
            passed: Double? = nil,
            validTasks: Double? = nil,
            averagePriceUSD: Decimal? = nil,
            priceSamples: Int? = nil,
            averageMinutes: Double? = nil,
            durationSamples: Int? = nil,
            incompleteCostSamples: Int? = nil,
            totalRuns: Int? = nil,
            latestGradedAt: String? = nil,
            averageAgentSteps: Double? = nil,
            agentStepsSamples: Int? = nil,
            averageTotalTokens: Double? = nil,
            tokenSamples: Int? = nil,
            cacheHitRate: Double? = nil,
            cacheTokenSamples: Int? = nil,
            averagePriceUSDBand: PriceBand? = nil,
            runs24h: Int? = nil,
            runs48h: Int? = nil,
            runsTotal: Int? = nil,
            rawCombinedCost: Decimal? = nil,
            combinedCostIndex: Double? = nil
        ) {
            self.model = model
            self.effort = effort
            self.harness = harness
            self.iq = iq
            self.passed = passed
            self.validTasks = validTasks
            self.averagePriceUSD = averagePriceUSD
            self.priceSamples = priceSamples
            self.averageMinutes = averageMinutes
            self.durationSamples = durationSamples
            self.incompleteCostSamples = incompleteCostSamples
            self.totalRuns = totalRuns
            self.latestGradedAt = latestGradedAt
            self.averageAgentSteps = averageAgentSteps
            self.agentStepsSamples = agentStepsSamples
            self.averageTotalTokens = averageTotalTokens
            self.tokenSamples = tokenSamples
            self.cacheHitRate = cacheHitRate
            self.cacheTokenSamples = cacheTokenSamples
            self.averagePriceUSDBand = averagePriceUSDBand
            self.runs24h = runs24h
            self.runs48h = runs48h
            self.runsTotal = runsTotal
            self.rawCombinedCost = rawCombinedCost
            self.combinedCostIndex = combinedCostIndex
        }

        enum CodingKeys: String, CodingKey {
            case model, effort, harness, iq, passed
            case validTasks = "valid_tasks"
            case averagePriceUSD = "average_price_usd"
            case priceSamples = "price_samples"
            case averageMinutes = "average_minutes"
            case durationSamples = "duration_samples"
            case incompleteCostSamples = "incomplete_cost_samples"
            case totalRuns = "total_runs"
            case latestGradedAt = "latest_graded_at"
            case averageAgentSteps = "average_agent_steps"
            case agentStepsSamples = "agent_steps_samples"
            case averageTotalTokens = "average_total_tokens"
            case tokenSamples = "token_samples"
            case cacheHitRate = "cache_hit_rate"
            case cacheTokenSamples = "cache_token_samples"
            case averagePriceUSDBand = "average_price_usd_by_band"
            case runs24h = "runs_24h"
            case runs48h = "runs_48h"
            case runsTotal = "runs_total"
            case rawCombinedCost = "raw_combined_cost"
            case combinedCostIndex = "combined_cost_index"
        }

        /// DeepSeek off-peak/peak price split (upstream `average_price_usd_by_band`).
        struct PriceBand: Codable, Hashable, Sendable {
            let offPeak: Decimal?
            let peak: Decimal?

            enum CodingKeys: String, CodingKey {
                case offPeak = "off_peak"
                case peak
            }
        }
    }

    /// One historical observation (upstream `history[]`), chronological.
    /// `points` tolerates a missing key so trimmed payloads still decode.
    struct HistoryEntry: Hashable, Sendable {
        let at: String?
        let points: [HistoryPoint]

        init(at: String?, points: [HistoryPoint]) {
            self.at = at
            self.points = points
        }
    }

    struct HistoryPoint: Codable, Hashable, Sendable {
        let model: String?
        let effort: String?
        let passed: Double?
        let validTasks: Double?
        let iq: Double?
        let averagePriceUSD: Decimal?
        let priceSamples: Int?
        let averageMinutes: Double?
        let durationSamples: Int?
        let averageAgentSteps: Double?
        let agentStepsSamples: Int?
        let averageTotalTokens: Double?
        let tokenSamples: Int?
        let cacheHitRate: Double?
        let cacheTokenSamples: Int?

        init(
            model: String? = nil,
            effort: String? = nil,
            passed: Double? = nil,
            validTasks: Double? = nil,
            iq: Double? = nil,
            averagePriceUSD: Decimal? = nil,
            priceSamples: Int? = nil,
            averageMinutes: Double? = nil,
            durationSamples: Int? = nil,
            averageAgentSteps: Double? = nil,
            agentStepsSamples: Int? = nil,
            averageTotalTokens: Double? = nil,
            tokenSamples: Int? = nil,
            cacheHitRate: Double? = nil,
            cacheTokenSamples: Int? = nil
        ) {
            self.model = model
            self.effort = effort
            self.passed = passed
            self.validTasks = validTasks
            self.iq = iq
            self.averagePriceUSD = averagePriceUSD
            self.priceSamples = priceSamples
            self.averageMinutes = averageMinutes
            self.durationSamples = durationSamples
            self.averageAgentSteps = averageAgentSteps
            self.agentStepsSamples = agentStepsSamples
            self.averageTotalTokens = averageTotalTokens
            self.tokenSamples = tokenSamples
            self.cacheHitRate = cacheHitRate
            self.cacheTokenSamples = cacheTokenSamples
        }

        enum CodingKeys: String, CodingKey {
            case model, effort, passed, iq
            case validTasks = "valid_tasks"
            case averagePriceUSD = "average_price_usd"
            case priceSamples = "price_samples"
            case averageMinutes = "average_minutes"
            case durationSamples = "duration_samples"
            case averageAgentSteps = "average_agent_steps"
            case agentStepsSamples = "agent_steps_samples"
            case averageTotalTokens = "average_total_tokens"
            case tokenSamples = "token_samples"
            case cacheHitRate = "cache_hit_rate"
            case cacheTokenSamples = "cache_token_samples"
        }
    }

    /// Upstream's own description of how the numbers are derived; shown
    /// verbatim, never reworded locally.
    struct Method: Codable, Hashable, Sendable {
        let iq: String?
        let price: String?
        let duration: String?
        let combinedCost: String?

        enum CodingKeys: String, CodingKey {
            case iq, price, duration
            case combinedCost = "combined_cost"
        }
    }
}

extension IntelligenceEfficiencyDataset.HistoryEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case at, points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decodeIfPresent(String.self, forKey: .at)
        points = try container.decodeIfPresent([IntelligenceEfficiencyDataset.HistoryPoint].self, forKey: .points) ?? []
    }
}

enum IntelligenceEfficiencyParseError: Error, Hashable, Sendable {
    case malformedJSON
    case unexpectedType(String?)
}
