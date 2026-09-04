import SwiftUI

struct SourceStatusView: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(title: WorkspaceCopy.sourceStatusTitle(for: projection.source), subtitle: "更新时间：\(RadarFormat.date(projection.sync?.sourceStatus.value?.sourceUpdatedAt ?? projection.sync?.sourceStatus.value?.fetchedAt))")
                StateBanner(state: projection.supportState, error: nil, sourceName: projection.source.displayName)
                GroupBox(WorkspaceCopy.quotaTitle(for: projection.source)) {
                    VStack(alignment: .leading, spacing: 12) {
                        if quotas.isEmpty { Text("暂无来源额度估算").foregroundStyle(palette.secondaryText.color) }
                        ForEach(quotas) { quota in
                            LabeledContent(quota.windowLabel) { VStack(alignment: .trailing) { Text(quotaValue(quota)); Text(quota.resetDescription ?? "未提供估算依据").font(.caption).foregroundStyle(palette.secondaryText.color) } }
                        }
                        Text("这些值来自 \(projection.source.displayName) 的公开估算，不代表任何用户账户用量。")
                            .font(.caption).foregroundStyle(palette.secondaryText.color).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                .groupBoxStyle(RadarGroupBoxStyle())
                GroupBox("分段状态") {
                    VStack(alignment: .leading, spacing: 10) {
                        status("Benchmark", projection.benchmarkState)
                        status("社区评分", projection.communityState)
                        status("来源状态", projection.sourceStatusState)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                .groupBoxStyle(RadarGroupBoxStyle())
                if let error = projection.latestError {
                    StateBanner(state: .error(error), error: nil, sourceName: projection.source.displayName)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let homepageURL = projection.source.homepageURL {
                    Link("打开 \(projection.source.displayName) 来源主页", destination: homepageURL)
                }
            }
            .radarPage()
        }
    }
    private var quotas: [SourceQuotaEstimate] { projection.sync?.sourceStatus.value?.quotaEstimates ?? [] }
    private func quotaValue(_ quota: SourceQuotaEstimate) -> String {
        if let usedPercent = quota.usedPercent { return RadarFormat.decimal(usedPercent, suffix: "%") }
        return quota.estimatedValueUSD.map { "$\(RadarFormat.decimal($0))" } ?? "—"
    }
    private func status(_ label: String, _ state: WorkspaceState) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(short(state)).foregroundStyle(statusColor(state))
        }
    }
    private func statusColor(_ state: WorkspaceState) -> Color {
        switch state {
        case .fresh: palette.positive.color
        case .validationFailed, .error: palette.negative.color
        default: palette.secondaryText.color
        }
    }
    private func short(_ state: WorkspaceState) -> String { switch state { case .loading: "载入中"; case .empty: "无数据"; case .fresh: "正常"; case .stale: "陈旧"; case .usingLastKnownGood: "正在使用最近一次良好数据"; case .validationFailed(let hasLastKnownGood): hasLastKnownGood ? "新数据未通过校验，已保留旧值" : "新数据未通过校验，暂无可用旧值"; case .unavailable(let v), .disabled(let v), .error(let v): v } }
}
