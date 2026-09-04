import Foundation
import SwiftData
import Testing
@testable import AIRadar

/// P2① station-status tests (spec §5.1): schema 2.0 parsing, v1 backward
/// compatibility, fingerprints, persistence round-trip, and the D13
/// verbatim-storage contract.
@Suite("CodexStationStatusTests")
struct CodexStationStatusTests {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Sources/AIRadar/Resources/Fixtures/\(name).json"))
    }

    @Test("schema 2.0 envelope parses station status benchmark provenance and quota detail")
    func v2Parsing() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let envelope = try CodexRadarParser().parseBenchmarkEnvelope(
            fixture("codex-radar-public-summary-v2"),
            fetchedAt: fetchedAt
        )

        let status = try #require(envelope.stationStatus?.value)
        #expect(status.sourceID == .codexRadar)
        #expect(status.timezone == "Asia/Shanghai")
        #expect(status.windowOpen == false)
        #expect(status.status == "community_confirmed")
        #expect(status.recommendedAction == "wait")

        let window = try #require(status.window)
        #expect(window.isOpen == false)
        #expect(window.title == "Codex 用量限制重置")
        #expect(window.message == "当前没有开启的速蹬窗口")
        #expect(window.closedAt == "2026-08-31T10:34:27+08:00")
        #expect(window.sourceURL == "https://x.com/thsottiaux/status/2094252447271366730")

        let prediction = try #require(status.prediction)
        #expect(prediction.level == "low")
        #expect(prediction.probability24h == 0.14)
        #expect(prediction.probability48h == 0.27)
        #expect(prediction.summary == "上一轮硬重置刚完成。")
        #expect(prediction.summaryEN == "Latest hard reset complete.")

        // D13: verbatim upstream observation, safety note travels with it.
        let tibo = try #require(status.tiboPresence)
        #expect(tibo.shouldDisplay == true)
        #expect(tibo.locationLabelZH == "旧金山湾区 / PT")
        #expect(tibo.locationLabelEN == "San Francisco Bay Area / PT")
        #expect(tibo.probability == 0.2)
        #expect(tibo.evidenceSummaryZH == "所提供的公开帖子未明确披露当前国家或地区。")
        #expect(tibo.safetyNoteZH == "仅基于公开发帖做国家/时区级推测，不展示住址。")
        #expect(tibo.safetyNoteEN == "Region-level inference only.")
        #expect(tibo.sourceURLs == ["https://x.com/thsottiaux/status/2079647758869475531"])

        // Quota trend stays chronological; check/calibration map through.
        let sourceStatus = try #require(envelope.sourceStatus.value)
        #expect(sourceStatus.trend?.map(\.date) == ["2026-07-14", "2026-07-15"])
        #expect(sourceStatus.trend?.first?.fiveH20x == Decimal(string: "300"))
        #expect(sourceStatus.check?.planType == "pro")
        #expect(sourceStatus.check?.creditsAvailable == 250)
        #expect(sourceStatus.check?.limitReached == false)
        #expect(sourceStatus.calibration?.status == "calibrated")
        #expect(sourceStatus.calibration?.globalConcurrency == 3)

        // Benchmark provenance + human-readable run fields ride along.
        let benchmark = try #require(envelope.benchmark.value)
        #expect(benchmark.dataSource?.type == "deep_swe_bench")
        #expect(benchmark.dataSource?.validCells == 42)
        let latest = try #require(envelope.benchmark.value?.models.first { $0.id.upstreamKey.contains("max") })
        #expect(latest.wallTimeHuman == "1小时")
        #expect(latest.costUSDBasis == nil || latest.costUSDBasis is String)
    }

    @Test("legacy v1 payload yields no station status and keeps the main chain intact")
    func v1BackwardCompatibility() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let envelope = try CodexRadarParser().parseBenchmarkEnvelope(
            fixture("codex-radar-public-summary"),
            fetchedAt: fetchedAt
        )
        #expect(envelope.stationStatus == nil)
        #expect(envelope.benchmark.value != nil)
        #expect(envelope.sourceStatus.value?.trend == nil)
        #expect(envelope.sourceStatus.value?.check == nil)
        #expect(envelope.sourceStatus.value?.calibration == nil)
    }

    @Test("station status fingerprint is stable and ignores fetch time")
    func fingerprintStability() throws {
        let fetchedA = Date(timeIntervalSince1970: 1_752_566_500)
        let fetchedB = Date(timeIntervalSince1970: 1_799_999_999)
        let a = try ContentFingerprint.stationStatus(
            try #require(CodexRadarParser().parseBenchmarkEnvelope(fixture("codex-radar-public-summary-v2"), fetchedAt: fetchedA).stationStatus?.value)
        )
        let b = try ContentFingerprint.stationStatus(
            try #require(CodexRadarParser().parseBenchmarkEnvelope(fixture("codex-radar-public-summary-v2"), fetchedAt: fetchedB).stationStatus?.value)
        )
        #expect(a == b)
    }

    @Test("repository persists latest station status and clears it with normalized history")
    func repositoryRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-StationStatus-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
        let metadataStore = SyncMetadataStore(root: environment.dataRoot)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: metadataStore
        )

        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let dataset = try #require(
            CodexRadarParser().parseBenchmarkEnvelope(
                fixture("codex-radar-public-summary-v2"),
                fetchedAt: fetchedAt
            ).stationStatus?.value
        )
        _ = try await repository.insertStationStatus(dataset)
        let latest = try #require(await repository.latestStationStatus(sourceID: .codexRadar))
        #expect(latest == dataset)

        try await repository.deleteNormalizedHistory(sourceID: .codexRadar)
        #expect((try? await repository.latestStationStatus(sourceID: .codexRadar)) ?? nil == nil)
    }
}
