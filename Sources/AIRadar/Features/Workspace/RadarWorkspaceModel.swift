import Foundation
import Observation

@MainActor @Observable
final class RadarWorkspaceModel {
    private let runtimes: [RadarSourceID: RadarAppRuntime]
    private(set) var selectedStation: WorkspaceStation

    init(runtimes: [RadarSourceID: RadarAppRuntime], selectedSourceID: RadarSourceID) {
        self.runtimes = runtimes
        self.selectedStation = runtimes[selectedSourceID] != nil ? .source(selectedSourceID) : .aggregate
    }

    init(runtimes: [RadarSourceID: RadarAppRuntime], selectedStation: WorkspaceStation = .aggregate) {
        self.runtimes = runtimes
        if case .source(let sourceID) = selectedStation, runtimes[sourceID] == nil {
            self.selectedStation = .aggregate
        } else {
            self.selectedStation = selectedStation
        }
    }

    /// Currently selected station; real stations carry a runtime, the
    /// aggregate and upcoming placeholder stations do not (spec §4.1).
    var selectedSourceID: RadarSourceID? {
        if case .source(let sourceID) = selectedStation { return sourceID }
        return nil
    }

    func selectSource(_ station: WorkspaceStation) {
        guard station.isRealSource || station == .aggregate || station.isWhitelistStation || station != selectedStation else { return }
        if case .source(let sourceID) = station, runtimes[sourceID] == nil { return }
        selectedStation = station
    }

    /// Runtime for the selected station, nil on aggregate/upcoming stations.
    var runtime: RadarAppRuntime? {
        if case .source(let sourceID) = selectedStation { return runtimes[sourceID] }
        return nil
    }
    func runtime(for sourceID: RadarSourceID) -> RadarAppRuntime? { runtimes[sourceID] }
    var source: RadarSourceDescriptor? { runtime?.descriptor }
    var sources: [RadarSourceDescriptor] {
        WorkspaceStation.realSources.compactMap { runtimes[$0]?.descriptor }
    }
    var projection: WorkspaceProjection? {
        guard let runtime else { return nil }
        return .init(
            sync: runtime.projection,
            lifecycle: runtime.lifecycleState,
            supportLevel: runtime.supportLevel,
            source: runtime.descriptor,
            renderedWarningState: runtime.renderedWarningProjection,
            renderedWarningHistory: runtime.renderedWarningHistory,
            stationStatus: runtime.sourceID == .codexRadar ? runtime.stationStatus : nil,
            intelligenceEfficiencyDataset: runtime.sourceID == .codexRadar ? runtime.intelligenceEfficiencyState?.value : nil,
            radarInsightsDataset: runtime.sourceID == .codexRadar ? runtime.radarInsightsState?.value : nil,
            visualSpatialReasoningDataset: runtime.sourceID == .codexRadar ? runtime.visualSpatialReasoningState?.value : nil,
            fastRadarDataset: runtime.sourceID == .codexRadar ? runtime.fastRadarHistoryState?.value : nil
        )
    }
    var history: [BenchmarkDataset] { runtime?.benchmarkHistory ?? [] }
    var refreshIntervalMinutes: Int { runtime?.refreshIntervalMinutes ?? 30 }

    var stationDisplayName: String {
        switch selectedStation {
        case .aggregate: "聚合站"
        case .whitelist(let station): station.displayName
        case .upcoming(let station): station.displayName
        case .source(let sourceID): runtime(for: sourceID)?.descriptor.displayName ?? sourceID.rawValue
        }
    }

    /// CommandMenu/toolbar refresh availability per station semantics:
    /// real station -> its support level; aggregate -> any real station
    /// enabled; whitelist view station -> the shared Codex sidecar's
    /// availability (same dataset, same refresh); upcoming -> disabled.
    var refreshAvailable: Bool {
        if case .aggregate = selectedStation {
            return sources.contains { RefreshActionAvailability.isEnabled(supportLevel: $0.supportLevel) }
        }
        if case .whitelist = selectedStation {
            guard let codexRuntime = runtime(for: .codexRadar) else { return false }
            return RefreshActionAvailability.isEnabled(supportLevel: codexRuntime.supportLevel)
        }
        guard let runtime else { return false }
        return RefreshActionAvailability.isEnabled(supportLevel: runtime.supportLevel)
    }

    /// Last-resort projection for views that require a value (menu bar
    /// summary). Built from the first available runtime.
    var anyProjection: WorkspaceProjection? {
        fallbackProjection ?? (fallbackRuntime.map { runtime in
            WorkspaceProjection(
                sync: runtime.projection,
                lifecycle: runtime.lifecycleState,
                supportLevel: runtime.supportLevel,
                source: runtime.descriptor,
                renderedWarningState: runtime.renderedWarningProjection,
                renderedWarningHistory: runtime.renderedWarningHistory,
                    stationStatus: runtime.sourceID == .codexRadar ? runtime.stationStatus : nil,
                intelligenceEfficiencyDataset: runtime.sourceID == .codexRadar ? runtime.intelligenceEfficiencyState?.value : nil,
                radarInsightsDataset: runtime.sourceID == .codexRadar ? runtime.radarInsightsState?.value : nil,
                visualSpatialReasoningDataset: runtime.sourceID == .codexRadar ? runtime.visualSpatialReasoningState?.value : nil,
                fastRadarDataset: runtime.sourceID == .codexRadar ? runtime.fastRadarHistoryState?.value : nil
            )
        })
    }

