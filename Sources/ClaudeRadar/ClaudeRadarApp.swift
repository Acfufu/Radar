import AppKit
import SwiftUI

@main
struct ClaudeRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let workspaceModel: RadarWorkspaceModel
    @State private var settings: AppSettings
    @AppStorage("appearance") private var appearance = AppAppearance.system

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let environment = AppEnvironment.current()
        let metadataStore = SyncMetadataStore(root: environment.dataRoot)
        let exportArchiver: any RadarExportArchiver
        #if DEBUG
        if ProcessInfo.processInfo.environment["RADAR_UI_EXPORT_ARCHIVER"] == "blocking" {
            exportArchiver = DebugBlockingExportArchiver()
        } else {
            exportArchiver = SystemZipArchiver()
        }
        #else
        exportArchiver = SystemZipArchiver()
        #endif
        let runtimes = [
            RadarSourceID.claudeCodeRadar: RadarAppRuntime(
                environment: environment,
                sourceID: .claudeCodeRadar,
                metadataStore: metadataStore,
                exportArchiver: exportArchiver,
                refreshIntervalMinutes: settings.refreshIntervalMinutes
            ),
            RadarSourceID.codexRadar: RadarAppRuntime(
                environment: environment,
                sourceID: .codexRadar,
                metadataStore: metadataStore,
                exportArchiver: exportArchiver,
                refreshIntervalMinutes: settings.refreshIntervalMinutes,
                renderedWarningReaderFactory: { CodexRenderedWarningPageReader() }
            ),
            RadarSourceID.sweBenchVerified: RadarAppRuntime(
                environment: environment,
                sourceID: .sweBenchVerified,
                metadataStore: metadataStore,
                exportArchiver: exportArchiver,
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

    @SceneBuilder
    var body: some Scene {
        workspaceScene

        MenuBarExtra("Claude Radar", systemImage: "scope") {
            MenuBarView(model: workspaceModel)
                .radarAppStyle()
                .preferredColorScheme(appearance.colorScheme)
        }
            .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, model: workspaceModel)
                .radarAppStyle()
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    private var workspaceScene: some Scene {
        if #available(macOS 15.0, *) {
            return workspaceWindow.defaultLaunchBehavior(.presented)
        } else {
            return workspaceWindow
        }
    }

    private var workspaceWindow: some Scene {
        Window("Claude Radar", id: "workspace") {
            RadarWorkspaceView(model: workspaceModel)
                .radarAppStyle()
                .frame(minWidth: 820, minHeight: 508)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .commands { AppCommands(model: workspaceModel) }
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
