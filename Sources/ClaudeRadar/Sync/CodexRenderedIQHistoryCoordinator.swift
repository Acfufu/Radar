import Foundation

struct CodexRenderedIQHistoryProjection: Sendable {
    let state: SegmentState<CodexRenderedIQHistorySnapshot>
    let history: [CodexRenderedIQHistorySnapshot]
}

struct CodexRenderedIQHistoryLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

actor CodexRenderedIQHistoryCoordinator {
    let repository: RadarRepository
    private let core: CodexRenderedSyncCore<CodexRenderedIQHistorySnapshot>

    init(
        reader: any CodexRenderedIQHistoryReading,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        projectionDidChange: (@Sendable (
            SegmentState<CodexRenderedIQHistorySnapshot>,
            [CodexRenderedIQHistorySnapshot]
        ) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil
    ) {
        self.repository = repository
        let adapter = CodexRenderedSyncAdapter<CodexRenderedIQHistorySnapshot>(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory,
            read: { try await reader.read() },
            cancel: { reader.cancel() },
            insert: { snapshot in
                try await repository.insertRenderedIQHistory(snapshot)
            },
            loadState: {
                try await repository.renderedIQHistoryState(sourceID: .codexRadar)
            },
            loadHistory: {
                try await repository.renderedIQHistoryHistory(sourceID: .codexRadar)
            },
            isCancellation: { error in
                (error as? CodexRenderedIQHistoryPageReaderError) == .cancelled
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

    func loadPersistedProjection() async throws -> CodexRenderedIQHistoryProjection {
        let projection = try await core.loadPersistedProjection()
        return CodexRenderedIQHistoryProjection(
            state: projection.0,
            history: projection.1
        )
    }

    func projection() async throws -> CodexRenderedIQHistoryProjection {
        let projection = try await core.projection()
        return CodexRenderedIQHistoryProjection(
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

    func lifecycleState() async -> CodexRenderedIQHistoryLifecycleState {
        let state = await core.lifecycleState()
        return CodexRenderedIQHistoryLifecycleState(
            isStopped: state.isStopped,
            isPaused: state.isPaused,
            hasActiveTask: state.hasActiveTask
        )
    }

    private static func segmentError(for error: Error) -> SegmentError {
        let kind: SegmentError.Kind
        switch error {
        case CodexRenderedIQHistoryPageReaderError.navigationFailed,
             CodexRenderedIQHistoryPageReaderError.navigationTimeout,
             CodexRenderedIQHistoryPageReaderError.totalTimeout:
            kind = .network
        default:
            kind = .validation
        }
        return SegmentError(
            kind: kind,
            message: "The rendered Codex IQ history page could not be read"
        )
    }
}
