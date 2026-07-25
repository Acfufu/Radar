import SwiftUI

@MainActor
struct InformationOverviewView: View {
    @Environment(\.radarPalette) private var palette
    let model: RadarWorkspaceModel
    let openSource: (RadarSourceID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                compactHeader
                informationNotice
                operationalStrip
                ForEach(model.sources) { source in
                    sourceBand(source)
                }
            }
            .radarPage()
        }
        .navigationTitle("信息总览")
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("信息总览")
                .font(.title2.bold())
            Text("浏览各来源已发布信息；指标口径保持独立")
                .font(.callout)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
        }
    }

    private var informationNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(palette.accent.color)
            Text("各来源口径独立，不生成统一排名")
                .font(.callout)
                .foregroundStyle(palette.primaryText.color)
        }
        .padding(RadarStyle.compactSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accentSoft.color, in: .rect(cornerRadius: RadarStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RadarStyle.cornerRadius)
                .stroke(palette.accentBorder.color)
        }
    }

    private var operationalStrip: some View {
        let projections = model.sources.compactMap { model.projection(for: $0.id) }
        let available = projections.filter { !$0.rows.isEmpty }.count
        let retained = projections.filter { projection in
            if projection.benchmarkState == .usingLastKnownGood { return true }
            if case .validationFailed(hasLastKnownGood: true) = projection.benchmarkState { return true }
            return false
        }.count
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: RadarStyle.compactSpacing)],
            spacing: RadarStyle.compactSpacing
        ) {
            summaryCard("来源", value: "\(model.sources.count)", icon: "square.stack.3d.up")
            summaryCard("已有快照", value: "\(available)", icon: "checkmark.circle")
            summaryCard("使用 LKG", value: "\(retained)", icon: "clock.arrow.circlepath")
        }
    }

    private func summaryCard(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(palette.accent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .radarMetricCard()
    }

    private func sourceBand(_ source: RadarSourceDescriptor) -> some View {
        let projection = model.projection(for: source.id)
        let leader = projection?.rows
            .filter { $0.benchmark.qualityScore != nil }
            .max {
                if $0.benchmark.qualityScore != $1.benchmark.qualityScore {
                    return ($0.benchmark.qualityScore ?? 0) < ($1.benchmark.qualityScore ?? 0)
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedDescending
            }
        let metricName = source.id == .sweBenchVerified ? "% Resolved" : "IQ"

        return VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Label(source.displayName, systemImage: source.icon)
                    .font(.headline)
                Spacer()
                Label(stateText(projection?.benchmarkState), systemImage: stateIcon(projection?.benchmarkState))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
            }
            Divider().overlay(palette.divider.color)
            HStack(alignment: .firstTextBaseline, spacing: RadarStyle.compactSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metricName)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                    Text(RadarFormat.decimal(leader?.benchmark.qualityScore))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(leader?.name ?? "等待已发布快照")
                        .font(.headline)
                        .lineLimit(2)
                    Text(sourceContext(source, projection: projection))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                }
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                sourceActions(source, projection: projection)
                sourceActionsStacked(source, projection: projection)
            }
        }
        .radarPanel()
    }

    private func sourceActions(_ source: RadarSourceDescriptor, projection: WorkspaceProjection?) -> some View {
        HStack {
            Button("打开来源分析") { openSource(source.id) }
            if let homepageURL = source.homepageURL {
                Link("打开上游页面", destination: homepageURL)
            }
            Spacer()
            timestamp(projection)
        }
    }

    private func sourceActionsStacked(_ source: RadarSourceDescriptor, projection: WorkspaceProjection?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("打开来源分析") { openSource(source.id) }
                if let homepageURL = source.homepageURL {
                    Link("打开上游页面", destination: homepageURL)
                }
            }
            timestamp(projection)
        }
    }

    private func timestamp(_ projection: WorkspaceProjection?) -> some View {
        Text("读取于 \(RadarFormat.date(projection?.updatedAt))")
            .font(.caption)
            .foregroundStyle(palette.secondaryText.color)
    }

    private func sourceContext(_ source: RadarSourceDescriptor, projection: WorkspaceProjection?) -> String {
        if source.id == .sweBenchVerified {
            return "Verified · mini-SWE-agent v2 · 500 tasks"
        }
        let count = projection?.rows.count ?? 0
        return "\(count) 个来源内模型配置 · \(source.seriesRevision)"
    }

    private func stateText(_ state: WorkspaceState?) -> String {
        switch state {
        case .fresh: "正常"
        case .stale: "陈旧"
        case .usingLastKnownGood: "LKG"
        case .validationFailed(let hasLastKnownGood): hasLastKnownGood ? "校验失败 · LKG" : "校验失败"
        case .loading: "载入中"
        case .empty, nil: "暂无数据"
        case .disabled: "在线读取关闭"
        case .unavailable, .error: "不可用"
        }
    }

    private func stateIcon(_ state: WorkspaceState?) -> String {
        switch state {
        case .fresh: "checkmark.circle.fill"
        case .stale, .usingLastKnownGood, .validationFailed: "clock.arrow.circlepath"
        case .loading: "arrow.triangle.2.circlepath"
        case .empty, nil: "circle.dashed"
        case .disabled: "pause.circle"
        case .unavailable, .error: "exclamationmark.triangle"
        }
    }
}

private extension RadarSourceDescriptor {
    var icon: String {
        switch id {
        case .sweBenchVerified: "checkmark.seal"
        case .codexRadar: "terminal"
        default: "scope"
        }
    }
}
