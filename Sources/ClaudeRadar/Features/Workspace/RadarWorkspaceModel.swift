import Foundation
import Observation

enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case overview = "概览"
    case decisionLens = "决策透镜"
    case models = "模型"
    case trends = "趋势"
    case sourceStatus = "来源状态"
    case export = "导出"
    var id: Self { self }
    var icon: String { switch self { case .overview: "rectangle.grid.2x2"; case .decisionLens: "scope"; case .models: "list.bullet.rectangle"; case .trends: "chart.xyaxis.line"; case .sourceStatus: "antenna.radiowaves.left.and.right"; case .export: "square.and.arrow.up" } }

    func title(for sourceID: RadarSourceID) -> String {
        guard sourceID == .sweBenchVerified else { return rawValue }
        return switch self {
        case .models: "榜单"
        case .sourceStatus: "来源与口径"
        default: rawValue
        }
    }

    fileprivate var storageKey: String {
        switch self {
        case .overview: "overview"
        case .decisionLens: "decision-lens"
        case .models: "models"
        case .trends: "trends"
        case .sourceStatus: "source-status"
        case .export: "export"
        }
    }

    fileprivate init?(storageKey: String) {
        switch storageKey {
        case "overview": self = .overview
        case "decision-lens": self = .decisionLens
        case "models": self = .models
        case "trends": self = .trends
        case "source-status": self = .sourceStatus
        case "export": self = .export
        default: return nil
        }
    }
}

enum WorkspaceRoute: Hashable, Sendable {
    case informationOverview
    case source(RadarSourceID)
    case sourcePage(RadarSourceID, WorkspaceDestination)
    case export

    static let initial = Self.informationOverview

    var sourceID: RadarSourceID? {
        switch self {
        case .source(let sourceID), .sourcePage(let sourceID, _): sourceID
        case .informationOverview, .export: nil
        }
    }

    var storageKey: String {
        switch self {
        case .informationOverview: "information-overview"
        case .source(let sourceID): "source:\(sourceID.rawValue)"
        case .sourcePage(let sourceID, let destination):
            "source:\(sourceID.rawValue):\(destination.storageKey)"
        case .export: "export"
        }
    }

    init(storageKey: String) {
        if storageKey == "information-overview" {
            self = .informationOverview
            return
        }
        if storageKey == "export" {
            self = .export
            return
        }
        let parts = storageKey.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[0] == "source" else {
            self = .initial
            return
        }
        let sourceID = RadarSourceID(rawValue: parts[1])
        if parts.count == 3, let destination = WorkspaceDestination(storageKey: parts[2]) {
            self = .sourcePage(sourceID, destination)
        } else {
            self = .source(sourceID)
        }
    }
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
    case quality = "IQ"
    case cost = "费用"
    case elapsed = "耗时"
    case agentSteps = "Agent steps"
    case cache = "Cache 命中率"
    case tokens = "总 Tokens"
}

