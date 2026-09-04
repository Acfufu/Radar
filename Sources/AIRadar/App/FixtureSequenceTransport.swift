#if DEBUG
import Foundation

actor FixtureSequenceTransport: HTTPTransport {
    static let benchmarkURL = URL(string: "https://fixture.invalid/benchmark")!
    static let communityURL = URL(string: "https://fixture.invalid/community")!

    private let benchmarkBodies: [Data]
    private let communityBody: Data
    private let evidenceURL: URL
    private var counts: [String: Int] = ["benchmark": 0, "community": 0]

    init(dataRoot: URL) throws {
        let valid = try Self.fixture("claude-radar-valid")
        benchmarkBodies = [valid, try Self.invalidBenchmark(valid)]
        communityBody = try Self.fixture("claude-radar-community-valid")
        evidenceURL = dataRoot.appending(path: "request-counts.json")
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        if url == Self.benchmarkURL {
            let index = counts["benchmark", default: 0]
            counts["benchmark"] = index + 1
            try persistCounts()
            guard benchmarkBodies.indices.contains(index) else { throw URLError(.notConnectedToInternet) }
            return Self.response(url: url, data: benchmarkBodies[index])
        }
        if url == Self.communityURL {
            let index = counts["community", default: 0]
            counts["community"] = index + 1
            try persistCounts()
            guard index < 2 else { throw URLError(.notConnectedToInternet) }
            return Self.response(url: url, data: communityBody)
        }
        throw URLError(.unsupportedURL)
    }

    private func persistCounts() throws {
        try FileManager.default.createDirectory(at: evidenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: counts, options: [.prettyPrinted, .sortedKeys])
            .write(to: evidenceURL, options: .atomic)
    }

    private static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    private static func invalidBenchmark(_ data: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var iq = root["iq"] as? [String: Any],
              var models = iq["models"] as? [[String: Any]],
              !models.isEmpty else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        models[0]["score"] = -1
        iq["models"] = models
        root["iq"] = iq
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func response(url: URL, data: Data) -> HTTPTransportResponse {
        HTTPTransportResponse(
            data: data,
            response: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}
#endif
