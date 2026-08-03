import Foundation
import Observation

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
    func runtime(for sourceID: RadarSourceID) -> RadarAppRuntime? { runtimes[sourceID] }
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
            renderedWarningHistory: runtime.renderedWarningHistory,
            renderedIQHistoryState: runtime.renderedIQHistoryProjection
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
            renderedWarningHistory: runtime.renderedWarningHistory,
            renderedIQHistoryState: runtime.renderedIQHistoryProjection
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
        selectedSourceID = sourceID
    }

    func normalizedRoute(_ route: WorkspaceRoute) -> WorkspaceRoute {
        return switch route {
        case .informationOverview:
            .informationOverview
        case .export:
            .sourcePage(selectedSourceID, .export)
        case .source(let sourceID):
            runtimes[sourceID] == nil ? .source(selectedSourceID) : route
        case .sourcePage(let sourceID, let destination):
            runtimes[sourceID] == nil
                ? .source(selectedSourceID)
                : destinations(for: sourceID).contains(destination) ? route : .source(sourceID)
        }
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
    func refresh() async { await runtime.refresh() }
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
