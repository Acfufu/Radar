import Foundation
import SwiftUI

extension OverviewLocalSections {
    var recentPerformance: [RadarPerformanceRow] {
        RadarRecentPerformance.rows(current: projection.rows, history: history)
    }

    var declineSignals: [RadarDeclineSignal] {
        projection.localDeclineSignals(history: history)
    }

    var efficiencyPoints: [IntelligenceEfficiencyPoint] {
        projection.intelligenceEfficiency.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return $0.modelName.localizedStandardCompare($1.modelName) == .orderedAscending
        }
    }

    var sourceHistory: [BenchmarkDataset] {
        history.filter { $0.sourceID == projection.source.id }
    }

    var monitoringDate: Date? {
        projection.sync?.benchmark.lastAttemptedAt ?? projection.updatedAt
    }

    func monitoringAge(at now: Date) -> String {
        guard let monitoringDate else { return "尚未同步" }
        let seconds = max(0, now.timeIntervalSince(monitoringDate))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前" }
        return "\(Int(seconds / 3_600)) 小时前"
    }

    func monitoringProgress(at now: Date) -> Double {
        guard let monitoringDate else { return 0 }
        let interval = TimeInterval(refreshIntervalMinutes * 60)
        return min(max(now.timeIntervalSince(monitoringDate) / interval, 0), 1)
    }

    func nextMonitoringText(at now: Date) -> String {
        guard let monitoringDate else { return "等待首次同步" }
        let remaining = TimeInterval(refreshIntervalMinutes * 60) - now.timeIntervalSince(monitoringDate)
        guard remaining > 0 else { return "已进入下一次自动同步窗口" }
        return "约 \(max(1, Int(ceil(remaining / 60)))) 分钟后检查更新"
    }

    @ViewBuilder func heatCell(row: WorkspaceModelRow?) -> some View {
        let quality = row?.benchmark.qualityScore
        Text(RadarFormat.decimal(quality))
            .font(.caption.monospacedDigit())
            .frame(minWidth: 40, maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RadarVisuals.qualityColor(quality).opacity(quality == nil ? 0.03 : 0.18))
            .foregroundStyle(quality == nil ? .secondary : .primary)
    }

    var peak: WorkspaceModelRow? {
        overviewPeak(in: projection.rows)
    }

    var familySummaries: [RadarFamilySummary] {
        RadarModelIdentity.familySummaries(projection.rows)
    }

    var heatmapFamilies: [String] {
        familySummaries.map(\.family).filter { family in
            projection.rows.contains {
                RadarModelIdentity.family(for: $0) == family && RadarModelIdentity.effort(for: $0) != nil
            }
        }
        .prefix(3)
        .map { $0 }
    }

    func heatmapRow(family: String, tier: String) -> WorkspaceModelRow? {
        projection.rows.first {
            RadarModelIdentity.family(for: $0) == family && RadarModelIdentity.effort(for: $0) == tier
        }
    }

    var trendPoints: [TrendPoint] {
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

    var trendUpperBound: Double {
        let quality = peak?.benchmark.qualityScore.map(RadarVisuals.double) ?? 100
        return max(110, ceil(quality / 10) * 10)
    }

    var selectedQuota: SourceQuotaEstimate? {
        projection.sync?.sourceStatus.value?.quotaEstimates.first {
            $0.windowLabel.localizedCaseInsensitiveContains(subscription)
        }
    }

    var quotaValue: String {
        guard let selectedQuota else { return "—" }
        if let used = selectedQuota.usedPercent {
            return RadarFormat.decimal(used, suffix: "%")
        }
        return selectedQuota.estimatedValueUSD.map { "$\(RadarFormat.decimal($0))" } ?? "—"
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
                    family: RadarModelIdentity.family(for: row),
                    tier: RadarModelIdentity.effort(for: row),
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


enum RadarVisuals {
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

struct RadarFamilySummary: Identifiable {
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
