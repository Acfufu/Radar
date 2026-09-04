import Foundation

/// Codex station status snapshot (spec §5.1): normalized top-level fields of
/// current.json schema 2.0 that describe window/prediction/Tibo state.
/// Every upstream field is optional so older payloads and upstream drift
/// decode tolerantly; nothing here is inferred locally (D13).
struct CodexStationStatusDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let fetchedAt: Date
    let monitoredAt: String?
    let timezone: String?
    let windowOpen: Bool?
    let status: String?
    let recommendedAction: String?
    let window: WindowInfo?
    let prediction: Prediction?
    let tiboPresence: TiboPresence?

    struct WindowInfo: Hashable, Codable, Sendable {
        let isOpen: Bool?
        let status: String?
        let action: String?
        let message: String?
        let title: String?
        let scope: String?
        let openedAt: String?
        let closedAt: String?
        let sourceURL: String?
    }

    struct Prediction: Hashable, Codable, Sendable {
        let level: String?
        let probability24h: Double?
        let probability48h: Double?
        let summary: String?
        let summaryEN: String?
        let updatedAt: String?
    }

    struct TiboPresence: Hashable, Codable, Sendable {
        let timezone: String?
        let locationLabelZH: String?
        let locationLabelEN: String?
        let probability: Double?
        let confidence: String?
        let evidenceSummaryZH: String?
        let evidenceSummaryEN: String?
        let sourceURLs: [String]?
        let shouldDisplay: Bool?
        let safetyNoteZH: String?
        let safetyNoteEN: String?
        let observedAt: String?
        let updatedAt: String?
    }
}

/// Upstream quota trend series (10 rows, chronological order preserved —
/// never re-sorted, per spec §5.1).
struct QuotaTrendPoint: Hashable, Codable, Sendable {
    let date: String?
    let fiveH5x: Decimal?
    let fiveH20x: Decimal?
    let fiveHPlus: Decimal?
    let rate: Decimal?
    let offset: Decimal?
}

/// quota_check summary (spec §1.1): source-account probe result, never a
/// personal usage figure.
struct QuotaCheckInfo: Hashable, Codable, Sendable {
    let planType: String?
    let creditsAvailable: Int?
    let limitReached: Bool?
    let allowed: Bool?
}

/// quota_calibration summary: how upstream calibrates the quota probes.
struct QuotaCalibrationInfo: Hashable, Codable, Sendable {
    let date: String?
    let status: String?
    let primaryWindow: String?
    let globalConcurrency: Int?
    let checkedAt: String?
}

/// model_iq.data_source provenance (spec §5.1): upstream's own description of
/// where the benchmark selection came from.
struct BenchmarkDataSourceInfo: Hashable, Codable, Sendable {
    let type: String?
    let url: String?
    let selection: String?
    let checkedAt: String?
    let validCells: Int?
}
