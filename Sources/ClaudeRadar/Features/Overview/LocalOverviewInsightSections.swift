import Charts
import SwiftUI

extension OverviewLocalSections {
    var localInsights: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 360), alignment: .top)],
            spacing: RadarStyle.compactSpacing
        ) {
            radarOverviewSection("本地 IQ 拟合") {
                VStack(alignment: .leading, spacing: 10) {
                    if projection.benchmarkState != .fresh {
                        Text("仅在来源数据为最新状态时计算，当前状态不生成信号。")
                            .foregroundStyle(.secondary)
                    } else if declineSignals.isEmpty {
                        Text("当前本地快照未触发信号；同步点不足时不会推断或插值。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(declineSignals) { signal in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(signal.modelName).fontWeight(.medium)
                                    Spacer()
                                    Text("当前 IQ \(RadarFormat.decimal(signal.currentIQ))")
                                        .monospacedDigit()
                                }
                                HStack(spacing: 12) {
                                    Text("24h ↓\(RadarFormat.decimal(signal.drop24Hours))")
                                        .foregroundStyle(palette.negative.color)
                                    Text("12h ↓\(RadarFormat.decimal(signal.drop12Hours))")
                                    Text(signal.drop48Hours.map { "48h \($0 >= 0 ? "↓" : "↑")\(RadarFormat.decimal(abs($0)))" } ?? "48h —")
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text("Radar 本地规则：同一来源、模型与 revision；24h 下降至少 2 IQ 且 12h 仍下降。按 24h 降幅排序，最多 4 条；非来源官方预警。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("local-iq-fit-section")

            radarOverviewSection("本地效率估算") {
                VStack(alignment: .leading, spacing: 8) {
                    if efficiencyPoints.isEmpty {
                        Text("缺少 IQ、费用或耗时，暂无法估算。")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                                GridRow {
                                    Text("模型")
                                    Text("IQ")
                                    Text("平均费用/每有效题")
                                    Text("平均耗时/每有效题")
                                    Text("成本指数")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                ForEach(efficiencyPoints.prefix(6)) { point in
                                    GridRow {
                                        Text(point.modelName).lineLimit(1)
                                        Text(point.quality.formatted(.number.precision(.fractionLength(1))))
                                        Text(point.averageCostUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                                        Text("\(point.averageMinutes.formatted(.number.precision(.fractionLength(1)))) 分钟")
                                        Text(point.combinedCostIndex.formatted(.number.precision(.fractionLength(2))))
                                    }
                                    .monospacedDigit()
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    Text("按每有效题平均费用与平均分钟计算；仅在当前来源数据集内归一。Radar 本地估算，非来源官方指标。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(projection.source.attributionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var signalHero: some View {
        GroupBox {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前峰值 · IQ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(RadarFormat.decimal(peak?.benchmark.qualityScore))
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Circle()
                            .fill(RadarVisuals.qualityColor(peak?.benchmark.qualityScore))
                            .frame(width: 10, height: 10)
                    }
                    Text(peak?.name ?? "数据不足")
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(RadarFormat.integer(peak?.benchmark.passedTasks)) / \(RadarFormat.integer(peak?.benchmark.validTasks)) 通过")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 180, alignment: .leading)
                .radarMetricCard()

                Divider()

                LocalIQTrendChart(projection: projection, history: history)
            }
            .padding(.top, 4)
        }
    }

    var familyHealth: some View {
        radarOverviewSection("模型家族健康") {
            VStack(spacing: 0) {
                ForEach(familySummaries) { summary in
                    HStack(spacing: 10) {
                        Image(systemName: RadarVisuals.familyIcon(summary.family))
                            .foregroundStyle(RadarVisuals.familyColor(summary.family))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.family).fontWeight(.medium)
                            Text(RadarModelIdentity.effort(for: summary.row) ?? "当前最佳档位")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(RadarFormat.decimal(summary.row.benchmark.qualityScore))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(RadarVisuals.qualityColor(summary.row.benchmark.qualityScore))
                    }
                    .padding(.vertical, 8)
                    if summary.id != familySummaries.last?.id { Divider() }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    var tierHeatmap: some View {
        radarOverviewSection("推理层级表现热力图 · IQ") {
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    Text("模型").foregroundStyle(.secondary)
                    ForEach(RadarModelIdentity.efforts, id: \.self) { tier in
                        Text(tier).foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)

                ForEach(heatmapFamilies, id: \.self) { family in
                    GridRow {
                        Text(family)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(RadarModelIdentity.efforts, id: \.self) { tier in
                            heatCell(row: heatmapRow(family: family, tier: tier))
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    var quotaContext: some View {
        radarOverviewSection("配额与成本上下文") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("订阅方案", selection: $subscription) {
                    Text("Plus").tag("Plus")
                    Text("5x Pro").tag("5x Pro")
                    Text("20x Pro").tag("20x Pro")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider()
                LabeledContent("公开额度估算") {
                    Text(quotaValue)
                        .monospacedDigit()
                }
                Text(selectedQuota?.resetDescription ?? "该订阅方案暂无公开额度估算")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    var monitoringAndRecentPerformance: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 360), alignment: .top)],
            spacing: RadarStyle.compactSpacing
        ) {
            radarOverviewSection("近期表现") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("模型")
                        Text("IQ")
                        Text("较上次")
                        Text("每题成本")
                        Text("平均耗时")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider().gridCellColumns(5)

                    ForEach(recentPerformance) { row in
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.family).fontWeight(.medium)
                                Text(row.tier ?? row.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(RadarFormat.decimal(row.quality))
                                .monospacedDigit()
                            Text(row.delta.map(RadarVisuals.signed) ?? "—")
                                .monospacedDigit()
                                .foregroundStyle(row.delta.map { $0 >= 0 ? Color.green : Color.orange } ?? .secondary)
                            Text(row.costPerTask.map { "$\(RadarFormat.decimal($0))" } ?? "—")
                                .monospacedDigit()
                            Text(RadarVisuals.duration(row.secondsPerTask))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 7)
                        if row.id != recentPerformance.last?.id {
                            Divider().gridCellColumns(5)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                radarOverviewSection("实时监控") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(overviewSourceHealth(projection.benchmarkState), systemImage: overviewSourceHealthIcon(projection.benchmarkState))
                            .foregroundStyle(projection.benchmarkState == .fresh ? .green : .orange)
                        LabeledContent("最近同步", value: monitoringAge(at: context.date))
                        LabeledContent("自动刷新", value: "每 \(refreshIntervalMinutes) 分钟")
                        LabeledContent("历史快照", value: "\(sourceHistory.count)")
                        ProgressView(value: monitoringProgress(at: context.date))
                            .tint(.green)
                        Text(nextMonitoringText(at: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
