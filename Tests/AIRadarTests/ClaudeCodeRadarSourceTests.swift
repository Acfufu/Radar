import Foundation
import Testing
@testable import AIRadar

@Suite("ClaudeCodeRadarSourceTests", .serialized)
struct ClaudeCodeRadarSourceTests {
    @Test("overlapping benchmark and status calls share one conditional JSON request")
    func sharedEnvelopeRequest() async throws {
        // Given
        let transport = ScriptedHTTPTransport(responses: [
            .json(url: benchmarkURL, body: try fixture("claude-radar-valid"), headers: [
                "ETag": "\"v2\"", "Last-Modified": "Tue, 14 Jul 2026 08:00:00 GMT",
            ]),
        ])
        let source = ClaudeCodeRadarSource(configuration: configuration, transport: transport)
        await source.beginAcquisition(validators: HTTPValidators(etag: "\"v1\"", lastModified: "Mon, 13 Jul 2026 08:00:00 GMT"))

        // When
        async let benchmark = source.fetchBenchmark()
        async let status = source.fetchSourceStatus()
        let values = try await (benchmark, status)

        // Then
        #expect(values.0.models.count == 1)
        #expect(values.1?.quotaEstimates.count == 2)
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(requests[0].value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 13 Jul 2026 08:00:00 GMT")
        #expect(requests[0].value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("community uses an independent request and an HTTP failure does not invalidate benchmark status")
    func independentCommunityFailure() async throws {
        // Given
        let transport = ScriptedHTTPTransport(responses: [
            .json(url: benchmarkURL, body: try fixture("claude-radar-valid")),
            .status(url: communityURL, code: 500),
        ])
        let source = ClaudeCodeRadarSource(configuration: configuration, transport: transport)

        // When
        let envelope = try await source.acquireBenchmarkEnvelope()
        let community = await capture { try await source.fetchCommunity() }

        // Then
        #expect(envelope.benchmark.value != nil)
        #expect(envelope.sourceStatus.value != nil)
        #expect(community.isFailure)
        let requestCount = await transport.requests.count
        #expect(requestCount == 2)
    }

    @Test("HTTP boundary rejects non JSON, oversized bodies, and authorization responses", arguments: [
        HTTPFixture.nonJSON,
        .oversized,
        .authorization,
    ])
    func responseValidation(fixture responseFixture: HTTPFixture) async {
        // Given
        let response = responseFixture.response(url: benchmarkURL)
        let source = ClaudeCodeRadarSource(configuration: configuration, transport: ScriptedHTTPTransport(responses: [response]))

        // When
        let result = await capture { try await source.fetchBenchmark() }

        // Then
        #expect(result.isFailure)
    }

    @Test("304 and Retry After are typed outcomes with response validators")
    func cacheAndRetryOutcomes() async throws {
        // Given
        let transport = ScriptedHTTPTransport(responses: [
            .status(url: benchmarkURL, code: 304, headers: ["ETag": "\"same\""]),
            .status(url: benchmarkURL, code: 429, headers: ["Retry-After": "120"]),
            .status(url: benchmarkURL, code: 429, headers: ["Retry-After": "Wed, 15 Jul 2026 01:02:03 GMT"]),
        ])
        let source = ClaudeCodeRadarSource(configuration: configuration, transport: transport)

        // When / Then
        do {
            _ = try await source.acquireBenchmarkEnvelope()
            Issue.record("expected not modified")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .notModified)
            #expect(error.validators.etag == "\"same\"")
        }
        await source.beginAcquisition(validators: .empty)
        do {
            _ = try await source.acquireBenchmarkEnvelope()
            Issue.record("expected retry")
        } catch let error as RadarHTTPError {
            #expect(error.kind == .retryableStatus)
            #expect(error.retryAfter == .seconds(120))
        }
        await source.beginAcquisition(validators: .empty)
        do {
            _ = try await source.acquireBenchmarkEnvelope()
            Issue.record("expected date retry")
        } catch let error as RadarHTTPError {
            guard case .date(let date) = error.retryAfter else {
                Issue.record("expected HTTP date")
                return
            }
            #expect(ISO8601DateFormatter().string(from: date) == "2026-07-15T01:02:03Z")
        }
    }

    @Test("raw sample store records successful HTTP and typed HTTP decoding and validation failures")
    func rawSampleOutcomes() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = RawSampleStore(dataRoot: root)
        let responses: [HTTPTransportResponse] = [
            .json(url: benchmarkURL, body: try fixture("claude-radar-valid"), headers: ["Authorization": "Bearer must-not-persist"]),
            .init(
                data: Data(#"{"error":"server"}"#.utf8),
                response: .make(url: benchmarkURL, status: 500, headers: ["Content-Type": "application/json", "Set-Cookie": "secret=value"])
            ),
            .json(url: benchmarkURL, body: Data(#"{"ok":true,"labels":[],"iq":{"models":[]},"quota":{"metrics":[],"usage":[]}}"#.utf8)),
            .json(url: benchmarkURL, body: Data("not-json".utf8)),
        ]

        // When
        for response in responses {
            let source = ClaudeCodeRadarSource(
                configuration: ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil),
                transport: ScriptedHTTPTransport(responses: [response]),
                rawSampleStore: store
            )
            _ = try? await source.acquireBenchmarkEnvelope()
        }
        let samples = try await store.samples(sourceID: .claudeCodeRadar)
        let bodies = try samples.map { try Data(contentsOf: $0.fileURL) }

        // Then
        #expect(Set(samples.map(\.outcome)) == [.success, .httpFailed, .validationFailed, .decodingFailed])
        #expect(bodies.allSatisfy { !String(decoding: $0, as: UTF8.self).contains("must-not-persist") })
        #expect(bodies.allSatisfy { !String(decoding: $0, as: UTF8.self).contains("secret=value") })
    }

    @Test("URLSession transport stops at its streaming cap and rejects an HTTP redirect")
    func streamingCapAndRedirectPolicy() async throws {
        // Given
        let server = try LocalPhase3HTTPServer()
        defer { server.stop() }
        let cap = 64 * 1_024
        let transport = URLSessionHTTPTransport(maxBodyBytes: cap)
        let rawRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let rawStore = RawSampleStore(dataRoot: rawRoot)
        var redirectRequest = URLRequest(url: server.url(path: "/redirect"))
        redirectRequest.setValue("\"private-validator\"", forHTTPHeaderField: "If-None-Match")
        redirectRequest.setValue("Bearer private", forHTTPHeaderField: "Authorization")

        // When
        let oversized = try await transport.data(for: URLRequest(url: server.url(path: "/oversize")))
        let redirect = try await transport.data(for: redirectRequest)
        let source = ClaudeCodeRadarSource(
            configuration: ClaudeRadarConfiguration(benchmarkURL: server.url(path: "/oversize"), communityURL: nil, sourceStatusURL: nil),
            transport: transport,
            rawSampleStore: rawStore
        )
        _ = try? await source.acquireBenchmarkEnvelope()
        let bytesWritten = try await server.waitForBytesWritten()
        let samples = try await rawStore.samples(sourceID: .claudeCodeRadar)

        // Then
        #expect(oversized.bodyWasTruncated)
        #expect(oversized.data.count == cap + 1)
        #expect(bytesWritten < 2 * 1_024 * 1_024)
        #expect(redirect.response.statusCode == 302)
        #expect(!server.targetWasReached)
        #expect(samples.count == 1)
        #expect(samples[0].outcome == .httpFailed)
        #expect((try Data(contentsOf: samples[0].fileURL)).count == cap + 1)
        await transport.cancelAll()
    }

    private var benchmarkURL: URL { URL(string: "https://test.invalid/benchmark")! }
    private var communityURL: URL { URL(string: "https://test.invalid/community")! }
    private var configuration: ClaudeRadarConfiguration {
        ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: communityURL, sourceStatusURL: nil)
    }

    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Sources/AIRadar/Resources/Fixtures/\(name).json"))
    }
}

