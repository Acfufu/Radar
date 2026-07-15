import Foundation

struct ClaudeRadarConfiguration: Sendable {
    static let seriesRevision = "claude-radar-v1"
    static let descriptor = RadarSourceDescriptor(
        id: .claudeCodeRadar,
        displayName: "Claude Code Radar",
        supportLevel: .authorized,
        homepageURL: URL(string: "https://claudecoderadar.com/?lang=en"),
        seriesRevision: seriesRevision
    )

    let benchmarkURL: URL
    let communityURL: URL?
    let sourceStatusURL: URL?

    static let production: Self = {
        guard let benchmarkURL = URL(string: "https://claudecoderadar.com/data/claude-code-radar.json") else {
            preconditionFailure("The frozen Claude Radar benchmark URL is invalid")
        }
        return Self(
            benchmarkURL: benchmarkURL,
            communityURL: URL(string: "https://claudecoderadar.com/api/model-ratings?history=10"),
            sourceStatusURL: nil
        )
    }()
}
