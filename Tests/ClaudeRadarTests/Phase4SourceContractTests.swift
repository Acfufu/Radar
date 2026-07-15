import Foundation
import Testing

@Suite("Phase4SourceContractTests")
struct Phase4SourceContractTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("workspace is singleton and source homepage is exact")
    func sceneAndHomepage() throws {
        let app = try text("Sources/ClaudeRadar/ClaudeRadarApp.swift")
        let commands = try text("Sources/ClaudeRadar/App/AppCommands.swift")
        #expect(app.contains("Window(\"Claude Radar\", id: \"workspace\")"))
        #expect(!app.contains("WindowGroup(\"Claude Radar\""))
        #expect(commands.contains("Button(\"关闭工作区\")"))
        let status = try text("Sources/ClaudeRadar/Features/SourceStatus/SourceStatusView.swift")
        #expect(status.contains("https://claudecoderadar.com/?lang=en"))
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
