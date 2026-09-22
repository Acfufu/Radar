import CryptoKit
import Foundation
import Testing
@testable import AIRadar

/// v0.4.0 radar-insights sidecar tests (spec §5.6/§5.0): canonical fixture
/// parsing, tolerant decode, fingerprint behavior, transport host+path
/// whitelist, 8MiB oversize → LKG, repository latest-only retention, and
/// the forbid-domain boundary.
@Suite("RadarInsightsDatasetTests")
struct RadarInsightsDatasetTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// SHA-256 of the canonical fixture as captured (Tests fixture SHA256SUMS
    /// and docs/source-contract.md agree).
    private let canonicalFixtureSHA256 = "6c2eb3aa0be2596dce8bed81285bdd959615b5ed89cde2b5f09755af72ff8466"

    private func canonicalFixtureData() throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/AIRadarTests/Fixtures/RadarInsights/radar-insights.json"))
    }

    private func makeRepository() throws -> (RadarRepository, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-RadarInsights-\(UUID().uuidString)", directoryHint: .isDirectory)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        return (repository, root)
    }

    private func dataset(fetchedAt: Date, iq: Double = 107.9) -> RadarInsightsDataset {
        RadarInsightsDataset(
            sourceID: .codexRadar,
            fetchedAt: fetchedAt,
            schema: 1,
            benchmarkID: RadarInsightsParser.expectedBenchmarkID,
            mode: "rolling_equal_per_task",
            recommendationMode: "comprehensive_weighted_mean",
            generatedAt: "2026-09-08T15:50:18+00:00",
            sourceUpdatedAt: "2026-09-08T13:53:05+00:00",
            softwareSourceUpdatedAt: "2026-09-08T15:49:31+00:00",
            visualSourceUpdatedAt: "2026-09-08T13:53:05+00:00",
            comprehensivePoints: [
                .init(model: "gpt-6-astra", effort: "ultra", iq: iq, softwareIq: 100.0, visualIq: 134.21, samples: 156),
            ],
            recommendations: [
                .init(
                    key: "daily_development",
                    title: "日常开发",
                    rule: "fixture rule",
                    items: [
                        .init(
                            model: "gpt-6-astra",
                            effort: "high",
                            iq: 105.5,
                            passed: 96.4,
                            samples: 141,
                            averageCostUSD: 1.82,
                            costSamples: 141,
                            averageDurationMinutes: 9.4,
                            durationSamples: 138,
                            combinedCostIndex: 17.3,
                            rule: "fixture item rule"
                        ),
                    ]
                ),
            ],
            degradationAlerts: .init(rule: "fixture alert rule", items: [])
        )
    }

    @Test("canonical fixture matches its recorded SHA-256 and parses completely")
    func canonicalFixtureParses() throws {
        let data = try canonicalFixtureData()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == canonicalFixtureSHA256)

        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let dataset = try RadarInsightsParser.parse(data, sourceID: .codexRadar, fetchedAt: fetchedAt)

        #expect(dataset.sourceID == .codexRadar)
        #expect(dataset.fetchedAt == fetchedAt)
        #expect(dataset.schema == 1)
        #expect(dataset.benchmarkID == "deep-swe")
        #expect(dataset.mode == "rolling_equal_per_task")
        #expect(dataset.recommendationMode == "comprehensive_weighted_mean")
        #expect(dataset.generatedAt == "2026-09-08T15:50:18+00:00")
        #expect(dataset.sourceUpdatedAt == "2026-09-08T13:53:05+00:00")
        #expect(dataset.softwareSourceUpdatedAt == "2026-09-08T15:49:31+00:00")
        #expect(dataset.visualSourceUpdatedAt == "2026-09-08T13:53:05+00:00")

        #expect(dataset.comprehensivePoints.count == 3)
        let point = try #require(dataset.comprehensivePoints.first)
        #expect(point.model == "gpt-6-astra")
        // Effort stays an open string rendered verbatim (upstream already
        // emits `ultra`; this captured fixture predates that tier).
        #expect(point.effort == "low")
        #expect(point.iq == 107.9)
        #expect(point.softwareIq == 100.0)
        #expect(point.visualIq == 134.21)
        #expect(point.samples == 156)

        #expect(dataset.recommendations.count == 2)
        let recommendation = try #require(dataset.recommendations.first)
        #expect(recommendation.key == "daily_development")
        #expect(recommendation.title == "日常开发")
        #expect(recommendation.rule?.isEmpty == false)
        let item = try #require(recommendation.items.first)
        #expect(item.model == "gpt-6-astra")
        #expect(item.effort == "medium")
        #expect(item.iq == 112.51)
        #expect(item.passed == 125.96)
        #expect(item.samples == 173)
        #expect(item.averageCostUSD == Decimal(string: "1.9"))
        #expect(item.costSamples == 173)
        #expect(item.averageDurationMinutes == 8.6)
        #expect(item.durationSamples == 173)
        #expect(item.combinedCostIndex == 119.51)
        #expect(item.rule?.isEmpty == false)

        #expect(dataset.degradationAlerts?.rule?.isEmpty == false)
        #expect(dataset.degradationAlerts?.items.isEmpty == true)
    }

    @Test("trimmed and empty payloads decode tolerantly")
    func tolerantDecoding() throws {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let minimal = try RadarInsightsParser.parse(Data("{}".utf8), sourceID: .codexRadar, fetchedAt: fetchedAt)
        #expect(minimal.comprehensivePoints.isEmpty)
        #expect(minimal.recommendations.isEmpty)
        #expect(minimal.degradationAlerts == nil)
        #expect(minimal.benchmarkID == nil)
        #expect(minimal.sourceID == .codexRadar)

        // degradation_alerts tolerates a missing items key (items observed
        // empty upstream; element fields are all optional either way).
        let payload = Data("""
        {"benchmark_id":"deep-swe","degradation_alerts":{"rule":"r"}}
        """.utf8)
        let dataset = try RadarInsightsParser.parse(payload, sourceID: .codexRadar, fetchedAt: fetchedAt)
        #expect(dataset.degradationAlerts?.rule == "r")
        #expect(dataset.degradationAlerts?.items.isEmpty == true)

        #expect(throws: RadarInsightsParseError.malformedJSON.self) {
            try RadarInsightsParser.parse(Data("{not json".utf8), sourceID: .codexRadar, fetchedAt: fetchedAt)
        }
        #expect(throws: RadarInsightsParseError.unexpectedBenchmark("other-benchmark").self) {
            try RadarInsightsParser.parse(
                Data(#"{"benchmark_id":"other-benchmark"}"#.utf8),
                sourceID: .codexRadar,
                fetchedAt: fetchedAt
            )
        }
    }

    @Test("fingerprint ignores fetch time and is sensitive to content")
    func fingerprintBehavior() throws {
        let data = try canonicalFixtureData()
        let a = try RadarInsightsParser.parse(data, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1_752_566_500))
        let b = try RadarInsightsParser.parse(data, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1_799_999_999))
        let aFingerprint = try ContentFingerprint.radarInsights(a)
        let bFingerprint = try ContentFingerprint.radarInsights(b)
        #expect(aFingerprint == bFingerprint)

        let changed = dataset(fetchedAt: Date(timeIntervalSince1970: 100), iq: 99.5)
        let baseline = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        let changedFingerprint = try ContentFingerprint.radarInsights(changed)
        let baselineFingerprint = try ContentFingerprint.radarInsights(baseline)
        #expect(changedFingerprint != baselineFingerprint)
    }

    @Test("adapter pins every request to the codexradar.com /api whitelist")
    func adapterHostWhitelist() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let transport = StubTransport(
            body: Data(#"{"benchmark_id":"deep-swe","comprehensive_points":[{"model":"m","effort":"high","iq":80}]}"#.utf8),
            status: 200,
            headers: ["Content-Type": "application/json"]
        )
        let adapter = RadarInsightsAdapter(
            transport: transport,
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        _ = try await adapter.read()

        let requests = transport.requests
        let request = try #require(requests.first)
        // Host+path double assertion (spec §5.0): no URL may ever be built
        // from response data fields.
        #expect(request.url?.host == "codexradar.com")
        #expect(request.url?.path == "/api/radar-insights")
        #expect(request.url?.absoluteString.contains("api.codexradar.com") == false)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "AIRadar/0.5.0 (macOS; +https://github.com/Acfufu/Radar)")
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

        let oversized = RadarInsightsAdapter(
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

        let badStatus = RadarInsightsAdapter(
            transport: StubTransport(body: Data(), status: 503),
            rawSampleStore: nil
        )
        do {
            _ = try await badStatus.read()
            Issue.record("expected status failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .status(503))
        }

        let badMIME = RadarInsightsAdapter(
            transport: StubTransport(body: Data("<html/>".utf8), status: 200, headers: ["Content-Type": "text/html"]),
            rawSampleStore: nil
        )
        do {
            _ = try await badMIME.read()
            Issue.record("expected MIME failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .mime)
        }

        #expect(RadarInsightsAdapter.maximumResponseBytes == 8 * 1_024 * 1_024)
    }

    @Test("benchmark-mismatch payload records a validation-failed sample")
    func adapterValidationSample() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let adapter = RadarInsightsAdapter(
            transport: StubTransport(
                body: Data(#"{"benchmark_id":"not-deep-swe"}"#.utf8),
                status: 200,
                headers: ["Content-Type": "application/json"]
            ),
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        do {
            _ = try await adapter.read()
            Issue.record("expected validation failure")
        } catch {
            #expect(error is RadarInsightsParseError)
        }
        let samples = try await RawSampleStore(dataRoot: storeRoot).samples(sourceID: .codexRadar)
        #expect(samples.first?.outcome == .validationFailed)
    }

    @Test("repository keeps a single latest snapshot and clears with history")
    func repositoryReplaceAndClear() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        let second = dataset(fetchedAt: Date(timeIntervalSince1970: 200), iq: 108.5)

        let insertion = try await repository.insertRadarInsights(first)
        #expect(insertion.inserted)
        let duplicate = try await repository.insertRadarInsights(first)
        #expect(!duplicate.inserted)
        #expect(try await repository.snapshotCount(datasetType: .radarInsights, sourceID: .codexRadar) == 1)

        _ = try await repository.insertRadarInsights(second)
        #expect(try await repository.snapshotCount(datasetType: .radarInsights, sourceID: .codexRadar) == 1)
        let state = try await repository.radarInsightsState(sourceID: .codexRadar)
        #expect(state.value == second)
        #expect(state.error == nil)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .radarInsights)
        #expect(metadata.lastSuccessfulAt != nil)

        let history = try await repository.radarInsightsHistory(sourceID: .codexRadar)
        #expect(history == [second])

        try await repository.deleteNormalizedHistory(sourceID: .codexRadar)
        #expect(try await repository.snapshotCount(datasetType: .radarInsights, sourceID: .codexRadar) == 0)
        let cleared = try await repository.radarInsightsState(sourceID: .codexRadar)
        #expect(cleared.value == nil)
        #expect(try await repository.metadata(sourceID: .codexRadar, datasetType: .radarInsights) == .empty)
    }

    @Test("oversized refresh keeps the last known good snapshot")
    func oversizeRetainsLKG() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let cached = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        _ = try await repository.insertRadarInsights(cached)

        let coordinator = RadarInsightsCoordinator(
            reader: StubReader(result: .failure(RadarHTTPError(kind: .oversized))),
            repository: repository
        )
        await coordinator.refresh(trigger: .manual)

        let projection = try await coordinator.projection()
        #expect(projection.state.value == cached)
        #expect(projection.state.error?.kind == .validation)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .radarInsights)
        #expect(metadata.consecutiveFailures == 1)
    }
}

private struct StubReader: RadarInsightsReading {
    let result: Result<RadarInsightsDataset, Error>

    func read() async throws -> RadarInsightsDataset {
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