enum HTTPFixture: CaseIterable, Sendable {
    case nonJSON, oversized, authorization

    func response(url: URL) -> HTTPTransportResponse {
        switch self {
        case .nonJSON:
            .init(data: Data("not json".utf8), response: .make(url: url, status: 200, headers: ["Content-Type": "text/html"]))
        case .oversized:
            .init(data: Data(repeating: 0, count: 5 * 1_024 * 1_024 + 1), response: .make(url: url, status: 200, headers: ["Content-Type": "application/json"]))
        case .authorization:
            .status(url: url, code: 403)
        }
    }
}

private actor ScriptedHTTPTransport: HTTPTransport {
    private var responses: [HTTPTransportResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [HTTPTransportResponse]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}

extension HTTPTransportResponse {
    static func json(url: URL, body: Data, headers: [String: String] = [:]) -> Self {
        var values = headers
        values["Content-Type"] = "application/json; charset=utf-8"
        return .init(data: body, response: .make(url: url, status: 200, headers: values))
    }

    static func status(url: URL, code: Int, headers: [String: String] = [:]) -> Self {
        .init(data: Data(), response: .make(url: url, status: code, headers: headers))
    }
}

extension HTTPURLResponse {
    static func make(url: URL, status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

private func capture<Value: Sendable>(
    _ operation: () async throws -> Value
) async -> Result<Value, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}
