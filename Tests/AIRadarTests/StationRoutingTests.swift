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
        // v1.1 (ADR-0003): DSH/ZCode/Grok elevated in place — raw values
        // unchanged, now whitelist view stations; Kimi stays the only
        // upcoming station.
        #expect(WorkspaceStation.whitelist(.dsh).rawValue == "dsh")
        #expect(WorkspaceStation(rawValue: "codex-radar") == .source(.codexRadar))
        #expect(WorkspaceStation(rawValue: "aggregate") == .aggregate)
        #expect(WorkspaceStation(rawValue: "kimi") == .upcoming(.kimi))
        #expect(WorkspaceStation(rawValue: "dsh") == .whitelist(.dsh))
        #expect(WorkspaceStation(rawValue: "zcode") == .whitelist(.zcode))
        #expect(WorkspaceStation(rawValue: "grok") == .whitelist(.grok))
        #expect(UpcomingStation.allCases.map(\.rawValue) == ["kimi"])
        #expect(WhitelistStation.allCases.map(\.rawValue) == ["dsh", "zcode", "grok"])
    }

    @Test("storage keys keep the source: prefix and restore round-trips")
    func storageKeyRoundTrip() {
        #expect(WorkspaceRoute.storageKey(for: .aggregate) == "information-overview")
        #expect(WorkspaceRoute.storageKey(for: .source(.codexRadar)) == "source:codex-radar")
        // Persisted pre-elevation keys keep their shape and now resolve to
        // the whitelist station.
        #expect(WorkspaceRoute.storageKey(for: .whitelist(.zcode)) == "source:zcode")
        #expect(WorkspaceRoute(storageKey: "source:zcode") == .whitelist(.zcode))
        #expect(WorkspaceRoute(storageKey: "source:dsh:efficiency-ranking") == .whitelist(.dsh))
        #expect(WorkspaceRoute(storageKey: "source:kimi") == .upcoming(.kimi))
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
        #expect(model.normalizedRoute(.upcoming(.kimi)) == .upcoming(.kimi))
        #expect(model.normalizedRoute(.whitelist(.dsh)) == .whitelist(.dsh))
        #expect(model.normalizedRoute(.whitelistPage(.dsh, .efficiencyRanking)) == .whitelistPage(.dsh, .efficiencyRanking))
        #expect(model.normalizedRoute(.whitelistPage(.dsh, .overview)) == .whitelist(.dsh))
        #expect(model.normalizedRoute(.export) == .informationOverview)
    }

    @Test("kimi placeholder selection is accepted and routes to its placeholder")
    func placeholderStationRouting() {
        let model = RadarWorkspaceModel(runtimes: [:], selectedStation: .upcoming(.kimi))
        #expect(model.selectedStation == .upcoming(.kimi))
        #expect(model.stationDisplayName == "Kimi 站")
        #expect(!model.refreshAvailable)
        model.selectSource(.upcoming(.kimi))
        #expect(model.selectedStation == .upcoming(.kimi))
    }

    @Test("whitelist stations accept selection without a runtime and follow the shared sidecar for refresh")
    func whitelistStationSemantics() {
        let environment = makeEnvironment()
        let runtimes = [
            RadarSourceID.codexRadar: RadarAppRuntime(environment: environment, sourceID: .codexRadar),
        ]
        let model = RadarWorkspaceModel(runtimes: runtimes, selectedStation: .whitelist(.dsh))
        #expect(model.selectedStation == .whitelist(.dsh))
        #expect(model.stationDisplayName == "DSH 站")
        #expect(model.selectedSourceID == nil)
        #expect(model.runtime == nil)
        // Refresh availability follows the shared Codex runtime's support
        // level (ui fixture: synchronization disabled → unavailable).
        #expect(model.refreshAvailable == false)
        model.selectSource(.whitelist(.zcode))
        #expect(model.selectedStation == .whitelist(.zcode))
        model.selectSource(.upcoming(.kimi))
        #expect(model.selectedStation == .upcoming(.kimi))
    }

    @Test("RADAR_UI_SOURCE value domain: whitelist direct values, upcoming-kimi only")
    func debugStationValueDomain() {
        // v1.1 elevation: dsh/zcode/grok are direct values; the upcoming-
        // prefix survives only for kimi (spec §4.1 naming conventions).
        #expect(AppEnvironment.debugInitialStation(variables: ["RADAR_UI_SOURCE": "dsh"]) == .whitelist(.dsh))
        #expect(AppEnvironment.debugInitialStation(variables: ["RADAR_UI_SOURCE": "zcode"]) == .whitelist(.zcode))
        #expect(AppEnvironment.debugInitialStation(variables: ["RADAR_UI_SOURCE": "grok"]) == .whitelist(.grok))
        #expect(AppEnvironment.debugInitialStation(variables: ["RADAR_UI_SOURCE": "upcoming-kimi"]) == .upcoming(.kimi))
        #expect(AppEnvironment.debugInitialStation(variables: ["RADAR_UI_SOURCE": "aggregate"]) == .aggregate)
        // Retired `upcoming-dsh` style values fall through to the default
        // real source (malformed value semantics unchanged).
        #expect(AppEnvironment.debugInitialStation(variables: ["RADAR_UI_SOURCE": "upcoming-dsh"]) == .source(.claudeCodeRadar))
    }

    @Test("whitelist model sets match the 2026-09-20 upstream station-config probe")
    func whitelistFrozenValues() {
        #expect(WhitelistStation.dsh.modelWhitelist == ["dsh-deepseek-v4-flash", "dsh-deepseek-v4-pro"])
        #expect(WhitelistStation.zcode.modelWhitelist == ["glm-5.3"])
        #expect(WhitelistStation.grok.modelWhitelist == ["grok-4.6"])
        // The aggregate comparison union covers exactly the four real
        // stations; data-plane-only models (kimi-k2.8-preview etc.) stay out.
        #expect(WhitelistStation.aggregateComparisonModels.contains("gpt-6-astra"))
        #expect(WhitelistStation.aggregateComparisonModels.contains("glm-5.3"))
        #expect(!WhitelistStation.aggregateComparisonModels.contains("kimi-k2.8-preview"))
        #expect(!WhitelistStation.aggregateComparisonModels.contains("dsh-deepseek-v4.1-flash"))
        #expect(WhitelistStation.comparisonSourceLabel(for: "gpt-5.6-sol") == "Codex")
        #expect(WhitelistStation.comparisonSourceLabel(for: "dsh-deepseek-v4-pro") == "DSH")
        #expect(WhitelistStation.comparisonSourceLabel(for: "glm-5.3") == "ZCode")
        #expect(WhitelistStation.comparisonSourceLabel(for: "grok-4.6") == "Grok")
        #expect(WhitelistStation.comparisonSourceLabel(for: "kimi-k2.8-preview") == "—")
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
        model.selectSource(.whitelist(.dsh))
        #expect(model.selectedStation == .whitelist(.dsh))
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
        let previewIndex = try #require(view.range(of: "Section(\"预览站\")")?.lowerBound)
        let upcomingIndex = try #require(view.range(of: "Section(\"即将开放\")")?.lowerBound)
        #expect(aggregateIndex < sourcesIndex)
        #expect(sourcesIndex < previewIndex)
        #expect(previewIndex < upcomingIndex)
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
