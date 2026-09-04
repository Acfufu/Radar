import SwiftUI

struct CodexEfficiencyMatrixPanel: View {
    @Environment(\.radarPalette) private var palette

    let cells: [CodexEfficiencyMatrixCell]
    let sourceUpdatedAt: Date?
    let provenance: String

    private let families = RadarModelIdentity.canonicalFamilies
    private let efforts = RadarModelIdentity.efforts

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Label("智力效率矩阵", systemImage: "square.grid.3x3")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("IQ、平均费用 / 每个有效任务、平均耗时 / 每个有效任务")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)

            if cells.isEmpty {
                ContentUnavailableView(
                    "暂无可用效率数据",
                    systemImage: "chart.bar.xaxis",
                    description: Text("缺少 IQ、费用或耗时；不会以 $0 或 0 分钟代替。")
                )
                .frame(minHeight: 180)
            } else {
                let affordance = RadarStyle.horizontalScrollAffordance
                Label(affordance.title, systemImage: affordance.systemImage)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .accessibilityIdentifier("codex-efficiency-horizontal-affordance")

                ScrollView(.horizontal) {
                    Grid(
                        alignment: .topLeading,
                        horizontalSpacing: RadarStyle.compactSpacing,
                        verticalSpacing: RadarStyle.compactSpacing
                    ) {
                        GridRow {
                            header("系列")
                                .frame(width: layout.matrixFamilyColumnWidth, alignment: .leading)
                            ForEach(efforts, id: \.self) { effort in
                                header(effort)
                                    .frame(width: layout.matrixCellWidth, alignment: .leading)
                            }
                        }

                        ForEach(families, id: \.self) { family in
                            GridRow {
                                Text(family)
                                    .font(.headline)
                                    .frame(width: layout.matrixFamilyColumnWidth, alignment: .topLeading)
                                    .frame(minHeight: layout.matrixRowHeight, alignment: .topLeading)
                                ForEach(efforts, id: \.self) { effort in
                                    if let cell = cellsByCoordinate[.init(family: family, effort: effort)] {
                                        matrixCell(cell)
                                    } else {
                                        Color.clear.frame(
                                            width: layout.matrixCellWidth,
                                            height: layout.matrixRowHeight
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible, axes: .horizontal)
                .accessibilityLabel("智力效率矩阵，可水平滚动查看各努力等级")
            }

            Divider().overlay(palette.divider.color)
            Text("来源更新时间：\(RadarFormat.date(sourceUpdatedAt))")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
            Text(provenance)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
        }
        .radarPanel()
    }

    private var cellsByCoordinate: [CodexEfficiencyCoordinate: CodexEfficiencyMatrixCell] {
        Dictionary(uniqueKeysWithValues: cells.map { ($0.coordinate, $0) })
    }

    private var layout: RadarAnalyticsLayoutMetrics {
        RadarStyle.analyticsLayout
    }

    private func header(_ value: String) -> some View {
        Text(value)
            .font(.caption.bold())
            .foregroundStyle(palette.secondaryText.color)
    }

    private func matrixCell(_ cell: CodexEfficiencyMatrixCell) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing / 2) {
            metric("IQ", value: cell.quality.formatted(.number.precision(.fractionLength(1))), valid: cell.quality)
            metric(
                "平均费用 / 每个有效任务",
                value: cell.averageCostUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))),
                valid: cell.averageCostUSD
            )
            metric(
                "平均耗时 / 每个有效任务",
                value: minutes(cell.averageMinutes),
                valid: cell.averageMinutes
            )
        }
        .font(.caption)
        .monospacedDigit()
        .frame(width: layout.matrixCellWidth, alignment: .topLeading)
        .frame(minHeight: layout.matrixRowHeight, alignment: .topLeading)
        .radarMetricCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("系列 \(cell.family)，努力等级 \(cell.effort)，IQ \(number(cell.quality))，平均费用 / 每个有效任务 \(cost(cell.averageCostUSD))，平均耗时 / 每个有效任务 \(minutes(cell.averageMinutes))")
    }

    private func metric(_ label: String, value: String, valid: Double) -> some View {
        Text("\(label)：\(valid.isFinite && valid > 0 ? value : "不可用")")
    }

    private func minutes(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "不可用" }
        if value < 0.1 { return "<0.1 分钟" }
        return value.formatted(.number.precision(.fractionLength(1))) + " 分钟"
    }

    private func number(_ value: Double) -> String {
        value.isFinite ? value.formatted(.number.precision(.fractionLength(1))) : "不可用"
    }

    private func cost(_ value: Double) -> String {
        value.isFinite && value > 0 ? value.formatted(.currency(code: "USD").precision(.fractionLength(2))) : "不可用"
    }
}
