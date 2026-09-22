import CryptoKit
import Foundation
import Testing
@testable import AIRadar

/// P2③ fast-radar sidecar tests (spec §5.3/§5.0): canonical fixture parsing,
/// tolerant decode, derived ratios and month buckets, transport host
/// whitelist, 8MiB oversize → LKG, replace-per-sync retention (no cross-sync
/// accumulation), and the forbid-domain boundary.
@Suite("FastRadarHistoryDatasetTests")
struct FastRadarHistoryDatasetTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// SHA-256 of the canonical fixture as captured (Tests fixture SHA256SUMS).
    /// v0.5.0 canonical = dual format (3 legacy trio runs + 6 per-model astra
    /// runs incl. one `tps_available=false`), carved from the 2026-09-22
    /// upstream payload; the pre-v0.5.0 legacy-only capture stays as
    /// `fast-radar-history-legacy.json`.
    private let canonicalFixtureSHA256 = "73b2ee17a5cb4fe74115fff3c7057a2935540100311be13d3281676655ff60b0"
    private let legacyFixtureSHA256 = "be947fad68b90c684f5670d8eddf2e58b3b313219b0a514c0ab57b9fee96b862"

    private func canonicalFixtureData() throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/AIRadarTests/Fixtures/FastRadarHistory/fast-radar-history.json"))
    }

    private func legacyFixtureData() throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/AIRadarTests/Fixtures/FastRadarHistory/fast-radar-history-legacy.json"))
    }

    private func makeRepository() throws -> (RadarRepository, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AIRadar-FRH-\(UUID().uuidString)", directoryHint: .isDirectory)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        return (repository, root)
    }

    private func tier(standardTTFT: Double, fastTTFT: Double, standardTPS: Double = 50, fastTPS: Double = 70, standardE2E: Double = 49, fastE2E: Double = 20) -> FastRadarHistoryDataset.FastRadarRun.Tier {
        .init(
            standard: .init(ttftSeconds: standardTTFT, tps: standardTPS, e2eSeconds: standardE2E),
            fast: .init(ttftSeconds: fastTTFT, tps: fastTPS, e2eSeconds: fastE2E)
        )
    }

    private func dataset(fetchedAt: Date, solTTFT: Double = 8.0, extraRun: Bool = false) -> FastRadarHistoryDataset {
        var runs = [
            FastRadarHistoryDataset.FastRadarRun(
                runID: "20260820-0900",
                measuredAt: "2026-08-20T09:00:00+08:00",
                completedAt: "2026-08-20T09:06:00+08:00",
                cliVersion: "0.147.0",
                models: ["sol": tier(standardTTFT: solTTFT, fastTTFT: 3.4), "terra": tier(standardTTFT: 8.4, fastTTFT: 3.6)]
            ),
        ]
        if extraRun {
            runs.append(FastRadarHistoryDataset.FastRadarRun(
                runID: "20260904-1314",
                measuredAt: "2026-09-04T13:14:54+08:00",
                completedAt: "2026-09-04T13:20:24+08:00",
                cliVersion: "0.149.0",
                models: ["luna": tier(standardTTFT: 7.4, fastTTFT: 3.0)]
            ))
        }
        return FastRadarHistoryDataset(
            sourceID: .codexRadar,
            fetchedAt: fetchedAt,
            schemaVersion: 1,
            type: FastRadarHistoryParser.expectedType,
            timezone: "Asia/Shanghai",
            updatedAt: "2026-09-04T13:20:24+08:00",
            runs: runs
        )
    }

    @Test("canonical dual-format fixture matches its recorded SHA-256 and parses completely")
    func canonicalFixtureParses() throws {
        let data = try canonicalFixtureData()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == canonicalFixtureSHA256)

        let fetchedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let dataset = try FastRadarHistoryParser.parse(data, sourceID: .codexRadar, fetchedAt: fetchedAt)

        #expect(dataset.sourceID == .codexRadar)
        #expect(dataset.fetchedAt == fetchedAt)
        #expect(dataset.schemaVersion == 1)
        #expect(dataset.type == FastRadarHistoryParser.expectedType)
        #expect(dataset.timezone == "Asia/Shanghai")
        #expect(dataset.updatedAt == "2026-09-21T10:20:55+08:00")
        #expect(dataset.runs.count == 9)

        // Legacy trio shape: first run keeps its sol/terra/luna tiers.
        let first = try #require(dataset.runs.first)
        #expect(first.runID == "20260720-0850")
        #expect(first.measuredAt == "2026-07-20T08:50:02+08:00")
        #expect(first.completedAt == "2026-07-20T08:57:53+08:00")
        #expect(first.cliVersion == nil)
        #expect(first.model == nil)
        let standard = try #require(first.models?["sol"]?.standard)
        #expect(standard.ttftSeconds == 9.000502638666667)
        #expect(standard.tps == 56.392279071085504)
        #expect(standard.e2eSeconds == 45.880695764)

        // Per-model shape: last run carries model/effort and an `astra` tier.
        let last = try #require(dataset.runs.last)
        #expect(last.runID == "20260921-1007-xhigh")
        #expect(last.cliVersion == "0.155.0-alpha.9.2")
        #expect(last.model == "gpt-6-astra")
        #expect(last.effort == "xhigh")
        #expect(last.profile == "gpt-6-astra/xhigh")
        #expect(last.validPairs == 3)
        #expect(last.sampleCount == 6)
        #expect(last.tpsAvailable == true)
        let astraStandard = try #require(last.models?["astra"]?.standard)
        #expect(astraStandard.tps == 33.22193905452613)
    }

    @Test("legacy-only fixture still decodes after the canonical swap")
    func legacyFixtureStillParses() throws {
        let data = try legacyFixtureData()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == legacyFixtureSHA256)

        let dataset = try FastRadarHistoryParser.parse(data, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1))
        #expect(dataset.runs.count >= 82)
        #expect(dataset.runs.allSatisfy { $0.model == nil && $0.effort == nil })
    }

    @Test("per-model runs evaluate with model+effort labels and keep tps-unavailable paths honest")
    func perModelEvaluation() throws {
        let data = try canonicalFixtureData()
        let dataset = try FastRadarHistoryParser.parse(data, sourceID: .codexRadar, fetchedAt: Date(timeIntervalSince1970: 1))

        let xhigh = try #require(dataset.runs.last { $0.effort == "xhigh" })
        let comparisons = FastRadarAnalysis.evaluate(run: xhigh)
        #expect(comparisons.count == 1)
        #expect(comparisons.first?.model == "gpt-6-astra")
        #expect(comparisons.first?.effort == "xhigh")
        #expect(comparisons.first?.id == "gpt-6-astra#xhigh")
        #expect(comparisons.first?.ttftRatio != nil)
        #expect(comparisons.first?.tpsRatio != nil)
        #expect(comparisons.first?.e2eRatio != nil)
        // displayModel prefers the run-level id over the short dict key.
        #expect(xhigh.displayModel == "gpt-6-astra")

        // tps_available=false run: TPS ratios stay nil (no substitution),
        // TTFT/E2E ratios still derive, and the upstream reason is preserved.
        let noTPS = try #require(dataset.runs.first { $0.tpsAvailable == false })
        #expect(noTPS.tpsUnavailableReason == "no_streaming_interval")
        let noTPSComparisons = FastRadarAnalysis.evaluate(run: noTPS)
        #expect(noTPSComparisons.count == 1)
        #expect(noTPSComparisons.first?.tpsRatio == nil)
        #expect(noTPSComparisons.first?.ttftRatio != nil)
        #expect(noTPSComparisons.first?.e2eRatio != nil)

        // Mixed array: legacy trio rows still evaluate under their dict keys.
        let legacy = try #require(dataset.runs.first { $0.model == nil })
        let legacyComparisons = FastRadarAnalysis.evaluate(run: legacy)
        #expect(legacyComparisons.map(\.model) == ["luna", "sol", "terra"])
        #expect(legacyComparisons.allSatisfy { $0.effort == nil })
    }

    @Test("trimmed and empty payloads decode tolerantly")
    func tolerantDecoding() throws {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let minimal = try FastRadarHistoryParser.parse(Data("{}".utf8), sourceID: .codexRadar, fetchedAt: fetchedAt)
        #expect(minimal.runs.isEmpty)
        #expect(minimal.type == nil)

        #expect(throws: FastRadarHistoryParseError.malformedJSON.self) {
            try FastRadarHistoryParser.parse(Data("{oops".utf8), sourceID: .codexRadar, fetchedAt: fetchedAt)
        }
        #expect(throws: FastRadarHistoryParseError.unexpectedType("wrong").self) {
            try FastRadarHistoryParser.parse(Data(#"{"type":"wrong"}"#.utf8), sourceID: .codexRadar, fetchedAt: fetchedAt)
        }
    }

    @Test("derived ratios are fast/standard and month buckets zero-fill ascending")
    func derivedMetrics() throws {
        let run = FastRadarHistoryDataset.FastRadarRun(
            runID: "r",
            measuredAt: "2026-09-04T13:14:54+08:00",
            models: ["sol": tier(standardTTFT: 8.0, fastTTFT: 4.0, standardTPS: 50, fastTPS: 100, standardE2E: 40, fastE2E: 10)]
        )
        let comparisons = FastRadarAnalysis.evaluate(run: run)
        #expect(comparisons.count == 1)
        #expect(comparisons.first?.model == "sol")
        #expect(comparisons.first?.ttftRatio == 0.5)
        #expect(comparisons.first?.tpsRatio == 2.0)
        #expect(comparisons.first?.e2eRatio == 0.25)

        // Missing pairs never substitute 0 or 1.
        let partial = FastRadarHistoryDataset.FastRadarRun(
            runID: "p",
            models: ["terra": .init(standard: .init(ttftSeconds: 8, tps: 50, e2eSeconds: 40), fast: nil)]
        )
        #expect(FastRadarAnalysis.evaluate(run: partial).isEmpty)

        let runs = [
            FastRadarHistoryDataset.FastRadarRun(runID: "a", measuredAt: "2026-07-02T08:00:00+08:00"),
            FastRadarHistoryDataset.FastRadarRun(runID: "b", measuredAt: "2026-07-20T08:00:00+08:00"),
            FastRadarHistoryDataset.FastRadarRun(runID: "c", measuredAt: "2026-09-04T13:00:00+08:00"),
        ]
        let buckets = FastRadarAnalysis.monthlyRunCounts(runs: runs)
        #expect(buckets.map(\.monthLabel) == ["2026-07", "2026-08", "2026-09"])
        #expect(buckets.map(\.count) == [2, 0, 1])
    }

    @Test("adapter pins every request to the codexradar.com /data whitelist")
    func adapterHostWhitelist() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let transport = StubFRHTransport(
            body: Data(#"{"schema_version":1,"type":"fast_radar_history","runs":[{"run_id":"r1","measured_at":"2026-09-04T13:14:54+08:00"}]}"#.utf8),
            status: 200
        )
        let adapter = FastRadarHistoryAdapter(
            transport: transport,
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        _ = try await adapter.read()

        let requests = transport.requests
        let request = try #require(requests.first)
        #expect(request.url?.host == "codexradar.com")
        #expect(request.url?.path == "/data/fast-radar-history.json")
        #expect(request.url?.absoluteString.contains("api.codexradar.com") == false)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "AIRadar/0.5.0 (macOS; +https://github.com/Acfufu/Radar)")

        let samples = try await RawSampleStore(dataRoot: storeRoot).samples(sourceID: .codexRadar)
        #expect(samples.count == 1)
        #expect(samples.first?.outcome == .success)
    }

    @Test("adapter enforces status, MIME, and the 8MiB caps")
    func adapterRejections() async throws {
        let (_, storeRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let oversized = FastRadarHistoryAdapter(
            transport: StubFRHTransport(body: Data("x".utf8), status: 200, truncated: true),
            rawSampleStore: RawSampleStore(dataRoot: storeRoot)
        )
        do {
            _ = try await oversized.read()
            Issue.record("expected oversized failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .oversized)
        }

        let badStatus = FastRadarHistoryAdapter(
            transport: StubFRHTransport(body: Data(), status: 500),
            rawSampleStore: nil
        )
        do {
            _ = try await badStatus.read()
            Issue.record("expected status failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .status(500))
        }

        let badMIME = FastRadarHistoryAdapter(
            transport: StubFRHTransport(body: Data("<html/>".utf8), status: 200, headers: ["Content-Type": "text/html"]),
            rawSampleStore: nil
        )
        do {
            _ = try await badMIME.read()
            Issue.record("expected MIME failure")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .mime)
        }

        #expect(FastRadarHistoryAdapter.maximumResponseBytes == 8 * 1_024 * 1_024)
    }

    @Test("repository replaces the whole run set per sync and never accumulates")
    func repositoryReplaceWithoutAccumulation() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        let insertion = try await repository.insertFastRadarHistory(first)
        #expect(insertion.inserted)
        #expect(try await repository.snapshotCount(datasetType: .fastRadarHistory, sourceID: .codexRadar) == 1)

        // Identical payload (new fetch time only) → same fingerprint → no-op.
        let duplicate = try await repository.insertFastRadarHistory(dataset(fetchedAt: Date(timeIntervalSince1970: 150)))
        #expect(!duplicate.inserted)
        #expect(try await repository.snapshotCount(datasetType: .fastRadarHistory, sourceID: .codexRadar) == 1)

        // New fingerprint → whole-set replacement, not accumulation.
        let second = dataset(fetchedAt: Date(timeIntervalSince1970: 200), solTTFT: 8.3, extraRun: true)
        _ = try await repository.insertFastRadarHistory(second)
        #expect(try await repository.snapshotCount(datasetType: .fastRadarHistory, sourceID: .codexRadar) == 2)

        let state = try await repository.fastRadarHistoryState(sourceID: .codexRadar)
        #expect(state.value == second)
        #expect(state.error == nil)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .fastRadarHistory)
        #expect(metadata.lastSuccessfulAt != nil)

        let runs = try await repository.fastRadarRuns(sourceID: .codexRadar)
        #expect(runs.compactMap(\.runID) == ["20260820-0900", "20260904-1314"])

        try await repository.deleteNormalizedHistory(sourceID: .codexRadar)
        #expect(try await repository.snapshotCount(datasetType: .fastRadarHistory, sourceID: .codexRadar) == 0)
        let cleared = try await repository.fastRadarHistoryState(sourceID: .codexRadar)
        #expect(cleared.value == nil)
        #expect(try await repository.metadata(sourceID: .codexRadar, datasetType: .fastRadarHistory) == .empty)
    }

    @Test("per-model run fields survive the encodedRun persistence round-trip")
    func repositoryRoundTripsPerModelFields() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let perModelRun = FastRadarHistoryDataset.FastRadarRun(
            runID: "20260908-234119-0072",
            measuredAt: "2026-09-08T23:41:19+08:00",
            completedAt: "2026-09-08T23:43:44+08:00",
            cliVersion: "0.153.4",
            model: "gpt-6-astra",
            effort: "medium",
            profile: "gpt-6-astra/medium",
            validPairs: 3,
            sampleCount: 6,
            tpsAvailable: false,
            tpsUnavailableReason: "no_streaming_interval",
            models: ["astra": .init(
                standard: .init(ttftSeconds: 70.56299368033332, tps: nil, e2eSeconds: 70.806406611),
                fast: .init(ttftSeconds: 41.716760986333334, tps: nil, e2eSeconds: 41.960522931)
            )]
        )
        let dataset = FastRadarHistoryDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100),
            schemaVersion: 1,
            type: FastRadarHistoryParser.expectedType,
            timezone: "Asia/Shanghai",
            updatedAt: "2026-09-08T23:43:44+08:00",
            runs: [perModelRun]
        )
        _ = try await repository.insertFastRadarHistory(dataset)

        let runs = try await repository.fastRadarRuns(sourceID: .codexRadar)
        let roundTripped = try #require(runs.first)
        #expect(roundTripped == perModelRun)
        #expect(roundTripped.models?["astra"]?.standard?.tps == nil)
    }

    @Test("oversized refresh keeps the last known good run set")
    func oversizeRetainsLKG() async throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let cached = dataset(fetchedAt: Date(timeIntervalSince1970: 100))
        _ = try await repository.insertFastRadarHistory(cached)

        let coordinator = FastRadarHistoryCoordinator(
            reader: StubFRHReader(result: .failure(RadarHTTPError(kind: .oversized))),
            repository: repository
        )
        await coordinator.refresh(trigger: .manual)

        let projection = try await coordinator.projection()
        #expect(projection.state.value == cached)
        #expect(projection.state.error?.kind == .validation)
        let metadata = try await repository.metadata(sourceID: .codexRadar, datasetType: .fastRadarHistory)
        #expect(metadata.consecutiveFailures == 1)
    }
}

private struct StubFRHReader: FastRadarHistoryReading {
    let result: Result<FastRadarHistoryDataset, Error>

    func read() async throws -> FastRadarHistoryDataset {
        try result.get()
    }

    func cancel() async {}
}

private final class StubFRHTransport: HTTPTransport, @unchecked Sendable {
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
