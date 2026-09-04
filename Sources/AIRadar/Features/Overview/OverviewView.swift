import SwiftUI

struct OverviewView: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    let refreshIntervalMinutes: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                OverviewHeaderSections(projection: projection)
                OfficialOverviewSections(projection: projection, history: history)

                if projection.rows.isEmpty {
                    ContentUnavailableView(
                        "暂无 Benchmark 数据",
                        systemImage: "chart.bar.xaxis",
                        description: Text("刷新后仍无数据时，请查看来源状态。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    OverviewLocalSections(
                        projection: projection,
                        history: history,
                        refreshIntervalMinutes: refreshIntervalMinutes
                    )
                }
            }
            .radarPage()
            .groupBoxStyle(RadarGroupBoxStyle())
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
}
