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
                // Sidebar section order is fixed by spec §4.1: aggregate first,
                // then real stations, then the 即将开放 placeholder group.
                Section {
                    Label("聚合站", systemImage: "rectangle.grid.1x2")
                        .foregroundStyle(route == .informationOverview ? palette.accent.color : palette.primaryText.color)
                        .tag(WorkspaceRoute.informationOverview)
                }
                Section("来源") {
                    ForEach(model.sources) { source in
                        Label(source.displayName, systemImage: source.id == .sweBenchVerified ? "checkmark.seal" : "scope")
                            .foregroundStyle(
                                (route == .source(source.id) || route.sourceID == source.id)
                                    ? palette.accent.color : palette.primaryText.color
                            )
                            .tag(WorkspaceRoute.source(source.id))
                    }
                }
                Section("即将开放") {
                    ForEach(UpcomingStation.allCases) { station in
                        Label(station.displayName, systemImage: "sparkles")
                            .foregroundStyle(
                                route == .upcoming(station) ? palette.accent.color : palette.secondaryText.color
                            )
                            .tag(WorkspaceRoute.upcoming(station))
                    }
                }
                if let sourceID = route.sourceID,
                   let source = model.sources.first(where: { $0.id == sourceID }) {
                    Section(source.displayName) {
                        ForEach(model.destinations(for: sourceID)) { destination in
                            Label(destination.title(for: sourceID), systemImage: destination.icon)
                                .foregroundStyle(route == .sourcePage(sourceID, destination) ? palette.accent.color : palette.primaryText.color)
                                .tag(WorkspaceRoute.sourcePage(sourceID, destination))
                        }
                        Text(source.attributionText)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.color)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(palette.section.color)
            .navigationTitle("AI Radar")
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
            // Scene restoration can asynchronously overwrite programmatic
            // SceneStorage writes made before it completes, so the fixture
            // routing hooks apply one beat later (DEBUG only).
            try? await Task.sleep(nanoseconds: 400_000_000)
            if ProcessInfo.processInfo.environment["RADAR_UI_SOURCE"] != nil {
                let station = AppEnvironment.debugInitialStation(
                    variables: ProcessInfo.processInfo.environment
                )
                model.selectSource(station)
                routeRaw = WorkspaceRoute.storageKey(for: station)
            }
            if let requested = ProcessInfo.processInfo.environment["RADAR_UI_DESTINATION"],
               let destination = WorkspaceDestination(rawValue: requested),
               let sourceID = model.selectedSourceID {
                routeRaw = WorkspaceRoute.sourcePage(sourceID, destination).storageKey
            }
            #endif
            routeRaw = model.restoreRoute(WorkspaceRoute(storageKey: routeRaw)).storageKey
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
            if let sourceID = model.selectedSourceID {
                sourceView(.export, sourceID: sourceID)
            } else {
                stationPlaceholder
            }
        case .upcoming(let station):
            upcomingPlaceholder(station)
        }
    }

    /// Placeholder for stations selected outside the real-source picker
    /// before the P1 sidebar sections land.
    private var stationPlaceholder: some View {
        VStack(spacing: RadarStyle.compactSpacing) {
            Image(systemName: "square.dashed")
                .font(.largeTitle)
                .foregroundStyle(palette.secondaryText.color)
            Text("此站点在此构建中不可用")
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .radarPage()
    }

    private func upcomingPlaceholder(_ station: UpcomingStation) -> some View {
        VStack(spacing: RadarStyle.compactSpacing) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(palette.accent.color)
            Text("即将开放").font(.title2.bold())
            Text(station.displayName)
                .foregroundStyle(palette.secondaryText.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .radarPage()
    }

    @ViewBuilder private func sourceView(_ destination: WorkspaceDestination, sourceID: RadarSourceID) -> some View {
        if let projection = model.projection(for: sourceID) ?? model.fallbackProjection {
            sourceContent(destination, sourceID: sourceID, projection: projection)
        } else {
            stationPlaceholder
        }
    }

    @ViewBuilder private func sourceContent(
        _ destination: WorkspaceDestination,
        sourceID: RadarSourceID,
        projection: WorkspaceProjection
    ) -> some View {
        let history = model.history(for: sourceID)
        switch destination {
        case .overview where sourceID == .codexRadar:
            // Spec §4.2 row 1: speed overview fuses the overview with the
            // model-tier list; official 24h trend card stays inside.
            CodexSpeedOverviewPage(
                projection: projection,
                history: history,
                refreshIntervalMinutes: model.refreshIntervalMinutes
            )
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
        case .intelligenceCenter:
            // Retired as a destination (spec §4.2); reachable only via a stale
            // persisted key, which normalizedRoute already maps away.
            CodexIntelligenceCenterView(projection: projection, history: history)
        case .alertsRecommendations:
            if sourceID == .codexRadar {
                AlertsRecommendationsPage(projection: projection)
            } else {
                stationPlaceholder
            }
        case .efficiencyPK:
            CodexEfficiencyPKPage(projection: projection, history: history)
        case .quotaRadar:
            CodexQuotaRadarPage(projection: projection)
        case .fastRadar:
            CodexFastRadarPage()
        case .historyComparison:
            CodexHistoryComparisonPage(projection: projection, history: history)
        case .tiboRadar:
            CodexTiboRadarPage(projection: projection)
        case .communityHub:
            CodexCommunityHubPage()
        case .sourceStatus:
            if sourceID == .sweBenchVerified {
                SWEBenchProvenanceView(projection: projection)
            } else {
                SourceStatusView(projection: projection)
            }
        case .export: ExportView(runtime: model.runtime(for: sourceID) ?? model.runtime ?? model.fallbackRuntime!)
        case .efficiencyPK, .fastRadar, .historyComparison, .tiboRadar, .communityHub:
            // P1b lands these pages; type-level routing exists since P1a.
            Text("\(destination.rawValue) 页面将在后续提交中提供")
                .foregroundStyle(palette.secondaryText.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .radarPage()
        }
    }

    private var route: WorkspaceRoute { model.normalizedRoute(WorkspaceRoute(storageKey: routeRaw)) }
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
            return model.refreshAvailable
        }
        if case .upcoming = route { return false }
        return model.refreshAvailable
    }

    private func refresh() async {
        if route == .informationOverview {
            await model.refreshAll()
        } else {
            await model.refresh()
        }
    }
}
