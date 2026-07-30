import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("MultiSourceWorkspaceTests", .serialized)
struct MultiSourceWorkspaceTests {
    @MainActor
    @Test("intelligence center route round-trips and stays Codex-only")
    func intelligenceCenterRouteIsolation() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let model = RadarWorkspaceModel(
            runtimes: Dictionary(uniqueKeysWithValues: [
                RadarSourceID.claudeCodeRadar,
                .codexRadar,
                .sweBenchVerified,
            ].map { ($0, RadarAppRuntime(environment: environment, sourceID: $0)) }),
            selectedSourceID: .codexRadar
        )
        let route = WorkspaceRoute.sourcePage(.codexRadar, .intelligenceCenter)

        #expect(WorkspaceRoute(storageKey: route.storageKey) == route)
        #expect(WorkspaceDestination.intelligenceCenter.title(for: .codexRadar) == "智力中心")
        #expect(WorkspaceDestination.intelligenceCenter.icon == "brain.head.profile")
        #expect(model.destinations(for: .codexRadar).last == .intelligenceCenter)
        #expect(!model.destinations(for: .claudeCodeRadar).contains(.intelligenceCenter))
        #expect(!model.destinations(for: .sweBenchVerified).contains(.intelligenceCenter))
    }

    #if DEBUG
    @Test("analytics fixture publishes same-revision Codex history beyond 24 hours")
    func analyticsFixtureHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Radar-Analytics-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )

        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .codexRadar,
            state: "analytics",
            now: now
        )
        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .codexRadar,
            state: "analytics",
            now: now.addingTimeInterval(60 * 60)
        )
        let history = try await repository.benchmarkHistory(sourceID: .codexRadar)
        let current = try #require(history.last)
        let names = current.models.map(\.descriptor.displayName)

        #expect(history.count == 5)
        #expect(Set(history.map(\.seriesRevision)).count == 1)
        #expect((history.last!.sourceUpdatedAt ?? history.last!.fetchedAt)
            .timeIntervalSince(history.first!.sourceUpdatedAt ?? history.first!.fetchedAt) > 24 * 60 * 60)
        #expect(names.contains { $0.contains("Sol") })
        #expect(names.contains { $0.contains("Terra") })
        #expect(names.contains { $0.contains("Luna") })
        #expect(names.contains { $0.contains("GPT-5.5") })
        #expect(current.models.contains { $0.agentSteps == nil })
        #expect(Dictionary(grouping: current.models, by: \.qualityScore).values.contains { $0.count >= 2 })
        #expect(current.models.allSatisfy { !$0.descriptor.displayName.contains("Ignore previous instructions") })
    }

    @MainActor
    @Test("UI fixture publishes three independent source projections without synchronization")
    func uiFixtureSourceIsolation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Radar-UI-Sources-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
        let runtimes = Dictionary(uniqueKeysWithValues: [
            RadarSourceID.claudeCodeRadar,
            .codexRadar,
            .sweBenchVerified,
        ].map { ($0, RadarAppRuntime(environment: environment, sourceID: $0)) })
        let model = RadarWorkspaceModel(runtimes: runtimes, selectedSourceID: .claudeCodeRadar)

        await model.start()

        for sourceID in [RadarSourceID.claudeCodeRadar, .codexRadar, .sweBenchVerified] {
            let runtime = try #require(runtimes[sourceID])
            let benchmark = try #require(runtime.projection?.benchmark.value)
            #expect(runtime.lifecycleState == .running)
            #expect(!environment.synchronizationEnabled(for: sourceID))
            #expect(benchmark.sourceID == sourceID)
            #expect(!benchmark.models.isEmpty)
            #expect(runtime.benchmarkHistory.count >= 2)
            #expect(benchmark.models.allSatisfy { $0.id.sourceID == sourceID })
        }
        let codex = try #require(runtimes[.codexRadar])
        #expect(Set(codex.benchmarkHistory.map(\.seriesRevision)) == ["fixture-r1", "fixture-r2"])
        #expect(codex.projection?.benchmark.value?.models.contains { $0.qualityScore == nil && $0.benchmarkCostUSD == nil } == true)
        #expect(codex.projection?.benchmark.value?.models.contains { $0.descriptor.displayName.contains("Ignore previous instructions") } == true)
        #expect(codex.projection?.community.value?.sourceID == .codexRadar)
        #expect(codex.projection?.sourceStatus.value?.sourceID == .codexRadar)
        let sweBench = try #require(runtimes[.sweBenchVerified]?.projection)
        let sweRows = try #require(sweBench.benchmark.value?.models)
        #expect(sweRows.allSatisfy { $0.validTasks == 500 })
        #expect(sweRows.contains { $0.benchmarkCostUSD == nil })
        #expect(Set(sweRows.filter { $0.descriptor.displayName == "Same Display Name" }.map(\.id)).count == 2)
        #expect(sweRows.contains { $0.descriptor.displayName.contains("Ignore previous instructions") })
        let swePareto = ParetoAnalysis.analyze(dataset: try #require(sweBench.benchmark.value), preset: .qualityCost)
        #expect(swePareto.first { $0.modelID.upstreamKey == "frontier" }?.classification == .frontier)
        #expect(swePareto.first { $0.modelID.upstreamKey == "dominated" }?.classification == .dominated)
        #expect(swePareto.first { $0.modelID.upstreamKey == "no-cost" }?.classification == .dataInsufficient)
        #expect(sweBench.community.value == nil)
        #expect(sweBench.community.error == nil)
        #expect(sweBench.sourceStatus.value == nil)
        #expect(sweBench.sourceStatus.error == nil)
        #expect((try await RawSampleStore(dataRoot: root).samples(sourceID: .claudeCodeRadar)).isEmpty)
        #expect((try await RawSampleStore(dataRoot: root).samples(sourceID: .codexRadar)).isEmpty)
        #expect((try await RawSampleStore(dataRoot: root).samples(sourceID: .sweBenchVerified)).isEmpty)
        await model.stop()
    }

    @Test("UI fixture retains benchmark LKG on failure and keeps SWE auxiliary segments neutral")
    func uiFixtureFailureStates() async throws {
        for sourceID in [RadarSourceID.claudeCodeRadar, .codexRadar, .sweBenchVerified] {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "Radar-UI-Error-\(sourceID.rawValue)-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let environment = AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
            let repository = RadarRepository(
                container: try environment.makeModelContainer(),
                metadataStore: SyncMetadataStore(root: root)
            )

            try await DebugUISeed.populate(repository: repository, sourceID: sourceID, state: "error")

            let benchmark = try await repository.benchmarkState(sourceID: sourceID)
            #expect(benchmark.value?.sourceID == sourceID)
            #expect(benchmark.error?.kind == .validation)
            if sourceID == .sweBenchVerified {
                let community = try await repository.communityState(sourceID: sourceID)
                let status = try await repository.sourceStatusState(sourceID: sourceID)
                #expect(community.value == nil)
                #expect(community.error == nil)
                #expect(status.value == nil)
                #expect(status.error == nil)
            }
        }
    }
    #endif

    @MainActor
    @Test("Codex fixture runtime publishes only the Codex-scoped workspace")
    func codexRuntimeScope() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CodexRadar-Runtime-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true)
        let runtime = RadarAppRuntime(environment: environment, sourceID: .codexRadar)

        // When
        await runtime.start()

        // Then
        #expect(runtime.lifecycleState == .running)
        #expect(runtime.projection?.benchmark.value?.sourceID == .codexRadar)
        #expect(runtime.projection?.community.value?.sourceID == .codexRadar)
        #expect(runtime.projection?.sourceStatus.value?.sourceID == .codexRadar)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        #expect(try await repository.snapshotCount(datasetType: .benchmark, sourceID: .codexRadar) == 1)
        #expect(try await repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 0)
        await runtime.stop()
    }

    @MainActor
    @Test("workspace selection swaps between three independent runtimes")
    func sourceSelection() {
        // Given
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let claude = RadarAppRuntime(environment: environment, sourceID: .claudeCodeRadar)
        let codex = RadarAppRuntime(environment: environment, sourceID: .codexRadar)
        let sweBench = RadarAppRuntime(environment: environment, sourceID: .sweBenchVerified)
        let model = RadarWorkspaceModel(
            runtimes: [
                .claudeCodeRadar: claude,
                .codexRadar: codex,
                .sweBenchVerified: sweBench,
            ],
            selectedSourceID: .claudeCodeRadar
        )

        // When
        model.selectSource(.codexRadar)

        // Then
        #expect(model.selectedSourceID == .codexRadar)
        #expect(model.runtime === codex)
        #expect(model.sources.map(\.id) == [.claudeCodeRadar, .codexRadar, .sweBenchVerified])
    }

    @MainActor
    @Test("app startup activates both independent runtimes")
    func startupActivatesBothSources() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Radar-Dual-Startup-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true)
        let claude = RadarAppRuntime(environment: environment, sourceID: .claudeCodeRadar)
        let codex = RadarAppRuntime(environment: environment, sourceID: .codexRadar)
        let model = RadarWorkspaceModel(
            runtimes: [.claudeCodeRadar: claude, .codexRadar: codex],
            selectedSourceID: .claudeCodeRadar
        )

        // When
        await model.start()

        // Then
        #expect(claude.lifecycleState == .running)
        #expect(codex.lifecycleState == .running)
        #expect(claude.projection?.benchmark.value == nil)
        #expect(codex.projection?.benchmark.value?.sourceID == .codexRadar)
        await model.stop()

        // When
        let offlineEnvironment = AppEnvironment(
            dataRoot: root,
            fixtureMode: .disabled,
            onlineSourceEnabled: false
        )
        let restoredClaude = RadarAppRuntime(environment: offlineEnvironment, sourceID: .claudeCodeRadar)
        let restoredCodex = RadarAppRuntime(environment: offlineEnvironment, sourceID: .codexRadar)
        let restoredModel = RadarWorkspaceModel(
            runtimes: [.claudeCodeRadar: restoredClaude, .codexRadar: restoredCodex],
            selectedSourceID: .codexRadar
        )
        await restoredModel.start()

        // Then
        #expect(restoredCodex.projection?.benchmark.value?.sourceID == .codexRadar)
        #expect(restoredCodex.benchmarkHistory.count == 1)
        #expect(restoredClaude.projection?.benchmark.value == nil)
        await restoredModel.stop()
    }

    @MainActor
    @Test("workspace publishes the Codex runtime official IQ history projection")
    func workspacePublishesRenderedIQHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Radar-Workspace-IQHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        let snapshot = try workspaceIQHistory()
        _ = try await repository.insertRenderedIQHistory(snapshot)
        let codex = RadarAppRuntime(
            environment: environment,
            sourceID: .codexRadar,
            renderedIQHistoryReaderFactory: { WorkspaceIQHistoryReader() }
        )
        let model = RadarWorkspaceModel(
            runtimes: [.codexRadar: codex],
            selectedSourceID: .codexRadar
        )

        await model.start()

        #expect(model.projection.renderedIQHistoryPresentation?.capturedAt == snapshot.capturedAt)
        #expect(model.projection.renderedIQHistoryPresentation?.selectedSeries?.displayName == "官网综合")
        await model.stop()
    }

    @Test("selected-source export excludes the sibling workspace")
    func exportScope() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Radar-Export-Scope-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try RadarModelSchema.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root))
        _ = try await repository.insertBenchmark(benchmark(sourceID: .claudeCodeRadar))
        _ = try await repository.insertBenchmark(benchmark(sourceID: .codexRadar))
        let source = RadarExportSource(
            repository: repository,
            rawSampleStore: RawSampleStore(dataRoot: root),
            sourceID: .codexRadar
        )

        // When
        let snapshot = try await source.beginExportSnapshot(includesRawSamples: false)
        let count = try await source.exportRecordCount(
            dataset: .benchmarkRuns,
            range: .all,
            snapshot: snapshot
        )
        await source.endExportSnapshot(snapshot)

        // Then
        #expect(count == 1)
    }

    private func benchmark(sourceID: RadarSourceID) -> BenchmarkDataset {
        let id = ModelID(sourceID: sourceID, upstreamKey: "fixture")
        return BenchmarkDataset(
            sourceID: sourceID,
            sourceUpdatedAt: Date(timeIntervalSince1970: 1),
            fetchedAt: Date(timeIntervalSince1970: 1),
            benchmarkName: "Fixture",
            benchmarkVersion: "1",
            seriesRevision: "fixture-r1",
            models: [ModelBenchmark(
                id: id,
                descriptor: ModelDescriptor(id: id, upstreamName: "Fixture", displayName: "Fixture"),
                qualityScore: 1,
                passedTasks: 1,
                validTasks: 1,
                invalidTasks: 0,
                benchmarkCostUSD: 1,
                inputTokens: 1,
                outputTokens: 1,
                cacheReadTokens: 0,
                cacheCreationTokens: nil,
                totalTokens: 2,
                elapsedSeconds: 1,
                agentSteps: nil,
                cacheHitPercent: 0
            )]
        )
    }
}

@MainActor
private final class WorkspaceIQHistoryReader: CodexRenderedIQHistoryReading {
    func read() async throws -> CodexRenderedIQHistorySnapshot {
        throw CancellationError()
    }

    func cancel() {}
}

private func workspaceIQHistory() throws -> CodexRenderedIQHistorySnapshot {
    let series = [
        CodexRenderedIQHistorySeries(
            sourceOrder: 0,
            seriesKey: "aggregate",
            displayName: "官网综合",
            points: (0..<24).map {
                CodexRenderedIQHistoryPoint(
                    sourceOrder: $0,
                    sourceTimeLabel: "\($0)h",
                    iq: 80
                )
            }
        ),
    ]
    let origin = "https://deng.codexradar.com"
    let revision = CodexRenderedIQHistoryDOMParser.parserRevision
    return CodexRenderedIQHistorySnapshot(
        sourceID: .codexRadar,
        parserRevision: revision,
        finalOrigin: origin,
        capturedAt: Date(timeIntervalSince1970: 100),
        series: series,
        semanticFingerprint: try CodexRenderedIQHistorySemanticFingerprint.make(
            sourceID: .codexRadar,
            series: series,
            finalOrigin: origin,
            parserRevision: revision
        )
    )
}
