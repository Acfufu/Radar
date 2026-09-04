import Foundation

enum CodexHistoryMetric: String, CaseIterable, Sendable {
    case iq
    case averageFeePerValidTask
    case averageMinutesPerValidTask
    case agentSteps
    case cacheHitPercent
    case totalTokens

    static let `default`: Self = .iq

    var title: String {
        switch self {
        case .iq: "IQ"
        case .averageFeePerValidTask: "平均费用 / 有效任务"
        case .averageMinutesPerValidTask: "平均分钟 / 有效任务"
        case .agentSteps: "Agent steps"
        case .cacheHitPercent: "缓存命中率"
        case .totalTokens: "总 tokens"
        }
    }
}

enum CodexHistoryBaseline: Int, CaseIterable, Sendable {
    case hours4 = 4
    case hours12 = 12
    case hours24 = 24

    static let `default`: Self = .hours24
    var interval: TimeInterval { TimeInterval(rawValue * 60 * 60) }
    var title: String { "\(rawValue)h" }
}

struct CodexHistoryValues: Equatable, Sendable {
    let current: Double?
    let baseline: Double?
    let delta: Double?

    init(current: Double?, baseline: Double?, delta: Double? = nil) {
        self.current = current
        self.baseline = baseline
        self.delta = delta ?? current.flatMap { current in baseline.map { current - $0 } }
    }
}

struct CodexHistoryComparisonRow: Identifiable, Equatable, Sendable {
    let modelID: ModelID
    let modelName: String
    let values: CodexHistoryValues

    var id: ModelID { modelID }
    var current: Double? { values.current }
    var baseline: Double? { values.baseline }
    var delta: Double? { values.delta }
}

enum CodexHistoryComparison {
    private static let baselineTolerance: TimeInterval = 6 * 60 * 60

    static func project(
        current: BenchmarkDataset,
        history: some Sequence<BenchmarkDataset>,
        metric: CodexHistoryMetric = .default,
        baseline: CodexHistoryBaseline = .default
    ) -> [CodexHistoryComparisonRow] {
        guard current.sourceID == .codexRadar else { return [] }
        let currentTime = semanticTime(current)
        let snapshots = (Array(history) + [current]).filter {
            $0.sourceID == current.sourceID && $0.seriesRevision == current.seriesRevision
        }
        let currentSnapshots = snapshots.filter { semanticTime($0) == currentTime }
        let currentIDs = Set(current.models.lazy.map(\.id).filter { $0.sourceID == current.sourceID })
        let cutoff = currentTime.addingTimeInterval(-baseline.interval)

        return currentIDs.map { modelID in
            let names = currentSnapshots
                .flatMap(\.models)
                .filter { $0.id == modelID }
                .map(\.descriptor.displayName)
            let currentValue = resolution(for: modelID, metric: metric, in: currentSnapshots).value
            let baselineValue = baselineValue(
                for: modelID,
                metric: metric,
                snapshots: snapshots.filter { semanticTime($0) < currentTime },
                cutoff: cutoff
            )
            return .init(
                modelID: modelID,
                modelName: names.min() ?? modelID.upstreamKey,
                values: .init(current: currentValue, baseline: baselineValue)
            )
        }
        .sorted(by: rowOrder)
    }

    private static func baselineValue(
        for modelID: ModelID,
        metric: CodexHistoryMetric,
        snapshots: [BenchmarkDataset],
        cutoff: Date
    ) -> Double? {
        let groups = Dictionary(grouping: snapshots, by: semanticTime)
        let resolutions = groups.map { (date: $0.key, resolution: resolution(for: modelID, metric: metric, in: $0.value)) }
        guard !resolutions.contains(where: { $0.resolution == .conflict }) else { return nil }
        return resolutions
            .compactMap { item -> (Date, Double)? in
                guard item.date <= cutoff,
                      cutoff.timeIntervalSince(item.date) <= baselineTolerance,
                      case .value(let value) = item.resolution
                else { return nil }
                return (item.date, value)
            }
            .max { $0.0 < $1.0 }?
            .1
    }

    private static func resolution(
        for modelID: ModelID,
        metric: CodexHistoryMetric,
        in snapshots: [BenchmarkDataset]
    ) -> MetricResolution {
        let values = snapshots.map { snapshot in
            snapshot.models.first(where: { $0.id == modelID }).flatMap { value($0, metric) }
        }
        guard values.contains(where: { $0 != nil }) else { return .missing }
        guard !values.contains(where: { $0 == nil }),
              Set(values.compactMap { $0 }).count == 1,
              let value = values[0]
        else { return .conflict }
        return .value(value)
    }

