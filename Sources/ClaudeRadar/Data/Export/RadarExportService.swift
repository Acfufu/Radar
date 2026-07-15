import Darwin
import Foundation

protocol RadarExportDataSource: Sendable {
    func beginExportSnapshot(includesRawSamples: Bool) async throws -> ExportSnapshotToken
    func endExportSnapshot(_ snapshot: ExportSnapshotToken) async
    func exportRecordCount(dataset: ExportDataset, range: ExportDateRange, snapshot: ExportSnapshotToken) async throws -> Int
    func exportRecords(dataset: ExportDataset, range: ExportDateRange, offset: Int, limit: Int, snapshot: ExportSnapshotToken) async throws -> [ExportRecord]
}

extension RadarExportDataSource {
    func beginExportSnapshot(includesRawSamples: Bool) async throws -> ExportSnapshotToken { .init(id: UUID(), cutoff: Date()) }
}

struct ExportSnapshotToken: Hashable, Sendable {
    let id: UUID
    let cutoff: Date
}

protocol RadarExportArchiver: Sendable {
    func archive(contentsOf directory: URL, to destination: URL) async throws
}

enum ExportDestinationPolicy: Sendable {
    case failIfExists
    case replaceExisting
}

struct ExportRequest: Sendable {
    let destination: URL
    let datasets: Set<ExportDataset>
    let range: ExportDateRange
    let pageSize: Int
    let includesRawSamples: Bool
    let destinationPolicy: ExportDestinationPolicy

    init(
        destination: URL,
        datasets: Set<ExportDataset> = Set(ExportDataset.normalized),
        range: ExportDateRange = .all,
        pageSize: Int = 500,
        includesRawSamples: Bool = false,
        destinationPolicy: ExportDestinationPolicy = .failIfExists
    ) {
        self.destination = destination
        self.datasets = datasets.subtracting([.rawSamples])
        self.range = range
        self.pageSize = pageSize
        self.includesRawSamples = includesRawSamples
        self.destinationPolicy = destinationPolicy
    }
}

struct ExportResult: Sendable {
    let destination: URL
    let manifest: ExportManifest
}

struct ExportProgress: Sendable {
    let completedPages: Int
    let totalPages: Int
    let dataset: ExportDataset?
}

enum ExportError: Error, Equatable {
    case invalidPageSize
    case invalidDestination
    case destinationExists
    case repositoryUnavailable
    case shortPage
    case archiveFailed(Int32)
}

