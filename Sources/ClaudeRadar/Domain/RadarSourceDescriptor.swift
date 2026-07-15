import Foundation

struct RadarSourceDescriptor: Identifiable, Sendable, Hashable {
    let id: RadarSourceID
    let displayName: String
    let supportLevel: SupportLevel
    let homepageURL: URL?
    let seriesRevision: String

    var attributionText: String {
        id == .codexRadar
            ? "数据来自 Codex 雷达 codexradar.com"
            : "数据来源：Claude Code Radar"
    }
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

struct RadarEnvelopeProjection: Sendable {
    let benchmark: SegmentProjection<BenchmarkDataset>
    let sourceStatus: SegmentProjection<SourceStatusDataset>
}

protocol RadarPayloadParser: Sendable {
    func parseBenchmarkEnvelope(_ data: Data, fetchedAt: Date) throws -> RadarEnvelopeProjection
    func parseCommunityEnvelope(_ data: Data, fetchedAt: Date) throws -> SegmentProjection<CommunityDataset>
}
