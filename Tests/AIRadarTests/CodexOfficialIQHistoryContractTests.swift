import Foundation
import Testing
@testable import AIRadar

/// v0.4.0 official IQ trend contract tests (spec §6 v1.1, ADR-0002): the
/// ie.json `history[]` mapping, breakpoint tolerance, state semantics, the
/// preserved official-vs-local toggle, and zero deng residue.
@Suite("CodexOfficialIQHistoryContractTests")
struct CodexOfficialIQHistoryContractTests {
    private func entry(_ at: String, _ tiers: (model: String, effort: String, iq: Double?)...) -> IntelligenceEfficiencyDataset.HistoryEntry {
        IntelligenceEfficiencyDataset.HistoryEntry(
            at: at,
            points: tiers.map { tier in
                .init(model: tier.model, effort: tier.effort, iq: tier.iq)
            }
        )
    }

    private func state(history: [IntelligenceEfficiencyDataset.HistoryEntry], stale: Bool = false, errorMessage: String? = nil) -> SegmentState<IntelligenceEfficiencyDataset> {
        let dataset = IntelligenceEfficiencyDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100),
            history: history
        )
        return SegmentState(
            value: history.isEmpty ? nil : dataset,
            lastSuccessfulAt: history.isEmpty ? nil : Date(timeIntervalSince1970: 90),
            lastAttemptedAt: Date(timeIntervalSince1970: 100),
            error: errorMessage.map { SegmentError(kind: .network, message: $0) },
            isStale: stale
        )
    }

    @Test("series map from the latest observation roster with breakpoint tolerance")
    func seriesMapping() throws {
        let history = [
            entry("2026-09-01T00:00:00+08:00", ("gpt-6-astra", "ultra", 108.0), ("gpt-5.6-sol", "xhigh", 100.0)),
            entry("2026-09-02T00:00:00+08:00", ("gpt-6-astra", "ultra", nil), ("gpt-5.6-sol", "xhigh", 100.5)),
            entry("2026-09-03T00:00:00+08:00", ("gpt-6-astra", "ultra", 109.0), ("gpt-5.6-sol", "xhigh", nil)),
        ]
        let presentation = try #require(OfficialIQHistoryPresentation(
            sourceID: .codexRadar,
            state: state(history: history)
        ))

        #expect(presentation.state == .fresh)
        #expect(presentation.observationCount == 3)
        // Roster order follows the latest observation's point order.
        #expect(presentation.series.map(\.seriesKey) == ["gpt-6-astra@ultra", "gpt-5.6-sol@xhigh"])

        // Breakpoint tolerance: missing tiers yield no point and no invented
        // bridge values (spec §6 v1.1 frozen rendering semantics).
        let astra = try #require(presentation.series.first)
        #expect(astra.points.map(\.ordinal) == [0, 2])
        #expect(astra.points.map(\.iq) == [108.0, 109.0])
        let sol = presentation.series[1]
        #expect(sol.points.map(\.ordinal) == [0, 1])
        #expect(presentation.selectedSeries?.seriesKey == "gpt-6-astra@ultra")
    }

    @Test("state semantics follow the shared segment state")
    func stateSemantics() throws {
        // A nil segment still yields a loading presentation for the card.
        let nilState = try #require(OfficialIQHistoryPresentation(sourceID: .codexRadar, state: nil))
        #expect(nilState.state == .loading)
        let empty = try #require(OfficialIQHistoryPresentation(sourceID: .codexRadar, state: state(history: [])))
        #expect(empty.state == .loading)
        #expect(empty.series.isEmpty)

        let stale = try #require(OfficialIQHistoryPresentation(
            sourceID: .codexRadar,
            state: state(history: [entry("a", ("m", "high", 80.0))], stale: true)
        ))
        #expect(stale.state == .staleLastKnownGood)

        let errored = try #require(OfficialIQHistoryPresentation(
            sourceID: .codexRadar,
            state: state(history: [entry("a", ("m", "high", 80.0))], errorMessage: "offline")
        ))
        #expect(errored.state == .lastKnownGoodWithError)
        #expect(errored.errorMessage == "offline")

        let unavailable = try #require(OfficialIQHistoryPresentation(
            sourceID: .codexRadar,
            state: state(history: [], errorMessage: "offline")
        ))
        #expect(unavailable.state == .unavailableWithoutLastKnownGood)

        #expect(OfficialIQHistoryPresentation(sourceID: .claudeCodeRadar, state: state(history: [entry("a", ("m", "high", 80.0))])) == nil)
    }

    @Test("the re-sourced card keeps the toggle, attribution, and independence wording")
    func cardContract() throws {
        let trend = try String(
            contentsOf: URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/AIRadar/Features/Overview/OfficialOverviewTrendSections.swift"),
            encoding: .utf8
        )
        // Toggle preserved: official side + untouched local-fit side.
        #expect(trend.contains("OfficialIQChartSource.officialTrend"))
        #expect(trend.contains("LocalIQTrendChart(projection: projection, history: history)"))
        #expect(trend.contains("官网曲线与本地拟合独立"))
        // Sourced from the ie plane; no deng strings anywhere in the card.
        #expect(trend.contains("officialIQHistoryPresentation"))
        #expect(!trend.lowercased().contains("deng"))
        #expect(!trend.contains("24h"))

        let workspace = try String(
            contentsOf: URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/AIRadar/Features/Workspace/CodexRenderedWorkspacePresentation.swift"),
            encoding: .utf8
        )
        #expect(workspace.contains("struct OfficialIQHistoryPresentation"))
        // The only 'deng' mention is the retirement provenance comment.
        let dengLines = workspace.split(separator: "\n").filter { $0.lowercased().contains("deng") }
        #expect(dengLines.count == 1)
        #expect(dengLines.first?.contains("retired") == true)
    }
}
