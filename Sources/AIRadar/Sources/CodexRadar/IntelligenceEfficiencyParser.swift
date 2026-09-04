import Foundation

/// Tolerant wire shape of `codexradar.com/data/intelligence-efficiency.json`
/// (spec §1.1: 15 top-level keys). Nested arrays reuse the dataset's own
/// value types — every field is optional, so upstream drift decodes instead
/// of breaking the sidecar; validation happens after decode.
struct IntelligenceEfficiencyPayload: Decodable, Sendable {
    var schema: Int?
    var mode: String?
    var type: String?
    var source: String?
    var metricsSource: String?
    var sourceUpdatedAt: String?
    var models: Int?
    var runs24hTotal: Int?
    var runs48hTotal: Int?
    var runsTotal: Int?
    var points: [IntelligenceEfficiencyDataset.Point]?
    var history: [IntelligenceEfficiencyDataset.HistoryEntry]?
    var fingerprint: String?
    var activityFingerprint: String?
    var method: IntelligenceEfficiencyDataset.Method?

    enum CodingKeys: String, CodingKey {
        case schema, mode, type, source, models, points, history, fingerprint, method
        case metricsSource = "metrics_source"
        case sourceUpdatedAt = "source_updated_at"
        case runs24hTotal = "runs_24h_total"
        case runs48hTotal = "runs_48h_total"
        case runsTotal = "runs_total"
        case activityFingerprint = "activity_fingerprint"
    }
}

enum IntelligenceEfficiencyParser {
    /// The payload `type` discriminates this endpoint's content; a mismatch
    /// means the endpoint drifted and the data must not be trusted (spec §5.2
    /// validator role). Provenance fields (`source`/`metrics_source`) are kept
    /// verbatim for attribution but never used to build requests (§5.0).
    static let expectedType = "distributed_intelligence_efficiency"

    static func parse(
        _ data: Data,
        sourceID: RadarSourceID,
        fetchedAt: Date
    ) throws -> IntelligenceEfficiencyDataset {
        let payload: IntelligenceEfficiencyPayload
        do {
            payload = try JSONDecoder().decode(IntelligenceEfficiencyPayload.self, from: data)
        } catch {
            throw IntelligenceEfficiencyParseError.malformedJSON
        }
        if let type = payload.type, type != expectedType {
            throw IntelligenceEfficiencyParseError.unexpectedType(type)
        }
        return IntelligenceEfficiencyDataset(
            sourceID: sourceID,
            fetchedAt: fetchedAt,
            schema: payload.schema,
            mode: payload.mode,
            type: payload.type,
            source: payload.source,
            metricsSource: payload.metricsSource,
            sourceUpdatedAt: payload.sourceUpdatedAt,
            models: payload.models,
            runs24hTotal: payload.runs24hTotal,
            runs48hTotal: payload.runs48hTotal,
            runsTotal: payload.runsTotal,
            points: payload.points ?? [],
            history: payload.history ?? [],
            fingerprint: payload.fingerprint,
            activityFingerprint: payload.activityFingerprint,
            method: payload.method
        )
    }
}
