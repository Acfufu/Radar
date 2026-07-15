import Foundation
import Testing
@testable import ClaudeRadar

@Suite("DerivedMetricsTests")
struct DerivedMetricsTests {
    @Test("all four transparent formulas preserve exact Decimal values")
    func formulasAndPrecision() {
        // Given
        let model = benchmark(
            quality: Decimal(string: "91.234567890123456789")!,
            passed: 3,
            cost: Decimal(string: "0.3")!,
            tokens: 1_000,
            seconds: 1.5
        )

        // When
        let results = DerivedMetrics.evaluate(model: model)

        // Then
        #expect(results.map(\.formula) == DerivedMetricFormula.allCases)
        #expect(results[0].value == .decimal(Decimal(string: "0.1")!))
        #expect(results[1].value == .decimal(Decimal(string: "333.33333333333333333333333333333333333")!))
        #expect(results[2].value == .decimal(Decimal(string: "0.5")!))
        #expect(results[3].value == .decimal(Decimal(string: "304.11522630041152263")!))
        #expect(results.allSatisfy { !$0.formula.formulaText.isEmpty && !$0.formula.requiredFields.isEmpty && !$0.formula.unit.isEmpty })
        #expect(RadarFormat.derived(results[0].value) == "0.1")
    }

    @Test("nil operands and zero denominators are explicit unavailable outcomes")
    func unavailableReasons() {
        // Given
        let missing = benchmark(quality: nil, passed: nil, cost: nil, tokens: nil, seconds: nil)
        let zero = benchmark(quality: 80, passed: 0, cost: 0, tokens: 10, seconds: 1)

        // When
        let missingResults = DerivedMetrics.evaluate(model: missing)
        let zeroResults = DerivedMetrics.evaluate(model: zero)

        // Then
        #expect(missingResults.allSatisfy { if case .unavailable(.missingRequiredFields(fields: _)) = $0.value { true } else { false } })
        #expect(zeroResults[0].value == .unavailable(.zeroDenominator(field: "passedTasks")))
        #expect(zeroResults[1].value == .unavailable(.zeroDenominator(field: "passedTasks")))
        #expect(zeroResults[2].value == .unavailable(.zeroDenominator(field: "passedTasks")))
        #expect(zeroResults[3].value == .unavailable(.zeroDenominator(field: "benchmarkCostUSD")))
        #expect(RadarFormat.derived(zeroResults[0].value) == "无法计算：分母 passedTasks 为 0")
    }

    private func benchmark(
        quality: Decimal?, passed: Int?, cost: Decimal?, tokens: Int64?, seconds: Double?
    ) -> ModelBenchmark {
        let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "fixture")
        return .init(
            id: id,
            descriptor: .init(id: id, upstreamName: "Fixture", displayName: "Fixture"),
            qualityScore: quality,
            passedTasks: passed,
            validTasks: passed,
            invalidTasks: 0,
            benchmarkCostUSD: cost,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: tokens,
            elapsedSeconds: seconds,
            agentSteps: nil,
            cacheHitPercent: nil
        )
    }
}