actor RadarExportService {
    private let source: any RadarExportDataSource
    private let archiver: any RadarExportArchiver
    private let fileManager: FileManager
    private let appVersion: String

    init(
        source: any RadarExportDataSource,
        archiver: any RadarExportArchiver = SystemZipArchiver(),
        fileManager: FileManager = .default,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    ) {
        self.source = source
        self.archiver = archiver
        self.fileManager = fileManager
        self.appVersion = appVersion
    }

    func export(
        request: ExportRequest,
        exportedAt: Date = Date(),
        progress: (@Sendable (ExportProgress) async -> Void)? = nil
    ) async throws -> ExportResult {
        guard (100...5000).contains(request.pageSize) else { throw ExportError.invalidPageSize }
        guard safeDestination(request.destination) else { throw ExportError.invalidDestination }
        let destinationExists = fileManager.fileExists(atPath: request.destination.path)
        if destinationExists, request.destinationPolicy == .failIfExists { throw ExportError.destinationExists }

        let snapshot = try await source.beginExportSnapshot(includesRawSamples: request.includesRawSamples)
        do {
            let result = try await export(request: request, exportedAt: exportedAt, snapshot: snapshot, destinationExisted: destinationExists, progress: progress)
            await source.endExportSnapshot(snapshot)
            return result
        } catch {
            await source.endExportSnapshot(snapshot)
            throw error
        }
    }

    private func export(
        request: ExportRequest,
        exportedAt: Date,
        snapshot: ExportSnapshotToken,
        destinationExisted: Bool,
        progress: (@Sendable (ExportProgress) async -> Void)?
    ) async throws -> ExportResult {

        let parent = request.destination.deletingLastPathComponent().standardizedFileURL
        let temporaryRoot = parent.appending(path: ".ClaudeRadarExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let packageRoot = temporaryRoot.appending(path: "package", directoryHint: .isDirectory)
        let temporaryArchive = temporaryRoot.appending(path: "archive.zip")
        try fileManager.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let datasets = selectedDatasets(request)
        var entries: [ExportManifest.Dataset] = []
        for dataset in datasets {
            try Task.checkCancellation()
            let count = try await source.exportRecordCount(dataset: dataset, range: request.range, snapshot: snapshot)
            let pages = count == 0 ? 0 : (count + request.pageSize - 1) / request.pageSize
            entries.append(.init(name: dataset.rawValue, schemaVersion: 1, recordCount: count, pageCount: pages))
        }
        let totalPages = entries.reduce(0) { $0 + $1.pageCount }
        var completedPages = 0

        for (dataset, entry) in zip(datasets, entries) {
            try Task.checkCancellation()
            let directory = packageRoot.appending(path: dataset.rawValue, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            for pageIndex in 0..<entry.pageCount {
                try Task.checkCancellation()
                let records = try await source.exportRecords(
                    dataset: dataset,
                    range: request.range,
                    offset: pageIndex * request.pageSize,
                    limit: request.pageSize,
                    snapshot: snapshot
                )
                let expected = min(request.pageSize, entry.recordCount - pageIndex * request.pageSize)
                guard records.count == expected else { throw ExportError.shortPage }
                let envelope = PageEnvelope(
                    dataset: dataset.rawValue,
                    schemaVersion: 1,
                    page: pageIndex + 1,
                    pageSize: request.pageSize,
                    recordCount: records.count,
                    totalRecords: entry.recordCount,
                    hasNextPage: pageIndex + 1 < entry.pageCount,
                    records: records
                )
                let name = String(format: "page-%06d.json", pageIndex + 1)
                try JSONEncoder.export.encode(envelope).write(to: directory.appending(path: name), options: .atomic)
                completedPages += 1
                await progress?(.init(completedPages: completedPages, totalPages: totalPages, dataset: dataset))
            }
        }

        let manifest = ExportManifest(
            format: "claude-radar-export",
            formatVersion: 1,
            exportedAt: exportedAt,
            appVersion: appVersion,
            pageSize: request.pageSize,
            includesRawSamples: request.includesRawSamples,
            sources: [RadarSourceID.claudeCodeRadar.rawValue],
            dateRange: request.range,
            datasets: entries
        )
        try JSONEncoder.export.encode(manifest).write(to: packageRoot.appending(path: "manifest.json"), options: .atomic)
        try Task.checkCancellation()
        try await archiver.archive(contentsOf: packageRoot, to: temporaryArchive)
        try Task.checkCancellation()
        try install(temporaryArchive, at: request.destination, policy: request.destinationPolicy, existed: destinationExisted)
        return ExportResult(destination: request.destination, manifest: manifest)
    }

    private func selectedDatasets(_ request: ExportRequest) -> [ExportDataset] {
        var selected = ExportDataset.normalized.filter(request.datasets.contains)
        if request.includesRawSamples { selected.append(.rawSamples) }
        return selected
    }

    private func safeDestination(_ destination: URL) -> Bool {
        guard destination.pathExtension.lowercased() == "zip",
              destination.standardizedFileURL.path == destination.path,
              !destination.lastPathComponent.contains("/"),
              !destination.lastPathComponent.contains("\\") else { return false }
        var information = stat()
        if lstat(destination.path, &information) == 0 {
            return information.st_mode & S_IFMT != S_IFLNK
        }
        return errno == ENOENT
    }

    private func install(_ archive: URL, at destination: URL, policy: ExportDestinationPolicy, existed: Bool) throws {
        if existed {
            guard policy == .replaceExisting else { throw ExportError.destinationExists }
            _ = try fileManager.replaceItemAt(destination, withItemAt: archive, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: archive, to: destination)
        }
    }
}

actor SystemZipArchiver: RadarExportArchiver {
    private let executableURL: URL
    private let arguments: [String]?
    private(set) var activeProcessID: Int32?

    init(executableURL: URL = URL(filePath: "/usr/bin/zip"), arguments: [String]? = nil) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    func archive(contentsOf directory: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = directory
        process.arguments = arguments ?? ["-q", "-r", destination.path, "."]
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume(returning: ()) }
                do {
                    try process.run()
                    activeProcessID = process.processIdentifier
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            guard process.isRunning else { return }
            let processID = process.processIdentifier
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if kill(processID, 0) == 0 { _ = kill(processID, SIGKILL) }
            }
        }
        activeProcessID = nil
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw ExportError.archiveFailed(process.terminationStatus) }
    }
}
