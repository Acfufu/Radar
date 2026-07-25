import SwiftUI

struct RadarWorkspaceView: View {
    @Environment(\.radarPalette) private var palette
    let model: RadarWorkspaceModel
    @SceneStorage("workspaceRoute") private var routeRaw = WorkspaceRoute.initial.storageKey

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
            List(selection: routeBinding) {
                Section {
                    Label("信息总览", systemImage: "rectangle.grid.1x2")
                        .tag(WorkspaceRoute.informationOverview)
                }
                Section("来源") {
                    ForEach(model.sources) { source in
                        Label(source.displayName, systemImage: source.id == .sweBenchVerified ? "checkmark.seal" : "scope")
                            .tag(WorkspaceRoute.source(source.id))
                    }
                }
                if let sourceID = route.sourceID,
                   let source = model.sources.first(where: { $0.id == sourceID }) {
                    Section(source.displayName) {
                        ForEach(model.destinations(for: sourceID)) { destination in
                            Label(destination.title(for: sourceID), systemImage: destination.icon)
                                .tag(WorkspaceRoute.sourcePage(sourceID, destination))
                        }
                        Text(source.attributionText)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.color)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    Label("导出", systemImage: "square.and.arrow.up")
                        .tag(WorkspaceRoute.export)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(palette.section.color)
            .navigationTitle("Radar")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            destinationView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvas.color)
                .toolbar {
                    ToolbarItem {
                        Button { Task { await refresh() } } label: { Label(refreshLabel, systemImage: "arrow.clockwise") }
                            .keyboardShortcut("r")
                            .disabled(!refreshEnabled)
                    }
                    ToolbarItem { SettingsLink { Label("设置", systemImage: "gear") } }
                }
        }
        .tint(palette.accent.color)
        .toolbarBackground(palette.section.color, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .task {
            #if DEBUG
            if let requestedSource = ProcessInfo.processInfo.environment["RADAR_UI_SOURCE"] {
                let sourceID = RadarSourceID(rawValue: requestedSource)
                model.selectSource(sourceID)
                routeRaw = WorkspaceRoute.source(sourceID).storageKey
            }
            if let requested = ProcessInfo.processInfo.environment["RADAR_UI_DESTINATION"],
               let destination = WorkspaceDestination(rawValue: requested) {
                routeRaw = WorkspaceRoute.sourcePage(model.selectedSourceID, destination).storageKey
            }
            #endif
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch route {
        case .informationOverview:
            InformationOverviewView(model: model) { sourceID in
                model.selectSource(sourceID)
                routeRaw = WorkspaceRoute.source(sourceID).storageKey
            }
        case .source(let sourceID):
            sourceView(model.defaultDestination(for: sourceID), sourceID: sourceID)
        case .sourcePage(let sourceID, let destination):
            sourceView(destination, sourceID: sourceID)
        case .export:
            ExportView(runtime: model.runtime)
        }
    }

    @ViewBuilder private func sourceView(_ destination: WorkspaceDestination, sourceID: RadarSourceID) -> some View {
        let projection = model.projection(for: sourceID) ?? model.projection
        let history = model.history(for: sourceID)
        switch destination {
        case .overview:
            OverviewView(
                projection: projection,
                history: history,
                refreshIntervalMinutes: model.refreshIntervalMinutes
            )
        case .decisionLens:
            DecisionLensPageView(projection: projection)
        case .models:
            if sourceID == .sweBenchVerified {
                SWEBenchLeaderboardView(projection: projection, history: history)
            } else {
                ModelListView(projection: projection, history: history)
            }
        case .trends:
            MetricTrendChart(projection: projection, history: history)
        case .sourceStatus:
            if sourceID == .sweBenchVerified {
                SWEBenchProvenanceView(projection: projection)
            } else {
                SourceStatusView(projection: projection)
            }
        case .export: ExportView(runtime: model.runtime)
        }
    }

    private var route: WorkspaceRoute { WorkspaceRoute(storageKey: routeRaw) }
    private var routeBinding: Binding<WorkspaceRoute?> {
        Binding(
            get: { route },
            set: { value in
                guard let value else { return }
                if let sourceID = value.sourceID { model.selectSource(sourceID) }
                routeRaw = value.storageKey
            }
        )
    }

    private var refreshLabel: String {
        if route == .informationOverview { return "读取全部" }
        if route.sourceID == .sweBenchVerified { return "读取最新" }
        return "刷新"
    }

    private var refreshEnabled: Bool {
        if route == .informationOverview {
            return model.sources.contains { RefreshActionAvailability.isEnabled(supportLevel: $0.supportLevel) }
        }
        return RefreshActionAvailability.isEnabled(supportLevel: model.projection.supportLevel)
    }

    private func refresh() async {
        if route == .informationOverview {
            await model.refreshAll()
        } else {
            await model.refresh()
        }
    }
}
