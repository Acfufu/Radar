import Foundation

struct RadarSourceID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

extension RadarSourceID {
    static let claudeCodeRadar = Self(rawValue: "claude-code-radar")
    static let codexRadar = Self(rawValue: "codex-radar")
}
