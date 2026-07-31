import Foundation
import Testing
@testable import ClaudeRadar

@Suite("CodexHistoryComparisonTests")
struct CodexHistoryComparisonTests {
    private let hour: TimeInterval = 3_600

    @Test("all six metrics preserve valid-task denominators and unavailable values")
    func allMetrics() {
        let current = dataset(at: 30, models: [
            model("sol", "Sol high", iq: 96, cost: 12, valid: 3, elapsed: 540, steps: nil, cache: 75, tokens: 12_000),
            model("zero", "Terra high", iq: 90, cost: 8, valid: 0, elapsed: 120, steps: 7, cache: 50, tokens: 8_000),
        ])
        let history = [dataset(at: 6, models: [
            model("sol", "Sol high", iq: 90, cost: 6, valid: 3, elapsed: 360, steps: 4, cache: 50, tokens: 10_000),
            model("zero", "Terra high", iq: 80, cost: 4, valid: 0, elapsed: 60, steps: 6, cache: 40, tokens: 7_000),
        ])]

        #expect(values(current, history, .iq, "sol") == .init(current: 96, baseline: 90, delta: 6))
        #expect(values(current, history, .averageFeePerValidTask, "sol") == .init(current: 4, baseline: 2, delta: 2))
        #expect(values(current, history, .averageMinutesPerValidTask, "sol") == .init(current: 3, baseline: 2, delta: 1))
        #expect(values(current, history, .agentSteps, "sol") == .init(current: nil, baseline: 4, delta: nil))
        #expect(values(current, history, .cacheHitPercent, "sol") == .init(current: 75, baseline: 50, delta: 25))
        #expect(values(current, history, .totalTokens, "sol") == .init(current: 12_000, baseline: 10_000, delta: 2_000))
        #expect(values(current, history, .averageFeePerValidTask, "zero") == .init(current: nil, baseline: nil, delta: nil))
        #expect(values(current, history, .averageMinutesPerValidTask, "zero") == .init(current: nil, baseline: nil, delta: nil))
        #expect(CodexHistoryMetric.allCases.count == 6)
        #expect(CodexHistoryMetric.default == .iq)
        #expect(CodexHistoryBaseline.default == .hours24)
    }

    @Test("4 12 and 24 hour cutoffs use newest prior point and inclusive six-hour tolerance")
    func cutoffAndToleranceEdges() {
        let current = dataset(at: 30, models: [model("sol", "Sol high", iq: 100)])
        let history = [
            dataset(at: 0, models: [model("sol", "Sol high", iq: 70)]),
            dataset(at: 6, models: [model("sol", "Sol high", iq: 76)]),
            dataset(at: 12, models: [model("sol", "Sol high", iq: 82)]),
            dataset(at: 18, models: [model("sol", "Sol high", iq: 88)]),
            dataset(at: 25, models: [model("sol", "Sol high", iq: 95)]),
            dataset(at: 27, models: [model("sol", "Sol high", iq: 97)]),
        ]

        #expect(values(current, history, .iq, "sol", .hours4).baseline == 95)
        #expect(values(current, history, .iq, "sol", .hours12).baseline == 88)
        #expect(values(current, history, .iq, "sol", .hours24).baseline == 76)

        let inclusive = [dataset(at: 0, models: [model("sol", "Sol high", iq: 70)])]
        #expect(values(current, inclusive, .iq, "sol", .hours24).baseline == 70)
        let outside = [dataset(at: -0.01, models: [model("sol", "Sol high", iq: 75)])]
        #expect(values(current, outside, .iq, "sol", .hours24).baseline == nil)
    }

