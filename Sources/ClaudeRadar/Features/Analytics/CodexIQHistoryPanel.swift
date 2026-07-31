import Charts
import Foundation
import SwiftUI

struct CodexIQHistorySmallMultiplesPanel: View {
    @Environment(\.radarPalette) private var palette

    let history: [BenchmarkDataset]
    let provenance: String

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Text("IQ 历史数据")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("时间按来源更新时间，缺失时使用本地抓取时间；不同数据版本或缺失点之间不会连线。")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: RadarStyle.chartMetrics(for: .standard).minimumCardWidth
                        ),
                        alignment: .top
                    ),
                ],
                alignment: .leading,
                spacing: RadarStyle.cardSpacing
            ) {
                ForEach(orderedPanels) { panel in
                    CodexIQHistoryFamilyPanel(panel: panel, sharedDomain: sharedDomain)
                }
            }

            Divider().overlay(palette.divider.color)
            Text("Radar 本地已保存快照 · \(history.count) 个")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
            Text(provenance)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier("codex-iq-history")
        .radarPanel()
    }

    private var projection: CodexIQHistoryProjection {
        CodexIQHistoryAnalytics.project(history: history)
    }

    private var orderedPanels: [CodexIQHistoryPanel] {
        RadarModelIdentity.canonicalFamilies.compactMap { family in
            projection.panels.first { $0.family == family }
        }
    }

    private var sharedDomain: ClosedRange<Date>? {
        TrendChartDomain.padded(
            projection.panels
                .flatMap(\.lines)
                .flatMap(\.segments)
                .flatMap(\.points)
                .map(\.date)
        )
    }
}

