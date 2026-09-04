import Foundation

/// Tolerant wire shape of `codexradar.com/data/fast-radar-history.json`
/// (spec §1.1: 5 top-level keys, schema_version 1). Nested arrays reuse the
/// dataset's own value types; every field is optional so upstream drift
/// decodes instead of breaking the sidecar.
struct FastRadarHistoryPayload: Decodable, Sendable {
    var schemaVersion: Int?
    var type: String?
    var timezone: String?
    var updatedAt: String?
    var runs: [FastRadarHistoryDataset.FastRadarRun]?

    enum CodingKeys: String, CodingKey {
        case type, timezone, runs
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
    }
}

enum FastRadarHistoryParser {
    static let expectedType = "fast_radar_history"

    static func parse(
        _ data: Data,
        sourceID: RadarSourceID,
        fetchedAt: Date
    ) throws -> FastRadarHistoryDataset {
        let payload: FastRadarHistoryPayload
        do {
            payload = try JSONDecoder().decode(FastRadarHistoryPayload.self, from: data)
        } catch {
            throw FastRadarHistoryParseError.malformedJSON
        }
        if let type = payload.type, type != expectedType {
            throw FastRadarHistoryParseError.unexpectedType(type)
        }
        return FastRadarHistoryDataset(
            sourceID: sourceID,
            fetchedAt: fetchedAt,
            schemaVersion: payload.schemaVersion,
            type: payload.type,
            timezone: payload.timezone,
            updatedAt: payload.updatedAt,
            runs: payload.runs ?? []
        )
    }
}
