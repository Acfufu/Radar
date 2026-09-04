import Foundation
import Testing
@testable import AIRadar

@Suite("CodexRenderedIQHistoryProjectionTests")
struct CodexRenderedIQHistoryProjectionTests {
    @Test("official aggregate is default and each model is selected alone")
    func aggregateAndModelSelection() {
        let projected = presentation(state: segment(value: history()))

        #expect(projected?.state == .fresh)
        #expect(projected?.selection == .aggregate)
        #expect(projected?.selectedSeries?.seriesKey == "aggregate")
        #expect(projected?.series.map(\.seriesKey) == ["aggregate", "model:sol", "model:codex"])
        #expect(projected?.modelChoices.map(\.seriesKey) == ["model:sol", "model:codex"])

        let selected = presentation(state: segment(value: history()), selection: .model("model:sol"))
        #expect(selected?.selection == .model("model:sol"))
        #expect(selected?.selectedSeries?.displayName == "GPT-5.6 Sol")
        #expect(selected?.selectedSeries?.points.count == 24)
        #expect(selected?.selectedSeries?.points.map(\.ordinal) == Array(0...23))
        #expect(selected?.selectedSeries?.points.map(\.sourceTimeLabel) == (0...23).map { "07/27 \($0)" })
        #expect(selected?.selectedSeries?.points.contains { $0.sourceTimeLabel == "07/27 0" && $0.iq == 100 } == true)
    }

    @Test("selection reconciliation never overlays, joins, or fabricates point dates")
    func selectionReconciliationAndOrdinalPoints() {
        let projected = presentation(
            state: segment(value: history()),
            selection: .model("model:missing")
        )

        #expect(projected?.selection == .aggregate)
        #expect(projected?.selectedSeries?.points.count == 24)
        #expect(projected?.selectedSeries?.points.map(\.ordinal) == Array(0...23))
        #expect(CodexRenderedIQHistoryChartSource.allCases == [.official24h, .localFit])
        #expect(CodexRenderedIQHistoryChartSource.official24h.rawValue == "官网 24h")
        #expect(CodexRenderedIQHistoryChartSource.localFit.rawValue == "本地拟合")
    }

    @Test("official projection distinguishes loading fresh stale LKG and unavailable states")
    func stateMatrix() {
        let value = history()
        #expect(CodexRenderedIQHistoryPresentation.State.allCases.count == 7)
        #expect(presentation(state: nil)?.state == .loading)
        #expect(presentation(state: segment(value: value))?.state == .fresh)
        #expect(presentation(state: segment(value: value, stale: true))?.state == .staleLastKnownGood)
        #expect(presentation(state: segment(value: value, error: .init(kind: .network, message: "offline")))?.state == .lastKnownGoodWithError)
        #expect(presentation(state: segment(error: .init(kind: .validation, message: "Rendered IQ history schema drift")))?.state == .schemaDriftWithoutLastKnownGood)
        #expect(presentation(state: segment(error: .init(kind: .validation, message: "challenge page")))?.state == .challengeWithoutLastKnownGood)
        #expect(presentation(state: segment(error: .init(kind: .network, message: "offline")))?.state == .unavailableWithoutLastKnownGood)
    }

    @Test("official projection is Codex-only, independent from empty benchmark and local fit")
    func sourceAndLocalIndependence() {
        let official = history()
        let localHistory = [benchmark(at: 0, quality: 100), benchmark(at: 12 * 3_600, quality: 99), benchmark(at: 24 * 3_600, quality: 98)]
        let emptyCodex = workspace(sourceID: .codexRadar, historyState: segment(value: official))
        let codex = workspace(
            sourceID: .codexRadar,
            historyState: segment(value: official),
            benchmarkState: segment(value: localHistory.last!)
        )
        #expect(emptyCodex.rows.isEmpty)
        #expect(emptyCodex.renderedIQHistoryPresentation?.state == .fresh)

        for sourceID in [RadarSourceID.claudeCodeRadar, .sweBenchVerified] {
            #expect(workspace(sourceID: sourceID, historyState: segment(value: official)).renderedIQHistoryPresentation == nil)
        }

        #expect(codex.renderedIQHistoryPresentation?.selectedSeries?.displayName == "官网综合")
        #expect(codex.localDeclineSignals(history: localHistory).map(\.modelName) == ["Local-only model"])
        #expect(WorkspaceProjection.trendSeries(history: localHistory, metric: .quality, selected: [localHistory[0].models[0].id]).flatMap(\.points).count == 3)
    }

    @Test("freshness provenance and accessibility preserve source labels without inferred dates")
    func provenanceAndAccessibility() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let refreshedAt = Date(timeIntervalSince1970: 200)
        let projected = presentation(state: segment(value: history(capturedAt: capturedAt), successfulAt: refreshedAt))

