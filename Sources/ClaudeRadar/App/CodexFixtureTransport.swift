#if DEBUG
import Foundation

actor CodexFixtureTransport: HTTPTransport {
    static let summaryURL = URL(string: "https://codex-fixture.invalid/current.json")!
    static let communityURL = URL(string: "https://codex-fixture.invalid/api/model-ratings")!

    private let summary: Data
    private let community: Data

    init() throws {
        summary = try Self.fixture("codex-radar-public-summary")
        community = try Self.fixture("codex-radar-community-valid")
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let data: Data
        if url == Self.summaryURL {
            data = summary
        } else if url == Self.communityURL {
            data = community
        } else {
            throw URLError(.unsupportedURL)
        }
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

    private static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
#endif
