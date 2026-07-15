import Foundation
import Observation

enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case overview = "概览"
    case models = "模型"
    case trends = "趋势"
    case sourceStatus = "来源状态"
    case export = "导出"
    var id: Self { self }
    var icon: String { switch self { case .overview: "rectangle.grid.2x2"; case .models: "list.bullet.rectangle"; case .trends: "chart.xyaxis.line"; case .sourceStatus: "antenna.radiowaves.left.and.right"; case .export: "square.and.arrow.up" } }
}

enum WorkspaceCopy {
    static let sourceStatusTitle = "Claude Code Radar 来源状态"
    static let quotaTitle = "Claude Code Radar 来源额度估算"
    static let exportPlaceholder = "Phase 6 将提供分页 JSON 导出"

    static func sourceStatusTitle(for source: RadarSourceDescriptor) -> String {
        "\(source.displayName) 来源状态"
    }

    static func quotaTitle(for source: RadarSourceDescriptor) -> String {
        "\(source.displayName) 来源额度估算"
    }
}

enum WorkspaceState: Equatable, Sendable {
    case loading, empty, fresh, stale, usingLastKnownGood
    case validationFailed(hasLastKnownGood: Bool)
    case unavailable(String), disabled(String), error(String)
}

enum ModelSort: String, CaseIterable, Sendable {
    case name = "名称", quality = "质量", cost = "成本", tokens = "Token", elapsed = "耗时"
}

enum TrendMetric: String, CaseIterable, Sendable {
    case quality = "质量", cost = "成本", tokens = "Token", elapsed = "耗时"
}

enum TrendTimeRange: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case lastDay = "24 小时"
    case lastSevenDays = "7 天"
    case lastThirtyDays = "30 天"

    var id: Self { self }
    fileprivate var interval: TimeInterval? {
        switch self {
        case .all: nil
        case .lastDay: 24 * 60 * 60
        case .lastSevenDays: 7 * 24 * 60 * 60
        case .lastThirtyDays: 30 * 24 * 60 * 60
        }
    }
}

enum ModelColumn: Hashable, Sendable {
    case model, quality, passRate, cost, tokens, elapsed, agentSteps, cache, community
}

struct WorkspaceModelRow: Identifiable, Sendable {
    let benchmark: ModelBenchmark
    let community: CommunityRating?
    var id: ModelID { benchmark.id }
    var name: String { benchmark.descriptor.displayName }
    var passRate: Decimal? {
        guard let passed = benchmark.passedTasks, let valid = benchmark.validTasks, valid > 0 else { return nil }
        return Decimal(passed) / Decimal(valid) * 100
    }
}

struct TrendPoint: Identifiable, Sendable {
    let id: String
    let date: Date
    let value: Double
}

struct TrendSeries: Identifiable, Sendable {
    let modelID: ModelID
    let modelName: String
    let seriesRevision: String
    let points: [TrendPoint]
    var id: String { "\(modelID.sourceID.rawValue)|\(modelID.upstreamKey)|\(seriesRevision)" }
}

struct CostEfficiencyLeader: Equatable, Sendable {
    let modelID: ModelID
    let modelName: String
    let costPerPassedTask: Decimal
    let formula: DerivedMetricFormula
}

struct BenchmarkPresentation: Equatable, Sendable {
    let supportState: WorkspaceState?
    let healthState: WorkspaceState?
    let error: String?
}

struct WorkspaceProjection: Sendable {
    let sync: RadarSyncProjection?
    let lifecycle: RadarAppLifecycleState
    let supportLevel: SupportLevel
    let source: RadarSourceDescriptor

    init(
        sync: RadarSyncProjection?,
        lifecycle: RadarAppLifecycleState,
        supportLevel: SupportLevel,
        source: RadarSourceDescriptor = ClaudeRadarConfiguration.descriptor
    ) {
        self.sync = sync
        self.lifecycle = lifecycle
        self.supportLevel = supportLevel
        self.source = source
    }

