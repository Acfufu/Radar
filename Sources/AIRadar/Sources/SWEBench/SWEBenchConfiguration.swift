import Foundation

struct SWEBenchConfiguration: Sendable {
    static let seriesRevision = "swe-bench-verified-mini-v2-v1"
    static let maximumResponseBytes = 16 * 1_024 * 1_024
    static let descriptor = RadarSourceDescriptor(
        id: .sweBenchVerified,
        displayName: "SWE-bench Verified",
        supportLevel: .authorized,
        homepageURL: URL(string: "https://www.swebench.com/"),
        seriesRevision: seriesRevision
    )

    let leaderboardURL: URL

    static let production = SWEBenchConfiguration(
        leaderboardURL: URL(
            string: "https://raw.githubusercontent.com/SWE-bench/swe-bench.github.io/master/data/leaderboards.json"
        )!
    )
}
