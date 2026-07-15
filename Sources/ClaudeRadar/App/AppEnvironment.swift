import Foundation
import SwiftData

struct AppEnvironment: Sendable {
    enum FixtureMode: String, Sendable {
        case disabled
        #if DEBUG
        case valid
        case nullFields = "null-fields"
        case invalid
        case online
        case sequence
        case ui
        #endif
    }

    let dataRoot: URL
    let fixtureMode: FixtureMode
    let onlineSourceEnabled: Bool

    var onlineSupportLevel: SupportLevel {
        #if DEBUG
        onlineSourceEnabled ? .experimental : .disabled
        #else
        .disabled
        #endif
    }

    var rawSamplesRoot: URL {
        dataRoot.appending(path: "RawSamples", directoryHint: .isDirectory)
    }

    func makeModelContainer() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: dataRoot.appending(path: "Radar.store"))
        return try ModelContainer(
            for: BenchmarkSnapshotEntity.self,
            CommunitySnapshotEntity.self,
            SourceStatusSnapshotEntity.self,
            configurations: configuration
        )
    }

    var fixtureURL: URL? {
        #if DEBUG
        let name: String? = switch fixtureMode {
        case .valid: "claude-radar-valid"
        case .nullFields: "claude-radar-null-fields"
        case .invalid: "claude-radar-invalid"
        case .disabled, .online, .sequence, .ui: nil
        }
        return name.flatMap { Bundle.main.url(forResource: $0, withExtension: "json") }
        #else
        return nil
        #endif
    }

    static func current() -> AppEnvironment {
        let defaultRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "ClaudeRadar", directoryHint: .isDirectory)

        #if DEBUG
        let variables = ProcessInfo.processInfo.environment
        let requestedMode = variables["RADAR_FIXTURE_MODE"]
        let mode = requestedMode.flatMap(FixtureMode.init(rawValue:)) ?? .disabled
        let dataRoot = variables["RADAR_DATA_ROOT"].map {
            URL(filePath: $0, directoryHint: .isDirectory)
        } ?? defaultRoot
        #else
        let mode = FixtureMode.disabled
        let dataRoot = defaultRoot
        #endif

        #if DEBUG
        let onlineSourceEnabled = mode == .sequence || mode == .online
        #else
        let onlineSourceEnabled = false
        #endif
        return AppEnvironment(
            dataRoot: dataRoot,
            fixtureMode: mode,
            onlineSourceEnabled: onlineSourceEnabled
        )
    }
}