    var benchmarkState: WorkspaceState { state(sync?.benchmark, lifecycle: lifecycle) }
    var benchmarkPresentation: BenchmarkPresentation {
        let health = benchmarkState
        guard supportLevel == .disabled else {
            return .init(supportState: nil, healthState: health, error: latestError)
        }
        let hasCachedData = sync?.benchmark.value != nil
        let support: WorkspaceState = hasCachedData
            ? .disabled("在线来源在当前构建中未启用，显示缓存数据")
            : .disabled("在线来源在当前构建中未启用")
        return .init(
            supportState: support,
            healthState: health == .fresh && hasCachedData ? nil : health,
            error: latestError
        )
    }
    var communityState: WorkspaceState {
        guard let segment = sync?.community else { return lifecycle == .starting ? .loading : .unavailable("社区评分暂不可用") }
        if segment.value == nil, segment.error == nil { return .unavailable("社区评分暂不可用") }
        return state(segment, lifecycle: lifecycle)
    }
    var supportState: WorkspaceState {
        supportLevel == .disabled ? .disabled("在线来源在当前构建中未启用") : .fresh
    }
    var sourceStatusState: WorkspaceState { state(sync?.sourceStatus, lifecycle: lifecycle) }
    var latestError: String? {
        let segments: [(SegmentError?, Bool)] = [
            (sync?.benchmark.error, sync?.benchmark.value != nil),
            (sync?.community.error, sync?.community.value != nil),
            (sync?.sourceStatus.error, sync?.sourceStatus.value != nil),
        ]
        if let (_, hasLastKnownGood) = segments.first(where: { $0.0?.kind == .validation }) {
            return hasLastKnownGood ? "新数据未通过校验，已保留旧值" : "新数据未通过校验，暂无可用旧值"
        }
        if lifecycle == .failed { return "同步运行时不可用" }
        guard let (error, _) = segments.first(where: { $0.0 != nil }), let error else { return nil }
        return safe(error.message)
    }
    var rows: [WorkspaceModelRow] {
        let ratings = Dictionary(uniqueKeysWithValues: (sync?.community.value?.ratings ?? []).map { ($0.id, $0) })
        return (sync?.benchmark.value?.models ?? []).map { .init(benchmark: $0, community: ratings[$0.id]) }
    }
    var updatedAt: Date? { sync?.benchmark.value?.sourceUpdatedAt ?? sync?.benchmark.value?.fetchedAt }
    var communityError: String? { sync?.community.error.map { safe($0.message) } }
    var bestCostEfficiency: CostEfficiencyLeader? {
        rows.compactMap { row -> CostEfficiencyLeader? in
            guard let result = DerivedMetrics.evaluate(model: row.benchmark)
                .first(where: { $0.formula == .costPerPassedTask }),
                case .decimal(let value) = result.value else { return nil }
            return .init(
                modelID: row.id,
                modelName: row.name,
                costPerPassedTask: value,
                formula: result.formula
            )
        }
        .min {
            if $0.costPerPassedTask != $1.costPerPassedTask {
                return $0.costPerPassedTask < $1.costPerPassedTask
            }
            let nameOrder = $0.modelName.localizedStandardCompare($1.modelName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.modelID.upstreamKey < $1.modelID.upstreamKey
        }
    }
    func pareto(_ preset: ParetoPreset) -> [ParetoResult] {
        guard let dataset = sync?.benchmark.value else { return [] }
        return ParetoAnalysis.analyze(dataset: dataset, preset: preset)
    }
    var availableModelColumns: Set<ModelColumn> {
        var columns: Set<ModelColumn> = [.model]
        if rows.contains(where: { $0.benchmark.qualityScore != nil }) { columns.insert(.quality) }
        if rows.contains(where: { $0.passRate != nil }) { columns.insert(.passRate) }
        if rows.contains(where: { $0.benchmark.benchmarkCostUSD != nil }) { columns.insert(.cost) }
        if rows.contains(where: { $0.benchmark.totalTokens != nil }) { columns.insert(.tokens) }
        if rows.contains(where: { $0.benchmark.elapsedSeconds != nil }) { columns.insert(.elapsed) }
        if rows.contains(where: { $0.benchmark.agentSteps != nil }) { columns.insert(.agentSteps) }
        if rows.contains(where: { $0.benchmark.cacheHitPercent != nil }) { columns.insert(.cache) }
        if rows.contains(where: { $0.community?.average != nil }) { columns.insert(.community) }
        return columns
    }

    func filteredModels(query: String, sort: ModelSort, ascending: Bool) -> [WorkspaceModelRow] {
        let filtered = rows.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.sorted { left, right in
            if sort != .name {
                let leftIsNil = Self.isNil(left.benchmark, sort)
                let rightIsNil = Self.isNil(right.benchmark, sort)
                if leftIsNil != rightIsNil { return !leftIsNil }
            }
            let order = compare(left, right, by: sort)
            if order == 0 { return tieBreak(left, right) }
            return ascending ? order < 0 : order > 0
        }
    }

    static func singleModelHistory(
        history: [BenchmarkDataset],
        modelID: ModelID,
        metric: TrendMetric
    ) -> [TrendSeries] {
        trendSeries(history: history, metric: metric, selected: [modelID])
    }

    static func trendSeries(
        history: [BenchmarkDataset],
        metric: TrendMetric,
        selected: Set<ModelID>,
        timeRange: TrendTimeRange = .all
    ) -> [TrendSeries] {
        struct Key: Hashable { let id: ModelID; let revision: String }
        struct Group { var names: Set<String> = []; var points: [TrendPoint] = [] }
        var grouped: [Key: Group] = [:]
        let orderedHistory = history.sorted {
            ($0.sourceUpdatedAt ?? $0.fetchedAt) < ($1.sourceUpdatedAt ?? $1.fetchedAt)
        }
        let filteredHistory: [BenchmarkDataset]
        if let interval = timeRange.interval,
           let latest = orderedHistory.last.map({ $0.sourceUpdatedAt ?? $0.fetchedAt }) {
            let cutoff = latest.addingTimeInterval(-interval)
            filteredHistory = orderedHistory.filter { ($0.sourceUpdatedAt ?? $0.fetchedAt) >= cutoff }
        } else {
            filteredHistory = orderedHistory
        }
        for (snapshotIndex, snapshot) in filteredHistory.enumerated() {
            for model in snapshot.models where selected.contains(model.id) {
                guard let value = metricValue(model, metric: metric) else { continue }
                let key = Key(id: model.id, revision: snapshot.seriesRevision)
                let date = snapshot.sourceUpdatedAt ?? snapshot.fetchedAt
                let pointID = "\(snapshot.sourceID.rawValue)|\(key.id.upstreamKey)|\(key.revision)|\(date.timeIntervalSince1970)|\(snapshotIndex)"
                grouped[key, default: Group()].names.insert(model.descriptor.displayName)
                grouped[key, default: Group()].points.append(.init(id: pointID, date: date, value: value))
            }
        }
        return grouped.map {
            let name = $0.value.names.min() ?? $0.key.id.upstreamKey
            return .init(modelID: $0.key.id, modelName: name, seriesRevision: $0.key.revision, points: $0.value.points)
        }
            .sorted { $0.id < $1.id }
    }

    private func compare(_ lhs: WorkspaceModelRow, _ rhs: WorkspaceModelRow, by sort: ModelSort) -> Int {
        if sort == .name { return lhs.name.localizedStandardCompare(rhs.name).rawValue }
        return switch sort {
        case .name: 0
        case .quality: Self.compareOptional(lhs.benchmark.qualityScore, rhs.benchmark.qualityScore)
        case .cost: Self.compareOptional(lhs.benchmark.benchmarkCostUSD, rhs.benchmark.benchmarkCostUSD)
        case .tokens: Self.compareOptional(lhs.benchmark.totalTokens, rhs.benchmark.totalTokens)
        case .elapsed: Self.compareOptional(lhs.benchmark.elapsedSeconds, rhs.benchmark.elapsedSeconds)
        }
    }

    private func tieBreak(_ lhs: WorkspaceModelRow, _ rhs: WorkspaceModelRow) -> Bool {
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id.upstreamKey < rhs.id.upstreamKey
    }

    private static func isNil(_ model: ModelBenchmark, _ sort: ModelSort) -> Bool {
        switch sort {
        case .name: false
        case .quality: model.qualityScore == nil
        case .cost: model.benchmarkCostUSD == nil
        case .tokens: model.totalTokens == nil
        case .elapsed: model.elapsedSeconds == nil
        }
    }
    private static func compareOptional<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Int {
        guard let lhs, let rhs else { return 0 }
        if lhs == rhs { return 0 }
        return lhs < rhs ? -1 : 1
    }
    private static func metricValue(_ model: ModelBenchmark, metric: TrendMetric) -> Double? {
        switch metric { case .quality: model.qualityScore.map { NSDecimalNumber(decimal: $0).doubleValue }; case .cost: model.benchmarkCostUSD.map { NSDecimalNumber(decimal: $0).doubleValue }; case .tokens: model.totalTokens.map(Double.init); case .elapsed: model.elapsedSeconds }
    }
}

private func state<T>(_ segment: SegmentState<T>?, lifecycle: RadarAppLifecycleState) -> WorkspaceState {
    if segment?.error?.kind == .validation { return .validationFailed(hasLastKnownGood: segment?.value != nil) }
    if lifecycle == .failed {
        return segment?.value == nil ? .error("同步运行时不可用") : .usingLastKnownGood
    }
    guard let segment else {
        if lifecycle == .starting { return .loading }
        return .empty
    }
    if segment.error != nil, segment.value != nil { return .usingLastKnownGood }
    if let error = segment.error, segment.value == nil { return .error(safe(error.message)) }
    guard segment.value != nil else {
        return .empty
    }
    return segment.isStale ? .stale : .fresh
}

struct TrendSelectionState: Equatable, Sendable {
    var selected: Set<ModelID> = []
    var hasInitializedSelection = false
}

enum TrendSelection {
    static func reconcile(
        state: TrendSelectionState,
        rows: [WorkspaceModelRow],
        history: [BenchmarkDataset]
    ) -> TrendSelectionState {
        let historicalIDs = Set(history.flatMap { $0.models.map(\.id) })
        let candidates = rows
            .filter { historicalIDs.contains($0.id) }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id.upstreamKey < $1.id.upstreamKey : order == .orderedAscending
            }
        let available = Set(candidates.map(\.id))
        if state.hasInitializedSelection {
            return .init(selected: state.selected.intersection(available), hasInitializedSelection: true)
        }
        guard let first = candidates.first else { return state }
        return .init(selected: [first.id], hasInitializedSelection: true)
    }

