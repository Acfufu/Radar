import Foundation

/// Tolerant wire shape of `codexradar.com/api/visual-spatial-reasoning`
/// (spec §1.1: 12 top-level keys, snake_case on the wire).
struct VisualSpatialReasoningPayload: Decodable, Sendable {
    var schema: Int?
    var benchmarkID: String?
    var mode: String?
    var type: String?
    var scoreLabel: String?
    var scoringMode: String?
    var sourceUpdatedAt: String?
    var runs24hTotal: Int?
    var runs48hTotal: Int?
    var runsTotal: Int?
    var points: [VisualSpatialReasoningDataset.Point]?
    /// The summary embeds its own history; the live payload (2026-09-20)
    /// carries an observation LIST (`[{at, points[]}]`) while the canonical
    /// sanitized fixture pins the keyed-dictionary shape — both decode
    /// tolerantly.
    var history: PayloadHistory?

    enum CodingKeys: String, CodingKey {
        case schema, mode, type, points, history
        case benchmarkID = "benchmark_id"
        case scoreLabel = "score_label"
        case scoringMode = "scoring_mode"
        case sourceUpdatedAt = "source_updated_at"
        case runs24hTotal = "runs_24h_total"
        case runs48hTotal = "runs_48h_total"
        case runsTotal = "runs_total"
    }

    struct SummaryHistoryEntry: Decodable, Sendable {
        let at: String?
        let points: [SummaryHistoryPoint]?

        struct SummaryHistoryPoint: Decodable, Sendable {
            let model: String?
            let effort: String?
            let iq: Double?
        }
    }

    struct PayloadHistory: Decodable, Sendable {
        let list: [SummaryHistoryEntry]?
        let keyed: [String: [VisualSpatialReasoningDataset.HistoryPoint]]?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let decodedList = try? container.decode([SummaryHistoryEntry].self) {
                list = decodedList
                keyed = nil
                return
            }
            list = nil
            keyed = try? container.decode([String: [VisualSpatialReasoningDataset.HistoryPoint]].self)
        }
    }
}

/// Tolerant wire shape of `codexradar.com/api/visual-spatial-reasoning-history`:
/// an object dictionary keyed by `"<model>@<effort>"` with `[{ts, score, n}]`
/// values (spec §1.1).
struct VisualSpatialReasoningHistoryPayload: Decodable, Sendable {
    var series: [String: [VisualSpatialReasoningDataset.HistoryPoint]]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        series = try container.decode([String: [VisualSpatialReasoningDataset.HistoryPoint]].self)
    }
}

enum VisualSpatialReasoningParser {
    /// The main payload's `type` discriminates this endpoint's content; a
    /// mismatch means the endpoint drifted and the data must not be trusted
    /// (spec §5.7 validator role).
    static let expectedType = "visual_spatial_reasoning_summary"

    static func parse(
        _ data: Data,
        historyData: Data?,
        sourceID: RadarSourceID,
        fetchedAt: Date
    ) throws -> VisualSpatialReasoningDataset {
        let payload: VisualSpatialReasoningPayload
        do {
            payload = try JSONDecoder().decode(VisualSpatialReasoningPayload.self, from: data)
        } catch {
            throw VisualSpatialReasoningParseError.malformedJSON
        }
        if let type = payload.type, type != expectedType {
            throw VisualSpatialReasoningParseError.unexpectedType(type)
        }
        var series: [String: [VisualSpatialReasoningDataset.HistoryPoint]] = [:]
        if let historyData, !historyData.isEmpty {
            do {
                series = try JSONDecoder().decode(VisualSpatialReasoningHistoryPayload.self, from: historyData).series
            } catch {
                throw VisualSpatialReasoningParseError.malformedJSON
            }
        } else if let embedded = payload.history?.list {
            // Fall back to the summary's embedded observation list: derive
            // the keyed series from it (ts = observation time, score = iq).
            for observation in embedded {
                guard let points = observation.points else { continue }
                for point in points {
                    guard let model = point.model, let effort = point.effort, let iq = point.iq else { continue }
                    series["\(model)@\(effort)", default: []].append(
                        .init(ts: observation.at, score: iq, n: nil)
                    )
                }
            }
        } else if let keyed = payload.history?.keyed {
            series = keyed
        }
        return VisualSpatialReasoningDataset(
            sourceID: sourceID,
            fetchedAt: fetchedAt,
            schema: payload.schema,
            benchmarkID: payload.benchmarkID,
            mode: payload.mode,
            type: payload.type,
            scoreLabel: payload.scoreLabel,
            scoringMode: payload.scoringMode,
            sourceUpdatedAt: payload.sourceUpdatedAt,
            runs24hTotal: payload.runs24hTotal,
            runs48hTotal: payload.runs48hTotal,
            runsTotal: payload.runsTotal,
            points: payload.points ?? [],
            history: series
        )
    }
}
