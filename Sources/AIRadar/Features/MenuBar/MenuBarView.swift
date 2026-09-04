import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.radarPalette) private var palette
    @Environment(\.openWindow) private var openWindow
    let model: RadarWorkspaceModel

    var body: some View {
        let benchmark = presentation
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            HStack {
                Image(systemName: "scope")
                    .font(.title2)
                    .foregroundStyle(palette.accent.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.source.displayName).font(.headline)
                    Text(freshness).font(.caption).foregroundStyle(palette.secondaryText.color)
                }
                Spacer()
            }
            .radarPanel()
            Picker("工作区", selection: sourceBinding) {
                ForEach(model.sources) { source in Text(source.displayName).tag(source.id) }
            }
            Text(model.source.attributionText).font(.caption2).foregroundStyle(palette.secondaryText.color)
            if let supportState = benchmark.supportState {
                StateBanner(state: supportState, error: nil, sourceName: model.source.displayName)
            }
            if let healthState = benchmark.healthState {
                StateBanner(state: healthState, error: benchmark.error, sourceName: model.source.displayName)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(metric.qualityLabel) 摘要").font(.caption).foregroundStyle(palette.secondaryText.color)
                ForEach(topThree) { row in HStack { Text(row.name).fixedSize(horizontal: false, vertical: true); Spacer(); Text(metric.formattedQuality(row.benchmark.qualityScore)).monospacedDigit() } }
                if topThree.isEmpty { Text("\(metric.qualityLabel) \(metric.unavailableValue)").foregroundStyle(palette.secondaryText.color) }
            }
            .radarPanel()
            Divider().overlay(palette.divider.color)
            HStack { Text(WorkspaceCopy.quotaTitle(for: model.source)).font(.caption).foregroundStyle(palette.secondaryText.color); Spacer(); Text(quota).font(.caption).monospacedDigit() }
            if let error = model.projection.latestError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(palette.negative.color).lineLimit(2) }
            Divider().overlay(palette.divider.color)
            HStack {
                Button("刷新") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(!RefreshActionAvailability.isEnabled(supportLevel: model.projection.supportLevel))
                Button("打开工作区") { openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut("o")
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(RadarStyle.cardSpacing)
        .frame(width: 400)
        .background(palette.canvas.color)
    }
    static func presentation(for projection: WorkspaceProjection) -> BenchmarkPresentation {
        WorkspacePresentation.benchmark(for: projection)
    }
    private var presentation: BenchmarkPresentation { Self.presentation(for: model.projection) }
    private var metric: WorkspaceMetricPresentation { WorkspacePresentation.metric(for: model.selectedSourceID) }
    private var topThree: [WorkspaceModelRow] { Array(model.projection.filteredModels(query: "", sort: .quality, ascending: false).prefix(3)) }
    private var freshness: String { "更新于 \(RadarFormat.date(model.projection.updatedAt))" }
    private var quota: String {
        guard let quota = model.projection.sync?.sourceStatus.value?.quotaEstimates.first else { return "—" }
        if let usedPercent = quota.usedPercent { return "\(quota.windowLabel) \(RadarFormat.decimal(usedPercent, suffix: "%"))" }
        return quota.estimatedValueUSD.map { "\(quota.windowLabel) $\(RadarFormat.decimal($0))" } ?? quota.windowLabel
    }
    private var sourceBinding: Binding<RadarSourceID> {
        Binding(get: { model.selectedSourceID }, set: { model.selectSource($0) })
    }
}