    @Test("future cross-source cross-revision and conflicting duplicates never become baselines")
    func isolationAndConflict() {
        let current = dataset(at: 30, models: [model("sol", "Sol high", iq: 100)])
        let history = [
            dataset(at: 6, revision: "old", models: [model("sol", "Sol high", iq: 1)]),
            dataset(at: 6, source: .claudeCodeRadar, models: [foreignModel("sol", "Sol high", iq: 2)]),
            dataset(at: 31, models: [model("sol", "Sol high", iq: 3)]),
        ]
        #expect(values(current, history, .iq, "sol").baseline == nil)

        let conflicts = [
            dataset(at: 6, models: [model("sol", "Sol high", iq: 90)]),
            dataset(at: 6, models: [model("sol", "Sol high", iq: 91)]),
            dataset(at: 5, models: [model("sol", "Sol high", iq: 89)]),
        ]
        #expect(values(current, conflicts, .iq, "sol").baseline == nil)

        let missingConflict = [
            dataset(at: 6, models: [model("sol", "Sol high", iq: 90)]),
            dataset(at: 6, models: [model("sol", "Sol high", iq: nil)]),
        ]
        #expect(values(current, missingConflict, .iq, "sol").baseline == nil)

        let identical = [
            dataset(at: 6, models: [model("sol", "Sol high", iq: 90)]),
            dataset(at: 6, models: [model("sol", "Sol high", iq: 90)]),
        ]
        #expect(values(current, identical, .iq, "sol").baseline == 90)
    }

    @Test("semantic time prefers source update and falls back to fetch time")
    func semanticTime() {
        let current = dataset(sourceUpdatedAt: 30, fetchedAt: 100, models: [
            model("sol", "Sol high", iq: 100),
        ])
        let history = [
            dataset(sourceUpdatedAt: nil, fetchedAt: 6, models: [
                model("sol", "Sol high", iq: 90),
            ]),
            dataset(sourceUpdatedAt: 7, fetchedAt: 6, models: [
                model("sol", "Sol high", iq: 91),
            ]),
        ]

        #expect(values(current, history, .iq, "sol").baseline == 90)
    }

    @Test("family defaults and explicit selections are deterministic persistent pruned and capped")
    func selectionSemantics() {
        let rows = [
            model("luna", "Luna high", iq: 89),
            model("gpt-5.6-sol-z-high", "Same", iq: 97),
            model("terra", "Terra high", iq: 92),
            model("gpt", "GPT-5.5 high", iq: 88),
            model("gpt-5.6-sol-a-high", "Same", iq: 97),
            model("nebula", "Nebula high", iq: 110),
        ]
        let available = dataset(at: 30, models: rows)
        let expected = Set(["gpt-5.6-sol-a-high", "terra", "luna", "gpt"].map(id))

        let automatic = CodexHistorySelection.reconcile(state: .init(), current: available)
        let reversed = CodexHistorySelection.reconcile(
            state: .init(),
            current: dataset(at: 30, models: rows.reversed())
        )
        #expect(automatic.selected == expected)
        #expect(reversed.selected == expected)
        #expect(!automatic.isExplicit)

        var explicit = CodexHistorySelection.userChanged([id("nebula")], current: available)
        #expect(explicit.selected == [id("nebula")])
        #expect(explicit.isExplicit)
        explicit = CodexHistorySelection.reconcile(state: explicit, current: available)
        #expect(explicit.selected == [id("nebula")])

        let removed = CodexHistorySelection.setting(
            id("nebula"), selected: false, state: explicit, current: available
        )
        #expect(removed.selected.isEmpty)
        #expect(removed.isExplicit)

        explicit = CodexHistorySelection.reconcile(
            state: explicit,
            current: dataset(at: 31, models: [model("gpt-5.6-sol-a-high", "Same", iq: 97)])
        )
        #expect(explicit.selected.isEmpty)
        #expect(explicit.isExplicit)

        var four = CodexHistorySelectionState(selected: Set(["gpt-5.6-sol-a-high", "terra", "luna", "gpt"].map(id)), isExplicit: true)
        four = CodexHistorySelection.setting(id("nebula"), selected: true, state: four, current: available)
        #expect(four.selected == expected)
        #expect(CodexHistorySelection.canSelect(id("nebula"), state: four, current: available) == false)
        #expect(CodexHistorySelection.canSelect(id("gpt-5.6-sol-a-high"), state: four, current: available))
    }

