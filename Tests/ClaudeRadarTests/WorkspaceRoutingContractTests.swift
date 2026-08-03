import Foundation
import Testing
@testable import ClaudeRadar

@Suite("WorkspaceRoutingContractTests")
struct WorkspaceRoutingContractTests {
    @MainActor
    @Test("source capabilities use the approved destination matrix")
    func sourceCapabilityMatrix() {
        // Given
        let model = workspaceModel()

        // When / Then
        #expect(model.defaultDestination(for: .claudeCodeRadar) == .overview)
        #expect(model.defaultDestination(for: .codexRadar) == .overview)
        #expect(model.defaultDestination(for: .sweBenchVerified) == .models)
        #expect(model.destinations(for: .claudeCodeRadar) == [.overview, .decisionLens, .models, .trends, .sourceStatus, .export])
        #expect(model.destinations(for: .codexRadar) == [.overview, .decisionLens, .models, .trends, .intelligenceCenter, .sourceStatus, .export])
        #expect(model.destinations(for: .sweBenchVerified) == [.models, .sourceStatus, .export])
    }

    #if DEBUG
    @MainActor
    @Test("runtime exposes SWE trends for same-revision history")
    func sweBenchSameRevisionHistoryExposesTrends() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Radar-SWE-Trends-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstCapture = Date(timeIntervalSince1970: 2_000_000_000)
        let seedEnvironment = AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try seedEnvironment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .sweBenchVerified,
            state: "fresh",
            now: firstCapture
        )
        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .sweBenchVerified,
            state: "fresh",
            now: firstCapture.addingTimeInterval(3_600)
        )
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false),
            sourceID: .sweBenchVerified
        )
        let model = RadarWorkspaceModel(
            runtimes: [.sweBenchVerified: runtime],
            selectedSourceID: .sweBenchVerified
        )

        // When
        await model.start()

        // Then
        #expect(runtime.lifecycleState == .running)
        #expect(model.hasComparableHistory(for: .sweBenchVerified))
        #expect(model.destinations(for: .sweBenchVerified) == [.models, .trends, .sourceStatus, .export])
        await model.stop()
    }
    #endif

    @Test("stored routes preserve canonical inputs and safely reject unsupported destinations")
    func storedRouteContract() {
        // Given
        let canonicalRoutes: [WorkspaceRoute] = [
            .informationOverview,
            .source(.claudeCodeRadar),
            .sourcePage(.claudeCodeRadar, .export),
            .sourcePage(.codexRadar, .intelligenceCenter),
            .sourcePage(.sweBenchVerified, .trends),
            .sourcePage(.sweBenchVerified, .export),
        ]

        // When / Then
        for route in canonicalRoutes {
            #expect(WorkspaceRoute(storageKey: route.storageKey) == route)
        }
        #expect(WorkspaceRoute(storageKey: "export") == .export)
        #expect(WorkspaceRoute(storageKey: "source:swe-bench-verified:decision-lens") == .source(.sweBenchVerified))
        #expect(WorkspaceRoute(storageKey: "malformed") == .informationOverview)
    }

    @MainActor
    @Test("route normalization keeps exports source-local and removes unavailable SWE trends")
    func routeNormalization() {
        // Given
        let model = workspaceModel()
        let unavailableSWERoute = WorkspaceRoute.sourcePage(.sweBenchVerified, .trends)

        // When / Then
        #expect(model.normalizedRoute(unavailableSWERoute) == .source(.sweBenchVerified))
        model.selectSource(.codexRadar)
        #expect(model.normalizedRoute(.export) == .sourcePage(.codexRadar, .export))
        #expect(model.normalizedRoute(.source(.init(rawValue: "unknown-source"))) == .source(.codexRadar))
    }

    @MainActor
    @Test("restoring a source page selects its refresh runtime")
    func sourcePageRestorationSelectsRefreshRuntime() throws {
        // Given
        let model = workspaceModel()
        let codex = try #require(model.runtime(for: .codexRadar))

        // When
        let route = model.restoreRoute(.sourcePage(.codexRadar, .models))

        // Then
        #expect(route == .sourcePage(.codexRadar, .models))
        #expect(model.selectedSourceID == .codexRadar)
        #expect(model.runtime === codex)
    }

    @MainActor
    private func workspaceModel() -> RadarWorkspaceModel {
        let environment = AppEnvironment(
            dataRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            fixtureMode: .disabled,
            onlineSourceEnabled: false
        )
        let runtimes = Dictionary(uniqueKeysWithValues: [
            RadarSourceID.claudeCodeRadar,
            .codexRadar,
            .sweBenchVerified,
        ].map { ($0, RadarAppRuntime(environment: environment, sourceID: $0)) })
        return RadarWorkspaceModel(runtimes: runtimes, selectedSourceID: .claudeCodeRadar)
    }
}
