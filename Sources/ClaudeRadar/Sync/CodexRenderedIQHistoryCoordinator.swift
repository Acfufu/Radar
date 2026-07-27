import Foundation

struct CodexRenderedIQHistoryProjection: Sendable {
    let state: SegmentState<CodexRenderedIQHistorySnapshot>
    let history: [CodexRenderedIQHistorySnapshot]
}

struct CodexRenderedIQHistoryLifecycleState: Sendable {
    let isStopped: Bool
    let hasActiveTask: Bool
}

actor CodexRenderedIQHistoryCoordinator {
    private let reader: any CodexRenderedIQHistoryReading
    let repository: RadarRepository
    private var policy: SyncPolicy
    private let clock: any RadarClock
    private let projectionDidChange: (@Sendable (
        SegmentState<CodexRenderedIQHistorySnapshot>,
        [CodexRenderedIQHistorySnapshot]
    ) async -> Void)?
    private let persistenceCheckpoint: (@Sendable () async -> Void)?

    private var activeTask: Task<Void, Never>?
    private var activeTrigger: SyncTrigger?
    private var isStopped = false
    private var lifecycleGeneration = 0
    private var failureCount = 0
    private var backoffDeadline: Date?
    private var stopOperation: Task<Void, Never>?

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
        self.reader = reader
        self.repository = repository
        self.policy = policy
        self.clock = clock
        self.projectionDidChange = projectionDidChange
        self.persistenceCheckpoint = persistenceCheckpoint
    }

    func refresh(trigger: SyncTrigger) async {
        guard !isStopped else { return }
        if let activeTask {
            activeTrigger = strongest(activeTrigger ?? trigger, trigger)
            await activeTask.value
            return
        }

        let generation = lifecycleGeneration
        activeTrigger = trigger
        let task = Task {
            await Task.yield()
            let selectedTrigger = self.activeTrigger ?? trigger
            guard await self.isEligible(trigger: selectedTrigger) else { return }
            await self.performRefresh(generation: generation)
        }
        activeTask = task
        await task.value
        if !isStopped, generation == lifecycleGeneration {
            activeTask = nil
            activeTrigger = nil
        }
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        policy = SyncPolicy(
            refreshInterval: interval,
            recoveryMinimumInterval: policy.recoveryMinimumInterval,
            maximumBackoff: policy.maximumBackoff
        )
    }

    func loadPersistedProjection() async throws -> CodexRenderedIQHistoryProjection {
        guard !isStopped else { throw CancellationError() }
        let generation = lifecycleGeneration
        let projection = try await projection()
        guard canContinue(generation) else { throw CancellationError() }
        if let projectionDidChange {
            await projectionDidChange(projection.state, projection.history)
        }
        return projection
    }

    func projection() async throws -> CodexRenderedIQHistoryProjection {
        let current = try await repository.renderedIQHistoryState(sourceID: .codexRadar)
        let history = try await repository.renderedIQHistoryHistory(sourceID: .codexRadar)
        return CodexRenderedIQHistoryProjection(
            state: stale(current, now: clock.now()),
            history: history
        )
    }

    func stop() async {
        if let stopOperation {
            await stopOperation.value
            return
        }
        guard !isStopped else { return }
        isStopped = true
        lifecycleGeneration += 1
        let task = activeTask
        activeTask = nil
        activeTrigger = nil
        task?.cancel()
        let reader = self.reader
        let operation = Task {
            await MainActor.run { reader.cancel() }
            await task?.value
        }
        stopOperation = operation
        await operation.value
    }

    func lifecycleState() -> CodexRenderedIQHistoryLifecycleState {
        CodexRenderedIQHistoryLifecycleState(
            isStopped: isStopped,
            hasActiveTask: activeTask != nil
        )
    }

    private func performRefresh(generation: Int) async {
        let attemptedAt = clock.now()
        let result: Result<CodexRenderedIQHistorySnapshot, Error>
        do {
            result = .success(try await reader.read())
        } catch {
            result = .failure(error)
        }

        guard canContinue(generation) else { return }
        await persistenceCheckpoint?()
        guard canContinue(generation) else { return }

        switch result {
        case let .success(snapshot):
            do {
                _ = try await repository.insertRenderedIQHistory(snapshot)
                guard canContinue(generation) else { return }
                failureCount = 0
                backoffDeadline = nil
            } catch {
                guard canContinue(generation) else { return }
                await persistFailure(error, attemptedAt: attemptedAt, generation: generation)
            }
        case let .failure(error):
            await persistFailure(error, attemptedAt: attemptedAt, generation: generation)
        }

        guard canContinue(generation),
              let current = try? await projection() else { return }
        guard canContinue(generation) else { return }
        if let projectionDidChange {
            await projectionDidChange(current.state, current.history)
        }
    }

    private func persistFailure(
        _ error: Error,
        attemptedAt: Date,
        generation: Int
    ) async {
        guard canContinue(generation) else { return }
        if error is CancellationError { return }
        if let error = error as? CodexRenderedIQHistoryPageReaderError,
           error == .cancelled {
            return
        }
        let segmentError = segmentError(for: error)
        try? await repository.recordFailure(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory,
            attemptedAt: attemptedAt,
            error: segmentError
        )
        guard canContinue(generation) else { return }
        let metadata = try? await repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        )
        guard canContinue(generation) else { return }
        let count = max(metadata?.consecutiveFailures ?? 1, 1)
        let deadline = attemptedAt.addingTimeInterval(policy.backoff(failureCount: count))
        try? await repository.recordBackoff(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory,
            until: deadline,
            failureCount: count
        )
        guard canContinue(generation) else { return }
        failureCount = count
        backoffDeadline = deadline
    }

    private func isEligible(trigger: SyncTrigger) async -> Bool {
        let now = clock.now()
        guard let metadata = try? await repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        ) else {
            return true
        }
        if let retryAfter = metadata.retryAfter, now < retryAfter { return false }
        if trigger != .manual,
           let deadline = metadata.backoffUntil,
           now < deadline {
            return false
        }
        if trigger == .networkRecovery || trigger == .sleepRecovery {
            if let attempted = metadata.lastAttemptedAt,
               now.timeIntervalSince(attempted) < policy.recoveryMinimumInterval {
                return false
            }
            if let state = try? await projection(),
               !state.state.isStale,
               state.state.error == nil {
                return false
            }
        }
        return true
    }

    private func canContinue(_ generation: Int) -> Bool {
        !Task.isCancelled && !isStopped && generation == lifecycleGeneration
    }

    private func stale(
        _ state: SegmentState<CodexRenderedIQHistorySnapshot>,
        now: Date
    ) -> SegmentState<CodexRenderedIQHistorySnapshot> {
        let isStale = state.lastSuccessfulAt
            .map { now.timeIntervalSince($0) >= policy.staleInterval } ?? true
        return SegmentState(
            value: state.value,
            lastSuccessfulAt: state.lastSuccessfulAt,
            lastAttemptedAt: state.lastAttemptedAt,
            error: state.error,
            isStale: isStale
        )
    }

    private func strongest(_ lhs: SyncTrigger, _ rhs: SyncTrigger) -> SyncTrigger {
        lhs.priority >= rhs.priority ? lhs : rhs
    }

    private func segmentError(for error: Error) -> SegmentError {
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
