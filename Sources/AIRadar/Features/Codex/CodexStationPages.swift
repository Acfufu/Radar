import SwiftUI

// Codex station page set (spec §4.2): the former intelligence center is
// dissolved — its five panels move to the efficiency-PK and history
// comparison pages — and the main-axis pages land in upstream order.
// Data surfaces that arrive with P2 render explicit nil-data empty states
// here (spec §4.2 empty-state policy).

/// Main axis row 1: speed overview. Fuses the original Codex overview with
/// the model-tier list; the official 24h IQ trend card (incl. the deng
/// rendered reader's display home) stays inside the overview sections.
struct CodexSpeedOverviewPage: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    let refreshIntervalMinutes: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                // Spec §4.2: announcement banner renders only when the
                // upstream window snapshot exists.
                AnnouncementBanner(content: bannerContent)
                OverviewView(
                    projection: projection,
                    history: history,
                    refreshIntervalMinutes: refreshIntervalMinutes
                )
                modelListCard
            }
            .radarPage()
        }
    }

    private var bannerContent: AnnouncementBanner.Content? {
        guard let window = projection.stationStatus?.window else { return nil }
        return .init(
            title: window.title ?? "Codex 用量限制重置",
            message: window.message,
            isOpen: window.isOpen ?? false,
            statusWord: projection.stationStatus?.recommendedAction
        )
    }

    private var modelListCard: some View {
        VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
            ViewHeader(title: "模型档位详情", subtitle: "来源内模型配置与本地指标")
            ModelListView(projection: projection, history: history)
        }
    }
}

/// Main axis row 2: degradation alerts (upgraded accent cards), the station
/// recommendation upstream link card (spec D4), and the prediction card
/// (hidden until P2① supplies prediction data).
struct AlertsRecommendationsPage: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(title: "预警与推荐", subtitle: "官网预警、站长推荐与重置预测；口径独立并标注来源")
                degradationCard
                recommendationLinkCard
                predictionCard
            }
            .radarPage()
        }
    }

    private var degradationCard: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Label("降智预警", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(palette.amber.color)
            if let cards = projection.renderedWarningPresentation?.cards, !cards.isEmpty {
                ForEach(cards, id: \.sourceOrder) { card in
                    HStack {
                        Text("\(card.displayName) · \(card.effort)")
                        Spacer()
                        Text("IQ \(card.iq, format: .number.precision(.fractionLength(0...1)))")
                            .monospacedDigit()
                        if card.drop24h != 0 {
                            Text("24h \(card.drop24h, format: .number.precision(.fractionLength(0...1)))")
                                .foregroundStyle(palette.red.color)
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                }
            } else {
                Text("暂无官网预警数据")
                    .foregroundStyle(palette.secondaryText.color)
            }
            Text(projection.source.attributionText)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarAccentCard(accent: palette.amber, soft: palette.amberSoft)
    }

    private var recommendationLinkCard: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Label("站长推荐", systemImage: "hand.thumbsup")
                .font(.headline)
                .foregroundStyle(palette.green.color)
            Text("上游编辑推荐内容在 codexradar.com 发布；Radar 不转载正文、不做本地派生推荐。")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText.color)
            Link("前往 codexradar.com 查看站长推荐", destination: URL(string: "https://codexradar.com/")!)
                .font(.subheadline.weight(.medium))
            Text(projection.source.attributionText)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarAccentCard(accent: palette.green, soft: palette.greenSoft)
    }

    /// Prediction card (spec §5.1 `prediction`): hidden while the fields
    /// are absent; summaries are upstream text verbatim.
    @ViewBuilder private var predictionCard: some View {
        if let prediction = projection.stationStatus?.prediction, prediction.level != nil || prediction.probability24h != nil {
            VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                Label("重置预测", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(palette.blue.color)
                if let level = prediction.level {
                    Text("等级：\(level)").font(.subheadline)
                }
                if let p24 = prediction.probability24h, let p48 = prediction.probability48h {
                    Text("24h \(Int((p24 * 100).rounded()))% · 48h \(Int((p48 * 100).rounded()))%")
                        .font(.subheadline)
                        .monospacedDigit()
                }
                if let summary = prediction.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .textSelection(.enabled)
                }
                Text(projection.source.attributionText)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .radarAccentCard(accent: palette.blue, soft: palette.blueSoft)
        }
    }
}

/// Main axis row 3: efficiency PK. Hosts the three analysis panels moved out
/// of the former intelligence center; the upstream intelligence-efficiency
/// dataset (P2②) feeds the ranking section below once available.
struct CodexEfficiencyPKPage: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(
                    title: "效能 PK",
                    subtitle: "\(projection.source.displayName) · 同基准横比与成本效率；面板口径独立"
                )
                if let supportState = projection.benchmarkPresentation.supportState {
                    StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
                }
                CodexCostVersusIQPanel(
                    points: projection.intelligenceEfficiency,
                    sourceUpdatedAt: projection.updatedAt,
                    seriesRevision: projection.sync?.benchmark.value?.seriesRevision,
                    provenance: "Radar 按 Codex Radar 公开摘要计算；不跨来源或版本比较"
                )
                CodexEfficiencyMatrixPanel(
                    cells: CodexEfficiencyAnalytics.matrix(points: projection.intelligenceEfficiency),
                    sourceUpdatedAt: projection.updatedAt,
                    provenance: "Radar 按 Codex Radar 公开摘要计算"
                )
                CodexScenarioRecommendationsPanel(
                    recommendations: CodexScenarioRecommendations.project(points: projection.intelligenceEfficiency)
                )
                Text("上游效能排行数据接入后在此显示（IntelligenceEfficiencyDataset，P2②）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(projection.source.attributionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .radarPage()
        }
    }
}

