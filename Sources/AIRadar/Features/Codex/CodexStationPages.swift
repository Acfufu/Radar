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
/// of the former intelligence center plus the upstream intelligence-efficiency
/// ranking (spec §5.2, P2②) with its own run-level columns.
struct CodexEfficiencyPKPage: View {
    @Environment(\.radarPalette) private var palette
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
                upstreamRankingCard
                Text(projection.source.attributionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .radarPage()
        }
    }

    /// Upstream distributed intelligence-efficiency ranking: displayed as
    /// published (upstream point order preserved, method text verbatim);
    /// Radar adds no local scoring on top.
    @ViewBuilder private var upstreamRankingCard: some View {
        if let dataset = projection.intelligenceEfficiencyDataset {
            VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
                ViewHeader(
                    title: "上游效能排行",
                    subtitle: dataset.sourceUpdatedAt ?? RadarFormat.date(dataset.fetchedAt)
                )
                summaryRow(dataset)
                rankingTable(dataset)
                if let method = dataset.method {
                    methodFootnotes(method)
                }
                Text(projection.source.attributionText)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .radarPanel()
        } else {
            Text("暂无上游效能排行数据；数据接入后在此显示（IntelligenceEfficiencyDataset）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ dataset: IntelligenceEfficiencyDataset) -> some View {
        HStack(spacing: RadarStyle.cardSpacing) {
            summaryItem("模型", RadarFormat.integer(dataset.models))
            summaryItem("24h 运行", RadarFormat.integer(dataset.runs24hTotal))
            summaryItem("48h 运行", RadarFormat.integer(dataset.runs48hTotal))
            summaryItem("累计运行", RadarFormat.integer(dataset.runsTotal))
        }
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(palette.secondaryText.color)
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }

    /// Run-level columns come from the upstream rows verbatim (spec §5.1
    /// human-readable dispositions); "—" marks fields the row omits.
    private func rankingTable(_ dataset: IntelligenceEfficiencyDataset) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            rankingHeaderRow
            ForEach(Array(dataset.points.enumerated()), id: \.offset) { _, point in
                rankingRow(point)
                Divider().overlay(palette.divider.color)
            }
        }
    }

    private var rankingHeaderRow: some View {
        HStack {
            Text("模型").frame(minWidth: 150, alignment: .leading)
            Text("IQ").frame(width: 56, alignment: .trailing)
            Text("通过/有效").frame(width: 80, alignment: .trailing)
            Text("均价").frame(width: 72, alignment: .trailing)
            Text("均时长").frame(width: 72, alignment: .trailing)
            Text("均 Tokens").frame(width: 88, alignment: .trailing)
            Text("缓存命中").frame(width: 72, alignment: .trailing)
            Text("24h").frame(width: 48, alignment: .trailing)
            Text("总运行").frame(width: 64, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(palette.secondaryText.color)
    }

    private func rankingRow(_ point: IntelligenceEfficiencyDataset.Point) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(point.model ?? "—").font(.caption.weight(.medium))
                Text([point.effort, point.harness].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
            .frame(minWidth: 150, alignment: .leading)
            Text(RadarFormat.decimal(point.iq.map { Decimal($0) })).frame(width: 56, alignment: .trailing).monospacedDigit()
            Text(ratio(point.passed, point.validTasks)).frame(width: 80, alignment: .trailing).monospacedDigit()
            Text(RadarFormat.decimal(point.averagePriceUSD, suffix: " $")).frame(width: 72, alignment: .trailing).monospacedDigit()
            Text(RadarFormat.decimal(point.averageMinutes.map { Decimal($0) }, suffix: " 分")).frame(width: 72, alignment: .trailing).monospacedDigit()
            Text(RadarFormat.decimal(point.averageTotalTokens.map { Decimal($0) })).frame(width: 88, alignment: .trailing).monospacedDigit()
            Text(percent(point.cacheHitRate)).frame(width: 72, alignment: .trailing).monospacedDigit()
            Text(RadarFormat.integer(point.runs24h)).frame(width: 48, alignment: .trailing).monospacedDigit()
            Text(RadarFormat.integer(point.runsTotal)).frame(width: 64, alignment: .trailing).monospacedDigit()
        }
        .font(.caption)
        .padding(.vertical, 6)
    }

    private func methodFootnotes(_ method: IntelligenceEfficiencyDataset.Method) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let iq = method.iq, !iq.isEmpty {
                Text("IQ 口径：\(iq)")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
                    .textSelection(.enabled)
            }
            if let price = method.price, !price.isEmpty {
                Text("价格口径：\(price)")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
                    .textSelection(.enabled)
            }
        }
    }

    private func ratio(_ passed: Double?, _ valid: Double?) -> String {
        guard let passed, let valid, valid > 0 else { return "—" }
        return String(format: "%.0f/%.0f", passed, valid)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value * 100)
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

