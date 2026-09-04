import AppKit
import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: RadarWorkspaceModel

    var body: some Commands {
        CommandMenu("Radar") {
            Button("打开工作区") {
                openWindow(id: "workspace")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")
            Button("刷新") { Task { await model.refresh() } }
                .keyboardShortcut("r")
                .disabled(!model.refreshAvailable)
            Button("关闭工作区") {
                WorkspaceWindowActions.closeTarget(from: NSApp.keyWindow)?.performClose(nil)
            }
            .keyboardShortcut("w")
        }
    }
}

@MainActor
enum WorkspaceWindowActions {
    static func closeTarget(from focusedWindow: NSWindow?) -> NSWindow? { focusedWindow }
}
