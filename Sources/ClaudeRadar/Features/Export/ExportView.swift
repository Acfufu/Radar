import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.radarPalette) private var palette
    let runtime: RadarAppRuntime
    @State private var datasets = Set(ExportDataset.normalized)
    @State private var includesRawSamples = false
    @State private var pageSize = 500
    @State private var limitsStart = false
    @State private var limitsEnd = false
    @State private var start = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var progress: ExportProgress?
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("日期范围") {
                Toggle("限制起始日期", isOn: $limitsStart)
                if limitsStart { DatePicker("起始", selection: $start) }
                Toggle("限制结束日期", isOn: $limitsEnd)
                if limitsEnd { DatePicker("结束", selection: $end) }
            }
            Section("数据集") {
                ForEach(ExportDataset.normalized, id: \.self) { dataset in
                    Toggle(datasetTitle(dataset), isOn: datasetBinding(dataset))
                }
                Toggle("包含最近原始样本", isOn: $includesRawSamples)
                Text("原始样本默认关闭，仅导出当前受限保留集合。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("分页") {
                Stepper("每页 \(pageSize) 条", value: $pageSize, in: 100...5000, step: 100)
            }
            Section {
                HStack {
                    Button("导出 ZIP…", action: beginExport)
                        .disabled(datasets.isEmpty || exportTask != nil || invalidRange)
                    if exportTask != nil { Button("取消", role: .cancel) { exportTask?.cancel() } }
                    if let exportedURL {
                        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) }
                    }
                }
                if let progress {
                    ProgressView(value: Double(progress.completedPages), total: Double(max(progress.totalPages, 1))) {
                        Text("正在写入 \(progress.dataset.map(datasetTitle) ?? "导出包")")
                    } currentValueLabel: {
                        Text("\(progress.completedPages) / \(progress.totalPages) 页")
                    }
                }
                if let exportedURL {
                    Label("已导出：\(exportedURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(palette.positive.color)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.negative.color)
                }
                if invalidRange { Text("结束日期必须晚于起始日期。").foregroundStyle(palette.negative.color) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(palette.canvas.color)
        .tint(palette.accent.color)
        .navigationTitle("导出")
        .padding(RadarStyle.compactSpacing)
        .onDisappear { exportTask?.cancel() }
    }

    private var invalidRange: Bool { limitsStart && limitsEnd && start > end }

    private func datasetBinding(_ dataset: ExportDataset) -> Binding<Bool> {
        Binding(
            get: { datasets.contains(dataset) },
            set: { selected in
                if selected { datasets.insert(dataset) } else { datasets.remove(dataset) }
            }
        )
    }

    private func beginExport() {
        guard let destination = exportDestination() else { return }
        progress = nil
        exportedURL = nil
        errorMessage = nil
        let request = ExportRequest(
            destination: destination,
            datasets: datasets,
            range: .init(start: limitsStart ? start : nil, end: limitsEnd ? end : nil),
            pageSize: pageSize,
            includesRawSamples: includesRawSamples,
            destinationPolicy: .replaceExisting
        )
        exportTask = Task {
            do {
                let result = try await runtime.export(request: request) { update in
                    await MainActor.run { progress = update }
                }
                try Task.checkCancellation()
                exportedURL = result.destination
                NSWorkspace.shared.activateFileViewerSelecting([result.destination])
            } catch is CancellationError {
                errorMessage = "导出已取消，未留下不完整文件。"
            } catch {
                errorMessage = "导出失败：\(safeExportMessage(error))"
            }
            exportTask = nil
        }
    }

    private func exportDestination() -> URL? {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["RADAR_UI_EXPORT_DESTINATION"] {
            return URL(filePath: path).standardizedFileURL
        }
        #endif
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ClaudeRadarExport-\(filenameTimestamp()).zip"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func datasetTitle(_ dataset: ExportDataset) -> String {
        switch dataset {
        case .models: "模型"
        case .benchmarkRuns: "Benchmark 运行"
        case .communityRatings: "社区评分"
        case .sourceStatus: "来源状态"
        case .rawSamples: "原始样本"
        }
    }

    private func filenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func safeExportMessage(_ error: Error) -> String {
        switch error {
        case ExportError.repositoryUnavailable: "本地数据仓库尚未就绪"
        case ExportError.invalidPageSize: "分页大小无效"
        case ExportError.invalidDestination: "请选择 ZIP 文件"
        case ExportError.destinationExists: "目标文件已存在"
        default: "无法完成 ZIP 导出"
        }
    }
}
