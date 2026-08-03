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
        let rootView = try source("OverviewView.swift")
        let officialRoot = try source("OfficialOverviewSections.swift")
        let official = try officialOverviewImplementation()

        #expect(rootView.contains("OfficialOverviewSections(projection: projection, history: history)"))
        #expect(rootView.range(of: "OfficialOverviewSections")!.lowerBound < rootView.range(of: "if projection.rows.isEmpty")!.lowerBound)
        #expect(officialRoot.contains("@State var codexIQChartSource: CodexRenderedIQHistoryChartSource = .official24h"))
        #expect(officialRoot.contains("@State var officialIQSelection: CodexRenderedIQHistoryPresentation.Selection = .aggregate"))
        #expect(official.contains("Text(\"官网 24h\").tag(CodexRenderedIQHistoryChartSource.official24h)"))
        #expect(official.contains("Text(\"本地拟合\").tag(CodexRenderedIQHistoryChartSource.localFit)"))
        #expect(official.contains("Text(\"综合\").tag(CodexRenderedIQHistoryPresentation.Selection.aggregate)"))
        #expect(rootView.contains("OverviewLocalSections("))
        #expect(!official.contains("if projection.source.id != .codexRadar"))
    }

    @Test("official chart is ordinal, straight, attributed, and summarized without chart marks")
    func officialChartContract() throws {
        let view = try officialOverviewImplementation()
        let official = try #require(section("var officialIQHistoryTrend", in: view))
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
        let official = try officialOverviewImplementation()
        let localInsights = try source("LocalOverviewInsightSections.swift")
        let localAnalytics = try source("LocalOverviewAnalytics.swift")
        #expect(official.contains("case .localFit:"))
        #expect(official.contains("LocalIQTrendChart(projection: projection, history: history)"))
        #expect(localInsights.contains("local-iq-fit-section"))
        #expect(localAnalytics.contains("projection.localDeclineSignals(history: history)"))
    }

    private func source(_ filename: String) throws -> String {
        try String(
            contentsOf: root.appending(path: "Sources/ClaudeRadar/Features/Overview/\(filename)"),
            encoding: .utf8
        )
    }

    private func officialOverviewImplementation() throws -> String {
        try ["OfficialOverviewSections.swift", "OfficialOverviewTrendSections.swift"]
            .map(source)
            .joined(separator: "\n")
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
