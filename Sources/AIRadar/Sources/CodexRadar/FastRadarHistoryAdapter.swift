import Foundation

/// Sidecar reader for the upstream fast-radar history dataset (spec §5.3),
/// mirroring the intelligence-efficiency adapter (spec §5.0 sidecar rules).
protocol FastRadarHistoryReading: Sendable {
    func read() async throws -> FastRadarHistoryDataset
    func cancel() async
}

actor FastRadarHistoryAdapter: FastRadarHistoryReading {
    /// Fixed endpoint (spec §5.0 whitelist: codexradar.com `/data/*` only).
    static let endpoint = URL(string: "https://codexradar.com/data/fast-radar-history.json")!

    /// Spec §5.0/§10: dedicated transport instance, both caps 8MiB.
    static let maximumResponseBytes = 8 * 1_024 * 1_024

    nonisolated let sourceID: RadarSourceID
    private let transport: any HTTPTransport
    private let rawSampleStore: RawSampleStore?

    init(
        transport: any HTTPTransport = URLSessionHTTPTransport(maxBodyBytes: FastRadarHistoryAdapter.maximumResponseBytes),
        rawSampleStore: RawSampleStore?
    ) {
        sourceID = .codexRadar
        self.transport = transport
        self.rawSampleStore = rawSampleStore
    }

    static func production(dataRoot: URL) -> FastRadarHistoryAdapter {
        FastRadarHistoryAdapter(
            transport: URLSessionHTTPTransport(maxBodyBytes: maximumResponseBytes),
            rawSampleStore: RawSampleStore(dataRoot: dataRoot)
        )
    }

    func read() async throws -> FastRadarHistoryDataset {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIRadar/0.3.0 (macOS; +https://github.com/Acfufu/Radar)", forHTTPHeaderField: "User-Agent")

        let payload: HTTPTransportResponse
        do {
            payload = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RadarHTTPError(kind: .network)
        }

        let fetchedAt = Date()
        guard !payload.bodyWasTruncated else {
            await saveRaw(payload.data, outcome: .httpFailed, at: fetchedAt)
            throw RadarHTTPError(kind: .oversized)
        }
        let status = payload.response.statusCode
        guard (200...299).contains(status) else {
            await saveRaw(payload.data, outcome: .httpFailed, at: fetchedAt)
            throw RadarHTTPError(kind: .status(status))
        }
        guard let mime = payload.response.mimeType, mime.lowercased().contains("json") else {
            await saveRaw(payload.data, outcome: .httpFailed, at: fetchedAt)
            throw RadarHTTPError(kind: .mime)
        }

        do {
            let dataset = try FastRadarHistoryParser.parse(
                payload.data,
                sourceID: sourceID,
                fetchedAt: fetchedAt
            )
            await saveRaw(payload.data, outcome: .success, at: fetchedAt)
            return dataset
        } catch let error as FastRadarHistoryParseError {
            switch error {
            case .malformedJSON:
                await saveRaw(payload.data, outcome: .decodingFailed, at: fetchedAt)
            case .unexpectedType:
                await saveRaw(payload.data, outcome: .validationFailed, at: fetchedAt)
            }
            throw error
        }
    }

    func cancel() async {
        await transport.cancelAll()
    }

    private func saveRaw(_ data: Data, outcome: RawSampleOutcome, at date: Date) async {
        guard let rawSampleStore else { return }
        _ = try? await rawSampleStore.save(data, sourceID: sourceID, outcome: outcome, at: date)
    }
}
