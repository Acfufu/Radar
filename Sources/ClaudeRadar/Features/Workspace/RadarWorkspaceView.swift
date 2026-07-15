import SwiftUI

struct RadarWorkspaceView: View {
    let sourceID: RadarSourceID
    let model: RadarWorkspaceModel
    @SceneStorage("workspaceDestination") private var destinationRaw = WorkspaceDestination.overview.rawValue

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RADAR_UI_SURFACE"] == "menu" {
            MenuBarView(model: model)
                .frame(minWidth: 400, idealWidth: 400, maxWidth: 400)
                .task { await model.runtime.start() }
        } else {
            workspace
        }
        #else
        workspace
        #endif
    }

    private var workspace: some View {
        NavigationSplitView {
            List(WorkspaceDestination.allCases, selection: destinationBinding) { destination in
                Label(destination.rawValue, systemImage: destination.icon).tag(destination)
            }
            .listStyle(.sidebar)
            .navigationTitle("Claude Radar")
        } detail: {
            destinationView
                .toolbar {
                    ToolbarItem {
                        Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                            .keyboardShortcut("r")
                            .disabled(!RefreshActionAvailability.isEnabled(supportLevel: model.projection.supportLevel))
                    }
                    ToolbarItem { SettingsLink { Label("设置", systemImage: "gear") } }
                }
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
        .task {
            #if DEBUG
            if let requested = ProcessInfo.processInfo.environment["RADAR_UI_DESTINATION"],
               let destination = WorkspaceDestination(rawValue: requested) {
                destinationRaw = destination.rawValue
            }
            #endif
            if sourceID == .claudeCodeRadar { await model.runtime.start() }
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch destination {
        case .overview: OverviewView(projection: model.projection)
        case .models: ModelListView(projection: model.projection, history: model.history)
        case .trends: MetricTrendChart(projection: model.projection, history: model.history)
        case .sourceStatus: SourceStatusView(projection: model.projection)
        case .export: ExportView(runtime: model.runtime)
        }
    }
    private var destination: WorkspaceDestination { WorkspaceDestination(rawValue: destinationRaw) ?? .overview }
    private var destinationBinding: Binding<WorkspaceDestination?> {
        Binding(get: { destination }, set: { if let value = $0 { destinationRaw = value.rawValue } })
    }
}
