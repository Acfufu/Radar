import AppKit
import SwiftUI

@main
struct ClaudeRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let workspaceModel: RadarWorkspaceModel
    @State private var settings: AppSettings

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let environment = AppEnvironment.current()
        let metadataStore = SyncMetadataStore(root: environment.dataRoot)
        let runtimes = [
            RadarSourceID.claudeCodeRadar: RadarAppRuntime(
                environment: environment,
                sourceID: .claudeCodeRadar,
                metadataStore: metadataStore,
                refreshIntervalMinutes: settings.refreshIntervalMinutes
            ),
            RadarSourceID.codexRadar: RadarAppRuntime(
                environment: environment,
                sourceID: .codexRadar,
                metadataStore: metadataStore,
                refreshIntervalMinutes: settings.refreshIntervalMinutes
            ),
            RadarSourceID.sweBenchVerified: RadarAppRuntime(
                environment: environment,
                sourceID: .sweBenchVerified,
                metadataStore: metadataStore,
                refreshIntervalMinutes: settings.refreshIntervalMinutes
            ),
        ]
        let model = RadarWorkspaceModel(
            runtimes: runtimes,
            selectedSourceID: environment.initialSourceID
        )
        workspaceModel = model
        appDelegate.model = model
    }

    var body: some Scene {
        Window("Claude Radar", id: "workspace") {
            RadarWorkspaceView(model: workspaceModel)
                .frame(minWidth: 820, minHeight: 560)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .commands { AppCommands(model: workspaceModel) }

        MenuBarExtra("Claude Radar", systemImage: "scope") {
            MenuBarView(model: workspaceModel)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
            .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, model: workspaceModel)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RadarWorkspaceModel?
    private var terminationIsPending = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let model else { return }
        Task { await model.start() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !terminationIsPending else { return .terminateLater }
        terminationIsPending = true
        Task { @MainActor in await model.stop(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
