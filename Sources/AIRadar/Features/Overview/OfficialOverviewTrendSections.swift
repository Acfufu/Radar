import Charts
import SwiftUI

/// Trend source toggle (spec §4.2 row 1, ADR-0002 successor): the official
/// side reads the ie.json `history[]` plane; `本地拟合` is unchanged.
enum OfficialIQChartSource: String, CaseIterable, Identifiable, Sendable {
    case officialTrend = "官网 IQ"
    case localFit = "本地拟合"

    var id: Self { self }
}

extension OfficialOverviewSections {
    /// Row 1 official IQ trend card, sourced from the public
    /// intelligence-efficiency `history[]` data plane (full observation
    /// window; breakpoint-tolerant series; never mixed with local fitting).
    @ViewBuilder var officialIQHistoryTrend: some View {
        if let presentation = projection.officialIQHistoryPresentation {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("IQ 趋势")
                            .font(.headline)
                        Spacer()
                        Picker("趋势来源", selection: $codexIQChartSource) {
                            Text(OfficialIQChartSource.officialTrend.rawValue).tag(OfficialIQChartSource.officialTrend)
                            Text(OfficialIQChartSource.localFit.rawValue).tag(OfficialIQChartSource.localFit)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityIdentifier("codex-official-iq-chart-source")

                        if codexIQChartSource == .officialTrend, !presentation.series.isEmpty {
                            Picker("官网模型", selection: seriesSelection) {
                                ForEach(presentation.series) { series in
                                    Text(series.displayName)
                                        .tag(series.seriesKey)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityIdentifier("codex-official-iq-series-picker")
                        }
                    }

                    switch codexIQChartSource {
                    case .officialTrend:
                        Label(presentation.stateMessage, systemImage: stateIcon(presentation.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(presentation.stateAccessibilityIdentifier)
                            .accessibilityLabel(presentation.stateAccessibilityLabel)

                        if let error = presentation.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(palette.negative.color)
                                .textSelection(.enabled)
                        }

                        if let series = selectedSeries(presentation) {
                            Text("\(series.displayName) · \(series.points.count) 个观察点 / 共 \(presentation.observationCount) 次观察")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("codex-official-iq-series-summary")

                            HStack(spacing: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    LabeledContent("当前 IQ") {
                                        Text(officialMetric(series.points.last?.iq))
                                            .font(.title2.weight(.semibold))
                                            .monospacedDigit()
                                    }
                                    LabeledContent("窗口均值") {
                                        let values = series.points.map(\.iq)
                                        Text(values.isEmpty ? "—" : officialMetric(values.reduce(0, +) / Double(values.count)))
                                            .monospacedDigit()
                                    }
                                    LabeledContent("观察点", value: "\(series.points.count)")
                                }
                                .frame(minWidth: 130, alignment: .leading)

                                Divider()

                                officialIQChart(series)
                            }
                        } else {
                            Text("暂无官网曲线（等待数据面同步）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let refreshedAt = presentation.lastSuccessfulAt {
                            Text("最近成功更新：\(refreshedAt.ISO8601Format())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Text(presentation.attribution + " · 官网曲线与本地拟合独立，互不校验")
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
        }
    }

    private func officialIQChart(_ series: OfficialIQHistoryPresentation.Series) -> some View {
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
        .chartXScale(domain: 0...max(1, series.points.last?.ordinal ?? 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
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
        _ series: OfficialIQHistoryPresentation.Series
    ) -> RadarChartDescriptor {
        RadarChartDescriptor(
            title: "Codex Radar 官网 · \(series.displayName) IQ 历史",
            summary: "\(projection.officialIQHistoryPresentation?.attribution ?? "Codex Radar 官网")；与 Radar 本地 IQ 拟合独立。",
            xAxisTitle: "官网观察顺序",
            yAxisTitle: "IQ",
            xValueDescription: { value in
                series.points.first { $0.ordinal == Int(value.rounded()) }?.sourceTimeLabel
                    ?? "第 \(Int(value.rounded()) + 1) 次观察"
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

    private func selectedSeries(_ presentation: OfficialIQHistoryPresentation) -> OfficialIQHistoryPresentation.Series? {
        if officialIQSelection.isEmpty {
            return presentation.selectedSeries
        }
        return presentation.series.first { $0.seriesKey == officialIQSelection } ?? presentation.selectedSeries
    }

    private var seriesSelection: Binding<String> {
        Binding(
            get: {
                if officialIQSelection.isEmpty {
                    return projection.officialIQHistoryPresentation?.selectedSeries?.seriesKey ?? ""
                }
                return officialIQSelection
            },
            set: { officialIQSelection = $0 }
        )
    }

    private func officialMetric(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    private func stateIcon(_ state: OfficialIQHistoryPresentation.State) -> String {
        switch state {
        case .loading: "arrow.triangle.2.circlepath"
        case .fresh: "checkmark.circle.fill"
        case .staleLastKnownGood: "clock.fill"
        case .lastKnownGoodWithError, .unavailableWithoutLastKnownGood: "exclamationmark.triangle.fill"
        }
    }
}
