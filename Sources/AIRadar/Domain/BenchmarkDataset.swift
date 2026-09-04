import Foundation

struct ModelDescriptor: Identifiable, Hashable, Codable, Sendable {
    let id: ModelID
    let upstreamName: String
    let displayName: String
}

struct BenchmarkDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    let benchmarkName: String?
    let benchmarkVersion: String?
    let seriesRevision: String
    let models: [ModelBenchmark]
    var dataSource: BenchmarkDataSourceInfo? = nil
}

struct ModelBenchmark: Identifiable, Hashable, Codable, Sendable {
    let id: ModelID
    let descriptor: ModelDescriptor
    let qualityScore: Decimal?
    let passedTasks: Int?
    let validTasks: Int?
    let invalidTasks: Int?
    let benchmarkCostUSD: Decimal?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cacheReadTokens: Int64?
    let cacheCreationTokens: Int64?
    let totalTokens: Int64?
    let elapsedSeconds: Double?
    let agentSteps: Int?
    let cacheHitPercent: Decimal?
    var wallTimeHuman: String? = nil
    var averageCostUSD: Decimal? = nil
    var averageTaskSeconds: Double? = nil
    var averageTaskTimeHuman: String? = nil
    var costUSDBasis: String? = nil
}
