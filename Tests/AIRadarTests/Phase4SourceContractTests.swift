import Foundation
import Testing

@Suite("Phase4SourceContractTests")
struct Phase4SourceContractTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("workspace is singleton and source homepages are exact")
    func sceneAndHomepage() throws {
        let app = try text("Sources/AIRadar/ClaudeRadarApp.swift")
        let commands = try text("Sources/AIRadar/App/AppCommands.swift")
        #expect(app.contains("Window(\"AI Radar\", id: \"workspace\")"))
        #expect(!app.contains("WindowGroup(\"AI Radar\""))
        #expect(commands.contains("Button(\"关闭工作区\")"))
        let claude = try text("Sources/AIRadar/Sources/ClaudeCodeRadar/ClaudeRadarConfiguration.swift")
        let codex = try text("Sources/AIRadar/Sources/CodexRadar/CodexRadarConfiguration.swift")
        let sweBench = try text("Sources/AIRadar/Sources/SWEBench/SWEBenchConfiguration.swift")
        let descriptor = try text("Sources/AIRadar/Domain/RadarSourceDescriptor.swift")
        let status = try text("Sources/AIRadar/Features/SourceStatus/SourceStatusView.swift")
        let workspace = try text("Sources/AIRadar/Features/Workspace/RadarWorkspaceView.swift")
        #expect(claude.contains("https://claudecoderadar.com/?lang=en"))
        #expect(codex.contains("https://codexradar.com/"))
        #expect(sweBench.contains("https://www.swebench.com/"))
        #expect(descriptor.contains("数据来自 Codex 雷达 codexradar.com"))
        #expect(descriptor.contains("数据来自 SWE-bench 官方已发布榜单"))
        #expect(status.contains("projection.source.homepageURL"))
        #expect(workspace.contains("source.attributionText"))
    }

    @Test("user agent and about-page branding are pinned literals")
    func userAgentAndAboutBranding() throws {
        let http = try text("Sources/AIRadar/Sources/ClaudeCodeRadar/ClaudeCodeRadarHTTP.swift")
        #expect(http.contains("AIRadar/0.3.0 (macOS; +https://github.com/Acfufu/Radar)"))
        #expect(!http.contains("ClaudeRadar/0.1"))
        let settings = try text("Sources/AIRadar/Features/Settings/SettingsView.swift")
        #expect(settings.contains("AI Radar is an independent open-source project and is not affiliated with codexradar.com (AI 雷达); the name is an independent choice."))
        #expect(settings.contains("AI Radar 为独立开源项目，与 codexradar.com 的 AI 雷达无关联，命名系独立选择"))
    }

    @Test("workspace opens from persistent menu scene")
    func workspaceLaunchBehavior() throws {
        let app = try text("Sources/AIRadar/ClaudeRadarApp.swift")
        #expect(app.contains("@SceneBuilder"))
        #expect(app.contains("var body: some Scene {"))
        #expect(!app.contains("workspaceScene"))
        #expect(!app.contains(".restorationBehavior(.disabled)"))
        #expect(!app.contains(".defaultLaunchBehavior(.presented)"))
        #expect(app.contains("private struct MenuBarLaunchLabel: View"))
        #expect(app.contains("@Environment(\\.openWindow) private var openWindow"))
        #expect(app.contains(".task { openWindow(id: \"workspace\") }"))
        #expect(app.contains("Label(\"AI Radar\", systemImage: \"scope\")"))
        #expect(app.components(separatedBy: "Window(\"AI Radar\", id: \"workspace\")").count == 2)
        #expect(app.contains(".commands { AppCommands(model: workspaceModel) }"))
    }

    @Test("fixture sequence and UI seed implementations are debug-only")
    func releaseIsolation() throws {
        let fixture = try text("Sources/AIRadar/App/FixtureSequenceTransport.swift")
        #expect(fixture.hasPrefix("#if DEBUG"))
        #expect(fixture.hasSuffix("#endif\n"))
        let seed = try text("Sources/AIRadar/App/DebugUISeed.swift")
        #expect(seed.hasPrefix("#if DEBUG"))
        #expect(seed.hasSuffix("#endif\n"))
    }

    @Test("analytics fixture adds no production resource or network surface")
    func analyticsFixtureReleaseBoundary() throws {
        let seed = try text("Sources/AIRadar/App/DebugUISeed.swift")
        let package = try text("Package.swift")
        #expect(seed.contains("state == \"analytics\""))
        #expect(!package.contains("analytics-fixture"))
        #expect(!package.contains("radar-insights"))
        // P2② (spec §5.2): the canonical intelligence-efficiency fixture is a
        // test-only asset — excluded from the test bundle resources and never
        // shipped inside the app target.
        #expect(package.contains("Fixtures/IntelligenceEfficiency"))
        #expect(FileManager.default.fileExists(
            atPath: root.appending(path: "Tests/AIRadarTests/Fixtures/IntelligenceEfficiency/intelligence-efficiency.json").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: "Sources/AIRadar/Resources/Fixtures/intelligence-efficiency.json").path
        ))
        // P2③: same placement contract for the fast-radar canonical fixture.
        #expect(package.contains("Fixtures/FastRadarHistory"))
        #expect(FileManager.default.fileExists(
            atPath: root.appending(path: "Tests/AIRadarTests/Fixtures/FastRadarHistory/fast-radar-history.json").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: "Sources/AIRadar/Resources/Fixtures/fast-radar-history.json").path
        ))
    }

    @Test("intelligence-efficiency sidecar endpoint and forbidden-domain contract")
    func efficiencySidecarBoundaryContract() throws {
        let adapter = try text("Sources/AIRadar/Sources/CodexRadar/IntelligenceEfficiencyAdapter.swift")
        // Fixed endpoint + dedicated 8MiB transport set at both sites
        // (transport cap and source-level cap, spec §5.0/§10).
        #expect(adapter.contains("URL(string: \"https://codexradar.com/data/intelligence-efficiency.json\")!"))
        #expect(adapter.contains("static let maximumResponseBytes = 8 * 1_024 * 1_024"))
        #expect(adapter.contains("URLSessionHTTPTransport(maxBodyBytes: IntelligenceEfficiencyAdapter.maximumResponseBytes)"))
        #expect(adapter.contains("URLSessionHTTPTransport(maxBodyBytes: maximumResponseBytes)"))

        // The payload's provenance fields point at the protected API domain;
        // no production source may construct requests for it. The only
        // permitted mention of the domain is the Settings disclosure, and the
        // deng submission API is forbidden everywhere (spec §5.0).
        var sources: [String: String] = [:]
        let sourcesRoot = root.appending(path: "Sources/AIRadar")
        for fileURL in FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)! {
            let url = fileURL as! URL
            if url.pathExtension == "swift" {
                sources[String(url.path.dropFirst(sourcesRoot.path.count + 1))] = try String(contentsOf: url, encoding: .utf8)
            }
        }
        let settings = try #require(sources["Features/Settings/SettingsView.swift"])
        let withoutDisclosure = sources.filter { $0.key != "Features/Settings/SettingsView.swift" }.values.joined()
        #expect(!withoutDisclosure.contains("api.codexradar.com"))
        #expect(!sources.values.joined().contains("deng.codexradar.com/api"))
        #expect(settings.contains("codexradar.com/data/intelligence-efficiency.json"))
        #expect(settings.contains("公开 GET、无认证"))
        #expect(settings.contains("api.codexradar.com"))
        #expect(settings.contains("/api/*"))

        // P2③ fast-radar sidecar: same whitelist and dual 8MiB caps.
        let fastAdapter = try text("Sources/AIRadar/Sources/CodexRadar/FastRadarHistoryAdapter.swift")
        #expect(fastAdapter.contains("URL(string: \"https://codexradar.com/data/fast-radar-history.json\")!"))
        #expect(fastAdapter.contains("static let maximumResponseBytes = 8 * 1_024 * 1_024"))
        #expect(fastAdapter.contains("URLSessionHTTPTransport(maxBodyBytes: FastRadarHistoryAdapter.maximumResponseBytes)"))
        #expect(fastAdapter.contains("URLSessionHTTPTransport(maxBodyBytes: maximumResponseBytes)"))
        #expect(settings.contains("codexradar.com/data/fast-radar-history.json"))
    }

    @Test("export is wired as a one-way save surface without an import handler")
    func exportIsOneWay() throws {
        let view = try text("Sources/AIRadar/Features/Export/ExportView.swift")
        let manifest = try text("Sources/AIRadar/Data/Export/ExportManifest.swift")
        #expect(view.contains("NSSavePanel"))
        #expect(view.contains("runtime.export"))
        #expect(view.contains("Codex Radar 官网降智预警"))
        #expect(manifest.contains("case renderedWarnings = \"rendered-warnings\""))
        #expect(!view.lowercased().contains("fileimporter("))
        #expect(!view.lowercased().contains("openpanel"))
    }

    @Test("Codex rendered page, privacy, attribution, and independent local fit stay explicit")
    func renderedWarningSourceAndPrivacyContract() throws {
        let contract = try text("docs/source-contract.md")
        let notices = try text("docs/third-party-notices.md")
        let readerSource = try text("Sources/AIRadar/Sources/CodexRadar/CodexRenderedWarningPageReader.swift")
        #expect(contract.contains("https://codexradar.com/"))
        #expect(contract.contains("codex-radar-rendered-dom-v2"))
        // P3 v2 (spec §6): values anchor only on the four surviving
        // degradation markers; the dead data-radar-metric fallback is gone
        // and Cloudflare challenge detection is retained.
        #expect(readerSource.contains("data-radar-degradation"))
        #expect(readerSource.contains("data-radar-degradation-grid"))
        #expect(readerSource.contains("degradation-card-score"))
        #expect(readerSource.contains("degradation-deltas"))
        #expect(!readerSource.contains("data-radar-metric"))
        #expect(readerSource.contains("data-radar-challenge"))
        #expect(readerSource.contains("cf-challenge"))
        #expect(contract.contains("数据来自 Codex 雷达 codexradar.com"))
        #expect(contract.contains("DOM observation is not official API authorization"))
        #expect(contract.contains("WKWebsiteDataStore.nonPersistent()"))
        #expect(contract.contains("Radar does not author, intercept, inspect, parse, replay, or persist those requests or responses"))
        #expect(contract.contains("never persists or exports HTML, body text, script source, cookies, browser storage/profile data, response bodies, authorization material, or endpoint/interception data"))
        #expect(contract.contains("`Codex Radar 官网降智预警` and `本地 IQ 拟合` are independent results"))
        #expect(notices.contains("not official API authorization or a license grant"))
        #expect(notices.contains("persists or exports only bounded normalized warning fields"))
    }

    @Test("Codex rendered IQ history documentation and source boundary stay aligned")
    func renderedIQHistorySourceAndReleaseContract() throws {
        let contract = try text("docs/source-contract.md")
        let notices = try text("docs/third-party-notices.md")
        let design = try text("docs/design-qa.md")
        let reader = try text("Sources/AIRadar/Sources/CodexRadar/CodexRenderedIQHistoryPageReader.swift")
        let parser = try text("Sources/AIRadar/Sources/CodexRadar/CodexRenderedIQHistoryDOMParser.swift")
        let lifecycle = try text("Sources/AIRadar/Sources/CodexRadar/CodexRenderedPageLifecycle.swift")
        let export = try text("Sources/AIRadar/Data/Export/ExportManifest.swift")
        let model = try text("Sources/AIRadar/Features/Workspace/CodexRenderedWorkspacePresentation.swift")

        #expect(contract.contains("https://deng.codexradar.com/"))
        #expect(contract.contains("noncommercial, anonymous observation"))
        #expect(contract.contains("WKWebsiteDataStore.nonPersistent()"))
        #expect(contract.contains("exactly 24 ordered points"))
        #expect(contract.contains("rendered-iq-history"))
        #expect(contract.contains("schema version `1`"))
        #expect(contract.contains("live readiness is **BLOCKED**"))
        #expect(notices.contains("数据来自分布式雷达 deng.codexradar.com · powered by codexradar"))
        #expect(notices.contains("https://deng.codexradar.com/"))
        #expect(design.contains("24 小时 IQ 趋势"))
        #expect(reader.contains("https://deng.codexradar.com/"))
        #expect(parser.contains("(2...8).contains(dto.series.count)"))
        #expect(parser.contains("value.points.count == 24"))
        #expect(lifecycle.contains("configuration.websiteDataStore = .nonPersistent()"))
        #expect(!reader.contains("fetch("))
        #expect(!reader.contains("XMLHttpRequest"))
        #expect(export.contains("case renderedIQHistory = \"rendered-iq-history\""))
        #expect(model.contains("let attribution = \"数据来自分布式雷达 deng.codexradar.com · powered by codexradar\""))
        #expect(model.contains("let backlink = \"https://deng.codexradar.com/\""))
    }

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: root.appending(path: relative), encoding: .utf8)
    }
}
