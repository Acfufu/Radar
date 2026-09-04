import Charts
import SwiftUI

struct OverviewHeaderSections: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection

    var body: some View {
        Group {
            header
            banners
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ViewHeader(
                title: "概览",
                subtitle: "\(projection.source.displayName) · 更新于 \(RadarFormat.date(projection.updatedAt))"
            )
            Spacer()
            Label(overviewSourceHealth(projection.benchmarkState), systemImage: overviewSourceHealthIcon(projection.benchmarkState))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var banners: some View {
        if let supportState = OverviewView.presentation(for: projection).supportState {
            StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
        }
        if let healthState = OverviewView.presentation(for: projection).healthState,
           healthState != .fresh {
            StateBanner(
                state: healthState,
                error: OverviewView.presentation(for: projection).error,
                sourceName: projection.source.displayName
            )
        }
        if let community = OverviewView.communityPresentation(for: projection) {
            Label(community.message, systemImage: "person.2.badge.exclamationmark")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(
                    community.state == .usingLastKnownGood
                        ? palette.secondaryText.color
                        : palette.negative.color
                )
                .radarPanel()
        }
    }

}

struct OverviewLocalSections: View {
    @Environment(\.radarPalette) var palette
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    let refreshIntervalMinutes: Int

    @State var subscription = "20x Pro"

    var body: some View {
        Group {
            signalHero
            localInsights
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 340), alignment: .top)],
                spacing: RadarStyle.compactSpacing
            ) {
                familyHealth
                tierHeatmap
                quotaContext
            }
            monitoringAndRecentPerformance
        }
    }
}
struct LocalIQTrendChart: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("本地 IQ 拟合").font(.headline)
                Spacer()
                Text(trendPoints.count > 1 ? "\(trendPoints.count) 个同步点" : "等待更多同步点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart {
                if let value = peak?.benchmark.qualityScore {
                    RuleMark(y: .value("当前 IQ", RadarVisuals.double(value)))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(trendPoints) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("IQ", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("IQ", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green.opacity(0.12))
                    PointMark(
                        x: .value("时间", point.date),
                        y: .value("IQ", point.value)
                    )
                    .foregroundStyle(.green)
                }
            }
            .accessibilityChartDescriptor(trendDescriptor)
            .chartYScale(domain: 0...trendUpperBound)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(minHeight: 150)
        }
    }

    private var peak: WorkspaceModelRow? {
        overviewPeak(in: projection.rows)
    }

    private var trendPoints: [TrendPoint] {
        guard let peak else { return [] }
        return WorkspaceProjection.trendSeries(
            history: history,
            metric: .quality,
            selected: [peak.id],
            timeRange: .lastDay
        )
        .flatMap(\.points)
        .sorted { $0.date < $1.date }
    }

    private var trendUpperBound: Double {
        let quality = peak?.benchmark.qualityScore.map(RadarVisuals.double) ?? 100
        return max(110, ceil(quality / 10) * 10)
    }

    private var trendDescriptor: RadarChartDescriptor {
        RadarChartDescriptor(
            title: "\(projection.source.displayName) · 本地 IQ 拟合",
            summary: "Radar 本地 24 小时快照；仅当前峰值模型，缺失值不补零。",
            xAxisTitle: "时间",
            yAxisTitle: "IQ",
            xValueDescription: RadarChartDescriptor.dateTime,
            yValueDescription: { RadarChartDescriptor.number($0, unit: "IQ") },
            series: [
                .init(
                    name: peak.map { "\($0.name) · 本地 IQ" } ?? "本地 IQ",
                    isContinuous: true,
                    points: trendPoints.map { point in
                        .init(
                            x: point.date.timeIntervalSince1970,
                            y: point.value,
                            label: "\(projection.source.displayName)，\(peak?.name ?? "模型不可用")，\(RadarChartDescriptor.dateTime(point.date.timeIntervalSince1970))，IQ \(RadarChartDescriptor.number(point.value))"
                        )
                    }
                ),
            ]
        )
    }
}

@MainActor @ViewBuilder
func radarOverviewSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
        Text(title).font(.headline)
        content()
    }
    .radarPanel()
}

func overviewSourceHealth(_ state: WorkspaceState) -> String {
    switch state {
    case .fresh: "数据源正常"
    case .loading: "正在同步"
    case .stale, .usingLastKnownGood: "使用缓存数据"
    case .empty: "暂无数据"
    case .validationFailed: "数据校验失败"
    case .unavailable, .disabled, .error: "数据源不可用"
    }
}

func overviewSourceHealthIcon(_ state: WorkspaceState) -> String {
    state == .fresh ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
}

func overviewPeak(in rows: [WorkspaceModelRow]) -> WorkspaceModelRow? {
    rows.compactMap { $0.benchmark.qualityScore == nil ? nil : $0 }
        .max { ($0.benchmark.qualityScore ?? 0) < ($1.benchmark.qualityScore ?? 0) }
}
