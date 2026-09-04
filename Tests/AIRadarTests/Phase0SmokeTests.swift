import Foundation
import Testing

@Suite("Phase0SmokeTests")
struct Phase0SmokeTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("package and application scaffold are frozen")
    func scaffoldContract() throws {
        let manifest = try text("Package.swift")
        #expect(manifest.contains(".macOS(.v26)"))
        #expect(manifest.contains("swiftLanguageModes: [.v6]"))
        #expect(manifest.contains(".process(\"Resources\")"))
        #expect(exists("Sources/AIRadar/ClaudeRadarApp.swift"))
        #expect(exists("Sources/AIRadar/App/AppEnvironment.swift"))
        #expect(exists("Sources/AIRadar/App/AppSettings.swift"))
    }

    @Test("fixtures are bundled, small, JSON, and sanitized")
    func fixtureContract() throws {
        for fixture in ["claude-radar-valid", "claude-radar-null-fields", "claude-radar-invalid"] {
            let relativePath = "Sources/AIRadar/Resources/Fixtures/\(fixture).json"
            let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
            #expect(data.count > 20 && data.count < 20_000)
            #expect((try JSONSerialization.jsonObject(with: data)) is [String: Any])
            let lowered = String(decoding: data, as: UTF8.self).lowercased()
            for forbidden in ["authorization", "cookie", "api_key", "api-key", "bearer ", "@"] {
                #expect(!lowered.contains(forbidden))
            }
        }

    }

    @Test("bundle, scripts, and Run action exist")
    func packagingContract() throws {
        let plist = try text("Config/AIRadar-Info.plist")
        #expect(plist.contains("com.acfufu.ClaudeRadar"))
        #expect(plist.contains("26.0"))
        #expect(exists("Scripts/build-app.sh"))
        #expect(exists("script/build_and_run.sh"))
        let environment = try text(".codex/environments/environment.toml")
        #expect(environment.contains("command = \"./script/build_and_run.sh\""))
    }

    @Test("status and source contracts carry the Phase 0 truth")
    func documentationContract() throws {
        let status = try text("docs/implementation-status.md")
        for heading in ["Current Phase", "Completed", "In Progress", "Blocked", "Decisions Made", "Tests", "Manual Review Needed", "Scope Guard"] {
            #expect(status.contains("## \(heading)"))
        }
        let contract = try text("docs/source-contract.md")
        #expect(contract.contains("https://claudecoderadar.com/data/claude-code-radar.json"))
        #expect(contract.contains("https://claudecoderadar.com/api/model-ratings?history=10"))
        #expect(contract.contains("public online default: enabled"))
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
