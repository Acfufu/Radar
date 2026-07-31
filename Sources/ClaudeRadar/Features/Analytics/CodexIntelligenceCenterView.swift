import SwiftUI

struct CodexIntelligenceCenterView: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(
                    title: "智力中心",
                    subtitle: "\(projection.source.displayName) · 当前数据与 \(history.count) 个 Radar 本地快照"
                )
                if let supportState = projection.benchmarkPresentation.supportState {
                    StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
                }
                if let healthState = projection.benchmarkPresentation.healthState, healthState != .fresh {
                    StateBanner(
                        state: healthState,
                        error: projection.benchmarkPresentation.error,
                        sourceName: projection.source.displayName
                    )
                }
                CodexScenarioRecommendationsPanel(
                    recommendations: scenarioRecommendations
                )
                CodexEfficiencyMatrixPanel(
                    cells: efficiencyCells,
                    sourceUpdatedAt: projection.updatedAt,
                    provenance: "Radar 按 Codex Radar 公开摘要计算"
                )
                CodexCostVersusIQPanel(
                    points: projection.intelligenceEfficiency,
                    sourceUpdatedAt: projection.updatedAt,
                    seriesRevision: projection.sync?.benchmark.value?.seriesRevision,
                    provenance: "Radar 按 Codex Radar 公开摘要计算；不跨来源或版本比较"
                )
                CodexHistoryComparisonPanel(
                    current: projection.sync?.benchmark.value,
                    history: history,
                    provenance: "C4-C5 使用 Codex Radar 的 Radar 本地持久化历史；不跨来源或版本比较"
                )
                CodexIQHistorySmallMultiplesPanel(
                    history: history,
                    provenance: "C4-C5 使用 Codex Radar 的 Radar 本地持久化历史；不跨来源或版本比较"
                )
                Text("C1-C3 由 Radar 从现有 Codex Radar 公开摘要在本地派生；C4-C5 使用 Radar 本地持久化历史。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(projection.source.attributionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("数据来源：\(projection.source.attributionText)")
            }
            .radarPage()
        }
        .navigationTitle("智力中心")
    }

    private var scenarioRecommendations: CodexScenarioRecommendations {
        CodexScenarioRecommendations.project(points: projection.intelligenceEfficiency)
    }

    private var efficiencyCells: [CodexEfficiencyMatrixCell] {
        CodexEfficiencyAnalytics.matrix(points: projection.intelligenceEfficiency)
    }
}