private struct CodexIQHistoryFamilyPanel: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.radarPalette) private var palette

    let panel: CodexIQHistoryPanel
    let sharedDomain: ClosedRange<Date>?

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Text(panel.family)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if panel.lines.isEmpty {
                ContentUnavailableView(
                    "\(panel.family) 暂无本地 IQ 历史",
                    systemImage: "chart.xyaxis.line",
                    description: Text("本地快照中没有可识别的 \(panel.family) 努力等级；不会以 0 代替。")
                )
                .frame(minHeight: chartMetrics.minimumHeight)
            } else if !hasComparableHistory {
                ContentUnavailableView(
                    "\(panel.family) 历史不足",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text("至少需要 2 个同努力等级、同数据版本的\n有效 IQ 点。\n缺失或冲突值不会以 0 代替。")
                )
                .frame(minHeight: chartMetrics.minimumHeight)
            } else {
                GeometryReader { geometry in
                    let axis = CodexIQHistoryAxisPolicy.projection(
                        domain: sharedDomain,
                        availableWidth: geometry.size.width
                    )
                    scaledChart
                        .chartForegroundStyleScale(
                            domain: efforts,
                            range: efforts.map(effortColor)
                        )
                        .chartLegend(position: .bottom, alignment: .leading)
                        .chartXAxis {
                            AxisMarks(values: axis.dates) { value in
                                AxisGridLine().foregroundStyle(palette.divider.color)
                                AxisValueLabel {
                                    if let date = value.as(Date.self) {
                                        Text(axis.label(for: date))
                                            .font(.caption2.monospacedDigit())
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .foregroundStyle(palette.secondaryText.color)
                            }
                        }
                        .chartYAxis {
                            AxisMarks {
                                AxisGridLine().foregroundStyle(palette.divider.color)
                                AxisValueLabel().foregroundStyle(palette.secondaryText.color)
                            }
                        }
                        .chartPlotStyle { $0.background(palette.section.color) }
                        .accessibilityRepresentation {
                            VStack(alignment: .leading) {
                                Text("\(panel.family) IQ 历史图")
                                Text("时间刻度：\(axis.labels.joined(separator: "，"))")
                                Text("努力等级图例：\(efforts.joined(separator: "，"))")
                                ForEach(panel.lines) { line in
                                    ForEach(line.segments) { segment in
                                        ForEach(segment.points) { point in
                                            Text(pointLabel(line: line, segment: segment, point: point))
                                        }
                                    }
                                }
                            }
                        }
                }
                .frame(minHeight: chartMetrics.minimumHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(RadarStyle.cardSpacing)
        .background(palette.section.color, in: .rect(cornerRadius: RadarStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RadarStyle.cornerRadius)
                .stroke(palette.divider.color)
        }
        .accessibilityIdentifier("codex-iq-history-\(panel.family.lowercased())")
    }

    private var chart: some View {
        Chart {
            ForEach(panel.lines) { line in
                ForEach(line.segments) { segment in
                    CodexIQHistorySegmentMarks(
                        family: panel.family,
                        effort: line.effort,
                        segment: segment,
                        lineWidth: chartMetrics.lineWidth,
                        symbolSize: chartMetrics.symbolSize
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var scaledChart: some View {
        if let sharedDomain {
            chart.chartXScale(domain: sharedDomain)
        } else {
            chart
        }
    }

    private var hasComparableHistory: Bool {
        panel.lines.flatMap(\.segments).contains { $0.points.count >= 2 }
    }

    private var chartMetrics: RadarChartMetrics {
        RadarStyle.chartMetrics(for: contrast)
    }

    private var efforts: [String] {
        RadarModelIdentity.efforts.filter { effort in
            panel.lines.contains { $0.effort == effort }
        }
    }

    private func effortColor(_ effort: String) -> Color {
        switch RadarModelIdentity.efforts.firstIndex(of: effort) {
        case 0: palette.primaryText.color
        case 1: palette.accent.color
        case 2: palette.negative.color
        case 3: palette.positive.color
        case 4: palette.secondaryText.color
        default: palette.accentBorder.color
        }
    }

    private func pointLabel(
        line: CodexIQHistoryLine,
        segment: CodexIQHistorySegment,
        point: CodexIQHistoryPoint
    ) -> String {
        "\(panel.family)，努力等级 \(line.effort)，\(point.date.formatted(date: .abbreviated, time: .shortened))，IQ \(number(point.value))，数据版本 \(segment.seriesRevision)"
    }

    private func number(_ value: Double) -> String {
        value.isFinite
            ? value.formatted(.number.precision(.fractionLength(1)))
            : "不可用"
    }
}

struct CodexIQHistoryAxisProjection: Equatable, Sendable {
    let dates: [Date]
    let labels: [String]

    func label(for date: Date) -> String {
        guard let index = dates.firstIndex(of: date), labels.indices.contains(index) else {
            return ""
        }
        return labels[index]
    }
}

enum CodexIQHistoryAxisPolicy {
    static func projection(
        domain: ClosedRange<Date>?,
        availableWidth: CGFloat,
        calendar: Calendar = .current
    ) -> CodexIQHistoryAxisProjection {
        guard let domain else {
            return .init(dates: [], labels: [])
        }
        let count = RadarStyle.historyAxisMetrics.tickCount(for: availableWidth)
        let duration = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let dates: [Date]
        if duration > 0 {
            dates = (0 ..< count).map { index in
                domain.lowerBound.addingTimeInterval(
                    duration * (Double(index) + 0.5) / Double(count)
                )
            }
        } else {
            dates = [domain.lowerBound]
        }
        return .init(
            dates: dates,
            labels: dates.map { label(for: $0, calendar: calendar) }
        )
    }

    private static func label(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents(
            [.month, .day, .hour, .minute],
            from: date
        )
        return String(
            format: "%02d/%02d\n%02d:%02d",
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}

private struct CodexIQHistorySegmentMarks: ChartContent {
    let family: String
    let effort: String
    let segment: CodexIQHistorySegment
    let lineWidth: CGFloat
    let symbolSize: CGFloat

    var body: some ChartContent {
        ForEach(segment.points) { point in
            LineMark(
                x: .value("时间", point.date),
                y: .value("IQ", point.value),
                series: .value("分段", segment.id)
            )
            .foregroundStyle(by: .value("努力等级", effort))
            .lineStyle(.init(lineWidth: lineWidth))

            PointMark(
                x: .value("时间", point.date),
                y: .value("IQ", point.value)
            )
            .foregroundStyle(by: .value("努力等级", effort))
            .symbolSize(symbolSize)
            .accessibilityLabel(
                "\(family)，努力等级 \(effort)，\(point.date.formatted(date: .abbreviated, time: .shortened))，IQ \(number(point.value))，数据版本 \(segment.seriesRevision)"
            )
        }
    }

    private func number(_ value: Double) -> String {
        value.isFinite
            ? value.formatted(.number.precision(.fractionLength(1)))
            : "不可用"
    }
}
