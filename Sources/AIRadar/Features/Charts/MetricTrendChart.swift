import Charts
import SwiftUI

struct MetricTrendChart: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    @State private var metric: TrendMetric = .quality
    @State private var timeRange: TrendTimeRange = .lastTwoDays
    @State private var selectionState = TrendSelectionState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(
                    title: "历史指标比较",
                    subtitle: "\(projection.source.displayName) · Radar 本地快照，不插值；每条线限定同一配置与同一 seriesRevision"
                )
                HStack {
                    Picker("指标", selection: $metric) {
                        ForEach(TrendMetric.allCases, id: \.self) { Text(metricTitle($0)).tag($0) }
                    }
                        .frame(width: 190)
                    Picker("时间范围", selection: $timeRange) { ForEach(TrendTimeRange.allCases) { Text($0.rawValue).tag($0) } }
                        .frame(width: 190)
                    Spacer()
                }
                .radarPanel()
                if projection.rows.isEmpty {
                    ContentUnavailableView("暂无趋势数据", systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .radarPanel()
                }
                else {
                    ScrollView(.horizontal) { HStack { ForEach(projection.rows) { row in Toggle(row.name, isOn: binding(row.id)).toggleStyle(.button) } } }
                        .radarPanel()
                    VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                        if series.isEmpty {
                            ContentUnavailableView(
                                "该指标暂无历史数据",
                                systemImage: "chart.xyaxis.line",
                                description: Text("缺失值保持为空，不会补零或插值。")
                            )
                            .frame(maxWidth: .infinity, minHeight: 320)
                        } else {
                            scaledTrendChart
                                .accessibilityChartDescriptor(trendDescriptor)
                                .chartLegend(position: .bottom)
                                .chartXAxis {
                                    AxisMarks { AxisGridLine().foregroundStyle(palette.divider.color); AxisValueLabel().foregroundStyle(palette.secondaryText.color) }
                                }
                                .chartYAxis {
                                    AxisMarks { AxisGridLine().foregroundStyle(palette.divider.color); AxisValueLabel().foregroundStyle(palette.secondaryText.color) }
                                }
                                .chartPlotStyle { $0.background(palette.section.color) }
                                .frame(minHeight: 320)
                        }
                        Text("系列分组：" + series.map { "\($0.modelName) · \($0.seriesRevision)" }.joined(separator: "，"))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                            .textSelection(.enabled)
                    }
                    .radarPanel()
                    ParetoComparisonView(projection: projection)
                }
            }
            .radarPage()
        }
        .onChange(of: selectionCandidates, initial: true) { _, _ in reconcileSelection() }
    }
    private var series: [TrendSeries] {
        WorkspaceProjection.trendSeries(
            history: history,
            metric: metric,
            selected: selectionState.selected,
            timeRange: timeRange
        )
    }
    private var trendChart: some View {
        Chart(series) { group in
            ForEach(group.points) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value(metricTitle(metric), point.value),
                    series: .value("系列", "\(group.id)|\(point.segmentIndex)")
                )
                    .foregroundStyle(by: .value("模型", group.modelName))
                    .symbol(by: .value("Revision", group.seriesRevision))
            }
        }
    }
    @ViewBuilder private var scaledTrendChart: some View {
        if let domain = TrendChartDomain.padded(series.flatMap(\.points).map(\.date)) {
            trendChart.chartXScale(domain: domain)
        } else {
            trendChart
        }
    }
    private var selectionCandidates: [ModelID] {
        let availableIDs = Set(WorkspaceProjection.trendSeries(
            history: history,
            metric: metric,
            selected: Set(projection.rows.map(\.id)),
            timeRange: timeRange
        ).map(\.modelID))
        return projection.rows.filter { availableIDs.contains($0.id) }.map(\.id)
    }
    private func reconcileSelection() {
        let availableIDs = Set(selectionCandidates)
        selectionState = TrendSelection.reconcile(
            state: selectionState,
            rows: projection.rows.filter { availableIDs.contains($0.id) },
            history: history
        )
    }
    private func binding(_ id: ModelID) -> Binding<Bool> {
        Binding(get: { selectionState.selected.contains(id) }, set: { enabled in
            var selected = selectionState.selected
            if enabled { selected.insert(id) } else { selected.remove(id) }
            selectionState = TrendSelection.userChanged(selectionState, selected: selected)
        })
    }
    private func metricTitle(_ metric: TrendMetric) -> String {
        WorkspacePresentation.metric(for: projection.source.id).title(for: metric)
    }
    private var trendDescriptor: RadarChartDescriptor {
        RadarChartDescriptor(
            title: "\(projection.source.displayName) · \(metricTitle(metric)) 历史",
            summary: "Radar 本地快照；按模型与数据版本分段，缺失值不补零或插值。",
            xAxisTitle: "时间",
            yAxisTitle: "\(metricTitle(metric))\(metricUnit.isEmpty ? "" : "（\(metricUnit)）")",
            xValueDescription: RadarChartDescriptor.dateTime,
            yValueDescription: { RadarChartDescriptor.number($0, unit: metricUnit) },
            series: series.flatMap { group in
                Dictionary(grouping: group.points, by: \.segmentIndex)
                    .sorted { $0.key < $1.key }
                    .map { segment, points in
                        RadarChartSeries(
                            name: "\(group.modelName) · \(group.seriesRevision) · 分段 \(segment + 1)",
                            isContinuous: true,
                            points: points.map { point in
                                .init(
                                    x: point.date.timeIntervalSince1970,
                                    y: point.value,
                                    label: "\(projection.source.displayName)，\(group.modelName)，数据版本 \(group.seriesRevision)，\(RadarChartDescriptor.dateTime(point.date.timeIntervalSince1970))，\(metricTitle(metric)) \(RadarChartDescriptor.number(point.value, unit: metricUnit))"
                                )
                            }
                        )
                    }
            }
        )
    }
    private var metricUnit: String {
        switch metric {
        case .quality: WorkspacePresentation.metric(for: projection.source.id).qualityUnit
        case .cost: "USD"
        case .elapsed: "秒"
        case .cache: "%"
        case .agentSteps: "步"
        case .tokens: "Token"
        }
    }
}

enum TrendChartDomain {
    private static let edgePadding: TimeInterval = 60 * 60

    static func padded(_ dates: [Date]) -> ClosedRange<Date>? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first.addingTimeInterval(-edgePadding)...last.addingTimeInterval(edgePadding)
    }
}
