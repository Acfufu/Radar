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
        let app = try text("Sources/ClaudeRadar/ClaudeRadarApp.swift")
        let commands = try text("Sources/ClaudeRadar/App/AppCommands.swift")
        #expect(app.contains("Window(\"Claude Radar\", id: \"workspace\")"))
        #expect(!app.contains("WindowGroup(\"Claude Radar\""))
        #expect(commands.contains("Button(\"关闭工作区\")"))
        let claude = try text("Sources/ClaudeRadar/Sources/ClaudeCodeRadar/ClaudeRadarConfiguration.swift")
        let codex = try text("Sources/ClaudeRadar/Sources/CodexRadar/CodexRadarConfiguration.swift")
        let sweBench = try text("Sources/ClaudeRadar/Sources/SWEBench/SWEBenchConfiguration.swift")
        let descriptor = try text("Sources/ClaudeRadar/Domain/RadarSourceDescriptor.swift")
        let status = try text("Sources/ClaudeRadar/Features/SourceStatus/SourceStatusView.swift")
        let workspace = try text("Sources/ClaudeRadar/Features/Workspace/RadarWorkspaceView.swift")
        #expect(claude.contains("https://claudecoderadar.com/?lang=en"))
        #expect(codex.contains("https://codexradar.com/"))
        #expect(sweBench.contains("https://www.swebench.com/"))
        #expect(descriptor.contains("数据来自 Codex 雷达 codexradar.com"))
        #expect(descriptor.contains("数据来自 SWE-bench 官方已发布榜单"))
        #expect(status.contains("projection.source.homepageURL"))
        #expect(workspace.contains("source.attributionText"))
    }

    @Test("workspace opens from persistent menu scene")
    func workspaceLaunchBehavior() throws {
        let app = try text("Sources/ClaudeRadar/ClaudeRadarApp.swift")
        #expect(app.contains("@SceneBuilder"))
        #expect(app.contains("var body: some Scene {"))
        #expect(!app.contains("workspaceScene"))
        #expect(!app.contains(".restorationBehavior(.disabled)"))
        #expect(!app.contains(".defaultLaunchBehavior(.presented)"))
        #expect(app.contains("private struct MenuBarLaunchLabel: View"))
        #expect(app.contains("@Environment(\\.openWindow) private var openWindow"))
        #expect(app.contains(".task { openWindow(id: \"workspace\") }"))
        #expect(app.contains("Label(\"Claude Radar\", systemImage: \"scope\")"))
        #expect(app.components(separatedBy: "Window(\"Claude Radar\", id: \"workspace\")").count == 2)
        #expect(app.contains(".commands { AppCommands(model: workspaceModel) }"))
    }

    @Test("fixture sequence and UI seed implementations are debug-only")
    func releaseIsolation() throws {
        let fixture = try text("Sources/ClaudeRadar/App/FixtureSequenceTransport.swift")
        #expect(fixture.hasPrefix("#if DEBUG"))
        #expect(fixture.hasSuffix("#endif\n"))
        let seed = try text("Sources/ClaudeRadar/App/DebugUISeed.swift")
        #expect(seed.hasPrefix("#if DEBUG"))
        #expect(seed.hasSuffix("#endif\n"))
    }

    @Test("analytics fixture adds no production resource or network surface")
    func analyticsFixtureReleaseBoundary() throws {
        let seed = try text("Sources/ClaudeRadar/App/DebugUISeed.swift")
        let package = try text("Package.swift")
        #expect(seed.contains("state == \"analytics\""))
        #expect(!package.contains("analytics-fixture"))
        #expect(!package.contains("radar-insights"))
        #expect(!package.contains("intelligence-efficiency"))
    }

    @Test("export is wired as a one-way save surface without an import handler")
    func exportIsOneWay() throws {
        let view = try text("Sources/ClaudeRadar/Features/Export/ExportView.swift")
        let manifest = try text("Sources/ClaudeRadar/Data/Export/ExportManifest.swift")
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
        #expect(contract.contains("https://codexradar.com/"))
        #expect(contract.contains("codex-radar-rendered-dom-v1"))
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
        let reader = try text("Sources/ClaudeRadar/Sources/CodexRadar/CodexRenderedIQHistoryPageReader.swift")
        let parser = try text("Sources/ClaudeRadar/Sources/CodexRadar/CodexRenderedIQHistoryDOMParser.swift")
        let lifecycle = try text("Sources/ClaudeRadar/Sources/CodexRadar/CodexRenderedPageLifecycle.swift")
        let export = try text("Sources/ClaudeRadar/Data/Export/ExportManifest.swift")
        let model = try text("Sources/ClaudeRadar/Features/Workspace/RadarWorkspaceModel.swift")

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
