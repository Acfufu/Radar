import Foundation
import Testing
@testable import ClaudeRadar

@Suite("CodexRadarParserTests")
struct CodexRadarParserTests {
    @Test("public summary projects independent benchmark and quota datasets")
    func publicSummaryProjection() throws {
        // Given
        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)

        // When
        let envelope = try CodexRadarParser().parseBenchmarkEnvelope(
            fixture("codex-radar-public-summary"),
            fetchedAt: fetchedAt
        )

        // Then
        let benchmark = try #require(envelope.benchmark.value)
        let status = try #require(envelope.sourceStatus.value)
        #expect(benchmark.sourceID == .codexRadar)
        #expect(benchmark.seriesRevision == "codex-radar-public-v2")
        #expect(benchmark.sourceUpdatedAt == Date(timeIntervalSince1970: 1_784_102_400))
        #expect(benchmark.models.map(\.id.upstreamKey) == ["gpt-5.6-sol-high", "gpt-5.6-sol-max"])
        let max = try #require(benchmark.models.last)
        #expect(max.qualityScore == 120)
        #expect(max.passedTasks == 8)
        #expect(max.validTasks == 10)
        #expect(max.benchmarkCostUSD == Decimal(string: "12.5"))
        #expect(max.inputTokens == 1_000)
        #expect(max.cacheReadTokens == 800)
        #expect(max.outputTokens == 100)
        #expect(max.totalTokens == 1_100)
        #expect(max.elapsedSeconds == 3_600)
        #expect(max.cacheHitPercent == 80)
        #expect(status.sourceID == .codexRadar)
        #expect(status.quotaEstimates.map(\.windowLabel) == ["20x Pro · 7d", "5x Pro · 7d"])
        #expect(status.quotaEstimates.map(\.estimatedValueUSD) == [1_800, 450])
    }

    @Test("community ratings preserve Codex-scoped model identity")
    func communityProjection() throws {
        // Given
        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_800)

        // When
        let projection = try CodexRadarParser().parseCommunityEnvelope(
            fixture("codex-radar-community-valid"),
            fetchedAt: fetchedAt
        )

        // Then
        let community = try #require(projection.value)
        #expect(community.sourceID == .codexRadar)
        #expect(community.ratings.map(\.id) == [
            ModelID(sourceID: .codexRadar, upstreamKey: "gpt-5.6-sol-max"),
            ModelID(sourceID: .codexRadar, upstreamKey: "gpt-5.6-sol-high"),
        ])
        #expect(community.ratings[0].average == Decimal(string: "8.4"))
        #expect(community.ratings[0].voteCount == 24)
        #expect(community.ratings[1].average == nil)
    }

    @Test("invalid cached token count rejects benchmark without discarding valid quota")
    func invalidCacheCountIsSegmentScoped() throws {
        // Given
        let data = try mutatedSummary { latest in latest["cached_input_tokens"] = 1_001 }

        // When
        let envelope = try CodexRadarParser().parseBenchmarkEnvelope(data, fetchedAt: .now)

        // Then
        #expect(envelope.benchmark.value == nil)
        #expect(envelope.benchmark.error?.kind == .validation)
        #expect(envelope.sourceStatus.value != nil)
        #expect(envelope.sourceStatus.error == nil)
    }

    @Test("HTTP source shares one summary acquisition across benchmark and status")
    func sourceAcquisition() async throws {
        // Given
        let summaryURL = URL(string: "https://codex.test/current.json")!
        let communityURL = URL(string: "https://codex.test/api/model-ratings")!
        let transport = CodexTestTransport(routes: [
            summaryURL: try fixture("codex-radar-public-summary"),
            communityURL: try fixture("codex-radar-community-valid"),
        ])
        let source = RadarHTTPSource(
            configuration: CodexRadarConfiguration(summaryURL: summaryURL, communityURL: communityURL),
            transport: transport
        )

        // When
        let benchmark = try await source.fetchBenchmark()
        let status = try await source.fetchSourceStatus()
        let community = try await source.fetchCommunity()

        // Then
        #expect(source.descriptor.id == .codexRadar)
        #expect(benchmark.sourceID == .codexRadar)
        #expect(status?.sourceID == .codexRadar)
        #expect(community?.sourceID == .codexRadar)
        #expect(await transport.requestCount(for: summaryURL) == 1)
        #expect(await transport.requestCount(for: communityURL) == 1)
    }

    private func fixture(_ name: String) throws -> Data {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Sources/ClaudeRadar/Resources/Fixtures/\(name).json"))
    }

    private func mutatedSummary(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
        let data = try fixture("codex-radar-public-summary")
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var modelIQ = root["model_iq"] as? [String: Any],
              var latest = modelIQ["latest"] as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        mutation(&latest)
        modelIQ["latest"] = latest
        root["model_iq"] = modelIQ
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

private actor CodexTestTransport: HTTPTransport {
    private let routes: [URL: Data]
    private var counts: [URL: Int] = [:]

    init(routes: [URL: Data]) { self.routes = routes }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        guard let url = request.url, let data = routes[url] else { throw URLError(.unsupportedURL) }
        counts[url, default: 0] += 1
        return HTTPTransportResponse(
            data: data,
            response: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }

    func requestCount(for url: URL) -> Int { counts[url, default: 0] }
}
