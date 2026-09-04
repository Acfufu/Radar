import Foundation

struct FastRadarHistoryProjection: Sendable {
    let state: SegmentState<FastRadarHistoryDataset>
    let history: [FastRadarHistoryDataset]
}

struct FastRadarHistoryLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

/// Sidecar coordinator for the upstream fast-radar history dataset
/// (spec §5.0/§5.3): independent of the benchmark main chain, driven by the
/// shared trigger observer, gated by `AppEnvironment.synchronizationEnabled`.
actor FastRadarHistoryCoordinator {
    let repository: RadarRepository
    private let core: CodexRenderedSyncCore<FastRadarHistoryDataset>

    init(
        reader: any FastRadarHistoryReading,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        projectionDidChange: (@Sendable (
            SegmentState<FastRadarHistoryDataset>,
            [FastRadarHistoryDataset]
        ) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil
    ) {
        self.repository = repository
        let adapter = CodexRenderedSyncAdapter<FastRadarHistoryDataset>(
            sourceID: .codexRadar,
            datasetType: .fastRadarHistory,
            read: { try await reader.read() },
            cancel: { await reader.cancel() },
            insert: { dataset in
                try await repository.insertFastRadarHistory(dataset)
            },
            loadState: {
                try await repository.fastRadarHistoryState(sourceID: .codexRadar)
            },
            loadHistory: {
                let state = try await repository.fastRadarHistoryState(sourceID: .codexRadar)
                return state.value.map { [$0] } ?? []
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

    func loadPersistedProjection() async throws -> FastRadarHistoryProjection {
        let projection = try await core.loadPersistedProjection()
        return FastRadarHistoryProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func projection() async throws -> FastRadarHistoryProjection {
        let projection = try await core.projection()
        return FastRadarHistoryProjection(
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

    func lifecycleState() async -> FastRadarHistoryLifecycleState {
        let state = await core.lifecycleState()
        return FastRadarHistoryLifecycleState(
            isStopped: state.isStopped,
            isPaused: state.isPaused,
            hasActiveTask: state.hasActiveTask
        )
    }

    private static func segmentError(for error: Error) -> SegmentError {
        switch error {
        case FastRadarHistoryParseError.malformedJSON:
            return SegmentError(kind: .decoding, message: "The fast-radar history payload could not be decoded")
        case FastRadarHistoryParseError.unexpectedType:
            return SegmentError(kind: .validation, message: "The fast-radar history payload changed shape")
        case let httpError as RadarHTTPError:
            switch httpError.kind {
            case .notModified, .retryableStatus, .status, .network:
                return SegmentError(kind: .network, message: "The fast-radar history endpoint could not be reached")
            case .mime, .oversized:
                return SegmentError(kind: .validation, message: "The fast-radar history response was rejected")
            }
        default:
            return SegmentError(kind: .validation, message: "The fast-radar history data could not be read")
        }
    }
}
