import Foundation

struct RadarInsightsProjection: Sendable {
    let state: SegmentState<RadarInsightsDataset>
    let history: [RadarInsightsDataset]
}

struct RadarInsightsLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

/// Sidecar coordinator for the upstream radar-insights dataset
/// (spec §5.0/§5.6): independent of the benchmark main chain, driven by the
/// shared trigger observer, gated by `AppEnvironment.synchronizationEnabled`.
actor RadarInsightsCoordinator {
    let repository: RadarRepository
    private let core: CodexRenderedSyncCore<RadarInsightsDataset>

    init(
        reader: any RadarInsightsReading,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        projectionDidChange: (@Sendable (
            SegmentState<RadarInsightsDataset>,
            [RadarInsightsDataset]
        ) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil
    ) {
        self.repository = repository
        let adapter = CodexRenderedSyncAdapter<RadarInsightsDataset>(
            sourceID: .codexRadar,
            datasetType: .radarInsights,
            read: { try await reader.read() },
            cancel: { await reader.cancel() },
            insert: { snapshot in
                try await repository.insertRadarInsights(snapshot)
            },
            loadState: {
                try await repository.radarInsightsState(sourceID: .codexRadar)
            },
            loadHistory: {
                try await repository.radarInsightsHistory(sourceID: .codexRadar)
            },
            isCancellation: { error in
                error is CancellationError
            },
            segmentError: { error in
                Self.segmentError(for: error)
            },
            projectionDidChange: projectionDidChange
        )
        core = CodexRenderedSyncCore(
            adapter: adapter,
            repository: repository,
            policy: policy,
            clock: clock,
            persistenceCheckpoint: persistenceCheckpoint
        )
    }

    func refresh(trigger: SyncTrigger) async {
        await core.refresh(trigger: trigger)
    }

    func updateRefreshInterval(_ interval: TimeInterval) async {
        await core.updateRefreshInterval(interval)
    }

    func loadPersistedProjection() async throws -> RadarInsightsProjection {
        let projection = try await core.loadPersistedProjection()
        return RadarInsightsProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func projection() async throws -> RadarInsightsProjection {
        let projection = try await core.projection()
        return RadarInsightsProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func stop() async {
        await core.stop()
    }

    func pauseAndDrain() async {
        await core.pauseAndDrain()
    }

    func resume() async {
        await core.resume()
    }

    func lifecycleState() async -> RadarInsightsLifecycleState {
        let state = await core.lifecycleState()
        return RadarInsightsLifecycleState(
            isStopped: state.isStopped,
            isPaused: state.isPaused,
            hasActiveTask: state.hasActiveTask
        )
    }

    private static func segmentError(for error: Error) -> SegmentError {
        switch error {
        case RadarInsightsParseError.malformedJSON:
            return SegmentError(kind: .decoding, message: "The radar-insights payload could not be decoded")
        case RadarInsightsParseError.unexpectedBenchmark:
            return SegmentError(kind: .validation, message: "The radar-insights payload changed shape")
        case let httpError as RadarHTTPError:
            switch httpError.kind {
            case .notModified, .retryableStatus, .status, .network:
                return SegmentError(kind: .network, message: "The radar-insights endpoint could not be reached")
            case .mime, .oversized:
                return SegmentError(kind: .validation, message: "The radar-insights response was rejected")
            }
        default:
            return SegmentError(kind: .validation, message: "The radar-insights data could not be read")
        }
    }
}
