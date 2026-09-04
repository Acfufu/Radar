import Foundation

struct CodexRenderedSyncAdapter<Snapshot: Sendable>: Sendable {
    let sourceID: RadarSourceID
    let datasetType: RadarDatasetType
    let read: @MainActor @Sendable () async throws -> Snapshot
    let cancel: @MainActor @Sendable () async -> Void
    let insert: @Sendable (Snapshot) async throws -> SnapshotInsertion
    let loadState: @Sendable () async throws -> SegmentState<Snapshot>
    let loadHistory: @Sendable () async throws -> [Snapshot]
    let isCancellation: @Sendable (Error) -> Bool
    let segmentError: @Sendable (Error) -> SegmentError
    let projectionDidChange: (@Sendable (SegmentState<Snapshot>, [Snapshot]) async -> Void)?
}

struct CodexRenderedSyncLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

actor CodexRenderedSyncCore<Snapshot: Sendable> {
    private let adapter: CodexRenderedSyncAdapter<Snapshot>
    private let repository: RadarRepository
    private var policy: SyncPolicy
    private let clock: any RadarClock
    private let persistenceCheckpoint: (@Sendable () async -> Void)?
    private let eligibilityCheckpoint: (@Sendable (SyncTrigger, Bool) async -> Void)?

    private var activeTask: Task<Void, Never>?
    private var activeTrigger: SyncTrigger?
    private var activeRefreshID = 0
    private var lastPerformedRefreshID: Int?
    private var lastManualRefreshID: Int?
    private var isStopped = false
    private var isPaused = false
    private var lifecycleGeneration = 0
    private var failureCount = 0
    private var backoffDeadline: Date?
    private var pauseOperation: Task<Void, Never>?
    private var stopOperation: Task<Void, Never>?

    init(
        adapter: CodexRenderedSyncAdapter<Snapshot>,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil,
        eligibilityCheckpoint: (@Sendable (SyncTrigger, Bool) async -> Void)? = nil
    ) {
        self.adapter = adapter
        self.repository = repository
        self.policy = policy
        self.clock = clock
        self.persistenceCheckpoint = persistenceCheckpoint
        self.eligibilityCheckpoint = eligibilityCheckpoint
    }

    func refresh(trigger: SyncTrigger) async {
        guard lifecycleAllowsRefresh else { return }
        if let activeTask {
            let joinedID = activeRefreshID
            activeTrigger = strongest(activeTrigger ?? trigger, trigger)
            await activeTask.value
            if activeRefreshID == joinedID {
                self.activeTask = nil
                activeTrigger = nil
            }
            if trigger.isManual,
               lifecycleAllowsRefresh,
               lastManualRefreshID != joinedID,
               lastPerformedRefreshID != joinedID {
                await refresh(trigger: trigger)
            }
            return
        }

        let generation = lifecycleGeneration
        activeRefreshID += 1
        let refreshID = activeRefreshID
        activeTrigger = trigger
        let task = Task {
            await Task.yield()
            guard self.canContinue(generation) else { return }
            let selectedTrigger = self.activeTrigger ?? trigger
            let eligible = await self.isEligible(trigger: selectedTrigger)
            await self.eligibilityCheckpoint?(selectedTrigger, eligible)
            guard self.canContinue(generation), eligible else { return }
            self.lastPerformedRefreshID = refreshID
            if selectedTrigger.isManual { self.lastManualRefreshID = refreshID }
            await self.performRefresh(generation: generation)
        }
        activeTask = task
        await task.value
        if canContinue(generation), activeRefreshID == refreshID {
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

    func loadPersistedProjection() async throws -> (SegmentState<Snapshot>, [Snapshot]) {
        guard lifecycleAllowsRefresh else { throw CancellationError() }
        let generation = lifecycleGeneration
        let projection = try await projection()
        guard canContinue(generation) else { throw CancellationError() }
        if let projectionDidChange = adapter.projectionDidChange {
            await projectionDidChange(projection.0, projection.1)
        }
        guard canContinue(generation) else { throw CancellationError() }
        return projection
    }

    func projection() async throws -> (SegmentState<Snapshot>, [Snapshot]) {
        let state = try await adapter.loadState()
        let history = try await adapter.loadHistory()
        return (stale(state, now: clock.now()), history)
    }

    func stop() async {
        if let stopOperation {
            await stopOperation.value
            return
        }
        guard !isStopped else { return }
        let wasPaused = isPaused
        isStopped = true
        isPaused = true
        lifecycleGeneration += 1
        let task = activeTask
        let pauseOperation = self.pauseOperation
        activeTask = nil
        activeTrigger = nil
        task?.cancel()
        let cancel = adapter.cancel
        let operation = Task {
            if let pauseOperation {
                await pauseOperation.value
            } else {
                if !wasPaused { await cancel() }
                await task?.value
            }
        }
        stopOperation = operation
        await operation.value
    }

    func pauseAndDrain() async {
        if let pauseOperation {
            await pauseOperation.value
            return
        }
        guard !isStopped, !isPaused else { return }
        isPaused = true
        lifecycleGeneration += 1
        let task = activeTask
        activeTask = nil
        activeTrigger = nil
        task?.cancel()
        let cancel = adapter.cancel
        let operation = Task {
            await cancel()
            await task?.value
        }
        pauseOperation = operation
        await operation.value
        self.pauseOperation = nil
    }

    func resume() {
        guard !isStopped, pauseOperation == nil else { return }
        isPaused = false
    }

    func lifecycleState() -> CodexRenderedSyncLifecycleState {
        CodexRenderedSyncLifecycleState(
            isStopped: isStopped,
            isPaused: isPaused,
            hasActiveTask: activeTask != nil || pauseOperation != nil
        )
    }

    private var lifecycleAllowsRefresh: Bool {
        !isStopped && !isPaused
    }

    private func canContinue(_ generation: Int) -> Bool {
        !Task.isCancelled
            && !isStopped
            && !isPaused
            && generation == lifecycleGeneration
    }

    private func performRefresh(generation: Int) async {
        let attemptedAt = clock.now()
        let result: Result<Snapshot, Error>
        do {
            result = .success(try await adapter.read())
        } catch {
            result = .failure(error)
        }

        guard canContinue(generation) else { return }
        await persistenceCheckpoint?()
        guard canContinue(generation) else { return }

        switch result {
        case let .success(snapshot):
            do {
                _ = try await adapter.insert(snapshot)
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
        if let projectionDidChange = adapter.projectionDidChange {
            await projectionDidChange(current.0, current.1)
        }
    }

    private func persistFailure(
        _ error: Error,
        attemptedAt: Date,
        generation: Int
    ) async {
        guard canContinue(generation) else { return }
        if error is CancellationError || adapter.isCancellation(error) { return }
        try? await repository.recordFailure(
            sourceID: adapter.sourceID,
            datasetType: adapter.datasetType,
            attemptedAt: attemptedAt,
            error: adapter.segmentError(error)
        )
        guard canContinue(generation) else { return }
        let metadata = try? await repository.metadata(
            sourceID: adapter.sourceID,
            datasetType: adapter.datasetType
        )
        guard canContinue(generation) else { return }
        let count = max(metadata?.consecutiveFailures ?? 1, 1)
        let deadline = attemptedAt.addingTimeInterval(policy.backoff(failureCount: count))
        try? await repository.recordBackoff(
            sourceID: adapter.sourceID,
            datasetType: adapter.datasetType,
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
            sourceID: adapter.sourceID,
            datasetType: adapter.datasetType
        ) else {
            return true
        }
        if let retryAfter = metadata.retryAfter, now < retryAfter { return false }
        if !trigger.isManual,
           let deadline = metadata.backoffUntil,
           now < deadline {
            return false
        }
        if trigger == .networkRecovery || trigger == .sleepRecovery {
            if let attempted = metadata.lastAttemptedAt,
               now.timeIntervalSince(attempted) < policy.recoveryMinimumInterval {
                return false
            }
            if let projection = try? await projection(),
               !projection.0.isStale,
               projection.0.error == nil {
                return false
            }
        }
        return true
    }

    private func stale(
        _ state: SegmentState<Snapshot>,
        now: Date
    ) -> SegmentState<Snapshot> {
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
}
