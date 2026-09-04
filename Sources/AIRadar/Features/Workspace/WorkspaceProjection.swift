import Foundation

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
    let renderedWarningPresentation: CodexRenderedWarningPresentation?
    var stationStatus: CodexStationStatusDataset? = nil
    var intelligenceEfficiencyDataset: IntelligenceEfficiencyDataset? = nil
    let renderedIQHistoryPresentation: CodexRenderedIQHistoryPresentation?

    init(
        sync: RadarSyncProjection?,
        lifecycle: RadarAppLifecycleState,
        supportLevel: SupportLevel,
        source: RadarSourceDescriptor = ClaudeRadarConfiguration.descriptor,
        renderedWarningState: SegmentState<CodexRenderedWarningSnapshot>? = nil,
        renderedWarningHistory: [CodexRenderedWarningSnapshot] = [],
        renderedIQHistoryState: SegmentState<CodexRenderedIQHistorySnapshot>? = nil,
        stationStatus: CodexStationStatusDataset? = nil,
        intelligenceEfficiencyDataset: IntelligenceEfficiencyDataset? = nil
    ) {
        self.sync = sync
        self.lifecycle = lifecycle
        self.supportLevel = supportLevel
        self.source = source
        renderedWarningPresentation = CodexRenderedWarningPresentation(
            sourceID: source.id,
            state: renderedWarningState,
            history: renderedWarningHistory
        )
        renderedIQHistoryPresentation = CodexRenderedIQHistoryPresentation(
            sourceID: source.id,
            state: renderedIQHistoryState
        )
        self.stationStatus = stationStatus
        self.intelligenceEfficiencyDataset = intelligenceEfficiencyDataset
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
    var intelligenceEfficiency: [IntelligenceEfficiencyPoint] {
        guard benchmarkState == .fresh, let dataset = sync?.benchmark.value else { return [] }
        return IntelligenceEfficiency.points(
            models: dataset.models.filter { $0.id.sourceID == dataset.sourceID }
        )
    }
    func localDeclineSignals(history: [BenchmarkDataset], limit: Int = 4) -> [RadarDeclineSignal] {
        guard benchmarkState == .fresh else { return [] }
        return RadarDeclineAnalysis.signals(history: history, sourceID: source.id, limit: limit)
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
        struct Group {
            var names: Set<String> = []
            var points: [TrendPoint] = []
            var segmentIndex = 0
        }
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
            for model in snapshot.models
            where selected.contains(model.id) && model.id.sourceID == snapshot.sourceID {
                let key = Key(id: model.id, revision: snapshot.seriesRevision)
                grouped[key, default: Group()].names.insert(model.descriptor.displayName)
                guard let value = metricValue(model, metric: metric) else {
                    grouped[key, default: Group()].segmentIndex += 1
                    continue
                }
                let date = snapshot.sourceUpdatedAt ?? snapshot.fetchedAt
                let pointID = "\(snapshot.sourceID.rawValue)|\(key.id.upstreamKey)|\(key.revision)|\(date.timeIntervalSince1970)|\(snapshotIndex)"
                let segmentIndex = grouped[key, default: Group()].segmentIndex
                grouped[key, default: Group()].points.append(
                    .init(id: pointID, date: date, value: value, segmentIndex: segmentIndex)
                )
            }
        }
        return grouped.compactMap {
            guard !$0.value.points.isEmpty else { return nil }
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
        switch metric {
        case .quality: model.qualityScore.map { NSDecimalNumber(decimal: $0).doubleValue }
        case .cost: model.benchmarkCostUSD.map { NSDecimalNumber(decimal: $0).doubleValue }
        case .elapsed: model.elapsedSeconds
        case .agentSteps: model.agentSteps.map(Double.init)
        case .cache: model.cacheHitPercent.map { NSDecimalNumber(decimal: $0).doubleValue }
        case .tokens: model.totalTokens.map(Double.init)
        }
    }
}
