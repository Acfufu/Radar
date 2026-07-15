import SwiftUI

struct SourceStatusView: View {
    let projection: WorkspaceProjection
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewHeader(title: WorkspaceCopy.sourceStatusTitle, subtitle: "更新时间：\(RadarFormat.date(projection.sync?.sourceStatus.value?.sourceUpdatedAt ?? projection.sync?.sourceStatus.value?.fetchedAt))")
                StateBanner(state: projection.supportState, error: nil)
                GroupBox(WorkspaceCopy.quotaTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        if quotas.isEmpty { Text("暂无来源额度估算").foregroundStyle(.secondary) }
                        ForEach(quotas) { quota in
                            LabeledContent(quota.windowLabel) { VStack(alignment: .trailing) { Text(RadarFormat.decimal(quota.usedPercent, suffix: "%")); Text(quota.resetDescription ?? "未提供重置说明").font(.caption).foregroundStyle(.secondary) } }
                        }
                        Text("这些值来自 Claude Code Radar 的公开估算，不代表任何用户账户用量。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                GroupBox("分段状态") {
                    VStack(alignment: .leading, spacing: 10) {
                        status("Benchmark", projection.benchmarkState)
                        status("社区评分", projection.communityState)
                        status("来源状态", projection.sourceStatusState)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                if let error = projection.latestError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                Link("打开 Claude Code Radar 来源主页", destination: URL(string: "https://claudecoderadar.com/?lang=en")!)
            }.padding(24)
        }
    }
    private var quotas: [SourceQuotaEstimate] { projection.sync?.sourceStatus.value?.quotaEstimates ?? [] }
    private func status(_ label: String, _ state: WorkspaceState) -> some View { HStack { Text(label); Spacer(); Text(short(state)).foregroundStyle(.secondary) } }
    private func short(_ state: WorkspaceState) -> String { switch state { case .loading: "载入中"; case .empty: "无数据"; case .fresh: "正常"; case .stale: "陈旧"; case .usingLastKnownGood: "正在使用最近一次良好数据"; case .validationFailed(let hasLastKnownGood): hasLastKnownGood ? "新数据未通过校验，已保留旧值" : "新数据未通过校验，暂无可用旧值"; case .unavailable(let v), .disabled(let v), .error(let v): v } }
}
