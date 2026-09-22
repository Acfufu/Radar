import Foundation

/// Upstream fast-radar history (spec §5.3), normalized from the public
/// `codexradar.com/data/fast-radar-history.json` payload (schema v1,
/// top-level `schema_version/type/timezone/updated_at/runs`). Runs are
/// chronological upstream measurements; all fields stay optional so drift
/// decodes tolerantly. The nested value types double as the wire types.
struct FastRadarHistoryDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let fetchedAt: Date
    let schemaVersion: Int?
    let type: String?
    let timezone: String?
    let updatedAt: String?
    let runs: [FastRadarRun]

    init(
        sourceID: RadarSourceID,
        fetchedAt: Date,
        schemaVersion: Int? = nil,
        type: String? = nil,
        timezone: String? = nil,
        updatedAt: String? = nil,
        runs: [FastRadarRun] = []
    ) {
        self.sourceID = sourceID
        self.fetchedAt = fetchedAt
        self.schemaVersion = schemaVersion
        self.type = type
        self.timezone = timezone
        self.updatedAt = updatedAt
        self.runs = runs
    }

    /// One upstream measurement run (`runs[]`). Two coexisting wire shapes
    /// (spec §5.3 v1.3 note, 2026-09-22 recon): the legacy trio shape carries
    /// only `models` keyed `sol`/`terra`/`luna`; the active per-model shape
    /// adds `model`/`effort`/`profile`/pairing bookkeeping and keys `models`
    /// by short model name (`astra`). All fields stay optional; unknown keys
    /// inside `models` are preserved verbatim (never a closed enum).
    struct FastRadarRun: Codable, Hashable, Sendable {
        let runID: String?
        let measuredAt: String?
        let completedAt: String?
        let cliVersion: String?
        let model: String?
        let effort: String?
        let profile: String?
        let validPairs: Int?
        let sampleCount: Int?
        let tpsAvailable: Bool?
        let tpsUnavailableReason: String?
        let models: [String: Tier]?

        enum CodingKeys: String, CodingKey {
            case runID = "run_id"
            case measuredAt = "measured_at"
            case completedAt = "completed_at"
            case cliVersion = "cli_version"
            case model
            case effort
            case profile
            case validPairs = "valid_pairs"
            case sampleCount = "sample_count"
            case tpsAvailable = "tps_available"
            case tpsUnavailableReason = "tps_unavailable_reason"
            case models
        }

        init(
            runID: String? = nil,
            measuredAt: String? = nil,
            completedAt: String? = nil,
            cliVersion: String? = nil,
            model: String? = nil,
            effort: String? = nil,
            profile: String? = nil,
            validPairs: Int? = nil,
            sampleCount: Int? = nil,
            tpsAvailable: Bool? = nil,
            tpsUnavailableReason: String? = nil,
            models: [String: Tier]? = nil
        ) {
            self.runID = runID
            self.measuredAt = measuredAt
            self.completedAt = completedAt
            self.cliVersion = cliVersion
            self.model = model
            self.effort = effort
            self.profile = profile
            self.validPairs = validPairs
            self.sampleCount = sampleCount
            self.tpsAvailable = tpsAvailable
            self.tpsUnavailableReason = tpsUnavailableReason
            self.models = models
        }

        /// Display name for a `models` key: the run-level `model` id when the
        /// per-model shape provides it, otherwise the legacy dict key.
        var displayModel: String? {
            model ?? models?.keys.sorted().first
        }

        struct Tier: Codable, Hashable, Sendable {
            let standard: Measurement?
            let fast: Measurement?

            init(standard: Measurement? = nil, fast: Measurement? = nil) {
                self.standard = standard
                self.fast = fast
            }
        }

        struct Measurement: Codable, Hashable, Sendable {
            let ttftSeconds: Double?
            let tps: Double?
            let e2eSeconds: Double?

            enum CodingKeys: String, CodingKey {
                case ttftSeconds = "ttft_seconds"
                case tps
                case e2eSeconds = "e2e_seconds"
            }
        }
    }

    static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }
}

enum FastRadarHistoryParseError: Error, Hashable, Sendable {
    case malformedJSON
    case unexpectedType(String?)
}
