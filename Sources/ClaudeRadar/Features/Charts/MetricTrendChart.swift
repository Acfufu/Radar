import Charts
import SwiftUI

struct MetricTrendChart: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    @State private var metric: TrendMetric = .quality
    @State private var timeRange: TrendTimeRange = .all
    @State private var selectionState = TrendSelectionState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ViewHeader(title: "趋势", subtitle: "每条线限定同一模型与同一 seriesRevision，revision 变化必定断线")
                HStack {
                    Picker("指标", selection: $metric) { ForEach(TrendMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .frame(width: 180)
                    Picker("时间范围", selection: $timeRange) { ForEach(TrendTimeRange.allCases) { Text($0.rawValue).tag($0) } }
                        .frame(width: 190)
                    Spacer()
                }
                if projection.rows.isEmpty { ContentUnavailableView("暂无趋势数据", systemImage: "chart.xyaxis.line") }
                else {
                    ScrollView(.horizontal) { HStack { ForEach(projection.rows) { row in Toggle(row.name, isOn: binding(row.id)).toggleStyle(.button) } } }
                    scaledTrendChart.chartLegend(position: .bottom).frame(minHeight: 320)
                    Text("系列分组：" + series.map { "\($0.modelName) · \($0.seriesRevision)" }.joined(separator: "，")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Divider().padding(.vertical, 8)
                    ParetoComparisonView(projection: projection)
                }
            }
            .padding(24)
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
                LineMark(x: .value("时间", point.date), y: .value(metric.rawValue, point.value), series: .value("系列", group.id))
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
        let historicalIDs = Set(history.flatMap { $0.models.map(\.id) })
        return projection.rows.filter { historicalIDs.contains($0.id) }.map(\.id)
    }
    private func reconcileSelection() {
        selectionState = TrendSelection.reconcile(state: selectionState, rows: projection.rows, history: history)
    }
    private func binding(_ id: ModelID) -> Binding<Bool> {
        Binding(get: { selectionState.selected.contains(id) }, set: { enabled in
            var selected = selectionState.selected
            if enabled { selected.insert(id) } else { selected.remove(id) }
            selectionState = TrendSelection.userChanged(selectionState, selected: selected)
        })
    }
}

enum TrendChartDomain {
    private static let edgePadding: TimeInterval = 60 * 60

    static func padded(_ dates: [Date]) -> ClosedRange<Date>? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first.addingTimeInterval(-edgePadding)...last.addingTimeInterval(edgePadding)
    }
}
