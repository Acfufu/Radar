import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("MultiSourceWorkspaceTests", .serialized)
struct MultiSourceWorkspaceTests {
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

    @Test("selected-source export excludes the sibling workspace")
    func exportScope() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Radar-Export-Scope-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(
            for: BenchmarkSnapshotEntity.self,
            CommunitySnapshotEntity.self,
            SourceStatusSnapshotEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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
