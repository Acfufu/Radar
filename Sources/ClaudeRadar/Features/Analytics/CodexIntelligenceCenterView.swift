import SwiftUI

struct CodexIntelligenceCenterView: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(
                    title: "智力中心",
                    subtitle: "\(projection.source.displayName) · 当前数据与 \(history.count) 个 Radar 本地快照"
                )
                if let supportState = projection.benchmarkPresentation.supportState {
                    StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
                }
                if let healthState = projection.benchmarkPresentation.healthState, healthState != .fresh {
                    StateBanner(
                        state: healthState,
                        error: projection.benchmarkPresentation.error,
                        sourceName: projection.source.displayName
                    )
                }
                IntelligenceCenterSlot(title: "场景推荐", systemImage: "sparkles")
                IntelligenceCenterSlot(title: "智力效率", systemImage: "square.grid.3x3")
                IntelligenceCenterSlot(title: "综合成本 × IQ", systemImage: "chart.dots.scatter")
                IntelligenceCenterSlot(title: "IQ 历史数据", systemImage: "chart.xyaxis.line")
                IntelligenceCenterSlot(title: "历史数据比较", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                Text(projection.source.attributionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("数据来源：\(projection.source.attributionText)")
            }
            .radarPage()
        }
        .navigationTitle("智力中心")
    }
}

private struct IntelligenceCenterSlot: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .accessibilityAddTraits(.isHeader)
            .radarPanel()
    }
}
