import SwiftUI

struct CodexHistoryComparisonPanel: View {
    @Environment(\.radarPalette) private var palette

    let current: BenchmarkDataset?
    let history: [BenchmarkDataset]
    let provenance: String

    @State private var metric: CodexHistoryMetric = .default
    @State private var baseline: CodexHistoryBaseline = .default
    @State private var selection = CodexHistorySelectionState()

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            Text("历史数据比较")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("最多选择 4 个模型；缺失当前值、基线或同版本快照时显示不可用。")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)

            HStack {
                Picker("指标", selection: $metric) {
                    ForEach(CodexHistoryMetric.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .accessibilityIdentifier("codex-history-metric")
                .frame(maxWidth: layout.comparisonMetricPickerMaximumWidth)

                Picker("基线", selection: $baseline) {
                    ForEach(CodexHistoryBaseline.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .accessibilityIdentifier("codex-history-baseline")
                .frame(width: layout.comparisonBaselinePickerWidth)
                Spacer()
            }

            if let current {
                modelChoices(current)
                comparisonRows(current)
            } else {
                unavailable
            }

            Divider().overlay(palette.divider.color)
            Text("仅比较 Codex Radar 的同 sourceID 与 seriesRevision 本地快照 · \(current?.seriesRevision ?? "不可用")")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
            Text(provenance)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
        }
        .onChange(of: refreshIdentity, initial: true) { _, _ in
            guard let current else {
                selection = .init(selected: [], isExplicit: selection.isExplicit)
                return
            }
            selection = CodexHistorySelection.reconcile(state: selection, current: current)
        }
        .accessibilityIdentifier("codex-history-comparison")
        .radarPanel()
    }

    private func modelChoices(_ dataset: BenchmarkDataset) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing / 2) {
            let affordance = RadarStyle.horizontalScrollAffordance
            Label(affordance.title, systemImage: affordance.systemImage)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .accessibilityIdentifier("codex-history-horizontal-affordance")

            ScrollView(.horizontal) {
                HStack {
                    ForEach(allRows(dataset)) { row in
                        let canSelect = CodexHistorySelection.canSelect(
                            row.modelID,
                            state: selection,
                            current: dataset
                        )
                        Toggle(
                            row.modelName,
                            isOn: Binding(
                                get: { selection.selected.contains(row.modelID) },
                                set: { selected in
                                    selection = CodexHistorySelection.setting(
                                        row.modelID,
                                        selected: selected,
                                        state: selection,
                                        current: dataset
                                    )
                                }
                            )
                        )
                        .toggleStyle(.button)
                        .disabled(!canSelect)
                        .help(canSelect ? "选择 \(row.modelName)" : "已达 4 个模型上限")
                        .accessibilityHint(canSelect ? "" : "已达 4 个模型上限，请先取消一个已选模型")
                        .accessibilityIdentifier("codex-history-model-\(row.modelID.upstreamKey)")
                    }
                }
            }
            .scrollIndicators(.visible, axes: .horizontal)
            Text(selection.selected.count >= CodexHistorySelection.limit ? "已达 4 个模型上限；其他模型暂不可选。" : "已选择 \(selection.selected.count) / \(CodexHistorySelection.limit)")
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
                .accessibilityIdentifier("codex-history-selection-hint")
        }
    }

    @ViewBuilder
    private func comparisonRows(_ dataset: BenchmarkDataset) -> some View {
        let selectedRows = rows(dataset).filter { selection.selected.contains($0.modelID) }
        if selectedRows.isEmpty {
            ContentUnavailableView(
                "未选择模型",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("选择最多 4 个模型进行历史比较。")
            )
            .frame(minHeight: 170)
        } else {
            VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                HStack(spacing: layout.comparisonColumnSpacing) {
                    header("模型").frame(maxWidth: .infinity, alignment: .leading)
                    header("当前").frame(maxWidth: .infinity, alignment: .leading)
                    header(baseline.title + " 前").frame(maxWidth: .infinity, alignment: .leading)
                    header("变化").frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                ForEach(selectedRows) { row in
                    let accessibleRow = CodexHistoryComparisonAccessibility.row(
                        row,
                        metric: metric,
                        baseline: baseline
                    )
                    HStack(spacing: layout.comparisonColumnSpacing) {
                        Text(row.modelName)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(format(row.current))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(format(row.baseline))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(formatDelta(row.delta))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibleRow.label)
                    .accessibilityIdentifier(
                        "codex-history-row-\(accessibleRow.modelID.upstreamKey)"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "历史比较不可用",
            systemImage: "clock.badge.exclamationmark",
            description: Text("当前 Codex Radar 数据不可用；不会以 0 代替。")
        )
        .frame(minHeight: 200)
    }

    private func allRows(_ dataset: BenchmarkDataset) -> [CodexHistoryComparisonRow] {
        CodexHistoryComparison.project(
            current: dataset,
            history: history,
            metric: metric,
            baseline: baseline
        )
    }

    private func rows(_ dataset: BenchmarkDataset) -> [CodexHistoryComparisonRow] {
        allRows(dataset)
    }

    private var refreshIdentity: String {
        guard let current else { return "unavailable" }
        return ([current.seriesRevision] + current.models.map(\.id.upstreamKey).sorted()).joined(separator: "|")
    }

    private var layout: RadarAnalyticsLayoutMetrics {
        RadarStyle.analyticsLayout
    }

    private func header(_ value: String) -> some View {
        Text(value)
            .font(.caption.bold())
            .foregroundStyle(palette.secondaryText.color)
    }

    private func format(_ value: Double?) -> String {
        CodexHistoryComparisonAccessibility.format(value, metric: metric)
    }

    private func formatDelta(_ value: Double?) -> String {
        CodexHistoryComparisonAccessibility.formatDelta(value, metric: metric)
    }
}

struct CodexHistoryComparisonAccessibilityRow: Identifiable, Equatable, Sendable {
    let modelID: ModelID
    let label: String

    var id: ModelID { modelID }
}

enum CodexHistoryComparisonAccessibility {
    static func rows(
        _ rows: [CodexHistoryComparisonRow],
        metric: CodexHistoryMetric,
        baseline: CodexHistoryBaseline
    ) -> [CodexHistoryComparisonAccessibilityRow] {
        rows.map { row($0, metric: metric, baseline: baseline) }
    }

    static func row(
        _ row: CodexHistoryComparisonRow,
        metric: CodexHistoryMetric,
        baseline: CodexHistoryBaseline
    ) -> CodexHistoryComparisonAccessibilityRow {
        .init(
            modelID: row.modelID,
            label: "模型 \(row.modelName)，\(metric.title) 当前 \(format(row.current, metric: metric))，\(baseline.title) 前 \(format(row.baseline, metric: metric))，变化 \(formatDelta(row.delta, metric: metric))"
        )
    }

    static func format(_ value: Double?, metric: CodexHistoryMetric) -> String {
        guard let value, value.isFinite else { return "不可用" }
        switch metric {
        case .iq, .averageMinutesPerValidTask:
            return value.formatted(.number.precision(.fractionLength(1)))
        case .averageFeePerValidTask:
            return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        case .agentSteps, .totalTokens:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .cacheHitPercent:
            return value.formatted(.number.precision(.fractionLength(1))) + "%"
        }
    }

    static func formatDelta(_ value: Double?, metric: CodexHistoryMetric) -> String {
        guard let value, value.isFinite else { return "不可用" }
        let formatted = format(abs(value), metric: metric)
        if value > 0 { return "+" + formatted }
        if value < 0 { return "−" + formatted }
        return formatted
    }
}