/// Main axis row 4: quota radar. Surfaces the source-status quota estimates
/// that previously lived inside the overview; trend/check/calibration detail
/// arrives with P2① and renders empty states until then.
struct CodexQuotaRadarPage: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(title: "额度雷达", subtitle: "来源账户额度估算；非个人用量（source-account estimate）")
                if let estimates = projection.sync?.sourceStatus.value?.quotaEstimates, !estimates.isEmpty {
                    ForEach(estimates, id: \.windowLabel) { quota in
                        HStack {
                            Text(quota.windowLabel)
                            Spacer()
                            if let usedPercent = quota.usedPercent {
                                Text(RadarFormat.decimal(usedPercent, suffix: "%")).monospacedDigit()
                            } else if let value = quota.estimatedValueUSD {
                                Text("$\(RadarFormat.decimal(value))").monospacedDigit()
                            } else {
                                Text(quota.windowLabel).foregroundStyle(palette.secondaryText.color)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("暂无额度估算数据")
                        .foregroundStyle(palette.secondaryText.color)
                }
                Text("额度 10 天趋势、当前核查与校准信息接入后在此显示（P2①）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .radarPage()
        }
    }
}

/// Main axis row 5: Fast radar (P2③ data). Empty state until then.
struct CodexFastRadarPage: View {
    @Environment(\.radarPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
            ViewHeader(title: "Fast 雷达", subtitle: "standard 与 Fast 档位的 TTFT / TPS / E2E 实测对比")
            Text("暂无 Fast 雷达实测数据；数据接入后在此显示当前对比、历史与月份计数。")
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .radarPage()
    }
}

/// Main axis row 6: history comparison. Hosts the two panels moved out of
/// the former intelligence center (local-fitting small multiples only; the
/// official 24h curve lives on the speed overview page, spec §4.2 row 1).
struct CodexHistoryComparisonPage: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(title: "历史对比", subtitle: "本地快照历史与 IQ 小倍数视图")
                CodexHistoryComparisonPanel(
                    current: projection.sync?.benchmark.value,
                    history: history,
                    provenance: "C4-C5 使用 Codex Radar 的 Radar 本地持久化历史；不跨来源或版本比较"
                )
                CodexIQHistorySmallMultiplesPanel(
                    history: history,
                    provenance: "C4-C5 使用 Codex Radar 的 Radar 本地持久化历史；不跨来源或版本比较"
                )
                Text(projection.source.attributionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .radarPage()
        }
    }
}

/// Main axis row 7: Tibo radar. Data comes only from current.json
/// `tibo_presence` (P2①, spec D13); empty state until then.
struct CodexTiboRadarPage: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(title: "Tibo 雷达", subtitle: "基于上游对公开帖的时区级观测；Radar 原文转存，不做本地推断")
                if let presence = projection.stationStatus?.tiboPresence, presence.shouldDisplay == true {
                    presenceCard(presence)
                } else {
                    Text("暂无 Tibo 观测数据。")
                        .foregroundStyle(palette.secondaryText.color)
                }
            }
            .radarPage()
        }
    }

    /// D13: verbatim upstream observation fields; safety note and
    /// should_display gate travel with the card.
    private func presenceCard(_ presence: CodexStationStatusDataset.TiboPresence) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Label("时区级存在观测", systemImage: "globe")
                .font(.headline)
            if let location = presence.locationLabelZH ?? presence.locationLabelEN {
                Text(location).font(.subheadline)
            }
            if let probability = presence.probability {
                Text("概率 \(Int((probability * 100).rounded()))%").font(.caption).monospacedDigit()
            }
            if let summary = presence.evidenceSummaryZH ?? presence.evidenceSummaryEN {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .textSelection(.enabled)
            }
            if let safety = presence.safetyNoteZH ?? presence.safetyNoteEN {
                Text(safety)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarAccentCard(accent: palette.blue, soft: palette.blueSoft)
    }
}

/// Main axis row 9: community hub — link cards only (spec D6/D7, §12).
struct CodexCommunityHubPage: View {
    @Environment(\.radarPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(title: "社区入口", subtitle: "上游社区与体感打分入口；Radar 只读不提交")
                Link("前往 codexradar.com 社区", destination: URL(string: "https://codexradar.com/")!)
                    .font(.subheadline.weight(.medium))
                Link("去上游给模型体感打分", destination: URL(string: "https://codexradar.com/")!)
                    .font(.subheadline.weight(.medium))
                communityKnowledgeCard
            }
            .radarPage()
        }
    }

    /// Spec §12: knowledge list card — title + upstream-provided summary +
    /// external link; without an upstream summary only the title and link.
    private var communityKnowledgeCard: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Label("社区知识", systemImage: "book")
                .font(.headline)
            Text("暂无知识文章条目；上游文章卡接入后按「标题 + 摘要 + 外链」显示。")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }
}
