import Foundation
import Testing

@Suite("CodexRenderedIQHistoryOverviewContractTests")
struct CodexRenderedIQHistoryOverviewContractTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("Codex Overview keeps the official 24h trend outside benchmark emptiness")
    func officialTrendPlacementAndDefaults() throws {
        let view = try overview()
        #expect(view.contains("@State private var codexIQChartSource: CodexRenderedIQHistoryChartSource = .official24h"))
        #expect(view.contains("@State private var officialIQSelection: CodexRenderedIQHistoryPresentation.Selection = .aggregate"))
        #expect(view.contains("officialIQHistoryTrend"))
        #expect(view.range(of: "officialIQHistoryTrend")!.lowerBound < view.range(of: "if projection.rows.isEmpty")!.lowerBound)
        #expect(view.contains("Text(\"官网 24h\").tag(CodexRenderedIQHistoryChartSource.official24h)"))
        #expect(view.contains("Text(\"本地拟合\").tag(CodexRenderedIQHistoryChartSource.localFit)"))
        #expect(view.contains("Text(\"综合\").tag(CodexRenderedIQHistoryPresentation.Selection.aggregate)"))
        #expect(view.contains("} else {\n                    signalHero\n                    localInsights"))
        #expect(!view.contains("if projection.source.id != .codexRadar"))
    }

    @Test("official chart is ordinal, straight, attributed, and summarized without chart marks")
    func officialChartContract() throws {
        let view = try overview()
        let official = try #require(section("private var officialIQHistoryTrend", in: view))
        #expect(official.contains("LineMark("))
        #expect(official.contains(".interpolationMethod(.linear)"))
        #expect(official.contains("PointMark("))
        #expect(official.contains("point.ordinal"))
        #expect(official.contains(".chartXScale(domain: 0...23)"))
        #expect(!official.contains(".catmullRom"))
        #expect(!official.contains("AreaMark("))
        #expect(official.contains("Link(presentation.attribution"))
        #expect(official.contains("与本地 IQ 拟合独立"))
        #expect(official.contains("officialSeriesAccessibilitySummary"))
        #expect(official.contains("codex-rendered-iq-history-source"))
        #expect(official.contains("officialSeriesAccessibilityIdentifier"))
    }

    @Test("local fit remains manual and independent")
    func localFitContract() throws {
        let view = try overview()
        #expect(view.contains("case .localFit:"))
        #expect(view.contains("localTrendChart"))
        #expect(view.contains("local-iq-fit-section"))
        #expect(view.contains("projection.localDeclineSignals(history: history)"))
    }

    private func overview() throws -> String {
        try String(
            contentsOf: root.appending(path: "Sources/ClaudeRadar/Features/Overview/OverviewView.swift"),
            encoding: .utf8
        )
    }

    private func section(_ marker: String, in text: String) -> String? {
        guard let start = text.range(of: marker) else { return nil }
        let remainder = text[start.lowerBound...]
        guard let end = remainder.range(of: "    private var localTrendChart") else {
            return String(remainder)
        }
        return String(remainder[..<end.lowerBound])
    }
}
