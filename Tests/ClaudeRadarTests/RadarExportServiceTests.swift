import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("RadarExportServiceTests", .serialized)
struct RadarExportServiceTests {
    @Test("501 records are written as fixed-width pages and a truthful manifest")
    func pagedPackageBoundary() async throws {
        // Given
        let root = try temporaryDirectory()
        let destination = root.appending(path: "fixture.zip")
        let source = ExportFixtureSource(counts: [.benchmarkRuns: 501])
        let service = RadarExportService(source: source, archiver: SystemZipArchiver())

        // When
        let result = try await service.export(
            request: ExportRequest(destination: destination, datasets: [.benchmarkRuns], pageSize: 500),
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        // Then
        #expect(result.destination == destination)
        let inspection = try unzip(destination, into: root.appending(path: "inspection"))
        let manifest = try JSONDecoder.export.decode(ExportManifest.self, from: Data(contentsOf: inspection.appending(path: "manifest.json")))
        #expect(manifest.format == "claude-radar-export")
        #expect(manifest.formatVersion == 1)
        #expect(manifest.datasets == [.init(name: "benchmark-runs", schemaVersion: 1, recordCount: 501, pageCount: 2)])
        let first = try JSONDecoder.export.decode(PageEnvelope.self, from: Data(contentsOf: inspection.appending(path: "benchmark-runs/page-000001.json")))
        let second = try JSONDecoder.export.decode(PageEnvelope.self, from: Data(contentsOf: inspection.appending(path: "benchmark-runs/page-000002.json")))
        #expect(first.recordCount == 500)
        #expect(first.hasNextPage)
        #expect(second.recordCount == 1)
        #expect(!second.hasNextPage)
        #expect(await source.maximumRequestedPageSize == 500)
    }

    @Test(arguments: [0, 500])
    func zeroAndExactPageBoundaries(recordCount: Int) async throws {
        // Given
        let root = try temporaryDirectory()
        let destination = root.appending(path: "boundary.zip")
        let source = ExportFixtureSource(counts: [.models: recordCount])

        // When
        _ = try await RadarExportService(source: source, archiver: SystemZipArchiver()).export(
            request: ExportRequest(destination: destination, datasets: [.models]),
            exportedAt: .init(timeIntervalSince1970: 1_800_000_000)
        )

        // Then
        let inspection = try unzip(destination, into: root.appending(path: "inspection"))
        let manifest = try JSONDecoder.export.decode(ExportManifest.self, from: Data(contentsOf: inspection.appending(path: "manifest.json")))
        #expect(manifest.datasets.first?.recordCount == recordCount)
        #expect(manifest.datasets.first?.pageCount == (recordCount == 0 ? 0 : 1))
        #expect(FileManager.default.fileExists(atPath: inspection.appending(path: "models/page-000001.json").path) == (recordCount > 0))
    }

    @Test("raw samples require explicit opt-in and Decimal/null values remain strings/null")
    func rawOptInAndJSONValues() async throws {
        // Given
        let root = try temporaryDirectory()
        let source = ExportFixtureSource(counts: [.models: 1, .rawSamples: 1])
        let withoutRaw = root.appending(path: "without.zip")
        let withRaw = root.appending(path: "with.zip")
        let service = RadarExportService(source: source, archiver: SystemZipArchiver())

        // When
        _ = try await service.export(request: .init(destination: withoutRaw, datasets: [.models]), exportedAt: .init(timeIntervalSince1970: 1))
        _ = try await service.export(request: .init(destination: withRaw, datasets: [.models], includesRawSamples: true), exportedAt: .init(timeIntervalSince1970: 1))

        // Then
        let noRaw = try unzip(withoutRaw, into: root.appending(path: "no-raw"))
        let yesRaw = try unzip(withRaw, into: root.appending(path: "yes-raw"))
        #expect(!FileManager.default.fileExists(atPath: noRaw.appending(path: "raw-samples").path))
        #expect(FileManager.default.fileExists(atPath: yesRaw.appending(path: "raw-samples/page-000001.json").path))
        let page = try JSONSerialization.jsonObject(with: Data(contentsOf: noRaw.appending(path: "models/page-000001.json"))) as? [String: Any]
        let record = (page?["records"] as? [[String: Any]])?.first
        #expect(record?["decimal"] as? String == "123.4500")
        #expect(record?["missing"] is NSNull)
    }

    @Test("existing destinations fail safely and cancellation removes all partial siblings")
    func destinationAndCancellationCleanup() async throws {
        // Given
        let root = try temporaryDirectory()
        let existing = root.appending(path: "existing.zip")
        try Data("keep".utf8).write(to: existing)
        let source = ExportFixtureSource(counts: [.models: 501], cancelAfterFirstPage: true)
        let service = RadarExportService(source: source, archiver: SystemZipArchiver())

        // When
        await #expect(throws: ExportError.destinationExists) {
            try await service.export(request: .init(destination: existing, datasets: [.models]))
        }

        // Then
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
        let cancelled = root.appending(path: "cancelled.zip")
        await #expect(throws: CancellationError.self) {
            try await service.export(request: .init(destination: cancelled, datasets: [.models]))
        }
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".ClaudeRadarExport-") })
        #expect(await source.endedSnapshotCount == 1)
    }

    @Test("stable content re-exports identically and archive failures preserve an existing destination")
    func deterministicContentAndFailureCleanup() async throws {
        // Given
        let root = try temporaryDirectory()
        let first = root.appending(path: "first.zip")
        let second = root.appending(path: "second.zip")
        let source = ExportFixtureSource(counts: [.models: 501, .sourceStatus: 1])
        let service = RadarExportService(source: source, archiver: SystemZipArchiver(), appVersion: "1.0.0")
        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)

        // When
        _ = try await service.export(request: .init(destination: first, datasets: [.models, .sourceStatus]), exportedAt: exportedAt)
        _ = try await service.export(request: .init(destination: second, datasets: [.models, .sourceStatus]), exportedAt: exportedAt)

        // Then
        let firstTree = try unzip(first, into: root.appending(path: "first-tree"))
        let secondTree = try unzip(second, into: root.appending(path: "second-tree"))
        #expect(try treeHash(firstTree) == treeHash(secondTree))

        let existing = root.appending(path: "preserved.zip")
        try Data("original".utf8).write(to: existing)
        let failing = RadarExportService(source: source, archiver: FailingArchiver())
        await #expect(throws: ExportFixtureFailure.self) {
            try await failing.export(request: .init(destination: existing, datasets: [.models], destinationPolicy: .replaceExisting))
        }
        #expect(try Data(contentsOf: existing) == Data("original".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".ClaudeRadarExport-") })
        #expect(await source.endedSnapshotCount == 3)
    }

    @Test(arguments: [99, 5_001])
    func pageSizeBoundaryRejectsInvalidValues(pageSize: Int) async throws {
        // Given
        let root = try temporaryDirectory()
        let service = RadarExportService(source: ExportFixtureSource(counts: [:]), archiver: SystemZipArchiver())

        // When
        await #expect(throws: ExportError.invalidPageSize) {
            try await service.export(request: .init(destination: root.appending(path: "invalid.zip"), pageSize: pageSize))
        }

        // Then
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("repository pages 501 persisted snapshots without returning more than the requested limit")
    func repositoryBoundedPaging() async throws {
        // Given
        let root = try temporaryDirectory()
        let container = try RadarModelSchema.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        var expectedIDs: [Int: String] = [:]
        for index in (0..<501).reversed() {
            let fetchedAt = Date(timeIntervalSince1970: TimeInterval(index))
            let dataset = exportBenchmark(index: index, fetchedAt: fetchedAt)
            let fingerprint = try ContentFingerprint.benchmark(dataset)
            expectedIDs[index] = fingerprint
            context.insert(BenchmarkSnapshotEntity(
                sourceID: .claudeCodeRadar,
                fingerprint: fingerprint,
                fetchedAt: fetchedAt,
                seriesRevision: dataset.seriesRevision,
                encodedDataset: try JSONEncoder.radar.encode(dataset)
            ))
        }
        try context.save()
        let repository = RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root))

        // When
        let snapshot = try await repository.beginExportSnapshot()
        let count = try await repository.exportRecordCount(dataset: .benchmarkRuns, range: .all, snapshot: snapshot)
        let first = try await repository.exportRecords(dataset: .benchmarkRuns, range: .all, offset: 0, limit: 500, snapshot: snapshot)
        let last = try await repository.exportRecords(dataset: .benchmarkRuns, range: .all, offset: 500, limit: 500, snapshot: snapshot)
        await repository.endExportSnapshot(snapshot)

        // Then
        #expect(count == 501)
        #expect(first.count == 500)
        #expect(last.count == 1)
        #expect(first.first?.fields["id"] == expectedIDs[0].map(ExportJSONValue.string))
        #expect(last.first?.fields["id"] == expectedIDs[500].map(ExportJSONValue.string))
    }

    @Test("repository export lease freezes pages while insertion and clear wait for release")
    func snapshotLeaseConsistency() async throws {
        // Given
        let root = try temporaryDirectory()
        let fixture = try exportRepository(root: root, count: 101)
        let destination = root.appending(path: "leased.zip")
        let gate = ExportPageGate()
        let service = RadarExportService(source: fixture.repository, archiver: SystemZipArchiver())
        let exportTask = Task {
            try await service.export(
                request: .init(destination: destination, datasets: [.benchmarkRuns], pageSize: 100),
                exportedAt: .init(timeIntervalSince1970: 1_800_000_000)
            ) { update in
                if update.completedPages == 1 { await gate.pauseAfterFirstPage() }
            }
        }
        await gate.waitUntilPaused()
        let mutations = MutationProbe()
        let insertTask = Task {
            await mutations.markInsertAttempted()
            _ = try await fixture.repository.insertBenchmark(exportBenchmark(index: 999, fetchedAt: .init(timeIntervalSince1970: 999)))
            await mutations.markInsertCompleted()
        }
        let clearTask = Task {
            await mutations.markClearAttempted()
            try await fixture.repository.deleteAll()
            await mutations.markClearCompleted()
        }
        await mutations.waitForAttempts()
        for _ in 0..<20 { await Task.yield() }

        // When
        let beforeRelease = await mutations.completed
        await gate.release()
        let result = try await exportTask.value
        _ = try await (insertTask.value, clearTask.value)

        // Then
        #expect(beforeRelease == [])
        #expect(await mutations.completed == [.insert, .clear])
        #expect(result.manifest.datasets.first?.recordCount == 101)
        let inspection = try unzip(destination, into: root.appending(path: "leased-tree"))
        let first = try JSONDecoder.export.decode(PageEnvelope.self, from: Data(contentsOf: inspection.appending(path: "benchmark-runs/page-000001.json")))
        let second = try JSONDecoder.export.decode(PageEnvelope.self, from: Data(contentsOf: inspection.appending(path: "benchmark-runs/page-000002.json")))
        #expect(first.records.count == 100)
        #expect(second.records.count == 1)
        #expect(Set((first.records + second.records).compactMap { record -> String? in
            guard case let .string(value) = record.fields["id"] else { return nil }
            return value
        }).count == 101)
    }

    @Test("cancelled export lease waiter exits before the active snapshot releases")
    func cancelledLeaseWaiter() async throws {
        let root = try temporaryDirectory()
        let fixture = try exportRepository(root: root, count: 0)
        let active = try await fixture.repository.beginExportSnapshot()
        let completion = ExportLeaseCompletion()
        let waiting = Task {
            do {
                _ = try await fixture.repository.beginExportSnapshot()
                await completion.finish(cancelled: false)
            } catch is CancellationError {
                await completion.finish(cancelled: true)
            } catch {
                await completion.finish(cancelled: false)
            }
        }
        for _ in 0..<20 { await Task.yield() }

        waiting.cancel()
        let completedBeforeRelease = await completion.wait(for: .milliseconds(200))
        await fixture.repository.endExportSnapshot(active)
        await waiting.value

        #expect(completedBeforeRelease)
        #expect(await completion.cancelled)
    }

    @Test("persisted chronology ties use stable fingerprint before differing fetched times")
    func persistedChronologyOrdering() async throws {
        // Given
        let root = try temporaryDirectory()
        let fixture = try exportRepository(root: root, count: 0)
        let context = ModelContext(fixture.container)
        let values: [(Int, Date?, Date)] = [
            (1, nil, .init(timeIntervalSince1970: 20)),
            (2, .init(timeIntervalSince1970: 10), .init(timeIntervalSince1970: 30)),
            (3, .init(timeIntervalSince1970: 20), .init(timeIntervalSince1970: 10)),
            (4, .init(timeIntervalSince1970: 20), .init(timeIntervalSince1970: 40)),
        ]
        var expected: [(Date, String)] = []
        for (index, updatedAt, fetchedAt) in values {
            let dataset = exportBenchmark(index: index, fetchedAt: fetchedAt, sourceUpdatedAt: updatedAt)
            let fingerprint = try ContentFingerprint.benchmark(dataset)
            expected.append((updatedAt ?? fetchedAt, fingerprint))
            let entity = BenchmarkSnapshotEntity(dataset: dataset, fingerprint: fingerprint, encodedDataset: try JSONEncoder.radar.encode(dataset))
            entity.chronologyAt = .distantPast
            context.insert(entity)
        }
        try context.save()
        let repository = RadarRepository(container: fixture.container, metadataStore: SyncMetadataStore(root: root))
        let token = try await repository.beginExportSnapshot()

        // When
        let records = try await repository.exportRecords(dataset: .benchmarkRuns, range: .all, offset: 0, limit: 100, snapshot: token)
        await repository.endExportSnapshot(token)

        // Then
        let expectedIDs = expected.sorted { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }.map { ExportJSONValue.string($0.1) }
        #expect(records.compactMap { $0.fields["id"] } == expectedIDs)
    }

    @Test("production conversion preserves Decimal strings and explicit null")
    func productionConversion() async throws {
        // Given
        let root = try temporaryDirectory()
        let fixture = try exportRepository(root: root, count: 1)
        let token = try await fixture.repository.beginExportSnapshot()

        // When
        let record = try #require(try await fixture.repository.exportRecords(dataset: .benchmarkRuns, range: .all, offset: 0, limit: 1, snapshot: token).first)
        await fixture.repository.endExportSnapshot(token)
        let run = try #require(record.fields["runs"])

        // Then
        guard case let .array(runs) = run, case let .object(fields) = try #require(runs.first) else {
            Issue.record("Expected one benchmark run object")
            return
        }
        #expect(fields["benchmarkCostUSD"] == ExportJSONValue.string("1.23"))
        #expect(fields["qualityScore"] == ExportJSONValue.null)
    }

    @Test("successful replacement is explicit and symlink or traversal destinations are rejected")
    func destinationSafetyAndReplacement() async throws {
        // Given
        let root = try temporaryDirectory()
        let source = ExportFixtureSource(counts: [.models: 1])
        let service = RadarExportService(source: source, archiver: SystemZipArchiver())
        let replacement = root.appending(path: "replace.zip")
        try Data("old".utf8).write(to: replacement)

        // When
        _ = try await service.export(request: .init(destination: replacement, datasets: [.models], destinationPolicy: .replaceExisting))

        // Then
        #expect(try Data(contentsOf: replacement) != Data("old".utf8))
        let target = root.appending(path: "target.zip")
        try Data("target".utf8).write(to: target)
        let symlink = root.appending(path: "link.zip")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        await #expect(throws: ExportError.invalidDestination) {
            try await service.export(request: .init(destination: symlink, datasets: [.models], destinationPolicy: .replaceExisting))
        }
        #expect(try Data(contentsOf: target) == Data("target".utf8))
        let traversal = root.appending(path: "sub/../escape.zip")
        await #expect(throws: ExportError.invalidDestination) {
            try await service.export(request: .init(destination: traversal, datasets: [.models]))
        }
        #expect(ExportDataset.allCases.map(\.rawValue) == ["models", "benchmark-runs", "community-ratings", "source-status", "raw-samples"])
    }

    @Test("zip process cancellation terminates and clears its active process")
    func zipProcessCancellation() async throws {
        // Given
        let root = try temporaryDirectory()
        let archiver = SystemZipArchiver(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", "sleep 30"])
        let task = Task { try await archiver.archive(contentsOf: root, to: root.appending(path: "unused.zip")) }
        while await archiver.activeProcessID == nil { await Task.yield() }

        // When
        task.cancel()

        // Then
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await archiver.activeProcessID == nil)
    }

    @Test("real raw sample store exports the validated bounded payload only when opted in")
    func realRawSampleExport() async throws {
        // Given
        let root = try temporaryDirectory()
        let fixture = try exportRepository(root: root, count: 0)
        let rawStore = RawSampleStore(dataRoot: root)
        let body = Data("{\"ok\":true}".utf8)
        try await rawStore.save(body, sourceID: .claudeCodeRadar, outcome: .success, at: Date(timeIntervalSince1970: 10))
        let destination = root.appending(path: "raw.zip")
        let source = RadarExportSource(repository: fixture.repository, rawSampleStore: rawStore)

        // When
        _ = try await RadarExportService(source: source).export(
            request: .init(destination: destination, datasets: [], includesRawSamples: true),
            exportedAt: .init(timeIntervalSince1970: 20)
        )

        // Then
        let tree = try unzip(destination, into: root.appending(path: "raw-tree"))
        let page = try JSONDecoder.export.decode(PageEnvelope.self, from: Data(contentsOf: tree.appending(path: "raw-samples/page-000001.json")))
        let record = try #require(page.records.first)
        #expect(record.fields["body"] == .string("{\"ok\":true}"))
        guard case let .string(id) = record.fields["id"] else { Issue.record("Missing raw ID"); return }
        let expectedHash = SHA256.hash(data: body).prefix(6).map { String(format: "%02x", $0) }.joined()
        #expect(id.hasSuffix("_\(expectedHash).json"))
    }

    @Test("normalized-only export never reads or retains raw payload bodies")
    func normalizedExportSkipsRawPayloads() async throws {
        let root = try temporaryDirectory()
        let fixture = try exportRepository(root: root, count: 0)
        let spy = RawPayloadSpy()
        let source = RadarExportSource(repository: fixture.repository, rawSampleStore: spy)

        _ = try await RadarExportService(source: source).export(
            request: .init(destination: root.appending(path: "normalized.zip"), datasets: [.models])
        )
        #expect(await spy.readCount == 0)

        _ = try await RadarExportService(source: source).export(
            request: .init(destination: root.appending(path: "raw.zip"), datasets: [], includesRawSamples: true)
        )
        #expect(await spy.readCount == 1)
    }
}

