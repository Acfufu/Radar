import Charts
import SwiftUI

extension OfficialOverviewSections {
    @ViewBuilder var officialIQHistoryTrend: some View {
        if let presentation = projection.renderedIQHistoryPresentation {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("24 小时 IQ 趋势")
                            .font(.headline)
                        Spacer()
                        Picker("趋势来源", selection: $codexIQChartSource) {
                            Text("官网 24h").tag(CodexRenderedIQHistoryChartSource.official24h)
                            Text("本地拟合").tag(CodexRenderedIQHistoryChartSource.localFit)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityIdentifier("codex-rendered-iq-history-chart-source")

                        if codexIQChartSource == .official24h {
                            Picker("官网模型", selection: $officialIQSelection) {
                                Text("综合").tag(CodexRenderedIQHistoryPresentation.Selection.aggregate)
                                ForEach(presentation.modelChoices) { series in
                                    Text(series.displayName)
                                        .tag(CodexRenderedIQHistoryPresentation.Selection.model(series.seriesKey))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityIdentifier("codex-rendered-iq-history-series-picker")
                        }
                    }

                    switch codexIQChartSource {
                    case .official24h:
                        Label(presentation.stateMessage, systemImage: iqHistoryStateIcon(presentation.state))
                            .font(.caption)
                            .foregroundStyle(iqHistoryStateColor(presentation.state))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(presentation.stateAccessibilityIdentifier)
                            .accessibilityLabel(presentation.stateAccessibilityLabel)

                        if let error = presentation.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(palette.negative.color)
                                .textSelection(.enabled)
                        }

                        Text(selectedOfficialIQSeries.map { "\($0.displayName) · \($0.points.count) 个点" } ?? "暂无官网曲线")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier(officialSeriesAccessibilityIdentifier)
                            .accessibilityLabel(officialSeriesAccessibilitySummary)

                        if let series = selectedOfficialIQSeries {
                            HStack(spacing: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    LabeledContent("当前 IQ") {
                                        Text(officialMetric(series.points.last?.iq ?? 0))
                                            .font(.title2.weight(.semibold))
                                            .monospacedDigit()
                                    }
                                    LabeledContent("24h 均值") {
                                        Text(officialMetric(series.points.map(\.iq).reduce(0, +) / Double(series.points.count)))
                                            .monospacedDigit()
                                    }
                                    LabeledContent("样本点", value: "\(series.points.count)")
                                }
                                .frame(minWidth: 130, alignment: .leading)

                                Divider()

                                officialIQChart(series)
                            }
                        }

                        HStack(spacing: 14) {
                            if let refreshedAt = presentation.lastSuccessfulAt {
                                Text("最近成功更新：\(refreshedAt.ISO8601Format())")
                            }
                            if let capturedAt = presentation.capturedAt {
                                Text("首次观察：\(capturedAt.ISO8601Format())")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                        Link(presentation.attribution, destination: URL(string: presentation.backlink)!)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("codex-rendered-iq-history-source")
                        Text("与本地 IQ 拟合独立")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .localFit:
                        LocalIQTrendChart(projection: projection, history: history)
                    }
                }
                .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(presentation.sectionAccessibilityIdentifier)
            .accessibilityLabel(officialSeriesAccessibilitySummary)
        }
    }

    private func officialIQChart(_ series: CodexRenderedIQHistoryPresentation.Series) -> some View {
        Chart {
            ForEach(series.points) { point in
                LineMark(
                    x: .value("顺序", point.ordinal),
                    y: .value("IQ", point.iq)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(.green)
                PointMark(
                    x: .value("顺序", point.ordinal),
                    y: .value("IQ", point.iq)
                )
                .foregroundStyle(.green)
            }
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let ordinal = value.as(Int.self),
                       let point = series.points.first(where: { $0.ordinal == ordinal }) {
                        Text(point.sourceTimeLabel)
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(minHeight: 180)
        .accessibilityChartDescriptor(officialDescriptor(series))
    }

    private func officialDescriptor(
        _ series: CodexRenderedIQHistoryPresentation.Series
    ) -> RadarChartDescriptor {
        RadarChartDescriptor(
            title: "Codex Radar 官网 · \(series.displayName) 24 小时 IQ",
            summary: "\(projection.renderedIQHistoryPresentation?.attribution ?? "Codex Radar 官网")；与 Radar 本地 IQ 拟合独立。",
            xAxisTitle: "官网时间顺序",
            yAxisTitle: "IQ",
            xValueDescription: { value in
                series.points.first { $0.ordinal == Int(value.rounded()) }?.sourceTimeLabel
                    ?? "第 \(Int(value.rounded()) + 1) 个点"
            },
            yValueDescription: { RadarChartDescriptor.number($0, unit: "IQ") },
            series: [
                .init(
                    name: series.displayName,
                    isContinuous: true,
                    points: series.points.map { point in
                        .init(
                            x: Double(point.ordinal),
                            y: point.iq,
                            label: "Codex Radar 官网，\(series.displayName)，\(point.sourceTimeLabel)，IQ \(officialMetric(point.iq))"
                        )
                    }
                ),
            ]
        )
    }

    private var selectedOfficialIQSeries: CodexRenderedIQHistoryPresentation.Series? {
        guard let presentation = projection.renderedIQHistoryPresentation else { return nil }
        switch officialIQSelection {
        case .aggregate:
            return presentation.series.first { $0.seriesKey == "aggregate" }
        case .model(let seriesKey):
            return presentation.modelChoices.first { $0.seriesKey == seriesKey }
                ?? presentation.series.first { $0.seriesKey == "aggregate" }
        }
    }

    private var officialSeriesAccessibilitySummary: String {
        guard let presentation = projection.renderedIQHistoryPresentation else { return "" }
        guard let series = selectedOfficialIQSeries else {
            return "\(presentation.stateAccessibilityLabel)，\(presentation.attribution)"
        }
        let labels = series.points.map(\.sourceTimeLabel).joined(separator: "、")
        return "\(presentation.stateAccessibilityLabel)，\(series.displayName)，\(series.points.count) 个点，\(labels)，\(presentation.attribution)"
    }

    private var officialSeriesAccessibilityIdentifier: String {
        "codex-rendered-iq-history-series-\(selectedOfficialIQSeries?.seriesKey ?? "none")"
    }

    private func iqHistoryStateIcon(_ state: CodexRenderedIQHistoryPresentation.State) -> String {
        switch state {
        case .loading: "arrow.triangle.2.circlepath"
        case .fresh: "checkmark.circle.fill"
        case .staleLastKnownGood: "clock.fill"
        case .lastKnownGoodWithError, .schemaDriftWithoutLastKnownGood,
             .challengeWithoutLastKnownGood, .unavailableWithoutLastKnownGood: "exclamationmark.triangle.fill"
        }
    }

    private func iqHistoryStateColor(_ state: CodexRenderedIQHistoryPresentation.State) -> Color {
        switch state {
        case .fresh: .green
        case .loading: palette.secondaryText.color
        case .staleLastKnownGood: .orange
        case .lastKnownGoodWithError, .schemaDriftWithoutLastKnownGood,
             .challengeWithoutLastKnownGood, .unavailableWithoutLastKnownGood: palette.negative.color
        }
    }
}
