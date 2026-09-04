import Foundation
import Testing
@testable import AIRadar

@Suite("ParetoAnalysisTests")
struct ParetoAnalysisTests {
    @Test("preset directions classify frontier dominated ties and self correctly", arguments: ParetoPreset.allCases)
    func directionsAndTies(preset: ParetoPreset) {
        // Given
        let dataset = benchmark(models: [
            model("frontier", "Zulu", quality: 90, cost: 2, tokens: 200, seconds: 20),
            model("dominated", "Beta", quality: 80, cost: 3, tokens: 300, seconds: 30),
            model("tie-a", "Same", quality: 90, cost: 2, tokens: 200, seconds: 20),
            model("tie-b", "Same", quality: 90, cost: 2, tokens: 200, seconds: 20),
        ])

        // When
        let results = ParetoAnalysis.analyze(dataset: dataset, preset: preset)

        // Then
        #expect(results.map(\.modelID.upstreamKey) == ["dominated", "tie-a", "tie-b", "frontier"])
        #expect(results.first { $0.modelID.upstreamKey == "dominated" }?.classification == .dominated)
        #expect(results.filter { $0.modelID.upstreamKey.hasPrefix("tie") }.allSatisfy { $0.classification == .frontier })
        #expect(results.first { $0.modelID.upstreamKey == "frontier" }?.classification == .frontier)
    }

    @Test("missing dimensions and mismatched model sources are data insufficient")
    func missingAndCrossSource() {
        // Given
        let foreignID = ModelID(sourceID: RadarSourceID(rawValue: "other"), upstreamKey: "foreign")
        let foreign = ModelBenchmark(
            id: foreignID,
            descriptor: .init(id: foreignID, upstreamName: "Foreign", displayName: "Foreign"),
            qualityScore: 100, passedTasks: 1, validTasks: 1, invalidTasks: 0,
            benchmarkCostUSD: 0.1, inputTokens: nil, outputTokens: nil, cacheReadTokens: nil,
            cacheCreationTokens: nil, totalTokens: 1, elapsedSeconds: 1,
            agentSteps: nil, cacheHitPercent: nil
        )
        let dataset = benchmark(models: [
            model("missing", "Missing", quality: nil, cost: 1, tokens: 1, seconds: 1),
            foreign,
        ])

        // When
        let results = ParetoAnalysis.analyze(dataset: dataset, preset: .qualityCost)

        // Then
        #expect(results.allSatisfy { $0.classification == .dataInsufficient })
    }

    @Test("minimize direction keeps a lower consumption tradeoff on the frontier")
    func minimizeDirection() {
        // Given
        let dataset = benchmark(models: [
            model("quality", "Quality", quality: 100, cost: 10, tokens: 1_000, seconds: 100),
            model("efficient", "Efficient", quality: 90, cost: 1, tokens: 100, seconds: 10),
        ])

        // When
        let results = ParetoPreset.allCases.flatMap { ParetoAnalysis.analyze(dataset: dataset, preset: $0) }

        // Then
        #expect(results.allSatisfy { $0.classification == .frontier })
    }

    @Test("workspace analysis uses only the current dataset and ignores history community and quota")
    func currentDatasetOnly() {
        // Given
        let current = benchmark(revision: "current", models: [model("current", "Current", quality: 50, cost: 5, tokens: 500, seconds: 50)])
        _ = benchmark(revision: "old", models: [model("old", "Old", quality: 100, cost: 1, tokens: 1, seconds: 1)])
        let rating = CommunityRating(
            id: current.models[0].id,
            model: current.models[0].descriptor,
            average: 10,
            voteCount: 999,
            scaleMinimum: 1,
            scaleMaximum: 10
        )
        let community = CommunityDataset(sourceID: .claudeCodeRadar, sourceUpdatedAt: nil, fetchedAt: current.fetchedAt, ratings: [rating])
        let status = SourceStatusDataset(sourceID: .claudeCodeRadar, sourceUpdatedAt: nil, fetchedAt: current.fetchedAt, quotaEstimates: [])
        let projection = WorkspaceProjection(
            sync: .init(
                supportLevel: .experimental,
                benchmark: .init(value: current, lastSuccessfulAt: current.fetchedAt, lastAttemptedAt: current.fetchedAt, error: nil, isStale: false),
                community: .init(value: community, lastSuccessfulAt: current.fetchedAt, lastAttemptedAt: current.fetchedAt, error: nil, isStale: false),
                sourceStatus: .init(value: status, lastSuccessfulAt: current.fetchedAt, lastAttemptedAt: current.fetchedAt, error: nil, isStale: false)
            ),
            lifecycle: .running,
            supportLevel: .experimental
        )

        // When
        let projected = projection.pareto(.qualityCost)

        // Then
        #expect(projected.map(\.modelID.upstreamKey) == ["current"])
        #expect(projected[0].classification == .frontier)
    }

    private func benchmark(revision: String = "current", models: [ModelBenchmark]) -> BenchmarkDataset {
        .init(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: nil,
            fetchedAt: Date(timeIntervalSince1970: 1),
            benchmarkName: "Fixture",
            benchmarkVersion: "1",
            seriesRevision: revision,
            models: models
        )
    }

    private func model(
        _ key: String, _ name: String, quality: Decimal?, cost: Decimal?, tokens: Int64?, seconds: Double?
    ) -> ModelBenchmark {
        let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: key)
        return .init(
            id: id,
            descriptor: .init(id: id, upstreamName: name, displayName: name),
            qualityScore: quality, passedTasks: 1, validTasks: 1, invalidTasks: 0,
            benchmarkCostUSD: cost, inputTokens: nil, outputTokens: nil, cacheReadTokens: nil,
            cacheCreationTokens: nil, totalTokens: tokens, elapsedSeconds: seconds,
            agentSteps: nil, cacheHitPercent: nil
        )
    }
}
