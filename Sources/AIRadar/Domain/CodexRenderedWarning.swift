import CryptoKit
import Foundation

struct CodexRenderedWarningCard: Codable, Equatable, Sendable {
    let displayName: String
    let family: String
    let effort: String
    let sourceOrder: Int
    let iq: Double
    let drop24h: Double
    let drop48h: Double?
}

struct CodexRenderedWarningSnapshot: Codable, Equatable, Sendable {
    let sourceID: RadarSourceID
    let parserRevision: String
    let finalOrigin: String
    let sourceTimeLabel: String
    let capturedAt: Date
    let cards: [CodexRenderedWarningCard]
    let semanticFingerprint: String
}

enum CodexRenderedWarningSemanticFingerprint {
    static func make(
        sourceTimeLabel: String,
        cards: [CodexRenderedWarningCard],
        finalOrigin: String,
        parserRevision: String
    ) throws -> String {
        let value = SemanticValue(
            sourceTimeLabel: sourceTimeLabel,
            cards: cards,
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
    let sourceTimeLabel: String
    let cards: [CodexRenderedWarningCard]
    let finalOrigin: String
    let parserRevision: String
}
