import Foundation

struct RadarSourceDescriptor: Sendable, Hashable {
    let id: RadarSourceID
    let displayName: String
    let supportLevel: SupportLevel
    let homepageURL: URL?
    let seriesRevision: String
}

enum SupportLevel: String, Codable, Sendable {
    case experimental
    case authorized
    case disabled
}

protocol RadarSource: Sendable {
    var descriptor: RadarSourceDescriptor { get }

    func fetchBenchmark() async throws -> BenchmarkDataset
    func fetchCommunity() async throws -> CommunityDataset?
    func fetchSourceStatus() async throws -> SourceStatusDataset?
}
