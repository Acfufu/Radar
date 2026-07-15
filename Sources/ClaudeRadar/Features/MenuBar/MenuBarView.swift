import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let model: RadarWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "scope").font(.title2); VStack(alignment: .leading) { Text("Claude Radar").font(.headline); Text(freshness).font(.caption).foregroundStyle(.secondary) }; Spacer() }
            if let supportState = Self.presentation(for: model.projection).supportState {
                StateBanner(state: supportState, error: nil)
            }
            if let healthState = Self.presentation(for: model.projection).healthState {
                StateBanner(state: healthState, error: Self.presentation(for: model.projection).error)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("质量摘要").font(.caption).foregroundStyle(.secondary)
                ForEach(topThree) { row in HStack { Text(short(row.name)); Spacer(); Text(RadarFormat.decimal(row.benchmark.qualityScore)).monospacedDigit() } }
                if topThree.isEmpty { Text("暂无模型数据").foregroundStyle(.secondary) }
            }
            Divider()
            HStack { Text(WorkspaceCopy.quotaTitle).font(.caption).foregroundStyle(.secondary); Spacer(); Text(quota).font(.caption).monospacedDigit() }
            if let error = model.projection.latestError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2) }
            Divider()
            HStack {
                Button("刷新") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(!RefreshActionAvailability.isEnabled(supportLevel: model.projection.supportLevel))
                Button("打开工作区") { openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut("o")
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(16).frame(width: 400)
        .task { await model.runtime.start() }
    }
    static func presentation(for projection: WorkspaceProjection) -> BenchmarkPresentation {
        projection.benchmarkPresentation
    }
    private var topThree: [WorkspaceModelRow] { Array(model.projection.filteredModels(query: "", sort: .quality, ascending: false).prefix(3)) }
    private var freshness: String { "更新于 \(RadarFormat.date(model.projection.updatedAt))" }
    private var quota: String { guard let q = model.projection.sync?.sourceStatus.value?.quotaEstimates.first else { return "—" }; return "\(q.windowLabel) \(RadarFormat.decimal(q.usedPercent, suffix: "%"))" }
    private func short(_ text: String) -> String { text.count <= 30 ? text : String(text.prefix(27)) + "…" }
}