    var fallbackRuntime: RadarAppRuntime? {
        for sourceID in WorkspaceStation.realSources {
            if let runtime = runtime(for: sourceID) { return runtime }
        }
        return nil
    }

    var fallbackProjection: WorkspaceProjection? {
        for sourceID in WorkspaceStation.realSources {
            if let projection = projection(for: sourceID) { return projection }
        }
        return nil
    }

    func projection(for sourceID: RadarSourceID) -> WorkspaceProjection? {
        guard let runtime = runtimes[sourceID] else { return nil }
        return .init(
            sync: runtime.projection,
            lifecycle: runtime.lifecycleState,
            supportLevel: runtime.supportLevel,
            source: runtime.descriptor,
            renderedWarningState: runtime.renderedWarningProjection,
            renderedWarningHistory: runtime.renderedWarningHistory,
            stationStatus: sourceID == .codexRadar ? runtime.stationStatus : nil,
            intelligenceEfficiencyDataset: sourceID == .codexRadar ? runtime.intelligenceEfficiencyState?.value : nil,
            radarInsightsDataset: sourceID == .codexRadar ? runtime.radarInsightsState?.value : nil,
            visualSpatialReasoningDataset: sourceID == .codexRadar ? runtime.visualSpatialReasoningState?.value : nil,
            fastRadarDataset: sourceID == .codexRadar ? runtime.fastRadarHistoryState?.value : nil
        )
    }

    /// Whitelist view stations follow the shared Codex sidecar freshness
    /// (spec §4.1): the status dot maps the Codex runtime's intelligence-
    /// efficiency state, not a station-local runtime (there is none).
    func whitelistStatusLevel(for station: WhitelistStation) -> StationStatusLevel {
        guard let codexRuntime = runtime(for: .codexRadar),
              let state = codexRuntime.intelligenceEfficiencyState else { return .muted }
        if state.error != nil { return .error }
        if state.value == nil { return .muted }
        return state.isStale ? .stale : .fresh
    }

    func history(for sourceID: RadarSourceID) -> [BenchmarkDataset] {
        runtimes[sourceID]?.benchmarkHistory ?? []
    }

    func defaultDestination(for sourceID: RadarSourceID) -> WorkspaceDestination {
        sourceID == .sweBenchVerified ? .models : .overview
    }

    func destinations(for sourceID: RadarSourceID) -> [WorkspaceDestination] {
        WorkspaceDestination.destinations(for: sourceID, hasComparableHistory: hasComparableHistory(for: sourceID))
    }

    func hasComparableHistory(for sourceID: RadarSourceID) -> Bool {
        Dictionary(grouping: history(for: sourceID), by: \.seriesRevision)
            .values
            .contains { $0.count >= 2 }
    }

    func selectSource(_ sourceID: RadarSourceID) {
        guard runtimes[sourceID] != nil else { return }
        selectedStation = .source(sourceID)
    }

    func normalizedRoute(_ route: WorkspaceRoute) -> WorkspaceRoute {
        switch route {
        case .informationOverview:
            .informationOverview
        case .whitelist(let station):
            .whitelist(station)
        case .whitelistPage(let station, let destination):
            destination == .efficiencyRanking ? .whitelistPage(station, destination) : .whitelist(station)
        case .upcoming(let station):
            .upcoming(station)
        case .export:
            if let sourceID = selectedSourceID {
                .sourcePage(sourceID, .export)
            } else {
                .informationOverview
            }
        case .source(let sourceID):
            runtimes[sourceID] == nil ? fallbackSourceRoute : route
        case .sourcePage(let sourceID, let destination):
            runtimes[sourceID] == nil
                ? fallbackSourceRoute
                : destinations(for: sourceID).contains(destination) ? route : .source(sourceID)
        }
    }

    private var fallbackSourceRoute: WorkspaceRoute {
        if let sourceID = selectedSourceID, runtimes[sourceID] != nil {
            return .source(sourceID)
        }
        return .informationOverview
    }

    func restoreRoute(_ route: WorkspaceRoute) -> WorkspaceRoute {
        let route = normalizedRoute(route)
        if let sourceID = route.sourceID { selectSource(sourceID) }
        return route
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
    func refresh() async {
        // Aggregate station refreshes all real stations; whitelist view
        // stations refresh the shared Codex runtime (the intelligence-
        // efficiency sidecar is the same dataset — same refresh, same
        // effect, spec §4.1); Kimi placeholder is never synchronized.
        if case .aggregate = selectedStation {
            await refreshAll()
            return
        }
        if case .whitelist = selectedStation {
            await runtime(for: .codexRadar)?.refresh()
            return
        }
        await runtime?.refresh()
    }
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for runtime in runtimes.values {
                group.addTask { await runtime.refresh() }
            }
        }
    }
    func updateRefreshInterval(minutes: Int) async {
        for runtime in runtimes.values {
            await runtime.updateRefreshInterval(minutes: minutes)
        }
    }
}
