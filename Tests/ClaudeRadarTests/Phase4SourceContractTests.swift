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

    @Test("workspace is presented on fresh macOS 15 launches with macOS 14 compatibility")
    func workspaceLaunchBehavior() throws {
        let app = try text("Sources/ClaudeRadar/ClaudeRadarApp.swift")
        #expect(app.contains("@SceneBuilder"))
        #expect(app.contains("var body: some Scene {"))
        #expect(app.contains("private var workspaceScene: some Scene"))
        #expect(app.contains("if #available(macOS 15.0, *)"))
        #expect(app.contains(".restorationBehavior(.disabled)"))
        #expect(app.contains(".defaultLaunchBehavior(.presented)"))
        #expect(app.contains("} else {"))
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

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: root.appending(path: relative), encoding: .utf8)
    }
}