    @Test("projection is independent of snapshot and model input order")
    func inputOrderIndependence() {
        let models = [
            model("terra", "Terra high", iq: 92, steps: 4),
            model("sol", "Sol high", iq: 96, steps: nil),
        ]
        let current = dataset(at: 30, models: models)
        let history = [
            dataset(at: 6, models: models.map { replacement($0, iq: ($0.id.upstreamKey == "sol" ? 90 : 91)) }),
            dataset(at: 18, models: models.map { replacement($0, iq: ($0.id.upstreamKey == "sol" ? 94 : 93)) }),
        ]
        let forward = CodexHistoryComparison.project(current: current, history: history, metric: .iq, baseline: .hours24)
        let reverse = CodexHistoryComparison.project(
            current: dataset(at: 30, models: models.reversed()),
            history: history.reversed().map { dataset(at: $0.sourceUpdatedAt!.timeIntervalSince1970 / hour, models: $0.models.reversed()) },
            metric: .iq,
            baseline: .hours24
        )
        #expect(forward == reverse)
    }

    @Test("C5 accessibility projects exactly one stable element per logical model row")
    func accessibilityRowsAreOneToOne() {
        let logicalRows = [
            CodexHistoryComparisonRow(
                modelID: id("sol"),
                modelName: "Sol high",
                values: .init(current: 96, baseline: 90)
            ),
            CodexHistoryComparisonRow(
                modelID: id("terra"),
                modelName: "Terra high",
                values: .init(current: nil, baseline: 91)
            ),
        ]

        let accessible = CodexHistoryComparisonAccessibility.rows(
            logicalRows,
            metric: .iq,
            baseline: .hours24
        )

        #expect(accessible.count == logicalRows.count)
        #expect(accessible.map(\.id) == logicalRows.map(\.id))
        #expect(Set(accessible.map(\.id)).count == accessible.count)
        #expect(accessible[0].label == "模型 Sol high，IQ 当前 96.0，24h 前 90.0，变化 +6.0")
        #expect(accessible[1].label == "模型 Terra high，IQ 当前 不可用，24h 前 91.0，变化 不可用")
    }

    @Test("manual data receipt")
    func qaReceipt() {
        let current = dataset(at: 28, models: [
            model("sol", "Sol high", iq: 96, steps: nil),
            model("terra", "Terra high", iq: 93, steps: 6),
            model("luna", "Luna high", iq: 90, steps: 5),
            model("gpt", "GPT-5.5 high", iq: 88, steps: 4),
            model("fifth", "Nebula high", iq: 99, steps: 3),
        ])
        let history: [BenchmarkDataset] = stride(from: 0, through: 24, by: 4).map { offset in
            let step = offset / 4
            return dataset(at: Double(offset), models: [
                model("sol", "Sol high", iq: Decimal(89 + step), steps: nil),
                model("terra", "Terra high", iq: Decimal(86 + step), steps: 6),
                model("luna", "Luna high", iq: Decimal(83 + step), steps: 5),
                model("gpt", "GPT-5.5 high", iq: Decimal(81 + step), steps: 4),
            ])
        }
        let selection = CodexHistorySelection.reconcile(state: .init(), current: current)
        let agent = CodexHistoryComparison.project(current: current, history: history, metric: .agentSteps, baseline: .hours24)
        var fifth = CodexHistorySelectionState(selected: selection.selected, isExplicit: true)
        fifth = CodexHistorySelection.setting(id("fifth"), selected: true, state: fifth, current: current)

        if ProcessInfo.processInfo.environment["RADAR_QA_RECEIPT"] == "1" {
            print("selected IDs: \(selection.selected.map(\.upstreamKey).sorted().joined(separator: ","))")
            for row in CodexHistoryComparison.project(current: current, history: history, metric: .iq, baseline: .hours24) {
                let currentText = row.current.map { String($0) } ?? "unavailable"
                let baselineText = row.baseline.map { String($0) } ?? "unavailable"
                print("IQ/24h \(row.modelID.upstreamKey): current=\(currentText) baseline=\(baselineText)")
            }
            let agentText = agent.first { $0.modelID == id("sol") }?.current == nil ? "unavailable" : "available"
            print("Agent steps sol: \(agentText)")
            print("rejected fifth selection: \(!fifth.selected.contains(id("fifth")))")
        }
        #expect(!fifth.selected.contains(id("fifth")))
    }

