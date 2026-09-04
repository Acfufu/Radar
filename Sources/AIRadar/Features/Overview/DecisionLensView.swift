import Charts
import SwiftUI

struct DecisionLensPageView: View {
    let projection: WorkspaceProjection
    @State private var goal = RadarDecisionGoal.quality

    var body: some View {
        ScrollView {
            Group {
                if projection.rows.isEmpty {
                    ContentUnavailableView(
                        "暂无 Benchmark 数据",
                        systemImage: "scope",
                        description: Text("刷新后仍无数据时，请查看来源状态。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    DecisionLensView(
                        rows: projection.rows,
                        familyRows: RadarModelIdentity.familySummaries(projection.rows).map(\.row),
                        sourceName: projection.source.displayName,
                        goal: $goal
                    )
                }
            }
            .radarPage()
            .groupBoxStyle(RadarGroupBoxStyle())
        }
    }
}

private struct DecisionLensView: View {
    let rows: [WorkspaceModelRow]
    let familyRows: [WorkspaceModelRow]
    let sourceName: String
    @Binding var goal: RadarDecisionGoal

    private var recommendation: WorkspaceModelRow? {
        RadarDecisionLens.recommendation(in: rows, for: goal)
    }

    var body: some View {
        GroupBox("决策透镜 · 选择目标，获得推荐") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230), alignment: .top)],
                spacing: RadarStyle.cardSpacing
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("选择你的目标")
                        .font(.headline)
                    ForEach(RadarDecisionGoal.allCases) { candidate in
                        Button {
                            goal = candidate
                        } label: {
                            HStack {
                                Image(systemName: candidate.icon).frame(width: 18)
                                Text(candidate.rawValue)
                                Spacer()
                                if goal == candidate {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(8)
                            .background(
                                goal == candidate ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: .rect(cornerRadius: RadarStyle.cornerRadius)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: RadarStyle.cornerRadius)
                                    .stroke(
                                        goal == candidate
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.25)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("决策目标：\(candidate.rawValue)")
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("模型对比图")
                        .font(.headline)
                    Text("IQ ↑ · 每题平均耗时 →")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(familyRows) { row in
                        PointMark(
                            x: .value("每题平均耗时", RadarVisuals.secondsPerTask(row) ?? 0),
                            y: .value("IQ", RadarVisuals.double(row.benchmark.qualityScore ?? 0))
                        )
                        .symbolSize(row.id == recommendation?.id ? 180 : 95)
                        .foregroundStyle(RadarVisuals.familyColor(RadarModelIdentity.family(for: row)))
                        .symbol(by: .value("系列", RadarModelIdentity.family(for: row)))
                        .annotation(position: .top) {
                            Text(RadarModelIdentity.family(for: row))
                                .font(.caption2.weight(.medium))
                        }
                    }
                    .accessibilityChartDescriptor(decisionDescriptor)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(minHeight: 220)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("推荐结果")
                        .font(.headline)
                    if let recommendation {
                        Label("推荐模型", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(RadarModelIdentity.family(for: recommendation))
                            .font(.title.bold())
                        Text(RadarModelIdentity.effort(for: recommendation) ?? recommendation.name)
                            .foregroundStyle(.secondary)
                        Divider()
                        LabeledContent("综合 IQ", value: RadarFormat.decimal(recommendation.benchmark.qualityScore))
                        LabeledContent(
                            "测试通过 / 有效",
                            value: "\(RadarFormat.integer(recommendation.benchmark.passedTasks)) / \(RadarFormat.integer(recommendation.benchmark.validTasks))"
                        )
                        LabeledContent(
                            "每题成本",
                            value: RadarVisuals.costPerTask(recommendation).map { "$\(RadarFormat.decimal($0))" } ?? "—"
                        )
                        LabeledContent(
                            "平均耗时",
                            value: RadarVisuals.duration(RadarVisuals.secondsPerTask(recommendation))
                        )
                    } else {
                        ContentUnavailableView(
                            "数据不足",
                            systemImage: "questionmark.circle",
                            description: Text("当前指标不足以生成推荐。")
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 6)
        }
    }

    private var decisionDescriptor: RadarChartDescriptor {
        RadarChartDescriptor(
            title: "\(sourceName) · 决策透镜模型对比",
            summary: "目标为\(goal.rawValue)；推荐结果也以文字与勾选符号显示。",
            xAxisTitle: "每题平均耗时（秒）",
            yAxisTitle: "IQ",
            xValueDescription: { RadarChartDescriptor.number($0, unit: "秒") },
            yValueDescription: { RadarChartDescriptor.number($0, unit: "IQ") },
            series: familyRows.map { row in
                let family = RadarModelIdentity.family(for: row)
                return .init(
                    name: family,
                    isContinuous: false,
                    points: [.init(
                        x: RadarVisuals.secondsPerTask(row) ?? 0,
                        y: RadarVisuals.double(row.benchmark.qualityScore ?? 0),
                        label: "\(sourceName)，\(family)，每题平均耗时 \(RadarChartDescriptor.number(RadarVisuals.secondsPerTask(row) ?? 0, unit: "秒"))，IQ \(RadarChartDescriptor.number(RadarVisuals.double(row.benchmark.qualityScore ?? 0)))\(row.id == recommendation?.id ? "，当前推荐" : "")"
                    )]
                )
            }
        )
    }
}

enum RadarDecisionGoal: String, CaseIterable, Identifiable, Sendable {
    case quality = "最高质量"
    case value = "性价比"
    case quota = "最低额度"
    case speed = "最快完成"

    var id: Self { self }
    var icon: String {
        switch self {
        case .quality: "sparkles"
        case .value: "diamond"
        case .quota: "gauge.with.dots.needle.0percent"
        case .speed: "clock"
        }
    }
}


enum RadarDecisionLens {
    static func recommendation(
        in rows: [WorkspaceModelRow],
        for goal: RadarDecisionGoal
    ) -> WorkspaceModelRow? {
        rows.compactMap { row -> (WorkspaceModelRow, Double)? in
            let metric: Double?
            switch goal {
            case .quality:
                metric = row.benchmark.qualityScore.map(RadarVisuals.double)
            case .value:
                guard let quality = row.benchmark.qualityScore.map(RadarVisuals.double),
                      let cost = RadarVisuals.costPerTask(row),
                      cost > 0 else { return nil }
                metric = quality / RadarVisuals.double(cost)
            case .quota:
                metric = RadarVisuals.costPerTask(row).map { -RadarVisuals.double($0) }
            case .speed:
                metric = RadarVisuals.secondsPerTask(row).map { -$0 }
            }
            return metric.map { (row, $0) }
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
        }
        .first?.0
    }
}
