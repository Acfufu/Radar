import Foundation

struct IntelligenceEfficiencyProjection: Sendable {
    let state: SegmentState<IntelligenceEfficiencyDataset>
    let history: [IntelligenceEfficiencyDataset]
}

struct IntelligenceEfficiencyLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

/// Sidecar coordinator for the upstream intelligence-efficiency dataset
/// (spec §5.0/§5.2): independent of the benchmark main chain, driven by the
/// shared trigger observer, gated by `AppEnvironment.synchronizationEnabled`.
actor IntelligenceEfficiencyCoordinator {
    let repository: RadarRepository
    private let core: CodexRenderedSyncCore<IntelligenceEfficiencyDataset>

    init(
        reader: any IntelligenceEfficiencyReading,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        projectionDidChange: (@Sendable (
            SegmentState<IntelligenceEfficiencyDataset>,
            [IntelligenceEfficiencyDataset]
        ) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil
    ) {
        self.repository = repository
        let adapter = CodexRenderedSyncAdapter<IntelligenceEfficiencyDataset>(
            sourceID: .codexRadar,
            datasetType: .intelligenceEfficiency,
            read: { try await reader.read() },
            cancel: { await reader.cancel() },
            insert: { snapshot in
                try await repository.insertIntelligenceEfficiency(snapshot)
            },
            loadState: {
                try await repository.intelligenceEfficiencyState(sourceID: .codexRadar)
            },
            loadHistory: {
                try await repository.intelligenceEfficiencyHistory(sourceID: .codexRadar)
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

    func loadPersistedProjection() async throws -> IntelligenceEfficiencyProjection {
        let projection = try await core.loadPersistedProjection()
        return IntelligenceEfficiencyProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func projection() async throws -> IntelligenceEfficiencyProjection {
        let projection = try await core.projection()
        return IntelligenceEfficiencyProjection(
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

    func lifecycleState() async -> IntelligenceEfficiencyLifecycleState {
        let state = await core.lifecycleState()
        return IntelligenceEfficiencyLifecycleState(
            isStopped: state.isStopped,
            isPaused: state.isPaused,
            hasActiveTask: state.hasActiveTask
        )
    }

    private static func segmentError(for error: Error) -> SegmentError {
        switch error {
        case IntelligenceEfficiencyParseError.malformedJSON:
            return SegmentError(kind: .decoding, message: "The intelligence-efficiency payload could not be decoded")
        case IntelligenceEfficiencyParseError.unexpectedType:
            return SegmentError(kind: .validation, message: "The intelligence-efficiency payload changed shape")
        case let httpError as RadarHTTPError:
            switch httpError.kind {
            case .notModified, .retryableStatus, .status, .network:
                return SegmentError(kind: .network, message: "The intelligence-efficiency endpoint could not be reached")
            case .mime, .oversized:
                return SegmentError(kind: .validation, message: "The intelligence-efficiency response was rejected")
            }
        default:
            return SegmentError(kind: .validation, message: "The intelligence-efficiency data could not be read")
        }
    }
}
