import Foundation
import SwiftData
import Testing
@testable import AIRadar

@Suite("CodexAnalyticsPanelsContractTests")
struct CodexAnalyticsPanelsContractTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("C3 is a truthful cost-versus-IQ chart with family and accessibility context")
    func costVersusIQContract() throws {
        let panel = try source("Sources/AIRadar/Features/Analytics/CodexCostVersusIQPanel.swift")

        #expect(panel.contains("Text(\"综合成本 × IQ\")"))
        #expect(panel.contains("横轴为当前数据集内归一化的综合成本，纵轴为 IQ；越靠左上越高效。"))
        #expect(panel.contains("CodexEfficiencyAnalytics.costVersusIQ"))
        #expect(panel.contains("RadarModelIdentity"))
        #expect(panel.contains("模型 \\(point.point.modelName)"))
        #expect(panel.contains("IQ \\(number(point.y))"))
        #expect(panel.contains("综合成本 \\(number(point.x))"))
        #expect(panel.contains(".chartXSelection(value: $selectedCost)"))
        #expect(panel.contains("overflowResolution: .init(x: .fit, y: .fit)"))
        #expect(!panel.contains("overflowResolution: .init(x: .fit, y: .disabled)"))
        #expect(panel.contains("已选择模型 \\(point.point.modelName)"))
        #expect(panel.contains(".accessibilityIdentifier(\"codex-cost-versus-iq\")"))
    }

    @Test("C5 exposes six metrics three baselines a four-model cap and reconciliation")
    func historyComparisonContract() throws {
        let panel = try source("Sources/AIRadar/Features/Analytics/CodexHistoryComparisonPanel.swift")

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

    @Test("C2 and C5 expose one native horizontal-overflow affordance")
    func horizontalOverflowAffordanceContract() throws {
        let matrix = try source("Sources/AIRadar/Features/Analytics/CodexEfficiencyMatrixPanel.swift")
        let comparison = try source("Sources/AIRadar/Features/Analytics/CodexHistoryComparisonPanel.swift")

        for panel in [matrix, comparison] {
            #expect(panel.contains("RadarStyle.horizontalScrollAffordance"))
            #expect(panel.contains(".scrollIndicators(.visible, axes: .horizontal)"))
        }
        #expect(matrix.contains(".accessibilityIdentifier(\"codex-efficiency-horizontal-affordance\")"))
        #expect(comparison.contains(".accessibilityIdentifier(\"codex-history-horizontal-affordance\")"))
    }

    @Test("C2 C3 and C5 consume centralized analytics style tokens")
    func analyticsStyleTokenContract() throws {
        let matrix = try source("Sources/AIRadar/Features/Analytics/CodexEfficiencyMatrixPanel.swift")
        let scatter = try source("Sources/AIRadar/Features/Analytics/CodexCostVersusIQPanel.swift")
        let comparison = try source("Sources/AIRadar/Features/Analytics/CodexHistoryComparisonPanel.swift")

        #expect(matrix.contains("RadarStyle.analyticsLayout"))
        #expect(!matrix.contains(".frame(width: 104"))
        #expect(!matrix.contains(".frame(width: 216"))
        #expect(!matrix.contains(".frame(minHeight: 112"))
        #expect(scatter.contains("RadarStyle.analyticsColors(for: colorScheme)"))
        #expect(!scatter.contains("case 0: .green"))
        #expect(!scatter.contains("case 1: .purple"))
        #expect(comparison.contains("RadarStyle.analyticsLayout"))
        #expect(!comparison.contains(".frame(maxWidth: 260"))
        #expect(!comparison.contains(".frame(width: 130"))
        #expect(!comparison.contains("HStack(spacing: 18)"))
    }

    @Test("intelligence center composes C3 C4 and C5 native panels")
    func integrationContract() throws {
        // Spec §4.2: the former intelligence center composition is re-anchored
        // onto the efficiency-PK and history-comparison pages; the retired
        // intelligence-center view keeps compiling only for legacy routes.
        let efficiency = try source("Sources/AIRadar/Features/Codex/CodexStationPages.swift")

        #expect(efficiency.contains("CodexCostVersusIQPanel("))
        #expect(efficiency.contains("CodexEfficiencyMatrixPanel("))
        #expect(efficiency.contains("CodexScenarioRecommendationsPanel("))
        #expect(efficiency.contains("CodexHistoryComparisonPanel("))
        #expect(efficiency.contains("CodexIQHistorySmallMultiplesPanel("))
        let c3Index = try #require(efficiency.range(of: "CodexCostVersusIQPanel(")?.lowerBound)
        let matrixIndex = try #require(efficiency.range(of: "CodexEfficiencyMatrixPanel(")?.lowerBound)
        let c2Index = try #require(efficiency.range(of: "CodexScenarioRecommendationsPanel(")?.lowerBound)
        let historyIndex = try #require(efficiency.range(of: "struct CodexHistoryComparisonPage")?.lowerBound)
        let smallMultiplesIndex = try #require(efficiency.range(of: "CodexIQHistorySmallMultiplesPanel(")?.lowerBound)
        // Efficiency PK: cost-versus-IQ then matrix then scenario cards.
        #expect(c3Index < matrixIndex)
        #expect(matrixIndex < c2Index)
        // History comparison page follows and hosts the small multiples.
        #expect(c2Index < historyIndex)
        #expect(historyIndex < smallMultiplesIndex)
        let fixture = try source("Sources/AIRadar/App/DebugUISeed.swift")
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
