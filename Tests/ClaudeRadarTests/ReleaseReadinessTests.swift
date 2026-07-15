import Foundation
import Testing
@testable import ClaudeRadar

@Suite("ReleaseReadinessTests", .serialized)
struct ReleaseReadinessTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("Release assembly excludes fixture and Debug resources")
    func releaseAssemblyContract() throws {
        let script = try text("Scripts/build-app.sh")
        #expect(script.contains("if [[ -z \"${DEVELOPER_DIR:-}\" && -d \"/Applications/Xcode.app/Contents/Developer\" ]]"))
        #expect(script.contains("export DEVELOPER_DIR=\"/Applications/Xcode.app/Contents/Developer\""))
        #expect(script.contains("if [[ \"$CONFIGURATION\" == \"debug\" ]]"))
        #expect(script.contains("Release bundle must not contain fixture or Debug resources"))
        #expect(script.contains("find \"$RESOURCES_DIR\""))
    }

    @Test("Release online source is compile-time disabled")
    func releaseOnlineSourceContract() throws {
        let environment = try text("Sources/ClaudeRadar/App/AppEnvironment.swift")
        #expect(environment.contains("#else\n        let onlineSourceEnabled = false"))
        #expect(environment.contains("#else\n        .disabled"))
        #expect(!environment.contains("PUBLIC_ONLINE"))
        #expect(!environment.contains("RADAR_ONLINE"))
    }

    @MainActor
    @Test("history and raw samples clear independently")
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

    @Test("release declarations state exact paths and external blockers")
    func releaseDocumentationContract() throws {
        let checklist = try text("docs/release-checklist.md")
        #expect(checklist.contains("/Applications/ClaudeRadar.app"))
        #expect(checklist.contains("~/Library/Application Support/ClaudeRadar"))
        #expect(checklist.contains("BLOCKED"))
        let notices = try text("docs/third-party-notices.md")
        #expect(notices.contains("https://claudecoderadar.com/?lang=en"))
        #expect(notices.contains("no affirmative"))
        #expect(notices.contains("disabled"))
    }

    @MainActor
    private func verifyHistoryClearPreservesRaw() async throws {
        let dataRoot = temporaryRoot("clear-history")
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        _ = try await repository(at: dataRoot).insertBenchmark(benchmark())
        let rawStore = RawSampleStore(dataRoot: dataRoot)
        try await rawStore.save(Data("raw".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: .now)
        let runtime = RadarAppRuntime(environment: .init(dataRoot: dataRoot, fixtureMode: .disabled, onlineSourceEnabled: false))
        await runtime.start()
        #expect(await runtime.clearHistory())
        await runtime.stop()
        #expect(try await repository(at: dataRoot).benchmarkHistory(sourceID: .claudeCodeRadar).isEmpty)
        #expect(!(try await rawStore.samples(sourceID: .claudeCodeRadar)).isEmpty)
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

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ClaudeRadar-ReleaseReadiness-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }
}
