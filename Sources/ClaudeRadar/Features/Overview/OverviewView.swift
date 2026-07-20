import Charts
import SwiftUI

struct OverviewView: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    let refreshIntervalMinutes: Int

    @State private var subscription = "20x Pro"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                banners

                if projection.rows.isEmpty {
                    ContentUnavailableView(
                        "暂无 Benchmark 数据",
                        systemImage: "chart.bar.xaxis",
                        description: Text("刷新后仍无数据时，请查看来源状态。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    signalHero
                    HStack(alignment: .top, spacing: 12) {
                        familyHealth
                        tierHeatmap
                        quotaContext
                    }
                    monitoringAndRecentPerformance
                }
            }
            .padding(18)
        }
    }

    static func presentation(for projection: WorkspaceProjection) -> BenchmarkPresentation {
        projection.benchmarkPresentation
    }

    static func communityPresentation(for projection: WorkspaceProjection) -> CommunityAlertPresentation? {
        guard let error = projection.communityError else { return nil }
        let hasLastKnownGood = projection.sync?.community.value != nil
        return .init(
            state: hasLastKnownGood ? .usingLastKnownGood : .error(error),
            message: hasLastKnownGood
                ? "社区评分刷新失败，正在使用最近一次良好数据\n\(error)"
                : "社区评分刷新失败，暂无可用数据\n\(error)"
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ViewHeader(
                title: "概览",
                subtitle: "\(projection.source.displayName) · 更新于 \(RadarFormat.date(projection.updatedAt))"
            )
            Spacer()
            Label(sourceHealth, systemImage: sourceHealthIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var banners: some View {
        if let supportState = Self.presentation(for: projection).supportState {
            StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
        }
        if let healthState = Self.presentation(for: projection).healthState,
           healthState != .fresh {
            StateBanner(
                state: healthState,
                error: Self.presentation(for: projection).error,
                sourceName: projection.source.displayName
            )
        }
        if let community = Self.communityPresentation(for: projection) {
            Label(community.message, systemImage: "person.2.badge.exclamationmark")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .foregroundStyle(.orange)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 8))
        }
    }

    private var signalHero: some View {
        GroupBox {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前峰值 · IQ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(RadarFormat.decimal(peak?.benchmark.qualityScore))
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Circle()
                            .fill(RadarVisuals.qualityColor(peak?.benchmark.qualityScore))
                            .frame(width: 10, height: 10)
                    }
                    Text(peak?.name ?? "数据不足")
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(RadarFormat.integer(peak?.benchmark.passedTasks)) / \(RadarFormat.integer(peak?.benchmark.validTasks)) 通过")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 180, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("24 小时趋势").font(.headline)
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
                    .chartYScale(domain: 0...trendUpperBound)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(minHeight: 150)
                }
            }
            .padding(.top, 4)
        }
    }

    private var familyHealth: some View {
        GroupBox("模型家族健康") {
            VStack(spacing: 0) {
                ForEach(familySummaries) { summary in
                    HStack(spacing: 10) {
                        Image(systemName: RadarVisuals.familyIcon(summary.family))
                            .foregroundStyle(RadarVisuals.familyColor(summary.family))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.family).fontWeight(.medium)
                            Text(RadarIdentity.tier(for: summary.row) ?? "当前最佳档位")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(RadarFormat.decimal(summary.row.benchmark.qualityScore))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(RadarVisuals.qualityColor(summary.row.benchmark.qualityScore))
                    }
                    .padding(.vertical, 8)
                    if summary.id != familySummaries.last?.id { Divider() }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var tierHeatmap: some View {
        GroupBox("推理层级表现热力图 · IQ") {
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    Text("模型").foregroundStyle(.secondary)
                    ForEach(RadarIdentity.tiers, id: \.self) { tier in
                        Text(tier).foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)

                ForEach(heatmapFamilies, id: \.self) { family in
                    GridRow {
                        Text(family)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(RadarIdentity.tiers, id: \.self) { tier in
                            heatCell(row: heatmapRow(family: family, tier: tier))
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var quotaContext: some View {
        GroupBox("配额与成本上下文") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("订阅方案", selection: $subscription) {
                    Text("Plus").tag("Plus")
                    Text("5x Pro").tag("5x Pro")
                    Text("20x Pro").tag("20x Pro")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider()
                LabeledContent("公开额度估算") {
                    Text(quotaValue)
                        .monospacedDigit()
                }
                Text(selectedQuota?.resetDescription ?? "该订阅方案暂无公开额度估算")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var monitoringAndRecentPerformance: some View {
        HStack(alignment: .top, spacing: 12) {
            GroupBox("近期表现") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("模型")
                        Text("IQ")
                        Text("较上次")
                        Text("每题成本")
                        Text("平均耗时")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider().gridCellColumns(5)

                    ForEach(recentPerformance) { row in
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.family).fontWeight(.medium)
                                Text(row.tier ?? row.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(RadarFormat.decimal(row.quality))
                                .monospacedDigit()
                            Text(row.delta.map(RadarVisuals.signed) ?? "—")
                                .monospacedDigit()
                                .foregroundStyle(row.delta.map { $0 >= 0 ? Color.green : Color.orange } ?? .secondary)
                            Text(row.costPerTask.map { "$\(RadarFormat.decimal($0))" } ?? "—")
                                .monospacedDigit()
                            Text(RadarVisuals.duration(row.secondsPerTask))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 7)
                        if row.id != recentPerformance.last?.id {
                            Divider().gridCellColumns(5)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                GroupBox("实时监控") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(sourceHealth, systemImage: sourceHealthIcon)
                            .foregroundStyle(projection.benchmarkState == .fresh ? .green : .orange)
                        LabeledContent("最近同步", value: monitoringAge(at: context.date))
                        LabeledContent("自动刷新", value: "每 \(refreshIntervalMinutes) 分钟")
                        LabeledContent("历史快照", value: "\(sourceHistory.count)")
                        ProgressView(value: monitoringProgress(at: context.date))
                            .tint(.green)
                        Text(nextMonitoringText(at: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(width: 300)
        }
    }

    private var recentPerformance: [RadarPerformanceRow] {
        RadarRecentPerformance.rows(current: projection.rows, history: history)
    }

    private var sourceHistory: [BenchmarkDataset] {
        history.filter { $0.sourceID == projection.source.id }
    }

    private var monitoringDate: Date? {
        projection.sync?.benchmark.lastAttemptedAt ?? projection.updatedAt
    }

    private func monitoringAge(at now: Date) -> String {
        guard let monitoringDate else { return "尚未同步" }
        let seconds = max(0, now.timeIntervalSince(monitoringDate))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前" }
        return "\(Int(seconds / 3_600)) 小时前"
    }

    private func monitoringProgress(at now: Date) -> Double {
        guard let monitoringDate else { return 0 }
        let interval = TimeInterval(refreshIntervalMinutes * 60)
        return min(max(now.timeIntervalSince(monitoringDate) / interval, 0), 1)
    }

    private func nextMonitoringText(at now: Date) -> String {
        guard let monitoringDate else { return "等待首次同步" }
        let remaining = TimeInterval(refreshIntervalMinutes * 60) - now.timeIntervalSince(monitoringDate)
        guard remaining > 0 else { return "已进入下一次自动同步窗口" }
        return "约 \(max(1, Int(ceil(remaining / 60)))) 分钟后检查更新"
    }

    @ViewBuilder private func heatCell(row: WorkspaceModelRow?) -> some View {
        let quality = row?.benchmark.qualityScore
        Text(RadarFormat.decimal(quality))
            .font(.caption.monospacedDigit())
            .frame(minWidth: 40, maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RadarVisuals.qualityColor(quality).opacity(quality == nil ? 0.03 : 0.18))
            .foregroundStyle(quality == nil ? .secondary : .primary)
    }

    private var peak: WorkspaceModelRow? {
        projection.rows.compactMap { $0.benchmark.qualityScore == nil ? nil : $0 }
            .max { ($0.benchmark.qualityScore ?? 0) < ($1.benchmark.qualityScore ?? 0) }
    }

    private var familySummaries: [RadarFamilySummary] {
        RadarIdentity.familySummaries(projection.rows)
    }

    private var heatmapFamilies: [String] {
        familySummaries.map(\.family).filter { family in
            projection.rows.contains { RadarIdentity.family(for: $0) == family && RadarIdentity.tier(for: $0) != nil }
        }
        .prefix(3)
        .map { $0 }
    }

    private func heatmapRow(family: String, tier: String) -> WorkspaceModelRow? {
        projection.rows.first {
            RadarIdentity.family(for: $0) == family && RadarIdentity.tier(for: $0) == tier
        }
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

    private var selectedQuota: SourceQuotaEstimate? {
        projection.sync?.sourceStatus.value?.quotaEstimates.first {
            $0.windowLabel.localizedCaseInsensitiveContains(subscription)
        }
    }

    private var quotaValue: String {
        guard let selectedQuota else { return "—" }
        if let used = selectedQuota.usedPercent {
            return RadarFormat.decimal(used, suffix: "%")
        }
        return selectedQuota.estimatedValueUSD.map { "$\(RadarFormat.decimal($0))" } ?? "—"
    }

    private var sourceHealth: String {
        switch projection.benchmarkState {
        case .fresh: "数据源正常"
        case .loading: "正在同步"
        case .stale, .usingLastKnownGood: "使用缓存数据"
        case .empty: "暂无数据"
        case .validationFailed: "数据校验失败"
        case .unavailable, .disabled, .error: "数据源不可用"
        }
    }

    private var sourceHealthIcon: String {
        projection.benchmarkState == .fresh ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
}

struct DecisionLensPageView: View {
    let projection: WorkspaceProjection
    @State private var goal = RadarDecisionGoal.quality

    var body: some View {
        ScrollView {
            if projection.rows.isEmpty {
                ContentUnavailableView(
                    "暂无 Benchmark 数据",
                    systemImage: "scope",
                    description: Text("刷新后仍无数据时，请查看来源状态。")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                DecisionLensView(
                    rows: projection.rows,
                    familyRows: RadarIdentity.familySummaries(projection.rows).map(\.row),
                    goal: $goal
                )
                .padding(18)
            }
        }
    }
}

private struct DecisionLensView: View {
    let rows: [WorkspaceModelRow]
    let familyRows: [WorkspaceModelRow]
    @Binding var goal: RadarDecisionGoal

    private var recommendation: WorkspaceModelRow? {
        RadarDecisionLens.recommendation(in: rows, for: goal)
    }

    var body: some View {
        GroupBox("决策透镜 · 选择目标，获得推荐") {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("选择你的目标")
                        .font(.headline)
                    ForEach(RadarDecisionGoal.allCases) { candidate in
                        Button {
                            goal = candidate
                        } label: {
                            HStack {
                                Image(systemName: candidate.icon).frame(width: 18)
                                Text(candidate.rawValue)
                                Spacer()
                                if goal == candidate {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(8)
                            .background(
                                goal == candidate ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: .rect(cornerRadius: 7)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(
                                        goal == candidate
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.25)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("决策目标：\(candidate.rawValue)")
                    }
                }
                .frame(width: 190)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("模型对比图")
                        .font(.headline)
                    Text("IQ ↑ · 每题平均耗时 →")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(familyRows) { row in
                        PointMark(
                            x: .value("每题平均耗时", RadarVisuals.secondsPerTask(row) ?? 0),
                            y: .value("IQ", RadarVisuals.double(row.benchmark.qualityScore ?? 0))
                        )
                        .symbolSize(row.id == recommendation?.id ? 180 : 95)
                        .foregroundStyle(RadarVisuals.familyColor(RadarIdentity.family(for: row)))
                        .annotation(position: .top) {
                            Text(RadarIdentity.family(for: row))
                                .font(.caption2.weight(.medium))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(minHeight: 220)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("推荐结果")
                        .font(.headline)
                    if let recommendation {
                        Label("推荐模型", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(RadarIdentity.family(for: recommendation))
                            .font(.title.bold())
                        Text(RadarIdentity.tier(for: recommendation) ?? recommendation.name)
                            .foregroundStyle(.secondary)
                        Divider()
                        LabeledContent("综合 IQ", value: RadarFormat.decimal(recommendation.benchmark.qualityScore))
                        LabeledContent(
                            "测试通过 / 有效",
                            value: "\(RadarFormat.integer(recommendation.benchmark.passedTasks)) / \(RadarFormat.integer(recommendation.benchmark.validTasks))"
                        )
                        LabeledContent(
                            "每题成本",
                            value: RadarVisuals.costPerTask(recommendation).map { "$\(RadarFormat.decimal($0))" } ?? "—"
                        )
                        LabeledContent(
                            "平均耗时",
                            value: RadarVisuals.duration(RadarVisuals.secondsPerTask(recommendation))
                        )
                    } else {
                        ContentUnavailableView(
                            "数据不足",
                            systemImage: "questionmark.circle",
                            description: Text("当前指标不足以生成推荐。")
                        )
                    }
                }
                .frame(width: 230, alignment: .leading)
            }
            .padding(.top, 6)
        }
    }
}

enum RadarDecisionGoal: String, CaseIterable, Identifiable, Sendable {
    case quality = "最高质量"
    case value = "性价比"
    case quota = "最低额度"
    case speed = "最快完成"

    var id: Self { self }
    var icon: String {
        switch self {
        case .quality: "sparkles"
        case .value: "diamond"
        case .quota: "gauge.with.dots.needle.0percent"
        case .speed: "clock"
        }
    }
}

struct RadarPerformanceRow: Identifiable {
    let id: ModelID
    let name: String
    let family: String
    let tier: String?
    let quality: Decimal?
    let delta: Decimal?
    let costPerTask: Decimal?
    let secondsPerTask: Double?
}

enum RadarRecentPerformance {
    static func rows(
        current: [WorkspaceModelRow],
        history: [BenchmarkDataset],
        limit: Int = 5
    ) -> [RadarPerformanceRow] {
        let sourceID = current.first?.id.sourceID
        let snapshots = history
            .filter { $0.sourceID == sourceID }
            .sorted { ($0.sourceUpdatedAt ?? $0.fetchedAt) < ($1.sourceUpdatedAt ?? $1.fetchedAt) }
        let previous = snapshots.count > 1 ? snapshots[snapshots.count - 2] : nil
        let latest = snapshots.last
        let previousByID = previous?.seriesRevision == latest?.seriesRevision
            ? Dictionary(uniqueKeysWithValues: previous?.models.map { ($0.id, $0) } ?? [])
            : [:]

        return current
            .filter { $0.benchmark.qualityScore != nil }
            .sorted {
                let left = $0.benchmark.qualityScore ?? 0
                let right = $1.benchmark.qualityScore ?? 0
                if left != right { return left > right }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .prefix(limit)
            .map { row in
                RadarPerformanceRow(
                    id: row.id,
                    name: row.name,
                    family: RadarIdentity.family(for: row),
                    tier: RadarIdentity.tier(for: row),
                    quality: row.benchmark.qualityScore,
                    delta: row.benchmark.qualityScore.flatMap { quality in
                        previousByID[row.id]?.qualityScore.map { quality - $0 }
                    },
                    costPerTask: RadarVisuals.costPerTask(row),
                    secondsPerTask: RadarVisuals.secondsPerTask(row)
                )
            }
    }
}

enum RadarDecisionLens {
    static func recommendation(
        in rows: [WorkspaceModelRow],
        for goal: RadarDecisionGoal
    ) -> WorkspaceModelRow? {
        rows.compactMap { row -> (WorkspaceModelRow, Double)? in
            let metric: Double?
            switch goal {
            case .quality:
                metric = row.benchmark.qualityScore.map(RadarVisuals.double)
            case .value:
                guard let quality = row.benchmark.qualityScore.map(RadarVisuals.double),
                      let cost = RadarVisuals.costPerTask(row),
                      cost > 0 else { return nil }
                metric = quality / RadarVisuals.double(cost)
            case .quota:
                metric = RadarVisuals.costPerTask(row).map { -RadarVisuals.double($0) }
            case .speed:
                metric = RadarVisuals.secondsPerTask(row).map { -$0 }
            }
            return metric.map { (row, $0) }
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
        }
        .first?.0
    }
}

private enum RadarIdentity {
    static let tiers = ["ultra", "max", "xhigh", "high", "medium", "low"]

    static func family(for row: WorkspaceModelRow) -> String {
        let key = row.id.upstreamKey.lowercased()
        if key.contains("-sol-") { return "Sol" }
        if key.contains("-terra-") { return "Terra" }
        if key.contains("-luna-") { return "Luna" }
        if key.hasPrefix("gpt-5.5") { return "GPT-5.5" }
        guard tier(in: key, separator: "-") == nil,
              let displayTier = tier(in: row.name, separator: " ")
        else { return row.name }
        return row.name.dropLast(displayTier.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tier(for row: WorkspaceModelRow) -> String? {
        tier(in: row.id.upstreamKey, separator: "-") ?? tier(in: row.name, separator: " ")
    }

    private static func tier(in value: String, separator: String) -> String? {
        tiers.first { value.lowercased().hasSuffix("\(separator)\($0)") }
    }

    static func familySummaries(_ rows: [WorkspaceModelRow]) -> [RadarFamilySummary] {
        let preferred = ["Sol", "Terra", "Luna", "GPT-5.5"]
        let grouped = Dictionary(grouping: rows, by: family)
        return grouped.compactMap { family, rows in
            guard let row = rows.compactMap({ $0.benchmark.qualityScore == nil ? nil : $0 })
                .max(by: { ($0.benchmark.qualityScore ?? 0) < ($1.benchmark.qualityScore ?? 0) })
            else { return nil }
            return RadarFamilySummary(family: family, row: row)
        }
        .sorted {
            let left = preferred.firstIndex(of: $0.family) ?? preferred.count
            let right = preferred.firstIndex(of: $1.family) ?? preferred.count
            if left != right { return left < right }
            return $0.family.localizedStandardCompare($1.family) == .orderedAscending
        }
        .prefix(4)
        .map { $0 }
    }
}

private enum RadarVisuals {
    static func qualityColor(_ value: Decimal?) -> Color {
        guard let value else { return .secondary }
        if value >= 85 { return .green }
        if value >= 70 { return .yellow }
        if value >= 50 { return .orange }
        return .red
    }

    static func familyColor(_ family: String) -> Color {
        switch family {
        case "Sol": .green
        case "Terra": .purple
        case "Luna": .orange
        case "GPT-5.5": .blue
        default: .teal
        }
    }

    static func familyIcon(_ family: String) -> String {
        switch family {
        case "Sol": "sun.max.fill"
        case "Terra": "globe.americas.fill"
        case "Luna": "moon.fill"
        default: "sparkle"
        }
    }

    static func costPerTask(_ row: WorkspaceModelRow?) -> Decimal? {
        guard let row,
              let cost = row.benchmark.benchmarkCostUSD,
              let valid = row.benchmark.validTasks,
              valid > 0 else { return nil }
        return cost / Decimal(valid)
    }

    static func secondsPerTask(_ row: WorkspaceModelRow?) -> Double? {
        guard let row,
              let elapsed = row.benchmark.elapsedSeconds,
              let valid = row.benchmark.validTasks,
              valid > 0 else { return nil }
        return elapsed / Double(valid)
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        if seconds >= 60 { return "\(Int((seconds / 60).rounded())) 分钟" }
        return "\(Int(seconds.rounded())) 秒"
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    static func signed(_ value: Decimal) -> String {
        "\(value >= 0 ? "+" : "")\(RadarFormat.decimal(value))"
    }
}

private struct RadarFamilySummary: Identifiable {
    let family: String
    let row: WorkspaceModelRow
    var id: String { family }
}

struct CommunityAlertPresentation: Equatable, Sendable {
    let state: WorkspaceState
    let message: String
}

struct AnalysisExplanation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("透明派生公式").font(.headline)
            ForEach(DerivedMetricFormula.allCases, id: \.self) { formula in
                Text("\(formula.name)：\(formula.formulaText) · \(formula.unit)")
            }
            Text(ParetoPreset.qualityCost.explanation)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
}

struct ViewHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

struct StateBanner: View {
    let state: WorkspaceState
    let error: String?
    let sourceName: String

    init(state: WorkspaceState, error: String?, sourceName: String = "Claude Code Radar") {
        self.state = state
        self.error = error
        self.sourceName = sourceName
    }

    var body: some View {
        Label(Self.message(for: state, error: error, sourceName: sourceName), systemImage: icon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: .rect(cornerRadius: 8))
    }

    static func message(
        for state: WorkspaceState,
        error: String?,
        sourceName: String = "Claude Code Radar"
    ) -> String {
        switch state {
        case .loading: "正在载入 \(sourceName) 数据"
        case .empty: "当前没有可显示的数据"
        case .fresh: "刚刚同步成功"
        case .stale: "正在使用最后良好数据；数据可能已过期"
        case .usingLastKnownGood: error.map { "正在使用最近一次良好数据\n\($0)" } ?? "正在使用最近一次良好数据"
        case .validationFailed(let hasLastKnownGood):
            error ?? (hasLastKnownGood ? "新数据未通过校验，已保留旧值" : "新数据未通过校验，暂无可用旧值")
        case .unavailable(let text), .disabled(let text), .error(let text): text
        }
    }

    private var icon: String {
        switch state {
        case .fresh: "checkmark.circle"
        case .loading: "arrow.triangle.2.circlepath"
        case .empty: "tray"
        case .stale: "clock.badge.exclamationmark"
        case .usingLastKnownGood, .validationFailed, .error: "exclamationmark.triangle"
        case .unavailable: "questionmark.circle"
        case .disabled: "lock.shield"
        }
    }
}
