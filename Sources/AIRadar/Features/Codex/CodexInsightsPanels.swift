import SwiftUI

// v0.4.0 structured panels for the radar-insights and visual-spatial-
// reasoning sidecars (spec §5.6/§5.7, §4.2 rows 1–2). Components consume
// locally defined display view-models only — never repository dataset or
// entity types (spec §7 constraint). Texts carried from upstream are shown
// verbatim with attribution; nothing is derived locally.

/// One sortable row in a capability tab: a model tier and its score.
struct CapabilityRowView: Identifiable, Equatable, Sendable {
    let id: String
    let model: String
    let effort: String
    let score: Double?
    let samples: Int?

    init(model: String, effort: String, score: Double?, samples: Int?) {
        id = "\(model)@\(effort)"
        self.model = model
        self.effort = effort
        self.score = score
        self.samples = samples
    }
}

/// One capability tab as displayed: rows plus a series caption naming the
/// score's provenance (the three capabilities are separate planes and are
/// never merged or cross-validated, spec §5.7).
struct CapabilityTabView: Equatable, Sendable {
    let title: String
    let systemImage: String
    let rows: [CapabilityRowView]
    let scoreCaption: String
    let isEmpty: Bool
}

/// Station-owner recommendation: one scene with upstream-authored rule text
/// and item rows, transcribed verbatim (spec §2 v1.1, D13-style).
struct StationRecommendationView: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rule: String?
    let items: [RecommendationItemView]

    struct RecommendationItemView: Identifiable, Equatable, Sendable {
        let id: String
        let model: String
        let effort: String
        let iq: Double?
        let averageCostUSD: Decimal?
        let averageDurationMinutes: Double?
        let combinedCostIndex: Double?
        let rule: String?
    }
}

/// Structured degradation alert row: coexists with the rendered warning
/// reader v2 — the two never merge, validate, or replace each other
/// (spec §5.6 hard rule).
struct DegradationAlertView: Identifiable, Equatable, Sendable {
    let id: String
    let model: String
    let effort: String
    let severity: String?
    let message: String?
    let currentIq: Double?
    let baselineIq: Double?
}

