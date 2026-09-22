import CryptoKit
import Foundation
import Testing
@testable import AIRadar

/// v0.4.0 visual-spatial-reasoning sidecar tests (spec §5.7/§5.0): canonical
/// fixture parsing (summary + history), tolerant decode, fingerprint
/// behavior, transport host+path whitelist on both URLs, 8MiB oversize →
/// LKG, whole-set replacement retention, and the forbid-domain boundary.
@Suite("VisualSpatialReasoningDatasetTests")
struct VisualSpatialReasoningDatasetTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// SHA-256 of the canonical fixtures as captured (Tests fixture
    /// SHA256SUMS and docs/source-contract.md agree).
    private let canonicalFixtureSHA256 = "553bc5571985f75cdde37c9cc459beaa8b3dfa864658f75b0922e1d083ad0bdc"
    private let canonicalHistorySHA256 = "7fb359c792f165a00667f8b89a9e932fa5f63a3e20bcbb65851faeb75a4c9100"

    private func canonicalFixtureData() throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/AIRadarTests/Fixtures/VisualSpatialReasoning/visual-spatial-reasoning.json"))
    }

    private func canonicalHistoryData() throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/AIRadarTests/Fixtures/VisualSpatialReasoning/visual-spatial-reasoning-history.json"))
    }

    private func makeRepository() throws -> (RadarRepository, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-VSR-\(UUID().uuidString)", directoryHint: .isDirectory)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        return (repository, root)
    }

    private func dataset(fetchedAt: Date, iq: Double = 134.89) -> VisualSpatialReasoningDataset {
        VisualSpatialReasoningDataset(
            sourceID: .codexRadar,
            fetchedAt: fetchedAt,
            schema: 1,
            benchmarkID: "pompeii-adjacency",
            mode: "latest_valid_per_task",
            type: VisualSpatialReasoningParser.expectedType,
            scoreLabel: "Adjacency F1",
            scoringMode: "continuous-macro",
            sourceUpdatedAt: "2026-09-08T07:00:05+00:00",
            runs24hTotal: 26,
            runs48hTotal: 41,
            runsTotal: 412,
            points: [
                .init(
                    model: "gpt-6-astra",
                    effort: "high",
                    passed: 44.96,
                    validTasks: 50,
                    benchmarkTasks: 86,
                    iq: iq,
                    scoreMode: "continuous-macro",
                    averagePriceUSD: 1.65,
                    priceSamples: 50,
                    averageMinutes: 7.97,
                    durationSamples: 50,
                    incompleteCostSamples: 0,
                    averageAgentSteps: nil,
                    agentStepsSamples: 0,
                    averageTotalTokens: nil,
                    tokenSamples: 0,
                    cacheHitRate: 0.92,
                    cacheTokenSamples: 40,
                    combinedCostIndex: 118.4,
                    latestGradedAt: "2026-09-08T07:00:05+00:00",
                    runs24h: 9,
                    runs48h: 14,
                    runsTotal: 412
                ),
            ],
            history: [
                "gpt-6-astra@high": [
                    .init(ts: "2026-09-05T07:00:05+00:00", score: 150, n: 1),
                ],
            ]
        )
    }

    @Test("canonical fixtures match their recorded SHA-256 and parse completely")
    func canonicalFixturesParse() throws {
        let data = try canonicalFixtureData()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == canonicalFixtureSHA256)
        let historyData = try canonicalHistoryData()
        let historyDigest = SHA256.hash(data: historyData).map { String(format: "%02x", $0) }.joined()
        #expect(historyDigest == canonicalHistorySHA256)

        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let dataset = try VisualSpatialReasoningParser.parse(
            data,
            historyData: historyData,
            sourceID: .codexRadar,
            fetchedAt: fetchedAt
        )

        #expect(dataset.sourceID == .codexRadar)
        #expect(dataset.fetchedAt == fetchedAt)
        #expect(dataset.schema == 1)
        #expect(dataset.benchmarkID == "pompeii-adjacency")
        #expect(dataset.mode == "latest_valid_per_task")
        #expect(dataset.type == VisualSpatialReasoningParser.expectedType)
        #expect(dataset.scoreLabel == "Adjacency F1")
        #expect(dataset.scoringMode == "continuous-macro")
        #expect(dataset.sourceUpdatedAt == "2026-09-08T13:53:05.000Z")
        #expect(dataset.runs24hTotal == 62)
        #expect(dataset.runs48hTotal == 78)
        #expect(dataset.runsTotal == 4742)

        #expect(dataset.points.count == 2)
        let point = try #require(dataset.points.first)
        #expect(point.model == "gpt-6-astra")
        #expect(point.effort == "high")
        #expect(point.iq == 134.89)
        #expect(point.passed == 44.96)
        #expect(point.validTasks == 50.0)
        #expect(point.benchmarkTasks == 86.0)
        // Observed JSON nulls for the agent-steps/token columns decode as
        // nil values with zero samples (spec §1.1 23-key field table).
        #expect(point.averageAgentSteps == nil)
        #expect(point.agentStepsSamples == 0)
        #expect(point.averageTotalTokens == nil)
        #expect(point.tokenSamples == 0)
        #expect(point.cacheHitRate == 0.92)
        #expect(point.combinedCostIndex == 118.4)
        #expect(point.runsTotal == 412)

        // History is a "<model>@<effort>" keyed dictionary of series.
        #expect(dataset.history.count == 3)
        let series = try #require(dataset.history["gpt-6-astra@high"])
        #expect(series.first?.ts == "2026-09-05T07:00:05+00:00")
        #expect(series.first?.score == 150)
        #expect(series.first?.n == 1)
    }

    @Test("trimmed payloads and a failed history companion decode tolerantly")
    func tolerantDecoding() throws {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let minimal = try VisualSpatialReasoningParser.parse(
            Data("{}".utf8),
            historyData: nil,
            sourceID: .codexRadar,
            fetchedAt: fetchedAt
        )
        #expect(minimal.points.isEmpty)
        #expect(minimal.history.isEmpty)
        #expect(minimal.type == nil)

        // A missing history companion yields an empty series map.
        let payload = Data("""
        {"type":"visual_spatial_reasoning_summary","points":[]}
        """.utf8)
        let withoutHistory = try VisualSpatialReasoningParser.parse(
            payload,
            historyData: nil,
            sourceID: .codexRadar,
            fetchedAt: fetchedAt
        )
        #expect(withoutHistory.history.isEmpty)

        #expect(throws: VisualSpatialReasoningParseError.malformedJSON.self) {
            try VisualSpatialReasoningParser.parse(Data("{not json".utf8), historyData: nil, sourceID: .codexRadar, fetchedAt: fetchedAt)
        }
        #expect(throws: VisualSpatialReasoningParseError.unexpectedType("something_else").self) {
            try VisualSpatialReasoningParser.parse(
                Data(#"{"type":"something_else"}"#.utf8),
                historyData: nil,
                sourceID: .codexRadar,
                fetchedAt: fetchedAt
            )
        }
        #expect(throws: VisualSpatialReasoningParseError.malformedJSON.self) {
            try VisualSpatialReasoningParser.parse(
                Data(#"{"type":"visual_spatial_reasoning_summary"}"#.utf8),
                historyData: Data("{not json".utf8),
                sourceID: .codexRadar,
                fetchedAt: fetchedAt
            )
        }
    }

    @Test("summary payload with embedded list history decodes and derives series")
    func embeddedListHistory() throws {
        // 2026-09-20 live shape: the summary's own history is an observation
        // LIST, not the -history endpoint's keyed dictionary.
        let payloadText = "{\"type\":\"visual_spatial_reasoning_summary\",\"points\":[]," +
            "\"history\":[{\"at\":\"2026-08-18T08:00:00.000Z\",\"points\":[{\"model\":\"gpt-6-astra\",\"effort\":\"high\",\"iq\":134.8}]}," +
            "{\"at\":\"2026-08-19T08:00:00.000Z\",\"points\":[{\"model\":\"gpt-6-astra\",\"effort\":\"high\",\"iq\":135.2},{\"model\":\"m2\",\"effort\":\"low\"}]}]}"
        let dataset = try VisualSpatialReasoningParser.parse(
            Data(payloadText.utf8),
            historyData: nil,
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let series = try #require(dataset.history["gpt-6-astra@high"])
        #expect(series.count == 2)
        #expect(series[0].ts == "2026-08-18T08:00:00.000Z")
        #expect(series[0].score == 134.8)
        #expect(series[1].score == 135.2)
        // A point without iq contributes no history value.
        #expect((dataset.history["m2@low"]?.count ?? 0) == 0)
    }

    @Test("fingerprint ignores fetch time and is sensitive to content")
    func fingerprintBehavior() throws {
        let data = try canonicalFixtureData()
        let historyData = try canonicalHistoryData()
        let a = try VisualSpatialReasoningParser.parse(data, historyData: historyData, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1_752_566_500))
        let b = try VisualSpatialReasoningParser.parse(data, historyData: historyData, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1_799_999_999))
        let aFingerprint = try ContentFingerprint.visualSpatialReasoning(a)
        let bFingerprint = try ContentFingerprint.visualSpatialReasoning(b)
        #expect(aFingerprint == bFingerprint)

        let changed = dataset(fetchedAt: Date(timeIntervalSince1970: 100), iq: 120.0)
        let baseline = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        let changedFingerprint = try ContentFingerprint.visualSpatialReasoning(changed)
        let baselineFingerprint = try ContentFingerprint.visualSpatialReasoning(baseline)
        #expect(changedFingerprint != baselineFingerprint)
    }

    @Test("adapter pins both requests to the codexradar.com /api whitelist")
    func adapterHostWhitelist() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let transport = StubTransport(responses: [
            StubResponse(
                body: Data(#"{"type":"visual_spatial_reasoning_summary","points":[{"model":"m","effort":"high","iq":80}]}"#.utf8)
            ),
            StubResponse(body: Data(#"{"m@high":[{"ts":"2026-09-05T07:00:05+00:00","score":80,"n":1}]}"#.utf8)),
        ])
        let adapter = VisualSpatialReasoningAdapter(
            transport: transport,
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        _ = try await adapter.read()

        let requests = transport.requests
        #expect(requests.count == 2)
        let summaryRequest = try #require(requests.first)
        let historyRequest = try #require(requests.last)
        // Host+path double assertions on both URLs of the sidecar (§5.0).
        #expect(summaryRequest.url?.host == "codexradar.com")
        #expect(summaryRequest.url?.path == "/api/visual-spatial-reasoning")
        #expect(historyRequest.url?.host == "codexradar.com")
        #expect(historyRequest.url?.path == "/api/visual-spatial-reasoning-history")
        #expect(summaryRequest.url?.absoluteString.contains("api.codexradar.com") == false)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == "AIRadar/0.5.0 (macOS; +https://github.com/Acfufu/Radar)" })
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })

        // Both successful reads land in the shared raw-sample prune pool.
        let samples = try await RawSampleStore(dataRoot: storeRoot).samples(sourceID: .codexRadar)
        #expect(samples.count == 2)
        #expect(samples.allSatisfy { $0.outcome == .success })
    }

    @Test("adapter enforces status, MIME, and the 8MiB caps")
    func adapterRejections() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let oversized = VisualSpatialReasoningAdapter(
            transport: StubTransport(responses: [StubResponse(body: Data("truncated".utf8), truncated: true)]),
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        do {
            _ = try await oversized.read()
            Issue.record("expected oversized failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .oversized)
        }
        let oversizeSamples = try await RawSampleStore(dataRoot: storeRoot).samples(sourceID: .codexRadar)
        #expect(oversizeSamples.first?.outcome == .httpFailed)

        let badStatus = VisualSpatialReasoningAdapter(
            transport: StubTransport(responses: [StubResponse(body: Data(), status: 503, headers: [:])]),
            rawSampleStore: nil
        )
        do {
            _ = try await badStatus.read()
            Issue.record("expected status failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .status(503))
        }

        let badMIME = VisualSpatialReasoningAdapter(
            transport: StubTransport(responses: [StubResponse(body: Data("<html/>".utf8), headers: ["Content-Type": "text/html"])]),
            rawSampleStore: nil
        )
        do {
            _ = try await badMIME.read()
            Issue.record("expected MIME failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .mime)
        }

        #expect(VisualSpatialReasoningAdapter.maximumResponseBytes == 8 * 1_024 * 1_024)
    }

    @Test("repository replaces the whole snapshot per sync and clears with history")
    func repositoryReplaceAndClear() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        let second = dataset(fetchedAt: Date(timeIntervalSince1970: 200), iq: 130.0)

        let insertion = try await repository.insertVisualSpatialReasoning(first)
        #expect(insertion.inserted)
        let duplicate = try await repository.insertVisualSpatialReasoning(first)
        #expect(!duplicate.inserted)
        #expect(try await repository.snapshotCount(datasetType: .visualSpatialReasoning, sourceID: .codexRadar) == 1)

        // A changed dataset replaces the retained row: the series never
        // accumulates across syncs (spec §5.7 whole-set rule).
        _ = try await repository.insertVisualSpatialReasoning(second)
        #expect(try await repository.snapshotCount(datasetType: .visualSpatialReasoning, sourceID: .codexRadar) == 1)
        let state = try await repository.visualSpatialReasoningState(sourceID: .codexRadar)
        #expect(state.value == second)
        #expect(state.error == nil)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .visualSpatialReasoning)
        #expect(metadata.lastSuccessfulAt != nil)

        let history = try await repository.visualSpatialReasoningHistory(sourceID: .codexRadar)
        #expect(history == [second])

        try await repository.deleteNormalizedHistory(sourceID: .codexRadar)
        #expect(try await repository.snapshotCount(datasetType: .visualSpatialReasoning, sourceID: .codexRadar) == 0)
        let cleared = try await repository.visualSpatialReasoningState(sourceID: .codexRadar)
        #expect(cleared.value == nil)
        #expect(try await repository.metadata(sourceID: .codexRadar, datasetType: .visualSpatialReasoning) == .empty)
    }

    @Test("oversized refresh keeps the last known good snapshot")
    func oversizeRetainsLKG() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let cached = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        _ = try await repository.insertVisualSpatialReasoning(cached)

        let coordinator = VisualSpatialReasoningCoordinator(
            reader: StubReader(result: .failure(RadarHTTPError(kind: .oversized))),
            repository: repository
        )
        await coordinator.refresh(trigger: .manual)

        let projection = try await coordinator.projection()
        #expect(projection.state.value == cached)
        #expect(projection.state.error?.kind == .validation)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .visualSpatialReasoning)
        #expect(metadata.consecutiveFailures == 1)
    }
}

private struct StubReader: VisualSpatialReasoningReading {
    let result: Result<VisualSpatialReasoningDataset, Error>

    func read() async throws -> VisualSpatialReasoningDataset {
        try result.get()
    }

    func cancel() async {}
}

private struct StubResponse {
    let body: Data
    let status: Int
    let headers: [String: String]
    let truncated: Bool

    init(body: Data, status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], truncated: Bool = false) {
        self.body = body
        self.status = status
        self.headers = headers
        self.truncated = truncated
    }
}

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let responses: [StubResponse]
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var index = 0

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    init(responses: [StubResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let response: StubResponse = lock.withLock {
            defer { _requests.append(request) }
            if index < responses.count {
                let response = responses[index]
                index += 1
                return response
            }
            return responses.last ?? StubResponse(body: Data())
        }
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: nil,
            headerFields: response.headers
        )!
        return HTTPTransportResponse(data: response.body, response: http, bodyWasTruncated: response.truncated)
    }

    func cancelAll() async {}
}
