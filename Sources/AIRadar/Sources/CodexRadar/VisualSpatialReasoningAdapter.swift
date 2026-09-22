import Foundation

/// Sidecar reader for the upstream visual-spatial-reasoning dataset
/// (spec §5.7). Two URLs share one sidecar: the summary plus its history
/// companion, fetched back to back through the same dedicated transport.
protocol VisualSpatialReasoningReading: Sendable {
    func read() async throws -> VisualSpatialReasoningDataset
    func cancel() async
}

actor VisualSpatialReasoningAdapter: VisualSpatialReasoningReading {
    /// Fixed endpoints (spec §5.0 whitelist: codexradar.com same-origin
    /// `/api/*` public GET, ADR-0001). Tests pin the host and path of every
    /// outgoing request so no URL is ever built from response data fields.
    static let endpoint = URL(string: "https://codexradar.com/api/visual-spatial-reasoning")!
    static let historyEndpoint = URL(string: "https://codexradar.com/api/visual-spatial-reasoning-history")!

    /// Spec §5.0/§10: the sidecar uses a dedicated transport instance and
    /// both the transport cap and the source-level cap are 8MiB (the summary
    /// measured ~777KiB on 2026-09-08; §5.0 sets 8MiB for every sidecar).
    static let maximumResponseBytes = 8 * 1_024 * 1_024

    nonisolated let sourceID: RadarSourceID
    private let transport: any HTTPTransport
    private let rawSampleStore: RawSampleStore?

    init(
        transport: any HTTPTransport = URLSessionHTTPTransport(maxBodyBytes: VisualSpatialReasoningAdapter.maximumResponseBytes),
        rawSampleStore: RawSampleStore?
    ) {
        sourceID = .codexRadar
        self.transport = transport
        self.rawSampleStore = rawSampleStore
    }

    /// Production wiring used by the app: dedicated 8MiB transport plus the
    /// shared raw-sample store (existing per-source prune applies, spec §5.0).
    static func production(dataRoot: URL) -> VisualSpatialReasoningAdapter {
        VisualSpatialReasoningAdapter(
            transport: URLSessionHTTPTransport(maxBodyBytes: maximumResponseBytes),
            rawSampleStore: RawSampleStore(dataRoot: dataRoot)
        )
    }

    func read() async throws -> VisualSpatialReasoningDataset {
        let summary = try await fetch(Self.endpoint)
        // The history companion is supplementary: a failed fetch decodes as
        // an empty series and the next successful sync repairs it — but a
        // cancellation still aborts the whole read.
        let history: Fetched?
        do {
            history = try await fetch(Self.historyEndpoint)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            history = nil
        }
        let fetchedAt = Date()
        do {
            let dataset = try VisualSpatialReasoningParser.parse(
                summary.data,
                historyData: history?.data,
                sourceID: sourceID,
                fetchedAt: fetchedAt
            )
            await saveRaw(summary.data, outcome: .success, at: fetchedAt)
            if let history { await saveRaw(history.data, outcome: .success, at: fetchedAt) }
            return dataset
        } catch let error as VisualSpatialReasoningParseError {
            switch error {
            case .malformedJSON:
                await saveRaw(summary.data, outcome: .decodingFailed, at: fetchedAt)
            case .unexpectedType:
                await saveRaw(summary.data, outcome: .validationFailed, at: fetchedAt)
            }
            throw error
        }
    }

    private struct Fetched {
        let data: Data
        let response: HTTPURLResponse
        let bodyWasTruncated: Bool
    }

    private func fetch(_ url: URL) async throws -> Fetched {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIRadar/0.5.0 (macOS; +https://github.com/Acfufu/Radar)", forHTTPHeaderField: "User-Agent")

        let payload: HTTPTransportResponse
        do {
            payload = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RadarHTTPError(kind: .network)
        }

        // Truncation means the cap was hit: never parse a partial payload.
        guard !payload.bodyWasTruncated else {
            await saveRaw(payload.data, outcome: .httpFailed, at: Date())
            throw RadarHTTPError(kind: .oversized)
        }
        let status = payload.response.statusCode
        guard (200...299).contains(status) else {
            await saveRaw(payload.data, outcome: .httpFailed, at: Date())
            throw RadarHTTPError(kind: .status(status))
        }
        guard let mime = payload.response.mimeType, mime.lowercased().contains("json") else {
            await saveRaw(payload.data, outcome: .httpFailed, at: Date())
            throw RadarHTTPError(kind: .mime)
        }
        return Fetched(data: payload.data, response: payload.response, bodyWasTruncated: payload.bodyWasTruncated)
    }

    func cancel() async {
        await transport.cancelAll()
    }

    private func saveRaw(_ data: Data, outcome: RawSampleOutcome, at date: Date) async {
        guard let rawSampleStore else { return }
        _ = try? await rawSampleStore.save(data, sourceID: sourceID, outcome: outcome, at: date)
    }
}
