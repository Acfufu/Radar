import Foundation
import SwiftData
import Testing
@testable import AIRadar

@Suite("CodexRenderedWarningRepositoryTests", .serialized)
struct CodexRenderedWarningRepositoryTests {
    @Test("rendered warning fingerprints exclude capture time and duplicate success updates independent metadata")
    func fingerprintDeduplicationAndMetadata() async throws {
        let fixture = try repositoryFixture()
        let first = try warning(capturedAt: Date(timeIntervalSince1970: 10))
        let duplicate = try warning(capturedAt: Date(timeIntervalSince1970: 20))

        #expect(RadarDatasetType.renderedWarnings.rawValue == "rendered-warnings")
        #expect(try ContentFingerprint.renderedWarning(first) == ContentFingerprint.renderedWarning(duplicate))

        let firstInsertion = try await fixture.repository.insertRenderedWarning(first)
        let duplicateInsertion = try await fixture.repository.insertRenderedWarning(duplicate)
        try await fixture.repository.recordFailure(
            sourceID: .codexRadar,
            datasetType: .benchmark,
            attemptedAt: Date(timeIntervalSince1970: 30),
            error: SegmentError(kind: .network, message: "offline")
        )

        #expect(firstInsertion.inserted)
        #expect(!duplicateInsertion.inserted)
        #expect(try await fixture.repository.snapshotCount(datasetType: .renderedWarnings, sourceID: .codexRadar) == 1)
        let warningMetadata = try await fixture.repository.metadata(sourceID: .codexRadar, datasetType: .renderedWarnings)
        let benchmarkMetadata = try await fixture.repository.metadata(sourceID: .codexRadar, datasetType: .benchmark)
        #expect(warningMetadata.lastAttemptedAt == duplicate.capturedAt)
        #expect(warningMetadata.lastSuccessfulAt == duplicate.capturedAt)
        #expect(warningMetadata.lastError == nil)
        #expect(benchmarkMetadata.lastError?.kind == .network)
    }

