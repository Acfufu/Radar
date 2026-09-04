import Foundation
import Testing
@testable import AIRadar

/// P1a station-model contract tests (spec §4.1): naming conventions,
/// persisted-key compatibility, station selection bypass, and refresh
/// semantics for aggregate/placeholder stations.
@Suite("StationRoutingTests")
@MainActor
struct StationRoutingTests {
    private func makeEnvironment() -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-StationRouting-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
    }

    @Test("real stations reuse RadarSourceID raw values and upcoming stations are distinct")
    func stationRawValues() {
        #expect(WorkspaceStation.source(.claudeCodeRadar).rawValue == "claude-code-radar")
        #expect(WorkspaceStation.source(.codexRadar).rawValue == "codex-radar")
        #expect(WorkspaceStation.source(.sweBenchVerified).rawValue == "swe-bench-verified")
        #expect(WorkspaceStation.aggregate.rawValue == "aggregate")
        #expect(WorkspaceStation.upcoming(.dsh).rawValue == "dsh")
        #expect(WorkspaceStation(rawValue: "codex-radar") == .source(.codexRadar))
        #expect(WorkspaceStation(rawValue: "aggregate") == .aggregate)
        #expect(WorkspaceStation(rawValue: "kimi") == .upcoming(.kimi))
        #expect(UpcomingStation.allCases.map(\.rawValue) == ["dsh", "zcode", "grok", "kimi"])
    }

    @Test("storage keys keep the source: prefix and restore round-trips")
    func storageKeyRoundTrip() {
        #expect(WorkspaceRoute.storageKey(for: .aggregate) == "information-overview")
        #expect(WorkspaceRoute.storageKey(for: .source(.codexRadar)) == "source:codex-radar")
        #expect(WorkspaceRoute.storageKey(for: .upcoming(.zcode)) == "source:zcode")
        #expect(WorkspaceRoute(storageKey: "source:zcode") == .upcoming(.zcode))
        #expect(WorkspaceRoute(storageKey: "source:aggregate") == .upcoming(.dsh) ? false : true)
        // Legacy persisted keys keep their meaning.
        #expect(WorkspaceRoute(storageKey: "information-overview") == .informationOverview)
        #expect(WorkspaceRoute(storageKey: "source:codex-radar:overview") == .sourcePage(.codexRadar, .overview))
        // Malformed keys fall back to the initial route.
        #expect(WorkspaceRoute(storageKey: "garbage") == .initial)
    }

    @Test("aggregate station has no runtime and never synchronizes")
    func aggregateStationBypass() async {
        let model = RadarWorkspaceModel(runtimes: [:], selectedStation: .aggregate)
        #expect(model.selectedSourceID == nil)
        #expect(model.runtime == nil)
        #expect(model.stationDisplayName == "聚合站")
        #expect(!model.refreshAvailable)
        await model.refresh() // must not crash
        #expect(model.normalizedRoute(.upcoming(.dsh)) == .upcoming(.dsh))
        #expect(model.normalizedRoute(.export) == .informationOverview)
    }

    @Test("placeholder station selection is accepted and routes to its placeholder")
    func placeholderStationRouting() {
        let model = RadarWorkspaceModel(runtimes: [:], selectedStation: .upcoming(.grok))
        #expect(model.selectedStation == .upcoming(.grok))
        #expect(model.stationDisplayName == "Grok 站")
        #expect(!model.refreshAvailable)
        model.selectSource(.upcoming(.kimi))
        #expect(model.selectedStation == .upcoming(.kimi))
    }

    @Test("unknown real station selection falls back to aggregate")
    func unknownSourceFallsBack() {
        let model = RadarWorkspaceModel(
            runtimes: [:],
            selectedStation: .source(RadarSourceID(rawValue: "codex-radar"))
        )
        #expect(model.selectedStation == .aggregate)
    }

    @Test("real station keeps runtime and refresh availability follows support level")
    func realStationSemantics() {
        let environment = makeEnvironment()
        let runtimes = [
            RadarSourceID.claudeCodeRadar: RadarAppRuntime(environment: environment, sourceID: .claudeCodeRadar),
        ]
        let model = RadarWorkspaceModel(runtimes: runtimes, selectedSourceID: .claudeCodeRadar)
        #expect(model.selectedSourceID == .claudeCodeRadar)
        #expect(model.runtime === runtimes[RadarSourceID.claudeCodeRadar])
        #expect(model.refreshAvailable == false) // ui fixture: synchronization disabled
        // Selecting a station without a runtime is a no-op.
        model.selectSource(.source(.codexRadar))
        #expect(model.selectedSourceID == .claudeCodeRadar)
        model.selectSource(.upcoming(.dsh))
        #expect(model.selectedStation == .upcoming(.dsh))
        #expect(model.runtime == nil)
    }

@Test("sidebar declares the fixed three-section order (spec §4.1)")
    func sidebarSectionOrder() throws {
        let view = try String(
            contentsOf: URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/AIRadar/Features/Workspace/RadarWorkspaceView.swift"),
            encoding: .utf8
        )
        let aggregateIndex = try #require(view.range(of: "Label(\"聚合站\"")?.lowerBound)
        let sourcesIndex = try #require(view.range(of: "Section(\"来源\")")?.lowerBound)
        let upcomingIndex = try #require(view.range(of: "Section(\"即将开放\")")?.lowerBound)
        #expect(aggregateIndex < sourcesIndex)
        #expect(sourcesIndex < upcomingIndex)
        // Placeholder card copy: main phrase + station-name subtitle.
        #expect(view.contains("即将开放"))
        #expect(view.contains("station.displayName"))
    }

    @Test("status dot mapping covers the WorkspaceState spectrum")
    func statusDotMapping() {
        #expect(StationStatusLevel.map(.fresh) == .fresh)
        #expect(StationStatusLevel.map(.stale) == .stale)
        #expect(StationStatusLevel.map(.usingLastKnownGood) == .stale)
        #expect(StationStatusLevel.map(.validationFailed(hasLastKnownGood: true)) == .stale)
        #expect(StationStatusLevel.map(.error("x")) == .error)
        #expect(StationStatusLevel.map(.loading) == .muted)
        #expect(StationStatusLevel.map(.empty) == .muted)
        #expect(StationStatusLevel.map(.unavailable("x")) == .muted)
        #expect(StationStatusLevel.map(.disabled("x")) == .muted)
    }

    @Test("aggregate station has no export destination (spec D10)")
    func aggregateHasNoExport() {
        let model = RadarWorkspaceModel(runtimes: [:], selectedStation: .aggregate)
        #expect(model.normalizedRoute(.export) == .informationOverview)
        #expect(model.stationDisplayName == "聚合站")
    }
}
