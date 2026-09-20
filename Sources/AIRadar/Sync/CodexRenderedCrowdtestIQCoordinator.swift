import Foundation

struct CodexRenderedCrowdtestIQProjection: Sendable {
    let state: SegmentState<CodexRenderedCrowdtestIQSnapshot>
    let history: [CodexRenderedCrowdtestIQSnapshot]
}

struct CodexRenderedCrowdtestIQLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

/// Sidecar coordinator for the deng crowdtest-IQ rendered reader
/// (spec §6 v1.2, ADR-0004): independent of the benchmark main chain,
/// driven by the shared trigger observer, gated by
/// `AppEnvironment.synchronizationEnabled`.
actor CodexRenderedCrowdtestIQCoordinator {
    let repository: RadarRepository
    private let core: CodexRenderedSyncCore<CodexRenderedCrowdtestIQSnapshot>

    init(
        reader: any CodexRenderedCrowdtestIQReading,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        projectionDidChange: (@Sendable (
            SegmentState<CodexRenderedCrowdtestIQSnapshot>,
            [CodexRenderedCrowdtestIQSnapshot]
        ) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil
    ) {
        self.repository = repository
        let adapter = CodexRenderedSyncAdapter<CodexRenderedCrowdtestIQSnapshot>(
            sourceID: .codexRadar,
            datasetType: .crowdtestIQ,
            read: { try await reader.read() },
            cancel: { reader.cancel() },
            insert: { snapshot in
                try await repository.insertCrowdtestIQ(snapshot)
            },
            loadState: {
                try await repository.crowdtestIQState(sourceID: .codexRadar)
            },
            loadHistory: {
                try await repository.crowdtestIQHistory(sourceID: .codexRadar)
            },
            isCancellation: { error in
                error is CancellationError
                    || (error as? CodexRenderedCrowdtestIQPageReaderError) == .cancelled
            },
            segmentError: { error in
                let kind: SegmentError.Kind
                switch error {
                case CodexRenderedCrowdtestIQPageReaderError.navigationFailed,
                     CodexRenderedCrowdtestIQPageReaderError.navigationTimeout,
                     CodexRenderedCrowdtestIQPageReaderError.totalTimeout:
                    kind = .network
                default:
                    kind = .validation
                }
                return SegmentError(
                    kind: kind,
                    message: "The deng crowdtest IQ page could not be read"
                )
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

    func loadPersistedProjection() async throws -> CodexRenderedCrowdtestIQProjection {
        let projection = try await core.loadPersistedProjection()
        return CodexRenderedCrowdtestIQProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func projection() async throws -> CodexRenderedCrowdtestIQProjection {
        let projection = try await core.projection()
        return CodexRenderedCrowdtestIQProjection(
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

    func lifecycleState() async -> CodexRenderedCrowdtestIQLifecycleState {
        let state = await core.lifecycleState()
        return CodexRenderedCrowdtestIQLifecycleState(
            isStopped: state.isStopped,
            isPaused: state.isPaused,
            hasActiveTask: state.hasActiveTask
        )
    }
}
