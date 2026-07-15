import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("RadarRepositoryTests", .serialized)
struct RadarRepositoryTests {
    @Test("fingerprints ignore fetched time while preserving dataset, source, revision, and semantic values")
    func fingerprintContract() throws {
        // Given
        let first = benchmark(fetchedAt: Date(timeIntervalSince1970: 1), score: 60)
        let second = benchmark(fetchedAt: Date(timeIntervalSince1970: 2), score: 60)

        // When
        let firstHash = try ContentFingerprint.benchmark(first)
        let secondHash = try ContentFingerprint.benchmark(second)

        // Then
        #expect(firstHash == secondHash)
        #expect(firstHash != (try ContentFingerprint.benchmark(benchmark(score: 61))))
        #expect(firstHash != (try ContentFingerprint.benchmark(first, seriesRevision: "claude-radar-v2")))
        #expect(firstHash != (try ContentFingerprint.benchmark(benchmark(sourceID: .init(rawValue: "other")))))
        let modelID = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "m1")
        let community = CommunityDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: first.sourceUpdatedAt,
            fetchedAt: first.fetchedAt,
            ratings: [CommunityRating(
                id: modelID,
                model: ModelDescriptor(id: modelID, upstreamName: "Model", displayName: "Model"),
                average: 6,
                voteCount: 1,
                scaleMinimum: 1,
                scaleMaximum: 10
            )]
        )
        #expect(firstHash != (try ContentFingerprint.community(community)))
        let originalModel = try #require(first.models.first)
        let secondID = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "a-model")
        let secondModel = ModelBenchmark(
            id: secondID,
            descriptor: ModelDescriptor(id: secondID, upstreamName: "A Model", displayName: "A Model"),
            qualityScore: 55,
            passedTasks: 1,
            validTasks: 1,
            invalidTasks: 0,
            benchmarkCostUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: nil,
            elapsedSeconds: nil,
            agentSteps: nil,
            cacheHitPercent: nil
        )
        let ordered = benchmarkWithModels(first, models: [originalModel, secondModel])
        let reversed = benchmarkWithModels(first, models: [secondModel, originalModel])
        #expect(try ContentFingerprint.benchmark(ordered) == ContentFingerprint.benchmark(reversed))
    }

    @Test("duplicate insertion is scoped and concurrent attempts create one immutable snapshot")
    func concurrentDeduplication() async throws {
        // Given
        let fixture = try repositoryFixture()
        let dataset = benchmark()

        // When
        let outcomes = try await withThrowingTaskGroup(of: SnapshotInsertion.self) { group in
            for _ in 0..<12 {
                group.addTask { try await fixture.repository.insertBenchmark(dataset) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        // Then
        #expect(outcomes.filter(\.inserted).count == 1)
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: dataset.sourceID) == 1)
    }

    @Test("new content creates history and newest valid benchmark is restored after restart")
    func restartRestoration() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appending(path: "restart.store")
        try await insertPersistentHistory(storeURL: storeURL, metadataRoot: root)

        // When
        let restartedContainer = try ModelContainer(
            for: BenchmarkSnapshotEntity.self,
            CommunitySnapshotEntity.self,
            SourceStatusSnapshotEntity.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let restarted = RadarRepository(container: restartedContainer, metadataStore: SyncMetadataStore(root: root))
        let state = try await restarted.benchmarkState(sourceID: .claudeCodeRadar)

        // Then
        #expect(state.value?.models.first?.qualityScore == Decimal(61))
        #expect(state.error == nil)
        #expect(try await restarted.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 2)
    }

    @Test("a corrupt newest payload reports decoding and preserves the preceding last known good")
    func corruptPayloadContainment() async throws {
        // Given
        let fixture = try repositoryFixture()
        _ = try await fixture.repository.insertBenchmark(benchmark(fetchedAt: Date(timeIntervalSince1970: 10), score: 60))
        let context = ModelContext(fixture.container)
        context.insert(BenchmarkSnapshotEntity(
            sourceID: .claudeCodeRadar,
            fingerprint: "corrupt-payload",
            fetchedAt: Date(timeIntervalSince1970: 20),
            seriesRevision: ClaudeRadarConfiguration.seriesRevision,
            encodedDataset: Data("not-json".utf8)
        ))
        try context.save()

        // When
        let state = try await fixture.repository.benchmarkState(sourceID: .claudeCodeRadar)

        // Then
        #expect(state.value?.models.first?.qualityScore == Decimal(60))
        #expect(state.error?.kind == .decoding)
    }

    @Test("decodable fingerprint mismatch is omitted from history and rejected by export")
    func mismatchedPayloadIntegrity() async throws {
        let fixture = try repositoryFixture()
        let good = benchmark(fetchedAt: Date(timeIntervalSince1970: 10), score: 60)
        _ = try await fixture.repository.insertBenchmark(good)
        let corrupt = benchmark(fetchedAt: Date(timeIntervalSince1970: 20), score: 99)
        let context = ModelContext(fixture.container)
        context.insert(BenchmarkSnapshotEntity(
            sourceID: .claudeCodeRadar,
            fingerprint: "not-the-payload-fingerprint",
            fetchedAt: corrupt.fetchedAt,
            seriesRevision: corrupt.seriesRevision,
            encodedDataset: try JSONEncoder.radar.encode(corrupt)
        ))
        try context.save()

        let state = try await fixture.repository.benchmarkState(sourceID: .claudeCodeRadar)
        let history = try await fixture.repository.benchmarkHistory(sourceID: .claudeCodeRadar)
        let snapshot = try await fixture.repository.beginExportSnapshot()
        defer { Task { await fixture.repository.endExportSnapshot(snapshot) } }

        #expect(state.value == good)
        #expect(state.error?.kind == .decoding)
        #expect(history == [good])
        await #expect(throws: RepositoryIntegrityError.self) {
            try await fixture.repository.exportRecords(dataset: .benchmarkRuns, range: .all, offset: 0, limit: 100, snapshot: snapshot)
        }
    }

    @Test("corrupt synchronization metadata is reported while normalized history remains available")
    func corruptMetadataContainment() async throws {
        // Given
        let fixture = try repositoryFixture()
        _ = try await fixture.repository.insertBenchmark(benchmark(score: 60))
        try Data("not-json".utf8).write(to: fixture.root.appending(path: "SyncMetadata.json"), options: .atomic)

        // When
        let restarted = RadarRepository(container: fixture.container, metadataStore: SyncMetadataStore(root: fixture.root))
        let state = try await restarted.benchmarkState(sourceID: .claudeCodeRadar)

        // Then
        #expect(state.value?.models.first?.qualityScore == Decimal(60))
        #expect(state.error?.kind == .decoding)
    }

    @Test("segment failure and duplicate success update metadata without inserting history")
    func metadataWithoutHistory() async throws {
        // Given
        let fixture = try repositoryFixture()
        let time = Date(timeIntervalSince1970: 100)
        _ = try await fixture.repository.insertBenchmark(benchmark(fetchedAt: time))

        // When
        _ = try await fixture.repository.insertBenchmark(benchmark(fetchedAt: time.addingTimeInterval(10)))
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            attemptedAt: time,
            error: SegmentError(kind: .network, message: "offline"),
            retryAfter: time.addingTimeInterval(30)
        )
        try await fixture.repository.recordNotModified(
            sourceID: .claudeCodeRadar,
            datasetType: .benchmark,
            attemptedAt: time.addingTimeInterval(20),
            etag: "etag-1",
            lastModified: "yesterday"
        )
        let benchmarkMetadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        let communityMetadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community)

        // Then
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 1)
        #expect(benchmarkMetadata.lastAttemptedAt == time.addingTimeInterval(20))
        #expect(benchmarkMetadata.lastSuccessfulAt == time.addingTimeInterval(20))
        #expect(benchmarkMetadata.etag == "etag-1")
        #expect(benchmarkMetadata.lastModified == "yesterday")
        #expect(communityMetadata.lastError?.kind == .network)
        #expect(communityMetadata.retryAfter == time.addingTimeInterval(30))
    }

    @Test("community and source status keep independent last known good values")
    func segmentedLastKnownGood() async throws {
        // Given
        let fixture = try repositoryFixture()
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let modelID = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "m1")
        let community = CommunityDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 90),
            fetchedAt: fetchedAt,
            ratings: [CommunityRating(
                id: modelID,
                model: ModelDescriptor(id: modelID, upstreamName: "Model", displayName: "Model"),
                average: Decimal(string: "7.5"),
                voteCount: 2,
                scaleMinimum: 1,
                scaleMaximum: 10
            )]
        )
        let sourceStatus = SourceStatusDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 91),
            fetchedAt: fetchedAt,
            quotaEstimates: [SourceQuotaEstimate(id: "h5", windowLabel: "5 hours", usedPercent: 20, estimatedValueUSD: nil, resetDescription: nil)]
        )
        _ = try await fixture.repository.insertCommunity(community)
        _ = try await fixture.repository.insertSourceStatus(sourceStatus)

        // When
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            attemptedAt: fetchedAt.addingTimeInterval(1),
            error: SegmentError(kind: .network, message: "offline")
        )
        let benchmarkState = try await fixture.repository.benchmarkState(sourceID: .claudeCodeRadar)
        let communityState = try await fixture.repository.communityState(sourceID: .claudeCodeRadar)
        let statusState = try await fixture.repository.sourceStatusState(sourceID: .claudeCodeRadar)

        // Then
        #expect(benchmarkState.value == nil)
        #expect(communityState.value == community)
        #expect(communityState.error?.kind == .network)
        #expect(statusState.value == sourceStatus)
        #expect(statusState.error == nil)
    }

    @Test("delete removes normalized history and metadata and permits reinitialization")
    func deleteAndReinitialize() async throws {
        // Given
        let fixture = try repositoryFixture()
        _ = try await fixture.repository.insertBenchmark(benchmark())

        // When
        try await fixture.repository.deleteAll()
        let restarted = RadarRepository(container: fixture.container, metadataStore: SyncMetadataStore(root: fixture.root))

        // Then
        #expect(try await restarted.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 0)
        #expect(try await restarted.benchmarkState(sourceID: .claudeCodeRadar).value == nil)
        #expect(try await restarted.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark).lastAttemptedAt == nil)
    }

    @Test("manual repository narrative emits the required history dump")
    func historyDumpEvidence() async throws {
        // Given
        let fixture = try repositoryFixture()
        let first = benchmark(fetchedAt: Date(timeIntervalSince1970: 10), score: 60)
        let duplicate = benchmark(fetchedAt: Date(timeIntervalSince1970: 11), score: 60)
        let second = benchmark(fetchedAt: Date(timeIntervalSince1970: 12), score: 61)

        // When
        _ = try await fixture.repository.insertBenchmark(first)
        let duplicateOutcome = try await fixture.repository.insertBenchmark(duplicate)
        _ = try await fixture.repository.insertBenchmark(second)
        let state = try await fixture.repository.benchmarkState(sourceID: .claudeCodeRadar)
        let count = try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar)

        // Then
        let dump = HistoryDump(
            benchmarkSnapshots: count,
            duplicateInsertions: duplicateOutcome.inserted ? 1 : 0,
            lastKnownGood: state.value?.models.first?.qualityScore.map(String.init(describing:))
        )
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let evidence = root.appending(path: ".omo/evidence/phase-2/history-dump.json")
        try FileManager.default.createDirectory(at: evidence.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.pretty.encode(dump).write(to: evidence, options: .atomic)
        #expect(dump.benchmarkSnapshots == 2)
        #expect(dump.duplicateInsertions == 0)
        #expect(dump.lastKnownGood != nil)
    }

    private func repositoryFixture() throws -> RepositoryFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BenchmarkSnapshotEntity.self, CommunitySnapshotEntity.self, SourceStatusSnapshotEntity.self, configurations: configuration)
        return RepositoryFixture(
            root: root,
            container: container,
            repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root))
        )
    }

    private func insertPersistentHistory(storeURL: URL, metadataRoot: URL) async throws {
        let container = try ModelContainer(
            for: BenchmarkSnapshotEntity.self,
            CommunitySnapshotEntity.self,
            SourceStatusSnapshotEntity.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let repository = RadarRepository(container: container, metadataStore: SyncMetadataStore(root: metadataRoot))
        _ = try await repository.insertBenchmark(benchmark(fetchedAt: Date(timeIntervalSince1970: 10), score: 60))
        _ = try await repository.insertBenchmark(benchmark(fetchedAt: Date(timeIntervalSince1970: 20), score: 61))
    }

    private func benchmark(
        sourceID: RadarSourceID = .claudeCodeRadar,
        fetchedAt: Date = Date(timeIntervalSince1970: 10),
        score: Decimal = 60
    ) -> BenchmarkDataset {
        let modelID = ModelID(sourceID: sourceID, upstreamKey: "m1")
        return BenchmarkDataset(
            sourceID: sourceID,
            sourceUpdatedAt: Date(timeIntervalSince1970: 5),
            fetchedAt: fetchedAt,
            benchmarkName: nil,
            benchmarkVersion: nil,
            seriesRevision: ClaudeRadarConfiguration.seriesRevision,
            models: [ModelBenchmark(
                id: modelID,
                descriptor: ModelDescriptor(id: modelID, upstreamName: "Model", displayName: "Model"),
                qualityScore: score,
                passedTasks: 1,
                validTasks: 1,
                invalidTasks: 0,
                benchmarkCostUSD: Decimal(string: "1.20"),
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                totalTokens: nil,
                elapsedSeconds: 3_600,
                agentSteps: nil,
                cacheHitPercent: nil
            )]
        )
    }

    private func benchmarkWithModels(_ dataset: BenchmarkDataset, models: [ModelBenchmark]) -> BenchmarkDataset {
        BenchmarkDataset(
            sourceID: dataset.sourceID,
            sourceUpdatedAt: dataset.sourceUpdatedAt,
            fetchedAt: dataset.fetchedAt,
            benchmarkName: dataset.benchmarkName,
            benchmarkVersion: dataset.benchmarkVersion,
            seriesRevision: dataset.seriesRevision,
            models: models
        )
    }
}
