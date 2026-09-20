import CryptoKit
import Foundation

/// One per-effort cell of a crowdtest harness card (ADR-0004 contract,
/// 2026-09-20 probe): the button's `data-model`×`data-effort` identity plus
/// its bounded normalized values. The methodology `title` is upstream text
/// shown verbatim.
struct CodexRenderedCrowdtestIQCell: Codable, Equatable, Sendable {
    let model: String
    let effort: String
    let iqScore: Double?
    let iqP: Int?
    let iqN: Int?
    let countP: Int?
    let countN: Int?
    let coveredTasks: Int?
    let totalTasks: Int?
    let coverageInsufficient: Bool
    let methodTitle: String?
}

/// One hourly trend observation parsed from a `circle[data-trend-label]`
/// label of the shape `MM/DD HH:00 · <score> IQ`.
struct CodexRenderedCrowdtestIQTrendPoint: Codable, Equatable, Sendable {
    let label: String
    let month: Int?
    let day: Int?
    let hour: Int?
    let score: Double?
}

/// One harness family card (per model). `harness` is the family key
/// (`codex`/`claude-code`/`dsh`/`zcode`/`grok` for the five mapped
/// stations); the parser keeps mapped families only.
struct CodexRenderedCrowdtestIQHarness: Codable, Equatable, Sendable {
    let harness: String
    let model: String?
    let cells: [CodexRenderedCrowdtestIQCell]
    let trend: [CodexRenderedCrowdtestIQTrendPoint]
}

/// Crowdtest IQ snapshot (ADR-0004): the bounded normalized result of one
/// anonymous nonpersistent read of `deng.codexradar.com`.
struct CodexRenderedCrowdtestIQSnapshot: Codable, Equatable, Sendable {
    let sourceID: RadarSourceID
    let parserRevision: String
    let finalOrigin: String
    let capturedAt: Date
    let harnesses: [CodexRenderedCrowdtestIQHarness]
    let semanticFingerprint: String
}

enum CodexRenderedCrowdtestIQSemanticFingerprint {
    static func make(
        harnesses: [CodexRenderedCrowdtestIQHarness],
        finalOrigin: String,
        parserRevision: String
    ) throws -> String {
        let value = SemanticValue(
            harnesses: harnesses,
            finalOrigin: finalOrigin,
            parserRevision: parserRevision
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct SemanticValue: Encodable {
    let harnesses: [CodexRenderedCrowdtestIQHarness]
    let finalOrigin: String
    let parserRevision: String
}

extension CodexRenderedCrowdtestIQSnapshot {
    /// The five mapped harness families in station navigator order
    /// (ADR-0004 five-station mapping); `kimi-code`, `codebuddy`,
    /// `antigravity` etc. are dropped at the parser and never displayed.
    static let mappedHarnesses: [String] = ["codex", "claude-code", "dsh", "zcode", "grok"]
}