/// Main axis row 5: Fast radar (spec §4.2 row 5, P2③ data). Current
/// comparison + run history + monthly count table; empty state without data.
struct CodexFastRadarPage: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RadarStyle.sectionSpacing) {
                ViewHeader(title: "Fast 雷达", subtitle: "standard 与 Fast 档位的 TTFT / TPS / E2E 实测对比")
                if let dataset = projection.fastRadarDataset, !dataset.runs.isEmpty {
                    currentComparisonCard(dataset)
                    monthlyCountCard(dataset)
                    historyCard(dataset)
                    Text(projection.source.attributionText)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .textSelection(.enabled)
                } else {
                    Text("暂无 Fast 雷达实测数据；数据接入后在此显示当前对比、历史与月份计数。")
                        .foregroundStyle(palette.secondaryText.color)
                }
            }
            .radarPage()
        }
    }

    /// Latest run with fast/standard pairs; ratios are Radar-derived
    /// (fast/standard) from upstream measurements, nothing else is computed.
    @ViewBuilder private func currentComparisonCard(_ dataset: FastRadarHistoryDataset) -> some View {
        let latest = dataset.runs.last
        VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
            ViewHeader(
                title: "当前对比",
                subtitle: latest.flatMap { $0.measuredAt ?? $0.runID } ?? dataset.updatedAt ?? "—"
            )
            let comparisons = latest.map { FastRadarAnalysis.evaluate(run: $0) } ?? []
            if comparisons.isEmpty {
                Text("最近一次运行缺少成对的 standard/Fast 实测。")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
            } else {
                comparisonHeaderRow
                ForEach(comparisons) { comparison in
                    comparisonRow(comparison, run: latest)
                    Divider().overlay(palette.divider.color)
                }
            }
            if let timezone = dataset.timezone {
                Text("时区：\(timezone)")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }

    private var comparisonHeaderRow: some View {
        HStack {
            Text("模型").frame(minWidth: 64, alignment: .leading)
            Text("TTFT (std → Fast)").frame(width: 150, alignment: .trailing)
            Text("倍率").frame(width: 64, alignment: .trailing)
            Text("TPS (std → Fast)").frame(width: 150, alignment: .trailing)
            Text("倍率").frame(width: 64, alignment: .trailing)
            Text("E2E (std → Fast)").frame(width: 150, alignment: .trailing)
            Text("倍率").frame(width: 64, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(palette.secondaryText.color)
    }

    private func comparisonRow(_ comparison: FastRadarTierComparison, run: FastRadarHistoryDataset.FastRadarRun?) -> some View {
        let tiers = run?.models
        let tier = switch comparison.model {
        case "sol": tiers?.sol
        case "terra": tiers?.terra
        default: tiers?.luna
        }
        return HStack {
            Text(comparison.model).frame(minWidth: 64, alignment: .leading)
            Text(pair(tier?.standard?.ttftSeconds, tier?.fast?.ttftSeconds, suffix: " s")).frame(width: 150, alignment: .trailing).monospacedDigit()
            Text(ratio(comparison.ttftRatio)).frame(width: 64, alignment: .trailing).monospacedDigit()
            Text(pair(tier?.standard?.tps, tier?.fast?.tps)).frame(width: 150, alignment: .trailing).monospacedDigit()
            Text(ratio(comparison.tpsRatio)).frame(width: 64, alignment: .trailing).monospacedDigit()
            Text(pair(tier?.standard?.e2eSeconds, tier?.fast?.e2eSeconds, suffix: " s")).frame(width: 150, alignment: .trailing).monospacedDigit()
            Text(ratio(comparison.e2eRatio)).frame(width: 64, alignment: .trailing).monospacedDigit()
        }
        .font(.caption)
        .padding(.vertical, 6)
    }

    private func monthlyCountCard(_ dataset: FastRadarHistoryDataset) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
            ViewHeader(title: "月份计数", subtitle: "runs 按 measured_at 所在月份分桶；升序、缺月补零")
            MonthlyCountTable(entries: FastRadarAnalysis.monthlyRunCounts(runs: dataset.runs))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }

    private func historyCard(_ dataset: FastRadarHistoryDataset) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
            ViewHeader(title: "运行历史", subtitle: "\(dataset.runs.count) 次实测；E2E 为 standard → Fast（秒）")
            HStack {
                Text("运行").frame(minWidth: 128, alignment: .leading)
                Text("measured_at").frame(width: 170, alignment: .leading)
                Text("CLI").frame(width: 76, alignment: .leading)
                Text("sol").frame(width: 130, alignment: .trailing)
                Text("terra").frame(width: 130, alignment: .trailing)
                Text("luna").frame(width: 130, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(palette.secondaryText.color)
            ForEach(Array(dataset.runs.reversed().enumerated()), id: \.offset) { _, run in
                historyRow(run)
                Divider().overlay(palette.divider.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }

    private func historyRow(_ run: FastRadarHistoryDataset.FastRadarRun) -> some View {
        func e2e(_ tier: FastRadarHistoryDataset.FastRadarRun.Tier?) -> String {
            guard let standard = tier?.standard?.e2eSeconds, let fast = tier?.fast?.e2eSeconds else { return "—" }
            return "\(RadarFormat.seconds(standard)) → \(RadarFormat.seconds(fast))"
        }
        return HStack {
            Text(run.runID ?? "—").frame(minWidth: 128, alignment: .leading)
            Text(run.measuredAt ?? "—").frame(width: 170, alignment: .leading)
            Text(run.cliVersion ?? "—").frame(width: 76, alignment: .leading)
            Text(e2e(run.models?.sol)).frame(width: 130, alignment: .trailing).monospacedDigit()
            Text(e2e(run.models?.terra)).frame(width: 130, alignment: .trailing).monospacedDigit()
            Text(e2e(run.models?.luna)).frame(width: 130, alignment: .trailing).monospacedDigit()
        }
        .font(.caption)
        .padding(.vertical, 5)
    }

    private func pair(_ standard: Double?, _ fast: Double?, suffix: String = "") -> String {
        guard let standard, let fast else { return "—" }
        return "\(value(standard, suffix: suffix)) → \(value(fast, suffix: suffix))"
    }

    private func value(_ number: Double, suffix: String) -> String {
        String(format: "%.2f%@", number, suffix)
    }

    private func ratio(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f×", value)
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
