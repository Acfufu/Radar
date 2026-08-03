import Charts
import SwiftUI

struct SWEBenchLeaderboardView: View {
    @Environment(\.radarPalette) private var palette
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    @State private var query = ""
    @State private var sort = SWEBenchSort.resolved
    @State private var ascending = false
    @State private var onlyWithCost = false
    @State private var selection: ModelID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
                    header
                    if let supportState = projection.benchmarkPresentation.supportState {
                        StateBanner(state: supportState, error: nil, sourceName: projection.source.displayName)
                    }
                    summary
                    analysis
                }
                .radarPage()
            }
            .frame(minHeight: 300, idealHeight: 340, maxHeight: 380)
            Divider().overlay(palette.divider.color)
            ViewThatFits(in: .horizontal) {
                HStack {
                    filterControls
                    Spacer()
                    rowCount
                }
                VStack(alignment: .leading, spacing: 8) {
                    compactFilterControls
                    rowCount
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(palette.section.color)
            GeometryReader { geometry in
                Group {
                    if geometry.size.width < 720 {
                        compactLeaderboardTable
                    } else {
                        fullLeaderboardTable
                    }
                }
                .radarPanel()
                .overlay {
                    if rows.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "筛选配置")
        .background(palette.canvas.color)
        .inspector(isPresented: .constant(selected != nil)) {
            if let selected {
                SWEBenchDetailView(
                    row: selected,
                    projection: projection,
                    history: history,
                    classification: classification(for: selected.id)
                )
                .inspectorColumnWidth(min: 340, ideal: 420, max: 520)
            }
        }
        .navigationTitle("SWE-bench Verified")
    }

    private var compactLeaderboardTable: some View {
        Table(rows, selection: $selection) {
            TableColumn("配置") { Text($0.name).lineLimit(2) }
                .width(min: 150, ideal: 230)
            TableColumn("% Resolved") {
                Text(RadarFormat.decimal($0.benchmark.qualityScore, suffix: "%"))
            }
            .width(90)
            TableColumn("Resolved / 500") {
                Text("\(RadarFormat.integer($0.benchmark.passedTasks)) / 500")
            }
            .width(115)
        }
    }

    private var fullLeaderboardTable: some View {
        Table(rows, selection: $selection) {
            TableColumn("配置") { Text($0.name).lineLimit(2) }
                .width(min: 130, ideal: 180, max: 220)
            TableColumn("% Resolved") {
                Text(RadarFormat.decimal($0.benchmark.qualityScore, suffix: "%"))
            }
            .width(78)
            TableColumn("Resolved / 500") {
                Text("\(RadarFormat.integer($0.benchmark.passedTasks)) / 500")
            }
            .width(100)
            TableColumn("总成本") {
                Text($0.benchmark.benchmarkCostUSD.map { "$" + RadarFormat.decimal($0) } ?? "未发布")
            }
            .width(65)
            TableColumn("每解决成本") {
                Text($0.costPerResolved.map { "$" + RadarFormat.decimal($0) } ?? "—")
            }
            .width(85)
            TableColumn("Pareto") { Text(classification(for: $0.id).label) }
                .width(65)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ViewHeader(
                title: "SWE-bench Verified",
                subtitle: "mini-SWE-agent v2 · 500 tasks · 读取于 \(RadarFormat.date(projection.updatedAt))"
            )
            Spacer()
            Label("只读", systemImage: "eye")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(palette.accentSoft.color, in: .rect(cornerRadius: RadarStyle.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: RadarStyle.cornerRadius)
                        .stroke(palette.accentBorder.color)
                }
        }
    }

    private var summary: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: RadarStyle.compactSpacing)],
            spacing: RadarStyle.compactSpacing
        ) {
            metricCard("配置数", "\(projection.rows.count)")
            metricCard("最高解决率", RadarFormat.decimal(leader?.benchmark.qualityScore, suffix: "%"))
            metricCard("任务数", "500")
            metricCard(
                "最低每解决成本",
                projection.bestCostEfficiency.map { "$" + RadarFormat.decimal($0.costPerPassedTask) } ?? "—"
            )
        }
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarMetricCard()
    }

    private var analysis: some View {
        GroupBox("同口径成本与解决率") {
            if chartRows.isEmpty {
                ContentUnavailableView(
                    "暂无可绘制成本数据",
                    systemImage: "chart.dots.scatter",
                    description: Text("仅展示上游同时发布解决率和总成本的配置。")
                )
                .frame(minHeight: 180)
            } else {
                Chart(chartRows) { row in
                    PointMark(
                        x: .value("总成本（USD）", decimal(row.benchmark.benchmarkCostUSD)),
                        y: .value("% Resolved", decimal(row.benchmark.qualityScore))
                    )
                    .foregroundStyle(by: .value("状态", classification(for: row.id).label))
                    .symbol(by: .value("状态", classification(for: row.id).label))
                }
                .accessibilityChartDescriptor(leaderboardDescriptor)
                .chartXScale(domain: 0...maximumChartCost)
                .chartYScale(domain: 0...100)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(palette.divider.color)
                        AxisValueLabel().foregroundStyle(palette.secondaryText.color)
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(palette.divider.color)
                        AxisValueLabel().foregroundStyle(palette.secondaryText.color)
                    }
                }
                .chartPlotStyle { $0.background(palette.section.color) }
                .frame(minHeight: 190)
                Text("Pareto 仅在 Verified · mini-SWE-agent v2 · \(projection.source.seriesRevision) 内计算。")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .groupBoxStyle(RadarGroupBoxStyle())
    }

    private var leaderboardDescriptor: RadarChartDescriptor {
        RadarChartDescriptor(
            title: "\(projection.source.displayName) · 成本与 % Resolved",
            summary: "仅 Verified · mini-SWE-agent v2 · \(projection.source.seriesRevision)；Pareto 状态同时以符号和系列名称区分。",
            xAxisTitle: "总成本（USD）",
            yAxisTitle: "% Resolved（%）",
            xValueDescription: { RadarChartDescriptor.number($0, unit: "USD") },
            yValueDescription: { RadarChartDescriptor.number($0, unit: "%") },
            series: [ParetoClassification.frontier, .dominated, .dataInsufficient].map { classification in
                .init(
                    name: classification.label,
                    isContinuous: false,
                    points: chartRows.filter { self.classification(for: $0.id) == classification }.map { row in
                        let cost = decimal(row.benchmark.benchmarkCostUSD)
                        let resolved = decimal(row.benchmark.qualityScore)
                        return .init(
                            x: cost,
                            y: resolved,
                            label: "\(projection.source.displayName)，\(row.name)，\(classification.label)，总成本 \(RadarChartDescriptor.number(cost, unit: "USD"))，% Resolved \(RadarChartDescriptor.number(resolved, unit: "%"))"
                        )
                    }
                )
            }
        )
    }

    private var filterControls: some View {
        HStack {
            sortPicker
            directionButton
            costToggle
        }
    }

    private var compactFilterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sortPicker
                directionButton
            }
            costToggle
        }
    }

    private var sortPicker: some View {
        Picker("排序", selection: $sort) {
            ForEach(SWEBenchSort.allCases) { Text($0.rawValue).tag($0) }
        }
        .frame(width: 170)
    }

    private var directionButton: some View {
        Button { ascending.toggle() } label: {
            Label(ascending ? "升序" : "降序", systemImage: ascending ? "arrow.up" : "arrow.down")
        }
    }

    private var costToggle: some View {
        Toggle("仅显示成本数据", isOn: $onlyWithCost)
    }

    private var rowCount: some View {
        Text("\(rows.count) 个配置")
            .foregroundStyle(palette.secondaryText.color)
    }

    private var leader: WorkspaceModelRow? {
        projection.rows.max {
            ($0.benchmark.qualityScore ?? 0) < ($1.benchmark.qualityScore ?? 0)
        }
    }

    private var chartRows: [WorkspaceModelRow] {
        projection.rows.filter {
            $0.benchmark.qualityScore != nil && $0.benchmark.benchmarkCostUSD != nil
        }
    }

    private var maximumChartCost: Double {
        max(chartRows.compactMap {
            $0.benchmark.benchmarkCostUSD.map { NSDecimalNumber(decimal: $0).doubleValue }
        }.max() ?? 1, 1) * 1.05
    }

    private var rows: [SWEBenchRow] {
        projection.rows
            .filter {
                (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
                    && (!onlyWithCost || $0.benchmark.benchmarkCostUSD != nil)
            }
            .map(SWEBenchRow.init)
            .sorted {
                let order = sort.compare($0, $1)
                if order == 0 {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return ascending ? order < 0 : order > 0
            }
    }

    private var selected: SWEBenchRow? { rows.first { $0.id == selection } }
    private var pareto: [ModelID: ParetoClassification] {
        Dictionary(uniqueKeysWithValues: projection.pareto(.qualityCost).map {
            ($0.modelID, $0.classification)
        })
    }
    private func classification(for id: ModelID) -> ParetoClassification {
        pareto[id] ?? .dataInsufficient
    }
    private func decimal(_ value: Decimal?) -> Double {
        value.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
    }
}

private enum SWEBenchSort: String, CaseIterable, Identifiable {
    case name = "配置名称"
    case resolved = "解决率"
    case cost = "总成本"
    case costPerResolved = "每解决成本"

    var id: Self { self }

    func compare(_ lhs: SWEBenchRow, _ rhs: SWEBenchRow) -> Int {
        switch self {
        case .name:
            lhs.name.localizedStandardCompare(rhs.name).rawValue
        case .resolved:
            compareOptional(lhs.benchmark.qualityScore, rhs.benchmark.qualityScore)
        case .cost:
            compareOptional(lhs.benchmark.benchmarkCostUSD, rhs.benchmark.benchmarkCostUSD)
        case .costPerResolved:
            compareOptional(lhs.costPerResolved, rhs.costPerResolved)
        }
    }

    private func compareOptional<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Int {
        switch (lhs, rhs) {
        case (.none, .none): 0
        case (.none, .some): -1
        case (.some, .none): 1
        case (.some(let lhs), .some(let rhs)):
            lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        }
    }
}

private struct SWEBenchRow: Identifiable {
    let benchmark: ModelBenchmark
    var id: ModelID { benchmark.id }
    var name: String { benchmark.descriptor.displayName }
    var costPerResolved: Decimal? {
        guard let cost = benchmark.benchmarkCostUSD,
              let resolved = benchmark.passedTasks,
              resolved > 0 else { return nil }
        return cost / Decimal(resolved)
    }

    init(_ row: WorkspaceModelRow) {
        benchmark = row.benchmark
    }
}

private struct SWEBenchDetailView: View {
    let row: SWEBenchRow
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    let classification: ParetoClassification

    var body: some View {
        Form {
            Section("配置") {
                LabeledContent("名称", value: row.name)
                LabeledContent("来源", value: projection.source.displayName)
                LabeledContent("上游标识", value: row.id.upstreamKey)
                LabeledContent("口径", value: "Verified · mini-SWE-agent v2")
                LabeledContent("seriesRevision", value: projection.source.seriesRevision)
            }
            Section("已发布指标") {
                LabeledContent("% Resolved", value: RadarFormat.decimal(row.benchmark.qualityScore, suffix: "%"))
                LabeledContent(
                    "Resolved / 500",
                    value: "\(RadarFormat.integer(row.benchmark.passedTasks)) / 500"
                )
                LabeledContent(
                    "总成本",
                    value: row.benchmark.benchmarkCostUSD.map { "$" + RadarFormat.decimal($0) } ?? "未发布"
                )
                LabeledContent(
                    "每解决成本",
                    value: row.costPerResolved.map { "$" + RadarFormat.decimal($0) } ?? "—"
                )
                LabeledContent("成本 / 解决任务", value: "benchmarkCostUSD / resolvedTasks")
                LabeledContent("同口径 Pareto", value: classification.label)
            }
            Section("兼容历史") {
                let points = WorkspaceProjection.singleModelHistory(
                    history: history,
                    modelID: row.id,
                    metric: .quality
                )
                if points.flatMap(\.points).count < 2 {
                    Text("等待至少两个同 seriesRevision 快照。").foregroundStyle(.secondary)
                } else {
                    Text(points.map { "\($0.seriesRevision)：\($0.points.count) 个点" }.joined(separator: " · "))
                }
            }
            Section("出处") {
                LabeledContent("读取时间", value: RadarFormat.date(projection.updatedAt))
                if let homepageURL = projection.source.homepageURL {
                    Link("打开 SWE-bench 上游页面", destination: homepageURL)
                }
                Text("Radar 仅浏览和分析已发布结果，不运行或提交评测。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .radarPanel()
        .radarPage()
        .navigationTitle(row.name)
    }
}
