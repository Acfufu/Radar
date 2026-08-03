import Charts
import SwiftUI

struct CodexCostVersusIQPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.radarPalette) private var palette

    let points: [IntelligenceEfficiencyPoint]
    let sourceUpdatedAt: Date?
    let seriesRevision: String?
    let provenance: String

    @State private var selectedCost: Double?

    var body: some View {
        let chartMetrics = RadarStyle.chartMetrics(for: contrast)
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Text("综合成本 × IQ")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("横轴为当前数据集内归一化的综合成本，纵轴为 IQ；越靠左上越高效。")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)

            if chartPoints.isEmpty {
                ContentUnavailableView(
                    "暂无可用成本与 IQ 数据",
                    systemImage: "chart.dots.scatter",
                    description: Text("缺少 IQ、费用或耗时；不会以 0 代替。")
                )
                .frame(minHeight: chartMetrics.minimumHeight)
            } else {
                Chart(chartPoints) { point in
                    PointMark(
                        x: .value("相对综合成本指数", point.x),
                        y: .value("IQ", point.y)
                    )
                    .foregroundStyle(by: .value("系列", point.family))
                    .symbol(by: .value("系列", point.family))
                    .accessibilityLabel(
                        pointAccessibilityLabel(point)
                    )

                    if visiblePointIDs.contains(point.id) {
                        RuleMark(x: .value("所选综合成本", point.x))
                            .foregroundStyle(palette.accent.color)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(point.point.modelName).fontWeight(.semibold)
                                    Text("IQ \(number(point.y)) · 综合成本 \(number(point.x))")
                                }
                                .font(.caption)
                                .padding(6)
                                .background(palette.card.color, in: .rect(cornerRadius: 6))
                                .accessibilityElement(children: .combine)
                            }
                            .accessibilityLabel(
                                "已选择模型 \(point.point.modelName)，IQ \(number(point.y))，综合成本 \(number(point.x))"
                            )
                    }
                }
                .chartForegroundStyleScale(
                    domain: families,
                    range: families.map {
                        Self.familyColor($0, colorScheme: colorScheme)
                    }
                )
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(palette.divider.color)
                        AxisValueLabel().foregroundStyle(palette.secondaryText.color)
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(palette.divider.color)
                        AxisValueLabel().foregroundStyle(palette.secondaryText.color)
                    }
                }
                .chartPlotStyle { $0.background(palette.section.color) }
                .chartXSelection(value: $selectedCost)
                .frame(minHeight: chartMetrics.minimumHeight)
                .accessibilityChartDescriptor(chartDescriptor)
                .accessibilityHint("在图表中选择一个点可查看模型、IQ 与综合成本")
            }

            Divider().overlay(palette.divider.color)
            Text("仅当前数据集 · \(seriesRevision ?? "不可用") · 来源更新时间：\(RadarFormat.date(sourceUpdatedAt))")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
            Text(provenance)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier("codex-cost-versus-iq")
        .radarPanel()
    }

    private var chartPoints: [CodexCostVersusIQPoint] {
        CodexEfficiencyAnalytics.costVersusIQ(points: points).filter {
            $0.x.isFinite && $0.x > 0 && $0.y.isFinite
        }
    }

    private var families: [String] {
        var seen = Set<String>()
        return chartPoints.map(\.family).filter { seen.insert($0).inserted }
    }

    private var selectedPoint: CodexCostVersusIQPoint? {
        guard let selectedCost, selectedCost.isFinite else { return nil }
        return chartPoints.min {
            abs($0.x - selectedCost) < abs($1.x - selectedCost)
        }
    }

    private var chartDescriptor: RadarChartDescriptor {
        RadarChartDescriptor(
            title: "Codex Radar · 综合成本与 IQ",
            summary: "\(provenance)；仅当前数据集与数据版本 \(seriesRevision ?? "不可用")，越靠左上越高效。",
            xAxisTitle: "相对综合成本指数",
            yAxisTitle: "IQ",
            xValueDescription: { RadarChartDescriptor.number($0, unit: "指数") },
            yValueDescription: { RadarChartDescriptor.number($0, unit: "IQ") },
            series: families.map { family in
                .init(
                    name: family,
                    isContinuous: false,
                    points: chartPoints.filter { $0.family == family }.map { point in
                        .init(x: point.x, y: point.y, label: pointAccessibilityLabel(point))
                    }
                )
            }
        )
    }

    private var visiblePointIDs: [ModelID] {
        CodexCostVersusIQAnnotationPolicy.visiblePointIDs(
            chartPoints,
            selected: selectedPoint?.id
        )
    }

    private func pointAccessibilityLabel(_ point: CodexCostVersusIQPoint) -> String {
        "模型 \(point.point.modelName)，IQ \(number(point.y))，综合成本 \(number(point.x))，系列 \(point.family)"
    }

    private func number(_ value: Double) -> String {
        guard value.isFinite else { return "不可用" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func familyColor(
        _ family: String,
        colorScheme: ColorScheme
    ) -> Color {
        RadarStyle.analyticsColors(for: colorScheme)
            .familyColor(at: RadarModelIdentity.canonicalFamilies.firstIndex(of: family))
            .color
    }
}

enum CodexCostVersusIQAnnotationPolicy {
    static func visiblePointIDs(
        _ points: [CodexCostVersusIQPoint],
        selected: ModelID?
    ) -> [ModelID] {
        guard let selected, points.contains(where: { $0.id == selected }) else { return [] }
        return [selected]
    }
}
