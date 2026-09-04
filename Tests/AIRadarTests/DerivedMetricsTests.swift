import Foundation
import Testing
@testable import AIRadar

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

    @Test("local intelligence efficiency uses per-valid-task averages and current-dataset normalization")
    func intelligenceEfficiency() {
        let priceWeighted = benchmark(
            key: "price",
            quality: 100,
            passed: 1,
            valid: 2,
            cost: 5,
            tokens: nil,
            seconds: 1_200
        )
        let timeWeighted = benchmark(
            key: "time",
            quality: 80,
            passed: 1,
            valid: 1,
            cost: 1,
            tokens: nil,
            seconds: 810
        )

        let points = IntelligenceEfficiency.points(models: [priceWeighted, timeWeighted])

        #expect(points.count == 2)
        #expect(points.allSatisfy { abs($0.combinedCostIndex - 100) < 0.000_000_1 })
        #expect(points.first { $0.id.upstreamKey == "price" }?.averageCostUSD == 2.5)
        #expect(points.first { $0.id.upstreamKey == "price" }?.averageMinutes == 10)
        #expect(points.first { $0.id.upstreamKey == "time" }?.averageMinutes == 13.5)
    }

    @Test("local intelligence efficiency omits nil zero and negative inputs")
    func intelligenceEfficiencyUnavailable() {
        let missing = benchmark(
            key: "missing",
            quality: 80,
            passed: 1,
            valid: 1,
            cost: nil,
            tokens: nil,
            seconds: nil
        )
        let zero = benchmark(
            key: "zero",
            quality: 80,
            passed: 1,
            valid: 0,
            cost: 1,
            tokens: nil,
            seconds: 1
        )
        let negativeQuality = benchmark(
            key: "negative-quality",
            quality: -1,
            passed: 1,
            valid: 1,
            cost: 1,
            tokens: nil,
            seconds: 1
        )
        let negativeCost = benchmark(
            key: "negative-cost",
            quality: 80,
            passed: 1,
            valid: 1,
            cost: -1,
            tokens: nil,
            seconds: 1
        )
        let negativeTime = benchmark(
            key: "negative-time",
            quality: 80,
            passed: 1,
            valid: 1,
            cost: 1,
            tokens: nil,
            seconds: -1
        )
        let missingValidTasks = benchmark(
            key: "missing-valid",
            quality: 80,
            passed: 1,
            valid: nil,
            cost: 1,
            tokens: nil,
            seconds: 1,
            defaultValidTasksToPassed: false
        )

        #expect(IntelligenceEfficiency.points(
            models: [missing, zero, negativeQuality, negativeCost, negativeTime, missingValidTasks]
        ).isEmpty)
    }

    private func benchmark(
        key: String = "fixture",
        quality: Decimal?,
        passed: Int?,
        valid: Int? = nil,
        cost: Decimal?,
        tokens: Int64?,
        seconds: Double?,
        defaultValidTasksToPassed: Bool = true
    ) -> ModelBenchmark {
        let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: key)
        return .init(
            id: id,
            descriptor: .init(id: id, upstreamName: "Fixture", displayName: "Fixture"),
            qualityScore: quality,
            passedTasks: passed,
            validTasks: defaultValidTasksToPassed ? (valid ?? passed) : valid,
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
