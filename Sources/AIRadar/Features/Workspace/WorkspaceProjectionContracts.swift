import Foundation

enum ModelSort: String, CaseIterable, Sendable {
    case name = "名称", quality = "质量", cost = "成本", tokens = "Token", elapsed = "耗时"
}

enum TrendMetric: String, CaseIterable, Sendable {
    case quality = "IQ"
    case cost = "费用"
    case elapsed = "耗时"
    case agentSteps = "Agent steps"
    case cache = "Cache 命中率"
    case tokens = "总 Tokens"
}

enum TrendTimeRange: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case lastDay = "24 小时"
    case lastTwoDays = "48 小时"
    case lastSevenDays = "7 天"
    case lastThirtyDays = "30 天"

    var id: Self { self }
    var interval: TimeInterval? {
        switch self {
        case .all: nil
        case .lastDay: 24 * 60 * 60
        case .lastTwoDays: 48 * 60 * 60
        case .lastSevenDays: 7 * 24 * 60 * 60
        case .lastThirtyDays: 30 * 24 * 60 * 60
        }
    }
}

enum ModelColumn: Hashable, Sendable {
    case model, quality, passRate, cost, tokens, elapsed, agentSteps, cache, community
}

struct WorkspaceModelRow: Identifiable, Sendable {
    let benchmark: ModelBenchmark
    let community: CommunityRating?
    var id: ModelID { benchmark.id }
    var name: String { benchmark.descriptor.displayName }
    var passRate: Decimal? {
        guard let passed = benchmark.passedTasks, let valid = benchmark.validTasks, valid > 0 else { return nil }
        return Decimal(passed) / Decimal(valid) * 100
    }
}

struct TrendPoint: Identifiable, Sendable {
    let id: String
    let date: Date
    let value: Double
    let segmentIndex: Int
}

struct TrendSeries: Identifiable, Sendable {
    let modelID: ModelID
    let modelName: String
    let seriesRevision: String
    let points: [TrendPoint]
    var id: String { "\(modelID.sourceID.rawValue)|\(modelID.upstreamKey)|\(seriesRevision)" }
}

struct CostEfficiencyLeader: Equatable, Sendable {
    let modelID: ModelID
    let modelName: String
    let costPerPassedTask: Decimal
    let formula: DerivedMetricFormula
}

struct RadarDeclineSignal: Identifiable, Equatable, Sendable {
    let modelID: ModelID
    let modelName: String
    let currentIQ: Decimal
    let drop12Hours: Decimal
    let drop24Hours: Decimal
    let drop48Hours: Decimal?
    var id: ModelID { modelID }
}
