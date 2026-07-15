import AppKit
import SwiftUI

@main
struct ClaudeRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let runtime: RadarAppRuntime
    private let workspaceModel: RadarWorkspaceModel
    private let settings: AppSettings

    init() {
        let settings = AppSettings()
        self.settings = settings
        let runtime = RadarAppRuntime(environment: .current(), refreshIntervalMinutes: settings.refreshIntervalMinutes)
        self.runtime = runtime
        workspaceModel = RadarWorkspaceModel(runtime: runtime)
    }

    var body: some Scene {
        Window("Claude Radar", id: "workspace") {
            RadarWorkspaceView(sourceID: .claudeCodeRadar, model: workspaceModel)
                .frame(minWidth: 820, minHeight: 560)
                .task { appDelegate.runtime = runtime }
        }
        .defaultSize(width: 1080, height: 720)
        .commands { AppCommands(model: workspaceModel) }

        MenuBarExtra("Claude Radar", systemImage: "scope") { MenuBarView(model: workspaceModel) }
            .menuBarExtraStyle(.window)

        Settings { SettingsView(settings: settings, runtime: runtime) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var runtime: RadarAppRuntime?
    private var terminationIsPending = false
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runtime else { return .terminateNow }
        guard !terminationIsPending else { return .terminateLater }
        terminationIsPending = true
        Task { @MainActor in await runtime.stop(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
