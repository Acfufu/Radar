import Foundation

struct VisualSpatialReasoningProjection: Sendable {
    let state: SegmentState<VisualSpatialReasoningDataset>
    let history: [VisualSpatialReasoningDataset]
}

struct VisualSpatialReasoningLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

/// Sidecar coordinator for the upstream visual-spatial-reasoning dataset
/// (spec §5.0/§5.7): independent of the benchmark main chain, driven by the
/// shared trigger observer, gated by `AppEnvironment.synchronizationEnabled`.
actor VisualSpatialReasoningCoordinator {
    let repository: RadarRepository
    private let core: CodexRenderedSyncCore<VisualSpatialReasoningDataset>

    init(
        reader: any VisualSpatialReasoningReading,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        projectionDidChange: (@Sendable (
            SegmentState<VisualSpatialReasoningDataset>,
            [VisualSpatialReasoningDataset]
        ) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil
    ) {
        self.repository = repository
        let adapter = CodexRenderedSyncAdapter<VisualSpatialReasoningDataset>(
            sourceID: .codexRadar,
            datasetType: .visualSpatialReasoning,
            read: { try await reader.read() },
            cancel: { await reader.cancel() },
            insert: { snapshot in
                try await repository.insertVisualSpatialReasoning(snapshot)
            },
            loadState: {
                try await repository.visualSpatialReasoningState(sourceID: .codexRadar)
            },
            loadHistory: {
                try await repository.visualSpatialReasoningHistory(sourceID: .codexRadar)
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

    func loadPersistedProjection() async throws -> VisualSpatialReasoningProjection {
        let projection = try await core.loadPersistedProjection()
        return VisualSpatialReasoningProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func projection() async throws -> VisualSpatialReasoningProjection {
        let projection = try await core.projection()
        return VisualSpatialReasoningProjection(
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

    func lifecycleState() async -> VisualSpatialReasoningLifecycleState {
        let state = await core.lifecycleState()
        return VisualSpatialReasoningLifecycleState(
            isStopped: state.isStopped,
            isPaused: state.isPaused,
            hasActiveTask: state.hasActiveTask
        )
    }

    private static func segmentError(for error: Error) -> SegmentError {
        switch error {
        case VisualSpatialReasoningParseError.malformedJSON:
            return SegmentError(kind: .decoding, message: "The visual-spatial-reasoning payload could not be decoded")
        case VisualSpatialReasoningParseError.unexpectedType:
            return SegmentError(kind: .validation, message: "The visual-spatial-reasoning payload changed shape")
        case let httpError as RadarHTTPError:
            switch httpError.kind {
            case .notModified, .retryableStatus, .status, .network:
                return SegmentError(kind: .network, message: "The visual-spatial-reasoning endpoint could not be reached")
            case .mime, .oversized:
                return SegmentError(kind: .validation, message: "The visual-spatial-reasoning response was rejected")
            }
        default:
            return SegmentError(kind: .validation, message: "The visual-spatial-reasoning data could not be read")
        }
    }
}
