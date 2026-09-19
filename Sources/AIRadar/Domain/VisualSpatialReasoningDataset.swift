import Foundation

/// Upstream visual-spatial-reasoning dataset (spec §5.7), merged from the
/// two public `codexradar.com/api/visual-spatial-reasoning[/-history]`
/// endpoints into one sidecar snapshot. All upstream fields stay optional
/// so drift decodes tolerantly; this benchmark (pompeii-adjacency,
/// Adjacency F1) is a third capability plane and is never merged with the
/// radar-insights `visual_iq` component (spec §5.7 hard rule).
struct VisualSpatialReasoningDataset: Codable, Hashable, Sendable {
    let sourceID: RadarSourceID
    let fetchedAt: Date
    let schema: Int?
    let benchmarkID: String?
    let mode: String?
    let type: String?
    let scoreLabel: String?
    let scoringMode: String?
    let sourceUpdatedAt: String?
    let runs24hTotal: Int?
    let runs48hTotal: Int?
    let runsTotal: Int?
    let points: [Point]
    let history: [String: [HistoryPoint]]

    init(
        sourceID: RadarSourceID,
        fetchedAt: Date,
        schema: Int? = nil,
        benchmarkID: String? = nil,
        mode: String? = nil,
        type: String? = nil,
        scoreLabel: String? = nil,
        scoringMode: String? = nil,
        sourceUpdatedAt: String? = nil,
        runs24hTotal: Int? = nil,
        runs48hTotal: Int? = nil,
        runsTotal: Int? = nil,
        points: [Point] = [],
        history: [String: [HistoryPoint]] = [:]
    ) {
        self.sourceID = sourceID
        self.fetchedAt = fetchedAt
        self.schema = schema
        self.benchmarkID = benchmarkID
        self.mode = mode
        self.type = type
        self.scoreLabel = scoreLabel
        self.scoringMode = scoringMode
        self.sourceUpdatedAt = sourceUpdatedAt
        self.runs24hTotal = runs24hTotal
        self.runs48hTotal = runs48hTotal
        self.runsTotal = runsTotal
        self.points = points
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case sourceID, fetchedAt, schema, mode, type, points, history
        case benchmarkID = "benchmarkID"
        case scoreLabel = "scoreLabel"
        case scoringMode = "scoringMode"
        case sourceUpdatedAt = "sourceUpdatedAt"
        case runs24hTotal = "runs24hTotal"
        case runs48hTotal = "runs48hTotal"
        case runsTotal = "runsTotal"
    }

    /// One benchmark row (upstream `points[]`, 23 observed keys); every
    /// field optional. `average_agent_steps` / `average_total_tokens`
    /// decode JSON `null` upstream, hence the `Int`-sample double fields.
    struct Point: Codable, Hashable, Sendable {
        let model: String?
        let effort: String?
        let passed: Double?
        let validTasks: Double?
        let benchmarkTasks: Double?
        let iq: Double?
        let scoreMode: String?
        let averagePriceUSD: Decimal?
        let priceSamples: Int?
        let averageMinutes: Double?
        let durationSamples: Int?
        let incompleteCostSamples: Int?
        let averageAgentSteps: Double?
        let agentStepsSamples: Int?
        let averageTotalTokens: Double?
        let tokenSamples: Int?
        let cacheHitRate: Double?
        let cacheTokenSamples: Int?
        let combinedCostIndex: Double?
        let latestGradedAt: String?
        let runs24h: Int?
        let runs48h: Int?
        let runsTotal: Int?

        init(
            model: String? = nil,
            effort: String? = nil,
            passed: Double? = nil,
            validTasks: Double? = nil,
            benchmarkTasks: Double? = nil,
            iq: Double? = nil,
            scoreMode: String? = nil,
            averagePriceUSD: Decimal? = nil,
            priceSamples: Int? = nil,
            averageMinutes: Double? = nil,
            durationSamples: Int? = nil,
            incompleteCostSamples: Int? = nil,
            averageAgentSteps: Double? = nil,
            agentStepsSamples: Int? = nil,
            averageTotalTokens: Double? = nil,
            tokenSamples: Int? = nil,
            cacheHitRate: Double? = nil,
            cacheTokenSamples: Int? = nil,
            combinedCostIndex: Double? = nil,
            latestGradedAt: String? = nil,
            runs24h: Int? = nil,
            runs48h: Int? = nil,
            runsTotal: Int? = nil
        ) {
            self.model = model
            self.effort = effort
            self.passed = passed
            self.validTasks = validTasks
            self.benchmarkTasks = benchmarkTasks
            self.iq = iq
            self.scoreMode = scoreMode
            self.averagePriceUSD = averagePriceUSD
            self.priceSamples = priceSamples
            self.averageMinutes = averageMinutes
            self.durationSamples = durationSamples
            self.incompleteCostSamples = incompleteCostSamples
            self.averageAgentSteps = averageAgentSteps
            self.agentStepsSamples = agentStepsSamples
            self.averageTotalTokens = averageTotalTokens
            self.tokenSamples = tokenSamples
            self.cacheHitRate = cacheHitRate
            self.cacheTokenSamples = cacheTokenSamples
            self.combinedCostIndex = combinedCostIndex
            self.latestGradedAt = latestGradedAt
            self.runs24h = runs24h
            self.runs48h = runs48h
            self.runsTotal = runsTotal
        }

        enum CodingKeys: String, CodingKey {
            case model, effort, passed, iq
            case validTasks = "valid_tasks"
            case benchmarkTasks = "benchmark_tasks"
            case scoreMode = "score_mode"
            case averagePriceUSD = "average_price_usd"
            case priceSamples = "price_samples"
            case averageMinutes = "average_minutes"
            case durationSamples = "duration_samples"
            case incompleteCostSamples = "incomplete_cost_samples"
            case averageAgentSteps = "average_agent_steps"
            case agentStepsSamples = "agent_steps_samples"
            case averageTotalTokens = "average_total_tokens"
            case tokenSamples = "token_samples"
            case cacheHitRate = "cache_hit_rate"
            case cacheTokenSamples = "cache_token_samples"
            case combinedCostIndex = "combined_cost_index"
            case latestGradedAt = "latest_graded_at"
            case runs24h = "runs_24h"
            case runs48h = "runs_48h"
            case runsTotal = "runs_total"
        }
    }

    /// One history observation for a `"<model>@<effort>"` series key
    /// (upstream `-history` payload), chronological ascending.
    struct HistoryPoint: Codable, Hashable, Sendable {
        let ts: String?
        let score: Double?
        let n: Int?
    }
}

enum VisualSpatialReasoningParseError: Error, Hashable, Sendable {
    case malformedJSON
    case unexpectedType(String?)
}
