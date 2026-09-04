import Foundation

struct CodexRenderedWarningProjection: Sendable {
    let state: SegmentState<CodexRenderedWarningSnapshot>
    let history: [CodexRenderedWarningSnapshot]
}

struct CodexRenderedWarningLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

actor CodexRenderedWarningCoordinator {
    let repository: RadarRepository
    private let core: CodexRenderedSyncCore<CodexRenderedWarningSnapshot>

    init(
        reader: any CodexRenderedWarningReading,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        projectionDidChange: (@Sendable (
            SegmentState<CodexRenderedWarningSnapshot>,
            [CodexRenderedWarningSnapshot]
        ) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil
    ) {
        self.repository = repository
        let adapter = CodexRenderedSyncAdapter<CodexRenderedWarningSnapshot>(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings,
            read: { try await reader.read() },
            cancel: { reader.cancel() },
            insert: { snapshot in
                try await repository.insertRenderedWarning(snapshot)
            },
            loadState: {
                try await repository.renderedWarningState(sourceID: .codexRadar)
            },
            loadHistory: {
                try await repository.renderedWarningHistory(sourceID: .codexRadar)
            },
            isCancellation: { error in
                error is CancellationError
                    || (error as? CodexRenderedWarningPageReaderError) == .cancelled
            },
            segmentError: { error in
                let kind: SegmentError.Kind
                switch error {
                case CodexRenderedWarningPageReaderError.navigationFailed,
                     CodexRenderedWarningPageReaderError.navigationTimeout,
                     CodexRenderedWarningPageReaderError.totalTimeout:
                    kind = .network
                default:
                    kind = .validation
                }
                return SegmentError(
                    kind: kind,
                    message: "The rendered Codex warning page could not be read"
                )
            },
            projectionDidChange: projectionDidChange
        )
        self.core = CodexRenderedSyncCore(
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

    func loadPersistedProjection() async throws -> CodexRenderedWarningProjection {
        let projection = try await core.loadPersistedProjection()
        return CodexRenderedWarningProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func projection() async throws -> CodexRenderedWarningProjection {
        let projection = try await core.projection()
        return CodexRenderedWarningProjection(
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

    func lifecycleState() async -> CodexRenderedWarningLifecycleState {
        let state = await core.lifecycleState()
        return CodexRenderedWarningLifecycleState(
            isStopped: state.isStopped,
            isPaused: state.isPaused,
            hasActiveTask: state.hasActiveTask
        )
    }
}
