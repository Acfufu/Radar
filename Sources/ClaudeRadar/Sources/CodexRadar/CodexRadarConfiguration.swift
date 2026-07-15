import Foundation

struct CodexRadarConfiguration: Sendable {
    static let seriesRevision = "codex-radar-public-v2"
    static let descriptor = RadarSourceDescriptor(
        id: .codexRadar,
        displayName: "Codex Radar",
        supportLevel: .authorized,
        homepageURL: URL(string: "https://codexradar.com/"),
        seriesRevision: seriesRevision
    )

    let summaryURL: URL
    let communityURL: URL?

    static let production = CodexRadarConfiguration(
        summaryURL: URL(string: "https://codexradar.com/current.json")!,
        communityURL: URL(string: "https://codexradar.com/api/model-ratings?history=14")!
    )
}
