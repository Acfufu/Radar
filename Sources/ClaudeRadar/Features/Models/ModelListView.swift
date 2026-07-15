import SwiftUI

struct ModelListView: View {
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]
    @State private var query = ""
    @State private var sort: ModelSort = .quality
    @State private var ascending = false
    @State private var selection: ModelID?
    @State private var paretoPreset: ParetoPreset = .qualityCost

    init(projection: WorkspaceProjection, history: [BenchmarkDataset]) {
        self.projection = projection
        self.history = history
        #if DEBUG
        let variables = ProcessInfo.processInfo.environment
        _query = State(initialValue: variables["RADAR_UI_MODEL_QUERY"] ?? "")
        if let key = variables["RADAR_UI_MODEL_KEY"] {
            _selection = State(initialValue: ModelID(sourceID: projection.source.id, upstreamKey: key))
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("排序", selection: $sort) { ForEach(ModelSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 160)
                Button { ascending.toggle() } label: { Label(ascending ? "升序" : "降序", systemImage: ascending ? "arrow.up" : "arrow.down") }
                Picker("Pareto", selection: $paretoPreset) { ForEach(ParetoPreset.allCases) { Text($0.name).tag($0) } }.frame(width: 210)
                Spacer()
            }.padding([.horizontal, .top])
            Table(rows, selection: $selection) {
                TableColumn("模型") { Text($0.name).lineLimit(2) }.width(min: 150, ideal: 220)
                if columns.contains(.quality) {
                    TableColumn("质量") { Text(RadarFormat.decimal($0.benchmark.qualityScore)) }
                }
                if columns.contains(.passRate) {
                    TableColumn("通过率") { Text(RadarFormat.decimal($0.passRate, suffix: "%")) }
                }
                if columns.contains(.cost) {
                    TableColumn("成本") { Text($0.benchmark.benchmarkCostUSD.map { "$" + RadarFormat.decimal($0) } ?? "—") }
                }
                if columns.contains(.tokens) {
                    TableColumn("Token") { Text(RadarFormat.integer($0.benchmark.totalTokens)) }
                }
                if columns.contains(.elapsed) {
                    TableColumn("耗时") { Text(RadarFormat.seconds($0.benchmark.elapsedSeconds)) }
                }
                if columns.contains(.agentSteps) {
                    TableColumn("Agent Steps") { Text(RadarFormat.integer($0.benchmark.agentSteps)) }
                }
                if columns.contains(.cache) {
                    TableColumn("Cache") { Text(RadarFormat.decimal($0.benchmark.cacheHitPercent, suffix: "%")) }
                }
                if columns.contains(.community) {
                    TableColumn("社区") { Text(RadarFormat.decimal($0.community?.average)) }
                }
                TableColumn("Pareto") { Text(classification(for: $0.id).label) }
            }
            .overlay { if rows.isEmpty { ContentUnavailableView.search(text: query) } }
        }
        .searchable(text: $query, prompt: "筛选模型")
        .inspector(isPresented: .constant(selected != nil)) { if let selected { ModelDetailView(row: selected, sourceName: projection.source.displayName, revision: projection.sync?.benchmark.value?.seriesRevision ?? "—", paretoPreset: paretoPreset, paretoClassification: classification(for: selected.id), history: history).inspectorColumnWidth(min: 340, ideal: 420, max: 520) } }
        .navigationTitle("模型")
    }

    private var rows: [WorkspaceModelRow] { projection.filteredModels(query: query, sort: sort, ascending: ascending) }
    private var columns: Set<ModelColumn> { projection.availableModelColumns }
    private var selected: WorkspaceModelRow? { rows.first { $0.id == selection } }
    private var pareto: [ParetoResult] { projection.pareto(paretoPreset) }
    private func classification(for id: ModelID) -> ParetoClassification {
        pareto.first { $0.modelID == id }?.classification ?? .dataInsufficient
    }
}