private actor RawPayloadSpy: RawSamplePayloadSource {
    private(set) var readCount = 0

    func exportPayloads(sourceID: RadarSourceID) throws -> [RawSamplePayload] {
        readCount += 1
        return []
    }
}

private actor ExportLeaseCompletion {
    private(set) var cancelled = false
    private var finished = false
    func finish(cancelled: Bool) { self.cancelled = cancelled; finished = true }
    func wait(for duration: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: duration)
        while !finished, clock.now < deadline { try? await clock.sleep(for: .milliseconds(2)) }
        return finished
    }
}

private actor ExportPageGate {
    private var paused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pauseAfterFirstPage() async {
        paused = true
        pauseWaiters.forEach { $0.resume() }
        pauseWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
}

private actor MutationProbe {
    enum Mutation: Hashable { case insert, clear }
    private(set) var attempted: Set<Mutation> = []
    private(set) var completed: Set<Mutation> = []
    private var attemptWaiters: [CheckedContinuation<Void, Never>] = []

    func markInsertAttempted() { markAttempted(.insert) }
    func markClearAttempted() { markAttempted(.clear) }
    func markInsertCompleted() { completed.insert(.insert) }
    func markClearCompleted() { completed.insert(.clear) }
    func waitForAttempts() async {
        if attempted.count == 2 { return }
        await withCheckedContinuation { attemptWaiters.append($0) }
    }
    private func markAttempted(_ mutation: Mutation) {
        attempted.insert(mutation)
        if attempted.count == 2 { attemptWaiters.forEach { $0.resume() }; attemptWaiters.removeAll() }
    }
}

private struct ExportRepositoryFixture {
    let container: ModelContainer
    let repository: RadarRepository
}

private func exportRepository(root: URL, count: Int) throws -> ExportRepositoryFixture {
    let container = try RadarModelSchema.makeContainer(
        configuration: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    for index in 0..<count {
        let fetchedAt = Date(timeIntervalSince1970: TimeInterval(index))
        let dataset = exportBenchmark(index: index, fetchedAt: fetchedAt)
        let fingerprint = try ContentFingerprint.benchmark(dataset)
        context.insert(BenchmarkSnapshotEntity(
            sourceID: .claudeCodeRadar,
            fingerprint: fingerprint,
            fetchedAt: fetchedAt,
            seriesRevision: dataset.seriesRevision,
            encodedDataset: try JSONEncoder.radar.encode(dataset)
        ))
    }
    try context.save()
    return .init(container: container, repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root)))
}