    @Test("fractional live capture time survives persistence and publishes LKG")
    func fractionalCaptureTimePersistence() async throws {
        let fixture = try repositoryFixture()
        let liveCapturedAt = Date(
            timeIntervalSince1970: 1_785_092_000 + 5.0 / 1_000_003.0
        )
        let snapshot = try warning(capturedAt: liveCapturedAt)
        let persistedSnapshot = try JSONDecoder.radar.decode(
            CodexRenderedWarningSnapshot.self,
            from: JSONEncoder.radar.encode(snapshot)
        )

        #expect(persistedSnapshot.capturedAt != liveCapturedAt)
        let entity = try CodexRenderedWarningSnapshotEntity(snapshot: snapshot)
        #expect(entity.capturedAt == persistedSnapshot.capturedAt)
        #expect(entity.chronologyAt == persistedSnapshot.capturedAt)

        _ = try await fixture.repository.insertRenderedWarning(snapshot)

        let state = try await fixture.repository.renderedWarningState(sourceID: .codexRadar)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 1)
        #expect(state.value == persistedSnapshot)
        #expect(state.lastSuccessfulAt == persistedSnapshot.capturedAt)
        #expect(state.error == nil)
    }

    @Test("corrupt newest warning falls back to LKG and history orders chronology then fingerprint")
    func corruptNewestFallbackAndHistoryOrdering() async throws {
        let fixture = try repositoryFixture()
        let later = try warning(sourceTimeLabel: "later", capturedAt: Date(timeIntervalSince1970: 20), iq: 80)
        let tieB = try warning(sourceTimeLabel: "tie-b", capturedAt: Date(timeIntervalSince1970: 10), iq: 70)
        let tieA = try warning(sourceTimeLabel: "tie-a", capturedAt: Date(timeIntervalSince1970: 10), iq: 60)
        _ = try await fixture.repository.insertRenderedWarning(later)
        _ = try await fixture.repository.insertRenderedWarning(tieB)
        _ = try await fixture.repository.insertRenderedWarning(tieA)

        let context = ModelContext(fixture.container)
        let corrupt = try warning(sourceTimeLabel: "corrupt", capturedAt: Date(timeIntervalSince1970: 30), iq: 90)
        let corruptEntity = try CodexRenderedWarningSnapshotEntity(snapshot: corrupt)
        corruptEntity.encodedSnapshot = Data("not-json".utf8)
        context.insert(corruptEntity)
        try context.save()

        let state = try await fixture.repository.renderedWarningState(sourceID: .codexRadar)
        let history = try await fixture.repository.renderedWarningHistory(sourceID: .codexRadar)
        let tied = history.filter { $0.capturedAt == tieA.capturedAt }

        #expect(state.value == later)
        #expect(state.error?.kind == .decoding)
        #expect(history.count == 3)
        #expect(history.map(\.capturedAt) == history.map(\.capturedAt).sorted())
        #expect(tied.map(\.semanticFingerprint) == tied.map(\.semanticFingerprint).sorted())
    }

    @Test("successful nonduplicate insertion removes corrupt rows and retains newest 256 valid rows per source revision")
    func pruningAndIntegrityCleanup() async throws {
        let fixture = try repositoryFixture()
        let otherRevision = try warning(
            sourceTimeLabel: "other-revision",
            capturedAt: Date(timeIntervalSince1970: 1),
            parserRevision: CodexRenderedWarningDOMParser.parserRevision,
            iq: 1
        )
        _ = try await fixture.repository.insertRenderedWarning(otherRevision)

        let context = ModelContext(fixture.container)
        let corrupt = try CodexRenderedWarningSnapshotEntity(snapshot: warning(
            sourceTimeLabel: "corrupt",
            capturedAt: Date(timeIntervalSince1970: 10_000),
            iq: 149
        ))
        corrupt.encodedSnapshot = Data("corrupt".utf8)
        context.insert(corrupt)
        try context.save()

        for index in 0..<257 {
            _ = try await fixture.repository.insertRenderedWarning(try warning(
                sourceTimeLabel: "snapshot-\(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(100 + index)),
                iq: Double(index % 151)
            ))
        }

        let history = try await fixture.repository.renderedWarningHistory(sourceID: .codexRadar)
        let v1 = history.filter { $0.parserRevision == "codex-radar-rendered-dom-v1" }
        let v2 = history.filter { $0.parserRevision == "codex-radar-rendered-dom-v2" }
        let state = try await fixture.repository.renderedWarningState(sourceID: .codexRadar)

        #expect(v1.count == 256)
        #expect(v2 == [otherRevision])
        #expect(v1.first?.sourceTimeLabel == "snapshot-1")
        #expect(v1.last?.sourceTimeLabel == "snapshot-256")
        #expect(state.value?.sourceTimeLabel == "snapshot-256")
        #expect(state.error == nil)
        #expect(try await fixture.repository.snapshotCount(datasetType: .renderedWarnings, sourceID: .codexRadar) == 257)
    }

    @Test("source deletion clears warning rows and metadata while preserving raw samples")
    func sourceDeletionPreservesRawSamples() async throws {
        let fixture = try repositoryFixture()
        _ = try await fixture.repository.insertRenderedWarning(try warning(capturedAt: Date(timeIntervalSince1970: 10)))
        let rawStore = RawSampleStore(dataRoot: fixture.root)
        try await rawStore.save(Data("raw".utf8), sourceID: .codexRadar, outcome: .success, at: Date(timeIntervalSince1970: 11))

        try await fixture.repository.deleteNormalizedHistory(sourceID: .codexRadar)

        #expect(try await fixture.repository.snapshotCount(datasetType: .renderedWarnings, sourceID: .codexRadar) == 0)
        #expect(try await fixture.repository.metadata(sourceID: .codexRadar, datasetType: .renderedWarnings) == .empty)
        #expect(try await rawStore.samples(sourceID: .codexRadar).count == 1)
    }

    @Test("old three-entity store upgrades additively, preserves all values, and warning LKG survives offline reopen")
    func legacyStoreUpgradeAndOfflineReopen() async throws {
        let root = temporaryRoot("legacy-upgrade")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appending(path: "Radar.store")
        let legacy = try createLegacyStore(at: storeURL)
        let storedWarning = try await upgradeLegacyStore(root: root, legacy: legacy)

        let offlineContainer = try AppEnvironment(
            dataRoot: root,
            fixtureMode: .disabled,
            onlineSourceEnabled: false
        ).makeModelContainer()
        let offlineRepository = RadarRepository(
            container: offlineContainer,
            metadataStore: SyncMetadataStore(root: root)
        )

        #expect(try await offlineRepository.benchmarkState(sourceID: .claudeCodeRadar).value == legacy.benchmark)
        #expect(try await offlineRepository.communityState(sourceID: .claudeCodeRadar).value == legacy.community)
        #expect(try await offlineRepository.sourceStatusState(sourceID: .claudeCodeRadar).value == legacy.status)
        #expect(try await offlineRepository.renderedWarningState(sourceID: .codexRadar).value == storedWarning)
    }

    private func upgradeLegacyStore(
        root: URL,
        legacy: LegacyValues
    ) async throws -> CodexRenderedWarningSnapshot {
        let container = try AppEnvironment(
            dataRoot: root,
            fixtureMode: .disabled,
            onlineSourceEnabled: false
        ).makeModelContainer()
        let repository = RadarRepository(
            container: container,
            metadataStore: SyncMetadataStore(root: root)
        )
        #expect(try await repository.benchmarkState(sourceID: .claudeCodeRadar).value == legacy.benchmark)
        #expect(try await repository.communityState(sourceID: .claudeCodeRadar).value == legacy.community)
        #expect(try await repository.sourceStatusState(sourceID: .claudeCodeRadar).value == legacy.status)
        let snapshot = try warning(
            sourceTimeLabel: "persisted-warning",
            capturedAt: Date(timeIntervalSince1970: 400)
        )
        _ = try await repository.insertRenderedWarning(snapshot)
        return snapshot
    }

    private func repositoryFixture() throws -> RepositoryFixture {
        let root = temporaryRoot("repository")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try RadarModelSchema.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return RepositoryFixture(
            root: root,
            container: container,
            repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root))
        )
    }

    private func createLegacyStore(at storeURL: URL) throws -> LegacyValues {
        // Deliberate compatibility fixture: exactly production's pre-warning three-entity schema.
        let legacyContainer = try ModelContainer(
            for: BenchmarkSnapshotEntity.self,
            CommunitySnapshotEntity.self,
            SourceStatusSnapshotEntity.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = ModelContext(legacyContainer)
        let values = legacyValues()
        context.insert(BenchmarkSnapshotEntity(
            dataset: values.benchmark,
            fingerprint: try ContentFingerprint.benchmark(values.benchmark),
            encodedDataset: try JSONEncoder.radar.encode(values.benchmark)
        ))
        context.insert(CommunitySnapshotEntity(
            dataset: values.community,
            seriesRevision: "legacy-v1",
            fingerprint: try ContentFingerprint.community(values.community, seriesRevision: "legacy-v1"),
            encodedDataset: try JSONEncoder.radar.encode(values.community)
        ))
        context.insert(SourceStatusSnapshotEntity(
            dataset: values.status,
            seriesRevision: "legacy-v1",
            fingerprint: try ContentFingerprint.sourceStatus(values.status, seriesRevision: "legacy-v1"),
            encodedDataset: try JSONEncoder.radar.encode(values.status)
        ))
        try context.save()
        return values
    }

    private func legacyValues() -> LegacyValues {
        let benchmarkID = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "legacy")
        let benchmark = BenchmarkDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 101),
            fetchedAt: Date(timeIntervalSince1970: 102),
            benchmarkName: "Legacy benchmark",
            benchmarkVersion: "old-three",
            seriesRevision: "legacy-v1",
            models: [ModelBenchmark(
                id: benchmarkID,
                descriptor: ModelDescriptor(id: benchmarkID, upstreamName: "Legacy", displayName: "Legacy Model"),
                qualityScore: 88,
                passedTasks: 8,
                validTasks: 9,
                invalidTasks: 1,
                benchmarkCostUSD: 2,
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                totalTokens: nil,
                elapsedSeconds: 12,
                agentSteps: nil,
                cacheHitPercent: nil
            )]
        )
        let community = CommunityDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 201),
            fetchedAt: Date(timeIntervalSince1970: 202),
            ratings: [CommunityRating(
                id: benchmarkID,
                model: ModelDescriptor(id: benchmarkID, upstreamName: "Legacy", displayName: "Legacy Model"),
                average: 7,
                voteCount: 42,
                scaleMinimum: 1,
                scaleMaximum: 10
            )]
        )
        let status = SourceStatusDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 301),
            fetchedAt: Date(timeIntervalSince1970: 302),
            quotaEstimates: [SourceQuotaEstimate(
                id: "legacy-window",
                windowLabel: "Legacy window",
                usedPercent: 25,
                estimatedValueUSD: 3,
                resetDescription: "later"
            )]
        )
        return LegacyValues(benchmark: benchmark, community: community, status: status)
    }

    private func warning(
        sourceTimeLabel: String = "Updated now",
        capturedAt: Date,
        parserRevision: String = "codex-radar-rendered-dom-v1",
        iq: Double = 100
    ) throws -> CodexRenderedWarningSnapshot {
        let cards = [CodexRenderedWarningCard(
            displayName: "GPT-5.6",
            family: "GPT",
            effort: "High",
            sourceOrder: 0,
            iq: iq,
            drop24h: 2,
            drop48h: 3
        )]
        let fingerprint = try CodexRenderedWarningSemanticFingerprint.make(
            sourceTimeLabel: sourceTimeLabel,
            cards: cards,
            finalOrigin: "https://codexradar.com",
            parserRevision: parserRevision
        )
        return CodexRenderedWarningSnapshot(
            sourceID: .codexRadar,
            parserRevision: parserRevision,
            finalOrigin: "https://codexradar.com",
            sourceTimeLabel: sourceTimeLabel,
            capturedAt: capturedAt,
            cards: cards,
            semanticFingerprint: fingerprint
        )
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "CodexRenderedWarningRepositoryTests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private struct LegacyValues {
    let benchmark: BenchmarkDataset
    let community: CommunityDataset
    let status: SourceStatusDataset
}
