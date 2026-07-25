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
        VStack(spacing: RadarStyle.cardSpacing) {
            HStack {
                Picker("排序", selection: $sort) { ForEach(ModelSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: selection == nil ? 160 : 120)
                Button { ascending.toggle() } label: { Label(ascending ? "升序" : "降序", systemImage: ascending ? "arrow.up" : "arrow.down") }
                Picker("Pareto", selection: $paretoPreset) { ForEach(ParetoPreset.allCases) { Text($0.name).tag($0) } }.frame(width: selection == nil ? 210 : 150)
                Spacer()
            }
            .radarPanel()
            Table(rows, selection: $selection) {
                TableColumn("模型") { Text($0.name).lineLimit(2) }.width(min: 150, ideal: 220)
                if selection == nil, columns.contains(.quality) {
                    TableColumn("质量") { Text(RadarFormat.decimal($0.benchmark.qualityScore)) }
                }
                if selection == nil, columns.contains(.passRate) {
                    TableColumn("通过率") { Text(RadarFormat.decimal($0.passRate, suffix: "%")) }
                }
                if selection == nil, columns.contains(.cost) {
                    TableColumn("成本") { Text($0.benchmark.benchmarkCostUSD.map { "$" + RadarFormat.decimal($0) } ?? "—") }
                }
                if selection == nil, columns.contains(.tokens) {
                    TableColumn("Token") { Text(RadarFormat.integer($0.benchmark.totalTokens)) }
                }
                if selection == nil, columns.contains(.elapsed) {
                    TableColumn("耗时") { Text(RadarFormat.seconds($0.benchmark.elapsedSeconds)) }
                }
                if selection == nil, columns.contains(.agentSteps) {
                    TableColumn("Agent Steps") { Text(RadarFormat.integer($0.benchmark.agentSteps)) }
                }
                if selection == nil, columns.contains(.cache) {
                    TableColumn("Cache") { Text(RadarFormat.decimal($0.benchmark.cacheHitPercent, suffix: "%")) }
                }
                if selection == nil, columns.contains(.community) {
                    TableColumn("社区") { Text(RadarFormat.decimal($0.community?.average)) }
                }
                TableColumn("Pareto") { Text(classification(for: $0.id).label) }
            }
            .overlay { if rows.isEmpty { ContentUnavailableView.search(text: query) } }
            .radarPanel()
        }
        .radarPage()
        .searchable(text: $query, prompt: "筛选模型")
        .inspector(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selection = nil } }
        )) { if let selected { ModelDetailView(row: selected, sourceName: projection.source.displayName, revision: projection.sync?.benchmark.value?.seriesRevision ?? "—", paretoPreset: paretoPreset, paretoClassification: classification(for: selected.id), history: history).inspectorColumnWidth(min: 280, ideal: 320, max: 380) } }
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