    static func userChanged(_ state: TrendSelectionState, selected: Set<ModelID>) -> TrendSelectionState {
        .init(selected: selected, hasInitializedSelection: true)
    }
}

private func safe(_ text: String) -> String {
    text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).prefix(160).description
}

enum MenuBarAction: CaseIterable { case refresh, openWorkspace, quit }
enum AppLifecycleAction { case closeWorkspace, quit; var terminatesProcess: Bool { self == .quit } }
enum RefreshActionAvailability {
    static func isEnabled(supportLevel: SupportLevel) -> Bool { supportLevel != .disabled }
}

@MainActor @Observable
final class RadarWorkspaceModel {
    private let runtimes: [RadarSourceID: RadarAppRuntime]
    private(set) var selectedSourceID: RadarSourceID

    init(runtimes: [RadarSourceID: RadarAppRuntime], selectedSourceID: RadarSourceID) {
        precondition(runtimes[selectedSourceID] != nil)
        self.runtimes = runtimes
        self.selectedSourceID = selectedSourceID
    }

    var runtime: RadarAppRuntime { runtimes[selectedSourceID]! }
    var source: RadarSourceDescriptor { runtime.descriptor }
    var sources: [RadarSourceDescriptor] {
        [RadarSourceID.claudeCodeRadar, .codexRadar].compactMap { runtimes[$0]?.descriptor }
    }
    var projection: WorkspaceProjection {
        .init(
            sync: runtime.projection,
            lifecycle: runtime.lifecycleState,
            supportLevel: runtime.supportLevel,
            source: runtime.descriptor
        )
    }
    var history: [BenchmarkDataset] { runtime.benchmarkHistory }
    func selectSource(_ sourceID: RadarSourceID) {
        guard runtimes[sourceID] != nil else { return }
        selectedSourceID = sourceID
    }
    func start() async {
        await withTaskGroup(of: Void.self) { group in
            for runtime in runtimes.values {
                group.addTask { await runtime.start() }
            }
        }
    }
    func stop() async {
        for runtime in runtimes.values { await runtime.stop() }
    }
    func refresh() async { await runtime.refresh() }
}
