import CryptoKit
import Foundation

struct CodexRenderedIQHistoryPoint: Codable, Equatable, Sendable {
    let sourceOrder: Int
    let sourceTimeLabel: String
    let iq: Double
}

struct CodexRenderedIQHistorySeries: Codable, Equatable, Sendable {
    let sourceOrder: Int
    let seriesKey: String
    let displayName: String
    let points: [CodexRenderedIQHistoryPoint]
}

struct CodexRenderedIQHistorySnapshot: Codable, Equatable, Sendable {
    let sourceID: RadarSourceID
    let parserRevision: String
    let finalOrigin: String
    let capturedAt: Date
    let series: [CodexRenderedIQHistorySeries]
    let semanticFingerprint: String
}

enum CodexRenderedIQHistorySemanticFingerprint {
    static func make(
        sourceID: RadarSourceID,
        series: [CodexRenderedIQHistorySeries],
        finalOrigin: String,
        parserRevision: String
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(SemanticValue(
            sourceID: sourceID,
            parserRevision: parserRevision,
            finalOrigin: finalOrigin,
            series: series
        ))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct SemanticValue: Encodable {
    let sourceID: RadarSourceID
    let parserRevision: String
    let finalOrigin: String
    let series: [CodexRenderedIQHistorySeries]
}