        #expect(projected?.lastSuccessfulAt == refreshedAt)
        #expect(projected?.capturedAt == capturedAt)
        #expect(projected?.attribution == "数据来自分布式雷达 deng.codexradar.com · powered by codexradar")
        #expect(projected?.backlink == "https://deng.codexradar.com/")
        #expect(projected?.sectionAccessibilityIdentifier == "codex-rendered-iq-history-section")
        #expect(projected?.stateAccessibilityIdentifier == "codex-rendered-iq-history-state-fresh")
        #expect(projected?.selectedSeriesAccessibilityIdentifier == "codex-rendered-iq-history-series-aggregate")
        #expect(projected?.selectedSeriesAccessibilityLabel.contains("官网综合") == true)
        #expect(projected?.selectedSeriesAccessibilityLabel.contains("24 个点") == true)
        #expect(projected?.selectedSeriesAccessibilityLabel.contains("07/27 0") == true)
        #expect(projected?.selectedSeriesAccessibilityLabel.contains("deng.codexradar.com") == true)
    }

    private func presentation(
        state: SegmentState<CodexRenderedIQHistorySnapshot>?,
        selection: CodexRenderedIQHistoryPresentation.Selection = .aggregate
    ) -> CodexRenderedIQHistoryPresentation? {
        CodexRenderedIQHistoryPresentation(sourceID: .codexRadar, state: state, selection: selection)
    }

    private func workspace(
        sourceID: RadarSourceID,
        historyState: SegmentState<CodexRenderedIQHistorySnapshot>,
        benchmarkState: SegmentState<BenchmarkDataset>? = nil
    ) -> WorkspaceProjection {
        let descriptor: RadarSourceDescriptor = switch sourceID {
        case .codexRadar: CodexRadarConfiguration.descriptor
        case .sweBenchVerified: SWEBenchConfiguration.descriptor
        default: ClaudeRadarConfiguration.descriptor
        }
        return WorkspaceProjection(
            sync: .init(
                supportLevel: .authorized,
                benchmark: benchmarkState ?? segment(),
                community: segment(),
                sourceStatus: segment()
            ),
            lifecycle: .running,
            supportLevel: .authorized,
            source: descriptor,
            renderedIQHistoryState: historyState
        )
    }

    private func segment<T: Sendable>(
        value: T? = nil,
        error: SegmentError? = nil,
        stale: Bool = false,
        successfulAt: Date? = nil
    ) -> SegmentState<T> {
        SegmentState(
            value: value,
            lastSuccessfulAt: successfulAt ?? value.map { _ in Date(timeIntervalSince1970: 200) },
            lastAttemptedAt: Date(timeIntervalSince1970: 300),
            error: error,
            isStale: stale
        )
    }

    private func history(capturedAt: Date = Date(timeIntervalSince1970: 100)) -> CodexRenderedIQHistorySnapshot {
        let series = [
            series(order: 0, key: "aggregate", name: "官网综合", startIQ: 90),
            series(order: 1, key: "model:sol", name: "GPT-5.6 Sol", startIQ: 100),
            series(order: 2, key: "model:codex", name: "GPT-5.5 Codex", startIQ: 80),
        ]
        return CodexRenderedIQHistorySnapshot(
            sourceID: .codexRadar,
            parserRevision: "codex-radar-rendered-iq-history-v1",
            finalOrigin: "https://deng.codexradar.com",
            capturedAt: capturedAt,
            series: series,
            semanticFingerprint: "fixture"
        )
    }

    private func series(order: Int, key: String, name: String, startIQ: Double) -> CodexRenderedIQHistorySeries {
        .init(
            sourceOrder: order,
            seriesKey: key,
            displayName: name,
            points: (0...23).map { .init(sourceOrder: $0, sourceTimeLabel: "07/27 \($0)", iq: startIQ - Double($0)) }
        )
    }

    private func benchmark(at time: TimeInterval, quality: Decimal) -> BenchmarkDataset {
        let id = ModelID(sourceID: .codexRadar, upstreamKey: "local-only")
        let model = ModelBenchmark(
            id: id,
            descriptor: .init(id: id, upstreamName: "Local-only model", displayName: "Local-only model"),
            qualityScore: quality,
            passedTasks: 1,
            validTasks: 1,
            invalidTasks: nil,
            benchmarkCostUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: nil,
            elapsedSeconds: nil,
            agentSteps: nil,
            cacheHitPercent: nil
        )
        let date = Date(timeIntervalSince1970: time)
        return .init(sourceID: .codexRadar, sourceUpdatedAt: date, fetchedAt: date, benchmarkName: "Fixture", benchmarkVersion: "1", seriesRevision: "r1", models: [model])
    }
}
