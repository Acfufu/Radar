import Foundation

/// Upstream radar-insights dataset (spec §5.6), normalized from the public
/// `codexradar.com/api/radar-insights` payload. Every upstream field stays
/// optional so drift decodes tolerantly; the recommendation texts are stored
/// and shown verbatim (never reworded or locally derived — D13-style
/// attribution consumption, spec §2 v1.1 revision).
struct RadarInsightsDataset: Codable, Hashable, Sendable {
    let sourceID: RadarSourceID
    let fetchedAt: Date
    let schema: Int?
    let benchmarkID: String?
    let mode: String?
    let recommendationMode: String?
    let generatedAt: String?
    let sourceUpdatedAt: String?
    let softwareSourceUpdatedAt: String?
    let visualSourceUpdatedAt: String?
    let comprehensivePoints: [ComprehensivePoint]
    let recommendations: [Recommendation]
    let degradationAlerts: DegradationAlerts?

    init(
        sourceID: RadarSourceID,
        fetchedAt: Date,
        schema: Int? = nil,
        benchmarkID: String? = nil,
        mode: String? = nil,
        recommendationMode: String? = nil,
        generatedAt: String? = nil,
        sourceUpdatedAt: String? = nil,
        softwareSourceUpdatedAt: String? = nil,
        visualSourceUpdatedAt: String? = nil,
        comprehensivePoints: [ComprehensivePoint] = [],
        recommendations: [Recommendation] = [],
        degradationAlerts: DegradationAlerts? = nil
    ) {
        self.sourceID = sourceID
        self.fetchedAt = fetchedAt
        self.schema = schema
        self.benchmarkID = benchmarkID
        self.mode = mode
        self.recommendationMode = recommendationMode
        self.generatedAt = generatedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.softwareSourceUpdatedAt = softwareSourceUpdatedAt
        self.visualSourceUpdatedAt = visualSourceUpdatedAt
        self.comprehensivePoints = comprehensivePoints
        self.recommendations = recommendations
        self.degradationAlerts = degradationAlerts
    }

    enum CodingKeys: String, CodingKey {
        case sourceID, fetchedAt, schema, mode, recommendations
        case benchmarkID = "benchmarkID"
        case recommendationMode = "recommendationMode"
        case generatedAt = "generatedAt"
        case sourceUpdatedAt = "sourceUpdatedAt"
        case softwareSourceUpdatedAt = "softwareSourceUpdatedAt"
        case visualSourceUpdatedAt = "visualSourceUpdatedAt"
        case comprehensivePoints = "comprehensivePoints"
        case degradationAlerts = "degradationAlerts"
    }

    /// One three-component IQ row (upstream `comprehensive_points[]`):
    /// comprehensive / software / visual IQ stay separate numbers and are
    /// never merged locally (spec §5.6/§5.7 boundary). `effort` is an open
    /// set rendered verbatim (upstream already emits `ultra`).
    struct ComprehensivePoint: Codable, Hashable, Sendable {
        let model: String?
        let effort: String?
        let iq: Double?
        let softwareIq: Double?
        let visualIq: Double?
        let samples: Int?

        init(
            model: String? = nil,
            effort: String? = nil,
            iq: Double? = nil,
            softwareIq: Double? = nil,
            visualIq: Double? = nil,
            samples: Int? = nil
        ) {
            self.model = model
            self.effort = effort
            self.iq = iq
            self.softwareIq = softwareIq
            self.visualIq = visualIq
            self.samples = samples
        }

        enum CodingKeys: String, CodingKey {
            case model, effort, iq, samples
            case softwareIq = "software_iq"
            case visualIq = "visual_iq"
        }    }

    /// One station-owner recommendation scene (upstream `recommendations[]`);
    /// `rule` and `title` are upstream-authored text kept verbatim. `items`
    /// tolerates a missing key so trimmed payloads still decode.
    struct Recommendation: Hashable, Sendable {
        let key: String?
        let title: String?
        let rule: String?
        let items: [RecommendationItem]

        init(key: String?, title: String?, rule: String?, items: [RecommendationItem]) {
            self.key = key
            self.title = title
            self.rule = rule
            self.items = items
        }
    }

    struct RecommendationItem: Codable, Hashable, Sendable {
        let model: String?
        let effort: String?
        let iq: Double?
        let passed: Double?
        let samples: Int?
        let averageCostUSD: Decimal?
        let costSamples: Int?
        let averageDurationMinutes: Double?
        let durationSamples: Int?
        let combinedCostIndex: Double?
        let rule: String?

        init(
            model: String? = nil,
            effort: String? = nil,
            iq: Double? = nil,
            passed: Double? = nil,
            samples: Int? = nil,
            averageCostUSD: Decimal? = nil,
            costSamples: Int? = nil,
            averageDurationMinutes: Double? = nil,
            durationSamples: Int? = nil,
            combinedCostIndex: Double? = nil,
            rule: String? = nil
        ) {
            self.model = model
            self.effort = effort
            self.iq = iq
            self.passed = passed
            self.samples = samples
            self.averageCostUSD = averageCostUSD
            self.costSamples = costSamples
            self.averageDurationMinutes = averageDurationMinutes
            self.durationSamples = durationSamples
            self.combinedCostIndex = combinedCostIndex
            self.rule = rule
        }

        enum CodingKeys: String, CodingKey {
            case model, effort, iq, passed, samples, rule
            case averageCostUSD = "average_cost_usd"
            case costSamples = "cost_samples"
            case averageDurationMinutes = "average_duration_minutes"
            case durationSamples = "duration_samples"
            case combinedCostIndex = "combined_cost_index"
        }
    }

    /// Upstream `degradation_alerts`: structured degradation signal that
    /// coexists with the rendered warning reader v2 — the two never merge,
    /// validate, or replace each other (spec §5.6 hard rule). `items` may be
    /// empty; element fields are all optional for drift tolerance.
    struct DegradationAlerts: Hashable, Sendable {
        let rule: String?
        let items: [DegradationAlert]

        init(rule: String?, items: [DegradationAlert]) {
            self.rule = rule
            self.items = items
        }
    }

    struct DegradationAlert: Codable, Hashable, Sendable {
        let model: String?
        let effort: String?
        let severity: String?
        let message: String?
        let currentIq: Double?
        let baselineIq: Double?

        init(
            model: String? = nil,
            effort: String? = nil,
            severity: String? = nil,
            message: String? = nil,
            currentIq: Double? = nil,
            baselineIq: Double? = nil
        ) {
            self.model = model
            self.effort = effort
            self.severity = severity
            self.message = message
            self.currentIq = currentIq
            self.baselineIq = baselineIq
        }

        enum CodingKeys: String, CodingKey {
            case model, effort, severity, message
            case currentIq = "current_iq"
            case baselineIq = "baseline_iq"
        }
    }
}

extension RadarInsightsDataset.Recommendation: Codable {
    enum CodingKeys: String, CodingKey {
        case key, title, rule, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        rule = try container.decodeIfPresent(String.self, forKey: .rule)
        items = try container.decodeIfPresent([RadarInsightsDataset.RecommendationItem].self, forKey: .items) ?? []
    }
}

extension RadarInsightsDataset.DegradationAlerts: Codable {
    enum CodingKeys: String, CodingKey {
        case rule, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rule = try container.decodeIfPresent(String.self, forKey: .rule)
        items = try container.decodeIfPresent([RadarInsightsDataset.DegradationAlert].self, forKey: .items) ?? []
    }
}

enum RadarInsightsParseError: Error, Hashable, Sendable {
    case malformedJSON
    case unexpectedBenchmark(String?)
}
