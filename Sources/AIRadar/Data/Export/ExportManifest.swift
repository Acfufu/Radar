import Foundation

struct ExportManifest: Codable, Equatable, Sendable {
    struct Dataset: Codable, Equatable, Sendable {
        let name: String
        let schemaVersion: Int
        let recordCount: Int
        let pageCount: Int
    }

    let format: String
    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String
    let pageSize: Int
    let includesRawSamples: Bool
    let sources: [String]
    let dateRange: ExportDateRange
    let datasets: [Dataset]
}

struct ExportDateRange: Codable, Equatable, Sendable {
    var start: Date?
    var end: Date?

    static let all = ExportDateRange(start: nil, end: nil)

    func contains(_ date: Date) -> Bool {
        if let start, date < start { return false }
        if let end, date > end { return false }
        return true
    }
}

enum ExportDataset: String, Codable, CaseIterable, Sendable {
    case models
    case benchmarkRuns = "benchmark-runs"
    case communityRatings = "community-ratings"
    case sourceStatus = "source-status"
    case renderedWarnings = "rendered-warnings"
    case renderedIQHistory = "rendered-iq-history"
    // P2 expanded surfaces (spec §5.5): additive, schemaVersion stays 1.
    case codexStationStatus = "codex-station-status"
    case intelligenceEfficiency = "intelligence-efficiency"
    case fastRadarHistory = "fast-radar-history"
    case rawSamples = "raw-samples"

    static let normalized: [ExportDataset] = [
        .models,
        .benchmarkRuns,
        .communityRatings,
        .sourceStatus,
        .renderedWarnings,
        .renderedIQHistory,
        .codexStationStatus,
        .intelligenceEfficiency,
        .fastRadarHistory,
    ]
}
