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
        guard station.isRealSource || station == .aggregate || station != selectedStation else { return }
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
            renderedIQHistoryState: runtime.renderedIQHistoryProjection,
            stationStatus: runtime.sourceID == .codexRadar ? runtime.stationStatus : nil
        )
    }
    var history: [BenchmarkDataset] { runtime?.benchmarkHistory ?? [] }
    var refreshIntervalMinutes: Int { runtime?.refreshIntervalMinutes ?? 30 }

    var stationDisplayName: String {
        switch selectedStation {
        case .aggregate: "聚合站"
        case .upcoming(let station): station.displayName
        case .source(let sourceID): runtime(for: sourceID)?.descriptor.displayName ?? sourceID.rawValue
        }
    }

    /// CommandMenu/toolbar refresh availability per station semantics:
    /// real station -> its support level; aggregate -> any real station
    /// enabled; upcoming -> disabled.
    var refreshAvailable: Bool {
        if case .aggregate = selectedStation {
            return sources.contains { RefreshActionAvailability.isEnabled(supportLevel: $0.supportLevel) }
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
                renderedIQHistoryState: runtime.renderedIQHistoryProjection,
                stationStatus: runtime.sourceID == .codexRadar ? runtime.stationStatus : nil
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
            renderedIQHistoryState: runtime.renderedIQHistoryProjection,
            stationStatus: sourceID == .codexRadar ? runtime.stationStatus : nil
        )
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
        // Aggregate station refreshes all real stations; placeholder
        // stations are never synchronized (spec D10 / §4.1).
        if case .aggregate = selectedStation {
            await refreshAll()
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
