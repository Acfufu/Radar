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
        case codex
        #endif
    }

    let dataRoot: URL
    let fixtureMode: FixtureMode
    let onlineSourceEnabled: Bool

    var rawSamplesRoot: URL {
        dataRoot.appending(path: "RawSamples", directoryHint: .isDirectory)
    }

    func makeModelContainer() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: dataRoot.appending(path: "Radar.store"))
        return try RadarModelSchema.makeContainer(configuration: configuration)
    }

    var fixtureURL: URL? {
        #if DEBUG
        let name: String? = switch fixtureMode {
        case .valid: "claude-radar-valid"
        case .nullFields: "claude-radar-null-fields"
        case .invalid: "claude-radar-invalid"
        case .disabled, .online, .sequence, .ui, .codex: nil
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
        if mode == .ui, variables["RADAR_UI_SOURCE"] != nil {
            setenv(
                "RADAR_UI_SOURCE",
                debugInitialSourceID(fixtureMode: mode, variables: variables).rawValue,
                1
            )
        }
        let dataRoot = variables["RADAR_DATA_ROOT"].map {
            URL(filePath: $0, directoryHint: .isDirectory)
        } ?? defaultRoot
        #else
        let mode = FixtureMode.disabled
        let dataRoot = defaultRoot
        #endif

        #if DEBUG
        let onlineSourceEnabled = mode == .sequence || mode == .online || mode == .codex
        #else
        let onlineSourceEnabled = true
        #endif
        return AppEnvironment(
            dataRoot: dataRoot,
            fixtureMode: mode,
            onlineSourceEnabled: onlineSourceEnabled
        )
    }

    var initialSourceID: RadarSourceID {
        #if DEBUG
        Self.debugInitialSourceID(
            fixtureMode: fixtureMode,
            variables: ProcessInfo.processInfo.environment
        )
        #else
        .codexRadar
        #endif
    }

    func synchronizationEnabled(for sourceID: RadarSourceID) -> Bool {
        #if DEBUG
        guard onlineSourceEnabled else { return false }
        return switch fixtureMode {
        case .online: true
        case .sequence: sourceID == .claudeCodeRadar
        case .codex: sourceID == .codexRadar
        case .disabled, .valid, .nullFields, .invalid, .ui: false
        }
        #else
        onlineSourceEnabled
        #endif
    }

    func supportLevel(for sourceID: RadarSourceID) -> SupportLevel {
        synchronizationEnabled(for: sourceID) ? .authorized : .disabled
    }

    #if DEBUG
    static func debugInitialSourceID(
        fixtureMode: FixtureMode,
        variables: [String: String]
    ) -> RadarSourceID {
        guard fixtureMode == .ui else {
            return fixtureMode == .codex || fixtureMode == .online
                ? .codexRadar
                : .claudeCodeRadar
        }
        return switch variables["RADAR_UI_SOURCE"] {
        case "codexRadar", RadarSourceID.codexRadar.rawValue:
            .codexRadar
        case "sweBenchVerified", RadarSourceID.sweBenchVerified.rawValue:
            .sweBenchVerified
        case "claudeCodeRadar", RadarSourceID.claudeCodeRadar.rawValue:
            .claudeCodeRadar
        default:
            .claudeCodeRadar
        }
    }
    #endif
}
