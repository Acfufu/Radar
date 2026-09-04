import Foundation

struct ModelID: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let upstreamKey: String

    static func fallback(sourceID: RadarSourceID, upstreamName: String) -> Self {
        let edgeTrimmed = upstreamName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { !$0.isLetter && !$0.isNumber })
            .reversed()
            .drop(while: { !$0.isLetter && !$0.isNumber })
            .reversed()
        let normalized = String(edgeTrimmed)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
        return Self(sourceID: sourceID, upstreamKey: normalized)
    }
}