/// Row 1: the three-capability tab card (🧠 comprehensive / 💻 software /
/// 🧩 visual-spatial). The visual tab's data comes from the VSR sidecar
/// dataset — an independent benchmark (Adjacency F1) displayed on its own
/// path with its own caption, never merged with `visual_iq`.
struct CodexCapabilityTabsCard: View {
    @Environment(\.radarPalette) private var palette
    @State private var selection: Int = 0
    let tabs: [CapabilityTabView]
    let attributionText: String

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            if tabs.isEmpty || tabs.allSatisfy({ $0.isEmpty }) {
                emptyState
            } else {
                Picker("能力", selection: $selection) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Label(tabs[index].title, systemImage: tabs[index].systemImage)
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
                let tab = selection < tabs.count ? tabs[selection] : tabs.first
                if let tab {
                    if tab.isEmpty {
                        Text("暂无该能力数据")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText.color)
                    } else {
                        Text(tab.scoreCaption)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                        ForEach(tab.rows) { row in
                            HStack {
                                Text("\(row.model) · \(row.effort)")
                                Spacer()
                                if let score = row.score {
                                    Text(score, format: .number.precision(.fractionLength(0...2)))
                                        .monospacedDigit()
                                } else {
                                    Text("—")
                                        .foregroundStyle(palette.secondaryText.color)
                                }
                                if let samples = row.samples {
                                    Text("n=\(samples)")
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText.color)
                                        .monospacedDigit()
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }
                Text(attributionText)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }

    private var emptyState: some View {
        Text("暂无综合智能数据")
            .font(.subheadline)
            .foregroundStyle(palette.secondaryText.color)
    }
}

/// Row 2: structured degradation-alerts card fed by the radar-insights
/// `degradation_alerts` block. Upstream rule text is verbatim; the rendered
/// warning card above stays untouched (both planes coexist).
struct CodexAlertsStructuredCard: View {
    @Environment(\.radarPalette) private var palette
    let rule: String?
    let alerts: [DegradationAlertView]
    let attributionText: String

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Label("降智预警（结构化）", systemImage: "list.bullet.clipboard")
                .font(.headline)
                .foregroundStyle(palette.amber.color)
            if alerts.isEmpty {
                Text("暂无结构化预警（alerts 为空或未同步）")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
            } else {
                if let rule, !rule.isEmpty {
                    Text(rule)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .textSelection(.enabled)
                }
                ForEach(alerts) { alert in
                    alertRow(alert)
                }
            }
            Text(attributionText)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarAccentCard(accent: palette.amber, soft: palette.amberSoft)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func alertRow(_ alert: DegradationAlertView) -> some View {
        let currentText = alert.currentIq.map { "当前 IQ " + Self.oneDecimal($0) }
        let baselineText = alert.baselineIq.map { " · 基准 " + Self.oneDecimal($0) }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(alert.model) · \(alert.effort)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let severity = alert.severity {
                    Text(severity)
                        .font(.caption)
                        .foregroundStyle(palette.amber.color)
                }
            }
            if let message = alert.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .textSelection(.enabled)
            }
            if let currentText {
                Text(currentText + (baselineText ?? ""))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Row 2: station-owner recommendation structured card fed by the
/// radar-insights `recommendations` scenes. Titles/rules are upstream text
/// verbatim; the D4 upstream link card stays alongside — Radar derives
/// nothing locally.
struct CodexStationRecommendationCard: View {
    @Environment(\.radarPalette) private var palette
    let scenes: [StationRecommendationView]
    let attributionText: String

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Label("站长推荐（结构化）", systemImage: "text.badge.star")
                .font(.headline)
                .foregroundStyle(palette.green.color)
            if scenes.isEmpty {
                Text("暂无结构化推荐（未同步或上游未发布）")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
            } else {
                ForEach(scenes) { scene in
                    VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                        Text(scene.title)
                            .font(.subheadline.weight(.semibold))
                        if let rule = scene.rule, !rule.isEmpty {
                            Text(rule)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText.color)
                                .textSelection(.enabled)
                        }
                        ForEach(scene.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(item.model) · \(item.effort)")
                                        .font(.subheadline)
                                    Spacer()
                                    if let iq = item.iq {
                                        Text("IQ \(iq, format: .number.precision(.fractionLength(0...1)))")
                                            .monospacedDigit()
                                    }
                                }
                                HStack(spacing: 10) {
                                    if let cost = item.averageCostUSD {
                                        Text("均成本 $\(cost)")
                                    }
                                    if let minutes = item.averageDurationMinutes {
                                        Text("均时长 \(minutes, format: .number.precision(.fractionLength(0...1))) 分钟")
                                    }
                                    if let index = item.combinedCostIndex {
                                        Text("组合成本 \(index, format: .number.precision(.fractionLength(0...1)))")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText.color)
                                .monospacedDigit()
                                if let rule = item.rule, !rule.isEmpty {
                                    Text(rule)
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText.color)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Text(attributionText)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarAccentCard(accent: palette.green, soft: palette.greenSoft)
    }
}


// MARK: - View-model mapping (spec §7: pages/components consume view-models)

extension WorkspaceProjection {
    /// Three-capability tabs: comprehensive + software from radar-insights,
    /// visual-spatial from the independent VSR dataset (never merged with
    /// comprehensive `visual_iq`, spec §5.7).
    var capabilityTabs: [CapabilityTabView] {
        let insights = radarInsightsDataset
        let vsr = visualSpatialReasoningDataset
        let comprehensive = CapabilityTabView(
            title: "综合智能",
            systemImage: "brain",
            rows: (insights?.comprehensivePoints ?? []).map {
                CapabilityRowView(model: $0.model ?? "—", effort: $0.effort ?? "—", score: $0.iq, samples: $0.samples)
            },
            scoreCaption: "综合智能 IQ（radar-insights comprehensive_points）",
            isEmpty: (insights?.comprehensivePoints ?? []).isEmpty
        )
        let softwareRows = (insights?.comprehensivePoints ?? []).compactMap { point -> CapabilityRowView? in
            guard point.softwareIq != nil else { return nil }
            return CapabilityRowView(model: point.model ?? "—", effort: point.effort ?? "—", score: point.softwareIq, samples: point.samples)
        }
        let software = CapabilityTabView(
            title: "软件工程能力",
            systemImage: "laptopcomputer.and.arrow.down",
            rows: softwareRows,
            scoreCaption: "软件工程 IQ（radar-insights software_iq，独立呈现）",
            isEmpty: softwareRows.isEmpty
        )
        let visualRows = (vsr?.points ?? []).map { point in
            CapabilityRowView(
                model: point.model ?? "—",
                effort: point.effort ?? "—",
                score: point.iq,
                samples: point.validTasks.map(Int.init)
            )
        }
        let label = vsr?.scoreLabel ?? "Adjacency F1"
        let visual = CapabilityTabView(
            title: "视觉空间推理",
            systemImage: "square.stack.3d.up",
            rows: visualRows,
            scoreCaption: label + "（visual-spatial-reasoning 独立基准，不与综合智能 visual_iq 合并）",
            isEmpty: visualRows.isEmpty
        )
        return [comprehensive, software, visual]
    }

    /// Structured degradation alerts (verbatim upstream text).
    var structuredAlerts: [DegradationAlertView] {
        let alerts = radarInsightsDataset?.degradationAlerts?.items ?? []
        return alerts.enumerated().map { index, alert in
            DegradationAlertView(
                id: "\(alert.model ?? "model-\(index)")@\(alert.effort ?? "effort-\(index)")#\(index)",
                model: alert.model ?? "—",
                effort: alert.effort ?? "—",
                severity: alert.severity,
                message: alert.message,
                currentIq: alert.currentIq,
                baselineIq: alert.baselineIq
            )
        }
    }

    /// Station-owner recommendation scenes (verbatim upstream text).
    var structuredRecommendations: [StationRecommendationView] {
        (radarInsightsDataset?.recommendations ?? []).map { scene in
            StationRecommendationView(
                id: scene.key ?? scene.title ?? "scene",
                title: scene.title ?? scene.key ?? "推荐场景",
                rule: scene.rule,
                items: scene.items.map { item in
                    StationRecommendationView.RecommendationItemView(
                        id: "\(item.model ?? "—")@\(item.effort ?? "—")",
                        model: item.model ?? "—",
                        effort: item.effort ?? "—",
                        iq: item.iq,
                        averageCostUSD: item.averageCostUSD,
                        averageDurationMinutes: item.averageDurationMinutes,
                        combinedCostIndex: item.combinedCostIndex,
                        rule: item.rule
                    )
                }
            )
        }
    }
}
