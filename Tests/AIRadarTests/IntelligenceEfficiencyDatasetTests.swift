import CryptoKit
import Foundation
import Testing
@testable import AIRadar

/// P2② intelligence-efficiency sidecar tests (spec §5.2/§5.0): canonical
/// fixture parsing, tolerant decode, fingerprint behavior, transport host
/// whitelist, 8MiB oversize → LKG, repository replace-per-sync retention,
/// and the forbid-domain boundary.
@Suite("IntelligenceEfficiencyDatasetTests")
struct IntelligenceEfficiencyDatasetTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// SHA-256 of the canonical fixture as captured (Tests fixture SHA256SUMS).
    private let canonicalFixtureSHA256 = "2f9416d8fd19c946b7138246d6ca8f7b175134ea5344bf2c52c339c1f04bb386"

    private func canonicalFixtureData() throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/AIRadarTests/Fixtures/IntelligenceEfficiency/intelligence-efficiency.json"))
    }

    private func makeRepository() throws -> (RadarRepository, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-IE-\(UUID().uuidString)", directoryHint: .isDirectory)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        return (repository, root)
    }

    private func dataset(fetchedAt: Date, iq: Double = 81.25) -> IntelligenceEfficiencyDataset {
        IntelligenceEfficiencyDataset(
            sourceID: .codexRadar,
            fetchedAt: fetchedAt,
            schema: 2,
            mode: "equal_latest_3",
            type: IntelligenceEfficiencyParser.expectedType,
            source: "https://api.codexradar.com/api/v1/table",
            metricsSource: "https://api.codexradar.com/api/v1/intelligence-efficiency",
            sourceUpdatedAt: "2026-09-05T01:27:38+08:00",
            models: 17,
            runs24hTotal: 267,
            runs48hTotal: 375,
            runsTotal: 42_903,
            points: [
                .init(
                    model: "gpt-5.6-sol",
                    effort: "low",
                    harness: "codex",
                    iq: iq,
                    passed: 182,
                    validTasks: 336,
                    averagePriceUSD: 1.603735,
                    priceSamples: 0,
                    averageMinutes: 10.3,
                    durationSamples: 0,
                    incompleteCostSamples: 0,
                    totalRuns: 1_876,
                    latestGradedAt: "2026-09-04T05:38:54+00:00",
                    averageAgentSteps: 42.335366,
                    agentStepsSamples: 328,
                    averageTotalTokens: 2_070_270.702381,
                    tokenSamples: 336,
                    cacheHitRate: 0.953387,
                    cacheTokenSamples: 336,
                    averagePriceUSDBand: nil,
                    runs24h: 3,
                    runs48h: 5,
                    runsTotal: 1_876,
                    rawCombinedCost: 175.520444,
                    combinedCostIndex: 0.0446
                ),
            ],
            history: [
                .init(
                    at: "2026-09-01T00:00:00+08:00",
                    points: [
                        .init(
                            model: "gpt-5.6-sol",
                            effort: "low",
                            passed: 180,
                            validTasks: 336,
                            iq: 80.9,
                            averagePriceUSD: 1.59,
                            priceSamples: 300,
                            averageMinutes: 10.1,
                            durationSamples: 298,
                            averageAgentSteps: 42.0,
                            agentStepsSamples: 300,
                            averageTotalTokens: 2_000_000.5,
                            tokenSamples: 330,
                            cacheHitRate: 0.95,
                            cacheTokenSamples: 330
                        ),
                    ]
                ),
            ],
            fingerprint: "5c74943b2fd7381e547e16725708b325dd3edb588fdf78f800cdc00f4c9f903a",
            activityFingerprint: "f33a99e9dea3952f694bc9ecbea9b15923ea00060faf2cd09e8c5bc05d76dbef",
            method: .init(
                iq: "equal-weight latest three valid samples per task; pass_rate * 150",
                price: "price method",
                duration: "duration method",
                combinedCost: "combined cost method"
            )
        )
    }

    @Test("canonical fixture matches its recorded SHA-256 and parses completely")
    func canonicalFixtureParses() throws {
        let data = try canonicalFixtureData()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == canonicalFixtureSHA256)

        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let dataset = try IntelligenceEfficiencyParser.parse(data, sourceID: .codexRadar, fetchedAt: fetchedAt)

        #expect(dataset.sourceID == .codexRadar)
        #expect(dataset.fetchedAt == fetchedAt)
        #expect(dataset.schema == 2)
        #expect(dataset.mode == "equal_latest_3")
        #expect(dataset.type == IntelligenceEfficiencyParser.expectedType)
        // Provenance strings are stored verbatim (attribution only; never
        // requested — the host whitelist test pins the request path).
        #expect(dataset.source == "https://api.codexradar.com/api/v1/table")
        #expect(dataset.metricsSource == "https://api.codexradar.com/api/v1/intelligence-efficiency")
        #expect(dataset.sourceUpdatedAt == "2026-09-05T01:27:38+08:00")
        #expect(dataset.models == 17)
        #expect(dataset.runs24hTotal == 267)
        #expect(dataset.runs48hTotal == 375)
        #expect(dataset.runsTotal == 42_903)
        #expect(dataset.points.count == 58)
        #expect(dataset.history.count == 255)
        #expect(dataset.fingerprint?.count == 64)
        #expect(dataset.activityFingerprint?.count == 64)
        #expect(dataset.method?.iq?.isEmpty == false)
        #expect(dataset.method?.price?.isEmpty == false)
        #expect(dataset.method?.duration?.isEmpty == false)
        #expect(dataset.method?.combinedCost?.isEmpty == false)

        let point = try #require(dataset.points.first)
        #expect(point.model == "gpt-5.6-sol")
        #expect(point.effort == "low")
        #expect(point.harness == "codex")
        #expect(point.iq == 81.25)
        #expect(point.passed == 182.0)
        #expect(point.validTasks == 336.0)
        #expect(point.averagePriceUSD == Decimal(string: "1.603735"))
        #expect(point.priceSamples == 0)
        #expect(point.averageMinutes == 10.3)
        #expect(point.durationSamples == 0)
        #expect(point.incompleteCostSamples == 0)
        #expect(point.totalRuns == 1_876)
        #expect(point.latestGradedAt == "2026-09-04T05:38:54+00:00")
        #expect(point.averageAgentSteps == 42.335366)
        #expect(point.agentStepsSamples == 328)
        #expect(point.averageTotalTokens == 2_070_270.702381)
        #expect(point.tokenSamples == 336)
        #expect(point.cacheHitRate == 0.953387)
        #expect(point.cacheTokenSamples == 336)
        #expect(point.averagePriceUSDBand == nil)
        #expect(point.runs24h == 3)
        #expect(point.runs48h == 5)
        #expect(point.runsTotal == 1_876)
        #expect(point.rawCombinedCost == Decimal(string: "175.520444"))
        #expect(point.combinedCostIndex == 0.0446)

        // DeepSeek rows carry the off-peak/peak price band.
        let banded = try #require(dataset.points.first { $0.averagePriceUSDBand != nil })
        #expect(banded.averagePriceUSDBand?.offPeak != nil)
        #expect(banded.averagePriceUSDBand?.peak != nil)

        let entry = try #require(dataset.history.first)
        #expect(entry.at == "2026-07-23T04:55:27+08:00")
        let historyPoint = try #require(entry.points.first)
        #expect(historyPoint.model == "gpt-5.6-terra")
        #expect(historyPoint.effort == "medium")
        #expect(historyPoint.iq == 55.8824)
        #expect(historyPoint.validTasks == 102.0)
        #expect(historyPoint.cacheHitRate == 0.956467)
    }

    @Test("trimmed and empty payloads decode tolerantly")
    func tolerantDecoding() throws {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let minimal = try IntelligenceEfficiencyParser.parse(Data("{}".utf8), sourceID: .codexRadar, fetchedAt: fetchedAt)
        #expect(minimal.points.isEmpty)
        #expect(minimal.history.isEmpty)
        #expect(minimal.type == nil)
        #expect(minimal.sourceID == .codexRadar)

        // history entries tolerate a missing points key.
        let payload = Data("""
        {"type":"distributed_intelligence_efficiency","history":[{"at":"2026-09-01T00:00:00+08:00"}]}
        """.utf8)
        let dataset = try IntelligenceEfficiencyParser.parse(payload, sourceID: .codexRadar, fetchedAt: fetchedAt)
        #expect(dataset.history.count == 1)
        #expect(dataset.history.first?.points.isEmpty == true)

        #expect(throws: IntelligenceEfficiencyParseError.malformedJSON.self) {
            try IntelligenceEfficiencyParser.parse(Data("{not json".utf8), sourceID: .codexRadar, fetchedAt: fetchedAt)
        }
        #expect(throws: IntelligenceEfficiencyParseError.unexpectedType("something_else").self) {
            try IntelligenceEfficiencyParser.parse(
                Data(#"{"type":"something_else"}"#.utf8),
                sourceID: .codexRadar,
                fetchedAt: fetchedAt
            )
        }
    }

    @Test("fingerprint ignores fetch time and is sensitive to content")
    func fingerprintBehavior() throws {
        let data = try canonicalFixtureData()
        let a = try IntelligenceEfficiencyParser.parse(data, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1_752_566_500))
        let b = try IntelligenceEfficiencyParser.parse(data, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1_799_999_999))
        let aFingerprint = try ContentFingerprint.intelligenceEfficiency(a)
        let bFingerprint = try ContentFingerprint.intelligenceEfficiency(b)
        #expect(aFingerprint == bFingerprint)

        let changed = dataset(fetchedAt: Date(timeIntervalSince1970: 100), iq: 99.5)
        let baseline = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        let changedFingerprint = try ContentFingerprint.intelligenceEfficiency(changed)
        let baselineFingerprint = try ContentFingerprint.intelligenceEfficiency(baseline)
        #expect(changedFingerprint != baselineFingerprint)
    }

    @Test("adapter pins every request to the codexradar.com /data whitelist")
    func adapterHostWhitelist() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let transport = StubTransport(
            body: Data(#"{"type":"distributed_intelligence_efficiency","points":[{"model":"m","effort":"high","iq":80}]}"#.utf8),
            status: 200,
            headers: ["Content-Type": "application/json"]
        )
        let adapter = IntelligenceEfficiencyAdapter(
            transport: transport,
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        _ = try await adapter.read()

        let requests = transport.requests
        let request = try #require(requests.first)
        #expect(request.url?.host == "codexradar.com")
        #expect(request.url?.path == "/data/intelligence-efficiency.json")
        #expect(request.url?.absoluteString.contains("api.codexradar.com") == false)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "AIRadar/0.3.0 (macOS; +https://github.com/Acfufu/Radar)")
        #expect(request.httpMethod == "GET")

        // A successful read lands in the shared raw-sample prune pool.
        let samples = try await RawSampleStore(dataRoot: storeRoot).samples(sourceID: .codexRadar)
        #expect(samples.count == 1)
        #expect(samples.first?.outcome == .success)
    }

    @Test("adapter enforces status, MIME, and the 8MiB caps")
    func adapterRejections() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let oversized = IntelligenceEfficiencyAdapter(
            transport: StubTransport(body: Data("truncated".utf8), status: 200, truncated: true),
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

        let badStatus = IntelligenceEfficiencyAdapter(
            transport: StubTransport(body: Data(), status: 503),
            rawSampleStore: nil
        )
        do {
            _ = try await badStatus.read()
            Issue.record("expected status failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .status(503))
        }

        let badMIME = IntelligenceEfficiencyAdapter(
            transport: StubTransport(body: Data("<html/>".utf8), status: 200, headers: ["Content-Type": "text/html"]),
            rawSampleStore: nil
        )
        do {
            _ = try await badMIME.read()
            Issue.record("expected MIME failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .mime)
        }

        #expect(IntelligenceEfficiencyAdapter.maximumResponseBytes == 8 * 1_024 * 1_024)
    }

    @Test("type-mismatch payload records a validation-failed sample")
    func adapterValidationSample() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let adapter = IntelligenceEfficiencyAdapter(
            transport: StubTransport(
                body: Data(#"{"type":"not-the-expected-type"}"#.utf8),
                status: 200,
                headers: ["Content-Type": "application/json"]
            ),
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        do {
            _ = try await adapter.read()
            Issue.record("expected validation failure")
        } catch {
            #expect(error is IntelligenceEfficiencyParseError)
        }
        let samples = try await RawSampleStore(dataRoot: storeRoot).samples(sourceID: .codexRadar)
        #expect(samples.first?.outcome == .validationFailed)
    }

    @Test("repository keeps a single latest snapshot and clears with history")
    func repositoryReplaceAndClear() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        let second = dataset(fetchedAt: Date(timeIntervalSince1970: 200), iq: 82)

        let insertion = try await repository.insertIntelligenceEfficiency(first)
        #expect(insertion.inserted)
        let duplicate = try await repository.insertIntelligenceEfficiency(first)
        #expect(!duplicate.inserted)
        #expect(try await repository.snapshotCount(datasetType: .intelligenceEfficiency, sourceID: .codexRadar) == 1)

        _ = try await repository.insertIntelligenceEfficiency(second)
        #expect(try await repository.snapshotCount(datasetType: .intelligenceEfficiency, sourceID: .codexRadar) == 1)
        let state = try await repository.intelligenceEfficiencyState(sourceID: .codexRadar)
        #expect(state.value == second)
        #expect(state.error == nil)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .intelligenceEfficiency)
        #expect(metadata.lastSuccessfulAt != nil)

        let history = try await repository.intelligenceEfficiencyHistory(sourceID: .codexRadar)
        #expect(history == [second])

        try await repository.deleteNormalizedHistory(sourceID: .codexRadar)
        #expect(try await repository.snapshotCount(datasetType: .intelligenceEfficiency, sourceID: .codexRadar) == 0)
        let cleared = try await repository.intelligenceEfficiencyState(sourceID: .codexRadar)
        #expect(cleared.value == nil)
        #expect(try await repository.metadata(sourceID: .codexRadar, datasetType: .intelligenceEfficiency) == .empty)
    }

    @Test("oversized refresh keeps the last known good snapshot")
    func oversizeRetainsLKG() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let cached = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        _ = try await repository.insertIntelligenceEfficiency(cached)

        let coordinator = IntelligenceEfficiencyCoordinator(
            reader: StubReader(result: .failure(RadarHTTPError(kind: .oversized))),
            repository: repository
        )
        await coordinator.refresh(trigger: .manual)

        let projection = try await coordinator.projection()
        #expect(projection.state.value == cached)
        #expect(projection.state.error?.kind == .validation)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .intelligenceEfficiency)
        #expect(metadata.consecutiveFailures == 1)
    }
}

private struct StubReader: IntelligenceEfficiencyReading {
    let result: Result<IntelligenceEfficiencyDataset, Error>

    func read() async throws -> IntelligenceEfficiencyDataset {
        try result.get()
    }

    func cancel() async {}
}

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let body: Data
    private let status: Int
    private let headers: [String: String]
    private let truncated: Bool
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    init(body: Data, status: Int, headers: [String: String] = ["Content-Type": "application/json"], truncated: Bool = false) {
        self.body = body
        self.status = status
        self.headers = headers
        self.truncated = truncated
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        lock.withLock { _requests.append(request) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        return HTTPTransportResponse(data: body, response: response, bodyWasTruncated: truncated)
    }

    func cancelAll() async {}
}