    private func values(
        _ current: BenchmarkDataset,
        _ history: [BenchmarkDataset],
        _ metric: CodexHistoryMetric,
        _ key: String,
        _ baseline: CodexHistoryBaseline = .hours24
    ) -> CodexHistoryValues {
        CodexHistoryComparison.project(current: current, history: history, metric: metric, baseline: baseline)
            .first { $0.modelID == id(key) }!.values
    }

    private func dataset<S: Sequence>(
        at hours: Double,
        source: RadarSourceID = .codexRadar,
        revision: String = "r1",
        models: S
    ) -> BenchmarkDataset where S.Element == ModelBenchmark {
        let date = Date(timeIntervalSince1970: hours * hour)
        return .init(
            sourceID: source,
            sourceUpdatedAt: date,
            fetchedAt: date,
            benchmarkName: "fixture",
            benchmarkVersion: "1",
            seriesRevision: revision,
            models: Array(models)
        )
    }

    private func dataset<S: Sequence>(
        sourceUpdatedAt hours: Double?,
        fetchedAt fetchedHours: Double,
        models: S
    ) -> BenchmarkDataset where S.Element == ModelBenchmark {
        .init(
            sourceID: .codexRadar,
            sourceUpdatedAt: hours.map { Date(timeIntervalSince1970: $0 * hour) },
            fetchedAt: Date(timeIntervalSince1970: fetchedHours * hour),
            benchmarkName: "fixture",
            benchmarkVersion: "1",
            seriesRevision: "r1",
            models: Array(models)
        )
    }

    private func model(
        _ key: String,
        _ name: String,
        iq: Decimal?,
        cost: Decimal? = 1,
        valid: Int? = 1,
        elapsed: Double? = 60,
        steps: Int? = 1,
        cache: Decimal? = 1,
        tokens: Int64? = 1
    ) -> ModelBenchmark {
        benchmark(id(key), name, iq, cost, valid, elapsed, steps, cache, tokens)
    }

    private func foreignModel(_ key: String, _ name: String, iq: Decimal?) -> ModelBenchmark {
        benchmark(ModelID(sourceID: .claudeCodeRadar, upstreamKey: key), name, iq, 1, 1, 60, 1, 1, 1)
    }

    private func benchmark(
        _ modelID: ModelID,
        _ name: String,
        _ iq: Decimal?,
        _ cost: Decimal?,
        _ valid: Int?,
        _ elapsed: Double?,
        _ steps: Int?,
        _ cache: Decimal?,
        _ tokens: Int64?
    ) -> ModelBenchmark {
        .init(
            id: modelID,
            descriptor: .init(id: modelID, upstreamName: name, displayName: name),
            qualityScore: iq,
            passedTasks: nil,
            validTasks: valid,
            invalidTasks: nil,
            benchmarkCostUSD: cost,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: tokens,
            elapsedSeconds: elapsed,
            agentSteps: steps,
            cacheHitPercent: cache
        )
    }

    private func replacement(_ model: ModelBenchmark, iq: Decimal) -> ModelBenchmark {
        benchmark(model.id, model.descriptor.displayName, iq, model.benchmarkCostUSD, model.validTasks, model.elapsedSeconds, model.agentSteps, model.cacheHitPercent, model.totalTokens)
    }

    private func id(_ key: String) -> ModelID {
        .init(sourceID: .codexRadar, upstreamKey: key)
    }
}
