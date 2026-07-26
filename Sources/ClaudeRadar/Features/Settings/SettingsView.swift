import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(\.radarPalette) private var palette
    let settings: AppSettings
    let model: RadarWorkspaceModel
    @State private var launchAtLogin = false
    @State private var dataActionMessage: String?
    private var runtime: RadarAppRuntime { model.runtime }

    var body: some View {
        TabView {
            Form {
                Picker("刷新间隔", selection: interval) { ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) 分钟").tag($0) } }
                Picker("外观", selection: appearance) {
                    ForEach(AppAppearance.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                Toggle("登录时启动", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, value in updateLoginItem(value) }
                LabeledContent("当前工作区", value: model.source.displayName)
                LabeledContent("在线来源", value: runtime.supportLevel == .disabled ? "当前构建未启用" : "已启用自动同步")
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.canvas.color)
            .tabItem { Label("通用", systemImage: "gear") }
            Form {
                Button("清除规范化历史", role: .destructive) {
                    Task { dataActionMessage = await runtime.clearHistory() ? "规范化历史（含官网预警及同步元数据）已清除；原始诊断样本保留。" : "无法清除规范化历史。" }
                }
                Button("清除原始诊断样本", role: .destructive) {
                    Task { dataActionMessage = await runtime.clearRawSamples() ? "原始诊断样本已清除；规范化历史（含官网预警）保留。" : "无法清除原始诊断样本。" }
                }
                Button("在 Finder 中显示数据目录") { NSWorkspace.shared.activateFileViewerSelecting([runtime.environment.dataRoot]) }
                Text(runtime.environment.dataRoot.path).font(.caption).foregroundStyle(palette.secondaryText.color).textSelection(.enabled)
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
                Text("项目已允许三个公开来源自动同步、缓存规范化历史与再展示。Codex Radar 还通过非持久 WebKit 读取公开首页已渲染的官网预警；页面自有渲染请求由页面发起，Radar 不拦截或保存响应，只保存与导出规范化字段。官网预警与本地 IQ 拟合口径独立，受保护的完整 API 始终不在范围内。")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.canvas.color)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 212)
        .background(palette.canvas.color)
        .tint(palette.accent.color)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    private var interval: Binding<Int> { Binding(get: { settings.refreshIntervalMinutes }, set: { value in
        settings.refreshIntervalMinutes = value
        Task { await runtime.updateRefreshInterval(minutes: value) }
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
