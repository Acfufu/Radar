import SwiftUI

struct RadarWorkspaceView: View {
    let model: RadarWorkspaceModel
    @SceneStorage("workspaceDestination") private var destinationRaw = WorkspaceDestination.overview.rawValue

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RADAR_UI_SURFACE"] == "menu" {
            MenuBarView(model: model)
                .frame(minWidth: 400, idealWidth: 400, maxWidth: 400)
        } else {
            workspace
        }
        #else
        workspace
        #endif
    }

    private var workspace: some View {
        NavigationSplitView {
            List(selection: destinationBinding) {
                Section("数据来源") {
                    Picker("工作区", selection: sourceBinding) {
                        ForEach(model.sources) { source in
                            Text(source.displayName).tag(source.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("工作区")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.source.attributionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("导航") {
                    ForEach(WorkspaceDestination.allCases) { destination in
                        Label(destination.rawValue, systemImage: destination.icon).tag(destination)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Radar")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
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
        .task {
            #if DEBUG
            if let requested = ProcessInfo.processInfo.environment["RADAR_UI_DESTINATION"],
               let destination = WorkspaceDestination(rawValue: requested) {
                destinationRaw = destination.rawValue
            }
            #endif
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
    private var sourceBinding: Binding<RadarSourceID> {
        Binding(get: { model.selectedSourceID }, set: { model.selectSource($0) })
    }
}
