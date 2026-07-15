import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let runtime: RadarAppRuntime
    @State private var launchAtLogin = false
    @State private var dataActionMessage: String?

    var body: some View {
        TabView {
            Form {
                Picker("刷新间隔", selection: interval) { ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) 分钟").tag($0) } }
                Toggle("登录时启动", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, value in updateLoginItem(value) }
                LabeledContent("在线来源", value: runtime.environment.onlineSupportLevel == .disabled ? "当前构建未启用" : "仅开发实验")
            }.formStyle(.grouped).tabItem { Label("通用", systemImage: "gear") }
            Form {
                Button("清除规范化历史", role: .destructive) {
                    Task { dataActionMessage = await runtime.clearHistory() ? "规范化历史已清除；原始诊断样本保留。" : "无法清除规范化历史。" }
                }
                Button("清除原始诊断样本", role: .destructive) {
                    Task { dataActionMessage = await runtime.clearRawSamples() ? "原始诊断样本已清除；规范化历史保留。" : "无法清除原始诊断样本。" }
                }
                Button("在 Finder 中显示数据目录") { NSWorkspace.shared.activateFileViewerSelecting([runtime.environment.dataRoot]) }
                Text(runtime.environment.dataRoot.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let dataActionMessage { Text(dataActionMessage).font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("数据", systemImage: "externaldrive") }
            Form {
                LabeledContent("Claude Radar", value: "0.1.0")
                Link("Claude Code Radar 来源主页", destination: URL(string: "https://claudecoderadar.com/?lang=en")!)
                Text("数据来源：Claude Code Radar。其网站可公开访问，但未发现允许缓存、历史留存或再展示的明确复用许可；公开 Release 构建的在线来源保持禁用。")
                    .fixedSize(horizontal: false, vertical: true)
            }.formStyle(.grouped).tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 300)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    private var interval: Binding<Int> { Binding(get: { settings.refreshIntervalMinutes }, set: { value in
        settings.refreshIntervalMinutes = value
        Task { await runtime.updateRefreshInterval(minutes: value) }
    }) }
    private func updateLoginItem(_ enabled: Bool) {
        do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); settings.launchAtLogin = enabled }
        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}
