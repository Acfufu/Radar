import Charts
import SwiftUI

struct ModelDetailView: View {
    let row: WorkspaceModelRow
    let sourceName: String
    let revision: String
    let paretoPreset: ParetoPreset
    let paretoClassification: ParetoClassification
    let history: [BenchmarkDataset]

    var body: some View {
        Form {
            Section("模型") {
                LabeledContent("名称", value: row.name)
                LabeledContent("来源", value: sourceName)
                LabeledContent("seriesRevision", value: revision)
            }
            Section("单模型历史") {
                Text("仅显示所选模型；seriesRevision 变化时断线。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if historySeries.isEmpty {
                    Text("暂无历史数据").foregroundStyle(.secondary)
                } else {
                    scaledHistoryChart
                        .chartLegend(position: .bottom)
                        .frame(minHeight: 190)
                    Text(historySeries.map { "\($0.seriesRevision)：\($0.points.count) 个点" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section("原始指标") {
                metric("质量分", RadarFormat.decimal(row.benchmark.qualityScore))
                metric("通过 / 有效", "\(RadarFormat.integer(row.benchmark.passedTasks)) / \(RadarFormat.integer(row.benchmark.validTasks))")
                metric("成本", row.benchmark.benchmarkCostUSD.map { "$" + RadarFormat.decimal($0) } ?? "—")
                metric("Token", RadarFormat.integer(row.benchmark.totalTokens))
                metric("耗时", RadarFormat.seconds(row.benchmark.elapsedSeconds))
                metric("Agent Steps", RadarFormat.integer(row.benchmark.agentSteps))
                metric("Cache", RadarFormat.decimal(row.benchmark.cacheHitPercent, suffix: "%"))
                metric("社区评分", RadarFormat.decimal(row.community?.average))
            }
            Section("派生指标") {
                ForEach(DerivedMetrics.evaluate(model: row.benchmark)) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        LabeledContent(result.formula.name, value: RadarFormat.derived(result.value))
                        Text("\(result.formula.formulaText) · \(result.formula.unit)")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Section("Pareto") {
                LabeledContent(paretoPreset.name, value: paretoClassification.label)
                Text(paretoPreset.explanation).font(.caption).foregroundStyle(.secondary)
                Text("不使用社区评分或来源额度估算。") .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(row.name)
    }

    private var historySeries: [TrendSeries] {
        WorkspaceProjection.singleModelHistory(history: history, modelID: row.id, metric: .quality)
    }
    private var historyChart: some View {
        Chart(historySeries) { group in
            ForEach(group.points) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("质量", point.value),
                    series: .value("Revision 系列", group.id)
                )
                .foregroundStyle(by: .value("Revision", group.seriesRevision))
                .symbol(by: .value("Revision", group.seriesRevision))
            }
        }
    }
    @ViewBuilder private var scaledHistoryChart: some View {
        if let domain = TrendChartDomain.padded(historySeries.flatMap(\.points).map(\.date)) {
            historyChart.chartXScale(domain: domain)
        } else {
            historyChart
        }
    }

    private func metric(_ label: String, _ value: String) -> some View { LabeledContent(label, value: value) }
}