private struct ExportFixtureFailure: Error {}

private actor FailingArchiver: RadarExportArchiver {
    func archive(contentsOf directory: URL, to destination: URL) async throws {
        try Data("partial".utf8).write(to: destination)
        throw ExportFixtureFailure()
    }
}

private actor ExportFixtureSource: RadarExportDataSource {
    let counts: [ExportDataset: Int]
    let cancelAfterFirstPage: Bool
    private(set) var maximumRequestedPageSize = 0
    private(set) var endedSnapshotCount = 0

    init(counts: [ExportDataset: Int], cancelAfterFirstPage: Bool = false) {
        self.counts = counts
        self.cancelAfterFirstPage = cancelAfterFirstPage
    }

    func endExportSnapshot(_ snapshot: ExportSnapshotToken) async { endedSnapshotCount += 1 }

    func exportRecordCount(dataset: ExportDataset, range: ExportDateRange, snapshot: ExportSnapshotToken) async throws -> Int { counts[dataset, default: 0] }

    func exportRecords(dataset: ExportDataset, range: ExportDateRange, offset: Int, limit: Int, snapshot: ExportSnapshotToken) async throws -> [ExportRecord] {
        maximumRequestedPageSize = max(maximumRequestedPageSize, limit)
        if cancelAfterFirstPage && offset > 0 { throw CancellationError() }
        let end = min(offset + limit, counts[dataset, default: 0])
        guard offset < end else { return [] }
        return (offset..<end).map { index in
            ExportRecord(fields: [
                "id": .string(String(format: "%06d", index)),
                "decimal": .string("123.4500"),
                "missing": .null,
            ])
        }
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func unzip(_ archive: URL, into destination: URL) throws -> URL {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/unzip")
    process.arguments = ["-q", archive.path, "-d", destination.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return destination
}

private func treeHash(_ root: URL) throws -> String {
    let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
    var data = Data()
    for path in files {
        let url = root.appending(path: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
        data.append(Data(path.utf8))
        data.append(try Data(contentsOf: url))
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func exportBenchmark(index: Int, fetchedAt: Date, sourceUpdatedAt: Date? = nil) -> BenchmarkDataset {
    let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "model-\(index)")
    return BenchmarkDataset(
        sourceID: .claudeCodeRadar,
        sourceUpdatedAt: sourceUpdatedAt,
        fetchedAt: fetchedAt,
        benchmarkName: nil,
        benchmarkVersion: nil,
        seriesRevision: ClaudeRadarConfiguration.seriesRevision,
        models: [ModelBenchmark(
            id: id,
            descriptor: .init(id: id, upstreamName: "Model \(index)", displayName: "Model \(index)"),
            qualityScore: nil,
            passedTasks: nil,
            validTasks: nil,
            invalidTasks: nil,
            benchmarkCostUSD: Decimal(string: "1.2300"),
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: nil,
            elapsedSeconds: nil,
            agentSteps: nil,
            cacheHitPercent: nil
        )]
    )
}
