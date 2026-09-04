import Foundation

/// Sidecar reader for the upstream intelligence-efficiency dataset
/// (spec §5.2). Follows the rendered-reader sidecar pattern: the main
/// benchmark chain never touches this endpoint; the coordinator drives
/// `read()` through `CodexRenderedSyncCore`.
protocol IntelligenceEfficiencyReading: Sendable {
    func read() async throws -> IntelligenceEfficiencyDataset
    func cancel() async
}

actor IntelligenceEfficiencyAdapter: IntelligenceEfficiencyReading {
    /// Single fixed endpoint (spec §5.0 whitelist: codexradar.com `/data/*`
    /// only). The response's own provenance fields point at a protected API
    /// domain; they are never used to build requests — tests pin the host of
    /// every outgoing request to `codexradar.com`.
    static let endpoint = URL(string: "https://codexradar.com/data/intelligence-efficiency.json")!

    /// Spec §5.0/§10: the sidecar uses a dedicated transport instance and
    /// both the transport cap and the source-level cap are 8MiB (the payload
    /// measured ~4.1MiB on 2026-09-04 and keeps growing).
    static let maximumResponseBytes = 8 * 1_024 * 1_024

    nonisolated let sourceID: RadarSourceID
    private let transport: any HTTPTransport
    private let rawSampleStore: RawSampleStore?

    init(
        transport: any HTTPTransport = URLSessionHTTPTransport(maxBodyBytes: IntelligenceEfficiencyAdapter.maximumResponseBytes),
        rawSampleStore: RawSampleStore?
    ) {
        sourceID = .codexRadar
        self.transport = transport
        self.rawSampleStore = rawSampleStore
    }

    /// Production wiring used by the app: dedicated 8MiB transport plus the
    /// shared raw-sample store (existing per-source prune applies, spec §5.0).
    static func production(dataRoot: URL) -> IntelligenceEfficiencyAdapter {
        IntelligenceEfficiencyAdapter(
            transport: URLSessionHTTPTransport(maxBodyBytes: maximumResponseBytes),
            rawSampleStore: RawSampleStore(dataRoot: dataRoot)
        )
    }

    func read() async throws -> IntelligenceEfficiencyDataset {
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
        // Truncation means the cap was hit: never parse a partial payload —
        // the sync core keeps the last known good snapshot instead.
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
            let dataset = try IntelligenceEfficiencyParser.parse(
                payload.data,
                sourceID: sourceID,
                fetchedAt: fetchedAt
            )
            await saveRaw(payload.data, outcome: .success, at: fetchedAt)
            return dataset
        } catch let error as IntelligenceEfficiencyParseError {
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
