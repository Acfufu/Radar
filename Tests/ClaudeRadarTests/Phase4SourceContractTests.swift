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
        #expect(view.contains("NSSavePanel"))
        #expect(view.contains("runtime.export"))
        #expect(!view.lowercased().contains("fileimporter("))
        #expect(!view.lowercased().contains("openpanel"))
    }

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: root.appending(path: relative), encoding: .utf8)
    }
}