enum TrendTimeRange: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case lastDay = "24 小时"
    case lastTwoDays = "48 小时"
    case lastSevenDays = "7 天"
    case lastThirtyDays = "30 天"

    var id: Self { self }
    fileprivate var interval: TimeInterval? {
        switch self {
        case .all: nil
        case .lastDay: 24 * 60 * 60
        case .lastTwoDays: 48 * 60 * 60
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
    let segmentIndex: Int
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

struct RadarDeclineSignal: Identifiable, Equatable, Sendable {
    let modelID: ModelID
    let modelName: String
    let currentIQ: Decimal
    let drop12Hours: Decimal
    let drop24Hours: Decimal
    let drop48Hours: Decimal?
    var id: ModelID { modelID }
}

struct CodexRenderedWarningPresentation: Equatable, Sendable {
    enum State: String, CaseIterable, Equatable, Sendable {
        case loading
        case freshCards = "fresh-cards"
        case freshEmpty = "fresh-empty"
        case staleLastKnownGood = "stale-last-known-good"
        case lastKnownGoodWithError = "last-known-good-with-error"
        case errorWithoutLastKnownGood = "error-without-last-known-good"
    }

    let state: State
    let cards: [CodexRenderedWarningCard]
    let sourceTimeLabel: String?
    let capturedAt: Date?
    let errorMessage: String?

    let attribution = CodexRadarConfiguration.descriptor.attributionText
    let sectionAccessibilityIdentifier = "codex-rendered-warning-section"
    let sourceTimeAccessibilityIdentifier = "codex-rendered-warning-source-time"
    let capturedAtAccessibilityIdentifier = "codex-rendered-warning-captured-at"

    init?(
        sourceID: RadarSourceID,
        state: SegmentState<CodexRenderedWarningSnapshot>?,
        history: [CodexRenderedWarningSnapshot]
    ) {
        guard sourceID == .codexRadar else { return nil }

        let snapshot: CodexRenderedWarningSnapshot?
        let presentationState: State
        if let error = state?.error {
            snapshot = state?.value ?? history.last
            presentationState = snapshot == nil ? .errorWithoutLastKnownGood : .lastKnownGoodWithError
            errorMessage = safe(error.message)
        } else if let current = state?.value {
            snapshot = current
            if state?.isStale == true {
                presentationState = .staleLastKnownGood
            } else {
                presentationState = current.cards.isEmpty ? .freshEmpty : .freshCards
            }
            errorMessage = nil
        } else if let lastKnownGood = history.last, state != nil {
            snapshot = lastKnownGood
            presentationState = .staleLastKnownGood
            errorMessage = nil
        } else {
            snapshot = nil
            presentationState = .loading
            errorMessage = nil
        }

        self.state = presentationState
        cards = snapshot?.cards ?? []
        sourceTimeLabel = snapshot?.sourceTimeLabel
        capturedAt = snapshot?.capturedAt
    }

    var stateMessage: String {
        switch state {
        case .loading: "正在读取 Codex Radar 官网降智预警"
        case .freshCards: "官网降智预警已更新"
        case .freshEmpty: "官网当前未显示降智预警"
        case .staleLastKnownGood: "正在显示可能已过期的最近有效官网数据"
        case .lastKnownGoodWithError: "官网预警刷新失败，正在显示最近有效数据"
        case .errorWithoutLastKnownGood: "官网预警暂不可用"
        }
    }

    var sectionAccessibilityLabel: String {
        "Codex Radar 官网降智预警，\(attribution)"
    }

    var stateAccessibilityIdentifier: String {
        "codex-rendered-warning-state-\(state.rawValue)"
    }

    var stateAccessibilityLabel: String {
        [stateMessage, errorMessage].compactMap { $0 }.joined(separator: "：")
    }

    var sourceTimeAccessibilityLabel: String {
        "官网时间：\(sourceTimeLabel ?? "暂无")"
    }

    var capturedAtAccessibilityLabel: String {
        "本地采集时间：\(capturedAt?.ISO8601Format() ?? "暂无")"
    }

    func cardAccessibilityIdentifier(_ card: CodexRenderedWarningCard) -> String {
        "codex-rendered-warning-card-\(card.sourceOrder)"
    }

    func cardAccessibilityLabel(_ card: CodexRenderedWarningCard) -> String {
        var parts = [
            stateAccessibilityLabel,
            card.displayName,
            "家族 \(card.family)",
            "推理强度 \(card.effort)",
            "IQ \(Self.metric(card.iq))",
            "24 小时下降 \(Self.metric(card.drop24h))",
        ]
        if let drop48h = card.drop48h {
            parts.append("48 小时下降 \(Self.metric(drop48h))")
        }
        if sourceTimeLabel != nil {
            parts.append(sourceTimeAccessibilityLabel)
        }
        if capturedAt != nil {
            parts.append(capturedAtAccessibilityLabel)
        }
        parts.append(attribution)
        return parts.joined(separator: "，")
    }

    private static func metric(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
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
    let renderedWarningPresentation: CodexRenderedWarningPresentation?

    init(
        sync: RadarSyncProjection?,
        lifecycle: RadarAppLifecycleState,
        supportLevel: SupportLevel,
        source: RadarSourceDescriptor = ClaudeRadarConfiguration.descriptor,
        renderedWarningState: SegmentState<CodexRenderedWarningSnapshot>? = nil,
        renderedWarningHistory: [CodexRenderedWarningSnapshot] = []
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

enum RadarDeclineAnalysis {
    private static let baselineTolerance: TimeInterval = 6 * 60 * 60
    private enum QualityResolution {
        case missing
        case value(Decimal)
        case conflict
    }

    static func signals(
        history: [BenchmarkDataset],
        sourceID: RadarSourceID,
        limit: Int = 4
    ) -> [RadarDeclineSignal] {
        guard limit > 0 else { return [] }
        let snapshots = history
            .filter { $0.sourceID == sourceID }
            .sorted { semanticTime($0) < semanticTime($1) }
        guard let latestDate = snapshots.last.map(semanticTime) else { return [] }
        let latestSnapshots = snapshots.filter { semanticTime($0) == latestDate }
        let revisions = Set(latestSnapshots.map(\.seriesRevision))
        guard revisions.count == 1, let latestRevision = revisions.first else { return [] }
        let revisionSnapshots = snapshots.filter { $0.seriesRevision == latestRevision }
        let currentIDs = Set(latestSnapshots.flatMap(\.models).map(\.id))

        return currentIDs.compactMap { modelID -> RadarDeclineSignal? in
            guard modelID.sourceID == sourceID else { return nil }
            guard case .value(let currentIQ) = qualityResolution(
                for: modelID,
                in: latestSnapshots
            ) else { return nil }
            let modelName = latestSnapshots
                .flatMap(\.models)
                .filter { $0.id == modelID }
                .map(\.descriptor.displayName)
                .min() ?? modelID.upstreamKey
            let groupedSnapshots = Dictionary(grouping: revisionSnapshots, by: semanticTime)
            var hasConflict = false
            let points = groupedSnapshots
                .compactMap { date, snapshots -> (Date, Decimal)? in
                    switch qualityResolution(for: modelID, in: snapshots) {
                    case .missing:
                        return nil
                    case .value(let quality):
                        return (date, quality)
                    case .conflict:
                        hasConflict = true
                        return nil
                    }
                }
                .sorted { $0.0 < $1.0 }
            guard !hasConflict,
                  points.count >= 3,
                  let twelveHourIQ = baseline(in: points, before: latestDate.addingTimeInterval(-12 * 60 * 60)),
                  let twentyFourHourIQ = baseline(in: points, before: latestDate.addingTimeInterval(-24 * 60 * 60))
            else { return nil }
            let drop12 = twelveHourIQ - currentIQ
            let drop24 = twentyFourHourIQ - currentIQ
            guard drop24 >= 2, drop12 > 0 else { return nil }
            let drop48 = baseline(
                in: points,
                before: latestDate.addingTimeInterval(-48 * 60 * 60)
            ).map { $0 - currentIQ }
            return .init(
                modelID: modelID,
                modelName: modelName,
                currentIQ: currentIQ,
                drop12Hours: drop12,
                drop24Hours: drop24,
                drop48Hours: drop48
            )
        }
        .sorted {
            if $0.drop24Hours != $1.drop24Hours { return $0.drop24Hours > $1.drop24Hours }
            if $0.drop12Hours != $1.drop12Hours { return $0.drop12Hours > $1.drop12Hours }
            let order = $0.modelName.localizedStandardCompare($1.modelName)
            return order == .orderedSame
                ? $0.modelID.upstreamKey < $1.modelID.upstreamKey
                : order == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func baseline(
        in points: [(Date, Decimal)],
        before cutoff: Date
    ) -> Decimal? {
        guard let point = points.last(where: { $0.0 <= cutoff }),
              cutoff.timeIntervalSince(point.0) <= baselineTolerance
        else { return nil }
        return point.1
    }

    private static func qualityResolution(
        for modelID: ModelID,
        in snapshots: [BenchmarkDataset]
    ) -> QualityResolution {
        let values: [Decimal?] = snapshots.map { snapshot in
            snapshot.models.first(where: { $0.id == modelID })?.qualityScore
        }
        guard values.contains(where: { $0 != nil }) else { return .missing }
        guard !values.contains(where: { $0 == nil }),
              Set(values).count == 1,
              let value = values[0]
        else { return .conflict }
        return .value(value)
    }

    private static func semanticTime(_ snapshot: BenchmarkDataset) -> Date {
        snapshot.sourceUpdatedAt ?? snapshot.fetchedAt
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
        [RadarSourceID.claudeCodeRadar, .codexRadar, .sweBenchVerified].compactMap { runtimes[$0]?.descriptor }
    }
    var projection: WorkspaceProjection {
        .init(
            sync: runtime.projection,
            lifecycle: runtime.lifecycleState,
            supportLevel: runtime.supportLevel,
            source: runtime.descriptor,
            renderedWarningState: runtime.renderedWarningProjection,
            renderedWarningHistory: runtime.renderedWarningHistory
        )
    }
    var history: [BenchmarkDataset] { runtime.benchmarkHistory }
    var refreshIntervalMinutes: Int { runtime.refreshIntervalMinutes }

    func projection(for sourceID: RadarSourceID) -> WorkspaceProjection? {
        guard let runtime = runtimes[sourceID] else { return nil }
        return .init(
            sync: runtime.projection,
            lifecycle: runtime.lifecycleState,
            supportLevel: runtime.supportLevel,
            source: runtime.descriptor,
            renderedWarningState: runtime.renderedWarningProjection,
            renderedWarningHistory: runtime.renderedWarningHistory
        )
    }

    func history(for sourceID: RadarSourceID) -> [BenchmarkDataset] {
        runtimes[sourceID]?.benchmarkHistory ?? []
    }

    func defaultDestination(for sourceID: RadarSourceID) -> WorkspaceDestination {
        sourceID == .sweBenchVerified ? .models : .overview
    }

    func destinations(for sourceID: RadarSourceID) -> [WorkspaceDestination] {
        if sourceID == .sweBenchVerified {
            var destinations: [WorkspaceDestination] = [.models]
            if hasComparableHistory(for: sourceID) { destinations.append(.trends) }
            destinations.append(.sourceStatus)
            return destinations
        }
        return [.overview, .decisionLens, .models, .trends, .sourceStatus]
    }

    func hasComparableHistory(for sourceID: RadarSourceID) -> Bool {
        Dictionary(grouping: history(for: sourceID), by: \.seriesRevision)
            .values
            .contains { $0.count >= 2 }
    }

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
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for runtime in runtimes.values {
                group.addTask { await runtime.refresh() }
            }
        }
    }
}
