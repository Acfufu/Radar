import Foundation

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

func state<T>(_ segment: SegmentState<T>?, lifecycle: RadarAppLifecycleState) -> WorkspaceState {
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

func safe(_ text: String) -> String {
    text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).prefix(160).description
}
