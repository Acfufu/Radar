import Foundation
import Testing
@testable import AIRadar

@Suite("ReleaseReadinessTests", .serialized)
struct ReleaseReadinessTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("Release assembly includes only the app icon and excludes fixture and Debug resources")
    func releaseAssemblyContract() throws {
        let script = try text("Scripts/build-app.sh")
        let plist = try text("Config/AIRadar-Info.plist")
        #expect(script.contains("if [[ -z \"${DEVELOPER_DIR:-}\" && -d \"/Applications/Xcode.app/Contents/Developer\" ]]"))
        #expect(script.contains("export DEVELOPER_DIR=\"/Applications/Xcode.app/Contents/Developer\""))
        #expect(script.contains("if [[ \"$CONFIGURATION\" == \"debug\" ]]"))
        #expect(script.contains("Assets/AIRadar.icns"))
        #expect(script.contains("! -name \"$APP_NAME.icns\""))
        #expect(script.contains("Release bundle must not contain fixture or Debug resources"))
        #expect(script.contains("find \"$RESOURCES_DIR\""))
        #expect(plist.contains("CFBundleIconFile"))
        #expect(plist.contains("AIRadar.icns"))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Assets/AIRadar.png").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Assets/AIRadar.icns").path))
    }

    @Test("Release and online QA enable all approved sources")
    func releaseOnlineSourceContract() throws {
        let environment = try text("Sources/AIRadar/App/AppEnvironment.swift")
        let app = try text("Sources/AIRadar/ClaudeRadarApp.swift")
        #expect(environment.contains("case online"))
        #expect(environment.contains("#else\n        let onlineSourceEnabled = true"))
        #expect(app.contains("Task { await model.start() }"))
        #expect(app.contains("let metadataStore = SyncMetadataStore(root: environment.dataRoot)"))
        #expect(app.components(separatedBy: "metadataStore: metadataStore").count == 4)
        #expect(!environment.contains("PUBLIC_ONLINE"))
        #expect(!environment.contains("RADAR_ONLINE"))

        let onlineQA = AppEnvironment(
            dataRoot: FileManager.default.temporaryDirectory,
            fixtureMode: .online,
            onlineSourceEnabled: true
        )
        #expect(onlineQA.synchronizationEnabled(for: .claudeCodeRadar))
        #expect(onlineQA.synchronizationEnabled(for: .codexRadar))
        #expect(onlineQA.synchronizationEnabled(for: .sweBenchVerified))
        #expect(onlineQA.supportLevel(for: .claudeCodeRadar) == .authorized)
        #expect(onlineQA.supportLevel(for: .codexRadar) == .authorized)
        #expect(onlineQA.supportLevel(for: .sweBenchVerified) == .authorized)
    }

    @MainActor
    @Test("selected-source normalized history clear preserves siblings and raw samples; raw clear is independent")
    func independentClearOperations() async throws {
        try await verifyHistoryClearPreservesRaw()
        try await verifyRawClearPreservesHistory()
    }

    @Test("compatible normalized history survives an upgrade reopen")
    func upgradePreservesHistory() async throws {
        let dataRoot = temporaryRoot("upgrade")
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let first = try repository(at: dataRoot)
        _ = try await first.insertBenchmark(benchmark())

        let reopened = try repository(at: dataRoot)
        let history = try await reopened.benchmarkHistory(sourceID: .claudeCodeRadar)
        #expect(history.count == 1)
        #expect(history.first?.seriesRevision == "claude-radar-v1")
        #expect(history.first?.models.first?.descriptor.displayName == "Release Upgrade Model")
    }

    /// P2② increment (spec §5.2): the additive intelligence-efficiency
    /// entity survives a store reopen under the current schema.
    @MainActor
    @Test("intelligence-efficiency snapshot survives an upgrade reopen")
    func upgradePreservesIntelligenceEfficiency() async throws {
        let dataRoot = temporaryRoot("upgrade-efficiency")
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let dataset = IntelligenceEfficiencyDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 1_752_566_500),
            type: IntelligenceEfficiencyParser.expectedType,
            points: [.init(model: "m", effort: "high", harness: "codex", iq: 80)]
        )
        let first = try repository(at: dataRoot)
        _ = try await first.insertIntelligenceEfficiency(dataset)

        let reopened = try repository(at: dataRoot)
        let state = try await reopened.intelligenceEfficiencyState(sourceID: .codexRadar)
        #expect(state.value == dataset)
        #expect(try await reopened.metadata(sourceID: .codexRadar, datasetType: .intelligenceEfficiency).lastSuccessfulAt != nil)
    }

    /// P2③ increment (spec §5.3): the whole-run-set replacement entity
    /// survives a store reopen under the current schema.
    @MainActor
    @Test("fast-radar run set survives an upgrade reopen")
    func upgradePreservesFastRadarRuns() async throws {
        let dataRoot = temporaryRoot("upgrade-fast-radar")
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let dataset = FastRadarHistoryDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 1_752_566_500),
            type: FastRadarHistoryParser.expectedType,
            runs: [.init(runID: "r1", measuredAt: "2026-09-04T13:14:54+08:00")]
        )
        let first = try repository(at: dataRoot)
        _ = try await first.insertFastRadarHistory(dataset)

        let reopened = try repository(at: dataRoot)
        let state = try await reopened.fastRadarHistoryState(sourceID: .codexRadar)
        #expect(state.value == dataset)
        #expect(try await reopened.metadata(sourceID: .codexRadar, datasetType: .fastRadarHistory).lastSuccessfulAt != nil)
    }

    @MainActor
    private func verifyHistoryClearPreservesRaw() async throws {
        let dataRoot = temporaryRoot("clear-history")
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let seededRepository = try repository(at: dataRoot)
        _ = try await seededRepository.insertBenchmark(benchmark())
        _ = try await seededRepository.insertRenderedWarning(warning())
        let rawStore = RawSampleStore(dataRoot: dataRoot)
        try await rawStore.save(Data("raw".utf8), sourceID: .codexRadar, outcome: .success, at: .now)
        let runtime = RadarAppRuntime(
            environment: .init(dataRoot: dataRoot, fixtureMode: .disabled, onlineSourceEnabled: false),
            sourceID: .codexRadar
        )
        await runtime.start()
        #expect(await runtime.clearHistory())
        await runtime.stop()
        let clearedRepository = try repository(at: dataRoot)
        #expect(try await clearedRepository.benchmarkHistory(sourceID: .claudeCodeRadar).count == 1)
        #expect(try await clearedRepository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark).lastSuccessfulAt != nil)
        #expect(try await clearedRepository.renderedWarningHistory(sourceID: .codexRadar).isEmpty)
        #expect(try await clearedRepository.metadata(sourceID: .codexRadar, datasetType: .renderedWarnings) == .empty)
        #expect(!(try await rawStore.samples(sourceID: .codexRadar)).isEmpty)
    }

    @MainActor
    private func verifyRawClearPreservesHistory() async throws {
        let dataRoot = temporaryRoot("clear-raw")
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        _ = try await repository(at: dataRoot).insertBenchmark(benchmark())
        let rawStore = RawSampleStore(dataRoot: dataRoot)
        try await rawStore.save(Data("raw".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: .now)
        let runtime = RadarAppRuntime(environment: .init(dataRoot: dataRoot, fixtureMode: .disabled, onlineSourceEnabled: false))
        await runtime.start()
        #expect(await runtime.clearRawSamples())
        await runtime.stop()
        #expect((try await rawStore.samples(sourceID: .claudeCodeRadar)).isEmpty)
        #expect(try await repository(at: dataRoot).benchmarkHistory(sourceID: .claudeCodeRadar).count == 1)
    }

    private func repository(at dataRoot: URL) throws -> RadarRepository {
        RadarRepository(container: try AppEnvironment(dataRoot: dataRoot, fixtureMode: .disabled, onlineSourceEnabled: false).makeModelContainer(), metadataStore: SyncMetadataStore(root: dataRoot))
    }

    private func benchmark() -> BenchmarkDataset {
        let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "release-upgrade")
        let model = ModelBenchmark(id: id, descriptor: .init(id: id, upstreamName: "Release Upgrade Model", displayName: "Release Upgrade Model"), qualityScore: 88, passedTasks: 8, validTasks: 10, invalidTasks: 2, benchmarkCostUSD: 2, inputTokens: nil, outputTokens: nil, cacheReadTokens: nil, cacheCreationTokens: nil, totalTokens: nil, elapsedSeconds: 12, agentSteps: nil, cacheHitPercent: nil)
        return .init(sourceID: .claudeCodeRadar, sourceUpdatedAt: .init(timeIntervalSince1970: 1_700_000_000), fetchedAt: .init(timeIntervalSince1970: 1_700_000_001), benchmarkName: "Release Upgrade", benchmarkVersion: "1", seriesRevision: "claude-radar-v1", models: [model])
    }

    private func warning() throws -> CodexRenderedWarningSnapshot {
        let cards = [CodexRenderedWarningCard(
            displayName: "GPT-5.6",
            family: "GPT",
            effort: "High",
            sourceOrder: 0,
            iq: 88,
            drop24h: 2,
            drop48h: nil
        )]
        let parserRevision = "codex-radar-rendered-dom-v1"
        let finalOrigin = "https://codexradar.com"
        let fingerprint = try CodexRenderedWarningSemanticFingerprint.make(
            sourceTimeLabel: "Updated now",
            cards: cards,
            finalOrigin: finalOrigin,
            parserRevision: parserRevision
        )
        return .init(
            sourceID: .codexRadar,
            parserRevision: parserRevision,
            finalOrigin: finalOrigin,
            sourceTimeLabel: "Updated now",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_002),
            cards: cards,
            semanticFingerprint: fingerprint
        )
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AIRadar-ReleaseReadiness-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }
}
