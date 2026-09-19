import Foundation

/// Tolerant wire shape of `codexradar.com/api/radar-insights`
/// (spec §1.1: 11 top-level keys, snake_case on the wire). Nested arrays
/// reuse the dataset's own value types — every field is optional, so
/// upstream drift decodes instead of breaking the sidecar; validation
/// happens after decode.
struct RadarInsightsPayload: Decodable, Sendable {
    var schema: Int?
    var benchmarkID: String?
    var mode: String?
    var recommendationMode: String?
    var generatedAt: String?
    var sourceUpdatedAt: String?
    var softwareSourceUpdatedAt: String?
    var visualSourceUpdatedAt: String?
    var comprehensivePoints: [RadarInsightsDataset.ComprehensivePoint]?
    var recommendations: [RadarInsightsDataset.Recommendation]?
    var degradationAlerts: RadarInsightsDataset.DegradationAlerts?

    enum CodingKeys: String, CodingKey {
        case schema, mode, recommendations
        case benchmarkID = "benchmark_id"
        case recommendationMode = "recommendation_mode"
        case generatedAt = "generated_at"
        case sourceUpdatedAt = "source_updated_at"
        case softwareSourceUpdatedAt = "software_source_updated_at"
        case visualSourceUpdatedAt = "visual_source_updated_at"
        case comprehensivePoints = "comprehensive_points"
        case degradationAlerts = "degradation_alerts"
    }
}

enum RadarInsightsParser {
    /// The payload `benchmark_id` discriminates this endpoint's content; a
    /// mismatch means the endpoint drifted and the data must not be trusted
    /// (spec §5.6 validator role).
    static let expectedBenchmarkID = "deep-swe"

    static func parse(
        _ data: Data,
        sourceID: RadarSourceID,
        fetchedAt: Date
    ) throws -> RadarInsightsDataset {
        let payload: RadarInsightsPayload
        do {
            payload = try JSONDecoder().decode(RadarInsightsPayload.self, from: data)
        } catch {
            throw RadarInsightsParseError.malformedJSON
        }
        if let benchmarkID = payload.benchmarkID, benchmarkID != expectedBenchmarkID {
            throw RadarInsightsParseError.unexpectedBenchmark(benchmarkID)
        }
        return RadarInsightsDataset(
            sourceID: sourceID,
            fetchedAt: fetchedAt,
            schema: payload.schema,
            benchmarkID: payload.benchmarkID,
            mode: payload.mode,
            recommendationMode: payload.recommendationMode,
            generatedAt: payload.generatedAt,
            sourceUpdatedAt: payload.sourceUpdatedAt,
            softwareSourceUpdatedAt: payload.softwareSourceUpdatedAt,
            visualSourceUpdatedAt: payload.visualSourceUpdatedAt,
            comprehensivePoints: payload.comprehensivePoints ?? [],
            recommendations: payload.recommendations ?? [],
            degradationAlerts: payload.degradationAlerts
        )
    }
}
