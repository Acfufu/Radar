import Foundation

struct SWEBenchLeaderboardsDTO: Decodable, Sendable {
    let leaderboards: [Leaderboard]

    struct Leaderboard: Decodable, Sendable {
        let name: String
        let results: [Result]
    }

    struct Result: Decodable, Sendable {
        let folder: String
        let name: String
        let resolved: RadarDecimal
        let cost: RadarDecimal?
        let miniSWEAgentVersion: String?
        let warning: String?

        enum CodingKeys: String, CodingKey {
            case folder, name, resolved, cost, warning
            case miniSWEAgentVersion = "mini-swe-agent_version"
        }
    }
}
