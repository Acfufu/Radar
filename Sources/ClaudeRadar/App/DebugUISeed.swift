#if DEBUG
import Foundation

enum DebugUISeed {
    static func populate(repository: RadarRepository, state: String) async throws {
        let exactSecondNow = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let now = exactSecondNow
        let base = state == "stale" ? now.addingTimeInterval(-8 * 60 * 60) : now
        if state == "analysis" {
            try await populateAnalysis(repository: repository, base: base)
            return
        }
        if state == "export-501" {
            try await populateExport(repository: repository, base: base)
            return
        }
        let ids = ["opus", "sonnet", "haiku", "very-long-model-name-for-cjk-wrapping-check"]
        let names = ["Opus 4.8 超长模型名称测试", "Sonnet 4.7", "Haiku 4.5", "Prompt-like <script>alert(1)</script> inert"]
        let first = zip(ids, names).enumerated().map { index, pair in model(key: pair.0, name: pair.1, quality: Decimal(62 - index * 4), cost: index == 2 ? nil : Decimal(index + 2), tokens: index == 1 ? nil : Int64(40_000 + index * 12_000)) }
        let second = zip(ids, names).enumerated().map { index, pair in model(key: pair.0, name: pair.1, quality: Decimal(70 - index * 3), cost: index == 2 ? nil : Decimal(index + 3), tokens: index == 1 ? nil : Int64(44_000 + index * 11_000)) }
        _ = try await repository.insertBenchmark(dataset(at: base.addingTimeInterval(-10_800), revision: "fixture-r1", models: first))
        _ = try await repository.insertBenchmark(dataset(at: base.addingTimeInterval(-7_200), revision: "fixture-r1", models: adjusted(first, by: 1)))
        _ = try await repository.insertBenchmark(dataset(at: base.addingTimeInterval(-3_600), revision: "fixture-r2", models: second))
        _ = try await repository.insertBenchmark(dataset(at: base, revision: "fixture-r2", models: adjusted(second, by: 1)))
        let quotas = [
            SourceQuotaEstimate(id: "h5", windowLabel: "5h", usedPercent: 24, estimatedValueUSD: 231.13, resetDescription: "约 20:50 重置"),
            SourceQuotaEstimate(id: "d7", windowLabel: "7d", usedPercent: 41, estimatedValueUSD: 1617.91, resetDescription: "约 7 天窗口重置"),
        ]
        _ = try await repository.insertSourceStatus(.init(sourceID: .claudeCodeRadar, sourceUpdatedAt: base, fetchedAt: base, quotaEstimates: quotas), seriesRevision: "fixture-r2")
        if state != "community-unavailable" {
            let ratings = second.prefix(2).map { CommunityRating(id: $0.id, model: $0.descriptor, average: 8.2, voteCount: 12, scaleMinimum: 1, scaleMaximum: 10) }
            _ = try await repository.insertCommunity(.init(sourceID: .claudeCodeRadar, sourceUpdatedAt: base, fetchedAt: base, ratings: ratings), seriesRevision: "fixture-r2")
        }
        if state == "community-error" {
            try await repository.recordFailure(
                sourceID: .claudeCodeRadar,
                datasetType: .community,
                attemptedAt: now,
                error: .init(kind: .http, message: "community HTTP 503")
            )
        }
        if state == "error" {
            try await repository.recordFailure(sourceID: .claudeCodeRadar, datasetType: .benchmark, attemptedAt: now, error: .init(kind: .validation, message: "upstream <script>alert(1)</script>"))
        }
    }

    private static func populateAnalysis(repository: RadarRepository, base: Date) async throws {
        let prior = [
            model(key: "revision-changed", name: "Revision Changed", quality: 99, cost: 1, tokens: 100),
        ]
        let current = [
            model(key: "dominated", name: "Beta Dominated", quality: 80, cost: 3, tokens: 300),
            model(key: "frontier", name: "Frontier", quality: 90, cost: 2, tokens: 200),
            model(key: "missing", name: "Nil Metric", quality: nil, cost: 1, tokens: 100),
            model(key: "tie-a", name: "Same Tie", quality: 90, cost: 2, tokens: 200),
            model(key: "tie-b", name: "Same Tie", quality: 90, cost: 2, tokens: 200),
            model(key: "zero-passed", name: "Zero Passed", quality: 70, cost: 4, tokens: 400, passed: 0),
        ]
        _ = try await repository.insertBenchmark(dataset(at: base.addingTimeInterval(-3_600), revision: "fixture-r1", models: prior))
        _ = try await repository.insertBenchmark(dataset(at: base, revision: "fixture-r2", models: current))
    }

    private static func populateExport(repository: RadarRepository, base: Date) async throws {
        for index in 0..<501 {
            let date = base.addingTimeInterval(TimeInterval(index - 501))
            let sample = model(key: "export-\(index)", name: "Export Model \(index)", quality: nil, cost: Decimal(string: "1.2300"), tokens: nil)
            _ = try await repository.insertBenchmark(dataset(at: date, revision: "fixture-export-\(index)", models: [sample]))
        }
    }

    private static func dataset(at date: Date, revision: String, models: [ModelBenchmark]) -> BenchmarkDataset {
        .init(sourceID: .claudeCodeRadar, sourceUpdatedAt: date, fetchedAt: date, benchmarkName: "Debug QA Fixture", benchmarkVersion: "1", seriesRevision: revision, models: models)
    }
    private static func model(key: String, name: String, quality: Decimal?, cost: Decimal?, tokens: Int64?, passed: Int = 8) -> ModelBenchmark {
        let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: key)
        return .init(id: id, descriptor: .init(id: id, upstreamName: name, displayName: name), qualityScore: quality, passedTasks: passed, validTasks: 10, invalidTasks: 10 - passed, benchmarkCostUSD: cost, inputTokens: tokens.map { $0 / 2 }, outputTokens: tokens.map { $0 / 4 }, cacheReadTokens: tokens.map { $0 / 5 }, cacheCreationTokens: nil, totalTokens: tokens, elapsedSeconds: 20, agentSteps: 14, cacheHitPercent: 82.4)
    }
    private static func adjusted(_ models: [ModelBenchmark], by delta: Decimal) -> [ModelBenchmark] {
        models.map { value in
            .init(id: value.id, descriptor: value.descriptor, qualityScore: value.qualityScore.map { $0 + delta }, passedTasks: value.passedTasks, validTasks: value.validTasks, invalidTasks: value.invalidTasks, benchmarkCostUSD: value.benchmarkCostUSD, inputTokens: value.inputTokens, outputTokens: value.outputTokens, cacheReadTokens: value.cacheReadTokens, cacheCreationTokens: value.cacheCreationTokens, totalTokens: value.totalTokens, elapsedSeconds: value.elapsedSeconds, agentSteps: value.agentSteps, cacheHitPercent: value.cacheHitPercent)
        }
    }
}
#endif
