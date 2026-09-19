import SwiftUI

/// Whitelist view station page (spec §4.1 v1.1, ADR-0003): the single
/// destination of DSH/ZCode/Grok — the same-benchmark efficiency ranking
/// plus model-tier details, cropped from the shared intelligence-efficiency
/// sidecar dataset by the station's frozen model whitelist (mirroring the
/// upstream front-end). No runtime, no independent sync; status follows the
/// shared dataset and attribution rides along.
struct WhitelistStationPage: View {
    @Environment(\.radarPalette) private var palette
    let station: WhitelistStation
    /// The Codex station's projection carries the shared sidecar datasets.
    let projection: WorkspaceProjection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(
                    title: "\(station.displayName) · 效能排行",
                    subtitle: "同基准效能排行与模型档位详情；按上游站点白名单裁剪，状态跟随共享数据面"
                )
                if let points = filteredPoints, !points.isEmpty {
                    rankingCard(points)
                    tierDetailCard(points)
                } else {
                    emptyState
                }
                Text(attributionText)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
            .radarPage()
        }
    }

    private var filteredPoints: [IntelligenceEfficiencyDataset.Point]? {
        guard let dataset = projection?.intelligenceEfficiencyDataset else { return nil }
        let whitelist = station.modelWhitelist
        // Payload order is the upstream ranking; filtering preserves it and
        // never re-ranks locally (no unified ranking across stations).
        let rows = dataset.points.filter { whitelist.contains($0.model ?? "") }
        return rows
    }

    private var attributionText: String {
        let freshness: String
        if let updatedAt = projection?.intelligenceEfficiencyDataset?.sourceUpdatedAt {
            freshness = " · 数据面更新于 \(updatedAt)"
        } else {
            freshness = ""
        }
        return projection?.source.attributionText.appending(freshness) ?? "数据来自 Codex 雷达 codexradar.com"
    }

    private func rankingCard(_ points: [IntelligenceEfficiencyDataset.Point]) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            ViewHeader(title: "同基准效能排行", subtitle: "上游 IQ 排序原样呈现（白名单内）")
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                HStack {
                    Text("#\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .monospacedDigit()
                    Text("\(point.model ?? "—") · \(point.effort ?? "—")")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let iq = point.iq {
                        Text("IQ \(String(format: "%.1f", iq))")
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }

    private func tierDetailCard(_ points: [IntelligenceEfficiencyDataset.Point]) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            ViewHeader(title: "模型档位详情", subtitle: "运行级口径与成本/时长参考（原样转存）")
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(point.model ?? "—") · \(point.effort ?? "—")")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if let passed = point.passed {
                            Text("通过 \(String(format: "%.1f", passed))")
                                .monospacedDigit()
                        }
                    }
                    HStack(spacing: 10) {
                        if let price = point.averagePriceUSD {
                            Text("均价 $\(price)")
                        }
                        if let minutes = point.averageMinutes {
                            Text("均时长 \(String(format: "%.1f", minutes)) 分钟")
                        }
                        if let runs = point.runsTotal {
                            Text("累计 \(runs) 次")
                        }
                        if let valid = point.validTasks {
                            Text("有效任务 \(Int(valid))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .monospacedDigit()
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Text("暂无效能数据")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText.color)
            Text("共享数据面尚未同步，或白名单内暂无可比档位。")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }
}
