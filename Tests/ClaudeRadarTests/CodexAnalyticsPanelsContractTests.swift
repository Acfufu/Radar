import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("CodexAnalyticsPanelsContractTests")
struct CodexAnalyticsPanelsContractTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("C3 is a truthful cost-versus-IQ chart with family and accessibility context")
    func costVersusIQContract() throws {
        let panel = try source("Sources/ClaudeRadar/Features/Analytics/CodexCostVersusIQPanel.swift")

        #expect(panel.contains("Text(\"综合成本 vs IQ\")"))
        #expect(panel.contains("越靠左上越高效"))
        #expect(panel.contains("CodexEfficiencyAnalytics.costVersusIQ"))
        #expect(panel.contains("RadarModelIdentity"))
        #expect(panel.contains("模型 \\(point.point.modelName)"))
        #expect(panel.contains("IQ \\(number(point.y))"))
        #expect(panel.contains("综合成本 \\(number(point.x))"))
        #expect(panel.contains(".chartXSelection(value: $selectedCost)"))
        #expect(panel.contains("已选择模型 \\(point.point.modelName)"))
        #expect(panel.contains(".accessibilityIdentifier(\"codex-cost-versus-iq\")"))
        #expect(!panel.contains("综合成本 × IQ"))
    }

    @Test("C5 exposes six metrics three baselines a four-model cap and reconciliation")
    func historyComparisonContract() throws {
        let panel = try source("Sources/ClaudeRadar/Features/Analytics/CodexHistoryComparisonPanel.swift")

        #expect(panel.contains("CodexHistoryMetric.allCases"))
        #expect(panel.contains("CodexHistoryBaseline.allCases"))
        #expect(panel.contains("CodexHistorySelection.limit"))
        #expect(panel.contains("最多选择 4 个模型"))
        #expect(panel.contains("已达 4 个模型上限"))
        #expect(panel.contains("CodexHistorySelection.reconcile"))
        #expect(panel.contains("CodexHistorySelection.setting"))
        #expect(panel.contains("不可用"))
        #expect(panel.contains(".accessibilityIdentifier(\"codex-history-comparison\")"))
    }

    @Test("intelligence center replaces only C3 and C5 slots with native panels")
    func integrationContract() throws {
        let center = try source("Sources/ClaudeRadar/Features/Analytics/CodexIntelligenceCenterView.swift")

        #expect(center.contains("CodexCostVersusIQPanel("))
        #expect(center.contains("CodexHistoryComparisonPanel("))
        #expect(!center.contains("IntelligenceCenterSlot(title: \"综合成本 × IQ\""))
        #expect(!center.contains("IntelligenceCenterSlot(title: \"历史数据比较\""))
        #expect(center.contains("IntelligenceCenterSlot(title: \"IQ 历史数据\""))
        let fixture = try source("Sources/ClaudeRadar/App/DebugUISeed.swift")
        #expect(fixture.contains("state == \"analytics-todo7-gaps\""))
        #expect(fixture.hasPrefix("#if DEBUG"))
    }

    #if DEBUG
    @Test("Debug-only Todo 7 fixture makes revision-gap baselines observably unavailable")
    func revisionGapFixture() async throws {
        let dataRoot = FileManager.default.temporaryDirectory
            .appending(path: "Radar-Todo7-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let environment = AppEnvironment(dataRoot: dataRoot, fixtureMode: .ui, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: dataRoot)
        )

        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .codexRadar,
            state: "analytics-todo7-gaps",
            now: now
        )

        let initialHistory = try await repository.benchmarkHistory(sourceID: .codexRadar)
        let current = try #require(initialHistory.last)
        let rows = CodexHistoryComparison.project(
            current: current,
            history: initialHistory,
            metric: .iq,
            baseline: .hours24
        )

        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .codexRadar,
            state: "analytics-todo7-gaps",
            now: now.addingTimeInterval(3_600)
        )
        let repeatedHistory = try await repository.benchmarkHistory(sourceID: .codexRadar)
        let initialCounts = Dictionary(grouping: initialHistory, by: \.seriesRevision).mapValues(\.count)
        let repeatedCounts = Dictionary(grouping: repeatedHistory, by: \.seriesRevision).mapValues(\.count)

        #expect(initialHistory.count == 6)
        #expect(repeatedHistory.count == initialHistory.count)
        #expect(initialCounts == ["fixture-analytics-r1": 5, "fixture-analytics-r2": 1])
        #expect(repeatedCounts == initialCounts)
        #expect(Set(initialHistory.map(\.seriesRevision)) == ["fixture-analytics-r1", "fixture-analytics-r2"])
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.baseline == nil && $0.delta == nil })
        #expect(current.models.contains { $0.agentSteps == nil })
    }
    #endif

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
}
