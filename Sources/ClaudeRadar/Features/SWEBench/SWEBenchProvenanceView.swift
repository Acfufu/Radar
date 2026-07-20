import SwiftUI

struct SWEBenchProvenanceView: View {
    let projection: WorkspaceProjection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewHeader(
                    title: "来源与口径",
                    subtitle: "SWE-bench Verified · mini-SWE-agent v2"
                )
                if let supportState = projection.benchmarkPresentation.supportState {
                    StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
                }
                GroupBox("测评口径") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("数据集", value: "SWE-bench Verified")
                        LabeledContent("Agent 基线", value: "mini-SWE-agent v2")
                        LabeledContent("任务数", value: "500")
                        LabeledContent("% Resolved", value: "resolved tasks / 500 × 100")
                        LabeledContent("seriesRevision", value: projection.source.seriesRevision)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                GroupBox("读取状态") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("最近读取", value: RadarFormat.date(projection.updatedAt))
                        LabeledContent("本地状态", value: stateText)
                        if let error = projection.latestError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                GroupBox("只读边界") {
                    Text("Radar 读取、缓存、分析和导出上游已发布榜单；不运行评测、不提交结果、不生成任务数据，也不回写上游。")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                if let homepageURL = projection.source.homepageURL {
                    Link("打开 SWE-bench 官方页面", destination: homepageURL)
                }
            }
            .padding(24)
        }
        .navigationTitle("来源与口径")
    }

    private var stateText: String {
        switch projection.benchmarkState {
        case .fresh: "正常"
        case .stale: "陈旧"
        case .usingLastKnownGood: "使用最近一次良好数据"
        case .validationFailed(let hasLastKnownGood):
            hasLastKnownGood ? "新数据校验失败，保留旧值" : "新数据校验失败"
        case .loading: "载入中"
        case .empty: "暂无数据"
        case .unavailable(let value), .disabled(let value), .error(let value): value
        }
    }
}
