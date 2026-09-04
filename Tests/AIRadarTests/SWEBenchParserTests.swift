import Foundation
import SwiftData
import Testing
@testable import AIRadar

@Suite("SWEBenchParserTests")
struct SWEBenchParserTests {
    @Test("mini-SWE-agent v2 results project exact Verified metrics and collapse compatible duplicates")
    func verifiedProjection() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)

        let envelope = try SWEBenchParser().parseBenchmarkEnvelope(
            fixture(),
            fetchedAt: fetchedAt
        )

        let benchmark = try #require(envelope.benchmark.value)
        #expect(benchmark.sourceID == .sweBenchVerified)
        #expect(benchmark.sourceUpdatedAt == nil)
        #expect(benchmark.fetchedAt == fetchedAt)
        #expect(benchmark.benchmarkName == "SWE-bench Verified · mini-SWE-agent v2")
        #expect(benchmark.seriesRevision == "swe-bench-verified-mini-v2-v1")
        #expect(benchmark.models.map(\.id.upstreamKey) == [
            "20260217_mini-v2.0.0_claude-opus",
            "20260218_mini-v2.0.0-gpt",
        ])
        #expect(benchmark.models[0].qualityScore == Decimal(string: "76.8"))
        #expect(benchmark.models[0].passedTasks == 384)
        #expect(benchmark.models[0].validTasks == 500)
        #expect(benchmark.models[0].benchmarkCostUSD == Decimal(string: "376.9539985"))
        #expect(benchmark.models[1].passedTasks == 360)
        #expect(benchmark.models[1].benchmarkCostUSD == nil)
        #expect(envelope.sourceStatus.error?.kind == .disabled)
    }

    @Test("conflicting duplicate identity rejects the whole benchmark projection")
    func conflictingDuplicate() throws {
        var root = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var boards = try #require(root["leaderboards"] as? [[String: Any]])
        var results = try #require(boards[0]["results"] as? [[String: Any]])
        results[1]["cost"] = 1
        boards[0]["results"] = results
        root["leaderboards"] = boards
        let data = try JSONSerialization.data(withJSONObject: root)

        let envelope = try SWEBenchParser().parseBenchmarkEnvelope(data, fetchedAt: .now)

        #expect(envelope.benchmark.value == nil)
        #expect(envelope.benchmark.error?.kind == .validation)
    }

    @Test("SWE-bench source accepts official text plain payload and advertises read-only JSON text")
    func sourceHTTPPolicy() async throws {
        let url = URL(string: "https://example.test/leaderboards.json")!
        let transport = SWEBenchTestTransport(url: url, data: try fixture())
        let source = RadarHTTPSource(
            configuration: SWEBenchConfiguration(leaderboardURL: url),
            transport: transport
        )

        let benchmark = try await source.fetchBenchmark()

        #expect(benchmark.sourceID == .sweBenchVerified)
        #expect(try await source.fetchSourceStatus() == nil)
        #expect(await transport.acceptHeader == "application/json, text/plain")
    }

    @Test("synchronization stores benchmark without manufacturing source status failure")
    func synchronizationWithoutStatus() async throws {
        let url = URL(string: "https://example.test/leaderboards.json")!
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SWEBench-Sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try RadarModelSchema.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = RadarRepository(
            container: container,
            metadataStore: SyncMetadataStore(root: root)
        )
        let source = RadarHTTPSource(
            configuration: SWEBenchConfiguration(leaderboardURL: url),
            transport: SWEBenchTestTransport(url: url, data: try fixture())
        )
        let coordinator = RadarSyncCoordinator(source: source, repository: repository)

        await coordinator.refresh(trigger: .manual)
        let projection = try await coordinator.projection()

        #expect(projection.benchmark.value?.sourceID == .sweBenchVerified)
        #expect(projection.benchmark.error == nil)
        #expect(projection.sourceStatus.value == nil)
        #expect(projection.sourceStatus.error == nil)
        await coordinator.stop()
    }

    private func fixture() throws -> Data {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appending(
            path: "Sources/AIRadar/Resources/Fixtures/swe-bench-mini-v2.json"
        ))
    }
}

private actor SWEBenchTestTransport: HTTPTransport {
    let url: URL
    let data: Data
    private(set) var acceptHeader: String?

    init(url: URL, data: Data) {
        self.url = url
        self.data = data
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        acceptHeader = request.value(forHTTPHeaderField: "Accept")
        return HTTPTransportResponse(
            data: data,
            response: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain; charset=utf-8"]
            )!
        )
    }
}
