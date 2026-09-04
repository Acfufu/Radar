import Charts
import SwiftUI

struct ParetoComparisonView: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection
    @State private var preset: ParetoPreset = .qualityCost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pareto 对比").font(.title2.bold())
                Spacer()
                Picker("预设", selection: $preset) {
                    ForEach(ParetoPreset.allCases) { Text($0.name).tag($0) }
                }
                .frame(width: 220)
            }
            Text(preset.explanation).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            AnalysisExplanation()
            Chart(plottable) { point in
                PointMark(
                    x: .value(preset.horizontalLabel, point.consumption),
                    y: .value(
                        "\(metric.qualityLabel)（越高越好）",
                        point.quality
                    )
                )
                .foregroundStyle(by: .value("状态", point.classification.label))
                .symbol(by: .value("状态", point.classification.label))
                .annotation(position: point.classification == .frontier ? .top : .bottom) {
                    Text(point.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160)
                        .padding(.horizontal, 3)
                        .background(palette.card.color.opacity(0.9), in: .rect(cornerRadius: 3))
                }
            }
            .accessibilityChartDescriptor(paretoDescriptor)
            .chartLegend(position: .bottom)
            .chartXAxis {
                AxisMarks { AxisGridLine().foregroundStyle(palette.divider.color); AxisValueLabel().foregroundStyle(palette.secondaryText.color) }
            }
            .chartYAxis {
                AxisMarks { AxisGridLine().foregroundStyle(palette.divider.color); AxisValueLabel().foregroundStyle(palette.secondaryText.color) }
            }
            .chartPlotStyle { $0.background(palette.section.color) }
            .frame(minHeight: 260)
            ForEach(results) { result in
                HStack {
                    Text(result.displayName)
                    Spacer()
                    if let model = model(for: result.modelID),
                       let costPerTask = DerivedMetrics.evaluate(model: model).first {
                        Text("\(costPerTask.formula.name)：\(RadarFormat.derived(costPerTask.value)) · \(costPerTask.formula.unit)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(result.classification.label)
                }
                .foregroundStyle(result.classification == .dataInsufficient ? .secondary : .primary)
            }
            if !efficiencyPoints.isEmpty {
                Divider()
                Text("成本-质量散点 · Radar 本地估算")
                    .font(.title3.bold())
                Text("横轴按每有效题平均费用与平均耗时折算并在当前数据集内归一为 100；纵轴为来源 \(metric.qualityLabel)。越靠左上越高效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Chart(efficiencyPoints) { point in
                    PointMark(
                        x: .value("相对综合成本指数", point.combinedCostIndex),
                        y: .value(metric.qualityLabel, point.quality)
                    )
                    .foregroundStyle(by: .value("模型", point.modelName))
                    .symbol(by: .value("模型", point.modelName))
                    .annotation(position: .top) {
                        Text(point.modelName)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 160)
                    }
                }
                .accessibilityChartDescriptor(efficiencyDescriptor)
                .chartLegend(position: .bottom)
                .chartXAxis {
                    AxisMarks { AxisGridLine().foregroundStyle(palette.divider.color); AxisValueLabel().foregroundStyle(palette.secondaryText.color) }
                }
                .chartYAxis {
                    AxisMarks { AxisGridLine().foregroundStyle(palette.divider.color); AxisValueLabel().foregroundStyle(palette.secondaryText.color) }
                }
                .chartPlotStyle { $0.background(palette.section.color) }
                .frame(minHeight: 260)
                Text("公式：每有效题平均费用 × (每有效题平均分钟 / 10)^(ln 2.5 / ln 1.35)；仅使用当前来源与 seriesRevision，不跨来源比较。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("仅当前数据集 · \(projection.sync?.benchmark.value?.seriesRevision ?? "—") · 不含社区评分与来源额度")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .radarPanel()
    }

    private var results: [ParetoResult] { projection.pareto(preset) }
    private var metric: WorkspaceMetricPresentation { WorkspacePresentation.metric(for: projection.source.id) }
    private var efficiencyPoints: [IntelligenceEfficiencyPoint] { projection.intelligenceEfficiency }
    private var sourceRevision: String { projection.sync?.benchmark.value?.seriesRevision ?? "不可用" }
    private var paretoDescriptor: RadarChartDescriptor {
        RadarChartDescriptor(
            title: "\(projection.source.displayName) · Pareto 对比",
            summary: "仅当前数据集与数据版本 \(sourceRevision)；状态包含前沿、被支配与数据不足。",
            xAxisTitle: preset.horizontalLabel,
            yAxisTitle: "\(metric.qualityLabel)（越高越好）",
            xValueDescription: { RadarChartDescriptor.number($0, unit: paretoUnit) },
            yValueDescription: { RadarChartDescriptor.number($0, unit: metric.qualityUnit) },
            series: ParetoClassification.allChartCases.map { classification in
                .init(
                    name: classification.label,
                    isContinuous: false,
                    points: plottable.filter { $0.classification == classification }.map { point in
                        .init(
                            x: point.consumption,
                            y: point.quality,
                            label: "\(projection.source.displayName)，\(point.displayName)，\(classification.label)，\(preset.horizontalLabel) \(RadarChartDescriptor.number(point.consumption, unit: paretoUnit))，\(metric.qualityLabel) \(RadarChartDescriptor.number(point.quality, unit: metric.qualityUnit))"
                        )
                    }
                )
            }
        )
    }
    private var efficiencyDescriptor: RadarChartDescriptor {
        RadarChartDescriptor(
            title: "\(projection.source.displayName) · 成本-质量散点",
            summary: "Radar 本地估算；仅当前数据集与数据版本 \(sourceRevision)，不跨来源比较。",
            xAxisTitle: "相对综合成本指数",
            yAxisTitle: metric.qualityLabel,
            xValueDescription: { RadarChartDescriptor.number($0, unit: "指数") },
            yValueDescription: { RadarChartDescriptor.number($0, unit: metric.qualityUnit) },
            series: efficiencyPoints.map { point in
                .init(
                    name: point.modelName,
                    isContinuous: false,
                    points: [.init(
                        x: point.combinedCostIndex,
                        y: point.quality,
                        label: "\(projection.source.displayName)，\(point.modelName)，综合成本指数 \(RadarChartDescriptor.number(point.combinedCostIndex))，\(metric.qualityLabel) \(RadarChartDescriptor.number(point.quality, unit: metric.qualityUnit))"
                    )]
                )
            }
        )
    }
    private var paretoUnit: String {
        switch preset {
        case .qualityCost: "USD"
        case .qualityTime: "秒"
        case .qualityTokens: "Token"
        }
    }
    private func model(for id: ModelID) -> ModelBenchmark? {
        projection.sync?.benchmark.value?.models.first { $0.id == id }
    }
    private var plottable: [ParetoChartPoint] {
        results.compactMap { result in
            guard let quality = result.quality, let consumption = result.consumption else { return nil }
            return .init(
                id: result.modelID,
                displayName: result.displayName,
                quality: NSDecimalNumber(decimal: quality).doubleValue,
                consumption: NSDecimalNumber(decimal: consumption).doubleValue,
                classification: result.classification
            )
        }
    }
}

private extension ParetoClassification {
    static let allChartCases: [Self] = [.frontier, .dominated, .dataInsufficient]
}

private struct ParetoChartPoint: Identifiable {
    let id: ModelID
    let displayName: String
    let quality: Double
    let consumption: Double
    let classification: ParetoClassification
}
