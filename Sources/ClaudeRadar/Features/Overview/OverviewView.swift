import SwiftUI

struct OverviewView: View {
    let projection: WorkspaceProjection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewHeader(title: "概览", subtitle: "\(projection.source.displayName) · 更新于 \(RadarFormat.date(projection.updatedAt))")
                if let supportState = Self.presentation(for: projection).supportState {
                    StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
                }
                if let healthState = Self.presentation(for: projection).healthState {
                    StateBanner(state: healthState, error: Self.presentation(for: projection).error, sourceName: projection.source.displayName)
                }
                if let community = Self.communityPresentation(for: projection) {
                    Label(community.message, systemImage: "person.2.badge.exclamationmark")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .foregroundStyle(.orange)
                        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
                }
                if projection.rows.isEmpty {
                    ContentUnavailableView("暂无 Benchmark 数据", systemImage: "chart.bar.xaxis", description: Text("刷新后仍无数据时，请查看来源状态。"))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVGrid(columns: [.init(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                        SummaryCard(title: "模型数量", value: "\(projection.rows.count)", detail: "当前 revision")
                        SummaryCard(title: "质量最高", value: best?.name ?? "—", detail: RadarFormat.decimal(best?.benchmark.qualityScore))
                        SummaryCard(
                            title: "最佳成本效率",
                            value: projection.bestCostEfficiency?.modelName ?? "数据不足",
                            detail: costEfficiencyDetail
                        )
                        SummaryCard(title: "当前口径", value: projection.sync?.benchmark.value?.seriesRevision ?? "—", detail: projection.sync?.benchmark.value?.benchmarkName ?? "未提供名称")
                        SummaryCard(title: WorkspaceCopy.quotaTitle(for: projection.source), value: quotaSummary, detail: "来源公开估算")
                        SummaryCard(title: "质量 ↑ / 成本 ↓", value: "前沿 \(frontierCount)", detail: "仅当前同来源、同 revision")
                    }
                    AnalysisExplanation()
                }
                if projection.communityState == .unavailable("社区评分暂不可用") {
                    Label("社区评分暂不可用", systemImage: "person.2.slash").foregroundStyle(.secondary)
                }
            }
            .padding(24)
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

    private var best: WorkspaceModelRow? { projection.rows.compactMap { $0.benchmark.qualityScore == nil ? nil : $0 }.max { ($0.benchmark.qualityScore ?? 0) < ($1.benchmark.qualityScore ?? 0) } }
    private var costEfficiencyDetail: String {
        guard let leader = projection.bestCostEfficiency else {
            return "benchmarkCostUSD / passedTasks"
        }
        return "$\(RadarFormat.decimal(leader.costPerPassedTask)) / passed task · \(leader.formula.formulaText)"
    }
    private var quotaSummary: String {
        guard let quota = projection.sync?.sourceStatus.value?.quotaEstimates.first else { return "—" }
        if let usedPercent = quota.usedPercent {
            return "\(quota.windowLabel) · \(RadarFormat.decimal(usedPercent, suffix: "%"))"
        }
        return quota.estimatedValueUSD.map { "\(quota.windowLabel) · $\(RadarFormat.decimal($0))" } ?? quota.windowLabel
    }
    private var frontierCount: Int { projection.pareto(.qualityCost).count { $0.classification == .frontier } }
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
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.largeTitle.bold()); Text(subtitle).foregroundStyle(.secondary).textSelection(.enabled) } }
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
        Label(Self.message(for: state, error: error, sourceName: sourceName), systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.quaternary, in: .rect(cornerRadius: 10))
    }
    static func message(for state: WorkspaceState, error: String?, sourceName: String = "Claude Code Radar") -> String { switch state { case .loading: "正在载入 \(sourceName) 数据"; case .empty: "当前没有可显示的数据"; case .fresh: "刚刚同步成功"; case .stale: "正在使用最后良好数据；数据可能已过期"; case .usingLastKnownGood: error.map { "正在使用最近一次良好数据\n\($0)" } ?? "正在使用最近一次良好数据"; case .validationFailed(let hasLastKnownGood): error ?? (hasLastKnownGood ? "新数据未通过校验，已保留旧值" : "新数据未通过校验，暂无可用旧值"); case .unavailable(let text), .disabled(let text), .error(let text): text } }
    private var icon: String { switch state { case .fresh: "checkmark.circle"; case .loading: "arrow.triangle.2.circlepath"; case .empty: "tray"; case .stale: "clock.badge.exclamationmark"; case .usingLastKnownGood, .validationFailed, .error: "exclamationmark.triangle"; case .unavailable: "questionmark.circle"; case .disabled: "lock.shield" } }
}

private struct SummaryCard: View {
    let title: String; let value: String; let detail: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.weight(.semibold)).lineLimit(2); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(14).background(.background.secondary, in: .rect(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.45)) } }
}
