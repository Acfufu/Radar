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
/// personal usage figure. The 2026-10-27 schema 3 recon froze `checked_at`
/// (2026-07-06 snapshot) and the per-window usage percentages as the
/// card-facing fields; everything renders verbatim (D13 sibling red line).
struct QuotaCheckInfo: Hashable, Codable, Sendable {
    let planType: String?
    let creditsAvailable: Int?
    let limitReached: Bool?
    let allowed: Bool?
    var checkedAt: String? = nil
    var windows: [String: QuotaCheckWindowInfo]? = nil
}

struct QuotaCheckWindowInfo: Hashable, Codable, Sendable {
    let usedPercent: Int?
}

/// quota_calibration summary: how upstream calibrates the quota probes.
/// schema 3 (2026-10-27): the field-age anchor is `checked_at_before`
/// (2026-07-16 snapshot) — the single `checked_at` key this struct's older
/// fixtures used no longer exists upstream; the parser maps
/// `checkedAtBefore ?? checkedAt` so both generations stay readable.
struct QuotaCalibrationInfo: Hashable, Codable, Sendable {
    let date: String?
    let status: String?
    let primaryWindow: String?
    let globalConcurrency: Int?
    let checkedAt: String?
    var source: String? = nil
    var tasks: Int? = nil
    var validTasks: Int? = nil
    var costUsd: Decimal? = nil
    var costBasis: String? = nil
    var checkedAtBefore: String? = nil
    var checkedAtAfter: String? = nil
    var windows: [String: QuotaCalibrationWindowInfo]? = nil
}

struct QuotaCalibrationWindowInfo: Hashable, Codable, Sendable {
    let valid: Bool?
    let reason: String?
    let usedPercentDelta: Int?
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
