import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(\.radarPalette) private var palette
    let settings: AppSettings
    let model: RadarWorkspaceModel
    @State private var launchAtLogin = false
    @State private var dataActionMessage: String?
    /// Nil on aggregate/placeholder stations; data actions fall back to the
    /// first real station so the boundary disclosures stay reachable.
    private var runtime: RadarAppRuntime? { model.runtime ?? model.fallbackRuntime }

    var body: some View {
        TabView {
            Form {
                Picker("刷新间隔", selection: interval) { ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) 分钟").tag($0) } }
                Picker("外观", selection: appearance) {
                    ForEach(AppAppearance.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                Toggle("登录时启动", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, value in updateLoginItem(value) }
                LabeledContent("当前工作区", value: model.stationDisplayName)
                LabeledContent("在线来源", value: runtime.map { $0.supportLevel == .disabled ? "当前构建未启用" : "已启用自动同步" } ?? "—")
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.canvas.color)
            .tabItem { Label("通用", systemImage: "gear") }
            Form {
                Button("清除规范化历史", role: .destructive) {
                    let sourceName = model.source?.displayName ?? model.stationDisplayName
                    guard let dataRuntime = self.runtime else { return }
                    Task { dataActionMessage = await dataRuntime.clearHistory() ? "当前来源（\(sourceName)）的规范化历史（含渲染预警、IQ 历史及同步元数据）已清除；原始诊断样本和其他来源保留。后续合法同步可能重新填充该来源数据。" : "无法清除当前来源（\(sourceName)）的规范化历史；未报告已清除数据。" }
                }
                Button("清除原始诊断样本", role: .destructive) {
                    guard let dataRuntime = self.runtime else { return }
                    Task { dataActionMessage = await dataRuntime.clearRawSamples() ? "原始诊断样本已清除；规范化历史（含渲染预警、IQ 历史及同步元数据）保留。" : "无法清除原始诊断样本；未报告已清除数据。" }
                }
                Button("在 Finder 中显示数据目录") { if let dataRuntime = self.runtime { NSWorkspace.shared.activateFileViewerSelecting([dataRuntime.environment.dataRoot]) } }
                if let dataRuntime = self.runtime { Text(dataRuntime.environment.dataRoot.path).font(.caption).foregroundStyle(palette.secondaryText.color).textSelection(.enabled) }
                if let dataActionMessage { Text(dataActionMessage).font(.caption).foregroundStyle(palette.secondaryText.color) }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.canvas.color)
            .tabItem { Label("数据", systemImage: "externaldrive") }
            Form {
                LabeledContent("Radar", value: appVersion)
                Link("Claude Code Radar 来源主页", destination: URL(string: "https://claudecoderadar.com/?lang=en")!)
                Link("Codex Radar 来源主页", destination: URL(string: "https://codexradar.com/")!)
                Text("数据来自 Codex 雷达 codexradar.com；额度类数值均为来源账户估算，从不代表个人用户用量。\nAI Radar is an independent open-source project and is not affiliated with codexradar.com (AI 雷达); the name is an independent choice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("AI Radar 为独立开源项目，与 codexradar.com 的 AI 雷达无关联，命名系独立选择。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("项目已允许三个公开来源自动同步、缓存规范化历史与再展示。Codex Radar 还通过非持久 WebKit 读取公开首页已渲染的官网预警；页面自有渲染请求由页面发起，Radar 不拦截或保存响应，只保存与导出规范化字段。官网预警与本地 IQ 拟合口径独立，受保护的完整 API 始终不在范围内。")
                    .fixedSize(horizontal: false, vertical: true)
                Text("效能排行读取公开端点 codexradar.com/data/intelligence-efficiency.json（公开 GET、无认证，站点级署名适用；经专属 8MiB 通道传输）。该数据由上游基于其受保护 API 派生发布；其溯源字段指向的 api.codexradar.com 受保护域与 deng 提交端点（/api/*）一律不在 Radar 的请求范围内。Fast 雷达实测读取公开端点 codexradar.com/data/fast-radar-history.json（公开 GET、无认证，同一禁域边界）。")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.canvas.color)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 300)
        .background(palette.canvas.color)
        .tint(palette.accent.color)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    private var interval: Binding<Int> { Binding(get: { settings.refreshIntervalMinutes }, set: { value in
        settings.refreshIntervalMinutes = value
        Task { await model.updateRefreshInterval(minutes: settings.refreshIntervalMinutes) }
    }) }
    private var appearance: Binding<AppAppearance> {
        Binding(get: { settings.appearance }, set: { settings.appearance = $0 })
    }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
    }
    private func updateLoginItem(_ enabled: Bool) {
        do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); settings.launchAtLogin = enabled }
        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}
