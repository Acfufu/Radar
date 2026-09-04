import Foundation
import SwiftData
import Testing
@testable import AIRadar

@Suite("CodexRenderedIQHistoryRepositoryTests", .serialized)
struct CodexRenderedIQHistoryRepositoryTests {
    @Test("history dedupe preserves first observation and updates independent metadata")
    func dedupeAndIndependentMetadata() async throws {
        let fixture = try repositoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try history(capturedAt: Date(timeIntervalSince1970: 10))
        let duplicate = try history(capturedAt: Date(timeIntervalSince1970: 20))

        #expect(RadarDatasetType.renderedIQHistory.rawValue == "rendered-iq-history")
        #expect(first.semanticFingerprint == duplicate.semanticFingerprint)
        #expect(try await fixture.repository.insertRenderedIQHistory(first).inserted)
        #expect(!(try await fixture.repository.insertRenderedIQHistory(duplicate).inserted))
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 1)
        let state = try await fixture.repository.renderedIQHistoryState(sourceID: .codexRadar)
        let metadata = try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        )
        #expect(state.value?.capturedAt == first.capturedAt)
        #expect(metadata.lastAttemptedAt == duplicate.capturedAt)
        #expect(metadata.lastSuccessfulAt == duplicate.capturedAt)
        #expect(try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings
        ) == .empty)

        let mismatched = CodexRenderedIQHistorySnapshot(
            sourceID: first.sourceID,
            parserRevision: first.parserRevision,
            finalOrigin: first.finalOrigin,
            capturedAt: Date(timeIntervalSince1970: 30),
            series: first.series,
            semanticFingerprint: "invalid"
        )
        await #expect(throws: RepositoryIntegrityError.self) {
            _ = try await fixture.repository.insertRenderedIQHistory(mismatched)
        }
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 1)
        #expect(try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        ).lastSuccessfulAt == duplicate.capturedAt)
    }

    @Test("corrupt newest history falls back to LKG and tie chronology is deterministic")
    func corruptNewestFallbackAndTieOrdering() async throws {
        let fixture = try repositoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let later = try history(marker: "later", capturedAt: Date(timeIntervalSince1970: 20))
        let tieB = try history(marker: "tie-b", capturedAt: Date(timeIntervalSince1970: 10))
        let tieA = try history(marker: "tie-a", capturedAt: Date(timeIntervalSince1970: 10))
        for value in [later, tieB, tieA] {
            _ = try await fixture.repository.insertRenderedIQHistory(value)
        }

        let context = ModelContext(fixture.container)
        let corrupt = try CodexRenderedIQHistorySnapshotEntity(
            snapshot: history(marker: "corrupt", capturedAt: Date(timeIntervalSince1970: 30))
        )
        corrupt.encodedSnapshot = Data("not-json".utf8)
        context.insert(corrupt)
        try context.save()

        let state = try await fixture.repository.renderedIQHistoryState(sourceID: .codexRadar)
        let stored = try await fixture.repository.renderedIQHistoryHistory(sourceID: .codexRadar)
        let tied = stored.filter { $0.capturedAt == tieA.capturedAt }

        #expect(state.value == later)
        #expect(state.error?.kind == .decoding)
        #expect(stored.count == 3)
        #expect(stored.map(\.capturedAt) == stored.map(\.capturedAt).sorted())
        #expect(tied.map(\.semanticFingerprint) == tied.map(\.semanticFingerprint).sorted())
    }

    @Test("successful insert removes corruption and retains 256 snapshots per parser revision")
    func pruningAndRevisionIsolation() async throws {
        let fixture = try repositoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let otherRevision = try history(
            marker: "other-revision",
            capturedAt: Date(timeIntervalSince1970: 1),
            parserRevision: "codex-radar-rendered-iq-history-v2"
        )
        _ = try await fixture.repository.insertRenderedIQHistory(otherRevision)

        let context = ModelContext(fixture.container)
        let corrupt = try CodexRenderedIQHistorySnapshotEntity(
            snapshot: history(marker: "corrupt", capturedAt: Date(timeIntervalSince1970: 10_000))
        )
        corrupt.encodedSnapshot = Data("corrupt".utf8)
        context.insert(corrupt)
        try context.save()

        for index in 0..<257 {
            _ = try await fixture.repository.insertRenderedIQHistory(try history(
                marker: "snapshot-\(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(100 + index))
            ))
        }

        let stored = try await fixture.repository.renderedIQHistoryHistory(sourceID: .codexRadar)
        let v1 = stored.filter { $0.parserRevision == "codex-radar-rendered-iq-history-v1" }
        let v2 = stored.filter { $0.parserRevision == "codex-radar-rendered-iq-history-v2" }
        #expect(v1.count == 256)
        #expect(v2 == [otherRevision])
        #expect(v1.first?.series.first?.displayName == "snapshot-1")
        #expect(v1.last?.series.first?.displayName == "snapshot-256")
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 257)
    }

    @Test("source deletion clears normalized IQ and warning rows but preserves raw samples")
    func sourceDeletionAndRawIsolation() async throws {
        let fixture = try repositoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try await fixture.repository.insertRenderedIQHistory(try history())
        _ = try await fixture.repository.insertRenderedWarning(try legacyValues().warning)
        let rawStore = RawSampleStore(dataRoot: fixture.root)
        try await rawStore.save(
            Data("raw".utf8),
            sourceID: .codexRadar,
            outcome: .success,
            at: Date(timeIntervalSince1970: 11)
        )

        try await fixture.repository.deleteNormalizedHistory(sourceID: .codexRadar)

        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 0)
        #expect(try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        ) == .empty)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 0)
        #expect(try await rawStore.samples(sourceID: .codexRadar).count == 1)
    }

    @Test("old four-entity store upgrades additively and IQ history survives offline reopen")
    func fourEntityUpgradeAndOfflineReopen() async throws {
        let root = temporaryRoot("four-entity-upgrade")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = try createFourEntityStore(at: root.appending(path: "Radar.store"))
        let storedHistory = try await upgradeStore(root: root, legacy: legacy)

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
        #expect(try await repository.renderedWarningState(sourceID: .codexRadar).value == legacy.warning)
        #expect(try await repository.renderedIQHistoryState(sourceID: .codexRadar).value == storedHistory)
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

    private func history(
        marker: String = "aggregate",
        capturedAt: Date = Date(timeIntervalSince1970: 10),
        parserRevision: String = "codex-radar-rendered-iq-history-v1"
    ) throws -> CodexRenderedIQHistorySnapshot {
        let points = (0..<24).map {
            CodexRenderedIQHistoryPoint(
                sourceOrder: $0,
                sourceTimeLabel: String(format: "07/27 %02d:00", $0),
                iq: 100 + Double($0) / 10
            )
        }
        let series = [
            CodexRenderedIQHistorySeries(
                sourceOrder: 0,
                seriesKey: "aggregate",
                displayName: marker,
                points: points
            ),
            CodexRenderedIQHistorySeries(
                sourceOrder: 1,
                seriesKey: "model:gpt-5.6-sol",
                displayName: "Sol",
                points: points
            ),
        ]
        let fingerprint = try CodexRenderedIQHistorySemanticFingerprint.make(
            sourceID: .codexRadar,
            series: series,
            finalOrigin: "https://deng.codexradar.com",
            parserRevision: parserRevision
        )
        return CodexRenderedIQHistorySnapshot(
            sourceID: .codexRadar,
            parserRevision: parserRevision,
            finalOrigin: "https://deng.codexradar.com",
            capturedAt: capturedAt,
            series: series,
            semanticFingerprint: fingerprint
        )
    }

    private func createFourEntityStore(at storeURL: URL) throws -> LegacyValues {
        let container = try ModelContainer(
            for: BenchmarkSnapshotEntity.self,
            CommunitySnapshotEntity.self,
            SourceStatusSnapshotEntity.self,
            CodexRenderedWarningSnapshotEntity.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = ModelContext(container)
        let values = try legacyValues()
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
        context.insert(try CodexRenderedWarningSnapshotEntity(snapshot: values.warning))
        try context.save()
        return values
    }

    private func upgradeStore(root: URL, legacy: LegacyValues) async throws -> CodexRenderedIQHistorySnapshot {
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
        #expect(try await repository.renderedWarningState(sourceID: .codexRadar).value == legacy.warning)
        let value = try history(marker: "persisted-history", capturedAt: Date(timeIntervalSince1970: 500))
        _ = try await repository.insertRenderedIQHistory(value)
        return value
    }

    private func legacyValues() throws -> LegacyValues {
        let benchmark = BenchmarkDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 101),
            fetchedAt: Date(timeIntervalSince1970: 102),
            benchmarkName: "Legacy",
            benchmarkVersion: "four-entity",
            seriesRevision: "legacy-v1",
            models: []
        )
        let community = CommunityDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 201),
            fetchedAt: Date(timeIntervalSince1970: 202),
            ratings: []
        )
        let status = SourceStatusDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 301),
            fetchedAt: Date(timeIntervalSince1970: 302),
            quotaEstimates: []
        )
        let cards = [
            CodexRenderedWarningCard(
                displayName: "Legacy Sol",
                family: "sol",
                effort: "xhigh",
                sourceOrder: 0,
                iq: 91,
                drop24h: 9,
                drop48h: 10
            ),
        ]
        let fingerprint = try CodexRenderedWarningSemanticFingerprint.make(
            sourceTimeLabel: "legacy",
            cards: cards,
            finalOrigin: "https://codexradar.com",
            parserRevision: "codex-radar-rendered-dom-v2"
        )
        let warning = CodexRenderedWarningSnapshot(
            sourceID: .codexRadar,
            parserRevision: "codex-radar-rendered-dom-v2",
            finalOrigin: "https://codexradar.com",
            sourceTimeLabel: "legacy",
            capturedAt: Date(timeIntervalSince1970: 401),
            cards: cards,
            semanticFingerprint: fingerprint
        )
        return LegacyValues(
            benchmark: benchmark,
            community: community,
            status: status,
            warning: warning
        )
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-IQHistory-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private struct LegacyValues {
    let benchmark: BenchmarkDataset
    let community: CommunityDataset
    let status: SourceStatusDataset
    let warning: CodexRenderedWarningSnapshot
}
