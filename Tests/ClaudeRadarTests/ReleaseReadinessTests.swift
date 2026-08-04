import Foundation
import Testing
@testable import ClaudeRadar

@Suite("ReleaseReadinessTests", .serialized)
struct ReleaseReadinessTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("Release assembly includes only the app icon and excludes fixture and Debug resources")
    func releaseAssemblyContract() throws {
        let script = try text("Scripts/build-app.sh")
        let plist = try text("Config/ClaudeRadar-Info.plist")
        #expect(script.contains("if [[ -z \"${DEVELOPER_DIR:-}\" && -d \"/Applications/Xcode.app/Contents/Developer\" ]]"))
        #expect(script.contains("export DEVELOPER_DIR=\"/Applications/Xcode.app/Contents/Developer\""))
        #expect(script.contains("if [[ \"$CONFIGURATION\" == \"debug\" ]]"))
        #expect(script.contains("Assets/ClaudeRadar.icns"))
        #expect(script.contains("! -name \"$APP_NAME.icns\""))
        #expect(script.contains("Release bundle must not contain fixture or Debug resources"))
        #expect(script.contains("find \"$RESOURCES_DIR\""))
        #expect(plist.contains("CFBundleIconFile"))
        #expect(plist.contains("ClaudeRadar.icns"))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Assets/ClaudeRadar.png").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Assets/ClaudeRadar.icns").path))
    }

    @Test("Release and online QA enable all approved sources")
    func releaseOnlineSourceContract() throws {
        let environment = try text("Sources/ClaudeRadar/App/AppEnvironment.swift")
        let app = try text("Sources/ClaudeRadar/ClaudeRadarApp.swift")
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

    @Test("release declarations state exact paths and external blockers")
    func releaseDocumentationContract() throws {
        let checklist = try text("docs/release-checklist.md")
        #expect(checklist.contains("/Applications/ClaudeRadar.app"))
        #expect(checklist.contains("~/Library/Application Support/ClaudeRadar"))
        #expect(checklist.contains("Claude Code Radar online source: **ENABLED in current code"))
        #expect(checklist.contains("Codex Radar online source: **ENABLED in current code"))
        #expect(checklist.contains("approved noncommercial rendered-page path"))
        #expect(checklist.contains("protected full API remains out of scope"))
        #expect(checklist.contains("selected source's normalized"))
        #expect(checklist.contains("legitimate synchronization may repopulate"))
        #expect(checklist.contains("rendered-warning history, rendered-IQ history, and sync metadata"))
        #expect(checklist.contains("HISTORICAL RECEIPT ONLY; CURRENT LIVE READINESS NOT ESTABLISHED"))
        #expect(checklist.contains("**BLOCKED** live readiness, not Pass"))
        #expect(checklist.contains("BLOCKED"))
        let notices = try text("docs/third-party-notices.md")
        #expect(notices.contains("https://claudecoderadar.com/?lang=en"))
        #expect(notices.contains("2026-07-16"))
        #expect(notices.contains("automatic synchronization, local history caching, and re-display"))
        #expect(notices.contains("rendered-DOM path is not official API authorization"))
        #expect(notices.contains("uses nonpersistent WebKit"))
        #expect(notices.contains("official rendered warning and Radar's local IQ fitting remain independent"))
        #expect(notices.contains("does not call or bypass the protected full API"))
        let settings = try text("Sources/ClaudeRadar/Features/Settings/SettingsView.swift")
        #expect(settings.contains("已启用自动同步"))
        #expect(settings.contains("规范化历史（含渲染预警、IQ 历史及同步元数据）已清除"))
        #expect(settings.contains("原始诊断样本和其他来源保留"))
        #expect(settings.contains("后续合法同步可能重新填充该来源数据"))
        #expect(settings.contains("规范化历史（含渲染预警、IQ 历史及同步元数据）保留"))
        #expect(settings.contains("未报告已清除数据"))
        #expect(settings.contains("官网预警与本地 IQ 拟合口径独立"))
        #expect(settings.contains("受保护的完整 API"))
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
        FileManager.default.temporaryDirectory.appending(path: "ClaudeRadar-ReleaseReadiness-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }
}
