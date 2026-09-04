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

    /// One upstream measurement run (`runs[]`).
    struct FastRadarRun: Codable, Hashable, Sendable {
        let runID: String?
        let measuredAt: String?
        let completedAt: String?
        let cliVersion: String?
        let models: Models?

        enum CodingKeys: String, CodingKey {
            case runID = "run_id"
            case measuredAt = "measured_at"
            case completedAt = "completed_at"
            case cliVersion = "cli_version"
            case models
        }

        init(
            runID: String? = nil,
            measuredAt: String? = nil,
            completedAt: String? = nil,
            cliVersion: String? = nil,
            models: Models? = nil
        ) {
            self.runID = runID
            self.measuredAt = measuredAt
            self.completedAt = completedAt
            self.cliVersion = cliVersion
            self.models = models
        }

        struct Models: Codable, Hashable, Sendable {
            let sol: Tier?
            let terra: Tier?
            let luna: Tier?

            init(sol: Tier? = nil, terra: Tier? = nil, luna: Tier? = nil) {
                self.sol = sol
                self.terra = terra
                self.luna = luna
            }
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
