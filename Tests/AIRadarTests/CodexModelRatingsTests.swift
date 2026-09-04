import Foundation
import SwiftData
import Testing
@testable import AIRadar

/// P2④ model-ratings upgrade tests (spec §5.4): open-set group/effort
/// parsing, the 7d/24h matrix mapping, and the D12 my_scores read-only
/// contract (in-memory display only — never persisted or fingerprinted).
@Suite("CodexModelRatingsTests")
struct CodexModelRatingsTests {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Sources/AIRadar/Resources/Fixtures/\(name).json"))
    }

    private func parse(_ name: String, fetchedAt: Date = Date(timeIntervalSince1970: 1_752_566_500)) throws -> CommunityDataset {
        let projection = try CodexRadarParser().parseCommunityEnvelope(try fixture(name), fetchedAt: fetchedAt)
        return try #require(projection.value)
    }

    @Test("v2 ratings parse groups, effort suffixes, history, and my_scores")
    func v2Parsing() throws {
        let dataset = try parse("codex-radar-community-v2")

        // Open set: known and unknown groups preserved verbatim.
        let ultra = try #require(dataset.ratings.first { $0.id.upstreamKey == "gpt-5.6-sol-ultra" })
        #expect(ultra.group == "GPT-5.6 Sol")
        #expect(ultra.effortSuffix == "ultra")
        let unknownGroup = try #require(dataset.ratings.first { $0.id.upstreamKey == "deepseek-v4-flash-off" })
        #expect(unknownGroup.group == "Brand New Unknown Group")
        #expect(unknownGroup.effortSuffix == "off")

        // No-effort ids are never mislabeled.
        let plain = try #require(dataset.ratings.first { $0.id.upstreamKey == "gpt-5.5" })
        #expect(plain.group == "GPT-5.5")
        #expect(plain.effortSuffix == nil)

        #expect(dataset.day == "2026-09-05")
        #expect(dataset.history?.count == 3)
        let lastDay = try #require(dataset.history?.last)
        #expect(lastDay.day == "2026-09-05")
        #expect(lastDay.ratings.first?.group == "GPT-5.6 Sol")

        // D12: my_scores is readable in memory for display.
        #expect(dataset.myScores?["gpt-5.6-sol-ultra"] == 9)
    }

    @Test("legacy ratings payload keeps parsing without the new fields")
    func v1BackwardCompatibility() throws {
        let dataset = try parse("codex-radar-community-valid")
        #expect(dataset.ratings.allSatisfy { $0.group == nil })
        // effort stays derivable from the id regardless of payload vintage.
        #expect(dataset.ratings.first { $0.id.upstreamKey == "gpt-5.6-sol-max" }?.effortSuffix == "max")
        #expect(dataset.history == nil)
        #expect(dataset.day == nil)
        #expect(dataset.myScores == nil)
    }

    @MainActor
    @Test("my_scores never persists and never changes the fingerprint (D12)")
    func myScoresNeverPersisted() async throws {
        var dataset = try parse("codex-radar-community-v2")
        let withMine = try ContentFingerprint.community(dataset)
        dataset.myScores = nil
        let withoutMine = try ContentFingerprint.community(dataset)
        #expect(withMine == withoutMine)

        let encoded = try JSONEncoder.radar.encode(dataset)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("myScores"))
        #expect(!json.contains("my_scores"))

        // Round trip through the repository keeps the blob free of my data.
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-D12-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        var stored = try parse("codex-radar-community-v2", fetchedAt: Date(timeIntervalSince1970: 100))
        stored.myScores = ["gpt-5.6-sol-ultra": 9]
        _ = try await repository.insertCommunity(stored, seriesRevision: "codex-radar-public-v2")
        let container = try environment.makeModelContainer()
        let entities = try ModelContext(container).fetch(FetchDescriptor<CommunitySnapshotEntity>())
        let blob = String(decoding: try #require(entities.first).encodedDataset, as: UTF8.self)
        #expect(!blob.contains("my_scores"))
        #expect(!blob.contains("myScores"))
        // In-memory projection still carries the read-only display value.
        #expect(stored.myScores?["gpt-5.6-sol-ultra"] == 9)
    }

    @Test("matrix builds 24h plus trailing 7-day columns with scale-normalized stars")
    func matrixBuild() throws {
        let dataset = try parse("codex-radar-community-v2")
        let padded = CommunityDataset(
            sourceID: dataset.sourceID,
            sourceUpdatedAt: dataset.sourceUpdatedAt,
            fetchedAt: dataset.fetchedAt,
            ratings: dataset.ratings,
            history: (dataset.history ?? []) + [CommunityHistoryDay(
                day: "2026-08-20",
                updatedAt: nil,
                ratings: [CommunityHistoryRating(id: "gpt-5.6-sol-ultra", group: "GPT-5.6 Sol", average: 8, count: 5)]
            )],
            day: dataset.day,
            myScores: dataset.myScores
        )
        // Pad history to prove the trailing window caps at 7 columns.

        let matrix = CodexStarMatrixModel.build(dataset: padded)
        // 24h bucket (2026-09-05) plus trailing days excluding that bucket,
        // ascending.
        #expect(matrix.columnTitles == ["24h", "2026-08-20", "2026-09-03", "2026-09-04"])
        let ultra = try #require(matrix.rows.first { $0.title.contains("ultra") })
        #expect(ultra.subtitle == "GPT-5.6 Sol")
        let firstCell = try #require(ultra.cells.first)
        let cell24h = try #require(firstCell)
        #expect(cell24h.average == 8.7)
        #expect(cell24h.starFill == 4.35)
        #expect(cell24h.mine == 9)
        // The plain GPT-5.5 model has no effort pill.
        let plain = try #require(matrix.rows.first { $0.title == "GPT-5.5" })
        #expect(plain.pill == nil)
        let ultraPill = try #require(matrix.rows.first { $0.title.contains("ultra") })
        #expect(ultraPill.pill == "ultra")

        // nil-data matrix stays empty without history.
        let empty = CodexStarMatrixModel.build(dataset: CommunityDataset(
            sourceID: .codexRadar,
            sourceUpdatedAt: nil,
            fetchedAt: .now,
            ratings: []
        ))
        #expect(empty.rows.isEmpty)
        #expect(empty.columnTitles.isEmpty)
    }
}
