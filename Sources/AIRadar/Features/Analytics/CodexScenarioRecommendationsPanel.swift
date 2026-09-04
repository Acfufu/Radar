import SwiftUI

struct CodexScenarioRecommendationsPanel: View {
    let recommendations: CodexScenarioRecommendations

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
            Text("场景推荐")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), alignment: .top)],
                alignment: .leading,
                spacing: RadarStyle.cardSpacing
            ) {
                ForEach(recommendations.groups) { group in
                    ScenarioCard(group: group)
                }
            }

            Text("Radar 按 Codex Radar 公开摘要计算")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .radarPanel()
    }
}

private struct ScenarioCard: View {
    let group: CodexScenarioRecommendationGroup

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Text(group.scenario.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(group.rule)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(group.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(group.provenance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if group.recommendations.isEmpty {
                Text("不可用：没有符合条件的完整指标")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(group.recommendations.prefix(2)) { point in
                    RecommendationRow(point: point)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("codex-scenario-\(group.scenario.rawValue)")
        .radarMetricCard()
    }
}

private struct RecommendationRow: View {
    let point: IntelligenceEfficiencyPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("模型") {
                Text(point.modelName)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("IQ", value: number(point.quality))
            LabeledContent("平均费用 / 每个有效任务", value: cost(point.averageCostUSD))
            LabeledContent("平均耗时 / 每个有效任务", value: minutes(point.averageMinutes))
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("模型 \(point.modelName)，IQ \(number(point.quality))，平均费用 / 每个有效任务 \(cost(point.averageCostUSD))，平均耗时 / 每个有效任务 \(minutes(point.averageMinutes))")
    }

    private func number(_ value: Double) -> String {
        guard value.isFinite else { return "不可用" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private func cost(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "不可用" }
        return "$" + value.formatted(.number.precision(.fractionLength(2)))
    }

    private func minutes(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "不可用" }
        if value < 0.1 { return "<0.1 分钟" }
        return value.formatted(.number.precision(.fractionLength(1))) + " 分钟"
    }
}