    fileprivate static func value(_ model: ModelBenchmark, _ metric: CodexHistoryMetric) -> Double? {
        let value: Double? = switch metric {
        case .iq:
            model.qualityScore.map(decimal)
        case .averageFeePerValidTask:
            validTasks(model).flatMap { valid in model.benchmarkCostUSD.map { decimal($0) / valid } }
        case .averageMinutesPerValidTask:
            validTasks(model).flatMap { valid in model.elapsedSeconds.map { $0 / 60 / valid } }
        case .agentSteps:
            model.agentSteps.map(Double.init)
        case .cacheHitPercent:
            model.cacheHitPercent.map(decimal)
        case .totalTokens:
            model.totalTokens.map(Double.init)
        }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func validTasks(_ model: ModelBenchmark) -> Double? {
        model.validTasks.flatMap { $0 > 0 ? Double($0) : nil }
    }

    private static func decimal(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static func semanticTime(_ snapshot: BenchmarkDataset) -> Date {
        snapshot.sourceUpdatedAt ?? snapshot.fetchedAt
    }

    private static func rowOrder(_ lhs: CodexHistoryComparisonRow, _ rhs: CodexHistoryComparisonRow) -> Bool {
        let order = lhs.modelName.localizedStandardCompare(rhs.modelName)
        return order == .orderedSame
            ? lhs.modelID.upstreamKey < rhs.modelID.upstreamKey
            : order == .orderedAscending
    }

    private enum MetricResolution: Equatable {
        case missing
        case value(Double)
        case conflict

        var value: Double? {
            if case .value(let value) = self { value } else { nil }
        }
    }
}

struct CodexHistorySelectionState: Equatable, Sendable {
    var selected: Set<ModelID> = []
    var isExplicit = false
}

enum CodexHistorySelection {
    static let limit = 4

    static func reconcile(
        state: CodexHistorySelectionState,
        current: BenchmarkDataset
    ) -> CodexHistorySelectionState {
        let available = availableModels(current)
        let availableIDs = Set(available.map(\.id))
        guard state.isExplicit else {
            return .init(selected: defaultSelection(available), isExplicit: false)
        }
        return .init(selected: state.selected.intersection(availableIDs), isExplicit: true)
    }

    static func userChanged(
        _ selected: Set<ModelID>,
        current: BenchmarkDataset
    ) -> CodexHistorySelectionState {
        let available = availableModels(current)
        let requested = selected.intersection(available.map(\.id))
        let capped = available.lazy.map(\.id).filter(requested.contains).prefix(limit)
        return .init(selected: Set(capped), isExplicit: true)
    }

    static func setting(
        _ modelID: ModelID,
        selected: Bool,
        state: CodexHistorySelectionState,
        current: BenchmarkDataset
    ) -> CodexHistorySelectionState {
        var explicit = state.selected
        if selected {
            guard canSelect(modelID, state: state, current: current) else {
                return .init(selected: explicit, isExplicit: true)
            }
            explicit.insert(modelID)
        } else {
            explicit.remove(modelID)
        }
        return userChanged(explicit, current: current)
    }

    static func canSelect(
        _ modelID: ModelID,
        state: CodexHistorySelectionState,
        current: BenchmarkDataset
    ) -> Bool {
        let available = Set(availableModels(current).map(\.id))
        return available.contains(modelID) && (state.selected.contains(modelID) || state.selected.count < limit)
    }

    private static func defaultSelection(_ models: [ModelBenchmark]) -> Set<ModelID> {
        let preferred = RadarModelIdentity.canonicalFamilies
        let grouped = Dictionary(grouping: models) {
            RadarModelIdentity.family(id: $0.id, displayName: $0.descriptor.displayName)
        }
        let representatives = preferred.compactMap { family in
            grouped[family]?
                .filter { CodexHistoryComparison.value($0, .iq) != nil }
                .sorted(by: defaultOrder)
                .first
        }
        return Set(representatives.prefix(limit).map(\.id))
    }

    private static func availableModels(_ current: BenchmarkDataset) -> [ModelBenchmark] {
        guard current.sourceID == .codexRadar else { return [] }
        return Dictionary(grouping: current.models.filter { $0.id.sourceID == current.sourceID }, by: \.id)
            .values
            .compactMap { $0.sorted(by: stableOrder).first }
            .sorted(by: stableOrder)
    }

    private static func defaultOrder(_ lhs: ModelBenchmark, _ rhs: ModelBenchmark) -> Bool {
        let lhsIQ = CodexHistoryComparison.value(lhs, .iq)!
        let rhsIQ = CodexHistoryComparison.value(rhs, .iq)!
        if lhsIQ != rhsIQ { return lhsIQ > rhsIQ }
        return stableOrder(lhs, rhs)
    }

    private static func stableOrder(_ lhs: ModelBenchmark, _ rhs: ModelBenchmark) -> Bool {
        let order = lhs.descriptor.displayName.localizedStandardCompare(rhs.descriptor.displayName)
        return order == .orderedSame
            ? lhs.id.upstreamKey < rhs.id.upstreamKey
            : order == .orderedAscending
    }
}
